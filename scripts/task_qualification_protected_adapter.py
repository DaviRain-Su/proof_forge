"""ADR-0021 §1 + SPEC-TASKQUAL-001 §8.4 protected production adapter.

The protected adapter is the policy-pinned production consumer. It:
1. Obtains the exact current production policy ref/store snapshot and
   revocation records from the candidate-external authority store.
2. Obtains a trusted verification instant from a trusted clock.
3. Obtains live eligible handoff/FD/session/peer provenance.
4. Safe-opens C/D archives and authenticated Git objects.
5. Obtains immutable review reports.
6. Obtains resolved command/tool/probe/sandbox/verifier/build-policy bytes.
7. Constructs the canonical production bundle per §8.2.
8. Calls the same pure verifier.
9. Additionally proves the provenance/currentness properties.
10. Sends the unsigned acceptance to the v2 service terminal signer and
    returns only the service-signed acceptance bytes.

Any step failure does not return Verified. The protected adapter is the
only type that can claim ``production-candidate-bound`` and be accepted
by docs-check.

The accepted production API is ``protect_taskqualification_v1`` with exactly
seven required positional-only parameters (ADR-0021 §1). The adapter never
touches role private keys; the final three role signatures come from the v2
service terminal sign response. There is no caller seed, private-key bytes,
HSM handle, signer callback, path, environment or kwargs parameter.
"""

from __future__ import annotations

import fcntl
import hashlib
import os
import socket
import stat as _stat
from dataclasses import dataclass
from typing import Tuple

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_objects as _TQO
import task_qualification_verifier as _TQV
import task_qualification_authority_store_v2 as _STORE_V2
import formal_evidence as _FORMAL
import authority_store as _AUTH_STORE
import private_scan as _PRIVATE_SCAN
import stage0_handoff as _STAGE0

Rejected = _BTO.Rejected
TASKQUAL_REJECTION = _TQO.TASKQUAL_REJECTION

Digest = _BTO.Digest
ContentRef = _BTO.ContentRef
CandidateIdentity = _BTO.CandidateIdentity

canonical_pf_jcs = _BTO.canonical_pf_jcs
decode_canonical_pf_jcs = _BTO.decode_canonical_pf_jcs
domain_digest = _TQO.domain_digest
plain_sha256_digest = _TQO.plain_sha256_digest
digest_to_wire = _TQO.digest_to_wire
content_ref_to_wire = _TQO.content_ref_to_wire


def _content_ref_record_equal(left: object, right: object) -> bool:
    """Compare pinned ContentRef ABI values across exact-path module classes."""
    try:
        return (
            left.schema == right.schema
            and left.id == right.id
            and left.version == right.version
            and left.digest.algorithm == right.digest.algorithm
            and left.digest.bytes == right.digest.bytes
        )
    except AttributeError:
        return False


# ---------------------------------------------------------------------------
# v2 protocol constants re-exported for the RED matrix and consumers
# ---------------------------------------------------------------------------

V2_OPERATIONS = _STORE_V2.OPERATIONS
V2_MAX_FRAME_BYTES = _STORE_V2.MAX_FRAME_BYTES
V2_MAX_ACCEPTANCE_BYTES = _STORE_V2.MAX_ACCEPTANCE_BYTES

V2_ACCEPTANCE_SCHEMA = _STORE_V2.ACCEPTANCE_SCHEMA
V2_UNSIGNED_ACCEPTANCE_FIELDS = _STORE_V2.UNSIGNED_ACCEPTANCE_FIELDS
V2_SIGNED_ACCEPTANCE_FIELDS = _STORE_V2.SIGNED_ACCEPTANCE_FIELDS
V2_ACCEPTANCE_STATEMENT_DOMAIN = _STORE_V2.ACCEPTANCE_STATEMENT_DOMAIN
V2_ACCEPTANCE_SIGNATURE_DOMAIN = _STORE_V2.ACCEPTANCE_SIGNATURE_DOMAIN
V2_ACCEPTANCE_FULL_DOMAIN = _STORE_V2.ACCEPTANCE_FULL_DOMAIN

PROTECTED_HANDOFF_SCHEMA = _STORE_V2.HANDOFF_SCHEMA
HANDOFF_STATEMENT_DOMAIN = _STORE_V2.HANDOFF_STATEMENT_DOMAIN
HANDOFF_SIGNATURE_DOMAIN = _STORE_V2.HANDOFF_SIGNATURE_DOMAIN
HANDOFF_FULL_DOMAIN = _STORE_V2.HANDOFF_FULL_DOMAIN

# Domain aliases for backward-compatible symbol names used by RED matrix.
DOMAIN_PROTECTED_ACCEPTANCE = _STORE_V2.ACCEPTANCE_FULL_DOMAIN
PROTECTED_ACCEPTANCE_SCHEMA = _STORE_V2.ACCEPTANCE_SCHEMA

# The five inherited channel FD roles (ADR-0021 §1).
_FD_ROLES = (
    "authorityPolicyFd",
    "authorityStoreFd",
    "candidateArchiveFd",
    "provenanceBundleFd",
    "trustedClockFd",
)


# ---------------------------------------------------------------------------
# v2 acceptance wire helpers — ADR-0021 §4.3/§4.4 exact field manifest
# ---------------------------------------------------------------------------

def v2_unsigned_acceptance_to_wire(unsigned: dict) -> dict:
    """Return a copy of the unsigned acceptance dict with the exact v2 field
    manifest/order. The caller must have constructed the dict with exactly the
    19 accepted fields; this helper enforces and normalizes insertion order.
    """
    if type(unsigned) is not dict:
        _BTO._reject("v2 unsigned acceptance must be a closed object")
    if set(unsigned.keys()) != set(V2_UNSIGNED_ACCEPTANCE_FIELDS):
        _BTO._reject("v2 unsigned acceptance field manifest drift")
    if "signatures" in unsigned:
        _BTO._reject("v2 unsigned acceptance must not contain signatures")
    return {k: unsigned[k] for k in V2_UNSIGNED_ACCEPTANCE_FIELDS}


def v2_signed_acceptance_to_wire(signed: dict) -> dict:
    """Enforce the exact 20-field signed acceptance manifest/order."""
    if type(signed) is not dict:
        _BTO._reject("v2 signed acceptance must be a closed object")
    if set(signed.keys()) != set(V2_SIGNED_ACCEPTANCE_FIELDS):
        _BTO._reject("v2 signed acceptance field manifest drift")
    return {k: signed[k] for k in V2_SIGNED_ACCEPTANCE_FIELDS}


def v2_acceptance_statement_digest(unsigned: dict) -> bytes:
    """Compute the v2 acceptance statement digest (ADR-0021 §4.3)."""
    return _STORE_V2.acceptance_statement_digest(unsigned)


def v2_acceptance_full_digest(signed: dict) -> bytes:
    """Compute the v2 signed acceptance full digest under ACCEPTANCE_FULL_DOMAIN."""
    return _STORE_V2.domain_digest(V2_ACCEPTANCE_FULL_DOMAIN, signed).bytes


def v2_acceptance_content_ref(signed: dict) -> ContentRef:
    """Compute the ContentRef for a v2 signed acceptance."""
    full_digest = _STORE_V2.domain_digest(V2_ACCEPTANCE_FULL_DOMAIN, signed)
    return ContentRef(
        schema=V2_ACCEPTANCE_SCHEMA,
        id=signed["id"],
        version=signed["version"],
        digest=full_digest,
    )


# ---------------------------------------------------------------------------
# Stable early validation helpers — ADR-0021 §1/§3
# ---------------------------------------------------------------------------

def _v2_reject(detail: str) -> None:
    raise Rejected(TASKQUAL_REJECTION, f"protected-adapter-v2: {detail}")


def _validate_operation_bytes(operation_bytes: object) -> bytes:
    """Validate the operation bytes are exactly one of the four accepted ops."""
    if type(operation_bytes) is not bytes:
        _v2_reject("operationBytes must be exact bytes")
    if operation_bytes not in V2_OPERATIONS:
        _v2_reject("operationBytes is not an accepted operation")
    return operation_bytes


# ---------------------------------------------------------------------------
# Protected handoff parsing and verification — SPEC §8.4 / ADR-0021 §1
# ---------------------------------------------------------------------------

HANDOFF_FIELDS = (
    "schema", "id", "version", "taskId", "operation", "runId", "nonce",
    "candidate", "authorityPolicy", "productionProfilePin",
    "gateSetDigest", "adapter", "snapshotParser",
    "authorityStoreService", "trustedClockService",
    "revocationHead", "trustedInstant", "channels", "signatures",
)


def _parse_handoff(handoff_bytes: bytes) -> dict:
    """Parse the signed TaskQualificationProtectedHandoffV1 into a closed dict.

    Validates: canonical PF-JCS, closed field set, exact schema, version,
    and field types. Does not verify signatures (that requires the policy).
    """
    if type(handoff_bytes) is not bytes:
        _v2_reject("handoffBytes must be exact bytes")
    if not 1 <= len(handoff_bytes) <= V2_MAX_FRAME_BYTES:
        _v2_reject("handoffBytes length must be 1..4194304")
    try:
        obj = decode_canonical_pf_jcs(handoff_bytes)
    except Exception:
        _v2_reject("handoffBytes are not canonical PF-JCS")
    if type(obj) is not dict:
        _v2_reject("handoffBytes must decode to a closed object")
    if set(obj.keys()) != set(HANDOFF_FIELDS):
        _v2_reject("handoff field manifest/order drift")
    if obj["schema"] != PROTECTED_HANDOFF_SCHEMA:
        _v2_reject("handoff.schema is not the protected handoff schema")
    if obj["version"] != "1.0.0":
        _v2_reject("handoff.version must be 1.0.0")
    _STORE_V2._require_ascii_text(obj["id"], "handoff.id")
    _STORE_V2._require_ascii_text(obj["taskId"], "handoff.taskId")
    if type(obj["operation"]) is not str:
        _v2_reject("handoff.operation must be text")
    _STORE_V2._require_ascii_text(obj["runId"], "handoff.runId")
    _STORE_V2._require_ascii_text(obj["nonce"], "handoff.nonce")
    _STORE_V2._parse_content_ref(obj["authorityPolicy"], "handoff.authorityPolicy")
    _STORE_V2._parse_content_ref(
        obj["productionProfilePin"], "handoff.productionProfilePin")
    _STORE_V2._parse_digest_field(obj["gateSetDigest"], "handoff.gateSetDigest")
    _STORE_V2._parse_verifier_identity(obj["adapter"], "handoff.adapter")
    _STORE_V2._parse_verifier_identity(
        obj["snapshotParser"], "handoff.snapshotParser")
    _STORE_V2._parse_content_ref(
        obj["authorityStoreService"], "handoff.authorityStoreService")
    _STORE_V2._parse_verifier_identity(
        obj["trustedClockService"], "handoff.trustedClockService")
    rev_head = obj["revocationHead"]
    if type(rev_head) is not dict:
        _v2_reject("handoff.revocationHead must be an object")
    if set(rev_head.keys()) != {"headSequence", "headDigest"}:
        _v2_reject("handoff.revocationHead field drift")
    _STORE_V2._require_safe_int(
        rev_head["headSequence"], "handoff.revocationHead.headSequence")
    _STORE_V2._parse_digest_field(
        rev_head["headDigest"], "handoff.revocationHead.headDigest")
    if type(obj["trustedInstant"]) is not str or not obj["trustedInstant"]:
        _v2_reject("handoff.trustedInstant must be nonempty text")
    channels = obj["channels"]
    if type(channels) is not dict:
        _v2_reject("handoff.channels must be an object")
    if set(channels.keys()) != set(_FD_ROLES):
        _v2_reject("handoff.channels field drift")
    for role in _FD_ROLES:
        if type(channels[role]) is not int or channels[role] < 0:
            _v2_reject(f"handoff.channels.{role} must be a non-negative integer")
    sigs = obj["signatures"]
    if type(sigs) is not list:
        _v2_reject("handoff.signatures must be an array")
    for sig in sigs:
        if type(sig) is not dict:
            _v2_reject("handoff signature must be an object")
        if set(sig.keys()) != {"keyId", "algorithm", "signature"}:
            _v2_reject("handoff signature wire drift")
        if sig.get("algorithm") != "ed25519":
            _v2_reject("handoff signature algorithm must be ed25519")
        _STORE_V2._require_lowercase_hex(
            sig["signature"], 128, "handoff.signature")
    return obj


