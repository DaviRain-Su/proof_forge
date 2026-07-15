#!/usr/bin/env python3
"""Validate the four Phase-1 output contracts without overstating maturity."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def load_manifest(root: Path, target: str) -> dict:
    path = root / target / "manifest.json"
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest["target"] != target:
        raise SystemExit(f"target mismatch in {path}")
    for relative in manifest["files"]:
        if not (root / target / relative).is_file():
            raise SystemExit(f"manifest references missing file: {target}/{relative}")
    return manifest


def validate_accumulator(root: Path) -> None:
    output = root / "evm-accumulator"
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"missing {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_files = {
        "Accumulator.yul",
        "Accumulator.abi.json",
        "Accumulator.bin",
    }
    if manifest["target"] != "evm" or manifest["deployable"] is not True:
        raise SystemExit("Accumulator EVM manifest is not deployable")
    if set(manifest["files"]) != expected_files or len(manifest["files"]) != len(expected_files):
        raise SystemExit(f"Accumulator manifest file set is invalid: {manifest['files']}")
    for digest_name in ("sourceHash", "semanticHash"):
        if not re.fullmatch(r"[0-9a-f]{64}", manifest.get(digest_name, "")):
            raise SystemExit(f"Accumulator manifest has invalid {digest_name}")
    for relative in expected_files:
        if not (output / relative).is_file():
            raise SystemExit(f"Accumulator manifest references missing file: {relative}")
    binary = (output / "Accumulator.bin").read_text(encoding="ascii").strip()
    if len(binary) % 2 != 0 or not re.fullmatch(r"[0-9a-fA-F]+", binary):
        raise SystemExit("Accumulator bytecode is not non-empty, even-length hexadecimal")
    abi = json.loads((output / "Accumulator.abi.json").read_text(encoding="utf-8"))
    expected_abi = [
        {
            "type": "constructor",
            "stateMutability": "nonpayable",
            "inputs": [{"name": "seed", "type": "uint64"}],
        },
        {
            "type": "function",
            "name": "add",
            "stateMutability": "nonpayable",
            "inputs": [{"name": "amount", "type": "uint64"}],
            "outputs": [{"name": "", "type": "uint64"}],
        },
        {
            "type": "function",
            "name": "current",
            "stateMutability": "view",
            "inputs": [],
            "outputs": [{"name": "", "type": "uint64"}],
        },
    ]
    if abi != expected_abi:
        raise SystemExit(f"Accumulator ABI is invalid: {abi}")
    yul = (output / "Accumulator.yul").read_text(encoding="utf-8")
    if "case 0x7b881196" not in yul or "case 0x9fa6a6e3" not in yul:
        raise SystemExit("Accumulator Yul does not bind the canonical selectors")


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/v2")
    manifests = {target: load_manifest(root, target) for target in ("evm", "solana", "near", "noir")}
    source_hashes = {manifest["sourceHash"] for manifest in manifests.values()}
    semantic_hashes = {manifest["semanticHash"] for manifest in manifests.values()}
    if len(source_hashes) != 1:
        raise SystemExit(f"source hash differs across targets: {source_hashes}")
    if len(semantic_hashes) != 1:
        raise SystemExit(f"semantic hash differs across targets: {semantic_hashes}")
    evm_bin = (root / "evm" / "Counter.bin").read_text(encoding="ascii").strip()
    if not manifests["evm"]["deployable"] or not re.fullmatch(r"[0-9a-fA-F]+", evm_bin):
        raise SystemExit("EVM artifact is not validated bytecode")
    wasm = (root / "near" / "Counter.wasm").read_bytes()
    if not manifests["near"]["deployable"] or not wasm.startswith(b"\x00asm"):
        raise SystemExit("NEAR artifact is not a validated Wasm binary")
    if manifests["solana"]["deployable"]:
        raise SystemExit("Solana must remain non-deployable until an sBPF ELF is produced")
    if manifests["noir"]["deployable"]:
        raise SystemExit("Noir must remain non-deployable until nargo/bb proof evidence exists")
    validate_accumulator(root)
    print("artifact-validation: ok")


if __name__ == "__main__":
    main()
