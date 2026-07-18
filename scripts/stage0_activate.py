#!/usr/bin/env python3
"""Stage-0 activation driver (development slice).

Composes the real activation sequence on an eligible host: verify the host
observation proves eligibility, recompute the four TCB digests from real
file bytes, start the authority-store service child whose executable bytes
are pinned by the service descriptor, produce (or consume) the eligible
Stage-0 handoff, backfill the signed chain D0-01..06 in exact topological
order, publish the six-item set and the activation receipt through the
protected store consumer, and finally write the closure bundle.

TCB file selection for this slice (rationale in the module is normative for
the development harness only; D0-07 owns the real semantics):

- ``stage0VerifierDigest``: SHA-256 of ``scripts/verify_host_stage0.sh``
  (the Stage-0 verifier entry that produces the attestation);
- ``bootstrapVerifierDigest``: ``policy.verifier.executableDigest`` from the
  signed policy, cross-asserted against ``workdir/bootstrap-verifier.exe``
  (the deployment-pinned verifier executable bytes);
- ``continuationDigest``: SHA-256 of ``scripts/stage0_containment.py``
  (the deny-default containment runner);
- ``formalFinalizerDigest``: SHA-256 of ``scripts/gate_evidence.py``
  (current finalizer candidate; real finalizer semantics land with D0-07).

The service executable assertion: the descriptor's
``serviceExecutableDigest`` must equal the SHA-256 of
``scripts/stage0_store_service.py``, the exact file spawned as the service
child (either over the handoff socketpair's inherited fd or a workdir Unix
socket).  The service seed is read only by the service child from the
explicit ``workdir/service-seed.hex`` path under the signing-tool custody
discipline; this driver never reads it.  Handoff production consumes an
existing ``workdir/eligible-stage0-handoff.json`` when present (re-verified
against policy/candidate/descriptor and the recomputed TCB) or produces a
fresh one through ``produce_stage0_handoff`` with live channel fds.

Every failure closes with ``PF-STAGE0-ACTIVATE-{INELIGIBLE,TCB,SERVICE,
HANDOFF,BACKFILL,BUNDLE,IO}`` and leaves no bundle behind.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from types import ModuleType
from typing import Dict, NoReturn, Optional, Tuple


def _load_bootstrap_activation() -> ModuleType:
    driver_path = Path(__file__).resolve(strict=True)
    target_path = driver_path.with_name("bootstrap_activation.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_activation_for_stage0_activate",
        target_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact bootstrap activation loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != target_path.resolve(strict=True):
        raise ImportError("exact bootstrap activation origin changed")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    for name in (
        "_load_policy",
        "_load_candidate",
        "_load_snapshot",
        "_load_chain",
        "_build_base_core",
        "_connect_client",
        "DriverRun",
    ):
        if getattr(module, name, None) is None:
            raise ImportError("exact bootstrap activation ABI changed")
    return module


_DRIVER = _load_bootstrap_activation()
_ACCEPTANCE = _DRIVER._ACCEPTANCE
_STORE = _ACCEPTANCE._STORE
_CONSUMER = _ACCEPTANCE._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef
_SCRIPT_DIR = Path(__file__).resolve().parent
_PYTHON = "/usr/bin/python3"
D0_TASK_IDS = tuple(f"TASK-D0-{index:02d}" for index in range(1, 7))
_TOPOLOGICAL_TASK_IDS = (
    "TASK-D0-01",
    "TASK-D0-02",
    "TASK-D0-03",
    "TASK-D0-05",
    "TASK-D0-06",
    "TASK-D0-04",
)


class Stage0ActivateError(Exception):
    """Stable activation failure."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise Stage0ActivateError(code, detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-IO", detail)


