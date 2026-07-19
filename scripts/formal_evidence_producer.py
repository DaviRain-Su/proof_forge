#!/usr/bin/env python3
"""Formal finalization producer/publisher and support-binding producer.

This module constructs the unsigned, digest-addressed formal artifacts and
publishes them atomically.  Wire anchors:

- finalization digests and FinalizationRef: gate-catalog-finalization.md
  1846-1871; publish path
  ``<trusted-root>/finalized-formal/<catalog.id>/<RequiredTestSetV1.id>/<record.id>.json``
  with directory names derived only from record content (no caller alias),
  no-clobber staging, per-file fsync, directory fsync, and a receipt-last
  marker (``<record.id>.receipt.json`` carrying the FinalizationRef wire).
- SupportEvidenceBindingV1 wire (capabilities-extensions.md:222-226,
  schema ``proof-forge.support-evidence-binding.v1``, fields exactly
  ``schema,evidence,finalization,candidate,build,requirement,claimDigest,
  achieved,finalizedAt,expiresAt,revocationLedgerDigest``),
  SupportBindingRef (capabilities-extensions.md:61-66,217),
  binding digest domain ``pf.support-evidence-binding.v1``
  (capabilities-extensions.md:233-238), grade enum
  ``specified < artifact_validated < local_runtime <
  network_or_proof_validated`` (capabilities-extensions.md:134-136),
  claimDigest domain ``pf.support-claim.v1`` (capabilities-extensions.md
  :152-156), and the rule that ref fields must equal the binding body
  (capabilities-extensions.md:240-241).

Boundaries declared for this slice: the support-binding publish path
``<trusted-root>/support-bindings/<requirement.id>/<evidence.id>-<build.targetId>.json``
is a development convention (SPEC-CAP-001 pins receipt-last no-clobber
publication but no literal path); requirement payload resolution against
the requirement-semantics registry stays with the D3 resolver (the
RequirementKey is taken from the supplied SupportClaim payload);
SupportPredicate JSON spelling ``{variant,name,value}`` with the
capabilities-extensions.md:22-27 variant set is the development encoding
of the pinned algebra; EV revocation content checks read the
``revokedEvidenceId`` field of resolved evidence-revocation records.
Validation failures use ``PF-EVIDENCE-FORMAL-UNVERIFIED``; filesystem and
staging failures use ``PF-EVIDENCE-IO`` / ``PF-EVIDENCE-ATOMICITY``.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Tuple


def _load_formal_evidence() -> ModuleType:
    """Load the exact sibling formal consumer without a sys.path seam."""
    module_path = Path(__file__).resolve(strict=True)
    formal_path = module_path.with_name("formal_evidence.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_formal_evidence_for_producer",
        formal_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact formal evidence loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != formal_path.resolve(strict=True):
        raise ImportError("exact formal evidence origin changed")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    for name in (
        "Rejected",
        "FORMAL_EVIDENCE_REJECTION",
        "parse_formal_evidence_finalization",
        "FormalEvidenceFinalizationV1",
        "FinalizationRefV1",
        "FormalGateV1",
        "BuildIdentityV1",
        "BootstrapApprovalBindingV1",
        "FINALIZATION_SCHEMA",
        "EVF_ID_RE",
        "TARGET_ID_RE",
        "UTC_INSTANT_RE",
    ):
        if getattr(module, name, None) is None:
            raise ImportError("exact formal evidence ABI changed")
    return module


_FORMAL = _load_formal_evidence()
_CONSUMER = _FORMAL._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef
CandidateIdentity = _CONSUMER.CandidateIdentity
GateCatalogRefV1 = _CONSUMER.GateCatalogRefV1
BootstrapApprovalBindingV1 = _FORMAL.BootstrapApprovalBindingV1
BuildIdentityV1 = _FORMAL.BuildIdentityV1
FormalGateV1 = _FORMAL.FormalGateV1
FormalEvidenceFinalizationV1 = _FORMAL.FormalEvidenceFinalizationV1
FinalizationRefV1 = _FORMAL.FinalizationRefV1
canonical_pf_jcs = _CONSUMER.canonical_pf_jcs
FORMAL_EVIDENCE_REJECTION = _FORMAL.FORMAL_EVIDENCE_REJECTION
FINALIZATION_SCHEMA = _FORMAL.FINALIZATION_SCHEMA

SUPPORT_BINDING_SCHEMA = "proof-forge.support-evidence-binding.v1"
GRADE_ORDER = (
    "specified",
    "artifact_validated",
    "local_runtime",
    "network_or_proof_validated",
)
_GRADE_INDEX = {grade: index for index, grade in enumerate(GRADE_ORDER)}
_PREDICATE_VARIANTS = (
    "uint-at-least",
    "uint-at-most",
    "bool-equals",
    "enum-contains",
    "digest-equals",
)
_PREDICATE_VARIANT_INDEX = {
    variant: index for index, variant in enumerate(_PREDICATE_VARIANTS)
}
_REQUIREMENT_SEGMENT_RE = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")


class FormalEvidenceProducerError(Exception):
    """Stable producer failure; details never grant authority."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise FormalEvidenceProducerError(code, detail)