def _parse_handoff_typed(handoff_bytes: bytes):
    """Parse the handoff using the object worker's typed parser.

    This provides full structural validation via the objects module's
    ``parse_protected_handoff`` which checks the closed field set, types,
    derived id, and all nested objects. Returns a typed
    ``TaskQualificationProtectedHandoffV1``.
    """
    try:
        obj = decode_canonical_pf_jcs(handoff_bytes)
    except Exception:
        _v2_reject("handoffBytes are not canonical PF-JCS")
    try:
        return _TQO.parse_protected_handoff(obj, "handoff")
    except _BTO.Rejected as r:
        _v2_reject(f"handoff typed parse failed: {r.detail}")


def _verify_fixed_rule_signatures(
    subject_wire: dict,
    signatures: tuple,
    policy,
    statement_domain: bytes,
    signature_domain: bytes,
    where: str,
) -> None:
    """Verify the §1 fixed Architecture+Quality+Security signature rule.

    The signed handoff and trusted-clock observation both use a closed unsigned
    object formed by removing ``signatures``.  Every supplied signature is
    verified; key IDs must be strictly ASCII-sorted and unique, the count is
    3..256, and at least three distinct policy principals must jointly cover
    Architecture, Quality and Security.
    """
    if type(signatures) is not tuple:
        _v2_reject(f"{where}.signatures must be a parsed tuple")
    if not 3 <= len(signatures) <= 256:
        _v2_reject(f"{where}.signatures count must be 3..256")
    key_ids = [sig.keyId for sig in signatures]
    if key_ids != sorted(key_ids) or len(set(key_ids)) != len(key_ids):
        _v2_reject(f"{where}.signatures must have unique ASCII-sorted keyIds")

    unsigned = dict(subject_wire)
    if "signatures" not in unsigned:
        _v2_reject(f"{where} signed wire is missing signatures")
    unsigned.pop("signatures")
    statement = _STORE_V2.domain_digest(statement_domain, unsigned).bytes
    message = signature_domain + b"\x00" + statement

    principals = {principal.keyId: principal for principal in policy.principals}
    covered_roles = set()
    covered_principal_ids = set()
    for sig in signatures:
        if sig.algorithm != "ed25519":
            _v2_reject(f"{where} signature algorithm must be ed25519")
        principal = principals.get(sig.keyId)
        if principal is None:
            _v2_reject(f"{where} signer unknown: {sig.keyId}")
        if not _BTO.verify_ed25519(
                principal.publicKey, message, sig.signature):
            _v2_reject(f"{where} signature invalid: {sig.keyId}")
        covered_principal_ids.add(principal.principalId)
        covered_roles.update(principal.roles)

    if len(covered_principal_ids) < 3:
        _v2_reject(f"{where} signatures require three distinct principals")
    if not {"architecture", "quality", "security"}.issubset(covered_roles):
        _v2_reject(f"{where} signatures do not cover A+Q+S")


def _verify_handoff_signatures(handoff: dict, handoff_typed, policy) -> None:
    _verify_fixed_rule_signatures(
        handoff,
        handoff_typed.signatures,
        policy,
        HANDOFF_STATEMENT_DOMAIN,
        HANDOFF_SIGNATURE_DOMAIN,
        "handoff",
    )


def _verify_handoff_channels_match_fds(handoff: dict, fds: tuple) -> None:
    """Verify the handoff channels match the exact FD numbers passed."""
    channels = handoff["channels"]
    for role, fd in zip(_FD_ROLES, fds):
        if channels[role] != fd:
            _v2_reject(f"handoff.channels.{role} does not match API FD")


def _verify_v1_cross_reject(handoff: dict) -> None:
    """Cross-reject any v1 descriptor/protocol/frame (ADR-0021 §10)."""
    service = handoff.get("authorityStoreService")
    if type(service) is dict:
        schema = service.get("schema")
        if _STORE_V2.is_v1_descriptor_schema(schema):
            _v2_reject("v1 authority-store descriptor is rejected")


# ---------------------------------------------------------------------------
# FD validation — ADR-0021 §1 / SPEC §8.4
# ---------------------------------------------------------------------------

def _validate_distinct_fds(fds: tuple) -> None:
    if len(fds) != 5:
        _v2_reject("exactly five channel FDs are required")
    for fd in fds:
        if type(fd) is not int or fd < 0:
            _v2_reject("channel FD must be a non-negative integer")
    if len(set(fds)) != 5:
        _v2_reject("channel FDs must be distinct")


def _fd_is_socket(fd: int) -> bool:
    try:
        sock = socket.socket(fileno=fd)
        sock.detach()
        return True
    except OSError:
        return False


def _fd_is_regular_file(fd: int) -> bool:
    try:
        st = os.fstat(fd)
        return _stat.S_ISREG(st.st_mode)
    except OSError:
        return False


def _fd_is_single_link_regular(fd: int) -> bool:
    try:
        st = os.fstat(fd)
        if not _stat.S_ISREG(st.st_mode):
            return False
        if st.st_nlink != 1:
            return False
        return True
    except OSError:
        return False


def _fd_is_readonly(fd: int) -> bool:
    try:
        flags = fcntl.fcntl(fd, fcntl.F_GETFL)
        return (flags & os.O_ACCMODE) == os.O_RDONLY
    except OSError:
        return False


def _validate_channel_fds(fds: tuple) -> None:
    """Validate the five inherited channel FDs per ADR-0021 §1.

    - All five must be open (valid FDs).
    - The four non-store FDs must be read-only regular single-link files
      (stable, exact-consume).
    - ``authorityStoreFd`` must be a connected Linux ``AF_UNIX/SOCK_SEQPACKET``
      socket; regular files and ``SOCK_STREAM`` (v1) are rejected.
    """
    policy_fd, store_fd, archive_fd, provenance_fd, clock_fd = fds

    for role, fd in zip(_FD_ROLES, fds):
        try:
            os.fstat(fd)
        except OSError:
            _v2_reject(f"{role} is not an open FD")

    for role, fd in zip(
            ("authorityPolicyFd", "candidateArchiveFd",
             "provenanceBundleFd", "trustedClockFd"),
            (policy_fd, archive_fd, provenance_fd, clock_fd)):
        if not _fd_is_regular_file(fd):
            _v2_reject(f"{role} must be a regular file")
        if not _fd_is_single_link_regular(fd):
            _v2_reject(f"{role} must be a single-link regular file")
        if not _fd_is_readonly(fd):
            _v2_reject(f"{role} must be opened read-only")

    if not _fd_is_socket(store_fd):
        _v2_reject("authorityStoreFd must be a connected AF_UNIX/SOCK_SEQPACKET socket")
    try:
        sock = socket.socket(fileno=store_fd)
        try:
            family = sock.family
            sotype = sock.getsockopt(socket.SOL_SOCKET, socket.SO_TYPE)
        finally:
            sock.detach()
    except OSError:
        _v2_reject("authorityStoreFd is not a socket")
    if family != socket.AF_UNIX:
        _v2_reject("authorityStoreFd must be AF_UNIX")
    if sotype != socket.SOCK_SEQPACKET:
        _v2_reject(
            "authorityStoreFd must be SOCK_SEQPACKET; SOCK_STREAM (v1) is rejected")


def _enumerate_inherited_fds() -> tuple:
    """Enumerate the live process FD set through the pinned Linux proc view.

    ``listdir`` briefly opens its own directory FD.  Linux may include that FD
    in the returned names after it has already been closed, so every numeric
    entry is revalidated with ``fstat``.  An unavailable or malformed proc view
    is an authority failure, never a reason to skip the exact-FD check.
    """
    try:
        fd_entries = os.listdir("/proc/self/fd")
    except OSError as exc:
        _v2_reject(f"cannot enumerate inherited FDs: {exc}")

    open_fds = []
    for entry in fd_entries:
        if not entry.isascii() or not entry.isdecimal():
            _v2_reject("/proc/self/fd contained a non-canonical FD entry")
        fd = int(entry, 10)
        if str(fd) != entry:
            _v2_reject("/proc/self/fd contained a non-canonical FD number")
        try:
            os.fstat(fd)
        except OSError:
            # The directory FD used by listdir is normally closed before this
            # loop.  Ignore only entries that are demonstrably no longer open.
            continue
        open_fds.append(fd)
    return tuple(sorted(open_fds))


def _verify_inherited_fd_set(fds: tuple) -> None:
    """Verify the inherited FD set is exactly 0,1,2 plus the five channel FDs."""
    expected = {0, 1, 2, *fds}
    actual = set(_enumerate_inherited_fds())
    extra = actual - expected
    if extra:
        _v2_reject(f"inherited FD set has extra FDs: {sorted(extra)}")
    missing = expected - actual
    if missing:
        _v2_reject(f"inherited FD set is missing FDs: {sorted(missing)}")


# ---------------------------------------------------------------------------
# Channel FD reading helpers — SPEC §8.4
# ---------------------------------------------------------------------------

_STABLE_STAT_FIELDS = ("st_dev", "st_ino", "st_mode", "st_nlink", "st_size")


def _stable_stat_identity(st: os.stat_result) -> tuple:
    return tuple(getattr(st, field) for field in _STABLE_STAT_FIELDS)


def _read_stable_regular_fd(fd: int, maximum: int, role: str) -> bytes:
    """Read one inherited regular-file channel exactly from offset zero.

    The descriptor itself is consumed; no pathname is reopened.  The file must
    remain the same single-link regular inode, mode, link count and size across
    the complete read.  A short read, growth, truncation or metadata drift is a
    protected-authority failure.
    """
    try:
        before = os.fstat(fd)
    except OSError as exc:
        _v2_reject(f"{role} pre-read fstat failed: {exc}")
    if not _stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        _v2_reject(f"{role} must remain a single-link regular file")
    if not 1 <= before.st_size <= maximum:
        _v2_reject(f"{role} size must be 1..{maximum} bytes")

    chunks = []
    offset = 0
    try:
        while offset < before.st_size:
            chunk = os.pread(fd, min(1024 * 1024, before.st_size - offset), offset)
            if not chunk:
                _v2_reject(f"{role} short read")
            chunks.append(chunk)
            offset += len(chunk)
        if os.pread(fd, 1, before.st_size):
            _v2_reject(f"{role} grew during exact read")
        after = os.fstat(fd)
    except OSError as exc:
        _v2_reject(f"{role} exact read failed: {exc}")

    if _stable_stat_identity(before) != _stable_stat_identity(after):
        _v2_reject(f"{role} metadata changed during exact read")
    payload = b"".join(chunks)
    if len(payload) != before.st_size:
        _v2_reject(f"{role} exact byte count mismatch")
    return payload


def _read_authority_policy(policy_fd: int) -> tuple:
    """Read and parse the bootstrap authority policy from authorityPolicyFd."""
    policy_bytes = _read_stable_regular_fd(
        policy_fd, V2_MAX_FRAME_BYTES, "authorityPolicyFd")
    try:
        policy, policy_ref = _BTO.parse_bootstrap_authority_policy(policy_bytes)
    except Exception as exc:
        _v2_reject(f"authority policy invalid: {exc}")
    return policy, policy_ref, policy_bytes


def _read_trusted_clock_observation(clock_fd: int) -> tuple:
    """Read and validate the trusted clock observation from trustedClockFd."""
    clock_bytes = _read_stable_regular_fd(
        clock_fd, V2_MAX_FRAME_BYTES, "trustedClockFd")
    try:
        clock_obj = decode_canonical_pf_jcs(clock_bytes)
    except Exception:
        _v2_reject("trusted clock bytes are not canonical PF-JCS")
    if type(clock_obj) is not dict:
        _v2_reject("trusted clock must be a closed object")
    if clock_obj.get("schema") != _STORE_V2.CLOCK_OBSERVATION_SCHEMA:
        _v2_reject("trusted clock schema mismatch")
    return clock_obj, clock_bytes


def _read_provenance_bundle(provenance_fd: int) -> tuple:
    """Read and validate the provenance bundle from provenanceBundleFd."""
    bundle_bytes = _read_stable_regular_fd(
        provenance_fd, _TQO.MAX_BUNDLE_CANONICAL, "provenanceBundleFd")
    try:
        bundle_obj = _TQO.decode_taskqualification_large_jcs(bundle_bytes)
    except Exception:
        _v2_reject("provenance bundle bytes are not canonical PF-JCS")
    if type(bundle_obj) is not dict:
        _v2_reject("provenance bundle must be a closed object")
    if bundle_obj.get("schema") != _STORE_V2.PROVENANCE_BUNDLE_SCHEMA:
        _v2_reject("provenance bundle schema mismatch")
    return bundle_obj, bundle_bytes


