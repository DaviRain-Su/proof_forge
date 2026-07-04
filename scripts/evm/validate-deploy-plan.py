#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"evm-deploy-plan-validate: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def resolve_path(root: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return root / path


def file_entry(root: Path, entry: dict, name: str) -> Path:
    path = resolve_path(root, expect_string(entry.get("path"), f"{name}.path"))
    expect(path.is_file(), f"{name}.path does not exist: {path}")
    data = path.read_bytes()
    expect(entry.get("bytes") == len(data), f"{name}.bytes mismatch")
    expect(entry.get("sha256") == hashlib.sha256(data).hexdigest(), f"{name}.sha256 mismatch")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expect-chain-profile")
    parser.add_argument("--expect-chain-id", type=int)
    parser.add_argument("deploy_plan")
    args = parser.parse_args()

    root = Path(args.root)
    plan = expect_object(json.loads(Path(args.deploy_plan).read_text(encoding="utf-8")), "deploy plan")

    expect(plan.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(plan.get("kind") == "proof-forge-evm-deploy-plan", "kind mismatch")
    expect(plan.get("target") == "evm", "target must be evm")
    expect_string(plan.get("fixture"), "fixture")
    expect_string(plan.get("contractName"), "contractName")

    manifest_path = file_entry(root, expect_object(plan.get("deployManifest"), "deployManifest"), "deployManifest")
    manifest = expect_object(json.loads(manifest_path.read_text(encoding="utf-8")), "deploy manifest")
    expect(manifest.get("kind") == "proof-forge-evm-deploy-manifest", "deploy manifest kind mismatch")

    profile = expect_object(plan.get("chainProfile"), "chainProfile")
    profile_id = expect_string(profile.get("id"), "chainProfile.id")
    if args.expect_chain_profile is not None:
        expect(profile_id == args.expect_chain_profile, "chainProfile.id mismatch")
    expect(profile.get("targetId") == "evm", "chainProfile.targetId must be evm")
    chain_id = profile.get("chainId")
    expect(isinstance(chain_id, int), "chainProfile.chainId must be an integer")
    if args.expect_chain_id is not None:
        expect(chain_id == args.expect_chain_id, "chainProfile.chainId mismatch")

    network = expect_object(plan.get("network"), "network")
    expect(network.get("kind") == "chain-profile", "network.kind mismatch")
    expect(network.get("chainId") == chain_id, "network.chainId mismatch")
    expect_string(network.get("rpcUrl"), "network.rpcUrl")

    broadcast = expect_object(plan.get("broadcastCommand"), "broadcastCommand")
    expect(broadcast.get("tool") == "cast", "broadcastCommand.tool mismatch")
    expect(broadcast.get("subcommand") == "send", "broadcastCommand.subcommand mismatch")
    args_list = broadcast.get("args")
    expect(isinstance(args_list, list) and args_list, "broadcastCommand.args must be a non-empty array")
    expect("<PRIVATE_KEY>" in args_list, "broadcastCommand.args must use <PRIVATE_KEY> placeholder")

    validation = expect_object(plan.get("validation"), "validation")
    expect(validation.get("chainProfileResolved") == "passed", "validation.chainProfileResolved mismatch")
    expect(validation.get("initCodeLoaded") == "passed", "validation.initCodeLoaded mismatch")
    expect(validation.get("liveBroadcast") == "not-requested", "validation.liveBroadcast mismatch")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
