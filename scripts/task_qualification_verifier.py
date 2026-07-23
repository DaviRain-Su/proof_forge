"""SPEC-TASKQUAL-001 §8.1 pure content verifier.

This module implements the four pure verifier functions defined in
SPEC-TASKQUAL-001 §8.1:

    verify_task_qualification_v1(contentBundleBytes, subjectBytes)
        -> VerifiedTaskQualificationV1 | RejectedV1
    verify_task_completion_receipt_v1(contentBundleBytes, subjectBytes)
        -> VerifiedTaskCompletionV1 | RejectedV1
    verify_d0_10_bootstrap_v1(contentBundleBytes, subjectBytes)
        -> VerifiedD0_10BootstrapApprovalV1 | RejectedV1
    verify_d0_10_bootstrap_receipt_v1(contentBundleBytes, subjectBytes)
        -> VerifiedD0_10BootstrapCompletionV1 | RejectedV1

Each verifier is a pure consumer: it takes exactly two positional byte
arguments (the canonical content bundle and the subject object), runs a
15-stage pipeline, and returns either a Verified record or a RejectedV1.
No kwargs, defaults, overloads, path access, env access, or typed shortcuts.

The 15 stages (in fixed order) are:
    bounds, bundle, profile, members, documents, candidate, policy,
    command, evidence, dependencies, reviews, controls, patch,
    signatures, projection

A failure at any stage returns RejectedV1 with the stage name; no later
stage's hash/curve work runs.
"""

from __future__ import annotations

import datetime as _datetime
import hashlib
import json
import re
from dataclasses import dataclass
from typing import Tuple

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import evidence_v1_core as _EVIDENCE
import formal_evidence as _FORMAL
import revocation_ledger as _REVOCATION
import task_qualification_objects as _TQO

Rejected = _BTO.Rejected
TASKQUAL_REJECTION = _TQO.TASKQUAL_REJECTION

# Re-export key types
Digest = _BTO.Digest
ContentRef = _BTO.ContentRef
CandidateIdentity = _BTO.CandidateIdentity

canonical_pf_jcs = _BTO.canonical_pf_jcs
decode_canonical_pf_jcs = _BTO.decode_canonical_pf_jcs
domain_digest = _TQO.domain_digest
plain_sha256_digest = _TQO.plain_sha256_digest
digest_to_wire = _TQO.digest_to_wire
content_ref_to_wire = _TQO.content_ref_to_wire


def _content_ref_record_equal(left: object, right: object) -> bool:
    """Compare ContentRef ABI values across exact-path module namespaces."""
    try:
        return (
            left.schema == right.schema
            and left.id == right.id
            and left.version == right.version
            and left.digest.algorithm == right.digest.algorithm
            and left.digest.bytes == right.digest.bytes
        )
    except AttributeError:
        return False


# Re-export object types
TaskQualificationV1 = _TQO.TaskQualificationV1
TaskCompletionReceiptV1 = _TQO.TaskCompletionReceiptV1
D0_10BootstrapApprovalV1 = _TQO.D0_10BootstrapApprovalV1
D0_10BootstrapReceiptV1 = _TQO.D0_10BootstrapReceiptV1
GovernanceBootstrapCompletionV1 = _TQO.GovernanceBootstrapCompletionV1
TaskQualificationContentBundleV1 = _TQO.TaskQualificationContentBundleV1
FixturePolicyV1 = _TQO.FixturePolicyV1
ProductionVerificationProfileV1 = _TQO.ProductionVerificationProfileV1
FixtureVerificationProfileV1 = _TQO.FixtureVerificationProfileV1
AllowedCloseoutPatchV1 = _TQO.AllowedCloseoutPatchV1
CloseoutFileSetV1 = _TQO.CloseoutFileSetV1
SemanticCloseoutFileSetV1 = _TQO.SemanticCloseoutFileSetV1
TaskQualificationGateV1 = _TQO.TaskQualificationGateV1
TaskCommandPolicyV1 = _TQO.TaskCommandPolicyV1
VerifierIdentityV1 = _TQO.VerifierIdentityV1
ApprovalSignatureV1 = _TQO.ApprovalSignatureV1
IndependentReviewRefV1 = _TQO.IndependentReviewRefV1
EvidenceRefV1 = _TQO.EvidenceRefV1
DependencyCompletionRefV1 = _TQO.DependencyCompletionRefV1
ArchiveProjection = _TQO.ArchiveProjection
GitCommitObject = _TQO.GitCommitObject

RFC8032_VECTOR_SEEDS = _TQO.RFC8032_VECTOR_SEEDS

# ---------------------------------------------------------------------------
# §8.1 Verified result records
# ---------------------------------------------------------------------------

PureAuthorityClassV1 = str  # "production-content-verified" | "fixture-non-authoritative"


@dataclass(frozen=True)
class VerifiedTaskQualificationV1:
    taskId: str
    preCloseCandidate: CandidateIdentity
    qualification: TaskQualificationV1
    allowedCloseoutPatch: AllowedCloseoutPatchV1
    authorityPolicy: ContentRef
    verificationInstant: str
    authorityClass: PureAuthorityClassV1


@dataclass(frozen=True)
class VerifiedTaskCompletionV1:
    taskId: str
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity
    qualification: TaskQualificationV1
    receipt: TaskCompletionReceiptV1
    closeoutDiffDigest: Digest
    authorityPolicy: ContentRef
    verificationInstant: str
    authorityClass: PureAuthorityClassV1


@dataclass(frozen=True)
class VerifiedD0_10BootstrapApprovalV1:
    taskId: str  # "TASK-D0-10"
    preCloseCandidate: CandidateIdentity
    approvalDigest: Digest
    allowedCloseoutPatch: AllowedCloseoutPatchV1
    authorityPolicy: ContentRef
    verificationInstant: str
    authorityClass: PureAuthorityClassV1


@dataclass(frozen=True)
class VerifiedD0_10BootstrapCompletionV1:
    taskId: str  # "TASK-D0-10"
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity
    approvalDigest: Digest
    receiptDigest: Digest
    closeoutDiffDigest: Digest
    authorityPolicy: ContentRef
    verificationInstant: str
    authorityClass: PureAuthorityClassV1


# ---------------------------------------------------------------------------
# Stage rejection helper
# ---------------------------------------------------------------------------

_REJECTION_STAGES = (
    "bounds",
    "bundle",
    "profile",
    "members",
    "documents",
    "candidate",
    "policy",
    "command",
    "evidence",
    "dependencies",
    "reviews",
    "controls",
    "patch",
    "signatures",
    "projection",
)


def _reject_stage(stage: str, detail: str) -> Rejected:
    """Return a RejectedV1 with the given stage and detail."""
    return Rejected(TASKQUAL_REJECTION, f"stage={stage} {detail}")


def _exception_detail(exc: BaseException) -> str:
    return exc.detail if isinstance(exc, Rejected) else str(exc)


def _stage_exc(stage: str, exc: BaseException) -> Rejected:
    """Map any exception (Rejected or generic) to a fixed 15-stage rejection."""
    if stage not in _REJECTION_STAGES:
        # This is an implementation fault, but the public wire must still use
        # an accepted stage. Attribute it to bounds rather than minting a new
        # rejection-stage value.
        return _reject_stage("bounds", f"invalid internal stage {stage!r}")
    return _reject_stage(stage, _exception_detail(exc))


# ---------------------------------------------------------------------------
# Stage 1: bounds
# ---------------------------------------------------------------------------

def _check_bounds(content_bundle_bytes: bytes, subject_bytes: bytes) -> None:
    """Check subject/bundle/member/aggregate bounds before any decode."""
    if not isinstance(content_bundle_bytes, (bytes, bytearray)):
        _BTO._reject("contentBundleBytes must be bytes")
    if not isinstance(subject_bytes, (bytes, bytearray)):
        _BTO._reject("subjectBytes must be bytes")
    cb_len = len(content_bundle_bytes)
    sb_len = len(subject_bytes)
    if sb_len < 1:
        _BTO._reject("subjectBytes must be nonempty")
    if sb_len > _TQO.MAX_SUBJECT_BYTES:
        _BTO._reject(f"subjectBytes exceeds {_TQO.MAX_SUBJECT_BYTES}")
    if cb_len < 1:
        _BTO._reject("contentBundleBytes must be nonempty")
    if cb_len > _TQO.MAX_BUNDLE_CANONICAL:
        _BTO._reject(f"contentBundleBytes exceeds {_TQO.MAX_BUNDLE_CANONICAL}")


def _check_aggregate_member_bound(bundle: TaskQualificationContentBundleV1, where: str) -> None:
    """Check the §8.2 aggregate decoded-member bound: the sum of all member
    bytesHex decoded sizes must not exceed MAX_BUNDLE_AGGREGATE (128 MiB).

    Per §8.2 line 440: "展开总计 <=128 MiB". The consumer must scan canonical
    token/hex length before any hex decode, allocation, or curve work.
    """
    aggregate = 0
    for m in bundle.members:
        # Each member's bytesHex is lowercase hex; decoded size = len // 2.
        # The parser already validates bytesHex format and per-member 64 MiB.
        aggregate += len(m.bytesHex) // 2
        if aggregate > _TQO.MAX_BUNDLE_AGGREGATE:
            _BTO._reject(
                f"{where}: aggregate decoded-member bytes {aggregate} > "
                f"{_TQO.MAX_BUNDLE_AGGREGATE} (§8.2)")


