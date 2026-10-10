# Gamemaker bundle system:
# * We break the data into two types:
#   * Transient objects: Things like objects, sprites, scripts that are used in many
#                        rooms. These may be put into any/all pages. They do not care
#                        where they are
#   * Local objects: Rooms, they live in a set page.
#
# * All local objects know that they use, and dependency graphs are resolved during compilation
#   to ensure rooms have all their objects on-page.
#    * HACK: When objects are 'persistant', we add a rom-page shim to all the events,
#             these are rare enough a few dozen cycles is worth it.
# * Stages of compilation:
#   * Transient object compilation: Compile objects and sprites
#   * Local object compilation: Rooms get compiled, with all the dependencies attached
#
#
# Sprite compilation notes (SEE: engine/engine.h, engine/resident/installed/sprite_system.asm):
# * We generate sprite *cache entries* directly, including the 8 pre-rotated
#   frames, so the runtime `new_sprite_cache_entry3x` / `build_cache3x` work
#   does not need to run on-calc.
# * Cache entry layout (must match `Sprite` in engine.h and the header comment
#   + `_new_sprite_cache_entry` in sprite_system.asm):
#     +00h 1 flags (0 = not displayed)
#     +01h 2 x_pos (0)
#     +03h 1 width_cols (cache cols, see below)
#     +04h 2 width_px (width_cols * 8, LE)
#     +06h 2 y_pos (0)
#     +08h 1 height_px
#     +09h 8 rl_entry (Renderlist_Entry, zeroed)
#     +11h 16 rotation_entries[8] (word ptrs to each frame)
#     +21h var cache_data: 8 frames of (width_cols * height * 3) bytes
#   Header size is 33 bytes (Sprite_sprite_data in struct_offsets.inc).
#   Each frame is col-major: for each col, for each row: mask, light, dark.
#   That byte order is what `norot3x2_blit` consumes (mask, light, dark).
# * Rotation: frame r (0..7) is the base image shifted right by r pixels with
#   zero fill on the left, bit7 = leftmost pixel (matches the RRA carry chain
#   in `build_cache_rejoin` / `_do_col`). Each of the 3 planes
#   (mask/light/dark) shifts independently per row; carry goes from bit0 of
#   col c to bit7 of col c+1 for the same row+plane.
# * Extra col: like `build_cache3x`, the cache is extended to hold the rotation
#   carry-out. Rotation needs 7 extra pixels (max shift 7), so
#   cache_cols = ceil((width + 7) / 8). That is disk_cols + 1, except for the
#   special case width % 8 == 1 where (width + 7) lands exactly on a col
#   boundary and cache_cols == disk_cols (we save a col).
# * Palette: every opaque pixel MUST be exactly one of the colors in
#   ti-img-pallette.gpl (compared by RGB). The only other allowed color is
#   pure black (0,0,0) which means transparent (mask bit 0).

import sys
import json
import os
import re
import shlex
import struct
from os.path import join, abspath, dirname, basename, splitext, getmtime, exists
from os import walk
import multiprocessing, subprocess, time

CORE_COUNT = None  # Set to a number to override

GAME_DIR = join(dirname(abspath(__file__)), "game")
APP_DIR = dirname(abspath(__file__))
REPO_ROOT = dirname(APP_DIR)
GPL_PATH = join(REPO_ROOT, "ti-img-pallette.gpl")
TRANSIENT_TYPES = [
    "objects", "sprites"
]


# Just the events we support
VALID_EVENTS = [
    "create",
    "begin_step",
    "step",
    "end_step",
    "draw",
    "pre_draw",
    "post_draw",
    "draw_begin",
    "draw_end",
    "draw_gui"
] + [f"user{n}"  for n in range(16)] + [f"alarm{n}" for n in range(12)]

VALID_EVENTSs = set(VALID_EVENTS)


# Must match engine.h Sprite layout (see struct_offsets.inc).
SPRITE_HEADER_SIZE = 33
SPRITE_RL_SIZE = 8
SPRITE_NROTS = 8
SPRITE_PLANES_PER_ROW = 3  # mask, light, dark



def _env_flags(var):
    """Split extra compiler flags from env var (e.g. CFLAGS/ASMFLAGS)."""
    raw = os.environ.get(var, "")
    if not raw or not raw.strip():
        return []
    try:
        return shlex.split(raw)
    except ValueError as e:
        sys.stderr.write(f"warning: could not parse ${var}={raw!r}: {e}\n")
        return []


def _compile_transient_asm(path):
    return [
        "z88dk-z80asm",
        *_env_flags("ASMFLAGS"),
        path,
    ]

