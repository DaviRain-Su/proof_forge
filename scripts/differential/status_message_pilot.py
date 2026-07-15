#!/usr/bin/env python3
"""Run the CMP-3h StatusMessage differential on the primary target VMs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from contracts import OBSERVATION_DIMENSIONS, validate_observation, validate_reference, validate_scenario  # noqa: E402
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

SCENARIO_PATH = REPO_ROOT / "testkit/differential/status-message/scenario.v1.json"
REFERENCE_ROOT = REPO_ROOT / "testkit/differential/status-message/references"
PRODUCT_SOURCE = REPO_ROOT / "Examples/Product/StatusMessage.lean"
ALICE_EVM_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ALICE_EVM = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
ALICE_NEAR = "alice.testnet"
STEPS = (
    ("initialize", "init", None, 0),
    ("set-seven", "set_status", 7, 7),
    ("get-seven", "get_status", None, 7),
    ("set-ninety-nine", "set_status", 99, 99),
    ("get-ninety-nine", "get_status", None, 99),
)
INTERFACES = {
    "init": {"mutability": "write", "params": [], "returns": "unit"},
    "set_status": {"mutability": "write", "params": [("status", "u64")], "returns": "unit"},
    "get_status": {"mutability": "view", "params": [("who", "u64")], "returns": "u64"},
}


class PilotError(RuntimeError):
    pass


def run(command: Sequence[str], *, env: Mapping[str, str] | None = None, timeout: int = 900) -> str:
    completed = subprocess.run(
        list(command), cwd=REPO_ROOT, env=dict(env) if env is not None else None,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout,
    )
    if completed.returncode != 0:
        raise PilotError(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
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
        raise PilotError(f"CMP-3h2 requires {label}; could not resolve {value!r}")
    return resolved


def default_solc() -> str:
    configured = os.environ.get("PF_CMP_SOLC")
    pinned = REPO_ROOT / "build/toolchains/solc-0.8.30"
    return configured or (str(pinned) if pinned.is_file() else "solc")


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PilotError(f"failed to read JSON {path.relative_to(REPO_ROOT)}: {error}") from error


def write_json(path: Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_reference(family: str) -> dict[str, Any]:
    document = read_json(REFERENCE_ROOT / f"{family}.v1.json")
    validate_reference(document, f"reference[{family}]")
    source = REPO_ROOT / document["source"]["path"]
    actual = f"sha256:{sha256(source)}"
    if document["provenance"]["revision"] != actual:
        raise PilotError(f"{family} reference digest is stale: {actual}")
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
        "sourceModule": "StatusMessage",
    }
    mismatches = {key: (value, document.get(key)) for key, value in expected.items() if document.get(key) != value}
    if mismatches:
        raise PilotError(f"{path.relative_to(REPO_ROOT)} is not direct StatusMessage: {mismatches}")
    return document


def no_legacy_sidecars(root: Path) -> None:
    forbidden = sorted(root.rglob("*contract-spec*")) + sorted(root.rglob("*ir-module*"))
    if forbidden:
        raise PilotError(f"direct StatusMessage output contains retired sidecars: {forbidden}")


def context(family: str, implementation: str, native_alice: str, native_height: int | None = None) -> RunnerContext:
    return RunnerContext(
        accounts=(
            LogicalAccount("contract", f"status-message.{implementation}.{family}", ("contract",)),
            LogicalAccount("alice", native_alice, ("caller",)),
        ),
        actors=(LogicalActor("alice", "alice", ("caller",)),),
        clock=LogicalClock(tick=0, native_height=native_height),
    )


def event(account: int, status: int) -> dict[str, Any]:
    return {
        "name": "StatusSet",
        "fields": {
            "account": NormalizedValue.u64(account).to_json(),
            "status": NormalizedValue.u64(status).to_json(),
        },
    }


def normalized_result(
    family: str,
    runner_name: str,
    implementation: str,
    native_alice: str,
    alice_handle: int,
    raw_steps: Sequence[Mapping[str, Any]],
    resource_unit: str,
    native_height: int | None = None,
) -> RunnerResult:
    if len(raw_steps) != len(STEPS):
        raise PilotError(f"{runner_name}: expected {len(STEPS)} steps, got {len(raw_steps)}")
    results: list[StepResult] = []
    for index, ((step_id, action, status_arg, expected_status), raw) in enumerate(zip(STEPS, raw_steps, strict=True)):
        if raw.get("id") != step_id or raw.get("action") != action:
            raise PilotError(f"{runner_name}: step {index} identity mismatch: {raw}")
        if not raw.get("success") or int(raw.get("status", -1)) != expected_status:
            raise PilotError(f"{runner_name}: step {step_id} did not preserve status {expected_status}: {raw}")
        expected_return = expected_status if action == "get_status" else None
        if raw.get("returnU64") != expected_return:
            raise PilotError(f"{runner_name}: step {step_id} return mismatch: {raw.get('returnU64')}")
        expected_events = [] if status_arg is None else [{"account": alice_handle, "status": status_arg}]
        if raw.get("events") != expected_events:
            raise PilotError(f"{runner_name}: step {step_id} event mismatch: {raw.get('events')}")
        interface = INTERFACES[action]
        observations = {
            "callStatus": {"status": "success", "errorCategory": None, "errorData": None},
            "returnValue": (
                NormalizedValue.u64(expected_return).to_json()
                if expected_return is not None else NormalizedValue.unit().to_json()
            ),
            "state": {"aliceStatus": NormalizedValue.u64(expected_status).to_json()},
            "balances": {},
            "events": [event(item["account"], item["status"]) for item in expected_events],
            "externalActions": [],
            "interface": {
                "entrypoint": action,
                "mutability": interface["mutability"],
                "params": [{"name": name, "type": value_type} for name, value_type in interface["params"]],
                "returns": interface["returns"],
            },
            "resources": ResourceObservation(
                family, {"execution": {"value": int(raw["resource"]), "unit": resource_unit}}
            ).to_json(),
        }
        results.append(StepResult(step_id, observations))
    return RunnerResult(
        scenario_id="portable-status-message-primary-triad",
        target_family=family,
        runner_name=runner_name,
        status="executed",
        provenance_complete=True,
        context=context(family, implementation, native_alice, native_height),
        declared_coverage=tuple(sorted(OBSERVATION_DIMENSIONS)),
        steps=tuple(results),
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
    raise PilotError(f"expected numeric output, got {value!r}")


def cast_receipt(command: Sequence[str], env: Mapping[str, str]) -> dict[str, Any]:
    document = json.loads(run(command, env=env))
    if not isinstance(document, dict):
        raise PilotError(f"cast receipt is not an object: {document!r}")
    return document


def decode_evm_events(receipt: Mapping[str, Any], topic: str) -> list[dict[str, int]]:
    events: list[dict[str, int]] = []
    for log in receipt.get("logs", []):
        topics = log.get("topics", [])
        if len(topics) != 2 or str(topics[0]).lower() != topic:
            raise PilotError(f"unknown StatusMessage EVM log: {log}")
        account = int(str(topics[1]), 16)
        data = str(log.get("data", ""))
        if not data.startswith("0x") or len(data) != 66:
            raise PilotError(f"malformed StatusSet data: {data}")
        events.append({"account": account, "status": int(data[2:], 16)})
    return events


def evm_call_status(
    cast: str,
    rpc: str,
    address: str,
    abi_type: str,
    who: int,
    env: Mapping[str, str],
) -> int:
    signature = f"get_status({abi_type})({abi_type})"
    return parse_number(
        run([cast, "call", "--rpc-url", rpc, address, signature, str(who)], env=env).strip()
    )


def evm_lifecycle(
    init_code: str,
    runner_name: str,
    abi_type: str,
    cast: str,
    rpc: str,
    env: Mapping[str, str],
) -> RunnerResult:
    deploy = cast_receipt(
        [cast, "send", "--rpc-url", rpc, "--private-key", ALICE_EVM_KEY, "--create", f"0x{init_code}", "--json"], env,
    )
    address = deploy.get("contractAddress")
    if not isinstance(address, str) or not address:
        raise PilotError(f"{runner_name}: deployment returned no address")
    alice_handle = int(ALICE_EVM, 16) & ((1 << 64) - 1)
    topic = run([cast, "keccak", "StatusSet(uint64,uint64)"], env=env).strip().lower()
    raw_steps: list[dict[str, Any]] = []
    for step_id, action, status_arg, _ in STEPS:
        if action == "get_status":
            returned = evm_call_status(cast, rpc, address, abi_type, alice_handle, env)
            resource = parse_number(
                run(
                    [cast, "estimate", "--rpc-url", rpc, address, f"get_status({abi_type})", str(alice_handle)],
                    env=env,
                ).strip()
            )
            events: list[dict[str, int]] = []
        else:
            signature = "init()" if action == "init" else f"set_status({abi_type})"
            args = [] if status_arg is None else [str(status_arg)]
            receipt = cast_receipt(
                [cast, "send", "--rpc-url", rpc, "--private-key", ALICE_EVM_KEY, address, signature, *args, "--json"], env,
            )
            if parse_number(receipt.get("status", "0x0")) != 1:
                raise PilotError(f"{runner_name}: {step_id} reverted")
            returned = None
            resource = parse_number(receipt["gasUsed"])
            events = decode_evm_events(receipt, topic)
        raw_steps.append({
            "id": step_id, "action": action, "success": True, "returnU64": returned,
            "status": evm_call_status(cast, rpc, address, abi_type, alice_handle, env),
            "events": events, "resource": resource,
        })
    return normalized_result("evm", runner_name, runner_name, ALICE_EVM, alice_handle, raw_steps, "gas")


def compile_native_evm(solc: str, reference: Mapping[str, Any]) -> str:
    version = tool_version(reference, "solc")
    output = run([solc, "--version"])
    if f"Version: {version}" not in output:
        raise PilotError(f"native EVM requires solc {version}: {output}")
    source = REPO_ROOT / reference["source"]["path"]
    document = json.loads(run([solc, "--combined-json", "abi,bin", str(source)]))
    matches = [value for key, value in document["contracts"].items() if key.endswith(":StatusMessage")]
    if len(matches) != 1:
        raise PilotError(f"solc returned {len(matches)} StatusMessage contracts")
    abi = matches[0]["abi"] if isinstance(matches[0]["abi"], list) else json.loads(matches[0]["abi"])
    functions = {item["name"] for item in abi if item.get("type") == "function"}
    if functions != {"init", "set_status", "get_status", "version"}:
        raise PilotError(f"native StatusMessage ABI drift: {sorted(functions)}")
    return str(matches[0]["bin"])


def build_pf_evm(output: Path, env: Mapping[str, str], cast: str) -> tuple[str, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    artifact_path = output / "artifact.json"
    run([
        "lake", "env", "proof-forge", "build", "--target", "evm", "--root", ".",
        "-o", str(output / "StatusMessage.bin"), "--artifact-output", str(artifact_path),
        "--cast", cast, str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
    ], env=env)
    artifact = direct_artifact(artifact_path, "evm")
    init_path = output / "StatusMessage.init.bin"
    if not init_path.is_file():
        raise PilotError("ProofForge EVM did not emit StatusMessage.init.bin")
    no_legacy_sidecars(output)
    return init_path.read_text(encoding="ascii").strip(), artifact


def run_evm(output: Path, reference: Mapping[str, Any], solc: str, cast: str, anvil: str, env: Mapping[str, str]):
    native_code = compile_native_evm(solc, reference)
    pf_code, artifact = build_pf_evm(output / "proof-forge", env, cast)
    port = free_port()
    rpc = f"http://127.0.0.1:{port}"
    process = subprocess.Popen([anvil, "--silent", "--port", str(port), "--chain-id", "31337"], cwd=REPO_ROOT, env=dict(env), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise PilotError(f"Anvil exited: {process.stderr.read() if process.stderr else ''}")
            if subprocess.run([cast, "block-number", "--rpc-url", rpc], cwd=REPO_ROOT, env=dict(env), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                break
            time.sleep(0.1)
        else:
            raise PilotError("Anvil did not become ready")
        native = evm_lifecycle(native_code, "native-solidity-anvil", "uint64", cast, rpc, env)
        proof_forge = evm_lifecycle(
            pf_code, "proof-forge-authored-anvil", "uint256", cast, rpc, env
        )
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    return native, proof_forge, artifact


SOLANA_LOG = re.compile(r"^Program log: 0x(?P<event>[0-9a-f]+), 0x[0-9a-f]+, 0x(?P<value>[0-9a-f]+), 0x[0-9a-f]+, 0x[0-9a-f]+$")


def solana_binary(elf: Path, runner_name: str, env: Mapping[str, str]) -> RunnerResult:
    stdout = run([
        "cargo", "run", "--quiet", "--manifest-path", "testkit/Cargo.toml",
        "-p", "proof-forge-testkit-harness-solana", "--bin", "status_message_differential",
        "--", str(elf), runner_name,
    ], env=env, timeout=300)
    document = json.loads([line for line in stdout.splitlines() if line.strip()][-1])
    if document.get("schema") != "proof-forge.native-status-message.solana.v1":
        raise PilotError(f"unexpected Solana result schema: {document.get('schema')}")
    alice_handle = int(document["aliceHandle"])
    raw_steps = []
    for item in document["steps"]:
        values = [int(match["value"], 16) for line in item["logs"] if (match := SOLANA_LOG.match(line))]
        events = []
        if item["call"] == "set_status":
            if len(values) != 2:
                raise PilotError(f"Solana StatusSet logs malformed: {item['logs']}")
            events = [{"account": values[0], "status": values[1]}]
        elif values:
            raise PilotError(f"Solana {item['call']} emitted unexpected numeric logs: {values}")
        raw_steps.append({
            "id": item["id"], "action": item["call"], "success": item["success"],
            "returnU64": item["returnU64"], "status": item["status"], "events": events,
            "resource": item["computeUnits"],
        })
    return normalized_result("solana", runner_name, runner_name, "49" * 32, alice_handle, raw_steps, "computeUnits", 0)


def build_native_solana(output: Path, reference: Mapping[str, Any], cargo_build_sbf: str, env: Mapping[str, str]) -> Path:
    version_output = run([cargo_build_sbf, "--version"], env=env)
    for name in ("cargo-build-sbf", "platform-tools"):
        if tool_version(reference, name) not in version_output:
            raise PilotError(f"native Solana toolchain mismatch for {name}: {version_output}")
    output.mkdir(parents=True, exist_ok=True)
    run([
        cargo_build_sbf, "--manifest-path", "benchmarks/native/solana/status-message/Cargo.toml",
        "--sbf-out-dir", str(output), "--features", "bpf-entrypoint",
    ], env=env, timeout=1200)
    candidates = sorted(output.glob("*.so"))
    if len(candidates) != 1:
        raise PilotError(f"native Solana build produced {len(candidates)} ELFs")
    return candidates[0]


def build_pf_solana(output: Path, env: Mapping[str, str]) -> tuple[Path, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    elf = output / "StatusMessage.so"
    artifact_path = output / "artifact.json"
    run([
        "lake", "env", "proof-forge", "build", "--target", "solana-sbpf-asm", "--root", ".",
        "-o", str(elf), "--artifact-output", str(artifact_path),
        str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
    ], env=env, timeout=1200)
    artifact = direct_artifact(artifact_path, "solana-sbpf-asm")
    if not elf.is_file():
        raise PilotError("ProofForge Solana did not emit StatusMessage.so")
    no_legacy_sidecars(output)
    return elf, artifact


def run_solana(output: Path, reference: Mapping[str, Any], cargo_build_sbf: str, env: Mapping[str, str]):
    native = build_native_solana(output / "native", reference, cargo_build_sbf, env)
    proof_forge, artifact = build_pf_solana(output / "proof-forge", env)
    return (
        solana_binary(native, "native-pinocchio-mollusk", env),
        solana_binary(proof_forge, "proof-forge-authored-mollusk", env),
        artifact,
    )


NEAR_CALL = re.compile(r"^call (?P<call>[a-zA-Z0-9_]+): (?:(?:return_hex=(?P<return>[0-9a-f]+))|return=<none>|aborted=(?P<abort>.*)) gas=(?P<resource>[0-9]+)$")
NEAR_LOG = re.compile(r"^call (?P<call>[a-zA-Z0-9_]+): log=(?P<log>.*)$")
NEAR_ACTION = re.compile(r"^call (?P<call>[a-zA-Z0-9_]+): action=(?P<action>.*)$")


def parse_near_calls(stdout: str) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        if match := NEAR_CALL.match(line):
            calls.append({"call": match["call"], "return": match["return"], "abort": match["abort"], "resource": int(match["resource"]), "logs": [], "actions": []})
        elif match := NEAR_LOG.match(line):
            calls[-1]["logs"].append(match["log"])
        elif match := NEAR_ACTION.match(line):
            calls[-1]["actions"].append(match["action"])
    return calls


def near_event(log: str) -> dict[str, int]:
    if not log.startswith("EVENT_JSON:"):
        raise PilotError(f"NEAR non-event log: {log}")
    document = json.loads(log.removeprefix("EVENT_JSON:"))
    if document.get("standard") != "proof_forge" or document.get("event") != "StatusSet":
        raise PilotError(f"NEAR StatusSet envelope drift: {document}")
    data = document.get("data")
    if not isinstance(data, list) or len(data) != 1:
        raise PilotError(f"NEAR StatusSet data drift: {document}")
    return {"account": int(data[0]["account"]), "status": int(data[0]["status"])}


def decode_near_u64(payload: str | None, native_json: bool) -> int:
    if payload is None:
        raise PilotError("NEAR get_status returned no bytes")
    raw = bytes.fromhex(payload)
    return int(raw.decode("ascii")) if native_json else int.from_bytes(raw, "little")


def near_lifecycle(wasm: Path, runner_name: str, native_json: bool, alice_handle: int, env: Mapping[str, str]) -> RunnerResult:
    methods: list[str] = []
    inputs: list[str] = []
    groups: list[int] = []
    for _, action, status_arg, _ in STEPS:
        methods.append(action)
        if native_json:
            payload = ({"status": status_arg} if action == "set_status" else {"who": alice_handle} if action == "get_status" else {})
            inputs.append(json.dumps(payload, separators=(",", ":")).encode().hex())
        else:
            inputs.append((status_arg if action == "set_status" else alice_handle if action == "get_status" else None).to_bytes(8, "little").hex() if action != "init" else "")
        groups.append(1)
        if action != "get_status":
            methods.append("get_status")
            snapshot = json.dumps({"who": alice_handle}, separators=(",", ":")).encode() if native_json else alice_handle.to_bytes(8, "little")
            inputs.append(snapshot.hex())
            groups[-1] = 2
    stdout = run([
        "cargo", "run", "--quiet", "--manifest-path", "tools/near-vm-runner/Cargo.toml", "--",
        str(wasm), *methods, "--inputs-hex", ",".join(inputs),
        "--predecessor-account-ids", ",".join(ALICE_NEAR for _ in methods), "--continue-on-abort",
    ], env=env, timeout=1200)
    calls = parse_near_calls(stdout)
    if len(calls) != sum(groups):
        raise PilotError(f"{runner_name}: NEAR call count drift\n{stdout}")
    raw_steps = []
    cursor = 0
    for (step_id, action, _, _), group in zip(STEPS, groups, strict=True):
        main = calls[cursor]
        snapshot = main if group == 1 else calls[cursor + 1]
        cursor += group
        if main["abort"] or snapshot["abort"] or main["actions"] or snapshot["actions"]:
            raise PilotError(f"{runner_name}: NEAR step {step_id} failed or created actions")
        raw_steps.append({
            "id": step_id, "action": action, "success": True,
            "returnU64": decode_near_u64(main["return"], native_json) if action == "get_status" else None,
            "status": decode_near_u64(snapshot["return"], native_json),
            "events": [near_event(log) for log in main["logs"]], "resource": main["resource"],
        })
    return normalized_result("near", runner_name, runner_name, ALICE_NEAR, alice_handle, raw_steps, "gas", 1)


def run_near(output: Path, reference: Mapping[str, Any], env: Mapping[str, str]):
    rust_version = tool_version(reference, "rustc")
    rustc = run(["rustup", "which", "--toolchain", rust_version, "rustc"], env=env).strip()
    native_env = dict(env)
    native_env["RUSTC"] = rustc
    run([
        "rustup", "run", rust_version, "cargo", "build", "--locked", "--release",
        "--target", "wasm32-unknown-unknown", "--manifest-path", "testkit/compare/near/status-message/Cargo.toml",
    ], env=native_env, timeout=1200)
    native_wasm = REPO_ROOT / "testkit/compare/near/status-message/target/wasm32-unknown-unknown/release/pf_near_sdk_status_message_reference.wasm"
    pf_output = output / "proof-forge"
    pf_output.mkdir(parents=True, exist_ok=True)
    artifact_path = pf_output / "artifact.json"
    run([
        "lake", "env", "proof-forge", "build", "--target", "wasm-near", "--root", ".",
        "-o", str(pf_output), "--artifact-output", str(artifact_path), str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
    ], env=env)
    artifact = direct_artifact(artifact_path, "wasm-near")
    pf_wasm = pf_output / "statusmessage.wasm"
    if not native_wasm.is_file() or not pf_wasm.is_file():
        raise PilotError("StatusMessage NEAR build did not produce both Wasm artifacts")
    no_legacy_sidecars(pf_output)
    alice_handle = int.from_bytes(hashlib.sha256(ALICE_NEAR.encode()).digest()[:8], "little")
    return (
        near_lifecycle(native_wasm, "native-near-sdk-near-vm", True, alice_handle, env),
        near_lifecycle(pf_wasm, "proof-forge-authored-near-vm", False, alice_handle, env),
        artifact,
    )


def compare_family(output: Path, family: str, scenario: Mapping[str, Any], native: RunnerResult, proof_forge: RunnerResult) -> dict[str, Any]:
    write_json(output / f"{family}.native.runner-result.v1.json", native.to_json())
    write_json(output / f"{family}.proof-forge.runner-result.v1.json", proof_forge.to_json())
    report = compare_results(scenario, native, proof_forge)
    validate_observation(report, f"comparison[{family}]")
    if not report["semanticMatch"] or report["observationCoverage"]["missing"]:
        raise PilotError(f"{family} StatusMessage mismatch: {report['comparison']}")
    write_json(output / f"{family}.comparison.v1.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("build/differential/status-message"))
    parser.add_argument("--solc", default=default_solc())
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
    env = os.environ.copy()
    env["RUST_LOG"] = "error"
    env["PATH"] = os.pathsep.join([
        str(Path.home() / ".cargo/bin"), str(Path(cast).parent), str(Path(cargo_build_sbf).parent),
        str(Path.home() / ".local/share/solana/install/active_release/bin"), env.get("PATH", ""),
    ])
    native_evm, pf_evm, evm_artifact = run_evm(output / "evm", references["evm"], solc, cast, anvil, env)
    native_solana, pf_solana, solana_artifact = run_solana(output / "solana", references["solana"], cargo_build_sbf, env)
    native_near, pf_near, near_artifact = run_near(output / "near", references["near"], env)
    reports = {
        "evm": compare_family(output, "evm", scenario, native_evm, pf_evm),
        "solana": compare_family(output, "solana", scenario, native_solana, pf_solana),
        "near": compare_family(output, "near", scenario, native_near, pf_near),
    }
    summary = {
        "schema": "proof-forge.differential.status-message-evidence.v1",
        "scenario": SCENARIO_PATH.relative_to(REPO_ROOT).as_posix(),
        "productSource": {"path": PRODUCT_SOURCE.relative_to(REPO_ROOT).as_posix(), "sha256": sha256(PRODUCT_SOURCE), "sourceKind": "contract-source-authored", "irVersion": "canonical-core-v1"},
        "references": {family: {"id": reference["id"], "revision": reference["provenance"]["revision"]} for family, reference in references.items()},
        "artifacts": {family: {key: artifact[key] for key in ("target", "sourceKind", "irVersion", "sourceModule")} for family, artifact in (("evm", evm_artifact), ("solana", solana_artifact), ("near", near_artifact))},
        "semanticMatch": {family: report["semanticMatch"] for family, report in reports.items()},
        "completeCoverage": {family: not report["observationCoverage"]["missing"] for family, report in reports.items()},
    }
    write_json(output / "evidence.v1.json", summary)
    print(f"differential-status-message: ok ({output.relative_to(REPO_ROOT)}/evidence.v1.json)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PilotError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"differential-status-message: {error}", file=sys.stderr)
        raise SystemExit(1)
