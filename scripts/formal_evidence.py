#!/usr/bin/env python3
"""Pure, dependency-free consumer for the formal evidence finalization family.

This module validates the five formal input object types
(SessionContainmentReceiptV1, FreshnessAuthoritySnapshotV1,
PrivateScanReceiptV1, RevocationLedgerSnapshotV1,
FormalFinalizerIdentityV1) and the root
``proof-forge.formal-evidence-finalization.v1`` record against exact
caller-supplied authority inputs, reusing the sibling bootstrap consumer's
validators read-only.  It performs no filesystem, socket, environment, or
CLI I/O.

The four signed inputs are verified only under the single resolved external
authority policy's exact rule (sessionContainmentRule /
freshnessAuthorityRule / privateScanRule / revocationSnapshotRule); every
statement/signature/digest domain follows the frozen tables in
gate-catalog-finalization 1732-1755.  The revocation ledger validates the
spec-pinned aggregate
``recordsDigest = SHA-256("pf.revocation-ledger-records.v1" || NUL ||
concat(u32be(size) || digest.bytes))`` and, when record bytes are supplied,
recomputes each record digest and the ``previousRecordSha256`` chain
(genesis is 64 zero hex, each subsequent link is the plain SHA-256 of the
previous record's canonical bytes; the evidence-revocation payload schema
itself remains owned by TRACE-EV-001 and is not redefined here).

Boundaries deliberately left to later slices (declared, not implemented):
EV content resolution (passed/qualification/candidate binding of each
evidenceRef), retained-member completeness of the private scan beyond the
ref-level coverage validated here, the formal freshness window evaluation
against the authority snapshot (the cited spec pins only nonzero
maximumAgeSeconds and ``finalizedAt < expiresAt``), publication path I/O,
support-binding production, and eligible runner/containment integration.
Every failure is a single coded ``Rejected`` carrying
``PF-EVIDENCE-FORMAL-UNVERIFIED``.
"""

from __future__ import annotations

import hashlib
import importlib.util
import re
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Optional, Tuple


_CONSUMER_ABI_NAMES = (
    "Rejected",
    "Digest",
    "ContentRef",
    "CandidateIdentity",
    "ApprovalSignatureV1",
    "BootstrapAuthorityPolicyV1",
    "BootstrapApprovalVerifierReceiptRefV1",
    "GateCatalogRefV1",
    "BootstrapDocumentSnapshotV1",
    "canonical_pf_jcs",
    "decode_canonical_pf_jcs",
    "parse_digest",
    "parse_content_ref",
    "parse_candidate_identity",
    "parse_bootstrap_authority_policy",
    "parse_document_bound_required_test_set",
    "parse_bootstrap_approval_set",
    "parse_bootstrap_approval_verifier_receipt",
    "parse_formal_gate_catalog_approval",
    "verify_ed25519",
    "PROFILE_ID_RE",
    "SAFE_ID_RE",
    "_require_ascii_text",
    "_require_semver",
    "_require_safe_id",
    "_require_exact_keys",
    "_parse_compact_gregorian_id",
    "_parse_approval_signatures_syntax",
    "_require_signature_policy_membership",
    "_require_signature_rule",
    "_verify_approval_signatures",
    "_parse_gate_catalog_ref",
    "_preflight_formal_gate_catalog",
    "_preflight_eligible_stage0_handoff",
    "EVIDENCE_ID_RE",
    "TEST_ID_RE",
    "BAV_ID_RE",
)


def _load_bootstrap_task_objects() -> ModuleType:
    """Load the exact sibling consumer module without a sys.path authority seam."""
    module_path = Path(__file__).resolve(strict=True)
    consumer_path = module_path.with_name("bootstrap_task_objects.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_task_objects_for_formal_evidence",
        consumer_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact bootstrap task consumer loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != consumer_path.resolve(strict=True):
        raise ImportError("exact bootstrap task consumer origin changed")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    for name in _CONSUMER_ABI_NAMES:
        if getattr(module, name, None) is None:
            raise ImportError("exact bootstrap task consumer ABI changed")
    return module


_CONSUMER = _load_bootstrap_task_objects()

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef
CandidateIdentity = _CONSUMER.CandidateIdentity
ApprovalSignatureV1 = _CONSUMER.ApprovalSignatureV1
BootstrapAuthorityPolicyV1 = _CONSUMER.BootstrapAuthorityPolicyV1
BootstrapApprovalVerifierReceiptRefV1 = (
    _CONSUMER.BootstrapApprovalVerifierReceiptRefV1
)
GateCatalogRefV1 = _CONSUMER.GateCatalogRefV1
canonical_pf_jcs = _CONSUMER.canonical_pf_jcs
decode_canonical_pf_jcs = _CONSUMER.decode_canonical_pf_jcs
parse_digest = _CONSUMER.parse_digest
parse_content_ref = _CONSUMER.parse_content_ref
parse_candidate_identity = _CONSUMER.parse_candidate_identity

FORMAL_EVIDENCE_REJECTION = "PF-EVIDENCE-FORMAL-UNVERIFIED"
MAX_SAFE_INTEGER = (1 << 53) - 1
EVF_ID_RE = re.compile(r"EVF-[0-9]{8}-[0-9]{4}")
RVK_ID_RE = re.compile(r"RVK-[0-9]{8}-[0-9]{4}")
TARGET_ID_RE = re.compile(r"[a-z][a-z0-9-]{0,31}")
UTC_INSTANT_RE = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
)
FINALIZATION_SCHEMA = "proof-forge.formal-evidence-finalization.v1"
CONTAINMENT_SCHEMA = "proof-forge.session-containment-receipt.v1"
FRESHNESS_SCHEMA = "proof-forge.freshness-authority-snapshot.v1"
PRIVATE_SCAN_SCHEMA = "proof-forge.private-scan-receipt.v1"
REVOCATION_SCHEMA = "proof-forge.revocation-ledger-snapshot.v1"
FINALIZER_SCHEMA = "proof-forge.formal-finalizer-identity.v1"
REVOCATION_RECORD_SCHEMA = "proof-forge.evidence-revocation.v1"
_D0_GATE_TASK_IDS = frozenset(f"TASK-D0-{index:02d}" for index in range(1, 8))


def _is_external_policy_abi(policy: object) -> bool:
    """Accept the exact policy ABI across pinned sibling module namespaces.

    Exact-path loaders intentionally create distinct Python class identities.
    A caller that already parsed the same closed wire through its own pinned
    sibling must not fail solely because ``type`` objects differ.  The formal
    parsers still verify every signature/rule/content field below.
    """
    fields = (
        "schema", "id", "version", "principals", "taskRules",
        "requiredTestSetRule", "formalCatalogRule", "bootstrapSetRule",
        "sessionContainmentRule", "freshnessAuthorityRule",
        "privateScanRule", "privateScanPolicy", "revocationSnapshotRule",
        "authorityStoreService", "verifier",
    )
    if not all(hasattr(policy, field) for field in fields):
        return False
    principals = getattr(policy, "principals", None)
    if type(principals) is not tuple or not principals:
        return False
    return all(
        all(hasattr(principal, field) for field in (
            "principalId", "keyId", "publicKey", "roles"
        ))
        for principal in principals
    )


