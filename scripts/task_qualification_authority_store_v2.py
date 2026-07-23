"""ADR-0021 v2 authority-store protocol client (pf.taskqual.authority-store.rpc.v2).

This module implements the wire-level client side of the v2 task-qualification
authority-store RPC protocol. It is a pure library with respect to the socket
FD and bytes provided by the caller; it never reads the filesystem, environment
or ambient state. The adapter (:mod:`task_qualification_protected_adapter`)
owns the only production entrypoint and supplies the inherited channel FDs.

The v2 protocol is layered on a single connected Linux ``AF_UNIX/SOCK_SEQPACKET``
endpoint. Every packet carries exactly one frame:

    u32be(payloadLength) || canonical PF-JCS(payload)

payload length ``1..4194304``; packet size is exactly ``4 + payloadLength``.
Only six frame schemas are allowed — the client sends client hello, lookup
request and terminal request; the server sends server hello, lookup response
and terminal response. Each server frame is service-signed over its own
signature domain; the full digest domain of each frame is fixed per schema.

The lookup transcript is a fixed total order (ADR-0021 §4.2):
    (0) authority-policy, (1) production-profile-pin, (2) production-profile,
    (3) adapter, (4) snapshot-parser, (5) authority-store-service,
    (6) trusted-clock-service, (7) revocation-snapshot,
    (8..) each revocation-record declared by the snapshot (ASCII id ascending).
The terminal request ``requestId`` equals the lookup request count:
    ``8 + revocationRecordCount``.

This module deliberately does not implement the service side, the custody
supervisor, the durable nonce state machine, or role-key custody. Those are
candidate-external ceremony responsibilities defined by ADR-0021 §4.1/§6/§7.
"""

from __future__ import annotations

import hashlib
import socket
from dataclasses import dataclass, field
from typing import Any, Tuple

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_objects as _TQO

# ---------------------------------------------------------------------------
# Public re-exports of shared object helpers (existing objects, no new types)
# ---------------------------------------------------------------------------

Digest = _BTO.Digest
ContentRef = _BTO.ContentRef
Rejected = _BTO.Rejected

canonical_pf_jcs = _BTO.canonical_pf_jcs
decode_canonical_pf_jcs = _BTO.decode_canonical_pf_jcs
verify_ed25519 = _BTO.verify_ed25519
sign_ed25519 = _BTP.sign_ed25519
ed25519_public_key_from_seed = _BTP.ed25519_public_key_from_seed

domain_digest = _TQO.domain_digest
plain_sha256_digest = _TQO.plain_sha256_digest
digest_to_wire = _TQO.digest_to_wire
content_ref_to_wire = _TQO.content_ref_to_wire

TASKQUAL_REJECTION = _TQO.TASKQUAL_REJECTION

# ---------------------------------------------------------------------------
# Protocol constants — exact ADR-0021 §2/§3/§4
# ---------------------------------------------------------------------------

PROTOCOL_ID = "pf.taskqual.authority-store.rpc.v2"
NAMESPACE = "task-qualification-production-v1"
VERSION = "2.0.0"

MAX_FRAME_BYTES = 4_194_304
MAX_PACKET_BYTES = 4 + MAX_FRAME_BYTES
MAX_ACCEPTANCE_BYTES = 2_000_000
MAX_SAFE_INTEGER = (1 << 53) - 1

# v1 cross-reject identifiers (SPEC §8.4 / ADR-0021 §10) — exact taskqual v1
V1_PROTOCOL = "pf.taskqual.authority-store.rpc.v1"
V1_DESCRIPTOR_SCHEMA = "proof-forge.task-qualification-authority-store-service.v1"
V1_CLIENT_HELLO_SCHEMA = "proof-forge.task-qualification-store-client-hello.v1"
V1_SERVER_HELLO_SCHEMA = "proof-forge.task-qualification-store-server-hello.v1"
V1_LOOKUP_REQUEST_SCHEMA = "proof-forge.task-qualification-store-lookup-request.v1"
V1_LOOKUP_RESPONSE_SCHEMA = "proof-forge.task-qualification-store-lookup-response.v1"
V1_FRAME_SCHEMAS = (
    V1_CLIENT_HELLO_SCHEMA, V1_SERVER_HELLO_SCHEMA,
    V1_LOOKUP_REQUEST_SCHEMA, V1_LOOKUP_RESPONSE_SCHEMA,
)

# Six v2 frame schemas (ADR-0021 §3)
CLIENT_HELLO_SCHEMA = "proof-forge.task-qualification-store-client-hello.v2"
SERVER_HELLO_SCHEMA = "proof-forge.task-qualification-store-server-hello.v2"
LOOKUP_REQUEST_SCHEMA = "proof-forge.task-qualification-store-lookup-request.v2"
LOOKUP_RESPONSE_SCHEMA = "proof-forge.task-qualification-store-lookup-response.v2"
TERMINAL_REQUEST_SCHEMA = (
    "proof-forge.task-qualification-store-acceptance-sign-request.v2"
)
TERMINAL_RESPONSE_SCHEMA = (
    "proof-forge.task-qualification-store-acceptance-sign-response.v2"
)

CLIENT_FRAME_SCHEMAS = (
    CLIENT_HELLO_SCHEMA,
    LOOKUP_REQUEST_SCHEMA,
    TERMINAL_REQUEST_SCHEMA,
)
SERVER_FRAME_SCHEMAS = (
    SERVER_HELLO_SCHEMA,
    LOOKUP_RESPONSE_SCHEMA,
    TERMINAL_RESPONSE_SCHEMA,
)
ALL_FRAME_SCHEMAS = CLIENT_FRAME_SCHEMAS + SERVER_FRAME_SCHEMAS

# Frame full digest domains (ADR-0021 §4)
FRAME_FULL_DOMAINS = {
    CLIENT_HELLO_SCHEMA: b"pf.taskqual.store-client-hello.v2",
    SERVER_HELLO_SCHEMA: b"pf.taskqual.store-server-hello.v2",
    LOOKUP_REQUEST_SCHEMA: b"pf.taskqual.store-lookup-request.v2",
    LOOKUP_RESPONSE_SCHEMA: b"pf.taskqual.store-lookup-response.v2",
    TERMINAL_REQUEST_SCHEMA: b"pf.taskqual.store-acceptance-sign-request.v2",
    TERMINAL_RESPONSE_SCHEMA: b"pf.taskqual.store-acceptance-sign-response.v2",
}

