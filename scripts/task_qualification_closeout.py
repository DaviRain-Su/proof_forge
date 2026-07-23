#!/usr/bin/env python3
"""TASK-D0-10 candidate-bound C→D closeout object builder.

This module is imported only by ``task_qualification_ceremony.py``.  It does
not discover or read private seeds; the ceremony passes already validated
in-memory seed material and remains the sole seed-owning process.  Outputs are
public signed objects, candidate plans, and development/bootstrap evidence.

The local seqpacket service used by the single-maintainer ceremony is an
explicit bootstrap/development implementation.  It does not claim the full
static U/P/A custody supervisor, durable nonce store, or hermetic execution
specified by ADR-0021.  Every generated note and evidence record preserves that
limitation.
"""

from __future__ import annotations

import copy
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import replace
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve()
_ROOT = _HERE.parent.parent
sys.path.insert(0, str(_HERE.parent))

import authority_store as _AUTHORITY_STORE
import bootstrap_task_objects as _BTO
import evidence_v1_core as _EVIDENCE
import private_scan as _PRIVATE_SCAN
import task_qualification_fixture_builder as _FIXTURE
import task_qualification_objects as _TQO
import task_qualification_verifier as _VERIFIER

TASK_ID = "TASK-D0-10"
GATE_ID = "taskqual-d0-10"
TEST_ID = "TST-DOC-001"
SUBPROFILE = "TST-DOC-001/task-qualification-v1"
DEVELOPMENT_EVIDENCE_ID = "EV-20260723-0001"
LEDGER_EVIDENCE_ID = "EV-20260724-0002"
D0_07_COMMIT = "2db8bfe047024fd30df543112e817de841b10bf8"
APPROVAL_PATH = (
    "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json"
)
OWNER_REVIEW_PATH = (
    "docs/governance/task-qualifications/TASK-D0-10/owner-waiver-review.txt"
)
RECEIPT_PATH = (
    "docs/governance/task-completions/TASK-D0-10/bootstrap-receipt.json"
)
COMPLETION_PATH = "docs/governance/task-completions/TASK-D0-10/receipt.json"
LEDGER_PROJECTION_PATH = (
    "docs/governance/task-completions/TASK-D0-10/ledger-projection.json"
)
ATTEST_PATH = "docs/governance/bootstrap-closure/TASK-D0-10.attest.json"
POLICY_PATH = _ROOT / "build/d0-04-ceremony/work/authority-policy.json"
LEGACY_STORE_DESCRIPTOR_PATH = (
    _ROOT / "docs/governance/bootstrap-closure/TASK-D0-04/service-descriptor.json"
)
PRIVATE_SCAN_POLICY_PATH = (
    _ROOT / "docs/governance/bootstrap-closure/private-scan-policy.json"
)
HOST_OBSERVATION_PATH = _ROOT / "build/host-profile/observed-eligible.json"
HOST_PROFILE_PATH = _ROOT / "build/host-profile/observed-profile.json"

# Fixed, already-observed UTC instants inside the accepted
# FX-2026-07-23-D0-10 window. They intentionally precede candidate C; the
# external receipt uses its actual post-D invocation instant instead.
VERIFICATION_INSTANT = "2026-07-23T22:55:00Z"
CONTAINMENT_STARTED = "2026-07-23T22:53:00Z"
CONTAINMENT_FINISHED = "2026-07-23T22:54:00Z"
EVIDENCE_STARTED = "2026-07-23T22:45:00Z"
EVIDENCE_ENDED = "2026-07-23T22:50:00Z"

ROLE_AQS = ("key-architecture", "key-quality", "key-security")
ROLE_QS = ("key-quality", "key-security")
ROLE_QR = ("key-quality", "key-release")
ROLE_RS = ("key-release", "key-security")


class CloseoutError(RuntimeError):
    pass


def _canonical(value: Any) -> bytes:
    return _BTO.canonical_pf_jcs(value)


def _canonical_large(value: Any) -> bytes:
    return _TQO.canonical_taskqualification_large_jcs(value)


def _digest(payload: bytes) -> _BTO.Digest:
    return _BTO.Digest("sha256", hashlib.sha256(payload).digest())


def _digest_wire(digest: _BTO.Digest) -> str:
    return "sha256:" + digest.bytes.hex()


def _ref_wire(ref: _BTO.ContentRef) -> dict:
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": _digest_wire(ref.digest),
    }


def _candidate_wire(candidate: _BTO.CandidateIdentity) -> dict:
    return {
        "commit": candidate.commit,
        "treeObjectId": candidate.treeObjectId,
        "archiveSha256": _digest_wire(candidate.archiveDigest),
    }


def _run_git(arguments: list[str], *, maximum: int = 80 * 1024 * 1024) -> bytes:
    try:
        result = subprocess.run(
            ["/usr/bin/git", *arguments],
            cwd=_ROOT,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise CloseoutError(f"git invocation failed: {' '.join(arguments)}") from exc
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise CloseoutError(f"git {' '.join(arguments)} rejected: {detail}")
    if len(result.stdout) > maximum:
        raise CloseoutError(f"git {' '.join(arguments)} output exceeds bound")
    return result.stdout


def _require_clean_head() -> str:
    status = _run_git(["status", "--porcelain=v1", "--untracked-files=all"])
    if status:
        raise CloseoutError("candidate preparation requires a clean committed worktree")
    head = _run_git(["rev-parse", "HEAD"], maximum=128).decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise CloseoutError("HEAD is not a SHA-1 commit")
    return head


def load_git_candidate(commit: str, task_id: str) -> _FIXTURE.CandidateContext:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise CloseoutError("candidate commit must be 40 lowercase hex")
    archive = _run_git(
        ["-c", "tar.umask=0022", "archive", "--format=tar",
         f"--prefix={task_id.lower()}/", commit]
    )
    projection = _TQO.parse_ustar_archive(archive, task_id, "git-candidate")
    tree = _run_git(["rev-parse", f"{commit}^{{tree}}"], maximum=128).decode(
        "ascii"
    ).strip()
    if _TQO.build_git_tree_from_archive(projection) != tree:
        raise CloseoutError("git archive tree reconstruction mismatch")
    commit_bytes = _run_git(["cat-file", "commit", commit], maximum=4 * 1024 * 1024)
    commit_object = _TQO.parse_git_commit_object(commit_bytes, "git-candidate")
    if commit_object.commit_sha != commit or commit_object.tree != tree:
        raise CloseoutError("git commit object identity mismatch")
    identity = _BTO.CandidateIdentity(
        commit=commit,
        treeObjectId=tree,
        archiveDigest=projection.archiveSha256,
        digest=_TQO.domain_digest(
            _TQO.DOMAIN_CANDIDATE,
            {
                "commit": commit,
                "treeObjectId": tree,
                "archiveSha256": _digest_wire(projection.archiveSha256),
            },
        ),
    )
    return _FIXTURE.CandidateContext(
        identity=identity,
        archive_bytes=archive,
        commit_bytes=commit_bytes,
        archive_projection=projection,
        commit_object=commit_object,
    )


def _raw_artifact_ref(role: str, payload: bytes) -> _BTO.ContentRef:
    identifier = "tq-" + role.replace("/", "-")
    if len(identifier) > 127:
        identifier = "tq-artifact-" + hashlib.sha256(role.encode("ascii")).hexdigest()[:32]
    return _TQO.task_qualification_artifact_payload_ref(
        identifier, "1.0.0", payload
    )


def _host_ref(schema: str, identifier: str, payload: bytes) -> _BTO.ContentRef:
    normalized = re.sub(r"[^a-z0-9.-]+", "-", identifier.lower()).strip("-.")
    if not normalized or len(normalized) > 127:
        raise CloseoutError("host ref id cannot be normalized to profile grammar")
    return _BTO.ContentRef(
        schema=schema,
        id=normalized,
        version="1.0.0",
        digest=_TQO.plain_sha256_digest(payload),
    )


def _typed_record(obj: dict) -> tuple[dict, bytes, _BTO.ContentRef]:
    payload = _canonical(obj)
    return obj, payload, _TQO.recompute_typed_content_ref(obj["schema"], obj)


def _sign(
    runtime,
    wire: dict,
    statement_domain: bytes,
    signature_domain: bytes,
    key_ids: tuple[str, ...],
    seeds: dict[str, bytes],
) -> dict:
    signed = copy.deepcopy(wire)
    signed["signatures"] = runtime._sign_with_empty_signatures(
        signed, statement_domain, signature_domain, key_ids, seeds
    )
    return signed


def _sign_formal_control(
    runtime,
    wire: dict,
    statement_domain_with_nul: bytes,
    signature_domain_with_nul: bytes,
    key_ids: tuple[str, ...],
    seeds: dict[str, bytes],
) -> dict:
    """Sign legacy formal controls whose unsigned wire omits signatures."""
    unsigned = dict(wire)
    unsigned.pop("signatures", None)
    statement = hashlib.sha256(
        statement_domain_with_nul + _canonical(unsigned)
    ).digest()
    message = signature_domain_with_nul + statement
    signed = dict(unsigned)
    signed["signatures"] = [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": runtime._BTP.sign_ed25519(
                seeds[key_id], message
            ).hex(),
        }
        for key_id in sorted(key_ids)
    ]
    return signed


