#!/usr/bin/env python3
"""Stage-0 handoff producer and inherited-channel verifier (dev slice).

``produce_stage0_handoff`` constructs an ``EligibleStage0HandoffV1`` with the
four spec-ordered channels bound to already-open file descriptors:

1. The three regular-file channels (authority-policy, candidate-archive,
   evidence-root) are safe-opened with ``O_RDONLY|O_NOFOLLOW|O_NONBLOCK``,
   pinned by ``fstat`` to regular files, and read through the same fd so the
   binding digest always describes the opened inode, never a replaced path.
2. The authority-store channel is a connected ``socketpair(AF_UNIX,
   SOCK_STREAM)``: one end is returned for the service side, the other is the
   consumer channel fd.
3. Channel fds must be unique and greater than 2; they are recorded in the
   handoff in the frozen role order (authority-policy, authority-store,
   candidate-archive, evidence-root) and delivered with the inheritable flag
   set (Python's PEP 446 default of close-on-exec is cleared explicitly).

Digest bindings: the authority-policy channel binds the recomputed
``pf.bootstrap-authority-policy.v1`` domain digest of the exact policy bytes
(the policy is fully parsed and validated at production time); the
authority-store channel binds the supplied descriptor ContentRef digest; the
candidate-archive channel binds the candidate's ``archiveDigest`` and the
producer recomputes the plain SHA-256 of the opened archive bytes and
requires exact equality (this slice's archive binding rule); the
evidence-root channel binds ``pf.bootstrap-evidence-root-manifest.v1`` over
the opened manifest bytes.

Eligibility is fail closed: the host observation bytes (bounded JSON) must
carry ``eligibleForHermetic: true`` or no handoff is produced and every
already-opened fd is closed before raising.  The nonce is the single random
value in this module (``secrets.token_bytes(32)``); no key material is ever
accepted or persisted here.

fd ownership: the returned fds stay open and inheritable; the caller owns
them and must either close them or transfer them to a containment child.
``verify_inherited_channels`` performs the consumer-side acceptance checks
(fstat type, read-only flag, fd numbers from the handoff, regular-file
digest recompute, connected AF_UNIX stream peer with matching euid, stdin
EOF, and the exact inherited fd set ``{0,1,2} ∪ channels`` enumerated via
``/proc/self/fd``) and never closes any fd.

This slice does not implement Stage-0 integration: tcb digests are typed
inputs the caller must recompute from the actual executable bytes, and the
socket peer check is a same-user connected-endpoint check, not a peer
executable attestation.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import secrets
import select
import socket
import stat
import struct
import sys
from dataclasses import dataclass
from fcntl import fcntl, F_GETFL, F_SETFD, F_GETFD, FD_CLOEXEC
from pathlib import Path
from types import ModuleType
from typing import NoReturn, Optional, Tuple


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
        "proof_forge_bootstrap_task_producers_for_stage0_handoff",
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
CandidateIdentity = _CONSUMER.CandidateIdentity
EligibleStage0TcbV1 = _CONSUMER.EligibleStage0TcbV1
EligibleStage0EnvironmentV1 = _CONSUMER.EligibleStage0EnvironmentV1
EligibleStage0HandoffV1 = _CONSUMER.EligibleStage0HandoffV1
canonical_pf_jcs = _CONSUMER.canonical_pf_jcs

HANDOFF_SCHEMA = "proof-forge.eligible-stage0-handoff.v1"
HOST_OBSERVATION_SCHEMA = "proof-forge.host-observation.v1"
HOST_PROFILE_SCHEMA = "proof-forge.host-profile.v1"
MAX_CHANNEL_FILE_BYTES = 4 * 1024 * 1024
MAX_OBSERVATION_BYTES = 64 * 1024

_HANDOFF_DIGEST_DOMAIN = b"pf.eligible-stage0-handoff.v1\x00"
_POLICY_DIGEST_DOMAIN = b"pf.bootstrap-authority-policy.v1\x00"
_EVIDENCE_ROOT_DIGEST_DOMAIN = b"pf.bootstrap-evidence-root-manifest.v1\x00"

_CHANNEL_ROLES = (
    "authority-policy",
    "authority-store",
    "candidate-archive",
    "evidence-root",
)
_CHANNEL_TRANSPORTS = (
    "regular-file",
    "authenticated-stream",
    "regular-file",
    "regular-file",
)
_CHANNEL_ACCESS = (
    "read-only",
    "request-response",
    "read-only",
    "read-only",
)


class Stage0HandoffError(Exception):
    """Stable handoff failure; internal details never grant authority."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail or code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str) -> NoReturn:
    raise Stage0HandoffError(code, detail)