def _compile_object_c(path):
    return [
        "zcc","+ti83p", "-c",
        *_env_flags("CFLAGS"),
        path,
    ]

def _compile_room_c(path):
    return [
        "zcc","+ti83p", "-c",
        *_env_flags("CFLAGS"),
        path,
    ]

class SpriteCompileError(Exception):
    pass


def get_transients(dirs=None):
    ret = []
    for ttype in dirs or TRANSIENT_TYPES:
        for (dirpath, _, files) in walk(join(GAME_DIR, ttype)):
            ret += [join(dirpath, f) for f in files if f.endswith(".json")]
    return sorted(ret)


def list_transients():
    print(", ".join(get_transients()))


def _compile(command_gen):
    nproc = CORE_COUNT or multiprocessing.cpu_count()
    procs = []
    exhausted = False
    failed = False

    while procs or (not exhausted and not failed):
        for proc in procs[:]:
            status = proc.poll()
            if status is not None:
                procs.remove(proc)
                if status != 0:
                    print(f"error: command exited with status {status}", file=sys.stderr)
                    failed = True

        while not failed and not exhausted and len(procs) < nproc:
            try:
                cmd = next(command_gen)
            except StopIteration:
                exhausted = True
                break
            print("$", "  ".join(cmd))
            procs.append(subprocess.Popen(cmd, cwd=APP_DIR))

        if procs:
            time.sleep(0.1)

    if failed:
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# Palette (ti-img-pallette.gpl)
# ---------------------------------------------------------------------------

def _norm_color_name(name):
    return name.strip().lower().replace("_", "-").replace(" ", "-")


# Maps normalized GPL color names to (light_bit, dark_bit).
# Matches the greyscale meaning: white=(0,0), light=(1,0), dark=(0,1),
# black=(1,1). See greyscale_swap.asm PIXEL_BASE: L=1,D=0 is 1/3 on (light),
# L=0,D=1 is 2/3 on (dark).
GREY_BITS_BY_NAME = {
    "white": (0, 0),
    "light-grey": (1, 0),
    "light-gray": (1, 0),
    "lightgrey": (1, 0),
    "lightgray": (1, 0),
    "dark-grey": (0, 1),
    "dark-gray": (0, 1),
    "darkgrey": (0, 1),
    "darkgray": (0, 1),
    "black": (1, 1),
}

TRANSPARENT_RGB = (0, 0, 0)


def parse_gpl(gpl_path=GPL_PATH):
    """Parse ti-img-pallette.gpl.

    Returns dict RGB tuple -> (mask, light, dark, name).
    Raises SpriteCompileError if the 4 required greys are missing.
    """
    try:
        text = open(gpl_path, "r").read()
    except OSError as e:
        raise SpriteCompileError(f"could not read palette {gpl_path}: {e}")
    rgb_by_name = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("GIMP") or line.startswith("Name:"):
            continue
        if line.startswith("Columns:") or line.startswith("#"):
            continue
        m = re.match(r"(\d+)\s+(\d+)\s+(\d+)\s+(.+)", line)
        if not m:
            continue
        r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
        name = m.group(4).strip()
        rgb_by_name[_norm_color_name(name)] = ((r, g, b), name)
    palette = {}
    for want, bits in GREY_BITS_BY_NAME.items():
        # Only require the canonical hyphenated names; aliases resolve above
        # if the file uses "gray" spellings.
        if want in ("lightgrey", "lightgray", "darkgrey", "darkgray",
                    "light-gray", "dark-gray"):
            continue
        if want not in rgb_by_name:
            raise SpriteCompileError(
                f"palette {gpl_path} is missing required color '{want}'; "
                f"found: {sorted(rgb_by_name)}")
        rgb, orig = rgb_by_name[want]
        if rgb == TRANSPARENT_RGB:
            raise SpriteCompileError(
                f"palette {gpl_path}: color '{orig}' must not be (0,0,0); "
                "that RGB is reserved for transparency")
        light, dark = bits
        if rgb in palette:
            raise SpriteCompileError(
                f"palette {gpl_path}: duplicate RGB {rgb}")
        palette[rgb] = (1, light, dark, orig)
    return palette


# ---------------------------------------------------------------------------
# Sprite geometry
# ---------------------------------------------------------------------------

def cache_dims(width_px):
    """Return (disk_cols, cache_cols) for a sprite width in pixels.

    disk_cols  = ceil(width / 8)      (how the PNG packs)
    cache_cols = ceil((width + 7) / 8) (room for rotation shifts 0..7)

    Normally cache_cols == disk_cols + 1, but when width % 8 == 1 the
    +7 pixels fit exactly and cache_cols == disk_cols (save a col).
    """
    if width_px <= 0:
        raise SpriteCompileError(f"invalid sprite width {width_px}")
    disk_cols = (width_px + 7) // 8
    cache_cols = (width_px + 14) // 8
    return disk_cols, cache_cols


