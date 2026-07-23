#!/usr/bin/env python3
"""TST-DOC-001/task-qualification-v1 tests-only RED for ADR-0021.

This focused RED matrix freezes the two production black-box surfaces accepted
by ADR-0021 plus the corrected C3 Linux capability transition:

1. ``task_qualification_protected_adapter.protect_taskqualification_v1`` with
   exactly seven required positional-only parameters;
2. the ``AF_UNIX/SOCK_SEQPACKET`` wire observed through ``authorityStoreFd``;
   and
3. a test-owned static Linux probe that reads real kernel capability and
   credential state before/after ordinary ``execveat``.  The probe must fail
   closed on an ineligible host and proves no production acceptance.

It deliberately does *not* require a production module to export parsers,
constants, state-machine helpers, validators, or test hooks that ADR-0021 does
not define. Protocol/reference vectors in this file are test-owned KATs only:

    synthetic-protocol-conformance-only; non-authoritative;
    not production-candidate-bound; does not satisfy current policy,
    custody, currentness, or protected acceptance.

Repository tests cannot produce a production-success acceptance: fixture keys
are forbidden from doing so, role private keys remain candidate-external, and
the exact U/P/A custody topology requires an eligible host. The successful
service/terminal path therefore belongs to candidate-external qualified
integration evidence. An ineligible host is never treated as a pass or as a
synthetic authority fallback.

At this corrected tests-only commit the authoritative v2 runtime/entrypoint is
still absent, so production black-box cases remain RED for the stable reason
``API-ABSENT``.  The protocol KATs and real-kernel feasibility probe must
already pass; otherwise the runner reports a preflight failure rather than
disguising a broken fixture or ineligible host as RED.

Run with::

    /usr/bin/python3 -I -S scripts/task_qualification_authority_store_v2_self_test.py
"""

from __future__ import annotations

import errno
import hashlib
import inspect
import os
import pwd
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable

_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent))

import bootstrap_task_objects as _BTO
import bootstrap_task_producers as _BTP
import task_qualification_protected_adapter as _ADAPTER


# ---------------------------------------------------------------------------
# Accepted black-box contract
# ---------------------------------------------------------------------------

API_NAME = "protect_taskqualification_v1"
API_PARAMETER_NAMES = (
    "operationBytes",
    "handoffBytes",
    "authorityPolicyFd",
    "authorityStoreFd",
    "candidateArchiveFd",
    "provenanceBundleFd",
    "trustedClockFd",
)
API_ABSENT = "API-ABSENT"

OPERATIONS = (
    b"task-qualification",
    b"task-completion",
    b"d0-10-bootstrap-approval",
    b"d0-10-bootstrap-receipt",
)

MAX_FRAME_BYTES = 4_194_304
MAX_PACKET_BYTES = 4 + MAX_FRAME_BYTES
MAX_ACCEPTANCE_BYTES = 2_000_000

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

FRAME_FULL_DOMAINS = {
    CLIENT_HELLO_SCHEMA: b"pf.taskqual.store-client-hello.v2",
    SERVER_HELLO_SCHEMA: b"pf.taskqual.store-server-hello.v2",
    LOOKUP_REQUEST_SCHEMA: b"pf.taskqual.store-lookup-request.v2",
    LOOKUP_RESPONSE_SCHEMA: b"pf.taskqual.store-lookup-response.v2",
    TERMINAL_REQUEST_SCHEMA: b"pf.taskqual.store-acceptance-sign-request.v2",
    TERMINAL_RESPONSE_SCHEMA: b"pf.taskqual.store-acceptance-sign-response.v2",
}
FRAME_SIGNATURE_DOMAINS = {
    SERVER_HELLO_SCHEMA: b"pf.taskqual.store-server-hello-signature.v2",
    LOOKUP_RESPONSE_SCHEMA: b"pf.taskqual.store-lookup-response-signature.v2",
    TERMINAL_RESPONSE_SCHEMA:
        b"pf.taskqual.store-acceptance-sign-response-signature.v2",
}

ACCEPTANCE_SCHEMA = "proof-forge.protected-task-qualification-acceptance.v1"
ACCEPTANCE_STATEMENT_DOMAIN = b"pf.taskqual.protected-acceptance-statement.v1"
ACCEPTANCE_SIGNATURE_DOMAIN = b"pf.taskqual.protected-acceptance-signature.v1"
ACCEPTANCE_FULL_DOMAIN = b"pf.taskqual.protected-acceptance.v1"

SYNTHETIC_PROTOCOL_LABEL = (
    "synthetic-protocol-conformance-only; non-authoritative; "
    "not production-candidate-bound"
)

CAP_SETPCAP = 8
CAP_SYS_PTRACE = 19
_TRANSITION_MASK = (1 << CAP_SETPCAP) | (1 << CAP_SYS_PTRACE)
_PTRACE_MASK = 1 << CAP_SYS_PTRACE
_CAPABILITY_PROBE_SOURCE = _HERE.with_name(
    "task_qualification_custody_capability_probe.c"
)

# Test-owned reference trace.  Production does not import this structure; the
# qualified seven-argument path remains the only production positive surface.
_EXPECTED_CAPABILITY_TRACE = (
    ("adapter-final", 0, 0, 0, 0, 0, 1001, 1003, 0, 1),
    (
        "service-pre-exec",
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        1002,
        1004,
        0,
        1,
    ),
    (
        "service-post-exec",
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        _TRANSITION_MASK,
        1002,
        1004,
        0,
        1,
    ),
    ("service-steady", 0, _PTRACE_MASK, _PTRACE_MASK, 0, 0, 1002, 1004, 0, 1),
    ("service-terminal", 0, 0, 0, 0, 0, 1002, 1004, 0, 1),
)
_EXPECTED_OLD_TRACE = (
    ("old-pre-exec", _PTRACE_MASK, _PTRACE_MASK, _PTRACE_MASK, 0, 0,
     1002, 1004, 0, 1),
    ("old-post-exec", _PTRACE_MASK, 0, 0, 0, 0, 1002, 1004, 0, 1),
)
_EXPECTED_CAPABILITY_EVENTS = (
    "adapter.drop-bounding-all",
    "adapter.setgroups-empty",
    "adapter.setresgid-all",
    "adapter.setresuid-all",
    "adapter.clear-capabilities",
    "adapter.set-no-new-privs",
    "service.drop-bounding-except-8-19",
    "service.set-keepcaps",
    "service.setgroups-empty",
    "service.setresgid-all",
    "service.setresuid-all",
    "service.capset-8-19",
    "service.ambient-raise-8",
    "service.ambient-raise-19",
    "service.set-no-new-privs",
    "service.pre-exec-checkpoint",
    "service.execveat-at-empty-path",
    "service.post-exec-checkpoint",
    "service.drop-bounding-19",
    "service.drop-bounding-8",
    "service.ambient-clear-all",
    "service.capset-steady-ptrace",
    "service.steady-checkpoint",
    "service.capset-terminal-zero",
    "service.terminal-checkpoint",
)
_FILTERED_CREDENTIAL_MUTATIONS = (
    "setuid", "setgid", "setreuid", "setregid", "setresuid", "setresgid",
    "setfsuid", "setfsgid", "setgroups",
)
_FORBIDDEN_CAPABILITY_FALLBACKS = (
    "file-capability", "u-root", "extra-helper", "host-skip", "best-effort",
)

