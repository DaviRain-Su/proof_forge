#!/usr/bin/env python3
"""Pure, dependency-free validation primitives for bootstrap task objects.

This module deliberately performs no filesystem, socket, environment, or CLI
I/O.  It can establish content-level facts only; it cannot authenticate a
Stage-0 handoff or close a bootstrap task by itself.
"""

from __future__ import annotations

import hashlib
import json
import posixpath
import re
import unicodedata
from datetime import date
from dataclasses import dataclass
from typing import Any, NoReturn, Tuple, Union


BOOTSTRAP_REJECTION = "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED"
MAX_INPUT_BYTES = 4 * 1024 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_DOCUMENT_LINE_BYTES = 65_536
MAX_DOCUMENT_LINES = 100_000
MAX_BOOTSTRAP_EVIDENCE_OBJECTS = 6 * 4096
MAX_BOOTSTRAP_REVIEW_REPORTS = 6 * 256
MAX_REVIEW_REPORT_BYTES = 1024 * 1024
MAX_BOOTSTRAP_REVIEW_REPORT_TOTAL_BYTES = 16 * 1024 * 1024

DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}")
GIT_OBJECT_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")
SCHEMA_RE = re.compile(
    r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
    r"(?:\.[a-z][a-z0-9]*(?:-[a-z0-9]+)*)+"
)
PROFILE_ID_RE = re.compile(r"[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*")
SAFE_ID_RE = re.compile(
    r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?"
)
TASK_ID_RE = re.compile(r"TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*")
TEST_ID_RE = re.compile(r"TST-[A-Z0-9]+(?:-[A-Z0-9]+)*")
EVIDENCE_ID_RE = re.compile(r"EV-[0-9]{8}-[0-9]{4}")
BTV_ID_RE = re.compile(r"BTV-[0-9]{8}-[0-9]{4}")
SEMVER_RE = re.compile(
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)"
    r"(?:-(?:"
    r"(?:0|[1-9][0-9]*)|"
    r"(?:[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r")(?:\.(?:"
    r"(?:0|[1-9][0-9]*)|"
    r"(?:[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


class Rejected(Exception):
    """Stable public rejection; internal details never grant authority."""

    def __init__(self, code: str = BOOTSTRAP_REJECTION, detail: str = "") -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _reject(detail: str) -> NoReturn:
    raise Rejected(BOOTSTRAP_REJECTION, detail)


@dataclass(frozen=True)
class Digest:
    algorithm: str
    bytes: bytes


@dataclass(frozen=True)
class ContentRef:
    schema: str
    id: str
    version: str
    digest: Digest


@dataclass(frozen=True)
class CandidateIdentity:
    commit: str
    treeObjectId: str
    archiveDigest: Digest
    digest: Digest


@dataclass(frozen=True)
class ApprovalRuleV1:
    requiredRoles: Tuple[str, ...]
    minimumDistinctSigners: int


@dataclass(frozen=True)
class BootstrapAuthorityPrincipalV1:
    principalId: str
    keyId: str
    publicKey: bytes
    roles: Tuple[str, ...]


@dataclass(frozen=True)
class BootstrapAuthorityTaskRuleV1:
    taskId: str
    rule: ApprovalRuleV1


@dataclass(frozen=True)
class BootstrapAuthorityVerifierV1:
    id: str
    executableDigest: Digest
    receiptKeyId: str
    receiptPublicKey: bytes


@dataclass(frozen=True)
class BootstrapAuthorityPolicyV1:
    schema: str
    id: str
    version: str
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...]
    taskRules: Tuple[BootstrapAuthorityTaskRuleV1, ...]
    requiredTestSetRule: ApprovalRuleV1
    formalCatalogRule: ApprovalRuleV1
    bootstrapSetRule: ApprovalRuleV1
    sessionContainmentRule: ApprovalRuleV1
    freshnessAuthorityRule: ApprovalRuleV1
    privateScanRule: ApprovalRuleV1
    privateScanPolicy: ContentRef
    revocationSnapshotRule: ApprovalRuleV1
    authorityStoreService: ContentRef
    verifier: BootstrapAuthorityVerifierV1


@dataclass(frozen=True)
class ApprovalSignatureV1:
    keyId: str
    algorithm: str
    signature: bytes


@dataclass(frozen=True)
class NormativeDocumentRefV1:
    id: str
    contentDigest: Digest
    status: str
    reviewCommit: str
    reviewLink: str
    approvedAt: str
    approvers: Tuple[str, ...]


@dataclass(frozen=True)
class RequiredTestSetV1:
    schema: str
    id: str
    version: str
    phase5Document: NormativeDocumentRefV1
    authorityPolicy: ContentRef
    requiredTestIds: Tuple[str, ...]
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class EvidenceRef:
    id: str
    digest: Digest


@dataclass(frozen=True)
class TaskApprovalRefV1:
    taskId: str
    digest: Digest


@dataclass(frozen=True)
class BootstrapTaskVerifierReceiptRefV1:
    taskId: str
    id: str
    digest: Digest


@dataclass(frozen=True)
class IndependentReviewRefV1:
    keyId: str
    role: str
    reviewCommit: str
    reviewLink: str
    reportDigest: Digest
    decision: str


@dataclass(frozen=True)
class TaskApprovalV1:
    schema: str
    taskId: str
    candidate: CandidateIdentity
    taskBreakdown: NormativeDocumentRefV1
    requiredTestSet: ContentRef
    testIds: Tuple[str, ...]
    evidence: Tuple[EvidenceRef, ...]
    dependencyCompletions: Tuple[BootstrapTaskVerifierReceiptRefV1, ...]
    prerequisiteDocuments: Tuple[NormativeDocumentRefV1, ...]
    authorityPolicy: ContentRef
    stage0Handoff: ContentRef
    independentReviews: Tuple[IndependentReviewRefV1, ...]
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class Stage0ChannelV1:
    role: str
    fd: int
    transport: str
    access: str
    bindingDigest: Digest


@dataclass(frozen=True)
class EligibleStage0TcbV1:
    stage0VerifierDigest: Digest
    bootstrapVerifierDigest: Digest
    continuationDigest: Digest
    formalFinalizerDigest: Digest


@dataclass(frozen=True)
class EligibleStage0EnvironmentV1:
    mode: str
    home: str
    path: str
    lcAll: str
    tz: str
    network: str


@dataclass(frozen=True)
class EligibleStage0HandoffV1:
    schema: str
    id: str
    version: str
    runId: str
    nonce: bytes
    candidate: CandidateIdentity
    authorityPolicy: ContentRef
    authorityStoreService: ContentRef
    hostObservation: ContentRef
    hostProfile: ContentRef
    eligible: bool
    tcb: EligibleStage0TcbV1
    environment: EligibleStage0EnvironmentV1
    channels: Tuple[Stage0ChannelV1, ...]
    pathnameReopen: bool
    fallback: str


@dataclass(frozen=True)
class BootstrapTaskVerifierReceiptV1:
    schema: str
    id: str
    taskId: str
    candidate: CandidateIdentity
    authorityPolicy: ContentRef
    requiredTestSet: ContentRef
    taskApproval: TaskApprovalRefV1
    stage0Handoff: ContentRef
    dependencyCompletions: Tuple[BootstrapTaskVerifierReceiptRefV1, ...]
    verifierDigest: Digest
    result: str
    signature: ApprovalSignatureV1


@dataclass(frozen=True)
class BootstrapLedgerSubjectV1:
    id: str
    taskId: str
    testIds: Tuple[str, ...]
    grade: str
    result: str


@dataclass(frozen=True)
class BootstrapDocumentSnapshotV1:
    id: str
    path: str
    bytes: bytes


@dataclass(frozen=True)
class Phase4TaskRowV1:
    taskId: str
    dependencies: Tuple[str, ...]
    prerequisiteDocumentIds: Tuple[str, ...]
    testIds: Tuple[str, ...]
    evidenceIds: Tuple[str, ...]


@dataclass(frozen=True)
class Phase4SnapshotContentV1:
    document: NormativeDocumentRefV1
    bootstrapTaskRows: Tuple[Phase4TaskRowV1, ...]


@dataclass(frozen=True)
class Phase5SnapshotContentV1:
    document: NormativeDocumentRefV1
    requiredTestIds: Tuple[str, ...]


@dataclass(frozen=True)
class _RequiredTestSetPreflightV1:
    policy: BootstrapAuthorityPolicyV1
    requiredTestSet: RequiredTestSetV1
    requiredTestSetRef: ContentRef
    signatureMessage: bytes


@dataclass(frozen=True)
class _TaskApprovalPreflightV1:
    taskApproval: TaskApprovalV1
    signatureMessage: bytes
    signedBytes: bytes


@dataclass(frozen=True)
class _EligibleStage0HandoffPreflightV1:
    handoff: EligibleStage0HandoffV1
    handoffRef: ContentRef


@dataclass(frozen=True)
class _BootstrapTaskVerifierReceiptPreflightV1:
    receipt: BootstrapTaskVerifierReceiptV1
    signatureMessage: bytes
    signedBytes: bytes


@dataclass(frozen=True)
class _BootstrapTaskSignedPreflightV1:
    approval: _TaskApprovalPreflightV1
    receipt: _BootstrapTaskVerifierReceiptPreflightV1


@dataclass(frozen=True)
class _BootstrapTaskObjectPreflightV1:
    approval: _TaskApprovalPreflightV1
    receipt: _BootstrapTaskVerifierReceiptPreflightV1
    handoff: _EligibleStage0HandoffPreflightV1


@dataclass(frozen=True)
class _VerifiedBootstrapTaskObjectV1:
    approval: TaskApprovalV1
    approvalRef: TaskApprovalRefV1
    receipt: BootstrapTaskVerifierReceiptV1
    receiptRef: BootstrapTaskVerifierReceiptRefV1
    stage0Handoff: ContentRef


@dataclass(frozen=True)
class _BootstrapTaskObjectGraphV1:
    root: _VerifiedBootstrapTaskObjectV1
    dependencies: Tuple[_VerifiedBootstrapTaskObjectV1, ...]


@dataclass(frozen=True)
class BootstrapTaskRowSubjectV1:
    taskId: str
    dependencies: Tuple[str, ...]
    prerequisites: Tuple[object, ...]
    testIds: Tuple[str, ...]
    evidenceIds: Tuple[str, ...]


@dataclass(frozen=True)
class BootstrapTaskSubjectV1:
    candidate: CandidateIdentity
    rootTaskId: str
    taskRows: Tuple[BootstrapTaskRowSubjectV1, ...]
    evidenceRows: Tuple[BootstrapLedgerSubjectV1, ...]
    documents: Tuple[BootstrapDocumentSnapshotV1, ...]


@dataclass(frozen=True)
class DependencyTaskObjectV1:
    approvalBytes: bytes
    receiptBytes: bytes
    stage0HandoffBytes: bytes


@dataclass(frozen=True)
class ReviewReportObjectV1:
    digest: Digest
    bytes: bytes


@dataclass(frozen=True)
class BootstrapTaskObjectSetV1:
    authorityPolicyBytes: bytes
    stage0HandoffBytes: bytes
    requiredTestSetBytes: bytes
    taskApprovalBytes: bytes
    taskReceiptBytes: bytes
    dependencyObjects: Tuple[DependencyTaskObjectV1, ...]
    evidenceObjectBytes: Tuple[bytes, ...]
    reviewReports: Tuple[ReviewReportObjectV1, ...]


@dataclass(frozen=True)
class ObjectVerifiedV1:
    taskId: str
    candidate: CandidateIdentity
    authorityPolicy: ContentRef
    requiredTestSet: ContentRef
    taskApproval: object
    taskReceipt: object
    stage0Handoff: ContentRef
    dependencyReceipts: Tuple[object, ...]
    evidence: Tuple[object, ...]


def _require_exact_keys(value: object, fields: Tuple[str, ...], where: str) -> dict:
    if type(value) is not dict:
        _reject(f"{where} must be an object")
    assert isinstance(value, dict)
    if tuple(value.keys()) != fields and set(value.keys()) != set(fields):
        _reject(f"{where} must contain exactly {fields}")
    if set(value.keys()) != set(fields):
        _reject(f"{where} must contain exactly {fields}")
    return value


def _require_ascii_text(value: object, pattern: re.Pattern, where: str,
                        maximum: int) -> str:
    if type(value) is not str or not value.isascii():
        _reject(f"{where} must be ASCII text")
    assert isinstance(value, str)
    if not 1 <= len(value.encode("ascii")) <= maximum or pattern.fullmatch(value) is None:
        _reject(f"{where} has an invalid format")
    return value


def _require_semver(value: object, where: str) -> str:
    version = _require_ascii_text(value, SEMVER_RE, where, 255)
    core = version.split("+", 1)[0].split("-", 1)[0]
    maximum_u64 = "18446744073709551615"
    for component in core.split("."):
        if (len(component) > len(maximum_u64)
                or (len(component) == len(maximum_u64)
                    and component > maximum_u64)):
            _reject(f"{where} core component exceeds UInt64")
    return version


def _require_json_key(key: object) -> str:
    if type(key) is not str:
        _reject("JSON object key must be text")
    assert isinstance(key, str)
    if (not key or len(key) > 256
            or any(ord(character) < 0x21 or ord(character) > 0x7E
                   for character in key)):
        _reject("JSON object key is outside the PF ASCII-graphic profile")
    return key


def _validate_json_tree(value: object) -> None:
    nodes = 0
    stack = [(value, 0)]
    while stack:
        current, depth = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES or depth > MAX_JSON_DEPTH:
            _reject("JSON resource limit exceeded")
        if current is None or type(current) is bool:
            continue
        if type(current) is int:
            if abs(current) > MAX_SAFE_INTEGER:
                _reject("JSON integer exceeds safe range")
            continue
        if type(current) is float:
            _reject("floating-point JSON is forbidden")
        if type(current) is str:
            assert isinstance(current, str)
            if ("\x00" in current
                    or any(0xD800 <= ord(character) <= 0xDFFF for character in current)
                    or len(current.encode("utf-8")) > MAX_STRING_BYTES):
                _reject("JSON string is outside the PF profile")
            continue
        if type(current) is list:
            assert isinstance(current, list)
            for item in reversed(current):
                stack.append((item, depth + 1))
            continue
        if type(current) is dict:
            assert isinstance(current, dict)
            for key, item in current.items():
                _require_json_key(key)
                stack.append((item, depth + 1))
            continue
        _reject("value is not in the JSON data model")


def canonical_pf_jcs(value: object) -> bytes:
    """Encode the restricted integer-only/ASCII-key PF JCS profile."""
    _validate_json_tree(value)
    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            check_circular=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError) as error:
        _reject(f"cannot encode canonical JSON: {error}")
    if len(encoded) > MAX_INPUT_BYTES:
        _reject("canonical JSON exceeds the input limit")
    return encoded


