#!/usr/bin/env python3
"""Eligible-kernel tests for ADR-0021 capability/credential transitions.

The static test driver creates a mapped Linux user namespace with four distinct
host subordinate IDs and executes the production transition code. It does not
create the required P/A PID topology, mounts, seed custody, seccomp policy, or a
formal authority service, so these results remain development infrastructure.
"""

from __future__ import annotations

import argparse
import errno
import os
import pwd
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent

_SETPCAP = 1 << 8
_PTRACE = 1 << 19
_CUSTODY = _SETPCAP | _PTRACE

_EXPECTED_TRACE = (
    ("adapter-final", 0, 0, 0, 0, 0, 1001, 1003, 0, 1),
    ("service-pre-exec", _CUSTODY, _CUSTODY, _CUSTODY, _CUSTODY, _CUSTODY,
     1002, 1004, 0, 1),
    ("service-post-exec", _CUSTODY, _CUSTODY, _CUSTODY, _CUSTODY, _CUSTODY,
     1002, 1004, 0, 1),
    ("service-steady", 0, _PTRACE, _PTRACE, 0, 0, 1002, 1004, 0, 1),
    ("service-terminal", 0, 0, 0, 0, 0, 1002, 1004, 0, 1),
)

_MAPPED_NEGATIVES = (
    "--preseed-missing",
    "--preseed-nnp",
    "--adapter-wrong-id",
    "--prepare-nnp-early",
    "--prepare-wrong-id",
    "--terminal-early",
    "--post-no-nnp",
    "--post-wrong-id",
    "--post-old",
    "--terminal-repeat",
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
    path: Path, username: str, wanted: int, excluded: set[int],
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


def eligible_mapping_ids() -> tuple[int, int, int, int]:
    if sys.platform != "linux":
        raise AssertionError("kernel transition matrix requires Linux")
    for helper in (Path("/usr/bin/newuidmap"), Path("/usr/bin/newgidmap")):
        metadata = helper.stat()
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                or not metadata.st_mode & stat.S_ISUID):
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


def compile_driver(binary: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/cc", "-static", "-no-pie", "-O2", "-std=c11",
            "-Wall", "-Wextra", "-Werror", "-Wpedantic", "-I", str(_HERE),
            "-o", str(binary),
            str(_HERE / "task_qualification_kernel_transition_v2_driver.c"),
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
    if result.returncode != 0:
        raise AssertionError(f"static kernel-transition compile failed: {result.stderr}")
    if result.stdout:
        raise AssertionError("kernel-transition compiler wrote stdout")
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1
            or metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("kernel-transition driver is not an ordinary executable")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(f"security.capability absence was errno {exc.errno}")
    else:
        raise AssertionError("kernel-transition driver has security.capability")
    elf = subprocess.run(
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
    if elf.returncode != 0 or elf.stderr:
        raise AssertionError(f"kernel-transition ELF inspection failed: {elf.stderr}")
    if any("INTERP" in line or "(NEEDED)" in line for line in elf.stdout.splitlines()):
        raise AssertionError("kernel-transition ELF contains PT_INTERP or DT_NEEDED")


def _parse_trace(stdout: str) -> tuple[tuple[Any, ...], ...]:
    expected_keys = {
        "label", "bnd", "prm", "eff", "inh", "amb",
        "uid", "gid", "groups", "nnp",
    }
    rows = []
    for line in stdout.splitlines():
        if not line.startswith("PF-KERNEL-CHECKPOINT "):
            raise AssertionError(f"unexpected transition output: {line!r}")
        fields: dict[str, str] = {}
        for token in line[len("PF-KERNEL-CHECKPOINT "):].split(" "):
            if token.count("=") != 1:
                raise AssertionError("malformed checkpoint token")
            key, value = token.split("=", 1)
            if key in fields:
                raise AssertionError("duplicate checkpoint field")
            fields[key] = value
        if set(fields) != expected_keys:
            raise AssertionError("checkpoint field manifest mismatch")
        rows.append((
            fields["label"],
            *(int(fields[key], 16) for key in ("bnd", "prm", "eff", "inh", "amb")),
            *(int(fields[key], 10) for key in ("uid", "gid", "groups", "nnp")),
        ))
    return tuple(rows)


def _invoke(binary: Path, mode: str, ids: tuple[int, ...] = ()) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(binary), mode, *(str(value) for value in ids)],
        cwd=binary.parent,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )


def _case(name: str, invoke) -> Result:
    try:
        invoke()
    except Exception as exc:
        return Result(name, False, f"{type(exc).__name__}: {exc}")
    return Result(name, True)


def source_order_contract() -> None:
    source = (_HERE / "task_qualification_kernel_transition_v2.c").read_text(
        encoding="utf-8"
    )
    post_start = source.index("int pf_tq_kernel_service_post_exec_v2(")
    terminal_start = source.index("int pf_tq_kernel_terminal_lockdown_v2(")
    post = source[post_start:terminal_start]
    ordered = (
        "PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SYS_PTRACE",
        "PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SETPCAP",
        "PR_CAP_AMBIENT_CLEAR_ALL",
        "pf_tq_kernel_capset(0U, PF_TQ_KERNEL_V2_STEADY_MASK",
    )
    offsets = [post.index(token) for token in ordered]
    if offsets != sorted(offsets) or any(post.count(token) != 1 for token in ordered):
        raise AssertionError("post-exec irreversible transition order drift")
    credential = source[source.index("static int pf_tq_kernel_drop_credentials("):post_start]
    order = ("setgroups(0, NULL)", "setresgid(gid, gid, gid)", "setresuid(uid, uid, uid)")
    offsets = [credential.index(token) for token in order]
    if offsets != sorted(offsets) or any(credential.count(token) != 1 for token in order):
        raise AssertionError("credential transition order drift")
    prepare = source[source.index("int pf_tq_kernel_prepare_custody_v2("):source.index(
        "int pf_tq_kernel_custody_no_new_privs_v2("
    )]
    raises = (
        "PR_CAP_AMBIENT_RAISE,\n                PF_TQ_KERNEL_V2_CAP_SETPCAP",
        "PR_CAP_AMBIENT_RAISE,\n                PF_TQ_KERNEL_V2_CAP_SYS_PTRACE",
    )
    offsets = [prepare.index(token) for token in raises]
    if offsets != sorted(offsets) or any(prepare.count(token) != 1 for token in raises):
        raise AssertionError("ambient raise order drift")


def run_cases(binary: Path, ids: tuple[int, int, int, int]) -> list[Result]:
    def positive() -> None:
        completed = _invoke(binary, "--positive", ids)
        if completed.returncode != 0 or completed.stderr:
            raise AssertionError(
                f"positive rc={completed.returncode} stderr={completed.stderr!r}"
            )
        trace = _parse_trace(completed.stdout)
        if trace != _EXPECTED_TRACE:
            raise AssertionError(f"kernel checkpoint trace mismatch: {trace}")

    results = [_case("positive-exec-transition", positive)]
    for mode in _MAPPED_NEGATIVES:
        def negative(mode: str = mode) -> None:
            completed = _invoke(binary, mode, ids)
            if completed.returncode != 0 or completed.stdout or completed.stderr:
                raise AssertionError(
                    f"{mode} rc={completed.returncode} "
                    f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
                )
        results.append(_case(mode.removeprefix("--"), negative))

    def invalid_proc() -> None:
        completed = _invoke(binary, "--invalid-proc-root")
        if completed.returncode != 0 or completed.stdout or completed.stderr:
            raise AssertionError(
                f"invalid proc root rc={completed.returncode}: {completed.stderr!r}"
            )

    results.append(_case("invalid-proc-root", invalid_proc))
    results.append(_case("source-order-contract", source_order_contract))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    try:
        ids = eligible_mapping_ids()
    except Exception as exc:
        print(f"task-qualification kernel-transition-v2 self-test: HOST-PRECHECK-FAIL: {exc}")
        return 1
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-kernel-transition-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        binary = Path(temporary) / "pf-taskqualification-kernel-transition-v2-test"
        try:
            compile_driver(binary)
            results = run_cases(binary, ids)
        except Exception as exc:
            print(f"task-qualification kernel-transition-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1
    passed = sum(result.passed for result in results)
    print(f"task-qualification kernel-transition-v2 self-test: {passed}/{len(results)} passed")
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