def _verify_production_profile_member_bytes(
    member_map: dict,
    profile: ProductionVerificationProfileV1,
    where: str,
) -> None:
    """§8.2 line 497-500: the bundle's embedded verificationProfile canonical
    PF-JCS bytes must逐字 equal the production-profile member's decoded bytes.
    The profile wire is re-canonicalized from the parsed profile (production_
    profile_to_wire is deterministic) and compared to the member's bytesHex.

    The re-computed ContentRef under pf.taskqual.production-profile.v1 must
    equal the member's content ref (the verifier already recomputes member
    content refs via _resolve_typed_member; this check additionally asserts the
    profile wire bytes equal the member bytes, prohibiting two semantically-
    equivalent but byte-different profiles).
    """
    member = member_map.get("production-profile")
    if member is None:
        _BTO._reject(f"{where}: production-profile member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: production-profile must be typed-content")
    # Re-canonicalize the parsed profile to PF-JCS bytes.
    profile_wire = _TQO.production_profile_to_wire(profile)
    profile_bytes = canonical_pf_jcs(profile_wire)
    member_bytes = bytes.fromhex(member.bytesHex)
    if profile_bytes != member_bytes:
        _BTO._reject(
            f"{where}: bundle verificationProfile PF-JCS bytes != "
            f"production-profile member bytes (§8.2)")
    # Verify the member content ref recomputes from the member bytes under
    # the production-profile domain.
    try:
        member_obj = decode_canonical_pf_jcs(member_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: production-profile member decode failed: {exc}")
    recomputed = _TQO.recompute_typed_content_ref(member.content.schema, member_obj)
    if recomputed != member.content:
        _BTO._reject(f"{where}: production-profile member bytes do not recompute to member.content")


# ---------------------------------------------------------------------------
# Stage 2: bundle decode
# ---------------------------------------------------------------------------

def _decode_bundle(content_bundle_bytes: bytes) -> TaskQualificationContentBundleV1:
    """Decode the content bundle from canonical PF-JCS bytes."""
    try:
        obj = _TQO.decode_taskqualification_large_jcs(content_bundle_bytes)
    except Exception as exc:
        _BTO._reject(f"bundle decode failed: {exc}")
    return _TQO.parse_content_bundle(obj, "bundle")


# ---------------------------------------------------------------------------
# Stage 3: profile verification
# ---------------------------------------------------------------------------

def _verify_profile(bundle: TaskQualificationContentBundleV1) -> tuple:
    """Stage 3: structural verification of the verification profile.

    Per §8.2, Stage 3 is **structural only** — no curve work. The production
    profile signatures are verified in Stage 7 (policy) after the authority
    policy is resolved, using ``_verify_production_profile_signatures`` with
    the parsed policy principals. This function only checks namespace,
    operation, and expectedAuthorityPolicy equality.
    """
    profile = bundle.verificationProfile
    if isinstance(profile, ProductionVerificationProfileV1):
        # Verify namespace
        if profile.namespace != _TQO.FIXTURE_PRODUCTION_NAMESPACE:
            _BTO._reject(f"profile.namespace must be {_TQO.FIXTURE_PRODUCTION_NAMESPACE}")
        # §8.2: profile.operation must equal bundle.operation逐字.
        if profile.operation != bundle.operation:
            _BTO._reject("profile.operation != bundle.operation")
        # Verify expectedAuthorityPolicy matches
        if profile.expectedAuthorityPolicy != bundle.expectedAuthorityPolicy:
            _BTO._reject("profile.expectedAuthorityPolicy != bundle.expectedAuthorityPolicy")
        authority_class = "production-content-verified"
        policy_ref = bundle.expectedAuthorityPolicy
    elif isinstance(profile, FixtureVerificationProfileV1):
        # Fixture profile — verify namespace and keySet
        if profile.namespace != _TQO.FIXTURE_NAMESPACE:
            _BTO._reject(f"profile.namespace must be {_TQO.FIXTURE_NAMESPACE}")
        if profile.keySet != _TQO.FIXTURE_KEYSET:
            _BTO._reject(f"profile.keySet must be {_TQO.FIXTURE_KEYSET}")
        if profile.fixturePolicy != bundle.expectedAuthorityPolicy:
            _BTO._reject("profile.fixturePolicy != bundle.expectedAuthorityPolicy")
        authority_class = "fixture-non-authoritative"
        policy_ref = bundle.expectedAuthorityPolicy
    else:
        _BTO._reject("profile: unknown type")
    return (profile, authority_class, policy_ref)


def _verify_profile_task_id(profile, subject_task_id: str, where: str) -> None:
    """§8.2: profile.taskId must equal subject.taskId逐字 (production profiles only)."""
    if isinstance(profile, ProductionVerificationProfileV1):
        if profile.taskId != subject_task_id:
            _BTO._reject(f"{where}: production_profile.taskId != subject.taskId")


def _verify_profile_gate_set_digest(
    profile: ProductionVerificationProfileV1,
    operation: str,
    gate_ids: tuple,
    where: str,
) -> None:
    """§8.2: recompute full gateSetDigest from subject gates and exact-compare
    to ``profile.gateSetDigest``.

    The gate IDs must be canonical (ASCII ascending sorted and unique).  The
    recompute uses the same ``build_gate_set_entries`` / ``compute_gate_set_digest``
    as the profile builder, so a profile whose gateSetDigest was computed from
    a different gate set (or a different ordering) will be rejected.

    Any same-48-hex-prefix but different-full-digest collision is rejected
    because the comparison is on the full 32-byte digest, not the 192-bit
    prefix used only for bounded IDs.
    """
    # Gate IDs must be canonical sorted and unique.
    gate_ids_list = list(gate_ids)
    if gate_ids_list != sorted(gate_ids_list):
        _BTO._reject(f"{where}: gate IDs not ASCII ascending sorted")
    if len(set(gate_ids_list)) != len(gate_ids_list):
        _BTO._reject(f"{where}: gate IDs not unique")
    computed = _TQO.compute_gate_set_digest(operation, tuple(gate_ids_list))
    if computed.bytes != profile.gateSetDigest.bytes:
        _BTO._reject(
            f"{where}: recomputed gateSetDigest != profile.gateSetDigest "
            f"(same-prefix collision or wrong gate set)")


def _verify_profile_artifacts_coverage(
    profile: ProductionVerificationProfileV1,
    operation: str,
    gate_ids: tuple,
    where: str,
) -> None:
    """§8.2: ``profile.artifacts`` must exact-cover the operation's production
    artifact logical roles.

    - task-qualification / d0-10-bootstrap-approval: per gate exactly 12
      gate-keyed artifact roles; d0-10 approval adds 6 top-level roles.
    - task-completion / d0-10-bootstrap-receipt: exactly zero artifacts.

    Missing, extra, duplicate, or wrong-role entries are rejected.  Artifact
    roles must not be raw/archive/git/review/control wrapper roles.
    """
    expected_roles = _TQO.operation_artifact_roles(operation, gate_ids)
    actual_roles = tuple(a.role for a in profile.artifacts)
    if actual_roles != expected_roles:
        missing = set(expected_roles) - set(actual_roles)
        extra = set(actual_roles) - set(expected_roles)
        _BTO._reject(
            f"{where}: artifacts do not exact-cover operation roles "
            f"(missing={sorted(missing)}, extra={sorted(extra)})")


def _verify_production_profile_signatures(profile: ProductionVerificationProfileV1, policy_obj, where: str) -> None:
    """Verify the production profile signatures against the authority policy principals.

    Per §8.2, the production profile is signed by the authority policy principals
    with statement domain pf.taskqual.production-profile-statement.v1, signature
    message domain pf.taskqual.production-profile-signature.v1, and full digest
    domain pf.taskqual.production-profile.v1 under the §1 fixed
    Architecture+Quality+Security rule.

    This function is called after the authority policy is resolved (stage 7),
    so the principal public keys are available for signature verification.
    """
    # §1: signatures count 3..256, sorted by keyId ascending, unique.
    # The parser enforces sort+unique; the verifier enforces the bounds
    # (the parser uses MAX_ARRAY=4096, which is too permissive for the
    # §1 signature-specific 3..256 bound).
    _enforce_signature_bounds(profile.signatures, where)

    # Build the unsigned statement (remove signatures field)
    unsigned_wire = _TQO.production_profile_to_wire(profile)
    unsigned_wire_copy = dict(unsigned_wire)
    unsigned_wire_copy["signatures"] = []
    statement_digest = domain_digest(_TQO.DOMAIN_PRODUCTION_PROFILE_STATEMENT, unsigned_wire_copy)
    message = _TQO.DOMAIN_PRODUCTION_PROFILE_SIGNATURE + b"\x00" + statement_digest.bytes

    # Build the principal registry from the policy
    if isinstance(policy_obj, _TQO.FixturePolicyV1):
        principals = {p.keyId: p for p in policy_obj.principals}
        rule = policy_obj.rule
    else:
        # Production policy — use bootstrap_task_objects principals
        principals = {p.keyId: p for p in policy_obj.principals}
        rule = _BTO.ApprovalRuleV1(
            requiredRoles=("architecture", "quality", "security"),
            minimumDistinctSigners=3,
        )

    # Verify each signature (no extra ignored — all signatures are verified)
    signed_roles = set()
    signed_principal_ids = set()
    seen_key_ids = set()
    for sig in profile.signatures:
        if sig.keyId in seen_key_ids:
            _BTO._reject(f"{where}.signatures: duplicate keyId '{sig.keyId}'")
        seen_key_ids.add(sig.keyId)
        if sig.keyId not in principals:
            _BTO._reject(f"{where}.signatures: keyId '{sig.keyId}' not in policy")
        principal = principals[sig.keyId]
        # Verify the Ed25519 signature
        if not _BTP.verify_ed25519(principal.publicKey, message, sig.signature):
            _BTO._reject(f"{where}.signatures: signature verification failed for keyId '{sig.keyId}'")
        signed_roles.update(principal.roles)
        signed_principal_ids.add(principal.principalId)

    # Verify the rule: requiredRoles covered, minimumDistinctSigners met
    if not set(rule.requiredRoles).issubset(signed_roles):
        _BTO._reject(f"{where}.signatures: required roles not covered")
    if len(signed_principal_ids) < rule.minimumDistinctSigners:
        _BTO._reject(f"{where}.signatures: minimum distinct signers not met")


# ---------------------------------------------------------------------------
# Stage 4: members verification
# ---------------------------------------------------------------------------

def _build_member_map(bundle: TaskQualificationContentBundleV1) -> dict:
    """Build a map of role -> member, verifying uniqueness and sorting."""
    member_map = {}
    for m in bundle.members:
        if m.role in member_map:
            _BTO._reject(f"members: duplicate role '{m.role}'")
        member_map[m.role] = m
    return member_map


# ---------------------------------------------------------------------------
# §8.2 operation-specific role set enforcement
# ---------------------------------------------------------------------------

# Required singleton roles per operation (from §8.2 table)
OPERATION_REQUIRED_SINGLETONS = {
    "task-qualification": (
        "phase-4-source", "phase-5-source", "freeze-package-source",
        "candidate-archive", "candidate-commit-object",
        "authority-policy", "revocation-snapshot", "allowed-closeout-patch",
    ),
    "task-completion": (
        "pre-close-archive", "closeout-archive",
        "pre-close-commit-object", "closeout-commit-object",
        "qualification", "allowed-closeout-patch", "closeout-file-set",
        "authority-policy", "revocation-snapshot",
    ),
    "d0-10-bootstrap-approval": (
        "phase-4-source", "phase-5-source", "ruling-source",
        "d0-07-ruling-source", "freeze-package-source",
        "candidate-archive", "candidate-commit-object",
        "authority-policy", "revocation-snapshot",
        "d0-07-governance-completion", "d0-07-completion-archive",
        "d0-07-completion-commit-object", "allowed-closeout-patch",
        "bootstrap-verifier-executable", "bootstrap-verifier-closure",
        "bootstrap-verifier-build-policy", "protected-consumer-executable",
        "protected-consumer-closure", "protected-consumer-build-policy",
    ),
    "d0-10-bootstrap-receipt": (
        "pre-close-archive", "closeout-archive",
        "pre-close-commit-object", "closeout-commit-object",
        "bootstrap-approval", "allowed-closeout-patch", "closeout-file-set",
        "authority-policy", "revocation-snapshot",
    ),
}

# Family prefixes per operation (from §8.2 table)
# Receipt operations have ZERO evidence/review/dependency/ancestry families.
OPERATION_FAMILY_PREFIXES = {
    "task-qualification": (
        "evidence/", "review-report/", "dependency/", "dependency-archive/",
        "dependency-commit-object/", "ancestry-commit/", "revocation-record/",
        "command-policy/", "eligible-stage0-handoff/",
        "session-containment/", "freshness/", "private-scan/",
        "resolved-tool/", "resolved-tool-closure/", "resolved-probe/",
        "sandbox-policy/", "verifier-executable/", "verifier-closure/",
        "verifier-build-policy/", "private-scan-policy/",
        "private-scan-scanner/", "authority-store-service/",
        "host-observation/", "host-profile/",
    ),
    "task-completion": (
        "revocation-record/",
    ),
    "d0-10-bootstrap-approval": (
        "evidence/", "review-report/", "dependency/", "dependency-archive/",
        "dependency-commit-object/", "ancestry-commit/", "revocation-record/",
        "command-policy/", "eligible-stage0-handoff/",
        "session-containment/", "freshness/", "private-scan/",
        "resolved-tool/", "resolved-tool-closure/", "resolved-probe/",
        "sandbox-policy/", "verifier-executable/", "verifier-closure/",
        "verifier-build-policy/", "private-scan-policy/",
        "private-scan-scanner/", "authority-store-service/",
        "host-observation/", "host-profile/",
    ),
    "d0-10-bootstrap-receipt": (
        "revocation-record/",
    ),
}

# Forbidden roles per profile kind
# Fixture operations must NOT have a "production-profile" member.
# Production operations MUST have a "production-profile" member.
FIXTURE_FORBIDDEN_ROLES = ("production-profile",)
PRODUCTION_REQUIRED_ROLES = ("production-profile",)

# §8.2 gate-keyed logical roles. Every declared gate has exactly five
# ordinary control members. Fixture profiles additionally carry exactly twelve
# artifact wrapper members; production profiles carry those twelve roles only
# in the signed profile mapping and must not put them in the bundle.
GATE_KEYED_CONTROL_ROLE_PREFIXES = (
    "command-policy",
    "eligible-stage0-handoff",
    "session-containment",
    "freshness",
    "private-scan",
)
GATE_KEYED_ARTIFACT_ROLE_PREFIXES = tuple(_TQO.GATE_KEYED_ARTIFACT_ROLES)
GATE_KEYED_FAMILY_PREFIXES = tuple(
    f"{prefix}/"
    for prefix in (
        GATE_KEYED_CONTROL_ROLE_PREFIXES + GATE_KEYED_ARTIFACT_ROLE_PREFIXES
    )
)


# §8.2 artifact logical role prefixes — these are bundle members in fixture
# (FixtureResolvedBlobV1 wrappers) but are **not** bundle members in production
# (resolved via signed profile artifacts mapping).  The pure verifier rejects
# any artifact-role member in a production bundle to enforce static isolation
# between the fixture wrapper path and the production mapping path.
PRODUCTION_ARTIFACT_ROLE_PREFIXES = (
    "resolved-tool/",
    "resolved-tool-closure/",
    "resolved-probe/",
    "sandbox-policy/",
    "verifier-executable/",
    "verifier-closure/",
    "verifier-build-policy/",
    "private-scan-policy/",
    "private-scan-scanner/",
    "authority-store-service/",
    "host-observation/",
    "host-profile/",
    # D0-10 top-level artifact roles.
    "bootstrap-verifier-executable",
    "bootstrap-verifier-closure",
    "bootstrap-verifier-build-policy",
    "protected-consumer-executable",
    "protected-consumer-closure",
    "protected-consumer-build-policy",
)


def _verify_member_role_set(
    bundle: TaskQualificationContentBundleV1,
    member_map: dict,
    profile,
    where: str,
) -> None:
    """Verify the §8.2 operation-specific role set and family cardinality."""
    operation = bundle.operation
    required = OPERATION_REQUIRED_SINGLETONS.get(operation, ())
    family_prefixes = OPERATION_FAMILY_PREFIXES.get(operation, ())

    # Check required singletons are present
    # §8.2: in fixture, ALL required singletons (including artifact roles)
    # are bundle members.  In production, artifact-role singletons are
    # resolved via profile mapping and must NOT be bundle members; only
    # non-artifact singletons are required as bundle members.
    is_production = isinstance(profile, ProductionVerificationProfileV1)
    for role in required:
        is_artifact = any(
            role == p or role.startswith(p)
            for p in PRODUCTION_ARTIFACT_ROLE_PREFIXES
        )
        if is_production and is_artifact:
            # Production: artifact singletons are NOT bundle members.
            if role in member_map:
                _BTO._reject(
                    f"{where}: production profile forbids artifact singleton "
                    f"'{role}' as bundle member (resolved via profile mapping)")
            continue
        if role not in member_map:
            _BTO._reject(f"{where}: missing required singleton '{role}' for operation '{operation}'")

    # Check for forbidden roles
    if isinstance(profile, FixtureVerificationProfileV1):
        for role in FIXTURE_FORBIDDEN_ROLES:
            if role in member_map:
                _BTO._reject(f"{where}: fixture profile forbids role '{role}'")
    elif isinstance(profile, ProductionVerificationProfileV1):
        for role in PRODUCTION_REQUIRED_ROLES:
            if role not in member_map:
                _BTO._reject(f"{where}: production profile requires role '{role}'")
        # §8.2: production artifacts are resolved via signed profile mapping,
        # NOT as bundle members.  Reject any artifact-role member to enforce
        # static isolation between fixture wrapper path and production mapping.
        for role in member_map:
            for prefix in PRODUCTION_ARTIFACT_ROLE_PREFIXES:
                if role == prefix or role.startswith(prefix):
                    _BTO._reject(
                        f"{where}: production profile forbids artifact-role "
                        f"bundle member '{role}' (resolved via profile mapping)")

    # Check that all member roles are either required singletons or valid family members
    for role in member_map:
        if role in required:
            continue
        if is_production and role in PRODUCTION_REQUIRED_ROLES:
            continue
        # Check if it's a valid family member
        is_valid_family = any(role.startswith(prefix) for prefix in family_prefixes)
        if not is_valid_family:
            _BTO._reject(f"{where}: role '{role}' is not a valid singleton or family member for operation '{operation}'")


def _verify_gate_keyed_roles_match_gates(
    member_map: dict,
    gates: tuple,
    profile,
    where: str,
) -> None:
    """Require the complete §8.2 per-gate role matrix, not merely one role
    carrying each gate suffix.

    Every gate has exactly five ordinary controls. Fixture bundles additionally
    have the twelve role-owned ``FixtureResolvedBlobV1`` members; production
    bundles must omit those members because the signed profile mapping owns
    them. Member-role uniqueness is already enforced during bundle parsing.
    """
    prefixes = list(GATE_KEYED_CONTROL_ROLE_PREFIXES)
    if isinstance(profile, FixtureVerificationProfileV1):
        prefixes.extend(GATE_KEYED_ARTIFACT_ROLE_PREFIXES)
    expected_roles = {
        f"{prefix}/{gate.gateId}"
        for gate in gates
        for prefix in prefixes
    }
    actual_roles = {
        role
        for role in member_map
        if any(role.startswith(prefix) for prefix in GATE_KEYED_FAMILY_PREFIXES)
    }
    if actual_roles != expected_roles:
        missing = sorted(expected_roles - actual_roles)
        extra = sorted(actual_roles - expected_roles)
        _BTO._reject(
            f"{where}: gate-keyed role matrix mismatch; "
            f"missing={missing}, extra={extra}")


def _verify_typed_member_recompute(member, ref: ContentRef, where: str) -> None:
    """Verify a typed-content member's content ref by recomputing from bytes.

    Per §8.2, the verifier must not trust a stale member.content.digest. It
    decodes the member's bytesHex, recomputes the ContentRef under the
    schema's domain via _TQO.recompute_typed_content_ref, and asserts:

      recomputed_ref == member.content == ref

    Any disagreement is a `members` rejection.
    """
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: decode failed: {exc}")
    recomputed = _TQO.recompute_typed_content_ref(member.content.schema, obj)
    if recomputed != member.content:
        _BTO._reject(f"{where}: bytesHex does not recompute to member.content")
    if member.content != ref:
        _BTO._reject(f"{where}: content ref mismatch")


def _resolve_typed_member(member_map: dict, role: str, ref: ContentRef, where: str) -> tuple:
    """Resolve a typed-content member to (decoded_obj, content_ref, bytes).

    Recomputes the ContentRef from the member's bytesHex under the schema's
    domain and asserts recomputed == member.content == ref. Returns the
    decoded object, the recomputed ContentRef, and the raw bytes.
    """
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: member '{role}' decode failed: {exc}")
    recomputed = _TQO.recompute_typed_content_ref(member.content.schema, obj)
    if recomputed != member.content:
        _BTO._reject(f"{where}: member '{role}' bytesHex does not recompute to member.content")
    if member.content != ref:
        _BTO._reject(f"{where}: member '{role}' content ref mismatch")
    return (obj, member.content, raw_bytes)


def _verify_receipt_qualification_member(
    member_map: dict,
    qual_ref: _TQO.TaskQualificationRefV1,
    receipt_task_id: str,
    where: str,
) -> _TQO.TaskQualificationV1:
    """§8.1/§8.2: authenticate the signed prior qualification subject in a
    task-completion bundle.

    Receipt operations do not replay the prior qualification closure
    (candidate/gates/evidence/reviews are not re-verified), but the bundle's
    ``qualification`` typed-content member must be authenticated by digest
    join: its bytesHex must recompute to a ContentRef whose id and digest
    exactly equal ``receipt.qualification.id`` / ``receipt.qualification.digest``,
    and the qualification ref's taskId must equal both the receipt's taskId
    and the decoded qualification object's taskId.

    Returns the parsed ``TaskQualificationV1`` for the projection.
    """
    role = "qualification"
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: member '{role}' decode failed: {exc}")
    # Recompute the ContentRef from the member bytes under the qualification
    # schema domain so a stale member.content cannot be trusted.
    recomputed = _TQO.recompute_typed_content_ref(member.content.schema, obj)
    if recomputed != member.content:
        _BTO._reject(f"{where}: member '{role}' bytesHex does not recompute to member.content")
    # Join the member content ref to the receipt qualification ref. The ref
    # is a TaskQualificationRefV1{taskId, id, digest} (no schema/version), so
    # compare id and digest explicitly.
    if member.content.id != qual_ref.id:
        _BTO._reject(f"{where}: qualification id mismatch")
    if member.content.digest != qual_ref.digest:
        _BTO._reject(f"{where}: qualification digest mismatch")
    # The qualification ref's taskId must equal the receipt's taskId.
    if qual_ref.taskId != receipt_task_id:
        _BTO._reject(f"{where}: qualification ref taskId does not equal receipt taskId")
    # Parse the decoded object as a TaskQualificationV1 and assert its taskId
    # agrees with the ref, so the prior subject is bound to the same task.
    qualification = _TQO.parse_qualification(obj, f"{where}: qualification")
    if qualification.taskId != qual_ref.taskId:
        _BTO._reject(f"{where}: decoded qualification taskId does not equal ref taskId")
    return qualification


def _resolve_raw_member(member_map: dict, role: str, where: str, domain: bytes = None) -> tuple:
    """Resolve a raw-source member to (raw_bytes, raw_doc_ref).

    If domain is None, the digest is plain SHA-256 of the raw bytes.
    If domain is provided, the digest is SHA-256(domain || NUL || raw bytes).
    """
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.RawContentMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be raw-source")
    raw_bytes = bytes.fromhex(member.bytesHex)
    # Recompute the raw document digest
    if domain is not None:
        computed = _TQO.domain_digest_raw(domain, raw_bytes)
    else:
        computed = plain_sha256_digest(raw_bytes)
    if computed.bytes != member.raw.digest.bytes:
        _BTO._reject(f"{where}: member '{role}' raw digest mismatch")
    return (raw_bytes, member.raw)


def _resolve_archive_member(member_map: dict, role: str, where: str) -> tuple:
    """Resolve an archive member to (raw_bytes, archive_sha256)."""
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.ArchiveMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be archive")
    raw_bytes = bytes.fromhex(member.bytesHex)
    computed = plain_sha256_digest(raw_bytes)
    if computed.bytes != member.archiveSha256.bytes:
        _BTO._reject(f"{where}: member '{role}' archive digest mismatch")
    return (raw_bytes, member.archiveSha256)


def _resolve_git_object_member(member_map: dict, role: str, where: str) -> tuple:
    """Resolve a git-object member to (raw_bytes, object_id)."""
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.GitObjectMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be git-object")
    raw_bytes = bytes.fromhex(member.bytesHex)
    # Recompute the git object SHA-1
    if member.objectType == "commit":
        computed = _TQO.git_sha1_object("commit", raw_bytes)
        if computed != member.objectId:
            _BTO._reject(f"{where}: member '{role}' git object id mismatch")
    else:
        _BTO._reject(f"{where}: member '{role}' objectType must be 'commit'")
    return (raw_bytes, member.objectId)


def _resolve_review_member(member_map: dict, role: str, where: str) -> tuple:
    """Resolve a review member to (raw_bytes, report_digest).

    Review report digest is SHA-256("pf.taskqual.review-report.v1" || NUL || raw bytes).
    """
    if role not in member_map:
        _BTO._reject(f"{where}: member '{role}' missing")
    member = member_map[role]
    if not isinstance(member, _TQO.ReviewMemberV1):
        _BTO._reject(f"{where}: member '{role}' must be review")
    raw_bytes = bytes.fromhex(member.bytesHex)
    import hashlib
    computed = _TQO.Digest(
        algorithm="sha256",
        bytes=hashlib.sha256(_TQO.DOMAIN_REVIEW_REPORT + b"\x00" + raw_bytes).digest(),
    )
    if computed.bytes != member.reportDigest.bytes:
        _BTO._reject(f"{where}: member '{role}' report digest mismatch")
    return (raw_bytes, member.reportDigest)


# ---------------------------------------------------------------------------
# Stage 5: documents verification (PHASE-4/5/ruling/freeze)
# ---------------------------------------------------------------------------

def _verify_phase4_source(member_map: dict, profile, where: str) -> bytes:
    """Verify a PHASE-4 source member and return raw bytes."""
    raw_bytes, raw_ref = _resolve_raw_member(member_map, "phase-4-source", where)
    if isinstance(profile, FixtureVerificationProfileV1):
        expected_path = "fixtures/task-qualification/04-task-breakdown.md"
    else:
        expected_path = "docs/04-task-breakdown.md"
    if raw_ref.path != expected_path:
        _BTO._reject(f"{where}: phase-4-source path must be '{expected_path}'")
    return raw_bytes


def _verify_phase5_source(member_map: dict, profile, where: str) -> bytes:
    """Verify a PHASE-5 source member and return raw bytes."""
    raw_bytes, raw_ref = _resolve_raw_member(member_map, "phase-5-source", where)
    if isinstance(profile, FixtureVerificationProfileV1):
        expected_path = "fixtures/task-qualification/05-test-spec.md"
    else:
        expected_path = "docs/05-test-spec.md"
    if raw_ref.path != expected_path:
        _BTO._reject(f"{where}: phase-5-source path must be '{expected_path}'")
    return raw_bytes


def _verify_freeze_package_source(member_map: dict, profile, where: str) -> bytes:
    """Verify the fixed-path freeze-package source member and return bytes."""
    raw_bytes, raw_ref = _resolve_raw_member(
        member_map, "freeze-package-source", where,
        domain=_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE,
    )
    expected_path = (
        "fixtures/task-qualification/freeze.json"
        if isinstance(profile, FixtureVerificationProfileV1)
        else "docs/governance/task-freeze-packages/TASK-D0-10.json"
    )
    # Production task qualification is task-scoped, so derive the path from
    # the signed production profile rather than hard-coding D0-10 globally.
    if isinstance(profile, ProductionVerificationProfileV1):
        expected_path = (
            f"docs/governance/task-freeze-packages/{profile.taskId}.json")
    if raw_ref.path != expected_path:
        _BTO._reject(
            f"{where}: freeze-package-source path must be '{expected_path}'")
    return raw_bytes


def _parse_freeze_package_source_bytes(raw_bytes: bytes, where: str) -> _TQO.TaskFreezePackageV1:
    """Parse the raw freeze package source bytes (JSON) per §3 to extract the
    fields needed for ancestry graph construction (freezeCommit).

    The freeze-package-source is a raw-source member whose bytes are the JSON
    encoding of TaskFreezePackageV1. It is not PF-JCS-encoded; the digest is a
    raw-bytes domain digest. We parse it as JSON and validate the fields the
    verifier consumes.
    """
    def reject_constant(value):
        raise ValueError(f"non-JSON numeric constant {value}")

    def closed_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate object key {key!r}")
            result[key] = value
        return result

    try:
        text = raw_bytes.decode("utf-8", errors="strict")
        obj = json.loads(
            text, object_pairs_hook=closed_pairs,
            parse_constant=reject_constant)
    except Exception as exc:
        _BTO._reject(f"{where}: freeze package source is not valid strict JSON: {exc}")
    return _TQO.parse_freeze_package(obj, where)


# ---------------------------------------------------------------------------
# Stage 6b: ancestry graph verification (§8.3)
# ---------------------------------------------------------------------------

def _collect_git_commit_objects(
    member_map: dict,
    roles: tuple,
    where: str,
) -> tuple:
    """Resolve a set of git-object member roles to a (commit_sha -> GitCommitObject)
    map. Each member's bytesHex is parsed and its SHA-1 recomputed (via
    _resolve_git_object_member which asserts objectId == recomputed SHA-1).

    Returns the map of commit_sha -> GitCommitObject. Raises Rejected if any
    role is missing or not a git-object member.
    """
    commit_objects = {}
    for role in roles:
        if role not in member_map:
            continue  # optional roles are skipped
        raw_bytes, commit_sha = _resolve_git_object_member(member_map, role, where)
        commit_obj = _TQO.parse_git_commit_object(raw_bytes, where)
        commit_objects[commit_sha] = commit_obj
    return commit_objects


def _collect_ancestry_commit_members(member_map: dict, where: str) -> tuple:
    """Collect all ancestry-commit/* family members and return a
    (commit_sha -> GitCommitObject) map plus a set of the roles seen.

    Per §8.3, ancestry-commit/<40hex> members carry the closure nodes of the
    ancestry graph (commits that are parents of targets or of other closure
    nodes). Each is a git-object member whose objectId is the Git SHA-1.
    """
    extra_commits = {}
    ancestry_roles = []
    for role, member in member_map.items():
        if not role.startswith("ancestry-commit/"):
            continue
        if not isinstance(member, _TQO.GitObjectMemberV1):
            _BTO._reject(f"{where}: member '{role}' must be git-object")
        raw_bytes = bytes.fromhex(member.bytesHex)
        commit_obj = _TQO.parse_git_commit_object(raw_bytes, f"{where}: {role}")
        if commit_obj.commit_sha != member.objectId:
            _BTO._reject(f"{where}: member '{role}' git object id mismatch")
        extra_commits[commit_obj.commit_sha] = commit_obj
        ancestry_roles.append(role)
    return (extra_commits, tuple(ancestry_roles))


def _verify_ancestry_graph(
    member_map: dict,
    candidate_commit: str,
    freeze_commit: str,
    dependencies: tuple,
    where: str,
    extra_target_roles: dict = None,
) -> None:
    """Verify the §8.3 ancestry graph closure.

    The graph is the union of all parent-edge closure paths from consuming C
    to freezeCommit and from C to each direct dependency completionCommit
    (and from C to each extra target, e.g. D0-07 completionCommit). Every
    commit's parents must be recursively represented; any missing parent,
    unreachable target, or extra commit not in the union is rejected. Target
    commits (C, dependency completionCommits, extra targets) must not be
    duplicated as ancestry-commit/*. ancestry-commit/* only carries closure
    nodes.

    extra_target_roles: optional dict of {member_role: commit_sha} for
    operation-specific singleton targets (e.g. d0-07-completion-commit-object).
    """
    # Collect dependency completion commits keyed by taskId.
    dependency_commits = {}
    for dep in dependencies:
        dep_commit_role = f"dependency-commit-object/{dep.taskId}"
        if dep_commit_role not in member_map:
            _BTO._reject(f"{where}: {dep_commit_role} member missing")
        _resolve_git_object_member(member_map, dep_commit_role, where)
        dependency_commits[dep.taskId] = dep.completionCommit

    # Collect extra target commits (e.g. D0-07 completionCommit).
    extra_target_commits = {}
    if extra_target_roles:
        for role, commit_sha in extra_target_roles.items():
            if role not in member_map:
                _BTO._reject(f"{where}: {role} member missing")
            _resolve_git_object_member(member_map, role, where)
            extra_target_commits[role] = commit_sha

    # Collect all git-object members into a commit_sha -> GitCommitObject map.
    # candidate-commit-object carries C; dependency-commit-object/<TASK> carry
    # dependency targets; extra target roles carry their targets;
    # ancestry-commit/* carry closure nodes.
    candidate_commits = _collect_git_commit_objects(
        member_map, ("candidate-commit-object",), where)
    dep_commit_objects = {}
    for dep in dependencies:
        dep_commit_role = f"dependency-commit-object/{dep.taskId}"
        if dep_commit_role in member_map:
            raw_bytes, commit_sha = _resolve_git_object_member(
                member_map, dep_commit_role, where)
            dep_commit_objects[commit_sha] = _TQO.parse_git_commit_object(
                raw_bytes, where)
    extra_target_commit_objects = {}
    if extra_target_roles:
        for role in extra_target_roles:
            if role in member_map:
                raw_bytes, commit_sha = _resolve_git_object_member(
                    member_map, role, where)
                extra_target_commit_objects[commit_sha] = _TQO.parse_git_commit_object(
                    raw_bytes, where)
    extra_commits, _ = _collect_ancestry_commit_members(member_map, where)

    commit_objects = {}
    commit_objects.update(candidate_commits)
    commit_objects.update(dep_commit_objects)
    commit_objects.update(extra_target_commit_objects)
    commit_objects.update(extra_commits)

    # Merge extra targets into dependency_commits for build_ancestry_graph
    # (using the member role as the "task_id" key to distinguish them).
    all_dependency_commits = dict(dependency_commits)
    if extra_target_roles:
        for role, commit_sha in extra_target_roles.items():
            all_dependency_commits[role] = commit_sha

    # Build the ancestry graph per §8.3. BFS from C following parent edges;
    # every target must be reachable from C (an ancestor of C).
    graph = _TQO.build_ancestry_graph(
        candidate_commit=candidate_commit,
        freeze_commit=freeze_commit,
        dependency_commits=all_dependency_commits,
        commit_objects=commit_objects,
        where=where,
    )

    # Verify membership: no extra commits outside the graph, no target
    # duplicated as ancestry-commit/*.
    _TQO.verify_ancestry_membership(graph, extra_commits, where)

    # §8.3: no two distinct git-object members carry the same commit_sha
    # (cross-role alias), per "同一objectId跨role出现...拒绝".
    seen_shas = {}
    for role, member in member_map.items():
        if not isinstance(member, _TQO.GitObjectMemberV1):
            continue
        sha = member.objectId
        if sha in seen_shas:
            _BTO._reject(f"{where}: commit {sha} aliased across roles '{seen_shas[sha]}' and '{role}'")
        seen_shas[sha] = role


# ---------------------------------------------------------------------------
# Stage 10c: D0-07 bridge internal verification (P1-4)
# ---------------------------------------------------------------------------

def _verify_d0_07_bridge_internal(
    member_map: dict,
    gc_member,
    gc_obj: dict,
    gc: _TQO.GovernanceBootstrapCompletionV1,
    bridge: _TQO.GovernanceBootstrapReceiptDependencyV1,
    authority_policy,
    profile,
    where: str,
) -> None:
    """Verify the D0-07 governance completion object internal consistency
    per §7 and the §8.2 dependencies stage.

    The D0-07 bridge must be an authenticated, current, non-revoked
    GOV-D0CLOSE-001 historical receipt. The governance completion object's
    signatures must verify under §1 Architecture+Quality+Security rule. The
    enum positional exact correspondence must hold (taskId/rulingId/purpose).
    wrapper.completionCommit must equal decoded completionCandidate.commit.
    The dependency wrapper's signatures must equal the decoded object's
    signatures (no wrapper-self-signed). The ruling ref must recompute from
    the member bytes. The sourceClosure path is fixed.
    """
    # Recompute the governance completion ContentRef from the member bytes
    # and assert it equals the member's declared content ref.
    recomputed = _TQO.recompute_typed_content_ref(gc_member.content.schema, gc_obj)
    if recomputed != gc_member.content:
        _BTO._reject(f"{where}: bytesHex does not recompute to member.content")

    # §7 enum positional exact correspondence: D0-07 pair is
    # (TASK-D0-07, GOV-D0CLOSE-001, d0-07-historical-bootstrap-closeout).
    if gc.taskId != "TASK-D0-07":
        _BTO._reject(f"{where}: gc.taskId must be TASK-D0-07, got {gc.taskId}")
    expected_ruling_id = (
        "GOV-D0CLOSE-FIXTURE-001"
        if isinstance(profile, FixtureVerificationProfileV1)
        else "GOV-D0CLOSE-001"
    )
    if gc.rulingId != expected_ruling_id:
        _BTO._reject(
            f"{where}: gc.rulingId must be {expected_ruling_id}, "
            f"got {gc.rulingId}")
    if gc.purpose != "d0-07-historical-bootstrap-closeout":
        _BTO._reject(f"{where}: gc.purpose must be d0-07-historical-bootstrap-closeout, got {gc.purpose}")
    if gc.id != "governance-bootstrap-completion-d0-07":
        _BTO._reject(f"{where}: gc.id must be governance-bootstrap-completion-d0-07, got {gc.id}")

    # §7: wrapper.completionCommit must equal decoded completionCandidate.commit.
    if bridge.completionCommit != gc.completionCandidate.commit:
        _BTO._reject(
            f"{where}: bridge.completionCommit ({bridge.completionCommit}) != "
            f"gc.completionCandidate.commit ({gc.completionCandidate.commit})")

    # §7: bridge.taskId must equal gc.taskId.
    if bridge.taskId != gc.taskId:
        _BTO._reject(f"{where}: bridge.taskId != gc.taskId")

    # §4/§8.3: the wrapper carries the same profile-discriminated normative
    # document ref as the decoded completion. It is not a manufactured
    # ContentRef and all four fields must be identical.
    if bridge.ruling != gc.ruling:
        _BTO._reject(f"{where}: bridge.ruling != gc.ruling")

    # The D0-07 ruling is an independent raw source role. Recompute the
    # profile-discriminated normative ref from those exact bytes; it must not
    # alias the D0-10 ruling source.
    ruling_bytes, ruling_raw = _resolve_raw_member(
        member_map, "d0-07-ruling-source", where)
    expected_ruling_path = (
        "fixtures/task-qualification/d0-07-ruling.md"
        if isinstance(profile, FixtureVerificationProfileV1)
        else "docs/governance/d0-07-closure-ruling.md"
    )
    if ruling_raw.path != expected_ruling_path:
        _BTO._reject(
            f"{where}: d0-07-ruling-source path must be "
            f"{expected_ruling_path}")
    ruling_parser = (
        _TQO.parse_fixture_qualification_normative_document_v1
        if isinstance(profile, FixtureVerificationProfileV1)
        else _TQO.parse_qualification_normative_document_v1
    )
    projected_ruling = ruling_parser(ruling_bytes, gc.ruling.id)
    if (
        projected_ruling.id,
        projected_ruling.status,
        projected_ruling.contentDigest,
        projected_ruling.reviewCommit,
    ) != (
        gc.ruling.id,
        gc.ruling.status,
        gc.ruling.contentDigest,
        gc.ruling.reviewCommit,
    ):
        _BTO._reject(
            f"{where}: D0-07 ruling ref does not equal source projection")
    d0_10_ruling_member = member_map.get("ruling-source")
    if (isinstance(d0_10_ruling_member, _TQO.RawContentMemberV1)
            and d0_10_ruling_member.bytesHex == ruling_bytes.hex()):
        _BTO._reject(f"{where}: D0-07 and D0-10 ruling sources alias")

    # §7: dependency wrapper signatures must equal decoded object signatures
    # (no wrapper-self-signed).
    if tuple(bridge.signatures) != tuple(gc.signatures):
        _BTO._reject(f"{where}: bridge.signatures != gc.signatures (wrapper must not self-sign)")

    # §7: sourceClosure path is fixed for D0-07.
    expected_source_path = "docs/governance/bootstrap-closure/TASK-D0-07.attest.json"
    if gc.sourceClosure.path != expected_source_path:
        _BTO._reject(
            f"{where}: gc.sourceClosure.path must be {expected_source_path}, "
            f"got {gc.sourceClosure.path}")

    # §4: sourceClosureBytesHex decoded bytes' plain SHA-256 must equal the
    # decoded completion.sourceClosure.digest. The wrapper verifies the
    # source closure bytes independently of the objectBytesHex claims.
    source_bytes = bytes.fromhex(bridge.sourceClosureBytesHex)
    computed_source_digest = _TQO.plain_sha256_digest(source_bytes)
    if computed_source_digest != gc.sourceClosure.digest:
        _BTO._reject(
            f"{where}: sourceClosureBytesHex sha256 != gc.sourceClosure.digest"
        )

    # §7: verify the governance completion signatures under §1 fixed rule.
    # The governance completion is signed under
    # DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT / SIGNATURE.
    _verify_signatures(
        gc_obj,
        gc.signatures,
        authority_policy,
        profile,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
        f"{where}.signatures",
    )


# ---------------------------------------------------------------------------
# Stage 6: candidate verification
# ---------------------------------------------------------------------------

def _verify_candidate(
    member_map: dict,
    archive_role: str,
    commit_role: str,
    expected: CandidateIdentity,
    task_id: str,
    where: str,
    profile=None,
    enforce_fixture_candidate_prefix: bool = True,
) -> tuple:
    """Verify candidate archive + commit object match the expected identity."""
    archive_bytes, archive_digest = _resolve_archive_member(member_map, archive_role, where)
    commit_bytes, commit_sha = _resolve_git_object_member(member_map, commit_role, where)

    # Parse archive with the correct task_id for prefix
    archive = _TQO.parse_ustar_archive(archive_bytes, task_id, where)
    if archive.archiveSha256.bytes != expected.archiveDigest.bytes:
        _BTO._reject(f"{where}: archiveSha256 mismatch")
    # Parse commit object
    commit_obj = _TQO.parse_git_commit_object(commit_bytes, where)
    # Verify tree
    computed_tree = _TQO.build_git_tree_from_archive(archive)
    if computed_tree != expected.treeObjectId:
        _BTO._reject(f"{where}: treeObjectId mismatch")
    if commit_obj.tree != expected.treeObjectId:
        _BTO._reject(f"{where}: commit tree mismatch")
    if commit_obj.commit_sha != expected.commit:
        _BTO._reject(f"{where}: commit SHA-1 mismatch")
    # §8.2 fixes the fixture pre-close C tuple to f1/f2. Receipt D is not the
    # fixture profile's authority-discriminating C and is checked separately.
    if (isinstance(profile, FixtureVerificationProfileV1)
            and enforce_fixture_candidate_prefix):
        if not expected.commit.startswith("f1"):
            _BTO._reject(f"{where}: commit first byte must be f1 (fixture)")
        if not expected.treeObjectId.startswith("f2"):
            _BTO._reject(f"{where}: tree first byte must be f2 (fixture)")
    return (archive, commit_obj)


def _verify_candidate_source_bytes(
    archive: ArchiveProjection, member_map: dict, roles: tuple, where: str,
) -> None:
    """Join candidate-owned raw document members to exact archive bytes."""
    for role in roles:
        member = member_map.get(role)
        if not isinstance(member, _TQO.RawContentMemberV1):
            _BTO._reject(f"{where}: {role} must be raw-source")
        entry = archive.path_map.get(member.raw.path)
        if entry is None:
            _BTO._reject(
                f"{where}: {role} path absent from candidate archive")
        if entry.content != bytes.fromhex(member.bytesHex):
            _BTO._reject(
                f"{where}: {role} bytes differ from candidate archive")


# ---------------------------------------------------------------------------
# Stage 7: policy verification
# ---------------------------------------------------------------------------

def _verify_authority_policy(
    member_map: dict,
    profile,
    expected_policy_ref: ContentRef,
    where: str,
) -> tuple:
    """Verify the authority policy member and return (policy_obj, policy_ref)."""
    member = member_map.get("authority-policy")
    if member is None:
        _BTO._reject(f"{where}: authority-policy member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: authority-policy must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: authority-policy decode failed: {exc}")

    if isinstance(profile, FixtureVerificationProfileV1):
        # Fixture policy
        policy = _TQO.parse_fixture_policy(obj, f"{where}.authority-policy")
        # Recompute the fixture policy content ref
        computed_ref = _TQO.fixture_policy_content_ref(policy)
        if computed_ref != expected_policy_ref:
            _BTO._reject(f"{where}: fixture policy ref mismatch")
        if member.content != computed_ref:
            _BTO._reject(f"{where}: authority-policy member content ref mismatch")
        return (policy, computed_ref)
    elif isinstance(profile, ProductionVerificationProfileV1):
        # Production policy — use bootstrap_task_objects parser, which takes
        # the canonical bytes and recomputes the ContentRef digest under
        # pf.bootstrap-authority-policy.v1. The decoded object is not passed
        # because the parser validates canonical bytes directly.
        policy, computed_ref = _BTO.parse_bootstrap_authority_policy(raw_bytes)
        # §8.2: every ContentRef must resolve to exactly one member and the
        # digest must be recomputed from the decoded bytes. The recomputed
        # ref must equal both the expected policy ref and the member's
        # declared content ref. A member whose bytes do not hash to its
        # declared digest must reject.
        if computed_ref != expected_policy_ref:
            _BTO._reject(f"{where}: production policy ref != expected policy ref")
        if member.content != computed_ref:
            _BTO._reject(f"{where}: authority-policy member content ref != recomputed")
        return (policy, computed_ref)
    else:
        _BTO._reject(f"{where}: unknown profile type")


# ---------------------------------------------------------------------------
# Stage 8: command policy verification
# ---------------------------------------------------------------------------

def _verify_command_policy(
    member_map: dict,
    gate: TaskQualificationGateV1,
    policy,
    profile,
    where: str,
) -> TaskCommandPolicyV1:
    """Verify a gate's command policy member and return the parsed policy.

    Per §8.2/§3, the command policy's tool/probe/sandboxPolicy/verifier refs
    must resolve to the resolved-tool/<gateId>, resolved-probe/<gateId>,
    sandbox-policy/<gateId>, verifier-executable/<gateId>,
    verifier-closure/<gateId>, verifier-build-policy/<gateId> members
    respectively (逐字段 exact join).
    """
    role = f"command-policy/{gate.gateId}"
    member = member_map.get(role)
    if member is None:
        _BTO._reject(f"{where}: {role} member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: {role} must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: {role} decode failed: {exc}")
    cmd = _TQO.parse_command_policy(obj, f"{where}.{role}")
    if cmd.taskId != gate.taskId or tuple(cmd.testIds) != tuple(gate.testIds):
        _BTO._reject(f"{where}: {role} taskId/testIds mismatch gate")
    # D0-10's sole reused denominator is bound to the frozen protocol id.
    if gate.taskId == "TASK-D0-10" and cmd.id != "tst-doc-001.task-qualification-v1":
        _BTO._reject(f"{where}: {role} id mismatch D0-10 subprofile")
    # Verify the command policy content ref matches the gate's
    if member.content != gate.commandPolicy:
        _BTO._reject(f"{where}: {role} content ref != gate.commandPolicy")
    # Recompute the command policy digest
    computed_ref = ContentRef(
        schema=cmd.schema,
        id=cmd.id,
        version=cmd.version,
        digest=domain_digest(_TQO.DOMAIN_TASK_COMMAND_POLICY, obj),
    )
    if computed_ref != gate.commandPolicy:
        _BTO._reject(f"{where}: {role} recomputed ref mismatch")
    # GAP-23: resolve command policy refs to gate-keyed resolved-* members.
    _resolve_command_policy_refs(
        member_map, profile, gate.gateId, cmd, where)
    return cmd


def _resolve_profile_artifact_ref(
    profile: ProductionVerificationProfileV1,
    role: str,
    expected_ref: ContentRef,
    where: str,
) -> None:
    matches = [mapping for mapping in profile.artifacts if mapping.role == role]
    if len(matches) != 1:
        _BTO._reject(f"{where}: profile must resolve exactly one artifact '{role}'")
    if matches[0].artifact != expected_ref:
        _BTO._reject(f"{where}: profile artifact '{role}' ref mismatch")


def _artifact_payload_digest(
    member_map: dict, profile, role: str, where: str,
) -> Digest:
    """Resolve the signed plain-payload digest for one logical artifact."""
    if isinstance(profile, ProductionVerificationProfileV1):
        matches = [mapping for mapping in profile.artifacts if mapping.role == role]
        if len(matches) != 1:
            _BTO._reject(
                f"{where}: production profile must resolve exactly one '{role}'")
        return matches[0].payloadSha256
    member = member_map.get(role)
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: fixture artifact '{role}' missing")
    raw = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw)
        blob = _TQO.parse_fixture_resolved_blob(obj, f"{where}.{role}")
    except Exception as exc:
        _BTO._reject(
            f"{where}: fixture artifact '{role}' invalid: {_exception_detail(exc)}")
    recomputed = _TQO.fixture_resolved_blob_content_ref(blob)
    if member.content != recomputed:
        _BTO._reject(f"{where}: fixture artifact '{role}' content ref mismatch")
    return blob.payloadSha256


