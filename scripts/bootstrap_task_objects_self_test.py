#!/usr/bin/env python3
"""Acceptance tests for the dependency-free bootstrap task object consumer.

The production module is intentionally loaded from its exact sibling pathname:
isolated Python does not add the script directory to ``sys.path``, and this test
must not make a repository-relative import path into an authority selector.
"""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import sys
import time
from pathlib import Path
from types import ModuleType
from typing import Callable


MODULE_PATH = Path(__file__).with_name("bootstrap_task_objects.py")
MODULE_NAME = "proof_forge_bootstrap_task_objects"
BOOTSTRAP_REJECTION = "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED"
ROOT_BYTE_FIELDS = (
    "authorityPolicyBytes",
    "stage0HandoffBytes",
    "requiredTestSetBytes",
    "taskApprovalBytes",
    "taskReceiptBytes",
)


def load_consumer() -> ModuleType:
    assert sys.flags.isolated, "consumer self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "consumer self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), (
        "missing scripts/bootstrap_task_objects.py (expected TASK-D0-01 RED)"
    )
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "consumer import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def assert_public_api(module: ModuleType) -> None:
    required_callables = (
        "canonical_pf_jcs",
        "decode_canonical_pf_jcs",
        "parse_digest",
        "parse_content_ref",
        "parse_candidate_identity",
        "verify_ed25519",
        "verifyBootstrapTaskObjects",
    )
    required_types = (
        "Rejected",
        "Digest",
        "ContentRef",
        "CandidateIdentity",
        "BootstrapLedgerSubjectV1",
        "BootstrapDocumentSnapshotV1",
        "BootstrapTaskRowSubjectV1",
        "BootstrapTaskSubjectV1",
        "BootstrapTaskObjectSetV1",
        "ObjectVerifiedV1",
    )
    for name in required_callables:
        assert callable(getattr(module, name, None)), f"missing callable {name}"
    for name in required_types:
        value = getattr(module, name, None)
        assert isinstance(value, type), f"missing type {name}"

    expected_fields = {
        "Digest": ("algorithm", "bytes"),
        "ContentRef": ("schema", "id", "version", "digest"),
        "CandidateIdentity": ("commit", "treeObjectId", "archiveDigest", "digest"),
        "BootstrapLedgerSubjectV1": (
            "id", "taskId", "testIds", "grade", "result",
        ),
        "BootstrapDocumentSnapshotV1": ("id", "path", "bytes"),
        "BootstrapTaskRowSubjectV1": (
            "taskId", "dependencies", "prerequisites", "testIds", "evidenceIds",
        ),
        "BootstrapTaskSubjectV1": (
            "candidate", "rootTaskId", "taskRows", "evidenceRows", "documents",
        ),
        "BootstrapTaskObjectSetV1": (
            "authorityPolicyBytes",
            "stage0HandoffBytes",
            "requiredTestSetBytes",
            "taskApprovalBytes",
            "taskReceiptBytes",
            "dependencyApprovalBytes",
            "dependencyReceiptBytes",
            "evidenceObjectBytes",
            "reviewReports",
        ),
        "ObjectVerifiedV1": (
            "taskId",
            "candidate",
            "authorityPolicy",
            "requiredTestSet",
            "taskApproval",
            "taskReceipt",
            "stage0Handoff",
            "dependencyReceipts",
            "evidence",
        ),
    }
    for name, fields in expected_fields.items():
        record = getattr(module, name)
        assert dataclasses.is_dataclass(record), f"{name} must be a dataclass"
        assert tuple(field.name for field in dataclasses.fields(record)) == fields, (
            f"{name} fields must match the frozen process-local record"
        )
        params = getattr(record, "__dataclass_params__")
        assert params.frozen, f"{name} must be immutable"


def assert_rejected(module: ModuleType, operation: Callable[[], object]) -> object:
    rejected_type = module.Rejected
    try:
        result = operation()
    except rejected_type as rejected:
        result = rejected
    assert isinstance(result, rejected_type), "invalid input must produce Rejected"
    assert getattr(result, "code", None) == BOOTSTRAP_REJECTION
    return result