def _handoff(detail: str) -> NoReturn:
    _fail("PF-STAGE0-HANDOFF", detail)


def _channel(detail: str) -> NoReturn:
    _fail("PF-STAGE0-CHANNEL", detail)


def _io(detail: str) -> NoReturn:
    _fail("PF-STAGE0-IO", detail)


@dataclass(frozen=True)
class Stage0HostObservationV1:
    id: str
    version: str
    bytes: bytes


@dataclass(frozen=True)
class Stage0HostProfileV1:
    id: str
    version: str
    bytes: bytes


@dataclass(frozen=True)
class Stage0ChannelSet:
    authorityPolicyFd: int
    authorityStoreFd: int
    candidateArchiveFd: int
    evidenceRootFd: int
    authorityStoreServiceFd: int


@dataclass(frozen=True)
class ProducedStage0Handoff:
    handoffBytes: bytes
    handoffDigest: Digest
    handoffRef: ContentRef
    channels: Stage0ChannelSet


def _require_consumer(validation, detail: str):
    try:
        return validation()
    except _CONSUMER.Rejected:
        _handoff(detail)


def _digest_wire(digest: Digest) -> str:
    if type(digest) is not Digest or digest.algorithm != "sha256":
        _handoff("digest values must be sha256 Digest records")
    return "sha256:" + digest.bytes.hex()


def _content_ref_wire(ref: ContentRef) -> dict:
    if type(ref) is not ContentRef:
        _handoff("handoff refs must be ContentRef records")
    return {
        "schema": ref.schema,
        "id": ref.id,
        "version": ref.version,
        "digest": _digest_wire(ref.digest),
    }


def _candidate_wire(candidate: CandidateIdentity) -> dict:
    if type(candidate) is not CandidateIdentity:
        _handoff("candidate must be a CandidateIdentity record")
    return {
        "commit": candidate.commit,
        "treeObjectId": candidate.treeObjectId,
        "archiveDigest": _digest_wire(candidate.archiveDigest),
        "digest": _digest_wire(candidate.digest),
    }


def _read_fd_bytes(fd: int, where: str) -> bytes:
    chunks = []
    offset = 0
    while True:
        try:
            chunk = os.pread(fd, 65536, offset)
        except OSError as error:
            _io(f"{where} fd read failed: {error}")
        if not chunk:
            break
        chunks.append(chunk)
        offset += len(chunk)
        if offset > MAX_CHANNEL_FILE_BYTES:
            _channel(f"{where} exceeds the 4 MiB channel maximum")
    return b"".join(chunks)


def _safe_open_regular(path: str, where: str) -> int:
    if type(path) is not str or not path.startswith("/"):
        _channel(f"{where} must be an absolute path")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        _channel(f"{where} cannot be safe-opened: {error}")
    try:
        metadata = os.fstat(fd)
    except OSError as error:
        os.close(fd)
        _io(f"{where} fstat failed: {error}")
    if not stat.S_ISREG(metadata.st_mode):
        os.close(fd)
        _channel(f"{where} is not a regular file")
    return fd


def _require_inheritable(fd: int, where: str) -> None:
    flags = fcntl(fd, F_GETFD)
    if flags & FD_CLOEXEC:
        fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC)
    if fcntl(fd, F_GETFD) & FD_CLOEXEC:
        _channel(f"{where} must be deliverable across exec")


def _close_quietly(fds: Tuple[int, ...]) -> None:
    for fd in fds:
        try:
            os.close(fd)
        except OSError:
            pass


def _parse_host_observation_eligibility(observation_bytes: bytes) -> None:
    if type(observation_bytes) is not bytes or not 1 <= len(
        observation_bytes
    ) <= MAX_OBSERVATION_BYTES:
        _handoff("host observation must be bounded exact bytes")
    try:
        parsed = json.loads(observation_bytes.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError):
        _handoff("host observation is not a bounded JSON document")
    if type(parsed) is not dict:
        _handoff("host observation must be a JSON object")
    if parsed.get("eligibleForHermetic") is not True:
        _handoff("host observation does not prove an eligible host")