def _reject(detail: str) -> NoReturn:
    _fail(FORMAL_EVIDENCE_REJECTION, detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-EVIDENCE-IO", detail)


def _atomicity(detail: str) -> NoReturn:
    _fail("PF-EVIDENCE-ATOMICITY", detail)


def _formal_checked(validation, detail: str):
    try:
        return validation()
    except _FORMAL.Rejected:
        _reject(detail)
    except _CONSUMER.Rejected:
        _reject(detail)


@dataclass(frozen=True)
class FormalRecordInputsV1:
    """One-capture bundle of the exact authority inputs for a record."""

    record_bytes: bytes
    authority_policy_bytes: bytes
    required_test_set_bytes: bytes
    phase5_snapshot: object
    catalog_bytes: bytes
    catalog_approval_bytes: bytes
    session_containment_bytes: bytes
    freshness_authority_bytes: bytes
    private_scan_bytes: bytes
    revocation_ledger_bytes: bytes
    revocation_record_bytes: Tuple[bytes, ...]
    finalizer_identity_bytes: bytes
    approval_set_bytes: bytes
    task_receipt_bytes: Tuple[bytes, ...]
    verifier_receipt_bytes: bytes
    stage0_handoff_bytes: bytes


@dataclass(frozen=True)
class GateVectorV1:
    gateId: str
    evidenceRef: Tuple[str, Digest]
    grade: str


@dataclass(frozen=True)
class RequirementKeyV1:
    id: str
    version: str
    digest: Digest


@dataclass(frozen=True)
class SupportEvidenceBindingV1:
    schema: str
    evidence: Tuple[str, Digest]
    finalization: FinalizationRefV1
    candidate: CandidateIdentity
    build: BuildIdentityV1
    requirement: RequirementKeyV1
    claimDigest: Digest
    achieved: str
    finalizedAt: str
    expiresAt: str
    revocationLedgerDigest: Digest


@dataclass(frozen=True)
class SupportBindingRefV1:
    evidence: Tuple[str, Digest]
    finalization: FinalizationRefV1
    requirement: RequirementKeyV1
    claimDigest: Digest
    digest: Digest


def _digest_wire(digest: Digest) -> str:
    if type(digest) is not Digest or digest.algorithm != "sha256":
        _reject("digest values must be sha256 Digest records")
    return "sha256:" + digest.bytes.hex()


def _content_ref_wire(ref: ContentRef, where: str) -> dict:
    if type(ref) is not ContentRef:
        _reject(f"{where} must be a ContentRef")
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": _digest_wire(ref.digest),
    }


def _candidate_wire(candidate: CandidateIdentity, where: str) -> dict:
    if type(candidate) is not CandidateIdentity:
        _reject(f"{where} must be a CandidateIdentity")
    return {
        "commit": candidate.commit,
        "treeObjectId": candidate.treeObjectId,
        "archiveDigest": _digest_wire(candidate.archiveDigest),
        "digest": _digest_wire(candidate.digest),
    }


