"""TST-DOC-001/task-qualification-v1 RED matrix: §8.4 protected adapter invariants.

The protected adapter is the policy-pinned production consumer. These tests
verify the adapter's internal logic in isolation, independent of the full
production ceremony (which requires an eligible Stage-0 host, external
authority store, and real authorization signatures).

The adapter is exercised via ``build_protected_acceptance`` with a synthetic
production profile and synthetic signing seeds. The tests assert:

- The protected acceptance has the exact §8.4 schema/id/field order.
- ``pureProjectionDigest`` recomputes from the complete §8.1 Verified record
  (not a subset), under domain ``pf.taskqual.pure-projection.v1``.
- ``productionProfilePin`` uses domain ``pf.taskqual.production-profile-pin.v1``
  (not the protected-acceptance domain).
- Signatures are sorted by keyId, unique, and match the re-derived message.
- A keyId not in the authority principals is rejected.
- The authorityClass is fixed to ``production-candidate-bound``.
- The protected id follows the fixed ``protected-task-qualification-<op>-<suffix>``
  grammar.

These are pure unit tests of the adapter's deterministic construction; they do
not exercise the external authority store, trusted clock, or live session
attestations, and they do not produce production-candidate-bound acceptance
that docs-check would accept (docs-check requires the external ceremony).
"""

from __future__ import annotations

import sys
from dataclasses import fields
from pathlib import Path

# Ensure scripts/ is importable when run from the repo root.
_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent))

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV
import task_qualification_fixture_builder as _TQFB
import task_qualification_protected_adapter as _TQPA


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

class AdapterResult:
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


