#!/usr/bin/env python3
"""Fail when a Lean product root reaches a forbidden internal module."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Callable, Iterable


IMPORT_RE = re.compile(r"^import\s+([A-Z][A-Za-z0-9_.]*)\s*$")
INTERNAL_PREFIXES = ("ProofForgeV2", "Tests")


class ClosureError(Exception):
    pass


def _is_lean_id_continue(ch: str) -> bool:
    """Chars that continue a Lean identifier (incl. trailing primes)."""
    return ch.isalnum() or ch == "_" or ch == "'" or ord(ch) > 127


def _consume_lean_string_escape(text: str, i: int) -> int:
    """Advance past a Lean string/char escape starting at backslash index ``i``.

    Total: always consumes at least the backslash; never raises.
    Recognizes ``\\"``, ``\\\\``, ``\\n``, ``\\t``, ``\\r``, ``\\xHH``,
    ``\\uXXXX``, and ``\\u{...}`` (brace form stops at ``}`` or EOF).
    """
    n = len(text)
    if i >= n or text[i] != "\\":
        return min(i + 1, n)
    j = i + 1
    if j >= n:
        return n
    esc = text[j]
    if esc in "\"'\\ntr":
        return j + 1
    if esc == "x":
        j += 1
        for _ in range(2):
            if j < n and text[j] in "0123456789abcdefABCDEF":
                j += 1
            else:
                break
        return j
    if esc == "u":
        j += 1
        if j < n and text[j] == "{":
            j += 1
            while j < n and text[j] != "}":
                j += 1
            if j < n and text[j] == "}":
                j += 1
            return j
        for _ in range(4):
            if j < n and text[j] in "0123456789abcdefABCDEF":
                j += 1
            else:
                break
        return j
    # Unknown escape: consume backslash + one following char.
    return j + 1


def strip_lean_comments(text: str) -> str:
    """Remove nested block and line comments while preserving line boundaries.

    String-literal-aware: ``/-`` and ``--`` inside ``"..."`` / char literals
    are not comment openers. Modes: code, line comment, nested block comment,
    string, char. Also covers ``s!"..."`` (``s!`` is ordinary code before the
    opening quote). Newlines inside comments are preserved so import line
    numbers stay stable. Never raises on strings; only raises
    ``ClosureError("unterminated Lean block comment")`` for a real open block
    comment still open at EOF.
    """
    out: list[str] = []
    n = len(text)
    i = 0
    # Modes: "code" | "line" | "block" | "string" | "char"
    mode = "code"
    block_depth = 0

    while i < n:
        ch = text[i]

        if mode == "block":
            if text.startswith("/-", i):
                block_depth += 1
                i += 2
            elif text.startswith("-/", i):
                block_depth -= 1
                i += 2
                if block_depth == 0:
                    mode = "code"
            else:
                if ch == "\n":
                    out.append("\n")
                i += 1
            continue

        if mode == "line":
            if ch == "\n":
                out.append("\n")
                mode = "code"
            i += 1
            continue

        if mode == "string":
            if ch == "\\":
                end = _consume_lean_string_escape(text, i)
                out.append(text[i:end])
                i = end
            elif ch == '"':
                out.append(ch)
                i += 1
                mode = "code"
            else:
                out.append(ch)
                i += 1
            continue

        if mode == "char":
            # Lean char: 'c' or '\\n' / '\\xHH' / '\\uXXXX' / '\\u{...}' then '
            if ch == "\\":
                end = _consume_lean_string_escape(text, i)
                out.append(text[i:end])
                i = end
            elif ch == "'":
                out.append(ch)
                i += 1
                mode = "code"
            else:
                out.append(ch)
                i += 1
                # Single non-escape body char; next ' closes if present.
                if i < n and text[i] == "'":
                    out.append("'")
                    i += 1
                    mode = "code"
            continue

        # mode == "code"
        # Raw string prefixes r"..." / r#"..."# (conservative; keep total).
        if ch == "r" and i + 1 < n and (i == 0 or not _is_lean_id_continue(text[i - 1])):
            if text.startswith('r#"', i):
                # r#" ... "#  — find closing "#; if missing, emit rest as code.
                close = text.find('"#', i + 3)
                if close >= 0:
                    out.append(text[i : close + 2])
                    i = close + 2
                    continue
            elif text.startswith('r"', i):
                j = i + 2
                while j < n:
                    if text[j] == "\\":
                        j = _consume_lean_string_escape(text, j)
                        continue
                    if text[j] == '"':
                        j += 1
                        break
                    j += 1
                out.append(text[i:j])
                i = j
                continue

        if text.startswith("/-", i):
            mode = "block"
            block_depth = 1
            i += 2
            continue

        if text.startswith("--", i):
            mode = "line"
            i += 2
            continue

        if ch == '"':
            # Covers ordinary "..." and s!"..." / m!"..." (prefix is code).
            out.append(ch)
            i += 1
            mode = "string"
            continue

        if ch == "'":
            # Trailing primes on identifiers (env', m') are not char openers.
            if i == 0 or not _is_lean_id_continue(text[i - 1]):
                out.append(ch)
                i += 1
                mode = "char"
                continue

        out.append(ch)
        i += 1

    if block_depth != 0:
        raise ClosureError("unterminated Lean block comment")
    return "".join(out)


def parse_imports(path: Path) -> tuple[str, ...]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ClosureError(f"cannot read {path}: {error}") from error
    imports: list[str] = []
    for line in strip_lean_comments(text).splitlines():
        match = IMPORT_RE.fullmatch(line.strip())
        if match is not None:
            imports.append(match.group(1))
    return tuple(imports)


def module_path(repo: Path, module: str) -> Path | None:
    if module == "ProofForgeV2":
        candidate = repo / "ProofForgeV2.lean"
    else:
        candidate = repo / (module.replace(".", "/") + ".lean")
    if candidate.is_file():
        return candidate
    if module.startswith(INTERNAL_PREFIXES):
        raise ClosureError(f"internal Lean module has no source file: {module}")
    return None


def is_forbidden(module: str, forbidden: tuple[str, ...]) -> bool:
    return any(module == item or module.startswith(item + ".") for item in forbidden)


def find_forbidden_chain(
    roots: Iterable[str],
    forbidden: tuple[str, ...],
    load_imports: Callable[[str], tuple[str, ...]],
) -> tuple[str, ...] | None:
    stack: list[tuple[str, tuple[str, ...]]] = [
        (root, (root,)) for root in reversed(tuple(roots))
    ]
    visited: set[str] = set()
    while stack:
        module, chain = stack.pop()
        if is_forbidden(module, forbidden):
            return chain
        if module in visited:
            continue
        visited.add(module)
        imports = load_imports(module)
        for imported in reversed(imports):
            stack.append((imported, chain + (imported,)))
    return None


def _imports_from_text(text: str) -> tuple[str, ...]:
    """Parse import module names from source text (comment-stripped)."""
    imports: list[str] = []
    for line in strip_lean_comments(text).splitlines():
        match = IMPORT_RE.fullmatch(line.strip())
        if match is not None:
            imports.append(match.group(1))
    return tuple(imports)


def self_test() -> None:
    graph = {
        "Product": ("Middle", "External"),
        "Middle": ("Forbidden.Core",),
        "External": (),
        "Clean": ("MiddleClean",),
        "MiddleClean": ("Clean",),
    }

    def load(module: str) -> tuple[str, ...]:
        return graph.get(module, ())

    chain = find_forbidden_chain(("Product",), ("Forbidden",), load)
    if chain != ("Product", "Middle", "Forbidden.Core"):
        raise ClosureError(f"self-test indirect chain mismatch: {chain}")
    if find_forbidden_chain(("Clean",), ("Forbidden",), load) is not None:
        raise ClosureError("self-test clean cycle was rejected")

    # --- string-aware strip_lean_comments cases ---

    # String containing /- must not open a block comment.
    stripped = strip_lean_comments('def m := "has /- inside"\nimport Foo.Bar\n')
    if "/-" in stripped and 'import Foo.Bar' not in stripped:
        raise ClosureError("self-test: /- inside string broke import scan")
    if _imports_from_text('def m := "has /- inside"\nimport Foo.Bar\n') != ("Foo.Bar",):
        raise ClosureError("self-test: import lost after /- inside string")

    # String containing -- must not open a line comment (rest of file still parsed).
    src_dash = 'def m := "has -- inside"\nimport Rest.Of.File\n'
    if _imports_from_text(src_dash) != ("Rest.Of.File",):
        raise ClosureError("self-test: -- inside string hid following import")

    # Interpolated s!"..." with /- and a following import on next line.
    src_interp = 'def m := s!".../-/..."\nimport Foo\n'
    if _imports_from_text(src_interp) != ("Foo",):
        raise ClosureError("self-test: s! string with /- hid import Foo")
    try:
        strip_lean_comments(src_interp)
    except ClosureError as error:
        raise ClosureError(
            f"self-test: s! string with /- raised unexpectedly: {error}"
        ) from error

    # Nested real block comments still stripped.
    nested = "import Keep\n/- outer /- inner -/ still comment -/\nimport After\n"
    if _imports_from_text(nested) != ("Keep", "After"):
        raise ClosureError(
            f"self-test: nested block comment strip failed: {_imports_from_text(nested)}"
        )
    if "outer" in strip_lean_comments(nested) or "inner" in strip_lean_comments(nested):
        raise ClosureError("self-test: nested block comment body leaked")

    # Trailing line comment after import.
    if _imports_from_text("import Foo -- trailing comment\n") != ("Foo",):
        raise ClosureError("self-test: trailing line comment broke import Foo")

    # Genuinely unterminated block comment in code must raise.
    try:
        strip_lean_comments("def x := 1\n/- never closed\nimport Ghost\n")
    except ClosureError as error:
        if str(error) != "unterminated Lean block comment":
            raise ClosureError(
                f"self-test: wrong unterminated message: {error}"
            ) from error
    else:
        raise ClosureError("self-test: expected unterminated Lean block comment")

    # Quote inside a block comment must not open a string.
    quoted_in_block = '/- "not a string" -/\nimport Bar\n'
    if _imports_from_text(quoted_in_block) != ("Bar",):
        raise ClosureError("self-test: quote inside block comment hid import Bar")

    # Escaped quote stays inside one string; backslash-escape ends correctly.
    esc_quote = 'def m := "a \\" b"\nimport Escaped.Ok\n'
    if _imports_from_text(esc_quote) != ("Escaped.Ok",):
        raise ClosureError("self-test: escaped quote broke string boundary")
    # "a \\"  →  content `a \` then closing quote; following import visible.
    esc_bs = 'def m := "a \\\\"\nimport After.Backslash\n'
    if _imports_from_text(esc_bs) != ("After.Backslash",):
        raise ClosureError(
            f"self-test: backslash-escape boundary failed: {_imports_from_text(esc_bs)}"
        )

    # Newlines inside comments preserve line structure for imports after blanks.
    multi = "import A\n-- comment only\nimport B\n/- block\nstill\n-/\nimport C\n"
    if _imports_from_text(multi) != ("A", "B", "C"):
        raise ClosureError(
            f"self-test: newline-preserving comment strip failed: {_imports_from_text(multi)}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=None)
    parser.add_argument("--root", action="append", dest="roots", required=True)
    parser.add_argument("--forbid", action="append", dest="forbidden", required=True)
    args = parser.parse_args()

    repo = Path(args.repo).resolve() if args.repo else Path(__file__).resolve().parents[1]
    forbidden = tuple(args.forbidden)
    self_test()

    cache: dict[str, tuple[str, ...]] = {}

    def load(module: str) -> tuple[str, ...]:
        if module in cache:
            return cache[module]
        path = module_path(repo, module)
        imports = () if path is None else parse_imports(path)
        cache[module] = imports
        return imports

    chain = find_forbidden_chain(tuple(args.roots), forbidden, load)
    if chain is not None:
        print(
            "product Lean import closure reaches forbidden module: " + " -> ".join(chain),
            file=sys.stderr,
        )
        return 1
    print(
        f"lean import closure: ok ({len(cache)} modules visited; {len(args.roots)} roots)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ClosureError as error:
        print(f"lean import closure gate error: {error}", file=sys.stderr)
        raise SystemExit(2)