# Server signature domains (server-only frames are signed; ADR-0021 §3)
FRAME_SIGNATURE_DOMAINS = {
    SERVER_HELLO_SCHEMA: b"pf.taskqual.store-server-hello-signature.v2",
    LOOKUP_RESPONSE_SCHEMA: b"pf.taskqual.store-lookup-response-signature.v2",
    TERMINAL_RESPONSE_SCHEMA:
        b"pf.taskqual.store-acceptance-sign-response-signature.v2",
}

# Accepted acceptance domains (ADR-0021 §4.3/§4.4 / SPEC §8.4)
ACCEPTANCE_SCHEMA = "proof-forge.protected-task-qualification-acceptance.v1"
ACCEPTANCE_STATEMENT_DOMAIN = b"pf.taskqual.protected-acceptance-statement.v1"
ACCEPTANCE_SIGNATURE_DOMAIN = b"pf.taskqual.protected-acceptance-signature.v1"
ACCEPTANCE_FULL_DOMAIN = b"pf.taskqual.protected-acceptance.v1"

# Protected handoff domains (SPEC §8.4)
HANDOFF_SCHEMA = "proof-forge.task-qualification-protected-handoff.v1"
HANDOFF_STATEMENT_DOMAIN = b"pf.taskqual.protected-handoff-statement.v1"
HANDOFF_SIGNATURE_DOMAIN = b"pf.taskqual.protected-handoff-signature.v1"
HANDOFF_FULL_DOMAIN = b"pf.taskqual.protected-handoff.v1"

# v2 service descriptor (ADR-0021 §2)
DESCRIPTOR_SCHEMA = "proof-forge.task-qualification-authority-store-service.v2"
DESCRIPTOR_DOMAIN = b"pf.taskqual.authority-store-service.v2"

# Trusted clock observation (SPEC §8.4)
CLOCK_OBSERVATION_SCHEMA = "proof-forge.task-qualification-trusted-clock-observation.v1"
CLOCK_STATEMENT_DOMAIN = b"pf.taskqual.trusted-clock-observation-statement.v1"
CLOCK_SIGNATURE_DOMAIN = b"pf.taskqual.trusted-clock-observation-signature.v1"
CLOCK_FULL_DOMAIN = b"pf.taskqual.trusted-clock-observation.v1"

# Provenance bundle (SPEC §8.4)
PROVENANCE_BUNDLE_SCHEMA = "proof-forge.protected-task-qualification-provenance-bundle.v1"

# The exact accepted unsigned acceptance field manifest/order (ADR-0021 §4.3 / SPEC §8.4).
# The signed acceptance appends ``signatures`` after ``provenanceRoles``.
UNSIGNED_ACCEPTANCE_FIELDS = (
    "schema", "id", "version", "authorityClass", "operation",
    "pureProjectionDigest", "bundleDigest", "subjectDigest",
    "preCloseCandidate", "closeoutCandidate", "trustedVerificationInstant",
    "adapter", "snapshotParser", "productionProfileDigest",
    "productionProfilePin", "ledgerProjectionDigest",
    "governanceCompletionDigest", "provenanceBundleDigest",
    "provenanceRoles",
)
SIGNED_ACCEPTANCE_FIELDS = UNSIGNED_ACCEPTANCE_FIELDS + ("signatures",)

# Operations allowed by SPEC-TASKQUAL-001 (ADR-0021 §3)
OPERATIONS = (
    b"task-qualification",
    b"task-completion",
    b"d0-10-bootstrap-approval",
    b"d0-10-bootstrap-receipt",
)

# Fixed ordered lookup transcript kinds (ADR-0021 §4.2): (0..7) fixed, then records.
FIXED_LOOKUP_OBJECT_KINDS = (
    "authority-policy",
    "production-profile-pin",
    "production-profile",
    "adapter",
    "snapshot-parser",
    "authority-store-service",
    "trusted-clock-service",
    "revocation-snapshot",
)
REVOCATION_SNAPSHOT_KIND = "revocation-snapshot"
REVOCATION_RECORD_KIND = "revocation-record"

# Object kind -> full digest domain for ContentRef recomputation
OBJECT_KIND_DOMAIN = {
    "authority-policy": b"pf.bootstrap-authority-policy.v1",
    "production-profile-pin": b"pf.taskqual.production-profile-pin.v1",
    "production-profile": b"pf.taskqual.production-profile.v1",
    "adapter": b"pf.taskqual.verifier-identity.v1",
    "snapshot-parser": b"pf.taskqual.verifier-identity.v1",
    "authority-store-service": DESCRIPTOR_DOMAIN,
    "trusted-clock-service": b"pf.taskqual.verifier-identity.v1",
    "revocation-record": b"pf.evidence-revocation.v1",
    "revocation-snapshot": b"pf.revocation-ledger-snapshot.v1",
}

# Object kind -> accepted schema (for ContentRef recomputation by bytes/domain/schema)
# revocation-snapshot is a head-key type but the lookup response still needs
# ContentRef recomputation.
OBJECT_KIND_SCHEMA = {
    "authority-policy": "proof-forge.bootstrap-authority-policy.v1",
    "production-profile-pin":
        "proof-forge.task-qualification-production-profile-pin.v1",
    "production-profile":
        "proof-forge.task-qualification-production-profile.v1",
    "adapter": "proof-forge.task-qualification.verifier-identity.v1",
    "snapshot-parser": "proof-forge.task-qualification.verifier-identity.v1",
    "authority-store-service": DESCRIPTOR_SCHEMA,
    "trusted-clock-service": "proof-forge.task-qualification.verifier-identity.v1",
    "revocation-record": "proof-forge.evidence-revocation.v1",
    "revocation-snapshot": "proof-forge.revocation-ledger-snapshot.v1",
}


# ---------------------------------------------------------------------------
# Stable rejection helper
# ---------------------------------------------------------------------------

def _reject(detail: str) -> None:
    raise Rejected(TASKQUAL_REJECTION, f"authority-store-v2: {detail}")


# ---------------------------------------------------------------------------
# Packet framing — ADR-0021 §3
# ---------------------------------------------------------------------------

def encode_packet(payload: bytes) -> bytes:
    """Encode a single SEQPACKET packet: u32be(len) || payload."""
    if type(payload) is not bytes:
        _reject("packet payload must be exact bytes")
    if not 1 <= len(payload) <= MAX_FRAME_BYTES:
        _reject("packet payload length must be 1..4194304")
    return len(payload).to_bytes(4, "big") + payload


def decode_packet(packet: bytes, *, msg_flags: int = 0) -> bytes:
    """Decode a single SEQPACKET packet, enforcing exact bounds."""
    if type(packet) is not bytes:
        _reject("packet must be exact bytes")
    if msg_flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC):
        _reject("truncated packet or ancillary data")
    if len(packet) < 4:
        _reject("truncated u32be header")
    length = int.from_bytes(packet[:4], "big")
    if not 1 <= length <= MAX_FRAME_BYTES:
        _reject("payload length out of bounds")
    if len(packet) != 4 + length:
        _reject("packet/u32 length mismatch")
    return packet[4:]


