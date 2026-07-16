#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


DEFAULT_DEPLOYER = "f83aa03c3e21321421696202b90f4dab0a9f87237c231bbba58b8f93c799126e"
DEFAULT_STATE_TREE_HEIGHT = 32


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


def expect_object(value: Any, name: str) -> dict:
    if not isinstance(value, dict):
        raise SystemExit(f"psy-deploy-manifest: {name} must be an object")
    return value


def expect_list(value: Any, name: str) -> list:
    if not isinstance(value, list):
        raise SystemExit(f"psy-deploy-manifest: {name} must be an array")
    return value


def expect_name(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"psy-deploy-manifest: {name} must be a non-empty string")
    return value


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as err:
        raise SystemExit(f"psy-deploy-manifest: failed to parse {path}: {err}") from err


def abi_functions(abi: dict, contract_name: str) -> dict:
    functions = {}
    for struct in expect_list(abi.get("structs"), "abi.structs"):
        struct_obj = expect_object(struct, "abi.structs[]")
        if struct_obj.get("name") != contract_name:
            continue
        for function in expect_list(struct_obj.get("functions"), f"abi.structs.{contract_name}.functions"):
            function_obj = expect_object(function, "abi function")
            name = expect_name(function_obj.get("name"), "abi function name")
            functions[name] = function_obj
    return functions


def circuit_function_summary(circuit: dict, abi_by_name: dict) -> dict:
    name = expect_name(circuit.get("name"), "circuit.name")
    method_id = circuit.get("method_id")
    if not isinstance(method_id, int):
        raise SystemExit(f"psy-deploy-manifest: circuit `{name}` has invalid method_id")
    circuit_inputs = expect_list(circuit.get("circuit_inputs"), f"circuit `{name}` inputs")
    circuit_outputs = expect_list(circuit.get("circuit_outputs"), f"circuit `{name}` outputs")
    return {
        "name": name,
        "methodId": method_id,
        "circuitInputs": len(circuit_inputs),
        "circuitOutputs": len(circuit_outputs),
        "stateCommands": len(expect_list(circuit.get("state_commands"), f"circuit `{name}` state_commands")),
        "definitions": len(expect_list(circuit.get("definitions"), f"circuit `{name}` definitions")),
        "assertions": len(expect_list(circuit.get("assertions"), f"circuit `{name}` assertions")),
        "events": len(expect_list(circuit.get("events"), f"circuit `{name}` events")),
        "abi": abi_by_name.get(name),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--contract-name", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--circuit-json", required=True)
    parser.add_argument("--abi-json", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--deployer", default=DEFAULT_DEPLOYER)
    parser.add_argument("--state-tree-height", type=int, default=DEFAULT_STATE_TREE_HEIGHT)
    args = parser.parse_args()

    if len(args.deployer) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in args.deployer):
        raise SystemExit("psy-deploy-manifest: deployer must be a 64-character hex string")
    if args.state_tree_height <= 0:
        raise SystemExit("psy-deploy-manifest: state tree height must be positive")

    root = Path(args.root)
    source = Path(args.source)
    circuit_path = Path(args.circuit_json)
    abi_path = Path(args.abi_json)
    circuits = expect_list(load_json(circuit_path), "circuit json")
    if not circuits:
        raise SystemExit("psy-deploy-manifest: circuit json must contain at least one function")
    abi = expect_object(load_json(abi_path), "abi json")
    abi_by_name = abi_functions(abi, args.contract_name)

    functions = [
        circuit_function_summary(expect_object(circuit, "circuit"), abi_by_name)
        for circuit in circuits
    ]
    function_whitelist = [function["methodId"] for function in functions]

    manifest = {
        "schemaVersion": 1,
        "kind": "proof-forge-psy-deploy-manifest",
        "target": "psy-dpn",
        "targetFamily": "zk-circuit-sourcegen",
        "artifactKind": "psy-deploy-json",
        "fixture": args.fixture,
        "contractName": args.contract_name,
        "deployer": args.deployer.lower(),
        "stateTreeHeight": args.state_tree_height,
        "functionWhitelist": function_whitelist,
        "functions": functions,
        "inputs": {
            "source": file_entry(root, source),
            "circuitJson": file_entry(root, circuit_path),
            "abiJson": file_entry(root, abi_path),
        },
        "upstreamGenesisJson": {
            "status": "not-generated",
            "reason": "current dargo release does not expose gen_deploy_json as a CLI subcommand; upstream example requires psy-dargo-cli Rust workspace internals",
            "reference": "psy-dargo-cli/examples/gen_deploy_json.rs",
        },
    }

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
