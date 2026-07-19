#!/usr/bin/env python3
"""Producers/signers for the remaining signed formal inputs, the freshness
window predicate, and the unsigned finalizer identity (TASK-D0-07 slice S3).

Key custody discipline (same as bootstrap_task_producers.py): signing takes
the exact 32-byte Ed25519 seed as an explicit call parameter.  This module
never generates random or fixed seeds, never reads key material from disk,
environment, or CLI, and never persists key material; seeds are used only for
the duration of the call and never appear in return values, logs, or
exception details.  The module performs no filesystem, socket, environment,
or CLI I/O beyond locating its exact sibling modules at import time; the
clock-source declaration and every digest input arrive as caller-supplied
bytes.

Wire authority (formal_evidence.py): SessionContainmentReceiptV1 and
FreshnessAuthoritySnapshotV1 follow parse_session_containment_receipt /
parse_freshness_authority_snapshot exactly (closed fields, descendant sort
by (pid,parentPid,startToken,sessionId,executableDigest,termination),
escape-probe sort by id, UtcInstant seconds precision, "contained" results,
termination in {exited,killed}, nonzero maximumAgeSeconds) with the frozen
statement/signature domains from gate-catalog-finalization.md 1764-1775.
Freshness semantics follow ADR-0018: expiresAt == observedAt +
maximumAgeSeconds and finalizedAt < expiresAt, judged at finalization.
FormalFinalizerIdentityV1 is unsigned per parse_formal_finalizer_identity
(closed six-field object with three Digest wires and no signatures field),
so its producer is a pure constructor plus a digest helper.  Slice scope is
the fixture namespace (ADR-0018): nothing here is formal or hermetic
evidence; building the supervising observer is a later TST-ISO-002 slice.
"""

from __future__ import annotations

import hashlib
import importlib.util
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Tuple


def _load_module(path: Path, name: str) -> ModuleType:
    """Load an exact sibling module without a sys.path authority seam."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError(f"exact sibling loader is unavailable: {path.name}")
    if Path(spec.origin).resolve(strict=True) != path.resolve(strict=True):
        raise ImportError(f"exact sibling origin changed: {path.name}")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _load_bootstrap_task_producers() -> ModuleType:
    module_path = Path(__file__).resolve(strict=True)
    return _load_module(
        module_path.with_name("bootstrap_task_producers.py"),
        "proof_forge_bootstrap_task_producers_for_formal_inputs",
    )


def _load_formal_evidence() -> ModuleType:
    module_path = Path(__file__).resolve(strict=True)
    return _load_module(
        module_path.with_name("formal_evidence.py"),
        "proof_forge_formal_evidence_for_formal_inputs",
    )


_PRODUCER = _load_bootstrap_task_producers()
_CONSUMER = _PRODUCER._CONSUMER
_FORMAL = _load_formal_evidence()

CONTAINMENT_SCHEMA = "proof-forge.session-containment-receipt.v1"
FRESHNESS_SCHEMA = "proof-forge.freshness-authority-snapshot.v1"
FINALIZER_SCHEMA = "proof-forge.formal-finalizer-identity.v1"
CONTAINMENT_STATEMENT_DOMAIN = b"pf.session-containment-receipt-statement.v1\x00"
CONTAINMENT_SIGNATURE_DOMAIN = b"pf.session-containment-receipt-signature.v1\x00"
FRESHNESS_STATEMENT_DOMAIN = b"pf.freshness-authority-snapshot-statement.v1\x00"
FRESHNESS_SIGNATURE_DOMAIN = b"pf.freshness-authority-snapshot-signature.v1\x00"
FINALIZER_DIGEST_DOMAIN = b"pf.formal-finalizer-identity.v1\x00"
MAX_SAFE_INTEGER = (1 << 53) - 1
UTC_INSTANT_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
_TERMINATIONS = ("exited", "killed")
_DESCENDANT_FIELDS = (
    "pid",
    "parentPid",
    "startToken",
    "sessionId",
    "executableDigest",
    "termination",
)
_ESCAPE_PROBE_FIELDS = ("id", "result")


class FormalInputError(Exception):
    """Stable formal-input failure; never carries key material."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise FormalInputError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-FORMAL-INPUT-SCHEMA", detail)


def _sign(detail: str) -> NoReturn:
    _fail("PF-FORMAL-INPUT-SIGN", detail)


def _verify(detail: str) -> NoReturn:
    _fail("PF-FORMAL-INPUT-VERIFY", detail)


