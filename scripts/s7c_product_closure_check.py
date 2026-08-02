#!/usr/bin/env python3
"""S7c gate helper: exact_physical_closure on Solana/Noir Counter product trees.

Independent test validator (not product authority). Consumes D3-E7 descriptor
manifest files: `{role,path,size,contentSha256}` + top-level evidenceSha256.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Import shared helper from the same scripts directory.
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from validate_artifacts import (  # noqa: E402
    artifact_paths_from_manifest,
    exact_physical_closure,
    validate_engineering_output_manifest,
    verify_descriptor_contents,
    verify_evidence_sha256,
)


def check(dir_name: str) -> None:
    root = Path("build/v2") / dir_name
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    descriptors = validate_engineering_output_manifest(manifest, label=dir_name)
    paths = artifact_paths_from_manifest(manifest)
    expected = set(paths) | {"manifest.json", "evidence.json"}
    exact_physical_closure(root, expected, label=dir_name)
    verify_descriptor_contents(root, descriptors, label=dir_name)
    verify_evidence_sha256(root, manifest["evidenceSha256"], label=dir_name)
    for sidecar in ("evidence.json", "manifest.json"):
        if sidecar in paths:
            raise SystemExit(f"{dir_name}: {sidecar} must not be in manifest.files")


def main() -> None:
    for name in ("s7c-gate-solana", "s7c-gate-noir"):
        check(name)
    print("s7c product closure: ok")


if __name__ == "__main__":
    main()
