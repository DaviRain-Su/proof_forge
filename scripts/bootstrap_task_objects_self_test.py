#!/usr/bin/env python3
"""Acceptance tests for the dependency-free bootstrap task object consumer.

The production module is intentionally loaded from its exact sibling pathname:
isolated Python does not add the script directory to ``sys.path``, and this test
must not make a repository-relative import path into an authority selector.
"""

from __future__ import annotations

import copy
import dataclasses
import hashlib
import importlib.util
import inspect
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
    "evidenceManifestBytes",
)
BOOTSTRAP_APPROVAL_SET_TASK_IDS = tuple(
    f"TASK-D0-{index:02d}" for index in range(1, 7)
)
RFC_8032_PUBLIC_KEYS = (
    "d75a980182b10ab7d54bfed3c964073a"
    "0ee172f3daa62325af021a68f707511a",
    "3d4017c3e843895a92b70aa74d1b7ebc"
    "9c982ccf2ec4968cc0cd55f12af4660c",
    "fc51cd8e6218a1a38da47ed00230f058"
    "0816ed13ba3303ac5deb911548908025",
    "278117fc144c72340f67d0f2316e8386"
    "ceffbf2b2428c9c51fef7c597f1d426e",
    "ec172b93ad5e563bf4932c70e1245034"
    "c35467ef2efd4d64ebf819683467e2bf",
)
RFC_8032_SEEDS_BY_KEY_ID = {
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
}
RFC_8032_RECEIPT_SEED = bytes.fromhex(
    "833fe62409237b9d62ec77587520911e"
    "9a759cec1d19755b7da901b96dca3d42"
)
ED25519_BASEPOINT = "58" + "66" * 31
ED25519_MIXED_ORDER_POINT = "95" + "99" * 31


def ed25519_sign_from_rfc_seed(seed: bytes, message: bytes) -> tuple[bytes, bytes]:
    """Minimal test-only pure-Ed25519 signer for fixed RFC 8032 seeds."""
    field = 2**255 - 19
    subgroup_order = 2**252 + 27742317777372353535851937790883648493
    curve_d = (-121665 * pow(121666, field - 2, field)) % field

    def recover_x(y: int) -> int:
        xx = ((y * y - 1) * pow(curve_d * y * y + 1, field - 2, field)) % field
        x = pow(xx, (field + 3) // 8, field)
        if (x * x - xx) % field != 0:
            x = (x * pow(2, (field - 1) // 4, field)) % field
        assert (x * x - xx) % field == 0
        return field - x if x & 1 else x

    def add(
        left: tuple[int, int, int, int],
        right: tuple[int, int, int, int],
    ) -> tuple[int, int, int, int]:
        x1, y1, z1, t1 = left
        x2, y2, z2, t2 = right
        a = ((y1 - x1) * (y2 - x2)) % field
        b = ((y1 + x1) * (y2 + x2)) % field
        c = (2 * curve_d * t1 * t2) % field
        d = (2 * z1 * z2) % field
        e = (b - a) % field
        f = (d - c) % field
        g = (d + c) % field
        h = (b + a) % field
        return e * f % field, g * h % field, f * g % field, e * h % field

    def double(point: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        x, y, z, _ = point
        a = x * x % field
        b = y * y % field
        c = 2 * z * z % field
        d = -a % field
        e = ((x + y) * (x + y) - a - b) % field
        g = (d + b) % field
        f = (g - c) % field
        h = (d - b) % field
        return e * f % field, g * h % field, f * g % field, e * h % field

    base_y = 4 * pow(5, field - 2, field) % field
    base_x = recover_x(base_y)
    base = (base_x, base_y, 1, base_x * base_y % field)

    def scalar_multiply(scalar: int) -> tuple[int, int, int, int]:
        result = (0, 1, 1, 0)
        addend = base
        while scalar:
            if scalar & 1:
                result = add(result, addend)
            addend = double(addend)
            scalar >>= 1
        return result

    def encode(point: tuple[int, int, int, int]) -> bytes:
        x, y, z, _ = point
        inverse_z = pow(z, field - 2, field)
        affine_x = x * inverse_z % field
        affine_y = y * inverse_z % field
        encoded_y = affine_y | ((affine_x & 1) << 255)
        return encoded_y.to_bytes(32, "little")

    expanded = hashlib.sha512(seed).digest()
    secret_scalar_bytes = bytearray(expanded[:32])
    secret_scalar_bytes[0] &= 248
    secret_scalar_bytes[31] &= 63
    secret_scalar_bytes[31] |= 64
    secret_scalar = int.from_bytes(secret_scalar_bytes, "little")
    public_key = encode(scalar_multiply(secret_scalar))
    nonce = int.from_bytes(
        hashlib.sha512(expanded[32:] + message).digest(), "little"
    ) % subgroup_order
    encoded_r = encode(scalar_multiply(nonce))
    challenge = int.from_bytes(
        hashlib.sha512(encoded_r + public_key + message).digest(), "little"
    ) % subgroup_order
    scalar_s = (nonce + challenge * secret_scalar) % subgroup_order
    return public_key, encoded_r + scalar_s.to_bytes(32, "little")


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
    if not callable(getattr(module, "parse_bootstrap_approval_set", None)):
        raise AssertionError("missing callable parse_bootstrap_approval_set")
    if not isinstance(getattr(module, "BootstrapApprovalSetV1", None), type):
        raise AssertionError("missing type BootstrapApprovalSetV1")
    required_callables = (
        "canonical_pf_jcs",
        "decode_canonical_pf_jcs",
        "parse_digest",
        "parse_content_ref",
        "parse_candidate_identity",
        "parse_bootstrap_authority_policy",
        "parse_required_test_set",
        "parse_phase4_snapshot_content",
        "parse_phase5_snapshot_content",
        "parse_document_bound_required_test_set",
        "parse_task_approval",
        "parse_bootstrap_task_verifier_receipt",
        "parse_bootstrap_approval_set",
        "parse_bootstrap_approval_verifier_receipt",
        "parse_bootstrap_approval_verifier_receipt_ref",
        "parse_formal_gate_catalog_approval",
        "verify_ed25519",
        "verifyBootstrapTaskObjects",
    )
    required_types = (
        "Rejected",
        "Digest",
        "ContentRef",
        "CandidateIdentity",
        "ApprovalRuleV1",
        "BootstrapAuthorityPrincipalV1",
        "BootstrapAuthorityTaskRuleV1",
        "BootstrapAuthorityVerifierV1",
        "BootstrapAuthorityPolicyV1",
        "ApprovalSignatureV1",
        "NormativeDocumentRefV1",
        "RequiredTestSetV1",
        "Phase4TaskRowV1",
        "Phase4SnapshotContentV1",
        "Phase5SnapshotContentV1",
        "EvidenceRef",
        "BootstrapEvidenceRootManifestV1",
        "TaskApprovalRefV1",
        "BootstrapTaskVerifierReceiptRefV1",
        "IndependentReviewRefV1",
        "TaskApprovalV1",
        "Stage0ChannelV1",
        "EligibleStage0TcbV1",
        "EligibleStage0EnvironmentV1",
        "EligibleStage0HandoffV1",
        "BootstrapTaskVerifierReceiptV1",
        "BootstrapApprovalSetV1",
        "BootstrapApprovalVerifierReceiptV1",
        "BootstrapApprovalVerifierReceiptRefV1",
        "GateCatalogRefV1",
        "FormalGateCatalogApprovalV1",
        "BootstrapLedgerSubjectV1",
        "BootstrapDocumentSnapshotV1",
        "BootstrapTaskRowSubjectV1",
        "BootstrapTaskSubjectV1",
        "DependencyTaskObjectV1",
        "ReviewReportObjectV1",
        "BootstrapTaskObjectSetV1",
        "ObjectVerifiedV1",
    )
    for name in required_callables:
        assert callable(getattr(module, name, None)), f"missing callable {name}"
    for name in required_types:
        value = getattr(module, name, None)
        assert isinstance(value, type), f"missing type {name}"

    required_set_parameters = tuple(
        inspect.signature(module.parse_required_test_set).parameters.values()
    )
    assert tuple(parameter.name for parameter in required_set_parameters) == (
        "required_bytes", "authority_policy_bytes",
    ), "required-set parser must not expose a policy/ref/selector seam"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in required_set_parameters
    ), "required-set parser arguments must be exactly two required byte inputs"

    snapshot_parameters = tuple(
        inspect.signature(module.parse_phase5_snapshot_content).parameters.values()
    )
    assert tuple(parameter.name for parameter in snapshot_parameters) == (
        "phase5_snapshot",
    ), "Phase-5 snapshot parser must expose exactly one typed snapshot input"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in snapshot_parameters
    ), "Phase-5 snapshot parser argument must be required"

    phase4_snapshot_parameters = tuple(
        inspect.signature(module.parse_phase4_snapshot_content).parameters.values()
    )
    assert tuple(parameter.name for parameter in phase4_snapshot_parameters) == (
        "phase4_snapshot",
    ), "Phase-4 snapshot parser must expose exactly one typed snapshot input"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in phase4_snapshot_parameters
    ), "Phase-4 snapshot parser argument must be required"

    document_bound_parameters = tuple(
        inspect.signature(
            module.parse_document_bound_required_test_set
        ).parameters.values()
    )
    assert tuple(parameter.name for parameter in document_bound_parameters) == (
        "required_bytes",
        "authority_policy_bytes",
        "phase5_snapshot",
    ), "document-bound parser must not expose expected refs, IDs, or selectors"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in document_bound_parameters
    ), "document-bound parser arguments must be exactly three required inputs"

    task_approval_parameters = tuple(
        inspect.signature(module.parse_task_approval).parameters.values()
    )
    assert tuple(parameter.name for parameter in task_approval_parameters) == (
        "task_approval_bytes",
        "required_test_set_bytes",
        "authority_policy_bytes",
        "phase5_snapshot",
    ), "task-approval parser must expose exactly four authoritative inputs"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in task_approval_parameters
    ), "task-approval parser arguments must be exactly four required inputs"

    task_receipt_parameters = tuple(
        inspect.signature(
            module.parse_bootstrap_task_verifier_receipt
        ).parameters.values()
    )
    assert tuple(parameter.name for parameter in task_receipt_parameters) == (
        "task_receipt_bytes",
        "task_approval_bytes",
        "required_test_set_bytes",
        "authority_policy_bytes",
        "phase5_snapshot",
        "stage0_handoff_bytes",
    ), "task-receipt parser must expose exactly six authoritative inputs"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in task_receipt_parameters
    ), "task-receipt parser arguments must be exactly six required inputs"

    bootstrap_set_parameters = tuple(
        inspect.signature(
            module.parse_bootstrap_approval_set
        ).parameters.values()
    )
    expected_bootstrap_set_parameters = (
        "approval_set_bytes",
        "task_receipt_bytes",
        "required_test_set_bytes",
        "authority_policy_bytes",
        "phase5_snapshot",
        "stage0_handoff_bytes",
    )
    if tuple(
        parameter.name for parameter in bootstrap_set_parameters
    ) != expected_bootstrap_set_parameters:
        raise AssertionError(
            "bootstrap-set parser must expose exactly six authoritative inputs"
        )
    if not all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in bootstrap_set_parameters
    ):
        raise AssertionError(
            "bootstrap-set parser arguments must be exactly six required inputs"
        )

    verifier_receipt_parameters = tuple(
        inspect.signature(
            module.parse_bootstrap_approval_verifier_receipt
        ).parameters.values()
    )
    expected_verifier_receipt_parameters = (
        "verifier_receipt_bytes",
        "approval_set_bytes",
        "task_receipt_bytes",
        "required_test_set_bytes",
        "authority_policy_bytes",
        "phase5_snapshot",
        "stage0_handoff_bytes",
    )
    if tuple(
        parameter.name for parameter in verifier_receipt_parameters
    ) != expected_verifier_receipt_parameters:
        raise AssertionError(
            "verifier-receipt parser must expose exactly seven "
            "authoritative inputs"
        )
    if not all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in verifier_receipt_parameters
    ):
        raise AssertionError(
            "verifier-receipt parser arguments must be exactly seven "
            "required inputs"
        )

    verifier_receipt_ref_parameters = tuple(
        inspect.signature(
            module.parse_bootstrap_approval_verifier_receipt_ref
        ).parameters.values()
    )
    if tuple(
        parameter.name for parameter in verifier_receipt_ref_parameters
    ) != ("verifier_receipt_ref_bytes",):
        raise AssertionError(
            "verifier-receipt ref parser must expose exactly one "
            "wire-bytes input"
        )
    if not all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in verifier_receipt_ref_parameters
    ):
        raise AssertionError(
            "verifier-receipt ref parser argument must be required"
        )

    catalog_approval_parameters = tuple(
        inspect.signature(
            module.parse_formal_gate_catalog_approval
        ).parameters.values()
    )
    expected_catalog_approval_parameters = (
        "approval_bytes",
        "catalog_bytes",
        "required_test_set_bytes",
        "authority_policy_bytes",
    )
    if tuple(
        parameter.name for parameter in catalog_approval_parameters
    ) != expected_catalog_approval_parameters:
        raise AssertionError(
            "formal catalog approval parser must expose exactly four "
            "authoritative inputs"
        )
    if not all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in catalog_approval_parameters
    ):
        raise AssertionError(
            "formal catalog approval parser arguments must be exactly four "
            "required inputs"
        )

    expected_fields = {
        "Digest": ("algorithm", "bytes"),
        "ContentRef": ("schema", "id", "version", "digest"),
        "CandidateIdentity": ("commit", "treeObjectId", "archiveDigest", "digest"),
        "ApprovalRuleV1": ("requiredRoles", "minimumDistinctSigners"),
        "BootstrapAuthorityPrincipalV1": (
            "principalId", "keyId", "publicKey", "roles",
        ),
        "BootstrapAuthorityTaskRuleV1": ("taskId", "rule"),
        "BootstrapAuthorityVerifierV1": (
            "id", "executableDigest", "receiptKeyId", "receiptPublicKey",
        ),
        "BootstrapAuthorityPolicyV1": (
            "schema",
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
        "ApprovalSignatureV1": ("keyId", "algorithm", "signature"),
        "NormativeDocumentRefV1": (
            "id",
            "contentDigest",
            "status",
            "reviewCommit",
            "reviewLink",
            "approvedAt",
            "approvers",
        ),
        "RequiredTestSetV1": (
            "schema",
            "id",
            "version",
            "phase5Document",
            "authorityPolicy",
            "requiredTestIds",
            "signatures",
        ),
        "Phase4TaskRowV1": (
            "taskId",
            "dependencies",
            "prerequisiteDocumentIds",
            "testIds",
            "evidenceIds",
        ),
        "Phase4SnapshotContentV1": ("document", "bootstrapTaskRows"),
        "Phase5SnapshotContentV1": ("document", "requiredTestIds"),
        "EvidenceRef": ("id", "digest"),
        "BootstrapEvidenceRootManifestV1": (
            "schema", "taskId", "candidate", "evidence",
        ),
        "TaskApprovalRefV1": ("taskId", "digest"),
        "BootstrapTaskVerifierReceiptRefV1": ("taskId", "id", "digest"),
        "IndependentReviewRefV1": (
            "keyId",
            "role",
            "reviewCommit",
            "reviewLink",
            "reportDigest",
            "decision",
        ),
        "TaskApprovalV1": (
            "schema",
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
            "signatures",
        ),
        "Stage0ChannelV1": (
            "role", "fd", "transport", "access", "bindingDigest",
        ),
        "EligibleStage0TcbV1": (
            "stage0VerifierDigest",
            "bootstrapVerifierDigest",
            "continuationDigest",
            "formalFinalizerDigest",
        ),
        "EligibleStage0EnvironmentV1": (
            "mode", "home", "path", "lcAll", "tz", "network",
        ),
        "EligibleStage0HandoffV1": (
            "schema",
            "id",
            "version",
            "runId",
            "nonce",
            "candidate",
            "authorityPolicy",
            "authorityStoreService",
            "hostObservation",
            "hostProfile",
            "eligible",
            "tcb",
            "environment",
            "channels",
            "pathnameReopen",
            "fallback",
        ),
        "BootstrapTaskVerifierReceiptV1": (
            "schema",
            "id",
            "taskId",
            "candidate",
            "authorityPolicy",
            "requiredTestSet",
            "taskApproval",
            "stage0Handoff",
            "dependencyCompletions",
            "verifierDigest",
            "result",
            "signature",
        ),
        "BootstrapApprovalSetV1": (
            "schema",
            "id",
            "version",
            "candidate",
            "authorityPolicy",
            "taskBreakdown",
            "requiredTestSet",
            "stage0Handoff",
            "taskApprovals",
            "taskReceipts",
            "signatures",
        ),
        "BootstrapApprovalVerifierReceiptV1": (
            "schema",
            "id",
            "candidate",
            "authorityPolicy",
            "requiredTestSet",
            "approvalSet",
            "stage0Handoff",
            "verifierDigest",
            "taskApprovals",
            "taskReceipts",
            "result",
            "signature",
        ),
        "BootstrapApprovalVerifierReceiptRefV1": ("id", "digest"),
        "GateCatalogRefV1": (
            "schema", "id", "version", "contentSha256", "catalogDigest",
        ),
        "FormalGateCatalogApprovalV1": (
            "schema",
            "id",
            "version",
            "authorityPolicy",
            "requiredTestSet",
            "catalog",
            "signatures",
        ),
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
        "DependencyTaskObjectV1": (
            "approvalBytes",
            "receiptBytes",
            "stage0HandoffBytes",
            "evidenceManifestBytes",
        ),
        "ReviewReportObjectV1": ("digest", "bytes"),
        "BootstrapTaskObjectSetV1": (
            "authorityPolicyBytes",
            "stage0HandoffBytes",
            "requiredTestSetBytes",
            "taskApprovalBytes",
            "taskReceiptBytes",
            "evidenceManifestBytes",
            "dependencyObjects",
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

    object_verified_annotations = module.ObjectVerifiedV1.__annotations__
    assert object_verified_annotations["taskApproval"] == "TaskApprovalRefV1"
    assert object_verified_annotations["taskReceipt"] == (
        "BootstrapTaskVerifierReceiptRefV1"
    )
    assert object_verified_annotations["dependencyReceipts"] == (
        "Tuple[BootstrapTaskVerifierReceiptRefV1, ...]"
    )
    assert object_verified_annotations["evidence"] == "Tuple[EvidenceRef, ...]"


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


def approval_rule(*roles: str, minimum: int) -> dict:
    return {
        "requiredRoles": list(roles),
        "minimumDistinctSigners": minimum,
    }


def valid_bootstrap_authority_policy() -> dict:
    principals = (
        ("principal-architecture", "key-architecture", RFC_8032_PUBLIC_KEYS[0], "architecture"),
        ("principal-quality", "key-quality", RFC_8032_PUBLIC_KEYS[1], "quality"),
        ("principal-release", "key-release", RFC_8032_PUBLIC_KEYS[2], "release"),
        ("principal-security", "key-security", RFC_8032_PUBLIC_KEYS[3], "security"),
    )
    task_rules = (
        ("TASK-D0-01", approval_rule("architecture", "quality", minimum=2)),
        ("TASK-D0-02", approval_rule("architecture", "quality", minimum=2)),
        ("TASK-D0-03", approval_rule("quality", "security", minimum=2)),
        ("TASK-D0-04", approval_rule("quality", "security", "release", minimum=3)),
        ("TASK-D0-05", approval_rule("quality", "security", minimum=2)),
        ("TASK-D0-06", approval_rule("architecture", "quality", minimum=2)),
    )
    return {
        "schema": "proof-forge.bootstrap-authority-policy.v1",
        "id": "bootstrap-authority-root",
        "version": "1.0.0",
        "principals": [
            {
                "principalId": principal_id,
                "keyId": key_id,
                "publicKey": public_key,
                "roles": [role],
            }
            for principal_id, key_id, public_key, role in principals
        ],
        "taskRules": [
            {"taskId": task_id, "rule": rule}
            for task_id, rule in task_rules
        ],
        "requiredTestSetRule": approval_rule("quality", "security", minimum=2),
        "formalCatalogRule": approval_rule("quality", "security", minimum=2),
        "bootstrapSetRule": approval_rule(
            "quality", "security", "release", minimum=3
        ),
        "sessionContainmentRule": approval_rule("quality", "security", minimum=2),
        "freshnessAuthorityRule": approval_rule("quality", "release", minimum=2),
        "privateScanRule": approval_rule("quality", "security", minimum=2),
        "privateScanPolicy": {
            "schema": "proof-forge.private-scan-policy.v1",
            "id": "bootstrap-private-scan-policy",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("41" * 32)),
        },
        "revocationSnapshotRule": approval_rule("security", "release", minimum=2),
        "authorityStoreService": {
            "schema": "proof-forge.authority-store-service.v1",
            "id": "bootstrap-authority-store",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("42" * 32)),
        },
        "verifier": {
            "id": "bootstrap-task-verifier",
            "executableDigest": digest_text(bytes.fromhex("43" * 32)),
            "receiptKeyId": "key-verifier-receipt",
            "receiptPublicKey": RFC_8032_PUBLIC_KEYS[4],
        },
    }


def test_bootstrap_authority_policy(module: ModuleType) -> None:
    policy = valid_bootstrap_authority_policy()
    encoded = module.canonical_pf_jcs(policy)
    parsed_policy, parsed_ref = module.parse_bootstrap_authority_policy(encoded)
    expected_digest = hashlib.sha256(
        b"pf.bootstrap-authority-policy.v1\x00" + encoded
    ).digest()
    expected_ref = module.ContentRef(
        "proof-forge.bootstrap-authority-policy.v1",
        "bootstrap-authority-root",
        "1.0.0",
        module.Digest("sha256", expected_digest),
    )
    assert isinstance(parsed_policy, module.BootstrapAuthorityPolicyV1)
    assert parsed_policy.id == "bootstrap-authority-root"
    assert isinstance(parsed_policy.principals, tuple)
    assert len(parsed_policy.principals) == 4
    assert all(
        isinstance(principal, module.BootstrapAuthorityPrincipalV1)
        and isinstance(principal.publicKey, bytes)
        and isinstance(principal.roles, tuple)
        for principal in parsed_policy.principals
    )
    assert isinstance(parsed_policy.taskRules, tuple)
    assert all(
        isinstance(task_rule, module.BootstrapAuthorityTaskRuleV1)
        and isinstance(task_rule.rule, module.ApprovalRuleV1)
        and isinstance(task_rule.rule.requiredRoles, tuple)
        for task_rule in parsed_policy.taskRules
    )
    assert tuple(rule.taskId for rule in parsed_policy.taskRules) == tuple(
        f"TASK-D0-0{number}" for number in range(1, 7)
    )
    assert isinstance(parsed_policy.privateScanPolicy, module.ContentRef)
    assert isinstance(parsed_policy.authorityStoreService, module.ContentRef)
    assert isinstance(parsed_policy.verifier, module.BootstrapAuthorityVerifierV1)
    assert isinstance(parsed_policy.verifier.executableDigest, module.Digest)
    assert isinstance(parsed_policy.verifier.receiptPublicKey, bytes)
    assert parsed_ref == expected_ref, (
        "valid policy must return its recomputed ContentRef projection"
    )

    valid_rotation = copy.deepcopy(policy)
    valid_rotation["principals"].insert(1, {
        "principalId": valid_rotation["principals"][0]["principalId"],
        "keyId": "key-architecture-rotation",
        "publicKey": ED25519_BASEPOINT,
        "roles": ["quality"],
    })
    rotated_policy, _ = module.parse_bootstrap_authority_policy(
        module.canonical_pf_jcs(valid_rotation)
    )
    assert len(rotated_policy.principals) == 5, (
        "same-principal rotation with distinct key material must remain legal"
    )

    stronger_policy = copy.deepcopy(policy)
    stronger_policy["taskRules"][0]["rule"] = approval_rule(
        "architecture", "quality", "security", minimum=3
    )
    stronger_policy["requiredTestSetRule"] = approval_rule(
        "quality", "security", "release", minimum=3
    )
    parsed_stronger, _ = module.parse_bootstrap_authority_policy(
        module.canonical_pf_jcs(stronger_policy)
    )
    assert parsed_stronger.taskRules[0].rule.minimumDistinctSigners == 3, (
        "policy may strengthen role and signer minima"
    )

    broad_safe_ids = copy.deepcopy(policy)
    broad_safe_ids["principals"][0]["principalId"] = "Principal_1:ops+arch"
    broad_safe_ids["verifier"]["id"] = "Verifier_1:prod+receipt"
    parsed_safe_ids, _ = module.parse_bootstrap_authority_policy(
        module.canonical_pf_jcs(broad_safe_ids)
    )
    assert parsed_safe_ids.principals[0].principalId == "Principal_1:ops+arch"
    assert parsed_safe_ids.verifier.id == "Verifier_1:prod+receipt"

    oversized_principals = copy.deepcopy(policy)
    oversized_principals["principals"] = [
        {
            "principalId": f"principal-bulk-{index:03d}",
            "keyId": f"key-bulk-{index:03d}",
            "publicKey": RFC_8032_PUBLIC_KEYS[0],
            "roles": ["quality"],
        }
        for index in range(257)
    ]
    duplicate_key_material = copy.deepcopy(policy)
    duplicate_key_material["principals"][1]["publicKey"] = (
        duplicate_key_material["principals"][0]["publicKey"]
    )
    receipt_key_alias = copy.deepcopy(policy)
    receipt_key_alias["verifier"]["receiptPublicKey"] = (
        receipt_key_alias["principals"][0]["publicKey"]
    )
    original_decode_point = module._decode_point
    curve_calls = 0

    def counted_decode_point(encoded: bytes) -> object:
        nonlocal curve_calls
        curve_calls += 1
        return object()

    module._decode_point = counted_decode_point
    try:
        assert_rejected(
            module,
            lambda: module.parse_bootstrap_authority_policy(
                module.canonical_pf_jcs(oversized_principals)
            ),
        )
        assert curve_calls == 0, "257 principals must reject before curve work"
        assert_rejected(
            module,
            lambda: module.parse_bootstrap_authority_policy(
                module.canonical_pf_jcs(duplicate_key_material)
            ),
        )
        assert curve_calls == 0, (
            "duplicate publicKey must reject before repeated subgroup validation"
        )
        assert_rejected(
            module,
            lambda: module.parse_bootstrap_authority_policy(
                module.canonical_pf_jcs(receipt_key_alias)
            ),
        )
        assert curve_calls == len(policy["principals"]), (
            "receipt key alias must reject before revalidating duplicate key material"
        )
    finally:
        module._decode_point = original_decode_point

    mutations = []

    wrong_schema = copy.deepcopy(policy)
    wrong_schema["schema"] = "proof-forge.bootstrap-authority-policy.v2"
    mutations.append(("wrong policy schema", wrong_schema))

    empty_principals = copy.deepcopy(policy)
    empty_principals["principals"] = []
    mutations.append(("empty principals", empty_principals))

    overflow_policy_version = copy.deepcopy(policy)
    overflow_policy_version["version"] = "18446744073709551616.0.0"
    mutations.append(("policy version exceeds UInt64", overflow_policy_version))

    overflow_nested_version = copy.deepcopy(policy)
    overflow_nested_version["authorityStoreService"]["version"] = (
        "18446744073709551616.0.0"
    )
    mutations.append(("nested ContentRef version exceeds UInt64", overflow_nested_version))

    wrong_store_schema = copy.deepcopy(policy)
    wrong_store_schema["authorityStoreService"]["schema"] = (
        "proof-forge.unrelated-service.v1"
    )
    mutations.append(("wrong authority store service schema", wrong_store_schema))

    unknown_field = copy.deepcopy(policy)
    unknown_field["futurePolicy"] = {}
    mutations.append(("unknown top-level field", unknown_field))

    for container, label in (
        (("principals", 0), "principal"),
        (("taskRules", 0), "task rule"),
    ):
        nested_unknown = copy.deepcopy(policy)
        nested_unknown[container[0]][container[1]]["futureField"] = True
        mutations.append((f"unknown {label} field", nested_unknown))

    unknown_rule_field = copy.deepcopy(policy)
    unknown_rule_field["taskRules"][0]["rule"]["futureField"] = True
    mutations.append(("unknown approval rule field", unknown_rule_field))

    unknown_verifier_field = copy.deepcopy(policy)
    unknown_verifier_field["verifier"]["futureField"] = True
    mutations.append(("unknown verifier field", unknown_verifier_field))

    for label, field_path, value in (
        ("invalid root profile id", ("id",), "Bootstrap_Root"),
        ("invalid policy version", ("version",), "v1.0.0"),
        ("invalid principal safe-id", ("principals", 0, "principalId"), "-principal"),
        ("invalid key safe-id", ("principals", 0, "keyId"), "key/architecture"),
        ("invalid verifier safe-id", ("verifier", "id"), "verifier receipt"),
    ):
        invalid_scalar = copy.deepcopy(policy)
        target = invalid_scalar
        for component in field_path[:-1]:
            target = target[component]
        target[field_path[-1]] = value
        mutations.append((label, invalid_scalar))

    missing_task_rule = copy.deepcopy(policy)
    del missing_task_rule["taskRules"][3]
    mutations.append(("missing task rule", missing_task_rule))

    reordered_task_rules = copy.deepcopy(policy)
    reordered_task_rules["taskRules"][0], reordered_task_rules["taskRules"][1] = (
        reordered_task_rules["taskRules"][1],
        reordered_task_rules["taskRules"][0],
    )
    mutations.append(("reordered task rules", reordered_task_rules))

    duplicate_task_rule = copy.deepcopy(policy)
    duplicate_task_rule["taskRules"].insert(
        1, copy.deepcopy(duplicate_task_rule["taskRules"][0])
    )
    mutations.append(("duplicate task rule", duplicate_task_rule))

    reordered_principals = copy.deepcopy(policy)
    reordered_principals["principals"][0], reordered_principals["principals"][1] = (
        reordered_principals["principals"][1],
        reordered_principals["principals"][0],
    )
    mutations.append(("reordered principals", reordered_principals))

    duplicate_key_id = copy.deepcopy(policy)
    duplicate_key_id["principals"][1]["keyId"] = (
        duplicate_key_id["principals"][0]["keyId"]
    )
    mutations.append(("duplicate principal keyId", duplicate_key_id))

    task_minima = (
        (("architecture", "quality"), 2),
        (("architecture", "quality"), 2),
        (("quality", "security"), 2),
        (("quality", "security", "release"), 3),
        (("quality", "security"), 2),
        (("architecture", "quality"), 2),
    )
    for index, (required_roles, minimum) in enumerate(task_minima):
        weak_threshold = copy.deepcopy(policy)
        weak_threshold["taskRules"][index]["rule"]["minimumDistinctSigners"] = (
            minimum - 1
        )
        mutations.append((f"weak task rule {index + 1} threshold", weak_threshold))

        weak_role = copy.deepcopy(policy)
        weak_role["taskRules"][index]["rule"]["requiredRoles"] = list(
            required_roles[1:]
        )
        mutations.append((f"weak task rule {index + 1} roles", weak_role))

    named_minima = (
        ("requiredTestSetRule", ("quality", "security"), 2),
        ("formalCatalogRule", ("quality", "security"), 2),
        ("bootstrapSetRule", ("quality", "security", "release"), 3),
        ("sessionContainmentRule", ("quality", "security"), 2),
        ("freshnessAuthorityRule", ("quality", "release"), 2),
        ("privateScanRule", ("quality", "security"), 2),
        ("revocationSnapshotRule", ("security", "release"), 2),
    )
    for field, required_roles, minimum in named_minima:
        weak_threshold = copy.deepcopy(policy)
        weak_threshold[field]["minimumDistinctSigners"] = minimum - 1
        mutations.append((f"weak {field} threshold", weak_threshold))

        weak_role = copy.deepcopy(policy)
        weak_role[field]["requiredRoles"] = list(required_roles[1:])
        mutations.append((f"weak {field} roles", weak_role))

    for label, minimum in (
        ("boolean signer threshold", True),
        ("zero signer threshold", 0),
        ("out-of-u32 signer threshold", 2**32),
        ("unsatisfiable signer threshold", 5),
    ):
        invalid_threshold = copy.deepcopy(policy)
        invalid_threshold["requiredTestSetRule"]["minimumDistinctSigners"] = minimum
        mutations.append((label, invalid_threshold))

    multi_key_single_principal = copy.deepcopy(policy)
    for principal in multi_key_single_principal["principals"]:
        principal["principalId"] = "principal-one-person"
    mutations.append(("single principal multi-key quorum", multi_key_single_principal))

    duplicate_principal_public_key = copy.deepcopy(policy)
    duplicate_principal_public_key["principals"][1]["publicKey"] = (
        duplicate_principal_public_key["principals"][0]["publicKey"]
    )
    mutations.append(
        ("duplicate principal public key", duplicate_principal_public_key)
    )

    duplicate_rotation_public_key = copy.deepcopy(policy)
    duplicate_rotation_public_key["principals"][1]["principalId"] = (
        duplicate_rotation_public_key["principals"][0]["principalId"]
    )
    duplicate_rotation_public_key["principals"][1]["publicKey"] = (
        duplicate_rotation_public_key["principals"][0]["publicKey"]
    )
    mutations.append(
        ("duplicate public key within principal rotation", duplicate_rotation_public_key)
    )

    ascii_role_order = copy.deepcopy(policy)
    ascii_role_order["taskRules"][3]["rule"]["requiredRoles"] = [
        "quality", "release", "security",
    ]
    mutations.append(("ASCII rather than enum role order", ascii_role_order))

    principal_role_order = copy.deepcopy(policy)
    principal_role_order["principals"][1]["roles"] = ["security", "quality"]
    mutations.append(("principal roles out of enum order", principal_role_order))

    duplicate_principal_role = copy.deepcopy(policy)
    duplicate_principal_role["principals"][1]["roles"] = ["quality", "quality"]
    mutations.append(("duplicate principal role", duplicate_principal_role))

    unknown_principal_role = copy.deepcopy(policy)
    unknown_principal_role["principals"][1]["roles"] = ["quality", "owner"]
    mutations.append(("unknown principal role", unknown_principal_role))

    invalid_key = copy.deepcopy(policy)
    invalid_key["principals"][0]["publicKey"] = "ff" * 32
    mutations.append(("invalid Ed25519 public key", invalid_key))

    uppercase_key = copy.deepcopy(policy)
    uppercase_key["principals"][0]["publicKey"] = (
        uppercase_key["principals"][0]["publicKey"].upper()
    )
    mutations.append(("uppercase Ed25519 public key", uppercase_key))

    empty_principal_roles = copy.deepcopy(policy)
    empty_principal_roles["principals"][0]["roles"] = []
    mutations.append(("empty principal roles", empty_principal_roles))

    small_order_key = copy.deepcopy(policy)
    small_order_key["principals"][0]["publicKey"] = "01" + "00" * 31
    mutations.append(("small-order Ed25519 public key", small_order_key))

    receipt_key_id_collision = copy.deepcopy(policy)
    receipt_key_id_collision["verifier"]["receiptKeyId"] = (
        receipt_key_id_collision["principals"][0]["keyId"]
    )
    mutations.append(("receipt keyId collision", receipt_key_id_collision))

    receipt_public_key_collision = copy.deepcopy(policy)
    receipt_public_key_collision["verifier"]["receiptPublicKey"] = (
        receipt_public_key_collision["principals"][0]["publicKey"]
    )
    mutations.append(("receipt publicKey collision", receipt_public_key_collision))

    for label, public_key in (
        ("small-order receipt public key", "01" + "00" * 31),
        ("mixed-order receipt public key", ED25519_MIXED_ORDER_POINT),
    ):
        bad_receipt_key = copy.deepcopy(policy)
        bad_receipt_key["verifier"]["receiptPublicKey"] = public_key
        mutations.append((label, bad_receipt_key))

    for label, mutation in mutations:
        assert_rejected(
            module,
            lambda mutation=mutation: module.parse_bootstrap_authority_policy(
                module.canonical_pf_jcs(mutation)
            ),
        )


def content_ref_wire(ref: object) -> dict:
    digest = getattr(ref, "digest")
    assert getattr(digest, "algorithm") == "sha256"
    return {
        "schema": getattr(ref, "schema"),
        "id": getattr(ref, "id"),
        "version": getattr(ref, "version"),
        "digest": digest_text(getattr(digest, "bytes")),
    }


def required_test_set_statement(policy_ref: object) -> dict:
    phase5_bytes = (
        b"---\nid: PHASE-5\nstatus: accepted\n---\n"
        b"# Phase 5 acceptance fixture\n"
    )
    phase5_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00" + phase5_bytes
    ).digest()
    return {
        "schema": "proof-forge.required-test-set.v1",
        "id": "phase-5-required-tests",
        "version": "1.0.0",
        "phase5Document": {
            "id": "PHASE-5",
            "contentDigest": digest_text(phase5_digest),
            "status": "accepted",
            "reviewCommit": "a" * 40,
            "reviewLink": "https://review.example/phase-5",
            "approvedAt": "2026-07-16",
            "approvers": ["principal-quality", "principal-security"],
        },
        "authorityPolicy": content_ref_wire(policy_ref),
        "requiredTestIds": [
            "TST-BOOTSTRAP-001",
            "TST-DOC-001",
            "TST-EVIDENCE-001",
        ],
    }


def sign_required_test_set_statement(
    module: ModuleType,
    statement: dict,
    signer_key_ids: tuple[str, ...] = ("key-quality", "key-security"),
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signatures" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.required-test-set-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.required-test-set-signature.v1\x00" + statement_digest
    )
    expected_public_keys = {
        "key-architecture": RFC_8032_PUBLIC_KEYS[0],
        "key-quality": RFC_8032_PUBLIC_KEYS[1],
        "key-release": RFC_8032_PUBLIC_KEYS[2],
        "key-security": RFC_8032_PUBLIC_KEYS[3],
    }
    signatures = []
    for key_id in signer_key_ids:
        public_key, signature = ed25519_sign_from_rfc_seed(
            RFC_8032_SEEDS_BY_KEY_ID[key_id], signature_message
        )
        assert public_key.hex() == expected_public_keys[key_id], (
            f"test signer seed must reproduce RFC 8032 public key for {key_id}"
        )
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": signature.hex(),
        })
    wire = dict(statement)
    wire["signatures"] = signatures
    return wire, statement_digest, signature_message


def signed_required_test_set(
    module: ModuleType,
    policy_ref: object,
    signer_key_ids: tuple[str, ...] = ("key-quality", "key-security"),
) -> tuple[dict, bytes, bytes]:
    return sign_required_test_set_statement(
        module,
        required_test_set_statement(policy_ref),
        signer_key_ids,
    )


def resign_required_test_set_wire(
    module: ModuleType,
    wire: dict,
    signer_key_ids: tuple[str, ...] = ("key-quality", "key-security"),
) -> dict:
    """Re-sign a structural mutation so stale signatures cannot explain rejection."""
    statement = copy.deepcopy(wire)
    statement.pop("signatures", None)
    resigned, _, _ = sign_required_test_set_statement(
        module, statement, signer_key_ids
    )
    return resigned


FROZEN_PHASE5_A0_IDS = tuple(
    f"TST-A0-{index:03d}" for index in range(1, 21)
)
PHASE5_REQUIRED_IDS = (
    "TST-BOOTSTRAP-001",
    "TST-DOC-001",
    "TST-EVIDENCE-001",
)
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


def phase5_snapshot_bytes(
    *,
    required_ids: tuple[str, ...] = PHASE5_REQUIRED_IDS,
    catalog_ids: tuple[str, ...] | None = None,
    metadata: dict[str, str] | None = None,
) -> bytes:
    """Build the strict synthetic PHASE-5 authority snapshot."""
    frontmatter = dict(PHASE5_FRONTMATTER if metadata is None else metadata)
    ids = catalog_ids
    if ids is None:
        # Source order is intentionally non-canonical; the parser owns sorting.
        ids = tuple(reversed(required_ids)) + tuple(reversed(FROZEN_PHASE5_A0_IDS))
    lines = ["---"]
    lines.extend(f"{key}: {value}" for key, value in frontmatter.items())
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


def make_phase5_snapshot(
    module: ModuleType,
    *,
    required_ids: tuple[str, ...] = PHASE5_REQUIRED_IDS,
    catalog_ids: tuple[str, ...] | None = None,
    metadata: dict[str, str] | None = None,
    encoded: bytes | None = None,
    identifier: str = "PHASE-5",
    path: str = "docs/05-test-spec.md",
) -> object:
    return module.BootstrapDocumentSnapshotV1(
        id=identifier,
        path=path,
        bytes=(
            phase5_snapshot_bytes(
                required_ids=required_ids,
                catalog_ids=catalog_ids,
                metadata=metadata,
            )
            if encoded is None else encoded
        ),
    )


def expected_phase5_document_wire(
    snapshot: object,
    metadata: dict[str, str] | None = None,
) -> dict:
    frontmatter = PHASE5_FRONTMATTER if metadata is None else metadata
    encoded = getattr(snapshot, "bytes")
    digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00" + encoded
    ).digest()
    return {
        "id": "PHASE-5",
        "contentDigest": digest_text(digest),
        "status": "accepted",
        "reviewCommit": frontmatter["reviewCommit"],
        "reviewLink": frontmatter["reviewLink"],
        "approvedAt": frontmatter["approvedAt"],
        "approvers": frontmatter["approvers"].split(", "),
    }


def signed_document_bound_required_set(
    module: ModuleType,
    policy_ref: object,
    snapshot: object,
    *,
    required_ids: tuple[str, ...] = PHASE5_REQUIRED_IDS,
    document_overrides: dict[str, object] | None = None,
) -> dict:
    statement = required_test_set_statement(policy_ref)
    document = expected_phase5_document_wire(snapshot)
    if document_overrides:
        document.update(document_overrides)
    statement["phase5Document"] = document
    statement["requiredTestIds"] = sorted(required_ids)
    wire, _, _ = sign_required_test_set_statement(module, statement)
    return wire


def candidate_identity_wire(module: ModuleType, commit: str = "a" * 40) -> dict:
    payload = {
        "commit": commit,
        "treeObjectId": "b" * len(commit),
        "archiveDigest": digest_text(bytes.fromhex("51" * 32)),
    }
    candidate_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + module.canonical_pf_jcs(payload)
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


def task_approval_required_set_ref(module: ModuleType, required_bytes: bytes) -> dict:
    return {
        "schema": "proof-forge.required-test-set.v1",
        "id": "phase-5-required-tests",
        "version": "1.0.0",
        "digest": digest_text(hashlib.sha256(
            b"pf.required-test-set.v1\x00" + required_bytes
        ).digest()),
    }


def independent_review_wire(
    key_id: str,
    role: str,
    review_commit: str,
    *,
    report_label: str | None = None,
    report_bytes: bytes | None = None,
) -> dict:
    assert not (
        report_label is not None and report_bytes is not None
    ), "review fixture must select either a label or exact raw bytes"
    label = key_id if report_label is None else report_label
    report_digest = independent_review_report_digest(
        independent_review_report_bytes(label)
        if report_bytes is None
        else report_bytes
    )
    return {
        "keyId": key_id,
        "role": role,
        "reviewCommit": review_commit,
        "reviewLink": f"https://review.example/task-d0-01/{key_id}",
        "reportDigest": digest_text(report_digest),
        "decision": "approved",
    }


def independent_review_report_bytes(label: str) -> bytes:
    return f"approved review by {label}\n".encode("ascii")


def independent_review_report_digest(raw: bytes) -> bytes:
    return hashlib.sha256(
        b"pf.independent-review-report.v1\x00" + raw
    ).digest()


def review_report_object(module: ModuleType, raw: bytes) -> object:
    return module.ReviewReportObjectV1(
        digest=module.Digest(
            "sha256",
            independent_review_report_digest(raw),
        ),
        bytes=raw,
    )


def full_raw_evidence_wire(
    module: ModuleType,
    candidate: dict,
    task_id: str,
    test_ids: tuple[str, ...],
    evidence_id: str,
) -> dict:
    """Build a complete canonical-schema EV without importing repo authority."""
    bare_sha = lambda byte: f"{byte:02x}" * 32
    archive_sha = candidate["archiveDigest"].removeprefix("sha256:")
    artifacts = [{
        "target": "docs",
        "role": "acceptance-report",
        "path": f"build/evidence/{evidence_id}.txt",
        "mediaType": "text/plain",
        "sha256": bare_sha(0x31),
        "size": 32,
        "retained": True,
    }]
    artifact_set_sha256 = hashlib.sha256(
        b"pf.evidence.artifact-set.v1\x00"
        + module.canonical_pf_jcs(artifacts)
    ).hexdigest()
    return {
        "schema": "proof-forge.evidence.v1",
        "id": evidence_id,
        "gate": {
            "id": f"bootstrap-{task_id.lower()}",
            "taskId": task_id,
            "testIds": list(test_ids),
            "qualification": "development",
        },
        "repository": {
            "commit": candidate["commit"],
            "subtree": ".",
            "treeObjectId": candidate["treeObjectId"],
            "anchorSource": "external",
            "dirty": False,
            "dirtyDigest": None,
            "unchangedDuringRun": True,
            "archive": {
                "format": "git-tar",
                "sha256": archive_sha,
                "size": 4096,
            },
        },
        "hostAttestation": {
            "scope": "local-point-in-time",
            "remoteAttestation": False,
            "profileId": "synthetic-eligible-host",
            "eligibleForHermetic": True,
            "bootstrapLockSha256": bare_sha(0x01),
            "hostProfileLockSha256": bare_sha(0x02),
            "toolchainLockSha256": bare_sha(0x03),
            "launcherSha256": bare_sha(0x04),
            "verifierSha256": bare_sha(0x05),
            "observationSha256": bare_sha(0x06),
        },
        "environment": {
            "os": "synthetic-darwin",
            "arch": "arm64",
            "environmentSha256": bare_sha(0x07),
            "sourceDateEpoch": 0,
            "cleanRoom": True,
            "buildCache": "empty",
            "assetCache": "locked-read-only",
        },
        "sandboxPolicies": [{
            "id": "deny-default",
            "engine": "synthetic-sandbox",
            "engineSha256": bare_sha(0x08),
            "defaultAction": "deny",
            "network": "deny-all",
            "templateSha256": bare_sha(0x09),
            "renderedSha256": bare_sha(0x0A),
            "probes": [{"id": "network-denied", "status": "passed"}],
        }],
        "tools": [{
            "id": "python",
            "version": "3.9.6",
            "source": "host-profile",
            "assetSha256": None,
            "executableSha256": bare_sha(0x0B),
            "closureSha256": bare_sha(0x0C),
        }],
        "command": {
            "argv": ["bootstrap-object-self-test", task_id],
            "cwdRelative": ".",
            "startedUtc": "2026-07-17T00:00:00Z",
            "endedUtc": "2026-07-17T00:00:01Z",
            "durationMs": 1000,
            "attempts": [{
                "number": 1,
                "exitCode": 0,
                "signal": None,
                "timedOut": False,
                "stdoutLog": "build/logs/evidence.stdout",
                "stderrLog": "build/logs/evidence.stderr",
            }],
        },
        "inputs": [{
            "role": "candidate-archive",
            "path": "candidate.tar",
            "sha256": archive_sha,
            "size": 4096,
        }],
        "artifacts": artifacts,
        "artifactSetSha256": artifact_set_sha256,
        "observations": [{
            "step": "bootstrap-object-consumer",
            "status": "passed",
            "return": True,
            "logicalState": {"taskId": task_id},
            "effects": [],
            "errorClass": None,
        }],
        "logs": [
            {
                "path": "build/logs/evidence.stderr",
                "sha256": bare_sha(0x0D),
                "size": 0,
                "truncated": False,
                "privateDataScan": "passed",
            },
            {
                "path": "build/logs/evidence.stdout",
                "sha256": bare_sha(0x0E),
                "size": 64,
                "truncated": False,
                "privateDataScan": "passed",
            },
        ],
        "result": "passed",
        "skipAuthorization": None,
    }


def evidence_ref_wire(raw_bytes: bytes, evidence_id: str) -> dict:
    return {
        "id": evidence_id,
        "digest": digest_text(hashlib.sha256(raw_bytes).digest()),
    }


def evidence_manifest_wire(
    task_id: str,
    candidate: dict,
    evidence_refs: tuple[dict, ...],
) -> dict:
    return {
        "schema": "proof-forge.bootstrap-evidence-root-manifest.v1",
        "taskId": task_id,
        "candidate": copy.deepcopy(candidate),
        "evidence": copy.deepcopy(list(evidence_refs)),
    }


def evidence_manifest_digest(raw_bytes: bytes) -> str:
    return digest_text(hashlib.sha256(
        b"pf.bootstrap-evidence-root-manifest.v1\x00" + raw_bytes
    ).digest())


def task_approval_statement(
    module: ModuleType,
    policy_ref: object,
    required_bytes: bytes,
    *,
    review_keys: tuple[tuple[str, str], ...] = (
        ("key-architecture", "architecture"),
        ("key-quality", "quality"),
    ),
    commit: str = "a" * 40,
) -> dict:
    return {
        "schema": "proof-forge.bootstrap-task-approval.v1",
        "taskId": "TASK-D0-01",
        "candidate": candidate_identity_wire(module, commit),
        "taskBreakdown": normative_document_ref_wire("PHASE-4", commit),
        "requiredTestSet": task_approval_required_set_ref(module, required_bytes),
        "testIds": ["TST-DOC-001"],
        "evidence": [
            {
                "id": "EV-20260716-0026",
                "digest": digest_text(bytes.fromhex("61" * 32)),
            },
            {
                "id": "EV-20260716-0027",
                "digest": digest_text(bytes.fromhex("62" * 32)),
            },
        ],
        "dependencyCompletions": [],
        "prerequisiteDocuments": [
            normative_document_ref_wire(identifier, commit)
            for identifier in ("PHASE-1", "PHASE-2", "PHASE-3")
        ],
        "authorityPolicy": content_ref_wire(policy_ref),
        "stage0Handoff": {
            "schema": "proof-forge.eligible-stage0-handoff.v1",
            "id": "task-d0-01-stage0-handoff",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("63" * 32)),
        },
        "independentReviews": [
            independent_review_wire(key_id, role, commit)
            for key_id, role in review_keys
        ],
    }


def sign_task_approval_statement(
    module: ModuleType,
    statement: dict,
    signer_key_ids: tuple[str, ...] = ("key-architecture", "key-quality"),
    signer_seeds: dict[str, bytes] | None = None,
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signatures" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-approval-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.bootstrap-task-approval-signature.v1\x00" + statement_digest
    )
    seeds = RFC_8032_SEEDS_BY_KEY_ID if signer_seeds is None else signer_seeds
    signatures = []
    for key_id in signer_key_ids:
        _, signature = ed25519_sign_from_rfc_seed(seeds[key_id], signature_message)
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": signature.hex(),
        })
    wire = dict(statement)
    wire["signatures"] = signatures
    return wire, statement_digest, signature_message


def resign_task_approval_wire(
    module: ModuleType,
    wire: dict,
    signer_key_ids: tuple[str, ...] = ("key-architecture", "key-quality"),
) -> dict:
    statement = copy.deepcopy(wire)
    statement.pop("signatures", None)
    resigned, _, _ = sign_task_approval_statement(
        module, statement, signer_key_ids
    )
    return resigned


def eligible_stage0_handoff_wire(
    module: ModuleType,
    policy_wire: dict,
    policy_ref: object,
    candidate: dict,
) -> dict:
    policy_ref_wire = content_ref_wire(policy_ref)
    store_ref = copy.deepcopy(policy_wire["authorityStoreService"])
    return {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": "task-d0-01-stage0-handoff",
        "version": "1.0.0",
        "runId": "task-d0-01-run-20260717-0001",
        "nonce": "70" * 32,
        "candidate": copy.deepcopy(candidate),
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
            "bootstrapVerifierDigest": policy_wire["verifier"]["executableDigest"],
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
                "bindingDigest": candidate["archiveDigest"],
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


def eligible_stage0_handoff_ref_wire(
    module: ModuleType,
    handoff_wire: dict,
    handoff_bytes: bytes,
) -> dict:
    return {
        "schema": handoff_wire["schema"],
        "id": handoff_wire["id"],
        "version": handoff_wire["version"],
        "digest": digest_text(hashlib.sha256(
            b"pf.eligible-stage0-handoff.v1\x00" + handoff_bytes
        ).digest()),
    }


def bootstrap_task_receipt_ref_wire(
    module: ModuleType,
    task_id: str,
    receipt_id: str,
    receipt_bytes: bytes,
) -> dict:
    return {
        "taskId": task_id,
        "id": receipt_id,
        "digest": digest_text(hashlib.sha256(
            b"pf.bootstrap-task-verifier-receipt.v1\x00" + receipt_bytes
        ).digest()),
    }


def sign_bootstrap_task_receipt_statement(
    module: ModuleType,
    statement: dict,
    *,
    key_id: str = "key-verifier-receipt",
    seed: bytes = RFC_8032_RECEIPT_SEED,
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signature" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-verifier-receipt-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        + statement_digest
    )
    public_key, signature = ed25519_sign_from_rfc_seed(seed, signature_message)
    assert public_key.hex() == RFC_8032_PUBLIC_KEYS[4], (
        "receipt signer seed must reproduce the policy receipt public key"
    )
    wire = dict(statement)
    wire["signature"] = {
        "keyId": key_id,
        "algorithm": "ed25519",
        "signature": signature.hex(),
    }
    return wire, statement_digest, signature_message


def resign_bootstrap_task_receipt_wire(
    module: ModuleType,
    wire: dict,
    *,
    key_id: str = "key-verifier-receipt",
) -> dict:
    statement = copy.deepcopy(wire)
    statement.pop("signature", None)
    resigned, _, _ = sign_bootstrap_task_receipt_statement(
        module, statement, key_id=key_id
    )
    return resigned


def sign_bootstrap_approval_set_statement(
    module: ModuleType,
    statement: dict,
    signer_key_ids: tuple[str, ...] = (
        "key-quality",
        "key-release",
        "key-security",
    ),
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signatures" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-set-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.bootstrap-approval-set-signature.v1\x00" + statement_digest
    )
    signatures = []
    for key_id in signer_key_ids:
        _, signature = ed25519_sign_from_rfc_seed(
            RFC_8032_SEEDS_BY_KEY_ID[key_id], signature_message
        )
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": signature.hex(),
        })
    wire = dict(statement)
    wire["signatures"] = signatures
    return wire, statement_digest, signature_message


def resign_bootstrap_approval_set_wire(
    module: ModuleType,
    wire: dict,
) -> dict:
    statement = copy.deepcopy(wire)
    statement.pop("signatures", None)
    resigned, _, _ = sign_bootstrap_approval_set_statement(module, statement)
    return resigned


def sign_bootstrap_approval_verifier_receipt_statement(
    module: ModuleType,
    statement: dict,
    *,
    key_id: str = "key-verifier-receipt",
    seed: bytes = RFC_8032_RECEIPT_SEED,
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signature" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-verifier-receipt-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.bootstrap-approval-verifier-receipt-signature.v1\x00"
        + statement_digest
    )
    _, signature = ed25519_sign_from_rfc_seed(seed, signature_message)
    wire = dict(statement)
    wire["signature"] = {
        "keyId": key_id,
        "algorithm": "ed25519",
        "signature": signature.hex(),
    }
    return wire, statement_digest, signature_message


def resign_bootstrap_approval_verifier_receipt_wire(
    module: ModuleType,
    wire: dict,
    *,
    key_id: str = "key-verifier-receipt",
    seed: bytes = RFC_8032_RECEIPT_SEED,
) -> dict:
    statement = copy.deepcopy(wire)
    statement.pop("signature", None)
    resigned, _, _ = sign_bootstrap_approval_verifier_receipt_statement(
        module, statement, key_id=key_id, seed=seed
    )
    return resigned


def sign_formal_gate_catalog_approval_statement(
    module: ModuleType,
    statement: dict,
    signer_key_ids: tuple[str, ...] = ("key-quality", "key-security"),
    signer_seeds: dict[str, bytes] | None = None,
) -> tuple[dict, bytes, bytes]:
    statement = copy.deepcopy(statement)
    assert "signatures" not in statement, "signer accepts the unsigned statement"
    statement_digest = hashlib.sha256(
        b"pf.formal-gate-catalog-approval-statement.v1\x00"
        + module.canonical_pf_jcs(statement)
    ).digest()
    signature_message = (
        b"pf.formal-gate-catalog-approval-signature.v1\x00"
        + statement_digest
    )
    seeds = RFC_8032_SEEDS_BY_KEY_ID if signer_seeds is None else signer_seeds
    signatures = []
    for key_id in signer_key_ids:
        _, signature = ed25519_sign_from_rfc_seed(seeds[key_id], signature_message)
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": signature.hex(),
        })
    wire = dict(statement)
    wire["signatures"] = signatures
    return wire, statement_digest, signature_message


def resign_formal_gate_catalog_approval_wire(
    module: ModuleType,
    wire: dict,
    signer_key_ids: tuple[str, ...] = ("key-quality", "key-security"),
) -> dict:
    statement = copy.deepcopy(wire)
    statement.pop("signatures", None)
    resigned, _, _ = sign_formal_gate_catalog_approval_statement(
        module, statement, signer_key_ids
    )
    return resigned


def dependency_receipt_refs(count: int) -> list[dict]:
    return [
        {
            "taskId": f"TASK-D0-0{index}",
            "id": f"BTV-20260717-{index:04d}",
            "digest": digest_text(bytes([0x80 + index]) * 32),
        }
        for index in range(2, 2 + count)
    ]


def signed_task_receipt_fixture(
    module: ModuleType,
    *,
    dependency_completions: tuple[dict, ...] = (),
    mutate_handoff: Callable[[dict], None] | None = None,
) -> dict[str, object]:
    policy_wire = valid_bootstrap_authority_policy()
    policy_bytes = module.canonical_pf_jcs(policy_wire)
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)
    phase5_snapshot = make_phase5_snapshot(module)
    required_wire = signed_document_bound_required_set(
        module, policy_ref, phase5_snapshot
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    candidate = candidate_identity_wire(module)
    handoff_wire = eligible_stage0_handoff_wire(
        module, policy_wire, policy_ref, candidate
    )
    if mutate_handoff is not None:
        mutate_handoff(handoff_wire)
    handoff_bytes = module.canonical_pf_jcs(handoff_wire)
    handoff_ref = eligible_stage0_handoff_ref_wire(
        module, handoff_wire, handoff_bytes
    )

    approval_statement = task_approval_statement(
        module, policy_ref, required_bytes
    )
    approval_statement["candidate"] = copy.deepcopy(candidate)
    approval_statement["stage0Handoff"] = handoff_ref
    approval_statement["dependencyCompletions"] = copy.deepcopy(
        list(dependency_completions)
    )
    approval_wire, approval_statement_digest, approval_signature_message = (
        sign_task_approval_statement(module, approval_statement)
    )
    approval_bytes = module.canonical_pf_jcs(approval_wire)
    approval_ref = {
        "taskId": approval_wire["taskId"],
        "digest": digest_text(hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
        ).digest()),
    }
    receipt_statement = {
        "schema": "proof-forge.bootstrap-task-verifier-receipt.v1",
        "id": "BTV-20260717-0001",
        "taskId": approval_wire["taskId"],
        "candidate": copy.deepcopy(candidate),
        "authorityPolicy": content_ref_wire(policy_ref),
        "requiredTestSet": task_approval_required_set_ref(
            module, required_bytes
        ),
        "taskApproval": approval_ref,
        "stage0Handoff": handoff_ref,
        "dependencyCompletions": copy.deepcopy(list(dependency_completions)),
        "verifierDigest": policy_wire["verifier"]["executableDigest"],
        "result": "task-approved",
    }
    receipt_wire, receipt_statement_digest, receipt_signature_message = (
        sign_bootstrap_task_receipt_statement(module, receipt_statement)
    )
    return {
        "policyWire": policy_wire,
        "policyBytes": policy_bytes,
        "policyRef": policy_ref,
        "phase5Snapshot": phase5_snapshot,
        "requiredWire": required_wire,
        "requiredBytes": required_bytes,
        "candidate": candidate,
        "handoffWire": handoff_wire,
        "handoffBytes": handoff_bytes,
        "handoffRef": handoff_ref,
        "approvalStatement": approval_statement,
        "approvalWire": approval_wire,
        "approvalBytes": approval_bytes,
        "approvalStatementDigest": approval_statement_digest,
        "approvalSignatureMessage": approval_signature_message,
        "receiptStatement": receipt_statement,
        "receiptWire": receipt_wire,
        "receiptBytes": module.canonical_pf_jcs(receipt_wire),
        "receiptStatementDigest": receipt_statement_digest,
        "receiptSignatureMessage": receipt_signature_message,
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

ACCEPTED_DOCUMENT_PATHS = {
    "PHASE-1": "docs/01-prd.md",
    "PHASE-2": "docs/02-architecture.md",
    "PHASE-3": "docs/03-technical-spec.md",
    "PHASE-4": "docs/04-task-breakdown.md",
}
ACCEPTED_PREREQUISITE_TITLES = {
    "PHASE-1": "Synthetic Phase 1 product requirements",
    "PHASE-2": "Synthetic Phase 2 architecture",
    "PHASE-3": "Synthetic Phase 3 technical specification",
}
PHASE4_FRONTMATTER = {
    "id": "PHASE-4",
    "title": "Synthetic Phase 4 task breakdown",
    "status": "accepted",
    "owner": "delivery",
    "updated": "2026-07-16",
    "normative": "true",
    "approvers": "principal-quality, principal-security",
    "approvedAt": "2026-07-16",
    "reviewCommit": "a" * 40,
    "reviewLink": "https://review.example/phase-4:443/approval",
    "openFindings": "none",
}
PHASE4_D0_07_ROW = {
    "dependencies": ("TASK-D0-04",),
    "prerequisites": (),
    "testIds": ("TST-EVIDENCE-002", "TST-ISO-002"),
    "evidenceIds": (),
}
PHASE4_STATUS_BY_TASK = {
    "TASK-D0-01": "in_progress",
    "TASK-D0-02": "pending",
    "TASK-D0-03": "pending",
    "TASK-D0-04": "blocked",
    "TASK-D0-05": "pending",
    "TASK-D0-06": "pending",
    "TASK-D0-07": "pending",
}


def _phase4_list_cell(values: tuple[str, ...], *, accepted: bool = False) -> str:
    if not values:
        return "—"
    if accepted:
        return ", ".join(f"{value}@accepted" for value in values)
    return ", ".join(values)


def phase4_snapshot_bytes(
    *,
    metadata: dict[str, str] | None = None,
    row_overrides: dict[str, dict[str, object]] | None = None,
) -> bytes:
    """Build the strict synthetic PHASE-4 authority snapshot."""
    frontmatter = dict(PHASE4_FRONTMATTER if metadata is None else metadata)
    rows = {
        task_id: {
            "dependencies": row["dependencies"],
            "prerequisites": row["prerequisites"],
            "testIds": row["testIds"],
            "evidenceIds": row["evidenceIds"],
            "status": PHASE4_STATUS_BY_TASK[task_id],
            "description": f"fixture for {task_id}",
        }
        for task_id, row in D0_GRAPH_ROWS.items()
    }
    rows["TASK-D0-07"] = {
        **PHASE4_D0_07_ROW,
        "status": PHASE4_STATUS_BY_TASK["TASK-D0-07"],
        "description": "fixture for TASK-D0-07",
    }
    for task_id, override in (row_overrides or {}).items():
        rows[task_id].update(override)

    lines = ["---"]
    lines.extend(f"{key}: {value}" for key, value in frontmatter.items())
    lines.extend((
        "---",
        "# Phase 4 synthetic authority fixture",
        "",
        "## Milestone D0：文档与独立工程",
        "",
        "| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |",
        "|---|---|---|---|---|---|---|",
    ))
    for task_id in tuple(D0_GRAPH_ROWS) + ("TASK-D0-07",):
        row = rows[task_id]
        lines.append(
            "| "
            + " | ".join((
                task_id,
                str(row["description"]),
                _phase4_list_cell(row["dependencies"]),
                _phase4_list_cell(row["prerequisites"], accepted=True),
                _phase4_list_cell(row["testIds"]),
                _phase4_list_cell(row["evidenceIds"]),
                str(row["status"]),
            ))
            + " |"
        )
    lines.extend((
        "",
        "## Milestone D1：语言前端",
        "",
        "Synthetic next milestone prose.",
    ))
    return ("\n".join(lines) + "\n").encode("utf-8")


def make_phase4_snapshot(
    module: ModuleType,
    *,
    metadata: dict[str, str] | None = None,
    row_overrides: dict[str, dict[str, object]] | None = None,
    encoded: bytes | None = None,
    identifier: str = "PHASE-4",
    path: str = "docs/04-task-breakdown.md",
) -> object:
    return module.BootstrapDocumentSnapshotV1(
        id=identifier,
        path=path,
        bytes=(
            phase4_snapshot_bytes(
                metadata=metadata,
                row_overrides=row_overrides,
            )
            if encoded is None else encoded
        ),
    )


def expected_phase4_document_wire(
    snapshot: object,
    metadata: dict[str, str] | None = None,
) -> dict:
    frontmatter = PHASE4_FRONTMATTER if metadata is None else metadata
    digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-4\x00" + getattr(snapshot, "bytes")
    ).digest()
    return {
        "id": "PHASE-4",
        "contentDigest": digest_text(digest),
        "status": "accepted",
        "reviewCommit": frontmatter["reviewCommit"],
        "reviewLink": frontmatter["reviewLink"],
        "approvedAt": frontmatter["approvedAt"],
        "approvers": frontmatter["approvers"].split(", "),
    }


def accepted_prerequisite_metadata(identifier: str) -> dict[str, str]:
    assert identifier in ACCEPTED_PREREQUISITE_TITLES
    return {
        "id": identifier,
        "title": ACCEPTED_PREREQUISITE_TITLES[identifier],
        "status": "accepted",
        "owner": "architecture",
        "updated": "2026-07-16",
        "normative": "true",
        "approvers": "principal-architecture, principal-quality",
        "approvedAt": "2026-07-16",
        "reviewCommit": "a" * 40,
        "reviewLink": (
            f"https://review.example/{identifier.lower()}:443/approval"
        ),
        "openFindings": "none",
    }


def accepted_prerequisite_snapshot_bytes(identifier: str) -> bytes:
    metadata = accepted_prerequisite_metadata(identifier)
    lines = ["---"]
    lines.extend(f"{key}: {value}" for key, value in metadata.items())
    lines.extend((
        "---",
        f"# {metadata['title']}",
        "",
        f"Synthetic accepted authority fixture for {identifier}.",
    ))
    return ("\n".join(lines) + "\n").encode("utf-8")


def make_accepted_prerequisite_snapshot(
    module: ModuleType,
    identifier: str,
) -> object:
    return module.BootstrapDocumentSnapshotV1(
        id=identifier,
        path=ACCEPTED_DOCUMENT_PATHS[identifier],
        bytes=accepted_prerequisite_snapshot_bytes(identifier),
    )


def snapshot_derived_normative_document_ref_wire(
    snapshot: object,
    metadata: dict[str, str],
) -> dict:
    identifier = getattr(snapshot, "id")
    digest = hashlib.sha256(
        b"pf.normative-document.v1\x00"
        + identifier.encode("ascii")
        + b"\x00"
        + getattr(snapshot, "bytes")
    ).digest()
    return {
        "id": identifier,
        "contentDigest": digest_text(digest),
        "status": "accepted",
        "reviewCommit": metadata["reviewCommit"],
        "reviewLink": metadata["reviewLink"],
        "approvedAt": metadata["approvedAt"],
        "approvers": metadata["approvers"].split(", "),
    }


def signed_d0_object_graph_fixture(
    module: ModuleType,
    root_task_id: str,
    *,
    shared_quality_review_bytes: bytes | None = None,
    approval_mutators: dict[str, Callable[[dict], None]] | None = None,
    evidence_mutators: dict[str, Callable[[dict], None]] | None = None,
    manifest_mutators: dict[str, Callable[[dict], None]] | None = None,
    manifest_source_overrides: dict[str, str] | None = None,
    handoff_mutators: dict[str, Callable[[dict], None]] | None = None,
    phase4_snapshot_override: object | None = None,
    prerequisite_snapshot_overrides: dict[str, object] | None = None,
) -> dict[str, object]:
    policy_wire = valid_bootstrap_authority_policy()
    policy_bytes = module.canonical_pf_jcs(policy_wire)
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)
    required_ids = tuple(sorted({
        test_id
        for row in D0_GRAPH_ROWS.values()
        for test_id in row["testIds"]
    }))
    phase5_snapshot = make_phase5_snapshot(
        module,
        required_ids=required_ids,
    )
    phase4_snapshot = (
        make_phase4_snapshot(module)
        if phase4_snapshot_override is None
        else phase4_snapshot_override
    )
    prerequisite_overrides = prerequisite_snapshot_overrides or {}
    document_snapshots = {
        identifier: (
            prerequisite_overrides[identifier]
            if identifier in prerequisite_overrides
            else make_accepted_prerequisite_snapshot(module, identifier)
        )
        for identifier in ACCEPTED_PREREQUISITE_TITLES
    }
    document_snapshots["PHASE-4"] = phase4_snapshot
    document_snapshots["PHASE-5"] = phase5_snapshot
    document_refs = {
        identifier: snapshot_derived_normative_document_ref_wire(
            snapshot,
            (
                PHASE4_FRONTMATTER
                if identifier == "PHASE-4"
                else accepted_prerequisite_metadata(identifier)
            ),
        )
        for identifier, snapshot in document_snapshots.items()
        if identifier != "PHASE-5"
    }
    required_wire = signed_document_bound_required_set(
        module,
        policy_ref,
        phase5_snapshot,
        required_ids=required_ids,
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    candidate_wire = candidate_identity_wire(module)
    candidate = module.parse_candidate_identity(candidate_wire)
    evidence_wires: dict[str, dict] = {}
    evidence_bytes: dict[str, bytes] = {}
    evidence_refs: dict[str, dict] = {}
    evidence_mutators = evidence_mutators or {}
    for task_id, row in D0_GRAPH_ROWS.items():
        for evidence_id in row["evidenceIds"]:
            raw_wire = full_raw_evidence_wire(
                module,
                candidate_wire,
                task_id,
                row["testIds"],
                evidence_id,
            )
            mutator = evidence_mutators.get(evidence_id)
            if mutator is not None:
                mutator(raw_wire)
            raw_bytes = module.canonical_pf_jcs(raw_wire)
            evidence_wires[evidence_id] = raw_wire
            evidence_bytes[evidence_id] = raw_bytes
            evidence_refs[evidence_id] = evidence_ref_wire(
                raw_bytes,
                evidence_id,
            )

    manifest_wires: dict[str, dict] = {}
    manifest_bytes: dict[str, bytes] = {}
    manifest_mutators = manifest_mutators or {}
    manifest_source_overrides = manifest_source_overrides or {}
    for task_id, row in D0_GRAPH_ROWS.items():
        source_task_id = manifest_source_overrides.get(task_id, task_id)
        source_row = D0_GRAPH_ROWS[source_task_id]
        manifest = evidence_manifest_wire(
            source_task_id,
            candidate_wire,
            tuple(
                evidence_refs[evidence_id]
                for evidence_id in source_row["evidenceIds"]
            ),
        )
        mutator = manifest_mutators.get(task_id)
        if mutator is not None:
            mutator(manifest)
        encoded_manifest = module.canonical_pf_jcs(manifest)
        manifest_wires[task_id] = manifest
        manifest_bytes[task_id] = encoded_manifest
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
        dependency_refs = [
            built[dependency]["receiptRefWire"]
            for dependency in row["dependencies"]
        ]
        handoff_wire = eligible_stage0_handoff_wire(
            module,
            policy_wire,
            policy_ref,
            candidate_wire,
        )
        handoff_wire["id"] = f"task-d0-{task_number:02d}-stage0-handoff"
        handoff_wire["runId"] = f"task-d0-{task_number:02d}-run-20260717"
        handoff_wire["nonce"] = f"{0x80 + task_number:02x}" * 32
        handoff_wire["channels"][3]["bindingDigest"] = evidence_manifest_digest(
            manifest_bytes[task_id]
        )
        handoff_mutator = (handoff_mutators or {}).get(task_id)
        if handoff_mutator is not None:
            handoff_mutator(handoff_wire)
        handoff_bytes = module.canonical_pf_jcs(handoff_wire)
        handoff_ref = eligible_stage0_handoff_ref_wire(
            module,
            handoff_wire,
            handoff_bytes,
        )
        signers = row["signers"]
        approval_statement = {
            "schema": "proof-forge.bootstrap-task-approval.v1",
            "taskId": task_id,
            "candidate": copy.deepcopy(candidate_wire),
            "taskBreakdown": copy.deepcopy(document_refs["PHASE-4"]),
            "requiredTestSet": task_approval_required_set_ref(
                module, required_bytes
            ),
            "testIds": list(row["testIds"]),
            "evidence": copy.deepcopy([
                evidence_refs[evidence_id]
                for evidence_id in row["evidenceIds"]
            ]),
            "dependencyCompletions": copy.deepcopy(dependency_refs),
            "prerequisiteDocuments": [
                copy.deepcopy(document_refs[document_id])
                for document_id in row["prerequisites"]
            ],
            "authorityPolicy": content_ref_wire(policy_ref),
            "stage0Handoff": handoff_ref,
            "independentReviews": [
                independent_review_wire(
                    key_id,
                    role,
                    candidate_wire["commit"],
                    report_label=(
                        None
                        if (
                            shared_quality_review_bytes is not None
                            and key_id == "key-quality"
                        )
                        else f"{task_id}:{key_id}"
                    ),
                    report_bytes=(
                        shared_quality_review_bytes
                        if key_id == "key-quality"
                        else None
                    ),
                )
                for key_id, role in signers
            ],
        }
        mutator = (approval_mutators or {}).get(task_id)
        if mutator is not None:
            mutator(approval_statement)
        signer_key_ids = tuple(key_id for key_id, _ in signers)
        approval_wire, _, _ = sign_task_approval_statement(
            module,
            approval_statement,
            signer_key_ids,
        )
        approval_bytes = module.canonical_pf_jcs(approval_wire)
        approval_ref = {
            "taskId": task_id,
            "digest": digest_text(hashlib.sha256(
                b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
            ).digest()),
        }
        receipt_id = f"BTV-20260717-{task_number:04d}"
        receipt_statement = {
            "schema": "proof-forge.bootstrap-task-verifier-receipt.v1",
            "id": receipt_id,
            "taskId": task_id,
            "candidate": copy.deepcopy(candidate_wire),
            "authorityPolicy": content_ref_wire(policy_ref),
            "requiredTestSet": task_approval_required_set_ref(
                module, required_bytes
            ),
            "taskApproval": approval_ref,
            "stage0Handoff": handoff_ref,
            "dependencyCompletions": copy.deepcopy(
                approval_statement["dependencyCompletions"]
            ),
            "verifierDigest": policy_wire["verifier"]["executableDigest"],
            "result": "task-approved",
        }
        receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
            module,
            receipt_statement,
        )
        receipt_bytes = module.canonical_pf_jcs(receipt_wire)
        built[task_id] = {
            "approvalWire": approval_wire,
            "approvalBytes": approval_bytes,
            "receiptWire": receipt_wire,
            "receiptBytes": receipt_bytes,
            "receiptRefWire": bootstrap_task_receipt_ref_wire(
                module,
                task_id,
                receipt_id,
                receipt_bytes,
            ),
            "handoffWire": handoff_wire,
            "handoffBytes": handoff_bytes,
            "handoffRefWire": handoff_ref,
            "approvalRefWire": approval_ref,
            "evidenceRefsWire": tuple(
                copy.deepcopy(evidence_refs[evidence_id])
                for evidence_id in row["evidenceIds"]
            ),
            "evidenceManifestWire": manifest_wires[task_id],
            "evidenceManifestBytes": manifest_bytes[task_id],
        }

    transitive: set[str] = set()

    def collect(task_id: str) -> None:
        for dependency in D0_GRAPH_ROWS[task_id]["dependencies"]:
            if dependency not in transitive:
                transitive.add(dependency)
                collect(dependency)

    collect(root_task_id)
    included_task_ids = tuple(sorted(transitive | {root_task_id}))
    dependency_task_ids = tuple(sorted(transitive))
    task_rows = tuple(
        module.BootstrapTaskRowSubjectV1(
            taskId=task_id,
            dependencies=D0_GRAPH_ROWS[task_id]["dependencies"],
            prerequisites=tuple(
                {
                    "documentId": document_id,
                    "requiredStatus": "accepted",
                }
                for document_id in D0_GRAPH_ROWS[task_id]["prerequisites"]
            ),
            testIds=D0_GRAPH_ROWS[task_id]["testIds"],
            evidenceIds=D0_GRAPH_ROWS[task_id]["evidenceIds"],
        )
        for task_id in included_task_ids
    )
    evidence_rows = tuple(
        module.BootstrapLedgerSubjectV1(
            id=evidence_id,
            taskId=task_id,
            testIds=D0_GRAPH_ROWS[task_id]["testIds"],
            grade="bootstrap",
            result="passed",
        )
        for task_id in included_task_ids
        for evidence_id in D0_GRAPH_ROWS[task_id]["evidenceIds"]
    )
    evidence_rows = tuple(sorted(evidence_rows, key=lambda row: row.id))
    selected_document_ids = {"PHASE-4", "PHASE-5"}
    for task_id in included_task_ids:
        selected_document_ids.update(D0_GRAPH_ROWS[task_id]["prerequisites"])
    documents = tuple(
        document_snapshots[identifier]
        for identifier in sorted(selected_document_ids)
    )
    subject = module.BootstrapTaskSubjectV1(
        candidate=candidate,
        rootTaskId=root_task_id,
        taskRows=task_rows,
        evidenceRows=evidence_rows,
        documents=documents,
    )
    root = built[root_task_id]
    objects = module.BootstrapTaskObjectSetV1(
        authorityPolicyBytes=policy_bytes,
        stage0HandoffBytes=root["handoffBytes"],
        requiredTestSetBytes=required_bytes,
        taskApprovalBytes=root["approvalBytes"],
        taskReceiptBytes=root["receiptBytes"],
        evidenceManifestBytes=root["evidenceManifestBytes"],
        dependencyObjects=tuple(
            module.DependencyTaskObjectV1(
                approvalBytes=built[task_id]["approvalBytes"],
                receiptBytes=built[task_id]["receiptBytes"],
                stage0HandoffBytes=built[task_id]["handoffBytes"],
                evidenceManifestBytes=built[task_id]["evidenceManifestBytes"],
            )
            for task_id in dependency_task_ids
        ),
        evidenceObjectBytes=tuple(
            evidence_bytes[row.id] for row in evidence_rows
        ),
        reviewReports=tuple(sorted(
            {
                review_report_object(
                    module,
                    shared_quality_review_bytes
                    if (
                        shared_quality_review_bytes is not None
                        and key_id == "key-quality"
                    )
                    else independent_review_report_bytes(f"{task_id}:{key_id}"),
                )
                for task_id in included_task_ids
                for key_id, _ in D0_GRAPH_ROWS[task_id]["signers"]
            },
            key=lambda report: report.digest.bytes,
        )),
    )
    return {
        "subject": subject,
        "objects": objects,
        "built": built,
        "dependencyTaskIds": dependency_task_ids,
        "phase4Snapshot": phase4_snapshot,
        "documentSnapshots": document_snapshots,
        "documentRefs": document_refs,
        "policyRef": policy_ref,
        "requiredBytes": required_bytes,
        "candidateWire": candidate_wire,
        "evidenceWires": evidence_wires,
        "evidenceBytes": evidence_bytes,
        "evidenceRefs": evidence_refs,
        "manifestWires": manifest_wires,
        "manifestBytes": manifest_bytes,
    }


def signed_bootstrap_approval_set_fixture(module: ModuleType) -> dict[str, object]:
    graph = signed_d0_object_graph_fixture(module, "TASK-D0-04")
    original_built = graph["built"]
    assert isinstance(original_built, dict)
    root = original_built["TASK-D0-04"]
    common_handoff_wire = copy.deepcopy(root["handoffWire"])
    common_handoff_bytes = root["handoffBytes"]
    common_handoff_ref = copy.deepcopy(root["handoffRefWire"])
    assert isinstance(common_handoff_bytes, bytes)

    aggregate_built: dict[str, dict[str, object]] = {}
    for task_id in (
        "TASK-D0-01",
        "TASK-D0-02",
        "TASK-D0-03",
        "TASK-D0-05",
        "TASK-D0-06",
        "TASK-D0-04",
    ):
        source = original_built[task_id]
        dependency_refs = [
            copy.deepcopy(aggregate_built[dependency]["receiptRefWire"])
            for dependency in D0_GRAPH_ROWS[task_id]["dependencies"]
        ]
        approval_wire = copy.deepcopy(source["approvalWire"])
        approval_wire["stage0Handoff"] = copy.deepcopy(common_handoff_ref)
        approval_wire["dependencyCompletions"] = dependency_refs
        approval_wire = resign_task_approval_wire(
            module,
            approval_wire,
            tuple(
                key_id for key_id, _ in D0_GRAPH_ROWS[task_id]["signers"]
            ),
        )
        approval_bytes = module.canonical_pf_jcs(approval_wire)
        approval_ref_wire = {
            "taskId": task_id,
            "digest": digest_text(hashlib.sha256(
                b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
            ).digest()),
        }

        receipt_wire = copy.deepcopy(source["receiptWire"])
        receipt_wire["stage0Handoff"] = copy.deepcopy(common_handoff_ref)
        receipt_wire["dependencyCompletions"] = copy.deepcopy(dependency_refs)
        receipt_wire["taskApproval"] = copy.deepcopy(approval_ref_wire)
        receipt_wire = resign_bootstrap_task_receipt_wire(module, receipt_wire)
        receipt_bytes = module.canonical_pf_jcs(receipt_wire)
        aggregate_built[task_id] = {
            "approvalWire": approval_wire,
            "approvalBytes": approval_bytes,
            "approvalRefWire": approval_ref_wire,
            "receiptWire": receipt_wire,
            "receiptBytes": receipt_bytes,
            "receiptRefWire": bootstrap_task_receipt_ref_wire(
                module,
                task_id,
                receipt_wire["id"],
                receipt_bytes,
            ),
        }

    task_approvals = [
        copy.deepcopy(aggregate_built[task_id]["approvalWire"])
        for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
    ]
    task_receipt_refs = [
        copy.deepcopy(aggregate_built[task_id]["receiptRefWire"])
        for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
    ]
    task_receipt_bytes = tuple(
        aggregate_built[task_id]["receiptBytes"]
        for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
    )
    policy_ref = graph["policyRef"]
    required_bytes = graph["requiredBytes"]
    assert isinstance(required_bytes, bytes)
    set_statement = {
        "schema": "proof-forge.bootstrap-approval-set.v1",
        "id": "bootstrap-approval-set",
        "version": "1.0.0",
        "candidate": copy.deepcopy(graph["candidateWire"]),
        "authorityPolicy": content_ref_wire(policy_ref),
        "taskBreakdown": copy.deepcopy(graph["documentRefs"]["PHASE-4"]),
        "requiredTestSet": task_approval_required_set_ref(
            module, required_bytes
        ),
        "stage0Handoff": copy.deepcopy(common_handoff_ref),
        "taskApprovals": task_approvals,
        "taskReceipts": task_receipt_refs,
    }
    set_wire, statement_digest, signature_message = (
        sign_bootstrap_approval_set_statement(module, set_statement)
    )
    set_bytes = module.canonical_pf_jcs(set_wire)
    objects = graph["objects"]
    return {
        "setStatement": set_statement,
        "setWire": set_wire,
        "setBytes": set_bytes,
        "setStatementDigest": statement_digest,
        "setSignatureMessage": signature_message,
        "setRefWire": {
            "schema": set_wire["schema"],
            "id": set_wire["id"],
            "version": set_wire["version"],
            "digest": digest_text(hashlib.sha256(
                b"pf.bootstrap-approval-set.v1\x00" + set_bytes
            ).digest()),
        },
        "taskReceiptBytes": task_receipt_bytes,
        "aggregateBuilt": aggregate_built,
        "requiredBytes": required_bytes,
        "policyBytes": getattr(objects, "authorityPolicyBytes"),
        "phase5Snapshot": graph["documentSnapshots"]["PHASE-5"],
        "handoffWire": common_handoff_wire,
        "handoffBytes": common_handoff_bytes,
    }


def signed_bootstrap_approval_verifier_receipt_fixture(
    module: ModuleType,
) -> dict[str, object]:
    set_fixture = signed_bootstrap_approval_set_fixture(module)
    aggregate_built = set_fixture["aggregateBuilt"]
    assert isinstance(aggregate_built, dict)
    set_wire = set_fixture["setWire"]
    assert isinstance(set_wire, dict)
    set_ref_wire = set_fixture["setRefWire"]
    assert isinstance(set_ref_wire, dict)
    policy_wire = valid_bootstrap_authority_policy()
    statement = {
        "schema": "proof-forge.bootstrap-approval-verifier-receipt.v1",
        "id": "BAV-20260717-0001",
        "candidate": copy.deepcopy(set_wire["candidate"]),
        "authorityPolicy": copy.deepcopy(set_wire["authorityPolicy"]),
        "requiredTestSet": copy.deepcopy(set_wire["requiredTestSet"]),
        "approvalSet": copy.deepcopy(set_ref_wire),
        "stage0Handoff": copy.deepcopy(set_wire["stage0Handoff"]),
        "verifierDigest": policy_wire["verifier"]["executableDigest"],
        "taskApprovals": [
            copy.deepcopy(aggregate_built[task_id]["approvalRefWire"])
            for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
        ],
        "taskReceipts": [
            copy.deepcopy(aggregate_built[task_id]["receiptRefWire"])
            for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
        ],
        "result": "bootstrap-approved",
    }
    receipt_wire, statement_digest, signature_message = (
        sign_bootstrap_approval_verifier_receipt_statement(module, statement)
    )
    receipt_bytes = module.canonical_pf_jcs(receipt_wire)
    return {
        "setFixture": set_fixture,
        "receiptStatement": statement,
        "receiptWire": receipt_wire,
        "receiptBytes": receipt_bytes,
        "receiptStatementDigest": statement_digest,
        "receiptSignatureMessage": signature_message,
        "receiptRefWire": {
            "id": receipt_wire["id"],
            "digest": digest_text(hashlib.sha256(
                b"pf.bootstrap-approval-verifier-receipt.v1\x00"
                + receipt_bytes
            ).digest()),
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


def formal_gate_catalog_ref_wire(catalog_wire: dict, catalog_bytes: bytes) -> dict:
    return {
        "schema": catalog_wire["schema"],
        "id": catalog_wire["id"],
        "version": catalog_wire["version"],
        "contentSha256": hashlib.sha256(catalog_bytes).hexdigest(),
        "catalogDigest": hashlib.sha256(
            b"pf.gate-catalog.v1\x00" + catalog_bytes
        ).hexdigest(),
    }


def signed_formal_gate_catalog_approval_fixture(
    module: ModuleType,
) -> dict[str, object]:
    policy_wire = valid_bootstrap_authority_policy()
    policy_bytes = module.canonical_pf_jcs(policy_wire)
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)
    phase5_snapshot = make_phase5_snapshot(module)
    required_wire = signed_document_bound_required_set(
        module, policy_ref, phase5_snapshot
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    required_ref_wire = task_approval_required_set_ref(module, required_bytes)
    catalog_wire = formal_gate_catalog_wire(required_ref_wire)
    catalog_bytes = module.canonical_pf_jcs(catalog_wire)
    catalog_ref_wire = formal_gate_catalog_ref_wire(catalog_wire, catalog_bytes)
    statement = {
        "schema": "proof-forge.formal-gate-catalog-approval.v1",
        "id": "formal-catalog-approval",
        "version": "1.0.0",
        "authorityPolicy": content_ref_wire(policy_ref),
        "requiredTestSet": copy.deepcopy(required_ref_wire),
        "catalog": copy.deepcopy(catalog_ref_wire),
    }
    approval_wire, statement_digest, signature_message = (
        sign_formal_gate_catalog_approval_statement(module, statement)
    )
    approval_bytes = module.canonical_pf_jcs(approval_wire)
    return {
        "policyWire": policy_wire,
        "policyBytes": policy_bytes,
        "policyRef": policy_ref,
        "phase5Snapshot": phase5_snapshot,
        "requiredWire": required_wire,
        "requiredBytes": required_bytes,
        "requiredRefWire": required_ref_wire,
        "catalogWire": catalog_wire,
        "catalogBytes": catalog_bytes,
        "catalogRefWire": catalog_ref_wire,
        "approvalStatement": statement,
        "approvalWire": approval_wire,
        "approvalBytes": approval_bytes,
        "approvalStatementDigest": statement_digest,
        "approvalSignatureMessage": signature_message,
        "approvalDigest": hashlib.sha256(
            b"pf.formal-gate-catalog-approval.v1\x00" + approval_bytes
        ).digest(),
    }


def test_bootstrap_approval_set(module: ModuleType) -> None:
    fixture = signed_bootstrap_approval_set_fixture(module)
    set_wire = fixture["setWire"]
    set_bytes = fixture["setBytes"]
    task_receipt_bytes = fixture["taskReceiptBytes"]
    required_bytes = fixture["requiredBytes"]
    policy_bytes = fixture["policyBytes"]
    phase5_snapshot = fixture["phase5Snapshot"]
    handoff_bytes = fixture["handoffBytes"]
    aggregate_built = fixture["aggregateBuilt"]
    assert isinstance(set_wire, dict)
    assert isinstance(set_bytes, bytes)
    assert isinstance(task_receipt_bytes, tuple)
    assert isinstance(required_bytes, bytes)
    assert isinstance(policy_bytes, bytes)
    assert isinstance(handoff_bytes, bytes)
    assert isinstance(aggregate_built, dict)

    def parse_set(
        approval_set_input: bytes,
        receipt_inputs: tuple[bytes, ...] = task_receipt_bytes,
    ) -> object:
        return module.parse_bootstrap_approval_set(
            approval_set_input,
            receipt_inputs,
            required_bytes,
            policy_bytes,
            phase5_snapshot,
            handoff_bytes,
        )

    parsed, parsed_ref = parse_set(set_bytes)
    expected_approvals = tuple(
        module.parse_task_approval(
            aggregate_built[task_id]["approvalBytes"],
            required_bytes,
            policy_bytes,
            phase5_snapshot,
        )[0]
        for task_id in BOOTSTRAP_APPROVAL_SET_TASK_IDS
    )
    expected_receipts = tuple(
        module.BootstrapTaskVerifierReceiptRefV1(
            receipt_ref["taskId"],
            receipt_ref["id"],
            module.parse_digest(receipt_ref["digest"]),
        )
        for receipt_ref in set_wire["taskReceipts"]
    )
    expected = module.BootstrapApprovalSetV1(
        set_wire["schema"],
        set_wire["id"],
        set_wire["version"],
        module.parse_candidate_identity(set_wire["candidate"]),
        module.parse_content_ref(set_wire["authorityPolicy"]),
        expected_approvals[0].taskBreakdown,
        module.parse_content_ref(set_wire["requiredTestSet"]),
        module.parse_content_ref(set_wire["stage0Handoff"]),
        expected_approvals,
        expected_receipts,
        tuple(
            module.ApprovalSignatureV1(
                signature["keyId"],
                signature["algorithm"],
                bytes.fromhex(signature["signature"]),
            )
            for signature in set_wire["signatures"]
        ),
    )
    set_ref_wire = fixture["setRefWire"]
    assert isinstance(set_ref_wire, dict)
    expected_ref = module.ContentRef(
        set_ref_wire["schema"],
        set_ref_wire["id"],
        set_ref_wire["version"],
        module.parse_digest(set_ref_wire["digest"]),
    )
    if parsed != expected:
        raise AssertionError(
            "bootstrap set positive must preserve every frozen typed field"
        )
    if parsed_ref != expected_ref:
        raise AssertionError(
            "bootstrap set ref must use the full signed-object domain digest"
        )
    if tuple(approval.taskId for approval in parsed.taskApprovals) != (
        BOOTSTRAP_APPROVAL_SET_TASK_IDS
    ):
        raise AssertionError("bootstrap set approvals must be exact D0-01..06 order")
    if tuple(receipt.taskId for receipt in parsed.taskReceipts) != (
        BOOTSTRAP_APPROVAL_SET_TASK_IDS
    ):
        raise AssertionError("bootstrap set receipts must be exact D0-01..06 order")

    expected_statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-set-statement.v1\x00"
        + module.canonical_pf_jcs(fixture["setStatement"])
    ).digest()
    if fixture["setStatementDigest"] != expected_statement_digest:
        raise AssertionError("bootstrap set statement digest domain drift")
    if fixture["setSignatureMessage"] != (
        b"pf.bootstrap-approval-set-signature.v1\x00"
        + expected_statement_digest
    ):
        raise AssertionError("bootstrap set signature message domain drift")

    def expect_set_rejected(operation: Callable[[], object], label: str) -> None:
        try:
            result = operation()
        except module.Rejected as rejected:
            result = rejected
        if not isinstance(result, module.Rejected):
            raise AssertionError(f"{label} must produce Rejected")
        if result.code != BOOTSTRAP_REJECTION:
            raise AssertionError(f"{label} must use the bootstrap rejection code")

    malformed_field = copy.deepcopy(set_wire)
    malformed_field["futureField"] = True
    malformed_receipts = list(task_receipt_bytes)
    malformed_receipts[0] = b"{"
    for label, operation in (
        ("malformed set bytes", lambda: parse_set(b"{")),
        (
            "unknown set field",
            lambda: parse_set(module.canonical_pf_jcs(malformed_field)),
        ),
        (
            "malformed task receipt bytes",
            lambda: parse_set(set_bytes, tuple(malformed_receipts)),
        ),
    ):
        expect_set_rejected(operation, label)

    tampered_set_signature = copy.deepcopy(set_wire)
    tampered_set_signature["signatures"][0]["signature"] = "00" * 64
    unknown_set_signer = copy.deepcopy(set_wire)
    unknown_set_signer["signatures"][-1]["keyId"] = "key-unlisted"
    under_quorum_set, _, _ = sign_bootstrap_approval_set_statement(
        module,
        fixture["setStatement"],
        ("key-quality", "key-security"),
    )
    missing_required_role_set, _, _ = sign_bootstrap_approval_set_statement(
        module,
        fixture["setStatement"],
        ("key-architecture", "key-quality", "key-release"),
    )
    for label, invalid_wire in (
        ("tampered bootstrap-set signature", tampered_set_signature),
        ("bootstrap-set signer absent from policy", unknown_set_signer),
        ("bootstrap-set signer quorum below three", under_quorum_set),
        (
            "bootstrap-set signatures omit required security role",
            missing_required_role_set,
        ),
    ):
        expect_set_rejected(
            lambda invalid_wire=invalid_wire: parse_set(
                module.canonical_pf_jcs(invalid_wire)
            ),
            label,
        )

    tampered_embedded_set = copy.deepcopy(set_wire)
    tampered_embedded_approval = tampered_embedded_set["taskApprovals"][0]
    tampered_embedded_approval["signatures"][0]["signature"] = "00" * 64
    tampered_embedded_approval_bytes = module.canonical_pf_jcs(
        tampered_embedded_approval
    )
    tampered_embedded_receipt = copy.deepcopy(
        aggregate_built["TASK-D0-01"]["receiptWire"]
    )
    tampered_embedded_receipt["taskApproval"]["digest"] = digest_text(
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00"
            + tampered_embedded_approval_bytes
        ).digest()
    )
    tampered_embedded_receipt = resign_bootstrap_task_receipt_wire(
        module, tampered_embedded_receipt
    )
    tampered_embedded_receipt_bytes = module.canonical_pf_jcs(
        tampered_embedded_receipt
    )
    tampered_embedded_set["taskReceipts"][0] = (
        bootstrap_task_receipt_ref_wire(
            module,
            "TASK-D0-01",
            tampered_embedded_receipt["id"],
            tampered_embedded_receipt_bytes,
        )
    )
    tampered_embedded_set_bytes = module.canonical_pf_jcs(
        resign_bootstrap_approval_set_wire(module, tampered_embedded_set)
    )
    tampered_embedded_receipts = list(task_receipt_bytes)
    tampered_embedded_receipts[0] = tampered_embedded_receipt_bytes
    expect_set_rejected(
        lambda: parse_set(
            tampered_embedded_set_bytes,
            tuple(tampered_embedded_receipts),
        ),
        "tampered embedded TaskApproval signature with coherent receipt refs",
    )

    tampered_raw_receipt = copy.deepcopy(
        aggregate_built["TASK-D0-01"]["receiptWire"]
    )
    tampered_raw_receipt["signature"]["signature"] = "00" * 64
    tampered_raw_receipt_bytes = module.canonical_pf_jcs(
        tampered_raw_receipt
    )
    tampered_receipt_set = copy.deepcopy(set_wire)
    tampered_receipt_set["taskReceipts"][0] = (
        bootstrap_task_receipt_ref_wire(
            module,
            "TASK-D0-01",
            tampered_raw_receipt["id"],
            tampered_raw_receipt_bytes,
        )
    )
    tampered_receipt_set_bytes = module.canonical_pf_jcs(
        resign_bootstrap_approval_set_wire(module, tampered_receipt_set)
    )
    tampered_raw_receipts = list(task_receipt_bytes)
    tampered_raw_receipts[0] = tampered_raw_receipt_bytes
    expect_set_rejected(
        lambda: parse_set(
            tampered_receipt_set_bytes,
            tuple(tampered_raw_receipts),
        ),
        "tampered raw task-receipt signature with coherent set ref",
    )

    def signed_set_mutation(mutator: Callable[[dict], None]) -> bytes:
        mutated = copy.deepcopy(set_wire)
        mutator(mutated)
        return module.canonical_pf_jcs(
            resign_bootstrap_approval_set_wire(module, mutated)
        )

    structural_cases = (
        (
            "missing approval",
            signed_set_mutation(lambda wire: wire["taskApprovals"].pop()),
        ),
        (
            "missing receipt ref",
            signed_set_mutation(lambda wire: wire["taskReceipts"].pop()),
        ),
        (
            "duplicate approval",
            signed_set_mutation(
                lambda wire: wire["taskApprovals"].__setitem__(
                    1, copy.deepcopy(wire["taskApprovals"][0])
                )
            ),
        ),
        (
            "duplicate receipt ref",
            signed_set_mutation(
                lambda wire: wire["taskReceipts"].__setitem__(
                    1, copy.deepcopy(wire["taskReceipts"][0])
                )
            ),
        ),
        (
            "reordered approvals",
            signed_set_mutation(
                lambda wire: wire["taskApprovals"].__setitem__(
                    slice(0, 2),
                    [wire["taskApprovals"][1], wire["taskApprovals"][0]],
                )
            ),
        ),
        (
            "reordered receipt refs",
            signed_set_mutation(
                lambda wire: wire["taskReceipts"].__setitem__(
                    slice(0, 2),
                    [wire["taskReceipts"][1], wire["taskReceipts"][0]],
                )
            ),
        ),
        (
            "task receipt ref mismatch",
            signed_set_mutation(
                lambda wire: wire["taskReceipts"][0].__setitem__(
                    "digest", digest_text(bytes.fromhex("d1" * 32))
                )
            ),
        ),
        (
            "candidate mismatch",
            signed_set_mutation(
                lambda wire: wire.__setitem__(
                    "candidate", candidate_identity_wire(module, "c" * 40)
                )
            ),
        ),
        (
            "authority policy mismatch",
            signed_set_mutation(
                lambda wire: wire["authorityPolicy"].__setitem__(
                    "digest", digest_text(bytes.fromhex("d2" * 32))
                )
            ),
        ),
        (
            "task-breakdown root mismatch",
            signed_set_mutation(
                lambda wire: wire["taskBreakdown"].__setitem__(
                    "contentDigest", digest_text(bytes.fromhex("d4" * 32))
                )
            ),
        ),
        (
            "required-test-set root mismatch",
            signed_set_mutation(
                lambda wire: wire["requiredTestSet"].__setitem__(
                    "digest", digest_text(bytes.fromhex("d5" * 32))
                )
            ),
        ),
        (
            "Stage-0 handoff root mismatch",
            signed_set_mutation(
                lambda wire: wire["stage0Handoff"].__setitem__(
                    "digest", digest_text(bytes.fromhex("d6" * 32))
                )
            ),
        ),
        (
            "extra seventh task approval",
            signed_set_mutation(
                lambda wire: wire["taskApprovals"].append(
                    copy.deepcopy(wire["taskApprovals"][-1])
                )
            ),
        ),
        (
            "substitute TASK-D0-07 approval",
            signed_set_mutation(
                lambda wire: wire["taskApprovals"][-1].__setitem__(
                    "taskId", "TASK-D0-07"
                )
            ),
        ),
    )
    for label, mutated_bytes in structural_cases:
        expect_set_rejected(
            lambda mutated_bytes=mutated_bytes: parse_set(mutated_bytes),
            label,
        )

    expect_set_rejected(
        lambda: parse_set(set_bytes, task_receipt_bytes[:-1]),
        "missing raw receipt",
    )
    duplicate_raw_receipts = list(task_receipt_bytes)
    duplicate_raw_receipts[1] = duplicate_raw_receipts[0]
    expect_set_rejected(
        lambda: parse_set(set_bytes, tuple(duplicate_raw_receipts)),
        "duplicate raw receipt",
    )
    reordered_raw_receipts = list(task_receipt_bytes)
    reordered_raw_receipts[0], reordered_raw_receipts[1] = (
        reordered_raw_receipts[1],
        reordered_raw_receipts[0],
    )
    expect_set_rejected(
        lambda: parse_set(set_bytes, tuple(reordered_raw_receipts)),
        "reordered raw receipts",
    )

    mismatched_receipt_wire = copy.deepcopy(
        aggregate_built["TASK-D0-01"]["receiptWire"]
    )
    mismatched_receipt_wire["taskApproval"]["digest"] = digest_text(
        bytes.fromhex("d3" * 32)
    )
    mismatched_receipt_wire = resign_bootstrap_task_receipt_wire(
        module, mismatched_receipt_wire
    )
    mismatched_receipt_bytes = module.canonical_pf_jcs(
        mismatched_receipt_wire
    )
    mismatched_set_wire = copy.deepcopy(set_wire)
    mismatched_set_wire["taskReceipts"][0] = bootstrap_task_receipt_ref_wire(
        module,
        "TASK-D0-01",
        mismatched_receipt_wire["id"],
        mismatched_receipt_bytes,
    )
    mismatched_set_bytes = module.canonical_pf_jcs(
        resign_bootstrap_approval_set_wire(module, mismatched_set_wire)
    )
    mismatched_receipt_inputs = list(task_receipt_bytes)
    mismatched_receipt_inputs[0] = mismatched_receipt_bytes
    expect_set_rejected(
        lambda: parse_set(
            mismatched_set_bytes, tuple(mismatched_receipt_inputs)
        ),
        "receipt task-approval ref mismatch",
    )

    def coherently_replace_task_dependencies(
        dependency_refs: list[dict],
    ) -> tuple[bytes, tuple[bytes, ...]]:
        task_id = "TASK-D0-04"
        task_index = BOOTSTRAP_APPROVAL_SET_TASK_IDS.index(task_id)
        approval_wire = copy.deepcopy(
            aggregate_built[task_id]["approvalWire"]
        )
        approval_wire["dependencyCompletions"] = copy.deepcopy(
            dependency_refs
        )
        approval_wire = resign_task_approval_wire(
            module,
            approval_wire,
            tuple(
                key_id for key_id, _ in D0_GRAPH_ROWS[task_id]["signers"]
            ),
        )
        approval_bytes = module.canonical_pf_jcs(approval_wire)
        approval_ref = {
            "taskId": task_id,
            "digest": digest_text(hashlib.sha256(
                b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
            ).digest()),
        }

        receipt_wire = copy.deepcopy(
            aggregate_built[task_id]["receiptWire"]
        )
        receipt_wire["dependencyCompletions"] = copy.deepcopy(
            dependency_refs
        )
        receipt_wire["taskApproval"] = approval_ref
        receipt_wire = resign_bootstrap_task_receipt_wire(
            module, receipt_wire
        )
        receipt_bytes = module.canonical_pf_jcs(receipt_wire)

        mutated_set = copy.deepcopy(set_wire)
        mutated_set["taskApprovals"][task_index] = approval_wire
        mutated_set["taskReceipts"][task_index] = (
            bootstrap_task_receipt_ref_wire(
                module,
                task_id,
                receipt_wire["id"],
                receipt_bytes,
            )
        )
        mutated_set = resign_bootstrap_approval_set_wire(
            module, mutated_set
        )
        mutated_receipts = list(task_receipt_bytes)
        mutated_receipts[task_index] = receipt_bytes
        return module.canonical_pf_jcs(mutated_set), tuple(mutated_receipts)

    empty_topology_set, empty_topology_receipts = (
        coherently_replace_task_dependencies([])
    )
    expect_set_rejected(
        lambda: parse_set(empty_topology_set, empty_topology_receipts),
        "coherently signed D0-04 approval and receipt with empty dependencies",
    )

    foreign_dependency_refs = copy.deepcopy(
        aggregate_built["TASK-D0-04"]["approvalWire"][
            "dependencyCompletions"
        ]
    )
    foreign_dependency_refs[0]["digest"] = digest_text(
        bytes.fromhex("e7" * 32)
    )
    foreign_dependency_set, foreign_dependency_receipts = (
        coherently_replace_task_dependencies(foreign_dependency_refs)
    )
    expect_set_rejected(
        lambda: parse_set(
            foreign_dependency_set, foreign_dependency_receipts
        ),
        "coherently signed D0-04 dependency ref absent from this set",
    )

    original_decode_point = module._decode_point
    original_verify_ed25519 = module.verify_ed25519
    subgroup_curve_calls = 0
    signature_curve_calls = 0

    def counted_decode_point(encoded: bytes) -> object:
        nonlocal subgroup_curve_calls
        subgroup_curve_calls += 1
        return original_decode_point(encoded)

    def counted_verify_ed25519(
        public_key: bytes,
        message: bytes,
        signature: bytes,
    ) -> bool:
        nonlocal signature_curve_calls
        signature_curve_calls += 1
        return original_verify_ed25519(public_key, message, signature)

    module._decode_point = counted_decode_point
    module.verify_ed25519 = counted_verify_ed25519
    try:
        expect_set_rejected(
            lambda: module.parse_bootstrap_approval_set(
                set_bytes,
                task_receipt_bytes,
                required_bytes,
                policy_bytes,
                phase5_snapshot,
                b"{",
            ),
            "malformed late Stage-0 handoff",
        )
    finally:
        module._decode_point = original_decode_point
        module.verify_ed25519 = original_verify_ed25519
    if subgroup_curve_calls != 0 or signature_curve_calls != 0:
        raise AssertionError(
            "malformed late Stage-0 handoff must reject before every public-key "
            "subgroup or signature curve operation"
        )


def test_bootstrap_approval_verifier_receipt(module: ModuleType) -> None:
    fixture = signed_bootstrap_approval_verifier_receipt_fixture(module)
    set_fixture = fixture["setFixture"]
    assert isinstance(set_fixture, dict)
    receipt_wire = fixture["receiptWire"]
    assert isinstance(receipt_wire, dict)
    receipt_bytes = fixture["receiptBytes"]
    assert isinstance(receipt_bytes, bytes)
    set_bytes = set_fixture["setBytes"]
    task_receipt_bytes = set_fixture["taskReceiptBytes"]
    required_bytes = set_fixture["requiredBytes"]
    policy_bytes = set_fixture["policyBytes"]
    phase5_snapshot = set_fixture["phase5Snapshot"]
    handoff_bytes = set_fixture["handoffBytes"]
    assert isinstance(set_bytes, bytes)
    assert isinstance(task_receipt_bytes, tuple)
    assert isinstance(required_bytes, bytes)
    assert isinstance(policy_bytes, bytes)
    assert isinstance(handoff_bytes, bytes)

    def parse_receipt(
        verifier_receipt_input: bytes,
        approval_set_input: bytes = set_bytes,
        receipt_inputs: tuple[bytes, ...] = task_receipt_bytes,
    ) -> object:
        return module.parse_bootstrap_approval_verifier_receipt(
            verifier_receipt_input,
            approval_set_input,
            receipt_inputs,
            required_bytes,
            policy_bytes,
            phase5_snapshot,
            handoff_bytes,
        )

    parsed, parsed_ref = parse_receipt(receipt_bytes)
    expected = module.BootstrapApprovalVerifierReceiptV1(
        receipt_wire["schema"],
        receipt_wire["id"],
        module.parse_candidate_identity(receipt_wire["candidate"]),
        module.parse_content_ref(receipt_wire["authorityPolicy"]),
        module.parse_content_ref(receipt_wire["requiredTestSet"]),
        module.parse_content_ref(receipt_wire["approvalSet"]),
        module.parse_content_ref(receipt_wire["stage0Handoff"]),
        module.parse_digest(receipt_wire["verifierDigest"]),
        tuple(
            module.TaskApprovalRefV1(
                approval_ref["taskId"],
                module.parse_digest(approval_ref["digest"]),
            )
            for approval_ref in receipt_wire["taskApprovals"]
        ),
        tuple(
            module.BootstrapTaskVerifierReceiptRefV1(
                receipt_ref["taskId"],
                receipt_ref["id"],
                module.parse_digest(receipt_ref["digest"]),
            )
            for receipt_ref in receipt_wire["taskReceipts"]
        ),
        receipt_wire["result"],
        module.ApprovalSignatureV1(
            receipt_wire["signature"]["keyId"],
            receipt_wire["signature"]["algorithm"],
            bytes.fromhex(receipt_wire["signature"]["signature"]),
        ),
    )
    if parsed != expected:
        raise AssertionError(
            "verifier receipt positive must preserve every frozen typed field"
        )
    ref_wire = fixture["receiptRefWire"]
    assert isinstance(ref_wire, dict)
    expected_ref = module.BootstrapApprovalVerifierReceiptRefV1(
        ref_wire["id"],
        module.parse_digest(ref_wire["digest"]),
    )
    if parsed_ref != expected_ref:
        raise AssertionError(
            "verifier receipt ref must use the full signed-object domain digest"
        )
    parsed_stored_ref = module.parse_bootstrap_approval_verifier_receipt_ref(
        module.canonical_pf_jcs(ref_wire)
    )
    if parsed_stored_ref != expected_ref:
        raise AssertionError("stored verifier receipt ref must reparse exactly")

    receipt_statement = fixture["receiptStatement"]
    assert isinstance(receipt_statement, dict)
    expected_statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-verifier-receipt-statement.v1\x00"
        + module.canonical_pf_jcs(receipt_statement)
    ).digest()
    if fixture["receiptStatementDigest"] != expected_statement_digest:
        raise AssertionError("verifier receipt statement digest domain drift")
    if fixture["receiptSignatureMessage"] != (
        b"pf.bootstrap-approval-verifier-receipt-signature.v1\x00"
        + expected_statement_digest
    ):
        raise AssertionError("verifier receipt signature message domain drift")
    if module.parse_digest(ref_wire["digest"]).bytes != hashlib.sha256(
        b"pf.bootstrap-approval-verifier-receipt.v1\x00" + receipt_bytes
    ).digest():
        raise AssertionError("verifier receipt digest domain drift")

    def expect_receipt_rejected(
        operation: Callable[[], object],
        label: str,
    ) -> None:
        try:
            result = operation()
        except module.Rejected as rejected:
            result = rejected
        if not isinstance(result, module.Rejected):
            raise AssertionError(f"{label} must produce Rejected")
        if result.code != BOOTSTRAP_REJECTION:
            raise AssertionError(f"{label} must use the bootstrap rejection code")

    def signed_receipt_mutation(mutator: Callable[[dict], None]) -> bytes:
        mutated = copy.deepcopy(receipt_wire)
        mutator(mutated)
        return module.canonical_pf_jcs(
            resign_bootstrap_approval_verifier_receipt_wire(module, mutated)
        )

    unknown_field = copy.deepcopy(receipt_wire)
    unknown_field["futureField"] = True
    missing_field = copy.deepcopy(receipt_wire)
    missing_field.pop("verifierDigest")
    malformed_signature_hex = copy.deepcopy(receipt_wire)
    malformed_signature_hex["signature"]["signature"] = "00" * 63
    unknown_signature_field = copy.deepcopy(receipt_wire)
    unknown_signature_field["signature"]["futureField"] = True
    wrong_signature_algorithm = copy.deepcopy(receipt_wire)
    wrong_signature_algorithm["signature"]["algorithm"] = "ed25519ph"
    tampered_signature = copy.deepcopy(receipt_wire)
    tampered_signature["signature"]["signature"] = "00" * 64
    substituted_statement_id = copy.deepcopy(receipt_wire)
    substituted_statement_id["id"] = "BAV-20260718-0002"
    foreign_task_receipt_ref = {
        "taskId": "TASK-D0-01",
        "id": "BTV-20260718-0009",
        "digest": digest_text(bytes.fromhex("c2" * 32)),
    }
    wrong_key_id = module.canonical_pf_jcs(
        resign_bootstrap_approval_verifier_receipt_wire(
            module, receipt_wire, key_id="key-quality"
        )
    )
    wrong_key_wire, _, _ = sign_bootstrap_approval_verifier_receipt_statement(
        module,
        receipt_statement,
        seed=RFC_8032_SEEDS_BY_KEY_ID["key-quality"],
    )
    wrong_key = module.canonical_pf_jcs(wrong_key_wire)
    malformed_raw_receipts = list(task_receipt_bytes)
    malformed_raw_receipts[0] = b"{"
    reordered_raw_receipts = list(task_receipt_bytes)
    reordered_raw_receipts[0], reordered_raw_receipts[1] = (
        reordered_raw_receipts[1],
        reordered_raw_receipts[0],
    )

    for label, operation in (
        ("malformed receipt bytes", lambda: parse_receipt(b"{")),
        (
            "noncanonical receipt bytes",
            lambda: parse_receipt(b" " + receipt_bytes),
        ),
        (
            "unknown receipt field",
            lambda: parse_receipt(module.canonical_pf_jcs(unknown_field)),
        ),
        (
            "missing receipt field",
            lambda: parse_receipt(module.canonical_pf_jcs(missing_field)),
        ),
        (
            "malformed singular receipt signature",
            lambda: parse_receipt(
                module.canonical_pf_jcs(malformed_signature_hex)
            ),
        ),
        (
            "unknown singular receipt signature field",
            lambda: parse_receipt(
                module.canonical_pf_jcs(unknown_signature_field)
            ),
        ),
        (
            "wrong singular receipt signature algorithm",
            lambda: parse_receipt(
                module.canonical_pf_jcs(wrong_signature_algorithm)
            ),
        ),
        (
            "tampered receipt signature",
            lambda: parse_receipt(module.canonical_pf_jcs(tampered_signature)),
        ),
        (
            "receipt statement id substitution breaks signature",
            lambda: parse_receipt(
                module.canonical_pf_jcs(substituted_statement_id)
            ),
        ),
        (
            "ordinary principal key id cannot sign verifier receipt",
            lambda: parse_receipt(wrong_key_id),
        ),
        (
            "foreign key signature fails policy receipt key verification",
            lambda: parse_receipt(wrong_key),
        ),
        (
            "malformed approval-set bytes",
            lambda: parse_receipt(receipt_bytes, b"{"),
        ),
        (
            "malformed raw task receipt bytes",
            lambda: parse_receipt(
                receipt_bytes, set_bytes, tuple(malformed_raw_receipts)
            ),
        ),
        (
            "reordered raw task receipts",
            lambda: parse_receipt(
                receipt_bytes, set_bytes, tuple(reordered_raw_receipts)
            ),
        ),
        (
            "wrong receipt schema",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__(
                    "schema",
                    "proof-forge.bootstrap-approval-verifier-receipt.v2",
                )
            )),
        ),
        (
            "malformed receipt ID grammar",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__("id", "BAV-2026071-0001")
            )),
        ),
        (
            "receipt ID contains an impossible Gregorian date",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__("id", "BAV-20260230-0001")
            )),
        ),
        (
            "reordered task approval refs",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire["taskApprovals"].__setitem__(
                    slice(0, 2),
                    [wire["taskApprovals"][1], wire["taskApprovals"][0]],
                )
            )),
        ),
        (
            "missing task approval ref",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire["taskApprovals"].pop()
            )),
        ),
        (
            "task approval ref digest drift",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire["taskApprovals"][0].__setitem__(
                    "digest", digest_text(bytes.fromhex("c1" * 32))
                )
            )),
        ),
        (
            "reordered task receipt refs",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire["taskReceipts"].__setitem__(
                    slice(0, 2),
                    [wire["taskReceipts"][1], wire["taskReceipts"][0]],
                )
            )),
        ),
        (
            "substituted task receipt ref",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire["taskReceipts"].__setitem__(
                    0, copy.deepcopy(foreign_task_receipt_ref)
                )
            )),
        ),
        (
            "verifier digest drift",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__(
                    "verifierDigest", digest_text(bytes.fromhex("c3" * 32))
                )
            )),
        ),
        (
            "wrong receipt result",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__("result", "task-approved")
            )),
        ),
        (
            "receipt candidate join",
            lambda: parse_receipt(signed_receipt_mutation(
                lambda wire: wire.__setitem__(
                    "candidate", candidate_identity_wire(module, "c" * 40)
                )
            )),
        ),
    ):
        expect_receipt_rejected(operation, label)

    for ref_field in (
        "authorityPolicy",
        "requiredTestSet",
        "approvalSet",
        "stage0Handoff",
    ):
        for component, replacement in (
            ("schema", "proof-forge.unrelated.v1"),
            ("id", "different-content-ref"),
            ("version", "2.0.0"),
            ("digest", digest_text(bytes.fromhex("c5" * 32))),
        ):
            expect_receipt_rejected(
                lambda ref_field=ref_field,
                component=component,
                replacement=replacement: parse_receipt(
                    signed_receipt_mutation(
                        lambda wire: wire[ref_field].__setitem__(
                            component, replacement
                        )
                    )
                ),
                f"receipt {ref_field} full ContentRef {component} join",
            )

    original_decode_point = module._decode_point
    original_verify_ed25519 = module.verify_ed25519
    subgroup_curve_calls = 0
    signature_curve_calls = 0

    def counted_decode_point(encoded: bytes) -> object:
        nonlocal subgroup_curve_calls
        subgroup_curve_calls += 1
        return original_decode_point(encoded)

    def counted_verify_ed25519(
        public_key: bytes,
        message: bytes,
        signature: bytes,
    ) -> bool:
        nonlocal signature_curve_calls
        signature_curve_calls += 1
        return original_verify_ed25519(public_key, message, signature)

    wrong_schema_wire = copy.deepcopy(receipt_wire)
    wrong_schema_wire["schema"] = (
        "proof-forge.bootstrap-approval-verifier-receipt.v2"
    )
    module._decode_point = counted_decode_point
    module.verify_ed25519 = counted_verify_ed25519
    try:
        expect_receipt_rejected(
            lambda: parse_receipt(module.canonical_pf_jcs(wrong_schema_wire)),
            "wrong receipt schema rejects before set closure curve work",
        )
    finally:
        module._decode_point = original_decode_point
        module.verify_ed25519 = original_verify_ed25519
    if subgroup_curve_calls != 0 or signature_curve_calls != 0:
        raise AssertionError(
            "wrong receipt schema must reject before every public-key "
            "subgroup or signature curve operation"
        )

    def parse_ref(ref_input: bytes) -> object:
        return module.parse_bootstrap_approval_verifier_receipt_ref(ref_input)

    ref_id_drift = parse_ref(module.canonical_pf_jcs(
        dict(ref_wire, id="BAV-20260718-0002")
    ))
    if ref_id_drift == expected_ref:
        raise AssertionError(
            "ref id drift must not compare equal to the verified ref"
        )
    ref_digest_drift = parse_ref(module.canonical_pf_jcs(
        dict(ref_wire, digest=digest_text(bytes.fromhex("c4" * 32)))
    ))
    if ref_digest_drift == expected_ref:
        raise AssertionError(
            "ref digest drift must not compare equal to the verified ref"
        )

    unknown_ref_field = dict(ref_wire, futureField=True)
    missing_ref_field = dict(ref_wire)
    missing_ref_field.pop("digest")
    malformed_ref_id = dict(ref_wire, id="BAV-2026071-0001")
    impossible_date_ref_id = dict(ref_wire, id="BAV-20260230-0001")
    malformed_ref_digest = dict(ref_wire, digest="sha256:" + "0" * 63)
    duplicate_ref_key_bytes = (
        b'{"digest":"' + ref_wire["digest"].encode("ascii")
        + b'","id":"' + ref_wire["id"].encode("ascii")
        + b'","id":"' + ref_wire["id"].encode("ascii") + b'"}'
    )
    noncanonical_ref_bytes = (
        b'{"id":"' + ref_wire["id"].encode("ascii")
        + b'","digest":"' + ref_wire["digest"].encode("ascii") + b'"}'
    )
    for label, operation in (
        ("malformed ref bytes", lambda: parse_ref(b"{")),
        (
            "noncanonical ref bytes",
            lambda: parse_ref(noncanonical_ref_bytes),
        ),
        (
            "duplicate ref field",
            lambda: parse_ref(duplicate_ref_key_bytes),
        ),
        (
            "unknown ref field",
            lambda: parse_ref(module.canonical_pf_jcs(unknown_ref_field)),
        ),
        (
            "missing ref field",
            lambda: parse_ref(module.canonical_pf_jcs(missing_ref_field)),
        ),
        (
            "malformed ref ID grammar",
            lambda: parse_ref(module.canonical_pf_jcs(malformed_ref_id)),
        ),
        (
            "ref ID contains an impossible Gregorian date",
            lambda: parse_ref(
                module.canonical_pf_jcs(impossible_date_ref_id)
            ),
        ),
        (
            "malformed ref digest",
            lambda: parse_ref(module.canonical_pf_jcs(malformed_ref_digest)),
        ),
    ):
        expect_receipt_rejected(operation, label)


def test_formal_gate_catalog_approval(module: ModuleType) -> None:
    fixture = signed_formal_gate_catalog_approval_fixture(module)
    approval_wire = fixture["approvalWire"]
    assert isinstance(approval_wire, dict)
    approval_bytes = fixture["approvalBytes"]
    assert isinstance(approval_bytes, bytes)
    catalog_wire = fixture["catalogWire"]
    assert isinstance(catalog_wire, dict)
    catalog_bytes = fixture["catalogBytes"]
    assert isinstance(catalog_bytes, bytes)
    required_bytes = fixture["requiredBytes"]
    assert isinstance(required_bytes, bytes)
    policy_bytes = fixture["policyBytes"]
    assert isinstance(policy_bytes, bytes)
    catalog_ref_wire = fixture["catalogRefWire"]
    assert isinstance(catalog_ref_wire, dict)

    def parse_approval(
        approval_input: bytes = approval_bytes,
        catalog_input: bytes = catalog_bytes,
        required_input: bytes = required_bytes,
        policy_input: bytes = policy_bytes,
    ) -> object:
        return module.parse_formal_gate_catalog_approval(
            approval_input,
            catalog_input,
            required_input,
            policy_input,
        )

    parsed, parsed_digest = parse_approval()
    expected = module.FormalGateCatalogApprovalV1(
        approval_wire["schema"],
        approval_wire["id"],
        approval_wire["version"],
        module.parse_content_ref(approval_wire["authorityPolicy"]),
        module.parse_content_ref(approval_wire["requiredTestSet"]),
        module.GateCatalogRefV1(
            catalog_ref_wire["schema"],
            catalog_ref_wire["id"],
            catalog_ref_wire["version"],
            catalog_ref_wire["contentSha256"],
            catalog_ref_wire["catalogDigest"],
        ),
        tuple(
            module.ApprovalSignatureV1(
                signature["keyId"],
                signature["algorithm"],
                bytes.fromhex(signature["signature"]),
            )
            for signature in approval_wire["signatures"]
        ),
    )
    if parsed != expected:
        raise AssertionError(
            "formal catalog approval positive must preserve every typed field"
        )
    if parsed_digest != module.Digest("sha256", fixture["approvalDigest"]):
        raise AssertionError(
            "formal catalog approval digest must use the full signed-object "
            "domain digest"
        )

    approval_statement = fixture["approvalStatement"]
    assert isinstance(approval_statement, dict)
    expected_statement_digest = hashlib.sha256(
        b"pf.formal-gate-catalog-approval-statement.v1\x00"
        + module.canonical_pf_jcs(approval_statement)
    ).digest()
    if fixture["approvalStatementDigest"] != expected_statement_digest:
        raise AssertionError("formal catalog approval statement digest drift")
    if fixture["approvalSignatureMessage"] != (
        b"pf.formal-gate-catalog-approval-signature.v1\x00"
        + expected_statement_digest
    ):
        raise AssertionError("formal catalog approval signature message drift")
    if fixture["approvalDigest"] != hashlib.sha256(
        b"pf.formal-gate-catalog-approval.v1\x00" + approval_bytes
    ).digest():
        raise AssertionError("formal catalog approval digest domain drift")
    if catalog_ref_wire["contentSha256"] != hashlib.sha256(
        catalog_bytes
    ).hexdigest():
        raise AssertionError("catalog contentSha256 must hash the exact bytes")
    if catalog_ref_wire["catalogDigest"] != hashlib.sha256(
        b"pf.gate-catalog.v1\x00" + catalog_bytes
    ).hexdigest():
        raise AssertionError("catalog catalogDigest must use the frozen domain")

    def expect_approval_rejected(
        operation: Callable[[], object],
        label: str,
    ) -> None:
        try:
            result = operation()
        except module.Rejected as rejected:
            result = rejected
        if not isinstance(result, module.Rejected):
            raise AssertionError(f"{label} must produce Rejected")
        if result.code != BOOTSTRAP_REJECTION:
            raise AssertionError(f"{label} must use the bootstrap rejection code")

    def signed_approval_mutation(mutator: Callable[[dict], None]) -> bytes:
        mutated = copy.deepcopy(approval_wire)
        mutator(mutated)
        return module.canonical_pf_jcs(
            resign_formal_gate_catalog_approval_wire(module, mutated)
        )

    unknown_field = copy.deepcopy(approval_wire)
    unknown_field["futureField"] = True
    missing_field = copy.deepcopy(approval_wire)
    missing_field.pop("catalog")
    unknown_signer = copy.deepcopy(approval_wire)
    unknown_signer["signatures"][0]["keyId"] = "key-unlisted"
    tampered_signature = copy.deepcopy(approval_wire)
    tampered_signature["signatures"][0]["signature"] = "00" * 64
    malformed_signature_hex = copy.deepcopy(approval_wire)
    malformed_signature_hex["signatures"][0]["signature"] = "00" * 63
    unknown_signature_field = copy.deepcopy(approval_wire)
    unknown_signature_field["signatures"][0]["futureField"] = True
    wrong_signature_algorithm = copy.deepcopy(approval_wire)
    wrong_signature_algorithm["signatures"][0]["algorithm"] = "ed25519ph"
    substituted_statement_version = copy.deepcopy(approval_wire)
    substituted_statement_version["version"] = "1.0.1"
    renamed_ref_digest_field = copy.deepcopy(approval_wire)
    renamed_ref_digest_field["catalog"]["contentDigest"] = (
        renamed_ref_digest_field["catalog"].pop("contentSha256")
    )
    unknown_ref_field = copy.deepcopy(approval_wire)
    unknown_ref_field["catalog"]["futureField"] = True
    missing_ref_field = copy.deepcopy(approval_wire)
    missing_ref_field["catalog"].pop("catalogDigest")
    spec_common_ref_digest = copy.deepcopy(approval_wire)
    spec_common_ref_digest["catalog"]["contentSha256"] = (
        "sha256:" + "0" * 64
    )
    uppercase_ref_digest = copy.deepcopy(approval_wire)
    uppercase_ref_digest["catalog"]["catalogDigest"] = "A" * 64
    short_ref_digest = copy.deepcopy(approval_wire)
    short_ref_digest["catalog"]["contentSha256"] = "0" * 63
    unsigned_order_wire, _, _ = sign_formal_gate_catalog_approval_statement(
        module,
        approval_statement,
        ("key-security", "key-quality"),
    )
    under_quorum_wire, _, _ = sign_formal_gate_catalog_approval_statement(
        module,
        approval_statement,
        ("key-quality",),
    )
    missing_role_wire, _, _ = sign_formal_gate_catalog_approval_statement(
        module,
        approval_statement,
        ("key-architecture", "key-quality"),
    )

    def mutated_catalog_bytes(mutator: Callable[[dict], None]) -> bytes:
        mutated = copy.deepcopy(catalog_wire)
        mutator(mutated)
        return module.canonical_pf_jcs(mutated)

    drifted_required_catalog = copy.deepcopy(catalog_wire)
    drifted_required_catalog["requiredTestSet"]["digest"] = digest_text(
        bytes.fromhex("ca" * 32)
    )
    drifted_required_catalog_bytes = module.canonical_pf_jcs(
        drifted_required_catalog
    )
    drifted_required_approval = copy.deepcopy(approval_wire)
    drifted_required_approval["catalog"] = formal_gate_catalog_ref_wire(
        drifted_required_catalog, drifted_required_catalog_bytes
    )
    drifted_required_approval_bytes = module.canonical_pf_jcs(
        resign_formal_gate_catalog_approval_wire(
            module, drifted_required_approval
        )
    )

    for label, operation in (
        ("malformed approval bytes", lambda: parse_approval(b"{")),
        (
            "noncanonical approval bytes",
            lambda: parse_approval(b" " + approval_bytes),
        ),
        (
            "unknown approval field",
            lambda: parse_approval(module.canonical_pf_jcs(unknown_field)),
        ),
        (
            "missing approval field",
            lambda: parse_approval(module.canonical_pf_jcs(missing_field)),
        ),
        (
            "approval signer absent from policy",
            lambda: parse_approval(module.canonical_pf_jcs(unknown_signer)),
        ),
        (
            "tampered approval signature",
            lambda: parse_approval(
                module.canonical_pf_jcs(tampered_signature)
            ),
        ),
        (
            "malformed approval signature hex",
            lambda: parse_approval(
                module.canonical_pf_jcs(malformed_signature_hex)
            ),
        ),
        (
            "unknown approval signature field",
            lambda: parse_approval(
                module.canonical_pf_jcs(unknown_signature_field)
            ),
        ),
        (
            "wrong approval signature algorithm",
            lambda: parse_approval(
                module.canonical_pf_jcs(wrong_signature_algorithm)
            ),
        ),
        (
            "approval statement version substitution breaks signature",
            lambda: parse_approval(
                module.canonical_pf_jcs(substituted_statement_version)
            ),
        ),
        (
            "catalog ref renames contentSha256 to contentDigest",
            lambda: parse_approval(
                module.canonical_pf_jcs(renamed_ref_digest_field)
            ),
        ),
        (
            "unknown catalog ref field",
            lambda: parse_approval(module.canonical_pf_jcs(unknown_ref_field)),
        ),
        (
            "missing catalog ref field",
            lambda: parse_approval(module.canonical_pf_jcs(missing_ref_field)),
        ),
        (
            "catalog ref contentSha256 uses SPEC-COMMON Digest form",
            lambda: parse_approval(
                module.canonical_pf_jcs(spec_common_ref_digest)
            ),
        ),
        (
            "catalog ref catalogDigest is not lowercase hex",
            lambda: parse_approval(
                module.canonical_pf_jcs(uppercase_ref_digest)
            ),
        ),
        (
            "catalog ref contentSha256 has wrong length",
            lambda: parse_approval(module.canonical_pf_jcs(short_ref_digest)),
        ),
        (
            "approval signatures not in ascending keyId order",
            lambda: parse_approval(module.canonical_pf_jcs(unsigned_order_wire)),
        ),
        (
            "approval signer quorum below formalCatalogRule",
            lambda: parse_approval(module.canonical_pf_jcs(under_quorum_wire)),
        ),
        (
            "approval signatures omit required security role",
            lambda: parse_approval(module.canonical_pf_jcs(missing_role_wire)),
        ),
        (
            "wrong approval schema",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire.__setitem__(
                    "schema", "proof-forge.formal-gate-catalog-approval.v2"
                )
            )),
        ),
        (
            "approval id violates ContentRef id grammar",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire.__setitem__("id", "Formal-Catalog-Approval")
            )),
        ),
        (
            "approval version has leading zero",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire.__setitem__("version", "01.0.0")
            )),
        ),
        (
            "approval version is not exact SemVer",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire.__setitem__("version", "1.0")
            )),
        ),
        (
            "approval authority policy digest join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["authorityPolicy"].__setitem__(
                    "digest", digest_text(bytes.fromhex("c6" * 32))
                )
            )),
        ),
        (
            "approval authority policy schema join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["authorityPolicy"].__setitem__(
                    "schema", "proof-forge.unrelated.v1"
                )
            )),
        ),
        (
            "approval required-test-set digest join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["requiredTestSet"].__setitem__(
                    "digest", digest_text(bytes.fromhex("c7" * 32))
                )
            )),
        ),
        (
            "approval catalog ref id join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["catalog"].__setitem__(
                    "id", "different-catalog"
                )
            )),
        ),
        (
            "approval catalog ref version join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["catalog"].__setitem__("version", "2.0.0")
            )),
        ),
        (
            "approval catalog contentSha256 join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["catalog"].__setitem__(
                    "contentSha256", "c8" * 32
                )
            )),
        ),
        (
            "approval catalog catalogDigest join",
            lambda: parse_approval(signed_approval_mutation(
                lambda wire: wire["catalog"].__setitem__(
                    "catalogDigest", "c9" * 32
                )
            )),
        ),
        (
            "malformed catalog bytes",
            lambda: parse_approval(approval_bytes, b"{"),
        ),
        (
            "noncanonical catalog bytes",
            lambda: parse_approval(approval_bytes, b" " + catalog_bytes),
        ),
        (
            "catalog root has unknown field",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog.__setitem__("futureField", True)
            )),
        ),
        (
            "catalog qualification is development",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog.__setitem__(
                    "qualification", "development"
                )
            )),
        ),
        (
            "catalog requiredTestSet is explicit null",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog.__setitem__("requiredTestSet", None)
            )),
        ),
        (
            "catalog requiredTestSet digest join",
            lambda: parse_approval(
                drifted_required_approval_bytes,
                drifted_required_catalog_bytes,
            ),
        ),
        (
            "catalog id drift breaks approval catalog ref join",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog.__setitem__("id", "renamed-catalog")
            )),
        ),
        (
            "catalog locks missing field",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog["locks"].pop("finalizerSha256")
            )),
        ),
        (
            "catalog locks value is not lowercase SHA-256",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog["locks"].__setitem__(
                    "finalizerSha256", "0" * 63
                )
            )),
        ),
        (
            "catalog gates are empty",
            lambda: parse_approval(approval_bytes, mutated_catalog_bytes(
                lambda catalog: catalog.__setitem__("gates", [])
            )),
        ),
        (
            "malformed required-test-set bytes",
            lambda: parse_approval(approval_bytes, catalog_bytes, b"{"),
        ),
        (
            "malformed authority policy bytes",
            lambda: parse_approval(
                approval_bytes, catalog_bytes, required_bytes, b"{"
            ),
        ),
    ):
        expect_approval_rejected(operation, label)

    original_decode_point = module._decode_point
    original_verify_ed25519 = module.verify_ed25519
    subgroup_curve_calls = 0
    signature_curve_calls = 0

    def counted_decode_point(encoded: bytes) -> object:
        nonlocal subgroup_curve_calls
        subgroup_curve_calls += 1
        return original_decode_point(encoded)

    def counted_verify_ed25519(
        public_key: bytes,
        message: bytes,
        signature: bytes,
    ) -> bool:
        nonlocal signature_curve_calls
        signature_curve_calls += 1
        return original_verify_ed25519(public_key, message, signature)

    module._decode_point = counted_decode_point
    module.verify_ed25519 = counted_verify_ed25519
    try:
        expect_approval_rejected(
            lambda: parse_approval(b"{"),
            "malformed approval bytes reject before any curve work",
        )
    finally:
        module._decode_point = original_decode_point
        module.verify_ed25519 = original_verify_ed25519
    if subgroup_curve_calls != 0 or signature_curve_calls != 0:
        raise AssertionError(
            "malformed approval bytes must reject before every public-key "
            "subgroup or signature curve operation"
        )


def test_task_approval_exact_upper_and_sha256_identity(
    module: ModuleType,
) -> None:
    policy_bytes = module.canonical_pf_jcs(valid_bootstrap_authority_policy())
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)

    upper_test_ids = tuple(
        f"TST-BOUND-{index:04d}" for index in range(4096)
    )
    upper_phase5_snapshot = make_phase5_snapshot(
        module,
        required_ids=upper_test_ids,
    )
    upper_required_wire = signed_document_bound_required_set(
        module,
        policy_ref,
        upper_phase5_snapshot,
        required_ids=upper_test_ids,
    )
    upper_required_bytes = module.canonical_pf_jcs(upper_required_wire)
    upper_statement = task_approval_statement(
        module,
        policy_ref,
        upper_required_bytes,
    )
    upper_statement["testIds"] = list(upper_test_ids)
    upper_statement["evidence"] = [
        {
            "id": f"EV-20260716-{index:04d}",
            "digest": digest_text(bytes.fromhex("64" * 32)),
        }
        for index in range(4096)
    ]
    upper_statement["dependencyCompletions"] = [
        {
            "taskId": f"TASK-D0-0{task_number}",
            "id": f"BTV-20260716-{task_number:04d}",
            "digest": digest_text(bytes([task_number]) * 32),
        }
        for task_number in range(2, 7)
    ]
    upper_statement["prerequisiteDocuments"] = [
        normative_document_ref_wire(
            f"PHASE-BOUND-{index:03d}",
            "a" * 40,
        )
        for index in range(256)
    ]
    upper_statement["independentReviews"] = [
        independent_review_wire(key_id, role, "a" * 40)
        for key_id, role in (
            ("key-architecture", "architecture"),
            ("key-quality", "quality"),
            ("key-release", "release"),
            ("key-security", "security"),
        )
    ]
    upper_wire, _, _ = sign_task_approval_statement(
        module,
        upper_statement,
        signer_key_ids=(
            "key-architecture",
            "key-quality",
            "key-release",
            "key-security",
        ),
    )
    upper_approval_bytes = module.canonical_pf_jcs(upper_wire)
    assert len(upper_phase5_snapshot.bytes) <= 4 * 1024 * 1024
    assert len(upper_required_bytes) <= 4 * 1024 * 1024
    assert len(upper_approval_bytes) <= 4 * 1024 * 1024
    upper_parsed, _ = module.parse_task_approval(
        upper_approval_bytes,
        upper_required_bytes,
        policy_bytes,
        upper_phase5_snapshot,
    )
    assert (
        len(upper_parsed.testIds),
        len(upper_parsed.evidence),
        len(upper_parsed.dependencyCompletions),
        len(upper_parsed.prerequisiteDocuments),
        len(upper_parsed.independentReviews),
        len(upper_parsed.signatures),
    ) == (4096, 4096, 5, 256, 4, 4), (
        "TaskApproval public parser must accept every simultaneous exact upper "
        "bound against the matching PHASE-5 denominator and RequiredTestSet"
    )

    sha256_commit = "c" * 64
    phase5_snapshot = make_phase5_snapshot(module)
    required_wire = signed_document_bound_required_set(
        module,
        policy_ref,
        phase5_snapshot,
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    sha256_statement = task_approval_statement(
        module,
        policy_ref,
        required_bytes,
        commit=sha256_commit,
    )
    # NormativeDocumentRefV1 remains the frozen 40-digit review-commit shape;
    # TaskApproval's candidate and independent reviews separately accept either
    # Git object width and require an exact match with one another.
    sha256_statement["taskBreakdown"]["reviewCommit"] = "a" * 40
    for document in sha256_statement["prerequisiteDocuments"]:
        document["reviewCommit"] = "a" * 40
    sha256_wire, _, _ = sign_task_approval_statement(module, sha256_statement)
    sha256_parsed, _ = module.parse_task_approval(
        module.canonical_pf_jcs(sha256_wire),
        required_bytes,
        policy_bytes,
        phase5_snapshot,
    )
    assert sha256_parsed.candidate.commit == sha256_commit
    assert sha256_parsed.candidate.treeObjectId == "b" * 64
    assert all(
        review.reviewCommit == sha256_commit
        for review in sha256_parsed.independentReviews
    ), "64-digit independent review commits must exactly match the candidate"

    invalid_review_commit = copy.deepcopy(sha256_wire)
    invalid_review_commit["independentReviews"][0]["reviewCommit"] = "c" * 63
    invalid_review_commit = resign_task_approval_wire(
        module,
        invalid_review_commit,
    )
    original_verify_ed25519 = module.verify_ed25519
    curve_calls = 0

    def counted_verify_ed25519(
        public_key: bytes,
        message: bytes,
        signature: bytes,
    ) -> bool:
        del public_key, message, signature
        nonlocal curve_calls
        curve_calls += 1
        return True

    module.verify_ed25519 = counted_verify_ed25519
    try:
        assert_rejected(
            module,
            lambda: module.parse_task_approval(
                module.canonical_pf_jcs(invalid_review_commit),
                required_bytes,
                policy_bytes,
                phase5_snapshot,
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert curve_calls == 0, (
        "illegal 63-digit independent review commit must reject before every "
        "RequiredTestSet or TaskApproval signature curve"
    )


def test_phase4_snapshot_authority(module: ModuleType) -> None:
    snapshot = make_phase4_snapshot(module)
    parsed = module.parse_phase4_snapshot_content(snapshot)
    expected_document_wire = expected_phase4_document_wire(snapshot)
    expected_document = module.NormativeDocumentRefV1(
        "PHASE-4",
        module.parse_digest(expected_document_wire["contentDigest"]),
        "accepted",
        PHASE4_FRONTMATTER["reviewCommit"],
        PHASE4_FRONTMATTER["reviewLink"],
        PHASE4_FRONTMATTER["approvedAt"],
        tuple(PHASE4_FRONTMATTER["approvers"].split(", ")),
    )
    expected_rows = tuple(
        module.Phase4TaskRowV1(
            task_id,
            D0_GRAPH_ROWS[task_id]["dependencies"],
            D0_GRAPH_ROWS[task_id]["prerequisites"],
            D0_GRAPH_ROWS[task_id]["testIds"],
            D0_GRAPH_ROWS[task_id]["evidenceIds"],
        )
        for task_id in D0_GRAPH_ROWS
    )
    assert parsed == module.Phase4SnapshotContentV1(
        expected_document,
        expected_rows,
    ), "PHASE-4 parser must derive the exact accepted ref and six row projection"
    assert all(
        row.taskId != "TASK-D0-07" for row in parsed.bootstrapTaskRows
    ), "TASK-D0-07 must be validated but excluded from the bootstrap projection"

    reordered_metadata = dict(reversed(tuple(PHASE4_FRONTMATTER.items())))
    reordered = module.parse_phase4_snapshot_content(
        make_phase4_snapshot(module, metadata=reordered_metadata)
    )
    assert reordered.bootstrapTaskRows == expected_rows
    assert reordered.document.reviewLink == PHASE4_FRONTMATTER["reviewLink"]

    class ForgedSnapshot(module.BootstrapDocumentSnapshotV1):
        pass

    class ForgedBytes(bytes):
        pass

    class ExplosiveScalar:
        def __eq__(self, other: object) -> bool:
            del other
            raise AssertionError("untyped PHASE-4 scalar equality must not run")

    for label, invalid_snapshot in (
        ("untyped snapshot", {"id": "PHASE-4"}),
        (
            "snapshot subclass",
            ForgedSnapshot(snapshot.id, snapshot.path, snapshot.bytes),
        ),
        ("untyped snapshot ID", dataclasses.replace(snapshot, id=ExplosiveScalar())),
        ("untyped snapshot path", dataclasses.replace(snapshot, path=ExplosiveScalar())),
        ("wrong snapshot ID", dataclasses.replace(snapshot, id="PHASE-5")),
        (
            "wrong snapshot path",
            dataclasses.replace(snapshot, path="docs/phase-4.md"),
        ),
        ("empty snapshot", dataclasses.replace(snapshot, bytes=b"")),
        ("one-byte snapshot", dataclasses.replace(snapshot, bytes=b"\n")),
        (
            "untyped snapshot bytes",
            dataclasses.replace(snapshot, bytes=bytearray(snapshot.bytes)),
        ),
        (
            "snapshot bytes subclass",
            dataclasses.replace(snapshot, bytes=ForgedBytes(snapshot.bytes)),
        ),
        (
            "snapshot over 4 MiB",
            dataclasses.replace(snapshot, bytes=b"x" * (4 * 1024 * 1024 + 1)),
        ),
        (
            "UTF-8 BOM",
            dataclasses.replace(snapshot, bytes=b"\xef\xbb\xbf" + snapshot.bytes),
        ),
        ("NUL byte", dataclasses.replace(snapshot, bytes=snapshot.bytes + b"\x00\n")),
        (
            "CR byte",
            dataclasses.replace(
                snapshot,
                bytes=snapshot.bytes.replace(b"\n", b"\r\n", 1),
            ),
        ),
        ("invalid UTF-8", dataclasses.replace(snapshot, bytes=snapshot.bytes + b"\xff\n")),
        ("missing final LF", dataclasses.replace(snapshot, bytes=snapshot.bytes[:-1])),
    ):
        assert_rejected(
            module,
            lambda invalid_snapshot=invalid_snapshot: (
                module.parse_phase4_snapshot_content(invalid_snapshot)
            ),
        )

    def mutated(old: bytes, new: bytes) -> object:
        assert snapshot.bytes.count(old) == 1, (
            f"PHASE-4 fixture mutation must match once: {old!r}"
        )
        return dataclasses.replace(
            snapshot,
            bytes=snapshot.bytes.replace(old, new, 1),
        )

    row_01 = (
        b"| TASK-D0-01 | fixture for TASK-D0-01 | \xe2\x80\x94 | "
        b"PHASE-1@accepted, PHASE-2@accepted, PHASE-3@accepted | "
        b"TST-DOC-001 | EV-20260717-0001 | in_progress |"
    )
    row_02 = (
        b"| TASK-D0-02 | fixture for TASK-D0-02 | TASK-D0-01 | \xe2\x80\x94 | "
        b"TST-ISO-001 | EV-20260717-0002 | pending |"
    )
    row_03 = (
        b"| TASK-D0-03 | fixture for TASK-D0-03 | TASK-D0-01, TASK-D0-02 | "
        b"\xe2\x80\x94 | TST-EVIDENCE-001, TST-HOST-001, TST-TOOL-001 | "
        b"EV-20260717-0003, EV-20260717-0004 | pending |"
    )
    row_06 = (
        b"| TASK-D0-06 | fixture for TASK-D0-06 | TASK-D0-01, TASK-D0-02 | "
        b"\xe2\x80\x94 | TST-COMMON-001 | EV-20260717-0007 | pending |"
    )
    row_07 = (
        b"| TASK-D0-07 | fixture for TASK-D0-07 | TASK-D0-04 | \xe2\x80\x94 | "
        b"TST-EVIDENCE-002, TST-ISO-002 | \xe2\x80\x94 | pending |"
    )
    d0_heading = "## Milestone D0：文档与独立工程".encode()
    d1_heading = "## Milestone D1：语言前端".encode()
    table_header = (
        "| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |"
    ).encode()
    table_delimiter = b"|---|---|---|---|---|---|---|"
    mutations = (
        (
            "missing opening delimiter",
            dataclasses.replace(snapshot, bytes=snapshot.bytes[4:]),
        ),
        ("missing closing delimiter", mutated(b"\n---\n", b"\n--\n")),
        (
            "noncanonical scalar delimiter",
            mutated(b"title: Synthetic", b"title:  Synthetic"),
        ),
        ("wrong accepted status", mutated(b"status: accepted", b"status: proposed")),
        ("wrong normative flag", mutated(b"normative: true", b"normative: false")),
        ("open finding", mutated(b"openFindings: none", b"openFindings: P1")),
        ("invalid updated date", mutated(b"updated: 2026-07-16", b"updated: 2026-02-30")),
        (
            "invalid approved date",
            mutated(b"approvedAt: 2026-07-16", b"approvedAt: 2026-13-01"),
        ),
        (
            "invalid review commit",
            mutated(b"reviewCommit: " + b"a" * 40, b"reviewCommit: " + b"A" * 40),
        ),
        (
            "invalid review link",
            mutated(
                b"https://review.example/phase-4:443/approval",
                b"http://review.example/phase-4/approval",
            ),
        ),
        (
            "noncanonical approver delimiter",
            mutated(
                b"principal-quality, principal-security",
                b"principal-quality,principal-security",
            ),
        ),
        (
            "duplicate approver",
            mutated(
                b"principal-quality, principal-security",
                b"principal-quality, principal-quality",
            ),
        ),
        (
            "unsorted approvers",
            mutated(
                b"principal-quality, principal-security",
                b"principal-security, principal-quality",
            ),
        ),
        ("missing D0 heading", mutated(d0_heading, b"## Missing D0")),
        ("missing D1 boundary", mutated(d1_heading, b"## Missing D1")),
        ("wrong table header", mutated(table_header, b"| ID | wrong |")),
        ("wrong table delimiter", mutated(table_delimiter, b"|:---|---|---|---|---|---|---:|")),
        (
            "nonblank before table",
            mutated(d0_heading + b"\n\n", d0_heading + b"\nprose\n"),
        ),
        (
            "nonblank before D1",
            mutated(row_07 + b"\n\n" + d1_heading, row_07 + b"\nprose\n" + d1_heading),
        ),
        ("missing row", mutated(row_02 + b"\n", b"")),
        ("duplicate row", mutated(row_02 + b"\n", row_02 + b"\n" + row_02 + b"\n")),
        (
            "reordered rows",
            mutated(
                row_02 + b"\n" + row_03,
                row_03 + b"\n" + row_02,
            ),
        ),
        (
            "noncontiguous rows",
            mutated(row_02 + b"\n", row_02 + b"\n\n"),
        ),
        (
            "extra row",
            mutated(row_07 + b"\n", row_07 + b"\n" + row_07 + b"\n"),
        ),
        (
            "extra cell",
            mutated(row_02, row_02[:-2] + b" | extra |"),
        ),
        (
            "empty description",
            mutated(b"fixture for TASK-D0-02", b""),
        ),
        (
            "description control",
            mutated(b"fixture for TASK-D0-02", b"fixture\x01for TASK-D0-02"),
        ),
        (
            "description embedded pipe",
            mutated(b"fixture for TASK-D0-02", b"fixture | for TASK-D0-02"),
        ),
        ("bad status", mutated(b"| pending |\n" + row_03, b"| complete |\n" + row_03)),
        (
            "noncanonical comma delimiter",
            mutated(
                row_03,
                row_03.replace(
                    b"TASK-D0-01, TASK-D0-02",
                    b"TASK-D0-01,TASK-D0-02",
                    1,
                ),
            ),
        ),
        (
            "backtick token",
            mutated(b"TST-ISO-001", b"`TST-ISO-001`"),
        ),
        (
            "trimmed token",
            mutated(
                row_03,
                row_03.replace(
                    b"TASK-D0-01, TASK-D0-02",
                    b"TASK-D0-01,  TASK-D0-02",
                    1,
                ),
            ),
        ),
        (
            "duplicate source ID",
            mutated(
                b"TST-EVIDENCE-001, TST-HOST-001, TST-TOOL-001",
                b"TST-EVIDENCE-001, TST-EVIDENCE-001, TST-TOOL-001",
            ),
        ),
        (
            "unsorted source IDs",
            mutated(
                b"TST-EVIDENCE-001, TST-HOST-001, TST-TOOL-001",
                b"TST-TOOL-001, TST-HOST-001, TST-EVIDENCE-001",
            ),
        ),
        ("empty tests", mutated(b"TST-ISO-001", b"\xe2\x80\x94")),
        (
            "wrong prerequisite status",
            mutated(b"PHASE-1@accepted", b"PHASE-1@proposed"),
        ),
        (
            "missing prerequisite status",
            mutated(b"PHASE-1@accepted", b"PHASE-1"),
        ),
        (
            "range test ID",
            mutated(b"TST-ISO-001", b"TST-ISO-001..003"),
        ),
        (
            "empty list token",
            mutated(b"TST-ISO-001", b"TST-ISO-001, "),
        ),
        (
            "unknown dependency",
            mutated(b"TASK-D0-04 | \xe2\x80\x94", b"TASK-D0-99 | \xe2\x80\x94"),
        ),
        (
            "dependency cycle",
            mutated(row_01, row_01.replace(b"| \xe2\x80\x94 |", b"| TASK-D0-02 |", 1)),
        ),
        (
            "bootstrap depends on D0-07",
            mutated(row_06, row_06.replace(
                b"TASK-D0-01, TASK-D0-02",
                b"TASK-D0-01, TASK-D0-02, TASK-D0-07",
                1,
            )),
        ),
        (
            "invalid D0-07 test",
            mutated(b"TST-EVIDENCE-002, TST-ISO-002", b"TST-*"),
        ),
    )
    for label, invalid_snapshot in mutations:
        assert_rejected(
            module,
            lambda invalid_snapshot=invalid_snapshot: (
                module.parse_phase4_snapshot_content(invalid_snapshot)
            ),
        )

    duplicate_frontmatter = mutated(
        b"owner: delivery\n",
        b"owner: delivery\nowner: security\n",
    )
    missing_frontmatter = mutated(b"owner: delivery\n", b"")
    unknown_frontmatter = mutated(
        b"owner: delivery\n",
        b"owner: delivery\nfutureField: no\n",
    )
    duplicate_d0 = mutated(
        d0_heading + b"\n",
        b"```\n" + d0_heading + b"\n```\n" + d0_heading + b"\n",
    )
    duplicate_d0_in_html = mutated(
        d0_heading + b"\n",
        b"<!--\n" + d0_heading + b"\n-->\n" + d0_heading + b"\n",
    )
    duplicate_d1 = mutated(d1_heading + b"\n", d1_heading + b"\n" + d1_heading + b"\n")
    duplicate_header = mutated(table_header + b"\n", table_header + b"\n" + table_header + b"\n")
    duplicate_delimiter = mutated(
        table_delimiter + b"\n",
        table_delimiter + b"\n" + table_delimiter + b"\n",
    )
    reversed_milestones = snapshot.bytes.replace(
        d0_heading,
        b"PHASE4-D0-PLACEHOLDER",
        1,
    ).replace(
        d1_heading,
        d0_heading,
        1,
    ).replace(
        b"PHASE4-D0-PLACEHOLDER",
        d1_heading,
        1,
    )
    reversed_table_markers = snapshot.bytes.replace(
        table_header,
        b"PHASE4-TABLE-HEADER-PLACEHOLDER",
        1,
    ).replace(
        table_delimiter,
        table_header,
        1,
    ).replace(
        b"PHASE4-TABLE-HEADER-PLACEHOLDER",
        table_delimiter,
        1,
    )
    for invalid_snapshot in (
        duplicate_frontmatter,
        missing_frontmatter,
        unknown_frontmatter,
        duplicate_d0,
        duplicate_d0_in_html,
        duplicate_d1,
        duplicate_header,
        duplicate_delimiter,
        dataclasses.replace(snapshot, bytes=reversed_milestones),
        dataclasses.replace(snapshot, bytes=reversed_table_markers),
    ):
        assert_rejected(
            module,
            lambda invalid_snapshot=invalid_snapshot: (
                module.parse_phase4_snapshot_content(invalid_snapshot)
            ),
        )

    nonexact_decoys = snapshot.bytes.replace(
        d0_heading + b"\n",
        b"`" + d0_heading + b"`\n<!-- " + d0_heading + b" -->\n"
        + d0_heading + b"\n",
        1,
    )
    assert module.parse_phase4_snapshot_content(
        dataclasses.replace(snapshot, bytes=nonexact_decoys)
    ).bootstrapTaskRows == expected_rows


def test_phase5_snapshot_and_document_bound_join(module: ModuleType) -> None:
    policy_bytes = module.canonical_pf_jcs(valid_bootstrap_authority_policy())
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)
    snapshot = make_phase5_snapshot(module)

    parsed_content = module.parse_phase5_snapshot_content(snapshot)
    expected_document_wire = expected_phase5_document_wire(snapshot)
    expected_document = module.NormativeDocumentRefV1(
        "PHASE-5",
        module.parse_digest(expected_document_wire["contentDigest"]),
        "accepted",
        PHASE5_FRONTMATTER["reviewCommit"],
        PHASE5_FRONTMATTER["reviewLink"],
        PHASE5_FRONTMATTER["approvedAt"],
        tuple(PHASE5_FRONTMATTER["approvers"].split(", ")),
    )
    assert parsed_content == module.Phase5SnapshotContentV1(
        expected_document,
        tuple(sorted(PHASE5_REQUIRED_IDS)),
    ), "snapshot parser must derive the exact document ref and sorted denominator"
    reordered_metadata = dict(reversed(tuple(PHASE5_FRONTMATTER.items())))
    reordered_snapshot = make_phase5_snapshot(module, metadata=reordered_metadata)
    reordered_content = module.parse_phase5_snapshot_content(reordered_snapshot)
    assert reordered_content.requiredTestIds == tuple(sorted(PHASE5_REQUIRED_IDS))
    assert reordered_content.document.reviewLink == PHASE5_FRONTMATTER["reviewLink"], (
        "frontmatter key declaration order must not affect scalar decoding"
    )
    non_a0_prefix_snapshot = make_phase5_snapshot(
        module,
        required_ids=PHASE5_REQUIRED_IDS + ("TST-A0X-001",),
    )
    assert "TST-A0X-001" in module.parse_phase5_snapshot_content(
        non_a0_prefix_snapshot
    ).requiredTestIds, "only the exact TST-A0- prefix is reserved"
    non_h3_raw_lines = snapshot.bytes.replace(
        b"| ID | ",
        b"#### H4 is not H3\n   ### leading-space raw prose\n| ID | ",
        1,
    )
    assert module.parse_phase5_snapshot_content(
        dataclasses.replace(snapshot, bytes=non_h3_raw_lines)
    ).requiredTestIds == tuple(sorted(PHASE5_REQUIRED_IDS))

    required_wire = signed_document_bound_required_set(
        module, policy_ref, snapshot
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    standalone = module.parse_required_test_set(required_bytes, policy_bytes)
    document_bound = module.parse_document_bound_required_test_set(
        required_bytes, policy_bytes, snapshot
    )
    assert document_bound == standalone, (
        "document-bound positive must return the fully signed object/ref pair"
    )

    class ForgedSnapshot(module.BootstrapDocumentSnapshotV1):
        pass

    class ExplosiveScalar:
        def __eq__(self, other: object) -> bool:
            del other
            raise AssertionError("untyped snapshot scalar equality must not run")

    for label, invalid_snapshot in (
        ("untyped snapshot", {"id": "PHASE-5"}),
        (
            "snapshot subclass",
            ForgedSnapshot(snapshot.id, snapshot.path, snapshot.bytes),
        ),
        ("untyped snapshot ID", dataclasses.replace(snapshot, id=ExplosiveScalar())),
        ("untyped snapshot path", dataclasses.replace(snapshot, path=ExplosiveScalar())),
        ("wrong snapshot ID", dataclasses.replace(snapshot, id="PHASE-4")),
        (
            "wrong snapshot path",
            dataclasses.replace(snapshot, path="docs/phase-5.md"),
        ),
        ("empty snapshot", dataclasses.replace(snapshot, bytes=b"")),
        (
            "snapshot over 4 MiB",
            dataclasses.replace(snapshot, bytes=b"x" * (4 * 1024 * 1024 + 1)),
        ),
        ("UTF-8 BOM", dataclasses.replace(snapshot, bytes=b"\xef\xbb\xbf" + snapshot.bytes)),
        ("NUL byte", dataclasses.replace(snapshot, bytes=snapshot.bytes + b"\x00\n")),
        ("CR byte", dataclasses.replace(snapshot, bytes=snapshot.bytes.replace(b"\n", b"\r\n", 1))),
        ("invalid UTF-8", dataclasses.replace(snapshot, bytes=snapshot.bytes + b"\xff\n")),
        ("missing final LF", dataclasses.replace(snapshot, bytes=snapshot.bytes[:-1])),
    ):
        assert_rejected(
            module,
            lambda invalid_snapshot=invalid_snapshot: (
                module.parse_phase5_snapshot_content(invalid_snapshot)
            ),
        )

    snapshot_mutations = []
    for label, old, new in (
        ("missing opening delimiter", b"---\n", b""),
        ("noncanonical scalar delimiter", b"title: Synthetic", b"title:  Synthetic"),
        ("wrong accepted status", b"status: accepted", b"status: proposed"),
        ("wrong normative flag", b"normative: true", b"normative: false"),
        ("open finding", b"openFindings: none", b"openFindings: P1"),
        (
            "noncanonical approver delimiter",
            b"principal-quality, principal-security",
            b"principal-quality,principal-security",
        ),
        ("missing catalog heading", "## 完整 Test ID Catalog".encode(), b"## Missing"),
        ("wrong table delimiter", b"|---|---|", b"|:---|---:|"),
        (
            "extra table cell",
            b"| TST-DOC-001 | fixture for TST-DOC-001 |",
            b"| TST-DOC-001 | fixture for TST-DOC-001 | extra |",
        ),
        (
            "empty description",
            b"| TST-DOC-001 | fixture for TST-DOC-001 |",
            b"| TST-DOC-001 |  |",
        ),
        (
            "missing frozen A0 ID",
            b"| TST-A0-020 | fixture for TST-A0-020 |\n",
            b"",
        ),
        (
            "wildcard ID",
            b"| TST-DOC-001 | fixture for TST-DOC-001 |",
            b"| TST-* | wildcard |",
        ),
    ):
        assert old in snapshot.bytes, f"fixture mutation {label} must match once"
        snapshot_mutations.append((
            label,
            dataclasses.replace(snapshot, bytes=snapshot.bytes.replace(old, new, 1)),
        ))

    duplicate_frontmatter = snapshot.bytes.replace(
        b"owner: quality\n", b"owner: quality\nowner: security\n", 1
    )
    unknown_frontmatter = snapshot.bytes.replace(
        b"owner: quality\n", b"owner: quality\nfutureField: no\n", 1
    )
    duplicate_heading = snapshot.bytes.replace(
        "## 完整 Test ID Catalog\n".encode(),
        "```\n## 完整 Test ID Catalog\n```\n## 完整 Test ID Catalog\n".encode(),
        1,
    )
    bare_h3_before_denominator = snapshot.bytes.replace(
        b"| ID | ",
        b"###\n| ID | ",
        1,
    )
    tab_h3_before_denominator = snapshot.bytes.replace(
        b"| ID | ",
        b"###\tHidden subsection\n| ID | ",
        1,
    )
    space_h3_before_denominator = snapshot.bytes.replace(
        b"| ID | ",
        b"### Hidden subsection\n| ID | ",
        1,
    )
    duplicate_table_header = snapshot.bytes.replace(
        "| ID | 测试对象 |\n".encode(),
        "| ID | 测试对象 |\n| ID | 测试对象 |\n".encode(),
        1,
    )
    duplicate_table_delimiter = snapshot.bytes.replace(
        b"|---|---|\n", b"|---|---|\n|---|---|\n", 1
    )
    missing_denominator = snapshot.bytes.replace(
        "### Phase 1 required-set 分母".encode(),
        b"Phase 1 denominator missing",
        1,
    )
    duplicate_denominator = snapshot.bytes.replace(
        "### Phase 1 required-set 分母\n".encode(),
        "### Phase 1 required-set 分母\n### Phase 1 required-set 分母\n".encode(),
        1,
    )
    missing_frontmatter_field = snapshot.bytes.replace(
        b"owner: quality\n", b"", 1
    )
    missing_closing_delimiter = snapshot.bytes.replace(
        b"\n---\n", b"\n--\n", 1
    )
    start_marker = "## 完整 Test ID Catalog".encode()
    end_marker = "### Phase 1 required-set 分母".encode()
    reversed_markers = snapshot.bytes.replace(
        start_marker, b"PHASE5-CATALOG-START-PLACEHOLDER", 1
    ).replace(
        end_marker, start_marker, 1
    ).replace(
        b"PHASE5-CATALOG-START-PLACEHOLDER", end_marker, 1
    )
    missing_table_header = snapshot.bytes.replace(
        "| ID | 测试对象 |".encode(), b"ID / test object", 1
    )
    duplicate_id = snapshot.bytes.replace(
        b"| TST-DOC-001 | fixture for TST-DOC-001 |\n",
        b"| TST-DOC-001 | fixture for TST-DOC-001 |\n"
        b"| TST-DOC-001 | duplicate |\n",
        1,
    )
    extra_a0 = snapshot.bytes.replace(
        b"|---|---|\n",
        b"|---|---|\n| TST-A0-021 | forbidden A0 |\n",
        1,
    )
    range_id = snapshot.bytes.replace(
        b"| TST-DOC-001 | fixture for TST-DOC-001 |",
        b"| TST-DOC-001..003 | forbidden range |",
        1,
    )
    snapshot_mutations.extend((
        ("duplicate frontmatter key", dataclasses.replace(snapshot, bytes=duplicate_frontmatter)),
        ("unknown frontmatter key", dataclasses.replace(snapshot, bytes=unknown_frontmatter)),
        ("duplicate heading even inside fence", dataclasses.replace(snapshot, bytes=duplicate_heading)),
        ("bare raw H3 before denominator", dataclasses.replace(snapshot, bytes=bare_h3_before_denominator)),
        ("tab raw H3 before denominator", dataclasses.replace(snapshot, bytes=tab_h3_before_denominator)),
        ("space raw H3 before denominator", dataclasses.replace(snapshot, bytes=space_h3_before_denominator)),
        ("duplicate table header", dataclasses.replace(snapshot, bytes=duplicate_table_header)),
        ("duplicate table delimiter", dataclasses.replace(snapshot, bytes=duplicate_table_delimiter)),
        ("missing denominator heading", dataclasses.replace(snapshot, bytes=missing_denominator)),
        ("duplicate denominator heading", dataclasses.replace(snapshot, bytes=duplicate_denominator)),
        ("reversed catalog markers", dataclasses.replace(snapshot, bytes=reversed_markers)),
        ("missing table header", dataclasses.replace(snapshot, bytes=missing_table_header)),
        ("missing frontmatter field", dataclasses.replace(snapshot, bytes=missing_frontmatter_field)),
        ("missing closing delimiter", dataclasses.replace(snapshot, bytes=missing_closing_delimiter)),
        ("duplicate catalog ID", dataclasses.replace(snapshot, bytes=duplicate_id)),
        ("extra A0 form", dataclasses.replace(snapshot, bytes=extra_a0)),
        ("range catalog ID", dataclasses.replace(snapshot, bytes=range_id)),
    ))
    for label, invalid_snapshot in snapshot_mutations:
        assert_rejected(
            module,
            lambda invalid_snapshot=invalid_snapshot: (
                module.parse_phase5_snapshot_content(invalid_snapshot)
            ),
        )

    mismatch_wires = []
    wrong_digest = signed_document_bound_required_set(
        module,
        policy_ref,
        snapshot,
        document_overrides={"contentDigest": digest_text(bytes(32))},
    )
    mismatch_wires.append(("document digest mismatch", wrong_digest))
    wrong_review = signed_document_bound_required_set(
        module,
        policy_ref,
        snapshot,
        document_overrides={"reviewLink": "https://review.example/other"},
    )
    mismatch_wires.append(("frontmatter metadata mismatch", wrong_review))
    missing_id = signed_document_bound_required_set(
        module, policy_ref, snapshot, required_ids=PHASE5_REQUIRED_IDS[:-1]
    )
    mismatch_wires.append(("signed denominator missing ID", missing_id))
    extra_id = signed_document_bound_required_set(
        module,
        policy_ref,
        snapshot,
        required_ids=PHASE5_REQUIRED_IDS + ("TST-ISO-002",),
    )
    mismatch_wires.append(("signed denominator extra ID", extra_id))
    reordered = copy.deepcopy(required_wire)
    reordered["requiredTestIds"].reverse()
    reordered = resign_required_test_set_wire(module, reordered)
    mismatch_wires.append(("signed denominator reordered", reordered))

    for label, mismatch_wire in mismatch_wires[:-1]:
        parsed_mismatch, _ = module.parse_required_test_set(
            module.canonical_pf_jcs(mismatch_wire), policy_bytes
        )
        assert isinstance(parsed_mismatch, module.RequiredTestSetV1), (
            f"{label} must be a valid signed intermediate before the document join"
        )

    original_verify_ed25519 = module.verify_ed25519
    signature_curve_calls = 0

    def counted_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        del public_key, message, signature
        nonlocal signature_curve_calls
        signature_curve_calls += 1
        return True

    module.verify_ed25519 = counted_verify_ed25519
    try:
        malformed_snapshot = dataclasses.replace(
            snapshot, bytes=snapshot.bytes.replace(b"|---|---|", b"|--|---|", 1)
        )
        signature_curve_calls = 0
        assert_rejected(
            module,
            lambda: module.parse_document_bound_required_test_set(
                required_bytes, policy_bytes, malformed_snapshot
            ),
        )
        assert signature_curve_calls == 0, (
            "malformed snapshot must reject before RequiredTestSet signature work"
        )
        for label, mismatch_wire in mismatch_wires:
            signature_curve_calls = 0
            assert_rejected(
                module,
                lambda mismatch_wire=mismatch_wire: (
                    module.parse_document_bound_required_test_set(
                        module.canonical_pf_jcs(mismatch_wire),
                        policy_bytes,
                        snapshot,
                    )
                ),
            )
            assert signature_curve_calls == 0, (
                f"{label} must reject during structural join before signature work"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519


def _insert_before_phase5_catalog(encoded: bytes, padding: bytes) -> bytes:
    marker = "## 完整 Test ID Catalog\n".encode("utf-8")
    assert encoded.count(marker) == 1
    return encoded.replace(marker, padding + marker, 1)


def _insert_before_phase4_d0(encoded: bytes, padding: bytes) -> bytes:
    marker = "## Milestone D0：文档与独立工程\n".encode("utf-8")
    assert encoded.count(marker) == 1
    return encoded.replace(marker, padding + marker, 1)


def _bounded_line_padding(size: int) -> bytes:
    parts = []
    remaining = size
    while remaining:
        if remaining == 1:
            parts.append(b"\n")
            break
        payload_size = min(65_536, remaining - 1)
        parts.append(b"x" * payload_size + b"\n")
        remaining -= payload_size + 1
    result = b"".join(parts)
    assert len(result) == size
    assert all(len(line) <= 65_536 for line in result[:-1].split(b"\n"))
    return result


def test_phase4_snapshot_resource_bounds(module: ModuleType) -> None:
    base = make_phase4_snapshot(module)
    maximum_bytes = 4 * 1024 * 1024
    maximum_encoded = _insert_before_phase4_d0(
        base.bytes,
        _bounded_line_padding(maximum_bytes - len(base.bytes)),
    )
    assert len(maximum_encoded) == maximum_bytes
    assert len(
        module.parse_phase4_snapshot_content(
            dataclasses.replace(base, bytes=maximum_encoded)
        ).bootstrapTaskRows
    ) == 6
    assert_rejected(
        module,
        lambda: module.parse_phase4_snapshot_content(
            dataclasses.replace(base, bytes=maximum_encoded + b"\n")
        ),
    )

    maximum_line = _insert_before_phase4_d0(
        base.bytes,
        b"x" * 65_536 + b"\n",
    )
    module.parse_phase4_snapshot_content(
        dataclasses.replace(base, bytes=maximum_line)
    )
    assert_rejected(
        module,
        lambda: module.parse_phase4_snapshot_content(dataclasses.replace(
            base,
            bytes=_insert_before_phase4_d0(
                base.bytes,
                b"x" * 65_537 + b"\n",
            ),
        )),
    )

    base_line_count = base.bytes.count(b"\n")
    maximum_lines = _insert_before_phase4_d0(
        base.bytes,
        b"\n" * (100_000 - base_line_count),
    )
    assert maximum_lines.count(b"\n") == 100_000
    module.parse_phase4_snapshot_content(
        dataclasses.replace(base, bytes=maximum_lines)
    )
    over_lines = _insert_before_phase4_d0(
        base.bytes,
        b"\n" * (100_001 - base_line_count),
    )
    assert_rejected(
        module,
        lambda: module.parse_phase4_snapshot_content(
            dataclasses.replace(base, bytes=over_lines)
        ),
    )

    description = b"fixture for TASK-D0-02"
    assert base.bytes.count(description) == 1
    maximum_description = base.bytes.replace(
        description,
        b"d" * 4096,
        1,
    )
    module.parse_phase4_snapshot_content(
        dataclasses.replace(base, bytes=maximum_description)
    )
    assert_rejected(
        module,
        lambda: module.parse_phase4_snapshot_content(dataclasses.replace(
            base,
            bytes=base.bytes.replace(description, b"d" * 4097, 1),
        )),
    )


def test_phase5_snapshot_resource_bounds(module: ModuleType) -> None:
    base = make_phase5_snapshot(module)
    maximum_bytes = 4 * 1024 * 1024
    maximum_encoded = _insert_before_phase5_catalog(
        base.bytes,
        _bounded_line_padding(maximum_bytes - len(base.bytes)),
    )
    assert len(maximum_encoded) == maximum_bytes
    assert module.parse_phase5_snapshot_content(
        dataclasses.replace(base, bytes=maximum_encoded)
    ).requiredTestIds == tuple(sorted(PHASE5_REQUIRED_IDS))
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(
            dataclasses.replace(base, bytes=maximum_encoded + b"\n")
        ),
    )

    maximum_line = _insert_before_phase5_catalog(
        base.bytes, b"x" * 65_536 + b"\n"
    )
    module.parse_phase5_snapshot_content(
        dataclasses.replace(base, bytes=maximum_line)
    )
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(dataclasses.replace(
            base,
            bytes=_insert_before_phase5_catalog(
                base.bytes, b"x" * 65_537 + b"\n"
            ),
        )),
    )

    base_line_count = base.bytes.count(b"\n")
    maximum_lines = _insert_before_phase5_catalog(
        base.bytes, b"\n" * (100_000 - base_line_count)
    )
    assert maximum_lines.count(b"\n") == 100_000
    module.parse_phase5_snapshot_content(
        dataclasses.replace(base, bytes=maximum_lines)
    )
    over_lines = _insert_before_phase5_catalog(
        base.bytes, b"\n" * (100_001 - base_line_count)
    )
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(
            dataclasses.replace(base, bytes=over_lines)
        ),
    )

    maximum_required_ids = tuple(
        f"TST-BOUNDARY-{index:04d}" for index in range(4096)
    )
    maximum_required = make_phase5_snapshot(
        module, required_ids=maximum_required_ids
    )
    maximum_content = module.parse_phase5_snapshot_content(maximum_required)
    assert maximum_content.requiredTestIds == maximum_required_ids
    over_required = make_phase5_snapshot(
        module,
        required_ids=maximum_required_ids + ("TST-BOUNDARY-4096",),
    )
    assert_rejected(
        module, lambda: module.parse_phase5_snapshot_content(over_required)
    )

    description_line = b"| TST-DOC-001 | fixture for TST-DOC-001 |"
    maximum_description = base.bytes.replace(
        description_line,
        b"| TST-DOC-001 | " + b"d" * 4096 + b" |",
        1,
    )
    module.parse_phase5_snapshot_content(
        dataclasses.replace(base, bytes=maximum_description)
    )
    over_description = base.bytes.replace(
        description_line,
        b"| TST-DOC-001 | " + b"d" * 4097 + b" |",
        1,
    )
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(
            dataclasses.replace(base, bytes=over_description)
        ),
    )

    review_link_prefix = "hTtPs://review.example/phase-5/"
    maximum_review_link = review_link_prefix + "r" * (
        4096 - len(review_link_prefix.encode("ascii"))
    )
    maximum_approvers = ", ".join(
        f"principal-boundary-{index:03d}" for index in range(256)
    )
    maximum_metadata = dict(PHASE5_FRONTMATTER)
    maximum_metadata["reviewLink"] = maximum_review_link
    maximum_metadata["approvers"] = maximum_approvers
    maximum_metadata_content = module.parse_phase5_snapshot_content(
        make_phase5_snapshot(module, metadata=maximum_metadata)
    )
    assert maximum_metadata_content.document.reviewLink == maximum_review_link
    assert len(maximum_metadata_content.document.approvers) == 256

    over_review_link = dict(maximum_metadata)
    over_review_link["reviewLink"] = maximum_review_link + "r"
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(
            make_phase5_snapshot(module, metadata=over_review_link)
        ),
    )
    over_approvers = dict(PHASE5_FRONTMATTER)
    over_approvers["approvers"] = ", ".join(
        f"principal-boundary-{index:03d}" for index in range(257)
    )
    assert_rejected(
        module,
        lambda: module.parse_phase5_snapshot_content(
            make_phase5_snapshot(module, metadata=over_approvers)
        ),
    )


def test_required_test_set(module: ModuleType) -> None:
    policy_wire = valid_bootstrap_authority_policy()
    policy_bytes = module.canonical_pf_jcs(policy_wire)
    _policy, policy_ref = module.parse_bootstrap_authority_policy(
        policy_bytes
    )
    wire, statement_digest, signature_message = signed_required_test_set(
        module, policy_ref
    )
    encoded = module.canonical_pf_jcs(wire)
    parsed, parsed_ref = module.parse_required_test_set(
        encoded, policy_bytes
    )
    expected_content_digest = hashlib.sha256(
        b"pf.required-test-set.v1\x00" + encoded
    ).digest()
    assert statement_digest.hex() == (
        "6009663bd14f189802f396ebbfb9a5a7d"
        "abcc643e35c3b0d23364af67d5814ad"
    ), "required-test-set statement domain/wire golden changed"
    assert expected_content_digest.hex() == (
        "613220d9f9c49763364fc1dd1be4c8ce"
        "abb8ca639199c86e69aab617e4eb5d9a"
    ), "required-test-set content domain/wire golden changed"
    expected_ref = module.ContentRef(
        "proof-forge.required-test-set.v1",
        "phase-5-required-tests",
        "1.0.0",
        module.Digest("sha256", expected_content_digest),
    )
    expected_phase5_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00"
        b"---\nid: PHASE-5\nstatus: accepted\n---\n"
        b"# Phase 5 acceptance fixture\n"
    ).digest()
    expected_phase5_document = module.NormativeDocumentRefV1(
        "PHASE-5",
        module.Digest("sha256", expected_phase5_digest),
        "accepted",
        "a" * 40,
        "https://review.example/phase-5",
        "2026-07-16",
        ("principal-quality", "principal-security"),
    )
    expected_signatures = tuple(
        module.ApprovalSignatureV1(
            key_id,
            "ed25519",
            ed25519_sign_from_rfc_seed(
                RFC_8032_SEEDS_BY_KEY_ID[key_id], signature_message
            )[1],
        )
        for key_id in ("key-quality", "key-security")
    )
    expected_required_set = module.RequiredTestSetV1(
        "proof-forge.required-test-set.v1",
        "phase-5-required-tests",
        "1.0.0",
        expected_phase5_document,
        policy_ref,
        ("TST-BOOTSTRAP-001", "TST-DOC-001", "TST-EVIDENCE-001"),
        expected_signatures,
    )
    assert parsed == expected_required_set, (
        "positive parse must preserve every scalar, nested record, and raw byte field"
    )
    assert parsed_ref == expected_ref
    assert statement_digest == hashlib.sha256(
        b"pf.required-test-set-statement.v1\x00"
        + module.canonical_pf_jcs({
            key: value for key, value in wire.items() if key != "signatures"
        })
    ).digest()
    assert signature_message == (
        b"pf.required-test-set-signature.v1\x00" + statement_digest
    )

    max_test_id = "TST-" + "Z" * 123
    assert len(max_test_id.encode("ascii")) == 127
    max_review_link_prefix = "hTtPs://review.example/phase-5/"
    max_review_link = max_review_link_prefix + "a" * (
        4096 - len(max_review_link_prefix.encode("ascii"))
    )
    assert len(max_review_link.encode("utf-8")) == 4096
    max_required_ids = [
        f"TST-BOUNDARY-{index:04d}" for index in range(4095)
    ]
    max_required_ids.append(max_test_id)
    max_required_ids.sort()
    assert len(max_required_ids) == 4096
    max_approvers = [
        f"principal-boundary-{index:03d}" for index in range(256)
    ]
    all_policy_key_ids = tuple(
        principal["keyId"] for principal in policy_wire["principals"]
    )
    assert all_policy_key_ids == tuple(sorted(all_policy_key_ids))

    equal_bound_statement = required_test_set_statement(policy_ref)
    equal_bound_statement["phase5Document"]["reviewLink"] = max_review_link
    equal_bound_statement["phase5Document"]["approvers"] = max_approvers
    equal_bound_statement["requiredTestIds"] = max_required_ids
    equal_bound_wire, _, _ = sign_required_test_set_statement(
        module,
        equal_bound_statement,
        signer_key_ids=all_policy_key_ids,
    )
    equal_bound_parsed, _ = module.parse_required_test_set(
        module.canonical_pf_jcs(equal_bound_wire), policy_bytes
    )
    assert max_test_id in equal_bound_parsed.requiredTestIds
    assert len(equal_bound_parsed.requiredTestIds) == 4096
    assert len(equal_bound_parsed.phase5Document.approvers) == 256
    assert equal_bound_parsed.phase5Document.reviewLink == max_review_link
    assert len(equal_bound_parsed.signatures) == len(policy_wire["principals"])

    over_test_id_statement = required_test_set_statement(policy_ref)
    over_test_id = "TST-" + "Z" * 124
    assert len(over_test_id.encode("ascii")) == 128
    over_test_id_statement["requiredTestIds"][2] = over_test_id
    over_test_id_statement["requiredTestIds"].sort()
    over_test_id_wire, _, _ = sign_required_test_set_statement(
        module, over_test_id_statement
    )

    over_required_ids_statement = required_test_set_statement(policy_ref)
    over_required_ids_statement["requiredTestIds"] = [
        f"TST-BOUNDARY-{index:04d}" for index in range(4096)
    ] + [max_test_id]
    over_required_ids_statement["requiredTestIds"].sort()
    assert len(over_required_ids_statement["requiredTestIds"]) == 4097
    over_required_ids_wire, _, _ = sign_required_test_set_statement(
        module, over_required_ids_statement
    )

    over_approvers_statement = required_test_set_statement(policy_ref)
    over_approvers_statement["phase5Document"]["approvers"] = [
        f"principal-boundary-{index:03d}" for index in range(257)
    ]
    over_approvers_wire, _, _ = sign_required_test_set_statement(
        module, over_approvers_statement
    )

    over_review_link_statement = required_test_set_statement(policy_ref)
    over_review_link_statement["phase5Document"]["reviewLink"] = (
        max_review_link + "a"
    )
    assert len(
        over_review_link_statement["phase5Document"]["reviewLink"].encode(
            "utf-8"
        )
    ) == 4097
    over_review_link_wire, _, _ = sign_required_test_set_statement(
        module, over_review_link_statement
    )

    over_signatures_wire, _, _ = sign_required_test_set_statement(
        module,
        required_test_set_statement(policy_ref),
        signer_key_ids=all_policy_key_ids,
    )
    over_signatures_wire["signatures"].append({
        "keyId": "key-unknown",
        "algorithm": "ed25519",
        "signature": "00" * 64,
    })
    assert len(over_signatures_wire["signatures"]) == (
        len(policy_wire["principals"]) + 1
    )

    for label, over_bound_wire in (
        ("128-byte TestId", over_test_id_wire),
        ("4097 required IDs", over_required_ids_wire),
        ("257 approvers", over_approvers_wire),
        ("4097-byte reviewLink", over_review_link_wire),
        ("signature count over resolved policy", over_signatures_wire),
    ):
        assert_rejected(
            module,
            lambda over_bound_wire=over_bound_wire: module.parse_required_test_set(
                module.canonical_pf_jcs(over_bound_wire), policy_bytes
            ),
        )

    malformed_preflight_wire = copy.deepcopy(wire)
    malformed_preflight_wire["requiredTestIds"][0] = "TST-*"
    malformed_preflight_wire["requiredTestIds"].sort()
    malformed_preflight_wire = resign_required_test_set_wire(
        module, malformed_preflight_wire
    )
    reordered_ids_preflight_wire = copy.deepcopy(wire)
    reordered_ids_preflight_wire["requiredTestIds"].reverse()
    reordered_ids_preflight_wire = resign_required_test_set_wire(
        module, reordered_ids_preflight_wire
    )
    duplicate_id_preflight_wire = copy.deepcopy(wire)
    duplicate_id_preflight_wire["requiredTestIds"][1] = (
        duplicate_id_preflight_wire["requiredTestIds"][0]
    )
    duplicate_id_preflight_wire = resign_required_test_set_wire(
        module, duplicate_id_preflight_wire
    )
    unknown_signature_field_preflight_wire = copy.deepcopy(wire)
    unknown_signature_field_preflight_wire["signatures"][0]["futureField"] = True
    reordered_signatures_preflight_wire = copy.deepcopy(wire)
    reordered_signatures_preflight_wire["signatures"].reverse()
    duplicate_signature_preflight_wire = copy.deepcopy(wire)
    duplicate_signature_preflight_wire["signatures"][1]["keyId"] = (
        duplicate_signature_preflight_wire["signatures"][0]["keyId"]
    )
    wrong_algorithm_preflight_wire = copy.deepcopy(wire)
    wrong_algorithm_preflight_wire["signatures"][0]["algorithm"] = "ed25519ph"
    malformed_signature_preflight_wire = copy.deepcopy(wire)
    malformed_signature_preflight_wire["signatures"][0]["signature"] = "00" * 63
    uppercase_signature_preflight_wire = copy.deepcopy(wire)
    uppercase_signature_preflight_wire["signatures"][0]["signature"] = (
        uppercase_signature_preflight_wire["signatures"][0]["signature"].upper()
    )
    unknown_key_preflight_wire = copy.deepcopy(wire)
    unknown_key_preflight_wire["signatures"][1]["keyId"] = "key-unknown"
    original_verify_ed25519 = module.verify_ed25519
    required_set_curve_calls = 0

    def counted_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        del public_key, message, signature
        nonlocal required_set_curve_calls
        required_set_curve_calls += 1
        return True

    module.verify_ed25519 = counted_verify_ed25519
    try:
        for label, preflight_wire in (
            ("128-byte TestId", over_test_id_wire),
            ("malformed TestId grammar", malformed_preflight_wire),
            ("4097 required IDs", over_required_ids_wire),
            ("reordered required IDs", reordered_ids_preflight_wire),
            ("duplicate required ID", duplicate_id_preflight_wire),
            ("unknown signature field", unknown_signature_field_preflight_wire),
            ("reordered signatures", reordered_signatures_preflight_wire),
            ("duplicate signature key", duplicate_signature_preflight_wire),
            ("wrong signature algorithm", wrong_algorithm_preflight_wire),
            ("malformed signature scalar", malformed_signature_preflight_wire),
            ("uppercase signature hex", uppercase_signature_preflight_wire),
            ("unknown signature key", unknown_key_preflight_wire),
            ("signature count over resolved policy", over_signatures_wire),
        ):
            required_set_curve_calls = 0
            assert_rejected(
                module,
                lambda preflight_wire=preflight_wire: module.parse_required_test_set(
                    module.canonical_pf_jcs(preflight_wire), policy_bytes
                ),
            )
            assert required_set_curve_calls == 0, (
                f"{label} must reject before RequiredTestSet curve verification"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519

    mutations = []
    signature_mutations = []

    unknown_root = copy.deepcopy(wire)
    unknown_root["futureField"] = True
    mutations.append(("unknown required-set field", unknown_root))

    wrong_required_set_schema = copy.deepcopy(wire)
    wrong_required_set_schema["schema"] = "proof-forge.required-test-set.v2"
    mutations.append(("wrong required-set schema", wrong_required_set_schema))

    wrong_required_set_id = copy.deepcopy(wire)
    wrong_required_set_id["id"] = "Phase_5_Required_Set"
    mutations.append(("invalid required-set profile ID", wrong_required_set_id))

    overflow_required_set_version = copy.deepcopy(wire)
    overflow_required_set_version["version"] = "18446744073709551616.0.0"
    mutations.append(("required-set version exceeds UInt64", overflow_required_set_version))

    missing_root = copy.deepcopy(wire)
    del missing_root["requiredTestIds"]
    mutations.append(("missing requiredTestIds field", missing_root))

    unknown_document = copy.deepcopy(wire)
    unknown_document["phase5Document"]["futureField"] = True
    mutations.append(("unknown normative document field", unknown_document))

    unknown_signature = copy.deepcopy(wire)
    unknown_signature["signatures"][0]["futureField"] = True
    signature_mutations.append(("unknown signature field", unknown_signature))

    empty_ids = copy.deepcopy(wire)
    empty_ids["requiredTestIds"] = []
    mutations.append(("empty required IDs", empty_ids))

    reordered_ids = copy.deepcopy(wire)
    reordered_ids["requiredTestIds"][0], reordered_ids["requiredTestIds"][1] = (
        reordered_ids["requiredTestIds"][1],
        reordered_ids["requiredTestIds"][0],
    )
    mutations.append(("reordered required IDs", reordered_ids))

    duplicate_ids = copy.deepcopy(wire)
    duplicate_ids["requiredTestIds"].insert(
        1, duplicate_ids["requiredTestIds"][0]
    )
    mutations.append(("duplicate required ID", duplicate_ids))

    malformed_id = copy.deepcopy(wire)
    malformed_id["requiredTestIds"][0] = "TST-*"
    mutations.append(("malformed required ID", malformed_id))

    development_a0_id = copy.deepcopy(wire)
    development_a0_id["requiredTestIds"][0] = "TST-A0-001"
    mutations.append(("development A0 ID in formal required set", development_a0_id))

    nonnumeric_a0_id = copy.deepcopy(wire)
    nonnumeric_a0_id["requiredTestIds"][0] = "TST-A0-XYZ"
    mutations.append(("nonnumeric A0-prefixed formal ID", nonnumeric_a0_id))

    missing_signatures = copy.deepcopy(wire)
    del missing_signatures["signatures"]
    signature_mutations.append(("missing signatures field", missing_signatures))

    empty_signatures = copy.deepcopy(wire)
    empty_signatures["signatures"] = []
    signature_mutations.append(("empty signatures", empty_signatures))

    reordered_signatures = copy.deepcopy(wire)
    reordered_signatures["signatures"].reverse()
    signature_mutations.append(("reordered signatures", reordered_signatures))

    duplicate_signatures = copy.deepcopy(wire)
    duplicate_signatures["signatures"].insert(
        1, copy.deepcopy(duplicate_signatures["signatures"][0])
    )
    signature_mutations.append(("duplicate signature keyId", duplicate_signatures))

    wrong_policy_ref = copy.deepcopy(wire)
    wrong_policy_ref["authorityPolicy"]["digest"] = digest_text(bytes(32))
    mutations.append(("wrong authority policy ref", wrong_policy_ref))

    wrong_policy_schema = copy.deepcopy(wire)
    wrong_policy_schema["authorityPolicy"]["schema"] = (
        "proof-forge.bootstrap-authority-policy.v2"
    )
    mutations.append(("wrong authority policy schema", wrong_policy_schema))

    wrong_phase = copy.deepcopy(wire)
    wrong_phase["phase5Document"]["id"] = "PHASE-4"
    mutations.append(("wrong Phase-5 document ID", wrong_phase))

    wrong_status = copy.deepcopy(wire)
    wrong_status["phase5Document"]["status"] = "proposed"
    mutations.append(("unaccepted Phase-5 document", wrong_status))

    bad_document_digest = copy.deepcopy(wire)
    bad_document_digest["phase5Document"]["contentDigest"] = "sha256:" + "A" * 64
    mutations.append(("invalid Phase-5 content digest scalar", bad_document_digest))

    bad_review_commit = copy.deepcopy(wire)
    bad_review_commit["phase5Document"]["reviewCommit"] = "a" * 39
    mutations.append(("invalid Phase-5 review commit", bad_review_commit))

    uppercase_review_commit = copy.deepcopy(wire)
    uppercase_review_commit["phase5Document"]["reviewCommit"] = "A" * 40
    mutations.append(("uppercase Phase-5 review commit", uppercase_review_commit))

    bad_review_link = copy.deepcopy(wire)
    bad_review_link["phase5Document"]["reviewLink"] = "http://review.example/phase-5"
    mutations.append(("invalid Phase-5 review link", bad_review_link))

    control_review_link = copy.deepcopy(wire)
    control_review_link["phase5Document"]["reviewLink"] = (
        "https://review.example/phase-5\n"
    )
    mutations.append(("control character in Phase-5 review link", control_review_link))

    bad_approved_at = copy.deepcopy(wire)
    bad_approved_at["phase5Document"]["approvedAt"] = "2026-02-30"
    mutations.append(("invalid Phase-5 approval date", bad_approved_at))

    empty_approvers = copy.deepcopy(wire)
    empty_approvers["phase5Document"]["approvers"] = []
    mutations.append(("empty Phase-5 approvers", empty_approvers))

    reordered_approvers = copy.deepcopy(wire)
    reordered_approvers["phase5Document"]["approvers"].reverse()
    mutations.append(("reordered Phase-5 approvers", reordered_approvers))

    duplicate_approvers = copy.deepcopy(wire)
    duplicate_approvers["phase5Document"]["approvers"][1] = (
        duplicate_approvers["phase5Document"]["approvers"][0]
    )
    mutations.append(("duplicate Phase-5 approver", duplicate_approvers))

    invalid_approver = copy.deepcopy(wire)
    invalid_approver["phase5Document"]["approvers"][0] = "-principal"
    mutations.append(("invalid Phase-5 approver safe-id", invalid_approver))

    alternate_document = copy.deepcopy(wire)
    alternate_document["phase5Document"]["contentDigest"] = digest_text(
        bytes.fromhex("7f" * 32)
    )
    alternate_document = resign_required_test_set_wire(
        module, alternate_document
    )
    alternate_document_parsed, _ = module.parse_required_test_set(
        module.canonical_pf_jcs(alternate_document), policy_bytes
    )
    assert alternate_document_parsed.phase5Document.contentDigest.bytes == (
        bytes.fromhex("7f" * 32)
    ), (
        "RequiredTestSet parser is an intermediate object consumer and must not "
        "join the normative document snapshot"
    )

    extended_ids = copy.deepcopy(wire)
    extended_ids["requiredTestIds"].append("TST-ISO-002")
    extended_ids["requiredTestIds"].sort()
    extended_ids = resign_required_test_set_wire(module, extended_ids)
    extended_ids_parsed, _ = module.parse_required_test_set(
        module.canonical_pf_jcs(extended_ids), policy_bytes
    )
    assert extended_ids_parsed.requiredTestIds == tuple(
        extended_ids["requiredTestIds"]
    ), (
        "RequiredTestSet parser must preserve signed IDs without performing the "
        "later ledger denominator join"
    )

    wrong_algorithm = copy.deepcopy(wire)
    wrong_algorithm["signatures"][0]["algorithm"] = "ed25519ph"
    signature_mutations.append(("wrong signature algorithm", wrong_algorithm))

    wrong_key = copy.deepcopy(wire)
    wrong_key["signatures"][0]["signature"] = wire["signatures"][1]["signature"]
    signature_mutations.append(("signature under wrong key", wrong_key))

    bad_signature = copy.deepcopy(wire)
    first_signature = bytes.fromhex(bad_signature["signatures"][0]["signature"])
    bad_signature["signatures"][0]["signature"] = (
        bytes([first_signature[0] ^ 1]) + first_signature[1:]
    ).hex()
    signature_mutations.append(("tampered signature", bad_signature))

    invalid_signature_scalar = copy.deepcopy(wire)
    invalid_signature_scalar["signatures"][0]["signature"] = "00" * 63
    signature_mutations.append(("invalid signature scalar", invalid_signature_scalar))

    unknown_key = copy.deepcopy(wire)
    unknown_key["signatures"][0]["keyId"] = "key-unknown"
    signature_mutations.append(("unknown signature keyId", unknown_key))

    for label, mutation in mutations:
        resigned_mutation = resign_required_test_set_wire(module, mutation)
        assert_rejected(
            module,
            lambda resigned_mutation=resigned_mutation: module.parse_required_test_set(
                module.canonical_pf_jcs(resigned_mutation), policy_bytes
            ),
        )

    for label, mutation in signature_mutations:
        assert_rejected(
            module,
            lambda mutation=mutation: module.parse_required_test_set(
                module.canonical_pf_jcs(mutation), policy_bytes
            ),
        )

    alternate_policy_wire = copy.deepcopy(policy_wire)
    alternate_policy_wire["id"] = "alternate-bootstrap-authority-root"
    alternate_policy_bytes = module.canonical_pf_jcs(alternate_policy_wire)
    module.parse_bootstrap_authority_policy(alternate_policy_bytes)
    assert_rejected(
        module,
        lambda: module.parse_required_test_set(encoded, alternate_policy_bytes),
    )

    same_principal_policy_wire = copy.deepcopy(policy_wire)
    same_principal_policy_wire["principals"][3]["principalId"] = (
        same_principal_policy_wire["principals"][1]["principalId"]
    )
    same_principal_policy_bytes = module.canonical_pf_jcs(
        same_principal_policy_wire
    )
    _, same_principal_policy_ref = module.parse_bootstrap_authority_policy(
        same_principal_policy_bytes
    )
    same_principal_wire, _, _ = signed_required_test_set(
        module, same_principal_policy_ref
    )

    role_insufficient_wire, _, _ = signed_required_test_set(
        module,
        policy_ref,
        signer_key_ids=("key-architecture", "key-quality"),
    )
    original_verify_ed25519 = module.verify_ed25519
    rule_failure_curve_calls = 0

    def counted_rule_failure_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        del public_key, message, signature
        nonlocal rule_failure_curve_calls
        rule_failure_curve_calls += 1
        return True

    module.verify_ed25519 = counted_rule_failure_verify_ed25519
    try:
        for label, rejected_wire, rejected_policy_bytes in (
            (
                "same-principal signatures below distinct quorum",
                same_principal_wire,
                same_principal_policy_bytes,
            ),
            (
                "architecture+quality signatures missing security role",
                role_insufficient_wire,
                policy_bytes,
            ),
        ):
            rule_failure_curve_calls = 0
            assert_rejected(
                module,
                lambda rejected_wire=rejected_wire,
                rejected_policy_bytes=rejected_policy_bytes: (
                    module.parse_required_test_set(
                        module.canonical_pf_jcs(rejected_wire),
                        rejected_policy_bytes,
                    )
                ),
            )
            assert rule_failure_curve_calls == 0, (
                f"{label} must reject before RequiredTestSet curve verification"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519

    unsigned_rotation_role_wire, _, _ = signed_required_test_set(
        module,
        same_principal_policy_ref,
        signer_key_ids=("key-architecture", "key-quality"),
    )
    assert_rejected(
        module,
        lambda: module.parse_required_test_set(
            module.canonical_pf_jcs(unsigned_rotation_role_wire),
            same_principal_policy_bytes,
        ),
    )

    threshold_policy_wire = copy.deepcopy(policy_wire)
    threshold_policy_wire["requiredTestSetRule"]["minimumDistinctSigners"] = 3
    threshold_policy_bytes = module.canonical_pf_jcs(threshold_policy_wire)
    _, threshold_policy_ref = module.parse_bootstrap_authority_policy(
        threshold_policy_bytes
    )
    threshold_insufficient_wire, _, _ = signed_required_test_set(
        module, threshold_policy_ref
    )
    assert_rejected(
        module,
        lambda: module.parse_required_test_set(
            module.canonical_pf_jcs(threshold_insufficient_wire),
            threshold_policy_bytes,
        ),
    )


def test_task_approval(module: ModuleType) -> None:
    policy_bytes = module.canonical_pf_jcs(valid_bootstrap_authority_policy())
    _, policy_ref = module.parse_bootstrap_authority_policy(policy_bytes)
    phase5_snapshot = make_phase5_snapshot(module)
    required_wire = signed_document_bound_required_set(
        module, policy_ref, phase5_snapshot
    )
    required_bytes = module.canonical_pf_jcs(required_wire)
    approval_statement = task_approval_statement(
        module, policy_ref, required_bytes
    )
    approval_wire, statement_digest, signature_message = (
        sign_task_approval_statement(module, approval_statement)
    )
    approval_bytes = module.canonical_pf_jcs(approval_wire)
    parsed, parsed_ref = module.parse_task_approval(
        approval_bytes,
        required_bytes,
        policy_bytes,
        phase5_snapshot,
    )

    def typed_document(wire: dict) -> object:
        return module.NormativeDocumentRefV1(
            wire["id"],
            module.parse_digest(wire["contentDigest"]),
            wire["status"],
            wire["reviewCommit"],
            wire["reviewLink"],
            wire["approvedAt"],
            tuple(wire["approvers"]),
        )

    expected_signatures = tuple(
        module.ApprovalSignatureV1(
            signature["keyId"],
            "ed25519",
            bytes.fromhex(signature["signature"]),
        )
        for signature in approval_wire["signatures"]
    )
    expected_reviews = tuple(
        module.IndependentReviewRefV1(
            review["keyId"],
            review["role"],
            review["reviewCommit"],
            review["reviewLink"],
            module.parse_digest(review["reportDigest"]),
            review["decision"],
        )
        for review in approval_wire["independentReviews"]
    )
    expected_approval = module.TaskApprovalV1(
        approval_wire["schema"],
        approval_wire["taskId"],
        module.parse_candidate_identity(approval_wire["candidate"]),
        typed_document(approval_wire["taskBreakdown"]),
        module.parse_content_ref(approval_wire["requiredTestSet"]),
        tuple(approval_wire["testIds"]),
        tuple(
            module.EvidenceRef(
                evidence["id"], module.parse_digest(evidence["digest"])
            )
            for evidence in approval_wire["evidence"]
        ),
        tuple(
            module.BootstrapTaskVerifierReceiptRefV1(
                receipt["taskId"],
                receipt["id"],
                module.parse_digest(receipt["digest"]),
            )
            for receipt in approval_wire["dependencyCompletions"]
        ),
        tuple(
            typed_document(document)
            for document in approval_wire["prerequisiteDocuments"]
        ),
        policy_ref,
        module.parse_content_ref(approval_wire["stage0Handoff"]),
        expected_reviews,
        expected_signatures,
    )
    approval_digest = hashlib.sha256(
        b"pf.bootstrap-task-approval.v1\x00" + approval_bytes
    ).digest()
    expected_ref = module.TaskApprovalRefV1(
        "TASK-D0-01", module.Digest("sha256", approval_digest)
    )
    assert parsed == expected_approval, (
        "TaskApproval positive must preserve every frozen typed field"
    )
    assert parsed_ref == expected_ref, (
        "TaskApprovalRef must use the full signed-object domain digest"
    )
    assert statement_digest == hashlib.sha256(
        b"pf.bootstrap-task-approval-statement.v1\x00"
        + module.canonical_pf_jcs(approval_statement)
    ).digest()
    assert signature_message == (
        b"pf.bootstrap-task-approval-signature.v1\x00" + statement_digest
    )

    lower_bound_statement = copy.deepcopy(approval_statement)
    lower_bound_statement["evidence"] = lower_bound_statement["evidence"][:1]
    lower_bound_statement["dependencyCompletions"] = []
    lower_bound_statement["prerequisiteDocuments"] = []
    lower_bound_wire, _, _ = sign_task_approval_statement(
        module, lower_bound_statement
    )
    lower_bound_parsed, _ = module.parse_task_approval(
        module.canonical_pf_jcs(lower_bound_wire),
        required_bytes,
        policy_bytes,
        phase5_snapshot,
    )
    assert (
        len(lower_bound_parsed.testIds),
        len(lower_bound_parsed.evidence),
        len(lower_bound_parsed.dependencyCompletions),
        len(lower_bound_parsed.prerequisiteDocuments),
        len(lower_bound_parsed.independentReviews),
        len(lower_bound_parsed.signatures),
    ) == (1, 1, 0, 0, 2, 2), (
        "TaskApproval must accept all effective lower bounds; task policy makes "
        "review/signature minimum two even though their structural minimum is one"
    )

    preflight_mutations = []

    wrong_schema = copy.deepcopy(approval_wire)
    wrong_schema["schema"] = "proof-forge.bootstrap-task-approval.v2"
    preflight_mutations.append(("wrong TaskApproval schema", wrong_schema))

    unknown_root_field = copy.deepcopy(approval_wire)
    unknown_root_field["futureField"] = True
    preflight_mutations.append((
        "unknown TaskApproval root field", unknown_root_field
    ))
    unknown_evidence_field = copy.deepcopy(approval_wire)
    unknown_evidence_field["evidence"][0]["futureField"] = True
    preflight_mutations.append((
        "unknown nested EvidenceRef field", unknown_evidence_field
    ))
    missing_root_field = copy.deepcopy(approval_wire)
    del missing_root_field["taskBreakdown"]
    preflight_mutations.append((
        "missing TaskApproval root field", missing_root_field
    ))
    missing_nested_field = copy.deepcopy(approval_wire)
    del missing_nested_field["evidence"][0]["digest"]
    preflight_mutations.append((
        "missing nested EvidenceRef field", missing_nested_field
    ))
    wrong_task_id = copy.deepcopy(approval_wire)
    wrong_task_id["taskId"] = "TASK-D0-07"
    preflight_mutations.append((
        "TaskApproval outside exact D0-01..06 set",
        resign_task_approval_wire(module, wrong_task_id),
    ))
    wrong_task_document = copy.deepcopy(approval_wire)
    wrong_task_document["taskBreakdown"]["id"] = "PHASE-5"
    preflight_mutations.append((
        "task breakdown ref is not PHASE-4",
        resign_task_approval_wire(module, wrong_task_document),
    ))

    wrong_required_ref = copy.deepcopy(approval_wire)
    wrong_required_ref["requiredTestSet"]["digest"] = digest_text(bytes(32))
    preflight_mutations.append((
        "wrong RequiredTestSet ref",
        resign_task_approval_wire(module, wrong_required_ref),
    ))

    nonmember_test = copy.deepcopy(approval_wire)
    nonmember_test["testIds"] = ["TST-ISO-001"]
    preflight_mutations.append((
        "task test outside signed denominator",
        resign_task_approval_wire(module, nonmember_test),
    ))

    review_principal_mismatch = copy.deepcopy(approval_wire)
    review_principal_mismatch["independentReviews"][0] = (
        independent_review_wire("key-security", "security", "a" * 40)
    )
    review_principal_mismatch["independentReviews"].sort(
        key=lambda review: review["keyId"]
    )
    preflight_mutations.append((
        "review and signature principal sets differ",
        resign_task_approval_wire(module, review_principal_mismatch),
    ))

    unauthorized_review_role = copy.deepcopy(approval_wire)
    unauthorized_review_role["independentReviews"][0]["role"] = "quality"
    preflight_mutations.append((
        "review role is not authorized for its exact key",
        resign_task_approval_wire(module, unauthorized_review_role),
    ))

    duplicate_report = copy.deepcopy(approval_wire)
    duplicate_report["independentReviews"][1]["reportDigest"] = (
        duplicate_report["independentReviews"][0]["reportDigest"]
    )
    preflight_mutations.append((
        "duplicate independent review report digest",
        resign_task_approval_wire(module, duplicate_report),
    ))

    for field in ("testIds", "evidence", "independentReviews"):
        empty_nonempty = copy.deepcopy(approval_wire)
        empty_nonempty[field] = []
        preflight_mutations.append((
            f"empty nonempty array {field}",
            resign_task_approval_wire(module, empty_nonempty),
        ))
    empty_signatures = copy.deepcopy(approval_wire)
    empty_signatures["signatures"] = []
    preflight_mutations.append(("empty signatures", empty_signatures))

    over_tests = copy.deepcopy(approval_wire)
    over_tests["testIds"] = [
        f"TST-BOUND-{index:04d}" for index in range(4097)
    ]
    preflight_mutations.append((
        "4097 task test IDs",
        resign_task_approval_wire(module, over_tests),
    ))

    over_evidence = copy.deepcopy(approval_wire)
    over_evidence["evidence"] = [
        {
            "id": f"EV-20260716-{index:04d}",
            "digest": digest_text(bytes.fromhex("64" * 32)),
        }
        for index in range(4097)
    ]
    preflight_mutations.append((
        "4097 evidence refs",
        resign_task_approval_wire(module, over_evidence),
    ))

    def receipt_ref(task_number: int, *, day: str = "20260716") -> dict:
        return {
            "taskId": f"TASK-D0-0{task_number}",
            "id": f"BTV-{day}-{task_number:04d}",
            "digest": digest_text(bytes([task_number]) * 32),
        }

    over_dependencies = copy.deepcopy(approval_wire)
    over_dependencies["dependencyCompletions"] = [
        receipt_ref(task_number) for task_number in range(1, 7)
    ]
    preflight_mutations.append((
        "six dependency completion refs",
        resign_task_approval_wire(module, over_dependencies),
    ))

    over_prerequisites = copy.deepcopy(approval_wire)
    over_prerequisites["prerequisiteDocuments"] = [
        normative_document_ref_wire(f"PHASE-BOUND-{index:03d}", "a" * 40)
        for index in range(257)
    ]
    preflight_mutations.append((
        "257 prerequisite document refs",
        resign_task_approval_wire(module, over_prerequisites),
    ))

    over_reviews = copy.deepcopy(approval_wire)
    over_reviews["independentReviews"] = [
        independent_review_wire(key_id, role, "a" * 40)
        for key_id, role in (
            ("key-architecture", "architecture"),
            ("key-quality", "quality"),
            ("key-release", "release"),
            ("key-security", "security"),
            ("key-z-over-bound", "architecture"),
        )
    ]
    preflight_mutations.append((
        "reviews over distinct-principal bound",
        resign_task_approval_wire(module, over_reviews),
    ))

    over_signatures = copy.deepcopy(approval_wire)
    over_signatures["signatures"] = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": "00" * 64,
        }
        for key_id in (
            "key-architecture", "key-quality", "key-release", "key-security",
            "key-z-over-bound",
        )
    ]
    preflight_mutations.append((
        "signatures over policy-entry bound", over_signatures
    ))

    two_tests = copy.deepcopy(approval_wire)
    two_tests["testIds"] = ["TST-DOC-001", "TST-EVIDENCE-001"]
    reordered_tests = copy.deepcopy(two_tests)
    reordered_tests["testIds"].reverse()
    duplicate_tests = copy.deepcopy(two_tests)
    duplicate_tests["testIds"][1] = duplicate_tests["testIds"][0]
    for label, mutation in (
        ("reordered task test IDs", reordered_tests),
        ("duplicate task test ID", duplicate_tests),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    reordered_evidence = copy.deepcopy(approval_wire)
    reordered_evidence["evidence"].reverse()
    duplicate_evidence = copy.deepcopy(approval_wire)
    duplicate_evidence["evidence"][1]["id"] = (
        duplicate_evidence["evidence"][0]["id"]
    )
    for label, mutation in (
        ("reordered evidence refs", reordered_evidence),
        ("duplicate EvidenceRef id", duplicate_evidence),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    two_dependencies = copy.deepcopy(approval_wire)
    two_dependencies["dependencyCompletions"] = [receipt_ref(2), receipt_ref(3)]
    reordered_dependencies = copy.deepcopy(two_dependencies)
    reordered_dependencies["dependencyCompletions"].reverse()
    duplicate_dependencies = copy.deepcopy(two_dependencies)
    duplicate_dependencies["dependencyCompletions"][1]["taskId"] = (
        duplicate_dependencies["dependencyCompletions"][0]["taskId"]
    )
    for label, mutation in (
        ("reordered dependency completion refs", reordered_dependencies),
        ("duplicate dependency taskId", duplicate_dependencies),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    reordered_prerequisites = copy.deepcopy(approval_wire)
    reordered_prerequisites["prerequisiteDocuments"].reverse()
    duplicate_prerequisites = copy.deepcopy(approval_wire)
    duplicate_prerequisites["prerequisiteDocuments"][1]["id"] = (
        duplicate_prerequisites["prerequisiteDocuments"][0]["id"]
    )
    for label, mutation in (
        ("reordered prerequisite document refs", reordered_prerequisites),
        ("duplicate prerequisite document id", duplicate_prerequisites),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    reordered_reviews = copy.deepcopy(approval_wire)
    reordered_reviews["independentReviews"].reverse()
    duplicate_review_key = copy.deepcopy(approval_wire)
    duplicate_review_key["independentReviews"].append(
        copy.deepcopy(duplicate_review_key["independentReviews"][0])
    )
    duplicate_review_key["independentReviews"][-1]["reportDigest"] = (
        digest_text(bytes.fromhex("65" * 32))
    )
    duplicate_review_key["independentReviews"].sort(
        key=lambda review: review["keyId"]
    )
    for label, mutation in (
        ("reordered independent reviews", reordered_reviews),
        ("duplicate independent review keyId", duplicate_review_key),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    reordered_signatures = copy.deepcopy(approval_wire)
    reordered_signatures["signatures"].reverse()
    duplicate_signature_key = copy.deepcopy(approval_wire)
    duplicate_signature_key["signatures"].append(
        copy.deepcopy(duplicate_signature_key["signatures"][0])
    )
    duplicate_signature_key["signatures"].sort(
        key=lambda signature: signature["keyId"]
    )
    preflight_mutations.extend((
        ("reordered TaskApproval signatures", reordered_signatures),
        ("duplicate TaskApproval signature keyId", duplicate_signature_key),
    ))

    impossible_evidence_date = copy.deepcopy(approval_wire)
    impossible_evidence_date["evidence"][0]["id"] = "EV-20260230-0026"
    preflight_mutations.append((
        "impossible Gregorian EvidenceRef date",
        resign_task_approval_wire(module, impossible_evidence_date),
    ))
    impossible_receipt_date = copy.deepcopy(approval_wire)
    impossible_receipt_date["dependencyCompletions"] = [
        receipt_ref(2, day="20260230")
    ]
    preflight_mutations.append((
        "impossible Gregorian BTV ref date",
        resign_task_approval_wire(module, impossible_receipt_date),
    ))
    malformed_receipt_id = copy.deepcopy(approval_wire)
    malformed_receipt_id["dependencyCompletions"] = [receipt_ref(2)]
    malformed_receipt_id["dependencyCompletions"][0]["id"] = "BTV-20260716-1"
    preflight_mutations.append((
        "malformed BTV ref ID grammar",
        resign_task_approval_wire(module, malformed_receipt_id),
    ))

    wrong_policy_ref = copy.deepcopy(approval_wire)
    wrong_policy_ref["authorityPolicy"]["digest"] = digest_text(bytes(32))
    wrong_stage0_schema = copy.deepcopy(approval_wire)
    wrong_stage0_schema["stage0Handoff"]["schema"] = (
        "proof-forge.eligible-stage0-handoff.v2"
    )
    for label, mutation in (
        ("wrong authority policy ref", wrong_policy_ref),
        ("wrong Stage-0 handoff schema", wrong_stage0_schema),
    ):
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    review_mutations = []
    unknown_review_key = copy.deepcopy(approval_wire)
    unknown_review_key["independentReviews"][0] = independent_review_wire(
        "key-a-unknown", "architecture", "a" * 40
    )
    review_mutations.append(("unknown independent review key", unknown_review_key))
    bad_review_commit = copy.deepcopy(approval_wire)
    bad_review_commit["independentReviews"][0]["reviewCommit"] = "c" * 40
    review_mutations.append(("review commit differs from candidate", bad_review_commit))
    bad_review_link = copy.deepcopy(approval_wire)
    bad_review_link["independentReviews"][0]["reviewLink"] = (
        "http://review.example/not-https"
    )
    review_mutations.append(("non-HTTPS review link", bad_review_link))
    bad_review_digest = copy.deepcopy(approval_wire)
    bad_review_digest["independentReviews"][0]["reportDigest"] = (
        "sha256:" + "A" * 64
    )
    review_mutations.append(("malformed review report digest", bad_review_digest))
    bad_review_decision = copy.deepcopy(approval_wire)
    bad_review_decision["independentReviews"][0]["decision"] = "rejected"
    review_mutations.append(("non-approved review decision", bad_review_decision))
    for label, mutation in review_mutations:
        mutation["independentReviews"].sort(key=lambda review: review["keyId"])
        preflight_mutations.append((
            label, resign_task_approval_wire(module, mutation)
        ))

    wrong_task_rule = copy.deepcopy(approval_wire)
    wrong_task_rule["taskId"] = "TASK-D0-03"
    preflight_mutations.append((
        "D0-03 signatures do not cover its security role",
        resign_task_approval_wire(module, wrong_task_rule),
    ))

    single_principal_statement = copy.deepcopy(approval_statement)
    single_principal_statement["independentReviews"] = [
        independent_review_wire("key-architecture", "architecture", "a" * 40)
    ]
    single_principal_wire, _, _ = sign_task_approval_statement(
        module,
        single_principal_statement,
        signer_key_ids=("key-architecture",),
    )
    preflight_mutations.append((
        "structural review/signature lower bound below D0-01 task rule",
        single_principal_wire,
    ))

    signature_syntax_mutations = []
    wrong_signature_algorithm = copy.deepcopy(approval_wire)
    wrong_signature_algorithm["signatures"][0]["algorithm"] = "ed25519ph"
    signature_syntax_mutations.append((
        "wrong TaskApproval signature algorithm", wrong_signature_algorithm
    ))
    malformed_signature = copy.deepcopy(approval_wire)
    malformed_signature["signatures"][0]["signature"] = "00" * 63
    signature_syntax_mutations.append((
        "short TaskApproval signature", malformed_signature
    ))
    uppercase_signature = copy.deepcopy(approval_wire)
    uppercase_signature["signatures"][0]["signature"] = (
        uppercase_signature["signatures"][0]["signature"].upper()
    )
    signature_syntax_mutations.append((
        "uppercase TaskApproval signature", uppercase_signature
    ))
    unknown_signature_key = copy.deepcopy(approval_wire)
    unknown_signature_key["signatures"][0]["keyId"] = "key-a-unknown"
    unknown_signature_key["signatures"].sort(
        key=lambda signature: signature["keyId"]
    )
    signature_syntax_mutations.append((
        "unknown TaskApproval signature key", unknown_signature_key
    ))
    preflight_mutations.extend(signature_syntax_mutations)

    context_preflight_mutations = []
    stronger_policy_wire = copy.deepcopy(valid_bootstrap_authority_policy())
    stronger_policy_wire["taskRules"][0]["rule"] = approval_rule(
        "architecture", "quality", "security", minimum=3
    )
    stronger_policy_bytes = module.canonical_pf_jcs(stronger_policy_wire)
    _, stronger_policy_ref = module.parse_bootstrap_authority_policy(
        stronger_policy_bytes
    )
    stronger_required_wire = signed_document_bound_required_set(
        module, stronger_policy_ref, phase5_snapshot
    )
    stronger_required_bytes = module.canonical_pf_jcs(stronger_required_wire)
    stronger_approval_statement = task_approval_statement(
        module, stronger_policy_ref, stronger_required_bytes
    )
    stronger_approval_wire, _, _ = sign_task_approval_statement(
        module, stronger_approval_statement
    )
    context_preflight_mutations.append((
        "stronger task-specific threshold and role rule",
        stronger_approval_wire,
        stronger_required_bytes,
        stronger_policy_bytes,
        phase5_snapshot,
    ))

    rotation_seed = bytes.fromhex("71" * 32)
    rotation_public_key, _ = ed25519_sign_from_rfc_seed(rotation_seed, b"")
    rotation_policy_wire = copy.deepcopy(valid_bootstrap_authority_policy())
    rotation_policy_wire["principals"].insert(1, {
        "principalId": "principal-architecture",
        "keyId": "key-architecture-rotation",
        "publicKey": rotation_public_key.hex(),
        "roles": ["architecture"],
    })
    rotation_policy_bytes = module.canonical_pf_jcs(rotation_policy_wire)
    _, rotation_policy_ref = module.parse_bootstrap_authority_policy(
        rotation_policy_bytes
    )
    rotation_required_wire = signed_document_bound_required_set(
        module, rotation_policy_ref, phase5_snapshot
    )
    rotation_required_bytes = module.canonical_pf_jcs(rotation_required_wire)
    rotation_statement = task_approval_statement(
        module,
        rotation_policy_ref,
        rotation_required_bytes,
        review_keys=(
            ("key-architecture-rotation", "architecture"),
            ("key-quality", "quality"),
        ),
    )
    rotation_wire, _, _ = sign_task_approval_statement(
        module, rotation_statement
    )
    rotation_parsed, _ = module.parse_task_approval(
        module.canonical_pf_jcs(rotation_wire),
        rotation_required_bytes,
        rotation_policy_bytes,
        phase5_snapshot,
    )
    assert tuple(
        review.keyId for review in rotation_parsed.independentReviews
    ) == ("key-architecture-rotation", "key-quality")
    assert tuple(
        signature.keyId for signature in rotation_parsed.signatures
    ) == ("key-architecture", "key-quality"), (
        "review and signature keys may rotate when their principal sets match"
    )

    duplicate_review_principal = copy.deepcopy(rotation_wire)
    duplicate_review_principal["independentReviews"].append(
        independent_review_wire("key-architecture", "architecture", "a" * 40)
    )
    duplicate_review_principal["independentReviews"].sort(
        key=lambda review: review["keyId"]
    )
    duplicate_review_principal = resign_task_approval_wire(
        module, duplicate_review_principal
    )
    context_preflight_mutations.append((
        "duplicate review principal through two rotation keys",
        duplicate_review_principal,
        rotation_required_bytes,
        rotation_policy_bytes,
        phase5_snapshot,
    ))

    rotation_threshold_policy = copy.deepcopy(rotation_policy_wire)
    rotation_threshold_policy["taskRules"][0]["rule"] = approval_rule(
        "architecture", "quality", minimum=3
    )
    rotation_threshold_policy_bytes = module.canonical_pf_jcs(
        rotation_threshold_policy
    )
    _, rotation_threshold_policy_ref = module.parse_bootstrap_authority_policy(
        rotation_threshold_policy_bytes
    )
    rotation_threshold_required_wire = signed_document_bound_required_set(
        module, rotation_threshold_policy_ref, phase5_snapshot
    )
    rotation_threshold_required_bytes = module.canonical_pf_jcs(
        rotation_threshold_required_wire
    )
    rotation_threshold_statement = task_approval_statement(
        module,
        rotation_threshold_policy_ref,
        rotation_threshold_required_bytes,
        review_keys=(
            ("key-architecture-rotation", "architecture"),
            ("key-quality", "quality"),
        ),
    )
    rotation_threshold_seeds = dict(RFC_8032_SEEDS_BY_KEY_ID)
    rotation_threshold_seeds["key-architecture-rotation"] = rotation_seed
    rotation_threshold_wire, _, _ = sign_task_approval_statement(
        module,
        rotation_threshold_statement,
        signer_key_ids=(
            "key-architecture",
            "key-architecture-rotation",
            "key-quality",
        ),
        signer_seeds=rotation_threshold_seeds,
    )
    context_preflight_mutations.append((
        "same principal rotation keys cannot forge distinct quorum",
        rotation_threshold_wire,
        rotation_threshold_required_bytes,
        rotation_threshold_policy_bytes,
        phase5_snapshot,
    ))

    misleading_review_policy = copy.deepcopy(valid_bootstrap_authority_policy())
    review_quality_seed = bytes.fromhex("72" * 32)
    review_architecture_seed = bytes.fromhex("73" * 32)
    review_quality_key, _ = ed25519_sign_from_rfc_seed(
        review_quality_seed, b""
    )
    review_architecture_key, _ = ed25519_sign_from_rfc_seed(
        review_architecture_seed, b""
    )
    misleading_review_policy["principals"].extend((
        {
            "principalId": "principal-architecture",
            "keyId": "key-a-review-quality",
            "publicKey": review_quality_key.hex(),
            "roles": ["quality"],
        },
        {
            "principalId": "principal-security",
            "keyId": "key-security-review-architecture",
            "publicKey": review_architecture_key.hex(),
            "roles": ["architecture"],
        },
    ))
    misleading_review_policy["principals"].sort(
        key=lambda principal: principal["keyId"]
    )
    misleading_review_policy_bytes = module.canonical_pf_jcs(
        misleading_review_policy
    )
    _, misleading_review_policy_ref = module.parse_bootstrap_authority_policy(
        misleading_review_policy_bytes
    )
    misleading_review_required_wire = signed_document_bound_required_set(
        module, misleading_review_policy_ref, phase5_snapshot
    )
    misleading_review_required_bytes = module.canonical_pf_jcs(
        misleading_review_required_wire
    )
    misleading_review_statement = task_approval_statement(
        module,
        misleading_review_policy_ref,
        misleading_review_required_bytes,
        review_keys=(
            ("key-a-review-quality", "quality"),
            ("key-security-review-architecture", "architecture"),
        ),
    )
    misleading_review_wire, _, _ = sign_task_approval_statement(
        module,
        misleading_review_statement,
        signer_key_ids=("key-architecture", "key-security"),
    )
    context_preflight_mutations.append((
        "review roles cannot replace exact signature-key role coverage",
        misleading_review_wire,
        misleading_review_required_bytes,
        misleading_review_policy_bytes,
        phase5_snapshot,
    ))

    malformed_phase5_snapshot = dataclasses.replace(
        phase5_snapshot,
        bytes=b"not a canonical PHASE-5 snapshot\n",
    )
    context_preflight_mutations.append((
        "malformed PHASE-5 snapshot through four-input API",
        approval_wire,
        required_bytes,
        policy_bytes,
        malformed_phase5_snapshot,
    ))
    alternate_phase5_metadata = dict(PHASE5_FRONTMATTER)
    alternate_phase5_metadata["reviewLink"] = (
        "https://review.example/phase-5/alternate-approval"
    )
    alternate_phase5_document = make_phase5_snapshot(
        module, metadata=alternate_phase5_metadata
    )
    context_preflight_mutations.append((
        "individually valid but different PHASE-5 document ref",
        approval_wire,
        required_bytes,
        policy_bytes,
        alternate_phase5_document,
    ))
    alternate_phase5_denominator = make_phase5_snapshot(
        module,
        required_ids=PHASE5_REQUIRED_IDS + ("TST-ISO-002",),
    )
    context_preflight_mutations.append((
        "individually valid but different PHASE-5 denominator",
        approval_wire,
        required_bytes,
        policy_bytes,
        alternate_phase5_denominator,
    ))

    original_verify_ed25519 = module.verify_ed25519
    curve_calls = 0

    def counted_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        del public_key, message, signature
        nonlocal curve_calls
        curve_calls += 1
        return True

    module.verify_ed25519 = counted_verify_ed25519
    try:
        for label, mutation in preflight_mutations:
            curve_calls = 0
            assert_rejected(
                module,
                lambda mutation=mutation: module.parse_task_approval(
                    module.canonical_pf_jcs(mutation),
                    required_bytes,
                    policy_bytes,
                    phase5_snapshot,
                ),
            )
            assert curve_calls == 0, (
                f"{label} must reject before RequiredTestSet or TaskApproval "
                "signature verification"
            )
        for (
            label,
            mutation,
            case_required_bytes,
            case_policy_bytes,
            case_phase5_snapshot,
        ) in context_preflight_mutations:
            curve_calls = 0
            assert_rejected(
                module,
                lambda mutation=mutation,
                case_required_bytes=case_required_bytes,
                case_policy_bytes=case_policy_bytes,
                case_phase5_snapshot=case_phase5_snapshot: (
                    module.parse_task_approval(
                        module.canonical_pf_jcs(mutation),
                        case_required_bytes,
                        case_policy_bytes,
                        case_phase5_snapshot,
                    )
                ),
            )
            assert curve_calls == 0, (
                f"{label} must reject before RequiredTestSet or TaskApproval "
                "signature verification"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519

    required_statement = {
        key: value for key, value in required_wire.items() if key != "signatures"
    }
    required_statement_digest = hashlib.sha256(
        b"pf.required-test-set-statement.v1\x00"
        + module.canonical_pf_jcs(required_statement)
    ).digest()
    required_signature_message = (
        b"pf.required-test-set-signature.v1\x00" + required_statement_digest
    )
    all_signatures_statement = copy.deepcopy(approval_statement)
    all_signatures_statement["independentReviews"].append(
        independent_review_wire("key-security", "security", "a" * 40)
    )
    all_signatures_statement["independentReviews"].sort(
        key=lambda review: review["keyId"]
    )
    all_signatures_wire, _, all_signatures_message = sign_task_approval_statement(
        module,
        all_signatures_statement,
        signer_key_ids=("key-architecture", "key-quality", "key-security"),
    )
    verification_messages = []

    def traced_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        verification_messages.append(message)
        return original_verify_ed25519(public_key, message, signature)

    module.verify_ed25519 = traced_verify_ed25519
    try:
        all_signatures_parsed, _ = module.parse_task_approval(
            module.canonical_pf_jcs(all_signatures_wire),
            required_bytes,
            policy_bytes,
            phase5_snapshot,
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert len(all_signatures_parsed.signatures) == 3
    assert verification_messages == (
        [required_signature_message, required_signature_message]
        + [all_signatures_message, all_signatures_message, all_signatures_message]
    ), "all RequiredTestSet signatures must precede every TaskApproval signature"

    invalid_redundant_signature = copy.deepcopy(all_signatures_wire)
    encoded_redundant = bytes.fromhex(
        invalid_redundant_signature["signatures"][-1]["signature"]
    )
    invalid_redundant_signature["signatures"][-1]["signature"] = (
        bytes([encoded_redundant[0] ^ 1]) + encoded_redundant[1:]
    ).hex()
    verification_messages = []
    module.verify_ed25519 = traced_verify_ed25519
    try:
        assert_rejected(
            module,
            lambda: module.parse_task_approval(
                module.canonical_pf_jcs(invalid_redundant_signature),
                required_bytes,
                policy_bytes,
                phase5_snapshot,
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert verification_messages == (
        [required_signature_message, required_signature_message]
        + [all_signatures_message, all_signatures_message, all_signatures_message]
    ), "a redundant invalid signature must not be ignored after quorum is met"

    invalid_required_wire = copy.deepcopy(required_wire)
    encoded_required = bytes.fromhex(
        invalid_required_wire["signatures"][-1]["signature"]
    )
    invalid_required_wire["signatures"][-1]["signature"] = (
        bytes([encoded_required[0] ^ 1]) + encoded_required[1:]
    ).hex()
    invalid_required_bytes = module.canonical_pf_jcs(invalid_required_wire)
    approval_for_invalid_required_statement = task_approval_statement(
        module, policy_ref, invalid_required_bytes
    )
    approval_for_invalid_required, _, _ = sign_task_approval_statement(
        module, approval_for_invalid_required_statement
    )
    verification_messages = []
    module.verify_ed25519 = traced_verify_ed25519
    try:
        assert_rejected(
            module,
            lambda: module.parse_task_approval(
                module.canonical_pf_jcs(approval_for_invalid_required),
                invalid_required_bytes,
                policy_bytes,
                phase5_snapshot,
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert verification_messages == [
        required_signature_message, required_signature_message
    ], "invalid RequiredTestSet signature must prevent all TaskApproval curve work"

    wrong_domain = copy.deepcopy(approval_wire)
    wrong_domain_message = (
        b"pf.required-test-set-signature.v1\x00" + statement_digest
    )
    _, wrong_domain_signature = ed25519_sign_from_rfc_seed(
        RFC_8032_SEEDS_BY_KEY_ID["key-architecture"], wrong_domain_message
    )
    wrong_domain["signatures"][0]["signature"] = wrong_domain_signature.hex()
    assert_rejected(
        module,
        lambda: module.parse_task_approval(
            module.canonical_pf_jcs(wrong_domain),
            required_bytes,
            policy_bytes,
            phase5_snapshot,
        ),
    )


def test_bootstrap_task_verifier_receipt(module: ModuleType) -> None:
    fixture = signed_task_receipt_fixture(module)
    parsed, parsed_ref = module.parse_bootstrap_task_verifier_receipt(
        fixture["receiptBytes"],
        fixture["approvalBytes"],
        fixture["requiredBytes"],
        fixture["policyBytes"],
        fixture["phase5Snapshot"],
        fixture["handoffBytes"],
    )
    receipt_wire = fixture["receiptWire"]
    assert isinstance(receipt_wire, dict)
    expected_receipt = module.BootstrapTaskVerifierReceiptV1(
        receipt_wire["schema"],
        receipt_wire["id"],
        receipt_wire["taskId"],
        module.parse_candidate_identity(receipt_wire["candidate"]),
        module.parse_content_ref(receipt_wire["authorityPolicy"]),
        module.parse_content_ref(receipt_wire["requiredTestSet"]),
        module.TaskApprovalRefV1(
            receipt_wire["taskApproval"]["taskId"],
            module.parse_digest(receipt_wire["taskApproval"]["digest"]),
        ),
        module.parse_content_ref(receipt_wire["stage0Handoff"]),
        tuple(
            module.BootstrapTaskVerifierReceiptRefV1(
                dependency["taskId"],
                dependency["id"],
                module.parse_digest(dependency["digest"]),
            )
            for dependency in receipt_wire["dependencyCompletions"]
        ),
        module.parse_digest(receipt_wire["verifierDigest"]),
        receipt_wire["result"],
        module.ApprovalSignatureV1(
            receipt_wire["signature"]["keyId"],
            receipt_wire["signature"]["algorithm"],
            bytes.fromhex(receipt_wire["signature"]["signature"]),
        ),
    )
    receipt_bytes = fixture["receiptBytes"]
    assert isinstance(receipt_bytes, bytes)
    expected_ref_wire = bootstrap_task_receipt_ref_wire(
        module, receipt_wire["taskId"], receipt_wire["id"], receipt_bytes
    )
    expected_ref = module.BootstrapTaskVerifierReceiptRefV1(
        expected_ref_wire["taskId"],
        expected_ref_wire["id"],
        module.parse_digest(expected_ref_wire["digest"]),
    )
    assert parsed == expected_receipt, (
        "task receipt positive must preserve every frozen typed field"
    )
    assert parsed_ref == expected_ref, (
        "task receipt ref must use the full signed-object domain digest"
    )

    receipt_statement = fixture["receiptStatement"]
    assert isinstance(receipt_statement, dict)
    expected_statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-verifier-receipt-statement.v1\x00"
        + module.canonical_pf_jcs(receipt_statement)
    ).digest()
    assert fixture["receiptStatementDigest"] == expected_statement_digest
    assert fixture["receiptSignatureMessage"] == (
        b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        + expected_statement_digest
    )

    five_dependency_fixture = signed_task_receipt_fixture(
        module,
        dependency_completions=tuple(dependency_receipt_refs(5)),
    )
    five_dependency_receipt, _ = module.parse_bootstrap_task_verifier_receipt(
        five_dependency_fixture["receiptBytes"],
        five_dependency_fixture["approvalBytes"],
        five_dependency_fixture["requiredBytes"],
        five_dependency_fixture["policyBytes"],
        five_dependency_fixture["phase5Snapshot"],
        five_dependency_fixture["handoffBytes"],
    )
    assert len(parsed.dependencyCompletions) == 0
    assert len(five_dependency_receipt.dependencyCompletions) == 5, (
        "task receipt dependencyCompletions bounds must include both 0 and 5"
    )

    malformed_receipt = copy.deepcopy(receipt_wire)
    malformed_receipt["futureField"] = True
    wrong_receipt_schema = copy.deepcopy(receipt_wire)
    wrong_receipt_schema["schema"] = (
        "proof-forge.bootstrap-task-verifier-receipt.v2"
    )
    wrong_receipt_schema = resign_bootstrap_task_receipt_wire(
        module, wrong_receipt_schema
    )
    malformed_receipt_id = copy.deepcopy(receipt_wire)
    malformed_receipt_id["id"] = "BTV-20260717-001"
    malformed_receipt_id = resign_bootstrap_task_receipt_wire(
        module, malformed_receipt_id
    )
    impossible_date_receipt = copy.deepcopy(receipt_wire)
    impossible_date_receipt["id"] = "BTV-20260230-0001"
    wrong_receipt_task = copy.deepcopy(receipt_wire)
    wrong_receipt_task["taskId"] = "TASK-D0-02"
    wrong_receipt_task = resign_bootstrap_task_receipt_wire(
        module, wrong_receipt_task
    )
    malformed_signature = copy.deepcopy(receipt_wire)
    malformed_signature["signature"]["signature"] = "00" * 63
    unknown_signature_field = copy.deepcopy(receipt_wire)
    unknown_signature_field["signature"]["futureField"] = True
    unknown_task_approval_ref_field = copy.deepcopy(receipt_wire)
    unknown_task_approval_ref_field["taskApproval"]["futureField"] = True
    unknown_task_approval_ref_field = resign_bootstrap_task_receipt_wire(
        module, unknown_task_approval_ref_field
    )
    wrong_signature_algorithm = copy.deepcopy(receipt_wire)
    wrong_signature_algorithm["signature"]["algorithm"] = "ed25519ph"
    wrong_result = copy.deepcopy(receipt_wire)
    wrong_result["result"] = "task-rejected"
    wrong_result = resign_bootstrap_task_receipt_wire(module, wrong_result)

    malformed_approval = copy.deepcopy(fixture["approvalWire"])
    malformed_approval["futureField"] = True

    malformed_handoff = copy.deepcopy(fixture["handoffWire"])
    malformed_handoff["futureField"] = True
    reordered_channels = copy.deepcopy(fixture["handoffWire"])
    reordered_channels["channels"][0], reordered_channels["channels"][1] = (
        reordered_channels["channels"][1],
        reordered_channels["channels"][0],
    )
    duplicate_channel_fd = copy.deepcopy(fixture["handoffWire"])
    duplicate_channel_fd["channels"][1]["fd"] = (
        duplicate_channel_fd["channels"][0]["fd"]
    )
    unknown_tcb_field = copy.deepcopy(fixture["handoffWire"])
    unknown_tcb_field["tcb"]["futureField"] = True
    unknown_environment_field = copy.deepcopy(fixture["handoffWire"])
    unknown_environment_field["environment"]["futureField"] = True
    unknown_channel_field = copy.deepcopy(fixture["handoffWire"])
    unknown_channel_field["channels"][0]["futureField"] = True

    different_handoff_candidate = copy.deepcopy(fixture["handoffWire"])
    different_handoff_candidate["candidate"] = candidate_identity_wire(
        module, "c" * 40
    )
    different_handoff_candidate["channels"][2]["bindingDigest"] = (
        different_handoff_candidate["candidate"]["archiveDigest"]
    )
    different_handoff_policy = copy.deepcopy(fixture["handoffWire"])
    different_handoff_policy["authorityPolicy"]["digest"] = digest_text(
        bytes.fromhex("77" * 32)
    )
    different_handoff_policy["channels"][0]["bindingDigest"] = (
        different_handoff_policy["authorityPolicy"]["digest"]
    )
    different_handoff_ref = copy.deepcopy(fixture["handoffWire"])
    different_handoff_ref["nonce"] = "78" * 32

    wrong_approval_handoff = copy.deepcopy(fixture["approvalWire"])
    wrong_approval_handoff["stage0Handoff"]["digest"] = digest_text(
        bytes.fromhex("79" * 32)
    )
    wrong_approval_handoff = resign_task_approval_wire(
        module, wrong_approval_handoff
    )

    six_dependencies = copy.deepcopy(receipt_wire)
    six_dependencies["dependencyCompletions"] = [
        {
            "taskId": f"TASK-D0-0{index}",
            "id": f"BTV-20260717-{index:04d}",
            "digest": digest_text(bytes([0x90 + index]) * 32),
        }
        for index in range(1, 7)
    ]
    five_dependency_wire = five_dependency_fixture["receiptWire"]
    assert isinstance(five_dependency_wire, dict)
    reordered_dependencies = copy.deepcopy(five_dependency_wire)
    reordered_dependencies["dependencyCompletions"][0:2] = reversed(
        reordered_dependencies["dependencyCompletions"][0:2]
    )
    duplicate_dependencies = copy.deepcopy(five_dependency_wire)
    duplicate_dependencies["dependencyCompletions"][1] = copy.deepcopy(
        duplicate_dependencies["dependencyCompletions"][0]
    )
    unknown_dependency_field = copy.deepcopy(five_dependency_wire)
    unknown_dependency_field["dependencyCompletions"][0]["futureField"] = True
    unknown_dependency_field = resign_bootstrap_task_receipt_wire(
        module, unknown_dependency_field
    )

    zero_curve_cases = [
        (
            "malformed receipt closed field",
            module.canonical_pf_jcs(malformed_receipt),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "wrong task receipt schema",
            module.canonical_pf_jcs(wrong_receipt_schema),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "malformed task receipt ID grammar",
            module.canonical_pf_jcs(malformed_receipt_id),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt ID contains an impossible Gregorian date",
            module.canonical_pf_jcs(impossible_date_receipt),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt root taskId join",
            module.canonical_pf_jcs(wrong_receipt_task),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "malformed singular receipt signature",
            module.canonical_pf_jcs(malformed_signature),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "unknown singular receipt signature field",
            module.canonical_pf_jcs(unknown_signature_field),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "unknown taskApproval ref field",
            module.canonical_pf_jcs(unknown_task_approval_ref_field),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "wrong singular receipt signature algorithm",
            module.canonical_pf_jcs(wrong_signature_algorithm),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "wrong task receipt result",
            module.canonical_pf_jcs(wrong_result),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "malformed TaskApproval after receipt preflight",
            fixture["receiptBytes"],
            module.canonical_pf_jcs(malformed_approval),
            fixture["handoffBytes"],
        ),
        (
            "malformed raw handoff closed field",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(malformed_handoff),
        ),
        (
            "handoff channel role order",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(reordered_channels),
        ),
        (
            "handoff channel fd uniqueness",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(duplicate_channel_fd),
        ),
        (
            "unknown handoff tcb field",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(unknown_tcb_field),
        ),
        (
            "unknown handoff environment field",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(unknown_environment_field),
        ),
        (
            "unknown handoff channel field",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(unknown_channel_field),
        ),
        (
            "raw handoff candidate join",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(different_handoff_candidate),
        ),
        (
            "raw handoff authority policy join",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(different_handoff_policy),
        ),
        (
            "raw handoff ref join",
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            module.canonical_pf_jcs(different_handoff_ref),
        ),
        (
            "TaskApproval handoff ref join",
            fixture["receiptBytes"],
            module.canonical_pf_jcs(wrong_approval_handoff),
            fixture["handoffBytes"],
        ),
        (
            "receipt dependency count above five",
            module.canonical_pf_jcs(six_dependencies),
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt dependency order",
            module.canonical_pf_jcs(reordered_dependencies),
            five_dependency_fixture["approvalBytes"],
            five_dependency_fixture["handoffBytes"],
        ),
        (
            "receipt dependency duplicate",
            module.canonical_pf_jcs(duplicate_dependencies),
            five_dependency_fixture["approvalBytes"],
            five_dependency_fixture["handoffBytes"],
        ),
        (
            "unknown receipt dependency ref field",
            module.canonical_pf_jcs(unknown_dependency_field),
            five_dependency_fixture["approvalBytes"],
            five_dependency_fixture["handoffBytes"],
        ),
    ]
    for channel_index, channel_role in enumerate((
        "authority-policy",
        "authority-store",
        "candidate-archive",
        "evidence-root",
    )):
        for field, invalid_value in (
            ("transport", "invalid-transport"),
            ("access", "invalid-access"),
        ):
            invalid_channel = copy.deepcopy(fixture["handoffWire"])
            assert isinstance(invalid_channel, dict)
            invalid_channel["channels"][channel_index][field] = invalid_value
            zero_curve_cases.append((
                f"handoff {channel_role} wrong {field}",
                fixture["receiptBytes"],
                fixture["approvalBytes"],
                module.canonical_pf_jcs(invalid_channel),
            ))

    propagated_handoff_zero_curve_cases = []

    def append_handoff_preflight_case(
        label: str,
        mutator: Callable[[dict], None],
    ) -> None:
        propagated_fixture = signed_task_receipt_fixture(
            module,
            mutate_handoff=mutator,
        )
        propagated_handoff_zero_curve_cases.append((
            label,
            propagated_fixture["receiptBytes"],
            propagated_fixture["approvalBytes"],
            propagated_fixture["requiredBytes"],
            propagated_fixture["policyBytes"],
            propagated_fixture["phase5Snapshot"],
            propagated_fixture["handoffBytes"],
        ))

    for field, invalid_value in (
        ("schema", "proof-forge.eligible-stage0-handoff.v2"),
        ("id", "Invalid/Handoff/Id"),
        ("version", "01.0.0"),
        ("runId", "invalid/run/id"),
        ("nonce", "AA" * 32),
        ("eligible", False),
        ("pathnameReopen", True),
        ("fallback", "repository"),
    ):
        append_handoff_preflight_case(
            f"handoff frozen root scalar {field}",
            lambda handoff, field=field, invalid_value=invalid_value: (
                handoff.__setitem__(field, invalid_value)
            ),
        )

    for field, invalid_value in (
        ("schema", "proof-forge.eligible-stage0-handoff.v2"),
        ("id", "Invalid/Handoff/Id"),
        ("version", "01.0.0"),
    ):
        raw_handoff = copy.deepcopy(fixture["handoffWire"])
        assert isinstance(raw_handoff, dict)
        raw_handoff[field] = invalid_value
        raw_handoff_bytes = module.canonical_pf_jcs(raw_handoff)
        assert_rejected(
            module,
            lambda raw_handoff_bytes=raw_handoff_bytes: (
                module._preflight_eligible_stage0_handoff(raw_handoff_bytes)
            ),
        )

    for field, invalid_value in (
        ("mode", "inherit"),
        ("home", "/tmp"),
        ("path", "/usr/local/bin:/usr/bin:/bin"),
        ("lcAll", "en_US.UTF-8"),
        ("tz", "Asia/Shanghai"),
        ("network", "allow"),
    ):
        append_handoff_preflight_case(
            f"handoff frozen environment scalar {field}",
            lambda handoff, field=field, invalid_value=invalid_value: (
                handoff["environment"].__setitem__(field, invalid_value)
            ),
        )

    for invalid_fd in (True, 2, 0x1_0000_0000):
        append_handoff_preflight_case(
            f"handoff channel fd boundary {invalid_fd!r}",
            lambda handoff, invalid_fd=invalid_fd: (
                handoff["channels"][0].__setitem__("fd", invalid_fd)
            ),
        )

    for field in (
        "stage0VerifierDigest",
        "bootstrapVerifierDigest",
        "continuationDigest",
        "formalFinalizerDigest",
    ):
        append_handoff_preflight_case(
            f"handoff malformed tcb digest {field}",
            lambda handoff, field=field: handoff["tcb"].__setitem__(
                field, "sha256:" + "0" * 63
            ),
        )

    for field in (
        "authorityPolicy",
        "authorityStoreService",
        "hostObservation",
        "hostProfile",
    ):
        append_handoff_preflight_case(
            f"handoff closed ContentRef {field}",
            lambda handoff, field=field: handoff[field].__setitem__(
                "futureField", True
            ),
        )
    append_handoff_preflight_case(
        "handoff malformed host observation digest",
        lambda handoff: handoff["hostObservation"].__setitem__(
            "digest", "sha256:" + "0" * 63
        ),
    )
    append_handoff_preflight_case(
        "handoff malformed host profile version",
        lambda handoff: handoff["hostProfile"].__setitem__(
            "version", "01.0.0"
        ),
    )
    append_handoff_preflight_case(
        "handoff malformed evidence-root digest",
        lambda handoff: handoff["channels"][3].__setitem__(
            "bindingDigest", "sha256:" + "0" * 63
        ),
    )

    def receipt_join_mutation(mutator: Callable[[dict], None]) -> bytes:
        mutation = copy.deepcopy(receipt_wire)
        mutator(mutation)
        return module.canonical_pf_jcs(
            resign_bootstrap_task_receipt_wire(module, mutation)
        )

    wrong_policy_ref = copy.deepcopy(receipt_wire["authorityPolicy"])
    wrong_policy_ref["digest"] = digest_text(bytes.fromhex("a1" * 32))
    wrong_required_ref = copy.deepcopy(receipt_wire["requiredTestSet"])
    wrong_required_ref["digest"] = digest_text(bytes.fromhex("a2" * 32))
    wrong_handoff_ref = copy.deepcopy(receipt_wire["stage0Handoff"])
    wrong_handoff_ref["digest"] = digest_text(bytes.fromhex("a3" * 32))
    wrong_task_approval_task = receipt_join_mutation(
        lambda wire: wire["taskApproval"].__setitem__("taskId", "TASK-D0-02")
    )
    wrong_candidate = receipt_join_mutation(
        lambda wire: wire.__setitem__(
            "candidate", candidate_identity_wire(module, "c" * 40)
        )
    )
    wrong_policy = receipt_join_mutation(
        lambda wire: wire.__setitem__("authorityPolicy", wrong_policy_ref)
    )
    wrong_required = receipt_join_mutation(
        lambda wire: wire.__setitem__("requiredTestSet", wrong_required_ref)
    )
    wrong_handoff = receipt_join_mutation(
        lambda wire: wire.__setitem__("stage0Handoff", wrong_handoff_ref)
    )
    wrong_dependencies = receipt_join_mutation(
        lambda wire: wire.__setitem__(
            "dependencyCompletions", dependency_receipt_refs(1)
        )
    )
    wrong_verifier = receipt_join_mutation(
        lambda wire: wire.__setitem__(
            "verifierDigest", digest_text(bytes.fromhex("a4" * 32))
        )
    )
    wrong_receipt_key = module.canonical_pf_jcs(
        resign_bootstrap_task_receipt_wire(
            module, receipt_wire, key_id="key-quality"
        )
    )
    zero_curve_cases.extend((
        (
            "receipt taskApproval.taskId join",
            wrong_task_approval_task,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt candidate join",
            wrong_candidate,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt authority policy join",
            wrong_policy,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt required-test-set join",
            wrong_required,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt stage0 handoff join",
            wrong_handoff,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt dependency join",
            wrong_dependencies,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "receipt verifier digest join",
            wrong_verifier,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
        (
            "ordinary principal key cannot sign verifier receipt",
            wrong_receipt_key,
            fixture["approvalBytes"],
            fixture["handoffBytes"],
        ),
    ))

    for ref_field in (
        "authorityPolicy",
        "requiredTestSet",
        "stage0Handoff",
    ):
        for component, replacement in (
            ("schema", "proof-forge.unrelated.v1"),
            ("id", "different-content-ref"),
            ("version", "2.0.0"),
        ):
            zero_curve_cases.append((
                f"receipt {ref_field} full ContentRef {component} join",
                receipt_join_mutation(
                    lambda wire,
                    ref_field=ref_field,
                    component=component,
                    replacement=replacement: wire[ref_field].__setitem__(
                        component, replacement
                    )
                ),
                fixture["approvalBytes"],
                fixture["handoffBytes"],
            ))

    for component, replacement in (
        ("schema", "proof-forge.unrelated.v1"),
        ("id", "different-content-ref"),
        ("version", "2.0.0"),
    ):
        changed_approval_handoff = copy.deepcopy(fixture["approvalWire"])
        assert isinstance(changed_approval_handoff, dict)
        changed_approval_handoff["stage0Handoff"][component] = replacement
        zero_curve_cases.append((
            f"TaskApproval stage0Handoff full ContentRef {component} join",
            fixture["receiptBytes"],
            module.canonical_pf_jcs(resign_task_approval_wire(
                module, changed_approval_handoff
            )),
            fixture["handoffBytes"],
        ))

    one_dependency_fixture = signed_task_receipt_fixture(
        module,
        dependency_completions=tuple(dependency_receipt_refs(1)),
    )
    one_dependency_receipt = one_dependency_fixture["receiptWire"]
    assert isinstance(one_dependency_receipt, dict)
    for component, replacement in (
        ("taskId", "TASK-D0-03"),
        ("id", "BTV-20260718-0002"),
        ("digest", digest_text(bytes.fromhex("d1" * 32))),
    ):
        changed_dependency = copy.deepcopy(one_dependency_receipt)
        changed_dependency["dependencyCompletions"][0][component] = replacement
        zero_curve_cases.append((
            f"receipt dependency full ref {component} join",
            module.canonical_pf_jcs(resign_bootstrap_task_receipt_wire(
                module, changed_dependency
            )),
            one_dependency_fixture["approvalBytes"],
            one_dependency_fixture["handoffBytes"],
        ))

    def break_policy_channel_binding(handoff: dict) -> None:
        handoff["channels"][0]["bindingDigest"] = digest_text(
            bytes.fromhex("b1" * 32)
        )

    def break_bootstrap_verifier_pin(handoff: dict) -> None:
        handoff["tcb"]["bootstrapVerifierDigest"] = digest_text(
            bytes.fromhex("b2" * 32)
        )

    def break_authority_store_pin(handoff: dict) -> None:
        wrong_store_digest = digest_text(bytes.fromhex("b3" * 32))
        handoff["authorityStoreService"]["digest"] = wrong_store_digest
        handoff["channels"][1]["bindingDigest"] = wrong_store_digest

    def break_candidate_archive_binding(handoff: dict) -> None:
        handoff["channels"][2]["bindingDigest"] = digest_text(
            bytes.fromhex("b4" * 32)
        )

    def break_authority_store_channel_binding(handoff: dict) -> None:
        handoff["channels"][1]["bindingDigest"] = digest_text(
            bytes.fromhex("b5" * 32)
        )

    def break_handoff_candidate_semantic_join(handoff: dict) -> None:
        handoff["candidate"] = candidate_identity_wire(module, "c" * 40)
        handoff["channels"][2]["bindingDigest"] = (
            handoff["candidate"]["archiveDigest"]
        )

    def break_handoff_policy_semantic_join(handoff: dict) -> None:
        wrong_policy_digest = digest_text(bytes.fromhex("b6" * 32))
        handoff["authorityPolicy"]["digest"] = wrong_policy_digest
        handoff["channels"][0]["bindingDigest"] = wrong_policy_digest

    for label, mutator in (
        ("authority-policy channel binding double pin", break_policy_channel_binding),
        ("bootstrap verifier policy/handoff double pin", break_bootstrap_verifier_pin),
        ("authority-store policy/handoff double pin", break_authority_store_pin),
        ("candidate archive channel binding", break_candidate_archive_binding),
        ("authority-store channel binding", break_authority_store_channel_binding),
        ("raw handoff propagated candidate semantic join", break_handoff_candidate_semantic_join),
        ("raw handoff propagated policy semantic join", break_handoff_policy_semantic_join),
    ):
        broken_fixture = signed_task_receipt_fixture(
            module, mutate_handoff=mutator
        )
        zero_curve_cases.append((
            label,
            broken_fixture["receiptBytes"],
            broken_fixture["approvalBytes"],
            broken_fixture["handoffBytes"],
        ))

    for ref_field in ("authorityPolicy", "authorityStoreService"):
        for component, replacement in (
            ("schema", "proof-forge.unrelated.v1"),
            ("id", "different-content-ref"),
            ("version", "2.0.0"),
        ):
            def mutate_handoff_ref(
                handoff: dict,
                ref_field: str = ref_field,
                component: str = component,
                replacement: str = replacement,
            ) -> None:
                handoff[ref_field][component] = replacement

            broken_fixture = signed_task_receipt_fixture(
                module,
                mutate_handoff=mutate_handoff_ref,
            )
            zero_curve_cases.append((
                f"raw handoff {ref_field} full ContentRef {component} join",
                broken_fixture["receiptBytes"],
                broken_fixture["approvalBytes"],
                broken_fixture["handoffBytes"],
            ))

    original_verify_ed25519 = module.verify_ed25519
    curve_calls = 0

    def counted_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        del public_key, message, signature
        nonlocal curve_calls
        curve_calls += 1
        return True

    module.verify_ed25519 = counted_verify_ed25519
    try:
        for label, case_receipt, case_approval, case_handoff in zero_curve_cases:
            curve_calls = 0
            assert_rejected(
                module,
                lambda case_receipt=case_receipt,
                case_approval=case_approval,
                case_handoff=case_handoff: (
                    module.parse_bootstrap_task_verifier_receipt(
                        case_receipt,
                        case_approval,
                        fixture["requiredBytes"],
                        fixture["policyBytes"],
                        fixture["phase5Snapshot"],
                        case_handoff,
                    )
                ),
            )
            assert curve_calls == 0, (
                f"{label} must reject before RequiredTestSet, TaskApproval, "
                "or receipt signature verification"
            )
        for (
            label,
            case_receipt,
            case_approval,
            case_required,
            case_policy,
            case_snapshot,
            case_handoff,
        ) in propagated_handoff_zero_curve_cases:
            curve_calls = 0
            assert_rejected(
                module,
                lambda case_receipt=case_receipt,
                case_approval=case_approval,
                case_required=case_required,
                case_policy=case_policy,
                case_snapshot=case_snapshot,
                case_handoff=case_handoff: (
                    module.parse_bootstrap_task_verifier_receipt(
                        case_receipt,
                        case_approval,
                        case_required,
                        case_policy,
                        case_snapshot,
                        case_handoff,
                    )
                ),
            )
            assert curve_calls == 0, (
                f"{label} with propagated handoff ref must reject before "
                "RequiredTestSet, TaskApproval, or receipt signature verification"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519

    required_wire = fixture["requiredWire"]
    assert isinstance(required_wire, dict)
    required_statement = {
        key: value for key, value in required_wire.items() if key != "signatures"
    }
    required_statement_digest = hashlib.sha256(
        b"pf.required-test-set-statement.v1\x00"
        + module.canonical_pf_jcs(required_statement)
    ).digest()
    required_signature_message = (
        b"pf.required-test-set-signature.v1\x00" + required_statement_digest
    )
    approval_signature_message = fixture["approvalSignatureMessage"]
    receipt_signature_message = fixture["receiptSignatureMessage"]

    verification_messages = []
    receipt_digest_after_curve_counts = []

    def traced_verify_ed25519(
        public_key: bytes, message: bytes, signature: bytes
    ) -> bool:
        verification_messages.append(message)
        return original_verify_ed25519(public_key, message, signature)

    original_sha256 = module.hashlib.sha256

    def traced_sha256(data: bytes = b"") -> object:
        if data.startswith(b"pf.bootstrap-task-verifier-receipt.v1\x00"):
            receipt_digest_after_curve_counts.append(len(verification_messages))
        return original_sha256(data)

    module.verify_ed25519 = traced_verify_ed25519
    module.hashlib.sha256 = traced_sha256
    try:
        module.parse_bootstrap_task_verifier_receipt(
            fixture["receiptBytes"],
            fixture["approvalBytes"],
            fixture["requiredBytes"],
            fixture["policyBytes"],
            fixture["phase5Snapshot"],
            fixture["handoffBytes"],
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
        module.hashlib.sha256 = original_sha256
    assert verification_messages == (
        [required_signature_message, required_signature_message]
        + [approval_signature_message, approval_signature_message]
        + [receipt_signature_message]
    ), (
        "signature work must be ordered RequiredTestSet, TaskApproval, then receipt"
    )
    assert receipt_digest_after_curve_counts == [5], (
        "full receipt digest must be computed exactly once after every signature"
    )

    wrong_approval_digest = copy.deepcopy(receipt_wire)
    wrong_approval_digest["taskApproval"]["digest"] = digest_text(
        bytes.fromhex("c1" * 32)
    )
    wrong_approval_digest = resign_bootstrap_task_receipt_wire(
        module, wrong_approval_digest
    )
    verification_messages = []
    module.verify_ed25519 = traced_verify_ed25519
    try:
        assert_rejected(
            module,
            lambda: module.parse_bootstrap_task_verifier_receipt(
                module.canonical_pf_jcs(wrong_approval_digest),
                fixture["approvalBytes"],
                fixture["requiredBytes"],
                fixture["policyBytes"],
                fixture["phase5Snapshot"],
                fixture["handoffBytes"],
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert verification_messages == (
        [required_signature_message, required_signature_message]
        + [approval_signature_message, approval_signature_message]
    ), (
        "wrong approval digest must reject after approval finalize and before "
        "receipt curve work"
    )

    bad_receipt_signature = copy.deepcopy(receipt_wire)
    encoded_signature = bytes.fromhex(
        bad_receipt_signature["signature"]["signature"]
    )
    bad_receipt_signature["signature"]["signature"] = (
        bytes([encoded_signature[0] ^ 1]) + encoded_signature[1:]
    ).hex()
    verification_messages = []
    receipt_digest_after_curve_counts = []
    module.verify_ed25519 = traced_verify_ed25519
    module.hashlib.sha256 = traced_sha256
    try:
        assert_rejected(
            module,
            lambda: module.parse_bootstrap_task_verifier_receipt(
                module.canonical_pf_jcs(bad_receipt_signature),
                fixture["approvalBytes"],
                fixture["requiredBytes"],
                fixture["policyBytes"],
                fixture["phase5Snapshot"],
                fixture["handoffBytes"],
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
        module.hashlib.sha256 = original_sha256
    assert verification_messages == (
        [required_signature_message, required_signature_message]
        + [approval_signature_message, approval_signature_message]
        + [receipt_signature_message]
    ), "tampered receipt signature must be checked after both signed prerequisites"
    assert receipt_digest_after_curve_counts == [], (
        "invalid receipt signature must prevent full receipt digest computation"
    )


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

    max_semver_ref = dict(
        schema="proof-forge.required-test-set.v1",
        id="phase-5-required-tests",
        version="18446744073709551615.0.0",
        digest=zero_digest,
    )
    assert module.parse_content_ref(max_semver_ref).version == max_semver_ref["version"]
    overflow_semver_ref = dict(max_semver_ref)
    overflow_semver_ref["version"] = "18446744073709551616.0.0"
    assert_rejected(module, lambda: module.parse_content_ref(overflow_semver_ref))

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


def test_subject_graph_preflight(module: ModuleType, candidate: object) -> None:
    rows = (
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-01",
            dependencies=(),
            prerequisites=(
                {"documentId": "PHASE-1", "requiredStatus": "accepted"},
                {"documentId": "PHASE-2", "requiredStatus": "accepted"},
                {"documentId": "PHASE-3", "requiredStatus": "accepted"},
            ),
            testIds=("TST-DOC-001",),
            evidenceIds=("EV-20260717-0001",),
        ),
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-02",
            dependencies=("TASK-D0-01",),
            prerequisites=(),
            testIds=("TST-ISO-001",),
            evidenceIds=("EV-20260717-0002",),
        ),
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-03",
            dependencies=("TASK-D0-01", "TASK-D0-02"),
            prerequisites=(),
            testIds=("TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"),
            evidenceIds=("EV-20260717-0003", "EV-20260717-0004"),
        ),
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-04",
            dependencies=(
                "TASK-D0-02",
                "TASK-D0-03",
                "TASK-D0-05",
                "TASK-D0-06",
            ),
            prerequisites=(),
            testIds=("TST-BOOTSTRAP-001",),
            evidenceIds=("EV-20260717-0005",),
        ),
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-05",
            dependencies=("TASK-D0-03",),
            prerequisites=(),
            testIds=("TST-SBOM-001",),
            evidenceIds=("EV-20260717-0006",),
        ),
        module.BootstrapTaskRowSubjectV1(
            taskId="TASK-D0-06",
            dependencies=("TASK-D0-01", "TASK-D0-02"),
            prerequisites=(),
            testIds=("TST-COMMON-001",),
            evidenceIds=("EV-20260717-0007",),
        ),
    )
    evidence_rows = (
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0001",
            taskId="TASK-D0-01",
            testIds=("TST-DOC-001",),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0002",
            taskId="TASK-D0-02",
            testIds=("TST-ISO-001",),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0003",
            taskId="TASK-D0-03",
            testIds=("TST-EVIDENCE-001", "TST-HOST-001"),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0004",
            taskId="TASK-D0-03",
            testIds=("TST-HOST-001", "TST-TOOL-001"),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0005",
            taskId="TASK-D0-04",
            testIds=("TST-BOOTSTRAP-001",),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0006",
            taskId="TASK-D0-05",
            testIds=("TST-SBOM-001",),
            grade="bootstrap",
            result="passed",
        ),
        module.BootstrapLedgerSubjectV1(
            id="EV-20260717-0007",
            taskId="TASK-D0-06",
            testIds=("TST-COMMON-001",),
            grade="bootstrap",
            result="passed",
        ),
    )
    documents = tuple(
        module.BootstrapDocumentSnapshotV1(
            id=document_id,
            path=f"docs/{index:02d}-{document_id.lower()}.md",
            bytes=(
                "---\n"
                f"id: {document_id}\n"
                "status: accepted\n"
                "---\n"
            ).encode("utf-8"),
        )
        for index, document_id in enumerate(
            ("PHASE-1", "PHASE-2", "PHASE-3", "PHASE-4", "PHASE-5"),
            start=1,
        )
    )
    subject = module.BootstrapTaskSubjectV1(
        candidate=candidate,
        rootTaskId="TASK-D0-04",
        taskRows=rows,
        evidenceRows=evidence_rows,
        documents=documents,
    )
    assert module._validate_subject(subject) is None

    leap_day_evidence_id = "EV-20280229-0001"
    leap_day_subject = dataclasses.replace(
        subject,
        taskRows=rows[:-1] + (
            dataclasses.replace(
                rows[-1], evidenceIds=(leap_day_evidence_id,)
            ),
        ),
        evidenceRows=evidence_rows[:-1] + (
            dataclasses.replace(
                evidence_rows[-1], id=leap_day_evidence_id
            ),
        ),
    )
    assert module._validate_subject(leap_day_subject) is None

    unicode_document_subject = dataclasses.replace(
        subject,
        documents=(
            dataclasses.replace(
                documents[0],
                path="docs/阶段一.md",
                bytes=b"---\nid: PHASE-1\nstatus: accepted\n---\n"
                + "标题: 阶段一\n".encode("utf-8"),
            ),
        ) + documents[1:],
    )
    assert module._validate_subject(unicode_document_subject) is None

    maximum_test_id = "TST-" + "A" * 123
    maximum_test_id_subject = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(rows[0], testIds=(maximum_test_id,)),
        ) + rows[1:],
        evidenceRows=(
            dataclasses.replace(
                evidence_rows[0], testIds=(maximum_test_id,)
            ),
        ) + evidence_rows[1:],
    )
    assert len(maximum_test_id.encode("ascii")) == 127
    assert module._validate_subject(maximum_test_id_subject) is None

    missing_dependency_row = dataclasses.replace(
        subject,
        taskRows=rows[1:],
        evidenceRows=evidence_rows[1:],
        documents=(documents[3], documents[4]),
    )
    extra_unreachable_row = dataclasses.replace(
        subject,
        rootTaskId="TASK-D0-02",
    )
    cyclic_subject = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(rows[0], dependencies=("TASK-D0-04",)),
        ) + rows[1:],
    )
    owner_isolation_rows = (
        dataclasses.replace(rows[0], testIds=("TST-DOC-001",)),
        dataclasses.replace(rows[1], testIds=("TST-DOC-001",)),
    ) + rows[2:]
    owner_isolation_evidence = (
        dataclasses.replace(evidence_rows[0], testIds=("TST-DOC-001",)),
        dataclasses.replace(evidence_rows[1], testIds=("TST-DOC-001",)),
    ) + evidence_rows[2:]
    owner_isolation_subject = dataclasses.replace(
        subject,
        taskRows=owner_isolation_rows,
        evidenceRows=owner_isolation_evidence,
    )
    assert module._validate_subject(owner_isolation_subject) is None
    wrong_evidence_task = dataclasses.replace(
        owner_isolation_subject,
        evidenceRows=(
            dataclasses.replace(
                owner_isolation_evidence[0],
                taskId="TASK-D0-02",
            ),
            dataclasses.replace(
                owner_isolation_evidence[1],
                taskId="TASK-D0-01",
            ),
        ) + owner_isolation_evidence[2:],
    )
    wrong_evidence_test_union = dataclasses.replace(
        subject,
        evidenceRows=(
            dataclasses.replace(
                evidence_rows[0], testIds=evidence_rows[1].testIds
            ),
            dataclasses.replace(
                evidence_rows[1], testIds=evidence_rows[0].testIds
            ),
        ) + evidence_rows[2:],
    )
    missing_only_evidence_test = dataclasses.replace(
        subject,
        evidenceRows=evidence_rows[:3] + (
            dataclasses.replace(
                evidence_rows[3], testIds=("TST-HOST-001",)
            ),
        ) + evidence_rows[4:],
    )
    extra_only_evidence_test = dataclasses.replace(
        subject,
        evidenceRows=evidence_rows[:3] + (
            dataclasses.replace(
                evidence_rows[3],
                testIds=(
                    "TST-HOST-001",
                    "TST-TOOL-001",
                    "TST-UNRELATED-001",
                ),
            ),
        ) + evidence_rows[4:],
    )
    malformed_evidence_test_id = dataclasses.replace(
        subject,
        evidenceRows=(
            dataclasses.replace(evidence_rows[0], testIds=("not-a-test-id",)),
        ) + evidence_rows[1:],
    )
    matched_malformed_test_id = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(rows[0], testIds=("not-a-test-id",)),
        ) + rows[1:],
        evidenceRows=(
            dataclasses.replace(evidence_rows[0], testIds=("not-a-test-id",)),
        ) + evidence_rows[1:],
    )
    overlong_test_id = "TST-" + "A" * 124
    matched_overlong_test_id = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(rows[0], testIds=(overlong_test_id,)),
        ) + rows[1:],
        evidenceRows=(
            dataclasses.replace(evidence_rows[0], testIds=(overlong_test_id,)),
        ) + evidence_rows[1:],
    )
    assert len(overlong_test_id.encode("ascii")) == 128
    impossible_evidence_date = "EV-20260230-0001"
    impossible_evidence_date_subject = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(
                rows[0], evidenceIds=(impossible_evidence_date,)
            ),
        ) + rows[1:],
        evidenceRows=(
            dataclasses.replace(
                evidence_rows[0], id=impossible_evidence_date
            ),
        ) + evidence_rows[1:],
    )
    missing_phase4_document = dataclasses.replace(
        subject,
        documents=tuple(
            document for document in documents if document.id != "PHASE-4"
        ),
    )
    missing_phase5_document = dataclasses.replace(
        subject,
        documents=tuple(
            document for document in documents if document.id != "PHASE-5"
        ),
    )
    missing_prerequisite_document = dataclasses.replace(
        subject,
        documents=documents[1:],
    )
    extra_document = module.BootstrapDocumentSnapshotV1(
        id="PHASE-6",
        path="docs/06-phase-6.md",
        bytes=b"---\nid: PHASE-6\nstatus: accepted\n---\n",
    )
    extra_document_subject = dataclasses.replace(
        subject,
        documents=documents + (extra_document,),
    )
    same_count_wrong_documents = dataclasses.replace(
        subject,
        documents=documents[1:] + (extra_document,),
    )
    invalid_utf8_subject = dataclasses.replace(
        subject,
        documents=(
            dataclasses.replace(documents[0], bytes=b"\xff"),
        ) + documents[1:],
    )
    malformed_document_id = "0/invalid"
    malformed_document_id_subject = dataclasses.replace(
        subject,
        taskRows=(
            dataclasses.replace(
                rows[0],
                prerequisites=(
                    {
                        "documentId": malformed_document_id,
                        "requiredStatus": "accepted",
                    },
                    {"documentId": "PHASE-2", "requiredStatus": "accepted"},
                    {"documentId": "PHASE-3", "requiredStatus": "accepted"},
                ),
            ),
        ) + rows[1:],
        documents=(
            dataclasses.replace(documents[0], id=malformed_document_id),
        ) + documents[1:],
    )
    generic_task_row = dataclasses.replace(
        rows[0],
        taskId="TASK-UNRELATED-01",
        prerequisites=(),
    )
    generic_task_subject = dataclasses.replace(
        subject,
        rootTaskId="TASK-UNRELATED-01",
        taskRows=(generic_task_row,),
        evidenceRows=(dataclasses.replace(
            evidence_rows[0], taskId="TASK-UNRELATED-01"
        ),),
        documents=(documents[3], documents[4]),
    )
    out_of_domain_dependency_row = dataclasses.replace(
        rows[0],
        taskId="TASK-D0-07",
        prerequisites=(),
        evidenceIds=("EV-20260717-0005",),
    )
    out_of_domain_dependency_subject = dataclasses.replace(
        subject,
        rootTaskId="TASK-D0-02",
        taskRows=(
            dataclasses.replace(
                rows[1], dependencies=("TASK-D0-07",)
            ),
            out_of_domain_dependency_row,
        ),
        evidenceRows=(
            evidence_rows[1],
            module.BootstrapLedgerSubjectV1(
                id="EV-20260717-0005",
                taskId="TASK-D0-07",
                testIds=rows[0].testIds,
                grade="bootstrap",
                result="passed",
            ),
        ),
        documents=(documents[3], documents[4]),
    )
    self_cycle_subject = dataclasses.replace(
        subject,
        rootTaskId="TASK-D0-01",
        taskRows=(dataclasses.replace(
            rows[0], dependencies=("TASK-D0-01",)
        ),),
        evidenceRows=(evidence_rows[0],),
        documents=documents,
    )
    missing_evidence_row_subject = dataclasses.replace(
        subject,
        evidenceRows=evidence_rows[:2] + (
            dataclasses.replace(
                evidence_rows[2],
                testIds=(
                    "TST-EVIDENCE-001",
                    "TST-HOST-001",
                    "TST-TOOL-001",
                ),
            ),
        ) + evidence_rows[4:],
    )
    extra_evidence_row = module.BootstrapLedgerSubjectV1(
        id="EV-20260717-0008",
        taskId="TASK-D0-03",
        testIds=("TST-TOOL-001",),
        grade="bootstrap",
        result="passed",
    )
    extra_evidence_row_subject = dataclasses.replace(
        subject,
        evidenceRows=evidence_rows + (extra_evidence_row,),
    )
    casefold_path_subject = dataclasses.replace(
        subject,
        documents=(
            dataclasses.replace(documents[0], path="docs/Straße.md"),
            dataclasses.replace(documents[1], path="docs/STRASSE.md"),
        ) + documents[2:],
    )

    invalid_subjects = (
        ("generic non-D0 task identity", generic_task_subject),
        ("D0-prefix task outside exact bootstrap set", out_of_domain_dependency_subject),
        ("missing transitive dependency row", missing_dependency_row),
        ("extra unreachable task row", extra_unreachable_row),
        ("task self dependency", self_cycle_subject),
        ("task dependency cycle", cyclic_subject),
        ("evidence row task mismatch", wrong_evidence_task),
        ("per-task evidence test union mismatch", wrong_evidence_test_union),
        ("per-task evidence test union missing member", missing_only_evidence_test),
        ("per-task evidence test union extra member", extra_only_evidence_test),
        ("malformed evidence test ID", malformed_evidence_test_id),
        ("matched malformed task/evidence test ID", matched_malformed_test_id),
        ("matched overlong task/evidence test ID", matched_overlong_test_id),
        ("impossible Gregorian evidence date", impossible_evidence_date_subject),
        ("missing exact evidence row", missing_evidence_row_subject),
        ("extra unreferenced evidence row", extra_evidence_row_subject),
        ("missing PHASE-4 document", missing_phase4_document),
        ("missing PHASE-5 document", missing_phase5_document),
        ("missing prerequisite document", missing_prerequisite_document),
        ("extra unreferenced document", extra_document_subject),
        ("same-count wrong document set", same_count_wrong_documents),
        ("document bytes are not strict UTF-8", invalid_utf8_subject),
        ("malformed prerequisite document ID", malformed_document_id_subject),
        ("casefold-colliding document paths", casefold_path_subject),
    )
    for label, invalid_subject in invalid_subjects:
        try:
            assert_rejected(
                module,
                lambda invalid_subject=invalid_subject: (
                    module._validate_subject(invalid_subject)
                ),
            )
        except AssertionError as error:
            raise AssertionError(f"{label}: {error}") from error

    shell_objects = module.BootstrapTaskObjectSetV1(
        authorityPolicyBytes=b"{}",
        stage0HandoffBytes=b"{}",
        requiredTestSetBytes=b"{}",
        taskApprovalBytes=b"{}",
        taskReceiptBytes=b"{}",
        evidenceManifestBytes=b"{}",
        dependencyObjects=tuple(
            module.DependencyTaskObjectV1(
                approvalBytes=module.canonical_pf_jcs({"taskId": task_id}),
                receiptBytes=module.canonical_pf_jcs({"taskId": task_id}),
                stage0HandoffBytes=module.canonical_pf_jcs({"taskId": task_id}),
                evidenceManifestBytes=module.canonical_pf_jcs({"taskId": task_id}),
            )
            for task_id in (
                "TASK-D0-01",
                "TASK-D0-02",
                "TASK-D0-03",
                "TASK-D0-05",
                "TASK-D0-06",
            )
        ),
        evidenceObjectBytes=tuple(
            module.canonical_pf_jcs({"id": index})
            for index in range(1, 8)
        ),
        reviewReports=(review_report_object(module, b"review"),),
    )
    original_graph_parser = module._parse_bootstrap_task_object_graph
    original_object_shell_validator = module._validate_object_shell
    events: list[str] = []
    shell_arguments: list[object] = []

    def capture_object_shell(objects: object) -> None:
        events.append("shell")
        shell_arguments.append(objects)
        original_object_shell_validator(objects)

    def capture_graph_parser(
        captured_subject: object,
        captured_objects: object,
    ) -> object:
        del captured_subject
        module._validate_object_shell(captured_objects)
        events.append("graph")
        return object()

    module._parse_bootstrap_task_object_graph = capture_graph_parser
    module._validate_object_shell = capture_object_shell
    try:
        result = module.verifyBootstrapTaskObjects(subject, shell_objects)
        assert isinstance(result, module.Rejected)
        assert events == ["shell", "graph"], (
            "valid subject graph must validate the object shell before "
            "object graph work"
        )
        assert shell_arguments == [shell_objects], (
            "object shell validation must receive the caller's exact object set"
        )
        events.clear()
        shell_arguments.clear()
        malformed_shell = dataclasses.replace(
            shell_objects,
            authorityPolicyBytes=b"",
        )
        result = module.verifyBootstrapTaskObjects(subject, malformed_shell)
        assert isinstance(result, module.Rejected)
        assert events == ["shell"], (
            "malformed object shell must reject before object graph work"
        )
        assert shell_arguments == [malformed_shell]
        shell_invalid_subjects = (
            ("generic non-D0 task identity", generic_task_subject),
        )
        for label, invalid_subject in shell_invalid_subjects:
            events.clear()
            shell_arguments.clear()
            result = module.verifyBootstrapTaskObjects(
                invalid_subject,
                shell_objects,
            )
            assert isinstance(result, module.Rejected)
            assert events == [], (
                f"{label} must reject in the typed subject shell before "
                "object or signature work"
            )
            assert shell_arguments == []
    finally:
        module._parse_bootstrap_task_object_graph = original_graph_parser
        module._validate_object_shell = original_object_shell_validator


def test_phase4_graph_authority_join(module: ModuleType) -> None:
    root_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-01")

    class EqualityGadget:
        def __hash__(self) -> int:
            return hash("documentId")

        def __eq__(self, other: object) -> bool:
            del other
            raise AssertionError("subject shell reached prerequisite equality gadget")

    gadget_row = dataclasses.replace(
        root_fixture["subject"].taskRows[0],
        prerequisites=(
            {EqualityGadget(): "PHASE-1", "requiredStatus": "accepted"},
        ),
    )
    gadget_subject = dataclasses.replace(
        root_fixture["subject"],
        taskRows=(gadget_row,),
    )
    assert_rejected(
        module,
        lambda: module._validate_subject_shell(gadget_subject),
    )
    assert isinstance(
        module.verifyBootstrapTaskObjects(
            gadget_subject,
            root_fixture["objects"],
        ),
        module.Rejected,
    )

    root_graph = module._parse_bootstrap_task_object_graph(
        root_fixture["subject"],
        root_fixture["objects"],
    )
    assert root_graph.root.approval.taskId == "TASK-D0-01"
    assert root_graph.dependencies == ()

    full_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-04")
    full_graph = module._parse_bootstrap_task_object_graph(
        full_fixture["subject"],
        full_fixture["objects"],
    )
    assert tuple(
        dependency.approval.taskId for dependency in full_graph.dependencies
    ) == full_fixture["dependencyTaskIds"]
    assert "TASK-D0-07" not in full_fixture["dependencyTaskIds"]

    phase4_snapshot = root_fixture["phase4Snapshot"]
    old_description = b"fixture for TASK-D0-01"
    new_description = b"changed fixture for TASK-D0-01"
    assert phase4_snapshot.bytes.count(old_description) == 1
    changed_phase4 = dataclasses.replace(
        phase4_snapshot,
        bytes=phase4_snapshot.bytes.replace(
            old_description,
            new_description,
            1,
        ),
    )
    changed_subject = dataclasses.replace(
        root_fixture["subject"],
        documents=tuple(
            changed_phase4 if document.id == "PHASE-4" else document
            for document in root_fixture["subject"].documents
        ),
    )
    def assert_join_rejected_before_curves(
        label: str,
        invalid_subject: object,
        invalid_objects: object,
    ) -> None:
        original_verify_ed25519 = module.verify_ed25519
        curve_calls = 0
        finalizer_names = (
            "_finalize_required_test_set",
            "_finalize_task_approval",
            "_finalize_bootstrap_task_verifier_receipt",
        )
        original_finalizers = {
            name: getattr(module, name) for name in finalizer_names
        }
        finalizer_calls = {name: 0 for name in finalizer_names}

        def count_curve_calls(*args: object, **kwargs: object) -> bool:
            nonlocal curve_calls
            curve_calls += 1
            return original_verify_ed25519(*args, **kwargs)

        module.verify_ed25519 = count_curve_calls
        for name in finalizer_names:
            original_finalizer = original_finalizers[name]

            def count_finalizer_calls(
                *args: object,
                _name: str = name,
                _original: Callable = original_finalizer,
                **kwargs: object,
            ) -> object:
                finalizer_calls[_name] += 1
                return _original(*args, **kwargs)

            setattr(module, name, count_finalizer_calls)
        try:
            assert_rejected(
                module,
                lambda: module._parse_bootstrap_task_object_graph(
                    invalid_subject,
                    invalid_objects,
                ),
            )
        finally:
            module.verify_ed25519 = original_verify_ed25519
            for name, original_finalizer in original_finalizers.items():
                setattr(module, name, original_finalizer)
        assert curve_calls == 0, (
            f"{label} must reject before every signature curve"
        )
        assert not any(finalizer_calls.values()), (
            f"{label} must reject before every signed-object finalizer"
        )

    assert_join_rejected_before_curves(
        "PHASE-4 raw digest mismatch",
        changed_subject,
        root_fixture["objects"],
    )

    changed_closure_snapshot = make_phase4_snapshot(
        module,
        row_overrides={"TASK-D0-02": {"dependencies": ()}},
    )
    closure_fixture = signed_d0_object_graph_fixture(
        module,
        "TASK-D0-02",
        phase4_snapshot_override=changed_closure_snapshot,
    )
    assert_join_rejected_before_curves(
        "raw-derived closure substitution",
        closure_fixture["subject"],
        closure_fixture["objects"],
    )

    root_row = root_fixture["subject"].taskRows[0]
    root_evidence = root_fixture["subject"].evidenceRows[0]
    substituted_tests_subject = dataclasses.replace(
        root_fixture["subject"],
        taskRows=(dataclasses.replace(
            root_row,
            testIds=("TST-DOC-999",),
        ),),
        evidenceRows=(dataclasses.replace(
            root_evidence,
            testIds=("TST-DOC-999",),
        ),),
    )
    assert module._validate_subject(substituted_tests_subject) is None
    assert_join_rejected_before_curves(
        "same-cardinality subject test substitution",
        substituted_tests_subject,
        root_fixture["objects"],
    )

    substituted_evidence_id = "EV-20260717-0099"
    substituted_evidence_subject = dataclasses.replace(
        root_fixture["subject"],
        taskRows=(dataclasses.replace(
            root_row,
            evidenceIds=(substituted_evidence_id,),
        ),),
        evidenceRows=(dataclasses.replace(
            root_evidence,
            id=substituted_evidence_id,
        ),),
    )
    assert module._validate_subject(substituted_evidence_subject) is None
    assert_join_rejected_before_curves(
        "same-cardinality subject evidence substitution",
        substituted_evidence_subject,
        root_fixture["objects"],
    )

    dependency_rows = tuple(
        dataclasses.replace(
            row,
            dependencies=(
                "TASK-D0-01",
                "TASK-D0-03",
                "TASK-D0-05",
                "TASK-D0-06",
            ),
        ) if row.taskId == "TASK-D0-04" else row
        for row in full_fixture["subject"].taskRows
    )
    substituted_dependency_subject = dataclasses.replace(
        full_fixture["subject"],
        taskRows=dependency_rows,
    )
    assert module._validate_subject(substituted_dependency_subject) is None
    assert_join_rejected_before_curves(
        "same-cardinality subject dependency substitution",
        substituted_dependency_subject,
        full_fixture["objects"],
    )

    substituted_prerequisites = (
        {"documentId": "PHASE-0", "requiredStatus": "accepted"},
    ) + root_row.prerequisites[1:]
    substituted_prerequisite_subject = dataclasses.replace(
        root_fixture["subject"],
        taskRows=(dataclasses.replace(
            root_row,
            prerequisites=substituted_prerequisites,
        ),),
        documents=tuple(
            dataclasses.replace(
                document,
                id="PHASE-0",
                path="docs/00-prerequisite-substitute.md",
            ) if document.id == "PHASE-1" else document
            for document in root_fixture["subject"].documents
        ),
    )
    assert module._validate_subject(substituted_prerequisite_subject) is None
    assert_join_rejected_before_curves(
        "same-cardinality subject prerequisite substitution",
        substituted_prerequisite_subject,
        root_fixture["objects"],
    )

    reordered_subject = dataclasses.replace(
        full_fixture["subject"],
        taskRows=tuple(reversed(full_fixture["subject"].taskRows)),
    )
    assert_join_rejected_before_curves(
        "subject task-row reorder",
        reordered_subject,
        full_fixture["objects"],
    )
    sparse_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-02")
    missing_raw_closure_row_subject = dataclasses.replace(
        sparse_fixture["subject"],
        taskRows=(sparse_fixture["subject"].taskRows[-1],),
    )
    assert_join_rejected_before_curves(
        "subject missing raw closure row",
        missing_raw_closure_row_subject,
        sparse_fixture["objects"],
    )
    extra_task_row = next(
        row for row in full_fixture["subject"].taskRows
        if row.taskId == "TASK-D0-03"
    )
    extra_evidence_rows = tuple(
        row for row in full_fixture["subject"].evidenceRows
        if row.taskId == "TASK-D0-03"
    )
    extra_raw_closure_row_subject = dataclasses.replace(
        sparse_fixture["subject"],
        taskRows=sparse_fixture["subject"].taskRows + (extra_task_row,),
        evidenceRows=(
            sparse_fixture["subject"].evidenceRows + extra_evidence_rows
        ),
    )
    assert_join_rejected_before_curves(
        "subject extra raw closure row",
        extra_raw_closure_row_subject,
        sparse_fixture["objects"],
    )

    task_breakdown_substitutions = (
        ("id", "PHASE-3"),
        ("contentDigest", digest_text(bytes(32))),
        ("status", "proposed"),
        ("reviewCommit", "b" * 40),
        ("reviewLink", "https://review.example/substituted-phase-4"),
        ("approvedAt", "2026-07-15"),
        ("approvers", ["principal-architecture", "principal-quality"]),
    )
    for field, replacement in task_breakdown_substitutions:
        def mutate_root_breakdown(
            statement: dict,
            _field: str = field,
            _replacement: object = replacement,
        ) -> None:
            statement["taskBreakdown"][_field] = copy.deepcopy(_replacement)

        wrong_root_breakdown = signed_d0_object_graph_fixture(
            module,
            "TASK-D0-01",
            approval_mutators={"TASK-D0-01": mutate_root_breakdown},
        )
        assert_join_rejected_before_curves(
            f"re-signed root taskBreakdown {field} substitution",
            wrong_root_breakdown["subject"],
            wrong_root_breakdown["objects"],
        )

    for dependency_task_id in full_fixture["dependencyTaskIds"]:
        for field, replacement in task_breakdown_substitutions:
            def mutate_dependency_breakdown(
                statement: dict,
                _field: str = field,
                _replacement: object = replacement,
            ) -> None:
                statement["taskBreakdown"][_field] = copy.deepcopy(_replacement)

            wrong_dependency_breakdown = signed_d0_object_graph_fixture(
                module,
                "TASK-D0-04",
                approval_mutators={
                    dependency_task_id: mutate_dependency_breakdown,
                },
            )
            assert_join_rejected_before_curves(
                f"re-signed {dependency_task_id} taskBreakdown {field} substitution",
                wrong_dependency_breakdown["subject"],
                wrong_dependency_breakdown["objects"],
            )

    def mutate_approval_test_axis(statement: dict) -> None:
        statement["testIds"] = ["TST-ISO-001"]

    def mutate_approval_evidence_axis(statement: dict) -> None:
        statement["evidence"][0]["id"] = "EV-20260717-0099"

    for label, mutator in (
        ("test", mutate_approval_test_axis),
        ("evidence", mutate_approval_evidence_axis),
    ):
        wrong_approval_axis = signed_d0_object_graph_fixture(
            module,
            "TASK-D0-01",
            approval_mutators={"TASK-D0-01": mutator},
        )
        assert_join_rejected_before_curves(
            f"re-signed approval {label}-axis substitution",
            wrong_approval_axis["subject"],
            wrong_approval_axis["objects"],
        )

    def mutate_dependency_axis(statement: dict) -> None:
        statement["dependencyCompletions"][0]["taskId"] = "TASK-D0-01"

    wrong_dependency_axis = signed_d0_object_graph_fixture(
        module,
        "TASK-D0-04",
        approval_mutators={"TASK-D0-04": mutate_dependency_axis},
    )
    assert_join_rejected_before_curves(
        "re-signed approval dependency-axis substitution",
        wrong_dependency_axis["subject"],
        wrong_dependency_axis["objects"],
    )

    dependency_test_substitutions = {
        "TASK-D0-01": ["TST-ISO-001"],
        "TASK-D0-02": ["TST-DOC-001"],
        "TASK-D0-03": [
            "TST-COMMON-001",
            "TST-DOC-001",
            "TST-ISO-001",
        ],
        "TASK-D0-05": ["TST-COMMON-001"],
        "TASK-D0-06": ["TST-DOC-001"],
    }
    for dependency_task_id in full_fixture["dependencyTaskIds"]:
        alternative_tests = dependency_test_substitutions[dependency_task_id]

        def mutate_dependency_test_axis(
            statement: dict,
            _alternative_tests: list[str] = alternative_tests,
        ) -> None:
            statement["testIds"] = copy.deepcopy(_alternative_tests)

        def mutate_dependency_evidence_axis(statement: dict) -> None:
            replacement_ids = (
                ["EV-20260717-0098", "EV-20260717-0099"]
                if len(statement["evidence"]) == 2
                else ["EV-20260717-0099"]
            )
            for evidence, replacement_id in zip(
                statement["evidence"], replacement_ids
            ):
                evidence["id"] = replacement_id

        for label, mutator in (
            ("test", mutate_dependency_test_axis),
            ("evidence", mutate_dependency_evidence_axis),
        ):
            wrong_dependency_approval_axis = signed_d0_object_graph_fixture(
                module,
                "TASK-D0-04",
                approval_mutators={dependency_task_id: mutator},
            )
            assert_join_rejected_before_curves(
                f"re-signed {dependency_task_id} approval {label}-axis substitution",
                wrong_dependency_approval_axis["subject"],
                wrong_dependency_approval_axis["objects"],
            )

    dependency_axis_substitutions = {
        "TASK-D0-02": ("TASK-D0-03",),
        "TASK-D0-03": ("TASK-D0-05", "TASK-D0-06"),
        "TASK-D0-05": ("TASK-D0-06",),
        "TASK-D0-06": ("TASK-D0-03", "TASK-D0-05"),
    }
    for dependency_task_id, replacement_task_ids in (
        dependency_axis_substitutions.items()
    ):
        def mutate_dependency_dependencies_axis(
            statement: dict,
            _replacement_task_ids: tuple[str, ...] = replacement_task_ids,
        ) -> None:
            for completion, replacement_task_id in zip(
                statement["dependencyCompletions"],
                _replacement_task_ids,
            ):
                completion["taskId"] = replacement_task_id

        wrong_dependency_axis = signed_d0_object_graph_fixture(
            module,
            "TASK-D0-04",
            approval_mutators={
                dependency_task_id: mutate_dependency_dependencies_axis,
            },
        )
        assert_join_rejected_before_curves(
            f"re-signed {dependency_task_id} dependency-axis substitution",
            wrong_dependency_axis["subject"],
            wrong_dependency_axis["objects"],
        )

    prerequisite_ref_substitutions = (
        ("contentDigest", digest_text(bytes(32))),
        ("status", "proposed"),
        ("reviewCommit", "b" * 40),
        ("reviewLink", "https://review.example/substituted-prerequisite"),
        ("approvedAt", "2026-07-15"),
        ("approvers", ["principal-architecture", "principal-security"]),
    )
    prerequisite_id_substitutions = {
        "PHASE-1": "PHASE-0",
        "PHASE-2": "PHASE-2A",
        "PHASE-3": "PHASE-3A",
    }
    for graph_root, approval_task_id, approval_role in (
        ("TASK-D0-01", "TASK-D0-01", "root"),
        ("TASK-D0-04", "TASK-D0-01", "dependency"),
    ):
        for prerequisite_index, document_id in enumerate(
            ("PHASE-1", "PHASE-2", "PHASE-3")
        ):
            substitutions = (
                ("id", prerequisite_id_substitutions[document_id]),
            ) + prerequisite_ref_substitutions
            for field, replacement in substitutions:
                def mutate_prerequisite_full_ref(
                    statement: dict,
                    _index: int = prerequisite_index,
                    _field: str = field,
                    _replacement: object = replacement,
                ) -> None:
                    statement["prerequisiteDocuments"][_index][
                        _field
                    ] = copy.deepcopy(_replacement)

                wrong_prerequisite_ref = signed_d0_object_graph_fixture(
                    module,
                    graph_root,
                    approval_mutators={
                        approval_task_id: mutate_prerequisite_full_ref,
                    },
                )
                assert_join_rejected_before_curves(
                    f"re-signed {approval_role} {document_id} prerequisite {field} substitution",
                    wrong_prerequisite_ref["subject"],
                    wrong_prerequisite_ref["objects"],
                )

    class ForgedPrerequisiteSnapshot(module.BootstrapDocumentSnapshotV1):
        pass

    for document_id in ("PHASE-1", "PHASE-2", "PHASE-3"):
        snapshot = root_fixture["documentSnapshots"][document_id]
        body = f"Synthetic accepted authority fixture for {document_id}.".encode()
        assert snapshot.bytes.count(body) == 1
        changed_snapshot = dataclasses.replace(
            snapshot,
            bytes=snapshot.bytes.replace(
                body,
                f"Changed accepted authority fixture for {document_id}.".encode(),
                1,
            ),
        )
        changed_subject = dataclasses.replace(
            root_fixture["subject"],
            documents=tuple(
                changed_snapshot if document.id == document_id else document
                for document in root_fixture["subject"].documents
            ),
        )
        assert_join_rejected_before_curves(
            f"{document_id} raw-byte/domain substitution",
            changed_subject,
            root_fixture["objects"],
        )

        wrong_path_subject = dataclasses.replace(
            root_fixture["subject"],
            documents=tuple(
                dataclasses.replace(
                    document,
                    path=f"docs/{document_id.lower()}-substitute.md",
                ) if document.id == document_id else document
                for document in root_fixture["subject"].documents
            ),
        )
        assert_join_rejected_before_curves(
            f"{document_id} canonical-path substitution",
            wrong_path_subject,
            root_fixture["objects"],
        )

        assert snapshot.bytes.count(b"status: accepted") == 1
        wrong_frontmatter = dataclasses.replace(
            snapshot,
            bytes=snapshot.bytes.replace(
                b"status: accepted",
                b"status: proposed",
                1,
            ),
        )
        wrong_frontmatter_fixture = signed_d0_object_graph_fixture(
            module,
            "TASK-D0-01",
            prerequisite_snapshot_overrides={
                document_id: wrong_frontmatter,
            },
        )
        assert_join_rejected_before_curves(
            f"{document_id} re-signed accepted-frontmatter substitution",
            wrong_frontmatter_fixture["subject"],
            wrong_frontmatter_fixture["objects"],
        )

        forged_snapshot = ForgedPrerequisiteSnapshot(
            snapshot.id,
            snapshot.path,
            snapshot.bytes,
        )
        forged_type_subject = dataclasses.replace(
            root_fixture["subject"],
            documents=tuple(
                forged_snapshot if document.id == document_id else document
                for document in root_fixture["subject"].documents
            ),
        )
        assert_join_rejected_before_curves(
            f"{document_id} snapshot subtype substitution",
            forged_type_subject,
            root_fixture["objects"],
        )

    parse_calls = 0
    original_parse_phase4 = module.parse_phase4_snapshot_content

    def count_phase4_parse(snapshot: object) -> object:
        nonlocal parse_calls
        parse_calls += 1
        return original_parse_phase4(snapshot)

    module.parse_phase4_snapshot_content = count_phase4_parse
    try:
        module._parse_bootstrap_task_object_graph(
            root_fixture["subject"],
            root_fixture["objects"],
        )
    finally:
        module.parse_phase4_snapshot_content = original_parse_phase4
    assert parse_calls == 1, (
        "one graph invocation must parse its exact PHASE-4 snapshot once"
    )


def test_dependency_bundle_graph(module: ModuleType) -> None:
    zero_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-01")
    zero_subject = zero_fixture["subject"]
    zero_objects = zero_fixture["objects"]
    assert module._validate_subject(zero_subject) is None
    zero_graph = module._parse_bootstrap_task_object_graph(
        zero_subject,
        zero_objects,
    )
    assert zero_graph.root.approval.taskId == "TASK-D0-01"
    assert zero_graph.dependencies == (), (
        "D0-01 must accept the exact zero-dependency bundle boundary"
    )
    zero_phase5 = next(
        document for document in zero_subject.documents
        if document.id == "PHASE-5"
    )
    public_order_events: list[str] = []
    public_order_hooks = (
        ("_preflight_bootstrap_task_verifier_receipt", "receipt"),
        ("_preflight_task_approval", "approval"),
        ("parse_phase5_snapshot_content", "phase5"),
        ("_preflight_required_test_set", "required"),
        ("_preflight_eligible_stage0_handoff", "handoff"),
    )
    original_public_order_hooks = {
        name: getattr(module, name) for name, _ in public_order_hooks
    }
    for name, event in public_order_hooks:
        original = original_public_order_hooks[name]

        def capture_public_order(
            *args: object,
            _event: str = event,
            _original: Callable = original,
            **kwargs: object,
        ) -> object:
            public_order_events.append(_event)
            return _original(*args, **kwargs)

        setattr(module, name, capture_public_order)
    try:
        module.parse_bootstrap_task_verifier_receipt(
            zero_objects.taskReceiptBytes,
            zero_objects.taskApprovalBytes,
            zero_objects.requiredTestSetBytes,
            zero_objects.authorityPolicyBytes,
            zero_phase5,
            zero_objects.stage0HandoffBytes,
        )
    finally:
        for name, original in original_public_order_hooks.items():
            setattr(module, name, original)
    assert public_order_events == [
        "receipt", "approval", "phase5", "required", "handoff",
    ], "public receipt parser must preserve its frozen cross-input order"

    zero_built = zero_fixture["built"]
    wrong_approval_digest_receipt = copy.deepcopy(
        zero_built["TASK-D0-01"]["receiptWire"]
    )
    wrong_approval_digest_receipt.pop("signature")
    wrong_approval_digest_receipt["taskApproval"]["digest"] = digest_text(
        bytes.fromhex("9e" * 32)
    )
    wrong_approval_digest_receipt_wire, _, _ = (
        sign_bootstrap_task_receipt_statement(
            module,
            wrong_approval_digest_receipt,
        )
    )
    wrong_approval_digest_objects = dataclasses.replace(
        zero_objects,
        taskReceiptBytes=module.canonical_pf_jcs(
            wrong_approval_digest_receipt_wire
        ),
    )
    original_verify_ed25519 = module.verify_ed25519
    signature_messages: list[bytes] = []

    def capture_signature_messages(
        public_key: bytes,
        message: bytes,
        signature: bytes,
    ) -> bool:
        signature_messages.append(message)
        return original_verify_ed25519(public_key, message, signature)

    module.verify_ed25519 = capture_signature_messages
    try:
        assert_rejected(
            module,
            lambda: module._parse_bootstrap_task_object_graph(
                zero_subject,
                wrong_approval_digest_objects,
            ),
        )
    finally:
        module.verify_ed25519 = original_verify_ed25519
    assert len(signature_messages) == 4, (
        "wrong approval digest must follow RequiredSet and TaskApproval curves"
    )
    assert not any(
        message.startswith(
            b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        )
        for message in signature_messages
    ), "wrong approval digest must reject before receipt signature work"

    full_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-04")
    subject = full_fixture["subject"]
    objects = full_fixture["objects"]
    built = full_fixture["built"]
    dependency_task_ids = full_fixture["dependencyTaskIds"]
    assert dependency_task_ids == (
        "TASK-D0-01",
        "TASK-D0-02",
        "TASK-D0-03",
        "TASK-D0-05",
        "TASK-D0-06",
    )
    assert tuple(
        ref["taskId"]
        for ref in built["TASK-D0-04"]["approvalWire"][
            "dependencyCompletions"
        ]
    ) == (
        "TASK-D0-02",
        "TASK-D0-03",
        "TASK-D0-05",
        "TASK-D0-06",
    ), "D0-04 direct dependency refs must remain distinct from transitive bundles"
    assert module._validate_subject(subject) is None

    original_approval_preflight = module._preflight_task_approval
    original_receipt_preflight = (
        module._preflight_bootstrap_task_verifier_receipt
    )
    original_handoff_preflight = module._preflight_eligible_stage0_handoff
    original_phase4_parser = module.parse_phase4_snapshot_content
    original_phase5_parser = module.parse_phase5_snapshot_content
    original_required_preflight = module._preflight_required_test_set
    original_required_finalize = module._finalize_required_test_set
    original_approval_finalize = module._finalize_task_approval
    original_receipt_finalize = (
        module._finalize_bootstrap_task_verifier_receipt
    )
    preflight_calls = {"approval": [], "receipt": [], "handoff": []}
    preflight_events: list[str] = []
    finalize_events: list[str] = []
    shared_calls = {
        "phase4": 0,
        "phase5": 0,
        "requiredPreflight": 0,
        "requiredFinalize": 0,
    }

    def capture_approval_preflight(encoded: bytes) -> object:
        preflight_events.append("approval")
        preflight_calls["approval"].append(encoded)
        return original_approval_preflight(encoded)

    def capture_receipt_preflight(encoded: bytes) -> object:
        preflight_events.append("receipt")
        preflight_calls["receipt"].append(encoded)
        return original_receipt_preflight(encoded)

    def capture_handoff_preflight(encoded: bytes) -> object:
        preflight_events.append("handoff")
        preflight_calls["handoff"].append(encoded)
        return original_handoff_preflight(encoded)

    def capture_phase5(snapshot: object) -> object:
        preflight_events.append("phase5")
        shared_calls["phase5"] += 1
        return original_phase5_parser(snapshot)

    def capture_phase4(snapshot: object) -> object:
        preflight_events.append("phase4")
        shared_calls["phase4"] += 1
        return original_phase4_parser(snapshot)

    def capture_required_preflight(*args: object, **kwargs: object) -> object:
        preflight_events.append("required")
        shared_calls["requiredPreflight"] += 1
        return original_required_preflight(*args, **kwargs)

    def capture_required_finalize(*args: object, **kwargs: object) -> object:
        shared_calls["requiredFinalize"] += 1
        finalize_events.append("required")
        return original_required_finalize(*args, **kwargs)

    def capture_approval_finalize(*args: object, **kwargs: object) -> object:
        finalize_events.append("approval")
        return original_approval_finalize(*args, **kwargs)

    def capture_receipt_finalize(*args: object, **kwargs: object) -> object:
        finalize_events.append("receipt")
        return original_receipt_finalize(*args, **kwargs)

    module._preflight_task_approval = capture_approval_preflight
    module._preflight_bootstrap_task_verifier_receipt = capture_receipt_preflight
    module._preflight_eligible_stage0_handoff = capture_handoff_preflight
    module.parse_phase4_snapshot_content = capture_phase4
    module.parse_phase5_snapshot_content = capture_phase5
    module._preflight_required_test_set = capture_required_preflight
    module._finalize_required_test_set = capture_required_finalize
    module._finalize_task_approval = capture_approval_finalize
    module._finalize_bootstrap_task_verifier_receipt = capture_receipt_finalize
    try:
        graph = module._parse_bootstrap_task_object_graph(subject, objects)
    finally:
        module._preflight_task_approval = original_approval_preflight
        module._preflight_bootstrap_task_verifier_receipt = (
            original_receipt_preflight
        )
        module._preflight_eligible_stage0_handoff = original_handoff_preflight
        module.parse_phase4_snapshot_content = original_phase4_parser
        module.parse_phase5_snapshot_content = original_phase5_parser
        module._preflight_required_test_set = original_required_preflight
        module._finalize_required_test_set = original_required_finalize
        module._finalize_task_approval = original_approval_finalize
        module._finalize_bootstrap_task_verifier_receipt = (
            original_receipt_finalize
        )
    assert graph.root.approval.taskId == "TASK-D0-04"
    assert tuple(
        dependency.approval.taskId for dependency in graph.dependencies
    ) == dependency_task_ids
    assert tuple(
        dependency.receiptRef.taskId for dependency in graph.dependencies
    ) == dependency_task_ids

    maximum_evidence_carrier = dataclasses.replace(
        objects,
        evidenceObjectBytes=(b"{}",) * (6 * 4096),
    )
    assert module._validate_object_shell(maximum_evidence_carrier) is None
    maximum_evidence_item = b"e" * (4 * 1024 * 1024)
    assert module._validate_object_shell(dataclasses.replace(
        objects,
        evidenceObjectBytes=(maximum_evidence_item,),
    )) is None
    assert_rejected(
        module,
        lambda: module._validate_object_shell(dataclasses.replace(
            objects,
            evidenceObjectBytes=(maximum_evidence_item + b"e",),
        )),
    )
    aggregate_maximum = (maximum_evidence_item,) * 64
    assert module._validate_object_shell(dataclasses.replace(
        objects,
        evidenceObjectBytes=aggregate_maximum,
    )) is None
    assert_rejected(
        module,
        lambda: module._validate_object_shell(dataclasses.replace(
            objects,
            evidenceObjectBytes=aggregate_maximum + (b"e",),
        )),
    )
    assert module._validate_object_shell(dataclasses.replace(
        objects,
        evidenceManifestBytes=maximum_evidence_item,
    )) is None
    assert_rejected(
        module,
        lambda: module._validate_object_shell(dataclasses.replace(
            objects,
            evidenceManifestBytes=maximum_evidence_item + b"e",
        )),
    )
    maximum_count_review_reports = tuple(sorted(
        (
            review_report_object(module, index.to_bytes(2, "big"))
            for index in range(6 * 256)
        ),
        key=lambda report: report.digest.bytes,
    ))
    maximum_review_carrier = dataclasses.replace(
        objects,
        reviewReports=maximum_count_review_reports,
    )
    assert module._validate_object_shell(maximum_review_carrier) is None
    overbound_evidence_carrier = dataclasses.replace(
        objects,
        evidenceObjectBytes=(b"{}",) * (6 * 4096 + 1),
    )
    original_decode = module.decode_canonical_pf_jcs
    overbound_carrier_decode_calls = 0

    def count_overbound_evidence_decode(encoded: bytes) -> object:
        nonlocal overbound_carrier_decode_calls
        overbound_carrier_decode_calls += 1
        return original_decode(encoded)

    module.decode_canonical_pf_jcs = count_overbound_evidence_decode
    try:
        assert_rejected(
            module,
            lambda: module._validate_object_shell(overbound_evidence_carrier),
        )
        assert_rejected(
            module,
            lambda: module._validate_object_shell(dataclasses.replace(
                objects,
                reviewReports=maximum_count_review_reports + (
                    review_report_object(module, (6 * 256).to_bytes(2, "big")),
                ),
            )),
        )
    finally:
        module.decode_canonical_pf_jcs = original_decode
    assert overbound_carrier_decode_calls == 0, (
        "carrier overflow must reject before any evidence entry decode"
    )

    expected_approval_bytes = (objects.taskApprovalBytes,) + tuple(
        bundle.approvalBytes for bundle in objects.dependencyObjects
    )
    expected_receipt_bytes = (objects.taskReceiptBytes,) + tuple(
        bundle.receiptBytes for bundle in objects.dependencyObjects
    )
    expected_handoff_bytes = (objects.stage0HandoffBytes,) + tuple(
        bundle.stage0HandoffBytes for bundle in objects.dependencyObjects
    )
    assert tuple(preflight_calls["approval"]) == expected_approval_bytes
    assert tuple(preflight_calls["receipt"]) == expected_receipt_bytes
    assert tuple(preflight_calls["handoff"]) == expected_handoff_bytes
    assert preflight_events == (
        ["phase4", "phase5"]
        + ["receipt", "approval"] * 6
        + ["required"]
        + ["handoff"] * 6
    ), "graph preflight order must preserve the frozen receipt boundary"
    assert shared_calls == {
        "phase4": 1,
        "phase5": 1,
        "requiredPreflight": 1,
        "requiredFinalize": 1,
    }, "graph must parse/finalize its shared authority inputs exactly once"
    assert finalize_events == (
        ["required"] + ["approval"] * 6 + ["receipt"] * 6
    ), "graph must finalize RequiredSet, then all approvals, then all receipts"
    assert len({id(value) for value in preflight_calls["approval"]}) == 6
    assert len({id(value) for value in preflight_calls["receipt"]}) == 6
    assert len({id(value) for value in preflight_calls["handoff"]}) == 6

    bundles = objects.dependencyObjects
    root_bundle = module.DependencyTaskObjectV1(
        approvalBytes=objects.taskApprovalBytes,
        receiptBytes=objects.taskReceiptBytes,
        stage0HandoffBytes=objects.stage0HandoffBytes,
        evidenceManifestBytes=objects.evidenceManifestBytes,
    )
    overbound_dependency_objects = dataclasses.replace(
        objects,
        dependencyObjects=bundles + (root_bundle,),
    )
    invalid_objects = (
        (
            "evidence object carrier is empty",
            dataclasses.replace(objects, evidenceObjectBytes=()),
        ),
        (
            "review report carrier is empty",
            dataclasses.replace(objects, reviewReports=()),
        ),
        (
            "dependency bundle carrier is not a tuple",
            dataclasses.replace(objects, dependencyObjects=list(bundles)),
        ),
        (
            "dependency bundle entry is untyped",
            dataclasses.replace(
                objects,
                dependencyObjects=({
                    "approvalBytes": bundles[0].approvalBytes,
                    "receiptBytes": bundles[0].receiptBytes,
                    "stage0HandoffBytes": bundles[0].stage0HandoffBytes,
                    "evidenceManifestBytes": bundles[0].evidenceManifestBytes,
                },) + bundles[1:],
            ),
        ),
        (
            "dependency approval bytes are empty",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(bundles[0], approvalBytes=b""),
                ) + bundles[1:],
            ),
        ),
        (
            "dependency receipt bytes are noncanonical",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(
                        bundles[0], receiptBytes=b'{"z":0,"a":0}'
                    ),
                ) + bundles[1:],
            ),
        ),
        (
            "dependency handoff bytes are empty",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(bundles[0], stage0HandoffBytes=b""),
                ) + bundles[1:],
            ),
        ),
        (
            "missing transitive dependency bundle",
            dataclasses.replace(objects, dependencyObjects=bundles[1:]),
        ),
        (
            "sixth extra dependency bundle",
            overbound_dependency_objects,
        ),
        (
            "duplicate dependency bundle",
            dataclasses.replace(
                objects,
                dependencyObjects=(bundles[0], bundles[0]) + bundles[2:],
            ),
        ),
        (
            "reordered dependency bundles",
            dataclasses.replace(
                objects,
                dependencyObjects=(bundles[1], bundles[0]) + bundles[2:],
            ),
        ),
        (
            "approval and receipt from different dependency tasks",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(
                        bundles[0], receiptBytes=bundles[1].receiptBytes
                    ),
                ) + bundles[1:],
            ),
        ),
        (
            "dependency bundle substitutes root handoff",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(
                        bundles[0],
                        stage0HandoffBytes=objects.stage0HandoffBytes,
                    ),
                ) + bundles[1:],
            ),
        ),
        (
            "dependency bundles cross-substitute handoffs",
            dataclasses.replace(
                objects,
                dependencyObjects=(
                    dataclasses.replace(
                        bundles[0],
                        stage0HandoffBytes=bundles[1].stage0HandoffBytes,
                    ),
                    dataclasses.replace(
                        bundles[1],
                        stage0HandoffBytes=bundles[0].stage0HandoffBytes,
                    ),
                ) + bundles[2:],
            ),
        ),
    )

    root_approval = copy.deepcopy(built["TASK-D0-04"]["approvalWire"])
    root_approval.pop("signatures")
    root_approval["dependencyCompletions"] = [
        copy.deepcopy(built[task_id]["receiptRefWire"])
        for task_id in dependency_task_ids
    ]
    root_approval_wire, _, _ = sign_task_approval_statement(
        module,
        root_approval,
        ("key-quality", "key-release", "key-security"),
    )
    root_approval_bytes = module.canonical_pf_jcs(root_approval_wire)
    root_receipt = copy.deepcopy(built["TASK-D0-04"]["receiptWire"])
    root_receipt.pop("signature")
    root_receipt["dependencyCompletions"] = copy.deepcopy(
        root_approval_wire["dependencyCompletions"]
    )
    root_receipt["taskApproval"]["digest"] = digest_text(hashlib.sha256(
        b"pf.bootstrap-task-approval.v1\x00" + root_approval_bytes
    ).digest())
    root_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        root_receipt,
    )
    wrong_direct_dependency_set = dataclasses.replace(
        objects,
        taskApprovalBytes=root_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(root_receipt_wire),
    )
    invalid_objects += ((
        "D0-04 transitive set substituted for direct dependency refs",
        wrong_direct_dependency_set,
    ),)

    sparse_fixture = signed_d0_object_graph_fixture(module, "TASK-D0-02")
    sparse_subject = sparse_fixture["subject"]
    sparse_objects = sparse_fixture["objects"]
    sparse_bundle = sparse_objects.dependencyObjects[0]
    sparse_root = sparse_fixture["built"]["TASK-D0-02"]
    sparse_extra = module.DependencyTaskObjectV1(
        approvalBytes=sparse_root["approvalBytes"],
        receiptBytes=sparse_root["receiptBytes"],
        stage0HandoffBytes=sparse_root["handoffBytes"],
        evidenceManifestBytes=sparse_root["evidenceManifestBytes"],
    )
    isolated_exact_set_invalids = (
        (
            "sparse graph extra bundle below count limit",
            dataclasses.replace(
                sparse_objects,
                dependencyObjects=(sparse_bundle, sparse_extra),
            ),
        ),
        (
            "sparse graph duplicate bundle with exact set preserved",
            dataclasses.replace(
                sparse_objects,
                dependencyObjects=(sparse_bundle, sparse_bundle),
            ),
        ),
    )
    sparse_built = sparse_fixture["built"]
    shared_handoff_bytes = sparse_built["TASK-D0-01"]["handoffBytes"]
    shared_handoff_ref = eligible_stage0_handoff_ref_wire(
        module,
        sparse_built["TASK-D0-01"]["handoffWire"],
        shared_handoff_bytes,
    )
    shared_handoff_approval = copy.deepcopy(
        sparse_built["TASK-D0-02"]["approvalWire"]
    )
    shared_handoff_approval.pop("signatures")
    shared_handoff_approval["stage0Handoff"] = shared_handoff_ref
    shared_handoff_approval_wire, _, _ = sign_task_approval_statement(
        module,
        shared_handoff_approval,
        ("key-architecture", "key-quality"),
    )
    shared_handoff_approval_bytes = module.canonical_pf_jcs(
        shared_handoff_approval_wire
    )
    shared_handoff_receipt = copy.deepcopy(
        sparse_built["TASK-D0-02"]["receiptWire"]
    )
    shared_handoff_receipt.pop("signature")
    shared_handoff_receipt["stage0Handoff"] = shared_handoff_ref
    shared_handoff_receipt["taskApproval"]["digest"] = digest_text(
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00"
            + shared_handoff_approval_bytes
        ).digest()
    )
    shared_handoff_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        shared_handoff_receipt,
    )
    shared_handoff_objects = dataclasses.replace(
        sparse_objects,
        stage0HandoffBytes=shared_handoff_bytes,
        taskApprovalBytes=shared_handoff_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(
            shared_handoff_receipt_wire
        ),
    )
    isolated_exact_set_invalids += ((
        "two tasks fully re-signed to the same run-specific handoff",
        shared_handoff_objects,
    ),)
    reused_run_handoff_wire = copy.deepcopy(
        sparse_built["TASK-D0-01"]["handoffWire"]
    )
    reused_run_handoff_wire["id"] = "task-d0-02-reused-run-handoff"
    reused_run_handoff_bytes = module.canonical_pf_jcs(
        reused_run_handoff_wire
    )
    reused_run_handoff_ref = eligible_stage0_handoff_ref_wire(
        module,
        reused_run_handoff_wire,
        reused_run_handoff_bytes,
    )
    reused_run_approval = copy.deepcopy(
        sparse_built["TASK-D0-02"]["approvalWire"]
    )
    reused_run_approval.pop("signatures")
    reused_run_approval["stage0Handoff"] = reused_run_handoff_ref
    reused_run_approval_wire, _, _ = sign_task_approval_statement(
        module,
        reused_run_approval,
        ("key-architecture", "key-quality"),
    )
    reused_run_approval_bytes = module.canonical_pf_jcs(
        reused_run_approval_wire
    )
    reused_run_receipt = copy.deepcopy(
        sparse_built["TASK-D0-02"]["receiptWire"]
    )
    reused_run_receipt.pop("signature")
    reused_run_receipt["stage0Handoff"] = reused_run_handoff_ref
    reused_run_receipt["taskApproval"]["digest"] = digest_text(
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00"
            + reused_run_approval_bytes
        ).digest()
    )
    reused_run_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        reused_run_receipt,
    )
    reused_run_objects = dataclasses.replace(
        sparse_objects,
        stage0HandoffBytes=reused_run_handoff_bytes,
        taskApprovalBytes=reused_run_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(reused_run_receipt_wire),
    )
    isolated_exact_set_invalids += ((
        "distinct handoff refs reuse the same Stage-0 runId and nonce",
        reused_run_objects,
    ),)

    nested_approval = copy.deepcopy(built["TASK-D0-05"]["approvalWire"])
    nested_approval.pop("signatures")
    nested_approval["dependencyCompletions"] = [
        copy.deepcopy(built[task_id]["receiptRefWire"])
        for task_id in ("TASK-D0-01", "TASK-D0-02", "TASK-D0-03")
    ]
    nested_approval_wire, _, _ = sign_task_approval_statement(
        module,
        nested_approval,
        ("key-quality", "key-security"),
    )
    nested_approval_bytes = module.canonical_pf_jcs(nested_approval_wire)
    nested_receipt = copy.deepcopy(built["TASK-D0-05"]["receiptWire"])
    nested_receipt.pop("signature")
    nested_receipt["dependencyCompletions"] = copy.deepcopy(
        nested_approval_wire["dependencyCompletions"]
    )
    nested_receipt["taskApproval"]["digest"] = digest_text(hashlib.sha256(
        b"pf.bootstrap-task-approval.v1\x00" + nested_approval_bytes
    ).digest())
    nested_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        nested_receipt,
    )
    nested_receipt_bytes = module.canonical_pf_jcs(nested_receipt_wire)
    nested_receipt_ref = bootstrap_task_receipt_ref_wire(
        module,
        "TASK-D0-05",
        nested_receipt_wire["id"],
        nested_receipt_bytes,
    )
    nested_root_approval = copy.deepcopy(
        built["TASK-D0-04"]["approvalWire"]
    )
    nested_root_approval.pop("signatures")
    nested_root_approval["dependencyCompletions"] = [
        nested_receipt_ref if ref["taskId"] == "TASK-D0-05" else ref
        for ref in nested_root_approval["dependencyCompletions"]
    ]
    nested_root_approval_wire, _, _ = sign_task_approval_statement(
        module,
        nested_root_approval,
        ("key-quality", "key-release", "key-security"),
    )
    nested_root_approval_bytes = module.canonical_pf_jcs(
        nested_root_approval_wire
    )
    nested_root_receipt = copy.deepcopy(
        built["TASK-D0-04"]["receiptWire"]
    )
    nested_root_receipt.pop("signature")
    nested_root_receipt["dependencyCompletions"] = copy.deepcopy(
        nested_root_approval_wire["dependencyCompletions"]
    )
    nested_root_receipt["taskApproval"]["digest"] = digest_text(hashlib.sha256(
        b"pf.bootstrap-task-approval.v1\x00" + nested_root_approval_bytes
    ).digest())
    nested_root_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        nested_root_receipt,
    )
    nested_bundles = tuple(
        dataclasses.replace(
            bundle,
            approvalBytes=nested_approval_bytes,
            receiptBytes=nested_receipt_bytes,
        ) if task_id == "TASK-D0-05" else bundle
        for task_id, bundle in zip(dependency_task_ids, bundles)
    )
    nested_wrong_direct_dependency_set = dataclasses.replace(
        objects,
        taskApprovalBytes=nested_root_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(nested_root_receipt_wire),
        dependencyObjects=nested_bundles,
    )
    invalid_objects += ((
        "nested D0-05 transitive refs substituted for its direct dependency",
        nested_wrong_direct_dependency_set,
    ),)

    wrong_digest_root_approval = copy.deepcopy(
        built["TASK-D0-04"]["approvalWire"]
    )
    wrong_digest_root_approval.pop("signatures")
    for completion in wrong_digest_root_approval["dependencyCompletions"]:
        if completion["taskId"] == "TASK-D0-05":
            completion["digest"] = digest_text(bytes.fromhex("9f" * 32))
    wrong_digest_root_approval_wire, _, _ = sign_task_approval_statement(
        module,
        wrong_digest_root_approval,
        ("key-quality", "key-release", "key-security"),
    )
    wrong_digest_root_approval_bytes = module.canonical_pf_jcs(
        wrong_digest_root_approval_wire
    )
    wrong_digest_root_receipt = copy.deepcopy(
        built["TASK-D0-04"]["receiptWire"]
    )
    wrong_digest_root_receipt.pop("signature")
    wrong_digest_root_receipt["dependencyCompletions"] = copy.deepcopy(
        wrong_digest_root_approval_wire["dependencyCompletions"]
    )
    wrong_digest_root_receipt["taskApproval"]["digest"] = digest_text(
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00"
            + wrong_digest_root_approval_bytes
        ).digest()
    )
    wrong_digest_root_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        wrong_digest_root_receipt,
    )
    wrong_dependency_receipt_digest = dataclasses.replace(
        objects,
        taskApprovalBytes=wrong_digest_root_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(
            wrong_digest_root_receipt_wire
        ),
    )

    wrong_id_root_approval = copy.deepcopy(
        built["TASK-D0-04"]["approvalWire"]
    )
    wrong_id_root_approval.pop("signatures")
    for completion in wrong_id_root_approval["dependencyCompletions"]:
        if completion["taskId"] == "TASK-D0-05":
            completion["id"] = "BTV-20260717-9999"
    wrong_id_root_approval_wire, _, _ = sign_task_approval_statement(
        module,
        wrong_id_root_approval,
        ("key-quality", "key-release", "key-security"),
    )
    wrong_id_root_approval_bytes = module.canonical_pf_jcs(
        wrong_id_root_approval_wire
    )
    wrong_id_root_receipt = copy.deepcopy(
        built["TASK-D0-04"]["receiptWire"]
    )
    wrong_id_root_receipt.pop("signature")
    wrong_id_root_receipt["dependencyCompletions"] = copy.deepcopy(
        wrong_id_root_approval_wire["dependencyCompletions"]
    )
    wrong_id_root_receipt["taskApproval"]["digest"] = digest_text(
        hashlib.sha256(
            b"pf.bootstrap-task-approval.v1\x00"
            + wrong_id_root_approval_bytes
        ).digest()
    )
    wrong_id_root_receipt_wire, _, _ = sign_bootstrap_task_receipt_statement(
        module,
        wrong_id_root_receipt,
    )
    wrong_dependency_receipt_id = dataclasses.replace(
        objects,
        taskApprovalBytes=wrong_id_root_approval_bytes,
        taskReceiptBytes=module.canonical_pf_jcs(
            wrong_id_root_receipt_wire
        ),
    )

    original_signed_preflight = module._preflight_bootstrap_task_signed_content
    overbound_preflight_calls = 0

    def count_overbound_preflight(*args: object, **kwargs: object) -> object:
        nonlocal overbound_preflight_calls
        overbound_preflight_calls += 1
        return original_signed_preflight(*args, **kwargs)

    module._preflight_bootstrap_task_signed_content = count_overbound_preflight
    try:
        assert_rejected(
            module,
            lambda: module._parse_bootstrap_task_object_graph(
                subject,
                overbound_dependency_objects,
            ),
        )
    finally:
        module._preflight_bootstrap_task_signed_content = (
            original_signed_preflight
        )
    assert overbound_preflight_calls == 0, (
        "dependency count overflow must reject before any task-object preflight"
    )

    original_verify_ed25519 = module.verify_ed25519
    curve_calls = 0

    def count_curve_calls(*args: object, **kwargs: object) -> bool:
        del args, kwargs
        nonlocal curve_calls
        curve_calls += 1
        return True

    module.verify_ed25519 = count_curve_calls
    for label, invalid in invalid_objects:
        curve_calls = 0
        try:
            assert_rejected(
                module,
                lambda invalid=invalid: module._parse_bootstrap_task_object_graph(
                    subject,
                    invalid,
                ),
            )
            assert curve_calls == 0, (
                f"{label} must reject before signature verification work"
            )
        except AssertionError as error:
            raise AssertionError(f"{label}: {error}") from error
    for label, invalid in isolated_exact_set_invalids:
        curve_calls = 0
        try:
            assert_rejected(
                module,
                lambda invalid=invalid: module._parse_bootstrap_task_object_graph(
                    sparse_subject,
                    invalid,
                ),
            )
            assert curve_calls == 0, (
                f"{label} must reject before signature verification work"
            )
        except AssertionError as error:
            raise AssertionError(f"{label}: {error}") from error
    module.verify_ed25519 = original_verify_ed25519
    assert_rejected(
        module,
        lambda: module._parse_bootstrap_task_object_graph(
            subject,
            wrong_dependency_receipt_digest,
        ),
    )
    assert_rejected(
        module,
        lambda: module._parse_bootstrap_task_object_graph(
            subject,
            wrong_dependency_receipt_id,
        ),
    )

    original_graph_parser = module._parse_bootstrap_task_object_graph
    original_public_receipt_parser = module.parse_bootstrap_task_verifier_receipt
    graph_calls: list[tuple[object, object]] = []

    def capture_graph_parser(
        captured_subject: object,
        captured_objects: object,
    ) -> object:
        graph_calls.append((captured_subject, captured_objects))
        return graph

    module._parse_bootstrap_task_object_graph = capture_graph_parser
    module.parse_bootstrap_task_verifier_receipt = (
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError(
            "object consumer must not reparse the root receipt outside graph"
        ))
    )
    try:
        result = module.verifyBootstrapTaskObjects(subject, objects)
    finally:
        module._parse_bootstrap_task_object_graph = original_graph_parser
        module.parse_bootstrap_task_verifier_receipt = (
            original_public_receipt_parser
        )
    assert type(result) is module.ObjectVerifiedV1
    assert graph_calls == [(subject, objects)], (
        "public consumer must invoke the verified dependency graph exactly once"
    )


def test_review_report_preflight(module: ModuleType) -> None:
    minimum_item = review_report_object(module, b"x")
    assert module._preflight_review_reports((minimum_item,)) == (
        minimum_item.digest,
    )
    opaque_vectors = (
        b"\x00",
        b" \t\r\n ",
        b"\xff",
        b'{"z":0,"a":1}',
        b"e\xcc\x81\r\n ",
    )
    for opaque_raw in opaque_vectors:
        opaque_report = review_report_object(module, opaque_raw)
        assert module._preflight_review_reports((opaque_report,)) == (
            opaque_report.digest,
        ), "review report bytes must remain opaque and digest exact raw bytes"

    maximum_item_raw = b"m" * (1024 * 1024)
    maximum_item = review_report_object(module, maximum_item_raw)
    assert module._preflight_review_reports((maximum_item,)) == (
        maximum_item.digest,
    )
    maximum_count_reports = tuple(sorted(
        (
            review_report_object(module, f"report-{index:04d}".encode("ascii"))
            for index in range(6 * 256)
        ),
        key=lambda report: report.digest.bytes,
    ))
    assert len(maximum_count_reports) == 1536
    assert len(module._preflight_review_reports(maximum_count_reports)) == 1536
    over_count_reports = tuple(sorted(
        maximum_count_reports + (
            review_report_object(module, b"report-over-count"),
        ),
        key=lambda report: report.digest.bytes,
    ))
    assert len(over_count_reports) == 1537

    aggregate_reports = tuple(sorted(
        (
            review_report_object(
                module,
                bytes([index]) + b"a" * (1024 * 1024 - 1),
            )
            for index in range(16)
        ),
        key=lambda report: report.digest.bytes,
    ))
    assert sum(len(report.bytes) for report in aggregate_reports) == 16 * 1024 * 1024
    assert len(module._preflight_review_reports(aggregate_reports)) == 16
    aggregate_overflow = tuple(sorted(
        aggregate_reports + (review_report_object(module, b"z"),),
        key=lambda report: report.digest.bytes,
    ))
    assert sum(
        len(report.bytes) for report in aggregate_overflow
    ) == 16 * 1024 * 1024 + 1

    ordered_pair = tuple(sorted(
        (
            review_report_object(module, b"first"),
            review_report_object(module, b"second"),
        ),
        key=lambda report: report.digest.bytes,
    ))
    assert module._preflight_review_reports(ordered_pair) == tuple(
        report.digest for report in ordered_pair
    ), "preflight must retain the caller's exact digest order"

    class TupleSubclass(tuple):
        pass

    class ReviewReportSubclass(module.ReviewReportObjectV1):
        pass

    class DigestSubclass(module.Digest):
        pass

    class BytesSubclass(bytes):
        pass

    class StrSubclass(str):
        pass

    duplicate_digest = module.Digest("sha256", bytes(32))
    structural_invalids = (
        ("outer carrier is list", list(ordered_pair)),
        ("outer carrier is tuple subclass", TupleSubclass(ordered_pair)),
        ("outer carrier is empty", ()),
        ("entry is dict", ({"digest": ordered_pair[0].digest, "bytes": b"x"},)),
        (
            "late invalid entry follows a structurally valid report",
            (
                ordered_pair[0],
                {"digest": module.Digest("sha256", b"\xff" * 32), "bytes": b"x"},
            ),
        ),
        (
            "entry is ReviewReportObjectV1 subclass",
            (ReviewReportSubclass(
                digest=ordered_pair[0].digest,
                bytes=ordered_pair[0].bytes,
            ),),
        ),
        (
            "digest is untyped",
            (module.ReviewReportObjectV1(
                digest=digest_text(bytes(32)),
                bytes=b"x",
            ),),
        ),
        (
            "digest is Digest subclass",
            (module.ReviewReportObjectV1(
                digest=DigestSubclass("sha256", bytes(32)),
                bytes=b"x",
            ),),
        ),
        (
            "digest algorithm is str subclass",
            (module.ReviewReportObjectV1(
                digest=module.Digest(StrSubclass("sha256"), bytes(32)),
                bytes=b"x",
            ),),
        ),
        (
            "digest algorithm is not sha256",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha512", bytes(32)),
                bytes=b"x",
            ),),
        ),
        (
            "digest bytes are str",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", "00" * 32),
                bytes=b"x",
            ),),
        ),
        (
            "digest bytes are bytearray",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytearray(32)),
                bytes=b"x",
            ),),
        ),
        (
            "digest bytes are memoryview",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", memoryview(bytes(32))),
                bytes=b"x",
            ),),
        ),
        (
            "digest bytes are bytes subclass",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", BytesSubclass(bytes(32))),
                bytes=b"x",
            ),),
        ),
        (
            "digest length is not 32 bytes",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(31)),
                bytes=b"x",
            ),),
        ),
        (
            "bytes field is str",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes="x",
            ),),
        ),
        (
            "bytes field is bytearray",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes=bytearray(b"x"),
            ),),
        ),
        (
            "bytes field is memoryview",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes=memoryview(b"x"),
            ),),
        ),
        (
            "bytes field is bytes subclass",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes=BytesSubclass(b"x"),
            ),),
        ),
        (
            "raw bytes are empty",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes=b"",
            ),),
        ),
        (
            "raw bytes exceed per-item maximum",
            (module.ReviewReportObjectV1(
                digest=module.Digest("sha256", bytes(32)),
                bytes=b"x" * (1024 * 1024 + 1),
            ),),
        ),
        ("report count exceeds maximum", over_count_reports),
        ("aggregate raw bytes exceed maximum", aggregate_overflow),
        ("reports are reordered", tuple(reversed(ordered_pair))),
        ("report digest is duplicated", (ordered_pair[0], ordered_pair[0])),
        (
            "same digest is duplicated across different raw bytes",
            (
                module.ReviewReportObjectV1(duplicate_digest, b"a"),
                module.ReviewReportObjectV1(duplicate_digest, b"b"),
            ),
        ),
    )
    original_sha256 = module.hashlib.sha256
    structural_hash_calls = 0

    def count_structural_hashes(*args: object, **kwargs: object) -> object:
        nonlocal structural_hash_calls
        structural_hash_calls += 1
        return original_sha256(*args, **kwargs)

    module.hashlib.sha256 = count_structural_hashes
    try:
        for label, invalid in structural_invalids:
            try:
                assert_rejected(
                    module,
                    lambda invalid=invalid: module._preflight_review_reports(
                        invalid
                    ),
                )
            except AssertionError as error:
                raise AssertionError(f"{label}: {error}") from error
    finally:
        module.hashlib.sha256 = original_sha256
    assert structural_hash_calls == 0, (
        "all review report structure/resource/order checks must precede hashing"
    )

    raw = b"domain-bound-review"
    digest_mismatch_cases = (
        module.ReviewReportObjectV1(
            module.Digest("sha256", hashlib.sha256(raw).digest()), raw
        ),
        module.ReviewReportObjectV1(
            module.Digest("sha256", hashlib.sha256(
                b"pf.independent-review-report.v1" + raw
            ).digest()),
            raw,
        ),
        module.ReviewReportObjectV1(
            module.Digest("sha256", hashlib.sha256(
                b"pf.other-review-report.v1\x00" + raw
            ).digest()),
            raw,
        ),
        dataclasses.replace(
            review_report_object(module, raw),
            bytes=raw + b"-mutated",
        ),
    )
    for invalid in digest_mismatch_cases:
        assert_rejected(
            module,
            lambda invalid=invalid: module._preflight_review_reports((invalid,)),
        )
    interior_reports = tuple(sorted(
        (
            review_report_object(module, b"interior-first"),
            review_report_object(module, b"interior-middle"),
            review_report_object(module, b"interior-last"),
        ),
        key=lambda report: report.digest.bytes,
    ))
    mutated_interior_reports = list(interior_reports)
    mutated_interior_reports[1] = dataclasses.replace(
        mutated_interior_reports[1],
        bytes=mutated_interior_reports[1].bytes + b"-mutated",
    )
    assert_rejected(
        module,
        lambda: module._preflight_review_reports(tuple(mutated_interior_reports)),
    )

    fixture = signed_d0_object_graph_fixture(module, "TASK-D0-04")
    subject = fixture["subject"]
    objects = fixture["objects"]
    original_review_preflight = module._preflight_review_reports
    preflight_calls: list[object] = []

    def capture_review_preflight(values: object) -> object:
        preflight_calls.append(values)
        return original_review_preflight(values)

    module._preflight_review_reports = capture_review_preflight
    try:
        graph = module._parse_bootstrap_task_object_graph(subject, objects)
    finally:
        module._preflight_review_reports = original_review_preflight
    assert graph.root.approval.taskId == "TASK-D0-04"
    assert preflight_calls == [objects.reviewReports], (
        "object graph must preflight the report carrier exactly once"
    )

    extra_report = review_report_object(module, b"unreferenced-review")
    missing_report_objects = dataclasses.replace(
        objects,
        reviewReports=objects.reviewReports[1:],
    )
    extra_report_objects = dataclasses.replace(
        objects,
        reviewReports=tuple(sorted(
            objects.reviewReports + (extra_report,),
            key=lambda report: report.digest.bytes,
        )),
    )
    substituted_report_objects = dataclasses.replace(
        objects,
        reviewReports=tuple(sorted(
            objects.reviewReports[1:] + (extra_report,),
            key=lambda report: report.digest.bytes,
        )),
    )
    required_wire = module.decode_canonical_pf_jcs(
        objects.requiredTestSetBytes
    )
    required_statement = {
        key: value
        for key, value in required_wire.items()
        if key != "signatures"
    }
    required_message = (
        b"pf.required-test-set-signature.v1\x00"
        + hashlib.sha256(
            b"pf.required-test-set-statement.v1\x00"
            + module.canonical_pf_jcs(required_statement)
        ).digest()
    )
    expected_signature_messages = [
        required_message
        for _ in required_wire["signatures"]
    ]
    for task_id in (subject.rootTaskId,) + fixture["dependencyTaskIds"]:
        approval_wire = fixture["built"][task_id]["approvalWire"]
        approval_statement = {
            key: value
            for key, value in approval_wire.items()
            if key != "signatures"
        }
        approval_message = (
            b"pf.bootstrap-task-approval-signature.v1\x00"
            + hashlib.sha256(
                b"pf.bootstrap-task-approval-statement.v1\x00"
                + module.canonical_pf_jcs(approval_statement)
            ).digest()
        )
        expected_signature_messages.extend(
            approval_message for _ in approval_wire["signatures"]
        )
    assert len(expected_signature_messages) == 15
    for label, invalid in (
        ("missing signed review report", missing_report_objects),
        ("extra unreferenced review report", extra_report_objects),
        (
            "same-count missing and unreferenced review reports",
            substituted_report_objects,
        ),
    ):
        original_verify = module.verify_ed25519
        signature_messages: list[bytes] = []

        def capture_signatures(
            public_key: bytes,
            message: bytes,
            signature: bytes,
        ) -> bool:
            signature_messages.append(message)
            return original_verify(public_key, message, signature)

        module.verify_ed25519 = capture_signatures
        try:
            assert_rejected(
                module,
                lambda invalid=invalid: module._parse_bootstrap_task_object_graph(
                    subject,
                    invalid,
                ),
            )
        except AssertionError as error:
            raise AssertionError(f"{label}: {error}") from error
        finally:
            module.verify_ed25519 = original_verify
        receipt_prefix = (
            b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        )
        assert signature_messages == expected_signature_messages, (
            f"{label} must follow every exact RequiredSet and TaskApproval "
            "signature message"
        )
        assert not any(
            message.startswith(receipt_prefix)
            for message in signature_messages
        ), f"{label} must reject before receipt signature verification"

    shared_fixture = signed_d0_object_graph_fixture(
        module,
        "TASK-D0-04",
        shared_quality_review_bytes=(
            b'{"role":"release","decision":"rejected",'
            b'"keyId":"attacker"}\r\n '
        ),
    )
    shared_objects = shared_fixture["objects"]
    assert len(shared_objects.reviewReports) == 8, (
        "six cross-task references to one quality report must occupy one "
        "carrier entry"
    )
    shared_graph = module._parse_bootstrap_task_object_graph(
        shared_fixture["subject"],
        shared_objects,
    )
    assert shared_graph.root.approval.taskId == "TASK-D0-04", (
        "review report join must deduplicate a digest shared across tasks"
    )

    graph_zero_work_invalids = (
        ("reordered carrier", dataclasses.replace(
            objects,
            reviewReports=tuple(reversed(objects.reviewReports)),
        )),
        ("duplicate digest carrier", dataclasses.replace(
            objects,
            reviewReports=(objects.reviewReports[0],) + objects.reviewReports,
        )),
        ("1537-entry carrier", dataclasses.replace(
            objects,
            reviewReports=over_count_reports,
        )),
        ("aggregate max-plus-one carrier", dataclasses.replace(
            objects,
            reviewReports=aggregate_overflow,
        )),
    )
    graph_digest_mismatches = tuple(
        (
            label,
            index + 1,
            dataclasses.replace(
                objects,
                reviewReports=tuple(
                    dataclasses.replace(
                        report,
                        bytes=report.bytes + b"-mutated",
                    )
                    if report_index == index
                    else report
                    for report_index, report in enumerate(
                        objects.reviewReports
                    )
                ),
            ),
        )
        for label, index in (
            ("first digest mismatch", 0),
            ("interior digest mismatch", len(objects.reviewReports) // 2),
            ("last digest mismatch", len(objects.reviewReports) - 1),
        )
    )
    original_verify = module.verify_ed25519
    original_graph_sha256 = module.hashlib.sha256
    graph_signature_calls = 0
    graph_hash_calls = 0
    graph_hash_inputs: list[object] = []

    def count_graph_signatures(*args: object, **kwargs: object) -> bool:
        del args, kwargs
        nonlocal graph_signature_calls
        graph_signature_calls += 1
        return True

    def count_graph_hashes(*args: object, **kwargs: object) -> object:
        nonlocal graph_hash_calls
        graph_hash_calls += 1
        graph_hash_inputs.append(args[0] if args else None)
        return original_graph_sha256(*args, **kwargs)

    module.verify_ed25519 = count_graph_signatures
    module.hashlib.sha256 = count_graph_hashes
    try:
        for label, invalid in graph_zero_work_invalids:
            graph_signature_calls = 0
            graph_hash_calls = 0
            try:
                assert_rejected(
                    module,
                    lambda invalid=invalid: (
                        module._parse_bootstrap_task_object_graph(
                            subject,
                            invalid,
                        )
                    ),
                )
            except AssertionError as error:
                raise AssertionError(f"{label}: {error}") from error
            assert graph_hash_calls == 0, (
                f"{label} must reject before any graph hash work"
            )
            assert graph_signature_calls == 0, (
                f"{label} must reject before signature work"
            )

        report_hash_domain = b"pf.independent-review-report.v1\x00"
        for label, expected_hash_count, invalid in graph_digest_mismatches:
            graph_signature_calls = 0
            graph_hash_calls = 0
            graph_hash_inputs.clear()
            assert_rejected(
                module,
                lambda invalid=invalid: (
                    module._parse_bootstrap_task_object_graph(
                        subject,
                        invalid,
                    )
                ),
            )
            assert graph_hash_calls == expected_hash_count, (
                f"{label} must reject after exactly {expected_hash_count} "
                "ordered report hashes"
            )
            assert all(
                type(value) is bytes
                and value.startswith(report_hash_domain)
                for value in graph_hash_inputs
            ), (
                f"{label} must perform only report-domain hashes before "
                "rejection"
            )
            assert graph_signature_calls == 0, (
                f"{label} must reject before signature work"
            )
    finally:
        module.verify_ed25519 = original_verify
        module.hashlib.sha256 = original_graph_sha256

    result = module.verifyBootstrapTaskObjects(subject, objects)
    assert type(result) is module.ObjectVerifiedV1


def test_evidence_manifest_raw_and_object_projection(module: ModuleType) -> None:
    def typed_evidence_ref(wire: dict) -> object:
        return module.EvidenceRef(wire["id"], module.parse_digest(wire["digest"]))

    def expected_projection(fixture: dict[str, object]) -> object:
        subject = fixture["subject"]
        built = fixture["built"]
        root_task_id = subject.rootTaskId
        root = built[root_task_id]
        dependency_task_ids = fixture["dependencyTaskIds"]
        return module.ObjectVerifiedV1(
            taskId=root_task_id,
            candidate=subject.candidate,
            authorityPolicy=fixture["policyRef"],
            requiredTestSet=module.parse_content_ref(
                root["approvalWire"]["requiredTestSet"]
            ),
            taskApproval=module.TaskApprovalRefV1(
                root_task_id,
                module.parse_digest(root["approvalRefWire"]["digest"]),
            ),
            taskReceipt=module.BootstrapTaskVerifierReceiptRefV1(
                root_task_id,
                root["receiptRefWire"]["id"],
                module.parse_digest(root["receiptRefWire"]["digest"]),
            ),
            stage0Handoff=module.parse_content_ref(root["handoffRefWire"]),
            dependencyReceipts=tuple(
                module.BootstrapTaskVerifierReceiptRefV1(
                    task_id,
                    built[task_id]["receiptRefWire"]["id"],
                    module.parse_digest(
                        built[task_id]["receiptRefWire"]["digest"]
                    ),
                )
                for task_id in dependency_task_ids
            ),
            evidence=tuple(
                typed_evidence_ref(wire)
                for wire in root["evidenceRefsWire"]
            ),
        )

    positive_fixtures = (
        signed_d0_object_graph_fixture(module, "TASK-D0-01"),
        signed_d0_object_graph_fixture(module, "TASK-D0-04"),
    )
    expected_raw_root_fields = {
        "schema", "id", "gate", "repository", "hostAttestation",
        "environment", "sandboxPolicies", "tools", "command", "inputs",
        "artifacts", "artifactSetSha256", "observations", "logs", "result",
        "skipAuthorization",
    }
    for fixture in positive_fixtures:
        objects = fixture["objects"]
        for encoded in objects.evidenceObjectBytes:
            decoded = module.decode_canonical_pf_jcs(encoded)
            assert set(decoded) == expected_raw_root_fields, (
                "graph fixture must carry complete proof-forge.evidence.v1"
            )
            assert decoded["schema"] == "proof-forge.evidence.v1"
        for task_id, task_object in fixture["built"].items():
            manifest_bytes = task_object["evidenceManifestBytes"]
            assert task_object["handoffWire"]["channels"][3][
                "bindingDigest"
            ] == evidence_manifest_digest(manifest_bytes)
            manifest = module.decode_canonical_pf_jcs(manifest_bytes)
            assert manifest["taskId"] == task_id
            assert manifest["evidence"] == list(
                task_object["evidenceRefsWire"]
            )

        result = module.verifyBootstrapTaskObjects(
            fixture["subject"],
            objects,
        )
        expected = expected_projection(fixture)
        assert type(result) is module.ObjectVerifiedV1
        assert result == expected
        assert type(result.taskApproval) is module.TaskApprovalRefV1
        assert type(result.taskReceipt) is module.BootstrapTaskVerifierReceiptRefV1
        assert all(
            type(ref) is module.BootstrapTaskVerifierReceiptRefV1
            for ref in result.dependencyReceipts
        )
        assert all(type(ref) is module.EvidenceRef for ref in result.evidence)

    order_fixture = positive_fixtures[0]
    original_report_preflight = module._preflight_review_reports
    original_evidence_decode = module._EVIDENCE_V1_CORE.decode_json
    intrinsic_events: list[str] = []

    def capture_report_preflight(values: object) -> object:
        intrinsic_events.append("report")
        return original_report_preflight(values)

    def capture_evidence_decode(encoded: bytes) -> object:
        intrinsic_events.append("evidence")
        return original_evidence_decode(encoded)

    module._preflight_review_reports = capture_report_preflight
    module._EVIDENCE_V1_CORE.decode_json = capture_evidence_decode
    try:
        ordered_result = module.verifyBootstrapTaskObjects(
            order_fixture["subject"],
            order_fixture["objects"],
        )
    finally:
        module._preflight_review_reports = original_report_preflight
        module._EVIDENCE_V1_CORE.decode_json = original_evidence_decode
    assert type(ordered_result) is module.ObjectVerifiedV1
    assert intrinsic_events[0] == "report"
    assert "evidence" in intrinsic_events[1:]

    def wrong_manifest_binding(handoff: dict) -> None:
        handoff["channels"][3]["bindingDigest"] = digest_text(b"\x00" * 32)

    def wrong_candidate(evidence: dict) -> None:
        evidence["repository"]["commit"] = "d" * 40

    def wrong_task(evidence: dict) -> None:
        evidence["gate"]["taskId"] = "TASK-D0-02"

    def wrong_tests(evidence: dict) -> None:
        evidence["gate"]["testIds"] = ["TST-DOC-002"]

    def wrong_qualification(evidence: dict) -> None:
        evidence["gate"]["qualification"] = "formal"

    def wrong_result(evidence: dict) -> None:
        evidence["result"] = "failed"
        evidence["command"]["attempts"][0]["exitCode"] = 1

    def unknown_raw_field(evidence: dict) -> None:
        evidence["callerClaim"] = True

    def wrong_artifact_set(evidence: dict) -> None:
        evidence["artifactSetSha256"] = "00" * 32

    def wrong_manifest_schema(manifest: dict) -> None:
        manifest["schema"] = "proof-forge.bootstrap-evidence-root.v1"

    def wrong_manifest_candidate(manifest: dict) -> None:
        manifest["candidate"] = candidate_identity_wire(module, "d" * 40)

    def wrong_manifest_evidence(manifest: dict) -> None:
        manifest["evidence"][0]["digest"] = digest_text(b"\x00" * 32)

    zero_curve_cases: list[tuple[str, object, object]] = []
    wrong_binding_fixture = signed_d0_object_graph_fixture(
        module,
        "TASK-D0-01",
        handoff_mutators={"TASK-D0-01": wrong_manifest_binding},
    )
    zero_curve_cases.append((
        "manifest digest is not bound by evidence-root handoff channel",
        wrong_binding_fixture["subject"],
        wrong_binding_fixture["objects"],
    ))
    cross_task_manifest = signed_d0_object_graph_fixture(
        module,
        "TASK-D0-04",
        manifest_source_overrides={"TASK-D0-04": "TASK-D0-03"},
    )
    zero_curve_cases.append((
        "root reuses a dependency task evidence manifest",
        cross_task_manifest["subject"],
        cross_task_manifest["objects"],
    ))
    for label, task_id, mutator in (
        ("root manifest schema mismatch", "TASK-D0-01", wrong_manifest_schema),
        ("root manifest candidate mismatch", "TASK-D0-01", wrong_manifest_candidate),
        ("root manifest EvidenceRef mismatch", "TASK-D0-01", wrong_manifest_evidence),
        (
            "dependency manifest candidate mismatch",
            "TASK-D0-03",
            wrong_manifest_candidate,
        ),
    ):
        root_task_id = "TASK-D0-01" if task_id == "TASK-D0-01" else "TASK-D0-04"
        fixture = signed_d0_object_graph_fixture(
            module,
            root_task_id,
            manifest_mutators={task_id: mutator},
        )
        zero_curve_cases.append((label, fixture["subject"], fixture["objects"]))

    for label, mutator in (
        ("raw EV candidate mismatch", wrong_candidate),
        ("raw EV task mismatch", wrong_task),
        ("raw EV test mismatch", wrong_tests),
        ("raw EV formal qualification", wrong_qualification),
        ("raw EV failed result", wrong_result),
        ("raw EV unknown closed-schema field", unknown_raw_field),
        ("raw EV artifact-set digest mismatch", wrong_artifact_set),
    ):
        fixture = signed_d0_object_graph_fixture(
            module,
            "TASK-D0-01",
            evidence_mutators={"EV-20260717-0001": mutator},
        )
        zero_curve_cases.append((label, fixture["subject"], fixture["objects"]))

    root_fixture = positive_fixtures[0]
    root_objects = root_fixture["objects"]
    changed_raw = copy.deepcopy(root_fixture["evidenceWires"]["EV-20260717-0001"])
    changed_raw["gate"]["id"] = "bootstrap-task-d0-01-changed"
    zero_curve_cases.append((
        "raw EV SHA-256 differs from the signed EvidenceRef",
        root_fixture["subject"],
        dataclasses.replace(
            root_objects,
            evidenceObjectBytes=(module.canonical_pf_jcs(changed_raw),),
        ),
    ))
    zero_curve_cases.extend((
        (
            "root evidence manifest is empty",
            root_fixture["subject"],
            dataclasses.replace(root_objects, evidenceManifestBytes=b""),
        ),
        (
            "root evidence manifest is noncanonical",
            root_fixture["subject"],
            dataclasses.replace(
                root_objects,
                evidenceManifestBytes=root_objects.evidenceManifestBytes + b" ",
            ),
        ),
        (
            "raw EV is noncanonical",
            root_fixture["subject"],
            dataclasses.replace(
                root_objects,
                evidenceObjectBytes=(root_objects.evidenceObjectBytes[0] + b" ",),
            ),
        ),
    ))

    full_fixture = positive_fixtures[1]
    full_objects = full_fixture["objects"]
    evidence_values = full_objects.evidenceObjectBytes
    extra_wire = full_raw_evidence_wire(
        module,
        full_fixture["candidateWire"],
        "TASK-D0-04",
        D0_GRAPH_ROWS["TASK-D0-04"]["testIds"],
        "EV-20260717-0099",
    )
    extra_bytes = module.canonical_pf_jcs(extra_wire)
    same_count_substitution = tuple(sorted(
        evidence_values[1:] + (extra_bytes,),
        key=lambda encoded: module.decode_canonical_pf_jcs(encoded)["id"],
    ))
    carrier_cases = (
        ("missing raw EV", evidence_values[1:]),
        ("extra raw EV", evidence_values + (extra_bytes,)),
        (
            "duplicate raw EV",
            (evidence_values[0],) + evidence_values[:-1],
        ),
        (
            "reordered raw EV",
            (evidence_values[1], evidence_values[0]) + evidence_values[2:],
        ),
        ("same-count raw EV substitution", same_count_substitution),
    )
    for label, values in carrier_cases:
        zero_curve_cases.append((
            label,
            full_fixture["subject"],
            dataclasses.replace(full_objects, evidenceObjectBytes=values),
        ))

    original_evidence_decode = module._EVIDENCE_V1_CORE.decode_json
    evidence_decode_calls = 0

    def count_evidence_decode(encoded: bytes) -> object:
        nonlocal evidence_decode_calls
        evidence_decode_calls += 1
        return original_evidence_decode(encoded)

    module._EVIDENCE_V1_CORE.decode_json = count_evidence_decode
    try:
        for label, values in (
            ("dynamic missing raw EV", evidence_values[1:]),
            ("dynamic extra raw EV", evidence_values + (extra_bytes,)),
        ):
            evidence_decode_calls = 0
            rejected = module.verifyBootstrapTaskObjects(
                full_fixture["subject"],
                dataclasses.replace(full_objects, evidenceObjectBytes=values),
            )
            assert isinstance(rejected, module.Rejected), label
            assert evidence_decode_calls == 0, (
                f"{label} must reject before any evidence entry decode"
            )
    finally:
        module._EVIDENCE_V1_CORE.decode_json = original_evidence_decode

    original_verify_ed25519 = module.verify_ed25519
    curve_calls = 0

    def count_curve_calls(*args: object, **kwargs: object) -> bool:
        nonlocal curve_calls
        curve_calls += 1
        return original_verify_ed25519(*args, **kwargs)

    module.verify_ed25519 = count_curve_calls
    try:
        for label, subject, objects in zero_curve_cases:
            curve_calls = 0
            rejected = module.verifyBootstrapTaskObjects(subject, objects)
            assert isinstance(rejected, module.Rejected), label
            assert rejected.code == BOOTSTRAP_REJECTION, label
            assert curve_calls == 0, (
                f"{label} must reject before every signature curve"
            )
    finally:
        module.verify_ed25519 = original_verify_ed25519


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
        "evidenceManifestBytes": b"{}",
        "dependencyObjects": (),
        "evidenceObjectBytes": (b"{}",),
        "reviewReports": (review_report_object(module, b"review"),),
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
    still_incomplete = module.verifyBootstrapTaskObjects(
        subject, complete_objects
    )
    assert isinstance(still_incomplete, module.Rejected)
    assert still_incomplete.code == BOOTSTRAP_REJECTION

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
        test_bootstrap_authority_policy(module)
        test_required_test_set(module)
        test_phase4_snapshot_authority(module)
        test_phase4_snapshot_resource_bounds(module)
        test_phase5_snapshot_and_document_bound_join(module)
        test_phase5_snapshot_resource_bounds(module)
        test_task_approval(module)
        test_task_approval_exact_upper_and_sha256_identity(module)
        test_bootstrap_task_verifier_receipt(module)
        test_bootstrap_approval_set(module)
        test_bootstrap_approval_verifier_receipt(module)
        test_formal_gate_catalog_approval(module)
        candidate = test_common_identities(module)
        test_ed25519(module)
        test_subject_graph_preflight(module, candidate)
        test_phase4_graph_authority_join(module)
        test_dependency_bundle_graph(module)
        test_review_report_preflight(module)
        test_evidence_manifest_raw_and_object_projection(module)
        test_subject_and_missing_root_bytes(module, candidate)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"bootstrap-task-objects-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    print("bootstrap-task-objects-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
