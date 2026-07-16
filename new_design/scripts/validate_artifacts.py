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


def validate_evm_accumulator(root: Path) -> dict:
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
    return manifest


def validate_solana_accumulator(root: Path, evm_manifest: dict) -> None:
    output = root / "solana-accumulator"
    manifest_path = output / "manifest.json"
    evidence_path = output / "evidence.json"
    plan_path = output / "Accumulator.sbpf-plan"
    idl_path = output / "Accumulator.idl.json"
    expected_names = {
        "manifest.json",
        "evidence.json",
        "Accumulator.sbpf-plan",
        "Accumulator.idl.json",
    }
    if not output.is_dir():
        raise SystemExit(f"missing {output}")
    actual_names = {
        str(path.relative_to(output)) for path in output.rglob("*") if path.is_file()
    }
    if actual_names != expected_names:
        raise SystemExit(
            f"Solana Accumulator output file set is invalid: {sorted(actual_names)}"
        )
    forbidden_suffixes = {".s", ".elf", ".so", ".o", ".bin"}
    forbidden = sorted(
        path.name
        for path in output.rglob("*")
        if path.is_file() and path.suffix.lower() in forbidden_suffixes
    )
    if forbidden:
        raise SystemExit(
            f"Solana Accumulator emitted executable/assembler artifacts: {forbidden}"
        )

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for digest_name in ("sourceHash", "semanticHash"):
        if not re.fullmatch(r"[0-9a-f]{64}", manifest.get(digest_name, "")):
            raise SystemExit(f"Solana Accumulator manifest has invalid {digest_name}")
    expected_manifest = {
        "schemaVersion": "proof-forge-output/v2alpha1",
        "target": "solana",
        "codegenProfile": "solana-sbpf-plan-v1",
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "deployable": False,
        "files": ["Accumulator.sbpf-plan", "Accumulator.idl.json"],
    }
    if manifest != expected_manifest:
        raise SystemExit(f"Solana Accumulator manifest is invalid: {manifest}")
    for digest_name in ("sourceHash", "semanticHash"):
        if manifest[digest_name] != evm_manifest[digest_name]:
            raise SystemExit(
                f"Accumulator {digest_name} differs between EVM and Solana: "
                f"{evm_manifest[digest_name]} != {manifest[digest_name]}"
            )

    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    expected_evidence = {
        "target": "solana",
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "deployable": False,
        "note": (
            "no pinned/approved sBPF assembler is configured; typed plan and "
            "IDL artifacts are non-executable"
        ),
    }
    if evidence != expected_evidence:
        raise SystemExit(f"Solana Accumulator evidence is invalid: {evidence}")

    expected_idl = {
        "version": "proof-forge-solana-idl/v1",
        "name": "Accumulator",
        "codegenProfile": "solana-sbpf-plan-v1",
        "deployable": False,
        "instructionEncoding": {
            "discriminator": "sha256-prefix-8",
            "domain": "proof-forge-solana-v1:",
            "arguments": "packed-u64-le",
            "trailingBytes": "reject",
        },
        "accounts": [
            {
                "name": "state",
                "index": 0,
                "owner": "current-program",
                "exactDataLen": 16,
                "header": {
                    "offset": 0,
                    "type": "u64-le",
                    "initializedMarker": "0xb298024662f2309a",
                    "layoutDomain": "proof-forge-solana-layout-v1:",
                },
                "initializerPayloadPolicy": "zero-all-fields",
                "fields": [
                    {
                        "name": "total",
                        "sourceId": 0,
                        "offset": 8,
                        "type": "u64-le",
                    }
                ],
            }
        ],
        "instructions": [
            {
                "name": "initialize",
                "discriminator": "5e494767a7582864",
                "mode": "initialize",
                "accounts": [
                    {
                        "name": "state",
                        "index": 0,
                        "owner": "current-program",
                        "isSigner": True,
                        "isWritable": True,
                        "initialization": "uninitialized",
                    }
                ],
                "args": [{"name": "seed", "type": "u64", "dataOffset": 8}],
                "returns": None,
            },
            {
                "name": "add",
                "discriminator": "2999f319c883ec76",
                "mode": "mutate",
                "accounts": [
                    {
                        "name": "state",
                        "index": 0,
                        "owner": "current-program",
                        "isSigner": False,
                        "isWritable": True,
                        "initialization": "initialized",
                    }
                ],
                "args": [{"name": "amount", "type": "u64", "dataOffset": 8}],
                "returns": "u64-le",
            },
            {
                "name": "current",
                "discriminator": "8c07d3938c593e21",
                "mode": "view",
                "accounts": [
                    {
                        "name": "state",
                        "index": 0,
                        "owner": "current-program",
                        "isSigner": False,
                        "isWritable": False,
                        "initialization": "initialized",
                    }
                ],
                "args": [],
                "returns": "u64-le",
            },
        ],
    }
    idl = json.loads(idl_path.read_text(encoding="utf-8"))
    if idl != expected_idl:
        raise SystemExit(f"Solana Accumulator IDL is invalid: {idl}")

    expected_plan = """; PROOF-FORGE-SBPF-PLAN v1
; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present
; codegen-profile: solana-sbpf-plan-v1
; program: Accumulator
; state-account index=0 owner=current-program exact-data-len=16
; header offset=0 type=u64-le initialized-marker=0xb298024662f2309a layout-domain=proof-forge-solana-layout-v1:
; initializer-payload-policy: zero-all-fields
; field source_id=0 name=total account=0 offset=8 type=u64-le
.handler 5e494767a7582864 initialize mode=initialize
  check instruction_data_len == 16
  check account[0].owner == current_program
  check account[0].data_len == 16
  check account[0].is_signer
  check account[0].is_writable
  check load_u64_le(account[0].data + 0) == 0x0000000000000000
  zero_u64_le account[0].data + 8
  %0 = load_u64_le(instruction_data + 8)
  store_u64_le account[0].data + 8, %0
  store_u64_le account[0].data + 0, 0xb298024662f2309a
.end-handler
.handler 2999f319c883ec76 add mode=mutate
  check instruction_data_len == 16
  check account[0].owner == current_program
  check account[0].data_len == 16
  check account[0].is_writable
  check load_u64_le(account[0].data + 0) == 0xb298024662f2309a
  %0 = load_u64_le(account[0].data + 8)
  %1 = load_u64_le(instruction_data + 8)
  %2 = checked_add_u64 %0, %1 else program_error 0x1001
  store_u64_le account[0].data + 8, %2
  %3 = load_u64_le(account[0].data + 8)
  set_return_data_u64_le %3
.end-handler
.handler 8c07d3938c593e21 current mode=view
  check instruction_data_len == 8
  check account[0].owner == current_program
  check account[0].data_len == 16
  check load_u64_le(account[0].data + 0) == 0xb298024662f2309a
  %0 = load_u64_le(account[0].data + 8)
  set_return_data_u64_le %0
.end-handler
"""
    plan = plan_path.read_text(encoding="utf-8")
    if re.search(r"(?im)^\s*\.globl\b|\bentrypoint\b", plan):
        raise SystemExit("Solana Accumulator plan contains assembler entrypoint syntax")
    if plan != expected_plan:
        raise SystemExit("Solana Accumulator typed plan does not match the accepted contract")


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
    evm_accumulator = validate_evm_accumulator(root)
    validate_solana_accumulator(root, evm_accumulator)
    print("artifact-validation: ok")


if __name__ == "__main__":
    main()