class Rejected(Exception):
    """Stable formal-evidence rejection; details never grant authority."""

    def __init__(self, code: str = FORMAL_EVIDENCE_REJECTION,
                 detail: str = "") -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _reject(detail: str) -> NoReturn:
    raise Rejected(FORMAL_EVIDENCE_REJECTION, detail)


def _consumer_checked(validation, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _reject(detail)


@dataclass(frozen=True)
class ContainmentDescendantV1:
    pid: int
    parentPid: int
    startToken: int
    sessionId: int
    executableDigest: Digest
    termination: str


@dataclass(frozen=True)
class EscapeProbeV1:
    id: str
    result: str


@dataclass(frozen=True)
class SessionContainmentReceiptV1:
    schema: str
    id: str
    version: str
    candidate: CandidateIdentity
    stage0Handoff: ContentRef
    supervisorDigest: Digest
    rootSessionId: str
    descendants: Tuple[ContainmentDescendantV1, ...]
    escapeProbes: Tuple[EscapeProbeV1, ...]
    startedAt: str
    finishedAt: str
    result: str
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class FreshnessAuthoritySnapshotV1:
    schema: str
    id: str
    version: str
    authorityPolicy: ContentRef
    observedAt: str
    maximumAgeSeconds: int
    clockSourceDigest: Digest
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class ScannedMemberRefV1:
    evidence: Tuple[str, Digest]
    role: str
    path: str
    size: int
    digest: Digest


@dataclass(frozen=True)
class PrivateScanReceiptV1:
    schema: str
    id: str
    version: str
    candidate: CandidateIdentity
    evidenceCoreDigest: Digest
    scannerDigest: Digest
    policy: ContentRef
    scannedEvidenceRefs: Tuple[Tuple[str, Digest], ...]
    scannedMembers: Tuple[ScannedMemberRefV1, ...]
    findings: Tuple[object, ...]
    result: str
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class RevocationRecordRefV1:
    schema: str
    id: str
    version: str
    digest: Digest


@dataclass(frozen=True)
class RevocationLedgerSnapshotV1:
    schema: str
    id: str
    version: str
    authorityPolicy: ContentRef
    records: Tuple[RevocationRecordRefV1, ...]
    head: Optional[RevocationRecordRefV1]
    recordsDigest: Digest
    signatures: Tuple[ApprovalSignatureV1, ...]


@dataclass(frozen=True)
class FormalFinalizerIdentityV1:
    schema: str
    id: str
    version: str
    executableDigest: Digest
    closureDigest: Digest
    toolchainLockDigest: Digest


@dataclass(frozen=True)
class BuildIdentityV1:
    targetId: str
    targetSemanticsVersion: str
    targetSemanticsDigest: Digest
    codegenProfileId: str
    codegenProfileDigest: Digest


@dataclass(frozen=True)
class FormalGateV1:
    id: str
    testIds: Tuple[str, ...]
    build: Optional[BuildIdentityV1]
    evidenceRefs: Tuple[Tuple[str, Digest], ...]


@dataclass(frozen=True)
class BootstrapApprovalBindingV1:
    set: ContentRef
    verifierReceipt: BootstrapApprovalVerifierReceiptRefV1


@dataclass(frozen=True)
class FormalEvidenceFinalizationV1:
    schema: str
    id: str
    qualification: str
    candidate: CandidateIdentity
    hostProfile: ContentRef
    stage0Handoff: ContentRef
    sessionContainment: ContentRef
    requiredTestSet: ContentRef
    catalog: GateCatalogRefV1
    catalogApproval: ContentRef
    gates: Tuple[FormalGateV1, ...]
    evidenceCoreDigest: Digest
    evidenceSetDigest: Digest
    freshnessAuthority: ContentRef
    finalizedAt: str
    expiresAt: str
    privateScan: ContentRef
    revocationLedger: ContentRef
    finalizer: ContentRef
    bootstrapApproval: BootstrapApprovalBindingV1


@dataclass(frozen=True)
class FinalizationRefV1:
    schema: str
    id: str
    digest: Digest


def _require_utc_instant(value: object, where: str) -> str:
    if type(value) is not str or UTC_INSTANT_RE.fullmatch(value) is None:
        _reject(f"{where} must be a UtcInstant seconds-precision wire value")
    assert isinstance(value, str)
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        _reject(f"{where} must be a real UTC instant")
    return value


def _require_u64(value: object, where: str) -> int:
    if type(value) is not int or not 0 <= value <= MAX_SAFE_INTEGER:
        _reject(f"{where} must be a UInt64 not above 2^53-1")
    assert isinstance(value, int)
    return value


def _require_evidence_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._parse_compact_gregorian_id(
            value, _CONSUMER.EVIDENCE_ID_RE, 3, where
        ),
        f"{where} must be a real EV-YYYYMMDD-NNNN id",
    )


def _require_evf_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._parse_compact_gregorian_id(
            value, EVF_ID_RE, 4, where
        ),
        f"{where} must be a real EVF-YYYYMMDD-NNNN id",
    )


def _require_rvk_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._parse_compact_gregorian_id(
            value, RVK_ID_RE, 4, where
        ),
        f"{where} must be a real RVK-YYYYMMDD-NNNN id",
    )


def _require_profile_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_ascii_text(
            value, _CONSUMER.PROFILE_ID_RE, where, 127
        ),
        f"{where} must use the ContentRef id grammar",
    )


def _require_semver(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_semver(value, where),
        f"{where} must be exact SemVer",
    )


def _require_safe_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_safe_id(value, where),
        f"{where} must be an ASCII safe-id",
    )


def _require_digest(value: object, where: str) -> Digest:
    return _consumer_checked(
        lambda: parse_digest(value),
        f"{where} must be the SPEC-COMMON Digest wire form",
    )


def _require_content_ref(value: object, where: str) -> ContentRef:
    return _consumer_checked(
        lambda: parse_content_ref(value),
        f"{where} must be a full ContentRef, not a bare digest",
    )


def _require_project_path(value: object, where: str) -> str:
    if type(value) is not str:
        _reject(f"{where} must be a ProjectRelativePath")
    assert isinstance(value, str)
    try:
        encoded = value.encode("utf-8")
    except UnicodeError:
        _reject(f"{where} must be valid UTF-8")
    if not 1 <= len(encoded) <= 1024:
        _reject(f"{where} must be 1..1024 UTF-8 bytes")
    if value.startswith("/") or "\\" in value:
        _reject(f"{where} must not be absolute or contain a backslash")
    segments = value.split("/")
    if any(segment in ("", ".", "..") for segment in segments):
        _reject(f"{where} must not contain empty/dot segments")
    if len(value) > 1 and value[1] == ":":
        _reject(f"{where} must not use a drive prefix")
    if any(unicodedata.category(character) == "Cc" for character in value):
        _reject(f"{where} must not contain control characters")
    return value


