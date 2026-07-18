#!/usr/bin/env python3
"""Pure, dependency-free producer/signer for bootstrap task objects.

Key custody discipline: every signing entry takes the exact 32-byte Ed25519
seed as an explicit call parameter.  This module never generates random or
fixed seeds, never reads key material from disk, environment, or CLI, and
never persists key material; seeds are used only for the duration of the
call and never appear in return values, logs, or exception details.  Real
genesis/authority private keys are held offline by humans; this module only
processes key material the caller supplies for the immediate invocation.

The module deliberately performs no filesystem, socket, environment, or CLI
I/O beyond locating its exact sibling consumer module at import time.  All
construction-time validation reuses the sibling consumer module's types and
validators read-only: each producer builds the unsigned statement, derives
the signature message with the same three exact derivation domains as the
consumer, signs, re-attaches the signature field, and then re-validates the
complete signed wire through the consumer's own structural preflight before
returning canonical PF-JCS bytes.  Producing a signature is not an authority
act: protected execution, authority-store publication, and activation remain
outside this module.
"""

from __future__ import annotations

import hashlib
import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Tuple


_CONSUMER_ABI_NAMES = (
    "BOOTSTRAP_REJECTION",
    "Rejected",
    "Digest",
    "ContentRef",
    "CandidateIdentity",
    "ApprovalRuleV1",
    "BootstrapAuthorityPrincipalV1",
    "BootstrapAuthorityTaskRuleV1",
    "BootstrapAuthorityVerifierV1",
    "ApprovalSignatureV1",
    "NormativeDocumentRefV1",
    "EvidenceRef",
    "TaskApprovalRefV1",
    "BootstrapTaskVerifierReceiptRefV1",
    "IndependentReviewRefV1",
    "TaskApprovalV1",
    "GateCatalogRefV1",
    "canonical_pf_jcs",
    "verify_ed25519",
    "_scalar_multiply",
    "_encode_point",
    "_BASE",
    "_L",
    "parse_bootstrap_authority_policy",
    "_preflight_required_test_set",
    "_finalize_required_test_set",
    "_preflight_task_approval",
    "_preflight_bootstrap_task_verifier_receipt",
    "_preflight_bootstrap_approval_set",
    "_preflight_bootstrap_approval_verifier_receipt",
    "_preflight_formal_gate_catalog_approval",
    "_require_signature_policy_membership",
    "_require_signature_rule",
    "_verify_approval_signatures",
)


