#!/usr/bin/env python3
"""TST-BOOTSTRAP-001 executable rehearsal harness (development slice).

This module wires the five previous slices into one end-to-end, pre-activation
rehearsal, entirely inside a fixture namespace that is disjoint from any
production lookup tuple: the dev authority policy uses test-only RFC 8032
principals, and runId/nonce/candidate/handoff are fixture values produced per
run.  The rehearsal

1. starts the authority-store service with the fixture policy on a temporary
   Unix socket;
2. publishes and read-back-closes the signed RequiredTestSet and the formal
   catalog approval;
3. produces, publishes, and read-back-closes each task approval and verifier
   receipt in D0-01..06 topological order, proving the closure gate that a
   task only closes when its dependencies' authenticated receipt refs exist
   (D0-01 closes alone; D0-02 requires D0-01);
4. publishes the six-item BootstrapApprovalSet;
5. produces an EligibleStage0HandoffV1 (eligible fixture observation), hands
   the four channel fds to a bubblewrap-contained consumer child which runs
   ``verify_inherited_channels``, adopts the pre-opened authority-store
   channel fd (replaying the standard client hello validation over the
   inherited socket), proves the activation lookup tuple is absent
   (pre-activation proof), publishes and read-back-closes the aggregate
   activation receipt over that channel, and finally runs the complete
   ``parse_bootstrap_approval_verifier_receipt`` chain;
6. returns a typed report.

Module-instance discipline: bootstrap objects and the store run on the
authority-store module's producer/consumer chain ("chain A"); the handoff
producer and ``verify_inherited_channels`` run on the stage0_handoff module's
own chain ("chain B").  The chains meet only through canonical bytes and
primitive digest values, never through shared class objects.

The service side of the handoff socketpair is driven through the store
server's connection handler in this local model; upstream connect-by-fd
support and Stage-0 integration remain follow-ups.  Nothing here reads,
requires, or produces a real activation: the fixture activation receipt
never satisfies the current D0 closure.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import socket
import sys
import threading
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Dict, NoReturn, Optional, Tuple


def _load_sibling(module_name: str, file_name: str) -> ModuleType:
    """Load an exact sibling module without a sys.path authority seam."""
    module_path = Path(__file__).resolve(strict=True)
    target_path = module_path.with_name(file_name)
    spec = importlib.util.spec_from_file_location(module_name, target_path)
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError(f"exact sibling loader is unavailable for {file_name}")
    if Path(spec.origin).resolve(strict=True) != target_path.resolve(strict=True):
        raise ImportError(f"exact sibling origin changed for {file_name}")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


_STORE = _load_sibling(
    "proof_forge_authority_store_for_acceptance", "authority_store.py"
)
_HANDOFF = _load_sibling(
    "proof_forge_stage0_handoff_for_acceptance", "stage0_handoff.py"
)
_CONTAINMENT = _load_sibling(
    "proof_forge_stage0_containment_for_acceptance", "stage0_containment.py"
)
_PRODUCER = _STORE._PRODUCER
_CONSUMER = _STORE._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef

D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
_TOPOLOGICAL_TASK_IDS = (
    "TASK-D0-01",
    "TASK-D0-02",
    "TASK-D0-03",
    "TASK-D0-05",
    "TASK-D0-06",
    "TASK-D0-04",
)
EXPECTED_PUBLISHED_OBJECTS = 16
HANDOFF_SCHEMA = "proof-forge.eligible-stage0-handoff.v1"


class BootstrapAcceptanceError(Exception):
    """Stable rehearsal failure; store/object errors keep their own types."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise BootstrapAcceptanceError(code, detail)