def produce_stage0_handoff(
    *,
    handoff_id: str,
    handoff_version: str,
    run_id: str,
    candidate: CandidateIdentity,
    candidate_archive_path: str,
    authority_policy_path: str,
    authority_store_descriptor: ContentRef,
    evidence_root_manifest_path: str,
    host_observation: Stage0HostObservationV1,
    host_profile: Stage0HostProfileV1,
    tcb: EligibleStage0TcbV1,
    environment: EligibleStage0EnvironmentV1,
) -> ProducedStage0Handoff:
    """Produce a validated eligible Stage-0 handoff with bound channel fds.

    The caller owns every returned fd and must close or transfer them; on
    any failure all already-opened fds are closed before raising.
    """
    if type(handoff_id) is not str or type(handoff_version) is not str:
        _handoff("handoff id/version must be text")
    if type(run_id) is not str:
        _handoff("runId must be text")
    if type(candidate) is not CandidateIdentity:
        _handoff("candidate must be a CandidateIdentity record")
    if type(authority_store_descriptor) is not ContentRef:
        _handoff("authority store descriptor must be a ContentRef")
    if type(host_observation) is not Stage0HostObservationV1:
        _handoff("host observation must be a Stage0HostObservationV1 record")
    if type(host_profile) is not Stage0HostProfileV1:
        _handoff("host profile must be a Stage0HostProfileV1 record")
    if type(tcb) is not EligibleStage0TcbV1:
        _handoff("tcb must be an EligibleStage0TcbV1 record")
    if type(environment) is not EligibleStage0EnvironmentV1:
        _handoff("environment must be an EligibleStage0EnvironmentV1 record")
    _require_consumer(
        lambda: _CONSUMER._require_safe_id(run_id, "runId"),
        "runId must be an ASCII safe-id",
    )
    _require_consumer(
        lambda: _CONSUMER._require_ascii_text(
            handoff_id, _CONSUMER.PROFILE_ID_RE, "handoff id", 127
        ),
        "handoff id must use the ContentRef id grammar",
    )
    _require_consumer(
        lambda: _CONSUMER._require_semver(handoff_version, "handoff version"),
        "handoff version must be exact SemVer",
    )
    _parse_host_observation_eligibility(host_observation.bytes)

    opened: list[int] = []
    try:
        policy_fd = _safe_open_regular(authority_policy_path, "authority-policy")
        opened.append(policy_fd)
        policy_bytes = _read_fd_bytes(policy_fd, "authority-policy")
        policy, policy_ref = _require_consumer(
            lambda: _CONSUMER.parse_bootstrap_authority_policy(policy_bytes),
            "authority-policy channel bytes are not a valid policy",
        )
        archive_fd = _safe_open_regular(candidate_archive_path, "candidate-archive")
        opened.append(archive_fd)
        archive_bytes = _read_fd_bytes(archive_fd, "candidate-archive")
        archive_sha256 = hashlib.sha256(archive_bytes).digest()
        if archive_sha256 != candidate.archiveDigest.bytes:
            os.close(archive_fd)
            opened.remove(archive_fd)
            _channel(
                "candidate-archive bytes do not match candidate.archiveDigest"
            )
        evidence_fd = _safe_open_regular(
            evidence_root_manifest_path, "evidence-root"
        )
        opened.append(evidence_fd)
        evidence_bytes = _read_fd_bytes(evidence_fd, "evidence-root")
        evidence_digest = hashlib.sha256(
            _EVIDENCE_ROOT_DIGEST_DOMAIN + evidence_bytes
        ).digest()

        service_socket, consumer_socket = socket.socketpair(
            socket.AF_UNIX, socket.SOCK_STREAM
        )
        service_fd = service_socket.detach()
        consumer_fd = consumer_socket.detach()
        opened.extend((service_fd, consumer_fd))
        channel_fds = (policy_fd, consumer_fd, archive_fd, evidence_fd)
        if any(fd <= 2 for fd in channel_fds) or len(set(channel_fds)) != 4:
            _channel("channel fds must be unique and greater than 2")
        for index, fd in enumerate(channel_fds + (service_fd,)):
            _require_inheritable(fd, f"channels[{index}]")

        observation_ref = ContentRef(
            HOST_OBSERVATION_SCHEMA,
            host_observation.id,
            host_observation.version,
            Digest(
                "sha256", hashlib.sha256(host_observation.bytes).digest()
            ),
        )
        profile_ref = ContentRef(
            HOST_PROFILE_SCHEMA,
            host_profile.id,
            host_profile.version,
            Digest("sha256", hashlib.sha256(host_profile.bytes).digest()),
        )
        wire = {
            "schema": HANDOFF_SCHEMA,
            "id": handoff_id,
            "version": handoff_version,
            "runId": run_id,
            "nonce": secrets.token_bytes(32).hex(),
            "candidate": _candidate_wire(candidate),
            "authorityPolicy": _content_ref_wire(policy_ref),
            "authorityStoreService": _content_ref_wire(
                authority_store_descriptor
            ),
            "hostObservation": _content_ref_wire(observation_ref),
            "hostProfile": _content_ref_wire(profile_ref),
            "eligible": True,
            "tcb": {
                "stage0VerifierDigest": _digest_wire(tcb.stage0VerifierDigest),
                "bootstrapVerifierDigest": _digest_wire(
                    tcb.bootstrapVerifierDigest
                ),
                "continuationDigest": _digest_wire(tcb.continuationDigest),
                "formalFinalizerDigest": _digest_wire(
                    tcb.formalFinalizerDigest
                ),
            },
            "environment": {
                "mode": environment.mode,
                "home": environment.home,
                "path": environment.path,
                "lcAll": environment.lcAll,
                "tz": environment.tz,
                "network": environment.network,
            },
            "channels": [
                {
                    "role": role,
                    "fd": fd,
                    "transport": transport,
                    "access": access,
                    "bindingDigest": binding,
                }
                for (role, transport, access, fd, binding) in (
                    (
                        _CHANNEL_ROLES[0],
                        _CHANNEL_TRANSPORTS[0],
                        _CHANNEL_ACCESS[0],
                        policy_fd,
                        _digest_wire(policy_ref.digest),
                    ),
                    (
                        _CHANNEL_ROLES[1],
                        _CHANNEL_TRANSPORTS[1],
                        _CHANNEL_ACCESS[1],
                        consumer_fd,
                        _digest_wire(authority_store_descriptor.digest),
                    ),
                    (
                        _CHANNEL_ROLES[2],
                        _CHANNEL_TRANSPORTS[2],
                        _CHANNEL_ACCESS[2],
                        archive_fd,
                        _digest_wire(candidate.archiveDigest),
                    ),
                    (
                        _CHANNEL_ROLES[3],
                        _CHANNEL_TRANSPORTS[3],
                        _CHANNEL_ACCESS[3],
                        evidence_fd,
                        _digest_wire(Digest("sha256", evidence_digest)),
                    ),
                )
            ],
            "pathnameReopen": False,
            "fallback": "none",
        }
        handoff_bytes = canonical_pf_jcs(wire)
        handoff_digest = Digest(
            "sha256",
            hashlib.sha256(_HANDOFF_DIGEST_DOMAIN + handoff_bytes).digest(),
        )
        handoff_ref = ContentRef(
            HANDOFF_SCHEMA, handoff_id, handoff_version, handoff_digest
        )
        _require_consumer(
            lambda: _CONSUMER._preflight_eligible_stage0_handoff(handoff_bytes),
            "produced handoff must pass the consumer preflight",
        )
        return ProducedStage0Handoff(
            handoff_bytes,
            handoff_digest,
            handoff_ref,
            Stage0ChannelSet(
                policy_fd, consumer_fd, archive_fd, evidence_fd, service_fd
            ),
        )
    except BaseException:
        _close_quietly(tuple(opened))
        raise


