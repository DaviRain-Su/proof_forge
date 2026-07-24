#!/usr/bin/env python3
"""Development matrix for the BootstrapAuthorityPolicyV1 static C owner."""

from __future__ import annotations

import argparse
import copy
import errno
import hashlib
import json
import os
import platform
import random
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import bootstrap_task_objects as _BTO


_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
_POLICY_PATH = _ROOT / "docs/governance/bootstrap-closure/TASK-D0-04/authority-policy.json"
_DOMAIN = b"pf.bootstrap-authority-policy.v1"


@dataclass(frozen=True)
class Vector:
    name: str
    payload: bytes
    accepted: bool
    expected_version: str = "1.0.0"
    driver_mode: str | None = None


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


def _mutated(base: dict[str, Any], mutate: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    mutate(result)
    return result


def _vector(
    name: str,
    value: dict[str, Any] | bytes,
    accepted: bool,
    *,
    expected_version: str = "1.0.0",
    driver_mode: str | None = None,
) -> Vector:
    return Vector(
        name,
        value if isinstance(value, bytes) else _canonical(value),
        accepted,
        expected_version,
        driver_mode,
    )


def _build_vectors(base: dict[str, Any], canonical: bytes) -> list[Vector]:
    semver = _mutated(base, lambda item: item.__setitem__(
        "version", "1.2.3-rc.1+build.01"))
    strengthened = _mutated(base, lambda item: item["requiredTestSetRule"].update({
        "requiredRoles": ["architecture", "quality", "security"],
        "minimumDistinctSigners": 3,
    }))
    duplicate_principal_id = _mutated(
        base, lambda item: item["principals"][2].__setitem__(
            "principalId", "principal-quality"))
    rotated_key = _mutated(
        base, lambda item: item["principals"][0].__setitem__(
            "publicKey",
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"))
    vectors = [
        _vector("baseline-current-policy", canonical, True),
        _vector("canonical-semver-positive", semver, True,
                expected_version="1.2.3-rc.1+build.01"),
        _vector("valid-strengthened-rule", strengthened, True),
        _vector("valid-duplicate-principal-id-satisfiable", duplicate_principal_id, True),
        _vector("valid-principal-key-rotation", rotated_key, True),
        _vector("claimed-ref-digest", canonical, False,
                driver_mode="--claimed-ref-reject"),
        _vector("expected-ref-shape", canonical, False,
                driver_mode="--expectation-shape-reject"),
        _vector("canonical-whitespace", canonical.replace(
            b'{"authorityStoreService"', b'{ "authorityStoreService"', 1), False),
        _vector("canonical-escape", canonical.replace(
            b'"bootstrap-authority-root"', b'"bootstrap-authority-\\u0072oot"', 1), False),
        _vector("root-not-object", b"[]", False),
        _vector("unknown-root-field", _mutated(
            base, lambda item: item.__setitem__("unknown", 1)), False),
        _vector("missing-root-field", _mutated(
            base, lambda item: item.pop("formalCatalogRule")), False),
        _vector("schema", _mutated(
            base, lambda item: item.__setitem__(
                "schema", "proof-forge.bootstrap-authority-policy.v2")), False),
        _vector("id-grammar", _mutated(
            base, lambda item: item.__setitem__("id", "Bootstrap-Authority")), False),
        _vector("id-expected-ref", _mutated(
            base, lambda item: item.__setitem__("id", "bootstrap-authority-other")), False),
        _vector("version-leading-zero", _mutated(
            base, lambda item: item.__setitem__("version", "01.0.0")), False),
    ]

    principal_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("principals-not-array", lambda item: item.__setitem__("principals", {})),
        ("principals-empty", lambda item: item.__setitem__("principals", [])),
        ("principal-not-object", lambda item: item["principals"].__setitem__(0, [])),
        ("principal-extra-field", lambda item: item["principals"][0].__setitem__("current", True)),
        ("principal-missing-field", lambda item: item["principals"][0].pop("roles")),
        ("principal-id-grammar", lambda item: item["principals"][0].__setitem__("principalId", "/bad")),
        ("principal-key-grammar", lambda item: item["principals"][0].__setitem__("keyId", "bad/key")),
        ("principal-key-order", lambda item: item["principals"].reverse()),
        ("principal-key-duplicate", lambda item: item["principals"][1].__setitem__("keyId", "key-architecture")),
        ("principal-public-duplicate", lambda item: item["principals"][1].__setitem__(
            "publicKey", item["principals"][0]["publicKey"])),
        ("principal-public-short", lambda item: item["principals"][0].__setitem__("publicKey", "00" * 31)),
        ("principal-public-uppercase", lambda item: item["principals"][0].__setitem__("publicKey", "AA" * 32)),
        ("principal-public-zero", lambda item: item["principals"][0].__setitem__("publicKey", "00" * 32)),
        ("principal-public-identity", lambda item: item["principals"][0].__setitem__("publicKey", "01" + "00" * 31)),
        ("principal-public-mixed-order", lambda item: item["principals"][0].__setitem__("publicKey", "95" + "99" * 31)),
        ("principal-public-noncanonical", lambda item: item["principals"][0].__setitem__("publicKey", "ff" * 32)),
        ("principal-roles-not-array", lambda item: item["principals"][0].__setitem__("roles", "architecture")),
        ("principal-roles-empty", lambda item: item["principals"][0].__setitem__("roles", [])),
        ("principal-roles-order", lambda item: item["principals"][0].__setitem__("roles", ["release", "architecture"])),
        ("principal-roles-duplicate", lambda item: item["principals"][0].__setitem__("roles", ["architecture", "architecture"])),
        ("principal-roles-unknown", lambda item: item["principals"][0].__setitem__("roles", ["operator"])),
        ("release-role-uncovered", lambda item: item["principals"][2].__setitem__("roles", ["quality"])),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in principal_mutations)
    overflow = _mutated(base, lambda item: item.__setitem__(
        "principals", [copy.deepcopy(item["principals"][0]) for _ in range(257)]))
    vectors.append(_vector("principals-count-overflow", overflow, False))

    task_rule_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("task-rules-not-array", lambda item: item.__setitem__("taskRules", {})),
        ("task-rules-count", lambda item: item["taskRules"].pop()),
        ("task-rules-order", lambda item: item["taskRules"].reverse()),
        ("task-rule-id", lambda item: item["taskRules"][0].__setitem__("taskId", "TASK-D0-02")),
        ("task-rule-extra", lambda item: item["taskRules"][0].__setitem__("id", "x")),
        ("task-rule-not-object", lambda item: item["taskRules"][0].__setitem__("rule", [])),
        ("rule-extra", lambda item: item["taskRules"][0]["rule"].__setitem__("kind", "quorum")),
        ("rule-minimum-bool", lambda item: item["taskRules"][0]["rule"].__setitem__("minimumDistinctSigners", True)),
        ("rule-minimum-zero", lambda item: item["taskRules"][0]["rule"].__setitem__("minimumDistinctSigners", 0)),
        ("rule-minimum-u32-overflow", lambda item: item["taskRules"][0]["rule"].__setitem__("minimumDistinctSigners", 2**32)),
        ("rule-roles-empty", lambda item: item["taskRules"][0]["rule"].__setitem__("requiredRoles", [])),
        ("task-rule-weaken-role", lambda item: item["taskRules"][0]["rule"].__setitem__("requiredRoles", ["quality"])),
        ("task-rule-weaken-minimum", lambda item: item["taskRules"][3]["rule"].__setitem__("minimumDistinctSigners", 2)),
        ("task-rule-unsatisfiable-minimum", lambda item: item["taskRules"][3]["rule"].__setitem__("minimumDistinctSigners", 5)),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in task_rule_mutations)

    named_rule_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("required-test-rule-role", lambda item: item["requiredTestSetRule"].__setitem__("requiredRoles", ["quality"])),
        ("formal-catalog-rule-minimum", lambda item: item["formalCatalogRule"].__setitem__("minimumDistinctSigners", 1)),
        ("bootstrap-set-rule-role", lambda item: item["bootstrapSetRule"].__setitem__("requiredRoles", ["quality", "security"])),
        ("session-rule-role", lambda item: item["sessionContainmentRule"].__setitem__("requiredRoles", ["quality"])),
        ("freshness-rule-role", lambda item: item["freshnessAuthorityRule"].__setitem__("requiredRoles", ["quality"])),
        ("private-scan-rule-role", lambda item: item["privateScanRule"].__setitem__("requiredRoles", ["quality"])),
        ("revocation-rule-role", lambda item: item["revocationSnapshotRule"].__setitem__("requiredRoles", ["security"])),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in named_rule_mutations)

    ref_verifier_mutations: list[tuple[str, Callable[[dict[str, Any]], None]]] = [
        ("private-scan-ref-extra", lambda item: item["privateScanPolicy"].__setitem__("size", 1)),
        ("private-scan-ref-digest", lambda item: item["privateScanPolicy"].__setitem__("digest", "sha256:" + "AA" * 32)),
        ("private-scan-document-id", lambda item: item["privateScanPolicy"].__setitem__("id", "GOV-PRIVATE-SCAN")),
        ("authority-store-document-id", lambda item: item["authorityStoreService"].__setitem__("id", "GOV-AUTHORITY-STORE")),
        ("authority-store-schema", lambda item: item["authorityStoreService"].__setitem__(
            "schema", "proof-forge.task-qualification-authority-store-service.v2")),
        ("verifier-not-object", lambda item: item.__setitem__("verifier", [])),
        ("verifier-extra", lambda item: item["verifier"].__setitem__("algorithm", "ed25519")),
        ("verifier-id", lambda item: item["verifier"].__setitem__("id", "/bad")),
        ("verifier-executable-digest", lambda item: item["verifier"].__setitem__("executableDigest", "sha512:" + "00" * 32)),
        ("verifier-receipt-key-id", lambda item: item["verifier"].__setitem__("receiptKeyId", "bad/key")),
        ("verifier-receipt-public-zero", lambda item: item["verifier"].__setitem__("receiptPublicKey", "00" * 32)),
        ("verifier-key-id-collision", lambda item: item["verifier"].__setitem__("receiptKeyId", "key-security")),
        ("verifier-public-key-collision", lambda item: item["verifier"].__setitem__(
            "receiptPublicKey", item["principals"][3]["publicKey"])),
    ]
    vectors.extend(_vector(name, _mutated(base, mutate), False)
                   for name, mutate in ref_verifier_mutations)

    # Differentially exercise compressed-point canonical/subgroup behavior.
    # Most arbitrary encodings are rejected; the fixed seed also yields valid
    # prime-subgroup points, so both outcomes are covered without host RNG.
    generator = random.Random(0xA0172101)
    for index in range(64):
        public_key = bytes(generator.getrandbits(8) for _ in range(32)).hex()
        candidate = _mutated(
            base, lambda item, key=public_key: item["principals"][0].__setitem__(
                "publicKey", key))
        payload = _canonical(candidate)
        try:
            _BTO.parse_bootstrap_authority_policy(payload)
            accepted = True
        except Exception:
            accepted = False
        vectors.append(_vector(
            f"public-key-differential-{index:02d}", payload, accepted))
    return vectors


