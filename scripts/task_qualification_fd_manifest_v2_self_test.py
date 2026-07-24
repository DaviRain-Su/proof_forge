#!/usr/bin/env python3
"""Development matrix for the ADR-0021 production FD lifecycle owner.

The matrix freezes the unique 44-row nonstdio manifest, adapter handoff joins,
service pre/post/steady continuity, and exact stdio-inclusive runtime
projections.  It is development evidence only; it does not launch the protected
supervisor or create formal task-qualification evidence.
"""

from __future__ import annotations

import argparse
import errno
import os
import platform
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_CASES = (
    "valid",
    "bind-null",
    "bind-conflict",
    "validate-null-policy",
    "validate-null-channels",
    "manifest-count",
    "row-process",
    "row-stage",
    "row-role",
    "row-close-on-exec",
    "row-stdio-collision",
    "row-stage-duplicate",
    "retained-pre-post-drift",
    "retained-post-steady-drift",
    "transition-drift",
    "service-executable-field",
    "authority-policy-cross-process",
    "adapter-endpoint-alias",
    "channel-mismatch",
    "channel-stdio",
    "channel-duplicate",
    "project-unknown-stage",
    "project-small-capacity",
    "project-null-output",
    "lookup-null-role",
)


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _sources() -> list[Path]:
    return [
        _HERE / "task_qualification_fd_manifest_v2_driver.c",
        _HERE / "task_qualification_fd_manifest_v2.c",
    ]


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-O2", "-static", "-no-pie"]
    )
    completed = subprocess.run(
        [
            "/usr/bin/cc", *flags, "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-I", str(_HERE), "-o", str(binary),
            *(str(source) for source in _sources()),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout:
        raise AssertionError(
            f"FD manifest {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("FD manifest driver is not an ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence errno={exc.errno}"
            ) from exc
    else:
        raise AssertionError("FD manifest driver unexpectedly has security.capability")
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
        raise AssertionError(f"FD manifest ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("FD manifest driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    completed = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-fanalyzer", "-fsyntax-only", "-I", str(_HERE),
            *(str(source) for source in _sources()),
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=False,
    )
    if completed.returncode != 0 or completed.stdout or completed.stderr:
        raise AssertionError(
            f"FD manifest static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke(binary: Path, case: str, *, sanitizer: bool) -> Result:
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": (
                "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1"
            ),
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    completed = subprocess.run(
        [str(binary), case],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    passed = (
        completed.returncode == 0 and
        not completed.stdout and
        not completed.stderr
    )
    detail = "" if passed else (
        f"exit={completed.returncode} stdout={completed.stdout!r} "
        f"stderr={completed.stderr!r}"
    )
    return Result(("asan-" if sanitizer else "") + case, passed, detail)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification FD manifest self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-fd-manifest-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-fd-manifest-v2-test"
        sanitizer_binary = base / "pf-taskqualification-fd-manifest-v2-asan"
        try:
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = [
                _invoke(binary, case, sanitizer=False) for case in _CASES
            ]
            results.extend(
                _invoke(sanitizer_binary, case, sanitizer=True)
                for case in _CASES
            )
        except (AssertionError, OSError, subprocess.SubprocessError) as exc:
            print(f"task-qualification FD manifest self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(
        f"task-qualification FD manifest self-test: {passed}/{len(results)} passed"
    )
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
