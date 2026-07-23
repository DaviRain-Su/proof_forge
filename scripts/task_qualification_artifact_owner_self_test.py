"""TST-DOC-001/task-qualification-v1 focused RED: artifact payload owners.

This tests SPEC-TASKQUAL-001 §2/§8.2 and ADR-0021 §2.1 without production
secrets.  It fixes the raw payload digest preimage, the closed role-to-owner
dispatch, independent profile payloadSha256 validation, typed-owner parsing,
and protected identity role coverage.  The first committed run is expected to
fail only because the owner APIs are absent; GREEN must implement the APIs
without weakening any case below.
"""

from __future__ import annotations

import hashlib
import inspect
import sys
from dataclasses import replace
from pathlib import Path

_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent))

import authority_store as _AUTH_STORE
import bootstrap_task_objects as _BTO
import private_scan as _PRIVATE_SCAN
import stage0_handoff as _STAGE0
import task_qualification_objects as _TQO
import task_qualification_protected_adapter as _ADAPTER


RAW_SCHEMA = "proof-forge.task-qualification-artifact-payload.v1"
RAW_DOMAIN = b"pf.taskqual.artifact-payload.v1"
FIXTURE_SCHEMA = "proof-forge.task-qualification-fixture-resolved-blob.v1"

RAW_GATE_PREFIXES = (
    "resolved-tool",
    "resolved-tool-closure",
    "resolved-probe",
    "sandbox-policy",
    "verifier-executable",
    "verifier-closure",
    "verifier-build-policy",
    "private-scan-scanner",
)
RAW_TOP_LEVEL_ROLES = tuple(
    f"{prefix}-{part}"
    for prefix in ("bootstrap-verifier", "protected-consumer")
    for part in ("executable", "closure", "build-policy")
)
RAW_PROTECTED_ROLES = tuple(
    f"{prefix}-{part}"
    for prefix in (
        "authority-store",
        "adapter",
        "snapshot-parser",
        "trusted-clock",
        "store-supervisor",
    )
    for part in ("executable", "closure", "build-policy")
)
TYPED_GATE_OWNER_KINDS = {
    "private-scan-policy/owner-gate": "private-scan-policy-v1",
    "authority-store-service/owner-gate": "authority-store-service-v1",
    "host-observation/owner-gate": "host-observation-v1",
    "host-profile/owner-gate": "host-profile-v1",
}
STRUCTURED_PROTECTED_OWNER_KINDS = {
    "authority-store-service-descriptor": "taskqual-store-descriptor-v2",
    "store-isolation-policy": "taskqual-store-isolation-policy-v2",
}


class Result:
    __slots__ = ("name", "passed", "detail")

    def __init__(self, name: str, passed: bool, detail: str = ""):
        self.name = name
        self.passed = passed
        self.detail = detail

    def __repr__(self) -> str:
        status = "PASS" if self.passed else "RED"
        detail = f" — {self.detail}" if self.detail else ""
        return f"[{status}] {self.name}{detail}"


def _digest(data: bytes) -> _BTO.Digest:
    return _BTO.Digest("sha256", hashlib.sha256(data).digest())


def _manual_raw_ref(identifier: str, version: str, payload: bytes) -> _BTO.ContentRef:
    h = hashlib.sha256()
    h.update(RAW_DOMAIN)
    h.update(b"\x00")
    h.update(identifier.encode("utf-8"))
    h.update(b"\x00")
    h.update(version.encode("utf-8"))
    h.update(b"\x00")
    h.update(payload)
    return _BTO.ContentRef(
        RAW_SCHEMA, identifier, version, _BTO.Digest("sha256", h.digest())
    )


def _raw_ref(identifier: str, version: str, payload: bytes) -> _BTO.ContentRef:
    candidate = getattr(_TQO, "task_qualification_artifact_payload_ref", None)
    if candidate is None:
        raise AssertionError("API-ABSENT: task_qualification_artifact_payload_ref")
    return candidate(identifier, version, payload)