# Dedicated non-production arithmetic keys. They deliberately differ from both
# RFC 8032 fixture vectors and the committed activated production public keys.
_SYNTHETIC_ROLE_SEEDS = {
    "key-architecture": hashlib.sha256(b"pf-red-v2-architecture").digest(),
    "key-quality": hashlib.sha256(b"pf-red-v2-quality").digest(),
    "key-security": hashlib.sha256(b"pf-red-v2-security").digest(),
}
_SYNTHETIC_RELEASE_SEED = hashlib.sha256(b"pf-red-v2-release").digest()
_SYNTHETIC_POLICY_SEEDS = {
    **_SYNTHETIC_ROLE_SEEDS,
    "key-release": _SYNTHETIC_RELEASE_SEED,
}
_SYNTHETIC_SERVICE_SEED = hashlib.sha256(b"pf-red-v2-service").digest()
_SYNTHETIC_RECEIPT_SEED = hashlib.sha256(b"pf-red-v2-receipt").digest()
_SYNTHETIC_SERVICE_PUBLIC_KEY = _BTP.ed25519_public_key_from_seed(
    _SYNTHETIC_SERVICE_SEED
)


# ---------------------------------------------------------------------------
# Test-owned protocol reference functions (never imported by production)
# ---------------------------------------------------------------------------


def _canonical(value: Any) -> bytes:
    return _BTO.canonical_pf_jcs(value)


def _digest_wire(raw: bytes) -> str:
    return "sha256:" + raw.hex()


def _domain_digest(domain: bytes, value: Any) -> bytes:
    return hashlib.sha256(domain + b"\x00" + _canonical(value)).digest()


def _encode_packet(payload: bytes) -> bytes:
    if type(payload) is not bytes or not 1 <= len(payload) <= MAX_FRAME_BYTES:
        raise ValueError("payload length must be 1..4194304")
    return len(payload).to_bytes(4, "big") + payload


def _decode_packet(packet: bytes, *, msg_flags: int = 0) -> bytes:
    if type(packet) is not bytes:
        raise ValueError("packet must be exact bytes")
    if msg_flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC):
        raise ValueError("truncated packet or ancillary data")
    if len(packet) < 4:
        raise ValueError("truncated u32be header")
    length = int.from_bytes(packet[:4], "big")
    if not 1 <= length <= MAX_FRAME_BYTES:
        raise ValueError("payload length out of bounds")
    if len(packet) != 4 + length:
        raise ValueError("packet/u32 length mismatch")
    return packet[4:]


def _server_signature_message(frame: dict[str, Any]) -> bytes:
    schema = frame.get("schema")
    domain = FRAME_SIGNATURE_DOMAINS.get(schema)
    if domain is None or "signature" not in frame:
        raise ValueError("not a signed server frame")
    unsigned = dict(frame)
    unsigned.pop("signature")
    return domain + b"\x00" + _canonical(unsigned)


def _frame_full_digest(frame: dict[str, Any]) -> bytes:
    domain = FRAME_FULL_DOMAINS.get(frame.get("schema"))
    if domain is None:
        raise ValueError("unknown frame schema")
    return _domain_digest(domain, frame)


def _synthetic_invalid_content_ref(schema: str, identifier: str) -> dict[str, Any]:
    """Deliberately non-authoritative placeholder using a normative schema.

    It exists only to exercise closed wire encoding. Its digest is not claimed
    to resolve a current authority object, and no production consumer is asked
    to accept it.
    """
    return {
        "schema": schema,
        "id": identifier,
        "version": "1.0.0",
        "digest": _digest_wire(hashlib.sha256(identifier.encode("ascii")).digest()),
    }


def _synthetic_invalid_verifier(identifier: str) -> dict[str, Any]:
    return {
        "id": identifier,
        "executable": _synthetic_invalid_content_ref(
            "proof-forge.private-scan-policy.v1", identifier + "-executable"
        ),
        "closure": _synthetic_invalid_content_ref(
            "proof-forge.private-scan-policy.v1", identifier + "-closure"
        ),
        "sourceDigest": _digest_wire(
            hashlib.sha256((identifier + "-source").encode("ascii")).digest()
        ),
        "buildPolicy": _synthetic_invalid_content_ref(
            "proof-forge.private-scan-policy.v1", identifier + "-build-policy"
        ),
    }


def _synthetic_unsigned_acceptance() -> dict[str, Any]:
    """Exact accepted field manifest, deliberately invalid authority values.

    This vector tests only statement-byte transformation and domains. It is not
    supplied to the production adapter and cannot close any task.
    """
    adapter = _synthetic_invalid_verifier("test-only-adapter")
    parser = _synthetic_invalid_verifier("test-only-snapshot-parser")
    return {
        "schema": ACCEPTANCE_SCHEMA,
        "id": "protected-task-qualification-task-qualification-d0-10",
        "version": "1.0.0",
        "authorityClass": "production-candidate-bound",
        "operation": "task-qualification",
        "pureProjectionDigest": _digest_wire(hashlib.sha256(b"pure").digest()),
        "bundleDigest": _digest_wire(hashlib.sha256(b"bundle").digest()),
        "subjectDigest": _digest_wire(hashlib.sha256(b"subject").digest()),
        "preCloseCandidate": {
            "commit": "0" * 40,
            "treeObjectId": "1" * 40,
            "archiveSha256": _digest_wire(hashlib.sha256(b"archive").digest()),
        },
        "closeoutCandidate": None,
        "trustedVerificationInstant": "2026-07-23T12:00:00Z",
        "adapter": adapter,
        "snapshotParser": parser,
        "productionProfileDigest": _digest_wire(
            hashlib.sha256(b"invalid-profile").digest()
        ),
        "productionProfilePin": _synthetic_invalid_content_ref(
            "proof-forge.task-qualification-production-profile-pin.v1",
            "tq-pin-d0-10-tq-" + "2" * 48,
        ),
        "ledgerProjectionDigest": None,
        "governanceCompletionDigest": None,
        "provenanceBundleDigest": _digest_wire(
            hashlib.sha256(b"invalid-provenance").digest()
        ),
        "provenanceRoles": ["live-handoff"],
    }


def _acceptance_statement_digest(unsigned: dict[str, Any]) -> bytes:
    return _domain_digest(ACCEPTANCE_STATEMENT_DOMAIN, unsigned)


def _synthetic_role_signatures(unsigned: dict[str, Any]) -> list[dict[str, Any]]:
    statement = _acceptance_statement_digest(unsigned)
    message = ACCEPTANCE_SIGNATURE_DOMAIN + b"\x00" + statement
    signatures = []
    for key_id in sorted(_SYNTHETIC_ROLE_SEEDS):
        signatures.append({
            "keyId": key_id,
            "algorithm": "ed25519",
            "signature": _BTP.sign_ed25519(
                _SYNTHETIC_ROLE_SEEDS[key_id], message
            ).hex(),
        })
    return signatures