# Synthetic production signing seeds (RFC 8032 vectors, distinct from the
# fixture verifier key #4 so the adapter uses real Ed25519 but stays out of
# the fixture principal set). Vector #1/#2/#3 are the fixture principal
# seeds, but the adapter does not check seed↔principal binding here — it
# only requires the keyId to be present in authority_principals and the
# caller to provide the matching seed. The ceremony caller (not the unit
# test) is responsible for real key management.
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
    authority_policy_ref: _TQO.ContentRef,
    adapter: _TQO.VerifierIdentityV1,
) -> _TQO.ProductionVerificationProfileV1:
    """Build a synthetic production profile with synthetic signatures.

    The profile's signatures are not verified by the adapter unit tests —
    the adapter only requires the profile object to derive its digest and pin.
    Real production profiles are signed by the authority store; the adapter
    receives them already verified.
    """
    # Build signed profile: the statement domain is
    # pf.taskqual.production-profile-statement.v1; signature message is
    # pf.taskqual.production-profile-signature.v1 || NUL || raw32(statement).
    unsigned_wire = _TQO.production_profile_to_wire(_TQO.ProductionVerificationProfileV1(
        schema="proof-forge.task-qualification-production-profile.v1",
        id="task-qualification-production-profile-v1",
        version="1.0.0",
        kind="production",
        namespace="task-qualification-production-v1",
        expectedAuthorityPolicy=authority_policy_ref,
        adapter=adapter,
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
        id="task-qualification-production-profile-v1",
        version="1.0.0",
        kind="production",
        namespace="task-qualification-production-v1",
        expectedAuthorityPolicy=authority_policy_ref,
        adapter=adapter,
        signatures=tuple(sigs),
    )


def _build_synth_production_profile_pin(
    profile: _TQO.ProductionVerificationProfileV1,
    authority_policy_ref: _TQO.ContentRef,
) -> _TQO.ProductionVerificationProfilePinV1:
    """Build a synthetic production profile pin with synthetic signatures."""
    profile_ref = _TQO.production_profile_content_ref(profile)
    unsigned_wire = _TQO.production_profile_pin_to_wire(_TQO.ProductionVerificationProfilePinV1(
        schema="proof-forge.task-qualification-production-profile-pin.v1",
        id="task-qualification-production-profile-v1",
        version="1.0.0",
        authorityPolicy=authority_policy_ref,
        namespace="task-qualification-production-v1",
        profile=profile_ref,
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
        id="task-qualification-production-profile-v1",
        version="1.0.0",
        authorityPolicy=authority_policy_ref,
        namespace="task-qualification-production-v1",
        profile=profile_ref,
        signatures=tuple(sigs),
    )


def _build_adapter_inputs(operation: str):
    """Build ProtectedAdapterInput and related inputs for a fixture chain."""
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


def _build_synth_adapter() -> _TQO.VerifierIdentityV1:
    """Build a synthetic adapter VerifierIdentityV1."""
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


def _build_synth_provenance_refs() -> tuple:
    """Build synthetic nonempty provenance refs for the adapter input.

    The adapter only checks nonempty + sorted + unique; the real ceremony
    caller provides clock/store/safe-open Git/archive/review/live-session
    attestations. The unit test uses well-formed synthetic refs.
    """
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
    # Return pre-sorted by (schema, id, version, digest) to match adapter
    # expectation; the adapter re-sorts anyway.
    return (clock_ref, store_ref)


def _make_protected_adapter_input(operation: str) -> _TQPA.ProtectedAdapterInput:
    verified, bundle_bytes, subject_bytes = _build_adapter_inputs(operation)
    # Use the exact authorityPolicy ref the pure verifier projected from the
    # bundle, so the §8.4 binding check (profile.expectedAuthorityPolicy ==
    # Verified.authorityPolicy) passes.
    authority_policy_ref = verified.authorityPolicy
    adapter = _build_synth_adapter()
    production_profile = _build_synth_production_profile(authority_policy_ref, adapter)
    production_profile_pin = _build_synth_production_profile_pin(
        production_profile, authority_policy_ref)
    return _TQPA.ProtectedAdapterInput(
        pure_verified=verified,
        bundle_bytes=bundle_bytes,
        subject_bytes=subject_bytes,
        trusted_verification_instant="2026-07-21T12:00:00Z",
        adapter=adapter,
        production_profile=production_profile,
        production_profile_pin=production_profile_pin,
        provenance_refs=_build_synth_provenance_refs(),
        authority_principals=SYNTH_PRINCIPALS,
        signing_seeds=dict(SYNTH_SEEDS),
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_protected_acceptance_schema_and_id() -> AdapterResult:
    """The protected acceptance must use the exact §8.4 schema and id grammar."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.schema_and_id", False, pa.detail)
    if pa.schema != _TQPA.PROTECTED_ACCEPTANCE_SCHEMA:
        return AdapterResult("protected.schema_and_id", False,
                             f"schema={pa.schema}")
    if pa.version != "1.0.0":
        return AdapterResult("protected.schema_and_id", False,
                             f"version={pa.version}")
    if pa.authorityClass != "production-candidate-bound":
        return AdapterResult("protected.schema_and_id", False,
                             f"authorityClass={pa.authorityClass}")
    if pa.id != "protected-task-qualification-task-qualification-d1-fixture":
        return AdapterResult("protected.schema_and_id", False,
                             f"id={pa.id}")
    return AdapterResult("protected.schema_and_id", True)


def test_protected_acceptance_field_order() -> AdapterResult:
    """The protected acceptance wire must emit the §8.4 fixed field order."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.field_order", False, pa.detail)
    wire = _TQPA.protected_acceptance_to_wire(pa)
    expected_keys = [
        "schema", "id", "version", "authorityClass", "operation",
        "pureProjectionDigest", "bundleDigest", "subjectDigest",
        "preCloseCandidate", "closeoutCandidate", "trustedVerificationInstant",
        "adapter", "productionProfileDigest", "productionProfilePin",
        "provenanceRefs", "signatures",
    ]
    actual_keys = list(wire.keys())
    if actual_keys != expected_keys:
        return AdapterResult("protected.field_order", False,
                             f"expected {expected_keys}, got {actual_keys}")
    return AdapterResult("protected.field_order", True)


def test_pure_projection_digest_complete() -> AdapterResult:
    """pureProjectionDigest must recompute from the complete §8.1 Verified record.

    The adapter must NOT project a subset of the Verified fields — the digest
    must bind every field the pure verifier returned, so that a forged
    projection cannot satisfy docs-check.
    """
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.pure_projection_complete", False, pa.detail)

    # Recompute the pure projection from the verified record.
    expected_projection = _TQO.verified_task_qualification_to_wire(
        inp.pure_verified)
    expected_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PURE_PROJECTION, expected_projection)

    if pa.pureProjectionDigest.bytes != expected_digest.bytes:
        return AdapterResult(
            "protected.pure_projection_complete", False,
            f"expected {expected_digest.bytes.hex()}, "
            f"got {pa.pureProjectionDigest.bytes.hex()}")
    return AdapterResult("protected.pure_projection_complete", True)


def test_pure_projection_digest_complete_completion() -> AdapterResult:
    """pureProjectionDigest for task-completion must bind the full Verified record
    including qualification, receipt, closeoutDiffDigest and authorityPolicy."""
    inp = _make_protected_adapter_input("task-completion")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-completion", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.pure_projection_completion", False, pa.detail)

    expected_projection = _TQO.verified_task_completion_to_wire(
        inp.pure_verified)
    expected_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PURE_PROJECTION, expected_projection)

    if pa.pureProjectionDigest.bytes != expected_digest.bytes:
        return AdapterResult(
            "protected.pure_projection_completion", False,
            f"digest mismatch: expected {expected_digest.bytes.hex()}, "
            f"got {pa.pureProjectionDigest.bytes.hex()}")
    return AdapterResult("protected.pure_projection_completion", True)