def _read_candidate_archive(archive_fd: int) -> bytes:
    """Read the candidate archive bytes from candidateArchiveFd."""
    return _read_stable_regular_fd(
        archive_fd, _TQO.MAX_ARCHIVE_BYTES, "candidateArchiveFd")


# ---------------------------------------------------------------------------
# v2 service descriptor parsing — ADR-0021 §2
# ---------------------------------------------------------------------------

DESCRIPTOR_FIELDS = (
    "schema", "id", "version", "namespace", "protocol", "servicePublicKey",
    "verifier", "supervisor", "isolationPolicy", "signingKeyIds",
    "custodyKind", "adapterUid", "adapterGid", "serviceUid", "serviceGid",
    "userNamespace", "seedRoot", "peerInspectionProfile",
    "maximumFrameBytes", "maximumTerminalAcceptances",
)


def _parse_v2_descriptor(descriptor_bytes: bytes, expected_run_id: str) -> dict:
    """Parse and validate the v2 service descriptor (ADR-0021 §2)."""
    try:
        obj = decode_canonical_pf_jcs(descriptor_bytes)
    except Exception:
        _v2_reject("descriptor bytes are not canonical PF-JCS")
    if type(obj) is not dict:
        _v2_reject("descriptor must be a closed object")
    if set(obj.keys()) != set(DESCRIPTOR_FIELDS):
        _v2_reject("descriptor field manifest drift")
    if obj["schema"] != _STORE_V2.DESCRIPTOR_SCHEMA:
        _v2_reject("descriptor.schema is not the v2 service schema")
    if obj["version"] != "2.0.0":
        _v2_reject("descriptor.version must be 2.0.0")
    expected_id = f"task-qualification-store-service-{expected_run_id}"
    if obj["id"] != expected_id:
        _v2_reject(f"descriptor.id must be {expected_id}")
    if obj["namespace"] != _STORE_V2.NAMESPACE:
        _v2_reject("descriptor.namespace must be task-qualification-production-v1")
    if obj["protocol"] != _STORE_V2.PROTOCOL_ID:
        _v2_reject("descriptor.protocol must be pf.taskqual.authority-store.rpc.v2")
    if _STORE_V2.is_v1_protocol(obj["protocol"]):
        _v2_reject("v1 protocol in descriptor is rejected")
    _STORE_V2._require_lowercase_hex(
        obj["servicePublicKey"], 64, "descriptor.servicePublicKey")
    _STORE_V2._parse_verifier_identity(obj["verifier"], "descriptor.verifier")
    _STORE_V2._parse_verifier_identity(obj["supervisor"], "descriptor.supervisor")
    _STORE_V2._parse_content_ref(
        obj["isolationPolicy"], "descriptor.isolationPolicy")
    signing_key_ids = obj["signingKeyIds"]
    if type(signing_key_ids) is not list or len(signing_key_ids) != 3:
        _v2_reject("descriptor.signingKeyIds must be an array of exactly 3")
    for kid in signing_key_ids:
        _STORE_V2._require_ascii_text(kid, "descriptor.signingKeyIds item")
    if signing_key_ids != sorted(signing_key_ids):
        _v2_reject("descriptor.signingKeyIds must be ASCII-sorted")
    if len(set(signing_key_ids)) != 3:
        _v2_reject("descriptor.signingKeyIds must be distinct")
    if obj["custodyKind"] != "one-time-seed-fd-v1":
        _v2_reject("descriptor.custodyKind must be one-time-seed-fd-v1")
    for uid_field in ("adapterUid", "adapterGid", "serviceUid", "serviceGid"):
        value = _STORE_V2._require_safe_int(
            obj[uid_field], f"descriptor.{uid_field}")
        if not 1 <= value <= 2**31 - 1 or value == 65534:
            _v2_reject(
                f"descriptor.{uid_field} must be 1..2^31-1 and not overflow ID 65534")
    if obj["adapterUid"] == obj["serviceUid"]:
        _v2_reject("descriptor.adapterUid must differ from serviceUid")
    if obj["adapterGid"] == obj["serviceGid"]:
        _v2_reject("descriptor.adapterGid must differ from serviceGid")
    for identity_field in ("userNamespace", "seedRoot"):
        identity = obj[identity_field]
        if type(identity) is not dict or set(identity) != {"device", "inode"}:
            _v2_reject(
                f"descriptor.{identity_field} must be closed device/inode identity")
        _STORE_V2._require_safe_int(
            identity["device"], f"descriptor.{identity_field}.device")
        _STORE_V2._require_safe_int(
            identity["inode"], f"descriptor.{identity_field}.inode")
    if obj["maximumFrameBytes"] != _STORE_V2.MAX_FRAME_BYTES:
        _v2_reject("descriptor.maximumFrameBytes must be 4194304")
    if obj["maximumTerminalAcceptances"] != 1:
        _v2_reject("descriptor.maximumTerminalAcceptances must be 1")
    if obj["peerInspectionProfile"] != "linux-pidfd-proc-cross-uid-v1":
        _v2_reject("descriptor.peerInspectionProfile mismatch")
    return obj


def _verify_descriptor_authority(descriptor: dict, policy) -> None:
    """Join the descriptor's three role keys to the current policy."""
    principals = {principal.keyId: principal for principal in policy.principals}
    selected = []
    for key_id in descriptor["signingKeyIds"]:
        principal = principals.get(key_id)
        if principal is None:
            _v2_reject(f"descriptor signing key is not current: {key_id}")
        selected.append(principal)
    if len({principal.principalId for principal in selected}) != 3:
        _v2_reject("descriptor signing keys must map to three distinct principals")
    covered_roles = {
        role for principal in selected for role in principal.roles
    }
    if not {"architecture", "quality", "security"}.issubset(covered_roles):
        _v2_reject("descriptor signing keys do not cover A+Q+S")
    service_public_key = bytes.fromhex(descriptor["servicePublicKey"])
    if service_public_key in {principal.publicKey for principal in policy.principals}:
        _v2_reject("descriptor service key must not reuse a role key")


def _decode_lookup_verifier_identity(result, where: str) -> dict:
    """Decode a looked-up VerifierIdentityV1 and return its exact wire.

    A lookup response's ``content_ref`` authenticates the top-level lookup
    object; it is not itself a VerifierIdentityV1 and must never be compared as
    one.  The exact looked-up bytes are decoded and closed-validated first.
    """
    try:
        obj = decode_canonical_pf_jcs(result.object_bytes)
    except Exception:
        _v2_reject(f"{where} bytes are not canonical PF-JCS")
    try:
        return _STORE_V2._parse_verifier_identity(obj, where)
    except _BTO.Rejected as exc:
        _v2_reject(f"{where} is not a closed verifier identity: {exc.detail}")


# ---------------------------------------------------------------------------
# Accepted production entrypoint — ADR-0021 §1 (seven positional-only params)
# ---------------------------------------------------------------------------

def protect_taskqualification_v1(
    operationBytes,
    handoffBytes,
    authorityPolicyFd,
    authorityStoreFd,
    candidateArchiveFd,
    provenanceBundleFd,
    trustedClockFd,
    /,
):
    """ADR-0021 §1 accepted protected production adapter entrypoint.

    The only production API that can return ``production-candidate-bound``.
    Exactly seven required positional-only parameters; no path, environment,
    kwargs, default, typed shortcut, signing seed, private-key bytes, HSM
    handle or signer callback. The adapter never touches role private keys.

    The adapter does NOT read ``sys.argv``, ``stdin``, or the environment.
    The test harness (or authority-controlled launcher) consumes any manifest
    before calling this API and passes the seven parameters directly.

    Returns the exact signed acceptance bytes from the v2 service terminal
    response on success, or ``Rejected`` on any failure. A production-success
    acceptance requires an eligible Stage-0 host and a live v2 service process
    on the ``authorityStoreFd`` endpoint.
    """
    try:
        return _protect_taskqualification_v1_inner(
            operationBytes, handoffBytes,
            authorityPolicyFd, authorityStoreFd,
            candidateArchiveFd, provenanceBundleFd, trustedClockFd,
        )
    except Rejected as r:
        return r
    except Exception as exc:
        return Rejected(TASKQUAL_REJECTION, f"protected-adapter-v2: {exc}")