def send_packet(sock: socket.socket, payload: bytes) -> None:
    """Send exactly one packet via a single ``send(..., MSG_NOSIGNAL)``."""
    packet = encode_packet(payload)
    try:
        sent = sock.send(packet, socket.MSG_NOSIGNAL)
    except OSError as exc:
        _reject(f"packet send failed: {exc}")
    if sent != len(packet):
        _reject("packet send was partial; split frame forbidden")


def recv_packet(sock: socket.socket) -> bytes:
    """Receive exactly one packet via a single ``recvmsg`` with truncation checks.

    Uses a 4194308-byte data buffer (4 + MAX_FRAME_BYTES) and an exact ancillary
    buffer; rejects ``MSG_TRUNC|MSG_CTRUNC``, EOF, split frames, or a packet
    carrying two frames.
    """
    try:
        data, _ancillary, msg_flags, _addr = sock.recvmsg(
            MAX_PACKET_BYTES, 512)
    except OSError as exc:
        _reject(f"packet recv failed: {exc}")
    n_bytes = len(data)
    if n_bytes == 0:
        _reject("connection closed mid-packet")
    if msg_flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC):
        _reject("truncated packet or ancillary data")
    packet = bytes(data)
    return decode_packet(packet, msg_flags=msg_flags)


# ---------------------------------------------------------------------------
# Canonical PF-JCS frame helpers
# ---------------------------------------------------------------------------

def _encode_frame(obj: dict) -> bytes:
    return canonical_pf_jcs(obj)


def _decode_frame(payload: bytes) -> dict:
    if type(payload) is not bytes:
        _reject("frame payload must be exact bytes")
    try:
        obj = decode_canonical_pf_jcs(payload)
    except Exception:
        _reject("frame payload is not canonical PF-JCS")
    if type(obj) is not dict:
        _reject("frame payload must be a closed object")
    return obj


def _require_exact_keys(obj: dict, fields: Tuple[str, ...], where: str) -> dict:
    if set(obj.keys()) != set(fields):
        _reject(f"{where} must contain exactly {fields}")
    return obj


def _require_safe_int(value: Any, where: str) -> int:
    if type(value) is not int or not 0 <= value <= MAX_SAFE_INTEGER:
        _reject(f"{where} must be a PF-JCS safe integer 0..2^53-1")
    return value


def _require_ascii_text(value: Any, where: str) -> str:
    if type(value) is not str or not value:
        _reject(f"{where} must be nonempty ASCII text")
    try:
        value.encode("ascii")
    except UnicodeEncodeError:
        _reject(f"{where} must be ASCII text")
    return value


def _require_lowercase_hex(value: Any, length: int, where: str) -> str:
    if (type(value) is not str or len(value) != length
            or any(c not in "0123456789abcdef" for c in value)):
        _reject(f"{where} must be {length} lowercase hex characters")
    return value


def _require_hex_bytes(value: Any, where: str, *, maximum: int = MAX_FRAME_BYTES) -> bytes:
    if type(value) is not str or not value or len(value) % 2 != 0:
        _reject(f"{where} must be nonempty even-length hex")
    if any(c not in "0123456789abcdef" for c in value):
        _reject(f"{where} must be lowercase hex")
    decoded = bytes.fromhex(value)
    if len(decoded) > maximum:
        _reject(f"{where} exceeds the bound {maximum}")
    return decoded


def _parse_digest_field(value: Any, where: str) -> Digest:
    if type(value) is not str or not value.startswith("sha256:"):
        _reject(f"{where} must be the Digest wire form sha256:<hex>")
    hex_part = value[7:]
    if len(hex_part) != 64 or any(c not in "0123456789abcdef" for c in hex_part):
        _reject(f"{where} must be 64 lowercase hex after sha256:")
    return Digest(algorithm="sha256", bytes=bytes.fromhex(hex_part))


def _parse_content_ref(value: Any, where: str) -> dict:
    if type(value) is not dict:
        _reject(f"{where} must be a ContentRef object")
    obj = _require_exact_keys(value, ("schema", "id", "version", "digest"), where)
    _require_ascii_text(obj["schema"], f"{where}.schema")
    _require_ascii_text(obj["id"], f"{where}.id")
    _require_ascii_text(obj["version"], f"{where}.version")
    _parse_digest_field(obj["digest"], f"{where}.digest")
    return obj


def _parse_verifier_identity(value: Any, where: str) -> dict:
    if type(value) is not dict:
        _reject(f"{where} must be a VerifierIdentity object")
    fields = ("id", "executable", "closure", "sourceDigest", "buildPolicy")
    obj = _require_exact_keys(value, fields, where)
    _require_ascii_text(obj["id"], f"{where}.id")
    _parse_content_ref(obj["executable"], f"{where}.executable")
    _parse_content_ref(obj["closure"], f"{where}.closure")
    _parse_digest_field(obj["sourceDigest"], f"{where}.sourceDigest")
    _parse_content_ref(obj["buildPolicy"], f"{where}.buildPolicy")
    return obj


def _content_ref_equal(a: dict, b: dict) -> bool:
    """Exact field-by-field ContentRef equality (wire dicts)."""
    return (a.get("schema") == b.get("schema")
            and a.get("id") == b.get("id")
            and a.get("version") == b.get("version")
            and a.get("digest") == b.get("digest"))


def _verifier_identity_equal(a: dict, b: dict) -> bool:
    """Exact field-by-field VerifierIdentityV1 equality (wire dicts)."""
    if a.get("id") != b.get("id"):
        return False
    if a.get("sourceDigest") != b.get("sourceDigest"):
        return False
    return (_content_ref_equal(a.get("executable"), b.get("executable"))
            and _content_ref_equal(a.get("closure"), b.get("closure"))
            and _content_ref_equal(a.get("buildPolicy"), b.get("buildPolicy")))


# ---------------------------------------------------------------------------
# ContentRef recomputation from object bytes — ADR-0021 §4.2 / SPEC §8.4
# ---------------------------------------------------------------------------