def _state(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACCEPT-STATE", detail)


def _closure(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACCEPT-CLOSURE", detail)


def _child(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACCEPT-CHILD", detail)


@dataclass(frozen=True)
class RehearsalBase:
    """Run-independent fixture authority objects and raw materials."""

    policyBytes: bytes
    policyRef: ContentRef
    requiredBytes: bytes
    requiredRef: ContentRef
    phase5Snapshot: object
    catalogBytes: bytes
    catalogApprovalBytes: bytes
    candidate: object
    candidateCommit: str
    candidateTreeObjectId: str
    candidateArchiveDigestBytes: bytes
    candidateDigestBytes: bytes
    archiveBytes: bytes
    manifestBytes: bytes
    descriptorWire: dict
    descriptorRef: ContentRef
    descriptorDigestBytes: bytes
    serviceSeed: bytes
    observationId: str
    observationVersion: str
    observationBytes: bytes
    profileId: str
    profileVersion: str
    profileBytes: bytes
    tcbDigests: Tuple[bytes, bytes, bytes, bytes]


@dataclass(frozen=True)
class RehearsalRun:
    """Per-run objects bound to one freshly produced handoff."""

    runId: str
    nonce: str
    handoffBytes: bytes
    handoffRef: ContentRef
    channels: object
    approvalBytes: Dict[str, bytes]
    receiptBytes: Dict[str, bytes]
    setBytes: bytes
    setRef: ContentRef
    activationBytes: bytes
    activationRef: ContentRef
    activationKey: bytes


@dataclass(frozen=True)
class BootstrapRehearsalReport:
    activationReceiptId: str
    activationReceiptDigestHex: str
    storeHeadSequence: int
    publishedObjects: int
    dependencyGateFailuresProven: int
    containmentExitCode: int
    childStdout: bytes


D0_GRAPH_ROWS = {
    "TASK-D0-01": {
        "dependencies": (),
        "prerequisites": ("PHASE-1", "PHASE-2", "PHASE-3"),
        "testIds": ("TST-DOC-001",),
        "evidenceIds": ("EV-20260717-0001",),
        "signers": (
            ("key-architecture", "architecture"),
            ("key-quality", "quality"),
        ),
    },
    "TASK-D0-02": {
        "dependencies": ("TASK-D0-01",),
        "prerequisites": (),
        "testIds": ("TST-ISO-001",),
        "evidenceIds": ("EV-20260717-0002",),
        "signers": (
            ("key-architecture", "architecture"),
            ("key-quality", "quality"),
        ),
    },
    "TASK-D0-03": {
        "dependencies": ("TASK-D0-01", "TASK-D0-02"),
        "prerequisites": (),
        "testIds": (
            "TST-EVIDENCE-001",
            "TST-HOST-001",
            "TST-TOOL-001",
        ),
        "evidenceIds": ("EV-20260717-0003", "EV-20260717-0004"),
        "signers": (
            ("key-quality", "quality"),
            ("key-security", "security"),
        ),
    },
    "TASK-D0-04": {
        "dependencies": (
            "TASK-D0-02",
            "TASK-D0-03",
            "TASK-D0-05",
            "TASK-D0-06",
        ),
        "prerequisites": (),
        "testIds": ("TST-BOOTSTRAP-001",),
        "evidenceIds": ("EV-20260717-0005",),
        "signers": (
            ("key-quality", "quality"),
            ("key-release", "release"),
            ("key-security", "security"),
        ),
    },
    "TASK-D0-05": {
        "dependencies": ("TASK-D0-03",),
        "prerequisites": (),
        "testIds": ("TST-SBOM-001",),
        "evidenceIds": ("EV-20260717-0006",),
        "signers": (
            ("key-quality", "quality"),
            ("key-security", "security"),
        ),
    },
    "TASK-D0-06": {
        "dependencies": ("TASK-D0-01", "TASK-D0-02"),
        "prerequisites": (),
        "testIds": ("TST-COMMON-001",),
        "evidenceIds": ("EV-20260717-0007",),
        "signers": (
            ("key-architecture", "architecture"),
            ("key-quality", "quality"),
        ),
    },
}


def _digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def _content_ref_wire(ref: ContentRef) -> dict:
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": _digest_text(ref.digest.bytes),
    }


def build_rehearsal_base(
    *,
    namespace_id: str,
    descriptor_id: str,
    descriptor_version: str,
    service_seed: bytes,
    executable_digest_bytes: bytes,
    observation_bytes: bytes,
    profile_bytes: bytes,
    seeds_by_key_id: Dict[str, bytes],
    observation_id: str = "eligible-host-observation",
    observation_version: str = "1.0.0",
    profile_id: str = "eligible-host-profile",
    profile_version: str = "1.0.0",
) -> RehearsalBase:
    """Build the run-independent fixture authority chain (test-only keys)."""
    producer = _PRODUCER
    consumer = _CONSUMER
    descriptor_wire = {
        "schema": "proof-forge.authority-store-service.v1",
        "id": descriptor_id,
        "version": descriptor_version,
        "protocol": "pf.authority-store.rpc.v1",
        "serviceExecutableDigest": _digest_text(executable_digest_bytes),
        "servicePublicKey": producer.ed25519_public_key_from_seed(
            service_seed
        ).hex(),
        "namespaceId": namespace_id,
        "maximumFrameBytes": 4194304,
    }
    descriptor_digest = hashlib.sha256(
        b"pf.authority-store-service.v1\x00"
        + consumer.canonical_pf_jcs(descriptor_wire)
    ).digest()
    descriptor_ref = ContentRef(
        descriptor_wire["schema"],
        descriptor_wire["id"],
        descriptor_wire["version"],
        Digest("sha256", descriptor_digest),
    )
    principals = tuple(
        consumer.BootstrapAuthorityPrincipalV1(
            principalId=f"principal-{role}",
            keyId=f"key-{role}",
            publicKey=producer.ed25519_public_key_from_seed(
                seeds_by_key_id[f"key-{role}"]
            ),
            roles=(role,),
        )
        for role in ("architecture", "quality", "release", "security")
    )
    policy_bytes = producer.produce_bootstrap_authority_policy(
        id="bootstrap-acceptance-authority",
        version="1.0.0",
        principals=principals,
        taskRules=tuple(
            consumer.BootstrapAuthorityTaskRuleV1(
                taskId=task_id,
                rule=consumer.ApprovalRuleV1(roles, minimum),
            )
            for task_id, roles, minimum in (
                ("TASK-D0-01", ("architecture", "quality"), 2),
                ("TASK-D0-02", ("architecture", "quality"), 2),
                ("TASK-D0-03", ("quality", "security"), 2),
                ("TASK-D0-04", ("quality", "security", "release"), 3),
                ("TASK-D0-05", ("quality", "security"), 2),
                ("TASK-D0-06", ("architecture", "quality"), 2),
            )
        ),
        requiredTestSetRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        formalCatalogRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        bootstrapSetRule=consumer.ApprovalRuleV1(
            ("quality", "security", "release"), 3
        ),
        sessionContainmentRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        freshnessAuthorityRule=consumer.ApprovalRuleV1(("quality", "release"), 2),
        privateScanRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        privateScanPolicy=ContentRef(
            "proof-forge.private-scan-policy.v1",
            "bootstrap-acceptance-private-scan",
            "1.0.0",
            Digest("sha256", bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=descriptor_ref,
        verifier=consumer.BootstrapAuthorityVerifierV1(
            id="bootstrap-acceptance-verifier",
            executableDigest=Digest("sha256", bytes.fromhex("43" * 32)),
            receiptKeyId="key-verifier-receipt",
            receiptPublicKey=producer.ed25519_public_key_from_seed(
                seeds_by_key_id["key-verifier-receipt"]
            ),
        ),
    )
    policy, policy_ref = consumer.parse_bootstrap_authority_policy(policy_bytes)

    required_ids = tuple(sorted({
        test_id for row in D0_GRAPH_ROWS.values() for test_id in row["testIds"]
    }))
    snapshot_bytes = _phase5_snapshot_bytes(required_ids)
    phase5_snapshot = consumer.BootstrapDocumentSnapshotV1(
        id="PHASE-5",
        path="docs/05-test-spec.md",
        bytes=snapshot_bytes,
    )
    document_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00" + snapshot_bytes
    ).digest()
    required_bytes = producer.produce_required_test_set(
        id="bootstrap-acceptance-required-tests",
        version="1.0.0",
        phase5Document=consumer.NormativeDocumentRefV1(
            id="PHASE-5",
            contentDigest=Digest("sha256", document_digest),
            status="accepted",
            reviewCommit="a" * 40,
            reviewLink="https://review.example/phase-5:443/approval",
            approvedAt="2026-07-16",
            approvers=("principal-quality", "principal-security"),
        ),
        authorityPolicy=policy_ref,
        requiredTestIds=required_ids,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    required_ref = ContentRef(
        "proof-forge.required-test-set.v1",
        "bootstrap-acceptance-required-tests",
        "1.0.0",
        Digest(
            "sha256",
            hashlib.sha256(
                b"pf.required-test-set.v1\x00" + required_bytes
            ).digest(),
        ),
    )

    archive_bytes = b"bootstrap-acceptance candidate archive v1\n" * 64
    archive_digest = hashlib.sha256(archive_bytes).digest()
    candidate_statement = {
        "commit": "a" * 40,
        "treeObjectId": "b" * 40,
        "archiveDigest": _digest_text(archive_digest),
    }
    candidate_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00"
        + consumer.canonical_pf_jcs(candidate_statement)
    ).digest()
    candidate = consumer.parse_candidate_identity({
        **candidate_statement,
        "digest": _digest_text(candidate_digest),
    })

    manifest_bytes = (
        b'{"schema":"proof-forge.bootstrap-evidence-root-manifest.v1",'
        b'"taskId":"TASK-D0-04"}\n'
    )
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "bootstrap-acceptance-formal-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": _content_ref_wire(required_ref),
        "locks": {
            field: f"{0x10 + index:02x}" * 32
            for index, field in enumerate((
                "hostBootstrapSha256",
                "hostProfileLockSha256",
                "toolchainLockSha256",
                "stage0LauncherSha256",
                "stage0VerifierSha256",
                "sandboxEngineSha256",
                "sandboxRendererSha256",
                "sandboxLauncherSha256",
                "sandboxProbeWrapperSha256",
                "evidenceValidatorSha256",
                "evidenceSchemaCoreSha256",
                "finalizerSha256",
            ))
        },
        "gates": [
            {
                "id": "bootstrap-acceptance-gate",
                "taskId": "TASK-D0-03",
                "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
            }
        ],
    }
    catalog_bytes = consumer.canonical_pf_jcs(catalog_wire)
    catalog_ref = consumer.GateCatalogRefV1(
        "proof-forge.gate-catalog.v1",
        catalog_wire["id"],
        catalog_wire["version"],
        hashlib.sha256(catalog_bytes).hexdigest(),
        hashlib.sha256(b"pf.gate-catalog.v1\x00" + catalog_bytes).hexdigest(),
    )
    catalog_approval_bytes = producer.produce_formal_gate_catalog_approval(
        id="bootstrap-acceptance-catalog-approval",
        version="1.0.0",
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        catalog=catalog_ref,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    return RehearsalBase(
        policyBytes=policy_bytes,
        policyRef=policy_ref,
        requiredBytes=required_bytes,
        requiredRef=required_ref,
        phase5Snapshot=phase5_snapshot,
        catalogBytes=catalog_bytes,
        catalogApprovalBytes=catalog_approval_bytes,
        candidate=candidate,
        candidateCommit=candidate.commit,
        candidateTreeObjectId=candidate.treeObjectId,
        candidateArchiveDigestBytes=archive_digest,
        candidateDigestBytes=candidate_digest,
        archiveBytes=archive_bytes,
        manifestBytes=manifest_bytes,
        descriptorWire=descriptor_wire,
        descriptorRef=descriptor_ref,
        descriptorDigestBytes=descriptor_digest,
        serviceSeed=service_seed,
        observationId=observation_id,
        observationVersion=observation_version,
        observationBytes=observation_bytes,
        profileId=profile_id,
        profileVersion=profile_version,
        profileBytes=profile_bytes,
        tcbDigests=(
            bytes.fromhex("73" * 32),
            policy.verifier.executableDigest.bytes,
            bytes.fromhex("74" * 32),
            bytes.fromhex("75" * 32),
        ),
    )


_FROZEN_PHASE5_A0_IDS = tuple(f"TST-A0-{index:03d}" for index in range(1, 21))
_PHASE5_FRONTMATTER = {
    "id": "PHASE-5",
    "title": "Synthetic Phase 5 acceptance",
    "status": "accepted",
    "owner": "quality",
    "updated": "2026-07-16",
    "normative": "true",
    "approvers": "principal-quality, principal-security",
    "approvedAt": "2026-07-16",
    "reviewCommit": "a" * 40,
    "reviewLink": "https://review.example/phase-5:443/approval",
    "openFindings": "none",
}


def _phase5_snapshot_bytes(required_ids: Tuple[str, ...]) -> bytes:
    ids = tuple(reversed(required_ids)) + tuple(reversed(_FROZEN_PHASE5_A0_IDS))
    lines = ["---"]
    lines.extend(f"{key}: {value}" for key, value in _PHASE5_FRONTMATTER.items())
    lines.extend((
        "---",
        "# Phase 5 synthetic authority fixture",
        "",
        "## 完整 Test ID Catalog",
        "",
        "| ID | 测试对象 |",
        "|---|---|",
    ))
    lines.extend(f"| {test_id} | fixture for {test_id} |" for test_id in ids)
    lines.extend((
        "",
        "### Phase 1 required-set 分母",
        "",
        "Synthetic denominator prose.",
    ))
    return ("\n".join(lines) + "\n").encode("utf-8")


def produce_run_handoff(
    base: RehearsalBase,
    *,
    handoff_id: str,
    handoff_version: str,
    run_id: str,
    policy_path: str,
    archive_path: str,
    manifest_path: str,
):
    """Produce this run's handoff via the stage0_handoff module (chain B)."""
    handoff_module = _HANDOFF

    def digest_b(raw: bytes) -> object:
        return handoff_module.Digest("sha256", raw)

    produced = handoff_module.produce_stage0_handoff(
        handoff_id=handoff_id,
        handoff_version=handoff_version,
        run_id=run_id,
        candidate=handoff_module.CandidateIdentity(
            base.candidateCommit,
            base.candidateTreeObjectId,
            digest_b(base.candidateArchiveDigestBytes),
            digest_b(base.candidateDigestBytes),
        ),
        candidate_archive_path=archive_path,
        authority_policy_path=policy_path,
        authority_store_descriptor=handoff_module.ContentRef(
            base.descriptorRef.schema,
            base.descriptorRef.id,
            base.descriptorRef.version,
            digest_b(base.descriptorDigestBytes),
        ),
        evidence_root_manifest_path=manifest_path,
        host_observation=handoff_module.Stage0HostObservationV1(
            id=base.observationId,
            version=base.observationVersion,
            bytes=base.observationBytes,
        ),
        host_profile=handoff_module.Stage0HostProfileV1(
            id=base.profileId,
            version=base.profileVersion,
            bytes=base.profileBytes,
        ),
        tcb=handoff_module.EligibleStage0TcbV1(
            digest_b(base.tcbDigests[0]),
            digest_b(base.tcbDigests[1]),
            digest_b(base.tcbDigests[2]),
            digest_b(base.tcbDigests[3]),
        ),
        environment=handoff_module.EligibleStage0EnvironmentV1(
            "env-i", "/var/empty", "/usr/bin:/bin", "C", "UTC", "deny-default"
        ),
    )
    return produced


def produce_run_objects(
    base: RehearsalBase,
    produced_handoff,
    *,
    run_id: str,
    nonce: str,
    seeds_by_key_id: Dict[str, bytes],
) -> RehearsalRun:
    """Produce this run's approvals, receipts, set, and activation receipt."""
    producer = _PRODUCER
    consumer = _CONSUMER
    handoff_ref = ContentRef(
        HANDOFF_SCHEMA,
        produced_handoff.handoffRef.id,
        produced_handoff.handoffRef.version,
        Digest("sha256", produced_handoff.handoffDigest.bytes),
    )
    policy_ref = base.policyRef
    required_ref = base.requiredRef
    candidate = base.candidate
    built: Dict[str, Dict[str, object]] = {}
    phase4_ref = _normative_ref("PHASE-4", candidate.commit)
    prerequisite_refs = {
        identifier: _normative_ref(identifier, candidate.commit)
        for identifier in ("PHASE-1", "PHASE-2", "PHASE-3")
    }
    for task_id in _TOPOLOGICAL_TASK_IDS:
        row = D0_GRAPH_ROWS[task_id]
        task_number = int(task_id[-2:])
        dependency_refs = tuple(
            built[dependency]["receiptRef"]
            for dependency in row["dependencies"]
        )
        approval_bytes = producer.produce_task_approval(
            taskId=task_id,
            candidate=candidate,
            taskBreakdown=phase4_ref,
            requiredTestSet=required_ref,
            testIds=row["testIds"],
            evidence=tuple(
                consumer.EvidenceRef(
                    id=evidence_id,
                    digest=Digest(
                        "sha256", bytes([0x60 + task_number]) * 32
                    ),
                )
                for evidence_id in row["evidenceIds"]
            ),
            dependencyCompletions=dependency_refs,
            prerequisiteDocuments=tuple(
                prerequisite_refs[document_id]
                for document_id in row["prerequisites"]
            ),
            authorityPolicy=policy_ref,
            stage0Handoff=handoff_ref,
            independentReviews=tuple(
                consumer.IndependentReviewRefV1(
                    keyId=key_id,
                    role=role,
                    reviewCommit=candidate.commit,
                    reviewLink=(
                        f"https://review.example/{task_id.lower()}/{key_id}"
                    ),
                    reportDigest=Digest(
                        "sha256",
                        hashlib.sha256(
                            b"pf.independent-review-report.v1\x00"
                            + f"approved review by {task_id}:{key_id}\n".encode(
                                "ascii"
                            )
                        ).digest(),
                    ),
                    decision="approved",
                )
                for key_id, role in row["signers"]
            ),
            signers=tuple(
                (key_id, seeds_by_key_id[key_id])
                for key_id, _ in row["signers"]
            ),
        )
        approval_ref = consumer.TaskApprovalRefV1(
            task_id,
            Digest(
                "sha256",
                hashlib.sha256(
                    b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
                ).digest(),
            ),
        )
        receipt_bytes = producer.produce_bootstrap_task_verifier_receipt(
            id=f"BTV-20260717-{task_number:04d}",
            taskId=task_id,
            candidate=candidate,
            authorityPolicy=policy_ref,
            requiredTestSet=required_ref,
            taskApproval=approval_ref,
            stage0Handoff=handoff_ref,
            dependencyCompletions=dependency_refs,
            verifierDigest=Digest("sha256", base.tcbDigests[1]),
            signer=(
                "key-verifier-receipt",
                seeds_by_key_id["key-verifier-receipt"],
            ),
        )
        receipt_ref = consumer.BootstrapTaskVerifierReceiptRefV1(
            task_id,
            f"BTV-20260717-{task_number:04d}",
            Digest(
                "sha256",
                hashlib.sha256(
                    b"pf.bootstrap-task-verifier-receipt.v1\x00"
                    + receipt_bytes
                ).digest(),
            ),
        )
        built[task_id] = {
            "approvalBytes": approval_bytes,
            "approvalRef": approval_ref,
            "receiptBytes": receipt_bytes,
            "receiptRef": receipt_ref,
        }

    set_bytes = producer.produce_bootstrap_approval_set(
        id="bootstrap-acceptance-approval-set",
        version="1.0.0",
        candidate=candidate,
        authorityPolicy=policy_ref,
        taskBreakdown=phase4_ref,
        requiredTestSet=required_ref,
        stage0Handoff=handoff_ref,
        taskApprovals=tuple(
            consumer.parse_task_approval(
                built[task_id]["approvalBytes"],
                base.requiredBytes,
                base.policyBytes,
                base.phase5Snapshot,
            )[0]
            for task_id in D0_TASK_IDS
        ),
        taskReceipts=tuple(built[task_id]["receiptRef"] for task_id in D0_TASK_IDS),
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-release", seeds_by_key_id["key-release"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
    )
    set_ref = ContentRef(
        "proof-forge.bootstrap-approval-set.v1",
        "bootstrap-acceptance-approval-set",
        "1.0.0",
        Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-approval-set.v1\x00" + set_bytes
            ).digest(),
        ),
    )
    activation_bytes = producer.produce_bootstrap_approval_verifier_receipt(
        id="BAV-20260718-0001",
        candidate=candidate,
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        approvalSet=set_ref,
        stage0Handoff=handoff_ref,
        verifierDigest=Digest("sha256", base.tcbDigests[1]),
        taskApprovals=tuple(built[task_id]["approvalRef"] for task_id in D0_TASK_IDS),
        taskReceipts=tuple(built[task_id]["receiptRef"] for task_id in D0_TASK_IDS),
        signer=(
            "key-verifier-receipt",
            seeds_by_key_id["key-verifier-receipt"],
        ),
    )
    activation_ref = ContentRef(
        "proof-forge.bootstrap-approval-verifier-receipt.v1",
        "BAV-20260718-0001",
        "1.0.0",
        Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-approval-verifier-receipt.v1\x00"
                + activation_bytes
            ).digest(),
        ),
    )
    activation_key = _STORE.derive_lookup_key(
        _STORE.VERIFIER_RECEIPT_SCHEMA, activation_bytes
    )
    return RehearsalRun(
        runId=run_id,
        nonce=nonce,
        handoffBytes=produced_handoff.handoffBytes,
        handoffRef=handoff_ref,
        channels=produced_handoff.channels,
        approvalBytes={
            task_id: built[task_id]["approvalBytes"] for task_id in D0_TASK_IDS
        },
        receiptBytes={
            task_id: built[task_id]["receiptBytes"] for task_id in D0_TASK_IDS
        },
        setBytes=set_bytes,
        setRef=set_ref,
        activationBytes=activation_bytes,
        activationRef=activation_ref,
        activationKey=activation_key,
    )


