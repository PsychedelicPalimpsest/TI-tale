#!/usr/bin/env python3
"""Lint and conservatively format the project's Z80 assembly sources.

The assembler does not care about indentation, and this project uses
indentation to communicate logical structure rather than to model every jump.
This tool therefore checks only whitespace and explicit constructs whose
indentation is unambiguous.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


INDENT_WIDTH = 4
SOURCE_SUFFIXES = {".asm", ".inc"}
SKIPPED_PARTS = {".git", "__pycache__", "build", "node_modules"}
GENERATED_MARKER = re.compile(r"autogenerat(?:ed|e) file", re.IGNORECASE)

LABEL_RE = re.compile(r"^[A-Za-z_.$@][A-Za-z0-9_.$@]*:")
TOKEN_RE = re.compile(r"^#?([A-Za-z][A-Za-z0-9_]*)\b")

OPENERS = {
    "MACRO": "macro",
    "REPT": "repeat",
    "REPTI": "repeat",
    "REPTC": "repeat",
    "IRP": "repeat",
    "IRPC": "repeat",
    "IF": "conditional",
    "IFDEF": "conditional",
    "IFNDEF": "conditional",
    "IFUSED": "conditional",
    "IFNUSED": "conditional",
}
CLOSERS = {
    "ENDM": "macro",
    "ENDR": "repeat",
    "ENDIF": "conditional",
}
ELSE_TOKENS = {"ELSE", "ELSEIF", "ELIF"}

# These directives describe layout or symbol declarations. They should not be
# treated as the executable body of a preceding routine label.
NON_BODY_TOKENS = {
    "ALIGN",
    "DEFC",
    "DEFL",
    "DEPHASE",
    "DEFINE",
    "ELSE",
    "ELSEIF",
    "ELIF",
    "ENDM",
    "ENDR",
    "ENDIF",
    "ERROR",
    "EXTERN",
    "GLOBAL",
    "IF",
    "IFDEF",
    "IFNDEF",
    "IFNUSED",
    "IFUSED",
    "INCLUDE",
    "MODULE",
    "ORG",
    "PHASE",
    "PUBLIC",
    "RALIGN",
    "RDEF",
    "SECTION",
    "UNDEFINE",
}


@dataclass(frozen=True)
class Block:
    kind: str
    indent: int
    line: int


@dataclass(frozen=True)
class Issue:
    line: int
    message: str


def split_comment(text: str) -> tuple[str, str]:
    """Split an assembly line without treating semicolons in strings as comments."""

    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "'\"":
            quote = char
        elif char == ";":
            return text[:index], text[index:]
    return text, ""


def leading_whitespace(line: str) -> tuple[str, str, int]:
    match = re.match(r"[ \t]*", line)
    assert match is not None
    prefix = match.group(0)
    rest = line[len(prefix) :]
    return prefix, rest, len(prefix.expandtabs(INDENT_WIDTH))


def rounded_indent(width: int) -> int:
    """Convert an existing indentation to a non-decreasing 4-space level."""

    if width == 0:
        return 0
    return ((width + INDENT_WIDTH - 1) // INDENT_WIDTH) * INDENT_WIDTH


def token_for(code: str) -> str:
    match = TOKEN_RE.match(code.strip())
    return match.group(1).upper() if match else ""


def label_info(code: str) -> tuple[bool, bool]:
    """Return (is_label, is_standalone_label)."""

    match = LABEL_RE.match(code.strip())
    if match is None:
        return False, False
    return True, not code.strip()[match.end() :].strip()


def matching_block_index(stack: list[Block], kind: str) -> int | None:
    for index in range(len(stack) - 1, -1, -1):
        if stack[index].kind == kind:
            return index
    return None


def block_body_indent(stack: list[Block]) -> int:
    if not stack:
        return 0
    return max(block.indent + INDENT_WIDTH for block in stack)


def line_is_body(token: str, is_label: bool) -> bool:
    return not is_label and token not in NON_BODY_TOKENS


def format_lines(lines: list[str]) -> tuple[list[str], list[Issue]]:
    """Format lines and return structural issues found while walking them."""

    stack: list[Block] = []
    pending_label: int | None = None
    output: list[str] = []
    structural_issues: list[Issue] = []

    for line_number, original in enumerate(lines, start=1):
        prefix, rest, expanded_width = leading_whitespace(original)
        code, _comment = split_comment(rest)
        stripped_code = code.strip()
        token = token_for(code)
        is_label, standalone_label = label_info(code)
        source_indent = rounded_indent(expanded_width)

        # Blank and comment-only lines retain their logical position. They do
        # not affect a label's following body or the explicit block stack.
        if not stripped_code:
            output.append((" " * source_indent + rest).rstrip(" \t"))
            continue

        expected_indent = source_indent
        close_index: int | None = None

        if token in CLOSERS:
            close_kind = CLOSERS[token]
            close_index = matching_block_index(stack, close_kind)
            if close_index is None:
                structural_issues.append(
                    Issue(line_number, f"unmatched {token.lower()} directive")
                )
            else:
                if close_index != len(stack) - 1:
                    structural_issues.append(
                        Issue(
                            line_number,
                            f"{token.lower()} closes {close_kind} before the inner block",
                        )
                    )
                expected_indent = stack[close_index].indent
                del stack[close_index:]
            pending_label = None
        elif token in ELSE_TOKENS:
            conditional_index = matching_block_index(stack, "conditional")
            if conditional_index is None:
                structural_issues.append(
                    Issue(line_number, f"unmatched {token.lower()} directive")
                )
            else:
                expected_indent = stack[conditional_index].indent
            pending_label = None
        elif is_label:
            # Labels can deliberately mark a new logical region inside a
            # macro, so preserve their source level and constrain only their
            # following executable body.
            expected_indent = source_indent
            pending_label = expected_indent if standalone_label else None
        elif token in OPENERS:
            expected_indent = max(
                source_indent,
                block_body_indent(stack),
                (pending_label + INDENT_WIDTH) if pending_label is not None else 0,
            )
            stack.append(Block(OPENERS[token], expected_indent, line_number))
        else:
            if line_is_body(token, is_label):
                expected_indent = max(
                    source_indent,
                    block_body_indent(stack),
                    (pending_label + INDENT_WIDTH)
                    if pending_label is not None
                    else 0,
                )
            else:
                # Declarations and layout directives can intentionally reset
                # the visual level inside a macro (for example, ALIGN before
                # a generated code region).
                expected_indent = source_indent

        output.append((" " * expected_indent + rest).rstrip(" \t"))

    for block in stack:
        structural_issues.append(
            Issue(block.line, f"unclosed {block.kind} block")
        )

    return output, structural_issues


def format_text(text: str) -> str:
    if not text:
        return text
    lines = text.splitlines()
    formatted, _issues = format_lines(lines)
    return "\n".join(formatted) + "\n"


def is_generated(text: str) -> bool:
    return any(GENERATED_MARKER.search(line) for line in text.splitlines()[:10])


def lint_text(text: str) -> list[Issue]:
    lines = text.splitlines()
    formatted, structural_issues = format_lines(lines)
    issues = list(structural_issues)

    for line_number, (original, expected) in enumerate(
        zip(lines, formatted, strict=True), start=1
    ):
        prefix, _rest, expanded_width = leading_whitespace(original)
        expected_prefix, _expected_rest, _ = leading_whitespace(expected)

        if original.rstrip(" \t") != original:
            issues.append(Issue(line_number, "trailing whitespace"))
        if "\t" in prefix:
            issues.append(Issue(line_number, "leading indentation must use spaces"))
        if expanded_width % INDENT_WIDTH:
            issues.append(
                Issue(line_number, "indentation must use 4-space levels")
            )
        if len(prefix.expandtabs(INDENT_WIDTH)) != len(expected_prefix):
            issues.append(
                Issue(
                    line_number,
                    f"indentation should be {len(expected_prefix)} spaces",
                )
            )

    if text and not text.endswith("\n"):
        issues.append(Issue(len(lines), "file must end with a newline"))
    return sorted(set(issues), key=lambda issue: (issue.line, issue.message))


def discover_files(root: Path, requested: Iterable[str], include_generated: bool) -> list[Path]:
    candidates: set[Path] = set()
    requested_paths = list(requested)

    if requested_paths:
        for requested_path in requested_paths:
            path = Path(requested_path)
            if not path.is_absolute():
                path = root / path
            if path.is_dir():
                candidates.update(path.rglob("*"))
            elif path.is_file():
                candidates.add(path)
    else:
        candidates.update(root.rglob("*"))

    files: list[Path] = []
    for path in sorted(candidates):
        if not path.is_file() or path.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        if any(part in SKIPPED_PARTS for part in path.relative_to(root).parts):
            continue
        text = path.read_text()
        if not include_generated and is_generated(text):
            continue
        files.append(path)
    return files


def relative_name(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def check_files(paths: list[Path], root: Path) -> int:
    issue_count = 0
    for path in paths:
        issues = lint_text(path.read_text())
        for issue in issues:
            print(f"{relative_name(path, root)}:{issue.line}: {issue.message}")
        issue_count += len(issues)
    if issue_count:
        print(f"{issue_count} assembly style issue(s) found", file=sys.stderr)
        return 1
    return 0


def format_files(paths: list[Path], root: Path, check_only: bool) -> int:
    changed = 0
    for path in paths:
        original = path.read_text()
        formatted = format_text(original)
        if original == formatted:
            continue
        changed += 1
        name = relative_name(path, root)
        if check_only:
            print(f"would format {name}")
        else:
            path.write_text(formatted)
            print(f"formatted {name}")
    return 1 if check_only and changed else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="project root (defaults to the directory containing tooling/)",
    )
    parser.add_argument(
        "--include-generated",
        action="store_true",
        help="include files marked AUTOGENERATED",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="report assembly style issues")
    check.add_argument("paths", nargs="*", help="files or directories to check")

    format_parser = subparsers.add_parser("format", help="format assembly sources")
    format_parser.add_argument(
        "--check",
        action="store_true",
        help="only report files that would change",
    )
    format_parser.add_argument("paths", nargs="*", help="files or directories to format")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    root = args.root.resolve()
    paths = discover_files(root, args.paths, args.include_generated)

    if args.command == "check":
        return check_files(paths, root)
    return format_files(paths, root, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
