#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


ADDRESS_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")
HASH_RE = re.compile(r"^0x[0-9a-fA-F]{64}$")
SUPPORTED_CONSTRUCTOR_TYPES = {"uint256", "uint64", "uint32", "bool", "bytes32", "address", "string", "bytes", "uint256[]"}
STATIC_CONSTRUCTOR_TYPES = {"uint256", "uint64", "uint32", "bool", "bytes32", "address"}
DYNAMIC_CONSTRUCTOR_TYPES = {"string", "bytes", "uint256[]"}
SUPPORTED_CONSTRUCTOR_ARG_SOURCES = {"--evm-constructor-args-hex", "--evm-constructor-arg"}


def fail(message: str) -> None:
    raise SystemExit(f"evm-deploy-run-validate: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def expect_array(value: Any, name: str) -> list:
    expect(isinstance(value, list), f"{name} must be an array")
    return value


def normalize_hex(value: str, name: str) -> str:
    text = value[2:] if value.startswith(("0x", "0X")) else value
    expect(all(ch in "0123456789abcdefABCDEF" for ch in text), f"{name} must contain only hex digits")
    expect(len(text) % 2 == 0, f"{name} must have an even number of hex digits")
    return text.lower()


def parse_hex_quantity(value: Any, name: str) -> int:
    text = expect_string(value, name)
    expect(text.startswith(("0x", "0X")), f"{name} must be a hex quantity")
    digits = text[2:]
    expect(digits and all(ch in "0123456789abcdefABCDEF" for ch in digits), f"{name} must contain hex digits")
    return int(digits, 16)


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


def expect_hex_file(path: Path, name: str) -> str:
    value = path.read_text().strip()
    expect(value, f"{name} must not be empty")
    expect(all(ch in "0123456789abcdefABCDEF" for ch in value), f"{name} must contain hex")
    expect(len(value) % 2 == 0, f"{name} must have an even number of hex digits")
    return value.lower()


def read_push_value(init_hex: str, offset: int, name: str) -> tuple[int, int]:
    expect(offset + 2 <= len(init_hex), f"{name} is missing PUSH opcode")
    opcode = int(init_hex[offset : offset + 2], 16)
    expect(0x60 <= opcode <= 0x7F, f"{name} must use PUSH1..PUSH32")
    width = opcode - 0x5F
    data_start = offset + 2
    data_end = data_start + width * 2
    expect(data_end <= len(init_hex), f"{name} PUSH data is truncated")
    return int(init_hex[data_start:data_end], 16), data_end


def validate_constructor_args(constructor_args: list, name: str, expected_source: str | None) -> str:
    if expected_source is not None:
        expect(
            expected_source in SUPPORTED_CONSTRUCTOR_ARG_SOURCES,
            "--expect-constructor-args-source is unsupported",
        )
    if constructor_args == []:
        return ""
    expect(len(constructor_args) == 1, f"{name} supports one ABI-encoded argument blob")
    arg = expect_object(constructor_args[0], f"{name}[0]")
    expect(arg.get("encoding") == "abi-encoded", f"{name}[0].encoding mismatch")
    actual_hex = normalize_hex(expect_string(arg.get("hex"), f"{name}[0].hex"), f"{name}[0].hex")
    arg_bytes = bytes.fromhex(actual_hex)
    expect(arg.get("bytes") == len(arg_bytes), f"{name}[0].bytes mismatch")
    expect(arg.get("sha256") == hashlib.sha256(arg_bytes).hexdigest(), f"{name}[0].sha256 mismatch")
    source = expect_string(arg.get("source"), f"{name}[0].source")
    expect(source in SUPPORTED_CONSTRUCTOR_ARG_SOURCES, f"{name}[0].source unsupported")
    if expected_source is not None:
        expect(source == expected_source, f"{name}[0].source mismatch")
    return actual_hex


def parse_expected_constructor_param(value: str) -> dict:
    if ":" not in value:
        fail("--expect-constructor-param expects name:type")
    name, abi_type = value.split(":", 1)
    expect(name and abi_type, "--expect-constructor-param expects name:type")
    return {"name": name, "type": abi_type}


def expected_constructor_param_encoding(abi_type: str) -> str:
    if abi_type in STATIC_CONSTRUCTOR_TYPES:
        return "abi-static-word"
    if abi_type in {"string", "bytes"}:
        return "abi-dynamic-bytes"
    if abi_type == "uint256[]":
        return "abi-dynamic-array"
    fail(f"unsupported constructor ABI type '{abi_type}'")


def constructor_schema_has_dynamic(params: list[dict]) -> bool:
    return any(param["type"] in DYNAMIC_CONSTRUCTOR_TYPES for param in params)


def validate_constructor_abi(abi: dict, expected_params: list[dict]) -> list[dict]:
    constructor = expect_object(abi.get("constructor"), "deploy manifest abi.constructor")
    params = expect_array(constructor.get("params"), "deploy manifest abi.constructor.params")
    expect(constructor.get("encoding") == "abi", "deploy manifest abi.constructor.encoding mismatch")
    actual_params = []
    for idx, param in enumerate(params):
        param = expect_object(param, f"deploy manifest abi.constructor.params[{idx}]")
        name = expect_string(param.get("name"), f"deploy manifest abi.constructor.params[{idx}].name")
        abi_type = expect_string(param.get("type"), f"deploy manifest abi.constructor.params[{idx}].type")
        expect(abi_type in SUPPORTED_CONSTRUCTOR_TYPES, f"deploy manifest abi.constructor.params[{idx}].type unsupported")
        expect(
            param.get("encoding") == expected_constructor_param_encoding(abi_type),
            f"deploy manifest abi.constructor.params[{idx}].encoding mismatch",
        )
        expect(param.get("slotBytes") == 32, f"deploy manifest abi.constructor.params[{idx}].slotBytes must be 32")
        if abi_type == "uint256[]":
            expect(
                param.get("elementType") == "uint256",
                f"deploy manifest abi.constructor.params[{idx}].elementType must be uint256",
            )
        actual_params.append({"name": name, "type": abi_type})
    if expected_params:
        expect(actual_params == expected_params, "deploy manifest abi.constructor.params mismatch")
    return actual_params


def validate_constructor_schema_args(params: list[dict], constructor_args_hex: str) -> None:
    if not params or not constructor_args_hex:
        return
    actual_bytes = len(constructor_args_hex) // 2
    if constructor_schema_has_dynamic(params):
        min_bytes = len(params) * 32
        expect(
            actual_bytes >= min_bytes,
            f"deploy manifest abi.constructor.params expects at least {min_bytes} constructor arg bytes, got {actual_bytes}",
        )
        return
    expected_bytes = len(params) * 32
    expect(
        actual_bytes == expected_bytes,
        f"deploy manifest abi.constructor.params expects {expected_bytes} constructor arg bytes, got {actual_bytes}",
    )


def validate_deployment_init_code(init_hex: str, runtime_hex: str, constructor_args_hex: str, prefix: str) -> None:
    runtime_size = len(runtime_hex) // 2
    size, offset = read_push_value(init_hex, 0, f"{prefix}.runtimeSize")
    code_offset, offset = read_push_value(init_hex, offset, f"{prefix}.codeOffset")
    expect(init_hex[offset : offset + 6].lower() == "600039", f"{prefix} must copy runtime to memory")
    offset += 6
    return_size, offset = read_push_value(init_hex, offset, f"{prefix}.returnSize")
    expect(init_hex[offset : offset + 6].lower() == "6000f3", f"{prefix} must return copied runtime")
    offset += 6
    expect(size == runtime_size, f"{prefix} runtime size mismatch")
    expect(return_size == runtime_size, f"{prefix} return size mismatch")
    expect(code_offset == offset // 2, f"{prefix} code offset mismatch")
    runtime_end = offset + len(runtime_hex)
    expect(init_hex[offset:runtime_end].lower() == runtime_hex, f"{prefix} runtime segment mismatch")
    expect(init_hex[runtime_end:].lower() == constructor_args_hex, f"{prefix} constructor args suffix mismatch")


def expect_address(value: Any, name: str) -> str:
    text = expect_string(value, name)
    expect(ADDRESS_RE.match(text) is not None, f"{name} must be an EVM address")
    return text.lower()


def expect_hash(value: Any, name: str) -> str:
    text = expect_string(value, name)
    expect(HASH_RE.match(text) is not None, f"{name} must be a 32-byte hash")
    return text.lower()


def unwrap_rpc_result(value: Any, name: str) -> dict:
    obj = expect_object(value, name)
    if "result" in obj:
        return expect_object(obj.get("result"), f"{name}.result")
    return obj


def validate_chain_profile(manifest: dict, run: dict, expected_profile: str | None, expected_chain_id: int) -> None:
    profile_value = manifest.get("chainProfile")
    deployment = expect_object(manifest.get("deployment"), "deploy manifest deployment")

    if profile_value is None:
        expect(deployment.get("profileId") is None, "deploy manifest deployment.profileId must be null without chain profile")
        expect(deployment.get("chainId") is None, "deploy manifest deployment.chainId must be null without chain profile")
        expect(deployment.get("networkName") is None, "deploy manifest deployment.networkName must be null without chain profile")
        expect(expect_array(deployment.get("rpcUrls"), "deploy manifest deployment.rpcUrls") == [], "deploy manifest deployment.rpcUrls must be empty without chain profile")
    else:
        manifest_profile = expect_object(profile_value, "deploy manifest chainProfile")
        manifest_profile_id = expect_string(manifest_profile.get("id"), "deploy manifest chainProfile.id")
        expect(manifest_profile.get("targetId") == "evm", "deploy manifest chainProfile.targetId must be evm")
        expect_string(manifest_profile.get("networkName"), "deploy manifest chainProfile.networkName")
        manifest_chain_id = manifest_profile.get("chainId")
        expect(isinstance(manifest_chain_id, int), "deploy manifest chainProfile.chainId must be an integer")
        expect_string(manifest_profile.get("nativeCurrencySymbol"), "deploy manifest chainProfile.nativeCurrencySymbol")
        for field_name in ("rpcUrls", "websocketUrls", "sequencerUrls", "notes"):
            values = expect_array(manifest_profile.get(field_name), f"deploy manifest chainProfile.{field_name}")
            for idx, value in enumerate(values):
                expect_string(value, f"deploy manifest chainProfile.{field_name}[{idx}]")
        expect(deployment.get("profileId") == manifest_profile_id, "deploy manifest deployment.profileId mismatch")
        expect(deployment.get("chainId") == manifest_chain_id, "deploy manifest deployment.chainId mismatch")
        expect(deployment.get("networkName") == manifest_profile.get("networkName"), "deploy manifest deployment.networkName mismatch")
        expect(deployment.get("rpcUrls") == manifest_profile.get("rpcUrls"), "deploy manifest deployment.rpcUrls mismatch")

    profile = expect_object(run.get("chainProfile"), "deploy run chainProfile")
    profile_id = expect_string(profile.get("id"), "deploy run chainProfile.id")
    if expected_profile is not None:
        expect(profile_id == expected_profile, "deploy run chainProfile.id mismatch")
    expect(profile.get("targetId") == "evm", "deploy run chainProfile.targetId must be evm")
    expect_string(profile.get("networkName"), "deploy run chainProfile.networkName")
    chain_id = profile.get("chainId")
    expect(isinstance(chain_id, int), "deploy run chainProfile.chainId must be an integer")
    expect(chain_id == expected_chain_id, "deploy run chainProfile.chainId must match deploy-run chain id")
    expect_string(profile.get("nativeCurrencySymbol"), "deploy run chainProfile.nativeCurrencySymbol")
    for field_name in ("rpcUrls", "websocketUrls", "sequencerUrls", "notes"):
        values = expect_array(profile.get(field_name), f"deploy run chainProfile.{field_name}")
        for idx, value in enumerate(values):
            expect_string(value, f"deploy run chainProfile.{field_name}[{idx}]")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expect-fixture", default="Counter")
    parser.add_argument("--expect-chain-id", type=int, default=31337)
    parser.add_argument("--expect-chain-profile")
    parser.add_argument("--expect-contract-name", default="Counter")
    parser.add_argument("--expect-constructor-args-source")
    parser.add_argument("--expect-constructor-param", action="append", default=[])
    parser.add_argument("deploy_run")
    args = parser.parse_args()

    root = Path(args.root)
    deploy_run_path = Path(args.deploy_run)
    run = expect_object(json.loads(deploy_run_path.read_text()), "deploy run")
    expected_constructor_params = [
        parse_expected_constructor_param(value) for value in args.expect_constructor_param
    ]

    expect(run.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(run.get("kind") == "proof-forge-evm-deploy-run", "kind mismatch")
    expect(run.get("target") == "evm", "target must be evm")
    expect(run.get("targetFamily") == "evm", "targetFamily mismatch")
    expect(run.get("fixture") == args.expect_fixture, "fixture mismatch")
    expect(run.get("contractName") == args.expect_contract_name, "contractName mismatch")

    deploy_manifest_path = file_entry(
        root,
        expect_object(run.get("deployManifest"), "deployManifest"),
        "deployManifest",
    )
    manifest = expect_object(json.loads(deploy_manifest_path.read_text()), "deploy manifest")
    expect(manifest.get("kind") == "proof-forge-evm-deploy-manifest", "deploy manifest kind mismatch")
    expect(manifest.get("fixture") == args.expect_fixture, "deploy manifest fixture mismatch")
    expect(manifest.get("contractName") == args.expect_contract_name, "deploy manifest contractName mismatch")
    validate_chain_profile(manifest, run, args.expect_chain_profile, args.expect_chain_id)
    constructor_params = validate_constructor_abi(
        expect_object(manifest.get("abi"), "deploy manifest abi"),
        expected_constructor_params,
    )

    runtime_path = file_entry(
        root,
        expect_object(run.get("runtimeBytecode"), "runtimeBytecode"),
        "runtimeBytecode",
    )
    init_code_path = file_entry(
        root,
        expect_object(run.get("initCode"), "initCode"),
        "initCode",
    )
    send_receipt_path = file_entry(
        root,
        expect_object(run.get("castSendReceipt"), "castSendReceipt"),
        "castSendReceipt",
    )
    creation_tx_path = file_entry(
        root,
        expect_object(run.get("creationTransaction"), "creationTransaction"),
        "creationTransaction",
    )
    initialize_receipt_path = file_entry(
        root,
        expect_object(run.get("initializeReceipt"), "initializeReceipt"),
        "initializeReceipt",
    )

    manifest_inputs = expect_object(manifest.get("inputs"), "deploy manifest inputs")
    manifest_runtime = file_entry(root, expect_object(manifest_inputs.get("bytecode"), "inputs.bytecode"), "inputs.bytecode")
    manifest_init = file_entry(root, expect_object(manifest_inputs.get("initCode"), "inputs.initCode"), "inputs.initCode")
    expect(manifest_runtime.resolve() == runtime_path.resolve(), "runtimeBytecode must match deploy manifest")
    expect(manifest_init.resolve() == init_code_path.resolve(), "initCode must match deploy manifest")

    runtime_hex = expect_hex_file(runtime_path, "runtimeBytecode").lower()
    init_hex = expect_hex_file(init_code_path, "initCode").lower()
    creation = expect_object(manifest.get("creation"), "deploy manifest creation")
    constructor_args = expect_array(creation.get("constructorArgs"), "deploy manifest creation.constructorArgs")
    constructor_args_hex = validate_constructor_args(
        constructor_args,
        "deploy manifest creation.constructorArgs",
        args.expect_constructor_args_source,
    )
    validate_constructor_schema_args(constructor_params, constructor_args_hex)
    expect(run.get("constructorAbi") == manifest["abi"]["constructor"], "constructorAbi must match deploy manifest")
    expect(run.get("constructorArgs") == constructor_args, "constructorArgs must match deploy manifest")
    validate_deployment_init_code(init_hex, runtime_hex, constructor_args_hex, "initCode")

    network = expect_object(run.get("network"), "network")
    network_kind = expect_string(network.get("kind"), "network.kind")
    profile_value = run.get("chainProfile")
    profile_id = profile_value.get("id") if isinstance(profile_value, dict) else None
    expected_network_kind = "anvil" if profile_id == "anvil-local" else "chain-profile"
    expect(network_kind == expected_network_kind, "network.kind does not match chain profile")
    expect(network.get("chainId") == args.expect_chain_id, "network.chainId mismatch")
    expect_string(network.get("rpcUrl"), "network.rpcUrl")

    deployer = expect_object(run.get("deployer"), "deployer")
    deployer_address = expect_address(deployer.get("address"), "deployer.address")

    transaction = expect_object(run.get("transaction"), "transaction")
    expect(transaction.get("status") == "0x1", "transaction.status must be 0x1")
    tx_hash = expect_hash(transaction.get("hash"), "transaction.hash")
    expect_hash(transaction.get("blockHash"), "transaction.blockHash")
    expect_address(transaction.get("from"), "transaction.from")
    expect(transaction.get("to") is None, "transaction.to must be null for contract creation")
    contract_address = expect_address(transaction.get("contractAddress"), "transaction.contractAddress")
    expect(transaction.get("from").lower() == deployer_address, "transaction.from must match deployer.address")
    expect(isinstance(transaction.get("blockNumber"), int) and transaction["blockNumber"] >= 1, "transaction.blockNumber must be positive")
    expect(isinstance(transaction.get("gasUsed"), int) and transaction["gasUsed"] > 0, "transaction.gasUsed must be positive")

    receipt = expect_object(json.loads(send_receipt_path.read_text()), "cast send receipt")
    expect(receipt.get("transactionHash", "").lower() == tx_hash, "cast send transactionHash mismatch")
    expect(receipt.get("contractAddress", "").lower() == contract_address, "cast send contractAddress mismatch")
    expect(receipt.get("status") == "0x1", "cast send status must be 0x1")

    creation_tx = unwrap_rpc_result(json.loads(creation_tx_path.read_text()), "creation transaction")
    expect(expect_hash(creation_tx.get("hash"), "creation transaction.hash") == tx_hash, "creation transaction.hash mismatch")
    expect(expect_address(creation_tx.get("from"), "creation transaction.from") == deployer_address, "creation transaction.from mismatch")
    expect(creation_tx.get("to") is None, "creation transaction.to must be null for contract creation")
    expect(expect_hash(creation_tx.get("blockHash"), "creation transaction.blockHash") == transaction["blockHash"].lower(), "creation transaction.blockHash mismatch")
    expect(parse_hex_quantity(creation_tx.get("blockNumber"), "creation transaction.blockNumber") == transaction["blockNumber"], "creation transaction.blockNumber mismatch")
    tx_input = creation_tx.get("input", creation_tx.get("data"))
    expect(normalize_hex(expect_string(tx_input, "creation transaction.input"), "creation transaction.input") == init_hex, "creation transaction.input must match initCode")

    initialize_receipt = expect_object(json.loads(initialize_receipt_path.read_text()), "initialize receipt")
    expect(initialize_receipt.get("status") == "0x1", "initialize receipt status must be 0x1")

    deployed_code = expect_object(run.get("deployedCode"), "deployedCode")
    expect(expect_address(deployed_code.get("address"), "deployedCode.address") == contract_address, "deployedCode.address mismatch")
    expect(deployed_code.get("runtimeBytecodeMatches") is True, "deployedCode.runtimeBytecodeMatches must be true")
    expect(deployed_code.get("sha256") == hashlib.sha256(bytes.fromhex(runtime_hex)).hexdigest(), "deployedCode.sha256 mismatch")
    expect(deployed_code.get("bytes") == len(runtime_hex) // 2, "deployedCode.bytes mismatch")

    calls = expect_object(run.get("calls"), "calls")
    expect(calls.get("initialGet") == "0", "calls.initialGet mismatch")
    expect(calls.get("afterInitializeGet") == "0", "calls.afterInitializeGet mismatch")
    expect(calls.get("afterIncrementGet") == "1", "calls.afterIncrementGet mismatch")
    expect(calls.get("afterSecondIncrementGet") == "2", "calls.afterSecondIncrementGet mismatch")

    validation = expect_object(run.get("validation"), "validation")
    anvil_started = validation.get("anvilStarted")
    expect(anvil_started in {"passed", "skipped"}, "validation.anvilStarted must be passed or skipped")
    if network_kind != "anvil":
        expect(anvil_started == "skipped", "public chain profile cannot report Anvil startup")
    for key in (
        "chainId",
        "castCreate",
        "creationTransaction",
        "receipt",
        "runtimeCodeMatch",
        "counterLifecycle",
        "artifactMetadata",
    ):
        expect(validation.get(key) == "passed", f"validation.{key} must be passed")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