def _require_unique_sorted(values: tuple, key, where: str) -> None:
    keys = [key(value) for value in values]
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        _reject(f"{where} must be unique ascending")


def _verify_signed_input(
    obj: dict,
    fields: Tuple[str, ...],
    policy: BootstrapAuthorityPolicyV1,
    rule,
    statement_domain: bytes,
    signature_domain: bytes,
    where: str,
) -> None:
    statement = {field: obj[field] for field in fields[:-1]}
    statement_digest = hashlib.sha256(
        statement_domain + canonical_pf_jcs(statement)
    ).digest()
    message = signature_domain + statement_digest
    signatures = _consumer_checked(
        lambda: _CONSUMER._parse_approval_signatures_syntax(
            obj["signatures"], f"{where}.signatures"
        ),
        f"{where}.signatures are malformed",
    )
    _consumer_checked(
        lambda: _CONSUMER._require_signature_policy_membership(
            signatures, policy.principals, f"{where}.signatures"
        ),
        f"{where}.signatures are not in the external policy",
    )
    _consumer_checked(
        lambda: _CONSUMER._require_signature_rule(
            signatures, policy.principals, rule, f"{where}.signatures"
        ),
        f"{where}.signatures do not satisfy the exact policy rule",
    )
    _consumer_checked(
        lambda: _CONSUMER._verify_approval_signatures(
            signatures, policy.principals, message, f"{where}.signatures"
        ),
        f"{where}.signatures failed Ed25519 verification",
    )


def _content_ref_for(schema: str, identifier: str, version: str,
                     domain: bytes, payload: bytes) -> ContentRef:
    return ContentRef(
        schema,
        identifier,
        version,
        Digest("sha256", hashlib.sha256(domain + payload).digest()),
    )


_CONTAINMENT_FIELDS = (
    "schema",
    "id",
    "version",
    "candidate",
    "stage0Handoff",
    "supervisorDigest",
    "rootSessionId",
    "descendants",
    "escapeProbes",
    "startedAt",
    "finishedAt",
    "result",
    "signatures",
)
_FRESHNESS_FIELDS = (
    "schema",
    "id",
    "version",
    "authorityPolicy",
    "observedAt",
    "maximumAgeSeconds",
    "clockSourceDigest",
    "signatures",
)
_PRIVATE_SCAN_FIELDS = (
    "schema",
    "id",
    "version",
    "candidate",
    "evidenceCoreDigest",
    "scannerDigest",
    "policy",
    "scannedEvidenceRefs",
    "scannedMembers",
    "findings",
    "result",
    "signatures",
)
_REVOCATION_FIELDS = (
    "schema",
    "id",
    "version",
    "authorityPolicy",
    "records",
    "head",
    "recordsDigest",
    "signatures",
)
_FINALIZER_FIELDS = (
    "schema",
    "id",
    "version",
    "executableDigest",
    "closureDigest",
    "toolchainLockDigest",
)
_RECORD_FIELDS = (
    "schema",
    "id",
    "qualification",
    "candidate",
    "hostProfile",
    "stage0Handoff",
    "sessionContainment",
    "requiredTestSet",
    "catalog",
    "catalogApproval",
    "gates",
    "evidenceCoreDigest",
    "evidenceSetDigest",
    "freshnessAuthority",
    "finalizedAt",
    "expiresAt",
    "privateScan",
    "revocationLedger",
    "finalizer",
    "bootstrapApproval",
)
_EVIDENCE_REF_KEYS = ("id", "digest")


def _parse_evidence_ref(value: object, where: str) -> Tuple[str, Digest]:
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(value, _EVIDENCE_REF_KEYS, where),
        f"{where} must be a closed EvidenceRef",
    )
    return (
        _require_evidence_id(obj["id"], f"{where}.id"),
        _require_digest(obj["digest"], f"{where}.digest"),
    )


def parse_session_containment_receipt(
    receipt_bytes: bytes,
    policy: BootstrapAuthorityPolicyV1,
) -> SessionContainmentReceiptV1:
    """Validate a signed SessionContainmentReceiptV1 under the policy rule."""
    if not _is_external_policy_abi(policy):
        _reject("session containment verification requires the external policy")
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(receipt_bytes),
        "session containment receipt bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _CONTAINMENT_FIELDS, "SessionContainmentReceiptV1"
        ),
        "SessionContainmentReceiptV1 must be a closed object",
    )
    if obj["schema"] != CONTAINMENT_SCHEMA:
        _reject("SessionContainmentReceiptV1.schema is not v1")
    identifier = _require_profile_id(obj["id"], "SessionContainmentReceiptV1.id")
    version = _require_semver(obj["version"], "SessionContainmentReceiptV1.version")
    candidate = _consumer_checked(
        lambda: parse_candidate_identity(obj["candidate"]),
        "SessionContainmentReceiptV1.candidate is invalid",
    )
    stage0_handoff = _require_content_ref(
        obj["stage0Handoff"], "SessionContainmentReceiptV1.stage0Handoff"
    )
    supervisor_digest = _require_digest(
        obj["supervisorDigest"], "SessionContainmentReceiptV1.supervisorDigest"
    )
    root_session_id = _require_safe_id(
        obj["rootSessionId"], "SessionContainmentReceiptV1.rootSessionId"
    )
    descendant_values = obj["descendants"]
    if type(descendant_values) is not list:
        _reject("SessionContainmentReceiptV1.descendants must be an array")
    descendants = []
    for index, entry in enumerate(descendant_values):
        where = f"SessionContainmentReceiptV1.descendants[{index}]"
        entry_obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry,
                (
                    "pid",
                    "parentPid",
                    "startToken",
                    "sessionId",
                    "executableDigest",
                    "termination",
                ),
                where,
            ),
            f"{where} must be a closed descendant",
        )
        if entry_obj["termination"] not in ("exited", "killed"):
            _reject(f"{where}.termination must be exited|killed")
        descendants.append(ContainmentDescendantV1(
            _require_u64(entry_obj["pid"], f"{where}.pid"),
            _require_u64(entry_obj["parentPid"], f"{where}.parentPid"),
            _require_u64(entry_obj["startToken"], f"{where}.startToken"),
            _require_u64(entry_obj["sessionId"], f"{where}.sessionId"),
            _require_digest(
                entry_obj["executableDigest"], f"{where}.executableDigest"
            ),
            entry_obj["termination"],
        ))
    descendants = tuple(descendants)
    _require_unique_sorted(
        descendants,
        lambda item: (
            item.pid, item.parentPid, item.startToken, item.sessionId,
            item.executableDigest.bytes, item.termination,
        ),
        "SessionContainmentReceiptV1.descendants",
    )
    probe_values = obj["escapeProbes"]
    if type(probe_values) is not list:
        _reject("SessionContainmentReceiptV1.escapeProbes must be an array")
    probes = []
    for index, entry in enumerate(probe_values):
        where = f"SessionContainmentReceiptV1.escapeProbes[{index}]"
        entry_obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry, ("id", "result"), where
            ),
            f"{where} must be a closed escape probe",
        )
        if entry_obj["result"] != "contained":
            _reject(f"{where}.result must be contained")
        probes.append(EscapeProbeV1(
            _require_safe_id(entry_obj["id"], f"{where}.id"),
            "contained",
        ))
    probes = tuple(probes)
    _require_unique_sorted(
        probes, lambda item: item.id, "SessionContainmentReceiptV1.escapeProbes"
    )
    started_at = _require_utc_instant(
        obj["startedAt"], "SessionContainmentReceiptV1.startedAt"
    )
    finished_at = _require_utc_instant(
        obj["finishedAt"], "SessionContainmentReceiptV1.finishedAt"
    )
    if obj["result"] != "contained":
        _reject("SessionContainmentReceiptV1.result must be contained")
    _verify_signed_input(
        obj,
        _CONTAINMENT_FIELDS,
        policy,
        policy.sessionContainmentRule,
        b"pf.session-containment-receipt-statement.v1\x00",
        b"pf.session-containment-receipt-signature.v1\x00",
        "SessionContainmentReceiptV1",
    )
    return SessionContainmentReceiptV1(
        CONTAINMENT_SCHEMA,
        identifier,
        version,
        candidate,
        stage0_handoff,
        supervisor_digest,
        root_session_id,
        descendants,
        probes,
        started_at,
        finished_at,
        "contained",
        _consumer_checked(
            lambda: _CONSUMER._parse_approval_signatures_syntax(
                obj["signatures"], "SessionContainmentReceiptV1.signatures"
            ),
            "SessionContainmentReceiptV1.signatures are malformed",
        ),
    )