def recompute_object_content_ref(object_kind: str, object_bytes: bytes) -> ContentRef:
    """Recompute the ContentRef for a looked-up object from its exact bytes.

    The object's schema/id/version are read from the decoded canonical bytes,
    and the digest is recomputed under the object kind's full domain. This
    prevents a response from claiming a ref that disagrees with its bytes.

    For VerifierIdentityV1-based kinds (adapter, snapshot-parser,
    trusted-clock-service), the object has no ``schema`` or ``version``
    field (it is an embedded identity, not a top-level typed object). The
    ContentRef uses the kind's schema, the object's ``id``, version
    ``"1.0.0"``, and the domain recomputed digest.
    """
    if object_kind not in OBJECT_KIND_DOMAIN:
        _reject(f"unknown object kind for ContentRef recomputation: {object_kind}")
    try:
        obj = decode_canonical_pf_jcs(object_bytes)
    except Exception:
        _reject(f"{object_kind} object bytes are not canonical PF-JCS")
    if type(obj) is not dict:
        _reject(f"{object_kind} object bytes must decode to a closed object")
    expected_schema = OBJECT_KIND_SCHEMA[object_kind]
    obj_id = obj.get("id")
    if type(obj_id) is not str or not obj_id:
        _reject(f"{object_kind} object missing id")
    domain = OBJECT_KIND_DOMAIN[object_kind]

    # VerifierIdentityV1-based kinds have no schema/version fields.  Validate
    # their exact closed identity wire before hashing; a ContentRef to an
    # arbitrary object that merely carries an ``id`` is not sufficient.
    if object_kind in ("adapter", "snapshot-parser", "trusted-clock-service"):
        _parse_verifier_identity(obj, f"{object_kind} object")
        obj_version = "1.0.0"
    else:
        schema = obj.get("schema")
        if schema != expected_schema:
            _reject(f"{object_kind} object schema mismatch: {schema} != {expected_schema}")
        obj_version = obj.get("version")
        if type(obj_version) is not str or not obj_version:
            _reject(f"{object_kind} object missing version")

    digest = domain_digest(domain, obj)
    return ContentRef(schema=expected_schema, id=obj_id, version=obj_version, digest=digest)


# ---------------------------------------------------------------------------
# Frame full/signature digest computation — ADR-0021 §3
# ---------------------------------------------------------------------------

def frame_full_digest(frame: dict) -> bytes:
    """Compute the full digest of a frame under its schema's full domain."""
    schema = frame.get("schema")
    domain = FRAME_FULL_DOMAINS.get(schema)
    if domain is None:
        _reject("unknown frame schema for full digest")
    return domain_digest(domain, frame).bytes


def _server_signature_message(frame: dict) -> bytes:
    """Compute the service signature message for a signed server frame."""
    schema = frame.get("schema")
    domain = FRAME_SIGNATURE_DOMAINS.get(schema)
    if domain is None or "signature" not in frame:
        _reject("not a signed server frame")
    unsigned = dict(frame)
    unsigned.pop("signature")
    return domain + b"\x00" + canonical_pf_jcs(unsigned)


def verify_server_signature(frame: dict, service_public_key: bytes) -> None:
    """Verify a server frame's service signature; reject on mismatch."""
    schema = frame.get("schema")
    if schema not in SERVER_FRAME_SCHEMAS:
        _reject("only server frames carry a service signature")
    signature_hex = frame.get("signature")
    if type(signature_hex) is not str or len(signature_hex) != 128:
        _reject("server signature must be 128 lowercase hex")
    if any(c not in "0123456789abcdef" for c in signature_hex):
        _reject("server signature must be lowercase hex")
    signature = bytes.fromhex(signature_hex)
    message = _server_signature_message(frame)
    if not verify_ed25519(service_public_key, message, signature):
        _reject("server frame service signature invalid")


# ---------------------------------------------------------------------------
# Echo tuple — ADR-0021 §3/§4
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class HandoffTuple:
    """The exact handoff echo fields shared across all frames."""
    taskId: str
    operation: str
    runId: str
    nonce: str
    service: dict  # ContentRef wire (v2 descriptor ref)
    handoffDigest: bytes  # raw 32 (full digest of signed handoff)
    headSequence: int
    headDigest: bytes  # raw 32


def _check_echo(frame: dict, tpl: HandoffTuple, *, has_handoff_digest: bool) -> None:
    """Verify that a frame echoes the handoff tuple exactly."""
    if frame.get("taskId") != tpl.taskId:
        _reject("frame taskId does not echo handoff")
    if frame.get("operation") != tpl.operation:
        _reject("frame operation does not echo handoff")
    if frame.get("runId") != tpl.runId:
        _reject("frame runId does not echo handoff")
    if frame.get("nonce") != tpl.nonce:
        _reject("frame nonce does not echo handoff")
    if not _content_ref_equal(frame.get("service"), tpl.service):
        _reject("frame service does not echo handoff")
    if frame.get("headSequence") != tpl.headSequence:
        _reject("frame headSequence does not echo handoff")
    head_digest = frame.get("headDigest")
    if type(head_digest) is not str or head_digest != digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.headDigest)):
        _reject("frame headDigest does not echo handoff")
    if has_handoff_digest:
        hd = frame.get("handoffDigest")
        if type(hd) is not str or hd != digest_to_wire(
                Digest(algorithm="sha256", bytes=tpl.handoffDigest)):
            _reject("frame handoffDigest does not echo handoff")


# ---------------------------------------------------------------------------
# v1 cross-reject — ADR-0021 §10 / SPEC §8.4
# ---------------------------------------------------------------------------

def is_v1_frame_schema(schema: str) -> bool:
    """True if the schema is a v1 authority-store frame schema (cross-reject)."""
    return schema in V1_FRAME_SCHEMAS


def is_v1_protocol(protocol: str) -> bool:
    """True if the protocol string is v1 (cross-reject)."""
    return protocol == V1_PROTOCOL


def is_v1_descriptor_schema(schema: str) -> bool:
    """True if the schema is the v1 descriptor schema (cross-reject)."""
    return schema == V1_DESCRIPTOR_SCHEMA


# ---------------------------------------------------------------------------
# Client/server hello — ADR-0021 §4.1
# ---------------------------------------------------------------------------

CLIENT_HELLO_FIELDS = (
    "schema", "version", "taskId", "operation", "runId", "nonce",
    "service", "handoffDigest", "headSequence", "headDigest",
)
SERVER_HELLO_FIELDS = (
    "schema", "version", "taskId", "operation", "runId", "nonce",
    "service", "handoffDigest", "headSequence", "headDigest",
    "status", "signature",
)


def build_client_hello(tpl: HandoffTuple) -> bytes:
    """Build and encode a client hello frame."""
    frame = {
        "schema": CLIENT_HELLO_SCHEMA,
        "version": VERSION,
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
        "handoffDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.handoffDigest)),
        "headSequence": tpl.headSequence,
        "headDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.headDigest)),
    }
    return _encode_frame(frame)


