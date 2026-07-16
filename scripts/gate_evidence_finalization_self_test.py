#!/usr/bin/env python3
"""Pre-acceptance fail-closed contract for development evidence finalization."""

from __future__ import annotations

import copy
import datetime as dt
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
GATE_EVIDENCE = ROOT / "scripts" / "gate_evidence.py"
EVIDENCE_CORE = ROOT / "scripts" / "evidence_v1_core.py"


def sha256(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def domain_sha256(domain: bytes, body: bytes) -> str:
    return hashlib.sha256(domain + b"\x00" + body).hexdigest()


def load_gate_evidence() -> object:
    spec = importlib.util.spec_from_file_location(
        "_proof_forge_gate_evidence_finalization_fixture", GATE_EVIDENCE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load scripts/gate_evidence.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_secure(path: Path, body: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_bytes(body)
    path.chmod(0o400)


def replace_secure(path: Path, body: bytes) -> None:
    path.chmod(0o600)
    path.write_bytes(body)
    path.chmod(0o400)


def write_formal_bundle(module: object, root: Path) -> None:
    document = module._sample_document(formal=True)
    document["command"]["startedUtc"] = "2026-07-15T00:00:00Z"
    document["command"]["endedUtc"] = "2026-07-15T00:00:00Z"
    document["command"]["durationMs"] = 7
    files = {
        "candidate.tar": b"synthetic candidate archive\n",
        "build/evm/Counter.bin": b"synthetic counter bytecode\n",
        "build/logs/gate.stderr": b"",
        "build/logs/gate.stdout": b"synthetic gate output\n",
    }
    for relative, body in files.items():
        write_secure(root / relative, body)

    claims = document["inputs"] + document["artifacts"] + document["logs"]
    for claim in claims:
        body = files[claim["path"]]
        claim["size"] = len(body)
        claim["sha256"] = hashlib.sha256(body).hexdigest()
    archive = document["repository"]["archive"]
    archive["size"] = len(files["candidate.tar"])
    archive["sha256"] = hashlib.sha256(files["candidate.tar"]).hexdigest()
    document["artifactSetSha256"] = module.artifact_set_sha256(document["artifacts"])
    module.validate_evidence(document)
    write_secure(root / "formal-evidence.json", module.canonical_bytes(document))


def write_realistic_development_bundle(
    module: object, root: Path
) -> tuple[dict[str, object], str, str, str, str]:
    """Write one canonical, internally consistent H1e-b development bundle."""
    canonical = module.canonical_bytes
    candidate = b"synthetic stable candidate archive\n"
    artifact = b"synthetic retained Counter bytecode\n"
    gate_launcher = (ROOT / "scripts" / "verify_isolation.sh").read_bytes()
    host_bootstrap = (ROOT / "host-bootstrap.lock").read_bytes()
    host_profile = (ROOT / "host-profiles.lock.json").read_bytes()
    toolchain_lock = (ROOT / "toolchains.lock.json").read_bytes()
    stage0_launcher = (ROOT / "scripts" / "verify_host_stage0.sh").read_bytes()
    stage0_verifier = (ROOT / "scripts" / "toolchain_assets.py").read_bytes()
    sandbox_launcher = (ROOT / "scripts" / "sandbox_exec.py").read_bytes()
    sandbox_renderer = (ROOT / "scripts" / "sandbox_policy.py").read_bytes()
    evidence_core = EVIDENCE_CORE.read_bytes()
    evidence_validator = GATE_EVIDENCE.read_bytes()
    probe_wrapper = (
        b"#!/usr/bin/env python3\n"
        b"# Synthetic, catalog-locked permission-denial probe fixture.\n"
    )
    engine_sha256 = sha256(b"synthetic observed /usr/bin/sandbox-exec bytes\n")
    lean_executable_sha256 = sha256(b"synthetic observed lean executable bytes\n")
    lean_closure_sha256 = sha256(b"synthetic lean runtime closure\n")
    lean_runtime_executable_sha256 = sha256(b"synthetic closure-only executable\n")
    lean_runtime_closure_sha256 = sha256(b"synthetic closure-only runtime closure\n")
    environment_sha256 = domain_sha256(
        b"pf.clean-room.environment.v1", b"synthetic environment"
    )
    core_template_sha256 = sha256(b"synthetic core policy template\n")
    runtime_template_sha256 = sha256(b"synthetic runtime policy template\n")
    core_policy = b"(version 1)\n(deny default)\n"
    runtime_port = 18545
    runtime_policy = (
        b"(version 1)\n"
        b"(deny default)\n"
        + f'(allow network-inbound (local ip "localhost:{runtime_port}"))\n'.encode(
            "ascii"
        )
        + f'(allow network-outbound (remote ip "localhost:{runtime_port}"))\n'.encode(
            "ascii"
        )
    )
    gate_stdout = b"synthetic clean-room gate passed\n"
    gate_stderr = b""
    core_stdout = b"Lean 4.31.0 synthetic\n"
    core_stderr = b""
    denial_stdout = b""
    denial_stderr = b"PF-SANDBOX-PROBE-DENIED\n"
    runtime_stdout = b"synthetic runtime returned 3\n"
    runtime_stderr = b""

    catalog_path = "catalog/development-alpha.json"
    run_context_path = "run-context.json"
    observation_path = "host/observation.json"
    core_policy_path = "policies/core.sb"
    runtime_policy_path = "policies/evm-runtime.sb"
    core_context_path = "contexts/sandbox-core-core-success.json"
    denial_context_path = "contexts/sandbox-core-file-read-denied.json"
    runtime_context_path = "contexts/sandbox-evm-runtime-runtime-success.json"
    core_receipt_path = "policies/sandbox-core-core-success.receipt.json"
    denial_receipt_path = "policies/sandbox-core-file-read-denied.receipt.json"
    runtime_receipt_path = "policies/sandbox-evm-runtime-runtime-success.receipt.json"
    core_stdout_path = "policies/sandbox-core-core-success.stdout.log"
    core_stderr_path = "policies/sandbox-core-core-success.stderr.log"
    denial_stdout_path = "policies/sandbox-core-file-read-denied.stdout.log"
    denial_stderr_path = "policies/sandbox-core-file-read-denied.stderr.log"
    runtime_stdout_path = "policies/sandbox-evm-runtime-runtime-success.stdout.log"
    runtime_stderr_path = "policies/sandbox-evm-runtime-runtime-success.stderr.log"
    artifact_path = "build/evm/Counter.bin"
    gate_stdout_path = "build/logs/gate.stdout"
    gate_stderr_path = "build/logs/gate.stderr"
    wrapper_path = "tcb/sandbox_probe_wrapper.py"

    host_observation_value = {
        "attestationScope": "local-observation-only",
        "eligibleForHermetic": False,
        "hostProfileId": "darwin-arm64-25E253-xcode17C529-development",
        "platform": {
            "arch": "arm64",
            "authenticatedRoot": "enabled",
            "buildVersion": "25E253",
            "kernelRelease": "25.4.0",
            "procTranslated": False,
            "productVersion": "26.4.1",
            "sip": "enabled",
            "systemVolumeSeal": "broken",
        },
        "remoteAttestation": False,
        "xcode": {
            "buildVersion": "17C529",
            "cdHash": "97d0bbc90eb11b42b3d2ae659800fb4dde9668e2",
            "identifier": "com.apple.dt.Xcode",
            "mutableByCurrentUser": True,
            "version": "26.3",
        },
    }
    host_observation = canonical(host_observation_value) + b"\n"

    candidate_policy = {
        "anchorSource": "derived-development",
        "archiveFormat": "git-tar",
        "dirty": False,
        "subtree": ".",
        "unchangedDuringRun": True,
    }
    host_policy = {
        "eligibleForHermetic": False,
        "observationInput": {"path": observation_path, "role": "host-observation"},
        "profileId": "darwin-arm64-25E253-xcode17C529-development",
        "remoteAttestation": False,
        "scope": "local-point-in-time",
    }
    required_tools = [
        {
            "assetSha256": sha256(b"synthetic lean asset\n"),
            "closureOf": None,
            "closureSha256": lean_closure_sha256,
            "executableSha256": lean_executable_sha256,
            "id": "lean",
            "source": "content-addressed-cache",
            "usage": "invoked",
            "version": "4.31.0",
        },
        {
            "assetSha256": None,
            "closureOf": "lean",
            "closureSha256": lean_runtime_closure_sha256,
            "executableSha256": lean_runtime_executable_sha256,
            "id": "lean-runtime",
            "source": "content-addressed-cache",
            "usage": "closure-only",
            "version": "4.31.0",
        },
    ]

    def literal(value: object) -> dict[str, object]:
        return {"kind": "literal", "value": value}

    def binding(name: str) -> dict[str, object]:
        return {"kind": "binding", "name": name}

    def binding_decimal(name: str) -> dict[str, object]:
        return {"kind": "binding-decimal", "name": name}

    def run_path(relative: str) -> dict[str, object]:
        return {"kind": "run-path", "relative": relative}

    core_probe = {
        "command": {
            "argv": [literal("/opt/proof-forge/lean"), literal("--version")],
            "environment": [
                {"name": "HOME", "value": run_path("home")},
            ],
            "executable": {"id": "lean", "kind": "tool"},
        },
        "denial": None,
        "id": "core-success",
        "invocation": "core-success",
        "invocationContextInput": {
            "path": core_context_path,
            "role": "sandbox-invocation-context",
        },
        "outcome": "success",
        "receiptInput": {
            "path": core_receipt_path,
            "role": "sandbox-invocation-receipt",
        },
        "stage": "core",
        "stderrLog": core_stderr_path,
        "stdoutLog": core_stdout_path,
    }
    denial_probe = {
        "command": {
            "argv": [
                run_path(wrapper_path),
                literal("file-read"),
                run_path("forbidden/secret"),
            ],
            "environment": [],
            "executable": {
                "kind": "input",
                "path": wrapper_path,
                "role": "sandbox-probe-wrapper",
            },
        },
        "denial": {
            "allowedErrnos": ["EACCES", "EPERM"],
            "operation": "file-read",
        },
        "id": "file-read-denied",
        "invocation": "file-read-denied",
        "invocationContextInput": {
            "path": denial_context_path,
            "role": "sandbox-invocation-context",
        },
        "outcome": "permission-denied",
        "receiptInput": {
            "path": denial_receipt_path,
            "role": "sandbox-invocation-receipt",
        },
        "stage": "core",
        "stderrLog": denial_stderr_path,
        "stdoutLog": denial_stdout_path,
    }
    runtime_probe = {
        "command": {
            "argv": [
                run_path(artifact_path),
                literal("--port"),
                binding_decimal("runtime-port"),
            ],
            "environment": [
                {"name": "CHAIN_ID", "value": binding_decimal("chain-id")},
                {"name": "PORT", "value": binding_decimal("runtime-port")},
            ],
            "executable": {
                "kind": "artifact",
                "path": artifact_path,
                "role": "bytecode",
                "target": "evm",
            },
        },
        "denial": None,
        "id": "runtime-success",
        "invocation": "runtime-success",
        "invocationContextInput": {
            "path": runtime_context_path,
            "role": "sandbox-invocation-context",
        },
        "outcome": "success",
        "receiptInput": {
            "path": runtime_receipt_path,
            "role": "sandbox-invocation-receipt",
        },
        "stage": "evm-runtime",
        "stderrLog": runtime_stderr_path,
        "stdoutLog": runtime_stdout_path,
    }
    catalog = {
        "gates": [
            {
                "candidatePolicy": candidate_policy,
                "commandPolicy": {
                    "argv": [
                        run_path("scripts/verify_isolation.sh"),
                        literal("--development"),
                    ],
                    "attempts": 1,
                    "cwdRelative": ".",
                    "environmentSha256": binding("environment-sha256"),
                    "result": "passed",
                },
                "hostPolicy": host_policy,
                "id": "v2-clean-room-alpha",
                "policies": [
                    {
                        "defaultAction": "deny",
                        "engine": "sandbox-exec",
                        "engineSha256": engine_sha256,
                        "id": "core-no-network",
                        "network": "deny-all",
                        "networkPort": None,
                        "probes": [core_probe, denial_probe],
                        "renderedPolicyInput": {
                            "path": core_policy_path,
                            "role": "sandbox-rendered-policy",
                        },
                        "templateSha256": core_template_sha256,
                    },
                    {
                        "defaultAction": "deny",
                        "engine": "sandbox-exec",
                        "engineSha256": engine_sha256,
                        "id": "evm-runtime-exact-port",
                        "network": "exact-local-port",
                        "networkPort": binding("runtime-port"),
                        "probes": [runtime_probe],
                        "renderedPolicyInput": {
                            "path": runtime_policy_path,
                            "role": "sandbox-rendered-policy",
                        },
                        "templateSha256": runtime_template_sha256,
                    },
                ],
                "requiredArtifacts": [
                    {
                        "mediaType": "application/octet-stream",
                        "path": artifact_path,
                        "retained": True,
                        "role": "bytecode",
                        "target": "evm",
                    }
                ],
                "requiredInputs": [
                    {"path": "candidate.tar", "role": "candidate-archive"},
                    {
                        "path": "scripts/verify_isolation.sh",
                        "role": "gate-launcher",
                    },
                ],
                "requiredLogs": [
                    {
                        "path": gate_stderr_path,
                        "privateDataScan": "not-run",
                        "truncated": False,
                    },
                    {
                        "path": gate_stdout_path,
                        "privateDataScan": "not-run",
                        "truncated": False,
                    },
                ],
                "requiredObservations": [
                    {
                        "effects": [],
                        "errorClass": None,
                        "logicalState": {"count": 3},
                        "return": 3,
                        "status": "passed",
                        "step": "runtime-success",
                    }
                ],
                "requiredTools": required_tools,
                "taskId": "TASK-D0-03",
                "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
            }
        ],
        "id": "development-alpha",
        "locks": {
            "evidenceSchemaCoreSha256": sha256(evidence_core),
            "evidenceValidatorSha256": sha256(evidence_validator),
            "finalizerSha256": sha256(evidence_validator),
            "hostBootstrapSha256": sha256(host_bootstrap),
            "hostProfileLockSha256": sha256(host_profile),
            "sandboxEngineSha256": engine_sha256,
            "sandboxLauncherSha256": sha256(sandbox_launcher),
            "sandboxProbeWrapperSha256": sha256(probe_wrapper),
            "sandboxRendererSha256": sha256(sandbox_renderer),
            "stage0LauncherSha256": sha256(stage0_launcher),
            "stage0VerifierSha256": sha256(stage0_verifier),
            "toolchainLockSha256": sha256(toolchain_lock),
        },
        "qualification": "development",
        "requiredTestSet": None,
        "schema": "proof-forge.gate-catalog.v1",
        "version": "1.0.0",
    }
    catalog_bytes = canonical(catalog)
    catalog_sha256 = sha256(catalog_bytes)
    catalog_digest = domain_sha256(b"pf.gate-catalog.v1", catalog_bytes)
    catalog_ref = {
        "catalogDigest": catalog_digest,
        "contentSha256": catalog_sha256,
        "id": catalog["id"],
        "schema": catalog["schema"],
        "version": catalog["version"],
    }
    run_context = {
        "bindings": [
            {
                "name": "environment-sha256",
                "type": "sha256",
                "value": environment_sha256,
            }
        ],
        "candidate": {
            "archiveSha256": sha256(candidate),
            "commit": "a" * 40,
            "treeObjectId": "b" * 40,
        },
        "catalog": catalog_ref,
        "gate": {
            "id": "v2-clean-room-alpha",
            "taskId": "TASK-D0-03",
            "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
        },
        "host": {
            "observationSha256": sha256(host_observation),
            "profileId": "darwin-arm64-25E253-xcode17C529-development",
        },
        "runId": "RUN-0123456789abcdef0123456789abcdef",
        "runRoot": os.fspath(root),
        "schema": "proof-forge.clean-room-run-context.v1",
    }
    run_context_bytes = canonical(run_context)
    run_binding_sha256 = domain_sha256(
        b"pf.clean-room-run-context.v1", run_context_bytes
    )

    def invocation_context(
        stage: str, invocation: str, bindings: list[dict[str, object]]
    ) -> bytes:
        return canonical(
            {
                "bindings": bindings,
                "invocation": invocation,
                "runBindingSha256": run_binding_sha256,
                "schema": "proof-forge.sandbox-invocation-context.v1",
                "stage": stage,
            }
        )

    core_context = invocation_context("core", "core-success", [])
    denial_context = invocation_context("core", "file-read-denied", [])
    runtime_context = invocation_context(
        "evm-runtime",
        "runtime-success",
        [
            {"name": "chain-id", "type": "integer", "value": 31337},
            {"name": "runtime-port", "type": "integer", "value": runtime_port},
        ],
    )

    def environment(entries: list[dict[str, str]]) -> dict[str, object]:
        return {
            "entries": entries,
            "sha256": domain_sha256(b"pf.sandbox.environment.v1", canonical(entries)),
        }

    def receipt(
        *,
        stage: str,
        invocation: str,
        context_bytes: bytes,
        policy_path: str,
        policy_bytes: bytes,
        port: int | None,
        argv: list[str],
        entries: list[dict[str, str]],
        executable_sha256: str,
        exit_code: int,
        stdout_path: str,
        stdout: bytes,
        stderr_path: str,
        stderr: bytes,
    ) -> bytes:
        return canonical(
            {
                "command": {
                    "argv": argv,
                    "argvSha256": domain_sha256(b"pf.sandbox.argv.v1", canonical(argv)),
                    "observedExecutablePath": argv[0],
                    "observedExecutableSha256": executable_sha256,
                },
                "durationMs": 7,
                "engine": {
                    "observedSha256": engine_sha256,
                    "path": "/usr/bin/sandbox-exec",
                },
                "environment": environment(entries),
                "invocation": invocation,
                "invocationBindingSha256": domain_sha256(
                    b"pf.sandbox.invocation-context.v1", context_bytes
                ),
                "observedLauncherSha256": sha256(sandbox_launcher),
                "policy": {
                    "path": policy_path,
                    "sha256": sha256(policy_bytes),
                    "size": len(policy_bytes),
                },
                "runBindingSha256": run_binding_sha256,
                "runtimePort": port,
                "schema": "proof-forge.sandbox-invocation.v1",
                "stage": stage,
                "stderr": {
                    "path": stderr_path,
                    "sha256": sha256(stderr),
                    "size": len(stderr),
                    "truncated": False,
                },
                "stdout": {
                    "path": stdout_path,
                    "sha256": sha256(stdout),
                    "size": len(stdout),
                    "truncated": False,
                },
                "terminal": {"exitCode": exit_code, "signal": None, "timedOut": False},
            }
        )

    core_argv = ["/opt/proof-forge/lean", "--version"]
    core_entries = [{"name": "HOME", "value": os.fspath(root / "home")}]
    core_receipt = receipt(
        stage="core",
        invocation="core-success",
        context_bytes=core_context,
        policy_path=core_policy_path,
        policy_bytes=core_policy,
        port=None,
        argv=core_argv,
        entries=core_entries,
        executable_sha256=lean_executable_sha256,
        exit_code=0,
        stdout_path=core_stdout_path,
        stdout=core_stdout,
        stderr_path=core_stderr_path,
        stderr=core_stderr,
    )
    denial_argv = [
        os.fspath(root / wrapper_path),
        "file-read",
        os.fspath(root / "forbidden" / "secret"),
    ]
    denial_receipt = receipt(
        stage="core",
        invocation="file-read-denied",
        context_bytes=denial_context,
        policy_path=core_policy_path,
        policy_bytes=core_policy,
        port=None,
        argv=denial_argv,
        entries=[],
        executable_sha256=sha256(probe_wrapper),
        exit_code=77,
        stdout_path=denial_stdout_path,
        stdout=denial_stdout,
        stderr_path=denial_stderr_path,
        stderr=denial_stderr,
    )
    runtime_argv = [
        os.fspath(root / artifact_path),
        "--port",
        str(runtime_port),
    ]
    runtime_entries = [
        {"name": "CHAIN_ID", "value": "31337"},
        {"name": "PORT", "value": str(runtime_port)},
    ]
    runtime_receipt = receipt(
        stage="evm-runtime",
        invocation="runtime-success",
        context_bytes=runtime_context,
        policy_path=runtime_policy_path,
        policy_bytes=runtime_policy,
        port=runtime_port,
        argv=runtime_argv,
        entries=runtime_entries,
        executable_sha256=sha256(artifact),
        exit_code=0,
        stdout_path=runtime_stdout_path,
        stdout=runtime_stdout,
        stderr_path=runtime_stderr_path,
        stderr=runtime_stderr,
    )

    files = {
        artifact_path: artifact,
        "candidate.tar": candidate,
        catalog_path: catalog_bytes,
        core_context_path: core_context,
        denial_context_path: denial_context,
        runtime_context_path: runtime_context,
        "host/host-bootstrap.lock": host_bootstrap,
        "host/host-profiles.lock.json": host_profile,
        observation_path: host_observation,
        "host/toolchains.lock.json": toolchain_lock,
        core_policy_path: core_policy,
        core_receipt_path: core_receipt,
        core_stderr_path: core_stderr,
        core_stdout_path: core_stdout,
        runtime_policy_path: runtime_policy,
        denial_receipt_path: denial_receipt,
        denial_stderr_path: denial_stderr,
        denial_stdout_path: denial_stdout,
        runtime_receipt_path: runtime_receipt,
        runtime_stderr_path: runtime_stderr,
        runtime_stdout_path: runtime_stdout,
        run_context_path: run_context_bytes,
        "scripts/verify_isolation.sh": gate_launcher,
        "tcb/evidence_v1_core.py": evidence_core,
        "tcb/sandbox_exec.py": sandbox_launcher,
        "tcb/sandbox_policy.py": sandbox_renderer,
        wrapper_path: probe_wrapper,
        "tcb/toolchain_assets.py": stage0_verifier,
        "tcb/verify_host_stage0.sh": stage0_launcher,
        gate_stderr_path: gate_stderr,
        gate_stdout_path: gate_stdout,
    }
    input_roles = {
        "candidate.tar": "candidate-archive",
        catalog_path: "gate-catalog",
        core_context_path: "sandbox-invocation-context",
        denial_context_path: "sandbox-invocation-context",
        runtime_context_path: "sandbox-invocation-context",
        "host/host-bootstrap.lock": "host-bootstrap-lock",
        "host/host-profiles.lock.json": "host-profile-lock",
        observation_path: "host-observation",
        "host/toolchains.lock.json": "toolchain-lock",
        core_policy_path: "sandbox-rendered-policy",
        core_receipt_path: "sandbox-invocation-receipt",
        runtime_policy_path: "sandbox-rendered-policy",
        denial_receipt_path: "sandbox-invocation-receipt",
        runtime_receipt_path: "sandbox-invocation-receipt",
        run_context_path: "clean-room-run-context",
        "scripts/verify_isolation.sh": "gate-launcher",
        "tcb/evidence_v1_core.py": "evidence-schema-core",
        "tcb/sandbox_exec.py": "sandbox-launcher",
        "tcb/sandbox_policy.py": "sandbox-policy-renderer",
        wrapper_path: "sandbox-probe-wrapper",
        "tcb/toolchain_assets.py": "host-stage0-verifier",
        "tcb/verify_host_stage0.sh": "host-stage0-launcher",
    }
    inputs = sorted(
        (
            {
                "path": path,
                "role": role,
                "sha256": sha256(files[path]),
                "size": len(files[path]),
            }
            for path, role in input_roles.items()
        ),
        key=lambda item: (item["role"], item["path"]),
    )
    logs = sorted(
        (
            {
                "path": path,
                "privateDataScan": "not-run",
                "sha256": sha256(files[path]),
                "size": len(files[path]),
                "truncated": False,
            }
            for path in (
                gate_stderr_path,
                gate_stdout_path,
                core_stderr_path,
                core_stdout_path,
                denial_stderr_path,
                denial_stdout_path,
                runtime_stderr_path,
                runtime_stdout_path,
            )
        ),
        key=lambda item: item["path"],
    )
    artifacts = [
        {
            "mediaType": "application/octet-stream",
            "path": artifact_path,
            "retained": True,
            "role": "bytecode",
            "sha256": sha256(artifact),
            "size": len(artifact),
            "target": "evm",
        }
    ]
    document = {
        "artifactSetSha256": module.artifact_set_sha256(artifacts),
        "artifacts": artifacts,
        "command": {
            "argv": [
                os.fspath(root / "scripts" / "verify_isolation.sh"),
                "--development",
            ],
            "attempts": [
                {
                    "exitCode": 0,
                    "number": 1,
                    "signal": None,
                    "stderrLog": gate_stderr_path,
                    "stdoutLog": gate_stdout_path,
                    "timedOut": False,
                }
            ],
            "cwdRelative": ".",
            "durationMs": 21,
            "endedUtc": "2026-07-15T00:00:00Z",
            "startedUtc": "2026-07-15T00:00:00Z",
        },
        "environment": {
            "arch": "arm64",
            "assetCache": "locked-read-only",
            "buildCache": "empty",
            "cleanRoom": True,
            "environmentSha256": environment_sha256,
            "os": "macOS 26.4.1",
            "sourceDateEpoch": 0,
        },
        "gate": {
            "id": "v2-clean-room-alpha",
            "qualification": "development",
            "taskId": "TASK-D0-03",
            "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
        },
        "gateCatalog": catalog_ref,
        "hostAttestation": {
            "bootstrapLockSha256": sha256(host_bootstrap),
            "eligibleForHermetic": False,
            "hostProfileLockSha256": sha256(host_profile),
            "launcherSha256": sha256(stage0_launcher),
            "observationInput": {"path": observation_path, "role": "host-observation"},
            "observationSha256": sha256(host_observation),
            "profileId": "darwin-arm64-25E253-xcode17C529-development",
            "remoteAttestation": False,
            "scope": "local-point-in-time",
            "toolchainLockSha256": sha256(toolchain_lock),
            "verifierSha256": sha256(stage0_verifier),
        },
        "id": "EV-20260715-0001",
        "inputs": inputs,
        "logs": logs,
        "observations": [
            {
                "effects": [],
                "errorClass": None,
                "logicalState": {"count": 3},
                "return": 3,
                "status": "passed",
                "step": "runtime-success",
            }
        ],
        "repository": {
            "anchorSource": "derived-development",
            "archive": {
                "format": "git-tar",
                "sha256": sha256(candidate),
                "size": len(candidate),
            },
            "commit": "a" * 40,
            "dirty": False,
            "dirtyDigest": None,
            "subtree": ".",
            "treeObjectId": "b" * 40,
            "unchangedDuringRun": True,
        },
        "result": "passed",
        "runContextInput": {"path": run_context_path, "role": "clean-room-run-context"},
        "sandboxPolicies": [
            {
                "defaultAction": "deny",
                "engine": "sandbox-exec",
                "engineSha256": engine_sha256,
                "id": "core-no-network",
                "network": "deny-all",
                "probes": [
                    {
                        "id": "core-success",
                        "receipt": {
                            "invocationContextInput": {
                                "path": core_context_path,
                                "role": "sandbox-invocation-context",
                            },
                            "path": core_receipt_path,
                            "role": "sandbox-invocation-receipt",
                            "stderrLog": core_stderr_path,
                            "stdoutLog": core_stdout_path,
                        },
                        "status": "passed",
                    },
                    {
                        "id": "file-read-denied",
                        "receipt": {
                            "invocationContextInput": {
                                "path": denial_context_path,
                                "role": "sandbox-invocation-context",
                            },
                            "path": denial_receipt_path,
                            "role": "sandbox-invocation-receipt",
                            "stderrLog": denial_stderr_path,
                            "stdoutLog": denial_stdout_path,
                        },
                        "status": "passed",
                    },
                ],
                "renderedPolicyInput": {
                    "path": core_policy_path,
                    "role": "sandbox-rendered-policy",
                },
                "renderedSha256": sha256(core_policy),
                "templateSha256": core_template_sha256,
            },
            {
                "defaultAction": "deny",
                "engine": "sandbox-exec",
                "engineSha256": engine_sha256,
                "id": "evm-runtime-exact-port",
                "network": "exact-local-port",
                "networkPort": runtime_port,
                "probes": [
                    {
                        "id": "runtime-success",
                        "receipt": {
                            "invocationContextInput": {
                                "path": runtime_context_path,
                                "role": "sandbox-invocation-context",
                            },
                            "path": runtime_receipt_path,
                            "role": "sandbox-invocation-receipt",
                            "stderrLog": runtime_stderr_path,
                            "stdoutLog": runtime_stdout_path,
                        },
                        "status": "passed",
                    }
                ],
                "renderedPolicyInput": {
                    "path": runtime_policy_path,
                    "role": "sandbox-rendered-policy",
                },
                "renderedSha256": sha256(runtime_policy),
                "templateSha256": runtime_template_sha256,
            },
        ],
        "schema": "proof-forge.evidence.v1",
        "skipAuthorization": None,
        "tools": [
            {
                key: tool[key]
                for key in (
                    "assetSha256",
                    "closureSha256",
                    "executableSha256",
                    "id",
                    "source",
                    "version",
                )
            }
            for tool in required_tools
        ],
    }
    module.validate_evidence(document)
    evidence_path = "development-evidence.json"
    evidence_bytes = canonical(document)
    for relative, body in files.items():
        write_secure(root / relative, body)
    write_secure(root / evidence_path, evidence_bytes)
    for directory in sorted((path for path in root.rglob("*") if path.is_dir())):
        directory.chmod(0o700)
    module.verify_bundle(document, root)
    return document, catalog_path, catalog_sha256, catalog_digest, run_binding_sha256


def invoke(
    arguments: list[str],
    *,
    descriptor_source: Path = GATE_EVIDENCE,
    executing_source: Path | str = GATE_EVIDENCE,
    source_flags: int = os.O_RDONLY,
) -> subprocess.CompletedProcess[bytes]:
    gate_descriptor = os.open(
        descriptor_source,
        source_flags | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0),
    )
    try:
        return subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                "-",
                arguments[0],
                "--executing-source",
                (
                    os.fspath(executing_source.resolve(strict=True))
                    if isinstance(executing_source, Path)
                    else executing_source
                ),
                *arguments[1:],
            ],
            cwd=ROOT,
            stdin=gate_descriptor,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(
            "finalizer blocked on catalog or claimed-member I/O before its policy decision"
        ) from error
    finally:
        os.close(gate_descriptor)


def invoke_prelude(
    arguments: list[str],
    *,
    fake_os_exit: bool = False,
    monkeypatch_getframe: bool = False,
) -> subprocess.CompletedProcess[bytes]:
    getframe_patch = """
class FakeFrame:
    pass
fake_frame = FakeFrame()
fake_frame.f_code = compile(source, "<stdin>", "exec", dont_inherit=True)
fake_frame.f_back = None
fake_frame.f_globals = {"__name__": "__main__"}
real_getframe = sys._getframe
sys._getframe = lambda depth=0: fake_frame if depth == 0 else real_getframe(depth)
""" if monkeypatch_getframe else ""
    os_patch = """
import builtins
real_import = builtins.__import__
real_os = os
class FakeOs:
    write = staticmethod(real_os.write)
    _exit = staticmethod(lambda code: None)
fake_os = FakeOs()
builtins.__import__ = lambda name, *args, **kwargs: (
    fake_os if name == "os" else real_import(name, *args, **kwargs)
)
""" if fake_os_exit else ""
    prelude = """import os, sys
sys.argv[0] = "-"
size = os.fstat(0).st_size
source = os.pread(0, size + 1, 0)
""" + getframe_patch + os_patch + """
namespace = {
    "__name__": "__main__",
    "__file__": "<stdin>",
    "__package__": None,
    "__cached__": None,
}
exec(compile(source, "<stdin>", "exec", dont_inherit=True), namespace, namespace)
"""
    gate_descriptor = os.open(
        GATE_EVIDENCE,
        os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0),
    )
    try:
        return subprocess.run(
            [sys.executable, "-I", "-S", "-c", prelude, *arguments],
            cwd=ROOT,
            stdin=gate_descriptor,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError("prelude finalizer invocation blocked") from error
    finally:
        os.close(gate_descriptor)


def invoke_pipe(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                "-",
                arguments[0],
                "--executing-source",
                os.fspath(GATE_EVIDENCE.resolve(strict=True)),
                *arguments[1:],
            ],
            cwd=ROOT,
            input=GATE_EVIDENCE.read_bytes(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError("pipe finalizer invocation blocked") from error


def invoke_path(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            [sys.executable, "-I", "-S", os.fspath(GATE_EVIDENCE), *arguments],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError("pathname finalizer invocation blocked") from error


def rewrite_catalog_binding(
    module: object,
    bundle_root: Path,
    document: dict[str, object],
    catalog_path: str,
    mutator: object,
) -> tuple[dict[str, object], str, str]:
    rebound = copy.deepcopy(document)
    catalog_file = bundle_root / catalog_path
    catalog = module.decode_json(catalog_file.read_bytes())
    if not callable(mutator):
        raise AssertionError("catalog mutator is not callable")
    mutator(catalog)
    catalog_bytes = module.canonical_bytes(catalog)
    content_sha256 = sha256(catalog_bytes)
    catalog_digest = domain_sha256(b"pf.gate-catalog.v1", catalog_bytes)
    replace_secure(catalog_file, catalog_bytes)
    rebound["gateCatalog"] = {
        "schema": catalog["schema"],
        "id": catalog["id"],
        "version": catalog["version"],
        "contentSha256": content_sha256,
        "catalogDigest": catalog_digest,
    }
    catalog_claim = next(
        entry for entry in rebound["inputs"] if entry["role"] == "gate-catalog"
    )
    catalog_claim["sha256"] = content_sha256
    catalog_claim["size"] = len(catalog_bytes)
    module.validate_evidence(rebound)
    replace_secure(
        bundle_root / "development-evidence.json",
        module.canonical_bytes(rebound),
    )
    return rebound, content_sha256, catalog_digest


def assert_catalog_rejection(
    module: object,
    temporary_root: Path,
    source_root: Path,
    document: dict[str, object],
    catalog_path: str,
    run_binding_sha256: str,
    *,
    label: str,
    expected_code: str,
    mutator: object | None = None,
    catalog_argument: str | None = None,
    content_override: str | None = None,
) -> None:
    case_root = temporary_root / f"catalog-negative-{label}"
    shutil.copytree(source_root, case_root, copy_function=shutil.copy2)
    case_document = copy.deepcopy(document)
    content_sha256 = case_document["gateCatalog"]["contentSha256"]
    catalog_digest = case_document["gateCatalog"]["catalogDigest"]
    if mutator is not None:
        case_document, content_sha256, catalog_digest = rewrite_catalog_binding(
            module,
            case_root,
            case_document,
            catalog_path,
            mutator,
        )
    if content_override is not None:
        content_sha256 = content_override
    output_root = temporary_root / f"catalog-negative-output-{label}"
    output = (
        output_root
        / "finalized-development"
        / case_document["gateCatalog"]["id"]
        / case_document["gate"]["id"]
        / "EVF-20260715-9001.json"
    )
    result = invoke(
        [
            "finalize-development",
            "--catalog",
            catalog_argument if catalog_argument is not None else catalog_path,
            "--catalog-sha256",
            content_sha256,
            "--catalog-digest",
            catalog_digest,
            "--run-binding-sha256",
            run_binding_sha256,
            "--evidence",
            "development-evidence.json",
            "--bundle-root",
            os.fspath(case_root),
            "--output",
            os.fspath(output),
        ]
    )
    stderr_lines = result.stderr.splitlines()
    if (
        result.returncode != 2
        or result.stdout
        or len(stderr_lines) != 1
        or not stderr_lines[0].startswith(expected_code.encode("ascii") + b": ")
    ):
        raise AssertionError(
            f"catalog negative {label} did not fail at {expected_code}:\n"
            + result.stderr.decode("utf-8", errors="replace")
        )
    if output_root.exists():
        raise AssertionError(f"catalog negative {label} touched its output namespace")


def assert_identity_rejection(
    result: subprocess.CompletedProcess[bytes],
    *,
    label: str,
    output_root: Path,
) -> None:
    stderr_lines = result.stderr.splitlines()
    if (
        result.returncode != 2
        or result.stdout
        or len(stderr_lines) != 1
        or not stderr_lines[0].startswith(b"PF-EVIDENCE-FINALIZER-IDENTITY: ")
    ):
        raise AssertionError(
            f"{label} did not fail with one stable finalizer-identity diagnostic:\n"
            + result.stderr.decode("utf-8", errors="replace")
        )
    if output_root.exists():
        raise AssertionError(f"{label} touched its output namespace")


def main() -> int:
    if not sys.flags.isolated or not sys.flags.no_site:
        raise AssertionError("invoke this test with isolated Python using -I -S")
    module = load_gate_evidence()
    with tempfile.TemporaryDirectory(prefix="proof-forge-evfinal-") as temporary:
        temporary_root = Path(temporary).resolve(strict=True)
        bundle_root = temporary_root / "formal-bundle"
        bundle_root.mkdir(mode=0o700)
        write_formal_bundle(module, bundle_root)

        candidate_trap = bundle_root / "candidate.tar"
        candidate_trap.unlink()
        os.mkfifo(candidate_trap, mode=0o400)
        candidate_trap_before = os.lstat(candidate_trap)

        catalog_must_not_be_read = temporary_root / "catalog-must-not-be-read.json"
        os.mkfifo(catalog_must_not_be_read, mode=0o400)
        catalog_trap_before = os.lstat(catalog_must_not_be_read)
        output_root_must_not_be_touched = temporary_root / "output-must-not-be-touched"
        output = (
            output_root_must_not_be_touched
            / "finalized-development"
            / "development-alpha"
            / "v2-clean-room-alpha"
            / "EVF-20260715-0001.json"
        )
        result = invoke_path(
            [
                "finalize-development",
                "--catalog",
                os.fspath(catalog_must_not_be_read),
                "--catalog-sha256",
                "0" * 64,
                "--catalog-digest",
                "0" * 64,
                "--run-binding-sha256",
                "0" * 64,
                "--evidence",
                "formal-evidence.json",
                "--bundle-root",
                os.fspath(bundle_root),
                "--output",
                os.fspath(output),
            ]
        )
        if result.returncode != 2:
            raise AssertionError("formal input did not fail with the stable CLI status")
        if result.stdout:
            raise AssertionError("formal input produced stdout")
        if b"PF-EVIDENCE-FORMAL-UNVERIFIED" not in result.stderr:
            raise AssertionError(
                "formal input was not rejected before catalog/member/output I/O:\n"
                + result.stderr.decode("utf-8", errors="replace")
            )
        catalog_trap_after = os.lstat(catalog_must_not_be_read)
        candidate_trap_after = os.lstat(candidate_trap)
        if (
            not stat.S_ISFIFO(catalog_trap_after.st_mode)
            or (catalog_trap_after.st_dev, catalog_trap_after.st_ino)
            != (catalog_trap_before.st_dev, catalog_trap_before.st_ino)
        ):
            raise AssertionError("formal rejection replaced the unread catalog trap")
        if (
            not stat.S_ISFIFO(candidate_trap_after.st_mode)
            or (candidate_trap_after.st_dev, candidate_trap_after.st_ino)
            != (candidate_trap_before.st_dev, candidate_trap_before.st_ino)
        ):
            raise AssertionError("formal rejection replaced the unread claimed-member trap")
        if output_root_must_not_be_touched.exists():
            raise AssertionError("formal rejection touched its output namespace")

        development_root = temporary_root / "development-bundle"
        development_root.mkdir(mode=0o700)
        (
            document,
            catalog_path,
            catalog_sha256,
            catalog_digest,
            run_binding_sha256,
        ) = write_realistic_development_bundle(module, development_root)

        def development_arguments(
            output_path: Path,
            selected_catalog: str,
            *,
            selected_evidence: str = "development-evidence.json",
        ) -> list[str]:
            return [
                "finalize-development",
                "--catalog",
                selected_catalog,
                "--catalog-sha256",
                catalog_sha256,
                "--catalog-digest",
                catalog_digest,
                "--run-binding-sha256",
                run_binding_sha256,
                "--evidence",
                selected_evidence,
                "--bundle-root",
                os.fspath(development_root),
                "--output",
                os.fspath(output_path),
            ]

        pathname_catalog_relative = "catalog/pathname-must-not-be-read.json"
        pathname_catalog_trap = development_root / pathname_catalog_relative
        os.mkfifo(pathname_catalog_trap, mode=0o400)
        pathname_catalog_before = os.lstat(pathname_catalog_trap)
        pathname_output_root = temporary_root / "pathname-output-must-not-be-touched"
        pathname_output = (
            pathname_output_root
            / "finalized-development"
            / document["gateCatalog"]["id"]
            / document["gate"]["id"]
            / "EVF-20260715-9000.json"
        )
        pathname_result = invoke_path(
            development_arguments(pathname_output, pathname_catalog_relative)
        )
        assert_identity_rejection(
            pathname_result,
            label="pathname finalizer invocation",
            output_root=pathname_output_root,
        )
        pathname_catalog_after = os.lstat(pathname_catalog_trap)
        if (
            not stat.S_ISFIFO(pathname_catalog_after.st_mode)
            or (pathname_catalog_after.st_dev, pathname_catalog_after.st_ino)
            != (pathname_catalog_before.st_dev, pathname_catalog_before.st_ino)
        ):
            raise AssertionError("pathname finalizer rejection replaced the unread catalog trap")

        pathname_evidence_relative = "pathname-preliminary-evidence.json"
        write_secure(development_root / pathname_evidence_relative, b"{")
        pathname_preliminary_result = invoke_path(
            development_arguments(
                temporary_root
                / "pathname-preliminary-output-must-not-be-touched"
                / "EVF-20260715-9000.json",
                pathname_catalog_relative,
                selected_evidence=pathname_evidence_relative,
            )
        )
        pathname_preliminary_stderr = pathname_preliminary_result.stderr.splitlines()
        if (
            pathname_preliminary_result.returncode != 2
            or pathname_preliminary_result.stdout
            or len(pathname_preliminary_stderr) != 1
            or not pathname_preliminary_stderr[0].startswith(b"PF-EVIDENCE-JSON: ")
        ):
            raise AssertionError(
                "pathname finalizer did not validate preliminary evidence before "
                "development source identity:\n"
                + pathname_preliminary_result.stderr.decode("utf-8", errors="replace")
            )
        pathname_catalog_after = os.lstat(pathname_catalog_trap)
        if (
            not stat.S_ISFIFO(pathname_catalog_after.st_mode)
            or (pathname_catalog_after.st_dev, pathname_catalog_after.st_ino)
            != (pathname_catalog_before.st_dev, pathname_catalog_before.st_ino)
        ):
            raise AssertionError(
                "preliminary evidence rejection replaced the unread catalog trap"
            )
        if (temporary_root / "pathname-preliminary-output-must-not-be-touched").exists():
            raise AssertionError("preliminary evidence rejection touched its output namespace")

        for label, result in (
            (
                "writable stdin finalizer invocation",
                invoke(
                    development_arguments(
                        temporary_root / "writable-stdin-output" / "EVF-20260715-9000.json",
                        pathname_catalog_relative,
                    ),
                    source_flags=os.O_RDWR,
                ),
            ),
            (
                "pipe stdin finalizer invocation",
                invoke_pipe(
                    development_arguments(
                        temporary_root / "pipe-stdin-output" / "EVF-20260715-9000.json",
                        pathname_catalog_relative,
                    )
                ),
            ),
        ):
            assert_identity_rejection(
                result,
                label=label,
                output_root=temporary_root
                / ("writable-stdin-output" if label.startswith("writable") else "pipe-stdin-output"),
            )

        substituted_source = temporary_root / "substituted-source" / "gate_evidence.py"
        write_secure(substituted_source, GATE_EVIDENCE.read_bytes() + b"# substituted\n")
        substituted_output_root = temporary_root / "substituted-source-output"
        substituted_result = invoke(
            development_arguments(
                substituted_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            executing_source=substituted_source,
        )
        assert_identity_rejection(
            substituted_result,
            label="substituted executing-source invocation",
            output_root=substituted_output_root,
        )

        same_bytes_root = temporary_root / "same-bytes-source"
        same_bytes_root.mkdir(mode=0o700)
        same_bytes_gate = same_bytes_root / "gate_evidence.py"
        write_secure(same_bytes_gate, GATE_EVIDENCE.read_bytes())
        write_secure(
            same_bytes_root / "evidence_v1_core.py",
            EVIDENCE_CORE.read_bytes(),
        )
        same_bytes_output_root = temporary_root / "same-bytes-source-output"
        same_bytes_result = invoke(
            development_arguments(
                same_bytes_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            executing_source=same_bytes_gate,
        )
        assert_identity_rejection(
            same_bytes_result,
            label="same-bytes different-inode executing-source invocation",
            output_root=same_bytes_output_root,
        )

        source_fifo_root = temporary_root / "source-fifo"
        source_fifo_root.mkdir(mode=0o700)
        source_fifo = source_fifo_root / "gate_evidence.py"
        os.mkfifo(source_fifo, mode=0o400)
        source_fifo_output_root = temporary_root / "source-fifo-output"
        source_fifo_result = invoke(
            development_arguments(
                source_fifo_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            executing_source=source_fifo,
        )
        assert_identity_rejection(
            source_fifo_result,
            label="FIFO executing-source invocation",
            output_root=source_fifo_output_root,
        )

        surrogate_output_root = temporary_root / "surrogate-source-output"
        surrogate_result = invoke(
            development_arguments(
                surrogate_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            executing_source="/tmp/\udcff/gate_evidence.py",
        )
        assert_identity_rejection(
            surrogate_result,
            label="surrogate executing-source invocation",
            output_root=surrogate_output_root,
        )

        prelude_output_root = temporary_root / "prelude-output"
        prelude_arguments = development_arguments(
            prelude_output_root / "EVF-20260715-9000.json",
            pathname_catalog_relative,
        )
        prelude_arguments[1:1] = [
            "--executing-source",
            os.fspath(GATE_EVIDENCE.resolve(strict=True)),
        ]
        prelude_result = invoke_prelude(prelude_arguments)
        assert_identity_rejection(
            prelude_result,
            label="unlocked -c prelude invocation",
            output_root=prelude_output_root,
        )
        monkeypatched_prelude_output_root = temporary_root / "monkeypatched-prelude-output"
        monkeypatched_prelude_arguments = development_arguments(
            monkeypatched_prelude_output_root / "EVF-20260715-9000.json",
            pathname_catalog_relative,
        )
        monkeypatched_prelude_arguments[1:1] = [
            "--executing-source",
            os.fspath(GATE_EVIDENCE.resolve(strict=True)),
        ]
        monkeypatched_prelude_result = invoke_prelude(
            monkeypatched_prelude_arguments,
            monkeypatch_getframe=True,
        )
        assert_identity_rejection(
            monkeypatched_prelude_result,
            label="monkeypatched getframe prelude invocation",
            output_root=monkeypatched_prelude_output_root,
        )
        returning_exit_output_root = temporary_root / "returning-exit-prelude-output"
        returning_exit_arguments = development_arguments(
            returning_exit_output_root / "EVF-20260715-9000.json",
            pathname_catalog_relative,
        )
        returning_exit_arguments[1:1] = [
            "--executing-source",
            os.fspath(GATE_EVIDENCE.resolve(strict=True)),
        ]
        returning_exit_result = invoke_prelude(
            returning_exit_arguments,
            fake_os_exit=True,
        )
        assert_identity_rejection(
            returning_exit_result,
            label="returning fake os exit prelude invocation",
            output_root=returning_exit_output_root,
        )

        substituted_core_root = temporary_root / "substituted-core-source"
        substituted_core_root.mkdir(mode=0o700)
        substituted_gate = substituted_core_root / "gate_evidence.py"
        substituted_core = substituted_core_root / "evidence_v1_core.py"
        substituted_core_sentinel = temporary_root / "substituted-core-executed"
        write_secure(substituted_gate, GATE_EVIDENCE.read_bytes())
        write_secure(
            substituted_core,
            EVIDENCE_CORE.read_bytes()
            + (
                "\n__import__('pathlib').Path("
                + repr(os.fspath(substituted_core_sentinel))
                + ").write_bytes(b'executed')\n"
            ).encode("utf-8"),
        )
        substituted_core_output_root = temporary_root / "substituted-core-output"
        substituted_core_result = invoke(
            development_arguments(
                substituted_core_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            descriptor_source=substituted_gate,
            executing_source=substituted_gate,
        )
        substituted_core_stderr = substituted_core_result.stderr.splitlines()
        if (
            substituted_core_result.returncode != 2
            or substituted_core_result.stdout
            or len(substituted_core_stderr) != 1
            or not substituted_core_stderr[0].startswith(
                b"PF-EVIDENCE-CATALOG-DIGEST: "
            )
        ):
            raise AssertionError(
                "substituted exact sibling core did not fail before execution:\n"
                + substituted_core_result.stderr.decode("utf-8", errors="replace")
            )
        if substituted_core_output_root.exists():
            raise AssertionError("substituted exact sibling core touched output")
        if substituted_core_sentinel.exists():
            raise AssertionError("substituted exact sibling core executed before its pin check")

        fifo_core_root = temporary_root / "fifo-core-source"
        fifo_core_root.mkdir(mode=0o700)
        fifo_core_gate = fifo_core_root / "gate_evidence.py"
        fifo_core = fifo_core_root / "evidence_v1_core.py"
        write_secure(fifo_core_gate, GATE_EVIDENCE.read_bytes())
        os.mkfifo(fifo_core, mode=0o400)
        fifo_core_output_root = temporary_root / "fifo-core-output"
        fifo_core_result = invoke(
            development_arguments(
                fifo_core_output_root / "EVF-20260715-9000.json",
                pathname_catalog_relative,
            ),
            descriptor_source=fifo_core_gate,
            executing_source=fifo_core_gate,
        )
        assert_identity_rejection(
            fifo_core_result,
            label="FIFO exact sibling core invocation",
            output_root=fifo_core_output_root,
        )

        duplicate_output_root = temporary_root / "duplicate-source-output"
        duplicate_arguments = development_arguments(
            duplicate_output_root / "EVF-20260715-9000.json",
            pathname_catalog_relative,
        )
        duplicate_arguments.extend(
            ["--executing-source", os.fspath(GATE_EVIDENCE.resolve(strict=True))]
        )
        duplicate_result = invoke(duplicate_arguments)
        assert_identity_rejection(
            duplicate_result,
            label="duplicate executing-source invocation",
            output_root=duplicate_output_root,
        )
        pathname_catalog_trap.unlink()
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="caller-content-digest",
            expected_code="PF-EVIDENCE-CATALOG-DIGEST",
            content_override="0" * 64,
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="absolute-catalog-path",
            expected_code="PF-EVIDENCE-PATH",
            catalog_argument=os.fspath((development_root / catalog_path).resolve(strict=True)),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="parent-catalog-path",
            expected_code="PF-EVIDENCE-PATH",
            catalog_argument="catalog/../catalog/development-alpha.json",
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="catalog-path-claim-split",
            expected_code="PF-EVIDENCE-CATALOG-DIGEST",
            catalog_argument="catalog/alternate-development-alpha.json",
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="hidden-malformed-gate",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"].append(
                {
                    **copy.deepcopy(catalog["gates"][0]),
                    "id": "zz-hidden-malformed",
                    "requiredTools": [],
                }
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="selected-task",
            expected_code="PF-EVIDENCE-CATALOG-GATE",
            mutator=lambda catalog: catalog["gates"][0].update(
                {"taskId": "TASK-D0-99"}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="implementation-core-lock",
            expected_code="PF-EVIDENCE-CATALOG-DIGEST",
            mutator=lambda catalog: catalog["locks"].update(
                {"evidenceSchemaCoreSha256": "0" * 64}
            ),
        )
        for lock_field, label in (
            ("evidenceValidatorSha256", "implementation-validator-lock"),
            ("finalizerSha256", "implementation-finalizer-lock"),
        ):
            assert_catalog_rejection(
                module,
                temporary_root,
                development_root,
                document,
                catalog_path,
                run_binding_sha256,
                label=label,
                expected_code="PF-EVIDENCE-CATALOG-DIGEST",
                mutator=lambda catalog, lock_field=lock_field: catalog["locks"].update(
                    {lock_field: "0" * 64}
                ),
            )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="candidate-policy",
            expected_code="PF-EVIDENCE-CANDIDATE-BINDING",
            mutator=lambda catalog: catalog["gates"][0]["candidatePolicy"].update(
                {"dirty": True}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="host-policy",
            expected_code="PF-EVIDENCE-HOST-BINDING",
            mutator=lambda catalog: catalog["gates"][0]["hostPolicy"].update(
                {"eligibleForHermetic": True}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="denial-non-wrapper-executable",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][0]["probes"][
                1
            ]["command"].update({"executable": {"kind": "tool", "id": "lean"}}),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="denial-operation-argv-mismatch",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][0]["probes"][
                1
            ]["command"]["argv"].__setitem__(
                1,
                {"kind": "literal", "value": "tcp-bind"},
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="dangling-input-executable",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][1]["probes"][
                0
            ]["command"].update(
                {
                    "executable": {
                        "kind": "input",
                        "path": "tcb/missing-input",
                        "role": "missing-input",
                    }
                }
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="dangling-artifact-executable",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][1]["probes"][
                0
            ]["command"]["executable"].update(
                {"path": "build/evm/Missing.bin"}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="non-retained-artifact-executable",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredArtifacts"][0].update(
                {"retained": False}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="rendered-policy-reuse",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][1].update(
                {
                    "renderedPolicyInput": copy.deepcopy(
                        catalog["gates"][0]["policies"][0]["renderedPolicyInput"]
                    )
                }
            ),
        )
        for field, label in (
            ("invocationContextInput", "invocation-context-reuse"),
            ("receiptInput", "invocation-receipt-reuse"),
            ("stdoutLog", "probe-stream-reuse"),
        ):
            assert_catalog_rejection(
                module,
                temporary_root,
                development_root,
                document,
                catalog_path,
                run_binding_sha256,
                label=label,
                expected_code="PF-EVIDENCE-CATALOG",
                mutator=lambda catalog, field=field: catalog["gates"][0]["policies"][1][
                    "probes"
                ][0].update(
                    {
                        field: copy.deepcopy(
                            catalog["gates"][0]["policies"][0]["probes"][0][field]
                        )
                    }
                ),
            )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="same-probe-stream-reuse",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["policies"][0]["probes"][0].update(
                {
                    "stderrLog": catalog["gates"][0]["policies"][0]["probes"][0][
                        "stdoutLog"
                    ]
                }
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="required-log-probe-stream-overlap",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredLogs"][1].update(
                {
                    "path": catalog["gates"][0]["policies"][0]["probes"][0][
                        "stdoutLog"
                    ]
                }
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="required-input-structural-overlap",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredInputs"][0].update(
                {
                    "path": catalog["gates"][0]["policies"][0]["renderedPolicyInput"][
                        "path"
                    ]
                }
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="required-input-path-reuse",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredInputs"][1].update(
                {"path": catalog["gates"][0]["requiredInputs"][0]["path"]}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="input-artifact-path-overlap",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredArtifacts"][0].update(
                {"path": catalog["gates"][0]["requiredInputs"][0]["path"]}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="input-log-path-overlap",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredLogs"][1].update(
                {"path": catalog["gates"][0]["requiredInputs"][0]["path"]}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="artifact-log-path-overlap",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: catalog["gates"][0]["requiredLogs"][0].update(
                {"path": catalog["gates"][0]["requiredArtifacts"][0]["path"]}
            ),
        )
        assert_catalog_rejection(
            module,
            temporary_root,
            development_root,
            document,
            catalog_path,
            run_binding_sha256,
            label="casefold-input-alias",
            expected_code="PF-EVIDENCE-CATALOG",
            mutator=lambda catalog: (
                catalog["gates"][0]["requiredInputs"][0].update(
                    {"path": "fixtures/CaseAlias.bin"}
                ),
                catalog["gates"][0]["requiredInputs"][1].update(
                    {"path": "fixtures/casealias.bin"}
                ),
            ),
        )
        retained_core_bytes = EVIDENCE_CORE.read_bytes() + b"# retained substitution\n"

        def assert_retained_core_rejection(
            label: str,
            *,
            file_bytes: bytes | None,
            claim_bytes: bytes | None,
        ) -> None:
            case_root = temporary_root / f"retained-core-{label}"
            shutil.copytree(development_root, case_root, copy_function=shutil.copy2)
            case_document = copy.deepcopy(document)
            if file_bytes is not None:
                replace_secure(case_root / "tcb/evidence_v1_core.py", file_bytes)
            if claim_bytes is not None:
                claim = next(
                    entry
                    for entry in case_document["inputs"]
                    if entry["role"] == "evidence-schema-core"
                )
                claim["sha256"] = sha256(claim_bytes)
                claim["size"] = len(claim_bytes)
            module.validate_evidence(case_document)
            replace_secure(
                case_root / "development-evidence.json",
                module.canonical_bytes(case_document),
            )
            output_root = temporary_root / f"retained-core-{label}-output"
            result = invoke(
                [
                    "finalize-development",
                    "--catalog",
                    catalog_path,
                    "--catalog-sha256",
                    catalog_sha256,
                    "--catalog-digest",
                    catalog_digest,
                    "--run-binding-sha256",
                    run_binding_sha256,
                    "--evidence",
                    "development-evidence.json",
                    "--bundle-root",
                    os.fspath(case_root),
                    "--output",
                    os.fspath(
                        output_root
                        / "finalized-development"
                        / document["gateCatalog"]["id"]
                        / document["gate"]["id"]
                        / "EVF-20260715-9002.json"
                    ),
                ]
            )
            stderr_lines = result.stderr.splitlines()
            if (
                result.returncode != 2
                or result.stdout
                or len(stderr_lines) != 1
                or not stderr_lines[0].startswith(b"PF-EVIDENCE-CATALOG-DIGEST: ")
            ):
                raise AssertionError(
                    f"retained evidence core {label} did not fail closed:\n"
                    + result.stderr.decode("utf-8", errors="replace")
                )
            if output_root.exists():
                raise AssertionError(f"retained evidence core {label} touched output")

        assert_retained_core_rejection(
            "file-only",
            file_bytes=retained_core_bytes,
            claim_bytes=None,
        )
        assert_retained_core_rejection(
            "claim-only",
            file_bytes=None,
            claim_bytes=retained_core_bytes,
        )
        assert_retained_core_rejection(
            "file-and-claim",
            file_bytes=retained_core_bytes,
            claim_bytes=retained_core_bytes,
        )
        finalized_id = "EVF-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d") + "-0001"
        output_root = temporary_root / "trusted-output"
        output_parent = (
            output_root
            / "finalized-development"
            / document["gateCatalog"]["id"]
            / document["gate"]["id"]
        )
        output_parent.mkdir(parents=True, mode=0o700)
        for directory in (output_root, *output_root.parents):
            if directory == temporary_root.parent:
                break
            if directory.exists() and directory != temporary_root.parent:
                directory.chmod(0o700)
        finalized_output = output_parent / f"{finalized_id}.json"
        result = invoke(
            [
                "finalize-development",
                "--catalog",
                catalog_path,
                "--catalog-sha256",
                catalog_sha256,
                "--catalog-digest",
                catalog_digest,
                "--run-binding-sha256",
                run_binding_sha256,
                "--evidence",
                "development-evidence.json",
                "--bundle-root",
                os.fspath(development_root),
                "--output",
                os.fspath(finalized_output),
            ]
        )
        if result.returncode != 0:
            raise AssertionError(
                "realistic development bundle did not produce an EVF record:\n"
                + result.stderr.decode("utf-8", errors="replace")
            )
        success = result.stdout.decode("utf-8", errors="strict")
        success_lines = success.splitlines()
        if len(success_lines) != 1:
            raise AssertionError("development success must be exactly one line")
        success_tokens = success_lines[0].split()
        for marker in (
            "development-catalog-verified",
            "formal-not-verified",
            "freshness-not-verified",
            "revocation-not-verified",
            "private-scan-not-verified",
        ):
            if marker not in success_tokens:
                raise AssertionError(f"development success omitted stable marker: {marker}")
        forbidden_claims = {"attested", "formal", "hermetic", "passed"}
        if forbidden_claims.intersection(success_tokens):
            raise AssertionError("development success emitted a forbidden stronger claim")
        if result.stderr:
            raise AssertionError("successful development finalization produced stderr")
        if not finalized_output.is_file():
            raise AssertionError("development finalization did not publish its EVF record")
        finalized_bytes = finalized_output.read_bytes()
        finalized = module.decode_json(finalized_bytes)
        if module.canonical_bytes(finalized) != finalized_bytes:
            raise AssertionError("development finalization record is not canonical")
        evidence_bytes = (development_root / "development-evidence.json").read_bytes()
        expected_claim_set = domain_sha256(
            b"pf.evidence.claim-set.v1",
            module.canonical_bytes(
                {
                    "artifacts": document["artifacts"],
                    "inputs": document["inputs"],
                    "logs": document["logs"],
                }
            ),
        )
        expected_limitations = [
            "formal-not-verified",
            "freshness-not-verified",
            "private-scan-not-verified",
            "revocation-not-verified",
        ]
        if set(finalized) != {
            "candidate",
            "catalog",
            "claimSetSha256",
            "evidence",
            "finalizedUtc",
            "finalizer",
            "gate",
            "host",
            "id",
            "limitations",
            "qualification",
            "result",
            "run",
            "schema",
        }:
            raise AssertionError("development EVF record has the wrong closed root")
        finalized_utc = finalized.get("finalizedUtc")
        if not isinstance(finalized_utc, str):
            raise AssertionError("development EVF omitted its UTC instant")
        try:
            parsed_finalized_utc = dt.datetime.strptime(
                finalized_utc, "%Y-%m-%dT%H:%M:%SZ"
            ).replace(tzinfo=dt.timezone.utc)
        except ValueError as error:
            raise AssertionError("development EVF UTC instant is not whole-second UTC") from error
        if parsed_finalized_utc.strftime("%Y%m%d") != finalized_id[4:12]:
            raise AssertionError("development EVF ID date does not match finalizedUtc")
        if (
            finalized["schema"] != "proof-forge.evidence-finalization.v1"
            or finalized["id"] != finalized_id
            or finalized["qualification"] != "development"
            or finalized["catalog"] != document["gateCatalog"]
            or finalized["gate"]
            != {
                "id": document["gate"]["id"],
                "taskId": document["gate"]["taskId"],
                "testIds": document["gate"]["testIds"],
            }
            or finalized["evidence"]
            != {
                "id": document["id"],
                "path": "development-evidence.json",
                "sha256": sha256(evidence_bytes),
                "size": len(evidence_bytes),
            }
            or finalized["run"]
            != {
                "id": "RUN-0123456789abcdef0123456789abcdef",
                "runBindingSha256": run_binding_sha256,
            }
            or finalized["claimSetSha256"] != expected_claim_set
            or finalized["candidate"]
            != {
                "archiveSha256": document["repository"]["archive"]["sha256"],
                "commit": document["repository"]["commit"],
                "treeObjectId": document["repository"]["treeObjectId"],
            }
            or finalized["host"]
            != {
                "observationSha256": document["hostAttestation"]["observationSha256"],
                "profileId": document["hostAttestation"]["profileId"],
            }
            or finalized["finalizer"] != {"sha256": sha256(GATE_EVIDENCE.read_bytes())}
            or finalized["result"] != "catalog-verified"
            or finalized["limitations"] != expected_limitations
        ):
            raise AssertionError("development EVF record does not preserve exact bindings")
        if (finalized_output.stat().st_mode & 0o777) != 0o444:
            raise AssertionError("development EVF record is not immutable mode 0444")
        if finalized_output.stat().st_nlink != 1:
            raise AssertionError("development EVF record is not single-linked")
    print("gate evidence finalization self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