def parse_freshness_authority_snapshot(
    snapshot_bytes: bytes,
    policy: BootstrapAuthorityPolicyV1,
) -> FreshnessAuthoritySnapshotV1:
    """Validate a signed FreshnessAuthoritySnapshotV1 under the policy rule."""
    if not _is_external_policy_abi(policy):
        _reject("freshness authority verification requires the external policy")
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(snapshot_bytes),
        "freshness authority snapshot bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _FRESHNESS_FIELDS, "FreshnessAuthoritySnapshotV1"
        ),
        "FreshnessAuthoritySnapshotV1 must be a closed object",
    )
    if obj["schema"] != FRESHNESS_SCHEMA:
        _reject("FreshnessAuthoritySnapshotV1.schema is not v1")
    identifier = _require_profile_id(obj["id"], "FreshnessAuthoritySnapshotV1.id")
    version = _require_semver(
        obj["version"], "FreshnessAuthoritySnapshotV1.version"
    )
    authority_policy = _require_content_ref(
        obj["authorityPolicy"], "FreshnessAuthoritySnapshotV1.authorityPolicy"
    )
    observed_at = _require_utc_instant(
        obj["observedAt"], "FreshnessAuthoritySnapshotV1.observedAt"
    )
    maximum_age = _require_u64(
        obj["maximumAgeSeconds"], "FreshnessAuthoritySnapshotV1.maximumAgeSeconds"
    )
    if maximum_age == 0:
        _reject("FreshnessAuthoritySnapshotV1.maximumAgeSeconds must be nonzero")
    clock_source = _require_digest(
        obj["clockSourceDigest"], "FreshnessAuthoritySnapshotV1.clockSourceDigest"
    )
    _verify_signed_input(
        obj,
        _FRESHNESS_FIELDS,
        policy,
        policy.freshnessAuthorityRule,
        b"pf.freshness-authority-snapshot-statement.v1\x00",
        b"pf.freshness-authority-snapshot-signature.v1\x00",
        "FreshnessAuthoritySnapshotV1",
    )
    return FreshnessAuthoritySnapshotV1(
        FRESHNESS_SCHEMA,
        identifier,
        version,
        authority_policy,
        observed_at,
        maximum_age,
        clock_source,
        _consumer_checked(
            lambda: _CONSUMER._parse_approval_signatures_syntax(
                obj["signatures"], "FreshnessAuthoritySnapshotV1.signatures"
            ),
            "FreshnessAuthoritySnapshotV1.signatures are malformed",
        ),
    )


def parse_private_scan_receipt(
    receipt_bytes: bytes,
    policy: BootstrapAuthorityPolicyV1,
) -> PrivateScanReceiptV1:
    """Validate a signed PrivateScanReceiptV1 under the policy rule."""
    if not _is_external_policy_abi(policy):
        _reject("private scan verification requires the external policy")
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(receipt_bytes),
        "private scan receipt bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _PRIVATE_SCAN_FIELDS, "PrivateScanReceiptV1"
        ),
        "PrivateScanReceiptV1 must be a closed object",
    )
    if obj["schema"] != PRIVATE_SCAN_SCHEMA:
        _reject("PrivateScanReceiptV1.schema is not v1")
    identifier = _require_profile_id(obj["id"], "PrivateScanReceiptV1.id")
    version = _require_semver(obj["version"], "PrivateScanReceiptV1.version")
    candidate = _consumer_checked(
        lambda: parse_candidate_identity(obj["candidate"]),
        "PrivateScanReceiptV1.candidate is invalid",
    )
    evidence_core_digest = _require_digest(
        obj["evidenceCoreDigest"], "PrivateScanReceiptV1.evidenceCoreDigest"
    )
    scanner_digest = _require_digest(
        obj["scannerDigest"], "PrivateScanReceiptV1.scannerDigest"
    )
    scan_policy = _require_content_ref(
        obj["policy"], "PrivateScanReceiptV1.policy"
    )
    refs_values = obj["scannedEvidenceRefs"]
    if type(refs_values) is not list:
        _reject("PrivateScanReceiptV1.scannedEvidenceRefs must be an array")
    scanned_refs = tuple(
        _parse_evidence_ref(
            entry, f"PrivateScanReceiptV1.scannedEvidenceRefs[{index}]"
        )
        for index, entry in enumerate(refs_values)
    )
    _require_unique_sorted(
        scanned_refs,
        lambda item: (item[0], item[1].bytes),
        "PrivateScanReceiptV1.scannedEvidenceRefs",
    )
    member_values = obj["scannedMembers"]
    if type(member_values) is not list:
        _reject("PrivateScanReceiptV1.scannedMembers must be an array")
    members = []
    for index, entry in enumerate(member_values):
        where = f"PrivateScanReceiptV1.scannedMembers[{index}]"
        entry_obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry, ("evidence", "role", "path", "size", "digest"), where
            ),
            f"{where} must be a closed ScannedMemberRefV1",
        )
        members.append(ScannedMemberRefV1(
            _parse_evidence_ref(entry_obj["evidence"], f"{where}.evidence"),
            _require_safe_id(entry_obj["role"], f"{where}.role"),
            _require_project_path(entry_obj["path"], f"{where}.path"),
            _require_u64(entry_obj["size"], f"{where}.size"),
            _require_digest(entry_obj["digest"], f"{where}.digest"),
        ))
    members = tuple(members)
    _require_unique_sorted(
        members,
        lambda item: (item.evidence[0], item.evidence[1].bytes, item.path),
        "PrivateScanReceiptV1.scannedMembers",
    )
    if obj["findings"] != []:
        _reject("PrivateScanReceiptV1.findings must be an empty array")
    if obj["result"] != "clean":
        _reject("PrivateScanReceiptV1.result must be clean")
    _verify_signed_input(
        obj,
        _PRIVATE_SCAN_FIELDS,
        policy,
        policy.privateScanRule,
        b"pf.private-scan-receipt-statement.v1\x00",
        b"pf.private-scan-receipt-signature.v1\x00",
        "PrivateScanReceiptV1",
    )
    return PrivateScanReceiptV1(
        PRIVATE_SCAN_SCHEMA,
        identifier,
        version,
        candidate,
        evidence_core_digest,
        scanner_digest,
        scan_policy,
        scanned_refs,
        members,
        (),
        "clean",
        _consumer_checked(
            lambda: _CONSUMER._parse_approval_signatures_syntax(
                obj["signatures"], "PrivateScanReceiptV1.signatures"
            ),
            "PrivateScanReceiptV1.signatures are malformed",
        ),
    )