def _resolve_command_policy_refs(
    member_map: dict,
    profile,
    gate_id: str,
    cmd: TaskCommandPolicyV1,
    where: str,
) -> None:
    """Resolve command refs through the profile-specific artifact authority.

    Fixture artifacts are ordinary typed bundle members.  Production artifacts
    are external payload mappings signed in ``profile.artifacts`` and therefore
    must not appear as bundle members.
    """
    ref_joins = [
        ("resolved-tool", cmd.tool),
        ("resolved-probe", cmd.probe),
        ("sandbox-policy", cmd.sandboxPolicy),
        ("verifier-executable", cmd.verifier.executable),
        ("verifier-closure", cmd.verifier.closure),
        ("verifier-build-policy", cmd.verifier.buildPolicy),
    ]
    for control_name, ref in ref_joins:
        role = f"{control_name}/{gate_id}"
        if isinstance(profile, ProductionVerificationProfileV1):
            if role in member_map:
                _BTO._reject(
                    f"{where}: production artifact '{role}' must not be a bundle member")
            _resolve_profile_artifact_ref(profile, role, ref, where)
            continue
        member = member_map.get(role)
        if member is None:
            _BTO._reject(f"{where}: {role} member missing (§8.2 gate-keyed control)")
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: {role} must be typed-content")
        _verify_typed_member_recompute(member, ref, f"{where}: {role}")


