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
class BootstrapTaskObjectSetV1:
    authorityPolicyBytes: bytes
    stage0HandoffBytes: bytes
    requiredTestSetBytes: bytes
    taskApprovalBytes: bytes
    taskReceiptBytes: bytes
    dependencyApprovalBytes: Tuple[bytes, ...]
    dependencyReceiptBytes: Tuple[bytes, ...]
    evidenceObjectBytes: Tuple[bytes, ...]
    reviewReports: Tuple[object, ...]


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
_LOWERCASE_COMMIT_RE = re.compile(r"[0-9a-f]{40}")
_GREGORIAN_DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
_DEVELOPMENT_A0_TEST_IDS = tuple(
    f"TST-A0-{index:03d}" for index in range(1, 21)
)
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


def _parse_phase5_frontmatter(
    data: bytes,
) -> tuple[dict[str, str], int]:
    if not data.startswith(b"---\n"):
        _reject("PHASE-5 snapshot lacks the exact opening frontmatter delimiter")
    closing = data.find(b"\n---\n", 4)
    if closing < 0:
        _reject("PHASE-5 snapshot lacks the exact closing frontmatter delimiter")
    try:
        frontmatter_text = data[4:closing].decode("utf-8", errors="strict")
    except UnicodeError:
        _reject("PHASE-5 frontmatter is not UTF-8")
    metadata: dict[str, str] = {}
    for line_number, line in enumerate(frontmatter_text.split("\n"), start=2):
        if line == "":
            continue
        separator = line.find(": ")
        if separator <= 0:
            _reject(f"PHASE-5 frontmatter line {line_number} is not key: value")
        key = line[:separator]
        value = line[separator + 2:]
        if (not value or key != key.strip() or value != value.strip()
                or key in metadata):
            _reject(f"PHASE-5 frontmatter line {line_number} is noncanonical")
        metadata[key] = value
    if set(metadata) != _PHASE5_FRONTMATTER_FIELDS:
        _reject("PHASE-5 frontmatter field set is not exact")
    if (metadata["id"] != "PHASE-5"
            or metadata["status"] != "accepted"
            or metadata["normative"] != "true"
            or metadata["openFindings"] != "none"):
        _reject("PHASE-5 frontmatter is not an accepted normative document")
    _parse_gregorian_date(metadata["updated"], "PHASE-5.updated")
    _parse_gregorian_date(metadata["approvedAt"], "PHASE-5.approvedAt")
    if _LOWERCASE_COMMIT_RE.fullmatch(metadata["reviewCommit"]) is None:
        _reject("PHASE-5.reviewCommit must be 40 lowercase hex digits")
    _parse_review_link(metadata["reviewLink"], "PHASE-5.reviewLink")
    return metadata, closing + len(b"\n---\n")


def _parse_phase5_approvers(value: str) -> Tuple[str, ...]:
    approver_values = tuple(value.split(", "))
    if (not value or ", ".join(approver_values) != value
            or not 1 <= len(approver_values) <= 256):
        _reject("PHASE-5.approvers must use the exact bounded ', ' grammar")
    approvers = tuple(
        _require_safe_id(approver, f"PHASE-5.approvers[{index}]")
        for index, approver in enumerate(approver_values)
    )
    if (approvers != tuple(sorted(approvers))
            or len(set(approvers)) != len(approvers)):
        _reject("PHASE-5.approvers must be unique ascending ASCII safe-id")
    return approvers


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


def parse_phase5_snapshot_content(
    phase5_snapshot: BootstrapDocumentSnapshotV1,
) -> Phase5SnapshotContentV1:
    """Derive PHASE-5 metadata and its formal test denominator from bytes."""
    if type(phase5_snapshot) is not BootstrapDocumentSnapshotV1:
        _reject("phase5_snapshot must be exact BootstrapDocumentSnapshotV1")
    if (type(phase5_snapshot.id) is not str
            or type(phase5_snapshot.path) is not str
            or phase5_snapshot.id != "PHASE-5"
            or phase5_snapshot.path != _PHASE5_DOCUMENT_PATH):
        _reject("PHASE-5 snapshot identity/path is not canonical")
    data = phase5_snapshot.bytes
    if type(data) is not bytes or not 1 <= len(data) <= MAX_INPUT_BYTES:
        _reject("PHASE-5 snapshot bytes must be 1..4 MiB")
    if data.startswith(b"\xef\xbb\xbf") or b"\x00" in data or b"\r" in data:
        _reject("PHASE-5 snapshot contains a forbidden byte sequence")
    if not data.endswith(b"\n"):
        _reject("PHASE-5 snapshot must end with LF")
    line_count = data.count(b"\n")
    if not 1 <= line_count <= MAX_DOCUMENT_LINES:
        _reject("PHASE-5 snapshot line count is outside 1..100000")
    raw_lines = data[:-1].split(b"\n")
    if any(len(line) > MAX_DOCUMENT_LINE_BYTES for line in raw_lines):
        _reject("PHASE-5 snapshot line exceeds 65536 UTF-8 bytes")
    try:
        data.decode("utf-8", errors="strict")
    except UnicodeError:
        _reject("PHASE-5 snapshot is not strict UTF-8")

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


