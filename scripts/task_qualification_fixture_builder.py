"""SPEC-TASKQUAL-001 fixture builder for TST-DOC-001/task-qualification-v1.

This module builds legal fixture chains for the pure verifier RED matrix.
It constructs:
    - Fixture policy with RFC 8032 §7.1 test vector principals
    - Synthetic candidate archives (ustar) with f1/f2 commit/tree first bytes
    - PHASE-4/5 source documents (synthetic)
    - Freeze package source
    - Ruling source
    - Command policy, gate, evidence, reviews
    - Allowed closeout patch, semantic closeout file set, closeout file set
    - TaskQualificationV1, TaskCompletionReceiptV1
    - D0_10BootstrapApprovalV1, D0_10BootstrapReceiptV1
    - GovernanceBootstrapCompletionV1 (D0-07 bridge)

All fixtures use the fixed fixture namespace and return
``fixture-non-authoritative``. They never close a task.
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import tarfile
from dataclasses import dataclass
from typing import Tuple

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import evidence_v1_core as _EVIDENCE
import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV

canonical_pf_jcs = _BTO.canonical_pf_jcs
decode_canonical_pf_jcs = _BTO.decode_canonical_pf_jcs
domain_digest = _TQO.domain_digest
plain_sha256_digest = _TQO.plain_sha256_digest
digest_to_wire = _TQO.digest_to_wire
content_ref_to_wire = _TQO.content_ref_to_wire

# ---------------------------------------------------------------------------
# Fixture constants
# ---------------------------------------------------------------------------

FIXTURE_TASK_ID = "TASK-D1-FIXTURE"
FIXTURE_TASK_ID_LOWER = "task-d1-fixture"
FIXTURE_GATE_ID = "fixture-gate-d1-fixture"
FIXTURE_TEST_ID = "TST-DOC-001"
FIXTURE_SUBPROFILE = "TST-DOC-001/task-qualification-v1"
FIXTURE_EVIDENCE_ID = "EV-20260721-0001"
# §7: approval/receipt ledgerEvidenceId must be an exact real EV-YYYYMMDD-NNNN
# ID, distinct from the raw gate EV. The fixture reuses the development EV
# namespace; the ledgerEvidenceId is a separate reserved ID.
FIXTURE_LEDGER_EVIDENCE_ID = "EV-20260721-0042"
FIXTURE_REVIEWER_ID = "fixture-reviewer-independent-ai"
FIXTURE_REVIEW_INVOCATION_ID = "task-qualification-fixture-run-review-0001"
FIXTURE_IMPL_INVOCATION_ID = "task-qualification-fixture-run-impl-0001"
FIXTURE_VERIFICATION_INSTANT = "2026-07-21T00:00:00Z"
FIXTURE_REVIEW_LINK = "https://fixture.example/review/0001"

# Planned closeout files for the qualification fixture, excluding the fixed
# Q path (qualification.json). These are the semantic closeout locations that
# D writes; their after-bytes here must match the ones used to build D in
# build_completion_receipt_chain so the §6 reconstruction the verifier
# performs yields exactly patch.semanticFileSetDigest.
_FIXTURE_PLANNED_SEMANTIC_FILES = {
    "docs/04-task-breakdown.md": b"# PHASE-4 fixture updated",
    "docs/05-test-spec.md": b"# PHASE-5 fixture updated",
    "docs/06-implementation-log.md": b"# Implementation log fixture",
    "docs/07-review-report.md": b"# Review report fixture",
}
_FIXTURE_QUALIFICATION_PATH = (
    "docs/governance/task-qualifications/TASK-D1-FIXTURE/qualification.json"
)

# Dependency task used by build_fixture_chain_with_dependency. A task-qualification
# dependency references a completed prior task's receipt; this synthetic task ID
# stands in for that prior task in the fixture.
FIXTURE_DEP_TASK_ID = "TASK-D0-09"
FIXTURE_REVIEW_COMMIT = "f1" + "a" * 38  # Must match candidate commit
FIXTURE_COMMAND_POLICY_ID = "tst-doc-001.task-qualification-v1"

# Fixture document IDs (synthetic, not accepted normative)
FIXTURE_PHASE4_ID = "PHASE-4-FIXTURE"
FIXTURE_PHASE5_ID = "PHASE-5-FIXTURE"
FIXTURE_RULING_ID = "GOV-TASKQUAL-FIXTURE-001"
FIXTURE_DOCUMENT_REVIEW_COMMIT = "f0" * 20
FIXTURE_PHASE4_PATH = "fixtures/task-qualification/04-task-breakdown.md"
FIXTURE_PHASE5_PATH = "fixtures/task-qualification/05-test-spec.md"
FIXTURE_FREEZE_PATH = "fixtures/task-qualification/freeze.json"
FIXTURE_RULING_PATH = "fixtures/task-qualification/ruling.md"

# Candidate commit/tree first bytes (§8.2 fixture policy)
FIXTURE_CANDIDATE_COMMIT_PREFIX = "f1"
FIXTURE_CANDIDATE_TREE_PREFIX = "f2"


# ---------------------------------------------------------------------------
# Fixture signing helpers
# ---------------------------------------------------------------------------

def _sign_with_vector(vector_num: int, message: bytes) -> bytes:
    """Sign a message with an RFC 8032 test vector seed."""
    seed = _TQO.RFC8032_VECTOR_SEEDS[vector_num]
    return _BTP.sign_ed25519(seed, message)


def _fixture_signature(key_id: str, message: bytes) -> _TQO.ApprovalSignatureV1:
    """Create a fixture approval signature for the given key_id."""
    vector_map = {
        _TQO.FIXTURE_KEY_ARCHITECTURE: 1,
        _TQO.FIXTURE_KEY_QUALITY: 2,
        _TQO.FIXTURE_KEY_SECURITY: 3,
    }
    if key_id not in vector_map:
        raise ValueError(f"unknown fixture key_id: {key_id}")
    sig = _sign_with_vector(vector_map[key_id], message)
    return _TQO.ApprovalSignatureV1(
        keyId=key_id,
        algorithm="ed25519",
        signature=sig,
    )


def _sign_subject(
    subject_obj: dict,
    statement_domain: bytes,
    signature_domain: bytes,
    key_ids: tuple = (
        _TQO.FIXTURE_KEY_ARCHITECTURE,
        _TQO.FIXTURE_KEY_QUALITY,
        _TQO.FIXTURE_KEY_SECURITY,
    ),
) -> list:
    """Sign a subject object and return the signatures list."""
    unsigned = dict(subject_obj)
    unsigned["signatures"] = []
    statement_digest = domain_digest(statement_domain, unsigned)
    message = signature_domain + b"\x00" + statement_digest.bytes
    sigs = []
    for key_id in sorted(key_ids):
        sig = _fixture_signature(key_id, message)
        sigs.append(sig)
    # Sort by keyId
    sigs.sort(key=lambda s: s.keyId)
    return [_TQO.approval_signature_to_wire(s) for s in sigs]


# ---------------------------------------------------------------------------
# Synthetic candidate archive builder
# ---------------------------------------------------------------------------

def build_synthetic_candidate_archive(
    task_id: str,
    files: dict,  # path -> content
) -> bytes:
    """Build a ustar archive for a synthetic candidate."""
    buf = io.BytesIO()
    prefix = f"{task_id.lower()}/"
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for path, content in sorted(files.items()):
            full_name = prefix + path
            info = tarfile.TarInfo(name=full_name)
            info.size = len(content)
            info.mode = 0o644
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            tar.addfile(info, io.BytesIO(content))
    return buf.getvalue()


def build_synthetic_git_commit(
    tree_sha: str,
    parent_sha: str | None,
    message: str = "fixture candidate",
    author_time: int = 0,
    committer_time: int = 0,
) -> bytes:
    """Build a raw git commit payload."""
    lines = [f"tree {tree_sha}"]
    if parent_sha:
        lines.append(f"parent {parent_sha}")
    lines.append(f"author Fixture <fixture@example.com> {author_time} +0000")
    lines.append(f"committer Fixture <fixture@example.com> {committer_time} +0000")
    lines.append("")
    lines.append(message)
    lines.append("")
    return "\n".join(lines).encode("utf-8")


@dataclass(frozen=True)
class CandidateContext:
    """A synthetic candidate with archive, commit, and identity."""
    identity: _BTO.CandidateIdentity
    archive_bytes: bytes
    commit_bytes: bytes
    archive_projection: _TQO.ArchiveProjection
    commit_object: _TQO.GitCommitObject


_SYNTHETIC_CANDIDATE_CACHE = {}


def build_synthetic_candidate(
    task_id: str,
    files: dict,
    parent_sha: str | None = None,
    commit_prefix: str = FIXTURE_CANDIDATE_COMMIT_PREFIX,
    tree_prefix: str | None = FIXTURE_CANDIDATE_TREE_PREFIX,
) -> CandidateContext:
    """Build a synthetic candidate with the fixture C commit/tree prefixes."""
    cache_key = (
        task_id, tuple(sorted(files.items())), parent_sha, commit_prefix,
        tree_prefix)
    cached = _SYNTHETIC_CANDIDATE_CACHE.get(cache_key)
    if cached is not None:
        return cached
    working_files = dict(files)
    archive_bytes = build_synthetic_candidate_archive(task_id, working_files)
    archive_proj = _TQO.parse_ustar_archive(archive_bytes, task_id, "candidate")
    tree_sha = _TQO.build_git_tree_from_archive(archive_proj)
    if tree_prefix is not None and not tree_sha.startswith(tree_prefix):
        padding_path = "fixtures/task-qualification/tree-padding.bin"
        nonce = 0
        while not tree_sha.startswith(tree_prefix):
            nonce += 1
            working_files[padding_path] = f"tree-padding={nonce}\n".encode("ascii")
            archive_bytes = build_synthetic_candidate_archive(
                task_id, working_files)
            archive_proj = _TQO.parse_ustar_archive(
                archive_bytes, task_id, "candidate")
            tree_sha = _TQO.build_git_tree_from_archive(archive_proj)

    commit_payload = build_synthetic_git_commit(tree_sha, parent_sha)
    commit_sha = _TQO.git_sha1_object("commit", commit_payload)
    commit_obj = _TQO.parse_git_commit_object(commit_payload, "candidate")

    # Ensure commit starts with f1
    if not commit_sha.startswith(commit_prefix):
        nonce = 0
        while not commit_sha.startswith(commit_prefix):
            nonce += 1
            msg = f"fixture candidate nonce={nonce}"
            commit_payload = build_synthetic_git_commit(tree_sha, parent_sha, message=msg)
            commit_sha = _TQO.git_sha1_object("commit", commit_payload)
            commit_obj = _TQO.parse_git_commit_object(commit_payload, "candidate")

    identity = _BTO.CandidateIdentity(
        commit=commit_sha,
        treeObjectId=tree_sha,
        archiveDigest=archive_proj.archiveSha256,
        digest=domain_digest(_TQO.DOMAIN_CANDIDATE, {
            "commit": commit_sha,
            "treeObjectId": tree_sha,
            "archiveSha256": digest_to_wire(archive_proj.archiveSha256),
        }),
    )
    result = CandidateContext(
        identity=identity,
        archive_bytes=archive_bytes,
        commit_bytes=commit_payload,
        archive_projection=archive_proj,
        commit_object=commit_obj,
    )
    _SYNTHETIC_CANDIDATE_CACHE[cache_key] = result
    return result


# ---------------------------------------------------------------------------
# Fixture document builders
# ---------------------------------------------------------------------------

def _fixture_document(document_id: str, title: str, body: str) -> bytes:
    """Build the exact §8.3 fixture Markdown carrier."""
    if not body.endswith("\n") or body.endswith("\n\n"):
        raise ValueError("fixture document body must have exactly one trailing LF")
    return (
        "---\n"
        f"id: {document_id}\n"
        f"title: {title}\n"
        "status: accepted\n"
        "owner: fixture-owner\n"
        "updated: 2026-07-21\n"
        "normative: true\n"
        "approvers: fixture-architecture, fixture-quality, fixture-security\n"
        "approvedAt: 2026-07-21\n"
        f"reviewCommit: {FIXTURE_DOCUMENT_REVIEW_COMMIT}\n"
        "reviewLink: https://fixture.example/task-qualification-review\n"
        "openFindings: none\n"
        "---\n\n"
        f"{body}"
    ).encode("utf-8")


def build_phase4_source(
    candidate: CandidateContext,
    dependencies: tuple = (),
    *,
    task_id: str = FIXTURE_TASK_ID,
    output: str = "fixture qualification verifier test",
    prerequisites: tuple = ("SPEC-TASKQUAL-001@accepted",),
    evidence_ids: tuple = (FIXTURE_EVIDENCE_ID,),
) -> bytes:
    """Build the exact synthetic PHASE-4 fixture task table."""
    del candidate
    dep_cell = ", ".join(dependencies) if dependencies else "—"
    prereq_cell = ", ".join(prerequisites) if prerequisites else "—"
    evidence_cell = ", ".join(evidence_ids) if evidence_ids else "—"
    body = (
        "# PHASE-4-FIXTURE: Task Table\n\n"
        "| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |\n"
        "|---|---|---|---|---|---|---|\n"
        f"| {task_id} | {output} | {dep_cell} | {prereq_cell} | "
        f"{FIXTURE_TEST_ID} | {evidence_cell} | in_progress |\n"
    )
    return _fixture_document(
        FIXTURE_PHASE4_ID, "Fixture task table", body)


def build_phase5_source(candidate: CandidateContext) -> bytes:
    """Build the exact synthetic PHASE-5 fixture test catalog."""
    del candidate
    body = (
        "# PHASE-5-FIXTURE: Test Spec\n\n"
        "TST-DOC-001/task-qualification-v1\n\n"
        "| ID | 测试对象 |\n"
        "|---|---|\n"
        "| TST-DOC-001 | task-qualification-v1 |\n"
    )
    return _fixture_document(
        FIXTURE_PHASE5_ID, "Fixture test specification", body)


def build_freeze_package_source(
    candidate: CandidateContext,
    dependencies: tuple = (),
    *,
    freeze_commit: str | None = None,
) -> bytes:
    """Build synthetic freeze package source bytes.

    The dependencies list must match the taskRow.dependencies (§3 row-vs-package
    exact equality). For the dependency-chain fixture, pass
    (FIXTURE_DEP_TASK_ID,).
    """
    package = {
        "schemaVersion": 1,
        "taskId": FIXTURE_TASK_ID,
        "frozenAt": "2026-07-21",
        "freezeCommit": freeze_commit or candidate.identity.commit,
        "output": "fixture qualification verifier test",
        "dependencies": list(dependencies),
        "prerequisites": ["SPEC-TASKQUAL-001@accepted"],
        "tests": [FIXTURE_TEST_ID],
        "inScope": [
            "fixture parser and verifier coverage",
            "fixture policy and resolved blob",
            "fixture RED matrix self-test",
        ],
        "outOfScope": [
            "production policy",
            "release aggregate",
            "formal closeout evidence",
        ],
        "doneWhen": [
            "fixture RED matrix passes",
        ],
        "overflowPolicy": "fixture only",
        "maxCalendarDays": 5,
        "maxCommits": 20,
        "notes": "fixture freeze package",
    }
    # Canonical PF-JCS encode
    return canonical_pf_jcs(package).encode("utf-8") if False else json.dumps(package, separators=(",", ":")).encode("utf-8")


def _fixture_ruling_source(document_id: str, text: str) -> bytes:
    return _fixture_document(
        document_id,
        f"Fixture ruling {document_id}",
        f"# {document_id}\n\n{text}\n",
    )


def build_ruling_source(candidate: CandidateContext) -> bytes:
    """Build a closed synthetic ruling source document."""
    del candidate
    return _fixture_ruling_source(
        FIXTURE_RULING_ID,
        "Fixture ruling for task qualification verifier test.")


# ---------------------------------------------------------------------------
# Fixture evidence builder
# ---------------------------------------------------------------------------

def build_evidence_source(
    candidate: CandidateContext,
    gate_id: str = FIXTURE_GATE_ID,
    task_id: str = FIXTURE_TASK_ID,
) -> bytes:
    """Build a complete canonical evidence-v1 fixture projection."""
    payload = lambda role: (
        b"pf.taskqual.fixture-resolved-payload.v1\x00" + role.encode("ascii"))
    tool_id = f"fixture-resolved-{gate_id}-resolved-tool"
    sandbox_id = f"fixture-resolved-{gate_id}-sandbox-policy"
    probe_id = f"fixture-resolved-{gate_id}-resolved-probe"
    probe_bytes = payload(f"resolved-probe/{gate_id}")
    artifact_bytes = b"fixture retained artifact\n"
    log_bytes = b"fixture command log\n"
    inputs = [
        {
            "role": "candidate-archive",
            "path": "candidate/archive.tar",
            "sha256": candidate.identity.archiveDigest.bytes.hex(),
            "size": len(candidate.archive_bytes),
        },
        {
            "role": "sandbox-probe-wrapper",
            "path": "inputs/probe-wrapper.bin",
            "sha256": hashlib.sha256(probe_bytes).hexdigest(),
            "size": len(probe_bytes),
        },
    ]
    artifacts = [{
        "target": "docs",
        "role": "task-qualification-fixture",
        "path": "artifacts/fixture.bin",
        "mediaType": "application/octet-stream",
        "sha256": hashlib.sha256(artifact_bytes).hexdigest(),
        "size": len(artifact_bytes),
        "retained": True,
    }]
    logs = [{
        "path": "logs/fixture.log",
        "sha256": hashlib.sha256(log_bytes).hexdigest(),
        "size": len(log_bytes),
        "truncated": False,
        "privateDataScan": "passed",
    }]
    evidence = {
        "schema": "proof-forge.evidence.v1",
        "id": FIXTURE_EVIDENCE_ID,
        "gate": {
            "id": gate_id,
            "taskId": task_id,
            "testIds": [FIXTURE_TEST_ID],
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
            "profileId": "taskqual-fixture-host",
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
        "sandboxPolicies": [{
            "id": sandbox_id,
            "engine": "sandbox-exec",
            "engineSha256": "88" * 32,
            "defaultAction": "deny",
            "network": "deny-all",
            "templateSha256": "99" * 32,
            "renderedSha256": hashlib.sha256(
                payload(f"sandbox-policy/{gate_id}")).hexdigest(),
            "probes": [{"id": probe_id, "status": "passed"}],
        }],
        "tools": [{
            "id": tool_id,
            "version": "1.0.0",
            "source": "content-addressed-cache",
            "assetSha256": "bb" * 32,
            "executableSha256": hashlib.sha256(
                payload(f"resolved-tool/{gate_id}")).hexdigest(),
            "closureSha256": hashlib.sha256(
                payload(f"resolved-tool-closure/{gate_id}")).hexdigest(),
        }],
        "command": {
            "argv": ["/usr/bin/python3", "-c", "print('fixture')"],
            "cwdRelative": ".",
            "startedUtc": "2026-07-21T00:00:00Z",
            "endedUtc": "2026-07-21T00:00:01Z",
            "durationMs": 1,
            "attempts": [{
                "number": 1,
                "exitCode": 0,
                "signal": None,
                "timedOut": False,
                "stdoutLog": "logs/fixture.log",
                "stderrLog": "logs/fixture.log",
            }],
        },
        "inputs": inputs,
        "artifacts": artifacts,
        "artifactSetSha256": "",
        "observations": [{
            "step": "task-qualification-fixture",
            "status": "passed",
            "return": 0,
            "logicalState": {"gate": gate_id},
            "effects": [],
            "errorClass": None,
        }],
        "logs": logs,
        "result": "passed",
        "skipAuthorization": None,
    }
    evidence["artifactSetSha256"] = _EVIDENCE.artifact_set_sha256(artifacts)
    encoded = _EVIDENCE.canonical_bytes(evidence)
    _EVIDENCE.validate_evidence(_EVIDENCE.decode_json(encoded))
    return encoded


# ---------------------------------------------------------------------------
# Fixture review report builder
# ---------------------------------------------------------------------------

def build_review_report(candidate: CandidateContext) -> bytes:
    """Build synthetic review report bytes (no P0/P1 findings)."""
    content = f"""# Independent Review Report (FIXTURE)