def _normative_ref(identifier: str, review_commit: str) -> object:
    consumer = _CONSUMER
    raw_bytes = f"synthetic normative document {identifier}\n".encode("ascii")
    content_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00"
        + identifier.encode("ascii")
        + b"\x00"
        + raw_bytes
    ).digest()
    return consumer.NormativeDocumentRefV1(
        id=identifier,
        contentDigest=Digest("sha256", content_digest),
        status="accepted",
        reviewCommit=review_commit,
        reviewLink=f"https://review.example/{identifier.lower()}",
        approvedAt="2026-07-16",
        approvers=("principal-architecture", "principal-quality"),
    )


def adopt_channel_client(
    *,
    expected_descriptor_ref: ContentRef,
    run_id: str,
    nonce: str,
    channel_fd: int,
    io_timeout: float = 5.0,
) -> object:
    """Adopt a pre-opened authority-store channel fd as a validated client.

    The hello validation mirrors ``AuthorityStoreClient.connect`` over the
    inherited socket; the standard client state machine takes over after.
    """
    conn = socket.socket(fileno=channel_fd)
    conn.settimeout(io_timeout)
    client = _STORE.AuthorityStoreClient(
        expected_descriptor_ref, run_id, nonce, io_timeout_seconds=io_timeout
    )
    try:
        hello = _STORE._decode_hello(_STORE._read_frame(conn))
        descriptor_ref = _STORE.descriptor_content_ref(hello["descriptor"])
        if descriptor_ref != expected_descriptor_ref:
            _STORE._fail(
                "PF-AUTH-STORE-AUTHORITY",
                "hello descriptor ref does not match the pinned ref",
            )
        if hello["runId"] != run_id or hello["nonce"] != nonce:
            _STORE._fail(
                "PF-AUTH-STORE-AUTHORITY",
                "hello runId/nonce does not match the handoff",
            )
        unsigned = {
            "schema": _STORE.HELLO_SCHEMA,
            "descriptor": hello["descriptor"],
            "runId": hello["runId"],
            "nonce": hello["nonce"],
        }
        public_key = bytes.fromhex(hello["descriptor"]["servicePublicKey"])
        if not _STORE.verify_ed25519(
            public_key,
            b"pf.authority-store-hello.v1\x00"
            + _STORE.canonical_pf_jcs(unsigned),
            hello["signature"],
        ):
            _STORE._fail(
                "PF-AUTH-STORE-AUTHORITY", "hello signature is invalid"
            )
    except BaseException:
        conn.close()
        raise
    client._conn = conn
    client._service_public_key = public_key
    client._next_request_id = 0
    client._last_head_sequence = 0
    return client


