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

import re
from dataclasses import dataclass
from typing import Tuple

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
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


# ---------------------------------------------------------------------------
# Stage 2: bundle decode
# ---------------------------------------------------------------------------

def _decode_bundle(content_bundle_bytes: bytes) -> TaskQualificationContentBundleV1:
    """Decode the content bundle from canonical PF-JCS bytes."""
    try:
        obj = decode_canonical_pf_jcs(content_bundle_bytes)
    except Exception as exc:
        _BTO._reject(f"bundle decode failed: {exc}")
    return _TQO.parse_content_bundle(obj, "bundle")


# ---------------------------------------------------------------------------
# Stage 3: profile verification
# ---------------------------------------------------------------------------

def _verify_profile(bundle: TaskQualificationContentBundleV1) -> tuple:
    """Verify the verification profile and return (profile, authority_class, policy_ref)."""
    profile = bundle.verificationProfile
    if isinstance(profile, ProductionVerificationProfileV1):
        # Production profile — verify signature
        _verify_production_profile_signatures(profile, "profile")
        # Verify namespace
        if profile.namespace != _TQO.FIXTURE_PRODUCTION_NAMESPACE:
            _BTO._reject(f"profile.namespace must be {_TQO.FIXTURE_PRODUCTION_NAMESPACE}")
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
        "freeze-package-source", "candidate-archive", "candidate-commit-object",
        "authority-policy", "revocation-snapshot",
        "d0-07-governance-completion", "d0-07-completion-archive",
        "d0-07-completion-commit-object", "allowed-closeout-patch",
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
        "command-policy/", "resolved-tool/", "resolved-probe/",
        "sandbox-policy/", "verifier-executable/", "verifier-closure/",
        "verifier-build-policy/", "eligible-stage0-handoff/",
        "session-containment/", "freshness/", "private-scan/",
        "private-scan-policy/", "authority-store-service/",
        "host-observation/", "host-profile/",
    ),
    "task-completion": (
        "revocation-record/",
    ),
    "d0-10-bootstrap-approval": (
        "evidence/", "review-report/", "dependency/", "dependency-archive/",
        "dependency-commit-object/", "ancestry-commit/", "revocation-record/",
        "command-policy/", "resolved-tool/", "resolved-probe/",
        "sandbox-policy/", "verifier-executable/", "verifier-closure/",
        "verifier-build-policy/", "eligible-stage0-handoff/",
        "session-containment/", "freshness/", "private-scan/",
        "private-scan-policy/", "authority-store-service/",
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
    for role in required:
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

    # Check that all member roles are either required singletons or valid family members
    for role in member_map:
        if role in required:
            continue
        # Check if it's a valid family member
        is_valid_family = any(role.startswith(prefix) for prefix in family_prefixes)
        if not is_valid_family:
            _BTO._reject(f"{where}: role '{role}' is not a valid singleton or family member for operation '{operation}'")


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


def _verify_freeze_package_source(member_map: dict, where: str) -> bytes:
    """Verify the freeze-package-source member and return raw bytes."""
    raw_bytes, raw_ref = _resolve_raw_member(
        member_map, "freeze-package-source", where,
        domain=_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE,
    )
    return raw_bytes


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
    return (archive, commit_obj)


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
    where: str,
) -> TaskCommandPolicyV1:
    """Verify a gate's command policy member and return the parsed policy."""
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
    return cmd


# ---------------------------------------------------------------------------
# Stage 9: evidence verification
# ---------------------------------------------------------------------------

def _verify_evidence_members(
    member_map: dict,
    gate: TaskQualificationGateV1,
    where: str,
) -> None:
    """Verify evidence members for a gate."""
    for ev_ref in gate.evidence:
        role = f"evidence/{ev_ref.id}"
        member = member_map.get(role)
        if member is None:
            _BTO._reject(f"{where}: {role} member missing")
        if not isinstance(member, _TQO.RawContentMemberV1):
            _BTO._reject(f"{where}: {role} must be raw-source")
        raw_bytes = bytes.fromhex(member.bytesHex)
        computed = plain_sha256_digest(raw_bytes)
        if computed.bytes != ev_ref.digest.bytes:
            _BTO._reject(f"{where}: {role} evidence digest mismatch")


# ---------------------------------------------------------------------------
# Stage 10: dependencies verification
# ---------------------------------------------------------------------------