def _protect_taskqualification_v1_inner(
    operationBytes, handoffBytes,
    authorityPolicyFd, authorityStoreFd,
    candidateArchiveFd, provenanceBundleFd, trustedClockFd,
):
    # --- Stable early validation before any curve work (ADR-0021 §1/§3) ---
    operation_bytes = _validate_operation_bytes(operationBytes)
    handoff = _parse_handoff(handoffBytes)
    handoff_typed = _parse_handoff_typed(handoffBytes)
    fds = (
        authorityPolicyFd, authorityStoreFd,
        candidateArchiveFd, provenanceBundleFd, trustedClockFd,
    )
    _validate_distinct_fds(fds)
    _validate_channel_fds(fds)
    _verify_inherited_fd_set(fds)
    _verify_handoff_channels_match_fds(handoff, fds)
    _verify_v1_cross_reject(handoff)

    # Verify handoff operation matches API operation
    if handoff["operation"] != operation_bytes.decode("ascii"):
        _v2_reject("handoff.operation does not match operationBytes")

    # --- Read and verify the current authority policy (SPEC §8.4) ---
    policy, policy_ref, policy_bytes = _read_authority_policy(authorityPolicyFd)
    handoff_policy_ref = handoff["authorityPolicy"]
    if not _STORE_V2._content_ref_equal(
            content_ref_to_wire(policy_ref), handoff_policy_ref):
        _v2_reject("authority policy ref does not match handoff")

    # --- Verify the handoff signatures using the verified policy ---
    _verify_handoff_signatures(handoff, handoff_typed, policy)

    # --- Read the trusted clock observation (SPEC §8.4) ---
    clock_obj, clock_bytes = _read_trusted_clock_observation(trustedClockFd)
    # Parse the clock using the object worker's typed parser
    try:
        clock_typed = _TQO.parse_trusted_clock_observation(clock_obj, "trusted-clock")
    except _BTO.Rejected as r:
        _v2_reject(f"trusted clock parse failed: {r.detail}")
    clock_tuple = (
        clock_typed.taskId,
        clock_typed.operation,
        clock_typed.runId,
        clock_typed.nonce,
    )
    handoff_tuple = (
        handoff_typed.taskId,
        handoff_typed.operation,
        handoff_typed.runId,
        handoff_typed.nonce,
    )
    if clock_tuple != handoff_tuple:
        _v2_reject("trusted clock task/operation/run/nonce does not match handoff")
    if clock_typed.observedAt != handoff["trustedInstant"]:
        _v2_reject("clock observedAt does not match handoff.trustedInstant")
    if not _STORE_V2._verifier_identity_equal(
            _TQO.verifier_identity_to_wire(clock_typed.trustedClockService),
            handoff["trustedClockService"]):
        _v2_reject("clock trustedClockService does not match handoff")
    _verify_fixed_rule_signatures(
        clock_obj,
        clock_typed.signatures,
        policy,
        _STORE_V2.CLOCK_STATEMENT_DOMAIN,
        _STORE_V2.CLOCK_SIGNATURE_DOMAIN,
        "trusted-clock",
    )

    # --- Read the provenance bundle (SPEC §8.4) ---
    provenance_bundle_obj, provenance_bundle_bytes = _read_provenance_bundle(
        provenanceBundleFd)
    # Parse the provenance bundle using the object worker's typed parser
    try:
        provenance_typed = _TQO.parse_provenance_bundle(
            provenance_bundle_obj, "provenance-bundle")
    except _BTO.Rejected as r:
        _v2_reject(f"provenance bundle parse failed: {r.detail}")
    provenance_bundle_digest = plain_sha256_digest(provenance_bundle_bytes)
    provenance_tuple = (
        provenance_typed.taskId,
        provenance_typed.operation,
        provenance_typed.runId,
        provenance_typed.nonce,
    )
    if provenance_tuple != handoff_tuple:
        _v2_reject("provenance task/operation/run/nonce does not match handoff")

    if not provenance_typed.entries:
        _v2_reject("provenance bundle entries must be a nonempty array")
    provenance_roles = [entry.role for entry in provenance_typed.entries]
    provenance_entry_bytes = {
        entry.role: bytes.fromhex(entry.bytesHex)
        for entry in provenance_typed.entries
    }

    # --- Read the candidate archive and bind it to both signed carriers ---
    archive_bytes = _read_candidate_archive(candidateArchiveFd)
    archive_digest = plain_sha256_digest(archive_bytes)
    if archive_digest != provenance_typed.candidateArchiveSha256:
        _v2_reject("candidate archive digest does not match provenance bundle")
    if digest_to_wire(archive_digest) != handoff["candidate"]["archiveSha256"]:
        _v2_reject("candidate archive digest does not match handoff.candidate")

    # --- Build the handoff tuple for the protocol frames ---
    rev_head = handoff["revocationHead"]
    handoff_digest = _STORE_V2.domain_digest(
        HANDOFF_FULL_DOMAIN, handoff).bytes
    service_ref = handoff["authorityStoreService"]
    tpl = _STORE_V2.HandoffTuple(
        taskId=handoff["taskId"],
        operation=handoff["operation"],
        runId=handoff["runId"],
        nonce=handoff["nonce"],
        service=service_ref,
        handoffDigest=handoff_digest,
        headSequence=rev_head["headSequence"],
        headDigest=bytes.fromhex(rev_head["headDigest"][7:]),
    )

    # --- Drive the v2 protocol over the authorityStoreFd ---
    # The adapter sends the client hello, receives the server hello, then
    # drives the fixed lookup transcript. The server hello and all lookup
    # responses are service-signed; the service public key is in the v2
    # descriptor (lookup item 5). The adapter buffers the server hello and
    # all lookup responses, obtains the descriptor from item 5, extracts the
    # service public key, then verifies all buffered signatures in order.
    # ``socket.socket(fileno=...)`` adopts the exact inherited endpoint without
    # duplicating it.  Keep the wrapper attached for the complete one-shot
    # transcript; detaching here would invalidate every subsequent operation.
    sock = socket.socket(fileno=authorityStoreFd)

    gate_set_digest = bytes.fromhex(handoff["gateSetDigest"][7:])
    object_ids = {
        "authority-policy": policy_ref.id,
        "production-profile-pin": handoff["productionProfilePin"]["id"],
        "adapter": handoff["adapter"]["id"],
        "snapshot-parser": handoff["snapshotParser"]["id"],
        "authority-store-service": service_ref["id"],
        "trusted-clock-service": handoff["trustedClockService"]["id"],
    }
    revocation_head = (rev_head["headSequence"],
                       bytes.fromhex(rev_head["headDigest"][7:]))

    # Send client hello
    client_hello_payload = _STORE_V2.build_client_hello(tpl)
    _STORE_V2.send_packet(sock, client_hello_payload)

    # Receive server hello (buffer for signature verification after
    # the descriptor lookup provides the service public key)
    server_hello_payload = _STORE_V2.recv_packet(sock)
    server_hello = _STORE_V2._decode_frame(server_hello_payload)
    if server_hello.get("schema") in _STORE_V2.V1_FRAME_SCHEMAS:
        _v2_reject("v1 server hello frame is rejected")
    _STORE_V2._require_exact_keys(
        server_hello, _STORE_V2.SERVER_HELLO_FIELDS, "server-hello")
    if server_hello["schema"] != _STORE_V2.SERVER_HELLO_SCHEMA:
        _v2_reject("server-hello.schema is not the v2 server hello schema")
    if server_hello["version"] != _STORE_V2.VERSION:
        _v2_reject("server-hello.version must be 2.0.0")
    if server_hello["status"] != "ready":
        _v2_reject("server-hello.status must be ready")
    _STORE_V2._check_echo(server_hello, tpl, has_handoff_digest=True)

    # Drive the fixed lookup transcript. The responses are service-signed;
    # we buffer them and verify after obtaining the service public key from
    # the descriptor (lookup item 5).
    lookup_results = _run_buffered_lookup_transcript(
        sock, tpl, gate_set_digest, object_ids, revocation_head)

    # Extract the descriptor (item 5: authority-store-service)
    descriptor_result = None
    for result in lookup_results:
        if result.object_kind == "authority-store-service":
            descriptor_result = result
            break
    if descriptor_result is None:
        _v2_reject("authority-store-service descriptor not found in transcript")

    # Parse and verify the v2 descriptor
    descriptor = _parse_v2_descriptor(
        descriptor_result.object_bytes, handoff["runId"])
    descriptor_ref = _STORE_V2.recompute_object_content_ref(
        "authority-store-service", descriptor_result.object_bytes)
    if not _STORE_V2._content_ref_equal(
            content_ref_to_wire(descriptor_ref), service_ref):
        _v2_reject("descriptor ref does not match handoff.authorityStoreService")
    _verify_descriptor_authority(descriptor, policy)
    service_public_key = bytes.fromhex(descriptor["servicePublicKey"])

    # Now verify the server hello signature (buffered)
    _STORE_V2.verify_server_signature(server_hello, service_public_key)

    # Verify all lookup response signatures (buffered)
    for result in lookup_results:
        _STORE_V2.verify_server_signature(result.response, service_public_key)

    # --- Authority equality chain (SPEC §8.4) ---
    # Verify the looked-up policy ref matches handoff.authorityPolicy
    policy_result = None
    pin_result = None
    profile_result = None
    adapter_result = None
    parser_result = None
    clock_service_result = None
    snapshot_result = None
    for result in lookup_results:
        if result.object_kind == "authority-policy":
            policy_result = result
        elif result.object_kind == "production-profile-pin":
            pin_result = result
        elif result.object_kind == "production-profile":
            profile_result = result
        elif result.object_kind == "adapter":
            adapter_result = result
        elif result.object_kind == "snapshot-parser":
            parser_result = result
        elif result.object_kind == "trusted-clock-service":
            clock_service_result = result
        elif result.object_kind == "revocation-snapshot":
            snapshot_result = result

    if policy_result is None:
        _v2_reject("authority-policy not found in transcript")
    # The looked-up policy ref must match the handoff's authorityPolicy
    if not _STORE_V2._content_ref_equal(
            policy_result.content_ref, handoff_policy_ref):
        _v2_reject("looked-up policy ref does not match handoff")
    if policy_result.object_bytes != policy_bytes:
        _v2_reject("looked-up policy bytes do not equal authorityPolicyFd bytes")

    # Verify the pin ref matches handoff.productionProfilePin
    if pin_result is None:
        _v2_reject("production-profile-pin not found in transcript")
    if not _STORE_V2._content_ref_equal(
            pin_result.content_ref, handoff["productionProfilePin"]):
        _v2_reject("looked-up pin ref does not match handoff")

    # Verify the pin's authorityPolicy matches the policy ref
    try:
        pin_obj = decode_canonical_pf_jcs(pin_result.object_bytes)
    except Exception:
        _v2_reject("pin bytes are not canonical PF-JCS")
    if type(pin_obj) is not dict:
        _v2_reject("pin must be a closed object")
    if not _STORE_V2._content_ref_equal(
            pin_obj.get("authorityPolicy"), handoff_policy_ref):
        _v2_reject("pin.authorityPolicy does not match policy ref")

    # Verify the profile ref matches pin.profile
    if profile_result is None:
        _v2_reject("production-profile not found in transcript")
    if not _STORE_V2._content_ref_equal(
            profile_result.content_ref, pin_obj.get("profile")):
        _v2_reject("looked-up profile ref does not match pin.profile")

    # Verify the profile's expectedAuthorityPolicy matches the policy ref
    try:
        profile_obj = decode_canonical_pf_jcs(profile_result.object_bytes)
    except Exception:
        _v2_reject("profile bytes are not canonical PF-JCS")
    if type(profile_obj) is not dict:
        _v2_reject("profile must be a closed object")
    if not _STORE_V2._content_ref_equal(
            profile_obj.get("expectedAuthorityPolicy"), handoff_policy_ref):
        _v2_reject("profile.expectedAuthorityPolicy does not match policy ref")

    # Verify the profile's adapter matches the handoff's adapter
    if not _STORE_V2._verifier_identity_equal(
            profile_obj.get("adapter"), handoff["adapter"]):
        _v2_reject("profile.adapter does not match handoff.adapter")

    # Verify the pin's expectedSnapshotParser matches the handoff's snapshotParser
    if not _STORE_V2._verifier_identity_equal(
            pin_obj.get("expectedSnapshotParser"), handoff["snapshotParser"]):
        _v2_reject("pin.expectedSnapshotParser does not match handoff.snapshotParser")

    # Verify the looked-up identities from their exact object bytes.  The
    # lookup ContentRef is not interchangeable with the embedded identity.
    if adapter_result is None:
        _v2_reject("adapter not found in transcript")
    looked_up_adapter = _decode_lookup_verifier_identity(
        adapter_result, "looked-up-adapter")
    if not _STORE_V2._verifier_identity_equal(
            looked_up_adapter, handoff["adapter"]):
        _v2_reject("looked-up adapter does not match handoff.adapter")

    if parser_result is None:
        _v2_reject("snapshot-parser not found in transcript")
    looked_up_parser = _decode_lookup_verifier_identity(
        parser_result, "looked-up-snapshot-parser")
    if not _STORE_V2._verifier_identity_equal(
            looked_up_parser, handoff["snapshotParser"]):
        _v2_reject("looked-up snapshot-parser does not match handoff.snapshotParser")

    if clock_service_result is None:
        _v2_reject("trusted-clock-service not found in transcript")
    looked_up_clock = _decode_lookup_verifier_identity(
        clock_service_result, "looked-up-trusted-clock-service")
    if not _STORE_V2._verifier_identity_equal(
            looked_up_clock, handoff["trustedClockService"]):
        _v2_reject("looked-up trusted clock service does not match handoff")
    if not _STORE_V2._verifier_identity_equal(
            looked_up_clock,
            _TQO.verifier_identity_to_wire(clock_typed.trustedClockService)):
        _v2_reject("looked-up trusted clock service does not match clock observation")

    # --- Current head check (SPEC §8.4 / ADR-0021 §6) ---
    # The revocation head from the lookup must match the handoff's head
    if snapshot_result is None:
        _v2_reject("revocation-snapshot not found in transcript")
    # The head tuple belongs to the authenticated authority-store log and was
    # already exact-echoed by every signed frame. The looked-up object is the
    # existing RevocationLedgerSnapshotV1; it does not grow invented
    # headSequence/headDigest fields. Parse and verify its complete signed
    # snapshot/record closure under the current policy.
    revocation_record_bytes = tuple(
        result.object_bytes
        for result in lookup_results
        if result.object_kind == _STORE_V2.REVOCATION_RECORD_KIND
    )
    try:
        current_revocation_snapshot = _FORMAL.parse_revocation_ledger_snapshot(
            snapshot_result.object_bytes, policy, revocation_record_bytes)
    except _BTO.Rejected as exc:
        _v2_reject(f"current revocation snapshot invalid: {exc.detail}")
    if not _content_ref_record_equal(
            current_revocation_snapshot.authorityPolicy, policy_ref):
        _v2_reject("current revocation snapshot authorityPolicy mismatch")

    # --- Build the production bundle and call the pure verifier ---
    # The production bundle is constructed per §8.2 from the archive, provenance
    # and resolved artifacts. The pure verifier takes (bundleBytes, subjectBytes).
    # The subject is the operation-specific signed object (qualification,
    # completion receipt, D0-10 approval, or D0-10 receipt).
    #
    # The provenance bundle entries carry the raw bytes for each role. The
    # adapter projects each entry to a ContentMemberV1 wire using the §8.2
    # role→kind mapping. The production profile (with its artifacts mapping)
    # is embedded as the bundle's verificationProfile.

    # Parse the looked-up profile and pin using the object worker's parsers
    try:
        profile_obj_typed = _TQO.parse_production_verification_profile(
            profile_obj, "looked-up-profile")
    except _BTO.Rejected as r:
        _v2_reject(f"looked-up profile parse failed: {r.detail}")
    try:
        pin_obj_typed = _TQO.parse_production_profile_pin(
            pin_obj, "looked-up-pin")
    except _BTO.Rejected as r:
        _v2_reject(f"looked-up pin parse failed: {r.detail}")

    # Join pin to profile (§8.2 field-by-field equality)
    try:
        _TQO.join_pin_to_profile(pin_obj_typed, profile_obj_typed)
    except _BTO.Rejected as r:
        _v2_reject(f"pin-profile join failed: {r.detail}")
    if (
        profile_obj_typed.taskId != handoff_typed.taskId
        or profile_obj_typed.operation != handoff_typed.operation
        or profile_obj_typed.gateSetDigest != handoff_typed.gateSetDigest
    ):
        _v2_reject("profile task/operation/gateSetDigest does not match handoff")
    if profile_obj_typed.expectedAuthorityPolicy != policy_ref:
        _v2_reject("profile expectedAuthorityPolicy does not match policy bytes")
    if pin_obj_typed.authorityPolicy != policy_ref:
        _v2_reject("pin authorityPolicy does not match policy bytes")
    if profile_obj_typed.adapter != handoff_typed.adapter:
        _v2_reject("profile adapter does not match handoff")
    if profile_obj_typed.snapshotParser != handoff_typed.snapshotParser:
        _v2_reject("profile snapshotParser does not match handoff")

    # Verify the pin signatures using the verified policy
    try:
        _TQO.verify_production_profile_pin_signatures(pin_obj_typed, policy)
    except _BTO.Rejected as r:
        _v2_reject(f"pin signature verification failed: {r.detail}")

    # Verify the profile signatures using the verified policy
    try:
        _TQV._verify_production_profile_signatures(
            profile_obj_typed, policy, "looked-up-profile")
    except _BTO.Rejected as r:
        _v2_reject(f"profile signature verification failed: {r.detail}")

    operation_str = operation_bytes.decode("ascii")
    subject_role = _SUBJECT_ROLES.get(operation_str)
    if subject_role is None:
        _v2_reject(f"unknown operation for subject extraction: {operation_str}")
    subject_bytes = _require_provenance_bytes(
        provenance_entry_bytes, subject_role)
    excluded_roles = _protected_only_roles(operation_str, profile_obj_typed)
    _validate_provenance_source_joins(
        provenance_entry_bytes,
        operation_str,
        excluded_roles,
        handoff_bytes=handoffBytes,
        policy_bytes=policy_bytes,
        profile_bytes=profile_result.object_bytes,
        pin_bytes=pin_result.object_bytes,
        clock_bytes=clock_bytes,
        snapshot_bytes=snapshot_result.object_bytes,
        descriptor_bytes=descriptor_result.object_bytes,
        archive_bytes=archive_bytes,
        subject_bytes=subject_bytes,
        provenance_subject_digest=provenance_typed.subjectDigest,
        profile=profile_obj_typed,
        lookup_results=lookup_results,
    )

    # Only ordinary §8.2 roles become pure bundle members.  Subject,
    # protected-only sources and profile artifact payloads remain bound solely
    # through the provenance digest/role projection and external joins.
    bundle_members = _project_provenance_to_members(
        provenance_bundle_obj, operation_str, excluded_roles)

    # Build the bundle wire
    bundle_id = _TQO.OPERATION_BUNDLE_IDS[operation_str]
    bundle_wire = {
        "schema": _TQO.BUNDLE_SCHEMA,
        "id": bundle_id,
        "version": "1.0.0",
        "operation": operation_str,
        "verificationProfile": _TQO.production_profile_to_wire(profile_obj_typed),
        "expectedAuthorityPolicy": content_ref_to_wire(policy_ref),
        "verificationInstant": handoff["trustedInstant"],
        "implementationInvocationId": handoff["runId"],
        "members": bundle_members,
    }
    bundle_bytes = _TQO.canonical_taskqualification_large_jcs(bundle_wire)

    # Call the pure verifier for the operation
    verified = _call_pure_verifier(operation_str, bundle_bytes, subject_bytes)
    if isinstance(verified, _BTO.Rejected):
        _v2_reject(f"pure verifier rejected: {verified.detail}")

    # Join the pure subject projection back to the signed protected handoff.
    if verified.taskId != handoff_typed.taskId:
        _v2_reject("pure verifier taskId does not match handoff")
    if operation_str in ("task-qualification", "d0-10-bootstrap-approval"):
        verified_candidate = verified.preCloseCandidate
    else:
        verified_candidate = verified.closeoutCandidate
    if verified_candidate != handoff_typed.candidate:
        _v2_reject("pure verifier candidate does not match handoff.candidate")

    # Verify the pure verifier's authorityClass is production-content-verified
    if verified.authorityClass != "production-content-verified":
        _v2_reject(
            f"pure verifier authorityClass is {verified.authorityClass}, "
            "not production-content-verified")

    # Verify the pure verifier's authorityPolicy matches the handoff
    if verified.authorityPolicy != policy_ref:
        _v2_reject("pure verifier authorityPolicy does not match policy ref")

    # Verify the pure verifier's verificationInstant matches the handoff
    if verified.verificationInstant != handoff["trustedInstant"]:
        _v2_reject("pure verifier verificationInstant does not match handoff")

    # --- Construct the exact unsigned ProtectedTaskQualificationAcceptanceV1 ---
    pure_projection = _serialize_pure_projection(verified)
    pure_projection_digest = domain_digest(
        _TQO.DOMAIN_PURE_PROJECTION, pure_projection)
    bundle_digest = plain_sha256_digest(bundle_bytes)
    subject_digest = plain_sha256_digest(subject_bytes)
    profile_digest = domain_digest(
        _TQO.DOMAIN_PRODUCTION_PROFILE,
        _TQO.production_profile_to_wire(profile_obj_typed))
    pin_ref = _TQO.production_profile_pin_content_ref(pin_obj_typed)
    if pin_ref != handoff_typed.productionProfilePin:
        _v2_reject("recomputed production profile pin does not match handoff")

    # D0-10 receipt nullable fields bind the separately verified external
    # Ledger projection and GovernanceBootstrapCompletion full objects.
    if operation_str == "d0-10-bootstrap-receipt":
        (
            ledger_projection_digest,
            governance_completion_digest,
        ) = _verify_d0_receipt_external_objects(
            provenance_entry_bytes,
            subject_bytes,
            verified,
            policy,
            profile_obj_typed,
        )
        closeout_candidate = verified.closeoutCandidate
    else:
        ledger_projection_digest = None
        governance_completion_digest = None
        closeout_candidate = (
            verified.closeoutCandidate
            if operation_str == "task-completion" else None)

    task_suffix = handoff["taskId"].lower().replace("task-", "")
    acceptance_id = f"protected-task-qualification-{operation_str}-{task_suffix}"

    unsigned_acceptance = {
        "schema": V2_ACCEPTANCE_SCHEMA,
        "id": acceptance_id,
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": operation_str,
        "pureProjectionDigest": digest_to_wire(pure_projection_digest),
        "bundleDigest": digest_to_wire(bundle_digest),
        "subjectDigest": digest_to_wire(subject_digest),
        "preCloseCandidate": _TQO.candidate_identity_to_wire(
            verified.preCloseCandidate),
        "closeoutCandidate": (
            _TQO.candidate_identity_to_wire(closeout_candidate)
            if closeout_candidate is not None else None),
        "trustedVerificationInstant": handoff["trustedInstant"],
        "adapter": handoff["adapter"],
        "snapshotParser": handoff["snapshotParser"],
        "productionProfileDigest": digest_to_wire(profile_digest),
        "productionProfilePin": content_ref_to_wire(pin_ref),
        "ledgerProjectionDigest": (
            digest_to_wire(ledger_projection_digest)
            if ledger_projection_digest is not None else None),
        "governanceCompletionDigest": (
            digest_to_wire(governance_completion_digest)
            if governance_completion_digest is not None else None),
        "provenanceBundleDigest": digest_to_wire(provenance_bundle_digest),
        "provenanceRoles": provenance_roles,
    }

    # --- Send the terminal sign request ---
    terminal_rid = len(lookup_results)
    terminal_request_payload = _STORE_V2.build_terminal_request(
        terminal_rid, tpl,
        handoff["adapter"],
        content_ref_to_wire(pin_ref),
        handoff["snapshotParser"],
        unsigned_acceptance)
    _STORE_V2.send_packet(sock, terminal_request_payload)

    # Receive and verify the terminal response
    terminal_response_payload = _STORE_V2.recv_packet(sock)
    authority_principals = {p.keyId: p for p in policy.principals}
    signed_acceptance_bytes = _STORE_V2.parse_terminal_response(
        terminal_response_payload, terminal_rid, tpl,
        unsigned_acceptance, service_public_key,
        authority_principals=authority_principals)

    # --- Return only the service-signed acceptance bytes ---
    # Release Python ownership without duplicating or closing the inherited
    # one-shot channel; the authority-controlled process lifecycle owns it.
    sock.detach()
    return signed_acceptance_bytes


