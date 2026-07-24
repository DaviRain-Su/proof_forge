#!/usr/bin/env python3
"""Development matrix for the ADR-0021 raw artifact payload C owner."""

from __future__ import annotations

import argparse
import errno
import hashlib
import os
import platform
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_SCHEMA = "proof-forge.task-qualification-artifact-payload.v1"
_DOMAIN = b"pf.taskqual.artifact-payload.v1"
_MAX_BYTES = 64 * 1024 * 1024


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool
    mutation: str = "none"
    identifier: str = "adapter-executable-v2"
    version: str = "1.0.0"
    ref_payload: bytes | None = None


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _ref_digest(identifier: str, version: str, payload: bytes) -> str:
    return hashlib.sha256(
        _DOMAIN + b"\0" + identifier.encode("ascii") + b"\0" +
        version.encode("ascii") + b"\0" + payload
    ).hexdigest()


def _vectors() -> tuple[Vector, ...]:
    baseline = b"\x7fELF\x02proof-forge-static-payload\x00\xff"
    return (
        Vector("baseline", baseline, True),
        Vector("binary-nul-high-byte", bytes(range(256)), True),
        Vector("one-byte", b"x", True),
        Vector("alternate-id-semver", b"policy-bytes", True,
               identifier="adapter-build-policy-v2",
               version="2.3.4-rc.1+build.7"),
        Vector("payload-stale-ref", baseline + b"!", False,
               ref_payload=baseline),
        Vector("empty", b"", False),
        Vector("overbound", b"", False, mutation="overbound"),
        Vector("hardlink", baseline, False, mutation="hardlink"),
        Vector("setid-mode", baseline, False, mutation="setid-mode"),
        Vector("read-write-fd", baseline, False, mutation="read-write-fd"),
        Vector("no-cloexec-fd", baseline, False, mutation="no-cloexec-fd"),
        Vector("expected-flags-zero", baseline, False,
               mutation="expected-flags-zero"),
        Vector("schema", baseline, False, mutation="schema"),
        Vector("id", baseline, False, mutation="id"),
        Vector("version", baseline, False, mutation="version"),
        Vector("digest", baseline, False, mutation="digest"),
        Vector("nonregular", b"", False, mutation="nonregular"),
    )


def _sources() -> list[Path]:
    return [
        _HERE / "task_qualification_artifact_payload_v2_driver.c",
        _HERE / "task_qualification_artifact_payload_v2.c",
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
            f"artifact payload {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("artifact payload driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence errno={exc.errno}"
            ) from exc
    else:
        raise AssertionError("artifact payload driver has security.capability")
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
        raise AssertionError(f"artifact payload ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("artifact payload driver contains PT_INTERP/DT_NEEDED")


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
            f"artifact payload static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _path_for(base: Path, vector: Vector) -> Path:
    if vector.mutation == "nonregular":
        return Path("/dev/null")
    path = base / f"{vector.name}.payload"
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


def _invoke(
    binary: Path,
    base: Path,
    vector: Vector,
    *,
    sanitizer: bool,
) -> Result:
    vector_base = base / ("asan-vectors" if sanitizer else "static-vectors")
    vector_base.mkdir(exist_ok=True)
    path = _path_for(vector_base, vector)
    ref_payload = vector.payload if vector.ref_payload is None else vector.ref_payload
    ref_digest = _ref_digest(vector.identifier, vector.version, ref_payload)
    plain_digest = hashlib.sha256(vector.payload).hexdigest()
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": (
                "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1"
            ),
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    completed = subprocess.run(
        [
            str(binary), "--accept" if vector.accepted else "--reject",
            vector.mutation, str(path), vector.identifier, vector.version,
            ref_digest, plain_digest,
        ],
        cwd=base,
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
        print("task-qualification artifact-payload self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-artifact-payload-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-artifact-payload-v2-test"
        sanitizer_binary = base / "pf-taskqualification-artifact-payload-v2-asan"
        try:
            vectors = _vectors()
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
            print(f"task-qualification artifact-payload self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(
        f"task-qualification artifact-payload self-test: {passed}/{len(results)} passed"
    )
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
