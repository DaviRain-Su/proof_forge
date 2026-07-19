#!/usr/bin/env python3
"""Acceptance tests for the Stage-0 activation driver.

Covers the ineligible fail-closed path (the real path on this host), the
fixture full chain (eligible observation, real TCB recompute, service child
with the descriptor-pinned executable, handoff consume/produce, backfill,
activation, closure bundle), and the negative matrix.  Everything runs
under temporary directories; nothing touches system state.
"""

from __future__ import annotations

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
from types import ModuleType
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
ACTIVATE_PATH = REPO_ROOT / "stage0_activate.py"
SERVICE_CHILD_PATH = REPO_ROOT / "stage0_store_service.py"
MODULE_NAME = "proof_forge_bootstrap_acceptance_for_stage0_test"
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
VERIFIER_EXE_BYTES = b"stage0 fixture bootstrap verifier executable\n"
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))


def load_acceptance() -> ModuleType:
    assert sys.flags.isolated, "stage0-activate self-test requires -I"
    assert sys.flags.no_site, "stage0-activate self-test requires -S"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, ACCEPTANCE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> bytes:
    return hashlib.sha256(path.read_bytes()).digest()


def run_driver(args: list) -> subprocess.CompletedProcess:
    return subprocess.run(
        [PYTHON, "-I", "-S", str(ACTIVATE_PATH), *args],
        capture_output=True,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        timeout=180,
    )