def _synthetic_server_hello() -> dict[str, Any]:
    unsigned = {
        "schema": SERVER_HELLO_SCHEMA,
        "version": "2.0.0",
        "taskId": "TASK-D0-10",
        "operation": "task-qualification",
        "runId": "test-only-run",
        "nonce": "test-only-nonce",
        "service": _synthetic_invalid_content_ref(
            "proof-forge.task-qualification-authority-store-service.v2",
            "task-qualification-store-service-test-only-run",
        ),
        "handoffDigest": _digest_wire(hashlib.sha256(b"handoff").digest()),
        "headSequence": 0,
        "headDigest": _digest_wire(hashlib.sha256(b"head").digest()),
        "status": "ready",
    }
    message = (
        FRAME_SIGNATURE_DOMAINS[SERVER_HELLO_SCHEMA]
        + b"\x00"
        + _canonical(unsigned)
    )
    frame = dict(unsigned)
    frame["signature"] = _BTP.sign_ed25519(
        _SYNTHETIC_SERVICE_SEED, message
    ).hex()
    return frame


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def __str__(self) -> str:
        marker = "PASS" if self.passed else "RED"
        suffix = f" — {self.detail}" if self.detail else ""
        return f"[{marker}] {self.name}{suffix}"


def _pass(name: str, detail: str = "") -> Result:
    return Result(name, True, detail)


def _red(name: str, detail: str) -> Result:
    return Result(name, False, detail)


def _entrypoint() -> Callable[..., Any] | None:
    candidate = getattr(_ADAPTER, API_NAME, None)
    return candidate if callable(candidate) else None


def _api_required(name: str) -> tuple[Callable[..., Any] | None, Result | None]:
    candidate = _entrypoint()
    if candidate is None:
        return None, _red(name, API_ABSENT)
    return candidate, None


def _is_rejection(value: Any) -> bool:
    rejected_type = getattr(_BTO, "Rejected", None)
    return rejected_type is not None and isinstance(value, rejected_type)


def _expect_rejection(name: str, invoke: Callable[[], Any]) -> Result:
    def _deadline(_signum: int, _frame: Any) -> None:
        raise TimeoutError("black-box invocation exceeded two seconds")

    previous = signal.signal(signal.SIGALRM, _deadline)
    signal.setitimer(signal.ITIMER_REAL, 2.0)
    try:
        try:
            value = invoke()
        except TimeoutError as exc:
            return _red(name, str(exc))
        except (TypeError, ValueError, OSError) as exc:
            return _pass(name, f"fail-closed exception {type(exc).__name__}")
        except Exception as exc:  # a stable project Rejected may be raised
            if exc.__class__.__name__ == "Rejected":
                return _pass(name, "Rejected")
            return _red(name, f"unexpected exception {type(exc).__name__}: {exc}")
        if _is_rejection(value):
            return _pass(name, "Rejected")
        return _red(name, f"invalid invocation returned {type(value).__name__}")
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0.0)
        signal.signal(signal.SIGALRM, previous)


def _validate_reference_capability_matrix(
    trace: tuple[tuple[Any, ...], ...], events: tuple[str, ...]
) -> None:
    if trace != _EXPECTED_CAPABILITY_TRACE:
        raise ValueError("capability checkpoint trace mismatch")
    if events != _EXPECTED_CAPABILITY_EVENTS:
        raise ValueError("capability event order mismatch")
    if _FILTERED_CREDENTIAL_MUTATIONS != (
        "setuid", "setgid", "setreuid", "setregid", "setresuid", "setresgid",
        "setfsuid", "setfsgid", "setgroups",
    ):
        raise ValueError("filtered credential mutation set drift")
    if _FORBIDDEN_CAPABILITY_FALLBACKS != (
        "file-capability", "u-root", "extra-helper", "host-skip", "best-effort",
    ):
        raise ValueError("forbidden capability fallback set drift")


def _mutate_trace(
    row_index: int, field_index: int, value: Any
) -> tuple[tuple[Any, ...], ...]:
    rows = [list(row) for row in _EXPECTED_CAPABILITY_TRACE]
    rows[row_index][field_index] = value
    return tuple(tuple(row) for row in rows)


def _subordinate_values(
    path: Path, username: str, wanted: int, excluded: set[int]
) -> list[int]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc
    result: list[int] = []
    accepted_names = {username, str(os.getuid())}
    for line in lines:
        fields = line.split(":")
        if len(fields) != 3 or fields[0] not in accepted_names:
            continue
        try:
            start = int(fields[1], 10)
            count = int(fields[2], 10)
        except ValueError as exc:
            raise ValueError(f"malformed subordinate range in {path}") from exc
        if start < 0 or count <= 0:
            raise ValueError(f"invalid subordinate range in {path}")
        for value in range(start, start + count):
            if value in excluded or value in result:
                continue
            result.append(value)
            if len(result) == wanted:
                return result
    raise ValueError(f"{path} lacks {wanted} distinct subordinate IDs")


def _eligible_mapping_ids() -> tuple[int, int, int, int]:
    if sys.platform != "linux":
        raise ValueError("capability kernel matrix requires Linux")
    for helper in (Path("/usr/bin/newuidmap"), Path("/usr/bin/newgidmap")):
        try:
            metadata = helper.stat()
        except OSError as exc:
            raise ValueError(f"missing mapping helper {helper}") from exc
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                or not metadata.st_mode & stat.S_ISUID):
            raise ValueError(f"mapping helper is not setuid-root regular: {helper}")
    username = pwd.getpwuid(os.getuid()).pw_name
    uid_values = _subordinate_values(Path("/etc/subuid"), username, 2, set())
    gid_values = _subordinate_values(
        Path("/etc/subgid"), username, 2, set(uid_values)
    )
    values = tuple(uid_values + gid_values)
    if len(set(values)) != 4:
        raise ValueError("four host subordinate IDs are not distinct")
    return values  # type: ignore[return-value]


def _validate_static_probe(executable: Path) -> None:
    metadata = executable.stat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1
            or metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise ValueError("probe is not an ordinary single-link executable")
    try:
        os.getxattr(executable, "security.capability")
    except OSError as exc:
        if exc.errno != errno.ENODATA:
            raise ValueError(
                f"security.capability absence was not ENODATA: {exc.errno}"
            ) from exc
    else:
        raise ValueError("probe unexpectedly has security.capability")

    raw = executable.read_bytes()
    if len(raw) < 64 or raw[:4] != b"\x7fELF" or raw[4:6] != b"\x02\x01":
        raise ValueError("probe is not ELF64 little-endian")
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", raw, 0)
    if header[2] != 62 or header[8] != 64 or header[9] != 56:
        raise ValueError("probe ELF header/machine mismatch")
    program_offset = header[5]
    program_count = header[10]
    if program_count == 0 or program_offset + program_count * 56 > len(raw):
        raise ValueError("probe program headers out of bounds")
    dynamic_ranges: list[tuple[int, int]] = []
    for index in range(program_count):
        fields = struct.unpack_from("<IIQQQQQQ", raw, program_offset + index * 56)
        segment_type, segment_offset, segment_size = fields[0], fields[2], fields[5]
        if segment_offset + segment_size > len(raw):
            raise ValueError("probe ELF segment out of bounds")
        if segment_type == 3:  # PT_INTERP
            raise ValueError("probe contains PT_INTERP")
        if segment_type == 2:  # PT_DYNAMIC
            dynamic_ranges.append((segment_offset, segment_size))
    for offset, size in dynamic_ranges:
        if size % 16 != 0:
            raise ValueError("probe PT_DYNAMIC size is not entry-aligned")
        for cursor in range(offset, offset + size, 16):
            tag, _value = struct.unpack_from("<QQ", raw, cursor)
            if tag == 0:
                break
            if tag == 1:  # DT_NEEDED
                raise ValueError("probe contains DT_NEEDED")


