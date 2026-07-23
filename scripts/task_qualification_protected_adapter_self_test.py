"""TST-DOC-001/task-qualification-v1: §8.4 protected adapter tests.

This file owns both:
1. The synthetic test-owned acceptance builder (no production module
   dependency on caller seeds). The old ``build_protected_acceptance``/
   ``ProtectedAdapterInput.signing_seeds`` production capability was deleted
   from the production module per ADR-0021 §1/§7; the synthetic acceptance
   construction now lives entirely in this test file.
2. The v2 acceptance wire helper tests (snapshotParser/D0 nullable/
   provenance digest+roles, exact accepted field manifest, statement digest).
3. The v2 protected API tests (seven POSITIONAL_ONLY, negative rejection,
   no private-key injection, keyword rejection).
4. The synthetic SOCK_SEQPACKET service unit tests covering the full
   hello+fixed lookup+terminal success path and key negatives. These use
   a test-owned synthetic service that never produces production authority.
"""

from __future__ import annotations

import hashlib
import inspect
import os
import socket
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Tuple

# Ensure scripts/ is importable when run from the repo root.
_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent))

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV
import task_qualification_fixture_builder as _TQFB
import task_qualification_protected_adapter as _TQPA
import task_qualification_authority_store_v2 as _STORE_V2


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

class Result:
    __slots__ = ("name", "passed", "detail")

    def __init__(self, name: str, passed: bool, detail: str = ""):
        self.name = name
        self.passed = passed
        self.detail = detail

    def __bool__(self) -> bool:
        return self.passed

    def __repr__(self) -> str:
        status = "[PASS]" if self.passed else "[FAIL]"
        detail = f" {self.detail}" if self.detail else ""
        return f"{status} {self.name}{detail}"


# ---------------------------------------------------------------------------
# Synthetic test-owned acceptance builder (formerly in production module)
#
# This constructs a synthetic ProtectedTaskQualificationAcceptanceV1 for test
# purposes only. It uses synthetic signing seeds and is never
# production-candidate-bound. The production adapter never accepts caller seeds
# (ADR-0021 §1/§7); this builder exists solely to test the v1 acceptance wire
# shape and digest arithmetic without depending on a production signer.
# ---------------------------------------------------------------------------

DOMAIN_PURE_PROJECTION = _TQO.DOMAIN_PURE_PROJECTION
DOMAIN_PROTECTED_ACCEPTANCE = _TQPA.DOMAIN_PROTECTED_ACCEPTANCE
DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT = _TQO.DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT
DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE = _TQO.DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE
PROTECTED_ACCEPTANCE_SCHEMA = _TQPA.PROTECTED_ACCEPTANCE_SCHEMA

SYNTH_SEEDS = {
    "synth-key-architecture": _TQO.RFC8032_VECTOR_SEEDS[1],
    "synth-key-quality": _TQO.RFC8032_VECTOR_SEEDS[2],
    "synth-key-security": _TQO.RFC8032_VECTOR_SEEDS[3],
}

SYNTH_PUBLIC_KEYS = {
    key_id: _BTP.ed25519_public_key_from_seed(seed)
    for key_id, seed in SYNTH_SEEDS.items()
}

SYNTH_PRINCIPALS = {
    "synth-key-architecture": {
        "principalId": "synth-principal-architecture",
        "keyId": "synth-key-architecture",
        "publicKey": SYNTH_PUBLIC_KEYS["synth-key-architecture"].hex(),
        "roles": ["architecture"],
    },
    "synth-key-quality": {
        "principalId": "synth-principal-quality",
        "keyId": "synth-key-quality",
        "publicKey": SYNTH_PUBLIC_KEYS["synth-key-quality"].hex(),
        "roles": ["quality"],
    },
    "synth-key-security": {
        "principalId": "synth-principal-security",
        "keyId": "synth-key-security",
        "publicKey": SYNTH_PUBLIC_KEYS["synth-key-security"].hex(),
        "roles": ["security"],
    },
}


def _build_synth_production_profile(
    authority_policy_ref, adapter,
    task_id="TASK-D1-FIXTURE", operation="task-qualification",
    gate_ids=("fixture-gate-d1-fixture",),
    snapshot_parser=None, artifacts=(),
):
    """Build a synthetic production profile with synthetic signatures.

    Now carries the §8.2 fields: taskId, operation, gateSetDigest,
    snapshotParser, and artifacts. The gateSetDigest is derived from the
    operation and gate_ids; the id is derived from the gateSetDigest.
    """
    if snapshot_parser is None:
        snapshot_parser = _build_synth_adapter()
    gate_set_digest = _TQO.compute_gate_set_digest(operation, gate_ids)
    profile_id = _TQO.derive_production_profile_id(task_id, operation, gate_set_digest)
    unsigned_wire = _TQO.production_profile_to_wire(_TQO.ProductionVerificationProfileV1(
        schema="proof-forge.task-qualification-production-profile.v1",
        id=profile_id,
        version="1.0.0",
        kind="production",
        namespace="task-qualification-production-v1",
        taskId=task_id,
        operation=operation,
        gateSetDigest=gate_set_digest,
        expectedAuthorityPolicy=authority_policy_ref,
        adapter=adapter,
        snapshotParser=snapshot_parser,
        artifacts=artifacts,
        signatures=(),
    ))
    statement_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PRODUCTION_PROFILE_STATEMENT, unsigned_wire)
    message = _TQO.DOMAIN_PRODUCTION_PROFILE_SIGNATURE + b"\x00" + statement_digest.bytes
    sigs = []
    for key_id in sorted(SYNTH_SEEDS):
        sig = _BTP.sign_ed25519(SYNTH_SEEDS[key_id], message)
        sigs.append(_TQO.ApprovalSignatureV1(
            keyId=key_id, algorithm="ed25519", signature=sig))
    sigs.sort(key=lambda s: s.keyId)
    return _TQO.ProductionVerificationProfileV1(
        schema="proof-forge.task-qualification-production-profile.v1",
        id=profile_id,
        version="1.0.0",
        kind="production",
        namespace="task-qualification-production-v1",
        taskId=task_id,
        operation=operation,
        gateSetDigest=gate_set_digest,
        expectedAuthorityPolicy=authority_policy_ref,
        adapter=adapter,
        snapshotParser=snapshot_parser,
        artifacts=artifacts,
        signatures=tuple(sigs),
    )


def _build_synth_production_profile_pin(profile, authority_policy_ref,
                                         expected_snapshot_parser=None):
    """Build a synthetic production profile pin with synthetic signatures.

    Now carries the §8.2 fields: taskId, operation, gateSetDigest,
    expectedSnapshotParser. The pin id is derived from the same gateSetDigest.
    """
    if expected_snapshot_parser is None:
        expected_snapshot_parser = profile.snapshotParser
    profile_ref = _TQO.production_profile_content_ref(profile)
    pin_id = _TQO.derive_production_profile_pin_id(
        profile.taskId, profile.operation, profile.gateSetDigest)
    unsigned_wire = _TQO.production_profile_pin_to_wire(_TQO.ProductionVerificationProfilePinV1(
        schema="proof-forge.task-qualification-production-profile-pin.v1",
        id=pin_id,
        version="1.0.0",
        taskId=profile.taskId,
        operation=profile.operation,
        gateSetDigest=profile.gateSetDigest,
        authorityPolicy=authority_policy_ref,
        namespace="task-qualification-production-v1",
        profile=profile_ref,
        expectedSnapshotParser=expected_snapshot_parser,
        signatures=(),
    ))
    statement_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_STATEMENT, unsigned_wire)
    message = _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_SIGNATURE + b"\x00" + statement_digest.bytes
    sigs = []
    for key_id in sorted(SYNTH_SEEDS):
        sig = _BTP.sign_ed25519(SYNTH_SEEDS[key_id], message)
        sigs.append(_TQO.ApprovalSignatureV1(
            keyId=key_id, algorithm="ed25519", signature=sig))
    sigs.sort(key=lambda s: s.keyId)
    return _TQO.ProductionVerificationProfilePinV1(
        schema="proof-forge.task-qualification-production-profile-pin.v1",
        id=pin_id,
        version="1.0.0",
        taskId=profile.taskId,
        operation=profile.operation,
        gateSetDigest=profile.gateSetDigest,
        authorityPolicy=authority_policy_ref,
        namespace="task-qualification-production-v1",
        profile=profile_ref,
        expectedSnapshotParser=expected_snapshot_parser,
        signatures=tuple(sigs),
    )


