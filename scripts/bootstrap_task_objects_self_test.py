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
    assert isinstance(parsed, module.RequiredTestSetV1)
    assert parsed.schema == "proof-forge.required-test-set.v1"
    assert isinstance(parsed.phase5Document, module.NormativeDocumentRefV1)
    assert isinstance(parsed.phase5Document.contentDigest, module.Digest)
    assert parsed.phase5Document.id == "PHASE-5"
    assert parsed.phase5Document.status == "accepted"
    assert parsed.phase5Document.approvers == (
        "principal-quality", "principal-security",
    )
    assert parsed.authorityPolicy == policy_ref
    assert parsed.requiredTestIds == (
        "TST-BOOTSTRAP-001", "TST-DOC-001", "TST-EVIDENCE-001",
    )
    assert all(
        isinstance(signature, module.ApprovalSignatureV1)
        and signature.algorithm == "ed25519"
        and isinstance(signature.signature, bytes)
        and len(signature.signature) == 64
        for signature in parsed.signatures
    )
    assert tuple(signature.keyId for signature in parsed.signatures) == (
        "key-quality", "key-security",
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
    reordered_ids_preflight_wire = copy.deepcopy(wire)
    reordered_ids_preflight_wire["requiredTestIds"].reverse()
    duplicate_id_preflight_wire = copy.deepcopy(wire)
    duplicate_id_preflight_wire["requiredTestIds"][1] = (
        duplicate_id_preflight_wire["requiredTestIds"][0]
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
    mutations.append(("unknown signature field", unknown_signature))

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

    missing_signatures = copy.deepcopy(wire)
    del missing_signatures["signatures"]
    mutations.append(("missing signatures field", missing_signatures))

    empty_signatures = copy.deepcopy(wire)
    empty_signatures["signatures"] = []
    mutations.append(("empty signatures", empty_signatures))

    reordered_signatures = copy.deepcopy(wire)
    reordered_signatures["signatures"].reverse()
    mutations.append(("reordered signatures", reordered_signatures))

    duplicate_signatures = copy.deepcopy(wire)
    duplicate_signatures["signatures"].insert(
        1, copy.deepcopy(duplicate_signatures["signatures"][0])
    )
    mutations.append(("duplicate signature keyId", duplicate_signatures))

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

    tampered_document = copy.deepcopy(wire)
    tampered_document["phase5Document"]["contentDigest"] = digest_text(
        bytes.fromhex("7f" * 32)
    )
    mutations.append(("tampered Phase-5 content", tampered_document))

    tampered_ids = copy.deepcopy(wire)
    tampered_ids["requiredTestIds"].append("TST-ISO-002")
    tampered_ids["requiredTestIds"].sort()
    mutations.append(("tampered required ID content", tampered_ids))

    wrong_algorithm = copy.deepcopy(wire)
    wrong_algorithm["signatures"][0]["algorithm"] = "ed25519ph"
    mutations.append(("wrong signature algorithm", wrong_algorithm))

    wrong_key = copy.deepcopy(wire)
    wrong_key["signatures"][0]["signature"] = wire["signatures"][1]["signature"]
    mutations.append(("signature under wrong key", wrong_key))

    bad_signature = copy.deepcopy(wire)
    first_signature = bytes.fromhex(bad_signature["signatures"][0]["signature"])
    bad_signature["signatures"][0]["signature"] = (
        bytes([first_signature[0] ^ 1]) + first_signature[1:]
    ).hex()
    mutations.append(("tampered signature", bad_signature))

    invalid_signature_scalar = copy.deepcopy(wire)
    invalid_signature_scalar["signatures"][0]["signature"] = "00" * 63
    mutations.append(("invalid signature scalar", invalid_signature_scalar))

    unknown_key = copy.deepcopy(wire)
    unknown_key["signatures"][0]["keyId"] = "key-unknown"
    mutations.append(("unknown signature keyId", unknown_key))

    for label, mutation in mutations:
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
    assert_rejected(
        module,
        lambda: module.parse_required_test_set(
            module.canonical_pf_jcs(same_principal_wire),
            same_principal_policy_bytes,
        ),
    )

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

    role_insufficient_wire, _, _ = signed_required_test_set(
        module,
        policy_ref,
        signer_key_ids=("key-architecture", "key-quality"),
    )
    assert_rejected(
        module,
        lambda: module.parse_required_test_set(
            module.canonical_pf_jcs(role_insufficient_wire), policy_bytes
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
        test_bootstrap_authority_policy(module)
        test_required_test_set(module)
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
