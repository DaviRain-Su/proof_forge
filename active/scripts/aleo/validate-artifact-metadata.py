#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("metadata", help="path to proof-forge-artifact.json")
    args = parser.parse_args()

    metadata_path = Path(args.metadata)
    if not metadata_path.is_file():
        print(f"aleo-validate-metadata: file not found: {metadata_path}", file=sys.stderr)
        return 1

    try:
        metadata = json.loads(metadata_path.read_text())
    except json.JSONDecodeError as e:
        print(f"aleo-validate-metadata: invalid JSON: {e}", file=sys.stderr)
        return 1

    required_top = [
        "schemaVersion",
        "package",
        "target",
        "targetFamily",
        "artifactKind",
        "source",
        "proofs",
        "capabilities",
        "artifacts",
        "toolchain",
        "validation",
    ]
    for key in required_top:
        if key not in metadata:
            print(f"aleo-validate-metadata: missing top-level field '{key}'", file=sys.stderr)
            return 1

    if metadata.get("schemaVersion") != 1:
        print(
            f"aleo-validate-metadata: unsupported schemaVersion {metadata.get('schemaVersion')}",
            file=sys.stderr,
        )
        return 1

    if metadata.get("target") != "aleo-leo":
        print(f"aleo-validate-metadata: expected target 'aleo-leo'", file=sys.stderr)
        return 1

    if metadata.get("targetFamily") != "zk-app-sourcegen":
        print(f"aleo-validate-metadata: expected targetFamily 'zk-app-sourcegen'", file=sys.stderr)
        return 1

    for capability in metadata.get("capabilities", []):
        if not isinstance(capability, str):
            print(f"aleo-validate-metadata: capability must be a string", file=sys.stderr)
            return 1

    validation = metadata.get("validation", {})
    for key in ("leoBuild", "leoTest"):
        if validation.get(key) != "passed":
            print(
                f"aleo-validate-metadata: validation.{key} is not 'passed'",
                file=sys.stderr,
            )
            return 1

    artifacts = metadata.get("artifacts", {})
    for key, entry in artifacts.items():
        if not isinstance(entry, dict):
            print(f"aleo-validate-metadata: artifact '{key}' must be an object", file=sys.stderr)
            return 1
        path = Path(entry.get("path", ""))
        if not path.is_file() or path.stat().st_size == 0:
            print(f"aleo-validate-metadata: artifact '{key}' missing or empty: {path}", file=sys.stderr)
            return 1
        expected_sha256 = entry.get("sha256", "")
        actual_sha256 = ""
        import hashlib
        actual_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        if expected_sha256 != actual_sha256:
            print(
                f"aleo-validate-metadata: artifact '{key}' SHA-256 mismatch",
                file=sys.stderr,
            )
            return 1

    print(f"aleo-validate-metadata: {metadata_path} is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