def _object_pairs(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        checked = _require_json_key(key)
        if checked in result:
            _reject("duplicate JSON object key")
        result[checked] = value
    return result


def _parse_int(text: str) -> int:
    digits = text[1:] if text.startswith("-") else text
    safe_limit = str(MAX_SAFE_INTEGER)
    if (len(digits) > len(safe_limit)
            or (len(digits) == len(safe_limit) and digits > safe_limit)):
        _reject("JSON integer exceeds safe range")
    value = int(text, 10)
    return value


def _reject_number(text: str) -> NoReturn:
    _reject(f"forbidden JSON number: {text}")


def decode_canonical_pf_jcs(data: bytes) -> object:
    """Decode only exact canonical PF-JCS bytes."""
    if type(data) is not bytes or len(data) > MAX_INPUT_BYTES:
        _reject("PF-JCS input must be bounded bytes")
    if data.startswith(b"\xef\xbb\xbf"):
        _reject("UTF-8 BOM is forbidden")
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeError:
        _reject("PF-JCS input is not UTF-8")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_object_pairs,
            parse_int=_parse_int,
            parse_float=_reject_number,
            parse_constant=_reject_number,
        )
    except Rejected:
        raise
    except (json.JSONDecodeError, RecursionError, ValueError):
        _reject("invalid JSON")
    _validate_json_tree(value)
    if canonical_pf_jcs(value) != data:
        _reject("JSON bytes are not canonical PF-JCS")
    return value


def parse_digest(value: object) -> Digest:
    if type(value) is not str or DIGEST_RE.fullmatch(value) is None:
        _reject("Digest must be sha256:<64 lowercase hex>")
    assert isinstance(value, str)
    return Digest("sha256", bytes.fromhex(value[7:]))


def parse_content_ref(value: object) -> ContentRef:
    obj = _require_exact_keys(value, ("schema", "id", "version", "digest"),
                              "ContentRef")
    schema = _require_ascii_text(obj["schema"], SCHEMA_RE, "ContentRef.schema", 127)
    identifier = _require_ascii_text(obj["id"], PROFILE_ID_RE, "ContentRef.id", 127)
    version = _require_semver(obj["version"], "ContentRef.version")
    return ContentRef(schema, identifier, version, parse_digest(obj["digest"]))


def parse_candidate_identity(value: object) -> CandidateIdentity:
    obj = _require_exact_keys(
        value,
        ("commit", "treeObjectId", "archiveDigest", "digest"),
        "CandidateIdentity",
    )
    commit = _require_ascii_text(obj["commit"], GIT_OBJECT_RE,
                                 "CandidateIdentity.commit", 64)
    tree = _require_ascii_text(obj["treeObjectId"], GIT_OBJECT_RE,
                               "CandidateIdentity.treeObjectId", 64)
    archive = parse_digest(obj["archiveDigest"])
    claimed = parse_digest(obj["digest"])
    statement = {
        "commit": commit,
        "treeObjectId": tree,
        "archiveDigest": obj["archiveDigest"],
    }
    expected = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + canonical_pf_jcs(statement)
    ).digest()
    if claimed.bytes != expected:
        _reject("CandidateIdentity digest mismatch")
    return CandidateIdentity(commit, tree, archive, claimed)


# RFC 8032 Ed25519 constants.  Verification handles public data only; this
# pure-Python implementation is not constant-time and must never be used to sign.
_P = 2**255 - 19
_L = 2**252 + 27742317777372353535851937790883648493
_D = 37095705934669439343138083508754565189542113879843219016388785533085940283555
_SQRT_M1 = 19681161376707505956807079304988542015446066515923890162744021073123829784752
_BX = 15112221349535400772501151409588531511454012693041857206046113283949847762202
_BY = 46316835694926478169428394003475163141307993866256225615783033603165251855960
_IDENTITY = (0, 1, 1, 0)
_BASE = (_BX, _BY, 1, (_BX * _BY) % _P)


def _point_add(left: tuple, right: tuple) -> tuple:
    x1, y1, z1, t1 = left
    x2, y2, z2, t2 = right
    a = ((y1 - x1) * (y2 - x2)) % _P
    b = ((y1 + x1) * (y2 + x2)) % _P
    c = (2 * _D * t1 * t2) % _P
    d = (2 * z1 * z2) % _P
    e = (b - a) % _P
    f = (d - c) % _P
    g = (d + c) % _P
    h = (b + a) % _P
    return ((e * f) % _P, (g * h) % _P, (f * g) % _P, (e * h) % _P)


def _point_equal(left: tuple, right: tuple) -> bool:
    return (
        (left[0] * right[2] - right[0] * left[2]) % _P == 0
        and (left[1] * right[2] - right[1] * left[2]) % _P == 0
    )


def _scalar_multiply(scalar: int, point: tuple) -> tuple:
    result = _IDENTITY
    addend = point
    while scalar:
        if scalar & 1:
            result = _point_add(result, addend)
        addend = _point_add(addend, addend)
        scalar >>= 1
    return result


def _encode_point(point: tuple) -> bytes:
    inverse = pow(point[2], _P - 2, _P)
    x = (point[0] * inverse) % _P
    y = (point[1] * inverse) % _P
    encoded = bytearray(y.to_bytes(32, "little"))
    encoded[31] |= (x & 1) << 7
    return bytes(encoded)


def _decode_point(encoded: bytes) -> Union[tuple, None]:
    if type(encoded) is not bytes or len(encoded) != 32:
        return None
    integer = int.from_bytes(encoded, "little")
    sign = integer >> 255
    y = integer & ((1 << 255) - 1)
    if y >= _P:
        return None
    y_squared = (y * y) % _P
    numerator = (y_squared - 1) % _P
    denominator = (_D * y_squared + 1) % _P
    if denominator == 0:
        return None
    x_squared = (numerator * pow(denominator, _P - 2, _P)) % _P
    x = pow(x_squared, (_P + 3) // 8, _P)
    if (x * x - x_squared) % _P != 0:
        x = (x * _SQRT_M1) % _P
    if (x * x - x_squared) % _P != 0:
        return None
    if x == 0 and sign == 1:
        return None
    if (x & 1) != sign:
        x = _P - x
    point = (x, y, 1, (x * y) % _P)
    if _encode_point(point) != encoded:
        return None
    if _point_equal(point, _IDENTITY):
        return None
    if _point_equal(_scalar_multiply(8, point), _IDENTITY):
        return None
    if not _point_equal(_scalar_multiply(_L, point), _IDENTITY):
        return None
    return point


def verify_ed25519(public_key: bytes, message: bytes, signature: bytes) -> bool:
    """Strict Pure Ed25519 verification with prime-subgroup inputs."""
    if (type(public_key) is not bytes or type(message) is not bytes
            or type(signature) is not bytes
            or len(public_key) != 32 or len(signature) != 64):
        return False
    encoded_r = signature[:32]
    scalar_s = int.from_bytes(signature[32:], "little")
    if scalar_s >= _L:
        return False
    public_point = _decode_point(public_key)
    r_point = _decode_point(encoded_r)
    if public_point is None or r_point is None:
        return False
    challenge = int.from_bytes(
        hashlib.sha512(encoded_r + public_key + message).digest(), "little"
    ) % _L
    left = _scalar_multiply(scalar_s, _BASE)
    right = _point_add(r_point, _scalar_multiply(challenge, public_point))
    return _point_equal(left, right)


_APPROVAL_ROLES = ("architecture", "quality", "security", "release")
_APPROVAL_ROLE_INDEX = {
    role: index for index, role in enumerate(_APPROVAL_ROLES)
}
_POLICY_FIELDS = (
    "schema",
    "id",
    "version",
    "principals",
    "taskRules",
    "requiredTestSetRule",
    "formalCatalogRule",
    "bootstrapSetRule",
    "sessionContainmentRule",
    "freshnessAuthorityRule",
    "privateScanRule",
    "privateScanPolicy",
    "revocationSnapshotRule",
    "authorityStoreService",
    "verifier",
)
_TASK_RULE_MINIMA = (
    ("TASK-D0-01", ("architecture", "quality"), 2),
    ("TASK-D0-02", ("architecture", "quality"), 2),
    ("TASK-D0-03", ("quality", "security"), 2),
    ("TASK-D0-04", ("quality", "security", "release"), 3),
    ("TASK-D0-05", ("quality", "security"), 2),
    ("TASK-D0-06", ("architecture", "quality"), 2),
)
_D0_TASK_IDS = tuple(item[0] for item in _TASK_RULE_MINIMA)
_NAMED_RULE_MINIMA = (
    ("requiredTestSetRule", ("quality", "security"), 2),
    ("formalCatalogRule", ("quality", "security"), 2),
    ("bootstrapSetRule", ("quality", "security", "release"), 3),
    ("sessionContainmentRule", ("quality", "security"), 2),
    ("freshnessAuthorityRule", ("quality", "release"), 2),
    ("privateScanRule", ("quality", "security"), 2),
    ("revocationSnapshotRule", ("security", "release"), 2),
)
_ED25519_PUBLIC_KEY_RE = re.compile(r"[0-9a-f]{64}")
_ED25519_SIGNATURE_RE = re.compile(r"[0-9a-f]{128}")
_LOWERCASE_32_BYTE_HEX_RE = re.compile(r"[0-9a-f]{64}")
_LOWERCASE_COMMIT_RE = re.compile(r"[0-9a-f]{40}")
_GREGORIAN_DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
_DEVELOPMENT_A0_TEST_IDS = tuple(
    f"TST-A0-{index:03d}" for index in range(1, 21)
)
_PHASE4_DOCUMENT_PATH = "docs/04-task-breakdown.md"
_PHASE4_D0_HEADING = "## Milestone D0：文档与独立工程"
_PHASE4_D1_HEADING = "## Milestone D1：语言前端"
_PHASE4_TABLE_HEADER = (
    "| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |"
)
_PHASE4_TABLE_DELIMITER = "|---|---|---|---|---|---|---|"
_PHASE4_ALL_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 8))
_PHASE4_TASK_STATUSES = frozenset({"pending", "in_progress", "blocked", "done"})
_PHASE5_DOCUMENT_PATH = "docs/05-test-spec.md"
_PHASE5_CATALOG_HEADING = "## 完整 Test ID Catalog"
_PHASE5_DENOMINATOR_HEADING = "### Phase 1 required-set 分母"
_PHASE5_CATALOG_HEADER = "| ID | 测试对象 |"
_PHASE5_CATALOG_DELIMITER = "|---|---|"
_PHASE5_FRONTMATTER_FIELDS = frozenset({
    "id",
    "title",
    "status",
    "owner",
    "updated",
    "normative",
    "approvers",
    "approvedAt",
    "reviewCommit",
    "reviewLink",
    "openFindings",
})
_REQUIRED_TEST_SET_FIELDS = (
    "schema",
    "id",
    "version",
    "phase5Document",
    "authorityPolicy",
    "requiredTestIds",
    "signatures",
)
_NORMATIVE_DOCUMENT_FIELDS = (
    "id",
    "contentDigest",
    "status",
    "reviewCommit",
    "reviewLink",
    "approvedAt",
    "approvers",
)
_APPROVAL_SIGNATURE_FIELDS = ("keyId", "algorithm", "signature")
_EVIDENCE_REF_FIELDS = ("id", "digest")
_TASK_RECEIPT_REF_FIELDS = ("taskId", "id", "digest")
_INDEPENDENT_REVIEW_FIELDS = (
    "keyId",
    "role",
    "reviewCommit",
    "reviewLink",
    "reportDigest",
    "decision",
)
_TASK_APPROVAL_FIELDS = (
    "schema",
    "taskId",
    "candidate",
    "taskBreakdown",
    "requiredTestSet",
    "testIds",
    "evidence",
    "dependencyCompletions",
    "prerequisiteDocuments",
    "authorityPolicy",
    "stage0Handoff",
    "independentReviews",
    "signatures",
)
_TASK_APPROVAL_REF_FIELDS = ("taskId", "digest")
_STAGE0_CHANNEL_FIELDS = (
    "role",
    "fd",
    "transport",
    "access",
    "bindingDigest",
)
_ELIGIBLE_STAGE0_TCB_FIELDS = (
    "stage0VerifierDigest",
    "bootstrapVerifierDigest",
    "continuationDigest",
    "formalFinalizerDigest",
)
_ELIGIBLE_STAGE0_ENVIRONMENT_FIELDS = (
    "mode",
    "home",
    "path",
    "lcAll",
    "tz",
    "network",
)
_ELIGIBLE_STAGE0_HANDOFF_FIELDS = (
    "schema",
    "id",
    "version",
    "runId",
    "nonce",
    "candidate",
    "authorityPolicy",
    "authorityStoreService",
    "hostObservation",
    "hostProfile",
    "eligible",
    "tcb",
    "environment",
    "channels",
    "pathnameReopen",
    "fallback",
)
_BOOTSTRAP_TASK_RECEIPT_FIELDS = (
    "schema",
    "id",
    "taskId",
    "candidate",
    "authorityPolicy",
    "requiredTestSet",
    "taskApproval",
    "stage0Handoff",
    "dependencyCompletions",
    "verifierDigest",
    "result",
    "signature",
)
_STAGE0_CHANNEL_SPECS = (
    ("authority-policy", "regular-file", "read-only"),
    ("authority-store", "authenticated-stream", "request-response"),
    ("candidate-archive", "regular-file", "read-only"),
    ("evidence-root", "regular-file", "read-only"),
)


def _require_safe_id(value: object, where: str) -> str:
    return _require_ascii_text(value, SAFE_ID_RE, where, 256)