# ---------------------------------------------------------------------------
# Stage 9: evidence verification
# ---------------------------------------------------------------------------

def _verify_evidence_members(
    member_map: dict,
    gate: TaskQualificationGateV1,
    candidate: CandidateIdentity,
    command_policy: TaskCommandPolicyV1,
    profile,
    where: str,
) -> tuple:
    """Validate complete evidence-v1 bytes and all taskqual identity joins."""
    if len(gate.evidence) == 0:
        _BTO._reject(f"{where}: gate {gate.gateId} evidence must be nonempty")
    ev_ids = [ev.id for ev in gate.evidence]
    if ev_ids != sorted(ev_ids) or len(set(ev_ids)) != len(ev_ids):
        _BTO._reject(
            f"{where}: gate {gate.gateId} evidence refs must be unique ascending")

    tool_payload = _artifact_payload_digest(
        member_map, profile, f"resolved-tool/{gate.gateId}", where)
    closure_payload = _artifact_payload_digest(
        member_map, profile, f"resolved-tool-closure/{gate.gateId}", where)
    probe_payload = _artifact_payload_digest(
        member_map, profile, f"resolved-probe/{gate.gateId}", where)
    sandbox_payload = _artifact_payload_digest(
        member_map, profile, f"sandbox-policy/{gate.gateId}", where)
    expected_qualification = (
        "development"
        if isinstance(profile, FixtureVerificationProfileV1)
        or gate.taskId == "TASK-D0-10"
        else "formal"
    )

    validated_documents = []
    for ev_ref in gate.evidence:
        role = f"evidence/{ev_ref.id}"
        member = member_map.get(role)
        if not isinstance(member, _TQO.RawContentMemberV1):
            _BTO._reject(f"{where}: {role} must be raw-source")
        raw_bytes = bytes.fromhex(member.bytesHex)
        if plain_sha256_digest(raw_bytes) != ev_ref.digest:
            _BTO._reject(f"{where}: {role} evidence digest mismatch")
        if member.raw.digest != ev_ref.digest:
            _BTO._reject(f"{where}: {role} raw ref digest mismatch")
        try:
            decoded = _EVIDENCE.decode_json(raw_bytes)
            if _EVIDENCE.canonical_bytes(decoded) != raw_bytes:
                _BTO._reject(f"{where}: {role} is not canonical evidence JSON")
            evidence = _EVIDENCE.validate_evidence(decoded)
        except _EVIDENCE.EvidenceError as exc:
            _BTO._reject(f"{where}: {role} invalid evidence: {exc.code}: {exc}")
        if evidence["id"] != ev_ref.id or evidence["result"] != "passed":
            _BTO._reject(f"{where}: {role} id/result mismatch")
        gate_obj = evidence["gate"]
        if (
            gate_obj["id"] != gate.gateId
            or gate_obj["taskId"] != gate.taskId
            or tuple(gate_obj["testIds"]) != tuple(gate.testIds)
            or gate_obj["qualification"] != expected_qualification
        ):
            _BTO._reject(f"{where}: {role} gate projection mismatch")
        repository = evidence["repository"]
        archive = repository["archive"]
        if (
            repository["commit"] != candidate.commit
            or repository["treeObjectId"] != candidate.treeObjectId
            or archive["sha256"] != candidate.archiveDigest.bytes.hex()
        ):
            _BTO._reject(f"{where}: {role} candidate projection mismatch")
        command = evidence["command"]
        if tuple(command["argv"]) != tuple(command_policy.argv):
            _BTO._reject(f"{where}: {role} argv != command policy")

        matching_tools = [
            tool for tool in evidence["tools"]
            if tool["id"] == command_policy.tool.id
            and tool["version"] == command_policy.tool.version
        ]
        if len(matching_tools) != 1:
            _BTO._reject(f"{where}: {role} must have one selected tool")
        selected_tool = matching_tools[0]
        if (
            selected_tool["executableSha256"] != tool_payload.bytes.hex()
            or selected_tool["closureSha256"] != closure_payload.bytes.hex()
        ):
            _BTO._reject(f"{where}: {role} selected tool payload mismatch")

        matching_sandboxes = [
            policy for policy in evidence["sandboxPolicies"]
            if policy["id"] == command_policy.sandboxPolicy.id
        ]
        if len(matching_sandboxes) != 1:
            _BTO._reject(f"{where}: {role} must have one selected sandbox")
        selected_sandbox = matching_sandboxes[0]
        if selected_sandbox["renderedSha256"] != sandbox_payload.bytes.hex():
            _BTO._reject(f"{where}: {role} sandbox payload mismatch")
        probes = selected_sandbox["probes"]
        if len(probes) != 1 or probes[0] != {
                "id": command_policy.probe.id, "status": "passed"}:
            _BTO._reject(f"{where}: {role} sandbox probe mismatch")

        wrappers = [
            entry for entry in evidence["inputs"]
            if entry["role"] == "sandbox-probe-wrapper"
        ]
        if len(wrappers) != 1 or wrappers[0]["sha256"] != probe_payload.bytes.hex():
            _BTO._reject(f"{where}: {role} probe-wrapper payload mismatch")
        validated_documents.append(evidence)
    return tuple(validated_documents)


# ---------------------------------------------------------------------------
# Stage 10: dependencies verification
# ---------------------------------------------------------------------------

def _verify_dependency_members(
    member_map: dict,
    dependencies: tuple,
    row_dependencies: tuple,
    authority_policy,
    profile,
    where: str,
) -> None:
    """Verify dependency members for each dependency.

    Per §8.2, each dependency is an exact three-piece row:
    `dependency/<TASK-id>`, `dependency-archive/<TASK-id>`,
    `dependency-commit-object/<TASK-id>`. Missing, extra, duplicate or wrong
    suffix is a `members` rejection. The three-piece set may be empty (when
    the dependency list is empty), but a present dependency requires all
    three members.

    Per §4, objectDigest = SHA-256("pf.taskqual.dependency-object.v1" || NUL
    || raw bytes), i.e. a raw-bytes digest, not a PF-JCS digest. objectBytesHex
    must decode to canonical JSON (PF-JCS). The typed task, policy, receipt,
    signatures must逐字段 exact join the decoded raw object. dependencies
    taskId set must exact-equal row direct dependencies (no transitive
    substitute).

    Per §4 kind-specific rules:
    - bootstrap-task-receipt: only D0-01..06, verify complete object bytes
      under the historical receipt schema/signature domain.
    - task-qualification: only D1..D8, verify TaskCompletionReceiptV1.
    - governance-bootstrap-receipt: handled by _verify_d0_07_bridge_internal
      for the D0-10 approval path (not here).
    """
    # GAP-10: dependencies taskId set must exact-equal row direct dependencies.
    dep_task_ids = tuple(dep.taskId for dep in dependencies)
    if dep_task_ids != tuple(row_dependencies):
        _BTO._reject(
            f"{where}: dependency taskIds {dep_task_ids} != row.dependencies "
            f"{tuple(row_dependencies)} (§4 exact equality)")

    for dep in dependencies:
        role = f"dependency/{dep.taskId}"
        archive_role = f"dependency-archive/{dep.taskId}"
        commit_role = f"dependency-commit-object/{dep.taskId}"
        # The dependency object itself
        member = member_map.get(role)
        if member is None:
            _BTO._reject(f"{where}: {role} member missing")
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: {role} must be typed-content")
        raw_bytes = bytes.fromhex(member.bytesHex)
        # §4: objectDigest is a raw-bytes digest, not a PF-JCS digest.
        computed = _TQO.domain_digest_raw(_TQO.DOMAIN_DEPENDENCY_OBJECT, raw_bytes)
        if computed.bytes != dep.objectDigest.bytes:
            _BTO._reject(f"{where}: {role} object digest mismatch")
        # GAP-9: decode objectBytesHex and assert canonical (PF-JCS).
        dep_obj = _BTO.decode_canonical_pf_jcs(raw_bytes)
        # GAP-9: for task-qualification kind, the objectBytesHex carries the
        # prior task's TaskCompletionReceiptV1. Join the dependency wire fields
        # to the decoded receipt fields (逐字段 exact join per §4).
        if dep.kind == "task-qualification":
            receipt = _TQO.parse_completion_receipt(dep_obj, f"{where}: {role} receipt")
            # dep.taskId == receipt.taskId
            if dep.taskId != receipt.taskId:
                _BTO._reject(f"{where}: {role} taskId != receipt.taskId")
            # dep.completionCommit == receipt.closeoutCandidate.commit
            if dep.completionCommit != receipt.closeoutCandidate.commit:
                _BTO._reject(
                    f"{where}: {role} completionCommit != receipt.closeoutCandidate.commit")
            # dep.authorityPolicy == receipt.authorityPolicy
            if dep.authorityPolicy != receipt.authorityPolicy:
                _BTO._reject(f"{where}: {role} authorityPolicy != receipt.authorityPolicy")
            # dep.receipt ref recomputes from the decoded receipt under
            # DOMAIN_TASK_COMPLETION_RECEIPT.
            expected_receipt_ref = _TQO.TaskCompletionReceiptRefV1(
                taskId=receipt.taskId,
                id=receipt.id,
                digest=_TQO.domain_digest(_TQO.DOMAIN_TASK_COMPLETION_RECEIPT, dep_obj),
            )
            if dep.receipt != expected_receipt_ref:
                _BTO._reject(f"{where}: {role} receipt ref does not recompute from decoded receipt")
            # dep.signatures == receipt.signatures (逐字段 exact join)
            if tuple(dep.signatures) != tuple(receipt.signatures):
                _BTO._reject(f"{where}: {role} signatures != receipt.signatures")
        elif dep.kind == "bootstrap-task-receipt":
            # §4: bootstrap-task-receipt only allows D0-01..06, verify complete
            # object bytes under the historical receipt schema/signature domain.
            # This is not exercised by the fixture (no D0-01..06 dependency in
            # the fixture chain). We verify the objectBytesHex is canonical
            # (already done) and that kind/taskId/completionCommit/signatures
            # join the decoded object. The historical receipt schema parser is
            # named in §8.3 but not wired here (out of fixture scope).
            if dep_obj.get("taskId") != dep.taskId:
                _BTO._reject(f"{where}: {role} taskId != decoded taskId")
            if dep_obj.get("completionCommit") != dep.completionCommit:
                _BTO._reject(f"{where}: {role} completionCommit != decoded completionCommit")
            dep_sigs = dep_obj.get("signatures", [])
            decoded_sigs = tuple(
                _TQO.parse_approval_signature(s, f"{where}: {role} signatures")
                for s in dep_sigs)
            if decoded_sigs != tuple(dep.signatures):
                _BTO._reject(f"{where}: {role} signatures != decoded signatures")
        # §8.2: dependency archive and commit object members are required
        # (exact three-piece row), not optional.
        if archive_role not in member_map:
            _BTO._reject(f"{where}: {archive_role} member missing")
        _resolve_archive_member(member_map, archive_role, where)
        if commit_role not in member_map:
            _BTO._reject(f"{where}: {commit_role} member missing")
        _resolve_git_object_member(member_map, commit_role, where)


# ---------------------------------------------------------------------------
# Stage 11: reviews verification
# ---------------------------------------------------------------------------

def _verify_review_members(
    member_map: dict,
    reviews: tuple,
    bundle_impl_invocation: str,
    signing_principal_ids: set,
    pre_close_commit: str,
    where: str,
) -> None:
    """Verify review report members per §2 and §8.3.

    Checks:
    - Each review member exists and has correct digest.
    - reviewerId matches the subject ref.
    - invocationId differs from bundle's implementationInvocationId.
    - invocationId is unique across all reviews.
    - reviewerId is not among the signing principal IDs.
    - reviewCommit equals the subject's preCloseCandidate.commit.
    - The raw review report bytes pass the §8.3 P0/P1 parser.
    - §8.2: independentReviews must be nonempty (review nonempty).
    """
    if len(reviews) < 1:
        _BTO._reject(f"{where}: independentReviews must be nonempty")
    seen_invocation_ids = set()
    for review in reviews:
        role = f"review-report/{review.reviewerId}/{review.reportDigest.bytes.hex()}"
        member = member_map.get(role)
        if member is None:
            _BTO._reject(f"{where}: {role} member missing")
        if not isinstance(member, _TQO.ReviewMemberV1):
            _BTO._reject(f"{where}: {role} must be review")
        raw_bytes = bytes.fromhex(member.bytesHex)
        # Recompute the review report digest under §8.3 raw domain
        computed = _TQO.domain_digest_raw(_TQO.DOMAIN_REVIEW_REPORT, raw_bytes)
        if computed.bytes != review.reportDigest.bytes:
            _BTO._reject(f"{where}: {role} report digest mismatch")
        # Verify reviewerId matches
        if member.reviewerId != review.reviewerId:
            _BTO._reject(f"{where}: {role} reviewerId mismatch")
        # Verify invocationId is different from bundle's implementationInvocationId
        if review.invocationId == bundle_impl_invocation:
            _BTO._reject(f"{where}: {role} invocationId must differ from implementationInvocationId")
        # Verify invocationId is unique across reviews
        if review.invocationId in seen_invocation_ids:
            _BTO._reject(f"{where}: {role} invocationId must be unique across reviews")
        seen_invocation_ids.add(review.invocationId)
        # Verify reviewerId is not a signing principal
        if review.reviewerId in signing_principal_ids:
            _BTO._reject(f"{where}: {role} reviewerId must not be a signing principal")
        # §2: reviewCommit must equal the subject's preCloseCandidate.commit
        if review.reviewCommit != pre_close_commit:
            _BTO._reject(
                f"{where}: {role} reviewCommit must equal preCloseCandidate.commit")
        # §8.3: run the P0/P1 parser on the raw review report bytes
        _parse_review_report_for_findings(raw_bytes, f"{where}: {role}")


def _parse_review_report_for_findings(raw_bytes: bytes, where: str) -> None:
    """Apply the exact bounded §8.3 byte/text finding scan."""
    try:
        raw_bytes.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        _BTO._reject(f"{where}: review report is not valid UTF-8")

    # Only CRLF is normalized. A remaining CR is a forbidden bare CR, and
    # Unicode line separators are ordinary characters rather than line breaks.
    normalized = raw_bytes.replace(b"\r\n", b"\n")
    if b"\r" in normalized:
        _BTO._reject(f"{where}: review report contains bare CR")
    for line in normalized.split(b"\n"):
        if line in (b"Severity: P0", b"Severity: P1"):
            _BTO._reject(f"{where}: review report contains P0/P1 severity line")
        if line.startswith((b"P0:", b"P1:")):
            _BTO._reject(f"{where}: review report contains P0/P1 finding prefix")

    # ASCII-only case folding and ASCII [A-Za-z0-9_] whole-word boundaries.
    folded = bytes(byte + 32 if 65 <= byte <= 90 else byte for byte in raw_bytes)
    needle = b"unresolved"
    start = 0
    while True:
        index = folded.find(needle, start)
        if index < 0:
            break
        before = folded[index - 1] if index else None
        after_index = index + len(needle)
        after = folded[after_index] if after_index < len(folded) else None
        is_word = lambda byte: byte is not None and (
            97 <= byte <= 122 or 48 <= byte <= 57 or byte == 95)
        if not is_word(before) and not is_word(after):
            _BTO._reject(f"{where}: review report contains 'unresolved'")
        start = index + 1


# ---------------------------------------------------------------------------
# Stage 12: controls verification (gate control members)
# ---------------------------------------------------------------------------

def _resolve_control_object(
    member_map: dict, role: str, expected_ref: ContentRef, where: str,
) -> tuple:
    member = member_map.get(role)
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: {role} must be typed-content")
    raw = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw)
    except Exception as exc:
        _BTO._reject(f"{where}: {role} decode failed: {exc}")
    recomputed = _TQO.recompute_typed_content_ref(member.content.schema, obj)
    if recomputed != member.content or member.content != expected_ref:
        _BTO._reject(f"{where}: {role} ref/bytes mismatch")
    return obj, raw


