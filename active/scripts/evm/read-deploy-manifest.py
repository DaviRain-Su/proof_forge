#!/usr/bin/env python3
"""Print deploy-manifest fields as key=value lines for proof-forge deploy."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: read-deploy-manifest.py MANIFEST.json", file=sys.stderr)
        return 2

    manifest_path = Path(sys.argv[1])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    inputs = manifest.get("inputs") or {}
    init_entry = inputs.get("initCode") or {}
    runtime_entry = inputs.get("bytecode") or {}
    profile = manifest.get("chainProfile")

    fields = {
        "fixture": manifest.get("fixture", ""),
        "contractName": manifest.get("contractName", ""),
        "initCodePath": init_entry.get("path", ""),
        "runtimeBytecodePath": runtime_entry.get("path", ""),
        "chainProfileId": (profile or {}).get("id", "") if isinstance(profile, dict) else "",
        "chainId": str((profile or {}).get("chainId", "")) if isinstance(profile, dict) else "",
    }

    for key, value in fields.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