def _parse_probe_trace(stdout: str) -> tuple[tuple[tuple[Any, ...], ...], bool]:
    rows: list[tuple[Any, ...]] = []
    old_drop = False
    expected_keys = {
        "label", "bnd", "prm", "eff", "inh", "amb",
        "uid", "gid", "groups", "nnp",
    }
    for line in stdout.splitlines():
        if line.startswith("PF-CAP-CHECKPOINT "):
            fields: dict[str, str] = {}
            for token in line[len("PF-CAP-CHECKPOINT "):].split(" "):
                if token.count("=") != 1:
                    raise ValueError("malformed capability checkpoint token")
                key, value = token.split("=", 1)
                if key in fields:
                    raise ValueError("duplicate capability checkpoint field")
                fields[key] = value
            if set(fields) != expected_keys:
                raise ValueError("capability checkpoint field set mismatch")
            masks = tuple(
                int(fields[key], 16) for key in ("bnd", "prm", "eff", "inh", "amb")
            )
            rows.append((
                fields["label"], *masks,
                int(fields["uid"], 10), int(fields["gid"], 10),
                int(fields["groups"], 10), int(fields["nnp"], 10),
            ))
        elif line.startswith("PF-CAP-OLD-DROP "):
            if line != "PF-CAP-OLD-DROP errno=1" or old_drop:
                raise ValueError("old checkpoint drop marker mismatch")
            old_drop = True
        elif line:
            raise ValueError(f"unexpected capability probe output: {line!r}")
    return tuple(rows), old_drop