def sanitize_label(name):
    """Make a string safe for use as a z80asm label."""
    s = re.sub(r"[^A-Za-z0-9_]", "_", name)
    if not s or s[0].isdigit():
        s = "spr_" + s
    return s


# ---------------------------------------------------------------------------
# PNG -> planes
# ---------------------------------------------------------------------------

def _pil_image_rgba(png_path):
    try:
        from PIL import Image
    except ImportError:
        raise SpriteCompileError(
            "Pillow is required for sprite compilation "
            "(pip install pillow)")
    try:
        im = Image.open(png_path)
    except OSError as e:
        raise SpriteCompileError(f"could not open {png_path}: {e}")
    w, h = im.size
    if w <= 0 or h <= 0:
        raise SpriteCompileError(f"{png_path}: invalid size {w}x{h}")
    # Preserve transparency info: RGBA/LA/TIFF transparency or P-mode tRNS.
    has_alpha = im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info
    if has_alpha:
        rgba = im.convert("RGBA")
        px = rgba.load()
        get = lambda x, y: px[x, y]
        alpha_mode = True
    else:
        rgb = im.convert("RGB")
        px = rgb.load()
        get = lambda x, y: px[x, y]
        alpha_mode = False
    return w, h, get, alpha_mode


def png_to_planes(png_path, palette):
    """Load a PNG frame, enforcing ti-img-pallette.gpl.

    Returns (w, h, mask_rows, light_rows, dark_rows) where each is a list of
    h rows, each a list of w bits (0/1). mask=0 means transparent.
    """
    w, h, get, alpha_mode = _pil_image_rgba(png_path)
    mask_rows = [[0] * w for _ in range(h)]
    light_rows = [[0] * w for _ in range(h)]
    dark_rows = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            pix = get(x, y)
            if alpha_mode:
                r, g, b, a = pix
                if a < 128:
                    continue  # transparent
                rgb = (r, g, b)
            else:
                rgb = (pix[0], pix[1], pix[2])
            if rgb == TRANSPARENT_RGB:
                continue  # transparent (mask 0)
            if rgb not in palette:
                allowed = sorted(palette) + [TRANSPARENT_RGB]
                raise SpriteCompileError(
                    f"{png_path} pixel ({x},{y}) has RGB {rgb} which is not "
                    f"in {GPL_PATH}; allowed RGBs (plus (0,0,0) transparent): "
                    f"{allowed}")
            mask, light, dark, _name = palette[rgb]
            mask_rows[y][x] = mask
            light_rows[y][x] = light
            dark_rows[y][x] = dark
    return w, h, mask_rows, light_rows, dark_rows


# ---------------------------------------------------------------------------
# Rotation cache generation
# ---------------------------------------------------------------------------

def build_rotation_frames(w, h, mask_rows, light_rows, dark_rows):
    """Build the 8 rotation frames for one sprite image.

    Returns (cache_cols, frames) where frames[r] is bytes of length
    cache_cols * h * 3 in col-major mask/light/dark order, matching what
    build_cache3x leaves in memory (rot0 = zero-extended base, rot r =
    base shifted right by r with zero fill).
    """
    _disk, cache_cols = cache_dims(w)
    plane_rows = [mask_rows, light_rows, dark_rows]
    full_w = cache_cols * 8
    # base[y][p][x] for x in 0..full_w-1 (padding zeros past w)
    base = []
    for y in range(h):
        brow = []
        for p in range(3):
            bits = [0] * full_w
            src = plane_rows[p][y]
            for x in range(w):
                bits[x] = 1 if src[x] else 0
            brow.append(bits)
        base.append(brow)
    frames = []
    for r in range(SPRITE_NROTS):
        buf = bytearray()
        for c in range(cache_cols):
            for y in range(h):
                for p in range(3):
                    byte = 0
                    for b in range(8):
                        x = c * 8 + b
                        bit = base[y][p][x - r] if x >= r else 0
                        if bit:
                            byte |= 1 << (7 - b)
                    buf.append(byte)
        frames.append(bytes(buf))
    return cache_cols, frames


def per_frame_size(cache_cols, height_px):
    return cache_cols * height_px * SPRITE_PLANES_PER_ROW


