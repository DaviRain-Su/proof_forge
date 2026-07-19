#!/usr/bin/env python3
"""TST-EVIDENCE-002 fixture acceptance rehearsal (TASK-D0-07 slice S5).

Proves the whole formal-evidence chain in one fixture namespace (ADR-0018):
fixture authority-store service, required-test-set and catalog-approval
publish/readback, catalog authority verification, fixture formal EV bundle,
the five signed inputs through the S1/S2/S3 producers, the S4 single
-snapshot finalization orchestrator producing and publishing the formal
record and a support binding, and end-to-end consumer re-verification.  The
fixture identity (policy id, store namespace, runId/nonce, candidate,
handoff) is deliberately disjoint from every production lookup tuple; using
a production id is rejected before any work starts.

The rehearsal composes the committed modules (bootstrap_acceptance,
formal_evidence, formal_evidence_producer, formal_evidence_finalizer,
revocation_ledger, private_scan, formal_input_producers,
evidence_v1_core); it does not reimplement any of them.  Seeds arrive only
as explicit 32-byte parameters and never appear in outputs.  Nothing here
is formal or hermetic evidence.
"""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Mapping, NoReturn, Optional, Tuple


def _load_module(path: Path, name: str) -> ModuleType:
    """Load an exact sibling module without a sys.path authority seam."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError(f"exact sibling loader is unavailable: {path.name}")
    if Path(spec.origin).resolve(strict=True) != path.resolve(strict=True):
        raise ImportError(f"exact sibling origin changed: {path.name}")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the defining module.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_MODULE_PATH = Path(__file__).resolve(strict=True)
_ACCEPTANCE = _load_module(
    _MODULE_PATH.with_name("bootstrap_acceptance.py"),
    "proof_forge_bootstrap_acceptance_for_formal_rehearsal",
)
_FINALIZER = _load_module(
    _MODULE_PATH.with_name("formal_evidence_finalizer.py"),
    "proof_forge_formal_evidence_finalizer_for_rehearsal",
)
_REVOCATION = _load_module(
    _MODULE_PATH.with_name("revocation_ledger.py"),
    "proof_forge_revocation_ledger_for_rehearsal",
)
_EV_CORE = _load_module(
    _MODULE_PATH.with_name("evidence_v1_core.py"),
    "proof_forge_evidence_v1_core_for_rehearsal",
)
_CONSUMER = _ACCEPTANCE._CONSUMER
_FORMAL = _FINALIZER._FORMAL
_STORE = _ACCEPTANCE._STORE

PRODUCTION_POLICY_ID = "bootstrap-authority-root"
PRODUCTION_NAMESPACE_ID = "bootstrap-authority-store"
FIXTURE_NAMESPACE_ID = "formal-evidence-acceptance-fixture-namespace"
FINALIZER_EXE = b"formal-evidence-finalizer fixture executable v1\n"
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
EV_ALPHA = "EV-20260718-0001"
EV_BETA = "EV-20260718-0002"
EV_UNUSED = "EV-20260717-0099"
EXPECTED_PUBLISHED_OBJECTS = 2


class FormalEvidenceAcceptanceError(Exception):
    """Stable rehearsal failure; details never grant authority."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise FormalEvidenceAcceptanceError(code, detail)


def _unverified(detail: str) -> NoReturn:
    _fail("PF-EVIDENCE-FORMAL-UNVERIFIED", detail)


def _harness(detail: str) -> NoReturn:
    _fail("PF-FORMAL-EVIDENCE-ACCEPTANCE", detail)


@dataclass(frozen=True)
class FormalEvidenceRehearsalReport:
    recordId: str
    recordDigestHex: str
    recordPath: str
    bindingEvidenceId: str
    bindingDigestHex: str
    bindingPath: str
    storeHeadSequence: int
    publishedObjects: int
    expiresAt: str
    evidenceCount: int
    memberCount: int
    inputBytes: Mapping


def _digest_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def _scan_policy_bytes() -> bytes:
    return json.dumps(SCAN_POLICY, sort_keys=True, indent=2).encode() + b"\n"


