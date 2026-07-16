#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path


SCHEMA = "proof-forge.stylus.remote-local.v1"
ADDRESS = re.compile(r"[0-9a-f]{40}")
WORD_42 = "00" * 31 + "2a"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"stylus-remote-local-evidence: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--evidence",
        type=Path,
        default=Path("build/evidence/stylus/remote-local.json"),
    )
    parser.add_argument(
        "--remote-wasm",
        type=Path,
        default=Path("build/stylus/remote-call/call.wasm"),
    )
    parser.add_argument(
        "--reentrant-wasm",
        type=Path,
        default=Path("build/stylus/reentrant/reentrant.wasm"),
    )
    args = parser.parse_args()

    require(args.evidence.is_file(), f"missing evidence {args.evidence}")
    require(args.remote_wasm.is_file(), f"missing artifact {args.remote_wasm}")
    require(args.reentrant_wasm.is_file(), f"missing artifact {args.reentrant_wasm}")
    try:
        evidence = json.loads(args.evidence.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"stylus-remote-local-evidence: invalid JSON: {error}") from error

    require(evidence.get("schema") == SCHEMA, "schema mismatch")
    require(evidence.get("environment") == "local-wasmtime", "environment mismatch")
    require(evidence.get("nitro") is False, "local evidence must never claim Nitro")

    contracts = evidence.get("contracts")
    require(isinstance(contracts, dict), "contracts object missing")
    caller = contracts.get("caller")
    callee = contracts.get("callee")
    require(isinstance(caller, str) and ADDRESS.fullmatch(caller) is not None,
            "caller must be a lowercase 20-byte address")
    require(isinstance(callee, str) and ADDRESS.fullmatch(callee) is not None,
            "callee must be a lowercase 20-byte address")
    require(caller != callee, "caller and callee must be distinct")

    artifacts = evidence.get("artifacts")
    require(isinstance(artifacts, dict), "artifacts object missing")
    require(artifacts.get("remoteWasmSha256") == sha256(args.remote_wasm),
            "remote Wasm hash mismatch")
    require(artifacts.get("reentrantWasmSha256") == sha256(args.reentrant_wasm),
            "reentrant Wasm hash mismatch")

    scenarios = evidence.get("scenarios")
    require(isinstance(scenarios, dict), "scenarios object missing")
    require(set(scenarios) == {
        "call", "staticWrite", "delegateContext", "reentrantSuccess", "reentrantRevert"
    }, "scenario set mismatch")
    require(scenarios["call"] == {"status": 0, "result": WORD_42},
            "call scenario mismatch")
    require(scenarios["staticWrite"] == {"status": 1, "storage": {}},
            "static write must fail without committed storage")
    require(scenarios["reentrantRevert"] == {"status": 1, "storage": {}},
            "reentrant revert must discard nested storage")
    require(scenarios["reentrantSuccess"].get("status") == 0 and
            scenarios["reentrantSuccess"].get("storage", {}).get("00" * 32) == WORD_42,
            "reentrant success storage mismatch")
    delegate = scenarios["delegateContext"]
    require(delegate.get("status") == 0, "delegate context call failed")
    delegate_storage = delegate.get("storage")
    require(isinstance(delegate_storage, dict) and len(delegate_storage) == 3,
            "delegate context storage mismatch")

    print("stylus-remote-local-evidence: ok")


if __name__ == "__main__":
    main()
