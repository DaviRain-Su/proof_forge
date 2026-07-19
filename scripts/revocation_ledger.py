#!/usr/bin/env python3
"""Revocation record producer/parser, append-only ledger store, and signed
RevocationLedgerSnapshotV1 producer (TASK-D0-07 slice S1).

Key custody discipline (same as bootstrap_task_producers.py): signing takes
the exact 32-byte Ed25519 seed as an explicit call parameter.  This module
never generates random or fixed seeds, never reads key material from disk,
environment, or CLI, and never persists key material; seeds are used only for
the duration of the call and never appear in return values, logs, or
exception details.  The module performs no filesystem, socket, environment,
or CLI I/O beyond locating its exact sibling modules at import time.

Wire authority: the record payload schema is TRACE-EV-001
(docs/traceability/evidence-schema.md "Revocation records"); the snapshot
shape and digest derivations follow gate-catalog-finalization.md 1729-1830
with the formal consumer (formal_evidence.parse_revocation_ledger_snapshot)
as the shape authority: genesis previousRecordSha256 is 64 zero hex (not
null), each subsequent link is the plain SHA-256 of the previous record's
canonical bytes, records are unique ascending by RVK id in chain order, head
is null iff the ledger is empty, recordsDigest is the domain-separated
length-prefixed u32be(size)||digest aggregate, and the snapshot is signed
under the policy revocationSnapshotRule with the statement/signature domains
from the frozen rule table.  Slice scope is the fixture namespace
(ADR-0018): nothing here is formal or hermetic evidence.
"""

from __future__ import annotations

import hashlib
import importlib.util
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Optional, Tuple


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
        "proof_forge_bootstrap_task_producers_for_revocation_ledger",
    )


def _load_formal_evidence() -> ModuleType:
    module_path = Path(__file__).resolve(strict=True)
    return _load_module(
        module_path.with_name("formal_evidence.py"),
        "proof_forge_formal_evidence_for_revocation_ledger",
    )


_PRODUCER = _load_bootstrap_task_producers()
_CONSUMER = _PRODUCER._CONSUMER
_FORMAL = _load_formal_evidence()

REVOCATION_RECORD_SCHEMA = "proof-forge.evidence-revocation.v1"
REVOCATION_SNAPSHOT_SCHEMA = "proof-forge.revocation-ledger-snapshot.v1"
RECORD_DIGEST_DOMAIN = b"pf.evidence-revocation.v1\x00"
RECORDS_DIGEST_DOMAIN = b"pf.revocation-ledger-records.v1\x00"
STATEMENT_DOMAIN = b"pf.revocation-ledger-snapshot-statement.v1\x00"
SIGNATURE_DOMAIN = b"pf.revocation-ledger-snapshot-signature.v1\x00"
GENESIS_PREVIOUS_RECORD_SHA256 = "0" * 64
REASON_CODES = ("compromised", "incorrect", "policy-violation", "superseded")
RVK_ID_RE = re.compile(r"RVK-[0-9]{8}-[0-9]{4}")
UTC_INSTANT_RE = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
)
HEX64_RE = re.compile(r"[0-9a-f]{64}")
_RECORD_FIELDS = (
    "schema",
    "id",
    "version",
    "evidence",
    "revokedUtc",
    "reasonCode",
    "reason",
    "authorityRef",
    "replacement",
    "previousRecordSha256",
)
_EVIDENCE_REF_FIELDS = ("id", "sha256")
MAX_REASON_BYTES = 4096