def close_task(
    base: RehearsalBase,
    run: RehearsalRun,
    client: object,
    task_id: str,
) -> None:
    """Close one task only when its authenticated dependency refs exist."""
    approval_bytes = run.approvalBytes[task_id]
    receipt_bytes = run.receiptBytes[task_id]
    approval_key = _STORE.derive_lookup_key(
        _STORE.TASK_APPROVAL_SCHEMA, approval_bytes
    )
    receipt_key = _STORE.derive_lookup_key(
        _STORE.TASK_RECEIPT_SCHEMA, receipt_bytes
    )
    approval_lookup = client.lookup(_STORE.TASK_APPROVAL_SCHEMA, approval_key)
    if approval_lookup.result != "found" or approval_lookup.objects != (
        approval_bytes,
    ):
        _state(f"{task_id} approval is not published")
    receipt_lookup = client.lookup(_STORE.TASK_RECEIPT_SCHEMA, receipt_key)
    if receipt_lookup.result != "found" or receipt_lookup.objects != (
        receipt_bytes,
    ):
        _state(f"{task_id} receipt is not published")
    receipt, receipt_ref = _CONSUMER.parse_bootstrap_task_verifier_receipt(
        receipt_bytes,
        approval_bytes,
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
        run.handoffBytes,
    )
    approval = _CONSUMER.parse_task_approval(
        approval_bytes,
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
    )[0]
    for dependency_ref in approval.dependencyCompletions:
        dependency_bytes = run.receiptBytes[dependency_ref.taskId]
        dependency_key = _STORE.derive_lookup_key(
            _STORE.TASK_RECEIPT_SCHEMA, dependency_bytes
        )
        dependency_lookup = client.lookup(
            _STORE.TASK_RECEIPT_SCHEMA, dependency_key
        )
        if dependency_lookup.result != "found" or dependency_lookup.objects != (
            dependency_bytes,
        ):
            _state(
                f"{task_id} dependency {dependency_ref.taskId} lacks an "
                "authenticated receipt ref"
            )
        _, dependency_verified_ref = _CONSUMER.parse_bootstrap_task_verifier_receipt(
            dependency_bytes,
            run.approvalBytes[dependency_ref.taskId],
            base.requiredBytes,
            base.policyBytes,
            base.phase5Snapshot,
            run.handoffBytes,
        )
        if dependency_verified_ref != dependency_ref:
            _state(
                f"{task_id} dependency {dependency_ref.taskId} ref does not "
                "match the authenticated bytes"
            )


