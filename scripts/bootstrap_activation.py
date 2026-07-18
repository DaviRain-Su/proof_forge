#!/usr/bin/env python3
"""Real-activation driver skeleton (development slice).

Drives the acceptance rehearsal steps against production-shaped inputs:
a signed authority policy, a candidate identity, and an ``--approvals-dir``
of objects produced offline by ``bootstrap_sign_tool.py`` (this driver never
takes signing material and never signs anything itself).

CLI:
``--policy <signed-policy.json> --candidate <candidate.json> --workdir <dir>
[--handoff <handoff.json>] [--store-socket <path>] [--dry-run]
[--approvals-dir <dir>]``

Workdir file conventions (development-slice stand-ins for the future
Stage-0/fd handoff): ``service-descriptor.json`` (descriptor wire whose
recomputed ContentRef must exactly equal ``policy.authorityStoreService``),
``service-seed.hex`` (embedded-store operational key), and
``phase5-snapshot.json`` (``{id,path,bytesHex}``).  Without ``--handoff`` a
non-dry-run also needs ``host-observation.json``, ``host-profile.json``,
``tcb.json`` (the three non-policy digests), ``candidate-archive.tar`` and
``evidence-root-manifest.json``; the handoff is then produced in-process and
eligibility fails closed with ``PF-BOOTSTRAP-ACTIVATION-HOST`` whenever the
observation does not prove an eligible host (no downgrade, no fabrication).

Modes: ``--dry-run`` verifies everything verifiable, backfills the store and
prints ``gap:`` lines for what remains (handoff-dependent verification when
no handoff is available, and the activation publish itself).  A full run is
two phases: without ``--handoff`` it issues the handoff from the workdir
inputs (eligible observation required; otherwise it fails closed with
``PF-BOOTSTRAP-ACTIVATION-HOST`` — no downgrade, no fabrication) and writes
``eligible-stage0-handoff.json`` no-clobber for the subsequent offline
signing ceremony; with ``--handoff`` it verifies the whole chain, backfills
D0-01..06 in exact topological order, publishes the six-item set and the
activation receipt through the store client, and re-verifies the activation.
A handoff file carries fd numbers that only its producer process can
inherit, so contained-execution activation stays with the rehearsal proof
and this driver publishes through the store client directly.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import secrets
import stat
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Dict, NoReturn, Optional, Tuple


def _load_bootstrap_acceptance() -> ModuleType:
    """Load the exact sibling acceptance module without a sys.path seam."""
    driver_path = Path(__file__).resolve(strict=True)
    acceptance_path = driver_path.with_name("bootstrap_acceptance.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_acceptance_for_activation",
        acceptance_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact bootstrap acceptance loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != acceptance_path.resolve(strict=True):
        raise ImportError("exact bootstrap acceptance origin changed")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    for name in (
        "produce_run_handoff",
        "close_task",
        "collect_activation_inputs",
        "rehearsal_child_main",
        "RehearsalBase",
    ):
        if getattr(module, name, None) is None:
            raise ImportError("exact bootstrap acceptance ABI changed")
    return module


_ACCEPTANCE = _load_bootstrap_acceptance()
_STORE = _ACCEPTANCE._STORE
_CONSUMER = _ACCEPTANCE._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef

D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
_TOPOLOGICAL_TASK_IDS = (
    "TASK-D0-01",
    "TASK-D0-02",
    "TASK-D0-03",
    "TASK-D0-05",
    "TASK-D0-06",
    "TASK-D0-04",
)
_OBSERVATION_REF_ID = "host-observation"
_PROFILE_REF_ID = "host-profile"
_REF_VERSION = "1.0.0"


class ActivationError(Exception):
    """Stable driver failure."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise ActivationError(code, detail)


def _schema(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACTIVATION-SCHEMA", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACTIVATION-IO", detail)