def _parse_required_set_signatures(
    value: object,
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
) -> Tuple[ApprovalSignatureV1, ...]:
    where = "RequiredTestSetV1.signatures"
    maximum = min(len(principals), 256)
    if type(value) is not list or not 1 <= len(value) <= maximum:
        _reject(f"{where} count exceeds the resolved authority policy")
    assert isinstance(value, list)
    principal_by_key = {principal.keyId: principal for principal in principals}
    signatures = []
    for index, entry in enumerate(value):
        entry_where = f"{where}[{index}]"
        obj = _require_exact_keys(
            entry, _APPROVAL_SIGNATURE_FIELDS, entry_where
        )
        key_id = _require_safe_id(obj["keyId"], f"{entry_where}.keyId")
        if obj["algorithm"] != "ed25519":
            _reject(f"{entry_where}.algorithm must be ed25519")
        encoded_signature = obj["signature"]
        if (type(encoded_signature) is not str
                or _ED25519_SIGNATURE_RE.fullmatch(encoded_signature) is None):
            _reject(
                f"{entry_where}.signature must be 64-byte lowercase hex"
            )
        assert isinstance(encoded_signature, str)
        if key_id not in principal_by_key:
            _reject(f"{entry_where}.keyId is not in the authority policy")
        signatures.append(ApprovalSignatureV1(
            key_id,
            "ed25519",
            bytes.fromhex(encoded_signature),
        ))
    result = tuple(signatures)
    key_ids = tuple(signature.keyId for signature in result)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _reject(f"{where} must have unique ascending keyId")
    return result