def _run_capability_probe() -> tuple[
    tuple[tuple[Any, ...], ...], tuple[tuple[Any, ...], ...]
]:
    outside_ids = _eligible_mapping_ids()
    if not _CAPABILITY_PROBE_SOURCE.is_file() or _CAPABILITY_PROBE_SOURCE.is_symlink():
        raise ValueError("capability probe source is missing or not a regular file")
    compiler = Path("/usr/bin/cc")
    if not compiler.is_file():
        raise ValueError("/usr/bin/cc is required for the kernel capability matrix")
    with tempfile.TemporaryDirectory(prefix="pf-capability-red-") as temporary:
        executable = Path(temporary) / "pf-capability-probe"
        compile_result = subprocess.run(
            [
                str(compiler), "-static", "-no-pie", "-O2", "-std=c11",
                "-Wall", "-Wextra", "-Werror", "-o", str(executable),
                str(_CAPABILITY_PROBE_SOURCE),
            ],
            cwd=_HERE.parent.parent,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        if compile_result.returncode != 0:
            raise ValueError(
                "static capability probe compilation failed: "
                + compile_result.stderr.strip()
            )
        if compile_result.stdout:
            raise ValueError("capability probe compiler wrote unexpected stdout")
        _validate_static_probe(executable)
        argv_ids = [str(value) for value in outside_ids]
        traces: list[tuple[tuple[Any, ...], ...]] = []
        for mode in ("--positive", "--old"):
            invocation = subprocess.run(
                [str(executable), mode, *argv_ids],
                cwd=temporary,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
                check=False,
            )
            if invocation.returncode != 0:
                raise ValueError(
                    f"capability probe {mode} failed exit={invocation.returncode}: "
                    + invocation.stderr.strip()
                )
            if invocation.stderr:
                raise ValueError(f"capability probe {mode} wrote stderr")
            trace, old_drop = _parse_probe_trace(invocation.stdout)
            if old_drop != (mode == "--old"):
                raise ValueError("old checkpoint EPERM marker cardinality mismatch")
            traces.append(trace)
        return traces[0], traces[1]


# ---------------------------------------------------------------------------
# Test-owned protocol KATs — these must pass in the RED commit
# ---------------------------------------------------------------------------


def kat_synthetic_label_is_explicit() -> Result:
    name = "kat.synthetic_label"
    required = (
        "synthetic-protocol-conformance-only",
        "non-authoritative",
        "not production-candidate-bound",
    )
    if not all(token in SYNTHETIC_PROTOCOL_LABEL for token in required):
        return _red(name, "synthetic vectors are not explicitly non-authoritative")
    return _pass(name)


def kat_corrected_capability_reference_matrix() -> Result:
    name = "kat.corrected_capability_reference_matrix"
    try:
        _validate_reference_capability_matrix(
            _EXPECTED_CAPABILITY_TRACE, _EXPECTED_CAPABILITY_EVENTS
        )
    except ValueError as exc:
        return _red(name, f"valid reference rejected: {exc}")

    mutations: list[tuple[str, tuple[tuple[Any, ...], ...], tuple[str, ...]]] = []
    without_setpcap = _TRANSITION_MASK & ~(1 << CAP_SETPCAP)
    without_ptrace = _TRANSITION_MASK & ~(1 << CAP_SYS_PTRACE)
    for row_index in (1, 2):
        for field_index in range(1, 6):
            mutations.append((
                f"checkpoint-{row_index}-missing-setpcap-{field_index}",
                _mutate_trace(row_index, field_index, without_setpcap),
                _EXPECTED_CAPABILITY_EVENTS,
            ))
            mutations.append((
                f"checkpoint-{row_index}-missing-ptrace-{field_index}",
                _mutate_trace(row_index, field_index, without_ptrace),
                _EXPECTED_CAPABILITY_EVENTS,
            ))
    mutations.append((
        "pre-exec-extra-capability",
        _mutate_trace(1, 1, _TRANSITION_MASK | 1),
        _EXPECTED_CAPABILITY_EVENTS,
    ))
    for field_index in range(1, 6):
        mutations.append((
            f"steady-residual-setpcap-{field_index}",
            _mutate_trace(3, field_index, 1 << CAP_SETPCAP),
            _EXPECTED_CAPABILITY_EVENTS,
        ))
        mutations.append((
            f"terminal-residual-ptrace-{field_index}",
            _mutate_trace(4, field_index, _PTRACE_MASK),
            _EXPECTED_CAPABILITY_EVENTS,
        ))
    mutations.extend((
        (
            "adapter-supplementary-group",
            _mutate_trace(0, 8, 1),
            _EXPECTED_CAPABILITY_EVENTS,
        ),
        (
            "service-credential-alias",
            _mutate_trace(3, 6, 0),
            _EXPECTED_CAPABILITY_EVENTS,
        ),
        (
            "checkpoint-order-swap",
            (
                _EXPECTED_CAPABILITY_TRACE[0],
                _EXPECTED_CAPABILITY_TRACE[2],
                _EXPECTED_CAPABILITY_TRACE[1],
                *_EXPECTED_CAPABILITY_TRACE[3:],
            ),
            _EXPECTED_CAPABILITY_EVENTS,
        ),
    ))

    event_mutations: list[tuple[str, tuple[str, ...]]] = []
    credential_swap = list(_EXPECTED_CAPABILITY_EVENTS)
    credential_swap[8], credential_swap[9] = credential_swap[9], credential_swap[8]
    event_mutations.append(("credential-order", tuple(credential_swap)))
    bounding_swap = list(_EXPECTED_CAPABILITY_EVENTS)
    bounding_swap[18], bounding_swap[19] = bounding_swap[19], bounding_swap[18]
    event_mutations.append(("bounding-drop-order", tuple(bounding_swap)))
    event_mutations.append((
        "missing-ambient-raise",
        tuple(event for event in _EXPECTED_CAPABILITY_EVENTS
              if event != "service.ambient-raise-8"),
    ))
    event_mutations.append((
        "filtered-credential-mutation",
        _EXPECTED_CAPABILITY_EVENTS + ("service-final.setfsuid",),
    ))
    event_mutations.append((
        "forbidden-fallback",
        _EXPECTED_CAPABILITY_EVENTS + ("fallback.file-capability",),
    ))
    for mutation_name, events in event_mutations:
        mutations.append((mutation_name, _EXPECTED_CAPABILITY_TRACE, events))

    if len({mutation[0] for mutation in mutations}) != len(mutations):
        return _red(name, "capability mutation names are not unique")
    for mutation_name, trace, events in mutations:
        try:
            _validate_reference_capability_matrix(trace, events)
        except ValueError:
            continue
        return _red(name, f"mutation accepted: {mutation_name}")
    return _pass(name, f"{len(mutations)} exact mutations rejected")


def kat_eligible_kernel_capability_transition() -> Result:
    name = "kat.eligible_kernel_capability_transition"
    try:
        positive_trace, old_trace = _run_capability_probe()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        return _red(name, f"eligible-host probe failed closed: {exc}")
    if positive_trace != _EXPECTED_CAPABILITY_TRACE:
        return _red(name, "corrected kernel checkpoint trace mismatch")
    if old_trace != _EXPECTED_OLD_TRACE:
        return _red(name, "superseded ptrace-only kernel trace mismatch")
    return _pass(
        name,
        "static exec [8,19]→ptrace-only→zero; old [19] loses P/E and returns EPERM",
    )


def kat_six_frame_schemas_are_exact() -> Result:
    name = "kat.six_frame_schemas"
    schemas = CLIENT_FRAME_SCHEMAS + SERVER_FRAME_SCHEMAS
    if len(schemas) != 6 or len(set(schemas)) != 6:
        return _red(name, "frame schema count/uniqueness drift")
    if set(FRAME_FULL_DOMAINS) != set(schemas):
        return _red(name, "full-domain coverage drift")
    if set(FRAME_SIGNATURE_DOMAINS) != set(SERVER_FRAME_SCHEMAS):
        return _red(name, "signature domains are not server-only")
    if not all(domain.endswith(b".v2") for domain in FRAME_FULL_DOMAINS.values()):
        return _red(name, "non-v2 frame full domain")
    return _pass(name)


def kat_packet_round_trip() -> Result:
    name = "kat.packet_round_trip"
    payload = _canonical({"schema": CLIENT_HELLO_SCHEMA})
    packet = _encode_packet(payload)
    if len(packet) != 4 + len(payload):
        return _red(name, "packet size mismatch")
    if _decode_packet(packet) != payload:
        return _red(name, "packet payload mismatch")
    return _pass(name)


def kat_packet_rejects_zero() -> Result:
    return _expect_rejection(
        "kat.packet_rejects_zero", lambda: _decode_packet(b"\x00\x00\x00\x00")
    )


def kat_packet_rejects_length_mismatch() -> Result:
    return _expect_rejection(
        "kat.packet_rejects_length_mismatch",
        lambda: _decode_packet(b"\x00\x00\x00\x05{}"),
    )


def kat_packet_rejects_two_frames() -> Result:
    packet = _encode_packet(b"{}") + _encode_packet(b"[]")
    return _expect_rejection(
        "kat.packet_rejects_two_frames", lambda: _decode_packet(packet)
    )


def kat_packet_rejects_truncation_flags() -> Result:
    packet = _encode_packet(b"{}")
    first = _expect_rejection(
        "kat.packet_rejects_truncation_flags",
        lambda: _decode_packet(packet, msg_flags=socket.MSG_TRUNC),
    )
    if not first.passed:
        return first
    return _expect_rejection(
        "kat.packet_rejects_truncation_flags",
        lambda: _decode_packet(packet, msg_flags=socket.MSG_CTRUNC),
    )


def kat_server_signature_domain() -> Result:
    name = "kat.server_signature_domain"
    frame = _synthetic_server_hello()
    signature = bytes.fromhex(frame["signature"])
    if not _BTO.verify_ed25519(
        _SYNTHETIC_SERVICE_PUBLIC_KEY,
        _server_signature_message(frame),
        signature,
    ):
        return _red(name, "synthetic service signature arithmetic mismatch")
    expected = _domain_digest(FRAME_FULL_DOMAINS[SERVER_HELLO_SCHEMA], frame)
    if _frame_full_digest(frame) != expected:
        return _red(name, "server hello full digest mismatch")
    return _pass(name)


def kat_unsigned_acceptance_manifest() -> Result:
    name = "kat.unsigned_acceptance_manifest"
    expected = [
        "schema", "id", "version", "authorityClass", "operation",
        "pureProjectionDigest", "bundleDigest", "subjectDigest",
        "preCloseCandidate", "closeoutCandidate", "trustedVerificationInstant",
        "adapter", "snapshotParser", "productionProfileDigest",
        "productionProfilePin", "ledgerProjectionDigest",
        "governanceCompletionDigest", "provenanceBundleDigest",
        "provenanceRoles",
    ]
    unsigned = _synthetic_unsigned_acceptance()
    if list(unsigned) != expected:
        return _red(name, "accepted field manifest/order drift")
    if "signatures" in unsigned or "provenanceRefs" in unsigned:
        return _red(name, "unsigned wire contains forbidden legacy/signature field")
    return _pass(name)


def kat_acceptance_statement_removes_signatures() -> Result:
    name = "kat.acceptance_statement_removes_signatures"
    unsigned = _synthetic_unsigned_acceptance()
    signatures = _synthetic_role_signatures(unsigned)
    signed = dict(unsigned)
    signed["signatures"] = signatures
    stripped = dict(signed)
    stripped.pop("signatures")
    if _canonical(stripped) != _canonical(unsigned):
        return _red(name, "signed-minus-signatures differs from unsigned bytes")
    expected = hashlib.sha256(
        ACCEPTANCE_STATEMENT_DOMAIN + b"\x00" + _canonical(unsigned)
    ).digest()
    if _acceptance_statement_digest(unsigned) != expected:
        return _red(name, "statement digest domain mismatch")
    return _pass(name)


def kat_acceptance_role_signature_arithmetic() -> Result:
    name = "kat.acceptance_role_signature_arithmetic"
    unsigned = _synthetic_unsigned_acceptance()
    statement = _acceptance_statement_digest(unsigned)
    message = ACCEPTANCE_SIGNATURE_DOMAIN + b"\x00" + statement
    signatures = _synthetic_role_signatures(unsigned)
    if [item["keyId"] for item in signatures] != sorted(_SYNTHETIC_ROLE_SEEDS):
        return _red(name, "synthetic keyIds not sorted")
    for item in signatures:
        public_key = _BTP.ed25519_public_key_from_seed(
            _SYNTHETIC_ROLE_SEEDS[item["keyId"]]
        )
        if not _BTO.verify_ed25519(
            public_key, message, bytes.fromhex(item["signature"])
        ):
            return _red(name, f"signature arithmetic failed for {item['keyId']}")
    signed = dict(unsigned)
    signed["signatures"] = signatures
    if len(_canonical(signed)) > MAX_ACCEPTANCE_BYTES:
        return _red(name, "synthetic signed wire exceeds acceptance bound")
    full = _domain_digest(ACCEPTANCE_FULL_DOMAIN, signed)
    if len(full) != 32:
        return _red(name, "acceptance full digest is not SHA-256")
    return _pass(name)


def kat_docs_check_does_not_call_protected_api() -> Result:
    name = "kat.docs_check_structural_only"
    source = (_HERE.with_name("docs_check.py")).read_text(encoding="utf-8")
    forbidden_calls = (
        "protect_taskqualification_v1(",
        "task_qualification_authority_store_v2",
    )
    if any(token in source for token in forbidden_calls):
        return _red(name, "root docs-check invokes the protected v2 path")
    return _pass(name)


def kat_qualified_hex_grammar_is_strict() -> Result:
    name = "kat.qualified_hex_grammar"
    invalid = ("", "0", "AA", "0a ", " 0a", "0g", "0A")
    for value in invalid:
        try:
            _strict_lower_hex(
                value, minimum_bytes=1, maximum_bytes=32, where="fixture"
            )
        except ValueError:
            continue
        return _red(name, f"invalid hex accepted: {value!r}")
    if _strict_lower_hex(
        "00ff", minimum_bytes=1, maximum_bytes=32, where="fixture"
    ) != b"\x00\xff":
        return _red(name, "valid lowercase hex decoded incorrectly")
    invalid_signatures = (
        "aa" * 63,
        "aa" * 65,
        "AA" * 64,
        ("aa" * 32) + " " + ("aa" * 32),
        ("aa" * 63) + "gg",
        ("aa" * 63) + "a",
    )
    for value in invalid_signatures:
        try:
            _strict_lower_hex(
                value, minimum_bytes=64, maximum_bytes=64,
                where="acceptance.signature",
            )
        except ValueError:
            continue
        return _red(name, "noncanonical acceptance signature hex accepted")
    return _pass(name)


def kat_qualified_deadline_restores_signal_state() -> Result:
    name = "kat.qualified_deadline_cleanup"
    global QUALIFIED_TIMEOUT_SECONDS
    global _blackbox_qualified_production_acceptance_inner
    original_timeout = QUALIFIED_TIMEOUT_SECONDS
    original_inner = _blackbox_qualified_production_acceptance_inner
    original_handler = signal.getsignal(signal.SIGALRM)
    original_timer = signal.getitimer(signal.ITIMER_REAL)

    def _hang() -> Result:
        time.sleep(1.0)
        return _pass("unreachable")

    try:
        QUALIFIED_TIMEOUT_SECONDS = 0.02
        _blackbox_qualified_production_acceptance_inner = _hang
        result = blackbox_qualified_production_acceptance()
        if result.passed or "exceeded" not in result.detail:
            return _red(name, "hanging qualified invocation did not time out")
        if signal.getsignal(signal.SIGALRM) != original_handler:
            return _red(name, "qualified timeout did not restore SIGALRM handler")
        remaining = signal.getitimer(signal.ITIMER_REAL)
        if original_timer == (0.0, 0.0) and remaining != (0.0, 0.0):
            return _red(name, "qualified timeout left an unexpected timer armed")
        return _pass(name)
    finally:
        QUALIFIED_TIMEOUT_SECONDS = original_timeout
        _blackbox_qualified_production_acceptance_inner = original_inner
        signal.setitimer(signal.ITIMER_REAL, 0.0)
        signal.signal(signal.SIGALRM, original_handler)
        if original_timer != (0.0, 0.0):
            signal.setitimer(signal.ITIMER_REAL, *original_timer)


# ---------------------------------------------------------------------------
# Production black-box RED cases — only the accepted seven-argument API
# ---------------------------------------------------------------------------


def blackbox_api_exists() -> Result:
    name = "blackbox.api_exists"
    candidate = _entrypoint()
    if candidate is None:
        return _red(name, API_ABSENT)
    return _pass(name)


def blackbox_api_signature_exact() -> Result:
    name = "blackbox.api_signature_exact"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    parameters = list(inspect.signature(candidate).parameters.values())
    if tuple(parameter.name for parameter in parameters) != API_PARAMETER_NAMES:
        return _red(name, "parameter names/order drift")
    if any(parameter.kind is not inspect.Parameter.POSITIONAL_ONLY
           for parameter in parameters):
        return _red(name, "all seven parameters must be POSITIONAL_ONLY")
    if any(parameter.default is not inspect.Parameter.empty
           for parameter in parameters):
        return _red(name, "all seven parameters must be required")
    return _pass(name)


def blackbox_keyword_invocation_rejected_by_python() -> Result:
    name = "blackbox.keyword_invocation_rejected"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    try:
        candidate(
            operationBytes=b"bad",
            handoffBytes=b"{}",
            authorityPolicyFd=-1,
            authorityStoreFd=-1,
            candidateArchiveFd=-1,
            provenanceBundleFd=-1,
            trustedClockFd=-1,
        )
    except TypeError:
        return _pass(name)
    except Exception as exc:
        return _red(name, f"body ran before keyword rejection: {type(exc).__name__}")
    return _red(name, "keyword invocation was accepted")


def blackbox_api_has_no_private_key_injection() -> Result:
    name = "blackbox.no_private_key_injection"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    parameters = inspect.signature(candidate).parameters
    forbidden_names = {
        "signing_seeds", "signingSeeds", "seed", "seeds", "privateKey",
        "privateKeys", "hsm", "hsmHandle", "signer", "signerCallback",
        "path", "environment", "kwargs",
    }
    if forbidden_names.intersection(parameters):
        return _red(name, "forbidden signer/path/environment parameter exposed")
    try:
        candidate(b"bad", b"{}", -1, -2, -3, -4, -5, b"extra-private-input")
    except TypeError:
        return _pass(name)
    except Exception as exc:
        return _red(name, f"eighth argument reached body: {type(exc).__name__}")
    return _red(name, "eighth private-input argument was accepted")


def blackbox_invalid_operation_rejects() -> Result:
    name = "blackbox.invalid_operation_rejects"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    return _expect_rejection(
        name, lambda: candidate(b"unknown-operation", b"{}", -1, -2, -3, -4, -5)
    )


def blackbox_noncanonical_handoff_rejects() -> Result:
    name = "blackbox.noncanonical_handoff_rejects"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    return _expect_rejection(
        name,
        lambda: candidate(
            OPERATIONS[0], b'{ "schema" : "wrong" }', -1, -2, -3, -4, -5
        ),
    )


def blackbox_duplicate_fds_reject() -> Result:
    name = "blackbox.duplicate_fds_reject"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    return _expect_rejection(
        name, lambda: candidate(OPERATIONS[0], b"{}", 3, 3, 3, 3, 3)
    )


def _open_readonly_regular(payload: bytes) -> tuple[tempfile.TemporaryFile, int]:
    handle = tempfile.TemporaryFile()
    handle.write(payload)
    handle.flush()
    handle.seek(0)
    return handle, handle.fileno()


def blackbox_regular_file_store_rejects() -> Result:
    name = "blackbox.regular_file_store_rejects"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    handles: list[tempfile.TemporaryFile] = []
    try:
        for payload in (b"policy", b"store", b"archive", b"provenance", b"clock"):
            handle, _ = _open_readonly_regular(payload)
            handles.append(handle)
        fds = [handle.fileno() for handle in handles]
        return _expect_rejection(
            name,
            lambda: candidate(OPERATIONS[0], b"{}", *fds),
        )
    finally:
        for handle in handles:
            handle.close()


def blackbox_sock_stream_store_rejects() -> Result:
    name = "blackbox.sock_stream_store_rejects"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    handles: list[tempfile.TemporaryFile] = []
    try:
        for payload in (b"policy", b"archive", b"provenance", b"clock"):
            handle, _ = _open_readonly_regular(payload)
            handles.append(handle)
        return _expect_rejection(
            name,
            lambda: candidate(
                OPERATIONS[0], b"{}",
                handles[0].fileno(), left.fileno(), handles[1].fileno(),
                handles[2].fileno(), handles[3].fileno(),
            ),
        )
    finally:
        left.close()
        right.close()
        for handle in handles:
            handle.close()


QUALIFIED_TIMEOUT_SECONDS = 300.0


def _strict_lower_hex(
    value: Any, *, minimum_bytes: int, maximum_bytes: int, where: str
) -> bytes:
    if (type(value) is not str or not value or len(value) % 2 != 0
            or value.lower() != value
            or any(character not in "0123456789abcdef" for character in value)):
        raise ValueError(f"{where} must be nonempty lowercase even hex")
    decoded_size = len(value) // 2
    if not minimum_bytes <= decoded_size <= maximum_bytes:
        raise ValueError(f"{where} decoded size out of bounds")
    return bytes.fromhex(value)


def blackbox_qualified_production_acceptance() -> Result:
    """Run the one-shot qualified path under a hard five-minute deadline."""
    name = "blackbox.qualified_production_acceptance"

    def _deadline(_signum: int, _frame: Any) -> None:
        raise TimeoutError(
            f"qualified integration exceeded {int(QUALIFIED_TIMEOUT_SECONDS)} seconds"
        )

    started = time.monotonic()
    previous = signal.signal(signal.SIGALRM, _deadline)
    previous_timer = signal.setitimer(
        signal.ITIMER_REAL, QUALIFIED_TIMEOUT_SECONDS
    )
    try:
        try:
            return _blackbox_qualified_production_acceptance_inner()
        except TimeoutError as exc:
            return _red(name, str(exc))
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0.0)
        signal.signal(signal.SIGALRM, previous)
        if previous_timer != (0.0, 0.0):
            elapsed = time.monotonic() - started
            remaining = max(0.000001, previous_timer[0] - elapsed)
            signal.setitimer(signal.ITIMER_REAL, remaining, previous_timer[1])


