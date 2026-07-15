#!/usr/bin/env python3
"""Run the CMP-3 ArrayExample differential on the primary target VMs."""

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


SCENARIO_PATH = REPO_ROOT / "testkit/differential/array-example/scenario.v1.json"
REFERENCE_ROOT = REPO_ROOT / "testkit/differential/array-example/references"
PRODUCT_SOURCE = REPO_ROOT / "Examples/Product/ArrayExample.lean"

ALICE_EVM_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ALICE_EVM = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
ALICE_NEAR = "alice.testnet"

STEPS: tuple[tuple[str, str, int | None], ...] = (
    ("size-of-3", "sizeOf3", 3),
    ("get-element", "getElem", 20),
    ("sum-of-3", "sumOf3", 60),
    ("out-of-bounds", "outOfBounds", None),
)


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
        raise PilotError(f"CMP-3g2 requires {label}; could not resolve {value!r}")
    return resolved


def default_solc() -> str:
    configured = os.environ.get("PF_CMP_SOLC")
    if configured:
        return configured
    pinned = REPO_ROOT / "build/toolchains/solc-0.8.30"
    return str(pinned) if pinned.is_file() else "solc"


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
        "sourceModule": "ArrayExample",
    }
    mismatches = {
        key: (value, document.get(key))
        for key, value in expected.items()
        if document.get(key) != value
    }
    if mismatches:
        raise PilotError(f"{path.relative_to(REPO_ROOT)} is not a direct ArrayExample artifact: {mismatches}")
    return document


def no_legacy_sidecars(root: Path) -> None:
    forbidden = sorted(root.rglob("*contract-spec*")) + sorted(root.rglob("*ir-module*"))
    if forbidden:
        names = ", ".join(path.relative_to(REPO_ROOT).as_posix() for path in forbidden)
        raise PilotError(f"direct ArrayExample output contains forbidden legacy sidecars: {names}")


