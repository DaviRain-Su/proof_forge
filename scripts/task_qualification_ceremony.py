#!/usr/bin/env python3
"""Local single-maintainer TASK-D0-10 ceremony and qualified integration.

Only this process reads the candidate-external production seed directory.  It
maps seeds by derived public key, never prints or persists private material,
and gives the protected adapter only the accepted seven public inputs.  The
initial ``qualified-self-test`` command builds a production-policy
bootstrap/development vector, drives the v2 seqpacket transcript, and supplies
the resulting manifest/FDS to the frozen black-box test.

The local service is deliberately not described as ADR-0021's complete static
U/P/A custody supervisor or durable nonce store.  Its public acceptance and
closeout outputs are bootstrap/development evidence, not formal or hermetic
custody evidence.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import replace
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve()
_ROOT = _HERE.parent.parent
sys.path.insert(0, str(_HERE.parent))

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import revocation_ledger as _REVOCATION
import task_qualification_authority_store_v2 as _STORE
import task_qualification_fixture_builder as _FIXTURE
import task_qualification_objects as _TQO
import task_qualification_protected_adapter as _ADAPTER

TASK_ID = "TASK-D0-10"
OPERATION = "task-completion"
ROLE_KEY_IDS = ("key-architecture", "key-quality", "key-security")
FIXED_FDS = {
    "authorityPolicyFd": 100,
    "authorityStoreFd": 101,
    "candidateArchiveFd": 102,
    "provenanceBundleFd": 103,
    "trustedClockFd": 104,
}
QUALIFIED_SCHEMA = "proof-forge.task-qualification-v2-qualified-test-input.v1"
POLICY_PATH = _ROOT / "build/d0-04-ceremony/work/authority-policy.json"
PUBLIC_SERVICE_DESCRIPTOR_PATH = (
    _ROOT / "build/d0-04-ceremony/work/service-descriptor.json"
)
SELF_TEST_PATH = _HERE.with_name(
    "task_qualification_authority_store_v2_self_test.py"
)


class CeremonyError(RuntimeError):
    pass


def _canonical(value: Any) -> bytes:
    return _BTO.canonical_pf_jcs(value)


def _digest(data: bytes) -> _BTO.Digest:
    return _BTO.Digest("sha256", hashlib.sha256(data).digest())


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


def _safe_read_seed_file(path: Path) -> bytes:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise CeremonyError("production seed safe-open failed") from exc
    try:
        st = os.fstat(fd)
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_nlink != 1
            or st.st_mode & 0o077
            or st.st_size not in (32, 64, 65)
        ):
            raise CeremonyError("production seed metadata rejected")
        raw = os.read(fd, 66)
        if len(raw) != st.st_size:
            raise CeremonyError("production seed stable read failed")
    finally:
        os.close(fd)
    if len(raw) == 32:
        seed = raw
    else:
        text = raw.decode("ascii", errors="strict").strip()
        if len(text) != 64 or any(ch not in "0123456789abcdef" for ch in text):
            raise CeremonyError("production seed encoding rejected")
        seed = bytes.fromhex(text)
    if len(seed) != 32:
        raise CeremonyError("production seed length rejected")
    return seed


def _load_production_seeds(seed_root: Path, policy) -> dict[str, bytes]:
    try:
        root_st = seed_root.stat()
        entries = sorted(seed_root.iterdir(), key=lambda p: p.name.encode("utf-8"))
    except OSError as exc:
        raise CeremonyError("production seed root unavailable") from exc
    if not stat.S_ISDIR(root_st.st_mode) or len(entries) != 6:
        raise CeremonyError("production seed root must contain exactly six files")

    public_to_key = {
        principal.publicKey: principal.keyId for principal in policy.principals
    }
    public_descriptor = json.loads(PUBLIC_SERVICE_DESCRIPTOR_PATH.read_text("utf-8"))
    public_to_key[bytes.fromhex(public_descriptor["servicePublicKey"])] = (
        "key-authority-store-service"
    )
    public_to_key[policy.verifier.receiptPublicKey] = "key-verifier-receipt"

    result: dict[str, bytes] = {}
    for path in entries:
        if path.is_symlink():
            raise CeremonyError("production seed entry symlink rejected")
        seed = _safe_read_seed_file(path)
        public_key = _BTP.ed25519_public_key_from_seed(seed)
        key_id = public_to_key.get(public_key)
        if key_id is None or key_id in result:
            raise CeremonyError("production seed public-key set mismatch")
        result[key_id] = seed
    if set(result) != set(public_to_key.values()):
        raise CeremonyError("production seed set incomplete")
    return result


def _sign_with_empty_signatures(
    wire: dict,
    statement_domain: bytes,
    signature_domain: bytes,
    key_ids: tuple[str, ...],
    seeds: dict[str, bytes],
) -> list[dict]:
    unsigned = dict(wire)
    unsigned["signatures"] = []
    statement = _TQO.domain_digest(statement_domain, unsigned).bytes
    message = signature_domain + b"\x00" + statement
    return [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": _BTP.sign_ed25519(seeds[key_id], message).hex(),
        }
        for key_id in sorted(key_ids)
    ]


def _sign_without_signatures_field(
    wire: dict,
    statement_domain: bytes,
    signature_domain: bytes,
    key_ids: tuple[str, ...],
    seeds: dict[str, bytes],
) -> list[dict]:
    unsigned = dict(wire)
    unsigned.pop("signatures", None)
    statement = _TQO.domain_digest(statement_domain, unsigned).bytes
    message = signature_domain + b"\x00" + statement
    return [
        {
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": _BTP.sign_ed25519(seeds[key_id], message).hex(),
        }
        for key_id in sorted(key_ids)
    ]


def _signature_records(wires: list[dict]) -> tuple[_TQO.ApprovalSignatureV1, ...]:
    return tuple(
        _TQO.ApprovalSignatureV1(
            item["keyId"], item["algorithm"], bytes.fromhex(item["signature"])
        )
        for item in wires
    )


def _identity(prefix: str, executable_bytes: bytes) -> tuple[_TQO.VerifierIdentityV1, dict[str, bytes]]:
    payloads = {
        f"{prefix}-executable": executable_bytes,
        f"{prefix}-closure": _canonical(
            {
                "identity": prefix,
                "executableSha256": hashlib.sha256(executable_bytes).hexdigest(),
            }
        ),
        f"{prefix}-build-policy": (
            f"proof-forge taskqualification {prefix} build policy v1\n"
        ).encode("ascii"),
    }
    executable = _TQO.task_qualification_artifact_payload_ref(
        f"{prefix}-executable-v1", "1.0.0", payloads[f"{prefix}-executable"]
    )
    closure = _TQO.task_qualification_artifact_payload_ref(
        f"{prefix}-closure-v1", "1.0.0", payloads[f"{prefix}-closure"]
    )
    build_policy = _TQO.task_qualification_artifact_payload_ref(
        f"{prefix}-build-policy-v1",
        "1.0.0",
        payloads[f"{prefix}-build-policy"],
    )
    return (
        _TQO.VerifierIdentityV1(
            id=f"{prefix}-identity-v1",
            executable=executable,
            closure=closure,
            sourceDigest=_digest(executable_bytes),
            buildPolicy=build_policy,
        ),
        payloads,
    )


def _build_profile_and_pin(
    policy_ref: _BTO.ContentRef,
    adapter: _TQO.VerifierIdentityV1,
    snapshot_parser: _TQO.VerifierIdentityV1,
    seeds: dict[str, bytes],
) -> tuple[_TQO.ProductionVerificationProfileV1, _TQO.ProductionVerificationProfilePinV1]:
    gate_digest = _TQO.compute_gate_set_digest(OPERATION, ())
    profile = _TQO.ProductionVerificationProfileV1(
        schema=_TQO.PRODUCTION_PROFILE_SCHEMA,
        id=_TQO.derive_production_profile_id(TASK_ID, OPERATION, gate_digest),
        version="1.0.0",
        kind="production",
        namespace=_TQO.FIXTURE_PRODUCTION_NAMESPACE,
        taskId=TASK_ID,
        operation=OPERATION,
        gateSetDigest=gate_digest,
        expectedAuthorityPolicy=policy_ref,
        adapter=adapter,
        snapshotParser=snapshot_parser,
        artifacts=(),
        signatures=(),
    )
    profile_wire = _TQO.production_profile_to_wire(profile)
    profile = replace(
        profile,
        signatures=_signature_records(
            _sign_with_empty_signatures(
                profile_wire,
                _TQO.DOMAIN_PRODUCTION_PROFILE_STATEMENT,
                _TQO.DOMAIN_PRODUCTION_PROFILE_SIGNATURE,
                ROLE_KEY_IDS,
                seeds,
            )
        ),
    )
    profile_ref = _TQO.production_profile_content_ref(profile)
    pin = _TQO.ProductionVerificationProfilePinV1(
        schema=_TQO.PRODUCTION_PROFILE_PIN_SCHEMA,
        id=_TQO.derive_production_profile_pin_id(TASK_ID, OPERATION, gate_digest),
        version="1.0.0",
        taskId=TASK_ID,
        operation=OPERATION,
        gateSetDigest=gate_digest,
        authorityPolicy=policy_ref,
        namespace=_TQO.FIXTURE_PRODUCTION_NAMESPACE,
        profile=profile_ref,
        expectedSnapshotParser=snapshot_parser,
        signatures=(),
    )
    pin_wire = _TQO.production_profile_pin_to_wire(pin)
    pin = replace(
        pin,
        signatures=_signature_records(
            _sign_with_empty_signatures(
                pin_wire,
                _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_STATEMENT,
                _TQO.DOMAIN_PRODUCTION_PROFILE_PIN_SIGNATURE,
                ROLE_KEY_IDS,
                seeds,
            )
        ),
    )
    _TQO.join_pin_to_profile(pin, profile)
    return profile, pin


def _build_completion_subjects(
    policy_ref: _BTO.ContentRef,
    adapter: _TQO.VerifierIdentityV1,
    snapshot_ref: _BTO.ContentRef,
    seeds: dict[str, bytes],
    instant: str,
) -> dict[str, Any]:
    pre_candidate = _FIXTURE.build_synthetic_candidate(
        TASK_ID,
        {"qualified/input.txt": b"taskqualification qualified C\n"},
        commit_prefix="",
        tree_prefix=None,
    )
    task_row = _TQO.TaskQualificationTaskRowV1(
        taskId=TASK_ID,
        output="qualified task-completion integration vector",
        dependencies=(),
        prerequisites=("SPEC-TASKQUAL-001@accepted",),
        tests=("TST-DOC-001",),
        evidenceIds=("EV-20260724-0001",),
        status="in_progress",
    )
    done_row = replace(task_row, status="done")
    semantic_set = _TQO.SemanticCloseoutFileSetV1(
        schema="proof-forge.semantic-closeout-file-set.v1",
        id="semantic-closeout-d0-10",
        version="1.0.0",
        taskId=TASK_ID,
        preCloseCandidate=pre_candidate.identity,
        changes=(),
    )
    semantic_digest = _FIXTURE.semantic_closeout_file_set_digest(semantic_set)
    qualification_path = (
        "docs/governance/task-qualifications/TASK-D0-10/qualification.json"
    )
    patch = _TQO.AllowedCloseoutPatchV1(
        schema="proof-forge.allowed-closeout-patch.v1",
        id="allowed-closeout-d0-10",
        version="1.0.0",
        taskId=TASK_ID,
        preCloseCandidate=pre_candidate.identity,
        allowedPaths=(qualification_path,),
        semanticFileSetDigest=semantic_digest,
        resultingTaskRowDigest=_FIXTURE.task_row_digest(done_row),
    )
    patch_ref = _FIXTURE.allowed_closeout_patch_content_ref(patch)
    freeze_bytes = (
        _ROOT / "docs/governance/task-freeze-packages/TASK-D0-10.json"
    ).read_bytes()
    freeze_ref = _TQO.TaskFreezePackageRefV1(
        taskId=TASK_ID,
        digest=_TQO.domain_digest_raw(
            _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, freeze_bytes
        ),
    )
    fixture_gate = copy.deepcopy(
        _FIXTURE.build_fixture_chain().qualification_obj["gates"][0]
    )
    fixture_gate["taskId"] = TASK_ID
    review_report = b"single-maintainer owner waiver; executable matrix retained\n"
    review_digest = _BTO.Digest(
        "sha256",
        hashlib.sha256(
            _TQO.DOMAIN_REVIEW_REPORT + b"\x00" + review_report
        ).digest(),
    )
    qualification = {
        "schema": "proof-forge.task-qualification.v1",
        "id": "task-qualification-d0-10",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "preCloseCandidate": _candidate_wire(pre_candidate.identity),
        "taskRow": _FIXTURE.task_row_to_wire(task_row),
        "freezePackage": _FIXTURE.freeze_package_ref_to_wire(freeze_ref),
        "gates": [fixture_gate],
        "dependencies": [],
        "verifier": _TQO.verifier_identity_to_wire(adapter),
        "authorityPolicy": _ref_wire(policy_ref),
        "allowedCloseoutPatch": _ref_wire(patch_ref),
        "independentReviews": [
            {
                "reviewerId": "davirain-owner-waiver",
                "reviewerKind": "human",
                "invocationId": "single-maintainer-owner-waiver-qualified-0001",
                "reportDigest": _digest_wire(review_digest),
                "reviewCommit": pre_candidate.identity.commit,
                "reviewLink": "https://github.com/DaviRain-Su/proof_forge",
                "decision": "approved",
                "findings": [],
            }
        ],
        "signatures": [],
    }
    qualification["signatures"] = _sign_with_empty_signatures(
        qualification,
        _TQO.DOMAIN_TASK_QUALIFICATION_STATEMENT,
        _TQO.DOMAIN_TASK_QUALIFICATION_SIGNATURE,
        ROLE_KEY_IDS,
        seeds,
    )
    qualification_bytes = _canonical(qualification)

    close_files = {
        path: entry.content
        for path, entry in pre_candidate.archive_projection.path_map.items()
    }
    close_files[qualification_path] = qualification_bytes
    close_candidate = _FIXTURE.build_synthetic_candidate(
        TASK_ID,
        close_files,
        parent_sha=pre_candidate.identity.commit,
        commit_prefix="",
        tree_prefix=None,
    )
    changes = [
        (qualification_path, None, _digest(qualification_bytes)),
    ]
    file_set = _FIXTURE.build_closeout_file_set(
        pre_candidate, close_candidate, changes, task_id=TASK_ID
    )
    file_set_bytes = _canonical(_FIXTURE.closeout_file_set_to_wire(file_set))
    file_set_ref = _FIXTURE.closeout_file_set_content_ref(file_set)
    closeout_diff = _FIXTURE.closeout_file_set_digest(file_set)
    qualification_ref = _BTO.ContentRef(
        qualification["schema"],
        qualification["id"],
        qualification["version"],
        _TQO.domain_digest(_TQO.DOMAIN_TASK_QUALIFICATION, qualification),
    )
    receipt = {
        "schema": "proof-forge.task-completion-receipt.v1",
        "id": "task-completion-d0-10",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "preCloseCandidate": _candidate_wire(pre_candidate.identity),
        "closeoutCandidate": _candidate_wire(close_candidate.identity),
        "qualification": {
            "taskId": TASK_ID,
            "id": qualification["id"],
            "digest": _digest_wire(qualification_ref.digest),
        },
        "allowedCloseoutPatch": _ref_wire(patch_ref),
        "closeoutDiffDigest": _digest_wire(closeout_diff),
        "authorityPolicy": _ref_wire(policy_ref),
        "revocationSnapshot": _ref_wire(snapshot_ref),
        "issuedAt": instant,
        "signatures": [],
    }
    receipt["signatures"] = _sign_with_empty_signatures(
        receipt,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_STATEMENT,
        _TQO.DOMAIN_TASK_COMPLETION_RECEIPT_SIGNATURE,
        ROLE_KEY_IDS,
        seeds,
    )
    return {
        "pre": pre_candidate,
        "close": close_candidate,
        "patch": patch,
        "patchBytes": _canonical(_FIXTURE.allowed_closeout_patch_to_wire(patch)),
        "patchRef": patch_ref,
        "fileSet": file_set,
        "fileSetBytes": file_set_bytes,
        "fileSetRef": file_set_ref,
        "qualification": qualification,
        "qualificationBytes": qualification_bytes,
        "qualificationRef": qualification_ref,
        "receipt": receipt,
        "receiptBytes": _canonical(receipt),
    }


def _isolation_policy(
    run_id: str, nonce: str, service_executable_fd: int
) -> tuple[dict, _BTO.ContentRef]:
    ns = {"device": 1, "inode": 1}
    policy = {
        "schema": "proof-forge.task-qualification-store-isolation-policy.v2",
        "id": f"task-qualification-store-isolation-{run_id}",
        "version": "2.0.0",
        "namespace": _STORE.NAMESPACE,
        "taskId": TASK_ID,
        "operation": OPERATION,
        "runId": run_id,
        "nonce": nonce,
        "userNamespace": ns,
        "parentPidNamespace": {"device": 1, "inode": 2},
        "adapterPidNamespace": {"device": 1, "inode": 3},
        "serviceMountNamespace": {"device": 1, "inode": 4},
        "adapterMountNamespace": {"device": 1, "inode": 5},
        "uidMap": [
            {"insideId": 1001, "outsideId": 200001, "length": 1},
            {"insideId": 1002, "outsideId": 200002, "length": 1},
        ],
        "gidMap": [
            {"insideId": 1003, "outsideId": 200003, "length": 1},
            {"insideId": 1004, "outsideId": 200004, "length": 1},
        ],
        "adapterUid": 1001,
        "adapterGid": 1003,
        "serviceUid": 1002,
        "serviceGid": 1004,
        "serviceProcRoot": {"device": 1, "inode": 6},
        "durableStateRoot": {"device": 1, "inode": 7},
        "seedRoot": {"device": 1, "inode": 8},
        "serviceMounts": [],
        "adapterMounts": [],
        "fdRoles": [],
        "socketDomain": "AF_UNIX",
        "socketType": "SOCK_SEQPACKET",
        "socketCreation": "socketpair",
        "socketSendFlags": "MSG_NOSIGNAL",
        "passCredentials": True,
        "requestedSocketBufferBytes": 4194304,
        "minimumEffectiveSocketBufferBytes": 8388608,
        "preSeedCapabilities": [6, 7, 8, 19, 21],
        "custodyCapabilities": [8, 19],
        "adapterCapabilities": [],
        "finalServiceCapabilities": [],
        "serviceExecutableFd": service_executable_fd,
        "serviceArgv": ["proof-forge-taskqualification-store-v2"],
        "serviceEnvironment": [],
        "execOperation": "execveat-at-empty-path",
        "staticElfRequired": True,
        "seccompPolicies": [],
        "maximumFrameBytes": _STORE.MAX_FRAME_BYTES,
        "maximumTerminalAcceptances": 1,
    }
    ref = _BTO.ContentRef(
        policy["schema"],
        policy["id"],
        policy["version"],
        _TQO.domain_digest(b"pf.taskqual.store-isolation-policy.v2", policy),
    )
    return policy, ref


def _descriptor(
    run_id: str,
    service_public_key: bytes,
    authority_store_identity: _TQO.VerifierIdentityV1,
    supervisor_identity: _TQO.VerifierIdentityV1,
    isolation_ref: _BTO.ContentRef,
) -> tuple[dict, _BTO.ContentRef]:
    descriptor = {
        "schema": _STORE.DESCRIPTOR_SCHEMA,
        "id": f"task-qualification-store-service-{run_id}",
        "version": "2.0.0",
        "namespace": _STORE.NAMESPACE,
        "protocol": _STORE.PROTOCOL_ID,
        "servicePublicKey": service_public_key.hex(),
        "verifier": _TQO.verifier_identity_to_wire(authority_store_identity),
        "supervisor": _TQO.verifier_identity_to_wire(supervisor_identity),
        "isolationPolicy": _ref_wire(isolation_ref),
        "signingKeyIds": list(sorted(ROLE_KEY_IDS)),
        "custodyKind": "one-time-seed-fd-v1",
        "adapterUid": 1001,
        "adapterGid": 1003,
        "serviceUid": 1002,
        "serviceGid": 1004,
        "userNamespace": {"device": 1, "inode": 1},
        "seedRoot": {"device": 1, "inode": 8},
        "peerInspectionProfile": "linux-pidfd-proc-cross-uid-v1",
        "maximumFrameBytes": _STORE.MAX_FRAME_BYTES,
        "maximumTerminalAcceptances": 1,
    }
    descriptor_bytes = _canonical(descriptor)
    _ADAPTER._parse_v2_descriptor(descriptor_bytes, run_id)
    ref = _STORE.recompute_object_content_ref(
        "authority-store-service", descriptor_bytes
    )
    return descriptor, ref


def _signed_server_frame(unsigned: dict, service_seed: bytes) -> bytes:
    domain = _STORE.FRAME_SIGNATURE_DOMAINS[unsigned["schema"]]
    message = domain + b"\x00" + _canonical(unsigned)
    frame = dict(unsigned)
    frame["signature"] = _BTP.sign_ed25519(service_seed, message).hex()
    return _canonical(frame)


def _echo_fields(tpl: _STORE.HandoffTuple, *, handoff: bool) -> dict:
    result = {
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
    }
    if handoff:
        result["handoffDigest"] = _digest_wire(
            _BTO.Digest("sha256", tpl.handoffDigest)
        )
    result["headSequence"] = tpl.headSequence
    result["headDigest"] = _digest_wire(_BTO.Digest("sha256", tpl.headDigest))
    return result


def _serve_once(
    fd: int,
    tpl: _STORE.HandoffTuple,
    gate_digest: bytes,
    objects: dict[str, bytes],
    service_seed: bytes,
    role_seeds: dict[str, bytes],
) -> None:
    sock = socket.socket(fileno=fd)
    try:
        hello = _STORE._decode_frame(_STORE.recv_packet(sock))
        _STORE._require_exact_keys(hello, _STORE.CLIENT_HELLO_FIELDS, "client-hello")
        _STORE._check_echo(hello, tpl, has_handoff_digest=True)
        server_hello = {
            "schema": _STORE.SERVER_HELLO_SCHEMA,
            "version": _STORE.VERSION,
            **_echo_fields(tpl, handoff=True),
            "status": "ready",
        }
        _STORE.send_packet(sock, _signed_server_frame(server_hello, service_seed))

        expected_kinds = list(_STORE.FIXED_LOOKUP_OBJECT_KINDS[:7])
        expected_kinds.append(_STORE.REVOCATION_SNAPSHOT_KIND)
        for request_id, object_kind in enumerate(expected_kinds):
            request = _STORE._decode_frame(_STORE.recv_packet(sock))
            _STORE._require_exact_keys(
                request, _STORE.LOOKUP_REQUEST_FIELDS, "lookup-request"
            )
            if request["requestId"] != request_id:
                raise CeremonyError("lookup request order mismatch")
            _STORE._check_echo(request, tpl, has_handoff_digest=False)
            key = _STORE._validate_lookup_key(request["key"], "lookup-request.key")
            if key["objectKind"] != object_kind:
                raise CeremonyError("lookup object kind order mismatch")
            if key["gateSetDigest"] != _digest_wire(
                _BTO.Digest("sha256", gate_digest)
            ):
                raise CeremonyError("lookup gate digest mismatch")
            object_bytes = objects[object_kind]
            object_ref = _STORE.recompute_object_content_ref(
                object_kind, object_bytes
            )
            if key["kind"] == "object" and key["objectId"] != object_ref.id:
                raise CeremonyError("lookup object id mismatch")
            response = {
                "schema": _STORE.LOOKUP_RESPONSE_SCHEMA,
                "version": _STORE.VERSION,
                "requestId": request_id,
                **_echo_fields(tpl, handoff=False),
                "status": "found",
                "key": key,
                "object": _ref_wire(object_ref),
                "objectBytesHex": object_bytes.hex(),
            }
            _STORE.send_packet(sock, _signed_server_frame(response, service_seed))

        terminal = _STORE._decode_frame(_STORE.recv_packet(sock))
        _STORE._require_exact_keys(
            terminal, _STORE.TERMINAL_REQUEST_FIELDS, "terminal-request"
        )
        if terminal["requestId"] != len(expected_kinds):
            raise CeremonyError("terminal request id mismatch")
        _STORE._check_echo(terminal, tpl, has_handoff_digest=True)
        unsigned_bytes = bytes.fromhex(terminal["unsignedAcceptanceBytesHex"])
        unsigned = _BTO.decode_canonical_pf_jcs(unsigned_bytes)
        statement = _STORE.acceptance_statement_digest(unsigned)
        if terminal["acceptanceStatementDigest"] != _digest_wire(
            _BTO.Digest("sha256", statement)
        ):
            raise CeremonyError("terminal statement mismatch")
        message = _STORE.ACCEPTANCE_SIGNATURE_DOMAIN + b"\x00" + statement
        signatures = [
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "signature": _BTP.sign_ed25519(role_seeds[key_id], message).hex(),
            }
            for key_id in sorted(ROLE_KEY_IDS)
        ]
        signed = dict(unsigned)
        signed["signatures"] = signatures
        signed_bytes = _canonical(signed)
        acceptance_ref = _BTO.ContentRef(
            _STORE.ACCEPTANCE_SCHEMA,
            signed["id"],
            signed["version"],
            _TQO.domain_digest(_STORE.ACCEPTANCE_FULL_DOMAIN, signed),
        )
        terminal_response = {
            "schema": _STORE.TERMINAL_RESPONSE_SCHEMA,
            "version": _STORE.VERSION,
            "requestId": len(expected_kinds),
            **_echo_fields(tpl, handoff=True),
            "status": "signed",
            "acceptanceStatementDigest": _digest_wire(
                _BTO.Digest("sha256", statement)
            ),
            "acceptance": _ref_wire(acceptance_ref),
            "acceptanceBytesHex": signed_bytes.hex(),
        }
        _STORE.send_packet(
            sock, _signed_server_frame(terminal_response, service_seed)
        )
    finally:
        sock.close()


def _fork_service(
    service_fd: int,
    tpl: _STORE.HandoffTuple,
    gate_digest: bytes,
    objects: dict[str, bytes],
    service_seed: bytes,
    role_seeds: dict[str, bytes],
) -> int:
    pid = os.fork()
    if pid == 0:
        try:
            _serve_once(
                service_fd, tpl, gate_digest, objects, service_seed, role_seeds
            )
            os._exit(0)
        except BaseException:
            os._exit(70)
    return pid


def _write_channel_file(directory: Path, name: str, payload: bytes) -> int:
    path = directory / name
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o400)
    try:
        view = memoryview(payload)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise CeremonyError("channel write failed")
            view = view[written:]
        os.fsync(fd)
    finally:
        os.close(fd)
    return os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)


def _install_fixed_fd(source_fd: int, target_fd: int) -> None:
    os.dup2(source_fd, target_fd, inheritable=True)
    if source_fd != target_fd:
        os.close(source_fd)


def _reap_service(service_pid: int, deadline_seconds: float = 5.0) -> int:
    deadline = time.monotonic() + deadline_seconds
    while time.monotonic() < deadline:
        pid, status = os.waitpid(service_pid, os.WNOHANG)
        if pid == service_pid:
            return status
        time.sleep(0.01)
    try:
        os.kill(service_pid, 15)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline:
        pid, status = os.waitpid(service_pid, os.WNOHANG)
        if pid == service_pid:
            return status
        time.sleep(0.01)
    try:
        os.kill(service_pid, 9)
    except ProcessLookupError:
        pass
    return os.waitpid(service_pid, 0)[1]


def _run_adapter_process(
    command: list[str],
    manifest_bytes: bytes,
    channel_payloads: dict[str, bytes],
    tpl: _STORE.HandoffTuple,
    gate_digest: bytes,
    objects: dict[str, bytes],
    service_seed: bytes,
    role_seeds: dict[str, bytes],
) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory(prefix="pf-taskqual-qualified-") as temp:
        directory = Path(temp)
        policy_fd = _write_channel_file(
            directory, "authority-policy.json", channel_payloads["policy"]
        )
        archive_fd = _write_channel_file(
            directory, "candidate-archive.tar", channel_payloads["archive"]
        )
        provenance_fd = _write_channel_file(
            directory, "provenance.json", channel_payloads["provenance"]
        )
        clock_fd = _write_channel_file(
            directory, "trusted-clock.json", channel_payloads["clock"]
        )
        adapter_sock, service_sock = socket.socketpair(
            socket.AF_UNIX, socket.SOCK_SEQPACKET | socket.SOCK_CLOEXEC
        )
        # Linux doubles the requested value reported by SO_{SND,RCV}BUF.  The
        # accepted isolation policy therefore requires an effective 8 MiB on
        # both endpoints before any 4 MiB single-packet frame is attempted.
        for endpoint in (adapter_sock, service_sock):
            for option in (socket.SO_SNDBUF, socket.SO_RCVBUF):
                endpoint.setsockopt(
                    socket.SOL_SOCKET, option, _STORE.MAX_FRAME_BYTES
                )
                if endpoint.getsockopt(socket.SOL_SOCKET, option) < (
                        2 * _STORE.MAX_FRAME_BYTES):
                    raise CeremonyError(
                        "authority-store seqpacket buffer is below 8 MiB"
                    )
        service_pid = None
        result = None
        try:
            _install_fixed_fd(policy_fd, FIXED_FDS["authorityPolicyFd"])
            _install_fixed_fd(adapter_sock.detach(), FIXED_FDS["authorityStoreFd"])
            _install_fixed_fd(archive_fd, FIXED_FDS["candidateArchiveFd"])
            _install_fixed_fd(provenance_fd, FIXED_FDS["provenanceBundleFd"])
            _install_fixed_fd(clock_fd, FIXED_FDS["trustedClockFd"])
            service_pid = _fork_service(
                service_sock.detach(), tpl, gate_digest, objects,
                service_seed, role_seeds,
            )
            result = subprocess.run(
                command,
                input=manifest_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                pass_fds=tuple(FIXED_FDS.values()),
                check=False,
                timeout=120,
            )
            # The parent must not keep the adapter endpoint alive while waiting
            # for a service whose peer has already exited.
            try:
                os.close(FIXED_FDS["authorityStoreFd"])
            except OSError:
                pass
            status = _reap_service(service_pid)
            service_pid = None
            if result.returncode == 0 and (
                not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0
            ):
                raise CeremonyError("authority service rejected qualified transcript")
            return result
        finally:
            service_sock.close()
            try:
                os.close(FIXED_FDS["authorityStoreFd"])
            except OSError:
                pass
            if service_pid is not None:
                _reap_service(service_pid, 0.25)
            for fd in FIXED_FDS.values():
                try:
                    os.close(fd)
                except OSError:
                    pass


def _build_qualified_context(seed_root: Path) -> dict[str, Any]:
    policy_bytes = POLICY_PATH.read_bytes()
    policy, policy_ref = _BTO.parse_bootstrap_authority_policy(policy_bytes)
    seeds = _load_production_seeds(seed_root, policy)
    service_seed = seeds["key-authority-store-service"]

    adapter, adapter_payloads = _identity(
        "adapter", _HERE.with_name("task_qualification_protected_adapter.py").read_bytes()
    )
    snapshot_parser, parser_payloads = _identity(
        "snapshot-parser", _HERE.with_name("task_qualification_objects.py").read_bytes()
    )
    clock_identity, clock_payloads = _identity("trusted-clock", _HERE.read_bytes())
    store_identity, store_payloads = _identity("authority-store", _HERE.read_bytes())
    supervisor_identity, supervisor_payloads = _identity(
        "store-supervisor", _HERE.read_bytes()
    )
    profile, pin = _build_profile_and_pin(
        policy_ref, adapter, snapshot_parser, seeds
    )
    profile_bytes = _canonical(_TQO.production_profile_to_wire(profile))
    pin_bytes = _canonical(_TQO.production_profile_pin_to_wire(pin))

    snapshot_bytes = _REVOCATION.produce_revocation_ledger_snapshot(
        id="taskqualification-qualified-revocation-v1",
        version="1.0.0",
        policy_bytes=policy_bytes,
        record_bytes=(),
        signers=tuple(
            (key_id, seeds[key_id])
            for key_id in sorted(("key-release", "key-security"))
        ),
    )
    snapshot_ref = _STORE.recompute_object_content_ref(
        _STORE.REVOCATION_SNAPSHOT_KIND, snapshot_bytes
    )
    instant = "2026-07-24T00:00:00Z"
    subjects = _build_completion_subjects(
        policy_ref, adapter, snapshot_ref, seeds, instant
    )

    run_id = "d0-10-qualified-owner-0001"
    nonce = hashlib.sha256(b"pf-d0-10-qualified-owner-0001").hexdigest()
    isolation, isolation_ref = _isolation_policy(run_id, nonce, 90)
    isolation_bytes = _canonical(isolation)
    descriptor, descriptor_ref = _descriptor(
        run_id,
        _BTP.ed25519_public_key_from_seed(service_seed),
        store_identity,
        supervisor_identity,
        isolation_ref,
    )
    descriptor_bytes = _canonical(descriptor)
    gate_digest = profile.gateSetDigest.bytes
    head_sequence = 1
    head_digest = hashlib.sha256(
        b"pf.taskqual.qualified-head.v1\x00" + snapshot_bytes
    ).digest()
    handoff = {
        "schema": _STORE.HANDOFF_SCHEMA,
        "id": f"task-qualification-protected-handoff-{run_id}",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": OPERATION,
        "runId": run_id,
        "nonce": nonce,
        "candidate": _candidate_wire(subjects["close"].identity),
        "authorityPolicy": _ref_wire(policy_ref),
        "productionProfilePin": _ref_wire(
            _TQO.production_profile_pin_content_ref(pin)
        ),
        "gateSetDigest": _digest_wire(profile.gateSetDigest),
        "adapter": _TQO.verifier_identity_to_wire(adapter),
        "snapshotParser": _TQO.verifier_identity_to_wire(snapshot_parser),
        "authorityStoreService": _ref_wire(descriptor_ref),
        "trustedClockService": _TQO.verifier_identity_to_wire(clock_identity),
        "revocationHead": {
            "headSequence": head_sequence,
            "headDigest": _digest_wire(_BTO.Digest("sha256", head_digest)),
        },
        "trustedInstant": instant,
        "channels": dict(FIXED_FDS),
        "signatures": [],
    }
    handoff["signatures"] = _sign_without_signatures_field(
        handoff,
        _STORE.HANDOFF_STATEMENT_DOMAIN,
        _STORE.HANDOFF_SIGNATURE_DOMAIN,
        ROLE_KEY_IDS,
        seeds,
    )
    handoff_bytes = _canonical(handoff)
    handoff_digest = _STORE.domain_digest(_STORE.HANDOFF_FULL_DOMAIN, handoff).bytes

    clock = {
        "schema": _STORE.CLOCK_OBSERVATION_SCHEMA,
        "id": "taskqualification-qualified-clock-v1",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": OPERATION,
        "runId": run_id,
        "nonce": nonce,
        "trustedClockService": _TQO.verifier_identity_to_wire(clock_identity),
        "observedAt": instant,
        "clockSourceDigest": _digest_wire(_digest(b"qualified-local-clock")),
        "signatures": [],
    }
    clock["signatures"] = _sign_without_signatures_field(
        clock,
        _STORE.CLOCK_STATEMENT_DOMAIN,
        _STORE.CLOCK_SIGNATURE_DOMAIN,
        ROLE_KEY_IDS,
        seeds,
    )
    clock_bytes = _canonical(clock)

    entries: dict[str, bytes] = {
        "pre-close-archive": subjects["pre"].archive_bytes,
        "closeout-archive": subjects["close"].archive_bytes,
        "pre-close-commit-object": subjects["pre"].commit_bytes,
        "closeout-commit-object": subjects["close"].commit_bytes,
        "qualification": subjects["qualificationBytes"],
        "allowed-closeout-patch": subjects["patchBytes"],
        "closeout-file-set": subjects["fileSetBytes"],
        "authority-policy": policy_bytes,
        "revocation-snapshot": snapshot_bytes,
        "production-profile": profile_bytes,
        "production-profile-pin": pin_bytes,
        "live-handoff": handoff_bytes,
        "live-session": _canonical(
            {"schema": "proof-forge.task-qualification-live-session.v1", "id": run_id}
        ),
        "trusted-clock-observation": clock_bytes,
        "current-revocation-snapshot": snapshot_bytes,
        "authority-store-service-descriptor": descriptor_bytes,
        "store-isolation-policy": isolation_bytes,
        "completion-receipt": subjects["receiptBytes"],
    }
    for payload_map in (
        adapter_payloads,
        parser_payloads,
        clock_payloads,
        store_payloads,
        supervisor_payloads,
    ):
        entries.update(payload_map)
    provenance = {
        "schema": _STORE.PROVENANCE_BUNDLE_SCHEMA,
        "id": "protected-taskqualification-provenance-qualified-0001",
        "version": "1.0.0",
        "taskId": TASK_ID,
        "operation": OPERATION,
        "runId": run_id,
        "nonce": nonce,
        "subjectDigest": _digest_wire(_digest(subjects["receiptBytes"])),
        "candidateArchiveSha256": _digest_wire(
            subjects["close"].identity.archiveDigest
        ),
        "entries": [
            {"role": role, "bytesHex": payload.hex()}
            for role, payload in sorted(entries.items())
        ],
    }
    provenance_bytes = _canonical(provenance)
    _TQO.parse_provenance_bundle(provenance, "qualified.provenance")

    tpl = _STORE.HandoffTuple(
        taskId=TASK_ID,
        operation=OPERATION,
        runId=run_id,
        nonce=nonce,
        service=_ref_wire(descriptor_ref),
        handoffDigest=handoff_digest,
        headSequence=head_sequence,
        headDigest=head_digest,
    )
    objects = {
        "authority-policy": policy_bytes,
        "production-profile-pin": pin_bytes,
        "production-profile": profile_bytes,
        "adapter": _canonical(_TQO.verifier_identity_to_wire(adapter)),
        "snapshot-parser": _canonical(
            _TQO.verifier_identity_to_wire(snapshot_parser)
        ),
        "authority-store-service": descriptor_bytes,
        "trusted-clock-service": _canonical(
            _TQO.verifier_identity_to_wire(clock_identity)
        ),
        "revocation-snapshot": snapshot_bytes,
    }
    manifest_base = {
        "schema": QUALIFIED_SCHEMA,
        "operationBytesHex": OPERATION.encode("ascii").hex(),
        "handoffBytesHex": handoff_bytes.hex(),
        **FIXED_FDS,
    }
    return {
        "manifestBase": manifest_base,
        "channelPayloads": {
            "policy": policy_bytes,
            "archive": subjects["close"].archive_bytes,
            "provenance": provenance_bytes,
            "clock": clock_bytes,
        },
        "tpl": tpl,
        "gateDigest": gate_digest,
        "objects": objects,
        "serviceSeed": service_seed,
        "roleSeeds": {key: seeds[key] for key in ROLE_KEY_IDS},
    }


def _adapter_once_from_stdin() -> int:
    manifest = _BTO.decode_canonical_pf_jcs(sys.stdin.buffer.read())
    value = _ADAPTER.protect_taskqualification_v1(
        bytes.fromhex(manifest["operationBytesHex"]),
        bytes.fromhex(manifest["handoffBytesHex"]),
        manifest["authorityPolicyFd"],
        manifest["authorityStoreFd"],
        manifest["candidateArchiveFd"],
        manifest["provenanceBundleFd"],
        manifest["trustedClockFd"],
    )
    if isinstance(value, _BTO.Rejected):
        sys.stderr.write(value.detail + "\n")
        return 2
    if type(value) is not bytes:
        sys.stderr.write("protected adapter returned a non-byte result\n")
        return 2
    sys.stdout.buffer.write(value)
    return 0


def qualified_self_test(seed_root: Path) -> int:
    context = _build_qualified_context(seed_root)
    preflight_manifest = dict(context["manifestBase"])
    preflight_manifest["expectedAcceptanceDigest"] = "sha256:" + "00" * 32
    preflight = _run_adapter_process(
        [sys.executable, "-I", "-S", str(_HERE), "--adapter-once"],
        _canonical(preflight_manifest),
        context["channelPayloads"],
        context["tpl"],
        context["gateDigest"],
        context["objects"],
        context["serviceSeed"],
        context["roleSeeds"],
    )
    if preflight.returncode != 0:
        detail = preflight.stderr.decode("utf-8", errors="replace").strip()
        raise CeremonyError(f"qualified adapter preflight rejected: {detail}")
    acceptance_bytes = preflight.stdout
    _BTO.decode_canonical_pf_jcs(acceptance_bytes)
    expected = hashlib.sha256(
        _STORE.ACCEPTANCE_FULL_DOMAIN + b"\x00" + acceptance_bytes
    ).hexdigest()
    manifest = dict(context["manifestBase"])
    manifest["expectedAcceptanceDigest"] = "sha256:" + expected
    result = _run_adapter_process(
        [
            sys.executable,
            "-I",
            "-S",
            str(SELF_TEST_PATH),
            "--qualified-input-stdin",
        ],
        _canonical(manifest),
        context["channelPayloads"],
        context["tpl"],
        context["gateDigest"],
        context["objects"],
        context["serviceSeed"],
        context["roleSeeds"],
    )
    sys.stdout.write(result.stdout.decode("utf-8", errors="replace"))
    if result.stderr:
        sys.stderr.write(result.stderr.decode("utf-8", errors="replace"))
    if result.returncode != 0:
        raise CeremonyError("qualified authority-store self-test failed")
    output_dir = _ROOT / "build/task-qualification-qualified"
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "acceptance.json").write_bytes(acceptance_bytes)
    (output_dir / "qualified-input-manifest.json").write_bytes(_canonical(manifest))
    print(
        "qualified ceremony: DEVELOPMENT-ONLY PASS; not formal/hermetic static "
        "custody; public acceptance sha256="
        + hashlib.sha256(acceptance_bytes).hexdigest()
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter-once", action="store_true")
    parser.add_argument("--qualified-self-test", action="store_true")
    parser.add_argument("--prepare-closeout", action="store_true")
    parser.add_argument("--complete-closeout", action="store_true")
    parser.add_argument(
        "--seed-root", default="/home/davirain/pf-d0-04-seeds"
    )
    parser.add_argument(
        "--closeout-output", default="build/task-qualification-closeout"
    )
    parser.add_argument(
        "--completion-output",
        default="build/task-qualification-completion",
    )
    args = parser.parse_args()
    try:
        if args.adapter_once:
            return _adapter_once_from_stdin()
        if args.qualified_self_test:
            return qualified_self_test(Path(args.seed_root))
        if args.prepare_closeout:
            import task_qualification_closeout as closeout
            return closeout.prepare_closeout(
                sys.modules[__name__],
                Path(args.seed_root),
                Path(args.closeout_output),
            )
        if args.complete_closeout:
            import task_qualification_completion as completion
            return completion.complete_closeout(
                sys.modules[__name__],
                Path(args.seed_root),
                Path(args.closeout_output),
                Path(args.completion_output),
            )
        parser.error("one command is required")
    except CeremonyError as exc:
        sys.stderr.write(f"taskqualification ceremony: {exc}\n")
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