def _build_adapter_inputs(operation: str):
    if operation == "task-qualification":
        chain = _TQFB.build_fixture_chain()
        bundle_bytes, subject_bytes = _TQFB.fixture_chain_to_bytes(chain)
        verified = _TQV.verify_task_qualification_v1(bundle_bytes, subject_bytes)
        if isinstance(verified, _BTO.Rejected):
            raise AssertionError(f"fixture chain did not verify: {verified.detail}")
        return verified, bundle_bytes, subject_bytes
    if operation == "task-completion":
        qual_chain = _TQFB.build_fixture_chain()
        receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
        bundle_bytes, subject_bytes = _TQFB.completion_receipt_chain_to_bytes(receipt_chain)
        verified = _TQV.verify_task_completion_receipt_v1(bundle_bytes, subject_bytes)
        if isinstance(verified, _BTO.Rejected):
            raise AssertionError(f"completion chain did not verify: {verified.detail}")
        return verified, bundle_bytes, subject_bytes
    if operation == "d0-10-bootstrap-approval":
        chain = _TQFB.build_d0_10_approval_chain()
        bundle_bytes, subject_bytes = _TQFB.d0_10_approval_chain_to_bytes(chain)
        verified = _TQV.verify_d0_10_bootstrap_v1(bundle_bytes, subject_bytes)
        if isinstance(verified, _BTO.Rejected):
            raise AssertionError(f"d0-10 approval chain did not verify: {verified.detail}")
        return verified, bundle_bytes, subject_bytes
    if operation == "d0-10-bootstrap-receipt":
        approval_chain = _TQFB.build_d0_10_approval_chain()
        receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
        bundle_bytes, subject_bytes = _TQFB.d0_10_receipt_chain_to_bytes(receipt_chain)
        verified = _TQV.verify_d0_10_bootstrap_receipt_v1(bundle_bytes, subject_bytes)
        if isinstance(verified, _BTO.Rejected):
            raise AssertionError(f"d0-10 receipt chain did not verify: {verified.detail}")
        return verified, bundle_bytes, subject_bytes
    raise AssertionError(f"unknown operation: {operation}")


def _build_synth_adapter():
    fake_ref = _TQO.ContentRef(
        schema="proof-forge.task-qualification-fixture-resolved-blob.v1",
        id="synth-adapter-executable",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\x11" * 32),
    )
    return _TQO.VerifierIdentityV1(
        id="synth-protected-adapter-v1",
        executable=fake_ref,
        closure=fake_ref,
        sourceDigest=_BTO.Digest(algorithm="sha256", bytes=b"\x22" * 32),
        buildPolicy=fake_ref,
    )


def _build_synth_provenance_refs():
    clock_ref = _TQO.ContentRef(
        schema="proof-forge.trusted-clock-observation.v1",
        id="synth-trusted-clock-v1",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\xaa" * 32),
    )
    store_ref = _TQO.ContentRef(
        schema="proof-forge.authority-store-attestation.v1",
        id="synth-authority-store-v1",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\xbb" * 32),
    )
    return (clock_ref, store_ref)


def _build_synth_acceptance(operation, task_id, verified, bundle_bytes,
                           subject_bytes, closeout_candidate=None):
    """Build a synthetic v1 acceptance wire (test-owned, synthetic-only).

    This constructs the OLD v1 acceptance wire shape (with provenanceRefs)
    purely for testing the digest/signature arithmetic. It is never
    production-candidate-bound.
    """
    authority_policy_ref = verified.authorityPolicy
    adapter = _build_synth_adapter()
    # Determine gate_ids and artifacts based on operation
    if operation in ("task-qualification", "d0-10-bootstrap-approval"):
        gate_ids = (_TQFB.FIXTURE_GATE_ID,)
        artifact_roles = _TQO.operation_artifact_roles(operation, gate_ids)
        artifacts = tuple(
            _TQO.ProductionArtifactMappingV1(
                role=role,
                artifact=_TQO.ContentRef(
                    schema="proof-forge.task-qualification-fixture-resolved-blob.v1",
                    id=f"synth-artifact-{role}",
                    version="1.0.0",
                    digest=_BTO.Digest(algorithm="sha256",
                                       bytes=hashlib.sha256(role.encode()).digest()),
                ),
                payloadSha256=_BTO.Digest(algorithm="sha256",
                                          bytes=hashlib.sha256(role.encode()).digest()),
            )
            for role in artifact_roles
        )
    else:
        gate_ids = ()
        artifacts = ()
    production_profile = _build_synth_production_profile(
        authority_policy_ref, adapter,
        task_id=verified.taskId, operation=operation,
        gate_ids=gate_ids, artifacts=artifacts,
    )
    production_profile_pin = _build_synth_production_profile_pin(
        production_profile, authority_policy_ref)

    pure_projection = _serialize_pure_projection(verified)
    pure_projection_digest = _TQO.domain_digest(DOMAIN_PURE_PROJECTION, pure_projection)
    bundle_digest = _TQO.plain_sha256_digest(bundle_bytes)
    subject_digest = _TQO.plain_sha256_digest(subject_bytes)
    profile_wire = _TQO.production_profile_to_wire(production_profile)
    production_profile_digest = _TQO.domain_digest(_TQO.DOMAIN_PRODUCTION_PROFILE, profile_wire)
    pin_ref = _TQO.production_profile_pin_content_ref(production_profile_pin)
    provenance_refs_sorted = tuple(sorted(
        _build_synth_provenance_refs(),
        key=lambda r: (r.schema, r.id, r.version, r.digest.bytes.hex())))

    task_suffix = task_id.lower().replace("task-", "")
    protected_id = f"protected-task-qualification-{operation}-{task_suffix}"

    obj = {
        "schema": PROTECTED_ACCEPTANCE_SCHEMA,
        "id": protected_id,
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": operation,
        "pureProjectionDigest": _TQO.digest_to_wire(pure_projection_digest),
        "bundleDigest": _TQO.digest_to_wire(bundle_digest),
        "subjectDigest": _TQO.digest_to_wire(subject_digest),
        "preCloseCandidate": _TQO.candidate_identity_to_wire(
            verified.preCloseCandidate),
        "closeoutCandidate": (
            _TQO.candidate_identity_to_wire(closeout_candidate)
            if closeout_candidate is not None else None),
        "trustedVerificationInstant": "2026-07-21T12:00:00Z",
        "adapter": _TQO.verifier_identity_to_wire(adapter),
        "productionProfileDigest": _TQO.digest_to_wire(production_profile_digest),
        "productionProfilePin": _TQO.content_ref_to_wire(pin_ref),
        "provenanceRefs": [_TQO.content_ref_to_wire(r) for r in provenance_refs_sorted],
        "signatures": [],
    }
    unsigned = dict(obj)
    unsigned["signatures"] = []
    statement_digest = _TQO.domain_digest(
        DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT, unsigned)
    message = DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE + b"\x00" + statement_digest.bytes
    sigs = []
    for key_id in sorted(SYNTH_SEEDS):
        sig = _BTP.sign_ed25519(SYNTH_SEEDS[key_id], message)
        sigs.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": sig.hex(),
        })
    obj["signatures"] = sigs
    return obj, unsigned, message


def _serialize_pure_projection(verified):
    if isinstance(verified, _TQV.VerifiedTaskQualificationV1):
        return _TQO.verified_task_qualification_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedTaskCompletionV1):
        return _TQO.verified_task_completion_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapApprovalV1):
        return _TQO.verified_d0_10_bootstrap_approval_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapCompletionV1):
        return _TQO.verified_d0_10_bootstrap_completion_to_wire(verified)
    raise AssertionError("unknown verified type")


def _make_synth_inputs(operation: str):
    verified, bundle_bytes, subject_bytes = _build_adapter_inputs(operation)
    return verified, bundle_bytes, subject_bytes


# ---------------------------------------------------------------------------
# v1 synthetic acceptance tests (migrated from production module)
# ---------------------------------------------------------------------------

def test_synth_acceptance_schema_and_id() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("task-qualification")
    signed, _, _ = _build_synth_acceptance(
        "task-qualification", "TASK-D1-FIXTURE",
        verified, bundle_bytes, subject_bytes)
    if signed["schema"] != PROTECTED_ACCEPTANCE_SCHEMA:
        return Result("synth.schema_and_id", False, f"schema={signed['schema']}")
    if signed["version"] != "1.0.0":
        return Result("synth.schema_and_id", False, f"version={signed['version']}")
    if signed["authorityClass"] != "production-candidate-bound":
        return Result("synth.schema_and_id", False,
                      f"authorityClass={signed['authorityClass']}")
    if signed["id"] != "protected-task-qualification-task-qualification-d1-fixture":
        return Result("synth.schema_and_id", False, f"id={signed['id']}")
    return Result("synth.schema_and_id", True)


def test_synth_pure_projection_digest_complete() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("task-qualification")
    signed, unsigned, _ = _build_synth_acceptance(
        "task-qualification", "TASK-D1-FIXTURE",
        verified, bundle_bytes, subject_bytes)
    expected_projection = _TQO.verified_task_qualification_to_wire(verified)
    expected_digest = _TQO.domain_digest(DOMAIN_PURE_PROJECTION, expected_projection)
    if signed["pureProjectionDigest"] != _TQO.digest_to_wire(expected_digest):
        return Result("synth.pure_projection_complete", False, "digest mismatch")
    return Result("synth.pure_projection_complete", True)


