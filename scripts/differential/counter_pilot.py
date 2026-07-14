#!/usr/bin/env python3
"""Run the CMP-2 Counter pilot against independent primary-triad references."""

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


SCENARIO_PATH = REPO_ROOT / "testkit/differential/counter/scenario.v1.json"
REFERENCE_ROOT = REPO_ROOT / "testkit/differential/counter/references"
PRODUCT_SOURCE = REPO_ROOT / "Examples/Product/Counter.lean"
STEP_IDS = ("initialize", "get-zero", "increment", "get-one")
STEP_CALLS = ("initialize", "get", "increment", "get")
EXPECTED_STATE = (0, 0, 1, 1)
DEFAULT_ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"


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
        raise PilotError(f"CMP-2 requires {label}; could not resolve {value!r}")
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
    revision = document["provenance"]["revision"]
    actual = f"sha256:{sha256(source)}"
    if revision != actual:
        raise PilotError(
            f"{family} reference revision is stale: manifest={revision}, source={actual}"
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
        "sourceModule": "Counter",
    }
    mismatches = {
        key: (value, document.get(key))
        for key, value in expected.items()
        if document.get(key) != value
    }
    if mismatches:
        raise PilotError(f"{path.relative_to(REPO_ROOT)} is not a direct Counter artifact: {mismatches}")
    return document


def no_legacy_sidecars(root: Path) -> None:
    forbidden = sorted(root.rglob("*contract-spec.json"))
    if forbidden:
        names = ", ".join(path.relative_to(REPO_ROOT).as_posix() for path in forbidden)
        raise PilotError(f"direct CMP-2 output contains forbidden ContractSpec sidecars: {names}")


def context(family: str, implementation: str) -> RunnerContext:
    return RunnerContext(
        accounts=(
            LogicalAccount("contract", f"counter.{implementation}.{family}", ("contract",)),
            LogicalAccount("alice", f"alice.{implementation}.{family}", ("caller",)),
        ),
        actors=(LogicalActor("alice", "alice", ("caller",)),),
        clock=LogicalClock(tick=0),
    )


