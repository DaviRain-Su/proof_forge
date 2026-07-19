#!/usr/bin/env python3
"""Acceptance tests for the formal evidence finalizer (TASK-D0-07 slice S4).

Exercises ``scripts/formal_evidence_finalizer.py`` (single-snapshot capture,
EV content resolution, signed-input orchestration through S1/S2/S3, record
produce/publish, support binding, end-to-end re-verification) over an
all-fixture authority chain.  All seeds are public RFC 8032 test vectors
(fixture namespace, ADR-0018); fixture trees live only in a temp directory.
Every failure path must yield PF-EVIDENCE-FORMAL-UNVERIFIED and zero output.
"""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parent
ACCEPTANCE_PATH = REPO_ROOT / "bootstrap_acceptance.py"
FORMAL_PATH = REPO_ROOT / "formal_evidence.py"
EV_CORE_PATH = REPO_ROOT / "evidence_v1_core.py"
S1_PATH = REPO_ROOT / "revocation_ledger.py"
FINALIZER_PATH = REPO_ROOT / "formal_evidence_finalizer.py"
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
FINALIZER_EXE = b"formal-evidence-finalizer fixture executable v1\n"
EV_ALPHA = "EV-20260718-0001"
EV_BETA = "EV-20260718-0002"
EV_EXTRA = "EV-20260718-0003"
RECORD_ID = "EVF-20260719-0001"
FINALIZED_AT = "2026-07-19T00:30:00Z"
OBSERVED_AT = "2026-07-19T00:00:00Z"
MAX_AGE = 3600
EXPECTED_EXPIRY = "2026-07-19T01:00:00Z"
CLOCK_DECLARATION = b"fixture local clock declaration\nsource: monotonic+utc\n"
SCAN_POLICY = {
    "schema": "proof-forge.private-scan-policy.v1",
    "id": "bootstrap-acceptance-private-scan",
    "version": "1.0.0",
    "denyContentMarkers": [
        "BEGIN OPENSSH PRIVATE KEY",
        "BEGIN PGP PRIVATE KEY BLOCK",
        "BEGIN PRIVATE KEY",
        "aws_secret_access_key",
        "xoxb-",
    ],
    "denyPathMarkers": [".env", ".key", ".p12", ".pem", "id_ed25519", "id_rsa"],
    "maximumFindings": 0,
}
GATE_ALPHA_BUILD = {
    "targetId": "noir",
    "targetSemanticsVersion": "1.0.0",
    "targetSemanticsDigest": "sha256:" + "94" * 32,
    "codegenProfileId": "noir-acir",
    "codegenProfileDigest": "sha256:" + "95" * 32,
}
GATE_BETA_BUILD = {
    "targetId": "noir",
    "targetSemanticsVersion": "1.1.0",
    "targetSemanticsDigest": "sha256:" + "96" * 32,
    "codegenProfileId": "noir-acir",
    "codegenProfileDigest": "sha256:" + "97" * 32,
}
SUPPORT_CLAIM = {
    "requirement": {
        "id": "counter.increment",
        "version": "1.0.0",
        "digest": "sha256:" + hashlib.sha256(b"fixture requirement").hexdigest(),
    },
    "predicates": [
        {"variant": "uint-at-least", "name": "count", "value": 1},
    ],
}

CHECKS = 0


def load_module(path: Path, name: str) -> ModuleType:
    assert sys.flags.isolated, "formal-finalizer self-test requires -I"
    assert sys.flags.no_site, "formal-finalizer self-test requires -S"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def checked(label: str) -> None:
    global CHECKS
    CHECKS += 1
    print(f"ok: {label}")


def digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def scan_policy_bytes() -> bytes:
    return json.dumps(SCAN_POLICY, sort_keys=True, indent=2).encode() + b"\n"


