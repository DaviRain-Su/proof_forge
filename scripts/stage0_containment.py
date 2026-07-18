#!/usr/bin/env python3
"""Containment runner for Stage-0-style sandboxed execution (dev slice).

``run_contained`` executes a payload under bubblewrap with a fixed
containment profile:

- ``--unshare-pid --die-with-parent``: the payload runs as PID 1 of a new
  PID namespace bound to the bwrap monitor's lifetime; when the monitor
  exits or is killed (including on timeout), the kernel tears down the
  whole namespace, so ``setsid``/double-fork escapees cannot outlive the
  run (verified on this host).
- ``--unshare-net``: no network interfaces except a down loopback.
- ``--clearenv`` plus an explicit ``--setenv`` whitelist; the bwrap process
  itself runs with a minimal fixed environment.
- stdin is ``/dev/null`` (immediate EOF); stdout/stderr are captured with
  byte caps and any overflow kills the run as a limit failure.
- fd hygiene: the child closes every fd except 0/1/2 and the explicit
  ``inherit_fds`` (subprocess ``close_fds=True, pass_fds=...``), whose
  numbers are preserved across the exec chain into the namespace; this
  module clears any close-on-exec flag on them before spawning.
- resource limits are applied in the pre-exec child via ``setrlimit``.

All failures raise ``Stage0ContainmentError`` with a ``PF-STAGE0-*`` code.
This module performs local process I/O only; it never touches the network,
never persists state, and requires no root.
"""

from __future__ import annotations

import os
import resource
import subprocess
import threading
import time
from dataclasses import dataclass
from fcntl import fcntl, F_GETFD, F_SETFD, FD_CLOEXEC
from typing import NoReturn, Optional, Tuple


