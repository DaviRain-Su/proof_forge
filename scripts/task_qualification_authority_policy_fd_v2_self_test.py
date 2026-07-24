#!/usr/bin/env python3
"""Development matrix for stable activated authorityPolicyFd consumption."""

from __future__ import annotations

import argparse
import errno
import hashlib
import json
import os
import platform
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_POLICY_PATH = (
    _ROOT / "docs/governance/bootstrap-closure/TASK-D0-04/authority-policy.json"
)
_DOMAIN = b"pf.bootstrap-authority-policy.v1"
_MAX_BYTES = 4 * 1024 * 1024


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool
    mutation: str = "none"
    ref_payload: bytes | None = None


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _vectors(canonical: bytes) -> tuple[Vector, ...]:
    whitespace = canonical.replace(
        b'{"authorityStoreService"', b'{ "authorityStoreService"', 1
    )
    stale = canonical[:-1] + (b" " if canonical[-1:] != b" " else b"\n")
    return (
        Vector("baseline", canonical, True),
        Vector("payload-stale-ref", stale, False, ref_payload=canonical),
        Vector("canonical-whitespace", whitespace, False),
        Vector("empty", b"", False),
        Vector("overbound", b"", False, "overbound"),
        Vector("hardlink", canonical, False, "hardlink"),
        Vector("setid-mode", canonical, False, "setid-mode"),
        Vector("read-write-fd", canonical, False, "read-write-fd"),
        Vector("cloexec-fd", canonical, False, "cloexec-fd"),
        Vector("nonblock-fd", canonical, False, "nonblock-fd"),
        Vector("schema", canonical, False, "schema"),
        Vector("id", canonical, False, "id"),
        Vector("version", canonical, False, "version"),
        Vector("nonregular", b"", False, "nonregular"),
    )


def _full_digest(payload: bytes) -> str:
    return hashlib.sha256(_DOMAIN + b"\0" + payload).hexdigest()


def _sources() -> list[Path]:
    return [
        _HERE / "task_qualification_authority_policy_fd_v2_driver.c",
        _HERE / "task_qualification_authority_policy_fd_v2.c",
        _HERE / "task_qualification_authority_policy_v2.c",
        _HERE / "task_qualification_wire_v2.c",
        _HERE / "task_qualification_pf_jcs_v2.c",
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
            *(str(source) for source in _sources()), "-lcrypto", "-ldl", "-pthread",
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
            f"authority-policy FD {'sanitizer' if sanitizer else 'static'} "
            f"compile failed: stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("authority-policy FD driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence errno={exc.errno}"
            ) from exc
    else:
        raise AssertionError("authority-policy FD driver has security.capability")
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
        raise AssertionError(
            f"authority-policy FD ELF inspection failed: {completed.stderr!r}"
        )
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("authority-policy FD driver contains PT_INTERP/DT_NEEDED")


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
            f"authority-policy FD static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _path_for(base: Path, vector: Vector) -> Path:
    if vector.mutation == "nonregular":
        return Path("/dev/null")
    path = base / f"{vector.name}.json"
    if vector.mutation == "overbound":
        with path.open("wb") as stream:
            stream.truncate(_MAX_BYTES + 1)
    else:
        path.write_bytes(vector.payload)
    os.chmod(path, 0o600)
    if vector.mutation == "hardlink":
        os.link(path, base / f"{vector.name}.second-link")
    if vector.mutation == "setid-mode":
        os.chmod(path, 0o4600)
    return path


def _invoke(binary: Path, base: Path, vector: Vector, *, sanitizer: bool) -> Result:
    run_base = base / ("asan-vectors" if sanitizer else "static-vectors")
    run_base.mkdir(exist_ok=True)
    path = _path_for(run_base, vector)
    ref_payload = vector.payload if vector.ref_payload is None else vector.ref_payload
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    completed = subprocess.run(
        [
            str(binary), "--accept" if vector.accepted else "--reject",
            vector.mutation, str(path), _full_digest(ref_payload),
        ],
        cwd=run_base,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
    detail = "" if passed else (
        f"exit={completed.returncode} stdout={completed.stdout!r} "
        f"stderr={completed.stderr!r}"
    )
    return Result(("asan-" if sanitizer else "") + vector.name, passed, detail)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification authority-policy-FD self-test: requires Linux x86_64")
        return 1
    canonical = _POLICY_PATH.read_bytes()
    if json.dumps(
        json.loads(canonical), sort_keys=True, separators=(",", ":"),
        ensure_ascii=False, allow_nan=False,
    ).encode("utf-8") != canonical:
        print("task-qualification authority-policy-FD self-test: policy not canonical")
        return 1
    if _full_digest(canonical) != (
            "f02f603904e2cee2198afa5474a9ba667ebba541b73306f1f3c3dcffa7ebb0e1"):
        print("task-qualification authority-policy-FD self-test: policy digest drift")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-authority-policy-fd-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-authority-policy-fd-v2-test"
        sanitizer_binary = base / "pf-taskqualification-authority-policy-fd-v2-asan"
        try:
            vectors = _vectors(canonical)
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = [
                _invoke(binary, base, vector, sanitizer=False)
                for vector in vectors
            ]
            results.extend(
                _invoke(sanitizer_binary, base, vector, sanitizer=True)
                for vector in vectors
            )
            invalid = subprocess.run(
                [str(binary), "--invalid-input"],
                cwd=base,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
                check=False,
            )
            results.append(Result(
                "invalid-api-input",
                invalid.returncode == 0 and not invalid.stdout and not invalid.stderr,
                "" if invalid.returncode == 0 else
                f"exit={invalid.returncode} stdout={invalid.stdout!r} stderr={invalid.stderr!r}",
            ))
        except (AssertionError, OSError, subprocess.SubprocessError) as exc:
            print(f"task-qualification authority-policy-FD self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(
        f"task-qualification authority-policy-FD self-test: "
        f"{passed}/{len(results)} passed"
    )
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
