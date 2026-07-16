#!/usr/bin/env python3
"""Fail when executable callers use legacy proof-forge flags directly."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCAN_PATHS = [
    ROOT / "justfile",
    ROOT / "scripts",
    ROOT / "testkit",
    ROOT / "Tests",
]
SKIP_PARTS = {
    ".git",
    ".lake",
    "build",
    "node_modules",
    "target",
}
SKIP_FILES = {
    Path("scripts/cli/check-target-first-migration.py"),
}
TEXT_SUFFIXES = {
    "",
    ".lean",
    ".mjs",
    ".py",
    ".rs",
    ".sh",
    ".toml",
}
COMMENT_PREFIXES = ("#", "//", "--")
# Flags that are not legacy EmitMode aliases. `--version` is a global CLI
# meta flag (not an emit/build mode) and must stay allowed in scripts.
ALLOWED_FLAGS = {
    "--help",
    "--list-targets",
    "--list-fixtures",
    "--version",
}

LEGACY_COMMAND = re.compile(
    r"(?:^|[\s\"'])"
    r"(?:(?:lake\s+(?:env|exe)\s+)|(?:\./))?"
    r"(?:[^\s\"']*/)?proof-forge[\"']?\s+(--[A-Za-z0-9][A-Za-z0-9_-]*)"
)


def should_scan(path: Path) -> bool:
    try:
        rel = path.relative_to(ROOT)
    except ValueError:
        return False
    if rel in SKIP_FILES:
        return False
    if any(part in SKIP_PARTS for part in rel.parts):
        return False
    if path.is_dir():
        return True
    return path.suffix in TEXT_SUFFIXES


def iter_files(path: Path):
    if path.is_file():
        if should_scan(path):
            yield path
        return
    for child in path.rglob("*"):
        if child.is_file() and should_scan(child):
            yield child


def is_comment(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith(COMMENT_PREFIXES)


def main() -> int:
    failures: list[str] = []
    for scan_path in SCAN_PATHS:
        for path in iter_files(scan_path):
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeDecodeError:
                continue
            rel = path.relative_to(ROOT)
            for lineno, line in enumerate(lines, start=1):
                if is_comment(line):
                    continue
                match = LEGACY_COMMAND.search(line)
                if match is None:
                    continue
                flag = match.group(1)
                if flag in ALLOWED_FLAGS:
                    continue
                failures.append(
                    f"{rel}:{lineno}: legacy proof-forge flag `{flag}`; "
                    "use `proof-forge build|emit|check --target ...`"
                )

    if failures:
        print("target-first migration check failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("target-first migration check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
