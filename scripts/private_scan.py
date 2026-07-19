#!/usr/bin/env python3
"""Private scan policy validator, deny-marker scanner, and signed
PrivateScanReceiptV1 producer (TASK-D0-07 slice S2).

Key custody discipline (same as bootstrap_task_producers.py): signing takes
the exact 32-byte Ed25519 seed as an explicit call parameter.  This module
never generates random or fixed seeds, never reads key material from disk,
environment, or CLI, and never persists key material; seeds are used only for
the duration of the call and never appear in return values, logs, or
exception details.  Member bytes are safe-read (O_NOFOLLOW, regular file,
bounded) from caller-designated absolute paths; the module performs no other
I/O beyond locating its exact sibling modules at import time.

Wire authority: the receipt shape follows gate-catalog-finalization.md
1702-1711/1754-1775 with the formal consumer
(formal_evidence.parse_private_scan_receipt) as the shape authority: closed
PrivateScanReceiptV1 fields, scannedEvidenceRefs unique ascending by
(id, digest), ScannedMemberRefV1 = {evidence:{id,digest}, role, path, size,
digest} unique ascending by (evidence.id, evidence.digest, path), findings
empty and result "clean", signatures under policy privateScanRule
(quality+security, two distinct principals) with the frozen
statement/signature domains.  Member size/digest are always recomputed from
the safe-read bytes by this module, never taken from the caller.

Marker semantics (slice-level development convention; no spec text pins them
yet): a denyContentMarkers entry is a byte substring search over the raw
member bytes; a denyPathMarkers entry matches when it appears as a substring
of any single path segment.  scannerDigest binds the scanner executable:
"sha256:" + SHA-256 of the scanner executable bytes supplied by the caller
at call time.  Slice scope is the fixture namespace (ADR-0018): nothing here
is formal or hermetic evidence.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Mapping, NoReturn, Optional, Tuple


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
        "proof_forge_bootstrap_task_producers_for_private_scan",
    )


def _load_formal_evidence() -> ModuleType:
    module_path = Path(__file__).resolve(strict=True)
    return _load_module(
        module_path.with_name("formal_evidence.py"),
        "proof_forge_formal_evidence_for_private_scan",
    )


_PRODUCER = _load_bootstrap_task_producers()
_CONSUMER = _PRODUCER._CONSUMER
_FORMAL = _load_formal_evidence()

PRIVATE_SCAN_POLICY_SCHEMA = "proof-forge.private-scan-policy.v1"
PRIVATE_SCAN_RECEIPT_SCHEMA = "proof-forge.private-scan-receipt.v1"
POLICY_DIGEST_DOMAIN = b"pf.private-scan-policy.v1\x00"
STATEMENT_DOMAIN = b"pf.private-scan-receipt-statement.v1\x00"
SIGNATURE_DOMAIN = b"pf.private-scan-receipt-signature.v1\x00"
_POLICY_FIELDS = (
    "schema",
    "id",
    "version",
    "denyContentMarkers",
    "denyPathMarkers",
    "maximumFindings",
)
_MEMBER_SPEC_FIELDS = ("evidence", "role", "path")
MAX_MEMBER_BYTES = 16 * 1024 * 1024


class PrivateScanError(Exception):
    """Stable private-scan failure; never carries key material."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise PrivateScanError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-PRIVATE-SCAN-SCHEMA", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-PRIVATE-SCAN-IO", detail)


def _sign(detail: str) -> NoReturn:
    _fail("PF-PRIVATE-SCAN-SIGN", detail)


def _verify(detail: str) -> NoReturn:
    _fail("PF-PRIVATE-SCAN-VERIFY", detail)