def collect_activation_inputs(
    base: RehearsalBase,
    run: RehearsalRun,
    client: object,
) -> Tuple[bytes, Tuple[bytes, ...], bytes, bytes]:
    """Collect the exact activation closure inputs from the store."""
    set_key = _STORE.derive_lookup_key(_STORE.APPROVAL_SET_SCHEMA, run.setBytes)
    set_lookup = client.lookup(_STORE.APPROVAL_SET_SCHEMA, set_key)
    if set_lookup.result != "found" or set_lookup.objects != (run.setBytes,):
        _state("six-item approval set is not authenticated in the store")
    receipts = []
    for task_id in D0_TASK_IDS:
        receipt_bytes = run.receiptBytes[task_id]
        receipt_key = _STORE.derive_lookup_key(
            _STORE.TASK_RECEIPT_SCHEMA, receipt_bytes
        )
        receipt_lookup = client.lookup(_STORE.TASK_RECEIPT_SCHEMA, receipt_key)
        if receipt_lookup.result != "found" or receipt_lookup.objects != (
            receipt_bytes,
        ):
            _state(f"task receipt {task_id} is not authenticated in the store")
        receipts.append(receipt_bytes)
    required_key = _STORE.derive_lookup_key(
        _STORE.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
    )
    required_lookup = client.lookup(_STORE.REQUIRED_TEST_SET_SCHEMA, required_key)
    if required_lookup.result != "found" or required_lookup.objects != (
        base.requiredBytes,
    ):
        _state("required test set is not authenticated in the store")
    return run.setBytes, tuple(receipts), base.requiredBytes, base.policyBytes


