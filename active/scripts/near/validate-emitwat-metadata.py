#!/usr/bin/env python3
"""Validate wasm-near EmitWat artifact and deploy metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    print(f"near-emitwat-metadata: {message}", file=sys.stderr)
    raise SystemExit(1)


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def expect_object(value: Any, label: str) -> dict[str, Any]:
    expect(isinstance(value, dict), f"{label} must be an object")
    return value


def expect_list(value: Any, label: str) -> list[Any]:
    expect(isinstance(value, list), f"{label} must be an array")
    return value


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_artifact_entry(entry: Any, key: str, base_dir: Path) -> dict[str, Any]:
    obj = expect_object(entry, f"artifact {key}")
    raw_path = obj.get("path")
    expect(isinstance(raw_path, str) and raw_path, f"artifact {key}.path must be a non-empty string")
    raw = Path(raw_path)
    expect(not raw.is_absolute(), f"artifact {key}.path must be relative: {raw_path}")
    expect(".." not in raw.parts, f"artifact {key}.path must not escape artifact directory: {raw_path}")
    path = base_dir / raw
    expect(path.is_file(), f"artifact {key}.path does not exist: {path}")
    expected_sha = obj.get("sha256")
    expected_bytes = obj.get("bytes")
    expect(isinstance(expected_sha, str) and len(expected_sha) == 64, f"artifact {key}.sha256 must be a SHA-256 hex digest")
    expect(isinstance(expected_bytes, int) and expected_bytes > 0, f"artifact {key}.bytes must be a positive integer")
    actual = path.read_bytes()
    expect(len(actual) == expected_bytes, f"artifact {key}.bytes mismatch")
    expect(sha256_file(path) == expected_sha, f"artifact {key}.sha256 mismatch")
    return obj


def entrypoint_names(metadata: dict[str, Any]) -> list[str]:
    abi = expect_object(metadata.get("abi"), "abi")
    entrypoints = expect_list(abi.get("entrypoints"), "abi.entrypoints")
    names: list[str] = []
    for index, entry in enumerate(entrypoints):
        obj = expect_object(entry, f"abi.entrypoints[{index}]")
        name = obj.get("name")
        expect(isinstance(name, str) and name, f"abi.entrypoints[{index}].name must be non-empty")
        expect_list(obj.get("params"), f"abi.entrypoints[{index}].params")
        returns = obj.get("returns")
        expect(isinstance(returns, str) and returns, f"abi.entrypoints[{index}].returns must be non-empty")
        names.append(name)
    return names


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("metadata", help="path to proof-forge-artifact.json")
    parser.add_argument("--expected-fixture", required=True)
    parser.add_argument("--expected-module", required=True)
    parser.add_argument("--expected-entrypoints", required=True, help="comma-separated entrypoint names")
    parser.add_argument("--expected-source-kind", default="portable-ir")
    args = parser.parse_args()

    metadata_path = Path(args.metadata)
    metadata = expect_object(json.loads(metadata_path.read_text()), "metadata")
    metadata_base = metadata_path.parent

    expect(metadata.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(metadata.get("target") == "wasm-near", "target must be wasm-near")
    expect(metadata.get("targetFamily") == "wasmHost", "targetFamily must be wasmHost")
    expect(metadata.get("artifactKind") == "wasm", "artifactKind must be wasm")
    expect(metadata.get("fixture") == args.expected_fixture, "fixture mismatch")
    expect(metadata.get("sourceKind") == args.expected_source_kind, "sourceKind mismatch")
    if args.expected_source_kind == "portable-ir":
        expect(metadata.get("irVersion") == "portable-ir-v0", "irVersion must be portable-ir-v0")
    else:
        expect(metadata.get("irVersion") is None, "irVersion must be null for non-IR sources")
    expect(metadata.get("sourceModule") == args.expected_module, "sourceModule mismatch")
    expect_list(metadata.get("capabilities"), "capabilities")
    expect(entrypoint_names(metadata) == args.expected_entrypoints.split(","), "entrypoint list mismatch")

    artifacts = expect_object(metadata.get("artifacts"), "artifacts")
    wat = validate_artifact_entry(artifacts.get("wat"), "wat", metadata_base)
    deploy = validate_artifact_entry(artifacts.get("deployManifest"), "deployManifest", metadata_base)
    if "wasm" in artifacts:
        validate_artifact_entry(artifacts.get("wasm"), "wasm", metadata_base)

    validation = expect_object(metadata.get("validation"), "validation")
    expect(validation.get("emitWat") == "passed", "validation.emitWat must be passed")
    expect(validation.get("watGeneration") == "passed", "validation.watGeneration must be passed")
    expect(validation.get("deployManifest") == "passed", "validation.deployManifest must be passed")
    expect(validation.get("wat2wasm") in {"passed", "skipped"}, "validation.wat2wasm must be passed or skipped")

    deploy_path = metadata_base / Path(deploy["path"])
    deploy_manifest = expect_object(json.loads(deploy_path.read_text()), "deploy manifest")
    deploy_base = deploy_path.parent
    expect(deploy_manifest.get("schemaVersion") == 1, "deploy schemaVersion must be 1")
    expect(deploy_manifest.get("kind") == "proof-forge-wasm-near-deploy-manifest", "deploy kind mismatch")
    expect(deploy_manifest.get("target") == "wasm-near", "deploy target must be wasm-near")
    expect(deploy_manifest.get("fixture") == args.expected_fixture, "deploy fixture mismatch")
    expect(deploy_manifest.get("sourceKind") == args.expected_source_kind, "deploy sourceKind mismatch")
    if args.expected_source_kind == "portable-ir":
        expect(deploy_manifest.get("irVersion") == "portable-ir-v0", "deploy irVersion must be portable-ir-v0")
    else:
        expect(deploy_manifest.get("irVersion") is None, "deploy irVersion must be null for non-IR sources")
    expect(deploy_manifest.get("sourceModule") == args.expected_module, "deploy sourceModule mismatch")
    expect(entrypoint_names(deploy_manifest) == args.expected_entrypoints.split(","), "deploy entrypoint list mismatch")
    deploy_artifacts = expect_object(deploy_manifest.get("artifacts"), "deploy artifacts")
    deploy_wat = validate_artifact_entry(deploy_artifacts.get("wat"), "deploy wat", deploy_base)
    expect(deploy_wat["sha256"] == wat["sha256"], "deploy wat sha256 must match metadata wat")
    if "wasm" in deploy_artifacts:
        validate_artifact_entry(deploy_artifacts.get("wasm"), "deploy wasm", deploy_base)
    deployment = expect_object(deploy_manifest.get("deployment"), "deployment")
    expect(deployment.get("mode") == "local-offline-host", "deployment.mode must be local-offline-host")
    expect(deployment.get("status") == "not-broadcast", "deployment.status must be not-broadcast")
    # N1.7: explicit offline vs broadcast labeling (EVM-aligned honesty).
    # Never accept "broadcast passed" / live deploy claims from build-time manifests.
    expect(
        deployment.get("broadcast") == "not-generated",
        "deployment.broadcast must be not-generated (no live NEAR broadcast from build)",
    )
    expect(
        deployment.get("broadcastArtifact") is None,
        "deployment.broadcastArtifact must be null (no signed/broadcast tx artifact)",
    )
    expect(
        deployment.get("networkDeploy") == "not-generated",
        "deployment.networkDeploy must be not-generated",
    )
    expect(deployment.get("localExecutor") == "runtime/offline-host", "deployment.localExecutor mismatch")
    expect(deployment.get("nearAccountId") is None, "deployment.nearAccountId must be null")
    expect(
        deployment.get("nearSandbox") == "not-generated",
        "deployment.nearSandbox must be not-generated",
    )
    note = deployment.get("note")
    expect(isinstance(note, str) and note, "deployment.note must be a non-empty string")
    for forbidden in ("broadcast:passed", "broadcasted", "network-deployed"):
        expect(
            forbidden not in note.lower().replace(" ", ""),
            f"deployment.note must not claim live deploy ({forbidden})",
        )
    # validation.deployManifest=passed means the JSON was written, not that a
    # transaction was broadcast. offlineHost stays pending until a host smoke runs.
    expect(
        validation.get("offlineHost") in {None, "pending", "passed", "skipped", "unavailable"},
        "validation.offlineHost must not invent a broadcast status",
    )
    for key, value in validation.items():
        if "broadcast" in key.lower() and value == "passed":
            fail(f"validation.{key}=passed is forbidden without a broadcast tool")

    print("near-emitwat-metadata: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