def parse_server_hello(payload: bytes, tpl: HandoffTuple,
                        service_public_key: bytes) -> dict:
    """Parse, echo-check and signature-verify a server hello frame."""
    obj = _decode_frame(payload)
    if obj.get("schema") in V1_FRAME_SCHEMAS:
        _reject("v1 server hello frame is rejected")
    obj = _require_exact_keys(obj, SERVER_HELLO_FIELDS, "server-hello")
    if obj["schema"] != SERVER_HELLO_SCHEMA:
        _reject("server-hello.schema is not the v2 server hello schema")
    if obj["version"] != VERSION:
        _reject("server-hello.version must be 2.0.0")
    if obj["status"] != "ready":
        _reject("server-hello.status must be ready")
    _check_echo(obj, tpl, has_handoff_digest=True)
    verify_server_signature(obj, service_public_key)
    return obj


# ---------------------------------------------------------------------------
# Lookup request/response — ADR-0021 §4.2
# ---------------------------------------------------------------------------

LOOKUP_REQUEST_FIELDS = (
    "schema", "version", "requestId", "taskId", "operation", "runId",
    "nonce", "service", "headSequence", "headDigest", "key",
)
LOOKUP_RESPONSE_FIELDS = (
    "schema", "version", "requestId", "taskId", "operation", "runId",
    "nonce", "service", "headSequence", "headDigest", "status", "key",
    "object", "objectBytesHex", "signature",
)

OBJECT_LOOKUP_KEY_FIELDS = (
    "kind", "namespace", "taskId", "operation", "gateSetDigest",
    "objectKind", "objectId",
)
REVOCATION_HEAD_KEY_FIELDS = (
    "kind", "namespace", "taskId", "operation", "gateSetDigest",
    "objectKind", "headSequence", "headDigest",
)


def build_object_lookup_key(task_id: str, operation: str,
                             gate_set_digest: bytes, object_kind: str,
                             object_id: str) -> dict:
    """Build a ``TaskQualificationStoreObjectLookupKeyV2`` key object."""
    if object_kind not in OBJECT_KIND_SCHEMA:
        _reject(f"object key objectKind {object_kind!r} is not allowed")
    return {
        "kind": "object",
        "namespace": NAMESPACE,
        "taskId": task_id,
        "operation": operation,
        "gateSetDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=gate_set_digest)),
        "objectKind": object_kind,
        "objectId": object_id,
    }


def build_revocation_head_key(task_id: str, operation: str,
                              gate_set_digest: bytes, head_sequence: int,
                              head_digest: bytes) -> dict:
    """Build a ``TaskQualificationStoreRevocationHeadLookupKeyV2`` key object."""
    return {
        "kind": "revocation-head",
        "namespace": NAMESPACE,
        "taskId": task_id,
        "operation": operation,
        "gateSetDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=gate_set_digest)),
        "objectKind": REVOCATION_SNAPSHOT_KIND,
        "headSequence": head_sequence,
        "headDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=head_digest)),
    }


def _validate_lookup_key(key: dict, where: str) -> dict:
    """Validate a lookup key object against its discriminated union."""
    if type(key) is not dict:
        _reject(f"{where} must be a lookup key object")
    kind = key.get("kind")
    if kind == "object":
        _require_exact_keys(key, OBJECT_LOOKUP_KEY_FIELDS, where)
        if key["namespace"] != NAMESPACE:
            _reject(f"{where}.namespace must be {NAMESPACE}")
        if key["objectKind"] not in OBJECT_KIND_SCHEMA:
            _reject(f"{where}.objectKind is not an allowed object kind")
        _parse_digest_field(key["gateSetDigest"], f"{where}.gateSetDigest")
        _require_ascii_text(key["objectId"], f"{where}.objectId")
        return key
    if kind == "revocation-head":
        _require_exact_keys(key, REVOCATION_HEAD_KEY_FIELDS, where)
        if key["namespace"] != NAMESPACE:
            _reject(f"{where}.namespace must be {NAMESPACE}")
        if key["objectKind"] != REVOCATION_SNAPSHOT_KIND:
            _reject(f"{where}.objectKind must be revocation-snapshot")
        _parse_digest_field(key["gateSetDigest"], f"{where}.gateSetDigest")
        _require_safe_int(key["headSequence"], f"{where}.headSequence")
        _parse_digest_field(key["headDigest"], f"{where}.headDigest")
        return key
    _reject(f"{where}.kind must be object|revocation-head")


def build_lookup_request(request_id: int, tpl: HandoffTuple,
                         key: dict) -> bytes:
    """Build and encode a lookup request frame."""
    _require_safe_int(request_id, "lookup-request.requestId")
    _validate_lookup_key(key, "lookup-request.key")
    frame = {
        "schema": LOOKUP_REQUEST_SCHEMA,
        "version": VERSION,
        "requestId": request_id,
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
        "headSequence": tpl.headSequence,
        "headDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.headDigest)),
        "key": key,
    }
    return _encode_frame(frame)


def parse_lookup_response(payload: bytes, request_id: int, key: dict,
                          tpl: HandoffTuple,
                          service_public_key: bytes) -> dict:
    """Parse, echo-check, requestId-match, recompute ContentRef and verify
    the service signature of a lookup response.

    Returns the validated response dict. The response ``object`` ContentRef
    must recompute from ``objectBytesHex`` under the object kind's domain and
    match the response's claimed ``object`` ref field-by-field.
    """
    obj = _decode_frame(payload)
    if obj.get("schema") in V1_FRAME_SCHEMAS:
        _reject("v1 lookup response frame is rejected")
    obj = _require_exact_keys(obj, LOOKUP_RESPONSE_FIELDS, "lookup-response")
    if obj["schema"] != LOOKUP_RESPONSE_SCHEMA:
        _reject("lookup-response.schema is not the v2 lookup response schema")
    if obj["version"] != VERSION:
        _reject("lookup-response.version must be 2.0.0")
    if obj["requestId"] != request_id:
        _reject("lookup-response.requestId does not match request")
    if obj["status"] != "found":
        _reject("lookup-response.status must be found exactly one")
    _check_echo(obj, tpl, has_handoff_digest=False)
    if obj["key"] != key:
        _reject("lookup-response.key does not match request key")
    object_bytes = _require_hex_bytes(
        obj["objectBytesHex"], "lookup-response.objectBytesHex",
        maximum=MAX_FRAME_BYTES)
    # Recompute the object ContentRef from exact bytes and verify it matches.
    object_kind = key["objectKind"]
    recomputed_ref = recompute_object_content_ref(object_kind, object_bytes)
    recomputed_wire = content_ref_to_wire(recomputed_ref)
    claimed_ref = _parse_content_ref(obj["object"], "lookup-response.object")
    if not _content_ref_equal(claimed_ref, recomputed_wire):
        _reject(
            "lookup-response.object ContentRef does not recompute from bytes")
    verify_server_signature(obj, service_public_key)
    return obj