def _legacy_candidate_matches(legacy, candidate: CandidateIdentity) -> bool:
    try:
        return (
            legacy.commit == candidate.commit
            and legacy.treeObjectId == candidate.treeObjectId
            and legacy.archiveDigest.algorithm == candidate.archiveDigest.algorithm
            and legacy.archiveDigest.bytes == candidate.archiveDigest.bytes
        )
    except AttributeError:
        return False


def _join_artifact_ref(
    member_map: dict, profile, role: str, expected_ref: ContentRef, where: str,
) -> None:
    if isinstance(profile, ProductionVerificationProfileV1):
        _resolve_profile_artifact_ref(profile, role, expected_ref, where)
    else:
        member = member_map.get(role)
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: fixture artifact {role} missing")
        _verify_typed_member_recompute(member, expected_ref, f"{where}.{role}")


def _parse_fixture_containment(
    obj: dict, policy, profile, candidate, handoff_ref, instant: str,
    where: str,
) -> None:
    _TQO._require_closed_keys(obj, (
        "schema", "id", "version", "candidate", "stage0Handoff",
        "supervisorDigest", "rootSessionId", "descendants", "escapeProbes",
        "startedAt", "finishedAt", "result", "signatures",
    ), where)
    if obj.get("schema") != "proof-forge.session-containment-receipt.v1":
        _BTO._reject(f"{where}: schema mismatch")
    _TQO._require_safe_id(obj.get("id"), f"{where}.id")
    if _TQO._require_semver(obj.get("version"), f"{where}.version") != "1.0.0":
        _BTO._reject(f"{where}: version must be 1.0.0")
    legacy = _BTO.parse_candidate_identity(obj.get("candidate"))
    if not _legacy_candidate_matches(legacy, candidate):
        _BTO._reject(f"{where}: candidate mismatch")
    if _TQO.parse_content_ref(
            obj.get("stage0Handoff"), f"{where}.stage0Handoff") != handoff_ref:
        _BTO._reject(f"{where}: stage0Handoff mismatch")
    _TQO._require_digest(obj.get("supervisorDigest"), f"{where}.supervisorDigest")
    _TQO._require_safe_id(obj.get("rootSessionId"), f"{where}.rootSessionId")
    descendants = _TQO._require_array(
        obj.get("descendants"), f"{where}.descendants")
    descendant_keys = []
    for index, entry in enumerate(descendants):
        item_where = f"{where}.descendants[{index}]"
        if not isinstance(entry, dict):
            _BTO._reject(f"{item_where}: must be object")
        _TQO._require_closed_keys(entry, (
            "pid", "parentPid", "startToken", "sessionId",
            "executableDigest", "termination",
        ), item_where)
        integers = tuple(entry.get(field) for field in (
            "pid", "parentPid", "startToken", "sessionId"))
        if any(type(value) is not int or not 0 <= value <= (1 << 53) - 1
               for value in integers):
            _BTO._reject(f"{item_where}: integer fields must be safe u64")
        digest = _TQO._require_digest(
            entry.get("executableDigest"), f"{item_where}.executableDigest")
        if entry.get("termination") not in ("exited", "killed"):
            _BTO._reject(f"{item_where}: termination invalid")
        descendant_keys.append(
            integers + (digest.bytes, entry.get("termination")))
    if descendant_keys != sorted(descendant_keys) or len(set(descendant_keys)) != len(descendant_keys):
        _BTO._reject(f"{where}.descendants: must be unique ascending")
    probes = _TQO._require_array(obj.get("escapeProbes"), f"{where}.escapeProbes")
    probe_ids = []
    for index, entry in enumerate(probes):
        item_where = f"{where}.escapeProbes[{index}]"
        if not isinstance(entry, dict):
            _BTO._reject(f"{item_where}: must be object")
        _TQO._require_closed_keys(entry, ("id", "result"), item_where)
        probe_ids.append(_TQO._require_safe_id(entry.get("id"), f"{item_where}.id"))
        if entry.get("result") != "contained":
            _BTO._reject(f"{item_where}: result must be contained")
    if probe_ids != sorted(probe_ids) or len(set(probe_ids)) != len(probe_ids):
        _BTO._reject(f"{where}.escapeProbes: must be unique ascending")
    started = _TQO._require_rfc3339_utc(obj.get("startedAt"), f"{where}.startedAt")
    finished = _TQO._require_rfc3339_utc(obj.get("finishedAt"), f"{where}.finishedAt")
    if not started <= finished <= instant or obj.get("result") != "contained":
        _BTO._reject(f"{where}: containment time/result mismatch")
    signatures = tuple(_TQO.parse_approval_signature(
        value, f"{where}.signatures") for value in _TQO._require_array(
            obj.get("signatures"), f"{where}.signatures"))
    _TQO._require_unique_sorted(signatures, lambda item: item.keyId, f"{where}.signatures")
    _verify_signatures(
        obj, signatures, policy, profile,
        b"pf.session-containment-receipt-statement.v1",
        b"pf.session-containment-receipt-signature.v1", where)


def _parse_fixture_freshness(
    obj: dict, policy, profile, policy_ref: ContentRef, instant: str,
    where: str,
) -> None:
    _TQO._require_closed_keys(obj, (
        "schema", "id", "version", "authorityPolicy", "observedAt",
        "maximumAgeSeconds", "clockSourceDigest", "signatures",
    ), where)
    if obj.get("schema") != "proof-forge.freshness-authority-snapshot.v1":
        _BTO._reject(f"{where}: schema mismatch")
    _TQO._require_safe_id(obj.get("id"), f"{where}.id")
    if obj.get("version") != "1.0.0":
        _BTO._reject(f"{where}: version must be 1.0.0")
    if _TQO.parse_content_ref(
            obj.get("authorityPolicy"), f"{where}.authorityPolicy") != policy_ref:
        _BTO._reject(f"{where}: authorityPolicy mismatch")
    observed = _TQO._require_rfc3339_utc(
        obj.get("observedAt"), f"{where}.observedAt")
    maximum_age = obj.get("maximumAgeSeconds")
    if type(maximum_age) is not int or not 1 <= maximum_age <= (1 << 53) - 1:
        _BTO._reject(f"{where}: maximumAgeSeconds must be nonzero safe integer")
    _TQO._require_digest(obj.get("clockSourceDigest"), f"{where}.clockSourceDigest")
    signatures = tuple(_TQO.parse_approval_signature(
        value, f"{where}.signatures") for value in _TQO._require_array(
            obj.get("signatures"), f"{where}.signatures"))
    _TQO._require_unique_sorted(signatures, lambda item: item.keyId, f"{where}.signatures")
    _verify_signatures(
        obj, signatures, policy, profile,
        b"pf.freshness-authority-snapshot-statement.v1",
        b"pf.freshness-authority-snapshot-signature.v1", where)
    observed_dt = _datetime.datetime.strptime(observed, "%Y-%m-%dT%H:%M:%SZ")
    instant_dt = _datetime.datetime.strptime(instant, "%Y-%m-%dT%H:%M:%SZ")
    if not observed_dt <= instant_dt < observed_dt + _datetime.timedelta(seconds=maximum_age):
        _BTO._reject(f"{where}: snapshot is future or expired")


def _expected_scanned_members(evidence_documents: tuple) -> tuple:
    members = []
    for evidence in evidence_documents:
        evidence_ref = {
            "id": evidence["id"],
            "digest": "sha256:" + hashlib.sha256(
                _EVIDENCE.canonical_bytes(evidence)).hexdigest(),
        }
        for entry in evidence["inputs"]:
            members.append({
                "evidence": evidence_ref, "role": entry["role"],
                "path": entry["path"], "size": entry["size"],
                "digest": "sha256:" + entry["sha256"],
            })
        for entry in evidence["artifacts"]:
            members.append({
                "evidence": evidence_ref,
                "role": f"artifact.{entry['target']}.{entry['role']}",
                "path": entry["path"], "size": entry["size"],
                "digest": "sha256:" + entry["sha256"],
            })
        for entry in evidence["logs"]:
            members.append({
                "evidence": evidence_ref, "role": "log",
                "path": entry["path"], "size": entry["size"],
                "digest": "sha256:" + entry["sha256"],
            })
    members.sort(key=lambda item: (
        item["evidence"]["id"], item["evidence"]["digest"][7:],
        item["path"].encode("utf-8")))
    return tuple(members)


def _verify_private_scan(
    obj: dict, policy, profile, member_map: dict, gate,
    candidate: CandidateIdentity, evidence_documents: tuple, where: str,
) -> None:
    _TQO._require_closed_keys(obj, (
        "schema", "id", "version", "candidate", "evidenceCoreDigest",
        "scannerDigest", "policy", "scannedEvidenceRefs", "scannedMembers",
        "findings", "result", "signatures",
    ), where)
    if obj.get("schema") != "proof-forge.task-qualification-private-scan-receipt.v1":
        _BTO._reject(f"{where}: schema mismatch")
    if obj.get("id") != f"task-qualification-private-scan-{gate.gateId}" or obj.get("version") != "1.0.0":
        _BTO._reject(f"{where}: id/version mismatch")
    parsed_candidate = _TQO.parse_candidate_identity(
        obj.get("candidate"), f"{where}.candidate")
    if parsed_candidate != candidate:
        _BTO._reject(f"{where}: candidate mismatch")
    evidence_refs = [
        {"id": ref.id, "digest": digest_to_wire(ref.digest)}
        for ref in gate.evidence
    ]
    if obj.get("scannedEvidenceRefs") != evidence_refs:
        _BTO._reject(f"{where}: scannedEvidenceRefs mismatch")
    expected_members = _expected_scanned_members(evidence_documents)
    if tuple(obj.get("scannedMembers", ())) != expected_members:
        _BTO._reject(f"{where}: scannedMembers mismatch")
    core = {
        "candidate": _TQO.candidate_identity_to_wire(candidate),
        "scannedEvidenceRefs": evidence_refs,
        "scannedMembers": list(expected_members),
    }
    expected_core = _TQO.domain_digest(
        b"pf.taskqual.private-scan-core.v1", core)
    if _TQO._require_digest(
            obj.get("evidenceCoreDigest"), f"{where}.evidenceCoreDigest") != expected_core:
        _BTO._reject(f"{where}: evidenceCoreDigest mismatch")
    expected_scanner = _artifact_payload_digest(
        member_map, profile, f"private-scan-scanner/{gate.gateId}", where)
    if _TQO._require_digest(
            obj.get("scannerDigest"), f"{where}.scannerDigest") != expected_scanner:
        _BTO._reject(f"{where}: scannerDigest mismatch")
    expected_policy_role = f"private-scan-policy/{gate.gateId}"
    scan_policy_ref = _TQO.parse_content_ref(obj.get("policy"), f"{where}.policy")
    _join_artifact_ref(
        member_map, profile, expected_policy_role, scan_policy_ref, where)
    if obj.get("findings") != [] or obj.get("result") != "clean":
        _BTO._reject(f"{where}: findings/result mismatch")
    signatures = tuple(_TQO.parse_approval_signature(
        value, f"{where}.signatures") for value in _TQO._require_array(
            obj.get("signatures"), f"{where}.signatures"))
    _TQO._require_unique_sorted(signatures, lambda item: item.keyId, f"{where}.signatures")
    _verify_signatures(
        obj, signatures, policy, profile,
        b"pf.taskqual.private-scan-statement.v1",
        b"pf.taskqual.private-scan-signature.v1", where)


def _verify_fixture_revocation_snapshot(
    obj: dict, policy, profile, policy_ref: ContentRef, where: str,
) -> None:
    _TQO._require_closed_keys(obj, (
        "schema", "id", "version", "authorityPolicy", "records", "head",
        "recordsDigest", "signatures",
    ), where)
    if obj.get("schema") != "proof-forge.revocation-ledger-snapshot.v1":
        _BTO._reject(f"{where}: schema mismatch")
    _TQO._require_safe_id(obj.get("id"), f"{where}.id")
    if obj.get("version") != "1.0.0" or obj.get("records") != [] or obj.get("head") is not None:
        _BTO._reject(f"{where}: fixture snapshot must be empty v1")
    if _TQO.parse_content_ref(
            obj.get("authorityPolicy"), f"{where}.authorityPolicy") != policy_ref:
        _BTO._reject(f"{where}: authorityPolicy mismatch")
    expected_records_digest = hashlib.sha256(
        b"pf.revocation-ledger-records.v1\x00").digest()
    if _TQO._require_digest(
            obj.get("recordsDigest"), f"{where}.recordsDigest").bytes != expected_records_digest:
        _BTO._reject(f"{where}: recordsDigest mismatch")
    signatures = tuple(_TQO.parse_approval_signature(
        value, f"{where}.signatures") for value in _TQO._require_array(
            obj.get("signatures"), f"{where}.signatures"))
    _TQO._require_unique_sorted(signatures, lambda item: item.keyId, f"{where}.signatures")
    _verify_signatures(
        obj, signatures, policy, profile,
        b"pf.revocation-ledger-snapshot-statement.v1",
        b"pf.revocation-ledger-snapshot-signature.v1", where)


def _verify_gate_test_ids_union(gates: tuple, task_row, where: str) -> None:
    """§3: all gate testIds must be non-overlapping and their sorted union
    must exactly equal row.tests.
    """
    seen = set()
    for gate in gates:
        for tid in gate.testIds:
            if tid in seen:
                _BTO._reject(f"{where}: gate testId '{tid}' overlaps across gates")
            seen.add(tid)
    union_sorted = tuple(sorted(seen))
    row_tests_sorted = tuple(sorted(task_row.tests))
    if union_sorted != row_tests_sorted:
        _BTO._reject(
            f"{where}: gate testIds union does not equal row.tests "
            f"(union={list(union_sorted)}, row.tests={list(row_tests_sorted)})")
    evidence_ids = [ref.id for gate in gates for ref in gate.evidence]
    if len(set(evidence_ids)) != len(evidence_ids):
        _BTO._reject(f"{where}: evidence IDs overlap across gates")
    if tuple(sorted(evidence_ids)) != tuple(task_row.evidenceIds):
        _BTO._reject(f"{where}: gate evidence ID union != taskRow.evidenceIds")
    for gate in gates:
        if gate.taskId != task_row.taskId:
            _BTO._reject(f"{where}: gate.taskId != taskRow.taskId")


def _verify_gate_controls(
    member_map: dict,
    gate: TaskQualificationGateV1,
    profile,
    authority_policy,
    policy_ref: ContentRef,
    candidate: CandidateIdentity,
    verification_instant: str,
    command_policy: TaskCommandPolicyV1,
    evidence_documents: tuple,
    where: str,
) -> None:
    """Parse and verify every complete control, signature, time, and join."""
    handoff_obj, handoff_bytes = _resolve_control_object(
        member_map, f"eligible-stage0-handoff/{gate.gateId}",
        gate.eligibleStage0Handoff, where)
    try:
        handoff = _BTO._preflight_eligible_stage0_handoff(handoff_bytes).handoff
    except Exception as exc:
        _BTO._reject(f"{where}: eligible handoff invalid: {_exception_detail(exc)}")
    if not _legacy_candidate_matches(handoff.candidate, candidate):
        _BTO._reject(f"{where}: eligible handoff candidate mismatch")
    if handoff.authorityPolicy != policy_ref:
        _BTO._reject(f"{where}: eligible handoff authority policy mismatch")
    for prefix, ref in (
        ("authority-store-service", handoff.authorityStoreService),
        ("host-observation", handoff.hostObservation),
        ("host-profile", handoff.hostProfile),
    ):
        _join_artifact_ref(
            member_map, profile, f"{prefix}/{gate.gateId}", ref, where)
    handoff_environment = (
        ("HOME", handoff.environment.home),
        ("LC_ALL", handoff.environment.lcAll),
        ("PATH", handoff.environment.path),
        ("TZ", handoff.environment.tz),
    )
    if command_policy.environment != handoff_environment:
        _BTO._reject(f"{where}: command environment != eligible handoff")

    containment_obj, containment_bytes = _resolve_control_object(
        member_map, f"session-containment/{gate.gateId}",
        gate.sessionContainment, where)
    if isinstance(profile, FixtureVerificationProfileV1):
        _parse_fixture_containment(
            containment_obj, authority_policy, profile, candidate,
            gate.eligibleStage0Handoff, verification_instant,
            f"{where}.containment")
    else:
        try:
            containment = _FORMAL.parse_session_containment_receipt(
                containment_bytes, authority_policy)
        except Exception as exc:
            _BTO._reject(f"{where}: containment invalid: {exc}")
        if (
            not _legacy_candidate_matches(containment.candidate, candidate)
            or not _content_ref_record_equal(
                containment.stage0Handoff, gate.eligibleStage0Handoff)
            or containment.result != "contained"
            or not containment.startedAt <= containment.finishedAt <= verification_instant
        ):
            _BTO._reject(f"{where}: containment projection mismatch")

    freshness_obj, freshness_bytes = _resolve_control_object(
        member_map, f"freshness/{gate.gateId}", gate.freshness, where)
    if isinstance(profile, FixtureVerificationProfileV1):
        _parse_fixture_freshness(
            freshness_obj, authority_policy, profile, policy_ref,
            verification_instant, f"{where}.freshness")
    else:
        try:
            freshness = _FORMAL.parse_freshness_authority_snapshot(
                freshness_bytes, authority_policy)
        except Exception as exc:
            _BTO._reject(f"{where}: freshness invalid: {exc}")
        if not _content_ref_record_equal(freshness.authorityPolicy, policy_ref):
            _BTO._reject(f"{where}: freshness authority policy mismatch")
        observed = _datetime.datetime.strptime(
            freshness.observedAt, "%Y-%m-%dT%H:%M:%SZ")
        instant = _datetime.datetime.strptime(
            verification_instant, "%Y-%m-%dT%H:%M:%SZ")
        if not observed <= instant < observed + _datetime.timedelta(
                seconds=freshness.maximumAgeSeconds):
            _BTO._reject(f"{where}: freshness is future or expired")

    scan_obj, _ = _resolve_control_object(
        member_map, f"private-scan/{gate.gateId}", gate.privateScan, where)
    _verify_private_scan(
        scan_obj, authority_policy, profile, member_map, gate, candidate,
        evidence_documents, f"{where}.private-scan")

    revocation_obj, revocation_bytes = _resolve_control_object(
        member_map, "revocation-snapshot", gate.revocationSnapshot, where)
    record_roles = sorted(
        role for role in member_map if role.startswith("revocation-record/"))
    record_bytes = []
    for role in record_roles:
        member = member_map[role]
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: {role} must be typed-content")
        raw = bytes.fromhex(member.bytesHex)
        obj = decode_canonical_pf_jcs(raw)
        recomputed = _TQO.recompute_typed_content_ref(member.content.schema, obj)
        if recomputed != member.content:
            _BTO._reject(f"{where}: {role} ref mismatch")
        record_bytes.append(raw)
    if isinstance(profile, FixtureVerificationProfileV1):
        if record_bytes:
            _BTO._reject(f"{where}: fixture snapshot must not carry records")
        _verify_fixture_revocation_snapshot(
            revocation_obj, authority_policy, profile, policy_ref,
            f"{where}.revocation")
    else:
        try:
            snapshot = _FORMAL.parse_revocation_ledger_snapshot(
                revocation_bytes, authority_policy, tuple(record_bytes))
        except Exception as exc:
            _BTO._reject(f"{where}: revocation snapshot invalid: {exc}")
        if not _content_ref_record_equal(snapshot.authorityPolicy, policy_ref):
            _BTO._reject(f"{where}: revocation authority policy mismatch")
        revoked = set()
        for raw in record_bytes:
            try:
                record = _REVOCATION.parse_revocation_record(raw)
            except Exception as exc:
                _BTO._reject(f"{where}: revocation record invalid: {exc}")
            revoked.add((record.evidenceId, record.evidenceSha256))
        for ref in gate.evidence:
            if (ref.id, ref.digest.bytes.hex()) in revoked:
                _BTO._reject(f"{where}: current evidence is revoked")