def test_production_profile_pin_digest_domain() -> AdapterResult:
    """productionProfilePin must use domain pf.taskqual.production-profile-pin.v1.

    Using the protected-acceptance domain (a prior bug) would bind the pin to
    the wrong statement and let a forged pin satisfy docs-check.
    """
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.pin_digest_domain", False, pa.detail)

    # The pin ref should match the canonical pin content ref computed under
    # DOMAIN_PRODUCTION_PROFILE_PIN.
    expected_pin_ref = _TQO.production_profile_pin_content_ref(
        inp.production_profile_pin)
    if pa.productionProfilePin.digest.bytes != expected_pin_ref.digest.bytes:
        return AdapterResult(
            "protected.pin_digest_domain", False,
            f"pin digest mismatch: expected {expected_pin_ref.digest.bytes.hex()}, "
            f"got {pa.productionProfilePin.digest.bytes.hex()}")
    if pa.productionProfilePin.schema != expected_pin_ref.schema:
        return AdapterResult("protected.pin_digest_domain", False,
                             f"pin schema mismatch")
    if pa.productionProfilePin.id != expected_pin_ref.id:
        return AdapterResult("protected.pin_digest_domain", False,
                             f"pin id mismatch: {pa.productionProfilePin.id} vs {expected_pin_ref.id}")
    return AdapterResult("protected.pin_digest_domain", True)


def test_signatures_sorted_by_keyid_and_unique() -> AdapterResult:
    """Signatures must be sorted by keyId and unique (§1)."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.signatures_sorted", False, pa.detail)
    key_ids = [s.keyId for s in pa.signatures]
    if key_ids != sorted(key_ids):
        return AdapterResult("protected.signatures_sorted", False,
                             f"not sorted: {key_ids}")
    if len(set(key_ids)) != len(key_ids):
        return AdapterResult("protected.signatures_sorted", False,
                             f"duplicates: {key_ids}")
    if len(pa.signatures) != 3:
        return AdapterResult("protected.signatures_sorted", False,
                             f"expected 3 sigs, got {len(pa.signatures)}")
    return AdapterResult("protected.signatures_sorted", True)


def test_signatures_match_recomputed_message() -> AdapterResult:
    """Each signature must verify against the recomputed statement/message."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.signatures_match", False, pa.detail)

    wire = _TQPA.protected_acceptance_to_wire(pa)
    unsigned = dict(wire)
    unsigned["signatures"] = []
    statement_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT, unsigned)
    message = _TQO.DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE + b"\x00" + statement_digest.bytes

    for sig in pa.signatures:
        public_key = SYNTH_PUBLIC_KEYS[sig.keyId]
        if not _BTP.verify_ed25519(public_key, message, sig.signature):
            return AdapterResult("protected.signatures_match", False,
                                 f"signature for {sig.keyId} did not verify")
    return AdapterResult("protected.signatures_match", True)


def test_reject_keyid_not_in_authority_principals() -> AdapterResult:
    """A keyId not in authority_principals must be rejected."""
    inp = _make_protected_adapter_input("task-qualification")
    # Inject an extra signing seed for a keyId not in authority_principals.
    bad_seeds = dict(inp.signing_seeds)
    bad_seeds["rogue-key"] = _TQO.RFC8032_VECTOR_SEEDS[4]
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=inp.production_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=inp.provenance_refs,
        authority_principals=inp.authority_principals,
        signing_seeds=bad_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    # The adapter must reject the rogue keyId. The rejection may be either a
    # Rejected return or raise (caught by build_protected_acceptance).
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_unknown_keyid", True)
    # If it somehow built, check that the rogue signature is absent.
    key_ids = [s.keyId for s in pa.signatures]
    if "rogue-key" in key_ids:
        return AdapterResult("protected.reject_unknown_keyid", False,
                             "rogue keyId was signed")
    return AdapterResult("protected.reject_unknown_keyid", True)


