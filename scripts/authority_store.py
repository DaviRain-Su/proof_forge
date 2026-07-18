#!/usr/bin/env python3
"""Authority-store protected service (pf.authority-store.rpc.v1).

This module implements the server and client ends of the authority-store RPC
protocol over an authenticated local byte-stream socket (Unix domain socket
in this development slice).  Every frame is
``u32be(payload.size) || canonical_pf_jcs(payload)`` and the payload never
exceeds the descriptor maximum ``4194304``.

Wire objects (all closed):

- hello ``{schema,descriptor,runId,nonce,signature}`` signed with the service
  key over ``"pf.authority-store-hello.v1" || NUL || canonical(unsigned)``;
- request ``{schema,requestId,runId,nonce,leaseId,operation,objectSchema,
  lookupKeyHex,objectBytesHex}`` with requestId exactly 0,1,2,... per
  connection;
- response ``{schema,requestId,runId,nonce,leaseId,result,objects,
  headSequence,headDigest,signature}`` signed with the service key over
  ``"pf.authority-store-response.v1" || NUL || canonical(unsigned)``.

hello/response signature wires are the 64-byte Ed25519 signature as 128
lowercase hex characters, not ApprovalSignatureV1 objects.

Lookup-key tuples are frozen per object schema: the four spec-pinned forms
(gate-catalog-finalization lines 1155, 1214, 1273, 1340) are

- ``bootstrap-task-verifier-receipt.v1`` ->
  ``[authorityPolicy,requiredTestSet,taskId,candidate,taskApproval,stage0Handoff]``
- ``bootstrap-approval-set.v1`` -> ``[setContentRef]``
- ``bootstrap-approval-verifier-receipt.v1`` ->
  ``[authorityPolicy,candidate,requiredTestSet,approvalSet,stage0Handoff]``
- ``formal-gate-catalog-approval.v1`` ->
  ``[authorityPolicy,requiredTestSet,catalog]``

and the remaining two allowlisted schemas use the same single-ref pattern:
``required-test-set.v1`` -> ``[requiredTestSetContentRef]`` and
``bootstrap-task-approval.v1`` -> ``[taskApprovalRefV1]``.  Content digests
inside every ref are recomputed from the exact object bytes with the frozen
per-schema digest domains; the tuple bytes are the canonical PF-JCS of the
array shown above.

The append-only log head is chained and pinned by this module:

```text
logHeadDigest(0) = SHA-256(
  "pf.authority-store-log-head.v1" || NUL || u64be(0))
logEntryHash(n)  = SHA-256(
  "pf.authority-store-log-entry.v1" || NUL ||
  utf8(objectSchema) || NUL || lookupKeyBytes || objectBytes)
logHeadDigest(n) = SHA-256(
  "pf.authority-store-log-head.v1" || NUL || u64be(n) ||
  raw32(logHeadDigest(n-1)) || raw32(logEntryHash(n)))   (n >= 1)
```

``headSequence`` is the count of successful appends; ``headDigest`` is the
SPEC-COMMON-001 Digest wire form of ``logHeadDigest(headSequence)``.

Key custody discipline mirrors the producer module: the service signing seed
is an explicit constructor parameter, used only in memory for the lifetime of
the server object; this module never reads key material from disk or the
environment.  The client API exposes no pathname/store-root semantics: the
only address it accepts is the already-connected Unix socket path of the
local RPC channel.  This slice does not implement Stage-0 integration: the
server is a local subprocess-model daemon and makes no claim about peer
executable identity beyond the protocol-level signed hello.
"""

from __future__ import annotations

import hashlib
import importlib.util
import secrets
import socket
import sys
import threading
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Dict, NoReturn, Optional, Tuple


_PRODUCER_ABI_NAMES = (
    "sign_ed25519",
    "ed25519_public_key_from_seed",
    "_CONSUMER",
)