def test_synth_signatures_match_recomputed() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("task-qualification")
    signed, unsigned, message = _build_synth_acceptance(
        "task-qualification", "TASK-D1-FIXTURE",
        verified, bundle_bytes, subject_bytes)
    sigs = signed["signatures"]
    key_ids = [s["keyId"] for s in sigs]
    if key_ids != sorted(key_ids):
        return Result("synth.signatures_match", False, "not sorted")
    if len(set(key_ids)) != len(key_ids):
        return Result("synth.signatures_match", False, "duplicates")
    if len(sigs) != 3:
        return Result("synth.signatures_match", False, f"expected 3 sigs, got {len(sigs)}")
    for sig in sigs:
        public_key = SYNTH_PUBLIC_KEYS[sig["keyId"]]
        if not _BTO.verify_ed25519(public_key, message, bytes.fromhex(sig["signature"])):
            return Result("synth.signatures_match", False,
                          f"signature for {sig['keyId']} did not verify")
    return Result("synth.signatures_match", True)


def test_synth_bundle_and_subject_digests() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("task-qualification")
    signed, _, _ = _build_synth_acceptance(
        "task-qualification", "TASK-D1-FIXTURE",
        verified, bundle_bytes, subject_bytes)
    expected_bundle = _TQO.plain_sha256_digest(bundle_bytes)
    expected_subject = _TQO.plain_sha256_digest(subject_bytes)
    if signed["bundleDigest"] != _TQO.digest_to_wire(expected_bundle):
        return Result("synth.bundle_subject_digest", False, "bundle digest mismatch")
    if signed["subjectDigest"] != _TQO.digest_to_wire(expected_subject):
        return Result("synth.bundle_subject_digest", False, "subject digest mismatch")
    return Result("synth.bundle_subject_digest", True)


def test_synth_d0_10_approval() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("d0-10-bootstrap-approval")
    signed, _, _ = _build_synth_acceptance(
        "d0-10-bootstrap-approval", "TASK-D0-10",
        verified, bundle_bytes, subject_bytes)
    if signed["operation"] != "d0-10-bootstrap-approval":
        return Result("synth.d0_10_approval", False, f"operation={signed['operation']}")
    if signed["id"] != "protected-task-qualification-d0-10-bootstrap-approval-d0-10":
        return Result("synth.d0_10_approval", False, f"id={signed['id']}")
    expected_projection = _TQO.verified_d0_10_bootstrap_approval_to_wire(verified)
    expected_digest = _TQO.domain_digest(DOMAIN_PURE_PROJECTION, expected_projection)
    if signed["pureProjectionDigest"] != _TQO.digest_to_wire(expected_digest):
        return Result("synth.d0_10_approval", False, "pureProjectionDigest mismatch")
    return Result("synth.d0_10_approval", True)


def test_synth_closeout_optional() -> Result:
    verified, bundle_bytes, subject_bytes = _make_synth_inputs("task-qualification")
    signed, _, _ = _build_synth_acceptance(
        "task-qualification", "TASK-D1-FIXTURE",
        verified, bundle_bytes, subject_bytes)
    if signed["closeoutCandidate"] is not None:
        return Result("synth.closeout_optional", False, "closeoutCandidate not None")
    return Result("synth.closeout_optional", True)


# ---------------------------------------------------------------------------
# v2 acceptance wire helper tests
# ---------------------------------------------------------------------------

def _v2_synthetic_verifier(identifier: str) -> dict:
    fake_ref = {
        "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
        "id": identifier + "-executable",
        "version": "1.0.0",
        "digest": "sha256:" + hashlib.sha256(
            (identifier + "-exec").encode("ascii")).hexdigest(),
    }
    return {
        "id": identifier,
        "executable": fake_ref,
        "closure": fake_ref,
        "sourceDigest": "sha256:" + hashlib.sha256(
            (identifier + "-source").encode("ascii")).hexdigest(),
        "buildPolicy": fake_ref,
    }


def _v2_synthetic_unsigned_acceptance(
    *, operation: str = "task-qualification",
    closeout_candidate: dict | None = None,
    ledger_projection_digest: str | None = None,
    governance_completion_digest: str | None = None,
    provenance_roles: tuple[str, ...] = ("live-handoff",),
) -> dict:
    return {
        "schema": _STORE_V2.ACCEPTANCE_SCHEMA,
        "id": f"protected-task-qualification-{operation}-d0-10",
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": operation,
        "pureProjectionDigest": "sha256:" + hashlib.sha256(b"pure").hexdigest(),
        "bundleDigest": "sha256:" + hashlib.sha256(b"bundle").hexdigest(),
        "subjectDigest": "sha256:" + hashlib.sha256(b"subject").hexdigest(),
        "preCloseCandidate": {
            "commit": "0" * 40,
            "treeObjectId": "1" * 40,
            "archiveSha256": "sha256:" + hashlib.sha256(b"archive").hexdigest(),
        },
        "closeoutCandidate": closeout_candidate,
        "trustedVerificationInstant": "2026-07-23T12:00:00Z",
        "adapter": _v2_synthetic_verifier("test-only-adapter"),
        "snapshotParser": _v2_synthetic_verifier("test-only-snapshot-parser"),
        "productionProfileDigest": "sha256:" + hashlib.sha256(
            b"invalid-profile").hexdigest(),
        "productionProfilePin": {
            "schema": "proof-forge.task-qualification-production-profile-pin.v1",
            "id": "task-qualification-production-profile-v1",
            "version": "1.0.0",
            "digest": "sha256:" + hashlib.sha256(b"pin").hexdigest(),
        },
        "ledgerProjectionDigest": ledger_projection_digest,
        "governanceCompletionDigest": governance_completion_digest,
        "provenanceBundleDigest": "sha256:" + hashlib.sha256(
            b"invalid-provenance").hexdigest(),
        "provenanceRoles": list(provenance_roles),
    }


def test_v2_unsigned_acceptance_field_manifest() -> Result:
    name = "v2.unsigned_field_manifest"
    unsigned = _v2_synthetic_unsigned_acceptance()
    if set(unsigned) != set(_TQPA.V2_UNSIGNED_ACCEPTANCE_FIELDS):
        return Result(name, False, f"field set drift: {set(unsigned)}")
    if "signatures" in unsigned:
        return Result(name, False, "unsigned contains signatures")
    normalized = _TQPA.v2_unsigned_acceptance_to_wire(unsigned)
    if list(normalized) != list(_TQPA.V2_UNSIGNED_ACCEPTANCE_FIELDS):
        return Result(name, False, "helper reordered fields")
    return Result(name, True)


def test_v2_signed_acceptance_field_manifest() -> Result:
    name = "v2.signed_field_manifest"
    unsigned = _v2_synthetic_unsigned_acceptance()
    signed = dict(unsigned)
    signed["signatures"] = []
    if set(signed) != set(_TQPA.V2_SIGNED_ACCEPTANCE_FIELDS):
        return Result(name, False, "signed field set drift")
    normalized = _TQPA.v2_signed_acceptance_to_wire(signed)
    if list(normalized) != list(_TQPA.V2_SIGNED_ACCEPTANCE_FIELDS):
        return Result(name, False, "helper reordered signed fields")
    if list(normalized)[-1] != "signatures":
        return Result(name, False, "signatures not final")
    return Result(name, True)


def test_v2_unsigned_rejects_signatures_field() -> Result:
    name = "v2.unsigned_rejects_signatures"
    unsigned = _v2_synthetic_unsigned_acceptance()
    unsigned["signatures"] = []
    try:
        _TQPA.v2_unsigned_acceptance_to_wire(unsigned)
    except _BTO.Rejected:
        return Result(name, True)
    return Result(name, False, "signatures field was accepted in unsigned")


def test_v2_acceptance_statement_digest_domain() -> Result:
    name = "v2.statement_digest_domain"
    unsigned = _v2_synthetic_unsigned_acceptance()
    actual = _TQPA.v2_acceptance_statement_digest(unsigned)
    expected = _STORE_V2.domain_digest(
        _TQPA.V2_ACCEPTANCE_STATEMENT_DOMAIN, unsigned).bytes
    if actual != expected:
        return Result(name, False, "statement digest domain mismatch")
    manual = hashlib.sha256(
        _TQPA.V2_ACCEPTANCE_STATEMENT_DOMAIN + b"\x00" +
        _TQO.canonical_pf_jcs(unsigned)).digest()
    if actual != manual:
        return Result(name, False, "statement digest arithmetic mismatch")
    return Result(name, True)


