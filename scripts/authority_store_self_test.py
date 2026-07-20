#!/usr/bin/env python3
"""Acceptance tests for the authority-store protected service (dev slice).

The module under test is intentionally loaded from its exact sibling pathname:
isolated Python does not add the script directory to ``sys.path``, and this
test must not make a repository-relative import path into an authority
selector.  All seeds are public RFC 8032 test vectors or synthetic test-only
material, never real authority keys.  Servers run only on Unix sockets under
a temporary directory; nothing listens on TCP or touches the system.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import inspect
import shutil
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path
from types import ModuleType
from typing import Callable


MODULE_PATH = Path(__file__).with_name("authority_store.py")
MODULE_NAME = "proof_forge_authority_store"
SEEDS_BY_KEY_ID = {
    "key-architecture": bytes.fromhex(
        "9d61b19deffd5a60ba844af492ec2cc4"
        "4449c5697b326919703bac031cae7f60"
    ),
    "key-quality": bytes.fromhex(
        "4ccd089b28ff96da9db6c346ec114e0f"
        "5b8a319f35aba624da8cf6ed4fb8a6fb"
    ),
    "key-release": bytes.fromhex(
        "c5aa8df43f9f837bedb7442f31dcb7b1"
        "66d38535076f094b85ce3a2e0b4458f7"
    ),
    "key-security": bytes.fromhex(
        "f5e5767cf153319517630f226876b86c"
        "8160cc583bc013744c6bf255f5cc0ee5"
    ),
    "key-verifier-receipt": bytes.fromhex(
        "833fe62409237b9d62ec77587520911e"
        "9a759cec1d19755b7da901b96dca3d42"
    ),
}
SERVICE_SEED = bytes.fromhex("10" * 32)
FOREIGN_SEED = bytes.fromhex("20" * 32)
RUN_ID = "run-20260718-0001"
NONCE = "ab" * 32
DESCRIPTOR_ID = "authority-store"
DESCRIPTOR_VERSION = "1.0.0"
NAMESPACE_ID = "bootstrap-authority-store"
EXECUTABLE_DIGEST_BYTES = bytes.fromhex("42" * 32)
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))


def load_store_module() -> ModuleType:
    assert sys.flags.isolated, "store self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "store self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), "missing scripts/authority_store.py"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "store import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def content_ref_wire(ref: object) -> dict:
    digest = getattr(ref, "digest")
    assert getattr(digest, "algorithm") == "sha256"
    return {
        "schema": getattr(ref, "schema"),
        "id": getattr(ref, "id"),
        "version": getattr(ref, "version"),
        "digest": digest_text(getattr(digest, "bytes")),
    }


FROZEN_PHASE5_A0_IDS = tuple(f"TST-A0-{index:03d}" for index in range(1, 21))
PHASE5_FRONTMATTER = {
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


def phase5_snapshot_bytes(required_ids: tuple[str, ...]) -> bytes:
    ids = tuple(reversed(required_ids)) + tuple(reversed(FROZEN_PHASE5_A0_IDS))
    lines = ["---"]
    lines.extend(f"{key}: {value}" for key, value in PHASE5_FRONTMATTER.items())
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


def expected_phase5_document_wire(snapshot: object) -> dict:
    encoded = getattr(snapshot, "bytes")
    digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00" + encoded
    ).digest()
    return {
        "id": "PHASE-5",
        "contentDigest": digest_text(digest),
        "status": "accepted",
        "reviewCommit": PHASE5_FRONTMATTER["reviewCommit"],
        "reviewLink": PHASE5_FRONTMATTER["reviewLink"],
        "approvedAt": PHASE5_FRONTMATTER["approvedAt"],
        "approvers": PHASE5_FRONTMATTER["approvers"].split(", "),
    }


def candidate_identity_wire(consumer: ModuleType, commit: str = "a" * 40) -> dict:
    payload = {
        "commit": commit,
        "treeObjectId": "b" * len(commit),
        "archiveDigest": digest_text(bytes.fromhex("51" * 32)),
    }
    candidate_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + consumer.canonical_pf_jcs(payload)
    ).digest()
    return {**payload, "digest": digest_text(candidate_digest)}


def normative_document_ref(consumer: ModuleType, identifier: str, review_commit: str) -> object:
    raw_bytes = f"synthetic normative document {identifier}\n".encode("ascii")
    content_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00"
        + identifier.encode("ascii")
        + b"\x00"
        + raw_bytes
    ).digest()
    return consumer.NormativeDocumentRefV1(
        id=identifier,
        contentDigest=consumer.Digest("sha256", content_digest),
        status="accepted",
        reviewCommit=review_commit,
        reviewLink=f"https://review.example/{identifier.lower()}",
        approvedAt="2026-07-16",
        approvers=("principal-architecture", "principal-quality"),
    )


def independent_review_report_bytes(label: str) -> bytes:
    return f"approved review by {label}\n".encode("ascii")


def independent_review_report_digest(raw: bytes) -> bytes:
    return hashlib.sha256(
        b"pf.independent-review-report.v1\x00" + raw
    ).digest()


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
FORMAL_CATALOG_LOCK_FIELDS = (
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
)


def build_objects(module: ModuleType) -> dict[str, object]:
    """Produce one valid allowlisted object per schema with real signatures."""
    producer = module._PRODUCER
    consumer = producer._CONSUMER

    def digest(raw: bytes) -> object:
        return consumer.Digest("sha256", raw)

    principals = tuple(
        consumer.BootstrapAuthorityPrincipalV1(
            principalId=f"principal-{role}",
            keyId=f"key-{role}",
            publicKey=producer.ed25519_public_key_from_seed(
                SEEDS_BY_KEY_ID[f"key-{role}"]
            ),
            roles=(role,),
        )
        for role in ("architecture", "quality", "release", "security")
    )
    task_rule_specs = (
        ("TASK-D0-01", ("architecture", "quality"), 2),
        ("TASK-D0-02", ("architecture", "quality"), 2),
        ("TASK-D0-03", ("quality", "security"), 2),
        ("TASK-D0-04", ("quality", "security", "release"), 3),
        ("TASK-D0-05", ("quality", "security"), 2),
        ("TASK-D0-06", ("architecture", "quality"), 2),
    )
    policy_bytes = producer.produce_bootstrap_authority_policy(
        id="bootstrap-authority-root",
        version="1.0.0",
        principals=principals,
        taskRules=tuple(
            consumer.BootstrapAuthorityTaskRuleV1(
                taskId=task_id,
                rule=consumer.ApprovalRuleV1(roles, minimum),
            )
            for task_id, roles, minimum in task_rule_specs
        ),
        requiredTestSetRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        formalCatalogRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        bootstrapSetRule=consumer.ApprovalRuleV1(
            ("quality", "security", "release"), 3
        ),
        sessionContainmentRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        freshnessAuthorityRule=consumer.ApprovalRuleV1(("quality", "release"), 2),
        privateScanRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        privateScanPolicy=consumer.ContentRef(
            "proof-forge.private-scan-policy.v1",
            "bootstrap-private-scan-policy",
            "1.0.0",
            digest(bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=consumer.ContentRef(
            "proof-forge.authority-store-service.v1",
            "bootstrap-authority-store",
            "1.0.0",
            digest(bytes.fromhex("42" * 32)),
        ),
        verifier=consumer.BootstrapAuthorityVerifierV1(
            id="bootstrap-task-verifier",
            executableDigest=digest(bytes.fromhex("43" * 32)),
            receiptKeyId="key-verifier-receipt",
            receiptPublicKey=producer.ed25519_public_key_from_seed(
                SEEDS_BY_KEY_ID["key-verifier-receipt"]
            ),
        ),
    )
    policy, policy_ref = consumer.parse_bootstrap_authority_policy(policy_bytes)

    required_ids = tuple(sorted({
        test_id
        for row in D0_GRAPH_ROWS.values()
        for test_id in row["testIds"]
    }))
    phase5_snapshot = consumer.BootstrapDocumentSnapshotV1(
        id="PHASE-5",
        path="docs/05-test-spec.md",
        bytes=phase5_snapshot_bytes(required_ids),
    )
    document_wire = expected_phase5_document_wire(phase5_snapshot)
    required_bytes = producer.produce_required_test_set(
        id="phase-5-required-tests",
        version="1.0.0",
        phase5Document=consumer.NormativeDocumentRefV1(
            id=document_wire["id"],
            contentDigest=consumer.parse_digest(document_wire["contentDigest"]),
            status="accepted",
            reviewCommit=document_wire["reviewCommit"],
            reviewLink=document_wire["reviewLink"],
            approvedAt=document_wire["approvedAt"],
            approvers=tuple(document_wire["approvers"]),
        ),
        authorityPolicy=policy_ref,
        requiredTestIds=required_ids,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    required_ref = consumer.ContentRef(
        "proof-forge.required-test-set.v1",
        "phase-5-required-tests",
        "1.0.0",
        digest(hashlib.sha256(
            b"pf.required-test-set.v1\x00" + required_bytes
        ).digest()),
    )

    candidate_wire = candidate_identity_wire(consumer)
    candidate = consumer.parse_candidate_identity(candidate_wire)
    handoff_ref = consumer.ContentRef(
        "proof-forge.eligible-stage0-handoff.v1",
        "bootstrap-stage0-handoff",
        "1.0.0",
        digest(bytes.fromhex("63" * 32)),
    )
    phase4_ref = normative_document_ref(consumer, "PHASE-4", candidate.commit)
    prerequisite_refs = {
        identifier: normative_document_ref(consumer, identifier, candidate.commit)
        for identifier in ("PHASE-1", "PHASE-2", "PHASE-3")
    }
    built: dict[str, dict[str, object]] = {}
    for task_id in (
        "TASK-D0-01",
        "TASK-D0-02",
        "TASK-D0-03",
        "TASK-D0-05",
        "TASK-D0-06",
        "TASK-D0-04",
    ):
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
                    digest=digest(bytes([0x60 + task_number]) * 32),
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
                    reportDigest=digest(independent_review_report_digest(
                        independent_review_report_bytes(f"{task_id}:{key_id}")
                    )),
                    decision="approved",
                )
                for key_id, role in row["signers"]
            ),
            signers=tuple(
                (key_id, SEEDS_BY_KEY_ID[key_id])
                for key_id, _ in row["signers"]
            ),
        )
        approval, approval_ref = consumer.parse_task_approval(
            approval_bytes,
            required_bytes,
            policy_bytes,
            phase5_snapshot,
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
            verifierDigest=policy.verifier.executableDigest,
            signer=(
                "key-verifier-receipt",
                SEEDS_BY_KEY_ID["key-verifier-receipt"],
            ),
        )
        receipt_ref = consumer.BootstrapTaskVerifierReceiptRefV1(
            task_id,
            f"BTV-20260717-{task_number:04d}",
            digest(hashlib.sha256(
                b"pf.bootstrap-task-verifier-receipt.v1\x00" + receipt_bytes
            ).digest()),
        )
        built[task_id] = {
            "approval": approval,
            "approvalBytes": approval_bytes,
            "receiptBytes": receipt_bytes,
            "receiptRef": receipt_ref,
        }

    set_bytes = producer.produce_bootstrap_approval_set(
        id="bootstrap-approval-set",
        version="1.0.0",
        candidate=candidate,
        authorityPolicy=policy_ref,
        taskBreakdown=phase4_ref,
        requiredTestSet=required_ref,
        stage0Handoff=handoff_ref,
        taskApprovals=tuple(built[task_id]["approval"] for task_id in D0_TASK_IDS),
        taskReceipts=tuple(built[task_id]["receiptRef"] for task_id in D0_TASK_IDS),
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-release", SEEDS_BY_KEY_ID["key-release"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
    )
    set_ref = consumer.ContentRef(
        "proof-forge.bootstrap-approval-set.v1",
        "bootstrap-approval-set",
        "1.0.0",
        digest(hashlib.sha256(
            b"pf.bootstrap-approval-set.v1\x00" + set_bytes
        ).digest()),
    )
    bav_bytes = producer.produce_bootstrap_approval_verifier_receipt(
        id="BAV-20260717-0001",
        candidate=candidate,
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        approvalSet=set_ref,
        stage0Handoff=handoff_ref,
        verifierDigest=policy.verifier.executableDigest,
        taskApprovals=tuple(
            consumer.TaskApprovalRefV1(
                task_id,
                digest(hashlib.sha256(
                    b"pf.bootstrap-task-approval.v1\x00"
                    + built[task_id]["approvalBytes"]
                ).digest()),
            )
            for task_id in D0_TASK_IDS
        ),
        taskReceipts=tuple(built[task_id]["receiptRef"] for task_id in D0_TASK_IDS),
        signer=(
            "key-verifier-receipt",
            SEEDS_BY_KEY_ID["key-verifier-receipt"],
        ),
    )
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "formal-alpha-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": content_ref_wire(required_ref),
        "locks": {
            field: f"{0x10 + index:02x}" * 32
            for index, field in enumerate(FORMAL_CATALOG_LOCK_FIELDS)
        },
        "gates": [
            {
                "id": "formal-gate-alpha",
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
        id="formal-catalog-approval",
        version="1.0.0",
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        catalog=catalog_ref,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )

    publishables = (
        (module.REQUIRED_TEST_SET_SCHEMA, required_bytes),
        (module.FORMAL_CATALOG_APPROVAL_SCHEMA, catalog_approval_bytes),
        (module.TASK_APPROVAL_SCHEMA, built["TASK-D0-01"]["approvalBytes"]),
        (module.TASK_RECEIPT_SCHEMA, built["TASK-D0-01"]["receiptBytes"]),
        (module.APPROVAL_SET_SCHEMA, set_bytes),
        (module.VERIFIER_RECEIPT_SCHEMA, bav_bytes),
    )
    return {
        "consumer": consumer,
        "producer": producer,
        "policyBytes": policy_bytes,
        "policy": policy,
        "policyRef": policy_ref,
        "requiredBytes": required_bytes,
        "requiredRef": required_ref,
        "phase5Snapshot": phase5_snapshot,
        "catalogBytes": catalog_bytes,
        "catalogApprovalBytes": catalog_approval_bytes,
        "built": built,
        "setBytes": set_bytes,
        "setRef": set_ref,
        "bavBytes": bav_bytes,
        "publishables": publishables,
    }


def make_server(
    module: ModuleType,
    objects: dict[str, object],
    socket_path: str,
    *,
    io_timeout: float = 5.0,
) -> object:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    server = module.AuthorityStoreServer(
        policy_bytes=objects["policyBytes"],
        service_seed=SERVICE_SEED,
        descriptor_id=DESCRIPTOR_ID,
        descriptor_version=DESCRIPTOR_VERSION,
        service_executable_digest=consumer.Digest(
            "sha256", EXECUTABLE_DIGEST_BYTES
        ),
        namespace_id=NAMESPACE_ID,
        expected_run_id=RUN_ID,
        expected_nonce=NONCE,
        io_timeout_seconds=io_timeout,
    )
    return server.serve_unix(socket_path)


def connect_client(
    module: ModuleType,
    handle: object,
    *,
    expected_ref: object | None = None,
    run_id: str = RUN_ID,
    nonce: str = NONCE,
    io_timeout: float = 5.0,
) -> object:
    server = getattr(handle, "server")
    ref = server.descriptor_ref if expected_ref is None else expected_ref
    client = module.AuthorityStoreClient(
        ref, run_id, nonce, io_timeout_seconds=io_timeout
    )
    client.connect(getattr(handle, "socket_path"))
    return client


def raw_connect(socket_path: str, timeout: float = 5.0) -> socket.socket:
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.settimeout(timeout)
    conn.connect(socket_path)
    return conn


def raw_send_frame(conn: socket.socket, payload: bytes) -> None:
    conn.sendall(len(payload).to_bytes(4, "big") + payload)


def raw_recv_exact(conn: socket.socket, count: int) -> bytes:
    chunks = []
    remaining = count
    while remaining:
        chunk = conn.recv(remaining)
        if not chunk:
            raise ConnectionError("peer closed mid-frame")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def raw_recv_frame(conn: socket.socket) -> bytes:
    header = raw_recv_exact(conn, 4)
    size = int.from_bytes(header, "big")
    return raw_recv_exact(conn, size)


def expect_closed(conn: socket.socket) -> None:
    conn.settimeout(2.0)
    try:
        data = conn.recv(1)
    except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
        return
    except socket.timeout:
        raise AssertionError("service must have closed this connection")
    except OSError:
        return
    if data:
        raise AssertionError("service must have closed this connection")


def expect_error(
    operation: Callable[[], object],
    module: ModuleType,
    codes: tuple[str, ...],
    label: str,
) -> object:
    try:
        result = operation()
    except module.AuthorityStoreError as error:
        if error.code not in codes:
            raise AssertionError(
                f"{label} raised {error.code}, expected one of {codes}"
            ) from error
        return error
    raise AssertionError(f"{label} must fail with one of {codes}; got {result!r}")


def craft_response(
    module: ModuleType,
    seed: bytes,
    *,
    request_id: int,
    run_id: str = RUN_ID,
    nonce: str = NONCE,
    lease_id: str | None = None,
    result: str = "not-found",
    objects: tuple[bytes, ...] = (),
    head_sequence: int = 0,
    head_digest: bytes = b"\x00" * 32,
) -> bytes:
    unsigned = {
        "schema": module.RESPONSE_SCHEMA,
        "requestId": request_id,
        "runId": run_id,
        "nonce": nonce,
        "leaseId": lease_id,
        "result": result,
        "objects": [item.hex() for item in objects],
        "headSequence": head_sequence,
        "headDigest": digest_text(head_digest),
    }
    signature = module._PRODUCER.sign_ed25519(
        seed, b"pf.authority-store-response.v1\x00"
        + module._CONSUMER.canonical_pf_jcs(unsigned)
    )
    return module._CONSUMER.canonical_pf_jcs(
        {**unsigned, "signature": signature.hex()}
    )


def run_fake_server(socket_path: str, handler: Callable[[socket.socket], None]) -> None:
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(socket_path)
    listener.listen(1)

    def loop() -> None:
        try:
            conn, _ = listener.accept()
        except OSError:
            return
        try:
            conn.settimeout(5.0)
            handler(conn)
        except (OSError, ConnectionError):
            pass
        finally:
            try:
                conn.close()
            finally:
                listener.close()

    threading.Thread(target=loop, daemon=True).start()


def valid_hello_bytes(module: ModuleType, handle: object) -> bytes:
    server = getattr(handle, "server")
    return module._encode_hello(
        server.descriptor_wire, RUN_ID, NONCE, SERVICE_SEED
    )


def assert_public_api(module: ModuleType) -> None:
    assert module.PROTOCOL_ID == "pf.authority-store.rpc.v1"
    assert module.MAXIMUM_FRAME_BYTES == 4194304
    assert len(module.ALLOWLIST_SCHEMAS) == 6
    for name in (
        "AuthorityStoreError",
        "AuthorityStoreServer",
        "AuthorityStoreClient",
        "StoreResponse",
        "derive_lookup_key",
        "descriptor_content_ref",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    import dataclasses
    assert dataclasses.is_dataclass(module.StoreResponse)
    assert tuple(
        field.name for field in dataclasses.fields(module.StoreResponse)
    ) == (
        "requestId",
        "runId",
        "nonce",
        "leaseId",
        "result",
        "objects",
        "headSequence",
        "headDigest",
    )
    server_parameters = tuple(
        inspect.signature(module.AuthorityStoreServer.__init__).parameters.values()
    )
    server_names = tuple(parameter.name for parameter in server_parameters)
    assert server_names == (
        "self",
        "policy_bytes",
        "service_seed",
        "descriptor_id",
        "descriptor_version",
        "service_executable_digest",
        "namespace_id",
        "expected_run_id",
        "expected_nonce",
        "io_timeout_seconds",
    ), "server constructor must take explicit deployment inputs only"
    client_parameters = tuple(
        inspect.signature(module.AuthorityStoreClient.__init__).parameters.values()
    )
    assert tuple(parameter.name for parameter in client_parameters) == (
        "self",
        "expected_descriptor_ref",
        "expected_run_id",
        "expected_nonce",
        "io_timeout_seconds",
    ), "client constructor must take pinned identity inputs only"


def test_positive_publish_readback_all_schemas(
    module: ModuleType,
    objects: dict[str, object],
    tmpdir: str,
) -> None:
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    expected_head = hashlib.sha256(
        b"pf.authority-store-log-head.v1\x00" + (0).to_bytes(8, "big")
    ).digest()
    with make_server(module, objects, f"{tmpdir}/positive.sock") as handle:
        for index, (schema, object_bytes) in enumerate(publishables, start=1):
            key = module.derive_lookup_key(schema, object_bytes)
            client = connect_client(module, handle)
            ack = client.publish(schema, object_bytes)
            if ack.result != "stored":
                raise AssertionError(f"publish of {schema} must store")
            if ack.leaseId is None or len(ack.leaseId) != 64:
                raise AssertionError("stored ack must carry a 64-hex leaseId")
            if ack.objects != (object_bytes,):
                raise AssertionError("stored ack must echo the exact object")
            entry_hash = hashlib.sha256(
                b"pf.authority-store-log-entry.v1\x00"
                + schema.encode("utf-8")
                + b"\x00"
                + key
                + object_bytes
            ).digest()
            expected_head = hashlib.sha256(
                b"pf.authority-store-log-head.v1\x00"
                + index.to_bytes(8, "big")
                + expected_head
                + entry_hash
            ).digest()
            if ack.headSequence != index:
                raise AssertionError("headSequence must count appends")
            if ack.headDigest.bytes != expected_head:
                raise AssertionError(
                    "headDigest must match the pinned log-head chain"
                )
            readback = client.lookup(schema, key, lease_id=ack.leaseId)
            if readback.result != "found" or readback.objects != (object_bytes,):
                raise AssertionError("readback must return the exact bytes")
            if (readback.leaseId != ack.leaseId
                    or readback.headSequence != ack.headSequence
                    or readback.headDigest != ack.headDigest):
                raise AssertionError(
                    "readback must match the stored ack lease and head pair"
                )
            client.close()

            plain_client = connect_client(module, handle)
            plain = plain_client.lookup(schema, key)
            if plain.result != "found" or plain.leaseId is not None:
                raise AssertionError(
                    "ordinary lookup must find the object with a null leaseId"
                )
            if plain.objects != (object_bytes,):
                raise AssertionError("ordinary lookup must echo exact bytes")
            plain_client.close()
        client = connect_client(module, handle)
        missing = client.lookup(
            module.REQUIRED_TEST_SET_SCHEMA,
            module._CONSUMER.canonical_pf_jcs([{"schema": "proof-forge.required-test-set.v1"}]),
        )
        if missing.result != "not-found" or missing.leaseId is not None:
            raise AssertionError("missing key must return not-found/null lease")
        if missing.objects:
            raise AssertionError("not-found must carry no objects")
        client.close()
        sequence, head = getattr(handle, "server").head
        if sequence != len(publishables) or head != expected_head:
            raise AssertionError("server head must track every append")


def test_closure_helper(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[0]
    with make_server(module, objects, f"{tmpdir}/closure.sock") as handle:
        client = connect_client(module, handle)
        returned = client.publish_with_readback(schema, object_bytes)
        if returned != object_bytes:
            raise AssertionError("closure must return the exact stored bytes")
        client.close()


def test_frame_negatives(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    request = {
        "schema": module.REQUEST_SCHEMA,
        "requestId": 0,
        "runId": RUN_ID,
        "nonce": NONCE,
        "leaseId": None,
        "operation": "lookup",
        "objectSchema": module.REQUIRED_TEST_SET_SCHEMA,
        "lookupKeyHex": consumer.canonical_pf_jcs([{"schema": "x"}]).hex(),
        "objectBytesHex": None,
    }
    canonical_request = consumer.canonical_pf_jcs(request)
    with make_server(module, objects, f"{tmpdir}/frames.sock") as handle:
        socket_path = getattr(handle, "socket_path")

        def raw_case(sender: Callable[[socket.socket], None], label: str) -> None:
            conn = raw_connect(socket_path)
            try:
                raw_recv_frame(conn)  # hello
                sender(conn)
                expect_closed(conn)
            finally:
                conn.close()

        def truncated_sender(payload: bytes) -> Callable[[socket.socket], None]:
            def send(conn: socket.socket) -> None:
                conn.sendall(payload)
                try:
                    conn.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
            return send

        raw_case(
            truncated_sender(b"\x00\x00"),
            "partial frame header",
        )
        raw_case(
            lambda conn: conn.sendall(
                (module.MAXIMUM_FRAME_BYTES + 1).to_bytes(4, "big") + b"aa"
            ),
            "oversized frame header",
        )
        raw_case(lambda conn: conn.sendall((0).to_bytes(4, "big")), "zero frame size")
        raw_case(
            truncated_sender((100).to_bytes(4, "big") + b"{}"),
            "truncated frame payload",
        )
        raw_case(
            lambda conn: raw_send_frame(conn, b" " + canonical_request),
            "noncanonical request payload",
        )
        raw_case(lambda conn: raw_send_frame(conn, b"{"), "invalid JSON payload")

        client = connect_client(module, handle)
        missing = client.lookup(
            module.REQUIRED_TEST_SET_SCHEMA,
            consumer.canonical_pf_jcs([{"schema": "x"}]),
        )
        if missing.result != "not-found":
            raise AssertionError("service must stay alive after raw negatives")
        client.close()


def test_hello_negatives(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    producer = objects["producer"]
    assert isinstance(producer, ModuleType)
    with make_server(module, objects, f"{tmpdir}/hello-anchor.sock") as anchor:
        descriptor_wire = getattr(anchor, "server").descriptor_wire
        expected_ref = getattr(anchor, "server").descriptor_ref

        def fake_hello_bytes(**overrides: object) -> bytes:
            descriptor = copy.deepcopy(descriptor_wire)
            run_id = RUN_ID
            nonce = NONCE
            signature_seed = SERVICE_SEED
            tampered_signature: str | None = None
            for key, value in overrides.items():
                if key == "descriptor_namespace":
                    descriptor["namespaceId"] = value
                elif key == "descriptor_pubkey":
                    descriptor["servicePublicKey"] = value
                elif key == "run_id":
                    run_id = value
                elif key == "nonce":
                    nonce = value
                elif key == "signature_seed":
                    signature_seed = value
                elif key == "tampered_signature":
                    tampered_signature = value
                else:
                    raise AssertionError(f"unknown override {key}")
            unsigned = {
                "schema": module.HELLO_SCHEMA,
                "descriptor": descriptor,
                "runId": run_id,
                "nonce": nonce,
            }
            signature = producer.sign_ed25519(
                signature_seed,
                b"pf.authority-store-hello.v1\x00"
                + consumer.canonical_pf_jcs(unsigned),
            )
            return consumer.canonical_pf_jcs({
                **unsigned,
                "signature": (
                    signature.hex()
                    if tampered_signature is None
                    else tampered_signature
                ),
            })

        cases = (
            (
                "descriptor namespace drift",
                fake_hello_bytes(descriptor_namespace="other-namespace"),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "descriptor public key drift",
                fake_hello_bytes(
                    descriptor_pubkey=producer.ed25519_public_key_from_seed(
                        FOREIGN_SEED
                    ).hex()
                ),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "hello runId drift",
                fake_hello_bytes(run_id="run-20990101-9999"),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "hello nonce drift",
                fake_hello_bytes(nonce="cd" * 32),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "hello signed with a foreign seed",
                fake_hello_bytes(signature_seed=FOREIGN_SEED),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "hello signature tampered",
                fake_hello_bytes(tampered_signature="00" * 64),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "hello signature not lowercase hex",
                fake_hello_bytes(tampered_signature="AA" * 64),
                ("PF-AUTH-STORE-WIRE",),
            ),
        )
        for index, (label, hello_bytes, codes) in enumerate(cases):
            socket_path = f"{tmpdir}/fake-hello-{index}.sock"

            def handler(conn: socket.socket, hello_bytes: bytes = hello_bytes) -> None:
                raw_send_frame(conn, hello_bytes)
                time.sleep(0.05)

            run_fake_server(socket_path, handler)
            client = module.AuthorityStoreClient(expected_ref, RUN_ID, NONCE)
            expect_error(
                lambda socket_path=socket_path, client=client: client.connect(
                    socket_path
                ),
                module,
                codes,
                label,
            )

        socket_path = f"{tmpdir}/fake-hello-noncanonical.sock"

        def noncanonical_handler(conn: socket.socket) -> None:
            raw_send_frame(conn, b" " + fake_hello_bytes())
            time.sleep(0.05)

        run_fake_server(socket_path, noncanonical_handler)
        client = module.AuthorityStoreClient(expected_ref, RUN_ID, NONCE)
        expect_error(
            lambda: client.connect(socket_path),
            module,
            ("PF-AUTH-STORE-WIRE",),
            "noncanonical hello payload",
        )

        drifted_ref = consumer.ContentRef(
            expected_ref.schema,
            expected_ref.id,
            expected_ref.version,
            consumer.Digest("sha256", bytes.fromhex("77" * 32)),
        )
        expect_error(
            lambda: connect_client(module, anchor, expected_ref=drifted_ref),
            module,
            ("PF-AUTH-STORE-AUTHORITY",),
            "client with drifted expected descriptor ref",
        )


def test_request_envelope_negatives(
    module: ModuleType,
    objects: dict[str, object],
    tmpdir: str,
) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[0]
    key = module.derive_lookup_key(schema, object_bytes)
    base_request = {
        "schema": module.REQUEST_SCHEMA,
        "requestId": 0,
        "runId": RUN_ID,
        "nonce": NONCE,
        "leaseId": None,
        "operation": "lookup",
        "objectSchema": schema,
        "lookupKeyHex": key.hex(),
        "objectBytesHex": None,
    }
    cases = []
    for label, mutator in (
        ("requestId starts at one", lambda r: r.__setitem__("requestId", 1)),
        ("requestId as text", lambda r: r.__setitem__("requestId", "0")),
        ("unknown operation", lambda r: r.__setitem__("operation", "delete")),
        (
            "ordinary request carries a leaseId",
            lambda r: r.__setitem__("leaseId", "ab" * 32),
        ),
        (
            "schema outside the allowlist",
            lambda r: r.__setitem__("objectSchema", "proof-forge.gate-catalog.v1"),
        ),
        (
            "lookup carries object bytes",
            lambda r: r.__setitem__("objectBytesHex", "aa"),
        ),
        (
            "lookup without a key",
            lambda r: r.__setitem__("lookupKeyHex", None),
        ),
        (
            "lookupKeyHex odd length",
            lambda r: r.__setitem__("lookupKeyHex", "abc"),
        ),
        (
            "lookupKeyHex uppercase",
            lambda r: r.__setitem__("lookupKeyHex", "AA"),
        ),
        (
            "lookupKeyHex of noncanonical bytes",
            lambda r: r.__setitem__("lookupKeyHex", (b" " + key).hex()),
        ),
        ("request runId drift", lambda r: r.__setitem__("runId", "run-x")),
        ("request nonce drift", lambda r: r.__setitem__("nonce", "cd" * 32)),
        (
            "request schema drift",
            lambda r: r.__setitem__("schema", "proof-forge.authority-store-request.v2"),
        ),
        ("unknown request field", lambda r: r.__setitem__("futureField", True)),
        ("missing request field", lambda r: r.pop("nonce")),
    ):
        mutated = copy.deepcopy(base_request)
        mutator(mutated)
        cases.append((label, consumer.canonical_pf_jcs(mutated)))

    canonical_base = consumer.canonical_pf_jcs(base_request)
    over_range = canonical_base.replace(
        b'"requestId":0,', b'"requestId":9007199254740992,', 1
    )
    assert over_range != canonical_base
    cases.append(("requestId above 2^53-1", over_range))

    replay_first = canonical_base
    with make_server(module, objects, f"{tmpdir}/envelope.sock") as handle:
        socket_path = getattr(handle, "socket_path")
        for label, payload in cases:
            conn = raw_connect(socket_path)
            try:
                raw_recv_frame(conn)
                raw_send_frame(conn, payload)
                expect_closed(conn)
            finally:
                conn.close()

        conn = raw_connect(socket_path)
        try:
            raw_recv_frame(conn)
            raw_send_frame(conn, replay_first)
            raw_recv_frame(conn)  # valid first response (not-found)
            raw_send_frame(conn, replay_first)
            expect_closed(conn)
        finally:
            conn.close()

        client = connect_client(module, handle)
        missing = client.lookup(schema, key)
        if missing.result != "not-found":
            raise AssertionError("service must stay alive after envelope negatives")
        client.close()


def test_publish_authority_negatives(
    module: ModuleType,
    objects: dict[str, object],
    tmpdir: str,
) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    producer = objects["producer"]
    assert isinstance(producer, ModuleType)
    required_bytes = objects["requiredBytes"]
    assert isinstance(required_bytes, bytes)
    receipt_bytes = objects["built"]["TASK-D0-01"]["receiptBytes"]
    assert isinstance(receipt_bytes, bytes)
    catalog_approval_bytes = objects["catalogApprovalBytes"]
    assert isinstance(catalog_approval_bytes, bytes)
    policy_ref = objects["policyRef"]

    tampered_required = consumer.decode_canonical_pf_jcs(required_bytes)
    tampered_required["signatures"][0]["signature"] = "00" * 64
    tampered_required_bytes = consumer.canonical_pf_jcs(tampered_required)

    drifted_policy_ref = consumer.ContentRef(
        policy_ref.schema,
        policy_ref.id,
        policy_ref.version,
        consumer.Digest("sha256", bytes.fromhex("c6" * 32)),
    )
    catalog_wire = consumer.decode_canonical_pf_jcs(objects["catalogBytes"])
    drifted_catalog_ref = consumer.GateCatalogRefV1(
        catalog_wire["schema"],
        catalog_wire["id"],
        catalog_wire["version"],
        hashlib.sha256(objects["catalogBytes"]).hexdigest(),
        hashlib.sha256(
            b"pf.gate-catalog.v1\x00" + objects["catalogBytes"]
        ).hexdigest(),
    )
    drifted_approval_bytes = producer.produce_formal_gate_catalog_approval(
        id="formal-catalog-approval",
        version="1.0.0",
        authorityPolicy=drifted_policy_ref,
        requiredTestSet=objects["requiredRef"],
        catalog=drifted_catalog_ref,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=objects["policyBytes"],
    )

    cases = (
        (
            "publish with tampered required-set signature",
            module.REQUIRED_TEST_SET_SCHEMA,
            tampered_required_bytes,
            module.derive_lookup_key(
                module.REQUIRED_TEST_SET_SCHEMA, tampered_required_bytes
            ),
        ),
        (
            "publish lookup key does not match the object",
            module.REQUIRED_TEST_SET_SCHEMA,
            required_bytes,
            module.derive_lookup_key(module.TASK_RECEIPT_SCHEMA, receipt_bytes),
        ),
        (
            "publish with drifted authority policy ref",
            module.FORMAL_CATALOG_APPROVAL_SCHEMA,
            drifted_approval_bytes,
            module.derive_lookup_key(
                module.FORMAL_CATALOG_APPROVAL_SCHEMA, drifted_approval_bytes
            ),
        ),
        (
            "publish malformed object bytes",
            module.REQUIRED_TEST_SET_SCHEMA,
            b"{",
            consumer.canonical_pf_jcs([{"schema": "x"}]),
        ),
        (
            "publish object under the wrong schema",
            module.APPROVAL_SET_SCHEMA,
            required_bytes,
            module.derive_lookup_key(module.REQUIRED_TEST_SET_SCHEMA, required_bytes),
        ),
    )
    with make_server(module, objects, f"{tmpdir}/authority.sock") as handle:
        socket_path = getattr(handle, "socket_path")
        for index, (label, schema, object_bytes, key_bytes) in enumerate(cases):
            request = {
                "schema": module.REQUEST_SCHEMA,
                "requestId": 0,
                "runId": RUN_ID,
                "nonce": NONCE,
                "leaseId": None,
                "operation": "publish",
                "objectSchema": schema,
                "lookupKeyHex": key_bytes.hex(),
                "objectBytesHex": object_bytes.hex(),
            }
            conn = raw_connect(socket_path)
            try:
                raw_recv_frame(conn)
                raw_send_frame(conn, consumer.canonical_pf_jcs(request))
                expect_closed(conn)
            finally:
                conn.close()

        client = connect_client(module, handle)
        returned = client.publish_with_readback(
            module.REQUIRED_TEST_SET_SCHEMA, required_bytes
        )
        if returned != required_bytes:
            raise AssertionError("service must stay alive after authority negatives")
        client.close()


def test_conflict_no_clobber(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[2]
    key = module.derive_lookup_key(schema, object_bytes)
    with make_server(module, objects, f"{tmpdir}/conflict.sock") as handle:
        first = connect_client(module, handle)
        returned = first.publish_with_readback(schema, object_bytes)
        if returned != object_bytes:
            raise AssertionError("first publish must close the readback window")
        first.close()

        second = connect_client(module, handle)
        conflict = second.publish(schema, object_bytes)
        if conflict.result != "conflict":
            raise AssertionError("re-publish of an existing key must conflict")
        if conflict.leaseId is not None or conflict.objects:
            raise AssertionError("conflict must carry a null leaseId and no objects")
        found = second.lookup(schema, key)
        if found.result != "found" or found.objects != (object_bytes,):
            raise AssertionError("conflict must not clobber the stored object")
        expect_error(
            lambda: second.publish_with_readback(schema, object_bytes),
            module,
            ("PF-AUTH-STORE-CONFLICT",),
            "closure helper must surface conflict",
        )
        second.close()


def test_readback_window(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[3]
    other_schema, other_bytes = publishables[4]
    key = module.derive_lookup_key(schema, object_bytes)
    other_key = module.derive_lookup_key(other_schema, other_bytes)

    with make_server(module, objects, f"{tmpdir}/window.sock") as handle:
        client = connect_client(module, handle)
        ack = client.publish(schema, object_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store before window negatives")
        expect_error(
            lambda: client.lookup(schema, key),
            module,
            ("PF-AUTH-STORE-IO",),
            "window lookup without the leaseId must close the channel",
        )

        client = connect_client(module, handle)
        ack = client.publish(other_schema, other_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store after the first window failed")
        expect_error(
            lambda: client.publish(schema, object_bytes),
            module,
            ("PF-AUTH-STORE-IO",),
            "publish inside the window must close the channel",
        )

        client = connect_client(module, handle)
        ack = client.publish(schema, object_bytes)
        if ack.result == "stored":
            raise AssertionError("object must already exist after the append")
        client.close()

        publisher = connect_client(module, handle)
        third_schema, third_bytes = publishables[5]
        third_key = module.derive_lookup_key(third_schema, third_bytes)
        ack = publisher.publish(third_schema, third_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store for the exclusivity case")
        intruder = connect_client(module, handle)
        expect_error(
            lambda: intruder.lookup(schema, key),
            module,
            ("PF-AUTH-STORE-IO",),
            "another connection must not enter the readback window",
        )
        readback = publisher.lookup(third_schema, third_key, lease_id=ack.leaseId)
        if readback.result != "found" or readback.objects != (third_bytes,):
            raise AssertionError("window owner must still complete its readback")
        publisher.close()

    with make_server(module, objects, f"{tmpdir}/window-close.sock") as handle:
        client = connect_client(module, handle)
        ack = client.publish(schema, object_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store for the close case")
        client.close()
        follower = connect_client(module, handle)
        found = follower.lookup(schema, key)
        if found.result != "found" or found.objects != (object_bytes,):
            raise AssertionError(
                "append persists after an unclosed readback window"
            )
        follower.close()

    with make_server(
        module, objects, f"{tmpdir}/window-timeout.sock", io_timeout=0.3
    ) as handle:
        client = connect_client(module, handle)
        ack = client.publish(schema, object_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store for the timeout case")
        time.sleep(0.7)
        expect_error(
            lambda: client.lookup(schema, key, lease_id=ack.leaseId),
            module,
            ("PF-AUTH-STORE-IO", "PF-AUTH-STORE-TIMEOUT"),
            "readback after the window timeout must fail",
        )

    with make_server(module, objects, f"{tmpdir}/window-lease.sock") as handle:
        client = connect_client(module, handle)
        ack = client.publish(schema, object_bytes)
        if ack.result != "stored":
            raise AssertionError("publish must store for the wrong-lease case")
        expect_error(
            lambda: client.lookup(schema, key, lease_id="0" * 64),
            module,
            ("PF-AUTH-STORE-IO",),
            "readback with a foreign leaseId must close the channel",
        )


def test_revoked_multiple(module: ModuleType, objects: dict[str, object], tmpdir: str) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[1]
    key = module.derive_lookup_key(schema, object_bytes)
    with make_server(module, objects, f"{tmpdir}/revoked.sock") as handle:
        server = getattr(handle, "server")
        server.inject_store_entry(schema, key, (), "revoked")
        client = connect_client(module, handle)
        revoked = client.lookup(schema, key)
        if revoked.result != "revoked" or revoked.objects or revoked.leaseId is not None:
            raise AssertionError("revoked key must return revoked/empty/null lease")
        conflict = client.publish(schema, object_bytes)
        if conflict.result != "conflict" or conflict.leaseId is not None:
            raise AssertionError("publish into a revoked key must conflict")
        client.close()

        foreign_bytes = consumer.canonical_pf_jcs({"schema": schema, "id": "other"})
        server.inject_store_entry(
            schema,
            key,
            (object_bytes, foreign_bytes),
            "multiple",
        )
        client = connect_client(module, handle)
        multiple = client.lookup(schema, key)
        if multiple.result != "multiple" or multiple.objects != (
            object_bytes,
            foreign_bytes,
        ):
            raise AssertionError("multiple key must return every conflicting object")
        client.close()


def test_response_validation_negatives(
    module: ModuleType,
    objects: dict[str, object],
    tmpdir: str,
) -> None:
    consumer = objects["consumer"]
    assert isinstance(consumer, ModuleType)
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    schema, object_bytes = publishables[0]
    key = module.derive_lookup_key(schema, object_bytes)
    with make_server(module, objects, f"{tmpdir}/response-anchor.sock") as anchor:
        expected_ref = getattr(anchor, "server").descriptor_ref
        hello = valid_hello_bytes(module, anchor)

        def run_response_case(
            label: str,
            responses: tuple[bytes, ...],
            operation: Callable[[object], object],
            codes: tuple[str, ...],
            index: int,
        ) -> None:
            socket_path = f"{tmpdir}/fake-response-{index}.sock"

            def handler(conn: socket.socket) -> None:
                raw_send_frame(conn, hello)
                for response in responses:
                    raw_recv_frame(conn)
                    raw_send_frame(conn, response)
                time.sleep(0.05)

            run_fake_server(socket_path, handler)
            client = module.AuthorityStoreClient(expected_ref, RUN_ID, NONCE)
            client.connect(socket_path)
            expect_error(lambda: operation(client), module, codes, label)
            client.close()

        cases = (
            (
                "response signature tampered",
                lambda response: consumer.canonical_pf_jcs({
                    **consumer.decode_canonical_pf_jcs(response),
                    "signature": "00" * 64,
                }),
                craft_response(
                    module, SERVICE_SEED, request_id=0, result="not-found"
                ),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "response signed with a foreign seed",
                None,
                craft_response(
                    module, FOREIGN_SEED, request_id=0, result="not-found"
                ),
                ("PF-AUTH-STORE-AUTHORITY",),
            ),
            (
                "response requestId does not echo",
                None,
                craft_response(
                    module, SERVICE_SEED, request_id=7, result="not-found"
                ),
                ("PF-AUTH-STORE-SEQUENCE",),
            ),
            (
                "response runId drift",
                None,
                craft_response(
                    module,
                    SERVICE_SEED,
                    request_id=0,
                    run_id="run-x",
                    result="not-found",
                ),
                ("PF-AUTH-STORE-WIRE",),
            ),
            (
                "response nonce drift",
                None,
                craft_response(
                    module,
                    SERVICE_SEED,
                    request_id=0,
                    nonce="cd" * 32,
                    result="not-found",
                ),
                ("PF-AUTH-STORE-WIRE",),
            ),
            (
                "response result outside the closed set",
                None,
                consumer.canonical_pf_jcs({
                    **consumer.decode_canonical_pf_jcs(craft_response(
                        module, SERVICE_SEED, request_id=0, result="not-found"
                    )),
                    "result": "bogus",
                }),
                ("PF-AUTH-STORE-WIRE",),
            ),
            (
                "not-found response carries a leaseId",
                None,
                consumer.canonical_pf_jcs({
                    **consumer.decode_canonical_pf_jcs(craft_response(
                        module, SERVICE_SEED, request_id=0, result="not-found"
                    )),
                    "leaseId": "ef" * 32,
                }),
                ("PF-AUTH-STORE-WIRE",),
            ),
            (
                "found response without objects",
                None,
                consumer.canonical_pf_jcs({
                    **consumer.decode_canonical_pf_jcs(craft_response(
                        module,
                        SERVICE_SEED,
                        request_id=0,
                        result="found",
                        objects=(),
                    )),
                }),
                ("PF-AUTH-STORE-WIRE",),
            ),
            (
                "response headDigest malformed",
                None,
                consumer.canonical_pf_jcs({
                    **consumer.decode_canonical_pf_jcs(craft_response(
                        module, SERVICE_SEED, request_id=0, result="not-found"
                    )),
                    "headDigest": "sha256:" + "0" * 63,
                }),
                ("PF-AUTH-STORE-WIRE",),
            ),
        )
        for index, (label, transform, response, codes) in enumerate(cases):
            payload = response if transform is None else transform(response)
            run_response_case(
                label,
                (payload,),
                lambda client: client.lookup(schema, key),
                codes,
                index,
            )

        regression_responses = (
            craft_response(
                module, SERVICE_SEED, request_id=0,
                result="not-found", head_sequence=5,
            ),
            craft_response(
                module, SERVICE_SEED, request_id=1,
                result="not-found", head_sequence=3,
            ),
        )
        run_response_case(
            "response headSequence regression",
            regression_responses,
            lambda client: (
                client.lookup(schema, key),
                client.lookup(schema, key),
            )[1],
            ("PF-AUTH-STORE-HEAD",),
            len(cases),
        )

        ack_head = hashlib.sha256(b"ack-head".rjust(32, b"\x00")).digest()
        other_head = hashlib.sha256(b"other-head".rjust(32, b"\x00")).digest()
        closure_responses = (
            craft_response(
                module, SERVICE_SEED, request_id=0,
                result="stored", objects=(object_bytes,),
                lease_id="01" * 32, head_sequence=1, head_digest=ack_head,
            ),
            craft_response(
                module, SERVICE_SEED, request_id=1,
                result="found", objects=(object_bytes,),
                lease_id="01" * 32, head_sequence=1, head_digest=other_head,
            ),
        )
        run_response_case(
            "readback headDigest differs from the stored ack",
            closure_responses,
            lambda client: client.publish_with_readback(schema, object_bytes),
            ("PF-AUTH-STORE-HEAD",),
            len(cases) + 1,
        )

        object_mismatch_responses = (
            craft_response(
                module, SERVICE_SEED, request_id=0,
                result="stored", objects=(object_bytes,),
                lease_id="01" * 32, head_sequence=1, head_digest=ack_head,
            ),
            craft_response(
                module, SERVICE_SEED, request_id=1,
                result="found", objects=(b"\x00" * 32,),
                lease_id="01" * 32, head_sequence=1, head_digest=ack_head,
            ),
        )
        run_response_case(
            "readback object bytes differ from the stored ack",
            object_mismatch_responses,
            lambda client: client.publish_with_readback(schema, object_bytes),
            ("PF-AUTH-STORE-HEAD",),
            len(cases) + 2,
        )


def test_head_chain_and_request_ids(
    module: ModuleType,
    objects: dict[str, object],
    tmpdir: str,
) -> None:
    publishables = objects["publishables"]
    assert isinstance(publishables, tuple)
    with make_server(module, objects, f"{tmpdir}/head.sock") as handle:
        client = connect_client(module, handle)
        expected_head = hashlib.sha256(
            b"pf.authority-store-log-head.v1\x00" + (0).to_bytes(8, "big")
        ).digest()
        for index, (schema, object_bytes) in enumerate(publishables[:3], start=1):
            key = module.derive_lookup_key(schema, object_bytes)
            ack = client.publish(schema, object_bytes)
            if ack.requestId != (index - 1) * 2:
                raise AssertionError("request ids must increment per request")
            entry_hash = hashlib.sha256(
                b"pf.authority-store-log-entry.v1\x00"
                + schema.encode("utf-8")
                + b"\x00"
                + key
                + object_bytes
            ).digest()
            expected_head = hashlib.sha256(
                b"pf.authority-store-log-head.v1\x00"
                + index.to_bytes(8, "big")
                + expected_head
                + entry_hash
            ).digest()
            if ack.headSequence != index or ack.headDigest.bytes != expected_head:
                raise AssertionError("ack head must equal the pinned chain")
            readback = client.lookup(schema, key, lease_id=ack.leaseId)
            if readback.requestId != (index - 1) * 2 + 1:
                raise AssertionError("readback request id must continue the chain")
            if (readback.headSequence != index
                    or readback.headDigest.bytes != expected_head):
                raise AssertionError("readback must preserve the ack head pair")
        client.close()


def main() -> int:
    # Darwin limits AF_UNIX pathnames to 104 bytes.  The default per-user
    # temporary directory is already long enough that descriptive fixture
    # socket names exceed that limit, so keep this process-private tree under
    # the stable short POSIX temporary root.
    tmpdir = tempfile.mkdtemp(prefix="pf-as-", dir="/tmp")
    try:
        module = load_store_module()
        assert_public_api(module)
        objects = build_objects(module)
        test_positive_publish_readback_all_schemas(module, objects, tmpdir)
        test_closure_helper(module, objects, tmpdir)
        test_frame_negatives(module, objects, tmpdir)
        test_hello_negatives(module, objects, tmpdir)
        test_request_envelope_negatives(module, objects, tmpdir)
        test_publish_authority_negatives(module, objects, tmpdir)
        test_conflict_no_clobber(module, objects, tmpdir)
        test_readback_window(module, objects, tmpdir)
        test_revoked_multiple(module, objects, tmpdir)
        test_response_validation_negatives(module, objects, tmpdir)
        test_head_chain_and_request_ids(module, objects, tmpdir)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"authority-store-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("authority-store-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
