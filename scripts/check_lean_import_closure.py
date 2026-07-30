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


def strip_lean_comments(text: str) -> str:
    """Remove nested block and line comments while preserving line boundaries."""
    out: list[str] = []
    depth = 0
    i = 0
    while i < len(text):
        if depth > 0:
            if text.startswith("/-", i):
                depth += 1
                i += 2
            elif text.startswith("-/", i):
                depth -= 1
                i += 2
            else:
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            continue
        if text.startswith("/-", i):
            depth = 1
            i += 2
            continue
        if text.startswith("--", i):
            newline = text.find("\n", i)
            if newline < 0:
                break
            out.append("\n")
            i = newline + 1
            continue
        out.append(text[i])
        i += 1
    if depth != 0:
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
