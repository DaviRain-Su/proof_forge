#!/usr/bin/env python3
"""Eligible-kernel tests for ADR-0021 U/P/A namespace isolation.

The static driver creates the exact two-entry mapped user namespace U, parent
PID namespace P, unique adapter child namespace A, distinct mount namespaces,
a detached readonly empty root, and per-PID-namespace detached procfs roots.
It also executes the adapter as an ordinary static ELF before direct parent
inspection. This remains development infrastructure: it does not open seeds,
reserve a durable nonce, install seccomp, or run the production service.
"""

from __future__ import annotations

import argparse
import errno
import os
import platform
import pwd
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_CUSTODY_MASK = (1 << 8) | (1 << 19)
_NEGATIVE_MODES = (
    "--map-mismatch",
    "--outside-reuse",
    "--inside-order",
    "--reserved-id",
    "--prepare-adapter-repeat",
    "--peer-invalid-pid",
    "--adapter-without-a",
    "--adapter-identity-substitution",
    "--release-no-cloexec",
)


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _subordinate_values(
    path: Path,
    username: str,
    wanted: int,
    excluded: set[int],
) -> list[int]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise AssertionError(f"cannot read {path}: {exc}") from exc
    accepted_names = {username, str(os.getuid())}
    result: list[int] = []
    for line in lines:
        fields = line.split(":")
        if len(fields) != 3 or fields[0] not in accepted_names:
            continue
        try:
            start = int(fields[1], 10)
            count = int(fields[2], 10)
        except ValueError as exc:
            raise AssertionError(f"malformed subordinate range in {path}") from exc
        if start < 0 or count <= 0:
            raise AssertionError(f"invalid subordinate range in {path}")
        for value in range(start, start + count):
            if value in excluded or value in result:
                continue
            result.append(value)
            if len(result) == wanted:
                return result
    raise AssertionError(f"{path} lacks {wanted} distinct subordinate IDs")