def _parse_approval_roles(value: object, where: str) -> Tuple[str, ...]:
    if type(value) is not list or not value:
        _reject(f"{where} must be a non-empty array")
    assert isinstance(value, list)
    roles = tuple(value)
    if any(type(role) is not str or role not in _APPROVAL_ROLE_INDEX
           for role in roles):
        _reject(f"{where} contains an unknown approval role")
    expected = tuple(sorted(roles, key=_APPROVAL_ROLE_INDEX.__getitem__))
    if roles != expected or len(set(roles)) != len(roles):
        _reject(f"{where} must be unique and ordered by ApprovalRoleV1")
    return roles


def _parse_approval_rule(value: object, where: str) -> ApprovalRuleV1:
    obj = _require_exact_keys(
        value,
        ("requiredRoles", "minimumDistinctSigners"),
        where,
    )
    roles = _parse_approval_roles(obj["requiredRoles"], f"{where}.requiredRoles")
    minimum = obj["minimumDistinctSigners"]
    if type(minimum) is not int or not 1 <= minimum <= 0xFFFFFFFF:
        _reject(f"{where}.minimumDistinctSigners must be a non-zero u32")
    assert isinstance(minimum, int)
    return ApprovalRuleV1(roles, minimum)


def _decode_ed25519_public_key(value: object, where: str) -> bytes:
    if type(value) is not str or _ED25519_PUBLIC_KEY_RE.fullmatch(value) is None:
        _reject(f"{where} must be a 32-byte lowercase-hex Ed25519 public key")
    assert isinstance(value, str)
    return bytes.fromhex(value)


def _require_prime_subgroup_public_key(encoded: bytes, where: str) -> bytes:
    if _decode_point(encoded) is None:
        _reject(f"{where} is not a canonical prime-subgroup Ed25519 public key")
    return encoded


def _parse_authority_principals(value: object) -> Tuple[BootstrapAuthorityPrincipalV1, ...]:
    if type(value) is not list or not 1 <= len(value) <= 256:
        _reject("BootstrapAuthorityPolicyV1.principals count must be 1..256")
    assert isinstance(value, list)
    principals = []
    for index, entry in enumerate(value):
        where = f"BootstrapAuthorityPolicyV1.principals[{index}]"
        obj = _require_exact_keys(
            entry, ("principalId", "keyId", "publicKey", "roles"), where
        )
        principals.append(BootstrapAuthorityPrincipalV1(
            _require_safe_id(obj["principalId"], f"{where}.principalId"),
            _require_safe_id(obj["keyId"], f"{where}.keyId"),
            _decode_ed25519_public_key(obj["publicKey"], f"{where}.publicKey"),
            _parse_approval_roles(obj["roles"], f"{where}.roles"),
        ))
    result = tuple(principals)
    key_ids = tuple(principal.keyId for principal in result)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _reject("BootstrapAuthorityPolicyV1.principals must have unique ascending keyId")
    public_keys = tuple(principal.publicKey for principal in result)
    if len(set(public_keys)) != len(public_keys):
        _reject("BootstrapAuthorityPolicyV1 principal publicKey values must be unique")
    for index, principal in enumerate(result):
        _require_prime_subgroup_public_key(
            principal.publicKey,
            f"BootstrapAuthorityPolicyV1.principals[{index}].publicKey",
        )
    return result


def _parse_authority_task_rules(value: object) -> Tuple[BootstrapAuthorityTaskRuleV1, ...]:
    if type(value) is not list:
        _reject("BootstrapAuthorityPolicyV1.taskRules must be an array")
    assert isinstance(value, list)
    rules = []
    for index, entry in enumerate(value):
        where = f"BootstrapAuthorityPolicyV1.taskRules[{index}]"
        obj = _require_exact_keys(entry, ("taskId", "rule"), where)
        task_id = obj["taskId"]
        if type(task_id) is not str or TASK_ID_RE.fullmatch(task_id) is None:
            _reject(f"{where}.taskId is invalid")
        rules.append(BootstrapAuthorityTaskRuleV1(
            task_id,
            _parse_approval_rule(obj["rule"], f"{where}.rule"),
        ))
    result = tuple(rules)
    expected_ids = tuple(item[0] for item in _TASK_RULE_MINIMA)
    if tuple(rule.taskId for rule in result) != expected_ids:
        _reject("BootstrapAuthorityPolicyV1.taskRules must be exact TASK-D0-01..06 order")
    return result


def _parse_authority_verifier(value: object) -> BootstrapAuthorityVerifierV1:
    where = "BootstrapAuthorityPolicyV1.verifier"
    obj = _require_exact_keys(
        value,
        ("id", "executableDigest", "receiptKeyId", "receiptPublicKey"),
        where,
    )
    return BootstrapAuthorityVerifierV1(
        _require_safe_id(obj["id"], f"{where}.id"),
        parse_digest(obj["executableDigest"]),
        _require_safe_id(obj["receiptKeyId"], f"{where}.receiptKeyId"),
        _decode_ed25519_public_key(
            obj["receiptPublicKey"], f"{where}.receiptPublicKey"
        ),
    )


def _require_rule_hard_minimum(
    rule: ApprovalRuleV1,
    required_roles: Tuple[str, ...],
    minimum_signers: int,
    where: str,
) -> None:
    if not set(required_roles).issubset(rule.requiredRoles):
        _reject(f"{where} weakens the required ApprovalRoleV1 set")
    if rule.minimumDistinctSigners < minimum_signers:
        _reject(f"{where} weakens minimumDistinctSigners")


def _require_rule_satisfiable(
    rule: ApprovalRuleV1,
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    where: str,
) -> None:
    distinct_principals = {principal.principalId for principal in principals}
    if rule.minimumDistinctSigners > len(distinct_principals):
        _reject(f"{where} cannot be satisfied by distinct principalId values")
    for role in rule.requiredRoles:
        if not any(role in principal.roles for principal in principals):
            _reject(f"{where} requires uncovered role {role}")


def parse_bootstrap_authority_policy(
    data: bytes,
) -> Tuple[BootstrapAuthorityPolicyV1, ContentRef]:
    """Parse and validate a canonical external bootstrap authority policy."""
    decoded = decode_canonical_pf_jcs(data)
    obj = _require_exact_keys(
        decoded, _POLICY_FIELDS, "BootstrapAuthorityPolicyV1"
    )
    if obj["schema"] != "proof-forge.bootstrap-authority-policy.v1":
        _reject("BootstrapAuthorityPolicyV1.schema is not v1")
    identifier = _require_ascii_text(
        obj["id"], PROFILE_ID_RE, "BootstrapAuthorityPolicyV1.id", 127
    )
    version = _require_semver(
        obj["version"], "BootstrapAuthorityPolicyV1.version"
    )
    principals = _parse_authority_principals(obj["principals"])
    task_rules = _parse_authority_task_rules(obj["taskRules"])
    named_rules = {
        field: _parse_approval_rule(
            obj[field], f"BootstrapAuthorityPolicyV1.{field}"
        )
        for field, _, _ in _NAMED_RULE_MINIMA
    }
    verifier = _parse_authority_verifier(obj["verifier"])

    principal_key_ids = {principal.keyId for principal in principals}
    principal_public_keys = {principal.publicKey for principal in principals}
    if verifier.receiptKeyId in principal_key_ids:
        _reject("verifier receiptKeyId collides with a principal keyId")
    if verifier.receiptPublicKey in principal_public_keys:
        _reject("verifier receiptPublicKey collides with a principal publicKey")
    _require_prime_subgroup_public_key(
        verifier.receiptPublicKey,
        "BootstrapAuthorityPolicyV1.verifier.receiptPublicKey",
    )

    for task_rule, (_, required_roles, minimum) in zip(
        task_rules, _TASK_RULE_MINIMA
    ):
        where = f"BootstrapAuthorityPolicyV1.taskRules[{task_rule.taskId}]"
        _require_rule_hard_minimum(
            task_rule.rule, required_roles, minimum, where
        )
        _require_rule_satisfiable(task_rule.rule, principals, where)
    for field, required_roles, minimum in _NAMED_RULE_MINIMA:
        rule = named_rules[field]
        where = f"BootstrapAuthorityPolicyV1.{field}"
        _require_rule_hard_minimum(rule, required_roles, minimum, where)
        _require_rule_satisfiable(rule, principals, where)

    private_scan_policy = parse_content_ref(obj["privateScanPolicy"])
    authority_store_service = parse_content_ref(obj["authorityStoreService"])
    if authority_store_service.schema != "proof-forge.authority-store-service.v1":
        _reject("authorityStoreService must reference the v1 authority store schema")

    policy = BootstrapAuthorityPolicyV1(
        "proof-forge.bootstrap-authority-policy.v1",
        identifier,
        version,
        principals,
        task_rules,
        named_rules["requiredTestSetRule"],
        named_rules["formalCatalogRule"],
        named_rules["bootstrapSetRule"],
        named_rules["sessionContainmentRule"],
        named_rules["freshnessAuthorityRule"],
        named_rules["privateScanRule"],
        private_scan_policy,
        named_rules["revocationSnapshotRule"],
        authority_store_service,
        verifier,
    )
    digest = Digest(
        "sha256",
        hashlib.sha256(b"pf.bootstrap-authority-policy.v1\x00" + data).digest(),
    )
    return policy, ContentRef(policy.schema, policy.id, policy.version, digest)


def _parse_review_link(value: object, where: str) -> str:
    if type(value) is not str:
        _reject(f"{where} must be text")
    assert isinstance(value, str)
    try:
        encoded = value.encode("utf-8")
    except UnicodeError:
        _reject(f"{where} must be valid UTF-8 text")
    if not 1 <= len(encoded) <= 4096:
        _reject(f"{where} must be 1..4096 UTF-8 bytes")
    if value[:8].lower() != "https://":
        _reject(f"{where} must use the https scheme")
    if any(unicodedata.category(character) == "Cc" for character in value):
        _reject(f"{where} must not contain control characters")
    return value


def _parse_gregorian_date(value: object, where: str) -> str:
    if type(value) is not str or _GREGORIAN_DATE_RE.fullmatch(value) is None:
        _reject(f"{where} must be Gregorian YYYY-MM-DD")
    assert isinstance(value, str)
    try:
        date.fromisoformat(value)
    except ValueError:
        _reject(f"{where} must be a real Gregorian date")
    return value


def _parse_normative_document_ref(
    value: object,
    where: str,
) -> NormativeDocumentRefV1:
    obj = _require_exact_keys(value, _NORMATIVE_DOCUMENT_FIELDS, where)
    identifier = _require_safe_id(obj["id"], f"{where}.id")
    content_digest = parse_digest(obj["contentDigest"])
    if obj["status"] != "accepted":
        _reject(f"{where}.status must be accepted")
    review_commit = obj["reviewCommit"]
    if (type(review_commit) is not str
            or _LOWERCASE_COMMIT_RE.fullmatch(review_commit) is None):
        _reject(f"{where}.reviewCommit must be 40 lowercase hex digits")
    assert isinstance(review_commit, str)
    review_link = _parse_review_link(obj["reviewLink"], f"{where}.reviewLink")
    approved_at = _parse_gregorian_date(
        obj["approvedAt"], f"{where}.approvedAt"
    )
    approver_values = obj["approvers"]
    if type(approver_values) is not list or not 1 <= len(approver_values) <= 256:
        _reject(f"{where}.approvers count must be 1..256")
    assert isinstance(approver_values, list)
    approvers = tuple(
        _require_safe_id(approver, f"{where}.approvers[{index}]")
        for index, approver in enumerate(approver_values)
    )
    if (approvers != tuple(sorted(approvers))
            or len(set(approvers)) != len(approvers)):
        _reject(f"{where}.approvers must be unique ascending ASCII safe-id")
    return NormativeDocumentRefV1(
        identifier,
        content_digest,
        "accepted",
        review_commit,
        review_link,
        approved_at,
        approvers,
    )


def _validate_document_snapshot_envelope(
    snapshot: BootstrapDocumentSnapshotV1,
    expected_id: str,
    expected_path: str,
) -> bytes:
    where = f"{expected_id} snapshot"
    if type(snapshot) is not BootstrapDocumentSnapshotV1:
        _reject(f"{where} must be exact BootstrapDocumentSnapshotV1")
    if (type(snapshot.id) is not str
            or type(snapshot.path) is not str
            or snapshot.id != expected_id
            or snapshot.path != expected_path):
        _reject(f"{where} identity/path is not canonical")
    data = snapshot.bytes
    if type(data) is not bytes or not 1 <= len(data) <= MAX_INPUT_BYTES:
        _reject(f"{where} bytes must be exact bytes with length 1..4 MiB")
    if data.startswith(b"\xef\xbb\xbf") or b"\x00" in data or b"\r" in data:
        _reject(f"{where} contains a forbidden byte sequence")
    if not data.endswith(b"\n"):
        _reject(f"{where} must end with LF")
    line_count = data.count(b"\n")
    if not 1 <= line_count <= MAX_DOCUMENT_LINES:
        _reject(f"{where} line count is outside 1..100000")
    raw_lines = data[:-1].split(b"\n")
    if any(len(line) > MAX_DOCUMENT_LINE_BYTES for line in raw_lines):
        _reject(f"{where} line exceeds 65536 UTF-8 bytes")
    try:
        data.decode("utf-8", errors="strict")
    except UnicodeError:
        _reject(f"{where} is not strict UTF-8")
    return data


