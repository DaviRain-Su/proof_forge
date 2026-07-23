#!/usr/bin/env python3
"""External TASK-D0-10 D→receipt/GBC/Ledger completion builder.

The module is called by ``task_qualification_ceremony.py`` after direct-child D
has been committed.  The ceremony remains the only process that reads private
production seeds.  This builder emits only public signed objects, a protected
acceptance, and an exact optional-P publication plan.

The local seqpacket ceremony is the accepted single-maintainer bootstrap/
development path.  It is not described as ADR-0021's complete static U/P/A
custody supervisor, durable nonce store, formal evidence, or hermetic evidence.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve()
_ROOT = _HERE.parent.parent
sys.path.insert(0, str(_HERE.parent))

import task_qualification_closeout as _C

_BTO = _C._BTO
_FIXTURE = _C._FIXTURE
_TQO = _C._TQO
_VERIFIER = _C._VERIFIER

TASK_ID = _C.TASK_ID
TEST_ID = _C.TEST_ID
LEDGER_EVIDENCE_ID = _C.LEDGER_EVIDENCE_ID
APPROVAL_PATH = _C.APPROVAL_PATH
RECEIPT_PATH = _C.RECEIPT_PATH
COMPLETION_PATH = _C.COMPLETION_PATH
LEDGER_PROJECTION_PATH = _C.LEDGER_PROJECTION_PATH
ATTEST_PATH = _C.ATTEST_PATH
ROLE_AQS = _C.ROLE_AQS


class CompletionError(RuntimeError):
    pass


def _canonical(value: Any) -> bytes:
    return _C._canonical(value)


def _canonical_large(value: Any) -> bytes:
    return _C._canonical_large(value)


def _digest(payload: bytes) -> _BTO.Digest:
    return _C._digest(payload)


def _digest_wire(value: _BTO.Digest) -> str:
    return _C._digest_wire(value)


def _ref_wire(value: _BTO.ContentRef) -> dict:
    return _C._ref_wire(value)


def _candidate_wire(value: _BTO.CandidateIdentity) -> dict:
    return _C._candidate_wire(value)


def _utc_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(
        microsecond=0
    ).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read_canonical(path: Path, maximum: int, label: str) -> tuple[dict, bytes]:
    try:
        if path.is_symlink() or not path.is_file():
            raise CompletionError(f"{label} is not a regular file")
        payload = path.read_bytes()
    except OSError as exc:
        raise CompletionError(f"cannot read {label}") from exc
    if not 1 <= len(payload) <= maximum:
        raise CompletionError(f"{label} size is outside its bound")
    try:
        value = _BTO.decode_canonical_pf_jcs(payload)
    except Exception as exc:
        raise CompletionError(f"{label} is not canonical PF-JCS") from exc
    if type(value) is not dict or _canonical(value) != payload:
        raise CompletionError(f"{label} must be one canonical object")
    return value, payload


def _build_closeout_file_set(
    pre: _FIXTURE.CandidateContext,
    close: _FIXTURE.CandidateContext,
) -> _TQO.CloseoutFileSetV1:
    if tuple(close.commit_object.parents) != (pre.identity.commit,):
        raise CompletionError("D must be the unique direct child of C")
    changes = []
    paths = sorted(
        set(pre.archive_projection.path_map)
        | set(close.archive_projection.path_map)
    )
    for path in paths:
        before_entry = pre.archive_projection.path_map.get(path)
        after_entry = close.archive_projection.path_map.get(path)
        before = _digest(before_entry.content) if before_entry is not None else None
        after = _digest(after_entry.content) if after_entry is not None else None
        if before == after:
            continue
        if before is None and after is None:
            raise CompletionError("closeout diff contains an empty change")
        changes.append((path, before, after))
    if not 1 <= len(changes) <= _TQO.MAX_CLOSEOUT_PATHS:
        raise CompletionError("closeout diff is outside the frozen path bound")
    return _TQO.CloseoutFileSetV1(
        schema="proof-forge.closeout-file-set.v1",
        id="closeout-d0-10",
        version="1.0.0",
        taskId=TASK_ID,
        preCloseCandidate=pre.identity,
        closeoutCandidate=close.identity,
        changes=tuple(changes),
    )


def _load_committed_d(
    input_root: Path,
) -> dict[str, Any]:
    d_commit = _C._require_clean_head()
    close = _C.load_git_candidate(d_commit, TASK_ID)
    if len(close.commit_object.parents) != 1:
        raise CompletionError("D commit must have exactly one parent")
    c_commit = close.commit_object.parents[0]
    pre = _C.load_git_candidate(c_commit, TASK_ID)

    plan_obj, _ = _read_canonical(
        input_root / "plan.json", 1_048_576, "closeout plan"
    )
    if (
        plan_obj.get("schema") != "proof-forge.task-qualification-closeout-plan.v1"
        or plan_obj.get("taskId") != TASK_ID
        or plan_obj.get("preCloseCandidate") != _candidate_wire(pre.identity)
    ):
        raise CompletionError("closeout plan is not bound to C")

    approval_entry = close.archive_projection.path_map.get(APPROVAL_PATH)
    if approval_entry is None:
        raise CompletionError("D does not contain the fixed bootstrap approval")
    approval_bytes = approval_entry.content
    try:
        approval_obj = _BTO.decode_canonical_pf_jcs(approval_bytes)
        approval = _TQO.parse_d0_10_bootstrap_approval(
            approval_obj, "committed-D.bootstrap-approval"
        )
    except Exception as exc:
        raise CompletionError("D bootstrap approval is not canonical/valid") from exc
    if _canonical(approval_obj) != approval_bytes:
        raise CompletionError("D bootstrap approval bytes are not canonical")
    if approval.preCloseCandidate != pre.identity:
        raise CompletionError("D approval does not bind C")
    if approval.ledgerEvidenceId != LEDGER_EVIDENCE_ID:
        raise CompletionError("D approval reserved the wrong Ledger ID")

    planned_approval = (input_root / "bootstrap-approval.json").read_bytes()
    if planned_approval != approval_bytes:
        raise CompletionError("D approval differs from the protected C plan")

    patch_obj, patch_bytes = _read_canonical(
        input_root / "allowed-closeout-patch.json",
        4 * 1024 * 1024,
        "allowed closeout patch",
    )
    try:
        patch = _TQO.parse_allowed_closeout_patch(
            patch_obj, "allowed-closeout-patch"
        )
        patch_ref = _FIXTURE.allowed_closeout_patch_content_ref(patch)
    except Exception as exc:
        raise CompletionError("allowed closeout patch is invalid") from exc
    if patch_ref != approval.allowedCloseoutPatch:
        raise CompletionError("approval does not bind the supplied closeout patch")

    snapshot_obj, snapshot_bytes = _read_canonical(
        input_root / "revocation-snapshot.json",
        4 * 1024 * 1024,
        "revocation snapshot",
    )
    del snapshot_obj
    if plan_obj.get("revocationSnapshotSha256") != hashlib.sha256(
            snapshot_bytes).hexdigest():
        raise CompletionError("retained revocation snapshot differs from the C plan")

    file_set = _build_closeout_file_set(pre, close)
    changed_paths = tuple(path for path, _before, _after in file_set.changes)
    if changed_paths != patch.allowedPaths:
        raise CompletionError("actual C→D paths differ from the signed allowed paths")
    approval_change = next(
        (item for item in file_set.changes if item[0] == APPROVAL_PATH), None
    )
    if approval_change is None or approval_change[1] is not None:
        raise CompletionError("fixed approval path must be newly added by D")
    if approval_change[2] != _digest(approval_bytes):
        raise CompletionError("fixed approval path digest mismatch")

    return {
        "pre": pre,
        "close": close,
        "approval": approval,
        "approvalObj": approval_obj,
        "approvalBytes": approval_bytes,
        "patch": patch,
        "patchObj": patch_obj,
        "patchBytes": patch_bytes,
        "patchRef": patch_ref,
        "snapshotBytes": snapshot_bytes,
        "fileSet": file_set,
    }


def _receipt_bundle(
    runtime,
    state: dict[str, Any],
    policy,
    policy_ref: _BTO.ContentRef,
    policy_bytes: bytes,
    seeds: dict[str, bytes],
    instant: str,
) -> dict[str, Any]:
    artifacts = _C._build_artifacts(runtime)
    profile, pin = _C._build_profile_and_pin(
        runtime,
        policy_ref,
        artifacts,
        "d0-10-bootstrap-receipt",
        (),
        (),
        seeds,
    )
    profile_bytes = _canonical(_TQO.production_profile_to_wire(profile))
    pin_bytes = _canonical(_TQO.production_profile_pin_to_wire(pin))

    snapshot_ref = runtime._STORE.recompute_object_content_ref(
        runtime._STORE.REVOCATION_SNAPSHOT_KIND, state["snapshotBytes"]
    )
    if state["approval"].authorityPolicy != policy_ref:
        raise CompletionError("approval authority policy is no longer activated")
    if state["approval"].bootstrapGate.revocationSnapshot != snapshot_ref:
        raise CompletionError("approval snapshot does not equal the retained snapshot")

    file_set_wire = _FIXTURE.closeout_file_set_to_wire(state["fileSet"])
    file_set_bytes = _canonical(file_set_wire)
    file_set_ref = _FIXTURE.closeout_file_set_content_ref(state["fileSet"])
    closeout_diff = _FIXTURE.closeout_file_set_digest(state["fileSet"])
    approval_digest = _TQO.domain_digest(
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, state["approvalObj"]
    )

    receipt_obj = {
        "schema": "proof-forge.d0-10-bootstrap-receipt.v1",
        "id": "d0-10-bootstrap-receipt-d0-10",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "ruling": _TQO.normative_document_ref_to_wire(state["approval"].ruling),
        "preCloseCandidate": _candidate_wire(state["pre"].identity),
        "closeoutCandidate": _candidate_wire(state["close"].identity),
        "approvalDigest": _digest_wire(approval_digest),
        "allowedCloseoutPatch": _ref_wire(state["patchRef"]),
        "closeoutDiffDigest": _digest_wire(closeout_diff),
        "ledgerEvidenceId": LEDGER_EVIDENCE_ID,
        "authorityPolicy": _ref_wire(policy_ref),
        "revocationSnapshot": _ref_wire(snapshot_ref),
        "ledgerGrade": "bootstrap",
        "purpose": "d0-10-taskqual-one-time-bridge",
        "issuedAt": instant,
        "signatures": [],
    }
    receipt_obj = _C._sign(
        runtime,
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
        ROLE_AQS,
        seeds,
    )
    receipt_bytes = _canonical(receipt_obj)

    approval_ref = _TQO.recompute_typed_content_ref(
        state["approvalObj"]["schema"], state["approvalObj"]
    )
    members = [
        _C._member_wire(
            "pre-close-archive", "archive",
            _digest_wire(state["pre"].identity.archiveDigest),
            state["pre"].archive_bytes,
        ),
        _C._member_wire(
            "closeout-archive", "archive",
            _digest_wire(state["close"].identity.archiveDigest),
            state["close"].archive_bytes,
        ),
        _C._member_wire(
            "pre-close-commit-object", "git-object",
            state["pre"].identity.commit, state["pre"].commit_bytes,
        ),
        _C._member_wire(
            "closeout-commit-object", "git-object",
            state["close"].identity.commit, state["close"].commit_bytes,
        ),
        _C._member_wire(
            "bootstrap-approval", "typed-content",
            _ref_wire(approval_ref), state["approvalBytes"],
        ),
        _C._member_wire(
            "allowed-closeout-patch", "typed-content",
            _ref_wire(state["patchRef"]), state["patchBytes"],
        ),
        _C._member_wire(
            "closeout-file-set", "typed-content",
            _ref_wire(file_set_ref), file_set_bytes,
        ),
        _C._member_wire(
            "authority-policy", "typed-content",
            _ref_wire(policy_ref), policy_bytes,
        ),
        _C._member_wire(
            "revocation-snapshot", "typed-content",
            _ref_wire(snapshot_ref), state["snapshotBytes"],
        ),
        _C._member_wire(
            "production-profile", "typed-content",
            _ref_wire(_TQO.production_profile_content_ref(profile)),
            profile_bytes,
        ),
    ]
    members.sort(key=lambda item: item["role"])
    bundle_obj = {
        "schema": _TQO.BUNDLE_SCHEMA,
        "id": _TQO.OPERATION_BUNDLE_IDS["d0-10-bootstrap-receipt"],
        "version": "1.0.0",
        "operation": "d0-10-bootstrap-receipt",
        "verificationProfile": _TQO.production_profile_to_wire(profile),
        "expectedAuthorityPolicy": _ref_wire(policy_ref),
        "verificationInstant": instant,
        "implementationInvocationId": "d0-10-receipt-owner-0001",
        "members": members,
    }
    bundle_bytes = _canonical_large(bundle_obj)
    verified = _VERIFIER.verify_d0_10_bootstrap_receipt_v1(
        bundle_bytes, receipt_bytes
    )
    if isinstance(verified, _BTO.Rejected):
        raise CompletionError(
            "production receipt pure verifier rejected: " + verified.detail
        )
    if verified.authorityClass != "production-content-verified":
        raise CompletionError("receipt pure verifier returned the wrong authority class")
    try:
        receipt = _TQO.parse_d0_10_bootstrap_receipt(
            receipt_obj, "verified-bootstrap-receipt"
        )
    except Exception as exc:
        raise CompletionError("verified receipt cannot be re-parsed") from exc
    return {
        **state,
        "policy": policy,
        "policyRef": policy_ref,
        "policyBytes": policy_bytes,
        "artifacts": artifacts,
        "profile": profile,
        "profileBytes": profile_bytes,
        "pin": pin,
        "pinBytes": pin_bytes,
        "snapshotRef": snapshot_ref,
        "receiptObj": receipt_obj,
        "receipt": receipt,
        "receiptBytes": receipt_bytes,
        "receiptDigest": verified.receiptDigest,
        "fileSetBytes": file_set_bytes,
        "members": members,
        "bundleBytes": bundle_bytes,
        "instant": instant,
    }


def _completion_review(close_candidate) -> tuple[_TQO.IndependentReviewRefV1, bytes]:
    report = (
        "TASK-D0-10 single-maintainer external completion review\n\n"
        "Directive: single-maintainer-owner-waiver\n"
        "Review mode: owner self-review; this is not an independent review.\n"
        f"Closeout candidate D: {close_candidate.identity.commit}\n"
        "Blocking findings recorded by the owner: none.\n"
        "Boundary: bootstrap/development local ceremony; not formal or hermetic "
        "static custody evidence.\n"
    ).encode("utf-8")
    review = _TQO.IndependentReviewRefV1(
        reviewerId="davirain-owner-waiver",
        reviewerKind="human",
        invocationId="single-maintainer-owner-waiver-d0-10-completion",
        reportDigest=_TQO.domain_digest_raw(_TQO.DOMAIN_REVIEW_REPORT, report),
        reviewCommit=close_candidate.identity.commit,
        reviewLink=(
            "https://github.com/DaviRain-Su/proof_forge/commit/"
            + close_candidate.identity.commit
        ),
        decision="approved",
        findings=(),
    )
    return review, report


def _external_objects(runtime, data: dict[str, Any], seeds: dict[str, bytes]) -> dict[str, Any]:
    review, review_bytes = _completion_review(data["close"])
    completion_obj = {
        "schema": "proof-forge.governance-bootstrap-completion.v1",
        "id": "governance-bootstrap-completion-d0-10",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "rulingId": "GOV-TASKQUAL-BOOTSTRAP-001",
        "purpose": "d0-10-taskqual-one-time-bridge",
        "completionCandidate": _candidate_wire(data["close"].identity),
        "ruling": _TQO.normative_document_ref_to_wire(data["receipt"].ruling),
        "sourceClosure": {
            "path": RECEIPT_PATH,
            "digest": _digest_wire(_digest(data["receiptBytes"])),
        },
        "authorityPolicy": _ref_wire(data["policyRef"]),
        "independentReviews": [
            _TQO.independent_review_ref_to_wire(review)
        ],
        "signatures": [],
    }
    completion_obj = _C._sign(
        runtime,
        completion_obj,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
        ROLE_AQS,
        seeds,
    )
    completion_bytes = _canonical(completion_obj)
    _TQO.parse_governance_bootstrap_completion(
        completion_obj, "governance-bootstrap-completion"
    )

    ledger_obj = {
        "schema": "proof-forge.d0-10-receipt-ledger-projection.v1",
        "id": "d0-10-receipt-ledger-projection",
        "version": "1.0.0",
        "evidenceId": LEDGER_EVIDENCE_ID,
        "taskId": TASK_ID,
        "testId": TEST_ID,
        "grade": "bootstrap",
        "result": "passed",
        "approvalRef": {
            "id": "d0-10-bootstrap-approval",
            "digest": _digest_wire(data["receipt"].approvalDigest),
        },
        "receiptRef": {
            "id": data["receipt"].id,
            "digest": _digest_wire(data["receiptDigest"]),
        },
        "rulingRef": _TQO.normative_document_ref_to_wire(
            data["receipt"].ruling
        ),
    }
    ledger_bytes = _canonical(ledger_obj)
    _TQO.parse_d0_10_receipt_ledger_projection(
        ledger_obj, "receipt-ledger-projection"
    )
    return {
        **data,
        "completionObj": completion_obj,
        "completionBytes": completion_bytes,
        "completionReviewBytes": review_bytes,
        "ledgerObj": ledger_obj,
        "ledgerBytes": ledger_bytes,
        "ledgerDigest": _TQO.domain_digest(
            _TQO.DOMAIN_D0_10_RECEIPT_LEDGER_PROJECTION, ledger_obj
        ),
        "completionDigest": _TQO.domain_digest(
            _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION, completion_obj
        ),
    }


def _protected_receipt(runtime, data: dict[str, Any], seeds: dict[str, bytes]) -> bytes:
    operation = "d0-10-bootstrap-receipt"
    run_id = "d0-10-receipt-owner-0001"
    nonce = hashlib.sha256(run_id.encode("ascii")).hexdigest()
    isolation, isolation_ref = runtime._isolation_policy(run_id, nonce, 90)
    isolation_bytes = _canonical(isolation)
    service_seed = seeds["key-authority-store-service"]
    descriptor, descriptor_ref = runtime._descriptor(
        run_id,
        runtime._BTP.ed25519_public_key_from_seed(service_seed),
        data["artifacts"]["authorityStore"],
        data["artifacts"]["supervisor"],
        isolation_ref,
    )
    descriptor_bytes = _canonical(descriptor)
    head_sequence = 1
    head_digest = hashlib.sha256(
        b"pf.taskqual.d0-10-receipt-head.v1\x00" + data["snapshotBytes"]
    ).digest()
    handoff = {
        "schema": runtime._STORE.HANDOFF_SCHEMA,
        "id": f"task-qualification-protected-handoff-{run_id}",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "candidate": _candidate_wire(data["close"].identity),
        "authorityPolicy": _ref_wire(data["policyRef"]),
        "productionProfilePin": _ref_wire(
            _TQO.production_profile_pin_content_ref(data["pin"])
        ),
        "gateSetDigest": _digest_wire(data["profile"].gateSetDigest),
        "adapter": _TQO.verifier_identity_to_wire(
            data["artifacts"]["adapter"]
        ),
        "snapshotParser": _TQO.verifier_identity_to_wire(
            data["artifacts"]["snapshotParser"]
        ),
        "authorityStoreService": _ref_wire(descriptor_ref),
        "trustedClockService": _TQO.verifier_identity_to_wire(
            data["artifacts"]["trustedClock"]
        ),
        "revocationHead": {
            "headSequence": head_sequence,
            "headDigest": _digest_wire(_BTO.Digest("sha256", head_digest)),
        },
        "trustedInstant": data["instant"],
        "channels": dict(runtime.FIXED_FDS),
        "signatures": [],
    }
    handoff["signatures"] = runtime._sign_without_signatures_field(
        handoff,
        runtime._STORE.HANDOFF_STATEMENT_DOMAIN,
        runtime._STORE.HANDOFF_SIGNATURE_DOMAIN,
        ROLE_AQS,
        seeds,
    )
    handoff_bytes = _canonical(handoff)
    handoff_digest = runtime._STORE.domain_digest(
        runtime._STORE.HANDOFF_FULL_DOMAIN, handoff
    ).bytes
    clock = {
        "schema": runtime._STORE.CLOCK_OBSERVATION_SCHEMA,
        "id": "taskqualification-d0-10-receipt-clock-v1",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "trustedClockService": _TQO.verifier_identity_to_wire(
            data["artifacts"]["trustedClock"]
        ),
        "observedAt": data["instant"],
        "clockSourceDigest": _digest_wire(
            _digest(b"d0-10 local owner receipt clock")
        ),
        "signatures": [],
    }
    clock["signatures"] = runtime._sign_without_signatures_field(
        clock,
        runtime._STORE.CLOCK_STATEMENT_DOMAIN,
        runtime._STORE.CLOCK_SIGNATURE_DOMAIN,
        ROLE_AQS,
        seeds,
    )
    clock_bytes = _canonical(clock)

    entries = {
        member["role"]: bytes.fromhex(member["bytesHex"])
        for member in data["members"]
    }
    entries.update({
        "bootstrap-receipt": data["receiptBytes"],
        "production-profile-pin": data["pinBytes"],
        "live-handoff": handoff_bytes,
        "live-session": _canonical({
            "schema": "proof-forge.task-qualification-live-session.v1",
            "id": run_id,
        }),
        "trusted-clock-observation": clock_bytes,
        "current-revocation-snapshot": data["snapshotBytes"],
        "authority-store-service-descriptor": descriptor_bytes,
        "store-isolation-policy": isolation_bytes,
        "governance-bootstrap-completion": data["completionBytes"],
        "receipt-ledger-projection": data["ledgerBytes"],
    })
    for payload_map in data["artifacts"]["protectedPayloadMaps"]:
        entries.update(payload_map)
    provenance = {
        "schema": runtime._STORE.PROVENANCE_BUNDLE_SCHEMA,
        "id": "protected-taskqualification-provenance-d0-10-receipt",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "subjectDigest": _digest_wire(_digest(data["receiptBytes"])),
        "candidateArchiveSha256": _digest_wire(
            data["close"].identity.archiveDigest
        ),
        "entries": [
            {"role": role, "bytesHex": payload.hex()}
            for role, payload in sorted(entries.items())
        ],
    }
    provenance_bytes = _canonical_large(provenance)
    _TQO.parse_provenance_bundle(provenance, "d0-10-receipt-provenance")

    tpl = runtime._STORE.HandoffTuple(
        taskId=TASK_ID,
        operation=operation,
        runId=run_id,
        nonce=nonce,
        service=_ref_wire(descriptor_ref),
        handoffDigest=handoff_digest,
        headSequence=head_sequence,
        headDigest=head_digest,
    )
    objects = {
        "authority-policy": data["policyBytes"],
        "production-profile-pin": data["pinBytes"],
        "production-profile": data["profileBytes"],
        "adapter": _canonical(_TQO.verifier_identity_to_wire(
            data["artifacts"]["adapter"]
        )),
        "snapshot-parser": _canonical(_TQO.verifier_identity_to_wire(
            data["artifacts"]["snapshotParser"]
        )),
        "authority-store-service": descriptor_bytes,
        "trusted-clock-service": _canonical(_TQO.verifier_identity_to_wire(
            data["artifacts"]["trustedClock"]
        )),
        "revocation-snapshot": data["snapshotBytes"],
    }
    manifest = {
        "schema": runtime.QUALIFIED_SCHEMA,
        "operationBytesHex": operation.encode("ascii").hex(),
        "handoffBytesHex": handoff_bytes.hex(),
        **runtime.FIXED_FDS,
    }
    result = runtime._run_adapter_process(
        [sys.executable, "-I", "-S", str(runtime._HERE), "--adapter-once"],
        _canonical(manifest),
        {
            "policy": data["policyBytes"],
            "archive": data["close"].archive_bytes,
            "provenance": provenance_bytes,
            "clock": clock_bytes,
        },
        tpl,
        data["profile"].gateSetDigest.bytes,
        objects,
        service_seed,
        {key: seeds[key] for key in ROLE_AQS},
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise CompletionError("protected receipt adapter rejected: " + detail)
    acceptance = result.stdout
    try:
        wire = _BTO.decode_canonical_pf_jcs(acceptance)
    except Exception as exc:
        raise CompletionError("protected receipt acceptance is not canonical") from exc
    if (
        wire.get("operation") != operation
        or wire.get("authorityClass") != "production-candidate-bound"
        or wire.get("closeoutCandidate") != _candidate_wire(data["close"].identity)
        or wire.get("ledgerProjectionDigest") != _digest_wire(data["ledgerDigest"])
        or wire.get("governanceCompletionDigest")
        != _digest_wire(data["completionDigest"])
    ):
        raise CompletionError("protected receipt acceptance join mismatch")
    return acceptance


def _replace_checkpoint(source: bytes, field: str, value: str) -> bytes:
    return _C._replace_table_value(source, field, value)


def _append_ledger_row(source: bytes, receipt_digest: _BTO.Digest) -> bytes:
    text = source.decode("utf-8")
    if LEDGER_EVIDENCE_ID in text:
        raise CompletionError("reserved Ledger ID already exists before P")
    row = (
        f"| {LEDGER_EVIDENCE_ID} | {TASK_ID} | {TEST_ID} | bootstrap | "
        f"protected receipt {_digest_wire(receipt_digest)} | passed | "
        "GOV-TASKQUAL-BOOTSTRAP-001 one-time receipt projection |"
    )
    marker = "\n\nLean cache consumer"
    if marker not in text:
        raise CompletionError("Evidence Ledger table terminator not found")
    return text.replace(marker, "\n" + row + marker, 1).encode("utf-8")


def _publication_files(data: dict[str, Any], acceptance: bytes) -> dict[str, bytes]:
    close = data["close"]
    pre = data["pre"]
    archive = close.archive_projection.path_map
    freeze_bytes = archive[
        "docs/governance/task-freeze-packages/TASK-D0-10.json"
    ].content
    approval_bytes = archive[APPROVAL_PATH].content
    attest = {
        "schemaVersion": 1,
        "taskId": TASK_ID,
        "kind": "d0-10-taskqual-one-time-bridge-closure",
        "ruling": "GOV-TASKQUAL-BOOTSTRAP-001",
        "freezePackage": "docs/governance/task-freeze-packages/TASK-D0-10.json",
        "freezePackageSha256": hashlib.sha256(freeze_bytes).hexdigest(),
        "bootstrapApproval": APPROVAL_PATH,
        "bootstrapApprovalSha256": hashlib.sha256(approval_bytes).hexdigest(),
        "bootstrapReceipt": RECEIPT_PATH,
        "bootstrapReceiptSha256": hashlib.sha256(data["receiptBytes"]).hexdigest(),
        "governanceBootstrapCompletion": COMPLETION_PATH,
        "governanceBootstrapCompletionSha256": hashlib.sha256(
            data["completionBytes"]
        ).hexdigest(),
        "ledgerProjection": LEDGER_PROJECTION_PATH,
        "ledgerProjectionSha256": hashlib.sha256(data["ledgerBytes"]).hexdigest(),
        "protectedReceiptAcceptanceSha256": hashlib.sha256(acceptance).hexdigest(),
        "docsCheckCommand": "/usr/bin/python3 -I -S scripts/docs_check.py --root .",
        "notes": (
            "TASK-D0-10 external one-time receipt accepted under the activated "
            "production policy and mirrored by optional P; single-maintainer-owner-waiver "
            "is owner self-review, not independent review; local Python ceremony is "
            "bootstrap/development and not formal or hermetic evidence or complete "
            "static U/P/A durable custody."
        ),
    }

    agents = archive["AGENTS.md"].content
    agents = _replace_checkpoint(
        agents,
        "Formal milestone",
        "**D0：10/10 done**；`TASK-D0-10` one-time bootstrap receipt已完成，"
        "不声称formal/hermetic static custody；D1尚未自动激活",
    )
    agents = _replace_checkpoint(
        agents,
        "Active task",
        "无（D0已收口；尚未激活D1任务）",
    )
    agents = _replace_checkpoint(
        agents,
        "D0-10 candidate",
        f"C `{pre.identity.commit}`；direct-child D `{close.identity.commit}`；"
        f"external protected receipt `{_digest_wire(data['receiptDigest'])}`",
    )
    agents = _replace_checkpoint(
        agents,
        "Active development slice",
        "无；D0 external receipt/GBC/Ledger projection已完成并由P镜像",
    )
    agents = _replace_checkpoint(
        agents,
        "Next development slice",
        "未冻结；继续只读审计`ProgramItemV1` decoder residual并选择单一slice，"
        "不得由checkpoint自动递增任务",
    )

    ledger = _append_ledger_row(
        archive["docs/traceability/evidence-ledger.md"].content,
        data["receiptDigest"],
    )
    implementation = archive["docs/06-implementation-log.md"].content.rstrip(b"\n")
    implementation += (
        f"\n\n## 2026-07-24 — TASK-D0-10 external receipt and D0 closeout\n\n"
        f"- Candidate chain：C `{pre.identity.commit}` → unique direct-child D "
        f"`{close.identity.commit}`；D diff与signed allowed patch exact。\n"
        f"- External objects：receipt `{hashlib.sha256(data['receiptBytes']).hexdigest()}`、"
        f"GovernanceBootstrapCompletion `{hashlib.sha256(data['completionBytes']).hexdigest()}`、"
        f"Ledger projection `{hashlib.sha256(data['ledgerBytes']).hexdigest()}`。\n"
        f"- Protected acceptance：SHA-256 `{hashlib.sha256(acceptance).hexdigest()}`；"
        f"reserved `{LEDGER_EVIDENCE_ID}`按bootstrap projection镜像。\n"
        "- Review：`single-maintainer-owner-waiver`，owner self-review；不声称independent review。\n"
        "- Boundary：本地Python seqpacket ceremony为bootstrap/development路径，不是完整static "
        "U/P/A custody或durable nonce store；本关闭不是formal/hermetic evidence。\n"
    ).encode("utf-8")

    return {
        "AGENTS.md": agents,
        "docs/06-implementation-log.md": implementation,
        "docs/traceability/evidence-ledger.md": ledger,
        RECEIPT_PATH: data["receiptBytes"],
        COMPLETION_PATH: data["completionBytes"],
        LEDGER_PROJECTION_PATH: data["ledgerBytes"],
        ATTEST_PATH: _canonical(attest),
    }


def complete_closeout(
    runtime,
    seed_root: Path,
    input_root: Path,
    output_root: Path,
) -> int:
    """Verify committed D, issue external objects, and emit optional-P files."""
    policy_bytes = _C.POLICY_PATH.read_bytes()
    policy, policy_ref = _BTO.parse_bootstrap_authority_policy(policy_bytes)
    seeds = runtime._load_production_seeds(seed_root, policy)
    state = _load_committed_d(input_root)
    instant = _utc_now()
    data = _receipt_bundle(
        runtime, state, policy, policy_ref, policy_bytes, seeds, instant
    )
    data = _external_objects(runtime, data, seeds)
    acceptance = _protected_receipt(runtime, data, seeds)
    publication = _publication_files(data, acceptance)

    output_root.mkdir(parents=True, exist_ok=True)
    _C._write_public(output_root / "bootstrap-receipt.json", data["receiptBytes"])
    _C._write_public(
        output_root / "governance-bootstrap-completion.json",
        data["completionBytes"],
    )
    _C._write_public(output_root / "ledger-projection.json", data["ledgerBytes"])
    _C._write_public(
        output_root / "protected-receipt-acceptance.json", acceptance
    )
    _C._write_public(
        output_root / "completion-owner-waiver-review.txt",
        data["completionReviewBytes"],
    )
    for path, payload in publication.items():
        _C._write_public(output_root / "publication" / path, payload)
    metadata = {
        "schema": "proof-forge.task-qualification-completion-plan.v1",
        "taskId": TASK_ID,
        "preCloseCandidate": _candidate_wire(data["pre"].identity),
        "closeoutCandidate": _candidate_wire(data["close"].identity),
        "receiptDigest": _digest_wire(data["receiptDigest"]),
        "ledgerProjectionDigest": _digest_wire(data["ledgerDigest"]),
        "governanceCompletionDigest": _digest_wire(data["completionDigest"]),
        "protectedAcceptanceSha256": hashlib.sha256(acceptance).hexdigest(),
        "publicationPaths": sorted(publication),
        "authority": "bootstrap-development; not formal or hermetic static custody",
    }
    _C._write_public(output_root / "completion-plan.json", _canonical(metadata))
    print(
        "TASK-D0-10 external completion: PASS; C="
        + data["pre"].identity.commit
        + "; D="
        + data["close"].identity.commit
        + "; receipt="
        + metadata["receiptDigest"]
        + "; protectedAcceptanceSha256="
        + metadata["protectedAcceptanceSha256"]
    )
    return 0