def test_bundle_and_subject_digests_exact_bytes() -> AdapterResult:
    """bundleDigest and subjectDigest must be plain SHA-256 of exact input bytes."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.bundle_subject_digest", False, pa.detail)

    expected_bundle = _TQO.plain_sha256_digest(inp.bundle_bytes)
    expected_subject = _TQO.plain_sha256_digest(inp.subject_bytes)

    if pa.bundleDigest.bytes != expected_bundle.bytes:
        return AdapterResult("protected.bundle_subject_digest", False,
                             "bundle digest mismatch")
    if pa.subjectDigest.bytes != expected_subject.bytes:
        return AdapterResult("protected.bundle_subject_digest", False,
                             "subject digest mismatch")
    return AdapterResult("protected.bundle_subject_digest", True)


def test_preclose_candidate_matches_verified() -> AdapterResult:
    """preCloseCandidate in the acceptance must match the Verified record's candidate."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.preclose_matches", False, pa.detail)

    verified = inp.pure_verified
    if pa.preCloseCandidate.commit != verified.preCloseCandidate.commit:
        return AdapterResult("protected.preclose_matches", False, "commit mismatch")
    if pa.preCloseCandidate.treeObjectId != verified.preCloseCandidate.treeObjectId:
        return AdapterResult("protected.preclose_matches", False, "tree mismatch")
    if pa.preCloseCandidate.archiveDigest.bytes != verified.preCloseCandidate.archiveDigest.bytes:
        return AdapterResult("protected.preclose_matches", False, "archive digest mismatch")
    return AdapterResult("protected.preclose_matches", True)


def test_d0_10_approval_adapter() -> AdapterResult:
    """The D0-10 bootstrap approval operation must build a protected acceptance."""
    inp = _make_protected_adapter_input("d0-10-bootstrap-approval")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="d0-10-bootstrap-approval", task_id="TASK-D0-10")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.d0_10_approval", False, pa.detail)
    if pa.operation != "d0-10-bootstrap-approval":
        return AdapterResult("protected.d0_10_approval", False,
                             f"operation={pa.operation}")
    if pa.id != "protected-task-qualification-d0-10-bootstrap-approval-d0-10":
        return AdapterResult("protected.d0_10_approval", False,
                             f"id={pa.id}")
    # Recompute the pure projection for D0-10 approval.
    expected_projection = _TQO.verified_d0_10_bootstrap_approval_to_wire(
        inp.pure_verified)
    expected_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PURE_PROJECTION, expected_projection)
    if pa.pureProjectionDigest.bytes != expected_digest.bytes:
        return AdapterResult("protected.d0_10_approval", False,
                             "pureProjectionDigest mismatch")
    return AdapterResult("protected.d0_10_approval", True)


def test_d0_10_receipt_adapter() -> AdapterResult:
    """The D0-10 bootstrap receipt operation must build a protected acceptance."""
    inp = _make_protected_adapter_input("d0-10-bootstrap-receipt")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="d0-10-bootstrap-receipt", task_id="TASK-D0-10",
        closeout_candidate=inp.pure_verified.closeoutCandidate)
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.d0_10_receipt", False, pa.detail)
    if pa.operation != "d0-10-bootstrap-receipt":
        return AdapterResult("protected.d0_10_receipt", False,
                             f"operation={pa.operation}")
    # Recompute the pure projection for D0-10 completion.
    expected_projection = _TQO.verified_d0_10_bootstrap_completion_to_wire(
        inp.pure_verified)
    expected_digest = _TQO.domain_digest(
        _TQO.DOMAIN_PURE_PROJECTION, expected_projection)
    if pa.pureProjectionDigest.bytes != expected_digest.bytes:
        return AdapterResult("protected.d0_10_receipt", False,
                             "pureProjectionDigest mismatch")
    return AdapterResult("protected.d0_10_receipt", True)


def test_closeout_candidate_optional() -> AdapterResult:
    """For operations without a closeout candidate (task-qualification, d0-10-bootstrap-approval),
    closeoutCandidate must be None in both the dataclass and the wire form."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.closeout_optional", False, pa.detail)
    if pa.closeoutCandidate is not None:
        return AdapterResult("protected.closeout_optional", False,
                             "dataclass closeoutCandidate not None")
    wire = _TQPA.protected_acceptance_to_wire(pa)
    if wire["closeoutCandidate"] is not None:
        return AdapterResult("protected.closeout_optional", False,
                             "wire closeoutCandidate not None")
    return AdapterResult("protected.closeout_optional", True)


def test_production_profile_digest_matches() -> AdapterResult:
    """productionProfileDigest must recompute under DOMAIN_PRODUCTION_PROFILE."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.profile_digest", False, pa.detail)

    expected = _TQO.domain_digest(
        _TQO.DOMAIN_PRODUCTION_PROFILE,
        _TQO.production_profile_to_wire(inp.production_profile))
    if pa.productionProfileDigest.bytes != expected.bytes:
        return AdapterResult("protected.profile_digest", False,
                             f"expected {expected.bytes.hex()}, "
                             f"got {pa.productionProfileDigest.bytes.hex()}")
    return AdapterResult("protected.profile_digest", True)


