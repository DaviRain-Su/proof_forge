#!/usr/bin/env python3
"""Sealed same-PID custody transition record tests.

The static C driver uses real sockets, regular single-link seed files, proc
namespace/start-time facts, fixed descriptor numbers, memfd seals, and exact
canonical bytes. Fixtures remain synthetic and do not establish U/P/A,
seccomp, formal key custody, or qualification evidence.
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent

_MODE_NAMES = (
    "positive-sealed-consume",
    "fixed-fd-next-mismatch",
    "fixed-fd-occupied",
    "service-endpoint-identity",
    "user-namespace-identity",
    "start-time-identity",
    "role-key-order",
    "seed-inode-substitution",
    "seed-cloexec",
    "service-executable-no-cloexec",
    "adapter-endpoint-flags",
    "consume-runtime-start-time",
    "unsealed-transition",
    "partial-seals",
    "executable-payload-digest",
    "supervisor-pid",
    "service-executable-still-open",
    "service-endpoint-replacement",
    "duplicate-endpoint-identity",
    "seed-inode-reuse",
    "malformed-executable-ref",
    "executable-proc-fd-collision",
    "fixed-fd-far-mismatch",
    "fd-role-extra",
    "fd-role-missing",
    "fd-role-flags",
    "fd-role-order",
)


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def compile_driver(binary: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/cc", "-static", "-no-pie", "-O2", "-std=c11",
            "-Wall", "-Wextra", "-Werror", "-Wpedantic", "-I", str(_HERE),
            "-o", str(binary),
            str(_HERE / "task_qualification_custody_transition_v2_driver.c"),
            str(_HERE / "task_qualification_custody_transition_v2.c"),
            str(_HERE / "task_qualification_pf_jcs_v2.c"),
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
        raise AssertionError(f"static custody-transition compile failed: {result.stderr}")
    if result.stdout:
        raise AssertionError("custody-transition compiler wrote stdout")
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
        raise AssertionError(f"custody-transition ELF inspection failed: {elf.stderr}")
    if any("INTERP" in line or "(NEEDED)" in line for line in elf.stdout.splitlines()):
        raise AssertionError("custody-transition ELF contains PT_INTERP or DT_NEEDED")


def run_mode(binary: Path, base: Path, mode: int, name: str) -> Result:
    completed = subprocess.run(
        [str(binary), str(mode)],
        cwd=base,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        return Result(
            name, False,
            f"rc={completed.returncode} stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}",
        )
    leftovers = sorted(path.name for path in base.glob("transition-seed-*") if path.is_file())
    if leftovers:
        return Result(name, False, f"seed fixture cleanup drift: {leftovers}")
    return Result(name, True)


def source_contract() -> Result:
    name = "source-seal-contract"
    try:
        source = (_HERE / "task_qualification_custody_transition_v2.c").read_text(
            encoding="utf-8"
        )
        required = (
            '"pf-tq-custody-transition", MFD_ALLOW_SEALING',
            "F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL",
            "fd != transition_fd",
            "fcntl(fd, F_ADD_SEALS, PF_TQ_TRANSITION_SEALS)",
            "fcntl(fd, F_GET_SEALS)",
            "if (transition_fd >= 0 && close(transition_fd) != 0",
        )
        if any(source.count(token) != 1 for token in required):
            raise AssertionError("memfd fixed-FD/seal/consume source contract drift")
        if "MFD_CLOEXEC" in source or "F_DUPFD" in source or "dup(" in source:
            raise AssertionError("transition source contains CLOEXEC/dup fallback")
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
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-custody-transition-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-custody-transition-v2-test"
        try:
            compile_driver(binary)
            results = [
                run_mode(binary, base, mode, name)
                for mode, name in enumerate(_MODE_NAMES)
            ]
            results.append(source_contract())
        except Exception as exc:
            print(f"task-qualification custody-transition-v2 self-test: PRECHECK-FAIL: {exc}")
            return 1
    passed = sum(result.passed for result in results)
    print(f"task-qualification custody-transition-v2 self-test: {passed}/{len(results)} passed")
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