def build_cache_entry_bytes(cache_cols, height_px, frames):
    """Pack one cache entry (header + ptr table + 8 frames) as bytes.

    Pointers are file offsets from the entry start (header is 33 bytes),
    suitable for tests. Use emit_sprite_asm() for linkable assembly where
    the pointers are real labels.
    """
    if len(frames) != SPRITE_NROTS:
        raise SpriteCompileError(
            f"expected {SPRITE_NROTS} rotation frames, got {len(frames)}")
    psize = per_frame_size(cache_cols, height_px)
    for f in frames:
        if len(f) != psize:
            raise SpriteCompileError(
                f"frame size {len(f)} != {psize} "
                f"(cols={cache_cols} height={height_px})")
    width_px = cache_cols * 8
    header = struct.pack("<B", 0)            # flags
    header += struct.pack("<H", 0)           # x_pos
    header += struct.pack("<B", cache_cols)  # width_cols
    header += struct.pack("<H", width_px)    # width_px
    header += struct.pack("<H", 0)           # y_pos
    header += struct.pack("<B", height_px)   # height
    header += bytes(SPRITE_RL_SIZE)          # rl_entry (zeroed)
    assert len(header) == SPRITE_HEADER_SIZE - 16
    table = b""
    for i in range(SPRITE_NROTS):
        table += struct.pack("<H", SPRITE_HEADER_SIZE + i * psize)
    return header + table + b"".join(frames)


def cache_entry_total_size(cache_cols, height_px):
    return SPRITE_HEADER_SIZE + SPRITE_NROTS * per_frame_size(
        cache_cols, height_px)


# ---------------------------------------------------------------------------
# Assembly emission
# ---------------------------------------------------------------------------

def _db_lines(data, per_line=16):
    lines = []
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        lines.append("    DEFB " + ", ".join(f"0x{b:02X}" for b in chunk))
    if not lines:
        lines.append("    DEFB 0x00 ; empty")
    return lines


def emit_sprite_asm(sprite_id, frames_info):
    """Render one .asm file for a sprite JSON.

    frames_info: list of (frame_index, w, h, cache_cols, frames) tuples.
    Returns asm text using SECTION rodata with PUBLIC labels.
    """
    sid = sanitize_label(sprite_id)
    out = []
    out.append("; AUTOGENERATED FILE! Do not edit!")
    out.append(f"; Generated by gm_comp.py from {sprite_id}.json")
    out.append("; Layout matches Sprite in engine/engine.h and")
    out.append("; _new_sprite_cache_entry/build_cache3x in")
    out.append("; engine/resident/installed/sprite_system.asm (header 33 bytes,")
    out.append("; 8 rotation frames of cols*height*3 bytes).")
    out.append("    SECTION rodata")
    for (fidx, w, h, cache_cols, frames) in frames_info:
        _disk, expect_cache = cache_dims(w)
        if cache_cols != expect_cache:
            raise SpriteCompileError("cache_cols mismatch")
        base_label = f"_{sid}_{fidx}"
        rot_labels = [f"{base_label}_rot{r}" for r in range(SPRITE_NROTS)]
        saved = " (saved a col: width%8==1)" if cache_cols == _disk else ""
        out.append("")
        out.append(f"; frame {fidx}: {w}x{h} -> cache "
                   f"{cache_cols} cols ({cache_cols * 8}px) x {h}{saved}")
        out.append(f"    PUBLIC {base_label}")
        out.append(f"{base_label}:")
        out.append("    DEFB 0x00 ; flags (not displayed)")
        out.append("    DEFW 0x0000 ; x_pos")
        out.append(f"    DEFB 0x{cache_cols:02X} ; width_cols")
        out.append(f"    DEFW 0x{cache_cols * 8:04X} ; width_px")
        out.append("    DEFW 0x0000 ; y_pos")
        out.append(f"    DEFB 0x{h:02X} ; height")
        out.append("    DEFS 8 ; rl_entry (Renderlist_Entry, zeroed)")
        for rl in rot_labels:
            out.append(f"    DEFW {rl}")
        for r, data in enumerate(frames):
            out.append(f"{rot_labels[r]}:")
            out.extend(_db_lines(data))
    # Convenience table of all frames in index order.
    if frames_info:
        out.append("")
        out.append(f"; Frame pointer table for {sprite_id}")
        table_label = f"_{sid}_frames"
        count_label = f"_{sid}_frame_count"
        out.append(f"    PUBLIC {table_label}")
        out.append(f"{table_label}:")
        for (fidx, _w, _h, _cc, _fr) in frames_info:
            out.append(f"    DEFW _{sid}_{fidx}")
        out.append(f"    DEFC {count_label} = {len(frames_info)}")
        out.append(f"    PUBLIC {count_label}")
    out.append("")
    return "\n".join(out) + "\n"