class RevocationError(Exception):
    """Stable revocation failure; never carries key material."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise RevocationError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-REVOCATION-SCHEMA", detail)


def _chain(detail: str) -> NoReturn:
    _fail("PF-REVOCATION-CHAIN", detail)


def _verify(detail: str) -> NoReturn:
    _fail("PF-REVOCATION-VERIFY", detail)


@dataclass(frozen=True)
class RevocationRecord:
    schema: str
    id: str
    version: str
    evidenceId: str
    evidenceSha256: str
    revokedUtc: str
    reasonCode: str
    reason: str
    authorityRef: str
    replacementId: Optional[str]
    replacementSha256: Optional[str]
    previousRecordSha256: str


def _consumer_checked(validation, code: str, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _fail(code, detail)
    except (TypeError, ValueError, AttributeError, IndexError, KeyError):
        _fail(code, detail)


def _require_text(value: object, where: str) -> str:
    if type(value) is not str or not value:
        _schema(f"{where} must be non-empty text")
    assert isinstance(value, str)
    return value


def _require_hex64(value: object, where: str) -> str:
    text = _require_text(value, where)
    if HEX64_RE.fullmatch(text) is None:
        _schema(f"{where} must be 64 lowercase hex digits")
    return text


def _require_evidence_id(value: object, where: str) -> str:
    return _consumer_checked(
        lambda: _CONSUMER._parse_compact_gregorian_id(
            value, _CONSUMER.EVIDENCE_ID_RE, 3, where
        ),
        "PF-REVOCATION-SCHEMA",
        f"{where} must be a real EV-YYYYMMDD-NNNN id",
    )


def _require_revoked_utc(value: object, where: str) -> str:
    text = _require_text(value, where)
    if UTC_INSTANT_RE.fullmatch(text) is None:
        _schema(f"{where} must be a UtcInstant seconds-precision wire value")
    try:
        datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        _schema(f"{where} must be a real UTC instant")
    return text


def _require_evidence_ref(value: object, where: str) -> Tuple[str, str]:
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(value, _EVIDENCE_REF_FIELDS, where),
        "PF-REVOCATION-SCHEMA",
        f"{where} must be a closed {{id, sha256}} reference",
    )
    return (
        _require_evidence_id(obj["id"], f"{where}.id"),
        _require_hex64(obj["sha256"], f"{where}.sha256"),
    )


def parse_revocation_record(record_bytes: bytes) -> RevocationRecord:
    """Validate the exact canonical RevocationRecord wire (TRACE-EV-001)."""
    if type(record_bytes) is not bytes or not record_bytes:
        _schema("revocation record must be non-empty canonical PF-JCS bytes")
    decoded = _consumer_checked(
        lambda: _CONSUMER.decode_canonical_pf_jcs(record_bytes),
        "PF-REVOCATION-SCHEMA",
        "revocation record is not canonical PF-JCS",
    )
    obj = _consumer_checked(
        lambda: _CONSUMER._require_exact_keys(
            decoded, _RECORD_FIELDS, "RevocationRecord"
        ),
        "PF-REVOCATION-SCHEMA",
        "RevocationRecord must be a closed object",
    )
    if obj["schema"] != REVOCATION_RECORD_SCHEMA:
        _schema("RevocationRecord.schema is not evidence-revocation.v1")
    identifier = _consumer_checked(
        lambda: _CONSUMER._parse_compact_gregorian_id(
            obj["id"], RVK_ID_RE, 4, "RevocationRecord.id"
        ),
        "PF-REVOCATION-SCHEMA",
        "RevocationRecord.id must be a real RVK-YYYYMMDD-NNNN id",
    )
    if obj["version"] != "1.0.0":
        _schema("RevocationRecord.version must be exactly 1.0.0")
    evidence_id, evidence_sha256 = _require_evidence_ref(
        obj["evidence"], "RevocationRecord.evidence"
    )
    revoked_utc = _require_revoked_utc(
        obj["revokedUtc"], "RevocationRecord.revokedUtc"
    )
    if identifier[4:12] != revoked_utc[0:10].replace("-", ""):
        _schema("RevocationRecord.id date must equal the revokedUtc UTC date")
    reason_code = obj["reasonCode"]
    if reason_code not in REASON_CODES:
        _schema("RevocationRecord.reasonCode is not a frozen reason code")
    assert isinstance(reason_code, str)
    reason = obj["reason"]
    if type(reason) is not str or not 1 <= len(reason.encode("utf-8")) <= (
        MAX_REASON_BYTES
    ):
        _schema("RevocationRecord.reason must be 1..4096 UTF-8 bytes")
    assert isinstance(reason, str)
    authority_ref = _consumer_checked(
        lambda: _CONSUMER._require_safe_id(
            obj["authorityRef"], "RevocationRecord.authorityRef"
        ),
        "PF-REVOCATION-SCHEMA",
        "RevocationRecord.authorityRef must be a safe-id",
    )
    replacement = obj["replacement"]
    if replacement is None:
        replacement_id: Optional[str] = None
        replacement_sha256: Optional[str] = None
    else:
        replacement_id, replacement_sha256 = _require_evidence_ref(
            replacement, "RevocationRecord.replacement"
        )
        if replacement_id == evidence_id:
            _schema(
                "RevocationRecord.replacement must not name the revoked evidence"
            )
    previous = obj["previousRecordSha256"]
    if previous is None:
        _schema(
            "RevocationRecord.previousRecordSha256 uses the zero-hex "
            "genesis convention, not null"
        )
    previous = _require_hex64(
        previous, "RevocationRecord.previousRecordSha256"
    )
    return RevocationRecord(
        REVOCATION_RECORD_SCHEMA,
        identifier,
        "1.0.0",
        evidence_id,
        evidence_sha256,
        revoked_utc,
        reason_code,
        reason,
        authority_ref,
        replacement_id,
        replacement_sha256,
        previous,
    )


def produce_revocation_record(
    *,
    id: str,
    evidence_id: str,
    evidence_sha256: str,
    revoked_utc: str,
    reason_code: str,
    reason: str,
    authority_ref: str,
    replacement: Optional[Tuple[str, str]],
    previous_record_sha256: Optional[str],
) -> bytes:
    """Construct and re-validate one canonical RevocationRecord."""
    wire = {
        "schema": REVOCATION_RECORD_SCHEMA,
        "id": id,
        "version": "1.0.0",
        "evidence": {"id": evidence_id, "sha256": evidence_sha256},
        "revokedUtc": revoked_utc,
        "reasonCode": reason_code,
        "reason": reason,
        "authorityRef": authority_ref,
        "replacement": (
            None
            if replacement is None
            else {"id": replacement[0], "sha256": replacement[1]}
        ),
        "previousRecordSha256": previous_record_sha256,
    }
    record_bytes = _CONSUMER.canonical_pf_jcs(wire)
    parse_revocation_record(record_bytes)
    return record_bytes


def revocation_record_ref(record_bytes: bytes) -> dict:
    """Derive the exact RevocationRecordRefV1 wire for a record."""
    record = parse_revocation_record(record_bytes)
    return {
        "schema": REVOCATION_RECORD_SCHEMA,
        "id": record.id,
        "version": "1.0.0",
        "digest": "sha256:" + hashlib.sha256(
            RECORD_DIGEST_DOMAIN + record_bytes
        ).hexdigest(),
    }


class RevocationLedgerStore:
    """Append-only revocation record store with chain validation.

    Duplicate record ids, unknown authorities, hash-chain forks (link
    pointing at a non-head record), and missing links (link pointing outside
    the ledger) are all rejected; the store performs no I/O.
    """

    def __init__(self, authorities: Tuple[str, ...]) -> None:
        if type(authorities) is not tuple:
            _schema("store authorities must be a tuple of safe-ids")
        self._authorities = frozenset(
            _consumer_checked(
                lambda authority=authority: _CONSUMER._require_safe_id(
                    authority, "RevocationLedgerStore.authorities"
                ),
                "PF-REVOCATION-SCHEMA",
                "store authorities must be safe-ids",
            )
            for authority in authorities
        )
        self._records: list = []
        self._ids: set = set()
        self._links: set = set()

    def append(self, record_bytes: bytes) -> dict:
        record = parse_revocation_record(record_bytes)
        if record.id in self._ids:
            _chain("duplicate revocation record id")
        if record.authorityRef not in self._authorities:
            _chain("unknown revocation authority")
        expected_previous = (
            hashlib.sha256(self._records[-1]).hexdigest()
            if self._records
            else GENESIS_PREVIOUS_RECORD_SHA256
        )
        if record.previousRecordSha256 != expected_previous:
            if record.previousRecordSha256 in self._links:
                _chain("hash chain fork")
            _chain("missing chain link")
        self._records.append(record_bytes)
        self._ids.add(record.id)
        self._links.add(hashlib.sha256(record_bytes).hexdigest())
        return revocation_record_ref(record_bytes)

    @property
    def records(self) -> Tuple[bytes, ...]:
        return tuple(self._records)

    @property
    def refs(self) -> Tuple[dict, ...]:
        return tuple(revocation_record_ref(item) for item in self._records)

    @property
    def head(self) -> Optional[dict]:
        if not self._records:
            return None
        return revocation_record_ref(self._records[-1])


def produce_revocation_ledger_snapshot(
    *,
    id: str,
    version: str,
    policy_bytes: bytes,
    record_bytes: Tuple[bytes, ...],
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-verify a RevocationLedgerSnapshotV1.

    The snapshot is signed under the policy revocationSnapshotRule
    (security+release, two distinct principals) and immediately re-verified
    through the formal consumer with the exact record bytes.
    """
    identifier = _consumer_checked(
        lambda: _CONSUMER._require_ascii_text(
            id, _CONSUMER.PROFILE_ID_RE, "RevocationLedgerSnapshotV1.id", 127
        ),
        "PF-REVOCATION-SCHEMA",
        "snapshot id must use the ContentRef id grammar",
    )
    snapshot_version = _consumer_checked(
        lambda: _CONSUMER._require_semver(
            version, "RevocationLedgerSnapshotV1.version"
        ),
        "PF-REVOCATION-SCHEMA",
        "snapshot version must be exact SemVer",
    )
    policy, policy_ref = _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_authority_policy(policy_bytes),
        "PF-REVOCATION-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )
    if type(record_bytes) is not tuple or any(
        type(item) is not bytes for item in record_bytes
    ):
        _schema("snapshot records must be supplied as exact bytes")
    refs = []
    previous = GENESIS_PREVIOUS_RECORD_SHA256
    for index, item in enumerate(record_bytes):
        record = parse_revocation_record(item)
        if index and record.id <= refs[-1]["id"]:
            _chain("snapshot records must be unique ascending by RVK id")
        if record.previousRecordSha256 != previous:
            _chain("snapshot record chain link mismatch")
        refs.append(revocation_record_ref(item))
        previous = hashlib.sha256(item).hexdigest()
    aggregate = b"".join(
        len(bytes.fromhex(ref["digest"][7:])).to_bytes(4, "big")
        + bytes.fromhex(ref["digest"][7:])
        for ref in refs
    )
    records_digest = "sha256:" + hashlib.sha256(
        RECORDS_DIGEST_DOMAIN + aggregate
    ).hexdigest()
    statement = {
        "schema": REVOCATION_SNAPSHOT_SCHEMA,
        "id": identifier,
        "version": snapshot_version,
        "authorityPolicy": {
            "schema": policy_ref.schema,
            "id": policy_ref.id,
            "version": policy_ref.version,
            "digest": "sha256:" + policy_ref.digest.bytes.hex(),
        },
        "records": refs,
        "head": refs[-1] if refs else None,
        "recordsDigest": records_digest,
    }
    statement_digest = hashlib.sha256(
        STATEMENT_DOMAIN + _CONSUMER.canonical_pf_jcs(statement)
    ).digest()
    message = SIGNATURE_DOMAIN + statement_digest
    if type(signers) is not tuple or not signers:
        _schema("snapshot signers must be a non-empty tuple")
    key_ids = tuple(key_id for key_id, _ in signers)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _schema("snapshot signers must be unique ascending by keyId")
    signatures = []
    for key_id, seed in signers:
        _consumer_checked(
            lambda key_id=key_id: _CONSUMER._require_safe_id(
                key_id, "RevocationLedgerSnapshotV1.signatures"
            ),
            "PF-REVOCATION-SCHEMA",
            "snapshot signer keyId must be a safe-id",
        )
        if type(seed) is not bytes or len(seed) != 32:
            _fail("PF-REVOCATION-SIGN", "invalid signing input")
        signatures.append(
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": _PRODUCER.sign_ed25519(seed, message).hex(),
            }
        )
    wire = {**statement, "signatures": signatures}
    snapshot_bytes = _CONSUMER.canonical_pf_jcs(wire)
    formal_policy = _consumer_checked(
        lambda: _FORMAL._CONSUMER.parse_bootstrap_authority_policy(
            policy_bytes
        )[0],
        "PF-REVOCATION-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )
    try:
        _FORMAL.parse_revocation_ledger_snapshot(
            snapshot_bytes, formal_policy, record_bytes
        )
    except _FORMAL.Rejected:
        _verify("produced snapshot failed formal consumer re-verification")
    return snapshot_bytes
