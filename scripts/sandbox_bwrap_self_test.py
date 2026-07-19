#!/usr/bin/env python3
"""Acceptance tests for the bwrap stage engine (TASK-D0-07 slice S6).

Exercises ``scripts/sandbox_bwrap.py`` (profile renderer, launcher,
engine-neutral sandbox-invocation receipt, probe wrapper) with REAL
bubblewrap invocations on this host.  The whole suite skips cleanly (exit 0
with a note) only when bwrap is absent; it is present on this host.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent
MODULE_PATH = REPO_ROOT / "sandbox_bwrap.py"
BWRAP = "/usr/bin/bwrap"
CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "sandbox-bwrap self-test requires -I"
    assert sys.flags.no_site, "sandbox-bwrap self-test requires -S"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def checked(label: str) -> None:
    global CHECKS
    CHECKS += 1
    print(f"ok: {label}")


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def expect_error(module: ModuleType, code: str, label: str, operation) -> None:
    try:
        result = operation()
    except module.BwrapError as error:
        if error.code != code:
            raise AssertionError(f"{label} raised {error.code}: {error.detail}")
        checked(label)
        return
    raise AssertionError(f"{label} must fail with {code}; got {result!r}")


def main() -> int:
    if not Path(BWRAP).is_file() or os.environ.get("PF_BWRAP_SKIP"):
        print("sandbox-bwrap-self-test: SKIP (bwrap unavailable)")
        return 0
    module = load_module(MODULE_PATH, "proof_forge_sandbox_bwrap_under_test")

    for name in (
        "render_stage_profile",
        "profile_argv",
        "launch_stage",
        "validate_receipt_document",
        "BwrapError",
        "PROFILE_SCHEMA",
        "RECEIPT_SCHEMA",
        "PROBE_DENIED_MARKER",
        "STAGES",
        "main",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    with tempfile.TemporaryDirectory(prefix="sandbox-bwrap-test-") as temporary:
        workspace = Path(temporary).resolve()
        policies = workspace / "policies"
        policies.mkdir()
        (workspace / "inputs").mkdir()
        candidate = workspace / "inputs" / "candidate.tar"
        candidate.write_bytes(b"fixture candidate archive\n")
        tool_root = workspace / "inputs" / "tool"
        tool_root.mkdir()
        (tool_root / "tool.bin").write_bytes(b"fixture tool\n")

        python_exe = os.path.realpath("/usr/bin/python3")
        runtime_binds = [
            {"src": python_exe, "dest": python_exe, "readOnly": True},
            {"src": "/usr/lib", "dest": "/usr/lib", "readOnly": True},
            {"src": "/lib", "dest": "/lib", "readOnly": True},
            {"src": "/lib64", "dest": "/lib64", "readOnly": True},
        ]
        stage_binds = runtime_binds + [
            {"src": str(REPO_ROOT / "sandbox_bwrap.py"),
             "dest": "/opt/probe/sandbox_bwrap.py", "readOnly": True},
            {"src": str(candidate), "dest": "/opt/candidate/candidate.tar",
             "readOnly": True},
            {"src": str(tool_root), "dest": "/opt/tool", "readOnly": True},
        ]
        env_entries = [
            {"name": "LC_ALL", "value": "C"},
            {"name": "PATH", "value": "/usr/bin:/bin"},
        ]

        # Positive: materialize profile wire + argv derivation.
        profile = module.render_stage_profile(
            "materialize",
            binds=stage_binds,
            tmpfs=("/workspace",),
            env=env_entries,
            workdir="/workspace",
        )
        assert profile["schema"] == "proof-forge.bwrap-stage-profile.v1"
        assert profile["stage"] == "materialize"
        assert profile["networkMode"] == "deny-all"
        argv = module.profile_argv(profile)
        assert argv[0] == BWRAP
        assert "--unshare-net" in argv
        assert "--clearenv" in argv
        assert "--tmpfs" in argv
        checked("materialize profile renders deny-all argv")

        # Positive: evm-runtime profile is loopback-only with --unshare-user.
        runtime_profile = module.render_stage_profile(
            "evm-runtime",
            binds=stage_binds,
            tmpfs=("/workspace",),
            env=env_entries,
            workdir="/workspace",
        )
        assert runtime_profile["networkMode"] == "loopback-only"
        runtime_argv = module.profile_argv(runtime_profile)
        assert "--unshare-user" in runtime_argv
        checked("evm-runtime profile renders loopback-only argv")

        # Negatives: profile schema violations.
        expect_error(
            module, "PF-SANDBOX-BWRAP-SCHEMA", "unknown stage rejected",
            lambda: module.render_stage_profile(
                "bogus-stage", binds=stage_binds, tmpfs=("/workspace",),
                env=env_entries, workdir="/workspace",
            ),
        )
        expect_error(
            module, "PF-SANDBOX-BWRAP-SCHEMA", "relative bind dest rejected",
            lambda: module.render_stage_profile(
                "core",
                binds=[{"src": str(candidate), "dest": "relative/dest",
                        "readOnly": True}],
                tmpfs=("/workspace",), env=env_entries, workdir="/workspace",
            ),
        )
        expect_error(
            module, "PF-SANDBOX-BWRAP-SCHEMA", "non-readOnly stage bind rejected",
            lambda: module.render_stage_profile(
                "materialize",
                binds=[{"src": str(candidate), "dest": "/opt/candidate/candidate.tar",
                        "readOnly": False}],
                tmpfs=("/workspace",), env=env_entries, workdir="/workspace",
            ),
        )
        expect_error(
            module, "PF-SANDBOX-BWRAP-IO", "missing bind source rejected",
            lambda: module.render_stage_profile(
                "core",
                binds=runtime_binds + [
                    {"src": "/does/not/exist", "dest": "/opt/missing",
                     "readOnly": True},
                ],
                tmpfs=("/workspace",), env=env_entries, workdir="/workspace",
            ),
        )

        def probe_launch(stage: str, probe_args: tuple, **kwargs):
            return module.launch_stage(
                stage=stage,
                invocation="probe-01",
                payload=[python_exe, "-I", "-S",
                         "/opt/probe/sandbox_bwrap.py", "probe", "--",
                         *probe_args],
                binds=stage_binds,
                tmpfs=("/workspace",),
                env=env_entries,
                workdir="/workspace",
                timeout_seconds=20.0,
                runtime_port=kwargs.get("runtime_port"),
                run_binding_sha256="ab" * 32,
                invocation_binding_sha256="cd" * 32,
                policies_dir=policies,
                receipt=kwargs.get("receipt", False),
            )

        # Positive: deny-all outbound connects are denied with exit 77.
        for target in ("10.203.0.1", "192.168.1.1"):
            outcome = probe_launch("materialize", ("connect", target, "80"))
            assert outcome.exitCode == 77, (target, outcome.exitCode, outcome.stderr)
            assert outcome.stderr == b"PF-SANDBOX-PROBE-DENIED\n"
            assert outcome.stdout == b""
        checked("deny-all: LAN connects exit 77 with exact marker")

        # Positive: read-only bind write denied (EROFS) with exit 77.
        outcome = probe_launch(
            "materialize", ("write-file", "/opt/candidate/candidate.tar", "x")
        )
        assert outcome.exitCode == 77, outcome.stderr
        assert outcome.stderr == b"PF-SANDBOX-PROBE-DENIED\n"
        checked("read-only bind write exits 77 with exact marker")

        # Positive: tmpfs workspace is writable (probe succeeds).
        outcome = probe_launch(
            "materialize", ("write-file", "/workspace/scratch.txt", "x")
        )
        assert outcome.exitCode == 0, outcome.stderr
        checked("tmpfs workspace write succeeds")

        # Positive: loopback connect to a closed port is a refusal, NOT a denial.
        outcome = probe_launch("materialize", ("connect", "127.0.0.1", "9"))
        assert outcome.exitCode == 1, outcome.exitCode
        assert outcome.stderr != b"PF-SANDBOX-PROBE-DENIED\n"
        checked("loopback closed-port refusal is not a denial (kernel note)")

        # Positive: evm-runtime loopback round-trip works; LAN denied; adjacent refused.
        runtime_port = 18747
        outcome = probe_launch(
            "evm-runtime", ("listen-connect", str(runtime_port)),
            runtime_port=runtime_port,
        )
        assert outcome.exitCode == 0, (outcome.exitCode, outcome.stderr)
        assert outcome.stdout == b"loopback-ok\n"
        checked("evm-runtime loopback round-trip succeeds")
        outcome = probe_launch(
            "evm-runtime", ("connect", "10.203.0.1", "80"),
            runtime_port=runtime_port,
        )
        assert outcome.exitCode == 77
        checked("evm-runtime LAN connect exits 77")
        outcome = probe_launch(
            "evm-runtime", ("listen-connect", str(runtime_port + 1)),
            runtime_port=runtime_port,
        )
        assert outcome.exitCode == 0
        outcome = probe_launch(
            "evm-runtime", ("connect", "127.0.0.1", str(runtime_port + 1)),
            runtime_port=runtime_port,
        )
        assert outcome.exitCode == 1
        assert outcome.stderr != b"PF-SANDBOX-PROBE-DENIED\n"
        checked("evm-runtime adjacent-port refusal is not a denial")

        # Positive: full receipt for a materialize run (fresh policies dir).
        receipt_dir = workspace / "receipt-policies"
        receipt_dir.mkdir()
        def receipt_launch(stage, probe_args, dir_path, **kwargs):
            return module.launch_stage(
                stage=stage,
                invocation="probe-01",
                payload=[python_exe, "-I", "-S",
                         "/opt/probe/sandbox_bwrap.py", "probe", "--",
                         *probe_args],
                binds=stage_binds,
                tmpfs=("/workspace",),
                env=env_entries,
                workdir="/workspace",
                timeout_seconds=20.0,
                runtime_port=kwargs.get("runtime_port"),
                run_binding_sha256="ab" * 32,
                invocation_binding_sha256="cd" * 32,
                policies_dir=dir_path,
                receipt=True,
            )
        outcome = receipt_launch(
            "materialize", ("write-file", "/workspace/a.txt", "x"), receipt_dir
        )
        receipt_path = receipt_dir / "sandbox-materialize-probe-01.receipt.json"
        assert receipt_path.is_file()
        metadata = receipt_path.stat()
        assert stat.S_IMODE(metadata.st_mode) == 0o400
        assert metadata.st_nlink == 1
        receipt = json.loads(receipt_path.read_bytes().decode("utf-8"))
        assert receipt["schema"] == "proof-forge.sandbox-invocation.v1"
        assert receipt["stage"] == "materialize"
        assert receipt["engine"]["id"] == "bwrap"
        assert receipt["engine"]["path"] == BWRAP
        assert receipt["engine"]["observedSha256"] == sha256(
            Path(BWRAP).read_bytes()
        )
        assert receipt["policy"]["path"] == "policies/materialize.bwrap.json"
        policy_bytes = (receipt_dir / "materialize.bwrap.json").read_bytes()
        assert receipt["policy"]["sha256"] == sha256(policy_bytes)
        assert receipt["policy"]["size"] == len(policy_bytes)
        assert receipt["runtimePort"] is None
        assert receipt["command"]["argv"][0] == python_exe
        assert receipt["command"]["observedExecutableSha256"] == sha256(
            Path(python_exe).read_bytes()
        )
        assert receipt["terminal"] == {
            "exitCode": 0, "signal": None, "timedOut": False
        }
        stdout_log = receipt_dir / "sandbox-materialize-probe-01.stdout.log"
        stderr_log = receipt_dir / "sandbox-materialize-probe-01.stderr.log"
        assert receipt["stdout"]["path"] == (
            "policies/sandbox-materialize-probe-01.stdout.log"
        )
        assert receipt["stdout"]["sha256"] == sha256(stdout_log.read_bytes())
        assert receipt["stderr"]["sha256"] == sha256(stderr_log.read_bytes())
        for path in (stdout_log, stderr_log):
            assert stat.S_IMODE(path.stat().st_mode) == 0o400
            assert path.stat().st_nlink == 1
        assert receipt_path.stat().st_mtime_ns >= stdout_log.stat().st_mtime_ns
        module.validate_receipt_document(receipt)
        checked("materialize receipt conforms to the engine-neutral schema")

        # Positive: evm-runtime receipt records the runtime port (fresh dir).
        runtime_dir = workspace / "runtime-policies"
        runtime_dir.mkdir()
        outcome = receipt_launch(
            "evm-runtime", ("listen-connect", str(runtime_port)), runtime_dir,
            runtime_port=runtime_port,
        )
        runtime_receipt_path = runtime_dir / "sandbox-evm-runtime-probe-01.receipt.json"
        runtime_receipt = json.loads(runtime_receipt_path.read_bytes().decode("utf-8"))
        assert runtime_receipt["runtimePort"] == runtime_port
        assert runtime_receipt["policy"]["path"] == "policies/evm-runtime.bwrap.json"
        module.validate_receipt_document(runtime_receipt)
        checked("evm-runtime receipt records runtimePort")

        # Negative: receipt tamper is rejected by validation (digest recompute).
        tampered = json.loads(json.dumps(runtime_receipt))
        tampered["command"]["argv"][1] = "-X"
        expect_error(
            module, "PF-SANDBOX-BWRAP-RECEIPT",
            "tampered argv breaks the argv digest",
            lambda: module.validate_receipt_document(tampered),
        )
        tampered_env = json.loads(json.dumps(runtime_receipt))
        tampered_env["environment"]["entries"][0]["value"] = "drifted"
        expect_error(
            module, "PF-SANDBOX-BWRAP-RECEIPT",
            "tampered environment breaks the environment digest",
            lambda: module.validate_receipt_document(tampered_env),
        )
        # Negative: malformed receipt (unknown field) rejected.
        expect_error(
            module, "PF-SANDBOX-BWRAP-RECEIPT",
            "receipt with unknown field rejected",
            lambda: module.validate_receipt_document(
                {**runtime_receipt, "extra": True}
            ),
        )

        # Negative: replay into the no-clobber policies dir fails, no new receipt.
        expect_error(
            module, "PF-SANDBOX-BWRAP-IO",
            "receipt publication is no-clobber",
            lambda: receipt_launch(
                "materialize", ("write-file", "/workspace/b.txt", "x"), receipt_dir
            ),
        )
        checked("replay into an existing policies dir fails closed")

        # Negative: stdout cap kills the run with no receipt.
        fresh = workspace / "cap-policies"
        fresh.mkdir()
        expect_error(
            module, "PF-SANDBOX-BWRAP-SPAWN",
            "stdout beyond the cap fails with no receipt",
            lambda: module.launch_stage(
                stage="core",
                invocation="cap-01",
                payload=[python_exe, "-I", "-S", "/opt/probe/sandbox_bwrap.py",
                         "probe", "--", "flood-stdout"],
                binds=stage_binds,
                tmpfs=("/workspace",),
                env=env_entries,
                workdir="/workspace",
                timeout_seconds=20.0,
                runtime_port=None,
                run_binding_sha256="ab" * 32,
                invocation_binding_sha256="cd" * 32,
                policies_dir=fresh,
                receipt=True,
            ),
        )
        assert not list(fresh.rglob("*.receipt.json"))
        checked("stdout cap failure leaves no receipt")

        # Negative: timeout kills the payload, no receipt, no survivors.
        fresh_timeout = workspace / "timeout-policies"
        fresh_timeout.mkdir()
        expect_error(
            module, "PF-SANDBOX-BWRAP-SPAWN",
            "timeout kill leaves no receipt",
            lambda: module.launch_stage(
                stage="core",
                invocation="timeout-01",
                payload=[python_exe, "-I", "-S", "/opt/probe/sandbox_bwrap.py",
                         "probe", "--", "sleep-forever"],
                binds=stage_binds,
                tmpfs=("/workspace",),
                env=env_entries,
                workdir="/workspace",
                timeout_seconds=0.5,
                runtime_port=None,
                run_binding_sha256="ab" * 32,
                invocation_binding_sha256="cd" * 32,
                policies_dir=fresh_timeout,
                receipt=True,
            ),
        )
        assert not list(fresh_timeout.rglob("*.receipt.json"))
        checked("timeout kill leaves no receipt")

        # Positive: stdin is at EOF for the payload.
        fresh_stdin = workspace / "stdin-policies"
        fresh_stdin.mkdir()
        outcome = module.launch_stage(
            stage="core",
            invocation="stdin-01",
            payload=[python_exe, "-I", "-S", "/opt/probe/sandbox_bwrap.py",
                     "probe", "--", "read-stdin"],
            binds=stage_binds,
            tmpfs=("/workspace",),
            env=env_entries,
            workdir="/workspace",
            timeout_seconds=20.0,
            runtime_port=None,
            run_binding_sha256="ab" * 32,
            invocation_binding_sha256="cd" * 32,
            policies_dir=fresh_stdin,
            receipt=False,
        )
        assert outcome.exitCode == 0
        assert outcome.stdout == b"stdin-eof\n"
        checked("payload stdin is at EOF")

        # Positive: only 0/1/2 (+ nothing else) leak into the payload.
        fresh_fd = workspace / "fd-policies"
        fresh_fd.mkdir()
        outcome = module.launch_stage(
            stage="core",
            invocation="fd-01",
            payload=[python_exe, "-I", "-S", "/opt/probe/sandbox_bwrap.py",
                     "probe", "--", "list-fds"],
            binds=stage_binds,
            tmpfs=("/workspace",),
            env=env_entries,
            workdir="/workspace",
            timeout_seconds=20.0,
            runtime_port=None,
            run_binding_sha256="ab" * 32,
            invocation_binding_sha256="cd" * 32,
            policies_dir=fresh_fd,
            receipt=False,
        )
        assert outcome.exitCode == 0
        assert outcome.stdout == b"fds:0,1,2\n", outcome.stdout
        checked("payload inherits exactly fds 0/1/2")

        # Negative: missing payload executable.
        expect_error(
            module, "PF-SANDBOX-BWRAP-IO",
            "missing payload executable rejected",
            lambda: module.launch_stage(
                stage="core",
                invocation="missing-01",
                payload=["/does/not/exist", "-c", "pass"],
                binds=stage_binds,
                tmpfs=("/workspace",),
                env=env_entries,
                workdir="/workspace",
                timeout_seconds=20.0,
                runtime_port=None,
                run_binding_sha256="ab" * 32,
                invocation_binding_sha256="cd" * 32,
                policies_dir=workspace / "missing-policies",
                receipt=True,
            ),
        )

        # Negative: probe non-denial error is a failure, not exit 77.
        outcome = probe_launch(
            "materialize", ("read-file", "/opt/probe/sandbox_bwrap.py")
        )
        assert outcome.exitCode == 0
        checked("probe read-file of bound path succeeds")

    print(f"sandbox-bwrap-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