def normalized_result(
    family: str,
    runner_name: str,
    implementation: str,
    raw_steps: Sequence[Mapping[str, Any]],
    resource_unit: str,
) -> RunnerResult:
    if len(raw_steps) != len(STEP_IDS):
        raise PilotError(f"{runner_name}: expected four steps, got {len(raw_steps)}")
    steps: list[StepResult] = []
    for index, (expected_id, expected_call, expected_state, raw) in enumerate(
        zip(STEP_IDS, STEP_CALLS, EXPECTED_STATE, raw_steps, strict=True)
    ):
        if raw.get("id") != expected_id or raw.get("call") != expected_call:
            raise PilotError(
                f"{runner_name}: step {index} identity mismatch: expected {expected_id}/{expected_call}, got {raw}"
            )
        if raw.get("state") != expected_state:
            raise PilotError(
                f"{runner_name}: step {expected_id} observed count={raw.get('state')}, expected {expected_state}"
            )
        return_value = (
            NormalizedValue.u64(expected_state).to_json()
            if expected_call == "get"
            else NormalizedValue.unit().to_json()
        )
        if expected_call == "get" and raw.get("returnU64") != expected_state:
            raise PilotError(
                f"{runner_name}: {expected_id} returned {raw.get('returnU64')}, expected {expected_state}"
            )
        observations = {
            "callStatus": {"status": "success", "errorCategory": None, "errorData": None},
            "returnValue": return_value,
            "state": {"count": NormalizedValue.u64(expected_state).to_json()},
            "balances": {},
            "events": [],
            "externalActions": [],
            "interface": {
                "entrypoint": expected_call,
                "mutability": "view" if expected_call == "get" else "call",
                "params": [],
                "returns": "u64" if expected_call == "get" else "unit",
            },
            "resources": ResourceObservation(
                family,
                {"execution": {"value": int(raw["resource"]), "unit": resource_unit}},
            ).to_json(),
        }
        steps.append(StepResult(expected_id, observations))
    return RunnerResult(
        scenario_id="portable-counter-primary-triad",
        target_family=family,
        runner_name=runner_name,
        status="executed",
        provenance_complete=True,
        context=context(family, implementation),
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


def evm_lifecycle(
    init_code: str,
    runner_name: str,
    cast: str,
    rpc: str,
    env: Mapping[str, str],
) -> RunnerResult:
    receipt = cast_receipt(
        [cast, "send", "--rpc-url", rpc, "--private-key", DEFAULT_ANVIL_KEY, "--create", f"0x{init_code}", "--json"],
        env,
    )
    address = receipt.get("contractAddress")
    if not isinstance(address, str) or not address:
        raise PilotError(f"{runner_name}: deployment returned no contract address")

    raw_steps: list[dict[str, Any]] = []
    for step_id, call in zip(STEP_IDS, STEP_CALLS, strict=True):
        signature = f"{call}()(uint64)" if call == "get" else f"{call}()"
        estimate = parse_number(run([cast, "estimate", "--rpc-url", rpc, address, signature], env=env).strip())
        if call != "get":
            call_receipt = cast_receipt(
                [cast, "send", "--rpc-url", rpc, "--private-key", DEFAULT_ANVIL_KEY, address, signature, "--json"],
                env,
            )
            resource = parse_number(call_receipt.get("gasUsed", estimate))
        else:
            resource = estimate
        get_output = run([cast, "call", "--rpc-url", rpc, address, "get()(uint64)"], env=env).strip()
        state = parse_number(get_output)
        raw_steps.append(
            {
                "id": step_id,
                "call": call,
                "returnU64": state if call == "get" else None,
                "state": state,
                "resource": resource,
            }
        )
    return normalized_result("evm", runner_name, runner_name, raw_steps, "gas")


def compile_native_evm(solc: str, output: Path, reference: Mapping[str, Any]) -> tuple[str, list[dict[str, Any]]]:
    version_output = run([solc, "--version"])
    version = tool_version(reference, "solc")
    if f"Version: {version}" not in version_output:
        raise PilotError(f"CMP-2 EVM reference requires solc {version}; got:\n{version_output}")
    output.mkdir(parents=True, exist_ok=True)
    source = REPO_ROOT / reference["source"]["path"]
    document = json.loads(run([solc, "--combined-json", "abi,bin", str(source)]))
    contracts = document.get("contracts", {})
    matches = [value for key, value in contracts.items() if key.endswith(":Counter")]
    if len(matches) != 1:
        raise PilotError(f"solc returned {len(matches)} Counter contracts")
    contract = matches[0]
    abi = contract["abi"] if isinstance(contract["abi"], list) else json.loads(contract["abi"])
    functions = {
        (entry["name"], entry.get("stateMutability"), tuple(item["type"] for item in entry.get("outputs", [])))
        for entry in abi
        if entry.get("type") == "function"
    }
    expected = {
        ("initialize", "nonpayable", ()),
        ("increment", "nonpayable", ()),
        ("get", "view", ("uint64",)),
        ("count", "view", ("uint64",)),
    }
    if functions != expected:
        raise PilotError(f"native Solidity Counter ABI mismatch: {sorted(functions)}")
    write_json(output / "abi.json", {"abi": abi})
    (output / "Counter.bin").write_text(str(contract["bin"]) + "\n", encoding="ascii")
    return str(contract["bin"]), abi


def build_pf_evm(output: Path, env: Mapping[str, str], cast: str) -> tuple[str, dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    bytecode = output / "Counter.bin"
    artifact_path = output / "Counter.proof-forge-artifact.json"
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
    if names != {"initialize", "increment", "get"}:
        raise PilotError(f"ProofForge EVM artifact has unexpected ABI entrypoints: {sorted(names)}")
    init_path = output / "Counter.init.bin"
    if not init_path.is_file():
        raise PilotError("ProofForge EVM direct build did not produce Counter.init.bin")
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
    native_code, _ = compile_native_evm(solc, output / "native", reference)
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
                raise PilotError(f"Anvil exited before CMP-2 execution: {stderr}")
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
        native = evm_lifecycle(native_code, "native-solidity-anvil", cast, rpc, env)
        proof_forge = evm_lifecycle(pf_code, "proof-forge-authored-anvil", cast, rpc, env)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    return native, proof_forge, artifact


SOLANA_TRACE = re.compile(
    r"^solana-sbpf-asm call \d+:(?P<call>[a-zA-Z0-9_]+): "
    r"return_hex=(?P<return>[0-9a-f]*) solana_cu=(?P<resource>[0-9]+)$"
)


def run_pf_solana(output: Path, env: Mapping[str, str]) -> tuple[RunnerResult, dict[str, Any]]:
    harness_output = REPO_ROOT / "build/testkit/solana/counter"
    shutil.rmtree(harness_output, ignore_errors=True)
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "testkit/Cargo.toml",
            "-p", "proof-forge-testkit", "--", "run", "--scenario", "counter",
            "--target", "solana-sbpf-asm", "--trace", "--deny-skip",
        ],
        env=env,
        timeout=1200,
    )
    parsed = [match.groupdict() for line in stdout.splitlines() if (match := SOLANA_TRACE.match(line))]
    if len(parsed) != 4:
        raise PilotError(f"ProofForge Solana runner emitted {len(parsed)} trace rows:\n{stdout}")
    raw_steps = []
    for step_id, state, item in zip(STEP_IDS, EXPECTED_STATE, parsed, strict=True):
        returned = item["return"]
        return_u64 = int.from_bytes(bytes.fromhex(returned), "little") if returned else None
        raw_steps.append(
            {
                "id": step_id,
                "call": item["call"],
                "returnU64": return_u64,
                "state": state,
                "resource": int(item["resource"]),
            }
        )
    artifact = direct_artifact(harness_output / "proof-forge-artifact.json", "solana-sbpf-asm")
    idl_path = Path(artifact["artifacts"]["solanaIdl"]["path"])
    idl = read_json(idl_path if idl_path.is_absolute() else REPO_ROOT / idl_path)
    names = {entry["name"] for entry in idl.get("instructions", [])}
    if names != {"initialize", "increment", "get"}:
        raise PilotError(f"ProofForge Solana IDL has unexpected entrypoints: {sorted(names)}")
    no_legacy_sidecars(harness_output)
    return (
        normalized_result(
            "solana", "proof-forge-authored-mollusk", "proof-forge", raw_steps, "computeUnits"
        ),
        artifact,
    )