def test_v2_d0_nullable_fields() -> Result:
    name = "v2.d0_nullable_fields"
    unsigned = _v2_synthetic_unsigned_acceptance(
        operation="task-qualification",
        closeout_candidate=None,
        ledger_projection_digest=None,
        governance_completion_digest=None,
    )
    try:
        _TQPA.v2_acceptance_statement_digest(unsigned)
    except _BTO.Rejected as r:
        return Result(name, False, f"nullable D0 rejected: {r.detail}")
    unsigned_d0 = _v2_synthetic_unsigned_acceptance(
        operation="d0-10-bootstrap-receipt",
        closeout_candidate={
            "commit": "2" * 40,
            "treeObjectId": "3" * 40,
            "archiveSha256": "sha256:" + hashlib.sha256(b"d0-archive").hexdigest(),
        },
        ledger_projection_digest="sha256:" + hashlib.sha256(b"ledger").hexdigest(),
        governance_completion_digest="sha256:" + hashlib.sha256(
            b"governance").hexdigest(),
    )
    try:
        _TQPA.v2_acceptance_statement_digest(unsigned_d0)
    except _BTO.Rejected as r:
        return Result(name, False, f"non-null D0 rejected: {r.detail}")
    return Result(name, True)


def test_v2_provenance_roles_and_digest() -> Result:
    name = "v2.provenance_roles_digest"
    roles = ("live-handoff", "store-isolation-policy",
             "store-supervisor-executable")
    unsigned = _v2_synthetic_unsigned_acceptance(provenance_roles=roles)
    digest_a = _TQPA.v2_acceptance_statement_digest(unsigned)
    unsigned2 = _v2_synthetic_unsigned_acceptance(
        provenance_roles=("live-handoff",))
    digest_b = _TQPA.v2_acceptance_statement_digest(unsigned2)
    if digest_a == digest_b:
        return Result(name, False, "provenanceRoles not bound by statement")
    unsigned3 = dict(unsigned)
    unsigned3["provenanceBundleDigest"] = "sha256:" + hashlib.sha256(
        b"different-provenance").hexdigest()
    digest_c = _TQPA.v2_acceptance_statement_digest(unsigned3)
    if digest_a == digest_c:
        return Result(name, False,
                       "provenanceBundleDigest not bound by statement")
    unsigned_empty = _v2_synthetic_unsigned_acceptance(provenance_roles=())
    try:
        _TQPA.v2_acceptance_statement_digest(unsigned_empty)
    except _BTO.Rejected:
        return Result(name, True)
    return Result(name, False, "empty provenanceRoles was accepted")


def test_v2_acceptance_full_digest_domain() -> Result:
    name = "v2.full_digest_domain"
    unsigned = _v2_synthetic_unsigned_acceptance()
    signed = dict(unsigned)
    signed["signatures"] = []
    actual = _TQPA.v2_acceptance_full_digest(signed)
    expected = hashlib.sha256(
        _TQPA.V2_ACCEPTANCE_FULL_DOMAIN + b"\x00" +
        _TQO.canonical_pf_jcs(signed)).digest()
    if actual != expected:
        return Result(name, False, "full digest domain mismatch")
    return Result(name, True)


def test_v2_acceptance_content_ref() -> Result:
    name = "v2.content_ref"
    unsigned = _v2_synthetic_unsigned_acceptance()
    signed = dict(unsigned)
    signed["signatures"] = []
    ref = _TQPA.v2_acceptance_content_ref(signed)
    if ref.schema != _TQPA.V2_ACCEPTANCE_SCHEMA:
        return Result(name, False, "content ref schema mismatch")
    expected = _TQPA.v2_acceptance_full_digest(signed)
    if ref.digest.bytes != expected:
        return Result(name, False, "content ref digest mismatch")
    return Result(name, True)


# ---------------------------------------------------------------------------
# v2 protected API tests
# ---------------------------------------------------------------------------

def test_v2_protect_api_seven_positional_only() -> Result:
    name = "v2.protect_api_signature"
    candidate = getattr(_TQPA, "protect_taskqualification_v1", None)
    if not callable(candidate):
        return Result(name, False, "API absent")
    parameters = list(inspect.signature(candidate).parameters.values())
    expected_names = (
        "operationBytes", "handoffBytes", "authorityPolicyFd",
        "authorityStoreFd", "candidateArchiveFd", "provenanceBundleFd",
        "trustedClockFd",
    )
    if tuple(p.name for p in parameters) != expected_names:
        return Result(name, False, "parameter names/order drift")
    if any(p.kind is not inspect.Parameter.POSITIONAL_ONLY for p in parameters):
        return Result(name, False, "not all POSITIONAL_ONLY")
    if any(p.default is not inspect.Parameter.empty for p in parameters):
        return Result(name, False, "has defaults")
    return Result(name, True)


def test_v2_protect_api_rejects_invalid_operation() -> Result:
    name = "v2.protect_rejects_invalid_operation"
    result = _TQPA.protect_taskqualification_v1(
        b"unknown-operation", b"{}", -1, -2, -3, -4, -5)
    if isinstance(result, _BTO.Rejected):
        return Result(name, True)
    return Result(name, False, "invalid operation was not rejected")


def test_v2_protect_api_rejects_noncanonical_handoff() -> Result:
    name = "v2.protect_rejects_noncanonical_handoff"
    result = _TQPA.protect_taskqualification_v1(
        b"task-qualification", b'{ "schema" : "wrong" }', -1, -2, -3, -4, -5)
    if isinstance(result, _BTO.Rejected):
        return Result(name, True)
    return Result(name, False, "noncanonical handoff was not rejected")


def test_v2_protect_api_rejects_duplicate_fds() -> Result:
    name = "v2.protect_rejects_duplicate_fds"
    result = _TQPA.protect_taskqualification_v1(
        b"task-qualification", b"{}", 3, 3, 3, 3, 3)
    if isinstance(result, _BTO.Rejected):
        return Result(name, True)
    return Result(name, False, "duplicate FDs was not rejected")


def test_v2_protect_api_no_private_key_injection() -> Result:
    name = "v2.protect_no_private_key_injection"
    try:
        _TQPA.protect_taskqualification_v1(
            b"task-qualification", b"{}", -1, -2, -3, -4, -5, b"extra-seed")
    except TypeError:
        return Result(name, True)
    except Exception as exc:
        return Result(name, False,
                       f"eighth arg reached body: {type(exc).__name__}")
    return Result(name, False, "eighth argument was accepted")


def test_v2_protect_api_keyword_invocation_rejected() -> Result:
    name = "v2.protect_keyword_rejected"
    try:
        _TQPA.protect_taskqualification_v1(
            operationBytes=b"task-qualification",
            handoffBytes=b"{}",
            authorityPolicyFd=-1,
            authorityStoreFd=-1,
            candidateArchiveFd=-1,
            provenanceBundleFd=-1,
            trustedClockFd=-1)
    except TypeError:
        return Result(name, True)
    except Exception as exc:
        return Result(name, False,
                       f"body ran before keyword rejection: {type(exc).__name__}")
    return Result(name, False, "keyword invocation was accepted")


def test_v2_protect_api_regular_file_store_rejects() -> Result:
    name = "v2.protect_regular_file_store_rejects"
    handles = []
    try:
        for payload in (b"policy", b"store", b"archive", b"provenance", b"clock"):
            h = tempfile.TemporaryFile()
            h.write(payload)
            h.flush()
            h.seek(0)
            handles.append(h)
        fds = [h.fileno() for h in handles]
        result = _TQPA.protect_taskqualification_v1(
            b"task-qualification", b"{}", *fds)
        if isinstance(result, _BTO.Rejected):
            return Result(name, True)
        return Result(name, False, "regular file store was not rejected")
    finally:
        for h in handles:
            h.close()


def test_v2_protect_api_sock_stream_store_rejects() -> Result:
    name = "v2.protect_sock_stream_store_rejects"
    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    handles = []
    try:
        for payload in (b"policy", b"archive", b"provenance", b"clock"):
            h = tempfile.TemporaryFile()
            h.write(payload)
            h.flush()
            h.seek(0)
            handles.append(h)
        result = _TQPA.protect_taskqualification_v1(
            b"task-qualification", b"{}",
            handles[0].fileno(), left.fileno(), handles[1].fileno(),
            handles[2].fileno(), handles[3].fileno())
        if isinstance(result, _BTO.Rejected):
            return Result(name, True)
        return Result(name, False, "SOCK_STREAM store was not rejected")
    finally:
        left.close()
        right.close()
        for h in handles:
            h.close()


# ---------------------------------------------------------------------------
# Synthetic SOCK_SEQPACKET service unit tests (P0-10)
#
# These tests run a test-owned synthetic v2 service over a socketpair that
# responds to hello/lookup/terminal frames. They verify the protocol client
# wire-level functions (framing, echo, signature verification, ContentRef
# recomputation, lookup order, terminal response verification) without any
# production authority. The synthetic service key is distinct from all fixture
# and production keys.
# ---------------------------------------------------------------------------

_SYNTH_SERVICE_SEED = hashlib.sha256(b"pf-v2-synth-service").digest()
_SYNTH_SERVICE_PUBLIC_KEY = _BTP.ed25519_public_key_from_seed(_SYNTH_SERVICE_SEED)
_SYNTH_ROLE_SEEDS = {
    "key-architecture": hashlib.sha256(b"pf-v2-synth-architecture").digest(),
    "key-quality": hashlib.sha256(b"pf-v2-synth-quality").digest(),
    "key-security": hashlib.sha256(b"pf-v2-synth-security").digest(),
}