def _verify_d0_top_level_identities(
    member_map: dict, profile, approval, command_policy, where: str,
) -> None:
    verifier = approval.verifier
    consumer = approval.protectedConsumer
    if verifier.id == consumer.id:
        _BTO._reject(f"{where}: verifier and protectedConsumer ids must differ")
    joins = (
        ("bootstrap-verifier-executable", verifier.executable),
        ("bootstrap-verifier-closure", verifier.closure),
        ("bootstrap-verifier-build-policy", verifier.buildPolicy),
        ("protected-consumer-executable", consumer.executable),
        ("protected-consumer-closure", consumer.closure),
        ("protected-consumer-build-policy", consumer.buildPolicy),
    )
    for role, ref in joins:
        _join_artifact_ref(member_map, profile, role, ref, where)
    all_refs = [ref for _, ref in joins] + [
        command_policy.tool,
        command_policy.verifier.executable,
        command_policy.verifier.closure,
        command_policy.verifier.buildPolicy,
    ]
    if len(set(all_refs)) != len(all_refs):
        _BTO._reject(f"{where}: top-level/gate/tool artifact refs must not alias")
    expected_verifier_closure = _TQO.domain_digest(
        _TQO.DOMAIN_D0_10_VERIFIER_CLOSURE,
        _TQO.verifier_identity_to_wire(verifier))
    expected_consumer_closure = _TQO.domain_digest(
        _TQO.DOMAIN_D0_10_CONSUMER_CLOSURE,
        _TQO.verifier_identity_to_wire(consumer))
    if approval.verifierClosureDigest != expected_verifier_closure:
        _BTO._reject(f"{where}: verifierClosureDigest mismatch")
    if approval.consumerClosureDigest != expected_consumer_closure:
        _BTO._reject(f"{where}: consumerClosureDigest mismatch")


def _verify_receipt_revocation(
    member_map: dict, profile, authority_policy, policy_ref: ContentRef,
    expected_ref: ContentRef, where: str,
) -> None:
    obj, snapshot_bytes = _resolve_control_object(
        member_map, "revocation-snapshot", expected_ref, where)
    record_roles = sorted(
        role for role in member_map if role.startswith("revocation-record/"))
    record_bytes = []
    for role in record_roles:
        member = member_map[role]
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: {role} must be typed-content")
        raw = bytes.fromhex(member.bytesHex)
        decoded = decode_canonical_pf_jcs(raw)
        if _TQO.recompute_typed_content_ref(
                member.content.schema, decoded) != member.content:
            _BTO._reject(f"{where}: {role} ref mismatch")
        record_bytes.append(raw)
    if isinstance(profile, FixtureVerificationProfileV1):
        if record_bytes:
            _BTO._reject(f"{where}: fixture snapshot must not carry records")
        _verify_fixture_revocation_snapshot(
            obj, authority_policy, profile, policy_ref, where)
    else:
        try:
            snapshot = _FORMAL.parse_revocation_ledger_snapshot(
                snapshot_bytes, authority_policy, tuple(record_bytes))
        except Exception as exc:
            _BTO._reject(f"{where}: revocation snapshot invalid: {exc}")
        if not _content_ref_record_equal(snapshot.authorityPolicy, policy_ref):
            _BTO._reject(f"{where}: revocation authority policy mismatch")


# ---------------------------------------------------------------------------
# Stage 13: patch verification (allowed closeout patch)
# ---------------------------------------------------------------------------

def _verify_allowed_closeout_patch(
    member_map: dict,
    patch_ref: ContentRef,
    where: str,
) -> AllowedCloseoutPatchV1:
    """Verify the allowed-closeout-patch member and return the parsed patch."""
    member = member_map.get("allowed-closeout-patch")
    if member is None:
        _BTO._reject(f"{where}: allowed-closeout-patch member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: allowed-closeout-patch must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: allowed-closeout-patch decode failed: {exc}")
    patch = _TQO.parse_allowed_closeout_patch(obj, f"{where}.allowed-closeout-patch")
    # Recompute the patch content ref
    computed_ref = ContentRef(
        schema=patch.schema,
        id=patch.id,
        version=patch.version,
        digest=domain_digest(_TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, obj),
    )
    if computed_ref != patch_ref:
        _BTO._reject(f"{where}: allowed-closeout-patch ref mismatch")
    if member.content != patch_ref:
        _BTO._reject(f"{where}: allowed-closeout-patch member content ref mismatch")
    # §5: allowedPaths content restrictions — only task-owned closeout
    # locations (task table, Evidence ledger, checkpoint, trace/review/log)
    # and the fixed qualification/bootstrap-approval path are allowed.
    # Product/verifier/protocol/test/freeze-package paths are forbidden.
    _verify_allowed_paths_content(patch.allowedPaths, f"{where}.allowed-closeout-patch")
    return patch


# Path prefixes that are forbidden in allowedCloseoutPatch.allowedPaths.
# Per §5, allowedPaths may only contain task-owned closeout locations
# (docs/ task table, evidence ledger, checkpoint, trace/review/log) and the
# fixed qualification/bootstrap-approval path. Product, verifier, protocol,
# test, and freeze-package locations are forbidden.
_FORBIDDEN_ALLOWED_PATH_PREFIXES = (
    "ProofForgeV2/",   # product / compiler / verifier
    "Tests/",          # tests
    "testdata/",       # test data
    "sandbox/",        # sandbox / test harness
    "scripts/",        # protocol / verifier tooling
    "supply-chain/",   # freeze-package pins / SBOM
    "build/",          # build artifacts
    "active/",         # archived v1 research tree
    "Examples/",       # examples
    "docs/governance/task-freeze-packages/",  # freeze packages
    "docs/governance/task-freeze-exceptions/",  # freeze exceptions
)


def _verify_patch_join(
    patch: AllowedCloseoutPatchV1, task_id: str,
    candidate: CandidateIdentity, where: str,
) -> None:
    if patch.taskId != task_id or patch.preCloseCandidate != candidate:
        _BTO._reject(f"{where}: patch task/candidate mismatch")


def _verify_allowed_paths_content(paths: tuple, where: str) -> None:
    """§5: reject allowedPaths that touch forbidden locations."""
    for p in paths:
        for prefix in _FORBIDDEN_ALLOWED_PATH_PREFIXES:
            if p.startswith(prefix):
                _BTO._reject(
                    f"{where}.allowedPaths: path '{p}' touches forbidden "
                    f"location '{prefix}' (product/verifier/protocol/test/"
                    f"freeze-package)")


# ---------------------------------------------------------------------------
# Stage 14: signatures verification
# ---------------------------------------------------------------------------

def _verify_signatures(
    subject_obj: dict,
    signatures: tuple,
    authority_policy,
    profile,
    statement_domain: bytes,
    signature_domain: bytes,
    where: str,
) -> None:
    """Verify the subject's signatures against the authority policy."""
    # §1: signatures count 3..256, sorted by keyId ascending, unique.
    # The parser enforces sort+unique; the verifier enforces the bounds
    # (the parser uses MAX_ARRAY=4096, which is too permissive for the
    # §1 signature-specific 3..256 bound).
    _enforce_signature_bounds(signatures, where)

    # Build the unsigned statement (remove signatures field)
    unsigned = dict(subject_obj)
    unsigned["signatures"] = []
    statement_digest = domain_digest(statement_domain, unsigned)
    message = signature_domain + b"\x00" + statement_digest.bytes

    # Build the principal registry from the policy
    if isinstance(authority_policy, FixturePolicyV1):
        principals = {p.keyId: p for p in authority_policy.principals}
        rule = authority_policy.rule
    else:
        # Production policy — use bootstrap_task_objects principals
        principals = {p.keyId: p for p in authority_policy.principals}
        rule = _BTO.ApprovalRuleV1(
            requiredRoles=("architecture", "quality", "security"),
            minimumDistinctSigners=3,
        )

    # Verify each signature (no extra ignored — all signatures are verified)
    signed_roles = set()
    signed_principal_ids = set()
    seen_key_ids = set()
    for sig in signatures:
        if sig.keyId in seen_key_ids:
            _BTO._reject(f"{where}.signatures: duplicate keyId '{sig.keyId}'")
        seen_key_ids.add(sig.keyId)
        if sig.keyId not in principals:
            _BTO._reject(f"{where}.signatures: keyId '{sig.keyId}' not in policy")
        principal = principals[sig.keyId]
        # Verify the Ed25519 signature
        if not _BTP.verify_ed25519(principal.publicKey, message, sig.signature):
            _BTO._reject(f"{where}.signatures: signature verification failed for keyId '{sig.keyId}'")
        signed_roles.update(principal.roles)
        signed_principal_ids.add(principal.principalId)

    # Verify the rule: requiredRoles covered, minimumDistinctSigners met
    if not set(rule.requiredRoles).issubset(signed_roles):
        _BTO._reject(f"{where}.signatures: required roles not covered")
    if len(signed_principal_ids) < rule.minimumDistinctSigners:
        _BTO._reject(f"{where}.signatures: minimum distinct signers not met")


def _enforce_signature_bounds(signatures: tuple, where: str) -> None:
    """§1: signatures count 3..256, sorted by keyId ascending, unique.

    The parser enforces sort+uniqueness via ``_require_unique_sorted``, but
    uses ``MAX_ARRAY`` (4096) as the upper bound. The §1 signature-specific
    bound is 3..256, so the verifier re-checks both bounds and the sort
    order defensively. A subject with >256 signatures or unsorted keyIds
    must reject before any curve work.
    """
    n = len(signatures)
    if n < 3:
        _BTO._reject(f"{where}.signatures: count {n} < 3 (§1 minimum)")
    if n > 256:
        _BTO._reject(f"{where}.signatures: count {n} > 256 (§1 maximum)")
    key_ids = [s.keyId for s in signatures]
    if key_ids != sorted(key_ids):
        _BTO._reject(f"{where}.signatures: keyIds not ASCII ascending sorted")
    if len(set(key_ids)) != len(key_ids):
        _BTO._reject(f"{where}.signatures: duplicate keyId")


# ---------------------------------------------------------------------------
# Stage 15: projection (closeout file set / diff verification)
# ---------------------------------------------------------------------------

def _verify_closeout_file_set_from_archives(
    member_map: dict,
    pre_archive: ArchiveProjection,
    close_archive: ArchiveProjection,
    expected_diff_digest: Digest,
    where: str,
) -> CloseoutFileSetV1:
    """Verify the closeout-file-set member and reconstruct from C/D archives per §6.

    The closeout file set is the exact changed-file set from comparing C and D
    candidate archives path-by-path. The verifier:
    1. Decodes the closeout-file-set member.
    2. Recomputes the closeoutDiffDigest.
    3. Reconstructs the file set from the C/D archives and verifies it matches.
    """
    member = member_map.get("closeout-file-set")
    if member is None:
        _BTO._reject(f"{where}: closeout-file-set member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: closeout-file-set must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: closeout-file-set decode failed: {exc}")
    file_set = _TQO.parse_closeout_file_set(obj, f"{where}.closeout-file-set")
    # Recompute the closeout file set digest
    computed_diff = domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, obj)
    if computed_diff.bytes != expected_diff_digest.bytes:
        _BTO._reject(f"{where}: closeoutDiffDigest mismatch")
    # Recompute the content ref and verify it matches the member
    computed_ref = ContentRef(
        schema=file_set.schema,
        id=file_set.id,
        version=file_set.version,
        digest=computed_diff,
    )
    if member.content != computed_ref:
        _BTO._reject(f"{where}: closeout-file-set member content ref mismatch")

    # Reconstruct the file set from C/D archives and verify it matches
    pre_paths = set(pre_archive.path_map.keys())
    close_paths = set(close_archive.path_map.keys())
    all_paths = sorted(pre_paths | close_paths)

    reconstructed_changes = []
    for path in all_paths:
        pre_entry = pre_archive.path_map.get(path)
        close_entry = close_archive.path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(close_entry.content) if close_entry else None
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue  # no change
        if before_digest is None and after_digest is None:
            continue
        reconstructed_changes.append((path, before_digest, after_digest))

    # Compare reconstructed changes with the file set's changes
    if len(reconstructed_changes) != len(file_set.changes):
        _BTO._reject(f"{where}: closeout file set changes count mismatch (reconstructed {len(reconstructed_changes)}, file set {len(file_set.changes)})")
    for i, (recon, file_set_change) in enumerate(zip(reconstructed_changes, file_set.changes)):
        if recon[0] != file_set_change[0]:
            _BTO._reject(f"{where}: closeout file set path mismatch at index {i}")
        if recon[1] != file_set_change[1]:
            _BTO._reject(f"{where}: closeout file set beforeDigest mismatch at index {i}")
        if recon[2] != file_set_change[2]:
            _BTO._reject(f"{where}: closeout file set afterDigest mismatch at index {i}")

    return file_set


def _reconstruct_semantic_file_set_digest(
    file_set: CloseoutFileSetV1,
    fixed_q_paths: set,
    where: str,
) -> Digest:
    """§6: reconstruct the SemanticCloseoutFileSetV1 digest from the full
    CloseoutFileSetV1.

    The algorithm is fixed by §6:
    1. Verify the full file set schema/id/version/taskId/C/D.
    2. Remove the single fixed Q/approval-path change.
    3. Replace schema with proof-forge.semantic-closeout-file-set.v1 and id
       with semantic-closeout-<lowercase task suffix>, keep version 1.0.0.
    4. Keep taskId, preCloseCandidate, and the remaining changes.
    5. Drop closeoutCandidate.
    6. Compute SHA-256("pf.semantic-closeout-file-set.v1" || NUL || PF-JCS(semantic)).

    Rejects if there is no fixed-path change, more than one, or the
    fixed-path change's after-bytes do not equal the verified Q/approval
    (GAP-12: caller passes verified_q_bytes; here we assert the fixed-path
    change's afterDigest equals plain_sha256(verified_q_bytes)).
    """
    # Identify the fixed-path changes present in the full file set.
    fixed_changes = [c for c in file_set.changes if c[0] in fixed_q_paths]
    if len(fixed_changes) != 1:
        _BTO._reject(
            f"{where}: full file set must contain exactly one fixed "
            f"Q/approval-path change (found {len(fixed_changes)})")
    semantic_changes = [c for c in file_set.changes if c[0] not in fixed_q_paths]
    # Build the semantic wire object per §6.
    task_suffix = file_set.taskId.lower().replace("task-", "")
    semantic_wire = {
        "schema": "proof-forge.semantic-closeout-file-set.v1",
        "id": f"semantic-closeout-{task_suffix}",
        "version": "1.0.0",
        "taskId": file_set.taskId,
        "preCloseCandidate": {
            "commit": file_set.preCloseCandidate.commit,
            "treeObjectId": file_set.preCloseCandidate.treeObjectId,
            "archiveSha256": _TQO.digest_to_wire(file_set.preCloseCandidate.archiveDigest),
        },
        "changes": [
            {
                "path": p,
                "beforeDigest": _TQO.digest_to_wire(b) if b else None,
                "afterDigest": _TQO.digest_to_wire(a) if a else None,
            }
            for (p, b, a) in semantic_changes
        ],
    }
    return domain_digest(_TQO.DOMAIN_SEMANTIC_CLOSEOUT_FILE_SET, semantic_wire)


def _verify_closeout_diff_paths_equal_allowed_paths(
    file_set: CloseoutFileSetV1,
    patch: "AllowedCloseoutPatchV1",
    where: str,
) -> None:
    """GAP-13: §6 diff(C,D) paths must exact-equal AllowedCloseoutPatchV1.
    allowedPaths. The full closeout file set's changed paths (sorted) must
    exactly equal patch.allowedPaths (sorted). Extra/missing paths reject.
    """
    file_set_paths = sorted(c[0] for c in file_set.changes)
    allowed_paths = sorted(patch.allowedPaths)
    if file_set_paths != allowed_paths:
        _BTO._reject(
            f"{where}: closeout diff paths do not exact-equal "
            f"allowedCloseoutPatch.allowedPaths "
            f"(file_set={file_set_paths}, allowed={allowed_paths})")


def _verify_resulting_task_row_digest(
    qualification_task_row,
    patch: "AllowedCloseoutPatchV1",
    where: str,
    reserved_evidence_id: str | None = None,
) -> None:
    """Recompute the exact post-close task row bound by the allowed patch.

    Ordinary qualification closeout only flips ``status`` to ``done``.  The
    one-time D0-10 bridge additionally appends its separately reserved
    bootstrap Ledger evidence ID; that ID is intentionally absent from C's
    in-progress row and raw development evidence set.
    """
    evidence_ids = qualification_task_row.evidenceIds
    if reserved_evidence_id is not None:
        if reserved_evidence_id in evidence_ids:
            _BTO._reject(
                f"{where}: reserved ledger evidence ID already exists in C row")
        evidence_ids = evidence_ids + (reserved_evidence_id,)
        if evidence_ids != tuple(sorted(evidence_ids)):
            _BTO._reject(
                f"{where}: resulting evidence IDs must be ASCII-sorted")
    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=qualification_task_row.taskId,
        output=qualification_task_row.output,
        dependencies=qualification_task_row.dependencies,
        prerequisites=qualification_task_row.prerequisites,
        tests=qualification_task_row.tests,
        evidenceIds=evidence_ids,
        status="done",
    )
    computed = _TQO.task_row_digest(resulting_row)
    if computed.bytes != patch.resultingTaskRowDigest.bytes:
        _BTO._reject(
            f"{where}: resulting task row digest mismatch "
            f"(computed={computed.bytes.hex()}, "
            f"patch={patch.resultingTaskRowDigest.bytes.hex()})")


