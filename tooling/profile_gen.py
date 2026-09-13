#!/usr/bin/env python3
"""
Generates wxWabbitemu profiler regions.txt from source markers and a .map file.

Markers:
  Assembly (*.asm, *.inc):
    ;#[PROFILE_ROUTINE]
    label:

    ;#[PROFILE_START <name>]
    start_label:
    ...
    ;#[PROFILE_STOP <name>]
    end_label:

  C (*.c, *.h):
    //#[PROFILE_ROUTINE]
    void func() {}

Usage:
    python profile_gen.py --list
    python profile_gen.py --regions
    python profile_gen.py --gen-regions [--map out.map] [--output regions.txt]
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = PROJECT_ROOT / "app"
if not APP_ROOT.exists():
    APP_ROOT = Path(__file__).resolve().parent
    if (APP_ROOT / "out.map").exists():
        pass
    else:
        APP_ROOT = PROJECT_ROOT

SRC_SUFFIXES = {".asm", ".inc", ".c", ".h"}
MARKER_NEEDLE = "#[PROFILE_"

ROUTINE_MARKER = re.compile(r"#\[PROFILE_ROUTINE\]")
START_MARKER = re.compile(r"#\[PROFILE_START\s+(\w+)\]")
STOP_MARKER = re.compile(r"#\[PROFILE_STOP\s+(\w+)\]")
FUNC_RE = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
CONTROL_KW = {"if", "for", "while", "switch", "return", "sizeof"}

# RAM page indices seen by the wxWabbitemu profiler at runtime.
# TI names RAM pages with bit7 set ($83 at $8000, $81 at $C000), but the
# emulator stores the masked index in bank->page (see 83psehw.c port5/port7:
# change_page(cpu, bank, (bus & 0x7F) % ram_pages, ...)) and the profiler
# matches RAM points by exact bank->page (see profiler/profiler.c:
# current_point/point_matches). So $83 -> 3 at $8000, $81 (written as 1
# to port 5) -> 1 at $C000. These must agree with core/ram_manager.asm:init_ram.
RAM_PAGE_8000 = 3
RAM_PAGE_C000 = 1

@dataclass
class Region:
    kind: str
    name: str
    start_label: str
    end_label: str | None
    file: Path
    line: int
    start_line: int
    end_line: int | None
    is_c: bool = False

def split_comment_asm(text: str) -> tuple[str, str]:
    quote: str | None = None
    escaped = False
    for i, ch in enumerate(text):
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == ";":
            return text[:i], text[i:]
    return text, ""

def get_files() -> list[Path]:
    return sorted(
        p for p in APP_ROOT.rglob("*")
        if p.is_file()
        and p.suffix.lower() in SRC_SUFFIXES
        and "objects" not in p.parts
        and MARKER_NEEDLE in p.read_text(errors="replace")
    )

def next_label(path: Path, lines: list[str], idx: int, kind: str, allow_marker_skip: bool = False) -> tuple[str, int]:
    for j in range(idx + 1, len(lines)):
        nxt = lines[j]
        if not nxt.strip():
            continue
        code, _ = split_comment_asm(nxt)
        stripped = code.strip()
        if not stripped:
            if MARKER_NEEDLE in nxt and allow_marker_skip:
                continue
            if MARKER_NEEDLE in nxt:
                break
            continue
        m = re.match(r"^\s*([A-Za-z_.$@][A-Za-z0-9_.$@]*)\s*:", stripped)
        if m:
            return m.group(1), j + 1
        if MARKER_NEEDLE in nxt:
            break
        raise SystemExit(f"{path}:{idx+1}: {kind} requires a label immediately after (found '{stripped}')")
    raise SystemExit(f"{path}:{idx+1}: {kind} requires a label immediately after")

def parse_file(path: Path) -> list[Region]:
    lines = path.read_text(errors="replace").splitlines()
    regions: list[Region] = []
    pending: dict[str, tuple[str, int, int]] = {}
    for idx, line in enumerate(lines):
        if ROUTINE_MARKER.search(line):
            if path.suffix.lower() in (".asm", ".inc"):
                label, lline = next_label(path, lines, idx, "#[PROFILE_ROUTINE]")
                regions.append(Region("start-ret", label, label, None, path, idx + 1, lline, None, False))
            else:
                found: str | None = None
                for j in range(idx + 1, len(lines)):
                    nxt = lines[j]
                    if not nxt.strip():
                        continue
                    stripped = nxt.strip()
                    if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
                        continue
                    code = nxt.split("//")[0]
                    m = FUNC_RE.search(code)
                    if m:
                        name = m.group(1)
                        if name in CONTROL_KW:
                            continue
                        found = name
                        break
                    if j - idx > 8:
                        break
                    if MARKER_NEEDLE in nxt and j != idx:
                        break
                if not found:
                    raise SystemExit(f"{path}:{idx+1}: #[PROFILE_ROUTINE] requires a function definition immediately after")
                regions.append(Region("start-ret", found, found, None, path, idx + 1, idx + 1, None, True))
        elif START_MARKER.search(line):
            m = START_MARKER.search(line)
            assert m
            name = m.group(1)
            if name in pending:
                raise SystemExit(f"{path}:{idx+1}: duplicate PROFILE_START {name} without STOP")
            label, lline = next_label(path, lines, idx, f"#[PROFILE_START {name}]")
            pending[name] = (label, lline, idx + 1)
        elif STOP_MARKER.search(line):
            m = STOP_MARKER.search(line)
            assert m
            name = m.group(1)
            if name not in pending:
                raise SystemExit(f"{path}:{idx+1}: #[PROFILE_STOP {name}] without matching PROFILE_START")
            start_label, start_lline, _ = pending.pop(name)
            label, lline = next_label(path, lines, idx, f"#[PROFILE_STOP {name}]", allow_marker_skip=True)
            regions.append(Region("start-end", name, start_label, label, path, idx + 1, start_lline, lline, False))
    if pending:
        names = ", ".join(pending.keys())
        raise SystemExit(f"{path}: unclosed PROFILE_START for: {names}")
    return regions

def collect_regions() -> list[Region]:
    all_regions: list[Region] = []
    seen: dict[str, Region] = {}
    for f in get_files():
        regs = parse_file(f)
        for r in regs:
            if r.name in seen:
                raise SystemExit(f"duplicate region name '{r.name}' in {r.file}:{r.line} and {seen[r.name].file}:{seen[r.name].line}")
            seen[r.name] = r
            all_regions.append(r)
    return all_regions

def parse_map(map_path: Path) -> dict[str, list[tuple[int, str, int]]]:
    text = map_path.read_text(errors="replace")
    out: dict[str, list[tuple[int, str, int]]] = {}
    pat = re.compile(r"^\s*(\S+)\s*=\s*\$(?P<val>[0-9A-Fa-f]+)\s*;\s*(?P<kind>\w+),\s*(?P<scope>\w+),\s*,\s*(?P<module>[^,]*),\s*(?P<section>[^,]*),\s*(?P<file>.*)$")
    for line in text.splitlines():
        m = pat.match(line)
        if not m:
            continue
        kind = m.group("kind")
        if kind not in ("addr", "const"):
            continue
        val = int(m.group("val"), 16)
        if val < 0x4000:
            continue
        name = m.group(1)
        fileinfo = m.group("file").strip()
        module = m.group("module").strip()
        key_file = fileinfo if fileinfo else module
        line_no = 0
        if ":" in key_file:
            try:
                line_no = int(key_file.rsplit(":", 1)[1])
            except ValueError:
                line_no = 0
        out.setdefault(name, []).append((val, key_file, line_no))
    return out

def resolve_symbol(symbol: str, source: Path, label_line: int, map_dict: dict[str, list[tuple[int, str, int]]], is_c: bool) -> int:
    candidates: list[tuple[int, str, int]] | None = None
    key = None
    if is_c:
        for cand in (f"_{symbol}", symbol):
            if cand in map_dict:
                candidates = map_dict[cand]
                key = cand
                break
    else:
        if symbol in map_dict:
            candidates = map_dict[symbol]
            key = symbol
        else:
            base = symbol.lstrip("@")
            matches: list[tuple[int, str, int]] = []
            for k, v in map_dict.items():
                if k == symbol or k.endswith("@" + base) or k.split("@")[-1] == base:
                    matches.extend(v)
            if matches:
                candidates = matches
                key = symbol
    if not candidates:
        raise SystemExit(f"cannot resolve symbol '{symbol}' from {source}:{label_line} in map (no entry for '{symbol}')")
    if len(candidates) == 1:
        return candidates[0][0]
    addrs = {a for a, _, _ in candidates}
    if len(addrs) == 1:
        return candidates[0][0]
    src_str = str(source.relative_to(APP_ROOT)) if source.is_relative_to(APP_ROOT) else str(source)
    src_name = source.name
    filtered = [c for c in candidates if src_name in c[1] or src_str in c[1]]
    if not filtered:
        filtered = candidates
    if len(filtered) == 1:
        return filtered[0][0]
    filtered_addrs = {a for a, _, _ in filtered}
    if len(filtered_addrs) == 1:
        return filtered[0][0]
    best = min(filtered, key=lambda c: abs(c[2] - label_line) if c[2] else 1_000_000)
    others = [c for c in filtered if c[0] != best[0] and abs(c[2] - label_line) == abs(best[2] - label_line)]
    if others:
        raise SystemExit(f"ambiguous symbol '{symbol}' from {source}:{label_line}: {candidates}")
    return best[0]

def addr_to_point(addr: int) -> str:
    if addr >= 0xC000:
        off = addr & 0x3FFF
        return f"ram:{RAM_PAGE_C000}:0x{off:04X}"
    if addr >= 0x8000:
        off = addr & 0x3FFF
        return f"ram:{RAM_PAGE_8000}:0x{off:04X}"
    off = addr & 0x3FFF
    return f"flash:0:0x{off:04X}"

def emit_regions(regions: list[Region], map_dict: dict[str, list[tuple[int, str, int]]]) -> str:
    from itertools import groupby
    out = "# AUTOGENERATED FILE! Do not edit!\n"
    out += "# wxWabbitemu profiler regions - generated from .map\n"
    out += "# See tooling/profile_gen.py\n\n"
    sorted_regions = sorted(regions, key=lambda r: (str(r.file.relative_to(APP_ROOT)) if r.file.is_relative_to(APP_ROOT) else str(r.file), r.start_line))
    for file_key, group in groupby(sorted_regions, key=lambda r: str(r.file.relative_to(APP_ROOT)) if r.file.is_relative_to(APP_ROOT) else str(r.file)):
        out += f"# {file_key}\n"
        for r in group:
            if r.kind == "start-ret":
                addr = resolve_symbol(r.start_label, r.file, r.start_line, map_dict, r.is_c)
                point = addr_to_point(addr)
                out += f"start-ret {r.name} {point}\n"
            else:
                assert r.end_label is not None and r.end_line is not None
                saddr = resolve_symbol(r.start_label, r.file, r.start_line, map_dict, False)
                eaddr = resolve_symbol(r.end_label, r.file, r.end_line, map_dict, False)
                spoint = addr_to_point(saddr)
                epoint = addr_to_point(eaddr)
                out += f"start-end {r.name} {spoint} {epoint}\n"
        out += "\n"
    return out.rstrip() + "\n"

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=APP_ROOT / "out.map", help="path to .map file")
    parser.add_argument("--output", type=Path, help="output file (default stdout)")
    sub = parser.add_argument_group("modes")
    sub.add_argument("--list", action="store_true", help="list files containing profile markers")
    sub.add_argument("--regions", action="store_true", help="debug print parsed regions")
    sub.add_argument("--gen-regions", action="store_true", help="generate regions.txt (default)")
    args = parser.parse_args()

    if args.list:
        files = get_files()
        print(" ".join(str(p.relative_to(APP_ROOT)) for p in files))
        return

    if args.regions:
        for r in collect_regions():
            if r.kind == "start-ret":
                print(f"{r.kind} {r.name} -> {r.start_label}:{r.start_line}  ({r.file.relative_to(APP_ROOT)}:{r.line})")
            else:
                print(f"{r.kind} {r.name} {r.start_label}:{r.start_line}->{r.end_label}:{r.end_line}  ({r.file.relative_to(APP_ROOT)}:{r.line})")
        return

    regions = collect_regions()
    if not regions:
        sys.stderr.write("no PROFILE markers found\n")
        raise SystemExit(1)

    map_path: Path = args.map
    if not map_path.is_absolute():
        cand = APP_ROOT / map_path
        if cand.exists():
            map_path = cand
        else:
            cand2 = PROJECT_ROOT / map_path
            if cand2.exists():
                map_path = cand2
    if not map_path.exists():
        sys.stderr.write(f"map file not found: {map_path}\n")
        raise SystemExit(1)

    map_dict = parse_map(map_path)
    text = emit_regions(regions, map_dict)
    if args.output:
        args.output.write_text(text)
    else:
        sys.stdout.write(text)

if __name__ == "__main__":
    main()
