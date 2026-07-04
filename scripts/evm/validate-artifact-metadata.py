#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Optional


REQUIRED_ARTIFACTS = ("yul", "bytecode", "initCode", "deployManifest")
REQUIRED_VALIDATIONS = ("solcStrictAssembly", "bytecodeGeneration", "initCodeGeneration", "deployManifest")
SUPPORTED_CONSTRUCTOR_TYPES = {"uint256", "uint64", "uint32", "bool", "bytes32", "address", "string", "bytes", "uint256[]"}
STATIC_CONSTRUCTOR_TYPES = {"uint256", "uint64", "uint32", "bool", "bytes32", "address"}
DYNAMIC_CONSTRUCTOR_TYPES = {"string", "bytes", "uint256[]"}
SUPPORTED_CONSTRUCTOR_ARG_SOURCES = {"--evm-constructor-args-hex", "--evm-constructor-arg"}
SUPPORTED_ENTRYPOINT_WORD_TYPES = {"uint256", "uint32", "bool", "bytes32", "address", "bytes", "string"}
SELECTOR_RE = re.compile(r"^[0-9a-fA-F]{8}$")
TOPIC_RE = re.compile(r"^(0x)?[0-9a-fA-F]{64}$")
SIGNATURE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\((.*)\)$")


def fail(message: str) -> None:
    raise SystemExit(f"evm-metadata-validate: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def expect_object(value: Any, name: str) -> dict:
    expect(isinstance(value, dict), f"{name} must be an object")
    return value


def expect_array(value: Any, name: str) -> list:
    expect(isinstance(value, list), f"{name} must be an array")
    return value


def expect_string(value: Any, name: str) -> str:
    expect(isinstance(value, str) and value, f"{name} must be a non-empty string")
    return value


def expect_optional_string(value: Any, name: str) -> None:
    expect(value is None or (isinstance(value, str) and value), f"{name} must be null or a non-empty string")


def normalize_hex(value: str, name: str) -> str:
    text = value[2:] if value.startswith(("0x", "0X")) else value
    expect(all(ch in "0123456789abcdefABCDEF" for ch in text), f"{name} must contain only hex digits")
    expect(len(text) % 2 == 0, f"{name} must have an even number of hex digits")
    return text.lower()


def resolve_path(root: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return root / path


def file_entry(root: Path, entry: dict, name: str, prefix: str = "artifacts") -> Path:
    path = resolve_path(root, expect_string(entry.get("path"), f"{prefix}.{name}.path"))
    expect(path.is_file(), f"{prefix}.{name}.path does not exist: {path}")
    data = path.read_bytes()
    expect(entry.get("bytes") == len(data), f"{prefix}.{name}.bytes mismatch")
    expect(
        entry.get("sha256") == hashlib.sha256(data).hexdigest(),
        f"{prefix}.{name}.sha256 mismatch",
    )
    return path


def parse_expected_mapping(value: str, option: str) -> tuple[str, str]:
    if ":" not in value:
        fail(f"{option} expects name:selector")
    name, selector = value.split(":", 1)
    if not name or not selector:
        fail(f"{option} expects name:selector")
    return name, normalize_selector(selector, option)


def parse_expected_event(value: str) -> tuple[str, str]:
    if ":" not in value:
        fail("--expect-event expects name:signature")
    name, signature = value.split(":", 1)
    expect(name and signature, "--expect-event expects name:signature")
    expect(signature.startswith(f"{name}("), "--expect-event name must match signature")
    signature_arg_count(signature, "--expect-event signature")
    return name, signature


def parse_expected_entrypoint_abi(value: str) -> tuple[str, str, int, int]:
    parts = value.split(":")
    if len(parts) != 4:
        fail("--expect-entrypoint-abi expects name:signature:calldataWords:returnWords")
    name, signature, calldata_words_text, return_words_text = parts
    expect(name and signature, "--expect-entrypoint-abi expects name:signature:calldataWords:returnWords")
    expect(signature.startswith(f"{name}("), "--expect-entrypoint-abi name must match signature")
    signature_arg_count(signature, "--expect-entrypoint-abi signature")
    try:
        calldata_words = int(calldata_words_text)
        return_words = int(return_words_text)
    except ValueError:
        fail("--expect-entrypoint-abi word counts must be integers")
    expect(calldata_words >= 0, "--expect-entrypoint-abi calldataWords must be non-negative")
    expect(return_words >= 0, "--expect-entrypoint-abi returnWords must be non-negative")
    return name, signature, calldata_words, return_words


def normalize_selector(value: str, name: str) -> str:
    selector = value[2:] if value.startswith(("0x", "0X")) else value
    expect(SELECTOR_RE.fullmatch(selector) is not None, f"{name} must be an 8-hex-digit selector")
    return selector.lower()


def normalize_topic(value: str, name: str) -> str:
    expect(isinstance(value, str) and TOPIC_RE.fullmatch(value) is not None, f"{name} must be a 32-byte hex topic")
    topic = value[2:] if value.startswith(("0x", "0X")) else value
    return "0x" + topic.lower()


def cast_keccak(signature: str) -> str:
    try:
        result = subprocess.run(
            ["cast", "keccak", signature],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        fail("cast not found on PATH; event topic validation requires Foundry cast")
    except subprocess.CalledProcessError as exc:
        fail(f"cast keccak failed for {signature}: {exc.stderr.strip() or exc.stdout.strip()}")
    return normalize_topic(result.stdout.strip(), f"cast keccak {signature}")


def cast_sig(signature: str) -> str:
    try:
        result = subprocess.run(
            ["cast", "sig", signature],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        fail("cast not found on PATH; entrypoint selector validation requires Foundry cast")
    except subprocess.CalledProcessError as exc:
        fail(f"cast sig failed for {signature}: {exc.stderr.strip() or exc.stdout.strip()}")
    return normalize_selector(result.stdout.strip(), f"cast sig {signature}")


def signature_arg_count(signature: str, name: str) -> int:
    match = SIGNATURE_RE.fullmatch(signature)
    expect(match is not None, f"{name} must be a Solidity-style signature")
    args = match.group(1).strip()
    if not args:
        return 0
    count = 1
    paren_depth = 0
    bracket_depth = 0
    token_has_content = False
    for char in args:
        if char == "(":
            paren_depth += 1
            token_has_content = True
        elif char == ")":
            paren_depth -= 1
            expect(paren_depth >= 0, f"{name} has unbalanced tuple parentheses")
            token_has_content = True
        elif char == "[":
            bracket_depth += 1
            token_has_content = True
        elif char == "]":
            bracket_depth -= 1
            expect(bracket_depth >= 0, f"{name} has unbalanced array brackets")
            token_has_content = True
        elif char == "," and paren_depth == 0 and bracket_depth == 0:
            expect(token_has_content, f"{name} has an empty argument")
            count += 1
            token_has_content = False
        elif not char.isspace():
            token_has_content = True
    expect(paren_depth == 0, f"{name} has unbalanced tuple parentheses")
    expect(bracket_depth == 0, f"{name} has unbalanced array brackets")
    expect(token_has_content, f"{name} has an empty argument")
    return count


def expect_no_duplicate(value: str, seen: set[str], name: str) -> None:
    expect(value not in seen, f"duplicate {name}: {value}")
    seen.add(value)


def parse_expected_constructor_param(value: str) -> dict:
    if ":" not in value:
        fail("--expect-constructor-param expects name:type")
    name, abi_type = value.split(":", 1)
    expect(name and abi_type, "--expect-constructor-param expects name:type")
    return {"name": name, "type": abi_type}


def same_path(left: Path, right: Path) -> bool:
    return left.resolve() == right.resolve()


def expect_hex_text(path: Path, name: str) -> str:
    value = path.read_text().strip()
    expect(value and all(ch in "0123456789abcdefABCDEF" for ch in value), f"{name} must be non-empty hex")
    expect(len(value) % 2 == 0, f"{name} must have an even number of hex digits")
    return value


def read_push_value(init_hex: str, offset: int, name: str) -> tuple[int, int]:
    expect(offset + 2 <= len(init_hex), f"{name} is missing PUSH opcode")
    opcode = int(init_hex[offset : offset + 2], 16)
    expect(0x60 <= opcode <= 0x7F, f"{name} must use PUSH1..PUSH32")
    width = opcode - 0x5F
    data_start = offset + 2
    data_end = data_start + width * 2
    expect(data_end <= len(init_hex), f"{name} PUSH data is truncated")
    return int(init_hex[data_start:data_end], 16), data_end


def validate_constructor_args(
    constructor_args: list,
    expected_hex: Optional[str],
    expected_source: Optional[str],
    prefix: str,
) -> str:
    if expected_hex is not None:
        expected_hex = normalize_hex(expected_hex, "--expect-constructor-args-hex")
    if expected_source is not None:
        expect(
            expected_source in SUPPORTED_CONSTRUCTOR_ARG_SOURCES,
            "--expect-constructor-args-source is unsupported",
        )

    if constructor_args == []:
        actual_hex = ""
    else:
        expect(len(constructor_args) == 1, f"{prefix}.constructorArgs supports one ABI-encoded argument blob")
        arg = expect_object(constructor_args[0], f"{prefix}.constructorArgs[0]")
        expect(arg.get("encoding") == "abi-encoded", f"{prefix}.constructorArgs[0].encoding mismatch")
        actual_hex = normalize_hex(expect_string(arg.get("hex"), f"{prefix}.constructorArgs[0].hex"), f"{prefix}.constructorArgs[0].hex")
        arg_bytes = bytes.fromhex(actual_hex)
        expect(arg.get("bytes") == len(arg_bytes), f"{prefix}.constructorArgs[0].bytes mismatch")
        expect(arg.get("sha256") == hashlib.sha256(arg_bytes).hexdigest(), f"{prefix}.constructorArgs[0].sha256 mismatch")
        source = expect_string(arg.get("source"), f"{prefix}.constructorArgs[0].source")
        expect(source in SUPPORTED_CONSTRUCTOR_ARG_SOURCES, f"{prefix}.constructorArgs[0].source unsupported")
        if expected_source is not None:
            expect(source == expected_source, f"{prefix}.constructorArgs[0].source mismatch")

    if expected_hex is not None:
        expect(actual_hex == expected_hex, f"{prefix}.constructorArgs hex mismatch")
    return actual_hex


def validate_deployment_init_code(init_path: Path, runtime_path: Path, constructor_args_hex: str, prefix: str) -> None:
    init_hex = expect_hex_text(init_path, f"{prefix}.initCode")
    runtime_hex = expect_hex_text(runtime_path, f"{prefix}.runtimeBytecode")
    runtime_size = len(runtime_hex) // 2

    size, offset = read_push_value(init_hex, 0, f"{prefix}.initCode.runtimeSize")
    code_offset, offset = read_push_value(init_hex, offset, f"{prefix}.initCode.codeOffset")
    expect(init_hex[offset : offset + 6].lower() == "600039", f"{prefix}.initCode must copy runtime to memory")
    offset += 6
    return_size, offset = read_push_value(init_hex, offset, f"{prefix}.initCode.returnSize")
    expect(init_hex[offset : offset + 6].lower() == "6000f3", f"{prefix}.initCode must return copied runtime")
    offset += 6

    expect(size == runtime_size, f"{prefix}.initCode runtime size mismatch")
    expect(return_size == runtime_size, f"{prefix}.initCode return size mismatch")
    expect(code_offset == offset // 2, f"{prefix}.initCode code offset mismatch")
    runtime_end = offset + len(runtime_hex)
    expect(init_hex[offset:runtime_end].lower() == runtime_hex.lower(), f"{prefix}.initCode runtime segment mismatch")
    expect(init_hex[runtime_end:].lower() == constructor_args_hex, f"{prefix}.initCode constructor args suffix mismatch")


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
    constructor = expect_object(abi.get("constructor"), "abi.constructor")
    params = expect_array(constructor.get("params"), "abi.constructor.params")
    expect(constructor.get("encoding") == "abi", "abi.constructor.encoding mismatch")
    actual_params = []
    for idx, param in enumerate(params):
        param = expect_object(param, f"abi.constructor.params[{idx}]")
        name = expect_string(param.get("name"), f"abi.constructor.params[{idx}].name")
        abi_type = expect_string(param.get("type"), f"abi.constructor.params[{idx}].type")
        expect(abi_type in SUPPORTED_CONSTRUCTOR_TYPES, f"abi.constructor.params[{idx}].type unsupported")
        expect(
            param.get("encoding") == expected_constructor_param_encoding(abi_type),
            f"abi.constructor.params[{idx}].encoding mismatch",
        )
        expect(param.get("slotBytes") == 32, f"abi.constructor.params[{idx}].slotBytes must be 32")
        if abi_type == "uint256[]":
            expect(
                param.get("elementType") == "uint256",
                f"abi.constructor.params[{idx}].elementType must be uint256",
            )
        actual_params.append({"name": name, "type": abi_type})
    if expected_params:
        expect(actual_params == expected_params, "abi.constructor.params mismatch")
    return actual_params


def validate_constructor_schema_args(params: list[dict], constructor_args_hex: str) -> None:
    if not params or not constructor_args_hex:
        return
    actual_bytes = len(constructor_args_hex) // 2
    if constructor_schema_has_dynamic(params):
        min_bytes = len(params) * 32
        expect(
            actual_bytes >= min_bytes,
            f"abi.constructor.params expects at least {min_bytes} constructor arg bytes, got {actual_bytes}",
        )
        return
    expected_bytes = len(params) * 32
    expect(
        actual_bytes == expected_bytes,
        f"abi.constructor.params expects {expected_bytes} constructor arg bytes, got {actual_bytes}",
    )


def validate_event_field(field: dict, prefix: str, indexed: bool) -> int:
    expect_string(field.get("name"), f"{prefix}.name")
    abi_type = expect_string(field.get("type"), f"{prefix}.type")
    expect_string(field.get("irType"), f"{prefix}.irType")
    expect(field.get("indexed") is indexed, f"{prefix}.indexed mismatch")
    word_types = expect_array(field.get("wordTypes"), f"{prefix}.wordTypes")
    for idx, word_type in enumerate(word_types):
        expect_string(word_type, f"{prefix}.wordTypes[{idx}]")
    word_count = field.get("wordCount")
    expect(isinstance(word_count, int) and word_count == len(word_types), f"{prefix}.wordCount mismatch")
    encoding = expect_string(field.get("encoding"), f"{prefix}.encoding")
    if indexed:
        expected_encoding = "indexed-word" if word_count == 1 else "indexed-keccak256"
    else:
        expected_encoding = "abi-static-words"
    expect(encoding == expected_encoding, f"{prefix}.encoding mismatch")
    expect(abi_type, f"{prefix}.type must be non-empty")
    return word_count


def validate_events(abi: dict, expected_events: list[tuple[str, str]]) -> None:
    events = expect_array(abi.get("events"), "abi.events")
    seen_signatures: set[str] = set()
    actual_events: set[tuple[str, str]] = set()
    for idx, event in enumerate(events):
        event = expect_object(event, f"abi.events[{idx}]")
        name = expect_string(event.get("name"), f"abi.events[{idx}].name")
        signature = expect_string(event.get("signature"), f"abi.events[{idx}].signature")
        expect(signature.startswith(f"{name}("), f"abi.events[{idx}].signature must start with event name")
        signature_arg_count(signature, f"abi.events[{idx}].signature")
        expect_no_duplicate(signature, seen_signatures, "abi.events.signature")
        topic0 = normalize_topic(expect_string(event.get("topic0"), f"abi.events[{idx}].topic0"), f"abi.events[{idx}].topic0")
        expect(topic0 == cast_keccak(signature), f"abi.events[{idx}].topic0 mismatch")
        expect(event.get("anonymous") is False, f"abi.events[{idx}].anonymous must be false")
        indexed_fields = expect_array(event.get("indexedFields"), f"abi.events[{idx}].indexedFields")
        data_fields = expect_array(event.get("dataFields"), f"abi.events[{idx}].dataFields")
        expect(isinstance(event.get("topics"), int), f"abi.events[{idx}].topics must be an integer")
        expect(event.get("topics") == len(indexed_fields) + 1, f"abi.events[{idx}].topics mismatch")
        expect(1 <= event.get("topics") <= 4, f"abi.events[{idx}].topics out of EVM log range")
        data_words = 0
        for field_idx, field in enumerate(indexed_fields):
            validate_event_field(expect_object(field, f"abi.events[{idx}].indexedFields[{field_idx}]"), f"abi.events[{idx}].indexedFields[{field_idx}]", True)
        for field_idx, field in enumerate(data_fields):
            data_words += validate_event_field(expect_object(field, f"abi.events[{idx}].dataFields[{field_idx}]"), f"abi.events[{idx}].dataFields[{field_idx}]", False)
        expect(event.get("dataWords") == data_words, f"abi.events[{idx}].dataWords mismatch")
        actual_events.add((name, signature))

    for expected in expected_events:
        expect(expected in actual_events, f"missing event metadata: {expected[1]}")


def validate_entrypoint_abi_value(value: dict, prefix: str, allow_none: bool) -> int:
    type_name = expect_string(value.get("type"), f"{prefix}.type")
    ir_type = expect_string(value.get("irType"), f"{prefix}.irType")
    expect(ir_type == type_name, f"{prefix}.irType must match type")
    abi_type = expect_string(value.get("abiType"), f"{prefix}.abiType")
    encoding = expect_string(value.get("encoding"), f"{prefix}.encoding")
    word_types = expect_array(value.get("wordTypes"), f"{prefix}.wordTypes")
    for idx, word_type in enumerate(word_types):
        word_type = expect_string(word_type, f"{prefix}.wordTypes[{idx}]")
        expect(word_type in SUPPORTED_ENTRYPOINT_WORD_TYPES, f"{prefix}.wordTypes[{idx}] unsupported")
    word_count = value.get("wordCount")
    expect(isinstance(word_count, int) and word_count == len(word_types), f"{prefix}.wordCount mismatch")
    if encoding == "none":
        expect(allow_none, f"{prefix}.encoding cannot be none")
        expect(type_name == "Unit", f"{prefix}.type must be Unit when encoding is none")
        expect(abi_type == "void", f"{prefix}.abiType must be void when encoding is none")
        expect(word_count == 0, f"{prefix}.wordCount must be 0 when encoding is none")
    elif encoding == "abi-dynamic-bytes":
        expect(abi_type in ("bytes", "string"), f"{prefix}.abiType must be bytes or string for dynamic-bytes encoding")
        expect(word_count == 1, f"{prefix}.wordCount must be 1 for dynamic-bytes encoding (offset word)")
    else:
        expect(encoding == "abi-static-words", f"{prefix}.encoding mismatch")
        expect(abi_type != "void", f"{prefix}.abiType must not be void for static ABI words")
        expect(word_count > 0, f"{prefix}.wordCount must be positive for static ABI words")
    return word_count

def validate_entrypoints(
    abi: dict,
    expected_entrypoint_selectors: list[str],
    expected_entrypoint_abis: list[tuple[str, str, int, int]],
) -> dict[str, dict[str, object]]:
    entrypoints = expect_array(abi.get("entrypoints"), "abi.entrypoints")
    actual_entrypoints: dict[str, dict[str, object]] = {}
    seen_entrypoint_names: set[str] = set()
    seen_entrypoint_selectors: set[str] = set()
    seen_entrypoint_signatures: set[str] = set()
    for idx, entry in enumerate(entrypoints):
        entry = expect_object(entry, f"abi.entrypoints[{idx}]")
        name = expect_string(entry.get("name"), f"abi.entrypoints[{idx}].name")
        selector = normalize_selector(
            expect_string(entry.get("selector"), f"abi.entrypoints[{idx}].selector"),
            f"abi.entrypoints[{idx}].selector",
        )
        signature = expect_string(entry.get("signature"), f"abi.entrypoints[{idx}].signature")
        expect(signature.startswith(f"{name}("), f"abi.entrypoints[{idx}].signature must start with entrypoint name")
        expect_no_duplicate(name, seen_entrypoint_names, "abi.entrypoints.name")
        expect_no_duplicate(selector, seen_entrypoint_selectors, "abi.entrypoints.selector")
        expect_no_duplicate(signature, seen_entrypoint_signatures, "abi.entrypoints.signature")
        expect(selector == cast_sig(signature), f"abi.entrypoints[{idx}].selector does not match signature")

        params = expect_array(entry.get("params"), f"abi.entrypoints[{idx}].params")
        expect(signature_arg_count(signature, f"abi.entrypoints[{idx}].signature") == len(params), f"abi.entrypoints[{idx}].signature arg count mismatch")
        param_abi_types = []
        calldata_words = 0
        seen_param_names: set[str] = set()
        for param_idx, param in enumerate(params):
            param = expect_object(param, f"abi.entrypoints[{idx}].params[{param_idx}]")
            param_name = expect_string(param.get("name"), f"abi.entrypoints[{idx}].params[{param_idx}].name")
            expect_no_duplicate(param_name, seen_param_names, f"abi.entrypoints[{idx}].params.name")
            param_abi_types.append(expect_string(param.get("abiType"), f"abi.entrypoints[{idx}].params[{param_idx}].abiType"))
            calldata_words += validate_entrypoint_abi_value(param, f"abi.entrypoints[{idx}].params[{param_idx}]", False)
        expect(signature == f"{name}({','.join(param_abi_types)})", f"abi.entrypoints[{idx}].signature does not match params")
        expect(entry.get("calldataWords") == calldata_words, f"abi.entrypoints[{idx}].calldataWords mismatch")

        returns = expect_string(entry.get("returns"), f"abi.entrypoints[{idx}].returns")
        return_value = expect_object(entry.get("returnValue"), f"abi.entrypoints[{idx}].returnValue")
        expect(return_value.get("type") == returns, f"abi.entrypoints[{idx}].returnValue.type must match returns")
        return_words = validate_entrypoint_abi_value(return_value, f"abi.entrypoints[{idx}].returnValue", True)
        expect(entry.get("returnWords") == return_words, f"abi.entrypoints[{idx}].returnWords mismatch")

        actual_entrypoints[name] = {
            "selector": selector,
            "signature": signature,
            "calldataWords": calldata_words,
            "returnWords": return_words,
        }

    for expected in expected_entrypoint_selectors:
        name, selector = parse_expected_mapping(expected, "--expect-entrypoint")
        actual = actual_entrypoints.get(name)
        expect(actual is not None and actual["selector"] == selector, f"entrypoint selector mismatch for {name}")

    for name, signature, calldata_words, return_words in expected_entrypoint_abis:
        actual = actual_entrypoints.get(name)
        expect(actual is not None, f"missing entrypoint ABI metadata for {name}")
        expect(actual["signature"] == signature, f"entrypoint signature mismatch for {name}")
        expect(actual["calldataWords"] == calldata_words, f"entrypoint calldataWords mismatch for {name}")
        expect(actual["returnWords"] == return_words, f"entrypoint returnWords mismatch for {name}")

    return actual_entrypoints


def validate_chain_profile(
    manifest: dict,
    expected_profile: Optional[str],
    expected_chain_id: Optional[int],
) -> None:
    profile_value = manifest.get("chainProfile")
    deployment = expect_object(manifest.get("deployment"), "deploy manifest deployment")

    if profile_value is None:
        expect(expected_profile is None, "deploy manifest chainProfile is missing")
        expect(expected_chain_id is None, "deploy manifest chainProfile.chainId is missing")
        expect(deployment.get("profileId") is None, "deploy manifest deployment.profileId must be null without chain profile")
        expect(deployment.get("chainId") is None, "deploy manifest deployment.chainId must be null without chain profile")
        expect(deployment.get("networkName") is None, "deploy manifest deployment.networkName must be null without chain profile")
        expect(expect_array(deployment.get("rpcUrls"), "deploy manifest deployment.rpcUrls") == [], "deploy manifest deployment.rpcUrls must be empty without chain profile")
        expect(deployment.get("blockExplorerUrl") is None, "deploy manifest deployment.blockExplorerUrl must be null without chain profile")
        expect(deployment.get("verifier") is None, "deploy manifest deployment.verifier must be null without chain profile")
        expect(deployment.get("verifierUrl") is None, "deploy manifest deployment.verifierUrl must be null without chain profile")
    else:
        profile = expect_object(profile_value, "deploy manifest chainProfile")
        profile_id = expect_string(profile.get("id"), "deploy manifest chainProfile.id")
        if expected_profile is not None:
            expect(profile_id == expected_profile, "deploy manifest chainProfile.id mismatch")
        expect(profile.get("targetId") == "evm", "deploy manifest chainProfile.targetId must be evm")
        expect_string(profile.get("networkName"), "deploy manifest chainProfile.networkName")
        chain_id = profile.get("chainId")
        expect(isinstance(chain_id, int), "deploy manifest chainProfile.chainId must be an integer")
        if expected_chain_id is not None:
            expect(chain_id == expected_chain_id, "deploy manifest chainProfile.chainId mismatch")
        expect_string(profile.get("nativeCurrencySymbol"), "deploy manifest chainProfile.nativeCurrencySymbol")
        expect_optional_string(profile.get("rollupFamily"), "deploy manifest chainProfile.rollupFamily")
        expect_optional_string(profile.get("dataAvailability"), "deploy manifest chainProfile.dataAvailability")
        for field_name in ("rpcUrls", "websocketUrls", "sequencerUrls", "notes"):
            values = expect_array(profile.get(field_name), f"deploy manifest chainProfile.{field_name}")
            for idx, value in enumerate(values):
                expect_string(value, f"deploy manifest chainProfile.{field_name}[{idx}]")
        expect_optional_string(profile.get("blockExplorerUrl"), "deploy manifest chainProfile.blockExplorerUrl")
        expect_optional_string(profile.get("verifier"), "deploy manifest chainProfile.verifier")
        expect_optional_string(profile.get("verifierUrl"), "deploy manifest chainProfile.verifierUrl")

        expect(deployment.get("profileId") == profile_id, "deploy manifest deployment.profileId mismatch")
        expect(deployment.get("chainId") == chain_id, "deploy manifest deployment.chainId mismatch")
        expect(deployment.get("networkName") == profile.get("networkName"), "deploy manifest deployment.networkName mismatch")
        expect(deployment.get("rpcUrls") == profile.get("rpcUrls"), "deploy manifest deployment.rpcUrls mismatch")
        expect(deployment.get("blockExplorerUrl") == profile.get("blockExplorerUrl"), "deploy manifest deployment.blockExplorerUrl mismatch")
        expect(deployment.get("verifier") == profile.get("verifier"), "deploy manifest deployment.verifier mismatch")
        expect(deployment.get("verifierUrl") == profile.get("verifierUrl"), "deploy manifest deployment.verifierUrl mismatch")

    expect(deployment.get("address") is None, "deploy manifest deployment.address must be null before broadcast")
    expect(deployment.get("broadcast") == "not-generated", "deploy manifest deployment.broadcast mismatch")
    expect(deployment.get("broadcastArtifact") is None, "deploy manifest deployment.broadcastArtifact must be null before broadcast")
    expect_string(deployment.get("reason"), "deploy manifest deployment.reason")
    expect_string(deployment.get("reference"), "deploy manifest deployment.reference")


def validate_deploy_manifest(
    root: Path,
    manifest_path: Path,
    metadata: dict,
    yul_path: Path,
    bytecode_path: Path,
    init_code_path: Path,
    source_path: Optional[Path],
    expected_profile: Optional[str],
    expected_chain_id: Optional[int],
    expected_constructor_args_hex: Optional[str],
    expected_constructor_args_source: Optional[str],
    expected_constructor_params: list[dict],
) -> None:
    manifest = expect_object(json.loads(manifest_path.read_text()), "deploy manifest")
    expect(manifest.get("schemaVersion") == 1, "deploy manifest schemaVersion must be 1")
    expect(manifest.get("kind") == "proof-forge-evm-deploy-manifest", "deploy manifest kind mismatch")
    expect(manifest.get("target") == "evm", "deploy manifest target must be evm")
    expect(manifest.get("targetFamily") == "evm", "deploy manifest targetFamily mismatch")
    expect(manifest.get("artifactKind") == "evm-initcode-deploy", "deploy manifest artifactKind mismatch")
    expect(manifest.get("fixture") == metadata.get("fixture"), "deploy manifest fixture mismatch")
    expect_string(manifest.get("contractName"), "deploy manifest contractName")
    expect(manifest.get("sourceKind") == metadata.get("sourceKind"), "deploy manifest sourceKind mismatch")
    expect(manifest.get("sourceModule") == metadata.get("sourceModule"), "deploy manifest sourceModule mismatch")
    expect(manifest.get("irVersion") == metadata.get("irVersion"), "deploy manifest irVersion mismatch")
    expect(manifest.get("capabilities") == metadata.get("capabilities"), "deploy manifest capabilities mismatch")
    expect(manifest.get("abi") == metadata.get("abi"), "deploy manifest ABI mismatch")
    constructor_params = validate_constructor_abi(
        expect_object(manifest.get("abi"), "deploy manifest abi"),
        expected_constructor_params,
    )
    validate_chain_profile(manifest, expected_profile, expected_chain_id)

    inputs = expect_object(manifest.get("inputs"), "deploy manifest inputs")
    manifest_yul = file_entry(root, expect_object(inputs.get("yul"), "inputs.yul"), "yul", "inputs")
    manifest_bytecode = file_entry(root, expect_object(inputs.get("bytecode"), "inputs.bytecode"), "bytecode", "inputs")
    manifest_init_code = file_entry(root, expect_object(inputs.get("initCode"), "inputs.initCode"), "initCode", "inputs")
    expect(same_path(manifest_yul, yul_path), "deploy manifest inputs.yul must match metadata artifacts.yul")
    expect(same_path(manifest_bytecode, bytecode_path), "deploy manifest inputs.bytecode must match metadata artifacts.bytecode")
    expect(same_path(manifest_init_code, init_code_path), "deploy manifest inputs.initCode must match metadata artifacts.initCode")
    if source_path is None:
        expect("source" not in inputs, "deploy manifest inputs.source must be absent when metadata has no source artifact")
    else:
        manifest_source = file_entry(root, expect_object(inputs.get("source"), "inputs.source"), "source", "inputs")
        expect(same_path(manifest_source, source_path), "deploy manifest inputs.source must match metadata artifacts.source")

    creation = expect_object(manifest.get("creation"), "deploy manifest creation")
    expect(creation.get("mode") == "init-code", "deploy manifest creation.mode mismatch")
    constructor_args = expect_array(creation.get("constructorArgs"), "deploy manifest creation.constructorArgs")
    constructor_args_hex = validate_constructor_args(
        constructor_args,
        expected_constructor_args_hex,
        expected_constructor_args_source,
        "deploy manifest creation",
    )
    validate_constructor_schema_args(constructor_params, constructor_args_hex)
    init_code_entry = expect_object(creation.get("initCode"), "deploy manifest creation.initCode")
    creation_init_code = file_entry(root, init_code_entry, "initCode", "creation")
    expect(init_code_entry == inputs["initCode"], "deploy manifest creation.initCode entry must match inputs.initCode")
    expect(same_path(creation_init_code, init_code_path), "deploy manifest creation.initCode must match metadata artifacts.initCode")
    runtime_entry = expect_object(creation.get("runtimeBytecode"), "deploy manifest creation.runtimeBytecode")
    runtime_path = file_entry(root, runtime_entry, "runtimeBytecode", "creation")
    expect(same_path(runtime_path, bytecode_path), "deploy manifest runtimeBytecode must match metadata artifacts.bytecode")
    expect(runtime_entry == inputs["bytecode"], "deploy manifest runtimeBytecode entry must match inputs.bytecode")
    validate_deployment_init_code(creation_init_code, runtime_path, constructor_args_hex, "deploy manifest creation")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expect-fixture", required=True)
    parser.add_argument("--expect-source-kind")
    parser.add_argument("--expect-chain-profile")
    parser.add_argument("--expect-chain-id", type=int)
    parser.add_argument("--expect-constructor-args-hex")
    parser.add_argument("--expect-constructor-args-source")
    parser.add_argument("--expect-constructor-param", action="append", default=[])
    parser.add_argument("--require-method-signatures", action="store_true")
    parser.add_argument("--expect-capability", action="append", default=[])
    parser.add_argument("--expect-entrypoint", action="append", default=[])
    parser.add_argument("--expect-entrypoint-abi", action="append", default=[])
    parser.add_argument("--expect-event", action="append", default=[])
    parser.add_argument("metadata")
    args = parser.parse_args()

    root = Path(args.root)
    metadata_path = Path(args.metadata)
    metadata = expect_object(json.loads(metadata_path.read_text()), "metadata")
    expected_constructor_params = [
        parse_expected_constructor_param(value) for value in args.expect_constructor_param
    ]
    expected_events = [parse_expected_event(value) for value in args.expect_event]
    expected_entrypoint_abis = [
        parse_expected_entrypoint_abi(value) for value in args.expect_entrypoint_abi
    ]

    expect(metadata.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(metadata.get("target") == "evm", "target must be evm")
    expect(metadata.get("targetFamily") == "evm", "targetFamily mismatch")
    expect(metadata.get("artifactKind") == "evm-bytecode", "artifactKind mismatch")
    expect(metadata.get("fixture") == args.expect_fixture, "fixture mismatch")
    expect_string(metadata.get("sourceModule"), "sourceModule")
    if args.expect_source_kind:
        expect(metadata.get("sourceKind") == args.expect_source_kind, "sourceKind mismatch")
        if args.expect_source_kind == "portable-ir":
            expect_string(metadata.get("irVersion"), "irVersion")
    else:
        expect_string(metadata.get("sourceKind"), "sourceKind")
    expect(metadata.get("irVersion") is None or isinstance(metadata.get("irVersion"), str), "irVersion must be null or string")

    capabilities = expect_array(metadata.get("capabilities"), "capabilities")
    for idx, capability in enumerate(capabilities):
        expect_string(capability, f"capabilities[{idx}]")
    for capability in args.expect_capability:
        expect(capability in capabilities, f"missing capability: {capability}")

    toolchain = expect_object(metadata.get("toolchain"), "toolchain")
    solc = expect_object(toolchain.get("solc"), "toolchain.solc")
    expect_string(solc.get("path"), "toolchain.solc.path")
    expect(solc.get("version") is None or isinstance(solc.get("version"), str), "toolchain.solc.version must be null or string")

    artifacts = expect_object(metadata.get("artifacts"), "artifacts")
    artifact_paths = {}
    for artifact_name in REQUIRED_ARTIFACTS:
        artifact_paths[artifact_name] = file_entry(
            root,
            expect_object(artifacts.get(artifact_name), f"artifacts.{artifact_name}"),
            artifact_name,
        )
    source_path = None
    if "source" in artifacts:
        source_path = file_entry(root, expect_object(artifacts.get("source"), "artifacts.source"), "source")

    yul_path = artifact_paths["yul"]
    bytecode_path = artifact_paths["bytecode"]
    init_code_path = artifact_paths["initCode"]
    deploy_manifest_path = artifact_paths["deployManifest"]
    expect_hex_text(bytecode_path, "artifacts.bytecode")

    abi = expect_object(metadata.get("abi"), "abi")
    constructor_params = validate_constructor_abi(abi, expected_constructor_params)
    validate_events(abi, expected_events)
    validate_entrypoints(abi, args.expect_entrypoint, expected_entrypoint_abis)

    methods = expect_array(abi.get("methods"), "abi.methods")
    seen_method_selectors: set[str] = set()
    seen_method_functions: set[str] = set()
    seen_method_signatures: set[str] = set()
    for idx, method in enumerate(methods):
        method = expect_object(method, f"abi.methods[{idx}]")
        selector = normalize_selector(expect_string(method.get("selector"), f"abi.methods[{idx}].selector"), f"abi.methods[{idx}].selector")
        fn_name = expect_string(method.get("fnName"), f"abi.methods[{idx}].fnName")
        expect(fn_name.startswith("f_"), f"abi.methods[{idx}].fnName must be a generated Yul function name")
        arg_count = method.get("argCount")
        expect(isinstance(arg_count, int) and arg_count >= 0, f"abi.methods[{idx}].argCount must be a non-negative integer")
        expect(isinstance(method.get("returnsValue"), bool), f"abi.methods[{idx}].returnsValue must be a boolean")
        expect_no_duplicate(selector, seen_method_selectors, "abi.methods.selector")
        expect_no_duplicate(fn_name, seen_method_functions, "abi.methods.fnName")
        signature = method.get("signature")
        if args.require_method_signatures:
            signature = expect_string(signature, f"abi.methods[{idx}].signature")
        else:
            expect(signature is None or (isinstance(signature, str) and signature), f"abi.methods[{idx}].signature must be null or a non-empty string")
        if isinstance(signature, str):
            expect_no_duplicate(signature, seen_method_signatures, "abi.methods.signature")
            expect(signature_arg_count(signature, f"abi.methods[{idx}].signature") == arg_count, f"abi.methods[{idx}].signature arg count mismatch")

    validation = expect_object(metadata.get("validation"), "validation")
    for key in REQUIRED_VALIDATIONS:
        expect(validation.get(key) == "passed", f"validation.{key} must be passed")

    validate_deploy_manifest(
        root,
        deploy_manifest_path,
        metadata,
        yul_path,
        bytecode_path,
        init_code_path,
        source_path,
        args.expect_chain_profile,
        args.expect_chain_id,
        args.expect_constructor_args_hex,
        args.expect_constructor_args_source,
        expected_constructor_params,
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