def emit_sprite_h(sprite_id, frames_info):
    """Render a small C header declaring the generated frames."""
    sid = sanitize_label(sprite_id)
    guard = f"SPR_{sid.upper()}_H"
    out = []
    out.append("// AUTOGENERATED FILE! Do not edit!")
    out.append(f"// Generated by gm_comp.py from {sprite_id}.json")
    out.append(f"#ifndef {guard}")
    out.append(f"#define {guard}")
    out.append("")
    out.append('#include "engine/engine.h"')
    out.append("")
    for (fidx, w, h, cache_cols, _frames) in frames_info:
        out.append(f"// frame {fidx}: source {w}x{h}, "
                   f"cache {cache_cols} cols x {h}")
        out.append(f"extern Sprite {sid}_{fidx};")
    out.append("")
    out.append(f"extern void *{sid}_frames[];")
    out.append(f"// frame count = {len(frames_info)}")
    out.append("")
    out.append(f"#endif // {guard}")
    out.append("")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Sprite JSON compilation
# ---------------------------------------------------------------------------

def sprite_output_paths(json_path):
    base, _ext = splitext(json_path)
    return base + ".asm", base + ".h"


def compile_sprite(json_path, gpl_path=GPL_PATH):
    """Compile one sprite JSON to .asm + .h cache entries.

    Returns (asm_path, h_path). Raises SpriteCompileError on bad input.
    """
    try:
        meta = _load_json(json_path)
    except json.JSONDecodeError as e:
        raise SpriteCompileError(f"{json_path}: invalid JSON: {e}")
    sprite_id = meta.get("id") or splitext(basename(json_path))[0]
    raw_frames = meta.get("frames")
    if not isinstance(raw_frames, list) or not raw_frames:
        raise SpriteCompileError(
            f"{json_path}: 'frames' must be a non-empty list")
    palette = parse_gpl(gpl_path)
    json_dir = dirname(abspath(json_path))
    json_w = meta.get("width")
    json_h = meta.get("height")
    frames_info = []
    seen = set()
    for entry in sorted(raw_frames, key=lambda e: e.get("index", 0)):
        try:
            fidx = int(entry["index"])
        except (KeyError, TypeError, ValueError):
            raise SpriteCompileError(
                f"{json_path}: every frame needs an integer 'index'")
        if fidx in seen:
            raise SpriteCompileError(
                f"{json_path}: duplicate frame index {fidx}")
        seen.add(fidx)
        rel = entry.get("path")
        if not rel:
            raise SpriteCompileError(
                f"{json_path}: frame {fidx} is missing 'path'")
        png_path = join(json_dir, rel)
        if not exists(png_path):
            raise SpriteCompileError(
                f"{json_path}: frame {fidx} not found: {png_path}")
        w, h, masks, lights, darks = png_to_planes(png_path, palette)
        if json_w is not None and w != json_w:
            sys.stderr.write(
                f"warning: {json_path} frame {fidx} width {w} != "
                f"json width {json_w}; using PNG size\n")
        if json_h is not None and h != json_h:
            sys.stderr.write(
                f"warning: {json_path} frame {fidx} height {h} != "
                f"json height {json_h}; using PNG size\n")
        cache_cols, frames = build_rotation_frames(w, h, masks, lights, darks)
        frames_info.append((fidx, w, h, cache_cols, frames))
    asm_text = emit_sprite_asm(sprite_id, frames_info)
    h_text = emit_sprite_h(sprite_id, frames_info)
    asm_path, h_path = sprite_output_paths(json_path)
    with open(asm_path, "w") as f:
        f.write(asm_text)
    with open(h_path, "w") as f:
        f.write(h_text)
    return asm_path, h_path


def _load_json(path):
    """Load JSON, tolerating trailing commas in arrays/objects."""
    with open(path, "r") as f:
        text = f.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Strip trailing commas: ", }" -> "}", ", ]" -> "]"
        cleaned = re.sub(r",\s*([\}\]])", r"\1", text)
        return json.loads(cleaned)


def sprite_frame_pngs(json_path):
    """List the PNG files referenced by a sprite JSON (for mtime checks)."""
    try:
        meta = _load_json(json_path)
    except (OSError, json.JSONDecodeError):
        return []
    json_dir = dirname(abspath(json_path))
    out = []
    for entry in meta.get("frames", []) or []:
        rel = entry.get("path")
        if rel:
            out.append(join(json_dir, rel))
    return out



# ---------------------------------------------------------------------------
# Object compilation
# ---------------------------------------------------------------------------


