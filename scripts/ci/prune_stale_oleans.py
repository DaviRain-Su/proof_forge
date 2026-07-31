#!/usr/bin/env python3
"""Prune .lake/build/lib/lean artifacts of deleted modules and their importers.

Lake does not garbage-collect olean artifacts of deleted modules, and it does
not notice when a cached olean still imports a module whose source has been
deleted. A restored CI cache can therefore carry orphans that break the
import-closure gates. This script iteratively removes:
  1. every module artifact set whose source file no longer exists, and
  2. every remaining olean whose import list references a removed module
     (its importer is stale and must be rebuilt from source).
"""
import sys
from pathlib import Path

def read_imports(olean: Path) -> list[str]:
    """Read the import list embedded in a Lean .olean (best effort).

    The olean layout: magic bytes, then an object file stream. Module names
    appear as raw UTF-8 strings; we scan for dotted module names that match
    the lib/lean layout (e.g. ProofForgeV2.Frontend.X). This is a heuristic,
    but safe: false positives only remove an olean that would be rebuilt.
    """
    try:
        data = olean.read_bytes()
    except OSError:
        return []
    names: list[str] = []
    # Scan for printable dotted names of reasonable length.
    text = data.decode("utf-8", errors="ignore")
    i = 0
    n = len(text)
    while i < n:
        # find start of a module-ish token
        if not (text[i].isalpha() or text[i] == "_"):
            i += 1
            continue
        j = i
        while j < n and (text[j].isalnum() or text[j] in "._'"):
            j += 1
        token = text[i:j]
        if 3 <= len(token) <= 200 and "." in token and "'" not in token:
            names.append(token)
        i = j
    return names

def artifact_paths(olean: Path, root: Path) -> list[Path]:
    paths = []
    base = olean.name[: -len(".olean")]
    for suffix in (".olean", ".ilean", ".olean.hash", ".olean.private",
                   ".olean.server", ".ilean.hash", ".trace"):
        p = olean.with_name(base + suffix)
        if p.exists():
            paths.append(p)
    return paths

def main() -> int:
    root = Path.cwd()
    lib_lean = root / ".lake" / "build" / "lib" / "lean"
    if not lib_lean.is_dir():
        return 0

    def source_exists(module_rel: Path) -> bool:
        return (root / f"{module_rel}.lean").exists()

    removed: set[Path] = set()
    # Pass 1: modules whose source is gone.
    for olean in list(lib_lean.rglob("*.olean")):
        rel = olean.relative_to(lib_lean)
        if not source_exists(rel.with_suffix("")):
            for p in artifact_paths(olean, root):
                removed.add(p)

    # Pass 2: importers of removed modules (iterate to fixpoint).
    changed = True
    while changed:
        changed = False
        for olean in list(lib_lean.rglob("*.olean")):
            if olean in removed or any(p == olean for p in removed):
                continue
            olean_rel = olean.relative_to(lib_lean)
            for imp in read_imports(olean):
                # Normalize: module name -> relative path under lib/lean.
                imp_rel = Path(*imp.split("."))
                if not source_exists(imp_rel) and imp_rel != olean_rel:
                    for p in artifact_paths(olean, root):
                        removed.add(p)
                    changed = True
                    break

    for p in sorted(removed, key=str):
        try:
            p.unlink()
        except FileNotFoundError:
            pass
    if removed:
        print(f"pruned {len(removed)} stale artifact(s) from .lake/build/lib/lean")
    return 0

if __name__ == "__main__":
    sys.exit(main())