# ---------------------------------------------------------------------------
# Helpers for the real qualified path
# ---------------------------------------------------------------------------

# Subject role per operation (SPEC §8.2)
_SUBJECT_ROLES = {
    "task-qualification": "qualification",
    "task-completion": "completion-receipt",
    "d0-10-bootstrap-approval": "bootstrap-approval",
    "d0-10-bootstrap-receipt": "bootstrap-receipt",
}

# The archive inherited through candidateArchiveFd is C for qualification /
# approval and D for the two closeout receipt operations.
_CHANNEL_ARCHIVE_ROLES = {
    "task-qualification": "candidate-archive",
    "task-completion": "closeout-archive",
    "d0-10-bootstrap-approval": "candidate-archive",
    "d0-10-bootstrap-receipt": "closeout-archive",
}

# These provenance entries bind protected-only inputs and must never be
# projected into the pure §8.2 content bundle.  ``production-profile`` is
# intentionally absent: it is both externally joined and the one production
# profile member required by the pure verifier.
_PROTECTED_ONLY_BASE_ROLES = frozenset({
    "production-profile-pin",
    "live-handoff",
    "live-session",
    "trusted-clock-observation",
    "current-revocation-snapshot",
    "authority-store-service-descriptor",
    "authority-store-executable",
    "authority-store-closure",
    "authority-store-build-policy",
    "adapter-executable",
    "adapter-closure",
    "adapter-build-policy",
    "snapshot-parser-executable",
    "snapshot-parser-closure",
    "snapshot-parser-build-policy",
    "trusted-clock-executable",
    "trusted-clock-closure",
    "trusted-clock-build-policy",
    "store-supervisor-executable",
    "store-supervisor-closure",
    "store-supervisor-build-policy",
    "store-isolation-policy",
})
_D0_RECEIPT_PROTECTED_ONLY_ROLES = frozenset({
    "governance-bootstrap-completion",
    "receipt-ledger-projection",
})


def _require_provenance_bytes(
    entries: dict, role: str, expected: bytes | None = None,
) -> bytes:
    payload = entries.get(role)
    if payload is None:
        _v2_reject(f"provenance role missing: {role}")
    if expected is not None and payload != expected:
        _v2_reject(f"provenance role bytes do not match protected source: {role}")
    return payload


_RAW_GATE_OWNER_PREFIXES = frozenset({
    "resolved-tool", "resolved-tool-closure", "resolved-probe",
    "sandbox-policy", "verifier-executable", "verifier-closure",
    "verifier-build-policy", "private-scan-scanner",
})
_TYPED_GATE_OWNER_KINDS = {
    "private-scan-policy": "private-scan-policy-v1",
    "authority-store-service": "authority-store-service-v1",
    "host-observation": "host-observation-v1",
    "host-profile": "host-profile-v1",
}
_RAW_EXACT_OWNER_ROLES = frozenset(
    _TQO.D0_10_TOP_LEVEL_ARTIFACT_ROLES
) | frozenset(
    f"{prefix}-{part}"
    for prefix in (
        "authority-store", "adapter", "snapshot-parser", "trusted-clock",
        "store-supervisor",
    )
    for part in ("executable", "closure", "build-policy")
)
_ISOLATION_POLICY_SCHEMA = (
    "proof-forge.task-qualification-store-isolation-policy.v2"
)
_ISOLATION_POLICY_DOMAIN = b"pf.taskqual.store-isolation-policy.v2"
_ISOLATION_POLICY_FIELDS = (
    "schema", "id", "version", "namespace", "taskId", "operation",
    "runId", "nonce", "userNamespace", "parentPidNamespace",
    "adapterPidNamespace", "serviceMountNamespace", "adapterMountNamespace",
    "uidMap", "gidMap", "adapterUid", "adapterGid", "serviceUid",
    "serviceGid", "serviceProcRoot", "durableStateRoot", "seedRoot",
    "serviceMounts", "adapterMounts", "fdRoles", "socketDomain",
    "socketType", "socketCreation", "socketSendFlags", "passCredentials",
    "requestedSocketBufferBytes", "minimumEffectiveSocketBufferBytes",
    "preSeedCapabilities", "custodyCapabilities", "adapterCapabilities",
    "finalServiceCapabilities", "serviceExecutableFd", "serviceArgv",
    "serviceEnvironment", "execOperation", "staticElfRequired",
    "seccompPolicies", "maximumFrameBytes", "maximumTerminalAcceptances",
)