def _parse_revocation_record_ref(
    value: object,
    where: str,
) -> RevocationRecordRefV1:
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            value, ("schema", "id", "version", "digest"), where
        ),
        f"{where} must be a closed RevocationRecordRefV1",
    )
    if obj["schema"] != REVOCATION_RECORD_SCHEMA:
        _reject(f"{where}.schema must be evidence-revocation.v1")
    identifier = _require_rvk_id(obj["id"], f"{where}.id")
    if obj["version"] != "1.0.0":
        _reject(f"{where}.version must be exactly 1.0.0")
    return RevocationRecordRefV1(
        REVOCATION_RECORD_SCHEMA,
        identifier,
        "1.0.0",
        _require_digest(obj["digest"], f"{where}.digest"),
    )


def parse_revocation_ledger_snapshot(
    snapshot_bytes: bytes,
    policy: BootstrapAuthorityPolicyV1,
    revocation_record_bytes: Tuple[bytes, ...] = (),
) -> RevocationLedgerSnapshotV1:
    """Validate a signed RevocationLedgerSnapshotV1 under the policy rule.

    ``revocation_record_bytes`` resolves the referenced records in ref
    order: each record's digest is recomputed and the
    ``previousRecordSha256`` chain is verified (genesis zero, then plain
    SHA-256 of the previous record's canonical bytes).
    """
    if not _is_external_policy_abi(policy):
        _reject("revocation ledger verification requires the external policy")
    if type(revocation_record_bytes) is not tuple or any(
        type(item) is not bytes for item in revocation_record_bytes
    ):
        _reject("revocation records must be supplied as exact bytes")
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(snapshot_bytes),
        "revocation ledger snapshot bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _REVOCATION_FIELDS, "RevocationLedgerSnapshotV1"
        ),
        "RevocationLedgerSnapshotV1 must be a closed object",
    )
    if obj["schema"] != REVOCATION_SCHEMA:
        _reject("RevocationLedgerSnapshotV1.schema is not v1")
    identifier = _require_profile_id(obj["id"], "RevocationLedgerSnapshotV1.id")
    version = _require_semver(
        obj["version"], "RevocationLedgerSnapshotV1.version"
    )
    authority_policy = _require_content_ref(
        obj["authorityPolicy"], "RevocationLedgerSnapshotV1.authorityPolicy"
    )
    records_values = obj["records"]
    if type(records_values) is not list:
        _reject("RevocationLedgerSnapshotV1.records must be an array")
    records = tuple(
        _parse_revocation_record_ref(
            entry, f"RevocationLedgerSnapshotV1.records[{index}]"
        )
        for index, entry in enumerate(records_values)
    )
    _require_unique_sorted(
        records, lambda item: item.id, "RevocationLedgerSnapshotV1.records"
    )
    head_value = obj["head"]
    if not records:
        if head_value is not None:
            _reject("RevocationLedgerSnapshotV1.head must be null when empty")
        head = None
    else:
        head = _parse_revocation_record_ref(
            head_value, "RevocationLedgerSnapshotV1.head"
        )
        if head != records[-1]:
            _reject("RevocationLedgerSnapshotV1.head must be the last record")
    aggregate = b"".join(
        len(ref.digest.bytes).to_bytes(4, "big") + ref.digest.bytes
        for ref in records
    )
    expected_records_digest = hashlib.sha256(
        b"pf.revocation-ledger-records.v1\x00" + aggregate
    ).digest()
    records_digest = _require_digest(
        obj["recordsDigest"], "RevocationLedgerSnapshotV1.recordsDigest"
    )
    if records_digest.bytes != expected_records_digest:
        _reject("RevocationLedgerSnapshotV1.recordsDigest mismatch")
    if revocation_record_bytes or records:
        if len(revocation_record_bytes) != len(records):
            _reject("revocation record bytes must resolve every ref exactly")
        previous_sha256 = b"\x00" * 32
        for index, (ref, record_bytes) in enumerate(
            zip(records, revocation_record_bytes)
        ):
            record_obj = _consumer_checked(
                lambda record_bytes=record_bytes: decode_canonical_pf_jcs(
                    record_bytes
                ),
                f"revocation record {ref.id} is not canonical PF-JCS",
            )
            if type(record_obj) is not dict:
                _reject(f"revocation record {ref.id} must be an object")
            recomputed = hashlib.sha256(
                b"pf.evidence-revocation.v1\x00" + record_bytes
            ).digest()
            if recomputed != ref.digest.bytes:
                _reject(f"revocation record {ref.id} digest mismatch")
            if record_obj.get("previousRecordSha256") != previous_sha256.hex():
                _reject(
                    f"revocation record {ref.id} breaks the "
                    "previousRecordSha256 chain"
                )
            previous_sha256 = hashlib.sha256(record_bytes).digest()
    _verify_signed_input(
        obj,
        _REVOCATION_FIELDS,
        policy,
        policy.revocationSnapshotRule,
        b"pf.revocation-ledger-snapshot-statement.v1\x00",
        b"pf.revocation-ledger-snapshot-signature.v1\x00",
        "RevocationLedgerSnapshotV1",
    )
    return RevocationLedgerSnapshotV1(
        REVOCATION_SCHEMA,
        identifier,
        version,
        authority_policy,
        records,
        head,
        records_digest,
        _consumer_checked(
            lambda: _CONSUMER._parse_approval_signatures_syntax(
                obj["signatures"], "RevocationLedgerSnapshotV1.signatures"
            ),
            "RevocationLedgerSnapshotV1.signatures are malformed",
        ),
    )