def run_bootstrap_rehearsal(
    base: RehearsalBase,
    *,
    workdir: str,
    self_test_path: str,
    run_id: str,
    nonce: str,
    seeds_by_key_id: Dict[str, bytes],
    handoff_id: str = "bootstrap-acceptance-stage0-handoff",
    handoff_version: str = "1.0.0",
    prior_activation_key: Optional[bytes] = None,
    child_timeout: float = 180.0,
) -> BootstrapRehearsalReport:
    """Run the full pre-activation rehearsal end to end."""
    policy_path = str(Path(workdir) / "policy.json")
    archive_path = str(Path(workdir) / "archive.tar")
    manifest_path = str(Path(workdir) / "manifest.json")
    Path(policy_path).write_bytes(base.policyBytes)
    Path(archive_path).write_bytes(base.archiveBytes)
    Path(manifest_path).write_bytes(base.manifestBytes)

    server = _STORE.AuthorityStoreServer(
        policy_bytes=base.policyBytes,
        service_seed=base.serviceSeed,
        descriptor_id=base.descriptorWire["id"],
        descriptor_version=base.descriptorWire["version"],
        service_executable_digest=Digest(
            "sha256",
            bytes.fromhex(
                base.descriptorWire["serviceExecutableDigest"][7:]
            ),
        ),
        namespace_id=base.descriptorWire["namespaceId"],
        expected_run_id=run_id,
        expected_nonce=nonce,
        io_timeout_seconds=30.0,
    )
    socket_path = str(Path(workdir) / "authority-store.sock")
    handle = server.serve_unix(socket_path)
    produced_handoff = None
    try:
        produced_handoff = produce_run_handoff(
            base,
            handoff_id=handoff_id,
            handoff_version=handoff_version,
            run_id=run_id,
            policy_path=policy_path,
            archive_path=archive_path,
            manifest_path=manifest_path,
        )
        run = produce_run_objects(
            base,
            produced_handoff,
            run_id=run_id,
            nonce=nonce,
            seeds_by_key_id=seeds_by_key_id,
        )
        service_socket = socket.socket(
            fileno=produced_handoff.channels.authorityStoreServiceFd
        )
        threading.Thread(
            target=server._serve_connection,
            args=(service_socket,),
            name="authority-store-handoff-channel",
            daemon=True,
        ).start()

        parent_client = _STORE.AuthorityStoreClient(
            base.descriptorRef, run_id, nonce, io_timeout_seconds=30.0
        )
        parent_client.connect(socket_path)
        try:
            if parent_client.publish_with_readback(
                _STORE.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
            ) != base.requiredBytes:
                _state("required test set publish closure failed")
            if parent_client.publish_with_readback(
                _STORE.FORMAL_CATALOG_APPROVAL_SCHEMA,
                base.catalogApprovalBytes,
            ) != base.catalogApprovalBytes:
                _state("formal catalog approval publish closure failed")
            _CONSUMER.parse_formal_gate_catalog_approval(
                base.catalogApprovalBytes,
                base.catalogBytes,
                base.requiredBytes,
                base.policyBytes,
            )

            gate_failures = 0
            for task_id in _TOPOLOGICAL_TASK_IDS:
                if task_id == "TASK-D0-02":
                    try:
                        close_task(base, run, parent_client, task_id)
                    except BootstrapAcceptanceError:
                        gate_failures += 1
                    else:
                        _state(
                            "TASK-D0-02 closed before TASK-D0-01 was "
                            "authenticated"
                        )
                for schema, object_bytes in (
                    (
                        _STORE.TASK_APPROVAL_SCHEMA,
                        run.approvalBytes[task_id],
                    ),
                    (
                        _STORE.TASK_RECEIPT_SCHEMA,
                        run.receiptBytes[task_id],
                    ),
                ):
                    if parent_client.publish_with_readback(
                        schema, object_bytes
                    ) != object_bytes:
                        _state(f"{task_id} publish closure failed")
                close_task(base, run, parent_client, task_id)
            if gate_failures != 1:
                _state("dependency gate proof was not exercised")
            if parent_client.publish_with_readback(
                _STORE.APPROVAL_SET_SCHEMA, run.setBytes
            ) != run.setBytes:
                _state("approval set publish closure failed")
            collect_activation_inputs(base, run, parent_client)
        finally:
            parent_client.close()

        manifest = {
            "handoffHex": run.handoffBytes.hex(),
            "descriptorRef": {
                "schema": base.descriptorRef.schema,
                "id": base.descriptorRef.id,
                "version": base.descriptorRef.version,
                "digestHex": base.descriptorRef.digest.bytes.hex(),
            },
            "runId": run_id,
            "nonce": nonce,
            "activationBytesHex": run.activationBytes.hex(),
            "activationKeyHex": run.activationKey.hex(),
            "priorActivationKeyHex": (
                prior_activation_key.hex()
                if prior_activation_key is not None
                else None
            ),
            "inputs": {
                "policyHex": base.policyBytes.hex(),
                "requiredHex": base.requiredBytes.hex(),
                "setHex": run.setBytes.hex(),
                "receiptsHex": [
                    run.receiptBytes[task_id].hex() for task_id in D0_TASK_IDS
                ],
                "phase5Id": base.phase5Snapshot.id,
                "phase5Path": base.phase5Snapshot.path,
                "phase5Hex": base.phase5Snapshot.bytes.hex(),
            },
        }
        manifest_file = Path(workdir) / "rehearsal-child-manifest.json"
        manifest_file.write_bytes(
            json.dumps(manifest, sort_keys=True).encode("utf-8")
        )
        channel_fds = (
            produced_handoff.channels.authorityPolicyFd,
            produced_handoff.channels.authorityStoreFd,
            produced_handoff.channels.candidateArchiveFd,
            produced_handoff.channels.evidenceRootFd,
        )
        child_argv = (
            "/usr/bin/python3",
            "-I",
            "-S",
            self_test_path,
            "--rehearsal-child",
            str(manifest_file),
        )
        result = _CONTAINMENT.run_contained(
            child_argv,
            inherit_fds=channel_fds,
            env=(
                ("PATH", "/usr/bin:/bin"),
                ("LC_ALL", "C"),
                ("PYTHONDONTWRITEBYTECODE", "1"),
            ),
            chdir="/",
            timeout_seconds=child_timeout,
            stdout_limit_bytes=1024 * 1024,
            stderr_limit_bytes=1024 * 1024,
        )
        if result.exitCode != 0:
            _child(
                "contained consumer child failed with exit code "
                f"{result.exitCode}: {result.stderrBytes!r}"
            )
        expected_line = (
            f"activation: BAV-20260718-0001 "
            f"{run.activationRef.digest.bytes.hex()}\n".encode("ascii")
        )
        if expected_line not in result.stdoutBytes:
            _child(
                "contained consumer child did not return the exact "
                f"activation ref: {result.stdoutBytes!r}"
            )
        sequence, head = server.head
        if sequence != EXPECTED_PUBLISHED_OBJECTS:
            _state(
                f"store head must count {EXPECTED_PUBLISHED_OBJECTS} "
                f"appends, got {sequence}"
            )
        return BootstrapRehearsalReport(
            activationReceiptId="BAV-20260718-0001",
            activationReceiptDigestHex=run.activationRef.digest.bytes.hex(),
            storeHeadSequence=sequence,
            publishedObjects=EXPECTED_PUBLISHED_OBJECTS,
            dependencyGateFailuresProven=1,
            containmentExitCode=result.exitCode,
            childStdout=result.stdoutBytes,
        )
    finally:
        handle.stop()
        if produced_handoff is not None:
            for fd in (
                produced_handoff.channels.authorityPolicyFd,
                produced_handoff.channels.authorityStoreFd,
                produced_handoff.channels.candidateArchiveFd,
                produced_handoff.channels.evidenceRootFd,
            ):
                try:
                    os.close(fd)
                except OSError:
                    pass


