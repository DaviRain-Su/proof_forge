#!/usr/bin/env python3
"""Development matrix for the protected-handoff static C owner."""

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

import bootstrap_task_producers as _BTP


_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_STATEMENT_DOMAIN = b"pf.taskqual.protected-handoff-statement.v1"
_SIGNATURE_DOMAIN = b"pf.taskqual.protected-handoff-signature.v1"
_FULL_DOMAIN = b"pf.taskqual.protected-handoff.v1"
_SEEDS = {
    "key-architecture": bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"),
    "key-quality": bytes.fromhex(
        "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"),
    "key-release": bytes.fromhex(
        "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"),
    "key-security": bytes.fromhex(
        "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5"),
}
_HANDOFF_KEYS = ("key-architecture", "key-quality", "key-security")


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool


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


def _digest(seed: int) -> str:
    return "sha256:" + (bytes([seed]) * 32).hex()


def _ref(schema: str, identifier: str, seed: int, version: str = "1.0.0") -> dict[str, str]:
    return {
        "schema": schema,
        "id": identifier,
        "version": version,
        "digest": _digest(seed),
    }


def _identity(identifier: str, prefix: str, seed: int) -> dict[str, Any]:
    raw_schema = "proof-forge.task-qualification-artifact-payload.v1"
    return {
        "id": identifier,
        "executable": _ref(raw_schema, f"{prefix}-executable", seed),
        "closure": _ref(raw_schema, f"{prefix}-closure", seed + 1),
        "sourceDigest": _digest(seed + 2),
        "buildPolicy": _ref(raw_schema, f"{prefix}-build-policy", seed + 3),
    }


def _unsigned_baseline() -> dict[str, Any]:
    return {
        "schema": "proof-forge.task-qualification-protected-handoff.v1",
        "id": "task-qualification-protected-handoff-run-handoff-v2",
        "version": "1.0.0",
        "taskId": "TASK-D1-01",
        "operation": "task-qualification",
        "runId": "run-handoff-v2",
        "nonce": "nonce-handoff-v2",
        "candidate": {
            "commit": "11" * 20,
            "treeObjectId": "22" * 20,
            "archiveSha256": _digest(0x33),
        },
        "authorityPolicy": _ref(
            "proof-forge.bootstrap-authority-policy.v1",
            "bootstrap-authority-root", 0x40),
        "productionProfilePin": _ref(
            "proof-forge.task-qualification-production-profile-pin.v1",
            "tq-pin-d1-01-tq-00112233445566778899aabbccddeeff0011223344556677",
            0x41),
        "gateSetDigest": _digest(0x42),
        "adapter": _identity("adapter-v2", "adapter", 1),
        "snapshotParser": _identity("snapshot-parser-v2", "snapshot-parser", 11),
        "authorityStoreService": _ref(
            "proof-forge.task-qualification-authority-store-service.v2",
            "task-qualification-store-service-run-handoff-v2", 0x43, "2.0.0"),
        "trustedClockService": _identity("trusted-clock-v2", "trusted-clock", 21),
        "revocationHead": {
            "headSequence": 42,
            "headDigest": _digest(0x44),
        },
        "trustedInstant": "2026-07-25T12:34:56Z",
        "channels": {
            "authorityPolicyFd": 3,
            "authorityStoreFd": 4,
            "candidateArchiveFd": 5,
            "provenanceBundleFd": 6,
            "trustedClockFd": 7,
        },
    }


def _signed(unsigned: dict[str, Any], *, keys: tuple[str, ...] | None = None) -> dict[str, Any]:
    statement = hashlib.sha256(
        _STATEMENT_DOMAIN + b"\x00" + _canonical(unsigned)).digest()
    message = _SIGNATURE_DOMAIN + b"\x00" + statement
    selected = _HANDOFF_KEYS if keys is None else keys
    result = copy.deepcopy(unsigned)
    result["signatures"] = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": _BTP.sign_ed25519(_SEEDS[key_id], message).hex(),
        }
        for key_id in selected
    ]
    return result