def _parse_accepted_frontmatter(
    data: bytes,
    expected_id: str,
) -> tuple[dict[str, str], int]:
    if not data.startswith(b"---\n"):
        _reject(
            f"{expected_id} snapshot lacks the exact opening frontmatter delimiter"
        )
    closing = data.find(b"\n---\n", 4)
    if closing < 0:
        _reject(
            f"{expected_id} snapshot lacks the exact closing frontmatter delimiter"
        )
    try:
        frontmatter_text = data[4:closing].decode("utf-8", errors="strict")
    except UnicodeError:
        _reject(f"{expected_id} frontmatter is not UTF-8")
    metadata: dict[str, str] = {}
    for line_number, line in enumerate(frontmatter_text.split("\n"), start=2):
        if line == "":
            continue
        separator = line.find(": ")
        if separator <= 0:
            _reject(
                f"{expected_id} frontmatter line {line_number} is not key: value"
            )
        key = line[:separator]
        value = line[separator + 2:]
        if (not value or key != key.strip() or value != value.strip()
                or key in metadata):
            _reject(
                f"{expected_id} frontmatter line {line_number} is noncanonical"
            )
        metadata[key] = value
    if set(metadata) != _PHASE5_FRONTMATTER_FIELDS:
        _reject(f"{expected_id} frontmatter field set is not exact")
    if (metadata["id"] != expected_id
            or metadata["status"] != "accepted"
            or metadata["normative"] != "true"
            or metadata["openFindings"] != "none"):
        _reject(
            f"{expected_id} frontmatter is not an accepted normative document"
        )
    _parse_gregorian_date(metadata["updated"], f"{expected_id}.updated")
    _parse_gregorian_date(metadata["approvedAt"], f"{expected_id}.approvedAt")
    if _LOWERCASE_COMMIT_RE.fullmatch(metadata["reviewCommit"]) is None:
        _reject(f"{expected_id}.reviewCommit must be 40 lowercase hex digits")
    _parse_review_link(metadata["reviewLink"], f"{expected_id}.reviewLink")
    return metadata, closing + len(b"\n---\n")


def _parse_accepted_approvers(value: str, where: str) -> Tuple[str, ...]:
    approver_values = tuple(value.split(", "))
    if (not value or ", ".join(approver_values) != value
            or not 1 <= len(approver_values) <= 256):
        _reject(f"{where} must use the exact bounded ', ' grammar")
    approvers = tuple(
        _require_safe_id(approver, f"{where}[{index}]")
        for index, approver in enumerate(approver_values)
    )
    if (approvers != tuple(sorted(approvers))
            or len(set(approvers)) != len(approvers)):
        _reject(f"{where} must be unique ascending ASCII safe-id")
    return approvers


def _parse_phase5_frontmatter(
    data: bytes,
) -> tuple[dict[str, str], int]:
    return _parse_accepted_frontmatter(data, "PHASE-5")


def _parse_phase5_approvers(value: str) -> Tuple[str, ...]:
    return _parse_accepted_approvers(value, "PHASE-5.approvers")


def _parse_phase5_catalog(body: bytes) -> Tuple[str, ...]:
    try:
        text = body.decode("utf-8", errors="strict")
    except UnicodeError:
        _reject("PHASE-5 body is not UTF-8")
    lines = text[:-1].split("\n") if text else []
    heading_indices: list[int] = []
    denominator_indices: list[int] = []
    header_indices: list[int] = []
    delimiter_indices: list[int] = []
    for index, line in enumerate(lines):
        if line == _PHASE5_CATALOG_HEADING:
            heading_indices.append(index)
        if line == _PHASE5_DENOMINATOR_HEADING:
            denominator_indices.append(index)
        if line == _PHASE5_CATALOG_HEADER:
            header_indices.append(index)
        if line == _PHASE5_CATALOG_DELIMITER:
            delimiter_indices.append(index)
    if (len(heading_indices) != 1 or len(denominator_indices) != 1
            or len(header_indices) != 1 or len(delimiter_indices) != 1):
        _reject("PHASE-5 catalog reserved lines must each occur exactly once")
    heading = heading_indices[0]
    denominator = denominator_indices[0]
    header = header_indices[0]
    delimiter = delimiter_indices[0]
    if not heading < header < delimiter < denominator or delimiter != header + 1:
        _reject("PHASE-5 catalog section/table order is invalid")
    for line in lines[heading + 1:denominator]:
        if (line == "###" or line.startswith("### ")
                or line.startswith("###\t")):
            _reject("PHASE-5 denominator heading is not the first H3")
    for line in lines[heading + 1:header]:
        if line.startswith("|") or line.endswith("|"):
            _reject("PHASE-5 catalog has a table-like line before its header")

    catalog_ids: list[str] = []
    table_ended = False
    for line in lines[delimiter + 1:denominator]:
        if line == "":
            table_ended = True
            continue
        if table_ended:
            _reject("PHASE-5 catalog table must be contiguous")
        if not line.startswith("| ") or not line.endswith(" |"):
            _reject("PHASE-5 catalog row is malformed")
        cells = line[2:-2].split(" | ")
        if len(cells) != 2:
            _reject("PHASE-5 catalog row must contain exactly two cells")
        test_id, description = cells
        if test_id != test_id.strip() or description != description.strip():
            _reject("PHASE-5 catalog cells contain outer whitespace")
        parsed_test_id = _require_ascii_text(
            test_id, TEST_ID_RE, "PHASE-5 catalog TestId", 127
        )
        try:
            encoded_description = description.encode("utf-8")
        except UnicodeError:
            _reject("PHASE-5 catalog description is not UTF-8")
        if (not 1 <= len(encoded_description) <= 4096 or "|" in description
                or any(unicodedata.category(character) == "Cc"
                       for character in description)):
            _reject("PHASE-5 catalog description is invalid")
        catalog_ids.append(parsed_test_id)
        if len(catalog_ids) > 4116:
            _reject("PHASE-5 catalog row count exceeds 4116")
    if not catalog_ids or len(set(catalog_ids)) != len(catalog_ids):
        _reject("PHASE-5 catalog TestIds must be non-empty and unique")
    development_ids = {
        test_id for test_id in catalog_ids if test_id.startswith("TST-A0-")
    }
    if development_ids != set(_DEVELOPMENT_A0_TEST_IDS):
        _reject("PHASE-5 catalog must contain exact TST-A0-001..020")
    required_test_ids = tuple(sorted(
        test_id for test_id in catalog_ids
        if not test_id.startswith("TST-A0-")
    ))
    if not 1 <= len(required_test_ids) <= 4096:
        _reject("PHASE-5 required catalog denominator count must be 1..4096")
    if len(catalog_ids) != len(_DEVELOPMENT_A0_TEST_IDS) + len(required_test_ids):
        _reject("PHASE-5 catalog contains a forbidden A0-prefixed TestId")
    return required_test_ids


def _parse_phase4_list_cell(
    value: str,
    kind: str,
    *,
    nonempty: bool,
) -> Tuple[str, ...]:
    where = f"PHASE-4 {kind} cell"
    if value == "—":
        if nonempty:
            _reject(f"{where} must be non-empty")
        return ()
    tokens = tuple(value.split(", "))
    if (not value or not tokens or ", ".join(tokens) != value
            or any(not token or token != token.strip() or "`" in token
                   for token in tokens)):
        _reject(f"{where} does not use the exact canonical list grammar")

    if kind == "Dependencies":
        parsed = tuple(
            _require_ascii_text(
                token,
                TASK_ID_RE,
                f"{where}[{index}]",
                127,
            )
            for index, token in enumerate(tokens)
        )
        if any(task_id not in _PHASE4_ALL_TASK_IDS for task_id in parsed):
            _reject(f"{where} references a task outside TASK-D0-01..07")
    elif kind == "Prerequisites":
        document_ids = []
        for index, token in enumerate(tokens):
            if token.count("@") != 1 or not token.endswith("@accepted"):
                _reject(
                    f"{where}[{index}] must be exact <safe-id>@accepted"
                )
            document_ids.append(_require_safe_id(
                token[:-len("@accepted")],
                f"{where}[{index}].documentId",
            ))
        parsed = tuple(document_ids)
    elif kind == "Tests":
        parsed = tuple(
            _require_ascii_text(
                token,
                TEST_ID_RE,
                f"{where}[{index}]",
                127,
            )
            for index, token in enumerate(tokens)
        )
    elif kind == "Evidence":
        parsed = tuple(
            _parse_compact_gregorian_id(
                token,
                EVIDENCE_ID_RE,
                3,
                f"{where}[{index}]",
            )
            for index, token in enumerate(tokens)
        )
    else:
        _reject("PHASE-4 parser contains an unknown list-cell kind")

    if parsed != tuple(sorted(parsed)) or len(set(parsed)) != len(parsed):
        _reject(f"{where} must contain unique ascending ASCII IDs")
    return parsed


def _parse_phase4_task_table(body: bytes) -> Tuple[Phase4TaskRowV1, ...]:
    try:
        text = body.decode("utf-8", errors="strict")
    except UnicodeError:
        _reject("PHASE-4 body is not UTF-8")
    lines = text[:-1].split("\n") if text else []
    reserved = (
        (_PHASE4_D0_HEADING, "D0 heading"),
        (_PHASE4_D1_HEADING, "D1 boundary"),
        (_PHASE4_TABLE_HEADER, "table header"),
        (_PHASE4_TABLE_DELIMITER, "table delimiter"),
    )
    label_by_line = {exact_line: label for exact_line, label in reserved}
    matches_by_label = {label: [] for _, label in reserved}
    for index, line in enumerate(lines):
        label = label_by_line.get(line)
        if label is not None:
            matches_by_label[label].append(index)
    positions: dict[str, int] = {}
    for _, label in reserved:
        matches = matches_by_label[label]
        if len(matches) != 1:
            _reject(f"PHASE-4 {label} must occur exactly once")
        positions[label] = matches[0]

    d0_index = positions["D0 heading"]
    d1_index = positions["D1 boundary"]
    header_index = positions["table header"]
    delimiter_index = positions["table delimiter"]
    if (not d0_index < header_index < delimiter_index < d1_index
            or delimiter_index != header_index + 1):
        _reject("PHASE-4 D0 table section order is invalid")
    if any(line != "" for line in lines[d0_index + 1:header_index]):
        _reject("PHASE-4 permits only blank lines before the D0 table")

    row_start = delimiter_index + 1
    row_end = row_start + len(_PHASE4_ALL_TASK_IDS)
    if row_end > len(lines) or row_end > d1_index:
        _reject("PHASE-4 D0 table lacks seven contiguous rows")
    row_lines = lines[row_start:row_end]
    if any(line == "" for line in row_lines):
        _reject("PHASE-4 D0 table rows must be contiguous")
    if any(line != "" for line in lines[row_end:d1_index]):
        _reject("PHASE-4 permits only blank lines after the D0 table")

    rows = []
    for row_index, line in enumerate(row_lines):
        where = f"PHASE-4 D0 row {row_index + 1}"
        if not line.startswith("| ") or not line.endswith(" |"):
            _reject(f"{where} is malformed")
        cells = line[2:-2].split(" | ")
        if len(cells) != 7:
            _reject(f"{where} must contain exactly seven cells")
        if any(cell != cell.strip() for cell in cells):
            _reject(f"{where} cells contain outer whitespace")
        (
            task_id,
            description,
            dependencies_cell,
            prerequisites_cell,
            tests_cell,
            evidence_cell,
            status,
        ) = cells
        expected_task_id = _PHASE4_ALL_TASK_IDS[row_index]
        if task_id != expected_task_id:
            _reject("PHASE-4 task rows are not the exact TASK-D0-01..07 sequence")
        try:
            encoded_description = description.encode("utf-8")
        except UnicodeError:
            _reject(f"{where} description is not UTF-8")
        if (not 1 <= len(encoded_description) <= 4096
                or "|" in description
                or any(unicodedata.category(character) == "Cc"
                       for character in description)):
            _reject(f"{where} description is invalid")
        if status not in _PHASE4_TASK_STATUSES:
            _reject(f"{where} status is invalid")
        dependencies = _parse_phase4_list_cell(
            dependencies_cell,
            "Dependencies",
            nonempty=False,
        )
        prerequisite_ids = _parse_phase4_list_cell(
            prerequisites_cell,
            "Prerequisites",
            nonempty=False,
        )
        test_ids = _parse_phase4_list_cell(
            tests_cell,
            "Tests",
            nonempty=True,
        )
        evidence_ids = _parse_phase4_list_cell(
            evidence_cell,
            "Evidence",
            nonempty=False,
        )
        if task_id in _D0_TASK_IDS and "TASK-D0-07" in dependencies:
            _reject("bootstrap tasks must not depend on TASK-D0-07")
        rows.append(Phase4TaskRowV1(
            task_id,
            dependencies,
            prerequisite_ids,
            test_ids,
            evidence_ids,
        ))

    row_by_task = {row.taskId: row for row in rows}
    visit_state: dict[str, int] = {}

    def visit(task_id: str) -> None:
        state = visit_state.get(task_id, 0)
        if state == 1:
            _reject("PHASE-4 task dependency graph contains a cycle")
        if state == 2:
            return
        visit_state[task_id] = 1
        for dependency in row_by_task[task_id].dependencies:
            visit(dependency)
        visit_state[task_id] = 2

    for task_id in _PHASE4_ALL_TASK_IDS:
        visit(task_id)
    return tuple(rows[:len(_D0_TASK_IDS)])


def parse_phase4_snapshot_content(
    phase4_snapshot: BootstrapDocumentSnapshotV1,
) -> Phase4SnapshotContentV1:
    """Derive the accepted PHASE-4 ref and frozen bootstrap task rows."""
    data = _validate_document_snapshot_envelope(
        phase4_snapshot,
        "PHASE-4",
        _PHASE4_DOCUMENT_PATH,
    )
    metadata, body_offset = _parse_accepted_frontmatter(data, "PHASE-4")
    approvers = _parse_accepted_approvers(
        metadata["approvers"],
        "PHASE-4.approvers",
    )
    digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.normative-document.v1\x00PHASE-4\x00" + data
        ).digest(),
    )
    document = NormativeDocumentRefV1(
        "PHASE-4",
        digest,
        "accepted",
        metadata["reviewCommit"],
        metadata["reviewLink"],
        metadata["approvedAt"],
        approvers,
    )
    return Phase4SnapshotContentV1(
        document,
        _parse_phase4_task_table(data[body_offset:]),
    )


def parse_phase5_snapshot_content(
    phase5_snapshot: BootstrapDocumentSnapshotV1,
) -> Phase5SnapshotContentV1:
    """Derive PHASE-5 metadata and its formal test denominator from bytes."""
    data = _validate_document_snapshot_envelope(
        phase5_snapshot,
        "PHASE-5",
        _PHASE5_DOCUMENT_PATH,
    )

    metadata, body_offset = _parse_phase5_frontmatter(data)
    approvers = _parse_phase5_approvers(metadata["approvers"])
    digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.normative-document.v1\x00PHASE-5\x00" + data
        ).digest(),
    )
    document = NormativeDocumentRefV1(
        "PHASE-5",
        digest,
        "accepted",
        metadata["reviewCommit"],
        metadata["reviewLink"],
        metadata["approvedAt"],
        approvers,
    )
    required_test_ids = _parse_phase5_catalog(data[body_offset:])
    return Phase5SnapshotContentV1(document, required_test_ids)