def _enumerate_inherited_fds() -> Tuple[int, ...]:
    try:
        entries = os.listdir("/proc/self/fd")
    except OSError as error:
        _io(f"/proc/self/fd enumeration failed: {error}")
    fds = set()
    for entry in entries:
        if entry.isdigit():
            fds.add(int(entry, 10))
    return tuple(sorted(fds))


def _verify_stdin_eof() -> None:
    try:
        readable, _, _ = select.select([0], [], [], 0)
    except OSError as error:
        _channel(f"stdin EOF check failed: {error}")
    if not readable:
        _channel("stdin is not at EOF")
    try:
        data = os.read(0, 1)
    except OSError as error:
        _channel(f"stdin EOF read failed: {error}")
    if data != b"":
        _channel("stdin must be at EOF")


def _verify_regular_channel(fd: int, role: str, expected_digest: Digest) -> None:
    try:
        metadata = os.fstat(fd)
    except OSError as error:
        _channel(f"{role} fd fstat failed: {error}")
    if not stat.S_ISREG(metadata.st_mode):
        _channel(f"{role} fd must be a regular file")
    access = fcntl(fd, F_GETFL) & os.O_ACCMODE
    if access != os.O_RDONLY:
        _channel(f"{role} fd must be read-only")
    data = _read_fd_bytes(fd, role)
    if role == "authority-policy":
        digest = hashlib.sha256(_POLICY_DIGEST_DOMAIN + data).digest()
    elif role == "candidate-archive":
        digest = hashlib.sha256(data).digest()
    else:
        digest = hashlib.sha256(_EVIDENCE_ROOT_DIGEST_DOMAIN + data).digest()
    if digest != expected_digest.bytes:
        _channel(f"{role} fd content does not match its bindingDigest")


