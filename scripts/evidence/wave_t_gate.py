#!/usr/bin/env python3
"""Run the Wave-T safety gates and emit artifact-bound JSON evidence."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any


FORMAT = "proof-forge.wave-t-evidence.v1"
MANIFEST_SCHEMA = "proof-forge.wave-t-gates.v1"
PRODUCTION_PROFILE = "primary-triad-wave-t"
PRODUCTION_TASK_IDS = {
    "T-00", "E-P0-01", "E-P0-02", "E-P0-03", "E-P0-04", "N-P0-01",
    "N-P0-02", "N-P0-03", "S-P0-01", "S-P0-02", "X-P0-01", "T-99",
}
PRODUCTION_IMPLEMENTATION_COMMITS = {
    "T-00": "528a01482264db9d6b613ff8e5676e81a3df0b1e",
    "E-P0-01": "fac64949531cdb7610f65a21c9f1213e44b3be0a",
    "E-P0-02": "86cc0f89509a8bb284bd4cded90ca8329c8e5445",
    "E-P0-03": "6dac65f655550a72738308f868de5f1580fe5653",
    "E-P0-04": "876e2ad9d00fbfd05026751d01b79c91afe11aa9",
    "N-P0-01": "ab4614174f37d0b25d07fb865e6f8ba5686911d8",
    "N-P0-02": "92ace75bafbdfe98692b611140cc5fa5085a27b8",
    "N-P0-03": "4f4ccb5f5ca2e2cc6d5f0e07ffc55a7d54cb46c8",
    "S-P0-01": "ab23a012e0378977d89c259f4c34784b8580eed6",
    "S-P0-02": "315f3acd6c8d44397f9be69f7a84a0e58771990c",
    "X-P0-01": "0f9ce05f77ece75d0fa131d0c4e5bfd8165859c8",
    "T-99": "HEAD",
}
PRODUCTION_GATE_SPECS = [
    ("T-00", "standard-compliance", ("just", "standard-compliance")),
    ("E-P0-01", "evm-abi-schema", ("just", "evm-abi-schema")),
    ("E-P0-02", "erc2612-foundry-attacks", ("just", "product-erc20-permit")),
    ("E-P0-03", "evm-standard-identity", ("just", "evm-standard-identity")),
    ("E-P0-04", "evm-diagnostics", ("just", "evm-diagnostics")),
    ("E-P0-04", "evm-errors-runtime", ("just", "evm-smoke", "errors")),
    ("T-99", "evm-wave-runtime", ("just", "evm-all")),
    ("N-P0-01", "near-abi-plan", ("just", "near-abi-plan")),
    ("N-P0-01", "near-generated-client", ("just", "near-abi-client")),
    ("N-P0-01", "near-abi-client-sandbox", ("just", "near-abi-client-sandbox")),
    ("N-P0-02", "near-ft-security", ("just", "near-ft-security")),
    ("N-P0-02", "near-ft-transfer-call-offline-host", ("just", "wasm-near-ft-transfer-call-e2e")),
    ("N-P0-02", "near-ft-security-sandbox", ("just", "near-ft-security-sandbox")),
    ("N-P0-03", "near-map-hash-alias", ("just", "near-map-hash-alias")),
    ("N-P0-03", "near-map-hash-alias-sandbox", ("just", "near-map-hash-alias-sandbox")),
    ("S-P0-01", "solana-duplicate-account-interpreter", ("just", "solana-duplicate-accounts")),
    ("S-P0-01", "solana-sbpf-encoder", ("just", "solana-bpf-encode-smoke")),
    ("S-P0-01", "solana-duplicate-account-live", ("just", "solana-duplicate-accounts-live")),
    ("S-P0-02", "solana-entrypoint-account-graph", ("just", "solana-account-graph")),
    ("S-P0-02", "solana-pinocchio-reference-equivalence", ("just", "solana-pinocchio-reference-equivalence")),
    ("S-P0-02", "solana-wave-light", ("just", "wave-t-solana-light")),
    ("X-P0-01", "token-feature-matrix", ("just", "token-feature-matrix")),
    ("T-99", "product-primary-triad", ("just", "product")),
    ("T-99", "product-solana-token", ("just", "product-token-solana")),
    ("T-99", "wave-static-baseline", ("just", "wave-t-check")),
]
PRODUCTION_TOOL_IDS = {
    "git", "python", "lean", "lake", "just", "forge", "solc", "cargo", "wat2wasm", "node",
    "java", "quint", "near-sandbox", "solana", "solana-keygen", "cargo-build-sbf", "sbpf", "surfpool",
}
PRODUCTION_TOOL_COMMANDS = {
    "git": ("git", "--version"),
    "python": ("python3", "--version"),
    "lean": ("lean", "--version"),
    "lake": ("lake", "--version"),
    "just": ("just", "--version"),
    "forge": ("forge", "--version"),
    "solc": ("solc", "--version"),
    "cargo": ("cargo", "--version"),
    "wat2wasm": ("wat2wasm", "--version"),
    "node": ("node", "--version"),
    "java": ("java", "--version"),
    "quint": ("quint", "--version"),
    "near-sandbox": ("near-sandbox", "--version"),
    "solana": ("solana", "--version"),
    "solana-keygen": ("solana-keygen", "--version"),
    "cargo-build-sbf": ("cargo-build-sbf", "--version"),
    "sbpf": ("sbpf", "--version"),
    "surfpool": ("surfpool", "--version"),
}
PRODUCTION_ARTIFACT_IDS = {
    "erc2612-creation-bytecode",
    "erc2612-contract-artifact",
    "nep141-token-plan",
    "nep141-wat",
    "spl-token-plan",
}
PRODUCTION_ARTIFACT_POLICIES = {
    "erc2612-creation-bytecode": {
        "path": "build/portable/erc20-permit/ERC20Permit.bin",
        "producedByOracleId": "erc2612-foundry-attacks",
        "adapter": {"id": "proof-forge.evm.erc2612", "version": "1"},
        "minimumBytes": 100,
    },
    "erc2612-contract-artifact": {
        "path": "build/portable/erc20-permit/ERC20Permit.proof-forge-artifact.json",
        "producedByOracleId": "erc2612-foundry-attacks",
        "adapter": {"id": "proof-forge.evm.erc2612", "version": "1"},
        "jsonEquals": {
            "format": "proof-forge-token-artifact-v0",
            "target": "evm",
            "artifactKind": "evm-erc20-contract",
        },
        "jsonArrayContains": {"token.features": "permit", "operations": "erc20.permit"},
    },
    "nep141-token-plan": {
        "path": "build/portable/token-near/FungibleToken.near-nep141-plan.json",
        "producedByOracleId": "product-primary-triad",
        "adapter": {"id": "proof-forge.near.nep141", "version": "1"},
        "jsonEquals": {
            "format": "proof-forge-token-plan-v0",
            "target": "wasm-near",
            "standard": "nep-141",
            "artifactKind": "near-nep141-plan",
        },
    },
    "nep141-wat": {
        "path": "build/portable/token-near/NearFungibleToken.wat",
        "producedByOracleId": "product-primary-triad",
        "adapter": {"id": "proof-forge.near.nep141", "version": "1"},
        "minimumBytes": 1000,
        "contains": ["ft_transfer", "ft_balance_of", "ft_mint", "promise_create"],
    },
    "spl-token-plan": {
        "path": "build/portable/token-solana/FungibleToken.solana-spl-token-plan.json",
        "producedByOracleId": "product-solana-token",
        "adapter": {"id": "proof-forge.solana.spl-token", "version": "1"},
        "jsonEquals": {
            "format": "proof-forge-token-plan-v0",
            "target": "solana-sbpf-asm",
            "standard": "spl-token",
            "artifactKind": "solana-spl-token-plan",
            "solana.programs.token": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
        },
    },
}
SKIP_PATTERN = re.compile(
    r"(?im)(?:^|:\s*)(?:skip|skipped)(?:\s*$|\s*:|\s*\()|"
    r"\b(?:missing tool|tool unavailable|not installed|not on path|prerequisite[^\n]*missing)\b"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], cwd: pathlib.Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def git_value(repo_root: pathlib.Path, *args: str) -> str:
    result = run(["git", *args], repo_root)
    if result.returncode != 0:
        raise ValueError(result.stdout.decode("utf-8", errors="replace").strip())
    return result.stdout.decode("utf-8", errors="replace").strip()


def checked_command(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{label} must be a non-empty array of strings")
    return value


def validate_manifest_structure(manifest: dict[str, Any], production: bool = False) -> list[dict[str, Any]]:
    if manifest.get("schemaVersion") != MANIFEST_SCHEMA:
        raise ValueError(f"expected manifest schema {MANIFEST_SCHEMA}")
    required_task_ids = manifest.get("requiredTaskIds")
    if (
        not isinstance(required_task_ids, list)
        or not required_task_ids
        or not all(isinstance(task_id, str) and task_id for task_id in required_task_ids)
        or len(set(required_task_ids)) != len(required_task_ids)
    ):
        raise ValueError("requiredTaskIds must be a non-empty array of unique strings")
    gates = manifest.get("gates")
    if not isinstance(gates, list) or not gates:
        raise ValueError("gates must be a non-empty array")
    covered_task_ids = {gate.get("taskId") for gate in gates}
    missing_task_ids = [task_id for task_id in required_task_ids if task_id not in covered_task_ids]
    if missing_task_ids:
        raise ValueError(f"required Wave-T tasks have no gate: {', '.join(missing_task_ids)}")

    if production or manifest.get("profile") == PRODUCTION_PROFILE:
        if manifest.get("profile") != PRODUCTION_PROFILE:
            raise ValueError("production manifest has the wrong profile")
        if manifest.get("requireCleanWorktree") is not True:
            raise ValueError("production manifest must require a clean worktree")
        if set(required_task_ids) != PRODUCTION_TASK_IDS:
            raise ValueError("production manifest task set does not match the code-level requirement")
        gate_specs = [
            (
                gate.get("taskId"),
                gate.get("oracle", {}).get("id"),
                gate.get("oracle", {}).get("version"),
                tuple(gate.get("command", [])),
            )
            for gate in gates
        ]
        expected_gate_specs = [(task, oracle, "1", command) for task, oracle, command in PRODUCTION_GATE_SPECS]
        if gate_specs != expected_gate_specs:
            raise ValueError("production manifest gate/task/oracle/command sequence does not match the code-level requirement")
        for gate in gates:
            expected_commit = PRODUCTION_IMPLEMENTATION_COMMITS[gate["taskId"]]
            if gate.get("implementationCommit") != expected_commit:
                raise ValueError(
                    f"production manifest gate {gate['taskId']} has a mismatched implementation commit"
                )
        tool_ids = [tool.get("id") for tool in manifest.get("tools", [])]
        if len(tool_ids) != len(set(tool_ids)) or set(tool_ids) != PRODUCTION_TOOL_IDS:
            raise ValueError("production manifest tool set does not match the code-level requirement")
        for tool in manifest.get("tools", []):
            if tuple(tool.get("command", [])) != PRODUCTION_TOOL_COMMANDS[tool["id"]]:
                raise ValueError(f"production manifest tool {tool['id']} has a mismatched version command")
        artifact_ids = [artifact.get("id") for artifact in manifest.get("artifacts", [])]
        if len(artifact_ids) != len(set(artifact_ids)) or set(artifact_ids) != PRODUCTION_ARTIFACT_IDS:
            raise ValueError("production manifest artifact set does not match the code-level requirement")
        for artifact in manifest.get("artifacts", []):
            policy = PRODUCTION_ARTIFACT_POLICIES[artifact["id"]]
            for key, expected in policy.items():
                if artifact.get(key) != expected:
                    raise ValueError(
                        f"production manifest artifact {artifact['id']} has a mismatched {key} policy"
                    )
        gate_artifacts = {
            artifact_id
            for gate in gates
            for artifact_id in gate.get("requiredArtifactIds", [])
        }
        if gate_artifacts != PRODUCTION_ARTIFACT_IDS:
            raise ValueError("production manifest gates do not bind every required artifact")
        producers = {artifact.get("producedByOracleId") for artifact in manifest.get("artifacts", [])}
        for artifact in manifest.get("artifacts", []):
            producer = artifact.get("producedByOracleId")
            matching_gates = [
                gate for gate in gates
                if gate.get("oracle", {}).get("id") == producer
                and artifact.get("id") in gate.get("requiredArtifactIds", [])
            ]
            if len(matching_gates) != 1:
                raise ValueError(f"production manifest artifact {artifact.get('id')} has no unique producing gate")
        if None in producers:
            raise ValueError("production manifest artifact has no producing oracle")
    return gates


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def nested_json_value(value: Any, dotted_path: str) -> Any:
    current = value
    for part in dotted_path.split("."):
        if not isinstance(current, dict) or part not in current:
            raise ValueError(f"artifact metadata has no JSON path {dotted_path}")
        current = current[part]
    return current


def artifact_path(repo_root: pathlib.Path, artifact: dict[str, Any]) -> pathlib.Path:
    relative = pathlib.Path(artifact.get("path", ""))
    if relative.is_absolute() or not relative.parts:
        raise ValueError(f"artifact {artifact.get('id')} path must be relative")
    resolved = (repo_root / relative).resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError as error:
        raise ValueError(f"artifact {artifact.get('id')} escapes the repository") from error
    return resolved


def inspect_artifact(repo_root: pathlib.Path, artifact: dict[str, Any], oracle_id: str) -> dict[str, Any]:
    path = artifact_path(repo_root, artifact)
    base = {
        "id": artifact.get("id"),
        "path": artifact.get("path"),
        "adapter": artifact.get("adapter"),
        "producedByOracleId": oracle_id,
    }
    if not path.is_file():
        return {**base, "status": "missing"}
    data = path.read_bytes()
    minimum_bytes = artifact.get("minimumBytes", 1)
    if len(data) < minimum_bytes:
        return {**base, "status": "invalid", "failure": f"artifact has {len(data)} bytes; expected at least {minimum_bytes}"}
    try:
        if artifact.get("jsonEquals") or artifact.get("jsonArrayContains"):
            decoded = json.loads(data)
            for dotted_path, expected in artifact.get("jsonEquals", {}).items():
                actual = nested_json_value(decoded, dotted_path)
                if actual != expected:
                    raise ValueError(f"JSON path {dotted_path} expected {expected!r}, got {actual!r}")
            for dotted_path, expected in artifact.get("jsonArrayContains", {}).items():
                actual = nested_json_value(decoded, dotted_path)
                if not isinstance(actual, list) or expected not in actual:
                    raise ValueError(f"JSON path {dotted_path} does not contain {expected!r}")
        text = data.decode("utf-8") if artifact.get("contains") else ""
        for expected in artifact.get("contains", []):
            if expected not in text:
                raise ValueError(f"artifact does not contain {expected!r}")
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        return {**base, "status": "invalid", "failure": str(error)}
    return {
        **base,
        "status": "present",
        "bytes": len(data),
        "sha256": sha256_bytes(data),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--repo-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--validate-manifest-only", action="store_true")
    parser.add_argument("--production", action="store_true")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    home = pathlib.Path.home()
    preferred_paths = [
        pathlib.Path("/opt/homebrew/opt/openjdk@17/bin"),
        home / ".elan" / "bin",
        home / ".local" / "bin",
        home / ".foundry" / "bin",
        home / ".cargo" / "bin",
        home / ".local" / "share" / "solana" / "install" / "active_release" / "bin",
    ]
    os.environ["PATH"] = os.pathsep.join(str(path) for path in preferred_paths) + os.pathsep + os.environ["PATH"]
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    canonical_manifest = (repo_root / "scripts" / "evidence" / "wave-t-gates.json").resolve()
    production = args.production or args.validate_manifest_only or args.manifest.resolve() == canonical_manifest
    gates = validate_manifest_structure(manifest, production=production)
    if args.validate_manifest_only:
        print("wave-t-gate: production manifest valid")
        return 0
    if args.output is None:
        raise ValueError("--output is required unless --validate-manifest-only is used")

    resolved_commits: list[str] = []
    for gate in gates:
        implementation_commit = gate.get("implementationCommit")
        if not isinstance(implementation_commit, str) or not implementation_commit:
            raise ValueError(f"gate {gate.get('taskId')} has no implementation commit")
        result = run(["git", "rev-parse", "--verify", f"{implementation_commit}^{{commit}}"], repo_root)
        if result.returncode != 0:
            raise ValueError(
                f"gate {gate.get('taskId')} references unknown implementation commit {implementation_commit}"
            )
        resolved_commit = result.stdout.decode("utf-8", errors="replace").strip()
        ancestor = run(["git", "merge-base", "--is-ancestor", resolved_commit, "HEAD"], repo_root)
        if ancestor.returncode != 0:
            raise ValueError(
                f"gate {gate.get('taskId')} implementation commit {implementation_commit} is not an ancestor of HEAD"
            )
        resolved_commits.append(resolved_commit)

    revision = git_value(repo_root, "rev-parse", "HEAD")
    dirty = bool(git_value(repo_root, "status", "--porcelain"))
    if manifest.get("requireCleanWorktree") is True and dirty:
        raise ValueError("Wave-T evidence requires a clean worktree")
    report: dict[str, Any] = {
        "format": FORMAT,
        "generatedAt": datetime.datetime.now(datetime.UTC).isoformat(),
        "source": {"revision": revision, "dirty": dirty},
        "manifestSha256": sha256_bytes(manifest_bytes),
        "result": "passed",
        "tools": [],
        "gates": [],
        "artifacts": [],
    }

    artifacts = manifest.get("artifacts", [])
    artifacts_by_id = {artifact.get("id"): artifact for artifact in artifacts}
    for artifact in artifacts:
        path = artifact_path(repo_root, artifact)
        if path.is_dir():
            raise ValueError(f"artifact {artifact.get('id')} path is a directory")
        path.unlink(missing_ok=True)

    failed = False
    for tool in manifest.get("tools", []):
        command = checked_command(tool.get("command"), f"tool {tool.get('id', '<unknown>')}")
        result = run(command, repo_root)
        output = result.stdout.decode("utf-8", errors="replace").strip()
        status = "passed" if result.returncode == 0 and output and not SKIP_PATTERN.search(output) else "failed"
        report["tools"].append(
            {
                "id": tool.get("id"),
                "command": shlex.join(command),
                "status": status,
                "version": output,
                "outputSha256": sha256_bytes(result.stdout),
            }
        )
        failed = failed or status == "failed"

    logs_dir = args.output.parent / "wave-t-logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    for index, gate in enumerate(gates):
        task_id = gate.get("taskId")
        command = checked_command(gate.get("command"), f"gate {task_id}")
        result = run(command, repo_root)
        output_text = result.stdout.decode("utf-8", errors="replace")
        log_path = logs_dir / f"{index + 1:02d}-{task_id}.log"
        log_path.write_bytes(result.stdout)
        failure = None
        if result.returncode != 0:
            failure = f"command exited {result.returncode}"
        elif SKIP_PATTERN.search(output_text):
            failure = "command output contains a skip marker or missing-tool marker"
        status = "failed" if failure else "passed"
        oracle_id = gate.get("oracle", {}).get("id")
        required_artifact_ids = set(gate.get("requiredArtifactIds", []))
        required_artifact_ids.update(
            artifact.get("id")
            for artifact in artifacts
            if artifact.get("producedByOracleId") == oracle_id
        )
        gate_artifacts = []
        for artifact_id in sorted(required_artifact_ids):
            artifact = artifacts_by_id.get(artifact_id)
            if artifact is None:
                failure = failure or f"gate references unknown artifact {artifact_id}"
                status = "failed"
                continue
            record = inspect_artifact(repo_root, artifact, oracle_id)
            gate_artifacts.append(record)
            report["artifacts"].append(record)
            if record["status"] != "present":
                failure = failure or f"required artifact {artifact_id} is {record['status']}"
                status = "failed"
        report["gates"].append(
            {
                "taskId": task_id,
                "implementationCommit": resolved_commits[index],
                "command": shlex.join(command),
                "oracle": gate.get("oracle"),
                "status": status,
                "exitCode": result.returncode,
                "runResultSha256": sha256_bytes(result.stdout),
                "log": str(log_path.relative_to(args.output.parent)),
                "artifacts": gate_artifacts,
                **({"failure": failure} if failure else {}),
            }
        )
        failed = failed or failure is not None

    recorded_artifact_ids = {artifact.get("id") for artifact in report["artifacts"]}
    for artifact in artifacts:
        if artifact.get("id") not in recorded_artifact_ids:
            record = inspect_artifact(repo_root, artifact, artifact.get("producedByOracleId"))
            report["artifacts"].append(record)
            failed = True

    for recorded in report["artifacts"]:
        if recorded.get("status") != "present":
            continue
        artifact = artifacts_by_id[recorded["id"]]
        current = inspect_artifact(repo_root, artifact, recorded["producedByOracleId"])
        if current.get("status") != "present" or current.get("sha256") != recorded.get("sha256"):
            failed = True
            report["artifactIntegrityFailure"] = (
                f"artifact {recorded['id']} changed after producing gate "
                f"{recorded['producedByOracleId']}"
            )
            break

    if failed:
        report["result"] = "failed"
    write_report(args.output, report)
    print(f"wave-t-gate: {report['result']} ({len(report['gates'])} gates, {len(report['artifacts'])} artifacts)")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"wave-t-gate: {error}", file=sys.stderr)
        raise SystemExit(1)
