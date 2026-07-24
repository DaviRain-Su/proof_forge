#!/usr/bin/env python3
"""Development matrix for the ADR-0021 v2 service-descriptor C owner."""

from __future__ import annotations

import argparse
import copy
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
from typing import Any, Callable

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_DOMAIN = b"pf.taskqual.authority-store-service.v2"


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool
    digest_override: str | None = None


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _canonical(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _full_digest(payload: bytes) -> str:
    return hashlib.sha256(_DOMAIN + b"\x00" + payload).hexdigest()



def _ref(schema: str, identifier: str, seed: int, version: str = "1.0.0") -> dict[str, str]:
    return {
        "schema": schema,
        "id": identifier,
        "version": version,
        "digest": "sha256:" + (bytes([seed]) * 32).hex(),
    }


def _identity(identifier: str, seed: int) -> dict[str, Any]:
    raw_schema = "proof-forge.task-qualification-artifact-payload.v1"
    return {
        "id": identifier,
        "executable": _ref(raw_schema, f"{identifier}-executable", seed),
        "closure": _ref(raw_schema, f"{identifier}-closure", seed + 1),
        "sourceDigest": "sha256:" + (bytes([seed + 2]) * 32).hex(),
        "buildPolicy": _ref(raw_schema, f"{identifier}-build-policy", seed + 3),
    }


def _baseline() -> dict[str, Any]:
    return {
        "schema": "proof-forge.task-qualification-authority-store-service.v2",
        "id": "task-qualification-store-service-run-descriptor-v2",
        "version": "2.0.0",
        "namespace": "task-qualification-production-v1",
        "protocol": "pf.taskqual.authority-store.rpc.v2",
        "servicePublicKey": (bytes([0x71]) * 32).hex(),
        "verifier": _identity("authority-store-v2", 1),
        "supervisor": _identity("store-supervisor-v2", 10),
        "isolationPolicy": _ref(
            "proof-forge.task-qualification-store-isolation-policy.v2",
            "task-qualification-store-isolation-run-descriptor-v2",
            20,
            "2.0.0",
        ),
        "signingKeyIds": ["arch-key", "quality-key", "security-key"],
        "custodyKind": "one-time-seed-fd-v1",
        "adapterUid": 1001,
        "adapterGid": 1003,
        "serviceUid": 1002,
        "serviceGid": 1004,
        "userNamespace": {"device": 10, "inode": 11},
        "seedRoot": {"device": 20, "inode": 23},
        "peerInspectionProfile": "linux-pidfd-proc-cross-uid-v1",
        "maximumFrameBytes": 4194304,
        "maximumTerminalAcceptances": 1,
    }


def _mutated(base: dict[str, Any], mutate: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    mutate(result)
    return result


def _vector(
    name: str,
    value: dict[str, Any] | bytes,
    accepted: bool,
    digest_override: str | None = None,
) -> Vector:
    return Vector(
        name,
        value if isinstance(value, bytes) else _canonical(value),
        accepted,
        digest_override,
    )


def _build_vectors() -> list[Vector]:
    base = _baseline()
    canonical = _canonical(base)
    vectors = [
        _vector("baseline", base, True),
        _vector("canonical-whitespace", canonical.replace(
            b'{"adapterGid"', b'{ "adapterGid"', 1), False),
        _vector("canonical-escape", canonical.replace(
            b'"one-time-seed-fd-v1"', b'"one-time-seed-fd-v\\u0031"', 1), False),
        _vector("root-not-object", b"[]", False),
        _vector("unknown-root-field", _mutated(
            base, lambda item: item.__setitem__("unknown", 1)), False),
        _vector("missing-root-field", _mutated(
            base, lambda item: item.pop("protocol")), False),
        _vector("claimed-ref-digest", base, False, "00" * 32),
    ]

    root_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("schema", lambda item: item.__setitem__("schema", "proof-forge.task-qualification-authority-store-service.v1")),
        ("id", lambda item: item.__setitem__("id", item["id"] + "-other")),
        ("version", lambda item: item.__setitem__("version", "2.0.1")),
        ("namespace", lambda item: item.__setitem__("namespace", "fixture")),
        ("protocol-v1", lambda item: item.__setitem__("protocol", "pf.taskqual.authority-store.rpc.v1")),
        ("protocol-other", lambda item: item.__setitem__("protocol", "pf.taskqual.authority-store.rpc.v3")),
        ("public-key-short", lambda item: item.__setitem__("servicePublicKey", "00" * 31)),
        ("public-key-uppercase", lambda item: item.__setitem__("servicePublicKey", "A0" * 32)),
        ("public-key-type", lambda item: item.__setitem__("servicePublicKey", 1)),
        ("custody-kind", lambda item: item.__setitem__("custodyKind", "hsm")),
        ("adapter-uid-zero", lambda item: item.__setitem__("adapterUid", 0)),
        ("adapter-uid-overflow", lambda item: item.__setitem__("adapterUid", 65534)),
        ("service-gid-high", lambda item: item.__setitem__("serviceGid", 2**31)),
        ("uid-equal", lambda item: item.__setitem__("serviceUid", 1001)),
        ("gid-equal", lambda item: item.__setitem__("serviceGid", 1003)),
        ("uid-bool", lambda item: item.__setitem__("adapterUid", True)),
        ("user-namespace-field", lambda item: item["userNamespace"].__setitem__("kind", "user")),
        ("seed-root-field", lambda item: item["seedRoot"].pop("inode")),
        ("identity-bool", lambda item: item["userNamespace"].__setitem__("device", True)),
        ("identity-unsafe", lambda item: item["seedRoot"].__setitem__("inode", 2**53)),
        ("peer-profile", lambda item: item.__setitem__("peerInspectionProfile", "same-uid")),
        ("frame-bound", lambda item: item.__setitem__("maximumFrameBytes", 4194303)),
        ("terminal-count", lambda item: item.__setitem__("maximumTerminalAcceptances", 2)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in root_mutations)

    identity_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("verifier-not-object", lambda item: item.__setitem__("verifier", [])),
        ("verifier-extra", lambda item: item["verifier"].__setitem__("schema", "x")),
        ("verifier-missing", lambda item: item["verifier"].pop("closure")),
        ("verifier-id-empty", lambda item: item["verifier"].__setitem__("id", "")),
        ("verifier-id-terminal-separator", lambda item: item["verifier"].__setitem__("id", "bad-")),
        ("verifier-source-digest", lambda item: item["verifier"].__setitem__("sourceDigest", "sha256:" + "A0" * 32)),
        ("supervisor-id", lambda item: item["supervisor"].__setitem__("id", "/bad")),
        ("content-ref-extra", lambda item: item["verifier"]["executable"].__setitem__("size", 1)),
        ("content-ref-schema", lambda item: item["verifier"]["executable"].__setitem__("schema", "ProofForge.Bad")),
        ("content-ref-wrong-valid-owner", lambda item: item["verifier"]["executable"].__setitem__("schema", "proof-forge.other-payload.v1")),
        ("content-ref-id", lambda item: item["verifier"]["closure"].__setitem__("id", "Bad_id")),
        ("content-ref-version-leading-zero", lambda item: item["verifier"]["closure"].__setitem__("version", "01.0.0")),
        ("content-ref-version-prerelease-leading-zero", lambda item: item["verifier"]["closure"].__setitem__("version", "1.0.0-01")),
        ("content-ref-version-empty-build", lambda item: item["verifier"]["closure"].__setitem__("version", "1.0.0+")),
        ("content-ref-digest-short", lambda item: item["supervisor"]["buildPolicy"].__setitem__("digest", "sha256:" + "00" * 31)),
        ("content-ref-digest-uppercase", lambda item: item["supervisor"]["buildPolicy"].__setitem__("digest", "sha256:" + "A0" * 32)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in identity_mutations)

    # Canonical SemVer prerelease/build forms are accepted by nested ContentRefV1.
    semver_positive = _mutated(base, lambda item: item["verifier"]["closure"].__setitem__(
        "version", "1.2.3-rc.1+build.01"))
    document_ref_positive = _mutated(base, lambda item: item["verifier"]["closure"].__setitem__(
        "id", "ADR-0021"))
    vectors.extend([
        _vector("semver-positive", semver_positive, True),
        _vector("document-content-ref-id", document_ref_positive, True),
    ])

    isolation_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("isolation-ref-schema", lambda item: item["isolationPolicy"].__setitem__("schema", "proof-forge.task-qualification-store-isolation-policy.v1")),
        ("isolation-ref-id", lambda item: item["isolationPolicy"].__setitem__("id", item["isolationPolicy"]["id"] + "-x")),
        ("isolation-ref-version", lambda item: item["isolationPolicy"].__setitem__("version", "2.0.1")),
        ("isolation-ref-digest", lambda item: item["isolationPolicy"].__setitem__("digest", "sha512:" + "00" * 32)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in isolation_mutations)

    signing_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("signing-count-low", lambda item: item["signingKeyIds"].pop()),
        ("signing-count-high", lambda item: item["signingKeyIds"].append("z-key")),
        ("signing-order", lambda item: item["signingKeyIds"].reverse()),
        ("signing-duplicate", lambda item: item["signingKeyIds"].__setitem__(1, "arch-key")),
        ("signing-empty", lambda item: item["signingKeyIds"].__setitem__(1, "")),
        ("signing-unsafe", lambda item: item["signingKeyIds"].__setitem__(1, "bad/role")),
        ("signing-type", lambda item: item["signingKeyIds"].__setitem__(1, 1)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in signing_mutations)
    return vectors


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-O2", "-static", "-no-pie"]
    )
    sources = [
        _HERE / "task_qualification_descriptor_v2_driver.c",
        _HERE / "task_qualification_descriptor_v2.c",
        _HERE / "task_qualification_wire_v2.c",
        _HERE / "task_qualification_pf_jcs_v2.c",
    ]
    completed = subprocess.run(
        [
            "/usr/bin/cc", *flags, "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-I", str(_HERE), "-o", str(binary),
            *(str(source) for source in sources), "-lcrypto", "-ldl", "-pthread",
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
            f"descriptor {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("descriptor driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(f"security.capability absence errno={exc.errno}") from exc
    else:
        raise AssertionError("descriptor driver unexpectedly has security.capability")
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
        raise AssertionError(f"descriptor ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("descriptor driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    sources = [
        _HERE / "task_qualification_descriptor_v2_driver.c",
        _HERE / "task_qualification_descriptor_v2.c",
        _HERE / "task_qualification_wire_v2.c",
        _HERE / "task_qualification_pf_jcs_v2.c",
    ]
    completed = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-fanalyzer", "-fsyntax-only", "-I", str(_HERE),
            *(str(source) for source in sources),
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
            f"descriptor static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )


def _invoke(
    binary: Path,
    vector: Vector,
    payload_path: Path,
    *,
    sanitizer: bool,
) -> subprocess.CompletedProcess[str]:
    payload_path.write_bytes(vector.payload)
    digest = vector.digest_override or _full_digest(vector.payload)
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    return subprocess.run(
        [str(binary), "--validate" if vector.accepted else "--reject",
         str(payload_path), digest],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )


def _matrix(binary: Path, base: Path, vectors: list[Vector], *, sanitizer: bool) -> list[Result]:
    payload = base / ("descriptor-asan.json" if sanitizer else "descriptor.json")
    results: list[Result] = []
    for vector in vectors:
        completed = _invoke(binary, vector, payload, sanitizer=sanitizer)
        passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
        detail = "" if passed else (
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}"
        )
        results.append(Result(("asan-" if sanitizer else "") + vector.name, passed, detail))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification descriptor self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-descriptor-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-descriptor-v2-test"
        sanitizer_binary = base / "pf-taskqualification-descriptor-v2-asan"
        try:
            vectors = _build_vectors()
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = _matrix(binary, base, vectors, sanitizer=False)
            results.extend(_matrix(sanitizer_binary, base, vectors, sanitizer=True))
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
            print(f"task-qualification descriptor self-test: PRECHECK-FAIL: {exc}")
            return 1
    for result in results:
        print(result)
    passed = sum(result.passed for result in results)
    print(f"task-qualification descriptor self-test: {passed}/{len(results)} passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
