#!/usr/bin/env python3
"""bwrap stage engine (TASK-D0-07 slice S6, ADR-0018 §2).

Profile renderer, launcher, engine-neutral sandbox-invocation receipt
producer, and probe wrapper for the linux stage engine.  Stage semantics:
``materialize``/``core`` run deny-all (``--unshare-net``; on this kernel
loopback comes up inside the new net namespace but has no route and no
peers — outbound connects fail with ENETUNREACH/EADDRNOTAVAIL), while
``evm-runtime`` runs loopback-only (``--unshare-user --unshare-net``; the
kernel brings ``lo`` up by default in the new namespace — verified live on
this host with a real TCP round-trip, ``ip link set lo up`` works under
``--cap-add CAP_NET_ADMIN`` but is unnecessary here and is not required).

Receipt fields follow the engine-neutral schema
(gate-catalog-finalization.md §sandbox-invocation): closed root, engine
object ``{id:"bwrap", path, observedSha256}``, policy path
``policies/<stage>.bwrap.json``, ``runtimePort`` only for evm-runtime,
argv/environment domain digests, exact terminal, and stream fields.
Publication mirrors sandbox_exec's discipline at slice depth: no-clobber
reservation, atomic 0400 single-link writes (policy → streams → receipt
last), readback verification, and rollback on any failure.  The probe
wrapper maps isolation-layer denials to exit 77 with stderr exactly
``PF-SANDBOX-PROBE-DENIED\n``: EACCES/EPERM per the spec contract, EROFS
for read-only bind mounts, and ENETUNREACH/EADDRNOTAVAIL for namespace
network denial (the bwrap engine's denial shape; documented in the log).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import selectors
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn, Optional, Sequence, Tuple


BWRAP_PATH = "/usr/bin/bwrap"
PROFILE_SCHEMA = "proof-forge.bwrap-stage-profile.v1"
RECEIPT_SCHEMA = "proof-forge.sandbox-invocation.v1"
PROBE_DENIED_MARKER = b"PF-SANDBOX-PROBE-DENIED\n"
STAGES = ("materialize", "core", "evm-runtime")
ARGV_DOMAIN = b"pf.sandbox.argv.v1\x00"
ENVIRONMENT_DOMAIN = b"pf.sandbox.environment.v1\x00"
INVOCATION_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,47}")
ENVIRONMENT_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,254}")
SHA256_RE = re.compile(r"[0-9a-f]{64}")
MAX_STREAM_BYTES = 4 * 1024 * 1024
MAX_POLICY_BYTES = 128 * 1024
MAX_ARGUMENT_BYTES = 64 * 1024
MAX_ENVIRONMENT_VALUE_BYTES = 64 * 1024
MAX_OBSERVED_BYTES = 256 * 1024 * 1024
MAX_RECEIPT_BYTES = 1024 * 1024
MAX_DURATION_MS = 86400000
_DENIAL_ERRNOS_NETWORK = frozenset({13, 1, 101, 99})
_DENIAL_ERRNOS_FILE = frozenset({13, 1, 30})


class BwrapError(Exception):
    """Stable bwrap engine failure with fixed non-content details."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise BwrapError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-SANDBOX-BWRAP-SCHEMA", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-SANDBOX-BWRAP-IO", detail)


def _spawn(detail: str) -> NoReturn:
    _fail("PF-SANDBOX-BWRAP-SPAWN", detail)


def _policy(detail: str) -> NoReturn:
    _fail("PF-SANDBOX-BWRAP-POLICY", detail)


def _receipt(detail: str) -> NoReturn:
    _fail("PF-SANDBOX-BWRAP-RECEIPT", detail)


@dataclass(frozen=True)
class LaunchOutcome:
    exitCode: Optional[int]
    signal: Optional[int]
    stdout: bytes
    stderr: bytes
    durationMs: int
    receiptPath: Optional[str]