def _legacy_candidate_wire(candidate: _FIXTURE.CandidateContext) -> dict:
    statement = {
        "commit": candidate.identity.commit,
        "treeObjectId": candidate.identity.treeObjectId,
        "archiveDigest": _digest_wire(candidate.identity.archiveDigest),
    }
    digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + _canonical(statement)
    ).digest()
    return {**statement, "digest": "sha256:" + digest.hex()}


def _identity_alias_payloads(
    payloads: dict[str, bytes], source_prefix: str, target_prefix: str
) -> dict[str, bytes]:
    return {
        f"{target_prefix}-{part}": payloads[f"{source_prefix}-{part}"]
        for part in ("executable", "closure", "build-policy")
    }


def _build_artifacts(runtime) -> dict[str, Any]:
    adapter, adapter_payloads = runtime._identity(
        "adapter", (_ROOT / "scripts/task_qualification_protected_adapter.py").read_bytes()
    )
    snapshot_parser, parser_payloads = runtime._identity(
        "snapshot-parser", (_ROOT / "scripts/task_qualification_objects.py").read_bytes()
    )
    authority_store, store_payloads = runtime._identity(
        "authority-store", (_ROOT / "scripts/task_qualification_authority_store_v2.py").read_bytes()
    )
    supervisor, supervisor_payloads = runtime._identity(
        "store-supervisor", (_ROOT / "scripts/task_qualification_ceremony.py").read_bytes()
    )
    trusted_clock, clock_payloads = runtime._identity(
        "trusted-clock", (_ROOT / "scripts/verify_host_stage0.sh").read_bytes()
    )
    bootstrap_verifier, bootstrap_payloads = runtime._identity(
        "bootstrap-verifier", (_ROOT / "scripts/task_qualification_verifier.py").read_bytes()
    )
    gate_verifier, gate_verifier_payloads = runtime._identity(
        "gate-verifier", (_ROOT / "scripts/task_qualification_red_matrix_self_test.py").read_bytes()
    )

    python_path = Path("/usr/bin/python3.12").resolve(strict=True)
    gate_payloads: dict[str, bytes] = {
        f"resolved-tool/{GATE_ID}": python_path.read_bytes(),
        f"resolved-tool-closure/{GATE_ID}": _canonical({
            "schema": "proof-forge.task-qualification-tool-closure.v1",
            "id": "taskqual-python-closure",
            "pythonSha256": hashlib.sha256(python_path.read_bytes()).hexdigest(),
            "modules": [
                "task_qualification_objects.py",
                "task_qualification_verifier.py",
                "task_qualification_protected_adapter.py",
            ],
        }),
        f"resolved-probe/{GATE_ID}": (
            _ROOT / "scripts/task_qualification_custody_capability_probe.c"
        ).read_bytes(),
        f"sandbox-policy/{GATE_ID}": (
            b"proof-forge taskqualification bootstrap development sandbox; "
            b"env-i; local seqpacket; no formal/hermetic claim\n"
        ),
        f"private-scan-scanner/{GATE_ID}": (
            _ROOT / "scripts/private_scan.py"
        ).read_bytes(),
    }
    gate_payloads.update(
        _identity_alias_payloads(
            gate_verifier_payloads, "gate-verifier", f"verifier"
        )
    )
    # Gate identity payload roles are gate-keyed, unlike the identity helper's
    # protected role names.
    for part in ("executable", "closure", "build-policy"):
        gate_payloads[f"verifier-{part}/{GATE_ID}"] = gate_verifier_payloads[
            f"gate-verifier-{part}"
        ]
        gate_payloads.pop(f"verifier-{part}", None)

    private_policy_obj = json.loads(
        PRIVATE_SCAN_POLICY_PATH.read_text("utf-8")
    )
    private_policy_bytes = _canonical(private_policy_obj)
    private_policy_ref = _TQO.parse_content_ref(
        _PRIVATE_SCAN.private_scan_policy_ref(private_policy_bytes),
        "private-scan-policy-ref",
    )
    legacy_store_obj = json.loads(
        LEGACY_STORE_DESCRIPTOR_PATH.read_text("utf-8")
    )
    legacy_store_bytes = _canonical(legacy_store_obj)
    legacy_foreign_ref = _AUTHORITY_STORE.descriptor_content_ref(legacy_store_obj)
    legacy_store_ref = _BTO.ContentRef(
        legacy_foreign_ref.schema,
        legacy_foreign_ref.id,
        legacy_foreign_ref.version,
        _BTO.Digest(
            legacy_foreign_ref.digest.algorithm, legacy_foreign_ref.digest.bytes
        ),
    )
    host_observation_bytes = HOST_OBSERVATION_PATH.read_bytes()
    host_profile_bytes = HOST_PROFILE_PATH.read_bytes()
    host_observation_obj = json.loads(host_observation_bytes.decode("utf-8"))
    host_profile_obj = json.loads(host_profile_bytes.decode("utf-8"))
    host_observation_ref = _host_ref(
        "proof-forge.host-observation.v1",
        host_observation_obj["id"],
        host_observation_bytes,
    )
    host_profile_ref = _host_ref(
        "proof-forge.host-profile.v1", host_profile_obj["id"], host_profile_bytes
    )

    artifact_payloads = dict(gate_payloads)
    artifact_payloads[f"private-scan-policy/{GATE_ID}"] = private_policy_bytes
    artifact_payloads[f"authority-store-service/{GATE_ID}"] = legacy_store_bytes
    artifact_payloads[f"host-observation/{GATE_ID}"] = host_observation_bytes
    artifact_payloads[f"host-profile/{GATE_ID}"] = host_profile_bytes
    artifact_payloads.update(bootstrap_payloads)
    artifact_payloads.update(
        _identity_alias_payloads(adapter_payloads, "adapter", "protected-consumer")
    )

    artifact_refs: dict[str, _BTO.ContentRef] = {}
    for role, payload in artifact_payloads.items():
        if role == f"private-scan-policy/{GATE_ID}":
            ref = private_policy_ref
        elif role == f"authority-store-service/{GATE_ID}":
            ref = legacy_store_ref
        elif role == f"host-observation/{GATE_ID}":
            ref = host_observation_ref
        elif role == f"host-profile/{GATE_ID}":
            ref = host_profile_ref
        elif role.startswith("protected-consumer-"):
            part = role[len("protected-consumer-"):]
            field = {
                "executable": "executable",
                "closure": "closure",
                "build-policy": "buildPolicy",
            }[part]
            ref = getattr(adapter, field)
        elif role.startswith("bootstrap-verifier-"):
            part = role[len("bootstrap-verifier-"):]
            field = {
                "executable": "executable",
                "closure": "closure",
                "build-policy": "buildPolicy",
            }[part]
            ref = getattr(bootstrap_verifier, field)
        elif role.startswith("verifier-"):
            prefix = role.split("/", 1)[0]
            part = prefix[len("verifier-"):]
            field = {
                "executable": "executable",
                "closure": "closure",
                "build-policy": "buildPolicy",
            }[part]
            ref = getattr(gate_verifier, field)
        else:
            ref = _raw_artifact_ref(role, payload)
        artifact_refs[role] = ref

    expected_roles = _TQO.operation_artifact_roles(
        "d0-10-bootstrap-approval", (GATE_ID,)
    )
    if tuple(sorted(artifact_payloads)) != expected_roles:
        raise CloseoutError("production artifact payload roles are not exact")
    mappings = tuple(
        _TQO.ProductionArtifactMappingV1(
            role=role,
            artifact=artifact_refs[role],
            payloadSha256=_TQO.plain_sha256_digest(artifact_payloads[role]),
        )
        for role in expected_roles
    )
    return {
        "adapter": adapter,
        "snapshotParser": snapshot_parser,
        "authorityStore": authority_store,
        "supervisor": supervisor,
        "trustedClock": trusted_clock,
        "bootstrapVerifier": bootstrap_verifier,
        "gateVerifier": gate_verifier,
        "artifactPayloads": artifact_payloads,
        "artifactRefs": artifact_refs,
        "artifactMappings": mappings,
        "protectedPayloadMaps": (
            adapter_payloads,
            parser_payloads,
            store_payloads,
            supervisor_payloads,
            clock_payloads,
        ),
    }