def _verify_dependency_members(
    member_map: dict,
    dependencies: tuple,
    where: str,
) -> None:
    """Verify dependency members for each dependency."""
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
        # Verify objectDigest matches
        computed = domain_digest(_TQO.DOMAIN_DEPENDENCY_OBJECT, raw_bytes)
        if computed.bytes != dep.objectDigest.bytes:
            _BTO._reject(f"{where}: {role} object digest mismatch")
        # Verify dependency archive member
        if archive_role in member_map:
            _resolve_archive_member(member_map, archive_role, where)
        # Verify dependency commit object member
        if commit_role in member_map:
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
    """§8.3 bounded P0/P1 parser on review report raw bytes.

    Rejects if the report contains:
    - Invalid UTF-8 (review reports must be UTF-8 text)
    - ASCII case-sensitive line starting with "Severity: P0" or "Severity: P1"
    - ASCII case-sensitive line starting with "P0:" or "P1:"
    - Case-insensitive whole-word "unresolved"

    The spec says we must not trust a summary field; we scan the raw bytes.
    """
    try:
        text = raw_bytes.decode("utf-8")
    except UnicodeDecodeError:
        _BTO._reject(f"{where}: review report is not valid UTF-8")
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("Severity: P0") or stripped.startswith("Severity: P1"):
            _BTO._reject(f"{where}: review report contains P0/P1 severity line")
        if stripped.startswith("P0:") or stripped.startswith("P1:"):
            _BTO._reject(f"{where}: review report contains P0/P1 finding prefix")
    import re
    if re.search(r"\bunresolved\b", text, re.IGNORECASE):
        _BTO._reject(f"{where}: review report contains 'unresolved'")


# ---------------------------------------------------------------------------
# Stage 12: controls verification (gate control members)
# ---------------------------------------------------------------------------

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


def _verify_gate_controls(
    member_map: dict,
    gate: TaskQualificationGateV1,
    profile,
    where: str,
) -> None:
    """Verify gate control members (handoff, containment, freshness, scan).

    Per §8.2, gate-keyed controls are: eligible-stage0-handoff, session-containment,
    freshness, private-scan, private-scan-policy, authority-store-service,
    host-observation, host-profile, command-policy, resolved-tool, resolved-probe,
    sandbox-policy, verifier-executable, verifier-closure, verifier-build-policy.
    The revocation-snapshot is a bundle-level singleton, not gate-keyed.

    Per §8.2, every typed-content member's content ref must be recomputed from
    its bytesHex under the schema's domain; the verifier must not trust a
    stale member.content.digest.
    """
    # Gate-keyed controls
    gate_keyed_controls = [
        ("eligible-stage0-handoff", gate.eligibleStage0Handoff),
        ("session-containment", gate.sessionContainment),
        ("freshness", gate.freshness),
        ("private-scan", gate.privateScan),
    ]
    for control_name, ref in gate_keyed_controls:
        role = f"{control_name}/{gate.gateId}"
        member = member_map.get(role)
        if member is None:
            _BTO._reject(f"{where}: {role} member missing")
        if not isinstance(member, _TQO.TypedContentMemberV1):
            _BTO._reject(f"{where}: {role} must be typed-content")
        _verify_typed_member_recompute(member, ref, f"{where}: {role}")

    # Revocation snapshot is a bundle-level singleton (not gate-keyed)
    revocation_member = member_map.get("revocation-snapshot")
    if revocation_member is None:
        _BTO._reject(f"{where}: revocation-snapshot singleton member missing")
    if not isinstance(revocation_member, _TQO.TypedContentMemberV1):
        _BTO._reject(f"{where}: revocation-snapshot must be typed-content")
    _verify_typed_member_recompute(
        revocation_member, gate.revocationSnapshot,
        f"{where}: revocation-snapshot")


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
        return Rejected(TASKQUAL_REJECTION, f"stage=unknown {exc}")