def _canonical_json_bytes(value: object) -> bytes:
    def check(item: object) -> None:
        if item is None or type(item) in (str, bool):
            return
        if type(item) is int:
            if abs(item) > (1 << 53) - 1:
                _receipt("canonical JSON integer exceeds the safe range")
            return
        if type(item) is list:
            for element in item:
                check(element)
            return
        if type(item) is dict:
            for key, element in item.items():
                if type(key) is not str:
                    _receipt("canonical JSON keys must be strings")
                check(element)
            return
        _receipt("value is outside the canonical JSON data model")

    check(value)
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


def _sha256_domain(domain: bytes, value: object) -> str:
    return hashlib.sha256(domain + _canonical_json_bytes(value)).hexdigest()


def _require_sha256(value: object, where: str) -> str:
    if type(value) is not str or SHA256_RE.fullmatch(value) is None:
        _schema(f"{where} must be 64 lowercase hex")
    assert isinstance(value, str)
    return value


def _read_observed(path: Path, label: str) -> Tuple[bytes, str]:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        _io(f"cannot observe {label}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _io(f"{label} is not a regular file")
        if metadata.st_size > MAX_OBSERVED_BYTES:
            _io(f"{label} exceeds the observed executable maximum")
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
        payload = b"".join(chunks)
    finally:
        os.close(fd)
    return payload, hashlib.sha256(payload).hexdigest()


def _atomic_write_0400(path: Path, payload: bytes, label: str) -> None:
    fd, temp_path = tempfile.mkstemp(prefix=".stage-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, 0o400)
        try:
            os.link(temp_path, path)
        except FileExistsError:
            _io(f"{label} already exists (no-clobber)")
        except OSError:
            _io(f"cannot publish {label}")
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def _require_absolute_normalized(value: object, where: str) -> str:
    if type(value) is not str or not value or "\x00" in value:
        _schema(f"{where} must be a non-empty path without NUL")
    assert isinstance(value, str)
    if not value.startswith("/") or os.path.normpath(value) != value:
        _schema(f"{where} must be an absolute normalized path")
    return value


def render_stage_profile(
    stage: str,
    *,
    binds: Sequence[dict],
    tmpfs: Sequence[str],
    env: Sequence[dict],
    workdir: str,
) -> dict:
    """Render the closed bwrap stage profile for one stage."""
    if stage not in STAGES:
        _schema("stage is not one of materialize/core/evm-runtime")
    network_mode = "loopback-only" if stage == "evm-runtime" else "deny-all"
    bind_wires = []
    seen_dests = set()
    for index, entry in enumerate(binds):
        where = f"binds[{index}]"
        if type(entry) is not dict or set(entry) != {"src", "dest", "readOnly"}:
            _schema(f"{where} must be a closed bind object")
        src = _require_absolute_normalized(entry["src"], f"{where}.src")
        dest = _require_absolute_normalized(entry["dest"], f"{where}.dest")
        if entry["readOnly"] is not True:
            _schema(f"{where} must be read-only (candidate tree non-writable)")
        if not os.path.lexists(src):
            _io(f"bind source does not exist: {where}.src")
        if dest in seen_dests:
            _schema("binds must be unique by dest")
        seen_dests.add(dest)
        bind_wires.append({"src": src, "dest": dest, "readOnly": True})
    bind_wires.sort(key=lambda item: item["dest"])
    tmpfs_wires = []
    for index, entry in enumerate(tmpfs):
        tmpfs_wires.append(
            _require_absolute_normalized(entry, f"tmpfs[{index}]")
        )
    if tmpfs_wires != sorted(tmpfs_wires) or len(set(tmpfs_wires)) != len(tmpfs_wires):
        _schema("tmpfs must be unique ascending")
    env_wires = []
    seen_names = set()
    for index, entry in enumerate(env):
        where = f"env[{index}]"
        if type(entry) is not dict or set(entry) != {"name", "value"}:
            _schema(f"{where} must be a closed env object")
        name = entry["name"]
        if type(name) is not str or ENVIRONMENT_NAME_RE.fullmatch(name) is None:
            _schema(f"{where}.name is invalid")
        value = entry["value"]
        if type(value) is not str or "\x00" in value or len(
            value.encode("utf-8")
        ) > MAX_ENVIRONMENT_VALUE_BYTES:
            _schema(f"{where}.value exceeds the environment value maximum")
        if name in seen_names:
            _schema("env must be unique by name")
        seen_names.add(name)
        env_wires.append({"name": name, "value": value})
    env_wires.sort(key=lambda item: item["name"])
    workdir = _require_absolute_normalized(workdir, "workdir")
    return {
        "schema": PROFILE_SCHEMA,
        "stage": stage,
        "networkMode": network_mode,
        "unshareUser": stage == "evm-runtime",
        "binds": bind_wires,
        "tmpfs": tmpfs_wires,
        "env": env_wires,
        "workdir": workdir,
    }


def profile_argv(profile: dict) -> list:
    """Derive the exact bwrap argv prefix from a rendered profile."""
    if type(profile) is not dict or profile.get("schema") != PROFILE_SCHEMA:
        _schema("profile is not a rendered bwrap stage profile")
    argv = [BWRAP_PATH, "--die-with-parent", "--unshare-pid", "--unshare-net"]
    if profile["unshareUser"]:
        argv.append("--unshare-user")
    argv.append("--clearenv")
    for entry in profile["env"]:
        argv.extend(("--setenv", entry["name"], entry["value"]))
    for bind in profile["binds"]:
        argv.extend(("--ro-bind", bind["src"], bind["dest"]))
    for mount in profile["tmpfs"]:
        argv.extend(("--tmpfs", mount))
    argv.extend(("--proc", "/proc"))
    argv.extend(("--chdir", profile["workdir"]))
    argv.append("--")
    return argv


def validate_receipt_document(value: object) -> dict:
    """Validate the engine-neutral sandbox-invocation receipt wire."""
    if type(value) is not dict:
        _receipt("receipt must be an object")
    required = {
        "schema", "stage", "invocation", "runBindingSha256",
        "invocationBindingSha256", "policy", "runtimePort", "engine",
        "observedLauncherSha256", "command", "environment", "durationMs",
        "terminal", "stdout", "stderr",
    }
    if set(value) != required:
        _receipt("receipt must be a closed root object")
    if value["schema"] != RECEIPT_SCHEMA:
        _receipt("receipt schema is not sandbox-invocation.v1")
    stage = value["stage"]
    if stage not in STAGES:
        _receipt("receipt stage is unsupported")
    invocation = value["invocation"]
    if type(invocation) is not str or INVOCATION_RE.fullmatch(invocation) is None:
        _receipt("receipt invocation must use the launcher id grammar")
    _require_sha256(value["runBindingSha256"], "receipt.runBindingSha256")
    _require_sha256(
        value["invocationBindingSha256"], "receipt.invocationBindingSha256"
    )
    policy = value["policy"]
    if type(policy) is not dict or set(policy) != {"path", "sha256", "size"}:
        _receipt("receipt policy must be a closed object")
    if policy["path"] != f"policies/{stage}.bwrap.json":
        _receipt("receipt policy path mismatch")
    _require_sha256(policy["sha256"], "receipt.policy.sha256")
    if type(policy["size"]) is not int or not 0 <= policy["size"] <= MAX_POLICY_BYTES:
        _receipt("receipt policy size exceeds the policy maximum")
    runtime_port = value["runtimePort"]
    if stage == "evm-runtime":
        if type(runtime_port) is not int or not 1 <= runtime_port <= 65535:
            _receipt("evm-runtime receipt requires an exact runtime port")
    elif runtime_port is not None:
        _receipt("non-runtime receipt must not carry a runtime port")
    engine = value["engine"]
    if type(engine) is not dict or set(engine) != {"id", "path", "observedSha256"}:
        _receipt("receipt engine must be a closed object")
    if engine["id"] not in ("sbpl", "bwrap"):
        _receipt("receipt engine id is unsupported")
    if type(engine["path"]) is not str or not engine["path"].startswith("/"):
        _receipt("receipt engine path must be absolute")
    _require_sha256(engine["observedSha256"], "receipt.engine.observedSha256")
    _require_sha256(
        value["observedLauncherSha256"], "receipt.observedLauncherSha256"
    )
    command = value["command"]
    if type(command) is not dict or set(command) != {
        "argv", "argvSha256", "observedExecutablePath",
        "observedExecutableSha256",
    }:
        _receipt("receipt command must be a closed object")
    argv = command["argv"]
    if type(argv) is not list or not argv:
        _receipt("receipt command argv must be non-empty")
    for index, argument in enumerate(argv):
        if type(argument) is not str or "\x00" in argument or len(
            argument.encode("utf-8")
        ) > MAX_ARGUMENT_BYTES:
            _receipt(f"receipt argv[{index}] exceeds the argument maximum")
    observed_path = command["observedExecutablePath"]
    if argv[0] != observed_path:
        _receipt("receipt observed executable path mismatch")
    _require_absolute_normalized(
        observed_path, "receipt.observedExecutablePath"
    )
    _require_sha256(
        command["observedExecutableSha256"],
        "receipt.command.observedExecutableSha256",
    )
    if command["argvSha256"] != _sha256_domain(ARGV_DOMAIN, argv):
        _receipt("receipt argv digest mismatch")
    environment = value["environment"]
    if type(environment) is not dict or set(environment) != {"entries", "sha256"}:
        _receipt("receipt environment must be a closed object")
    entries = environment["entries"]
    if type(entries) is not list:
        _receipt("receipt environment entries must be an array")
    names = []
    for index, entry in enumerate(entries):
        if type(entry) is not dict or set(entry) != {"name", "value"}:
            _receipt("receipt environment entry must be a closed object")
        name = entry["name"]
        if type(name) is not str or ENVIRONMENT_NAME_RE.fullmatch(name) is None:
            _receipt("receipt environment name is invalid")
        entry_value = entry["value"]
        if type(entry_value) is not str or "\x00" in entry_value or len(
            entry_value.encode("utf-8")
        ) > MAX_ENVIRONMENT_VALUE_BYTES:
            _receipt("receipt environment value exceeds the maximum")
        names.append(name)
    if names != sorted(names) or len(set(names)) != len(names):
        _receipt("receipt environment must be sorted and unique")
    if environment["sha256"] != _sha256_domain(ENVIRONMENT_DOMAIN, entries):
        _receipt("receipt environment digest mismatch")
    duration = value["durationMs"]
    if type(duration) is not int or not 0 <= duration <= MAX_DURATION_MS:
        _receipt("receipt durationMs out of range")
    terminal = value["terminal"]
    if type(terminal) is not dict or set(terminal) != {
        "exitCode", "signal", "timedOut"
    }:
        _receipt("receipt terminal must be a closed object")
    if terminal["timedOut"] is not False:
        _receipt("committed receipt cannot be timed out")
    exit_code = terminal["exitCode"]
    signal_value = terminal["signal"]
    if exit_code is not None and (
        type(exit_code) is not int or not 0 <= exit_code <= 255
    ):
        _receipt("receipt exitCode out of range")
    if signal_value is not None and (
        type(signal_value) is not int or not 1 <= signal_value <= 255
    ):
        _receipt("receipt signal out of range")
    if (exit_code is None) == (signal_value is None):
        _receipt("receipt terminal must select exit or signal")
    for stream_name in ("stdout", "stderr"):
        stream = value[stream_name]
        if type(stream) is not dict or set(stream) != {
            "path", "sha256", "size", "truncated"
        }:
            _receipt(f"receipt {stream_name} must be a closed object")
        if stream["path"] != (
            f"policies/sandbox-{stage}-{invocation}.{stream_name}.log"
        ):
            _receipt(f"receipt {stream_name} path mismatch")
        _require_sha256(stream["sha256"], f"receipt.{stream_name}.sha256")
        if type(stream["size"]) is not int or not 0 <= (
            stream["size"]
        ) <= MAX_STREAM_BYTES:
            _receipt(f"receipt {stream_name} size exceeds the stream maximum")
        if stream["truncated"] is not False:
            _receipt("receipt streams cannot be truncated")
    return value


def _bounded_capture(process: subprocess.Popen, timeout_seconds: float) -> Tuple[bytes, bytes, bool, bool]:
    """Capture stdout/stderr bounded; returns (stdout, stderr, timed_out, capped)."""
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    streams = {"stdout": process.stdout, "stderr": process.stderr}
    output = {"stdout": bytearray(), "stderr": bytearray()}
    for name, stream in streams.items():
        os.set_blocking(stream.fileno(), False)
        selector.register(stream, selectors.EVENT_READ, name)
    deadline = time.monotonic() + timeout_seconds
    timed_out = False
    capped = False
    while selector.get_map():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            timed_out = True
            break
        events = selector.select(min(remaining, 0.1))
        for key, _ in events:
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
                continue
            name = key.data
            output[name].extend(chunk)
            if len(output[name]) > MAX_STREAM_BYTES:
                capped = True
        if capped:
            break
    if timed_out or capped:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    process.wait()
    for stream in streams.values():
        stream.close()
    return bytes(output["stdout"]), bytes(output["stderr"]), timed_out, capped


def launch_stage(
    *,
    stage: str,
    invocation: str,
    payload: Sequence[str],
    binds: Sequence[dict],
    tmpfs: Sequence[str],
    env: Sequence[dict],
    workdir: str,
    timeout_seconds: float,
    runtime_port: Optional[int],
    run_binding_sha256: str,
    invocation_binding_sha256: str,
    policies_dir,
    receipt: bool = True,
) -> LaunchOutcome:
    """Launch one payload under the rendered bwrap profile."""
    if type(invocation) is not str or INVOCATION_RE.fullmatch(invocation) is None:
        _schema("invocation must use the launcher id grammar")
    if type(payload) is not list or not payload:
        payload = list(payload)
    if not payload:
        _schema("payload argv must be non-empty")
    for index, argument in enumerate(payload):
        if type(argument) is not str or "\x00" in argument or len(
            argument.encode("utf-8")
        ) > MAX_ARGUMENT_BYTES:
            _schema(f"payload argv[{index}] exceeds the argument maximum")
    executable = _require_absolute_normalized(payload[0], "payload executable")
    if stage == "evm-runtime":
        if type(runtime_port) is not int or not 1 <= runtime_port <= 65535:
            _schema("evm-runtime requires an exact runtime port")
    elif runtime_port is not None:
        _schema(f"{stage} forbids a runtime port")
    _require_sha256(run_binding_sha256, "runBindingSha256")
    _require_sha256(invocation_binding_sha256, "invocationBindingSha256")
    profile = render_stage_profile(
        stage, binds=binds, tmpfs=tmpfs, env=env, workdir=workdir
    )
    _, executable_sha256 = _read_observed(Path(executable), "payload executable")
    engine_path = Path(BWRAP_PATH)
    if not engine_path.is_file():
        _io("bwrap executable is unavailable")
    _, engine_sha256 = _read_observed(engine_path, "bwrap engine")
    _, launcher_sha256 = _read_observed(
        Path(__file__).resolve(strict=True), "bwrap launcher"
    )
    profile_bytes = _canonical_json_bytes(profile)
    if len(profile_bytes) > MAX_POLICY_BYTES:
        _policy("rendered profile exceeds the policy maximum")

    policies_path = Path(policies_dir)
    policies_path.mkdir(parents=True, exist_ok=True)
    policy_path = policies_path / f"{stage}.bwrap.json"
    stdout_path = policies_path / f"sandbox-{stage}-{invocation}.stdout.log"
    stderr_path = policies_path / f"sandbox-{stage}-{invocation}.stderr.log"
    receipt_path = policies_path / f"sandbox-{stage}-{invocation}.receipt.json"
    reservation_path = policies_path / f".sandbox-{stage}-{invocation}.reservation"
    published: list = []
    if receipt:
        for path in (policy_path, stdout_path, stderr_path, receipt_path):
            if path.exists() or path.is_symlink():
                _io(f"publication target already exists: {path.name}")
        try:
            reservation_fd = os.open(
                reservation_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
            )
        except OSError:
            _io("invocation reservation already exists (single-writer)")
    else:
        reservation_fd = None

    def rollback() -> None:
        for path in published:
            try:
                os.unlink(path)
            except OSError:
                pass
        if reservation_fd is not None:
            try:
                os.close(reservation_fd)
            except OSError:
                pass
            try:
                os.unlink(reservation_path)
            except OSError:
                pass

    started_ns = time.monotonic_ns()
    argv = profile_argv(profile) + list(payload)
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
            env={},
        )
    except OSError:
        rollback()
        _spawn("cannot spawn the bwrap payload")
    stdout, stderr, timed_out, capped = _bounded_capture(process, timeout_seconds)
    return_code = process.returncode
    if timed_out:
        rollback()
        _spawn("sandbox stage exceeded the fixed timeout")
    if capped:
        rollback()
        _spawn("sandbox output exceeded the byte cap")
    if return_code < 0:
        terminal = {"exitCode": None, "signal": -return_code, "timedOut": False}
    else:
        terminal = {"exitCode": return_code, "signal": None, "timedOut": False}
    duration_ms = (time.monotonic_ns() - started_ns) // 1_000_000
    outcome = LaunchOutcome(
        terminal["exitCode"], terminal["signal"], stdout, stderr,
        duration_ms, None,
    )
    if not receipt:
        return outcome
    try:
        _atomic_write_0400(policy_path, profile_bytes, "policy")
        published.append(policy_path)
        _atomic_write_0400(stdout_path, stdout, "stdout log")
        published.append(stdout_path)
        _atomic_write_0400(stderr_path, stderr, "stderr log")
        published.append(stderr_path)
        receipt_document = {
            "schema": RECEIPT_SCHEMA,
            "stage": stage,
            "invocation": invocation,
            "runBindingSha256": run_binding_sha256,
            "invocationBindingSha256": invocation_binding_sha256,
            "policy": {
                "path": f"policies/{stage}.bwrap.json",
                "sha256": hashlib.sha256(profile_bytes).hexdigest(),
                "size": len(profile_bytes),
            },
            "runtimePort": runtime_port,
            "engine": {
                "id": "bwrap",
                "path": BWRAP_PATH,
                "observedSha256": engine_sha256,
            },
            "observedLauncherSha256": launcher_sha256,
            "command": {
                "argv": list(payload),
                "argvSha256": _sha256_domain(ARGV_DOMAIN, list(payload)),
                "observedExecutablePath": executable,
                "observedExecutableSha256": executable_sha256,
            },
            "environment": {
                "entries": [
                    {"name": entry["name"], "value": entry["value"]}
                    for entry in profile["env"]
                ],
                "sha256": _sha256_domain(
                    ENVIRONMENT_DOMAIN,
                    [
                        {"name": entry["name"], "value": entry["value"]}
                        for entry in profile["env"]
                    ],
                ),
            },
            "durationMs": duration_ms,
            "terminal": terminal,
            "stdout": {
                "path": f"policies/sandbox-{stage}-{invocation}.stdout.log",
                "sha256": hashlib.sha256(stdout).hexdigest(),
                "size": len(stdout),
                "truncated": False,
            },
            "stderr": {
                "path": f"policies/sandbox-{stage}-{invocation}.stderr.log",
                "sha256": hashlib.sha256(stderr).hexdigest(),
                "size": len(stderr),
                "truncated": False,
            },
        }
        validate_receipt_document(receipt_document)
        receipt_bytes = _canonical_json_bytes(receipt_document)
        if len(receipt_bytes) >= MAX_RECEIPT_BYTES:
            _receipt("receipt exceeds 1 MiB")
        _atomic_write_0400(receipt_path, receipt_bytes, "receipt")
        published.append(receipt_path)
        for path, payload_bytes in (
            (policy_path, profile_bytes),
            (stdout_path, stdout),
            (stderr_path, stderr),
            (receipt_path, receipt_bytes),
        ):
            reread, reread_sha256 = _read_observed(path, "published receipt member")
            if reread != payload_bytes or reread_sha256 != hashlib.sha256(
                payload_bytes
            ).hexdigest():
                _receipt("published receipt member changed on readback")
    except BwrapError:
        rollback()
        raise
    except OSError:
        rollback()
        _io("receipt publication failed")
    if reservation_fd is not None:
        os.close(reservation_fd)
        try:
            os.unlink(reservation_path)
        except OSError:
            pass
    return LaunchOutcome(
        terminal["exitCode"], terminal["signal"], stdout, stderr,
        duration_ms, str(receipt_path),
    )


def _probe_denied() -> NoReturn:
    os.write(2, PROBE_DENIED_MARKER)
    raise SystemExit(77)


def _probe_failed(error: BaseException) -> NoReturn:
    errno = getattr(error, "errno", None)
    os.write(2, f"PF-SANDBOX-PROBE-FAILED {errno}\n".encode("ascii"))
    raise SystemExit(1)


def _run_probe(arguments: list) -> int:
    """Probe wrapper: map isolation-layer denials to the exact contract."""
    if not arguments:
        return 2
    operation, operands = arguments[0], arguments[1:]
    try:
        if operation == "connect" and len(operands) == 2:
            host, port = operands[0], int(operands[1])
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.settimeout(5.0)
            try:
                client.connect((host, port))
            finally:
                client.close()
            return 0
        if operation == "write-file" and len(operands) == 2:
            with open(operands[0], "a", encoding="utf-8") as handle:
                handle.write(operands[1])
            return 0
        if operation == "read-file" and len(operands) == 1:
            with open(operands[0], "rb") as handle:
                handle.read()
            return 0
        if operation == "listen-connect" and len(operands) == 1:
            port = int(operands[0])
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", port))
            server.listen(1)
            client = socket.create_connection(("127.0.0.1", port), timeout=5)
            conn, _ = server.accept()
            client.sendall(b"ok")
            assert conn.recv(2) == b"ok"
            client.close()
            conn.close()
            server.close()
            sys.stdout.write("loopback-ok\n")
            return 0
        if operation == "flood-stdout":
            sys.stdout.write("x" * (5 * 1024 * 1024))
            sys.stdout.flush()
            return 0
        if operation == "sleep-forever":
            time.sleep(3600)
            return 0
        if operation == "read-stdin":
            payload = sys.stdin.buffer.read()
            sys.stdout.write("stdin-eof\n" if payload == b"" else "stdin-bytes\n")
            return 0
        if operation == "list-fds":
            survivors = []
            for entry in os.listdir("/proc/self/fd"):
                if not entry.isdigit():
                    continue
                fd = int(entry)
                if fd <= 2:
                    survivors.append(fd)
                    continue
                try:
                    os.fstat(fd)
                except OSError:
                    continue
                survivors.append(fd)
            sys.stdout.write("fds:" + ",".join(str(fd) for fd in sorted(survivors)) + "\n")
            return 0
        return 2
    except OSError as error:
        denial = (
            _DENIAL_ERRNOS_NETWORK
            if operation in ("connect",)
            else _DENIAL_ERRNOS_FILE
        )
        if error.errno in denial:
            _probe_denied()
        _probe_failed(error)


def main(argv: Optional[list] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args[:1] == ["probe"]:
        if args[1:2] != ["--"]:
            return 2
        return _run_probe(args[2:])
    print("usage: sandbox_bwrap.py probe -- <operation> [args]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
