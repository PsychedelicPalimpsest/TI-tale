#!/usr/bin/env python3
"""
Generates assembly structure offsets from C structs marked //#[ASM_EXPOSED].

For each exposed struct, the offsets of all of its fields are computed
natively by z88dk: sccz80 constant-folds offsetof() into defw directives,
so z88dk's 16-bit word/pointer sizes are always respected. No desktop
compiler is involved.

Usage:
    python struct_to_asm.py --list     -> prints the files that contain markers
    python struct_to_asm.py --structs  -> debug print of the parsed structs
    python struct_to_asm.py --gen-inc  -> prints the generated .inc equates
"""
import re
import sys
import hashlib
import tempfile
from pathlib import Path
from subprocess import run

APP_ROOT = Path(__file__).resolve().parent
MARKER = "//#[ASM_EXPOSED]"
ZCC = "zcc"
TARGET = "+ti83p"

SRC_SUFFIXES = {".c", ".h"}

try:
    from pycparser import c_ast
except ImportError:
    c_ast = None


def get_files():
    """All source files under the app root containing an ASM_EXPOSED marker."""
    return sorted(
        p
        for p in APP_ROOT.rglob("*")
        if p.is_file()
        and p.suffix in SRC_SUFFIXES
        and "objects" not in p.parts
        and p.name != "struct_to_asm.py"
        and MARKER in p.read_text(errors="replace")
    )


def get_marker_lines(path):
    lines = path.read_text(errors="replace").splitlines()
    return [i + 1 for i, line in enumerate(lines) if MARKER in line]


def _struct_of(decl_type):
    while isinstance(decl_type, (c_ast.TypeDecl, c_ast.PtrDecl, c_ast.ArrayDecl)):
        decl_type = decl_type.type
    return decl_type if isinstance(decl_type, (c_ast.Struct, c_ast.Union)) else None


def _pycparser_structs(path, marker_lines):
    from pycparser import parse_file

    ast = parse_file(
        str(path),
        use_cpp=True,
        cpp_args=[
            "-E",
            f"-I{APP_ROOT}",
            "-D__attribute__(x)=",
            "-D__asm(x)=",
            "-D__inline=",
            "-D__extension__=",
        ],
    )

    candidates = []
    for node in ast.ext:
        struct = (
            _struct_of(node.type)
            if isinstance(node, (c_ast.Decl, c_ast.Typedef))
            else None
        )
        if struct is None:
            continue
        name = struct.name
        if isinstance(node, c_ast.Typedef):
            name = node.name
        if not name:
            continue
        fields = [d.name for d in struct.decls] if struct.decls else []
        candidates.append((node.coord.line, name, fields))

    matched = []
    for mline in marker_lines:
        best = min(
            (c for c in candidates if c[0] >= mline),
            default=None,
            key=lambda c: c[0],
        )
        if best and best[1]:
            matched.append((path, best[1], best[2]))
    return matched


def _field_names(inner):
    """Extract field names from the raw body of a struct declaration."""
    inner = re.sub(r"/\*.*?\*/", "", inner, flags=re.S)
    inner = re.sub(r"//[^\n]*", "", inner)

    names = []
    for decl in inner.split(";"):
        decl = decl.strip()
        if not decl:
            continue
        while re.search(r"\([^()]*\)", decl):
            decl = re.sub(r"\([^()]*\)", "", decl)
        decl = re.sub(r"\[[^\]]*\]", "", decl)
        ids = re.findall(r"[A-Za-z_]\w*", decl)
        if ids:
            names.append(ids[-1])
    return names


def _fallback_structs(path, marker_lines):
    text = path.read_text(errors="replace")
    lines = text.splitlines()

    matched = []
    for mline in marker_lines:
        body = "\n".join(lines[mline:])
        m = re.search(r"typedef\s+(?:struct|union)\b", body)
        if not m:
            continue
        open_idx = body.find("{", m.end())
        if open_idx == -1:
            continue
        depth, i = 1, open_idx + 1
        while depth and i < len(body):
            if body[i] == "{":
                depth += 1
            elif body[i] == "}":
                depth -= 1
            i += 1
        if depth:
            continue
        close_idx = i - 1

        name_m = re.match(r"\s*(\w+)\s*;", body[close_idx + 1 :])
        if not name_m:
            continue
        matched.append(
            (path, name_m.group(1), _field_names(body[open_idx + 1 : close_idx]))
        )
    return matched