def object_paths(json_path):
    base, _ext = splitext(json_path)
    return base + ".c", base + ".h"



def sprite_o_path(json_path):
    base, _ext = splitext(json_path)
    return base + ".o"


def object_o_path(json_path):
    base, _ext = splitext(json_path)
    return base + ".o"


def check_sprite_codegen(json_path):
    """True if the generated .asm/.h are newer than inputs.

    Inputs are the JSON, its frame PNGs, and ti-img-pallette.gpl.
    """
    asm_path, h_path = sprite_output_paths(json_path)
    if not exists(asm_path) or not exists(h_path):
        return False
    try:
        out_mtime = min(getmtime(asm_path), getmtime(h_path))
    except OSError:
        return False
    inputs = [json_path, __file__] + sprite_frame_pngs(json_path) + [GPL_PATH]
    for p in inputs:
        try:
            if getmtime(p) > out_mtime:
                return False
        except OSError:
            return False
    return True


def check_sprite_o(json_path):
    """True if the assembled .o exists and is newer than the .asm."""
    asm_path, _h_path = sprite_output_paths(json_path)
    o_path = sprite_o_path(json_path)
    if not exists(o_path):
        return False
    try:
        if getmtime(o_path) < getmtime(asm_path):
            return False
    except OSError:
        return False
    return True


def check_asm_only_compilation(json_path):
    """True if sprites are fully up-to-date (codegen + .o)."""
    return check_sprite_codegen(json_path) and check_sprite_o(json_path)

def get_parent_path(jso):
    if "parent" in jso:
        return join(GAME_DIR, jso["parent"])

def check_object_codegen(path, past=None):
    """True if the generated object .h is newer than its inputs.

    Inputs are the object JSON, its .c file, and (recursively) the
    parent's codegen state.
    """
    past = past or []

    c_file, h_file = object_paths(path)

    if not exists(h_file):
        return False
    try:
        out_mtime = getmtime(h_file)
    except OSError:
        return False

    inputs = [path, c_file, __file__]

    for p in inputs:
        try:
            if getmtime(p) > out_mtime:
                return False
        except OSError:
            return False

    try:
        jso = _load_json(path)
    except (OSError, json.JSONDecodeError, ValueError):
        return False
    if jso.get("sprite"):
        inputs = [join(GAME_DIR, "sprites", jso["sprite"] + suffix)
                  for suffix in (".json", ".h")]
        if any(not exists(p) or getmtime(p) > out_mtime for p in inputs):
            return False

    # Parent codegen out of date forces our codegen out of date
    # (child .h inlines parent event ids).
    parent = get_parent_path(jso)
    if parent is not None and parent not in past and not check_object_codegen(parent, past + [parent]):
        return False

    return True


def check_object_o(path):
    """True if the compiled object .o exists and is newer than .c/.h."""
    c_file, h_file = object_paths(path)
    o_file = object_o_path(path)
    if not exists(o_file):
        return False
    try:
        o_mtime = getmtime(o_file)
        if o_mtime < getmtime(c_file):
            return False
        if o_mtime < getmtime(h_file):
            return False
    except OSError:
        return False
    return True


def check_obj_compilation(path, past=None):
    """True if objects are fully up-to-date (codegen + .o)."""
    past = past or []
    if not check_object_codegen(path, past):
        return False
    if not check_object_o(path):
        return False
    return True


def _all_events(jso, depth=1):
    events = set(jso.get('events', []))
    if depth < 50 and 'parent' in jso:
        try:
            parent_jso = _load_json(get_parent_path(jso))
        except (OSError, json.JSONDecodeError, ValueError):
            return events
        events |= _all_events(parent_jso, depth=depth+1)
    return events