def observation_bytes(eligible: bool) -> bytes:
    return json.dumps(
        {
            "attestationScope": "local-observation-only",
            "eligibleForHermetic": eligible,
            "hostProfileId": "linux-x86_64-stage0-activate-fixture",
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


def build_fixture(module: ModuleType, tmpdir: Path) -> dict:
    producer = module._PRODUCER
    consumer = module._CONSUMER
    service_exe_digest = sha256_file(SERVICE_CHILD_PATH)
    base = module.build_rehearsal_base(
        namespace_id="stage0-activate-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=service_exe_digest,
        observation_bytes=observation_bytes(True),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-stage0-activate-fixture"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    verifier_digest = hashlib.sha256(VERIFIER_EXE_BYTES).digest()
    policy_bytes = producer.produce_bootstrap_authority_policy(
        id="stage0-activate-authority",
        version="1.0.0",
        principals=base.policyRef and consumer.parse_bootstrap_authority_policy(
            base.policyBytes
        )[0].principals,
        taskRules=consumer.parse_bootstrap_authority_policy(
            base.policyBytes
        )[0].taskRules,
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
            "stage0-activate-private-scan",
            "1.0.0",
            consumer.Digest("sha256", bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=base.descriptorRef,
        verifier=consumer.BootstrapAuthorityVerifierV1(
            id="stage0-activate-verifier",
            executableDigest=consumer.Digest("sha256", verifier_digest),
            receiptKeyId="key-verifier-receipt",
            receiptPublicKey=producer.ed25519_public_key_from_seed(
                SEEDS_BY_KEY_ID["key-verifier-receipt"]
            ),
        ),
    )
    _, policy_ref = consumer.parse_bootstrap_authority_policy(policy_bytes)
    required_bytes = producer.produce_required_test_set(
        id="bootstrap-acceptance-required-tests",
        version="1.0.0",
        phase5Document=base.requiredRef and consumer.parse_required_test_set(
            base.requiredBytes, base.policyBytes
        )[0].phase5Document,
        authorityPolicy=policy_ref,
        requiredTestIds=consumer.parse_required_test_set(
            base.requiredBytes, base.policyBytes
        )[0].requiredTestIds,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    required_ref = consumer.ContentRef(
        "proof-forge.required-test-set.v1",
        "bootstrap-acceptance-required-tests",
        "1.0.0",
        consumer.Digest(
            "sha256",
            hashlib.sha256(
                b"pf.required-test-set.v1\x00" + required_bytes
            ).digest(),
        ),
    )
    catalog_wire = consumer.decode_canonical_pf_jcs(base.catalogBytes)
    catalog_wire["requiredTestSet"] = {
        "schema": required_ref.schema,
        "id": required_ref.id,
        "version": required_ref.version,
        "digest": "sha256:" + required_ref.digest.bytes.hex(),
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
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    tcb_digests = (
        sha256_file(REPO_ROOT / "verify_host_stage0.sh"),
        verifier_digest,
        sha256_file(REPO_ROOT / "stage0_containment.py"),
        sha256_file(REPO_ROOT / "gate_evidence.py"),
    )
    base = module.RehearsalBase(**{
        **vars(base),
        "policyBytes": policy_bytes,
        "policyRef": policy_ref,
        "requiredBytes": required_bytes,
        "requiredRef": required_ref,
        "catalogBytes": catalog_bytes,
        "catalogApprovalBytes": catalog_approval_bytes,
        "tcbDigests": tcb_digests,
    })

    workdir_seed = tmpdir / "fixture-seed"
    workdir_seed.mkdir()
    write_file(workdir_seed / "policy.json", policy_bytes)
    write_file(workdir_seed / "archive.tar", base.archiveBytes)
    write_file(workdir_seed / "manifest.json", base.manifestBytes)
    handoff = module.produce_run_handoff(
        base,
        handoff_id="stage0-activate-handoff",
        handoff_version="1.0.0",
        run_id="stage0-activate-fixture-run",
        policy_path=str(workdir_seed / "policy.json"),
        archive_path=str(workdir_seed / "archive.tar"),
        manifest_path=str(workdir_seed / "manifest.json"),
    )
    run = module.produce_run_objects(
        base,
        handoff,
        run_id="stage0-activate-fixture-run",
        nonce="dd" * 32,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    return {"base": base, "handoff": handoff, "run": run}


def close_fixture(fixture: dict) -> None:
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


def prepare_workdir(
    fixture: dict,
    tmpdir: Path,
    name: str,
    *,
    eligible: bool,
    verifier_bytes: bytes = VERIFIER_EXE_BYTES,
    with_handoff: bool = True,
    with_full_approvals: bool = True,
    descriptor_override: dict | None = None,
) -> Path:
    base = fixture["base"]
    workdir = tmpdir / name
    approvals = workdir / "approvals"
    approvals.mkdir(parents=True)
    run = fixture["run"]
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
    write_file(workdir / "host-observation.json", observation_bytes(eligible))
    write_file(workdir / "host-profile.json", base.profileBytes)
    descriptor = (
        dict(base.descriptorWire)
        if descriptor_override is None
        else descriptor_override
    )
    write_file(
        workdir / "service-descriptor.json",
        json.dumps(descriptor, sort_keys=True).encode("utf-8"),
    )
    write_file(workdir / "service-seed.hex", SERVICE_SEED.hex().encode(), 0o400)
    write_file(
        workdir / "phase5-snapshot.json",
        json.dumps({
            "id": base.phase5Snapshot.id,
            "path": base.phase5Snapshot.path,
            "bytesHex": base.phase5Snapshot.bytes.hex(),
        }, sort_keys=True).encode("utf-8"),
    )
    write_file(workdir / "candidate-archive.tar", base.archiveBytes)
    write_file(workdir / "evidence-root-manifest.json", base.manifestBytes)
    write_file(workdir / "bootstrap-verifier.exe", verifier_bytes)
    write_file(approvals / "required-test-set.json", base.requiredBytes)
    if with_full_approvals:
        write_file(approvals / "catalog.json", base.catalogBytes)
        write_file(
            approvals / "catalog-approval.json", base.catalogApprovalBytes
        )
        for task_id in D0_TASK_IDS:
            write_file(
                approvals / f"{task_id.lower()}-approval.json",
                run.approvalBytes[task_id],
            )
            write_file(
                approvals / f"{task_id.lower()}-receipt.json",
                run.receiptBytes[task_id],
            )
        write_file(approvals / "approval-set.json", run.setBytes)
        write_file(approvals / "activation-receipt.json", run.activationBytes)
    if with_handoff:
        write_file(
            workdir / "eligible-stage0-handoff.json",
            fixture["handoff"].handoffBytes,
        )
    return workdir


def driver_args(workdir: Path, output: Path) -> list:
    return [
        "--policy", str(workdir / "policy.json"),
        "--candidate", str(workdir / "candidate.json"),
        "--workdir", str(workdir),
        "--output", str(output),
    ]


def expect_error(
    result: subprocess.CompletedProcess,
    code: bytes,
    label: str,
) -> None:
    if result.returncode != 1 or not result.stderr.startswith(code + b":"):
        raise AssertionError(
            f"{label} must fail with {code.decode()}: "
            f"{result.returncode} {result.stderr!r}"
        )


def test_ineligible(fixture: dict, tmpdir: Path) -> None:
    workdir = prepare_workdir(fixture, tmpdir, "ineligible", eligible=False)
    output = tmpdir / "bundle-ineligible"
    result = run_driver(driver_args(workdir, output))
    expect_error(result, b"PF-STAGE0-ACTIVATE-INELIGIBLE", "ineligible host")
    if output.exists():
        raise AssertionError("ineligible rejection must not create a bundle")


def test_full_chain(fixture: dict, tmpdir: Path) -> None:
    base = fixture["base"]
    workdir = prepare_workdir(fixture, tmpdir, "full", eligible=True)
    output = tmpdir / "bundle-full"
    result = run_driver(driver_args(workdir, output))
    if result.returncode != 0:
        raise AssertionError(f"full activation failed: {result!r}")
    for marker in (
        b"eligible: ok",
        b"tcb: ok",
        b"service: ok",
        b"handoff: consumed",
        b"backfill: TASK-D0-04 closed",
        b"bundle: ",
    ):
        if marker not in result.stdout:
            raise AssertionError(f"missing progress marker {marker}: {result.stdout!r}")
    expected_activation_digest = hashlib.sha256(
        b"pf.bootstrap-approval-verifier-receipt.v1\x00"
        + fixture["run"].activationBytes
    ).hexdigest()
    if (
        f"activation: BAV-20260718-0001 sha256:{expected_activation_digest}\n".encode()
        not in result.stdout
    ):
        raise AssertionError("activation line must carry the exact ref")

    run = fixture["run"]
    expected_files = {
        "authority-policy.json": base.policyBytes,
        "required-test-set.json": base.requiredBytes,
        "bootstrap-approval-set.json": run.setBytes,
        "activation-receipt.json": run.activationBytes,
    }
    for task_id in D0_TASK_IDS:
        expected_files[f"approvals/{task_id.lower()}-approval.json"] = (
            run.approvalBytes[task_id]
        )
        expected_files[f"receipts/{task_id.lower()}-receipt.json"] = (
            run.receiptBytes[task_id]
        )
    for name, payload in expected_files.items():
        target = output / name
        if not target.is_file():
            raise AssertionError(f"bundle lacks {name}")
        if target.read_bytes() != payload:
            raise AssertionError(f"bundle {name} bytes drift")
        if stat.S_IMODE(target.stat().st_mode) != 0o444:
            raise AssertionError(f"bundle {name} must be 0444")
    manifest_path = output / "closure-manifest.json"
    if stat.S_IMODE(manifest_path.stat().st_mode) != 0o444:
        raise AssertionError("closure manifest must be 0444")
    manifest = json.loads(manifest_path.read_bytes())
    if manifest["schema"] != "proof-forge.stage0-activation-closure-manifest.v1":
        raise AssertionError("manifest schema drift")
    if manifest["authorityPolicy"]["digest"] != (
        "sha256:" + base.policyRef.digest.bytes.hex()
    ):
        raise AssertionError("manifest policy digest drift")
    if manifest["requiredTestSet"]["digest"] != (
        "sha256:" + base.requiredRef.digest.bytes.hex()
    ):
        raise AssertionError("manifest required-set digest drift")
    if manifest["approvalSet"]["digest"] != (
        "sha256:"
        + hashlib.sha256(
            b"pf.bootstrap-approval-set.v1\x00" + run.setBytes
        ).hexdigest()
    ):
        raise AssertionError("manifest set digest drift")
    if manifest["stage0Handoff"]["digest"] != (
        "sha256:"
        + hashlib.sha256(
            b"pf.eligible-stage0-handoff.v1\x00" + fixture["handoff"].handoffBytes
        ).hexdigest()
    ):
        raise AssertionError("manifest handoff digest drift")
    for index, task_id in enumerate(D0_TASK_IDS):
        approval_entry = manifest["taskApprovals"][index]
        if approval_entry["taskId"] != task_id or approval_entry["digest"] != (
            "sha256:"
            + hashlib.sha256(
                b"pf.bootstrap-task-approval.v1\x00"
                + run.approvalBytes[task_id]
            ).hexdigest()
        ):
            raise AssertionError(f"manifest approval entry drift for {task_id}")
        receipt_entry = manifest["taskReceipts"][index]
        if receipt_entry["taskId"] != task_id or receipt_entry["digest"] != (
            "sha256:"
            + hashlib.sha256(
                b"pf.bootstrap-task-verifier-receipt.v1\x00"
                + run.receiptBytes[task_id]
            ).hexdigest()
        ):
            raise AssertionError(f"manifest receipt entry drift for {task_id}")
    if manifest["activationReceipt"] != {
        "id": "BAV-20260718-0001",
        "digest": f"sha256:{expected_activation_digest}",
    }:
        raise AssertionError("manifest activation entry drift")

    rerun = run_driver(driver_args(workdir, output))
    expect_error(rerun, b"PF-STAGE0-ACTIVATE-BUNDLE", "bundle no-clobber rerun")


def test_issuance_live_channel(fixture: dict, tmpdir: Path) -> None:
    workdir = prepare_workdir(
        fixture,
        tmpdir,
        "issuance",
        eligible=True,
        with_handoff=False,
        with_full_approvals=True,
    )
    output = tmpdir / "bundle-issuance"
    result = run_driver(driver_args(workdir, output))
    expect_error(result, b"PF-STAGE0-ACTIVATE-BACKFILL", "issuance then gap")
    handoff_path = workdir / "eligible-stage0-handoff.json"
    if not handoff_path.is_file():
        raise AssertionError("issuance must write the handoff file")
    if b"handoff: produced " not in result.stdout:
        raise AssertionError("issuance must report the produced handoff")
    if b"backfill: required-test-set stored" not in result.stdout:
        raise AssertionError(
            "the live socketpair service-child channel must complete the "
            "required-set publish/readback closure"
        )
    if b"receipt rejected against the handoff" not in result.stderr:
        raise AssertionError(
            "the fixture chain must fail against the freshly issued handoff"
        )
    if output.exists():
        raise AssertionError("a failed run must not create a bundle")


def test_negatives(fixture: dict, tmpdir: Path) -> None:
    base = fixture["base"]

    # Replaced bootstrap verifier executable.
    workdir = prepare_workdir(
        fixture, tmpdir, "neg-verifier", eligible=True,
        verifier_bytes=b"replaced verifier bytes\n",
    )
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-verifier"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-TCB", "replaced verifier exe")

    # Service executable digest drift.
    drifted_descriptor = dict(base.descriptorWire)
    drifted_descriptor["serviceExecutableDigest"] = "sha256:" + "99" * 32
    workdir = prepare_workdir(
        fixture, tmpdir, "neg-service", eligible=True,
        descriptor_override=drifted_descriptor,
    )
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-service"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-SERVICE", "service exe drift")

    # Garbage policy bytes.
    workdir = prepare_workdir(fixture, tmpdir, "neg-policy", eligible=True)
    write_file(workdir / "policy.json", b"not a policy\n")
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-policy"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-IO", "garbage policy")

    # Missing one task receipt.
    workdir = prepare_workdir(fixture, tmpdir, "neg-missing", eligible=True)
    (workdir / "approvals" / "task-d0-03-receipt.json").unlink()
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-missing"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-BACKFILL", "missing receipt")

    # Tampered approval-set signature.
    workdir = prepare_workdir(fixture, tmpdir, "neg-set", eligible=True)
    consumer = fixture["consumer"]
    set_wire = consumer.decode_canonical_pf_jcs(fixture["run"].setBytes)
    set_wire["signatures"][0]["signature"] = "00" * 64
    write_file(
        workdir / "approvals" / "approval-set.json",
        consumer.canonical_pf_jcs(set_wire),
    )
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-set"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-BACKFILL", "tampered set")

    # Consumed handoff whose tcb drifts from the recomputed digests.
    workdir = prepare_workdir(fixture, tmpdir, "neg-tcb", eligible=True)
    drifted_base = fixture["module"].RehearsalBase(**{
        **vars(base),
        "tcbDigests": (
            bytes.fromhex("00" * 32),
            base.tcbDigests[1],
            base.tcbDigests[2],
            base.tcbDigests[3],
        ),
    })
    seed_dir = tmpdir / "neg-tcb-seed"
    seed_dir.mkdir()
    write_file(seed_dir / "policy.json", base.policyBytes)
    write_file(seed_dir / "archive.tar", base.archiveBytes)
    write_file(seed_dir / "manifest.json", base.manifestBytes)
    drifted_handoff = fixture["module"].produce_run_handoff(
        drifted_base,
        handoff_id="stage0-activate-handoff",
        handoff_version="1.0.0",
        run_id="stage0-activate-fixture-run",
        policy_path=str(seed_dir / "policy.json"),
        archive_path=str(seed_dir / "archive.tar"),
        manifest_path=str(seed_dir / "manifest.json"),
    )
    try:
        write_file(
            workdir / "eligible-stage0-handoff.json",
            drifted_handoff.handoffBytes,
        )
    finally:
        channels = drifted_handoff.channels
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
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-tcb"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-TCB", "consumed handoff tcb drift")

    # Service child dies at startup (missing service seed).
    workdir = prepare_workdir(fixture, tmpdir, "neg-seed", eligible=True)
    (workdir / "service-seed.hex").unlink()
    result = run_driver(driver_args(workdir, tmpdir / "bundle-neg-seed"))
    expect_error(result, b"PF-STAGE0-ACTIVATE-SERVICE", "dead service child")

    # Pre-existing bundle directory.
    workdir = prepare_workdir(fixture, tmpdir, "neg-bundle", eligible=True)
    output = tmpdir / "bundle-neg-bundle"
    output.mkdir()
    result = run_driver(driver_args(workdir, output))
    expect_error(result, b"PF-STAGE0-ACTIVATE-BUNDLE", "pre-existing bundle")


def main() -> int:
    # Keep nested AF_UNIX fixtures below Darwin's 104-byte pathname limit.
    tmpdir = Path(tempfile.mkdtemp(prefix="pf-sa-", dir="/tmp"))
    try:
        module = load_acceptance()
        fixture = build_fixture(module, tmpdir)
        fixture["module"] = module
        fixture["consumer"] = module._CONSUMER
        try:
            test_ineligible(fixture, tmpdir)
            test_full_chain(fixture, tmpdir)
            test_issuance_live_channel(fixture, tmpdir)
            test_negatives(fixture, tmpdir)
        finally:
            close_fixture(fixture)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"stage0-activate-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("stage0-activate-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
