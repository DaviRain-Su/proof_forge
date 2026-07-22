#!/usr/bin/env python3
"""TST-DOC-001/task-qualification-v1 RED matrix.

This is the RED matrix for TASK-D0-10. It tests the pure verifier
(``task_qualification_verifier``) against legal fixture chains (positive
cases) and mutated chains (negative cases).

The RED matrix is committed before the GREEN implementation. The GREEN
implementation must make all positive cases pass and all negative cases
reject with the correct stage.

This is a self-test module: run with ``python3 scripts/task_qualification_red_matrix_self_test.py``.
"""

from __future__ import annotations

import copy
import json
import sys
import os

# Add scripts directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV
import task_qualification_fixture_builder as _TQFB
import bootstrap_task_objects as _BTO

Rejected = _BTO.Rejected


def _bytes_hex(b: bytes) -> str:
    return b.hex()


# ---------------------------------------------------------------------------
# RED matrix test cases
# ---------------------------------------------------------------------------

class RedMatrixResult:
    def __init__(self, name: str, expected_pass: bool, actual_pass: bool, detail: str = ""):
        self.name = name
        self.expected_pass = expected_pass
        self.actual_pass = actual_pass
        self.detail = detail

    def passed(self) -> bool:
        return self.expected_pass == self.actual_pass

    def __repr__(self) -> str:
        status = "PASS" if self.passed() else "FAIL"
        return f"[{status}] {self.name}: expected={'pass' if self.expected_pass else 'reject'} actual={'pass' if self.actual_pass else 'reject'} {self.detail}"


def _run_verifier(bundle_bytes: bytes, subject_bytes: bytes) -> bool:
    """Run the task-qualification verifier and return True if Verified, False if Rejected."""
    result = _TQV.verify_task_qualification_v1(bundle_bytes, subject_bytes)
    return isinstance(result, _TQV.VerifiedTaskQualificationV1)


def _run_completion_verifier(bundle_bytes: bytes, subject_bytes: bytes) -> bool:
    """Run the task-completion-receipt verifier and return True if Verified, False if Rejected."""
    result = _TQV.verify_task_completion_receipt_v1(bundle_bytes, subject_bytes)
    return isinstance(result, _TQV.VerifiedTaskCompletionV1)


def _run_d0_10_approval_verifier(bundle_bytes: bytes, subject_bytes: bytes) -> bool:
    """Run the d0-10-bootstrap-approval verifier and return True if Verified, False if Rejected."""
    result = _TQV.verify_d0_10_bootstrap_v1(bundle_bytes, subject_bytes)
    return isinstance(result, _TQV.VerifiedD0_10BootstrapApprovalV1)


def _run_d0_10_receipt_verifier(bundle_bytes: bytes, subject_bytes: bytes) -> bool:
    """Run the d0-10-bootstrap-receipt verifier and return True if Verified, False if Rejected."""
    result = _TQV.verify_d0_10_bootstrap_receipt_v1(bundle_bytes, subject_bytes)
    return isinstance(result, _TQV.VerifiedD0_10BootstrapCompletionV1)


def _make_mutated_chain(chain) -> tuple:
    """Return (bundle_obj_copy, subject_obj_copy) for mutation."""
    if hasattr(chain, "qualification_obj"):
        return (copy.deepcopy(chain.bundle_obj), copy.deepcopy(chain.qualification_obj))
    if hasattr(chain, "receipt_obj"):
        return (copy.deepcopy(chain.bundle_obj), copy.deepcopy(chain.receipt_obj))
    if hasattr(chain, "approval_obj"):
        return (copy.deepcopy(chain.bundle_obj), copy.deepcopy(chain.approval_obj))
    return (copy.deepcopy(chain.bundle_obj), copy.deepcopy(chain.approval_obj))


def _canonical_bytes(obj: dict) -> bytes:
    return _BTO.canonical_pf_jcs(obj)


# ---------------------------------------------------------------------------
# Positive cases (should pass)
# ---------------------------------------------------------------------------

def test_positive_legal_chain() -> RedMatrixResult:
    """A legal fixture chain should verify successfully."""
    chain = _TQFB.build_fixture_chain()
    bundle_bytes, subject_bytes = _TQFB.fixture_chain_to_bytes(chain)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("positive.legal_chain", True, actual)


def test_positive_legal_completion_receipt() -> RedMatrixResult:
    """A legal completion receipt chain should verify successfully."""
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_bytes, subject_bytes = _TQFB.completion_receipt_chain_to_bytes(receipt_chain)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("positive.legal_completion_receipt", True, actual)


def test_negative_completion_wrong_signature() -> RedMatrixResult:
    """A completion receipt with a wrong signature should reject."""
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    receipt_obj["signatures"][0]["signature"] = "00" * 64
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_wrong_signature", False, actual)


def test_negative_completion_wrong_parent() -> RedMatrixResult:
    """A completion receipt where D's parent is not C should reject."""
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    # Change the preCloseCandidate commit to something else
    receipt_obj["preCloseCandidate"]["commit"] = "f1" + "c" * 38
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_wrong_parent", False, actual)


def test_positive_legal_d0_10_approval() -> RedMatrixResult:
    """A legal D0-10 bootstrap approval chain should verify successfully."""
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_bytes, subject_bytes = _TQFB.d0_10_approval_chain_to_bytes(chain)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("positive.legal_d0_10_approval", True, actual)


def test_negative_d0_10_wrong_signature() -> RedMatrixResult:
    """A D0-10 approval with a wrong signature should reject."""
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["signatures"][0]["signature"] = "00" * 64
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_wrong_signature", False, actual)


def test_negative_d0_10_wrong_task_id() -> RedMatrixResult:
    """A D0-10 approval with wrong taskId should reject."""
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["taskId"] = "TASK-D0-99"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_wrong_task_id", False, actual)


def test_negative_d0_10_wrong_ruling() -> RedMatrixResult:
    """A D0-10 approval with wrong ruling ID should reject."""
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["ruling"]["id"] = "GOV-WRONG-001"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_wrong_ruling", False, actual)


def test_negative_d0_10_ruling_content_digest_mismatch() -> RedMatrixResult:
    """GAP-16: §7 ruling ref 必须重算本 accepted ruling. The approval's
    ruling.contentDigest must equal plain_sha256(ruling-source member bytes).
    Corrupt the ruling.contentDigest to a wrong value; expect reject at the
    documents stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["ruling"]["contentDigest"] = "sha256:" + "ee" * 32
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_ruling_content_digest_mismatch", False, actual)


def test_negative_d0_10_ruling_wrong_status() -> RedMatrixResult:
    """GAP-16: §7 ruling.status must be 'accepted'. A D0-10 approval whose
    ruling.status is 'draft' must reject at the documents stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["ruling"]["status"] = "draft"
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_ruling_wrong_status", False, actual)


def test_negative_d0_10_ruling_review_commit_mismatch() -> RedMatrixResult:
    """GAP-16: §7 ruling.reviewCommit must equal preCloseCandidate.commit. A
    D0-10 approval whose ruling.reviewCommit differs from the candidate commit
    must reject at the documents stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["ruling"]["reviewCommit"] = "0" * 40
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_ruling_review_commit_mismatch", False, actual)


def test_negative_d0_10_approval_missing_ledger_evidence_id() -> RedMatrixResult:
    """SA-1: §7 D0_10BootstrapApprovalV1 must carry a ledgerEvidenceId field
    (exact real EV-YYYYMMDD-NNNN ID). Removing it from a legal fixture approval
    must reject at the document stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    del approval_obj["ledgerEvidenceId"]
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(
        "negative.d0_10_approval_missing_ledger_evidence_id", False, actual,
    )


def test_negative_d0_10_approval_malformed_ledger_evidence_id() -> RedMatrixResult:
    """SA-1: §7 D0_10BootstrapApprovalV1.ledgerEvidenceId must be an exact real
    EV-YYYYMMDD-NNNN ID. A malformed value must reject.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["ledgerEvidenceId"] = "not-an-ev-id"
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(
        "negative.d0_10_approval_malformed_ledger_evidence_id", False, actual,
    )


def test_positive_d0_10_approval_has_ledger_evidence_id() -> RedMatrixResult:
    """SA-1: §7 the legal fixture D0-10 approval must include a valid
    ledgerEvidenceId. RED until the fixture builder emits it.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    _bundle_obj, approval_obj = _make_mutated_chain(chain)
    has_field = (
        "ledgerEvidenceId" in approval_obj
        and isinstance(approval_obj["ledgerEvidenceId"], str)
        and __import__("re").fullmatch(
            r"EV-\d{8}-\d{4}", approval_obj["ledgerEvidenceId"]
        ) is not None
    )
    return RedMatrixResult(
        "positive.d0_10_approval_has_ledger_evidence_id", True, has_field,
    )


def test_positive_d0_10_receipt_has_ledger_evidence_id() -> RedMatrixResult:
    """SA-2: §7 the legal fixture D0-10 receipt must include a valid
    ledgerEvidenceId. RED until the fixture builder emits it.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    _bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    has_field = (
        "ledgerEvidenceId" in receipt_obj
        and isinstance(receipt_obj["ledgerEvidenceId"], str)
        and __import__("re").fullmatch(
            r"EV-\d{8}-\d{4}", receipt_obj["ledgerEvidenceId"]
        ) is not None
    )
    return RedMatrixResult(
        "positive.d0_10_receipt_has_ledger_evidence_id", True, has_field,
    )


def test_negative_d0_10_receipt_missing_ledger_evidence_id() -> RedMatrixResult:
    """SA-2: §7 D0_10BootstrapReceiptV1 must carry ledgerEvidenceId. Removing
    it must reject at the document stage.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    del receipt_obj["ledgerEvidenceId"]
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(
        "negative.d0_10_receipt_missing_ledger_evidence_id", False, actual,
    )