# ---------------------------------------------------------------------------
# Terminal request/response — ADR-0021 §4.3/§4.4
# ---------------------------------------------------------------------------

TERMINAL_REQUEST_FIELDS = (
    "schema", "version", "requestId", "taskId", "operation", "runId",
    "nonce", "service", "handoffDigest", "headSequence", "headDigest",
    "adapter", "productionProfilePin", "snapshotParser",
    "acceptanceStatementDigest", "unsignedAcceptanceBytesHex",
)
TERMINAL_RESPONSE_FIELDS = (
    "schema", "version", "requestId", "taskId", "operation", "runId",
    "nonce", "service", "handoffDigest", "headSequence", "headDigest",
    "status", "acceptanceStatementDigest", "acceptance",
    "acceptanceBytesHex", "signature",
)


def _validate_unsigned_acceptance(unsigned: dict) -> None:
    """Validate the closed shape of an unsigned acceptance (ADR-0021 §4.3)."""
    if type(unsigned) is not dict:
        _reject("unsigned acceptance must be a closed object")
    if set(unsigned.keys()) != set(UNSIGNED_ACCEPTANCE_FIELDS):
        _reject("unsigned acceptance field manifest/order drift")
    if unsigned["schema"] != ACCEPTANCE_SCHEMA:
        _reject("unsigned acceptance schema mismatch")
    if unsigned["version"] != "1.0.0":
        _reject("unsigned acceptance version must be 1.0.0")
    if unsigned["authorityClass"] != "production-candidate-bound":
        _reject("unsigned acceptance authorityClass must be production-candidate-bound")
    operation = unsigned["operation"]
    accepted_operations = {value.decode("ascii") for value in OPERATIONS}
    if operation not in accepted_operations:
        _reject("unsigned acceptance operation is not accepted")
    try:
        _TQO.parse_candidate_identity(
            unsigned["preCloseCandidate"], "unsigned.preCloseCandidate")
    except Rejected as exc:
        _reject(f"unsigned preCloseCandidate invalid: {exc.detail}")
    closeout = unsigned["closeoutCandidate"]
    closeout_required = operation in (
        "task-completion", "d0-10-bootstrap-receipt")
    if closeout_required:
        if closeout is None:
            _reject("unsigned closeoutCandidate is required for receipt operation")
        try:
            _TQO.parse_candidate_identity(
                closeout, "unsigned.closeoutCandidate")
        except Rejected as exc:
            _reject(f"unsigned closeoutCandidate invalid: {exc.detail}")
    elif closeout is not None:
        _reject("unsigned closeoutCandidate must be null for approval operation")
    _parse_digest_field(unsigned["pureProjectionDigest"],
                        "unsigned.pureProjectionDigest")
    _parse_digest_field(unsigned["bundleDigest"], "unsigned.bundleDigest")
    _parse_digest_field(unsigned["subjectDigest"], "unsigned.subjectDigest")
    _parse_digest_field(
        unsigned["productionProfileDigest"], "unsigned.productionProfileDigest")
    _parse_content_ref(unsigned["productionProfilePin"],
                       "unsigned.productionProfilePin")
    try:
        _TQO._require_rfc3339_utc(
            unsigned["trustedVerificationInstant"],
            "unsigned.trustedVerificationInstant")
    except Rejected as exc:
        _reject(f"unsigned trustedVerificationInstant invalid: {exc.detail}")
    ledger_digest = unsigned["ledgerProjectionDigest"]
    governance_digest = unsigned["governanceCompletionDigest"]
    if operation == "d0-10-bootstrap-receipt":
        if ledger_digest is None or governance_digest is None:
            _reject("D0 receipt unsigned acceptance requires both external digests")
        _parse_digest_field(ledger_digest, "unsigned.ledgerProjectionDigest")
        _parse_digest_field(
            governance_digest, "unsigned.governanceCompletionDigest")
    elif ledger_digest is not None or governance_digest is not None:
        _reject("non-D0-receipt unsigned acceptance requires null external digests")
    _parse_digest_field(unsigned["provenanceBundleDigest"],
                       "unsigned.provenanceBundleDigest")
    _parse_verifier_identity(unsigned["adapter"], "unsigned.adapter")
    _parse_verifier_identity(unsigned["snapshotParser"],
                             "unsigned.snapshotParser")
    roles = unsigned["provenanceRoles"]
    if type(roles) is not list or not roles:
        _reject("unsigned.provenanceRoles must be a nonempty array")
    for role in roles:
        if type(role) is not str:
            _reject("unsigned.provenanceRoles items must be strings")
        try:
            encoded = role.encode("ascii")
        except UnicodeEncodeError:
            _reject("unsigned.provenanceRoles items must be ASCII")
        if not 1 <= len(encoded) <= 512:
            _reject("unsigned.provenanceRoles item must be 1..512 ASCII bytes")
        if (role.startswith("/") or role.endswith("/") or "//" in role
                or any(not (c.isalnum() or c in "-._/") for c in role)):
            _reject("unsigned.provenanceRoles item has invalid role grammar")
    # provenanceRoles must be ASCII-sorted strictly ascending and unique
    role_strs = list(roles)
    if role_strs != sorted(role_strs):
        _reject("unsigned.provenanceRoles must be ASCII-sorted ascending")
    if len(set(role_strs)) != len(role_strs):
        _reject("unsigned.provenanceRoles must be unique")


def acceptance_statement_digest(unsigned: dict) -> bytes:
    """Compute the acceptance statement digest (ADR-0021 §4.3).

    ``SHA-256("pf.taskqual.protected-acceptance-statement.v1" || NUL ||
       PF-JCS(unsigned))``. The unsigned object must not contain
    ``signatures``; carrying ``signatures:[]`` or any other field is rejected.
    """
    if "signatures" in unsigned:
        _reject("unsigned acceptance must not contain signatures")
    _validate_unsigned_acceptance(unsigned)
    return domain_digest(ACCEPTANCE_STATEMENT_DOMAIN, unsigned).bytes


