#!/usr/bin/env python3
import argparse
import hashlib
import json
import subprocess
import sys
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


VALIDATION_KEYS = (
    "dargoTest",
    "dargoCompile",
    "dargoExecute",
    "dargoGenerateAbi",
    "dargoPackage",
    "deployManifest",
)

ALLOWED_STATUSES = ("notRun", "passed", "failed", "unavailable")


def parse_validation_statuses(raw: Optional[str]) -> dict:
    """Parse a `key=status,...` override string into a dict.

    Unknown keys, unknown statuses, or malformed pairs are rejected. The
    executeResult field is always carried by the explicit --execute-result
    flag and is not part of this map.
    """
    statuses: dict = {}
    if not raw:
        return statuses
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        if "=" not in token:
            raise SystemExit(
                f"write-artifact-metadata: --validation-status entry '{token}' "
                f"is not a key=status pair"
            )
        key, _, value = token.partition("=")
        key = key.strip()
        value = value.strip()
        if key not in VALIDATION_KEYS:
            raise SystemExit(
                f"write-artifact-metadata: --validation-status key '{key}' "
                f"is not one of {VALIDATION_KEYS}"
            )
        if value not in ALLOWED_STATUSES:
            raise SystemExit(
                f"write-artifact-metadata: --validation-status '{key}={value}' "
                f"is not one of {ALLOWED_STATUSES}"
            )
        statuses[key] = value
    return statuses


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
    parser.add_argument("--dependency", action="append", default=[])
    parser.add_argument("--plan-metadata")
    parser.add_argument(
        "--validation-status",
        default="",
        help=(
            "Comma-separated key=status overrides for Dargo validation keys. "
            "Allowed statuses: notRun, passed, failed, unavailable. "
            "Keys not listed default to 'notRun'."
        ),
    )
    parser.add_argument(
        "--dargo-ran",
        action="store_true",
        help=(
            "Convenience flag for smoke scripts: mark every Dargo validation "
            "key as 'passed'. Used after a full Dargo test/compile/execute/abi/"
            "package cycle succeeded. Equivalent to --validation-status "
            "dargoTest=passed,dargoCompile=passed,..."
        ),
    )
    args = parser.parse_args()

    overrides = parse_validation_statuses(args.validation_status)
    dargo_keys = (
        "dargoTest",
        "dargoCompile",
        "dargoExecute",
        "dargoGenerateAbi",
        "dargoPackage",
    )
    default_status = "passed" if args.dargo_ran else "notRun"
    validation = {key: overrides.get(key, default_status) for key in dargo_keys}
    validation["executeResult"] = args.execute_result

    root = Path(args.root)
    artifacts = {
        "source": file_entry(root, Path(args.source)),
        "packageSource": file_entry(root, Path(args.package_source)),
        "circuitJson": file_entry(root, Path(args.circuit_json)),
        "abiJson": file_entry(root, Path(args.abi_json)),
        "executeLog": file_entry(root, Path(args.execute_log)),
        "dargoManifest": file_entry(root, Path(args.dargo_manifest)),
    }
    if args.deploy_json:
        artifacts["deployJson"] = file_entry(root, Path(args.deploy_json))
        validation["deployManifest"] = overrides.get("deployManifest", default_status)

    # Z1.2 honesty: circuitJson is the measured lower boundary (DPN bytecode).
    # Source `.psy` is intermediate when present. Never advertise a final DPN
    # primary when dargo compile did not pass.
    dargo_compile_status = validation.get("dargoCompile", "notRun")
    if dargo_compile_status == "passed":
        primary_output = "dpn-bytecode-json"
        final_output = "dpn-bytecode-json"
        lower_boundary = "DPNFunctionCircuitDefinition"
    else:
        primary_output = "psy-source"
        final_output = None
        lower_boundary = "psy-sourcegen-pending-dargo"

    metadata = {
        "schemaVersion": 1,
        "target": "psy-dpn",
        "targetFamily": "zk-circuit-sourcegen",
        "artifactKind": "psy-circuit-json",
        "primaryOutput": primary_output,
        "finalOutput": final_output,
        "lowerBoundary": lower_boundary,
        "fixture": args.fixture,
        "capabilities": args.capability,
        "dependencies": {dep: {} for dep in args.dependency},
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
        metadata["target"] = plan_meta.get("targetId", metadata.get("target"))
        metadata["abi"] = {"entrypoints": plan_meta.get("entrypoints", [])}
        metadata["events"] = plan_meta.get("events", [])
        metadata["contextOps"] = plan_meta.get("contextOps", [])
        metadata["crosscalls"] = plan_meta.get("crosscalls", [])
        metadata["planCapabilities"] = plan_meta.get("capabilities", [])
        plan_caps = set(metadata["planCapabilities"])
        smoke_caps = set(args.capability)
        # Plan capabilities are IR-derived; smoke scripts may add target-level
        # capabilities (e.g. zk.circuit) that the IR cannot see. Require that
        # every plan capability appears in the smoke list, but allow extra
        # smoke-side capabilities.
        missing = plan_caps - smoke_caps
        if missing:
            print(
                f"Error: plan capabilities {sorted(missing)} are not in "
                f"--capability list {sorted(smoke_caps)}",
                file=sys.stderr,
            )
            return 1

        # --- Metadata consistency validation ---
        CONTEXT_OP_TO_CAPABILITY = {
            "userId": "caller.sender",
            "contractId": "account.explicit",
            "checkpointId": "env.block",
        }

        # Rule 1: every contextOp must have its required capability present.
        for op in metadata["contextOps"]:
            op_name = op.get("name", "")
            required_cap = CONTEXT_OP_TO_CAPABILITY.get(op_name)
            if required_cap and required_cap not in smoke_caps:
                print(
                    f"Error: contextOp '{op_name}' requires capability "
                    f"'{required_cap}' but it is not in --capability list",
                    file=sys.stderr,
                )
                return 1

        # Rule 2: crosscall targets must reference a declared dependency or
        # the special literals "this" / "self".
        allowed_targets = set(metadata["dependencies"].keys()) | {"this", "self"}
        for cc in metadata["crosscalls"]:
            target = cc.get("targetContractId", "")
            if not target:
                print(
                    "Error: crosscall entry has empty targetContractId",
                    file=sys.stderr,
                )
                return 1
            if target not in allowed_targets:
                print(
                    f"Error: crosscall target '{target}' is not declared as a "
                    f"dependency and is not 'this' or 'self'",
                    file=sys.stderr,
                )
                return 1

        # Rule 3: dedup sanity — events, contextOps, crosscalls must be unique.
        for field_name, items in [
            ("events", metadata["events"]),
            ("contextOps", metadata["contextOps"]),
            ("crosscalls", metadata["crosscalls"]),
        ]:
            seen = set()
            for item in items:
                key = json.dumps(item, sort_keys=True)
                if key in seen:
                    print(
                        f"Error: duplicate entry in plan-metadata '{field_name}': {item}",
                        file=sys.stderr,
                    )
                    return 1
                seen.add(key)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