def _owner_kind(role: str) -> str:
    candidate = getattr(_ADAPTER, "_artifact_owner_kind_for_role", None)
    if candidate is None:
        raise AssertionError("API-ABSENT: _artifact_owner_kind_for_role")
    return candidate(role)


def _recompute(role: str, ref: _BTO.ContentRef, payload: bytes) -> _BTO.ContentRef:
    candidate = getattr(_ADAPTER, "_recompute_owned_payload_ref", None)
    if candidate is None:
        raise AssertionError("API-ABSENT: _recompute_owned_payload_ref")
    return candidate(role, ref, payload)


def _validate_mapping(mapping, payload: bytes) -> None:
    candidate = getattr(_ADAPTER, "_validate_profile_artifact_payload", None)
    if candidate is None:
        raise AssertionError("API-ABSENT: _validate_profile_artifact_payload")
    candidate(mapping, payload)


def _expect_rejected(action, where: str) -> None:
    try:
        action()
    except _BTO.Rejected:
        return
    raise AssertionError(f"accepted invalid case: {where}")


def _raw_role_ref(role: str, payload: bytes = b"owner-payload") -> _BTO.ContentRef:
    identifier = "owner-" + role.replace("/", "-")
    return _raw_ref(identifier, "1.0.0", payload)


def test_api_and_domain() -> Result:
    name = "owner.api_and_domain"
    try:
        if getattr(_TQO, "TASKQUAL_ARTIFACT_PAYLOAD_SCHEMA", None) != RAW_SCHEMA:
            raise AssertionError("raw schema constant absent or wrong")
        if getattr(_TQO, "DOMAIN_TASKQUAL_ARTIFACT_PAYLOAD", None) != RAW_DOMAIN:
            raise AssertionError("raw domain constant absent or wrong")
        raw_api = getattr(_TQO, "task_qualification_artifact_payload_ref", None)
        owner_api = getattr(_ADAPTER, "_recompute_owned_payload_ref", None)
        mapping_api = getattr(_ADAPTER, "_validate_profile_artifact_payload", None)
        if None in (raw_api, owner_api, mapping_api):
            raise AssertionError("owner API absent")
        for api, expected in (
            (raw_api, ("identifier", "version", "payload")),
            (owner_api, ("role", "claimed_ref", "payload")),
            (mapping_api, ("mapping", "payload")),
        ):
            parameters = tuple(inspect.signature(api).parameters.values())
            if tuple(p.name for p in parameters) != expected:
                raise AssertionError(f"{api.__name__} parameter drift")
            if any(p.kind is not inspect.Parameter.POSITIONAL_ONLY for p in parameters):
                raise AssertionError(f"{api.__name__} must be positional-only")
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def test_raw_preimage_exact() -> Result:
    name = "owner.raw_preimage_exact"
    try:
        payload = b"\x00raw\xffpayload"
        actual = _raw_ref("owner-preimage-v1", "1.2.3", payload)
        expected = _manual_raw_ref("owner-preimage-v1", "1.2.3", payload)
        if actual != expected:
            raise AssertionError("domain/id/version/payload preimage mismatch")
        if _raw_ref("owner-preimage-v2", "1.2.3", payload).digest == actual.digest:
            raise AssertionError("id is not digest-bound")
        if _raw_ref("owner-preimage-v1", "1.2.4", payload).digest == actual.digest:
            raise AssertionError("version is not digest-bound")
        if _raw_ref("owner-preimage-v1", "1.2.3", payload + b"!").digest == actual.digest:
            raise AssertionError("payload is not digest-bound")
        _expect_rejected(
            lambda: _raw_ref("owner-preimage-v1", "01.2.3", payload),
            "noncanonical SemVer",
        )
        _expect_rejected(lambda: _raw_ref("UPPERCASE", "1.0.0", payload), "bad id")
        _expect_rejected(lambda: _raw_ref("owner-empty", "1.0.0", b""), "empty payload")
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def test_closed_role_dispatch() -> Result:
    name = "owner.closed_role_dispatch"
    try:
        expected = {}
        expected.update({f"{prefix}/owner-gate": "taskqual-artifact-payload-v1" for prefix in RAW_GATE_PREFIXES})
        expected.update({role: "taskqual-artifact-payload-v1" for role in RAW_TOP_LEVEL_ROLES})
        expected.update({role: "taskqual-artifact-payload-v1" for role in RAW_PROTECTED_ROLES})
        expected.update(TYPED_GATE_OWNER_KINDS)
        expected.update(STRUCTURED_PROTECTED_OWNER_KINDS)
        for role, owner in expected.items():
            if _owner_kind(role) != owner:
                raise AssertionError(f"{role} did not dispatch to {owner}")
        for role in (
            "resolved-tool",
            "resolved-tool/",
            "private-scan-policy",
            "adapter-executable/owner-gate",
            "unknown/owner-gate",
            "authority-store-service-descriptor/extra",
        ):
            _expect_rejected(lambda role=role: _owner_kind(role), role)
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def test_all_raw_roles_recompute() -> Result:
    name = "owner.all_raw_roles_recompute"
    try:
        roles = tuple(f"{prefix}/owner-gate" for prefix in RAW_GATE_PREFIXES)
        roles += RAW_TOP_LEVEL_ROLES + RAW_PROTECTED_ROLES
        if len(roles) != 29 or len(set(roles)) != 29:
            raise AssertionError("raw role test closure drift")
        for role in roles:
            payload = b"payload:" + role.encode("ascii")
            ref = _raw_role_ref(role, payload)
            if _recompute(role, ref, payload) != ref:
                raise AssertionError(f"raw ref mismatch for {role}")
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def test_raw_mutations_and_schema_confusion() -> Result:
    name = "owner.raw_mutations_and_schema_confusion"
    try:
        role = "resolved-tool/owner-gate"
        payload = b"immutable-owner-payload"
        ref = _raw_role_ref(role, payload)
        stale_id = replace(ref, id="owner-different-id")
        stale_version = replace(ref, version="1.0.1")
        fixture_ref = replace(ref, schema=FIXTURE_SCHEMA)
        unknown_ref = replace(ref, schema="proof-forge.unknown-owner.v1")
        for label, bad_ref, bad_payload in (
            ("id", stale_id, payload),
            ("version", stale_version, payload),
            ("payload", ref, payload + b"!"),
            ("fixture schema", fixture_ref, payload),
            ("unknown schema", unknown_ref, payload),
        ):
            _expect_rejected(
                lambda bad_ref=bad_ref, bad_payload=bad_payload: _recompute(
                    role, bad_ref, bad_payload
                ),
                label,
            )
        _expect_rejected(
            lambda: _recompute("private-scan-policy/owner-gate", ref, payload),
            "raw schema on typed role",
        )
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def test_plain_sha_is_independent() -> Result:
    name = "owner.plain_sha_is_independent"
    try:
        role = "resolved-probe/owner-gate"
        payload = b"probe-payload"
        ref = _raw_role_ref(role, payload)
        mapping = _TQO.ProductionArtifactMappingV1(role, ref, _digest(payload))
        _validate_mapping(mapping, payload)
        _expect_rejected(
            lambda: _validate_mapping(replace(mapping, payloadSha256=_digest(b"other")), payload),
            "plain checksum mismatch",
        )
        stale_ref = replace(ref, id="owner-probe-different")
        _expect_rejected(
            lambda: _validate_mapping(replace(mapping, artifact=stale_ref), payload),
            "valid plain checksum with stale ContentRef",
        )
        mutated = payload + b"!"
        _expect_rejected(
            lambda: _validate_mapping(
                replace(mapping, payloadSha256=_digest(mutated)), mutated
            ),
            "updated plain checksum with stale ContentRef",
        )
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def _private_scan_vector() -> tuple[bytes, _BTO.ContentRef]:
    obj = {
        "schema": _PRIVATE_SCAN.PRIVATE_SCAN_POLICY_SCHEMA,
        "id": "owner-private-scan-policy-v1",
        "version": "1.0.0",
        "denyContentMarkers": [],
        "denyPathMarkers": [],
        "maximumFindings": 0,
    }
    payload = _BTO.canonical_pf_jcs(obj)
    return payload, _TQO.parse_content_ref(
        _PRIVATE_SCAN.private_scan_policy_ref(payload), "owner.private-scan"
    )