def _verify_semantic_file_set_digest(
    file_set: CloseoutFileSetV1,
    patch: "AllowedCloseoutPatchV1",
    verified_q_bytes: bytes,
    where: str,
) -> None:
    """§6: reconstruct the semantic file set from the full closeout file set
    and assert its digest equals patch.semanticFileSetDigest.

    GAP-12: the fixed Q/approval-path change's afterDigest must equal
    plain_sha256(verified_q_bytes) (the verified Q/approval subject bytes).

    The fixed Q/approval paths are those allowedPaths that end with
    qualification.json or bootstrap-approval.json (the fixed
    qualification/bootstrap-approval path per §5). Exactly one such path
    must appear as a change in the full file set.
    """
    fixed_q_paths = {
        p for p in patch.allowedPaths
        if p.endswith("qualification.json") or p.endswith("bootstrap-approval.json")
    }
    # GAP-12: assert the fixed-path change's afterDigest equals
    # plain_sha256(verified_q_bytes).
    fixed_changes = [c for c in file_set.changes if c[0] in fixed_q_paths]
    if len(fixed_changes) != 1:
        _BTO._reject(
            f"{where}: full file set must contain exactly one fixed "
            f"Q/approval-path change (found {len(fixed_changes)})")
    fixed_after = fixed_changes[0][2]
    if fixed_after is None:
        _BTO._reject(f"{where}: fixed Q/approval-path change has null afterDigest")
    expected_after = plain_sha256_digest(verified_q_bytes)
    if fixed_after.bytes != expected_after.bytes:
        _BTO._reject(
            f"{where}: fixed Q/approval-path afterDigest does not equal "
            f"plain_sha256(verified_q_bytes)")
    computed = _reconstruct_semantic_file_set_digest(file_set, fixed_q_paths, where)
    if computed.bytes != patch.semanticFileSetDigest.bytes:
        _BTO._reject(
            f"{where}: reconstructed semanticFileSetDigest does not equal "
            f"patch.semanticFileSetDigest")


def _verify_closeout_file_set_member(
    member_map: dict,
    expected_diff_digest: Digest,
    where: str,
) -> CloseoutFileSetV1:
    """Verify the closeout-file-set member and the diff digest (without archive reconstruction).

    Used when the verifier does not have access to the C/D archives (e.g. when
    the archives are not yet loaded). For full §6 compliance, use
    _verify_closeout_file_set_from_archives instead.
    """
    member = member_map.get("closeout-file-set")
    if member is None:
        _BTO._reject(f"{where}: closeout-file-set member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: closeout-file-set must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: closeout-file-set decode failed: {exc}")
    file_set = _TQO.parse_closeout_file_set(obj, f"{where}.closeout-file-set")
    # Recompute the closeout file set digest
    computed_diff = domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, obj)
    if computed_diff.bytes != expected_diff_digest.bytes:
        _BTO._reject(f"{where}: closeoutDiffDigest mismatch")
    # Recompute the content ref and verify it matches the member
    computed_ref = ContentRef(
        schema=file_set.schema,
        id=file_set.id,
        version=file_set.version,
        digest=computed_diff,
    )
    if member.content != computed_ref:
        _BTO._reject(f"{where}: closeout-file-set member content ref mismatch")
    return file_set


def _verify_closeout_file_set(
    member_map: dict,
    pre_archive: ArchiveProjection,
    close_archive: ArchiveProjection,
    closeout_file_set_ref: ContentRef,
    expected_diff_digest: Digest,
    where: str,
) -> CloseoutFileSetV1:
    """Verify the closeout file set member and the diff digest."""
    member = member_map.get("closeout-file-set")
    if member is None:
        _BTO._reject(f"{where}: closeout-file-set member missing")
    if not isinstance(member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: closeout-file-set must be typed-content")
    raw_bytes = bytes.fromhex(member.bytesHex)
    try:
        obj = decode_canonical_pf_jcs(raw_bytes)
    except Exception as exc:
        _BTO._reject(f"{where}: closeout-file-set decode failed: {exc}")
    file_set = _TQO.parse_closeout_file_set(obj, f"{where}.closeout-file-set")
    # Recompute the closeout file set digest
    computed_ref = ContentRef(
        schema=file_set.schema,
        id=file_set.id,
        version=file_set.version,
        digest=domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, obj),
    )
    if computed_ref != closeout_file_set_ref:
        _BTO._reject(f"{where}: closeout-file-set ref mismatch")
    if member.content != closeout_file_set_ref:
        _BTO._reject(f"{where}: closeout-file-set member content ref mismatch")
    # Verify the diff digest
    computed_diff = domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, obj)
    if computed_diff.bytes != expected_diff_digest.bytes:
        _BTO._reject(f"{where}: closeoutDiffDigest mismatch")
    return file_set


# ---------------------------------------------------------------------------
# Main verifier: verify_task_qualification_v1
# ---------------------------------------------------------------------------

def verify_task_qualification_v1(contentBundleBytes, subjectBytes):
    """Verify a TaskQualificationV1 subject against a content bundle.

    Pure consumer: takes exactly two positional byte arguments.
    Returns VerifiedTaskQualificationV1 or RejectedV1.
    """
    try:
        return _verify_task_qualification(contentBundleBytes, subjectBytes)
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"stage=bounds {exc}")


def _verify_task_qualification(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bounds", r)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bundle", r)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
        _check_aggregate_member_bound(bundle, "members")
    except (Rejected, Exception) as r:
        return _stage_exc("members", r)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        qualification = _TQO.parse_qualification(subject_obj, "subject")
    except (Rejected, Exception) as r:
        return _stage_exc("members", f"subject decode: {_exception_detail(r)}")

    # §8.2: profile.taskId must equal subject.taskId (production only).
    try:
        _verify_profile_task_id(profile, qualification.taskId, "profile")
        # §8.2: recompute full gateSetDigest from subject gates and exact-compare.
        if isinstance(profile, ProductionVerificationProfileV1):
            gate_ids = tuple(g.gateId for g in qualification.gates)
            _verify_profile_gate_set_digest(profile, bundle.operation, gate_ids, "profile")
            # §8.2: artifacts must exact-cover operation/gates.
            _verify_profile_artifacts_coverage(profile, bundle.operation, gate_ids, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4b: production profile member bytes (§8.2 line 497-500)
    # For production profiles, the bundle's embedded verificationProfile PF-JCS
    # bytes must equal the production-profile member's decoded bytes.
    if isinstance(profile, ProductionVerificationProfileV1):
        try:
            _verify_production_profile_member_bytes(member_map, profile, "members")
        except Rejected as r:
            return _reject_stage("members", r)

    # Stage 5: documents
    try:
        phase4_bytes = _verify_phase4_source(member_map, profile, "documents")
        phase5_bytes = _verify_phase5_source(member_map, profile, "documents")
        snapshot_parser = (
            _TQO.parse_fixture_taskqualification_snapshot_v1
            if isinstance(profile, FixtureVerificationProfileV1)
            else _TQO.parse_taskqualification_snapshot_v1
        )
        snapshot = snapshot_parser(
            phase4_bytes, phase5_bytes, qualification.taskId)
        if snapshot.row != qualification.taskRow:
            _BTO._reject(
                "documents: PHASE-4 snapshot row does not equal signed taskRow")
        if snapshot.tests != qualification.taskRow.tests:
            _BTO._reject(
                "documents: PHASE-5 snapshot tests do not equal signed taskRow.tests")
        freeze_bytes = _verify_freeze_package_source(member_map, profile, "documents")
        # §3/§8.2: join the recomputed freeze-package digest to the
        # qualification.freezePackage ref. taskId and digest must match.
        freeze_ref = qualification.freezePackage
        computed_freeze = _TQO.domain_digest_raw(
            _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes)
        if computed_freeze.bytes != freeze_ref.digest.bytes:
            _BTO._reject(
                "documents: freezePackage.digest does not recompute from "
                "freeze-package-source member")
        if freeze_ref.taskId != qualification.taskId:
            _BTO._reject(
                "documents: freezePackage.taskId must equal qualification.taskId")
    except (Rejected, Exception) as r:
        return _stage_exc("documents", r)

    # Stage 6: candidate
    try:
        archive, commit_obj = _verify_candidate(
            member_map, "candidate-archive", "candidate-commit-object",
            qualification.preCloseCandidate, qualification.taskId, "candidate",
            profile=profile,
        )
        _verify_candidate_source_bytes(
            archive, member_map,
            ("phase-4-source", "phase-5-source", "freeze-package-source"),
            "candidate.sources")
    except (Rejected, Exception) as r:
        return _stage_exc("candidate", r)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
        if qualification.authorityPolicy != policy_ref:
            _BTO._reject("policy: qualification.authorityPolicy mismatch")
        # For production profiles, verify the profile signatures now that policy is resolved
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_production_profile_signatures(profile, policy_obj, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("policy", r)

    # Stage 8: command
    try:
        command_policies = {
            gate.gateId: _verify_command_policy(
                member_map, gate, policy_obj, profile, "command")
            for gate in qualification.gates
        }
    except (Rejected, Exception) as r:
        return _stage_exc("command", r)

    # Stage 9: evidence
    try:
        evidence_documents = {
            gate.gateId: _verify_evidence_members(
                member_map, gate, qualification.preCloseCandidate,
                command_policies[gate.gateId], profile, "evidence")
            for gate in qualification.gates
        }
    except (Rejected, Exception) as r:
        return _stage_exc("evidence", r)

    # Stage 10: dependencies
    try:
        _verify_dependency_members(
            member_map, qualification.dependencies,
            qualification.taskRow.dependencies, policy_obj, profile,
            "dependencies")
    except (Rejected, Exception) as r:
        return _stage_exc("dependencies", r)

    # Stage 10b: ancestry graph (§8.3)
    # The ancestry graph is the union of parent-edge closure paths from C to
    # freezeCommit and from C to each direct dependency completionCommit. Every
    # commit's parents must be recursively represented; any missing parent,
    # unreachable target, or extra commit not in the union is rejected. Target
    # commits must not be duplicated as ancestry-commit/*. Receipt operations do
    # not carry this graph (§8.2).
    try:
        freeze_pkg = _parse_freeze_package_source_bytes(freeze_bytes, "ancestry")
        _verify_ancestry_graph(
            member_map,
            qualification.preCloseCandidate.commit,
            freeze_pkg.freezeCommit,
            qualification.dependencies,
            "ancestry",
        )
        # GAP-3: §3 row vs freeze package exact equality (taskId/output/
        # dependencies/prerequisites/tests).
        row = qualification.taskRow
        if row.taskId != freeze_pkg.taskId:
            _BTO._reject("ancestry: row.taskId != freeze.taskId")
        if row.output != freeze_pkg.output:
            _BTO._reject("ancestry: row.output != freeze.output")
        if tuple(row.dependencies) != freeze_pkg.dependencies:
            _BTO._reject("ancestry: row.dependencies != freeze.dependencies")
        if tuple(row.prerequisites) != freeze_pkg.prerequisites:
            _BTO._reject("ancestry: row.prerequisites != freeze.prerequisites")
        if tuple(row.tests) != freeze_pkg.tests:
            _BTO._reject("ancestry: row.tests != freeze.tests")
    except (Rejected, Exception) as r:
        return _stage_exc("dependencies", r)

    # Stage 11: reviews
    try:
        # Build signing principal IDs from the authority policy
        if isinstance(policy_obj, _TQO.FixturePolicyV1):
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        else:
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        _verify_review_members(member_map, qualification.independentReviews, bundle.implementationInvocationId, signing_principal_ids, qualification.preCloseCandidate.commit, "reviews")
    except (Rejected, Exception) as r:
        return _stage_exc("reviews", r)

    # Stage 12: controls
    try:
        _verify_gate_test_ids_union(qualification.gates, qualification.taskRow, "controls")
        # GAP-24: §8.2 gate-keyed member suffixes must exactly equal declared
        # gateIds. Any phantom gateId (member with no matching gate) or missing
        # gateId (gate with no keyed members) must reject.
        _verify_gate_keyed_roles_match_gates(
            member_map, qualification.gates, profile, "controls")
        for gate in qualification.gates:
            _verify_gate_controls(
                member_map, gate, profile, policy_obj, policy_ref,
                qualification.preCloseCandidate, bundle.verificationInstant,
                command_policies[gate.gateId],
                evidence_documents[gate.gateId], "controls")
    except (Rejected, Exception) as r:
        return _stage_exc("controls", r)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, qualification.allowedCloseoutPatch, "patch")
        _verify_patch_join(
            patch, qualification.taskId, qualification.preCloseCandidate,
            "patch")
        if any(command.verifier != qualification.verifier
               for command in command_policies.values()):
            _BTO._reject("patch: qualification verifier != gate command verifier")
    except (Rejected, Exception) as r:
        return _stage_exc("patch", r)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, qualification.signatures, policy_obj, profile,
            _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
            _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
            "signatures",
        )
    except (Rejected, Exception) as r:
        return _stage_exc("signatures", r)

    # Stage 15: projection
    # For qualification, the projection is the qualification digest itself
    try:
        computed_digest = domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, subject_obj)
        if computed_digest != _TQO.TaskQualificationRefV1(
            taskId=qualification.taskId, id=qualification.id, digest=computed_digest
        ).digest:
            _BTO._reject("projection: qualification digest mismatch")
    except (Rejected, Exception) as r:
        return _stage_exc("projection", r)

    return VerifiedTaskQualificationV1(
        taskId=qualification.taskId,
        preCloseCandidate=qualification.preCloseCandidate,
        qualification=qualification,
        allowedCloseoutPatch=patch,
        authorityPolicy=policy_ref,
        verificationInstant=bundle.verificationInstant,
        authorityClass=authority_class,
    )


# ---------------------------------------------------------------------------
# Main verifier: verify_task_completion_receipt_v1
# ---------------------------------------------------------------------------

def verify_task_completion_receipt_v1(contentBundleBytes, subjectBytes):
    """Verify a TaskCompletionReceiptV1 subject against a content bundle."""
    try:
        return _verify_task_completion(contentBundleBytes, subjectBytes)
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"stage=bounds {exc}")


def _verify_task_completion(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bounds", r)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bundle", r)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
        _check_aggregate_member_bound(bundle, "members")
    except (Rejected, Exception) as r:
        return _stage_exc("members", r)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        receipt = _TQO.parse_completion_receipt(subject_obj, "subject")
    except (Rejected, Exception) as r:
        return _stage_exc("members", f"subject decode: {_exception_detail(r)}")

    # §8.2: profile.taskId must equal subject.taskId (production only).
    try:
        _verify_profile_task_id(profile, receipt.taskId, "profile")
        # §8.2: receipt operations have zero gate IDs and zero artifacts.
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_profile_gate_set_digest(profile, bundle.operation, (), "profile")
            _verify_profile_artifacts_coverage(profile, bundle.operation, (), "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 5: documents — receipt operations have zero evidence/review/dependency
    # (no document verification needed for receipt)

    # Stage 6: candidate — verify pre-close and closeout archives
    try:
        pre_archive, pre_commit = _verify_candidate(
            member_map, "pre-close-archive", "pre-close-commit-object",
            receipt.preCloseCandidate, receipt.taskId, "candidate.pre-close",
            profile=profile,
        )
        close_archive, close_commit = _verify_candidate(
            member_map, "closeout-archive", "closeout-commit-object",
            receipt.closeoutCandidate, receipt.taskId, "candidate.closeout",
            profile=profile, enforce_fixture_candidate_prefix=False,
        )
        # Verify D parent is C
        if len(close_commit.parents) != 1:
            _BTO._reject("candidate.closeout: D must have exactly one parent")
        if close_commit.parents[0] != receipt.preCloseCandidate.commit:
            _BTO._reject("candidate.closeout: D parent must be C")
    except (Rejected, Exception) as r:
        return _stage_exc("candidate", r)

    # Stage 6b: qualification — authenticate the signed prior qualification
    # subject by digest join (§8.1/§8.2). Receipt operations do not replay the
    # prior qualification closure, but the bundle's qualification member must
    # recompute to a full digest equal to receipt.qualification.digest, and the
    # ref's taskId/id must match. The parsed qualification is carried in the
    # projection (VerifiedTaskCompletionV1.qualification is non-Optional per §8.1).
    try:
        qualification = _verify_receipt_qualification_member(
            member_map, receipt.qualification, receipt.taskId, "qualification",
        )
    except (Rejected, Exception) as r:
        return _stage_exc("members", r)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
        if receipt.authorityPolicy != policy_ref:
            _BTO._reject("policy: receipt.authorityPolicy mismatch")
        if qualification.authorityPolicy != policy_ref:
            _BTO._reject("policy: prior qualification authorityPolicy mismatch")
        if qualification.preCloseCandidate != receipt.preCloseCandidate:
            _BTO._reject("policy: prior qualification candidate mismatch")
        if qualification.allowedCloseoutPatch != receipt.allowedCloseoutPatch:
            _BTO._reject("policy: prior qualification patch mismatch")
        _verify_signatures(
            decode_canonical_pf_jcs(bytes.fromhex(
                member_map["qualification"].bytesHex)),
            qualification.signatures, policy_obj, profile,
            _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
            _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
            "policy.qualification-signatures")
        # For production profiles, verify the profile signatures now that policy is resolved
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_production_profile_signatures(profile, policy_obj, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("policy", r)

    # Receipt operations have no gates, but still authenticate the complete
    # current revocation snapshot and its record closure.
    try:
        _verify_receipt_revocation(
            member_map, profile, policy_obj, policy_ref,
            receipt.revocationSnapshot, "controls.revocation")
        if receipt.issuedAt > bundle.verificationInstant:
            _BTO._reject("controls: receipt issuedAt is after verificationInstant")
    except (Rejected, Exception) as r:
        return _stage_exc("controls", r)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, receipt.allowedCloseoutPatch, "patch")
        _verify_patch_join(
            patch, receipt.taskId, receipt.preCloseCandidate, "patch")
    except (Rejected, Exception) as r:
        return _stage_exc("patch", r)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, receipt.signatures, policy_obj, profile,
            _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
            _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
            "signatures",
        )
    except (Rejected, Exception) as r:
        return _stage_exc("signatures", r)

    # Stage 15: projection — verify closeout file set and diff from archives
    try:
        file_set = _verify_closeout_file_set_from_archives(
            member_map, pre_archive, close_archive,
            receipt.closeoutDiffDigest, "projection",
        )
        # GAP-13: §6 diff(C,D) paths must exact-equal allowedCloseoutPatch.
        # allowedPaths.
        _verify_closeout_diff_paths_equal_allowed_paths(file_set, patch, "projection")
        # GAP-13: §6 resulting row 与 AllowedCloseoutPatchV1 exact. Recompute
        # the resulting row digest (status flipped to done) and assert equals
        # patch.resultingTaskRowDigest.
        _verify_resulting_task_row_digest(
            qualification.taskRow, patch, "projection")
        # §6: reconstruct the semantic file set from the full closeout file
        # set and assert its digest equals patch.semanticFileSetDigest.
        # GAP-12: the fixed-path change's afterDigest must equal
        # plain_sha256(verified qualification bytes).
        qual_member = member_map.get("qualification")
        if qual_member is None:
            _BTO._reject("projection: qualification member missing")
        verified_q_bytes = bytes.fromhex(qual_member.bytesHex)
        _verify_semantic_file_set_digest(file_set, patch, verified_q_bytes, "projection")
    except (Rejected, Exception) as r:
        return _stage_exc("projection", r)

    return VerifiedTaskCompletionV1(
        taskId=receipt.taskId,
        preCloseCandidate=receipt.preCloseCandidate,
        closeoutCandidate=receipt.closeoutCandidate,
        qualification=qualification,  # §8.1: non-Optional, parsed from bundle member
        receipt=receipt,
        closeoutDiffDigest=receipt.closeoutDiffDigest,
        authorityPolicy=policy_ref,
        verificationInstant=bundle.verificationInstant,
        authorityClass=authority_class,
    )