def _catalog_ref_wire(ref: GateCatalogRefV1, where: str) -> dict:
    if type(ref) is not GateCatalogRefV1:
        _reject(f"{where} must be a GateCatalogRefV1")
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "contentSha256": ref.contentSha256,
        "catalogDigest": ref.catalogDigest,
    }


def _evidence_ref_wire(ref: Tuple[str, Digest], where: str) -> dict:
    if (type(ref) is not tuple or len(ref) != 2
            or type(ref[0]) is not str or type(ref[1]) is not Digest):
        _reject(f"{where} must be an (EvidenceId, Digest) tuple")
    return {"id": ref[0], "digest": _digest_wire(ref[1])}


def _build_identity_wire(build: BuildIdentityV1, where: str) -> dict:
    if type(build) is not BuildIdentityV1:
        _reject(f"{where} must be a BuildIdentityV1")
    return {
        "targetId": build.targetId,
        "targetSemanticsVersion": build.targetSemanticsVersion,
        "targetSemanticsDigest": _digest_wire(build.targetSemanticsDigest),
        "codegenProfileId": build.codegenProfileId,
        "codegenProfileDigest": _digest_wire(build.codegenProfileDigest),
    }


def _gate_wire(gate: FormalGateV1, where: str) -> dict:
    if type(gate) is not FormalGateV1:
        _reject(f"{where} must be a FormalGateV1")
    return {
        "id": gate.id,
        "testIds": list(gate.testIds),
        "build": (
            None
            if gate.build is None
            else _build_identity_wire(gate.build, f"{where}.build")
        ),
        "evidenceRefs": [
            _evidence_ref_wire(ref, f"{where}.evidenceRefs")
            for ref in gate.evidenceRefs
        ],
    }