def _load_bootstrap_task_producers() -> ModuleType:
    """Load the exact sibling producer module without a sys.path authority seam."""
    module_path = Path(__file__).resolve(strict=True)
    producer_path = module_path.with_name("bootstrap_task_producers.py")
    spec = importlib.util.spec_from_file_location(
        "proof_forge_bootstrap_task_producers_for_authority_store",
        producer_path,
    )
    if spec is None or spec.loader is None or spec.origin is None:
        raise ImportError("exact bootstrap task producer loader is unavailable")
    if Path(spec.origin).resolve(strict=True) != producer_path.resolve(strict=True):
        raise ImportError("exact bootstrap task producer origin changed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name in _PRODUCER_ABI_NAMES:
        if getattr(module, name, None) is None:
            raise ImportError("exact bootstrap task producer ABI changed")
    return module


_PRODUCER = _load_bootstrap_task_producers()
_CONSUMER = _PRODUCER._CONSUMER

Digest = _CONSUMER.Digest
ContentRef = _CONSUMER.ContentRef
canonical_pf_jcs = _CONSUMER.canonical_pf_jcs
decode_canonical_pf_jcs = _CONSUMER.decode_canonical_pf_jcs
verify_ed25519 = _CONSUMER.verify_ed25519
sign_ed25519 = _PRODUCER.sign_ed25519
ed25519_public_key_from_seed = _PRODUCER.ed25519_public_key_from_seed

PROTOCOL_ID = "pf.authority-store.rpc.v1"
MAXIMUM_FRAME_BYTES = 4 * 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
DESCRIPTOR_SCHEMA = "proof-forge.authority-store-service.v1"
HELLO_SCHEMA = "proof-forge.authority-store-hello.v1"
REQUEST_SCHEMA = "proof-forge.authority-store-request.v1"
RESPONSE_SCHEMA = "proof-forge.authority-store-response.v1"
REQUIRED_TEST_SET_SCHEMA = "proof-forge.required-test-set.v1"
FORMAL_CATALOG_APPROVAL_SCHEMA = "proof-forge.formal-gate-catalog-approval.v1"
TASK_APPROVAL_SCHEMA = "proof-forge.bootstrap-task-approval.v1"
TASK_RECEIPT_SCHEMA = "proof-forge.bootstrap-task-verifier-receipt.v1"
APPROVAL_SET_SCHEMA = "proof-forge.bootstrap-approval-set.v1"
VERIFIER_RECEIPT_SCHEMA = "proof-forge.bootstrap-approval-verifier-receipt.v1"
ALLOWLIST_SCHEMAS = (
    REQUIRED_TEST_SET_SCHEMA,
    FORMAL_CATALOG_APPROVAL_SCHEMA,
    TASK_APPROVAL_SCHEMA,
    TASK_RECEIPT_SCHEMA,
    APPROVAL_SET_SCHEMA,
    VERIFIER_RECEIPT_SCHEMA,
)
RESULTS = ("stored", "found", "not-found", "conflict", "revoked", "multiple")
OPERATIONS = ("lookup", "publish")

_HELLO_DOMAIN = b"pf.authority-store-hello.v1\x00"
_RESPONSE_DOMAIN = b"pf.authority-store-response.v1\x00"
_DESCRIPTOR_DOMAIN = b"pf.authority-store-service.v1\x00"
_LOG_HEAD_DOMAIN = b"pf.authority-store-log-head.v1\x00"
_LOG_ENTRY_DOMAIN = b"pf.authority-store-log-entry.v1\x00"
_REQUIRED_SET_DIGEST_DOMAIN = b"pf.required-test-set.v1\x00"
_TASK_APPROVAL_DIGEST_DOMAIN = b"pf.bootstrap-task-approval.v1\x00"
_TASK_RECEIPT_DIGEST_DOMAIN = b"pf.bootstrap-task-verifier-receipt.v1\x00"
_APPROVAL_SET_DIGEST_DOMAIN = b"pf.bootstrap-approval-set.v1\x00"

_DESCRIPTOR_FIELDS = (
    "schema",
    "id",
    "version",
    "protocol",
    "serviceExecutableDigest",
    "servicePublicKey",
    "namespaceId",
    "maximumFrameBytes",
)
_HELLO_FIELDS = ("schema", "descriptor", "runId", "nonce", "signature")
_REQUEST_FIELDS = (
    "schema",
    "requestId",
    "runId",
    "nonce",
    "leaseId",
    "operation",
    "objectSchema",
    "lookupKeyHex",
    "objectBytesHex",
)
_RESPONSE_FIELDS = (
    "schema",
    "requestId",
    "runId",
    "nonce",
    "leaseId",
    "result",
    "objects",
    "headSequence",
    "headDigest",
    "signature",
)


class AuthorityStoreError(Exception):
    """Stable protocol failure; internal details never grant authority."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise AuthorityStoreError(code, detail)


def _wire(detail: str) -> NoReturn:
    _fail("PF-AUTH-STORE-WIRE", detail)


def _sequence(detail: str) -> NoReturn:
    _fail("PF-AUTH-STORE-SEQUENCE", detail)


def _authority(detail: str) -> NoReturn:
    _fail("PF-AUTH-STORE-AUTHORITY", detail)


def _lease(detail: str) -> NoReturn:
    _fail("PF-AUTH-STORE-LEASE", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-AUTH-STORE-IO", detail)


def _require_exact_keys(value: object, fields: Tuple[str, ...], where: str) -> dict:
    if type(value) is not dict:
        _wire(f"{where} must be a closed object")
    assert isinstance(value, dict)
    if set(value.keys()) != set(fields):
        _wire(f"{where} must contain exactly {fields}")
    return value


def _require_consumer(validation, code: str, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _fail(code, detail)


def _require_safe_id(value: object, where: str) -> str:
    return _require_consumer(
        lambda: _CONSUMER._require_safe_id(value, where),
        "PF-AUTH-STORE-WIRE",
        f"{where} must be an ASCII safe-id",
    )


def _require_profile_id(value: object, where: str) -> str:
    return _require_consumer(
        lambda: _CONSUMER._require_ascii_text(
            value, _CONSUMER.PROFILE_ID_RE, where, 127
        ),
        "PF-AUTH-STORE-WIRE",
        f"{where} must use the ContentRef id grammar",
    )


def _require_semver(value: object, where: str) -> str:
    return _require_consumer(
        lambda: _CONSUMER._require_semver(value, where),
        "PF-AUTH-STORE-WIRE",
        f"{where} must be exact SemVer",
    )


def _require_lowercase_hex(value: object, length: int, where: str) -> str:
    if (type(value) is not str or len(value) != length
            or any(character not in "0123456789abcdef" for character in value)):
        _wire(f"{where} must be {length} lowercase hex characters")
    assert isinstance(value, str)
    return value


def _require_hex_bytes(value: object, where: str) -> bytes:
    if type(value) is not str or not value or len(value) % 2 != 0:
        _wire(f"{where} must be non-empty even-length hex")
    assert isinstance(value, str)
    if any(character not in "0123456789abcdef" for character in value):
        _wire(f"{where} must be lowercase hex")
    decoded = bytes.fromhex(value)
    if len(decoded) > MAXIMUM_FRAME_BYTES:
        _wire(f"{where} exceeds the descriptor maximum")
    return decoded


def _require_u64(value: object, where: str) -> int:
    if type(value) is not int or not 0 <= value <= MAX_SAFE_INTEGER:
        _wire(f"{where} must be a UInt64 not above 2^53-1")
    assert isinstance(value, int)
    return value


def _parse_digest_field(value: object, where: str) -> Digest:
    return _require_consumer(
        lambda: _CONSUMER.parse_digest(value),
        "PF-AUTH-STORE-WIRE",
        f"{where} must be the SPEC-COMMON Digest wire form",
    )


def _parse_descriptor(value: object, where: str) -> dict:
    obj = _require_exact_keys(value, _DESCRIPTOR_FIELDS, where)
    if obj["schema"] != DESCRIPTOR_SCHEMA:
        _wire(f"{where}.schema is not the authority-store service schema")
    identifier = _require_profile_id(obj["id"], f"{where}.id")
    version = _require_semver(obj["version"], f"{where}.version")
    if obj["protocol"] != PROTOCOL_ID:
        _wire(f"{where}.protocol is not pf.authority-store.rpc.v1")
    executable_digest = _parse_digest_field(
        obj["serviceExecutableDigest"], f"{where}.serviceExecutableDigest"
    )
    public_key_hex = _require_lowercase_hex(
        obj["servicePublicKey"], 64, f"{where}.servicePublicKey"
    )
    namespace = _require_safe_id(obj["namespaceId"], f"{where}.namespaceId")
    if obj["maximumFrameBytes"] != MAXIMUM_FRAME_BYTES:
        _wire(f"{where}.maximumFrameBytes must be exactly {MAXIMUM_FRAME_BYTES}")
    return {
        "schema": DESCRIPTOR_SCHEMA,
        "id": identifier,
        "version": version,
        "protocol": PROTOCOL_ID,
        "serviceExecutableDigest": obj["serviceExecutableDigest"],
        "servicePublicKey": public_key_hex,
        "namespaceId": namespace,
        "maximumFrameBytes": MAXIMUM_FRAME_BYTES,
    }


def descriptor_content_ref(descriptor_wire: dict) -> ContentRef:
    """Recompute the exact descriptor ContentRef from its wire object."""
    descriptor = _parse_descriptor(descriptor_wire, "descriptor")
    digest = Digest(
        "sha256",
        hashlib.sha256(
            _DESCRIPTOR_DOMAIN + canonical_pf_jcs(descriptor)
        ).digest(),
    )
    return ContentRef(
        DESCRIPTOR_SCHEMA,
        descriptor["id"],
        descriptor["version"],
        digest,
    )


def derive_lookup_key(object_schema: str, object_bytes: bytes) -> bytes:
    """Recompute the frozen per-schema lookup tuple bytes from exact bytes."""
    obj = _require_consumer(
        lambda: decode_canonical_pf_jcs(object_bytes),
        "PF-AUTH-STORE-WIRE",
        "object bytes are not canonical PF-JCS",
    )
    if type(obj) is not dict or obj.get("schema") != object_schema:
        _wire("object schema does not match the requested objectSchema")

    def digest_text(domain: bytes) -> str:
        return "sha256:" + hashlib.sha256(domain + object_bytes).hexdigest()

    if object_schema == REQUIRED_TEST_SET_SCHEMA:
        tuple_value = [{
            "schema": obj["schema"],
            "id": obj["id"],
            "version": obj["version"],
            "digest": digest_text(_REQUIRED_SET_DIGEST_DOMAIN),
        }]
    elif object_schema == FORMAL_CATALOG_APPROVAL_SCHEMA:
        tuple_value = [
            obj["authorityPolicy"],
            obj["requiredTestSet"],
            obj["catalog"],
        ]
    elif object_schema == TASK_APPROVAL_SCHEMA:
        tuple_value = [{
            "taskId": obj["taskId"],
            "digest": digest_text(_TASK_APPROVAL_DIGEST_DOMAIN),
        }]
    elif object_schema == TASK_RECEIPT_SCHEMA:
        tuple_value = [
            obj["authorityPolicy"],
            obj["requiredTestSet"],
            obj["taskId"],
            obj["candidate"],
            obj["taskApproval"],
            obj["stage0Handoff"],
        ]
    elif object_schema == APPROVAL_SET_SCHEMA:
        tuple_value = [{
            "schema": obj["schema"],
            "id": obj["id"],
            "version": obj["version"],
            "digest": digest_text(_APPROVAL_SET_DIGEST_DOMAIN),
        }]
    elif object_schema == VERIFIER_RECEIPT_SCHEMA:
        tuple_value = [
            obj["authorityPolicy"],
            obj["candidate"],
            obj["requiredTestSet"],
            obj["approvalSet"],
            obj["stage0Handoff"],
        ]
    else:
        _wire("objectSchema is outside the closed allowlist")
    return canonical_pf_jcs(tuple_value)


def _strict_key_bytes(lookup_key_hex: object) -> bytes:
    key_bytes = _require_hex_bytes(lookup_key_hex, "lookupKeyHex")
    decoded = _require_consumer(
        lambda: decode_canonical_pf_jcs(key_bytes),
        "PF-AUTH-STORE-WIRE",
        "lookupKeyHex bytes are not canonical PF-JCS",
    )
    if canonical_pf_jcs(decoded) != key_bytes:
        _wire("lookupKeyHex bytes are not canonical PF-JCS")
    return key_bytes


def _log_head_genesis() -> bytes:
    return hashlib.sha256(_LOG_HEAD_DOMAIN + (0).to_bytes(8, "big")).digest()


def _log_entry_hash(
    object_schema: str,
    key_bytes: bytes,
    object_bytes: bytes,
) -> bytes:
    return hashlib.sha256(
        _LOG_ENTRY_DOMAIN
        + object_schema.encode("utf-8")
        + b"\x00"
        + key_bytes
        + object_bytes
    ).digest()


def _log_head_next(
    sequence: int,
    previous_head: bytes,
    entry_hash: bytes,
) -> bytes:
    return hashlib.sha256(
        _LOG_HEAD_DOMAIN
        + sequence.to_bytes(8, "big")
        + previous_head
        + entry_hash
    ).digest()


def _digest_wire_text(raw: bytes) -> str:
    return "sha256:" + raw.hex()


@dataclass(frozen=True)
class StoreResponse:
    requestId: int
    runId: str
    nonce: str
    leaseId: Optional[str]
    result: str
    objects: Tuple[bytes, ...]
    headSequence: int
    headDigest: Digest


def _read_exact(conn: socket.socket, count: int) -> bytes:
    chunks = []
    remaining = count
    while remaining:
        try:
            chunk = conn.recv(remaining)
        except socket.timeout:
            _fail("PF-AUTH-STORE-TIMEOUT", "timed out waiting for frame bytes")
        except OSError as error:
            _io(f"frame read failed: {error}")
        if not chunk:
            _io("connection closed mid-frame")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _read_frame(conn: socket.socket) -> bytes:
    header = _read_exact(conn, 4)
    size = int.from_bytes(header, "big")
    if size == 0 or size > MAXIMUM_FRAME_BYTES:
        _wire("frame payload size violates the descriptor maximum")
    return _read_exact(conn, size)


def _write_frame(conn: socket.socket, payload: bytes) -> None:
    if not 1 <= len(payload) <= MAXIMUM_FRAME_BYTES:
        _wire("outgoing frame payload violates the descriptor maximum")
    try:
        conn.sendall(len(payload).to_bytes(4, "big") + payload)
    except OSError as error:
        _io(f"frame write failed: {error}")


def _decode_payload(payload: bytes, where: str) -> object:
    return _require_consumer(
        lambda: decode_canonical_pf_jcs(payload),
        "PF-AUTH-STORE-WIRE",
        f"{where} payload is not canonical PF-JCS",
    )


def _encode_hello(descriptor_wire: dict, run_id: str, nonce: str,
                  service_seed: bytes) -> bytes:
    unsigned = {
        "schema": HELLO_SCHEMA,
        "descriptor": descriptor_wire,
        "runId": run_id,
        "nonce": nonce,
    }
    signature = sign_ed25519(
        service_seed,
        _HELLO_DOMAIN + canonical_pf_jcs(unsigned),
    )
    return canonical_pf_jcs({**unsigned, "signature": signature.hex()})


def _decode_hello(payload: bytes) -> dict:
    obj = _require_exact_keys(
        _decode_payload(payload, "hello"), _HELLO_FIELDS, "hello"
    )
    if obj["schema"] != HELLO_SCHEMA:
        _wire("hello.schema is not the authority-store hello schema")
    descriptor = _parse_descriptor(obj["descriptor"], "hello.descriptor")
    run_id = _require_safe_id(obj["runId"], "hello.runId")
    nonce = _require_lowercase_hex(obj["nonce"], 64, "hello.nonce")
    signature_hex = _require_lowercase_hex(
        obj["signature"], 128, "hello.signature"
    )
    return {
        "descriptor": descriptor,
        "runId": run_id,
        "nonce": nonce,
        "signature": bytes.fromhex(signature_hex),
    }


def _decode_request(payload: bytes) -> dict:
    obj = _require_exact_keys(
        _decode_payload(payload, "request"), _REQUEST_FIELDS, "request"
    )
    if obj["schema"] != REQUEST_SCHEMA:
        _wire("request.schema is not the authority-store request schema")
    request_id = _require_u64(obj["requestId"], "request.requestId")
    run_id = _require_safe_id(obj["runId"], "request.runId")
    nonce = _require_lowercase_hex(obj["nonce"], 64, "request.nonce")
    lease_id = obj["leaseId"]
    if lease_id is not None:
        lease_id = _require_lowercase_hex(lease_id, 64, "request.leaseId")
    operation = obj["operation"]
    if operation not in OPERATIONS:
        _wire("request.operation is not lookup|publish")
    object_schema = obj["objectSchema"]
    if object_schema not in ALLOWLIST_SCHEMAS:
        _wire("request.objectSchema is outside the closed allowlist")
    lookup_key_hex = obj["lookupKeyHex"]
    object_bytes_hex = obj["objectBytesHex"]
    if operation == "lookup":
        if lookup_key_hex is None or object_bytes_hex is not None:
            _wire("lookup requires lookupKeyHex and forbids objectBytesHex")
    else:
        if object_bytes_hex is None or lookup_key_hex is None:
            _wire("publish requires both lookupKeyHex and objectBytesHex")
    return {
        "requestId": request_id,
        "runId": run_id,
        "nonce": nonce,
        "leaseId": lease_id,
        "operation": operation,
        "objectSchema": object_schema,
        "lookupKeyHex": lookup_key_hex,
        "objectBytesHex": object_bytes_hex,
    }


def _encode_response(
    request_id: int,
    run_id: str,
    nonce: str,
    lease_id: Optional[str],
    result: str,
    objects: Tuple[bytes, ...],
    head_sequence: int,
    head_digest: bytes,
    service_seed: bytes,
) -> bytes:
    unsigned = {
        "schema": RESPONSE_SCHEMA,
        "requestId": request_id,
        "runId": run_id,
        "nonce": nonce,
        "leaseId": lease_id,
        "result": result,
        "objects": [item.hex() for item in objects],
        "headSequence": head_sequence,
        "headDigest": _digest_wire_text(head_digest),
    }
    signature = sign_ed25519(
        service_seed,
        _RESPONSE_DOMAIN + canonical_pf_jcs(unsigned),
    )
    return canonical_pf_jcs({**unsigned, "signature": signature.hex()})


def _decode_response(payload: bytes) -> dict:
    obj = _require_exact_keys(
        _decode_payload(payload, "response"), _RESPONSE_FIELDS, "response"
    )
    if obj["schema"] != RESPONSE_SCHEMA:
        _wire("response.schema is not the authority-store response schema")
    request_id = _require_u64(obj["requestId"], "response.requestId")
    run_id = _require_safe_id(obj["runId"], "response.runId")
    nonce = _require_lowercase_hex(obj["nonce"], 64, "response.nonce")
    lease_id = obj["leaseId"]
    if lease_id is not None:
        lease_id = _require_lowercase_hex(lease_id, 64, "response.leaseId")
    result = obj["result"]
    if result not in RESULTS:
        _wire("response.result is outside the closed result set")
    objects_value = obj["objects"]
    if type(objects_value) is not list:
        _wire("response.objects must be a canonical array")
    assert isinstance(objects_value, list)
    objects = tuple(
        _require_hex_bytes(item, f"response.objects[{index}]")
        for index, item in enumerate(objects_value)
    )
    head_sequence = _require_u64(obj["headSequence"], "response.headSequence")
    head_digest = _parse_digest_field(obj["headDigest"], "response.headDigest")
    signature_hex = _require_lowercase_hex(
        obj["signature"], 128, "response.signature"
    )
    if result in ("stored", "found"):
        if len(objects) != 1:
            _wire(f"response {result} must carry exactly one object")
    elif result in ("not-found", "conflict", "revoked"):
        if objects:
            _wire(f"response {result} must carry no objects")
    elif len(objects) < 2:
        _wire("response multiple must carry at least two objects")
    if result == "stored":
        if lease_id is None:
            _wire("response stored must carry a leaseId")
    elif result != "found" and lease_id is not None:
        _wire(f"response {result} must carry a null leaseId")
    return {
        "requestId": request_id,
        "runId": run_id,
        "nonce": nonce,
        "leaseId": lease_id,
        "result": result,
        "objects": objects,
        "headSequence": head_sequence,
        "headDigest": head_digest,
        "signature": bytes.fromhex(signature_hex),
    }


def _unsigned_response(response: dict) -> dict:
    return {
        "schema": RESPONSE_SCHEMA,
        "requestId": response["requestId"],
        "runId": response["runId"],
        "nonce": response["nonce"],
        "leaseId": response["leaseId"],
        "result": response["result"],
        "objects": [item.hex() for item in response["objects"]],
        "headSequence": response["headSequence"],
        "headDigest": _digest_wire_text(response["headDigest"].bytes),
    }


@dataclass(frozen=True)
class _StoreEntry:
    state: str
    objects: Tuple[bytes, ...]


@dataclass(frozen=True)
class _ReadbackWindow:
    connection: socket.socket
    objectSchema: str
    keyBytes: bytes
    objectBytes: bytes
    leaseId: str
    headSequence: int
    headDigest: bytes


class AuthorityStoreServer:
    """Policy-pinned append-only authority-store service (one namespace)."""

    def __init__(
        self,
        policy_bytes: bytes,
        service_seed: bytes,
        descriptor_id: str,
        descriptor_version: str,
        service_executable_digest: Digest,
        namespace_id: str,
        expected_run_id: str,
        expected_nonce: str,
        io_timeout_seconds: float = 5.0,
    ) -> None:
        if type(policy_bytes) is not bytes:
            _wire("authority policy must be exact bytes")
        if type(service_seed) is not bytes or len(service_seed) != 32:
            _wire("service seed must be exact 32-byte bytes")
        if type(service_executable_digest) is not Digest:
            _wire("serviceExecutableDigest must be a Digest")
        self._policy_bytes = policy_bytes
        self._policy, self._policy_ref = _require_consumer(
            lambda: _CONSUMER.parse_bootstrap_authority_policy(policy_bytes),
            "PF-AUTH-STORE-AUTHORITY",
            "authority policy bytes are not a valid policy",
        )
        self._service_seed = service_seed
        self._descriptor_wire = _parse_descriptor(
            {
                "schema": DESCRIPTOR_SCHEMA,
                "id": descriptor_id,
                "version": descriptor_version,
                "protocol": PROTOCOL_ID,
                "serviceExecutableDigest": _digest_wire_text(
                    service_executable_digest.bytes
                ),
                "servicePublicKey": ed25519_public_key_from_seed(
                    service_seed
                ).hex(),
                "namespaceId": namespace_id,
                "maximumFrameBytes": MAXIMUM_FRAME_BYTES,
            },
            "descriptor",
        )
        self._descriptor_ref = descriptor_content_ref(self._descriptor_wire)
        self._expected_run_id = _require_safe_id(expected_run_id, "runId")
        self._expected_nonce = _require_lowercase_hex(
            expected_nonce, 64, "nonce"
        )
        if type(io_timeout_seconds) is not float or io_timeout_seconds <= 0:
            _wire("io timeout must be a positive float")
        self._io_timeout = io_timeout_seconds
        self._lock = threading.Lock()
        self._store: Dict[Tuple[str, bytes], _StoreEntry] = {}
        self._sequence = 0
        self._head = _log_head_genesis()
        self._window: Optional[_ReadbackWindow] = None
        self._connections = set()
        self._listener: Optional[socket.socket] = None
        self._accept_thread: Optional[threading.Thread] = None
        self._closed = False

    @property
    def descriptor_ref(self) -> ContentRef:
        return self._descriptor_ref

    @property
    def descriptor_wire(self) -> dict:
        return dict(self._descriptor_wire)

    @property
    def head(self) -> Tuple[int, bytes]:
        with self._lock:
            return self._sequence, self._head

    def inject_store_entry(
        self,
        object_schema: str,
        key_bytes: bytes,
        objects: Tuple[bytes, ...],
        state: str,
    ) -> None:
        """Seed revoked/multiple store state for protocol negatives.

        This process-local seeding never travels over the wire and never
        advances the append-only object log or head.
        """
        if object_schema not in ALLOWLIST_SCHEMAS:
            _wire("injected objectSchema is outside the closed allowlist")
        if type(key_bytes) is not bytes or not key_bytes:
            _wire("injected key must be exact bytes")
        if state not in ("revoked", "multiple"):
            _wire("injected state must be revoked|multiple")
        if state == "revoked" and objects:
            _wire("revoked entries carry no objects")
        if state == "multiple" and (
            type(objects) is not tuple or len(objects) < 2
            or any(type(item) is not bytes for item in objects)
        ):
            _wire("multiple entries carry at least two byte objects")
        with self._lock:
            self._store[(object_schema, key_bytes)] = _StoreEntry(
                state, tuple(objects)
            )

    def serve_unix(self, socket_path: str) -> "UnixServerHandle":
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            listener.bind(socket_path)
            listener.listen(16)
        except OSError as error:
            listener.close()
            _io(f"cannot listen on the unix socket: {error}")
        handle = UnixServerHandle(self, listener, socket_path)
        self._listener = listener
        self._accept_thread = threading.Thread(
            target=self._accept_loop,
            args=(listener,),
            name="authority-store-accept",
            daemon=True,
        )
        self._accept_thread.start()
        return handle

    def _accept_loop(self, listener: socket.socket) -> None:
        while True:
            try:
                connection, _ = listener.accept()
            except OSError:
                return
            with self._lock:
                if self._closed:
                    connection.close()
                    return
                self._connections.add(connection)
            thread = threading.Thread(
                target=self._serve_connection,
                args=(connection,),
                name="authority-store-connection",
                daemon=True,
            )
            thread.start()

    def _serve_connection(self, conn: socket.socket) -> None:
        try:
            conn.settimeout(self._io_timeout)
            _write_frame(
                conn,
                _encode_hello(
                    self._descriptor_wire,
                    self._expected_run_id,
                    self._expected_nonce,
                    self._service_seed,
                ),
            )
            expected_request_id = 0
            while True:
                payload = _read_frame(conn)
                request = _decode_request(payload)
                if request["requestId"] != expected_request_id:
                    _sequence("requestId must increment exactly from 0")
                expected_request_id += 1
                if (request["runId"] != self._expected_run_id
                        or request["nonce"] != self._expected_nonce):
                    _wire("request runId/nonce does not match the handoff")
                self._dispatch(conn, request)
        except AuthorityStoreError:
            pass
        except (OSError, EOFError):
            pass
        finally:
            with self._lock:
                self._connections.discard(conn)
                window = self._window
                if window is not None and window.connection is conn:
                    self._window = None
            try:
                conn.close()
            except OSError:
                pass

    def _dispatch(self, conn: socket.socket, request: dict) -> None:
        with self._lock:
            window = self._window
        if window is not None:
            if window.connection is not conn:
                _lease("another connection holds the readback window")
            self._answer_readback(conn, request, window)
            return
        if request["leaseId"] is not None:
            _lease("ordinary requests must carry a null leaseId")
        if request["operation"] == "lookup":
            self._answer_lookup(conn, request)
        else:
            self._answer_publish(conn, request)

    def _answer_readback(
        self,
        conn: socket.socket,
        request: dict,
        window: _ReadbackWindow,
    ) -> None:
        if (request["operation"] != "lookup"
                or request["objectSchema"] != window.objectSchema
                or request["leaseId"] != window.leaseId):
            _lease("readback window requires the same key/schema lookup "
                   "with the issued leaseId")
        key_bytes = _strict_key_bytes(request["lookupKeyHex"])
        if key_bytes != window.keyBytes:
            _lease("readback lookup key does not match the stored key")
        with self._lock:
            current = (self._sequence, self._head)
            if current != (window.headSequence, window.headDigest):
                _fail(
                    "PF-AUTH-STORE-HEAD",
                    "log head changed inside the readback window",
                )
            self._window = None
        _write_frame(
            conn,
            _encode_response(
                request["requestId"],
                self._expected_run_id,
                self._expected_nonce,
                window.leaseId,
                "found",
                (window.objectBytes,),
                window.headSequence,
                window.headDigest,
                self._service_seed,
            ),
        )

    def _answer_lookup(self, conn: socket.socket, request: dict) -> None:
        key_bytes = _strict_key_bytes(request["lookupKeyHex"])
        with self._lock:
            entry = self._store.get((request["objectSchema"], key_bytes))
            sequence, head = self._sequence, self._head
        if entry is None:
            result, objects = "not-found", ()
        elif entry.state == "active":
            result, objects = "found", entry.objects
        else:
            result, objects = entry.state, entry.objects
        _write_frame(
            conn,
            _encode_response(
                request["requestId"],
                self._expected_run_id,
                self._expected_nonce,
                None,
                result,
                objects,
                sequence,
                head,
                self._service_seed,
            ),
        )

    def _answer_publish(self, conn: socket.socket, request: dict) -> None:
        object_bytes = _require_hex_bytes(
            request["objectBytesHex"], "request.objectBytesHex"
        )
        key_bytes = _strict_key_bytes(request["lookupKeyHex"])
        self._validate_publish_authority(
            request["objectSchema"], object_bytes
        )
        recomputed = derive_lookup_key(request["objectSchema"], object_bytes)
        if recomputed != key_bytes:
            _wire("lookupKeyHex does not match the published object bytes")
        with self._lock:
            key = (request["objectSchema"], key_bytes)
            if key in self._store:
                result, objects, lease_id = "conflict", (), None
                sequence, head = self._sequence, self._head
            else:
                self._sequence += 1
                if self._sequence > MAX_SAFE_INTEGER:
                    _sequence("log head sequence exceeds 2^53-1")
                self._head = _log_head_next(
                    self._sequence,
                    self._head,
                    _log_entry_hash(
                        request["objectSchema"], key_bytes, object_bytes
                    ),
                )
                self._store[key] = _StoreEntry("active", (object_bytes,))
                lease_id = secrets.token_hex(32)
                self._window = _ReadbackWindow(
                    conn,
                    request["objectSchema"],
                    key_bytes,
                    object_bytes,
                    lease_id,
                    self._sequence,
                    self._head,
                )
                result, objects = "stored", (object_bytes,)
                sequence, head = self._sequence, self._head
        _write_frame(
            conn,
            _encode_response(
                request["requestId"],
                self._expected_run_id,
                self._expected_nonce,
                lease_id,
                result,
                objects,
                sequence,
                head,
                self._service_seed,
            ),
        )

    def _validate_publish_authority(
        self,
        object_schema: str,
        object_bytes: bytes,
    ) -> None:
        policy = self._policy
        policy_ref = self._policy_ref

        def rejected_to_authority(validation):
            return _require_consumer(
                validation,
                "PF-AUTH-STORE-AUTHORITY",
                f"publish authority validation failed for {object_schema}",
            )

        if object_schema == REQUIRED_TEST_SET_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_required_test_set(
                    object_bytes, self._policy_bytes
                )
            )
            rejected_to_authority(
                lambda: _CONSUMER._finalize_required_test_set(preflight)
            )
            return
        if object_schema == FORMAL_CATALOG_APPROVAL_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_formal_gate_catalog_approval(
                    object_bytes
                )
            )
            approval = preflight.approval
            if approval.authorityPolicy != policy_ref:
                _authority("catalog approval authority policy does not match")
            rule = policy.formalCatalogRule
            signatures = approval.signatures
            message = preflight.signatureMessage
        elif object_schema == TASK_APPROVAL_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_task_approval(object_bytes)
            )
            approval = preflight.taskApproval
            if approval.authorityPolicy != policy_ref:
                _authority("task approval authority policy does not match")
            rule = next(
                task_rule.rule for task_rule in policy.taskRules
                if task_rule.taskId == approval.taskId
            )
            signatures = approval.signatures
            message = preflight.signatureMessage
        elif object_schema == APPROVAL_SET_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_bootstrap_approval_set(
                    object_bytes
                )
            )
            approval_set = preflight.approvalSet
            if approval_set.authorityPolicy != policy_ref:
                _authority("approval set authority policy does not match")
            rule = policy.bootstrapSetRule
            signatures = approval_set.signatures
            message = preflight.signatureMessage
        elif object_schema == TASK_RECEIPT_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_bootstrap_task_verifier_receipt(
                    object_bytes
                )
            )
            receipt = preflight.receipt
            if receipt.authorityPolicy != policy_ref:
                _authority("task receipt authority policy does not match")
            if receipt.signature.keyId != policy.verifier.receiptKeyId:
                _authority("task receipt key is not the policy receipt key")
            if not verify_ed25519(
                policy.verifier.receiptPublicKey,
                preflight.signatureMessage,
                receipt.signature.signature,
            ):
                _authority("task receipt signature is invalid")
            return
        elif object_schema == VERIFIER_RECEIPT_SCHEMA:
            preflight = rejected_to_authority(
                lambda: _CONSUMER._preflight_bootstrap_approval_verifier_receipt(
                    object_bytes
                )
            )
            receipt = preflight.receipt
            if receipt.authorityPolicy != policy_ref:
                _authority("verifier receipt authority policy does not match")
            if receipt.signature.keyId != policy.verifier.receiptKeyId:
                _authority("verifier receipt key is not the policy receipt key")
            if not verify_ed25519(
                policy.verifier.receiptPublicKey,
                preflight.signatureMessage,
                receipt.signature.signature,
            ):
                _authority("verifier receipt signature is invalid")
            return
        else:
            _wire("publish schema is outside the closed allowlist")
        rejected_to_authority(
            lambda: _CONSUMER._require_signature_policy_membership(
                signatures,
                policy.principals,
                "publish.signatures",
            )
        )
        rejected_to_authority(
            lambda: _CONSUMER._require_signature_rule(
                signatures,
                policy.principals,
                rule,
                "publish.signatures",
            )
        )
        rejected_to_authority(
            lambda: _CONSUMER._verify_approval_signatures(
                signatures,
                policy.principals,
                message,
                "publish.signatures",
            )
        )

    def stop(self) -> None:
        with self._lock:
            self._closed = True
            connections = list(self._connections)
            self._connections.clear()
            self._window = None
        listener = self._listener
        if listener is not None:
            try:
                listener.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                listener.close()
            except OSError:
                pass
        for connection in connections:
            try:
                connection.close()
            except OSError:
                pass


class UnixServerHandle:
    """Handle for a background Unix-socket authority-store server."""

    def __init__(
        self,
        server: AuthorityStoreServer,
        listener: socket.socket,
        socket_path: str,
    ) -> None:
        self._server = server
        self._listener = listener
        self.socket_path = socket_path

    @property
    def server(self) -> AuthorityStoreServer:
        return self._server

    def stop(self) -> None:
        self._server.stop()
        thread = self._server._accept_thread
        if thread is not None:
            thread.join(timeout=2.0)

    def __enter__(self) -> "UnixServerHandle":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.stop()


class AuthorityStoreClient:
    """Request-response end of the authority-store RPC channel."""

    def __init__(
        self,
        expected_descriptor_ref: ContentRef,
        expected_run_id: str,
        expected_nonce: str,
        io_timeout_seconds: float = 5.0,
    ) -> None:
        if type(expected_descriptor_ref) is not ContentRef:
            _wire("expected descriptor ref must be a ContentRef")
        self._expected_descriptor_ref = expected_descriptor_ref
        self._expected_run_id = _require_safe_id(expected_run_id, "runId")
        self._expected_nonce = _require_lowercase_hex(
            expected_nonce, 64, "nonce"
        )
        if type(io_timeout_seconds) is not float or io_timeout_seconds <= 0:
            _wire("io timeout must be a positive float")
        self._io_timeout = io_timeout_seconds
        self._conn: Optional[socket.socket] = None
        self._service_public_key: Optional[bytes] = None
        self._next_request_id = 0
        self._last_head_sequence = 0

    def connect(self, socket_path: str) -> None:
        if self._conn is not None:
            _io("client is already connected")
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.settimeout(self._io_timeout)
        try:
            conn.connect(socket_path)
        except OSError as error:
            conn.close()
            _io(f"cannot connect to the authority store: {error}")
        try:
            hello = _decode_hello(_read_frame(conn))
            descriptor_ref = descriptor_content_ref(hello["descriptor"])
            if descriptor_ref != self._expected_descriptor_ref:
                _authority("hello descriptor ref does not match the pinned ref")
            if (hello["runId"] != self._expected_run_id
                    or hello["nonce"] != self._expected_nonce):
                _authority("hello runId/nonce does not match the handoff")
            unsigned = {
                "schema": HELLO_SCHEMA,
                "descriptor": hello["descriptor"],
                "runId": hello["runId"],
                "nonce": hello["nonce"],
            }
            public_key = bytes.fromhex(hello["descriptor"]["servicePublicKey"])
            if not verify_ed25519(
                public_key,
                _HELLO_DOMAIN + canonical_pf_jcs(unsigned),
                hello["signature"],
            ):
                _authority("hello signature is invalid")
        except AuthorityStoreError:
            conn.close()
            raise
        except OSError as error:
            conn.close()
            _io(f"hello exchange failed: {error}")
        self._conn = conn
        self._service_public_key = public_key
        self._next_request_id = 0
        self._last_head_sequence = 0

    def _request(self, operation: str, object_schema: str,
                 lookup_key_bytes: Optional[bytes],
                 object_bytes: Optional[bytes],
                 lease_id: Optional[str]) -> StoreResponse:
        conn = self._conn
        if conn is None or self._service_public_key is None:
            _io("client is not connected")
        if type(lookup_key_bytes) is not bytes or not lookup_key_bytes:
            _wire("lookup key must be exact non-empty bytes")
        if operation == "publish" and (
            type(object_bytes) is not bytes or not object_bytes
        ):
            _wire("publish object must be exact non-empty bytes")
        request = {
            "schema": REQUEST_SCHEMA,
            "requestId": self._next_request_id,
            "runId": self._expected_run_id,
            "nonce": self._expected_nonce,
            "leaseId": lease_id,
            "operation": operation,
            "objectSchema": object_schema,
            "lookupKeyHex": lookup_key_bytes.hex(),
            "objectBytesHex": (
                object_bytes.hex() if object_bytes is not None else None
            ),
        }
        expected_id = self._next_request_id
        try:
            _write_frame(conn, canonical_pf_jcs(request))
            response = _decode_response(_read_frame(conn))
        except AuthorityStoreError:
            self._abort()
            raise
        except OSError as error:
            self._abort()
            _io(f"request exchange failed: {error}")
        if response["requestId"] != expected_id:
            self._abort()
            _sequence("response requestId does not echo the request")
        if (response["runId"] != self._expected_run_id
                or response["nonce"] != self._expected_nonce):
            self._abort()
            _wire("response runId/nonce does not match the handoff")
        if not verify_ed25519(
            self._service_public_key,
            _RESPONSE_DOMAIN
            + canonical_pf_jcs(_unsigned_response(response)),
            response["signature"],
        ):
            self._abort()
            _authority("response signature is invalid")
        if response["headSequence"] < self._last_head_sequence:
            self._abort()
            _fail(
                "PF-AUTH-STORE-HEAD",
                "response headSequence regressed on this connection",
            )
        self._last_head_sequence = response["headSequence"]
        self._next_request_id += 1
        if operation == "lookup" and lease_id is None:
            if response["leaseId"] is not None:
                self._abort()
                _lease("ordinary lookup response must carry a null leaseId")
        return StoreResponse(
            response["requestId"],
            response["runId"],
            response["nonce"],
            response["leaseId"],
            response["result"],
            response["objects"],
            response["headSequence"],
            response["headDigest"],
        )

    def lookup(
        self,
        object_schema: str,
        lookup_key_bytes: bytes,
        lease_id: Optional[str] = None,
    ) -> StoreResponse:
        return self._request(
            "lookup", object_schema, lookup_key_bytes, None, lease_id
        )

    def publish(self, object_schema: str, object_bytes: bytes) -> StoreResponse:
        lookup_key_bytes = derive_lookup_key(object_schema, object_bytes)
        return self._request(
            "publish", object_schema, lookup_key_bytes, object_bytes, None
        )

    def publish_with_readback(
        self,
        object_schema: str,
        object_bytes: bytes,
    ) -> bytes:
        """Publish, verify the stored ack, then close the readback window."""
        ack = self.publish(object_schema, object_bytes)
        if ack.result == "conflict":
            _fail(
                "PF-AUTH-STORE-CONFLICT",
                "publish hit an existing store key",
            )
        if ack.result != "stored":
            _wire(f"publish returned an unexpected result {ack.result!r}")
        if ack.leaseId is None or ack.objects != (object_bytes,):
            _fail(
                "PF-AUTH-STORE-HEAD",
                "stored ack does not echo the exact published object",
            )
        readback = self.lookup(
            object_schema,
            derive_lookup_key(object_schema, object_bytes),
            lease_id=ack.leaseId,
        )
        if readback.result != "found":
            _fail(
                "PF-AUTH-STORE-HEAD",
                f"readback returned an unexpected result {readback.result!r}",
            )
        if (readback.leaseId != ack.leaseId
                or readback.objects != (object_bytes,)
                or readback.headSequence != ack.headSequence
                or readback.headDigest != ack.headDigest):
            self._abort()
            _fail(
                "PF-AUTH-STORE-HEAD",
                "readback does not exactly match the stored ack",
            )
        return readback.objects[0]

    def _abort(self) -> None:
        conn = self._conn
        self._conn = None
        self._service_public_key = None
        if conn is not None:
            try:
                conn.close()
            except OSError:
                pass

    def close(self) -> None:
        self._abort()

    def __enter__(self) -> "AuthorityStoreClient":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()