def _artifact_owner_kind_for_role(role, /) -> str:
    """Return the one accepted owner for a production/protected payload role."""
    if type(role) is not str or not role:
        _v2_reject("artifact owner role must be nonempty text")
    if role in _RAW_EXACT_OWNER_ROLES:
        return "taskqual-artifact-payload-v1"
    if role == "authority-store-service-descriptor":
        return "taskqual-store-descriptor-v2"
    if role == "store-isolation-policy":
        return "taskqual-store-isolation-policy-v2"
    prefix, separator, suffix = role.partition("/")
    if separator != "/" or not suffix or "/" in suffix:
        _v2_reject(f"artifact owner role is not in the closed registry: {role}")
    try:
        _TQO._require_ascii_text(
            suffix, _TQO.PROFILE_ID_RE, "artifact owner gate suffix", 127
        )
    except _BTO.Rejected:
        _v2_reject(f"artifact owner role has an invalid gate suffix: {role}")
    if prefix in _RAW_GATE_OWNER_PREFIXES:
        return "taskqual-artifact-payload-v1"
    owner = _TYPED_GATE_OWNER_KINDS.get(prefix)
    if owner is None:
        _v2_reject(f"artifact owner role is not in the closed registry: {role}")
    return owner


def _require_claimed_content_ref(claimed_ref, where: str) -> ContentRef:
    if type(claimed_ref) is not ContentRef:
        _v2_reject(f"{where} must be a parsed ContentRef")
    try:
        _TQO._require_content_ref_id(claimed_ref.id, f"{where}.id")
        _TQO._require_semver(claimed_ref.version, f"{where}.version")
    except _BTO.Rejected as exc:
        _v2_reject(f"{where} id/version invalid: {exc.detail}")
    if (
        type(claimed_ref.digest) is not Digest
        or claimed_ref.digest.algorithm != "sha256"
        or len(claimed_ref.digest.bytes) != 32
    ):
        _v2_reject(f"{where}.digest must be sha256")
    return claimed_ref


def _recompute_host_raw_ref(
    claimed_ref: ContentRef, payload: bytes, expected_schema: str,
) -> ContentRef:
    if claimed_ref.schema != expected_schema:
        _v2_reject("host payload schema does not match its role owner")
    return ContentRef(
        schema=expected_schema,
        id=claimed_ref.id,
        version=claimed_ref.version,
        digest=plain_sha256_digest(payload),
    )


def _recompute_isolation_policy_ref(payload: bytes) -> ContentRef:
    try:
        obj = decode_canonical_pf_jcs(payload)
    except Exception:
        _v2_reject("store isolation policy is not canonical PF-JCS")
    if type(obj) is not dict or set(obj) != set(_ISOLATION_POLICY_FIELDS):
        _v2_reject("store isolation policy field manifest drift")
    if obj["schema"] != _ISOLATION_POLICY_SCHEMA:
        _v2_reject("store isolation policy schema mismatch")
    if obj["version"] != "2.0.0":
        _v2_reject("store isolation policy version mismatch")
    if obj["namespace"] != _STORE_V2.NAMESPACE:
        _v2_reject("store isolation policy namespace mismatch")
    try:
        identifier = _TQO._require_content_ref_id(
            obj["id"], "store isolation policy id"
        )
        version = _TQO._require_semver(
            obj["version"], "store isolation policy version"
        )
    except _BTO.Rejected as exc:
        _v2_reject(f"store isolation policy id/version invalid: {exc.detail}")
    return ContentRef(
        schema=_ISOLATION_POLICY_SCHEMA,
        id=identifier,
        version=version,
        digest=domain_digest(_ISOLATION_POLICY_DOMAIN, obj),
    )


def _recompute_owned_payload_ref(role, claimed_ref, payload, /) -> ContentRef:
    """Recompute and compare a payload ContentRef under its sole role owner."""
    claimed_ref = _require_claimed_content_ref(
        claimed_ref, f"artifact[{role}]"
    )
    if type(payload) is not bytes or not 1 <= len(payload) <= _TQO.MAX_MEMBER_BYTES:
        _v2_reject(f"artifact payload length invalid: {role}")
    owner = _artifact_owner_kind_for_role(role)
    try:
        if owner == "taskqual-artifact-payload-v1":
            if claimed_ref.schema != _TQO.TASKQUAL_ARTIFACT_PAYLOAD_SCHEMA:
                _v2_reject(f"raw artifact schema mismatch: {role}")
            recomputed = _TQO.task_qualification_artifact_payload_ref(
                claimed_ref.id, claimed_ref.version, payload
            )
        elif owner == "private-scan-policy-v1":
            if claimed_ref.schema != _PRIVATE_SCAN.PRIVATE_SCAN_POLICY_SCHEMA:
                _v2_reject(f"private-scan policy schema mismatch: {role}")
            decode_canonical_pf_jcs(payload)
            recomputed = _TQO.parse_content_ref(
                _PRIVATE_SCAN.private_scan_policy_ref(payload),
                f"artifact[{role}]",
            )
        elif owner == "authority-store-service-v1":
            if claimed_ref.schema != _AUTH_STORE.DESCRIPTOR_SCHEMA:
                _v2_reject(f"authority-store descriptor schema mismatch: {role}")
            descriptor_obj = decode_canonical_pf_jcs(payload)
            foreign_ref = _AUTH_STORE.descriptor_content_ref(descriptor_obj)
            # authority_store deliberately loads its exact sibling consumer in
            # a private module namespace.  Normalize that structurally equal
            # record into this adapter's pinned ContentRef class.
            recomputed = ContentRef(
                schema=foreign_ref.schema,
                id=foreign_ref.id,
                version=foreign_ref.version,
                digest=Digest(
                    algorithm=foreign_ref.digest.algorithm,
                    bytes=foreign_ref.digest.bytes,
                ),
            )
        elif owner == "host-observation-v1":
            if claimed_ref.schema != _STAGE0.HOST_OBSERVATION_SCHEMA:
                _v2_reject(f"host observation schema mismatch: {role}")
            _STAGE0._parse_host_observation_eligibility(payload)
            recomputed = _recompute_host_raw_ref(
                claimed_ref, payload, _STAGE0.HOST_OBSERVATION_SCHEMA
            )
        elif owner == "host-profile-v1":
            recomputed = _recompute_host_raw_ref(
                claimed_ref, payload, _STAGE0.HOST_PROFILE_SCHEMA
            )
        elif owner == "taskqual-store-descriptor-v2":
            if claimed_ref.schema != _STORE_V2.DESCRIPTOR_SCHEMA:
                _v2_reject("v2 authority-store descriptor schema mismatch")
            prefix = "task-qualification-store-service-"
            if not claimed_ref.id.startswith(prefix) or len(claimed_ref.id) == len(prefix):
                _v2_reject("v2 authority-store descriptor id mismatch")
            _parse_v2_descriptor(payload, claimed_ref.id[len(prefix):])
            recomputed = _STORE_V2.recompute_object_content_ref(
                "authority-store-service", payload
            )
        elif owner == "taskqual-store-isolation-policy-v2":
            if claimed_ref.schema != _ISOLATION_POLICY_SCHEMA:
                _v2_reject("store isolation policy schema mismatch")
            recomputed = _recompute_isolation_policy_ref(payload)
        else:  # pragma: no cover - closed dispatch above makes this unreachable.
            _v2_reject(f"artifact owner implementation missing: {owner}")
    except Rejected:
        raise
    except Exception as exc:
        _v2_reject(f"artifact owner rejected {role}: {exc}")
    if recomputed != claimed_ref:
        _v2_reject(f"artifact ContentRef mismatch: {role}")
    return recomputed


def _validate_profile_artifact_payload(mapping, payload, /) -> None:
    if type(mapping) is not _TQO.ProductionArtifactMappingV1:
        _v2_reject("profile artifact mapping must be parsed")
    _recompute_owned_payload_ref(mapping.role, mapping.artifact, payload)
    if plain_sha256_digest(payload) != mapping.payloadSha256:
        _v2_reject(
            f"profile artifact payloadSha256 mismatch: {mapping.role}"
        )


_IDENTITY_PAYLOAD_PARTS = (
    ("executable", "executable"),
    ("closure", "closure"),
    ("build-policy", "buildPolicy"),
)


def _validate_identity_payloads(
    entries: dict, role_prefix: str, identity: dict, /
) -> None:
    try:
        parsed_identity = _STORE_V2._parse_verifier_identity(
            identity, f"{role_prefix} identity"
        )
    except _BTO.Rejected as exc:
        _v2_reject(f"{role_prefix} identity invalid: {exc.detail}")
    for role_part, field in _IDENTITY_PAYLOAD_PARTS:
        role = f"{role_prefix}-{role_part}"
        payload = _require_provenance_bytes(entries, role)
        try:
            claimed_ref = _TQO.parse_content_ref(
                parsed_identity[field], f"{role_prefix}.{field}"
            )
        except _BTO.Rejected as exc:
            _v2_reject(f"{role_prefix}.{field} invalid: {exc.detail}")
        _recompute_owned_payload_ref(role, claimed_ref, payload)


def _validate_d0_consumer_adapter_cross_carrier(
    entries: dict, profile, adapter: dict, /
) -> None:
    mappings = {mapping.role: mapping for mapping in profile.artifacts}
    for role_part, field in _IDENTITY_PAYLOAD_PARTS:
        profile_role = f"protected-consumer-{role_part}"
        protected_role = f"adapter-{role_part}"
        mapping = mappings.get(profile_role)
        if mapping is None:
            _v2_reject(f"D0 protected consumer profile role missing: {profile_role}")
        try:
            adapter_ref = _TQO.parse_content_ref(
                adapter[field], f"handoff.adapter.{field}"
            )
        except _BTO.Rejected as exc:
            _v2_reject(f"handoff.adapter.{field} invalid: {exc.detail}")
        if mapping.artifact != adapter_ref:
            _v2_reject(
                f"D0 protected consumer ref does not equal adapter: {role_part}"
            )
        profile_payload = _require_provenance_bytes(entries, profile_role)
        adapter_payload = _require_provenance_bytes(entries, protected_role)
        if profile_payload != adapter_payload:
            _v2_reject(
                f"D0 protected consumer bytes do not equal adapter: {role_part}"
            )


def _protected_only_roles(operation: str, profile) -> frozenset:
    roles = set(_PROTECTED_ONLY_BASE_ROLES)
    subject_role = _SUBJECT_ROLES.get(operation)
    if subject_role is None:
        _v2_reject(f"unknown operation for provenance roles: {operation}")
    roles.add(subject_role)
    if operation == "d0-10-bootstrap-receipt":
        roles.update(_D0_RECEIPT_PROTECTED_ONLY_ROLES)
    artifact_roles = {mapping.role for mapping in profile.artifacts}
    collision = roles.intersection(artifact_roles) | {"production-profile"}.intersection(
        artifact_roles)
    if collision:
        _v2_reject(
            f"profile artifact role collides with protected/core role: {sorted(collision)}")
    roles.update(artifact_roles)
    return frozenset(roles)