def rehearsal_child_main(manifest_path: str) -> int:
    """Contained consumer child: verify channels, closure, activation chain."""
    manifest = json.loads(Path(manifest_path).read_bytes().decode("utf-8"))
    handoff_bytes = bytes.fromhex(manifest["handoffHex"])
    handoff_b = _HANDOFF._CONSUMER._preflight_eligible_stage0_handoff(
        handoff_bytes
    ).handoff
    _HANDOFF.verify_inherited_channels(handoff_b)
    descriptor = manifest["descriptorRef"]
    descriptor_ref = ContentRef(
        descriptor["schema"],
        descriptor["id"],
        descriptor["version"],
        Digest("sha256", bytes.fromhex(descriptor["digestHex"])),
    )
    store_channel_fd = handoff_b.channels[1].fd
    client = adopt_channel_client(
        expected_descriptor_ref=descriptor_ref,
        run_id=manifest["runId"],
        nonce=manifest["nonce"],
        channel_fd=store_channel_fd,
        io_timeout=60.0,
    )
    activation_bytes = bytes.fromhex(manifest["activationBytesHex"])
    activation_key = bytes.fromhex(manifest["activationKeyHex"])
    schema = _STORE.VERIFIER_RECEIPT_SCHEMA
    prior = client.lookup(schema, activation_key)
    if prior.result != "not-found":
        print(
            f"pre-activation lookup must be not-found, got {prior.result}",
            file=sys.stderr,
        )
        return 2
    prior_key_hex = manifest["priorActivationKeyHex"]
    if prior_key_hex is not None:
        prior_run = client.lookup(schema, bytes.fromhex(prior_key_hex))
        if prior_run.result != "not-found":
            print(
                "prior run activation must be absent from this namespace",
                file=sys.stderr,
            )
            return 3
    if client.publish_with_readback(schema, activation_bytes) != (
        activation_bytes
    ):
        print("activation publish closure failed", file=sys.stderr)
        return 4
    inputs = manifest["inputs"]
    phase5_snapshot = _CONSUMER.BootstrapDocumentSnapshotV1(
        id=inputs["phase5Id"],
        path=inputs["phase5Path"],
        bytes=bytes.fromhex(inputs["phase5Hex"]),
    )
    receipt, receipt_ref = _CONSUMER.parse_bootstrap_approval_verifier_receipt(
        activation_bytes,
        bytes.fromhex(inputs["setHex"]),
        tuple(bytes.fromhex(item) for item in inputs["receiptsHex"]),
        bytes.fromhex(inputs["requiredHex"]),
        bytes.fromhex(inputs["policyHex"]),
        phase5_snapshot,
        handoff_bytes,
    )
    client.close()
    print(f"activation: {receipt.id} {receipt_ref.digest.bytes.hex()}")
