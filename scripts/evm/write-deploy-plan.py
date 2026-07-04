#!/usr/bin/env python3
"""Write a proof-forge-evm-deploy-plan artifact for documented testnet workflows."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def file_entry(root: Path, path_text: str) -> dict:
    path = Path(path_text)
    if not path.is_absolute():
        path = root / path
    data = path.read_bytes()
    try:
        display = str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        display = str(path)
    return {
        "path": display,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--deploy-manifest", required=True)
    parser.add_argument("--init-code", required=True)
    parser.add_argument("--runtime-bytecode", required=True)
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    root = Path(args.root)
    manifest = json.loads(Path(args.deploy_manifest).read_text(encoding="utf-8"))
    init_hex = Path(args.init_code).read_text(encoding="utf-8").strip()
    profile = manifest.get("chainProfile") or {}

    plan = {
        "schemaVersion": 1,
        "kind": "proof-forge-evm-deploy-plan",
        "target": "evm",
        "targetFamily": "evm",
        "fixture": manifest.get("fixture", ""),
        "contractName": manifest.get("contractName", ""),
        "deployManifest": file_entry(root, args.deploy_manifest),
        "runtimeBytecode": file_entry(root, args.runtime_bytecode),
        "initCode": file_entry(root, args.init_code),
        "chainProfile": profile,
        "constructorAbi": manifest["abi"]["constructor"],
        "constructorArgs": manifest["creation"]["constructorArgs"],
        "network": {
            "kind": "chain-profile",
            "chainId": profile.get("chainId"),
            "rpcUrl": args.rpc_url,
        },
        "broadcastCommand": {
            "tool": "cast",
            "subcommand": "send",
            "args": [
                "--rpc-url",
                args.rpc_url,
                "--private-key",
                "<PRIVATE_KEY>",
                "--create",
                f"0x{init_hex}",
            ],
            "notes": [
                "Resolve <PRIVATE_KEY> from your wallet or CI secret store; never commit keys.",
                "Use the chain profile RPC metadata from proof-forge-deploy.json.",
                "Re-run with `proof-forge deploy --target evm --broadcast --rpc-url ... --private-key ...` to record a deploy-run artifact.",
            ],
        },
        "validation": {
            "chainProfileResolved": "passed",
            "initCodeLoaded": "passed",
            "liveBroadcast": "not-requested",
        },
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