def _synth_service_sign(frame: dict, domain: bytes) -> str:
    unsigned = dict(frame)
    unsigned.pop("signature", None)
    message = domain + b"\x00" + _TQO.canonical_pf_jcs(unsigned)
    return _BTP.sign_ed25519(_SYNTH_SERVICE_SEED, message).hex()


def _synth_build_server_hello(tpl: _STORE_V2.HandoffTuple) -> bytes:
    frame = {
        "schema": _STORE_V2.SERVER_HELLO_SCHEMA,
        "version": _STORE_V2.VERSION,
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
        "handoffDigest": _TQO.digest_to_wire(
            _BTO.Digest(algorithm="sha256", bytes=tpl.handoffDigest)),
        "headSequence": tpl.headSequence,
        "headDigest": _TQO.digest_to_wire(
            _BTO.Digest(algorithm="sha256", bytes=tpl.headDigest)),
        "status": "ready",
    }
    frame["signature"] = _synth_service_sign(
        frame, _STORE_V2.FRAME_SIGNATURE_DOMAINS[_STORE_V2.SERVER_HELLO_SCHEMA])
    return _TQO.canonical_pf_jcs(frame)


def _synth_build_lookup_response(request_id: int, key: dict, tpl, object_bytes: bytes) -> bytes:
    ref = _STORE_V2.recompute_object_content_ref(key["objectKind"], object_bytes)
    frame = {
        "schema": _STORE_V2.LOOKUP_RESPONSE_SCHEMA,
        "version": _STORE_V2.VERSION,
        "requestId": request_id,
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
        "headSequence": tpl.headSequence,
        "headDigest": _TQO.digest_to_wire(
            _BTO.Digest(algorithm="sha256", bytes=tpl.headDigest)),
        "status": "found",
        "key": key,
        "object": _TQO.content_ref_to_wire(ref),
        "objectBytesHex": object_bytes.hex(),
    }
    frame["signature"] = _synth_service_sign(
        frame, _STORE_V2.FRAME_SIGNATURE_DOMAINS[_STORE_V2.LOOKUP_RESPONSE_SCHEMA])
    return _TQO.canonical_pf_jcs(frame)


def _synth_make_object(object_kind: str, task_id: str, operation: str) -> bytes:
    """Build a minimal valid object for the given kind (synthetic, non-authoritative).

    For VerifierIdentityV1-based kinds (adapter, snapshot-parser,
    trusted-clock-service), builds a valid verifier identity. For the v2
    descriptor, builds a minimal valid descriptor. For authority-policy/pin/
    profile/revocation-snapshot/revocation-record, builds minimal closed
    objects with the correct schema/id/version so ContentRef recomputation
    succeeds. These are synthetic and non-authoritative.
    """
    if object_kind in ("adapter", "snapshot-parser", "trusted-clock-service"):
        fake_ref = {
            "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
            "id": f"synth-{object_kind}",
            "version": "1.0.0",
            "digest": "sha256:" + hashlib.sha256(
                f"synth-{object_kind}".encode()).hexdigest(),
        }
        obj = {
            "id": f"synth-{object_kind}",
            "executable": fake_ref,
            "closure": fake_ref,
            "sourceDigest": "sha256:" + hashlib.sha256(
                f"synth-{object_kind}-src".encode()).hexdigest(),
            "buildPolicy": fake_ref,
        }
        return _TQO.canonical_pf_jcs(obj)
    if object_kind == "authority-store-service":
        fake_ref = {
            "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
            "id": "synth-descriptor",
            "version": "1.0.0",
            "digest": "sha256:" + hashlib.sha256(b"synth-descriptor").hexdigest(),
        }
        verifier = {
            "id": "synth-verifier",
            "executable": fake_ref,
            "closure": fake_ref,
            "sourceDigest": "sha256:" + hashlib.sha256(b"sv").hexdigest(),
            "buildPolicy": fake_ref,
        }
        desc = {
            "schema": _STORE_V2.DESCRIPTOR_SCHEMA,
            "id": "task-qualification-store-service-synth-run",
            "version": "2.0.0",
            "namespace": _STORE_V2.NAMESPACE,
            "protocol": _STORE_V2.PROTOCOL_ID,
            "servicePublicKey": _SYNTH_SERVICE_PUBLIC_KEY.hex(),
            "verifier": verifier,
            "supervisor": verifier,
            "isolationPolicy": fake_ref,
            "signingKeyIds": sorted(_SYNTH_ROLE_SEEDS),
            "custodyKind": "one-time-seed-fd-v1",
            "adapterUid": 1000,
            "adapterGid": 1000,
            "serviceUid": 1001,
            "serviceGid": 1001,
            "userNamespace": {"device": 0, "inode": 0},
            "seedRoot": {"device": 0, "inode": 1},
            "peerInspectionProfile": "linux-pidfd-proc-cross-uid-v1",
            "maximumFrameBytes": _STORE_V2.MAX_FRAME_BYTES,
            "maximumTerminalAcceptances": 1,
        }
        return _TQO.canonical_pf_jcs(desc)
    if object_kind == "authority-policy":
        # Minimal synthetic authority policy — NOT a real BootstrapAuthorityPolicyV1.
        # We build a minimal valid one using the bootstrap_task_objects parser
        # format. For the protocol test, we only need the ContentRef to
        # recompute, which requires the schema/id/version to match.
        # Use the fixture builder's fixture policy as a baseline (it has the
        # right schema for fixture, but we need the production schema).
        # Build a minimal BootstrapAuthorityPolicyV1 wire:
        from task_qualification_fixture_builder import build_fixture_chain
        chain = build_fixture_chain()
        # The fixture policy uses a fixture schema, not the production one.
        # We need to build a production policy. Use the fixture builder's
        # policy and remap the schema. But that won't parse correctly.
        # Instead, just return the fixture policy bytes — the ContentRef
        # recomputation will use the fixture schema, which doesn't match
        # "authority-policy" kind's expected schema. So we need a real
        # production policy.
        # For the protocol test, skip authority-policy by using a simple
        # object with the correct schema:
        obj = {
            "schema": "proof-forge.bootstrap-authority-policy.v1",
            "id": "synth-authority-policy-v1",
            "version": "1.0.0",
            "principals": [],
            "taskRules": [],
            "requiredTestSetRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "formalCatalogRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "bootstrapSetRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "sessionContainmentRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "freshnessAuthorityRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "privateScanRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "privateScanPolicy": {
                "schema": "proof-forge.private-scan-policy.v1",
                "id": "synth-private-scan-policy",
                "version": "1.0.0",
                "digest": "sha256:" + hashlib.sha256(b"psp").hexdigest(),
            },
            "revocationSnapshotRule": {"requiredRoles": [], "minimumDistinctSigners": 0},
            "authorityStoreService": {
                "schema": "proof-forge.task-qualification-authority-store-service.v2",
                "id": "task-qualification-store-service-synth-run",
                "version": "2.0.0",
                "digest": "sha256:" + hashlib.sha256(b"svc").hexdigest(),
            },
            "verifier": {
                "id": "synth-verifier",
                "executableDigest": "sha256:" + hashlib.sha256(b"ve").hexdigest(),
                "receiptKeyId": "synth-receipt-key",
                "receiptPublicKey": "00" * 32,
            },
        }
        return _TQO.canonical_pf_jcs(obj)
    if object_kind == "production-profile-pin":
        obj = {
            "schema": "proof-forge.task-qualification-production-profile-pin.v1",
            "id": "synth-pin-v1",
            "version": "1.0.0",
            "taskId": task_id,
            "operation": operation,
            "gateSetDigest": "sha256:" + hashlib.sha256(b"gs").hexdigest(),
            "authorityPolicy": {
                "schema": "proof-forge.bootstrap-authority-policy.v1",
                "id": "synth-authority-policy-v1",
                "version": "1.0.0",
                "digest": "sha256:" + hashlib.sha256(b"ap").hexdigest(),
            },
            "namespace": _STORE_V2.NAMESPACE,
            "profile": {
                "schema": "proof-forge.task-qualification-production-profile.v1",
                "id": "synth-profile-v1",
                "version": "1.0.0",
                "digest": "sha256:" + hashlib.sha256(b"prof").hexdigest(),
            },
            "expectedSnapshotParser": {
                "id": "synth-snapshot-parser",
                "executable": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-executable",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spe").hexdigest(),
                },
                "closure": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-closure",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spc").hexdigest(),
                },
                "sourceDigest": "sha256:" + hashlib.sha256(b"sps").hexdigest(),
                "buildPolicy": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-bp",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spbp").hexdigest(),
                },
            },
            "signatures": [],
        }
        return _TQO.canonical_pf_jcs(obj)
    if object_kind == "production-profile":
        obj = {
            "schema": "proof-forge.task-qualification-production-profile.v1",
            "id": "synth-profile-v1",
            "version": "1.0.0",
            "kind": "production",
            "namespace": _STORE_V2.NAMESPACE,
            "taskId": task_id,
            "operation": operation,
            "gateSetDigest": "sha256:" + hashlib.sha256(b"gs").hexdigest(),
            "expectedAuthorityPolicy": {
                "schema": "proof-forge.bootstrap-authority-policy.v1",
                "id": "synth-authority-policy-v1",
                "version": "1.0.0",
                "digest": "sha256:" + hashlib.sha256(b"ap").hexdigest(),
            },
            "adapter": {
                "id": "synth-adapter",
                "executable": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-adapter-exec",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"ae").hexdigest(),
                },
                "closure": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-adapter-cl",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"ac").hexdigest(),
                },
                "sourceDigest": "sha256:" + hashlib.sha256(b"as").hexdigest(),
                "buildPolicy": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-adapter-bp",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"abp").hexdigest(),
                },
            },
            "snapshotParser": {
                "id": "synth-snapshot-parser",
                "executable": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-executable",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spe").hexdigest(),
                },
                "closure": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-closure",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spc").hexdigest(),
                },
                "sourceDigest": "sha256:" + hashlib.sha256(b"sps").hexdigest(),
                "buildPolicy": {
                    "schema": "proof-forge.task-qualification-fixture-resolved-blob.v1",
                    "id": "synth-snapshot-parser-bp",
                    "version": "1.0.0",
                    "digest": "sha256:" + hashlib.sha256(b"spbp").hexdigest(),
                },
            },
            "artifacts": [],
            "signatures": [],
        }
        return _TQO.canonical_pf_jcs(obj)
    if object_kind == "revocation-snapshot":
        snap = {
            "schema": "proof-forge.revocation-ledger-snapshot.v1",
            "id": "synth-revocation-snapshot",
            "version": "1.0.0",
            "authorityPolicy": {
                "schema": "proof-forge.bootstrap-authority-policy.v1",
                "id": "synth-authority-policy-v1",
                "version": "1.0.0",
                "digest": "sha256:" + hashlib.sha256(b"policy").hexdigest(),
            },
            "records": [],
            "head": None,
            "recordsDigest": "sha256:" + hashlib.sha256(b"records").hexdigest(),
            "signatures": [],
        }
        return _TQO.canonical_pf_jcs(snap)
    if object_kind == "revocation-record":
        rec = {
            "schema": "proof-forge.evidence-revocation.v1",
            "id": "RVK-20260723-0001",
            "version": "1.0.0",
            "evidence": {"id": "EV-20260723-0001", "sha256": "00" * 32},
            "revokedUtc": "2026-07-23T00:00:00Z",
            "reasonCode": "other",
            "reason": "synthetic protocol object",
            "authorityRef": "synth-authority-policy-v1",
            "replacement": None,
            "previousRecordSha256": "00" * 32,
        }
        return _TQO.canonical_pf_jcs(rec)
    raise AssertionError(f"unknown object kind: {object_kind}")