def produce_formal_evidence_finalization(
    *,
    identifier: str,
    candidate: CandidateIdentity,
    hostProfile: ContentRef,
    stage0Handoff: ContentRef,
    sessionContainment: ContentRef,
    requiredTestSet: ContentRef,
    catalog: GateCatalogRefV1,
    catalogApproval: ContentRef,
    gates: Tuple[FormalGateV1, ...],
    freshnessAuthority: ContentRef,
    finalizedAt: str,
    expiresAt: str,
    privateScan: ContentRef,
    revocationLedger: ContentRef,
    finalizer: ContentRef,
    bootstrapApproval: BootstrapApprovalBindingV1,
    inputs: FormalRecordInputsV1,
) -> Tuple[bytes, FinalizationRefV1]:
    """Construct, digest, and fully re-verify a finalization record.

    The produced bytes are immediately re-parsed through the complete
    consumer chain; any divergence fails closed before returning.
    """
    if type(inputs) is not FormalRecordInputsV1:
        _reject("record authority inputs must be a FormalRecordInputsV1")
    if type(bootstrapApproval) is not BootstrapApprovalBindingV1:
        _reject("bootstrapApproval must be a BootstrapApprovalBindingV1")
    if type(gates) is not tuple or not gates:
        _reject("gates must be a non-empty tuple")
    core_object = {
        "candidate": _candidate_wire(candidate, "candidate"),
        "hostProfile": _content_ref_wire(hostProfile, "hostProfile"),
        "stage0Handoff": _content_ref_wire(stage0Handoff, "stage0Handoff"),
        "sessionContainment": _content_ref_wire(
            sessionContainment, "sessionContainment"
        ),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "catalog": _catalog_ref_wire(catalog, "catalog"),
        "catalogApproval": _content_ref_wire(catalogApproval, "catalogApproval"),
        "gates": [
            _gate_wire(gate, f"gates[{index}]")
            for index, gate in enumerate(gates)
        ],
        "freshnessAuthority": _content_ref_wire(
            freshnessAuthority, "freshnessAuthority"
        ),
        "revocationLedger": _content_ref_wire(
            revocationLedger, "revocationLedger"
        ),
        "finalizer": _content_ref_wire(finalizer, "finalizer"),
        "bootstrapApproval": {
            "set": _content_ref_wire(
                bootstrapApproval.set, "bootstrapApproval.set"
            ),
            "verifierReceipt": {
                "id": bootstrapApproval.verifierReceipt.id,
                "digest": _digest_wire(
                    bootstrapApproval.verifierReceipt.digest
                ),
            },
        },
    }
    core_digest = hashlib.sha256(
        b"pf.formal-evidence-core.v1\x00" + canonical_pf_jcs(core_object)
    ).digest()
    set_object = {
        "evidenceCoreDigest": "sha256:" + core_digest.hex(),
        "privateScan": _content_ref_wire(privateScan, "privateScan"),
    }
    set_digest = hashlib.sha256(
        b"pf.formal-evidence-set.v1\x00" + canonical_pf_jcs(set_object)
    ).digest()
    record_wire = {
        "schema": FINALIZATION_SCHEMA,
        "id": identifier,
        "qualification": "formal",
        **core_object,
        "evidenceCoreDigest": "sha256:" + core_digest.hex(),
        "evidenceSetDigest": "sha256:" + set_digest.hex(),
        "finalizedAt": finalizedAt,
        "expiresAt": expiresAt,
        "privateScan": set_object["privateScan"],
    }
    record_bytes = canonical_pf_jcs(record_wire)
    _, ref = _formal_checked(
        lambda: _FORMAL.parse_formal_evidence_finalization(
            record_bytes,
            inputs.authority_policy_bytes,
            inputs.required_test_set_bytes,
            inputs.phase5_snapshot,
            inputs.catalog_bytes,
            inputs.catalog_approval_bytes,
            inputs.session_containment_bytes,
            inputs.freshness_authority_bytes,
            inputs.private_scan_bytes,
            inputs.revocation_ledger_bytes,
            inputs.revocation_record_bytes,
            inputs.finalizer_identity_bytes,
            inputs.approval_set_bytes,
            inputs.task_receipt_bytes,
            inputs.verifier_receipt_bytes,
            inputs.stage0_handoff_bytes,
        ),
        "produced record failed the full consumer re-verification",
    )
    return record_bytes, ref


def _read_record_identity(record_bytes: bytes) -> Tuple[str, str]:
    decoded = _formal_checked(
        lambda: _CONSUMER.decode_canonical_pf_jcs(record_bytes),
        "record bytes are not canonical PF-JCS",
    )
    if type(decoded) is not dict or decoded.get("schema") != FINALIZATION_SCHEMA:
        _reject("record bytes are not a finalization record")
    identifier = decoded.get("id")
    catalog = decoded.get("catalog")
    if type(identifier) is not str or type(catalog) is not dict:
        _reject("record lacks a usable id/catalog identity")
    catalog_id = catalog.get("id")
    if type(catalog_id) is not str:
        _reject("record catalog lacks a usable id")
    return identifier, catalog_id


def _resolved_required_set_id(
    required_test_set_bytes: bytes,
    authority_policy_bytes: bytes,
) -> str:
    required_set, _ = _formal_checked(
        lambda: _CONSUMER.parse_required_test_set(
            required_test_set_bytes, authority_policy_bytes
        ),
        "required test set bytes failed verification",
    )
    return required_set.id


def _require_trusted_root(trusted_root: str) -> str:
    if type(trusted_root) is not str or not trusted_root.startswith("/"):
        _io("trusted root must be an absolute path")
    if not os.path.isdir(trusted_root):
        _io("trusted root is not a directory")
    return trusted_root


def _fsync_directory(path: str) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _atomic_link(temp_path: str, final_path: str) -> None:
    try:
        os.link(temp_path, final_path)
    except FileExistsError:
        _atomicity("publish target already exists (no-clobber)")
    except OSError as error:
        _io(f"cannot link the publication into place: {error}")
    _fsync_directory(os.path.dirname(final_path))