def _compile_object(json_path, jso):
    c_file, h_file = object_paths(json_path)

    parent_path = get_parent_path(jso)
    parent_jso = json.load(open(parent_path)) if parent_path else {}
    oid = jso["id"]
    pid = parent_jso.get('id', '')

    out = []
    out.append("// AUTOGENERATED FILE! Do not edit!")
    out.append(f"// Generated by gm_comp.py for object {oid}")
    out.append("#ifdef OBJECT")
    out.append('#include "engine/engine.h"')

    object_events = set(jso.get('events', []))        
    parent_events = _all_events(parent_jso)

    if (invalid:=object_events - VALID_EVENTSs):
        raise Exception(f"Invalid event(s): {', '.join(invalid)}")
    
    for event in object_events:
        out.append(f"#define object_{event} OBJ_{event}_{oid}")
        out.append(f"extern void object_{event}(void);")
    for event in parent_events:
        out.append(f"#define object_{event}_inherited OBJ_{event}_{pid}")
        out.append(f"\textern object_{event}_inherited();")

    # A non-exported fake function to smuggle in our function overides
    out.append("static void __() __naked {")
    out.append("\t#asm")
    for event in parent_events - object_events:
        out.append(f"\n\tEXTERN OBJ_{event}_{pid}")
        out.append(  f"\tPUBLIC OBJ_{event}_{oid}")
        out.append(  f"\tDEFC  OBJ_{event}_{oid}=OBJ_{event}_{pid}")
    out.append("\t#endasm")

    out.append("}")
    sprite = jso.get("sprite")
    if sprite:
        sprite = _room_identifier(sprite, f"{oid}: sprite")
        sprite_jso = _load_json(join(GAME_DIR, "sprites", sprite + ".json"))
        frames = sprite_jso.get("frames", [])
        if isinstance(frames, int):
            frames = range(frames)
        out.append(f'#include "game/sprites/{sprite}.h"')
    else:
        frames = []
    out.append(f"Object {oid} = {{")
    events = _all_events(jso)
    callback_fields = ("begin_step", "step", "end_step", "draw", "pre_draw",
                       "post_draw", "draw_begin", "draw_end", "draw_gui")
    out += [f"    OBJ_{event}_{oid}," if event in events else "    0,"
            for event in callback_fields]
    frames = list(frames)
    if len(frames) > 16:
        raise ValueError(f"{oid}: at most 16 sprite frames are supported")
    out.append("    {" + ", ".join(
        f"&{sprite}_{i}" if i < len(frames) else "0" for i in range(16)) + "},")
    out.append("    {" + ", ".join(
        f"OBJ_user{i}_{oid}" if f"user{i}" in events else "0" for i in range(16)) + "},")
    out.append("    {" + ", ".join(
        f"OBJ_alarm{i}_{oid}" if f"alarm{i}" in events else "0" for i in range(12)) + "},")
    out.append("};")
    out.append("#endif")

    with open(h_file, "w") as f:
        f.write("\n".join(out))

    return _compile_object_c(c_file)

    

def compile_transients(gpl_path=GPL_PATH):
    # Sprites are relativly simple
    for jso in get_transients(["sprites"]):
        if check_asm_only_compilation(jso):
            print(f"up-to-date: {jso}")
        elif not check_sprite_codegen(jso):
            print(f"compiling sprite: {jso}")
            try:
                asm_path, h_path = compile_sprite(jso, gpl_path)
            except SpriteCompileError as e:
                print(f"error: {e}", file=sys.stderr)
                raise SystemExit(1)
            print(f"  -> {asm_path}, {h_path}")

            yield _compile_transient_asm(asm_path)
        else:
            # Codegen (.asm/.h) is fresh but .o is missing/stale:
            # reassemble without regenerating.
            print(f"assembling sprite: {jso}")
            asm_path, _h_path = sprite_output_paths(jso)
            yield _compile_transient_asm(asm_path)

    for jso in get_transients(["objects"]):
        if check_obj_compilation(jso):
            print(f"up-to-date: {jso}")
        elif not check_object_codegen(jso):
            print(f"compiling object: {jso}")
            yield _compile_object(jso, _load_json(jso))
        else:
            # Generated .h is fresh but .o is missing/stale:
            # recompile the .c without regenerating.
            print(f"compiling object (.o stale): {jso}")
            c_file, _h_file = object_paths(jso)
            yield _compile_object_c(c_file)

# ==== Rooms ====

def list_rooms():
    return sorted(join(GAME_DIR, "rooms", file)
                  for file in os.listdir(join(GAME_DIR, "rooms"))
                  if file.endswith(".json"))

def room_paths(json_path):
    base, _ext = splitext(json_path)
    return base + ".c", base + ".h"

def _room_int(value, field):
    if type(value) is not int or not -32768 <= value <= 32767:
        raise ValueError(f"{field} must be a signed 16-bit integer")
    return value


def _room_identifier(value, field):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", value):
        raise ValueError(f"{field} must be a C identifier")
    return value


