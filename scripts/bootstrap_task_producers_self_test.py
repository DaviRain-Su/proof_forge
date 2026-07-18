#!/usr/bin/env python3
"""Acceptance tests for the dependency-free bootstrap task object producer.

The producer module is intentionally loaded from its exact sibling pathname:
isolated Python does not add the script directory to ``sys.path``, and this test
must not make a repository-relative import path into an authority selector.
All seeds below are public RFC 8032 test vectors, never real authority keys.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import inspect
import sys
from pathlib import Path
from types import ModuleType
from typing import Callable


MODULE_PATH = Path(__file__).with_name("bootstrap_task_producers.py")
MODULE_NAME = "proof_forge_bootstrap_task_producers"
BOOTSTRAP_REJECTION = "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED"
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
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
EXPECTED_PUBLIC_KEYS = {
    "key-architecture": (
        "d75a980182b10ab7d54bfed3c964073a"
        "0ee172f3daa62325af021a68f707511a"
    ),
    "key-quality": (
        "3d4017c3e843895a92b70aa74d1b7ebc"
        "9c982ccf2ec4968cc0cd55f12af4660c"
    ),
    "key-release": (
        "fc51cd8e6218a1a38da47ed00230f058"
        "0816ed13ba3303ac5deb911548908025"
    ),
    "key-security": (
        "278117fc144c72340f67d0f2316e8386"
        "ceffbf2b2428c9c51fef7c597f1d426e"
    ),
    "key-verifier-receipt": (
        "ec172b93ad5e563bf4932c70e1245034"
        "c35467ef2efd4d64ebf819683467e2bf"
    ),
}
RFC_8032_TEST1_MESSAGE = b""
RFC_8032_TEST1_SIGNATURE = (
    "e5564300c360ac729086e2cc806e82"
    "8a84877f1eb8e5d974d873e06522490155"
    "5fb8821590a33bacc61e39701cf9b46b"
    "d25bf5f0595bbe24655141438e7a100b"
)
RFC_8032_TEST2_MESSAGE = bytes([0x72])
RFC_8032_TEST2_SIGNATURE = (
    "92a009a9f0d4cab8720e820b5f6425"
    "40a2b27b5416503f8fb3762223ebdb69da"
    "085ac1e43e15996e458f3613d0f11d8c"
    "387b2eaeb4302aeeb00d291612bb0c00"
)


def load_producer() -> ModuleType:
    assert sys.flags.isolated, "producer self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "producer self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), "missing scripts/bootstrap_task_producers.py"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "producer import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_public_api(module: ModuleType) -> None:
    expected_parameters = {
        "sign_ed25519": ("seed", "message"),
        "ed25519_public_key_from_seed": ("seed",),
        "produce_bootstrap_authority_policy": (
            "id",
            "version",
            "principals",
            "taskRules",
            "requiredTestSetRule",
            "formalCatalogRule",
            "bootstrapSetRule",
            "sessionContainmentRule",
            "freshnessAuthorityRule",
            "privateScanRule",
            "privateScanPolicy",
            "revocationSnapshotRule",
            "authorityStoreService",
            "verifier",
        ),
        "produce_required_test_set": (
            "id",
            "version",
            "phase5Document",
            "authorityPolicy",
            "requiredTestIds",
            "signers",
            "authority_policy_bytes",
        ),
        "produce_task_approval": (
            "taskId",
            "candidate",
            "taskBreakdown",
            "requiredTestSet",
            "testIds",
            "evidence",
            "dependencyCompletions",
            "prerequisiteDocuments",
            "authorityPolicy",
            "stage0Handoff",
            "independentReviews",
            "signers",
        ),
        "produce_bootstrap_task_verifier_receipt": (
            "id",
            "taskId",
            "candidate",
            "authorityPolicy",
            "requiredTestSet",
            "taskApproval",
            "stage0Handoff",
            "dependencyCompletions",
            "verifierDigest",
            "signer",
        ),
        "produce_bootstrap_approval_set": (
            "id",
            "version",
            "candidate",
            "authorityPolicy",
            "taskBreakdown",
            "requiredTestSet",
            "stage0Handoff",
            "taskApprovals",
            "taskReceipts",
            "signers",
        ),
        "produce_bootstrap_approval_verifier_receipt": (
            "id",
            "candidate",
            "authorityPolicy",
            "requiredTestSet",
            "approvalSet",
            "stage0Handoff",
            "verifierDigest",
            "taskApprovals",
            "taskReceipts",
            "signer",
        ),
        "produce_formal_gate_catalog_approval": (
            "id",
            "version",
            "authorityPolicy",
            "requiredTestSet",
            "catalog",
            "signers",
            "authority_policy_bytes",
        ),
    }
    for name, expected_names in expected_parameters.items():
        entry = getattr(module, name, None)
        assert callable(entry), f"missing callable {name}"
        parameters = tuple(inspect.signature(entry).parameters.values())
        assert tuple(parameter.name for parameter in parameters) == expected_names, (
            f"{name} parameters must be exactly the object fields plus "
            "explicit signer inputs"
        )
        assert all(
            parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
            and parameter.default is inspect.Parameter.empty
            for parameter in parameters
        ), f"{name} arguments must all be required explicit inputs"
        for parameter in parameters:
            lowered = parameter.name.lower()
            assert not any(
                forbidden in lowered
                for forbidden in ("path", "file", "env", "fd")
            ), (
                f"{name}.{parameter.name} must not resemble a key-file or "
                "environment selector"
            )
    for forbidden_attribute in (
        "os",
        "random",
        "getenv",
        "open",
        "input",
        "socket",
        "subprocess",
    ):
        assert not hasattr(module, forbidden_attribute), (
            f"producer must not import a key-material channel: "
            f"{forbidden_attribute}"
        )


def assert_rejected(module: ModuleType, operation: Callable[[], object]) -> object:
    rejected_type = module.Rejected
    try:
        result = operation()
    except rejected_type as rejected:
        result = rejected
    assert isinstance(result, rejected_type), "invalid input must produce Rejected"
    assert result.code == BOOTSTRAP_REJECTION, "rejection must keep the stable code"
    return result


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
    """Build the strict synthetic PHASE-5 authority snapshot."""
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


def normative_document_ref_wire(identifier: str, review_commit: str) -> dict:
    raw_bytes = f"synthetic normative document {identifier}\n".encode("ascii")
    content_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00"
        + identifier.encode("ascii")
        + b"\x00"
        + raw_bytes
    ).digest()
    return {
        "id": identifier,
        "contentDigest": digest_text(content_digest),
        "status": "accepted",
        "reviewCommit": review_commit,
        "reviewLink": f"https://review.example/{identifier.lower()}",
        "approvedAt": "2026-07-16",
        "approvers": ["principal-architecture", "principal-quality"],
    }


def normative_document_ref(consumer: ModuleType, identifier: str, review_commit: str) -> object:
    wire = normative_document_ref_wire(identifier, review_commit)
    return consumer.NormativeDocumentRefV1(
        id=wire["id"],
        contentDigest=consumer.parse_digest(wire["contentDigest"]),
        status="accepted",
        reviewCommit=wire["reviewCommit"],
        reviewLink=wire["reviewLink"],
        approvedAt=wire["approvedAt"],
        approvers=tuple(wire["approvers"]),
    )


def independent_review_report_bytes(label: str) -> bytes:
    return f"approved review by {label}\n".encode("ascii")


def independent_review_report_digest(raw: bytes) -> bytes:
    return hashlib.sha256(
        b"pf.independent-review-report.v1\x00" + raw
    ).digest()


def eligible_stage0_handoff_wire(
    consumer: ModuleType,
    policy: object,
    policy_ref: object,
    candidate_wire: dict,
) -> dict:
    policy_ref_wire = content_ref_wire(policy_ref)
    store_ref = content_ref_wire(getattr(policy, "authorityStoreService"))
    verifier = getattr(policy, "verifier")
    executable_digest = getattr(verifier, "executableDigest")
    return {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": "bootstrap-stage0-handoff",
        "version": "1.0.0",
        "runId": "bootstrap-run-20260717-0001",
        "nonce": "70" * 32,
        "candidate": copy.deepcopy(candidate_wire),
        "authorityPolicy": policy_ref_wire,
        "authorityStoreService": store_ref,
        "hostObservation": {
            "schema": "proof-forge.host-observation.v1",
            "id": "eligible-host-observation",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("71" * 32)),
        },
        "hostProfile": {
            "schema": "proof-forge.host-profile.v1",
            "id": "eligible-host-profile",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("72" * 32)),
        },
        "eligible": True,
        "tcb": {
            "stage0VerifierDigest": digest_text(bytes.fromhex("73" * 32)),
            "bootstrapVerifierDigest": digest_text(
                getattr(executable_digest, "bytes")
            ),
            "continuationDigest": digest_text(bytes.fromhex("74" * 32)),
            "formalFinalizerDigest": digest_text(bytes.fromhex("75" * 32)),
        },
        "environment": {
            "mode": "env-i",
            "home": "/var/empty",
            "path": "/usr/bin:/bin",
            "lcAll": "C",
            "tz": "UTC",
            "network": "deny-default",
        },
        "channels": [
            {
                "role": "authority-policy",
                "fd": 3,
                "transport": "regular-file",
                "access": "read-only",
                "bindingDigest": policy_ref_wire["digest"],
            },
            {
                "role": "authority-store",
                "fd": 4,
                "transport": "authenticated-stream",
                "access": "request-response",
                "bindingDigest": store_ref["digest"],
            },
            {
                "role": "candidate-archive",
                "fd": 5,
                "transport": "regular-file",
                "access": "read-only",
                "bindingDigest": candidate_wire["archiveDigest"],
            },
            {
                "role": "evidence-root",
                "fd": 6,
                "transport": "regular-file",
                "access": "read-only",
                "bindingDigest": digest_text(bytes.fromhex("76" * 32)),
            },
        ],
        "pathnameReopen": False,
        "fallback": "none",
    }


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


def formal_gate_catalog_wire(required_set_ref_wire: dict) -> dict:
    # Root wire form mirrors the existing gate catalog family; gate internals
    # stay a minimal placeholder because this consumer family deliberately
    # does not validate gate-level content semantics.
    return {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "formal-alpha-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": copy.deepcopy(required_set_ref_wire),
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


def build_bootstrap_context(module: ModuleType) -> dict[str, object]:
    """Produce the complete six-task bootstrap object chain with producers."""
    consumer = module._CONSUMER

    def digest(raw: bytes) -> object:
        return consumer.Digest("sha256", raw)

    principals = tuple(
        consumer.BootstrapAuthorityPrincipalV1(
            principalId=f"principal-{role}",
            keyId=f"key-{role}",
            publicKey=module.ed25519_public_key_from_seed(SEEDS_BY_KEY_ID[f"key-{role}"]),
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
    task_rules = tuple(
        consumer.BootstrapAuthorityTaskRuleV1(
            taskId=task_id,
            rule=consumer.ApprovalRuleV1(roles, minimum),
        )
        for task_id, roles, minimum in task_rule_specs
    )
    verifier = consumer.BootstrapAuthorityVerifierV1(
        id="bootstrap-task-verifier",
        executableDigest=digest(bytes.fromhex("43" * 32)),
        receiptKeyId="key-verifier-receipt",
        receiptPublicKey=module.ed25519_public_key_from_seed(
            SEEDS_BY_KEY_ID["key-verifier-receipt"]
        ),
    )
    policy_inputs = {
        "id": "bootstrap-authority-root",
        "version": "1.0.0",
        "principals": principals,
        "taskRules": task_rules,
        "requiredTestSetRule": consumer.ApprovalRuleV1(("quality", "security"), 2),
        "formalCatalogRule": consumer.ApprovalRuleV1(("quality", "security"), 2),
        "bootstrapSetRule": consumer.ApprovalRuleV1(
            ("quality", "security", "release"), 3
        ),
        "sessionContainmentRule": consumer.ApprovalRuleV1(
            ("quality", "security"), 2
        ),
        "freshnessAuthorityRule": consumer.ApprovalRuleV1(("quality", "release"), 2),
        "privateScanRule": consumer.ApprovalRuleV1(("quality", "security"), 2),
        "privateScanPolicy": consumer.ContentRef(
            "proof-forge.private-scan-policy.v1",
            "bootstrap-private-scan-policy",
            "1.0.0",
            digest(bytes.fromhex("41" * 32)),
        ),
        "revocationSnapshotRule": consumer.ApprovalRuleV1(
            ("security", "release"), 2
        ),
        "authorityStoreService": consumer.ContentRef(
            "proof-forge.authority-store-service.v1",
            "bootstrap-authority-store",
            "1.0.0",
            digest(bytes.fromhex("42" * 32)),
        ),
        "verifier": verifier,
    }
    policy_bytes = module.produce_bootstrap_authority_policy(**policy_inputs)
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
    phase5_document = consumer.NormativeDocumentRefV1(
        id=document_wire["id"],
        contentDigest=consumer.parse_digest(document_wire["contentDigest"]),
        status="accepted",
        reviewCommit=document_wire["reviewCommit"],
        reviewLink=document_wire["reviewLink"],
        approvedAt=document_wire["approvedAt"],
        approvers=tuple(document_wire["approvers"]),
    )
    required_bytes = module.produce_required_test_set(
        id="phase-5-required-tests",
        version="1.0.0",
        phase5Document=phase5_document,
        authorityPolicy=policy_ref,
        requiredTestIds=required_ids,
        signers=(
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    required_set, required_ref = consumer.parse_document_bound_required_test_set(
        required_bytes,
        policy_bytes,
        phase5_snapshot,
    )

    candidate_wire = candidate_identity_wire(consumer)
    candidate = consumer.parse_candidate_identity(candidate_wire)
    handoff_wire = eligible_stage0_handoff_wire(
        consumer, policy, policy_ref, candidate_wire
    )
    handoff_bytes = consumer.canonical_pf_jcs(handoff_wire)
    handoff_ref = consumer._preflight_eligible_stage0_handoff(
        handoff_bytes
    ).handoffRef

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
        reviews = tuple(
            consumer.IndependentReviewRefV1(
                keyId=key_id,
                role=role,
                reviewCommit=candidate.commit,
                reviewLink=f"https://review.example/{task_id.lower()}/{key_id}",
                reportDigest=digest(independent_review_report_digest(
                    independent_review_report_bytes(f"{task_id}:{key_id}")
                )),
                decision="approved",
            )
            for key_id, role in row["signers"]
        )
        approval_bytes = module.produce_task_approval(
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
            independentReviews=reviews,
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
        receipt_bytes = module.produce_bootstrap_task_verifier_receipt(
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
        receipt, receipt_ref = consumer.parse_bootstrap_task_verifier_receipt(
            receipt_bytes,
            approval_bytes,
            required_bytes,
            policy_bytes,
            phase5_snapshot,
            handoff_bytes,
        )
        built[task_id] = {
            "approval": approval,
            "approvalRef": approval_ref,
            "approvalBytes": approval_bytes,
            "receipt": receipt,
            "receiptRef": receipt_ref,
            "receiptBytes": receipt_bytes,
        }

    six_receipt_bytes = tuple(built[task_id]["receiptBytes"] for task_id in D0_TASK_IDS)
    set_bytes = module.produce_bootstrap_approval_set(
        id="bootstrap-approval-set",
        version="1.0.0",
        candidate=candidate,
        authorityPolicy=policy_ref,
        taskBreakdown=phase4_ref,
        requiredTestSet=required_ref,
        stage0Handoff=handoff_ref,
        taskApprovals=tuple(built[task_id]["approval"] for task_id in D0_TASK_IDS),
        taskReceipts=tuple(
            built[task_id]["receiptRef"] for task_id in D0_TASK_IDS
        ),
        signers=(
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
            ("key-release", SEEDS_BY_KEY_ID["key-release"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
        ),
    )
    approval_set, set_ref = consumer.parse_bootstrap_approval_set(
        set_bytes,
        six_receipt_bytes,
        required_bytes,
        policy_bytes,
        phase5_snapshot,
        handoff_bytes,
    )
    bav_bytes = module.produce_bootstrap_approval_verifier_receipt(
        id="BAV-20260717-0001",
        candidate=candidate,
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        approvalSet=set_ref,
        stage0Handoff=handoff_ref,
        verifierDigest=policy.verifier.executableDigest,
        taskApprovals=tuple(
            built[task_id]["approvalRef"] for task_id in D0_TASK_IDS
        ),
        taskReceipts=tuple(built[task_id]["receiptRef"] for task_id in D0_TASK_IDS),
        signer=(
            "key-verifier-receipt",
            SEEDS_BY_KEY_ID["key-verifier-receipt"],
        ),
    )
    bav_receipt, bav_ref = consumer.parse_bootstrap_approval_verifier_receipt(
        bav_bytes,
        set_bytes,
        six_receipt_bytes,
        required_bytes,
        policy_bytes,
        phase5_snapshot,
        handoff_bytes,
    )

    catalog_wire = formal_gate_catalog_wire(content_ref_wire(required_ref))
    catalog_bytes = consumer.canonical_pf_jcs(catalog_wire)
    catalog_ref = consumer.GateCatalogRefV1(
        "proof-forge.gate-catalog.v1",
        catalog_wire["id"],
        catalog_wire["version"],
        hashlib.sha256(catalog_bytes).hexdigest(),
        hashlib.sha256(b"pf.gate-catalog.v1\x00" + catalog_bytes).hexdigest(),
    )
    catalog_approval_bytes = module.produce_formal_gate_catalog_approval(
        id="formal-catalog-approval",
        version="1.0.0",
        authorityPolicy=policy_ref,
        requiredTestSet=required_ref,
        catalog=catalog_ref,
        signers=(
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    catalog_approval, catalog_approval_digest = (
        consumer.parse_formal_gate_catalog_approval(
            catalog_approval_bytes,
            catalog_bytes,
            required_bytes,
            policy_bytes,
        )
    )
    return {
        "policyInputs": policy_inputs,
        "policyBytes": policy_bytes,
        "policy": policy,
        "policyRef": policy_ref,
        "phase5Snapshot": phase5_snapshot,
        "requiredBytes": required_bytes,
        "requiredSet": required_set,
        "requiredRef": required_ref,
        "requiredIds": required_ids,
        "candidate": candidate,
        "candidateWire": candidate_wire,
        "handoffBytes": handoff_bytes,
        "handoffRef": handoff_ref,
        "phase4Ref": phase4_ref,
        "built": built,
        "sixReceiptBytes": six_receipt_bytes,
        "setBytes": set_bytes,
        "approvalSet": approval_set,
        "setRef": set_ref,
        "bavBytes": bav_bytes,
        "bavReceipt": bav_receipt,
        "bavRef": bav_ref,
        "catalogBytes": catalog_bytes,
        "catalogRef": catalog_ref,
        "catalogApprovalBytes": catalog_approval_bytes,
        "catalogApproval": catalog_approval,
        "catalogApprovalDigest": catalog_approval_digest,
    }


def test_sign_primitive(module: ModuleType) -> None:
    consumer = module._CONSUMER
    architecture_seed = SEEDS_BY_KEY_ID["key-architecture"]
    quality_seed = SEEDS_BY_KEY_ID["key-quality"]
    for key_id, seed in SEEDS_BY_KEY_ID.items():
        derived = module.ed25519_public_key_from_seed(seed)
        assert derived.hex() == EXPECTED_PUBLIC_KEYS[key_id], (
            f"derived public key for {key_id} must match the RFC 8032 vector"
        )
    signature = module.sign_ed25519(architecture_seed, RFC_8032_TEST1_MESSAGE)
    assert signature.hex() == RFC_8032_TEST1_SIGNATURE, (
        "RFC 8032 TEST 1 signature must be reproduced exactly"
    )
    assert consumer.verify_ed25519(
        bytes.fromhex(EXPECTED_PUBLIC_KEYS["key-architecture"]),
        RFC_8032_TEST1_MESSAGE,
        signature,
    ), "consumer verifier must accept the produced RFC 8032 TEST 1 signature"
    signature2 = module.sign_ed25519(quality_seed, RFC_8032_TEST2_MESSAGE)
    assert signature2.hex() == RFC_8032_TEST2_SIGNATURE, (
        "RFC 8032 TEST 2 signature must be reproduced exactly"
    )
    assert consumer.verify_ed25519(
        bytes.fromhex(EXPECTED_PUBLIC_KEYS["key-quality"]),
        RFC_8032_TEST2_MESSAGE,
        signature2,
    )
    assert not consumer.verify_ed25519(
        bytes.fromhex(EXPECTED_PUBLIC_KEYS["key-quality"]),
        b"\x73",
        signature2,
    ), "consumer verifier must reject a message substitution"
    assert not consumer.verify_ed25519(
        bytes.fromhex(EXPECTED_PUBLIC_KEYS["key-architecture"]),
        RFC_8032_TEST2_MESSAGE,
        signature2,
    ), "consumer verifier must reject a public-key substitution"

    for label, operation in (
        ("seed shorter than 32 bytes", lambda: module.sign_ed25519(b"\x01" * 31, b"m")),
        ("seed longer than 32 bytes", lambda: module.sign_ed25519(b"\x01" * 33, b"m")),
        ("seed as hex text", lambda: module.sign_ed25519("ab" * 32, b"m")),
        ("seed as None", lambda: module.sign_ed25519(None, b"m")),
        ("message as text", lambda: module.sign_ed25519(quality_seed, "m")),
        ("message as None", lambda: module.sign_ed25519(quality_seed, None)),
        (
            "public-key derivation with short seed",
            lambda: module.ed25519_public_key_from_seed(b"\x01" * 31),
        ),
        (
            "public-key derivation with text seed",
            lambda: module.ed25519_public_key_from_seed("ab" * 32),
        ),
    ):
        rejected = assert_rejected(module, operation)
        assert "ab" * 32 not in str(rejected), (
            f"{label} rejection must not echo seed material"
        )
        assert "01010101" not in str(rejected), (
            f"{label} rejection must not echo seed material"
        )


def test_key_custody(module: ModuleType, context: dict[str, object]) -> None:
    produced_keys = (
        "policyBytes",
        "requiredBytes",
        "setBytes",
        "bavBytes",
        "catalogApprovalBytes",
    )
    for key in produced_keys:
        assert type(context[key]) is bytes, (
            f"producer output {key} must be bare canonical bytes"
        )
    for task_id in D0_TASK_IDS:
        built = context["built"]
        assert isinstance(built, dict)
        assert type(built[task_id]["approvalBytes"]) is bytes
        assert type(built[task_id]["receiptBytes"]) is bytes
    short_seed = bytes(range(31))
    rejected = assert_rejected(
        module,
        lambda: module.sign_ed25519(short_seed, b"message"),
    )
    assert getattr(rejected, "detail") == "signing seed must be exact 32-byte bytes", (
        "seed-shape rejection must use the fixed no-leak detail"
    )
    assert short_seed.hex() not in str(rejected)


def test_policy_producer(module: ModuleType, context: dict[str, object]) -> None:
    consumer = module._CONSUMER
    policy = context["policy"]
    policy_inputs = context["policyInputs"]
    assert isinstance(policy_inputs, dict)
    assert policy == consumer.BootstrapAuthorityPolicyV1(
        "proof-forge.bootstrap-authority-policy.v1",
        "bootstrap-authority-root",
        "1.0.0",
        policy_inputs["principals"],
        policy_inputs["taskRules"],
        policy_inputs["requiredTestSetRule"],
        policy_inputs["formalCatalogRule"],
        policy_inputs["bootstrapSetRule"],
        policy_inputs["sessionContainmentRule"],
        policy_inputs["freshnessAuthorityRule"],
        policy_inputs["privateScanRule"],
        policy_inputs["privateScanPolicy"],
        policy_inputs["revocationSnapshotRule"],
        policy_inputs["authorityStoreService"],
        policy_inputs["verifier"],
    ), "produced policy must round-trip every typed field"
    policy_ref = context["policyRef"]
    policy_bytes = context["policyBytes"]
    assert isinstance(policy_bytes, bytes)
    expected_ref = consumer.ContentRef(
        "proof-forge.bootstrap-authority-policy.v1",
        "bootstrap-authority-root",
        "1.0.0",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-authority-policy.v1\x00" + policy_bytes
            ).digest(),
        ),
    )
    assert policy_ref == expected_ref, "policy ref must recompute the domain digest"

    def produce_with(**overrides: object) -> bytes:
        inputs = dict(policy_inputs)
        inputs.update(overrides)
        return module.produce_bootstrap_authority_policy(**inputs)

    weak_set_rule = consumer.ApprovalRuleV1(("quality", "security", "release"), 2)
    colliding_verifier = consumer.BootstrapAuthorityVerifierV1(
        id="bootstrap-task-verifier",
        executableDigest=consumer.Digest("sha256", bytes.fromhex("43" * 32)),
        receiptKeyId="key-quality",
        receiptPublicKey=module.ed25519_public_key_from_seed(
            SEEDS_BY_KEY_ID["key-verifier-receipt"]
        ),
    )
    reordered_principals = tuple(reversed(policy_inputs["principals"]))
    for label, overrides in (
        ("bootstrapSetRule below the hard minimum", {"bootstrapSetRule": weak_set_rule}),
        ("verifier keyId collides with a principal", {"verifier": colliding_verifier}),
        ("principals not ascending by keyId", {"principals": reordered_principals}),
        (
            "verifier parameter with wrong type",
            {"verifier": context["policyRef"]},
        ),
        (
            "privateScanPolicy parameter with wrong type",
            {"privateScanPolicy": context["candidate"]},
        ),
    ):
        assert_rejected(module, lambda overrides=overrides: produce_with(**overrides))


def test_required_set_producer(module: ModuleType, context: dict[str, object]) -> None:
    consumer = module._CONSUMER
    required_set = context["requiredSet"]
    required_ids = context["requiredIds"]
    assert isinstance(required_ids, tuple)
    assert required_set.requiredTestIds == required_ids
    assert required_set.authorityPolicy == context["policyRef"]
    assert tuple(signature.keyId for signature in required_set.signatures) == (
        "key-quality",
        "key-security",
    ), "producer must assemble signatures in ascending keyId order"
    required_bytes = context["requiredBytes"]
    assert isinstance(required_bytes, bytes)
    decoded = consumer.decode_canonical_pf_jcs(required_bytes)
    assert decoded["signatures"][0]["keyId"] == "key-quality"
    required_ref = context["requiredRef"]
    expected_ref = consumer.ContentRef(
        "proof-forge.required-test-set.v1",
        "phase-5-required-tests",
        "1.0.0",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.required-test-set.v1\x00" + required_bytes
            ).digest(),
        ),
    )
    assert required_ref == expected_ref

    policy_ref = context["policyRef"]
    phase5_snapshot = context["phase5Snapshot"]
    policy_bytes = context["policyBytes"]
    assert isinstance(policy_bytes, bytes)
    base_inputs = dict(
        id="phase-5-required-tests",
        version="1.0.0",
        phase5Document=required_set.phase5Document,
        authorityPolicy=policy_ref,
        requiredTestIds=required_ids,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )

    def produce_with(**overrides: object) -> bytes:
        inputs = dict(base_inputs)
        inputs.update(overrides)
        return module.produce_required_test_set(**inputs)

    drifted_policy_ref = consumer.ContentRef(
        policy_ref.schema,
        policy_ref.id,
        policy_ref.version,
        consumer.Digest("sha256", bytes.fromhex("c6" * 32)),
    )
    for label, overrides in (
        ("empty signer tuple", {"signers": ()}),
        (
            "duplicate signer keyId",
            {
                "signers": (
                    ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
                    ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
                ),
            },
        ),
        (
            "signer entry missing the seed",
            {"signers": (("key-quality",),)},
        ),
        (
            "signer entry with text seed",
            {"signers": (("key-quality", "ab" * 32),)},
        ),
        (
            "under-quorum single signer",
            {"signers": (("key-quality", SEEDS_BY_KEY_ID["key-quality"]),)},
        ),
        (
            "unknown signer keyId",
            {"signers": (("key-unlisted", SEEDS_BY_KEY_ID["key-quality"]),)},
        ),
        (
            "impersonated quality signature",
            {
                "signers": (
                    ("key-quality", SEEDS_BY_KEY_ID["key-security"]),
                    ("key-security", SEEDS_BY_KEY_ID["key-security"]),
                ),
            },
        ),
        (
            "authority policy ref digest join",
            {"authorityPolicy": drifted_policy_ref},
        ),
        (
            "phase5Document parameter with wrong type",
            {"phase5Document": policy_ref},
        ),
    ):
        assert_rejected(module, lambda overrides=overrides: produce_with(**overrides))

    tampered = consumer.decode_canonical_pf_jcs(required_bytes)
    tampered["requiredTestIds"] = sorted(list(tampered["requiredTestIds"]) + ["TST-TAMPER-001"])
    assert_rejected(
        module,
        lambda: consumer.parse_required_test_set(
            consumer.canonical_pf_jcs(tampered),
            policy_bytes,
        ),
    )
    assert_rejected(
        module,
        lambda: consumer.parse_required_test_set(b"{", policy_bytes),
    )


def test_task_approval_producer(module: ModuleType, context: dict[str, object]) -> None:
    consumer = module._CONSUMER
    built = context["built"]
    assert isinstance(built, dict)
    root = built["TASK-D0-01"]
    approval = root["approval"]
    approval_ref = root["approvalRef"]
    approval_bytes = root["approvalBytes"]
    assert isinstance(approval_bytes, bytes)
    assert approval.taskId == "TASK-D0-01"
    assert approval.candidate == context["candidate"]
    assert approval.requiredTestSet == context["requiredRef"]
    assert approval.stage0Handoff == context["handoffRef"]
    assert tuple(signature.keyId for signature in approval.signatures) == (
        "key-architecture",
        "key-quality",
    )
    expected_ref = consumer.TaskApprovalRefV1(
        "TASK-D0-01",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
            ).digest(),
        ),
    )
    assert approval_ref == expected_ref

    base_inputs = dict(
        taskId="TASK-D0-01",
        candidate=context["candidate"],
        taskBreakdown=context["phase4Ref"],
        requiredTestSet=context["requiredRef"],
        testIds=("TST-DOC-001",),
        evidence=(
            consumer.EvidenceRef(
                id="EV-20260717-0001",
                digest=consumer.Digest("sha256", bytes.fromhex("61" * 32)),
            ),
        ),
        dependencyCompletions=(),
        prerequisiteDocuments=tuple(
            normative_document_ref(consumer, identifier, "a" * 40)
            for identifier in ("PHASE-1", "PHASE-2", "PHASE-3")
        ),
        authorityPolicy=context["policyRef"],
        stage0Handoff=context["handoffRef"],
        independentReviews=(
            consumer.IndependentReviewRefV1(
                keyId="key-architecture",
                role="architecture",
                reviewCommit="a" * 40,
                reviewLink="https://review.example/task-d0-01/key-architecture",
                reportDigest=consumer.Digest(
                    "sha256",
                    independent_review_report_digest(
                        independent_review_report_bytes(
                            "TASK-D0-01:key-architecture"
                        )
                    ),
                ),
                decision="approved",
            ),
            consumer.IndependentReviewRefV1(
                keyId="key-quality",
                role="quality",
                reviewCommit="a" * 40,
                reviewLink="https://review.example/task-d0-01/key-quality",
                reportDigest=consumer.Digest(
                    "sha256",
                    independent_review_report_digest(
                        independent_review_report_bytes("TASK-D0-01:key-quality")
                    ),
                ),
                decision="approved",
            ),
        ),
        signers=(
            ("key-architecture", SEEDS_BY_KEY_ID["key-architecture"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
        ),
    )

    def produce_with(**overrides: object) -> bytes:
        inputs = dict(base_inputs)
        inputs.update(overrides)
        return module.produce_task_approval(**inputs)

    for label, overrides in (
        ("testIds not ascending", {"testIds": ("TST-ISO-001", "TST-DOC-001")}),
        (
            "candidate parameter with wrong type",
            {"candidate": context["policyRef"]},
        ),
        (
            "evidence entry with wrong type",
            {"evidence": (context["policyRef"],)},
        ),
        (
            "empty signer tuple",
            {"signers": ()},
        ),
    ):
        assert_rejected(module, lambda overrides=overrides: produce_with(**overrides))

    impersonated_bytes = produce_with(
        signers=(
            ("key-architecture", SEEDS_BY_KEY_ID["key-architecture"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-security"]),
        ),
    )
    assert type(impersonated_bytes) is bytes, (
        "impersonation is not a producer-side failure without the policy"
    )
    assert_rejected(
        module,
        lambda: consumer.parse_task_approval(
            impersonated_bytes,
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
        ),
    )

    tampered = consumer.decode_canonical_pf_jcs(approval_bytes)
    tampered["testIds"] = ["TST-TAMPER-001"]
    assert_rejected(
        module,
        lambda: consumer.parse_task_approval(
            consumer.canonical_pf_jcs(tampered),
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
        ),
    )


def test_task_receipt_producer(module: ModuleType, context: dict[str, object]) -> None:
    consumer = module._CONSUMER
    built = context["built"]
    assert isinstance(built, dict)
    root = built["TASK-D0-01"]
    receipt = root["receipt"]
    receipt_ref = root["receiptRef"]
    receipt_bytes = root["receiptBytes"]
    assert isinstance(receipt_bytes, bytes)
    assert receipt.id == "BTV-20260717-0001"
    assert receipt.taskApproval == root["approvalRef"]
    assert receipt.result == "task-approved"
    assert receipt.signature.keyId == "key-verifier-receipt"
    expected_ref = consumer.BootstrapTaskVerifierReceiptRefV1(
        "TASK-D0-01",
        "BTV-20260717-0001",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-task-verifier-receipt.v1\x00" + receipt_bytes
            ).digest(),
        ),
    )
    assert receipt_ref == expected_ref

    base_inputs = dict(
        id="BTV-20260717-0001",
        taskId="TASK-D0-01",
        candidate=context["candidate"],
        authorityPolicy=context["policyRef"],
        requiredTestSet=context["requiredRef"],
        taskApproval=root["approvalRef"],
        stage0Handoff=context["handoffRef"],
        dependencyCompletions=(),
        verifierDigest=context["policy"].verifier.executableDigest,
        signer=(
            "key-verifier-receipt",
            SEEDS_BY_KEY_ID["key-verifier-receipt"],
        ),
    )

    def produce_with(**overrides: object) -> bytes:
        inputs = dict(base_inputs)
        inputs.update(overrides)
        return module.produce_bootstrap_task_verifier_receipt(**inputs)

    for label, overrides in (
        ("malformed receipt ID grammar", {"id": "BTV-2026071-0001"}),
        (
            "verifierDigest parameter with wrong type",
            {"verifierDigest": context["policyRef"]},
        ),
        (
            "signer with text seed",
            {"signer": ("key-verifier-receipt", "ab" * 32)},
        ),
    ):
        assert_rejected(module, lambda overrides=overrides: produce_with(**overrides))

    wrong_key_bytes = produce_with(
        signer=("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
    )
    assert type(wrong_key_bytes) is bytes
    assert_rejected(
        module,
        lambda: consumer.parse_bootstrap_task_verifier_receipt(
            wrong_key_bytes,
            root["approvalBytes"],
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
            context["handoffBytes"],
        ),
    )

    tampered = consumer.decode_canonical_pf_jcs(receipt_bytes)
    tampered["result"] = "task-rejected"
    assert_rejected(
        module,
        lambda: consumer.parse_bootstrap_task_verifier_receipt(
            consumer.canonical_pf_jcs(tampered),
            root["approvalBytes"],
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
            context["handoffBytes"],
        ),
    )


def test_approval_set_and_verifier_receipt_producers(
    module: ModuleType,
    context: dict[str, object],
) -> None:
    consumer = module._CONSUMER
    built = context["built"]
    assert isinstance(built, dict)
    approval_set = context["approvalSet"]
    expected_approvals = tuple(built[task_id]["approval"] for task_id in D0_TASK_IDS)
    expected_receipt_refs = tuple(
        built[task_id]["receiptRef"] for task_id in D0_TASK_IDS
    )
    assert approval_set.taskApprovals == expected_approvals, (
        "produced set must embed the exact six signed approvals"
    )
    assert approval_set.taskReceipts == expected_receipt_refs
    assert tuple(signature.keyId for signature in approval_set.signatures) == (
        "key-quality",
        "key-release",
        "key-security",
    )
    set_bytes = context["setBytes"]
    assert isinstance(set_bytes, bytes)
    set_ref = context["setRef"]
    expected_set_ref = consumer.ContentRef(
        "proof-forge.bootstrap-approval-set.v1",
        "bootstrap-approval-set",
        "1.0.0",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-approval-set.v1\x00" + set_bytes
            ).digest(),
        ),
    )
    assert set_ref == expected_set_ref

    bav_receipt = context["bavReceipt"]
    bav_ref = context["bavRef"]
    bav_bytes = context["bavBytes"]
    assert isinstance(bav_bytes, bytes)
    assert bav_receipt.id == "BAV-20260717-0001"
    assert bav_receipt.approvalSet == set_ref
    assert bav_receipt.taskApprovals == tuple(
        built[task_id]["approvalRef"] for task_id in D0_TASK_IDS
    )
    assert bav_receipt.taskReceipts == expected_receipt_refs
    assert bav_receipt.result == "bootstrap-approved"
    expected_bav_ref = consumer.BootstrapApprovalVerifierReceiptRefV1(
        "BAV-20260717-0001",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.bootstrap-approval-verifier-receipt.v1\x00" + bav_bytes
            ).digest(),
        ),
    )
    assert bav_ref == expected_bav_ref

    set_base_inputs = dict(
        id="bootstrap-approval-set",
        version="1.0.0",
        candidate=context["candidate"],
        authorityPolicy=context["policyRef"],
        taskBreakdown=context["phase4Ref"],
        requiredTestSet=context["requiredRef"],
        stage0Handoff=context["handoffRef"],
        taskApprovals=expected_approvals,
        taskReceipts=expected_receipt_refs,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-release", SEEDS_BY_KEY_ID["key-release"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
    )

    def produce_set_with(**overrides: object) -> bytes:
        inputs = dict(set_base_inputs)
        inputs.update(overrides)
        return module.produce_bootstrap_approval_set(**inputs)

    bav_base_inputs = dict(
        id="BAV-20260717-0001",
        candidate=context["candidate"],
        authorityPolicy=context["policyRef"],
        requiredTestSet=context["requiredRef"],
        approvalSet=set_ref,
        stage0Handoff=context["handoffRef"],
        verifierDigest=context["policy"].verifier.executableDigest,
        taskApprovals=tuple(built[task_id]["approvalRef"] for task_id in D0_TASK_IDS),
        taskReceipts=expected_receipt_refs,
        signer=(
            "key-verifier-receipt",
            SEEDS_BY_KEY_ID["key-verifier-receipt"],
        ),
    )

    def produce_bav_with(**overrides: object) -> bytes:
        inputs = dict(bav_base_inputs)
        inputs.update(overrides)
        return module.produce_bootstrap_approval_verifier_receipt(**inputs)

    for label, operation in (
        (
            "set with five approvals",
            lambda: produce_set_with(taskApprovals=expected_approvals[:-1]),
        ),
        (
            "set approvals out of task order",
            lambda: produce_set_with(
                taskApprovals=(expected_approvals[1],) + expected_approvals[:1]
                + expected_approvals[2:]
            ),
        ),
        (
            "set approval entry with wrong type",
            lambda: produce_set_with(
                taskApprovals=(context["policyRef"],) + expected_approvals[1:]
            ),
        ),
        (
            "BAV taskReceipts out of order",
            lambda: produce_bav_with(
                taskReceipts=(expected_receipt_refs[1],)
                + expected_receipt_refs[:1]
                + expected_receipt_refs[2:]
            ),
        ),
        (
            "BAV malformed ID grammar",
            lambda: produce_bav_with(id="BAV-2026071-0001"),
        ),
    ):
        assert_rejected(module, operation)

    tampered_set = consumer.decode_canonical_pf_jcs(set_bytes)
    tampered_set["taskReceipts"][0], tampered_set["taskReceipts"][1] = (
        tampered_set["taskReceipts"][1],
        tampered_set["taskReceipts"][0],
    )
    assert_rejected(
        module,
        lambda: consumer.parse_bootstrap_approval_set(
            consumer.canonical_pf_jcs(tampered_set),
            context["sixReceiptBytes"],
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
            context["handoffBytes"],
        ),
    )

    tampered_bav = consumer.decode_canonical_pf_jcs(bav_bytes)
    tampered_bav["verifierDigest"] = digest_text(bytes.fromhex("c3" * 32))
    assert_rejected(
        module,
        lambda: consumer.parse_bootstrap_approval_verifier_receipt(
            consumer.canonical_pf_jcs(tampered_bav),
            set_bytes,
            context["sixReceiptBytes"],
            context["requiredBytes"],
            context["policyBytes"],
            context["phase5Snapshot"],
            context["handoffBytes"],
        ),
    )


def test_catalog_approval_producer(module: ModuleType, context: dict[str, object]) -> None:
    consumer = module._CONSUMER
    catalog_approval = context["catalogApproval"]
    catalog_approval_digest = context["catalogApprovalDigest"]
    catalog_ref = context["catalogRef"]
    catalog_approval_bytes = context["catalogApprovalBytes"]
    assert isinstance(catalog_approval_bytes, bytes)
    assert catalog_approval.catalog == catalog_ref
    assert catalog_approval.authorityPolicy == context["policyRef"]
    assert catalog_approval.requiredTestSet == context["requiredRef"]
    assert tuple(signature.keyId for signature in catalog_approval.signatures) == (
        "key-quality",
        "key-security",
    )
    expected_digest = consumer.Digest(
        "sha256",
        hashlib.sha256(
            b"pf.formal-gate-catalog-approval.v1\x00" + catalog_approval_bytes
        ).digest(),
    )
    assert catalog_approval_digest == expected_digest

    base_inputs = dict(
        id="formal-catalog-approval",
        version="1.0.0",
        authorityPolicy=context["policyRef"],
        requiredTestSet=context["requiredRef"],
        catalog=catalog_ref,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=context["policyBytes"],
    )

    def produce_with(**overrides: object) -> bytes:
        inputs = dict(base_inputs)
        inputs.update(overrides)
        return module.produce_formal_gate_catalog_approval(**inputs)

    malformed_hex_ref = consumer.GateCatalogRefV1(
        catalog_ref.schema,
        catalog_ref.id,
        catalog_ref.version,
        catalog_ref.contentSha256,
        "zz" * 32,
    )
    for label, overrides in (
        (
            "under-quorum single signer",
            {"signers": (("key-quality", SEEDS_BY_KEY_ID["key-quality"]),)},
        ),
        (
            "unknown signer keyId",
            {"signers": (("key-unlisted", SEEDS_BY_KEY_ID["key-quality"]),)},
        ),
        (
            "impersonated quality signature",
            {
                "signers": (
                    ("key-quality", SEEDS_BY_KEY_ID["key-security"]),
                    ("key-security", SEEDS_BY_KEY_ID["key-security"]),
                ),
            },
        ),
        (
            "duplicate signer keyId",
            {
                "signers": (
                    ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
                    ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
                ),
            },
        ),
        (
            "catalog ref digest not lowercase hex",
            {"catalog": malformed_hex_ref},
        ),
        (
            "catalog parameter with wrong type",
            {"catalog": context["policyRef"]},
        ),
    ):
        assert_rejected(module, lambda overrides=overrides: produce_with(**overrides))

    descending_bytes = produce_with(
        signers=(
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
        ),
    )
    decoded = consumer.decode_canonical_pf_jcs(descending_bytes)
    assert tuple(
        signature["keyId"] for signature in decoded["signatures"]
    ) == ("key-quality", "key-security"), (
        "producer must assemble quorum signatures in ascending keyId order"
    )

    tampered = consumer.decode_canonical_pf_jcs(catalog_approval_bytes)
    tampered["catalog"]["catalogDigest"] = "c9" * 32
    assert_rejected(
        module,
        lambda: consumer.parse_formal_gate_catalog_approval(
            consumer.canonical_pf_jcs(tampered),
            context["catalogBytes"],
            context["requiredBytes"],
            context["policyBytes"],
        ),
    )


def main() -> int:
    try:
        module = load_producer()
        assert_public_api(module)
        test_sign_primitive(module)
        context = build_bootstrap_context(module)
        test_key_custody(module, context)
        test_policy_producer(module, context)
        test_required_set_producer(module, context)
        test_task_approval_producer(module, context)
        test_task_receipt_producer(module, context)
        test_approval_set_and_verifier_receipt_producers(module, context)
        test_catalog_approval_producer(module, context)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"bootstrap-task-producers-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    print("bootstrap-task-producers-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
