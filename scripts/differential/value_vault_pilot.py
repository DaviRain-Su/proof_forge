#!/usr/bin/env python3
"""Run the CMP-3 ValueVault differential against independent native references."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from contracts import (  # noqa: E402
    OBSERVATION_DIMENSIONS,
    validate_observation,
    validate_reference,
    validate_scenario,
)
from runner import (  # noqa: E402
    LogicalAccount,
    LogicalActor,
    LogicalClock,
    NormalizedValue,
    ResourceObservation,
    RunnerContext,
    RunnerResult,
    StepResult,
    compare_results,
)


SCENARIO_PATH = REPO_ROOT / "testkit/differential/value-vault/scenario.v1.json"
REFERENCE_ROOT = REPO_ROOT / "testkit/differential/value-vault/references"
PRODUCT_SOURCE = REPO_ROOT / "Examples/Product/ValueVault.lean"
DEFAULT_ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

STEPS: tuple[tuple[str, str, tuple[int, ...]], ...] = (
    ("initialize", "initialize", (100,)),
    ("get-initial", "get_balance", ()),
    ("deposit", "deposit", (25,)),
    ("get-deposited", "get_balance", ()),
    ("charge-fee", "charge_fee", (100, 250)),
    ("get-charged", "get_balance", ()),
    ("get-net-charged", "get_net_value", ()),
    ("release", "release", (23,)),
    ("get-released", "get_balance", ()),
    ("snapshot", "snapshot", ()),
    ("get-net-final", "get_net_value", ()),
    ("release-too-much", "release", (201,)),
    ("get-after-rejected", "get_balance", ()),
)

EXPECTED_STATE: tuple[tuple[int, int, int, int, int], ...] = (
    (100, 0, 0, 100, 1),
    (100, 0, 0, 100, 1),
    (125, 0, 0, 25, 2),
    (125, 0, 0, 25, 2),
    (223, 0, 2, 98, 3),
    (223, 0, 2, 98, 3),
    (223, 0, 2, 98, 3),
    (200, 23, 2, 23, 4),
    (200, 23, 2, 23, 4),
    (200, 23, 2, 23, 4),
    (200, 23, 2, 23, 4),
    (200, 23, 2, 23, 4),
    (200, 23, 2, 23, 4),
)

EXPECTED_RETURNS: Mapping[str, int] = {
    "get-initial": 100,
    "get-deposited": 125,
    "get-charged": 223,
    "get-net-charged": 221,
    "get-released": 200,
    "snapshot": 200,
    "get-net-final": 198,
    "get-after-rejected": 200,
}

EVENT_FIELDS: Mapping[str, tuple[str, tuple[str, ...]]] = {
    "initialize": ("VaultInitialized", ("initial", "checkpoint")),
    "deposit": ("ValueDeposited", ("amount", "balance", "operations")),
    "charge-fee": ("ValueCharged", ("gross", "fee", "net", "balance")),
    "release": ("ValueReleased", ("amount", "balance", "released")),
    "snapshot": ("ValueSnapshot", ("balance", "released", "fees", "checkpoint")),
}

EXPECTED_EVENT_VALUES: Mapping[str, Mapping[str, int]] = {
    "initialize": {"initial": 100},
    "deposit": {"amount": 25, "balance": 125, "operations": 2},
    "charge-fee": {"gross": 100, "fee": 2, "net": 98, "balance": 223},
    "release": {"amount": 23, "balance": 200, "released": 23},
    "snapshot": {"balance": 200, "released": 23, "fees": 2},
}

INTERFACES: Mapping[str, Mapping[str, Any]] = {
    "initialize": {"mutability": "call", "params": (("initial", "u64"),), "returns": "unit"},
    "deposit": {"mutability": "call", "params": (("amount", "u64"),), "returns": "unit"},
    "charge_fee": {
        "mutability": "call",
        "params": (("gross", "u64"), ("fee_bps", "u64")),
        "returns": "unit",
    },
    "release": {"mutability": "call", "params": (("amount", "u64"),), "returns": "unit"},
    "snapshot": {"mutability": "call", "params": (), "returns": "u64"},
    "get_balance": {"mutability": "view", "params": (), "returns": "u64"},
    "get_net_value": {"mutability": "view", "params": (), "returns": "u64"},
}

NATIVE_EVM_SIGNATURES: Mapping[str, str] = {
    "initialize": "initialize(uint64)",
    "deposit": "deposit(uint64)",
    "charge_fee": "charge_fee(uint64,uint64)",
    "release": "release(uint64)",
    "snapshot": "snapshot()",
    "get_balance": "get_balance()",
    "get_net_value": "get_net_value()",
}

PROOF_FORGE_EVM_SIGNATURES: Mapping[str, str] = {
    "initialize": "initialize(uint256)",
    "deposit": "deposit(uint256)",
    "charge_fee": "charge_fee(uint256,uint256)",
    "release": "release(uint256)",
    "snapshot": "snapshot()",
    "get_balance": "get_balance()",
    "get_net_value": "get_net_value()",
}

EVENT_SIGNATURES: Mapping[str, str] = {
    "VaultInitialized": "VaultInitialized(uint64,uint64)",
    "ValueDeposited": "ValueDeposited(uint64,uint64,uint64)",
    "ValueCharged": "ValueCharged(uint64,uint64,uint64,uint64)",
    "ValueReleased": "ValueReleased(uint64,uint64,uint64)",
    "ValueSnapshot": "ValueSnapshot(uint64,uint64,uint64,uint64)",
}


class PilotError(RuntimeError):
    pass


def run(
    command: Sequence[str],
    *,
    env: Mapping[str, str] | None = None,
    timeout: int = 900,
) -> str:
    completed = subprocess.run(
        list(command),
        cwd=REPO_ROOT,
        env=dict(env) if env is not None else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if completed.returncode != 0:
        rendered = " ".join(command)
        raise PilotError(
            f"command failed ({completed.returncode}): {rendered}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed.stdout


def require_tool(value: str, label: str) -> str:
    if os.sep in value:
        path = Path(value).expanduser().resolve()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    resolved = shutil.which(value)
    if resolved is None:
        raise PilotError(f"CMP-3 requires {label}; could not resolve {value!r}")
    return resolved


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PilotError(f"failed to read JSON {path.relative_to(REPO_ROOT)}: {error}") from error


def write_json(path: Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_reference(family: str) -> dict[str, Any]:
    document = read_json(REFERENCE_ROOT / f"{family}.v1.json")
    validate_reference(document, f"reference[{family}]")
    source = REPO_ROOT / document["source"]["path"]
    actual = f"sha256:{sha256(source)}"
    if document["provenance"]["revision"] != actual:
        raise PilotError(
            f"{family} reference revision is stale: "
            f"manifest={document['provenance']['revision']}, source={actual}"
        )
    return document


def tool_version(reference: Mapping[str, Any], name: str) -> str:
    for tool in reference["provenance"]["toolchain"]:
        if tool["name"] == name:
            return str(tool["version"])
    raise PilotError(f"reference {reference['id']} does not pin {name}")


def direct_artifact(path: Path, target: str) -> dict[str, Any]:
    document = read_json(path)
    expected = {
        "target": target,
        "sourceKind": "contract-source-authored",
        "irVersion": "canonical-core-v1",
        "sourceModule": "ValueVault",
    }
    mismatches = {
        key: (value, document.get(key))
        for key, value in expected.items()
        if document.get(key) != value
    }
    if mismatches:
        raise PilotError(
            f"{path.relative_to(REPO_ROOT)} is not a direct ValueVault artifact: {mismatches}"
        )
    return document


def no_legacy_sidecars(root: Path) -> None:
    forbidden = sorted(root.rglob("*contract-spec.json"))
    if forbidden:
        names = ", ".join(path.relative_to(REPO_ROOT).as_posix() for path in forbidden)
        raise PilotError(f"direct CMP-3 output contains forbidden ContractSpec sidecars: {names}")


def context(family: str, implementation: str, native_height: int | None = None) -> RunnerContext:
    return RunnerContext(
        accounts=(
            LogicalAccount("contract", f"value-vault.{implementation}.{family}", ("contract",)),
            LogicalAccount("alice", f"alice.{implementation}.{family}", ("caller",)),
        ),
        actors=(LogicalActor("alice", "alice", ("caller",)),),
        clock=LogicalClock(tick=0, native_height=native_height),
    )


def event_json(name: str, fields: Mapping[str, int]) -> dict[str, Any]:
    return {
        "name": name,
        "fields": {field: NormalizedValue.u64(value).to_json() for field, value in fields.items()},
    }


def validate_raw_step(runner_name: str, index: int, raw: Mapping[str, Any]) -> None:
    step_id, call, _ = STEPS[index]
    if raw.get("id") != step_id or raw.get("call") != call:
        raise PilotError(
            f"{runner_name}: step {index} identity mismatch: expected {step_id}/{call}, got {raw}"
        )
    should_succeed = step_id != "release-too-much"
    if bool(raw.get("success")) != should_succeed:
        raise PilotError(f"{runner_name}: step {step_id} success={raw.get('success')}, expected {should_succeed}")

    balance, released, fees, last_value, operations = EXPECTED_STATE[index]
    state = raw.get("state")
    if not isinstance(state, Mapping):
        raise PilotError(f"{runner_name}: step {step_id} has no observed state")
    expected_state = {
        "balance": balance,
        "released": released,
        "fees": fees,
        "lastValue": last_value,
        "operations": operations,
    }
    for name, expected in expected_state.items():
        if name in state and state[name] != expected:
            raise PilotError(
                f"{runner_name}: step {step_id} state {name}={state[name]}, expected {expected}"
            )
    if state.get("balance") != balance or state.get("netValue") != balance - fees:
        raise PilotError(f"{runner_name}: step {step_id} portable state snapshot is incomplete or wrong")

    expected_return = EXPECTED_RETURNS.get(step_id)
    if raw.get("returnU64") != expected_return:
        raise PilotError(
            f"{runner_name}: step {step_id} returned {raw.get('returnU64')}, expected {expected_return}"
        )

    events = raw.get("events")
    if not isinstance(events, list):
        raise PilotError(f"{runner_name}: step {step_id} has no observed event array")
    expected_event = EVENT_FIELDS.get(step_id)
    if expected_event is None:
        if events:
            raise PilotError(f"{runner_name}: step {step_id} emitted unexpected events: {events}")
    else:
        if len(events) != 1 or events[0].get("name") != expected_event[0]:
            raise PilotError(f"{runner_name}: step {step_id} event mismatch: {events}")
        fields = events[0].get("fields", {})
        if tuple(fields) != expected_event[1]:
            raise PilotError(f"{runner_name}: step {step_id} event fields drift: {fields}")
        for name, expected in EXPECTED_EVENT_VALUES[step_id].items():
            if fields.get(name) != expected:
                raise PilotError(
                    f"{runner_name}: step {step_id} event {name}={fields.get(name)}, expected {expected}"
                )


def normalized_result(
    family: str,
    runner_name: str,
    implementation: str,
    raw_steps: Sequence[Mapping[str, Any]],
    resource_unit: str,
    native_height: int | None = None,
) -> RunnerResult:
    if len(raw_steps) != len(STEPS):
        raise PilotError(f"{runner_name}: expected {len(STEPS)} steps, got {len(raw_steps)}")
    steps: list[StepResult] = []
    for index, raw in enumerate(raw_steps):
        validate_raw_step(runner_name, index, raw)
        step_id, call, _ = STEPS[index]
        success = step_id != "release-too-much"
        return_value = (
            NormalizedValue.u64(EXPECTED_RETURNS[step_id]).to_json()
            if step_id in EXPECTED_RETURNS
            else NormalizedValue.unit().to_json()
        )
        status = (
            {"status": "success", "errorCategory": None, "errorData": None}
            if success
            else {
                "status": "revert",
                "errorCategory": "arithmetic",
                "errorData": {"kind": "underflow", "operation": "release"},
            }
        )
        interface = INTERFACES[call]
        observations = {
            "callStatus": status,
            "returnValue": return_value,
            "state": {
                "balance": NormalizedValue.u64(int(raw["state"]["balance"])).to_json(),
                "netValue": NormalizedValue.u64(int(raw["state"]["netValue"])).to_json(),
            },
            "balances": {},
            "events": [event_json(event["name"], event["fields"]) for event in raw["events"]],
            "externalActions": [],
            "interface": {
                "entrypoint": call,
                "mutability": interface["mutability"],
                "params": [
                    {"name": name, "type": value_type} for name, value_type in interface["params"]
                ],
                "returns": interface["returns"],
            },
            "resources": ResourceObservation(
                family,
                {"execution": {"value": int(raw["resource"]), "unit": resource_unit}},
            ).to_json(),
        }
        steps.append(StepResult(step_id, observations))
    return RunnerResult(
        scenario_id="portable-value-vault-primary-triad",
        target_family=family,
        runner_name=runner_name,
        status="executed",
        provenance_complete=True,
        context=context(family, implementation, native_height),
        declared_coverage=tuple(sorted(OBSERVATION_DIMENSIONS)),
        steps=tuple(steps),
    )


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def parse_number(value: Any) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 16) if value.startswith("0x") else int(value.split()[0])
    raise PilotError(f"expected numeric tool output, got {value!r}")


def cast_receipt(command: Sequence[str], env: Mapping[str, str]) -> dict[str, Any]:
    output = run(command, env=env)
    try:
        receipt = json.loads(output)
    except json.JSONDecodeError as error:
        raise PilotError(f"cast did not return a JSON receipt: {output}") from error
    if not isinstance(receipt, dict):
        raise PilotError(f"cast receipt is not an object: {receipt!r}")
    return receipt


def evm_topics(cast: str, env: Mapping[str, str]) -> dict[str, str]:
    return {
        run([cast, "keccak", signature], env=env).strip().lower(): name
        for name, signature in EVENT_SIGNATURES.items()
    }


def decode_evm_events(
    receipt: Mapping[str, Any],
    topic_names: Mapping[str, str],
    base_checkpoint: int | None,
) -> tuple[list[dict[str, Any]], int | None]:
    events: list[dict[str, Any]] = []
    for log in receipt.get("logs", []):
        topics = log.get("topics", [])
        if len(topics) != 1 or str(topics[0]).lower() not in topic_names:
            raise PilotError(f"EVM receipt contains an unknown ValueVault log: {log}")
        name = topic_names[str(topics[0]).lower()]
        data = str(log.get("data", ""))
        if not data.startswith("0x") or (len(data) - 2) % 64:
            raise PilotError(f"EVM event {name} has malformed data: {data}")
        values = [int(data[index : index + 64], 16) for index in range(2, len(data), 64)]
        fields = EVENT_FIELDS[next(step for step, spec in EVENT_FIELDS.items() if spec[0] == name)][1]
        if len(values) != len(fields):
            raise PilotError(f"EVM event {name} has {len(values)} fields, expected {len(fields)}")
        decoded = dict(zip(fields, values, strict=True))
        if name == "VaultInitialized":
            base_checkpoint = decoded["checkpoint"]
            decoded["checkpoint"] = 0
        elif name == "ValueSnapshot":
            if base_checkpoint is None or decoded["checkpoint"] < base_checkpoint:
                raise PilotError("EVM snapshot checkpoint precedes initialization")
            decoded["checkpoint"] -= base_checkpoint
        events.append({"name": name, "fields": decoded})
    return events, base_checkpoint


def evm_call_u64(
    cast: str,
    rpc: str,
    address: str,
    method: str,
    signatures: Mapping[str, str],
    return_type: str,
    env: Mapping[str, str],
) -> int:
    output = run(
        [cast, "call", "--rpc-url", rpc, address, f"{signatures[method]}({return_type})"],
        env=env,
    ).strip()
    return parse_number(output)


def evm_lifecycle(
    init_code: str,
    runner_name: str,
    cast: str,
    rpc: str,
    env: Mapping[str, str],
    topic_names: Mapping[str, str],
    signatures: Mapping[str, str],
    return_type: str,
) -> RunnerResult:
    deploy = cast_receipt(
        [cast, "send", "--rpc-url", rpc, "--private-key", DEFAULT_ANVIL_KEY, "--create", f"0x{init_code}", "--json"],
        env,
    )
    address = deploy.get("contractAddress")
    if not isinstance(address, str) or not address:
        raise PilotError(f"{runner_name}: deployment returned no contract address")

    raw_steps: list[dict[str, Any]] = []
    base_checkpoint: int | None = None
    for step_id, call, args in STEPS:
        signature = signatures[call]
        command_args = [str(value) for value in args]
        events: list[dict[str, Any]] = []
        return_u64: int | None = None
        success = step_id != "release-too-much"
        if INTERFACES[call]["mutability"] == "view":
            resource = parse_number(
                run([cast, "estimate", "--rpc-url", rpc, address, signature, *command_args], env=env).strip()
            )
            return_u64 = evm_call_u64(cast, rpc, address, call, signatures, return_type, env)
        else:
            if call == "snapshot":
                return_u64 = evm_call_u64(cast, rpc, address, call, signatures, return_type, env)
            send = [
                cast,
                "send",
                "--rpc-url",
                rpc,
                "--private-key",
                DEFAULT_ANVIL_KEY,
            ]
            if not success:
                send.extend(["--gas-limit", "1000000"])
            receipt = cast_receipt([*send, address, signature, *command_args, "--json"], env)
            receipt_success = parse_number(receipt.get("status", "0x1")) == 1
            if receipt_success != success:
                raise PilotError(
                    f"{runner_name}: {step_id} receipt status success={receipt_success}, expected {success}"
                )
            resource = parse_number(receipt["gasUsed"])
            events, base_checkpoint = decode_evm_events(receipt, topic_names, base_checkpoint)

        balance = evm_call_u64(cast, rpc, address, "get_balance", signatures, return_type, env)
        net_value = evm_call_u64(cast, rpc, address, "get_net_value", signatures, return_type, env)
        raw_steps.append(
            {
                "id": step_id,
                "call": call,
                "success": success,
                "returnU64": return_u64,
                "state": {"balance": balance, "netValue": net_value},
                "events": events,
                "resource": resource,
            }
        )
    return normalized_result("evm", runner_name, runner_name, raw_steps, "gas")


def compile_native_evm(solc: str, output: Path, reference: Mapping[str, Any]) -> str:
    version_output = run([solc, "--version"])
    version = tool_version(reference, "solc")
    if f"Version: {version}" not in version_output:
        raise PilotError(f"CMP-3 EVM reference requires solc {version}; got:\n{version_output}")
    output.mkdir(parents=True, exist_ok=True)
    source = REPO_ROOT / reference["source"]["path"]
    document = json.loads(run([solc, "--combined-json", "abi,bin", str(source)]))
    matches = [value for key, value in document.get("contracts", {}).items() if key.endswith(":ValueVault")]
    if len(matches) != 1:
        raise PilotError(f"solc returned {len(matches)} ValueVault contracts")
    contract = matches[0]
    abi = contract["abi"] if isinstance(contract["abi"], list) else json.loads(contract["abi"])
    functions = {entry["name"] for entry in abi if entry.get("type") == "function"}
    events = {entry["name"] for entry in abi if entry.get("type") == "event"}
    if functions != set(INTERFACES):
        raise PilotError(f"native Solidity ValueVault ABI functions drift: {sorted(functions)}")
    if events != set(EVENT_SIGNATURES):
        raise PilotError(f"native Solidity ValueVault ABI events drift: {sorted(events)}")
    write_json(output / "abi.json", {"abi": abi})
    (output / "ValueVault.bin").write_text(str(contract["bin"]) + "\n", encoding="ascii")
    return str(contract["bin"])


def build_pf_evm(output: Path, env: Mapping[str, str], cast: str) -> tuple[str, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    bytecode = output / "ValueVault.bin"
    artifact_path = output / "ValueVault.proof-forge-artifact.json"
    run(
        [
            "lake", "env", "proof-forge", "build", "--target", "evm", "--root", ".",
            "-o", str(bytecode), "--artifact-output", str(artifact_path), "--cast", cast,
            str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
        ],
        env=env,
    )
    artifact = direct_artifact(artifact_path, "evm")
    names = {entry["name"] for entry in artifact.get("abi", {}).get("entrypoints", [])}
    if names != set(INTERFACES):
        raise PilotError(f"ProofForge EVM artifact has unexpected entrypoints: {sorted(names)}")
    init_path = output / "ValueVault.init.bin"
    if not init_path.is_file():
        raise PilotError("ProofForge EVM direct build did not produce ValueVault.init.bin")
    no_legacy_sidecars(output)
    return init_path.read_text(encoding="ascii").strip(), artifact


def run_evm(
    output: Path,
    reference: Mapping[str, Any],
    solc: str,
    cast: str,
    anvil: str,
    env: Mapping[str, str],
) -> tuple[RunnerResult, RunnerResult, dict[str, Any]]:
    native_code = compile_native_evm(solc, output / "native", reference)
    pf_code, artifact = build_pf_evm(output / "proof-forge", env, cast)
    port = free_port()
    rpc = f"http://127.0.0.1:{port}"
    process = subprocess.Popen(
        [anvil, "--silent", "--port", str(port), "--chain-id", "31337"],
        cwd=REPO_ROOT,
        env=dict(env),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        for _ in range(100):
            if process.poll() is not None:
                stderr = process.stderr.read() if process.stderr is not None else ""
                raise PilotError(f"Anvil exited before CMP-3 execution: {stderr}")
            probe = subprocess.run(
                [cast, "block-number", "--rpc-url", rpc],
                cwd=REPO_ROOT,
                env=dict(env),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if probe.returncode == 0:
                break
            time.sleep(0.1)
        else:
            raise PilotError(f"Anvil did not become ready at {rpc}")
        topics = evm_topics(cast, env)
        native = evm_lifecycle(
            native_code,
            "native-solidity-anvil",
            cast,
            rpc,
            env,
            topics,
            NATIVE_EVM_SIGNATURES,
            "uint64",
        )
        proof_forge = evm_lifecycle(
            pf_code,
            "proof-forge-authored-anvil",
            cast,
            rpc,
            env,
            topics,
            PROOF_FORGE_EVM_SIGNATURES,
            "uint256",
        )
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    return native, proof_forge, artifact


SOLANA_LOG = re.compile(
    r"^Program log: 0x(?P<event>[0-9a-f]+), 0x[0-9a-f]+, 0x(?P<value>[0-9a-f]+), 0x[0-9a-f]+, 0x[0-9a-f]+$"
)


def solana_events(step_id: str, logs: Sequence[str]) -> list[dict[str, Any]]:
    values = [(int(match["event"], 16), int(match["value"], 16)) for line in logs if (match := SOLANA_LOG.match(line))]
    expected = EVENT_FIELDS.get(step_id)
    if expected is None:
        if values:
            raise PilotError(f"Solana step {step_id} emitted unexpected numeric event logs: {values}")
        return []
    event_id = list(EVENT_FIELDS).index(step_id)
    if len(values) != len(expected[1]) or any(observed_id != event_id for observed_id, _ in values):
        raise PilotError(f"Solana step {step_id} emitted malformed numeric event logs: {values}")
    return [{"name": expected[0], "fields": dict(zip(expected[1], (value for _, value in values), strict=True))}]


def run_solana_binary(elf: Path, runner_name: str, env: Mapping[str, str]) -> RunnerResult:
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "testkit/Cargo.toml",
            "-p", "proof-forge-testkit-harness-solana", "--bin", "value_vault_differential", "--",
            str(elf), runner_name,
        ],
        env=env,
        timeout=300,
    )
    lines = [line for line in stdout.splitlines() if line.strip()]
    document = json.loads(lines[-1])
    if document.get("schema") != "proof-forge.native-value-vault.solana.v1":
        raise PilotError(f"Solana runner returned unexpected schema: {document.get('schema')}")
    raw_steps = []
    for item in document["steps"]:
        state = item["state"]
        raw_steps.append(
            {
                "id": item["id"],
                "call": item["call"],
                "success": item["success"],
                "returnU64": item["returnU64"],
                "state": {**state, "netValue": state["balance"] - state["fees"]},
                "events": solana_events(item["id"], item["logs"]),
                "resource": item["computeUnits"],
            }
        )
    return normalized_result("solana", runner_name, runner_name, raw_steps, "computeUnits", 0)


def build_pf_solana(output: Path, env: Mapping[str, str]) -> tuple[Path, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    elf = output / "ValueVault.so"
    artifact_path = output / "artifact.json"
    run(
        [
            "lake", "env", "proof-forge", "build", "--target", "solana-sbpf-asm", "--root", ".",
            "-o", str(elf), "--artifact-output", str(artifact_path),
            str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
        ],
        env=env,
        timeout=1200,
    )
    artifact = direct_artifact(artifact_path, "solana-sbpf-asm")
    idl_ref = artifact.get("artifacts", {}).get("solanaIdl", {}).get("path")
    if not isinstance(idl_ref, str):
        raise PilotError("ProofForge Solana artifact did not declare its IDL")
    idl_path = Path(idl_ref)
    idl = read_json(idl_path if idl_path.is_absolute() else REPO_ROOT / idl_path)
    names = {entry["name"] for entry in idl.get("instructions", [])}
    if names != set(INTERFACES):
        raise PilotError(f"ProofForge Solana IDL has unexpected entrypoints: {sorted(names)}")
    no_legacy_sidecars(output)
    return elf, artifact


def build_native_solana(
    output: Path,
    reference: Mapping[str, Any],
    cargo_build_sbf: str,
    env: Mapping[str, str],
) -> Path:
    version_output = run([cargo_build_sbf, "--version"], env=env)
    for name in ("cargo-build-sbf", "platform-tools"):
        expected = tool_version(reference, name)
        if expected not in version_output:
            raise PilotError(f"native Solana reference requires {name} {expected}; got:\n{version_output}")
    output.mkdir(parents=True, exist_ok=True)
    run(
        [
            cargo_build_sbf,
            "--manifest-path", "benchmarks/native/solana/value-vault/Cargo.toml",
            "--sbf-out-dir", str(output),
            "--features", "bpf-entrypoint",
        ],
        env=env,
        timeout=1200,
    )
    candidates = sorted(output.glob("*.so"))
    if len(candidates) != 1:
        raise PilotError(f"native Solana build produced {len(candidates)} ELF candidates in {output}")
    return candidates[0]


def run_solana(
    output: Path,
    reference: Mapping[str, Any],
    cargo_build_sbf: str,
    env: Mapping[str, str],
) -> tuple[RunnerResult, RunnerResult, dict[str, Any]]:
    native_elf = build_native_solana(output / "native", reference, cargo_build_sbf, env)
    pf_elf, artifact = build_pf_solana(output / "proof-forge", env)
    native = run_solana_binary(native_elf, "native-pinocchio-mollusk", env)
    proof_forge = run_solana_binary(pf_elf, "proof-forge-authored-mollusk", env)
    return native, proof_forge, artifact


NEAR_CALL = re.compile(
    r"^call (?P<call>[a-zA-Z0-9_]+): "
    r"(?:(?:return_hex=(?P<return>[0-9a-f]+))|return=<none>|aborted=(?P<abort>.*)) "
    r"gas=(?P<resource>[0-9]+)$"
)
NEAR_LOG = re.compile(r"^call (?P<call>[a-zA-Z0-9_]+): log=(?P<log>.*)$")
NEAR_ACTION = re.compile(r"^call (?P<call>[a-zA-Z0-9_]+): action=(?P<action>.*)$")


def parse_near_calls(stdout: str, runner_name: str) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        if match := NEAR_CALL.match(line):
            calls.append(
                {
                    "call": match["call"],
                    "return": match["return"],
                    "abort": match["abort"],
                    "resource": int(match["resource"]),
                    "logs": [],
                    "actions": [],
                }
            )
        elif match := NEAR_LOG.match(line):
            if not calls or calls[-1]["call"] != match["call"]:
                raise PilotError(f"{runner_name}: orphan NEAR log line: {line}")
            calls[-1]["logs"].append(match["log"])
        elif match := NEAR_ACTION.match(line):
            if not calls or calls[-1]["call"] != match["call"]:
                raise PilotError(f"{runner_name}: orphan NEAR action line: {line}")
            calls[-1]["actions"].append(match["action"])
    return calls


def decode_near_u64(payload_hex: str | None, native_json: bool, label: str) -> int:
    if payload_hex is None:
        raise PilotError(f"{label}: expected a return value")
    payload = bytes.fromhex(payload_hex)
    if native_json:
        return int(payload.decode("ascii"))
    if len(payload) != 8:
        raise PilotError(f"{label}: expected eight Borsh bytes, got {len(payload)}")
    return int.from_bytes(payload, "little")


def near_event(log: str) -> dict[str, Any]:
    prefix = "EVENT_JSON:"
    if not log.startswith(prefix):
        raise PilotError(f"NEAR ValueVault emitted a non-event log: {log}")
    document = json.loads(log[len(prefix) :])
    if document.get("standard") != "proof_forge" or document.get("version") != "1.0.0":
        raise PilotError(f"NEAR ValueVault event envelope drift: {document}")
    data = document.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        raise PilotError(f"NEAR ValueVault event data drift: {document}")
    return {"name": document["event"], "fields": data[0]}


def near_inputs(native_json: bool) -> tuple[list[str], list[str]]:
    methods: list[str] = []
    encoded: list[str] = []
    param_names = {
        "initialize": ("initial",),
        "deposit": ("amount",),
        "charge_fee": ("gross", "fee_bps"),
        "release": ("amount",),
    }
    for _, call, args in STEPS:
        methods.append(call)
        if native_json and args:
            payload = json.dumps(dict(zip(param_names[call], args, strict=True)), separators=(",", ":")).encode()
        elif native_json:
            payload = b""
        else:
            payload = b"".join(struct.pack("<Q", value) for value in args)
        encoded.append(payload.hex())
        methods.extend(("get_balance", "get_net_value"))
        encoded.extend(("", ""))
    return methods, encoded


def near_lifecycle(
    wasm: Path,
    runner_name: str,
    native_json: bool,
    env: Mapping[str, str],
) -> RunnerResult:
    methods, inputs = near_inputs(native_json)
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "tools/near-vm-runner/Cargo.toml",
            "--", str(wasm), *methods, "--inputs-hex", ",".join(inputs), "--continue-on-abort",
        ],
        env=env,
        timeout=1200,
    )
    calls = parse_near_calls(stdout, runner_name)
    if len(calls) != len(STEPS) * 3:
        raise PilotError(f"{runner_name}: expected {len(STEPS) * 3} NEAR call rows, got {len(calls)}\n{stdout}")
    raw_steps: list[dict[str, Any]] = []
    for index, (step_id, call, _) in enumerate(STEPS):
        main, balance_call, net_call = calls[index * 3 : index * 3 + 3]
        if main["call"] != call or balance_call["call"] != "get_balance" or net_call["call"] != "get_net_value":
            raise PilotError(f"{runner_name}: NEAR call grouping drift at {step_id}")
        success = main["abort"] is None
        if balance_call["abort"] is not None or net_call["abort"] is not None:
            raise PilotError(f"{runner_name}: state query aborted after {step_id}")
        if main["actions"] or balance_call["actions"] or net_call["actions"]:
            raise PilotError(f"{runner_name}: portable ValueVault unexpectedly created NEAR actions")
        return_u64 = (
            decode_near_u64(main["return"], native_json, f"{runner_name}:{step_id}")
            if step_id in EXPECTED_RETURNS
            else None
        )
        raw_steps.append(
            {
                "id": step_id,
                "call": call,
                "success": success,
                "returnU64": return_u64,
                "state": {
                    "balance": decode_near_u64(balance_call["return"], native_json, f"{runner_name}:{step_id}:balance"),
                    "netValue": decode_near_u64(net_call["return"], native_json, f"{runner_name}:{step_id}:net"),
                },
                "events": [near_event(log) for log in main["logs"]],
                "resource": main["resource"],
            }
        )
    return normalized_result("near", runner_name, runner_name, raw_steps, "gas", 1)


def run_near(
    output: Path,
    reference: Mapping[str, Any],
    env: Mapping[str, str],
) -> tuple[RunnerResult, RunnerResult, dict[str, Any]]:
    rust_version = tool_version(reference, "rustc")
    rustc = run(["rustup", "which", "--toolchain", rust_version, "rustc"], env=env).strip()
    actual = run(["rustup", "run", rust_version, "rustc", "--version"], env=env).strip()
    if not actual.startswith(f"rustc {rust_version} "):
        raise PilotError(f"native NEAR reference requires rustc {rust_version}; got {actual}")
    targets = run(["rustup", "target", "list", "--installed", "--toolchain", rust_version], env=env)
    if "wasm32-unknown-unknown" not in targets.splitlines():
        raise PilotError(
            f"native NEAR reference requires: rustup target add --toolchain {rust_version} wasm32-unknown-unknown"
        )

    native_env = dict(env)
    native_env["RUSTC"] = rustc
    run(
        [
            "rustup", "run", rust_version, "cargo", "build", "--locked", "--release",
            "--target", "wasm32-unknown-unknown", "--manifest-path",
            "testkit/compare/near/value-vault/Cargo.toml",
        ],
        env=native_env,
        timeout=1200,
    )
    native_wasm = (
        REPO_ROOT
        / "testkit/compare/near/value-vault/target/wasm32-unknown-unknown/release/pf_near_sdk_value_vault_reference.wasm"
    )
    if not native_wasm.is_file():
        raise PilotError(f"native NEAR build did not produce {native_wasm.relative_to(REPO_ROOT)}")

    pf_output = output / "proof-forge"
    pf_output.mkdir(parents=True, exist_ok=True)
    artifact_path = pf_output / "artifact.json"
    run(
        [
            "lake", "env", "proof-forge", "build", "--target", "wasm-near", "--root", ".",
            "-o", str(pf_output), "--artifact-output", str(artifact_path),
            str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
        ],
        env=env,
    )
    artifact = direct_artifact(artifact_path, "wasm-near")
    names = {entry["name"] for entry in artifact.get("abi", {}).get("entrypoints", [])}
    if names != set(INTERFACES):
        raise PilotError(f"ProofForge NEAR artifact has unexpected entrypoints: {sorted(names)}")
    pf_wasm = pf_output / "valuevault.wasm"
    if not pf_wasm.is_file():
        raise PilotError("ProofForge NEAR direct build did not produce valuevault.wasm")
    no_legacy_sidecars(pf_output)

    native = near_lifecycle(native_wasm, "native-near-sdk-near-vm", True, env)
    proof_forge = near_lifecycle(pf_wasm, "proof-forge-authored-near-vm", False, env)
    return native, proof_forge, artifact


def compare_family(
    output: Path,
    family: str,
    scenario: Mapping[str, Any],
    native: RunnerResult,
    proof_forge: RunnerResult,
) -> dict[str, Any]:
    write_json(output / f"{family}.native.runner-result.v1.json", native.to_json())
    write_json(output / f"{family}.proof-forge.runner-result.v1.json", proof_forge.to_json())
    report = compare_results(scenario, native, proof_forge)
    validate_observation(report, f"comparison[{family}]")
    if not report["semanticMatch"]:
        raise PilotError(f"{family} ValueVault differential did not semantically match: {report['comparison']}")
    if report["observationCoverage"]["missing"]:
        raise PilotError(f"{family} ValueVault differential has incomplete coverage")
    write_json(output / f"{family}.comparison.v1.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("build/differential/value-vault"))
    parser.add_argument("--solc", default=os.environ.get("PF_CMP_SOLC", "solc"))
    parser.add_argument("--cast", default=os.environ.get("CAST", str(Path.home() / ".foundry/bin/cast")))
    parser.add_argument("--anvil", default=os.environ.get("ANVIL", str(Path.home() / ".foundry/bin/anvil")))
    parser.add_argument("--cargo-build-sbf", default=os.environ.get("CARGO_BUILD_SBF", "cargo-build-sbf"))
    args = parser.parse_args()

    output = args.output if args.output.is_absolute() else REPO_ROOT / args.output
    shutil.rmtree(output, ignore_errors=True)
    output.mkdir(parents=True)

    scenario = read_json(SCENARIO_PATH)
    validate_scenario(scenario)
    references = {family: checked_reference(family) for family in ("evm", "solana", "near")}

    solc = require_tool(args.solc, "solc 0.8.30")
    cast = require_tool(args.cast, "Foundry cast")
    anvil = require_tool(args.anvil, "Foundry anvil")
    cargo_build_sbf = require_tool(args.cargo_build_sbf, "cargo-build-sbf")

    tool_bin = output / "tool-bin"
    tool_bin.mkdir()
    (tool_bin / "solc").symlink_to(solc)
    env = os.environ.copy()
    env["RUST_LOG"] = "error"
    env["PATH"] = os.pathsep.join(
        [
            str(tool_bin),
            str(Path(cast).parent),
            str(Path.home() / ".cargo/bin"),
            str(Path(cargo_build_sbf).parent),
            str(Path.home() / ".local/share/solana/install/active_release/bin"),
            env.get("PATH", ""),
        ]
    )

    native_evm, pf_evm, evm_artifact = run_evm(output / "evm", references["evm"], solc, cast, anvil, env)
    native_solana, pf_solana, solana_artifact = run_solana(
        output / "solana", references["solana"], cargo_build_sbf, env
    )
    native_near, pf_near, near_artifact = run_near(output / "near", references["near"], env)

    reports = {
        "evm": compare_family(output, "evm", scenario, native_evm, pf_evm),
        "solana": compare_family(output, "solana", scenario, native_solana, pf_solana),
        "near": compare_family(output, "near", scenario, native_near, pf_near),
    }
    summary = {
        "schema": "proof-forge.differential.value-vault-evidence.v1",
        "scenario": SCENARIO_PATH.relative_to(REPO_ROOT).as_posix(),
        "productSource": {
            "path": PRODUCT_SOURCE.relative_to(REPO_ROOT).as_posix(),
            "sha256": sha256(PRODUCT_SOURCE),
            "sourceKind": "contract-source-authored",
            "irVersion": "canonical-core-v1",
        },
        "references": {
            family: {
                "id": reference["id"],
                "path": (REFERENCE_ROOT / f"{family}.v1.json").relative_to(REPO_ROOT).as_posix(),
                "revision": reference["provenance"]["revision"],
            }
            for family, reference in references.items()
        },
        "artifacts": {
            "evm": {key: evm_artifact[key] for key in ("target", "sourceKind", "irVersion", "sourceModule")},
            "solana": {key: solana_artifact[key] for key in ("target", "sourceKind", "irVersion", "sourceModule")},
            "near": {key: near_artifact[key] for key in ("target", "sourceKind", "irVersion", "sourceModule")},
        },
        "semanticMatch": {family: report["semanticMatch"] for family, report in reports.items()},
        "completeCoverage": {
            family: not report["observationCoverage"]["missing"] for family, report in reports.items()
        },
    }
    write_json(output / "evidence.v1.json", summary)
    print(f"differential-value-vault: ok ({output.relative_to(REPO_ROOT)}/evidence.v1.json)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PilotError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"differential-value-vault: {error}", file=sys.stderr)
        raise SystemExit(1)