def test_pf_jcs(module: ModuleType) -> None:
    value = {
        "z": [True, None, "caf\N{LATIN SMALL LETTER E WITH ACUTE}", 0],
        "a": {"b": "quoted\"", "a": 1},
    }
    golden = (
        b'{"a":{"a":1,"b":"quoted\\\""},'
        b'"z":[true,null,"caf\xc3\xa9",0]}'
    )
    assert module.canonical_pf_jcs(value) == golden
    assert module.decode_canonical_pf_jcs(golden) == value

    invalid = (
        b'{"a":1,"a":2}',
        b'{"a": 1}',
        b'{"z":0,"a":1}',
        b'{"a":"caf\\u00e9"}',
        b'{"a":1.0}',
    )
    for encoded in invalid:
        assert_rejected(module, lambda encoded=encoded: module.decode_canonical_pf_jcs(encoded))

    oversized_integer = b'{"a":' + (b"9" * 1_000_000) + b"}"
    started = time.monotonic()
    assert_rejected(
        module,
        lambda: module.decode_canonical_pf_jcs(oversized_integer),
    )
    assert time.monotonic() - started < 0.5, (
        "unsafe integer must be rejected lexically before big-int conversion"
    )


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def test_common_identities(module: ModuleType) -> object:
    zero_digest = digest_text(bytes(32))
    digest = module.parse_digest(zero_digest)
    assert isinstance(digest, module.Digest)
    assert digest.algorithm == "sha256"
    assert digest.bytes == bytes(32)

    content_ref = module.parse_content_ref({
        "schema": "proof-forge.required-test-set.v1",
        "id": "phase-5-required-tests",
        "version": "1.0.0",
        "digest": zero_digest,
    })
    assert isinstance(content_ref, module.ContentRef)
    assert content_ref.schema == "proof-forge.required-test-set.v1"
    assert content_ref.id == "phase-5-required-tests"
    assert content_ref.version == "1.0.0"
    assert content_ref.digest == digest

    candidate_payload = {
        "commit": "a" * 40,
        "treeObjectId": "b" * 40,
        "archiveDigest": digest_text(bytes.fromhex("11" * 32)),
    }
    candidate_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + module.canonical_pf_jcs(candidate_payload)
    ).digest()
    candidate_wire = dict(candidate_payload)
    candidate_wire["digest"] = digest_text(candidate_digest)
    candidate = module.parse_candidate_identity(candidate_wire)
    assert isinstance(candidate, module.CandidateIdentity)
    assert candidate.commit == candidate_payload["commit"]
    assert candidate.treeObjectId == candidate_payload["treeObjectId"]
    assert candidate.archiveDigest.bytes == bytes.fromhex("11" * 32)
    assert candidate.digest.bytes == candidate_digest

    malformed_digests = (
        "sha256:" + "A" * 64,
        "sha256:" + "00" * 31,
        "sha512:" + "00" * 32,
        "00" * 32,
    )
    for malformed in malformed_digests:
        assert_rejected(module, lambda malformed=malformed: module.parse_digest(malformed))

    wrong_candidate = dict(candidate_wire)
    wrong_candidate["digest"] = zero_digest
    assert_rejected(module, lambda: module.parse_candidate_identity(wrong_candidate))
    return candidate


def test_ed25519(module: ModuleType) -> None:
    # RFC 8032 section 7.1, test vector 1 (pure Ed25519, empty message).
    public_key = bytes.fromhex(
        "d75a980182b10ab7d54bfed3c964073a"
        "0ee172f3daa62325af021a68f707511a"
    )
    signature = bytes.fromhex(
        "e5564300c360ac729086e2cc806e828a"
        "84877f1eb8e5d974d873e06522490155"
        "5fb8821590a33bacc61e39701cf9b46b"
        "d25bf5f0595bbe24655141438e7a100b"
    )
    assert module.verify_ed25519(public_key, b"", signature) is True
    assert module.verify_ed25519(public_key, b"tampered", signature) is False

    # S must be strictly less than the prime subgroup order L.
    subgroup_order = 2**252 + 27742317777372353535851937790883648493
    noncanonical_s = signature[:32] + subgroup_order.to_bytes(32, "little")
    assert module.verify_ed25519(public_key, b"", noncanonical_s) is False

    # A permissive equation-only verifier accepts this identity-key forgery.
    identity = b"\x01" + bytes(31)
    identity_forgery = identity + bytes(32)
    assert module.verify_ed25519(identity, b"forgery", identity_forgery) is False


