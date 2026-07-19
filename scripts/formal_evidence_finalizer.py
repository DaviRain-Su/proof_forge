#!/usr/bin/env python3
"""Single-snapshot formal evidence finalization orchestrator (TASK-D0-07
slice S4).

Captures one fixture authority bundle exactly once (O_NOFOLLOW, regular
file, bounded per-file and total capture), resolves every gate evidence ref
to canonical ``proof-forge.evidence.v1`` bytes with full content joins,
drives the S1/S2/S3 signed-input producers (revocation ledger, private
scan, session containment, freshness authority, finalizer identity),
produces and publishes the formal finalization record and a support binding
through ``formal_evidence_producer.py``, and re-verifies the published
artifacts end to end.  Every failure closes with
``PF-EVIDENCE-FORMAL-UNVERIFIED`` and removes anything already published.

Signing follows the same custody discipline as bootstrap_task_producers.py:
seeds arrive only as explicit 32-byte call parameters and never appear in
outputs, logs, or exception details.  Slice scope is the fixture namespace
(ADR-0018): nothing here is formal or hermetic evidence.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import stat
import sys
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
_PRODUCERS = _load_module(
    _MODULE_PATH.with_name("bootstrap_task_producers.py"),
    "proof_forge_bootstrap_task_producers_for_finalizer",
)
_FORMAL_PRODUCER = _load_module(
    _MODULE_PATH.with_name("formal_evidence_producer.py"),
    "proof_forge_formal_evidence_producer_for_finalizer",
)
_REVOCATION = _load_module(
    _MODULE_PATH.with_name("revocation_ledger.py"),
    "proof_forge_revocation_ledger_for_finalizer",
)
_PRIVATE_SCAN = _load_module(
    _MODULE_PATH.with_name("private_scan.py"),
    "proof_forge_private_scan_for_finalizer",
)
_FORMAL_INPUTS = _load_module(
    _MODULE_PATH.with_name("formal_input_producers.py"),
    "proof_forge_formal_input_producers_for_finalizer",
)
_EV_CORE = _load_module(
    _MODULE_PATH.with_name("evidence_v1_core.py"),
    "proof_forge_evidence_v1_core_for_finalizer",
)

_CONSUMER = _FORMAL_PRODUCER._CONSUMER
_FORMAL = _FORMAL_PRODUCER._FORMAL
Digest = _FORMAL_PRODUCER.Digest
ContentRef = _FORMAL_PRODUCER.ContentRef

REJECTION = "PF-EVIDENCE-FORMAL-UNVERIFIED"
MAX_CAPTURE_FILE_BYTES = 4 * 1024 * 1024
MAX_CAPTURE_TOTAL_BYTES = 64 * 1024 * 1024
_D0_GATE_TASK_IDS = frozenset(f"TASK-D0-{index:02d}" for index in range(1, 8))
_D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
_CAPTURED_AUTHORITY_FILES = (
    "authority-policy.json",
    "required-test-set.json",
    "phase5-snapshot.json",
    "catalog.json",
    "catalog-approval.json",
    "eligible-stage0-handoff.json",
    "approval-set.json",
    "activation-receipt.json",
)
_INPUT_DOMAINS = {
    "containment": b"pf.session-containment-receipt.v1\x00",
    "freshness": b"pf.freshness-authority-snapshot.v1\x00",
    "privateScan": b"pf.private-scan-receipt.v1\x00",
    "revocation": b"pf.revocation-ledger-snapshot.v1\x00",
    "finalizer": b"pf.formal-finalizer-identity.v1\x00",
}
_CATALOG_APPROVAL_DOMAIN = b"pf.formal-gate-catalog-approval.v1\x00"


class FormalFinalizerError(Exception):
    """Stable finalizer failure; the only public code is the rejection."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail or REJECTION)
        self.code = REJECTION
        self.detail = detail


def _unverified(detail: str) -> NoReturn:
    raise FormalFinalizerError(detail)


@dataclass(frozen=True)
class FinalizeOutcome:
    recordBytes: bytes
    recordPath: str
    bindingBytes: bytes
    bindingPath: str
    expiresAt: str
    containmentBytes: bytes
    freshnessBytes: bytes
    privateScanBytes: bytes
    revocationLedgerBytes: bytes
    revocationRecordBytes: Tuple[bytes, ...]
    finalizerIdentityBytes: bytes