def _stage_payload(
    staging_dir: str,
    final_path: str,
    payload: bytes,
) -> None:
    fd, temp_path = tempfile.mkstemp(
        prefix=".stage-", dir=staging_dir
    )
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, 0o444)
        _atomic_link(temp_path, final_path)
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def publish_finalization(
    record_bytes: bytes,
    ref: FinalizationRefV1,
    trusted_root: str,
    required_test_set_bytes: bytes,
    authority_policy_bytes: bytes,
) -> str:
    """Publish a validated record to the spec-frozen finalized-formal path.

    Returns the exact record path; the receipt marker carrying the
    FinalizationRef wire is always written last.
    """
    if type(ref) is not FinalizationRefV1:
        _reject("FinalizationRef must be a FinalizationRefV1")
    trusted_root = _require_trusted_root(trusted_root)
    identifier, catalog_id = _read_record_identity(record_bytes)
    required_set_id = _resolved_required_set_id(
        required_test_set_bytes, authority_policy_bytes
    )
    if ref.id != identifier:
        _reject("FinalizationRef id does not match the record id")
    expected_digest = hashlib.sha256(
        b"pf.formal-evidence-finalization.v1\x00" + record_bytes
    ).digest()
    if ref.digest.bytes != expected_digest:
        _reject("FinalizationRef digest does not match the record")
    record_dir = os.path.join(
        trusted_root, "finalized-formal", catalog_id, required_set_id
    )
    os.makedirs(record_dir, exist_ok=True)
    final_path = os.path.join(record_dir, f"{identifier}.json")
    receipt_path = os.path.join(record_dir, f"{identifier}.receipt.json")
    if os.path.lexists(final_path) or os.path.lexists(receipt_path):
        _atomicity("finalization publication already exists (no-clobber)")
    receipt_wire = canonical_pf_jcs({
        "schema": ref.schema,
        "id": ref.id,
        "digest": _digest_wire(ref.digest),
    })
    _stage_payload(record_dir, final_path, record_bytes)
    _stage_payload(record_dir, receipt_path, receipt_wire)
    return final_path


def _parse_predicates(value: object, where: str) -> Tuple[dict, ...]:
    if type(value) is not list:
        _reject(f"{where} must be an array")
    assert isinstance(value, list)
    predicates = []
    for index, entry in enumerate(value):
        entry_where = f"{where}[{index}]"
        if type(entry) is not dict or set(entry.keys()) != {
            "variant", "name", "value",
        }:
            _reject(f"{entry_where} must be a closed SupportPredicate")
        variant = entry["variant"]
        if variant not in _PREDICATE_VARIANT_INDEX:
            _reject(f"{entry_where}.variant is not a pinned variant")
        name = entry["name"]
        if type(name) is not str or not 1 <= len(name) <= 127:
            _reject(f"{entry_where}.name must be 1..127 bytes")
        assert isinstance(name, str)
        predicate_value = entry["value"]
        if variant in ("uint-at-least", "uint-at-most"):
            if type(predicate_value) is not int or not 0 <= predicate_value <= (
                (1 << 53) - 1
            ):
                _reject(f"{entry_where}.value must be a UInt64")
        elif variant == "bool-equals":
            if type(predicate_value) is not bool:
                _reject(f"{entry_where}.value must be a Bool")
        elif variant == "enum-contains":
            if (type(predicate_value) is not list or not predicate_value
                    or any(type(item) is not str for item in predicate_value)):
                _reject(f"{entry_where}.value must be a non-empty string array")
        else:
            try:
                _CONSUMER.parse_digest(predicate_value)
            except _CONSUMER.Rejected:
                _reject(f"{entry_where}.value must be a Digest wire value")
        predicates.append({
            "variant": variant,
            "name": name,
            "value": predicate_value,
        })
    ordered = sorted(
        predicates,
        key=lambda item: (
            item["name"],
            _PREDICATE_VARIANT_INDEX[item["variant"]],
            canonical_pf_jcs(item),
        ),
    )
    if [
        (item["name"], item["variant"]) for item in ordered
    ] != [(item["name"], item["variant"]) for item in predicates]:
        _reject(f"{where} must be unique ascending by (name, variant)")
    keys = [(item["name"], item["variant"]) for item in ordered]
    if len(set(keys)) != len(keys):
        _reject(f"{where} must not repeat a (name, variant) pair")
    return tuple(ordered)