def build_evidence_document(
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
    """Build one canonical fixture ``proof-forge.evidence.v1`` document."""
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
            "profileId": "s5-acceptance-host",
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
    document["artifactSetSha256"] = _EV_CORE.artifact_set_sha256(
        document["artifacts"]
    )
    document_bytes = _EV_CORE.canonical_bytes(document)
    _EV_CORE.validate_evidence(_EV_CORE.decode_json(document_bytes))
    return document_bytes


def _build_evidence_for(
    base,
    *,
    ev_id: str,
    qualification: str = "formal",
) -> Tuple[bytes, dict]:
    archive_sha = hashlib.sha256(base.archiveBytes).hexdigest()
    if ev_id == EV_ALPHA:
        members = {
            "inputs": (("spec", "spec/alpha.txt"),),
            "artifacts": ("out/alpha.acir",),
            "logs": ("logs/alpha.log",),
            "files": {
                "spec/alpha.txt": b"fixture alpha spec\n",
                "out/alpha.acir": b"\x00alpha circuit bytes",
                "logs/alpha.log": b"alpha run log\n",
            },
        }
        gate_id, task_id, test_ids = (
            "gate-alpha", "TASK-D1-01", ("TST-DOC-001", "TST-ISO-001")
        )
    else:
        members = {
            "inputs": (),
            "artifacts": ("out/beta.acir",),
            "logs": ("logs/beta.log",),
            "files": {
                "out/beta.acir": b"\x01beta circuit bytes",
                "logs/beta.log": b"beta run log\n",
            },
        }
        gate_id, task_id, test_ids = (
            "gate-beta",
            "TASK-D1-02",
            (
                "TST-BOOTSTRAP-001", "TST-COMMON-001", "TST-EVIDENCE-001",
                "TST-HOST-001", "TST-SBOM-001", "TST-TOOL-001",
            ),
        )
    document_bytes = build_evidence_document(
        ev_id=ev_id,
        gate_id=gate_id,
        task_id=task_id,
        test_ids=test_ids,
        qualification=qualification,
        commit=base.candidateCommit,
        tree=base.candidateTreeObjectId,
        archive_sha=archive_sha,
        archive_size=len(base.archiveBytes),
        members=members,
        artifact_target="noir",
    )
    return document_bytes, members


def _write_fixture_tree(root: Path, base, handoff, run, catalog_bytes: bytes,
                        catalog_approval_bytes: bytes,
                        ev_alpha: bytes, ev_beta: bytes,
                        member_sets: tuple, revocation_bytes: bytes) -> Path:
    tree = root / "tree"
    (tree / "approvals").mkdir(parents=True)
    (tree / "receipts").mkdir(parents=True)
    (tree / "evidence").mkdir(parents=True)
    (tree / "revocation").mkdir(parents=True)
    (tree / "members" / "candidate").mkdir(parents=True)
    (tree / "members" / "spec").mkdir(parents=True)
    (tree / "members" / "out").mkdir(parents=True)
    (tree / "members" / "logs").mkdir(parents=True)
    (tree / "authority-policy.json").write_bytes(base.policyBytes)
    (tree / "required-test-set.json").write_bytes(base.requiredBytes)
    (tree / "phase5-snapshot.json").write_bytes(
        json.dumps(
            {
                "id": base.phase5Snapshot.id,
                "path": base.phase5Snapshot.path,
                "bytesHex": base.phase5Snapshot.bytes.hex(),
            },
            sort_keys=True,
        ).encode()
    )
    (tree / "catalog.json").write_bytes(catalog_bytes)
    (tree / "catalog-approval.json").write_bytes(catalog_approval_bytes)
    (tree / "eligible-stage0-handoff.json").write_bytes(handoff.handoffBytes)
    (tree / "approval-set.json").write_bytes(run.setBytes)
    (tree / "activation-receipt.json").write_bytes(run.activationBytes)
    for task_id in (
        "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
        "TASK-D0-04", "TASK-D0-05", "TASK-D0-06",
    ):
        (tree / "approvals" / f"{task_id.lower()}-approval.json").write_bytes(
            run.approvalBytes[task_id]
        )
        (tree / "receipts" / f"{task_id.lower()}-receipt.json").write_bytes(
            run.receiptBytes[task_id]
        )
    (tree / "evidence" / f"{EV_ALPHA}.json").write_bytes(ev_alpha)
    (tree / "evidence" / f"{EV_BETA}.json").write_bytes(ev_beta)
    (tree / "members" / "candidate" / "archive.tar").write_bytes(
        base.archiveBytes
    )
    for members in member_sets:
        for relative, payload in members["files"].items():
            (tree / "members" / relative).write_bytes(payload)
    (tree / "revocation" / "RVK-20260718-0009.json").write_bytes(
        revocation_bytes
    )
    return tree


def build_rehearsal_fixture(
    root: Path,
    *,
    seeds_by_key_id: Mapping[str, bytes],
    run_id: str,
    nonce: str,
) -> dict:
    """Build one complete fixture authority chain and evidence bundle."""
    del nonce
    base = _ACCEPTANCE.build_rehearsal_base(
        namespace_id=FIXTURE_NAMESPACE_ID,
        descriptor_id="authority-store",
        descriptor_version="1.0.0",
        service_seed=bytes.fromhex("10" * 32),
        executable_digest_bytes=bytes.fromhex("42" * 32),
        observation_bytes=json.dumps(
            {
                "attestationScope": "local-observation-only",
                "eligibleForHermetic": True,
                "hostProfileId": "s5-acceptance-host",
                "platform": {"secureBoot": "enabled"},
                "remoteAttestation": False,
                "trustRoot": "synthetic fixture",
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8"),
        profile_bytes=json.dumps(
            {"id": "s5-acceptance-host"}, sort_keys=True, separators=(",", ":")
        ).encode("utf-8"),
        seeds_by_key_id=dict(seeds_by_key_id),
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
    root.mkdir(parents=True, exist_ok=True)
    seed_dir = root / "fixture-seed"
    seed_dir.mkdir()
    (seed_dir / "policy.json").write_bytes(base.policyBytes)
    (seed_dir / "archive.tar").write_bytes(base.archiveBytes)
    (seed_dir / "manifest.json").write_bytes(base.manifestBytes)
    handoff = _ACCEPTANCE.produce_run_handoff(
        base,
        handoff_id="s5-acceptance-stage0-handoff",
        handoff_version="1.0.0",
        run_id=run_id,
        policy_path=str(seed_dir / "policy.json"),
        archive_path=str(seed_dir / "archive.tar"),
        manifest_path=str(seed_dir / "manifest.json"),
    )
    run = _ACCEPTANCE.produce_run_objects(
        base,
        handoff,
        run_id=run_id,
        nonce="ee" * 32,
        seeds_by_key_id=dict(seeds_by_key_id),
    )
    for fd in (
        handoff.channels.authorityPolicyFd,
        handoff.channels.authorityStoreFd,
        handoff.channels.candidateArchiveFd,
        handoff.channels.evidenceRootFd,
        handoff.channels.authorityStoreServiceFd,
    ):
        try:
            os.close(fd)
        except OSError:
            pass

    consumer = _CONSUMER
    producer = _ACCEPTANCE._PRODUCER
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "s5-acceptance-catalog",
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": {
            "schema": base.requiredRef.schema,
            "id": base.requiredRef.id,
            "version": base.requiredRef.version,
            "digest": _digest_text(base.requiredRef.digest.bytes),
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
        id="s5-acceptance-catalog-approval",
        version="1.0.0",
        authorityPolicy=base.policyRef,
        requiredTestSet=base.requiredRef,
        catalog=catalog_ref,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
        authority_policy_bytes=base.policyBytes,
    )

    ev_alpha, alpha_members = _build_evidence_for(base, ev_id=EV_ALPHA)
    ev_beta, beta_members = _build_evidence_for(base, ev_id=EV_BETA)
    revocation_bytes = _REVOCATION.produce_revocation_record(
        id="RVK-20260718-0009",
        evidence_id=EV_UNUSED,
        evidence_sha256=hashlib.sha256(b"unused fixture evidence").hexdigest(),
        revoked_utc="2026-07-18T09:30:00Z",
        reason_code="incorrect",
        reason="fixture revocation of an unused evidence id",
        authority_ref="revocation-authority-alpha",
        replacement=None,
        previous_record_sha256="0" * 64,
    )
    tree = _write_fixture_tree(
        root,
        base,
        handoff,
        run,
        catalog_bytes,
        catalog_approval_bytes,
        ev_alpha,
        ev_beta,
        (alpha_members, beta_members),
        revocation_bytes,
    )

    def make_revocation_record(evidence_id: str) -> bytes:
        return _REVOCATION.produce_revocation_record(
            id="RVK-20260718-0001",
            evidence_id=evidence_id,
            evidence_sha256=hashlib.sha256(ev_alpha).hexdigest(),
            revoked_utc="2026-07-18T09:30:00Z",
            reason_code="incorrect",
            reason=f"fixture revocation of {evidence_id}",
            authority_ref="revocation-authority-alpha",
            replacement=None,
            previous_record_sha256="0" * 64,
        )

    def make_evidence(ev_id: str, qualification: str) -> bytes:
        document_bytes, _ = _build_evidence_for(
            base, ev_id=ev_id, qualification=qualification
        )
        return document_bytes

    gate_inputs = {
        "gate-alpha": {
            "build": {
                "targetId": "noir",
                "targetSemanticsVersion": "1.0.0",
                "targetSemanticsDigest": "sha256:" + "94" * 32,
                "codegenProfileId": "noir-acir",
                "codegenProfileDigest": "sha256:" + "95" * 32,
            },
            "evidenceRefs": [
                {"id": EV_ALPHA, "digest": _digest_text(
                    hashlib.sha256(ev_alpha).digest()
                )},
            ],
        },
        "gate-beta": {
            "build": {
                "targetId": "noir",
                "targetSemanticsVersion": "1.1.0",
                "targetSemanticsDigest": "sha256:" + "96" * 32,
                "codegenProfileId": "noir-acir",
                "codegenProfileDigest": "sha256:" + "97" * 32,
            },
            "evidenceRefs": [
                {"id": EV_BETA, "digest": _digest_text(
                    hashlib.sha256(ev_beta).digest()
                )},
            ],
        },
    }
    return {
        "base": base,
        "run": run,
        "handoff": handoff,
        "tree": tree,
        "catalogBytes": catalog_bytes,
        "catalogApprovalBytes": catalog_approval_bytes,
        "catalogRef": catalog_ref,
        "evAlphaBytes": ev_alpha,
        "evBetaBytes": ev_beta,
        "gateInputs": gate_inputs,
        "finalizerExecutable": FINALIZER_EXE,
        "scanPolicyBytes": _scan_policy_bytes(),
        "clockDeclaration": CLOCK_DECLARATION,
        "containmentObservation": {
            "supervisor_digest": _digest_text(bytes.fromhex("81" * 32)),
            "root_session_id": "root-session-01",
            "descendants": (
                {
                    "pid": 101,
                    "parentPid": 1,
                    "startToken": 11,
                    "sessionId": 501,
                    "executableDigest": _digest_text(bytes.fromhex("82" * 32)),
                    "termination": "exited",
                },
            ),
            "escape_probes": ({"id": "escape-probe-01", "result": "contained"},),
            "started_at": "2026-07-19T00:00:00Z",
            "finished_at": "2026-07-19T00:20:00Z",
        },
        "support": {
            "evidence_id": EV_ALPHA,
            "build": gate_inputs["gate-alpha"]["build"],
            "support_claim": {
                "requirement": {
                    "id": "counter.increment",
                    "version": "1.0.0",
                    "digest": _digest_text(
                        hashlib.sha256(b"fixture requirement").digest()
                    ),
                },
                "predicates": [
                    {"variant": "uint-at-least", "name": "count", "value": 1},
                ],
            },
            "gate_vectors": (
                {"gateId": "gate-alpha", "evidenceId": EV_ALPHA,
                 "grade": "local_runtime"},
                {"gateId": "gate-beta", "evidenceId": EV_BETA,
                 "grade": "local_runtime"},
            ),
        },
        "makeRevocationRecord": make_revocation_record,
        "makeEvidence": make_evidence,
    }


def start_fixture_store(fixture: dict, run_id: str, nonce: str,
                        socket_path: str):
    """Start the fixture authority-store service in-process."""
    base = fixture["base"]
    server = _STORE.AuthorityStoreServer(
        policy_bytes=base.policyBytes,
        service_seed=base.serviceSeed,
        descriptor_id=base.descriptorWire["id"],
        descriptor_version=base.descriptorWire["version"],
        service_executable_digest=_STORE.Digest(
            "sha256",
            bytes.fromhex(base.descriptorWire["serviceExecutableDigest"][7:]),
        ),
        namespace_id=base.descriptorWire["namespaceId"],
        expected_run_id=run_id,
        expected_nonce=nonce,
        io_timeout_seconds=30.0,
    )
    handle = server.serve_unix(socket_path)
    return server, handle


def verify_published_record(record_bytes: bytes, report_or_fixture) -> None:
    """Re-verify a published formal record against the rehearsal inputs."""
    fixture = report_or_fixture
    base = fixture["base"]
    inputs = fixture.get("inputs")
    if inputs is None:
        _harness("verify_published_record requires the rehearsal input bytes")
    try:
        _FORMAL.parse_formal_evidence_finalization(
            record_bytes,
            base.policyBytes,
            base.requiredBytes,
            _FORMAL._CONSUMER.BootstrapDocumentSnapshotV1(
                id=base.phase5Snapshot.id,
                path=base.phase5Snapshot.path,
                bytes=base.phase5Snapshot.bytes,
            ),
            fixture["catalogBytes"],
            fixture["catalogApprovalBytes"],
            inputs["containment"],
            inputs["freshness"],
            inputs["privateScan"],
            inputs["revocation"],
            inputs["revocationRecords"],
            inputs["finalizer"],
            fixture["run"].setBytes,
            tuple(
                fixture["run"].receiptBytes[task_id]
                for task_id in (
                    "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
                    "TASK-D0-04", "TASK-D0-05", "TASK-D0-06",
                )
            ),
            fixture["run"].activationBytes,
            fixture["handoff"].handoffBytes,
        )
    except _FORMAL.Rejected:
        _unverified("published record failed the full consumer re-verification")


def _require_fixture_namespace(policy_bytes: bytes, descriptor_wire: dict) -> None:
    try:
        policy, _ = _CONSUMER.parse_bootstrap_authority_policy(policy_bytes)
    except _CONSUMER.Rejected:
        _harness("authority policy bytes are not a valid signed policy")
    if policy.id == PRODUCTION_POLICY_ID:
        _harness("fixture policy id collides with the production namespace")
    if descriptor_wire.get("namespaceId") == PRODUCTION_NAMESPACE_ID:
        _harness("fixture store namespace collides with production")


def run_formal_evidence_rehearsal(
    fixture: dict,
    *,
    workdir: str,
    trusted_root: str,
    run_id: str,
    nonce: str,
    seeds_by_key_id: Mapping[str, bytes],
    record_id: str,
    finalized_at: str,
    observed_at: str,
    maximum_age_seconds: int = 3600,
    policy_bytes: Optional[bytes] = None,
    gate_inputs: Optional[Mapping] = None,
) -> FormalEvidenceRehearsalReport:
    """Run the TST-EVIDENCE-002 fixture rehearsal end to end."""
    base = fixture["base"]
    effective_policy = base.policyBytes if policy_bytes is None else policy_bytes
    _require_fixture_namespace(effective_policy, base.descriptorWire)
    os.makedirs(workdir, exist_ok=True)
    server, handle = start_fixture_store(
        fixture, run_id, nonce, os.path.join(workdir, "authority-store.sock")
    )
    try:
        try:
            _CONSUMER.parse_formal_gate_catalog_approval(
                fixture["catalogApprovalBytes"],
                fixture["catalogBytes"],
                base.requiredBytes,
                effective_policy,
            )
        except _CONSUMER.Rejected:
            _unverified("catalog authority failed full verification")
        client = _STORE.AuthorityStoreClient(
            base.descriptorRef, run_id, nonce, io_timeout_seconds=30.0
        )
        client.connect(os.path.join(workdir, "authority-store.sock"))
        try:
            if client.publish_with_readback(
                _STORE.REQUIRED_TEST_SET_SCHEMA, base.requiredBytes
            ) != base.requiredBytes:
                _harness("required test set publish closure failed")
            if client.publish_with_readback(
                _STORE.FORMAL_CATALOG_APPROVAL_SCHEMA,
                fixture["catalogApprovalBytes"],
            ) != fixture["catalogApprovalBytes"]:
                _harness("catalog approval publish closure failed")
        finally:
            client.close()
        try:
            outcome = _FINALIZER.finalize_formal_evidence(
                fixture_root=str(fixture["tree"]),
                trusted_root=trusted_root,
                record_id=record_id,
                finalized_at=finalized_at,
                observed_at=observed_at,
                maximum_age_seconds=maximum_age_seconds,
                clock_source_bytes=fixture["clockDeclaration"],
                containment_observation=fixture["containmentObservation"],
                finalizer_executable_bytes=fixture["finalizerExecutable"],
                finalizer_identity_id="s5-acceptance-finalizer",
                finalizer_closure_digest=_digest_text(bytes.fromhex("85" * 32)),
                finalizer_toolchain_lock_digest=_digest_text(
                    bytes.fromhex("86" * 32)
                ),
                scan_policy_bytes=fixture["scanPolicyBytes"],
                gate_inputs=(
                    fixture["gateInputs"] if gate_inputs is None else gate_inputs
                ),
                signers=dict(seeds_by_key_id),
                support=fixture["support"],
            )
        except _FINALIZER.FormalFinalizerError as error:
            _fail(error.code, error.detail)
        sequence, _ = server.head
        if sequence != EXPECTED_PUBLISHED_OBJECTS:
            _harness(
                f"store head must count {EXPECTED_PUBLISHED_OBJECTS} "
                f"appends, got {sequence}"
            )
        record_wire = _CONSUMER.decode_canonical_pf_jcs(outcome.recordBytes)
        binding_wire = _CONSUMER.decode_canonical_pf_jcs(outcome.bindingBytes)
        fixture["inputs"] = {
            "containment": outcome.containmentBytes,
            "freshness": outcome.freshnessBytes,
            "privateScan": outcome.privateScanBytes,
            "revocation": outcome.revocationLedgerBytes,
            "revocationRecords": outcome.revocationRecordBytes,
            "finalizer": outcome.finalizerIdentityBytes,
        }
        return FormalEvidenceRehearsalReport(
            recordId=record_id,
            recordDigestHex=hashlib.sha256(
                b"pf.formal-evidence-finalization.v1\x00" + outcome.recordBytes
            ).hexdigest(),
            recordPath=outcome.recordPath,
            bindingEvidenceId=binding_wire["evidence"]["id"],
            bindingDigestHex=hashlib.sha256(
                b"pf.support-evidence-binding.v1\x00" + outcome.bindingBytes
            ).hexdigest(),
            bindingPath=outcome.bindingPath,
            storeHeadSequence=sequence,
            publishedObjects=EXPECTED_PUBLISHED_OBJECTS,
            expiresAt=outcome.expiresAt,
            evidenceCount=len(record_wire["gates"]),
            memberCount=len(
                _CONSUMER.decode_canonical_pf_jcs(
                    outcome.privateScanBytes
                )["scannedMembers"]
            ),
            inputBytes=fixture["inputs"],
        )
    finally:
        handle.stop()


def format_report_lines(report: FormalEvidenceRehearsalReport) -> list:
    """Render the typed rehearsal report as exact output lines."""
    return [
        "policy: fixture (production lookup tuple disjoint)",
        "required-set: published",
        "catalog-approval: published",
        f"evidence: {report.evidenceCount} resolved",
        f"inputs: containment freshness revocation private-scan finalizer signed",
        f"record: {report.recordId} sha256:{report.recordDigestHex}",
        f"binding: {report.bindingEvidenceId} sha256:{report.bindingDigestHex}",
        f"store: {report.storeHeadSequence} objects",
        "rehearsal: ok",
    ]


_FIXTURE_SEEDS = {
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


def main(argv: Optional[list] = None) -> int:
    """Run one default fixture rehearsal and print the typed report."""
    args = list(sys.argv[1:] if argv is None else argv)
    if args:
        print("usage: formal_evidence_acceptance.py", file=sys.stderr)
        return 2
    workspace = Path(
        tempfile.mkdtemp(prefix="formal-evidence-acceptance-")
    ).resolve()
    try:
        workdir = workspace / "work"
        trusted = workspace / "trusted"
        workdir.mkdir()
        trusted.mkdir()
        fixture = build_rehearsal_fixture(
            workspace / "fixture",
            seeds_by_key_id=_FIXTURE_SEEDS,
            run_id="s5-acceptance-run",
            nonce="ee" * 32,
        )
        report = run_formal_evidence_rehearsal(
            fixture,
            workdir=str(workdir),
            trusted_root=str(trusted),
            run_id="s5-acceptance-run",
            nonce="ee" * 32,
            seeds_by_key_id=_FIXTURE_SEEDS,
            record_id="EVF-20260719-0001",
            finalized_at="2026-07-19T00:30:00Z",
            observed_at="2026-07-19T00:00:00Z",
        )
        for line in format_report_lines(report):
            print(line)
        return 0
    except FormalEvidenceAcceptanceError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"PF-FORMAL-EVIDENCE-ACCEPTANCE: {type(error).__name__}",
              file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