def _eligible_mapping_ids() -> tuple[int, int, int, int]:
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise AssertionError("namespace matrix requires Linux x86_64")
    for helper in (Path("/usr/bin/newuidmap"), Path("/usr/bin/newgidmap")):
        metadata = helper.stat()
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or
                not metadata.st_mode & stat.S_ISUID):
            raise AssertionError(f"mapping helper is not setuid-root regular: {helper}")
    username = pwd.getpwuid(os.getuid()).pw_name
    uid_values = _subordinate_values(Path("/etc/subuid"), username, 2, set())
    gid_values = _subordinate_values(
        Path("/etc/subgid"), username, 2, set(uid_values),
    )
    values = tuple(uid_values + gid_values)
    if len(values) != 4 or len(set(values)) != 4:
        raise AssertionError("four host subordinate IDs are not distinct")
    return values  # type: ignore[return-value]


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-static", "-no-pie", "-O2"]
    )
    completed = subprocess.run(
        [
            "/usr/bin/cc", *flags, "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-I", str(_HERE), "-o", str(binary),
            str(_HERE / "task_qualification_namespace_v2_driver.c"),
            str(_HERE / "task_qualification_namespace_v2.c"),
            str(_HERE / "task_qualification_kernel_transition_v2.c"),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout:
        raise AssertionError(
            f"namespace {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("namespace driver is not an ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence returned errno {exc.errno}"
            ) from exc
    else:
        raise AssertionError("namespace driver unexpectedly has security.capability")
    completed = subprocess.run(
        ["/usr/bin/readelf", "-W", "-l", "-d", str(binary)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or completed.stderr:
        raise AssertionError(f"namespace ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("namespace driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    completed = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-fanalyzer", "-fsyntax-only", "-I", str(_HERE),
            str(_HERE / "task_qualification_namespace_v2_driver.c"),
            str(_HERE / "task_qualification_namespace_v2.c"),
            str(_HERE / "task_qualification_kernel_transition_v2.c"),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"namespace static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke(
    binary: Path,
    mode: str,
    setup: Path,
    sentinel: Path,
    ids: tuple[int, int, int, int],
    *,
    sanitizer: bool = False,
) -> subprocess.CompletedProcess[str]:
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=0:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    return subprocess.run(
        [str(binary), mode, str(setup), str(sentinel),
         *(str(value) for value in ids)],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )


def _fresh_setup(parent: Path, name: str) -> tuple[Path, Path]:
    setup = parent / name
    setup.mkdir(mode=0o755)
    sentinel = setup / "host-sentinel"
    sentinel.write_bytes(b"must-not-be-visible-after-chroot\n")
    return setup, sentinel


def _parse_positive(stdout: str) -> None:
    rows: dict[str, dict[str, str]] = {}
    for line in stdout.splitlines():
        if not line.startswith("PF-NS "):
            raise AssertionError(f"unexpected positive output: {line!r}")
        tokens = line.split(" ")
        if (len(tokens) not in {8, 9} or
                tokens[1] not in {"adapter", "service"} or
                (tokens[1] == "adapter" and len(tokens) != 8) or
                (tokens[1] == "service" and len(tokens) != 9)):
            raise AssertionError(f"malformed namespace checkpoint: {line!r}")
        fields: dict[str, str] = {}
        for token in tokens[2:]:
            if token.count("=") != 1:
                raise AssertionError("malformed namespace checkpoint field")
            key, value = token.split("=", 1)
            if key in fields:
                raise AssertionError("duplicate namespace checkpoint field")
            fields[key] = value
        rows[tokens[1]] = fields
    if set(rows) != {"adapter", "service"}:
        raise AssertionError("namespace checkpoint role set mismatch")
    adapter = rows["adapter"]
    service = rows["service"]
    expected_adapter = {
        "pid": "1", "procCount": "1", "capEff": "0000000000000000",
    }
    expected_service = {
        "pid": "1", "adapterPid": "2", "procCount": "2",
        "capEff": f"{_CUSTODY_MASK:016x}",
    }
    if any(adapter.get(key) != value for key, value in expected_adapter.items()):
        raise AssertionError(f"adapter scalar checkpoint mismatch: {adapter}")
    if any(service.get(key) != value for key, value in expected_service.items()):
        raise AssertionError(f"service scalar checkpoint mismatch: {service}")
    if set(adapter) != {"pid", "procCount", "capEff", "user", "pidns", "mnt"}:
        raise AssertionError("adapter checkpoint field manifest mismatch")
    if set(service) != {
        "pid", "adapterPid", "procCount", "capEff", "user", "pidns", "mnt",
    }:
        raise AssertionError("service checkpoint field manifest mismatch")
    if adapter["user"] != service["user"]:
        raise AssertionError("adapter and service are not in common U")
    if adapter["pidns"] == service["pidns"]:
        raise AssertionError("adapter A equals service P")
    if adapter["mnt"] == service["mnt"]:
        raise AssertionError("adapter and service mount namespaces are equal")
    for role in (adapter, service):
        for key in ("user", "pidns", "mnt"):
            parts = role[key].split(":")
            if len(parts) != 2 or any(int(part, 10) <= 0 for part in parts):
                raise AssertionError("namespace identity is not positive dev:ino")


def _positive(binary: Path, base: Path, ids: tuple[int, int, int, int]) -> None:
    setup, sentinel = _fresh_setup(base, "positive")
    completed = _invoke(binary, "--positive", setup, sentinel, ids)
    if completed.returncode != 0 or completed.stderr:
        raise AssertionError(
            f"positive rc={completed.returncode} stderr={completed.stderr!r}"
        )
    _parse_positive(completed.stdout)


def _negative(
    binary: Path,
    base: Path,
    ids: tuple[int, int, int, int],
    mode: str,
) -> None:
    setup, sentinel = _fresh_setup(base, mode.removeprefix("--"))
    completed = _invoke(binary, mode, setup, sentinel, ids)
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"{mode} rc={completed.returncode} stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _not_pid_one(binary: Path, base: Path) -> None:
    setup, _ = _fresh_setup(base, "not-pid-one")
    completed = subprocess.run(
        [str(binary), "--not-pid-one", str(setup)],
        cwd=binary.parent,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"not-pid-one rc={completed.returncode} "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _sanitizer_invalid_input(binary: Path, base: Path) -> None:
    setup, _ = _fresh_setup(base, "sanitizer-not-pid-one")
    environment = {
        "PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC",
        "ASAN_OPTIONS": "detect_leaks=0:symbolize=0:halt_on_error=1:abort_on_error=1",
        "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
    }
    completed = subprocess.run(
        [str(binary), "--not-pid-one", str(setup)],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"sanitizer invalid input rc={completed.returncode} "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _source_contract() -> None:
    source = (_HERE / "task_qualification_namespace_v2.c").read_text(
        encoding="utf-8"
    )
    driver = (_HERE / "task_qualification_namespace_v2_driver.c").read_text(
        encoding="utf-8"
    )
    required = (
        "SYS_fsopen", "SYS_fsconfig", "SYS_fsmount", "SYS_mount_setattr",
        "MOUNT_ATTR_RDONLY", "chroot(\".\")", "unshare(CLONE_NEWNS)",
        "unshare(CLONE_NEWPID)", "self/ns/pid_for_children",
    )
    if any(token not in source for token in required):
        raise AssertionError("namespace detached-root/proc source contract drift")
    forbidden = (
        "pivot_root", "move_mount", "open_tree", "F_DUPFD", "dup(",
        "PR_SET_DUMPABLE", "hidepid", "ptrace_scope",
    )
    if any(token in source or token in driver for token in forbidden):
        raise AssertionError("namespace source contains path/fd/dumpable fallback")
    ordered = (
        "pf_tq_namespace_enter_adapter_v2(",
        "pf_tq_kernel_isolate_adapter_v2(",
        "SYS_execveat",
    )
    adapter_start = driver.index("static int pf_tq_ns_adapter_positive(")
    adapter_end = driver.index("static int pf_tq_ns_adapter_child(")
    adapter = driver[adapter_start:adapter_end]
    offsets = [adapter.index(token) for token in ordered]
    if offsets != sorted(offsets) or any(adapter.count(token) != 1 for token in ordered):
        raise AssertionError("adapter namespace/credential/exec ordering drift")
    service_start = driver.index("static int pf_tq_ns_service_positive(")
    service_end = driver.index("static void pf_tq_ns_service_negative(")
    service = driver[service_start:service_end]
    ordered = ("pf_tq_namespace_peer_v2(", "pf_tq_kernel_prepare_custody_v2(")
    offsets = [service.index(token) for token in ordered]
    if offsets != sorted(offsets) or any(service.count(token) != 1 for token in ordered):
        raise AssertionError("post-exec peer-before-service-transition ordering drift")


def _case(name: str, operation) -> Result:
    try:
        operation()
    except Exception as exc:
        return Result(name, False, f"{type(exc).__name__}: {exc}")
    return Result(name, True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    try:
        ids = _eligible_mapping_ids()
    except Exception as exc:
        print(f"task-qualification namespace-v2 self-test: HOST-PRECHECK-FAIL: {exc}")
        return 1
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-namespace-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-namespace-v2-test"
        sanitizer_binary = base / "pf-taskqualification-namespace-v2-sanitizer"
        try:
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
        except Exception as exc:
            print(f"task-qualification namespace-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1
        results = [_case("positive-U-P-A-static-exec", lambda: _positive(
            binary, base, ids,
        ))]
        for mode in _NEGATIVE_MODES:
            results.append(_case(
                mode.removeprefix("--"),
                lambda mode=mode: _negative(binary, base, ids, mode),
            ))
        results.extend([
            _case("not-pid-one", lambda: _not_pid_one(binary, base)),
            _case("source-contract", _source_contract),
            _case(
                "asan-ubsan-invalid-input",
                lambda: _sanitizer_invalid_input(sanitizer_binary, base),
            ),
        ])
    passed = sum(result.passed for result in results)
    print(f"task-qualification namespace-v2 self-test: {passed}/{len(results)} passed")
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
