#!/usr/bin/env python3
"""Acceptance tests for the formal evidence finalization consumer family.

Builds a complete signed fixture chain with the producer modules (policy,
required set, formal catalog + approval, bootstrap set + activation receipt,
five signed formal inputs, and the root finalization record), then exercises
the full consumer and the negative matrix.  All seeds are public RFC 8032
test vectors; nothing touches the filesystem outside a temp directory.
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
from pathlib import Path
from types import ModuleType
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
FORMAL_PATH = REPO_ROOT / "formal_evidence.py"
ACCEPTANCE_MODULE_NAME = "proof_forge_bootstrap_acceptance_for_formal_test"
FORMAL_MODULE_NAME = "proof_forge_formal_evidence_under_test"
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
CONTAINMENT_DOMAINS = (
    b"pf.session-containment-receipt-statement.v1\x00",
    b"pf.session-containment-receipt-signature.v1\x00",
)
FRESHNESS_DOMAINS = (
    b"pf.freshness-authority-snapshot-statement.v1\x00",
    b"pf.freshness-authority-snapshot-signature.v1\x00",
)
PRIVATE_SCAN_DOMAINS = (
    b"pf.private-scan-receipt-statement.v1\x00",
    b"pf.private-scan-receipt-signature.v1\x00",
)
REVOCATION_DOMAINS = (
    b"pf.revocation-ledger-snapshot-statement.v1\x00",
    b"pf.revocation-ledger-snapshot-signature.v1\x00",
)


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "formal-evidence self-test requires -I"
    assert sys.flags.no_site, "formal-evidence self-test requires -S"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def observation_bytes() -> bytes:
    return json.dumps(
        {
            "attestationScope": "local-observation-only",
            "eligibleForHermetic": True,
            "hostProfileId": "linux-x86_64-formal-fixture",
            "platform": {"secureBoot": "enabled"},
            "remoteAttestation": False,
            "trustRoot": "synthetic fixture",
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def ref_wire(schema: str, identifier: str, version: str, domain: bytes, payload: bytes) -> dict:
    return {
        "schema": schema,
        "id": identifier,
        "version": version,
        "digest": digest_text(hashlib.sha256(domain + payload).digest()),
    }


def sign_input(
    acceptance: ModuleType,
    statement: dict,
    signer_key_ids: tuple,
    domains: tuple,
) -> dict:
    consumer = acceptance._CONSUMER
    producer = acceptance._PRODUCER
    statement = copy.deepcopy(statement)
    statement.pop("signatures", None)
    statement_digest = hashlib.sha256(
        domains[0] + consumer.canonical_pf_jcs(statement)
    ).digest()
    message = domains[1] + statement_digest
    signatures = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": producer.sign_ed25519(
                SEEDS_BY_KEY_ID[key_id], message
            ).hex(),
        }
        for key_id in signer_key_ids
    ]
    return {**statement, "signatures": signatures}


def resign_input(
    acceptance: ModuleType,
    wire: dict,
    signer_key_ids: tuple,
    domains: tuple,
) -> dict:
    return sign_input(acceptance, wire, signer_key_ids, domains)


def build_fixture(acceptance: ModuleType, tmpdir: Path) -> dict:
    consumer = acceptance._CONSUMER
    base = acceptance.build_rehearsal_base(
        namespace_id="formal-evidence-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=observation_bytes(),
        profile_bytes=json.dumps(
            {"id": "linux-x86_64-formal-fixture"},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    seed_dir = tmpdir / "fixture-seed"
    seed_dir.mkdir()
    (seed_dir / "policy.json").write_bytes(base.policyBytes)
    (seed_dir / "archive.tar").write_bytes(base.archiveBytes)
    (seed_dir / "manifest.json").write_bytes(base.manifestBytes)
    handoff = acceptance.produce_run_handoff(
        base,
        handoff_id="formal-fixture-stage0-handoff",
        handoff_version="1.0.0",
        run_id="formal-fixture-run",
        policy_path=str(seed_dir / "policy.json"),
        archive_path=str(seed_dir / "archive.tar"),
        manifest_path=str(seed_dir / "manifest.json"),
    )
    run = acceptance.produce_run_objects(
        base,
        handoff,
        run_id="formal-fixture-run",
        nonce="ee" * 32,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )

    required_ref_wire = {
        "schema": base.requiredRef.schema,
        "id": base.requiredRef.id,
        "version": base.requiredRef.version,
        "digest": digest_text(base.requiredRef.digest.bytes),
    }
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "formal-evidence-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": copy.deepcopy(required_ref_wire),
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
                "id": "gate-alpha",
                "taskId": "TASK-D0-01",
                "testIds": ["TST-DOC-001", "TST-ISO-001"],
            },
            {
                "id": "gate-beta",
                "taskId": "TASK-D0-03",
                "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
            },
            {
                "id": "gate-delta",
                "taskId": "TASK-D1-01",
                "testIds": ["TST-COMMON-001", "TST-SBOM-001"],
            },
            {
                "id": "gate-gamma",
                "taskId": "TASK-D0-04",
                "testIds": ["TST-BOOTSTRAP-001"],
            },
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
    producer = acceptance._PRODUCER
    catalog_approval_bytes = producer.produce_formal_gate_catalog_approval(
        id="formal-evidence-catalog-approval",
        version="1.0.0",
        authorityPolicy=base.policyRef,
        requiredTestSet=base.requiredRef,
        catalog=catalog_ref,
        signers=(
            ("key-quality", SEEDS_BY_KEY_ID["key-quality"]),
            ("key-security", SEEDS_BY_KEY_ID["key-security"]),
        ),
        authority_policy_bytes=base.policyBytes,
    )
    catalog_approval_digest = hashlib.sha256(
        b"pf.formal-gate-catalog-approval.v1\x00" + catalog_approval_bytes
    ).digest()
    catalog_approval_ref_wire = {
        "schema": "proof-forge.formal-gate-catalog-approval.v1",
        "id": "formal-evidence-catalog-approval",
        "version": "1.0.0",
        "digest": digest_text(catalog_approval_digest),
    }

    candidate_wire = consumer.decode_canonical_pf_jcs(
        consumer.canonical_pf_jcs({
            "commit": base.candidateCommit,
            "treeObjectId": base.candidateTreeObjectId,
            "archiveDigest": digest_text(base.candidateArchiveDigestBytes),
            "digest": digest_text(base.candidateDigestBytes),
        })
    )
    handoff_ref_wire = {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": handoff.handoffRef.id,
        "version": handoff.handoffRef.version,
        "digest": digest_text(handoff.handoffDigest.bytes),
    }
    host_profile_ref_wire = {
        "schema": "proof-forge.host-profile.v1",
        "id": base.profileId,
        "version": base.profileVersion,
        "digest": digest_text(hashlib.sha256(base.profileBytes).digest()),
    }
    policy_ref_wire = {
        "schema": base.policyRef.schema,
        "id": base.policyRef.id,
        "version": base.policyRef.version,
        "digest": digest_text(base.policyRef.digest.bytes),
    }

    containment_statement = {
        "schema": "proof-forge.session-containment-receipt.v1",
        "id": "session-containment-alpha",
        "version": "1.0.0",
        "candidate": copy.deepcopy(candidate_wire),
        "stage0Handoff": copy.deepcopy(handoff_ref_wire),
        "supervisorDigest": digest_text(bytes.fromhex("81" * 32)),
        "rootSessionId": "root-session-01",
        "descendants": [
            {
                "pid": 101,
                "parentPid": 1,
                "startToken": 11,
                "sessionId": 501,
                "executableDigest": digest_text(bytes.fromhex("82" * 32)),
                "termination": "exited",
            },
            {
                "pid": 102,
                "parentPid": 1,
                "startToken": 12,
                "sessionId": 501,
                "executableDigest": digest_text(bytes.fromhex("83" * 32)),
                "termination": "killed",
            },
        ],
        "escapeProbes": [
            {"id": "escape-probe-01", "result": "contained"},
        ],
        "startedAt": "2026-07-18T10:00:00Z",
        "finishedAt": "2026-07-18T10:05:00Z",
        "result": "contained",
    }
    containment_wire = sign_input(
        acceptance, containment_statement,
        ("key-quality", "key-security"), CONTAINMENT_DOMAINS,
    )
    containment_bytes = consumer.canonical_pf_jcs(containment_wire)
    containment_ref_wire = ref_wire(
        containment_wire["schema"], containment_wire["id"],
        containment_wire["version"],
        b"pf.session-containment-receipt.v1\x00", containment_bytes,
    )

    freshness_statement = {
        "schema": "proof-forge.freshness-authority-snapshot.v1",
        "id": "freshness-alpha",
        "version": "1.0.0",
        "authorityPolicy": copy.deepcopy(policy_ref_wire),
        "observedAt": "2026-07-18T10:06:00Z",
        "maximumAgeSeconds": 3600,
        "clockSourceDigest": digest_text(bytes.fromhex("84" * 32)),
    }
    freshness_wire = sign_input(
        acceptance, freshness_statement,
        ("key-quality", "key-release"), FRESHNESS_DOMAINS,
    )
    freshness_bytes = consumer.canonical_pf_jcs(freshness_wire)
    freshness_ref_wire = ref_wire(
        freshness_wire["schema"], freshness_wire["id"],
        freshness_wire["version"],
        b"pf.freshness-authority-snapshot.v1\x00", freshness_bytes,
    )

    revocation_records = []
    previous_sha256 = "0" * 64
    for index in (1, 2):
        record = {
            "schema": "proof-forge.evidence-revocation.v1",
            "id": f"RVK-20260718-{index:04d}",
            "version": "1.0.0",
            "previousRecordSha256": previous_sha256,
            "revokedEvidenceId": f"EV-20260717-{index:04d}",
            "revokedAt": "2026-07-18T09:00:00Z",
        }
        record_bytes = consumer.canonical_pf_jcs(record)
        previous_sha256 = hashlib.sha256(record_bytes).hexdigest()
        revocation_records.append((record, record_bytes))
    revocation_refs = [
        {
            "schema": "proof-forge.evidence-revocation.v1",
            "id": record["id"],
            "version": "1.0.0",
            "digest": digest_text(hashlib.sha256(
                b"pf.evidence-revocation.v1\x00" + record_bytes
            ).digest()),
        }
        for record, record_bytes in revocation_records
    ]
    aggregate = b"".join(
        (32).to_bytes(4, "big") + bytes.fromhex(ref["digest"][7:])
        for ref in revocation_refs
    )
    revocation_statement = {
        "schema": "proof-forge.revocation-ledger-snapshot.v1",
        "id": "revocation-ledger-alpha",
        "version": "1.0.0",
        "authorityPolicy": copy.deepcopy(policy_ref_wire),
        "records": copy.deepcopy(revocation_refs),
        "head": copy.deepcopy(revocation_refs[-1]),
        "recordsDigest": digest_text(hashlib.sha256(
            b"pf.revocation-ledger-records.v1\x00" + aggregate
        ).digest()),
    }
    revocation_wire = sign_input(
        acceptance, revocation_statement,
        ("key-release", "key-security"), REVOCATION_DOMAINS,
    )
    revocation_bytes = consumer.canonical_pf_jcs(revocation_wire)
    revocation_ref_wire = ref_wire(
        revocation_wire["schema"], revocation_wire["id"],
        revocation_wire["version"],
        b"pf.revocation-ledger-snapshot.v1\x00", revocation_bytes,
    )

    finalizer_wire = {
        "schema": "proof-forge.formal-finalizer-identity.v1",
        "id": "formal-finalizer",
        "version": "1.0.0",
        "executableDigest": digest_text(base.tcbDigests[3]),
        "closureDigest": digest_text(bytes.fromhex("85" * 32)),
        "toolchainLockDigest": digest_text(bytes.fromhex("86" * 32)),
    }
    finalizer_bytes = consumer.canonical_pf_jcs(finalizer_wire)
    finalizer_ref_wire = ref_wire(
        finalizer_wire["schema"], finalizer_wire["id"],
        finalizer_wire["version"],
        b"pf.formal-finalizer-identity.v1\x00", finalizer_bytes,
    )

    gates_wire = [
        {
            "id": "gate-alpha",
            "testIds": ["TST-DOC-001", "TST-ISO-001"],
            "build": None,
            "evidenceRefs": [
                {
                    "id": "EV-20260718-0001",
                    "digest": digest_text(bytes.fromhex("91" * 32)),
                },
            ],
        },
        {
            "id": "gate-beta",
            "testIds": ["TST-EVIDENCE-001", "TST-HOST-001", "TST-TOOL-001"],
            "build": None,
            "evidenceRefs": [
                {
                    "id": "EV-20260718-0002",
                    "digest": digest_text(bytes.fromhex("92" * 32)),
                },
                {
                    "id": "EV-20260718-0003",
                    "digest": digest_text(bytes.fromhex("93" * 32)),
                },
            ],
        },
        {
            "id": "gate-delta",
            "testIds": ["TST-COMMON-001", "TST-SBOM-001"],
            "build": {
                "targetId": "noir",
                "targetSemanticsVersion": "1.0.0",
                "targetSemanticsDigest": digest_text(bytes.fromhex("94" * 32)),
                "codegenProfileId": "noir-acir",
                "codegenProfileDigest": digest_text(bytes.fromhex("95" * 32)),
            },
            "evidenceRefs": [
                {
                    "id": "EV-20260718-0005",
                    "digest": digest_text(bytes.fromhex("96" * 32)),
                },
            ],
        },
        {
            "id": "gate-gamma",
            "testIds": ["TST-BOOTSTRAP-001"],
            "build": None,
            "evidenceRefs": [
                {
                    "id": "EV-20260718-0004",
                    "digest": digest_text(bytes.fromhex("97" * 32)),
                },
            ],
        },
    ]
    all_refs_sorted = sorted(
        (ref for gate in gates_wire for ref in gate["evidenceRefs"]),
        key=lambda ref: (ref["id"], ref["digest"]),
    )
    set_ref_wire = {
        "schema": run.setRef.schema,
        "id": run.setRef.id,
        "version": run.setRef.version,
        "digest": digest_text(run.setRef.digest.bytes),
    }

    core_object = {
        "candidate": candidate_wire,
        "hostProfile": copy.deepcopy(host_profile_ref_wire),
        "stage0Handoff": copy.deepcopy(handoff_ref_wire),
        "sessionContainment": containment_ref_wire,
        "requiredTestSet": required_ref_wire,
        "catalog": {
            "schema": catalog_ref.schema,
            "id": catalog_ref.id,
            "version": catalog_ref.version,
            "contentSha256": catalog_ref.contentSha256,
            "catalogDigest": catalog_ref.catalogDigest,
        },
        "catalogApproval": catalog_approval_ref_wire,
        "gates": gates_wire,
        "freshnessAuthority": freshness_ref_wire,
        "revocationLedger": revocation_ref_wire,
        "finalizer": finalizer_ref_wire,
        "bootstrapApproval": {
            "set": set_ref_wire,
            "verifierReceipt": {
                "id": "BAV-20260718-0001",
                "digest": digest_text(run.activationRef.digest.bytes),
            },
        },
    }
    core_digest = hashlib.sha256(
        b"pf.formal-evidence-core.v1\x00"
        + consumer.canonical_pf_jcs(core_object)
    ).digest()

    scan_statement = {
        "schema": "proof-forge.private-scan-receipt.v1",
        "id": "private-scan-alpha",
        "version": "1.0.0",
        "candidate": copy.deepcopy(candidate_wire),
        "evidenceCoreDigest": digest_text(core_digest),
        "scannerDigest": digest_text(bytes.fromhex("87" * 32)),
        "policy": {
            "schema": "proof-forge.private-scan-policy.v1",
            "id": "bootstrap-acceptance-private-scan",
            "version": "1.0.0",
            "digest": digest_text(bytes.fromhex("41" * 32)),
        },
        "scannedEvidenceRefs": copy.deepcopy(all_refs_sorted),
        "scannedMembers": [
            {
                "evidence": copy.deepcopy(gates_wire[0]["evidenceRefs"][0]),
                "role": "candidate-archive",
                "path": "archive.tar",
                "size": 128,
                "digest": digest_text(bytes.fromhex("98" * 32)),
            },
            {
                "evidence": copy.deepcopy(gates_wire[1]["evidenceRefs"][0]),
                "role": "host-observation",
                "path": "obs/observation.json",
                "size": 64,
                "digest": digest_text(bytes.fromhex("99" * 32)),
            },
        ],
        "findings": [],
        "result": "clean",
    }
    scan_wire = sign_input(
        acceptance, scan_statement,
        ("key-quality", "key-security"), PRIVATE_SCAN_DOMAINS,
    )
    scan_bytes = consumer.canonical_pf_jcs(scan_wire)
    scan_ref_wire = ref_wire(
        scan_wire["schema"], scan_wire["id"], scan_wire["version"],
        b"pf.private-scan-receipt.v1\x00", scan_bytes,
    )
    set_digest = hashlib.sha256(
        b"pf.formal-evidence-set.v1\x00"
        + consumer.canonical_pf_jcs({
            "evidenceCoreDigest": digest_text(core_digest),
            "privateScan": scan_ref_wire,
        })
    ).digest()

    record_wire = {
        "schema": "proof-forge.formal-evidence-finalization.v1",
        "id": "EVF-20260718-0001",
        "qualification": "formal",
        "candidate": candidate_wire,
        "hostProfile": copy.deepcopy(host_profile_ref_wire),
        "stage0Handoff": copy.deepcopy(handoff_ref_wire),
        "sessionContainment": containment_ref_wire,
        "requiredTestSet": required_ref_wire,
        "catalog": core_object["catalog"],
        "catalogApproval": catalog_approval_ref_wire,
        "gates": gates_wire,
        "evidenceCoreDigest": digest_text(core_digest),
        "evidenceSetDigest": digest_text(set_digest),
        "freshnessAuthority": freshness_ref_wire,
        "finalizedAt": "2026-07-18T10:07:00Z",
        "expiresAt": "2026-07-18T12:00:00Z",
        "privateScan": scan_ref_wire,
        "revocationLedger": revocation_ref_wire,
        "finalizer": finalizer_ref_wire,
        "bootstrapApproval": core_object["bootstrapApproval"],
    }
    record_bytes = consumer.canonical_pf_jcs(record_wire)
    return {
        "base": base,
        "handoff": handoff,
        "run": run,
        "catalogBytes": catalog_bytes,
        "catalogApprovalBytes": catalog_approval_bytes,
        "containmentBytes": containment_bytes,
        "freshnessBytes": freshness_bytes,
        "scanBytes": scan_bytes,
        "revocationBytes": revocation_bytes,
        "revocationRecordBytes": tuple(
            record_bytes for _, record_bytes in revocation_records
        ),
        "finalizerBytes": finalizer_bytes,
        "recordWire": record_wire,
        "recordBytes": record_bytes,
        "coreDigest": core_digest,
        "setDigest": set_digest,
        "candidateWire": candidate_wire,
        "handoffRefWire": handoff_ref_wire,
        "hostProfileRefWire": host_profile_ref_wire,
        "policyRefWire": policy_ref_wire,
        "requiredRefWire": required_ref_wire,
        "catalogRefWire": core_object["catalog"],
        "catalogApprovalRefWire": catalog_approval_ref_wire,
        "containmentRefWire": containment_ref_wire,
        "freshnessRefWire": freshness_ref_wire,
        "scanRefWire": scan_ref_wire,
        "revocationRefWire": revocation_ref_wire,
        "finalizerRefWire": finalizer_ref_wire,
        "setRefWire": set_ref_wire,
    }


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


def parse_record(formal: ModuleType, fixture: dict, **overrides: object) -> object:
    base = fixture["base"]
    run = fixture["run"]
    snapshot = base.phase5Snapshot
    kwargs = {
        "record_bytes": fixture["recordBytes"],
        "authority_policy_bytes": base.policyBytes,
        "required_test_set_bytes": base.requiredBytes,
        "phase5_snapshot": formal._CONSUMER.BootstrapDocumentSnapshotV1(
            id=snapshot.id,
            path=snapshot.path,
            bytes=snapshot.bytes,
        ),
        "catalog_bytes": fixture["catalogBytes"],
        "catalog_approval_bytes": fixture["catalogApprovalBytes"],
        "session_containment_bytes": fixture["containmentBytes"],
        "freshness_authority_bytes": fixture["freshnessBytes"],
        "private_scan_bytes": fixture["scanBytes"],
        "revocation_ledger_bytes": fixture["revocationBytes"],
        "revocation_record_bytes": fixture["revocationRecordBytes"],
        "finalizer_identity_bytes": fixture["finalizerBytes"],
        "approval_set_bytes": run.setBytes,
        "task_receipt_bytes": tuple(
            run.receiptBytes[task_id] for task_id in D0_TASK_IDS
        ),
        "verifier_receipt_bytes": run.activationBytes,
        "stage0_handoff_bytes": fixture["handoff"].handoffBytes,
    }
    kwargs.update(overrides)
    return formal.parse_formal_evidence_finalization(**kwargs)


def expect_rejected(
    formal: ModuleType,
    operation: Callable[[], object],
    label: str,
) -> None:
    try:
        result = operation()
    except formal.Rejected as rejected:
        if rejected.code != "PF-EVIDENCE-FORMAL-UNVERIFIED":
            raise AssertionError(f"{label} raised {rejected.code}")
        return
    raise AssertionError(f"{label} must fail with formal Rejected; got {result!r}")


def assert_public_api(formal: ModuleType) -> None:
    import dataclasses
    import inspect
    for name in (
        "parse_session_containment_receipt",
        "parse_freshness_authority_snapshot",
        "parse_private_scan_receipt",
        "parse_revocation_ledger_snapshot",
        "parse_formal_finalizer_identity",
        "parse_formal_evidence_finalization",
    ):
        assert callable(getattr(formal, name, None)), f"missing callable {name}"
    for name in (
        "SessionContainmentReceiptV1",
        "FreshnessAuthoritySnapshotV1",
        "PrivateScanReceiptV1",
        "ScannedMemberRefV1",
        "RevocationLedgerSnapshotV1",
        "RevocationRecordRefV1",
        "FormalFinalizerIdentityV1",
        "BuildIdentityV1",
        "FormalGateV1",
        "BootstrapApprovalBindingV1",
        "FormalEvidenceFinalizationV1",
        "FinalizationRefV1",
        "Rejected",
    ):
        assert isinstance(getattr(formal, name, None), type), f"missing type {name}"
    parameters = tuple(
        inspect.signature(
            formal.parse_formal_evidence_finalization
        ).parameters.values()
    )
    assert tuple(parameter.name for parameter in parameters) == (
        "record_bytes",
        "authority_policy_bytes",
        "required_test_set_bytes",
        "phase5_snapshot",
        "catalog_bytes",
        "catalog_approval_bytes",
        "session_containment_bytes",
        "freshness_authority_bytes",
        "private_scan_bytes",
        "revocation_ledger_bytes",
        "revocation_record_bytes",
        "finalizer_identity_bytes",
        "approval_set_bytes",
        "task_receipt_bytes",
        "verifier_receipt_bytes",
        "stage0_handoff_bytes",
    ), "root parser must expose exactly sixteen authoritative inputs"
    assert all(
        parameter.kind is inspect.Parameter.POSITIONAL_OR_KEYWORD
        and parameter.default is inspect.Parameter.empty
        for parameter in parameters
    ), "root parser arguments must be exactly sixteen required inputs"
    record_fields = tuple(
        field.name
        for field in dataclasses.fields(formal.FormalEvidenceFinalizationV1)
    )
    assert record_fields == (
        "schema",
        "id",
        "qualification",
        "candidate",
        "hostProfile",
        "stage0Handoff",
        "sessionContainment",
        "requiredTestSet",
        "catalog",
        "catalogApproval",
        "gates",
        "evidenceCoreDigest",
        "evidenceSetDigest",
        "freshnessAuthority",
        "finalizedAt",
        "expiresAt",
        "privateScan",
        "revocationLedger",
        "finalizer",
        "bootstrapApproval",
    ), "record dataclass must match the frozen record shape"


def test_positive(formal: ModuleType, fixture: dict) -> None:
    record, ref = parse_record(formal, fixture)
    wire = fixture["recordWire"]
    if record.id != "EVF-20260718-0001" or record.qualification != "formal":
        raise AssertionError("record identity fields drift")
    if record.schema != "proof-forge.formal-evidence-finalization.v1":
        raise AssertionError("record schema drift")
    if len(record.gates) != 4:
        raise AssertionError("record must carry four gates")
    if record.gates[2].build is None:
        raise AssertionError("target gate must keep its non-null build")
    if record.gates[0].build is not None:
        raise AssertionError("D0 gate must keep its null build")
    if record.finalizedAt != "2026-07-18T10:07:00Z":
        raise AssertionError("record finalizedAt drift")
    if record.evidenceCoreDigest.bytes != fixture["coreDigest"]:
        raise AssertionError("evidenceCoreDigest must recompute exactly")
    if record.evidenceSetDigest.bytes != fixture["setDigest"]:
        raise AssertionError("evidenceSetDigest must recompute exactly")
    expected_finalization = hashlib.sha256(
        b"pf.formal-evidence-finalization.v1\x00" + fixture["recordBytes"]
    ).digest()
    if ref.schema != "proof-forge.formal-evidence-finalization.v1":
        raise AssertionError("FinalizationRef schema drift")
    if ref.id != record.id or ref.digest.bytes != expected_finalization:
        raise AssertionError("FinalizationRef must recompute exactly")
    record_ref_wire = {
        "schema": ref.schema,
        "id": ref.id,
        "digest": "sha256:" + ref.digest.bytes.hex(),
    }
    if record_ref_wire != {
        "schema": "proof-forge.formal-evidence-finalization.v1",
        "id": "EVF-20260718-0001",
        "digest": "sha256:" + expected_finalization.hex(),
    }:
        raise AssertionError("FinalizationRef wire form must be exact")


def test_record_shape_negatives(formal: ModuleType, fixture: dict) -> None:
    consumer = formal._CONSUMER
    record_wire = fixture["recordWire"]
    cases = []
    wrong_schema = copy.deepcopy(record_wire)
    wrong_schema["schema"] = "proof-forge.formal-evidence-finalization.v2"
    cases.append(("wrong record schema", consumer.canonical_pf_jcs(wrong_schema)))
    missing_field = copy.deepcopy(record_wire)
    missing_field.pop("privateScan")
    cases.append(("missing record field", consumer.canonical_pf_jcs(missing_field)))
    extra_field = copy.deepcopy(record_wire)
    extra_field["futureField"] = True
    cases.append(("extra record field", consumer.canonical_pf_jcs(extra_field)))
    bare_digest = copy.deepcopy(record_wire)
    bare_digest["hostProfile"] = "sha256:" + "11" * 32
    cases.append(("hostProfile degraded to a bare digest", consumer.canonical_pf_jcs(bare_digest)))
    wrong_id = copy.deepcopy(record_wire)
    wrong_id["id"] = "EVF-2026071-0001"
    cases.append(("malformed record id", consumer.canonical_pf_jcs(wrong_id)))
    impossible_date = copy.deepcopy(record_wire)
    impossible_date["id"] = "EVF-20260230-0001"
    cases.append(("impossible record date", consumer.canonical_pf_jcs(impossible_date)))
    dev_qualification = copy.deepcopy(record_wire)
    dev_qualification["qualification"] = "development"
    cases.append(("development qualification", consumer.canonical_pf_jcs(dev_qualification)))
    cases.append(("noncanonical record bytes", b" " + fixture["recordBytes"]))
    for label, record_bytes in cases:
        expect_rejected(
            formal,
            lambda record_bytes=record_bytes: parse_record(
                formal, fixture, record_bytes=record_bytes
            ),
            label,
        )


def rebuild_record_digests(acceptance: ModuleType, record_wire: dict) -> dict:
    consumer = acceptance._CONSUMER
    mutated = copy.deepcopy(record_wire)
    core_object = {
        key: mutated[key]
        for key in (
            "candidate",
            "hostProfile",
            "stage0Handoff",
            "sessionContainment",
            "requiredTestSet",
            "catalog",
            "catalogApproval",
            "gates",
            "freshnessAuthority",
            "revocationLedger",
            "finalizer",
            "bootstrapApproval",
        )
    }
    core_digest = hashlib.sha256(
        b"pf.formal-evidence-core.v1\x00"
        + consumer.canonical_pf_jcs(core_object)
    ).digest()
    set_digest = hashlib.sha256(
        b"pf.formal-evidence-set.v1\x00"
        + consumer.canonical_pf_jcs({
            "evidenceCoreDigest": digest_text(core_digest),
            "privateScan": mutated["privateScan"],
        })
    ).digest()
    mutated["evidenceCoreDigest"] = digest_text(core_digest)
    mutated["evidenceSetDigest"] = digest_text(set_digest)
    return mutated


def test_join_negatives(formal: ModuleType, acceptance: ModuleType, fixture: dict) -> None:
    consumer = formal._CONSUMER
    base = fixture["base"]
    record_wire = fixture["recordWire"]

    def mutated_record(mutator, label, *, rebuild=True):
        mutated = copy.deepcopy(record_wire)
        mutator(mutated)
        if rebuild:
            mutated = rebuild_record_digests(acceptance, mutated)
        expect_rejected(
            formal,
            lambda: parse_record(
                formal, fixture,
                record_bytes=consumer.canonical_pf_jcs(mutated),
            ),
            label,
        )

    mutated_record(
        lambda wire: wire.__setitem__("hostProfile", dict(wire["hostProfile"], digest=digest_text(bytes.fromhex("a1" * 32)))),
        "hostProfile ref drift",
    )
    mutated_record(
        lambda wire: wire.__setitem__("sessionContainment", dict(wire["sessionContainment"], digest=digest_text(bytes.fromhex("a2" * 32)))),
        "sessionContainment ContentRef digest drift",
    )
    mutated_record(
        lambda wire: wire.__setitem__("finalizer", dict(wire["finalizer"], digest=digest_text(bytes.fromhex("a3" * 32)))),
        "finalizer ContentRef digest drift",
    )
    mutated_record(
        lambda wire: wire["bootstrapApproval"]["verifierReceipt"].__setitem__("digest", digest_text(bytes.fromhex("a4" * 32))),
        "verifierReceipt ref digest drift",
    )
    mutated_record(
        lambda wire: wire["gates"][0].__setitem__("testIds", ["TST-DOC-001"]),
        "gates lose a required test id",
    )
    mutated_record(
        lambda wire: wire["gates"][1].__setitem__("testIds", wire["gates"][1]["testIds"] + ["TST-DOC-001"]),
        "gates duplicate a required test id",
    )
    mutated_record(
        lambda wire: wire["gates"][0].__setitem__("id", "gate-unknown"),
        "record gate id absent from catalog",
    )
    mutated_record(
        lambda wire: wire["gates"][1].__setitem__("testIds", ["TST-HOST-001", "TST-EVIDENCE-001", "TST-TOOL-001"]),
        "record gate testIds not ascending",
    )
    mutated_record(
        lambda wire: wire["gates"][2].__setitem__("build", None),
        "target gate build null",
    )
    mutated_record(
        lambda wire: wire["gates"][1]["evidenceRefs"].append(
            copy.deepcopy(wire["gates"][0]["evidenceRefs"][0])
        ),
        "duplicate evidence ref across gates",
    )

    # externalAuthorityPolicy mismatch: handoff whose policy ref drifts.
    drifted_handoff_wire = consumer.decode_canonical_pf_jcs(
        fixture["handoff"].handoffBytes
    )
    drifted_handoff_wire["authorityPolicy"]["digest"] = digest_text(
        bytes.fromhex("a5" * 32)
    )
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            stage0_handoff_bytes=consumer.canonical_pf_jcs(
                drifted_handoff_wire
            ),
        ),
        "externalAuthorityPolicy triple mismatch via drifted handoff",
    )

    # containment candidate/handoff joins (re-signed mutations).
    containment_wire = consumer.decode_canonical_pf_jcs(
        fixture["containmentBytes"]
    )
    drifted_candidate_containment = copy.deepcopy(containment_wire)
    drifted_candidate_containment["candidate"] = {
        "commit": "c" * 40,
        "treeObjectId": "b" * 40,
        "archiveDigest": digest_text(bytes.fromhex("51" * 32)),
        "digest": digest_text(bytes.fromhex("a6" * 32)),
    }
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            session_containment_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_candidate_containment,
                    ("key-quality", "key-security"), CONTAINMENT_DOMAINS,
                )
            ),
        ),
        "session containment candidate join drift",
    )
    drifted_handoff_containment = copy.deepcopy(containment_wire)
    drifted_handoff_containment["stage0Handoff"]["digest"] = digest_text(
        bytes.fromhex("a7" * 32)
    )
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            session_containment_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_handoff_containment,
                    ("key-quality", "key-security"), CONTAINMENT_DOMAINS,
                )
            ),
        ),
        "session containment handoff join drift",
    )

    # statement substitution without re-signing breaks the signature.
    substituted = copy.deepcopy(containment_wire)
    substituted["rootSessionId"] = "root-session-99"
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            session_containment_bytes=consumer.canonical_pf_jcs(substituted),
        ),
        "containment statement substitution without re-signing",
    )

    # private scan joins.
    scan_wire = consumer.decode_canonical_pf_jcs(fixture["scanBytes"])
    drifted_core_scan = copy.deepcopy(scan_wire)
    drifted_core_scan["evidenceCoreDigest"] = digest_text(bytes.fromhex("a8" * 32))
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            private_scan_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_core_scan,
                    ("key-quality", "key-security"), PRIVATE_SCAN_DOMAINS,
                )
            ),
        ),
        "private scan evidenceCoreDigest join drift",
    )
    drifted_policy_scan = copy.deepcopy(scan_wire)
    drifted_policy_scan["policy"]["digest"] = digest_text(bytes.fromhex("a9" * 32))
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            private_scan_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_policy_scan,
                    ("key-quality", "key-security"), PRIVATE_SCAN_DOMAINS,
                )
            ),
        ),
        "private scan policy join drift",
    )
    missing_ref_scan = copy.deepcopy(scan_wire)
    missing_ref_scan["scannedEvidenceRefs"] = missing_ref_scan["scannedEvidenceRefs"][:-1]
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            private_scan_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, missing_ref_scan,
                    ("key-quality", "key-security"), PRIVATE_SCAN_DOMAINS,
                )
            ),
        ),
        "private scan evidence coverage incomplete",
    )

    # freshness / revocation authority joins and rule misuse.
    freshness_wire = consumer.decode_canonical_pf_jcs(fixture["freshnessBytes"])
    drifted_freshness = copy.deepcopy(freshness_wire)
    drifted_freshness["authorityPolicy"]["digest"] = digest_text(
        bytes.fromhex("aa" * 32)
    )
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            freshness_authority_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_freshness,
                    ("key-quality", "key-release"), FRESHNESS_DOMAINS,
                )
            ),
        ),
        "freshness authority policy join drift",
    )
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            freshness_authority_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, freshness_wire,
                    ("key-quality", "key-security"), FRESHNESS_DOMAINS,
                )
            ),
        ),
        "freshness signed under the wrong policy rule",
    )
    zero_age_freshness = copy.deepcopy(freshness_wire)
    zero_age_freshness["maximumAgeSeconds"] = 0
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            freshness_authority_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, zero_age_freshness,
                    ("key-quality", "key-release"), FRESHNESS_DOMAINS,
                )
            ),
        ),
        "freshness maximumAgeSeconds zero",
    )

    revocation_wire = consumer.decode_canonical_pf_jcs(fixture["revocationBytes"])
    drifted_revocation = copy.deepcopy(revocation_wire)
    drifted_revocation["authorityPolicy"]["digest"] = digest_text(
        bytes.fromhex("ab" * 32)
    )
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            revocation_ledger_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, drifted_revocation,
                    ("key-release", "key-security"), REVOCATION_DOMAINS,
                )
            ),
        ),
        "revocation authority policy join drift",
    )
    tampered_records_digest = copy.deepcopy(revocation_wire)
    tampered_records_digest["recordsDigest"] = digest_text(bytes.fromhex("ac" * 32))
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            revocation_ledger_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, tampered_records_digest,
                    ("key-release", "key-security"), REVOCATION_DOMAINS,
                )
            ),
        ),
        "revocation recordsDigest recompute mismatch",
    )
    wrong_head = copy.deepcopy(revocation_wire)
    wrong_head["head"] = copy.deepcopy(revocation_wire["records"][0])
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            revocation_ledger_bytes=consumer.canonical_pf_jcs(
                resign_input(
                    acceptance, wrong_head,
                    ("key-release", "key-security"), REVOCATION_DOMAINS,
                )
            ),
        ),
        "revocation head is not the last record",
    )
    broken_chain_record = consumer.decode_canonical_pf_jcs(
        fixture["revocationRecordBytes"][1]
    )
    broken_chain_record["previousRecordSha256"] = "f" * 64
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            revocation_record_bytes=(
                fixture["revocationRecordBytes"][0],
                consumer.canonical_pf_jcs(broken_chain_record),
            ),
        ),
        "revocation previousRecordSha256 chain break",
    )


def test_time_and_catalog_negatives(
    formal: ModuleType, acceptance: ModuleType, fixture: dict
) -> None:
    consumer = formal._CONSUMER
    base = fixture["base"]
    record_wire = fixture["recordWire"]

    inverted = copy.deepcopy(record_wire)
    inverted["expiresAt"] = "2026-07-18T10:00:00Z"
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            record_bytes=consumer.canonical_pf_jcs(
                rebuild_record_digests(acceptance, inverted)
            ),
        ),
        "finalizedAt not before expiresAt",
    )
    malformed_time = copy.deepcopy(record_wire)
    malformed_time["finalizedAt"] = "2026-07-18 10:07:00Z"
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            record_bytes=consumer.canonical_pf_jcs(
                rebuild_record_digests(acceptance, malformed_time)
            ),
        ),
        "finalizedAt not a UtcInstant",
    )

    # development catalog qualification.
    dev_catalog = consumer.decode_canonical_pf_jcs(fixture["catalogBytes"])
    dev_catalog["qualification"] = "development"
    dev_catalog["requiredTestSet"] = None
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture,
            catalog_bytes=consumer.canonical_pf_jcs(dev_catalog),
        ),
        "catalog qualification development",
    )

    # catalog approval signed under the wrong rule membership.
    producer = acceptance._PRODUCER
    approval_statement = consumer.decode_canonical_pf_jcs(
        fixture["catalogApprovalBytes"]
    )
    approval_statement.pop("signatures", None)
    approval_digest = hashlib.sha256(
        b"pf.formal-gate-catalog-approval-statement.v1\x00"
        + consumer.canonical_pf_jcs(approval_statement)
    ).digest()
    approval_message = (
        b"pf.formal-gate-catalog-approval-signature.v1\x00" + approval_digest
    )
    wrong_rule_approval = consumer.canonical_pf_jcs({
        **approval_statement,
        "signatures": [
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": producer.sign_ed25519(
                    SEEDS_BY_KEY_ID[key_id], approval_message
                ).hex(),
            }
            for key_id in ("key-quality", "key-release")
        ],
    })
    expect_rejected(
        formal,
        lambda: parse_record(
            formal, fixture, catalog_approval_bytes=wrong_rule_approval
        ),
        "catalog approval signed without the security role",
    )

    # approval set with reordered tasks, coherently re-signed.
    set_wire = consumer.decode_canonical_pf_jcs(fixture["run"].setBytes)
    set_wire["taskApprovals"][0], set_wire["taskApprovals"][1] = (
        set_wire["taskApprovals"][1],
        set_wire["taskApprovals"][0],
    )
    statement = copy.deepcopy(set_wire)
    statement.pop("signatures", None)
    statement_digest = hashlib.sha256(
        b"pf.bootstrap-approval-set-statement.v1\x00"
        + consumer.canonical_pf_jcs(statement)
    ).digest()
    message = b"pf.bootstrap-approval-set-signature.v1\x00" + statement_digest
    reordered_set = consumer.canonical_pf_jcs({
        **statement,
        "signatures": [
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": producer.sign_ed25519(
                    SEEDS_BY_KEY_ID[key_id], message
                ).hex(),
            }
            for key_id in ("key-quality", "key-release", "key-security")
        ],
    })
    expect_rejected(
        formal,
        lambda: parse_record(formal, fixture, approval_set_bytes=reordered_set),
        "approval set with reordered tasks",
    )


def main() -> int:
    tmpdir = Path(tempfile.mkdtemp(prefix="formal-evidence-self-test-"))
    try:
        acceptance = load_module(ACCEPTANCE_PATH, ACCEPTANCE_MODULE_NAME)
        formal = load_module(FORMAL_PATH, FORMAL_MODULE_NAME)
        assert_public_api(formal)
        fixture = build_fixture(acceptance, tmpdir)
        try:
            test_positive(formal, fixture)
            test_record_shape_negatives(formal, fixture)
            test_join_negatives(formal, acceptance, fixture)
            test_time_and_catalog_negatives(formal, acceptance, fixture)
        finally:
            close_fixture(fixture)
    except (AssertionError, AttributeError, OSError, ImportError, SyntaxError) as error:
        print(f"formal-evidence-self-test: FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("formal-evidence-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