def parse_formal_finalizer_identity(
    identity_bytes: bytes,
) -> FormalFinalizerIdentityV1:
    """Validate the unsigned FormalFinalizerIdentityV1 shape."""
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(identity_bytes),
        "finalizer identity bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _FINALIZER_FIELDS, "FormalFinalizerIdentityV1"
        ),
        "FormalFinalizerIdentityV1 must be a closed object",
    )
    if obj["schema"] != FINALIZER_SCHEMA:
        _reject("FormalFinalizerIdentityV1.schema is not v1")
    return FormalFinalizerIdentityV1(
        FINALIZER_SCHEMA,
        _require_profile_id(obj["id"], "FormalFinalizerIdentityV1.id"),
        _require_semver(obj["version"], "FormalFinalizerIdentityV1.version"),
        _require_digest(
            obj["executableDigest"], "FormalFinalizerIdentityV1.executableDigest"
        ),
        _require_digest(
            obj["closureDigest"], "FormalFinalizerIdentityV1.closureDigest"
        ),
        _require_digest(
            obj["toolchainLockDigest"],
            "FormalFinalizerIdentityV1.toolchainLockDigest",
        ),
    )


def _parse_build_identity(value: object, where: str) -> BuildIdentityV1:
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            value,
            (
                "targetId",
                "targetSemanticsVersion",
                "targetSemanticsDigest",
                "codegenProfileId",
                "codegenProfileDigest",
            ),
            where,
        ),
        f"{where} must be a closed flattened BuildIdentity",
    )
    target_id = obj["targetId"]
    if type(target_id) is not str or TARGET_ID_RE.fullmatch(target_id) is None:
        _reject(f"{where}.targetId must use the TargetId grammar")
    assert isinstance(target_id, str)
    return BuildIdentityV1(
        target_id,
        _require_semver(obj["targetSemanticsVersion"], f"{where}.targetSemanticsVersion"),
        _require_digest(
            obj["targetSemanticsDigest"], f"{where}.targetSemanticsDigest"
        ),
        _require_profile_id(obj["codegenProfileId"], f"{where}.codegenProfileId"),
        _require_digest(
            obj["codegenProfileDigest"], f"{where}.codegenProfileDigest"
        ),
    )


def _parse_formal_gates(
    value: object,
    catalog_gate_task_ids: dict,
) -> Tuple[FormalGateV1, ...]:
    if type(value) is not list or not value:
        _reject("formal record gates must be a non-empty array")
    assert isinstance(value, list)
    gates = []
    for index, entry in enumerate(value):
        where = f"formal record gates[{index}]"
        obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry, ("id", "testIds", "build", "evidenceRefs"), where
            ),
            f"{where} must be a closed gate",
        )
        gate_id = _require_safe_id(obj["id"], f"{where}.id")
        test_ids_value = obj["testIds"]
        if type(test_ids_value) is not list or not test_ids_value:
            _reject(f"{where}.testIds must be a non-empty array")
        test_ids = tuple(
            _consumer_checked(
                lambda item=item, where=where: _CONSUMER._require_ascii_text(
                    item, _CONSUMER.TEST_ID_RE, where, 127
                ),
                f"{where}.testIds contains an invalid TestId",
            )
            for item in test_ids_value
        )
        _require_unique_sorted(test_ids, lambda item: item, f"{where}.testIds")
        build_value = obj["build"]
        task_id = catalog_gate_task_ids.get(gate_id)
        if build_value is None:
            if task_id not in _D0_GATE_TASK_IDS:
                _reject(
                    f"{where}.build must be non-null for a non-D0 target gate"
                )
            build = None
        else:
            build = _parse_build_identity(build_value, f"{where}.build")
        refs_value = obj["evidenceRefs"]
        if type(refs_value) is not list or not refs_value:
            _reject(f"{where}.evidenceRefs must be a non-empty array")
        evidence_refs = tuple(
            _parse_evidence_ref(item, f"{where}.evidenceRefs[{ref_index}]")
            for ref_index, item in enumerate(refs_value)
        )
        _require_unique_sorted(
            evidence_refs,
            lambda item: (item[0], item[1].bytes),
            f"{where}.evidenceRefs",
        )
        gates.append(FormalGateV1(gate_id, test_ids, build, evidence_refs))
    gates = tuple(gates)
    _require_unique_sorted(gates, lambda item: item.id, "formal record gates")
    return gates


def _evidence_core_object(record_obj: dict) -> dict:
    return {
        "candidate": record_obj["candidate"],
        "hostProfile": record_obj["hostProfile"],
        "stage0Handoff": record_obj["stage0Handoff"],
        "sessionContainment": record_obj["sessionContainment"],
        "requiredTestSet": record_obj["requiredTestSet"],
        "catalog": record_obj["catalog"],
        "catalogApproval": record_obj["catalogApproval"],
        "gates": record_obj["gates"],
        "freshnessAuthority": record_obj["freshnessAuthority"],
        "revocationLedger": record_obj["revocationLedger"],
        "finalizer": record_obj["finalizer"],
        "bootstrapApproval": record_obj["bootstrapApproval"],
    }