class Stage0ContainmentError(Exception):
    """Stable containment failure."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise Stage0ContainmentError(code, detail)


def _containment(detail: str) -> NoReturn:
    _fail("PF-STAGE0-CONTAINMENT", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-STAGE0-IO", detail)


MAX_CAPTURE_BYTES = 256 * 1024 * 1024
_ENV_NAME_RE = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
)
_BWRAP_CANDIDATES = ("/usr/bin/bwrap", "/bin/bwrap")
READ_ONLY_ROOT_BIND = (("--ro-bind", "/", "/"),)


@dataclass(frozen=True)
class ContainmentLimits:
    addressSpaceBytes: Optional[int] = None
    cpuSeconds: Optional[int] = None
    maxOpenFiles: Optional[int] = None
    maxProcesses: Optional[int] = None


@dataclass(frozen=True)
class ContainmentResult:
    exitCode: int
    stdoutBytes: bytes
    stderrBytes: bytes
    wallTimeSeconds: float


def _resolve_bwrap() -> str:
    for candidate in _BWRAP_CANDIDATES:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    _containment("bubblewrap executable is not available")


def _require_positive_int(value: object, where: str) -> int:
    if type(value) is not int or value <= 0:
        _containment(f"{where} must be a positive integer")
    assert isinstance(value, int)
    return value


def run_contained(
    argv: Tuple[str, ...],
    *,
    inherit_fds: Tuple[int, ...] = (),
    env: Tuple[Tuple[str, str], ...] = (),
    bind_rules: Tuple[Tuple[str, ...], ...] = READ_ONLY_ROOT_BIND,
    chdir: str = "/",
    timeout_seconds: float = 10.0,
    stdout_limit_bytes: int = 1024 * 1024,
    stderr_limit_bytes: int = 1024 * 1024,
    limits: Optional[ContainmentLimits] = None,
) -> ContainmentResult:
    """Run ``argv`` inside the fixed containment profile.

    Returns the exit code and capped captures; non-zero exit codes are data,
    not errors.  Timeout, capture overflow, and spawn/setup failures raise
    ``Stage0ContainmentError``.
    """
    if type(argv) is not tuple or not argv:
        _containment("argv must be a non-empty tuple")
    if any(type(arg) is not str or not arg or "\x00" in arg for arg in argv):
        _containment("argv entries must be non-empty NUL-free text")
    if not argv[0].startswith("/"):
        _containment("argv[0] must be an absolute path")
    if type(inherit_fds) is not tuple or any(
        type(fd) is not int or fd <= 2 for fd in inherit_fds
    ):
        _containment("inherit_fds must be a tuple of fds greater than 2")
    if len(set(inherit_fds)) != len(inherit_fds):
        _containment("inherit_fds must be unique")
    if type(env) is not tuple:
        _containment("env must be a tuple of (name, value) pairs")
    for entry in env:
        if (type(entry) is not tuple or len(entry) != 2
                or type(entry[0]) is not str or type(entry[1]) is not str):
            _containment("env entries must be (name, value) text pairs")
        name, value = entry
        if (not name or name[0].isdigit()
                or any(character not in _ENV_NAME_RE for character in name)):
            _containment("env names must be POSIX shell identifiers")
        if "\x00" in value:
            _containment("env values must be NUL-free")
    env_names = [name for name, _ in env]
    if len(set(env_names)) != len(env_names):
        _containment("env names must be unique")
    if type(bind_rules) is not tuple or any(
        type(rule) is not tuple
        or not rule
        or any(type(part) is not str or not part or "\x00" in part
               for part in rule)
        for rule in bind_rules
    ):
        _containment("bind_rules must be tuples of non-empty text")
    if type(chdir) is not str or not chdir.startswith("/"):
        _containment("chdir must be an absolute path")
    if type(timeout_seconds) not in (int, float) or timeout_seconds <= 0:
        _containment("timeout must be a positive number of seconds")
    stdout_cap = _require_positive_int(stdout_limit_bytes, "stdout limit")
    stderr_cap = _require_positive_int(stderr_limit_bytes, "stderr limit")
    if stdout_cap > MAX_CAPTURE_BYTES or stderr_cap > MAX_CAPTURE_BYTES:
        _containment("capture limits exceed the 256 MiB ceiling")
    if limits is not None:
        if type(limits) is not ContainmentLimits:
            _containment("limits must be a ContainmentLimits record")
        for field_value, where in (
            (limits.addressSpaceBytes, "addressSpaceBytes"),
            (limits.cpuSeconds, "cpuSeconds"),
            (limits.maxOpenFiles, "maxOpenFiles"),
            (limits.maxProcesses, "maxProcesses"),
        ):
            if field_value is not None:
                _require_positive_int(field_value, f"limits.{where}")

    bwrap = _resolve_bwrap()
    for fd in inherit_fds:
        try:
            os.fstat(fd)
        except OSError as error:
            _containment(f"inherit fd {fd} is not open: {error}")
        flags = fcntl(fd, F_GETFD)
        if flags & FD_CLOEXEC:
            fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC)

    bwrap_argv = [
        bwrap,
        "--unshare-pid",
        "--die-with-parent",
        "--unshare-net",
        "--clearenv",
    ]
    for name, value in env:
        bwrap_argv.extend(("--setenv", name, value))
    for rule in bind_rules:
        bwrap_argv.extend(rule)
    bwrap_argv.extend(("--chdir", chdir, "--"))
    bwrap_argv.extend(argv)

    def apply_limits() -> None:
        if limits is None:
            return
        if limits.addressSpaceBytes is not None:
            resource.setrlimit(
                resource.RLIMIT_AS,
                (limits.addressSpaceBytes, limits.addressSpaceBytes),
            )
        if limits.cpuSeconds is not None:
            resource.setrlimit(
                resource.RLIMIT_CPU,
                (limits.cpuSeconds, limits.cpuSeconds),
            )
        if limits.maxOpenFiles is not None:
            resource.setrlimit(
                resource.RLIMIT_NOFILE,
                (limits.maxOpenFiles, limits.maxOpenFiles),
            )
        if limits.maxProcesses is not None:
            resource.setrlimit(
                resource.RLIMIT_NPROC,
                (limits.maxProcesses, limits.maxProcesses),
            )

    started = time.monotonic()
    try:
        proc = subprocess.Popen(
            bwrap_argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
            close_fds=True,
            pass_fds=inherit_fds,
            start_new_session=True,
            preexec_fn=apply_limits if limits is not None else None,
        )
    except OSError as error:
        _io(f"cannot spawn the containment monitor: {error}")

    overflow = {"stdout": False, "stderr": False}
    overflow_event = threading.Event()

    def pump(stream_fd: int, cap: int, bucket: list, which: str) -> None:
        total = 0
        while True:
            try:
                chunk = os.read(stream_fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            bucket.append(chunk)
            total += len(chunk)
            if total > cap:
                overflow[which] = True
                overflow_event.set()
                break

    stdout_chunks: list = []
    stderr_chunks: list = []
    assert proc.stdout is not None and proc.stderr is not None
    threads = (
        threading.Thread(
            target=pump,
            args=(proc.stdout.fileno(), stdout_cap, stdout_chunks, "stdout"),
            daemon=True,
        ),
        threading.Thread(
            target=pump,
            args=(proc.stderr.fileno(), stderr_cap, stderr_chunks, "stderr"),
            daemon=True,
        ),
    )
    for thread in threads:
        thread.start()
    deadline = started + timeout_seconds
    while True:
        if overflow_event.is_set():
            proc.kill()
            proc.wait()
            for thread in threads:
                thread.join(timeout=2.0)
            _fail(
                "PF-STAGE0-LIMIT",
                "contained run exceeded a capture byte limit",
            )
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            proc.kill()
            proc.wait()
            for thread in threads:
                thread.join(timeout=2.0)
            _fail(
                "PF-STAGE0-TIMEOUT",
                "contained run exceeded the wall-clock timeout",
            )
        try:
            exit_code = proc.wait(timeout=min(remaining, 0.05))
            break
        except subprocess.TimeoutExpired:
            continue
    for thread in threads:
        thread.join(timeout=2.0)
    wall_time = time.monotonic() - started
    if overflow["stdout"] or overflow["stderr"]:
        proc.kill()
        proc.wait()
        _fail(
            "PF-STAGE0-LIMIT",
            "contained run exceeded a capture byte limit",
        )
    return ContainmentResult(
        exit_code,
        b"".join(stdout_chunks)[:stdout_cap],
        b"".join(stderr_chunks)[:stderr_cap],
        wall_time,
    )