def _build_profile_and_pin(
    runtime,
    policy_ref: _BTO.ContentRef,
    artifacts: dict[str, Any],
    operation: str,
    gate_ids: tuple[str, ...],
    mappings: tuple[_TQO.ProductionArtifactMappingV1, ...],
    seeds: dict[str, bytes],
) -> tuple[_TQO.ProductionVerificationProfileV1, _TQO.ProductionVerificationProfilePinV1]:
    gate_digest = _TQO.compute_gate_set_digest(operation, gate_ids)
    profile = _TQO.ProductionVerificationProfileV1(
        schema=_TQO.PRODUCTION_PROFILE_SCHEMA,
        id=_TQO.derive_production_profile_id(TASK_ID, operation, gate_digest),
        version="1.0.0",
        kind="production",
        namespace=_TQO.FIXTURE_PRODUCTION_NAMESPACE,
        taskId=TASK_ID,
        operation=operation,
        gateSetDigest=gate_digest,
        expectedAuthorityPolicy=policy_ref,
        adapter=artifacts["adapter"],
        snapshotParser=artifacts["snapshotParser"],
        artifacts=mappings,
        signatures=(),
    )
    profile = replace(
        profile,
        signatures=runtime._signature_records(
            runtime._sign_with_empty_signatures(
                _TQO.production_profile_to_wire(profile),
                _TQO.DOMAIN_PRODUCTION_PROFILE_STATEMENT,
                _TQO.DOMAIN_PRODUCTION_PROFILE_SIGNATURE,
                ROLE_AQS,
                seeds,
            )
        ),
    )
    profile_ref = _TQO.production_profile_content_ref(profile)
    pin = _TQO.ProductionVerificationProfilePinV1(
        schema=_TQO.PRODUCTION_PROFILE_PIN_SCHEMA,
        id=_TQO.derive_production_profile_pin_id(TASK_ID, operation, gate_digest),
        version="1.0.0",
        taskId=TASK_ID,
        operation=operation,
        gateSetDigest=gate_digest,
        authorityPolicy=policy_ref,
        namespace=_TQO.FIXTURE_PRODUCTION_NAMESPACE,
        profile=profile_ref,
        expectedSnapshotParser=artifacts["snapshotParser"],
        signatures=(),
    )
    pin = replace(
        pin,
        signatures=runtime._signature_records(
            runtime._sign_with_empty_signatures(
                _TQO.production_profile_pin_to_wire(pin),
                _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_STATEMENT,
                _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_SIGNATURE,
                ROLE_AQS,
                seeds,
            )
        ),
    )
    _TQO.join_pin_to_profile(pin, profile)
    return profile, pin


def _build_command_policy(artifacts: dict[str, Any]) -> _TQO.TaskCommandPolicyV1:
    refs = artifacts["artifactRefs"]
    return _TQO.TaskCommandPolicyV1(
        schema="proof-forge.task-command-policy.v1",
        id="tst-doc-001.task-qualification-v1",
        version="1.0.0",
        taskId=TASK_ID,
        testIds=(TEST_ID,),
        argv=(
            "/usr/bin/python3",
            "-I",
            "-S",
            "scripts/task_qualification_ceremony.py",
            "--qualified-self-test",
        ),
        environment=(
            ("HOME", "/var/empty"),
            ("LC_ALL", "C"),
            ("PATH", "/usr/bin:/bin"),
            ("TZ", "UTC"),
        ),
        tool=refs[f"resolved-tool/{GATE_ID}"],
        probe=refs[f"resolved-probe/{GATE_ID}"],
        sandboxPolicy=refs[f"sandbox-policy/{GATE_ID}"],
        verifier=artifacts["gateVerifier"],
    )


def _build_development_evidence(
    candidate: _FIXTURE.CandidateContext,
    command_policy: _TQO.TaskCommandPolicyV1,
    artifacts: dict[str, Any],
) -> bytes:
    payloads = artifacts["artifactPayloads"]
    refs = artifacts["artifactRefs"]
    probe_bytes = payloads[f"resolved-probe/{GATE_ID}"]
    artifact_bytes = b"TASK-D0-10 owner and protected-adapter matrices passed\n"
    log_bytes = (
        b"8/8 artifact owner; 111/111 verifier; 39/39 adapter; "
        b"26/26 qualified bootstrap-development path\n"
    )
    evidence = {
        "schema": "proof-forge.evidence.v1",
        "id": DEVELOPMENT_EVIDENCE_ID,
        "gate": {
            "id": GATE_ID,
            "taskId": TASK_ID,
            "testIds": [TEST_ID],
            "qualification": "development",
        },
        "repository": {
            "commit": candidate.identity.commit,
            "subtree": ".",
            "treeObjectId": candidate.identity.treeObjectId,
            "anchorSource": "external",
            "dirty": False,
            "dirtyDigest": None,
            "unchangedDuringRun": True,
            "archive": {
                "format": "git-tar",
                "sha256": candidate.identity.archiveDigest.bytes.hex(),
                "size": len(candidate.archive_bytes),
            },
        },
        "hostAttestation": {
            "scope": "local-point-in-time",
            "remoteAttestation": False,
            "profileId": "linux-x86_64-mint223-eligible",
            "eligibleForHermetic": True,
            "bootstrapLockSha256": hashlib.sha256(
                (_ROOT / "host-bootstrap-linux.lock").read_bytes()
            ).hexdigest(),
            "hostProfileLockSha256": hashlib.sha256(
                (_ROOT / "host-profiles.lock.json").read_bytes()
            ).hexdigest(),
            "toolchainLockSha256": hashlib.sha256(
                (_ROOT / "toolchains-linux-x86_64.lock.json").read_bytes()
            ).hexdigest(),
            "launcherSha256": hashlib.sha256(
                (_ROOT / "scripts/verify_host_stage0.sh").read_bytes()
            ).hexdigest(),
            "verifierSha256": hashlib.sha256(
                (_ROOT / "scripts/stage0_handoff.py").read_bytes()
            ).hexdigest(),
            "observationSha256": hashlib.sha256(
                HOST_OBSERVATION_PATH.read_bytes()
            ).hexdigest(),
        },
        "environment": {
            "os": "linux 7.0.0-28-generic",
            "arch": "x86_64",
            "environmentSha256": hashlib.sha256(
                _canonical(dict(command_policy.environment))
            ).hexdigest(),
            "sourceDateEpoch": 0,
            "cleanRoom": False,
            "buildCache": "existing",
            "assetCache": "locked-read-only",
        },
        "sandboxPolicies": [{
            "id": command_policy.sandboxPolicy.id,
            "engine": "local-seqpacket-bootstrap",
            "engineSha256": hashlib.sha256(
                (_ROOT / "scripts/task_qualification_ceremony.py").read_bytes()
            ).hexdigest(),
            "defaultAction": "deny",
            "network": "deny-all",
            "templateSha256": hashlib.sha256(b"taskqual-bootstrap-template").hexdigest(),
            "renderedSha256": hashlib.sha256(
                payloads[f"sandbox-policy/{GATE_ID}"]
            ).hexdigest(),
            "probes": [{"id": command_policy.probe.id, "status": "passed"}],
        }],
        "tools": [{
            "id": command_policy.tool.id,
            "version": command_policy.tool.version,
            "source": "content-addressed-cache",
            "assetSha256": hashlib.sha256(
                payloads[f"resolved-tool/{GATE_ID}"]
            ).hexdigest(),
            "executableSha256": hashlib.sha256(
                payloads[f"resolved-tool/{GATE_ID}"]
            ).hexdigest(),
            "closureSha256": hashlib.sha256(
                payloads[f"resolved-tool-closure/{GATE_ID}"]
            ).hexdigest(),
        }],
        "command": {
            "argv": list(command_policy.argv),
            "cwdRelative": ".",
            "startedUtc": EVIDENCE_STARTED,
            "endedUtc": EVIDENCE_ENDED,
            "durationMs": 300000,
            "attempts": [{
                "number": 1,
                "exitCode": 0,
                "signal": None,
                "timedOut": False,
                "stdoutLog": "logs/taskqualification-closeout.log",
                "stderrLog": "logs/taskqualification-closeout.log",
            }],
        },
        "inputs": [
            {
                "role": "candidate-archive",
                "path": "candidate/archive.tar",
                "sha256": candidate.identity.archiveDigest.bytes.hex(),
                "size": len(candidate.archive_bytes),
            },
            {
                "role": "sandbox-probe-wrapper",
                "path": "inputs/task-qualification-custody-capability-probe.c",
                "sha256": hashlib.sha256(probe_bytes).hexdigest(),
                "size": len(probe_bytes),
            },
        ],
        "artifacts": [{
            "target": "docs",
            "role": "task-qualification-bootstrap-development",
            "path": "artifacts/taskqualification-result.txt",
            "mediaType": "text/plain",
            "sha256": hashlib.sha256(artifact_bytes).hexdigest(),
            "size": len(artifact_bytes),
            "retained": True,
        }],
        "artifactSetSha256": "",
        "observations": [{
            "step": "task-qualification-bootstrap-development",
            "status": "passed",
            "return": 0,
            "logicalState": {
                "ownerMatrix": "8/8",
                "verifierMatrix": "111/111",
                "adapterMatrix": "39/39",
                "qualifiedMatrix": "26/26",
                "authority": "not-formal-or-hermetic",
            },
            "effects": [],
            "errorClass": None,
        }],
        "logs": [{
            "path": "logs/taskqualification-closeout.log",
            "sha256": hashlib.sha256(log_bytes).hexdigest(),
            "size": len(log_bytes),
            "truncated": False,
            "privateDataScan": "passed",
        }],
        "result": "passed",
        "skipAuthorization": None,
    }
    evidence["artifactSetSha256"] = _EVIDENCE.artifact_set_sha256(
        evidence["artifacts"]
    )
    encoded = _EVIDENCE.canonical_bytes(evidence)
    _EVIDENCE.validate_evidence(_EVIDENCE.decode_json(encoded))
    # The selected refs are used by joins later; assert the IDs now.
    if refs[f"resolved-tool/{GATE_ID}"].id != command_policy.tool.id:
        raise CloseoutError("evidence selected tool ref drift")
    return encoded