def _parse_requirement_key(value: object, where: str) -> RequirementKeyV1:
    if type(value) is not dict or set(value.keys()) != {
        "id", "version", "digest",
    }:
        _reject(f"{where} must be a closed RequirementKey")
    identifier = value["id"]
    if type(identifier) is not str or not 1 <= len(identifier) <= 127:
        _reject(f"{where}.id must be 1..127 bytes")
    assert isinstance(identifier, str)
    segments = identifier.split(".")
    if len(segments) < 2 or any(
        _REQUIREMENT_SEGMENT_RE.fullmatch(segment) is None
        for segment in segments
    ):
        _reject(f"{where}.id must use the RequirementId grammar")
    version = value["version"]
    try:
        checked_version = _CONSUMER._require_semver(version, f"{where}.version")
    except _CONSUMER.Rejected:
        _reject(f"{where}.version must be exact SemVer")
    try:
        digest = _CONSUMER.parse_digest(value["digest"])
    except _CONSUMER.Rejected:
        _reject(f"{where}.digest must be the SPEC-COMMON Digest wire form")
    return RequirementKeyV1(identifier, checked_version, digest)


def _parse_support_claim(value: object, where: str) -> Tuple[RequirementKeyV1, dict]:
    if type(value) is not dict or set(value.keys()) != {
        "requirement", "predicates",
    }:
        _reject(f"{where} must be a closed SupportClaim")
    requirement = _parse_requirement_key(
        value["requirement"], f"{where}.requirement"
    )
    predicates = _parse_predicates(value["predicates"], f"{where}.predicates")
    return requirement, {
        "requirement": {
            "id": requirement.id,
            "version": requirement.version,
            "digest": _digest_wire(requirement.digest),
        },
        "predicates": list(predicates),
    }


def _validate_binding_wire(binding_wire: dict, where: str) -> None:
    if type(binding_wire) is not dict or set(binding_wire.keys()) != {
        "schema",
        "evidence",
        "finalization",
        "candidate",
        "build",
        "requirement",
        "claimDigest",
        "achieved",
        "finalizedAt",
        "expiresAt",
        "revocationLedgerDigest",
    }:
        _reject(f"{where} must be the closed SupportEvidenceBinding wire")
    if binding_wire["schema"] != SUPPORT_BINDING_SCHEMA:
        _reject(f"{where}.schema is not support-evidence-binding.v1")
    if binding_wire["achieved"] not in _GRADE_INDEX:
        _reject(f"{where}.achieved is not a SupportEvidenceGrade")
    finalization = binding_wire["finalization"]
    if type(finalization) is not dict or set(finalization.keys()) != {
        "schema", "id", "digest",
    }:
        _reject(f"{where}.finalization must be a closed FinalizationRef")
    if finalization["schema"] != FINALIZATION_SCHEMA:
        _reject(f"{where}.finalization must reference a formal finalization")