def _mutated(base: dict[str, Any], mutate: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    mutate(result)
    return result


def _vector(name: str, value: dict[str, Any] | bytes, accepted: bool) -> Vector:
    return Vector(name, value if isinstance(value, bytes) else _canonical(value), accepted)


def _build_vectors() -> list[Vector]:
    unsigned = _unsigned_baseline()
    base = _signed(unsigned)
    canonical = _canonical(base)
    vectors = [
        _vector("baseline", base, True),
        _vector("valid-extra-release-signer", _signed(
            unsigned, keys=("key-architecture", "key-quality",
                            "key-release", "key-security")), True),
        _vector("canonical-whitespace", canonical.replace(
            b'{"adapter"', b'{ "adapter"', 1), False),
        _vector("canonical-escape", canonical.replace(
            b'"run-handoff-v2"', b'"run-handoff-v\\u0032"', 1), False),
        _vector("root-not-object", b"[]", False),
        _vector("unknown-root-field", _mutated(
            base, lambda item: item.__setitem__("unknown", 1)), False),
        _vector("missing-root-field", _mutated(
            base, lambda item: item.pop("gateSetDigest")), False),
    ]

    root_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("schema", lambda item: item.__setitem__("schema", "proof-forge.task-qualification-protected-handoff.v2")),
        ("id-derived", lambda item: item.__setitem__("id", item["id"] + "-other")),
        ("id-type", lambda item: item.__setitem__("id", 1)),
        ("version", lambda item: item.__setitem__("version", "1.0.1")),
        ("task-id-grammar", lambda item: item.__setitem__("taskId", "task-d1-01")),
        ("task-id-join", lambda item: item.__setitem__("taskId", "TASK-D1-02")),
        ("operation-unknown", lambda item: item.__setitem__("operation", "verify")),
        ("operation-join", lambda item: item.__setitem__("operation", "task-completion")),
        ("run-id-grammar", lambda item: item.__setitem__("runId", "/bad")),
        ("run-id-join", lambda item: item.__setitem__("runId", "run-handoff-other")),
        ("nonce-grammar", lambda item: item.__setitem__("nonce", "bad/nonce")),
        ("nonce-join", lambda item: item.__setitem__("nonce", "nonce-handoff-other")),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in root_mutations)

    candidate_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("candidate-not-object", lambda item: item.__setitem__("candidate", [])),
        ("candidate-extra", lambda item: item["candidate"].__setitem__("digest", _digest(1))),
        ("candidate-missing", lambda item: item["candidate"].pop("treeObjectId")),
        ("candidate-commit-short", lambda item: item["candidate"].__setitem__("commit", "1" * 39)),
        ("candidate-commit-uppercase", lambda item: item["candidate"].__setitem__("commit", "AA" * 20)),
        ("candidate-commit-join", lambda item: item["candidate"].__setitem__("commit", "33" * 20)),
        ("candidate-tree-join", lambda item: item["candidate"].__setitem__("treeObjectId", "44" * 20)),
        ("candidate-archive-format", lambda item: item["candidate"].__setitem__("archiveSha256", "sha256:" + "A0" * 32)),
        ("candidate-archive-join", lambda item: item["candidate"].__setitem__("archiveSha256", _digest(0x34))),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in candidate_mutations)

    ref_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("authority-policy-not-object", lambda item: item.__setitem__("authorityPolicy", [])),
        ("authority-policy-extra", lambda item: item["authorityPolicy"].__setitem__("size", 1)),
        ("authority-policy-schema", lambda item: item["authorityPolicy"].__setitem__("schema", "proof-forge.fixture-policy.v1")),
        ("authority-policy-id", lambda item: item["authorityPolicy"].__setitem__("id", "other-policy")),
        ("authority-policy-version", lambda item: item["authorityPolicy"].__setitem__("version", "1.0.1")),
        ("authority-policy-digest", lambda item: item["authorityPolicy"].__setitem__("digest", _digest(0x45))),
        ("pin-id", lambda item: item["productionProfilePin"].__setitem__("id", "other-pin")),
        ("gate-digest", lambda item: item.__setitem__("gateSetDigest", _digest(0x45))),
        ("store-v1-cross-reject", lambda item: item["authorityStoreService"].__setitem__("schema", "proof-forge.task-qualification-authority-store-service.v1")),
        ("store-id", lambda item: item["authorityStoreService"].__setitem__("id", "task-qualification-store-service-other")),
        ("store-version", lambda item: item["authorityStoreService"].__setitem__("version", "1.0.0")),
        ("store-digest", lambda item: item["authorityStoreService"].__setitem__("digest", _digest(0x46))),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in ref_mutations)

    identity_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("adapter-not-object", lambda item: item.__setitem__("adapter", [])),
        ("adapter-extra", lambda item: item["adapter"].__setitem__("schema", "x")),
        ("adapter-id", lambda item: item["adapter"].__setitem__("id", "other-adapter")),
        ("adapter-raw-owner", lambda item: item["adapter"]["executable"].__setitem__("schema", "proof-forge.other-payload.v1")),
        ("adapter-executable-digest", lambda item: item["adapter"]["executable"].__setitem__("digest", _digest(0x49))),
        ("snapshot-id", lambda item: item["snapshotParser"].__setitem__("id", "other-parser")),
        ("snapshot-source", lambda item: item["snapshotParser"].__setitem__("sourceDigest", _digest(0x4A))),
        ("clock-id", lambda item: item["trustedClockService"].__setitem__("id", "other-clock")),
        ("clock-build-policy", lambda item: item["trustedClockService"]["buildPolicy"].__setitem__("digest", _digest(0x4B))),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in identity_mutations)

    revocation_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("revocation-not-object", lambda item: item.__setitem__("revocationHead", [])),
        ("revocation-extra", lambda item: item["revocationHead"].__setitem__("id", "x")),
        ("revocation-missing", lambda item: item["revocationHead"].pop("headDigest")),
        ("revocation-sequence-bool", lambda item: item["revocationHead"].__setitem__("headSequence", True)),
        ("revocation-sequence-negative", lambda item: item["revocationHead"].__setitem__("headSequence", -1)),
        ("revocation-sequence-unsafe", lambda item: item["revocationHead"].__setitem__("headSequence", 2**53)),
        ("revocation-sequence-join", lambda item: item["revocationHead"].__setitem__("headSequence", 43)),
        ("revocation-digest", lambda item: item["revocationHead"].__setitem__("headDigest", _digest(0x4C))),
        ("trusted-instant-offset", lambda item: item.__setitem__("trustedInstant", "2026-07-25T12:34:56+00:00")),
        ("trusted-instant-fraction", lambda item: item.__setitem__("trustedInstant", "2026-07-25T12:34:56.0Z")),
        ("trusted-instant-invalid-date", lambda item: item.__setitem__("trustedInstant", "2026-02-30T12:34:56Z")),
        ("trusted-instant-join", lambda item: item.__setitem__("trustedInstant", "2026-07-25T12:34:57Z")),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in revocation_mutations)

    channel_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("channels-not-object", lambda item: item.__setitem__("channels", [])),
        ("channels-extra", lambda item: item["channels"].__setitem__("extraFd", 8)),
        ("channels-missing", lambda item: item["channels"].pop("trustedClockFd")),
        ("channel-bool", lambda item: item["channels"].__setitem__("authorityPolicyFd", True)),
        ("channel-negative", lambda item: item["channels"].__setitem__("authorityStoreFd", -1)),
        ("channel-int-overflow", lambda item: item["channels"].__setitem__("candidateArchiveFd", 2**31)),
        ("channel-duplicate", lambda item: item["channels"].__setitem__("trustedClockFd", 3)),
        ("channel-join", lambda item: item["channels"].__setitem__("provenanceBundleFd", 8)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in channel_mutations)

    signature_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("signatures-not-array", lambda item: item.__setitem__("signatures", {})),
        ("signatures-count-low", lambda item: item["signatures"].pop()),
        ("signature-not-object", lambda item: item["signatures"].__setitem__(0, [])),
        ("signature-extra", lambda item: item["signatures"][0].__setitem__("role", "architecture")),
        ("signature-missing", lambda item: item["signatures"][0].pop("algorithm")),
        ("signature-order", lambda item: item["signatures"].reverse()),
        ("signature-duplicate-key", lambda item: item["signatures"][1].__setitem__("keyId", "key-architecture")),
        ("signature-key-grammar", lambda item: item["signatures"][0].__setitem__("keyId", "/bad")),
        ("signature-unknown-key", lambda item: item["signatures"][0].__setitem__("keyId", "key-aaa")),
        ("signature-algorithm", lambda item: item["signatures"][0].__setitem__("algorithm", "ed448")),
        ("signature-short", lambda item: item["signatures"][0].__setitem__("signature", "00" * 63)),
        ("signature-uppercase", lambda item: item["signatures"][0].__setitem__("signature", "AA" * 64)),
        ("signature-corrupt", lambda item: item["signatures"][0].__setitem__("signature", "00" * 64)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in signature_mutations)

    # Valid signatures over a valid but different tuple still fail the explicit
    # candidate-external expectation, rather than being accepted as self-authorizing.
    different_unsigned = _mutated(
        unsigned, lambda item: item.__setitem__("nonce", "nonce-signed-but-wrong"))
    different_unsigned["id"] = "task-qualification-protected-handoff-run-handoff-v2"
    vectors.append(_vector(
        "valid-signatures-wrong-expected-tuple", _signed(different_unsigned), False))
    return vectors