def _parse_required_test_ids(value: object) -> Tuple[str, ...]:
    where = "RequiredTestSetV1.requiredTestIds"
    if type(value) is not list or not 1 <= len(value) <= 4096:
        _reject(f"{where} count must be 1..4096")
    assert isinstance(value, list)
    test_ids = tuple(
        _require_ascii_text(item, TEST_ID_RE, f"{where}[{index}]", 127)
        for index, item in enumerate(value)
    )
    if (test_ids != tuple(sorted(test_ids))
            or len(set(test_ids)) != len(test_ids)):
        _reject(f"{where} must be unique ascending ASCII TestId")
    if any(test_id.startswith("TST-A0-") for test_id in test_ids):
        _reject(f"{where} must exclude every TST-A0-prefixed ID")
    return test_ids


def _parse_approval_signature_syntax(
    value: object,
    where: str,
) -> ApprovalSignatureV1:
    obj = _require_exact_keys(value, _APPROVAL_SIGNATURE_FIELDS, where)
    key_id = _require_safe_id(obj["keyId"], f"{where}.keyId")
    if obj["algorithm"] != "ed25519":
        _reject(f"{where}.algorithm must be ed25519")
    encoded_signature = obj["signature"]
    if (type(encoded_signature) is not str
            or _ED25519_SIGNATURE_RE.fullmatch(encoded_signature) is None):
        _reject(f"{where}.signature must be 64-byte lowercase hex")
    assert isinstance(encoded_signature, str)
    return ApprovalSignatureV1(
        key_id,
        "ed25519",
        bytes.fromhex(encoded_signature),
    )


def _parse_approval_signatures_syntax(
    value: object,
    where: str,
    maximum: int = 256,
) -> Tuple[ApprovalSignatureV1, ...]:
    if type(value) is not list or not 1 <= len(value) <= maximum:
        _reject(f"{where} count must be 1..{maximum}")
    assert isinstance(value, list)
    signatures = tuple(
        _parse_approval_signature_syntax(entry, f"{where}[{index}]")
        for index, entry in enumerate(value)
    )
    key_ids = tuple(signature.keyId for signature in signatures)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _reject(f"{where} must have unique ascending keyId")
    return signatures


def _require_signature_policy_membership(
    signatures: Tuple[ApprovalSignatureV1, ...],
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    where: str,
) -> None:
    maximum = min(len(principals), 256)
    if not 1 <= len(signatures) <= maximum:
        _reject(f"{where} count exceeds the resolved authority policy")
    principal_by_key = {principal.keyId: principal for principal in principals}
    for index, signature in enumerate(signatures):
        if signature.keyId not in principal_by_key:
            _reject(f"{where}[{index}].keyId is not in the authority policy")


def _parse_required_set_signatures(
    value: object,
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
) -> Tuple[ApprovalSignatureV1, ...]:
    where = "RequiredTestSetV1.signatures"
    signatures = _parse_approval_signatures_syntax(value, where)
    _require_signature_policy_membership(signatures, principals, where)
    return signatures


def _require_signature_rule(
    signatures: Tuple[ApprovalSignatureV1, ...],
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    rule: ApprovalRuleV1,
    where: str,
) -> None:
    principal_by_key = {principal.keyId: principal for principal in principals}
    signed_principals = tuple(
        principal_by_key[signature.keyId] for signature in signatures
    )
    distinct_principal_ids = {
        principal.principalId for principal in signed_principals
    }
    if len(distinct_principal_ids) < rule.minimumDistinctSigners:
        _reject(f"{where} do not satisfy distinct-principal quorum")
    signed_roles = {
        role for principal in signed_principals for role in principal.roles
    }
    if not set(rule.requiredRoles).issubset(signed_roles):
        _reject(f"{where} do not cover required roles")


def _verify_approval_signatures(
    signatures: Tuple[ApprovalSignatureV1, ...],
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    message: bytes,
    where: str,
) -> None:
    principal_by_key = {principal.keyId: principal for principal in principals}
    for signature in signatures:
        principal = principal_by_key[signature.keyId]
        if not verify_ed25519(
            principal.publicKey,
            message,
            signature.signature,
        ):
            _reject(f"{where} signature {signature.keyId} is invalid")


def _preflight_required_test_set(
    required_bytes: bytes,
    authority_policy_bytes: bytes,
) -> _RequiredTestSetPreflightV1:
    policy, policy_ref = parse_bootstrap_authority_policy(
        authority_policy_bytes
    )
    decoded = decode_canonical_pf_jcs(required_bytes)
    obj = _require_exact_keys(
        decoded, _REQUIRED_TEST_SET_FIELDS, "RequiredTestSetV1"
    )
    if obj["schema"] != "proof-forge.required-test-set.v1":
        _reject("RequiredTestSetV1.schema is not v1")
    identifier = _require_ascii_text(
        obj["id"], PROFILE_ID_RE, "RequiredTestSetV1.id", 127
    )
    version = _require_semver(obj["version"], "RequiredTestSetV1.version")
    phase5_document = _parse_normative_document_ref(
        obj["phase5Document"], "RequiredTestSetV1.phase5Document"
    )
    if phase5_document.id != "PHASE-5":
        _reject("RequiredTestSetV1.phase5Document.id must be PHASE-5")
    authority_policy = parse_content_ref(obj["authorityPolicy"])
    if authority_policy != policy_ref:
        _reject("RequiredTestSetV1.authorityPolicy does not match policy bytes")
    required_test_ids = _parse_required_test_ids(obj["requiredTestIds"])
    signatures = _parse_required_set_signatures(
        obj["signatures"], policy.principals
    )

    statement = {
        field: obj[field] for field in _REQUIRED_TEST_SET_FIELDS[:-1]
    }
    statement_digest = hashlib.sha256(
        b"pf.required-test-set-statement.v1\x00"
        + canonical_pf_jcs(statement)
    ).digest()
    message = b"pf.required-test-set-signature.v1\x00" + statement_digest
    required_set = RequiredTestSetV1(
        "proof-forge.required-test-set.v1",
        identifier,
        version,
        phase5_document,
        authority_policy,
        required_test_ids,
        signatures,
    )
    digest = Digest(
        "sha256",
        hashlib.sha256(b"pf.required-test-set.v1\x00" + required_bytes).digest(),
    )
    required_set_ref = ContentRef(
        required_set.schema,
        required_set.id,
        required_set.version,
        digest,
    )
    return _RequiredTestSetPreflightV1(
        policy,
        required_set,
        required_set_ref,
        message,
    )


def _finalize_required_test_set(
    preflight: _RequiredTestSetPreflightV1,
) -> Tuple[RequiredTestSetV1, ContentRef]:
    _require_signature_rule(
        preflight.requiredTestSet.signatures,
        preflight.policy.principals,
        preflight.policy.requiredTestSetRule,
        "RequiredTestSetV1.signatures",
    )
    _verify_approval_signatures(
        preflight.requiredTestSet.signatures,
        preflight.policy.principals,
        preflight.signatureMessage,
        "RequiredTestSetV1.signatures",
    )
    return preflight.requiredTestSet, preflight.requiredTestSetRef


def parse_required_test_set(
    required_bytes: bytes,
    authority_policy_bytes: bytes,
) -> Tuple[RequiredTestSetV1, ContentRef]:
    """Validate a canonical signed RequiredTestSet against policy bytes."""
    return _finalize_required_test_set(_preflight_required_test_set(
        required_bytes,
        authority_policy_bytes,
    ))


def _require_phase5_required_set_join(
    snapshot_content: Phase5SnapshotContentV1,
    preflight: _RequiredTestSetPreflightV1,
) -> None:
    if snapshot_content.document != preflight.requiredTestSet.phase5Document:
        _reject("RequiredTestSetV1 PHASE-5 document ref does not match snapshot")
    if (snapshot_content.requiredTestIds
            != preflight.requiredTestSet.requiredTestIds):
        _reject("RequiredTestSetV1 denominator does not match PHASE-5 catalog")


def parse_document_bound_required_test_set(
    required_bytes: bytes,
    authority_policy_bytes: bytes,
    phase5_snapshot: BootstrapDocumentSnapshotV1,
) -> Tuple[RequiredTestSetV1, ContentRef]:
    """Bind a signed RequiredTestSet to exact PHASE-5 snapshot content."""
    snapshot_content = parse_phase5_snapshot_content(phase5_snapshot)
    preflight = _preflight_required_test_set(
        required_bytes,
        authority_policy_bytes,
    )
    _require_phase5_required_set_join(snapshot_content, preflight)
    return _finalize_required_test_set(preflight)


def _parse_compact_gregorian_id(
    value: object,
    pattern: re.Pattern,
    date_offset: int,
    where: str,
) -> str:
    identifier = _require_ascii_text(value, pattern, where, 64)
    compact_date = identifier[date_offset:date_offset + 8]
    try:
        date(
            int(compact_date[0:4], 10),
            int(compact_date[4:6], 10),
            int(compact_date[6:8], 10),
        )
    except ValueError:
        _reject(f"{where} must contain a real Gregorian date")
    return identifier


def _parse_task_approval_test_ids(value: object) -> Tuple[str, ...]:
    where = "TaskApprovalV1.testIds"
    if type(value) is not list or not 1 <= len(value) <= 4096:
        _reject(f"{where} count must be 1..4096")
    assert isinstance(value, list)
    test_ids = tuple(
        _require_ascii_text(item, TEST_ID_RE, f"{where}[{index}]", 127)
        for index, item in enumerate(value)
    )
    if (test_ids != tuple(sorted(test_ids))
            or len(set(test_ids)) != len(test_ids)):
        _reject(f"{where} must be unique ascending ASCII TestId")
    return test_ids


def _parse_evidence_ref(value: object, where: str) -> EvidenceRef:
    obj = _require_exact_keys(value, _EVIDENCE_REF_FIELDS, where)
    return EvidenceRef(
        _parse_compact_gregorian_id(
            obj["id"], EVIDENCE_ID_RE, 3, f"{where}.id"
        ),
        parse_digest(obj["digest"]),
    )


def _parse_evidence_refs(value: object) -> Tuple[EvidenceRef, ...]:
    where = "TaskApprovalV1.evidence"
    if type(value) is not list or not 1 <= len(value) <= 4096:
        _reject(f"{where} count must be 1..4096")
    assert isinstance(value, list)
    evidence = tuple(
        _parse_evidence_ref(entry, f"{where}[{index}]")
        for index, entry in enumerate(value)
    )
    identifiers = tuple(item.id for item in evidence)
    if (identifiers != tuple(sorted(identifiers))
            or len(set(identifiers)) != len(identifiers)):
        _reject(f"{where} must be unique ascending by EvidenceRef.id")
    return evidence


def _parse_task_receipt_ref(
    value: object,
    where: str,
) -> BootstrapTaskVerifierReceiptRefV1:
    obj = _require_exact_keys(value, _TASK_RECEIPT_REF_FIELDS, where)
    task_id = obj["taskId"]
    if type(task_id) is not str or task_id not in _D0_TASK_IDS:
        _reject(f"{where}.taskId must be exact TASK-D0-01..06")
    assert isinstance(task_id, str)
    return BootstrapTaskVerifierReceiptRefV1(
        task_id,
        _parse_compact_gregorian_id(
            obj["id"], BTV_ID_RE, 4, f"{where}.id"
        ),
        parse_digest(obj["digest"]),
    )


def _parse_task_approval_ref(
    value: object,
    where: str,
) -> TaskApprovalRefV1:
    obj = _require_exact_keys(value, _TASK_APPROVAL_REF_FIELDS, where)
    task_id = obj["taskId"]
    if type(task_id) is not str or task_id not in _D0_TASK_IDS:
        _reject(f"{where}.taskId must be exact TASK-D0-01..06")
    assert isinstance(task_id, str)
    return TaskApprovalRefV1(task_id, parse_digest(obj["digest"]))


def _parse_dependency_completion_refs(
    value: object,
    where: str = "TaskApprovalV1.dependencyCompletions",
) -> Tuple[BootstrapTaskVerifierReceiptRefV1, ...]:
    if type(value) is not list or len(value) > 5:
        _reject(f"{where} count must be 0..5")
    assert isinstance(value, list)
    completions = tuple(
        _parse_task_receipt_ref(entry, f"{where}[{index}]")
        for index, entry in enumerate(value)
    )
    task_ids = tuple(item.taskId for item in completions)
    if (task_ids != tuple(sorted(task_ids))
            or len(set(task_ids)) != len(task_ids)):
        _reject(f"{where} must be unique ascending by taskId")
    return completions


def _parse_prerequisite_documents(
    value: object,
) -> Tuple[NormativeDocumentRefV1, ...]:
    where = "TaskApprovalV1.prerequisiteDocuments"
    if type(value) is not list or len(value) > 256:
        _reject(f"{where} count must be 0..256")
    assert isinstance(value, list)
    documents = tuple(
        _parse_normative_document_ref(entry, f"{where}[{index}]")
        for index, entry in enumerate(value)
    )
    identifiers = tuple(document.id for document in documents)
    if (identifiers != tuple(sorted(identifiers))
            or len(set(identifiers)) != len(identifiers)):
        _reject(f"{where} must be unique ascending by document id")
    return documents