def _synth_run_service(server_sock: socket.socket, tpl, object_ids, revocation_head):
    """Run a synthetic v2 service on the server side of a socketpair.

    Responds to hello, fixed lookups, and revocation records. This is a
    test-owned synthetic service; it never produces production authority.
    """
    # Receive client hello
    hello_payload = _STORE_V2.recv_packet(server_sock)
    hello = _STORE_V2._decode_frame(hello_payload)
    if hello.get("schema") != _STORE_V2.CLIENT_HELLO_SCHEMA:
        raise AssertionError("expected client hello")
    # Send server hello
    server_hello_payload = _synth_build_server_hello(tpl)
    _STORE_V2.send_packet(server_sock, server_hello_payload)

    # Handle fixed lookups (0..6)
    request_id = 0
    for object_kind in _STORE_V2.FIXED_LOOKUP_OBJECT_KINDS[:7]:
        req_payload = _STORE_V2.recv_packet(server_sock)
        req = _STORE_V2._decode_frame(req_payload)
        if req["requestId"] != request_id:
            raise AssertionError(f"expected requestId {request_id}")
        key = req["key"]
        obj_bytes = _synth_make_object(object_kind, tpl.taskId, tpl.operation)
        resp_payload = _synth_build_lookup_response(
            request_id, key, tpl, obj_bytes)
        _STORE_V2.send_packet(server_sock, resp_payload)
        request_id += 1

    # (7): revocation-snapshot
    req_payload = _STORE_V2.recv_packet(server_sock)
    req = _STORE_V2._decode_frame(req_payload)
    if req["requestId"] != request_id:
        raise AssertionError(f"expected requestId {request_id}")
    key = req["key"]
    snap_bytes = _synth_make_object("revocation-snapshot", tpl.taskId, tpl.operation)
    resp_payload = _synth_build_lookup_response(
        request_id, key, tpl, snap_bytes)
    _STORE_V2.send_packet(server_sock, resp_payload)
    request_id += 1

    # (8..): no revocation records (empty snapshot)
    return request_id  # terminal requestId


def test_synthetic_seqpacket_hello_and_lookup_success() -> Result:
    """Synthetic SEQPACKET service: client hello + fixed lookup transcript succeeds.

    This verifies the full v2 protocol client framing, echo checking, ContentRef
    recomputation, and service signature verification over a real AF_UNIX
    SOCK_SEQPACKET socketpair. The synthetic service is test-owned and never
    produces production authority.
    """
    name = "synth.seqpacket_hello_lookup_success"
    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    try:
        # Build a synthetic handoff tuple
        service_ref = {
            "schema": _STORE_V2.DESCRIPTOR_SCHEMA,
            "id": "task-qualification-store-service-synth-run",
            "version": "2.0.0",
            "digest": "sha256:" + hashlib.sha256(b"synth-service-ref").hexdigest(),
        }
        tpl = _STORE_V2.HandoffTuple(
            taskId="TASK-D1-FIXTURE",
            operation="task-qualification",
            runId="synth-run",
            nonce="a" * 64,
            service=service_ref,
            handoffDigest=hashlib.sha256(b"handoff").digest(),
            headSequence=0,
            headDigest=hashlib.sha256(b"head").digest(),
        )
        gate_set_digest = hashlib.sha256(b"gate-set").digest()
        object_ids = {
            "authority-policy": "synth-authority-policy-v1",
            "production-profile-pin": "synth-pin-v1",
            # production-profile ID is derived from pin.profile after pin lookup
            "adapter": "synth-adapter",
            "snapshot-parser": "synth-snapshot-parser",
            "authority-store-service": "task-qualification-store-service-synth-run",
            "trusted-clock-service": "synth-trusted-clock-service",
        }
        revocation_head = (0, hashlib.sha256(b"head").digest())

        # Run the synthetic service on one side
        import threading
        terminal_rid_holder = []
        def _service_thread():
            terminal_rid_holder.append(
                _synth_run_service(right, tpl, object_ids, revocation_head))
        t = threading.Thread(target=_service_thread, daemon=True)
        t.start()

        # Run the client on the other side
        # First send hello
        client_hello_payload = _STORE_V2.build_client_hello(tpl)
        _STORE_V2.send_packet(left, client_hello_payload)
        # Receive server hello
        server_hello_payload = _STORE_V2.recv_packet(left)
        server_hello = _STORE_V2._decode_frame(server_hello_payload)
        _STORE_V2._require_exact_keys(
            server_hello, _STORE_V2.SERVER_HELLO_FIELDS, "server-hello")
        _STORE_V2._check_echo(server_hello, tpl, has_handoff_digest=True)

        # Run the buffered lookup transcript (client side)
        results = _TQPA._run_buffered_lookup_transcript(
            left, tpl, gate_set_digest, object_ids, revocation_head)

        t.join(timeout=5)

        if len(results) != 8:
            return Result(name, False, f"expected 8 lookups, got {len(results)}")
        # Verify the lookup order
        expected_kinds = list(_STORE_V2.FIXED_LOOKUP_OBJECT_KINDS)
        actual_kinds = [r.object_kind for r in results]
        if actual_kinds != expected_kinds:
            return Result(name, False, f"lookup order drift: {actual_kinds}")
        # Verify the descriptor (item 5) has the service public key
        desc_result = results[5]
        if desc_result.object_kind != "authority-store-service":
            return Result(name, False, "descriptor not at position 5")
        # Verify all service signatures
        _STORE_V2.verify_server_signature(server_hello, _SYNTH_SERVICE_PUBLIC_KEY)
        for r in results:
            _STORE_V2.verify_server_signature(r.response, _SYNTH_SERVICE_PUBLIC_KEY)
        return Result(name, True)
    except Exception as exc:
        return Result(name, False, f"exception: {type(exc).__name__}: {exc}")
    finally:
        left.close()
        right.close()