def _consumer_checked(validation, code: str, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _fail(code, detail)
    except (TypeError, ValueError, AttributeError, IndexError, KeyError):
        _fail(code, detail)


def _require_u64(value: object, where: str) -> int:
    if type(value) is not int or not 0 <= value <= MAX_SAFE_INTEGER:
        _schema(f"{where} must be a UInt64 not above 2^53-1")
    assert isinstance(value, int)
    return value


def _require_utc_instant(value: object, where: str) -> str:
    if type(value) is not str:
        _schema(f"{where} must be a UtcInstant seconds-precision wire value")
    assert isinstance(value, str)
    try:
        parsed = datetime.strptime(value, UTC_INSTANT_FORMAT)
    except ValueError:
        _schema(f"{where} must be a real UTC instant")
    if parsed.strftime(UTC_INSTANT_FORMAT) != value:
        _schema(f"{where} must be a UtcInstant seconds-precision wire value")
    return value


def _require_safe_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_safe_id(value, where),
        "PF-FORMAL-INPUT-SCHEMA",
        f"{where} must be an ASCII safe-id",
    )


def _require_digest_wire(value: object, where: str) -> str:
    _consumer_checked(
        lambda: _CONSUMER.parse_digest(value),
        "PF-FORMAL-INPUT-SCHEMA",
        f"{where} must be the SPEC-COMMON Digest wire form",
    )
    assert isinstance(value, str)
    return value


def _require_profile_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_ascii_text(
            value, _CONSUMER.PROFILE_ID_RE, where, 127
        ),
        "PF-FORMAL-INPUT-SCHEMA",
        f"{where} must use the ContentRef id grammar",
    )


def _require_semver(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._require_semver(value, where),
        "PF-FORMAL-INPUT-SCHEMA",
        f"{where} must be exact SemVer",
    )


def _authority_policy_ref(authority_policy_bytes: bytes):
    return _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_authority_policy(
            authority_policy_bytes
        ),
        "PF-FORMAL-INPUT-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )


def _formal_policy(authority_policy_bytes: bytes):
    return _consumer_checked(
        lambda: _FORMAL._CONSUMER.parse_bootstrap_authority_policy(
            authority_policy_bytes
        )[0],
        "PF-FORMAL-INPUT-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )


def _sign_statement(statement: dict, statement_domain: bytes,
                    signature_domain: bytes,
                    signers: Tuple[Tuple[str, bytes], ...],
                    where: str) -> list:
    statement_digest = hashlib.sha256(
        statement_domain + _CONSUMER.canonical_pf_jcs(statement)
    ).digest()
    message = signature_domain + statement_digest
    if type(signers) is not tuple or not signers:
        _schema(f"{where} signers must be a non-empty tuple")
    key_ids = tuple(key_id for key_id, _ in signers)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _schema(f"{where} signers must be unique ascending by keyId")
    signatures = []
    for key_id, seed in signers:
        _require_safe_id(key_id, f"{where}.signatures")
        if type(seed) is not bytes or len(seed) != 32:
            _sign("invalid signing input")
        signatures.append(
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": _PRODUCER.sign_ed25519(seed, message).hex(),
            }
        )
    return signatures


