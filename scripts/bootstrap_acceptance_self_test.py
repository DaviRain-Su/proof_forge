#!/usr/bin/env python3
"""Acceptance tests for the TST-BOOTSTRAP-001 rehearsal harness (dev slice).

Runs the end-to-end pre-activation rehearsal against a fixture namespace that
is disjoint from any production lookup tuple, plus the pre-activation
negative matrix.  All seeds are public RFC 8032 test vectors.  Everything
runs under a temporary directory with unprivileged bubblewrap.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import ModuleType
from typing import Callable


MODULE_PATH = Path(__file__).with_name("bootstrap_acceptance.py")
MODULE_NAME = "proof_forge_bootstrap_acceptance"
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
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
RUN_A_ID = "bootstrap-acceptance-run-a"
RUN_A_NONCE = "aa" * 32
RUN_B_ID = "bootstrap-acceptance-run-b"
RUN_B_NONCE = "bb" * 32


def load_module() -> ModuleType:
    assert sys.flags.isolated, "acceptance self-test requires isolated Python (-I)"
    assert sys.flags.no_site, "acceptance self-test requires no-site Python (-S)"
    assert MODULE_PATH.is_file(), "missing scripts/bootstrap_acceptance.py"
    spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
    assert spec is not None and spec.loader is not None, "import spec unavailable"
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)
    return module


def observation_bytes(eligible: bool) -> bytes:
    return json.dumps(
        {
            "attestationScope": "local-observation-only",
            "eligibleForHermetic": eligible,
            "hostProfileId": "linux-x86_64-acceptance-fixture",
            "platform": {"secureBoot": "enabled"},
            "remoteAttestation": False,
            "trustRoot": "synthetic fixture",
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def build_base(module: ModuleType) -> object:
    return module.build_rehearsal_base(
        namespace_id="bootstrap-acceptance-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=observation_bytes(True),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-acceptance-fixture", "qualification": "formal"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )


def write_run_files(base: object, workdir: str) -> None:
    Path(workdir, "policy.json").write_bytes(base.policyBytes)
    Path(workdir, "archive.tar").write_bytes(base.archiveBytes)
    Path(workdir, "manifest.json").write_bytes(base.manifestBytes)


def start_server(
    module: ModuleType,
    base: object,
    run_id: str,
    nonce: str,
    socket_path: str,
) -> object:
    server = module._STORE.AuthorityStoreServer(
        policy_bytes=base.policyBytes,
        service_seed=base.serviceSeed,
        descriptor_id=base.descriptorWire["id"],
        descriptor_version=base.descriptorWire["version"],
        service_executable_digest=module._CONSUMER.Digest(
            "sha256", bytes.fromhex("42" * 32)
        ),
        namespace_id=base.descriptorWire["namespaceId"],
        expected_run_id=run_id,
        expected_nonce=nonce,
        io_timeout_seconds=30.0,
    )
    return server.serve_unix(socket_path)


def close_run_fds(run_handoff: object) -> None:
    for fd in (
        run_handoff.channels.authorityPolicyFd,
        run_handoff.channels.authorityStoreFd,
        run_handoff.channels.candidateArchiveFd,
        run_handoff.channels.evidenceRootFd,
        run_handoff.channels.authorityStoreServiceFd,
    ):
        try:
            os.close(fd)
        except OSError:
            pass


def build_shared_run(module: ModuleType, base: object, tmpdir: str) -> dict:
    workdir = os.path.join(tmpdir, "shared-run")
    os.mkdir(workdir)
    write_run_files(base, workdir)
    handoff = module.produce_run_handoff(
        base,
        handoff_id="bootstrap-acceptance-stage0-handoff",
        handoff_version="1.0.0",
        run_id=RUN_A_ID,
        policy_path=os.path.join(workdir, "policy.json"),
        archive_path=os.path.join(workdir, "archive.tar"),
        manifest_path=os.path.join(workdir, "manifest.json"),
    )
    run = module.produce_run_objects(
        base, handoff, run_id=RUN_A_ID, nonce=RUN_A_NONCE,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    return {"handoff": handoff, "run": run}


def expect_consumer_rejected(
    module: ModuleType,
    operation: Callable[[], object],
    label: str,
) -> None:
    try:
        result = operation()
    except module._CONSUMER.Rejected as rejected:
        if rejected.code != "PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED":
            raise AssertionError(f"{label} raised {rejected.code}")
        return
    raise AssertionError(f"{label} must fail with consumer Rejected; got {result!r}")


def expect_acceptance_error(
    module: ModuleType,
    operation: Callable[[], object],
    codes: tuple[str, ...],
    label: str,
) -> None:
    try:
        result = operation()
    except module.BootstrapAcceptanceError as error:
        if error.code not in codes:
            raise AssertionError(f"{label} raised {error.code}, expected {codes}")
        return
    raise AssertionError(f"{label} must fail with one of {codes}; got {result!r}")


def assert_public_api(module: ModuleType) -> None:
    import dataclasses
    for name in (
        "BootstrapAcceptanceError",
        "RehearsalBase",
        "RehearsalRun",
        "BootstrapRehearsalReport",
        "build_rehearsal_base",
        "produce_run_handoff",
        "produce_run_objects",
        "adopt_channel_client",
        "close_task",
        "collect_activation_inputs",
        "run_bootstrap_rehearsal",
        "rehearsal_child_main",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    for record in ("RehearsalBase", "RehearsalRun", "BootstrapRehearsalReport"):
        assert dataclasses.is_dataclass(getattr(module, record))
    error = module.BootstrapAcceptanceError("PF-BOOTSTRAP-ACCEPT-STATE", "probe")
    assert error.code == "PF-BOOTSTRAP-ACCEPT-STATE"


def test_positive_rehearsal(
    module: ModuleType,
    base: object,
    tmpdir: str,
) -> dict:
    workdir = os.path.join(tmpdir, "rehearsal-a")
    os.mkdir(workdir)
    started = time.monotonic()
    report = module.run_bootstrap_rehearsal(
        base,
        workdir=workdir,
        self_test_path=str(Path(__file__).resolve()),
        run_id=RUN_A_ID,
        nonce=RUN_A_NONCE,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    elapsed = time.monotonic() - started
    if report.activationReceiptId != "BAV-20260718-0001":
        raise AssertionError("rehearsal must return the fixture activation id")
    if report.storeHeadSequence != 16 or report.publishedObjects != 16:
        raise AssertionError("rehearsal must publish exactly sixteen objects")
    if report.dependencyGateFailuresProven != 1:
        raise AssertionError("rehearsal must prove the D0-02 dependency gate")
    if report.containmentExitCode != 0:
        raise AssertionError("contained consumer child must exit cleanly")
    expected_line = (
        f"activation: BAV-20260718-0001 {report.activationReceiptDigestHex}\n"
    ).encode("ascii")
    if expected_line not in report.childStdout:
        raise AssertionError("child stdout must carry the exact activation ref")
    return {"report": report, "elapsed": elapsed}


def test_pre_activation_negatives(
    module: ModuleType,
    base: object,
    shared: dict,
    tmpdir: str,
) -> None:
    consumer = module._CONSUMER
    store = module._STORE
    run = shared["run"]

    def fresh_store(name: str):
        workdir = os.path.join(tmpdir, name)
        os.mkdir(workdir)
        handle = start_server(
            module, base, RUN_A_ID, RUN_A_NONCE,
            os.path.join(workdir, "store.sock"),
        )
        client = store.AuthorityStoreClient(
            base.descriptorRef, RUN_A_ID, RUN_A_NONCE, io_timeout_seconds=30.0
        )
        client.connect(os.path.join(workdir, "store.sock"))
        return handle, client

    # Missing items: no required set.
    handle, client = fresh_store("neg-no-required")
    try:
        for task_id in D0_TASK_IDS:
            client.publish_with_readback(
                store.TASK_APPROVAL_SCHEMA, run.approvalBytes[task_id]
            )
            client.publish_with_readback(
                store.TASK_RECEIPT_SCHEMA, run.receiptBytes[task_id]
            )
        client.publish_with_readback(store.APPROVAL_SET_SCHEMA, run.setBytes)
        expect_acceptance_error(
            module,
            lambda: module.collect_activation_inputs(base, run, client),
            ("PF-BOOTSTRAP-ACCEPT-STATE",),
            "activation without an authenticated required set",
        )
    finally:
        client.close()
        handle.stop()

    # Missing items: five receipts only.
    handle, client = fresh_store("neg-missing-receipt")
    try:
        client.publish_with_readback(
            store.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
        )
        for task_id in D0_TASK_IDS[:-1]:
            client.publish_with_readback(
                store.TASK_RECEIPT_SCHEMA, run.receiptBytes[task_id]
            )
        client.publish_with_readback(store.APPROVAL_SET_SCHEMA, run.setBytes)
        expect_acceptance_error(
            module,
            lambda: module.collect_activation_inputs(base, run, client),
            ("PF-BOOTSTRAP-ACCEPT-STATE",),
            "activation with a missing task receipt",
        )
    finally:
        client.close()
        handle.stop()

    # Missing items: no six-item set.
    handle, client = fresh_store("neg-no-set")
    try:
        client.publish_with_readback(
            store.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
        )
        for task_id in D0_TASK_IDS:
            client.publish_with_readback(
                store.TASK_RECEIPT_SCHEMA, run.receiptBytes[task_id]
            )
        expect_acceptance_error(
            module,
            lambda: module.collect_activation_inputs(base, run, client),
            ("PF-BOOTSTRAP-ACCEPT-STATE",),
            "activation without the six-item set",
        )
    finally:
        client.close()
        handle.stop()

    # D0-04 with only its own approval and receipt.
    handle, client = fresh_store("neg-d0-04-only")
    try:
        client.publish_with_readback(
            store.TASK_APPROVAL_SCHEMA, run.approvalBytes["TASK-D0-04"]
        )
        client.publish_with_readback(
            store.TASK_RECEIPT_SCHEMA, run.receiptBytes["TASK-D0-04"]
        )
        expect_acceptance_error(
            module,
            lambda: module.collect_activation_inputs(base, run, client),
            ("PF-BOOTSTRAP-ACCEPT-STATE",),
            "D0-04 with only its own task receipt must not activate",
        )
    finally:
        client.close()
        handle.stop()

    # Revoked and multiple activation states fail the pre-activation probe.
    handle, client = fresh_store("neg-revoked-multiple")
    try:
        server = getattr(handle, "server")
        server.inject_store_entry(
            store.VERIFIER_RECEIPT_SCHEMA, run.activationKey, (), "revoked"
        )
        revoked = client.lookup(store.VERIFIER_RECEIPT_SCHEMA, run.activationKey)
        if revoked.result != "revoked":
            raise AssertionError("revoked activation key must report revoked")
        foreign = consumer.canonical_pf_jcs({"schema": "x"})
        server.inject_store_entry(
            store.VERIFIER_RECEIPT_SCHEMA,
            run.activationKey,
            (run.activationBytes, foreign),
            "multiple",
        )
        multiple = client.lookup(store.VERIFIER_RECEIPT_SCHEMA, run.activationKey)
        if multiple.result != "multiple":
            raise AssertionError("multiple activation key must report multiple")
    finally:
        client.close()
        handle.stop()

    # Set with reordered task approvals, coherently re-signed.
    set_wire = consumer.decode_canonical_pf_jcs(run.setBytes)
    reordered_wire = copy.deepcopy(set_wire)
    reordered_wire["taskApprovals"][0], reordered_wire["taskApprovals"][1] = (
        reordered_wire["taskApprovals"][1],
        reordered_wire["taskApprovals"][0],
    )
    reordered_set = consumer.canonical_pf_jcs(
        resign_set(module, reordered_wire)
    )
    expect_consumer_rejected(
        module,
        lambda: consumer.parse_bootstrap_approval_verifier_receipt(
            run.activationBytes,
            reordered_set,
            tuple(run.receiptBytes[task_id] for task_id in D0_TASK_IDS),
            base.requiredBytes,
            base.policyBytes,
            base.phase5Snapshot,
            shared["handoff"].handoffBytes,
        ),
        "activation with a reordered set",
    )

    # Task receipt whose approval ref does not match, coherently re-signed.
    receipt_wire = consumer.decode_canonical_pf_jcs(
        run.receiptBytes["TASK-D0-01"]
    )
    receipt_wire["taskApproval"]["digest"] = "sha256:" + "c3" * 32
    mismatched_receipt = consumer.canonical_pf_jcs(
        resign_receipt(module, receipt_wire)
    )
    mismatched_receipts = dict(run.receiptBytes)
    mismatched_receipts["TASK-D0-01"] = mismatched_receipt
    expect_consumer_rejected(
        module,
        lambda: consumer.parse_bootstrap_approval_verifier_receipt(
            run.activationBytes,
            run.setBytes,
            tuple(mismatched_receipts[task_id] for task_id in D0_TASK_IDS),
            base.requiredBytes,
            base.policyBytes,
            base.phase5Snapshot,
            shared["handoff"].handoffBytes,
        ),
        "activation with a mismatched task receipt",
    )

    # Activation verified against a replaced policy.
    other_policy = module._PRODUCER.produce_bootstrap_authority_policy(
        id="bootstrap-other-policy",
        version="1.0.0",
        principals=consumer.parse_bootstrap_authority_policy(
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
            "bootstrap-acceptance-private-scan",
            "1.0.0",
            consumer.Digest("sha256", bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=base.descriptorRef,
        verifier=consumer.parse_bootstrap_authority_policy(
            base.policyBytes
        )[0].verifier,
    )
    expect_consumer_rejected(
        module,
        lambda: consumer.parse_bootstrap_approval_verifier_receipt(
            run.activationBytes,
            run.setBytes,
            tuple(run.receiptBytes[task_id] for task_id in D0_TASK_IDS),
            base.requiredBytes,
            other_policy,
            base.phase5Snapshot,
            shared["handoff"].handoffBytes,
        ),
        "activation verified against a replaced policy",
    )

    # Activation verified against a replaced handoff (fresh run materials).
    drift_dir = os.path.join(tmpdir, "neg-handoff-drift")
    os.mkdir(drift_dir)
    write_run_files(base, drift_dir)
    drifted_handoff = module.produce_run_handoff(
        base,
        handoff_id="bootstrap-acceptance-stage0-handoff",
        handoff_version="1.0.0",
        run_id="bootstrap-acceptance-run-drift",
        policy_path=os.path.join(drift_dir, "policy.json"),
        archive_path=os.path.join(drift_dir, "archive.tar"),
        manifest_path=os.path.join(drift_dir, "manifest.json"),
    )
    try:
        expect_consumer_rejected(
            module,
            lambda: consumer.parse_bootstrap_approval_verifier_receipt(
                run.activationBytes,
                run.setBytes,
                tuple(run.receiptBytes[task_id] for task_id in D0_TASK_IDS),
                base.requiredBytes,
                base.policyBytes,
                base.phase5Snapshot,
                drifted_handoff.handoffBytes,
            ),
            "activation verified against a replaced handoff",
        )
    finally:
        close_run_fds(drifted_handoff)

    # Handoff whose tcb verifier digest drifts from the policy pin.
    drift_tcb_base = module.build_rehearsal_base(
        namespace_id="bootstrap-acceptance-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=observation_bytes(True),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-acceptance-fixture", "qualification": "formal"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    drift_tcb_base = module.RehearsalBase(
        **{
            **vars(drift_tcb_base),
            "tcbDigests": (
                drift_tcb_base.tcbDigests[0],
                bytes.fromhex("99" * 32),
                drift_tcb_base.tcbDigests[2],
                drift_tcb_base.tcbDigests[3],
            ),
        }
    )
    tcb_dir = os.path.join(tmpdir, "neg-tcb-drift")
    os.mkdir(tcb_dir)
    write_run_files(drift_tcb_base, tcb_dir)
    tcb_drifted_handoff = module.produce_run_handoff(
        drift_tcb_base,
        handoff_id="bootstrap-acceptance-stage0-handoff",
        handoff_version="1.0.0",
        run_id=RUN_A_ID,
        policy_path=os.path.join(tcb_dir, "policy.json"),
        archive_path=os.path.join(tcb_dir, "archive.tar"),
        manifest_path=os.path.join(tcb_dir, "manifest.json"),
    )
    try:
        drifted_run = module.produce_run_objects(
            base,
            tcb_drifted_handoff,
            run_id=RUN_A_ID,
            nonce=RUN_A_NONCE,
            seeds_by_key_id=SEEDS_BY_KEY_ID,
        )
        expect_consumer_rejected(
            module,
            lambda: consumer.parse_bootstrap_approval_verifier_receipt(
                drifted_run.activationBytes,
                drifted_run.setBytes,
                tuple(
                    drifted_run.receiptBytes[task_id] for task_id in D0_TASK_IDS
                ),
                base.requiredBytes,
                base.policyBytes,
                base.phase5Snapshot,
                tcb_drifted_handoff.handoffBytes,
            ),
            "activation with a drifted tcb verifier digest",
        )
    finally:
        close_run_fds(tcb_drifted_handoff)


def resign_set(module: ModuleType, wire: dict) -> dict:
    consumer = module._CONSUMER
    producer = module._PRODUCER
    statement = copy.deepcopy(wire)
    statement.pop("signatures", None)
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-set-statement.v1\x00"
        + consumer.canonical_pf_jcs(statement)
    ).digest()
    message = b"pf.bootstrap-approval-set-signature.v1\x00" + statement_digest
    signatures = []
    for key_id in ("key-quality", "key-release", "key-security"):
        signature = producer.sign_ed25519(SEEDS_BY_KEY_ID[key_id], message)
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": signature.hex(),
        })
    return {**statement, "signatures": signatures}


def resign_receipt(module: ModuleType, wire: dict) -> dict:
    consumer = module._CONSUMER
    producer = module._PRODUCER
    statement = copy.deepcopy(wire)
    statement.pop("signature", None)
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-task-verifier-receipt-statement.v1\x00"
        + consumer.canonical_pf_jcs(statement)
    ).digest()
    message = (
        b"pf.bootstrap-task-verifier-receipt-signature.v1\x00"
        + statement_digest
    )
    signature = producer.sign_ed25519(
        SEEDS_BY_KEY_ID["key-verifier-receipt"], message
    )
    return {
        **statement,
        "signature": {
            "keyId": "key-verifier-receipt",
            "algorithm": "ed25519",
            "signature": signature.hex(),
        },
    }


def test_state_independence(
    module: ModuleType,
    base: object,
    shared: dict,
    tmpdir: str,
) -> None:
    store = module._STORE
    run_a = shared["run"]

    # Server A already holds a complete activation from run A.
    workdir_a = os.path.join(tmpdir, "independence-a")
    os.mkdir(workdir_a)
    handle_a = start_server(
        module, base, RUN_A_ID, RUN_A_NONCE,
        os.path.join(workdir_a, "store.sock"),
    )
    client_a = store.AuthorityStoreClient(
        base.descriptorRef, RUN_A_ID, RUN_A_NONCE, io_timeout_seconds=30.0
    )
    client_a.connect(os.path.join(workdir_a, "store.sock"))
    try:
        if client_a.publish_with_readback(
            store.VERIFIER_RECEIPT_SCHEMA, run_a.activationBytes
        ) != run_a.activationBytes:
            raise AssertionError("run A activation publish must close")
        found = client_a.lookup(
            store.VERIFIER_RECEIPT_SCHEMA, run_a.activationKey
        )
        if found.result != "found" or found.objects != (run_a.activationBytes,):
            raise AssertionError("run A activation must be stored exactly")

        # Run B completes independently with a new runId/nonce while the
        # activation from run A exists in its own namespace.
        workdir_b = os.path.join(tmpdir, "independence-b")
        os.mkdir(workdir_b)
        report_b = module.run_bootstrap_rehearsal(
            base,
            workdir=workdir_b,
            self_test_path=str(Path(__file__).resolve()),
            run_id=RUN_B_ID,
            nonce=RUN_B_NONCE,
            seeds_by_key_id=SEEDS_BY_KEY_ID,
            prior_activation_key=run_a.activationKey,
        )
        if report_b.containmentExitCode != 0:
            raise AssertionError("run B must complete independently")

        still = client_a.lookup(
            store.VERIFIER_RECEIPT_SCHEMA, run_a.activationKey
        )
        if still.result != "found" or still.objects != (run_a.activationBytes,):
            raise AssertionError(
                "run A activation must be untouched by the rerun"
            )
    finally:
        client_a.close()
        handle_a.stop()


def run_rehearsal_child() -> int:
    module = load_module()
    result = module.rehearsal_child_main(sys.argv[2])
    return 0 if result is None else result


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--rehearsal-child":
        return run_rehearsal_child()
    # Keep nested AF_UNIX fixtures below Darwin's 104-byte pathname limit.
    tmpdir = tempfile.mkdtemp(prefix="pf-ba-", dir="/tmp")
    started = time.monotonic()
    rehearsal_elapsed = None
    try:
        module = load_module()
        assert_public_api(module)
        base = build_base(module)
        # The positive rehearsal is a Linux-owned bubblewrap namespace
        # boundary.  Darwin can validate the dependency-free object/API
        # baseline above, but cannot honestly execute that runtime proof.
        if sys.platform.startswith("linux"):
            shared = build_shared_run(module, base, tmpdir)
            try:
                positive = test_positive_rehearsal(module, base, tmpdir)
                rehearsal_elapsed = positive["elapsed"]
                test_pre_activation_negatives(module, base, shared, tmpdir)
                test_state_independence(module, base, shared, tmpdir)
            finally:
                close_run_fds(shared["handoff"])
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(
            f"bootstrap-acceptance-self-test: FAIL: {error}", file=sys.stderr
        )
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    elapsed = time.monotonic() - started
    if rehearsal_elapsed is None:
        print(
            "bootstrap-acceptance-self-test: ok "
            f"(linux runtime rehearsal skipped, total {elapsed:.1f}s)"
        )
    else:
        print(
            f"bootstrap-acceptance-self-test: ok "
            f"(rehearsal {rehearsal_elapsed:.1f}s, total {elapsed:.1f}s)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