def _validate_provenance_source_joins(
    entries: dict,
    operation: str,
    excluded_roles: frozenset,
    *,
    handoff_bytes: bytes,
    policy_bytes: bytes,
    profile_bytes: bytes,
    pin_bytes: bytes,
    clock_bytes: bytes,
    snapshot_bytes: bytes,
    descriptor_bytes: bytes,
    archive_bytes: bytes,
    subject_bytes: bytes,
    provenance_subject_digest: Digest,
    profile,
    lookup_results: tuple,
) -> None:
    """Bind protected provenance entries to the exact live/external sources."""
    missing = set(excluded_roles) - set(entries)
    if missing:
        _v2_reject(f"provenance protected roles missing: {sorted(missing)}")

    _require_provenance_bytes(entries, "live-handoff", handoff_bytes)
    _require_provenance_bytes(entries, "authority-policy", policy_bytes)
    _require_provenance_bytes(entries, "production-profile", profile_bytes)
    _require_provenance_bytes(entries, "production-profile-pin", pin_bytes)
    _require_provenance_bytes(
        entries, "trusted-clock-observation", clock_bytes)
    _require_provenance_bytes(
        entries, "current-revocation-snapshot", snapshot_bytes)
    # Both provenance roles bind the same existing signed
    # RevocationLedgerSnapshotV1 bytes. ``current-*`` records the live lookup
    # provenance; the ordinary role becomes the pure-bundle member. No second
    # wrapper schema or semantic alias is permitted.
    _require_provenance_bytes(
        entries, "revocation-snapshot", snapshot_bytes)
    _require_provenance_bytes(
        entries, "authority-store-service-descriptor", descriptor_bytes)
    _require_provenance_bytes(
        entries, _CHANNEL_ARCHIVE_ROLES[operation], archive_bytes)
    if plain_sha256_digest(subject_bytes) != provenance_subject_digest:
        _v2_reject("subject bytes do not match provenance subjectDigest")

    # Recompute every protected identity payload under the raw owner and every
    # structured descriptor/policy under its own schema domain.  These entries
    # have no profile payloadSha256 field, so their signed identity refs are the
    # mandatory independent commitments.
    try:
        handoff_obj = decode_canonical_pf_jcs(handoff_bytes)
        descriptor_obj = decode_canonical_pf_jcs(descriptor_bytes)
    except Exception:
        _v2_reject("protected handoff/descriptor source is not canonical")
    if type(handoff_obj) is not dict or type(descriptor_obj) is not dict:
        _v2_reject("protected handoff/descriptor source must be closed objects")
    try:
        descriptor_ref = _TQO.parse_content_ref(
            handoff_obj["authorityStoreService"],
            "handoff.authorityStoreService",
        )
        isolation_ref = _TQO.parse_content_ref(
            descriptor_obj["isolationPolicy"],
            "descriptor.isolationPolicy",
        )
    except (KeyError, _BTO.Rejected) as exc:
        detail = exc.detail if isinstance(exc, _BTO.Rejected) else str(exc)
        _v2_reject(f"protected descriptor refs invalid: {detail}")
    _recompute_owned_payload_ref(
        "authority-store-service-descriptor", descriptor_ref, descriptor_bytes
    )
    isolation_bytes = _require_provenance_bytes(
        entries, "store-isolation-policy"
    )
    _recompute_owned_payload_ref(
        "store-isolation-policy", isolation_ref, isolation_bytes
    )
    _validate_identity_payloads(
        entries, "authority-store", descriptor_obj.get("verifier")
    )
    _validate_identity_payloads(entries, "adapter", handoff_obj.get("adapter"))
    _validate_identity_payloads(
        entries, "snapshot-parser", handoff_obj.get("snapshotParser")
    )
    _validate_identity_payloads(
        entries, "trusted-clock", handoff_obj.get("trustedClockService")
    )
    _validate_identity_payloads(
        entries, "store-supervisor", descriptor_obj.get("supervisor")
    )
    if operation == "d0-10-bootstrap-approval":
        _validate_d0_consumer_adapter_cross_carrier(
            entries, profile, handoff_obj["adapter"]
        )

    # Every current revocation record returned by the fixed transcript is the
    # exact ordinary pure-bundle record for the same ID; no stale/extra record
    # carrier can be substituted.
    record_results = {
        result.content_ref["id"]: result.object_bytes
        for result in lookup_results
        if result.object_kind == _STORE_V2.REVOCATION_RECORD_KIND
    }
    expected_record_roles = {
        f"revocation-record/{record_id}" for record_id in record_results
    }
    actual_record_roles = {
        role for role in entries if role.startswith("revocation-record/")
    }
    if actual_record_roles != expected_record_roles:
        _v2_reject(
            "provenance revocation-record roles do not equal current snapshot")
    for record_id, record_bytes in record_results.items():
        _require_provenance_bytes(
            entries, f"revocation-record/{record_id}", record_bytes)

    # Production artifact payloads stay outside the pure bundle.  The signed
    # original ContentRef and the independent plain SHA-256 pin are separate
    # commitments and both are recomputed from the exact protected bytes.
    for mapping in profile.artifacts:
        payload = _require_provenance_bytes(entries, mapping.role)
        _validate_profile_artifact_payload(mapping, payload)


def _decode_canonical_object(payload: bytes, where: str) -> dict:
    try:
        obj = decode_canonical_pf_jcs(payload)
    except Exception:
        _v2_reject(f"{where} is not canonical PF-JCS")
    if type(obj) is not dict:
        _v2_reject(f"{where} must be a closed object")
    return obj


def _verify_d0_receipt_external_objects(
    entries: dict,
    subject_bytes: bytes,
    verified,
    policy,
    profile,
) -> tuple:
    """Verify the external R→GBC→Ledger joins for the D0-10 receipt path."""
    receipt_obj = _decode_canonical_object(subject_bytes, "bootstrap receipt")
    try:
        receipt = _TQO.parse_d0_10_bootstrap_receipt(
            receipt_obj, "bootstrap-receipt")
    except _BTO.Rejected as exc:
        _v2_reject(f"bootstrap receipt parse failed: {exc.detail}")
    receipt_digest = domain_digest(
        _TQO.DOMAIN_D0_10_BOOTSTRAP_RECEIPT, receipt_obj)
    if receipt_digest != verified.receiptDigest:
        _v2_reject("verified receiptDigest does not recompute from subject bytes")

    gbc_bytes = _require_provenance_bytes(
        entries, "governance-bootstrap-completion")
    gbc_obj = _decode_canonical_object(
        gbc_bytes, "governance bootstrap completion")
    try:
        gbc = _TQO.parse_governance_bootstrap_completion(
            gbc_obj, "governance-bootstrap-completion")
    except _BTO.Rejected as exc:
        _v2_reject(f"governance completion parse failed: {exc.detail}")
    if (
        gbc.id != "governance-bootstrap-completion-d0-10"
        or gbc.taskId != "TASK-D0-10"
        or gbc.rulingId != "GOV-TASKQUAL-BOOTSTRAP-001"
        or gbc.purpose != "d0-10-taskqual-one-time-bridge"
    ):
        _v2_reject("governance completion D0-10 enum/id tuple mismatch")
    if gbc.completionCandidate != verified.closeoutCandidate:
        _v2_reject("governance completion candidate does not equal D")
    if gbc.ruling != receipt.ruling:
        _v2_reject("governance completion ruling does not equal receipt ruling")
    if gbc.authorityPolicy != verified.authorityPolicy:
        _v2_reject("governance completion authority policy mismatch")
    if plain_sha256_digest(subject_bytes) != gbc.sourceClosure.digest:
        _v2_reject("governance completion sourceClosure is not exact receipt bytes")
    if not gbc.independentReviews:
        _v2_reject("governance completion independentReviews must be nonempty")
    signing_principal_ids = {
        principal.principalId for principal in policy.principals
    }
    review_invocations = set()
    for review in gbc.independentReviews:
        if review.reviewCommit != verified.closeoutCandidate.commit:
            _v2_reject("governance completion reviewCommit must equal D")
        if review.reviewerId in signing_principal_ids:
            _v2_reject("governance completion reviewer must not be a signer")
        if review.invocationId in review_invocations:
            _v2_reject("governance completion review invocation reused")
        review_invocations.add(review.invocationId)
    try:
        _TQV._verify_signatures(
            gbc_obj,
            gbc.signatures,
            policy,
            profile,
            _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_STATEMENT,
            _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION_SIGNATURE,
            "governance-bootstrap-completion.signatures",
        )
    except _BTO.Rejected as exc:
        _v2_reject(f"governance completion signatures invalid: {exc.detail}")
    governance_digest = domain_digest(
        _TQO.DOMAIN_GOVERNANCE_BOOTSTRAP_COMPLETION, gbc_obj)

    ledger_bytes = _require_provenance_bytes(
        entries, "receipt-ledger-projection")
    ledger_obj = _decode_canonical_object(
        ledger_bytes, "receipt ledger projection")
    try:
        ledger = _TQO.parse_d0_10_receipt_ledger_projection(
            ledger_obj, "receipt-ledger-projection")
    except _BTO.Rejected as exc:
        _v2_reject(f"receipt ledger projection parse failed: {exc.detail}")
    if ledger.evidenceId != receipt.ledgerEvidenceId:
        _v2_reject("ledger evidenceId does not equal receipt ledgerEvidenceId")
    if (
        ledger.approvalRef.id != "d0-10-bootstrap-approval"
        or ledger.approvalRef.digest != verified.approvalDigest
    ):
        _v2_reject("ledger approvalRef does not equal verified approval")
    if (
        ledger.receiptRef.id != receipt.id
        or ledger.receiptRef.digest != receipt_digest
    ):
        _v2_reject("ledger receiptRef does not equal verified receipt")
    if ledger.rulingRef != receipt.ruling:
        _v2_reject("ledger rulingRef does not equal verified ruling")
    ledger_digest = domain_digest(
        _TQO.DOMAIN_D0_10_RECEIPT_LEDGER_PROJECTION, ledger_obj)
    return ledger_digest, governance_digest


# Role → member kind mapping (SPEC §8.2 role table)
_RAW_SOURCE_ROLES = frozenset({
    "phase-4-source", "phase-5-source", "ruling-source",
    "d0-07-ruling-source", "freeze-package-source",
})
_RAW_SOURCE_PREFIXES = ("evidence/",)
_ARCHIVE_ROLES = frozenset({
    "candidate-archive", "pre-close-archive", "closeout-archive",
    "d0-07-completion-archive",
})
_ARCHIVE_PREFIXES = ("dependency-archive/",)
_GIT_OBJECT_ROLES = frozenset({
    "candidate-commit-object", "pre-close-commit-object",
    "closeout-commit-object", "d0-07-completion-commit-object",
})
_GIT_OBJECT_PREFIXES = ("dependency-commit-object/", "ancestry-commit/")
_REVIEW_PREFIX = "review-report/"


def _raw_source_path(role: str, task_id: str) -> str:
    fixed = {
        "phase-4-source": "docs/04-task-breakdown.md",
        "phase-5-source": "docs/05-test-spec.md",
        "ruling-source": "docs/governance/task-qualification-bootstrap-ruling.md",
        "d0-07-ruling-source": "docs/governance/d0-07-closure-ruling.md",
        "freeze-package-source": (
            f"docs/governance/task-freeze-packages/{task_id}.json"),
    }
    return fixed.get(role, role)


def _project_provenance_to_members(
    provenance_obj: dict, operation: str, excluded_roles: frozenset,
) -> list:
    """Project only pure-bundle provenance entries to ContentMemberV1 wires.

    Each provenance entry has ``{role, bytesHex}``. The adapter projects each
    to the correct member kind based on the role. For typed-content roles, the
    ContentRef is recomputed from the decoded bytes. Raw-source roles use plain
    SHA-256 except ``freeze-package-source``, whose accepted wire owner is the
    task-freeze-package source domain. For archive roles, the archiveSha256 is
    plain SHA-256. For git-object roles, the objectId is read from the decoded
    commit bytes.
    """
    entries = provenance_obj.get("entries")
    if type(entries) is not list or not entries:
        _v2_reject("provenance bundle entries must be a nonempty array")
    members = []
    for entry in entries:
        if type(entry) is not dict:
            _v2_reject("provenance entry must be an object")
        role = entry.get("role")
        if type(role) is not str or not role:
            _v2_reject("provenance entry role must be nonempty text")
        bytes_hex = entry.get("bytesHex")
        if type(bytes_hex) is not str or not bytes_hex:
            _v2_reject("provenance entry bytesHex must be nonempty text")
        if role in excluded_roles:
            continue
        entry_bytes = bytes.fromhex(bytes_hex)

        if (role in _RAW_SOURCE_ROLES
                or any(role.startswith(prefix) for prefix in _RAW_SOURCE_PREFIXES)):
            digest = (
                _TQO.domain_digest_raw(
                    _TQO.DOMAIN_TASK_FREEZE_PACKAGE_SOURCE, entry_bytes)
                if role == "freeze-package-source"
                else plain_sha256_digest(entry_bytes)
            )
            members.append({
                "role": role,
                "kind": "raw-source",
                "raw": {
                    "path": _raw_source_path(role, provenance_obj["taskId"]),
                    "digest": digest_to_wire(digest),
                },
                "bytesHex": bytes_hex,
            })
        elif (role in _ARCHIVE_ROLES
              or any(role.startswith(prefix) for prefix in _ARCHIVE_PREFIXES)):
            digest = plain_sha256_digest(entry_bytes)
            members.append({
                "role": role,
                "kind": "archive",
                "archiveSha256": digest_to_wire(digest),
                "bytesHex": bytes_hex,
            })
        elif (role in _GIT_OBJECT_ROLES
              or any(role.startswith(prefix) for prefix in _GIT_OBJECT_PREFIXES)):
            # Git-object members carry the exact raw commit payload.  Their ID
            # is the Git SHA-1 object hash, not a caller-supplied JSON field.
            try:
                commit_obj = _TQO.parse_git_commit_object(
                    entry_bytes, f"provenance entry {role}")
            except _BTO.Rejected as exc:
                _v2_reject(f"provenance entry {role} is not a Git commit: {exc.detail}")
            object_id = commit_obj.commit_sha
            members.append({
                "role": role,
                "kind": "git-object",
                "objectId": object_id,
                "objectType": "commit",
                "bytesHex": bytes_hex,
            })
        elif role.startswith(_REVIEW_PREFIX):
            review_suffix = role[len(_REVIEW_PREFIX):]
            parts = review_suffix.split("/")
            if len(parts) != 2 or not parts[0] or not parts[1]:
                _v2_reject(f"provenance review role grammar invalid: {role}")
            reviewer_id, claimed_digest_hex = parts
            report_digest = Digest(
                algorithm="sha256",
                bytes=hashlib.sha256(
                    _TQO.DOMAIN_REVIEW_REPORT + b"\x00" + entry_bytes).digest(),
            )
            if claimed_digest_hex != report_digest.bytes.hex():
                _v2_reject(f"provenance review role digest mismatch: {role}")
            members.append({
                "role": role,
                "kind": "review",
                "reviewerId": reviewer_id,
                "reportDigest": digest_to_wire(report_digest),
                "bytesHex": bytes_hex,
            })
        else:
            # typed-content: recompute ContentRef from decoded bytes
            try:
                typed_obj = decode_canonical_pf_jcs(entry_bytes)
            except Exception:
                _v2_reject(f"provenance entry {role} bytes not canonical PF-JCS")
            if type(typed_obj) is not dict:
                _v2_reject(f"provenance entry {role} must be a closed object")
            schema = typed_obj.get("schema")
            obj_id = typed_obj.get("id")
            obj_version = typed_obj.get("version")
            if type(schema) is not str or type(obj_id) is not str:
                _v2_reject(f"provenance entry {role} missing schema/id")
            # Recompute ContentRef using the typed content domain
            try:
                ref = _TQO.recompute_typed_content_ref(schema, typed_obj)
            except _BTO.Rejected as r:
                _v2_reject(f"provenance entry {role} ref recompute failed: {r.detail}")
            members.append({
                "role": role,
                "kind": "typed-content",
                "content": content_ref_to_wire(ref),
                "bytesHex": bytes_hex,
            })

    # Sort members by role ASCII ascending
    members.sort(key=lambda m: m["role"])
    return members