def _blackbox_qualified_production_acceptance_inner() -> Result:
    """Require real eligible-host success when a ceremony supplies stdin.

    The optional ``--qualified-input-stdin`` mode is a test-harness transport,
    not a production API switch. The authority-controlled launcher writes one
    canonical manifest to stdin, then invokes this process with exactly stdio
    plus the five signed-handoff channel FDs. The manifest FD does not survive
    into the adapter call. Without that candidate-external input this case
    remains RED; host ineligibility is never converted to pass.
    """
    name = "blackbox.qualified_production_acceptance"
    candidate, absent = _api_required(name)
    if absent is not None:
        return absent
    assert candidate is not None
    if sys.argv[1:] != ["--qualified-input-stdin"]:
        return _red(name, "QUALIFIED-INTEGRATION-INPUT-ABSENT")
    try:
        manifest_bytes = sys.stdin.buffer.read(1_048_577)
        if not 1 <= len(manifest_bytes) <= 1_048_576:
            return _red(name, "qualified manifest size out of bounds")
        manifest = _BTO.decode_canonical_pf_jcs(manifest_bytes)
    except Exception as exc:
        return _red(name, f"qualified manifest invalid: {type(exc).__name__}")
    expected_fields = {
        "schema", "operationBytesHex", "handoffBytesHex",
        "authorityPolicyFd", "authorityStoreFd", "candidateArchiveFd",
        "provenanceBundleFd", "trustedClockFd", "expectedAcceptanceDigest",
    }
    if not isinstance(manifest, dict) or set(manifest) != expected_fields:
        return _red(name, "qualified manifest is not the exact closed object")
    if manifest.get("schema") != (
        "proof-forge.task-qualification-v2-qualified-test-input.v1"
    ):
        return _red(name, "qualified manifest schema mismatch")
    try:
        operation_bytes = _strict_lower_hex(
            manifest["operationBytesHex"], minimum_bytes=1,
            maximum_bytes=64, where="operationBytesHex",
        )
        if operation_bytes not in OPERATIONS:
            return _red(name, "qualified operationBytes is not an accepted operation")
        handoff_bytes = _strict_lower_hex(
            manifest["handoffBytesHex"], minimum_bytes=1,
            maximum_bytes=4_194_304, where="handoffBytesHex",
        )
        handoff_wire = _BTO.decode_canonical_pf_jcs(handoff_bytes)
        if _canonical(handoff_wire) != handoff_bytes:
            return _red(name, "qualified handoff bytes are not canonical PF-JCS")
        fds = tuple(
            manifest[field]
            for field in (
                "authorityPolicyFd", "authorityStoreFd", "candidateArchiveFd",
                "provenanceBundleFd", "trustedClockFd",
            )
        )
        if (any(type(fd) is not int or fd < 0 for fd in fds)
                or len(set(fds)) != 5):
            return _red(name, "qualified channel FDs are invalid/non-distinct")
        expected_channels = dict(zip(
            ("authorityPolicyFd", "authorityStoreFd", "candidateArchiveFd",
             "provenanceBundleFd", "trustedClockFd"),
            fds,
        ))
        if (not isinstance(handoff_wire, dict)
                or handoff_wire.get("schema")
                != "proof-forge.task-qualification-protected-handoff.v1"
                or handoff_wire.get("operation") != operation_bytes.decode("ascii")
                or handoff_wire.get("channels") != expected_channels):
            return _red(name, "qualified manifest does not match signed handoff tuple")
        expected_digest = manifest["expectedAcceptanceDigest"]
        if type(expected_digest) is not str or not expected_digest.startswith("sha256:"):
            return _red(name, "qualified expected acceptance digest is invalid")
        _strict_lower_hex(
            expected_digest[7:], minimum_bytes=32, maximum_bytes=32,
            where="expectedAcceptanceDigest",
        )
        policy_bytes = os.pread(fds[0], 4_194_305, 0)
        if not 1 <= len(policy_bytes) <= 4_194_304:
            return _red(name, "qualified authority policy size out of bounds")
        policy, _policy_ref = _BTO.parse_bootstrap_authority_policy(policy_bytes)
    except (KeyError, TypeError, ValueError, OSError) as exc:
        return _red(name, f"qualified manifest field invalid: {type(exc).__name__}")
    except Exception as exc:
        return _red(name, f"qualified authority policy invalid: {type(exc).__name__}")

    try:
        value = candidate(operation_bytes, handoff_bytes, *fds)
    except Exception as exc:
        return _red(name, f"qualified invocation rejected: {type(exc).__name__}")
    if _is_rejection(value):
        return _red(name, "qualified invocation returned Rejected")
    try:
        if isinstance(value, bytes):
            wire = _BTO.decode_canonical_pf_jcs(value)
            exact_bytes = value
        else:
            encoder = getattr(_ADAPTER, "protected_acceptance_to_wire", None)
            if not callable(encoder):
                return _red(name, "acceptance result has no canonical encoder")
            wire = encoder(value)
            exact_bytes = _canonical(wire)
        expected_acceptance_fields = [
            "schema", "id", "version", "authorityClass", "operation",
            "pureProjectionDigest", "bundleDigest", "subjectDigest",
            "preCloseCandidate", "closeoutCandidate", "trustedVerificationInstant",
            "adapter", "snapshotParser", "productionProfileDigest",
            "productionProfilePin", "ledgerProjectionDigest",
            "governanceCompletionDigest", "provenanceBundleDigest",
            "provenanceRoles", "signatures",
        ]
        # PF-JCS sorts object keys bytewise; after canonical decode the exact
        # accepted field manifest must therefore appear in that canonical
        # order, not in the schema prose's presentation order.
        if list(wire) != sorted(expected_acceptance_fields):
            return _red(name, "qualified acceptance field manifest/order mismatch")
        if (wire.get("schema") != ACCEPTANCE_SCHEMA
                or wire.get("version") != "1.0.0"
                or wire.get("authorityClass") != "production-candidate-bound"):
            return _red(name, "qualified result lacks exact production identity")
        signatures = wire.get("signatures")
        if (not isinstance(signatures, list) or len(signatures) != 3
                or [item.get("keyId") for item in signatures]
                != sorted(item.get("keyId") for item in signatures)):
            return _red(name, "qualified acceptance lacks exact sorted three-signature set")
        unsigned = dict(wire)
        unsigned.pop("signatures")
        statement = _domain_digest(ACCEPTANCE_STATEMENT_DOMAIN, unsigned)
        message = ACCEPTANCE_SIGNATURE_DOMAIN + b"\x00" + statement
        principals = {principal.keyId: principal for principal in policy.principals}
        covered_roles: set[str] = set()
        covered_principals: set[str] = set()
        for item in signatures:
            if (not isinstance(item, dict)
                    or set(item) != {"keyId", "algorithm", "signature"}
                    or item.get("algorithm") != "ed25519"):
                return _red(name, "qualified acceptance signature wire invalid")
            principal = principals.get(item["keyId"])
            if principal is None or principal.principalId in covered_principals:
                return _red(name, "qualified acceptance signer is unknown/reused")
            signature = _strict_lower_hex(
                item["signature"], minimum_bytes=64, maximum_bytes=64,
                where="acceptance.signature",
            )
            if not _BTO.verify_ed25519(principal.publicKey, message, signature):
                return _red(name, "qualified acceptance role signature invalid")
            covered_principals.add(principal.principalId)
            covered_roles.update(principal.roles)
        if not {"architecture", "quality", "security"}.issubset(covered_roles):
            return _red(name, "qualified acceptance does not cover A+Q+S")
        actual_digest = _digest_wire(
            hashlib.sha256(
                ACCEPTANCE_FULL_DOMAIN + b"\x00" + exact_bytes
            ).digest()
        )
    except Exception as exc:
        return _red(name, f"qualified acceptance encoding failed: {type(exc).__name__}")
    if actual_digest != expected_digest:
        return _red(name, "qualified acceptance digest mismatch")
    return _pass(name, "eligible-host acceptance and A+Q+S quorum independently verified")