def _verify_task_qualification(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except Rejected as r:
        return _reject_stage("bounds", r.detail)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except Rejected as r:
        return _reject_stage("bundle", r.detail)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except Rejected as r:
        return _reject_stage("profile", r.detail)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
    except Rejected as r:
        return _reject_stage("members", r.detail)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        qualification = _TQO.parse_qualification(subject_obj, "subject")
    except Rejected as r:
        return _reject_stage("members", f"subject decode: {r.detail}")

    # Stage 5: documents
    try:
        phase4_bytes = _verify_phase4_source(member_map, profile, "documents")
        phase5_bytes = _verify_phase5_source(member_map, profile, "documents")
        freeze_bytes = _verify_freeze_package_source(member_map, "documents")
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
    except Rejected as r:
        return _reject_stage("documents", r.detail)

    # Stage 6: candidate
    try:
        archive, commit_obj = _verify_candidate(
            member_map, "candidate-archive", "candidate-commit-object",
            qualification.preCloseCandidate, qualification.taskId, "candidate",
        )
    except Rejected as r:
        return _reject_stage("candidate", r.detail)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
        # For production profiles, verify the profile signatures now that policy is resolved
        if isinstance(profile, ProductionVerificationProfileV1):
            _verify_production_profile_signatures(profile, policy_obj, "profile")
    except Rejected as r:
        return _reject_stage("policy", r.detail)

    # Stage 8: command
    try:
        for gate in qualification.gates:
            _verify_command_policy(member_map, gate, policy_obj, "command")
    except Rejected as r:
        return _reject_stage("command", r.detail)

    # Stage 9: evidence
    try:
        for gate in qualification.gates:
            _verify_evidence_members(member_map, gate, "evidence")
    except Rejected as r:
        return _reject_stage("evidence", r.detail)

    # Stage 10: dependencies
    try:
        _verify_dependency_members(member_map, qualification.dependencies, "dependencies")
    except Rejected as r:
        return _reject_stage("dependencies", r.detail)

    # Stage 11: reviews
    try:
        # Build signing principal IDs from the authority policy
        if isinstance(policy_obj, _TQO.FixturePolicyV1):
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        else:
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        _verify_review_members(member_map, qualification.independentReviews, bundle.implementationInvocationId, signing_principal_ids, qualification.preCloseCandidate.commit, "reviews")
    except Rejected as r:
        return _reject_stage("reviews", r.detail)

    # Stage 12: controls
    try:
        _verify_gate_test_ids_union(qualification.gates, qualification.taskRow, "controls")
        for gate in qualification.gates:
            _verify_gate_controls(member_map, gate, profile, "controls")
    except Rejected as r:
        return _reject_stage("controls", r.detail)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, qualification.allowedCloseoutPatch, "patch")
    except Rejected as r:
        return _reject_stage("patch", r.detail)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, qualification.signatures, policy_obj, profile,
            _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
            _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
            "signatures",
        )
    except Rejected as r:
        return _reject_stage("signatures", r.detail)

    # Stage 15: projection
    # For qualification, the projection is the qualification digest itself
    try:
        computed_digest = domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, subject_obj)
        if computed_digest != _TQO.TaskQualificationRefV1(
            taskId=qualification.taskId, id=qualification.id, digest=computed_digest
        ).digest:
            _BTO._reject("projection: qualification digest mismatch")
    except Rejected as r:
        return _reject_stage("projection", r.detail)

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
        return Rejected(TASKQUAL_REJECTION, f"stage=unknown {exc}")