def context(family: str, implementation: str, native_height: int | None = None) -> RunnerContext:
    return RunnerContext(
        accounts=(LogicalAccount("contract", f"array-example.{implementation}.{family}", ("contract",)),),
        actors=(LogicalActor("caller", "contract", ("caller",)),),
        clock=LogicalClock(tick=0, native_height=native_height),
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
    for index, ((step_id, action, expected_return), raw) in enumerate(zip(STEPS, raw_steps, strict=True)):
        if raw.get("id") != step_id or raw.get("action") != action:
            raise PilotError(f"{runner_name}: step {index} identity mismatch: {raw}")
        expected_success = expected_return is not None
        if bool(raw.get("success")) != expected_success:
            raise PilotError(
                f"{runner_name}: step {step_id} success={raw.get('success')}, expected {expected_success}"
            )
        if raw.get("returnU64") != expected_return:
            raise PilotError(
                f"{runner_name}: step {step_id} returned {raw.get('returnU64')}, expected {expected_return}"
            )
        if not expected_success and not raw.get("error"):
            raise PilotError(f"{runner_name}: out-of-bounds call failed without native error evidence")
        if raw.get("events") != [] or raw.get("externalActions") != []:
            raise PilotError(f"{runner_name}: step {step_id} observed target-specific side effects")

        status = (
            {"status": "success", "errorCategory": None, "errorData": None}
            if expected_success
            else {
                "status": "revert",
                "errorCategory": "assertion",
                "errorData": {"kind": "array-index-out-of-bounds"},
            }
        )
        return_value = (
            NormalizedValue.u64(expected_return).to_json()
            if expected_return is not None
            else NormalizedValue.unit().to_json()
        )
        observations = {
            "callStatus": status,
            "returnValue": return_value,
            "state": {},
            "balances": {},
            "events": [],
            "externalActions": [],
            "interface": {
                "entrypoint": action,
                "mutability": "view",
                "params": [],
                "returns": "u64",
            },
            "resources": ResourceObservation(
                family,
                {"execution": {"value": int(raw["resource"]), "unit": resource_unit}},
            ).to_json(),
        }
        steps.append(StepResult(step_id, observations))
    return RunnerResult(
        scenario_id="portable-array-example-primary-triad",
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


def evm_calls(
    init_code: str,
    runner_name: str,
    cast: str,
    rpc: str,
    env: Mapping[str, str],
) -> RunnerResult:
    deploy = cast_receipt(
        [cast, "send", "--rpc-url", rpc, "--private-key", ALICE_EVM_KEY, "--create", f"0x{init_code}", "--json"],
        env,
    )
    address = deploy.get("contractAddress")
    if not isinstance(address, str) or not address:
        raise PilotError(f"{runner_name}: deployment returned no contract address")

    raw_steps: list[dict[str, Any]] = []
    for step_id, action, expected_return in STEPS:
        signature = f"{action}()(uint64)"
        if expected_return is not None:
            returned = parse_number(
                run([cast, "call", "--rpc-url", rpc, address, signature], env=env).strip()
            )
            resource = parse_number(
                run([cast, "estimate", "--rpc-url", rpc, "--from", ALICE_EVM, address, signature], env=env).strip()
            )
            success = True
            native_error = None
        else:
            receipt = cast_receipt(
                [cast, "send", "--rpc-url", rpc, "--private-key", ALICE_EVM_KEY,
                 "--gas-limit", "1000000", address, f"{action}()", "--json"],
                env,
            )
            success = parse_number(receipt.get("status", "0x1")) == 1
            returned = None
            resource = parse_number(receipt["gasUsed"])
            native_error = None if success else f"receipt-status={receipt.get('status')}"
        raw_steps.append(
            {
                "id": step_id,
                "action": action,
                "success": success,
                "error": native_error,
                "returnU64": returned,
                "events": [],
                "externalActions": [],
                "resource": resource,
            }
        )
    return normalized_result("evm", runner_name, runner_name, raw_steps, "gas")


def compile_native_evm(solc: str, output: Path, reference: Mapping[str, Any]) -> str:
    version_output = run([solc, "--version"])
    version = tool_version(reference, "solc")
    if f"Version: {version}" not in version_output:
        raise PilotError(f"ArrayExample EVM reference requires solc {version}; got:\n{version_output}")
    output.mkdir(parents=True, exist_ok=True)
    source = REPO_ROOT / reference["source"]["path"]
    document = json.loads(run([solc, "--combined-json", "abi,bin", str(source)]))
    matches = [value for key, value in document.get("contracts", {}).items() if key.endswith(":ArrayExample")]
    if len(matches) != 1:
        raise PilotError(f"solc returned {len(matches)} ArrayExample contracts")
    contract = matches[0]
    abi = contract["abi"] if isinstance(contract["abi"], list) else json.loads(contract["abi"])
    functions = {entry["name"] for entry in abi if entry.get("type") == "function"}
    if functions != {action for _, action, _ in STEPS}:
        raise PilotError(f"native Solidity ArrayExample ABI functions drift: {sorted(functions)}")
    write_json(output / "abi.json", {"abi": abi})
    return str(contract["bin"])


def build_pf_evm(output: Path, env: Mapping[str, str], cast: str) -> tuple[str, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    artifact_path = output / "ArrayExample.proof-forge-artifact.json"
    run(
        [
            "lake", "env", "proof-forge", "build", "--target", "evm", "--root", ".",
            "-o", str(output / "ArrayExample.bin"), "--artifact-output", str(artifact_path),
            "--cast", cast, str(PRODUCT_SOURCE.relative_to(REPO_ROOT)),
        ],
        env=env,
    )
    artifact = direct_artifact(artifact_path, "evm")
    names = {entry["name"] for entry in artifact.get("abi", {}).get("entrypoints", [])}
    if names != {action for _, action, _ in STEPS}:
        raise PilotError(f"ProofForge EVM artifact has unexpected entrypoints: {sorted(names)}")
    init_path = output / "ArrayExample.init.bin"
    if not init_path.is_file():
        raise PilotError("ProofForge EVM direct build did not produce ArrayExample.init.bin")
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
                raise PilotError(f"Anvil exited before ArrayExample execution: {stderr}")
            probe = subprocess.run(
                [cast, "block-number", "--rpc-url", rpc], cwd=REPO_ROOT, env=dict(env),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            if probe.returncode == 0:
                break
            time.sleep(0.1)
        else:
            raise PilotError(f"Anvil did not become ready at {rpc}")
        native = evm_calls(native_code, "native-solidity-anvil", cast, rpc, env)
        proof_forge = evm_calls(pf_code, "proof-forge-authored-anvil", cast, rpc, env)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    return native, proof_forge, artifact


def run_solana_binary(elf: Path, runner_name: str, env: Mapping[str, str]) -> RunnerResult:
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "testkit/Cargo.toml",
            "-p", "proof-forge-testkit-harness-solana", "--bin", "array_example_differential",
            "--", str(elf), runner_name,
        ],
        env=env,
        timeout=300,
    )
    lines = [line for line in stdout.splitlines() if line.strip()]
    document = json.loads(lines[-1])
    if document.get("schema") != "proof-forge.native-array-example.solana.v1":
        raise PilotError(f"Solana runner returned unexpected schema: {document.get('schema')}")
    raw_steps = [
        {
            "id": item["id"],
            "action": item["call"],
            "success": item["success"],
            "error": item["error"],
            "returnU64": item["returnU64"],
            "events": [],
            "externalActions": [],
            "resource": item["computeUnits"],
        }
        for item in document["steps"]
    ]
    return normalized_result("solana", runner_name, runner_name, raw_steps, "computeUnits", 0)


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
            cargo_build_sbf, "--manifest-path", "benchmarks/native/solana/array-example/Cargo.toml",
            "--sbf-out-dir", str(output), "--features", "bpf-entrypoint",
        ],
        env=env,
        timeout=1200,
    )
    candidates = sorted(output.glob("*.so"))
    if len(candidates) != 1:
        raise PilotError(f"native Solana build produced {len(candidates)} ELF candidates in {output}")
    return candidates[0]