def _require_signature_rule(
    signatures: Tuple[ApprovalSignatureV1, ...],
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    rule: ApprovalRuleV1,
) -> None:
    principal_by_key = {principal.keyId: principal for principal in principals}
    signed_principals = tuple(
        principal_by_key[signature.keyId] for signature in signatures
    )
    distinct_principal_ids = {
        principal.principalId for principal in signed_principals
    }
    if len(distinct_principal_ids) < rule.minimumDistinctSigners:
        _reject("RequiredTestSetV1 signatures do not satisfy distinct-principal quorum")
    signed_roles = {
        role for principal in signed_principals for role in principal.roles
    }
    if not set(rule.requiredRoles).issubset(signed_roles):
        _reject("RequiredTestSetV1 signatures do not cover required roles")


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
    )
    principal_by_key = {
        principal.keyId: principal for principal in preflight.policy.principals
    }
    for signature in preflight.requiredTestSet.signatures:
        principal = principal_by_key[signature.keyId]
        if not verify_ed25519(
            principal.publicKey,
            preflight.signatureMessage,
            signature.signature,
        ):
            _reject(f"RequiredTestSetV1 signature {signature.keyId} is invalid")
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
    if snapshot_content.document != preflight.requiredTestSet.phase5Document:
        _reject("RequiredTestSetV1 PHASE-5 document ref does not match snapshot")
    if (snapshot_content.requiredTestIds
            != preflight.requiredTestSet.requiredTestIds):
        _reject("RequiredTestSetV1 denominator does not match PHASE-5 catalog")
    return _finalize_required_test_set(preflight)


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
            or TASK_ID_RE.fullmatch(subject.rootTaskId) is None):
        _reject("rootTaskId is invalid")
    if type(subject.taskRows) is not tuple or not subject.taskRows:
        _reject("taskRows must be non-empty")
    for row in subject.taskRows:
        if type(row) is not BootstrapTaskRowSubjectV1:
            _reject("taskRows contain an untyped row")
        if (type(row.taskId) is not str
                or TASK_ID_RE.fullmatch(row.taskId) is None):
            _reject("task row ID is invalid")
    task_ids = tuple(row.taskId for row in subject.taskRows)
    if task_ids != tuple(sorted(task_ids)) or len(set(task_ids)) != len(task_ids):
        _reject("taskRows must be unique and sorted")
    if subject.rootTaskId not in task_ids:
        _reject("root task row is missing")
    for row in subject.taskRows:
        _require_sorted_unique(row.dependencies, f"{row.taskId}.dependencies", nonempty=False)
        _require_sorted_unique(row.testIds, f"{row.taskId}.testIds", nonempty=True)
        _require_sorted_unique(row.evidenceIds, f"{row.taskId}.evidenceIds", nonempty=True)
        if any(TASK_ID_RE.fullmatch(value) is None for value in row.dependencies):
            _reject("dependency task ID is invalid")
        if any(TEST_ID_RE.fullmatch(value) is None for value in row.testIds):
            _reject("test ID is invalid")
        if any(EVIDENCE_ID_RE.fullmatch(value) is None for value in row.evidenceIds):
            _reject("evidence ID is invalid")
        if type(row.prerequisites) is not tuple:
            _reject("prerequisites must be a tuple")
        prerequisite_ids = []
        for prerequisite in row.prerequisites:
            obj = _require_exact_keys(
                prerequisite, ("documentId", "requiredStatus"), "prerequisite")
            if obj["requiredStatus"] != "accepted" or type(obj["documentId"]) is not str:
                _reject("prerequisite must require accepted")
            prerequisite_ids.append(obj["documentId"])
        if prerequisite_ids != sorted(prerequisite_ids) or len(set(prerequisite_ids)) != len(prerequisite_ids):
            _reject("prerequisites must be unique and sorted")

    if type(subject.evidenceRows) is not tuple or not subject.evidenceRows:
        _reject("evidenceRows must be non-empty")
    evidence_ids = []
    for row in subject.evidenceRows:
        if type(row) is not BootstrapLedgerSubjectV1:
            _reject("evidenceRows contain an untyped row")
        if (type(row.id) is not str or EVIDENCE_ID_RE.fullmatch(row.id) is None
                or type(row.taskId) is not str
                or TASK_ID_RE.fullmatch(row.taskId) is None):
            _reject("evidence row identity is invalid")
        if row.grade != "bootstrap" or row.result != "passed":
            _reject("bootstrap ledger row must be passed")
        _require_sorted_unique(row.testIds, f"{row.id}.testIds", nonempty=True)
        evidence_ids.append(row.id)
    if evidence_ids != sorted(evidence_ids) or len(set(evidence_ids)) != len(evidence_ids):
        _reject("evidenceRows must be unique and sorted")
    expected_evidence = sorted(
        evidence_id for row in subject.taskRows for evidence_id in row.evidenceIds
    )
    if evidence_ids != expected_evidence:
        _reject("evidenceRows do not match task row evidence IDs")

    if type(subject.documents) is not tuple or not subject.documents:
        _reject("documents must be non-empty")
    document_ids = []
    document_paths = []
    for document in subject.documents:
        if type(document) is not BootstrapDocumentSnapshotV1:
            _reject("documents contain an untyped snapshot")
        if type(document.id) is not str or type(document.bytes) is not bytes:
            _reject("document snapshot fields are invalid")
        document_ids.append(document.id)
        document_paths.append(_require_project_path(document.path))
    if document_ids != sorted(document_ids) or len(set(document_ids)) != len(document_ids):
        _reject("documents must be unique and sorted by ID")
    if len(set(document_paths)) != len(document_paths):
        _reject("document paths must be unique")


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
        decode_canonical_pf_jcs(encoded)
    for field in (
        "dependencyApprovalBytes", "dependencyReceiptBytes", "evidenceObjectBytes",
    ):
        values = getattr(objects, field)
        if type(values) is not tuple:
            _reject(f"{field} must be a tuple")
        for encoded in values:
            if type(encoded) is not bytes or not encoded:
                _reject(f"{field} contains invalid bytes")
            decode_canonical_pf_jcs(encoded)
    if type(objects.reviewReports) is not tuple:
        _reject("reviewReports must be a tuple")


def verifyBootstrapTaskObjects(
    subject: BootstrapTaskSubjectV1,
    objects: BootstrapTaskObjectSetV1,
) -> Union[ObjectVerifiedV1, Rejected]:
    """Validate the frozen shell, retaining fail-closed object semantics.

    Full policy/approval/receipt verification is intentionally not claimed by
    this initial slice.  Until that graph is complete the function can only
    return the stable rejection, never ObjectVerifiedV1.
    """
    try:
        _validate_subject(subject)
        _validate_object_shell(objects)
        phase5_snapshot = next(
            (
                document for document in subject.documents
                if document.id == "PHASE-5"
            ),
            None,
        )
        if phase5_snapshot is None:
            _reject("subject lacks the PHASE-5 document snapshot")
        parse_document_bound_required_test_set(
            objects.requiredTestSetBytes,
            objects.authorityPolicyBytes,
            phase5_snapshot,
        )
    except Rejected as rejected:
        return rejected
    except (TypeError, ValueError, UnicodeError, AttributeError) as error:
        return Rejected(BOOTSTRAP_REJECTION, f"invalid process-local input: {error}")
    return Rejected(
        BOOTSTRAP_REJECTION,
        "bootstrap policy/approval/receipt graph verification is not complete",
    )