def _object(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACTIVATION-OBJECT", detail)


def _store(detail: str) -> NoReturn:
    _fail("PF-BOOTSTRAP-ACTIVATION-STORE", detail)


@dataclass(frozen=True)
class DriverRun:
    handoffBytes: bytes
    approvalBytes: Dict[str, bytes]
    receiptBytes: Dict[str, bytes]
    setBytes: bytes


def _read_file(path: str, where: str, maximum: int = 16 * 1024 * 1024) -> bytes:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        _io(f"cannot open {where}: {error}")
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            _io(f"{where} is not a regular file")
        chunks = []
        offset = 0
        while True:
            chunk = os.pread(fd, 65536, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
            if offset > maximum:
                _io(f"{where} exceeds the input maximum")
        return b"".join(chunks)
    finally:
        os.close(fd)


def _consumer_checked(validation, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _object(detail)


def _read_json_object(path: str, where: str) -> dict:
    raw = _read_file(path, where)
    try:
        parsed = json.loads(raw.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _schema(f"{where} is not valid JSON")
    if type(parsed) is not dict:
        _schema(f"{where} must be a JSON object")
    assert isinstance(parsed, dict)
    return parsed


def _read_seed_hex(path: str) -> bytes:
    raw = _read_file(path, "service seed", maximum=66)
    text = raw[:-1] if raw.endswith(b"\n") else raw
    if len(text) != 64 or any(
        character not in b"0123456789abcdef" for character in text
    ):
        _schema("service seed must be 64 lowercase hex characters")
    return bytes.fromhex(text.decode("ascii"))


def _load_policy(path: str) -> Tuple[bytes, object, ContentRef]:
    policy_bytes = _read_file(path, "authority policy")
    policy, policy_ref = _consumer_checked(
        lambda: _CONSUMER.parse_bootstrap_authority_policy(policy_bytes),
        "authority policy is not a valid signed policy",
    )
    return policy_bytes, policy, policy_ref


def _load_candidate(path: str) -> object:
    raw = _read_file(path, "candidate identity")
    try:
        wire = json.loads(raw.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _schema("candidate identity is not valid JSON")
    return _consumer_checked(
        lambda: _CONSUMER.parse_candidate_identity(wire),
        "candidate identity is not valid",
    )


def _load_snapshot(workdir: str) -> object:
    wire = _read_json_object(
        os.path.join(workdir, "phase5-snapshot.json"), "phase5 snapshot"
    )
    if set(wire.keys()) != {"id", "path", "bytesHex"}:
        _schema("phase5 snapshot must contain exactly id/path/bytesHex")
    try:
        snapshot_bytes = bytes.fromhex(wire["bytesHex"])
    except (TypeError, ValueError):
        _schema("phase5 snapshot bytesHex must be hex")
    return _CONSUMER.BootstrapDocumentSnapshotV1(
        id=wire["id"], path=wire["path"], bytes=snapshot_bytes
    )


def _load_descriptor(workdir: str, policy: object) -> Tuple[dict, ContentRef]:
    wire = _read_json_object(
        os.path.join(workdir, "service-descriptor.json"), "service descriptor"
    )
    descriptor_ref = _consumer_checked(
        lambda: _STORE.descriptor_content_ref(wire),
        "service descriptor is not a valid descriptor",
    )
    if descriptor_ref != policy.authorityStoreService:
        _schema(
            "service descriptor ref does not equal policy.authorityStoreService"
        )
    return wire, descriptor_ref


def _load_handoff(handoff_path: Optional[str]) -> Optional[bytes]:
    if handoff_path is None:
        return None
    handoff_bytes = _read_file(handoff_path, "stage0 handoff")
    _consumer_checked(
        lambda: _CONSUMER._preflight_eligible_stage0_handoff(handoff_bytes),
        "stage0 handoff bytes are not a valid eligible handoff",
    )
    return handoff_bytes


def _preflight_handoff_run(handoff_bytes: bytes) -> Tuple[str, str]:
    handoff = _consumer_checked(
        lambda: _CONSUMER._preflight_eligible_stage0_handoff(handoff_bytes),
        "stage0 handoff bytes are not a valid eligible handoff",
    ).handoff
    return handoff.runId, handoff.nonce.hex()


def _approvals_path(approvals_dir: str, name: str) -> Optional[bytes]:
    path = os.path.join(approvals_dir, name)
    if not os.path.isfile(path):
        return None
    return _read_file(path, f"approvals/{name}")


def _load_chain(
    policy_bytes: bytes,
    snapshot: object,
    handoff_bytes: Optional[bytes],
    approvals_dir: str,
    gaps: list,
) -> Tuple[bytes, ContentRef, Dict[str, bytes], Dict[str, bytes],
           Optional[bytes], Optional[bytes], Optional[bytes]]:
    required_bytes = _approvals_path(approvals_dir, "required-test-set.json")
    if required_bytes is None:
        _schema("approvals dir lacks required-test-set.json")
    assert required_bytes is not None
    _, required_ref = _consumer_checked(
        lambda: _CONSUMER.parse_document_bound_required_test_set(
            required_bytes, policy_bytes, snapshot
        ),
        "required test set failed document-bound verification",
    )
    catalog_approval_bytes = _approvals_path(
        approvals_dir, "catalog-approval.json"
    )
    catalog_bytes = _approvals_path(approvals_dir, "catalog.json")
    if catalog_approval_bytes is not None:
        if catalog_bytes is None:
            _schema("catalog-approval.json requires catalog.json")
        _consumer_checked(
            lambda: _CONSUMER.parse_formal_gate_catalog_approval(
                catalog_approval_bytes, catalog_bytes, required_bytes,
                policy_bytes,
            ),
            "formal catalog approval failed verification",
        )
    approval_bytes: Dict[str, bytes] = {}
    receipt_bytes: Dict[str, bytes] = {}
    for task_id in _TOPOLOGICAL_TASK_IDS:
        approval = _approvals_path(
            approvals_dir, f"{task_id.lower()}-approval.json"
        )
        receipt = _approvals_path(
            approvals_dir, f"{task_id.lower()}-receipt.json"
        )
        if approval is None or receipt is None:
            gaps.append(f"{task_id} approval/receipt pair missing")
            continue
        _consumer_checked(
            lambda approval=approval: _CONSUMER.parse_task_approval(
                approval, required_bytes, policy_bytes, snapshot
            ),
            f"{task_id} approval failed verification",
        )
        if handoff_bytes is not None:
            _consumer_checked(
                lambda approval=approval, receipt=receipt: (
                    _CONSUMER.parse_bootstrap_task_verifier_receipt(
                        receipt, approval, required_bytes, policy_bytes,
                        snapshot, handoff_bytes,
                    )
                ),
                f"{task_id} receipt failed verification",
            )
        approval_bytes[task_id] = approval
        receipt_bytes[task_id] = receipt
    set_bytes = _approvals_path(approvals_dir, "approval-set.json")
    activation_bytes = _approvals_path(approvals_dir, "activation-receipt.json")
    if set_bytes is None:
        gaps.append("approval-set.json missing")
    if activation_bytes is None:
        gaps.append("activation-receipt.json missing")
    if handoff_bytes is None:
        gaps.append(
            "stage0 handoff missing: receipt/set/activation verification "
            "deferred"
        )
    else:
        if set_bytes is not None and len(receipt_bytes) == 6:
            _consumer_checked(
                lambda: _CONSUMER.parse_bootstrap_approval_set(
                    set_bytes,
                    tuple(receipt_bytes[task_id] for task_id in D0_TASK_IDS),
                    required_bytes,
                    policy_bytes,
                    snapshot,
                    handoff_bytes,
                ),
                "approval set failed verification",
            )
        if activation_bytes is not None and set_bytes is not None and len(
            receipt_bytes
        ) == 6:
            _consumer_checked(
                lambda: _CONSUMER.parse_bootstrap_approval_verifier_receipt(
                    activation_bytes,
                    set_bytes,
                    tuple(
                        receipt_bytes[task_id] for task_id in D0_TASK_IDS
                    ),
                    required_bytes,
                    policy_bytes,
                    snapshot,
                    handoff_bytes,
                ),
                "activation receipt failed verification",
            )
    return (
        required_bytes,
        required_ref,
        approval_bytes,
        receipt_bytes,
        set_bytes,
        activation_bytes,
        catalog_approval_bytes,
    )


def _start_embedded_store(
    workdir: str,
    policy_bytes: bytes,
    descriptor_wire: dict,
    run_id: str,
    nonce: str,
):
    service_seed = _read_seed_hex(os.path.join(workdir, "service-seed.hex"))
    try:
        server = _STORE.AuthorityStoreServer(
            policy_bytes=policy_bytes,
            service_seed=service_seed,
            descriptor_id=descriptor_wire["id"],
            descriptor_version=descriptor_wire["version"],
            service_executable_digest=_CONSUMER.parse_digest(
                descriptor_wire["serviceExecutableDigest"]
            ),
            namespace_id=descriptor_wire["namespaceId"],
            expected_run_id=run_id,
            expected_nonce=nonce,
            io_timeout_seconds=30.0,
        )
        socket_path = os.path.join(workdir, "authority-store.sock")
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
        return server.serve_unix(socket_path), socket_path
    except _STORE.AuthorityStoreError as error:
        _store(f"embedded authority store failed to start: {error.code}")


def _connect_client(
    descriptor_ref: ContentRef,
    run_id: str,
    nonce: str,
    socket_path: str,
):
    try:
        client = _STORE.AuthorityStoreClient(
            descriptor_ref, run_id, nonce, io_timeout_seconds=30.0
        )
        client.connect(socket_path)
        return client
    except _STORE.AuthorityStoreError as error:
        _store(f"authority store connect failed: {error.code}")


def _backfill(
    client,
    required_bytes: bytes,
    catalog_approval_bytes: Optional[bytes],
    approval_bytes: Dict[str, bytes],
    receipt_bytes: Dict[str, bytes],
    set_bytes: Optional[bytes],
    base,
    run,
) -> None:
    try:
        client.publish_with_readback(
            _STORE.REQUIRED_TEST_SET_SCHEMA, required_bytes
        )
        if catalog_approval_bytes is not None:
            client.publish_with_readback(
                _STORE.FORMAL_CATALOG_APPROVAL_SCHEMA, catalog_approval_bytes
            )
        for task_id in _TOPOLOGICAL_TASK_IDS:
            if task_id not in approval_bytes:
                continue
            client.publish_with_readback(
                _STORE.TASK_APPROVAL_SCHEMA, approval_bytes[task_id]
            )
            client.publish_with_readback(
                _STORE.TASK_RECEIPT_SCHEMA, receipt_bytes[task_id]
            )
            if run.handoffBytes:
                _ACCEPTANCE.close_task(base, run, client, task_id)
        if set_bytes is not None:
            client.publish_with_readback(_STORE.APPROVAL_SET_SCHEMA, set_bytes)
            _ACCEPTANCE.collect_activation_inputs(base, run, client)
    except _STORE.AuthorityStoreError as error:
        _store(f"authority store backfill failed: {error.code}")
    except _ACCEPTANCE.BootstrapAcceptanceError as error:
        _store(f"authority closure failed: {error.code}")


def _build_base_core(
    policy_bytes: bytes,
    policy_ref: ContentRef,
    required_bytes: bytes,
    required_ref: ContentRef,
    snapshot: object,
    candidate: object,
    descriptor_wire: dict,
    descriptor_ref: ContentRef,
) -> object:
    """Core rehearsal context for closure helpers.

    Only policyBytes/policyRef/requiredBytes/requiredRef/phase5Snapshot and
    the candidate fields are read by close_task/collect_activation_inputs;
    the remaining fields are typed placeholders by construction.
    """
    return _ACCEPTANCE.RehearsalBase(
        policyBytes=policy_bytes,
        policyRef=policy_ref,
        requiredBytes=required_bytes,
        requiredRef=required_ref,
        phase5Snapshot=snapshot,
        catalogBytes=b"",
        catalogApprovalBytes=b"",
        candidate=candidate,
        candidateCommit=candidate.commit,
        candidateTreeObjectId=candidate.treeObjectId,
        candidateArchiveDigestBytes=candidate.archiveDigest.bytes,
        candidateDigestBytes=candidate.digest.bytes,
        archiveBytes=b"",
        manifestBytes=b"",
        descriptorWire=descriptor_wire,
        descriptorRef=descriptor_ref,
        descriptorDigestBytes=descriptor_ref.digest.bytes,
        serviceSeed=b"\x00" * 32,
        observationId=_OBSERVATION_REF_ID,
        observationVersion=_REF_VERSION,
        observationBytes=b"",
        profileId=_PROFILE_REF_ID,
        profileVersion=_REF_VERSION,
        profileBytes=b"",
        tcbDigests=(bytes(32), bytes(32), bytes(32), bytes(32)),
    )


def _build_base_for_handoff(
    policy_bytes: bytes,
    policy_ref: ContentRef,
    candidate: object,
    descriptor_wire: dict,
    descriptor_ref: ContentRef,
    workdir: str,
) -> object:
    """Rehearsal context for handoff issuance (phase 1).

    Only the candidate/descriptor/observation/profile/tcb/archive/manifest
    fields are read by produce_run_handoff; the required-set and catalog
    fields are typed placeholders by construction.
    """
    observation_bytes = _read_file(
        os.path.join(workdir, "host-observation.json"), "host observation"
    )
    profile_bytes = _read_file(
        os.path.join(workdir, "host-profile.json"), "host profile"
    )
    tcb_wire = _read_json_object(os.path.join(workdir, "tcb.json"), "tcb digests")
    if set(tcb_wire.keys()) != {
        "stage0VerifierDigest",
        "continuationDigest",
        "formalFinalizerDigest",
    }:
        _schema("tcb.json must contain exactly the three non-policy digests")
    archive_bytes = _read_file(
        os.path.join(workdir, "candidate-archive.tar"), "candidate archive"
    )
    manifest_bytes = _read_file(
        os.path.join(workdir, "evidence-root-manifest.json"),
        "evidence root manifest",
    )
    policy = _CONSUMER.parse_bootstrap_authority_policy(policy_bytes)[0]
    return _ACCEPTANCE.RehearsalBase(
        policyBytes=policy_bytes,
        policyRef=policy_ref,
        requiredBytes=b"",
        requiredRef=ContentRef(
            "proof-forge.required-test-set.v1",
            "driver-placeholder",
            "1.0.0",
            Digest("sha256", bytes(32)),
        ),
        phase5Snapshot=None,
        catalogBytes=b"",
        catalogApprovalBytes=b"",
        candidate=candidate,
        candidateCommit=candidate.commit,
        candidateTreeObjectId=candidate.treeObjectId,
        candidateArchiveDigestBytes=candidate.archiveDigest.bytes,
        candidateDigestBytes=candidate.digest.bytes,
        archiveBytes=archive_bytes,
        manifestBytes=manifest_bytes,
        descriptorWire=descriptor_wire,
        descriptorRef=descriptor_ref,
        descriptorDigestBytes=descriptor_ref.digest.bytes,
        serviceSeed=b"\x00" * 32,
        observationId=_OBSERVATION_REF_ID,
        observationVersion=_REF_VERSION,
        observationBytes=observation_bytes,
        profileId=_PROFILE_REF_ID,
        profileVersion=_REF_VERSION,
        profileBytes=profile_bytes,
        tcbDigests=(
            _CONSUMER.parse_digest(tcb_wire["stage0VerifierDigest"]).bytes,
            policy.verifier.executableDigest.bytes,
            _CONSUMER.parse_digest(tcb_wire["continuationDigest"]).bytes,
            _CONSUMER.parse_digest(tcb_wire["formalFinalizerDigest"]).bytes,
        ),
    )


def run_driver(
    policy_path: str,
    candidate_path: str,
    workdir: str,
    handoff_path: Optional[str],
    store_socket: Optional[str],
    dry_run: bool,
    approvals_dir: Optional[str],
) -> int:
    policy_bytes, policy, policy_ref = _load_policy(policy_path)
    candidate = _load_candidate(candidate_path)
    descriptor_wire, descriptor_ref = _load_descriptor(workdir, policy)
    handoff_bytes = _load_handoff(handoff_path)

    if not dry_run and handoff_bytes is None:
        if store_socket is not None:
            _fail(
                "PF-BOOTSTRAP-ACTIVATION-HOST",
                "external store mode requires an explicit --handoff",
            )
        run_id = "activation-run-" + secrets.token_hex(8)
        nonce = secrets.token_bytes(32).hex()
        try:
            produced_handoff = _ACCEPTANCE.produce_run_handoff(
                _build_base_for_handoff(
                    policy_bytes,
                    policy_ref,
                    candidate,
                    descriptor_wire,
                    descriptor_ref,
                    workdir,
                ),
                handoff_id="activation-stage0-handoff",
                handoff_version="1.0.0",
                run_id=run_id,
                policy_path=policy_path,
                archive_path=os.path.join(workdir, "candidate-archive.tar"),
                manifest_path=os.path.join(
                    workdir, "evidence-root-manifest.json"
                ),
            )
        except _ACCEPTANCE._HANDOFF.Stage0HandoffError as error:
            _fail(
                "PF-BOOTSTRAP-ACTIVATION-HOST",
                f"host is not eligible for a real handoff: {error.code}",
            )
        handoff_output = os.path.join(workdir, "eligible-stage0-handoff.json")
        _write_no_clobber(handoff_output, produced_handoff.handoffBytes)
        for fd in (
            produced_handoff.channels.authorityPolicyFd,
            produced_handoff.channels.authorityStoreFd,
            produced_handoff.channels.candidateArchiveFd,
            produced_handoff.channels.evidenceRootFd,
            produced_handoff.channels.authorityStoreServiceFd,
        ):
            try:
                os.close(fd)
            except OSError:
                pass
        print(
            f"handoff: {produced_handoff.handoffRef.id} "
            f"sha256:{produced_handoff.handoffDigest.bytes.hex()}"
        )
        return 0

    approvals = approvals_dir or os.path.join(workdir, "approvals")
    snapshot = _load_snapshot(workdir)
    gaps: list = []
    (
        required_bytes,
        required_ref,
        approval_bytes,
        receipt_bytes,
        set_bytes,
        activation_bytes,
        catalog_approval_bytes,
    ) = _load_chain(policy_bytes, snapshot, handoff_bytes, approvals, gaps)
    base = _build_base_core(
        policy_bytes,
        policy_ref,
        required_bytes,
        required_ref,
        snapshot,
        candidate,
        descriptor_wire,
        descriptor_ref,
    )

    if dry_run:
        if handoff_bytes is None:
            gaps.append("handoff production skipped (dry-run)")
        gaps.append("activation publish skipped (dry-run)")

    run_id, nonce = (
        _preflight_handoff_run(handoff_bytes)
        if handoff_bytes is not None
        else (
            "activation-run-" + secrets.token_hex(8),
            secrets.token_bytes(32).hex(),
        )
    )
    run = DriverRun(
        handoffBytes=handoff_bytes or b"",
        approvalBytes=approval_bytes,
        receiptBytes=receipt_bytes,
        setBytes=set_bytes or b"",
    )
    handle = None
    client = None
    try:
        if store_socket is not None:
            socket_path = store_socket
        else:
            handle, socket_path = _start_embedded_store(
                workdir, policy_bytes, descriptor_wire, run_id, nonce
            )
        client = _connect_client(descriptor_ref, run_id, nonce, socket_path)
        _backfill(
            client,
            required_bytes,
            catalog_approval_bytes,
            approval_bytes,
            receipt_bytes,
            set_bytes,
            base,
            run,
        )

        if dry_run:
            for gap in gaps:
                print(f"gap: {gap}")
            print("dry-run: backfill verified; handoff/activation deferred")
            return 0

        if activation_bytes is None or set_bytes is None:
            _schema("non-dry-run requires the full approvals chain")
        assert activation_bytes is not None and set_bytes is not None
        try:
            client.publish_with_readback(
                _STORE.VERIFIER_RECEIPT_SCHEMA, activation_bytes
            )
        except _STORE.AuthorityStoreError as error:
            _store(f"activation publish failed: {error.code}")
        receipt, receipt_ref = _consumer_checked(
            lambda: _CONSUMER.parse_bootstrap_approval_verifier_receipt(
                activation_bytes,
                set_bytes,
                tuple(receipt_bytes[task_id] for task_id in D0_TASK_IDS),
                required_bytes,
                policy_bytes,
                snapshot,
                handoff_bytes,
            ),
            "activation receipt failed final verification",
        )
        print(f"activation: {receipt.id} sha256:{receipt_ref.digest.bytes.hex()}")
        return 0
    finally:
        if client is not None:
            client.close()
        if handle is not None:
            handle.stop()


def _write_no_clobber(path: str, payload: bytes) -> None:
    try:
        fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o444,
        )
    except FileExistsError:
        _io("handoff output already exists (no-clobber)")
    except OSError as error:
        _io(f"cannot create the handoff output: {error}")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        _io(f"cannot write the handoff output: {error}")


_USAGE = (
    "usage: bootstrap_activation.py --policy <policy.json> --candidate "
    "<candidate.json> --workdir <dir> [--handoff <handoff.json>] "
    "[--store-socket <path>] [--dry-run] [--approvals-dir <dir>]"
)


def main(argv: Optional[Tuple[str, ...]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    options = {
        "--policy": None,
        "--candidate": None,
        "--workdir": None,
        "--handoff": None,
        "--store-socket": None,
        "--approvals-dir": None,
    }
    dry_run = False
    index = 0
    while index < len(args):
        flag = args[index]
        if flag == "--dry-run":
            if dry_run:
                print(_USAGE, file=sys.stderr)
                return 2
            dry_run = True
            index += 1
            continue
        if flag not in options or index + 1 >= len(args):
            print(_USAGE, file=sys.stderr)
            return 2
        if options[flag] is not None:
            print(_USAGE, file=sys.stderr)
            return 2
        options[flag] = args[index + 1]
        index += 2
    if (options["--policy"] is None or options["--candidate"] is None
            or options["--workdir"] is None):
        print(_USAGE, file=sys.stderr)
        return 2
    try:
        return run_driver(
            options["--policy"],
            options["--candidate"],
            options["--workdir"],
            options["--handoff"],
            options["--store-socket"],
            dry_run,
            options["--approvals-dir"],
        )
    except ActivationError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
