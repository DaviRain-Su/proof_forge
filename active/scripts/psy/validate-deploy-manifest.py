#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"psy-deploy-validate: {message}")


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_list(value: Any, name: str) -> list:
    expect(isinstance(value, list), f"{name} must be an array")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def file_entry(root: Path, entry: dict, name: str) -> Path:
    path = root / expect_string(entry.get("path"), f"inputs.{name}.path")
    expect(path.is_file(), f"inputs.{name}.path does not exist: {path}")
    data = path.read_bytes()
    expect(entry.get("bytes") == len(data), f"inputs.{name}.bytes mismatch")
    expect(entry.get("sha256") == hashlib.sha256(data).hexdigest(), f"inputs.{name}.sha256 mismatch")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("manifest")
    args = parser.parse_args()

    root = Path(args.root)
    manifest_path = Path(args.manifest)
    manifest = expect_object(json.loads(manifest_path.read_text()), "manifest")

    expect(manifest.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(manifest.get("kind") == "proof-forge-psy-deploy-manifest", "kind mismatch")
    expect(manifest.get("target") == "psy-dpn", "target must be psy-dpn")
    expect(manifest.get("targetFamily") == "zk-circuit-sourcegen", "targetFamily mismatch")
    expect(manifest.get("artifactKind") == "psy-deploy-json", "artifactKind mismatch")
    expect_string(manifest.get("fixture"), "fixture")
    expect_string(manifest.get("contractName"), "contractName")

    deployer = expect_string(manifest.get("deployer"), "deployer")
    expect(len(deployer) == 64 and all(ch in "0123456789abcdef" for ch in deployer), "deployer must be lowercase 64-character hex")
    expect(isinstance(manifest.get("stateTreeHeight"), int) and manifest["stateTreeHeight"] > 0, "stateTreeHeight must be positive integer")

    inputs = expect_object(manifest.get("inputs"), "inputs")
    file_entry(root, expect_object(inputs.get("source"), "inputs.source"), "source")
    circuit_path = file_entry(root, expect_object(inputs.get("circuitJson"), "inputs.circuitJson"), "circuitJson")
    file_entry(root, expect_object(inputs.get("abiJson"), "inputs.abiJson"), "abiJson")

    circuits = expect_list(json.loads(circuit_path.read_text()), "circuit json")
    method_ids = []
    for idx, circuit in enumerate(circuits):
        circuit_obj = expect_object(circuit, f"circuit[{idx}]")
        method_id = circuit_obj.get("method_id")
        expect(isinstance(method_id, int), f"circuit[{idx}].method_id must be integer")
        method_ids.append(method_id)

    whitelist = expect_list(manifest.get("functionWhitelist"), "functionWhitelist")
    expect(whitelist == method_ids, "functionWhitelist must match circuit method_id order")

    functions = expect_list(manifest.get("functions"), "functions")
    expect(len(functions) == len(circuits), "functions length must match circuit json")
    for idx, function in enumerate(functions):
        function_obj = expect_object(function, f"functions[{idx}]")
        expect(function_obj.get("methodId") == method_ids[idx], f"functions[{idx}].methodId mismatch")
        expect_string(function_obj.get("name"), f"functions[{idx}].name")
        for key in ("circuitInputs", "circuitOutputs", "stateCommands", "definitions", "assertions", "events"):
            expect(isinstance(function_obj.get(key), int) and function_obj[key] >= 0, f"functions[{idx}].{key} must be non-negative integer")

    upstream = expect_object(manifest.get("upstreamGenesisJson"), "upstreamGenesisJson")
    expect(upstream.get("status") in ("not-generated", "generated"), "upstreamGenesisJson.status mismatch")
    expect_string(upstream.get("reference"), "upstreamGenesisJson.reference")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
