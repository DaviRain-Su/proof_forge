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
    required_callables = (
        "canonical_pf_jcs",
        "decode_canonical_pf_jcs",
        "parse_digest",
        "parse_content_ref",
        "parse_candidate_identity",
        "parse_bootstrap_authority_policy",
        "parse_required_test_set",
        "parse_phase5_snapshot_content",
        "parse_document_bound_required_test_set",
        "parse_task_approval",
        "parse_bootstrap_task_verifier_receipt",
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
        "Phase5SnapshotContentV1",
        "EvidenceRef",
        "TaskApprovalRefV1",
        "BootstrapTaskVerifierReceiptRefV1",
        "IndependentReviewRefV1",
        "TaskApprovalV1",
        "Stage0ChannelV1",
        "EligibleStage0TcbV1",
        "EligibleStage0EnvironmentV1",
        "EligibleStage0HandoffV1",
        "BootstrapTaskVerifierReceiptV1",
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
        "Phase5SnapshotContentV1": ("document", "requiredTestIds"),
        "EvidenceRef": ("id", "digest"),
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
) -> dict:
    label = key_id if report_label is None else report_label
    report_digest = hashlib.sha256(
        b"pf.independent-review-report.v1\x00"
        + f"approved review by {label}\n".encode("ascii")
    ).digest()
    return {
        "keyId": key_id,
        "role": role,
        "reviewCommit": review_commit,
        "reviewLink": f"https://review.example/task-d0-01/{key_id}",
        "reportDigest": digest_text(report_digest),
        "decision": "approved",
    }


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
        dependencyApprovalBytes=tuple(
            module.canonical_pf_jcs({"taskId": task_id})
            for task_id in (
                "TASK-D0-01",
                "TASK-D0-02",
                "TASK-D0-03",
                "TASK-D0-05",
                "TASK-D0-06",
            )
        ),
        dependencyReceiptBytes=tuple(
            module.canonical_pf_jcs({"taskId": task_id})
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
        reviewReports=({
            "digest": digest_text(hashlib.sha256(
                b"pf.independent-review-report.v1\x00review"
            ).digest()),
            "bytes": b"review",
        },),
    )
    original_receipt_parser = module.parse_bootstrap_task_verifier_receipt
    original_object_shell_validator = module._validate_object_shell
    events: list[str] = []
    shell_arguments: list[object] = []

    def capture_receipt_parser(*args: object, **kwargs: object) -> tuple:
        del args, kwargs
        events.append("receipt")
        return object(), object()

    def capture_object_shell(objects: object) -> None:
        events.append("shell")
        shell_arguments.append(objects)
        original_object_shell_validator(objects)

    module.parse_bootstrap_task_verifier_receipt = capture_receipt_parser
    module._validate_object_shell = capture_object_shell
    try:
        result = module.verifyBootstrapTaskObjects(subject, shell_objects)
        assert isinstance(result, module.Rejected)
        assert events == ["shell", "receipt"], (
            "valid subject graph must validate the object shell before "
            "receipt signature work"
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
            "malformed object shell must reject before receipt signature work"
        )
        assert shell_arguments == [malformed_shell]
        for label, invalid_subject in invalid_subjects:
            events.clear()
            shell_arguments.clear()
            result = module.verifyBootstrapTaskObjects(
                invalid_subject,
                shell_objects,
            )
            assert isinstance(result, module.Rejected)
            assert events == [], (
                f"{label} must reject before object or signature work"
            )
            assert shell_arguments == []
    finally:
        module.parse_bootstrap_task_verifier_receipt = original_receipt_parser
        module._validate_object_shell = original_object_shell_validator


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
    original_task_receipt_parser = module.parse_bootstrap_task_verifier_receipt
    original_task_approval_parser = module.parse_task_approval
    task_receipt_calls = []

    def capture_task_receipt_call(
        task_receipt_bytes: bytes,
        task_approval_bytes: bytes,
        required_test_set_bytes: bytes,
        authority_policy_bytes: bytes,
        phase5_snapshot: object,
        stage0_handoff_bytes: bytes,
    ) -> tuple[object, object]:
        task_receipt_calls.append((
            task_receipt_bytes,
            task_approval_bytes,
            required_test_set_bytes,
            authority_policy_bytes,
            phase5_snapshot,
            stage0_handoff_bytes,
        ))
        return object(), object()

    module.parse_bootstrap_task_verifier_receipt = capture_task_receipt_call
    module.parse_task_approval = lambda *args, **kwargs: (_ for _ in ()).throw(
        AssertionError("legacy TaskApproval parser must not be called")
    )
    try:
        still_incomplete = module.verifyBootstrapTaskObjects(
            subject, complete_objects
        )
    finally:
        module.parse_bootstrap_task_verifier_receipt = original_task_receipt_parser
        module.parse_task_approval = original_task_approval_parser
    assert isinstance(still_incomplete, module.Rejected)
    assert len(task_receipt_calls) == 1, (
        "object consumer must invoke the six-input task receipt parser once"
    )
    (
        called_receipt,
        called_approval,
        called_required,
        called_policy,
        called_snapshot,
        called_handoff,
    ) = task_receipt_calls[0]
    assert called_receipt is complete_objects.taskReceiptBytes
    assert called_approval is complete_objects.taskApprovalBytes
    assert called_required is complete_objects.requiredTestSetBytes
    assert called_policy is complete_objects.authorityPolicyBytes
    assert called_snapshot is documents[-1], (
        "object consumer must pass the same subject PHASE-5 snapshot identity"
    )
    assert called_handoff is complete_objects.stage0HandoffBytes

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
        test_phase5_snapshot_and_document_bound_join(module)
        test_phase5_snapshot_resource_bounds(module)
        test_task_approval(module)
        test_task_approval_exact_upper_and_sha256_identity(module)
        test_bootstrap_task_verifier_receipt(module)
        candidate = test_common_identities(module)
        test_ed25519(module)
        test_subject_graph_preflight(module, candidate)
        test_subject_and_missing_root_bytes(module, candidate)
    except (AssertionError, OSError, ImportError, SyntaxError) as error:
        print(f"bootstrap-task-objects-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    print("bootstrap-task-objects-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