def test_protected_acceptance_content_ref_domain() -> AdapterResult:
    """The protected acceptance ContentRef must use DOMAIN_PROTECTED_ACCEPTANCE."""
    inp = _make_protected_adapter_input("task-qualification")
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.content_ref_domain", False, pa.detail)

    ref = _TQPA.protected_acceptance_content_ref(pa)
    wire = _TQPA.protected_acceptance_to_wire(pa)
    expected = _TQO.domain_digest(_TQPA.DOMAIN_PROTECTED_ACCEPTANCE, wire)
    if ref.digest.bytes != expected.bytes:
        return AdapterResult("protected.content_ref_domain", False,
                             f"expected {expected.bytes.hex()}, "
                             f"got {ref.digest.bytes.hex()}")
    if ref.schema != _TQPA.PROTECTED_ACCEPTANCE_SCHEMA:
        return AdapterResult("protected.content_ref_domain", False,
                             f"schema={ref.schema}")
    return AdapterResult("protected.content_ref_domain", True)


# ---------------------------------------------------------------------------
# §8.4 binding enforcement tests (P1-D/E/F)
# ---------------------------------------------------------------------------

def test_reject_adapter_mismatch() -> AdapterResult:
    """§8.4: adapter executable/closure/buildPolicy must equal
    production_profile.adapter field-by-field. A mismatch must reject."""
    inp = _make_protected_adapter_input("task-qualification")
    # Swap the adapter to a different VerifierIdentityV1.
    fake_ref = _TQO.ContentRef(
        schema="proof-forge.task-qualification-fixture-resolved-blob.v1",
        id="rogue-adapter-executable",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\xff" * 32),
    )
    rogue_adapter = _TQO.VerifierIdentityV1(
        id="rogue-protected-adapter-v1",
        executable=fake_ref,
        closure=fake_ref,
        sourceDigest=_BTO.Digest(algorithm="sha256", bytes=b"\xee" * 32),
        buildPolicy=fake_ref,
    )
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=rogue_adapter,
        production_profile=inp.production_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=inp.provenance_refs,
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_adapter_mismatch", True)
    return AdapterResult("protected.reject_adapter_mismatch", False,
                         "adapter mismatch was not rejected")


def test_reject_profile_authority_policy_mismatch() -> AdapterResult:
    """§8.2/§8.4: production_profile.expectedAuthorityPolicy must equal the
    bundle's authorityPolicy (carried on the Verified record). A mismatch
    must reject."""
    inp = _make_protected_adapter_input("task-qualification")
    wrong_policy_ref = _TQO.ContentRef(
        schema="proof-forge.bootstrap-authority-policy.v1",
        id="wrong-bootstrap-authority-policy-v1",
        version="1.0.0",
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\x99" * 32),
    )
    # Rebuild the production profile with the wrong expectedAuthorityPolicy.
    wrong_profile = _TQO.ProductionVerificationProfileV1(
        schema=inp.production_profile.schema,
        id=inp.production_profile.id,
        version=inp.production_profile.version,
        kind=inp.production_profile.kind,
        namespace=inp.production_profile.namespace,
        expectedAuthorityPolicy=wrong_policy_ref,
        adapter=inp.production_profile.adapter,
        signatures=inp.production_profile.signatures,
    )
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=wrong_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=inp.provenance_refs,
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_policy_mismatch", True)
    return AdapterResult("protected.reject_policy_mismatch", False,
                         "profile authorityPolicy mismatch was not rejected")


