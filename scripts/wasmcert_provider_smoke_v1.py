#!/usr/bin/env python3
"""Exercise the unprovisioned WasmCert provider on VerifiedVaultPF.

This is a focused engineering acceptance test. It does not activate the
provider or mint target-refinement evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


REVISION = "9ab0f87f03fff5507749efc273ec662fe27e6d14"
HOST_PROFILE = "proof-forge.near.wasmcert-host.v1"
OBSERVATION_POLICY = "proof-forge.near.strict-call-observation.v1"
LAYOUT_MARKER = 13_610_957_463_298_805_261


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def u64(value: int) -> bytes:
    return struct.pack("<Q", value)


def storage_rows(reserves: int, shares: int) -> list[dict[str, str]]:
    return [
        {"keyHex": b"pf:v1:layout".hex(), "valueHex": u64(LAYOUT_MARKER).hex()},
        {"keyHex": b"pf:v1:state:0".hex(), "valueHex": u64(reserves).hex()},
        {"keyHex": b"pf:v1:state:1".hex(), "valueHex": u64(shares).hex()},
    ]


def context(is_view: bool) -> dict[str, object]:
    zero16 = bytes(16).hex()
    return {
        "accountBalanceHex": zero16,
        "accountLockedBalanceHex": zero16,
        "attachedDepositHex": zero16,
        "blockHeightHex": u64(42).hex(),
        "blockTimestampNanosHex": u64(1_700_000_000_000_000_000).hex(),
        "currentAccountId": "vault.test.near",
        "epochHeightHex": u64(7).hex(),
        "isView": is_view,
        "outputDataReceivers": [],
        "predecessorAccountId": "alice.test.near",
        "prepaidGasHex": u64(300_000_000_000_000).hex(),
        "promiseResults": [],
        "randomSeedHex": (bytes([2]) * 32).hex(),
        "signerAccountId": "alice.test.near",
        "signerAccountPkHex": (bytes([1]) * 33).hex(),
        "storageUsageHex": u64(128).hex(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, type=Path)
    parser.add_argument("--wasm", required=True, type=Path)
    return parser.parse_args()


def require_project_relative(root: Path, path: Path, label: str) -> tuple[Path, str]:
    resolved = path.resolve(strict=True)
    try:
        relative = resolved.relative_to(root)
    except ValueError as error:
        raise SystemExit(f"{label} must be inside the repository: {resolved}") from error
    return resolved, relative.as_posix()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parent.parent
    provider, _ = require_project_relative(root, args.provider, "provider")
    wasm, wasm_relative = require_project_relative(root, args.wasm, "Wasm fixture")
    if not provider.is_file() or not provider.stat().st_mode & 0o111:
        raise SystemExit(f"provider is not an executable regular file: {provider}")
    lake = shutil.which("lake")
    if lake is None:
        raise SystemExit("lake is required for the canonical Lean artifact join")
    wasm_bytes = wasm.read_bytes()
    provider_digest = digest(provider.read_bytes())
    build_root = root / "build" / "v2"
    build_root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="wasmcert-provider-smoke-v1-", dir=build_root))
    work_relative = work.relative_to(root).as_posix()

    def execute(request_relative: str, result_relative: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(provider), "check-execute", "--request", request_relative,
             "--result", result_relative],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            env={"LC_ALL": "C", "TZ": "UTC"},
            timeout=60,
        )

    cases = [
        ("init", b"", [], False),
        ("deposit", u64(5), storage_rows(10, 10), False),
        ("withdraw", u64(5), storage_rows(10, 10), False),
        ("status", b"", storage_rows(10, 10), True),
        ("withdraw-overdraw", u64(11), storage_rows(10, 10), False),
    ]

    try:
        for case_name, input_bytes, pre_storage, is_view in cases:
            export_name = "withdraw" if case_name == "withdraw-overdraw" else case_name
            invocation = {
                "context": context(is_view),
                "exportName": export_name,
                "hostProfile": HOST_PROFILE,
                "inputHex": input_bytes.hex(),
                "observationPolicy": OBSERVATION_POLICY,
                "preStorage": pre_storage,
                "schema": "proof-forge.near.wasmcert-invocation.v1",
            }
            invocation_bytes = canonical(invocation)
            invocation_relative = f"{work_relative}/{case_name}.invocation.json"
            invocation_path = root / invocation_relative
            invocation_path.write_bytes(invocation_bytes)
            request = {
                "fuel": 100_000,
                "inputWasmPath": wasm_relative,
                "inputWasmSha256": digest(wasm_bytes),
                "invocationPath": invocation_relative,
                "invocationSha256": digest(invocation_bytes),
                "providerRevision": REVISION,
                "schema": "proof-forge.near.wasmcert-request.v1",
            }
            request_relative = f"{work_relative}/{case_name}.request.json"
            result_relative = f"{work_relative}/{case_name}.result.json"
            (root / request_relative).write_bytes(canonical(request))
            output = execute(request_relative, result_relative)
            if output.returncode != 0:
                raise SystemExit(
                    f"{case_name}: provider exit {output.returncode}: {output.stderr.strip()}"
                )
            if output.stdout or output.stderr:
                raise SystemExit(f"{case_name}: successful provider run emitted diagnostics")
            result_bytes = (root / result_relative).read_bytes()
            trace_path = root / f"{result_relative}.host-trace.pf-jcs.json"
            observation_path = root / f"{result_relative}.observation.pf-jcs.json"
            trace_bytes = trace_path.read_bytes()
            observation_bytes = observation_path.read_bytes()
            result = json.loads(result_bytes)
            observation = json.loads(observation_bytes)
            trace = json.loads(trace_bytes)
            expected_argv = [
                "check-execute", "--request", request_relative,
                "--result", result_relative,
            ]
            if result["argv"] != expected_argv or result["executableSha256"] != provider_digest:
                raise SystemExit(f"{case_name}: result identity mismatch")
            if result["executionStatus"] != observation["status"]:
                raise SystemExit(f"{case_name}: result/observation terminal status mismatch")
            if result["hostTraceSha256"] != digest(trace_bytes) or \
                    result["observationSha256"] != digest(observation_bytes):
                raise SystemExit(f"{case_name}: output artifact digest mismatch")
            if not trace["events"] or trace["events"][0]["import"] != "env.input":
                raise SystemExit(f"{case_name}: host trace is missing its input event")

        stale_paths = [
            root / result_relative,
            root / f"{result_relative}.host-trace.pf-jcs.json",
            root / f"{result_relative}.observation.pf-jcs.json",
        ]
        stale_bytes = [path.read_bytes() for path in stale_paths]
        stale = execute(request_relative, result_relative)
        if stale.returncode == 0 or stale.stdout:
            raise SystemExit("provider did not fail closed on pre-existing output artifacts")
        if [path.read_bytes() for path in stale_paths] != stale_bytes:
            raise SystemExit("provider mutated a pre-existing output artifact")

        lean = subprocess.run(
            [lake, "env", "lean", "--run",
             "Tests/Materialization/WasmCertProviderRuntimeV1.lean", work_relative],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            env={"LC_ALL": "C", "TZ": "UTC"},
            timeout=120,
        )
        if lean.returncode != 0:
            raise SystemExit(f"Lean artifact join failed:\n{lean.stdout}{lean.stderr}")
        print(lean.stdout.strip())
        print("wasmcert-provider-smoke-v1: 5/5 VerifiedVaultPF executions passed")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