def _safe_read_once(path: Path, where: str) -> bytes:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        _unverified(f"cannot capture {where}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _unverified(f"{where} is not a regular file")
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
            if offset > MAX_CAPTURE_FILE_BYTES:
                _unverified(f"{where} exceeds the capture maximum")
        return b"".join(chunks)
    finally:
        os.close(fd)


def _capture_tree(fixture_root: Path) -> dict:
    if not fixture_root.is_dir():
        _unverified("fixture root is not a directory")
    captured: dict = {}
    total = 0
    for relative in _CAPTURED_AUTHORITY_FILES:
        payload = _safe_read_once(fixture_root / relative, relative)
        total += len(payload)
        if total > MAX_CAPTURE_TOTAL_BYTES:
            _unverified("capture exceeds the total maximum")
        captured[relative] = payload
    for task_id in _D0_TASK_IDS:
        for kind, directory in (("approval", "approvals"), ("receipt", "receipts")):
            relative = f"{directory}/{task_id.lower()}-{kind}.json"
            payload = _safe_read_once(fixture_root / relative, relative)
            total += len(payload)
            if total > MAX_CAPTURE_TOTAL_BYTES:
                _unverified("capture exceeds the total maximum")
            captured[relative] = payload
    for directory in ("evidence", "revocation"):
        entries = []
        directory_path = fixture_root / directory
        if directory_path.is_dir():
            entries = sorted(
                path for path in directory_path.iterdir() if not path.is_dir()
            )
        for path in entries:
            relative = f"{directory}/{path.name}"
            payload = _safe_read_once(path, relative)
            total += len(payload)
            if total > MAX_CAPTURE_TOTAL_BYTES:
                _unverified("capture exceeds the total maximum")
            captured[relative] = payload
    return captured


def _digest_wire(domain: bytes, payload: bytes) -> str:
    return "sha256:" + hashlib.sha256(domain + payload).hexdigest()


def _content_ref(schema: str, identifier: str, version: str, domain: bytes,
                 payload: bytes):
    return ContentRef(
        schema,
        identifier,
        version,
        Digest("sha256", hashlib.sha256(domain + payload).digest()),
    )


def _ref_id_version(payload: bytes) -> Tuple[str, str]:
    try:
        wire = _CONSUMER.decode_canonical_pf_jcs(payload)
    except _CONSUMER.Rejected:
        _unverified("produced input is not canonical PF-JCS")
    if type(wire) is not dict:
        _unverified("produced input is not an object")
    return wire["id"], wire["version"]


def _publish_cleanup(paths: list) -> None:
    for path in paths:
        try:
            os.unlink(path)
        except OSError:
            pass
    for path in paths:
        parent = Path(path).parent
        while True:
            try:
                parent.rmdir()
            except OSError:
                break
            if parent == parent.parent:
                break
            parent = parent.parent


def finalize_formal_evidence(
    *,
    fixture_root: str,
    trusted_root: str,
    record_id: str,
    finalized_at: str,
    observed_at: str,
    maximum_age_seconds: int,
    clock_source_bytes: bytes,
    containment_observation: dict,
    finalizer_executable_bytes: bytes,
    finalizer_identity_id: str,
    finalizer_closure_digest: str,
    finalizer_toolchain_lock_digest: str,
    scan_policy_bytes: bytes,
    gate_inputs: Mapping[str, dict],
    signers: Mapping[str, bytes],
    support: dict,
) -> FinalizeOutcome:
    """Capture, resolve, produce, publish, and re-verify one formal record."""
    published: list = []
    try:
        return _finalize(
            fixture_root=fixture_root,
            trusted_root=trusted_root,
            record_id=record_id,
            finalized_at=finalized_at,
            observed_at=observed_at,
            maximum_age_seconds=maximum_age_seconds,
            clock_source_bytes=clock_source_bytes,
            containment_observation=containment_observation,
            finalizer_executable_bytes=finalizer_executable_bytes,
            finalizer_identity_id=finalizer_identity_id,
            finalizer_closure_digest=finalizer_closure_digest,
            finalizer_toolchain_lock_digest=finalizer_toolchain_lock_digest,
            scan_policy_bytes=scan_policy_bytes,
            gate_inputs=gate_inputs,
            signers=signers,
            support=support,
            published=published,
        )
    except FormalFinalizerError:
        _publish_cleanup(published)
        raise
    except Exception as error:
        _publish_cleanup(published)
        _unverified(f"finalization failed: {type(error).__name__}")


def _finalize(**kwargs) -> FinalizeOutcome:
    fixture_root = Path(kwargs["fixture_root"])
    trusted_root = kwargs["trusted_root"]
    published: list = kwargs["published"]
    captured = _capture_tree(fixture_root)

    policy, policy_ref = _CONSUMER.parse_bootstrap_authority_policy(
        captured["authority-policy.json"]
    )
    snapshot_wire = json.loads(captured["phase5-snapshot.json"].decode("utf-8"))
    if set(snapshot_wire) != {"id", "path", "bytesHex"}:
        _unverified("phase5 snapshot must contain exactly id/path/bytesHex")
    phase5_snapshot = _CONSUMER.BootstrapDocumentSnapshotV1(
        snapshot_wire["id"],
        snapshot_wire["path"],
        bytes.fromhex(snapshot_wire["bytesHex"]),
    )
    required_set, required_ref = _CONSUMER.parse_document_bound_required_test_set(
        captured["required-test-set.json"],
        captured["authority-policy.json"],
        phase5_snapshot,
    )
    handoff_preflight = _CONSUMER._preflight_eligible_stage0_handoff(
        captured["eligible-stage0-handoff.json"]
    )
    handoff = handoff_preflight.handoff
    handoff_ref = handoff_preflight.handoffRef
    catalog_preflight = _CONSUMER._preflight_formal_gate_catalog(
        captured["catalog.json"]
    )
    catalog_ref = catalog_preflight.catalogRef
    if catalog_preflight.requiredTestSet != required_ref:
        _unverified("catalog requiredTestSet does not match the resolved set")
    catalog_wire = _CONSUMER.decode_canonical_pf_jcs(captured["catalog.json"])
    candidate = handoff.candidate

    approval_set, set_ref = _CONSUMER.parse_bootstrap_approval_set(
        captured["approval-set.json"],
        tuple(
            captured[f"receipts/{task_id.lower()}-receipt.json"]
            for task_id in _D0_TASK_IDS
        ),
        captured["required-test-set.json"],
        captured["authority-policy.json"],
        phase5_snapshot,
        captured["eligible-stage0-handoff.json"],
    )
    verifier_receipt, verifier_ref = (
        _CONSUMER.parse_bootstrap_approval_verifier_receipt(
            captured["activation-receipt.json"],
            captured["approval-set.json"],
            tuple(
                captured[f"receipts/{task_id.lower()}-receipt.json"]
                for task_id in _D0_TASK_IDS
            ),
            captured["required-test-set.json"],
            captured["authority-policy.json"],
            phase5_snapshot,
            captured["eligible-stage0-handoff.json"],
        )
    )

    signers = kwargs["signers"]

    def signer_pair(key_ids: Tuple[str, ...]) -> Tuple[Tuple[str, bytes], ...]:
        pairs = []
        for key_id in key_ids:
            seed = signers.get(key_id) if type(signers) is dict else None
            if type(seed) is not bytes or len(seed) != 32:
                _unverified("signing material is unavailable for a rule signer")
            pairs.append((key_id, seed))
        return tuple(pairs)

    # Revocation: parse captured records, derive the revoked set, sign snapshot.
    revocation_record_bytes = tuple(
        payload
        for relative, payload in sorted(captured.items())
        if relative.startswith("revocation/")
    )
    revoked_ids = set()
    for record_bytes in revocation_record_bytes:
        record = _REVOCATION.parse_revocation_record(record_bytes)
        revoked_ids.add(record.evidenceId)
    revocation_bytes = _REVOCATION.produce_revocation_ledger_snapshot(
        id="s4-fixture-revocation-ledger",
        version="1.0.0",
        policy_bytes=captured["authority-policy.json"],
        record_bytes=revocation_record_bytes,
        signers=signer_pair(("key-release", "key-security")),
    )

    # Freshness: sign the authority snapshot and judge the window at produce time.
    freshness_bytes = _FORMAL_INPUTS.produce_freshness_authority_snapshot(
        id="s4-fixture-freshness-authority",
        version="1.0.0",
        authority_policy_bytes=captured["authority-policy.json"],
        observed_at=kwargs["observed_at"],
        maximum_age_seconds=kwargs["maximum_age_seconds"],
        clock_source_bytes=kwargs["clock_source_bytes"],
        signers=signer_pair(("key-quality", "key-release")),
    )
    expires_at = _FORMAL_INPUTS.freshness_expires_at(
        kwargs["observed_at"], kwargs["maximum_age_seconds"]
    )
    _FORMAL_INPUTS.require_freshness_window(
        kwargs["observed_at"],
        kwargs["maximum_age_seconds"],
        expires_at,
        kwargs["finalized_at"],
    )

    # Containment: sign the caller-supplied observation receipt.
    observation = kwargs["containment_observation"]
    containment_bytes = _FORMAL_INPUTS.produce_session_containment_receipt(
        id="s4-fixture-session-containment",
        version="1.0.0",
        candidate={
            "commit": candidate.commit,
            "treeObjectId": candidate.treeObjectId,
            "archiveDigest": "sha256:" + candidate.archiveDigest.bytes.hex(),
            "digest": "sha256:" + candidate.digest.bytes.hex(),
        },
        stage0_handoff={
            "schema": handoff_ref.schema,
            "id": handoff_ref.id,
            "version": handoff_ref.version,
            "digest": "sha256:" + handoff_ref.digest.bytes.hex(),
        },
        supervisor_digest=observation["supervisor_digest"],
        root_session_id=observation["root_session_id"],
        descendants=observation["descendants"],
        escape_probes=observation["escape_probes"],
        started_at=observation["started_at"],
        finished_at=observation["finished_at"],
        result="contained",
        authority_policy_bytes=captured["authority-policy.json"],
        signers=signer_pair(("key-quality", "key-security")),
    )

    # Finalizer identity: the caller-declared fixture executable bytes.
    executable_digest = hashlib.sha256(
        kwargs["finalizer_executable_bytes"]
    ).hexdigest()
    if executable_digest != handoff.tcb.formalFinalizerDigest.bytes.hex():
        _unverified("finalizer executable digest does not match the handoff tcb")
    finalizer_bytes = _FORMAL_INPUTS.produce_formal_finalizer_identity(
        id=kwargs["finalizer_identity_id"],
        version="1.0.0",
        executable_digest="sha256:" + executable_digest,
        closure_digest=kwargs["finalizer_closure_digest"],
        toolchain_lock_digest=kwargs["finalizer_toolchain_lock_digest"],
    )

    # EV content resolution against the declared gate inputs.
    evidence_map = {
        relative[len("evidence/"):-len(".json")]: payload
        for relative, payload in captured.items()
        if relative.startswith("evidence/") and relative.endswith(".json")
    }
    gate_inputs = kwargs["gate_inputs"]
    catalog_gates = catalog_wire["gates"]
    gates_typed = []
    member_specs = []
    declared_members: dict = {}
    scanned_refs = []
    referenced_evidence = set()
    for row in catalog_gates:
        gate_id = row.get("id")
        task_id = row.get("taskId")
        test_ids = row.get("testIds")
        if type(gate_id) is not str or type(task_id) is not str:
            _unverified("catalog gate rows must carry id/taskId")
        claim = gate_inputs.get(gate_id) if type(gate_inputs) is dict else None
        if claim is None:
            _unverified(f"gate {gate_id} lacks declared evidence inputs")
        build_wire = claim.get("build")
        if build_wire is None and task_id not in _D0_GATE_TASK_IDS:
            _unverified(f"gate {gate_id} build must be non-null for a non-D0 gate")
        declared_refs = claim.get("evidenceRefs")
        if type(declared_refs) is not list or not declared_refs:
            _unverified(f"gate {gate_id} evidenceRefs must be non-empty")
        resolved_refs = []
        for declared in declared_refs:
            evidence_id = declared.get("id")
            evidence_bytes = evidence_map.get(evidence_id)
            if evidence_bytes is None:
                _unverified(f"gate evidenceRef {evidence_id} missing from bundle")
            actual_digest = hashlib.sha256(evidence_bytes).hexdigest()
            if declared.get("digest") != "sha256:" + actual_digest:
                _unverified(f"evidence {evidence_id} digest mismatch")
            try:
                document = _EV_CORE.validate_evidence(
                    _EV_CORE.decode_json(evidence_bytes)
                )
            except _EV_CORE.EvidenceError:
                _unverified(f"evidence {evidence_id} is not a valid EV document")
            if document["result"] != "passed":
                _unverified(f"evidence {evidence_id} is not passed")
            gate = document["gate"]
            expected_qualification = (
                "development" if task_id in _D0_GATE_TASK_IDS else "formal"
            )
            if gate["qualification"] != expected_qualification:
                _unverified(
                    f"evidence {evidence_id} qualification is not "
                    f"{expected_qualification}"
                )
            if gate["id"] != gate_id or gate["taskId"] != task_id:
                _unverified(f"evidence {evidence_id} gate does not match the catalog")
            if tuple(gate["testIds"]) != tuple(sorted(test_ids)):
                _unverified(f"evidence {evidence_id} testIds do not match the gate")
            repository = document["repository"]
            if (repository["commit"] != candidate.commit
                    or repository["treeObjectId"] != candidate.treeObjectId):
                _unverified(f"evidence {evidence_id} candidate does not match")
            if repository["archive"]["sha256"] != (
                candidate.archiveDigest.bytes.hex()
            ):
                _unverified(f"evidence {evidence_id} archive digest does not match")
            if build_wire is not None and not any(
                artifact.get("target") == build_wire["targetId"]
                for artifact in document["artifacts"]
            ):
                _unverified(
                    f"evidence {evidence_id} lacks the gate build target artifact"
                )
            if evidence_id in revoked_ids:
                _unverified(f"evidence {evidence_id} is revoked by the ledger")
            if "gateCatalog" in document:
                catalog_binding = document["gateCatalog"]
                if catalog_binding.get("catalogDigest") != (
                    catalog_ref.catalogDigest
                ):
                    _unverified(
                        f"evidence {evidence_id} catalog binding does not match"
                    )
            resolved_refs.append((evidence_id, bytes.fromhex(actual_digest)))
            referenced_evidence.add(evidence_id)
            ref_wire = {"id": evidence_id, "digest": "sha256:" + actual_digest}
            scanned_refs.append(ref_wire)
            for entry in document["inputs"]:
                member_specs.append(
                    {"evidence": ref_wire, "role": entry["role"], "path": entry["path"]}
                )
                declared_members[entry["path"]] = (
                    entry["sha256"],
                    entry["size"],
                )
            for entry in document["artifacts"]:
                if entry.get("retained") is True:
                    member_specs.append(
                        {
                            "evidence": ref_wire,
                            "role": entry["role"],
                            "path": entry["path"],
                        }
                    )
                    declared_members[entry["path"]] = (
                        entry["sha256"],
                        entry["size"],
                    )
            for entry in document["logs"]:
                member_specs.append(
                    {"evidence": ref_wire, "role": "log", "path": entry["path"]}
                )
                declared_members[entry["path"]] = (
                    entry["sha256"],
                    entry["size"],
                )
        resolved_refs.sort()
        gates_typed.append(
            _FORMAL_PRODUCER.FormalGateV1(
                gate_id,
                tuple(sorted(test_ids)),
                (
                    None
                    if build_wire is None
                    else _FORMAL_PRODUCER.BuildIdentityV1(
                        build_wire["targetId"],
                        build_wire["targetSemanticsVersion"],
                        Digest(
                            "sha256",
                            bytes.fromhex(
                                build_wire["targetSemanticsDigest"][7:]
                            ),
                        ),
                        build_wire["codegenProfileId"],
                        Digest(
                            "sha256",
                            bytes.fromhex(
                                build_wire["codegenProfileDigest"][7:]
                            ),
                        ),
                    )
                ),
                tuple(
                    (evidence_id, Digest("sha256", digest_bytes))
                    for evidence_id, digest_bytes in resolved_refs
                ),
            )
        )
    extra_evidence = set(evidence_map) - referenced_evidence
    if extra_evidence:
        _unverified("bundle evidence unreferenced by any gate")

    # Private scan over the declared retained member set (exact-set: any
    # undeclared file under members/ is an orphan failure).
    members_root = fixture_root / "members"
    manifest = {}
    declared_paths = {spec["path"] for spec in member_specs}
    for spec in member_specs:
        manifest[spec["path"]] = str(members_root / spec["path"])
    if members_root.is_dir():
        for path in sorted(members_root.rglob("*")):
            if path.is_dir():
                continue
            relative = path.relative_to(members_root).as_posix()
            if relative not in declared_paths:
                _unverified("bundle member not declared by any evidence")

    def input_ref(key: str, payload: bytes, schema: str):
        identifier, version = _ref_id_version(payload)
        return _content_ref(
            schema, identifier, version, _INPUT_DOMAINS[key], payload
        )

    containment_ref = input_ref(
        "containment",
        containment_bytes,
        "proof-forge.session-containment-receipt.v1",
    )
    freshness_ref = input_ref(
        "freshness",
        freshness_bytes,
        "proof-forge.freshness-authority-snapshot.v1",
    )
    revocation_ref = input_ref(
        "revocation",
        revocation_bytes,
        "proof-forge.revocation-ledger-snapshot.v1",
    )
    finalizer_ref = input_ref(
        "finalizer",
        finalizer_bytes,
        "proof-forge.formal-finalizer-identity.v1",
    )
    approval_id, approval_version = _ref_id_version(
        captured["catalog-approval.json"]
    )
    catalog_approval_ref = _content_ref(
        "proof-forge.formal-gate-catalog-approval.v1",
        approval_id,
        approval_version,
        _CATALOG_APPROVAL_DOMAIN,
        captured["catalog-approval.json"],
    )
    core_object = {
        "candidate": {
            "commit": candidate.commit,
            "treeObjectId": candidate.treeObjectId,
            "archiveDigest": "sha256:" + candidate.archiveDigest.bytes.hex(),
            "digest": "sha256:" + candidate.digest.bytes.hex(),
        },
        "hostProfile": {
            "schema": handoff.hostProfile.schema,
            "id": handoff.hostProfile.id,
            "version": handoff.hostProfile.version,
            "digest": "sha256:" + handoff.hostProfile.digest.bytes.hex(),
        },
        "stage0Handoff": {
            "schema": handoff_ref.schema,
            "id": handoff_ref.id,
            "version": handoff_ref.version,
            "digest": "sha256:" + handoff_ref.digest.bytes.hex(),
        },
        "sessionContainment": {
            "schema": containment_ref.schema,
            "id": containment_ref.id,
            "version": containment_ref.version,
            "digest": "sha256:" + containment_ref.digest.bytes.hex(),
        },
        "requiredTestSet": {
            "schema": required_ref.schema,
            "id": required_ref.id,
            "version": required_ref.version,
            "digest": "sha256:" + required_ref.digest.bytes.hex(),
        },
        "catalog": {
            "schema": catalog_ref.schema,
            "id": catalog_ref.id,
            "version": catalog_ref.version,
            "contentSha256": catalog_ref.contentSha256,
            "catalogDigest": catalog_ref.catalogDigest,
        },
        "catalogApproval": {
            "schema": catalog_approval_ref.schema,
            "id": catalog_approval_ref.id,
            "version": catalog_approval_ref.version,
            "digest": "sha256:" + catalog_approval_ref.digest.bytes.hex(),
        },
        "gates": None,
        "freshnessAuthority": {
            "schema": freshness_ref.schema,
            "id": freshness_ref.id,
            "version": freshness_ref.version,
            "digest": "sha256:" + freshness_ref.digest.bytes.hex(),
        },
        "revocationLedger": {
            "schema": revocation_ref.schema,
            "id": revocation_ref.id,
            "version": revocation_ref.version,
            "digest": "sha256:" + revocation_ref.digest.bytes.hex(),
        },
        "finalizer": {
            "schema": finalizer_ref.schema,
            "id": finalizer_ref.id,
            "version": finalizer_ref.version,
            "digest": "sha256:" + finalizer_ref.digest.bytes.hex(),
        },
        "bootstrapApproval": {
            "set": {
                "schema": set_ref.schema,
                "id": set_ref.id,
                "version": set_ref.version,
                "digest": "sha256:" + set_ref.digest.bytes.hex(),
            },
            "verifierReceipt": {
                "id": verifier_receipt.id,
                "digest": "sha256:" + verifier_ref.digest.bytes.hex(),
            },
        },
    }

    gate_wires = []
    for gate in gates_typed:
        wire = {
            "id": gate.id,
            "testIds": list(gate.testIds),
            "build": (
                None
                if gate.build is None
                else {
                    "targetId": gate.build.targetId,
                    "targetSemanticsVersion": gate.build.targetSemanticsVersion,
                    "targetSemanticsDigest": "sha256:"
                    + gate.build.targetSemanticsDigest.bytes.hex(),
                    "codegenProfileId": gate.build.codegenProfileId,
                    "codegenProfileDigest": "sha256:"
                    + gate.build.codegenProfileDigest.bytes.hex(),
                }
            ),
            "evidenceRefs": [
                {"id": evidence_id, "digest": "sha256:" + digest.bytes.hex()}
                for evidence_id, digest in gate.evidenceRefs
            ],
        }
        gate_wires.append(wire)
    core_object["gates"] = gate_wires
    core_digest = hashlib.sha256(
        b"pf.formal-evidence-core.v1\x00"
        + _CONSUMER.canonical_pf_jcs(core_object)
    ).digest()

    scan_bytes = _PRIVATE_SCAN.produce_private_scan_receipt(
        id="s4-fixture-private-scan",
        version="1.0.0",
        candidate=core_object["candidate"],
        evidence_core_digest="sha256:" + core_digest.hex(),
        scanner_executable_bytes=kwargs["finalizer_executable_bytes"],
        authority_policy_bytes=captured["authority-policy.json"],
        scan_policy_bytes=kwargs["scan_policy_bytes"],
        scanned_evidence_refs=tuple(
            sorted(scanned_refs, key=lambda item: (item["id"], item["digest"]))
        ),
        member_specs=tuple(member_specs),
        manifest=manifest,
        signers=signer_pair(("key-quality", "key-security")),
        policy_ref={
            "schema": policy.privateScanPolicy.schema,
            "id": policy.privateScanPolicy.id,
            "version": policy.privateScanPolicy.version,
            "digest": "sha256:" + policy.privateScanPolicy.digest.bytes.hex(),
        },
    )
    scan_ref = input_ref(
        "privateScan", scan_bytes, "proof-forge.private-scan-receipt.v1"
    )
    # Member honesty: the signed receipt's recomputed member facts must equal
    # every resolved EV's declared retained-member facts (no drift between
    # the evidence claims and the captured bundle bytes).
    receipt_wire = _CONSUMER.decode_canonical_pf_jcs(scan_bytes)
    for member in receipt_wire["scannedMembers"]:
        declared = declared_members.get(member["path"])
        if declared is None:
            _unverified("scanned member is not declared by any evidence")
        declared_sha256, declared_size = declared
        if member["digest"] != "sha256:" + declared_sha256:
            _unverified("member bytes drift vs EV declaration")
        if member["size"] != declared_size:
            _unverified("member size drift vs EV declaration")

    inputs = _FORMAL_PRODUCER.FormalRecordInputsV1(
        record_bytes=b"",
        authority_policy_bytes=captured["authority-policy.json"],
        required_test_set_bytes=captured["required-test-set.json"],
        phase5_snapshot=phase5_snapshot,
        catalog_bytes=captured["catalog.json"],
        catalog_approval_bytes=captured["catalog-approval.json"],
        session_containment_bytes=containment_bytes,
        freshness_authority_bytes=freshness_bytes,
        private_scan_bytes=scan_bytes,
        revocation_ledger_bytes=revocation_bytes,
        revocation_record_bytes=revocation_record_bytes,
        finalizer_identity_bytes=finalizer_bytes,
        approval_set_bytes=captured["approval-set.json"],
        task_receipt_bytes=tuple(
            captured[f"receipts/{task_id.lower()}-receipt.json"]
            for task_id in _D0_TASK_IDS
        ),
        verifier_receipt_bytes=captured["activation-receipt.json"],
        stage0_handoff_bytes=captured["eligible-stage0-handoff.json"],
    )
    record_bytes, record_ref = _FORMAL_PRODUCER.produce_formal_evidence_finalization(
        identifier=kwargs["record_id"],
        candidate=candidate,
        hostProfile=handoff.hostProfile,
        stage0Handoff=handoff_ref,
        sessionContainment=containment_ref,
        requiredTestSet=required_ref,
        catalog=catalog_ref,
        catalogApproval=catalog_approval_ref,
        gates=tuple(gates_typed),
        freshnessAuthority=freshness_ref,
        finalizedAt=kwargs["finalized_at"],
        expiresAt=expires_at,
        privateScan=scan_ref,
        revocationLedger=revocation_ref,
        finalizer=finalizer_ref,
        bootstrapApproval=_FORMAL_PRODUCER.BootstrapApprovalBindingV1(
            set_ref,
            _CONSUMER.BootstrapApprovalVerifierReceiptRefV1(
                verifier_receipt.id, verifier_ref.digest
            ),
        ),
        inputs=inputs,
    )

    support = kwargs["support"]
    evidence_id = support["evidence_id"]
    evidence_bytes = evidence_map.get(evidence_id)
    if evidence_bytes is None:
        _unverified("support binding evidence is not in the bundle")
    binding_inputs = _FORMAL_PRODUCER.FormalRecordInputsV1(
        record_bytes=record_bytes,
        authority_policy_bytes=inputs.authority_policy_bytes,
        required_test_set_bytes=inputs.required_test_set_bytes,
        phase5_snapshot=phase5_snapshot,
        catalog_bytes=inputs.catalog_bytes,
        catalog_approval_bytes=inputs.catalog_approval_bytes,
        session_containment_bytes=inputs.session_containment_bytes,
        freshness_authority_bytes=inputs.freshness_authority_bytes,
        private_scan_bytes=inputs.private_scan_bytes,
        revocation_ledger_bytes=inputs.revocation_ledger_bytes,
        revocation_record_bytes=inputs.revocation_record_bytes,
        finalizer_identity_bytes=inputs.finalizer_identity_bytes,
        approval_set_bytes=inputs.approval_set_bytes,
        task_receipt_bytes=inputs.task_receipt_bytes,
        verifier_receipt_bytes=inputs.verifier_receipt_bytes,
        stage0_handoff_bytes=inputs.stage0_handoff_bytes,
    )
    build_wire = support["build"]
    gate_vectors = []
    ref_tuple_by_id = {}
    for gate in gates_typed:
        for evidence_ref_id, evidence_ref_digest in gate.evidenceRefs:
            ref_tuple_by_id[evidence_ref_id] = (
                evidence_ref_id,
                evidence_ref_digest,
            )
    for vector in support["gate_vectors"]:
        evidence_ref = ref_tuple_by_id.get(vector["evidenceId"])
        if evidence_ref is None:
            _unverified("support gate vector references unknown evidence")
        gate_vectors.append(
            _FORMAL_PRODUCER.GateVectorV1(
                vector["gateId"], evidence_ref, vector["grade"]
            )
        )
    binding_bytes, binding_ref = _FORMAL_PRODUCER.produce_support_binding(
        evidence_bytes=evidence_bytes,
        evidence_id=evidence_id,
        record_inputs=binding_inputs,
        build=_FORMAL_PRODUCER.BuildIdentityV1(
            build_wire["targetId"],
            build_wire["targetSemanticsVersion"],
            Digest(
                "sha256",
                bytes.fromhex(build_wire["targetSemanticsDigest"][7:]),
            ),
            build_wire["codegenProfileId"],
            Digest(
                "sha256",
                bytes.fromhex(build_wire["codegenProfileDigest"][7:]),
            ),
        ),
        support_claim=support["support_claim"],
        gate_vectors=tuple(gate_vectors),
    )

    record_path = _FORMAL_PRODUCER.publish_finalization(
        record_bytes,
        record_ref,
        trusted_root,
        captured["required-test-set.json"],
        captured["authority-policy.json"],
    )
    published.append(record_path)
    published.append(record_path[: -len(".json")] + ".receipt.json")
    binding_path = _FORMAL_PRODUCER.publish_support_binding(
        binding_bytes, binding_ref, trusted_root
    )
    published.append(binding_path)
    published.append(binding_path[: -len(".json")] + ".receipt.json")

    # End-to-end: the published record re-verifies against the captured inputs.
    published_record = _safe_read_once(Path(record_path), "published record")
    _FORMAL.parse_formal_evidence_finalization(
        published_record,
        inputs.authority_policy_bytes,
        inputs.required_test_set_bytes,
        phase5_snapshot,
        inputs.catalog_bytes,
        inputs.catalog_approval_bytes,
        inputs.session_containment_bytes,
        inputs.freshness_authority_bytes,
        inputs.private_scan_bytes,
        inputs.revocation_ledger_bytes,
        inputs.revocation_record_bytes,
        inputs.finalizer_identity_bytes,
        inputs.approval_set_bytes,
        inputs.task_receipt_bytes,
        inputs.verifier_receipt_bytes,
        inputs.stage0_handoff_bytes,
    )

    return FinalizeOutcome(
        recordBytes=record_bytes,
        recordPath=record_path,
        bindingBytes=binding_bytes,
        bindingPath=binding_path,
        expiresAt=expires_at,
        containmentBytes=containment_bytes,
        freshnessBytes=freshness_bytes,
        privateScanBytes=scan_bytes,
        revocationLedgerBytes=revocation_bytes,
        revocationRecordBytes=revocation_record_bytes,
        finalizerIdentityBytes=finalizer_bytes,
    )