def run_native_solana(
    output: Path,
    reference: Mapping[str, Any],
    cargo_build_sbf: str,
    env: Mapping[str, str],
) -> RunnerResult:
    version_output = run([cargo_build_sbf, "--version"], env=env)
    for name in ("cargo-build-sbf", "platform-tools"):
        expected = tool_version(reference, name)
        if expected not in version_output:
            raise PilotError(f"native Solana reference requires {name} {expected}; got:\n{version_output}")
    sbf_output = output / "sbf"
    sbf_output.mkdir(parents=True, exist_ok=True)
    run(
        [
            cargo_build_sbf,
            "--manifest-path", "benchmarks/native/solana/counter/Cargo.toml",
            "--sbf-out-dir", str(sbf_output),
            "--features", "bpf-entrypoint",
        ],
        env=env,
        timeout=1200,
    )
    candidates = sorted(sbf_output.glob("*.so"))
    if len(candidates) != 1:
        raise PilotError(f"native Solana build produced {len(candidates)} ELF candidates in {sbf_output}")
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "testkit/Cargo.toml",
            "-p", "proof-forge-testkit-harness-solana", "--bin", "native_counter", "--",
            str(candidates[0]),
        ],
        env=env,
        timeout=300,
    )
    lines = [line for line in stdout.splitlines() if line.strip()]
    document = json.loads(lines[-1])
    if document.get("schema") != "proof-forge.native-counter.solana.v1":
        raise PilotError(f"native Solana runner returned unexpected schema: {document.get('schema')}")
    raw_steps = [
        {
            "id": step["id"],
            "call": step["call"],
            "returnU64": step["returnU64"],
            "state": step["state"]["count"],
            "resource": step["computeUnits"],
        }
        for step in document["steps"]
    ]
    return normalized_result("solana", "native-pinocchio-mollusk", "native", raw_steps, "computeUnits")


