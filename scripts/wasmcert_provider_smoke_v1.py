#!/usr/bin/env python3
"""Run a locked WasmCert product acceptance or native-platform smoke.

The default mode never accepts a candidate executable or prebuilt Wasm fixture:
the selected per-platform Tool Lock supplies the executable identity, while the
Lean consumer certifies the exact VerifiedVaultPF source and materializes its
own production artifact before invoking the provider. ``--platform-smoke`` is
the narrower cross-platform CI mode. It rehashes the selected native closure and
exercises the real parser, proved checker, instantiator, and interpreter with a
minimal generated fixture; it does not claim a product or Reference join.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import tempfile


PROVIDER_ID = "wasmcert-coq-provider"
WAT2WASM_ID = "wat2wasm"
CONSUMER_TARGET = "wasmcert_provider_runtime_v1"
CONSUMER_EXE = "wasmcert-provider-runtime-v1"
PROVIDER_REVISION = "9ab0f87f03fff5507749efc273ec662fe27e6d14"


def platform_lock(root: Path) -> Path:
    machine = platform.machine().lower()
    if platform.system() == "Darwin" and machine in {"arm64", "aarch64"}:
        return root / "toolchains.lock.json"
    if platform.system() == "Linux" and machine in {"x86_64", "amd64"}:
        return root / "toolchains-linux-x86_64.lock.json"
    raise SystemExit(
        f"unsupported WasmCert product-smoke platform: {platform.system()}-{machine}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tool-root",
        type=Path,
        default=None,
        help="exact materialized Tool Root (default: PROOF_FORGE_TOOL_ROOT)",
    )
    parser.add_argument(
        "--platform-smoke",
        action="store_true",
        help=(
            "exercise the native locked provider without rebuilding the "
            "platform-independent Lean product/Reference consumer"
        ),
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_wire(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canonical_json(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def locked_environment(tool_root: Path) -> dict[str, str]:
    library_variable = (
        "DYLD_LIBRARY_PATH" if platform.system() == "Darwin" else "LD_LIBRARY_PATH"
    )
    return {
        "HOME": "/var/empty",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
        "TZ": "UTC",
        library_variable: str(tool_root / "lib"),
    }


def require_canonical_json(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"provider emitted invalid JSON at {path.name}: {error}")
    if not isinstance(value, dict) or canonical_json(value) != raw:
        raise SystemExit(f"provider emitted noncanonical JSON at {path.name}")
    return value


def run_platform_smoke(
    repository: Path,
    tool_root: Path,
    provider: dict[str, object],
    wat2wasm: dict[str, object],
) -> None:
    """Exercise the native provider closure without claiming a product join."""

    provider_executable = tool_root / str(provider["executable"])
    wat2wasm_executable = tool_root / str(wat2wasm["executable"])
    environment = locked_environment(tool_root)
    version = subprocess.run(
        [str(provider_executable), "--version"],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        timeout=10,
    )
    if (
        version.returncode != 0
        or version.stdout != str(provider["expectedVersion"]) + "\n"
        or version.stderr
    ):
        raise SystemExit(
            "locked WasmCert provider version probe failed:\n"
            f"{version.stdout}{version.stderr}"
        )

    scratch_parent = repository / "build" / "v2"
    scratch_parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    with tempfile.TemporaryDirectory(
        prefix="wasmcert-platform-smoke-", dir=scratch_parent
    ) as scratch_text:
        scratch = Path(scratch_text)
        wat_path = scratch / "input.wat"
        wasm_path = scratch / "input.wasm"
        invocation_path = scratch / "invocation.pf-jcs.json"
        request_path = scratch / "request.pf-jcs.json"
        result_path = scratch / "result.pf-jcs.json"
        wat_path.write_text(
            '(module (memory (export "memory") 1) (func (export "smoke")))\n',
            encoding="utf-8",
        )
        compile_wat = subprocess.run(
            [str(wat2wasm_executable), wat_path.name, "-o", wasm_path.name],
            cwd=scratch,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=30,
        )
        if compile_wat.returncode != 0 or compile_wat.stdout or compile_wat.stderr:
            raise SystemExit(
                "locked wat2wasm platform fixture build failed:\n"
                f"{compile_wat.stdout}{compile_wat.stderr}"
            )

        invocation = {
            "context": {
                "accountBalanceHex": "00" * 16,
                "accountLockedBalanceHex": "00" * 16,
                "attachedDepositHex": "00" * 16,
                "blockHeightHex": "00" * 8,
                "blockTimestampNanosHex": "00" * 8,
                "currentAccountId": "vault.test.near",
                "epochHeightHex": "00" * 8,
                "isView": True,
                "outputDataReceivers": [],
                "predecessorAccountId": "alice.test.near",
                "prepaidGasHex": "00" * 8,
                "promiseResults": [],
                "randomSeedHex": "02" * 32,
                "signerAccountId": "alice.test.near",
                "signerAccountPkHex": "01" * 33,
                "storageUsageHex": "00" * 8,
            },
            "exportName": "smoke",
            "hostProfile": "proof-forge.near.wasmcert-host.v1",
            "inputHex": "",
            "observationPolicy": "proof-forge.near.strict-call-observation.v1",
            "preStorage": [],
            "schema": "proof-forge.near.wasmcert-invocation.v1",
        }
        invocation_bytes = canonical_json(invocation)
        invocation_path.write_bytes(invocation_bytes)
        wasm_bytes = wasm_path.read_bytes()
        request = {
            "fuel": 10000,
            "inputWasmPath": wasm_path.name,
            "inputWasmSha256": sha256_wire(wasm_bytes),
            "invocationPath": invocation_path.name,
            "invocationSha256": sha256_wire(invocation_bytes),
            "providerRevision": PROVIDER_REVISION,
            "schema": "proof-forge.near.wasmcert-request.v1",
        }
        request_path.write_bytes(canonical_json(request))

        execution = subprocess.run(
            [
                str(provider_executable),
                "check-execute",
                "--request",
                request_path.name,
                "--result",
                result_path.name,
            ],
            cwd=scratch,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=120,
        )
        if execution.returncode != 0 or execution.stdout or execution.stderr:
            raise SystemExit(
                "locked WasmCert native platform execution failed:\n"
                f"{execution.stdout}{execution.stderr}"
            )

        trace_path = Path(str(result_path) + ".host-trace.pf-jcs.json")
        observation_path = Path(str(result_path) + ".observation.pf-jcs.json")
        trace = require_canonical_json(trace_path)
        observation = require_canonical_json(observation_path)
        result = require_canonical_json(result_path)
        invocation_digest = sha256_wire(invocation_bytes)
        expected_trace = {
            "events": [],
            "hostProfile": "proof-forge.near.wasmcert-host.v1",
            "invocationSha256": invocation_digest,
            "schema": "proof-forge.near.wasmcert-host-trace.v1",
        }
        expected_observation = {
            "hostProfile": "proof-forge.near.wasmcert-host.v1",
            "invocationSha256": invocation_digest,
            "logsHex": [],
            "postStorage": [],
            "promisesHex": [],
            "returnDataHex": None,
            "schema": "proof-forge.near.wasmcert-observation.v1",
            "status": "returned",
            "trapKind": None,
        }
        expected_result = {
            "argv": [
                "check-execute",
                "--request",
                request_path.name,
                "--result",
                result_path.name,
            ],
            "checkerStatus": "accepted-proved-sound",
            "executableSha256": "sha256:" + str(provider["executableSha256"]),
            "executionStatus": "returned",
            "hostProfile": "proof-forge.near.wasmcert-host.v1",
            "hostTraceSha256": sha256_wire(trace_path.read_bytes()),
            "inputWasmSha256": sha256_wire(wasm_bytes),
            "instantiationStatus": "accepted-proved-sound",
            "invocationSha256": invocation_digest,
            "observationSha256": sha256_wire(observation_path.read_bytes()),
            "parserStatus": "parsed-unverified",
            "providerRevision": PROVIDER_REVISION,
            "schema": "proof-forge.near.wasmcert-result.v1",
            "simdUsed": False,
        }
        if trace != expected_trace:
            raise SystemExit("locked WasmCert platform trace differs from the fixture contract")
        if observation != expected_observation:
            raise SystemExit(
                "locked WasmCert platform observation differs from the fixture contract"
            )
        if result != expected_result:
            raise SystemExit("locked WasmCert platform result differs from the fixture contract")

    print("wasmcert-provider-smoke-v1: native locked platform execution passed")


def run_consumer(
    executable: Path, repository: Path, tool_root: Path, *args: str
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update(
        {
            "LC_ALL": "C",
            "TZ": "UTC",
            "PROOF_FORGE_TOOL_ROOT": str(tool_root),
        }
    )
    return subprocess.run(
        [str(executable), *args],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        timeout=180,
    )


def require_failure(
    result: subprocess.CompletedProcess[str], label: str, diagnostic: str
) -> None:
    output = result.stdout + result.stderr
    if result.returncode == 0:
        raise SystemExit(f"{label}: unexpectedly succeeded")
    if diagnostic not in output:
        raise SystemExit(
            f"{label}: missing {diagnostic!r} diagnostic:\n{output.strip()}"
        )


def copy_locked_file(
    source_root: Path, destination_root: Path, record: dict[str, object]
) -> Path:
    relative = Path(str(record["path"]))
    source = source_root / relative
    if not source.is_file() or source.is_symlink():
        raise SystemExit(f"locked Tool Root member is absent or non-regular: {source}")
    destination = destination_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    shutil.copyfile(source, destination)
    destination.chmod(int(str(record["mode"]), 8))
    return destination


def main() -> int:
    args = parse_args()
    repository = Path(__file__).resolve().parent.parent
    lock_path = platform_lock(repository)
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    tools = [tool for tool in lock["tools"] if tool["id"] == PROVIDER_ID]
    if len(tools) != 1:
        raise SystemExit(f"{lock_path.name}: expected one {PROVIDER_ID!r} tool")
    provider = tools[0]
    wat_tools = [tool for tool in lock["tools"] if tool["id"] == WAT2WASM_ID]
    if len(wat_tools) != 1:
        raise SystemExit(f"{lock_path.name}: expected one {WAT2WASM_ID!r} tool")
    wat2wasm_tool = wat_tools[0]
    tool_root_arg = args.tool_root
    if tool_root_arg is None:
        configured = os.environ.get("PROOF_FORGE_TOOL_ROOT")
        if not configured:
            raise SystemExit("set PROOF_FORGE_TOOL_ROOT or pass --tool-root")
        tool_root_arg = Path(configured)
    tool_root = tool_root_arg.expanduser().resolve(strict=True)
    if not tool_root.is_dir() or tool_root.is_symlink():
        raise SystemExit(f"Tool Root is not a real directory: {tool_root}")

    provider_paths = [provider["executable"]] + [
        runtime["path"] for runtime in provider["runtimeFiles"]
    ]
    wat2wasm_paths = [wat2wasm_tool["executable"]] + [
        runtime["path"] for runtime in wat2wasm_tool["runtimeFiles"]
    ]
    required_paths = provider_paths + wat2wasm_paths
    records = {
        record["path"]: record
        for record in lock["bundleFiles"]
        if record["path"] in required_paths
    }
    if set(records) != set(required_paths):
        raise SystemExit("selected Tool Lock closure is incomplete")
    for path in required_paths:
        member = tool_root / path
        if not member.is_file() or member.is_symlink():
            raise SystemExit(f"Tool Root member is absent or non-regular: {member}")
        record = records[path]
        if member.stat().st_size != record["size"]:
            raise SystemExit(f"Tool Root member has the wrong size: {member}")
        if stat.S_IMODE(member.stat().st_mode) != int(str(record["mode"]), 8):
            raise SystemExit(f"Tool Root member has the wrong mode: {member}")
        if sha256_file(member) != record["sha256"]:
            raise SystemExit(f"Tool Root member has the wrong SHA-256: {member}")

    if args.platform_smoke:
        run_platform_smoke(repository, tool_root, provider, wat2wasm_tool)
        return 0

    lake = shutil.which("lake")
    if lake is None:
        raise SystemExit("lake is required for the locked WasmCert product consumer")
    # Darwin arm64 CI rebuilds theorem-heavy ProofForgeV2 from a cold or
    # partially restored Lake tree; 30 min expired while `lean` was still
    # compiling. Linux target-smoke is warm and returns early.
    build = subprocess.run(
        [lake, "build", CONSUMER_TARGET],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
        timeout=5400,
    )
    if build.returncode != 0:
        raise SystemExit(f"WasmCert product consumer build failed:\n{build.stdout}{build.stderr}")
    executable = repository / ".lake" / "build" / "bin" / CONSUMER_EXE
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit(f"built WasmCert product consumer is absent: {executable}")

    positive = run_consumer(executable, repository, tool_root)
    if positive.returncode != 0:
        raise SystemExit(
            f"locked WasmCert product consumer failed:\n{positive.stdout}{positive.stderr}"
        )
    expected = "locked WasmCert product + ReferenceMachine joins: 5/5 passed"
    if positive.stdout.strip() != expected or positive.stderr:
        raise SystemExit(
            "locked WasmCert product consumer emitted unexpected output:\n"
            f"{positive.stdout}{positive.stderr}"
        )

    scratch_parent = repository / "build" / "v2"
    scratch_parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    scratch = Path(tempfile.mkdtemp(prefix="wasmcert-locked-negative-", dir=scratch_parent))
    try:
        missing_root = scratch / "missing-root"
        missing_root.mkdir(mode=0o755)
        require_failure(
            run_consumer(executable, repository, missing_root, "resolve-only"),
            "missing WasmCert Tool Root",
            "PF-TOOLCHAIN-MISSING",
        )

        tampered_root = scratch / "tampered-executable-root"
        tampered_root.mkdir(mode=0o755)
        copied = {
            path: copy_locked_file(tool_root, tampered_root, records[path])
            for path in provider_paths
        }
        provider_copy = copied[provider["executable"]]
        provider_bytes = provider_copy.read_bytes()
        if not provider_bytes:
            raise SystemExit("locked provider executable is unexpectedly empty")
        provider_copy.chmod(0o644)
        provider_copy.write_bytes(provider_bytes[:-1] + bytes([provider_bytes[-1] ^ 1]))
        provider_copy.chmod(int(str(records[provider["executable"]]["mode"]), 8))
        require_failure(
            run_consumer(executable, repository, tampered_root, "resolve-only"),
            "tampered WasmCert executable",
            "PF-TOOLCHAIN-MISMATCH",
        )

        runtime_files = provider["runtimeFiles"]
        if runtime_files:
            tampered_runtime_root = scratch / "tampered-runtime-root"
            tampered_runtime_root.mkdir(mode=0o755)
            runtime_copies = {
                path: copy_locked_file(
                    tool_root, tampered_runtime_root, records[path]
                )
                for path in provider_paths
            }
            runtime_path = runtime_files[0]["path"]
            runtime_copy = runtime_copies[runtime_path]
            runtime_bytes = runtime_copy.read_bytes()
            if not runtime_bytes:
                raise SystemExit("locked provider runtime file is unexpectedly empty")
            runtime_copy.chmod(0o644)
            runtime_copy.write_bytes(runtime_bytes[:-1] + bytes([runtime_bytes[-1] ^ 1]))
            runtime_copy.chmod(int(str(records[runtime_path]["mode"]), 8))
            require_failure(
                run_consumer(
                    executable, repository, tampered_runtime_root, "resolve-only"
                ),
                "tampered WasmCert runtime closure",
                "PF-TOOLCHAIN-MISMATCH",
            )
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(expected)
    print("wasmcert-provider-smoke-v1: locked product and fail-closed gates passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