def _compile_room(json_path):
    jso = _load_json(json_path)
    c_file, h_file = room_paths(json_path)
    rid = _room_identifier(jso["id"], f"{json_path}: id")
    page = jso.get("page", 0)
    if type(page) is not int or not 0 <= page <= 255:
        raise ValueError(f"{rid}: page must be between 0 and 255")
    instances = jso.get("instances", [])
    if not isinstance(instances, list):
        raise ValueError(f"{rid}: instances must be a list")
    lines = ["// AUTOGENERATED FILE! Do not edit!", '#include "engine/engine.h"']
    objects = set()
    for instance in instances:
        oid = _room_identifier(instance["object"], f"{rid}: instance object")
        if not exists(join(GAME_DIR, "objects", oid + ".json")):
            raise ValueError(f"{rid}: unknown object {oid}")
        objects.add(oid)
    lines += [f"extern Object {oid};" for oid in sorted(objects)]
    if jso.get("on_entry", False):
        lines.append("extern void room_entry(void);")
    for oid in sorted(objects):
        object_jso = _load_json(join(GAME_DIR, "objects", oid + ".json"))
        if "create" in _all_events(object_jso):
            lines.append(f"extern void OBJ_create_{oid}(void);")
    lines.append(f"void ROOM_init_{rid}(void) {{")
    for instance in instances:
        oid = instance["object"]
        depth = _room_int(instance.get("depth", 0), f"{rid}: depth")
        x = _room_int(instance.get("x", 0), f"{rid}: x")
        y = _room_int(instance.get("y", 0), f"{rid}: y")
        lines.append(f"    gmctx.instance = instance_create_depth({depth}, {x}, {y}, &{oid});")
        object_jso = _load_json(join(GAME_DIR, "objects", oid + ".json"))
        if "create" in _all_events(object_jso):
            lines.append(f"    OBJ_create_{oid}();")
    if jso.get("on_entry", False):
        lines.append("    room_entry();")
    lines.append("}")
    with open(h_file, "w") as f:
        f.write("\n".join(lines) + "\n")
    if not exists(c_file):
        with open(c_file, "w") as f:
            f.write(f'#define ROOM\n#include "game/rooms/{basename(h_file)}"\n')
    return _compile_room_c(c_file)


def generate_room_index():
    pages = {}
    ids = set()
    for path in list_rooms():
        jso = _load_json(path)
        rid = _room_identifier(jso["id"], f"{path}: id")
        if rid in ids:
            raise ValueError(f"duplicate room id: {rid}")
        ids.add(rid)
        page = jso.get("page", 0)
        if type(page) is not int or not 0 <= page <= 255:
            raise ValueError(f"{path}: page must be between 0 and 255")
        pages.setdefault(page, []).append(rid)
    c_lines = ["#ifndef ROOMS_H", "#define ROOMS_H", "typedef enum {"]
    asm_lines = ["IFNDEF ROOMS_INC", "DEFINE ROOMS_INC"]
    for page, rooms in sorted(pages.items()):
        if len(rooms) > 512:
            raise ValueError(f"page {page} has more than 512 rooms")
        for index, rid in enumerate(sorted(rooms)):
            value = index + (page << 9)
            c_lines.append(f"    {rid} = {value},")
            asm_lines.append(f"    DEFC {rid} = {value}")
    c_lines += ["} Room;", "#endif"]
    asm_lines.append("ENDIF")
    for name, content in (("rooms.h", c_lines), ("rooms.inc", asm_lines)):
        path = join(GAME_DIR, "rooms", name)
        data = "// AUTOGENERATED FILE! Do not edit!\n" if name.endswith(".h") else "; AUTOGENERATED FILE! Do not edit!\n"
        data += "\n".join(content) + "\n"
        if not exists(path) or open(path).read() != data:
            with open(path, "w") as f:
                f.write(data)


def compile_rooms():
    generate_room_index()
    for room in list_rooms():
        json_mtime = getmtime(room)
        room_json = _load_json(room)
        object_mtimes = [getmtime(join(GAME_DIR, "objects", instance["object"] + ".json"))
                         for instance in room_json.get("instances", [])]
        c_file, h_file = room_paths(room)
        o_file = splitext(c_file)[0] + ".o"
        if not exists(h_file) or getmtime(h_file) < max(json_mtime, getmtime(__file__), *object_mtimes):
            print(f"generating room: {room}")
            yield _compile_room(room)
        elif not exists(o_file) or getmtime(o_file) < max(getmtime(c_file), getmtime(h_file)):
            print(f"compiling room: {room}")
            yield _compile_room_c(c_file)


def main():
    if len(sys.argv) >= 2:
        if "--list-transients" == sys.argv[1]:
            list_transients()
        elif "--compile-transients" == sys.argv[1]:
            _compile(compile_transients())
        elif "--compile-rooms" == sys.argv[1]:
            _compile(compile_rooms())
        else:
            print("unknown operation")
    else:
        print("usage: gm_comp.py --list-transients|--compile-transients|--compile-rooms|"
              "--compile-sprite <json>|--check <json>")


if __name__ == "__main__":
    main()