def _consumer_checked(validation, code: str, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _fail(code, detail)
    except (TypeError, ValueError, AttributeError, IndexError, KeyError):
        _fail(code, detail)


@dataclass(frozen=True)
class PrivateScanPolicy:
    schema: str
    id: str
    version: str
    denyContentMarkers: Tuple[bytes, ...]
    denyPathMarkers: Tuple[str, ...]
    maximumFindings: int


@dataclass(frozen=True)
class ScannedMember:
    size: int
    digest: str


@dataclass(frozen=True)
class ScanOutcome:
    members: Mapping[str, ScannedMember]
    findings: Tuple[dict, ...]


def _require_marker_list(value: object, where: str) -> Tuple[str, ...]:
    if type(value) is not list or any(type(item) is not str or not item
                                      for item in value):
        _schema(f"{where} must be an array of non-empty text")
    assert isinstance(value, list)
    markers = tuple(value)
    # Uniqueness only: the committed real policy document (pinned by ContentRef
    # digest in the signed authority policy) is not sorted, and re-sorting it
    # would change the pinned digest.  Order is cryptographically bound by the
    # policy ref, so it is not a security property of the validator.
    if len(set(markers)) != len(markers):
        _schema(f"{where} must not contain duplicates")
    return markers


def parse_private_scan_policy(policy_bytes: bytes) -> PrivateScanPolicy:
    """Validate the exact private-scan policy document wire."""
    if type(policy_bytes) is not bytes or not policy_bytes:
        _schema("private scan policy must be non-empty bytes")
    try:
        decoded = json.loads(policy_bytes.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _schema("private scan policy is not valid JSON")
    if type(decoded) is not dict:
        _schema("private scan policy must be a JSON object")
    if set(decoded) != set(_POLICY_FIELDS):
        _schema("private scan policy must be a closed object")
    if decoded["schema"] != PRIVATE_SCAN_POLICY_SCHEMA:
        _schema("private scan policy schema is not v1")
    identifier = _consumer_checked(
        lambda: _CONSUMER._require_ascii_text(
            decoded["id"], _CONSUMER.PROFILE_ID_RE,
            "PrivateScanPolicyV1.id", 127
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "private scan policy id must use the ContentRef id grammar",
    )
    version = _consumer_checked(
        lambda: _CONSUMER._require_semver(
            decoded["version"], "PrivateScanPolicyV1.version"
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "private scan policy version must be exact SemVer",
    )
    content_markers = _require_marker_list(
        decoded["denyContentMarkers"], "PrivateScanPolicyV1.denyContentMarkers"
    )
    path_markers = _require_marker_list(
        decoded["denyPathMarkers"], "PrivateScanPolicyV1.denyPathMarkers"
    )
    maximum = decoded["maximumFindings"]
    if type(maximum) is not int or maximum < 0:
        _schema("PrivateScanPolicyV1.maximumFindings must be a non-negative integer")
    return PrivateScanPolicy(
        PRIVATE_SCAN_POLICY_SCHEMA,
        identifier,
        version,
        tuple(marker.encode("utf-8") for marker in content_markers),
        path_markers,
        maximum,
    )


def private_scan_policy_ref(policy_bytes: bytes) -> dict:
    """Derive the exact ContentRef wire for a private-scan policy document."""
    policy = parse_private_scan_policy(policy_bytes)
    decoded = json.loads(policy_bytes.decode("utf-8"))
    return {
        "schema": PRIVATE_SCAN_POLICY_SCHEMA,
        "id": policy.id,
        "version": policy.version,
        "digest": "sha256:" + hashlib.sha256(
            POLICY_DIGEST_DOMAIN + _CONSUMER.canonical_pf_jcs(decoded)
        ).hexdigest(),
    }


def _require_project_path(value: object, where: str) -> str:
    if type(value) is not str:
        _schema(f"{where} must be a ProjectRelativePath")
    assert isinstance(value, str)
    encoded = value.encode("utf-8")
    if not 1 <= len(encoded) <= 1024:
        _schema(f"{where} must be 1..1024 UTF-8 bytes")
    if value.startswith("/") or "\\" in value:
        _schema(f"{where} must not be absolute or contain a backslash")
    segments = value.split("/")
    if any(segment in ("", ".", "..") for segment in segments):
        _schema(f"{where} must not contain empty/dot segments")
    if len(value) > 1 and value[1] == ":":
        _schema(f"{where} must not use a drive prefix")
    if any(unicodedata.category(character) == "Cc" for character in value):
        _schema(f"{where} must not contain control characters")
    return value


def _safe_read_member(relative: str, absolute: str) -> bytes:
    if type(absolute) is not str or not os.path.isabs(absolute):
        _io(f"member {relative}: manifest path must be absolute")
    try:
        fd = os.open(absolute, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        _io(f"member {relative}: cannot safe-open the member file")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _io(f"member {relative}: member is not a regular file")
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
            if offset > MAX_MEMBER_BYTES:
                _io(f"member {relative}: member exceeds the input maximum")
        return b"".join(chunks)
    finally:
        os.close(fd)


def scan_bundle_members(
    manifest: Mapping[str, str],
    policy: PrivateScanPolicy,
) -> ScanOutcome:
    """Safe-read every manifest member and apply the deny-marker policy."""
    if type(policy) is not PrivateScanPolicy:
        _schema("scan requires a validated PrivateScanPolicy")
    if type(manifest) is not dict or any(
        type(key) is not str or type(value) is not str
        for key, value in manifest.items()
    ):
        _schema("member manifest must map ProjectRelativePath to absolute path")
    members = {}
    findings = []
    for relative in sorted(manifest):
        _require_project_path(relative, "member manifest path")
        payload = _safe_read_member(relative, manifest[relative])
        members[relative] = ScannedMember(len(payload), hashlib.sha256(payload).hexdigest())
        for segment in relative.split("/"):
            for marker in policy.denyPathMarkers:
                if marker in segment:
                    findings.append(
                        {"kind": "path", "marker": marker, "path": relative}
                    )
        for marker in policy.denyContentMarkers:
            if marker in payload:
                findings.append(
                    {
                        "kind": "content",
                        "marker": marker.decode("utf-8"),
                        "path": relative,
                    }
                )
    findings.sort(key=lambda item: (item["path"], item["kind"], item["marker"]))
    return ScanOutcome(members, tuple(findings))


def produce_private_scan_receipt(
    *,
    id: str,
    version: str,
    candidate: dict,
    evidence_core_digest: str,
    scanner_executable_bytes: bytes,
    authority_policy_bytes: bytes,
    scan_policy_bytes: bytes,
    scanned_evidence_refs: Tuple[dict, ...],
    member_specs: Tuple[dict, ...],
    manifest: Mapping[str, str],
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-verify a PrivateScanReceiptV1.

    Member size/digest are recomputed from the safe-read member bytes; any
    scan finding, coverage mismatch, or signature-rule failure aborts before
    a receipt is returned.
    """
    identifier = _consumer_checked(
        lambda: _CONSUMER._require_ascii_text(
            id, _CONSUMER.PROFILE_ID_RE, "PrivateScanReceiptV1.id", 127
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "receipt id must use the ContentRef id grammar",
    )
    receipt_version = _consumer_checked(
        lambda: _CONSUMER._require_semver(
            version, "PrivateScanReceiptV1.version"
        ),
        "PF-PRIVATE-SCAN-SCHEMA",
        "receipt version must be exact SemVer",
    )
    parsed_candidate = _consumer_checked(
        lambda: _CONSUMER.parse_candidate_identity(candidate),
        "PF-PRIVATE-SCAN-SCHEMA",
        "receipt candidate is not a valid CandidateIdentity",
    )
    del parsed_candidate
    _consumer_checked(
        lambda: _CONSUMER.parse_digest(evidence_core_digest),
        "PF-PRIVATE-SCAN-SCHEMA",
        "evidenceCoreDigest must be the SPEC-COMMON Digest wire form",
    )
    if type(scanner_executable_bytes) is not bytes or not scanner_executable_bytes:
        _schema("scanner executable must be non-empty bytes")
    scanner_digest = "sha256:" + hashlib.sha256(scanner_executable_bytes).hexdigest()
    _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_authority_policy(
            authority_policy_bytes
        ),
        "PF-PRIVATE-SCAN-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )
    policy = parse_private_scan_policy(scan_policy_bytes)
    policy_ref = private_scan_policy_ref(scan_policy_bytes)
    outcome = scan_bundle_members(manifest, policy)
    if outcome.findings or len(outcome.findings) > policy.maximumFindings:
        _verify("scan findings exceed the policy maximumFindings")

    if type(scanned_evidence_refs) is not tuple:
        _schema("scannedEvidenceRefs must be a tuple")
    refs = []
    for entry in scanned_evidence_refs:
        obj = _consumer_checked(
            lambda entry=entry: _CONSUMER._require_exact_keys(
                entry, ("id", "digest"), "PrivateScanReceiptV1.scannedEvidenceRefs"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            "scannedEvidenceRefs entries must be closed {id, digest} refs",
        )
        evidence_id = _consumer_checked(
            lambda obj=obj: _CONSUMER._parse_compact_gregorian_id(
                obj["id"], _CONSUMER.EVIDENCE_ID_RE, 3,
                "PrivateScanReceiptV1.scannedEvidenceRefs"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            "scannedEvidenceRefs id must be a real EV-YYYYMMDD-NNNN id",
        )
        _consumer_checked(
            lambda obj=obj: _CONSUMER.parse_digest(obj["digest"]),
            "PF-PRIVATE-SCAN-SCHEMA",
            "scannedEvidenceRefs digest must be the SPEC-COMMON Digest wire form",
        )
        refs.append({"id": evidence_id, "digest": obj["digest"]})
    ref_keys = [(item["id"], bytes.fromhex(item["digest"][7:])) for item in refs]
    if len(set(ref_keys)) != len(ref_keys):
        _schema("scannedEvidenceRefs must not contain duplicates")
    refs = [item for _, item in sorted(zip(ref_keys, refs))]
    ref_set = set(ref_keys)

    if type(member_specs) is not tuple:
        _schema("member specs must be a tuple")
    members = []
    seen_member_keys = set()
    for index, spec in enumerate(member_specs):
        where = f"PrivateScanReceiptV1.scannedMembers[{index}]"
        obj = _consumer_checked(
            lambda spec=spec, where=where: _CONSUMER._require_exact_keys(
                spec, _MEMBER_SPEC_FIELDS, where
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            f"{where} must be a closed member spec",
        )
        evidence = _consumer_checked(
            lambda obj=obj, where=where: _CONSUMER._require_exact_keys(
                obj["evidence"], ("id", "digest"), f"{where}.evidence"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            f"{where}.evidence must be a closed {{id, digest}} ref",
        )
        evidence_id = _consumer_checked(
            lambda evidence=evidence: _CONSUMER._parse_compact_gregorian_id(
                evidence["id"], _CONSUMER.EVIDENCE_ID_RE, 3,
                "PrivateScanReceiptV1.scannedMembers.evidence"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            f"{where}.evidence.id must be a real EV-YYYYMMDD-NNNN id",
        )
        _consumer_checked(
            lambda evidence=evidence: _CONSUMER.parse_digest(evidence["digest"]),
            "PF-PRIVATE-SCAN-SCHEMA",
            f"{where}.evidence.digest must be the SPEC-COMMON Digest wire form",
        )
        role = _consumer_checked(
            lambda obj=obj, where=where: _CONSUMER._require_safe_id(
                obj["role"], f"{where}.role"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            f"{where}.role must be a safe-id",
        )
        path = _require_project_path(obj["path"], f"{where}.path")
        member_key = (evidence_id, bytes.fromhex(evidence["digest"][7:]))
        if member_key not in ref_set:
            _verify("member evidence is not in scannedEvidenceRefs")
        tuple_key = (evidence_id, bytes.fromhex(evidence["digest"][7:]), path)
        if tuple_key in seen_member_keys:
            _schema("duplicate (evidence,path) member")
        seen_member_keys.add(tuple_key)
        scanned = outcome.members.get(path)
        if scanned is None:
            _verify("referenced member is not in the manifest")
        members.append(
            (
                tuple_key,
                {
                    "evidence": {"id": evidence_id, "digest": evidence["digest"]},
                    "role": role,
                    "path": path,
                    "size": scanned.size,
                    "digest": "sha256:" + scanned.digest,
                },
            )
        )
    referenced_paths = {key[2] for key in seen_member_keys}
    if referenced_paths != set(outcome.members):
        _verify("manifest carries a member not referenced by any evidence")
    members = [item for _, item in sorted(members)]

    statement = {
        "schema": PRIVATE_SCAN_RECEIPT_SCHEMA,
        "id": identifier,
        "version": receipt_version,
        "candidate": candidate,
        "evidenceCoreDigest": evidence_core_digest,
        "scannerDigest": scanner_digest,
        "policy": policy_ref,
        "scannedEvidenceRefs": refs,
        "scannedMembers": members,
        "findings": [],
        "result": "clean",
    }
    statement_digest = hashlib.sha256(
        STATEMENT_DOMAIN + _CONSUMER.canonical_pf_jcs(statement)
    ).digest()
    message = SIGNATURE_DOMAIN + statement_digest
    if type(signers) is not tuple or not signers:
        _schema("receipt signers must be a non-empty tuple")
    key_ids = tuple(key_id for key_id, _ in signers)
    if key_ids != tuple(sorted(key_ids)) or len(set(key_ids)) != len(key_ids):
        _schema("receipt signers must be unique ascending by keyId")
    signatures = []
    for key_id, seed in signers:
        _consumer_checked(
            lambda key_id=key_id: _CONSUMER._require_safe_id(
                key_id, "PrivateScanReceiptV1.signatures"
            ),
            "PF-PRIVATE-SCAN-SCHEMA",
            "receipt signer keyId must be a safe-id",
        )
        if type(seed) is not bytes or len(seed) != 32:
            _sign("invalid signing input")
        signatures.append(
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": _PRODUCER.sign_ed25519(seed, message).hex(),
            }
        )
    wire = {**statement, "signatures": signatures}
    receipt_bytes = _CONSUMER.canonical_pf_jcs(wire)
    formal_policy = _consumer_checked(
        lambda: _FORMAL._CONSUMER.parse_bootstrap_authority_policy(
            authority_policy_bytes
        )[0],
        "PF-PRIVATE-SCAN-VERIFY",
        "authority policy bytes are not a valid signed policy",
    )
    try:
        _FORMAL.parse_private_scan_receipt(receipt_bytes, formal_policy)
    except _FORMAL.Rejected:
        _verify("produced receipt failed formal consumer re-verification")
    return receipt_bytes