def _tcb(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-TCB", detail)


def _service(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-SERVICE", detail)


def _handoff(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-HANDOFF", detail)


def _backfill(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-BACKFILL", detail)


def _bundle(detail: str) -> NoReturn:
    _fail("PF-STAGE0-ACTIVATE-BUNDLE", detail)


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


def _sha256_file(path: Path, where: str) -> bytes:
    return hashlib.sha256(_read_file(str(path), where)).digest()


def _map_error(code_fn, operation, detail: str):
    try:
        return operation()
    except _DRIVER.ActivationError as error:
        code_fn(f"{detail}: {error.detail}")
    except _CONSUMER.Rejected:
        code_fn(detail)


def _require_eligible(observation_bytes: bytes) -> None:
    try:
        parsed = json.loads(observation_bytes.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _fail(
            "PF-STAGE0-ACTIVATE-INELIGIBLE",
            "host observation is not a bounded JSON document",
        )
    if type(parsed) is not dict or parsed.get("eligibleForHermetic") is not True:
        _fail(
            "PF-STAGE0-ACTIVATE-INELIGIBLE",
            "host observation does not prove an eligible host",
        )


def _content_ref_wire(ref: ContentRef) -> dict:
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": "sha256:" + ref.digest.bytes.hex(),
    }


def _build_handoff_base(
    policy_bytes: bytes,
    policy_ref: ContentRef,
    candidate: object,
    descriptor_wire: dict,
    descriptor_ref: ContentRef,
    workdir: str,
    observation_bytes: bytes,
    profile_bytes: bytes,
    tcb_digests: Tuple[bytes, bytes, bytes, bytes],
) -> object:
    archive_bytes = _read_file(
        os.path.join(workdir, "candidate-archive.tar"), "candidate archive"
    )
    manifest_bytes = _read_file(
        os.path.join(workdir, "evidence-root-manifest.json"),
        "evidence root manifest",
    )
    return _ACCEPTANCE.RehearsalBase(
        policyBytes=policy_bytes,
        policyRef=policy_ref,
        requiredBytes=b"",
        requiredRef=ContentRef(
            "proof-forge.required-test-set.v1",
            "activate-placeholder",
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
        observationId="host-observation",
        observationVersion="1.0.0",
        observationBytes=observation_bytes,
        profileId="host-profile",
        profileVersion="1.0.0",
        profileBytes=profile_bytes,
        tcbDigests=tcb_digests,
    )


def _spawn_service_child(
    *,
    policy_path: str,
    workdir: str,
    run_id: str,
    nonce: str,
    channel_fd: Optional[int],
    socket_path: Optional[str],
) -> subprocess.Popen:
    argv = [
        _PYTHON,
        "-I",
        "-S",
        str(_SCRIPT_DIR / "stage0_store_service.py"),
        "--policy",
        policy_path,
        "--seed-file",
        os.path.join(workdir, "service-seed.hex"),
        "--descriptor",
        os.path.join(workdir, "service-descriptor.json"),
        "--run-id",
        run_id,
        "--nonce",
        nonce,
    ]
    pass_fds: Tuple[int, ...] = ()
    if channel_fd is not None:
        argv.extend(("--fd", str(channel_fd)))
        pass_fds = (channel_fd,)
    else:
        assert socket_path is not None
        argv.extend(("--socket", socket_path))
    try:
        return subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
            close_fds=True,
            pass_fds=pass_fds,
            start_new_session=True,
        )
    except OSError as error:
        _service(f"cannot spawn the service child: {error}")


def _connect_path_client(
    proc: subprocess.Popen,
    descriptor_ref: ContentRef,
    run_id: str,
    nonce: str,
    socket_path: str,
) -> object:
    deadline = time.monotonic() + 10.0
    while True:
        if proc.poll() is not None:
            stderr = b"" if proc.stderr is None else proc.stderr.read()
            _service(f"service child exited during startup: {stderr!r}")
        try:
            client = _STORE.AuthorityStoreClient(
                descriptor_ref, run_id, nonce, io_timeout_seconds=30.0
            )
            client.connect(socket_path)
            return client
        except _STORE.AuthorityStoreError as error:
            if time.monotonic() > deadline:
                _service(f"authority store connect failed: {error.code}")
            time.sleep(0.05)


def _publish_closure(
    client: object,
    schema: str,
    object_bytes: bytes,
    where: str,
) -> None:
    try:
        stored = client.publish_with_readback(schema, object_bytes)
    except _STORE.AuthorityStoreError as error:
        _backfill(f"{where} publish closure failed: {error.code}")
    if stored != object_bytes:
        _backfill(f"{where} publish closure failed")


def _write_bundle(
    output_dir: str,
    *,
    policy_bytes: bytes,
    policy_ref: ContentRef,
    required_bytes: bytes,
    required_ref: ContentRef,
    approval_bytes: Dict[str, bytes],
    receipt_bytes: Dict[str, bytes],
    set_bytes: bytes,
    handoff_bytes: bytes,
    activation_bytes: bytes,
    activation_receipt_id: str,
    activation_receipt_digest: bytes,
) -> None:
    try:
        os.mkdir(output_dir)
    except FileExistsError:
        _bundle("output bundle directory already exists")
    except OSError as error:
        _bundle(f"cannot create the bundle directory: {error}")
    try:
        set_wire = _CONSUMER.decode_canonical_pf_jcs(set_bytes)
        handoff_wire = _CONSUMER.decode_canonical_pf_jcs(handoff_bytes)
        manifest = {
            "schema": "proof-forge.stage0-activation-closure-manifest.v1",
            "authorityPolicy": _content_ref_wire(policy_ref),
            "requiredTestSet": _content_ref_wire(required_ref),
            "approvalSet": {
                "schema": set_wire["schema"],
                "id": set_wire["id"],
                "version": set_wire["version"],
                "digest": "sha256:" + hashlib.sha256(
                    b"pf.bootstrap-approval-set.v1\x00" + set_bytes
                ).hexdigest(),
            },
            "stage0Handoff": {
                "schema": handoff_wire["schema"],
                "id": handoff_wire["id"],
                "version": handoff_wire["version"],
                "digest": "sha256:" + hashlib.sha256(
                    b"pf.eligible-stage0-handoff.v1\x00" + handoff_bytes
                ).hexdigest(),
            },
            "taskApprovals": [
                {
                    "taskId": task_id,
                    "digest": "sha256:" + hashlib.sha256(
                        b"pf.bootstrap-task-approval.v1\x00"
                        + approval_bytes[task_id]
                    ).hexdigest(),
                }
                for task_id in D0_TASK_IDS
            ],
            "taskReceipts": [
                {
                    "taskId": task_id,
                    "id": _CONSUMER.decode_canonical_pf_jcs(
                        receipt_bytes[task_id]
                    )["id"],
                    "digest": "sha256:" + hashlib.sha256(
                        b"pf.bootstrap-task-verifier-receipt.v1\x00"
                        + receipt_bytes[task_id]
                    ).hexdigest(),
                }
                for task_id in D0_TASK_IDS
            ],
            "activationReceipt": {
                "id": activation_receipt_id,
                "digest": "sha256:" + activation_receipt_digest.hex(),
            },
        }
        files = {
            "authority-policy.json": policy_bytes,
            "required-test-set.json": required_bytes,
            "bootstrap-approval-set.json": set_bytes,
            "activation-receipt.json": activation_bytes,
            "closure-manifest.json": (
                json.dumps(manifest, sort_keys=True, indent=1).encode("utf-8")
                + b"\n"
            ),
        }
        for task_id in D0_TASK_IDS:
            files[f"approvals/{task_id.lower()}-approval.json"] = (
                approval_bytes[task_id]
            )
            files[f"receipts/{task_id.lower()}-receipt.json"] = (
                receipt_bytes[task_id]
            )
        os.mkdir(os.path.join(output_dir, "approvals"))
        os.mkdir(os.path.join(output_dir, "receipts"))
        for name, payload in files.items():
            target = os.path.join(output_dir, name)
            fd = os.open(
                target,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o444,
            )
            with os.fdopen(fd, "wb") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
    except BaseException:
        shutil.rmtree(output_dir, ignore_errors=True)
        raise


def run_activate(
    policy_path: str,
    candidate_path: str,
    workdir: str,
    output_dir: str,
    approvals_dir: Optional[str],
) -> int:
    if os.path.lexists(output_dir):
        _bundle("output bundle directory already exists")
    policy_bytes, policy, policy_ref = _map_error(
        _io, lambda: _DRIVER._load_policy(policy_path), "policy load failed"
    )
    candidate = _map_error(
        _io, lambda: _DRIVER._load_candidate(candidate_path),
        "candidate load failed",
    )
    observation_bytes = _read_file(
        os.path.join(workdir, "host-observation.json"), "host observation"
    )
    profile_bytes = _read_file(
        os.path.join(workdir, "host-profile.json"), "host profile"
    )
    _require_eligible(observation_bytes)
    print("eligible: ok")

    tcb_digests = (
        _sha256_file(_SCRIPT_DIR / "verify_host_stage0.sh", "stage0 verifier"),
        policy.verifier.executableDigest.bytes,
        _sha256_file(_SCRIPT_DIR / "stage0_containment.py", "continuation"),
        _sha256_file(_SCRIPT_DIR / "gate_evidence.py", "formal finalizer"),
    )
    verifier_exe_digest = hashlib.sha256(
        _read_file(
            os.path.join(workdir, "bootstrap-verifier.exe"),
            "bootstrap verifier executable",
        )
    ).digest()
    if verifier_exe_digest != policy.verifier.executableDigest.bytes:
        _tcb(
            "pinned bootstrap verifier executable does not match the policy "
            "executableDigest"
        )
    print("tcb: ok")

    descriptor_pair = _map_error(
        _service,
        lambda: _DRIVER._load_descriptor(workdir, policy),
        "service descriptor rejected",
    )
    descriptor_wire, descriptor_ref = descriptor_pair
    expected_service_digest = _CONSUMER.parse_digest(
        descriptor_wire["serviceExecutableDigest"]
    ).bytes
    if _sha256_file(
        _SCRIPT_DIR / "stage0_store_service.py", "service executable"
    ) != expected_service_digest:
        _service(
            "service executable bytes do not match the descriptor "
            "serviceExecutableDigest"
        )
    print("service: ok")

    handoff_path = os.path.join(workdir, "eligible-stage0-handoff.json")
    produced_handoff = None
    handoff_bytes: bytes
    if os.path.isfile(handoff_path):
        handoff_bytes = _read_file(handoff_path, "stage0 handoff")
        handoff = _map_error(
            _handoff,
            lambda: _CONSUMER._preflight_eligible_stage0_handoff(
                handoff_bytes
            ).handoff,
            "stage0 handoff rejected",
        )
        if handoff.authorityPolicy != policy_ref:
            _handoff("handoff authority policy does not match the policy")
        if handoff.authorityStoreService != descriptor_ref:
            _handoff("handoff authority store ref does not match the descriptor")
        if handoff.candidate != candidate:
            _handoff("handoff candidate does not match the candidate")
        recomputed_tcb = (
            handoff.tcb.stage0VerifierDigest.bytes,
            handoff.tcb.bootstrapVerifierDigest.bytes,
            handoff.tcb.continuationDigest.bytes,
            handoff.tcb.formalFinalizerDigest.bytes,
        )
        if recomputed_tcb != tcb_digests:
            _tcb("consumed handoff tcb does not match recomputed digests")
        handoff_digest_hex = hashlib.sha256(
            b"pf.eligible-stage0-handoff.v1\x00" + handoff_bytes
        ).hexdigest()
        print(f"handoff: consumed {handoff.id} sha256:{handoff_digest_hex}")
    else:
        run_id = "stage0-activate-" + secrets.token_hex(8)
        nonce = secrets.token_bytes(32).hex()
        base = _build_handoff_base(
            policy_bytes,
            policy_ref,
            candidate,
            descriptor_wire,
            descriptor_ref,
            workdir,
            observation_bytes,
            profile_bytes,
            tcb_digests,
        )
        try:
            produced_handoff = _ACCEPTANCE.produce_run_handoff(
                base,
                handoff_id="stage0-activate-handoff",
                handoff_version="1.0.0",
                run_id=run_id,
                policy_path=policy_path,
                archive_path=os.path.join(workdir, "candidate-archive.tar"),
                manifest_path=os.path.join(
                    workdir, "evidence-root-manifest.json"
                ),
            )
        except _ACCEPTANCE._HANDOFF.Stage0HandoffError as error:
            _handoff(f"handoff production failed: {error.code}")
        handoff_bytes = produced_handoff.handoffBytes
        fd = os.open(
            handoff_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o444,
        )
        with os.fdopen(fd, "wb") as handle:
            handle.write(handoff_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        handoff_digest_hex = produced_handoff.handoffDigest.bytes.hex()
        print(
            f"handoff: produced {produced_handoff.handoffRef.id} "
            f"sha256:{handoff_digest_hex}"
        )

    run_id, nonce = _map_error(
        _handoff,
        lambda: _DRIVER._preflight_handoff_run(handoff_bytes),
        "stage0 handoff rejected",
    )
    snapshot = _map_error(
        _io, lambda: _DRIVER._load_snapshot(workdir), "phase5 snapshot load failed"
    )
    approvals = approvals_dir or os.path.join(workdir, "approvals")
    gaps: list = []
    chain = _map_error(
        _backfill,
        lambda: _DRIVER._load_chain(
            policy_bytes, snapshot, None, approvals, gaps
        ),
        "approvals chain rejected",
    )
    substantive_gaps = [
        gap for gap in gaps
        if not gap.startswith("stage0 handoff missing:")
    ]
    if substantive_gaps:
        _backfill(f"approvals chain incomplete: {substantive_gaps[0]}")
    (
        required_bytes,
        required_ref,
        approval_bytes,
        receipt_bytes,
        set_bytes,
        activation_bytes,
        catalog_approval_bytes,
    ) = chain
    if len(receipt_bytes) != 6 or set_bytes is None or activation_bytes is None:
        _backfill("approvals chain must carry the full six-task closure")
    base = _DRIVER._build_base_core(
        policy_bytes,
        policy_ref,
        required_bytes,
        required_ref,
        snapshot,
        candidate,
        descriptor_wire,
        descriptor_ref,
    )
    run = _DRIVER.DriverRun(
        handoffBytes=handoff_bytes,
        approvalBytes=approval_bytes,
        receiptBytes=receipt_bytes,
        setBytes=set_bytes or b"",
    )

    service_proc: Optional[subprocess.Popen] = None
    client = None
    try:
        if produced_handoff is not None:
            service_fd = produced_handoff.channels.authorityStoreServiceFd
            service_proc = _spawn_service_child(
                policy_path=policy_path,
                workdir=workdir,
                run_id=run_id,
                nonce=nonce,
                channel_fd=service_fd,
                socket_path=None,
            )
            try:
                client = _ACCEPTANCE.adopt_channel_client(
                    expected_descriptor_ref=descriptor_ref,
                    run_id=run_id,
                    nonce=nonce,
                    channel_fd=produced_handoff.channels.authorityStoreFd,
                    io_timeout=30.0,
                )
            except _STORE.AuthorityStoreError as error:
                _service(f"handoff channel hello failed: {error.code}")
        else:
            socket_path = os.path.join(workdir, "authority-store.sock")
            service_proc = _spawn_service_child(
                policy_path=policy_path,
                workdir=workdir,
                run_id=run_id,
                nonce=nonce,
                channel_fd=None,
                socket_path=socket_path,
            )
            client = _connect_path_client(
                service_proc, descriptor_ref, run_id, nonce, socket_path
            )

        _publish_closure(
            client,
            _STORE.REQUIRED_TEST_SET_SCHEMA,
            required_bytes,
            "required test set",
        )
        print("backfill: required-test-set stored")
        if catalog_approval_bytes is not None:
            _publish_closure(
                client,
                _STORE.FORMAL_CATALOG_APPROVAL_SCHEMA,
                catalog_approval_bytes,
                "formal catalog approval",
            )
            print("backfill: catalog-approval stored")
        for task_id in _TOPOLOGICAL_TASK_IDS:
            _map_error(
                _backfill,
                lambda task_id=task_id: (
                    _CONSUMER.parse_bootstrap_task_verifier_receipt(
                        receipt_bytes[task_id],
                        approval_bytes[task_id],
                        required_bytes,
                        policy_bytes,
                        snapshot,
                        handoff_bytes,
                    )
                ),
                f"{task_id} receipt rejected against the handoff",
            )
        _map_error(
            _backfill,
            lambda: _CONSUMER.parse_bootstrap_approval_set(
                set_bytes,
                tuple(receipt_bytes[task_id] for task_id in D0_TASK_IDS),
                required_bytes,
                policy_bytes,
                snapshot,
                handoff_bytes,
            ),
            "approval set rejected against the handoff",
        )
        for task_id in _TOPOLOGICAL_TASK_IDS:
            _publish_closure(
                client,
                _STORE.TASK_APPROVAL_SCHEMA,
                approval_bytes[task_id],
                f"{task_id} approval",
            )
            _publish_closure(
                client,
                _STORE.TASK_RECEIPT_SCHEMA,
                receipt_bytes[task_id],
                f"{task_id} receipt",
            )
            try:
                _ACCEPTANCE.close_task(base, run, client, task_id)
            except _ACCEPTANCE.BootstrapAcceptanceError as error:
                _backfill(f"{task_id} closure failed: {error.detail}")
            print(f"backfill: {task_id} closed")
        _publish_closure(
            client, _STORE.APPROVAL_SET_SCHEMA, set_bytes, "approval set"
        )
        print("backfill: approval set stored")
        try:
            _ACCEPTANCE.collect_activation_inputs(base, run, client)
        except _ACCEPTANCE.BootstrapAcceptanceError as error:
            _backfill(f"activation inputs incomplete: {error.detail}")
        _publish_closure(
            client,
            _STORE.VERIFIER_RECEIPT_SCHEMA,
            activation_bytes,
            "activation receipt",
        )
        receipt, receipt_ref = _map_error(
            _backfill,
            lambda: _CONSUMER.parse_bootstrap_approval_verifier_receipt(
                activation_bytes,
                set_bytes,
                tuple(receipt_bytes[task_id] for task_id in D0_TASK_IDS),
                required_bytes,
                policy_bytes,
                snapshot,
                handoff_bytes,
            ),
            "activation receipt final verification failed",
        )
        print(f"activation: {receipt.id} sha256:{receipt_ref.digest.bytes.hex()}")
    finally:
        if client is not None:
            client.close()
        if service_proc is not None:
            service_proc.kill()
            service_proc.wait()
        if produced_handoff is not None:
            for fd in (
                produced_handoff.channels.authorityPolicyFd,
                produced_handoff.channels.candidateArchiveFd,
                produced_handoff.channels.evidenceRootFd,
            ):
                try:
                    os.close(fd)
                except OSError:
                    pass

    _write_bundle(
        output_dir,
        policy_bytes=policy_bytes,
        policy_ref=policy_ref,
        required_bytes=required_bytes,
        required_ref=required_ref,
        approval_bytes=approval_bytes,
        receipt_bytes=receipt_bytes,
        set_bytes=set_bytes,
        handoff_bytes=handoff_bytes,
        activation_bytes=activation_bytes,
        activation_receipt_id=receipt.id,
        activation_receipt_digest=receipt_ref.digest.bytes,
    )
    print(f"bundle: {output_dir}")
    return 0


_USAGE = (
    "usage: stage0_activate.py --policy <policy.json> --candidate "
    "<candidate.json> --workdir <dir> --output <bundle-dir> "
    "[--approvals-dir <dir>]"
)


def main(argv: Optional[Tuple[str, ...]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    options = {
        "--policy": None,
        "--candidate": None,
        "--workdir": None,
        "--output": None,
        "--approvals-dir": None,
    }
    index = 0
    while index < len(args):
        flag = args[index]
        if flag not in options or index + 1 >= len(args):
            print(_USAGE, file=sys.stderr)
            return 2
        if options[flag] is not None:
            print(_USAGE, file=sys.stderr)
            return 2
        options[flag] = args[index + 1]
        index += 2
    if any(options[flag] is None for flag in (
        "--policy", "--candidate", "--workdir", "--output",
    )):
        print(_USAGE, file=sys.stderr)
        return 2
    try:
        return run_activate(
            options["--policy"],
            options["--candidate"],
            options["--workdir"],
            options["--output"],
            options["--approvals-dir"],
        )
    except Stage0ActivateError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