def _check_python_oracle(vectors: list[Vector]) -> None:
    external_ref_only = {
        "claimed-ref-digest", "expected-ref-shape", "id-expected-ref"
    }
    mismatches: list[str] = []
    for vector in vectors:
        try:
            _BTO.parse_bootstrap_authority_policy(vector.payload)
            accepted = True
        except Exception:
            accepted = False
        expected = vector.accepted or vector.name in external_ref_only
        if accepted != expected:
            mismatches.append(
                f"{vector.name}: python={accepted} expected={expected}")
    if mismatches:
        raise AssertionError(
            "authority policy vector/oracle disagreement: " + "; ".join(mismatches))


def _full_digest(payload: bytes) -> str:
    return hashlib.sha256(_DOMAIN + b"\x00" + payload).hexdigest()


def _compile(binary: Path, *, sanitizer: bool) -> None:
    flags = (
        ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        if sanitizer else ["-O2", "-static", "-no-pie"]
    )
    sources = [
        _HERE / "task_qualification_authority_policy_v2_driver.c",
        _HERE / "task_qualification_authority_policy_v2.c",
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
            f"authority policy {'sanitizer' if sanitizer else 'static'} compile failed: "
            f"stdout={completed.stdout!r} stderr={completed.stderr!r}")


def _inspect_static(binary: Path) -> None:
    metadata = binary.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
            metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise AssertionError("authority policy driver is not ordinary single-link ELF")
    try:
        os.getxattr(binary, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise AssertionError(f"security.capability absence errno={exc.errno}") from exc
    else:
        raise AssertionError("authority policy driver unexpectedly has security.capability")
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
        raise AssertionError(f"authority policy ELF inspection failed: {completed.stderr!r}")
    if any("INTERP" in line or "(NEEDED)" in line
           for line in completed.stdout.splitlines()):
        raise AssertionError("authority policy driver contains PT_INTERP or DT_NEEDED")


def _analyze_sources() -> None:
    sources = [
        _HERE / "task_qualification_authority_policy_v2_driver.c",
        _HERE / "task_qualification_authority_policy_v2.c",
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
            f"authority policy static analysis failed: stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}")


def _invoke(
    binary: Path,
    vector: Vector,
    payload_path: Path,
    *,
    sanitizer: bool,
) -> subprocess.CompletedProcess[str]:
    payload_path.write_bytes(vector.payload)
    mode = vector.driver_mode or ("--validate" if vector.accepted else "--reject")
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
    if sanitizer:
        environment.update({
            "ASAN_OPTIONS": "detect_leaks=1:symbolize=0:halt_on_error=1:abort_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=0",
        })
    return subprocess.run(
        [str(binary), mode, str(payload_path), _full_digest(vector.payload),
         vector.expected_version],
        cwd=binary.parent,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )


def _matrix(binary: Path, base: Path, vectors: list[Vector], *, sanitizer: bool) -> list[Result]:
    payload = base / ("authority-policy-asan.json" if sanitizer else "authority-policy.json")
    results: list[Result] = []
    for vector in vectors:
        completed = _invoke(binary, vector, payload, sanitizer=sanitizer)
        passed = completed.returncode == 0 and not completed.stdout and not completed.stderr
        detail = "" if passed else (
            f"exit={completed.returncode} stdout={completed.stdout!r} stderr={completed.stderr!r}")
        results.append(Result(("asan-" if sanitizer else "") + vector.name, passed, detail))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        print("task-qualification authority-policy self-test: requires Linux x86_64")
        return 1
    canonical = _POLICY_PATH.read_bytes()
    base = json.loads(canonical)
    if _canonical(base) != canonical:
        print("[FAIL] committed authority policy is not canonical PF-JCS")
        return 1
    if _full_digest(canonical) != (
            "f02f603904e2cee2198afa5474a9ba667ebba541b73306f1f3c3dcffa7ebb0e1"):
        print("[FAIL] committed activated authority policy domain digest drift")
        return 1
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-authority-policy-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        work = Path(temporary)
        binary = work / "pf-taskqualification-authority-policy-v2-test"
        sanitizer_binary = work / "pf-taskqualification-authority-policy-v2-asan"
        try:
            vectors = _build_vectors(base, canonical)
            _check_python_oracle(vectors)
            _compile(binary, sanitizer=False)
            _inspect_static(binary)
            _compile(sanitizer_binary, sanitizer=True)
            _analyze_sources()
            results = _matrix(binary, work, vectors, sanitizer=False)
            results.extend(_matrix(
                sanitizer_binary, work, vectors, sanitizer=True))
            invalid = subprocess.run(
                [str(binary), "--invalid-input"],
                cwd=work,
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
            print(f"[FAIL] authority policy matrix setup — {exc}")
            return 1
    failures = [result for result in results if not result.passed]
    for result in failures:
        print(result)
    print(
        f"task-qualification authority-policy self-test: "
        f"{len(results) - len(failures)}/{len(results)}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