# ---------------------------------------------------------------------------
# Main verifier: verify_d0_10_bootstrap_v1
# ---------------------------------------------------------------------------

def verify_d0_10_bootstrap_v1(contentBundleBytes, subjectBytes):
    """Verify a D0_10BootstrapApprovalV1 subject against a content bundle."""
    try:
        return _verify_d0_10_approval(contentBundleBytes, subjectBytes)
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"stage=bounds {exc}")


def _verify_d0_10_approval(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bounds", r)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bundle", r)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
        _check_aggregate_member_bound(bundle, "members")
    except (Rejected, Exception) as r:
        return _stage_exc("members", r)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        approval = _TQO.parse_d0_10_bootstrap_approval(subject_obj, "subject")
        if approval.ledgerEvidenceId in approval.taskRow.evidenceIds:
            _BTO._reject(
                "subject: reserved ledgerEvidenceId must be absent from C's "
                "development evidence IDs")
    except (Rejected, Exception) as r:
        return _stage_exc("members", f"subject decode: {_exception_detail(r)}")

    # §8.2: profile.taskId must equal subject.taskId (production only).
    try:
        _verify_profile_task_id(profile, approval.taskId, "profile")
        # §8.2: recompute full gateSetDigest from subject bootstrapGate.
        if isinstance(profile, ProductionVerificationProfileV1):
            gate_ids = (approval.bootstrapGate.gateId,)
            _verify_profile_gate_set_digest(profile, bundle.operation, gate_ids, "profile")
            # §8.2: artifacts must exact-cover operation/gates.
            _verify_profile_artifacts_coverage(profile, bundle.operation, gate_ids, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4b: production profile member bytes (§8.2 line 497-500)
    if isinstance(profile, ProductionVerificationProfileV1):
        try:
            _verify_production_profile_member_bytes(member_map, profile, "members")
        except Rejected as r:
            return _reject_stage("members", r)

    # Stage 5: documents
    try:
        phase4_bytes = _verify_phase4_source(member_map, profile, "documents")
        phase5_bytes = _verify_phase5_source(member_map, profile, "documents")
        snapshot_parser = (
            _TQO.parse_fixture_taskqualification_snapshot_v1
            if isinstance(profile, FixtureVerificationProfileV1)
            else _TQO.parse_taskqualification_snapshot_v1
        )
        snapshot = snapshot_parser(
            phase4_bytes, phase5_bytes, approval.taskId)
        if snapshot.row != approval.taskRow:
            _BTO._reject(
                "documents: PHASE-4 snapshot row does not equal signed taskRow")
        if snapshot.tests != approval.taskRow.tests:
            _BTO._reject(
                "documents: PHASE-5 snapshot tests do not equal signed taskRow.tests")
        # ruling-source
        ruling_bytes, ruling_ref = _resolve_raw_member(member_map, "ruling-source", "documents")
        # NEW-2: §8.2 ruling-source path is fixed ("path固定"). The fixture
        # profile uses "fixtures/task-qualification/ruling.md".
        if isinstance(profile, FixtureVerificationProfileV1):
            expected_ruling_path = "fixtures/task-qualification/ruling.md"
        else:
            expected_ruling_path = (
                "docs/governance/task-qualification-bootstrap-ruling.md")
        if ruling_ref.path != expected_ruling_path:
            _BTO._reject(
                f"documents: ruling-source path must be '{expected_ruling_path}', "
                f"got '{ruling_ref.path}'")
        # Parse the complete carrier and join every projected ref field; a
        # digest-only check would leave status/reviewCommit caller-controlled.
        ruling_parser = (
            _TQO.parse_fixture_qualification_normative_document_v1
            if isinstance(profile, FixtureVerificationProfileV1)
            else _TQO.parse_qualification_normative_document_v1
        )
        projected_ruling = ruling_parser(
            ruling_bytes, approval.ruling.id)
        projected_fields = (
            projected_ruling.id, projected_ruling.status,
            projected_ruling.contentDigest, projected_ruling.reviewCommit)
        approval_fields = (
            approval.ruling.id, approval.ruling.status,
            approval.ruling.contentDigest, approval.ruling.reviewCommit)
        if projected_fields != approval_fields:
            _BTO._reject(
                "documents: ruling ref does not equal ruling-source projection")
        # §3/§8.2: join the recomputed freeze-package digest to the
        # approval.freezePackage ref. taskId and digest must match.
        freeze_bytes = _verify_freeze_package_source(member_map, profile, "documents")
        freeze_ref = approval.freezePackage
        computed_freeze = _TQO.domain_digest_raw(
            _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes)
        if computed_freeze.bytes != freeze_ref.digest.bytes:
            _BTO._reject(
                "documents: freezePackage.digest does not recompute from "
                "freeze-package-source member")
        if freeze_ref.taskId != approval.taskId:
            _BTO._reject(
                "documents: freezePackage.taskId must equal approval.taskId")
    except (Rejected, Exception) as r:
        return _stage_exc("documents", r)

    # Stage 6: candidate
    try:
        archive, commit_obj = _verify_candidate(
            member_map, "candidate-archive", "candidate-commit-object",
            approval.preCloseCandidate, approval.taskId, "candidate",
            profile=profile,
        )
        _verify_candidate_source_bytes(
            archive, member_map,
            ("phase-4-source", "phase-5-source", "freeze-package-source",
             "ruling-source", "d0-07-ruling-source"),
            "candidate.sources")
    except (Rejected, Exception) as r:
        return _stage_exc("candidate", r)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
        if approval.authorityPolicy != policy_ref:
            _BTO._reject("policy: approval.authorityPolicy mismatch")
        if approval.d0_07Bridge.authorityPolicy != policy_ref:
            _BTO._reject("policy: D0-07 bridge authorityPolicy mismatch")
        # For production profiles, verify the profile signatures now that policy is resolved
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_production_profile_signatures(profile, policy_obj, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("policy", r)

    # Stage 8: command — verify the single bootstrap gate
    try:
        bootstrap_command_policy = _verify_command_policy(
            member_map, approval.bootstrapGate, policy_obj, profile, "command")
    except (Rejected, Exception) as r:
        return _stage_exc("command", r)

    # Stage 9: evidence
    try:
        bootstrap_evidence_documents = _verify_evidence_members(
            member_map, approval.bootstrapGate, approval.preCloseCandidate,
            bootstrap_command_policy, profile, "evidence")
    except (Rejected, Exception) as r:
        return _stage_exc("evidence", r)

    # Stage 10: dependencies — verify D0-07 bridge
    try:
        # The d0-07 bridge is a GovernanceBootstrapReceiptDependencyV1
        # Verify the d0-07-governance-completion, d0-07-completion-archive,
        # d0-07-completion-commit-object members
        bridge = approval.d0_07Bridge
        # Verify the governance completion object
        gc_member = member_map.get("d0-07-governance-completion")
        if gc_member is None:
            _BTO._reject("dependencies: d0-07-governance-completion member missing")
        if not isinstance(gc_member, _TQO.TypedContentMemberV1):
            _BTO._reject("dependencies: d0-07-governance-completion must be typed-content")
        gc_bytes = bytes.fromhex(gc_member.bytesHex)
        gc_obj = decode_canonical_pf_jcs(gc_bytes)
        gc = _TQO.parse_governance_bootstrap_completion(gc_obj, "dependencies.d0-07-governance-completion")
        # P1-4: verify the D0-07 governance completion internal consistency.
        _verify_d0_07_bridge_internal(
            member_map, gc_member, gc_obj, gc, bridge, policy_obj, profile,
            "dependencies.d0-07-bridge",
        )
        # Verify the archive and commit object members
        _resolve_archive_member(member_map, "d0-07-completion-archive", "dependencies")
        _resolve_git_object_member(member_map, "d0-07-completion-commit-object", "dependencies")
    except (Rejected, Exception) as r:
        return _stage_exc("dependencies", r)

    # Stage 10b: ancestry graph (§8.3)
    # D0-10 approval targets: C, freezeCommit, D0-07 completionCommit. The
    # D0-07 completionCommit must be a strict ancestor of C.
    try:
        freeze_pkg = _parse_freeze_package_source_bytes(freeze_bytes, "ancestry")
        if isinstance(profile, ProductionVerificationProfileV1):
            if (
                freeze_pkg.exceptionId != _TQO.D0_10_FREEZE_EXCEPTION_ID
                or freeze_pkg.exceptionExpiresAt
                != _TQO.D0_10_FREEZE_EXCEPTION_EXPIRES_AT
            ):
                _BTO._reject("ancestry: D0-10 ADR-0021 exception metadata missing")
            if bundle.verificationInstant >= freeze_pkg.exceptionExpiresAt:
                _BTO._reject("ancestry: D0-10 freeze exception expired")
        _verify_ancestry_graph(
            member_map,
            approval.preCloseCandidate.commit,
            freeze_pkg.freezeCommit,
            (),  # D0-10 approval has no task-qualification dependencies
            "ancestry",
            extra_target_roles={
                "d0-07-completion-commit-object": approval.d0_07Bridge.completionCommit,
            },
        )
        # GAP-3: §3 row vs freeze package exact equality (taskId/output/
        # dependencies/prerequisites/tests).
        row = approval.taskRow
        if row.taskId != freeze_pkg.taskId:
            _BTO._reject("ancestry: row.taskId != freeze.taskId")
        if row.output != freeze_pkg.output:
            _BTO._reject("ancestry: row.output != freeze.output")
        if tuple(row.dependencies) != freeze_pkg.dependencies:
            _BTO._reject("ancestry: row.dependencies != freeze.dependencies")
        if tuple(row.prerequisites) != freeze_pkg.prerequisites:
            _BTO._reject("ancestry: row.prerequisites != freeze.prerequisites")
        if tuple(row.tests) != freeze_pkg.tests:
            _BTO._reject("ancestry: row.tests != freeze.tests")
    except (Rejected, Exception) as r:
        return _stage_exc("dependencies", r)

    # Stage 11: reviews
    try:
        # Build signing principal IDs from the authority policy
        if isinstance(policy_obj, _TQO.FixturePolicyV1):
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        else:
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        _verify_review_members(member_map, approval.independentReviews, bundle.implementationInvocationId, signing_principal_ids, approval.preCloseCandidate.commit, "reviews")
    except (Rejected, Exception) as r:
        return _stage_exc("reviews", r)

    # Stage 12: controls
    try:
        _verify_gate_test_ids_union((approval.bootstrapGate,), approval.taskRow, "controls")
        # GAP-24: §8.2 gate-keyed member suffixes must exactly equal declared
        # gateIds (here a single bootstrapGate).
        _verify_gate_keyed_roles_match_gates(
            member_map, (approval.bootstrapGate,), profile, "controls")
        _verify_gate_controls(
            member_map, approval.bootstrapGate, profile, policy_obj,
            policy_ref, approval.preCloseCandidate,
            bundle.verificationInstant, bootstrap_command_policy,
            bootstrap_evidence_documents, "controls")
        _verify_d0_top_level_identities(
            member_map, profile, approval, bootstrap_command_policy,
            "controls.top-level")
    except (Rejected, Exception) as r:
        return _stage_exc("controls", r)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, approval.allowedCloseoutPatch, "patch")
        _verify_patch_join(
            patch, approval.taskId, approval.preCloseCandidate, "patch")
    except (Rejected, Exception) as r:
        return _stage_exc("patch", r)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, approval.signatures, policy_obj, profile,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
            "signatures",
        )
    except (Rejected, Exception) as r:
        return _stage_exc("signatures", r)

    # Stage 15: projection
    try:
        computed_digest = domain_digest(_TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, subject_obj)
        # The approval digest is the full object digest
    except (Rejected, Exception) as r:
        return _stage_exc("projection", r)

    return VerifiedD0_10BootstrapApprovalV1(
        taskId=approval.taskId,
        preCloseCandidate=approval.preCloseCandidate,
        approvalDigest=computed_digest,
        allowedCloseoutPatch=patch,
        authorityPolicy=policy_ref,
        verificationInstant=bundle.verificationInstant,
        authorityClass=authority_class,
    )


# ---------------------------------------------------------------------------
# Main verifier: verify_d0_10_bootstrap_receipt_v1
# ---------------------------------------------------------------------------

def verify_d0_10_bootstrap_receipt_v1(contentBundleBytes, subjectBytes):
    """Verify a D0_10BootstrapReceiptV1 subject against a content bundle."""
    try:
        return _verify_d0_10_receipt(contentBundleBytes, subjectBytes)
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"stage=bounds {exc}")


def _verify_d0_10_receipt(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bounds", r)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except (Rejected, Exception) as r:
        return _stage_exc("bundle", r)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
        _check_aggregate_member_bound(bundle, "members")
    except (Rejected, Exception) as r:
        return _stage_exc("members", r)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        receipt = _TQO.parse_d0_10_bootstrap_receipt(subject_obj, "subject")
    except (Rejected, Exception) as r:
        return _stage_exc("members", f"subject decode: {_exception_detail(r)}")

    # §8.2: profile.taskId must equal subject.taskId (production only).
    try:
        _verify_profile_task_id(profile, receipt.taskId, "profile")
        # §8.2: receipt operations have zero gate IDs and zero artifacts.
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_profile_gate_set_digest(profile, bundle.operation, (), "profile")
            _verify_profile_artifacts_coverage(profile, bundle.operation, (), "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("profile", r)

    # Stage 5: documents — receipt operations have zero evidence/review/dependency

    # Stage 6: candidate — verify pre-close and closeout archives
    try:
        pre_archive, pre_commit = _verify_candidate(
            member_map, "pre-close-archive", "pre-close-commit-object",
            receipt.preCloseCandidate, receipt.taskId, "candidate.pre-close",
            profile=profile,
        )
        close_archive, close_commit = _verify_candidate(
            member_map, "closeout-archive", "closeout-commit-object",
            receipt.closeoutCandidate, receipt.taskId, "candidate.closeout",
            profile=profile, enforce_fixture_candidate_prefix=False,
        )
        # Verify D parent is C
        if len(close_commit.parents) != 1:
            _BTO._reject("candidate.closeout: D must have exactly one parent")
        if close_commit.parents[0] != receipt.preCloseCandidate.commit:
            _BTO._reject("candidate.closeout: D parent must be C")
    except (Rejected, Exception) as r:
        return _stage_exc("candidate", r)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
        if receipt.authorityPolicy != policy_ref:
            _BTO._reject("policy: receipt.authorityPolicy mismatch")
        # For production profiles, verify the profile signatures now that policy is resolved
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_production_profile_signatures(profile, policy_obj, "profile")
    except (Rejected, Exception) as r:
        return _stage_exc("policy", r)

    try:
        _verify_receipt_revocation(
            member_map, profile, policy_obj, policy_ref,
            receipt.revocationSnapshot, "controls.revocation")
        if receipt.issuedAt > bundle.verificationInstant:
            _BTO._reject("controls: receipt issuedAt is after verificationInstant")
    except (Rejected, Exception) as r:
        return _stage_exc("controls", r)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, receipt.allowedCloseoutPatch, "patch")
        _verify_patch_join(
            patch, receipt.taskId, receipt.preCloseCandidate, "patch")
    except (Rejected, Exception) as r:
        return _stage_exc("patch", r)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, receipt.signatures, policy_obj, profile,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
            "signatures",
        )
    except (Rejected, Exception) as r:
        return _stage_exc("signatures", r)

    # Stage 15: projection — verify closeout file set and diff from archives,
    # then verify the bootstrap-approval member, then reconstruct the semantic
    # file set using the verified approval bytes as the fixed Q/approval path.
    try:
        file_set = _verify_closeout_file_set_from_archives(
            member_map, pre_archive, close_archive,
            receipt.closeoutDiffDigest, "projection",
        )
        # GAP-13: §6 diff(C,D) paths must exact-equal allowedCloseoutPatch.
        # allowedPaths.
        _verify_closeout_diff_paths_equal_allowed_paths(file_set, patch, "projection")
        # Verify the bootstrap-approval member and capture its verified bytes
        # for the GAP-12 fixed-path afterDigest check.
        approval_member = member_map.get("bootstrap-approval")
        if approval_member is None:
            _BTO._reject("projection: bootstrap-approval member missing")
        if not isinstance(approval_member, _TQO.TypedContentMemberV1):
            _BTO._reject("projection: bootstrap-approval must be typed-content")
        approval_bytes = bytes.fromhex(approval_member.bytesHex)
        approval_obj = decode_canonical_pf_jcs(approval_bytes)
        approval = _TQO.parse_d0_10_bootstrap_approval(approval_obj, "projection.bootstrap-approval")
        computed_approval_digest = domain_digest(
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, approval_obj)
        if approval_member.content != ContentRef(
                schema=approval.schema, id=approval.id, version=approval.version,
                digest=computed_approval_digest):
            _BTO._reject("projection: bootstrap-approval member ref mismatch")
        if (
            approval.taskId != receipt.taskId
            or approval.preCloseCandidate != receipt.preCloseCandidate
            or approval.authorityPolicy != policy_ref
            or approval.allowedCloseoutPatch != receipt.allowedCloseoutPatch
            or approval.ruling != receipt.ruling
        ):
            _BTO._reject("projection: approval/receipt identity join mismatch")
        _verify_signatures(
            approval_obj, approval.signatures, policy_obj, profile,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
            "projection.bootstrap-approval.signatures")
        # §7: approval and receipt ledgerEvidenceId must be逐字 equal.
        if approval.ledgerEvidenceId != receipt.ledgerEvidenceId:
            _BTO._reject(
                "projection: approval and receipt ledgerEvidenceId must be equal"
            )
        # Verify the approval digest matches
        if computed_approval_digest != receipt.approvalDigest:
            _BTO._reject("projection: approval digest mismatch")
        # GAP-13: §6 resulting row 与 AllowedCloseoutPatchV1 exact. Recompute
        # the resulting row digest (status flipped to done) and assert equals
        # patch.resultingTaskRowDigest. The approval's taskRow is the
        # in_progress row that the resulting row derives from.
        _verify_resulting_task_row_digest(
            approval.taskRow, patch, "projection", receipt.ledgerEvidenceId)
        # §6: reconstruct the semantic file set from the full closeout file
        # set and assert its digest equals patch.semanticFileSetDigest.
        # GAP-12: the fixed-path change's afterDigest must equal
        # plain_sha256(verified approval bytes).
        _verify_semantic_file_set_digest(file_set, patch, approval_bytes, "projection")
    except (Rejected, Exception) as r:
        return _stage_exc("projection", r)

    receipt_digest = domain_digest(_TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT, subject_obj)

    return VerifiedD0_10BootstrapCompletionV1(
        taskId=receipt.taskId,
        preCloseCandidate=receipt.preCloseCandidate,
        closeoutCandidate=receipt.closeoutCandidate,
        approvalDigest=receipt.approvalDigest,
        receiptDigest=receipt_digest,
        closeoutDiffDigest=receipt.closeoutDiffDigest,
        authorityPolicy=policy_ref,
        verificationInstant=bundle.verificationInstant,
        authorityClass=authority_class,
    )