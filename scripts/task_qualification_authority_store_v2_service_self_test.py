#!/usr/bin/env python3
"""Static service-side protocol and durable terminal transaction tests.

The harness generates a per-run C context containing only synthetic public
objects and RFC-independent test seeds, compiles the production protocol engine
as a static ELF, and drives it with the existing Python v2 client. The positive
case uses real Linux ``SOCK_SEQPACKET`` + kernel ``SCM_CREDENTIALS`` + pidfd and
verifies that the three role signatures are emitted only after the durable
``active -> signing -> accepted`` transaction.

These synthetic objects are non-authoritative and cannot close a task. The
separate custody supervisor must eventually supply production policy objects,
one-time seed FDs, namespace/credential isolation, capability transitions and
seccomp.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
sys.path.insert(0, str(_HERE))

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_authority_store_v2 as _STORE

_TASK = "TASK-D1-01"
_OPERATION = "task-qualification"
_RUN = "service-self-test-run"
_NONCE = "service-self-test-nonce"
_INSTANT = "2026-07-24T12:00:00Z"
_HEAD_SEQUENCE = 7

_SERVICE_SEED = hashlib.sha256(b"pf-tq-v2-service-self-test").digest()
_ROLE_SEEDS = {
    "self-test-key-architecture": hashlib.sha256(b"pf-tq-v2-role-a").digest(),
    "self-test-key-quality": hashlib.sha256(b"pf-tq-v2-role-q").digest(),
    "self-test-key-security": hashlib.sha256(b"pf-tq-v2-role-s").digest(),
}
_ROLE_PRINCIPALS = {
    "self-test-key-architecture": ("self-test-principal-architecture", ("architecture",)),
    "self-test-key-quality": ("self-test-principal-quality", ("quality",)),
    "self-test-key-security": ("self-test-principal-security", ("security",)),
}


@dataclass(frozen=True)
class ObjectSpec:
    kind: str
    schema: str
    identifier: str
    version: str
    domain: bytes
    embedded_identity: bool
    wire: dict[str, Any]
    raw: bytes
    ref: dict[str, Any]


@dataclass(frozen=True)
class Vector:
    objects: tuple[ObjectSpec, ...]
    service_ref: dict[str, Any]
    profile_pin_ref: dict[str, Any]
    profile_digest: str
    adapter: dict[str, Any]
    snapshot_parser: dict[str, Any]
    pre_candidate: dict[str, Any]
    handoff_digest: bytes
    gate_digest: bytes
    head_digest: bytes
    unsigned_acceptance: dict[str, Any]


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{'PASS' if self.passed else 'FAIL'}] {self.name}{suffix}"


def _canonical(value: Any) -> bytes:
    return _BTO.canonical_pf_jcs(value)


def _digest_wire(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def _domain_digest(domain: bytes, raw: bytes) -> bytes:
    return hashlib.sha256(domain + b"\x00" + raw).digest()


def _content_ref(
    schema: str,
    identifier: str,
    version: str,
    domain: bytes,
    raw: bytes,
) -> dict[str, Any]:
    return {
        "schema": schema,
        "id": identifier,
        "version": version,
        "digest": _digest_wire(_domain_digest(domain, raw)),
    }


def _fake_payload_ref(identifier: str) -> dict[str, Any]:
    payload = ("payload:" + identifier).encode("ascii")
    digest = hashlib.sha256(
        b"pf.taskqual.artifact-payload.v1\x00"
        + identifier.encode("ascii") + b"\x00" + b"1.0.0\x00" + payload
    ).digest()
    return {
        "schema": "proof-forge.task-qualification-artifact-payload.v1",
        "id": identifier,
        "version": "1.0.0",
        "digest": _digest_wire(digest),
    }


def _identity(identifier: str) -> dict[str, Any]:
    return {
        "id": identifier,
        "executable": _fake_payload_ref(identifier + "-executable"),
        "closure": _fake_payload_ref(identifier + "-closure"),
        "sourceDigest": _digest_wire(hashlib.sha256((identifier + ":source").encode()).digest()),
        "buildPolicy": _fake_payload_ref(identifier + "-build-policy"),
    }


def _typed_object(
    kind: str,
    schema: str,
    identifier: str,
    domain: bytes,
    extra: dict[str, Any] | None = None,
) -> ObjectSpec:
    wire: dict[str, Any] = {
        "schema": schema,
        "id": identifier,
        "version": "1.0.0" if not schema.endswith("service.v2") else "2.0.0",
    }
    if extra:
        wire.update(extra)
    raw = _canonical(wire)
    ref = _content_ref(schema, identifier, wire["version"], domain, raw)
    return ObjectSpec(kind, schema, identifier, wire["version"], domain, False, wire, raw, ref)


def _identity_object(kind: str, schema: str, wire: dict[str, Any]) -> ObjectSpec:
    raw = _canonical(wire)
    ref = _content_ref(schema, wire["id"], "1.0.0", b"pf.taskqual.verifier-identity.v1", raw)
    return ObjectSpec(
        kind, schema, wire["id"], "1.0.0",
        b"pf.taskqual.verifier-identity.v1", True, wire, raw, ref,
    )


def build_vector() -> Vector:
    adapter = _identity("service-self-test-adapter")
    parser = _identity("service-self-test-snapshot-parser")
    clock = _identity("service-self-test-clock")
    policy = _typed_object(
        "authority-policy",
        "proof-forge.bootstrap-authority-policy.v1",
        "service-self-test-policy",
        b"pf.bootstrap-authority-policy.v1",
    )
    profile = _typed_object(
        "production-profile",
        "proof-forge.task-qualification-production-profile.v1",
        "service-self-test-profile",
        b"pf.taskqual.production-profile.v1",
    )
    pin = _typed_object(
        "production-profile-pin",
        "proof-forge.task-qualification-production-profile-pin.v1",
        "service-self-test-pin",
        b"pf.taskqual.production-profile-pin.v1",
        {"profile": profile.ref},
    )
    adapter_object = _identity_object(
        "adapter", "proof-forge.task-qualification.verifier-identity.v1", adapter
    )
    parser_object = _identity_object(
        "snapshot-parser",
        "proof-forge.task-qualification.verifier-identity.v1",
        parser,
    )
    service = _typed_object(
        "authority-store-service",
        "proof-forge.task-qualification-authority-store-service.v2",
        "task-qualification-store-service-service-self-test-run",
        b"pf.taskqual.authority-store-service.v2",
        {"servicePublicKey": _BTP.ed25519_public_key_from_seed(_SERVICE_SEED).hex()},
    )
    clock_object = _identity_object(
        "trusted-clock-service",
        "proof-forge.task-qualification.verifier-identity.v1",
        clock,
    )
    snapshot = _typed_object(
        "revocation-snapshot",
        "proof-forge.revocation-ledger-snapshot.v1",
        "service-self-test-snapshot",
        b"pf.revocation-ledger-snapshot.v1",
        {"records": []},
    )
    objects = (
        policy, pin, profile, adapter_object, parser_object,
        service, clock_object, snapshot,
    )
    handoff_digest = hashlib.sha256(b"service-self-test-handoff").digest()
    gate_digest = hashlib.sha256(b"service-self-test-gate-set").digest()
    head_digest = hashlib.sha256(b"service-self-test-head").digest()
    pre_candidate = {
        "commit": "1" * 40,
        "treeObjectId": "2" * 40,
        "archiveSha256": _digest_wire(hashlib.sha256(b"candidate-archive").digest()),
    }
    unsigned = {
        "schema": _STORE.ACCEPTANCE_SCHEMA,
        "id": "protected-task-qualification-task-qualification-d1-01",
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": _OPERATION,
        "pureProjectionDigest": _digest_wire(hashlib.sha256(b"pure").digest()),
        "bundleDigest": _digest_wire(hashlib.sha256(b"bundle").digest()),
        "subjectDigest": _digest_wire(hashlib.sha256(b"subject").digest()),
        "preCloseCandidate": pre_candidate,
        "closeoutCandidate": None,
        "trustedVerificationInstant": _INSTANT,
        "adapter": adapter,
        "snapshotParser": parser,
        "productionProfileDigest": profile.ref["digest"],
        "productionProfilePin": pin.ref,
        "ledgerProjectionDigest": None,
        "governanceCompletionDigest": None,
        "provenanceBundleDigest": _digest_wire(hashlib.sha256(b"provenance").digest()),
        "provenanceRoles": ["live-handoff"],
    }
    return Vector(
        objects, service.ref, pin.ref, profile.ref["digest"],
        adapter, parser, pre_candidate, handoff_digest,
        gate_digest, head_digest, unsigned,
    )


def _c_bytes(name: str, raw: bytes) -> str:
    values = ",".join(f"0x{value:02x}" for value in raw)
    return f"static const unsigned char {name}[] = {{{values}}};\n"


def _c_string(value: str) -> str:
    if not value.isascii() or any(ord(character) < 0x20 for character in value):
        raise ValueError("C fixture string must be printable ASCII")
    return json.dumps(value)


def generate_driver(vector: Vector, destination: Path) -> None:
    arrays: list[str] = []
    arrays.append(_c_bytes("service_ref_bytes", _canonical(vector.service_ref)))
    arrays.append(_c_bytes("pin_ref_bytes", _canonical(vector.profile_pin_ref)))
    arrays.append(_c_bytes("adapter_bytes", _canonical(vector.adapter)))
    arrays.append(_c_bytes("parser_bytes", _canonical(vector.snapshot_parser)))
    arrays.append(_c_bytes("candidate_bytes", _canonical(vector.pre_candidate)))
    arrays.append(_c_bytes("service_seed", _SERVICE_SEED))
    arrays.append(_c_bytes("service_public", _BTP.ed25519_public_key_from_seed(_SERVICE_SEED)))
    arrays.append(_c_bytes("handoff_digest", vector.handoff_digest))
    arrays.append(_c_bytes("gate_digest", vector.gate_digest))
    arrays.append(_c_bytes("head_digest", vector.head_digest))
    for index, spec in enumerate(vector.objects):
        arrays.append(_c_bytes(f"object_{index}_bytes", spec.raw))
    for index, key_id in enumerate(sorted(_ROLE_SEEDS)):
        arrays.append(_c_bytes(f"role_{index}_seed", _ROLE_SEEDS[key_id]))
        arrays.append(_c_bytes(
            f"role_{index}_public", _BTP.ed25519_public_key_from_seed(_ROLE_SEEDS[key_id])
        ))

    object_rows = []
    for index, spec in enumerate(vector.objects):
        object_rows.append(
            "    {"
            f"{_c_string(spec.kind)},{_c_string(spec.schema)},"
            f"{_c_string(spec.identifier)},{_c_string(spec.version)},"
            f"{_c_string(spec.domain.decode('ascii'))},{1 if spec.embedded_identity else 0},"
            f"{{object_{index}_bytes,sizeof(object_{index}_bytes)}}"
            "}"
        )
    signer_rows = []
    role_masks = {
        "architecture": "PF_TQ_STORE_V2_ROLE_ARCHITECTURE",
        "quality": "PF_TQ_STORE_V2_ROLE_QUALITY",
        "security": "PF_TQ_STORE_V2_ROLE_SECURITY",
    }
    for index, key_id in enumerate(sorted(_ROLE_SEEDS)):
        principal, roles = _ROLE_PRINCIPALS[key_id]
        signer_rows.append(
            "    {"
            f"{_c_string(key_id)},{_c_string(principal)},{role_masks[roles[0]]},"
            "{0},{0}"
            "}"
        )

    source = f'''#define _GNU_SOURCE
#include "task_qualification_authority_store_v2_service.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

{''.join(arrays)}

static const pf_tq_store_v2_object objects[] = {{
{',\n'.join(object_rows)}
}};

static pf_tq_store_v2_signer signers[] = {{
{',\n'.join(signer_rows)}
}};

static int mode_value;
static int terminal_socket_fd = -1;
static unsigned head_calls;
static unsigned peer_counts[5];
static unsigned lockdown_calls;
static int observed_pidfd = -1;

static int peer_check(void *opaque, pid_t pid, int pidfd, unsigned checkpoint,
                      char *error, size_t error_size) {{
    (void)opaque;
    if (pid <= 0 || pidfd < 0 || fcntl(pidfd, F_GETFD) != FD_CLOEXEC ||
            checkpoint < 1 || checkpoint > 4) {{
        snprintf(error, error_size, "peer callback tuple rejected");
        return -1;
    }}
    if (observed_pidfd < 0) observed_pidfd = pidfd;
    if (observed_pidfd != pidfd) {{
        snprintf(error, error_size, "peer callback pidfd changed");
        return -1;
    }}
    ++peer_counts[checkpoint];
    return 0;
}}

static int current_head(void *opaque, uint64_t *sequence,
                        unsigned char digest[32], char *error,
                        size_t error_size) {{
    (void)opaque; (void)error; (void)error_size;
    ++head_calls;
    *sequence = {_HEAD_SEQUENCE}U;
    memcpy(digest, head_digest, 32);
    if (mode_value == 1 && head_calls >= 2) digest[0] ^= 1U;
    return 0;
}}

static int terminal_lockdown(void *opaque, char *error, size_t error_size) {{
    (void)opaque;
    ++lockdown_calls;
    if (mode_value == 10 && shutdown(terminal_socket_fd, SHUT_RDWR) != 0) {{
        snprintf(error, error_size, "terminal response channel shutdown injection failed");
        return -1;
    }}
    if (mode_value == 11) {{
        snprintf(error, error_size, "terminal lockdown injection");
        return -1;
    }}
    return 0;
}}

int main(int argc, char **argv) {{
    int socket_fd, root_fd, rc;
    struct stat root;
    char error[PF_TQ_STORE_V2_ERROR_BYTES];
    char run_error[PF_TQ_STORE_V2_ERROR_BYTES];
    unsigned char *accepted = NULL;
    size_t accepted_size = 0;
    pf_tq_durable_snapshot_v2 snapshot;
    pf_tq_store_v2_context context;
    size_t index;
    if (argc != 4) return 2;
    socket_fd = atoi(argv[1]);
    terminal_socket_fd = socket_fd;
    root_fd = open(argv[2], O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    mode_value = atoi(argv[3]);
    if (root_fd < 0 || fstat(root_fd, &root) != 0) return 2;
    memset(&context, 0, sizeof(context));
    context.task_id = {_c_string(_TASK)};
    context.operation = {_c_string(_OPERATION)};
    context.run_id = {_c_string(_RUN)};
    context.nonce = {_c_string(_NONCE)};
    context.service_ref = (pf_tq_store_v2_bytes){{service_ref_bytes,sizeof(service_ref_bytes)}};
    memcpy(context.handoff_digest, handoff_digest, 32);
    memcpy(context.gate_set_digest, gate_digest, 32);
    context.head_sequence = {_HEAD_SEQUENCE}U;
    memcpy(context.head_digest, head_digest, 32);
    context.trusted_instant = {_c_string(_INSTANT)};
    context.adapter = (pf_tq_store_v2_bytes){{adapter_bytes,sizeof(adapter_bytes)}};
    context.production_profile_pin_ref = (pf_tq_store_v2_bytes){{pin_ref_bytes,sizeof(pin_ref_bytes)}};
    context.snapshot_parser = (pf_tq_store_v2_bytes){{parser_bytes,sizeof(parser_bytes)}};
    context.pre_close_candidate = (pf_tq_store_v2_bytes){{candidate_bytes,sizeof(candidate_bytes)}};
    context.closeout_candidate = (pf_tq_store_v2_bytes){{NULL,0}};
    context.production_profile_digest = {_c_string(vector.profile_digest)};
    context.objects = objects;
    context.object_count = sizeof(objects)/sizeof(objects[0]);
    memcpy(context.service_seed, service_seed, 32);
    memcpy(context.service_public_key, service_public, 32);
    for (index = 0; index < 3; ++index) context.role_signers[index] = signers[index];
    memcpy(context.role_signers[0].seed, role_0_seed, 32);
    memcpy(context.role_signers[0].public_key, role_0_public, 32);
    memcpy(context.role_signers[1].seed, role_1_seed, 32);
    memcpy(context.role_signers[1].public_key, role_1_public, 32);
    memcpy(context.role_signers[2].seed, role_2_seed, 32);
    memcpy(context.role_signers[2].public_key, role_2_public, 32);
    if (mode_value == 2) context.role_signers[1].principal_id = context.role_signers[0].principal_id;
    if (mode_value == 3) context.service_public_key[0] ^= 1U;
    if (mode_value == 6) {{
        pf_tq_store_v2_signer temporary = context.role_signers[0];
        context.role_signers[0] = context.role_signers[1];
        context.role_signers[1] = temporary;
    }}
    if (mode_value == 7) context.role_signers[1].public_key[0] ^= 1U;
    if (mode_value == 8) context.production_profile_digest =
        "sha256:0000000000000000000000000000000000000000000000000000000000000000";
    if (mode_value == 9) context.service_ref =
        (pf_tq_store_v2_bytes){{pin_ref_bytes,sizeof(pin_ref_bytes)}};
    context.durable_root_fd = root_fd;
    context.durable_uid = root.st_uid;
    context.durable_gid = root.st_gid;
    if (pf_tq_durable_tuple_init_v2(&context.durable_tuple,
            context.task_id, context.operation, context.run_id, context.nonce,
            error, sizeof(error)) != 0 ||
            pf_tq_durable_reserve_v2(root_fd, root.st_uid, root.st_gid,
                &context.durable_tuple, &snapshot, error, sizeof(error)) != 0) {{
        fprintf(stderr, "%s\\n", error); close(root_fd); return 71;
    }}
    context.adapter_uid = mode_value == 4 ? getuid() + 1U : getuid();
    context.adapter_gid = getgid();
    context.require_kernel_credentials = mode_value == 12 ? 0 : 1;
    context.require_pidfd = mode_value == 13 ? 0 : 1;
    context.peer_check = mode_value == 14 ? NULL : peer_check;
    context.current_head = mode_value == 15 ? NULL : current_head;
    context.terminal_lockdown = mode_value == 16 ? NULL : terminal_lockdown;
    if (mode_value == 17) context.role_signers[0].role_mask |= (1U << 7);
    if (mode_value == 18) context.head_sequence = UINT64_MAX;
    rc = pf_tq_store_v2_run(socket_fd, &context, &accepted, &accepted_size,
        error, sizeof(error));
    snprintf(run_error, sizeof(run_error), "%s", error);
    if (pf_tq_durable_inspect_v2(root_fd, root.st_uid, root.st_gid,
            &context.durable_tuple, &snapshot, error, sizeof(error)) != 0) {{
        free(accepted); close(root_fd); return 72;
    }}
    if (mode_value == 0) {{
        if (rc != 0 || snapshot.state != PF_TQ_DURABLE_ACCEPTED ||
                accepted == NULL || accepted_size == 0 || lockdown_calls != 1 ||
                peer_counts[1] != 1 || peer_counts[2] != 8 ||
                peer_counts[3] != 1 || peer_counts[4] != 1) {{
            fprintf(stderr, "positive service invariant failed: %s\\n", run_error);
            free(accepted); close(root_fd); return 73;
        }}
    }} else if (mode_value == 10) {{
        if (rc == 0 || snapshot.state != PF_TQ_DURABLE_ACCEPTED ||
                !snapshot.accepted_response_undelivered ||
                accepted != NULL || accepted_size != 0) {{
            fprintf(stderr, "undelivered service invariant failed: %s\\n", run_error);
            free(accepted); close(root_fd); return 74;
        }}
    }} else if (rc == 0 || snapshot.state != PF_TQ_DURABLE_REJECTED ||
            accepted != NULL || accepted_size != 0) {{
        fprintf(stderr, "negative service invariant failed: %s\\n", run_error);
        free(accepted); close(root_fd); return 75;
    }}
    free(accepted);
    close(root_fd);
    return 0;
}}
'''
    destination.write_text(source, encoding="utf-8")


def compile_driver(source: Path, binary: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-Wpedantic", "-static", "-no-pie", "-I", str(_HERE),
            "-o", str(binary), str(source),
            str(_HERE / "task_qualification_authority_store_v2_service.c"),
            str(_HERE / "task_qualification_pf_jcs_v2.c"),
            str(_HERE / "task_qualification_durable_state_v2.c"),
            "-lcrypto", "-ldl", "-pthread",
        ],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"static service compile failed: {result.stderr}")
    if result.stdout:
        raise AssertionError("static service compiler wrote stdout")
    elf = subprocess.run(
        ["/usr/bin/readelf", "-W", "-l", "-d", str(binary)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    if elf.returncode != 0 or elf.stderr:
        raise AssertionError(f"static service ELF inspection failed: {elf.stderr}")
    if any("INTERP" in line or "(NEEDED)" in line for line in elf.stdout.splitlines()):
        raise AssertionError("service ELF contains PT_INTERP or DT_NEEDED")


def _set_buffers(*sockets: socket.socket) -> None:
    for endpoint in sockets:
        endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
        for option in (socket.SO_SNDBUF, socket.SO_RCVBUF):
            endpoint.setsockopt(socket.SOL_SOCKET, option, _STORE.MAX_FRAME_BYTES)
            if endpoint.getsockopt(socket.SOL_SOCKET, option) < 2 * _STORE.MAX_FRAME_BYTES:
                raise AssertionError("seqpacket effective buffer is below 8 MiB")


def _tpl(vector: Vector) -> _STORE.HandoffTuple:
    return _STORE.HandoffTuple(
        taskId=_TASK,
        operation=_OPERATION,
        runId=_RUN,
        nonce=_NONCE,
        service=vector.service_ref,
        handoffDigest=vector.handoff_digest,
        headSequence=_HEAD_SEQUENCE,
        headDigest=vector.head_digest,
    )


def _principals() -> dict[str, _BTO.BootstrapAuthorityPrincipalV1]:
    result = {}
    for key_id, seed in _ROLE_SEEDS.items():
        principal, roles = _ROLE_PRINCIPALS[key_id]
        result[key_id] = _BTO.BootstrapAuthorityPrincipalV1(
            principal, key_id, _BTP.ed25519_public_key_from_seed(seed), roles
        )
    return result


def _drive_hello(
    client: socket.socket,
    vector: Vector,
) -> tuple[_STORE.HandoffTuple, bytes]:
    tpl = _tpl(vector)
    service_public = _BTP.ed25519_public_key_from_seed(_SERVICE_SEED)
    _STORE.send_packet(client, _STORE.build_client_hello(tpl))
    _STORE.parse_server_hello(_STORE.recv_packet(client), tpl, service_public)
    return tpl, service_public


def _drive_prefix(
    client: socket.socket,
    vector: Vector,
) -> tuple[_STORE.HandoffTuple, bytes]:
    tpl, service_public = _drive_hello(client, vector)
    for request_id, spec in enumerate(vector.objects):
        if request_id == 7:
            key = _STORE.build_revocation_head_key(
                _TASK, _OPERATION, vector.gate_digest,
                _HEAD_SEQUENCE, vector.head_digest,
            )
        else:
            key = _STORE.build_object_lookup_key(
                _TASK, _OPERATION, vector.gate_digest, spec.kind, spec.identifier
            )
        _STORE.send_packet(client, _STORE.build_lookup_request(request_id, tpl, key))
        response = _STORE.parse_lookup_response(
            _STORE.recv_packet(client), request_id, key, tpl, service_public
        )
        if bytes.fromhex(response["objectBytesHex"]) != spec.raw:
            raise AssertionError(f"lookup bytes mismatch for {spec.kind}")
    return tpl, service_public


def drive_positive(client: socket.socket, vector: Vector) -> bytes:
    tpl, service_public = _drive_prefix(client, vector)
    request = _STORE.build_terminal_request(
        len(vector.objects), tpl, vector.adapter, vector.profile_pin_ref,
        vector.snapshot_parser, vector.unsigned_acceptance,
    )
    _STORE.send_packet(client, request)
    return _STORE.parse_terminal_response(
        _STORE.recv_packet(client), len(vector.objects), tpl,
        vector.unsigned_acceptance, service_public,
        authority_principals=_principals(),
    )


def _decode_object(payload: bytes) -> dict[str, Any]:
    decoded = _BTO.decode_canonical_pf_jcs(payload)
    if not isinstance(decoded, dict):
        raise AssertionError("fixture frame did not decode to an object")
    return decoded


def _expect_peer_close(client: socket.socket) -> None:
    client.settimeout(10.0)
    try:
        packet = client.recv(_STORE.MAX_PACKET_BYTES)
    except ConnectionResetError:
        return
    except socket.timeout as exc:
        raise AssertionError("service did not close after rejecting the session") from exc
    if packet:
        raise AssertionError(f"service emitted {len(packet)} unexpected bytes after rejection")


def _send_raw_packet(client: socket.socket, packet: bytes) -> None:
    sent = client.send(packet, socket.MSG_NOSIGNAL)
    if sent != len(packet):
        raise AssertionError(f"raw seqpacket send was partial: {sent}/{len(packet)}")


def _reject_payload(payload: bytes) -> Callable[[socket.socket, Vector], None]:
    def action(client: socket.socket, _vector: Vector) -> None:
        _STORE.send_packet(client, payload)
        _expect_peer_close(client)

    return action


def _reject_raw_packet(packet: bytes) -> Callable[[socket.socket, Vector], None]:
    def action(client: socket.socket, _vector: Vector) -> None:
        _send_raw_packet(client, packet)
        _expect_peer_close(client)

    return action


def _expect_context_rejection(client: socket.socket, _vector: Vector) -> None:
    _expect_peer_close(client)


def _expect_credential_rejection(client: socket.socket, vector: Vector) -> None:
    _STORE.send_packet(client, _STORE.build_client_hello(_tpl(vector)))
    _expect_peer_close(client)


def _reject_hello_mutation(
    mutate: Callable[[dict[str, Any]], None],
) -> Callable[[socket.socket, Vector], None]:
    def action(client: socket.socket, vector: Vector) -> None:
        frame = _decode_object(_STORE.build_client_hello(_tpl(vector)))
        mutate(frame)
        _STORE.send_packet(client, _canonical(frame))
        _expect_peer_close(client)

    return action


def _reject_lookup_out_of_order(client: socket.socket, vector: Vector) -> None:
    tpl, _service_public = _drive_hello(client, vector)
    spec = vector.objects[1]
    key = _STORE.build_object_lookup_key(
        _TASK, _OPERATION, vector.gate_digest, spec.kind, spec.identifier,
    )
    _STORE.send_packet(client, _STORE.build_lookup_request(0, tpl, key))
    _expect_peer_close(client)


def _reject_lookup_replay(client: socket.socket, vector: Vector) -> None:
    tpl, service_public = _drive_hello(client, vector)
    spec = vector.objects[0]
    key = _STORE.build_object_lookup_key(
        _TASK, _OPERATION, vector.gate_digest, spec.kind, spec.identifier,
    )
    request = _STORE.build_lookup_request(0, tpl, key)
    _STORE.send_packet(client, request)
    _STORE.parse_lookup_response(
        _STORE.recv_packet(client), 0, key, tpl, service_public,
    )
    _STORE.send_packet(client, request)
    _expect_peer_close(client)


def _reject_terminal_before_lookups(client: socket.socket, vector: Vector) -> None:
    tpl, _service_public = _drive_hello(client, vector)
    request = _STORE.build_terminal_request(
        len(vector.objects), tpl, vector.adapter, vector.profile_pin_ref,
        vector.snapshot_parser, vector.unsigned_acceptance,
    )
    _STORE.send_packet(client, request)
    _expect_peer_close(client)


def _terminal_request(vector: Vector, tpl: _STORE.HandoffTuple) -> bytes:
    return _STORE.build_terminal_request(
        len(vector.objects), tpl, vector.adapter, vector.profile_pin_ref,
        vector.snapshot_parser, vector.unsigned_acceptance,
    )


def _reject_terminal_mutation(
    mutate: Callable[[dict[str, Any]], None],
) -> Callable[[socket.socket, Vector], None]:
    def action(client: socket.socket, vector: Vector) -> None:
        tpl, _service_public = _drive_prefix(client, vector)
        frame = _decode_object(_terminal_request(vector, tpl))
        mutate(frame)
        _STORE.send_packet(client, _canonical(frame))
        _expect_peer_close(client)

    return action


def _mutate_unsigned_acceptance(
    frame: dict[str, Any], field: str, value: Any,
) -> None:
    unsigned = _decode_object(bytes.fromhex(frame["unsignedAcceptanceBytesHex"]))
    unsigned[field] = value
    frame["unsignedAcceptanceBytesHex"] = _canonical(unsigned).hex()


def _reject_terminal_extra_packet(client: socket.socket, vector: Vector) -> None:
    tpl, _service_public = _drive_prefix(client, vector)
    _STORE.send_packet(client, _terminal_request(vector, tpl))
    _STORE.send_packet(client, _canonical({"extra": True}))
    _expect_peer_close(client)


def _terminal_then_expect_close(client: socket.socket, vector: Vector) -> None:
    tpl, _service_public = _drive_prefix(client, vector)
    _STORE.send_packet(client, _terminal_request(vector, tpl))
    _expect_peer_close(client)


def run_driver(
    binary: Path,
    base: Path,
    vector: Vector,
    mode: int,
    client_action: Callable[[socket.socket, Vector], Any],
) -> tuple[Any, subprocess.CompletedProcess[bytes], Path]:
    root = base / f"state-{mode}-{len(list(base.glob('state-*')))}"
    root.mkdir(mode=0o700)
    os.chmod(root, 0o700)
    client, service = socket.socketpair(
        socket.AF_UNIX, socket.SOCK_SEQPACKET | socket.SOCK_CLOEXEC
    )
    _set_buffers(client, service)
    process = subprocess.Popen(
        [str(binary), str(service.fileno()), str(root), str(mode)],
        cwd=_ROOT,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(service.fileno(),),
    )
    service.close()
    value: Any = None
    action_error: BaseException | None = None
    try:
        value = client_action(client, vector)
    except BaseException as exc:
        action_error = exc
    finally:
        client.close()
    stdout, stderr = process.communicate(timeout=30)
    completed = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
    if action_error is not None:
        raise AssertionError(
            f"client failed with {type(action_error).__name__}: {action_error}; "
            f"service rc={process.returncode}, stderr={stderr!r}"
        ) from action_error
    return value, completed, root


def _case(name: str, invoke: Callable[[], None]) -> Result:
    try:
        invoke()
    except Exception as exc:
        return Result(name, False, f"{type(exc).__name__}: {exc}")
    return Result(name, True)


def run_cases(binary: Path, base: Path, vector: Vector) -> list[Result]:
    def invoke(
        mode: int,
        action: Callable[[socket.socket, Vector], Any],
        *,
        expected: str,
    ) -> Any:
        value, completed, root = run_driver(binary, base, vector, mode, action)
        if completed.returncode != 0 or completed.stdout or completed.stderr:
            raise AssertionError(
                f"service driver failed rc={completed.returncode}: {completed.stderr!r}"
            )
        statuses = sorted(path.name for path in root.iterdir() if path.name != ".lock")
        accepted = [name for name in statuses if ".accepted.json" in name]
        rejected = [name for name in statuses if ".rejected.json" in name]
        undelivered = [
            name for name in statuses if ".accepted-response-undelivered.json" in name
        ]
        if expected == "accepted":
            if len(accepted) != 1 or rejected or undelivered:
                raise AssertionError(f"accepted durable audit mismatch: {statuses}")
        elif expected == "rejected":
            if len(rejected) != 1 or accepted or undelivered:
                raise AssertionError(f"rejected durable audit mismatch: {statuses}")
        elif expected == "accepted-undelivered":
            if len(accepted) != 1 or rejected or len(undelivered) != 1:
                raise AssertionError(f"undelivered durable audit mismatch: {statuses}")
        else:
            raise AssertionError(f"unknown expected durable outcome: {expected}")
        return value

    def positive() -> None:
        acceptance = invoke(0, drive_positive, expected="accepted")
        decoded = _decode_object(acceptance)
        if decoded["authorityClass"] != "production-candidate-bound":
            raise AssertionError("signed acceptance authority class mismatch")
        signatures = decoded.get("signatures")
        if not isinstance(signatures, list) or len(signatures) != 3:
            raise AssertionError("signed acceptance lacks the exact A+Q+S quorum")

    def case(
        name: str,
        mode: int,
        action: Callable[[socket.socket, Vector], Any],
        *,
        expected: str = "rejected",
    ) -> Result:
        return _case(name, lambda: invoke(mode, action, expected=expected))

    hello = _STORE.build_client_hello(_tpl(vector))
    malformed_unsorted = (
        b'{"version":"2.0.0","schema":'
        b'"proof-forge.task-qualification-store-client-hello.v2"}'
    )
    malformed_duplicate = b'{"schema":"x","schema":"x"}'
    zero_digest = "sha256:" + "0" * 64

    results = [_case("positive-terminal-transaction", positive)]
    results.extend([
        case("framing-zero-length", 20, _reject_raw_packet(b"\x00\x00\x00\x00")),
        case(
            "framing-length-mismatch", 21,
            _reject_raw_packet((len(hello) + 1).to_bytes(4, "big") + hello),
        ),
        case(
            "framing-over-bound", 22,
            _reject_raw_packet((_STORE.MAX_FRAME_BYTES + 1).to_bytes(4, "big")),
        ),
        case(
            "framing-two-frames-one-packet", 23,
            _reject_raw_packet(_STORE.encode_packet(hello) + _STORE.encode_packet(hello)),
        ),
        case("jcs-unsorted-object", 24, _reject_payload(malformed_unsorted)),
        case("jcs-duplicate-key", 25, _reject_payload(malformed_duplicate)),
        case(
            "v1-client-hello-cross-rejected", 26,
            _reject_hello_mutation(
                lambda frame: frame.__setitem__("schema", _STORE.V1_CLIENT_HELLO_SCHEMA)
            ),
        ),
        case(
            "client-hello-extra-field", 27,
            _reject_hello_mutation(lambda frame: frame.__setitem__("extra", None)),
        ),
        case(
            "client-hello-tuple-substitution", 28,
            _reject_hello_mutation(
                lambda frame: frame.__setitem__("nonce", "substituted-nonce")
            ),
        ),
        case("lookup-fixed-order", 30, _reject_lookup_out_of_order),
        case("lookup-request-replay", 31, _reject_lookup_replay),
        case("terminal-before-lookups", 32, _reject_terminal_before_lookups),
        case(
            "terminal-request-id-substitution", 40,
            _reject_terminal_mutation(
                lambda frame: frame.__setitem__("requestId", len(vector.objects) + 1)
            ),
        ),
        case(
            "terminal-adapter-substitution", 41,
            _reject_terminal_mutation(
                lambda frame: frame.__setitem__(
                    "adapter", _identity("substituted-terminal-adapter")
                )
            ),
        ),
        case(
            "terminal-profile-pin-substitution", 42,
            _reject_terminal_mutation(
                lambda frame: frame.__setitem__(
                    "productionProfilePin", copy.deepcopy(vector.service_ref)
                )
            ),
        ),
        case(
            "terminal-parser-substitution", 43,
            _reject_terminal_mutation(
                lambda frame: frame.__setitem__(
                    "snapshotParser", _identity("substituted-snapshot-parser")
                )
            ),
        ),
        case(
            "terminal-statement-digest-substitution", 44,
            _reject_terminal_mutation(
                lambda frame: frame.__setitem__("acceptanceStatementDigest", zero_digest)
            ),
        ),
        case(
            "terminal-unsigned-instant-substitution", 45,
            _reject_terminal_mutation(
                lambda frame: _mutate_unsigned_acceptance(
                    frame, "trustedVerificationInstant", "2026-07-24T12:00:01Z"
                )
            ),
        ),
        case(
            "terminal-unsigned-profile-substitution", 46,
            _reject_terminal_mutation(
                lambda frame: _mutate_unsigned_acceptance(
                    frame, "productionProfileDigest", zero_digest
                )
            ),
        ),
        case(
            "terminal-extra-field", 47,
            _reject_terminal_mutation(lambda frame: frame.__setitem__("extra", False)),
        ),
        case("terminal-extra-packet", 50, _reject_terminal_extra_packet),
        case("final-head-drift", 1, _terminal_then_expect_close),
        case("principal-reuse", 2, _expect_context_rejection),
        case("service-public-key-substitution", 3, _expect_context_rejection),
        case("kernel-credential-substitution", 4, _expect_credential_rejection),
        case("signer-order-substitution", 6, _expect_context_rejection),
        case("role-public-key-substitution", 7, _expect_context_rejection),
        case("profile-digest-substitution", 8, _expect_context_rejection),
        case("service-ref-substitution", 9, _expect_context_rejection),
        case("credentials-check-disabled", 12, _expect_context_rejection),
        case("pidfd-check-disabled", 13, _expect_context_rejection),
        case("peer-observer-missing", 14, _expect_context_rejection),
        case("current-head-observer-missing", 15, _expect_context_rejection),
        case("terminal-lockdown-observer-missing", 16, _expect_context_rejection),
        case("unknown-role-mask-bit", 17, _expect_context_rejection),
        case("unsafe-head-sequence", 18, _expect_context_rejection),
        case("terminal-lockdown-failure", 11, _terminal_then_expect_close),
        case(
            "accepted-response-undelivered", 10, _terminal_then_expect_close,
            expected="accepted-undelivered",
        ),
    ])
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch-root", type=Path)
    arguments = parser.parse_args()
    vector = build_vector()
    parent = arguments.scratch_root
    if parent is not None:
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="pf-tq-store-service-v2-",
        dir=None if parent is None else str(parent),
    ) as temporary:
        base = Path(temporary)
        source = base / "generated_service_driver.c"
        binary = base / "pf-taskqualification-store-v2-test"
        try:
            generate_driver(vector, source)
            compile_driver(source, binary)
            results = run_cases(binary, base, vector)
        except Exception as exc:
            print(f"task-qualification authority-store-v2 service self-test: PRECHECK-FAIL: {exc}")
            return 1
    passed = sum(result.passed for result in results)
    print(
        "task-qualification authority-store-v2 service self-test: "
        f"{passed}/{len(results)} passed"
    )
    for result in results:
        print(result)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