def _parse_independent_reviews_syntax(
    value: object,
    candidate_commit: str,
) -> Tuple[IndependentReviewRefV1, ...]:
    where = "TaskApprovalV1.independentReviews"
    if type(value) is not list or not 1 <= len(value) <= 256:
        _reject(f"{where} count must be 1..256")
    assert isinstance(value, list)
    reviews = []
    for index, entry in enumerate(value):
        entry_where = f"{where}[{index}]"
        obj = _require_exact_keys(entry, _INDEPENDENT_REVIEW_FIELDS, entry_where)
        key_id = _require_safe_id(obj["keyId"], f"{entry_where}.keyId")
        role = obj["role"]
        if type(role) is not str or role not in _APPROVAL_ROLE_INDEX:
            _reject(f"{entry_where}.role is not an ApprovalRoleV1")
        assert isinstance(role, str)
        review_commit = obj["reviewCommit"]
        if (type(review_commit) is not str
                or GIT_OBJECT_RE.fullmatch(review_commit) is None):
            _reject(f"{entry_where}.reviewCommit is not a GitObjectId")
        if review_commit != candidate_commit:
            _reject(f"{entry_where}.reviewCommit does not match candidate")
        assert isinstance(review_commit, str)
        review_link = _parse_review_link(
            obj["reviewLink"], f"{entry_where}.reviewLink"
        )
        report_digest = parse_digest(obj["reportDigest"])
        if obj["decision"] != "approved":
            _reject(f"{entry_where}.decision must be approved")
        reviews.append(IndependentReviewRefV1(
            key_id,
            role,
            review_commit,
            review_link,
            report_digest,
            "approved",
        ))
    result = tuple(reviews)
    key_ids = tuple(review.keyId for review in result)
    if (key_ids != tuple(sorted(key_ids))
            or len(set(key_ids)) != len(key_ids)):
        _reject(f"{where} must have unique ascending keyId")
    report_digests = tuple(review.reportDigest.bytes for review in result)
    if len(set(report_digests)) != len(report_digests):
        _reject(f"{where} must have unique reportDigest values")
    return result


def _parse_eligible_stage0_tcb(value: object) -> EligibleStage0TcbV1:
    where = "EligibleStage0HandoffV1.tcb"
    obj = _require_exact_keys(value, _ELIGIBLE_STAGE0_TCB_FIELDS, where)
    return EligibleStage0TcbV1(
        parse_digest(obj["stage0VerifierDigest"]),
        parse_digest(obj["bootstrapVerifierDigest"]),
        parse_digest(obj["continuationDigest"]),
        parse_digest(obj["formalFinalizerDigest"]),
    )


def _parse_eligible_stage0_environment(
    value: object,
) -> EligibleStage0EnvironmentV1:
    where = "EligibleStage0HandoffV1.environment"
    obj = _require_exact_keys(
        value, _ELIGIBLE_STAGE0_ENVIRONMENT_FIELDS, where
    )
    expected = {
        "mode": "env-i",
        "home": "/var/empty",
        "path": "/usr/bin:/bin",
        "lcAll": "C",
        "tz": "UTC",
        "network": "deny-default",
    }
    for field, expected_value in expected.items():
        if obj[field] != expected_value:
            _reject(f"{where}.{field} is not the frozen Stage-0 value")
    return EligibleStage0EnvironmentV1(
        obj["mode"],
        obj["home"],
        obj["path"],
        obj["lcAll"],
        obj["tz"],
        obj["network"],
    )


def _parse_stage0_channels(value: object) -> Tuple[Stage0ChannelV1, ...]:
    where = "EligibleStage0HandoffV1.channels"
    if type(value) is not list or len(value) != len(_STAGE0_CHANNEL_SPECS):
        _reject(f"{where} must contain the exact four channels")
    assert isinstance(value, list)
    channels = []
    for index, (entry, expected) in enumerate(
        zip(value, _STAGE0_CHANNEL_SPECS)
    ):
        entry_where = f"{where}[{index}]"
        obj = _require_exact_keys(entry, _STAGE0_CHANNEL_FIELDS, entry_where)
        expected_role, expected_transport, expected_access = expected
        if obj["role"] != expected_role:
            _reject(f"{entry_where}.role is not the fixed channel role")
        fd = obj["fd"]
        if type(fd) is not int or not 3 <= fd <= 0xFFFFFFFF:
            _reject(f"{entry_where}.fd must be a u32 greater than 2")
        assert isinstance(fd, int)
        if obj["transport"] != expected_transport:
            _reject(f"{entry_where}.transport is not valid for its role")
        if obj["access"] != expected_access:
            _reject(f"{entry_where}.access is not valid for its role")
        channels.append(Stage0ChannelV1(
            expected_role,
            fd,
            expected_transport,
            expected_access,
            parse_digest(obj["bindingDigest"]),
        ))
    result = tuple(channels)
    fds = tuple(channel.fd for channel in result)
    if len(set(fds)) != len(fds):
        _reject(f"{where} fd values must be unique")
    return result


def _preflight_eligible_stage0_handoff(
    stage0_handoff_bytes: bytes,
) -> _EligibleStage0HandoffPreflightV1:
    decoded = decode_canonical_pf_jcs(stage0_handoff_bytes)
    obj = _require_exact_keys(
        decoded,
        _ELIGIBLE_STAGE0_HANDOFF_FIELDS,
        "EligibleStage0HandoffV1",
    )
    if obj["schema"] != "proof-forge.eligible-stage0-handoff.v1":
        _reject("EligibleStage0HandoffV1.schema is not v1")
    identifier = _require_ascii_text(
        obj["id"], PROFILE_ID_RE, "EligibleStage0HandoffV1.id", 127
    )
    version = _require_semver(
        obj["version"], "EligibleStage0HandoffV1.version"
    )
    run_id = _require_safe_id(
        obj["runId"], "EligibleStage0HandoffV1.runId"
    )
    encoded_nonce = obj["nonce"]
    if (type(encoded_nonce) is not str
            or _LOWERCASE_32_BYTE_HEX_RE.fullmatch(encoded_nonce) is None):
        _reject("EligibleStage0HandoffV1.nonce must be 32-byte lowercase hex")
    assert isinstance(encoded_nonce, str)
    candidate = parse_candidate_identity(obj["candidate"])
    authority_policy = parse_content_ref(obj["authorityPolicy"])
    authority_store = parse_content_ref(obj["authorityStoreService"])
    host_observation = parse_content_ref(obj["hostObservation"])
    host_profile = parse_content_ref(obj["hostProfile"])
    if obj["eligible"] is not True:
        _reject("EligibleStage0HandoffV1.eligible must be true")
    tcb = _parse_eligible_stage0_tcb(obj["tcb"])
    environment = _parse_eligible_stage0_environment(obj["environment"])
    channels = _parse_stage0_channels(obj["channels"])
    if obj["pathnameReopen"] is not False:
        _reject("EligibleStage0HandoffV1.pathnameReopen must be false")
    if obj["fallback"] != "none":
        _reject("EligibleStage0HandoffV1.fallback must be none")

    if channels[0].bindingDigest != authority_policy.digest:
        _reject("EligibleStage0HandoffV1 authority-policy binding mismatch")
    if channels[1].bindingDigest != authority_store.digest:
        _reject("EligibleStage0HandoffV1 authority-store binding mismatch")
    if channels[2].bindingDigest != candidate.archiveDigest:
        _reject("EligibleStage0HandoffV1 candidate-archive binding mismatch")

    handoff = EligibleStage0HandoffV1(
        "proof-forge.eligible-stage0-handoff.v1",
        identifier,
        version,
        run_id,
        bytes.fromhex(encoded_nonce),
        candidate,
        authority_policy,
        authority_store,
        host_observation,
        host_profile,
        True,
        tcb,
        environment,
        channels,
        False,
        "none",
    )
    handoff_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.eligible-stage0-handoff.v1\x00" + stage0_handoff_bytes
        ).digest(),
    )
    handoff_ref = ContentRef(
        handoff.schema,
        handoff.id,
        handoff.version,
        handoff_digest,
    )
    return _EligibleStage0HandoffPreflightV1(handoff, handoff_ref)


def _preflight_bootstrap_task_verifier_receipt(
    task_receipt_bytes: bytes,
) -> _BootstrapTaskVerifierReceiptPreflightV1:
    decoded = decode_canonical_pf_jcs(task_receipt_bytes)
    obj = _require_exact_keys(
        decoded,
        _BOOTSTRAP_TASK_RECEIPT_FIELDS,
        "BootstrapTaskVerifierReceiptV1",
    )
    if obj["schema"] != "proof-forge.bootstrap-task-verifier-receipt.v1":
        _reject("BootstrapTaskVerifierReceiptV1.schema is not v1")
    identifier = _parse_compact_gregorian_id(
        obj["id"], BTV_ID_RE, 4, "BootstrapTaskVerifierReceiptV1.id"
    )
    task_id = obj["taskId"]
    if type(task_id) is not str or task_id not in _D0_TASK_IDS:
        _reject(
            "BootstrapTaskVerifierReceiptV1.taskId must be exact "
            "TASK-D0-01..06"
        )
    assert isinstance(task_id, str)
    candidate = parse_candidate_identity(obj["candidate"])
    authority_policy = parse_content_ref(obj["authorityPolicy"])
    required_test_set = parse_content_ref(obj["requiredTestSet"])
    task_approval = _parse_task_approval_ref(
        obj["taskApproval"],
        "BootstrapTaskVerifierReceiptV1.taskApproval",
    )
    if task_approval.taskId != task_id:
        _reject(
            "BootstrapTaskVerifierReceiptV1.taskApproval.taskId does not "
            "match receipt taskId"
        )
    stage0_handoff = parse_content_ref(obj["stage0Handoff"])
    dependency_completions = _parse_dependency_completion_refs(
        obj["dependencyCompletions"],
        "BootstrapTaskVerifierReceiptV1.dependencyCompletions",
    )
    verifier_digest = parse_digest(obj["verifierDigest"])
    if obj["result"] != "task-approved":
        _reject("BootstrapTaskVerifierReceiptV1.result must be task-approved")
    signature = _parse_approval_signature_syntax(
        obj["signature"],
        "BootstrapTaskVerifierReceiptV1.signature",
    )

    statement = {
        field: obj[field] for field in _BOOTSTRAP_TASK_RECEIPT_FIELDS[:-1]
    }
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-verifier-receipt-statement.v1\x00"
        + canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        + statement_digest
    )
    receipt = BootstrapTaskVerifierReceiptV1(
        "proof-forge.bootstrap-task-verifier-receipt.v1",
        identifier,
        task_id,
        candidate,
        authority_policy,
        required_test_set,
        task_approval,
        stage0_handoff,
        dependency_completions,
        verifier_digest,
        "task-approved",
        signature,
    )
    return _BootstrapTaskVerifierReceiptPreflightV1(
        receipt,
        signature_message,
        task_receipt_bytes,
    )


def _preflight_task_approval(
    task_approval_bytes: bytes,
) -> _TaskApprovalPreflightV1:
    decoded = decode_canonical_pf_jcs(task_approval_bytes)
    obj = _require_exact_keys(
        decoded, _TASK_APPROVAL_FIELDS, "TaskApprovalV1"
    )
    if obj["schema"] != "proof-forge.bootstrap-task-approval.v1":
        _reject("TaskApprovalV1.schema is not v1")
    task_id = obj["taskId"]
    if type(task_id) is not str or task_id not in _D0_TASK_IDS:
        _reject("TaskApprovalV1.taskId must be exact TASK-D0-01..06")
    assert isinstance(task_id, str)
    candidate = parse_candidate_identity(obj["candidate"])
    task_breakdown = _parse_normative_document_ref(
        obj["taskBreakdown"], "TaskApprovalV1.taskBreakdown"
    )
    if task_breakdown.id != "PHASE-4":
        _reject("TaskApprovalV1.taskBreakdown.id must be PHASE-4")
    required_test_set = parse_content_ref(obj["requiredTestSet"])
    if required_test_set.schema != "proof-forge.required-test-set.v1":
        _reject("TaskApprovalV1.requiredTestSet schema is not v1")
    test_ids = _parse_task_approval_test_ids(obj["testIds"])
    evidence = _parse_evidence_refs(obj["evidence"])
    dependency_completions = _parse_dependency_completion_refs(
        obj["dependencyCompletions"]
    )
    prerequisite_documents = _parse_prerequisite_documents(
        obj["prerequisiteDocuments"]
    )
    authority_policy = parse_content_ref(obj["authorityPolicy"])
    if authority_policy.schema != "proof-forge.bootstrap-authority-policy.v1":
        _reject("TaskApprovalV1.authorityPolicy schema is not v1")
    stage0_handoff = parse_content_ref(obj["stage0Handoff"])
    if stage0_handoff.schema != "proof-forge.eligible-stage0-handoff.v1":
        _reject("TaskApprovalV1.stage0Handoff schema is not v1")
    independent_reviews = _parse_independent_reviews_syntax(
        obj["independentReviews"], candidate.commit
    )
    signatures = _parse_approval_signatures_syntax(
        obj["signatures"], "TaskApprovalV1.signatures"
    )

    statement = {
        field: obj[field] for field in _TASK_APPROVAL_FIELDS[:-1]
    }
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-approval-statement.v1\x00"
        + canonical_pf_jcs(statement)
    ).digest()
    message = b"pf.bootstrap-task-approval-signature.v1\x00" + statement_digest
    approval = TaskApprovalV1(
        "proof-forge.bootstrap-task-approval.v1",
        task_id,
        candidate,
        task_breakdown,
        required_test_set,
        test_ids,
        evidence,
        dependency_completions,
        prerequisite_documents,
        authority_policy,
        stage0_handoff,
        independent_reviews,
        signatures,
    )
    return _TaskApprovalPreflightV1(
        approval,
        message,
        task_approval_bytes,
    )


def _resolve_task_approval_authority(
    approval: TaskApprovalV1,
    policy: BootstrapAuthorityPolicyV1,
) -> None:
    signature_where = "TaskApprovalV1.signatures"
    _require_signature_policy_membership(
        approval.signatures,
        policy.principals,
        signature_where,
    )
    principal_by_key = {
        principal.keyId: principal for principal in policy.principals
    }
    distinct_policy_principals = {
        principal.principalId for principal in policy.principals
    }
    if len(approval.independentReviews) > min(
        len(distinct_policy_principals), 256
    ):
        _reject(
            "TaskApprovalV1.independentReviews count exceeds distinct policy principals"
        )
    review_principal_ids = []
    for index, review in enumerate(approval.independentReviews):
        principal = principal_by_key.get(review.keyId)
        if principal is None:
            _reject(
                f"TaskApprovalV1.independentReviews[{index}].keyId is not in policy"
            )
        if review.role not in principal.roles:
            _reject(
                f"TaskApprovalV1.independentReviews[{index}].role is not authorized"
            )
        review_principal_ids.append(principal.principalId)
    if len(set(review_principal_ids)) != len(review_principal_ids):
        _reject("TaskApprovalV1 independent review principalId values are not unique")
    signature_principal_ids = {
        principal_by_key[signature.keyId].principalId
        for signature in approval.signatures
    }
    if set(review_principal_ids) != signature_principal_ids:
        _reject(
            "TaskApprovalV1 review and signature principalId sets do not match"
        )
    task_rule = next(
        task_rule.rule for task_rule in policy.taskRules
        if task_rule.taskId == approval.taskId
    )
    _require_signature_rule(
        approval.signatures,
        policy.principals,
        task_rule,
        signature_where,
    )