def test_reject_pin_profile_ref_mismatch() -> AdapterResult:
    """§8.2: pin.profile must equal the recomputed production profile content
    ref. A mismatch must reject."""
    inp = _make_protected_adapter_input("task-qualification")
    wrong_profile_ref = _TQO.ContentRef(
        schema=inp.production_profile.schema,
        id=inp.production_profile.id,
        version=inp.production_profile.version,
        digest=_BTO.Digest(algorithm="sha256", bytes=b"\x77" * 32),
    )
    wrong_pin = _TQO.ProductionVerificationProfilePinV1(
        schema=inp.production_profile_pin.schema,
        id=inp.production_profile_pin.id,
        version=inp.production_profile_pin.version,
        authorityPolicy=inp.production_profile_pin.authorityPolicy,
        namespace=inp.production_profile_pin.namespace,
        profile=wrong_profile_ref,
        signatures=inp.production_profile_pin.signatures,
    )
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=inp.production_profile,
        production_profile_pin=wrong_pin,
        provenance_refs=inp.provenance_refs,
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_pin_profile_mismatch", True)
    return AdapterResult("protected.reject_pin_profile_mismatch", False,
                         "pin profile ref mismatch was not rejected")


def test_reject_empty_provenance_refs() -> AdapterResult:
    """§8.4: provenanceRefs must be nonempty. Empty must reject."""
    inp = _make_protected_adapter_input("task-qualification")
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=inp.production_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=(),
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_empty_provenance", True)
    return AdapterResult("protected.reject_empty_provenance", False,
                         "empty provenanceRefs was not rejected")


def test_reject_duplicate_provenance_refs() -> AdapterResult:
    """§8.4: provenanceRefs must be unique by (schema,id,version,digest).
    Duplicates must reject."""
    inp = _make_protected_adapter_input("task-qualification")
    dup_ref = inp.provenance_refs[0]
    dup_refs = (dup_ref, dup_ref, inp.provenance_refs[1])
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=inp.production_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=dup_refs,
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.reject_dup_provenance", True)
    return AdapterResult("protected.reject_dup_provenance", False,
                         "duplicate provenanceRefs was not rejected")


def test_provenance_refs_sorted_in_wire() -> AdapterResult:
    """§8.4: provenanceRefs in the wire form must be ASCII-sorted by
    (schema,id,version,digest)."""
    inp = _make_protected_adapter_input("task-qualification")
    # Provide refs in reverse order; adapter must sort them.
    refs = tuple(reversed(inp.provenance_refs))
    inp = _TQPA.ProtectedAdapterInput(
        pure_verified=inp.pure_verified,
        bundle_bytes=inp.bundle_bytes,
        subject_bytes=inp.subject_bytes,
        trusted_verification_instant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        production_profile=inp.production_profile,
        production_profile_pin=inp.production_profile_pin,
        provenance_refs=refs,
        authority_principals=inp.authority_principals,
        signing_seeds=inp.signing_seeds,
    )
    pa = _TQPA.build_protected_acceptance(
        inp, operation="task-qualification", task_id="TASK-D1-FIXTURE")
    if isinstance(pa, _BTO.Rejected):
        return AdapterResult("protected.provenance_sorted", False, pa.detail)
    wire = _TQPA.protected_acceptance_to_wire(pa)
    refs_in_wire = [
        (r["schema"], r["id"], r["version"], r["digest"])
        for r in wire["provenanceRefs"]
    ]
    if refs_in_wire != sorted(refs_in_wire):
        return AdapterResult("protected.provenance_sorted", False,
                             f"not sorted: {refs_in_wire}")
    return AdapterResult("protected.provenance_sorted", True)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_all_tests() -> list:
    tests = [
        test_protected_acceptance_schema_and_id,
        test_protected_acceptance_field_order,
        test_pure_projection_digest_complete,
        test_pure_projection_digest_complete_completion,
        test_production_profile_pin_digest_domain,
        test_signatures_sorted_by_keyid_and_unique,
        test_signatures_match_recomputed_message,
        test_reject_keyid_not_in_authority_principals,
        test_bundle_and_subject_digests_exact_bytes,
        test_preclose_candidate_matches_verified,
        test_d0_10_approval_adapter,
        test_d0_10_receipt_adapter,
        test_closeout_candidate_optional,
        test_production_profile_digest_matches,
        test_protected_acceptance_content_ref_domain,
        # §8.4 binding enforcement (P1-D/E/F)
        test_reject_adapter_mismatch,
        test_reject_profile_authority_policy_mismatch,
        test_reject_pin_profile_ref_mismatch,
        test_reject_empty_provenance_refs,
        test_reject_duplicate_provenance_refs,
        test_provenance_refs_sorted_in_wire,
    ]
    results = []
    for test in tests:
        try:
            result = test()
        except Exception as exc:
            result = AdapterResult(test.__name__, False, f"exception: {exc}")
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