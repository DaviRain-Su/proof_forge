#!/usr/bin/env python3
"""Development matrix for pre-exec raw identity payload FD consumption."""

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
_DOMAIN = b"pf.taskqual.artifact-payload.v1"
_BUILD_ID = "adapter-build-policy-v2"
_CLOSURE_ID = "adapter-closure-v2"
_SERVICE_ID = "authority-store-executable-v2"
_VERSION = "1.0.0"
_BUILD_PAYLOAD = b'{"adapter-build-policy":"pinned"}\x00\xff'
_CLOSURE_PAYLOAD = bytes(range(256))
_SERVICE_PAYLOAD = b"\x7fELF\x02proof-forge-static-service-payload\x00\x80\xff"


@dataclass(frozen=True)
class Vector:
    name: str
    accepted: bool
    mutation: str = "none"


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _ref_digest(identifier: str, payload: bytes) -> str:
    return hashlib.sha256(
        _DOMAIN + b"\0" + identifier.encode("ascii") + b"\0" +
        _VERSION.encode("ascii") + b"\0" + payload
    ).hexdigest()


def _vectors() -> tuple[Vector, ...]:
    return (
        Vector("baseline", True),
        Vector("build-stale-ref", False, "build-stale-ref"),
        Vector("closure-stale-ref", False, "closure-stale-ref"),
        Vector("service-stale-ref", False, "service-stale-ref"),
        Vector("service-schema", False, "service-schema"),
        Vector("closure-version", False, "closure-version"),
        Vector("build-id", False, "build-id"),
        Vector("service-no-cloexec", False, "service-no-cloexec"),
        Vector("closure-cloexec", False, "closure-cloexec"),
        Vector("build-readwrite", False, "build-readwrite"),
        Vector("manifest-fd", False, "manifest-fd"),
        Vector("descriptor-ref", False, "descriptor-ref"),
        Vector("isolation-ref", False, "isolation-ref"),
        Vector("tuple", False, "tuple"),
        Vector("descriptor-uid", False, "descriptor-uid"),
        Vector("user-namespace", False, "user-namespace"),
        Vector("seed-root", False, "seed-root"),
        Vector("canonical", False, "canonical"),
    )


def _sources() -> list[Path]:
    return [
        _HERE / "task_qualification_pre_exec_payloads_v2_driver.c",
        _HERE / "task_qualification_pre_exec_payloads_v2.c",
        _HERE / "task_qualification_artifact_payload_v2.c",
        _HERE / "task_qualification_fd_manifest_v2.c",
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
            f"pre-exec payload {'sanitizer' if sanitizer else 'static'} compile "
            f"failed: stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("pre-exec payload driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(
                f"security.capability absence errno={exc.errno}"
            ) from exc
    else:
        raise AssertionError("pre-exec payload driver has security.capability")
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
        raise AssertionError(f"pre-exec payload ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("pre-exec payload driver contains PT_INTERP/DT_NEEDED")


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
            f"pre-exec payload static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _write_payloads(base: Path, vector: Vector) -> tuple[Path, Path, Path]:
    vector_base = base / vector.name
    vector_base.mkdir()
    build_path = vector_base / "adapter-build-policy.payload"
    closure_path = vector_base / "adapter-closure.payload"
    service_path = vector_base / "authority-store-executable.payload"
    build_path.write_bytes(_BUILD_PAYLOAD)
    closure_path.write_bytes(_CLOSURE_PAYLOAD)
    service_path.write_bytes(_SERVICE_PAYLOAD)
    os.chmod(build_path, 0o600)
    os.chmod(closure_path, 0o600)
    os.chmod(service_path, 0o700)
    return build_path, closure_path, service_path


def _invoke(binary: Path, base: Path, vector: Vector, *, sanitizer: bool) -> Result:
    run_base = base / ("asan-vectors" if sanitizer else "static-vectors")
    run_base.mkdir(exist_ok=True)
    build_path, closure_path, service_path = _write_payloads(run_base, vector)
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    completed = subprocess.run(
        [
            str(binary), "--accept" if vector.accepted else "--reject",
            vector.mutation, str(build_path), str(closure_path), str(service_path),
            _ref_digest(_BUILD_ID, _BUILD_PAYLOAD),
            _ref_digest(_CLOSURE_ID, _CLOSURE_PAYLOAD),
            _ref_digest(_SERVICE_ID, _SERVICE_PAYLOAD),
            hashlib.sha256(_BUILD_PAYLOAD).hexdigest(),
            hashlib.sha256(_CLOSURE_PAYLOAD).hexdigest(),
            hashlib.sha256(_SERVICE_PAYLOAD).hexdigest(),
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
        print("task-qualification pre-exec-payload self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-pre-exec-payloads-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-pre-exec-payloads-v2-test"
        sanitizer_binary = base / "pf-taskqualification-pre-exec-payloads-v2-asan"
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
            print(f"task-qualification pre-exec-payload self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(
        f"task-qualification pre-exec-payload self-test: "
        f"{passed}/{len(results)} passed"
    )
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