def _load_bootstrap_task_objects() -> ModuleType:
    """Load the exact sibling consumer module without a sys.path authority seam."""
    producer_path = Path(__file__).resolve(strict=True)
    consumer_path = producer_path.with_name("bootstrap_task_objects.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_task_objects_for_producers",
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

Rejected = _CONSUMER.Rejected
Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef
CandidateIdentity = _CONSUMER.CandidateIdentity
ApprovalRuleV1 = _CONSUMER.ApprovalRuleV1
BootstrapAuthorityPrincipalV1 = _CONSUMER.BootstrapAuthorityPrincipalV1
BootstrapAuthorityTaskRuleV1 = _CONSUMER.BootstrapAuthorityTaskRuleV1
BootstrapAuthorityVerifierV1 = _CONSUMER.BootstrapAuthorityVerifierV1
ApprovalSignatureV1 = _CONSUMER.ApprovalSignatureV1
NormativeDocumentRefV1 = _CONSUMER.NormativeDocumentRefV1
EvidenceRef = _CONSUMER.EvidenceRef
TaskApprovalRefV1 = _CONSUMER.TaskApprovalRefV1
BootstrapTaskVerifierReceiptRefV1 = _CONSUMER.BootstrapTaskVerifierReceiptRefV1
IndependentReviewRefV1 = _CONSUMER.IndependentReviewRefV1
TaskApprovalV1 = _CONSUMER.TaskApprovalV1
GateCatalogRefV1 = _CONSUMER.GateCatalogRefV1
canonical_pf_jcs = _CONSUMER.canonical_pf_jcs
verify_ed25519 = _CONSUMER.verify_ed25519
_scalar_multiply = _CONSUMER._scalar_multiply
_encode_point = _CONSUMER._encode_point
_BASE = _CONSUMER._BASE
_L = _CONSUMER._L


def _reject(detail: str) -> NoReturn:
    raise Rejected(_CONSUMER.BOOTSTRAP_REJECTION, detail)


def _require_seed(seed: object) -> bytes:
    if type(seed) is not bytes or len(seed) != 32:
        _reject("signing seed must be exact 32-byte bytes")
    assert isinstance(seed, bytes)
    return seed


def _expand_seed(seed: bytes) -> Tuple[int, bytes]:
    expanded = hashlib.sha512(seed).digest()
    clamped = bytearray(expanded[:32])
    clamped[0] &= 248
    clamped[31] &= 63
    clamped[31] |= 64
    return int.from_bytes(clamped, "little"), expanded[32:]


def ed25519_public_key_from_seed(seed: bytes) -> bytes:
    """Derive the RFC 8032 public key from an explicit 32-byte seed."""
    secret_scalar, _ = _expand_seed(_require_seed(seed))
    return _encode_point(_scalar_multiply(secret_scalar, _BASE))


def sign_ed25519(seed: bytes, message: bytes) -> bytes:
    """Sign a message with an explicit 32-byte RFC 8032 Ed25519 seed."""
    secret_scalar, nonce_prefix = _expand_seed(_require_seed(seed))
    if type(message) is not bytes:
        _reject("signature message must be bytes")
    public_key = _encode_point(_scalar_multiply(secret_scalar, _BASE))
    nonce = int.from_bytes(
        hashlib.sha512(nonce_prefix + message).digest(), "little"
    ) % _L
    encoded_r = _encode_point(_scalar_multiply(nonce, _BASE))
    challenge = int.from_bytes(
        hashlib.sha512(encoded_r + public_key + message).digest(), "little"
    ) % _L
    scalar_s = (nonce + challenge * secret_scalar) % _L
    signature = encoded_r + scalar_s.to_bytes(32, "little")
    if not verify_ed25519(public_key, message, signature):
        _reject("produced signature failed self-verification")
    return signature


_REQUIRED_TEST_SET_STATEMENT_DOMAIN = b"pf.required-test-set-statement.v1\x00"
_REQUIRED_TEST_SET_SIGNATURE_DOMAIN = b"pf.required-test-set-signature.v1\x00"
_TASK_APPROVAL_STATEMENT_DOMAIN = b"pf.bootstrap-task-approval-statement.v1\x00"
_TASK_APPROVAL_SIGNATURE_DOMAIN = b"pf.bootstrap-task-approval-signature.v1\x00"
_TASK_RECEIPT_STATEMENT_DOMAIN = (
    b"pf.bootstrap-task-verifier-receipt-statement.v1\x00"
)
_TASK_RECEIPT_SIGNATURE_DOMAIN = (
    b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
)
_APPROVAL_SET_STATEMENT_DOMAIN = b"pf.bootstrap-approval-set-statement.v1\x00"
_APPROVAL_SET_SIGNATURE_DOMAIN = b"pf.bootstrap-approval-set-signature.v1\x00"
_VERIFIER_RECEIPT_STATEMENT_DOMAIN = (
    b"pf.bootstrap-approval-verifier-receipt-statement.v1\x00"
)
_VERIFIER_RECEIPT_SIGNATURE_DOMAIN = (
    b"pf.bootstrap-approval-verifier-receipt-signature.v1\x00"
)
_CATALOG_APPROVAL_STATEMENT_DOMAIN = (
    b"pf.formal-gate-catalog-approval-statement.v1\x00"
)
_CATALOG_APPROVAL_SIGNATURE_DOMAIN = (
    b"pf.formal-gate-catalog-approval-signature.v1\x00"
)


def _statement_message(
    statement: dict,
    statement_domain: bytes,
    signature_domain: bytes,
) -> bytes:
    statement_digest = hashlib.sha256(
        statement_domain + canonical_pf_jcs(statement)
    ).digest()
    return signature_domain + statement_digest


def _require_message_match(consumer_message: object, message: bytes) -> None:
    if consumer_message != message:
        _reject("producer and consumer statement derivations diverge")


def _digest_wire(value: object, where: str) -> str:
    if type(value) is not Digest:
        _reject(f"{where} must be a Digest")
    assert isinstance(value, Digest)
    if (value.algorithm != "sha256" or type(value.bytes) is not bytes
            or len(value.bytes) != 32):
        _reject(f"{where} must be a sha256 Digest with exact 32-byte bytes")
    return "sha256:" + value.bytes.hex()


def _content_ref_wire(value: object, where: str) -> dict:
    if type(value) is not ContentRef:
        _reject(f"{where} must be a ContentRef")
    assert isinstance(value, ContentRef)
    return {
        "schema": value.schema,
        "id": value.id,
        "version": value.version,
        "digest": _digest_wire(value.digest, f"{where}.digest"),
    }


def _candidate_wire(value: object, where: str) -> dict:
    if type(value) is not CandidateIdentity:
        _reject(f"{where} must be a CandidateIdentity")
    assert isinstance(value, CandidateIdentity)
    return {
        "commit": value.commit,
        "treeObjectId": value.treeObjectId,
        "archiveDigest": _digest_wire(
            value.archiveDigest, f"{where}.archiveDigest"
        ),
        "digest": _digest_wire(value.digest, f"{where}.digest"),
    }


def _normative_document_ref_wire(value: object, where: str) -> dict:
    if type(value) is not NormativeDocumentRefV1:
        _reject(f"{where} must be a NormativeDocumentRefV1")
    assert isinstance(value, NormativeDocumentRefV1)
    return {
        "id": value.id,
        "contentDigest": _digest_wire(
            value.contentDigest, f"{where}.contentDigest"
        ),
        "status": value.status,
        "reviewCommit": value.reviewCommit,
        "reviewLink": value.reviewLink,
        "approvedAt": value.approvedAt,
        "approvers": _string_list(value.approvers, f"{where}.approvers"),
    }


def _approval_signature_wire(value: object, where: str) -> dict:
    if type(value) is not ApprovalSignatureV1:
        _reject(f"{where} must be an ApprovalSignatureV1")
    assert isinstance(value, ApprovalSignatureV1)
    if type(value.signature) is not bytes or len(value.signature) != 64:
        _reject(f"{where}.signature must be exact 64-byte bytes")
    return {
        "keyId": value.keyId,
        "algorithm": value.algorithm,
        "signature": value.signature.hex(),
    }


def _evidence_ref_wire(value: object, where: str) -> dict:
    if type(value) is not EvidenceRef:
        _reject(f"{where} must be an EvidenceRef")
    assert isinstance(value, EvidenceRef)
    return {
        "id": value.id,
        "digest": _digest_wire(value.digest, f"{where}.digest"),
    }


def _task_approval_ref_wire(value: object, where: str) -> dict:
    if type(value) is not TaskApprovalRefV1:
        _reject(f"{where} must be a TaskApprovalRefV1")
    assert isinstance(value, TaskApprovalRefV1)
    return {
        "taskId": value.taskId,
        "digest": _digest_wire(value.digest, f"{where}.digest"),
    }


def _task_receipt_ref_wire(value: object, where: str) -> dict:
    if type(value) is not BootstrapTaskVerifierReceiptRefV1:
        _reject(f"{where} must be a BootstrapTaskVerifierReceiptRefV1")
    assert isinstance(value, BootstrapTaskVerifierReceiptRefV1)
    return {
        "taskId": value.taskId,
        "id": value.id,
        "digest": _digest_wire(value.digest, f"{where}.digest"),
    }


def _independent_review_wire(value: object, where: str) -> dict:
    if type(value) is not IndependentReviewRefV1:
        _reject(f"{where} must be an IndependentReviewRefV1")
    assert isinstance(value, IndependentReviewRefV1)
    return {
        "keyId": value.keyId,
        "role": value.role,
        "reviewCommit": value.reviewCommit,
        "reviewLink": value.reviewLink,
        "reportDigest": _digest_wire(value.reportDigest, f"{where}.reportDigest"),
        "decision": value.decision,
    }


def _gate_catalog_ref_wire(value: object, where: str) -> dict:
    if type(value) is not GateCatalogRefV1:
        _reject(f"{where} must be a GateCatalogRefV1")
    assert isinstance(value, GateCatalogRefV1)
    return {
        "schema": value.schema,
        "id": value.id,
        "version": value.version,
        "contentSha256": value.contentSha256,
        "catalogDigest": value.catalogDigest,
    }


def _approval_rule_wire(value: object, where: str) -> dict:
    if type(value) is not ApprovalRuleV1:
        _reject(f"{where} must be an ApprovalRuleV1")
    assert isinstance(value, ApprovalRuleV1)
    return {
        "requiredRoles": _string_list(
            value.requiredRoles, f"{where}.requiredRoles"
        ),
        "minimumDistinctSigners": value.minimumDistinctSigners,
    }


def _principal_wire(value: object, where: str) -> dict:
    if type(value) is not BootstrapAuthorityPrincipalV1:
        _reject(f"{where} must be a BootstrapAuthorityPrincipalV1")
    assert isinstance(value, BootstrapAuthorityPrincipalV1)
    if type(value.publicKey) is not bytes or len(value.publicKey) != 32:
        _reject(f"{where}.publicKey must be exact 32-byte bytes")
    return {
        "principalId": value.principalId,
        "keyId": value.keyId,
        "publicKey": value.publicKey.hex(),
        "roles": _string_list(value.roles, f"{where}.roles"),
    }


def _task_rule_wire(value: object, where: str) -> dict:
    if type(value) is not BootstrapAuthorityTaskRuleV1:
        _reject(f"{where} must be a BootstrapAuthorityTaskRuleV1")
    assert isinstance(value, BootstrapAuthorityTaskRuleV1)
    return {
        "taskId": value.taskId,
        "rule": _approval_rule_wire(value.rule, f"{where}.rule"),
    }


def _verifier_wire(value: object, where: str) -> dict:
    if type(value) is not BootstrapAuthorityVerifierV1:
        _reject(f"{where} must be a BootstrapAuthorityVerifierV1")
    assert isinstance(value, BootstrapAuthorityVerifierV1)
    if type(value.receiptPublicKey) is not bytes or len(value.receiptPublicKey) != 32:
        _reject(f"{where}.receiptPublicKey must be exact 32-byte bytes")
    return {
        "id": value.id,
        "executableDigest": _digest_wire(
            value.executableDigest, f"{where}.executableDigest"
        ),
        "receiptKeyId": value.receiptKeyId,
        "receiptPublicKey": value.receiptPublicKey.hex(),
    }


def _task_approval_wire(value: object, where: str) -> dict:
    if type(value) is not TaskApprovalV1:
        _reject(f"{where} must be a TaskApprovalV1")
    assert isinstance(value, TaskApprovalV1)
    return {
        "schema": value.schema,
        "taskId": value.taskId,
        "candidate": _candidate_wire(value.candidate, f"{where}.candidate"),
        "taskBreakdown": _normative_document_ref_wire(
            value.taskBreakdown, f"{where}.taskBreakdown"
        ),
        "requiredTestSet": _content_ref_wire(
            value.requiredTestSet, f"{where}.requiredTestSet"
        ),
        "testIds": _string_list(value.testIds, f"{where}.testIds"),
        "evidence": _ref_tuple(
            value.evidence, _evidence_ref_wire, f"{where}.evidence"
        ),
        "dependencyCompletions": _ref_tuple(
            value.dependencyCompletions,
            _task_receipt_ref_wire,
            f"{where}.dependencyCompletions",
        ),
        "prerequisiteDocuments": _ref_tuple(
            value.prerequisiteDocuments,
            _normative_document_ref_wire,
            f"{where}.prerequisiteDocuments",
        ),
        "authorityPolicy": _content_ref_wire(
            value.authorityPolicy, f"{where}.authorityPolicy"
        ),
        "stage0Handoff": _content_ref_wire(
            value.stage0Handoff, f"{where}.stage0Handoff"
        ),
        "independentReviews": _ref_tuple(
            value.independentReviews,
            _independent_review_wire,
            f"{where}.independentReviews",
        ),
        "signatures": _ref_tuple(
            value.signatures, _approval_signature_wire, f"{where}.signatures"
        ),
    }


def _string_list(value: object, where: str) -> list:
    if type(value) is not tuple or any(type(item) is not str for item in value):
        _reject(f"{where} must be a tuple of strings")
    assert isinstance(value, tuple)
    return list(value)


def _ref_tuple(value: object, encoder, where: str) -> list:
    if type(value) is not tuple:
        _reject(f"{where} must be a tuple")
    assert isinstance(value, tuple)
    return [encoder(item, f"{where}[{index}]") for index, item in enumerate(value)]


def _require_signer_pairs(
    signers: object,
    where: str,
) -> Tuple[Tuple[str, bytes], ...]:
    if type(signers) is not tuple or not signers:
        _reject(f"{where} must be a non-empty (keyId, seed) tuple")
    assert isinstance(signers, tuple)
    pairs = []
    key_ids = set()
    for index, entry in enumerate(signers):
        if (type(entry) is not tuple or len(entry) != 2
                or type(entry[0]) is not str or type(entry[1]) is not bytes):
            _reject(f"{where}[{index}] must be a (keyId, seed) tuple")
        key_id, seed = entry
        assert isinstance(key_id, str) and isinstance(seed, bytes)
        if key_id in key_ids:
            _reject(f"{where} must not repeat a keyId")
        key_ids.add(key_id)
        pairs.append((key_id, seed))
    pairs.sort(key=lambda pair: pair[0])
    return tuple(pairs)


def _sign_with_pairs(
    pairs: Tuple[Tuple[str, bytes], ...],
    message: bytes,
    where: str,
) -> Tuple[ApprovalSignatureV1, ...]:
    return tuple(
        ApprovalSignatureV1(key_id, "ed25519", sign_ed25519(seed, message))
        for key_id, seed in pairs
    )


def _sign_single(
    signer: object,
    message: bytes,
    where: str,
) -> ApprovalSignatureV1:
    pairs = _require_signer_pairs((signer,), where)
    return _sign_with_pairs(pairs, message, where)[0]


def produce_bootstrap_authority_policy(
    id: str,
    version: str,
    principals: Tuple[BootstrapAuthorityPrincipalV1, ...],
    taskRules: Tuple[BootstrapAuthorityTaskRuleV1, ...],
    requiredTestSetRule: ApprovalRuleV1,
    formalCatalogRule: ApprovalRuleV1,
    bootstrapSetRule: ApprovalRuleV1,
    sessionContainmentRule: ApprovalRuleV1,
    freshnessAuthorityRule: ApprovalRuleV1,
    privateScanRule: ApprovalRuleV1,
    privateScanPolicy: ContentRef,
    revocationSnapshotRule: ApprovalRuleV1,
    authorityStoreService: ContentRef,
    verifier: BootstrapAuthorityVerifierV1,
) -> bytes:
    """Construct and fully validate the genesis-root authority policy bytes."""
    wire = {
        "schema": "proof-forge.bootstrap-authority-policy.v1",
        "id": id,
        "version": version,
        "principals": _ref_tuple(principals, _principal_wire, "principals"),
        "taskRules": _ref_tuple(taskRules, _task_rule_wire, "taskRules"),
        "requiredTestSetRule": _approval_rule_wire(
            requiredTestSetRule, "requiredTestSetRule"
        ),
        "formalCatalogRule": _approval_rule_wire(
            formalCatalogRule, "formalCatalogRule"
        ),
        "bootstrapSetRule": _approval_rule_wire(
            bootstrapSetRule, "bootstrapSetRule"
        ),
        "sessionContainmentRule": _approval_rule_wire(
            sessionContainmentRule, "sessionContainmentRule"
        ),
        "freshnessAuthorityRule": _approval_rule_wire(
            freshnessAuthorityRule, "freshnessAuthorityRule"
        ),
        "privateScanRule": _approval_rule_wire(
            privateScanRule, "privateScanRule"
        ),
        "privateScanPolicy": _content_ref_wire(
            privateScanPolicy, "privateScanPolicy"
        ),
        "revocationSnapshotRule": _approval_rule_wire(
            revocationSnapshotRule, "revocationSnapshotRule"
        ),
        "authorityStoreService": _content_ref_wire(
            authorityStoreService, "authorityStoreService"
        ),
        "verifier": _verifier_wire(verifier, "verifier"),
    }
    produced = canonical_pf_jcs(wire)
    _CONSUMER.parse_bootstrap_authority_policy(produced)
    return produced


def produce_required_test_set(
    id: str,
    version: str,
    phase5Document: NormativeDocumentRefV1,
    authorityPolicy: ContentRef,
    requiredTestIds: Tuple[str, ...],
    signers: Tuple[Tuple[str, bytes], ...],
    authority_policy_bytes: bytes,
) -> bytes:
    """Construct, sign, and re-validate a RequiredTestSetV1.

    ``authority_policy_bytes`` is a construction-validation input only: the
    produced wire embeds the caller-supplied ``authorityPolicy`` ContentRef.
    """
    statement = {
        "schema": "proof-forge.required-test-set.v1",
        "id": id,
        "version": version,
        "phase5Document": _normative_document_ref_wire(
            phase5Document, "phase5Document"
        ),
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "requiredTestIds": _string_list(requiredTestIds, "requiredTestIds"),
    }
    message = _statement_message(
        statement,
        _REQUIRED_TEST_SET_STATEMENT_DOMAIN,
        _REQUIRED_TEST_SET_SIGNATURE_DOMAIN,
    )
    signatures = _sign_with_pairs(
        _require_signer_pairs(signers, "signers"), message, "signers"
    )
    wire = dict(statement)
    wire["signatures"] = _ref_tuple(
        signatures, _approval_signature_wire, "signatures"
    )
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_required_test_set(
        produced,
        authority_policy_bytes,
    )
    _require_message_match(preflight.signatureMessage, message)
    _CONSUMER._finalize_required_test_set(preflight)
    return produced


def produce_task_approval(
    taskId: str,
    candidate: CandidateIdentity,
    taskBreakdown: NormativeDocumentRefV1,
    requiredTestSet: ContentRef,
    testIds: Tuple[str, ...],
    evidence: Tuple[EvidenceRef, ...],
    dependencyCompletions: Tuple[BootstrapTaskVerifierReceiptRefV1, ...],
    prerequisiteDocuments: Tuple[NormativeDocumentRefV1, ...],
    authorityPolicy: ContentRef,
    stage0Handoff: ContentRef,
    independentReviews: Tuple[IndependentReviewRefV1, ...],
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-validate a TaskApprovalV1."""
    statement = {
        "schema": "proof-forge.bootstrap-task-approval.v1",
        "taskId": taskId,
        "candidate": _candidate_wire(candidate, "candidate"),
        "taskBreakdown": _normative_document_ref_wire(
            taskBreakdown, "taskBreakdown"
        ),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "testIds": _string_list(testIds, "testIds"),
        "evidence": _ref_tuple(evidence, _evidence_ref_wire, "evidence"),
        "dependencyCompletions": _ref_tuple(
            dependencyCompletions,
            _task_receipt_ref_wire,
            "dependencyCompletions",
        ),
        "prerequisiteDocuments": _ref_tuple(
            prerequisiteDocuments,
            _normative_document_ref_wire,
            "prerequisiteDocuments",
        ),
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "stage0Handoff": _content_ref_wire(stage0Handoff, "stage0Handoff"),
        "independentReviews": _ref_tuple(
            independentReviews, _independent_review_wire, "independentReviews"
        ),
    }
    message = _statement_message(
        statement,
        _TASK_APPROVAL_STATEMENT_DOMAIN,
        _TASK_APPROVAL_SIGNATURE_DOMAIN,
    )
    signatures = _sign_with_pairs(
        _require_signer_pairs(signers, "signers"), message, "signers"
    )
    wire = dict(statement)
    wire["signatures"] = _ref_tuple(
        signatures, _approval_signature_wire, "signatures"
    )
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_task_approval(produced)
    _require_message_match(preflight.signatureMessage, message)
    return produced


def produce_bootstrap_task_verifier_receipt(
    id: str,
    taskId: str,
    candidate: CandidateIdentity,
    authorityPolicy: ContentRef,
    requiredTestSet: ContentRef,
    taskApproval: TaskApprovalRefV1,
    stage0Handoff: ContentRef,
    dependencyCompletions: Tuple[BootstrapTaskVerifierReceiptRefV1, ...],
    verifierDigest: Digest,
    signer: Tuple[str, bytes],
) -> bytes:
    """Construct, sign, and re-validate a per-task verifier receipt.

    ``result`` is fixed to ``task-approved`` by the receipt schema.
    """
    statement = {
        "schema": "proof-forge.bootstrap-task-verifier-receipt.v1",
        "id": id,
        "taskId": taskId,
        "candidate": _candidate_wire(candidate, "candidate"),
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "taskApproval": _task_approval_ref_wire(taskApproval, "taskApproval"),
        "stage0Handoff": _content_ref_wire(stage0Handoff, "stage0Handoff"),
        "dependencyCompletions": _ref_tuple(
            dependencyCompletions,
            _task_receipt_ref_wire,
            "dependencyCompletions",
        ),
        "verifierDigest": _digest_wire(verifierDigest, "verifierDigest"),
        "result": "task-approved",
    }
    message = _statement_message(
        statement,
        _TASK_RECEIPT_STATEMENT_DOMAIN,
        _TASK_RECEIPT_SIGNATURE_DOMAIN,
    )
    signature = _sign_single(signer, message, "signer")
    wire = dict(statement)
    wire["signature"] = _approval_signature_wire(signature, "signature")
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_bootstrap_task_verifier_receipt(produced)
    _require_message_match(preflight.signatureMessage, message)
    return produced


def produce_bootstrap_approval_set(
    id: str,
    version: str,
    candidate: CandidateIdentity,
    authorityPolicy: ContentRef,
    taskBreakdown: NormativeDocumentRefV1,
    requiredTestSet: ContentRef,
    stage0Handoff: ContentRef,
    taskApprovals: Tuple[TaskApprovalV1, ...],
    taskReceipts: Tuple[BootstrapTaskVerifierReceiptRefV1, ...],
    signers: Tuple[Tuple[str, bytes], ...],
) -> bytes:
    """Construct, sign, and re-validate a six-item BootstrapApprovalSetV1."""
    statement = {
        "schema": "proof-forge.bootstrap-approval-set.v1",
        "id": id,
        "version": version,
        "candidate": _candidate_wire(candidate, "candidate"),
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "taskBreakdown": _normative_document_ref_wire(
            taskBreakdown, "taskBreakdown"
        ),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "stage0Handoff": _content_ref_wire(stage0Handoff, "stage0Handoff"),
        "taskApprovals": _ref_tuple(
            taskApprovals, _task_approval_wire, "taskApprovals"
        ),
        "taskReceipts": _ref_tuple(
            taskReceipts, _task_receipt_ref_wire, "taskReceipts"
        ),
    }
    message = _statement_message(
        statement,
        _APPROVAL_SET_STATEMENT_DOMAIN,
        _APPROVAL_SET_SIGNATURE_DOMAIN,
    )
    signatures = _sign_with_pairs(
        _require_signer_pairs(signers, "signers"), message, "signers"
    )
    wire = dict(statement)
    wire["signatures"] = _ref_tuple(
        signatures, _approval_signature_wire, "signatures"
    )
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_bootstrap_approval_set(produced)
    _require_message_match(preflight.signatureMessage, message)
    return produced


def produce_bootstrap_approval_verifier_receipt(
    id: str,
    candidate: CandidateIdentity,
    authorityPolicy: ContentRef,
    requiredTestSet: ContentRef,
    approvalSet: ContentRef,
    stage0Handoff: ContentRef,
    verifierDigest: Digest,
    taskApprovals: Tuple[TaskApprovalRefV1, ...],
    taskReceipts: Tuple[BootstrapTaskVerifierReceiptRefV1, ...],
    signer: Tuple[str, bytes],
) -> bytes:
    """Construct, sign, and re-validate the aggregate activation receipt.

    ``result`` is fixed to ``bootstrap-approved`` by the receipt schema.  This
    producer only constructs and signs the object; it does not simulate the
    protected execution snapshot the real verifier performs.
    """
    statement = {
        "schema": "proof-forge.bootstrap-approval-verifier-receipt.v1",
        "id": id,
        "candidate": _candidate_wire(candidate, "candidate"),
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "approvalSet": _content_ref_wire(approvalSet, "approvalSet"),
        "stage0Handoff": _content_ref_wire(stage0Handoff, "stage0Handoff"),
        "verifierDigest": _digest_wire(verifierDigest, "verifierDigest"),
        "taskApprovals": _ref_tuple(
            taskApprovals, _task_approval_ref_wire, "taskApprovals"
        ),
        "taskReceipts": _ref_tuple(
            taskReceipts, _task_receipt_ref_wire, "taskReceipts"
        ),
        "result": "bootstrap-approved",
    }
    message = _statement_message(
        statement,
        _VERIFIER_RECEIPT_STATEMENT_DOMAIN,
        _VERIFIER_RECEIPT_SIGNATURE_DOMAIN,
    )
    signature = _sign_single(signer, message, "signer")
    wire = dict(statement)
    wire["signature"] = _approval_signature_wire(signature, "signature")
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_bootstrap_approval_verifier_receipt(produced)
    _require_message_match(preflight.signatureMessage, message)
    return produced


def produce_formal_gate_catalog_approval(
    id: str,
    version: str,
    authorityPolicy: ContentRef,
    requiredTestSet: ContentRef,
    catalog: GateCatalogRefV1,
    signers: Tuple[Tuple[str, bytes], ...],
    authority_policy_bytes: bytes,
) -> bytes:
    """Construct, quorum-sign, and re-validate a FormalGateCatalogApprovalV1.

    Signatures are collected from the explicit ``(keyId, seed)`` pairs,
    assembled in ascending keyId order, and checked against the policy
    ``formalCatalogRule`` before return.  ``authority_policy_bytes`` is a
    construction-validation input only.
    """
    statement = {
        "schema": "proof-forge.formal-gate-catalog-approval.v1",
        "id": id,
        "version": version,
        "authorityPolicy": _content_ref_wire(authorityPolicy, "authorityPolicy"),
        "requiredTestSet": _content_ref_wire(requiredTestSet, "requiredTestSet"),
        "catalog": _gate_catalog_ref_wire(catalog, "catalog"),
    }
    message = _statement_message(
        statement,
        _CATALOG_APPROVAL_STATEMENT_DOMAIN,
        _CATALOG_APPROVAL_SIGNATURE_DOMAIN,
    )
    signatures = _sign_with_pairs(
        _require_signer_pairs(signers, "signers"), message, "signers"
    )
    wire = dict(statement)
    wire["signatures"] = _ref_tuple(
        signatures, _approval_signature_wire, "signatures"
    )
    produced = canonical_pf_jcs(wire)
    preflight = _CONSUMER._preflight_formal_gate_catalog_approval(produced)
    _require_message_match(preflight.signatureMessage, message)
    policy, _ = _CONSUMER.parse_bootstrap_authority_policy(authority_policy_bytes)
    approval = preflight.approval
    _CONSUMER._require_signature_policy_membership(
        approval.signatures,
        policy.principals,
        "FormalGateCatalogApprovalV1.signatures",
    )
    _CONSUMER._require_signature_rule(
        approval.signatures,
        policy.principals,
        policy.formalCatalogRule,
        "FormalGateCatalogApprovalV1.signatures",
    )
    _CONSUMER._verify_approval_signatures(
        approval.signatures,
        policy.principals,
        message,
        "FormalGateCatalogApprovalV1.signatures",
    )
    return produced