def _verify_task_completion(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except Rejected as r:
        return _reject_stage("bounds", r.detail)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except Rejected as r:
        return _reject_stage("bundle", r.detail)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except Rejected as r:
        return _reject_stage("profile", r.detail)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
    except Rejected as r:
        return _reject_stage("members", r.detail)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        receipt = _TQO.parse_completion_receipt(subject_obj, "subject")
    except Rejected as r:
        return _reject_stage("members", f"subject decode: {r.detail}")

    # Stage 5: documents — receipt operations have zero evidence/review/dependency
    # (no document verification needed for receipt)

    # Stage 6: candidate — verify pre-close and closeout archives
    try:
        pre_archive, pre_commit = _verify_candidate(
            member_map, "pre-close-archive", "pre-close-commit-object",
            receipt.preCloseCandidate, receipt.taskId, "candidate.pre-close",
        )
        close_archive, close_commit = _verify_candidate(
            member_map, "closeout-archive", "closeout-commit-object",
            receipt.closeoutCandidate, receipt.taskId, "candidate.closeout",
        )
        # Verify D parent is C
        if len(close_commit.parents) != 1:
            _BTO._reject("candidate.closeout: D must have exactly one parent")
        if close_commit.parents[0] != receipt.preCloseCandidate.commit:
            _BTO._reject("candidate.closeout: D parent must be C")
    except Rejected as r:
        return _reject_stage("candidate", r.detail)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
    except Rejected as r:
        return _reject_stage("policy", r.detail)

    # Stage 8-12: command/evidence/dependencies/reviews/controls — receipt has zero
    # (no gate verification needed for receipt)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, receipt.allowedCloseoutPatch, "patch")
    except Rejected as r:
        return _reject_stage("patch", r.detail)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, receipt.signatures, policy_obj, profile,
            _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
            _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
            "signatures",
        )
    except Rejected as r:
        return _reject_stage("signatures", r.detail)

    # Stage 15: projection — verify closeout file set and diff from archives
    try:
        file_set = _verify_closeout_file_set_from_archives(
            member_map, pre_archive, close_archive,
            receipt.closeoutDiffDigest, "projection",
        )
    except Rejected as r:
        return _reject_stage("projection", r.detail)

    return VerifiedTaskCompletionV1(
        taskId=receipt.taskId,
        preCloseCandidate=receipt.preCloseCandidate,
        closeoutCandidate=receipt.closeoutCandidate,
        qualification=None,  # Receipt doesn't embed qualification object
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
        return Rejected(TASKQUAL_REJECTION, f"stage=unknown {exc}")


def _verify_d0_10_approval(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except Rejected as r:
        return _reject_stage("bounds", r.detail)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except Rejected as r:
        return _reject_stage("bundle", r.detail)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except Rejected as r:
        return _reject_stage("profile", r.detail)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
    except Rejected as r:
        return _reject_stage("members", r.detail)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        approval = _TQO.parse_d0_10_bootstrap_approval(subject_obj, "subject")
    except Rejected as r:
        return _reject_stage("members", f"subject decode: {r.detail}")

    # Stage 5: documents
    try:
        phase4_bytes = _verify_phase4_source(member_map, profile, "documents")
        phase5_bytes = _verify_phase5_source(member_map, profile, "documents")
        # ruling-source
        ruling_bytes, ruling_ref = _resolve_raw_member(member_map, "ruling-source", "documents")
        # §3/§8.2: join the recomputed freeze-package digest to the
        # approval.freezePackage ref. taskId and digest must match.
        freeze_bytes = _verify_freeze_package_source(member_map, "documents")
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
    except Rejected as r:
        return _reject_stage("documents", r.detail)

    # Stage 6: candidate
    try:
        archive, commit_obj = _verify_candidate(
            member_map, "candidate-archive", "candidate-commit-object",
            approval.preCloseCandidate, approval.taskId, "candidate",
        )
    except Rejected as r:
        return _reject_stage("candidate", r.detail)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
    except Rejected as r:
        return _reject_stage("policy", r.detail)

    # Stage 8: command — verify the single bootstrap gate
    try:
        _verify_command_policy(member_map, approval.bootstrapGate, policy_obj, "command")
    except Rejected as r:
        return _reject_stage("command", r.detail)

    # Stage 9: evidence
    try:
        _verify_evidence_members(member_map, approval.bootstrapGate, "evidence")
    except Rejected as r:
        return _reject_stage("evidence", r.detail)

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
        # Verify the archive and commit object members
        _resolve_archive_member(member_map, "d0-07-completion-archive", "dependencies")
        _resolve_git_object_member(member_map, "d0-07-completion-commit-object", "dependencies")
    except Rejected as r:
        return _reject_stage("dependencies", r.detail)

    # Stage 11: reviews
    try:
        # Build signing principal IDs from the authority policy
        if isinstance(policy_obj, _TQO.FixturePolicyV1):
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        else:
            signing_principal_ids = {p.principalId for p in policy_obj.principals}
        _verify_review_members(member_map, approval.independentReviews, bundle.implementationInvocationId, signing_principal_ids, approval.preCloseCandidate.commit, "reviews")
    except Rejected as r:
        return _reject_stage("reviews", r.detail)

    # Stage 12: controls
    try:
        _verify_gate_test_ids_union((approval.bootstrapGate,), approval.taskRow, "controls")
        _verify_gate_controls(member_map, approval.bootstrapGate, profile, "controls")
    except Rejected as r:
        return _reject_stage("controls", r.detail)

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, approval.allowedCloseoutPatch, "patch")
    except Rejected as r:
        return _reject_stage("patch", r.detail)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, approval.signatures, policy_obj, profile,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
            "signatures",
        )
    except Rejected as r:
        return _reject_stage("signatures", r.detail)

    # Stage 15: projection
    try:
        computed_digest = domain_digest(_TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, subject_obj)
        # The approval digest is the full object digest
    except Rejected as r:
        return _reject_stage("projection", r.detail)

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
        return Rejected(TASKQUAL_REJECTION, f"stage=unknown {exc}")