def parse_structs(path, marker_lines):
    try:
        return _pycparser_structs(path, marker_lines)
    except Exception as e:
        sys.stderr.write(
            f"struct_to_asm.py: pycparser failed on {path.name} ({e}), "
            "falling back to a lightweight parser\n"
        )
        return _fallback_structs(path, marker_lines)


def generate_offsets(parsed):
    """Compile offsetof()/sizeof() through z88dk and return sym -> value."""
    c_lines = ["#include <stddef.h>", "#include <stdint.h>"]
    expected = {}
    for path in {p for p, _, _ in parsed}:
        c_lines.append(f'#include "{path.relative_to(APP_ROOT)}"')
    for path, struct, fields in parsed:
        tag = hashlib.md5(str(path).encode()).hexdigest()[:8]
        for field in fields:
            sym = f"zoff_{tag}_{struct}_{field}"
            c_lines.append(f"const uint16_t {sym} = offsetof({struct}, {field});")
            expected[sym] = (path, struct, field)
        sym = f"zoff_{tag}_{struct}_size"
        c_lines.append(f"const uint16_t {sym} = sizeof({struct});")
        expected[sym] = (path, struct, None)

    with tempfile.TemporaryDirectory() as td:
        cfile = Path(td) / "offsets.c"
        asmfile = Path(td) / "offsets.asm"
        cfile.write_text("\n".join(c_lines) + "\n")

        proc = run(
            [ZCC, TARGET, "-c", "-a", f"-I{APP_ROOT}", str(cfile), "-o", str(asmfile)],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            sys.stderr.write(f"zcc failed:\n{proc.stdout}\n{proc.stderr}\n")
            raise SystemExit(1)

        values = {}
        cur = None
        for line in asmfile.read_text(errors="replace").splitlines():
            line = line.strip()
            m = re.match(r"^\.(_zoff_\w+)\s*:?$", line)
            if m:
                cur = m.group(1)
                continue
            if cur and line.startswith("defw"):
                nums = re.findall(r"-?\d+", line)
                if nums:
                    values[cur.lstrip("_")] = int(nums[0])
                cur = None

    missing = set(expected) - set(values)
    if missing:
        sys.stderr.write(
            "struct_to_asm.py: zcc did not produce offsets for: "
            + ", ".join(sorted(missing))
            + "\n"
        )
        raise SystemExit(1)
    return values


def emit_inc(parsed, values):
    out = "; AUTOGENERATED FILE! Do not edit!\n"
    out += "IFNDEF STRUCT_OFFSETS_INC\n"
    out += "DEFINE STRUCT_OFFSETS_INC\n"

    used = {}
    for path, struct, fields in parsed:
        out += f"\n; {struct} from {path.relative_to(APP_ROOT)}\n"
        for field in fields:
            sym = f"zoff_{hashlib.md5(str(path).encode()).hexdigest()[:8]}_{struct}_{field}"
            name = f"{struct}_{field}"
            assert name not in used, f"duplicate offset name {name}"
            used[name] = True
            out += f"DEFC {name} = {values[sym]}\n"
        sym = f"zoff_{hashlib.md5(str(path).encode()).hexdigest()[:8]}_{struct}_size"
        name = f"{struct}_size"
        assert name not in used, f"duplicate offset name {name}"
        used[name] = True
        out += f"DEFC {name} = {values[sym]}\n"

    out += "\nENDIF\n"
    return out


def main():
    files = get_files()
    mode = sys.argv[1] if len(sys.argv) > 1 else "--gen-inc"

    if mode == "--list":
        print(" ".join(str(p.relative_to(APP_ROOT)) for p in files))
        return

    parsed = []
    for path in files:
        parsed.extend(parse_structs(path, get_marker_lines(path)))

    if mode == "--structs":
        for path, struct, fields in parsed:
            print(f"{struct}: {', '.join(fields)} (from {path.relative_to(APP_ROOT)})")
        return

    if mode != "--gen-inc":
        sys.stderr.write(f"unknown mode: {mode}\n")
        raise SystemExit(1)

    if not parsed:
        sys.stderr.write("no ASM_EXPOSED structs found\n")
        raise SystemExit(1)

    values = generate_offsets(parsed)
    print(emit_inc(parsed, values), end="")


if __name__ == "__main__":
    main()