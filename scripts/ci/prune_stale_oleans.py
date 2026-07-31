#!/usr/bin/env python3
"""Prune .lake/build/lib/lean oleans whose source file no longer exists.

Lake does not garbage-collect olean artifacts of deleted modules, so a restored
CI cache can carry orphans (e.g. after a module removal) that break import
closure gates. This prunes exactly those, leaving everything else untouched.
"""
import os
import sys
from pathlib import Path

def main() -> int:
    root = Path.cwd()
    lib_lean = root / ".lake" / "build" / "lib" / "lean"
    if not lib_lean.is_dir():
        return 0
    removed = 0
    for olean in lib_lean.rglob("*.olean"):
        rel = olean.relative_to(lib_lean)
        module_path = rel.with_suffix("")
        source = root / f"{module_path}.lean"
        if not source.exists():
            for suffix in (".olean", ".ilean", ".olean.hash", ".olean.private",
                           ".olean.server", ".ilean.hash", ".trace", ".c", ".o"):
                stale = olean.with_suffix("") if False else olean
                # handle each artifact named <module><suffix> next to the olean
                candidate = olean.with_name(olean.name[: -len(".olean")] + suffix)
                try:
                    candidate.unlink()
                except FileNotFoundError:
                    pass
            removed += 1
    if removed:
        print(f"pruned {removed} stale module artifact set(s) from .lake/build/lib/lean")
    return 0

if __name__ == "__main__":
    sys.exit(main())
