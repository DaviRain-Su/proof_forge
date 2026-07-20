#!/usr/bin/env python3
"""TST-ISO-002 fixture clean-room harness (TASK-D0-07 slice S7).

Runs the formal clean-room stage semantics in the ADR-0018 fixture
namespace: the authoritative Stage-0 (env -i verify_host_stage0.sh
--require-eligible), an external commit/tree/archive anchor over the
product tree, empty-env/cache deny-all bwrap stages via
``scripts/sandbox_bwrap.py`` (materialize: external tools from the locked
asset cache; core: a real structural re-audit payload over the extracted
candidate; evm-runtime: a real Anvil Counter differential under a
loopback-only net namespace), a signed SessionContainmentReceiptV1 from a
supervised invocation, and one fixture formal ``proof-forge.evidence.v1``
record binding candidate/host/stages/receipts/containment plus a small
fixture catalog (three gates partitioning a fixture required set).  Every
failure closes with a ``PF-CLEAN-ROOM-*`` family and zero published
evidence.  Fixture keys only (public RFC 8032 test vectors); nothing here
is formal or hermetic evidence.
"""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Mapping, NoReturn, Optional, Sequence, Tuple


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
_PRODUCERS = _load_module(
    _MODULE_PATH.with_name("bootstrap_task_producers.py"),
    "proof_forge_bootstrap_task_producers_for_clean_room",
)
_ACCEPTANCE = _load_module(
    _MODULE_PATH.with_name("bootstrap_acceptance.py"),
    "proof_forge_bootstrap_acceptance_for_clean_room",
)
_FORMAL = _load_module(
    _MODULE_PATH.with_name("formal_evidence.py"),
    "proof_forge_formal_evidence_for_clean_room",
)
_FORMAL_INPUTS = _load_module(
    _MODULE_PATH.with_name("formal_input_producers.py"),
    "proof_forge_formal_input_producers_for_clean_room",
)
_BWRAP = _load_module(
    _MODULE_PATH.with_name("sandbox_bwrap.py"),
    "proof_forge_sandbox_bwrap_for_clean_room",
)
_EV_CORE = _load_module(
    _MODULE_PATH.with_name("evidence_v1_core.py"),
    "proof_forge_evidence_v1_core_for_clean_room",
)
_CONSUMER = _PRODUCERS._CONSUMER

BWRAP_PATH = "/usr/bin/bwrap"
PYTHON_PATH = os.path.realpath("/usr/bin/python3")
PRODUCT_TREE_PATHS = (
    "ProofForgeV2",
    "ProofForgeV2.lean",
    "Examples",
    "Examples.lean",
    "lakefile.lean",
    "lake-manifest.json",
    "lean-toolchain",
    "Tests",
    "testdata",
)
TOOL_IDS = ("anvil", "cast", "jv", "solc", "wat2wasm")
LOCK_RELATIVE = "toolchains-linux-x86_64.lock.json"
DEFAULT_ASSET_CACHE = os.path.expanduser("~/.cache/proof-forge-v2/assets")
FIXTURE_POLICY_ID = "s7-clean-room-authority"
FIXTURE_NAMESPACE_ID = "s7-clean-room-namespace"
FIXTURE_CATALOG_ID = "s7-clean-room-catalog"
FIXTURE_REQUIRED_SET_ID = "s7-clean-room-required-tests"
FIXTURE_TEST_IDS = ("TST-DOC-001", "TST-ISO-001", "TST-ISO-002")
EVM_PRIVATE_KEY = (
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
)
EVM_CHAIN_ID = 31337
COUNTER_SOL = """// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Counter {
    uint64 private count;

    constructor(uint64 initial) {
        count = initial;
    }

    function increment(uint64 delta) external {
        uint64 updated = count + delta;
        require(updated >= count, "overflow");
        count = updated;
    }

    function get() external view returns (uint64) {
        return count;
    }
}
"""
_NETWORK_DENIAL_ERRNOS = frozenset({13, 1, 101, 99})


