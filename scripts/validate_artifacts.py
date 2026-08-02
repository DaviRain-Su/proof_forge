#!/usr/bin/env python3
"""Validate the four Phase-1 output contracts without overstating maturity."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path

# Engineering S7c bounds (metadata only; mirror Lean EngineeringDiskClosureV1).
MAX_CLOSURE_FILES = 1024
MAX_CLOSURE_FILE_BYTES = 64 * 1024 * 1024
MAX_CLOSURE_TOTAL_BYTES = 256 * 1024 * 1024
# Slack beyond exact expected direct children before fail-closed (mirror Lean).
MAX_DIR_ENTRY_SLACK = 8


def parent_dir_prefixes(relative: str) -> list[str]:
    parts = [p for p in relative.split("/") if p]
    out: list[str] = []
    acc: list[str] = []
    for part in parts[:-1]:
        acc.append(part)
        out.append("/".join(acc))
    return out


def expected_dirs_from_files(files: set[str]) -> set[str]:
    dirs: set[str] = set()
    for path in files:
        dirs.update(parent_dir_prefixes(path))
    return dirs


def _is_direct_child_of(parent: str, path: str) -> bool:
    if parent == "":
        return "/" not in path
    prefix = parent + "/"
    return path.startswith(prefix) and "/" not in path[len(prefix) :]


def expected_direct_child_count(
    rel: str, expected_files: set[str], expected_dirs: set[str]
) -> int:
    n = 0
    for path in expected_files:
        if _is_direct_child_of(rel, path):
            n += 1
    for path in expected_dirs:
        if _is_direct_child_of(rel, path):
            n += 1
    return n


def exact_physical_closure(
    root: Path,
    expected_files: set[str],
    expected_dirs: set[str] | None = None,
    *,
    label: str | None = None,
) -> None:
    """No-follow exact physical closure of regular files + intermediate dirs.

    Shared helper for every Counter/Accumulator target tree. Rejects symlinks,
    FIFO/socket/device/other nonregular entries, missing/extra files or dirs, and
    type mismatches. Does not inspect file contents. Deterministic scandir order.
    """
    tag = label or root.name
    if expected_dirs is None:
        expected_dirs = expected_dirs_from_files(expected_files)
    else:
        expected_dirs = set(expected_dirs)
    expected_files = set(expected_files)

    if len(expected_files) > MAX_CLOSURE_FILES:
        raise SystemExit(
            f"{tag}: too many closure files ({len(expected_files)} > {MAX_CLOSURE_FILES})"
        )

    try:
        root_st = os.lstat(root)
    except FileNotFoundError as exc:
        raise SystemExit(f"{tag}: missing staging root") from exc
    if stat.S_ISLNK(root_st.st_mode) or not stat.S_ISDIR(root_st.st_mode):
        raise SystemExit(f"{tag}: staging root is not a real directory")

    observed_files: set[str] = set()
    observed_dirs: set[str] = set()
    total_bytes = 0
    worklist: list[str] = [""]
    head = 0
    max_visits = len(expected_dirs) + len(expected_files) + 8
    visits = 0

    while head < len(worklist):
        visits += 1
        if visits > max_visits:
            raise SystemExit(f"{tag}: staging walk exceeded bounded worklist")
        rel = worklist[head]
        head += 1
        dir_path = root if rel == "" else root / rel
        try:
            dir_st = os.lstat(dir_path)
        except FileNotFoundError as exc:
            msg = "staging root is missing" if rel == "" else f"missing directory '{rel}'"
            raise SystemExit(f"{tag}: {msg}") from exc
        if stat.S_ISLNK(dir_st.st_mode) or not stat.S_ISDIR(dir_st.st_mode):
            msg = (
                "staging root is not a real directory"
                if rel == ""
                else f"path is not a directory '{rel}'"
            )
            raise SystemExit(f"{tag}: {msg}")

        try:
            with os.scandir(dir_path) as it:
                raw_entries = list(it)
        except OSError as exc:
            raise SystemExit(f"{tag}: cannot read directory '{rel or '.'}'") from exc
        max_entries = (
            expected_direct_child_count(rel, expected_files, expected_dirs)
            + MAX_DIR_ENTRY_SLACK
        )
        if len(raw_entries) > max_entries:
            dir_label = "." if rel == "" else rel
            raise SystemExit(
                f"{tag}: too many directory entries under '{dir_label}' "
                f"({len(raw_entries)} > {max_entries})"
            )
        entries = sorted(raw_entries, key=lambda e: e.name)

        for entry in entries:
            name = entry.name
            if name in (".", "..") or "/" in name or name == "":
                raise SystemExit(f"{tag}: invalid directory entry name under '{rel}'")
            child_rel = name if rel == "" else f"{rel}/{name}"
            try:
                child_st = entry.stat(follow_symlinks=False)
            except OSError as exc:
                raise SystemExit(f"{tag}: missing path '{child_rel}'") from exc
            mode = child_st.st_mode
            if stat.S_ISLNK(mode):
                raise SystemExit(f"{tag}: path is a symbolic link '{child_rel}'")
            if stat.S_ISDIR(mode):
                if child_rel not in expected_dirs:
                    raise SystemExit(f"{tag}: unexpected directory '{child_rel}'")
                observed_dirs.add(child_rel)
                worklist.append(child_rel)
            elif stat.S_ISREG(mode):
                if child_rel not in expected_files:
                    raise SystemExit(f"{tag}: unexpected file '{child_rel}'")
                size = child_st.st_size
                if size > MAX_CLOSURE_FILE_BYTES:
                    raise SystemExit(f"{tag}: file exceeds size limit '{child_rel}'")
                total_bytes += size
                if total_bytes > MAX_CLOSURE_TOTAL_BYTES:
                    raise SystemExit(
                        f"{tag}: total closure size exceeds limit at '{child_rel}'"
                    )
                observed_files.add(child_rel)
            else:
                raise SystemExit(f"{tag}: non-regular filesystem entry '{child_rel}'")

    missing_files = sorted(expected_files - observed_files)
    if missing_files:
        raise SystemExit(f"{tag}: missing regular file '{missing_files[0]}'")
    missing_dirs = sorted(expected_dirs - observed_dirs)
    if missing_dirs:
        raise SystemExit(f"{tag}: missing directory '{missing_dirs[0]}'")


_HEX64 = re.compile(r"[0-9a-f]{64}")
_ENGINEERING_OUTPUT_SCHEMA = "proof-forge.output.v1"
_ENGINEERING_OUTPUT_REQUIRED_KEYS = (
    "schemaVersion",
    "target",
    "codegenProfile",
    "artifactProgramName",
    "sourceHash",
    "semanticHash",
    "buildIdentityDigest",
    "planDigest",
    "supportClaimDigest",
    "engineeringRegistryRootDigest",
    "outputSetDigest",
    "deployable",
    "files",
)


def _require_hex64(manifest: dict, key: str, label: str) -> None:
    value = manifest.get(key, "")
    if not isinstance(value, str) or not _HEX64.fullmatch(value):
        raise SystemExit(f"{label}: invalid {key}")


def validate_engineering_output_manifest(manifest: dict, *, label: str) -> None:
    """Validate engineering proof-forge.output.v1 field surface (not formal)."""
    if not isinstance(manifest, dict):
        raise SystemExit(f"{label}: manifest must be an object")
    if set(manifest.keys()) != set(_ENGINEERING_OUTPUT_REQUIRED_KEYS):
        raise SystemExit(
            f"{label}: unexpected manifest keys {sorted(manifest.keys())}; "
            f"want {sorted(_ENGINEERING_OUTPUT_REQUIRED_KEYS)}"
        )
    if manifest["schemaVersion"] != _ENGINEERING_OUTPUT_SCHEMA:
        raise SystemExit(
            f"{label}: schemaVersion must be {_ENGINEERING_OUTPUT_SCHEMA!r}, "
            f"got {manifest['schemaVersion']!r}"
        )
    for key in (
        "sourceHash",
        "semanticHash",
        "buildIdentityDigest",
        "planDigest",
        "supportClaimDigest",
        "engineeringRegistryRootDigest",
        "outputSetDigest",
    ):
        _require_hex64(manifest, key, label)
    if not isinstance(manifest["target"], str) or not manifest["target"]:
        raise SystemExit(f"{label}: invalid target")
    if not isinstance(manifest["codegenProfile"], str) or not manifest["codegenProfile"]:
        raise SystemExit(f"{label}: invalid codegenProfile")
    if (
        not isinstance(manifest["artifactProgramName"], str)
        or not manifest["artifactProgramName"]
    ):
        raise SystemExit(f"{label}: invalid artifactProgramName")
    if not isinstance(manifest["deployable"], bool):
        raise SystemExit(f"{label}: deployable must be bool")
    if not isinstance(manifest["files"], list) or not all(
        isinstance(p, str) and p for p in manifest["files"]
    ):
        raise SystemExit(f"{label}: files must be a non-empty list of strings")
    if not manifest["files"]:
        raise SystemExit(f"{label}: files must be non-empty")
    if len(set(manifest["files"])) != len(manifest["files"]):
        raise SystemExit(f"{label}: files list has duplicates")
    if "manifest.json" in manifest["files"] or "evidence.json" in manifest["files"]:
        raise SystemExit(f"{label}: sidecars must not appear in files")


def _require_engineering_output_manifest(
    manifest: dict,
    *,
    target: str,
    codegen_profile: str,
    artifact_program_name: str,
    deployable: bool,
    files: list[str],
    label: str,
) -> None:
    validate_engineering_output_manifest(manifest, label=label)
    expected = {
        "schemaVersion": _ENGINEERING_OUTPUT_SCHEMA,
        "target": target,
        "codegenProfile": codegen_profile,
        "artifactProgramName": artifact_program_name,
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "buildIdentityDigest": manifest["buildIdentityDigest"],
        "planDigest": manifest["planDigest"],
        "supportClaimDigest": manifest["supportClaimDigest"],
        "engineeringRegistryRootDigest": manifest["engineeringRegistryRootDigest"],
        "outputSetDigest": manifest["outputSetDigest"],
        "deployable": deployable,
        "files": files,
    }
    if manifest != expected:
        raise SystemExit(f"{label}: manifest is invalid: {manifest}")


def load_manifest(root: Path, target: str) -> dict:
    path = root / target / "manifest.json"
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"missing {path}")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest["target"] != target:
        raise SystemExit(f"target mismatch in {path}")
    validate_engineering_output_manifest(manifest, label=target)
    expected_files = set(manifest["files"]) | {"manifest.json", "evidence.json"}
    exact_physical_closure(root / target, expected_files, label=target)
    return manifest


def validate_evm_accumulator(root: Path) -> dict:
    output = root / "evm-accumulator"
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise SystemExit(f"missing {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_files = [
        "Accumulator.yul",
        "Accumulator.abi.json",
        "Accumulator.bin",
    ]
    _require_engineering_output_manifest(
        manifest,
        target="evm",
        codegen_profile="evm-yul-solc-0.8.34-v1",
        artifact_program_name="Accumulator",
        deployable=True,
        files=expected_files,
        label="Accumulator EVM",
    )
    exact_physical_closure(
        output,
        set(expected_files) | {"manifest.json", "evidence.json"},
        label="evm-accumulator",
    )
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


def validate_solana_accumulator(root: Path, evm_manifest: dict) -> dict:
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
    exact_physical_closure(output, expected_names, label="solana-accumulator")
    forbidden_suffixes = {".s", ".elf", ".so", ".o", ".bin"}
    forbidden = sorted(
        name
        for name in expected_names
        if Path(name).suffix.lower() in forbidden_suffixes
    )
    if forbidden:
        raise SystemExit(
            f"Solana Accumulator emitted executable/assembler artifacts: {forbidden}"
        )

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _require_engineering_output_manifest(
        manifest,
        target="solana",
        codegen_profile="solana-sbpf-plan-v1",
        artifact_program_name="Accumulator",
        deployable=False,
        files=["Accumulator.sbpf-plan", "Accumulator.idl.json"],
        label="Solana Accumulator",
    )
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
        "fns": [],
        "events": [],
        "errors": [],
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
    return manifest


def validate_near_accumulator(
    root: Path, evm_manifest: dict, solana_manifest: dict
) -> dict:
    output = root / "near-accumulator"
    manifest_path = output / "manifest.json"
    evidence_path = output / "evidence.json"
    wat_path = output / "Accumulator.wat"
    abi_path = output / "Accumulator.near-abi.json"
    wasm_path = output / "Accumulator.wasm"
    expected_names = {
        "manifest.json",
        "evidence.json",
        "Accumulator.wat",
        "Accumulator.near-abi.json",
        "Accumulator.wasm",
    }
    exact_physical_closure(output, expected_names, label="near-accumulator")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _require_engineering_output_manifest(
        manifest,
        target="near",
        codegen_profile="near-wasm-raw-u64-v1",
        artifact_program_name="Accumulator",
        deployable=True,
        files=[
            "Accumulator.wat",
            "Accumulator.near-abi.json",
            "Accumulator.wasm",
        ],
        label="NEAR Accumulator",
    )
    for other_name, other_manifest in (
        ("EVM", evm_manifest),
        ("Solana", solana_manifest),
    ):
        for digest_name in ("sourceHash", "semanticHash"):
            if manifest[digest_name] != other_manifest[digest_name]:
                raise SystemExit(
                    f"Accumulator {digest_name} differs between NEAR and {other_name}: "
                    f"{manifest[digest_name]} != {other_manifest[digest_name]}"
                )

    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    expected_evidence = {
        "target": "near",
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "deployable": True,
        "note": (
            "wat2wasm 1.0.41 "
            "sha256=1c0791a1e06a2c5447976ebd2558b8505f65cb8f17e470f55dd4e7be3355b55e "
            "completed; runtime remains separate"
        ),
    }
    if evidence != expected_evidence:
        raise SystemExit(f"NEAR Accumulator evidence is invalid: {evidence}")

    expected_abi = {
        "schema": "proof-forge-near-abi/v1alpha1",
        "program": "Accumulator",
        "codegenProfile": "near-wasm-raw-u64-v1",
        "hostAbi": "near-host-abi-v1",
        "encoding": "packed-raw-little-endian-u64",
        "storage": {
            "markerKey": "pf:v1:layout",
            "layoutMarker": "0x6e2484750dd85e01",
            "initializerPayloadPolicy": "zero-all-fields",
            "fields": [
                {
                    "name": "total",
                    "sourceId": 0,
                    "key": "pf:v1:state:0",
                    "type": "u64-le",
                }
            ],
        },
        "exports": [
            {
                "name": "init",
                "mode": "initialize",
                "depositPolicy": "zero-required",
                "exactInputLen": 8,
                "args": [{"name": "seed", "type": "u64-le", "inputOffset": 0}],
                "returns": None,
            },
            {
                "name": "add",
                "mode": "mutate",
                "depositPolicy": "zero-required",
                "exactInputLen": 8,
                "args": [
                    {"name": "amount", "type": "u64-le", "inputOffset": 0}
                ],
                "returns": "u64-le",
            },
            {
                "name": "current",
                "mode": "view",
                "depositPolicy": "query-only",
                "exactInputLen": 0,
                "args": [],
                "returns": "u64-le",
            },
        ],
    }
    abi = json.loads(abi_path.read_text(encoding="utf-8"))
    if abi != expected_abi:
        raise SystemExit(f"NEAR Accumulator ABI is invalid: {abi}")

    expected_wat = """(module
  (import "env" "input" (func $pf_input (param i64)))
  (import "env" "register_len" (func $pf_register_len (param i64) (result i64)))
  (import "env" "read_register" (func $pf_read_register (param i64 i64)))
  (import "env" "storage_read" (func $pf_storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "value_return" (func $pf_value_return (param i64 i64)))
  (import "env" "attached_deposit" (func $pf_attached_deposit (param i64)))
  (import "env" "log_utf8" (func $pf_log_utf8 (param i64 i64)))
  (import "env" "panic_utf8" (func $pf_panic_utf8 (param i64 i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "pf:v1:layout")
  (data (i32.const 12) "pf:v1:state:0")
  (func (export "init") (local $t0 i64)
    (call $pf_input (i64.const 0))
    (if (i64.ne (call $pf_register_len (i64.const 0)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 0) (i64.const 32))
    (call $pf_attached_deposit (i64.const 40))
    (if (i64.ne (i64.load (i32.const 40)) (i64.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 48)) (i64.const 0)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 12) (i64.const 0) (i64.const 1)) (i64.const 0)) (then unreachable))
    (i64.store (i32.const 56) (i64.const 0))
    (if (i64.ne (call $pf_storage_write (i64.const 13) (i64.const 12) (i64.const 8) (i64.const 56) (i64.const 2)) (i64.const 0)) (then unreachable))
    (local.set $t0 (i64.load (i32.const 32)))
    (i64.store (i32.const 56) (local.get $t0))
    (if (i64.ne (call $pf_storage_write (i64.const 13) (i64.const 12) (i64.const 8) (i64.const 56) (i64.const 2)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 2)) (i64.const 8)) (then unreachable))
    (i64.store (i32.const 56) (i64.const 7936614081611980289))
    (if (i64.ne (call $pf_storage_write (i64.const 12) (i64.const 0) (i64.const 8) (i64.const 56) (i64.const 2)) (i64.const 0)) (then unreachable))
  )
  (func (export "add") (local $t0 i64) (local $t1 i64) (local $t2 i64) (local $t3 i64)
    (call $pf_input (i64.const 0))
    (if (i64.ne (call $pf_register_len (i64.const 0)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 0) (i64.const 32))
    (call $pf_attached_deposit (i64.const 40))
    (if (i64.ne (i64.load (i32.const 40)) (i64.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 48)) (i64.const 0)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 12) (i64.const 0) (i64.const 1)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 1)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 1) (i64.const 56))
    (if (i64.ne (i64.load (i32.const 56)) (i64.const 7936614081611980289)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 13) (i64.const 12) (i64.const 1)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 1)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 1) (i64.const 56))
    (local.set $t0 (i64.load (i32.const 56)))
    (local.set $t1 (i64.load (i32.const 32)))
    (local.set $t2 (i64.add (local.get $t0) (local.get $t1)))
    (if (i64.lt_u (local.get $t2) (local.get $t0)) (then unreachable))
    (i64.store (i32.const 56) (local.get $t2))
    (if (i64.ne (call $pf_storage_write (i64.const 13) (i64.const 12) (i64.const 8) (i64.const 56) (i64.const 2)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 2)) (i64.const 8)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 13) (i64.const 12) (i64.const 1)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 1)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 1) (i64.const 56))
    (local.set $t3 (i64.load (i32.const 56)))
    (i64.store (i32.const 56) (local.get $t3))
    (call $pf_value_return (i64.const 8) (i64.const 56))
  )
  (func (export "current") (local $t0 i64)
    (call $pf_input (i64.const 0))
    (if (i64.ne (call $pf_register_len (i64.const 0)) (i64.const 0)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 12) (i64.const 0) (i64.const 1)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 1)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 1) (i64.const 56))
    (if (i64.ne (i64.load (i32.const 56)) (i64.const 7936614081611980289)) (then unreachable))
    (if (i64.ne (call $pf_storage_read (i64.const 13) (i64.const 12) (i64.const 1)) (i64.const 1)) (then unreachable))
    (if (i64.ne (call $pf_register_len (i64.const 1)) (i64.const 8)) (then unreachable))
    (call $pf_read_register (i64.const 1) (i64.const 56))
    (local.set $t0 (i64.load (i32.const 56)))
    (i64.store (i32.const 56) (local.get $t0))
    (call $pf_value_return (i64.const 8) (i64.const 56))
  )
)
"""
    wat = wat_path.read_text(encoding="utf-8")
    if wat != expected_wat:
        raise SystemExit("NEAR Accumulator WAT does not match the accepted contract")

    wasm = wasm_path.read_bytes()
    if wasm[:8] != b"\x00asm\x01\x00\x00\x00":
        raise SystemExit("NEAR Accumulator artifact has an invalid Wasm header/version")
    if len(wasm) != 859:
        raise SystemExit(f"NEAR Accumulator Wasm has invalid size: {len(wasm)}")
    wasm_digest = hashlib.sha256(wasm).hexdigest()
    if wasm_digest != "889bccfc92c914deb6d1f68510bab36be2f1c62dbb601457e084683aa27250a9":
        raise SystemExit(f"NEAR Accumulator Wasm digest is invalid: {wasm_digest}")
    return manifest


def validate_noir_bundle(
    root: Path,
    directory: str,
    program: str,
    state_name: str,
    init_param: str,
    mutate_name: str,
    mutate_param: str,
    view_name: str,
    plan_hash: str,
    peer_manifests=(),
) -> dict:
    output = root / directory
    interface_name = f"{program}.noir-relations.json"
    relation_stems = ("r0-init", f"r1-{mutate_name}", f"r2-{view_name}")
    logical_files = [interface_name]
    for stem in relation_stems:
        logical_files.extend(
            [f"relations/{stem}/src/main.nr", f"relations/{stem}/Nargo.toml"]
        )
    expected_files = {"manifest.json", "evidence.json", *logical_files}
    expected_dirs = expected_dirs_from_files(expected_files)
    # Explicit intermediate package dirs (relations/, relations/<stem>/, src/).
    expected_dirs.update({"relations"})
    for stem in relation_stems:
        expected_dirs.update({f"relations/{stem}", f"relations/{stem}/src"})
    exact_physical_closure(
        output, expected_files, expected_dirs, label=f"noir-{program}"
    )
    forbidden_suffixes = {".acir", ".proof", ".vk", ".witness"}
    forbidden = sorted(
        relative
        for relative in expected_files
        if Path(relative).suffix.lower() in forbidden_suffixes
    )
    if forbidden:
        raise SystemExit(f"Noir source-only bundle contains proof-stage artifacts: {forbidden}")

    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    _require_engineering_output_manifest(
        manifest,
        target="noir",
        codegen_profile="noir-source-u64-relations-v1",
        artifact_program_name=program,
        deployable=False,
        files=logical_files,
        label=f"Noir {program}",
    )
    for peer_name, peer_manifest in peer_manifests:
        for digest_name in ("sourceHash", "semanticHash"):
            if manifest[digest_name] != peer_manifest[digest_name]:
                raise SystemExit(
                    f"{program} {digest_name} differs between Noir and {peer_name}: "
                    f"{manifest[digest_name]} != {peer_manifest[digest_name]}"
                )

    evidence = json.loads((output / "evidence.json").read_text(encoding="utf-8"))
    expected_evidence = {
        "target": "noir",
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "deployable": False,
        "note": (
            "no approved and digest-pinned Noir compiler/proving backend is configured; "
            "relation source/schema were emitted without ACIR, witness execution, proof, "
            "or verification"
        ),
    }
    if evidence != expected_evidence:
        raise SystemExit(f"Noir {program} evidence is invalid: {evidence}")

    def input_binding(
        name: str,
        source_name: str,
        role: str,
        value_type: str,
        source_id=None,
    ) -> dict:
        return {
            "name": name,
            "sourceName": source_name,
            "sourceId": source_id,
            "role": role,
            "visibility": "public",
            "type": value_type,
        }

    init_inputs = [
        input_binding("pre_initialized", "initialized", "pre-initialized", "bool"),
        input_binding("arg_p0", init_param, "parameter", "u64", 0),
        input_binding("post_s0", state_name, "post-state", "u64", 0),
        input_binding("post_initialized", "initialized", "post-initialized", "bool"),
    ]
    mutate_inputs = [
        input_binding("pre_initialized", "initialized", "pre-initialized", "bool"),
        input_binding("pre_s0", state_name, "pre-state", "u64", 0),
        input_binding("arg_p0", mutate_param, "parameter", "u64", 0),
        input_binding("post_s0", state_name, "post-state", "u64", 0),
        input_binding("post_initialized", "initialized", "post-initialized", "bool"),
        input_binding("result", "result", "result", "u64"),
    ]
    view_inputs = [
        input_binding("pre_initialized", "initialized", "pre-initialized", "bool"),
        input_binding("pre_s0", state_name, "pre-state", "u64", 0),
        input_binding("post_s0", state_name, "post-state", "u64", 0),
        input_binding("post_initialized", "initialized", "post-initialized", "bool"),
        input_binding("result", "result", "result", "u64"),
    ]
    expected_interface = {
        "schema": "proof-forge-noir-relations/v1alpha1",
        "program": program,
        "codegenProfile": "noir-source-u64-relations-v1",
        "sourceDialect": "noir-native-u64-relations-v1",
        "sourceHash": manifest["sourceHash"],
        "semanticHash": manifest["semanticHash"],
        "planHash": plan_hash,
        "artifactKind": "source-only",
        "stateContinuity": "external-public-pre-post",
        "arithmetic": "native-checked-u64",
        "proofStatus": "not-produced",
        "relations": [
            {
                "index": 0,
                "name": "init",
                "mode": "initialize",
                "package": "relations/r0-init",
                "operationCount": 3,
                "inputs": init_inputs,
            },
            {
                "index": 1,
                "name": mutate_name,
                "mode": "mutate",
                "package": f"relations/r1-{mutate_name}",
                "operationCount": 5,
                "inputs": mutate_inputs,
            },
            {
                "index": 2,
                "name": view_name,
                "mode": "view",
                "package": f"relations/r2-{view_name}",
                "operationCount": 4,
                "inputs": view_inputs,
            },
        ],
    }
    interface = json.loads((output / interface_name).read_text(encoding="utf-8"))
    if interface != expected_interface:
        raise SystemExit(f"Noir {program} relation interface is invalid: {interface}")

    expected_sources = {
        "r0-init": (
            "fn main(pre_initialized: pub bool, arg_p0: pub u64, post_s0: pub u64, "
            "post_initialized: pub bool) {\n"
            "    assert(pre_initialized == false);\n"
            "    assert(post_s0 == arg_p0);\n"
            "    assert(post_initialized == true);\n"
            "}\n"
        ),
        f"r1-{mutate_name}": (
            "fn main(pre_initialized: pub bool, pre_s0: pub u64, arg_p0: pub u64, "
            "post_s0: pub u64, post_initialized: pub bool, result: pub u64) {\n"
            "    assert(pre_initialized == true);\n"
            "    let t0: u64 = pre_s0 + arg_p0;\n"
            "    assert(post_s0 == t0);\n"
            "    assert(post_initialized == true);\n"
            "    assert(result == t0);\n"
            "}\n"
        ),
        f"r2-{view_name}": (
            "fn main(pre_initialized: pub bool, pre_s0: pub u64, post_s0: pub u64, "
            "post_initialized: pub bool, result: pub u64) {\n"
            "    assert(pre_initialized == true);\n"
            "    assert(post_s0 == pre_s0);\n"
            "    assert(post_initialized == true);\n"
            "    assert(result == pre_s0);\n"
            "}\n"
        ),
    }
    for index, stem in enumerate(relation_stems):
        source = (output / f"relations/{stem}/src/main.nr").read_text(encoding="utf-8")
        if source != expected_sources[stem]:
            raise SystemExit(f"Noir {program} relation source is invalid: {stem}")
        package = (output / f"relations/{stem}/Nargo.toml").read_text(encoding="utf-8")
        expected_package = (
            "[package]\n"
            f'name = "pf_relation_{index}"\n'
            'type = "bin"\n'
            'authors = ["ProofForge V2"]\n'
        )
        if package != expected_package:
            raise SystemExit(f"Noir {program} package manifest is invalid: {stem}")
    return manifest


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
    validate_noir_bundle(
        root,
        "noir",
        "Counter",
        "count",
        "initial",
        "increment",
        "delta",
        "get",
        "3355c6eebe0e59913f51eda0fe2474f07e1a1947837f77c3f2a6a51660ced0e9",
        (("EVM", manifests["evm"]), ("Solana", manifests["solana"]), ("NEAR", manifests["near"])),
    )
    evm_accumulator = validate_evm_accumulator(root)
    solana_accumulator = validate_solana_accumulator(root, evm_accumulator)
    near_accumulator = validate_near_accumulator(root, evm_accumulator, solana_accumulator)
    validate_noir_bundle(
        root,
        "noir-accumulator",
        "Accumulator",
        "total",
        "seed",
        "add",
        "amount",
        "current",
        "f58772dc5241fb2c5b5558a216a2ae448c42425d32a3b70185611a4c74d2c08e",
        (
            ("EVM", evm_accumulator),
            ("Solana", solana_accumulator),
            ("NEAR", near_accumulator),
        ),
    )
    print("artifact-validation: ok")


if __name__ == "__main__":
    main()