KAT_TESTS: tuple[Callable[[], Result], ...] = (
    kat_synthetic_label_is_explicit,
    kat_corrected_capability_reference_matrix,
    kat_eligible_kernel_capability_transition,
    kat_six_frame_schemas_are_exact,
    kat_packet_round_trip,
    kat_packet_rejects_zero,
    kat_packet_rejects_length_mismatch,
    kat_packet_rejects_two_frames,
    kat_packet_rejects_truncation_flags,
    kat_server_signature_domain,
    kat_unsigned_acceptance_manifest,
    kat_acceptance_statement_removes_signatures,
    kat_acceptance_role_signature_arithmetic,
    kat_docs_check_does_not_call_protected_api,
    kat_qualified_hex_grammar_is_strict,
    kat_qualified_deadline_restores_signal_state,
)

BLACKBOX_TESTS: tuple[Callable[[], Result], ...] = (
    blackbox_api_exists,
    blackbox_api_signature_exact,
    blackbox_keyword_invocation_rejected_by_python,
    blackbox_api_has_no_private_key_injection,
    blackbox_invalid_operation_rejects,
    blackbox_noncanonical_handoff_rejects,
    blackbox_duplicate_fds_reject,
    blackbox_regular_file_store_rejects,
    blackbox_sock_stream_store_rejects,
    blackbox_qualified_production_acceptance,
)


def _run(tests: Iterable[Callable[[], Result]]) -> list[Result]:
    results: list[Result] = []
    for test in tests:
        try:
            results.append(test())
        except Exception as exc:
            results.append(_red(test.__name__, f"CASE-ERROR {type(exc).__name__}: {exc}"))
    return results


def main() -> int:
    kat_results = _run(KAT_TESTS)
    if any(not result.passed for result in kat_results):
        print("task_qualification_authority_store_v2 self-test: KAT-PREFLIGHT-FAIL")
        for result in kat_results:
            print(result)
        return 1

    blackbox_results = _run(BLACKBOX_TESTS)
    all_results = kat_results + blackbox_results
    passed = sum(result.passed for result in all_results)
    red = len(all_results) - passed
    print(
        "task_qualification_authority_store_v2 self-test: "
        f"{passed}/{len(all_results)} passed, {red} RED"
    )
    print(f"protocol vectors: {SYNTHETIC_PROTOCOL_LABEL}")
    if _entrypoint() is None:
        print(
            "production black-box status: "
            "task_qualification_protected_adapter.protect_taskqualification_v1 "
            f"not callable ({API_ABSENT})"
        )
    for result in all_results:
        print(result)
    return 0 if red == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