def test_synthetic_seqpacket_rejects_v1_frame() -> Result:
    """The client must reject a v1 server hello frame (cross-reject)."""
    name = "synth.seqpacket_rejects_v1_frame"
    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    try:
        service_ref = {
            "schema": _STORE_V2.DESCRIPTOR_SCHEMA,
            "id": "synth-svc",
            "version": "2.0.0",
            "digest": "sha256:" + hashlib.sha256(b"svc").hexdigest(),
        }
        tpl = _STORE_V2.HandoffTuple(
            taskId="TASK-D1-FIXTURE", operation="task-qualification",
            runId="synth-run", nonce="a" * 64, service=service_ref,
            handoffDigest=hashlib.sha256(b"h").digest(),
            headSequence=0, headDigest=hashlib.sha256(b"hd").digest())
        # Send a v1 server hello
        v1_hello = {
            "schema": _STORE_V2.V1_SERVER_HELLO_SCHEMA,
            "version": "1.0.0", "taskId": tpl.taskId, "operation": tpl.operation,
            "runId": tpl.runId, "nonce": tpl.nonce, "service": tpl.service,
            "headSequence": tpl.headSequence,
            "headDigest": _TQO.digest_to_wire(
                _BTO.Digest(algorithm="sha256", bytes=tpl.headDigest)),
            "status": "ready", "signature": "0" * 128,
        }
        _STORE_V2.send_packet(right, _TQO.canonical_pf_jcs(v1_hello))
        # Client sends hello, receives the v1 frame
        _STORE_V2.send_packet(left, _STORE_V2.build_client_hello(tpl))
        payload = _STORE_V2.recv_packet(left)
        try:
            _STORE_V2.parse_server_hello(payload, tpl, _SYNTH_SERVICE_PUBLIC_KEY)
            return Result(name, False, "v1 frame was not rejected")
        except _BTO.Rejected:
            return Result(name, True)
    finally:
        left.close()
        right.close()


def test_synthetic_seqpacket_rejects_bad_service_signature() -> Result:
    """The client must reject a server hello with an invalid service signature."""
    name = "synth.seqpacket_rejects_bad_sig"
    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    try:
        service_ref = {
            "schema": _STORE_V2.DESCRIPTOR_SCHEMA,
            "id": "synth-svc", "version": "2.0.0",
            "digest": "sha256:" + hashlib.sha256(b"svc").hexdigest(),
        }
        tpl = _STORE_V2.HandoffTuple(
            taskId="TASK-D1-FIXTURE", operation="task-qualification",
            runId="synth-run", nonce="a" * 64, service=service_ref,
            handoffDigest=hashlib.sha256(b"h").digest(),
            headSequence=0, headDigest=hashlib.sha256(b"hd").digest())
        # Build a server hello with a wrong signature
        frame = {
            "schema": _STORE_V2.SERVER_HELLO_SCHEMA,
            "version": _STORE_V2.VERSION,
            "taskId": tpl.taskId, "operation": tpl.operation,
            "runId": tpl.runId, "nonce": tpl.nonce, "service": tpl.service,
            "handoffDigest": _TQO.digest_to_wire(
                _BTO.Digest(algorithm="sha256", bytes=tpl.handoffDigest)),
            "headSequence": tpl.headSequence,
            "headDigest": _TQO.digest_to_wire(
                _BTO.Digest(algorithm="sha256", bytes=tpl.headDigest)),
            "status": "ready",
        }
        frame["signature"] = "0" * 128  # wrong signature
        _STORE_V2.send_packet(right, _TQO.canonical_pf_jcs(frame))
        _STORE_V2.send_packet(left, _STORE_V2.build_client_hello(tpl))
        payload = _STORE_V2.recv_packet(left)
        try:
            _STORE_V2.parse_server_hello(payload, tpl, _SYNTH_SERVICE_PUBLIC_KEY)
            return Result(name, False, "bad signature was not rejected")
        except _BTO.Rejected:
            return Result(name, True)
    finally:
        left.close()
        right.close()


# ---------------------------------------------------------------------------
# §8.2 production profile/pin field and join tests (adapted from object worker)
# ---------------------------------------------------------------------------

import dataclasses as _dc

def _make_synth_profile_and_pin(operation="task-qualification",
                                 task_id="TASK-D1-FIXTURE"):
    """Build a synth profile+pin pair for field/join tests."""
    authority_policy_ref = _TQO.ContentRef(
        schema="proof-forge.bootstrap-authority-policy.v1",
        id="synth-authority-policy-v1",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\x55" * 32),
    )
    adapter = _build_synth_adapter()
    if operation in ("task-qualification", "d0-10-bootstrap-approval"):
        gate_ids = (_TQFB.FIXTURE_GATE_ID,)
        artifact_roles = _TQO.operation_artifact_roles(operation, gate_ids)
        artifacts = tuple(
            _TQO.ProductionArtifactMappingV1(
                role=role,
                artifact=_TQO.ContentRef(
                    schema="proof-forge.task-qualification-fixture-resolved-blob.v1",
                    id=f"synth-artifact-{role}",
                    version="1.0.0",
                    digest=_BTO.Digest(algorithm="sha256",
                                       bytes=hashlib.sha256(role.encode()).digest()),
                ),
                payloadSha256=_BTO.Digest(algorithm="sha256",
                                          bytes=hashlib.sha256(role.encode()).digest()),
            )
            for role in artifact_roles
        )
    else:
        gate_ids = ()
        artifacts = ()
    profile = _build_synth_production_profile(
        authority_policy_ref, adapter, task_id=task_id, operation=operation,
        gate_ids=gate_ids, artifacts=artifacts)
    pin = _build_synth_production_profile_pin(profile, authority_policy_ref)
    return profile, pin


def test_production_profile_fields_present() -> Result:
    """§8.2: production profile must carry taskId, operation, gateSetDigest,
    snapshotParser, artifacts in the correct spec field order."""
    name = "obj.profile_fields"
    profile, _ = _make_synth_profile_and_pin()
    wire = _TQO.production_profile_to_wire(profile)
    expected_keys = [
        "schema", "id", "version", "kind", "namespace",
        "taskId", "operation", "gateSetDigest",
        "expectedAuthorityPolicy", "adapter", "snapshotParser",
        "artifacts", "signatures",
    ]
    if list(wire.keys()) != expected_keys:
        return Result(name, False, f"field order: {list(wire.keys())}")
    return Result(name, True)


def test_production_pin_fields_present() -> Result:
    """§8.2: production pin must carry taskId, operation, gateSetDigest,
    expectedSnapshotParser in the correct spec field order."""
    name = "obj.pin_fields"
    _, pin = _make_synth_profile_and_pin()
    wire = _TQO.production_profile_pin_to_wire(pin)
    expected_keys = [
        "schema", "id", "version", "taskId", "operation", "gateSetDigest",
        "authorityPolicy", "namespace", "profile", "expectedSnapshotParser",
        "signatures",
    ]
    if list(wire.keys()) != expected_keys:
        return Result(name, False, f"field order: {list(wire.keys())}")
    return Result(name, True)


def test_pin_profile_join_passes() -> Result:
    """§8.2: join_pin_to_profile must pass when pin and profile fields match."""
    name = "obj.pin_join_passes"
    profile, pin = _make_synth_profile_and_pin()
    try:
        _TQO.join_pin_to_profile(pin, profile)
    except _BTO.Rejected as r:
        return Result(name, False, r.detail)
    return Result(name, True)


def test_pin_profile_join_rejects_taskid_mismatch() -> Result:
    """§8.2: join_pin_to_profile must reject when pin.taskId != profile.taskId."""
    name = "obj.pin_join_taskid_mismatch"
    profile, pin = _make_synth_profile_and_pin()
    wrong_pin = _dc.replace(pin, taskId="TASK-D0-99")
    try:
        _TQO.join_pin_to_profile(wrong_pin, profile)
        return Result(name, False, "join did not reject")
    except _BTO.Rejected:
        return Result(name, True)


def test_pin_profile_join_rejects_gatesetdigest_mismatch() -> Result:
    """§8.2: join_pin_to_profile must reject when gateSetDigest differs."""
    name = "obj.pin_join_gsd_mismatch"
    profile, pin = _make_synth_profile_and_pin()
    wrong_bytes = bytearray(profile.gateSetDigest.bytes)
    wrong_bytes[-1] ^= 0x01
    wrong_digest = _BTO.Digest(algorithm="sha256", bytes=bytes(wrong_bytes))
    wrong_pin = _dc.replace(pin, gateSetDigest=wrong_digest)
    try:
        _TQO.join_pin_to_profile(wrong_pin, profile)
        return Result(name, False, "join did not reject")
    except _BTO.Rejected:
        return Result(name, True)