def _authority_store_vector() -> tuple[bytes, _BTO.ContentRef]:
    obj = {
        "schema": _AUTH_STORE.DESCRIPTOR_SCHEMA,
        "id": "owner-authority-store-service-v1",
        "version": "1.0.0",
        "protocol": _AUTH_STORE.PROTOCOL_ID,
        "serviceExecutableDigest": "sha256:" + "00" * 32,
        "servicePublicKey": "11" * 32,
        "namespaceId": "owner-test",
        "maximumFrameBytes": _AUTH_STORE.MAXIMUM_FRAME_BYTES,
    }
    payload = _BTO.canonical_pf_jcs(obj)
    return payload, _AUTH_STORE.descriptor_content_ref(obj)


def _raw_typed_vector(schema: str, identifier: str, payload: bytes) -> _BTO.ContentRef:
    return _BTO.ContentRef(schema, identifier, "1.0.0", _digest(payload))


def test_existing_typed_owner_positive_and_negative() -> Result:
    name = "owner.existing_typed_owner_positive_and_negative"
    try:
        private_payload, private_ref = _private_scan_vector()
        store_payload, store_ref = _authority_store_vector()
        observation_payload = _BTO.canonical_pf_jcs({"eligibleForHermetic": True})
        observation_ref = _raw_typed_vector(
            _STAGE0.HOST_OBSERVATION_SCHEMA,
            "owner-host-observation-v1",
            observation_payload,
        )
        profile_payload = _BTO.canonical_pf_jcs({"profile": "owner-test"})
        profile_ref = _raw_typed_vector(
            _STAGE0.HOST_PROFILE_SCHEMA, "owner-host-profile-v1", profile_payload
        )
        vectors = (
            ("private-scan-policy/owner-gate", private_ref, private_payload),
            ("authority-store-service/owner-gate", store_ref, store_payload),
            ("host-observation/owner-gate", observation_ref, observation_payload),
            ("host-profile/owner-gate", profile_ref, profile_payload),
        )
        for role, ref, payload in vectors:
            if _recompute(role, ref, payload) != ref:
                raise AssertionError(f"typed owner mismatch: {role}")
        noncanonical = b'{ "schema": "proof-forge.private-scan-policy.v1" }'
        _expect_rejected(
            lambda: _recompute(
                "private-scan-policy/owner-gate", private_ref, noncanonical
            ),
            "typed noncanonical payload",
        )
        _expect_rejected(
            lambda: _recompute(
                "private-scan-policy/owner-gate", private_ref, b"not-json"
            ),
            "typed parse failure",
        )
        _expect_rejected(
            lambda: _recompute("resolved-tool/owner-gate", private_ref, private_payload),
            "known typed schema on raw role",
        )
        ineligible = _BTO.canonical_pf_jcs({"eligibleForHermetic": False})
        _expect_rejected(
            lambda: _recompute(
                "host-observation/owner-gate", observation_ref, ineligible
            ),
            "ineligible host observation",
        )
    except Exception as exc:
        return Result(name, False, str(exc))
    return Result(name, True)


def run_all() -> list[Result]:
    tests = (
        test_api_and_domain,
        test_raw_preimage_exact,
        test_closed_role_dispatch,
        test_all_raw_roles_recompute,
        test_raw_mutations_and_schema_confusion,
        test_plain_sha_is_independent,
        test_existing_typed_owner_positive_and_negative,
    )
    results = []
    for test in tests:
        try:
            results.append(test())
        except Exception as exc:
            results.append(Result(test.__name__, False, f"exception: {exc}"))
    return results


def main() -> int:
    results = run_all()
    passed = sum(result.passed for result in results)
    failed = len(results) - passed
    print(f"Artifact owner RED: {passed}/{len(results)} passed, {failed} RED")
    for result in results:
        print(result)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
