"""SPEC-TASKQUAL-001 closed wire objects, parsers, and fixture policy.

This module is the object authority for TaskQualificationV1, TaskCompletionReceiptV1,
D0_10BootstrapApprovalV1, D0_10BootstrapReceiptV1, and GovernanceBootstrapCompletionV1.
It reuses the PF-JCS canonical encoder, Digest, ContentRef, and Rejected types from
``bootstrap_task_objects`` but defines its own closed object schemas per
SPEC-TASKQUAL-001. It does not import object defaults or verifier behavior from
ADR-0018 or SPEC-EVFINAL-001.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from typing import NoReturn, Tuple

# Reuse the canonical PF-JCS + Digest + ContentRef + Rejected from bootstrap_task_objects.
import bootstrap_task_objects as _BTO

canonical_pf_jcs = _BTO.canonical_pf_jcs
decode_canonical_pf_jcs = _BTO.decode_canonical_pf_jcs
Rejected = _BTO.Rejected
_reject = _BTO._reject
Digest = _BTO.Digest
ContentRef = _BTO.ContentRef
CandidateIdentity = _BTO.CandidateIdentity
ApprovalRuleV1 = _BTO.ApprovalRuleV1

PROFILE_ID_RE = _BTO.PROFILE_ID_RE
SAFE_ID_RE = _BTO.SAFE_ID_RE
TASK_ID_RE = _BTO.TASK_ID_RE
TEST_ID_RE = _BTO.TEST_ID_RE
EVIDENCE_ID_RE = _BTO.EVIDENCE_ID_RE
SEMVER_RE = _BTO.SEMVER_RE
DIGEST_RE = _BTO.DIGEST_RE
GIT_OBJECT_RE = _BTO.GIT_OBJECT_RE

# SPEC-TASKQUAL-001 §1: Git commit/tree are 40 lowercase hex (SHA-1 only).
# The bootstrap GIT_OBJECT_RE accepts both 40 and 64 hex, but this protocol
# only uses SHA-1 Git objects per §8.3.
GIT_SHA1_RE = re.compile(r"[0-9a-f]{40}")

# SPEC-TASKQUAL-001 §3: frozenAt is a real YYYY-MM-DD date.
_YYYY_MM_DD_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

# GAP-15: §6/§8.2 issuedAt and verificationInstant are RFC3339 UTC seconds.
# Strict RFC3339 with 'Z' suffix (UTC only, no offsets).
_RFC3339_UTC_RE = re.compile(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z")


def _require_rfc3339_utc(value, where: str) -> str:
    """GAP-15: validate a string is RFC3339 UTC (Z suffix, no offset)."""
    s = _require_string(value, where, 64)
    if not _RFC3339_UTC_RE.fullmatch(s):
        _reject(f"{where}: must be RFC3339 UTC (YYYY-MM-DDThh:mm:ss[.ssssss]Z)")
    return s

TASKQUAL_REJECTION = "PF-TASK-QUALIFICATION-UNVERIFIED"

# ---------------------------------------------------------------------------
# §2 shared value objects
# ---------------------------------------------------------------------------

MAX_STRING_BYTES = 4096
MAX_ARGV_BYTES = 65536
MAX_ARRAY = 4096
MAX_ROOT_CANONICAL = 4 * 1024 * 1024
MAX_REVIEW_REPORT = 1_048_576
MAX_REVIEWS = 256
MAX_REVIEW_INVOCATIONS = 256
MAX_CLOSEOUT_PATHS = 16
MAX_GATES = 256
MAX_ENV = 256
MAX_ARGV_COUNT = 256
MAX_DEPENDENCIES = 256
MAX_EVIDENCE = 256
MAX_SCOPE_ITEMS = 12
MAX_DONE_WHEN = 32
MAX_DAYS = 365
MAX_COMMITS = 10000


def _require_ascii_text(value, pattern, where, limit=127):
    return _BTO._require_ascii_text(value, pattern, where, limit)


def _require_semver(value, where):
    return _BTO._require_semver(value, where)


def _require_digest(value, where):
    if not isinstance(value, str) or not DIGEST_RE.fullmatch(value):
        _reject(f"{where}: digest must be sha256:<64 lowercase hex>")
    return Digest(algorithm="sha256", bytes=bytes.fromhex(value[7:]))


def _require_git_object(value, where):
    if not isinstance(value, str) or not GIT_SHA1_RE.fullmatch(value):
        _reject(f"{where}: git object id must be 40 lowercase hex (SHA-1)")
    return value


def _require_string(value, where, limit=MAX_STRING_BYTES):
    if not isinstance(value, str):
        _reject(f"{where}: must be string")
    if "\x00" in value:
        _reject(f"{where}: NUL forbidden")
    encoded = value.encode("utf-8")
    if len(encoded) > limit:
        _reject(f"{where}: exceeds {limit} UTF-8 bytes")
    for ch in value:
        code = ord(ch)
        if code <= 0x1F or 0x7F <= code <= 0x9F:
            _reject(f"{where}: Cc forbidden")
    return value


def _require_safe_id(value, where):
    if not isinstance(value, str) or not SAFE_ID_RE.fullmatch(value):
        _reject(f"{where}: safe-id required")
    return _require_string(value, where, 256)


def _require_task_id(value, where):
    if not isinstance(value, str) or not TASK_ID_RE.fullmatch(value):
        _reject(f"{where}: TASK-* id required")
    return value


def _require_test_id(value, where):
    if not isinstance(value, str) or not TEST_ID_RE.fullmatch(value):
        _reject(f"{where}: TST-* id required")
    return value


def _require_evidence_id(value, where):
    if not isinstance(value, str) or not EVIDENCE_ID_RE.fullmatch(value):
        _reject(f"{where}: EV-YYYYMMDD-NNNN required")
    return value


def _require_array(value, where, limit=MAX_ARRAY):
    if not isinstance(value, list):
        _reject(f"{where}: must be array")
    if len(value) > limit:
        _reject(f"{where}: exceeds {limit} entries")
    return value


def _require_unique_sorted(items, key_fn, where):
    keys = [key_fn(item) for item in items]
    if keys != sorted(keys):
        _reject(f"{where}: must be ASCII ascending sorted")
    if len(set(keys)) != len(keys):
        _reject(f"{where}: duplicates forbidden")
    return items


@dataclass(frozen=True)
class NormativeDocumentRefV1:
    id: str
    status: str  # "accepted"
    contentDigest: Digest
    reviewCommit: str


@dataclass(frozen=True)
class RawDocumentRefV1:
    path: str
    digest: Digest


@dataclass(frozen=True)
class EvidenceRefV1:
    id: str
    digest: Digest


@dataclass(frozen=True)
class ApprovalSignatureV1:
    keyId: str
    algorithm: str  # "ed25519"
    signature: bytes


@dataclass(frozen=True)
class IndependentReviewRefV1:
    reviewerId: str
    reviewerKind: str  # "human" | "independent-ai"
    invocationId: str
    reportDigest: Digest
    reviewCommit: str
    reviewLink: str
    decision: str  # "approved"
    findings: Tuple  # ()


@dataclass(frozen=True)
class VerifierIdentityV1:
    id: str
    executable: ContentRef
    closure: ContentRef
    sourceDigest: Digest
    buildPolicy: ContentRef


# Digest domains (§1-§8)
DOMAIN_CANDIDATE = b"pf.taskqual.candidate.v1"
DOMAIN_REVIEW_REPORT = b"pf.taskqual.review-report.v1"
DOMAIN_VERIFIER_IDENTITY = b"pf.taskqual.verifier-identity.v1"
DOMAIN_TASK_FREEZE_PACKAGE_SOURCE = b"pf.task-freeze-package-source.v1"
DOMAIN_TASK_COMMAND_POLICY = b"pf.task-command-policy.v1"
DOMAIN_TASK_QUALIFICATION_STATEMENT = b"pf.task-qualification-statement.v1"
DOMAIN_TASK_QUALIFICATION_SIGNATURE = b"pf.task-qualification-signature.v1"
DOMAIN_TASK_QUALIFICATION = b"pf.task-qualification.v1"
DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT = b"pf.task-completion-receipt-statement.v1"
DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE = b"pf.task-completion-receipt-signature.v1"
DOMAIN_TASK_COMPLETION_RECEIPT = b"pf.task-completion-receipt.v1"
DOMAIN_CLOSEOUT_FILE_SET = b"pf.closeout-file-set.v1"
DOMAIN_SEMANTIC_CLOSEOUT_FILE_SET = b"pf.semantic-closeout-file-set.v1"
DOMAIN_ALLOWED_CLOSEOUT_PATCH = b"pf.allowed-closeout-patch.v1"
DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT = b"pf.governance-bootstrap-completion-statement.v1"
DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE = b"pf.governance-bootstrap-completion-signature.v1"
DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION = b"pf.governance-bootstrap-completion.v1"
DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT = b"pf.d0-10-bootstrap-approval-statement.v1"
DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE = b"pf.d0-10-bootstrap-approval-signature.v1"
DOMAIN_D0_10_BOOTSTRAP_APPROVAL = b"pf.d0-10-bootstrap-approval.v1"
DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT = b"pf.d0-10-bootstrap-receipt-statement.v1"
DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE = b"pf.d0-10-bootstrap-receipt-signature.v1"
DOMAIN_D0_10_BOOTSTRAP_RECEIPT = b"pf.d0-10-bootstrap-receipt.v1"
DOMAIN_FIXTURE_POLICY = b"pf.taskqual.fixture-policy.v1"
DOMAIN_FIXTURE_RESOLVED_BLOB = b"pf.taskqual.fixture-resolved-blob.v1"
DOMAIN_PRODUCTION_PROFILE_STATEMENT = b"pf.taskqual.production-profile-statement.v1"
DOMAIN_PRODUCTION_PROFILE_SIGNATURE = b"pf.taskqual.production-profile-signature.v1"
DOMAIN_PRODUCTION_PROFILE = b"pf.taskqual.production-profile.v1"
DOMAIN_PRODUCTION_PROFILE_PIN_STATEMENT = b"pf.taskqual.production-profile-pin-statement.v1"
DOMAIN_PRODUCTION_PROFILE_PIN_SIGNATURE = b"pf.taskqual.production-profile-pin-signature.v1"
DOMAIN_PRODUCTION_PROFILE_PIN = b"pf.taskqual.production-profile-pin.v1"
DOMAIN_PURE_PROJECTION = b"pf.taskqual.pure-projection.v1"
DOMAIN_PROTECTED_ACCEPTANCE_STATEMENT = b"pf.taskqual.protected-acceptance-statement.v1"
DOMAIN_PROTECTED_ACCEPTANCE_SIGNATURE = b"pf.taskqual.protected-acceptance-signature.v1"
DOMAIN_PROTECTED_ACCEPTANCE = b"pf.taskqual.protected-acceptance.v1"
DOMAIN_DEPENDENCY_OBJECT = b"pf.taskqual.dependency-object.v1"


def domain_digest(domain: bytes, value) -> Digest:
    """SHA-256(ASCII(domain) || NUL || PF-JCS(value))."""
    canonical = canonical_pf_jcs(value)
    h = hashlib.sha256()
    h.update(domain)
    h.update(b"\x00")
    h.update(canonical)
    return Digest(algorithm="sha256", bytes=h.digest())


def domain_digest_raw(domain: bytes, raw: bytes) -> Digest:
    """SHA-256(ASCII(domain) || NUL || raw bytes).

    Used for raw-source carriers like freeze-package-source, evidence,
    review-report, and dependency objects where the digest is over raw bytes
    rather than PF-JCS.
    """
    h = hashlib.sha256()
    h.update(domain)
    h.update(b"\x00")
    h.update(raw)
    return Digest(algorithm="sha256", bytes=h.digest())


def plain_sha256_digest(raw: bytes) -> Digest:
    return Digest(algorithm="sha256", bytes=hashlib.sha256(raw).digest())


def digest_to_wire(d: Digest) -> str:
    return f"sha256:{d.bytes.hex()}"


def content_ref_to_wire(ref: ContentRef) -> dict:
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": digest_to_wire(ref.digest),
    }


def digest_to_wire_or_none(d) -> str | None:
    if d is None:
        return None
    return digest_to_wire(d)


# ---------------------------------------------------------------------------
# §2 parsers
# ---------------------------------------------------------------------------

def parse_candidate_identity(obj: dict, where: str) -> CandidateIdentity:
    if not isinstance(obj, dict):
        _reject(f"{where}: candidate must be object")
    commit = _require_git_object(obj.get("commit"), f"{where}.commit")
    tree = _require_git_object(obj.get("treeObjectId"), f"{where}.treeObjectId")
    archive = _require_digest(obj.get("archiveSha256"), f"{where}.archiveSha256")
    # candidate digest domain
    wire = {
        "commit": commit,
        "treeObjectId": tree,
        "archiveSha256": digest_to_wire(archive),
    }
    digest = domain_digest(DOMAIN_CANDIDATE, wire)
    return CandidateIdentity(
        commit=commit,
        treeObjectId=tree,
        archiveDigest=archive,
        digest=digest,
    )


def _require_content_ref_id(value, where):
    """ContentRef.id accepts lowercase profile IDs or uppercase document IDs."""
    if not isinstance(value, str):
        _reject(f"{where}: must be string")
    if len(value) > 127:
        _reject(f"{where}: exceeds 127 bytes")
    # Try lowercase profile ID first
    if PROFILE_ID_RE.fullmatch(value):
        return value
    # Try uppercase document ID (ADR-*, SPEC-*, GOV-*, etc.)
    if re.fullmatch(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*", value):
        return value
    _reject(f"{where}: must be lowercase profile ID or uppercase document ID")


def parse_content_ref(obj: dict, where: str) -> ContentRef:
    if not isinstance(obj, dict):
        _reject(f"{where}: content ref must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    cid = _require_content_ref_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return ContentRef(schema=schema, id=cid, version=version, digest=digest)


def parse_normative_document_ref(obj: dict, where: str) -> NormativeDocumentRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: normative doc ref must be object")
    # Document IDs can be ADR-*, SPEC-*, GOV-* etc. — uppercase + digits + hyphens
    doc_id = obj.get("id")
    if not isinstance(doc_id, str) or not re.fullmatch(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*", doc_id):
        _reject(f"{where}.id: must be uppercase document ID format (e.g. ADR-0020, SPEC-TASKQUAL-001)")
    if len(doc_id) > 127:
        _reject(f"{where}.id: exceeds 127 bytes")
    status = obj.get("status")
    if status != "accepted":
        _reject(f"{where}.status: must be 'accepted'")
    content_digest = _require_digest(obj.get("contentDigest"), f"{where}.contentDigest")
    review_commit = _require_git_object(obj.get("reviewCommit"), f"{where}.reviewCommit")
    return NormativeDocumentRefV1(
        id=doc_id, status=status, contentDigest=content_digest, reviewCommit=review_commit
    )


def parse_raw_document_ref(obj: dict, where: str) -> RawDocumentRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: raw doc ref must be object")
    path = _require_string(obj.get("path"), f"{where}.path", 4096)
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return RawDocumentRefV1(path=path, digest=digest)


def parse_evidence_ref(obj: dict, where: str) -> EvidenceRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: evidence ref must be object")
    eid = _require_evidence_id(obj.get("id"), f"{where}.id")
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return EvidenceRefV1(id=eid, digest=digest)


def parse_approval_signature(obj: dict, where: str) -> ApprovalSignatureV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: signature must be object")
    key_id = _require_safe_id(obj.get("keyId"), f"{where}.keyId")
    algorithm = obj.get("algorithm")
    if algorithm != "ed25519":
        _reject(f"{where}.algorithm: must be 'ed25519'")
    sig_hex = obj.get("signature")
    if not isinstance(sig_hex, str) or not re.fullmatch(r"[0-9a-f]{128}", sig_hex):
        _reject(f"{where}.signature: must be 128 lowercase hex (64-byte Ed25519)")
    return ApprovalSignatureV1(
        keyId=key_id, algorithm=algorithm, signature=bytes.fromhex(sig_hex)
    )


def parse_independent_review_ref(obj: dict, where: str) -> IndependentReviewRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: review ref must be object")
    reviewer_id = _require_safe_id(obj.get("reviewerId"), f"{where}.reviewerId")
    kind = obj.get("reviewerKind")
    if kind not in ("human", "independent-ai"):
        _reject(f"{where}.reviewerKind: must be 'human' or 'independent-ai'")
    invocation_id = _require_safe_id(obj.get("invocationId"), f"{where}.invocationId")
    report_digest = _require_digest(obj.get("reportDigest"), f"{where}.reportDigest")
    review_commit = _require_git_object(obj.get("reviewCommit"), f"{where}.reviewCommit")
    review_link = obj.get("reviewLink")
    if not isinstance(review_link, str) or not review_link.startswith("https://"):
        _reject(f"{where}.reviewLink: must be https://")
    decision = obj.get("decision")
    if decision != "approved":
        _reject(f"{where}.decision: must be 'approved'")
    findings = obj.get("findings")
    if not isinstance(findings, list) or len(findings) != 0:
        _reject(f"{where}.findings: must be empty array")
    return IndependentReviewRefV1(
        reviewerId=reviewer_id,
        reviewerKind=kind,
        invocationId=invocation_id,
        reportDigest=report_digest,
        reviewCommit=review_commit,
        reviewLink=review_link,
        decision=decision,
        findings=tuple(),
    )


def parse_verifier_identity(obj: dict, where: str) -> VerifierIdentityV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: verifier identity must be object")
    vid = _require_safe_id(obj.get("id"), f"{where}.id")
    executable = parse_content_ref(obj.get("executable"), f"{where}.executable")
    closure = parse_content_ref(obj.get("closure"), f"{where}.closure")
    source_digest = _require_digest(obj.get("sourceDigest"), f"{where}.sourceDigest")
    build_policy = parse_content_ref(obj.get("buildPolicy"), f"{where}.buildPolicy")
    return VerifierIdentityV1(
        id=vid,
        executable=executable,
        closure=closure,
        sourceDigest=source_digest,
        buildPolicy=build_policy,
    )


# ---------------------------------------------------------------------------
# §3 Task row, freeze, command gate
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TaskQualificationTaskRowV1:
    taskId: str
    output: str
    dependencies: Tuple[str, ...]
    prerequisites: Tuple[str, ...]
    tests: Tuple[str, ...]
    evidenceIds: Tuple[str, ...]
    status: str  # "in_progress"


@dataclass(frozen=True)
class TaskFreezePackageRefV1:
    taskId: str
    digest: Digest


@dataclass(frozen=True)
class TaskCommandPolicyV1:
    schema: str
    id: str
    version: str
    taskId: str
    testIds: Tuple[str, ...]
    argv: Tuple[str, ...]
    environment: Tuple  # tuple of (name, value) pairs
    tool: ContentRef
    probe: ContentRef
    sandboxPolicy: ContentRef
    verifier: VerifierIdentityV1


@dataclass(frozen=True)
class TaskQualificationGateV1:
    gateId: str
    taskId: str
    testIds: Tuple[str, ...]
    evidence: Tuple[EvidenceRefV1, ...]
    commandPolicy: ContentRef
    eligibleStage0Handoff: ContentRef
    sessionContainment: ContentRef
    freshness: ContentRef
    privateScan: ContentRef
    revocationSnapshot: ContentRef


def _parse_id_list(value, where, id_validator, limit=MAX_ARRAY):
    arr = _require_array(value, where, limit)
    out = []
    for item in arr:
        out.append(id_validator(item, where))
    return tuple(out)


def parse_task_row(obj: dict, where: str) -> TaskQualificationTaskRowV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: task row must be object")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    output = _require_string(obj.get("output"), f"{where}.output", MAX_STRING_BYTES)
    deps = _parse_id_list(obj.get("dependencies"), f"{where}.dependencies", _require_task_id)
    prereqs = _require_array(obj.get("prerequisites"), f"{where}.prerequisites")
    prereq_out = []
    for p in prereqs:
        if not isinstance(p, str) or "@" not in p:
            _reject(f"{where}.prerequisites: must be '<doc-id>@accepted'")
        doc_id, _, status = p.partition("@")
        if status != "accepted":
            _reject(f"{where}.prerequisites: must be '@accepted'")
        # Document IDs can be ADR-*, SPEC-*, GOV-* etc. — uppercase + digits + hyphens
        if not re.fullmatch(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*", doc_id):
            _reject(f"{where}.prerequisites: doc-id must be uppercase ID format")
        if len(doc_id) > 127:
            _reject(f"{where}.prerequisites: doc-id exceeds 127 bytes")
        prereq_out.append(p)
    tests = _parse_id_list(obj.get("tests"), f"{where}.tests", _require_test_id)
    if len(tests) == 0:
        _reject(f"{where}.tests: must be nonempty")
    ev_ids = _parse_id_list(obj.get("evidenceIds"), f"{where}.evidenceIds", _require_evidence_id)
    status = obj.get("status")
    if status != "in_progress":
        _reject(f"{where}.status: must be 'in_progress'")
    return TaskQualificationTaskRowV1(
        taskId=task_id,
        output=output,
        dependencies=deps,
        prerequisites=tuple(prereq_out),
        tests=tests,
        evidenceIds=ev_ids,
        status=status,
    )


def parse_freeze_package_ref(obj: dict, where: str) -> TaskFreezePackageRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: freeze ref must be object")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return TaskFreezePackageRefV1(taskId=task_id, digest=digest)


@dataclass(frozen=True)
class TaskFreezePackageV1:
    taskId: str
    freezeCommit: str
    output: str
    dependencies: Tuple[str, ...]
    prerequisites: Tuple[str, ...]
    tests: Tuple[str, ...]
    inScope: Tuple[str, ...]
    outOfScope: Tuple[str, ...]
    doneWhen: Tuple[str, ...]
    overflowPolicy: str
    maxCalendarDays: int
    maxCommits: int
    notes: str
    frozenAt: str


def parse_freeze_package(obj: dict, where: str) -> TaskFreezePackageV1:
    """Parse the raw freeze package source (§3 TaskFreezePackageV1) and
    extract the fields the verifier needs for ancestry graph construction
    and row-equality verification (GAP-3) plus freeze field bounds (GAP-5).
    """
    if not isinstance(obj, dict):
        _reject(f"{where}: freeze package must be object")
    schema_version = obj.get("schemaVersion")
    if schema_version != 1:
        _reject(f"{where}.schemaVersion: must be 1")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    freeze_commit = _require_git_object(obj.get("freezeCommit"), f"{where}.freezeCommit")
    # GAP-5: frozenAt must be a real YYYY-MM-DD date (§3).
    frozen_at = _require_string(obj.get("frozenAt"), f"{where}.frozenAt", 10)
    if not _YYYY_MM_DD_RE.fullmatch(frozen_at):
        _reject(f"{where}.frozenAt: must be YYYY-MM-DD")
    output = _require_string(obj.get("output"), f"{where}.output")
    deps_arr = obj.get("dependencies")
    if not isinstance(deps_arr, list):
        _reject(f"{where}.dependencies: must be array")
    if len(deps_arr) > MAX_DEPENDENCIES:
        _reject(f"{where}.dependencies: exceeds {MAX_DEPENDENCIES}")
    deps = tuple(_require_task_id(d, f"{where}.dependencies") for d in deps_arr)
    prereqs_arr = obj.get("prerequisites")
    if not isinstance(prereqs_arr, list):
        _reject(f"{where}.prerequisites: must be array")
    if len(prereqs_arr) > MAX_ARRAY:
        _reject(f"{where}.prerequisites: exceeds {MAX_ARRAY}")
    prereqs = tuple(_require_string(p, f"{where}.prerequisites") for p in prereqs_arr)
    tests_arr = obj.get("tests")
    if not isinstance(tests_arr, list):
        _reject(f"{where}.tests: must be array")
    # GAP-5: tests nonempty (§3 "tests 非空").
    if len(tests_arr) == 0:
        _reject(f"{where}.tests: must be nonempty")
    if len(tests_arr) > MAX_ARRAY:
        _reject(f"{where}.tests: exceeds {MAX_ARRAY}")
    tests = tuple(_require_test_id(t, f"{where}.tests") for t in tests_arr)
    # GAP-5: in/out scope each 3..12, doneWhen 1..32 (§3).
    in_scope_arr = obj.get("inScope")
    if not isinstance(in_scope_arr, list):
        _reject(f"{where}.inScope: must be array")
    if not (3 <= len(in_scope_arr) <= MAX_SCOPE_ITEMS):
        _reject(f"{where}.inScope: must be 3..{MAX_SCOPE_ITEMS}")
    in_scope = tuple(_require_string(s, f"{where}.inScope") for s in in_scope_arr)
    out_scope_arr = obj.get("outOfScope")
    if not isinstance(out_scope_arr, list):
        _reject(f"{where}.outOfScope: must be array")
    if not (3 <= len(out_scope_arr) <= MAX_SCOPE_ITEMS):
        _reject(f"{where}.outOfScope: must be 3..{MAX_SCOPE_ITEMS}")
    out_scope = tuple(_require_string(s, f"{where}.outOfScope") for s in out_scope_arr)
    done_when_arr = obj.get("doneWhen")
    if not isinstance(done_when_arr, list):
        _reject(f"{where}.doneWhen: must be array")
    if not (1 <= len(done_when_arr) <= MAX_DONE_WHEN):
        _reject(f"{where}.doneWhen: must be 1..{MAX_DONE_WHEN}")
    done_when = tuple(_require_string(s, f"{where}.doneWhen") for s in done_when_arr)
    # GAP-5: overflowPolicy safe string (§3).
    overflow_policy = _require_string(obj.get("overflowPolicy"), f"{where}.overflowPolicy", 256)
    # GAP-5: maxCalendarDays 1..365, maxCommits 1..10000 safe int (§3).
    max_days = obj.get("maxCalendarDays")
    if not isinstance(max_days, int) or isinstance(max_days, bool):
        _reject(f"{where}.maxCalendarDays: must be integer")
    if not (1 <= max_days <= MAX_DAYS):
        _reject(f"{where}.maxCalendarDays: must be 1..{MAX_DAYS}")
    max_commits = obj.get("maxCommits")
    if not isinstance(max_commits, int) or isinstance(max_commits, bool):
        _reject(f"{where}.maxCommits: must be integer")
    if not (1 <= max_commits <= MAX_COMMITS):
        _reject(f"{where}.maxCommits: must be 1..{MAX_COMMITS}")
    notes = _require_string(obj.get("notes"), f"{where}.notes")
    return TaskFreezePackageV1(
        taskId=task_id, freezeCommit=freeze_commit, output=output,
        dependencies=deps, prerequisites=prereqs, tests=tests,
        inScope=in_scope, outOfScope=out_scope, doneWhen=done_when,
        overflowPolicy=overflow_policy, maxCalendarDays=max_days,
        maxCommits=max_commits, notes=notes, frozenAt=frozen_at)


def parse_command_policy(obj: dict, where: str) -> TaskCommandPolicyV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: command policy must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.task-command-policy.v1":
        _reject(f"{where}.schema: must be proof-forge.task-command-policy.v1")
    cid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    test_ids = _parse_id_list(obj.get("testIds"), f"{where}.testIds", _require_test_id)
    argv = _require_array(obj.get("argv"), f"{where}.argv", MAX_ARGV_COUNT)
    if len(argv) < 1:
        _reject(f"{where}.argv: must be nonempty")
    argv_out = []
    for a in argv:
        argv_out.append(_require_string(a, f"{where}.argv", MAX_ARGV_BYTES))
    # GAP-6: §3 argv[0] is absolute canonical executable (starts with '/').
    if not argv_out[0].startswith("/"):
        _reject(f"{where}.argv[0]: must be absolute path (start with '/')")
    env_arr = _require_array(obj.get("environment"), f"{where}.environment", MAX_ENV)
    env_pairs = []
    for entry in env_arr:
        if not isinstance(entry, dict):
            _reject(f"{where}.environment: entry must be object")
        name = obj_env_name(entry.get("name"), f"{where}.environment.name")
        value = _require_string(entry.get("value"), f"{where}.environment.value", MAX_ARGV_BYTES)
        env_pairs.append((name, value))
    # environment must be sorted by name ascending
    names = [p[0] for p in env_pairs]
    if names != sorted(names):
        _reject(f"{where}.environment: must be sorted by name ascending")
    if len(set(names)) != len(names):
        _reject(f"{where}.environment: duplicate names forbidden")
    tool = parse_content_ref(obj.get("tool"), f"{where}.tool")
    probe = parse_content_ref(obj.get("probe"), f"{where}.probe")
    sandbox = parse_content_ref(obj.get("sandboxPolicy"), f"{where}.sandboxPolicy")
    verifier = parse_verifier_identity(obj.get("verifier"), f"{where}.verifier")
    return TaskCommandPolicyV1(
        schema=schema,
        id=cid,
        version=version,
        taskId=task_id,
        testIds=test_ids,
        argv=tuple(argv_out),
        environment=tuple(env_pairs),
        tool=tool,
        probe=probe,
        sandboxPolicy=sandbox,
        verifier=verifier,
    )


def _obj_env_name(value, where):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,254}", value):
        _reject(f"{where}: must match [A-Za-z_][A-Za-z0-9_]{{0,254}}")
    return value


def parse_gate(obj: dict, where: str) -> TaskQualificationGateV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: gate must be object")
    gate_id = _require_safe_id(obj.get("gateId"), f"{where}.gateId")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    test_ids = _parse_id_list(obj.get("testIds"), f"{where}.testIds", _require_test_id)
    ev_arr = _require_array(obj.get("evidence"), f"{where}.evidence", MAX_EVIDENCE)
    ev_refs = tuple(parse_evidence_ref(e, f"{where}.evidence") for e in ev_arr)
    cmd = parse_content_ref(obj.get("commandPolicy"), f"{where}.commandPolicy")
    handoff = parse_content_ref(obj.get("eligibleStage0Handoff"), f"{where}.eligibleStage0Handoff")
    containment = parse_content_ref(obj.get("sessionContainment"), f"{where}.sessionContainment")
    freshness = parse_content_ref(obj.get("freshness"), f"{where}.freshness")
    scan = parse_content_ref(obj.get("privateScan"), f"{where}.privateScan")
    revocation = parse_content_ref(obj.get("revocationSnapshot"), f"{where}.revocationSnapshot")
    return TaskQualificationGateV1(
        gateId=gate_id,
        taskId=task_id,
        testIds=test_ids,
        evidence=ev_refs,
        commandPolicy=cmd,
        eligibleStage0Handoff=handoff,
        sessionContainment=containment,
        freshness=freshness,
        privateScan=scan,
        revocationSnapshot=revocation,
    )


# ---------------------------------------------------------------------------
# §4 Dependency completion (closed discriminated union)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BootstrapTaskReceiptDependencyV1:
    kind: str  # "bootstrap-task-receipt"
    taskId: str
    completionCommit: str
    authorityPolicy: ContentRef
    objectDigest: Digest
    objectBytesHex: str
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class GovernanceBootstrapReceiptDependencyV1:
    kind: str  # "governance-bootstrap-receipt"
    taskId: str
    ruling: ContentRef
    completionCommit: str
    authorityPolicy: ContentRef
    objectDigest: Digest
    objectBytesHex: str
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class TaskQualificationDependencyV1:
    kind: str  # "task-qualification"
    taskId: str
    completionCommit: str
    authorityPolicy: ContentRef
    receipt: "TaskCompletionReceiptRefV1"
    objectDigest: Digest
    objectBytesHex: str
    signatures: Tuple[ApprovalSignatureV1, ...]


DependencyCompletionRefV1 = (
    BootstrapTaskReceiptDependencyV1
    | GovernanceBootstrapReceiptDependencyV1
    | TaskQualificationDependencyV1
)


def _parse_dependency_signatures(obj, where):
    arr = _require_array(obj.get("signatures"), f"{where}.signatures", MAX_ARRAY)
    sigs = tuple(parse_approval_signature(s, f"{where}.signatures") for s in arr)
    _require_unique_sorted(sigs, lambda s: s.keyId, f"{where}.signatures")
    return sigs


def _parse_object_bytes_hex(value, where):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]+", value) or len(value) % 2 != 0:
        _reject(f"{where}: objectBytesHex must be nonempty lowercase even hex")
    if len(value) < 2:
        _reject(f"{where}: objectBytesHex must be nonempty")
    return value


def parse_dependency(obj: dict, where: str) -> DependencyCompletionRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: dependency must be object")
    kind = obj.get("kind")
    if kind == "bootstrap-task-receipt":
        task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
        if task_id not in _BTO._BOOTSTRAP_TASK_IDS:
            _reject(f"{where}.taskId: bootstrap-task-receipt only allows D0-01..06")
        commit = _require_git_object(obj.get("completionCommit"), f"{where}.completionCommit")
        policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
        obj_digest = _require_digest(obj.get("objectDigest"), f"{where}.objectDigest")
        obj_hex = _parse_object_bytes_hex(obj.get("objectBytesHex"), f"{where}.objectBytesHex")
        sigs = _parse_dependency_signatures(obj, where)
        return BootstrapTaskReceiptDependencyV1(
            kind=kind, taskId=task_id, completionCommit=commit,
            authorityPolicy=policy, objectDigest=obj_digest,
            objectBytesHex=obj_hex, signatures=sigs,
        )
    if kind == "governance-bootstrap-receipt":
        task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
        ruling = parse_content_ref(obj.get("ruling"), f"{where}.ruling")
        commit = _require_git_object(obj.get("completionCommit"), f"{where}.completionCommit")
        policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
        obj_digest = _require_digest(obj.get("objectDigest"), f"{where}.objectDigest")
        obj_hex = _parse_object_bytes_hex(obj.get("objectBytesHex"), f"{where}.objectBytesHex")
        sigs = _parse_dependency_signatures(obj, where)
        return GovernanceBootstrapReceiptDependencyV1(
            kind=kind, taskId=task_id, ruling=ruling, completionCommit=commit,
            authorityPolicy=policy, objectDigest=obj_digest,
            objectBytesHex=obj_hex, signatures=sigs,
        )
    if kind == "task-qualification":
        task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
        commit = _require_git_object(obj.get("completionCommit"), f"{where}.completionCommit")
        policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
        receipt = parse_completion_receipt_ref(obj.get("receipt"), f"{where}.receipt")
        obj_digest = _require_digest(obj.get("objectDigest"), f"{where}.objectDigest")
        obj_hex = _parse_object_bytes_hex(obj.get("objectBytesHex"), f"{where}.objectBytesHex")
        sigs = _parse_dependency_signatures(obj, where)
        return TaskQualificationDependencyV1(
            kind=kind, taskId=task_id, completionCommit=commit,
            authorityPolicy=policy, receipt=receipt,
            objectDigest=obj_digest, objectBytesHex=obj_hex, signatures=sigs,
        )
    _reject(f"{where}.kind: unknown dependency kind '{kind}'")


# ---------------------------------------------------------------------------
# §5 Qualification, AllowedCloseoutPatch, SemanticCloseoutFileSet
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class AllowedCloseoutPatchV1:
    schema: str
    id: str
    version: str
    taskId: str
    preCloseCandidate: CandidateIdentity
    allowedPaths: Tuple[str, ...]
    semanticFileSetDigest: Digest
    resultingTaskRowDigest: Digest


@dataclass(frozen=True)
class SemanticCloseoutFileSetV1:
    schema: str
    id: str
    version: str
    taskId: str
    preCloseCandidate: CandidateIdentity
    changes: Tuple  # tuple of (path, beforeDigest|None, afterDigest|None)


@dataclass(frozen=True)
class TaskQualificationRefV1:
    taskId: str
    id: str
    digest: Digest


@dataclass(frozen=True)
class TaskQualificationV1:
    schema: str
    id: str
    version: str
    taskId: str
    preCloseCandidate: CandidateIdentity
    taskRow: TaskQualificationTaskRowV1
    freezePackage: TaskFreezePackageRefV1
    gates: Tuple[TaskQualificationGateV1, ...]
    dependencies: Tuple[DependencyCompletionRefV1, ...]
    verifier: VerifierIdentityV1
    authorityPolicy: ContentRef
    allowedCloseoutPatch: ContentRef
    independentReviews: Tuple[IndependentReviewRefV1, ...]
    signatures: Tuple[ApprovalSignatureV1, ...]


def parse_completion_receipt_ref(obj: dict, where: str) -> "TaskCompletionReceiptRefV1":
    if not isinstance(obj, dict):
        _reject(f"{where}: receipt ref must be object")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    rid = _require_safe_id(obj.get("id"), f"{where}.id")
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return TaskCompletionReceiptRefV1(taskId=task_id, id=rid, digest=digest)


def _parse_closeout_changes(arr, where):
    out = []
    for entry in arr:
        if not isinstance(entry, dict):
            _reject(f"{where}: change must be object")
        path = _require_string(entry.get("path"), f"{where}.path", 4096)
        before = entry.get("beforeDigest")
        after = entry.get("afterDigest")
        if before is None and after is None:
            _reject(f"{where}: before/after both null")
        if before is not None and after is not None:
            bd = _require_digest(before, f"{where}.beforeDigest")
            ad = _require_digest(after, f"{where}.afterDigest")
            if bd.bytes == ad.bytes:
                _reject(f"{where}: before==after")
        if before is not None:
            before = _require_digest(before, f"{where}.beforeDigest")
        if after is not None:
            after = _require_digest(after, f"{where}.afterDigest")
        out.append((path, before, after))
    # sort by path UTF-8 ascending
    out.sort(key=lambda c: c[0].encode("utf-8"))
    # check sorted + unique
    paths = [c[0] for c in out]
    if paths != sorted(paths):
        _reject(f"{where}: must be sorted by path UTF-8 ascending")
    if len(set(paths)) != len(paths):
        _reject(f"{where}: duplicate paths forbidden")
    return tuple(out)


def parse_allowed_closeout_patch(obj: dict, where: str) -> AllowedCloseoutPatchV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: allowed patch must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.allowed-closeout-patch.v1":
        _reject(f"{where}.schema: must be proof-forge.allowed-closeout-patch.v1")
    cid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    candidate = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    paths = _require_array(obj.get("allowedPaths"), f"{where}.allowedPaths", MAX_CLOSEOUT_PATHS)
    if len(paths) < 1:
        _reject(f"{where}.allowedPaths: must be nonempty")
    paths_out = tuple(_require_string(p, f"{where}.allowedPaths", 4096) for p in paths)
    if tuple(sorted(paths_out)) != paths_out:
        _reject(f"{where}.allowedPaths: must be UTF-8 ascending sorted")
    if len(set(paths_out)) != len(paths_out):
        _reject(f"{where}.allowedPaths: duplicates forbidden")
    sem_digest = _require_digest(obj.get("semanticFileSetDigest"), f"{where}.semanticFileSetDigest")
    row_digest = _require_digest(obj.get("resultingTaskRowDigest"), f"{where}.resultingTaskRowDigest")
    return AllowedCloseoutPatchV1(
        schema=schema, id=cid, version=version, taskId=task_id,
        preCloseCandidate=candidate, allowedPaths=paths_out,
        semanticFileSetDigest=sem_digest, resultingTaskRowDigest=row_digest,
    )


def parse_semantic_closeout_file_set(obj: dict, where: str) -> SemanticCloseoutFileSetV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: semantic file set must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.semantic-closeout-file-set.v1":
        _reject(f"{where}.schema: must be proof-forge.semantic-closeout-file-set.v1")
    cid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    candidate = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    changes = _parse_closeout_changes(
        _require_array(obj.get("changes"), f"{where}.changes", MAX_CLOSEOUT_PATHS),
        f"{where}.changes",
    )
    return SemanticCloseoutFileSetV1(
        schema=schema, id=cid, version=version, taskId=task_id,
        preCloseCandidate=candidate, changes=changes,
    )


def parse_qualification_ref(obj: dict, where: str) -> TaskQualificationRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: qualification ref must be object")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    qid = _require_safe_id(obj.get("id"), f"{where}.id")
    digest = _require_digest(obj.get("digest"), f"{where}.digest")
    return TaskQualificationRefV1(taskId=task_id, id=qid, digest=digest)


def parse_qualification(obj: dict, where: str) -> TaskQualificationV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: qualification must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.task-qualification.v1":
        _reject(f"{where}.schema: must be proof-forge.task-qualification.v1")
    qid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    candidate = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    row = parse_task_row(obj.get("taskRow"), f"{where}.taskRow")
    freeze = parse_freeze_package_ref(obj.get("freezePackage"), f"{where}.freezePackage")
    gates_arr = _require_array(obj.get("gates"), f"{where}.gates", MAX_GATES)
    gates = tuple(parse_gate(g, f"{where}.gates") for g in gates_arr)
    _require_unique_sorted(gates, lambda g: g.gateId, f"{where}.gates")
    deps_arr = _require_array(obj.get("dependencies"), f"{where}.dependencies", MAX_DEPENDENCIES)
    deps = tuple(parse_dependency(d, f"{where}.dependencies") for d in deps_arr)
    _require_unique_sorted(deps, lambda d: d.taskId, f"{where}.dependencies")
    verifier = parse_verifier_identity(obj.get("verifier"), f"{where}.verifier")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    patch = parse_content_ref(obj.get("allowedCloseoutPatch"), f"{where}.allowedCloseoutPatch")
    reviews_arr = _require_array(obj.get("independentReviews"), f"{where}.independentReviews", MAX_REVIEWS)
    reviews = tuple(parse_independent_review_ref(r, f"{where}.independentReviews") for r in reviews_arr)
    _require_unique_sorted(reviews, lambda r: (r.reviewerId, r.reportDigest.bytes.hex()), f"{where}.independentReviews")
    sigs = _parse_dependency_signatures(obj, where)
    return TaskQualificationV1(
        schema=schema, id=qid, version=version, taskId=task_id,
        preCloseCandidate=candidate, taskRow=row, freezePackage=freeze,
        gates=gates, dependencies=deps, verifier=verifier,
        authorityPolicy=policy, allowedCloseoutPatch=patch,
        independentReviews=reviews, signatures=sigs,
    )


# ---------------------------------------------------------------------------
# §6 TaskCompletionReceipt, CloseoutFileSet
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TaskCompletionReceiptRefV1:
    taskId: str
    id: str
    digest: Digest


@dataclass(frozen=True)
class TaskCompletionReceiptV1:
    schema: str
    id: str
    version: str
    taskId: str
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity
    qualification: TaskQualificationRefV1
    allowedCloseoutPatch: ContentRef
    closeoutDiffDigest: Digest
    authorityPolicy: ContentRef
    revocationSnapshot: ContentRef
    issuedAt: str
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class CloseoutFileSetV1:
    schema: str
    id: str
    version: str
    taskId: str
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity
    changes: Tuple  # tuple of (path, beforeDigest|None, afterDigest|None)


def parse_completion_receipt(obj: dict, where: str) -> TaskCompletionReceiptV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: receipt must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.task-completion-receipt.v1":
        _reject(f"{where}.schema: must be proof-forge.task-completion-receipt.v1")
    rid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    pre = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    close = parse_candidate_identity(obj.get("closeoutCandidate"), f"{where}.closeoutCandidate")
    qual = parse_qualification_ref(obj.get("qualification"), f"{where}.qualification")
    patch = parse_content_ref(obj.get("allowedCloseoutPatch"), f"{where}.allowedCloseoutPatch")
    diff_digest = _require_digest(obj.get("closeoutDiffDigest"), f"{where}.closeoutDiffDigest")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    revocation = parse_content_ref(obj.get("revocationSnapshot"), f"{where}.revocationSnapshot")
    issued = _require_rfc3339_utc(obj.get("issuedAt"), f"{where}.issuedAt")
    sigs = _parse_dependency_signatures(obj, where)
    return TaskCompletionReceiptV1(
        schema=schema, id=rid, version=version, taskId=task_id,
        preCloseCandidate=pre, closeoutCandidate=close, qualification=qual,
        allowedCloseoutPatch=patch, closeoutDiffDigest=diff_digest,
        authorityPolicy=policy, revocationSnapshot=revocation,
        issuedAt=issued, signatures=sigs,
    )


def parse_closeout_file_set(obj: dict, where: str) -> CloseoutFileSetV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: closeout file set must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.closeout-file-set.v1":
        _reject(f"{where}.schema: must be proof-forge.closeout-file-set.v1")
    cid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    pre = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    close = parse_candidate_identity(obj.get("closeoutCandidate"), f"{where}.closeoutCandidate")
    changes = _parse_closeout_changes(
        _require_array(obj.get("changes"), f"{where}.changes", MAX_CLOSEOUT_PATHS),
        f"{where}.changes",
    )
    return CloseoutFileSetV1(
        schema=schema, id=cid, version=version, taskId=task_id,
        preCloseCandidate=pre, closeoutCandidate=close, changes=changes,
    )


# ---------------------------------------------------------------------------
# §7 D0-10 one-time bootstrap objects
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class GovernanceBootstrapCompletionV1:
    schema: str
    id: str
    version: str
    taskId: str  # "TASK-D0-07" | "TASK-D0-10"
    rulingId: str  # "GOV-D0CLOSE-001" | "GOV-TASKQUAL-BOOTSTRAP-001"
    purpose: str
    completionCandidate: CandidateIdentity
    ruling: NormativeDocumentRefV1
    sourceClosure: RawDocumentRefV1
    authorityPolicy: ContentRef
    independentReviews: Tuple[IndependentReviewRefV1, ...]
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class D0_10BootstrapGateV1:
    gateId: str
    taskId: str  # "TASK-D0-10"
    testIds: Tuple[str, ...]
    evidence: Tuple[EvidenceRefV1, ...]
    commandPolicy: ContentRef
    eligibleStage0Handoff: ContentRef
    sessionContainment: ContentRef
    freshness: ContentRef
    privateScan: ContentRef
    revocationSnapshot: ContentRef


@dataclass(frozen=True)
class D0_10BootstrapApprovalV1:
    schema: str
    id: str
    version: str
    taskId: str  # "TASK-D0-10"
    ruling: NormativeDocumentRefV1
    preCloseCandidate: CandidateIdentity
    taskRow: TaskQualificationTaskRowV1
    freezePackage: TaskFreezePackageRefV1
    verifier: VerifierIdentityV1
    protectedConsumer: VerifierIdentityV1
    verifierClosureDigest: Digest
    consumerClosureDigest: Digest
    tstDocSubprofile: str  # "TST-DOC-001/task-qualification-v1"
    bootstrapGate: D0_10BootstrapGateV1
    d0_07Bridge: GovernanceBootstrapReceiptDependencyV1
    allowedCloseoutPatch: ContentRef
    independentReviews: Tuple[IndependentReviewRefV1, ...]
    authorityPolicy: ContentRef
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class D0_10BootstrapReceiptV1:
    schema: str
    id: str
    version: str
    taskId: str  # "TASK-D0-10"
    ruling: NormativeDocumentRefV1
    preCloseCandidate: CandidateIdentity
    closeoutCandidate: CandidateIdentity
    approvalDigest: Digest
    allowedCloseoutPatch: ContentRef
    closeoutDiffDigest: Digest
    authorityPolicy: ContentRef
    revocationSnapshot: ContentRef
    ledgerGrade: str  # "bootstrap"
    purpose: str  # "d0-10-taskqual-one-time-bridge"
    issuedAt: str
    signatures: Tuple[ApprovalSignatureV1, ...]


def parse_governance_bootstrap_completion(obj: dict, where: str) -> GovernanceBootstrapCompletionV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: governance completion must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.governance-bootstrap-completion.v1":
        _reject(f"{where}.schema: must be proof-forge.governance-bootstrap-completion.v1")
    cid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    ruling_id = obj.get("rulingId")
    # positional enum: (D0-07, GOV-D0CLOSE-001) or (D0-10, GOV-TASKQUAL-BOOTSTRAP-001)
    pairs = {("TASK-D0-07", "GOV-D0CLOSE-001"), ("TASK-D0-10", "GOV-TASKQUAL-BOOTSTRAP-001")}
    if (task_id, ruling_id) not in pairs:
        _reject(f"{where}: (taskId, rulingId) must be one of {sorted(pairs)}")
    purpose = obj.get("purpose")
    purpose_pairs = {
        ("TASK-D0-07", "d0-07-historical-bootstrap-closeout"),
        ("TASK-D0-10", "d0-10-taskqual-one-time-bridge"),
    }
    if (task_id, purpose) not in purpose_pairs:
        _reject(f"{where}: (taskId, purpose) pair invalid")
    candidate = parse_candidate_identity(obj.get("completionCandidate"), f"{where}.completionCandidate")
    ruling = parse_normative_document_ref(obj.get("ruling"), f"{where}.ruling")
    source = parse_raw_document_ref(obj.get("sourceClosure"), f"{where}.sourceClosure")
    # D0-07 source path fixed
    if task_id == "TASK-D0-07":
        if source.path != "docs/governance/bootstrap-closure/TASK-D0-07.attest.json":
            _reject(f"{where}.sourceClosure.path: D0-07 path fixed")
    elif task_id == "TASK-D0-10":
        if source.path != "docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json":
            _reject(f"{where}.sourceClosure.path: D0-10 path fixed")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    reviews_arr = _require_array(obj.get("independentReviews"), f"{where}.independentReviews", MAX_REVIEWS)
    reviews = tuple(parse_independent_review_ref(r, f"{where}.independentReviews") for r in reviews_arr)
    _require_unique_sorted(reviews, lambda r: (r.reviewerId, r.reportDigest.bytes.hex()), f"{where}.independentReviews")
    sigs = _parse_dependency_signatures(obj, where)
    return GovernanceBootstrapCompletionV1(
        schema=schema, id=cid, version=version, taskId=task_id,
        rulingId=ruling_id, purpose=purpose, completionCandidate=candidate,
        ruling=ruling, sourceClosure=source, authorityPolicy=policy,
        independentReviews=reviews, signatures=sigs,
    )


def parse_d0_10_bootstrap_gate(obj: dict, where: str) -> D0_10BootstrapGateV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: d0-10 gate must be object")
    gate_id = _require_safe_id(obj.get("gateId"), f"{where}.gateId")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    if task_id != "TASK-D0-10":
        _reject(f"{where}.taskId: must be TASK-D0-10")
    test_ids = _parse_id_list(obj.get("testIds"), f"{where}.testIds", _require_test_id)
    if test_ids != ("TST-DOC-001",):
        _reject(f"{where}.testIds: must be ['TST-DOC-001']")
    ev_arr = _require_array(obj.get("evidence"), f"{where}.evidence", MAX_EVIDENCE)
    ev_refs = tuple(parse_evidence_ref(e, f"{where}.evidence") for e in ev_arr)
    cmd = parse_content_ref(obj.get("commandPolicy"), f"{where}.commandPolicy")
    handoff = parse_content_ref(obj.get("eligibleStage0Handoff"), f"{where}.eligibleStage0Handoff")
    containment = parse_content_ref(obj.get("sessionContainment"), f"{where}.sessionContainment")
    freshness = parse_content_ref(obj.get("freshness"), f"{where}.freshness")
    scan = parse_content_ref(obj.get("privateScan"), f"{where}.privateScan")
    revocation = parse_content_ref(obj.get("revocationSnapshot"), f"{where}.revocationSnapshot")
    return D0_10BootstrapGateV1(
        gateId=gate_id, taskId=task_id, testIds=test_ids, evidence=ev_refs,
        commandPolicy=cmd, eligibleStage0Handoff=handoff, sessionContainment=containment,
        freshness=freshness, privateScan=scan, revocationSnapshot=revocation,
    )


def parse_d0_10_bootstrap_approval(obj: dict, where: str) -> D0_10BootstrapApprovalV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: d0-10 approval must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.d0-10-bootstrap-approval.v1":
        _reject(f"{where}.schema: must be proof-forge.d0-10-bootstrap-approval.v1")
    aid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    if task_id != "TASK-D0-10":
        _reject(f"{where}.taskId: must be TASK-D0-10")
    ruling = parse_normative_document_ref(obj.get("ruling"), f"{where}.ruling")
    candidate = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    row = parse_task_row(obj.get("taskRow"), f"{where}.taskRow")
    freeze = parse_freeze_package_ref(obj.get("freezePackage"), f"{where}.freezePackage")
    verifier = parse_verifier_identity(obj.get("verifier"), f"{where}.verifier")
    consumer = parse_verifier_identity(obj.get("protectedConsumer"), f"{where}.protectedConsumer")
    vcd = _require_digest(obj.get("verifierClosureDigest"), f"{where}.verifierClosureDigest")
    ccd = _require_digest(obj.get("consumerClosureDigest"), f"{where}.consumerClosureDigest")
    subprofile = obj.get("tstDocSubprofile")
    if subprofile != "TST-DOC-001/task-qualification-v1":
        _reject(f"{where}.tstDocSubprofile: must be TST-DOC-001/task-qualification-v1")
    gate = parse_d0_10_bootstrap_gate(obj.get("bootstrapGate"), f"{where}.bootstrapGate")
    bridge = parse_dependency(obj.get("d0_07Bridge"), f"{where}.d0_07Bridge")
    if not isinstance(bridge, GovernanceBootstrapReceiptDependencyV1):
        _reject(f"{where}.d0_07Bridge: must be governance-bootstrap-receipt")
    if bridge.taskId != "TASK-D0-07":
        _reject(f"{where}.d0_07Bridge.taskId: must be TASK-D0-07")
    patch = parse_content_ref(obj.get("allowedCloseoutPatch"), f"{where}.allowedCloseoutPatch")
    reviews_arr = _require_array(obj.get("independentReviews"), f"{where}.independentReviews", MAX_REVIEWS)
    reviews = tuple(parse_independent_review_ref(r, f"{where}.independentReviews") for r in reviews_arr)
    _require_unique_sorted(reviews, lambda r: (r.reviewerId, r.reportDigest.bytes.hex()), f"{where}.independentReviews")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    sigs = _parse_dependency_signatures(obj, where)
    return D0_10BootstrapApprovalV1(
        schema=schema, id=aid, version=version, taskId=task_id, ruling=ruling,
        preCloseCandidate=candidate, taskRow=row, freezePackage=freeze,
        verifier=verifier, protectedConsumer=consumer,
        verifierClosureDigest=vcd, consumerClosureDigest=ccd,
        tstDocSubprofile=subprofile, bootstrapGate=gate, d0_07Bridge=bridge,
        allowedCloseoutPatch=patch, independentReviews=reviews,
        authorityPolicy=policy, signatures=sigs,
    )


def parse_d0_10_bootstrap_receipt(obj: dict, where: str) -> D0_10BootstrapReceiptV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: d0-10 receipt must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != "proof-forge.d0-10-bootstrap-receipt.v1":
        _reject(f"{where}.schema: must be proof-forge.d0-10-bootstrap-receipt.v1")
    rid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    task_id = _require_task_id(obj.get("taskId"), f"{where}.taskId")
    if task_id != "TASK-D0-10":
        _reject(f"{where}.taskId: must be TASK-D0-10")
    ruling = parse_normative_document_ref(obj.get("ruling"), f"{where}.ruling")
    pre = parse_candidate_identity(obj.get("preCloseCandidate"), f"{where}.preCloseCandidate")
    close = parse_candidate_identity(obj.get("closeoutCandidate"), f"{where}.closeoutCandidate")
    approval_digest = _require_digest(obj.get("approvalDigest"), f"{where}.approvalDigest")
    patch = parse_content_ref(obj.get("allowedCloseoutPatch"), f"{where}.allowedCloseoutPatch")
    diff_digest = _require_digest(obj.get("closeoutDiffDigest"), f"{where}.closeoutDiffDigest")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    revocation = parse_content_ref(obj.get("revocationSnapshot"), f"{where}.revocationSnapshot")
    grade = obj.get("ledgerGrade")
    if grade != "bootstrap":
        _reject(f"{where}.ledgerGrade: must be 'bootstrap'")
    purpose = obj.get("purpose")
    if purpose != "d0-10-taskqual-one-time-bridge":
        _reject(f"{where}.purpose: must be 'd0-10-taskqual-one-time-bridge'")
    issued = _require_rfc3339_utc(obj.get("issuedAt"), f"{where}.issuedAt")
    sigs = _parse_dependency_signatures(obj, where)
    return D0_10BootstrapReceiptV1(
        schema=schema, id=rid, version=version, taskId=task_id, ruling=ruling,
        preCloseCandidate=pre, closeoutCandidate=close, approvalDigest=approval_digest,
        allowedCloseoutPatch=patch, closeoutDiffDigest=diff_digest,
        authorityPolicy=policy, revocationSnapshot=revocation,
        ledgerGrade=grade, purpose=purpose, issuedAt=issued, signatures=sigs,
    )


# ---------------------------------------------------------------------------
# §8.2 Fixture policy, principals, verifier key, resolved blob
# ---------------------------------------------------------------------------

# RFC 8032 §7.1 Ed25519 test vectors — public keys (lowercase hex, 32 bytes).
# These are the fixed fixture policy principal public keys and the non-quorum
# verifier key. Seeds are verified at runtime against the project's pure-Python
# Ed25519 implementation; if a seed does not reproduce the exact public key,
# the fixture builder rejects.
RFC8032_VECTOR_1_PUBLIC = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
RFC8032_VECTOR_2_PUBLIC = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
RFC8032_VECTOR_3_PUBLIC = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
RFC8032_VECTOR_4_PUBLIC = "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"

FIXTURE_NAMESPACE = "task-qualification-fixture-v1"
FIXTURE_PRODUCTION_NAMESPACE = "task-qualification-production-v1"
FIXTURE_PRINCIPAL_ARCHITECTURE = "fixture-principal-architecture"
FIXTURE_PRINCIPAL_QUALITY = "fixture-principal-quality"
FIXTURE_PRINCIPAL_SECURITY = "fixture-principal-security"
FIXTURE_KEY_ARCHITECTURE = "fixture-key-architecture"
FIXTURE_KEY_QUALITY = "fixture-key-quality"
FIXTURE_KEY_SECURITY = "fixture-key-security"
FIXTURE_VERIFIER_KEY_ID = "fixture-verifier-key"


@dataclass(frozen=True)
class FixtureAuthorityPrincipalV1:
    principalId: str
    keyId: str
    publicKey: bytes  # 32-byte Ed25519 public key
    roles: Tuple[str, ...]


@dataclass(frozen=True)
class FixtureVerifierKeyV1:
    keyId: str  # "fixture-verifier-key"
    algorithm: str  # "ed25519"
    publicKey: bytes  # 32-byte


@dataclass(frozen=True)
class FixturePolicyV1:
    schema: str
    id: str
    version: str
    namespace: str
    principals: Tuple[FixtureAuthorityPrincipalV1, ...]
    rule: ApprovalRuleV1
    verifierKey: FixtureVerifierKeyV1


@dataclass(frozen=True)
class FixtureResolvedBlobV1:
    schema: str
    id: str
    version: str
    role: str
    payloadSha256: Digest


@dataclass(frozen=True)
class FixtureNormativeDocumentRefV1:
    id: str
    status: str  # "accepted"
    contentDigest: Digest
    reviewCommit: str


# The canonical RFC 8032 §7.1 test vector seeds (verified against the project's
# pure-Python Ed25519 implementation in bootstrap_task_producers). These produce
# the exact public keys above.
RFC8032_VECTOR_SEEDS = {
    1: bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    ),
    2: bytes.fromhex(
        "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
    ),
    3: bytes.fromhex(
        "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
    ),
    4: bytes.fromhex(
        "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5"
    ),
}


# Fixed fixture principal registry — §8.2 table. Principals sorted by keyId.
FIXTURE_PRINCIPALS = (
    FixtureAuthorityPrincipalV1(
        principalId=FIXTURE_PRINCIPAL_ARCHITECTURE,
        keyId=FIXTURE_KEY_ARCHITECTURE,
        publicKey=bytes.fromhex(RFC8032_VECTOR_1_PUBLIC),
        roles=("architecture",),
    ),
    FixtureAuthorityPrincipalV1(
        principalId=FIXTURE_PRINCIPAL_QUALITY,
        keyId=FIXTURE_KEY_QUALITY,
        publicKey=bytes.fromhex(RFC8032_VECTOR_2_PUBLIC),
        roles=("quality",),
    ),
    FixtureAuthorityPrincipalV1(
        principalId=FIXTURE_PRINCIPAL_SECURITY,
        keyId=FIXTURE_KEY_SECURITY,
        publicKey=bytes.fromhex(RFC8032_VECTOR_3_PUBLIC),
        roles=("security",),
    ),
)

FIXTURE_VERIFIER_KEY = FixtureVerifierKeyV1(
    keyId=FIXTURE_VERIFIER_KEY_ID,
    algorithm="ed25519",
    publicKey=bytes.fromhex(RFC8032_VECTOR_4_PUBLIC),
)

FIXTURE_RULE = ApprovalRuleV1(
    requiredRoles=("architecture", "quality", "security"),
    minimumDistinctSigners=3,
)

FIXTURE_POLICY_ID = "task-qualification-fixture-policy-v1"
FIXTURE_POLICY_SCHEMA = "proof-forge.task-qualification-fixture-policy.v1"

FIXTURE_RESOLVED_BLOB_SCHEMA = "proof-forge.task-qualification-fixture-resolved-blob.v1"
TASK_QUALIFICATION_SCHEMA = "proof-forge.task-qualification.v1"
GOVERNANCE_BOOTSTRAP_COMPLETION_SCHEMA = "proof-forge.governance-bootstrap-completion.v1"
PRODUCTION_PROFILE_SCHEMA = "proof-forge.task-qualification-production-profile.v1"
FIXTURE_RESOLVED_BLOB_ROLE_PREFIXES = (
    "resolved-tool",
    "resolved-probe",
    "sandbox-policy",
    "verifier-executable",
    "verifier-closure",
    "verifier-build-policy",
    "private-scan-policy",
    "authority-store-service",
    "host-observation",
    "host-profile",
)


# Schema -> domain digest mapping for typed-content members.
# Each typed-content member's bytesHex is the PF-JCS of a wire object whose
# digest is computed under a schema-specific domain. The verifier recomputes
# the content ref from the decoded bytes using this mapping so it cannot be
# fooled by a member that carries a stale content.digest.
#
# Entries are added as new typed-content schemas are introduced. An unknown
# schema is rejected by recompute_typed_content_ref.
_TYPED_CONTENT_SCHEMA_DOMAINS = {
    FIXTURE_POLICY_SCHEMA: DOMAIN_FIXTURE_POLICY,
    FIXTURE_RESOLVED_BLOB_SCHEMA: DOMAIN_FIXTURE_RESOLVED_BLOB,
    TASK_QUALIFICATION_SCHEMA: DOMAIN_TASK_QUALIFICATION,
    GOVERNANCE_BOOTSTRAP_COMPLETION_SCHEMA: DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION,
    PRODUCTION_PROFILE_SCHEMA: DOMAIN_PRODUCTION_PROFILE,
}


def recompute_typed_content_ref(schema: str, obj: dict) -> ContentRef:
    """Recompute a ContentRef for a typed-content member from its decoded wire.

    The schema selects the domain; the id and version are read from the
    decoded object so a member cannot carry a content ref that disagrees
    with its own bytes. Raises (via _reject) on unknown schema or missing
    id/version.
    """
    if schema not in _TYPED_CONTENT_SCHEMA_DOMAINS:
        _reject(f"recompute_typed_content_ref: unknown schema '{schema}'")
    if not isinstance(obj, dict):
        _reject(f"recompute_typed_content_ref: decoded value must be object")
    obj_id = obj.get("id")
    obj_version = obj.get("version")
    if not isinstance(obj_id, str) or not obj_id:
        _reject(f"recompute_typed_content_ref: missing id")
    if not isinstance(obj_version, str) or not obj_version:
        _reject(f"recompute_typed_content_ref: missing version")
    domain = _TYPED_CONTENT_SCHEMA_DOMAINS[schema]
    digest = domain_digest(domain, obj)
    return ContentRef(schema=schema, id=obj_id, version=obj_version, digest=digest)


def _require_ed25519_public_key_hex(value, where):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        _reject(f"{where}: must be 64 lowercase hex (32-byte Ed25519 public key)")
    return bytes.fromhex(value)


def parse_fixture_authority_principal(obj: dict, where: str) -> FixtureAuthorityPrincipalV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture principal must be object")
    pid = _require_safe_id(obj.get("principalId"), f"{where}.principalId")
    key_id = _require_safe_id(obj.get("keyId"), f"{where}.keyId")
    pk = _require_ed25519_public_key_hex(obj.get("publicKey"), f"{where}.publicKey")
    roles = _require_array(obj.get("roles"), f"{where}.roles", 16)
    if len(roles) == 0:
        _reject(f"{where}.roles: must be nonempty")
    roles_out = tuple(_BTO._parse_approval_roles(roles, f"{where}.roles"))
    return FixtureAuthorityPrincipalV1(
        principalId=pid, keyId=key_id, publicKey=pk, roles=roles_out,
    )


def parse_fixture_verifier_key(obj: dict, where: str) -> FixtureVerifierKeyV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture verifier key must be object")
    key_id = _require_safe_id(obj.get("keyId"), f"{where}.keyId")
    algorithm = obj.get("algorithm")
    if algorithm != "ed25519":
        _reject(f"{where}.algorithm: must be 'ed25519'")
    pk = _require_ed25519_public_key_hex(obj.get("publicKey"), f"{where}.publicKey")
    return FixtureVerifierKeyV1(keyId=key_id, algorithm=algorithm, publicKey=pk)


def parse_fixture_policy(obj: dict, where: str) -> FixturePolicyV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture policy must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != FIXTURE_POLICY_SCHEMA:
        _reject(f"{where}.schema: must be {FIXTURE_POLICY_SCHEMA}")
    pid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    namespace = obj.get("namespace")
    if namespace != FIXTURE_NAMESPACE:
        _reject(f"{where}.namespace: must be {FIXTURE_NAMESPACE}")
    principals_arr = _require_array(obj.get("principals"), f"{where}.principals", 16)
    principals = tuple(
        parse_fixture_authority_principal(p, f"{where}.principals") for p in principals_arr
    )
    _require_unique_sorted(principals, lambda p: p.keyId, f"{where}.principals")
    # GAP-11: §8.2 fixture-profile principal signing keys must use RFC 8032
    # §7.1 public test vectors #1-#3 (architecture/quality/security), and the
    # non-quorum verifier key must use vector #4. Pin keyIds and public keys.
    if len(principals) != 3:
        _reject(f"{where}.principals: must be exactly 3 (fixture)")
    expected_pins = (
        (FIXTURE_KEY_ARCHITECTURE, bytes.fromhex(RFC8032_VECTOR_1_PUBLIC), ("architecture",)),
        (FIXTURE_KEY_QUALITY, bytes.fromhex(RFC8032_VECTOR_2_PUBLIC), ("quality",)),
        (FIXTURE_KEY_SECURITY, bytes.fromhex(RFC8032_VECTOR_3_PUBLIC), ("security",)),
    )
    for p, (exp_key_id, exp_pub, exp_roles) in zip(principals, expected_pins):
        if p.keyId != exp_key_id:
            _reject(f"{where}.principals: keyId must be {exp_key_id}, got {p.keyId}")
        if p.publicKey != exp_pub:
            _reject(f"{where}.principals[{p.keyId}].publicKey must be RFC 8032 vector public key")
        if tuple(p.roles) != exp_roles:
            _reject(f"{where}.principals[{p.keyId}].roles must be {exp_roles}, got {tuple(p.roles)}")
    rule = _BTO._parse_approval_rule(obj.get("rule"), f"{where}.rule")
    verifier_key = parse_fixture_verifier_key(obj.get("verifierKey"), f"{where}.verifierKey")
    # GAP-11: verifier key must use RFC 8032 vector #4.
    if verifier_key.keyId != FIXTURE_VERIFIER_KEY_ID:
        _reject(f"{where}.verifierKey.keyId must be {FIXTURE_VERIFIER_KEY_ID}, got {verifier_key.keyId}")
    if verifier_key.publicKey != bytes.fromhex(RFC8032_VECTOR_4_PUBLIC):
        _reject(f"{where}.verifierKey.publicKey must be RFC 8032 vector #4 public key")
    return FixturePolicyV1(
        schema=schema, id=pid, version=version, namespace=namespace,
        principals=principals, rule=rule, verifierKey=verifier_key,
    )


def parse_fixture_resolved_blob(obj: dict, where: str) -> FixtureResolvedBlobV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture resolved blob must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != FIXTURE_RESOLVED_BLOB_SCHEMA:
        _reject(f"{where}.schema: must be {FIXTURE_RESOLVED_BLOB_SCHEMA}")
    rid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    role = _require_string(obj.get("role"), f"{where}.role", 4096)
    payload_digest = _require_digest(obj.get("payloadSha256"), f"{where}.payloadSha256")
    return FixtureResolvedBlobV1(
        schema=schema, id=rid, version=version, role=role, payloadSha256=payload_digest,
    )


def parse_fixture_normative_document_ref(obj: dict, where: str) -> FixtureNormativeDocumentRefV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture normative doc ref must be object")
    cid = _require_ascii_text(obj.get("id"), PROFILE_ID_RE, f"{where}.id", 127)
    status = obj.get("status")
    if status != "accepted":
        _reject(f"{where}.status: must be 'accepted'")
    content_digest = _require_digest(obj.get("contentDigest"), f"{where}.contentDigest")
    review_commit = _require_git_object(obj.get("reviewCommit"), f"{where}.reviewCommit")
    return FixtureNormativeDocumentRefV1(
        id=cid, status=status, contentDigest=content_digest, reviewCommit=review_commit,
    )


# ---------------------------------------------------------------------------
# Fixture policy wire encoders (used by fixture builders and tests)
# ---------------------------------------------------------------------------

def fixture_principal_to_wire(p: FixtureAuthorityPrincipalV1) -> dict:
    return {
        "principalId": p.principalId,
        "keyId": p.keyId,
        "publicKey": p.publicKey.hex(),
        "roles": list(p.roles),
    }


def fixture_verifier_key_to_wire(k: FixtureVerifierKeyV1) -> dict:
    return {
        "keyId": k.keyId,
        "algorithm": k.algorithm,
        "publicKey": k.publicKey.hex(),
    }


def fixture_policy_to_wire(policy: FixturePolicyV1) -> dict:
    return {
        "schema": policy.schema,
        "id": policy.id,
        "version": policy.version,
        "namespace": policy.namespace,
        "principals": [fixture_principal_to_wire(p) for p in policy.principals],
        "rule": {
            "requiredRoles": list(policy.rule.requiredRoles),
            "minimumDistinctSigners": policy.rule.minimumDistinctSigners,
        },
        "verifierKey": fixture_verifier_key_to_wire(policy.verifierKey),
    }


def fixture_resolved_blob_to_wire(blob: FixtureResolvedBlobV1) -> dict:
    return {
        "schema": blob.schema,
        "id": blob.id,
        "version": blob.version,
        "role": blob.role,
        "payloadSha256": digest_to_wire(blob.payloadSha256),
    }


def fixture_policy_content_ref(policy: FixturePolicyV1) -> ContentRef:
    """Compute the ContentRef for a FixturePolicyV1."""
    wire = fixture_policy_to_wire(policy)
    digest = domain_digest(DOMAIN_FIXTURE_POLICY, wire)
    return ContentRef(
        schema=policy.schema,
        id=policy.id,
        version=policy.version,
        digest=digest,
    )


def fixture_resolved_blob_content_ref(blob: FixtureResolvedBlobV1) -> ContentRef:
    """Compute the ContentRef for a FixtureResolvedBlobV1."""
    wire = fixture_resolved_blob_to_wire(blob)
    digest = domain_digest(DOMAIN_FIXTURE_RESOLVED_BLOB, wire)
    return ContentRef(
        schema=blob.schema,
        id=blob.id,
        version=blob.version,
        digest=digest,
    )


def build_default_fixture_policy() -> FixturePolicyV1:
    """Build the fixed fixture policy with the RFC 8032 §7.1 test vector principals."""
    return FixturePolicyV1(
        schema=FIXTURE_POLICY_SCHEMA,
        id=FIXTURE_POLICY_ID,
        version="1.0.0",
        namespace=FIXTURE_NAMESPACE,
        principals=FIXTURE_PRINCIPALS,
        rule=FIXTURE_RULE,
        verifierKey=FIXTURE_VERIFIER_KEY,
    )


def build_fixture_resolved_blob(gate_id: str, role_prefix: str, payload: bytes) -> FixtureResolvedBlobV1:
    """Build a FixtureResolvedBlobV1 for a gate-keyed resolved role."""
    if role_prefix not in FIXTURE_RESOLVED_BLOB_ROLE_PREFIXES:
        _reject(f"build_fixture_resolved_blob: role_prefix '{role_prefix}' not allowed")
    role = f"{role_prefix}/{gate_id}"
    blob_id = f"fixture-resolved-{gate_id}-{role_prefix}"
    payload_digest = plain_sha256_digest(payload)
    return FixtureResolvedBlobV1(
        schema=FIXTURE_RESOLVED_BLOB_SCHEMA,
        id=blob_id,
        version="1.0.0",
        role=role,
        payloadSha256=payload_digest,
    )


# ---------------------------------------------------------------------------
# §8.2 Content bundle, verification profile, content members
# ---------------------------------------------------------------------------

OPERATIONS = (
    "task-qualification",
    "task-completion",
    "d0-10-bootstrap-approval",
    "d0-10-bootstrap-receipt",
)

OPERATION_BUNDLE_IDS = {
    "task-qualification": "task-qualification-content-task-qualification",
    "task-completion": "task-qualification-content-task-completion",
    "d0-10-bootstrap-approval": "task-qualification-content-d0-10-bootstrap-approval",
    "d0-10-bootstrap-receipt": "task-qualification-content-d0-10-bootstrap-receipt",
}

MAX_MEMBER_BYTES = 64 * 1024 * 1024  # 64 MiB per member
MAX_BUNDLE_AGGREGATE = 128 * 1024 * 1024  # 128 MiB aggregate
MAX_BUNDLE_CANONICAL = 260 * 1024 * 1024  # 260 MiB
MAX_SUBJECT_BYTES = 4 * 1024 * 1024  # 4 MiB
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024  # 64 MiB per archive
MAX_ARCHIVE_PATHS = 100_000
MAX_ARCHIVE_EXPANDED = 128 * 1024 * 1024  # 128 MiB
MAX_ARCHIVE_PATH_BYTES = 4096
MAX_MEMBERS = 4096

PRODUCTION_PROFILE_ID = "task-qualification-production-profile-v1"
PRODUCTION_PROFILE_PIN_SCHEMA = "proof-forge.task-qualification-production-profile-pin.v1"
PRODUCTION_PROFILE_PIN_ID = "task-qualification-production-profile-v1"

FIXTURE_KEYSET = "rfc8032-test-vectors"

BUNDLE_SCHEMA = "proof-forge.task-qualification-content-bundle.v1"


@dataclass(frozen=True)
class ProductionVerificationProfileV1:
    schema: str
    id: str
    version: str
    kind: str  # "production"
    namespace: str
    expectedAuthorityPolicy: ContentRef
    adapter: VerifierIdentityV1
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class FixtureVerificationProfileV1:
    kind: str  # "fixture"
    namespace: str
    fixturePolicy: ContentRef
    keySet: str  # "rfc8032-test-vectors"


@dataclass(frozen=True)
class TypedContentMemberV1:
    role: str
    kind: str  # "typed-content"
    content: ContentRef
    bytesHex: str


@dataclass(frozen=True)
class RawContentMemberV1:
    role: str
    kind: str  # "raw-source"
    raw: RawDocumentRefV1
    bytesHex: str


@dataclass(frozen=True)
class ArchiveMemberV1:
    role: str
    kind: str  # "archive"
    archiveSha256: Digest
    bytesHex: str


@dataclass(frozen=True)
class GitObjectMemberV1:
    role: str
    kind: str  # "git-object"
    objectId: str
    objectType: str  # "commit"
    bytesHex: str


@dataclass(frozen=True)
class ReviewMemberV1:
    role: str
    kind: str  # "review"
    reviewerId: str
    reportDigest: Digest
    bytesHex: str


ContentMemberV1 = (
    TypedContentMemberV1
    | RawContentMemberV1
    | ArchiveMemberV1
    | GitObjectMemberV1
    | ReviewMemberV1
)


@dataclass(frozen=True)
class TaskQualificationContentBundleV1:
    schema: str
    id: str
    version: str
    operation: str
    verificationProfile: object  # Production or Fixture profile
    expectedAuthorityPolicy: ContentRef
    verificationInstant: str
    implementationInvocationId: str
    members: Tuple[ContentMemberV1, ...]


@dataclass(frozen=True)
class ProductionVerificationProfilePinV1:
    schema: str
    id: str
    version: str
    authorityPolicy: ContentRef
    namespace: str
    profile: ContentRef
    signatures: Tuple[ApprovalSignatureV1, ...]


def _require_bytes_hex(value, where, limit=MAX_MEMBER_BYTES):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]+", value) or len(value) % 2 != 0:
        _reject(f"{where}: bytesHex must be nonempty lowercase even hex")
    if len(value) < 2:
        _reject(f"{where}: bytesHex must be nonempty")
    decoded_len = len(value) // 2
    if decoded_len > limit:
        _reject(f"{where}: decoded bytes exceed {limit}")
    return value


def parse_production_verification_profile(obj: dict, where: str) -> ProductionVerificationProfileV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: production profile must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != PRODUCTION_PROFILE_SCHEMA:
        _reject(f"{where}.schema: must be {PRODUCTION_PROFILE_SCHEMA}")
    pid = _require_safe_id(obj.get("id"), f"{where}.id")
    if pid != PRODUCTION_PROFILE_ID:
        _reject(f"{where}.id: must be {PRODUCTION_PROFILE_ID}")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    kind = obj.get("kind")
    if kind != "production":
        _reject(f"{where}.kind: must be 'production'")
    namespace = obj.get("namespace")
    if namespace != FIXTURE_PRODUCTION_NAMESPACE:
        _reject(f"{where}.namespace: must be {FIXTURE_PRODUCTION_NAMESPACE}")
    policy = parse_content_ref(obj.get("expectedAuthorityPolicy"), f"{where}.expectedAuthorityPolicy")
    adapter = parse_verifier_identity(obj.get("adapter"), f"{where}.adapter")
    sigs = _parse_dependency_signatures(obj, where)
    return ProductionVerificationProfileV1(
        schema=schema, id=pid, version=version, kind=kind, namespace=namespace,
        expectedAuthorityPolicy=policy, adapter=adapter, signatures=sigs,
    )


def parse_fixture_verification_profile(obj: dict, where: str) -> FixtureVerificationProfileV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: fixture profile must be object")
    kind = obj.get("kind")
    if kind != "fixture":
        _reject(f"{where}.kind: must be 'fixture'")
    namespace = obj.get("namespace")
    if namespace != FIXTURE_NAMESPACE:
        _reject(f"{where}.namespace: must be {FIXTURE_NAMESPACE}")
    policy = parse_content_ref(obj.get("fixturePolicy"), f"{where}.fixturePolicy")
    key_set = obj.get("keySet")
    if key_set != FIXTURE_KEYSET:
        _reject(f"{where}.keySet: must be {FIXTURE_KEYSET}")
    return FixtureVerificationProfileV1(
        kind=kind, namespace=namespace, fixturePolicy=policy, keySet=key_set,
    )


def parse_verification_profile(obj: dict, where: str):
    if not isinstance(obj, dict):
        _reject(f"{where}: verification profile must be object")
    kind = obj.get("kind")
    if kind == "production":
        return parse_production_verification_profile(obj, where)
    if kind == "fixture":
        return parse_fixture_verification_profile(obj, where)
    _reject(f"{where}.kind: must be 'production' or 'fixture'")


def parse_content_member(obj: dict, where: str) -> ContentMemberV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: content member must be object")
    role = _require_string(obj.get("role"), f"{where}.role", 4096)
    kind = obj.get("kind")
    if kind == "typed-content":
        content = parse_content_ref(obj.get("content"), f"{where}.content")
        hex_val = _require_bytes_hex(obj.get("bytesHex"), f"{where}.bytesHex")
        return TypedContentMemberV1(role=role, kind=kind, content=content, bytesHex=hex_val)
    if kind == "raw-source":
        raw = parse_raw_document_ref(obj.get("raw"), f"{where}.raw")
        hex_val = _require_bytes_hex(obj.get("bytesHex"), f"{where}.bytesHex")
        return RawContentMemberV1(role=role, kind=kind, raw=raw, bytesHex=hex_val)
    if kind == "archive":
        digest = _require_digest(obj.get("archiveSha256"), f"{where}.archiveSha256")
        hex_val = _require_bytes_hex(obj.get("bytesHex"), f"{where}.bytesHex", MAX_ARCHIVE_BYTES)
        return ArchiveMemberV1(role=role, kind=kind, archiveSha256=digest, bytesHex=hex_val)
    if kind == "git-object":
        oid = _require_git_object(obj.get("objectId"), f"{where}.objectId")
        obj_type = obj.get("objectType")
        if obj_type != "commit":
            _reject(f"{where}.objectType: must be 'commit'")
        hex_val = _require_bytes_hex(obj.get("bytesHex"), f"{where}.bytesHex")
        return GitObjectMemberV1(role=role, kind=kind, objectId=oid, objectType=obj_type, bytesHex=hex_val)
    if kind == "review":
        reviewer_id = _require_safe_id(obj.get("reviewerId"), f"{where}.reviewerId")
        report_digest = _require_digest(obj.get("reportDigest"), f"{where}.reportDigest")
        hex_val = _require_bytes_hex(obj.get("bytesHex"), f"{where}.bytesHex", MAX_REVIEW_REPORT)
        return ReviewMemberV1(
            role=role, kind=kind, reviewerId=reviewer_id,
            reportDigest=report_digest, bytesHex=hex_val,
        )
    _reject(f"{where}.kind: unknown member kind '{kind}'")


def parse_content_bundle(obj: dict, where: str) -> TaskQualificationContentBundleV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: content bundle must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != BUNDLE_SCHEMA:
        _reject(f"{where}.schema: must be {BUNDLE_SCHEMA}")
    bid = _require_safe_id(obj.get("id"), f"{where}.id")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    operation = obj.get("operation")
    if operation not in OPERATIONS:
        _reject(f"{where}.operation: must be one of {OPERATIONS}")
    if bid != OPERATION_BUNDLE_IDS[operation]:
        _reject(f"{where}.id: must be {OPERATION_BUNDLE_IDS[operation]} for operation {operation}")
    profile = parse_verification_profile(obj.get("verificationProfile"), f"{where}.verificationProfile")
    policy = parse_content_ref(obj.get("expectedAuthorityPolicy"), f"{where}.expectedAuthorityPolicy")
    instant = _require_rfc3339_utc(obj.get("verificationInstant"), f"{where}.verificationInstant")
    impl_invocation = _require_safe_id(obj.get("implementationInvocationId"), f"{where}.implementationInvocationId")
    members_arr = _require_array(obj.get("members"), f"{where}.members", MAX_MEMBERS)
    if len(members_arr) == 0:
        _reject(f"{where}.members: must be nonempty")
    members = tuple(parse_content_member(m, f"{where}.members") for m in members_arr)
    _require_unique_sorted(members, lambda m: m.role, f"{where}.members")
    return TaskQualificationContentBundleV1(
        schema=schema, id=bid, version=version, operation=operation,
        verificationProfile=profile, expectedAuthorityPolicy=policy,
        verificationInstant=instant, implementationInvocationId=impl_invocation,
        members=members,
    )


def parse_production_profile_pin(obj: dict, where: str) -> ProductionVerificationProfilePinV1:
    if not isinstance(obj, dict):
        _reject(f"{where}: production profile pin must be object")
    schema = _require_ascii_text(obj.get("schema"), _BTO.SCHEMA_RE, f"{where}.schema", 127)
    if schema != PRODUCTION_PROFILE_PIN_SCHEMA:
        _reject(f"{where}.schema: must be {PRODUCTION_PROFILE_PIN_SCHEMA}")
    pid = _require_safe_id(obj.get("id"), f"{where}.id")
    if pid != PRODUCTION_PROFILE_PIN_ID:
        _reject(f"{where}.id: must be {PRODUCTION_PROFILE_PIN_ID}")
    version = _require_semver(obj.get("version"), f"{where}.version")
    if version != "1.0.0":
        _reject(f"{where}.version: must be 1.0.0")
    policy = parse_content_ref(obj.get("authorityPolicy"), f"{where}.authorityPolicy")
    namespace = obj.get("namespace")
    if namespace != FIXTURE_PRODUCTION_NAMESPACE:
        _reject(f"{where}.namespace: must be {FIXTURE_PRODUCTION_NAMESPACE}")
    profile = parse_content_ref(obj.get("profile"), f"{where}.profile")
    sigs = _parse_dependency_signatures(obj, where)
    return ProductionVerificationProfilePinV1(
        schema=schema, id=pid, version=version, authorityPolicy=policy,
        namespace=namespace, profile=profile, signatures=sigs,
    )


# Wire encoders for bundle/profile/members
def production_profile_to_wire(p: ProductionVerificationProfileV1) -> dict:
    return {
        "schema": p.schema,
        "id": p.id,
        "version": p.version,
        "kind": p.kind,
        "namespace": p.namespace,
        "expectedAuthorityPolicy": content_ref_to_wire(p.expectedAuthorityPolicy),
        "adapter": verifier_identity_to_wire(p.adapter),
        "signatures": [approval_signature_to_wire(s) for s in p.signatures],
    }


def fixture_profile_to_wire(p: FixtureVerificationProfileV1) -> dict:
    return {
        "kind": p.kind,
        "namespace": p.namespace,
        "fixturePolicy": content_ref_to_wire(p.fixturePolicy),
        "keySet": p.keySet,
    }


def verification_profile_to_wire(p) -> dict:
    if isinstance(p, ProductionVerificationProfileV1):
        return production_profile_to_wire(p)
    if isinstance(p, FixtureVerificationProfileV1):
        return fixture_profile_to_wire(p)
    _reject("verification_profile_to_wire: unknown profile type")


def verifier_identity_to_wire(v: VerifierIdentityV1) -> dict:
    return {
        "id": v.id,
        "executable": content_ref_to_wire(v.executable),
        "closure": content_ref_to_wire(v.closure),
        "sourceDigest": digest_to_wire(v.sourceDigest),
        "buildPolicy": content_ref_to_wire(v.buildPolicy),
    }


def approval_signature_to_wire(s: ApprovalSignatureV1) -> dict:
    return {
        "keyId": s.keyId,
        "algorithm": s.algorithm,
        "signature": s.signature.hex(),
    }


def content_member_to_wire(m: ContentMemberV1) -> dict:
    if isinstance(m, TypedContentMemberV1):
        return {
            "role": m.role,
            "kind": m.kind,
            "content": content_ref_to_wire(m.content),
            "bytesHex": m.bytesHex,
        }
    if isinstance(m, RawContentMemberV1):
        return {
            "role": m.role,
            "kind": m.kind,
            "raw": {"path": m.raw.path, "digest": digest_to_wire(m.raw.digest)},
            "bytesHex": m.bytesHex,
        }
    if isinstance(m, ArchiveMemberV1):
        return {
            "role": m.role,
            "kind": m.kind,
            "archiveSha256": digest_to_wire(m.archiveSha256),
            "bytesHex": m.bytesHex,
        }
    if isinstance(m, GitObjectMemberV1):
        return {
            "role": m.role,
            "kind": m.kind,
            "objectId": m.objectId,
            "objectType": m.objectType,
            "bytesHex": m.bytesHex,
        }
    if isinstance(m, ReviewMemberV1):
        return {
            "role": m.role,
            "kind": m.kind,
            "reviewerId": m.reviewerId,
            "reportDigest": digest_to_wire(m.reportDigest),
            "bytesHex": m.bytesHex,
        }
    _reject("content_member_to_wire: unknown member type")


def content_bundle_to_wire(b: TaskQualificationContentBundleV1) -> dict:
    return {
        "schema": b.schema,
        "id": b.id,
        "version": b.version,
        "operation": b.operation,
        "verificationProfile": verification_profile_to_wire(b.verificationProfile),
        "expectedAuthorityPolicy": content_ref_to_wire(b.expectedAuthorityPolicy),
        "verificationInstant": b.verificationInstant,
        "implementationInvocationId": b.implementationInvocationId,
        "members": [content_member_to_wire(m) for m in b.members],
    }


def production_profile_pin_to_wire(p: ProductionVerificationProfilePinV1) -> dict:
    return {
        "schema": p.schema,
        "id": p.id,
        "version": p.version,
        "authorityPolicy": content_ref_to_wire(p.authorityPolicy),
        "namespace": p.namespace,
        "profile": content_ref_to_wire(p.profile),
        "signatures": [approval_signature_to_wire(s) for s in p.signatures],
    }


def production_profile_content_ref(p: ProductionVerificationProfileV1) -> ContentRef:
    wire = production_profile_to_wire(p)
    digest = domain_digest(DOMAIN_PRODUCTION_PROFILE, wire)
    return ContentRef(schema=p.schema, id=p.id, version=p.version, digest=digest)


def production_profile_pin_content_ref(p: ProductionVerificationProfilePinV1) -> ContentRef:
    wire = production_profile_pin_to_wire(p)
    digest = domain_digest(DOMAIN_PRODUCTION_PROFILE_PIN, wire)
    return ContentRef(schema=p.schema, id=p.id, version=p.version, digest=digest)


# ---------------------------------------------------------------------------
# §2-§7 typed wire encoders (used by the §8.4 protected adapter projection)
# ---------------------------------------------------------------------------

def candidate_identity_to_wire(c: CandidateIdentity) -> dict:
    """Encode a CandidateIdentityV1 as the §1 `archiveSha256` wire form.

    The verifier projects Verified* records using the §1 wire spelling
    ``archiveSha256`` (not the legacy ``archiveDigest``). The digest field is
    omitted from the projection because the receiver recomputes it from
    the other three fields under the candidate domain.
    """
    return {
        "commit": c.commit,
        "treeObjectId": c.treeObjectId,
        "archiveSha256": digest_to_wire(c.archiveDigest),
    }


def normative_document_ref_to_wire(r: NormativeDocumentRefV1) -> dict:
    return {
        "id": r.id,
        "status": r.status,
        "contentDigest": digest_to_wire(r.contentDigest),
        "reviewCommit": r.reviewCommit,
    }


def raw_document_ref_to_wire(r: RawDocumentRefV1) -> dict:
    return {
        "path": r.path,
        "digest": digest_to_wire(r.digest),
    }


def evidence_ref_to_wire(e: EvidenceRefV1) -> dict:
    return {
        "id": e.id,
        "digest": digest_to_wire(e.digest),
    }


def independent_review_ref_to_wire(r: IndependentReviewRefV1) -> dict:
    return {
        "reviewerId": r.reviewerId,
        "reviewerKind": r.reviewerKind,
        "invocationId": r.invocationId,
        "reportDigest": digest_to_wire(r.reportDigest),
        "reviewCommit": r.reviewCommit,
        "reviewLink": r.reviewLink,
        "decision": r.decision,
        "findings": list(r.findings),
    }


def task_qualification_ref_to_wire(r: TaskQualificationRefV1) -> dict:
    return {
        "taskId": r.taskId,
        "id": r.id,
        "digest": digest_to_wire(r.digest),
    }


def completion_receipt_ref_to_wire(r: "TaskCompletionReceiptRefV1") -> dict:
    return {
        "taskId": r.taskId,
        "id": r.id,
        "digest": digest_to_wire(r.digest),
    }


def task_row_to_wire(r: TaskQualificationTaskRowV1) -> dict:
    return {
        "taskId": r.taskId,
        "output": r.output,
        "dependencies": list(r.dependencies),
        "prerequisites": list(r.prerequisites),
        "tests": list(r.tests),
        "evidenceIds": list(r.evidenceIds),
        "status": r.status,
    }


def task_row_digest(r: TaskQualificationTaskRowV1) -> "Digest":
    """Compute the task row digest (plain SHA-256 of canonical PF-JCS wire).

    Used for AllowedCloseoutPatchV1.resultingTaskRowDigest (§5). The resulting
    row is the row with status flipped to "done" (§6 "diff(C,D) paths/resulting
    row 与 AllowedCloseoutPatchV1 exact").
    """
    wire = task_row_to_wire(r)
    return plain_sha256_digest(canonical_pf_jcs(wire))


def freeze_package_ref_to_wire(r: TaskFreezePackageRefV1) -> dict:
    return {
        "taskId": r.taskId,
        "digest": digest_to_wire(r.digest),
    }


def gate_to_wire(g: TaskQualificationGateV1) -> dict:
    return {
        "gateId": g.gateId,
        "taskId": g.taskId,
        "testIds": list(g.testIds),
        "evidence": [evidence_ref_to_wire(e) for e in g.evidence],
        "commandPolicy": content_ref_to_wire(g.commandPolicy),
        "eligibleStage0Handoff": content_ref_to_wire(g.eligibleStage0Handoff),
        "sessionContainment": content_ref_to_wire(g.sessionContainment),
        "freshness": content_ref_to_wire(g.freshness),
        "privateScan": content_ref_to_wire(g.privateScan),
        "revocationSnapshot": content_ref_to_wire(g.revocationSnapshot),
    }


def dependency_to_wire(d: DependencyCompletionRefV1) -> dict:
    if isinstance(d, BootstrapTaskReceiptDependencyV1):
        return {
            "kind": d.kind,
            "taskId": d.taskId,
            "completionCommit": d.completionCommit,
            "authorityPolicy": content_ref_to_wire(d.authorityPolicy),
            "objectDigest": digest_to_wire(d.objectDigest),
            "objectBytesHex": d.objectBytesHex,
            "signatures": [approval_signature_to_wire(s) for s in d.signatures],
        }
    if isinstance(d, GovernanceBootstrapReceiptDependencyV1):
        return {
            "kind": d.kind,
            "taskId": d.taskId,
            "ruling": content_ref_to_wire(d.ruling),
            "completionCommit": d.completionCommit,
            "authorityPolicy": content_ref_to_wire(d.authorityPolicy),
            "objectDigest": digest_to_wire(d.objectDigest),
            "objectBytesHex": d.objectBytesHex,
            "signatures": [approval_signature_to_wire(s) for s in d.signatures],
        }
    if isinstance(d, TaskQualificationDependencyV1):
        return {
            "kind": d.kind,
            "taskId": d.taskId,
            "completionCommit": d.completionCommit,
            "authorityPolicy": content_ref_to_wire(d.authorityPolicy),
            "receipt": completion_receipt_ref_to_wire(d.receipt),
            "objectDigest": digest_to_wire(d.objectDigest),
            "objectBytesHex": d.objectBytesHex,
            "signatures": [approval_signature_to_wire(s) for s in d.signatures],
        }
    _reject("dependency_to_wire: unknown dependency type")


def allowed_closeout_patch_to_wire(p: AllowedCloseoutPatchV1) -> dict:
    return {
        "schema": p.schema,
        "id": p.id,
        "version": p.version,
        "taskId": p.taskId,
        "preCloseCandidate": candidate_identity_to_wire(p.preCloseCandidate),
        "allowedPaths": list(p.allowedPaths),
        "semanticFileSetDigest": digest_to_wire(p.semanticFileSetDigest),
        "resultingTaskRowDigest": digest_to_wire(p.resultingTaskRowDigest),
    }


def task_qualification_to_wire(q: TaskQualificationV1) -> dict:
    return {
        "schema": q.schema,
        "id": q.id,
        "version": q.version,
        "taskId": q.taskId,
        "preCloseCandidate": candidate_identity_to_wire(q.preCloseCandidate),
        "taskRow": task_row_to_wire(q.taskRow),
        "freezePackage": freeze_package_ref_to_wire(q.freezePackage),
        "gates": [gate_to_wire(g) for g in q.gates],
        "dependencies": [dependency_to_wire(d) for d in q.dependencies],
        "verifier": verifier_identity_to_wire(q.verifier),
        "authorityPolicy": content_ref_to_wire(q.authorityPolicy),
        "allowedCloseoutPatch": content_ref_to_wire(q.allowedCloseoutPatch),
        "independentReviews": [
            independent_review_ref_to_wire(r) for r in q.independentReviews
        ],
        "signatures": [approval_signature_to_wire(s) for s in q.signatures],
    }


def task_completion_receipt_to_wire(r: TaskCompletionReceiptV1) -> dict:
    return {
        "schema": r.schema,
        "id": r.id,
        "version": r.version,
        "taskId": r.taskId,
        "preCloseCandidate": candidate_identity_to_wire(r.preCloseCandidate),
        "closeoutCandidate": candidate_identity_to_wire(r.closeoutCandidate),
        "qualification": task_qualification_ref_to_wire(r.qualification),
        "allowedCloseoutPatch": content_ref_to_wire(r.allowedCloseoutPatch),
        "closeoutDiffDigest": digest_to_wire(r.closeoutDiffDigest),
        "authorityPolicy": content_ref_to_wire(r.authorityPolicy),
        "revocationSnapshot": content_ref_to_wire(r.revocationSnapshot),
        "issuedAt": r.issuedAt,
        "signatures": [approval_signature_to_wire(s) for s in r.signatures],
    }


def d0_10_bootstrap_gate_to_wire(g: D0_10BootstrapGateV1) -> dict:
    return {
        "gateId": g.gateId,
        "taskId": g.taskId,
        "testIds": list(g.testIds),
        "evidence": [evidence_ref_to_wire(e) for e in g.evidence],
        "commandPolicy": content_ref_to_wire(g.commandPolicy),
        "eligibleStage0Handoff": content_ref_to_wire(g.eligibleStage0Handoff),
        "sessionContainment": content_ref_to_wire(g.sessionContainment),
        "freshness": content_ref_to_wire(g.freshness),
        "privateScan": content_ref_to_wire(g.privateScan),
        "revocationSnapshot": content_ref_to_wire(g.revocationSnapshot),
    }


def d0_10_bootstrap_approval_to_wire(a: D0_10BootstrapApprovalV1) -> dict:
    return {
        "schema": a.schema,
        "id": a.id,
        "version": a.version,
        "taskId": a.taskId,
        "ruling": normative_document_ref_to_wire(a.ruling),
        "preCloseCandidate": candidate_identity_to_wire(a.preCloseCandidate),
        "taskRow": task_row_to_wire(a.taskRow),
        "freezePackage": freeze_package_ref_to_wire(a.freezePackage),
        "verifier": verifier_identity_to_wire(a.verifier),
        "protectedConsumer": verifier_identity_to_wire(a.protectedConsumer),
        "verifierClosureDigest": digest_to_wire(a.verifierClosureDigest),
        "consumerClosureDigest": digest_to_wire(a.consumerClosureDigest),
        "tstDocSubprofile": a.tstDocSubprofile,
        "bootstrapGate": d0_10_bootstrap_gate_to_wire(a.bootstrapGate),
        "d0_07Bridge": dependency_to_wire(a.d0_07Bridge),
        "allowedCloseoutPatch": content_ref_to_wire(a.allowedCloseoutPatch),
        "independentReviews": [
            independent_review_ref_to_wire(r) for r in a.independentReviews
        ],
        "authorityPolicy": content_ref_to_wire(a.authorityPolicy),
        "signatures": [approval_signature_to_wire(s) for s in a.signatures],
    }


def d0_10_bootstrap_receipt_to_wire(r: D0_10BootstrapReceiptV1) -> dict:
    return {
        "schema": r.schema,
        "id": r.id,
        "version": r.version,
        "taskId": r.taskId,
        "ruling": normative_document_ref_to_wire(r.ruling),
        "preCloseCandidate": candidate_identity_to_wire(r.preCloseCandidate),
        "closeoutCandidate": candidate_identity_to_wire(r.closeoutCandidate),
        "approvalDigest": digest_to_wire(r.approvalDigest),
        "allowedCloseoutPatch": content_ref_to_wire(r.allowedCloseoutPatch),
        "closeoutDiffDigest": digest_to_wire(r.closeoutDiffDigest),
        "authorityPolicy": content_ref_to_wire(r.authorityPolicy),
        "revocationSnapshot": content_ref_to_wire(r.revocationSnapshot),
        "ledgerGrade": r.ledgerGrade,
        "purpose": r.purpose,
        "issuedAt": r.issuedAt,
        "signatures": [approval_signature_to_wire(s) for s in r.signatures],
    }


def verified_task_qualification_to_wire(v) -> dict:
    """§8.1 VerifiedTaskQualificationV1 wire form for the pure projection."""
    return {
        "taskId": v.taskId,
        "preCloseCandidate": candidate_identity_to_wire(v.preCloseCandidate),
        "qualification": task_qualification_to_wire(v.qualification),
        "allowedCloseoutPatch": allowed_closeout_patch_to_wire(
            v.allowedCloseoutPatch),
        "authorityPolicy": content_ref_to_wire(v.authorityPolicy),
        "verificationInstant": v.verificationInstant,
        "authorityClass": v.authorityClass,
    }


def verified_task_completion_to_wire(v) -> dict:
    """§8.1 VerifiedTaskCompletionV1 wire form for the pure projection.

    The ``qualification`` field is projected as the full ``TaskQualificationV1``
    when the verifier embedded it, or as the receipt's
    ``TaskQualificationRefV1`` when the verifier only had the receipt subject
    (receipt operations do not carry the qualification object in the bundle
    per §8.2 role table, so the verifier stores ``None`` for the full object
    and the receiver rebinds via the receipt's qualification ref). The
    ``authorityClass`` is the pure verifier's result (``production-content-
    verified`` or ``fixture-non-authoritative``); the protected adapter never
    rewrites it.
    """
    if v.qualification is not None:
        qualification_wire = task_qualification_to_wire(v.qualification)
    else:
        # Receipt operations: project the receipt's qualification ref so the
        # pure projection binds the exact (taskId, id, digest) triple the
        # verifier validated, without inventing a full qualification object.
        qualification_wire = task_qualification_ref_to_wire(v.receipt.qualification)
    return {
        "taskId": v.taskId,
        "preCloseCandidate": candidate_identity_to_wire(v.preCloseCandidate),
        "closeoutCandidate": candidate_identity_to_wire(v.closeoutCandidate),
        "qualification": qualification_wire,
        "receipt": task_completion_receipt_to_wire(v.receipt),
        "closeoutDiffDigest": digest_to_wire(v.closeoutDiffDigest),
        "authorityPolicy": content_ref_to_wire(v.authorityPolicy),
        "verificationInstant": v.verificationInstant,
        "authorityClass": v.authorityClass,
    }


def verified_d0_10_bootstrap_approval_to_wire(v) -> dict:
    """§8.1 VerifiedD0_10BootstrapApprovalV1 wire form for the pure projection."""
    return {
        "taskId": v.taskId,
        "preCloseCandidate": candidate_identity_to_wire(v.preCloseCandidate),
        "approvalDigest": digest_to_wire(v.approvalDigest),
        "allowedCloseoutPatch": allowed_closeout_patch_to_wire(
            v.allowedCloseoutPatch),
        "authorityPolicy": content_ref_to_wire(v.authorityPolicy),
        "verificationInstant": v.verificationInstant,
        "authorityClass": v.authorityClass,
    }


def verified_d0_10_bootstrap_completion_to_wire(v) -> dict:
    """§8.1 VerifiedD0_10BootstrapCompletionV1 wire form for the pure projection."""
    return {
        "taskId": v.taskId,
        "preCloseCandidate": candidate_identity_to_wire(v.preCloseCandidate),
        "closeoutCandidate": candidate_identity_to_wire(v.closeoutCandidate),
        "approvalDigest": digest_to_wire(v.approvalDigest),
        "receiptDigest": digest_to_wire(v.receiptDigest),
        "closeoutDiffDigest": digest_to_wire(v.closeoutDiffDigest),
        "authorityPolicy": content_ref_to_wire(v.authorityPolicy),
        "verificationInstant": v.verificationInstant,
        "authorityClass": v.authorityClass,
    }


# ---------------------------------------------------------------------------
# §8.3 Archive (POSIX.1-1988 ustar) projection
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ArchiveEntry:
    path: str  # path after prefix stripping (relative POSIX)
    mode: int  # low 9 bits
    is_executable: bool
    content: bytes


@dataclass(frozen=True)
class ArchiveProjection:
    archiveSha256: Digest
    entries: Tuple[ArchiveEntry, ...]  # sorted by path UTF-8
    path_map: dict  # path -> ArchiveEntry


def _reject_archive(where, detail):
    _reject(f"{where}: {detail}")


def parse_ustar_archive(raw: bytes, task_id: str, where: str) -> ArchiveProjection:
    """Parse a POSIX.1-1988 ustar archive, enforcing §8.3 constraints.

    Only regular files under ``<taskId-lower>/`` prefix are accepted. PAX/GNU
    extensions, symlinks, hardlinks, devices, sparse files, and duplicate paths
    are rejected. uname/gname/uid/gid/mtime must be zero or ignored.
    """
    if len(raw) > MAX_ARCHIVE_BYTES:
        _reject_archive(where, f"archive exceeds {MAX_ARCHIVE_BYTES} bytes")
    if len(raw) % 512 != 0:
        _reject_archive(where, "archive length must be multiple of 512")
    if len(raw) == 0:
        _reject_archive(where, "archive empty")

    prefix_expected = f"{task_id.lower()}/"
    entries = []
    offset = 0
    seen_paths = set()
    while offset + 512 <= len(raw):
        header = raw[offset:offset + 512]
        # Check for end-of-archive (two zero blocks)
        if header == b"\x00" * 512:
            # Verify remaining is all zero
            remaining = raw[offset + 512:]
            if remaining != b"\x00" * len(remaining):
                _reject_archive(where, "trailing non-zero after end marker")
            break
        # Parse name (100 bytes)
        name = header[0:100].rstrip(b"\x00")
        # Parse mode (8 bytes octal)
        mode_field = header[100:108].rstrip(b"\x00 ")
        # Parse size (12 bytes octal)
        size_field = header[124:136].rstrip(b"\x00 ")
        # typeflag (1 byte at offset 156)
        typeflag = header[156:157]
        # magic (6 bytes at offset 257) — ustar\0
        magic = header[257:263]
        # prefix (155 bytes at offset 345)
        prefix = header[345:500].rstrip(b"\x00")

        # Validate magic
        if magic != b"ustar\x00":
            _reject_archive(where, f"magic must be 'ustar\\0', got {magic!r}")

        # Parse size
        try:
            size = int(size_field, 8) if size_field else 0
        except ValueError:
            _reject_archive(where, "size must be octal")
        if size < 0:
            _reject_archive(where, "size negative")

        # Validate typeflag — only regular file (0 or NUL).
        # PAX global/local headers (typeflag 'g'/'x') from `git archive` are
        # metadata-only and skipped per §8.3 "git archive --format=tar subset".
        # Directory entries (typeflag '5') from `git archive --prefix=` are
        # prefix placeholders and skipped (only regular files are accepted).
        if typeflag in (b"g", b"x"):
            # Skip PAX header block(s) — advance past header + content
            try:
                pax_size = int(size_field, 8) if size_field else 0
            except ValueError:
                _reject_archive(where, "pax size must be octal")
            content_blocks = (pax_size + 511) // 512
            offset = offset + 512 + content_blocks * 512
            continue
        if typeflag == b"5":
            # Directory entry — skip (only regular files accepted)
            offset = offset + 512
            continue
        if typeflag not in (b"0", b"\x00"):
            _reject_archive(where, f"typeflag must be '0' or NUL, got {typeflag!r}")

        # Parse mode
        try:
            mode = int(mode_field, 8) if mode_field else 0
        except ValueError:
            _reject_archive(where, "mode must be octal")
        mode_low = mode & 0o7777
        if mode_low not in (0o644, 0o755):
            _reject_archive(where, f"mode must be 0644 or 0755, got {oct(mode_low)}")

        # Build full path
        if prefix:
            full_name = prefix + b"/" + name
        else:
            full_name = name
        try:
            full_path = full_name.decode("utf-8")
        except UnicodeDecodeError:
            _reject_archive(where, "path must be UTF-8")

        # Strip task prefix
        if not full_path.startswith(prefix_expected):
            _reject_archive(where, f"path must start with '{prefix_expected}'")
        rel_path = full_path[len(prefix_expected):]

        # Validate relative path — no empty, ., .., absolute, backslash, NUL
        if not rel_path:
            _reject_archive(where, "path empty after prefix strip")
        if "\x00" in rel_path:
            _reject_archive(where, "path contains NUL")
        if "\\" in rel_path:
            _reject_archive(where, "path contains backslash")
        if rel_path.startswith("/"):
            _reject_archive(where, "path absolute")
        components = rel_path.split("/")
        for comp in components:
            if comp == "" or comp == "." or comp == "..":
                _reject_archive(where, f"path component '{comp}' forbidden")

        # Read content
        content_offset = offset + 512
        if content_offset + size > len(raw):
            _reject_archive(where, "content exceeds archive")
        content = raw[content_offset:content_offset + size]

        # Check for duplicate/casefold collision
        if rel_path in seen_paths:
            _reject_archive(where, f"duplicate path '{rel_path}'")
        seen_paths.add(rel_path)

        entries.append(ArchiveEntry(
            path=rel_path,
            mode=mode_low,
            is_executable=(mode_low == 0o755),
            content=content,
        ))

        # Advance to next block (content padded to 512)
        content_blocks = (size + 511) // 512
        offset = content_offset + content_blocks * 512

    if len(entries) > MAX_ARCHIVE_PATHS:
        _reject_archive(where, f"too many paths ({MAX_ARCHIVE_PATHS})")

    # Sort by path UTF-8
    entries.sort(key=lambda e: e.path.encode("utf-8"))

    # Verify no casefold collision
    lower_paths = set()
    for e in entries:
        low = e.path.lower()
        if low in lower_paths:
            _reject_archive(where, f"casefold collision on '{e.path}'")
        lower_paths.add(low)

    # Verify expanded size
    total = sum(len(e.content) for e in entries)
    if total > MAX_ARCHIVE_EXPANDED:
        _reject_archive(where, f"expanded exceeds {MAX_ARCHIVE_EXPANDED}")

    path_map = {e.path: e for e in entries}
    return ArchiveProjection(
        archiveSha256=plain_sha256_digest(raw),
        entries=tuple(entries),
        path_map=path_map,
    )


# ---------------------------------------------------------------------------
# §8.3 Git object (SHA-1) projection
# ---------------------------------------------------------------------------

def git_sha1_object(obj_type: str, content: bytes) -> str:
    """Compute the Git SHA-1 object ID for a blob/tree/commit."""
    header = f"{obj_type} {len(content)}\x00".encode("ascii")
    return hashlib.sha1(header + content).hexdigest()


def git_blob_sha1(content: bytes) -> str:
    return git_sha1_object("blob", content)


def git_tree_sha1(entries: list) -> str:
    """Compute the Git tree SHA-1 from a list of (mode, name, blob_sha1_hex).

    entries must be sorted by Git bytewise name order. mode is the Git mode
    string (e.g. "100644", "100755", "40000" for tree).
    """
    payload = b""
    for mode, name, blob_hex in entries:
        payload += mode.encode("ascii") + b" " + name.encode("utf-8") + b"\x00" + bytes.fromhex(blob_hex)
    return git_sha1_object("tree", payload)


def build_git_tree_from_archive(archive: ArchiveProjection) -> str:
    """Build the Git tree SHA-1 from an archive projection.

    Builds a flat tree (no subdirectories) if all paths have no slash, or a
    nested tree structure if paths contain slashes. Entries are sorted by Git
    bytewise name order.
    """
    # Build nested tree structure
    tree_map = {}  # dir path -> list of (mode, name, hex)
    for entry in archive.entries:
        mode = "100755" if entry.is_executable else "100644"
        blob_hex = git_blob_sha1(entry.content)
        # Split path into components and build nested trees
        components = entry.path.split("/")
        # Navigate/create tree structure
        current = tree_map
        for i, comp in enumerate(components[:-1]):
            if comp not in current:
                current[comp] = {}
            current = current[comp]
        leaf_name = components[-1]
        if "__entries__" not in current:
            current["__entries__"] = []
        current["__entries__"].append((mode, leaf_name, blob_hex))

    def build_tree(tree_dict: dict) -> str:
        entries = []
        for name, val in tree_dict.items():
            if name == "__entries__":
                continue
            subtree_sha = build_tree(val)
            entries.append(("40000", name, subtree_sha))
        if "__entries__" in tree_dict:
            entries.extend(tree_dict["__entries__"])
        # Sort by Git bytewise name order: tree entries are sorted by name
        # but trees (mode 40000) sort as if they have a trailing '/'
        def sort_key(e):
            mode, name, _ = e
            if mode == "40000":
                return name + "/"
            return name
        entries.sort(key=sort_key)
        return git_tree_sha1(entries)

    return build_tree(tree_map)


@dataclass(frozen=True)
class GitCommitObject:
    commit_sha: str
    tree: str
    parents: Tuple[str, ...]
    payload: bytes  # raw commit payload (without header)


def parse_git_commit_object(raw: bytes, where: str) -> GitCommitObject:
    """Parse a raw Git commit payload and recompute its SHA-1."""
    # Recompute commit SHA-1
    commit_sha = git_sha1_object("commit", raw)
    # Parse tree and parents from commit payload
    text = raw.decode("utf-8", errors="strict")
    lines = text.split("\n")
    tree = None
    parents = []
    for line in lines:
        if line.startswith("tree "):
            tree = line[5:].strip()
        elif line.startswith("parent "):
            parents.append(line[7:].strip())
        elif line == "":
            break  # header ends at first blank line
    if tree is None:
        _reject(f"{where}: commit missing tree")
    return GitCommitObject(
        commit_sha=commit_sha,
        tree=tree,
        parents=tuple(parents),
        payload=raw,
    )


def verify_candidate_identity_from_archive(
    archive: ArchiveProjection,
    commit_obj: GitCommitObject,
    expected: CandidateIdentity,
    where: str,
) -> None:
    """Verify that a candidate archive + commit object match the expected identity."""
    # Verify archiveSha256
    if archive.archiveSha256.bytes != expected.archiveDigest.bytes:
        _reject(f"{where}: archiveSha256 mismatch")
    # Verify treeObjectId matches archive tree
    computed_tree = build_git_tree_from_archive(archive)
    if computed_tree != expected.treeObjectId:
        _reject(f"{where}: treeObjectId mismatch (computed {computed_tree}, expected {expected.treeObjectId})")
    # Verify commit tree matches
    if commit_obj.tree != expected.treeObjectId:
        _reject(f"{where}: commit tree mismatch")
    # Verify commit SHA-1 matches
    if commit_obj.commit_sha != expected.commit:
        _reject(f"{where}: commit SHA-1 mismatch (computed {commit_obj.commit_sha}, expected {expected.commit})")


# ---------------------------------------------------------------------------
# §8.3 Ancestry graph
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class AncestryGraph:
    """Ancestry graph from consuming candidate C to freezeCommit and to each
    direct dependency completionCommit.

    Members are keyed by commit SHA-1. Each target must have at least one path,
    and every commit's parents must be recursively represented.
    """
    members: dict  # commit_sha -> GitCommitObject
    targets: dict  # target_commit -> source_role (e.g. "candidate-commit-object")


def build_ancestry_graph(
    candidate_commit: str,
    freeze_commit: str,
    dependency_commits: dict,  # task_id -> completion_commit
    commit_objects: dict,  # commit_sha -> GitCommitObject
    where: str,
) -> AncestryGraph:
    """Build the ancestry graph per §8.3.

    The graph is the union of all parent-edge closure paths from consuming C
    to freezeCommit and from C to each direct dependency completionCommit.
    BFS starts from C (consuming candidate) and follows parent edges. Every
    target (freezeCommit and each dependency completionCommit) must be
    reachable from C along parent edges — i.e. each target must be an ancestor
    of C. Every commit's parents must be recursively represented. Any missing
    parent, unreachable target, or extra commit not in the union is rejected.
    """
    targets = {
        candidate_commit: "candidate-commit-object",
        freeze_commit: "freeze-commit",
    }
    for task_id, dep_commit in dependency_commits.items():
        targets[dep_commit] = f"dependency-commit-object/{task_id}"

    # BFS from C (consuming candidate) following parent edges. The reachable
    # set is the union of all parent-edge closure paths from C. Every target
    # must be reachable from C (i.e. an ancestor of C).
    if candidate_commit not in commit_objects:
        _reject(f"{where}: ancestry missing candidate commit {candidate_commit}")
    reachable = set()
    to_visit = [candidate_commit]
    while to_visit:
        sha = to_visit.pop()
        if sha in reachable:
            continue
        if sha not in commit_objects:
            _reject(f"{where}: ancestry missing commit {sha}")
        reachable.add(sha)
        for parent in commit_objects[sha].parents:
            if parent not in reachable:
                to_visit.append(parent)

    # Every target must be reachable from C (an ancestor of C). C itself is a
    # trivial target (reachable as the BFS root). freezeCommit and dependency
    # completionCommits must be ancestors of C.
    target_set = set(targets.keys())
    unreachable_targets = target_set - reachable
    if unreachable_targets:
        _reject(
            f"{where}: ancestry target(s) unreachable from candidate C: "
            f"{sorted(unreachable_targets)}")

    members = {sha: commit_objects[sha] for sha in reachable}
    return AncestryGraph(members=members, targets=targets)


def verify_ancestry_membership(
    graph: AncestryGraph,
    extra_commits: dict,  # commit_sha -> GitCommitObject (for ancestry-commit/* members)
    where: str,
) -> None:
    """Verify that no extra commits are present and all target commits are present."""
    # Check that extra_commits only contains commits in graph.members
    for sha in extra_commits:
        if sha not in graph.members:
            _reject(f"{where}: extra ancestry commit {sha} not in graph")
    # Check that target commits are not duplicated as ancestry-commit/*
    for target_sha, role in graph.targets.items():
        if target_sha in extra_commits:
            _reject(f"{where}: target commit {target_sha} duplicated as ancestry-commit")