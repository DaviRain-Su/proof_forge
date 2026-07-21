"""SPEC-TASKQUAL-001 §8.4 protected production adapter.

The protected adapter is the policy-pinned production consumer. It:
1. Obtains the exact current production policy ref/store snapshot and
   revocation records from the candidate-external authority store.
2. Obtains a trusted verification instant from a trusted clock.
3. Obtains live eligible handoff/FD/session/peer provenance.
4. Safe-opens C/D archives and authenticated Git objects.
5. Obtains immutable review reports.
6. Obtains resolved command/tool/probe/sandbox/verifier/build-policy bytes.
7. Constructs the canonical production bundle per §8.2.
8. Calls the same pure verifier.
9. Additionally proves the provenance/currentness properties.

Any step failure does not return Verified. The protected adapter is the
only type that can claim ``production-candidate-bound`` and be accepted
by docs-check.

This module provides the adapter framework. The actual authority store,
trusted clock, and live session access are provided by the caller via
dependency injection — the adapter itself is pure with respect to the
provided inputs.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Tuple

import bootstrap_task_objects as _BTO
import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV

Rejected = _BTO.Rejected
TASKQUAL_REJECTION = _TQO.TASKQUAL_REJECTION

Digest = _BTO.Digest
ContentRef = _BTO.ContentRef
CandidateIdentity = _BTO.CandidateIdentity

canonical_pf_jcs = _BTO.canonical_pf_jcs
domain_digest = _TQO.domain_digest
plain_sha256_digest = _TQO.plain_sha256_digest
digest_to_wire = _TQO.digest_to_wire
content_ref_to_wire = _TQO.content_ref_to_wire


# ---------------------------------------------------------------------------
# Protected acceptance result
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ProtectedTaskQualificationAcceptanceV1:
    schema: str
    id: str
    version: str
    authorityClass: str  # "production-candidate-bound"
    operation: str
    pureProjectionDigest: Digest
    bundleDigest: Digest
    subjectDigest: Digest
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity | None
    trustedVerificationInstant: str
    adapter: _TQO.VerifierIdentityV1
    productionProfileDigest: Digest
    productionProfilePin: ContentRef
    provenanceRefs: Tuple[ContentRef, ...]
    signatures: Tuple[_TQO.ApprovalSignatureV1, ...]


PROTECTED_ACCEPTANCE_SCHEMA = "proof-forge.protected-task-qualification-acceptance.v1"
DOMAIN_PURE_PROJECTION = _TQO.DOMAIN_PURE_PROJECTION
DOMAIN_PROTECTED_ACCEPTANCE = _TQO.DOMAIN_PROTECTED_ACCEPTANCE
DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT = _TQO.DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT
DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE = _TQO.DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE


# ---------------------------------------------------------------------------
# Protected adapter input
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ProtectedAdapterInput:
    """Input to the protected adapter.

    All fields are obtained from candidate-external sources by the caller.
    The adapter itself does not access the filesystem, network, or any
    ambient state — it only uses what the caller provides.
    """
    # The pure verifier result (from verify_*_v1)
    pure_verified: object  # VerifiedTaskQualificationV1 | VerifiedTaskCompletionV1 | ...
    # The canonical bundle and subject bytes
    bundle_bytes: bytes
    subject_bytes: bytes
    # The trusted verification instant (from trusted clock)
    trusted_verification_instant: str
    # The adapter verifier identity
    adapter: _TQO.VerifierIdentityV1
    # The production profile
    production_profile: _TQO.ProductionVerificationProfileV1
    # The production profile pin
    production_profile_pin: _TQO.ProductionVerificationProfilePinV1
    # Provenance refs (clock/store/safe-open Git/archive/review/live-session attestations)
    provenance_refs: Tuple[ContentRef, ...]
    # The authority policy principals for signing
    authority_principals: dict  # keyId -> principal
    # The signing keys (seeds) for signing
    signing_seeds: dict  # keyId -> seed bytes


# ---------------------------------------------------------------------------
# Protected adapter
# ---------------------------------------------------------------------------

def build_protected_acceptance(
    inp: ProtectedAdapterInput,
    operation: str,
    task_id: str,
    closeout_candidate: CandidateIdentity | None = None,
) -> ProtectedTaskQualificationAcceptanceV1 | Rejected:
    """Build a ProtectedTaskQualificationAcceptanceV1.

    This is the protected adapter. It takes the pure verifier result and
    wraps it with provenance/currentness attestations. The result is signed
    by the authority policy principals.

    Returns ProtectedTaskQualificationAcceptanceV1 on success, Rejected on failure.
    """
    try:
        return _build_protected_acceptance(inp, operation, task_id, closeout_candidate)
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"protected adapter: {exc}")


def _build_protected_acceptance(
    inp: ProtectedAdapterInput,
    operation: str,
    task_id: str,
    closeout_candidate: CandidateIdentity | None,
) -> ProtectedTaskQualificationAcceptanceV1:
    # §8.4 binding checks before any digest/signature work. These enforce
    # the candidate-external profile↔adapter↔policy↔bundle equality that the
    # pure verifier alone cannot check (it only sees the bundle).
    _verify_profile_binding(inp)

    # Compute the pure projection digest.
    # The pure projection is the PF-JCS of the complete §8.1 Verified record
    # (not a subset): every field of the pure verifier's result is bound by
    # SHA-256("pf.taskqual.pure-projection.v1" || NUL || PF-JCS(Verified)).
    pure_verified = inp.pure_verified
    pure_projection = _serialize_pure_projection(pure_verified)
    pure_projection_digest = domain_digest(DOMAIN_PURE_PROJECTION, pure_projection)

    # Compute bundle and subject digests (plain SHA-256 of exact input bytes).
    bundle_digest = plain_sha256_digest(inp.bundle_bytes)
    subject_digest = plain_sha256_digest(inp.subject_bytes)

    # Compute production profile digest under §8.2 profile domain.
    profile_wire = _TQO.production_profile_to_wire(inp.production_profile)
    production_profile_digest = domain_digest(_TQO.DOMAIN_PRODUCTION_PROFILE, profile_wire)

    # Compute production profile pin ref under the §8.2 pin domain
    # (pf.taskqual.production-profile-pin.v1), not the protected-acceptance
    # domain. The pin has its own accepted full-digest domain; using the
    # protected-acceptance domain would misbind the pin to the wrong
    # statement and let a forged pin satisfy docs-check.
    pin_ref = _TQO.production_profile_pin_content_ref(
        inp.production_profile_pin)

    # §8.4: provenanceRefs must be nonempty and sorted by
    # (schema, id, version, digest) ASCII ascending, with exact coverage of
    # clock/store/safe-open Git/archive/review/live-session attestations.
    provenance_refs_sorted = _normalize_provenance_refs(inp.provenance_refs)

    # Build the protected acceptance object (unsigned), with the §8.4 fixed
    # field order. The preCloseCandidate/closeoutCandidate use the §1
    # archiveSha256 spelling that matches the Verified records.
    task_suffix = task_id.lower().replace("task-", "")
    protected_id = f"protected-task-qualification-{operation}-{task_suffix}"

    obj = {
        "schema": PROTECTED_ACCEPTANCE_SCHEMA,
        "id": protected_id,
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": operation,
        "pureProjectionDigest": digest_to_wire(pure_projection_digest),
        "bundleDigest": digest_to_wire(bundle_digest),
        "subjectDigest": digest_to_wire(subject_digest),
        "preCloseCandidate": _TQO.candidate_identity_to_wire(
            pure_verified.preCloseCandidate),
        "closeoutCandidate": (
            _TQO.candidate_identity_to_wire(closeout_candidate)
            if closeout_candidate is not None
            else None
        ),
        "trustedVerificationInstant": inp.trusted_verification_instant,
        "adapter": _TQO.verifier_identity_to_wire(inp.adapter),
        "productionProfileDigest": digest_to_wire(production_profile_digest),
        "productionProfilePin": content_ref_to_wire(pin_ref),
        "provenanceRefs": [content_ref_to_wire(r) for r in provenance_refs_sorted],
        "signatures": [],
    }

    # Sign the protected acceptance. The unsigned statement is the object
    # with an empty signatures array; domain_digest applies PF-JCS
    # canonicalization internally, so the signature binds the canonical
    # bytes (sorted keys, no whitespace) regardless of dict insertion order.
    import bootstrap_task_producers as _BTP
    unsigned = dict(obj)
    unsigned["signatures"] = []
    statement_digest = domain_digest(
        DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT, unsigned)
    message = DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE + b"\x00" + statement_digest.bytes

    sigs = []
    signing_keys = sorted(
        ((k, v) for k, v in inp.signing_seeds.items()),
        key=lambda kv: kv[0])
    for key_id, seed in signing_keys:
        if key_id not in inp.authority_principals:
            _BTO._reject(f"protected adapter: keyId '{key_id}' not in authority principals")
        sig = _BTP.sign_ed25519(seed, message)
        sigs.append(_TQO.ApprovalSignatureV1(
            keyId=key_id,
            algorithm="ed25519",
            signature=sig,
        ))

    # Signatures must be sorted by keyId (§1). The signing loop already
    # iterates in keyId order, but enforce uniqueness/sort defensively.
    sigs.sort(key=lambda s: s.keyId)
    if len({s.keyId for s in sigs}) != len(sigs):
        _BTO._reject("protected adapter: duplicate keyId in signatures")

    obj["signatures"] = [_TQO.approval_signature_to_wire(s) for s in sigs]

    # Build the final protected acceptance object
    return ProtectedTaskQualificationAcceptanceV1(
        schema=obj["schema"],
        id=obj["id"],
        version=obj["version"],
        authorityClass=obj["authorityClass"],
        operation=obj["operation"],
        pureProjectionDigest=pure_projection_digest,
        bundleDigest=bundle_digest,
        subjectDigest=subject_digest,
        preCloseCandidate=pure_verified.preCloseCandidate,
        closeoutCandidate=closeout_candidate,
        trustedVerificationInstant=inp.trusted_verification_instant,
        adapter=inp.adapter,
        productionProfileDigest=production_profile_digest,
        productionProfilePin=pin_ref,
        provenanceRefs=tuple(provenance_refs_sorted),
        signatures=tuple(sigs),
    )


def _verify_profile_binding(inp: "ProtectedAdapterInput") -> None:
    """Enforce §8.4 candidate-external profile↔adapter↔policy equality.

    The pure verifier only sees the bundle; it cannot check that the external
    production profile's adapter matches the protected adapter that will sign
    the acceptance, or that the profile/pin authorityPolicy matches the
    bundle's expectedAuthorityPolicy (now carried on the Verified record).
    These checks close that gap so a swapped adapter or mismatched policy
    cannot produce an accepted ProtectedTaskQualificationAcceptanceV1.
    """
    # §8.4: adapter executable/closure/buildPolicy must equal expectedAdapter
    # (the adapter embedded in the production profile) field-by-field.
    profile_adapter = inp.production_profile.adapter
    if inp.adapter != profile_adapter:
        _BTO._reject(
            "protected adapter: adapter != production_profile.adapter "
            "(executable/closure/buildPolicy/sourceDigest must match)")

    # §8.2: the production profile's expectedAuthorityPolicy must equal the
    # bundle's expectedAuthorityPolicy, which the pure verifier projected as
    # Verified*.authorityPolicy. A mismatch would let a profile signed under
    # a different policy satisfy docs-check via the protected adapter.
    if inp.production_profile.expectedAuthorityPolicy != inp.pure_verified.authorityPolicy:
        _BTO._reject(
            "protected adapter: production_profile.expectedAuthorityPolicy "
            "!= bundle authorityPolicy")

    # §8.2: the pin's authorityPolicy must equal the profile's
    # expectedAuthorityPolicy and the pin's profile ref must equal the
    # recomputed production profile content ref. The pure verifier checks
    # the bundle's embedded profile; the adapter checks the external pin
    # against the same profile.
    if inp.production_profile_pin.authorityPolicy != inp.production_profile.expectedAuthorityPolicy:
        _BTO._reject(
            "protected adapter: pin.authorityPolicy != "
            "production_profile.expectedAuthorityPolicy")
    expected_profile_ref = _TQO.production_profile_content_ref(
        inp.production_profile)
    if inp.production_profile_pin.profile != expected_profile_ref:
        _BTO._reject(
            "protected adapter: pin.profile != recomputed "
            "production_profile content ref")


def _normalize_provenance_refs(refs) -> tuple:
    """§8.4: provenanceRefs must be nonempty, unique, and ASCII-sorted by
    (schema, id, version, digest). Return the normalized tuple.
    """
    if not refs:
        _BTO._reject("protected adapter: provenanceRefs must be nonempty")
    normalized = tuple(refs)
    normalized = tuple(sorted(
        normalized,
        key=lambda r: (r.schema, r.id, r.version, r.digest.bytes.hex())))
    # Uniqueness by (schema, id, version, digest)
    seen = set()
    for r in normalized:
        key = (r.schema, r.id, r.version, r.digest.bytes.hex())
        if key in seen:
            _BTO._reject("protected adapter: duplicate provenanceRef")
        seen.add(key)
    return normalized


def _serialize_pure_projection(verified) -> dict:
    """Serialize a §8.1 Verified record to its complete wire form.

    The projection must include every field of the pure verifier result so
    that pureProjectionDigest binds the complete verification outcome, not
    a subset. The wire encoders live in ``task_qualification_objects`` and
    emit the exact field order/spelling required by SPEC-TASKQUAL-001 §8.1.
    """
    if isinstance(verified, _TQV.VerifiedTaskQualificationV1):
        return _TQO.verified_task_qualification_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedTaskCompletionV1):
        return _TQO.verified_task_completion_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapApprovalV1):
        return _TQO.verified_d0_10_bootstrap_approval_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapCompletionV1):
        return _TQO.verified_d0_10_bootstrap_completion_to_wire(verified)
    _BTO._reject("protected adapter: unknown verified type")


def protected_acceptance_to_wire(pa: ProtectedTaskQualificationAcceptanceV1) -> dict:
    """Convert a ProtectedTaskQualificationAcceptanceV1 to wire format."""
    return {
        "schema": pa.schema,
        "id": pa.id,
        "version": pa.version,
        "authorityClass": pa.authorityClass,
        "operation": pa.operation,
        "pureProjectionDigest": digest_to_wire(pa.pureProjectionDigest),
        "bundleDigest": digest_to_wire(pa.bundleDigest),
        "subjectDigest": digest_to_wire(pa.subjectDigest),
        "preCloseCandidate": {
            "commit": pa.preCloseCandidate.commit,
            "treeObjectId": pa.preCloseCandidate.treeObjectId,
            "archiveSha256": digest_to_wire(pa.preCloseCandidate.archiveDigest),
        },
        "closeoutCandidate": (
            {
                "commit": pa.closeoutCandidate.commit,
                "treeObjectId": pa.closeoutCandidate.treeObjectId,
                "archiveSha256": digest_to_wire(pa.closeoutCandidate.archiveDigest),
            }
            if pa.closeoutCandidate is not None
            else None
        ),
        "trustedVerificationInstant": pa.trustedVerificationInstant,
        "adapter": _TQO.verifier_identity_to_wire(pa.adapter),
        "productionProfileDigest": digest_to_wire(pa.productionProfileDigest),
        "productionProfilePin": content_ref_to_wire(pa.productionProfilePin),
        "provenanceRefs": [content_ref_to_wire(r) for r in pa.provenanceRefs],
        "signatures": [_TQO.approval_signature_to_wire(s) for s in pa.signatures],
    }


def protected_acceptance_content_ref(pa: ProtectedTaskQualificationAcceptanceV1) -> ContentRef:
    """Compute the ContentRef for a ProtectedTaskQualificationAcceptanceV1."""
    wire = protected_acceptance_to_wire(pa)
    digest = domain_digest(DOMAIN_PROTECTED_ACCEPTANCE, wire)
    return ContentRef(schema=pa.schema, id=pa.id, version=pa.version, digest=digest)