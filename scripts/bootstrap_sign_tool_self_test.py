#!/usr/bin/env python3
"""Acceptance tests for the signing-ceremony CLI and activation driver.

Covers every sign subcommand end to end (spec JSON -> signed bytes ->
full parse), the seed custody chain, and the two-phase activation driver
(handoff issuance -> offline ceremony via the sign CLI -> activation).
All seeds are public RFC 8032 test vectors; everything runs under a
temporary directory as unprivileged subprocesses.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
SIGN_TOOL_PATH = REPO_ROOT / "bootstrap_sign_tool.py"
ACTIVATION_PATH = REPO_ROOT / "bootstrap_activation.py"
ACCEPTANCE_MODULE_NAME = "proof_forge_bootstrap_acceptance_for_sign_tool_test"
PYTHON = "/usr/bin/python3"
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
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
D0_SIGNERS = {
    "TASK-D0-01": ("key-architecture", "key-quality"),
    "TASK-D0-02": ("key-architecture", "key-quality"),
    "TASK-D0-03": ("key-quality", "key-security"),
    "TASK-D0-04": ("key-quality", "key-release", "key-security"),
    "TASK-D0-05": ("key-quality", "key-security"),
    "TASK-D0-06": ("key-architecture", "key-quality"),
}


def load_acceptance() -> ModuleType:
    assert sys.flags.isolated, "sign-tool self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "sign-tool self-test requires no-site Python (-S)"
    spec = importlib.util.spec_from_file_location(
        ACCEPTANCE_MODULE_NAME, ACCEPTANCE_PATH
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[ACCEPTANCE_MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def run_cli(script: Path, args: list, **kwargs: object) -> subprocess.CompletedProcess:
    return subprocess.run(
        [PYTHON, "-I", "-S", str(script), *args],
        capture_output=True,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        timeout=120,
        **kwargs,
    )


def observation_bytes(eligible: bool) -> bytes:
    return json.dumps(
        {
            "attestationScope": "local-observation-only",
            "eligibleForHermetic": eligible,
            "hostProfileId": "linux-x86_64-sign-tool-fixture",
            "platform": {"secureBoot": "enabled" if eligible else "disabled"},
            "remoteAttestation": False,
            "trustRoot": "synthetic fixture",
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def write_file(path: Path, payload: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(payload)
    os.chmod(path, mode)


def strip_ref(ref_wire: dict) -> dict:
    return {
        "id": ref_wire["id"],
        "version": ref_wire["version"],
        "digest": ref_wire["digest"],
    }


def strip_candidate(candidate_wire: dict) -> dict:
    return {
        "commit": candidate_wire["commit"],
        "treeObjectId": candidate_wire["treeObjectId"],
        "archiveDigest": candidate_wire["archiveDigest"],
    }


def signer_entries(key_ids: tuple, seeds_dir: Path) -> list:
    return [
        {"keyId": key_id, "seedFile": str(seeds_dir / f"{key_id}.hex")}
        for key_id in key_ids
    ]


def spec_policy(policy_wire: dict) -> dict:
    return {
        "fields": {
            "id": policy_wire["id"],
            "version": policy_wire["version"],
            "principals": policy_wire["principals"],
            "taskRules": policy_wire["taskRules"],
            "requiredTestSetRule": policy_wire["requiredTestSetRule"],
            "formalCatalogRule": policy_wire["formalCatalogRule"],
            "bootstrapSetRule": policy_wire["bootstrapSetRule"],
            "sessionContainmentRule": policy_wire["sessionContainmentRule"],
            "freshnessAuthorityRule": policy_wire["freshnessAuthorityRule"],
            "privateScanRule": policy_wire["privateScanRule"],
            "privateScanPolicy": strip_ref(policy_wire["privateScanPolicy"]),
            "revocationSnapshotRule": policy_wire["revocationSnapshotRule"],
            "authorityStoreService": strip_ref(policy_wire["authorityStoreService"]),
            "verifier": policy_wire["verifier"],
        }
    }


def spec_required(required_wire: dict, policy_bytes: bytes, seeds_dir: Path) -> dict:
    return {
        "fields": {
            "id": required_wire["id"],
            "version": required_wire["version"],
            "phase5Document": required_wire["phase5Document"],
            "authorityPolicy": strip_ref(required_wire["authorityPolicy"]),
            "requiredTestIds": required_wire["requiredTestIds"],
        },
        "inputs": {"authorityPolicyBytesHex": policy_bytes.hex()},
        "signers": signer_entries(("key-quality", "key-security"), seeds_dir),
    }


def spec_task_approval(
    approval_wire: dict,
    required_bytes: bytes,
    policy_bytes: bytes,
    snapshot: object,
    seeds_dir: Path,
    task_id: str,
) -> dict:
    return {
        "fields": {
            "taskId": approval_wire["taskId"],
            "candidate": strip_candidate(approval_wire["candidate"]),
            "taskBreakdown": approval_wire["taskBreakdown"],
            "requiredTestSet": strip_ref(approval_wire["requiredTestSet"]),
            "testIds": approval_wire["testIds"],
            "evidence": approval_wire["evidence"],
            "dependencyCompletions": approval_wire["dependencyCompletions"],
            "prerequisiteDocuments": approval_wire["prerequisiteDocuments"],
            "authorityPolicy": strip_ref(approval_wire["authorityPolicy"]),
            "stage0Handoff": strip_ref(approval_wire["stage0Handoff"]),
            "independentReviews": approval_wire["independentReviews"],
        },
        "inputs": {
            "requiredTestSetBytesHex": required_bytes.hex(),
            "authorityPolicyBytesHex": policy_bytes.hex(),
            "phase5Snapshot": {
                "id": snapshot.id,
                "path": snapshot.path,
                "bytesHex": snapshot.bytes.hex(),
            },
        },
        "signers": signer_entries(D0_SIGNERS[task_id], seeds_dir),
    }


def spec_task_receipt(
    receipt_wire: dict,
    approval_bytes: bytes,
    required_bytes: bytes,
    policy_bytes: bytes,
    snapshot: object,
    handoff_bytes: bytes,
    seeds_dir: Path,
) -> dict:
    return {
        "fields": {
            "id": receipt_wire["id"],
            "taskId": receipt_wire["taskId"],
            "candidate": strip_candidate(receipt_wire["candidate"]),
            "authorityPolicy": strip_ref(receipt_wire["authorityPolicy"]),
            "requiredTestSet": strip_ref(receipt_wire["requiredTestSet"]),
            "taskApproval": receipt_wire["taskApproval"],
            "stage0Handoff": strip_ref(receipt_wire["stage0Handoff"]),
            "dependencyCompletions": receipt_wire["dependencyCompletions"],
            "verifierDigest": receipt_wire["verifierDigest"],
        },
        "inputs": {
            "taskApprovalBytesHex": approval_bytes.hex(),
            "requiredTestSetBytesHex": required_bytes.hex(),
            "authorityPolicyBytesHex": policy_bytes.hex(),
            "phase5Snapshot": {
                "id": snapshot.id,
                "path": snapshot.path,
                "bytesHex": snapshot.bytes.hex(),
            },
            "stage0HandoffBytesHex": handoff_bytes.hex(),
        },
        "signer": {
            "keyId": "key-verifier-receipt",
            "seedFile": str(seeds_dir / "key-verifier-receipt.hex"),
        },
    }


def spec_approval_set(
    set_wire: dict,
    approval_bytes: dict,
    receipt_bytes: dict,
    required_bytes: bytes,
    policy_bytes: bytes,
    snapshot: object,
    handoff_bytes: bytes,
    seeds_dir: Path,
) -> dict:
    return {
        "fields": {
            "id": set_wire["id"],
            "version": set_wire["version"],
            "candidate": strip_candidate(set_wire["candidate"]),
            "authorityPolicy": strip_ref(set_wire["authorityPolicy"]),
            "taskBreakdown": set_wire["taskBreakdown"],
            "requiredTestSet": strip_ref(set_wire["requiredTestSet"]),
            "stage0Handoff": strip_ref(set_wire["stage0Handoff"]),
            "taskApprovalsHex": [
                approval_bytes[task_id].hex() for task_id in D0_TASK_IDS
            ],
            "taskReceipts": set_wire["taskReceipts"],
        },
        "inputs": {
            "taskReceiptBytesHex": [
                receipt_bytes[task_id].hex() for task_id in D0_TASK_IDS
            ],
            "requiredTestSetBytesHex": required_bytes.hex(),
            "authorityPolicyBytesHex": policy_bytes.hex(),
            "phase5Snapshot": {
                "id": snapshot.id,
                "path": snapshot.path,
                "bytesHex": snapshot.bytes.hex(),
            },
            "stage0HandoffBytesHex": handoff_bytes.hex(),
        },
        "signers": signer_entries(
            ("key-quality", "key-release", "key-security"), seeds_dir
        ),
    }


def spec_activation(
    activation_wire: dict,
    set_bytes: bytes,
    receipt_bytes: dict,
    required_bytes: bytes,
    policy_bytes: bytes,
    snapshot: object,
    handoff_bytes: bytes,
    seeds_dir: Path,
) -> dict:
    return {
        "fields": {
            "id": activation_wire["id"],
            "candidate": strip_candidate(activation_wire["candidate"]),
            "authorityPolicy": strip_ref(activation_wire["authorityPolicy"]),
            "requiredTestSet": strip_ref(activation_wire["requiredTestSet"]),
            "approvalSet": strip_ref(activation_wire["approvalSet"]),
            "stage0Handoff": strip_ref(activation_wire["stage0Handoff"]),
            "verifierDigest": activation_wire["verifierDigest"],
            "taskApprovals": activation_wire["taskApprovals"],
            "taskReceipts": activation_wire["taskReceipts"],
        },
        "inputs": {
            "approvalSetBytesHex": set_bytes.hex(),
            "taskReceiptBytesHex": [
                receipt_bytes[task_id].hex() for task_id in D0_TASK_IDS
            ],
            "requiredTestSetBytesHex": required_bytes.hex(),
            "authorityPolicyBytesHex": policy_bytes.hex(),
            "phase5Snapshot": {
                "id": snapshot.id,
                "path": snapshot.path,
                "bytesHex": snapshot.bytes.hex(),
            },
            "stage0HandoffBytesHex": handoff_bytes.hex(),
        },
        "signer": {
            "keyId": "key-verifier-receipt",
            "seedFile": str(seeds_dir / "key-verifier-receipt.hex"),
        },
    }


def spec_catalog_approval(
    approval_wire: dict,
    catalog_bytes: bytes,
    required_bytes: bytes,
    policy_bytes: bytes,
    seeds_dir: Path,
) -> dict:
    return {
        "fields": {
            "id": approval_wire["id"],
            "version": approval_wire["version"],
            "authorityPolicy": strip_ref(approval_wire["authorityPolicy"]),
            "requiredTestSet": strip_ref(approval_wire["requiredTestSet"]),
            "catalog": {
                "id": approval_wire["catalog"]["id"],
                "version": approval_wire["catalog"]["version"],
                "contentSha256": approval_wire["catalog"]["contentSha256"],
                "catalogDigest": approval_wire["catalog"]["catalogDigest"],
            },
        },
        "inputs": {
            "authorityPolicyBytesHex": policy_bytes.hex(),
            "catalogBytesHex": catalog_bytes.hex(),
            "requiredTestSetBytesHex": required_bytes.hex(),
        },
        "signers": signer_entries(("key-quality", "key-security"), seeds_dir),
    }


def write_spec(path: Path, spec: dict) -> None:
    write_file(
        path,
        json.dumps(spec, sort_keys=True, indent=1).encode("utf-8") + b"\n",
    )


def seed_files(tmpdir: Path) -> Path:
    seeds_dir = tmpdir / "seeds"
    seeds_dir.mkdir(parents=True, exist_ok=True)
    for key_id, seed in SEEDS_BY_KEY_ID.items():
        write_file(seeds_dir / f"{key_id}.hex", seed.hex().encode("ascii"), 0o400)
    write_file(seeds_dir / "service.hex", SERVICE_SEED.hex().encode("ascii"), 0o400)
    write_file(seeds_dir / "foreign.hex", FOREIGN_SEED.hex().encode("ascii"), 0o400)
    return seeds_dir


def all_seed_hexes() -> tuple:
    return tuple(seed.hex() for seed in SEEDS_BY_KEY_ID.values()) + (
        SERVICE_SEED.hex(),
        FOREIGN_SEED.hex(),
    )


def assert_no_seed_leak(*payloads: bytes) -> None:
    for payload in payloads:
        text = payload.decode("utf-8", errors="replace")
        for seed_hex in all_seed_hexes():
            if seed_hex in text:
                raise AssertionError("seed material leaked into tool output")


def build_fixture(module: ModuleType, tmpdir: Path) -> dict:
    base = module.build_rehearsal_base(
        namespace_id="bootstrap-sign-tool-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=observation_bytes(True),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-sign-tool-fixture", "qualification": "formal"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    workdir = tmpdir / "fixture"
    workdir.mkdir()
    write_file(workdir / "policy.json", base.policyBytes)
    write_file(workdir / "archive.tar", base.archiveBytes)
    write_file(workdir / "manifest.json", base.manifestBytes)
    handoff = module.produce_run_handoff(
        base,
        handoff_id="sign-tool-stage0-handoff",
        handoff_version="1.0.0",
        run_id="sign-tool-fixture-run",
        policy_path=str(workdir / "policy.json"),
        archive_path=str(workdir / "archive.tar"),
        manifest_path=str(workdir / "manifest.json"),
    )
    run = module.produce_run_objects(
        base,
        handoff,
        run_id="sign-tool-fixture-run",
        nonce="cc" * 32,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    return {
        "base": base,
        "handoff": handoff,
        "run": run,
        "workdir": workdir,
    }


def close_fixture_fds(fixture: dict) -> None:
    channels = fixture["handoff"].channels
    for fd in (
        channels.authorityPolicyFd,
        channels.authorityStoreFd,
        channels.candidateArchiveFd,
        channels.evidenceRootFd,
        channels.authorityStoreServiceFd,
    ):
        try:
            os.close(fd)
        except OSError:
            pass


def sign_and_check(
    module: ModuleType,
    tmpdir: Path,
    subcommand: str,
    spec: dict,
    expected_bytes: bytes,
    expected_id: str,
    extra_args: tuple = (),
    tag: str = "",
) -> bytes:
    consumer = module._CONSUMER
    suffix = f"-{tag}" if tag else ""
    spec_path = tmpdir / f"spec-{subcommand}{suffix}.json"
    output_path = tmpdir / f"out-{subcommand}{suffix}.json"
    write_spec(spec_path, spec)
    result = run_cli(
        SIGN_TOOL_PATH,
        [subcommand, "--spec", str(spec_path), "--output", str(output_path),
         *extra_args],
    )
    if result.returncode != 0:
        raise AssertionError(
            f"{subcommand} failed: {result.returncode} {result.stderr!r}"
        )
    produced = output_path.read_bytes()
    if produced != expected_bytes:
        raise AssertionError(f"{subcommand} output bytes drift from reference")
    expected_digest = hashlib.sha256(
        _SIGN_DIGEST_DOMAINS[subcommand] + expected_bytes
    ).hexdigest()
    expected_stdout = f"signed: {expected_id} sha256:{expected_digest}\n".encode()
    if result.stdout != expected_stdout:
        raise AssertionError(
            f"{subcommand} stdout drift: {result.stdout!r} vs {expected_stdout!r}"
        )
    mode = stat.S_IMODE(output_path.stat().st_mode)
    if mode != 0o444:
        raise AssertionError(f"{subcommand} output mode must be 0444, got {mode:o}")
    assert_no_seed_leak(result.stdout, result.stderr, produced)
    return produced


_SIGN_DIGEST_DOMAINS = {
    "sign-authority-policy": b"pf.bootstrap-authority-policy.v1\x00",
    "sign-required-test-set": b"pf.required-test-set.v1\x00",
    "sign-task-approval": b"pf.bootstrap-task-approval.v1\x00",
    "sign-task-receipt": b"pf.bootstrap-task-verifier-receipt.v1\x00",
    "sign-approval-set": b"pf.bootstrap-approval-set.v1\x00",
    "sign-activation-receipt": (
        b"pf.bootstrap-approval-verifier-receipt.v1\x00"
    ),
    "sign-catalog-approval": b"pf.formal-gate-catalog-approval.v1\x00",
}


def test_sign_all_positive(module: ModuleType, fixture: dict, tmpdir: Path) -> dict:
    base = fixture["base"]
    run = fixture["run"]
    handoff_bytes = fixture["handoff"].handoffBytes
    seeds_dir = Path(fixture["seedsDir"])
    consumer = module._CONSUMER
    signed: dict = {"approvals": {}, "receipts": {}}

    policy_wire = consumer.decode_canonical_pf_jcs(base.policyBytes)
    signed["policy"] = sign_and_check(
        module, tmpdir, "sign-authority-policy",
        spec_policy(policy_wire), base.policyBytes, "bootstrap-acceptance-authority",
    )
    required_wire = consumer.decode_canonical_pf_jcs(base.requiredBytes)
    signed["required"] = sign_and_check(
        module, tmpdir, "sign-required-test-set",
        spec_required(required_wire, signed["policy"], seeds_dir),
        base.requiredBytes, "bootstrap-acceptance-required-tests",
    )
    for task_id in D0_TASK_IDS:
        approval_wire = consumer.decode_canonical_pf_jcs(run.approvalBytes[task_id])
        signed["approvals"][task_id] = sign_and_check(
            module, tmpdir, "sign-task-approval",
            spec_task_approval(
                approval_wire, signed["required"], signed["policy"],
                base.phase5Snapshot, seeds_dir, task_id,
            ),
            run.approvalBytes[task_id], task_id, tag=task_id,
        )
        receipt_wire = consumer.decode_canonical_pf_jcs(run.receiptBytes[task_id])
        signed["receipts"][task_id] = sign_and_check(
            module, tmpdir, "sign-task-receipt",
            spec_task_receipt(
                receipt_wire, signed["approvals"][task_id], signed["required"],
                signed["policy"], base.phase5Snapshot, handoff_bytes, seeds_dir,
            ),
            run.receiptBytes[task_id], receipt_wire["id"], tag=task_id,
        )
    set_wire = consumer.decode_canonical_pf_jcs(run.setBytes)
    signed["set"] = sign_and_check(
        module, tmpdir, "sign-approval-set",
        spec_approval_set(
            set_wire, signed["approvals"], signed["receipts"], signed["required"],
            signed["policy"], base.phase5Snapshot, handoff_bytes, seeds_dir,
        ),
        run.setBytes, "bootstrap-acceptance-approval-set",
    )
    activation_wire = consumer.decode_canonical_pf_jcs(run.activationBytes)
    signed["activation"] = sign_and_check(
        module, tmpdir, "sign-activation-receipt",
        spec_activation(
            activation_wire, signed["set"], signed["receipts"], signed["required"],
            signed["policy"], base.phase5Snapshot, handoff_bytes, seeds_dir,
        ),
        run.activationBytes, "BAV-20260718-0001",
    )
    catalog_approval_wire = consumer.decode_canonical_pf_jcs(
        base.catalogApprovalBytes
    )
    signed["catalogApproval"] = sign_and_check(
        module, tmpdir, "sign-catalog-approval",
        spec_catalog_approval(
            catalog_approval_wire, base.catalogBytes, signed["required"],
            signed["policy"], seeds_dir,
        ),
        base.catalogApprovalBytes, "bootstrap-acceptance-catalog-approval",
    )
    return signed


def test_no_clobber(module: ModuleType, fixture: dict, tmpdir: Path) -> None:
    consumer = module._CONSUMER
    base = fixture["base"]
    seeds_dir = Path(fixture["seedsDir"])
    required_wire = consumer.decode_canonical_pf_jcs(base.requiredBytes)
    spec_path = tmpdir / "spec-no-clobber.json"
    output_path = tmpdir / "out-no-clobber.json"
    write_spec(
        spec_path, spec_required(required_wire, base.policyBytes, seeds_dir)
    )
    args = [
        "sign-required-test-set", "--spec", str(spec_path),
        "--output", str(output_path),
    ]
    first = run_cli(SIGN_TOOL_PATH, args)
    if first.returncode != 0:
        raise AssertionError(f"first sign must succeed: {first.stderr!r}")
    original = output_path.read_bytes()
    second = run_cli(SIGN_TOOL_PATH, args)
    if second.returncode != 1 or b"PF-SIGN-TOOL-IO" not in second.stderr:
        raise AssertionError(f"no-clobber rerun must fail with IO: {second!r}")
    if output_path.read_bytes() != original:
        raise AssertionError("no-clobber rerun must not modify the output")


def test_spec_negatives(module: ModuleType, fixture: dict, tmpdir: Path) -> None:
    consumer = module._CONSUMER
    base = fixture["base"]
    seeds_dir = Path(fixture["seedsDir"])
    required_wire = consumer.decode_canonical_pf_jcs(base.requiredBytes)
    good_spec = spec_required(required_wire, base.policyBytes, seeds_dir)
    cases = []
    unknown_field = copy.deepcopy(good_spec)
    unknown_field["fields"]["futureField"] = True
    cases.append(("unknown field", unknown_field, b"PF-SIGN-TOOL-SCHEMA"))
    missing_field = copy.deepcopy(good_spec)
    missing_field["fields"].pop("requiredTestIds")
    cases.append(("missing field", missing_field, b"PF-SIGN-TOOL-SCHEMA"))
    wrong_type = copy.deepcopy(good_spec)
    wrong_type["fields"]["requiredTestIds"] = "TST-DOC-001"
    cases.append(("wrong field type", wrong_type, b"PF-SIGN-TOOL-SCHEMA"))
    bad_ref = copy.deepcopy(good_spec)
    bad_ref["fields"]["authorityPolicy"]["digest"] = "sha256:zz"
    cases.append(("malformed ContentRef digest", bad_ref, b"PF-SIGN-TOOL-SCHEMA"))
    unknown_signer_field = copy.deepcopy(good_spec)
    unknown_signer_field["signers"][0]["futureField"] = True
    cases.append(
        ("unknown signer field", unknown_signer_field, b"PF-SIGN-TOOL-SCHEMA")
    )
    for label, spec, code in cases:
        spec_path = tmpdir / f"spec-neg-{len(label)}.json"
        output_path = tmpdir / f"out-neg-{len(label)}.json"
        write_spec(spec_path, spec)
        result = run_cli(
            SIGN_TOOL_PATH,
            ["sign-required-test-set", "--spec", str(spec_path),
             "--output", str(output_path)],
        )
        if result.returncode != 1 or code not in result.stderr:
            raise AssertionError(f"{label} must fail with {code}: {result!r}")
        if output_path.exists():
            raise AssertionError(f"{label} must leave no output")
        assert_no_seed_leak(result.stdout, result.stderr)


def test_seed_file_negatives(module: ModuleType, fixture: dict, tmpdir: Path) -> None:
    consumer = module._CONSUMER
    base = fixture["base"]
    seeds_dir = Path(fixture["seedsDir"])
    receipt_wire = consumer.decode_canonical_pf_jcs(
        fixture["run"].receiptBytes["TASK-D0-01"]
    )
    spec = spec_task_receipt(
        receipt_wire,
        fixture["run"].approvalBytes["TASK-D0-01"],
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
        fixture["handoff"].handoffBytes,
        seeds_dir,
    )
    spec.pop("signer")
    spec_path = tmpdir / "spec-seed-neg.json"
    write_spec(spec_path, spec)

    def attempt(seed_path: Path) -> subprocess.CompletedProcess:
        return run_cli(
            SIGN_TOOL_PATH,
            [
                "sign-task-receipt", "--spec", str(spec_path),
                "--output", str(tmpdir / "out-seed-neg.json"),
                "--seed-file", str(seed_path), "--key-id", "key-verifier-receipt",
            ],
        )

    cases = []
    cases.append(("missing seed file", tmpdir / "no-such-seed.hex", b"PF-SIGN-TOOL-IO"))
    symlink_path = tmpdir / "seed-link.hex"
    os.symlink(seeds_dir / "key-verifier-receipt.hex", symlink_path)
    cases.append(("symlink seed file", symlink_path, b"PF-SIGN-TOOL-IO"))
    cases.append(("directory seed file", seeds_dir, b"PF-SIGN-TOOL-IO"))
    wide_mode = tmpdir / "seed-wide.hex"
    write_file(wide_mode, SEEDS_BY_KEY_ID["key-verifier-receipt"].hex().encode(), 0o644)
    cases.append(("group-readable seed file", wide_mode, b"PF-SIGN-TOOL-IO"))
    long_seed = tmpdir / "seed-long.bin"
    write_file(long_seed, b"\x01" * 33, 0o400)
    cases.append(("33-byte seed file", long_seed, b"PF-SIGN-TOOL-SCHEMA"))
    upper_seed = tmpdir / "seed-upper.hex"
    write_file(upper_seed, b"AA" * 32, 0o400)
    cases.append(("uppercase hex seed file", upper_seed, b"PF-SIGN-TOOL-SCHEMA"))
    bad_hex = tmpdir / "seed-bad.hex"
    write_file(bad_hex, b"zz" * 32, 0o400)
    cases.append(("non-hex seed file", bad_hex, b"PF-SIGN-TOOL-SCHEMA"))
    for label, seed_path, code in cases:
        result = attempt(seed_path)
        if result.returncode != 1 or code not in result.stderr:
            raise AssertionError(f"{label} must fail with {code}: {result!r}")
        assert_no_seed_leak(result.stdout, result.stderr)
    if (tmpdir / "out-seed-neg.json").exists():
        raise AssertionError("seed negatives must leave no output")

    raw_seed = tmpdir / "seed-raw.bin"
    write_file(raw_seed, SEEDS_BY_KEY_ID["key-verifier-receipt"], 0o400)
    positive = attempt(raw_seed)
    if positive.returncode != 0:
        raise AssertionError(f"raw 32-byte seed file must sign: {positive!r}")
    (tmpdir / "out-seed-neg.json").unlink()


def test_key_id_override_and_wrong_seed(
    module: ModuleType, fixture: dict, tmpdir: Path
) -> None:
    consumer = module._CONSUMER
    base = fixture["base"]
    seeds_dir = Path(fixture["seedsDir"])
    receipt_wire = consumer.decode_canonical_pf_jcs(
        fixture["run"].receiptBytes["TASK-D0-01"]
    )
    handoff_bytes = fixture["handoff"].handoffBytes

    override_spec = spec_task_receipt(
        receipt_wire,
        fixture["run"].approvalBytes["TASK-D0-01"],
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
        handoff_bytes,
        seeds_dir,
    )
    override_spec["signer"]["keyId"] = "wrong-key-name"
    spec_path = tmpdir / "spec-override.json"
    output_path = tmpdir / "out-override.json"
    write_spec(spec_path, override_spec)
    result = run_cli(
        SIGN_TOOL_PATH,
        [
            "sign-task-receipt", "--spec", str(spec_path),
            "--output", str(output_path),
            "--key-id", "key-verifier-receipt",
        ],
    )
    if result.returncode != 0:
        raise AssertionError(f"--key-id override must rescue the signer: {result!r}")
    if output_path.read_bytes() != fixture["run"].receiptBytes["TASK-D0-01"]:
        raise AssertionError("override output must equal the reference receipt")

    plain_spec = spec_task_receipt(
        receipt_wire,
        fixture["run"].approvalBytes["TASK-D0-01"],
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
        handoff_bytes,
        seeds_dir,
    )
    plain_spec.pop("signer")
    spec_path = tmpdir / "spec-wrong-key.json"
    output_path = tmpdir / "out-wrong-key.json"
    write_spec(spec_path, plain_spec)
    result = run_cli(
        SIGN_TOOL_PATH,
        [
            "sign-task-receipt", "--spec", str(spec_path),
            "--output", str(output_path),
            "--seed-file", str(seeds_dir / "key-verifier-receipt.hex"),
            "--key-id", "key-quality",
        ],
    )
    if result.returncode != 1 or b"PF-SIGN-TOOL-VERIFY" not in result.stderr:
        raise AssertionError(f"wrong key id must fail verification: {result!r}")
    if output_path.exists():
        raise AssertionError("wrong key id must leave no output")
    assert_no_seed_leak(result.stdout, result.stderr)

    result = run_cli(
        SIGN_TOOL_PATH,
        [
            "sign-task-receipt", "--spec", str(spec_path),
            "--output", str(output_path),
            "--seed-file", str(seeds_dir / "foreign.hex"),
            "--key-id", "key-verifier-receipt",
        ],
    )
    if result.returncode != 1 or b"PF-SIGN-TOOL-VERIFY" not in result.stderr:
        raise AssertionError(f"wrong seed must fail verification: {result!r}")
    if output_path.exists():
        raise AssertionError("wrong seed must leave no output")
    assert_no_seed_leak(result.stdout, result.stderr)

    approval_wire = consumer.decode_canonical_pf_jcs(
        fixture["run"].approvalBytes["TASK-D0-01"]
    )
    approval_spec = spec_task_approval(
        approval_wire,
        base.requiredBytes,
        base.policyBytes,
        base.phase5Snapshot,
        seeds_dir,
        "TASK-D0-01",
    )
    approval_spec["signers"] = approval_spec["signers"][:1]
    spec_path = tmpdir / "spec-quorum.json"
    output_path = tmpdir / "out-quorum.json"
    write_spec(spec_path, approval_spec)
    result = run_cli(
        SIGN_TOOL_PATH,
        [
            "sign-task-approval", "--spec", str(spec_path),
            "--output", str(output_path),
        ],
    )
    if result.returncode != 1 or b"PF-SIGN-TOOL-VERIFY" not in result.stderr:
        raise AssertionError(f"under-quorum approval must fail: {result!r}")
    if output_path.exists():
        raise AssertionError("under-quorum approval must leave no output")


def prepare_driver_workdir(
    module: ModuleType,
    base: object,
    tmpdir: Path,
    name: str,
    *,
    eligible: bool,
) -> Path:
    workdir = tmpdir / name
    approvals = workdir / "approvals"
    approvals.mkdir(parents=True)
    consumer = module._CONSUMER
    write_file(workdir / "policy.json", base.policyBytes)
    candidate_wire = {
        "commit": base.candidateCommit,
        "treeObjectId": base.candidateTreeObjectId,
        "archiveDigest": "sha256:" + base.candidateArchiveDigestBytes.hex(),
        "digest": "sha256:" + base.candidateDigestBytes.hex(),
    }
    write_file(
        workdir / "candidate.json",
        json.dumps(candidate_wire, sort_keys=True).encode("utf-8"),
    )
    write_file(
        workdir / "phase5-snapshot.json",
        json.dumps({
            "id": base.phase5Snapshot.id,
            "path": base.phase5Snapshot.path,
            "bytesHex": base.phase5Snapshot.bytes.hex(),
        }, sort_keys=True).encode("utf-8"),
    )
    write_file(
        workdir / "service-descriptor.json",
        json.dumps(base.descriptorWire, sort_keys=True).encode("utf-8"),
    )
    write_file(workdir / "service-seed.hex", SERVICE_SEED.hex().encode(), 0o400)
    write_file(workdir / "host-observation.json", observation_bytes(eligible))
    write_file(workdir / "host-profile.json", base.profileBytes)
    write_file(
        workdir / "tcb.json",
        json.dumps({
            "stage0VerifierDigest": "sha256:" + "73" * 32,
            "continuationDigest": "sha256:" + "74" * 32,
            "formalFinalizerDigest": "sha256:" + "75" * 32,
        }, sort_keys=True).encode("utf-8"),
    )
    write_file(workdir / "candidate-archive.tar", base.archiveBytes)
    write_file(workdir / "evidence-root-manifest.json", base.manifestBytes)
    return workdir


def driver_args(workdir: Path) -> list:
    return [
        "--policy", str(workdir / "policy.json"),
        "--candidate", str(workdir / "candidate.json"),
        "--workdir", str(workdir),
    ]


def test_activation_driver(
    module: ModuleType, fixture: dict, tmpdir: Path
) -> None:
    base = fixture["base"]
    seeds_dir = Path(fixture["seedsDir"])
    workdir = prepare_driver_workdir(module, base, tmpdir, "driver", eligible=True)

    # Phase 1: issue the handoff from the eligible observation.
    phase1 = run_cli(ACTIVATION_PATH, driver_args(workdir))
    if phase1.returncode != 0:
        raise AssertionError(f"handoff issuance failed: {phase1!r}")
    handoff_path = workdir / "eligible-stage0-handoff.json"
    if not handoff_path.is_file():
        raise AssertionError("phase 1 must write the handoff file")
    handoff_bytes = handoff_path.read_bytes()
    handoff_digest = hashlib.sha256(
        b"pf.eligible-stage0-handoff.v1\x00" + handoff_bytes
    ).hexdigest()
    if f"sha256:{handoff_digest}".encode() not in phase1.stdout:
        raise AssertionError("phase 1 must print the recomputed handoff digest")
    assert_no_seed_leak(phase1.stdout, phase1.stderr)

    rerun = run_cli(ACTIVATION_PATH, driver_args(workdir))
    if rerun.returncode != 1 or b"PF-BOOTSTRAP-ACTIVATION-IO" not in rerun.stderr:
        raise AssertionError(f"handoff no-clobber rerun must fail: {rerun!r}")

    # Offline ceremony: sign the full chain against the issued handoff.
    consumer = module._CONSUMER
    handoff_wire = consumer.decode_canonical_pf_jcs(handoff_bytes)
    handoff_ref = SimpleNamespace(
        id=handoff_wire["id"],
        version=handoff_wire["version"],
    )
    issued_handoff = SimpleNamespace(
        handoffBytes=handoff_bytes,
        handoffDigest=SimpleNamespace(bytes=bytes.fromhex(handoff_digest)),
        handoffRef=handoff_ref,
        channels=None,
    )
    run = module.produce_run_objects(
        base,
        issued_handoff,
        run_id=handoff_wire["runId"],
        nonce=handoff_wire["nonce"],
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    approvals_dir = workdir / "approvals"
    specs_dir = tmpdir / "driver-specs"
    specs_dir.mkdir()

    def sign_to(subcommand: str, spec: dict, out_name: str) -> bytes:
        spec_path = specs_dir / f"{out_name}.spec.json"
        output_path = approvals_dir / out_name
        write_spec(spec_path, spec)
        result = run_cli(
            SIGN_TOOL_PATH,
            [subcommand, "--spec", str(spec_path), "--output", str(output_path)],
        )
        if result.returncode != 0:
            raise AssertionError(f"ceremony {subcommand} failed: {result!r}")
        return output_path.read_bytes()

    policy_wire = consumer.decode_canonical_pf_jcs(base.policyBytes)
    signed_policy = sign_to(
        "sign-authority-policy", spec_policy(policy_wire), "signed-policy.json"
    )
    write_file(workdir / "policy.json", signed_policy)
    required_wire = consumer.decode_canonical_pf_jcs(base.requiredBytes)
    signed_required = sign_to(
        "sign-required-test-set",
        spec_required(required_wire, signed_policy, seeds_dir),
        "required-test-set.json",
    )
    approval_wires: dict = {}
    for task_id in D0_TASK_IDS:
        approval_wire = consumer.decode_canonical_pf_jcs(run.approvalBytes[task_id])
        approval_wires[task_id] = approval_wire
        signed_approval = sign_to(
            "sign-task-approval",
            spec_task_approval(
                approval_wire, signed_required, signed_policy,
                base.phase5Snapshot, seeds_dir, task_id,
            ),
            f"{task_id.lower()}-approval.json",
        )
        receipt_wire = consumer.decode_canonical_pf_jcs(run.receiptBytes[task_id])
        sign_to(
            "sign-task-receipt",
            spec_task_receipt(
                receipt_wire, signed_approval, signed_required, signed_policy,
                base.phase5Snapshot, handoff_bytes, seeds_dir,
            ),
            f"{task_id.lower()}-receipt.json",
        )
    set_wire = consumer.decode_canonical_pf_jcs(run.setBytes)
    signed_approvals = {
        task_id: (approvals_dir / f"{task_id.lower()}-approval.json").read_bytes()
        for task_id in D0_TASK_IDS
    }
    signed_receipts = {
        task_id: (approvals_dir / f"{task_id.lower()}-receipt.json").read_bytes()
        for task_id in D0_TASK_IDS
    }
    signed_set = sign_to(
        "sign-approval-set",
        spec_approval_set(
            set_wire, signed_approvals, signed_receipts, signed_required,
            signed_policy, base.phase5Snapshot, handoff_bytes, seeds_dir,
        ),
        "approval-set.json",
    )
    activation_wire = consumer.decode_canonical_pf_jcs(run.activationBytes)
    sign_to(
        "sign-activation-receipt",
        spec_activation(
            activation_wire, signed_set, signed_receipts, signed_required,
            signed_policy, base.phase5Snapshot, handoff_bytes, seeds_dir,
        ),
        "activation-receipt.json",
    )
    catalog_approval_wire = consumer.decode_canonical_pf_jcs(
        base.catalogApprovalBytes
    )
    sign_to(
        "sign-catalog-approval",
        spec_catalog_approval(
            catalog_approval_wire, base.catalogBytes, signed_required,
            signed_policy, seeds_dir,
        ),
        "catalog-approval.json",
    )
    write_file(approvals_dir / "catalog.json", base.catalogBytes)

    # Dry-run without --handoff: gaps must cover handoff and activation.
    dry_no_handoff = run_cli(
        ACTIVATION_PATH, driver_args(workdir) + ["--dry-run"]
    )
    if dry_no_handoff.returncode != 0:
        raise AssertionError(f"dry-run without handoff failed: {dry_no_handoff!r}")
    if b"gap: stage0 handoff missing" not in dry_no_handoff.stdout:
        raise AssertionError("dry-run must report the deferred verification gap")
    if b"gap: activation publish skipped (dry-run)" not in dry_no_handoff.stdout:
        raise AssertionError("dry-run must report the activation publish gap")

    # Dry-run with --handoff: only the publish gap remains.
    dry_with_handoff = run_cli(
        ACTIVATION_PATH,
        driver_args(workdir) + ["--dry-run", "--handoff", str(handoff_path)],
    )
    if dry_with_handoff.returncode != 0:
        raise AssertionError(f"dry-run with handoff failed: {dry_with_handoff!r}")
    if b"receipt/set/activation verification" in dry_with_handoff.stdout:
        raise AssertionError("handoff dry-run must verify the full chain")
    if b"gap: activation publish skipped (dry-run)" not in dry_with_handoff.stdout:
        raise AssertionError("handoff dry-run must keep only the publish gap")

    # Phase 2: activate with the issued handoff and the ceremony objects.
    phase2 = run_cli(
        ACTIVATION_PATH,
        driver_args(workdir) + ["--handoff", str(handoff_path)],
    )
    if phase2.returncode != 0:
        raise AssertionError(f"activation phase failed: {phase2!r}")
    expected_activation_digest = hashlib.sha256(
        b"pf.bootstrap-approval-verifier-receipt.v1\x00"
        + (approvals_dir / "activation-receipt.json").read_bytes()
    ).hexdigest()
    expected_line = (
        f"activation: BAV-20260718-0001 sha256:{expected_activation_digest}\n"
    ).encode()
    if expected_line not in phase2.stdout:
        raise AssertionError(
            f"activation phase must print the exact ref: {phase2.stdout!r}"
        )
    assert_no_seed_leak(phase2.stdout, phase2.stderr)

    # Phase-2 negative: a tampered activation receipt fails the chain.
    tampered = consumer.decode_canonical_pf_jcs(
        (approvals_dir / "activation-receipt.json").read_bytes()
    )
    tampered["signature"]["signature"] = "00" * 64
    os.chmod(approvals_dir / "activation-receipt.json", 0o644)
    write_file(
        approvals_dir / "activation-receipt.json",
        consumer.canonical_pf_jcs(tampered),
    )
    tampered_run = run_cli(
        ACTIVATION_PATH,
        driver_args(workdir) + ["--handoff", str(handoff_path)],
    )
    if (tampered_run.returncode != 1
            or b"PF-BOOTSTRAP-ACTIVATION-OBJECT" not in tampered_run.stderr):
        raise AssertionError(
            f"tampered activation receipt must fail the chain: {tampered_run!r}"
        )


def test_activation_driver_ineligible(
    module: ModuleType, fixture: dict, tmpdir: Path
) -> None:
    base = fixture["base"]
    workdir = prepare_driver_workdir(
        module, base, tmpdir, "driver-ineligible", eligible=False
    )
    result = run_cli(ACTIVATION_PATH, driver_args(workdir))
    if (result.returncode != 1
            or b"PF-BOOTSTRAP-ACTIVATION-HOST" not in result.stderr):
        raise AssertionError(
            f"ineligible observation must fail closed: {result!r}"
        )
    if (workdir / "eligible-stage0-handoff.json").exists():
        raise AssertionError("ineligible rejection must not write a handoff")
    assert_no_seed_leak(result.stdout, result.stderr)


def main() -> int:
    tmpdir = Path(tempfile.mkdtemp(prefix="bootstrap-sign-tool-self-test-"))
    try:
        module = load_acceptance()
        fixture = build_fixture(module, tmpdir)
        try:
            fixture["seedsDir"] = str(seed_files(tmpdir))
            test_sign_all_positive(module, fixture, tmpdir)
            test_no_clobber(module, fixture, tmpdir)
            test_spec_negatives(module, fixture, tmpdir)
            test_seed_file_negatives(module, fixture, tmpdir)
            test_key_id_override_and_wrong_seed(module, fixture, tmpdir)
            test_activation_driver(module, fixture, tmpdir)
            test_activation_driver_ineligible(module, fixture, tmpdir)
        finally:
            close_fixture_fds(fixture)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"bootstrap-sign-tool-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("bootstrap-sign-tool-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
