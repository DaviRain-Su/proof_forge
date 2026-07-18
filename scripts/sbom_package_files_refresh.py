#!/usr/bin/env python3
"""Regenerate supply-chain/lean-package-files.v1.json from the working tree.

The manifest is a committed pin consumed by TST-SBOM-002 (TASK-D0-08): any
ProofForgeV2 source add/remove/rename/content change must be followed by a
deliberate refresh committed alongside the source change, exactly like the
canonical golden re-pins.  Run with:

    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "supply-chain" / "lean-package-files.v1.json"
SCHEMA = "proof-forge.lean-package-files.v1"


def main() -> int:
    paths = [REPO_ROOT / "ProofForgeV2.lean"]
    paths.extend(sorted((REPO_ROOT / "ProofForgeV2").rglob("*.lean")))
    records = []
    for path in paths:
        data = path.read_bytes()
        records.append(
            {
                "path": str(path.relative_to(REPO_ROOT)),
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    records.sort(key=lambda record: record["path"])
    document = {"schema": SCHEMA, "files": records}
    MANIFEST_PATH.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"lean-package-files manifest refreshed: {len(records)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