NEAR_RETURN = re.compile(
    r"^call (?P<call>[a-zA-Z0-9_]+): (?:return_hex=(?P<return>[0-9a-f]+)|return=<none>) gas=(?P<resource>[0-9]+)$"
)


def near_lifecycle(wasm: Path, runner_name: str, native_json: bool, env: Mapping[str, str]) -> RunnerResult:
    stdout = run(
        [
            "cargo", "run", "--quiet", "--manifest-path", "tools/near-vm-runner/Cargo.toml",
            "--", str(wasm), "initialize", "get", "increment", "get",
        ],
        env=env,
        timeout=900,
    )
    parsed = [match.groupdict() for line in stdout.splitlines() if (match := NEAR_RETURN.match(line))]
    if len(parsed) != 4:
        raise PilotError(f"{runner_name}: near-vm-runner emitted {len(parsed)} call rows:\n{stdout}")
    raw_steps = []
    for step_id, state, item in zip(STEP_IDS, EXPECTED_STATE, parsed, strict=True):
        returned = item["return"]
        return_u64 = None
        if returned is not None:
            payload = bytes.fromhex(returned)
            return_u64 = int(payload.decode("ascii")) if native_json else int.from_bytes(payload, "little")
        raw_steps.append(
            {
                "id": step_id,
                "call": item["call"],
                "returnU64": return_u64,
                "state": state,
                "resource": int(item["resource"]),
            }
        )
    return normalized_result("near", runner_name, runner_name, raw_steps, "gas")


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
            "benchmarks/native/near/counter-rs/Cargo.toml",
        ],
        env=native_env,
        timeout=1200,
    )
    native_wasm = (
        REPO_ROOT
        / "benchmarks/native/near/counter-rs/target/wasm32-unknown-unknown/release/proofforge_benchmark_native_near_counter.wasm"
    )
    if not native_wasm.is_file():
        raise PilotError(f"native NEAR build did not produce {native_wasm.relative_to(REPO_ROOT)}")

    pf_output = output / "proof-forge"
    pf_output.mkdir(parents=True, exist_ok=True)
    artifact_path = pf_output / "Counter.near-artifact.json"
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
    if names != {"initialize", "increment", "get"}:
        raise PilotError(f"ProofForge NEAR artifact has unexpected entrypoints: {sorted(names)}")
    pf_wasm = pf_output / "counter.wasm"
    if not pf_wasm.is_file():
        raise PilotError("ProofForge NEAR direct build did not produce counter.wasm")
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
        raise PilotError(f"{family} Counter differential did not semantically match: {report['comparison']}")
    if report["observationCoverage"]["missing"]:
        raise PilotError(f"{family} Counter differential has incomplete coverage")
    write_json(output / f"{family}.comparison.v1.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("build/differential/counter"))
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
            str(Path(cargo_build_sbf).parent),
            str(Path.home() / ".cargo/bin"),
            str(Path.home() / ".local/share/solana/install/active_release/bin"),
            env.get("PATH", ""),
        ]
    )

    native_evm, pf_evm, evm_artifact = run_evm(output / "evm", references["evm"], solc, cast, anvil, env)
    pf_solana, solana_artifact = run_pf_solana(output / "solana/proof-forge", env)
    native_solana = run_native_solana(output / "solana/native", references["solana"], cargo_build_sbf, env)
    native_near, pf_near, near_artifact = run_near(output / "near", references["near"], env)

    reports = {
        "evm": compare_family(output, "evm", scenario, native_evm, pf_evm),
        "solana": compare_family(output, "solana", scenario, native_solana, pf_solana),
        "near": compare_family(output, "near", scenario, native_near, pf_near),
    }
    summary = {
        "schema": "proof-forge.differential.counter-evidence.v1",
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
    print(f"differential-counter: ok ({output.relative_to(REPO_ROOT)}/evidence.v1.json)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PilotError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"differential-counter: {error}", file=sys.stderr)
        raise SystemExit(1)