def parse_formal_evidence_finalization(
    record_bytes: bytes,
    authority_policy_bytes: bytes,
    required_test_set_bytes: bytes,
    phase5_snapshot: object,
    catalog_bytes: bytes,
    catalog_approval_bytes: bytes,
    session_containment_bytes: bytes,
    freshness_authority_bytes: bytes,
    private_scan_bytes: bytes,
    revocation_ledger_bytes: bytes,
    revocation_record_bytes: Tuple[bytes, ...],
    finalizer_identity_bytes: bytes,
    approval_set_bytes: bytes,
    task_receipt_bytes: Tuple[bytes, ...],
    verifier_receipt_bytes: bytes,
    stage0_handoff_bytes: bytes,
) -> Tuple[FormalEvidenceFinalizationV1, FinalizationRefV1]:
    """Validate the root formal evidence finalization record end to end.

    Every authority input is re-parsed from exact bytes; nothing is trusted
    from the record's self-reported fields.  See the module docstring for
    the declared boundaries of this consumer slice.
    """
    decoded = _consumer_checked(
        lambda: decode_canonical_pf_jcs(record_bytes),
        "formal record bytes are not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _RECORD_FIELDS, "formal evidence finalization record"
        ),
        "formal record must be a closed object",
    )
    if obj["schema"] != FINALIZATION_SCHEMA:
        _reject("formal record schema is not v1")
    record_id = _require_evf_id(obj["id"], "formal record id")
    if obj["qualification"] != "formal":
        _reject("formal record qualification must be formal")
    candidate = _consumer_checked(
        lambda: parse_candidate_identity(obj["candidate"]),
        "formal record candidate is invalid",
    )
    host_profile = _require_content_ref(obj["hostProfile"], "record.hostProfile")
    stage0_handoff = _require_content_ref(
        obj["stage0Handoff"], "record.stage0Handoff"
    )
    session_containment_ref = _require_content_ref(
        obj["sessionContainment"], "record.sessionContainment"
    )
    required_test_set_ref = _require_content_ref(
        obj["requiredTestSet"], "record.requiredTestSet"
    )
    catalog_ref = _consumer_checked(
        lambda: _CONSUMER._parse_gate_catalog_ref(
            obj["catalog"], "record.catalog"
        ),
        "record.catalog must be a GateCatalogRefV1",
    )
    catalog_approval_ref = _require_content_ref(
        obj["catalogApproval"], "record.catalogApproval"
    )
    evidence_core_digest = _require_digest(
        obj["evidenceCoreDigest"], "record.evidenceCoreDigest"
    )
    evidence_set_digest = _require_digest(
        obj["evidenceSetDigest"], "record.evidenceSetDigest"
    )
    freshness_ref = _require_content_ref(
        obj["freshnessAuthority"], "record.freshnessAuthority"
    )
    finalized_at = _require_utc_instant(
        obj["finalizedAt"], "record.finalizedAt"
    )
    expires_at = _require_utc_instant(obj["expiresAt"], "record.expiresAt")
    if finalized_at >= expires_at:
        _reject("record.finalizedAt must be before record.expiresAt")
    private_scan_ref = _require_content_ref(
        obj["privateScan"], "record.privateScan"
    )
    revocation_ref = _require_content_ref(
        obj["revocationLedger"], "record.revocationLedger"
    )
    finalizer_ref = _require_content_ref(obj["finalizer"], "record.finalizer")
    binding_obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            obj["bootstrapApproval"],
            ("set", "verifierReceipt"),
            "record.bootstrapApproval",
        ),
        "record.bootstrapApproval must be a closed object",
    )
    approval_set_ref = _require_content_ref(
        binding_obj["set"], "record.bootstrapApproval.set"
    )
    verifier_ref_obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            binding_obj["verifierReceipt"],
            ("id", "digest"),
            "record.bootstrapApproval.verifierReceipt",
        ),
        "record.bootstrapApproval.verifierReceipt must be a closed ref",
    )
    verifier_receipt_ref = BootstrapApprovalVerifierReceiptRefV1(
        _consumer_checked(
            lambda: _CONSUMER._parse_compact_gregorian_id(
                verifier_ref_obj["id"],
                _CONSUMER.BAV_ID_RE,
                4,
                "record.bootstrapApproval.verifierReceipt.id",
            ),
            "record.bootstrapApproval.verifierReceipt.id is invalid",
        ),
        _require_digest(
            verifier_ref_obj["digest"],
            "record.bootstrapApproval.verifierReceipt.digest",
        ),
    )

    expected_core = hashlib.sha256(
        b"pf.formal-evidence-core.v1\x00"
        + canonical_pf_jcs(_evidence_core_object(obj))
    ).digest()
    if evidence_core_digest.bytes != expected_core:
        _reject("record.evidenceCoreDigest mismatch")
    expected_set_digest = hashlib.sha256(
        b"pf.formal-evidence-set.v1\x00"
        + canonical_pf_jcs({
            "evidenceCoreDigest": obj["evidenceCoreDigest"],
            "privateScan": obj["privateScan"],
        })
    ).digest()
    if evidence_set_digest.bytes != expected_set_digest:
        _reject("record.evidenceSetDigest mismatch")

    policy, policy_ref = _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_authority_policy(
            authority_policy_bytes
        ),
        "external authority policy is not a valid signed policy",
    )
    required_set, resolved_required_ref = _consumer_checked(
        lambda: _CONSUMER.parse_document_bound_required_test_set(
            required_test_set_bytes, authority_policy_bytes, phase5_snapshot
        ),
        "required test set failed document-bound verification",
    )
    if required_test_set_ref != resolved_required_ref:
        _reject("record.requiredTestSet does not match the resolved set")
    handoff_preflight = _consumer_checked(
        lambda: _CONSUMER._preflight_eligible_stage0_handoff(
            stage0_handoff_bytes
        ),
        "stage0 handoff bytes are not a valid eligible handoff",
    )
    resolved_handoff = handoff_preflight.handoff
    resolved_handoff_ref = handoff_preflight.handoffRef
    if stage0_handoff != resolved_handoff_ref:
        _reject("record.stage0Handoff does not match the resolved handoff")
    if host_profile != resolved_handoff.hostProfile:
        _reject("record.hostProfile does not equal the handoff hostProfile")

    catalog_preflight = _consumer_checked(
        lambda: _CONSUMER._preflight_formal_gate_catalog(catalog_bytes),
        "catalog bytes are not a canonical formal gate catalog",
    )
    if catalog_ref != catalog_preflight.catalogRef:
        _reject("record.catalog does not match the resolved catalog identity")
    if catalog_preflight.requiredTestSet != resolved_required_ref:
        _reject("formal catalog requiredTestSet does not match the record")
    catalog_obj = _consumer_checked(
        lambda: decode_canonical_pf_jcs(catalog_bytes),
        "catalog bytes are not canonical PF-JCS",
    )
    catalog_gates = catalog_obj.get("gates")
    if type(catalog_gates) is not list:
        _reject("formal catalog gates must be an array")
    catalog_gate_ids = tuple(
        entry.get("id") if type(entry) is dict else None
        for entry in catalog_gates
    )
    catalog_gate_test_ids = {
        entry.get("id"): tuple(entry.get("testIds", ()))
        for entry in catalog_gates
        if type(entry) is dict
    }
    catalog_gate_task_ids = {
        entry.get("id"): entry.get("taskId")
        for entry in catalog_gates
        if type(entry) is dict
    }
    gates = _parse_formal_gates(obj["gates"], catalog_gate_task_ids)
    if tuple(gate.id for gate in gates) != catalog_gate_ids:
        _reject("record gate IDs do not equal the catalog gate IDs")
    for gate in gates:
        if gate.testIds != catalog_gate_test_ids.get(gate.id):
            _reject(f"record gate {gate.id} testIds do not match the catalog")
    flattened = tuple(
        test_id for gate in gates for test_id in gate.testIds
    )
    if len(flattened) != len(set(flattened)):
        _reject("record gates testIds must be duplicate-free")
    if set(flattened) != set(required_set.requiredTestIds):
        _reject("record gates must partition the resolved requiredTestIds")
    if len(flattened) != len(required_set.requiredTestIds):
        _reject("record gates must cover every resolved requiredTestId")
    all_evidence_refs = tuple(
        ref for gate in gates for ref in gate.evidenceRefs
    )
    if len(all_evidence_refs) != len(set(all_evidence_refs)):
        _reject("record evidenceRefs must be globally unique")
    all_evidence_refs_sorted = tuple(sorted(
        all_evidence_refs, key=lambda item: (item[0], item[1].bytes)
    ))

    catalog_approval, catalog_approval_digest = _consumer_checked(
        lambda: _CONSUMER.parse_formal_gate_catalog_approval(
            catalog_approval_bytes,
            catalog_bytes,
            required_test_set_bytes,
            authority_policy_bytes,
        ),
        "catalog approval failed full verification",
    )
    expected_catalog_approval_ref = ContentRef(
        catalog_approval.schema,
        catalog_approval.id,
        catalog_approval.version,
        catalog_approval_digest,
    )
    if catalog_approval_ref != expected_catalog_approval_ref:
        _reject("record.catalogApproval does not match the resolved approval")

    containment = parse_session_containment_receipt(
        session_containment_bytes, policy
    )
    expected_containment_ref = _content_ref_for(
        containment.schema,
        containment.id,
        containment.version,
        b"pf.session-containment-receipt.v1\x00",
        session_containment_bytes,
    )
    if session_containment_ref != expected_containment_ref:
        _reject("record.sessionContainment does not match the resolved receipt")
    if containment.candidate != candidate:
        _reject("session containment candidate does not match the record")
    if containment.stage0Handoff != stage0_handoff:
        _reject("session containment handoff does not match the record")

    freshness = parse_freshness_authority_snapshot(
        freshness_authority_bytes, policy
    )
    expected_freshness_ref = _content_ref_for(
        freshness.schema,
        freshness.id,
        freshness.version,
        b"pf.freshness-authority-snapshot.v1\x00",
        freshness_authority_bytes,
    )
    if freshness_ref != expected_freshness_ref:
        _reject("record.freshnessAuthority does not match the resolved snapshot")
    if freshness.authorityPolicy != policy_ref:
        _reject("freshness authority policy does not match the external policy")

    private_scan = parse_private_scan_receipt(private_scan_bytes, policy)
    expected_scan_ref = _content_ref_for(
        private_scan.schema,
        private_scan.id,
        private_scan.version,
        b"pf.private-scan-receipt.v1\x00",
        private_scan_bytes,
    )
    if private_scan_ref != expected_scan_ref:
        _reject("record.privateScan does not match the resolved receipt")
    if private_scan.candidate != candidate:
        _reject("private scan candidate does not match the record")
    if private_scan.evidenceCoreDigest.bytes != expected_core:
        _reject("private scan evidenceCoreDigest does not match the record")
    if private_scan.policy != policy.privateScanPolicy:
        _reject("private scan policy does not match the resolved policy")
    if private_scan.scannedEvidenceRefs != all_evidence_refs_sorted:
        _reject("private scan must exactly cover every record evidenceRef")
    scanned_member_evidence = {member.evidence for member in private_scan.scannedMembers}
    if not scanned_member_evidence.issubset(set(all_evidence_refs)):
        _reject("private scan members reference unknown evidenceRefs")

    revocation = parse_revocation_ledger_snapshot(
        revocation_ledger_bytes, policy, revocation_record_bytes
    )
    expected_revocation_ref = _content_ref_for(
        revocation.schema,
        revocation.id,
        revocation.version,
        b"pf.revocation-ledger-snapshot.v1\x00",
        revocation_ledger_bytes,
    )
    if revocation_ref != expected_revocation_ref:
        _reject("record.revocationLedger does not match the resolved snapshot")
    if revocation.authorityPolicy != policy_ref:
        _reject("revocation authority policy does not match the external policy")

    finalizer = parse_formal_finalizer_identity(finalizer_identity_bytes)
    expected_finalizer_ref = _content_ref_for(
        finalizer.schema,
        finalizer.id,
        finalizer.version,
        b"pf.formal-finalizer-identity.v1\x00",
        finalizer_identity_bytes,
    )
    if finalizer_ref != expected_finalizer_ref:
        _reject("record.finalizer does not match the resolved identity")
    if finalizer.executableDigest != resolved_handoff.tcb.formalFinalizerDigest:
        _reject("finalizer executableDigest does not match the handoff tcb")

    approval_set, resolved_set_ref = _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_approval_set(
            approval_set_bytes,
            task_receipt_bytes,
            required_test_set_bytes,
            authority_policy_bytes,
            phase5_snapshot,
            stage0_handoff_bytes,
        ),
        "bootstrap approval set failed full six-item verification",
    )
    if approval_set_ref != resolved_set_ref:
        _reject("record.bootstrapApproval.set does not match the resolved set")

    verifier_receipt, resolved_verifier_ref = _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_approval_verifier_receipt(
            verifier_receipt_bytes,
            approval_set_bytes,
            task_receipt_bytes,
            required_test_set_bytes,
            authority_policy_bytes,
            phase5_snapshot,
            stage0_handoff_bytes,
        ),
        "bootstrap verifier receipt failed full verification",
    )
    if verifier_receipt_ref != resolved_verifier_ref:
        _reject(
            "record.bootstrapApproval.verifierReceipt does not match the "
            "resolved receipt"
        )
    if verifier_receipt.approvalSet != resolved_set_ref:
        _reject("verifier receipt set ref does not match the record set")
    if verifier_receipt.candidate != candidate:
        _reject("verifier receipt candidate does not match the record")
    if verifier_receipt.stage0Handoff != resolved_handoff_ref:
        _reject("verifier receipt handoff does not match the resolved handoff")
    if verifier_receipt.requiredTestSet != resolved_required_ref:
        _reject("verifier receipt required-test-set does not match the record")

    external_policies = {
        resolved_handoff.authorityPolicy,
        approval_set.authorityPolicy,
        verifier_receipt.authorityPolicy,
    }
    if external_policies != {policy_ref}:
        _reject(
            "externalAuthorityPolicy is not a single bytewise-equal value "
            "across handoff, set, and receipt"
        )

    record = FormalEvidenceFinalizationV1(
        FINALIZATION_SCHEMA,
        record_id,
        "formal",
        candidate,
        host_profile,
        stage0_handoff,
        session_containment_ref,
        required_test_set_ref,
        catalog_ref,
        catalog_approval_ref,
        gates,
        evidence_core_digest,
        evidence_set_digest,
        freshness_ref,
        finalized_at,
        expires_at,
        private_scan_ref,
        revocation_ref,
        finalizer_ref,
        BootstrapApprovalBindingV1(approval_set_ref, verifier_receipt_ref),
    )
    finalization_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.formal-evidence-finalization.v1\x00" + record_bytes
        ).digest(),
    )
    return record, FinalizationRefV1(
        FINALIZATION_SCHEMA, record_id, finalization_digest
    )