def build_pf_solana(output: Path, env: Mapping[str, str]) -> tuple[Path, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    elf = output / "ArrayExample.so"
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
    if names != {action for _, action, _ in STEPS}:
        raise PilotError(f"ProofForge Solana IDL has unexpected entrypoints: {sorted(names)}")
    if not elf.is_file():
        raise PilotError("ProofForge Solana direct build did not produce ArrayExample.so")
    no_legacy_sidecars(output)
    return elf, artifact


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
        raise PilotError(f"{label}: expected u64 return bytes")
    payload = bytes.fromhex(payload_hex)
    value = json.loads(payload.decode("utf-8")) if native_json else int.from_bytes(payload, "little")
    if not isinstance(value, int):
        raise PilotError(f"{label}: expected integer return, got {value!r}")
    return value


def near_calls(
    wasm: Path,
    runner_name: str,
    methods: Sequence[str],
    native_json: bool,
    env: Mapping[str, str],
) -> RunnerResult:
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "tools/near-vm-runner/Cargo.toml",
            "--", str(wasm), *methods, "--inputs-hex", ",".join("" for _ in methods),
            "--predecessor-account-ids", ",".join(ALICE_NEAR for _ in methods),
            "--continue-on-abort",
        ],
        env=env,
        timeout=1200,
    )
    calls = parse_near_calls(stdout, runner_name)
    if len(calls) != len(STEPS):
        raise PilotError(f"{runner_name}: expected {len(STEPS)} NEAR calls, got {len(calls)}\n{stdout}")
    raw_steps: list[dict[str, Any]] = []
    for (step_id, action, expected_return), method, call in zip(STEPS, methods, calls, strict=True):
        if call["call"] != method:
            raise PilotError(f"{runner_name}: expected NEAR method {method}, got {call['call']}")
        if call["logs"] or call["actions"]:
            raise PilotError(f"{runner_name}: portable ArrayExample unexpectedly created NEAR side effects")
        raw_steps.append(
            {
                "id": step_id,
                "action": action,
                "success": call["abort"] is None,
                "error": call["abort"],
                "returnU64": (
                    decode_near_u64(call["return"], native_json, f"{runner_name}:{step_id}")
                    if expected_return is not None
                    else None
                ),
                "events": [],
                "externalActions": [],
                "resource": call["resource"],
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
            "testkit/compare/near/array-example/Cargo.toml",
        ],
        env=native_env,
        timeout=1200,
    )
    native_wasm = (
        REPO_ROOT
        / "testkit/compare/near/array-example/target/wasm32-unknown-unknown/release/pf_near_sdk_array_example_reference.wasm"
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
    if names != {action for _, action, _ in STEPS}:
        raise PilotError(f"ProofForge NEAR artifact has unexpected entrypoints: {sorted(names)}")
    pf_wasm = pf_output / "arrayexample.wasm"
    if not pf_wasm.is_file():
        raise PilotError("ProofForge NEAR direct build did not produce arrayexample.wasm")
    no_legacy_sidecars(pf_output)

    native = near_calls(
        native_wasm,
        "native-near-sdk-near-vm",
        ("size_of3", "get_elem", "sum_of3", "out_of_bounds"),
        True,
        env,
    )
    proof_forge = near_calls(
        pf_wasm,
        "proof-forge-authored-near-vm",
        tuple(action for _, action, _ in STEPS),
        False,
        env,
    )
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
        raise PilotError(f"{family} ArrayExample differential did not semantically match: {report['comparison']}")
    if report["observationCoverage"]["missing"]:
        raise PilotError(f"{family} ArrayExample differential has incomplete coverage")
    write_json(output / f"{family}.comparison.v1.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("build/differential/array-example"))
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

    native_evm, pf_evm, evm_artifact = run_evm(
        output / "evm", references["evm"], solc, cast, anvil, env
    )
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
        "schema": "proof-forge.differential.array-example-evidence.v1",
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
    print(f"differential-array-example: ok ({output.relative_to(REPO_ROOT)}/evidence.v1.json)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PilotError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"differential-array-example: {error}", file=sys.stderr)
        raise SystemExit(1)