Reviewer: {FIXTURE_REVIEWER_ID}
Invocation: {FIXTURE_REVIEW_INVOCATION_ID}
Review commit: {candidate.identity.commit}

## Summary

The fixture chain is well-formed and passes all structural checks.

## Findings

No P0 or P1 findings.

Severity: P2
The fixture is non-authoritative and cannot close a task.
"""
    return content.encode("utf-8")


def build_review_report_digest(report_bytes: bytes) -> _BTO.Digest:
    """Compute the review report digest."""
    return _BTO.Digest(
        algorithm="sha256",
        bytes=hashlib.sha256(_TQO.DOMAIN_REVIEW_REPORT + b"\x00" + report_bytes).digest(),
    )


# ---------------------------------------------------------------------------
# Fixture command policy builder
# ---------------------------------------------------------------------------

def build_command_policy(
    candidate: CandidateContext,
    gate_id: str,
    fixture_policy: _TQO.FixturePolicyV1,
) -> _TQO.TaskCommandPolicyV1:
    """Build a fixture command policy for a gate."""
    # Build fixture resolved blobs for tool/probe/sandbox/verifier
    tool_blob = _TQO.build_fixture_resolved_blob(gate_id, "resolved-tool", b"fixture tool payload")
    probe_blob = _TQO.build_fixture_resolved_blob(gate_id, "resolved-probe", b"fixture probe payload")
    sandbox_blob = _TQO.build_fixture_resolved_blob(gate_id, "sandbox-policy", b"fixture sandbox payload")
    verifier_exec_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-executable", b"fixture verifier exec")
    verifier_closure_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-closure", b"fixture verifier closure")
    verifier_build_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-build-policy", b"fixture verifier build")

    tool_ref = _TQO.fixture_resolved_blob_content_ref(tool_blob)
    probe_ref = _TQO.fixture_resolved_blob_content_ref(probe_blob)
    sandbox_ref = _TQO.fixture_resolved_blob_content_ref(sandbox_blob)
    verifier_exec_ref = _TQO.fixture_resolved_blob_content_ref(verifier_exec_blob)
    verifier_closure_ref = _TQO.fixture_resolved_blob_content_ref(verifier_closure_blob)
    verifier_build_ref = _TQO.fixture_resolved_blob_content_ref(verifier_build_blob)

    verifier = _TQO.VerifierIdentityV1(
        id=f"fixture-verifier-{gate_id}",
        executable=verifier_exec_ref,
        closure=verifier_closure_ref,
        sourceDigest=plain_sha256_digest(b"fixture verifier source"),
        buildPolicy=verifier_build_ref,
    )

    return _TQO.TaskCommandPolicyV1(
        schema="proof-forge.task-command-policy.v1",
        id=FIXTURE_COMMAND_POLICY_ID,
        version="1.0.0",
        taskId=FIXTURE_TASK_ID,
        testIds=(FIXTURE_TEST_ID,),
        argv=("/usr/bin/python3", "-c", "print('fixture')"),
        environment=(
            ("HOME", "/var/empty"),
            ("LC_ALL", "C"),
            ("PATH", "/usr/bin:/bin"),
            ("TZ", "UTC"),
        ),
        tool=tool_ref,
        probe=probe_ref,
        sandboxPolicy=sandbox_ref,
        verifier=verifier,
    )


def command_policy_to_wire(cmd: _TQO.TaskCommandPolicyV1) -> dict:
    """Convert a TaskCommandPolicyV1 to wire format."""
    return {
        "schema": cmd.schema,
        "id": cmd.id,
        "version": cmd.version,
        "taskId": cmd.taskId,
        "testIds": list(cmd.testIds),
        "argv": list(cmd.argv),
        "environment": [{"name": n, "value": v} for n, v in cmd.environment],
        "tool": content_ref_to_wire(cmd.tool),
        "probe": content_ref_to_wire(cmd.probe),
        "sandboxPolicy": content_ref_to_wire(cmd.sandboxPolicy),
        "verifier": _TQO.verifier_identity_to_wire(cmd.verifier),
    }


def command_policy_content_ref(cmd: _TQO.TaskCommandPolicyV1) -> _BTO.ContentRef:
    """Compute the ContentRef for a TaskCommandPolicyV1."""
    wire = command_policy_to_wire(cmd)
    digest = domain_digest(_TQO.DOMAIN_TASK_COMMAND_POLICY, wire)
    return _BTO.ContentRef(schema=cmd.schema, id=cmd.id, version=cmd.version, digest=digest)


def _fixture_artifact_member(gate_id: str, role_prefix: str) -> tuple:
    """Build one exact gate-keyed FixtureResolvedBlobV1 bundle member."""
    blob = _TQO.build_fixture_resolved_blob(gate_id, role_prefix)
    payload = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(blob))
    return (
        f"{role_prefix}/{gate_id}",
        "typed-content",
        content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(blob)),
        payload.hex(),
    )


def _fixture_top_level_artifact_member(role: str) -> tuple:
    """Build one exact D0-10 top-level FixtureResolvedBlobV1 member."""
    blob = _TQO.build_fixture_top_level_resolved_blob(role)
    payload = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(blob))
    return (
        role,
        "typed-content",
        content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(blob)),
        payload.hex(),
    )


# ---------------------------------------------------------------------------
# Fixture gate control builders
# ---------------------------------------------------------------------------

def _legacy_candidate_wire(candidate: CandidateContext) -> dict:
    statement = {
        "commit": candidate.identity.commit,
        "treeObjectId": candidate.identity.treeObjectId,
        "archiveDigest": digest_to_wire(candidate.identity.archiveDigest),
    }
    digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00" + canonical_pf_jcs(statement)).digest()
    return {**statement, "digest": f"sha256:{digest.hex()}"}


def _signed_fixture_control(
    statement: dict, statement_domain: bytes, signature_domain: bytes,
) -> dict:
    result = dict(statement)
    result["signatures"] = _sign_subject(
        result, statement_domain, signature_domain)
    return result


def _control_record(obj: dict) -> tuple:
    encoded = canonical_pf_jcs(obj)
    ref = _TQO.recompute_typed_content_ref(obj["schema"], obj)
    return obj, encoded, ref


_FIXTURE_GATE_CONTROL_CACHE = {}


def build_fixture_gate_controls(
    candidate: CandidateContext,
    fixture_policy: _TQO.FixturePolicyV1,
    gate_id: str,
    task_id: str,
    evidence_bytes: bytes,
) -> dict:
    """Build the five real closed control types under fixture authority."""
    cache_key = (
        candidate.identity.commit, gate_id, task_id,
        hashlib.sha256(evidence_bytes).digest(),
        _TQO.fixture_policy_content_ref(fixture_policy).digest.bytes,
    )
    cached = _FIXTURE_GATE_CONTROL_CACHE.get(cache_key)
    if cached is not None:
        return cached
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    artifact_ref = lambda prefix: _TQO.fixture_resolved_blob_content_ref(
        _TQO.build_fixture_resolved_blob(gate_id, prefix))
    artifact_payload = lambda prefix: _TQO.build_fixture_resolved_blob(
        gate_id, prefix).payloadSha256
    legacy_candidate = _legacy_candidate_wire(candidate)

    authority_store_ref = artifact_ref("authority-store-service")
    host_observation_ref = artifact_ref("host-observation")
    host_profile_ref = artifact_ref("host-profile")
    handoff_obj = {
        "schema": "proof-forge.eligible-stage0-handoff.v1",
        "id": f"eligible-stage0-handoff-{gate_id}",
        "version": "1.0.0",
        "runId": f"taskqual-fixture-{gate_id}",
        "nonce": "10" * 32,
        "candidate": legacy_candidate,
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "authorityStoreService": content_ref_to_wire(authority_store_ref),
        "hostObservation": content_ref_to_wire(host_observation_ref),
        "hostProfile": content_ref_to_wire(host_profile_ref),
        "eligible": True,
        "tcb": {
            "stage0VerifierDigest": "sha256:" + "21" * 32,
            "bootstrapVerifierDigest": "sha256:" + "22" * 32,
            "continuationDigest": "sha256:" + "23" * 32,
            "formalFinalizerDigest": "sha256:" + "24" * 32,
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
                "bindingDigest": digest_to_wire(policy_ref.digest),
            },
            {
                "role": "authority-store", "fd": 4,
                "transport": "authenticated-stream", "access": "request-response",
                "bindingDigest": digest_to_wire(authority_store_ref.digest),
            },
            {
                "role": "candidate-archive", "fd": 5,
                "transport": "regular-file", "access": "read-only",
                "bindingDigest": digest_to_wire(candidate.identity.archiveDigest),
            },
            {
                "role": "evidence-root", "fd": 6,
                "transport": "regular-file", "access": "read-only",
                "bindingDigest": digest_to_wire(plain_sha256_digest(evidence_bytes)),
            },
        ],
        "pathnameReopen": False,
        "fallback": "none",
    }
    handoff_record = _control_record(handoff_obj)
    # Exercise the accepted historical handoff parser while constructing the
    # fixture so malformed legacy candidate/channel projections cannot enter.
    _BTO._preflight_eligible_stage0_handoff(handoff_record[1])

    containment_statement = {
        "schema": "proof-forge.session-containment-receipt.v1",
        "id": f"session-containment-{gate_id}",
        "version": "1.0.0",
        "candidate": legacy_candidate,
        "stage0Handoff": content_ref_to_wire(handoff_record[2]),
        "supervisorDigest": "sha256:" + "31" * 32,
        "rootSessionId": f"root-session-{gate_id}",
        "descendants": [{
            "pid": 101,
            "parentPid": 1,
            "startToken": 11,
            "sessionId": 501,
            "executableDigest": "sha256:" + "32" * 32,
            "termination": "exited",
        }],
        "escapeProbes": [{
            "id": f"escape-probe-{gate_id}", "result": "contained"}],
        "startedAt": "2026-07-20T23:59:00Z",
        "finishedAt": "2026-07-20T23:59:30Z",
        "result": "contained",
    }
    containment_obj = _signed_fixture_control(
        containment_statement,
        b"pf.session-containment-receipt-statement.v1",
        b"pf.session-containment-receipt-signature.v1")
    containment_record = _control_record(containment_obj)

    freshness_statement = {
        "schema": "proof-forge.freshness-authority-snapshot.v1",
        "id": f"freshness-{gate_id}",
        "version": "1.0.0",
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "observedAt": "2026-07-20T23:59:30Z",
        "maximumAgeSeconds": 120,
        "clockSourceDigest": "sha256:" + "41" * 32,
    }
    freshness_obj = _signed_fixture_control(
        freshness_statement,
        b"pf.freshness-authority-snapshot-statement.v1",
        b"pf.freshness-authority-snapshot-signature.v1")
    freshness_record = _control_record(freshness_obj)

    evidence_obj = _EVIDENCE.validate_evidence(
        _EVIDENCE.decode_json(evidence_bytes))
    evidence_ref = {
        "id": evidence_obj["id"],
        "digest": digest_to_wire(plain_sha256_digest(evidence_bytes)),
    }
    scanned_members = []
    for entry in evidence_obj["inputs"]:
        scanned_members.append({
            "evidence": evidence_ref,
            "role": entry["role"],
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    for entry in evidence_obj["artifacts"]:
        scanned_members.append({
            "evidence": evidence_ref,
            "role": f"artifact.{entry['target']}.{entry['role']}",
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    for entry in evidence_obj["logs"]:
        scanned_members.append({
            "evidence": evidence_ref,
            "role": "log",
            "path": entry["path"],
            "size": entry["size"],
            "digest": "sha256:" + entry["sha256"],
        })
    scanned_members.sort(key=lambda item: (
        item["evidence"]["id"], item["evidence"]["digest"][7:],
        item["path"].encode("utf-8")))
    scan_core = {
        "candidate": _TQO.candidate_identity_to_wire(candidate.identity),
        "scannedEvidenceRefs": [evidence_ref],
        "scannedMembers": scanned_members,
    }
    scan_statement = {
        "schema": "proof-forge.task-qualification-private-scan-receipt.v1",
        "id": f"task-qualification-private-scan-{gate_id}",
        "version": "1.0.0",
        "candidate": _TQO.candidate_identity_to_wire(candidate.identity),
        "evidenceCoreDigest": digest_to_wire(_TQO.domain_digest(
            b"pf.taskqual.private-scan-core.v1", scan_core)),
        "scannerDigest": digest_to_wire(
            artifact_payload("private-scan-scanner")),
        "policy": content_ref_to_wire(artifact_ref("private-scan-policy")),
        "scannedEvidenceRefs": [evidence_ref],
        "scannedMembers": scanned_members,
        "findings": [],
        "result": "clean",
    }
    scan_obj = _signed_fixture_control(
        scan_statement,
        b"pf.taskqual.private-scan-statement.v1",
        b"pf.taskqual.private-scan-signature.v1")
    scan_record = _control_record(scan_obj)

    records_digest = hashlib.sha256(
        b"pf.revocation-ledger-records.v1\x00").digest()
    revocation_statement = {
        "schema": "proof-forge.revocation-ledger-snapshot.v1",
        "id": f"revocation-ledger-{gate_id}",
        "version": "1.0.0",
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "records": [],
        "head": None,
        "recordsDigest": f"sha256:{records_digest.hex()}",
    }
    revocation_obj = _signed_fixture_control(
        revocation_statement,
        b"pf.revocation-ledger-snapshot-statement.v1",
        b"pf.revocation-ledger-snapshot-signature.v1")
    revocation_record = _control_record(revocation_obj)

    result = {
        "eligible-stage0-handoff": handoff_record,
        "session-containment": containment_record,
        "freshness": freshness_record,
        "private-scan": scan_record,
        "revocation-snapshot": revocation_record,
    }
    _FIXTURE_GATE_CONTROL_CACHE[cache_key] = result
    return result


# ---------------------------------------------------------------------------
# Fixture allowed closeout patch builder
# ---------------------------------------------------------------------------

def build_allowed_closeout_patch(
    candidate: CandidateContext,
    semantic_file_set_digest: _BTO.Digest,
    resulting_row_digest: _BTO.Digest,
) -> _TQO.AllowedCloseoutPatchV1:
    """Build a fixture AllowedCloseoutPatchV1."""
    task_suffix = FIXTURE_TASK_ID.lower().replace("task-", "")
    return _TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id=f"allowed-closeout-{task_suffix}",
        version="1.0.0",
        taskId=FIXTURE_TASK_ID,
        preCloseCandidate=candidate.identity,
        allowedPaths=(
            "docs/04-task-breakdown.md",
            "docs/05-test-spec.md",
            "docs/06-implementation-log.md",
            "docs/07-review-report.md",
            "docs/governance/task-qualifications/TASK-D1-FIXTURE/qualification.json",
        ),
        semanticFileSetDigest=semantic_file_set_digest,
        resultingTaskRowDigest=resulting_row_digest,
    )


def allowed_closeout_patch_to_wire(patch: _TQO.AllowedCloseoutPatchV1) -> dict:
    """Convert an AllowedCloseoutPatchV1 to wire format."""
    return {
        "schema": patch.schema,
        "id": patch.id,
        "version": patch.version,
        "taskId": patch.taskId,
        "preCloseCandidate": {
            "commit": patch.preCloseCandidate.commit,
            "treeObjectId": patch.preCloseCandidate.treeObjectId,
            "archiveSha256": digest_to_wire(patch.preCloseCandidate.archiveDigest),
        },
        "allowedPaths": list(patch.allowedPaths),
        "semanticFileSetDigest": digest_to_wire(patch.semanticFileSetDigest),
        "resultingTaskRowDigest": digest_to_wire(patch.resultingTaskRowDigest),
    }


def allowed_closeout_patch_content_ref(patch: _TQO.AllowedCloseoutPatchV1) -> _BTO.ContentRef:
    """Compute the ContentRef for an AllowedCloseoutPatchV1."""
    wire = allowed_closeout_patch_to_wire(patch)
    digest = domain_digest(_TQO.DOMAIN_ALLOWED_CLOSEOUT_PATCH, wire)
    return _BTO.ContentRef(schema=patch.schema, id=patch.id, version=patch.version, digest=digest)


# ---------------------------------------------------------------------------
# Fixture semantic/closeout file set builders
# ---------------------------------------------------------------------------

def build_semantic_closeout_file_set(
    candidate: CandidateContext,
    changes: list,  # list of (path, before_digest|None, after_digest|None)
) -> _TQO.SemanticCloseoutFileSetV1:
    """Build a fixture SemanticCloseoutFileSetV1."""
    task_suffix = FIXTURE_TASK_ID.lower().replace("task-", "")
    return _TQO.SemanticCloseoutFileSetV1(
        schema="proof-forge.semantic-closeout-file-set.v1",
        id=f"semantic-closeout-{task_suffix}",
        version="1.0.0",
        taskId=FIXTURE_TASK_ID,
        preCloseCandidate=candidate.identity,
        changes=tuple(changes),
    )


def semantic_closeout_file_set_to_wire(fset: _TQO.SemanticCloseoutFileSetV1) -> dict:
    """Convert a SemanticCloseoutFileSetV1 to wire format."""
    changes = []
    for path, before, after in fset.changes:
        changes.append({
            "path": path,
            "beforeDigest": digest_to_wire(before) if before else None,
            "afterDigest": digest_to_wire(after) if after else None,
        })
    return {
        "schema": fset.schema,
        "id": fset.id,
        "version": fset.version,
        "taskId": fset.taskId,
        "preCloseCandidate": {
            "commit": fset.preCloseCandidate.commit,
            "treeObjectId": fset.preCloseCandidate.treeObjectId,
            "archiveSha256": digest_to_wire(fset.preCloseCandidate.archiveDigest),
        },
        "changes": changes,
    }


def semantic_closeout_file_set_digest(fset: _TQO.SemanticCloseoutFileSetV1) -> _BTO.Digest:
    """Compute the semanticFileSetDigest."""
    wire = semantic_closeout_file_set_to_wire(fset)
    return domain_digest(_TQO.DOMAIN_SEMANTIC_CLOSEOUT_FILE_SET, wire)


def build_closeout_file_set(
    pre_candidate: CandidateContext,
    close_candidate: CandidateContext,
    changes: list,
    task_id: str = FIXTURE_TASK_ID,
) -> _TQO.CloseoutFileSetV1:
    """Build a fixture CloseoutFileSetV1."""
    task_suffix = task_id.lower().replace("task-", "")
    return _TQO.CloseoutFileSetV1(
        schema="proof-forge.closeout-file-set.v1",
        id=f"closeout-{task_suffix}",
        version="1.0.0",
        taskId=task_id,
        preCloseCandidate=pre_candidate.identity,
        closeoutCandidate=close_candidate.identity,
        changes=tuple(changes),
    )


def closeout_file_set_to_wire(fset: _TQO.CloseoutFileSetV1) -> dict:
    """Convert a CloseoutFileSetV1 to wire format."""
    changes = []
    for path, before, after in fset.changes:
        changes.append({
            "path": path,
            "beforeDigest": digest_to_wire(before) if before else None,
            "afterDigest": digest_to_wire(after) if after else None,
        })
    return {
        "schema": fset.schema,
        "id": fset.id,
        "version": fset.version,
        "taskId": fset.taskId,
        "preCloseCandidate": {
            "commit": fset.preCloseCandidate.commit,
            "treeObjectId": fset.preCloseCandidate.treeObjectId,
            "archiveSha256": digest_to_wire(fset.preCloseCandidate.archiveDigest),
        },
        "closeoutCandidate": {
            "commit": fset.closeoutCandidate.commit,
            "treeObjectId": fset.closeoutCandidate.treeObjectId,
            "archiveSha256": digest_to_wire(fset.closeoutCandidate.archiveDigest),
        },
        "changes": changes,
    }


def closeout_file_set_content_ref(fset: _TQO.CloseoutFileSetV1) -> _BTO.ContentRef:
    """Compute the ContentRef for a CloseoutFileSetV1."""
    wire = closeout_file_set_to_wire(fset)
    digest = domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, wire)
    return _BTO.ContentRef(schema=fset.schema, id=fset.id, version=fset.version, digest=digest)


def closeout_file_set_digest(fset: _TQO.CloseoutFileSetV1) -> _BTO.Digest:
    """Compute the closeoutDiffDigest."""
    wire = closeout_file_set_to_wire(fset)
    return domain_digest(_TQO.DOMAIN_CLOSEOUT_FILE_SET, wire)


# ---------------------------------------------------------------------------
# Fixture task row builder
# ---------------------------------------------------------------------------

def build_task_row(candidate: CandidateContext) -> _TQO.TaskQualificationTaskRowV1:
    """Build a fixture TaskQualificationTaskRowV1."""
    return _TQO.TaskQualificationTaskRowV1(
        taskId=FIXTURE_TASK_ID,
        output="fixture qualification verifier test",
        dependencies=(),
        prerequisites=("SPEC-TASKQUAL-001@accepted",),
        tests=(FIXTURE_TEST_ID,),
        evidenceIds=(FIXTURE_EVIDENCE_ID,),
        status="in_progress",
    )


def task_row_to_wire(row: _TQO.TaskQualificationTaskRowV1) -> dict:
    """Convert a TaskQualificationTaskRowV1 to wire format."""
    return {
        "taskId": row.taskId,
        "output": row.output,
        "dependencies": list(row.dependencies),
        "prerequisites": list(row.prerequisites),
        "tests": list(row.tests),
        "evidenceIds": list(row.evidenceIds),
        "status": row.status,
    }


def task_row_digest(row: _TQO.TaskQualificationTaskRowV1) -> _BTO.Digest:
    """Compute the resulting task row digest (plain SHA-256 of canonical bytes)."""
    wire = task_row_to_wire(row)
    return plain_sha256_digest(canonical_pf_jcs(wire))


# ---------------------------------------------------------------------------
# Fixture freeze package ref builder
# ---------------------------------------------------------------------------

def build_freeze_package_ref(freeze_bytes: bytes) -> _TQO.TaskFreezePackageRefV1:
    """Build a fixture TaskFreezePackageRefV1 from freeze package source bytes."""
    digest = _TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes)
    return _TQO.TaskFreezePackageRefV1(taskId=FIXTURE_TASK_ID, digest=digest)


def freeze_package_ref_to_wire(ref: _TQO.TaskFreezePackageRefV1) -> dict:
    return {
        "taskId": ref.taskId,
        "digest": digest_to_wire(ref.digest),
    }


# ---------------------------------------------------------------------------
# Fixture evidence ref builder
# ---------------------------------------------------------------------------

def build_evidence_ref(evidence_bytes: bytes) -> _TQO.EvidenceRefV1:
    """Build a fixture EvidenceRefV1 from evidence source bytes."""
    digest = plain_sha256_digest(evidence_bytes)
    return _TQO.EvidenceRefV1(id=FIXTURE_EVIDENCE_ID, digest=digest)


def evidence_ref_to_wire(ref: _TQO.EvidenceRefV1) -> dict:
    return {
        "id": ref.id,
        "digest": digest_to_wire(ref.digest),
    }


# ---------------------------------------------------------------------------
# Fixture review ref builder
# ---------------------------------------------------------------------------

def build_review_ref(candidate: CandidateContext, report_bytes: bytes) -> _TQO.IndependentReviewRefV1:
    """Build a fixture IndependentReviewRefV1."""
    report_digest = build_review_report_digest(report_bytes)
    return _TQO.IndependentReviewRefV1(
        reviewerId=FIXTURE_REVIEWER_ID,
        reviewerKind="independent-ai",
        invocationId=FIXTURE_REVIEW_INVOCATION_ID,
        reportDigest=report_digest,
        reviewCommit=candidate.identity.commit,
        reviewLink=FIXTURE_REVIEW_LINK,
        decision="approved",
        findings=tuple(),
    )


def review_ref_to_wire(ref: _TQO.IndependentReviewRefV1) -> dict:
    return {
        "reviewerId": ref.reviewerId,
        "reviewerKind": ref.reviewerKind,
        "invocationId": ref.invocationId,
        "reportDigest": digest_to_wire(ref.reportDigest),
        "reviewCommit": ref.reviewCommit,
        "reviewLink": ref.reviewLink,
        "decision": ref.decision,
        "findings": list(ref.findings),
    }


# ---------------------------------------------------------------------------
# Fixture gate builder
# ---------------------------------------------------------------------------

def build_gate(
    candidate: CandidateContext,
    command_policy: _TQO.TaskCommandPolicyV1,
    evidence_ref: _TQO.EvidenceRefV1,
    fixture_policy: _TQO.FixturePolicyV1,
    evidence_bytes: bytes,
) -> _TQO.TaskQualificationGateV1:
    """Build a fixture gate referencing the five real closed controls."""
    cmd_ref = command_policy_content_ref(command_policy)
    controls = build_fixture_gate_controls(
        candidate, fixture_policy, FIXTURE_GATE_ID, FIXTURE_TASK_ID,
        evidence_bytes)
    return _TQO.TaskQualificationGateV1(
        gateId=FIXTURE_GATE_ID,
        taskId=FIXTURE_TASK_ID,
        testIds=(FIXTURE_TEST_ID,),
        evidence=(evidence_ref,),
        commandPolicy=cmd_ref,
        eligibleStage0Handoff=controls["eligible-stage0-handoff"][2],
        sessionContainment=controls["session-containment"][2],
        freshness=controls["freshness"][2],
        privateScan=controls["private-scan"][2],
        revocationSnapshot=controls["revocation-snapshot"][2],
    )


def gate_to_wire(gate: _TQO.TaskQualificationGateV1) -> dict:
    return {
        "gateId": gate.gateId,
        "taskId": gate.taskId,
        "testIds": list(gate.testIds),
        "evidence": [evidence_ref_to_wire(e) for e in gate.evidence],
        "commandPolicy": content_ref_to_wire(gate.commandPolicy),
        "eligibleStage0Handoff": content_ref_to_wire(gate.eligibleStage0Handoff),
        "sessionContainment": content_ref_to_wire(gate.sessionContainment),
        "freshness": content_ref_to_wire(gate.freshness),
        "privateScan": content_ref_to_wire(gate.privateScan),
        "revocationSnapshot": content_ref_to_wire(gate.revocationSnapshot),
    }


# ---------------------------------------------------------------------------
# Fixture verifier identity builder
# ---------------------------------------------------------------------------

def build_verifier_identity(gate_id: str) -> _TQO.VerifierIdentityV1:
    """Build a fixture VerifierIdentityV1 for the qualification verifier."""
    exec_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-executable", b"fixture verifier exec")
    closure_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-closure", b"fixture verifier closure")
    build_blob = _TQO.build_fixture_resolved_blob(gate_id, "verifier-build-policy", b"fixture verifier build")
    return _TQO.VerifierIdentityV1(
        id=f"fixture-verifier-{gate_id}",
        executable=_TQO.fixture_resolved_blob_content_ref(exec_blob),
        closure=_TQO.fixture_resolved_blob_content_ref(closure_blob),
        sourceDigest=plain_sha256_digest(b"fixture verifier source"),
        buildPolicy=_TQO.fixture_resolved_blob_content_ref(build_blob),
    )


# ---------------------------------------------------------------------------
# Fixture TaskQualificationV1 builder
# ---------------------------------------------------------------------------

def build_qualification(
    candidate: CandidateContext,
    fixture_policy: _TQO.FixturePolicyV1,
    command_policy: _TQO.TaskCommandPolicyV1,
    gate: _TQO.TaskQualificationGateV1,
    evidence_ref: _TQO.EvidenceRefV1,
    freeze_ref: _TQO.TaskFreezePackageRefV1,
    review_ref: _TQO.IndependentReviewRefV1,
    patch: _TQO.AllowedCloseoutPatchV1,
    verifier: _TQO.VerifierIdentityV1,
) -> dict:
    """Build a fixture TaskQualificationV1 wire object (unsigned)."""
    task_suffix = FIXTURE_TASK_ID.lower().replace("task-", "")
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    patch_ref = allowed_closeout_patch_content_ref(patch)
    obj = {
        "schema": "proof-forge.task-qualification.v1",
        "id": f"task-qualification-{task_suffix}",
        "version": "1.0.0",
        "taskId": FIXTURE_TASK_ID,
        "preCloseCandidate": {
            "commit": candidate.identity.commit,
            "treeObjectId": candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(candidate.identity.archiveDigest),
        },
        "taskRow": task_row_to_wire(build_task_row(candidate)),
        "freezePackage": freeze_package_ref_to_wire(freeze_ref),
        "gates": [gate_to_wire(gate)],
        "dependencies": [],
        "verifier": _TQO.verifier_identity_to_wire(verifier),
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "allowedCloseoutPatch": content_ref_to_wire(patch_ref),
        "independentReviews": [review_ref_to_wire(review_ref)],
        "signatures": [],
    }
    # Sign the qualification
    sigs = _sign_subject(
        obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )
    obj["signatures"] = sigs
    return obj


def qualification_content_ref(qual_obj: dict) -> _BTO.ContentRef:
    """Compute the ContentRef for a TaskQualificationV1."""
    digest = domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, qual_obj)
    return _BTO.ContentRef(
        schema=qual_obj["schema"],
        id=qual_obj["id"],
        version=qual_obj["version"],
        digest=digest,
    )


# ---------------------------------------------------------------------------
# Fixture content bundle builder
# ---------------------------------------------------------------------------

def build_content_bundle(
    operation: str,
    fixture_policy: _TQO.FixturePolicyV1,
    candidate: CandidateContext,
    members: list,  # list of (role, kind, wire_dict, bytes_hex)
) -> dict:
    """Build a fixture TaskQualificationContentBundleV1 wire object."""
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    profile = {
        "kind": "fixture",
        "namespace": _TQO.FIXTURE_NAMESPACE,
        "fixturePolicy": content_ref_to_wire(policy_ref),
        "keySet": _TQO.FIXTURE_KEYSET,
    }
    bundle_id = _TQO.OPERATION_BUNDLE_IDS[operation]
    member_wires = []
    for role, kind, content_or_raw, bytes_hex in members:
        if kind == "typed-content":
            member_wires.append({
                "role": role,
                "kind": "typed-content",
                "content": content_or_raw,
                "bytesHex": bytes_hex,
            })
        elif kind == "raw-source":
            member_wires.append({
                "role": role,
                "kind": "raw-source",
                "raw": content_or_raw,
                "bytesHex": bytes_hex,
            })
        elif kind == "archive":
            member_wires.append({
                "role": role,
                "kind": "archive",
                "archiveSha256": content_or_raw,
                "bytesHex": bytes_hex,
            })
        elif kind == "git-object":
            member_wires.append({
                "role": role,
                "kind": "git-object",
                "objectId": content_or_raw,
                "objectType": "commit",
                "bytesHex": bytes_hex,
            })
        elif kind == "review":
            member_wires.append({
                "role": role,
                "kind": "review",
                "reviewerId": content_or_raw["reviewerId"],
                "reportDigest": content_or_raw["reportDigest"],
                "bytesHex": bytes_hex,
            })
    # Sort members by role
    member_wires.sort(key=lambda m: m["role"])
    return {
        "schema": _TQO.BUNDLE_SCHEMA,
        "id": bundle_id,
        "version": "1.0.0",
        "operation": operation,
        "verificationProfile": profile,
        "expectedAuthorityPolicy": content_ref_to_wire(policy_ref),
        "verificationInstant": FIXTURE_VERIFICATION_INSTANT,
        "implementationInvocationId": FIXTURE_IMPL_INVOCATION_ID,
        "members": member_wires,
    }


# ---------------------------------------------------------------------------
# Full fixture chain builder for task-qualification operation
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class FixtureChain:
    """A complete fixture chain for the task-qualification operation."""
    candidate: CandidateContext
    fixture_policy: _TQO.FixturePolicyV1
    command_policy: _TQO.TaskCommandPolicyV1
    gate: _TQO.TaskQualificationGateV1
    evidence_ref: _TQO.EvidenceRefV1
    freeze_ref: _TQO.TaskFreezePackageRefV1
    review_ref: _TQO.IndependentReviewRefV1
    patch: _TQO.AllowedCloseoutPatchV1
    verifier: _TQO.VerifierIdentityV1
    qualification_obj: dict
    bundle_obj: dict
    evidence_bytes: bytes
    review_report_bytes: bytes
    phase4_bytes: bytes
    phase5_bytes: bytes
    freeze_bytes: bytes


def build_fixture_chain() -> FixtureChain:
    """Build a complete legal fixture chain for task-qualification."""
    # Build fixture policy
    fixture_policy = _TQO.build_default_fixture_policy()

    # Freeze source points to a strict ancestor; C then archives the exact
    # PHASE/freeze bytes it signs and consumes.
    freeze_anchor = build_synthetic_candidate(
        FIXTURE_TASK_ID, {"fixtures/task-qualification/anchor.txt": b"anchor\n"})
    phase4_bytes = build_phase4_source(freeze_anchor)
    phase5_bytes = build_phase5_source(freeze_anchor)
    freeze_bytes = build_freeze_package_source(
        freeze_anchor, dependencies=(),
        freeze_commit=freeze_anchor.identity.commit)
    candidate = build_synthetic_candidate(
        FIXTURE_TASK_ID,
        {
            "docs/04-task-breakdown.md": b"# PHASE-4 fixture",
            "docs/05-test-spec.md": b"# PHASE-5 fixture",
            FIXTURE_PHASE4_PATH: phase4_bytes,
            FIXTURE_PHASE5_PATH: phase5_bytes,
            FIXTURE_FREEZE_PATH: freeze_bytes,
        },
        parent_sha=freeze_anchor.identity.commit,
    )
    evidence_bytes = build_evidence_source(candidate)
    review_report_bytes = build_review_report(candidate)

    # Build refs
    evidence_ref = build_evidence_ref(evidence_bytes)
    freeze_ref = build_freeze_package_ref(freeze_bytes)
    review_ref = build_review_ref(candidate, review_report_bytes)

    # Build command policy and gate
    command_policy = build_command_policy(candidate, FIXTURE_GATE_ID, fixture_policy)
    gate = build_gate(
        candidate, command_policy, evidence_ref, fixture_policy,
        evidence_bytes)

    # Build verifier identity
    verifier = build_verifier_identity(FIXTURE_GATE_ID)

    # Build semantic closeout file set.
    # Per §5/§6, the semantic file set is constructed from C's archive and the
    # planned closeout files *excluding* the fixed Q/approval path
    # (qualification.json). The before-digests come from C's archive (where a
    # path exists), the after-digests from the planned files. This must match
    # the §6 reconstruction the verifier performs in the receipt path, so the
    # planned docs/04-07 files below must be identical to the ones used to
    # build D in build_completion_receipt_chain.
    planned_semantic_files = _FIXTURE_PLANNED_SEMANTIC_FILES
    pre_path_map = candidate.archive_projection.path_map
    semantic_changes = []
    for path in sorted(planned_semantic_files.keys()):
        pre_entry = pre_path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(planned_semantic_files[path])
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue
        if before_digest is None and after_digest is None:
            continue
        semantic_changes.append((path, before_digest, after_digest))
    semantic_fset = build_semantic_closeout_file_set(candidate, semantic_changes)
    semantic_digest = semantic_closeout_file_set_digest(semantic_fset)

    # Build resulting task row digest (the row after closeout, status -> done)
    # For fixture, we use the same row but with status="done"
    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=FIXTURE_TASK_ID,
        output="fixture qualification verifier test",
        dependencies=(),
        prerequisites=("SPEC-TASKQUAL-001@accepted",),
        tests=(FIXTURE_TEST_ID,),
        evidenceIds=(FIXTURE_EVIDENCE_ID,),
        status="done",  # resulting row is done
    )
    resulting_row_digest = task_row_digest(resulting_row)

    # Build allowed closeout patch
    patch = build_allowed_closeout_patch(candidate, semantic_digest, resulting_row_digest)

    # Build qualification
    qualification_obj = build_qualification(
        candidate, fixture_policy, command_policy, gate,
        evidence_ref, freeze_ref, review_ref, patch, verifier,
    )

    # Build content bundle members
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    patch_ref = allowed_closeout_patch_content_ref(patch)
    cmd_ref = command_policy_content_ref(command_policy)

    controls = build_fixture_gate_controls(
        candidate, fixture_policy, FIXTURE_GATE_ID, FIXTURE_TASK_ID,
        evidence_bytes)

    # Build command policy member bytes
    cmd_wire = command_policy_to_wire(command_policy)
    cmd_bytes = canonical_pf_jcs(cmd_wire)

    # Build fixture policy member bytes
    policy_wire = _TQO.fixture_policy_to_wire(fixture_policy)
    policy_bytes = canonical_pf_jcs(policy_wire)

    # Build patch member bytes
    patch_wire = allowed_closeout_patch_to_wire(patch)
    patch_bytes = canonical_pf_jcs(patch_wire)

    handoff_bytes = controls["eligible-stage0-handoff"][1]
    containment_bytes = controls["session-containment"][1]
    freshness_bytes = controls["freshness"][1]
    scan_bytes = controls["private-scan"][1]
    revocation_bytes = controls["revocation-snapshot"][1]

    # Build verifier identity member bytes (for verifier-executable, verifier-closure, verifier-build-policy)
    exec_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-executable", b"fixture verifier exec")
    closure_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-closure", b"fixture verifier closure")
    build_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-build-policy", b"fixture verifier build")
    exec_wire = _TQO.fixture_resolved_blob_to_wire(exec_blob)
    exec_bytes = canonical_pf_jcs(exec_wire)
    closure_wire = _TQO.fixture_resolved_blob_to_wire(closure_blob)
    closure_bytes = canonical_pf_jcs(closure_wire)
    build_wire = _TQO.fixture_resolved_blob_to_wire(build_blob)
    build_bytes = canonical_pf_jcs(build_wire)

    # Build resolved tool/probe/sandbox members
    tool_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "resolved-tool", b"fixture tool payload")
    probe_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "resolved-probe", b"fixture probe payload")
    sandbox_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "sandbox-policy", b"fixture sandbox payload")
    tool_wire = _TQO.fixture_resolved_blob_to_wire(tool_blob)
    tool_bytes = canonical_pf_jcs(tool_wire)
    probe_wire = _TQO.fixture_resolved_blob_to_wire(probe_blob)
    probe_bytes = canonical_pf_jcs(probe_wire)
    sandbox_wire = _TQO.fixture_resolved_blob_to_wire(sandbox_blob)
    sandbox_bytes = canonical_pf_jcs(sandbox_wire)

    members = [
        ("phase-4-source", "raw-source", {"path": FIXTURE_PHASE4_PATH, "digest": digest_to_wire(plain_sha256_digest(phase4_bytes))}, phase4_bytes.hex()),
        ("phase-5-source", "raw-source", {"path": FIXTURE_PHASE5_PATH, "digest": digest_to_wire(plain_sha256_digest(phase5_bytes))}, phase5_bytes.hex()),
        ("freeze-package-source", "raw-source", {"path": FIXTURE_FREEZE_PATH, "digest": digest_to_wire(_TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes))}, freeze_bytes.hex()),
        ("candidate-archive", "archive", digest_to_wire(candidate.identity.archiveDigest), candidate.archive_bytes.hex()),
        ("candidate-commit-object", "git-object", candidate.identity.commit, candidate.commit_bytes.hex()),
        ("authority-policy", "typed-content", content_ref_to_wire(policy_ref), policy_bytes.hex()),
        ("allowed-closeout-patch", "typed-content", content_ref_to_wire(patch_ref), patch_bytes.hex()),
        (f"command-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(cmd_ref), cmd_bytes.hex()),
        (f"resolved-tool/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(tool_blob)), tool_bytes.hex()),
        (f"resolved-probe/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(probe_blob)), probe_bytes.hex()),
        (f"sandbox-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(sandbox_blob)), sandbox_bytes.hex()),
        (f"verifier-executable/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(exec_blob)), exec_bytes.hex()),
        (f"verifier-closure/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(closure_blob)), closure_bytes.hex()),
        (f"verifier-build-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(build_blob)), build_bytes.hex()),
        _fixture_artifact_member(FIXTURE_GATE_ID, "resolved-tool-closure"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "private-scan-policy"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "private-scan-scanner"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "authority-store-service"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "host-observation"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "host-profile"),
        (f"eligible-stage0-handoff/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["eligible-stage0-handoff"][2]), handoff_bytes.hex()),
        (f"session-containment/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["session-containment"][2]), containment_bytes.hex()),
        (f"freshness/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["freshness"][2]), freshness_bytes.hex()),
        (f"private-scan/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["private-scan"][2]), scan_bytes.hex()),
        ("revocation-snapshot", "typed-content", content_ref_to_wire(controls["revocation-snapshot"][2]), revocation_bytes.hex()),
        (f"evidence/{FIXTURE_EVIDENCE_ID}", "raw-source", {"path": f"evidence/{FIXTURE_EVIDENCE_ID}", "digest": digest_to_wire(evidence_ref.digest)}, evidence_bytes.hex()),
        (f"review-report/{FIXTURE_REVIEWER_ID}/{review_ref.reportDigest.bytes.hex()}", "review", {"reviewerId": FIXTURE_REVIEWER_ID, "reportDigest": digest_to_wire(review_ref.reportDigest)}, review_report_bytes.hex()),
        (f"ancestry-commit/{freeze_anchor.identity.commit}", "git-object", freeze_anchor.identity.commit, freeze_anchor.commit_bytes.hex()),
    ]

    bundle_obj = build_content_bundle("task-qualification", fixture_policy, candidate, members)

    return FixtureChain(
        candidate=candidate,
        fixture_policy=fixture_policy,
        command_policy=command_policy,
        gate=gate,
        evidence_ref=evidence_ref,
        freeze_ref=freeze_ref,
        review_ref=review_ref,
        patch=patch,
        verifier=verifier,
        qualification_obj=qualification_obj,
        bundle_obj=bundle_obj,
        evidence_bytes=evidence_bytes,
        review_report_bytes=review_report_bytes,
        phase4_bytes=phase4_bytes,
        phase5_bytes=phase5_bytes,
        freeze_bytes=freeze_bytes,
    )


def fixture_chain_to_bytes(chain: FixtureChain) -> tuple:
    """Convert a fixture chain to (bundle_bytes, subject_bytes)."""
    bundle_bytes = canonical_pf_jcs(chain.bundle_obj)
    subject_bytes = canonical_pf_jcs(chain.qualification_obj)
    return (bundle_bytes, subject_bytes)


# ---------------------------------------------------------------------------
# Variant fixture chain with a task-qualification dependency
# ---------------------------------------------------------------------------

def build_qualification_dependency(
    fixture_policy: _TQO.FixturePolicyV1,
    dep_candidate: CandidateContext,
    dep_receipt_id: str,
) -> tuple:
    """Build a fixture TaskQualificationDependencyV1 (kind=task-qualification).

    Returns (dependency_wire_obj, dependency_object_bytes,
    receipt_bytes) where:
    - receipt_bytes is the canonical PF-JCS of a synthetic TaskCompletionReceipt
      wire object (the prior task's receipt). This is what objectBytesHex
      encodes and what objectDigest digests (under DOMAIN_DEPENDENCY_OBJECT,
      raw bytes per §4).
    - dependency_object_bytes is the canonical PF-JCS of the dependency wire
      object (used as the dependency/<taskId> bundle member bytes).
    - dependency_wire_obj is the wire object embedded in the qualification's
      dependencies list.

    The verifier (P0-3 scope) only checks objectDigest against the
    dependency/<taskId> member bytes and the presence of the archive/commit
    members. It does not re-verify the dependency's internal receipt
    signatures (that is P1-4).
    """
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    # Build a minimal synthetic completion receipt wire object for the prior
    # task. Its bytes are the objectBytesHex payload.
    task_suffix = FIXTURE_DEP_TASK_ID.lower().replace("task-", "")
    receipt_obj = {
        "schema": "proof-forge.task-completion-receipt.v1",
        "id": dep_receipt_id,
        "version": "1.0.0",
        "taskId": FIXTURE_DEP_TASK_ID,
        "preCloseCandidate": {
            "commit": dep_candidate.identity.commit,
            "treeObjectId": dep_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(dep_candidate.identity.archiveDigest),
        },
        "closeoutCandidate": {
            "commit": dep_candidate.identity.commit,
            "treeObjectId": dep_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(dep_candidate.identity.archiveDigest),
        },
        "qualification": {
            "taskId": FIXTURE_DEP_TASK_ID,
            "id": f"task-qualification-{task_suffix}",
            "digest": digest_to_wire(plain_sha256_digest(b"fixture prior qual")),
        },
        "allowedCloseoutPatch": content_ref_to_wire(_BTO.ContentRef(
            schema="proof-forge.allowed-closeout-patch.v1",
            id=f"allowed-closeout-{task_suffix}",
            version="1.0.0",
            digest=plain_sha256_digest(b"fixture prior patch"),
        )),
        "closeoutDiffDigest": digest_to_wire(plain_sha256_digest(b"fixture prior diff")),
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "revocationSnapshot": content_ref_to_wire(_BTO.ContentRef(
            schema="pf.taskqual.fixture-resolved-blob.v1",
            id=f"revocation-{task_suffix}",
            version="1.0.0",
            digest=plain_sha256_digest(b"fixture prior revocation"),
        )),
        "issuedAt": FIXTURE_VERIFICATION_INSTANT,
        "signatures": [],
    }
    receipt_obj["signatures"] = _sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    receipt_bytes = canonical_pf_jcs(receipt_obj)
    receipt_digest = _TQO.domain_digest(
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT, receipt_obj)
    receipt_ref = _TQO.TaskCompletionReceiptRefV1(
        taskId=FIXTURE_DEP_TASK_ID,
        id=dep_receipt_id,
        digest=receipt_digest,
    )
    dep_obj = {
        "kind": "task-qualification",
        "taskId": FIXTURE_DEP_TASK_ID,
        "completionCommit": dep_candidate.identity.commit,
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "receipt": _TQO.completion_receipt_ref_to_wire(receipt_ref),
        "objectDigest": "",  # filled below
        "objectBytesHex": receipt_bytes.hex(),
        "signatures": receipt_obj["signatures"],
    }
    # §4: objectDigest = SHA-256(DOMAIN_DEPENDENCY_OBJECT || NUL || raw bytes)
    # where raw bytes = objectBytesHex content = receipt_bytes. The verifier
    # recomputes this from the dependency/<taskId> member's bytesHex (which
    # carries receipt_bytes) and asserts equality.
    object_digest = _TQO.domain_digest_raw(
        _TQO.DOMAIN_DEPENDENCY_OBJECT, receipt_bytes)
    dep_obj["objectDigest"] = digest_to_wire(object_digest)
    dependency_object_bytes = canonical_pf_jcs(dep_obj)
    return (dep_obj, dependency_object_bytes, receipt_bytes)


def build_fixture_chain_with_dependency() -> FixtureChain:
    """Build a legal fixture chain for task-qualification with one dependency.

    The dependency is a task-qualification dependency on FIXTURE_DEP_TASK_ID.
    The bundle carries the three-piece dependency row:
      dependency/<depTaskId>, dependency-archive/<depTaskId>,
      dependency-commit-object/<depTaskId>. The qualification's
    taskRow.dependencies and qualification.dependencies both list
    FIXTURE_DEP_TASK_ID.
    """
    fixture_policy = _TQO.build_default_fixture_policy()

    # Per §4/§8.3: the dependency's completionCommit must be a strict ancestor
    # of the consuming candidate C. So the dependency candidate is built first
    # (as a root commit), and the main candidate is built with parent_sha set
    # to the dependency candidate's commit, making dep an ancestor of C.
    dep_candidate = build_synthetic_candidate(
        FIXTURE_DEP_TASK_ID,
        {
            "docs/04-task-breakdown.md": b"# PHASE-4 prior task",
            "docs/05-test-spec.md": b"# PHASE-5 prior task",
        },
    )

    phase4_bytes = build_phase4_source(
        dep_candidate, dependencies=(FIXTURE_DEP_TASK_ID,))
    phase5_bytes = build_phase5_source(dep_candidate)
    freeze_bytes = build_freeze_package_source(
        dep_candidate, dependencies=(FIXTURE_DEP_TASK_ID,),
        freeze_commit=dep_candidate.identity.commit)
    candidate = build_synthetic_candidate(
        FIXTURE_TASK_ID,
        {
            "docs/04-task-breakdown.md": b"# PHASE-4 fixture",
            "docs/05-test-spec.md": b"# PHASE-5 fixture",
            FIXTURE_PHASE4_PATH: phase4_bytes,
            FIXTURE_PHASE5_PATH: phase5_bytes,
            FIXTURE_FREEZE_PATH: freeze_bytes,
        },
        parent_sha=dep_candidate.identity.commit,
    )

    dep_receipt_id = "task-completion-d0-09"
    dep_obj, dep_object_bytes, dep_receipt_bytes = build_qualification_dependency(
        fixture_policy, dep_candidate, dep_receipt_id,
    )
    dep_object_digest = _TQO.domain_digest_raw(
        _TQO.DOMAIN_DEPENDENCY_OBJECT, dep_receipt_bytes)

    evidence_bytes = build_evidence_source(candidate)
    review_report_bytes = build_review_report(candidate)

    evidence_ref = build_evidence_ref(evidence_bytes)
    freeze_ref = build_freeze_package_ref(freeze_bytes)
    review_ref = build_review_ref(candidate, review_report_bytes)

    command_policy = build_command_policy(candidate, FIXTURE_GATE_ID, fixture_policy)
    gate = build_gate(
        candidate, command_policy, evidence_ref, fixture_policy,
        evidence_bytes)
    verifier = build_verifier_identity(FIXTURE_GATE_ID)

    planned_semantic_files = _FIXTURE_PLANNED_SEMANTIC_FILES
    pre_path_map = candidate.archive_projection.path_map
    semantic_changes = []
    for path in sorted(planned_semantic_files.keys()):
        pre_entry = pre_path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(planned_semantic_files[path])
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue
        if before_digest is None and after_digest is None:
            continue
        semantic_changes.append((path, before_digest, after_digest))
    semantic_fset = build_semantic_closeout_file_set(candidate, semantic_changes)
    semantic_digest = semantic_closeout_file_set_digest(semantic_fset)

    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=FIXTURE_TASK_ID,
        output="fixture qualification verifier test",
        dependencies=(FIXTURE_DEP_TASK_ID,),
        prerequisites=("SPEC-TASKQUAL-001@accepted",),
        tests=(FIXTURE_TEST_ID,),
        evidenceIds=(FIXTURE_EVIDENCE_ID,),
        status="done",
    )
    resulting_row_digest = task_row_digest(resulting_row)

    patch = build_allowed_closeout_patch(candidate, semantic_digest, resulting_row_digest)

    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    patch_ref = allowed_closeout_patch_content_ref(patch)
    task_suffix = FIXTURE_TASK_ID.lower().replace("task-", "")
    # The qualification's taskRow carries the in_progress row (status must be
    # in_progress per §3). Its dependencies list the direct dependencies.
    in_progress_row = _TQO.TaskQualificationTaskRowV1(
        taskId=FIXTURE_TASK_ID,
        output="fixture qualification verifier test",
        dependencies=(FIXTURE_DEP_TASK_ID,),
        prerequisites=("SPEC-TASKQUAL-001@accepted",),
        tests=(FIXTURE_TEST_ID,),
        evidenceIds=(FIXTURE_EVIDENCE_ID,),
        status="in_progress",
    )
    qualification_obj = {
        "schema": "proof-forge.task-qualification.v1",
        "id": f"task-qualification-{task_suffix}",
        "version": "1.0.0",
        "taskId": FIXTURE_TASK_ID,
        "preCloseCandidate": {
            "commit": candidate.identity.commit,
            "treeObjectId": candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(candidate.identity.archiveDigest),
        },
        "taskRow": task_row_to_wire(in_progress_row),
        "freezePackage": freeze_package_ref_to_wire(freeze_ref),
        "gates": [gate_to_wire(gate)],
        "dependencies": [dep_obj],
        "verifier": _TQO.verifier_identity_to_wire(verifier),
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "allowedCloseoutPatch": content_ref_to_wire(patch_ref),
        "independentReviews": [review_ref_to_wire(review_ref)],
        "signatures": [],
    }
    # Sign the qualification subject.
    qualification_obj["signatures"] = _sign_subject(
        qualification_obj,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
    )

    cmd_ref = command_policy_content_ref(command_policy)
    controls = build_fixture_gate_controls(
        candidate, fixture_policy, FIXTURE_GATE_ID, FIXTURE_TASK_ID,
        evidence_bytes)

    cmd_wire = command_policy_to_wire(command_policy)
    cmd_bytes = canonical_pf_jcs(cmd_wire)
    policy_wire = _TQO.fixture_policy_to_wire(fixture_policy)
    policy_bytes = canonical_pf_jcs(policy_wire)
    patch_wire = allowed_closeout_patch_to_wire(patch)
    patch_bytes = canonical_pf_jcs(patch_wire)
    handoff_bytes = controls["eligible-stage0-handoff"][1]
    containment_bytes = controls["session-containment"][1]
    freshness_bytes = controls["freshness"][1]
    scan_bytes = controls["private-scan"][1]
    revocation_bytes = controls["revocation-snapshot"][1]

    exec_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-executable", b"fixture verifier exec")
    closure_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-closure", b"fixture verifier closure")
    build_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "verifier-build-policy", b"fixture verifier build")
    exec_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(exec_blob))
    closure_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(closure_blob))
    build_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(build_blob))

    tool_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "resolved-tool", b"fixture tool payload")
    probe_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "resolved-probe", b"fixture probe payload")
    sandbox_blob = _TQO.build_fixture_resolved_blob(FIXTURE_GATE_ID, "sandbox-policy", b"fixture sandbox payload")
    tool_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(tool_blob))
    probe_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(probe_blob))
    sandbox_bytes = canonical_pf_jcs(_TQO.fixture_resolved_blob_to_wire(sandbox_blob))

    dep_content_ref = _BTO.ContentRef(
        schema="proof-forge.task-completion-receipt.v1",
        id=dep_receipt_id,
        version="1.0.0",
        digest=_TQO.domain_digest(
            _TQO.DOMAIN_TASK_COMPLETION_RECEIPT, _BTO.decode_canonical_pf_jcs(dep_receipt_bytes)),
    )

    members = [
        ("phase-4-source", "raw-source", {"path": FIXTURE_PHASE4_PATH, "digest": digest_to_wire(plain_sha256_digest(phase4_bytes))}, phase4_bytes.hex()),
        ("phase-5-source", "raw-source", {"path": FIXTURE_PHASE5_PATH, "digest": digest_to_wire(plain_sha256_digest(phase5_bytes))}, phase5_bytes.hex()),
        ("freeze-package-source", "raw-source", {"path": FIXTURE_FREEZE_PATH, "digest": digest_to_wire(_TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes))}, freeze_bytes.hex()),
        ("candidate-archive", "archive", digest_to_wire(candidate.identity.archiveDigest), candidate.archive_bytes.hex()),
        ("candidate-commit-object", "git-object", candidate.identity.commit, candidate.commit_bytes.hex()),
        ("authority-policy", "typed-content", content_ref_to_wire(policy_ref), policy_bytes.hex()),
        ("allowed-closeout-patch", "typed-content", content_ref_to_wire(patch_ref), patch_bytes.hex()),
        (f"command-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(cmd_ref), cmd_bytes.hex()),
        (f"resolved-tool/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(tool_blob)), tool_bytes.hex()),
        (f"resolved-probe/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(probe_blob)), probe_bytes.hex()),
        (f"sandbox-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(sandbox_blob)), sandbox_bytes.hex()),
        (f"verifier-executable/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(exec_blob)), exec_bytes.hex()),
        (f"verifier-closure/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(closure_blob)), closure_bytes.hex()),
        (f"verifier-build-policy/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(build_blob)), build_bytes.hex()),
        _fixture_artifact_member(FIXTURE_GATE_ID, "resolved-tool-closure"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "private-scan-policy"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "private-scan-scanner"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "authority-store-service"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "host-observation"),
        _fixture_artifact_member(FIXTURE_GATE_ID, "host-profile"),
        (f"eligible-stage0-handoff/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["eligible-stage0-handoff"][2]), handoff_bytes.hex()),
        (f"session-containment/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["session-containment"][2]), containment_bytes.hex()),
        (f"freshness/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["freshness"][2]), freshness_bytes.hex()),
        (f"private-scan/{FIXTURE_GATE_ID}", "typed-content", content_ref_to_wire(controls["private-scan"][2]), scan_bytes.hex()),
        ("revocation-snapshot", "typed-content", content_ref_to_wire(controls["revocation-snapshot"][2]), revocation_bytes.hex()),
        (f"evidence/{FIXTURE_EVIDENCE_ID}", "raw-source", {"path": f"evidence/{FIXTURE_EVIDENCE_ID}", "digest": digest_to_wire(evidence_ref.digest)}, evidence_bytes.hex()),
        (f"review-report/{FIXTURE_REVIEWER_ID}/{review_ref.reportDigest.bytes.hex()}", "review", {"reviewerId": FIXTURE_REVIEWER_ID, "reportDigest": digest_to_wire(review_ref.reportDigest)}, review_report_bytes.hex()),
        # Three-piece dependency row. The dependency/<taskId> member carries
        # the prior task's receipt bytes (objectBytesHex); the verifier
        # recomputes objectDigest from those bytes under
        # DOMAIN_DEPENDENCY_OBJECT (raw) and asserts it equals dep.objectDigest.
        (f"dependency/{FIXTURE_DEP_TASK_ID}", "typed-content", content_ref_to_wire(dep_content_ref), dep_receipt_bytes.hex()),
        (f"dependency-archive/{FIXTURE_DEP_TASK_ID}", "archive", digest_to_wire(dep_candidate.identity.archiveDigest), dep_candidate.archive_bytes.hex()),
        (f"dependency-commit-object/{FIXTURE_DEP_TASK_ID}", "git-object", dep_candidate.identity.commit, dep_candidate.commit_bytes.hex()),
    ]

    bundle_obj = build_content_bundle("task-qualification", fixture_policy, candidate, members)

    return FixtureChain(
        candidate=candidate,
        fixture_policy=fixture_policy,
        command_policy=command_policy,
        gate=gate,
        evidence_ref=evidence_ref,
        freeze_ref=freeze_ref,
        review_ref=review_ref,
        patch=patch,
        verifier=verifier,
        qualification_obj=qualification_obj,
        bundle_obj=bundle_obj,
        evidence_bytes=evidence_bytes,
        review_report_bytes=review_report_bytes,
        phase4_bytes=phase4_bytes,
        phase5_bytes=phase5_bytes,
        freeze_bytes=freeze_bytes,
    )


def _reuse_typed_bundle_member(bundle_obj: dict, role: str) -> tuple:
    matches = [member for member in bundle_obj["members"] if member["role"] == role]
    if len(matches) != 1 or matches[0].get("kind") != "typed-content":
        raise ValueError(f"expected one typed member {role}")
    member = matches[0]
    return (
        _TQO.parse_content_ref(member["content"], f"fixture.{role}.content"),
        bytes.fromhex(member["bytesHex"]),
    )


# ---------------------------------------------------------------------------
# Task-completion-receipt fixture chain
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class CompletionReceiptChain:
    """A complete fixture chain for the task-completion operation."""
    pre_candidate: CandidateContext
    close_candidate: CandidateContext
    fixture_policy: _TQO.FixturePolicyV1
    qualification_obj: dict
    receipt_obj: dict
    bundle_obj: dict
    closeout_file_set: _TQO.CloseoutFileSetV1
    patch: _TQO.AllowedCloseoutPatchV1


def build_completion_receipt_chain(qual_chain: FixtureChain) -> CompletionReceiptChain:
    """Build a legal fixture chain for task-completion-receipt."""
    pre_candidate = qual_chain.candidate

    # Build closeout candidate D (child of C)
    # D's archive contains the closeout files (qualification.json + updated docs).
    # The docs/04-07 files must match _FIXTURE_PLANNED_SEMANTIC_FILES so the
    # §6 reconstruction the verifier performs yields patch.semanticFileSetDigest.
    closeout_files = {
        path: entry.content
        for path, entry in pre_candidate.archive_projection.path_map.items()
    }
    closeout_files.update(_FIXTURE_PLANNED_SEMANTIC_FILES)
    closeout_files[_FIXTURE_QUALIFICATION_PATH] = canonical_pf_jcs(qual_chain.qualification_obj)
    close_candidate = build_synthetic_candidate(
        FIXTURE_TASK_ID,
        closeout_files,
        parent_sha=pre_candidate.identity.commit,
        tree_prefix=None,
    )

    # Build the closeout file set (diff between C and D)
    pre_paths = set(pre_candidate.archive_projection.path_map.keys())
    close_paths = set(close_candidate.archive_projection.path_map.keys())
    all_paths = sorted(pre_paths | close_paths)

    changes = []
    for path in all_paths:
        pre_entry = pre_candidate.archive_projection.path_map.get(path)
        close_entry = close_candidate.archive_projection.path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(close_entry.content) if close_entry else None
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue  # no change
        if before_digest is None and after_digest is None:
            continue  # shouldn't happen
        changes.append((path, before_digest, after_digest))

    closeout_file_set = build_closeout_file_set(
        pre_candidate, close_candidate, changes,
    )
    closeout_diff_digest = closeout_file_set_digest(closeout_file_set)

    # Build the qualification ref
    qual_ref = _TQO.TaskQualificationRefV1(
        taskId=FIXTURE_TASK_ID,
        id=qual_chain.qualification_obj["id"],
        digest=domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, qual_chain.qualification_obj),
    )

    # Build the receipt
    task_suffix = FIXTURE_TASK_ID.lower().replace("task-", "")
    policy_ref = _TQO.fixture_policy_content_ref(qual_chain.fixture_policy)
    patch_ref = allowed_closeout_patch_content_ref(qual_chain.patch)

    # Receipt consumes the exact snapshot already verified with Q.
    revocation_ref, revocation_bytes = _reuse_typed_bundle_member(
        qual_chain.bundle_obj, "revocation-snapshot")

    receipt_obj = {
        "schema": "proof-forge.task-completion-receipt.v1",
        "id": f"task-completion-{task_suffix}",
        "version": "1.0.0",
        "taskId": FIXTURE_TASK_ID,
        "preCloseCandidate": {
            "commit": pre_candidate.identity.commit,
            "treeObjectId": pre_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(pre_candidate.identity.archiveDigest),
        },
        "closeoutCandidate": {
            "commit": close_candidate.identity.commit,
            "treeObjectId": close_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(close_candidate.identity.archiveDigest),
        },
        "qualification": {
            "taskId": qual_ref.taskId,
            "id": qual_ref.id,
            "digest": digest_to_wire(qual_ref.digest),
        },
        "allowedCloseoutPatch": content_ref_to_wire(patch_ref),
        "closeoutDiffDigest": digest_to_wire(closeout_diff_digest),
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "revocationSnapshot": content_ref_to_wire(revocation_ref),
        "issuedAt": FIXTURE_VERIFICATION_INSTANT,
        "signatures": [],
    }

    # Sign the receipt
    sigs = _sign_subject(
        receipt_obj,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
    )
    receipt_obj["signatures"] = sigs

    # Build the content bundle for task-completion
    # Members: pre-close-archive, closeout-archive, pre-close-commit-object,
    # closeout-commit-object, qualification, allowed-closeout-patch,
    # closeout-file-set, authority-policy, revocation-snapshot
    policy_wire = _TQO.fixture_policy_to_wire(qual_chain.fixture_policy)
    policy_bytes = canonical_pf_jcs(policy_wire)
    patch_wire = allowed_closeout_patch_to_wire(qual_chain.patch)
    patch_bytes = canonical_pf_jcs(patch_wire)
    closeout_file_set_wire = closeout_file_set_to_wire(closeout_file_set)
    closeout_file_set_bytes = canonical_pf_jcs(closeout_file_set_wire)
    closeout_file_set_ref = closeout_file_set_content_ref(closeout_file_set)

    members = [
        ("pre-close-archive", "archive", digest_to_wire(pre_candidate.identity.archiveDigest), pre_candidate.archive_bytes.hex()),
        ("closeout-archive", "archive", digest_to_wire(close_candidate.identity.archiveDigest), close_candidate.archive_bytes.hex()),
        ("pre-close-commit-object", "git-object", pre_candidate.identity.commit, pre_candidate.commit_bytes.hex()),
        ("closeout-commit-object", "git-object", close_candidate.identity.commit, close_candidate.commit_bytes.hex()),
        ("qualification", "typed-content", content_ref_to_wire(_BTO.ContentRef(
            schema=qual_chain.qualification_obj["schema"],
            id=qual_chain.qualification_obj["id"],
            version=qual_chain.qualification_obj["version"],
            digest=domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, qual_chain.qualification_obj),
        )), canonical_pf_jcs(qual_chain.qualification_obj).hex()),
        ("allowed-closeout-patch", "typed-content", content_ref_to_wire(patch_ref), patch_bytes.hex()),
        ("closeout-file-set", "typed-content", content_ref_to_wire(closeout_file_set_ref), closeout_file_set_bytes.hex()),
        ("authority-policy", "typed-content", content_ref_to_wire(policy_ref), policy_bytes.hex()),
        ("revocation-snapshot", "typed-content", content_ref_to_wire(revocation_ref), revocation_bytes.hex()),
    ]

    bundle_obj = build_content_bundle("task-completion", qual_chain.fixture_policy, pre_candidate, members)

    return CompletionReceiptChain(
        pre_candidate=pre_candidate,
        close_candidate=close_candidate,
        fixture_policy=qual_chain.fixture_policy,
        qualification_obj=qual_chain.qualification_obj,
        receipt_obj=receipt_obj,
        bundle_obj=bundle_obj,
        closeout_file_set=closeout_file_set,
        patch=qual_chain.patch,
    )


def completion_receipt_chain_to_bytes(chain: CompletionReceiptChain) -> tuple:
    """Convert a completion receipt chain to (bundle_bytes, subject_bytes)."""
    bundle_bytes = canonical_pf_jcs(chain.bundle_obj)
    subject_bytes = canonical_pf_jcs(chain.receipt_obj)
    return (bundle_bytes, subject_bytes)


# ---------------------------------------------------------------------------
# D0-10 bootstrap approval fixture chain
# ---------------------------------------------------------------------------

D0_10_TASK_ID = "TASK-D0-10"
D0_10_TASK_ID_LOWER = "task-d0-10"
D0_10_GATE_ID = "d0-10-bootstrap-gate"
D0_10_RULING_ID = "GOV-TASKQUAL-BOOTSTRAP-001"
D0_10_APPROVAL_ID = "d0-10-bootstrap-approval-d0-10"
D0_10_RECEIPT_ID = "d0-10-bootstrap-receipt-d0-10"
D0_10_COMMAND_POLICY_ID = "tst-doc-001.task-qualification-v1"

# Planned closeout files for the D0-10 approval fixture, excluding the fixed
# approval path (bootstrap-approval.json). The docs/04-07 after-bytes here
# must match the ones used to build D in build_d0_10_receipt_chain so the §6
# reconstruction the verifier performs yields the approval patch's
# semanticFileSetDigest.
_D0_10_PLANNED_SEMANTIC_FILES = {
    "docs/04-task-breakdown.md": b"# PHASE-4 D0-10 fixture updated",
    "docs/05-test-spec.md": b"# PHASE-5 D0-10 fixture updated",
    "docs/06-implementation-log.md": b"# D0-10 implementation log fixture",
    "docs/07-review-report.md": b"# D0-10 review report fixture",
}
_D0_10_APPROVAL_PATH = (
    "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json"
)

# D0-07 bridge constants
D0_07_TASK_ID = "TASK-D0-07"
D0_07_RULING_ID = "GOV-D0CLOSE-FIXTURE-001"
D0_07_SOURCE_PATH = "docs/governance/bootstrap-closure/TASK-D0-07.attest.json"
D0_07_RULING_BYTES = _fixture_ruling_source(
    D0_07_RULING_ID, "Fixture D0-07 historical closeout ruling.")
D0_10_RULING_BYTES = _fixture_ruling_source(
    D0_10_RULING_ID, "Fixture D0-10 task qualification bootstrap ruling.")
# §4: the d0_07Bridge sourceClosureBytesHex carries the raw bytes of the
# D0-07 GBC sourceClosure (the attest file content), so the verifier can
# recompute plain_sha256(bytes) == gc.sourceClosure.digest independently.
D0_07_SOURCE_CONTENT = b'{"fixture": "d0-07-attest"}'


@dataclass(frozen=True)
class D0_10ApprovalChain:
    """A complete fixture chain for the d0-10-bootstrap-approval operation."""
    candidate: CandidateContext
    fixture_policy: _TQO.FixturePolicyV1
    approval_obj: dict
    bundle_obj: dict
    semantic_file_set_digest: _BTO.Digest
    d0_07_completion_obj: dict
    d0_07_completion_bytes: bytes
    d0_07_archive_bytes: bytes
    d0_07_commit_bytes: bytes
    d0_07_candidate: CandidateContext


def _build_d0_07_governance_completion(
    fixture_policy: _TQO.FixturePolicyV1,
    d0_07_candidate: CandidateContext,
) -> dict:
    """Build a fixture D0-07 GovernanceBootstrapCompletionV1."""
    # The D0-07 source closure is the attest.json file
    source_content = D0_07_SOURCE_CONTENT
    source_digest = plain_sha256_digest(source_content)

    ruling_ref = _TQO.NormativeDocumentRefV1(
        id=D0_07_RULING_ID,
        status="accepted",
        contentDigest=_TQO.normative_document_digest(
            _TQO.DOMAIN_FIXTURE_NORMATIVE_DOCUMENT,
            D0_07_RULING_ID,
            D0_07_RULING_BYTES,
        ),
        reviewCommit=FIXTURE_DOCUMENT_REVIEW_COMMIT,
    )
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)

    completion_obj = {
        "schema": "proof-forge.governance-bootstrap-completion.v1",
        "id": "governance-bootstrap-completion-d0-07",
        "version": "1.0.0",
        "taskId": D0_07_TASK_ID,
        "rulingId": D0_07_RULING_ID,
        "purpose": "d0-07-historical-bootstrap-closeout",
        "completionCandidate": {
            "commit": d0_07_candidate.identity.commit,
            "treeObjectId": d0_07_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(d0_07_candidate.identity.archiveDigest),
        },
        "ruling": {
            "id": ruling_ref.id,
            "status": ruling_ref.status,
            "contentDigest": digest_to_wire(ruling_ref.contentDigest),
            "reviewCommit": ruling_ref.reviewCommit,
        },
        "sourceClosure": {
            "path": D0_07_SOURCE_PATH,
            "digest": digest_to_wire(source_digest),
        },
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "independentReviews": [],
        "signatures": [],
    }

    # Sign the completion
    sigs = _sign_subject(
        completion_obj,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
    )
    completion_obj["signatures"] = sigs
    return completion_obj


def build_d0_10_approval_chain() -> D0_10ApprovalChain:
    """Build a legal fixture chain for d0-10-bootstrap-approval."""
    fixture_policy = _TQO.build_default_fixture_policy()

    # Per §4/§8.3: the D0-07 bridge completionCommit must be a strict ancestor
    # of the consuming candidate C. So the D0-07 candidate is built first (as
    # a root commit), and the D0-10 candidate is built with parent_sha set to
    # the D0-07 candidate's commit, making D0-07 an ancestor of C.
    d0_07_candidate = build_synthetic_candidate(
        D0_07_TASK_ID,
        {
            "docs/governance/bootstrap-closure/TASK-D0-07.attest.json": b'{"fixture": "d0-07-attest"}',
        },
    )

    phase4_bytes = build_phase4_source(
        d0_07_candidate,
        dependencies=(D0_07_TASK_ID,),
        task_id=D0_10_TASK_ID,
        output=(
            "task-scoped formal qualification verifier + protected docs "
            "consumer + one-time completion bridge"),
        prerequisites=(
            "ADR-0020@accepted",
            "GOV-TASKQUAL-BOOTSTRAP-001@accepted",
            "SPEC-TASKQUAL-001@accepted",
        ),
        evidence_ids=(FIXTURE_EVIDENCE_ID,),
    )
    phase5_bytes = build_phase5_source(d0_07_candidate)
    freeze_bytes = canonical_pf_jcs({
        "schemaVersion": 1,
        "taskId": D0_10_TASK_ID,
        "frozenAt": "2026-07-20",
        "freezeCommit": d0_07_candidate.identity.commit,
        "output": "task-scoped formal qualification verifier + protected docs consumer + one-time completion bridge",
        "dependencies": [D0_07_TASK_ID],
        "prerequisites": ["ADR-0020@accepted", "GOV-TASKQUAL-BOOTSTRAP-001@accepted", "SPEC-TASKQUAL-001@accepted"],
        "tests": ["TST-DOC-001"],
        "inScope": ["fixture d0-10 approval verifier", "fixture d0-10 receipt verifier", "fixture protected adapter"],
        "outOfScope": ["production profile", "release aggregate", "formal closeout evidence"],
        "doneWhen": ["fixture passes"],
        "overflowPolicy": "fixture",
        "maxCalendarDays": 5,
        "maxCommits": 20,
        "notes": "fixture",
    })
    candidate = build_synthetic_candidate(
        D0_10_TASK_ID,
        {
            "docs/04-task-breakdown.md": b"# PHASE-4 D0-10 fixture",
            "docs/05-test-spec.md": b"# PHASE-5 D0-10 fixture",
            FIXTURE_PHASE4_PATH: phase4_bytes,
            FIXTURE_PHASE5_PATH: phase5_bytes,
            FIXTURE_FREEZE_PATH: freeze_bytes,
            FIXTURE_RULING_PATH: D0_10_RULING_BYTES,
            "fixtures/task-qualification/d0-07-ruling.md": D0_07_RULING_BYTES,
        },
        parent_sha=d0_07_candidate.identity.commit,
    )

    # Build the D0-07 governance completion
    d0_07_completion_obj = _build_d0_07_governance_completion(fixture_policy, d0_07_candidate)
    d0_07_completion_bytes = canonical_pf_jcs(d0_07_completion_obj)

    # Build the D0-07 bridge dependency
    d0_07_bridge = _TQO.GovernanceBootstrapReceiptDependencyV1(
        kind="governance-bootstrap-receipt",
        taskId=D0_07_TASK_ID,
        ruling=_TQO.NormativeDocumentRefV1(
            id=D0_07_RULING_ID,
            status="accepted",
            contentDigest=_TQO.normative_document_digest(
                _TQO.DOMAIN_FIXTURE_NORMATIVE_DOCUMENT,
                D0_07_RULING_ID,
                D0_07_RULING_BYTES,
            ),
            reviewCommit=FIXTURE_DOCUMENT_REVIEW_COMMIT,
        ),
        completionCommit=d0_07_candidate.identity.commit,
        authorityPolicy=_TQO.fixture_policy_content_ref(fixture_policy),
        objectDigest=_TQO.domain_digest_raw(
            _TQO.DOMAIN_DEPENDENCY_OBJECT, d0_07_completion_bytes
        ),
        objectBytesHex=d0_07_completion_bytes.hex(),
        sourceClosureBytesHex=D0_07_SOURCE_CONTENT.hex(),
        signatures=tuple(
            _TQO.parse_approval_signature(s, "bridge")
            for s in d0_07_completion_obj["signatures"]
        ),
    )

    # Build the D0-10 ruling ref
    ruling_ref = _TQO.NormativeDocumentRefV1(
        id=D0_10_RULING_ID,
        status="accepted",
        contentDigest=_TQO.normative_document_digest(
            _TQO.DOMAIN_FIXTURE_NORMATIVE_DOCUMENT,
            D0_10_RULING_ID,
            D0_10_RULING_BYTES,
        ),
        reviewCommit=FIXTURE_DOCUMENT_REVIEW_COMMIT,
    )

    # Build the task row for D0-10
    task_row = _TQO.TaskQualificationTaskRowV1(
        taskId=D0_10_TASK_ID,
        output="task-scoped formal qualification verifier + protected docs consumer + one-time completion bridge",
        dependencies=(D0_07_TASK_ID,),
        prerequisites=(
            "ADR-0020@accepted",
            "GOV-TASKQUAL-BOOTSTRAP-001@accepted",
            "SPEC-TASKQUAL-001@accepted",
        ),
        tests=("TST-DOC-001",),
        evidenceIds=("EV-20260721-0001",),
        status="in_progress",
    )

    # Build the freeze package ref from the exact archived bytes.
    freeze_ref = _TQO.TaskFreezePackageRefV1(
        taskId=D0_10_TASK_ID,
        digest=_TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes),
    )

    # Build the complete evidence-v1 source.
    evidence_bytes = build_evidence_source(
        candidate, D0_10_GATE_ID, D0_10_TASK_ID)
    evidence_ref = _TQO.EvidenceRefV1(
        id="EV-20260721-0001",
        digest=plain_sha256_digest(evidence_bytes),
    )

    # Build the review
    review_report_bytes = b"fixture d0-10 review report no P0/P1"
    review_ref = _TQO.IndependentReviewRefV1(
        reviewerId="fixture-reviewer-d0-10",
        reviewerKind="independent-ai",
        invocationId="task-qualification-fixture-run-d0-10-review-0001",
        reportDigest=_BTO.Digest(
            algorithm="sha256",
            bytes=hashlib.sha256(_TQO.DOMAIN_REVIEW_REPORT + b"\x00" + review_report_bytes).digest(),
        ),
        reviewCommit=candidate.identity.commit,
        reviewLink="https://fixture.example/d0-10-review",
        decision="approved",
        findings=tuple(),
    )

    # Build the command policy
    tool_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "resolved-tool", b"fixture tool")
    probe_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "resolved-probe", b"fixture probe")
    sandbox_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "sandbox-policy", b"fixture sandbox")
    verifier_exec_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "verifier-executable", b"fixture verifier exec")
    verifier_closure_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "verifier-closure", b"fixture verifier closure")
    verifier_build_blob = _TQO.build_fixture_resolved_blob(D0_10_GATE_ID, "verifier-build-policy", b"fixture verifier build")

    verifier = _TQO.VerifierIdentityV1(
        id=f"fixture-verifier-{D0_10_GATE_ID}",
        executable=_TQO.fixture_resolved_blob_content_ref(verifier_exec_blob),
        closure=_TQO.fixture_resolved_blob_content_ref(verifier_closure_blob),
        sourceDigest=plain_sha256_digest(b"fixture verifier source"),
        buildPolicy=_TQO.fixture_resolved_blob_content_ref(verifier_build_blob),
    )

    command_policy = _TQO.TaskCommandPolicyV1(
        schema="proof-forge.task-command-policy.v1",
        id=D0_10_COMMAND_POLICY_ID,
        version="1.0.0",
        taskId=D0_10_TASK_ID,
        testIds=("TST-DOC-001",),
        argv=("/usr/bin/python3", "-c", "print('fixture')"),
        environment=(
            ("HOME", "/var/empty"),
            ("LC_ALL", "C"),
            ("PATH", "/usr/bin:/bin"),
            ("TZ", "UTC"),
        ),
        tool=_TQO.fixture_resolved_blob_content_ref(tool_blob),
        probe=_TQO.fixture_resolved_blob_content_ref(probe_blob),
        sandboxPolicy=_TQO.fixture_resolved_blob_content_ref(sandbox_blob),
        verifier=verifier,
    )
    cmd_ref = command_policy_content_ref(command_policy)

    controls = build_fixture_gate_controls(
        candidate, fixture_policy, D0_10_GATE_ID, D0_10_TASK_ID,
        evidence_bytes)

    # Build the bootstrap gate
    bootstrap_gate = _TQO.D0_10BootstrapGateV1(
        gateId=D0_10_GATE_ID,
        taskId=D0_10_TASK_ID,
        testIds=("TST-DOC-001",),
        evidence=(evidence_ref,),
        commandPolicy=cmd_ref,
        eligibleStage0Handoff=controls["eligible-stage0-handoff"][2],
        sessionContainment=controls["session-containment"][2],
        freshness=controls["freshness"][2],
        privateScan=controls["private-scan"][2],
        revocationSnapshot=controls["revocation-snapshot"][2],
    )

    # D0 top-level checker/consumer identities are distinct from the gate
    # command verifier and resolve only their six singleton roles.
    bootstrap_verifier = _TQO.VerifierIdentityV1(
        id="fixture-bootstrap-verifier-d0-10",
        executable=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "bootstrap-verifier-executable")),
        closure=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "bootstrap-verifier-closure")),
        sourceDigest=plain_sha256_digest(b"fixture bootstrap verifier source"),
        buildPolicy=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "bootstrap-verifier-build-policy")),
    )
    consumer = _TQO.VerifierIdentityV1(
        id="fixture-protected-consumer-d0-10",
        executable=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "protected-consumer-executable")),
        closure=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "protected-consumer-closure")),
        sourceDigest=plain_sha256_digest(b"fixture consumer source"),
        buildPolicy=_TQO.fixture_resolved_blob_content_ref(
            _TQO.build_fixture_top_level_resolved_blob(
                "protected-consumer-build-policy")),
    )

    # Build the allowed closeout patch.
    # Per §5/§6, the semantic file set is constructed from C's archive and the
    # planned closeout files excluding the fixed approval path
    # (bootstrap-approval.json). The before-digests come from C's archive,
    # the after-digests from _D0_10_PLANNED_SEMANTIC_FILES. These must match
    # the §6 reconstruction the verifier performs in the D0-10 receipt path.
    pre_path_map = candidate.archive_projection.path_map
    d0_10_semantic_changes = []
    for path in sorted(_D0_10_PLANNED_SEMANTIC_FILES.keys()):
        pre_entry = pre_path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(_D0_10_PLANNED_SEMANTIC_FILES[path])
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue
        if before_digest is None and after_digest is None:
            continue
        d0_10_semantic_changes.append((path, before_digest, after_digest))
    semantic_fset = _TQO.SemanticCloseoutFileSetV1(
        schema="proof-forge.semantic-closeout-file-set.v1",
        id="semantic-closeout-d0-10",
        version="1.0.0",
        taskId=D0_10_TASK_ID,
        preCloseCandidate=candidate.identity,
        changes=tuple(d0_10_semantic_changes),
    )
    semantic_digest = domain_digest(_TQO.DOMAIN_SEMANTIC_CLOSEOUT_FILE_SET, semantic_closeout_file_set_to_wire(semantic_fset))

    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=D0_10_TASK_ID,
        output="task-scoped formal qualification verifier + protected docs consumer + one-time completion bridge",
        dependencies=(D0_07_TASK_ID,),
        prerequisites=("ADR-0020@accepted", "GOV-TASKQUAL-BOOTSTRAP-001@accepted", "SPEC-TASKQUAL-001@accepted"),
        tests=("TST-DOC-001",),
        evidenceIds=("EV-20260721-0001", FIXTURE_LEDGER_EVIDENCE_ID),
        status="done",
    )
    resulting_row_digest = task_row_digest(resulting_row)

    patch = _TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id="allowed-closeout-d0-10",
        version="1.0.0",
        taskId=D0_10_TASK_ID,
        preCloseCandidate=candidate.identity,
        allowedPaths=(
            "docs/04-task-breakdown.md",
            "docs/05-test-spec.md",
            "docs/06-implementation-log.md",
            "docs/07-review-report.md",
            "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json",
        ),
        semanticFileSetDigest=semantic_digest,
        resultingTaskRowDigest=resulting_row_digest,
    )
    patch_ref = allowed_closeout_patch_content_ref(patch)

    # Build the approval object
    policy_ref = _TQO.fixture_policy_content_ref(fixture_policy)
    approval_obj = {
        "schema": "proof-forge.d0-10-bootstrap-approval.v1",
        "id": D0_10_APPROVAL_ID,
        "version": "1.0.0",
        "taskId": D0_10_TASK_ID,
        "ruling": {
            "id": ruling_ref.id,
            "status": ruling_ref.status,
            "contentDigest": digest_to_wire(ruling_ref.contentDigest),
            "reviewCommit": ruling_ref.reviewCommit,
        },
        "preCloseCandidate": {
            "commit": candidate.identity.commit,
            "treeObjectId": candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(candidate.identity.archiveDigest),
        },
        "taskRow": task_row_to_wire(task_row),
        "freezePackage": freeze_package_ref_to_wire(freeze_ref),
        "verifier": _TQO.verifier_identity_to_wire(bootstrap_verifier),
        "protectedConsumer": _TQO.verifier_identity_to_wire(consumer),
        "verifierClosureDigest": digest_to_wire(_TQO.domain_digest(
            _TQO.DOMAIN_D0_10_VERIFIER_CLOSURE,
            _TQO.verifier_identity_to_wire(bootstrap_verifier))),
        "consumerClosureDigest": digest_to_wire(_TQO.domain_digest(
            _TQO.DOMAIN_D0_10_CONSUMER_CLOSURE,
            _TQO.verifier_identity_to_wire(consumer))),
        "ledgerEvidenceId": FIXTURE_LEDGER_EVIDENCE_ID,
        "tstDocSubprofile": FIXTURE_SUBPROFILE,
        "bootstrapGate": {
            "gateId": bootstrap_gate.gateId,
            "taskId": bootstrap_gate.taskId,
            "testIds": list(bootstrap_gate.testIds),
            "evidence": [evidence_ref_to_wire(e) for e in bootstrap_gate.evidence],
            "commandPolicy": content_ref_to_wire(bootstrap_gate.commandPolicy),
            "eligibleStage0Handoff": content_ref_to_wire(bootstrap_gate.eligibleStage0Handoff),
            "sessionContainment": content_ref_to_wire(bootstrap_gate.sessionContainment),
            "freshness": content_ref_to_wire(bootstrap_gate.freshness),
            "privateScan": content_ref_to_wire(bootstrap_gate.privateScan),
            "revocationSnapshot": content_ref_to_wire(bootstrap_gate.revocationSnapshot),
        },
        "d0_07Bridge": {
            "kind": "governance-bootstrap-receipt",
            "taskId": d0_07_bridge.taskId,
            "ruling": _TQO.normative_document_ref_to_wire(
                d0_07_bridge.ruling),
            "completionCommit": d0_07_bridge.completionCommit,
            "authorityPolicy": content_ref_to_wire(d0_07_bridge.authorityPolicy),
            "objectDigest": digest_to_wire(d0_07_bridge.objectDigest),
            "objectBytesHex": d0_07_bridge.objectBytesHex,
            "sourceClosureBytesHex": d0_07_bridge.sourceClosureBytesHex,
            "signatures": [_TQO.approval_signature_to_wire(s) for s in d0_07_bridge.signatures],
        },
        "allowedCloseoutPatch": content_ref_to_wire(patch_ref),
        "independentReviews": [review_ref_to_wire(review_ref)],
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "signatures": [],
    }

    # Sign the approval
    sigs = _sign_subject(
        approval_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL_SIGNATURE,
    )
    approval_obj["signatures"] = sigs

    # Build the content bundle members from the archived source bytes.
    ruling_bytes = D0_10_RULING_BYTES

    policy_wire = _TQO.fixture_policy_to_wire(fixture_policy)
    policy_bytes = canonical_pf_jcs(policy_wire)
    patch_wire = allowed_closeout_patch_to_wire(patch)
    patch_bytes = canonical_pf_jcs(patch_wire)
    cmd_wire = command_policy_to_wire(command_policy)
    cmd_bytes = canonical_pf_jcs(cmd_wire)

    # Gate control member bytes
    handoff_bytes = controls["eligible-stage0-handoff"][1]
    containment_bytes = controls["session-containment"][1]
    freshness_bytes = controls["freshness"][1]
    scan_bytes = controls["private-scan"][1]
    revocation_bytes = controls["revocation-snapshot"][1]

    # Verifier/consumer member bytes
    exec_wire = _TQO.fixture_resolved_blob_to_wire(verifier_exec_blob)
    exec_bytes = canonical_pf_jcs(exec_wire)
    closure_wire = _TQO.fixture_resolved_blob_to_wire(verifier_closure_blob)
    closure_bytes = canonical_pf_jcs(closure_wire)
    build_wire = _TQO.fixture_resolved_blob_to_wire(verifier_build_blob)
    build_bytes = canonical_pf_jcs(build_wire)

    # Resolved tool/probe/sandbox
    tool_wire = _TQO.fixture_resolved_blob_to_wire(tool_blob)
    tool_bytes = canonical_pf_jcs(tool_wire)
    probe_wire = _TQO.fixture_resolved_blob_to_wire(probe_blob)
    probe_bytes = canonical_pf_jcs(probe_wire)
    sandbox_wire = _TQO.fixture_resolved_blob_to_wire(sandbox_blob)
    sandbox_bytes = canonical_pf_jcs(sandbox_wire)

    members = [
        ("phase-4-source", "raw-source", {"path": "fixtures/task-qualification/04-task-breakdown.md", "digest": digest_to_wire(plain_sha256_digest(phase4_bytes))}, phase4_bytes.hex()),
        ("phase-5-source", "raw-source", {"path": "fixtures/task-qualification/05-test-spec.md", "digest": digest_to_wire(plain_sha256_digest(phase5_bytes))}, phase5_bytes.hex()),
        ("ruling-source", "raw-source", {"path": "fixtures/task-qualification/ruling.md", "digest": digest_to_wire(plain_sha256_digest(ruling_bytes))}, ruling_bytes.hex()),
        ("d0-07-ruling-source", "raw-source", {"path": "fixtures/task-qualification/d0-07-ruling.md", "digest": digest_to_wire(plain_sha256_digest(D0_07_RULING_BYTES))}, D0_07_RULING_BYTES.hex()),
        ("freeze-package-source", "raw-source", {"path": "fixtures/task-qualification/freeze.json", "digest": digest_to_wire(_TQO.domain_digest_raw(_TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes))}, freeze_bytes.hex()),
        ("candidate-archive", "archive", digest_to_wire(candidate.identity.archiveDigest), candidate.archive_bytes.hex()),
        ("candidate-commit-object", "git-object", candidate.identity.commit, candidate.commit_bytes.hex()),
        ("authority-policy", "typed-content", content_ref_to_wire(policy_ref), policy_bytes.hex()),
        ("allowed-closeout-patch", "typed-content", content_ref_to_wire(patch_ref), patch_bytes.hex()),
        (f"command-policy/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(cmd_ref), cmd_bytes.hex()),
        (f"resolved-tool/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(tool_blob)), tool_bytes.hex()),
        (f"resolved-probe/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(probe_blob)), probe_bytes.hex()),
        (f"sandbox-policy/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(sandbox_blob)), sandbox_bytes.hex()),
        (f"verifier-executable/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(verifier_exec_blob)), exec_bytes.hex()),
        (f"verifier-closure/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(verifier_closure_blob)), closure_bytes.hex()),
        (f"verifier-build-policy/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(_TQO.fixture_resolved_blob_content_ref(verifier_build_blob)), build_bytes.hex()),
        _fixture_artifact_member(D0_10_GATE_ID, "resolved-tool-closure"),
        _fixture_artifact_member(D0_10_GATE_ID, "private-scan-policy"),
        _fixture_artifact_member(D0_10_GATE_ID, "private-scan-scanner"),
        _fixture_artifact_member(D0_10_GATE_ID, "authority-store-service"),
        _fixture_artifact_member(D0_10_GATE_ID, "host-observation"),
        _fixture_artifact_member(D0_10_GATE_ID, "host-profile"),
        _fixture_top_level_artifact_member("bootstrap-verifier-executable"),
        _fixture_top_level_artifact_member("bootstrap-verifier-closure"),
        _fixture_top_level_artifact_member("bootstrap-verifier-build-policy"),
        _fixture_top_level_artifact_member("protected-consumer-executable"),
        _fixture_top_level_artifact_member("protected-consumer-closure"),
        _fixture_top_level_artifact_member("protected-consumer-build-policy"),
        (f"eligible-stage0-handoff/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(controls["eligible-stage0-handoff"][2]), handoff_bytes.hex()),
        (f"session-containment/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(controls["session-containment"][2]), containment_bytes.hex()),
        (f"freshness/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(controls["freshness"][2]), freshness_bytes.hex()),
        (f"private-scan/{D0_10_GATE_ID}", "typed-content", content_ref_to_wire(controls["private-scan"][2]), scan_bytes.hex()),
        ("revocation-snapshot", "typed-content", content_ref_to_wire(controls["revocation-snapshot"][2]), revocation_bytes.hex()),
        ("d0-07-governance-completion", "typed-content", content_ref_to_wire(_BTO.ContentRef(
            schema=d0_07_completion_obj["schema"],
            id=d0_07_completion_obj["id"],
            version=d0_07_completion_obj["version"],
            digest=domain_digest(_TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION, d0_07_completion_obj),
        )), d0_07_completion_bytes.hex()),
        ("d0-07-completion-archive", "archive", digest_to_wire(d0_07_candidate.identity.archiveDigest), d0_07_candidate.archive_bytes.hex()),
        ("d0-07-completion-commit-object", "git-object", d0_07_candidate.identity.commit, d0_07_candidate.commit_bytes.hex()),
        (f"evidence/EV-20260721-0001", "raw-source", {"path": "evidence/EV-20260721-0001", "digest": digest_to_wire(evidence_ref.digest)}, evidence_bytes.hex()),
        (f"review-report/{review_ref.reviewerId}/{review_ref.reportDigest.bytes.hex()}", "review", {"reviewerId": review_ref.reviewerId, "reportDigest": digest_to_wire(review_ref.reportDigest)}, review_report_bytes.hex()),
    ]

    bundle_obj = build_content_bundle("d0-10-bootstrap-approval", fixture_policy, candidate, members)

    return D0_10ApprovalChain(
        candidate=candidate,
        fixture_policy=fixture_policy,
        approval_obj=approval_obj,
        bundle_obj=bundle_obj,
        semantic_file_set_digest=semantic_digest,
        d0_07_completion_obj=d0_07_completion_obj,
        d0_07_completion_bytes=d0_07_completion_bytes,
        d0_07_archive_bytes=d0_07_candidate.archive_bytes,
        d0_07_commit_bytes=d0_07_candidate.commit_bytes,
        d0_07_candidate=d0_07_candidate,
    )


def d0_10_approval_chain_to_bytes(chain: D0_10ApprovalChain) -> tuple:
    """Convert a D0-10 approval chain to (bundle_bytes, subject_bytes)."""
    bundle_bytes = canonical_pf_jcs(chain.bundle_obj)
    subject_bytes = canonical_pf_jcs(chain.approval_obj)
    return (bundle_bytes, subject_bytes)


# ---------------------------------------------------------------------------
# D0-10 bootstrap receipt fixture chain
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class D0_10ReceiptChain:
    """A complete fixture chain for the d0-10-bootstrap-receipt operation."""
    pre_candidate: CandidateContext
    close_candidate: CandidateContext
    fixture_policy: _TQO.FixturePolicyV1
    approval_obj: dict
    receipt_obj: dict
    bundle_obj: dict
    closeout_file_set: _TQO.CloseoutFileSetV1


def build_d0_10_receipt_chain(approval_chain: D0_10ApprovalChain) -> D0_10ReceiptChain:
    """Build a legal fixture chain for d0-10-bootstrap-receipt."""
    pre_candidate = approval_chain.candidate

    # Build closeout candidate D (child of C).
    # The docs/04-07 files must match _D0_10_PLANNED_SEMANTIC_FILES so the
    # §6 reconstruction the verifier performs yields the approval patch's
    # semanticFileSetDigest. The fixed approval path carries the signed
    # approval object bytes.
    closeout_files = {
        path: entry.content
        for path, entry in pre_candidate.archive_projection.path_map.items()
    }
    closeout_files.update(_D0_10_PLANNED_SEMANTIC_FILES)
    closeout_files[_D0_10_APPROVAL_PATH] = canonical_pf_jcs(approval_chain.approval_obj)
    close_candidate = build_synthetic_candidate(
        D0_10_TASK_ID,
        closeout_files,
        parent_sha=pre_candidate.identity.commit,
        tree_prefix=None,
    )

    # Build the closeout file set
    pre_paths = set(pre_candidate.archive_projection.path_map.keys())
    close_paths = set(close_candidate.archive_projection.path_map.keys())
    all_paths = sorted(pre_paths | close_paths)

    changes = []
    for path in all_paths:
        pre_entry = pre_candidate.archive_projection.path_map.get(path)
        close_entry = close_candidate.archive_projection.path_map.get(path)
        before_digest = plain_sha256_digest(pre_entry.content) if pre_entry else None
        after_digest = plain_sha256_digest(close_entry.content) if close_entry else None
        if before_digest and after_digest and before_digest.bytes == after_digest.bytes:
            continue
        if before_digest is None and after_digest is None:
            continue
        changes.append((path, before_digest, after_digest))

    closeout_file_set = build_closeout_file_set(
        pre_candidate, close_candidate, changes, task_id=D0_10_TASK_ID,
    )
    closeout_diff_digest = closeout_file_set_digest(closeout_file_set)

    # Build the approval digest
    approval_digest = domain_digest(_TQO.DOMAIN_D0_10_BOOTSTRAP_APPROVAL, approval_chain.approval_obj)

    # Build the ruling ref
    ruling_ref = _TQO.NormativeDocumentRefV1(
        id=D0_10_RULING_ID,
        status="accepted",
        contentDigest=_TQO.normative_document_digest(
            _TQO.DOMAIN_FIXTURE_NORMATIVE_DOCUMENT,
            D0_10_RULING_ID,
            D0_10_RULING_BYTES,
        ),
        reviewCommit=FIXTURE_DOCUMENT_REVIEW_COMMIT,
    )

    policy_ref = _TQO.fixture_policy_content_ref(approval_chain.fixture_policy)
    # The receipt's allowed-closeout-patch must carry the same
    # semanticFileSetDigest as the approval patch so the §6 reconstruction
    # the verifier performs on the receipt's closeout file set yields this
    # digest. The allowedPaths list only the fixed approval path here; the
    # semantic reconstruction removes that path from the full file set.
    d0_10_semantic_digest = approval_chain.semantic_file_set_digest
    # GAP-13: compute the resultingTaskRowDigest from the approval's taskRow
    # (status flipped to done). The verifier recomputes this and asserts
    # equality to the patch's resultingTaskRowDigest.
    approval_task_row_wire = approval_chain.approval_obj["taskRow"]
    resulting_row = _TQO.TaskQualificationTaskRowV1(
        taskId=approval_task_row_wire["taskId"],
        output=approval_task_row_wire["output"],
        dependencies=tuple(approval_task_row_wire["dependencies"]),
        prerequisites=tuple(approval_task_row_wire["prerequisites"]),
        tests=tuple(approval_task_row_wire["tests"]),
        evidenceIds=tuple(approval_task_row_wire["evidenceIds"])
        + (approval_chain.approval_obj["ledgerEvidenceId"],),
        status="done",
    )
    d0_10_resulting_row_digest = task_row_digest(resulting_row)
    # GAP-13: the receipt's allowedCloseoutPatch.allowedPaths must exact-equal
    # the closeout diff paths (§6). The closeout file set has 5 paths (docs/04-07
    # + the fixed approval path), so allowedPaths lists all 5.
    d0_10_allowed_paths = (
        "docs/04-task-breakdown.md",
        "docs/05-test-spec.md",
        "docs/06-implementation-log.md",
        "docs/07-review-report.md",
        "docs/governance/task-qualifications/TASK-D0-10/bootstrap-approval.json",
    )
    patch_ref = allowed_closeout_patch_content_ref(_TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id="allowed-closeout-d0-10",
        version="1.0.0",
        taskId=D0_10_TASK_ID,
        preCloseCandidate=pre_candidate.identity,
        allowedPaths=d0_10_allowed_paths,
        semanticFileSetDigest=d0_10_semantic_digest,
        resultingTaskRowDigest=d0_10_resulting_row_digest,
    ))

    # Receipt consumes the exact snapshot already verified with approval.
    revocation_ref, revocation_bytes = _reuse_typed_bundle_member(
        approval_chain.bundle_obj, "revocation-snapshot")

    receipt_obj = {
        "schema": "proof-forge.d0-10-bootstrap-receipt.v1",
        "id": D0_10_RECEIPT_ID,
        "version": "1.0.0",
        "taskId": D0_10_TASK_ID,
        "ruling": {
            "id": ruling_ref.id,
            "status": ruling_ref.status,
            "contentDigest": digest_to_wire(ruling_ref.contentDigest),
            "reviewCommit": ruling_ref.reviewCommit,
        },
        "preCloseCandidate": {
            "commit": pre_candidate.identity.commit,
            "treeObjectId": pre_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(pre_candidate.identity.archiveDigest),
        },
        "closeoutCandidate": {
            "commit": close_candidate.identity.commit,
            "treeObjectId": close_candidate.identity.treeObjectId,
            "archiveSha256": digest_to_wire(close_candidate.identity.archiveDigest),
        },
        "approvalDigest": digest_to_wire(approval_digest),
        "allowedCloseoutPatch": content_ref_to_wire(patch_ref),
        "closeoutDiffDigest": digest_to_wire(closeout_diff_digest),
        "ledgerEvidenceId": FIXTURE_LEDGER_EVIDENCE_ID,
        "authorityPolicy": content_ref_to_wire(policy_ref),
        "revocationSnapshot": content_ref_to_wire(revocation_ref),
        "ledgerGrade": "bootstrap",
        "purpose": "d0-10-taskqual-one-time-bridge",
        "issuedAt": FIXTURE_VERIFICATION_INSTANT,
        "signatures": [],
    }

    # Sign the receipt
    sigs = _sign_subject(
        receipt_obj,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_STATEMENT,
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT_SIGNATURE,
    )
    receipt_obj["signatures"] = sigs

    # Build the content bundle for d0-10-bootstrap-receipt
    policy_wire = _TQO.fixture_policy_to_wire(approval_chain.fixture_policy)
    policy_bytes = canonical_pf_jcs(policy_wire)
    patch_wire = allowed_closeout_patch_to_wire(_TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id="allowed-closeout-d0-10",
        version="1.0.0",
        taskId=D0_10_TASK_ID,
        preCloseCandidate=pre_candidate.identity,
        allowedPaths=d0_10_allowed_paths,
        semanticFileSetDigest=d0_10_semantic_digest,
        resultingTaskRowDigest=d0_10_resulting_row_digest,
    ))
    patch_bytes = canonical_pf_jcs(patch_wire)
    closeout_file_set_wire = closeout_file_set_to_wire(closeout_file_set)
    closeout_file_set_bytes = canonical_pf_jcs(closeout_file_set_wire)
    approval_bytes = canonical_pf_jcs(approval_chain.approval_obj)

    closeout_file_set_ref = closeout_file_set_content_ref(closeout_file_set)

    members = [
        ("pre-close-archive", "archive", digest_to_wire(pre_candidate.identity.archiveDigest), pre_candidate.archive_bytes.hex()),
        ("closeout-archive", "archive", digest_to_wire(close_candidate.identity.archiveDigest), close_candidate.archive_bytes.hex()),
        ("pre-close-commit-object", "git-object", pre_candidate.identity.commit, pre_candidate.commit_bytes.hex()),
        ("closeout-commit-object", "git-object", close_candidate.identity.commit, close_candidate.commit_bytes.hex()),
        ("bootstrap-approval", "typed-content", content_ref_to_wire(_BTO.ContentRef(
            schema=approval_chain.approval_obj["schema"],
            id=approval_chain.approval_obj["id"],
            version=approval_chain.approval_obj["version"],
            digest=approval_digest,
        )), approval_bytes.hex()),
        ("allowed-closeout-patch", "typed-content", content_ref_to_wire(patch_ref), patch_bytes.hex()),
        ("closeout-file-set", "typed-content", content_ref_to_wire(closeout_file_set_ref), closeout_file_set_bytes.hex()),
        ("authority-policy", "typed-content", content_ref_to_wire(policy_ref), policy_bytes.hex()),
        ("revocation-snapshot", "typed-content", content_ref_to_wire(revocation_ref), revocation_bytes.hex()),
    ]

    bundle_obj = build_content_bundle("d0-10-bootstrap-receipt", approval_chain.fixture_policy, pre_candidate, members)

    return D0_10ReceiptChain(
        pre_candidate=pre_candidate,
        close_candidate=close_candidate,
        fixture_policy=approval_chain.fixture_policy,
        approval_obj=approval_chain.approval_obj,
        receipt_obj=receipt_obj,
        bundle_obj=bundle_obj,
        closeout_file_set=closeout_file_set,
    )


def d0_10_receipt_chain_to_bytes(chain: D0_10ReceiptChain) -> tuple:
    """Convert a D0-10 receipt chain to (bundle_bytes, subject_bytes)."""
    bundle_bytes = canonical_pf_jcs(chain.bundle_obj)
    subject_bytes = canonical_pf_jcs(chain.receipt_obj)
    return (bundle_bytes, subject_bytes)