def test_pin_profile_join_rejects_snapshot_parser_mismatch() -> Result:
    """§8.2: join must reject when pin.expectedSnapshotParser != profile.snapshotParser."""
    name = "obj.pin_join_sp_mismatch"
    profile, pin = _make_synth_profile_and_pin()
    fake_ref = _TQO.ContentRef(
        schema="proof-forge.task-qualification-fixture-resolved-blob.v1",
        id="wrong-sp", version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\x33" * 32),
    )
    wrong_parser = _TQO.VerifierIdentityV1(
        id="wrong-sp-v1", executable=fake_ref, closure=fake_ref,
        sourceDigest=_BTO.Digest(algorithm="sha256", bytes=b"\x44" * 32),
        buildPolicy=fake_ref,
    )
    wrong_pin = _dc.replace(pin, expectedSnapshotParser=wrong_parser)
    try:
        _TQO.join_pin_to_profile(wrong_pin, profile)
        return Result(name, False, "join did not reject")
    except _BTO.Rejected:
        return Result(name, True)


def test_profile_derived_id_matches() -> Result:
    """§8.2: the profile id must be derived from taskId/operation/gateSetDigest."""
    name = "obj.profile_derived_id"
    profile, _ = _make_synth_profile_and_pin()
    expected = _TQO.derive_production_profile_id(
        profile.taskId, profile.operation, profile.gateSetDigest)
    if profile.id != expected:
        return Result(name, False, f"expected {expected}, got {profile.id}")
    return Result(name, True)


def test_pin_derived_id_matches() -> Result:
    """§8.2: the pin id must be derived from taskId/operation/gateSetDigest."""
    name = "obj.pin_derived_id"
    _, pin = _make_synth_profile_and_pin()
    expected = _TQO.derive_production_profile_pin_id(
        pin.taskId, pin.operation, pin.gateSetDigest)
    if pin.id != expected:
        return Result(name, False, f"expected {expected}, got {pin.id}")
    return Result(name, True)


def test_gate_set_digest_recomputed_from_gates() -> Result:
    """§8.2: gateSetDigest must recompute from the operation and gate IDs."""
    name = "obj.gsd_recompute"
    profile, _ = _make_synth_profile_and_pin("task-qualification")
    recomputed = _TQO.compute_gate_set_digest(
        "task-qualification", (_TQFB.FIXTURE_GATE_ID,))
    if recomputed.bytes != profile.gateSetDigest.bytes:
        return Result(name, False, "gateSetDigest mismatch")
    return Result(name, True)


def test_production_profile_all_four_operations() -> Result:
    """§8.2: all four operations must produce valid production profiles."""
    name = "obj.all_four_ops"
    for operation in ("task-qualification", "task-completion",
                      "d0-10-bootstrap-approval", "d0-10-bootstrap-receipt"):
        profile, pin = _make_synth_profile_and_pin(operation)
        if profile.operation != operation:
            return Result(name, False, f"operation mismatch: {profile.operation}")
        if operation in ("task-completion", "d0-10-bootstrap-receipt"):
            if len(profile.artifacts) != 0:
                return Result(name, False, f"{operation} has nonzero artifacts")
        try:
            _TQO.join_pin_to_profile(pin, profile)
        except _BTO.Rejected as r:
            return Result(name, False, f"pin join failed for {operation}: {r.detail}")
    return Result(name, True)


def test_artifacts_exact_coverage_task_qualification() -> Result:
    """§8.2: task-qualification artifacts must exact-cover 12 gate-keyed roles."""
    name = "obj.artifacts_coverage_tq"
    profile, _ = _make_synth_profile_and_pin("task-qualification")
    expected_roles = _TQO.operation_artifact_roles(
        "task-qualification", (_TQFB.FIXTURE_GATE_ID,))
    actual_roles = tuple(a.role for a in profile.artifacts)
    if actual_roles != expected_roles:
        return Result(name, False, f"expected {len(expected_roles)}, got {len(actual_roles)}")
    return Result(name, True)


def test_artifacts_exact_coverage_receipt_zero() -> Result:
    """§8.2: receipt operations must have exactly zero artifacts."""
    name = "obj.artifacts_receipt_zero"
    for operation in ("task-completion", "d0-10-bootstrap-receipt"):
        profile, _ = _make_synth_profile_and_pin(operation)
        if len(profile.artifacts) != 0:
            return Result(name, False, f"{operation} has nonzero artifacts")
    return Result(name, True)


def test_pin_signature_verification_passes() -> Result:
    """§8.2: verify_production_profile_pin_signatures must pass for a valid pin."""
    name = "obj.pin_sig_passes"
    _, pin = _make_synth_profile_and_pin()
    synth_principals = tuple(
        _TQO.FixtureAuthorityPrincipalV1(
            principalId=SYNTH_PRINCIPALS[kid]["principalId"],
            keyId=kid,
            publicKey=SYNTH_PUBLIC_KEYS[kid],
            roles=tuple(SYNTH_PRINCIPALS[kid]["roles"]),
        )
        for kid in sorted(SYNTH_SEEDS)
    )
    synth_policy = _dc.replace(_TQO.build_default_fixture_policy(), principals=synth_principals)
    try:
        _TQO.verify_production_profile_pin_signatures(pin, synth_policy)
    except _BTO.Rejected as r:
        return Result(name, False, r.detail)
    return Result(name, True)


def test_pin_signature_verification_rejects_wrong_sig() -> Result:
    """§8.2: verify_production_profile_pin_signatures must reject a corrupted sig."""
    name = "obj.pin_sig_rejects"
    _, pin = _make_synth_profile_and_pin()
    bad_sigs = list(pin.signatures)
    bad_sigs[0] = _dc.replace(bad_sigs[0], signature=b"\x00" * 64)
    bad_pin = _dc.replace(pin, signatures=tuple(bad_sigs))
    synth_principals = tuple(
        _TQO.FixtureAuthorityPrincipalV1(
            principalId=SYNTH_PRINCIPALS[kid]["principalId"],
            keyId=kid,
            publicKey=SYNTH_PUBLIC_KEYS[kid],
            roles=tuple(SYNTH_PRINCIPALS[kid]["roles"]),
        )
        for kid in sorted(SYNTH_SEEDS)
    )
    synth_policy = _dc.replace(_TQO.build_default_fixture_policy(), principals=synth_principals)
    try:
        _TQO.verify_production_profile_pin_signatures(bad_pin, synth_policy)
        return Result(name, False, "did not reject corrupted signature")
    except _BTO.Rejected:
        return Result(name, True)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_all_tests() -> list:
    tests = [
        # v1 synthetic acceptance (migrated from production module)
        test_synth_acceptance_schema_and_id,
        test_synth_pure_projection_digest_complete,
        test_synth_signatures_match_recomputed,
        test_synth_bundle_and_subject_digests,
        test_synth_d0_10_approval,
        test_synth_closeout_optional,
        # v2 acceptance wire helpers
        test_v2_unsigned_acceptance_field_manifest,
        test_v2_signed_acceptance_field_manifest,
        test_v2_unsigned_rejects_signatures_field,
        test_v2_acceptance_statement_digest_domain,
        test_v2_d0_nullable_fields,
        test_v2_provenance_roles_and_digest,
        test_v2_acceptance_full_digest_domain,
        test_v2_acceptance_content_ref,
        # v2 protected API
        test_v2_protect_api_seven_positional_only,
        test_v2_protect_api_rejects_invalid_operation,
        test_v2_protect_api_rejects_noncanonical_handoff,
        test_v2_protect_api_rejects_duplicate_fds,
        test_v2_protect_api_no_private_key_injection,
        test_v2_protect_api_keyword_invocation_rejected,
        test_v2_protect_api_regular_file_store_rejects,
        test_v2_protect_api_sock_stream_store_rejects,
        # synthetic SEQPACKET service
        test_synthetic_seqpacket_hello_and_lookup_success,
        test_synthetic_seqpacket_rejects_v1_frame,
        test_synthetic_seqpacket_rejects_bad_service_signature,
        # §8.2 production profile/pin field and join tests
        test_production_profile_fields_present,
        test_production_pin_fields_present,
        test_pin_profile_join_passes,
        test_pin_profile_join_rejects_taskid_mismatch,
        test_pin_profile_join_rejects_gatesetdigest_mismatch,
        test_pin_profile_join_rejects_snapshot_parser_mismatch,
        test_profile_derived_id_matches,
        test_pin_derived_id_matches,
        test_gate_set_digest_recomputed_from_gates,
        test_production_profile_all_four_operations,
        test_artifacts_exact_coverage_task_qualification,
        test_artifacts_exact_coverage_receipt_zero,
        test_pin_signature_verification_passes,
        test_pin_signature_verification_rejects_wrong_sig,
    ]
    results = []
    for test in tests:
        try:
            result = test()
        except Exception as exc:
            result = Result(test.__name__, False, f"exception: {exc}")
        results.append(result)
    return results


def main() -> int:
    results = run_all_tests()
    passed = sum(1 for r in results if r.passed)
    failed = sum(1 for r in results if not r.passed)
    print(f"Protected adapter self-test: {passed}/{len(results)} passed, {failed} failed")
    for r in results:
        print(r)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())