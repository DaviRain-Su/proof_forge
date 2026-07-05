#!/usr/bin/env python3
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Optional


def file_entry(root: Path, path: Path) -> dict:
    data = path.read_bytes()
    try:
        display_path = str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        display_path = str(path)
    return {
        "path": display_path,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    }


def dargo_version(dargo: str) -> Optional[str]:
    try:
        output = subprocess.run(
            [dargo, "--version"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError:
        return None
    if output.returncode != 0:
        return None
    return output.stdout.strip() or None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--package-source", required=True)
    parser.add_argument("--circuit-json", required=True)
    parser.add_argument("--abi-json", required=True)
    parser.add_argument("--execute-log", required=True)
    parser.add_argument("--dargo-manifest", required=True)
    parser.add_argument("--deploy-json")
    parser.add_argument("--out", required=True)
    parser.add_argument("--dargo", required=True)
    parser.add_argument("--execute-result", required=True)
    parser.add_argument("--capability", action="append", default=[])
    parser.add_argument("--plan-metadata")
    args = parser.parse_args()

    root = Path(args.root)
    artifacts = {
        "source": file_entry(root, Path(args.source)),
        "packageSource": file_entry(root, Path(args.package_source)),
        "circuitJson": file_entry(root, Path(args.circuit_json)),
        "abiJson": file_entry(root, Path(args.abi_json)),
        "executeLog": file_entry(root, Path(args.execute_log)),
        "dargoManifest": file_entry(root, Path(args.dargo_manifest)),
    }
    validation = {
        "dargoTest": "passed",
        "dargoCompile": "passed",
        "dargoExecute": "passed",
        "dargoGenerateAbi": "passed",
        "dargoPackage": "passed",
        "executeResult": args.execute_result,
    }
    if args.deploy_json:
        artifacts["deployJson"] = file_entry(root, Path(args.deploy_json))
        validation["deployManifest"] = "passed"

    metadata = {
        "schemaVersion": 1,
        "target": "psy-dpn",
        "targetFamily": "zk-circuit-sourcegen",
        "artifactKind": "psy-circuit-json",
        "fixture": args.fixture,
        "capabilities": args.capability,
        "toolchain": {
            "dargo": {
                "path": args.dargo,
                "version": dargo_version(args.dargo),
            }
        },
        "artifacts": artifacts,
        "validation": validation,
    }

    if args.plan_metadata:
        plan_meta = json.loads(Path(args.plan_metadata).read_text())
        metadata["moduleName"] = plan_meta.get("moduleName")
        metadata["abi"] = {"entrypoints": plan_meta.get("entrypoints", [])}
        metadata["events"] = plan_meta.get("events", [])
        metadata["contextOps"] = plan_meta.get("contextOps", [])
        metadata["crosscalls"] = plan_meta.get("crosscalls", [])
        metadata["planCapabilities"] = plan_meta.get("capabilities", [])

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