def produce_session_containment_receipt(
    *,
    id: str,
    version: str,
    candidate: dict,
    stage0_handoff: dict,
    supervisor_digest: str,
    root_session_id: str,
    descendants: Tuple[dict, ...],
    escape_probes: Tuple[dict, ...],
    started_at: str,
    finished_at: str,
    result: str,
    authority_policy_bytes: bytes,
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-verify a SessionContainmentReceiptV1."""
    identifier = _require_profile_id(id, "SessionContainmentReceiptV1.id")
    receipt_version = _require_semver(
        version, "SessionContainmentReceiptV1.version"
    )
    _consumer_checked(
        lambda: _CONSUMER.parse_candidate_identity(candidate),
        "PF-FORMAL-INPUT-SCHEMA",
        "receipt candidate is not a valid CandidateIdentity",
    )
    _consumer_checked(
        lambda: _CONSUMER.parse_content_ref(stage0_handoff),
        "PF-FORMAL-INPUT-SCHEMA",
        "receipt stage0Handoff must be a full ContentRef",
    )
    supervisor_digest = _require_digest_wire(
        supervisor_digest, "SessionContainmentReceiptV1.supervisorDigest"
    )
    root_session_id = _require_safe_id(
        root_session_id, "SessionContainmentReceiptV1.rootSessionId"
    )
    if type(descendants) is not tuple:
        _schema("SessionContainmentReceiptV1.descendants must be a tuple")
    descendant_wires = []
    for index, entry in enumerate(descendants):
        where = f"SessionContainmentReceiptV1.descendants[{index}]"
        obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry, _DESCENDANT_FIELDS, where
            ),
            "PF-FORMAL-INPUT-SCHEMA",
            f"{where} must be a closed descendant",
        )
        termination = obj["termination"]
        if termination not in _TERMINATIONS:
            _schema(f"{where}.termination must be exited|killed")
        descendant_wires.append(
            (
                (
                    _require_u64(obj["pid"], f"{where}.pid"),
                    _require_u64(obj["parentPid"], f"{where}.parentPid"),
                    _require_u64(obj["startToken"], f"{where}.startToken"),
                    _require_u64(obj["sessionId"], f"{where}.sessionId"),
                    bytes.fromhex(
                        _require_digest_wire(
                            obj["executableDigest"],
                            f"{where}.executableDigest",
                        )[7:]
                    ),
                    termination,
                ),
                {
                    "pid": obj["pid"],
                    "parentPid": obj["parentPid"],
                    "startToken": obj["startToken"],
                    "sessionId": obj["sessionId"],
                    "executableDigest": obj["executableDigest"],
                    "termination": termination,
                },
            )
        )
    descendant_keys = [key for key, _ in descendant_wires]
    if len(set(descendant_keys)) != len(descendant_keys):
        _schema("SessionContainmentReceiptV1.descendants must not contain duplicates")
    descendant_wires = [
        wire for _, wire in sorted(descendant_wires, key=lambda item: item[0])
    ]
    if type(escape_probes) is not tuple:
        _schema("SessionContainmentReceiptV1.escapeProbes must be a tuple")
    probe_wires = []
    for index, entry in enumerate(escape_probes):
        where = f"SessionContainmentReceiptV1.escapeProbes[{index}]"
        obj = _consumer_checked(
            lambda entry=entry, where=where: _CONSUMER._require_exact_keys(
                entry, _ESCAPE_PROBE_FIELDS, where
            ),
            "PF-FORMAL-INPUT-SCHEMA",
            f"{where} must be a closed escape probe",
        )
        if obj["result"] != "contained":
            _schema(f"{where}.result must be contained")
        probe_wires.append(
            (
                _require_safe_id(obj["id"], f"{where}.id"),
                {"id": obj["id"], "result": "contained"},
            )
        )
    probe_ids = [key for key, _ in probe_wires]
    if len(set(probe_ids)) != len(probe_ids):
        _schema("SessionContainmentReceiptV1.escapeProbes must not contain duplicates")
    probe_wires = [item for _, item in sorted(probe_wires)]
    started_at = _require_utc_instant(
        started_at, "SessionContainmentReceiptV1.startedAt"
    )
    finished_at = _require_utc_instant(
        finished_at, "SessionContainmentReceiptV1.finishedAt"
    )
    if result != "contained":
        _schema("SessionContainmentReceiptV1.result must be contained")
    _authority_policy_ref(authority_policy_bytes)
    statement = {
        "schema": CONTAINMENT_SCHEMA,
        "id": identifier,
        "version": receipt_version,
        "candidate": candidate,
        "stage0Handoff": stage0_handoff,
        "supervisorDigest": supervisor_digest,
        "rootSessionId": root_session_id,
        "descendants": descendant_wires,
        "escapeProbes": probe_wires,
        "startedAt": started_at,
        "finishedAt": finished_at,
        "result": "contained",
    }
    signatures = _sign_statement(
        statement,
        CONTAINMENT_STATEMENT_DOMAIN,
        CONTAINMENT_SIGNATURE_DOMAIN,
        signers,
        "SessionContainmentReceiptV1",
    )
    wire = {**statement, "signatures": signatures}
    receipt_bytes = _CONSUMER.canonical_pf_jcs(wire)
    try:
        _FORMAL.parse_session_containment_receipt(
            receipt_bytes, _formal_policy(authority_policy_bytes)
        )
    except _FORMAL.Rejected:
        _verify("produced receipt failed formal consumer re-verification")
    return receipt_bytes


def produce_freshness_authority_snapshot(
    *,
    id: str,
    version: str,
    authority_policy_bytes: bytes,
    observed_at: str,
    maximum_age_seconds: int,
    clock_source_bytes: bytes,
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-verify a FreshnessAuthoritySnapshotV1."""
    identifier = _require_profile_id(id, "FreshnessAuthoritySnapshotV1.id")
    snapshot_version = _require_semver(
        version, "FreshnessAuthoritySnapshotV1.version"
    )
    observed_at = _require_utc_instant(
        observed_at, "FreshnessAuthoritySnapshotV1.observedAt"
    )
    maximum_age = _require_u64(
        maximum_age_seconds, "FreshnessAuthoritySnapshotV1.maximumAgeSeconds"
    )
    if maximum_age == 0:
        _schema("FreshnessAuthoritySnapshotV1.maximumAgeSeconds must be nonzero")
    if type(clock_source_bytes) is not bytes or not clock_source_bytes:
        _schema("clock source declaration must be non-empty bytes")
    clock_source_digest = "sha256:" + hashlib.sha256(clock_source_bytes).hexdigest()
    _, policy_ref = _authority_policy_ref(authority_policy_bytes)
    statement = {
        "schema": FRESHNESS_SCHEMA,
        "id": identifier,
        "version": snapshot_version,
        "authorityPolicy": {
            "schema": policy_ref.schema,
            "id": policy_ref.id,
            "version": policy_ref.version,
            "digest": "sha256:" + policy_ref.digest.bytes.hex(),
        },
        "observedAt": observed_at,
        "maximumAgeSeconds": maximum_age,
        "clockSourceDigest": clock_source_digest,
    }
    signatures = _sign_statement(
        statement,
        FRESHNESS_STATEMENT_DOMAIN,
        FRESHNESS_SIGNATURE_DOMAIN,
        signers,
        "FreshnessAuthoritySnapshotV1",
    )
    wire = {**statement, "signatures": signatures}
    snapshot_bytes = _CONSUMER.canonical_pf_jcs(wire)
    try:
        _FORMAL.parse_freshness_authority_snapshot(
            snapshot_bytes, _formal_policy(authority_policy_bytes)
        )
    except _FORMAL.Rejected:
        _verify("produced snapshot failed formal consumer re-verification")
    return snapshot_bytes


def freshness_expires_at(observed_at: str, maximum_age_seconds: int) -> str:
    """expiresAt == observedAt + maximumAgeSeconds (ADR-0018)."""
    observed_at = _require_utc_instant(
        observed_at, "FreshnessAuthoritySnapshotV1.observedAt"
    )
    maximum_age = _require_u64(
        maximum_age_seconds, "FreshnessAuthoritySnapshotV1.maximumAgeSeconds"
    )
    if maximum_age == 0:
        _schema("FreshnessAuthoritySnapshotV1.maximumAgeSeconds must be nonzero")
    observed = datetime.strptime(observed_at, UTC_INSTANT_FORMAT)
    return (observed + timedelta(seconds=maximum_age)).strftime(
        UTC_INSTANT_FORMAT
    )


def require_freshness_window(
    observed_at: str,
    maximum_age_seconds: int,
    expires_at: str,
    finalized_at: str,
) -> None:
    """Judge the ADR-0018 freshness predicate at finalization time."""
    expected = freshness_expires_at(observed_at, maximum_age_seconds)
    expires_at = _require_utc_instant(
        expires_at, "freshness window expiresAt"
    )
    finalized_at = _require_utc_instant(
        finalized_at, "freshness window finalizedAt"
    )
    if expires_at != expected:
        _verify("freshness expiresAt does not equal observedAt + maximumAgeSeconds")
    if finalized_at >= expires_at:
        _verify("freshness window reversed or expired (finalizedAt >= expiresAt)")


def produce_formal_finalizer_identity(
    *,
    id: str,
    version: str,
    executable_digest: str,
    closure_digest: str,
    toolchain_lock_digest: str,
) -> bytes:
    """Construct and re-validate the unsigned FormalFinalizerIdentityV1."""
    identifier = _require_profile_id(id, "FormalFinalizerIdentityV1.id")
    identity_version = _require_semver(
        version, "FormalFinalizerIdentityV1.version"
    )
    wire = {
        "schema": FINALIZER_SCHEMA,
        "id": identifier,
        "version": identity_version,
        "executableDigest": _require_digest_wire(
            executable_digest, "FormalFinalizerIdentityV1.executableDigest"
        ),
        "closureDigest": _require_digest_wire(
            closure_digest, "FormalFinalizerIdentityV1.closureDigest"
        ),
        "toolchainLockDigest": _require_digest_wire(
            toolchain_lock_digest,
            "FormalFinalizerIdentityV1.toolchainLockDigest",
        ),
    }
    identity_bytes = _CONSUMER.canonical_pf_jcs(wire)
    try:
        _FORMAL.parse_formal_finalizer_identity(identity_bytes)
    except _FORMAL.Rejected:
        _verify("produced identity failed formal consumer re-verification")
    return identity_bytes


def formal_finalizer_identity_digest(identity_bytes: bytes) -> str:
    """Derive the domain-separated digest of a finalizer identity."""
    if type(identity_bytes) is not bytes or not identity_bytes:
        _schema("finalizer identity must be non-empty bytes")
    return "sha256:" + hashlib.sha256(
        FINALIZER_DIGEST_DOMAIN + identity_bytes
    ).hexdigest()
