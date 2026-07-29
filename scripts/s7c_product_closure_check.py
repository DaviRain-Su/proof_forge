#!/usr/bin/env python3
"""S7c gate helper: exact_physical_closure on Solana/Noir Counter product trees."""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Import shared helper from the same scripts directory.
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from validate_artifacts import exact_physical_closure  # noqa: E402


def check(dir_name: str) -> None:
    root = Path("build/v2") / dir_name
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    expected = set(manifest["files"]) | {"manifest.json", "evidence.json"}
    exact_physical_closure(root, expected, label=dir_name)
    if "evidence.json" in manifest["files"]:
        raise SystemExit(f"{dir_name}: evidence.json must not be in manifest.files")


def main() -> None:
    for name in ("s7c-gate-solana", "s7c-gate-noir"):
        check(name)
    print("s7c product closure: ok")


if __name__ == "__main__":
    main()