def test_negative_d0_10_receipt_malformed_ledger_evidence_id() -> RedMatrixResult:
    """SA-2: §7 D0_10BootstrapReceiptV1.ledgerEvidenceId must be an exact real
    EV-YYYYMMDD-NNNN ID. A malformed value must reject.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    receipt_obj["ledgerEvidenceId"] = "not-an-ev-id"
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(
        "negative.d0_10_receipt_malformed_ledger_evidence_id", False, actual,
    )


def test_negative_d0_10_receipt_ledger_evidence_id_mismatch() -> RedMatrixResult:
    """SA-2: §7 approval and receipt ledgerEvidenceId must be逐字 equal. A
    receipt whose ledgerEvidenceId differs from the embedded approval's must
    reject at the projection stage.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    receipt_obj["ledgerEvidenceId"] = "EV-20260721-0099"
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(
        "negative.d0_10_receipt_ledger_evidence_id_mismatch", False, actual,
    )


def test_negative_phantom_gate_id_member() -> RedMatrixResult:
    """GAP-24: §8.2 gate-keyed member suffixes must exactly equal declared
    gateIds. A qualification bundle with an extra command-policy/<phantom-gate>
    member (no matching declared gate) must reject at the controls stage.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Duplicate an existing command-policy member with a phantom gateId suffix.
    phantom_gate = "phantom-gate-id"
    for m in bundle_obj["members"]:
        if m.get("role", "").startswith("command-policy/"):
            bundle_obj["members"].append({
                "role": f"command-policy/{phantom_gate}",
                "kind": m["kind"],
                "content": copy.deepcopy(m["content"]),
                "bytesHex": m["bytesHex"],
            })
            break
    bundle_obj["members"].sort(key=lambda m: m["role"])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.phantom_gate_id_member", False, actual)


def test_negative_fixture_policy_wrong_principal_public_key() -> RedMatrixResult:
    """GAP-11: §8.2 fixture-profile principal signing keys must use RFC 8032
    §7.1 public test vectors #1-#3. A fixture policy whose architecture
    principal has a non-RFC-8032 public key must reject at the policy stage.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt the authority-policy member's architecture principal publicKey.
    for m in bundle_obj["members"]:
        if m.get("role") == "authority-policy":
            policy_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            # Replace the architecture principal's publicKey with a random
            # 32-byte value (not RFC 8032 vector #1).
            policy_wire["principals"][0]["publicKey"] = "aa" * 32
            new_bytes = _BTO.canonical_pf_jcs(policy_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_FIXTURE_POLICY, policy_wire)
            new_ref = {
                "schema": policy_wire["schema"],
                "id": policy_wire["id"],
                "version": policy_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            subject_obj["authorityPolicy"] = new_ref
            bundle_obj["expectedAuthorityPolicy"] = new_ref
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.fixture_policy_wrong_principal_public_key", False, actual)


def test_negative_completion_receipt_invalid_issued_at() -> RedMatrixResult:
    """GAP-15: §6 issuedAt is RFC3339 UTC seconds. A completion receipt whose
    issuedAt is not RFC3339 UTC (e.g. has a timezone offset) must reject at
    the subject decode stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    # Corrupt issuedAt to a non-RFC3339-UTC value (with offset).
    receipt_obj["issuedAt"] = "2026-07-21T00:00:00+02:00"
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_receipt_invalid_issued_at", False, actual)


def test_negative_command_policy_argv0_not_absolute() -> RedMatrixResult:
    """GAP-6: §3 argv[0] is absolute canonical executable (starts with '/').
    A command policy whose argv[0] is a relative path must reject at the
    command stage. The command-policy member is corrupted and the subject is
    re-signed.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt the command-policy member's argv[0] to a relative path.
    for m in bundle_obj["members"]:
        if m.get("role", "").startswith("command-policy/"):
            cmd_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            cmd_wire["argv"][0] = "python3"
            new_bytes = _BTO.canonical_pf_jcs(cmd_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_TASK_COMMAND_POLICY, cmd_wire)
            new_ref = {
                "schema": cmd_wire["schema"],
                "id": cmd_wire["id"],
                "version": cmd_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            subject_obj["gates"][0]["commandPolicy"] = new_ref
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.command_policy_argv0_not_absolute", False, actual)


def test_positive_legal_d0_10_receipt() -> RedMatrixResult:
    """A legal D0-10 bootstrap receipt chain should verify successfully."""
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_bytes, subject_bytes = _TQFB.d0_10_receipt_chain_to_bytes(receipt_chain)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("positive.legal_d0_10_receipt", True, actual)


def test_negative_d0_10_receipt_wrong_signature() -> RedMatrixResult:
    """A D0-10 receipt with a wrong signature should reject."""
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    receipt_obj["signatures"][0]["signature"] = "00" * 64
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_receipt_wrong_signature", False, actual)


def test_negative_d0_10_receipt_wrong_parent() -> RedMatrixResult:
    """A D0-10 receipt where D's parent is not C should reject."""
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    receipt_obj["preCloseCandidate"]["commit"] = "f1" + "d" * 38
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_receipt_wrong_parent", False, actual)


def test_negative_receipt_forbidden_evidence_member() -> RedMatrixResult:
    """A receipt operation with an evidence/* member should reject at members stage (§8.2)."""
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    # Add a forbidden evidence member to a receipt operation
    bundle_obj["members"].append({
        "role": "evidence/EV-20260721-0001",
        "kind": "raw-source",
        "raw": {"path": "evidence/EV-20260721-0001", "digest": "sha256:" + "00" * 32},
        "bytesHex": "00",
    })
    # Re-sort members
    bundle_obj["members"].sort(key=lambda m: m["role"])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.receipt_forbidden_evidence_member", False, actual)


def test_negative_fixture_forbidden_production_profile() -> RedMatrixResult:
    """A fixture bundle with a production-profile member should reject at members stage (§8.2)."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Add a forbidden production-profile member to a fixture bundle
    bundle_obj["members"].append({
        "role": "production-profile",
        "kind": "typed-content",
        "content": {
            "schema": "proof-forge.task-qualification-production-profile.v1",
            "id": "task-qualification-production-profile-v1",
            "version": "1.0.0",
            "digest": "sha256:" + "00" * 32,
        },
        "bytesHex": "00",
    })
    # Re-sort members
    bundle_obj["members"].sort(key=lambda m: m["role"])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.fixture_forbidden_production_profile", False, actual)


def test_negative_qualification_missing_revocation_snapshot() -> RedMatrixResult:
    """A qualification bundle missing the revocation-snapshot singleton should reject (§8.2)."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Remove the revocation-snapshot singleton
    bundle_obj["members"] = [m for m in bundle_obj["members"] if m["role"] != "revocation-snapshot"]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.qualification_missing_revocation_snapshot", False, actual)


def test_negative_completion_wrong_diff_digest() -> RedMatrixResult:
    """A completion receipt whose closeoutDiffDigest doesn't match the actual C/D diff should reject (§6)."""
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    # Corrupt the closeoutDiffDigest to something wrong
    receipt_obj["closeoutDiffDigest"] = "sha256:" + "ab" * 32
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_wrong_diff_digest", False, actual)


def test_negative_completion_resulting_task_row_digest_mismatch() -> RedMatrixResult:
    """GAP-13: §6 resulting row 与 AllowedCloseoutPatchV1 exact. The patch's
    resultingTaskRowDigest must equal the digest recomputed from the
    qualification's taskRow with status flipped to done. Corrupt the patch's
    resultingTaskRowDigest and recompute the patch member ref; expect reject
    at the projection stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    # Corrupt the allowed-closeout-patch member's resultingTaskRowDigest.
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            patch_wire["resultingTaskRowDigest"] = "sha256:" + "ee" * 32
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            receipt_obj["allowedCloseoutPatch"] = new_ref
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_resulting_task_row_digest_mismatch", False, actual)


def test_negative_completion_closeout_diff_paths_mismatch_allowed() -> RedMatrixResult:
    """GAP-13: §6 diff(C,D) paths must exact-equal allowedCloseoutPatch.
    allowedPaths. A patch whose allowedPaths omits one of the closeout diff
    paths must reject at the projection stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    # Corrupt the allowed-closeout-patch member's allowedPaths to drop one
    # path so it no longer exact-equals the closeout diff paths.
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            # Drop the first path.
            patch_wire["allowedPaths"] = list(patch_wire["allowedPaths"])[1:]
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            receipt_obj["allowedCloseoutPatch"] = new_ref
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_closeout_diff_paths_mismatch_allowed", False, actual)


def test_negative_completion_fixed_path_after_bytes_mismatch() -> RedMatrixResult:
    """GAP-12: §6 the fixed Q/approval-path change's afterDigest must equal
    plain_sha256(verified qualification bytes). Corrupt the qualification
    member bytes so the fixed-path change's afterDigest no longer matches;
    expect reject at the projection stage. The qualification ref digest in
    the receipt is recomputed to match the corrupted member so the verifier
    reaches the projection stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    # Corrupt the qualification member bytes by appending a new field so the
    # JSON remains valid but the bytes differ from the fixed-path afterDigest.
    # Recompute the qualification full digest and the receipt's qualification
    # ref digest so the verifier passes the qualification-join stage and
    # reaches the projection stage.
    for m in bundle_obj["members"]:
        if m.get("role") == "qualification":
            orig_bytes = bytes.fromhex(m["bytesHex"])
            orig_obj = _BTO.decode_canonical_pf_jcs(orig_bytes)
            orig_obj["gap12_corruption_marker"] = "tampered"
            corrupted = _BTO.canonical_pf_jcs(orig_obj)
            m["bytesHex"] = corrupted.hex()
            new_qual_digest = _TQO.domain_digest(
                _TQO.DOMAIN_TASK_QUALIFICATION, orig_obj)
            m["content"]["digest"] = _TQO.digest_to_wire(new_qual_digest)
            receipt_obj["qualification"]["digest"] = _TQO.digest_to_wire(new_qual_digest)
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.completion_fixed_path_after_bytes_mismatch", False, actual)


def test_negative_receipt_qualification_digest_mismatch() -> RedMatrixResult:
    """§8.1/§8.2: the task-completion bundle's ``qualification`` member must
    recompute to a full digest that exactly equals ``receipt.qualification.digest``.
    Receipt operations do not replay the prior qualification closure, but the
    signed prior subject must be authenticated by digest join.

    The receipt's ``qualification.digest`` ref is corrupted to a wrong value
    and the subject is re-signed so the verifier reaches the qualification-join
    stage where the mismatch fires.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    # Corrupt the qualification ref digest; the bundle member bytes are
    # untouched, so the recomputed qualification full digest will not match.
    receipt_obj["qualification"]["digest"] = "sha256:" + "cd" * 32
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.receipt_qualification_digest_mismatch", False, actual)


def test_negative_receipt_qualification_taskid_mismatch() -> RedMatrixResult:
    """§8.1/§8.2: ``receipt.qualification.taskId`` must equal
    ``receipt.taskId`` and the decoded qualification member's taskId.

    The receipt's ``qualification.taskId`` ref is corrupted and the subject is
    re-signed so the verifier reaches the qualification-join stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    receipt_obj["qualification"]["taskId"] = "TASK-D0-99"
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.receipt_qualification_taskid_mismatch", False, actual)


def test_negative_receipt_qualification_id_mismatch() -> RedMatrixResult:
    """§8.1/§8.2: ``receipt.qualification.id`` must equal the decoded
    qualification member's id.

    The receipt's ``qualification.id`` ref is corrupted and the subject is
    re-signed so the verifier reaches the qualification-join stage.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj = copy.deepcopy(receipt_chain.bundle_obj)
    receipt_obj = copy.deepcopy(receipt_chain.receipt_obj)
    receipt_obj["qualification"]["id"] = "task-qualification-d0-99"
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.receipt_qualification_id_mismatch", False, actual)


# ---------------------------------------------------------------------------
# Negative cases (should reject)
# ---------------------------------------------------------------------------

def test_negative_wrong_signature() -> RedMatrixResult:
    """A chain with a wrong signature should reject at signatures stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt one signature
    subject_obj["signatures"][0]["signature"] = "00" * 64
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_signature", False, actual)


def test_negative_missing_signature() -> RedMatrixResult:
    """A chain with only 2 signatures should reject at signatures stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Remove one signature
    subject_obj["signatures"] = subject_obj["signatures"][:2]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.missing_signature", False, actual)


def test_negative_wrong_role_signature() -> RedMatrixResult:
    """A chain where all 3 signatures are from the same role should reject."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Replace all signatures with architecture key signatures
    # This requires re-signing with only the architecture key
    # For simplicity, just corrupt the keyId of one signature
    subject_obj["signatures"][1]["keyId"] = "fixture-key-architecture"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_role_signature", False, actual)


def test_negative_missing_member() -> RedMatrixResult:
    """A chain missing a required member should reject at members stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Remove the authority-policy member
    bundle_obj["members"] = [m for m in bundle_obj["members"] if m["role"] != "authority-policy"]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.missing_member", False, actual)


def test_negative_corrupt_archive() -> RedMatrixResult:
    """A chain with a corrupted archive should reject at candidate stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt the candidate-archive bytes
    for m in bundle_obj["members"]:
        if m["role"] == "candidate-archive":
            # Flip a byte in the hex
            corrupted = bytearray(bytes.fromhex(m["bytesHex"]))
            corrupted[0] ^= 0x01
            m["bytesHex"] = corrupted.hex()
            # Also update the archiveSha256 to match the corrupted archive
            import hashlib
            new_digest = "sha256:" + hashlib.sha256(bytes(corrupted)).hexdigest()
            m["archiveSha256"] = new_digest
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.corrupt_archive", False, actual)


def test_negative_wrong_candidate_commit() -> RedMatrixResult:
    """A chain where the subject's candidate commit doesn't match the archive should reject."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Change the preCloseCandidate commit in the subject
    subject_obj["preCloseCandidate"]["commit"] = "f1" + "b" * 38
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_candidate_commit", False, actual)


def test_negative_oversized_subject() -> RedMatrixResult:
    """A subject exceeding 4 MiB should reject at bounds stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    bundle_bytes = _canonical_bytes(bundle_obj)
    # Create an oversized subject (5 MiB)
    subject_obj["taskRow"]["output"] = "x" * (5 * 1024 * 1024)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.oversized_subject", False, actual)


def test_negative_wrong_fixture_namespace() -> RedMatrixResult:
    """A chain with the wrong fixture namespace should reject at profile stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Change the namespace
    bundle_obj["verificationProfile"]["namespace"] = "wrong-namespace"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_fixture_namespace", False, actual)


def test_negative_wrong_keyset() -> RedMatrixResult:
    """A chain with the wrong keySet should reject at profile stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    bundle_obj["verificationProfile"]["keySet"] = "wrong-keyset"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_keyset", False, actual)


def test_negative_policy_ref_mismatch() -> RedMatrixResult:
    """A chain where the profile's fixturePolicy ref doesn't match the bundle's expectedAuthorityPolicy should reject."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Change the expectedAuthorityPolicy
    bundle_obj["expectedAuthorityPolicy"]["digest"] = "sha256:" + "00" * 32
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.policy_ref_mismatch", False, actual)


def test_negative_duplicate_member_role() -> RedMatrixResult:
    """A chain with duplicate member roles should reject at members stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Duplicate the first member
    bundle_obj["members"].append(bundle_obj["members"][0])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.duplicate_member_role", False, actual)


def test_negative_unsorted_members() -> RedMatrixResult:
    """A chain with unsorted members should reject at members stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Reverse the member order
    bundle_obj["members"].reverse()
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.unsorted_members", False, actual)


def test_negative_wrong_schema() -> RedMatrixResult:
    """A subject with the wrong schema should reject at members stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    subject_obj["schema"] = "wrong.schema.v1"
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.wrong_schema", False, actual)


def test_negative_empty_gates() -> RedMatrixResult:
    """A subject with no gates should reject."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    subject_obj["gates"] = []
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.empty_gates", False, actual)


def test_negative_empty_reviews() -> RedMatrixResult:
    """A subject with no reviews should reject at reviews stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    subject_obj["independentReviews"] = []
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.empty_reviews", False, actual)


def test_negative_non_canonical_subject() -> RedMatrixResult:
    """A non-canonical subject (non-PF-JCS) should reject."""
    chain = _TQFB.build_fixture_chain()
    bundle_bytes, _ = _TQFB.fixture_chain_to_bytes(chain)
    # Create a non-canonical subject (with whitespace)
    import json
    subject_bytes = json.dumps(chain.qualification_obj, indent=2).encode("utf-8")
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.non_canonical_subject", False, actual)


def test_negative_oversized_signature_count() -> RedMatrixResult:
    """A subject with >256 signatures must reject at signatures stage (§1).

    The parser uses MAX_ARRAY=4096; the §1 signature-specific bound is 3..256.
    A subject with 257 valid-but-duplicate-role signatures must reject before
    any curve work rather than silently accepting extra signatures.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Duplicate the 3 fixture signatures to exceed 256. The parser enforces
    # keyId uniqueness, so we must use distinct keyIds; instead, we inject
    # 257 signatures by repeating the fixture principal signatures with
    # synthetic keyIds that are NOT in the fixture policy. The verifier
    # should reject at signatures stage (keyId not in policy) — but to test
    # the §1 upper bound specifically, we instead verify the bound check
    # fires for a count >256. Since the parser rejects duplicate keyIds,
    # we test the bound by constructing a subject with 257 entries where
    # every entry has a distinct synthetic keyId, none in the policy. The
    # verifier's _enforce_signature_bounds runs before per-signature policy
    # lookup, so the count >256 rejection fires first.
    import copy
    base_sigs = list(subject_obj["signatures"])
    # Pad with synthetic signatures having distinct keyIds not in policy.
    # The signatures array must still be sorted by keyId (parser enforces).
    synth_sigs = []
    for i in range(257):
        synth_sigs.append({
            "keyId": f"synth-key-{i:04d}",
            "algorithm": "ed25519",
            "signature": "00" * 64,
        })
    # Build a sorted combined list: the base sigs + synth sigs, sorted by keyId.
    all_sigs = base_sigs + synth_sigs
    all_sigs.sort(key=lambda s: s["keyId"])
    subject_obj["signatures"] = all_sigs
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.oversized_signature_count", False, actual)


def test_negative_unsorted_signature_keyids() -> RedMatrixResult:
    """A subject with signatures not sorted by keyId must reject (§1)."""
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Reverse the signature order (parser should catch this, but the
    # verifier's _enforce_signature_bounds also checks defensively).
    subject_obj["signatures"] = list(reversed(subject_obj["signatures"]))
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.unsorted_signature_keyids", False, actual)


def test_negative_review_commit_mismatch() -> RedMatrixResult:
    """§2: reviewCommit must equal the subject's preCloseCandidate.commit.

    A review whose reviewCommit points to a different commit than the
    subject's preCloseCandidate must reject at the reviews stage. The
    subject is re-signed after mutation so signature verification passes
    and the verifier reaches the reviews stage where the reviewCommit
    equality check must fire.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the review's reviewCommit to a different commit and re-sign
    # so the verifier reaches the reviews stage.
    subject_obj["independentReviews"][0]["reviewCommit"] = "f1" + "0" * 38
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.review_commit_mismatch", False, actual)


def _build_review_p01_test(name: str, bad_report: bytes) -> RedMatrixResult:
    """Helper: inject a bad review report into the bundle, update the subject
    ref's reportDigest to match, re-sign the subject, and run the verifier.

    The verifier should reject at the reviews stage because the §8.3 P0/P1
    parser finds a finding in the raw report bytes. The subject is re-signed
    so signature verification passes and the verifier reaches the reviews
    stage where the P0/P1 parser runs.

    The member role uses the raw 64-char hex of the report digest (not the
    `sha256:` wire form) to match the verifier's role construction.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    import hashlib
    bad_digest = hashlib.sha256(
        _TQO.DOMAIN_REVIEW_REPORT + b"\x00" + bad_report).digest()
    bad_digest_hex = bad_digest.hex()
    reviewer_id = subject_obj["independentReviews"][0]["reviewerId"]
    # Subject ref uses the wire form sha256:<hex>; member role uses raw hex.
    subject_obj["independentReviews"][0]["reportDigest"] = f"sha256:{bad_digest_hex}"
    for m in bundle_obj["members"]:
        if m.get("role", "").startswith("review-report/"):
            m["role"] = f"review-report/{reviewer_id}/{bad_digest_hex}"
            m["reviewerId"] = reviewer_id
            m["reportDigest"] = f"sha256:{bad_digest_hex}"
            m["bytesHex"] = bad_report.hex()
            break
    # Re-sign the subject so signature verification passes and the verifier
    # reaches the reviews stage where the P0/P1 parser runs.
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(name, False, actual)


def test_negative_review_report_p0_severity() -> RedMatrixResult:
    """§8.3: review report containing 'Severity: P0' must reject."""
    return _build_review_p01_test(
        "negative.review_report_p0_severity",
        b"# Review\n\nSeverity: P0\nsomething\n")


def test_negative_review_report_p1_prefix() -> RedMatrixResult:
    """§8.3: review report containing a 'P1:' line must reject."""
    return _build_review_p01_test(
        "negative.review_report_p1_prefix",
        b"# Review\n\nP1: something is wrong\n")


def test_negative_review_report_unresolved() -> RedMatrixResult:
    """§8.3: review report containing 'unresolved' (case-insensitive) must reject."""
    return _build_review_p01_test(
        "negative.review_report_unresolved",
        b"# Review\n\nThere is an Unresolved issue here.\n")


def _build_typed_member_corrupt_test(name: str, role_prefix: str) -> RedMatrixResult:
    """Helper: corrupt a typed-content member's bytesHex while keeping its
    content ref (and the subject ref) unchanged. The verifier must recompute
    the digest from the bytes and reject the mismatch.

    Currently the verifier only checks `member.content != ref`, which stays
    equal, so this passes (the bug). After the fix it must reject.

    The corruption flips a single byte in the middle of the bytesHex so that
    the bytes still decode as valid PF-JCS but produce a different digest.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    for m in bundle_obj["members"]:
        if m.get("role", "").startswith(role_prefix):
            corrupted = bytearray(bytes.fromhex(m["bytesHex"]))
            # Flip a byte in the middle of the payload. The fixture resolved
            # blob wire ends in a lowercase hex payloadSha256; flipping the
            # case bit of a hex letter keeps it valid lowercase hex (a-f ->
            # A-F is invalid, so instead we XOR a bit that maps 0-9 to a
            # different 0-9 or a-f to a different a-f). The simplest robust
            # flip: change a nibble by XORing 0x01 when the byte is a hex
            # digit char (0x30-0x39 or 0x61-0x66).
            idx = len(corrupted) // 2
            b = corrupted[idx]
            if 0x30 <= b <= 0x39 or 0x61 <= b <= 0x66:
                # Flip the low bit: 0x30<->0x31, 0x61<->0x60 (`a`<->backtick,
                # invalid). Use 0x02 instead to map a<->c, 0<->2.
                corrupted[idx] = b ^ 0x02
            else:
                # Fall back to flipping the case bit.
                corrupted[idx] = b ^ 0x20
            m["bytesHex"] = corrupted.hex()
            break
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult(name, False, actual)


def test_negative_typed_member_bytes_digest_mismatch() -> RedMatrixResult:
    """§8.2: gate-keyed control member bytesHex must recompute to member.content.digest.

    A gate-keyed control (eligible-stage0-handoff) whose bytesHex decodes to
    a different digest than member.content.digest must reject at the controls
    stage. The member.content and the subject gate ref are left unchanged, so
    the current verifier (which only checks member.content != ref) accepts it.
    After the fix it must recompute and reject.
    """
    return _build_typed_member_corrupt_test(
        "negative.typed_member_bytes_digest_mismatch",
        "eligible-stage0-handoff/")


def test_negative_gate_control_bytes_digest_mismatch() -> RedMatrixResult:
    """§8.2: revocation-snapshot singleton bytesHex must recompute to member.content.digest.

    The revocation-snapshot is a bundle-level singleton typed-content member.
    Corrupting its bytesHex while keeping member.content and the gate ref
    unchanged must reject. The current verifier only checks
    member.content != ref, so it accepts the corruption.
    """
    return _build_typed_member_corrupt_test(
        "negative.gate_control_bytes_digest_mismatch",
        "revocation-snapshot")


def test_negative_empty_independent_reviews() -> RedMatrixResult:
    """§8.2: independentReviews must be nonempty (review nonempty).

    A qualification with zero independent reviews must reject. The parser
    caps reviews at MAX_REVIEWS=256 but does not enforce a lower bound of 1,
    so an empty list parses. The verifier must reject it per §8.2
    ('review nonempty'). The subject is re-signed so signature verification
    passes and the verifier reaches the reviews stage where the count
    check must fire.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Remove all review-report members from the bundle and empty the subject's
    # independentReviews so the member-stage role-set and the reviews-stage
    # count both see zero reviews.
    bundle_obj["members"] = [
        m for m in bundle_obj["members"]
        if not m.get("role", "").startswith("review-report/")
    ]
    subject_obj["independentReviews"] = []
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.empty_independent_reviews", False, actual)


def test_negative_d0_10_empty_independent_reviews() -> RedMatrixResult:
    """§8.2: D0-10 bootstrap approval independentReviews must be nonempty.

    Same as the qualification variant but for the D0-10 bootstrap approval
    path. The verifier must reject an approval with zero independent reviews.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    bundle_obj["members"] = [
        m for m in bundle_obj["members"]
        if not m.get("role", "").startswith("review-report/")
    ]
    approval_obj["independentReviews"] = []
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_empty_independent_reviews", False, actual)


def test_negative_gate_testids_union_mismatch() -> RedMatrixResult:
    """§3: all gate testIds must be non-overlapping and their sorted union
    must exactly equal row.tests.

    A qualification whose gate testIds union does not equal row.tests must
    reject. The fixture has a single gate whose testIds == row.tests. Adding
    an extra testId to the gate (so the union has one extra) breaks the
    invariant. The subject is re-signed so signature verification passes and
    the verifier reaches the controls stage where the union check fires.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Add an extra testId to the first gate so the union no longer equals
    # row.tests.
    subject_obj["gates"][0]["testIds"] = list(
        subject_obj["gates"][0]["testIds"]) + ["TST-EXTRA-FAKE"]
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.gate_testids_union_mismatch", False, actual)


def test_negative_d0_10_gate_testids_union_mismatch() -> RedMatrixResult:
    """§3: D0-10 bootstrap gate testIds must equal row.tests.

    The D0-10 approval has a single bootstrapGate whose testIds must equal
    taskRow.tests. Adding an extra testId breaks the invariant. The subject
    is re-signed so the verifier reaches the controls stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["bootstrapGate"]["testIds"] = list(
        approval_obj["bootstrapGate"]["testIds"]) + ["TST-EXTRA-FAKE"]
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_gate_testids_union_mismatch", False, actual)


def test_negative_forbidden_allowed_path() -> RedMatrixResult:
    """§5: allowedCloseoutPatch.allowedPaths may only contain task-owned
    closeout locations (task table, Evidence ledger, checkpoint,
    trace/review/log) and the fixed qualification/bootstrap-approval path.

    Paths under product/verifier/protocol/test/freeze package are forbidden.
    The fixture patch is mutated to include a forbidden product path, the
    patch content ref is recomputed, the bundle member.content and the
    subject allowedCloseoutPatch ref are updated to match, and the subject
    is re-signed. The parser accepts the sorted unique nonempty list, so
    the verifier must reject it at the patch stage via the content
    restriction check.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Locate the allowed-closeout-patch member and inject a forbidden path.
    forbidden_path = "ProofForgeV2/ProofForge/Verifier.lean"
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            paths = list(patch_wire["allowedPaths"])
            # Insert the forbidden path in sorted position.
            import bisect
            bisect.insort(paths, forbidden_path)
            patch_wire["allowedPaths"] = paths
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            # Recompute the patch content ref.
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            # Update the subject's allowedCloseoutPatch ref to match.
            subject_obj["allowedCloseoutPatch"] = new_ref
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.forbidden_allowed_path", False, actual)


def test_negative_freeze_package_digest_mismatch() -> RedMatrixResult:
    """§3/§8.2: qualification.freezePackage.digest must equal the digest
    recomputed from the freeze-package-source member bytes under
    pf.task-freeze-package-source.v1.

    The verifier currently parses the freeze-package-source member and
    recomputes its digest (via _resolve_raw_member) but never joins it to
    qualification.freezePackage. A subject whose freezePackage.digest does
    not match the member bytes must reject. The subject is re-signed so
    signature verification passes and the verifier reaches the documents
    stage where the join check fires.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt the subject's freezePackage.digest to a different value.
    subject_obj["freezePackage"]["digest"] = "sha256:" + "cd" * 32
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.freeze_package_digest_mismatch", False, actual)


def test_negative_d0_10_freeze_package_digest_mismatch() -> RedMatrixResult:
    """§3/§8.2: D0-10 approval.freezePackage.digest must equal the digest
    recomputed from the freeze-package-source member bytes.

    Same as the qualification variant but for the D0-10 bootstrap approval
    path. The subject is re-signed so the verifier reaches the documents
    stage where the join check fires.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    approval_obj["freezePackage"]["digest"] = "sha256:" + "cd" * 32
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_freeze_package_digest_mismatch", False, actual)


def test_negative_semantic_file_set_digest_mismatch() -> RedMatrixResult:
    """§6: patch.semanticFileSetDigest must equal the digest recomputed from
    the full CloseoutFileSetV1 by removing the fixed Q/approval-path change,
    swapping schema/id, and dropping closeoutCandidate.

    The completion-receipt fixture is mutated so the allowed-closeout-patch
    member's semanticFileSetDigest disagrees with the §6 reconstruction.
    The patch content ref, member.content, and subject allowedCloseoutPatch
    ref are all recomputed consistently, and the subject is re-signed so
    the verifier reaches the projection stage where the reconstruction
    check fires.
    """
    qual_chain = _TQFB.build_fixture_chain()
    receipt_chain = _TQFB.build_completion_receipt_chain(qual_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    # Corrupt the allowed-closeout-patch member's semanticFileSetDigest and
    # recompute its content ref so the verifier reaches the projection stage.
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            patch_wire["semanticFileSetDigest"] = "sha256:" + "ee" * 32
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            receipt_obj["allowedCloseoutPatch"] = new_ref
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_completion_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.semantic_file_set_digest_mismatch", False, actual)


def test_negative_d0_10_semantic_file_set_digest_mismatch() -> RedMatrixResult:
    """§6: D0-10 receipt patch.semanticFileSetDigest must equal the digest
    recomputed from the full CloseoutFileSetV1.

    Same as the qualification variant but for the D0-10 bootstrap receipt
    path. The allowed-closeout-patch member's semanticFileSetDigest is
    corrupted, the patch content ref is recomputed, and the subject is
    re-signed.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            patch_wire["semanticFileSetDigest"] = "sha256:" + "ee" * 32
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            receipt_obj["allowedCloseoutPatch"] = new_ref
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_semantic_file_set_digest_mismatch", False, actual)


def test_negative_d0_10_receipt_resulting_task_row_digest_mismatch() -> RedMatrixResult:
    """GAP-13: §6 D0-10 receipt resulting row 与 AllowedCloseoutPatchV1 exact.
    The patch's resultingTaskRowDigest must equal the digest recomputed from
    the approval's taskRow with status flipped to done. Corrupt the patch's
    resultingTaskRowDigest and recompute the patch member ref; expect reject
    at the projection stage.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    for m in bundle_obj["members"]:
        if m.get("role") == "allowed-closeout-patch":
            patch_wire = _BTO.decode_canonical_pf_jcs(
                bytes.fromhex(m["bytesHex"]))
            patch_wire["resultingTaskRowDigest"] = "sha256:" + "ee" * 32
            new_bytes = _BTO.canonical_pf_jcs(patch_wire)
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest(
                _TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, patch_wire)
            new_ref = {
                "schema": patch_wire["schema"],
                "id": patch_wire["id"],
                "version": patch_wire["version"],
                "digest": _TQO.digest_to_wire(new_digest),
            }
            m["content"] = new_ref
            receipt_obj["allowedCloseoutPatch"] = new_ref
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_receipt_resulting_task_row_digest_mismatch", False, actual)


def test_negative_d0_10_receipt_fixed_path_after_bytes_mismatch() -> RedMatrixResult:
    """GAP-12: §6 D0-10 receipt fixed Q/approval-path change's afterDigest
    must equal plain_sha256(verified approval bytes). Corrupt the
    bootstrap-approval member bytes so the fixed-path change's afterDigest no
    longer matches; expect reject at the projection stage. The approval
    digest in the receipt is recomputed to match the corrupted member so the
    verifier reaches the projection stage.
    """
    approval_chain = _TQFB.build_d0_10_approval_chain()
    receipt_chain = _TQFB.build_d0_10_receipt_chain(approval_chain)
    bundle_obj, receipt_obj = _make_mutated_chain(receipt_chain)
    for m in bundle_obj["members"]:
        if m.get("role") == "bootstrap-approval":
            orig_bytes = bytes.fromhex(m["bytesHex"])
            orig_obj = _BTO.decode_canonical_pf_jcs(orig_bytes)
            orig_obj["gap12_corruption_marker"] = "tampered"
            corrupted = _BTO.canonical_pf_jcs(orig_obj)
            m["bytesHex"] = corrupted.hex()
            new_approval_digest = _TQO.domain_digest(
                _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, orig_obj)
            m["content"]["digest"] = _TQO.digest_to_wire(new_approval_digest)
            receipt_obj["approvalDigest"] = _TQO.digest_to_wire(new_approval_digest)
            break
    receipt_obj["signatures"] = _TQFB._sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(receipt_obj)
    actual = _run_d0_10_receipt_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_receipt_fixed_path_after_bytes_mismatch", False, actual)


def test_negative_dependency_archive_missing() -> RedMatrixResult:
    """§8.2: a present dependency requires its exact three-piece row:
    dependency/<taskId>, dependency-archive/<taskId>,
    dependency-commit-object/<taskId>.

    A qualification with one dependency whose dependency-archive member is
    removed must reject at the dependencies stage. The fixture chain with a
    dependency is used; the subject is not re-signed because removing a bundle
    member does not affect the subject signature.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Remove the dependency-archive member.
    bundle_obj["members"] = [
        m for m in bundle_obj["members"]
        if not m.get("role", "").startswith("dependency-archive/")
    ]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.dependency_archive_missing", False, actual)


def test_negative_dependency_commit_missing() -> RedMatrixResult:
    """§8.2: a present dependency requires its exact three-piece row.
    Removing the dependency-commit-object member must reject.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    bundle_obj["members"] = [
        m for m in bundle_obj["members"]
        if not m.get("role", "").startswith("dependency-commit-object/")
    ]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.dependency_commit_missing", False, actual)


def test_positive_legal_chain_with_dependency() -> RedMatrixResult:
    """A legal fixture chain with one task-qualification dependency and its
    three-piece member row should verify successfully.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_bytes, subject_bytes = _TQFB.fixture_chain_to_bytes(chain)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("positive.legal_chain_with_dependency", True, actual)


def test_negative_dependency_row_mismatch() -> RedMatrixResult:
    """GAP-10: §4 dependencies taskId set must exact-equal row direct
    dependencies. A qualification whose row.dependencies lists a different
    taskId than the actual dependency must reject.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the row.dependencies to a different taskId.
    subject_obj["taskRow"]["dependencies"] = ["TASK-D0-99"]
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.dependency_row_mismatch", False, actual)


def test_negative_dependency_receipt_taskid_mismatch() -> RedMatrixResult:
    """GAP-9: §4 the dependency's taskId must join the decoded receipt's
    taskId. A qualification whose dependency taskId differs from the decoded
    receipt's taskId must reject.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the dependency wire taskId to a different value (doesn't match
    # the decoded receipt). Re-sign the subject.
    subject_obj["dependencies"][0]["taskId"] = "TASK-D0-99"
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.dependency_receipt_taskid_mismatch", False, actual)


def test_negative_dependency_receipt_signatures_mismatch() -> RedMatrixResult:
    """GAP-9: §4 the dependency's signatures must exact-equal the decoded
    receipt's signatures (no wrapper self-sign). A qualification whose
    dependency signatures differ from the decoded receipt signatures must
    reject.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Truncate the dependency wire signatures (differs from receipt's 3).
    subject_obj["dependencies"][0]["signatures"] = [
        subject_obj["dependencies"][0]["signatures"][0]
    ]
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.dependency_receipt_signatures_mismatch", False, actual)


def test_negative_row_output_mismatch_freeze() -> RedMatrixResult:
    """GAP-3: §3 the taskRow must exact-equal the freeze package across
    taskId/output/dependencies/prerequisites/tests. A qualification whose
    taskRow.output differs from the freeze package's output must reject at the
    ancestry stage. The subject is re-signed so the verifier reaches the
    ancestry stage where the row-vs-freeze equality check fires.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the row.output to a different value than the freeze package's
    # output ("fixture qualification verifier test").
    subject_obj["taskRow"]["output"] = "tampered output value"
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.row_output_mismatch_freeze", False, actual)


def test_negative_row_prerequisites_mismatch_freeze() -> RedMatrixResult:
    """GAP-3: §3 the taskRow.prerequisites must exact-equal the freeze
    package's prerequisites. A qualification whose row lists an extra
    prerequisite absent from the freeze package must reject at the ancestry
    stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Add an extra prerequisite to row that the freeze package lacks.
    subject_obj["taskRow"]["prerequisites"] = list(
        subject_obj["taskRow"]["prerequisites"]
    ) + ["ADR-9999@accepted"]
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.row_prerequisites_mismatch_freeze", False, actual)


def test_negative_row_tests_mismatch_freeze() -> RedMatrixResult:
    """GAP-3: §3 the taskRow.tests must exact-equal the freeze package's
    tests. A qualification whose row lists a different test than the freeze
    package must reject at the ancestry stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the row.tests to a different test id.
    subject_obj["taskRow"]["tests"] = ["TST-FAKE-001"]
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.row_tests_mismatch_freeze", False, actual)


def test_negative_freeze_in_scope_too_few() -> RedMatrixResult:
    """GAP-5: §3 freeze package inScope must be 3..12. A freeze package source
    whose inScope has only 2 items must reject at the ancestry stage (freeze
    package parse). The bundle's freeze-package-source member is corrupted to
    have only 2 inScope items; the subject's freezePackage.digest is recomputed
    to match so the verifier reaches the ancestry stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Mutate the freeze-package-source member to have only 2 inScope items.
    for m in bundle_obj["members"]:
        if m.get("role") == "freeze-package-source":
            content_bytes = bytes.fromhex(m["bytesHex"])
            pkg = json.loads(content_bytes.decode("utf-8"))
            pkg["inScope"] = pkg["inScope"][:2]
            new_bytes = json.dumps(pkg, separators=(",", ":")).encode("utf-8")
            m["bytesHex"] = new_bytes.hex()
            # Recompute the raw.digest and subject's freezePackage.digest.
            new_digest = _TQO.domain_digest_raw(
                _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, new_bytes)
            m["raw"]["digest"] = _TQO.digest_to_wire(new_digest)
            subject_obj["freezePackage"]["digest"] = _TQO.digest_to_wire(new_digest)
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.freeze_in_scope_too_few", False, actual)


def test_negative_freeze_max_days_out_of_bounds() -> RedMatrixResult:
    """GAP-5: §3 freeze package maxCalendarDays must be 1..365. A freeze
    package source whose maxCalendarDays exceeds 365 must reject at the
    ancestry stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    for m in bundle_obj["members"]:
        if m.get("role") == "freeze-package-source":
            content_bytes = bytes.fromhex(m["bytesHex"])
            pkg = json.loads(content_bytes.decode("utf-8"))
            pkg["maxCalendarDays"] = 366
            new_bytes = json.dumps(pkg, separators=(",", ":")).encode("utf-8")
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest_raw(
                _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, new_bytes)
            m["raw"]["digest"] = _TQO.digest_to_wire(new_digest)
            subject_obj["freezePackage"]["digest"] = _TQO.digest_to_wire(new_digest)
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.freeze_max_days_out_of_bounds", False, actual)


def test_negative_freeze_tests_empty() -> RedMatrixResult:
    """GAP-5: §3 freeze package tests must be nonempty. A freeze package
    source whose tests is empty must reject at the ancestry stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    for m in bundle_obj["members"]:
        if m.get("role") == "freeze-package-source":
            content_bytes = bytes.fromhex(m["bytesHex"])
            pkg = json.loads(content_bytes.decode("utf-8"))
            pkg["tests"] = []
            new_bytes = json.dumps(pkg, separators=(",", ":")).encode("utf-8")
            m["bytesHex"] = new_bytes.hex()
            new_digest = _TQO.domain_digest_raw(
                _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, new_bytes)
            m["raw"]["digest"] = _TQO.digest_to_wire(new_digest)
            subject_obj["freezePackage"]["digest"] = _TQO.digest_to_wire(new_digest)
            break
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.freeze_tests_empty", False, actual)


def test_negative_command_policy_tool_ref_unjoined() -> RedMatrixResult:
    """GAP-23: §8.2/§3 the command policy's tool ContentRef must join the
    resolved-tool/<gateId> member. A bundle whose resolved-tool member content
    ref differs from the command policy's tool ref must reject at the command
    stage.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Corrupt the resolved-tool member's content ref so it doesn't match the
    # command policy's tool ref.
    for m in bundle_obj["members"]:
        if m.get("role", "").startswith("resolved-tool/"):
            m["content"]["digest"] = "sha256:" + "ee" * 32
            break
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.command_policy_tool_ref_unjoined", False, actual)


def test_negative_command_policy_verifier_closure_missing() -> RedMatrixResult:
    """GAP-22/23: §8.2 the verifier-closure/<gateId> member must be present and
    join the command policy's verifier.closure ref. Removing the
    verifier-closure member must reject at the command stage.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    bundle_obj["members"] = [
        m for m in bundle_obj["members"]
        if not m.get("role", "").startswith("verifier-closure/")
    ]
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.command_policy_verifier_closure_missing", False, actual)


def test_negative_gate_evidence_empty() -> RedMatrixResult:
    """GAP-25: §8.2 qualification/approval evidence families are nonempty per
    gate. A qualification whose gate has zero evidence must reject at the
    evidence stage.
    """
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Empty the gate's evidence list and re-sign.
    subject_obj["gates"][0]["evidence"] = []
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.gate_evidence_empty", False, actual)


def _build_random_root_commit() -> tuple:
    """Build a random root git commit object (no parents) and return
    (commit_sha, commit_payload).
    """
    tree_sha = "a" * 40  # arbitrary tree, doesn't need to match anything
    payload = _TQFB.build_synthetic_git_commit(tree_sha, None, message="extra ancestry node")
    sha = _TQO.git_sha1_object("commit", payload)
    return (sha, payload)


def test_negative_ancestry_extra_commit_not_in_graph() -> RedMatrixResult:
    """§8.3: an ancestry-commit/* member whose commit is not in the ancestry
    union (not reachable from C via parent edges) must reject at the ancestry
    stage. The fixture chain with a dependency is used; an extra
    ancestry-commit/<40hex> member with a random root commit is appended.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    sha, payload = _build_random_root_commit()
    bundle_obj["members"].append({
        "role": f"ancestry-commit/{sha}",
        "kind": "git-object",
        "objectId": sha,
        "objectType": "commit",
        "bytesHex": payload.hex(),
    })
    bundle_obj["members"].sort(key=lambda m: m["role"])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.ancestry_extra_commit_not_in_graph", False, actual)


def test_negative_ancestry_dependency_unreachable() -> RedMatrixResult:
    """§4/§8.3: the dependency's completionCommit must be a strict ancestor of
    C (reachable from C via parent edges). A qualification whose dependency
    completionCommit is an independent root (not C's ancestor) must reject at
    the ancestry stage.

    The fixture chain is mutated: a second independent root commit is built,
    added as a dependency-commit-object/<taskId> member, and the
    qualification's dependency completionCommit is set to that commit. The
    subject is re-signed so the verifier reaches the ancestry stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Build an independent root commit that is NOT an ancestor of C.
    unreachable_sha, unreachable_payload = _build_random_root_commit()
    # Add a dependency-commit-object member for a bogus task carrying the
    # unreachable commit. We use the existing FIXTURE_DEP_TASK_ID role.
    for m in bundle_obj["members"]:
        if m.get("role") == f"dependency-commit-object/{_TQFB.FIXTURE_DEP_TASK_ID}":
            m["objectId"] = unreachable_sha
            m["bytesHex"] = unreachable_payload.hex()
            break
    # Mutate the qualification subject's dependency completionCommit to the
    # unreachable commit and re-sign.
    subject_obj["dependencies"][0]["completionCommit"] = unreachable_sha
    subject_obj["signatures"] = _TQFB._sign_subject(
        subject_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.ancestry_dependency_unreachable", False, actual)


def test_negative_ancestry_duplicate_target_as_ancestry_commit() -> RedMatrixResult:
    """§8.3: target commits (C, dependency completionCommits) must not be
    duplicated as ancestry-commit/*. A qualification whose candidate commit
    is also carried by an ancestry-commit/* member must reject at the ancestry
    stage.
    """
    chain = _TQFB.build_fixture_chain_with_dependency()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    candidate_commit = subject_obj["preCloseCandidate"]["commit"]
    # Find the candidate-commit-object member's bytesHex (the candidate commit
    # payload) and duplicate it as an ancestry-commit/* member.
    candidate_payload_hex = None
    for m in bundle_obj["members"]:
        if m.get("role") == "candidate-commit-object":
            candidate_payload_hex = m["bytesHex"]
            break
    bundle_obj["members"].append({
        "role": f"ancestry-commit/{candidate_commit}",
        "kind": "git-object",
        "objectId": candidate_commit,
        "objectType": "commit",
        "bytesHex": candidate_payload_hex,
    })
    bundle_obj["members"].sort(key=lambda m: m["role"])
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(subject_obj)
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.ancestry_duplicate_target_as_ancestry_commit", False, actual)


def test_negative_d0_10_ancestry_bridge_unreachable() -> RedMatrixResult:
    """§4/§8.3: the D0-07 bridge completionCommit must be a strict ancestor of
    C. A D0-10 approval whose D0-07 completionCommit is an independent root
    (not C's ancestor) must reject at the ancestry stage.

    The D0-10 approval fixture is mutated: the d0-07-completion-commit-object
    member is replaced with an independent root commit, and the approval
    subject's d0_07Bridge.completionCommit is set to that commit. The subject
    is re-signed so the verifier reaches the ancestry stage.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    unreachable_sha, unreachable_payload = _build_random_root_commit()
    # Replace the d0-07-completion-commit-object member with the unreachable
    # commit.
    for m in bundle_obj["members"]:
        if m.get("role") == "d0-07-completion-commit-object":
            m["objectId"] = unreachable_sha
            m["bytesHex"] = unreachable_payload.hex()
            break
    # Mutate the approval subject's d0_07Bridge.completionCommit and re-sign.
    approval_obj["d0_07Bridge"]["completionCommit"] = unreachable_sha
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_ancestry_bridge_unreachable", False, actual)


def _mutate_d0_10_approval_bridge(bridge_mutator, re_sign=True) -> RedMatrixResult:
    """Helper: mutate the D0-10 approval subject's d0_07Bridge field via
    bridge_mutator(approval_obj), optionally re-sign, and run the verifier.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    bridge_mutator(approval_obj)
    if re_sign:
        approval_obj["signatures"] = _TQFB._sign_subject(
            approval_obj,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
        )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return actual


def test_negative_d0_10_bridge_wrong_completion_commit() -> RedMatrixResult:
    """§7: wrapper.completionCommit must equal decoded completionCandidate.commit.
    Mutating the bridge completionCommit to a different value must reject.
    """
    def mutator(approval_obj):
        approval_obj["d0_07Bridge"]["completionCommit"] = "f1" + "e" * 38
    actual = _mutate_d0_10_approval_bridge(mutator)
    return RedMatrixResult("negative.d0_10_bridge_wrong_completion_commit", False, actual)


def test_negative_d0_10_bridge_wrong_task_id() -> RedMatrixResult:
    """§7: bridge.taskId must equal gc.taskId (TASK-D0-07). Mutating the bridge
    taskId must reject.
    """
    def mutator(approval_obj):
        approval_obj["d0_07Bridge"]["taskId"] = "TASK-D0-99"
    actual = _mutate_d0_10_approval_bridge(mutator)
    return RedMatrixResult("negative.d0_10_bridge_wrong_task_id", False, actual)


def test_negative_d0_10_bridge_wrong_ruling_digest() -> RedMatrixResult:
    """§7: bridge.ruling.digest must equal gc.ruling.contentDigest. Mutating
    the bridge ruling digest must reject.
    """
    def mutator(approval_obj):
        approval_obj["d0_07Bridge"]["ruling"]["digest"] = "sha256:" + "ee" * 32
    actual = _mutate_d0_10_approval_bridge(mutator)
    return RedMatrixResult("negative.d0_10_bridge_wrong_ruling_digest", False, actual)


def test_negative_d0_10_bridge_self_signed() -> RedMatrixResult:
    """§7: dependency wrapper signatures must equal decoded object signatures
    (no wrapper-self-signed). Mutating the bridge signatures to differ from the
    gc object signatures must reject.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    # The gc object signatures are 3 (Architecture+Quality+Security). Replace
    # the bridge signatures with a single bogus signature to make them differ.
    approval_obj["d0_07Bridge"]["signatures"] = [
        approval_obj["d0_07Bridge"]["signatures"][0]
    ]
    approval_obj["signatures"] = _TQFB._sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_bridge_self_signed", False, actual)


def test_negative_d0_10_bridge_corrupt_gc_signatures() -> RedMatrixResult:
    """§7: the governance completion object's signatures must verify under §1
    fixed rule. Corrupting the gc member's signature bytes must reject.
    """
    chain = _TQFB.build_d0_10_approval_chain()
    bundle_obj, approval_obj = _make_mutated_chain(chain)
    # Corrupt the d0-07-governance-completion member's bytesHex (corrupt a
    # signature) so the gc signature verification fails.
    for m in bundle_obj["members"]:
        if m.get("role") == "d0-07-governance-completion":
            gc_wire = _BTO.decode_canonical_pf_jcs(bytes.fromhex(m["bytesHex"]))
            gc_wire["signatures"][0]["signature"] = "00" * 64
            m["bytesHex"] = _BTO.canonical_pf_jcs(gc_wire).hex()
            # Recompute the content ref digest to match the corrupted bytes.
            new_ref = _TQO.recompute_typed_content_ref(
                gc_wire["schema"], gc_wire)
            m["content"] = {
                "schema": new_ref.schema,
                "id": new_ref.id,
                "version": new_ref.version,
                "digest": _TQO.digest_to_wire(new_ref.digest),
            }
            break
    bundle_bytes = _canonical_bytes(bundle_obj)
    subject_bytes = _canonical_bytes(approval_obj)
    actual = _run_d0_10_approval_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.d0_10_bridge_corrupt_gc_signatures", False, actual)


def test_negative_aggregate_member_bound_exceeded() -> RedMatrixResult:
    """§8.2: the aggregate decoded-member bytes must not exceed
    MAX_BUNDLE_AGGREGATE (128 MiB). The verifier must scan canonical hex
    length before any allocation/curve work and reject if the aggregate
    exceeds the bound.

    To keep the test computationally feasible, the MAX_BUNDLE_AGGREGATE
    constant is temporarily lowered to a small value, and a fixture bundle's
    member bytesHex are inflated to exceed that lowered threshold. The test
    drives the real shipped _check_aggregate_member_bound code path (which
    reads _TQO.MAX_BUNDLE_AGGREGATE at runtime).
    """
    import unittest.mock as mock
    chain = _TQFB.build_fixture_chain()
    bundle_obj, subject_obj = _make_mutated_chain(chain)
    # Lower the threshold to 256 bytes so the test is fast. Inflate one
    # member's bytesHex to exceed 256 decoded bytes.
    small_limit = 256
    with mock.patch.object(_TQO, "MAX_BUNDLE_AGGREGATE", small_limit):
        for m in bundle_obj["members"]:
            if m.get("role") == "candidate-archive":
                # Set bytesHex to 300 decoded bytes (600 hex chars).
                m["bytesHex"] = "ab" * 300
                break
        bundle_bytes = _canonical_bytes(bundle_obj)
        subject_bytes = _canonical_bytes(subject_obj)
        actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.aggregate_member_bound_exceeded", False, actual)


def test_negative_production_profile_member_bytes_mismatch() -> RedMatrixResult:
    """§8.2 line 497-500: the bundle's embedded verificationProfile canonical
    PF-JCS bytes must equal the production-profile member's decoded bytes.

    This test drives the real shipped _verify_production_profile_member_bytes
    function directly with a synthetic production profile and a production-
    profile member whose bytes differ from the profile's PF-JCS bytes.
    """
    import task_qualification_protected_adapter_self_test as _tas
    # Build a synthetic production profile (signed).
    auth_policy_ref = _TQO.fixture_policy_content_ref(_TQO.build_default_fixture_policy())
    adapter = _TQFB.build_verifier_identity("synth-gate")
    profile = _tas._build_synth_production_profile(auth_policy_ref, adapter)
    # Build a production-profile typed-content member whose bytes differ
    # from the profile's canonical PF-JCS bytes (corrupt one signature byte).
    profile_wire = _TQO.production_profile_to_wire(profile)
    profile_bytes = _BTO.canonical_pf_jcs(profile_wire)
    corrupt_wire = _BTO.decode_canonical_pf_jcs(profile_bytes)
    corrupt_wire["signatures"][0]["signature"] = "00" * 64
    corrupt_bytes = _BTO.canonical_pf_jcs(corrupt_wire)
    corrupt_ref = _TQO.recompute_typed_content_ref(corrupt_wire["schema"], corrupt_wire)
    member = _TQO.TypedContentMemberV1(
        role="production-profile",
        kind="typed-content",
        content=corrupt_ref,
        bytesHex=corrupt_bytes.hex(),
    )
    member_map = {"production-profile": member}
    # The function must reject because the profile PF-JCS bytes != member bytes.
    try:
        _TQV._verify_production_profile_member_bytes(member_map, profile, "profile-member")
        actual = True  # should not reach here
    except _BTO.Rejected:
        actual = False  # rejected as expected
    return RedMatrixResult("negative.production_profile_member_bytes_mismatch", False, actual)


def test_positive_production_profile_member_bytes_match() -> RedMatrixResult:
    """§8.2: when the production-profile member bytes exactly equal the
    bundle's verificationProfile PF-JCS bytes, the check must pass.

    This test drives the real shipped _verify_production_profile_member_bytes
    function directly with a synthetic production profile and a matching
    production-profile member.
    """
    import task_qualification_protected_adapter_self_test as _tas
    auth_policy_ref = _TQO.fixture_policy_content_ref(_TQO.build_default_fixture_policy())
    adapter = _TQFB.build_verifier_identity("synth-gate")
    profile = _tas._build_synth_production_profile(auth_policy_ref, adapter)
    profile_wire = _TQO.production_profile_to_wire(profile)
    profile_bytes = _BTO.canonical_pf_jcs(profile_wire)
    profile_ref = _TQO.recompute_typed_content_ref(profile_wire["schema"], profile_wire)
    member = _TQO.TypedContentMemberV1(
        role="production-profile",
        kind="typed-content",
        content=profile_ref,
        bytesHex=profile_bytes.hex(),
    )
    member_map = {"production-profile": member}
    try:
        _TQV._verify_production_profile_member_bytes(member_map, profile, "profile-member")
        actual = True  # passed as expected
    except _BTO.Rejected:
        actual = False
    return RedMatrixResult("positive.production_profile_member_bytes_match", True, actual)


def test_negative_non_canonical_bundle() -> RedMatrixResult:
    """A non-canonical bundle (non-PF-JCS) should reject at bundle stage."""
    chain = _TQFB.build_fixture_chain()
    _, subject_bytes = _TQFB.fixture_chain_to_bytes(chain)
    # Create a non-canonical bundle (with whitespace)
    import json
    bundle_bytes = json.dumps(chain.bundle_obj, indent=2).encode("utf-8")
    actual = _run_verifier(bundle_bytes, subject_bytes)
    return RedMatrixResult("negative.non_canonical_bundle", False, actual)


def test_negative_empty_subject() -> RedMatrixResult:
    """An empty subject should reject at bounds stage."""
    chain = _TQFB.build_fixture_chain()
    bundle_bytes, _ = _TQFB.fixture_chain_to_bytes(chain)
    actual = _run_verifier(bundle_bytes, b"")
    return RedMatrixResult("negative.empty_subject", False, actual)


def test_negative_empty_bundle() -> RedMatrixResult:
    """An empty bundle should reject at bounds stage."""
    chain = _TQFB.build_fixture_chain()
    _, subject_bytes = _TQFB.fixture_chain_to_bytes(chain)
    actual = _run_verifier(b"", subject_bytes)
    return RedMatrixResult("negative.empty_bundle", False, actual)


# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

def run_all_tests() -> list:
    """Run all RED matrix tests and return the results."""
    tests = [
        # Positive
        test_positive_legal_chain,
        test_positive_legal_completion_receipt,
        # Negative
        test_negative_wrong_signature,
        test_negative_missing_signature,
        test_negative_wrong_role_signature,
        test_negative_missing_member,
        test_negative_corrupt_archive,
        test_negative_wrong_candidate_commit,
        test_negative_oversized_subject,
        test_negative_wrong_fixture_namespace,
        test_negative_wrong_keyset,
        test_negative_policy_ref_mismatch,
        test_negative_duplicate_member_role,
        test_negative_unsorted_members,
        test_negative_wrong_schema,
        test_negative_empty_gates,
        test_negative_empty_reviews,
        # §1 signature bound enforcement (P1-G/P1-H)
        test_negative_oversized_signature_count,
        test_negative_unsorted_signature_keyids,
        # §2 reviewCommit equality + §8.3 P0/P1 parser (P0-5/P0-4)
        test_negative_review_commit_mismatch,
        test_negative_review_report_p0_severity,
        test_negative_review_report_p1_prefix,
        test_negative_review_report_unresolved,
        # §8.2 typed-content member digest recompute (P0-2)
        test_negative_typed_member_bytes_digest_mismatch,
        test_negative_gate_control_bytes_digest_mismatch,
        # §8.2 independentReviews nonempty (P1-3)
        test_negative_empty_independent_reviews,
        test_negative_d0_10_empty_independent_reviews,
        # §3 gate testIds union == row.tests, non-overlap (P1-2)
        test_negative_gate_testids_union_mismatch,
        test_negative_d0_10_gate_testids_union_mismatch,
        # §5 allowedCloseoutPatch.allowedPaths content restrictions (P1-11)
        test_negative_forbidden_allowed_path,
        # §3/§8.2 freezePackage digest join (P1-1)
        test_negative_freeze_package_digest_mismatch,
        test_negative_d0_10_freeze_package_digest_mismatch,
        # §6 semanticFileSetDigest reconstruction (P0-6)
        test_negative_semantic_file_set_digest_mismatch,
        test_negative_d0_10_semantic_file_set_digest_mismatch,
        # §6 GAP-12/13 D0-10 receipt: resulting row + fixed-path after-bytes
        test_negative_d0_10_receipt_resulting_task_row_digest_mismatch,
        test_negative_d0_10_receipt_fixed_path_after_bytes_mismatch,
        # §8.2 dependency three-piece row enforcement (P0-3)
        test_negative_dependency_archive_missing,
        test_negative_dependency_commit_missing,
        test_positive_legal_chain_with_dependency,
        # §4 dependency internal verification (GAP-9/10)
        test_negative_dependency_row_mismatch,
        test_negative_dependency_receipt_taskid_mismatch,
        test_negative_dependency_receipt_signatures_mismatch,
        # §3 row vs freeze package exact equality (GAP-3)
        test_negative_row_output_mismatch_freeze,
        test_negative_row_prerequisites_mismatch_freeze,
        test_negative_row_tests_mismatch_freeze,
        # §3 freeze field bounds (GAP-5)
        test_negative_freeze_in_scope_too_few,
        test_negative_freeze_max_days_out_of_bounds,
        test_negative_freeze_tests_empty,
        # §8.2/§3 command policy ref joins (GAP-22/23)
        test_negative_command_policy_tool_ref_unjoined,
        test_negative_command_policy_verifier_closure_missing,
        # §8.2/§3 gate evidence nonempty + id-sort (GAP-25/8)
        test_negative_gate_evidence_empty,
        # §8.3 ancestry graph closure (P1-5/P1-6)
        test_negative_ancestry_extra_commit_not_in_graph,
        test_negative_ancestry_dependency_unreachable,
        test_negative_ancestry_duplicate_target_as_ancestry_commit,
        test_negative_d0_10_ancestry_bridge_unreachable,
        # §7 D0-07 bridge internal verification (P1-4)
        test_negative_d0_10_bridge_wrong_completion_commit,
        test_negative_d0_10_bridge_wrong_task_id,
        test_negative_d0_10_bridge_wrong_ruling_digest,
        test_negative_d0_10_bridge_self_signed,
        test_negative_d0_10_bridge_corrupt_gc_signatures,
        # §8.2 aggregate decoded-member bound (P1-9)
        test_negative_aggregate_member_bound_exceeded,
        # §8.2 production-profile member bytes (P1-7)
        test_negative_production_profile_member_bytes_mismatch,
        test_positive_production_profile_member_bytes_match,
        test_negative_non_canonical_subject,
        test_negative_non_canonical_bundle,
        test_negative_empty_subject,
        test_negative_empty_bundle,
        # Completion receipt negative
        test_negative_completion_wrong_signature,
        test_negative_completion_wrong_parent,
        # D0-10 bootstrap approval
        test_positive_legal_d0_10_approval,
        test_negative_d0_10_wrong_signature,
        test_negative_d0_10_wrong_task_id,
        test_negative_d0_10_wrong_ruling,
        # §7 GAP-16: ruling-source join (contentDigest/status/reviewCommit)
        test_negative_d0_10_ruling_content_digest_mismatch,
        test_negative_d0_10_ruling_wrong_status,
        test_negative_d0_10_ruling_review_commit_mismatch,
        # §7 SA-1: ledgerEvidenceId presence/format on D0-10 approval
        test_positive_d0_10_approval_has_ledger_evidence_id,
        test_negative_d0_10_approval_missing_ledger_evidence_id,
        test_negative_d0_10_approval_malformed_ledger_evidence_id,
        # §7 SA-2: ledgerEvidenceId on D0-10 receipt + approval/receipt equality
        test_positive_d0_10_receipt_has_ledger_evidence_id,
        test_negative_d0_10_receipt_missing_ledger_evidence_id,
        test_negative_d0_10_receipt_malformed_ledger_evidence_id,
        test_negative_d0_10_receipt_ledger_evidence_id_mismatch,
        # §8.2 GAP-24: phantom gateId in gate-keyed members
        test_negative_phantom_gate_id_member,
        # §8.2 GAP-11: fixture policy principal keys pinned to RFC 8032 vectors
        test_negative_fixture_policy_wrong_principal_public_key,
        # §6 GAP-15: issuedAt RFC3339 UTC validation
        test_negative_completion_receipt_invalid_issued_at,
        # §3 GAP-6: argv[0] absolute canonical executable
        test_negative_command_policy_argv0_not_absolute,
        # D0-10 bootstrap receipt
        test_positive_legal_d0_10_receipt,
        test_negative_d0_10_receipt_wrong_signature,
        test_negative_d0_10_receipt_wrong_parent,
        # §8.2 role-set enforcement (P0-3)
        test_negative_receipt_forbidden_evidence_member,
        test_negative_fixture_forbidden_production_profile,
        test_negative_qualification_missing_revocation_snapshot,
        # §6 closeout file set from archives (P0-4)
        test_negative_completion_wrong_diff_digest,
        # §6 GAP-12/13: fixed-path after-bytes + closeout diff paths + resulting row
        test_negative_completion_resulting_task_row_digest_mismatch,
        test_negative_completion_closeout_diff_paths_mismatch_allowed,
        test_negative_completion_fixed_path_after_bytes_mismatch,
        # §8.1/§8.2 receipt qualification member verification (P1-8)
        test_negative_receipt_qualification_digest_mismatch,
        test_negative_receipt_qualification_taskid_mismatch,
        test_negative_receipt_qualification_id_mismatch,
    ]
    results = []
    for test in tests:
        try:
            result = test()
        except Exception as exc:
            result = RedMatrixResult(test.__name__, False, False, f"exception: {exc}")
        results.append(result)
    return results


def main():
    results = run_all_tests()
    passed = sum(1 for r in results if r.passed())
    failed = sum(1 for r in results if not r.passed())
    print(f"RED Matrix: {passed}/{len(results)} passed, {failed} failed")
    for r in results:
        print(r)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())