def build_evidence_doc(
    ev_core: ModuleType,
    *,
    ev_id: str,
    gate_id: str,
    task_id: str,
    test_ids: tuple,
    qualification: str,
    commit: str,
    tree: str,
    archive_sha: str,
    archive_size: int,
    members: dict,
    artifact_target: str,
    result: str = "passed",
) -> bytes:
    attempt_exit = 0 if result == "passed" else 1
    inputs = [
        {
            "role": "candidate-archive",
            "path": "candidate/archive.tar",
            "sha256": archive_sha,
            "size": archive_size,
        }
    ]
    for role, path in members.get("inputs", ()):
        inputs.append(
            {
                "role": role,
                "path": path,
                "sha256": hashlib.sha256(members["files"][path]).hexdigest(),
                "size": len(members["files"][path]),
            }
        )
    artifacts = [
        {
            "target": artifact_target,
            "role": "circuit",
            "path": path,
            "mediaType": "application/octet-stream",
            "sha256": hashlib.sha256(members["files"][path]).hexdigest(),
            "size": len(members["files"][path]),
            "retained": True,
        }
        for path in members.get("artifacts", ())
    ]
    logs = [
        {
            "path": path,
            "sha256": hashlib.sha256(members["files"][path]).hexdigest(),
            "size": len(members["files"][path]),
            "truncated": False,
            "privateDataScan": "passed",
        }
        for path in members.get("logs", ())
    ]
    document = {
        "schema": "proof-forge.evidence.v1",
        "id": ev_id,
        "gate": {
            "id": gate_id,
            "taskId": task_id,
            "testIds": sorted(test_ids),
            "qualification": qualification,
        },
        "repository": {
            "commit": commit,
            "subtree": ".",
            "treeObjectId": tree,
            "anchorSource": "external",
            "dirty": False,
            "dirtyDigest": None,
            "unchangedDuringRun": True,
            "archive": {
                "format": "git-tar",
                "sha256": archive_sha,
                "size": archive_size,
            },
        },
        "hostAttestation": {
            "scope": "local-point-in-time",
            "remoteAttestation": False,
            "profileId": "s4-fixture-host",
            "eligibleForHermetic": True,
            "bootstrapLockSha256": "11" * 32,
            "hostProfileLockSha256": "22" * 32,
            "toolchainLockSha256": "33" * 32,
            "launcherSha256": "44" * 32,
            "verifierSha256": "55" * 32,
            "observationSha256": "66" * 32,
        },
        "environment": {
            "os": "linux 7.0.0",
            "arch": "x86_64",
            "environmentSha256": "77" * 32,
            "sourceDateEpoch": 0,
            "cleanRoom": True,
            "buildCache": "empty",
            "assetCache": "locked-read-only",
        },
        "sandboxPolicies": [
            {
                "id": "core-no-network",
                "engine": "sandbox-exec",
                "engineSha256": "88" * 32,
                "defaultAction": "deny",
                "network": "deny-all",
                "templateSha256": "99" * 32,
                "renderedSha256": "aa" * 32,
                "probes": [{"id": "network-denied", "status": "passed"}],
            }
        ],
        "tools": [
            {
                "id": "fixture-tool",
                "version": "1.0.0",
                "source": "content-addressed-cache",
                "assetSha256": "bb" * 32,
                "executableSha256": "cc" * 32,
                "closureSha256": "dd" * 32,
            }
        ],
        "command": {
            "argv": ["scripts/fixture_gate.sh"],
            "cwdRelative": ".",
            "startedUtc": "2026-07-18T08:59:00Z",
            "endedUtc": "2026-07-18T09:00:00Z",
            "durationMs": 60,
            "attempts": [
                {
                    "number": 1,
                    "exitCode": attempt_exit,
                    "signal": None,
                    "timedOut": False,
                    "stdoutLog": members["logs"][0],
                    "stderrLog": members["logs"][0],
                }
            ],
        },
        "inputs": inputs,
        "artifacts": artifacts,
        "artifactSetSha256": "",
        "observations": [
            {
                "step": "fixture-gate-run",
                "status": "passed",
                "return": 0,
                "logicalState": {"gate": gate_id},
                "effects": [],
                "errorClass": None,
            }
        ],
        "logs": logs,
        "result": result,
        "skipAuthorization": None,
    }
    document["artifactSetSha256"] = ev_core.artifact_set_sha256(
        document["artifacts"]
    )
    document_bytes = ev_core.canonical_bytes(document)
    ev_core.validate_evidence(ev_core.decode_json(document_bytes))
    return document_bytes