def build_terminal_request(request_id: int, tpl: HandoffTuple,
                           adapter_wire: dict, profile_pin_ref: dict,
                           snapshot_parser_wire: dict,
                           unsigned_acceptance: dict) -> bytes:
    """Build and encode a terminal acceptance-sign request frame (ADR-0021 §4.3)."""
    _require_safe_int(request_id, "terminal-request.requestId")
    statement = acceptance_statement_digest(unsigned_acceptance)
    expected_id = (
        f"protected-task-qualification-{tpl.operation}-"
        f"{tpl.taskId.lower().replace('task-', '')}")
    if unsigned_acceptance["id"] != expected_id:
        _reject(f"unsigned acceptance id must be {expected_id}")
    if unsigned_acceptance["operation"] != tpl.operation:
        _reject("unsigned acceptance operation does not match handoff tuple")
    if not _verifier_identity_equal(
            unsigned_acceptance["adapter"], adapter_wire):
        _reject("unsigned acceptance adapter does not match terminal request")
    if not _content_ref_equal(
            unsigned_acceptance["productionProfilePin"], profile_pin_ref):
        _reject("unsigned acceptance profile pin does not match terminal request")
    if not _verifier_identity_equal(
            unsigned_acceptance["snapshotParser"], snapshot_parser_wire):
        _reject("unsigned acceptance snapshot parser does not match terminal request")
    unsigned_canonical = canonical_pf_jcs(unsigned_acceptance)
    unsigned_hex = unsigned_canonical.hex()
    if len(unsigned_canonical) > MAX_ACCEPTANCE_BYTES:
        _reject("terminal-request unsigned acceptance exceeds 2000000 bytes")
    # Verify the hex decodes back to canonical bytes of the unsigned object.
    decoded = _require_hex_bytes(unsigned_hex, "terminal-request.unsigned",
                                 maximum=MAX_ACCEPTANCE_BYTES)
    if unsigned_canonical != decoded:
        _reject("terminal-request unsigned bytes are not canonical PF-JCS")
    frame = {
        "schema": TERMINAL_REQUEST_SCHEMA,
        "version": VERSION,
        "requestId": request_id,
        "taskId": tpl.taskId,
        "operation": tpl.operation,
        "runId": tpl.runId,
        "nonce": tpl.nonce,
        "service": tpl.service,
        "handoffDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.handoffDigest)),
        "headSequence": tpl.headSequence,
        "headDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=tpl.headDigest)),
        "adapter": adapter_wire,
        "productionProfilePin": profile_pin_ref,
        "snapshotParser": snapshot_parser_wire,
        "acceptanceStatementDigest": digest_to_wire(
            Digest(algorithm="sha256", bytes=statement)),
        "unsignedAcceptanceBytesHex": unsigned_hex,
    }
    return _encode_frame(frame)


def parse_terminal_response(
    payload: bytes, request_id: int, tpl: HandoffTuple,
    unsigned_acceptance: dict, service_public_key: bytes,
    *, authority_principals: dict,
) -> bytes:
    """Parse, verify and return the exact signed acceptance bytes (ADR-0021 §4.4).

    The adapter exact-decodes the response, re-verifies the service signature,
    the three role signatures (A+Q+S distinct principals from the verified
    policy), fixed quorum, unsigned/signed byte equality, ContentRef
    recomputation, echo tuple, current head and terminal state. It returns only
    the response's exact signed acceptance bytes.

    ``authority_principals`` is a ``{keyId: BootstrapAuthorityPrincipalV1}`` dict
    derived from the already-verified current authority policy. The three
    role signatures must cover distinct principals spanning
    Architecture+Quality+Security.
    """
    obj = _decode_frame(payload)
    if obj.get("schema") in V1_FRAME_SCHEMAS:
        _reject("v1 terminal response frame is rejected")
    obj = _require_exact_keys(obj, TERMINAL_RESPONSE_FIELDS, "terminal-response")
    if obj["schema"] != TERMINAL_RESPONSE_SCHEMA:
        _reject("terminal-response.schema is not the v2 terminal response schema")
    if obj["version"] != VERSION:
        _reject("terminal-response.version must be 2.0.0")
    if obj["requestId"] != request_id:
        _reject("terminal-response.requestId does not match request")
    if obj["status"] != "signed":
        _reject("terminal-response.status must be signed")
    _check_echo(obj, tpl, has_handoff_digest=True)
    # Service signature over the response frame.
    verify_server_signature(obj, service_public_key)
    # The statement digest must match the request's unsigned acceptance.
    expected_statement = acceptance_statement_digest(unsigned_acceptance)
    actual_statement = _parse_digest_field(
        obj["acceptanceStatementDigest"], "terminal-response.acceptanceStatementDigest")
    if actual_statement.bytes != expected_statement:
        _reject("terminal-response acceptanceStatementDigest mismatch")
    # Decode the signed acceptance bytes.
    signed_bytes = _require_hex_bytes(
        obj["acceptanceBytesHex"], "terminal-response.acceptanceBytesHex",
        maximum=MAX_ACCEPTANCE_BYTES)
    signed_wire = _decode_frame(signed_bytes)
    if set(signed_wire.keys()) != set(SIGNED_ACCEPTANCE_FIELDS):
        _reject("signed acceptance field manifest/order drift")
    # The signed acceptance must equal the unsigned object plus a signatures
    # field at the fixed final position.
    unsigned_from_signed = dict(signed_wire)
    signatures = unsigned_from_signed.pop("signatures")
    if canonical_pf_jcs(unsigned_from_signed) != canonical_pf_jcs(unsigned_acceptance):
        _reject("signed acceptance unsigned portion does not match request unsigned")
    # Verify the acceptance ContentRef recomputed from exact signed bytes.
    _parse_content_ref(obj["acceptance"], "terminal-response.acceptance")
    expected_ref_digest = domain_digest(ACCEPTANCE_FULL_DOMAIN, signed_wire).bytes
    actual_ref = obj["acceptance"]
    if actual_ref["digest"] != digest_to_wire(
            Digest(algorithm="sha256", bytes=expected_ref_digest)):
        _reject("terminal-response acceptance ContentRef does not recompute")
    if actual_ref["schema"] != ACCEPTANCE_SCHEMA:
        _reject("terminal-response acceptance schema mismatch")
    if actual_ref["id"] != signed_wire["id"]:
        _reject("terminal-response acceptance ref id mismatch")
    if actual_ref["version"] != signed_wire["version"]:
        _reject("terminal-response acceptance ref version mismatch")
    # Verify the three role signatures (A+Q+S distinct principals).
    if type(signatures) is not list or len(signatures) != 3:
        _reject("terminal-response must carry exactly three role signatures")
    statement = expected_statement
    message = ACCEPTANCE_SIGNATURE_DOMAIN + b"\x00" + statement
    key_ids = [item.get("keyId") for item in signatures]
    if key_ids != sorted(key_ids):
        _reject("terminal-response role signatures not sorted by keyId")
    if len(set(key_ids)) != 3:
        _reject("terminal-response role signature keyIds not distinct")
    covered_roles: set = set()
    covered_principals: set = set()
    for item in signatures:
        if type(item) is not dict:
            _reject("terminal-response role signature must be an object")
        if set(item) != {"keyId", "algorithm", "signature"}:
            _reject("terminal-response role signature wire invalid")
        if item.get("algorithm") != "ed25519":
            _reject("terminal-response role signature algorithm must be ed25519")
        key_id = item["keyId"]
        if type(key_id) is not str or not key_id:
            _reject("terminal-response role signature keyId invalid")
        principal = authority_principals.get(key_id)
        if principal is None:
            _reject(f"terminal-response role signer unknown: {key_id}")
        if principal.principalId in covered_principals:
            _reject("terminal-response role signer reused")
        sig_hex = item["signature"]
        if type(sig_hex) is not str or len(sig_hex) != 128:
            _reject("terminal-response role signature must be 128 lowercase hex")
        if any(c not in "0123456789abcdef" for c in sig_hex):
            _reject("terminal-response role signature must be lowercase hex")
        signature = bytes.fromhex(sig_hex)
        if not verify_ed25519(principal.publicKey, message, signature):
            _reject(f"terminal-response role signature invalid: {key_id}")
        covered_principals.add(principal.principalId)
        covered_roles.update(principal.roles)
    if not {"architecture", "quality", "security"}.issubset(covered_roles):
        _reject("terminal-response role signatures do not cover A+Q+S")
    return signed_bytes