def _extract_subject_from_provenance(provenance_obj: dict, subject_role: str) -> bytes:
    """Extract the subject bytes from the provenance bundle by role name."""
    entries = provenance_obj.get("entries")
    if type(entries) is not list:
        _v2_reject("provenance entries must be a list")
    for entry in entries:
        if type(entry) is not dict:
            continue
        if entry.get("role") == subject_role:
            bytes_hex = entry.get("bytesHex")
            if type(bytes_hex) is not str or not bytes_hex:
                _v2_reject(f"subject entry {subject_role} missing bytesHex")
            return bytes.fromhex(bytes_hex)
    _v2_reject(f"subject role {subject_role} not found in provenance bundle")


def _call_pure_verifier(operation: str, bundle_bytes: bytes,
                       subject_bytes: bytes):
    """Call the correct pure verifier for the operation."""
    if operation == "task-qualification":
        return _TQV.verify_task_qualification_v1(bundle_bytes, subject_bytes)
    if operation == "task-completion":
        return _TQV.verify_task_completion_receipt_v1(bundle_bytes, subject_bytes)
    if operation == "d0-10-bootstrap-approval":
        return _TQV.verify_d0_10_bootstrap_v1(bundle_bytes, subject_bytes)
    if operation == "d0-10-bootstrap-receipt":
        return _TQV.verify_d0_10_bootstrap_receipt_v1(bundle_bytes, subject_bytes)
    _v2_reject(f"unknown operation for pure verifier: {operation}")


def _serialize_pure_projection(verified) -> dict:
    """Serialize a §8.1 Verified record to its complete wire form."""
    if isinstance(verified, _TQV.VerifiedTaskQualificationV1):
        return _TQO.verified_task_qualification_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedTaskCompletionV1):
        return _TQO.verified_task_completion_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapApprovalV1):
        return _TQO.verified_d0_10_bootstrap_approval_to_wire(verified)
    if isinstance(verified, _TQV.VerifiedD0_10BootstrapCompletionV1):
        return _TQO.verified_d0_10_bootstrap_completion_to_wire(verified)
    _v2_reject("unknown verified type for pure projection")


def _run_buffered_lookup_transcript(
    sock: socket.socket,
    tpl: _STORE_V2.HandoffTuple,
    gate_set_digest: bytes,
    object_ids: dict,
    revocation_head: tuple,
) -> tuple:
    """Drive the fixed lookup transcript, buffering responses for later
    signature verification (after the descriptor provides the service key).

    Sends lookup requests in the fixed ADR-0021 §4.2 order:
        (0) authority-policy, (1) production-profile-pin, (2) production-profile,
        (3) adapter, (4) snapshot-parser, (5) authority-store-service,
        (6) trusted-clock-service, (7) revocation-snapshot,
        (8..) revocation-records (ASCII id ascending).
    """
    task_id = tpl.taskId
    operation = tpl.operation
    head_sequence, head_digest = revocation_head
    results: list = []
    request_id = 0

    # (0)..(6): fixed object lookups
    # The production-profile ID (item 2) is derived from the pin (item 1):
    # after the pin lookup, the adapter reads pin.profile.id to get the
    # profile object ID. So we run lookups 0-1 first, extract the profile ID,
    # then continue 2-6.
    for object_kind in _STORE_V2.FIXED_LOOKUP_OBJECT_KINDS[:7]:
        if object_kind == "production-profile":
            # The profile ID is derived from the pin lookup result.
            if "production-profile" not in object_ids:
                # Find the pin result (item 1) and extract the profile ID
                pin_result = None
                for r in results:
                    if r.object_kind == "production-profile-pin":
                        pin_result = r
                        break
                if pin_result is None:
                    _v2_reject("production-profile-pin not found before profile lookup")
                try:
                    pin_obj = decode_canonical_pf_jcs(pin_result.object_bytes)
                except Exception:
                    _v2_reject("pin bytes are not canonical PF-JCS")
                if type(pin_obj) is not dict:
                    _v2_reject("pin must be a closed object")
                profile_ref = pin_obj.get("profile")
                if not _STORE_V2._parse_content_ref(profile_ref, "pin.profile"):
                    _v2_reject("pin.profile is not a valid ContentRef")
                object_ids["production-profile"] = profile_ref["id"]
        if object_kind not in object_ids:
            _v2_reject(f"missing object_id for fixed lookup kind: {object_kind}")
        key = _STORE_V2.build_object_lookup_key(
            task_id, operation, gate_set_digest, object_kind,
            object_ids[object_kind])
        request_payload = _STORE_V2.build_lookup_request(request_id, tpl, key)
        _STORE_V2.send_packet(sock, request_payload)
        response_payload = _STORE_V2.recv_packet(sock)
        # Parse response without signature verification (buffered)
        response = _STORE_V2._decode_frame(response_payload)
        if response.get("schema") in _STORE_V2.V1_FRAME_SCHEMAS:
            _v2_reject("v1 lookup response frame is rejected")
        _STORE_V2._require_exact_keys(
            response, _STORE_V2.LOOKUP_RESPONSE_FIELDS, "lookup-response")
        if response["schema"] != _STORE_V2.LOOKUP_RESPONSE_SCHEMA:
            _v2_reject("lookup-response.schema is not the v2 lookup response schema")
        if response["version"] != _STORE_V2.VERSION:
            _v2_reject("lookup-response.version must be 2.0.0")
        if response["requestId"] != request_id:
            _v2_reject("lookup-response.requestId does not match request")
        if response["status"] != "found":
            _v2_reject("lookup-response.status must be found exactly one")
        _STORE_V2._check_echo(response, tpl, has_handoff_digest=False)
        if response["key"] != key:
            _v2_reject("lookup-response.key does not match request key")
        object_bytes = bytes.fromhex(response["objectBytesHex"])
        object_kind_val = key["objectKind"]
        recomputed_ref = _STORE_V2.recompute_object_content_ref(
            object_kind_val, object_bytes)
        recomputed_wire = content_ref_to_wire(recomputed_ref)
        claimed_ref = _STORE_V2._parse_content_ref(
            response["object"], "lookup-response.object")
        if not _STORE_V2._content_ref_equal(claimed_ref, recomputed_wire):
            _v2_reject(
                "lookup-response.object ContentRef does not recompute from bytes")
        results.append(_STORE_V2.LookupResult(
            response=response, object_bytes=object_bytes,
            content_ref=response["object"], object_kind=object_kind_val))
        request_id += 1

    # (7): revocation-snapshot (head key)
    head_key = _STORE_V2.build_revocation_head_key(
        task_id, operation, gate_set_digest, head_sequence, head_digest)
    request_payload = _STORE_V2.build_lookup_request(request_id, tpl, head_key)
    _STORE_V2.send_packet(sock, request_payload)
    response_payload = _STORE_V2.recv_packet(sock)
    response = _STORE_V2._decode_frame(response_payload)
    if response.get("schema") in _STORE_V2.V1_FRAME_SCHEMAS:
        _v2_reject("v1 lookup response frame is rejected")
    _STORE_V2._require_exact_keys(
        response, _STORE_V2.LOOKUP_RESPONSE_FIELDS, "lookup-response")
    if response["schema"] != _STORE_V2.LOOKUP_RESPONSE_SCHEMA:
        _v2_reject("lookup-response.schema is not the v2 lookup response schema")
    if response["version"] != _STORE_V2.VERSION:
        _v2_reject("lookup-response.version must be 2.0.0")
    if response["requestId"] != request_id:
        _v2_reject("lookup-response.requestId does not match request")
    if response["status"] != "found":
        _v2_reject("lookup-response.status must be found exactly one")
    _STORE_V2._check_echo(response, tpl, has_handoff_digest=False)
    if response["key"] != head_key:
        _v2_reject("lookup-response.key does not match request key")
    snapshot_bytes = bytes.fromhex(response["objectBytesHex"])
    recomputed_ref = _STORE_V2.recompute_object_content_ref(
        _STORE_V2.REVOCATION_SNAPSHOT_KIND, snapshot_bytes)
    recomputed_wire = content_ref_to_wire(recomputed_ref)
    claimed_ref = _STORE_V2._parse_content_ref(
        response["object"], "lookup-response.object")
    if not _STORE_V2._content_ref_equal(claimed_ref, recomputed_wire):
        _v2_reject(
            "lookup-response.object ContentRef does not recompute from bytes")
    results.append(_STORE_V2.LookupResult(
        response=response, object_bytes=snapshot_bytes,
        content_ref=response["object"],
        object_kind=_STORE_V2.REVOCATION_SNAPSHOT_KIND))
    request_id += 1

    # (8..): revocation-records from the snapshot, ASCII id ascending
    record_ids = _STORE_V2._extract_revocation_record_ids(snapshot_bytes)
    for record_id in record_ids:
        key = _STORE_V2.build_object_lookup_key(
            task_id, operation, gate_set_digest,
            _STORE_V2.REVOCATION_RECORD_KIND, record_id)
        request_payload = _STORE_V2.build_lookup_request(request_id, tpl, key)
        _STORE_V2.send_packet(sock, request_payload)
        response_payload = _STORE_V2.recv_packet(sock)
        response = _STORE_V2._decode_frame(response_payload)
        if response.get("schema") in _STORE_V2.V1_FRAME_SCHEMAS:
            _v2_reject("v1 lookup response frame is rejected")
        _STORE_V2._require_exact_keys(
            response, _STORE_V2.LOOKUP_RESPONSE_FIELDS, "lookup-response")
        if response["schema"] != _STORE_V2.LOOKUP_RESPONSE_SCHEMA:
            _v2_reject("lookup-response.schema is not the v2 lookup response schema")
        if response["version"] != _STORE_V2.VERSION:
            _v2_reject("lookup-response.version must be 2.0.0")
        if response["requestId"] != request_id:
            _v2_reject("lookup-response.requestId does not match request")
        if response["status"] != "found":
            _v2_reject("lookup-response.status must be found exactly one")
        _STORE_V2._check_echo(response, tpl, has_handoff_digest=False)
        if response["key"] != key:
            _v2_reject("lookup-response.key does not match request key")
        object_bytes = bytes.fromhex(response["objectBytesHex"])
        recomputed_ref = _STORE_V2.recompute_object_content_ref(
            _STORE_V2.REVOCATION_RECORD_KIND, object_bytes)
        recomputed_wire = content_ref_to_wire(recomputed_ref)
        claimed_ref = _STORE_V2._parse_content_ref(
            response["object"], "lookup-response.object")
        if not _STORE_V2._content_ref_equal(claimed_ref, recomputed_wire):
            _v2_reject(
                "lookup-response.object ContentRef does not recompute from bytes")
        results.append(_STORE_V2.LookupResult(
            response=response, object_bytes=object_bytes,
            content_ref=response["object"],
            object_kind=_STORE_V2.REVOCATION_RECORD_KIND))
        request_id += 1

    return tuple(results)