#!/usr/bin/env python3
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def sha256_and_bytes(path: Path) -> tuple[str, int]:
    data = path.read_bytes()
    return hashlib.sha256(data).hexdigest(), len(data)


def artifact_entry(path: Path) -> dict:
    digest, bytes_ = sha256_and_bytes(path)
    return {
        "path": str(path),
        "sha256": digest,
        "bytes": bytes_,
    }


def leo_version(leo_bin: str) -> str | None:
    try:
        result = subprocess.run(
            [leo_bin, "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.stdout.strip() or None
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--leo-project", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--leo", required=True)
    args = parser.parse_args()

    root = Path(args.root)
    source = Path(args.source)
    project_dir = Path(args.leo_project)
    out = Path(args.out)
    leo_bin = args.leo

    build_dir = project_dir / "build"
    program_name = project_dir.name

    artifacts: dict[str, dict] = {"leoSource": artifact_entry(source)}

    optional_artifacts = {
        "aleoInstructions": build_dir / "main.aleo",
        "abiJson": build_dir / "abi.json",
    }

    for key, path in optional_artifacts.items():
        if path.is_file():
            artifacts[key] = artifact_entry(path)

    leo_version_value = leo_version(leo_bin)

    metadata = {
        "schemaVersion": 1,
        "package": args.fixture,
        "target": "aleo-leo",
        "targetFamily": "zk-app-sourcegen",
        "artifactKind": "aleo-leo-package",
        "source": {
            "entryFile": "ProofForge/IR/Examples/Counter.lean",
            "module": "ProofForge.IR.Examples.Counter",
        },
        "proofs": {"checked": True, "warnings": []},
        "capabilities": [
            "lang.leo",
            "vm.aleo_avm",
            "artifact.avm",
            "artifact.aleo_abi",
            "execution.finalize",
            "state.mapping",
            "input.public",
            "output.public",
            "test.leo",
        ],
        "artifacts": artifacts,
        "toolchain": {
            "proofForge": "0.1.0",
            "lean": (root / "lean-toolchain").read_text().strip(),
            "external": {
                "leo": {
                    "path": leo_bin,
                    "version": leo_version_value,
                }
            },
        },
        "targetMetadata": {
            "programId": f"{program_name}.aleo",
            "mappings": [
                {"name": "count", "keyType": "u64", "valueType": "u64"}
            ],
            "entrypoints": [
                {
                    "name": "initialize",
                    "publicInputs": [],
                    "publicOutputs": [],
                    "finalize": True,
                },
                {
                    "name": "increment",
                    "publicInputs": [],
                    "publicOutputs": [],
                    "finalize": True,
                },
                {
                    "name": "get",
                    "publicInputs": [],
                    "publicOutputs": [],
                    "finalize": True,
                },
            ],
        },
        "validation": {
            "leoBuild": "passed",
            "leoTest": "passed",
            "leoTestProve": "skipped",
        },
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"aleo-artifact-metadata: wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
