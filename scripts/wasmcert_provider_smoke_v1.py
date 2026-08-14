#!/usr/bin/env python3
"""Run the locked WasmCert VerifiedVaultPF product acceptance consumer.

This script never accepts a candidate executable or a prebuilt Wasm fixture.
The selected per-platform Tool Lock supplies the executable identity, while the
Lean consumer certifies the exact source and materializes/finalizes its own
production artifact before invoking the provider.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


PROVIDER_ID = "wasmcert-coq-provider"
CONSUMER_TARGET = "wasmcert_provider_runtime_v1"
CONSUMER_EXE = "wasmcert-provider-runtime-v1"


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
    return parser.parse_args()


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
    tool_root_arg = args.tool_root
    if tool_root_arg is None:
        configured = os.environ.get("PROOF_FORGE_TOOL_ROOT")
        if not configured:
            raise SystemExit("set PROOF_FORGE_TOOL_ROOT or pass --tool-root")
        tool_root_arg = Path(configured)
    tool_root = tool_root_arg.expanduser().resolve(strict=True)
    if not tool_root.is_dir() or tool_root.is_symlink():
        raise SystemExit(f"Tool Root is not a real directory: {tool_root}")

    required_paths = [provider["executable"]] + [
        runtime["path"] for runtime in provider["runtimeFiles"]
    ]
    records = {
        record["path"]: record
        for record in lock["bundleFiles"]
        if record["path"] in required_paths
    }
    if set(records) != set(required_paths):
        raise SystemExit("provider Tool Lock closure is incomplete")
    for path in required_paths:
        member = tool_root / path
        if not member.is_file() or member.is_symlink():
            raise SystemExit(f"provider Tool Root member is absent or non-regular: {member}")
    wat2wasm = tool_root / "wat2wasm"
    if not wat2wasm.is_file() or wat2wasm.is_symlink():
        raise SystemExit(f"locked wat2wasm is required for production finalization: {wat2wasm}")

    lake = shutil.which("lake")
    if lake is None:
        raise SystemExit("lake is required for the locked WasmCert product consumer")
    build = subprocess.run(
        [lake, "build", CONSUMER_TARGET],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
        timeout=1800,
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
            for path in required_paths
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
                for path in required_paths
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