def _verify_socket_channel(fd: int, role: str) -> None:
    try:
        metadata = os.fstat(fd)
    except OSError as error:
        _channel(f"{role} fd fstat failed: {error}")
    if not stat.S_ISSOCK(metadata.st_mode):
        _channel(f"{role} fd must be a socket")
    try:
        peer = socket.fromfd(fd, socket.AF_UNIX, socket.SOCK_STREAM)
    except OSError as error:
        _channel(f"{role} fd must be an AF_UNIX stream socket: {error}")
    try:
        if peer.getsockopt(socket.SOL_SOCKET, socket.SO_TYPE) != (
            socket.SOCK_STREAM
        ):
            _channel(f"{role} fd must be a stream socket")
        try:
            peer.getsockname()
        except OSError as error:
            _channel(f"{role} socket name check failed: {error}")
        try:
            peer.getpeername()
        except OSError:
            _channel(f"{role} socket must be connected to a peer")
        credentials = peer.getsockopt(
            socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
        )
        _, uid, _ = struct.unpack("3i", credentials)
        if uid != os.geteuid():
            _channel(f"{role} socket peer must share the effective uid")
    finally:
        peer.close()


def verify_inherited_channels(
    handoff: EligibleStage0HandoffV1,
    inherited_fds: Optional[Tuple[int, ...]] = None,
) -> None:
    """Verify the exact inherited channel set against a validated handoff.

    With ``inherited_fds=None`` the set is enumerated from ``/proc/self/fd``;
    the enumeration's own transient directory fd is ignored.  This verifier
    never closes any fd.
    """
    if type(handoff) is not EligibleStage0HandoffV1:
        _handoff("handoff must be an EligibleStage0HandoffV1 record")
    channels = handoff.channels
    if tuple(channel.role for channel in channels) != _CHANNEL_ROLES:
        _channel("handoff channels are not in the frozen role order")
    channel_fds = tuple(channel.fd for channel in channels)
    if any(fd <= 2 for fd in channel_fds) or len(set(channel_fds)) != 4:
        _channel("handoff channel fds must be unique and greater than 2")
    if inherited_fds is None:
        actual = set(_enumerate_inherited_fds())
        expected = {0, 1, 2, *channel_fds}
        missing = expected - actual
        if missing:
            _channel(f"inherited fd set is missing {sorted(missing)}")
        extras = actual - expected
        unexpected = []
        for extra in sorted(extras):
            try:
                target = os.readlink(f"/proc/self/fd/{extra}")
            except FileNotFoundError:
                continue  # the enumeration's own transient directory fd
            except OSError:
                unexpected.append(extra)
                continue
            if target != "/proc/self/fd":
                unexpected.append(extra)
        if unexpected:
            _channel(f"unexpected inherited fds {unexpected}")
    else:
        if type(inherited_fds) is not tuple or any(
            type(fd) is not int for fd in inherited_fds
        ):
            _channel("inherited_fds must be a tuple of integers")
        expected = {0, 1, 2, *channel_fds}
        if set(inherited_fds) != expected:
            _channel("inherited fd set must be exactly {0,1,2} plus channels")

    _verify_stdin_eof()
    for channel in channels:
        if channel.role == "authority-store":
            _verify_socket_channel(channel.fd, channel.role)
        else:
            _verify_regular_channel(
                channel.fd, channel.role, channel.bindingDigest
            )