def test_subject_and_missing_root_bytes(module: ModuleType, candidate: object) -> None:
    evidence_id = "EV-20260716-9999"
    row = module.BootstrapTaskRowSubjectV1(
        taskId="TASK-D0-01",
        dependencies=(),
        prerequisites=(
            {"documentId": "PHASE-1", "requiredStatus": "accepted"},
            {"documentId": "PHASE-2", "requiredStatus": "accepted"},
            {"documentId": "PHASE-3", "requiredStatus": "accepted"},
        ),
        testIds=("TST-DOC-001",),
        evidenceIds=(evidence_id,),
    )
    ledger = module.BootstrapLedgerSubjectV1(
        id=evidence_id,
        taskId="TASK-D0-01",
        testIds=("TST-DOC-001",),
        grade="bootstrap",
        result="passed",
    )
    documents = tuple(
        module.BootstrapDocumentSnapshotV1(
            id=document_id,
            path=path,
            bytes=(
                "---\n"
                f"id: {document_id}\n"
                "status: accepted\n"
                "---\n"
            ).encode("utf-8"),
        )
        for document_id, path in (
            ("PHASE-1", "docs/01-prd.md"),
            ("PHASE-2", "docs/02-architecture.md"),
            ("PHASE-3", "docs/03-technical-spec.md"),
            ("PHASE-4", "docs/04-task-breakdown.md"),
            ("PHASE-5", "docs/05-test-spec.md"),
        )
    )
    subject = module.BootstrapTaskSubjectV1(
        candidate=candidate,
        rootTaskId="TASK-D0-01",
        taskRows=(row,),
        evidenceRows=(ledger,),
        documents=documents,
    )

    base = {
        "authorityPolicyBytes": b"{}",
        "stage0HandoffBytes": b"{}",
        "requiredTestSetBytes": b"{}",
        "taskApprovalBytes": b"{}",
        "taskReceiptBytes": b"{}",
        "dependencyApprovalBytes": (),
        "dependencyReceiptBytes": (),
        "evidenceObjectBytes": (b"{}",),
        "reviewReports": ({"digest": digest_text(bytes(32)), "bytes": b"review"},),
    }
    for missing in ROOT_BYTE_FIELDS:
        fields = dict(base)
        fields[missing] = b""
        objects = module.BootstrapTaskObjectSetV1(**fields)
        rejected = module.verifyBootstrapTaskObjects(subject, objects)
        assert isinstance(rejected, module.Rejected), (
            f"missing {missing} must return Rejected"
        )
        assert rejected.code == BOOTSTRAP_REJECTION

    complete_objects = module.BootstrapTaskObjectSetV1(**base)
    mixed_task_ids = dataclasses.replace(
        subject,
        taskRows=(row, dataclasses.replace(row, taskId=1)),
    )
    assert_rejected(
        module,
        lambda: module.verifyBootstrapTaskObjects(mixed_task_ids, complete_objects),
    )

    surrogate_document = dataclasses.replace(
        documents[0],
        path="docs/\ud800.md",
    )
    surrogate_subject = dataclasses.replace(
        subject,
        documents=(surrogate_document,) + documents[1:],
    )
    assert_rejected(
        module,
        lambda: module.verifyBootstrapTaskObjects(surrogate_subject, complete_objects),
    )


def main() -> int:
    try:
        module = load_consumer()
        assert_public_api(module)
        test_pf_jcs(module)
        candidate = test_common_identities(module)
        test_ed25519(module)
        test_subject_and_missing_root_bytes(module, candidate)
    except (AssertionError, OSError, ImportError, SyntaxError) as error:
        print(f"bootstrap-task-objects-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    print("bootstrap-task-objects-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