def produce_support_binding(
    *,
    evidence_bytes: bytes,
    evidence_id: str,
    record_inputs: FormalRecordInputsV1,
    build: BuildIdentityV1,
    support_claim: dict,
    gate_vectors: Tuple[GateVectorV1, ...],
) -> Tuple[bytes, SupportBindingRefV1]:
    """Construct and fully bind a SupportEvidenceBindingV1.

    The finalization record is re-verified through the complete consumer
    chain from ``record_inputs`` before any binding field is accepted.
    """
    if type(record_inputs) is not FormalRecordInputsV1:
        _reject("record authority inputs must be a FormalRecordInputsV1")
    if type(evidence_bytes) is not bytes or not evidence_bytes:
        _reject("evidence must be exact canonical EV bytes")
    if type(evidence_id) is not str:
        _reject("evidence id must be text")
    record, finalization_ref = _formal_checked(
        lambda: _FORMAL.parse_formal_evidence_finalization(
            record_inputs.record_bytes,
            record_inputs.authority_policy_bytes,
            record_inputs.required_test_set_bytes,
            record_inputs.phase5_snapshot,
            record_inputs.catalog_bytes,
            record_inputs.catalog_approval_bytes,
            record_inputs.session_containment_bytes,
            record_inputs.freshness_authority_bytes,
            record_inputs.private_scan_bytes,
            record_inputs.revocation_ledger_bytes,
            record_inputs.revocation_record_bytes,
            record_inputs.finalizer_identity_bytes,
            record_inputs.approval_set_bytes,
            record_inputs.task_receipt_bytes,
            record_inputs.verifier_receipt_bytes,
            record_inputs.stage0_handoff_bytes,
        ),
        "finalization record failed full re-verification",
    )
    try:
        checked_evidence_id = _CONSUMER._parse_compact_gregorian_id(
            evidence_id, _CONSUMER.EVIDENCE_ID_RE, 3, "evidence id"
        )
    except _CONSUMER.Rejected:
        _reject("evidence id must be a real EV-YYYYMMDD-NNNN id")
    evidence_digest = Digest(
        "sha256", hashlib.sha256(evidence_bytes).digest()
    )
    evidence_ref = (checked_evidence_id, evidence_digest)
    all_refs = {
        ref for gate in record.gates for ref in gate.evidenceRefs
    }
    if evidence_ref not in all_refs:
        _reject("binding evidence is not covered by the finalization record")
    revoked_ids = set()
    for record_bytes_item in record_inputs.revocation_record_bytes:
        record_obj = _formal_checked(
            lambda record_bytes_item=record_bytes_item: (
                _CONSUMER.decode_canonical_pf_jcs(record_bytes_item)
            ),
            "revocation record bytes are not canonical PF-JCS",
        )
        if type(record_obj) is dict:
            revoked_id = record_obj.get("revokedEvidenceId")
            if type(revoked_id) is str:
                revoked_ids.add(revoked_id)
    if checked_evidence_id in revoked_ids:
        _reject("binding evidence is revoked by the resolved ledger")
    if type(build) is not BuildIdentityV1:
        _reject("build must be a BuildIdentityV1")
    requirement, claim_wire = _parse_support_claim(
        support_claim, "support_claim"
    )
    claim_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.support-claim.v1\x00" + canonical_pf_jcs(claim_wire)
        ).digest(),
    )
    if type(gate_vectors) is not tuple or not gate_vectors:
        _reject("gate vectors must be a non-empty tuple")
    for index, vector in enumerate(gate_vectors):
        if type(vector) is not GateVectorV1:
            _reject(f"gate_vectors[{index}] must be a GateVectorV1")
        if vector.grade not in _GRADE_INDEX:
            _reject(f"gate_vectors[{index}].grade is not a valid grade")
        if vector.evidenceRef not in all_refs:
            _reject(
                f"gate_vectors[{index}] references an evidenceRef outside "
                "the finalization record"
            )
    vector_gate_ids = tuple(vector.gateId for vector in gate_vectors)
    record_gate_ids = tuple(gate.id for gate in record.gates)
    if set(vector_gate_ids) != set(record_gate_ids) or len(
        set(vector_gate_ids)
    ) != len(vector_gate_ids):
        _reject("gate vectors must cover every record gate exactly once")
    achieved = min(
        (vector.grade for vector in gate_vectors),
        key=_GRADE_INDEX.__getitem__,
    )
    if record.finalizedAt >= record.expiresAt:
        _reject("finalization record window is not positive")
    binding_wire = {
        "schema": SUPPORT_BINDING_SCHEMA,
        "evidence": _evidence_ref_wire(evidence_ref, "evidence"),
        "finalization": {
            "schema": finalization_ref.schema,
            "id": finalization_ref.id,
            "digest": _digest_wire(finalization_ref.digest),
        },
        "candidate": _candidate_wire(record.candidate, "candidate"),
        "build": _build_identity_wire(build, "build"),
        "requirement": claim_wire["requirement"],
        "claimDigest": _digest_wire(claim_digest),
        "achieved": achieved,
        "finalizedAt": record.finalizedAt,
        "expiresAt": record.expiresAt,
        "revocationLedgerDigest": _digest_wire(
            record.revocationLedger.digest
        ),
    }
    _validate_binding_wire(binding_wire, "produced binding")
    binding_bytes = canonical_pf_jcs(binding_wire)
    binding_digest = Digest(
        "sha256",
        hashlib.sha256(
            b"pf.support-evidence-binding.v1\x00" + binding_bytes
        ).digest(),
    )
    ref = SupportBindingRefV1(
        evidence_ref,
        finalization_ref,
        requirement,
        claim_digest,
        binding_digest,
    )
    return binding_bytes, ref