# ---------------------------------------------------------------------------
# Fixed ordered lookup transcript — ADR-0021 §4.2
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class LookupResult:
    """A single lookup result: the validated response dict and object bytes."""
    response: dict
    object_bytes: bytes
    content_ref: dict
    object_kind: str


def run_lookup_transcript(
    sock: socket.socket,
    tpl: HandoffTuple,
    service_public_key: bytes,
    *,
    gate_set_digest: bytes,
    object_ids: dict,
    revocation_head: tuple,
) -> Tuple[LookupResult, ...]:
    """Drive the exact fixed ordered lookup transcript over the SEQPACKET endpoint.

    The transcript order is fixed (ADR-0021 §4.2):
        (0) authority-policy, (1) production-profile-pin, (2) production-profile,
        (3) adapter, (4) snapshot-parser, (5) authority-store-service,
        (6) trusted-clock-service, (7) revocation-snapshot,
        (8..) each revocation-record declared by the snapshot (ASCII id ascending).

    ``object_ids`` is a ``{object_kind: object_id}`` dict for the fixed object
    lookups; the revocation-snapshot uses a head key. ``revocation_head`` is
    ``(head_sequence, head_digest)``. The record objectIds are read from the
    decoded snapshot bytes.

    The terminal ``requestId`` equals ``8 + revocationRecordCount``.
    """
    task_id = tpl.taskId
    operation = tpl.operation
    head_sequence, head_digest = revocation_head
    results: list = []
    request_id = 0

    # (0)..(6): fixed object lookups
    for object_kind in FIXED_LOOKUP_OBJECT_KINDS[:7]:
        if object_kind not in object_ids:
            _reject(f"missing object_id for fixed lookup kind: {object_kind}")
        key = build_object_lookup_key(
            task_id, operation, gate_set_digest, object_kind,
            object_ids[object_kind])
        request_payload = build_lookup_request(request_id, tpl, key)
        send_packet(sock, request_payload)
        response_payload = recv_packet(sock)
        response = parse_lookup_response(
            response_payload, request_id, key, tpl, service_public_key)
        object_bytes = bytes.fromhex(response["objectBytesHex"])
        results.append(LookupResult(
            response=response, object_bytes=object_bytes,
            content_ref=response["object"], object_kind=object_kind))
        request_id += 1

    # (7): revocation-snapshot (head key)
    head_key = build_revocation_head_key(
        task_id, operation, gate_set_digest, head_sequence, head_digest)
    request_payload = build_lookup_request(request_id, tpl, head_key)
    send_packet(sock, request_payload)
    response_payload = recv_packet(sock)
    response = parse_lookup_response(
        response_payload, request_id, head_key, tpl, service_public_key)
    snapshot_bytes = bytes.fromhex(response["objectBytesHex"])
    results.append(LookupResult(
        response=response, object_bytes=snapshot_bytes,
        content_ref=response["object"], object_kind=REVOCATION_SNAPSHOT_KIND))
    request_id += 1

    # (8..): revocation-records from the snapshot, ASCII id ascending
    record_ids = _extract_revocation_record_ids(snapshot_bytes)
    for record_id in record_ids:
        key = build_object_lookup_key(
            task_id, operation, gate_set_digest, REVOCATION_RECORD_KIND,
            record_id)
        request_payload = build_lookup_request(request_id, tpl, key)
        send_packet(sock, request_payload)
        response_payload = recv_packet(sock)
        response = parse_lookup_response(
            response_payload, request_id, key, tpl, service_public_key)
        object_bytes = bytes.fromhex(response["objectBytesHex"])
        results.append(LookupResult(
            response=response, object_bytes=object_bytes,
            content_ref=response["object"], object_kind=REVOCATION_RECORD_KIND))
        request_id += 1

    return tuple(results)


def _extract_revocation_record_ids(snapshot_bytes: bytes) -> Tuple[str, ...]:
    """Extract revocation-record IDs from a decoded snapshot, ASCII ascending.

    The snapshot is a closed object with a ``records`` array; each record has
    an ``id`` field. IDs are returned ASCII-sorted strictly ascending and unique.
    """
    try:
        snapshot = decode_canonical_pf_jcs(snapshot_bytes)
    except Exception:
        _reject("revocation-snapshot bytes are not canonical PF-JCS")
    if type(snapshot) is not dict:
        _reject("revocation-snapshot must be a closed object")
    records = snapshot.get("records")
    if type(records) is not list:
        _reject("revocation-snapshot.records must be an array")
    ids = []
    for record in records:
        if type(record) is not dict:
            _reject("revocation-snapshot record must be an object")
        rid = record.get("id")
        if type(rid) is not str or not rid:
            _reject("revocation-snapshot record id must be nonempty text")
        ids.append(rid)
    if ids != sorted(ids):
        _reject("revocation-snapshot record ids must be ASCII-sorted ascending")
    if len(set(ids)) != len(ids):
        _reject("revocation-snapshot record ids must be unique")
    return tuple(ids)


def terminal_request_id(lookup_results: Tuple[LookupResult, ...]) -> int:
    """The terminal requestId equals the lookup request count."""
    return len(lookup_results)