def _verify_d0_10_receipt(content_bundle_bytes, subject_bytes):
    # Stage 1: bounds
    try:
        _check_bounds(content_bundle_bytes, subject_bytes)
    except Rejected as r:
        return _reject_stage("bounds", r.detail)

    # Stage 2: bundle decode
    try:
        bundle = _decode_bundle(content_bundle_bytes)
    except Rejected as r:
        return _reject_stage("bundle", r.detail)

    # Stage 3: profile
    try:
        profile, authority_class, policy_ref = _verify_profile(bundle)
    except Rejected as r:
        return _reject_stage("profile", r.detail)

    # Stage 4: members
    try:
        member_map = _build_member_map(bundle)
        _verify_member_role_set(bundle, member_map, profile, "members")
    except Rejected as r:
        return _reject_stage("members", r.detail)

    # Decode the subject
    try:
        subject_obj = decode_canonical_pf_jcs(subject_bytes)
        receipt = _TQO.parse_d0_10_bootstrap_receipt(subject_obj, "subject")
    except Rejected as r:
        return _reject_stage("members", f"subject decode: {r.detail}")

    # Stage 5: documents — receipt operations have zero evidence/review/dependency

    # Stage 6: candidate — verify pre-close and closeout archives
    try:
        pre_archive, pre_commit = _verify_candidate(
            member_map, "pre-close-archive", "pre-close-commit-object",
            receipt.preCloseCandidate, receipt.taskId, "candidate.pre-close",
        )
        close_archive, close_commit = _verify_candidate(
            member_map, "closeout-archive", "closeout-commit-object",
            receipt.closeoutCandidate, receipt.taskId, "candidate.closeout",
        )
        # Verify D parent is C
        if len(close_commit.parents) != 1:
            _BTO._reject("candidate.closeout: D must have exactly one parent")
        if close_commit.parents[0] != receipt.preCloseCandidate.commit:
            _BTO._reject("candidate.closeout: D parent must be C")
    except Rejected as r:
        return _reject_stage("candidate", r.detail)

    # Stage 7: policy
    try:
        policy_obj, policy_ref = _verify_authority_policy(member_map, profile, policy_ref, "policy")
    except Rejected as r:
        return _reject_stage("policy", r.detail)

    # Stage 8-12: command/evidence/dependencies/reviews/controls — receipt has zero

    # Stage 13: patch
    try:
        patch = _verify_allowed_closeout_patch(member_map, receipt.allowedCloseoutPatch, "patch")
    except Rejected as r:
        return _reject_stage("patch", r.detail)

    # Stage 14: signatures
    try:
        _verify_signatures(
            subject_obj, receipt.signatures, policy_obj, profile,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
            "signatures",
        )
    except Rejected as r:
        return _reject_stage("signatures", r.detail)

    # Stage 15: projection — verify closeout file set and diff from archives
    try:
        file_set = _verify_closeout_file_set_from_archives(
            member_map, pre_archive, close_archive,
            receipt.closeoutDiffDigest, "projection",
        )
    except Rejected as r:
        return _reject_stage("projection", r.detail)

    # Verify the bootstrap-approval member
    try:
        approval_member = member_map.get("bootstrap-approval")
        if approval_member is None:
            _BTO._reject("projection: bootstrap-approval member missing")
        if not isinstance(approval_member, _TQO.TypedContentMemberV1):
            _BTO._reject("projection: bootstrap-approval must be typed-content")
        approval_bytes = bytes.fromhex(approval_member.bytesHex)
        approval_obj = decode_canonical_pf_jcs(approval_bytes)
        approval = _TQO.parse_d0_10_bootstrap_approval(approval_obj, "projection.bootstrap-approval")
        # Verify the approval digest matches
        computed_approval_digest = domain_digest(_TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, approval_obj)
        if computed_approval_digest != receipt.approvalDigest:
            _BTO._reject("projection: approval digest mismatch")
    except Rejected as r:
        return _reject_stage("projection", r.detail)

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