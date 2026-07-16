#!/usr/bin/env python3
"""Launch one development sandbox stage with closed FDs and fixed receipts.

The launcher cleans the dedicated process group before reaping its leader.  A
child can still create a new session on macOS, so this is not formal orphan or
fork-bomb containment; formal qualification needs a stronger host runner.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import select
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, NoReturn, Sequence


STAGES = ("materialize", "core", "evm-runtime")
INVOCATION_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,47}\Z")
MAX_STREAM_BYTES = 4 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
MAX_POLICY_BYTES = 128 * 1024
MAX_CONTEXT_BYTES = 1024 * 1024
MAX_RECEIPT_BYTES = 1024 * 1024
MAX_EXECUTABLE_BYTES = 256 * 1024 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_ARGUMENT_BYTES = 64 * 1024
MAX_ENVIRONMENT_VALUE_BYTES = 64 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_DURATION_MS = 86_400_000
RUN_CONTEXT_SCHEMA = "proof-forge.clean-room-run-context.v1"
INVOCATION_CONTEXT_SCHEMA = "proof-forge.sandbox-invocation-context.v1"
INVOCATION_RECEIPT_SCHEMA = "proof-forge.sandbox-invocation.v1"
RUN_CONTEXT_DOMAIN = b"pf.clean-room-run-context.v1\x00"
INVOCATION_CONTEXT_DOMAIN = b"pf.sandbox.invocation-context.v1\x00"
ARGV_DOMAIN = b"pf.sandbox.argv.v1\x00"
ENVIRONMENT_DOMAIN = b"pf.sandbox.environment.v1\x00"
SANDBOX_ENGINE = Path("/usr/bin/sandbox-exec")
STAGE_TIMEOUT_SECONDS = {"materialize": 3600, "core": 3600, "evm-runtime": 900}
SYSCTL_RULE = '(allow sysctl-read (sysctl-name "hw.ncpu" "hw.pagesize_compat"))'
ALLOW_DEFAULT_RE = re.compile(r"\(\s*allow\s+default\b")
PROCESS_EXEC_RE = re.compile(r"\(\s*allow\s+process-exec\b")
BARE_PROCESS_EXEC_RE = re.compile(r"\(\s*allow\s+process-exec\s*\)")
PROCESS_WILDCARD_RE = re.compile(r"\bprocess(?:-exec|-info)?\s*\*")
NETWORK_WILDCARD_RE = re.compile(r"\bnetwork\s*\*")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
GIT_OBJECT_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
RUN_ID_RE = re.compile(r"RUN-[0-9a-f]{32}\Z")
SAFE_ID_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?\Z")
TASK_ID_RE = re.compile(r"TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*\Z")
TEST_ID_RE = re.compile(r"TST-[A-Z0-9]+(?:-[A-Z0-9]+)*\Z")
SEMVER_RE = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")
ENVIRONMENT_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,254}\Z")


class LaunchError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> NoReturn:
    raise LaunchError(code, message)


@dataclass(frozen=True)
class FileObservation:
    path: Path
    metadata: tuple[int, int, int, int, int, int, int, int]
    sha256: str


@dataclass(frozen=True)
class ReceiptContexts:
    run_binding_sha256: str
    invocation_binding_sha256: str
    run_observation: FileObservation
    invocation_observation: FileObservation


@dataclass(frozen=True)
class PublishedReceipt:
    name: str
    metadata: tuple[int, int, int, int, int, int, int, int]
    sha256: str


@dataclass(frozen=True)
class InvocationReservation:
    name: str
    descriptor: int
    metadata: tuple[int, int, int, int, int, int, int, int]
    token_sha256: str


def stable_metadata(
    metadata: os.stat_result,
) -> tuple[int, int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_nlink,
        stat.S_IMODE(metadata.st_mode),
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _require_json_key(key: object, where: str) -> str:
    if not isinstance(key, str):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains a non-string key")
    if (
        not key
        or len(key) > 256
        or any(ord(char) < 0x21 or ord(char) > 0x7E for char in key)
    ):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains an invalid object key")
    return key


def _parse_safe_int(text: str) -> int:
    digits = text[1:] if text.startswith("-") else text
    if len(digits) > 16:
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT", "JSON integer exceeds the lexical digit limit"
        )
    value = int(text, 10)
    if abs(value) > MAX_SAFE_INTEGER:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "JSON integer exceeds the safe range")
    return value


def _reject_json_number(text: str) -> NoReturn:
    fail("PF-SANDBOX-LAUNCH-CONTEXT", f"forbidden JSON number: {text}")


def _object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for raw_key, value in pairs:
        key = _require_json_key(raw_key, "JSON")
        if key in result:
            fail("PF-SANDBOX-LAUNCH-CONTEXT", f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_json_tree(value: object) -> None:
    nodes = 0
    stack: list[tuple[object, int, str]] = [(value, 0, "$")]
    while stack:
        current, depth, where = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES or depth > MAX_JSON_DEPTH:
            fail("PF-SANDBOX-LAUNCH-CONTEXT", "JSON resource limit exceeded")
        if current is None or type(current) is bool:
            continue
        if type(current) is int:
            if abs(current) > MAX_SAFE_INTEGER:
                fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains an unsafe integer")
            continue
        if isinstance(current, float):
            fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains a float")
        if isinstance(current, str):
            if "\x00" in current or any(
                0xD800 <= ord(char) <= 0xDFFF for char in current
            ):
                fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains invalid Unicode")
            if len(current.encode("utf-8")) > MAX_STRING_BYTES:
                fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} exceeds the string limit")
            continue
        if isinstance(current, list):
            for index in range(len(current) - 1, -1, -1):
                stack.append((current[index], depth + 1, f"{where}[{index}]"))
            continue
        if isinstance(current, dict):
            for key, item in current.items():
                _require_json_key(key, where)
                stack.append((item, depth + 1, f"{where}.{key}"))
            continue
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} contains a non-JSON value")


def canonical_json_bytes(value: object) -> bytes:
    validate_json_tree(value)
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            check_circular=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError, RecursionError) as error:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"cannot encode canonical JSON: {error}")


def decode_canonical_json(data: bytes, label: str) -> object:
    if len(data) > MAX_CONTEXT_BYTES:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{label} exceeds {MAX_CONTEXT_BYTES} bytes")
    if data.startswith(b"\xef\xbb\xbf"):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{label} contains a UTF-8 BOM")
    try:
        text = data.decode("utf-8", errors="strict")
        value = json.loads(
            text,
            object_pairs_hook=_object_pairs,
            parse_int=_parse_safe_int,
            parse_float=_reject_json_number,
            parse_constant=_reject_json_number,
        )
    except LaunchError:
        raise
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as error:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"invalid {label}: {error}")
    validate_json_tree(value)
    if canonical_json_bytes(value) != data:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{label} is not canonical PF JSON")
    return value


def require_keys(value: object, required: set[str], where: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be an object")
    actual = set(value)
    if actual != required:
        missing = ",".join(sorted(required - actual))
        unknown = ",".join(sorted(actual - required))
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            f"{where} field mismatch missing={missing or '-'} unknown={unknown or '-'}",
        )
    return value


def require_string(
    value: object,
    where: str,
    *,
    maximum: int = MAX_STRING_BYTES,
    allow_empty: bool = False,
) -> str:
    if not isinstance(value, str) or (not allow_empty and not value) or "\x00" in value:
        qualifier = "a string" if allow_empty else "a non-empty string"
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be {qualifier}")
    if len(value.encode("utf-8")) > maximum:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} exceeds {maximum} bytes")
    return value


def require_text(value: object, where: str, *, maximum: int = MAX_STRING_BYTES) -> str:
    return require_string(value, where, maximum=maximum)


def require_pattern(value: object, pattern: re.Pattern[str], where: str) -> str:
    text = require_text(value, where)
    if not text.isascii() or pattern.fullmatch(text) is None:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} has an invalid format")
    return text


def require_sha256(value: object, where: str) -> str:
    return require_pattern(value, SHA256_RE, where)


def require_safe_id(value: object, where: str) -> str:
    return require_pattern(value, SAFE_ID_RE, where)


def require_bool(value: object, where: str) -> bool:
    if type(value) is not bool:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be a boolean")
    return value


def require_int(value: object, where: str, minimum: int, maximum: int) -> int:
    if type(value) is not int or value < minimum or value > maximum:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be in [{minimum},{maximum}]")
    return value


def validate_bindings(value: object, where: str) -> None:
    if not isinstance(value, list):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be an array")
    names: list[str] = []
    for index, raw in enumerate(value):
        item_where = f"{where}[{index}]"
        item = require_keys(raw, {"name", "type", "value"}, item_where)
        name = require_safe_id(item["name"], f"{item_where}.name")
        kind = require_text(item["type"], f"{item_where}.type")
        if kind == "string":
            require_string(item["value"], f"{item_where}.value", allow_empty=True)
        elif kind == "integer":
            require_int(
                item["value"],
                f"{item_where}.value",
                -MAX_SAFE_INTEGER,
                MAX_SAFE_INTEGER,
            )
        elif kind == "sha256":
            require_sha256(item["value"], f"{item_where}.value")
        else:
            fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{item_where}.type is unsupported")
        names.append(name)
    if names != sorted(names) or len(names) != len(set(names)):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", f"{where} must be sorted and unique")


def reject_symlink_components(path: Path, label: str) -> None:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            metadata = os.lstat(current)
        except OSError as error:
            fail("PF-SANDBOX-LAUNCH-PATH", f"cannot inspect {label}: {error.strerror}")
        if stat.S_ISLNK(metadata.st_mode):
            fail("PF-SANDBOX-LAUNCH-PATH", f"{label} contains a symbolic link")


def canonical_existing(path_text: str, label: str, *, kind: str) -> Path:
    if not path_text or "\x00" in path_text:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} is empty or contains NUL")
    path = Path(path_text)
    if not path.is_absolute() or os.path.normpath(path_text) != path_text:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be absolute and normalized")
    reject_symlink_components(path, label)
    if Path(os.path.realpath(path)) != path:
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must already be canonical")
    metadata = os.stat(path, follow_symlinks=False)
    if kind == "dir" and not stat.S_ISDIR(metadata.st_mode):
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be a directory")
    if kind == "file" and not stat.S_ISREG(metadata.st_mode):
        fail("PF-SANDBOX-LAUNCH-PATH", f"{label} must be a regular file")
    return path


def observe_regular_file(
    path: Path,
    label: str,
    *,
    maximum: int,
    required_mode: int | None = None,
    required_owner: int | None = None,
    executable: bool = False,
    capture: bool = True,
    before_path_check: Callable[[], None] | None = None,
) -> tuple[FileObservation, bytes]:
    canonical = canonical_existing(str(path), label, kind="file")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(canonical, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            fail(
                "PF-SANDBOX-LAUNCH-OBSERVATION",
                f"{label} must be regular and single-link",
            )
        if required_owner is not None and before.st_uid != required_owner:
            fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} has the wrong owner")
        if required_mode is not None and stat.S_IMODE(before.st_mode) != required_mode:
            fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} has the wrong mode")
        if executable and not os.access(canonical, os.X_OK):
            fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} is not executable")
        if before.st_size < 0 or before.st_size > maximum:
            fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} exceeds {maximum} bytes")
        remaining = before.st_size
        chunks: list[bytes] = []
        digest = hashlib.sha256()
        read_size = 0
        while remaining:
            chunk = os.read(descriptor, min(remaining, 64 * 1024))
            if not chunk:
                break
            digest.update(chunk)
            read_size += len(chunk)
            if capture:
                chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks) if capture else b""
        after = os.fstat(descriptor)
        if read_size != before.st_size or stable_metadata(before) != stable_metadata(
            after
        ):
            fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} changed while being read")
        if before_path_check is not None:
            before_path_check()
        try:
            pathname = os.stat(canonical, follow_symlinks=False)
        except OSError as error:
            fail(
                "PF-SANDBOX-LAUNCH-OBSERVATION",
                f"{label} pathname changed while being read: {error.strerror}",
            )
        if stable_metadata(after) != stable_metadata(pathname):
            fail(
                "PF-SANDBOX-LAUNCH-OBSERVATION",
                f"{label} pathname changed while being read",
            )
    finally:
        os.close(descriptor)
    observation = FileObservation(
        path=canonical,
        metadata=stable_metadata(before),
        sha256=digest.hexdigest(),
    )
    return observation, data


def verify_file_observation(observation: FileObservation, label: str) -> None:
    current, _ = observe_regular_file(
        observation.path,
        label,
        maximum=MAX_EXECUTABLE_BYTES,
        capture=False,
    )
    if current != observation:
        fail("PF-SANDBOX-LAUNCH-OBSERVATION", f"{label} changed after observation")


def validate_run_context(value: object) -> dict[str, object]:
    root = require_keys(
        value,
        {
            "schema",
            "runId",
            "runRoot",
            "catalog",
            "gate",
            "candidate",
            "host",
            "bindings",
        },
        "run context",
    )
    if require_text(root["schema"], "run context.schema") != RUN_CONTEXT_SCHEMA:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "unsupported run context schema")
    require_pattern(root["runId"], RUN_ID_RE, "run context.runId")
    run_root = require_text(root["runRoot"], "run context.runRoot", maximum=4096)
    if not run_root.startswith("/") or os.path.normpath(run_root) != run_root:
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            "run context.runRoot must be normalized absolute",
        )
    catalog = require_keys(
        root["catalog"],
        {"schema", "id", "version", "contentSha256", "catalogDigest"},
        "run context.catalog",
    )
    if (
        require_text(catalog["schema"], "run context.catalog.schema")
        != "proof-forge.gate-catalog.v1"
    ):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "unsupported gate catalog schema")
    require_safe_id(catalog["id"], "run context.catalog.id")
    require_pattern(catalog["version"], SEMVER_RE, "run context.catalog.version")
    require_sha256(catalog["contentSha256"], "run context.catalog.contentSha256")
    require_sha256(catalog["catalogDigest"], "run context.catalog.catalogDigest")
    gate = require_keys(root["gate"], {"id", "taskId", "testIds"}, "run context.gate")
    require_safe_id(gate["id"], "run context.gate.id")
    require_pattern(gate["taskId"], TASK_ID_RE, "run context.gate.taskId")
    test_ids = gate["testIds"]
    if not isinstance(test_ids, list) or not test_ids:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "run context.gate.testIds must be non-empty")
    parsed_test_ids = [
        require_pattern(item, TEST_ID_RE, f"run context.gate.testIds[{index}]")
        for index, item in enumerate(test_ids)
    ]
    if parsed_test_ids != sorted(parsed_test_ids) or len(parsed_test_ids) != len(
        set(parsed_test_ids)
    ):
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            "run context.gate.testIds must be sorted and unique",
        )
    candidate = require_keys(
        root["candidate"],
        {"commit", "treeObjectId", "archiveSha256"},
        "run context.candidate",
    )
    require_pattern(candidate["commit"], GIT_OBJECT_RE, "run context.candidate.commit")
    require_pattern(
        candidate["treeObjectId"], GIT_OBJECT_RE, "run context.candidate.treeObjectId"
    )
    require_sha256(candidate["archiveSha256"], "run context.candidate.archiveSha256")
    host = require_keys(
        root["host"], {"profileId", "observationSha256"}, "run context.host"
    )
    require_safe_id(host["profileId"], "run context.host.profileId")
    require_sha256(host["observationSha256"], "run context.host.observationSha256")
    validate_bindings(root["bindings"], "run context.bindings")
    return root


def validate_invocation_context(value: object) -> dict[str, object]:
    root = require_keys(
        value,
        {"schema", "runBindingSha256", "stage", "invocation", "bindings"},
        "invocation context",
    )
    if (
        require_text(root["schema"], "invocation context.schema")
        != INVOCATION_CONTEXT_SCHEMA
    ):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "unsupported invocation context schema")
    require_sha256(root["runBindingSha256"], "invocation context.runBindingSha256")
    if require_text(root["stage"], "invocation context.stage") not in STAGES:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "invocation context.stage is unsupported")
    validate_invocation(
        require_text(root["invocation"], "invocation context.invocation")
    )
    validate_bindings(root["bindings"], "invocation context.bindings")
    return root


def load_receipt_contexts(
    run_context_text: str | None,
    invocation_context_text: str | None,
    *,
    stage: str,
    invocation: str,
    temp_root: Path,
) -> ReceiptContexts | None:
    if (run_context_text is None) != (invocation_context_text is None):
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            "--receipt-run-context and --receipt-invocation-context are all-or-none",
        )
    if run_context_text is None or invocation_context_text is None:
        return None
    contexts_root = canonical_existing(
        str(temp_root / "contexts"), "contexts root", kind="dir"
    )
    require_private_directory(contexts_root, "contexts root")
    expected_run = temp_root / "run-context.json"
    expected_invocation = contexts_root / f"sandbox-{stage}-{invocation}.json"
    if run_context_text != str(expected_run) or invocation_context_text != str(
        expected_invocation
    ):
        fail(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            "receipt context path does not match the fixed layout",
        )
    run_observation, run_bytes = observe_regular_file(
        expected_run,
        "run context",
        maximum=MAX_CONTEXT_BYTES,
        required_mode=0o400,
        required_owner=os.geteuid(),
    )
    invocation_observation, invocation_bytes = observe_regular_file(
        expected_invocation,
        "invocation context",
        maximum=MAX_CONTEXT_BYTES,
        required_mode=0o400,
        required_owner=os.geteuid(),
    )
    run = validate_run_context(decode_canonical_json(run_bytes, "run context"))
    invocation_record = validate_invocation_context(
        decode_canonical_json(invocation_bytes, "invocation context")
    )
    run_digest = hashlib.sha256(RUN_CONTEXT_DOMAIN + run_bytes).hexdigest()
    invocation_digest = hashlib.sha256(
        INVOCATION_CONTEXT_DOMAIN + invocation_bytes
    ).hexdigest()
    if run["runRoot"] != str(temp_root):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "run context root does not match --temp-root")
    if invocation_record["runBindingSha256"] != run_digest:
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "invocation context run binding mismatch")
    if (
        invocation_record["stage"] != stage
        or invocation_record["invocation"] != invocation
    ):
        fail("PF-SANDBOX-LAUNCH-CONTEXT", "invocation context identity mismatch")
    return ReceiptContexts(
        run_binding_sha256=run_digest,
        invocation_binding_sha256=invocation_digest,
        run_observation=run_observation,
        invocation_observation=invocation_observation,
    )


def require_direct_xcode_python() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail("PF-SANDBOX-LAUNCH-PYTHON", "launcher requires direct Xcode Python -I -S")
    executable = canonical_existing(sys.executable, "Python executable", kind="file")
    app_roots = [
        parent for parent in executable.parents if parent.name.endswith(".app")
    ]
    if len(app_roots) != 1 or any(
        parent.name == "Python.app" for parent in executable.parents
    ):
        fail("PF-SANDBOX-LAUNCH-PYTHON", "launcher requires the direct Xcode Python")
    developer = app_roots[0] / "Contents" / "Developer"
    version = f"{sys.version_info.major}.{sys.version_info.minor}"
    expected = (
        developer
        / "Library"
        / "Frameworks"
        / "Python3.framework"
        / "Versions"
        / version
        / "bin"
        / f"python{version}"
    )
    if executable != expected or not os.access(executable, os.X_OK):
        fail("PF-SANDBOX-LAUNCH-PYTHON", "unexpected Xcode Python executable path")


def require_private_directory(path: Path, label: str) -> None:
    metadata = os.stat(path, follow_symlinks=False)
    if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
        fail("PF-SANDBOX-LAUNCH-LAYOUT", f"{label} must be current-user 0700")


def validate_layout(
    stage: str, temp_text: str
) -> tuple[Path, Path, Path, bytes, tuple[int, int, int, int]]:
    temp_root = canonical_existing(temp_text, "TEMP_ROOT", kind="dir")
    require_private_directory(temp_root, "TEMP_ROOT")
    work = canonical_existing(str(temp_root / "work"), "work root", kind="dir")
    policies = canonical_existing(
        str(temp_root / "policies"), "policies root", kind="dir"
    )
    require_private_directory(work, "work root")
    require_private_directory(policies, "policies root")
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor = os.open(policies, directory_flags)
    try:
        identity = directory_identity(os.fstat(descriptor))
        verify_open_directory(descriptor, policies, identity, "policies root")
        _, policy_bytes = observe_regular_file(
            policies / f"{stage}.sb",
            f"{stage} policy",
            maximum=MAX_POLICY_BYTES,
            required_mode=0o400,
            required_owner=os.geteuid(),
        )
        verify_open_directory(descriptor, policies, identity, "policies root")
    finally:
        os.close(descriptor)
    return temp_root, work, policies, policy_bytes, identity


def validate_invocation(value: str) -> str:
    if INVOCATION_RE.fullmatch(value) is None:
        fail("PF-SANDBOX-LAUNCH-ID", "invocation must match [a-z0-9][a-z0-9-]{0,47}")
    return value


def validate_policy_snapshot(policy_bytes: bytes, stage: str, port: int | None) -> None:
    try:
        policy = policy_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
    if "\x00" in policy:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains NUL")
    if policy.count("(version 1)") != 1 or policy.count("(deny default)") != 1:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be version 1 deny-default")
    if (
        ALLOW_DEFAULT_RE.search(policy)
        or len(PROCESS_EXEC_RE.findall(policy)) != 1
        or BARE_PROCESS_EXEC_RE.search(policy)
    ):
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy has unsafe default/process execution")
    if PROCESS_WILDCARD_RE.search(policy) or NETWORK_WILDCARD_RE.search(policy):
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains a wildcard operation")
    if policy.count("sysctl-read") != 1 or policy.count(SYSCTL_RULE) != 1:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy has an unlocked sysctl allowance")
    for forbidden in (
        "mach-lookup",
        "ipc-posix",
        "dynamic-code-generation",
        '(subpath "/")',
        "/dev/fd",
    ):
        if forbidden in policy:
            fail("PF-SANDBOX-LAUNCH-POLICY", f"policy contains forbidden {forbidden}")
    if stage != "evm-runtime":
        if "network-" in policy:
            fail("PF-SANDBOX-LAUNCH-POLICY", f"{stage} must deny all network access")
        return
    if type(port) is not int:
        fail("PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires an exact local port")
    inbound = f'(allow network-inbound (local ip "localhost:{port}"))'
    outbound = f'(allow network-outbound (remote ip "localhost:{port}"))'
    if (
        policy.count(inbound) != 1
        or policy.count(outbound) != 1
        or policy.count("network-") != 2
    ):
        fail("PF-SANDBOX-LAUNCH-PORT", "runtime policy local-port rules mismatch")


def xcode_tool_paths() -> tuple[Path, Path]:
    python = Path(sys.executable)
    app_root = next(parent for parent in python.parents if parent.name.endswith(".app"))
    developer = app_root / "Contents" / "Developer"
    git = canonical_existing(
        str(developer / "usr" / "bin" / "git"), "Xcode Git", kind="file"
    )
    return python, git


def derive_environment(
    stage: str,
    temp_root: Path,
    asset_cache: str | None,
    runtime_port: int | None,
) -> dict[str, str]:
    common = {
        "HOME": str(temp_root / "home"),
        "LC_ALL": "C",
        "PYTHONDONTWRITEBYTECODE": "1",
        "TMPDIR": str(temp_root / "work"),
        "TZ": "UTC",
    }
    xcode_python, xcode_git = xcode_tool_paths()
    if stage == "materialize":
        if asset_cache is None:
            fail("PF-SANDBOX-LAUNCH-ENV", "materialize requires --asset-cache")
        cache = canonical_existing(asset_cache, "ASSET_CACHE", kind="dir")
        if (
            cache == temp_root
            or cache in temp_root.parents
            or temp_root in cache.parents
        ):
            fail("PF-SANDBOX-LAUNCH-ENV", "ASSET_CACHE must be disjoint from TEMP_ROOT")
        cache_metadata = os.stat(cache, follow_symlinks=False)
        if (
            cache_metadata.st_uid != os.geteuid()
            or stat.S_IMODE(cache_metadata.st_mode) & 0o022
        ):
            fail(
                "PF-SANDBOX-LAUNCH-ENV",
                "ASSET_CACHE must be owned and not writable by peers",
            )
        cache_index = canonical_existing(
            str(cache / "sha256"), "ASSET_CACHE/sha256", kind="dir"
        )
        index_metadata = os.stat(cache_index, follow_symlinks=False)
        if (
            index_metadata.st_uid != os.geteuid()
            or stat.S_IMODE(index_metadata.st_mode) & 0o022
        ):
            fail(
                "PF-SANDBOX-LAUNCH-ENV",
                "ASSET_CACHE/sha256 must be owned and not writable by peers",
            )
        return common | {
            "PATH": "/usr/bin:/bin",
            "PF_XCODE_PYTHON": str(xcode_python),
            "PROOF_FORGE_ASSET_CACHE": str(cache),
        }
    if asset_cache is not None:
        fail("PF-SANDBOX-LAUNCH-ENV", f"{stage} forbids --asset-cache")
    build = common | {
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "LAKE_CACHE_DIR": str(temp_root / "cache" / "lake-packages"),
        "LAKE_HOME": str(temp_root / "cache" / "lake"),
        "LAKE_NO_CACHE": "1",
        "PATH": f"{temp_root / 'tools' / 'lean' / 'bin'}:{temp_root / 'tools' / 'external'}",
        "PF_CLEAN_OUTPUT": str(temp_root / "output"),
        "PF_CLEAN_SOURCE": str(temp_root / "source"),
        "PF_CLEAN_WORK": str(temp_root / "work"),
        "PF_LEAN_ROOT": str(temp_root / "tools" / "lean"),
        "PF_XCODE_GIT": str(xcode_git),
        "PF_XCODE_PYTHON": str(xcode_python),
        "PROOF_FORGE_TOOL_ROOT": str(temp_root / "tools" / "external"),
        "SOURCE_DATE_EPOCH": "0",
        "XDG_CACHE_HOME": str(temp_root / "cache" / "xdg"),
    }
    if stage == "evm-runtime":
        if runtime_port is None:
            fail("PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires --runtime-port")
        return common | {
            "PATH": str(temp_root / "tools" / "external"),
            "PF_CLEAN_OUTPUT": str(temp_root / "output"),
            "PF_CLEAN_WORK": str(temp_root / "work"),
            "PF_EVM_PORT": str(runtime_port),
            "PF_XCODE_PYTHON": str(xcode_python),
            "PROOF_FORGE_TOOL_ROOT": str(temp_root / "tools" / "external"),
            "XDG_CACHE_HOME": str(temp_root / "cache" / "xdg"),
        }
    return build


def validate_runtime_port(
    stage: str,
    runtime_port: int | None,
    environment: dict[str, str],
    policy_bytes: bytes,
) -> None:
    if stage != "evm-runtime":
        if runtime_port is not None:
            fail("PF-SANDBOX-LAUNCH-PORT", f"{stage} forbids --runtime-port")
        return
    if type(runtime_port) is not int or not 1 <= runtime_port <= 65535:
        fail(
            "PF-SANDBOX-LAUNCH-PORT", "evm-runtime requires --runtime-port in [1,65535]"
        )
    if environment.get("PF_EVM_PORT") != str(runtime_port):
        fail("PF-SANDBOX-LAUNCH-PORT", "PF_EVM_PORT must equal --runtime-port")
    try:
        text = policy_bytes.decode("utf-8")
    except UnicodeDecodeError:
        fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
    inbound = f'(allow network-inbound (local ip "localhost:{runtime_port}"))'
    outbound = f'(allow network-outbound (remote ip "localhost:{runtime_port}"))'
    if text.count(inbound) != 1 or text.count(outbound) != 1:
        fail("PF-SANDBOX-LAUNCH-PORT", "policy does not bind both local-port rules")


def validate_command(command: Sequence[str]) -> list[str]:
    result = list(command)
    if result and result[0] == "--":
        result = result[1:]
    if not result:
        fail("PF-SANDBOX-LAUNCH-COMMAND", "sandbox command must be non-empty")
    executable = canonical_existing(result[0], "command executable", kind="file")
    metadata = os.stat(executable, follow_symlinks=False)
    if metadata.st_nlink != 1 or not os.access(executable, os.X_OK):
        fail(
            "PF-SANDBOX-LAUNCH-COMMAND",
            "command executable must be single-link executable",
        )
    result[0] = str(executable)
    return result


def same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def directory_identity(metadata: os.stat_result) -> tuple[int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        stat.S_IMODE(metadata.st_mode),
    )


def verify_open_directory(
    directory_fd: int,
    path: Path,
    expected: tuple[int, int, int, int],
    label: str,
) -> None:
    descriptor_metadata = os.fstat(directory_fd)
    pathname_metadata = os.stat(path, follow_symlinks=False)
    if (
        not stat.S_ISDIR(descriptor_metadata.st_mode)
        or not stat.S_ISDIR(pathname_metadata.st_mode)
        or directory_identity(descriptor_metadata) != expected
        or directory_identity(pathname_metadata) != expected
        or descriptor_metadata.st_uid != os.geteuid()
        or stat.S_IMODE(descriptor_metadata.st_mode) != 0o700
    ):
        fail("PF-SANDBOX-LAUNCH-LAYOUT", f"{label} identity changed")


def sha256_domain(domain: bytes, value: object) -> str:
    return hashlib.sha256(domain + canonical_json_bytes(value)).hexdigest()


def canonical_environment_entries(environment: dict[str, str]) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for name in sorted(environment):
        value = environment[name]
        if ENVIRONMENT_NAME_RE.fullmatch(name) is None:
            fail("PF-SANDBOX-LAUNCH-RECEIPT", f"invalid environment name: {name}")
        if "\x00" in value or len(value.encode("utf-8")) > MAX_ENVIRONMENT_VALUE_BYTES:
            fail("PF-SANDBOX-LAUNCH-RECEIPT", f"invalid environment value: {name}")
        entries.append({"name": name, "value": value})
    return entries


def validate_receipt_document(value: object) -> dict[str, object]:
    root = require_keys(
        value,
        {
            "schema",
            "stage",
            "invocation",
            "runBindingSha256",
            "invocationBindingSha256",
            "policy",
            "runtimePort",
            "engine",
            "observedLauncherSha256",
            "command",
            "environment",
            "durationMs",
            "terminal",
            "stdout",
            "stderr",
        },
        "receipt",
    )
    if require_text(root["schema"], "receipt.schema") != INVOCATION_RECEIPT_SCHEMA:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "unsupported receipt schema")
    stage = require_text(root["stage"], "receipt.stage")
    if stage not in STAGES:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt stage is unsupported")
    invocation = validate_invocation(
        require_text(root["invocation"], "receipt.invocation")
    )
    require_sha256(root["runBindingSha256"], "receipt.runBindingSha256")
    require_sha256(root["invocationBindingSha256"], "receipt.invocationBindingSha256")
    policy = require_keys(root["policy"], {"path", "sha256", "size"}, "receipt.policy")
    if policy["path"] != f"policies/{stage}.sb":
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt policy path mismatch")
    require_sha256(policy["sha256"], "receipt.policy.sha256")
    require_int(policy["size"], "receipt.policy.size", 0, MAX_POLICY_BYTES)
    runtime_port = root["runtimePort"]
    if stage == "evm-runtime":
        require_int(runtime_port, "receipt.runtimePort", 1, 65535)
    elif runtime_port is not None:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "non-runtime receipt has a runtime port")
    engine = require_keys(root["engine"], {"path", "observedSha256"}, "receipt.engine")
    if engine["path"] != str(SANDBOX_ENGINE):
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt engine path mismatch")
    require_sha256(engine["observedSha256"], "receipt.engine.observedSha256")
    require_sha256(root["observedLauncherSha256"], "receipt.observedLauncherSha256")
    command = require_keys(
        root["command"],
        {"argv", "argvSha256", "observedExecutablePath", "observedExecutableSha256"},
        "receipt.command",
    )
    argv = command["argv"]
    if not isinstance(argv, list) or not argv:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt command argv must be non-empty")
    parsed_argv: list[str] = []
    for index, raw_argument in enumerate(argv):
        argument = require_string(
            raw_argument,
            f"receipt.command.argv[{index}]",
            maximum=MAX_ARGUMENT_BYTES,
            allow_empty=True,
        )
        parsed_argv.append(argument)
    observed_path = require_text(
        command["observedExecutablePath"],
        "receipt.command.observedExecutablePath",
        maximum=4096,
    )
    if parsed_argv[0] != observed_path:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt observed executable path mismatch")
    if (
        not observed_path.startswith("/")
        or os.path.normpath(observed_path) != observed_path
    ):
        fail(
            "PF-SANDBOX-LAUNCH-RECEIPT",
            "receipt executable path must be normalized absolute",
        )
    require_sha256(
        command["observedExecutableSha256"], "receipt.command.observedExecutableSha256"
    )
    if require_sha256(
        command["argvSha256"], "receipt.command.argvSha256"
    ) != sha256_domain(ARGV_DOMAIN, parsed_argv):
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt argv digest mismatch")
    environment = require_keys(
        root["environment"], {"entries", "sha256"}, "receipt.environment"
    )
    raw_entries = environment["entries"]
    if not isinstance(raw_entries, list):
        fail(
            "PF-SANDBOX-LAUNCH-RECEIPT", "receipt environment entries must be an array"
        )
    parsed_entries: list[dict[str, str]] = []
    names: list[str] = []
    for index, raw_entry in enumerate(raw_entries):
        entry = require_keys(
            raw_entry, {"name", "value"}, f"receipt.environment.entries[{index}]"
        )
        name = require_text(entry["name"], f"receipt.environment.entries[{index}].name")
        value_text = require_string(
            entry["value"],
            f"receipt.environment.entries[{index}].value",
            maximum=MAX_ENVIRONMENT_VALUE_BYTES,
            allow_empty=True,
        )
        if ENVIRONMENT_NAME_RE.fullmatch(name) is None:
            fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt environment name is invalid")
        names.append(name)
        parsed_entries.append({"name": name, "value": value_text})
    if names != sorted(names) or len(names) != len(set(names)):
        fail(
            "PF-SANDBOX-LAUNCH-RECEIPT", "receipt environment must be sorted and unique"
        )
    if require_sha256(
        environment["sha256"], "receipt.environment.sha256"
    ) != sha256_domain(ENVIRONMENT_DOMAIN, parsed_entries):
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt environment digest mismatch")
    require_int(root["durationMs"], "receipt.durationMs", 0, MAX_DURATION_MS)
    terminal = require_keys(
        root["terminal"], {"exitCode", "signal", "timedOut"}, "receipt.terminal"
    )
    if terminal["timedOut"] is not False:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "committed receipt cannot be timed out")
    exit_code = terminal["exitCode"]
    signal_value = terminal["signal"]
    if exit_code is not None:
        require_int(exit_code, "receipt.terminal.exitCode", 0, 255)
    if signal_value is not None:
        require_int(signal_value, "receipt.terminal.signal", 1, 255)
    if (exit_code is None) == (signal_value is None):
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt terminal must select exit or signal")
    for stream_name in ("stdout", "stderr"):
        stream = require_keys(
            root[stream_name],
            {"path", "sha256", "size", "truncated"},
            f"receipt.{stream_name}",
        )
        expected_path = f"policies/sandbox-{stage}-{invocation}.{stream_name}.log"
        if stream["path"] != expected_path:
            fail("PF-SANDBOX-LAUNCH-RECEIPT", f"receipt {stream_name} path mismatch")
        require_sha256(stream["sha256"], f"receipt.{stream_name}.sha256")
        require_int(stream["size"], f"receipt.{stream_name}.size", 0, MAX_STREAM_BYTES)
        if stream["truncated"] is not False:
            fail("PF-SANDBOX-LAUNCH-RECEIPT", "receipt streams cannot be truncated")
    return root


def receipt_document(
    *,
    stage: str,
    invocation: str,
    contexts: ReceiptContexts,
    policy_bytes: bytes,
    runtime_port: int | None,
    engine: FileObservation,
    launcher: FileObservation,
    executable: FileObservation,
    command: Sequence[str],
    environment: dict[str, str],
    duration_ms: int,
    return_code: int,
    stdout_sha256: str,
    stdout_size: int,
    stderr_sha256: str,
    stderr_size: int,
) -> dict[str, object]:
    argv = list(command)
    entries = canonical_environment_entries(environment)
    terminal: dict[str, object]
    if return_code >= 0:
        terminal = {"exitCode": return_code, "signal": None, "timedOut": False}
    else:
        terminal = {"exitCode": None, "signal": -return_code, "timedOut": False}
    document: dict[str, object] = {
        "schema": INVOCATION_RECEIPT_SCHEMA,
        "stage": stage,
        "invocation": invocation,
        "runBindingSha256": contexts.run_binding_sha256,
        "invocationBindingSha256": contexts.invocation_binding_sha256,
        "policy": {
            "path": f"policies/{stage}.sb",
            "sha256": hashlib.sha256(policy_bytes).hexdigest(),
            "size": len(policy_bytes),
        },
        "runtimePort": runtime_port,
        "engine": {"path": str(engine.path), "observedSha256": engine.sha256},
        "observedLauncherSha256": launcher.sha256,
        "command": {
            "argv": argv,
            "argvSha256": sha256_domain(ARGV_DOMAIN, argv),
            "observedExecutablePath": str(executable.path),
            "observedExecutableSha256": executable.sha256,
        },
        "environment": {
            "entries": entries,
            "sha256": sha256_domain(ENVIRONMENT_DOMAIN, entries),
        },
        "durationMs": duration_ms,
        "terminal": terminal,
        "stdout": {
            "path": f"policies/sandbox-{stage}-{invocation}.stdout.log",
            "sha256": stdout_sha256,
            "size": stdout_size,
            "truncated": False,
        },
        "stderr": {
            "path": f"policies/sandbox-{stage}-{invocation}.stderr.log",
            "sha256": stderr_sha256,
            "size": stderr_size,
            "truncated": False,
        },
    }
    return validate_receipt_document(document)


def encode_receipt(document: dict[str, object]) -> bytes:
    validate_receipt_document(document)
    encoded = canonical_json_bytes(document)
    if len(encoded) >= MAX_RECEIPT_BYTES:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "metadata receipt exceeds 1 MiB")
    return encoded


def preflight_receipt(
    *,
    stage: str,
    invocation: str,
    contexts: ReceiptContexts,
    policy_bytes: bytes,
    runtime_port: int | None,
    engine: FileObservation,
    launcher: FileObservation,
    executable: FileObservation,
    command: Sequence[str],
    environment: dict[str, str],
) -> None:
    sizes: list[int] = []
    for return_code in (255, -255):
        candidate = receipt_document(
            stage=stage,
            invocation=invocation,
            contexts=contexts,
            policy_bytes=policy_bytes,
            runtime_port=runtime_port,
            engine=engine,
            launcher=launcher,
            executable=executable,
            command=command,
            environment=environment,
            duration_ms=MAX_DURATION_MS,
            return_code=return_code,
            stdout_sha256="f" * 64,
            stdout_size=MAX_STREAM_BYTES,
            stderr_sha256="f" * 64,
            stderr_size=MAX_STREAM_BYTES,
        )
        sizes.append(len(encode_receipt(candidate)))
    if max(sizes) >= MAX_RECEIPT_BYTES:
        fail("PF-SANDBOX-LAUNCH-RECEIPT", "metadata receipt preflight exceeds 1 MiB")


def acquire_invocation_reservation(
    directory_fd: int, name: str
) -> InvocationReservation:
    flags = (
        os.O_RDWR
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor: int | None = None
    created_inode: tuple[int, int] | None = None
    try:
        descriptor = os.open(name, flags, 0o600, dir_fd=directory_fd)
        opened = os.fstat(descriptor)
        created_inode = (opened.st_dev, opened.st_ino)
        token = secrets.token_bytes(32)
        if os.write(descriptor, token) != len(token):
            fail("PF-SANDBOX-LAUNCH-RESERVATION", "short reservation write")
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o400)
        os.fsync(descriptor)
        metadata = os.fstat(descriptor)
        pathname = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or stable_metadata(metadata) != stable_metadata(pathname)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != 0o400
            or metadata.st_size != len(token)
        ):
            fail(
                "PF-SANDBOX-LAUNCH-RESERVATION",
                "invocation reservation invariant failed",
            )
        os.fsync(directory_fd)
        return InvocationReservation(
            name=name,
            descriptor=descriptor,
            metadata=stable_metadata(metadata),
            token_sha256=hashlib.sha256(token).hexdigest(),
        )
    except FileExistsError:
        fail(
            "PF-SANDBOX-LAUNCH-RESERVATION",
            f"invocation is already reserved: {name}",
        )
    except BaseException:
        if created_inode is not None:
            try:
                current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                if (current.st_dev, current.st_ino) == created_inode:
                    os.unlink(name, dir_fd=directory_fd)
            except OSError:
                pass
        if descriptor is not None:
            os.close(descriptor)
        raise


def verify_invocation_reservation(
    directory_fd: int, reservation: InvocationReservation
) -> None:
    descriptor = reservation.descriptor
    before = os.fstat(descriptor)
    if stable_metadata(before) != reservation.metadata:
        fail("PF-SANDBOX-LAUNCH-RESERVATION", "invocation reservation changed")
    os.lseek(descriptor, 0, os.SEEK_SET)
    token = os.read(descriptor, before.st_size + 1)
    after = os.fstat(descriptor)
    try:
        pathname = os.stat(reservation.name, dir_fd=directory_fd, follow_symlinks=False)
    except OSError as error:
        fail(
            "PF-SANDBOX-LAUNCH-RESERVATION",
            f"invocation reservation pathname changed: {error.strerror}",
        )
    if (
        stable_metadata(before) != stable_metadata(after)
        or stable_metadata(after) != stable_metadata(pathname)
        or hashlib.sha256(token).hexdigest() != reservation.token_sha256
    ):
        fail("PF-SANDBOX-LAUNCH-RESERVATION", "invocation reservation changed")


def release_invocation_reservation(
    directory_fd: int, reservation: InvocationReservation
) -> None:
    release_error: LaunchError | None = None
    try:
        verify_invocation_reservation(directory_fd, reservation)
    except LaunchError as error:
        release_error = error
    try:
        current = os.stat(reservation.name, dir_fd=directory_fd, follow_symlinks=False)
        if (current.st_dev, current.st_ino) == (
            reservation.metadata[0],
            reservation.metadata[1],
        ):
            os.unlink(reservation.name, dir_fd=directory_fd)
            os.fsync(directory_fd)
        elif release_error is None:
            release_error = LaunchError(
                "PF-SANDBOX-LAUNCH-RESERVATION",
                "invocation reservation ownership changed",
            )
    except OSError as error:
        if release_error is None:
            release_error = LaunchError(
                "PF-SANDBOX-LAUNCH-RESERVATION",
                f"cannot release invocation reservation: {error.strerror}",
            )
    finally:
        os.close(reservation.descriptor)
    if release_error is not None:
        raise release_error


def verify_published_receipt(
    directory_fd: int,
    receipt: PublishedReceipt,
    expected_data: bytes,
    *,
    before_path_check: Callable[[], None] | None = None,
) -> None:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(receipt.name, flags, dir_fd=directory_fd)
    except OSError as error:
        fail(
            "PF-SANDBOX-LAUNCH-LOG",
            f"cannot open published receipt {receipt.name}: {error.strerror}",
        )
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or stable_metadata(before) != receipt.metadata
            or before.st_nlink != 1
            or before.st_uid != os.geteuid()
            or stat.S_IMODE(before.st_mode) != 0o400
            or before.st_size != len(expected_data)
        ):
            fail("PF-SANDBOX-LAUNCH-LOG", f"published receipt changed: {receipt.name}")
        digest = hashlib.sha256()
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(remaining, 64 * 1024))
            if not chunk:
                break
            digest.update(chunk)
            chunks.append(chunk)
            remaining -= len(chunk)
        after = os.fstat(descriptor)
        if (
            remaining != 0
            or stable_metadata(before) != stable_metadata(after)
            or b"".join(chunks) != expected_data
            or digest.hexdigest() != receipt.sha256
        ):
            fail(
                "PF-SANDBOX-LAUNCH-LOG",
                f"published receipt bytes changed: {receipt.name}",
            )
        if before_path_check is not None:
            before_path_check()
        try:
            pathname = os.stat(receipt.name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            fail(
                "PF-SANDBOX-LAUNCH-LOG",
                f"published receipt pathname changed {receipt.name}: {error.strerror}",
            )
        if stable_metadata(after) != stable_metadata(pathname):
            fail(
                "PF-SANDBOX-LAUNCH-LOG",
                f"published receipt pathname changed: {receipt.name}",
            )
    finally:
        os.close(descriptor)


def atomic_receipt(
    directory_fd: int,
    name: str,
    data: bytes,
    *,
    before_final_path_check: Callable[[], None] | None = None,
) -> PublishedReceipt:
    if not name or "/" in name or name in {".", ".."}:
        fail("PF-SANDBOX-LAUNCH-LOG", "receipt name must be one safe path component")
    temporary = f".{name}.tmp-{os.getpid()}-{secrets.token_hex(8)}"
    flags = (
        os.O_RDWR
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    descriptor: int | None = None
    temporary_present = False
    linked = False
    completed = False
    staged_inode: tuple[int, int] | None = None
    try:
        descriptor = os.open(temporary, flags, 0o600, dir_fd=directory_fd)
        temporary_present = True
        offset = 0
        while offset < len(data):
            written = os.write(descriptor, data[offset:])
            if written <= 0:
                fail("PF-SANDBOX-LAUNCH-LOG", "short receipt write")
            offset += written
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o400)
        os.fsync(descriptor)
        staged = os.fstat(descriptor)
        staged_inode = (staged.st_dev, staged.st_ino)
        if (
            not stat.S_ISREG(staged.st_mode)
            or staged.st_size != len(data)
            or staged.st_nlink != 1
            or staged.st_uid != os.geteuid()
            or stat.S_IMODE(staged.st_mode) != 0o400
        ):
            fail("PF-SANDBOX-LAUNCH-LOG", "receipt staging invariant failed")
        try:
            os.link(
                temporary,
                name,
                src_dir_fd=directory_fd,
                dst_dir_fd=directory_fd,
                follow_symlinks=False,
            )
            linked = True
        except FileExistsError:
            fail("PF-SANDBOX-LAUNCH-LOG", f"receipt already exists: {name}")
        published = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if not same_inode(staged, published) or published.st_nlink != 2:
            fail("PF-SANDBOX-LAUNCH-LOG", "receipt pathname changed during publication")
        os.fsync(directory_fd)
        os.unlink(temporary, dir_fd=directory_fd)
        temporary_present = False
        os.fsync(directory_fd)
        final = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (
            not same_inode(staged, final)
            or final.st_nlink != 1
            or final.st_uid != os.geteuid()
            or stat.S_IMODE(final.st_mode) != 0o400
            or final.st_size != len(data)
        ):
            fail("PF-SANDBOX-LAUNCH-LOG", "final receipt invariant failed")
        receipt = PublishedReceipt(
            name=name,
            metadata=stable_metadata(final),
            sha256=hashlib.sha256(data).hexdigest(),
        )
        verify_published_receipt(
            directory_fd,
            receipt,
            data,
            before_path_check=before_final_path_check,
        )
        completed = True
        return receipt
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if linked and not completed and staged_inode is not None:
            try:
                current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                if (current.st_dev, current.st_ino) == staged_inode:
                    os.unlink(name, dir_fd=directory_fd)
            except OSError:
                pass
        if temporary_present:
            try:
                os.unlink(temporary, dir_fd=directory_fd)
            except FileNotFoundError:
                pass


def kill_process_group(process: subprocess.Popen[bytes]) -> None:
    # The group leader may have exited while a descendant still holds a pipe.
    # Always address the dedicated session by PGID before reaping the leader.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (PermissionError, ProcessLookupError):
        # macOS reports EPERM when the reserved group contains only an exited
        # zombie leader, which is the expected no-descendant success case.
        pass
    process.wait()


def collect_bounded_output(
    process: subprocess.Popen[bytes], timeout_seconds: int
) -> tuple[int, bytes, bytes]:
    if process.stdout is None or process.stderr is None:
        fail("PF-SANDBOX-LAUNCH", "launcher pipes are missing")
    output = {"stdout": bytearray(), "stderr": bytearray()}
    selector = selectors.DefaultSelector()
    exit_queue = select.kqueue()
    streams = {
        process.stdout.fileno(): ("stdout", process.stdout),
        process.stderr.fileno(): ("stderr", process.stderr),
    }
    for descriptor, (name, stream) in streams.items():
        os.set_blocking(descriptor, False)
        selector.register(descriptor, selectors.EVENT_READ, (name, stream))
    deadline = time.monotonic() + timeout_seconds
    leader_exited = False
    group_cleaned = False
    try:
        try:
            exit_queue.control(
                [
                    select.kevent(
                        process.pid,
                        filter=select.KQ_FILTER_PROC,
                        flags=(
                            select.KQ_EV_ADD
                            | select.KQ_EV_ENABLE
                            | select.KQ_EV_ONESHOT
                        ),
                        fflags=select.KQ_NOTE_EXIT,
                    )
                ],
                0,
                0,
            )
        except ProcessLookupError:
            # A fast leader can exit between Popen and kqueue registration.
            # Its reserved process group must still be cleaned before wait()
            # reaps the leader and permits PGID reuse.
            kill_process_group(process)
            leader_exited = True
            group_cleaned = True
        # KQ_NOTE_EXIT observes completion without wait()/poll() reaping the
        # leader.  Its zombie keeps the PGID reserved until descendants have
        # been killed and the original status can be collected safely.
        while selector.get_map() or not leader_exited:
            if not leader_exited and exit_queue.control([], 1, 0):
                leader_exited = True
                # Keep the exited leader unreaped until this point so its PGID
                # cannot be reused.  Then kill every member still in that
                # process group immediately; waiting for inherited pipes to
                # reach EOF would otherwise consume the stage timeout.
                kill_process_group(process)
                group_cleaned = True
            if leader_exited and not selector.get_map():
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                if not group_cleaned:
                    kill_process_group(process)
                    group_cleaned = True
                fail(
                    "PF-SANDBOX-LAUNCH-TIMEOUT", "sandbox stage exceeded fixed timeout"
                )
            events = (
                selector.select(timeout=min(0.25, remaining))
                if selector.get_map()
                else ()
            )
            if not events:
                time.sleep(min(0.01, remaining))
            for key, _ in events:
                name, stream = key.data
                try:
                    chunk = os.read(key.fd, 64 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(key.fd)
                    stream.close()
                    continue
                output[name].extend(chunk)
                if (
                    len(output[name]) > MAX_STREAM_BYTES
                    or len(output["stdout"]) + len(output["stderr"]) > MAX_TOTAL_BYTES
                ):
                    if not group_cleaned:
                        kill_process_group(process)
                        group_cleaned = True
                    fail("PF-SANDBOX-LAUNCH-OUTPUT", "sandbox output exceeded byte cap")
        if not group_cleaned:
            kill_process_group(process)
            group_cleaned = True
        return_code = process.returncode
        if return_code is None:
            fail("PF-SANDBOX-LAUNCH", "sandbox leader was not reaped")
    finally:
        selector.close()
        exit_queue.close()
        for _, stream in streams.values():
            if not stream.closed:
                stream.close()
    return return_code, bytes(output["stdout"]), bytes(output["stderr"])


def launch(
    stage: str,
    invocation: str,
    temp_root: Path,
    policies: Path,
    policy_bytes: bytes,
    environment: dict[str, str],
    command: Sequence[str],
    contexts: ReceiptContexts | None = None,
    *,
    expected_policies_identity: tuple[int, int, int, int] | None = None,
    receipt_writer: Callable[[int, str, bytes], PublishedReceipt] | None = None,
    before_spawn_check: Callable[[], None] | None = None,
    before_post_check: Callable[[], None] | None = None,
    before_metadata_publish: Callable[[], None] | None = None,
    before_reservation_release: Callable[[], None] | None = None,
    before_final_publication_check: Callable[[], None] | None = None,
    popen_factory: Callable[..., subprocess.Popen[bytes]] | None = None,
    output_collector: Callable[[subprocess.Popen[bytes], int], tuple[int, bytes, bytes]]
    | None = None,
) -> int:
    validate_invocation(invocation)
    command = tuple(command)
    environment = {name: environment[name] for name in sorted(environment)}
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        policies_fd = os.open(policies, directory_flags)
    except OSError as error:
        fail(
            "PF-SANDBOX-LAUNCH-LAYOUT",
            f"cannot open policies root: {error.strerror}",
        )
    policies_identity = (
        directory_identity(os.fstat(policies_fd))
        if expected_policies_identity is None
        else expected_policies_identity
    )
    stdout_name = f"sandbox-{stage}-{invocation}.stdout.log"
    stderr_name = f"sandbox-{stage}-{invocation}.stderr.log"
    metadata_name = f"sandbox-{stage}-{invocation}.receipt.json"
    reservation_name = f".sandbox-{stage}-{invocation}.reservation"
    process: subprocess.Popen[bytes] | None = None
    reservation: InvocationReservation | None = None
    try:
        verify_open_directory(policies_fd, policies, policies_identity, "policies root")
        reservation = acquire_invocation_reservation(policies_fd, reservation_name)
        verify_invocation_reservation(policies_fd, reservation)
        expected_outputs = [stdout_name, stderr_name, metadata_name]
        for name in expected_outputs:
            try:
                os.stat(name, dir_fd=policies_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            fail("PF-SANDBOX-LAUNCH-LOG", f"receipt already exists: {name}")
        try:
            policy_text = policy_bytes.decode("utf-8")
        except UnicodeDecodeError:
            fail("PF-SANDBOX-LAUNCH-POLICY", "policy must be UTF-8")
        if "\x00" in policy_text:
            fail("PF-SANDBOX-LAUNCH-POLICY", "policy contains NUL")
        engine_observation: FileObservation | None = None
        launcher_observation: FileObservation | None = None
        executable_observation: FileObservation | None = None
        policy_observation: FileObservation | None = None
        if contexts is not None:
            engine_observation, _ = observe_regular_file(
                SANDBOX_ENGINE,
                "sandbox engine",
                maximum=MAX_EXECUTABLE_BYTES,
                executable=True,
                capture=False,
            )
            launcher_observation, _ = observe_regular_file(
                Path(__file__).resolve(strict=True),
                "sandbox launcher source",
                maximum=MAX_EXECUTABLE_BYTES,
                required_owner=os.geteuid(),
                capture=False,
            )
            executable_observation, _ = observe_regular_file(
                Path(command[0]),
                "payload executable",
                maximum=MAX_EXECUTABLE_BYTES,
                executable=True,
                capture=False,
            )
            policy_observation, observed_policy_bytes = observe_regular_file(
                policies / f"{stage}.sb",
                "sandbox policy",
                maximum=MAX_POLICY_BYTES,
                required_mode=0o400,
                required_owner=os.geteuid(),
            )
            if observed_policy_bytes != policy_bytes:
                fail(
                    "PF-SANDBOX-LAUNCH-POLICY",
                    "policy observation differs from validated bytes",
                )
            preflight_receipt(
                stage=stage,
                invocation=invocation,
                contexts=contexts,
                policy_bytes=policy_bytes,
                runtime_port=(
                    int(environment["PF_EVM_PORT"]) if stage == "evm-runtime" else None
                ),
                engine=engine_observation,
                launcher=launcher_observation,
                executable=executable_observation,
                command=command,
                environment=environment,
            )
            if before_spawn_check is not None:
                before_spawn_check()
            for observation, label in (
                (contexts.run_observation, "run context"),
                (contexts.invocation_observation, "invocation context"),
                (policy_observation, "sandbox policy"),
                (engine_observation, "sandbox engine"),
                (launcher_observation, "sandbox launcher source"),
                (executable_observation, "payload executable"),
            ):
                if observation is None:
                    fail(
                        "PF-SANDBOX-LAUNCH-OBSERVATION",
                        f"missing {label} observation",
                    )
                verify_file_observation(observation, label)
        verify_invocation_reservation(policies_fd, reservation)
        verify_open_directory(policies_fd, policies, policies_identity, "policies root")
        started_ns = time.monotonic_ns()
        factory = subprocess.Popen if popen_factory is None else popen_factory
        process = factory(
            [str(SANDBOX_ENGINE), "-p", policy_text, *command],
            shell=False,
            cwd=str(temp_root),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
        )
        collector = (
            collect_bounded_output if output_collector is None else output_collector
        )
        return_code, stdout_data, stderr_data = collector(
            process, STAGE_TIMEOUT_SECONDS[stage]
        )
        metadata_data: bytes | None = None
        if contexts is not None:
            if before_post_check is not None:
                before_post_check()
            for observation, label in (
                (contexts.run_observation, "run context"),
                (contexts.invocation_observation, "invocation context"),
                (policy_observation, "sandbox policy"),
                (engine_observation, "sandbox engine"),
                (launcher_observation, "sandbox launcher source"),
                (executable_observation, "payload executable"),
            ):
                if observation is None:
                    fail(
                        "PF-SANDBOX-LAUNCH-OBSERVATION", f"missing {label} observation"
                    )
                verify_file_observation(observation, label)
            duration_ms = (time.monotonic_ns() - started_ns) // 1_000_000
            metadata = receipt_document(
                stage=stage,
                invocation=invocation,
                contexts=contexts,
                policy_bytes=policy_bytes,
                runtime_port=(
                    int(environment["PF_EVM_PORT"]) if stage == "evm-runtime" else None
                ),
                engine=engine_observation,
                launcher=launcher_observation,
                executable=executable_observation,
                command=command,
                environment=environment,
                duration_ms=duration_ms,
                return_code=return_code,
                stdout_sha256=hashlib.sha256(stdout_data).hexdigest(),
                stdout_size=len(stdout_data),
                stderr_sha256=hashlib.sha256(stderr_data).hexdigest(),
                stderr_size=len(stderr_data),
            )
            metadata_data = encode_receipt(metadata)
        writer = atomic_receipt if receipt_writer is None else receipt_writer
        published: list[tuple[PublishedReceipt, bytes]] = []

        def publish(name: str, data: bytes) -> None:
            receipt = writer(policies_fd, name, data)
            if not isinstance(receipt, PublishedReceipt) or receipt.name != name:
                fail(
                    "PF-SANDBOX-LAUNCH-LOG",
                    "receipt writer returned an invalid observation",
                )
            published.append((receipt, data))
            verify_published_receipt(policies_fd, receipt, data)

        def verify_publication(*, require_reservation: bool) -> None:
            verify_open_directory(
                policies_fd, policies, policies_identity, "policies root"
            )
            if require_reservation:
                if reservation is None:
                    fail(
                        "PF-SANDBOX-LAUNCH-RESERVATION",
                        "missing invocation reservation",
                    )
                verify_invocation_reservation(policies_fd, reservation)
            for receipt, data in published:
                verify_published_receipt(policies_fd, receipt, data)
            if not any(receipt.name == metadata_name for receipt, _ in published):
                try:
                    os.stat(metadata_name, dir_fd=policies_fd, follow_symlinks=False)
                except FileNotFoundError:
                    pass
                else:
                    fail(
                        "PF-SANDBOX-LAUNCH-LOG",
                        "metadata marker appeared without launcher ownership",
                    )

        try:
            verify_publication(require_reservation=True)
            publish(stdout_name, stdout_data)
            verify_publication(require_reservation=True)
            publish(stderr_name, stderr_data)
            if metadata_data is not None:
                if before_metadata_publish is not None:
                    before_metadata_publish()
            verify_publication(require_reservation=True)
            if before_reservation_release is not None:
                before_reservation_release()
            current_reservation = reservation
            if current_reservation is None:
                fail("PF-SANDBOX-LAUNCH-RESERVATION", "missing invocation reservation")
            try:
                release_invocation_reservation(policies_fd, current_reservation)
            finally:
                reservation = None
            verify_publication(require_reservation=False)
            if metadata_data is not None:
                publish(metadata_name, metadata_data)
            if before_final_publication_check is not None:
                before_final_publication_check()
            verify_publication(require_reservation=False)
            os.fsync(policies_fd)
            verify_publication(require_reservation=False)
        except BaseException:
            for name in reversed(expected_outputs):
                try:
                    os.unlink(name, dir_fd=policies_fd)
                except OSError:
                    pass
            try:
                os.fsync(policies_fd)
            except OSError:
                pass
            raise
        return return_code if return_code >= 0 else 128 - return_code
    finally:
        had_active_error = sys.exc_info()[0] is not None
        try:
            if process is not None and process.returncode is None:
                kill_process_group(process)
        finally:
            try:
                if reservation is not None:
                    release_invocation_reservation(policies_fd, reservation)
            except LaunchError:
                if not had_active_error:
                    raise
            finally:
                os.close(policies_fd)


def expect_error(code: str, operation) -> None:  # type: ignore[no-untyped-def]
    try:
        operation()
    except LaunchError as error:
        if error.code != code:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", f"expected {code}, got {error.code}")
        return
    fail("PF-SANDBOX-LAUNCH-SELFTEST", f"expected rejection {code}")


def expect_process_exit(pid: int, label: str) -> None:
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.02)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    fail("PF-SANDBOX-LAUNCH-SELFTEST", f"{label} survived process-group cleanup")


def self_test() -> None:
    global MAX_STREAM_BYTES
    codec_golden: dict[str, object] = {
        "z": None,
        "a": ["Lean/链", -1, "", False, MAX_SAFE_INTEGER],
        "quote": '"\\\n',
    }
    expected_codec = (
        b'{"a":["Lean/\xe9\x93\xbe",-1,"",false,9007199254740991],'
        b'"quote":"\\"\\\\\\n","z":null}'
    )
    if canonical_json_bytes(codec_golden) != expected_codec:
        fail("PF-SANDBOX-LAUNCH-SELFTEST", "canonical codec golden mismatch")
    if hashlib.sha256(expected_codec).hexdigest() != (
        "42725016f3d5d023c03b9c2c6e1feb793706bbb19f7f2e3af8a9025c8235c5ba"
    ):
        fail("PF-SANDBOX-LAUNCH-SELFTEST", "canonical codec digest golden mismatch")
    if decode_canonical_json(expected_codec, "codec golden") != codec_golden:
        fail("PF-SANDBOX-LAUNCH-SELFTEST", "canonical codec roundtrip mismatch")
    for label, malformed in (
        ("duplicate", b'{"x":1,"x":2}'),
        ("float", b'{"x":1.0}'),
        ("huge-int", b'{"x":99999999999999999}'),
        ("noncanonical", b'{ "x":1}'),
        ("newline", b'{"x":1}\n'),
    ):
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda data=malformed, name=label: decode_canonical_json(data, name),
        )
    with tempfile.TemporaryDirectory(prefix="proof-forge-sandbox-launch-") as raw:
        outer = Path(raw).resolve(strict=True)
        temp_root = outer / "private"
        asset_cache = outer / "assets"
        work = temp_root / "work"
        policies = temp_root / "policies"
        contexts_root = temp_root / "contexts"
        source = temp_root / "source"
        for directory in (
            temp_root,
            work,
            policies,
            contexts_root,
            source,
            temp_root / "home",
            temp_root / "cache",
            temp_root / "output",
            temp_root / "tools",
            temp_root / "tools" / "lean",
            temp_root / "tools" / "external",
            asset_cache,
            asset_cache / "sha256",
        ):
            directory.mkdir(parents=True, exist_ok=True)
        for directory in (
            temp_root,
            work,
            policies,
            contexts_root,
            temp_root / "home",
            temp_root / "cache",
            temp_root / "output",
            temp_root / "tools",
        ):
            os.chmod(directory, 0o700)
        runner = temp_root / "clean-room-runner.sh"
        runner.write_bytes(b"#!/bin/bash\n")
        os.chmod(runner, 0o500)
        policy = policies / "core.sb"
        renderer = Path(__file__).with_name("sandbox_policy.py")
        subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                str(renderer),
                "render",
                "core",
                "--temp-root",
                str(temp_root),
                "--asset-cache",
                str(asset_cache),
                "--xcode-python",
                sys.executable,
                "--lean-root",
                str(temp_root / "tools" / "lean"),
                "--external-root",
                str(temp_root / "tools" / "external"),
                "--source-root",
                str(source),
                "-o",
                str(policy),
            ],
            check=True,
            close_fds=True,
        )
        runtime_port = 43123
        runtime_policy = policies / "evm-runtime.sb"
        subprocess.run(
            [
                sys.executable,
                "-I",
                "-S",
                str(renderer),
                "render",
                "evm-runtime",
                "--temp-root",
                str(temp_root),
                "--asset-cache",
                str(asset_cache),
                "--xcode-python",
                sys.executable,
                "--lean-root",
                str(temp_root / "tools" / "lean"),
                "--external-root",
                str(temp_root / "tools" / "external"),
                "--source-root",
                str(source),
                "--port",
                str(runtime_port),
                "-o",
                str(runtime_policy),
            ],
            check=True,
            close_fds=True,
        )
        environment = derive_environment("core", temp_root, None, None)
        (
            _,
            _,
            validated_policies,
            policy_bytes,
            validated_policies_identity,
        ) = validate_layout("core", str(temp_root))
        validate_policy_snapshot(policy_bytes, "core", None)
        expect_error(
            "PF-SANDBOX-LAUNCH-POLICY",
            lambda: validate_policy_snapshot(
                b"(version 1)\n(allow default)\n", "core", None
            ),
        )

        run_context_path = temp_root / "run-context.json"
        base_context: dict[str, object] = {
            "schema": RUN_CONTEXT_SCHEMA,
            "runId": "RUN-0123456789abcdef0123456789abcdef",
            "runRoot": str(temp_root),
            "catalog": {
                "schema": "proof-forge.gate-catalog.v1",
                "id": "h1e-launcher-self-test",
                "version": "1.0.0",
                "contentSha256": "1" * 64,
                "catalogDigest": "2" * 64,
            },
            "gate": {
                "id": "sandbox-launcher-self-test",
                "taskId": "TASK-D0-03",
                "testIds": ["TST-EVIDENCE-001", "TST-ISO-002"],
            },
            "candidate": {
                "commit": "3" * 40,
                "treeObjectId": "4" * 40,
                "archiveSha256": "5" * 64,
            },
            "host": {
                "profileId": "darwin-arm64-self-test",
                "observationSha256": "6" * 64,
            },
            "bindings": [
                {"name": "base-count", "type": "integer", "value": -1},
                {"name": "empty-label", "type": "string", "value": ""},
                {"name": "source-sha256", "type": "sha256", "value": "7" * 64},
            ],
        }

        def replace_private_json(path: Path, value: object) -> bytes:
            encoded = canonical_json_bytes(value)
            try:
                os.chmod(path, 0o600, follow_symlinks=False)
                path.unlink()
            except FileNotFoundError:
                pass
            path.write_bytes(encoded)
            os.chmod(path, 0o400)
            return encoded

        base_bytes = replace_private_json(run_context_path, base_context)
        base_digest = hashlib.sha256(RUN_CONTEXT_DOMAIN + base_bytes).hexdigest()

        def invocation_context_document(
            invocation: str,
            *,
            stage: str = "core",
            run_binding: str = base_digest,
        ) -> dict[str, object]:
            return {
                "schema": INVOCATION_CONTEXT_SCHEMA,
                "runBindingSha256": run_binding,
                "stage": stage,
                "invocation": invocation,
                "bindings": [],
            }

        def prepare_contexts(
            invocation: str, *, stage: str = "core"
        ) -> ReceiptContexts:
            path = contexts_root / f"sandbox-{stage}-{invocation}.json"
            replace_private_json(
                path, invocation_context_document(invocation, stage=stage)
            )
            loaded = load_receipt_contexts(
                str(run_context_path),
                str(path),
                stage=stage,
                invocation=invocation,
                temp_root=temp_root,
            )
            if loaded is None:
                fail("PF-SANDBOX-LAUNCH-SELFTEST", "receipt contexts were not loaded")
            return loaded

        context_marker = work / "context-mismatch-spawned"
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                None,
                stage="core",
                invocation="context-single",
                temp_root=temp_root,
            ),
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                None,
                str(contexts_root / "sandbox-core-context-single.json"),
                stage="core",
                invocation="context-single",
                temp_root=temp_root,
            ),
        )
        valid_context_path = contexts_root / "sandbox-core-context-joins.json"
        replace_private_json(
            valid_context_path, invocation_context_document("context-joins")
        )
        os.chmod(contexts_root, 0o755)
        expect_error(
            "PF-SANDBOX-LAUNCH-LAYOUT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        os.chmod(contexts_root, 0o700)
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path) + ".wrong",
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        wrong_root = copy.deepcopy(base_context)
        wrong_root["runRoot"] = str(temp_root / "wrong")
        replace_private_json(run_context_path, wrong_root)
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        replace_private_json(run_context_path, base_context)
        replace_private_json(
            valid_context_path,
            invocation_context_document("context-joins", run_binding="8" * 64),
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        replace_private_json(
            valid_context_path,
            invocation_context_document("wrong-invocation", stage="materialize"),
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        replace_private_json(
            valid_context_path, invocation_context_document("context-joins")
        )
        os.chmod(run_context_path, 0o600)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        os.chmod(run_context_path, 0o400)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: observe_regular_file(
                run_context_path,
                "wrong-owner run context",
                maximum=MAX_CONTEXT_BYTES,
                required_mode=0o400,
                required_owner=os.geteuid() + 1,
            ),
        )
        hardlink = temp_root / "run-context-hardlink.json"
        os.link(run_context_path, hardlink)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-OBSERVATION",
                lambda: load_receipt_contexts(
                    str(run_context_path),
                    str(valid_context_path),
                    stage="core",
                    invocation="context-joins",
                    temp_root=temp_root,
                ),
            )
        finally:
            hardlink.unlink()
        os.chmod(run_context_path, 0o600)
        run_context_path.unlink()
        run_context_path.write_bytes(b"x" * (MAX_CONTEXT_BYTES + 1))
        os.chmod(run_context_path, 0o400)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(valid_context_path),
                stage="core",
                invocation="context-joins",
                temp_root=temp_root,
            ),
        )
        replace_private_json(run_context_path, base_context)
        saved_run_context = temp_root / "saved-run-context.json"
        run_context_path.rename(saved_run_context)
        os.symlink(saved_run_context.name, run_context_path)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-PATH",
                lambda: load_receipt_contexts(
                    str(run_context_path),
                    str(valid_context_path),
                    stage="core",
                    invocation="context-joins",
                    temp_root=temp_root,
                ),
            )
        finally:
            run_context_path.unlink()
            saved_run_context.rename(run_context_path)
        path_replacement_context = temp_root / "path-replacement-context.json"
        replace_private_json(path_replacement_context, base_context)

        def replace_observed_context_path() -> None:
            os.chmod(path_replacement_context, 0o600)
            path_replacement_context.unlink()
            path_replacement_context.write_bytes(base_bytes)
            os.chmod(path_replacement_context, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: observe_regular_file(
                path_replacement_context,
                "path-replaced run context",
                maximum=MAX_CONTEXT_BYTES,
                required_mode=0o400,
                required_owner=os.geteuid(),
                before_path_check=replace_observed_context_path,
            ),
        )
        path_replacement_context.unlink()

        invocation_matrix = "invocation-matrix"
        invocation_matrix_path = (
            contexts_root / f"sandbox-core-{invocation_matrix}.json"
        )
        invocation_matrix_document = invocation_context_document(invocation_matrix)
        invocation_matrix_bytes = replace_private_json(
            invocation_matrix_path, invocation_matrix_document
        )
        invocation_matrix_contexts = load_receipt_contexts(
            str(run_context_path),
            str(invocation_matrix_path),
            stage="core",
            invocation=invocation_matrix,
            temp_root=temp_root,
        )
        if invocation_matrix_contexts is None or (
            invocation_matrix_contexts.run_binding_sha256 != base_digest
            or invocation_matrix_contexts.invocation_binding_sha256
            != hashlib.sha256(
                INVOCATION_CONTEXT_DOMAIN + invocation_matrix_bytes
            ).hexdigest()
        ):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST",
                "independent context domain digest mismatch",
            )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(invocation_matrix_path) + ".wrong",
                stage="core",
                invocation=invocation_matrix,
                temp_root=temp_root,
            ),
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: observe_regular_file(
                invocation_matrix_path,
                "wrong-owner invocation context",
                maximum=MAX_CONTEXT_BYTES,
                required_mode=0o400,
                required_owner=os.geteuid() + 1,
            ),
        )
        os.chmod(invocation_matrix_path, 0o600)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(invocation_matrix_path),
                stage="core",
                invocation=invocation_matrix,
                temp_root=temp_root,
            ),
        )
        os.chmod(invocation_matrix_path, 0o400)
        invocation_hardlink = contexts_root / "invocation-context-hardlink.json"
        os.link(invocation_matrix_path, invocation_hardlink)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-OBSERVATION",
                lambda: load_receipt_contexts(
                    str(run_context_path),
                    str(invocation_matrix_path),
                    stage="core",
                    invocation=invocation_matrix,
                    temp_root=temp_root,
                ),
            )
        finally:
            invocation_hardlink.unlink()
        os.chmod(invocation_matrix_path, 0o600)
        invocation_matrix_path.unlink()
        invocation_matrix_path.write_bytes(b"x" * (MAX_CONTEXT_BYTES + 1))
        os.chmod(invocation_matrix_path, 0o400)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(invocation_matrix_path),
                stage="core",
                invocation=invocation_matrix,
                temp_root=temp_root,
            ),
        )
        replace_private_json(invocation_matrix_path, invocation_matrix_document)
        saved_invocation_context = contexts_root / "saved-invocation-context.json"
        invocation_matrix_path.rename(saved_invocation_context)
        os.symlink(saved_invocation_context.name, invocation_matrix_path)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-PATH",
                lambda: load_receipt_contexts(
                    str(run_context_path),
                    str(invocation_matrix_path),
                    stage="core",
                    invocation=invocation_matrix,
                    temp_root=temp_root,
                ),
            )
        finally:
            invocation_matrix_path.unlink()
            saved_invocation_context.rename(invocation_matrix_path)

        def replace_observed_invocation_path() -> None:
            os.chmod(invocation_matrix_path, 0o600)
            invocation_matrix_path.unlink()
            invocation_matrix_path.write_bytes(invocation_matrix_bytes)
            os.chmod(invocation_matrix_path, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: observe_regular_file(
                invocation_matrix_path,
                "path-replaced invocation context",
                maximum=MAX_CONTEXT_BYTES,
                required_mode=0o400,
                required_owner=os.geteuid(),
                before_path_check=replace_observed_invocation_path,
            ),
        )
        noncanonical_invocation = b"{ " + invocation_matrix_bytes[1:]
        os.chmod(invocation_matrix_path, 0o600)
        invocation_matrix_path.unlink()
        invocation_matrix_path.write_bytes(noncanonical_invocation)
        os.chmod(invocation_matrix_path, 0o400)
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: load_receipt_contexts(
                str(run_context_path),
                str(invocation_matrix_path),
                stage="core",
                invocation=invocation_matrix,
                temp_root=temp_root,
            ),
        )
        replace_private_json(invocation_matrix_path, invocation_matrix_document)
        unknown_invocation_context = copy.deepcopy(invocation_matrix_document)
        unknown_invocation_context["unknown"] = True
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: validate_invocation_context(unknown_invocation_context),
        )
        duplicate_invocation_context = (
            invocation_matrix_bytes[:-1] + b',"schema":"duplicate"}'
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: decode_canonical_json(
                duplicate_invocation_context, "duplicate invocation context"
            ),
        )

        no_spawn_invocation = "context-no-spawn"
        no_spawn_context_path = (
            contexts_root / f"sandbox-core-{no_spawn_invocation}.json"
        )
        replace_private_json(
            no_spawn_context_path,
            invocation_context_document(no_spawn_invocation, run_binding="9" * 64),
        )
        spawn_calls = 0

        def context_spawn_spy(*_args, **_kwargs):  # type: ignore[no-untyped-def]
            nonlocal spawn_calls
            spawn_calls += 1
            raise AssertionError("invalid context reached Popen")

        no_spawn_args = argparse.Namespace(
            stage="core",
            invocation=no_spawn_invocation,
            temp_root=str(temp_root),
            asset_cache=None,
            runtime_port=None,
            receipt_run_context=str(run_context_path),
            receipt_invocation_context=str(no_spawn_context_path),
            command=[sys.executable, "-I", "-S", "-c", "pass"],
        )
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: run_command(no_spawn_args, popen_factory=context_spawn_spy),
        )
        if spawn_calls != 0 or any(
            policies.glob(f"sandbox-core-{no_spawn_invocation}.*")
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "context rejection spawned or published")

        cross_field_cases: list[tuple[str, dict[str, object], dict[str, object]]] = [
            (
                "cross-run-root",
                wrong_root,
                invocation_context_document("cross-run-root"),
            ),
            (
                "cross-run-binding",
                base_context,
                invocation_context_document("cross-run-binding", run_binding="a" * 64),
            ),
            (
                "cross-stage",
                base_context,
                invocation_context_document("cross-stage", stage="materialize"),
            ),
            (
                "cross-invocation",
                base_context,
                invocation_context_document("different-invocation"),
            ),
        ]
        for invocation, run_document, invocation_document in cross_field_cases:
            replace_private_json(run_context_path, run_document)
            cross_path = contexts_root / f"sandbox-core-{invocation}.json"
            replace_private_json(cross_path, invocation_document)
            cross_args = argparse.Namespace(
                stage="core",
                invocation=invocation,
                temp_root=str(temp_root),
                asset_cache=None,
                runtime_port=None,
                receipt_run_context=str(run_context_path),
                receipt_invocation_context=str(cross_path),
                command=[sys.executable, "-I", "-S", "-c", "pass"],
            )
            expect_error(
                "PF-SANDBOX-LAUNCH-CONTEXT",
                lambda current_args=cross_args: run_command(
                    current_args, popen_factory=context_spawn_spy
                ),
            )
            if any(policies.glob(f"sandbox-core-{invocation}.*")):
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    f"{invocation} mismatch published receipts",
                )
        replace_private_json(run_context_path, base_context)
        if spawn_calls != 0:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "cross-field mismatch reached spawn")
        if context_marker.exists():
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "context rejection spawned a payload")

        unknown_context = copy.deepcopy(base_context)
        unknown_context["unknown"] = True
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT", lambda: validate_run_context(unknown_context)
        )
        duplicate_context = base_bytes[:-1] + b',"schema":"duplicate"}'
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: decode_canonical_json(duplicate_context, "duplicate run context"),
        )
        pre_spawn_contexts = prepare_contexts("pre-spawn-context-swap")
        pre_spawn_path = pre_spawn_contexts.invocation_observation.path
        pre_spawn_bytes = pre_spawn_path.read_bytes()
        pre_spawn_calls = 0

        def replace_context_before_spawn() -> None:
            os.chmod(pre_spawn_path, 0o600)
            pre_spawn_path.unlink()
            pre_spawn_path.write_bytes(pre_spawn_bytes)
            os.chmod(pre_spawn_path, 0o400)

        def pre_spawn_spy(*_args, **_kwargs):  # type: ignore[no-untyped-def]
            nonlocal pre_spawn_calls
            pre_spawn_calls += 1
            raise AssertionError("pre-spawn context mismatch reached Popen")

        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: launch(
                "core",
                "pre-spawn-context-swap",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                pre_spawn_contexts,
                before_spawn_check=replace_context_before_spawn,
                popen_factory=pre_spawn_spy,
            ),
        )
        if pre_spawn_calls != 0 or any(
            policies.glob("*sandbox-core-pre-spawn-context-swap*")
        ):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST", "pre-spawn mismatch spawned or published"
            )
        secret = source / "body"
        secret.write_bytes(b"candidate-body")
        descriptor = os.open(secret, os.O_WRONLY)
        try:
            os.dup2(descriptor, 9, inheritable=True)
            code = (
                "import errno,os,sys; "
                "assert os.read(0,1)==b''; "
                "\ntry: os.write(9,b'changed')\n"
                "except OSError as e: assert e.errno==errno.EBADF\n"
                "else: raise AssertionError('fd9 inherited')\n"
                "print('stdout-ok'); print('stderr-ok',file=sys.stderr)"
            )
            result = launch(
                "core",
                "fd-close",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", code],
            )
        finally:
            os.close(9)
            if descriptor != 9:
                os.close(descriptor)
        if result != 0 or secret.read_bytes() != b"candidate-body":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "inherited fd modified candidate body")
        stdout_receipt = policies / "sandbox-core-fd-close.stdout.log"
        stderr_receipt = policies / "sandbox-core-fd-close.stderr.log"
        if stdout_receipt.read_text() != "stdout-ok\n":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "stdout log mismatch")
        if stderr_receipt.read_text() != "stderr-ok\n":
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "stderr log mismatch")
        if stat.S_IMODE(stdout_receipt.stat().st_mode) != 0o400:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "receipt mode mismatch")
        if (policies / "sandbox-core-fd-close.receipt.json").exists():
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "legacy launch published metadata")

        def read_metadata(invocation: str, *, stage: str = "core") -> dict[str, object]:
            path = policies / f"sandbox-{stage}-{invocation}.receipt.json"
            encoded = path.read_bytes()
            if (
                not encoded
                or encoded.endswith(b"\n")
                or len(encoded) >= MAX_RECEIPT_BYTES
            ):
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "metadata canonical size/newline mismatch",
                )
            value = decode_canonical_json(encoded, "metadata receipt")
            document = validate_receipt_document(value)
            if canonical_json_bytes(document) != encoded:
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "metadata receipt roundtrip changed bytes",
                )
            if stat.S_IMODE(path.stat().st_mode) != 0o400 or path.stat().st_nlink != 1:
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "metadata receipt file invariant mismatch",
                )
            return document

        success_contexts = prepare_contexts("metadata-success")
        success_command = [
            sys.executable,
            "-I",
            "-S",
            "-c",
            "import sys;print('meta-ok');print('meta-err',file=sys.stderr)",
        ]
        success_result = launch(
            "core",
            "metadata-success",
            temp_root,
            validated_policies,
            policy_bytes,
            environment,
            success_command,
            success_contexts,
        )
        if success_result != 0:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata success command failed")
        success_metadata = read_metadata("metadata-success")
        if success_metadata["terminal"] != {
            "exitCode": 0,
            "signal": None,
            "timedOut": False,
        }:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata success terminal mismatch")
        if success_metadata["runBindingSha256"] != success_contexts.run_binding_sha256:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata run binding mismatch")
        if (
            success_metadata["invocationBindingSha256"]
            != success_contexts.invocation_binding_sha256
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata invocation binding mismatch")
        expected_policy = {
            "path": "policies/core.sb",
            "sha256": hashlib.sha256(policy_bytes).hexdigest(),
            "size": len(policy_bytes),
        }
        if (
            success_metadata["policy"] != expected_policy
            or success_metadata["runtimePort"] is not None
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata policy/port mismatch")
        engine = success_metadata["engine"]
        if engine != {
            "path": str(SANDBOX_ENGINE),
            "observedSha256": hashlib.sha256(SANDBOX_ENGINE.read_bytes()).hexdigest(),
        }:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata engine observation mismatch")
        if (
            success_metadata["observedLauncherSha256"]
            != hashlib.sha256(
                Path(__file__).resolve(strict=True).read_bytes()
            ).hexdigest()
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata launcher observation mismatch")
        expected_argv = list(success_command)
        expected_command = {
            "argv": expected_argv,
            "argvSha256": hashlib.sha256(
                ARGV_DOMAIN + canonical_json_bytes(expected_argv)
            ).hexdigest(),
            "observedExecutablePath": sys.executable,
            "observedExecutableSha256": hashlib.sha256(
                Path(sys.executable).read_bytes()
            ).hexdigest(),
        }
        if success_metadata["command"] != expected_command:
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST", "metadata exact argv/executable mismatch"
            )
        expected_entries = [
            {"name": name, "value": environment[name]} for name in sorted(environment)
        ]
        expected_environment = {
            "entries": expected_entries,
            "sha256": hashlib.sha256(
                ENVIRONMENT_DOMAIN + canonical_json_bytes(expected_entries)
            ).hexdigest(),
        }
        if success_metadata["environment"] != expected_environment:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata exact environment mismatch")
        for stream_name, expected in (
            ("stdout", b"meta-ok\n"),
            ("stderr", b"meta-err\n"),
        ):
            stream = success_metadata[stream_name]
            if not isinstance(stream, dict):
                fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata stream shape mismatch")
            if stream["sha256"] != hashlib.sha256(expected).hexdigest() or stream[
                "size"
            ] != len(expected):
                fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata stream binding mismatch")

        (
            _,
            _,
            runtime_policies,
            runtime_policy_bytes,
            runtime_policies_identity,
        ) = validate_layout("evm-runtime", str(temp_root))
        runtime_environment = derive_environment(
            "evm-runtime", temp_root, None, runtime_port
        )
        validate_policy_snapshot(runtime_policy_bytes, "evm-runtime", runtime_port)
        validate_runtime_port(
            "evm-runtime", runtime_port, runtime_environment, runtime_policy_bytes
        )
        runtime_contexts = prepare_contexts("metadata-runtime", stage="evm-runtime")
        if (
            launch(
                "evm-runtime",
                "metadata-runtime",
                temp_root,
                runtime_policies,
                runtime_policy_bytes,
                runtime_environment,
                [sys.executable, "-I", "-S", "-c", "print('runtime-ok')"],
                runtime_contexts,
                expected_policies_identity=runtime_policies_identity,
            )
            != 0
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "runtime metadata command failed")
        runtime_metadata = read_metadata("metadata-runtime", stage="evm-runtime")
        if runtime_metadata["runtimePort"] != runtime_port or runtime_metadata[
            "policy"
        ] != {
            "path": "policies/evm-runtime.sb",
            "sha256": hashlib.sha256(runtime_policy_bytes).hexdigest(),
            "size": len(runtime_policy_bytes),
        }:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "runtime receipt port/policy mismatch")

        nonzero_contexts = prepare_contexts("metadata-nonzero")
        nonzero_result = launch(
            "core",
            "metadata-nonzero",
            temp_root,
            validated_policies,
            policy_bytes,
            environment,
            [sys.executable, "-I", "-S", "-c", "raise SystemExit(17)"],
            nonzero_contexts,
        )
        if nonzero_result != 17 or read_metadata("metadata-nonzero")["terminal"] != {
            "exitCode": 17,
            "signal": None,
            "timedOut": False,
        }:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata nonzero terminal mismatch")

        signal_contexts = prepare_contexts("metadata-signal")
        signal_result = launch(
            "core",
            "metadata-signal",
            temp_root,
            validated_policies,
            policy_bytes,
            environment,
            [
                sys.executable,
                "-I",
                "-S",
                "-c",
                "import os,signal;os.kill(os.getpid(),signal.SIGTERM)",
            ],
            signal_contexts,
        )
        signal_terminal = read_metadata("metadata-signal")["terminal"]
        if signal_result != 143 or signal_terminal != {
            "exitCode": None,
            "signal": signal.SIGTERM,
            "timedOut": False,
        }:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata signal terminal mismatch")

        tampered_metadata = copy.deepcopy(success_metadata)
        tampered_metadata["command"]["argvSha256"] = "0" * 64  # type: ignore[index]
        expect_error(
            "PF-SANDBOX-LAUNCH-RECEIPT",
            lambda: validate_receipt_document(tampered_metadata),
        )
        unknown_metadata = copy.deepcopy(success_metadata)
        unknown_metadata["unknown"] = True
        expect_error(
            "PF-SANDBOX-LAUNCH-CONTEXT",
            lambda: validate_receipt_document(unknown_metadata),
        )
        original_stream_cap = MAX_STREAM_BYTES
        MAX_STREAM_BYTES = 32
        output_cap_contexts = prepare_contexts("output-cap")
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-OUTPUT",
                lambda: launch(
                    "core",
                    "output-cap",
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "print('x'*1024)"],
                    output_cap_contexts,
                ),
            )
        finally:
            MAX_STREAM_BYTES = original_stream_cap
        if any(policies.glob("sandbox-core-output-cap.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "output-cap failure published receipts")
        fast_process = subprocess.Popen(
            [sys.executable, "-I", "-S", "-c", "print('fast-exit')"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
        )
        time.sleep(0.15)
        fast_code, fast_stdout, fast_stderr = collect_bounded_output(fast_process, 2)
        if fast_code != 0 or fast_stdout != b"fast-exit\n" or fast_stderr:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "fast-exit collection mismatch")
        detached_marker = work / "detached.pid"
        detached_code = (
            "import os,time\n"
            f"marker={str(detached_marker)!r}\n"
            "pid=os.fork()\n"
            "if pid == 0:\n"
            "    fd=os.open(marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)\n"
            "    os.write(fd,str(os.getpid()).encode())\n"
            "    os.close(fd)\n"
            "    time.sleep(30)\n"
            "    os._exit(0)\n"
            "while not os.path.exists(marker): time.sleep(0.01)\n"
            "os._exit(0)\n"
        )
        detached_result = launch(
            "core",
            "detached-child",
            temp_root,
            validated_policies,
            policy_bytes,
            environment,
            [sys.executable, "-I", "-S", "-c", detached_code],
        )
        if detached_result != 0:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "detached-child leader failed")
        expect_process_exit(int(detached_marker.read_text()), "detached child")
        orphan_marker = work / "orphan.pid"
        original_timeout = STAGE_TIMEOUT_SECONDS["core"]
        STAGE_TIMEOUT_SECONDS["core"] = 0.5
        orphan_code = (
            "import os,time\n"
            f"marker={str(orphan_marker)!r}\n"
            "pid=os.fork()\n"
            "if pid == 0:\n"
            "    fd=os.open(marker,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)\n"
            "    os.write(fd,str(os.getpid()).encode())\n"
            "    os.close(fd)\n"
            "else:\n"
            "    while not os.path.exists(marker): time.sleep(0.01)\n"
            "time.sleep(30)\n"
        )
        try:
            orphan_contexts = prepare_contexts("orphan-timeout")
            expect_error(
                "PF-SANDBOX-LAUNCH-TIMEOUT",
                lambda: launch(
                    "core",
                    "orphan-timeout",
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", orphan_code],
                    orphan_contexts,
                ),
            )
        finally:
            STAGE_TIMEOUT_SECONDS["core"] = original_timeout
        if any(policies.glob("sandbox-core-orphan-timeout.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "timeout failure published receipts")
        expect_process_exit(int(orphan_marker.read_text()), "timed-out descendant")

        oversized_marker = work / "oversized-spawned"
        oversized_contexts = prepare_contexts("oversized-preflight")
        oversized_arguments = ["x" * MAX_ARGUMENT_BYTES for _ in range(16)]
        expect_error(
            "PF-SANDBOX-LAUNCH-RECEIPT",
            lambda: launch(
                "core",
                "oversized-preflight",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [
                    sys.executable,
                    "-I",
                    "-S",
                    "-c",
                    f"open({str(oversized_marker)!r},'wb').close()",
                    *oversized_arguments,
                ],
                oversized_contexts,
            ),
        )
        if oversized_marker.exists() or any(
            policies.glob("sandbox-core-oversized-preflight.*")
        ):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST", "oversized preflight spawned or published"
            )

        spawn_contexts = prepare_contexts("spawn-failure")

        def injected_spawn_failure(*_args, **_kwargs):  # type: ignore[no-untyped-def]
            raise OSError("injected spawn failure")

        try:
            launch(
                "core",
                "spawn-failure",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                spawn_contexts,
                popen_factory=injected_spawn_failure,
            )
        except OSError as error:
            if "injected spawn failure" not in str(error):
                raise
        else:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "spawn failure was not surfaced")
        if any(policies.glob("sandbox-core-spawn-failure.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "spawn failure published receipts")

        cleanup_contexts = prepare_contexts("cleanup-failure")

        def injected_cleanup_failure(
            process: subprocess.Popen[bytes], _timeout: int
        ) -> tuple[int, bytes, bytes]:
            kill_process_group(process)
            fail("PF-SANDBOX-LAUNCH-SELFTEST-INJECT", "injected cleanup failure")

        expect_error(
            "PF-SANDBOX-LAUNCH-SELFTEST-INJECT",
            lambda: launch(
                "core",
                "cleanup-failure",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                cleanup_contexts,
                output_collector=injected_cleanup_failure,
            ),
        )
        if any(policies.glob("sandbox-core-cleanup-failure.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "cleanup failure published receipts")

        post_contexts = prepare_contexts("post-check-failure")

        def mutate_post_context() -> None:
            os.chmod(post_contexts.invocation_observation.path, 0o600)

        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: launch(
                "core",
                "post-check-failure",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                post_contexts,
                before_post_check=mutate_post_context,
            ),
        )
        if any(policies.glob("sandbox-core-post-check-failure.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "post-check failure published receipts")

        post_swap_contexts = prepare_contexts("post-path-replacement")
        post_swap_path = post_swap_contexts.invocation_observation.path
        post_swap_bytes = post_swap_path.read_bytes()

        def replace_post_context_path() -> None:
            os.chmod(post_swap_path, 0o600)
            post_swap_path.unlink()
            post_swap_path.write_bytes(post_swap_bytes)
            os.chmod(post_swap_path, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: launch(
                "core",
                "post-path-replacement",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                post_swap_contexts,
                before_post_check=replace_post_context_path,
            ),
        )
        if any(policies.glob("sandbox-core-post-path-replacement.*")):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST", "post path replacement published receipts"
            )

        for failure_step in (1, 2, 3):
            invocation = f"publish-failure-{failure_step}"
            failure_contexts = prepare_contexts(invocation)
            calls = 0

            def injected_writer(
                directory_fd: int,
                name: str,
                data: bytes,
                *,
                fail_at: int = failure_step,
            ) -> PublishedReceipt:
                nonlocal calls
                calls += 1
                if calls == fail_at:
                    fail(
                        "PF-SANDBOX-LAUNCH-SELFTEST-INJECT", "injected publish failure"
                    )
                return atomic_receipt(directory_fd, name, data)

            expect_error(
                "PF-SANDBOX-LAUNCH-SELFTEST-INJECT",
                lambda current_invocation=invocation, current_contexts=failure_contexts: (
                    launch(
                        "core",
                        current_invocation,
                        temp_root,
                        validated_policies,
                        policy_bytes,
                        environment,
                        [sys.executable, "-I", "-S", "-c", "print('publish')"],
                        current_contexts,
                        receipt_writer=injected_writer,
                    )
                ),
            )
            if any(policies.glob(f"sandbox-core-{invocation}.*")):
                fail("PF-SANDBOX-LAUNCH-SELFTEST", "publish failure left a partial set")

        order_contexts = prepare_contexts("publication-order")
        publication_order: list[str] = []

        def ordered_writer(
            directory_fd: int, name: str, data: bytes
        ) -> PublishedReceipt:
            publication_order.append(name)
            return atomic_receipt(directory_fd, name, data)

        if (
            launch(
                "core",
                "publication-order",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                order_contexts,
                receipt_writer=ordered_writer,
            )
            != 0
        ):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "publication-order launch failed")
        if publication_order != [
            "sandbox-core-publication-order.stdout.log",
            "sandbox-core-publication-order.stderr.log",
            "sandbox-core-publication-order.receipt.json",
        ]:
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata was not the commit marker")

        reservation_invocation = "reservation-contention"
        reservation_name = f".sandbox-core-{reservation_invocation}.reservation"
        reservation_fd = os.open(
            policies,
            os.O_RDONLY
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0),
        )
        held_reservation = acquire_invocation_reservation(
            reservation_fd, reservation_name
        )
        reservation_spawn_calls = 0

        def reservation_spawn_spy(*_args, **_kwargs):  # type: ignore[no-untyped-def]
            nonlocal reservation_spawn_calls
            reservation_spawn_calls += 1
            raise AssertionError("reservation contention reached Popen")

        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-RESERVATION",
                lambda: launch(
                    "core",
                    reservation_invocation,
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "pass"],
                    popen_factory=reservation_spawn_spy,
                ),
            )
            verify_invocation_reservation(reservation_fd, held_reservation)
            if any(policies.glob(f"sandbox-core-{reservation_invocation}.*")):
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "contending launcher changed owner receipts",
                )
        finally:
            release_invocation_reservation(reservation_fd, held_reservation)
            os.close(reservation_fd)
        if reservation_spawn_calls != 0 or (policies / reservation_name).exists():
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST",
                "reservation contention was not fail-closed",
            )

        atomic_swap_name = "atomic-path-replacement.log"
        atomic_swap_path = policies / atomic_swap_name
        atomic_fd = os.open(
            policies,
            os.O_RDONLY
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0),
        )

        def replace_atomic_path() -> None:
            atomic_swap_path.unlink()
            atomic_swap_path.write_bytes(b"replacement")
            os.chmod(atomic_swap_path, 0o400)

        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-LOG",
                lambda: atomic_receipt(
                    atomic_fd,
                    atomic_swap_name,
                    b"original",
                    before_final_path_check=replace_atomic_path,
                ),
            )
        finally:
            os.close(atomic_fd)
        if atomic_swap_path.read_bytes() != b"replacement":
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST", "atomic path replacement was not detected"
            )
        atomic_swap_path.unlink()

        raw_swap_invocation = "raw-path-replacement"
        raw_swap_contexts = prepare_contexts(raw_swap_invocation)
        raw_swap_path = policies / f"sandbox-core-{raw_swap_invocation}.stdout.log"

        def replace_raw_before_marker() -> None:
            raw_swap_path.unlink()
            raw_swap_path.write_bytes(b"replacement")
            os.chmod(raw_swap_path, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                raw_swap_invocation,
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "print('raw')"],
                raw_swap_contexts,
                before_metadata_publish=replace_raw_before_marker,
            ),
        )
        if any(policies.glob(f"sandbox-core-{raw_swap_invocation}.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "raw replacement survived rollback")

        release_failure_invocation = "reservation-release-failure"
        release_failure_contexts = prepare_contexts(release_failure_invocation)
        release_failure_path = (
            policies / f".sandbox-core-{release_failure_invocation}.reservation"
        )

        def mutate_reservation_before_release() -> None:
            os.chmod(release_failure_path, 0o600)

        expect_error(
            "PF-SANDBOX-LAUNCH-RESERVATION",
            lambda: launch(
                "core",
                release_failure_invocation,
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "print('reserved')"],
                release_failure_contexts,
                before_reservation_release=mutate_reservation_before_release,
            ),
        )
        if any(policies.glob(f"*sandbox-core-{release_failure_invocation}*")):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST",
                "reservation release failure left receipts or marker",
            )

        metadata_swap_invocation = "metadata-path-replacement"
        metadata_swap_contexts = prepare_contexts(metadata_swap_invocation)
        metadata_swap_path = (
            policies / f"sandbox-core-{metadata_swap_invocation}.receipt.json"
        )

        def replace_metadata_after_publish() -> None:
            metadata_swap_path.unlink()
            metadata_swap_path.write_bytes(b"replacement")
            os.chmod(metadata_swap_path, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                metadata_swap_invocation,
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                metadata_swap_contexts,
                before_final_publication_check=replace_metadata_after_publish,
            ),
        )
        if any(policies.glob(f"sandbox-core-{metadata_swap_invocation}.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "metadata replacement survived rollback")

        directory_swap_invocation = "directory-path-replacement"
        directory_swap_contexts = prepare_contexts(directory_swap_invocation)
        detached_policies = temp_root / "detached-policies"

        def replace_directory_after_publish() -> None:
            policies.rename(detached_policies)
            policies.mkdir()
            os.chmod(policies, 0o700)

        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-LAYOUT",
                lambda: launch(
                    "core",
                    directory_swap_invocation,
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "pass"],
                    directory_swap_contexts,
                    before_final_publication_check=replace_directory_after_publish,
                ),
            )
            if any(policies.iterdir()):
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "replacement directory received a marker",
                )
        finally:
            policies.rmdir()
            detached_policies.rename(policies)
        if any(policies.glob(f"sandbox-core-{directory_swap_invocation}.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "detached directory retained receipts")

        for preexisting_kind in ("stdout.log", "stderr.log", "receipt.json"):
            invocation = f"preexisting-{preexisting_kind.split('.')[0]}"
            preexisting_contexts = prepare_contexts(invocation)
            preexisting = policies / f"sandbox-core-{invocation}.{preexisting_kind}"
            preexisting.write_bytes(b"occupied")
            os.chmod(preexisting, 0o400)
            marker = work / f"{invocation}.spawned"
            expect_error(
                "PF-SANDBOX-LAUNCH-LOG",
                lambda current_invocation=invocation, current_contexts=preexisting_contexts, current_marker=marker: (
                    launch(
                        "core",
                        current_invocation,
                        temp_root,
                        validated_policies,
                        policy_bytes,
                        environment,
                        [
                            sys.executable,
                            "-I",
                            "-S",
                            "-c",
                            f"open({str(current_marker)!r},'wb').close()",
                        ],
                        current_contexts,
                    )
                ),
            )
            if marker.exists():
                fail("PF-SANDBOX-LAUNCH-SELFTEST", "preexisting output allowed spawn")
            preexisting.unlink()

        legacy_stale_invocation = "legacy-stale-marker"
        legacy_stale = policies / f"sandbox-core-{legacy_stale_invocation}.receipt.json"
        legacy_stale.write_bytes(b"stale")
        os.chmod(legacy_stale, 0o400)
        legacy_spawn_marker = work / "legacy-stale-spawned"
        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                legacy_stale_invocation,
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [
                    sys.executable,
                    "-I",
                    "-S",
                    "-c",
                    f"open({str(legacy_spawn_marker)!r},'wb').close()",
                ],
            ),
        )
        if legacy_spawn_marker.exists():
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "legacy stale marker allowed spawn")
        legacy_stale.unlink()

        legacy_race_invocation = "legacy-marker-race"
        legacy_race_marker = (
            policies / f"sandbox-core-{legacy_race_invocation}.receipt.json"
        )

        def inject_legacy_marker() -> None:
            legacy_race_marker.write_bytes(b"counterfeit")
            os.chmod(legacy_race_marker, 0o400)

        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                legacy_race_invocation,
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
                before_final_publication_check=inject_legacy_marker,
            ),
        )
        if any(policies.glob(f"sandbox-core-{legacy_race_invocation}.*")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "legacy marker race survived rollback")

        identity_swap_invocation = "validated-directory-swap"
        identity_spawn_calls = 0
        original_policies = temp_root / "validated-policies-original"

        def identity_spawn_spy(*_args, **_kwargs):  # type: ignore[no-untyped-def]
            nonlocal identity_spawn_calls
            identity_spawn_calls += 1
            raise AssertionError("replaced policies directory reached Popen")

        policies.rename(original_policies)
        policies.mkdir()
        os.chmod(policies, 0o700)
        replacement_policy = policies / "core.sb"
        replacement_policy.write_bytes(policy_bytes)
        os.chmod(replacement_policy, 0o400)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-LAYOUT",
                lambda: launch(
                    "core",
                    identity_swap_invocation,
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "pass"],
                    expected_policies_identity=validated_policies_identity,
                    popen_factory=identity_spawn_spy,
                ),
            )
            if any(policies.glob(f"sandbox-core-{identity_swap_invocation}.*")):
                fail(
                    "PF-SANDBOX-LAUNCH-SELFTEST",
                    "replacement directory received receipts",
                )
        finally:
            replacement_policy.unlink()
            policies.rmdir()
            original_policies.rename(policies)
        if identity_spawn_calls != 0 or any(
            policies.glob(f"sandbox-core-{identity_swap_invocation}.*")
        ):
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST",
                "validated directory replacement was accepted",
            )

        policies.rename(original_policies)
        os.symlink(original_policies.name, policies)
        try:
            expect_error(
                "PF-SANDBOX-LAUNCH-LAYOUT",
                lambda: launch(
                    "core",
                    "validated-directory-symlink",
                    temp_root,
                    validated_policies,
                    policy_bytes,
                    environment,
                    [sys.executable, "-I", "-S", "-c", "pass"],
                    expected_policies_identity=validated_policies_identity,
                    popen_factory=identity_spawn_spy,
                ),
            )
        finally:
            policies.unlink()
            original_policies.rename(policies)
        if identity_spawn_calls != 0:
            fail(
                "PF-SANDBOX-LAUNCH-SELFTEST",
                "symlinked policies directory reached spawn",
            )

        observed_runner, _ = observe_regular_file(
            runner,
            "synthetic executable",
            maximum=MAX_CONTEXT_BYTES,
            executable=True,
            capture=False,
        )
        os.chmod(runner, 0o700)
        runner.write_bytes(b"#!/bin/bash\nexit 0\n")
        os.chmod(runner, 0o500)
        expect_error(
            "PF-SANDBOX-LAUNCH-OBSERVATION",
            lambda: verify_file_observation(observed_runner, "synthetic executable"),
        )

        expect_error("PF-SANDBOX-LAUNCH-ID", lambda: validate_invocation("Invalid_ID"))
        expect_error("PF-SANDBOX-LAUNCH-ID", lambda: validate_invocation("x" * 49))
        expect_error(
            "PF-SANDBOX-LAUNCH-LOG",
            lambda: launch(
                "core",
                "fd-close",
                temp_root,
                validated_policies,
                policy_bytes,
                environment,
                [sys.executable, "-I", "-S", "-c", "pass"],
            ),
        )
        if any(policies.glob(".sandbox-*.reservation")):
            fail("PF-SANDBOX-LAUNCH-SELFTEST", "invocation reservation leaked")
    print("sandbox-exec-launcher: self-test ok")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(prog="sandbox-exec-launcher", allow_abbrev=False)
    subcommands = command.add_subparsers(dest="action", required=True)
    run = subcommands.add_parser("run", allow_abbrev=False)
    run.add_argument("stage", choices=STAGES)
    run.add_argument("--invocation", required=True)
    run.add_argument("--temp-root", required=True)
    run.add_argument("--asset-cache")
    run.add_argument("--runtime-port", type=int)
    run.add_argument("--receipt-run-context")
    run.add_argument("--receipt-invocation-context")
    test = subcommands.add_parser("self-test", allow_abbrev=False)
    test.set_defaults(handler=lambda _args: self_test())
    return command


def run_command(
    args: argparse.Namespace,
    *,
    popen_factory: Callable[..., subprocess.Popen[bytes]] | None = None,
) -> int:
    invocation = validate_invocation(args.invocation)
    temp_root, _, policies, policy_bytes, policies_identity = validate_layout(
        args.stage, args.temp_root
    )
    contexts = load_receipt_contexts(
        args.receipt_run_context,
        args.receipt_invocation_context,
        stage=args.stage,
        invocation=invocation,
        temp_root=temp_root,
    )
    environment = derive_environment(
        args.stage, temp_root, args.asset_cache, args.runtime_port
    )
    validate_policy_snapshot(policy_bytes, args.stage, args.runtime_port)
    validate_runtime_port(args.stage, args.runtime_port, environment, policy_bytes)
    command = validate_command(args.command)
    return launch(
        args.stage,
        invocation,
        temp_root,
        policies,
        policy_bytes,
        environment,
        command,
        contexts,
        expected_policies_identity=policies_identity,
        popen_factory=popen_factory,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        require_direct_xcode_python()
        raw = list(sys.argv[1:] if argv is None else argv)
        sandbox_command: list[str] = []
        # Split explicitly so launcher options may follow STAGE; REMAINDER would
        # otherwise swallow them into the sandboxed command.
        if raw and raw[0] == "run" and "--" in raw:
            delimiter = raw.index("--")
            sandbox_command = raw[delimiter + 1 :]
            raw = raw[:delimiter]
        args = parser().parse_args(raw)
        if args.action == "run":
            args.command = sandbox_command
            return run_command(args)
        args.handler(args)
        return 0
    except (LaunchError, OSError, UnicodeError, subprocess.SubprocessError) as error:
        code = error.code if isinstance(error, LaunchError) else "PF-SANDBOX-LAUNCH"
        print(f"sandbox-exec-launcher: {code}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