def publish_support_binding(
    binding_bytes: bytes,
    ref: SupportBindingRefV1,
    trusted_root: str,
) -> str:
    """Publish a binding receipt-last at its derived no-clobber path."""
    if type(ref) is not SupportBindingRefV1:
        _reject("SupportBindingRef must be a SupportBindingRefV1")
    trusted_root = _require_trusted_root(trusted_root)
    binding_wire = _formal_checked(
        lambda: _CONSUMER.decode_canonical_pf_jcs(binding_bytes),
        "binding bytes are not canonical PF-JCS",
    )
    _validate_binding_wire(binding_wire, "binding")
    expected_digest = hashlib.sha256(
        b"pf.support-evidence-binding.v1\x00" + binding_bytes
    ).digest()
    if ref.digest.bytes != expected_digest:
        _reject("SupportBindingRef digest does not match the binding")
    ref_wire = {
        "evidence": binding_wire["evidence"],
        "finalization": binding_wire["finalization"],
        "requirement": binding_wire["requirement"],
        "claimDigest": binding_wire["claimDigest"],
        "digest": _digest_wire(ref.digest),
    }
    if ref_wire["evidence"]["id"] != ref.evidence[0]:
        _reject("SupportBindingRef evidence does not match the binding")
    if ref_wire["finalization"] != {
        "schema": ref.finalization.schema,
        "id": ref.finalization.id,
        "digest": _digest_wire(ref.finalization.digest),
    }:
        _reject("SupportBindingRef finalization does not match the binding")
    if ref_wire["requirement"] != {
        "id": ref.requirement.id,
        "version": ref.requirement.version,
        "digest": _digest_wire(ref.requirement.digest),
    }:
        _reject("SupportBindingRef requirement does not match the binding")
    if ref_wire["claimDigest"] != _digest_wire(ref.claimDigest):
        _reject("SupportBindingRef claimDigest does not match the binding")
    binding_dir = os.path.join(
        trusted_root, "support-bindings", ref.requirement.id
    )
    os.makedirs(binding_dir, exist_ok=True)
    base_name = f"{ref.evidence[0]}-{ref_evidence_build_target(binding_wire)}"
    final_path = os.path.join(binding_dir, f"{base_name}.json")
    receipt_path = os.path.join(binding_dir, f"{base_name}.receipt.json")
    if os.path.lexists(final_path) or os.path.lexists(receipt_path):
        _atomicity("support binding publication already exists (no-clobber)")
    _stage_payload(binding_dir, final_path, binding_bytes)
    _stage_payload(
        binding_dir, receipt_path, canonical_pf_jcs(ref_wire)
    )
    return final_path


def ref_evidence_build_target(binding_wire: dict) -> str:
    build = binding_wire.get("build")
    if type(build) is not dict or type(build.get("targetId")) is not str:
        _reject("binding build lacks a usable targetId")
    return build["targetId"]