def _finalize_task_approval(
    preflight: _TaskApprovalPreflightV1,
    policy: BootstrapAuthorityPolicyV1,
) -> Tuple[TaskApprovalV1, TaskApprovalRefV1]:
    approval = preflight.taskApproval
    _verify_approval_signatures(
        approval.signatures,
        policy.principals,
        preflight.signatureMessage,
        "TaskApprovalV1.signatures",
    )
    approval_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00" + preflight.signedBytes
        ).digest(),
    )
    return approval, TaskApprovalRefV1(approval.taskId, approval_digest)


def _require_task_approval_input_joins(
    approval_preflight: _TaskApprovalPreflightV1,
    snapshot_content: Phase5SnapshotContentV1,
    required_preflight: _RequiredTestSetPreflightV1,
) -> None:
    _require_phase5_required_set_join(snapshot_content, required_preflight)
    approval = approval_preflight.taskApproval
    required_set = required_preflight.requiredTestSet
    if approval.authorityPolicy != required_set.authorityPolicy:
        _reject(
            "TaskApprovalV1 authority policy ref does not match "
            "RequiredTestSetV1"
        )
    if approval.requiredTestSet != required_preflight.requiredTestSetRef:
        _reject(
            "TaskApprovalV1 required-test-set ref does not match exact bytes"
        )
    required_test_ids = set(required_set.requiredTestIds)
    if any(test_id not in required_test_ids for test_id in approval.testIds):
        _reject(
            "TaskApprovalV1 testIds are not members of RequiredTestSetV1"
        )
    _resolve_task_approval_authority(approval, required_preflight.policy)


def _require_bootstrap_task_receipt_input_joins(
    receipt_preflight: _BootstrapTaskVerifierReceiptPreflightV1,
    approval_preflight: _TaskApprovalPreflightV1,
    required_preflight: _RequiredTestSetPreflightV1,
    handoff_preflight: _EligibleStage0HandoffPreflightV1,
) -> None:
    receipt = receipt_preflight.receipt
    approval = approval_preflight.taskApproval
    required_set = required_preflight.requiredTestSet
    policy = required_preflight.policy
    handoff = handoff_preflight.handoff

    if receipt.taskId != approval.taskId:
        _reject("task receipt taskId does not match TaskApprovalV1")
    if receipt.taskApproval.taskId != approval.taskId:
        _reject("task receipt TaskApprovalRefV1 taskId does not match approval")
    if receipt.candidate != approval.candidate:
        _reject("task receipt candidate does not match TaskApprovalV1")
    if receipt.authorityPolicy != required_set.authorityPolicy:
        _reject("task receipt authority policy does not match RequiredTestSetV1")
    if receipt.requiredTestSet != required_preflight.requiredTestSetRef:
        _reject("task receipt required-test-set ref does not match exact bytes")
    if receipt.stage0Handoff != handoff_preflight.handoffRef:
        _reject("task receipt Stage-0 handoff ref does not match exact bytes")
    if approval.stage0Handoff != handoff_preflight.handoffRef:
        _reject("TaskApprovalV1 Stage-0 handoff ref does not match exact bytes")
    if receipt.dependencyCompletions != approval.dependencyCompletions:
        _reject("task receipt dependencies do not match TaskApprovalV1")
    if receipt.verifierDigest != policy.verifier.executableDigest:
        _reject("task receipt verifier digest does not match authority policy")
    if receipt.signature.keyId != policy.verifier.receiptKeyId:
        _reject("task receipt signature key is not the policy receipt key")

    if handoff.candidate != approval.candidate:
        _reject("raw Stage-0 handoff candidate does not match TaskApprovalV1")
    if handoff.authorityPolicy != required_set.authorityPolicy:
        _reject("raw Stage-0 handoff authority policy ref does not match")
    if handoff.authorityStoreService != policy.authorityStoreService:
        _reject("raw Stage-0 handoff authority-store service ref does not match")
    if handoff.tcb.bootstrapVerifierDigest != policy.verifier.executableDigest:
        _reject("raw Stage-0 handoff bootstrap verifier digest does not match")


def _finalize_bootstrap_task_verifier_receipt(
    preflight: _BootstrapTaskVerifierReceiptPreflightV1,
    policy: BootstrapAuthorityPolicyV1,
) -> Tuple[
    BootstrapTaskVerifierReceiptV1,
    BootstrapTaskVerifierReceiptRefV1,
]:
    receipt = preflight.receipt
    if not verify_ed25519(
        policy.verifier.receiptPublicKey,
        preflight.signatureMessage,
        receipt.signature.signature,
    ):
        _reject("BootstrapTaskVerifierReceiptV1 signature is invalid")
    receipt_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.bootstrap-task-verifier-receipt.v1\x00"
            + preflight.signedBytes
        ).digest(),
    )
    return receipt, BootstrapTaskVerifierReceiptRefV1(
        receipt.taskId,
        receipt.id,
        receipt_digest,
    )


def parse_task_approval(
    task_approval_bytes: bytes,
    required_test_set_bytes: bytes,
    authority_policy_bytes: bytes,
    phase5_snapshot: BootstrapDocumentSnapshotV1,
) -> Tuple[TaskApprovalV1, TaskApprovalRefV1]:
    """Validate signed TaskApproval content against its four authority inputs."""
    approval_preflight = _preflight_task_approval(task_approval_bytes)
    snapshot_content = parse_phase5_snapshot_content(phase5_snapshot)
    required_preflight = _preflight_required_test_set(
        required_test_set_bytes,
        authority_policy_bytes,
    )
    _require_task_approval_input_joins(
        approval_preflight,
        snapshot_content,
        required_preflight,
    )

    _finalize_required_test_set(required_preflight)
    return _finalize_task_approval(
        approval_preflight,
        required_preflight.policy,
    )


def _preflight_bootstrap_task_signed_content(
    task_receipt_bytes: bytes,
    task_approval_bytes: bytes,
) -> _BootstrapTaskSignedPreflightV1:
    receipt = _preflight_bootstrap_task_verifier_receipt(task_receipt_bytes)
    approval = _preflight_task_approval(task_approval_bytes)
    return _BootstrapTaskSignedPreflightV1(
        approval,
        receipt,
    )


def _require_bootstrap_task_object_input_joins(
    task_object: _BootstrapTaskObjectPreflightV1,
    snapshot_content: Phase5SnapshotContentV1,
    required_preflight: _RequiredTestSetPreflightV1,
) -> None:
    _require_task_approval_input_joins(
        task_object.approval,
        snapshot_content,
        required_preflight,
    )
    _require_bootstrap_task_receipt_input_joins(
        task_object.receipt,
        task_object.approval,
        required_preflight,
        task_object.handoff,
    )


def _finalize_bootstrap_task_object(
    task_object: _BootstrapTaskObjectPreflightV1,
    policy: BootstrapAuthorityPolicyV1,
) -> _VerifiedBootstrapTaskObjectV1:
    approval, approval_ref = _finalize_task_approval(
        task_object.approval,
        policy,
    )
    if task_object.receipt.receipt.taskApproval.digest != approval_ref.digest:
        _reject("task receipt TaskApprovalRefV1 digest does not match exact bytes")
    receipt, receipt_ref = _finalize_bootstrap_task_verifier_receipt(
        task_object.receipt,
        policy,
    )
    return _VerifiedBootstrapTaskObjectV1(
        approval,
        approval_ref,
        receipt,
        receipt_ref,
        task_object.handoff.handoffRef,
    )


def _parse_bootstrap_task_object_content(
    task_receipt_bytes: bytes,
    task_approval_bytes: bytes,
    required_test_set_bytes: bytes,
    authority_policy_bytes: bytes,
    phase5_snapshot: BootstrapDocumentSnapshotV1,
    stage0_handoff_bytes: bytes,
) -> _VerifiedBootstrapTaskObjectV1:
    signed = _preflight_bootstrap_task_signed_content(
        task_receipt_bytes,
        task_approval_bytes,
    )
    snapshot_content = parse_phase5_snapshot_content(phase5_snapshot)
    required_preflight = _preflight_required_test_set(
        required_test_set_bytes,
        authority_policy_bytes,
    )
    task_object = _BootstrapTaskObjectPreflightV1(
        signed.approval,
        signed.receipt,
        _preflight_eligible_stage0_handoff(stage0_handoff_bytes),
    )
    _require_bootstrap_task_object_input_joins(
        task_object,
        snapshot_content,
        required_preflight,
    )
    _finalize_required_test_set(required_preflight)
    return _finalize_bootstrap_task_object(
        task_object,
        required_preflight.policy,
    )


def parse_bootstrap_task_verifier_receipt(
    task_receipt_bytes: bytes,
    task_approval_bytes: bytes,
    required_test_set_bytes: bytes,
    authority_policy_bytes: bytes,
    phase5_snapshot: BootstrapDocumentSnapshotV1,
    stage0_handoff_bytes: bytes,
) -> Tuple[
    BootstrapTaskVerifierReceiptV1,
    BootstrapTaskVerifierReceiptRefV1,
]:
    """Validate the signed receipt and its exact six content inputs.

    This function establishes content closure only.  It does not authenticate
    the live Stage-0 process, authority-store state, or filesystem provenance.
    """
    verified = _parse_bootstrap_task_object_content(
        task_receipt_bytes,
        task_approval_bytes,
        required_test_set_bytes,
        authority_policy_bytes,
        phase5_snapshot,
        stage0_handoff_bytes,
    )
    return verified.receipt, verified.receiptRef


def _require_sorted_unique(values: tuple, where: str, *, nonempty: bool) -> None:
    if type(values) is not tuple or (nonempty and not values):
        _reject(f"{where} must be a{' non-empty' if nonempty else ''} tuple")
    if any(type(value) is not str for value in values):
        _reject(f"{where} must contain strings")
    if tuple(sorted(values)) != values or len(set(values)) != len(values):
        _reject(f"{where} must be unique and sorted")


def _require_project_path(value: object) -> str:
    if type(value) is not str or not value:
        _reject("document path must be non-empty text")
    assert isinstance(value, str)
    if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
        _reject("document path contains an invalid Unicode scalar")
    if (unicodedata.normalize("NFC", value) != value
            or len(value.encode("utf-8")) > 1024
            or value.startswith("/") or value.endswith("/")
            or "\\" in value or posixpath.normpath(value) != value
            or any(part in {"", ".", ".."} for part in value.split("/"))
            or any(unicodedata.category(character) == "Cc" for character in value)):
        _reject("document path is not a normalized project-relative path")
    return value