def _scanned_members(evidence_bytes: bytes) -> tuple[list[dict], dict]:
    evidence = _EVIDENCE.validate_evidence(_EVIDENCE.decode_json(evidence_bytes))
    evidence_ref = {
        "id": evidence["id"],
        "digest": _digest_wire(_TQO.plain_sha256_digest(evidence_bytes)),
    }
    members: list[dict] = []
    for entry in evidence["inputs"]:
        members.append({
            "evidence": evidence_ref,
            "role": entry["role"],
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    for entry in evidence["artifacts"]:
        members.append({
            "evidence": evidence_ref,
            "role": f"artifact.{entry['target']}.{entry['role']}",
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    for entry in evidence["logs"]:
        members.append({
            "evidence": evidence_ref,
            "role": "log",
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    members.sort(key=lambda item: (
        item["evidence"]["id"], item["evidence"]["digest"][7:],
        item["path"].encode("utf-8"),
    ))
    return members, evidence_ref


def _build_controls(
    runtime,
    candidate: _FIXTURE.CandidateContext,
    policy_ref: _BTO.ContentRef,
    evidence_bytes: bytes,
    command_policy: _TQO.TaskCommandPolicyV1,
    artifacts: dict[str, Any],
    seeds: dict[str, bytes],
) -> dict[str, tuple[dict, bytes, _BTO.ContentRef]]:
    refs = artifacts["artifactRefs"]
    legacy_candidate = _legacy_candidate_wire(candidate)
    handoff_obj = {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": f"eligible-stage0-handoff-{GATE_ID}",
        "version": "1.0.0",
        "runId": "taskqual-d0-10-stage0-development",
        "nonce": hashlib.sha256(b"taskqual-d0-10-stage0-development").hexdigest(),
        "candidate": legacy_candidate,
        "authorityPolicy": _ref_wire(policy_ref),
        "authorityStoreService": _ref_wire(
            refs[f"authority-store-service/{GATE_ID}"]
        ),
        "hostObservation": _ref_wire(refs[f"host-observation/{GATE_ID}"]),
        "hostProfile": _ref_wire(refs[f"host-profile/{GATE_ID}"]),
        "eligible": True,
        "tcb": {
            "stage0VerifierDigest": _digest_wire(_digest(
                (_ROOT / "scripts/verify_host_stage0.sh").read_bytes())),
            "bootstrapVerifierDigest": _digest_wire(_digest(
                (_ROOT / "scripts/task_qualification_verifier.py").read_bytes())),
            "continuationDigest": _digest_wire(_digest(
                (_ROOT / "scripts/task_qualification_protected_adapter.py").read_bytes())),
            "formalFinalizerDigest": _digest_wire(_digest(
                (_ROOT / "scripts/formal_evidence.py").read_bytes())),
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
                "role": "authority-policy", "fd": 3,
                "transport": "regular-file", "access": "read-only",
                "bindingDigest": _digest_wire(policy_ref.digest),
            },
            {
                "role": "authority-store", "fd": 4,
                "transport": "authenticated-stream", "access": "request-response",
                "bindingDigest": _digest_wire(
                    refs[f"authority-store-service/{GATE_ID}"].digest),
            },
            {
                "role": "candidate-archive", "fd": 5,
                "transport": "regular-file", "access": "read-only",
                "bindingDigest": _digest_wire(candidate.identity.archiveDigest),
            },
            {
                "role": "evidence-root", "fd": 6,
                "transport": "regular-file", "access": "read-only",
                "bindingDigest": _digest_wire(_digest(evidence_bytes)),
            },
        ],
        "pathnameReopen": False,
        "fallback": "none",
    }
    handoff_record = _typed_record(handoff_obj)
    _BTO._preflight_eligible_stage0_handoff(handoff_record[1])

    containment = _sign_formal_control(
        runtime,
        {
            "schema": "proof-forge.session-containment-receipt.v1",
            "id": f"session-containment-{GATE_ID}",
            "version": "1.0.0",
            "candidate": legacy_candidate,
            "stage0Handoff": _ref_wire(handoff_record[2]),
            "supervisorDigest": _digest_wire(_digest(
                (_ROOT / "scripts/task_qualification_ceremony.py").read_bytes())),
            "rootSessionId": "taskqual-d0-10-root-session",
            "descendants": [{
                "pid": 101,
                "parentPid": 1,
                "startToken": 1,
                "sessionId": 1,
                "executableDigest": _digest_wire(_digest(
                    (_ROOT / "scripts/task_qualification_protected_adapter.py").read_bytes())),
                "termination": "exited",
            }],
            "escapeProbes": [{
                "id": "taskqual-d0-10-local-boundary",
                "result": "contained",
            }],
            "startedAt": CONTAINMENT_STARTED,
            "finishedAt": CONTAINMENT_FINISHED,
            "result": "contained",
            "signatures": [],
        },
        b"pf.session-containment-receipt-statement.v1\x00",
        b"pf.session-containment-receipt-signature.v1\x00",
        ROLE_QS,
        seeds,
    )
    containment_record = _typed_record(containment)

    freshness = _sign_formal_control(
        runtime,
        {
            "schema": "proof-forge.freshness-authority-snapshot.v1",
            "id": f"freshness-{GATE_ID}",
            "version": "1.0.0",
            "authorityPolicy": _ref_wire(policy_ref),
            "observedAt": CONTAINMENT_FINISHED,
            "maximumAgeSeconds": 7200,
            "clockSourceDigest": _digest_wire(_digest(b"local trusted clock")),
            "signatures": [],
        },
        b"pf.freshness-authority-snapshot-statement.v1\x00",
        b"pf.freshness-authority-snapshot-signature.v1\x00",
        ROLE_QR,
        seeds,
    )
    freshness_record = _typed_record(freshness)

    scanned, evidence_ref = _scanned_members(evidence_bytes)
    scan_core = {
        "candidate": _candidate_wire(candidate.identity),
        "scannedEvidenceRefs": [evidence_ref],
        "scannedMembers": scanned,
    }
    private_scan = _sign(
        runtime,
        {
            "schema": "proof-forge.task-qualification-private-scan-receipt.v1",
            "id": f"task-qualification-private-scan-{GATE_ID}",
            "version": "1.0.0",
            "candidate": _candidate_wire(candidate.identity),
            "evidenceCoreDigest": _digest_wire(_TQO.domain_digest(
                b"pf.taskqual.private-scan-core.v1", scan_core)),
            "scannerDigest": _digest_wire(_TQO.plain_sha256_digest(
                artifacts["artifactPayloads"][f"private-scan-scanner/{GATE_ID}"])),
            "policy": _ref_wire(refs[f"private-scan-policy/{GATE_ID}"]),
            "scannedEvidenceRefs": [evidence_ref],
            "scannedMembers": scanned,
            "findings": [],
            "result": "clean",
            "signatures": [],
        },
        b"pf.taskqual.private-scan-statement.v1",
        b"pf.taskqual.private-scan-signature.v1",
        ROLE_AQS,
        seeds,
    )
    private_scan_record = _typed_record(private_scan)

    # Reuse the repository producer to ensure the production snapshot parser
    # sees the exact accepted empty-ledger wire and Q+R signature rule.
    import revocation_ledger as revocation
    snapshot_bytes = revocation.produce_revocation_ledger_snapshot(
        id="taskqualification-d0-10-revocation-v1",
        version="1.0.0",
        policy_bytes=POLICY_PATH.read_bytes(),
        record_bytes=(),
        signers=tuple((key, seeds[key]) for key in sorted(ROLE_RS)),
    )
    snapshot_obj = _BTO.decode_canonical_pf_jcs(snapshot_bytes)
    snapshot_record = (
        snapshot_obj,
        snapshot_bytes,
        _TQO.recompute_typed_content_ref(snapshot_obj["schema"], snapshot_obj),
    )
    return {
        "eligible-stage0-handoff": handoff_record,
        "session-containment": containment_record,
        "freshness": freshness_record,
        "private-scan": private_scan_record,
        "revocation-snapshot": snapshot_record,
    }


def _normative_ref(path: Path, identifier: str) -> _TQO.NormativeDocumentRefV1:
    return _TQO.parse_qualification_normative_document_v1(
        path.read_bytes(), identifier
    )


def _d0_07_bridge(
    runtime,
    policy_ref: _BTO.ContentRef,
    seeds: dict[str, bytes],
) -> dict[str, Any]:
    candidate = load_git_candidate(D0_07_COMMIT, "TASK-D0-07")
    ruling = _normative_ref(
        _ROOT / "docs/governance/d0-07-closure-ruling.md", "GOV-D0CLOSE-001"
    )
    source_bytes = (
        _ROOT / "docs/governance/bootstrap-closure/TASK-D0-07.attest.json"
    ).read_bytes()
    completion = _sign(
        runtime,
        {
            "schema": "proof-forge.governance-bootstrap-completion.v1",
            "id": "governance-bootstrap-completion-d0-07",
            "version": "1.0.0",
            "taskId": "TASK-D0-07",
            "rulingId": "GOV-D0CLOSE-001",
            "purpose": "d0-07-historical-bootstrap-closeout",
            "completionCandidate": _candidate_wire(candidate.identity),
            "ruling": _TQO.normative_document_ref_to_wire(ruling),
            "sourceClosure": {
                "path": "docs/governance/bootstrap-closure/TASK-D0-07.attest.json",
                "digest": _digest_wire(_digest(source_bytes)),
            },
            "authorityPolicy": _ref_wire(policy_ref),
            "independentReviews": [],
            "signatures": [],
        },
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
        ROLE_AQS,
        seeds,
    )
    completion_bytes = _canonical(completion)
    bridge = _TQO.GovernanceBootstrapReceiptDependencyV1(
        kind="governance-bootstrap-receipt",
        taskId="TASK-D0-07",
        ruling=ruling,
        completionCommit=candidate.identity.commit,
        authorityPolicy=policy_ref,
        objectDigest=_TQO.domain_digest_raw(
            _TQO.DOMAIN_DEPENDENCY_OBJECT, completion_bytes
        ),
        objectBytesHex=completion_bytes.hex(),
        sourceClosureBytesHex=source_bytes.hex(),
        signatures=tuple(
            _TQO.parse_approval_signature(item, "d0-07-bridge.signature")
            for item in completion["signatures"]
        ),
    )
    return {
        "candidate": candidate,
        "completion": completion,
        "completionBytes": completion_bytes,
        "bridge": bridge,
    }


def _replace_table_value(payload: bytes, field: str, value: str) -> bytes:
    text = payload.decode("utf-8")
    pattern = re.compile(rf"^\| {re.escape(field)} \|.*\|$", re.MULTILINE)
    replacement = f"| {field} | {value} |"
    updated, count = pattern.subn(replacement, text)
    if count != 1:
        raise CloseoutError(f"AGENTS table field {field} did not match exactly once")
    return updated.encode("utf-8")


def _render_d_files(candidate: _FIXTURE.CandidateContext) -> dict[str, bytes]:
    agents = candidate.archive_projection.path_map["AGENTS.md"].content
    agents = _replace_table_value(
        agents,
        "Formal milestone",
        "**D0：9/10 authority-complete**；`TASK-D0-10` direct-child D 已完成结构收口，外部bootstrap receipt/projection待同一ceremony镜像后才更新为10/10",
    )
    agents = _replace_table_value(
        agents,
        "Active task",
        "无（D0-10已进入structural-only D状态；external one-time bridge completion pending）",
    )
    agents = _replace_table_value(
        agents,
        "D0-10 candidate",
        f"implementation candidate C `{candidate.identity.commit}`；本提交计划为其唯一direct-child D",
    )
    agents = _replace_table_value(
        agents,
        "Active development slice",
        "TASK-D0-10 candidate-owned approval与direct-child D structural closeout",
    )
    agents = _replace_table_value(
        agents,
        "Next development slice",
        "仅完成external receipt/GBC/Ledger projection与optional P mirror；此前不得启动D1实现",
    )
    agents = _replace_table_value(
        agents,
        "Known blocker",
        "无实现blocker；D0-10仍待D外签发receipt并验证one-time bridge，不把本地ceremony称为formal/hermetic",
    )

    phase4 = candidate.archive_projection.path_map[
        "docs/04-task-breakdown.md"
    ].content.decode("utf-8")
    lines = phase4.splitlines(keepends=True)
    row_indexes = [
        index for index, line in enumerate(lines)
        if line.startswith("| TASK-D0-10 |")
    ]
    if len(row_indexes) != 1:
        raise CloseoutError("TASK-D0-10 task row did not match exactly once")
    index = row_indexes[0]
    cells = [cell.strip() for cell in lines[index].strip().strip("|").split("|")]
    if len(cells) != 7 or cells[0] != TASK_ID or cells[6] != "in_progress":
        raise CloseoutError("TASK-D0-10 task row shape/status drift")
    cells[5] = f"{DEVELOPMENT_EVIDENCE_ID}, {LEDGER_EVIDENCE_ID}"
    cells[6] = "done"
    lines[index] = "| " + " | ".join(cells) + " |\n"
    phase4_after = "".join(lines).encode("utf-8")

    implementation_log = candidate.archive_projection.path_map[
        "docs/06-implementation-log.md"
    ].content
    log_entry = f"""

## 2026-07-24 — TASK-D0-10 direct-child D structural closeout

- Candidate：approved implementation candidate C `{candidate.identity.commit}`；本D只允许
  `AGENTS.md`、task row、implementation/review closeout记录与固定
  `bootstrap-approval.json`，不修改verifier/protocol/product/test/freeze。
- Evidence：C绑定development `{DEVELOPMENT_EVIDENCE_ID}`；D row另加入signed reserved
  `{LEDGER_EVIDENCE_ID}`，该ID在D中尚无Ledger row，只能由D外receipt projection镜像。
- Review：使用已接受的`single-maintainer-owner-waiver`；本记录不声称independent review。
- Boundary：本地Python seqpacket ceremony是bootstrap/development路径，不是ADR-0021完整static
  U/P/A custody、durable nonce store或formal/hermetic证据。D本身只有structural authority；external
  receipt/GBC/projection通过后才可把D0 checkpoint写为10/10 authority-complete。
""".encode("utf-8")
    if implementation_log.endswith(b"\n"):
        implementation_log = implementation_log.rstrip(b"\n") + log_entry
    else:
        implementation_log += log_entry

    review_report = candidate.archive_projection.path_map[
        "docs/07-review-report.md"
    ].content
    review_entry = f"""

## TASK-D0-10 single-maintainer closeout record

- Review mode: `single-maintainer-owner-waiver`; owner self-review, not independent review.
- Review commit: `{candidate.identity.commit}`.
- Executable checks retained: owner 8/8, verifier 111/111, protected adapter 39/39,
  authority-store qualified bootstrap-development matrix 26/26.
- Blocking findings recorded by the owner: none.
- Limitation: this task closeout does not change the Phase 7 release decision and does not
  claim formal or hermetic static custody evidence.
""".encode("utf-8")
    if review_report.endswith(b"\n"):
        review_report = review_report.rstrip(b"\n") + review_entry
    else:
        review_report += review_entry

    return {
        "AGENTS.md": agents,
        "docs/04-task-breakdown.md": phase4_after,
        "docs/06-implementation-log.md": implementation_log,
        "docs/07-review-report.md": review_report,
    }


def _task_row_from_sources(phase4: bytes, phase5: bytes) -> _TQO.TaskQualificationTaskRowV1:
    snapshot = _TQO.parse_taskqualification_snapshot_v1(phase4, phase5, TASK_ID)
    return snapshot.row


def _build_patch(
    candidate: _FIXTURE.CandidateContext,
    planned: dict[str, bytes],
    approval_task_row: _TQO.TaskQualificationTaskRowV1,
) -> tuple[_TQO.AllowedCloseoutPatchV1, bytes, _BTO.ContentRef]:
    semantic_changes = []
    for path in sorted(planned):
        before_entry = candidate.archive_projection.path_map.get(path)
        before = _digest(before_entry.content) if before_entry is not None else None
        after = _digest(planned[path])
        if before == after:
            continue
        semantic_changes.append((path, before, after))
    semantic = _TQO.SemanticCloseoutFileSetV1(
        schema="proof-forge.semantic-closeout-file-set.v1",
        id="semantic-closeout-d0-10",
        version="1.0.0",
        taskId=TASK_ID,
        preCloseCandidate=candidate.identity,
        changes=tuple(semantic_changes),
    )
    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=approval_task_row.taskId,
        output=approval_task_row.output,
        dependencies=approval_task_row.dependencies,
        prerequisites=approval_task_row.prerequisites,
        tests=approval_task_row.tests,
        evidenceIds=approval_task_row.evidenceIds + (LEDGER_EVIDENCE_ID,),
        status="done",
    )
    patch = _TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id="allowed-closeout-d0-10",
        version="1.0.0",
        taskId=TASK_ID,
        preCloseCandidate=candidate.identity,
        allowedPaths=tuple(sorted((*planned.keys(), APPROVAL_PATH))),
        semanticFileSetDigest=_FIXTURE.semantic_closeout_file_set_digest(semantic),
        resultingTaskRowDigest=_TQO.task_row_digest(resulting_row),
    )
    patch_bytes = _canonical(_FIXTURE.allowed_closeout_patch_to_wire(patch))
    return patch, patch_bytes, _FIXTURE.allowed_closeout_patch_content_ref(patch)


def _review_ref(candidate: _FIXTURE.CandidateContext, report: bytes) -> _TQO.IndependentReviewRefV1:
    return _TQO.IndependentReviewRefV1(
        reviewerId="davirain-owner-waiver",
        reviewerKind="human",
        invocationId="single-maintainer-owner-waiver-d0-10-closeout",
        reportDigest=_TQO.domain_digest_raw(_TQO.DOMAIN_REVIEW_REPORT, report),
        reviewCommit=candidate.identity.commit,
        reviewLink=(
            "https://github.com/DaviRain-Su/proof_forge/commit/"
            + candidate.identity.commit
        ),
        decision="approved",
        findings=(),
    )


def _member_wire(role: str, kind: str, descriptor: Any, payload: bytes) -> dict:
    if kind == "typed-content":
        return {"role": role, "kind": kind, "content": descriptor, "bytesHex": payload.hex()}
    if kind == "raw-source":
        return {"role": role, "kind": kind, "raw": descriptor, "bytesHex": payload.hex()}
    if kind == "archive":
        return {"role": role, "kind": kind, "archiveSha256": descriptor, "bytesHex": payload.hex()}
    if kind == "git-object":
        return {
            "role": role, "kind": kind, "objectId": descriptor,
            "objectType": "commit", "bytesHex": payload.hex(),
        }
    if kind == "review":
        return {
            "role": role, "kind": kind,
            "reviewerId": descriptor["reviewerId"],
            "reportDigest": descriptor["reportDigest"],
            "bytesHex": payload.hex(),
        }
    raise CloseoutError(f"unknown member kind: {kind}")


def _ancestry_members(candidate_commit: str, dedicated: set[str]) -> list[dict]:
    commits = _run_git(["rev-list", candidate_commit], maximum=256 * 1024).decode(
        "ascii"
    ).splitlines()
    result = []
    for commit in commits:
        if commit in dedicated:
            continue
        payload = _run_git(["cat-file", "commit", commit], maximum=4 * 1024 * 1024)
        result.append(_member_wire(
            f"ancestry-commit/{commit}", "git-object", commit, payload
        ))
    return result


def _build_approval_inputs(runtime, seeds: dict[str, bytes]) -> dict[str, Any]:
    candidate_commit = _require_clean_head()
    candidate = load_git_candidate(candidate_commit, TASK_ID)
    policy_bytes = POLICY_PATH.read_bytes()
    policy, policy_ref = _BTO.parse_bootstrap_authority_policy(policy_bytes)
    artifacts = _build_artifacts(runtime)
    profile, pin = _build_profile_and_pin(
        runtime,
        policy_ref,
        artifacts,
        "d0-10-bootstrap-approval",
        (GATE_ID,),
        artifacts["artifactMappings"],
        seeds,
    )
    command_policy = _build_command_policy(artifacts)
    command_policy_bytes = _canonical(_FIXTURE.command_policy_to_wire(command_policy))
    command_policy_ref = _FIXTURE.command_policy_content_ref(command_policy)
    evidence_bytes = _build_development_evidence(
        candidate, command_policy, artifacts
    )
    evidence_ref = _TQO.EvidenceRefV1(
        DEVELOPMENT_EVIDENCE_ID, _digest(evidence_bytes)
    )
    controls = _build_controls(
        runtime, candidate, policy_ref, evidence_bytes,
        command_policy, artifacts, seeds,
    )
    bridge_data = _d0_07_bridge(runtime, policy_ref, seeds)

    phase4_bytes = candidate.archive_projection.path_map[
        "docs/04-task-breakdown.md"
    ].content
    phase5_bytes = candidate.archive_projection.path_map[
        "docs/05-test-spec.md"
    ].content
    task_row = _task_row_from_sources(phase4_bytes, phase5_bytes)
    if (
        task_row.status != "in_progress"
        or task_row.evidenceIds != (DEVELOPMENT_EVIDENCE_ID,)
    ):
        raise CloseoutError("candidate C task row is not the expected in-progress evidence row")
    planned = _render_d_files(candidate)
    expected_resulting = _TQO.TaskQualificationTaskRowV1(
        taskId=task_row.taskId,
        output=task_row.output,
        dependencies=task_row.dependencies,
        prerequisites=task_row.prerequisites,
        tests=task_row.tests,
        evidenceIds=task_row.evidenceIds + (LEDGER_EVIDENCE_ID,),
        status="done",
    )
    planned_phase4 = planned["docs/04-task-breakdown.md"].decode("utf-8")
    expected_tail = (
        f"| {DEVELOPMENT_EVIDENCE_ID}, {LEDGER_EVIDENCE_ID} | done |"
    )
    if expected_tail not in planned_phase4:
        raise CloseoutError("planned D task row does not carry the reserved ID")
    patch, patch_bytes, patch_ref = _build_patch(candidate, planned, task_row)
    if patch.resultingTaskRowDigest != _TQO.task_row_digest(expected_resulting):
        raise CloseoutError("planned D resulting task-row digest drift")

    freeze_bytes = candidate.archive_projection.path_map[
        "docs/governance/task-freeze-packages/TASK-D0-10.json"
    ].content
    freeze_ref = _TQO.TaskFreezePackageRefV1(
        TASK_ID,
        _TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes),
    )
    ruling = _normative_ref(
        _ROOT / "docs/governance/task-qualification-bootstrap-ruling.md",
        "GOV-TASKQUAL-BOOTSTRAP-001",
    )
    review_bytes = candidate.archive_projection.path_map[OWNER_REVIEW_PATH].content
    review = _review_ref(candidate, review_bytes)
    bootstrap_gate = _TQO.D0_10BootstrapGateV1(
        gateId=GATE_ID,
        taskId=TASK_ID,
        testIds=(TEST_ID,),
        evidence=(evidence_ref,),
        commandPolicy=command_policy_ref,
        eligibleStage0Handoff=controls["eligible-stage0-handoff"][2],
        sessionContainment=controls["session-containment"][2],
        freshness=controls["freshness"][2],
        privateScan=controls["private-scan"][2],
        revocationSnapshot=controls["revocation-snapshot"][2],
    )
    bridge = bridge_data["bridge"]
    approval = {
        "schema": "proof-forge.d0-10-bootstrap-approval.v1",
        "id": "d0-10-bootstrap-approval-d0-10",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "ruling": _TQO.normative_document_ref_to_wire(ruling),
        "preCloseCandidate": _candidate_wire(candidate.identity),
        "taskRow": _FIXTURE.task_row_to_wire(task_row),
        "freezePackage": _FIXTURE.freeze_package_ref_to_wire(freeze_ref),
        "verifier": _TQO.verifier_identity_to_wire(artifacts["bootstrapVerifier"]),
        "protectedConsumer": _TQO.verifier_identity_to_wire(artifacts["adapter"]),
        "verifierClosureDigest": _digest_wire(_TQO.domain_digest(
            _TQO.DOMAIN_D0_10_VERIFIER_CLOSURE,
            _TQO.verifier_identity_to_wire(artifacts["bootstrapVerifier"]))),
        "consumerClosureDigest": _digest_wire(_TQO.domain_digest(
            _TQO.DOMAIN_D0_10_CONSUMER_CLOSURE,
            _TQO.verifier_identity_to_wire(artifacts["adapter"]))),
        "ledgerEvidenceId": LEDGER_EVIDENCE_ID,
        "tstDocSubprofile": SUBPROFILE,
        "bootstrapGate": {
            "gateId": bootstrap_gate.gateId,
            "taskId": bootstrap_gate.taskId,
            "testIds": list(bootstrap_gate.testIds),
            "evidence": [_FIXTURE.evidence_ref_to_wire(item) for item in bootstrap_gate.evidence],
            "commandPolicy": _ref_wire(bootstrap_gate.commandPolicy),
            "eligibleStage0Handoff": _ref_wire(bootstrap_gate.eligibleStage0Handoff),
            "sessionContainment": _ref_wire(bootstrap_gate.sessionContainment),
            "freshness": _ref_wire(bootstrap_gate.freshness),
            "privateScan": _ref_wire(bootstrap_gate.privateScan),
            "revocationSnapshot": _ref_wire(bootstrap_gate.revocationSnapshot),
        },
        "d0_07Bridge": {
            "kind": bridge.kind,
            "taskId": bridge.taskId,
            "ruling": _TQO.normative_document_ref_to_wire(bridge.ruling),
            "completionCommit": bridge.completionCommit,
            "authorityPolicy": _ref_wire(bridge.authorityPolicy),
            "objectDigest": _digest_wire(bridge.objectDigest),
            "objectBytesHex": bridge.objectBytesHex,
            "sourceClosureBytesHex": bridge.sourceClosureBytesHex,
            "signatures": [_TQO.approval_signature_to_wire(item) for item in bridge.signatures],
        },
        "allowedCloseoutPatch": _ref_wire(patch_ref),
        "independentReviews": [_TQO.independent_review_ref_to_wire(review)],
        "authorityPolicy": _ref_wire(policy_ref),
        "signatures": [],
    }
    approval = _sign(
        runtime,
        approval,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
        ROLE_AQS,
        seeds,
    )
    approval_bytes = _canonical(approval)

    profile_bytes = _canonical(_TQO.production_profile_to_wire(profile))
    members = [
        _member_wire("phase-4-source", "raw-source", {
            "path": "docs/04-task-breakdown.md",
            "digest": _digest_wire(_digest(phase4_bytes)),
        }, phase4_bytes),
        _member_wire("phase-5-source", "raw-source", {
            "path": "docs/05-test-spec.md",
            "digest": _digest_wire(_digest(phase5_bytes)),
        }, phase5_bytes),
        _member_wire("ruling-source", "raw-source", {
            "path": "docs/governance/task-qualification-bootstrap-ruling.md",
            "digest": _digest_wire(_digest(
                candidate.archive_projection.path_map[
                    "docs/governance/task-qualification-bootstrap-ruling.md"
                ].content)),
        }, candidate.archive_projection.path_map[
            "docs/governance/task-qualification-bootstrap-ruling.md"
        ].content),
        _member_wire("d0-07-ruling-source", "raw-source", {
            "path": "docs/governance/d0-07-closure-ruling.md",
            "digest": _digest_wire(_digest(
                candidate.archive_projection.path_map[
                    "docs/governance/d0-07-closure-ruling.md"
                ].content)),
        }, candidate.archive_projection.path_map[
            "docs/governance/d0-07-closure-ruling.md"
        ].content),
        _member_wire("freeze-package-source", "raw-source", {
            "path": "docs/governance/task-freeze-packages/TASK-D0-10.json",
            "digest": _digest_wire(freeze_ref.digest),
        }, freeze_bytes),
        _member_wire("candidate-archive", "archive",
                     _digest_wire(candidate.identity.archiveDigest), candidate.archive_bytes),
        _member_wire("candidate-commit-object", "git-object",
                     candidate.identity.commit, candidate.commit_bytes),
        _member_wire("authority-policy", "typed-content", _ref_wire(policy_ref), policy_bytes),
        _member_wire("production-profile", "typed-content",
                     _ref_wire(_TQO.production_profile_content_ref(profile)), profile_bytes),
        _member_wire("allowed-closeout-patch", "typed-content", _ref_wire(patch_ref), patch_bytes),
        _member_wire(f"command-policy/{GATE_ID}", "typed-content",
                     _ref_wire(command_policy_ref), command_policy_bytes),
        _member_wire(f"eligible-stage0-handoff/{GATE_ID}", "typed-content",
                     _ref_wire(controls["eligible-stage0-handoff"][2]),
                     controls["eligible-stage0-handoff"][1]),
        _member_wire(f"session-containment/{GATE_ID}", "typed-content",
                     _ref_wire(controls["session-containment"][2]),
                     controls["session-containment"][1]),
        _member_wire(f"freshness/{GATE_ID}", "typed-content",
                     _ref_wire(controls["freshness"][2]), controls["freshness"][1]),
        _member_wire(f"private-scan/{GATE_ID}", "typed-content",
                     _ref_wire(controls["private-scan"][2]), controls["private-scan"][1]),
        _member_wire("revocation-snapshot", "typed-content",
                     _ref_wire(controls["revocation-snapshot"][2]),
                     controls["revocation-snapshot"][1]),
        _member_wire("d0-07-governance-completion", "typed-content",
                     _ref_wire(_TQO.recompute_typed_content_ref(
                         bridge_data["completion"]["schema"], bridge_data["completion"])),
                     bridge_data["completionBytes"]),
        _member_wire("d0-07-completion-archive", "archive",
                     _digest_wire(bridge_data["candidate"].identity.archiveDigest),
                     bridge_data["candidate"].archive_bytes),
        _member_wire("d0-07-completion-commit-object", "git-object",
                     bridge_data["candidate"].identity.commit,
                     bridge_data["candidate"].commit_bytes),
        _member_wire(f"evidence/{DEVELOPMENT_EVIDENCE_ID}", "raw-source", {
            "path": f"evidence/{DEVELOPMENT_EVIDENCE_ID}",
            "digest": _digest_wire(evidence_ref.digest),
        }, evidence_bytes),
        _member_wire(
            f"review-report/{review.reviewerId}/{review.reportDigest.bytes.hex()}",
            "review",
            {"reviewerId": review.reviewerId,
             "reportDigest": _digest_wire(review.reportDigest)},
            review_bytes,
        ),
    ]
    members.extend(_ancestry_members(
        candidate.identity.commit,
        {candidate.identity.commit, bridge_data["candidate"].identity.commit},
    ))
    members.sort(key=lambda item: item["role"])
    bundle = {
        "schema": _TQO.BUNDLE_SCHEMA,
        "id": _TQO.OPERATION_BUNDLE_IDS["d0-10-bootstrap-approval"],
        "version": "1.0.0",
        "operation": "d0-10-bootstrap-approval",
        "verificationProfile": _TQO.production_profile_to_wire(profile),
        "expectedAuthorityPolicy": _ref_wire(policy_ref),
        "verificationInstant": VERIFICATION_INSTANT,
        "implementationInvocationId": "d0-10-closeout-implementation-0001",
        "members": members,
    }
    bundle_bytes = _canonical_large(bundle)
    verified = _VERIFIER.verify_d0_10_bootstrap_v1(bundle_bytes, approval_bytes)
    if isinstance(verified, _BTO.Rejected):
        raise CloseoutError(f"production approval pure verifier rejected: {verified.detail}")
    return {
        "candidate": candidate,
        "policy": policy,
        "policyRef": policy_ref,
        "policyBytes": policy_bytes,
        "artifacts": artifacts,
        "profile": profile,
        "profileBytes": profile_bytes,
        "pin": pin,
        "pinBytes": _canonical(_TQO.production_profile_pin_to_wire(pin)),
        "controls": controls,
        "approval": approval,
        "approvalBytes": approval_bytes,
        "patch": patch,
        "patchBytes": patch_bytes,
        "patchRef": patch_ref,
        "planned": planned,
        "evidenceBytes": evidence_bytes,
        "bundle": bundle,
        "bundleBytes": bundle_bytes,
        "members": members,
    }


def _protected_approval(runtime, data: dict[str, Any], seeds: dict[str, bytes]) -> bytes:
    candidate = data["candidate"]
    artifacts = data["artifacts"]
    profile = data["profile"]
    pin = data["pin"]
    policy_ref = data["policyRef"]
    operation = "d0-10-bootstrap-approval"
    run_id = "d0-10-approval-owner-0001"
    nonce = hashlib.sha256(run_id.encode("ascii")).hexdigest()
    isolation, isolation_ref = runtime._isolation_policy(run_id, nonce, 90)
    isolation_bytes = _canonical(isolation)
    service_seed = seeds["key-authority-store-service"]
    descriptor, descriptor_ref = runtime._descriptor(
        run_id,
        runtime._BTP.ed25519_public_key_from_seed(service_seed),
        artifacts["authorityStore"],
        artifacts["supervisor"],
        isolation_ref,
    )
    descriptor_bytes = _canonical(descriptor)
    snapshot_bytes = data["controls"]["revocation-snapshot"][1]
    head_sequence = 1
    head_digest = hashlib.sha256(
        b"pf.taskqual.d0-10-approval-head.v1\x00" + snapshot_bytes
    ).digest()
    handoff = {
        "schema": runtime._STORE.HANDOFF_SCHEMA,
        "id": f"task-qualification-protected-handoff-{run_id}",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "candidate": _candidate_wire(candidate.identity),
        "authorityPolicy": _ref_wire(policy_ref),
        "productionProfilePin": _ref_wire(
            _TQO.production_profile_pin_content_ref(pin)),
        "gateSetDigest": _digest_wire(profile.gateSetDigest),
        "adapter": _TQO.verifier_identity_to_wire(artifacts["adapter"]),
        "snapshotParser": _TQO.verifier_identity_to_wire(artifacts["snapshotParser"]),
        "authorityStoreService": _ref_wire(descriptor_ref),
        "trustedClockService": _TQO.verifier_identity_to_wire(artifacts["trustedClock"]),
        "revocationHead": {
            "headSequence": head_sequence,
            "headDigest": _digest_wire(_BTO.Digest("sha256", head_digest)),
        },
        "trustedInstant": VERIFICATION_INSTANT,
        "channels": dict(runtime.FIXED_FDS),
        "signatures": [],
    }
    handoff["signatures"] = runtime._sign_without_signatures_field(
        handoff,
        runtime._STORE.HANDOFF_STATEMENT_DOMAIN,
        runtime._STORE.HANDOFF_SIGNATURE_DOMAIN,
        ROLE_AQS,
        seeds,
    )
    handoff_bytes = _canonical(handoff)
    handoff_digest = runtime._STORE.domain_digest(
        runtime._STORE.HANDOFF_FULL_DOMAIN, handoff
    ).bytes
    clock = {
        "schema": runtime._STORE.CLOCK_OBSERVATION_SCHEMA,
        "id": "taskqualification-d0-10-approval-clock-v1",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "trustedClockService": _TQO.verifier_identity_to_wire(artifacts["trustedClock"]),
        "observedAt": VERIFICATION_INSTANT,
        "clockSourceDigest": _digest_wire(_digest(b"d0-10 local owner clock")),
        "signatures": [],
    }
    clock["signatures"] = runtime._sign_without_signatures_field(
        clock,
        runtime._STORE.CLOCK_STATEMENT_DOMAIN,
        runtime._STORE.CLOCK_SIGNATURE_DOMAIN,
        ROLE_AQS,
        seeds,
    )
    clock_bytes = _canonical(clock)

    entries = {
        member["role"]: bytes.fromhex(member["bytesHex"])
        for member in data["members"]
    }
    entries["bootstrap-approval"] = data["approvalBytes"]
    entries["production-profile-pin"] = data["pinBytes"]
    entries["live-handoff"] = handoff_bytes
    entries["live-session"] = _canonical({
        "schema": "proof-forge.task-qualification-live-session.v1", "id": run_id
    })
    entries["trusted-clock-observation"] = clock_bytes
    entries["current-revocation-snapshot"] = snapshot_bytes
    entries["authority-store-service-descriptor"] = descriptor_bytes
    entries["store-isolation-policy"] = isolation_bytes
    entries.update(data["artifacts"]["artifactPayloads"])
    for payload_map in data["artifacts"]["protectedPayloadMaps"]:
        entries.update(payload_map)
    provenance = {
        "schema": runtime._STORE.PROVENANCE_BUNDLE_SCHEMA,
        "id": "protected-taskqualification-provenance-d0-10-approval",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": operation,
        "runId": run_id,
        "nonce": nonce,
        "subjectDigest": _digest_wire(_digest(data["approvalBytes"])),
        "candidateArchiveSha256": _digest_wire(candidate.identity.archiveDigest),
        "entries": [
            {"role": role, "bytesHex": payload.hex()}
            for role, payload in sorted(entries.items())
        ],
    }
    provenance_bytes = _canonical_large(provenance)
    _TQO.parse_provenance_bundle(provenance, "d0-10-approval-provenance")
    tpl = runtime._STORE.HandoffTuple(
        taskId=TASK_ID,
        operation=operation,
        runId=run_id,
        nonce=nonce,
        service=_ref_wire(descriptor_ref),
        handoffDigest=handoff_digest,
        headSequence=head_sequence,
        headDigest=head_digest,
    )
    objects = {
        "authority-policy": data["policyBytes"],
        "production-profile-pin": data["pinBytes"],
        "production-profile": data["profileBytes"],
        "adapter": _canonical(_TQO.verifier_identity_to_wire(artifacts["adapter"])),
        "snapshot-parser": _canonical(_TQO.verifier_identity_to_wire(artifacts["snapshotParser"])),
        "authority-store-service": descriptor_bytes,
        "trusted-clock-service": _canonical(_TQO.verifier_identity_to_wire(artifacts["trustedClock"])),
        "revocation-snapshot": snapshot_bytes,
    }
    manifest = {
        "schema": runtime.QUALIFIED_SCHEMA,
        "operationBytesHex": operation.encode("ascii").hex(),
        "handoffBytesHex": handoff_bytes.hex(),
        **runtime.FIXED_FDS,
    }
    result = runtime._run_adapter_process(
        [sys.executable, "-I", "-S", str(runtime._HERE), "--adapter-once"],
        _canonical(manifest),
        {
            "policy": data["policyBytes"],
            "archive": candidate.archive_bytes,
            "provenance": provenance_bytes,
            "clock": clock_bytes,
        },
        tpl,
        profile.gateSetDigest.bytes,
        objects,
        service_seed,
        {key: seeds[key] for key in ROLE_AQS},
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise CloseoutError(f"protected approval adapter rejected: {detail}")
    acceptance = result.stdout
    wire = _BTO.decode_canonical_pf_jcs(acceptance)
    if wire.get("operation") != operation or wire.get("authorityClass") != "production-candidate-bound":
        raise CloseoutError("protected approval acceptance identity mismatch")
    return acceptance


def _write_public(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def prepare_closeout(runtime, seed_root: Path, output_root: Path) -> int:
    """Build and verify C-bound approval, then emit the exact D staging plan."""
    policy, _ = _BTO.parse_bootstrap_authority_policy(POLICY_PATH.read_bytes())
    seeds = runtime._load_production_seeds(seed_root, policy)
    data = _build_approval_inputs(runtime, seeds)
    acceptance = _protected_approval(runtime, data, seeds)

    output_root.mkdir(parents=True, exist_ok=True)
    _write_public(output_root / "bootstrap-approval.json", data["approvalBytes"])
    _write_public(output_root / "allowed-closeout-patch.json", data["patchBytes"])
    _write_public(output_root / "development-evidence.json", data["evidenceBytes"])
    _write_public(
        output_root / "revocation-snapshot.json",
        data["controls"]["revocation-snapshot"][1],
    )
    _write_public(output_root / "protected-approval-acceptance.json", acceptance)
    for path, payload in data["planned"].items():
        _write_public(output_root / "planned" / path, payload)
    metadata = {
        "schema": "proof-forge.task-qualification-closeout-plan.v1",
        "taskId": TASK_ID,
        "preCloseCandidate": _candidate_wire(data["candidate"].identity),
        "approvalSha256": hashlib.sha256(data["approvalBytes"]).hexdigest(),
        "approvalDigest": _digest_wire(_TQO.domain_digest(
            _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, data["approval"])),
        "allowedCloseoutPatch": _ref_wire(data["patchRef"]),
        "developmentEvidenceId": DEVELOPMENT_EVIDENCE_ID,
        "ledgerEvidenceId": LEDGER_EVIDENCE_ID,
        "protectedAcceptanceSha256": hashlib.sha256(acceptance).hexdigest(),
        "revocationSnapshotSha256": hashlib.sha256(
            data["controls"]["revocation-snapshot"][1]
        ).hexdigest(),
        "plannedPaths": sorted((*data["planned"].keys(), APPROVAL_PATH)),
        "authority": "bootstrap-development; not formal or hermetic static custody",
    }
    _write_public(output_root / "plan.json", _canonical(metadata))
    print(
        "TASK-D0-10 closeout plan: PASS; C="
        + data["candidate"].identity.commit
        + "; approvalSha256="
        + metadata["approvalSha256"]
        + "; protectedAcceptanceSha256="
        + metadata["protectedAcceptanceSha256"]
    )
    return 0