class CleanRoomError(Exception):
    """Stable clean-room failure; details never grant authority."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise CleanRoomError(code, detail)


def _stage0(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-STAGE0", detail)


def _anchor(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-ANCHOR", detail)


def _stage(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-STAGE", detail)


def _containment(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-CONTAINMENT", detail)


def _evidence(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-EVIDENCE", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-CLEAN-ROOM-IO", detail)


@dataclass(frozen=True)
class CleanRoomReport:
    eligibleForHermetic: bool
    hostProfileId: str
    candidateCommit: str
    candidateTreeObjectId: str
    archiveSha256: str
    evidencePath: str
    containmentPath: str
    policyPath: str
    requiredSetPath: str
    catalogPath: str
    catalogApprovalPath: str
    containmentDescendants: tuple
    stageReceiptPaths: tuple
    durationMs: int


def network_denied_errno(errno_value: int) -> bool:
    """True when an errno is an isolation-layer network denial."""
    return errno_value in _NETWORK_DENIAL_ERRNOS


def git_commit(repo_root: str) -> str:
    result = subprocess.run(
        ["git", "-C", repo_root, "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def require_eligible_observation(observation_bytes: bytes) -> dict:
    """Parse the authoritative Stage-0 observation and require eligibility."""
    try:
        parsed = json.loads(observation_bytes.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _stage0("host observation is not a bounded JSON document")
    if type(parsed) is not dict or parsed.get("eligibleForHermetic") is not True:
        _stage0("host observation does not prove an eligible host")
    return parsed


def _run_authoritative_stage0(repo_root: str) -> Tuple[dict, bytes]:
    argv = (
        "/usr/bin/env", "-i", "HOME=/var/empty", "PATH=/usr/bin:/bin",
        "LC_ALL=C", "TZ=UTC", "/bin/bash", "--noprofile", "--norc",
        "scripts/verify_host_stage0.sh", "--require-eligible",
    )
    try:
        result = subprocess.run(
            argv, cwd=repo_root, capture_output=True, timeout=360,
        )
    except (OSError, subprocess.TimeoutExpired):
        _stage0("authoritative Stage-0 invocation failed")
    if result.returncode != 0:
        _stage0("authoritative Stage-0 did not prove an eligible host")
    return require_eligible_observation(result.stdout), result.stdout


def _status_hash(repo_root: str) -> str:
    result = subprocess.run(
        ["git", "-C", repo_root, "status", "--porcelain=v1", "--untracked-files=all",
         "--", ".", ":(exclude)active"],
        check=True,
        capture_output=True,
    )
    return hashlib.sha256(result.stdout).hexdigest()


def _candidate_anchor(repo_root: str, work: Path,
                      expected_commit: Optional[str],
                      expected_archive_sha256: Optional[str]) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    commit = git_commit(repo_root)
    if expected_commit is not None and commit != expected_commit:
        _anchor("stale anchor commit mismatch")
    tree = subprocess.run(
        ["git", "-C", repo_root, "rev-parse", "HEAD^{tree}"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    archive = work / "candidate.tar"
    subprocess.run(
        ["git", "-C", repo_root, "archive", "HEAD", *PRODUCT_TREE_PATHS,
         "-o", str(archive)],
        check=True,
    )
    archive_bytes = archive.read_bytes()
    archive_sha256 = hashlib.sha256(archive_bytes).hexdigest()
    if expected_archive_sha256 is not None and (
        archive_sha256 != expected_archive_sha256
    ):
        _anchor("candidate archive digest mismatch")
    statement = {
        "commit": commit,
        "treeObjectId": tree,
        "archiveDigest": "sha256:" + archive_sha256,
    }
    identity_digest = hashlib.sha256(
        b"pf.candidate-identity.v1\x00"
        + _CONSUMER.canonical_pf_jcs(statement)
    ).hexdigest()
    source = work / "source"
    source.mkdir()
    with tarfile.open(archive) as handle:
        for member in handle.getmembers():
            if member.issym() or member.islnk():
                _anchor("candidate archive contains a link entry")
            if member.name.startswith("/") or ".." in member.name.split("/"):
                _anchor("candidate archive contains an unsafe path")
        handle.extractall(source)
    if (source / ".git").exists() or (source / "active").exists():
        _anchor("extracted candidate leaked metadata or the legacy tree")
    return {
        "commit": commit,
        "treeObjectId": tree,
        "archiveDigest": "sha256:" + archive_sha256,
        "digest": "sha256:" + identity_digest,
    }, archive_bytes, source


def _fixture_policy_bytes(seeds_by_key_id: Mapping[str, bytes]) -> Tuple[bytes, object]:
    producer = _PRODUCERS
    consumer = _CONSUMER
    def public_key(role: str) -> bytes:
        return producer.ed25519_public_key_from_seed(seeds_by_key_id[f"key-{role}"])
    principals = tuple(
        consumer.BootstrapAuthorityPrincipalV1(
            f"principal-{role}", f"key-{role}", public_key(role), (role,)
        )
        for role in ("architecture", "quality", "release", "security")
    )
    descriptor_wire = {
        "schema": "proof-forge.authority-store-service.v1",
        "id": "authority-store",
        "version": "1.0.0",
        "protocol": "pf.authority-store.rpc.v1",
        "serviceExecutableDigest": "sha256:" + "42" * 32,
        "servicePublicKey": producer.ed25519_public_key_from_seed(
            seeds_by_key_id["key-verifier-receipt"]
        ).hex(),
        "namespaceId": FIXTURE_NAMESPACE_ID,
        "maximumFrameBytes": 4194304,
    }
    descriptor_digest = hashlib.sha256(
        b"pf.authority-store-service.v1\x00"
        + consumer.canonical_pf_jcs(descriptor_wire)
    ).digest()
    descriptor_ref = consumer.ContentRef(
        descriptor_wire["schema"],
        descriptor_wire["id"],
        descriptor_wire["version"],
        consumer.Digest("sha256", descriptor_digest),
    )
    task_rules = tuple(
        consumer.BootstrapAuthorityTaskRuleV1(
            task_id,
            consumer.ApprovalRuleV1(roles, minimum),
        )
        for task_id, roles, minimum in (
            ("TASK-D0-01", ("architecture", "quality"), 2),
            ("TASK-D0-02", ("architecture", "quality"), 2),
            ("TASK-D0-03", ("quality", "security"), 2),
            ("TASK-D0-04", ("quality", "security", "release"), 3),
            ("TASK-D0-05", ("quality", "security"), 2),
            ("TASK-D0-06", ("architecture", "quality"), 2),
        )
    )
    policy_bytes = producer.produce_bootstrap_authority_policy(
        id=FIXTURE_POLICY_ID,
        version="1.0.0",
        principals=principals,
        taskRules=task_rules,
        requiredTestSetRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        formalCatalogRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        bootstrapSetRule=consumer.ApprovalRuleV1(("quality", "security", "release"), 3),
        sessionContainmentRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        freshnessAuthorityRule=consumer.ApprovalRuleV1(("quality", "release"), 2),
        privateScanRule=consumer.ApprovalRuleV1(("quality", "security"), 2),
        privateScanPolicy=consumer.ContentRef(
            "proof-forge.private-scan-policy.v1",
            "s7-clean-room-private-scan",
            "1.0.0",
            consumer.Digest("sha256", bytes.fromhex("41" * 32)),
        ),
        revocationSnapshotRule=consumer.ApprovalRuleV1(("security", "release"), 2),
        authorityStoreService=descriptor_ref,
        verifier=consumer.BootstrapAuthorityVerifierV1(
            id="s7-clean-room-verifier",
            executableDigest=consumer.Digest(
                "sha256",
                hashlib.sha256(
                    (_MODULE_PATH.with_name("stage0_activate.py")).read_bytes()
                ).digest(),
            ),
            receiptKeyId="key-verifier-receipt",
            receiptPublicKey=public_key("verifier-receipt"),
        ),
    )
    _, policy_ref = consumer.parse_bootstrap_authority_policy(policy_bytes)
    return policy_bytes, policy_ref


def _fixture_required_set(policy_bytes: bytes, policy_ref,
                          seeds_by_key_id: Mapping[str, bytes]) -> bytes:
    producer = _PRODUCERS
    consumer = _CONSUMER
    snapshot_bytes = _ACCEPTANCE._phase5_snapshot_bytes(FIXTURE_TEST_IDS)
    document_digest = hashlib.sha256(
        b"pf.normative-document.v1\x00PHASE-5\x00" + snapshot_bytes
    ).digest()
    return producer.produce_required_test_set(
        id=FIXTURE_REQUIRED_SET_ID,
        version="1.0.0",
        phase5Document=consumer.NormativeDocumentRefV1(
            id="PHASE-5",
            contentDigest=consumer.Digest("sha256", document_digest),
            status="accepted",
            reviewCommit="a" * 40,
            reviewLink="https://review.example/phase-5/approval",
            approvedAt="2026-07-16",
            approvers=("principal-quality", "principal-security"),
        ),
        authorityPolicy=policy_ref,
        requiredTestIds=FIXTURE_TEST_IDS,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )


def _fixture_catalog(policy_bytes: bytes, policy_ref, required_bytes: bytes,
                     seeds_by_key_id: Mapping[str, bytes]) -> Tuple[bytes, bytes]:
    producer = _PRODUCERS
    consumer = _CONSUMER
    required_wire = consumer.decode_canonical_pf_jcs(required_bytes)
    required_digest = hashlib.sha256(
        b"pf.required-test-set.v1\x00" + required_bytes
    ).digest()
    catalog_wire = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": FIXTURE_CATALOG_ID,
        "version": "1.0.0",
        "qualification": "formal",
        "requiredTestSet": {
            "schema": "proof-forge.required-test-set.v1",
            "id": required_wire["id"],
            "version": required_wire["version"],
            "digest": "sha256:" + required_digest.hex(),
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
            {"id": "gate-materialize", "taskId": "TASK-D0-07",
             "testIds": ["TST-DOC-001"]},
            {"id": "gate-core", "taskId": "TASK-D0-07",
             "testIds": ["TST-ISO-001"]},
            {"id": "gate-evm-runtime", "taskId": "TASK-D0-07",
             "testIds": ["TST-ISO-002"]},
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
    approval_bytes = producer.produce_formal_gate_catalog_approval(
        id="s7-clean-room-catalog-approval",
        version="1.0.0",
        authorityPolicy=policy_ref,
        requiredTestSet=consumer.ContentRef(
            "proof-forge.required-test-set.v1",
            required_wire["id"],
            required_wire["version"],
            consumer.Digest("sha256", required_digest),
        ),
        catalog=catalog_ref,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
        authority_policy_bytes=policy_bytes,
    )
    return catalog_bytes, approval_bytes


def _fixture_handoff(policy_bytes: bytes, policy_ref, candidate: dict,
                     observation_bytes: bytes, seeds_by_key_id: Mapping[str, bytes]):
    """Produce a fixture eligible Stage-0 handoff over the real candidate."""
    consumer = _CONSUMER
    descriptor_wire = {
        "schema": "proof-forge.authority-store-service.v1",
        "id": "authority-store",
        "version": "1.0.0",
        "protocol": "pf.authority-store.rpc.v1",
        "serviceExecutableDigest": "sha256:" + "42" * 32,
        "servicePublicKey": _PRODUCERS.ed25519_public_key_from_seed(
            seeds_by_key_id["key-verifier-receipt"]
        ).hex(),
        "namespaceId": FIXTURE_NAMESPACE_ID,
        "maximumFrameBytes": 4194304,
    }
    descriptor_digest = hashlib.sha256(
        b"pf.authority-store-service.v1\x00"
        + consumer.canonical_pf_jcs(descriptor_wire)
    ).digest()
    descriptor_ref = consumer.ContentRef(
        descriptor_wire["schema"],
        descriptor_wire["id"],
        descriptor_wire["version"],
        consumer.Digest("sha256", descriptor_digest),
    )
    candidate_identity = consumer.parse_candidate_identity(candidate)
    base = _ACCEPTANCE.RehearsalBase(
        policyBytes=policy_bytes,
        policyRef=policy_ref,
        requiredBytes=b"",
        requiredRef=consumer.ContentRef(
            "proof-forge.required-test-set.v1",
            "s7-clean-room-placeholder",
            "1.0.0",
            consumer.Digest("sha256", bytes(32)),
        ),
        phase5Snapshot=None,
        catalogBytes=b"",
        catalogApprovalBytes=b"",
        candidate=candidate_identity,
        candidateCommit=candidate_identity.commit,
        candidateTreeObjectId=candidate_identity.treeObjectId,
        candidateArchiveDigestBytes=candidate_identity.archiveDigest.bytes,
        candidateDigestBytes=candidate_identity.digest.bytes,
        archiveBytes=b"",
        manifestBytes=b"",
        descriptorWire=descriptor_wire,
        descriptorRef=descriptor_ref,
        descriptorDigestBytes=descriptor_digest,
        serviceSeed=bytes(32),
        observationId="host-observation",
        observationVersion="1.0.0",
        observationBytes=observation_bytes,
        profileId="host-profile",
        profileVersion="1.0.0",
        profileBytes=json.dumps({"id": "linux-x86_64-mint223-eligible"}).encode(),
        tcbDigests=(
            hashlib.sha256(
                _MODULE_PATH.with_name("verify_host_stage0.sh").read_bytes()
            ).digest(),
            policy_ref.digest.bytes,
            hashlib.sha256(
                _MODULE_PATH.with_name("stage0_containment.py").read_bytes()
            ).digest(),
            hashlib.sha256(
                _MODULE_PATH.with_name("gate_evidence.py").read_bytes()
            ).digest(),
        ),
    )
    return base


def _produce_handoff(base, work: Path, run_id: str):
    produced = _ACCEPTANCE.produce_run_handoff(
        base,
        handoff_id="s7-clean-room-stage0-handoff",
        handoff_version="1.0.0",
        run_id=run_id,
        policy_path=str(work / "authority-policy.json"),
        archive_path=str(work / "candidate.tar"),
        manifest_path=str(work / "candidate.tar"),
    )
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
    return produced


_MATERIALIZE_PAYLOAD = r'''
import hashlib, json, socket, sys, tarfile
from pathlib import Path

LOCK = Path("/opt/lock/toolchains-linux-x86_64.lock.json")
CACHE = Path("/opt/assets")
DEST = Path("/workspace/tool-root")
TOOLS = ("anvil", "cast", "jv", "solc", "wat2wasm")

def denied(operation):
    try:
        operation()
    except OSError as error:
        if error.errno in (13, 1, 101, 99):
            return True
    return False

def main() -> int:
    lock = json.loads(LOCK.read_text())
    assets = {asset["id"]: asset for asset in lock["assets"]}
    DEST.mkdir(parents=True)
    for tool in lock["tools"]:
        if tool["id"] not in TOOLS:
            continue
        asset = assets[tool["assetId"]]
        archive = CACHE / "sha256" / asset["sha256"] / asset["id"]
        payload = archive.read_bytes()
        if hashlib.sha256(payload).hexdigest() != asset["sha256"]:
            print(f"asset digest mismatch: {tool['id']}", file=sys.stderr)
            return 1
        executable = tool["executable"]
        if asset.get("format") == "file":
            found = archive
            target = DEST / executable
            target.write_bytes(found.read_bytes())
        else:
            scratch = DEST / f".asset-{tool['id']}"
            scratch.mkdir()
            with tarfile.open(archive) as handle:
                for member in handle.getmembers():
                    if member.name.startswith("/") or ".." in member.name.split("/"):
                        print("unsafe asset path", file=sys.stderr)
                        return 1
                    if member.issym() or member.islnk():
                        continue
                    handle.extract(member, scratch)
            found = None
            for path in scratch.rglob(executable):
                if path.is_file():
                    found = path
                    break
            if found is None:
                print(f"tool executable missing in asset: {tool['id']}", file=sys.stderr)
                return 1
            target = DEST / executable
            target.write_bytes(found.read_bytes())
        target.chmod(0o555)
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != tool["executableSha256"]:
            print(f"tool digest mismatch: {tool['id']}", file=sys.stderr)
            return 1
    present = sorted(path.name for path in DEST.iterdir() if not path.name.startswith(".asset-"))
    if present != sorted(TOOLS):
        print(f"tool root mismatch: {present}", file=sys.stderr)
        return 1
    for scratch in DEST.glob(".asset-*"):
        import shutil
        shutil.rmtree(scratch)
    if not denied(lambda: socket.create_connection(("10.203.0.1", 80), 2)):
        print("materialize stage did not deny outbound network", file=sys.stderr)
        return 1
    print("materialize: ok (5 tools, offline, deny-all proven)")
    return 0

sys.exit(main())
'''

_CORE_PAYLOAD = r'''
import hashlib, os, sys
from pathlib import Path

SOURCE = Path("/opt/source")
EXPECTED_TOP = (
    "Examples", "Examples.lean", "ProofForgeV2", "ProofForgeV2.lean",
    "Tests", "lake-manifest.json", "lean-toolchain",
    "lakefile.lean", "testdata",
)

def main() -> int:
    if (SOURCE / ".git").exists() or (SOURCE / "active").exists():
        print("extracted candidate leaked metadata or legacy tree", file=sys.stderr)
        return 1
    for path in SOURCE.rglob("*"):
        if path.is_symlink():
            print(f"symlink in extracted candidate: {path}", file=sys.stderr)
            return 1
    top = sorted(entry.name for entry in SOURCE.iterdir())
    if top != sorted(EXPECTED_TOP):
        print(f"top-level mismatch: {top}", file=sys.stderr)
        return 1
    lean_files = sorted(SOURCE.rglob("*.lean"))
    if len(lean_files) < 10:
        print(f"too few lean files: {len(lean_files)}", file=sys.stderr)
        return 1
    toolchain = (SOURCE / "lean-toolchain").read_text().strip()
    if "lean4" not in toolchain:
        print(f"unexpected lean-toolchain: {toolchain}", file=sys.stderr)
        return 1
    digest = hashlib.sha256()
    count = 0
    for path in sorted(lean_files):
        digest.update(str(path.relative_to(SOURCE)).encode() + b"\x00")
        digest.update(path.read_bytes())
        count += 1
    probe = SOURCE / "lakefile.lean"
    try:
        probe.write_bytes(b"mutated")
        print("source-write probe unexpectedly succeeded", file=sys.stderr)
        return 1
    except OSError as error:
        if error.errno not in (13, 1, 30):
            print(f"source-write probe wrong errno: {error.errno}", file=sys.stderr)
            return 1
    if probe.read_bytes() == b"mutated":
        print("source-write probe changed the source", file=sys.stderr)
        return 1
    try:
        Path("/opt/policies/core.bwrap.json").read_bytes()
        print("policy file unexpectedly visible", file=sys.stderr)
        return 1
    except OSError as error:
        if error.errno != 2:
            print(f"policy-read probe wrong errno: {error.errno}", file=sys.stderr)
            return 1
    print(f"core: ok ({count} lean files re-audited, digest {digest.hexdigest()[:16]}, probes denied)")
    return 0

sys.exit(main())
'''

_EVM_PAYLOAD = r'''
import json, os, socket, subprocess, sys, time
from pathlib import Path

TOOLS = Path("/opt/tools")
ANVIL = TOOLS / "anvil"
CAST = TOOLS / "cast"
SOLC = TOOLS / "solc"
PORT = int(sys.argv[1])
LAN_IP = sys.argv[2]
RPC = f"http://127.0.0.1:{PORT}"
KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

def run(argv, **kwargs):
    return subprocess.run(argv, capture_output=True, text=True, timeout=30, **kwargs)

def denied(operation):
    try:
        operation()
    except OSError as error:
        return error.errno if error.errno in (13, 1, 101, 99) else None
    return "connected"

def main() -> int:
    compile_result = run([str(SOLC), "--bin", "/opt/fixture/Counter.sol", "-o", "/workspace"])
    if compile_result.returncode != 0:
        print(f"solc failed: {compile_result.stderr[:400]}", file=sys.stderr)
        return 1
    bytecode = Path("/workspace/Counter.bin").read_text().strip()
    anvil = subprocess.Popen(
        [str(ANVIL), "--host", "127.0.0.1", "--port", str(PORT),
         "--chain-id", "31337", "--silent"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        ready = False
        for _ in range(100):
            probe = run([str(CAST), "chain-id", "--rpc-url", RPC])
            if probe.stdout.strip() == "31337":
                ready = True
                break
            time.sleep(0.1)
        if not ready:
            print("anvil failed to start", file=sys.stderr)
            return 1
        encoded = run([str(CAST), "abi-encode", "constructor(uint64)", "7"]).stdout.strip()
        receipt = run([str(CAST), "send", "--json", "--rpc-url", RPC,
                       "--private-key", KEY, "--create", f"0x{bytecode}{encoded[2:]}"])
        if receipt.returncode != 0:
            print(f"deploy failed: {receipt.stderr[:400]}", file=sys.stderr)
            return 1
        address = json.loads(receipt.stdout)["contractAddress"]
        value = run([str(CAST), "call", "--rpc-url", RPC, address, "get()(uint64)"]).stdout.strip().split()[0]
        if value != "7":
            print(f"unexpected initial counter: {value}", file=sys.stderr)
            return 1
        run([str(CAST), "send", "--rpc-url", RPC, "--private-key", KEY,
             address, "increment(uint64)", "5"], check=True)
        value = run([str(CAST), "call", "--rpc-url", RPC, address, "get()(uint64)"]).stdout.strip().split()[0]
        if value != "12":
            print(f"unexpected incremented counter: {value}", file=sys.stderr)
            return 1
        maximum = "18446744073709551615"
        encoded_max = run([str(CAST), "abi-encode", "constructor(uint64)", maximum]).stdout.strip()
        receipt_max = run([str(CAST), "send", "--json", "--rpc-url", RPC,
                           "--private-key", KEY, "--create", f"0x{bytecode}{encoded_max[2:]}"])
        address_max = json.loads(receipt_max.stdout)["contractAddress"]
        overflow = run([str(CAST), "send", "--rpc-url", RPC, "--private-key", KEY,
                        address_max, "increment(uint64)", "1"])
        if overflow.returncode == 0:
            print("overflow transaction unexpectedly succeeded", file=sys.stderr)
            return 1
        preserved = run([str(CAST), "call", "--rpc-url", RPC, address_max, "get()(uint64)"]).stdout.strip().split()[0]
        if preserved != maximum:
            print(f"overflow changed state: {preserved}", file=sys.stderr)
            return 1
        lan = denied(lambda: socket.create_connection((LAN_IP, PORT), 2))
        if lan is None or lan == "connected":
            print(f"anvil reachable through the LAN interface: {lan}", file=sys.stderr)
            return 1
        try:
            socket.create_connection(("127.0.0.1", PORT + 1), 2)
            print("adjacent port unexpectedly reachable", file=sys.stderr)
            return 1
        except OSError as error:
            if error.errno != 111:
                print(f"adjacent-port probe wrong errno: {error.errno}", file=sys.stderr)
                return 1
        print("evm-runtime: ok (deploy/increment/overflow-rollback, LAN+adjacent denied)")
        return 0
    finally:
        anvil.kill()
        anvil.wait()

sys.exit(main())
'''


def _write_payloads(work: Path) -> dict:
    payloads = work / "payloads"
    payloads.mkdir()
    files = {
        "materialize": payloads / "materialize_payload.py",
        "core": payloads / "core_payload.py",
        "evm": payloads / "evm_payload.py",
    }
    files["materialize"].write_text(_MATERIALIZE_PAYLOAD)
    files["core"].write_text(_CORE_PAYLOAD)
    files["evm"].write_text(_EVM_PAYLOAD)
    fixture = payloads / "Counter.sol"
    fixture.write_text(COUNTER_SOL)
    files["counter"] = fixture
    return files


def _runtime_binds(extra: Sequence[dict]) -> list:
    binds = [
        {"src": PYTHON_PATH, "dest": PYTHON_PATH, "readOnly": True},
        {"src": "/usr/lib", "dest": "/usr/lib", "readOnly": True},
        {"src": "/lib", "dest": "/lib", "readOnly": True},
        {"src": "/lib64", "dest": "/lib64", "readOnly": True},
    ]
    binds.extend(extra)
    return binds


def _run_stage(stage: str, invocation: str, payload: list, binds: list,
               stage_work: Path, policies_dir: Path, runtime_port=None,
               timeout_seconds: float = 120.0) -> object:
    home = stage_work / "home"
    cache = stage_work / "cache"
    home.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    env = [
        {"name": "PATH", "value": "/usr/bin:/bin"},
        {"name": "LC_ALL", "value": "C"},
        {"name": "HOME", "value": "/workspace/home"},
        {"name": "XDG_CACHE_HOME", "value": "/workspace/cache"},
    ]
    try:
        outcome = _BWRAP.launch_stage(
            stage=stage,
            invocation=invocation,
            payload=payload,
            binds=binds,
            tmpfs=(),
            env=env,
            workdir="/workspace",
            timeout_seconds=timeout_seconds,
            runtime_port=runtime_port,
            run_binding_sha256="ab" * 32,
            invocation_binding_sha256="cd" * 32,
            policies_dir=policies_dir,
            receipt=True,
            workspace_src=str(stage_work),
        )
    except _BWRAP.BwrapError as error:
        _stage(f"{stage} failed: {error.detail}")
    if outcome.exitCode != 0:
        _stage(
            f"{stage} payload exited {outcome.exitCode}: "
            f"{outcome.stderr[-400:]!r}"
        )
    return outcome


def _supervise(work: Path, policy_bytes: bytes, policy_ref, candidate: dict,
               handoff_ref, seeds_by_key_id: Mapping[str, bytes],
               policies_dir: Path) -> Tuple[bytes, tuple]:
    """Run one supervised minimal invocation and sign the containment receipt."""
    profile = _BWRAP.render_stage_profile(
        "core",
        binds=_runtime_binds([]),
        tmpfs=("/workspace",),
        env=[{"name": "PATH", "value": "/usr/bin:/bin"}],
        workdir="/workspace",
    )
    payload = [PYTHON_PATH, "-I", "-S", "-c", "import os,sys; sys.stdout.write('supervised\\n')"]
    argv = tuple(_BWRAP.profile_argv(profile)) + tuple(payload)
    started_ns = time.monotonic_ns()
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
            env={},
        )
    except OSError:
        _containment("cannot spawn the supervised invocation")
    session_id = os.getsid(process.pid)
    child_pid = process.pid
    stdout, stderr, timed_out, capped = _BWRAP._bounded_capture(process, 30.0)
    finished_ns = time.monotonic_ns()
    if timed_out or capped or process.returncode != 0:
        _containment("supervised invocation did not complete cleanly")
    escaped = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.getsid(int(entry)) == session_id:
                escaped.append(int(entry))
        except (OSError, ProcessLookupError):
            continue
    if escaped:
        _containment("a descendant escaped the supervised session")
    descendants = (
        {
            "pid": child_pid,
            "parentPid": os.getpid(),
            "startToken": started_ns,
            "sessionId": session_id,
            "executableDigest": "sha256:" + hashlib.sha256(
                Path(BWRAP_PATH).read_bytes()
            ).hexdigest(),
            "termination": "exited",
        },
    )
    receipt_bytes = _FORMAL_INPUTS.produce_session_containment_receipt(
        id="s7-clean-room-session-containment",
        version="1.0.0",
        candidate=candidate,
        stage0_handoff=handoff_ref,
        supervisor_digest="sha256:" + hashlib.sha256(
            _MODULE_PATH.with_name("stage0_containment.py").read_bytes()
        ).hexdigest(),
        root_session_id=f"session-{session_id}",
        descendants=descendants,
        escape_probes=({"id": "escape-probe-01", "result": "contained"},),
        started_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started_ns / 1e9)),
        finished_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(finished_ns / 1e9)),
        result="contained",
        authority_policy_bytes=policy_bytes,
        signers=(
            ("key-quality", seeds_by_key_id["key-quality"]),
            ("key-security", seeds_by_key_id["key-security"]),
        ),
    )
    return receipt_bytes, descendants


def sign_containment_receipt(*, report: CleanRoomReport, descendants: tuple,
                             escape_probes: tuple, started_at: str,
                             finished_at: str, seeds_by_key_id: Mapping[str, bytes],
                             output) -> bytes:
    """Sign a containment receipt for already-observed values (gate helper)."""
    policy_bytes = Path(report.policyPath).read_bytes()
    candidate = _CONSUMER.parse_candidate_identity(
        json.loads((Path(report.evidencePath).parent / "candidate.json").read_bytes())
    )
    try:
        receipt_bytes = _FORMAL_INPUTS.produce_session_containment_receipt(
            id="s7-clean-room-session-containment",
            version="1.0.0",
            candidate={
                "commit": candidate.commit,
                "treeObjectId": candidate.treeObjectId,
                "archiveDigest": "sha256:" + candidate.archiveDigest.bytes.hex(),
                "digest": "sha256:" + candidate.digest.bytes.hex(),
            },
            stage0_handoff=json.loads(
                (Path(report.evidencePath).parent / "handoff-ref.json").read_bytes()
            ),
            supervisor_digest="sha256:" + "81" * 32,
            root_session_id="session-escape-simulation",
            descendants=descendants,
            escape_probes=escape_probes,
            started_at=started_at,
            finished_at=finished_at,
            result="contained",
            authority_policy_bytes=policy_bytes,
            signers=(
                ("key-quality", seeds_by_key_id["key-quality"]),
                ("key-security", seeds_by_key_id["key-security"]),
            ),
        )
    except _FORMAL_INPUTS.FormalInputError as error:
        _containment(error.detail)
    Path(output).write_bytes(receipt_bytes)
    return receipt_bytes


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _build_fixture_evidence(
    *,
    ev_id: str,
    candidate: dict,
    archive_bytes: bytes,
    observation: dict,
    observation_bytes: bytes,
    profile_bytes: bytes,
    repo_root: Path,
    policy_files: Mapping[str, bytes],
    tool_files: Mapping[str, bytes],
    payload_files: Mapping[str, bytes],
    counter_sol: bytes,
    counter_bin: bytes,
    stage_logs: Mapping[str, Tuple[bytes, bytes]],
    stage_observations: Tuple[dict, ...],
    attempts: Tuple[dict, ...],
    started_utc: str,
    ended_utc: str,
    environment_entries: Tuple[dict, ...],
) -> bytes:
    """Build the aggregate fixture formal EV for one clean-room run."""
    def member(path: str, role: str, payload: bytes) -> dict:
        return {
            "role": role,
            "path": path,
            "sha256": _sha256_bytes(payload),
            "size": len(payload),
        }

    inputs = [
        member("candidate/archive.tar", "candidate-archive", archive_bytes),
        member("locks/host-bootstrap-linux.lock", "host-bootstrap-lock",
               (repo_root / "host-bootstrap-linux.lock").read_bytes()),
        member("locks/host-profiles.lock.json", "host-profile-lock",
               (repo_root / "host-profiles.lock.json").read_bytes()),
        member("locks/toolchains-linux-x86_64.lock.json", "toolchain-lock",
               (repo_root / "toolchains-linux-x86_64.lock.json").read_bytes()),
        member("observation/host-observation.json", "host-observation",
               observation_bytes),
    ]
    for stage, payload in sorted(policy_files.items()):
        inputs.append(
            member(f"policies/{stage}.bwrap.json", "sandbox-rendered-policy", payload)
        )
    for name, payload in sorted(tool_files.items()):
        inputs.append(member(f"tools/{name}", "external-tool", payload))
    for name, payload in sorted(payload_files.items()):
        inputs.append(member(f"payloads/{name}", "payload-script", payload))
    inputs.append(member("fixture/Counter.sol", "fixture-contract", counter_sol))
    inputs.sort(key=lambda item: (item["role"], item["path"]))
    artifacts = [
        {
            "target": "evm",
            "role": "bytecode",
            "path": "out/Counter.bin",
            "mediaType": "application/octet-stream",
            "sha256": _sha256_bytes(counter_bin),
            "size": len(counter_bin),
            "retained": True,
        }
    ]
    logs = []
    for stage, (stdout, stderr) in sorted(stage_logs.items()):
        logs.append(
            {
                "path": f"logs/{stage}.stdout.log",
                "sha256": _sha256_bytes(stdout),
                "size": len(stdout),
                "truncated": False,
                "privateDataScan": "passed",
            }
        )
        logs.append(
            {
                "path": f"logs/{stage}.stderr.log",
                "sha256": _sha256_bytes(stderr),
                "size": len(stderr),
                "truncated": False,
                "privateDataScan": "passed",
            }
        )
    engine_sha = _sha256_bytes(Path(BWRAP_PATH).read_bytes())
    logs.sort(key=lambda item: item["path"])
    policies = []
    for stage, payload in sorted(policy_files.items()):
        profile = json.loads(payload.decode("utf-8"))
        policies.append(
            {
                "id": stage,
                "engine": "bwrap",
                "engineSha256": engine_sha,
                "defaultAction": "deny",
                "network": profile["networkMode"],
                "templateSha256": _sha256_bytes(payload),
                "renderedSha256": _sha256_bytes(payload),
                "probes": [{"id": "isolation-denied", "status": "passed"}],
            }
        )
    tools = []
    tool_entries = dict(tool_files)
    tool_entries["bwrap"] = Path(BWRAP_PATH).read_bytes()
    for name, payload in sorted(tool_entries.items()):
        tools.append(
            {
                "id": name,
                "version": "locked",
                "source": "content-addressed-cache",
                "assetSha256": _sha256_bytes(payload),
                "executableSha256": _sha256_bytes(payload),
                "closureSha256": _sha256_bytes(payload),
            }
        )
    document = {
        "schema": "proof-forge.evidence.v1",
        "id": ev_id,
        "gate": {
            "id": "gate-evm-runtime",
            "taskId": "TASK-D0-07",
            "testIds": ["TST-ISO-002"],
            "qualification": "formal",
        },
        "repository": {
            "commit": candidate["commit"],
            "subtree": ".",
            "treeObjectId": candidate["treeObjectId"],
            "anchorSource": "external",
            "dirty": False,
            "dirtyDigest": None,
            "unchangedDuringRun": True,
            "archive": {
                "format": "git-tar",
                "sha256": candidate["archiveDigest"][7:],
                "size": len(archive_bytes),
            },
        },
        "hostAttestation": {
            "scope": "local-point-in-time",
            "remoteAttestation": False,
            "profileId": observation["hostProfileId"],
            "eligibleForHermetic": True,
            "bootstrapLockSha256": _sha256_bytes(
                (repo_root / "host-bootstrap-linux.lock").read_bytes()
            ),
            "hostProfileLockSha256": _sha256_bytes(
                (repo_root / "host-profiles.lock.json").read_bytes()
            ),
            "toolchainLockSha256": _sha256_bytes(
                (repo_root / "toolchains-linux-x86_64.lock.json").read_bytes()
            ),
            "launcherSha256": _sha256_bytes(
                _MODULE_PATH.with_name("sandbox_bwrap.py").read_bytes()
            ),
            "verifierSha256": _sha256_bytes(
                _MODULE_PATH.with_name("verify_host_stage0.sh").read_bytes()
            ),
            "observationSha256": _sha256_bytes(observation_bytes),
        },
        "environment": {
            "os": (
                f"{observation['platform']['osReleaseId']} "
                f"{observation['platform']['osReleaseVersionId']}"
            ),
            "arch": observation["platform"]["arch"],
            "environmentSha256": _sha256_bytes(
                _CONSUMER.canonical_pf_jcs(list(environment_entries))
            ),
            "sourceDateEpoch": 0,
            "cleanRoom": True,
            "buildCache": "empty",
            "assetCache": "locked-read-only",
        },
        "sandboxPolicies": policies,
        "tools": tools,
        "command": {
            "argv": ["/usr/bin/python3", "-I", "-S", "scripts/formal_clean_room.py"],
            "cwdRelative": ".",
            "startedUtc": started_utc,
            "endedUtc": ended_utc,
            "durationMs": 0,
            "attempts": list(attempts),
        },
        "inputs": inputs,
        "artifacts": artifacts,
        "artifactSetSha256": "",
        "observations": list(stage_observations),
        "logs": logs,
        "result": "passed",
        "skipAuthorization": None,
    }
    document["artifactSetSha256"] = _EV_CORE.artifact_set_sha256(
        document["artifacts"]
    )
    document_bytes = _EV_CORE.canonical_bytes(document)
    _EV_CORE.validate_evidence(_EV_CORE.decode_json(document_bytes))
    return document_bytes


def _lan_ip() -> str:
    try:
        host = socket.gethostname()
        for family, _, _, _, address in socket.getaddrinfo(host, None):
            if family == socket.AF_INET:
                ip = address[0]
                if not ip.startswith("127."):
                    return ip
    except OSError:
        pass
    return "192.168.1.1"


def _free_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _atomic_write_0400(path: Path, payload: bytes) -> None:
    fd, temp_path = tempfile.mkstemp(prefix=".stage-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, 0o400)
        try:
            os.link(temp_path, path)
        except FileExistsError:
            _io(f"evidence output already exists: {path.name}")
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def run_formal_clean_room(
    *,
    repo_root: str,
    work_root: str,
    seeds_by_key_id: Mapping[str, bytes],
    run_id: str,
    nonce: str,
    expected_commit: Optional[str] = None,
    expected_archive_sha256: Optional[str] = None,
    mid_run_hook: Optional[object] = None,
    skip_tools: Tuple[str, ...] = (),
) -> CleanRoomReport:
    """Run the TST-ISO-002 fixture clean-room end to end."""
    started = time.monotonic()
    started_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    repo = Path(repo_root)
    work = Path(work_root)
    if work.exists() and any(work.iterdir()):
        _io("work root is not empty")
    work.mkdir(parents=True, exist_ok=True)
    try:
        observation, observation_bytes = _run_authoritative_stage0(repo_root)
        status_before = _status_hash(repo_root)
        candidate, archive_bytes, source = _candidate_anchor(
            repo_root, work, expected_commit, expected_archive_sha256
        )

        policy_bytes, policy_ref = _fixture_policy_bytes(seeds_by_key_id)
        required_bytes = _fixture_required_set(
            policy_bytes, policy_ref, seeds_by_key_id
        )
        catalog_bytes, catalog_approval_bytes = _fixture_catalog(
            policy_bytes, policy_ref, required_bytes, seeds_by_key_id
        )
        (work / "authority-policy.json").write_bytes(policy_bytes)
        handoff_base = _fixture_handoff(
            policy_bytes, policy_ref, candidate, observation_bytes, seeds_by_key_id
        )
        handoff = _produce_handoff(handoff_base, work, run_id)
        handoff_ref_wire = {
            "schema": handoff.handoffRef.schema,
            "id": handoff.handoffRef.id,
            "version": handoff.handoffRef.version,
            "digest": "sha256:" + handoff.handoffDigest.bytes.hex(),
        }

        payloads = _write_payloads(work)
        policies_dir = work / "policies"
        policies_dir.mkdir()
        stages_work = work / "stages"
        stages_work.mkdir()

        # materialize: external tools from the locked cache, deny-all.
        mat_work = stages_work / "materialize" / "workspace"
        mat_work.mkdir(parents=True)
        mat_binds = _runtime_binds([
            {"src": str(payloads["materialize"]), "dest": "/opt/payload/materialize.py",
             "readOnly": True},
            {"src": str(repo / LOCK_RELATIVE),
             "dest": "/opt/lock/toolchains-linux-x86_64.lock.json",
             "readOnly": True},
            {"src": DEFAULT_ASSET_CACHE, "dest": "/opt/assets", "readOnly": True},
        ])
        mat_outcome = _run_stage(
            "materialize", "materialize-tools",
            [PYTHON_PATH, "-I", "-S", "/opt/payload/materialize.py"],
            mat_binds, mat_work, policies_dir, timeout_seconds=120.0,
        )
        tool_root = mat_work / "tool-root"
        for tool_id in skip_tools:
            target = tool_root / tool_id
            if target.exists():
                target.unlink()

        # core: structural re-audit of the extracted candidate, deny-all.
        core_work = stages_work / "core" / "workspace"
        core_work.mkdir(parents=True)
        core_binds = _runtime_binds([
            {"src": str(payloads["core"]), "dest": "/opt/payload/core.py",
             "readOnly": True},
            {"src": str(source), "dest": "/opt/source", "readOnly": True},
        ])
        core_outcome = _run_stage(
            "core", "core-audit",
            [PYTHON_PATH, "-I", "-S", "/opt/payload/core.py"],
            core_binds, core_work, policies_dir, timeout_seconds=120.0,
        )

        # evm-runtime: real Anvil Counter differential, loopback-only.
        evm_work = stages_work / "evm-runtime" / "workspace"
        evm_work.mkdir(parents=True)
        evm_port = _free_port()
        evm_binds = _runtime_binds([
            {"src": str(payloads["evm"]), "dest": "/opt/payload/evm.py",
             "readOnly": True},
            {"src": str(tool_root), "dest": "/opt/tools", "readOnly": True},
            {"src": str(payloads["counter"]), "dest": "/opt/fixture/Counter.sol",
             "readOnly": True},
        ])
        evm_outcome = _run_stage(
            "evm-runtime", "anvil-counter",
            [PYTHON_PATH, "-I", "-S", "/opt/payload/evm.py",
             str(evm_port), _lan_ip()],
            evm_binds, evm_work, policies_dir,
            runtime_port=evm_port, timeout_seconds=120.0,
        )

        # containment: supervised minimal invocation + signed receipt.
        containment_bytes, descendants = _supervise(
            work, policy_bytes, policy_ref, candidate, handoff_ref_wire,
            seeds_by_key_id, policies_dir,
        )

        if mid_run_hook is not None:
            mid_run_hook()
        status_after = _status_hash(repo_root)
        if status_after != status_before:
            _anchor("candidate worktree status changed during the run")

        ended_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        policy_files = {
            "materialize": (policies_dir / "materialize.bwrap.json").read_bytes(),
            "core": (policies_dir / "core.bwrap.json").read_bytes(),
            "evm-runtime": (policies_dir / "evm-runtime.bwrap.json").read_bytes(),
        }
        tool_files = {
            name: (tool_root / name).read_bytes()
            for name in sorted(TOOL_IDS)
            if (tool_root / name).exists()
        }
        payload_files = {
            "materialize.py": payloads["materialize"].read_bytes(),
            "core.py": payloads["core"].read_bytes(),
            "evm.py": payloads["evm"].read_bytes(),
        }
        counter_bin = (evm_work / "Counter.bin").read_bytes()
        stage_logs = {
            "materialize": (mat_outcome.stdout, mat_outcome.stderr),
            "core": (core_outcome.stdout, core_outcome.stderr),
            "evm-runtime": (evm_outcome.stdout, evm_outcome.stderr),
        }
        stage_observations = tuple(
            {
                "step": f"stage-{stage}",
                "status": "passed",
                "return": 0,
                "logicalState": {"stage": stage},
                "effects": [],
                "errorClass": None,
            }
            for stage in ("materialize", "core", "evm-runtime")
        )
        # Formal-passed EVs admit exactly one command attempt: the single
        # clean-room invocation; per-stage detail lives in observations/logs.
        attempts = (
            {
                "number": 1,
                "exitCode": 0,
                "signal": None,
                "timedOut": False,
                "stdoutLog": "logs/evm-runtime.stdout.log",
                "stderrLog": "logs/evm-runtime.stderr.log",
            },
        )
        # The evidence id's UTC date must equal the command's endedUtc date:
        # derive it from the run clock, never a hardcoded calendar day.
        ev_id = "EV-" + ended_utc[:10].replace("-", "") + "-0001"
        evidence_bytes = _build_fixture_evidence(
            ev_id=ev_id,
            candidate=candidate,
            archive_bytes=archive_bytes,
            observation=observation,
            observation_bytes=observation_bytes,
            profile_bytes=b"",
            repo_root=repo,
            policy_files=policy_files,
            tool_files=tool_files,
            payload_files=payload_files,
            counter_sol=payloads["counter"].read_bytes(),
            counter_bin=counter_bin,
            stage_logs=stage_logs,
            stage_observations=stage_observations,
            attempts=attempts,
            started_utc=started_utc,
            ended_utc=ended_utc,
            environment_entries=(
                {"name": "PATH", "value": "/usr/bin:/bin"},
                {"name": "LC_ALL", "value": "C"},
            ),
        )

        evidence_root = work / "evidence"
        evidence_root.mkdir()
        evidence_path = evidence_root / f"{ev_id}.json"
        containment_path = evidence_root / "session-containment.json"
        policy_path = evidence_root / "authority-policy.json"
        required_path = evidence_root / "required-test-set.json"
        catalog_path = evidence_root / "catalog.json"
        catalog_approval_path = evidence_root / "catalog-approval.json"
        candidate_path = evidence_root / "candidate.json"
        handoff_ref_path = evidence_root / "handoff-ref.json"
        _atomic_write_0400(candidate_path, json.dumps(candidate, sort_keys=True).encode() + b"\n")
        _atomic_write_0400(handoff_ref_path, json.dumps(handoff_ref_wire, sort_keys=True).encode() + b"\n")
        _atomic_write_0400(policy_path, policy_bytes)
        _atomic_write_0400(required_path, required_bytes)
        _atomic_write_0400(catalog_path, catalog_bytes)
        _atomic_write_0400(catalog_approval_path, catalog_approval_bytes)
        _atomic_write_0400(containment_path, containment_bytes)
        _atomic_write_0400(evidence_path, evidence_bytes)

        duration_ms = int((time.monotonic() - started) * 1000)
        return CleanRoomReport(
            eligibleForHermetic=True,
            hostProfileId=observation["hostProfileId"],
            candidateCommit=candidate["commit"],
            candidateTreeObjectId=candidate["treeObjectId"],
            archiveSha256=candidate["archiveDigest"][7:],
            evidencePath=str(evidence_path),
            containmentPath=str(containment_path),
            policyPath=str(policy_path),
            requiredSetPath=str(required_path),
            catalogPath=str(catalog_path),
            catalogApprovalPath=str(catalog_approval_path),
            containmentDescendants=descendants,
            stageReceiptPaths=tuple(
                str(path) for path in sorted(policies_dir.glob("sandbox-*.receipt.json"))
            ),
            durationMs=duration_ms,
        )
    except CleanRoomError:
        raise
    except Exception as error:
        _io(f"clean-room failed: {type(error).__name__}: {error}")


def format_report_lines(report: CleanRoomReport) -> list:
    """Render the typed clean-room report as exact output lines."""
    return [
        f"stage0: ok profile={report.hostProfileId} eligible=true",
        f"anchor: ok commit={report.candidateCommit} archive={report.archiveSha256[:16]}",
        "stages: ok materialize(deny-all) core(deny-all) evm-runtime(loopback-only)",
        "containment: contained (session supervised, no escapees)",
        f"evidence: {Path(report.evidencePath).stem} published ({report.evidencePath})",
        "clean-room: ok",
    ]


def evidence_core() -> ModuleType:
    """Return the evidence-v1 core module used for EV validation."""
    return _EV_CORE


def formal_consumer() -> ModuleType:
    """Return the formal evidence consumer module."""
    return _FORMAL


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
    """Run one fixture clean-room into a temp workspace; print the report."""
    args = list(sys.argv[1:] if argv is None else argv)
    if args:
        print("usage: formal_clean_room.py", file=sys.stderr)
        return 2
    workspace = Path(tempfile.mkdtemp(prefix="formal-clean-room-")).resolve()
    try:
        report = run_formal_clean_room(
            repo_root=str(_MODULE_PATH.parent.parent),
            work_root=str(workspace / "run"),
            seeds_by_key_id=_FIXTURE_SEEDS,
            run_id="s7-clean-room-run",
            nonce="ee" * 32,
        )
        for line in format_report_lines(report):
            print(line)
        return 0
    except CleanRoomError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
