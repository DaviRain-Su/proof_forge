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
ED25519_BASEPOINT = "58" + "66" * 31
ED25519_MIXED_ORDER_POINT = "95" + "99" * 31


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

    mutations = []

    wrong_schema = copy.deepcopy(policy)
    wrong_schema["schema"] = "proof-forge.bootstrap-authority-policy.v2"
    mutations.append(("wrong policy schema", wrong_schema))

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
        test_bootstrap_authority_policy(module)
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