def build_fixture(acceptance: ModuleType, ev_core: ModuleType,
                  root: Path) -> dict:
    consumer = acceptance._CONSUMER
    producer = acceptance._PRODUCER
    base = acceptance.build_rehearsal_base(
        namespace_id="s4-finalizer-fixture-namespace",
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=SERVICE_SEED,
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=json.dumps(
            {
                "attestationScope": "local-observation-only",
                "eligibleForHermetic": True,
                "hostProfileId": "s4-fixture-host",
                "platform": {"secureBoot": "enabled"},
                "remoteAttestation": False,
                "trustRoot": "synthetic fixture",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        profile_bytes=json.dumps(
            {"id": "s4-fixture-host"}, sort_keys=True, separators=(",", ":")
        ).encode("utf-8"),
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    base = dataclasses.replace(
        base,
        tcbDigests=(
            base.tcbDigests[0],
            base.tcbDigests[1],
            base.tcbDigests[2],
            hashlib.sha256(FINALIZER_EXE).digest(),
        ),
    )
    seed_dir = root / "fixture-seed"
    seed_dir.mkdir(parents=True)
    (seed_dir / "policy.json").write_bytes(base.policyBytes)
    (seed_dir / "archive.tar").write_bytes(base.archiveBytes)
    (seed_dir / "manifest.json").write_bytes(base.manifestBytes)
    handoff = acceptance.produce_run_handoff(
        base,
        handoff_id="s4-fixture-stage0-handoff",
        handoff_version="1.0.0",
        run_id="s4-fixture-run",
        policy_path=str(seed_dir / "policy.json"),
        archive_path=str(seed_dir / "archive.tar"),
        manifest_path=str(seed_dir / "manifest.json"),
    )
    run = acceptance.produce_run_objects(
        base,
        handoff,
        run_id="s4-fixture-run",
        nonce="ee" * 32,
        seeds_by_key_id=SEEDS_BY_KEY_ID,
    )
    for fd in (
        handoff.channels.authorityPolicyFd,
        handoff.channels.authorityStoreFd,
        handoff.channels.candidateArchiveFd,
        handoff.channels.evidenceRootFd,
        handoff.channels.authorityStoreServiceFd,
    ):
        try:
            import os
            os.close(fd)
        except OSError:
            pass

    archive_sha = hashlib.sha256(base.archiveBytes).hexdigest()
    archive_size = len(base.archiveBytes)
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "s4-fixture-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": {
            "schema": base.requiredRef.schema,
            "id": base.requiredRef.id,
            "version": base.requiredRef.version,
            "digest": digest_text(base.requiredRef.digest.bytes),
        },
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
                "taskId": "TASK-D1-01",
                "testIds": ["TST-DOC-001", "TST-ISO-001"],
            },
            {
                "id": "gate-beta",
                "taskId": "TASK-D1-02",
                "testIds": [
                    "TST-BOOTSTRAP-001",
                    "TST-COMMON-001",
                    "TST-EVIDENCE-001",
                    "TST-HOST-001",
                    "TST-SBOM-001",
                    "TST-TOOL-001",
                ],
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
    catalog_approval_bytes = producer.produce_formal_gate_catalog_approval(
        id="s4-fixture-catalog-approval",
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

    alpha_members = {
        "inputs": (("spec", "spec/alpha.txt"),),
        "artifacts": ("out/alpha.acir",),
        "logs": ("logs/alpha.log",),
        "files": {
            "spec/alpha.txt": b"fixture alpha spec\n",
            "out/alpha.acir": b"\x00alpha circuit bytes",
            "logs/alpha.log": b"alpha run log\n",
        },
    }
    beta_members = {
        "inputs": (),
        "artifacts": ("out/beta.acir",),
        "logs": ("logs/beta.log",),
        "files": {
            "out/beta.acir": b"\x01beta circuit bytes",
            "logs/beta.log": b"beta run log\n",
        },
    }
    ev_alpha_bytes = build_evidence_doc(
        ev_core,
        ev_id=EV_ALPHA,
        gate_id="gate-alpha",
        task_id="TASK-D1-01",
        test_ids=("TST-DOC-001", "TST-ISO-001"),
        qualification="formal",
        commit=base.candidateCommit,
        tree=base.candidateTreeObjectId,
        archive_sha=archive_sha,
        archive_size=archive_size,
        members=alpha_members,
        artifact_target="noir",
    )
    ev_beta_bytes = build_evidence_doc(
        ev_core,
        ev_id=EV_BETA,
        gate_id="gate-beta",
        task_id="TASK-D1-02",
        test_ids=(
            "TST-BOOTSTRAP-001", "TST-COMMON-001", "TST-EVIDENCE-001",
            "TST-HOST-001", "TST-SBOM-001", "TST-TOOL-001",
        ),
        qualification="formal",
        commit=base.candidateCommit,
        tree=base.candidateTreeObjectId,
        archive_sha=archive_sha,
        archive_size=archive_size,
        members=beta_members,
        artifact_target="noir",
    )

    fixture = root / "fixture"
    (fixture / "approvals").mkdir(parents=True)
    (fixture / "receipts").mkdir(parents=True)
    (fixture / "evidence").mkdir(parents=True)
    (fixture / "revocation").mkdir(parents=True)
    (fixture / "members" / "candidate").mkdir(parents=True)
    (fixture / "members" / "spec").mkdir(parents=True)
    (fixture / "members" / "out").mkdir(parents=True)
    (fixture / "members" / "logs").mkdir(parents=True)
    (fixture / "authority-policy.json").write_bytes(base.policyBytes)
    (fixture / "required-test-set.json").write_bytes(base.requiredBytes)
    (fixture / "phase5-snapshot.json").write_bytes(
        json.dumps(
            {
                "id": base.phase5Snapshot.id,
                "path": base.phase5Snapshot.path,
                "bytesHex": base.phase5Snapshot.bytes.hex(),
            },
            sort_keys=True,
        ).encode()
    )
    (fixture / "catalog.json").write_bytes(catalog_bytes)
    (fixture / "catalog-approval.json").write_bytes(catalog_approval_bytes)
    (fixture / "eligible-stage0-handoff.json").write_bytes(handoff.handoffBytes)
    (fixture / "approval-set.json").write_bytes(run.setBytes)
    (fixture / "activation-receipt.json").write_bytes(run.activationBytes)
    for task_id in (
        "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
        "TASK-D0-04", "TASK-D0-05", "TASK-D0-06",
    ):
        (fixture / "approvals" / f"{task_id.lower()}-approval.json").write_bytes(
            run.approvalBytes[task_id]
        )
        (fixture / "receipts" / f"{task_id.lower()}-receipt.json").write_bytes(
            run.receiptBytes[task_id]
        )
    (fixture / "evidence" / f"{EV_ALPHA}.json").write_bytes(ev_alpha_bytes)
    (fixture / "evidence" / f"{EV_BETA}.json").write_bytes(ev_beta_bytes)
    (fixture / "members" / "candidate" / "archive.tar").write_bytes(
        base.archiveBytes
    )
    for members in (alpha_members, beta_members):
        for relative, payload in members["files"].items():
            (fixture / "members" / relative).write_bytes(payload)

    gate_inputs = {
        "gate-alpha": {
            "build": GATE_ALPHA_BUILD,
            "evidenceRefs": [
                {"id": EV_ALPHA, "digest": digest_text(
                    hashlib.sha256(ev_alpha_bytes).digest()
                )},
            ],
        },
        "gate-beta": {
            "build": GATE_BETA_BUILD,
            "evidenceRefs": [
                {"id": EV_BETA, "digest": digest_text(
                    hashlib.sha256(ev_beta_bytes).digest()
                )},
            ],
        },
    }
    return {
        "base": base,
        "run": run,
        "handoff": handoff,
        "fixture": fixture,
        "gate_inputs": gate_inputs,
        "ev_alpha_bytes": ev_alpha_bytes,
        "ev_beta_bytes": ev_beta_bytes,
    }


def call_finalizer(module: ModuleType, fixture: dict, trusted_root: Path,
                   **overrides: object) -> object:
    kwargs = {
        "fixture_root": str(fixture["fixture"]),
        "trusted_root": str(trusted_root),
        "record_id": RECORD_ID,
        "finalized_at": FINALIZED_AT,
        "observed_at": OBSERVED_AT,
        "maximum_age_seconds": MAX_AGE,
        "clock_source_bytes": CLOCK_DECLARATION,
        "containment_observation": {
            "supervisor_digest": digest_text(bytes.fromhex("81" * 32)),
            "root_session_id": "root-session-01",
            "descendants": (
                {
                    "pid": 101,
                    "parentPid": 1,
                    "startToken": 11,
                    "sessionId": 501,
                    "executableDigest": digest_text(bytes.fromhex("82" * 32)),
                    "termination": "exited",
                },
            ),
            "escape_probes": ({"id": "escape-probe-01", "result": "contained"},),
            "started_at": "2026-07-19T00:00:00Z",
            "finished_at": "2026-07-19T00:20:00Z",
        },
        "finalizer_executable_bytes": FINALIZER_EXE,
        "finalizer_identity_id": "s4-fixture-finalizer",
        "finalizer_closure_digest": digest_text(bytes.fromhex("85" * 32)),
        "finalizer_toolchain_lock_digest": digest_text(bytes.fromhex("86" * 32)),
        "scan_policy_bytes": scan_policy_bytes(),
        "gate_inputs": fixture["gate_inputs"],
        "signers": dict(SEEDS_BY_KEY_ID),
        "support": {
            "evidence_id": EV_ALPHA,
            "build": GATE_ALPHA_BUILD,
            "support_claim": SUPPORT_CLAIM,
            "gate_vectors": (
                {"gateId": "gate-alpha", "evidenceId": EV_ALPHA,
                 "grade": "local_runtime"},
                {"gateId": "gate-beta", "evidenceId": EV_BETA,
                 "grade": "local_runtime"},
            ),
        },
    }
    kwargs.update(overrides)
    return module.finalize_formal_evidence(**kwargs)


def expect_failure(module: ModuleType, label: str, operation,
                   trusted_root: Path) -> None:
    try:
        result = operation()
    except module.FormalFinalizerError as error:
        if error.code != "PF-EVIDENCE-FORMAL-UNVERIFIED":
            raise AssertionError(f"{label} raised {error.code}: {error.detail}")
        leftovers = [p for p in trusted_root.rglob("*") if p.is_file()]
        if leftovers:
            raise AssertionError(
                f"{label} left outputs behind: {[str(p) for p in leftovers]}"
            )
        checked(label)
        return
    raise AssertionError(f"{label} must fail; got {result!r}")


def main() -> int:
    acceptance = load_module(
        ACCEPTANCE_PATH, "proof_forge_bootstrap_acceptance_for_s4_test"
    )
    formal = load_module(FORMAL_PATH, "proof_forge_formal_evidence_for_s4_test")
    ev_core = load_module(EV_CORE_PATH, "proof_forge_evidence_core_for_s4_test")
    s1 = load_module(S1_PATH, "proof_forge_revocation_ledger_for_s4_test")
    module = load_module(
        FINALIZER_PATH, "proof_forge_formal_evidence_finalizer_under_test"
    )
    consumer = acceptance._CONSUMER

    for name in (
        "finalize_formal_evidence",
        "FinalizeOutcome",
        "FormalFinalizerError",
        "MAX_CAPTURE_FILE_BYTES",
    ):
        assert getattr(module, name, None) is not None, f"missing {name}"
    checked("public API surface")

    with tempfile.TemporaryDirectory(prefix="formal-finalizer-test-") as temporary:
        workspace = Path(temporary)
        built = build_fixture(acceptance, ev_core, workspace)
        fixture = built["fixture"]
        base = built["base"]

        def fresh_root(name: str) -> Path:
            root = workspace / name
            root.mkdir()
            return root

        # Positive: full produce + publish + re-verify pipeline.
        trusted = fresh_root("trusted-positive")
        outcome = call_finalizer(module, built, trusted)
        record_path = Path(outcome.recordPath)
        expected_record_path = (
            trusted / "finalized-formal" / "s4-fixture-catalog"
            / "bootstrap-acceptance-required-tests" / f"{RECORD_ID}.json"
        )
        assert record_path == expected_record_path, (
            f"record path {record_path} != {expected_record_path}"
        )
        assert record_path.read_bytes() == outcome.recordBytes
        receipt_path = record_path.with_suffix(".receipt.json")
        assert receipt_path.is_file()
        assert record_path.stat().st_mode & 0o777 == 0o444
        binding_path = Path(outcome.bindingPath)
        assert binding_path.is_file()
        assert binding_path.read_bytes() == outcome.bindingBytes
        assert binding_path.with_suffix(".receipt.json").is_file()
        # End-to-end: the published record re-verifies against the captured inputs.
        record, ref = formal.parse_formal_evidence_finalization(
            record_path.read_bytes(),
            base.policyBytes,
            base.requiredBytes,
            formal._CONSUMER.BootstrapDocumentSnapshotV1(
                id=base.phase5Snapshot.id,
                path=base.phase5Snapshot.path,
                bytes=base.phase5Snapshot.bytes,
            ),
            (fixture / "catalog.json").read_bytes(),
            (fixture / "catalog-approval.json").read_bytes(),
            outcome.containmentBytes,
            outcome.freshnessBytes,
            outcome.privateScanBytes,
            outcome.revocationLedgerBytes,
            (),
            outcome.finalizerIdentityBytes,
            (fixture / "approval-set.json").read_bytes(),
            tuple(
                (fixture / "receipts" / f"task-d0-0{index}-receipt.json").read_bytes()
                for index in range(1, 7)
            ),
            (fixture / "activation-receipt.json").read_bytes(),
            (fixture / "eligible-stage0-handoff.json").read_bytes(),
        )
        assert ref.id == RECORD_ID
        assert record.qualification == "formal"
        assert tuple(gate.id for gate in record.gates) == ("gate-alpha", "gate-beta")
        checked("positive pipeline: produce+publish+layout+full re-verify")

        # Positive: end-to-end consumer re-verification of published artifacts.
        formal_policy = formal._CONSUMER.parse_bootstrap_authority_policy(
            base.policyBytes
        )[0]
        containment = formal.parse_session_containment_receipt(
            outcome.containmentBytes, formal_policy
        )
        assert containment.candidate.commit == base.candidateCommit
        freshness = formal.parse_freshness_authority_snapshot(
            outcome.freshnessBytes, formal_policy
        )
        assert freshness.clockSourceDigest.bytes == hashlib.sha256(
            CLOCK_DECLARATION
        ).digest()
        scan = formal.parse_private_scan_receipt(
            outcome.privateScanBytes, formal_policy
        )
        assert scan.policy.id == "bootstrap-acceptance-private-scan"
        assert tuple(ref[0] for ref in scan.scannedEvidenceRefs) == (
            EV_ALPHA, EV_BETA
        )
        revocation = formal.parse_revocation_ledger_snapshot(
            outcome.revocationLedgerBytes, formal_policy, ()
        )
        assert revocation.head is None
        identity = formal.parse_formal_finalizer_identity(
            outcome.finalizerIdentityBytes
        )
        assert identity.executableDigest.bytes == hashlib.sha256(
            FINALIZER_EXE
        ).digest()
        assert outcome.expiresAt == EXPECTED_EXPIRY
        checked("positive: signed inputs parse + freshness expiry relation")

        # Negative: publication no-clobber on rerun (originals stay intact).
        try:
            call_finalizer(module, built, trusted)
            raise AssertionError("rerun publication must fail")
        except module.FormalFinalizerError as error:
            if error.code != "PF-EVIDENCE-FORMAL-UNVERIFIED":
                raise AssertionError(f"rerun raised {error.code}")
        assert record_path.read_bytes() == outcome.recordBytes
        checked("publication rerun is no-clobber (originals intact)")

        # Each negative gets a pristine copy of the fixture tree.
        def negative_case(name: str, mutate, label: str,
                          trusted_name: str | None = None) -> None:
            case_dir = workspace / f"case-{name}"
            shutil.copytree(fixture, case_dir)
            case_built = dict(built)
            case_built["fixture"] = case_dir
            mutate(case_built)
            expect_failure(
                module,
                label,
                lambda: call_finalizer(
                    module, case_built, fresh_root(trusted_name or f"trusted-{name}")
                ),
                fresh_root(f"verify-{name}"),
            )

        def gate_ref_mutation(built_case, gate_id, index, digest):
            built_case["gate_inputs"] = {
                key: dict(value) for key, value in built_case["gate_inputs"].items()
            }
            refs = list(built_case["gate_inputs"][gate_id]["evidenceRefs"])
            refs[index] = {"id": refs[index]["id"], "digest": digest}
            built_case["gate_inputs"][gate_id]["evidenceRefs"] = refs

        def gate_ref_mutation_id(built_case, gate_id, index, evidence_id):
            built_case["gate_inputs"] = {
                key: dict(value) for key, value in built_case["gate_inputs"].items()
            }
            refs = list(built_case["gate_inputs"][gate_id]["evidenceRefs"])
            refs[index] = {
                "id": evidence_id,
                "digest": digest_text(hashlib.sha256(b"absent").digest()),
            }
            built_case["gate_inputs"][gate_id]["evidenceRefs"] = refs

        negative_case(
            "ev-digest-mismatch",
            lambda case: gate_ref_mutation(
                case, "gate-alpha", 0, digest_text(bytes(32))
            ),
            "EV digest mismatch vs declared evidenceRef",
        )
        negative_case(
            "ev-qualification",
            lambda case: (case["fixture"] / "evidence" / f"{EV_BETA}.json").write_bytes(
                build_evidence_doc(
                    ev_core, ev_id=EV_BETA, gate_id="gate-beta",
                    task_id="TASK-D1-02",
                    test_ids=("TST-BOOTSTRAP-001", "TST-COMMON-001",
                              "TST-EVIDENCE-001", "TST-HOST-001",
                              "TST-SBOM-001", "TST-TOOL-001"),
                    qualification="development",
                    commit=base.candidateCommit,
                    tree=base.candidateTreeObjectId,
                    archive_sha=hashlib.sha256(base.archiveBytes).hexdigest(),
                    archive_size=len(base.archiveBytes),
                    members={
                        "inputs": (), "artifacts": ("out/beta.acir",),
                        "logs": ("logs/beta.log",),
                        "files": {
                            "out/beta.acir": b"\x01beta circuit bytes",
                            "logs/beta.log": b"beta run log\n",
                        },
                    },
                    artifact_target="noir",
                )
            ),
            "EV qualification==development on a formal gate rejected",
        )
        negative_case(
            "ev-result",
            lambda case: (case["fixture"] / "evidence" / f"{EV_ALPHA}.json").write_bytes(
                build_evidence_doc(
                    ev_core, ev_id=EV_ALPHA, gate_id="gate-alpha",
                    task_id="TASK-D1-01",
                    test_ids=("TST-DOC-001", "TST-ISO-001"),
                    qualification="formal",
                    commit=base.candidateCommit,
                    tree=base.candidateTreeObjectId,
                    archive_sha=hashlib.sha256(base.archiveBytes).hexdigest(),
                    archive_size=len(base.archiveBytes),
                    members={
                        "inputs": (("spec", "spec/alpha.txt"),),
                        "artifacts": ("out/alpha.acir",),
                        "logs": ("logs/alpha.log",),
                        "files": {
                            "spec/alpha.txt": b"fixture alpha spec\n",
                            "out/alpha.acir": b"\x00alpha circuit bytes",
                            "logs/alpha.log": b"alpha run log\n",
                        },
                    },
                    artifact_target="noir",
                    result="failed",
                )
            ),
            "EV result!=passed rejected",
        )
        negative_case(
            "ev-missing",
            lambda case: gate_ref_mutation_id(
                case, "gate-alpha", 0, "EV-20260718-0099"
            ),
            "gate evidenceRef missing from the bundle rejected",
        )
        negative_case(
            "ev-extra",
            lambda case: (case["fixture"] / "evidence" / f"{EV_EXTRA}.json").write_bytes(
                (case["fixture"] / "evidence" / f"{EV_ALPHA}.json").read_bytes()
            ),
            "extra bundle EV unreferenced by any gate rejected",
        )
        negative_case(
            "member-drift",
            lambda case: (case["fixture"] / "members" / "out" / "alpha.acir").write_bytes(
                b"drifted member bytes"
            ),
            "member bytes drift vs EV declaration rejected",
        )
        negative_case(
            "member-extra",
            lambda case: (case["fixture"] / "members" / "out" / "extra.bin").write_bytes(
                b"extra"
            ),
            "undeclared member file in bundle rejected (exact set)",
        )
        negative_case(
            "scan-finding",
            lambda case: (case["fixture"] / "members" / "spec" / "alpha.txt").write_bytes(
                b"-----BEGIN PRIVATE KEY-----\n"
            ),
            "private scan content finding rejected",
        )
        negative_case(
            "revoked-ev",
            lambda case: (case["fixture"] / "revocation" / "RVK-20260718-0001.json").write_bytes(
                s1.produce_revocation_record(
                    id="RVK-20260718-0001",
                    evidence_id=EV_ALPHA,
                    evidence_sha256=hashlib.sha256(
                        built["ev_alpha_bytes"]
                    ).hexdigest(),
                    revoked_utc="2026-07-18T09:30:00Z",
                    reason_code="incorrect",
                    reason="fixture revocation of the alpha evidence",
                    authority_ref="revocation-authority-alpha",
                    replacement=None,
                    previous_record_sha256="0" * 64,
                )
            ),
            "revoked EV referenced by a gate rejected",
        )
        def swap_handoff(case):
            produced = acceptance.produce_run_handoff(
                base,
                handoff_id="s4-fixture-handoff-swap",
                handoff_version="1.0.0",
                run_id="s4-fixture-run-swap",
                policy_path=str(workspace / "fixture-seed" / "policy.json"),
                archive_path=str(workspace / "fixture-seed" / "archive.tar"),
                manifest_path=str(workspace / "fixture-seed" / "manifest.json"),
            )
            import os
            for fd in (
                produced.channels.authorityPolicyFd,
                produced.channels.authorityStoreFd,
                produced.channels.candidateArchiveFd,
                produced.channels.evidenceRootFd,
                produced.channels.authorityStoreServiceFd,
            ):
                try:
                    os.close(fd)
                except OSError:
                    pass
            (case["fixture"] / "eligible-stage0-handoff.json").write_bytes(
                produced.handoffBytes
            )

        negative_case(
            "handoff-swap",
            swap_handoff,
            "swapped handoff breaks the set/receipt joins",
        )
        negative_case(
            "member-missing",
            lambda case: (case["fixture"] / "members" / "out" / "alpha.acir").unlink(),
            "scanned member missing from the bundle rejected",
        )
        negative_case(
            "phase5-tamper",
            lambda case: (case["fixture"] / "phase5-snapshot.json").write_bytes(
                b'{"id":"PHASE-5","path":"docs/05-test-spec.md","bytesHex":"00"}'
            ),
            "tampered phase5 snapshot rejected (document-bound join)",
        )
        negative_case(
            "ev-malformed",
            lambda case: (case["fixture"] / "evidence" / f"{EV_ALPHA}.json").write_bytes(
                b'{"schema":"proof-forge.evidence.v1","id":"' + EV_ALPHA.encode() + b'"}'
            ),
            "malformed EV document rejected",
        )
        negative_case(
            "revocation-chain",
            lambda case: [
                (case["fixture"] / "revocation" / "RVK-20260718-0001.json").write_bytes(
                    s1.produce_revocation_record(
                        id="RVK-20260718-0001",
                        evidence_id="EV-20260717-0001",
                        evidence_sha256=hashlib.sha256(b"fixture:ev1").hexdigest(),
                        revoked_utc="2026-07-18T09:30:00Z",
                        reason_code="incorrect",
                        reason="fixture revocation one",
                        authority_ref="revocation-authority-alpha",
                        replacement=None,
                        previous_record_sha256="0" * 64,
                    )
                ),
                (case["fixture"] / "revocation" / "RVK-20260718-0002.json").write_bytes(
                    s1.produce_revocation_record(
                        id="RVK-20260718-0002",
                        evidence_id="EV-20260717-0002",
                        evidence_sha256=hashlib.sha256(b"fixture:ev2").hexdigest(),
                        revoked_utc="2026-07-18T09:31:00Z",
                        reason_code="superseded",
                        reason="fixture revocation two with a broken link",
                        authority_ref="revocation-authority-alpha",
                        replacement=("EV-20260717-0003", hashlib.sha256(b"fixture:ev3").hexdigest()),
                        previous_record_sha256="0" * 64,
                    )
                ),
            ],
            "broken revocation chain link rejected",
        )

        # Support binding gate-vector coverage via call override.
        expect_failure(
            module,
            "support binding gate vectors must cover every gate",
            lambda: call_finalizer(
                module, built, fresh_root("trusted-vector"),
                support={
                    "evidence_id": EV_ALPHA,
                    "build": GATE_ALPHA_BUILD,
                    "support_claim": SUPPORT_CLAIM,
                    "gate_vectors": (
                        {"gateId": "gate-alpha", "evidenceId": EV_ALPHA,
                         "grade": "local_runtime"},
                    ),
                },
            ),
            fresh_root("verify-vector"),
        )
        expect_failure(
            module,
            "record id must use the EVF grammar",
            lambda: call_finalizer(
                module, built, fresh_root("trusted-record-id"),
                record_id="not-an-evf-id",
            ),
            fresh_root("verify-record-id"),
        )
        negative_case(
            "catalog-approval-tamper",
            lambda case: (case["fixture"] / "catalog-approval.json").write_bytes(
                bytes([case["fixture"].joinpath("catalog-approval.json").read_bytes()[0] ^ 0x01])
                + case["fixture"].joinpath("catalog-approval.json").read_bytes()[1:]
            ),
            "tampered catalog approval rejected",
        )
        negative_case(
            "required-set-tamper",
            lambda case: (case["fixture"] / "required-test-set.json").write_bytes(
                bytes([case["fixture"].joinpath("required-test-set.json").read_bytes()[0] ^ 0x01])
                + case["fixture"].joinpath("required-test-set.json").read_bytes()[1:]
            ),
            "tampered required test set rejected (4-way join)",
        )
        negative_case(
            "missing-receipt",
            lambda case: (case["fixture"] / "receipts" / "task-d0-04-receipt.json").unlink(),
            "six-item set missing one receipt rejected",
        )
        negative_case(
            "wrong-candidate",
            lambda case: (case["fixture"] / "evidence" / f"{EV_ALPHA}.json").write_bytes(
                build_evidence_doc(
                    ev_core, ev_id=EV_ALPHA, gate_id="gate-alpha",
                    task_id="TASK-D1-01",
                    test_ids=("TST-DOC-001", "TST-ISO-001"),
                    qualification="formal",
                    commit="f" * 40,
                    tree=base.candidateTreeObjectId,
                    archive_sha=hashlib.sha256(base.archiveBytes).hexdigest(),
                    archive_size=len(base.archiveBytes),
                    members={
                        "inputs": (("spec", "spec/alpha.txt"),),
                        "artifacts": ("out/alpha.acir",),
                        "logs": ("logs/alpha.log",),
                        "files": {
                            "spec/alpha.txt": b"fixture alpha spec\n",
                            "out/alpha.acir": b"\x00alpha circuit bytes",
                            "logs/alpha.log": b"alpha run log\n",
                        },
                    },
                    artifact_target="noir",
                )
            ),
            "EV with wrong candidate rejected",
        )

        # Direct finalizer-drift and freshness-stale cases via call overrides.
        expect_failure(
            module,
            "finalizer executable digest mismatch vs handoff tcb",
            lambda: call_finalizer(
                module, built, fresh_root("trusted-finalizer-drift-2"),
                finalizer_executable_bytes=b"different executable\n",
            ),
            fresh_root("verify-finalizer-drift-2"),
        )
        expect_failure(
            module,
            "freshness stale finalizedAt==expiresAt",
            lambda: call_finalizer(
                module, built, fresh_root("trusted-stale-2"),
                finalized_at=EXPECTED_EXPIRY,
            ),
            fresh_root("verify-stale-2"),
        )

    print(f"formal-evidence-finalizer-self-test: ok ({CHECKS} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