def _domains(payload: bytes) -> tuple[str, str]:
    value = json.loads(payload)
    unsigned = dict(value)
    unsigned.pop("signatures", None)
    statement = hashlib.sha256(
        _STATEMENT_DOMAIN + b"\x00" + _canonical(unsigned)).digest()
    full = hashlib.sha256(_FULL_DOMAIN + b"\x00" + payload).digest()
    return full.hex(), statement.hex()


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-O2", "-static", "-no-pie"]
    )
    sources = [
        _HERE / "task_qualification_handoff_v2_driver.c",
        _HERE / "task_qualification_handoff_v2.c",
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
            f"handoff {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}")


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("handoff driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(f"security.capability absence errno={exc.errno}") from exc
    else:
        raise AssertionError("handoff driver unexpectedly has security.capability")
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
        raise AssertionError(f"handoff ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("handoff driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    sources = [
        _HERE / "task_qualification_handoff_v2_driver.c",
        _HERE / "task_qualification_handoff_v2.c",
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
            f"handoff static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}")


def _invoke(
    binary: Path,
    vector: Vector,
    payload_path: Path,
    *,
    sanitizer: bool,
) -> subprocess.CompletedProcess[str]:
    payload_path.write_bytes(vector.payload)
    try:
        full_digest, statement_digest = _domains(vector.payload)
    except Exception:
        full_digest, statement_digest = "00" * 32, "00" * 32
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    return subprocess.run(
        [str(binary), "--validate" if vector.accepted else "--reject",
         str(payload_path), full_digest, statement_digest],
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
    payload = base / ("handoff-asan.json" if sanitizer else "handoff.json")
    results: list[Result] = []
    for vector in vectors:
        completed = _invoke(binary, vector, payload, sanitizer=sanitizer)
        passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
        detail = "" if passed else (
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}")
        results.append(Result(("asan-" if sanitizer else "") + vector.name, passed, detail))
    return results


def _special_matrix(
    binary: Path,
    base: Path,
    baseline: Vector,
    *,
    sanitizer: bool,
) -> list[Result]:
    modes = (
        "expectation-noncurrent",
        "expectation-duplicate-public-key",
        "expectation-count-low",
        "expectation-owner-v1",
        "descriptor-ref-digest",
        "descriptor-id",
        "descriptor-key-order",
        "descriptor-key-unknown",
        "descriptor-service-key-reuse",
        "descriptor-principal-duplicate",
        "descriptor-role-coverage",
    )
    payload = base / ("handoff-special-asan.json" if sanitizer else "handoff-special.json")
    payload.write_bytes(baseline.payload)
    full_digest, statement_digest = _domains(baseline.payload)
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    results: list[Result] = []
    for mode in modes:
        completed = subprocess.run(
            [str(binary), f"--{mode}", str(payload), full_digest, statement_digest],
            cwd=binary.parent,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            check=False,
        )
        passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
        detail = "" if passed else (
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}")
        results.append(Result(("asan-" if sanitizer else "") + mode, passed, detail))
    return results


def _alternate_signer_result(
    binary: Path,
    base: Path,
    *,
    sanitizer: bool,
) -> Result:
    payload_bytes = _canonical(_signed(
        _unsigned_baseline(),
        keys=("key-architecture", "key-quality", "key-release")))
    payload = base / (
        "handoff-alternate-asan.json" if sanitizer else "handoff-alternate.json")
    payload.write_bytes(payload_bytes)
    full_digest, statement_digest = _domains(payload_bytes)
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    completed = subprocess.run(
        [str(binary), "--alternate-signer-validate", str(payload),
         full_digest, statement_digest],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
    detail = "" if passed else (
        f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}")
    return Result(
        ("asan-" if sanitizer else "") + "alternate-handoff-signer-policy-join",
        passed,
        detail,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification handoff self-test: requires Linux x86_64")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-handoff-v2-", dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        binary = base / "pf-taskqualification-handoff-v2-test"
        sanitizer_binary = base / "pf-taskqualification-handoff-v2-asan"
        try:
            vectors = _build_vectors()
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = _matrix(binary, base, vectors, sanitizer=False)
            results.extend(_matrix(sanitizer_binary, base, vectors, sanitizer=True))
            results.extend(_special_matrix(
                binary, base, vectors[0], sanitizer=False))
            results.extend(_special_matrix(
                sanitizer_binary, base, vectors[0], sanitizer=True))
            results.append(_alternate_signer_result(
                binary, base, sanitizer=False))
            results.append(_alternate_signer_result(
                sanitizer_binary, base, sanitizer=True))
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
        except Exception as exc:
            print(f"[FAIL] handoff matrix setup — {exc}")
            return 1
    failures = [result for result in results if not result.passed]
    for result in failures:
        print(result)
    print(f"task-qualification handoff self-test: {len(results) - len(failures)}/{len(results)}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