def _validate_subject(subject: BootstrapTaskSubjectV1) -> None:
    if type(subject) is not BootstrapTaskSubjectV1:
        _reject("subject must be BootstrapTaskSubjectV1")
    if type(subject.candidate) is not CandidateIdentity:
        _reject("subject candidate must be typed")
    if (type(subject.rootTaskId) is not str
            or subject.rootTaskId not in _D0_TASK_IDS):
        _reject("rootTaskId must be exact TASK-D0-01..06")
    if (type(subject.taskRows) is not tuple
            or not 1 <= len(subject.taskRows) <= len(_D0_TASK_IDS)):
        _reject("taskRows count must be 1..6")
    for row in subject.taskRows:
        if type(row) is not BootstrapTaskRowSubjectV1:
            _reject("taskRows contain an untyped row")
        if (type(row.taskId) is not str
                or row.taskId not in _D0_TASK_IDS):
            _reject("task row ID must be exact TASK-D0-01..06")
    task_ids = tuple(row.taskId for row in subject.taskRows)
    if task_ids != tuple(sorted(task_ids)) or len(set(task_ids)) != len(task_ids):
        _reject("taskRows must be unique and sorted")
    if subject.rootTaskId not in task_ids:
        _reject("root task row is missing")
    row_by_task = {row.taskId: row for row in subject.taskRows}
    for row in subject.taskRows:
        _require_sorted_unique(row.dependencies, f"{row.taskId}.dependencies", nonempty=False)
        _require_sorted_unique(row.testIds, f"{row.taskId}.testIds", nonempty=True)
        _require_sorted_unique(row.evidenceIds, f"{row.taskId}.evidenceIds", nonempty=True)
        if any(value not in _D0_TASK_IDS for value in row.dependencies):
            _reject("dependency task ID must be exact TASK-D0-01..06")
        if any(value not in row_by_task for value in row.dependencies):
            _reject("dependency task row is missing")
        for index, test_id in enumerate(row.testIds):
            _require_ascii_text(
                test_id,
                TEST_ID_RE,
                f"{row.taskId}.testIds[{index}]",
                127,
            )
        for evidence_id in row.evidenceIds:
            _parse_compact_gregorian_id(
                evidence_id,
                EVIDENCE_ID_RE,
                3,
                f"{row.taskId}.evidenceIds",
            )
        if type(row.prerequisites) is not tuple:
            _reject("prerequisites must be a tuple")
        prerequisite_ids = []
        for prerequisite in row.prerequisites:
            obj = _require_exact_keys(
                prerequisite, ("documentId", "requiredStatus"), "prerequisite")
            if obj["requiredStatus"] != "accepted":
                _reject("prerequisite must require accepted")
            prerequisite_ids.append(_require_safe_id(
                obj["documentId"],
                "prerequisite.documentId",
            ))
        if prerequisite_ids != sorted(prerequisite_ids) or len(set(prerequisite_ids)) != len(prerequisite_ids):
            _reject("prerequisites must be unique and sorted")

    visit_state: dict[str, int] = {}

    def visit(task_id: str) -> None:
        state = visit_state.get(task_id, 0)
        if state == 1:
            _reject("task dependency graph contains a cycle")
        if state == 2:
            return
        visit_state[task_id] = 1
        for dependency in row_by_task[task_id].dependencies:
            visit(dependency)
        visit_state[task_id] = 2

    visit(subject.rootTaskId)
    if set(visit_state) != set(row_by_task):
        _reject("taskRows contain a row unreachable from rootTaskId")

    if type(subject.evidenceRows) is not tuple or not subject.evidenceRows:
        _reject("evidenceRows must be non-empty")
    evidence_ids = []
    for evidence_row in subject.evidenceRows:
        if type(evidence_row) is not BootstrapLedgerSubjectV1:
            _reject("evidenceRows contain an untyped row")
        _parse_compact_gregorian_id(
            evidence_row.id,
            EVIDENCE_ID_RE,
            3,
            "evidence row ID",
        )
        if (type(evidence_row.taskId) is not str
                or evidence_row.taskId not in _D0_TASK_IDS):
            _reject("evidence row taskId must be exact TASK-D0-01..06")
        if evidence_row.grade != "bootstrap" or evidence_row.result != "passed":
            _reject("bootstrap ledger row must be passed")
        _require_sorted_unique(
            evidence_row.testIds,
            f"{evidence_row.id}.testIds",
            nonempty=True,
        )
        for index, test_id in enumerate(evidence_row.testIds):
            _require_ascii_text(
                test_id,
                TEST_ID_RE,
                f"{evidence_row.id}.testIds[{index}]",
                127,
            )
        evidence_ids.append(evidence_row.id)
    if evidence_ids != sorted(evidence_ids) or len(set(evidence_ids)) != len(evidence_ids):
        _reject("evidenceRows must be unique and sorted")
    expected_evidence = tuple(sorted(
        evidence_id for row in subject.taskRows for evidence_id in row.evidenceIds
    ))
    if tuple(evidence_ids) != expected_evidence:
        _reject("evidenceRows do not match task row evidence IDs")

    evidence_owner: dict[str, str] = {}
    for task_row in subject.taskRows:
        for evidence_id in task_row.evidenceIds:
            if evidence_id in evidence_owner:
                _reject("an evidence ID is referenced by multiple task rows")
            evidence_owner[evidence_id] = task_row.taskId
    tests_by_task = {task_id: set() for task_id in row_by_task}
    for evidence_row in subject.evidenceRows:
        if evidence_row.taskId != evidence_owner[evidence_row.id]:
            _reject("evidence row taskId does not match its owning task row")
        tests_by_task[evidence_row.taskId].update(evidence_row.testIds)
    for task_row in subject.taskRows:
        if tuple(sorted(tests_by_task[task_row.taskId])) != task_row.testIds:
            _reject("evidence test union does not match task row testIds")

    if type(subject.documents) is not tuple or not subject.documents:
        _reject("documents must be non-empty")
    document_ids = []
    document_paths = []
    for document in subject.documents:
        if type(document) is not BootstrapDocumentSnapshotV1:
            _reject("documents contain an untyped snapshot")
        document_ids.append(_require_safe_id(
            document.id,
            "document snapshot ID",
        ))
        if type(document.bytes) is not bytes:
            _reject("document snapshot bytes must be bytes")
        try:
            document.bytes.decode("utf-8", errors="strict")
        except UnicodeError:
            _reject("document snapshot bytes must be strict UTF-8")
        document_paths.append(_require_project_path(document.path))
    if document_ids != sorted(document_ids) or len(set(document_ids)) != len(document_ids):
        _reject("documents must be unique and sorted by ID")
    if len(set(document_paths)) != len(document_paths):
        _reject("document paths must be unique")
    casefolded_paths = tuple(path.casefold() for path in document_paths)
    if len(set(casefolded_paths)) != len(casefolded_paths):
        _reject("document paths must be unique after Unicode casefold")
    expected_document_ids = {"PHASE-4", "PHASE-5"}
    for task_row in subject.taskRows:
        expected_document_ids.update(
            prerequisite["documentId"]
            for prerequisite in task_row.prerequisites
        )
    if tuple(document_ids) != tuple(sorted(expected_document_ids)):
        _reject("documents do not match PHASE-4/5 and task prerequisites")


def _validate_object_shell(objects: BootstrapTaskObjectSetV1) -> None:
    if type(objects) is not BootstrapTaskObjectSetV1:
        _reject("objects must be BootstrapTaskObjectSetV1")
    for field in (
        "authorityPolicyBytes", "stage0HandoffBytes", "requiredTestSetBytes",
        "taskApprovalBytes", "taskReceiptBytes",
    ):
        encoded = getattr(objects, field)
        if type(encoded) is not bytes or not encoded:
            _reject(f"{field} must be non-empty bytes")
    if (type(objects.dependencyObjects) is not tuple
            or len(objects.dependencyObjects) > 5):
        _reject("dependencyObjects must be a tuple with 0..5 entries")
    for dependency in objects.dependencyObjects:
        if type(dependency) is not DependencyTaskObjectV1:
            _reject("dependencyObjects contain an untyped bundle")
        for field in (
            "approvalBytes", "receiptBytes", "stage0HandoffBytes",
        ):
            encoded = getattr(dependency, field)
            if type(encoded) is not bytes or not encoded:
                _reject(f"dependencyObjects.{field} must be non-empty bytes")
    evidence_objects = objects.evidenceObjectBytes
    if (type(evidence_objects) is not tuple
            or not 1 <= len(evidence_objects) <= MAX_BOOTSTRAP_EVIDENCE_OBJECTS):
        _reject("evidenceObjectBytes count must be 1..24576")
    if (type(objects.reviewReports) is not tuple
            or not 1 <= len(objects.reviewReports) <= MAX_BOOTSTRAP_REVIEW_REPORTS):
        _reject("reviewReports count must be 1..1536")
    for encoded in evidence_objects:
        if type(encoded) is not bytes or not encoded:
            _reject("evidenceObjectBytes contains invalid bytes")
        decode_canonical_pf_jcs(encoded)


def _preflight_review_reports(values: object) -> Tuple[Digest, ...]:
    """Validate exact raw review-report carriers before any report hash."""
    if (type(values) is not tuple
            or not 1 <= len(values) <= MAX_BOOTSTRAP_REVIEW_REPORTS):
        _reject("reviewReports count must be 1..1536")
    assert isinstance(values, tuple)

    reports = []
    digest_bytes = []
    total_bytes = 0
    for index, report in enumerate(values):
        where = f"reviewReports[{index}]"
        if type(report) is not ReviewReportObjectV1:
            _reject(f"{where} must be exact ReviewReportObjectV1")
        digest = report.digest
        if type(digest) is not Digest:
            _reject(f"{where}.digest must be exact Digest")
        if type(digest.algorithm) is not str or digest.algorithm != "sha256":
            _reject(f"{where}.digest algorithm must be exact sha256")
        if type(digest.bytes) is not bytes or len(digest.bytes) != 32:
            _reject(f"{where}.digest must contain exact 32 bytes")
        raw = report.bytes
        if (type(raw) is not bytes
                or not 1 <= len(raw) <= MAX_REVIEW_REPORT_BYTES):
            _reject(f"{where}.bytes length must be 1..1048576")
        total_bytes += len(raw)
        if total_bytes > MAX_BOOTSTRAP_REVIEW_REPORT_TOTAL_BYTES:
            _reject("reviewReports aggregate bytes exceed 16777216")
        reports.append(report)
        digest_bytes.append(digest.bytes)

    digest_order = tuple(digest_bytes)
    if digest_order != tuple(sorted(digest_order)):
        _reject("reviewReports must be ascending by digest bytes")
    if len(set(digest_order)) != len(digest_order):
        _reject("reviewReports digest bytes must be unique")

    for index, report in enumerate(reports):
        expected = hashlib.sha256(
            b"pf.independent-review-report.v1\x00" + report.bytes
        ).digest()
        if report.digest.bytes != expected:
            _reject(f"reviewReports[{index}] digest does not match exact bytes")
    return tuple(report.digest for report in reports)


def _parse_bootstrap_task_object_graph(
    subject: BootstrapTaskSubjectV1,
    objects: BootstrapTaskObjectSetV1,
) -> _BootstrapTaskObjectGraphV1:
    _validate_object_shell(objects)
    report_digests = _preflight_review_reports(objects.reviewReports)
    phase5_snapshot = next(
        (
            document for document in subject.documents
            if document.id == "PHASE-5"
        ),
        None,
    )
    if phase5_snapshot is None:
        _reject("subject lacks the PHASE-5 document snapshot")

    root_signed = _preflight_bootstrap_task_signed_content(
        objects.taskReceiptBytes,
        objects.taskApprovalBytes,
    )
    dependency_signed = tuple(
        _preflight_bootstrap_task_signed_content(
            dependency.receiptBytes,
            dependency.approvalBytes,
        )
        for dependency in objects.dependencyObjects
    )
    expected_dependency_ids = tuple(
        row.taskId for row in subject.taskRows
        if row.taskId != subject.rootTaskId
    )
    actual_dependency_ids = tuple(
        dependency.approval.taskApproval.taskId
        for dependency in dependency_signed
    )
    if actual_dependency_ids != expected_dependency_ids:
        _reject(
            "dependencyObjects do not match the sorted transitive dependency set"
        )
    if root_signed.approval.taskApproval.taskId != subject.rootTaskId:
        _reject("root TaskApprovalV1 taskId does not match subject rootTaskId")

    signed_objects = (root_signed,) + dependency_signed
    row_by_task = {row.taskId: row for row in subject.taskRows}
    for task_object in signed_objects:
        approval = task_object.approval.taskApproval
        if approval.candidate != subject.candidate:
            _reject("TaskApprovalV1 candidate does not match subject candidate")
        expected_direct_ids = row_by_task[approval.taskId].dependencies
        actual_direct_ids = tuple(
            completion.taskId
            for completion in approval.dependencyCompletions
        )
        if actual_direct_ids != expected_direct_ids:
            _reject(
                "TaskApprovalV1 dependencies do not match the subject DAG row"
            )

    snapshot_content = parse_phase5_snapshot_content(phase5_snapshot)
    required_preflight = _preflight_required_test_set(
        objects.requiredTestSetBytes,
        objects.authorityPolicyBytes,
    )
    handoff_preflights = (
        _preflight_eligible_stage0_handoff(objects.stage0HandoffBytes),
    ) + tuple(
        _preflight_eligible_stage0_handoff(
            dependency.stage0HandoffBytes
        )
        for dependency in objects.dependencyObjects
    )
    handoff_refs = tuple(
        handoff.handoffRef for handoff in handoff_preflights
    )
    if len(set(handoff_refs)) != len(handoff_refs):
        _reject("root and dependency Stage-0 handoffs must be unique per task")
    handoff_run_keys = tuple(
        (handoff.handoff.runId, handoff.handoff.nonce)
        for handoff in handoff_preflights
    )
    if len(set(handoff_run_keys)) != len(handoff_run_keys):
        _reject("Stage-0 handoff runId/nonce pairs must be unique per task")
    preflights = tuple(
        _BootstrapTaskObjectPreflightV1(
            signed.approval,
            signed.receipt,
            handoff,
        )
        for signed, handoff in zip(signed_objects, handoff_preflights)
    )
    for task_object in preflights:
        _require_bootstrap_task_object_input_joins(
            task_object,
            snapshot_content,
            required_preflight,
        )

    _finalize_required_test_set(required_preflight)
    finalized_approvals = tuple(
        _finalize_task_approval(
            task_object.approval,
            required_preflight.policy,
        )
        for task_object in preflights
    )
    referenced_reports = {
        review.reportDigest.bytes: review.reportDigest
        for approval, _ in finalized_approvals
        for review in approval.independentReviews
    }
    expected_report_digests = tuple(
        referenced_reports[digest_bytes]
        for digest_bytes in sorted(referenced_reports)
    )
    if report_digests != expected_report_digests:
        _reject(
            "reviewReports do not match the verified TaskApproval digest union"
        )
    for task_object, (_, approval_ref) in zip(
        preflights,
        finalized_approvals,
    ):
        if task_object.receipt.receipt.taskApproval.digest != approval_ref.digest:
            _reject(
                "task receipt TaskApprovalRefV1 digest does not match exact bytes"
            )
    finalized_receipts = tuple(
        _finalize_bootstrap_task_verifier_receipt(
            task_object.receipt,
            required_preflight.policy,
        )
        for task_object in preflights
    )
    verified = tuple(
        _VerifiedBootstrapTaskObjectV1(
            approval,
            approval_ref,
            receipt,
            receipt_ref,
            task_object.handoff.handoffRef,
        )
        for task_object, (approval, approval_ref), (receipt, receipt_ref) in zip(
            preflights,
            finalized_approvals,
            finalized_receipts,
        )
    )
    receipt_ref_by_task = {
        task_object.receiptRef.taskId: task_object.receiptRef
        for task_object in verified
    }
    for task_object in verified:
        expected_refs = tuple(
            receipt_ref_by_task[dependency_id]
            for dependency_id in row_by_task[
                task_object.approval.taskId
            ].dependencies
        )
        if task_object.approval.dependencyCompletions != expected_refs:
            _reject(
                "TaskApprovalV1 dependency receipt refs do not match exact bytes"
            )
    return _BootstrapTaskObjectGraphV1(
        verified[0],
        verified[1:],
    )


def verifyBootstrapTaskObjects(
    subject: BootstrapTaskSubjectV1,
    objects: BootstrapTaskObjectSetV1,
) -> Union[ObjectVerifiedV1, Rejected]:
    """Validate the frozen shell, retaining fail-closed object semantics.

    The signed root/dependency approval, receipt, RequiredSet, policy,
    run-specific handoff graph, and exact raw review-report digest union are
    verified here.  PHASE-4 raw content, evidence objects, reviewer provenance,
    and protected provenance remain open, so the function can only return the
    stable rejection, never ObjectVerifiedV1.
    """
    try:
        _validate_subject(subject)
        _parse_bootstrap_task_object_graph(subject, objects)
    except Rejected as rejected:
        return rejected
    except (TypeError, ValueError, UnicodeError, AttributeError) as error:
        return Rejected(BOOTSTRAP_REJECTION, f"invalid process-local input: {error}")
    return Rejected(
        BOOTSTRAP_REJECTION,
        "bootstrap object/provenance joins are not complete",
    )
