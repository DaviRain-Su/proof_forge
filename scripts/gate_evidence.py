#!/usr/bin/env python3
"""Strict ProofForge V2 gate-evidence validation and publication.

This module intentionally uses only the Python standard library.  Gate
invocations must use the Stage-0-pinned direct Python with ``-I -S`` so user and
site packages cannot influence parsing, validation, or canonical encoding.
"""

from __future__ import annotations

import argparse
import ast
import copy
import datetime as dt
import hashlib
import json
import os
import posixpath
import re
import secrets
import stat
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import NoReturn


SCHEMA = "proof-forge.evidence.v1"
ARTIFACT_SET_DOMAIN = b"pf.evidence.artifact-set.v1\x00"
MAX_INPUT_BYTES = 4 * 1024 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_BUNDLE_FILES = 1024
MAX_BUNDLE_FILE_BYTES = 64 * 1024 * 1024
MAX_BUNDLE_TOTAL_BYTES = 256 * 1024 * 1024

SHA256_RE = re.compile(r"[0-9a-f]{64}")
GIT_OBJECT_RE = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
EVIDENCE_ID_RE = re.compile(r"EV-[0-9]{8}-[0-9]{4}")
TASK_ID_RE = re.compile(r"TASK-[A-Z0-9]+(?:-[A-Z0-9]+)*")
TEST_ID_RE = re.compile(r"TST-[A-Z0-9]+(?:-[A-Z0-9]+)*")
SAFE_ID_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?")
MEDIA_TYPE_RE = re.compile(
    r"[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*/"
    r"[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*(?:;[A-Za-z0-9_.+-]+=[A-Za-z0-9_.+-]+)*"
)
UTC_RE = re.compile(
    r"[0-9]{4}-(?:0[1-9]|1[0-2])-"
    r"(?:0[1-9]|[12][0-9]|3[01])T"
    r"(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]"
    r"(?:\.[0-9]{3})?Z"
)


class EvidenceError(RuntimeError):
    """Stable, user-facing evidence rejection."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> NoReturn:
    raise EvidenceError(code, message)


def _where(parent: str, field: str) -> str:
    return f"{parent}.{field}" if parent else field


def _diagnostic_repr(value: str, *, limit: int = 96) -> str:
    """Return an ASCII-only, bounded representation safe for diagnostics."""
    rendered = ascii(value)
    if len(rendered) > limit:
        rendered = rendered[: limit - 3] + "..."
    return rendered


def _require_json_key(key: object, where: str) -> str:
    if not isinstance(key, str):
        fail("PF-EVIDENCE-KEY", f"{where} contains a non-string object key")
    if len(key) > 256 or not key or any(ord(char) < 0x21 or ord(char) > 0x7E for char in key):
        fail(
            "PF-EVIDENCE-KEY",
            f"{where} contains an object key outside the ASCII-graphic/256 profile: "
            f"{_diagnostic_repr(key)}",
        )
    return key


def require_sorted_unique(keys: list[object], where: str) -> None:
    try:
        unique_count = len(set(keys))
        sorted_keys = sorted(keys)
    except TypeError:
        fail("PF-EVIDENCE-SCHEMA", f"{where} has a non-comparable canonical key")
    if unique_count != len(keys):
        fail("PF-EVIDENCE-INVARIANT", f"{where} contains duplicate entries")
    if keys != sorted_keys:
        fail("PF-EVIDENCE-INVARIANT", f"{where} must use stable canonical order")


def require_keys(
    value: object,
    required: set[str],
    where: str,
    optional: set[str] | None = None,
) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("PF-EVIDENCE-SCHEMA", f"{where} must be an object")
    optional = optional or set()
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required - optional)
    if missing:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} is missing required fields: {', '.join(missing)}",
        )
    if unknown:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} contains unknown fields: "
            f"{', '.join(_diagnostic_repr(field) for field in unknown)}",
        )
    return value


def require_array(value: object, where: str, *, nonempty: bool = False) -> list[object]:
    if not isinstance(value, list):
        fail("PF-EVIDENCE-SCHEMA", f"{where} must be an array")
    if nonempty and not value:
        fail("PF-EVIDENCE-INVARIANT", f"{where} must be non-empty")
    return value


def require_text(
    value: object,
    where: str,
    *,
    allow_empty: bool = False,
    ascii_only: bool = False,
    max_bytes: int = MAX_STRING_BYTES,
) -> str:
    if not isinstance(value, str) or (not allow_empty and not value):
        qualifier = "a string" if allow_empty else "a non-empty string"
        fail("PF-EVIDENCE-SCHEMA", f"{where} must be {qualifier}")
    if "\x00" in value or any(0xD800 <= ord(char) <= 0xDFFF for char in value):
        fail("PF-EVIDENCE-SCHEMA", f"{where} contains an invalid Unicode scalar")
    if ascii_only and not value.isascii():
        fail("PF-EVIDENCE-SCHEMA", f"{where} must be ASCII")
    if len(value.encode("utf-8")) > max_bytes:
        fail("PF-EVIDENCE-LIMIT", f"{where} exceeds {max_bytes} UTF-8 bytes")
    return value


def require_bool(value: object, where: str) -> bool:
    if type(value) is not bool:
        fail("PF-EVIDENCE-SCHEMA", f"{where} must be a boolean")
    return value


def require_int(
    value: object,
    where: str,
    *,
    minimum: int = 0,
    maximum: int = MAX_SAFE_INTEGER,
) -> int:
    if type(value) is not int or value < minimum or value > maximum:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} must be an integer in [{minimum}, {maximum}]",
        )
    return value


def require_enum(value: object, allowed: set[str], where: str) -> str:
    text = require_text(value, where, ascii_only=True)
    if text not in allowed:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} must be one of: {', '.join(sorted(allowed))}",
        )
    return text


def require_pattern(value: object, pattern: re.Pattern[str], where: str) -> str:
    text = require_text(value, where, ascii_only=True)
    if pattern.fullmatch(text) is None:
        fail("PF-EVIDENCE-SCHEMA", f"{where} has an invalid format")
    return text


def require_sha256(value: object, where: str) -> str:
    return require_pattern(value, SHA256_RE, where)


def require_nullable_sha256(value: object, where: str) -> str | None:
    if value is None:
        return None
    return require_sha256(value, where)


def require_safe_id(value: object, where: str) -> str:
    return require_pattern(value, SAFE_ID_RE, where)


def require_relative_path(value: object, where: str, *, allow_dot: bool = False) -> str:
    path = require_text(value, where, max_bytes=4096)
    if unicodedata.normalize("NFC", path) != path:
        fail("PF-EVIDENCE-PATH", f"{where} must be Unicode NFC")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in path):
        fail("PF-EVIDENCE-PATH", f"{where} contains an ASCII control character")
    if path == "." and allow_dot:
        return path
    if (
        path == "."
        or path.startswith("/")
        or path.endswith("/")
        or "\\" in path
        or posixpath.normpath(path) != path
    ):
        fail("PF-EVIDENCE-PATH", f"{where} must be a normalized relative POSIX path")
    parts = path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        fail("PF-EVIDENCE-PATH", f"{where} contains a forbidden path component")
    return path


def require_utc(value: object, where: str) -> tuple[str, dt.datetime]:
    text = require_text(value, where, ascii_only=True)
    if UTC_RE.fullmatch(text) is None:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} must be RFC 3339 UTC with zero or three fractional digits",
        )
    try:
        parsed = dt.datetime.fromisoformat(text[:-1] + "+00:00")
    except ValueError:
        fail("PF-EVIDENCE-SCHEMA", f"{where} is not a real UTC timestamp")
    return text, parsed


def _reject_float(_: str) -> NoReturn:
    fail("PF-EVIDENCE-NUMBER", "floating-point JSON numbers are forbidden")


def _parse_safe_int(text: str) -> int:
    value = int(text, 10)
    if abs(value) > MAX_SAFE_INTEGER:
        fail(
            "PF-EVIDENCE-NUMBER",
            f"JSON integer exceeds the interoperable range: {text}",
        )
    return value


def _reject_constant(text: str) -> NoReturn:
    fail("PF-EVIDENCE-NUMBER", f"non-finite JSON number is forbidden: {text}")


def _object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        _require_json_key(key, "JSON")
        if key in result:
            fail(
                "PF-EVIDENCE-DUPLICATE-KEY",
                f"duplicate JSON key: {_diagnostic_repr(key)}",
            )
        result[key] = value
    return result


def _validate_json_tree(value: object) -> None:
    nodes = 0
    stack: list[tuple[object, int, str]] = [(value, 0, "$")]
    while stack:
        current, depth, where = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES:
            fail("PF-EVIDENCE-LIMIT", f"JSON exceeds {MAX_JSON_NODES} values")
        if depth > MAX_JSON_DEPTH:
            fail("PF-EVIDENCE-LIMIT", f"JSON exceeds depth {MAX_JSON_DEPTH}")
        if current is None or type(current) is bool:
            continue
        if type(current) is int:
            if abs(current) > MAX_SAFE_INTEGER:
                fail("PF-EVIDENCE-NUMBER", f"{where} contains an unsafe integer")
            continue
        if isinstance(current, float):
            fail("PF-EVIDENCE-NUMBER", f"{where} contains a float")
        if isinstance(current, str):
            require_text(current, where, allow_empty=True)
            continue
        if isinstance(current, list):
            for index in range(len(current) - 1, -1, -1):
                stack.append((current[index], depth + 1, f"{where}[{index}]"))
            continue
        if isinstance(current, dict):
            for key, item in current.items():
                _require_json_key(key, where)
                stack.append((item, depth + 1, _where(where, key)))
            continue
        fail("PF-EVIDENCE-SCHEMA", f"{where} contains a non-JSON value")


def decode_json(data: bytes) -> object:
    if len(data) > MAX_INPUT_BYTES:
        fail("PF-EVIDENCE-LIMIT", f"evidence exceeds {MAX_INPUT_BYTES} bytes")
    if data.startswith(b"\xef\xbb\xbf"):
        fail("PF-EVIDENCE-JSON", "UTF-8 BOM is forbidden")
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        fail("PF-EVIDENCE-JSON", f"evidence is not UTF-8: byte {exc.start}")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_object_pairs,
            parse_int=_parse_safe_int,
            parse_float=_reject_float,
            parse_constant=_reject_constant,
        )
    except EvidenceError:
        raise
    except (json.JSONDecodeError, RecursionError, ValueError) as exc:
        fail("PF-EVIDENCE-JSON", f"invalid JSON: {exc}")
    _validate_json_tree(value)
    return value


def canonical_bytes(value: object) -> bytes:
    """Encode the PF integer-only/ASCII-key JCS profile deterministically."""
    _validate_json_tree(value)
    try:
        text = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            check_circular=True,
            separators=(",", ":"),
            sort_keys=True,
        )
    except (TypeError, ValueError, RecursionError) as exc:
        fail("PF-EVIDENCE-JSON", f"cannot encode canonical JSON: {exc}")
    # The restricted PF profile retains the JCS no-trailing-whitespace rule;
    # it deliberately does not claim support for the full RFC 8785 number/key
    # domain.
    return text.encode("utf-8")


def artifact_set_sha256(artifacts: object) -> str:
    """Hash the canonical artifact array in its explicit evidence domain."""
    return hashlib.sha256(ARTIFACT_SET_DOMAIN + canonical_bytes(artifacts)).hexdigest()


def _validate_gate(value: object) -> tuple[str, str]:
    where = "$.gate"
    obj = require_keys(value, {"id", "taskId", "testIds", "qualification"}, where)
    gate_id = require_safe_id(obj["id"], _where(where, "id"))
    require_pattern(obj["taskId"], TASK_ID_RE, _where(where, "taskId"))
    tests = require_array(obj["testIds"], _where(where, "testIds"), nonempty=True)
    parsed_tests = [
        require_pattern(test, TEST_ID_RE, f"{where}.testIds[{index}]")
        for index, test in enumerate(tests)
    ]
    require_sorted_unique(parsed_tests, f"{where}.testIds")
    qualification = require_enum(
        obj["qualification"], {"development", "formal"}, _where(where, "qualification")
    )
    return qualification, gate_id


def _validate_repository(value: object) -> dict[str, object]:
    where = "$.repository"
    obj = require_keys(
        value,
        {
            "commit",
            "subtree",
            "treeObjectId",
            "anchorSource",
            "dirty",
            "dirtyDigest",
            "unchangedDuringRun",
            "archive",
        },
        where,
    )
    require_pattern(obj["commit"], GIT_OBJECT_RE, _where(where, "commit"))
    require_relative_path(obj["subtree"], _where(where, "subtree"), allow_dot=True)
    require_pattern(obj["treeObjectId"], GIT_OBJECT_RE, _where(where, "treeObjectId"))
    require_enum(
        obj["anchorSource"],
        {"derived-development", "external"},
        _where(where, "anchorSource"),
    )
    dirty = require_bool(obj["dirty"], _where(where, "dirty"))
    dirty_digest = require_nullable_sha256(obj["dirtyDigest"], _where(where, "dirtyDigest"))
    require_bool(obj["unchangedDuringRun"], _where(where, "unchangedDuringRun"))
    if dirty != (dirty_digest is not None):
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.dirtyDigest must be present exactly when dirty is true",
        )
    archive_where = _where(where, "archive")
    archive = require_keys(obj["archive"], {"format", "sha256", "size"}, archive_where)
    require_enum(archive["format"], {"git-tar"}, _where(archive_where, "format"))
    require_sha256(archive["sha256"], _where(archive_where, "sha256"))
    require_int(archive["size"], _where(archive_where, "size"), minimum=1)
    return obj


def _validate_host(value: object) -> dict[str, object]:
    where = "$.hostAttestation"
    fields = {
        "scope",
        "remoteAttestation",
        "profileId",
        "eligibleForHermetic",
        "bootstrapLockSha256",
        "hostProfileLockSha256",
        "toolchainLockSha256",
        "launcherSha256",
        "verifierSha256",
        "observationSha256",
    }
    obj = require_keys(value, fields, where)
    require_enum(obj["scope"], {"local-point-in-time"}, _where(where, "scope"))
    remote_attestation = require_bool(
        obj["remoteAttestation"], _where(where, "remoteAttestation")
    )
    if remote_attestation:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.remoteAttestation must remain false until a remote protocol is specified",
        )
    require_safe_id(obj["profileId"], _where(where, "profileId"))
    require_bool(obj["eligibleForHermetic"], _where(where, "eligibleForHermetic"))
    for field in sorted(
        fields - {"scope", "remoteAttestation", "profileId", "eligibleForHermetic"}
    ):
        require_sha256(obj[field], _where(where, field))
    return obj


def _validate_environment(value: object) -> dict[str, object]:
    where = "$.environment"
    obj = require_keys(
        value,
        {
            "os",
            "arch",
            "environmentSha256",
            "sourceDateEpoch",
            "cleanRoom",
            "buildCache",
            "assetCache",
        },
        where,
    )
    require_text(obj["os"], _where(where, "os"), max_bytes=256)
    require_safe_id(obj["arch"], _where(where, "arch"))
    require_sha256(obj["environmentSha256"], _where(where, "environmentSha256"))
    require_int(obj["sourceDateEpoch"], _where(where, "sourceDateEpoch"))
    require_bool(obj["cleanRoom"], _where(where, "cleanRoom"))
    require_safe_id(obj["buildCache"], _where(where, "buildCache"))
    require_safe_id(obj["assetCache"], _where(where, "assetCache"))
    return obj


def _validate_sandbox_policies(value: object) -> list[dict[str, object]]:
    policies = require_array(value, "$.sandboxPolicies", nonempty=True)
    result: list[dict[str, object]] = []
    ids: set[str] = set()
    for index, policy_value in enumerate(policies):
        where = f"$.sandboxPolicies[{index}]"
        policy = require_keys(
            policy_value,
            {
                "id",
                "engine",
                "engineSha256",
                "defaultAction",
                "network",
                "templateSha256",
                "renderedSha256",
                "probes",
            },
            where,
            optional={"networkPort"},
        )
        policy_id = require_safe_id(policy["id"], _where(where, "id"))
        if policy_id in ids:
            fail("PF-EVIDENCE-INVARIANT", f"duplicate sandbox policy id: {policy_id}")
        ids.add(policy_id)
        require_safe_id(policy["engine"], _where(where, "engine"))
        require_sha256(policy["engineSha256"], _where(where, "engineSha256"))
        require_enum(policy["defaultAction"], {"allow", "deny"}, _where(where, "defaultAction"))
        network = require_enum(
            policy["network"],
            {"deny-all", "exact-local-port", "loopback-only"},
            _where(where, "network"),
        )
        if network == "exact-local-port":
            if "networkPort" not in policy:
                fail(
                    "PF-EVIDENCE-SCHEMA",
                    f"{where}.networkPort is required for exact-local-port",
                )
            require_int(
                policy["networkPort"],
                _where(where, "networkPort"),
                minimum=1,
                maximum=65535,
            )
        elif "networkPort" in policy:
            fail(
                "PF-EVIDENCE-INVARIANT",
                f"{where}.networkPort is forbidden unless network is exact-local-port",
            )
        require_sha256(policy["templateSha256"], _where(where, "templateSha256"))
        require_sha256(policy["renderedSha256"], _where(where, "renderedSha256"))
        probes = require_array(policy["probes"], _where(where, "probes"), nonempty=True)
        probe_ids: set[str] = set()
        for probe_index, probe_value in enumerate(probes):
            probe_where = f"{where}.probes[{probe_index}]"
            probe = require_keys(probe_value, {"id", "status"}, probe_where)
            probe_id = require_safe_id(probe["id"], _where(probe_where, "id"))
            if probe_id in probe_ids:
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    f"{where}.probes contains duplicate id: {probe_id}",
                )
            probe_ids.add(probe_id)
            require_enum(
                probe["status"], {"passed", "failed", "skipped"}, _where(probe_where, "status")
            )
        probe_order = [probe["id"] for probe in probes]
        require_sorted_unique(probe_order, f"{where}.probes")
        result.append(policy)
    policy_order = [policy["id"] for policy in result]
    require_sorted_unique(policy_order, "$.sandboxPolicies")
    return result


def _validate_tools(value: object) -> list[dict[str, object]]:
    tools = require_array(value, "$.tools", nonempty=True)
    result: list[dict[str, object]] = []
    ids: set[str] = set()
    for index, tool_value in enumerate(tools):
        where = f"$.tools[{index}]"
        tool = require_keys(
            tool_value,
            {
                "id",
                "version",
                "source",
                "assetSha256",
                "executableSha256",
                "closureSha256",
            },
            where,
        )
        tool_id = require_safe_id(tool["id"], _where(where, "id"))
        if tool_id in ids:
            fail("PF-EVIDENCE-INVARIANT", f"duplicate tool id: {tool_id}")
        ids.add(tool_id)
        require_text(tool["version"], _where(where, "version"), max_bytes=512)
        require_text(tool["source"], _where(where, "source"), max_bytes=2048)
        require_nullable_sha256(tool["assetSha256"], _where(where, "assetSha256"))
        require_sha256(tool["executableSha256"], _where(where, "executableSha256"))
        require_sha256(tool["closureSha256"], _where(where, "closureSha256"))
        result.append(tool)
    tool_order = [tool["id"] for tool in result]
    require_sorted_unique(tool_order, "$.tools")
    return result


def _validate_command(value: object, result: str) -> dict[str, object]:
    where = "$.command"
    obj = require_keys(
        value,
        {"argv", "cwdRelative", "startedUtc", "endedUtc", "durationMs", "attempts"},
        where,
    )
    argv = require_array(obj["argv"], _where(where, "argv"), nonempty=True)
    for index, argument in enumerate(argv):
        require_text(argument, f"{where}.argv[{index}]", max_bytes=65536)
    require_relative_path(obj["cwdRelative"], _where(where, "cwdRelative"), allow_dot=True)
    _, started = require_utc(obj["startedUtc"], _where(where, "startedUtc"))
    _, ended = require_utc(obj["endedUtc"], _where(where, "endedUtc"))
    duration = require_int(obj["durationMs"], _where(where, "durationMs"))
    delta = ended - started
    elapsed = delta.days * 86_400_000 + delta.seconds * 1000 + delta.microseconds // 1000
    if ended < started or duration != elapsed:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.durationMs must equal endedUtc - startedUtc in milliseconds",
        )
    attempts = require_array(
        obj["attempts"], _where(where, "attempts"), nonempty=result != "skipped"
    )
    for index, attempt_value in enumerate(attempts):
        attempt_where = f"{where}.attempts[{index}]"
        attempt = require_keys(
            attempt_value,
            {"number", "exitCode", "signal", "timedOut", "stdoutLog", "stderrLog"},
            attempt_where,
        )
        number = require_int(attempt["number"], _where(attempt_where, "number"), minimum=1)
        if number != index + 1:
            fail(
                "PF-EVIDENCE-INVARIANT",
                f"{attempt_where}.number must be {index + 1}",
            )
        exit_code = attempt["exitCode"]
        if exit_code is not None:
            require_int(exit_code, _where(attempt_where, "exitCode"), maximum=255)
        signal_value = attempt["signal"]
        if signal_value is not None:
            require_int(signal_value, _where(attempt_where, "signal"), minimum=1, maximum=255)
        if exit_code is not None and signal_value is not None:
            fail(
                "PF-EVIDENCE-INVARIANT",
                f"{attempt_where} cannot have both exitCode and signal",
            )
        timed_out = require_bool(attempt["timedOut"], _where(attempt_where, "timedOut"))
        if timed_out:
            if exit_code is not None or signal_value is not None:
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    f"{attempt_where} timeout must have null exitCode and signal",
                )
        elif (exit_code is None) == (signal_value is None):
            fail(
                "PF-EVIDENCE-INVARIANT",
                f"{attempt_where} must have exactly one exitCode or signal terminal state",
            )
        require_relative_path(attempt["stdoutLog"], _where(attempt_where, "stdoutLog"))
        require_relative_path(attempt["stderrLog"], _where(attempt_where, "stderrLog"))
    return obj


def _validate_inputs(value: object) -> list[dict[str, object]]:
    entries = require_array(value, "$.inputs")
    result: list[dict[str, object]] = []
    keys: set[tuple[str, str]] = set()
    for index, entry_value in enumerate(entries):
        where = f"$.inputs[{index}]"
        entry = require_keys(entry_value, {"role", "path", "sha256", "size"}, where)
        role = require_safe_id(entry["role"], _where(where, "role"))
        path = require_relative_path(entry["path"], _where(where, "path"))
        require_sha256(entry["sha256"], _where(where, "sha256"))
        require_int(entry["size"], _where(where, "size"))
        key = (role, path)
        if key in keys:
            fail("PF-EVIDENCE-INVARIANT", f"duplicate input role/path: {role} {path}")
        keys.add(key)
        result.append(entry)
    input_order = [(entry["role"], entry["path"]) for entry in result]
    require_sorted_unique(input_order, "$.inputs")
    return result


def _validate_artifacts(value: object) -> list[dict[str, object]]:
    entries = require_array(value, "$.artifacts")
    result: list[dict[str, object]] = []
    paths: set[str] = set()
    for index, entry_value in enumerate(entries):
        where = f"$.artifacts[{index}]"
        entry = require_keys(
            entry_value,
            {"target", "role", "path", "mediaType", "sha256", "size", "retained"},
            where,
        )
        require_safe_id(entry["target"], _where(where, "target"))
        require_safe_id(entry["role"], _where(where, "role"))
        path = require_relative_path(entry["path"], _where(where, "path"))
        require_pattern(entry["mediaType"], MEDIA_TYPE_RE, _where(where, "mediaType"))
        require_sha256(entry["sha256"], _where(where, "sha256"))
        require_int(entry["size"], _where(where, "size"))
        require_bool(entry["retained"], _where(where, "retained"))
        if path in paths:
            fail("PF-EVIDENCE-INVARIANT", f"duplicate artifact path: {path}")
        paths.add(path)
        result.append(entry)
    artifact_order = [
        (entry["target"], entry["role"], entry["path"]) for entry in result
    ]
    require_sorted_unique(artifact_order, "$.artifacts")
    return result


def _validate_observations(value: object) -> list[dict[str, object]]:
    entries = require_array(value, "$.observations")
    result: list[dict[str, object]] = []
    for index, entry_value in enumerate(entries):
        where = f"$.observations[{index}]"
        entry = require_keys(
            entry_value,
            {"step", "status", "return", "logicalState", "effects", "errorClass"},
            where,
        )
        require_safe_id(entry["step"], _where(where, "step"))
        require_enum(
            entry["status"], {"passed", "failed", "skipped"}, _where(where, "status")
        )
        if entry["errorClass"] is not None:
            require_safe_id(entry["errorClass"], _where(where, "errorClass"))
        result.append(entry)
    return result


def _validate_logs(value: object) -> list[dict[str, object]]:
    entries = require_array(value, "$.logs", nonempty=True)
    result: list[dict[str, object]] = []
    paths: set[str] = set()
    for index, entry_value in enumerate(entries):
        where = f"$.logs[{index}]"
        entry = require_keys(
            entry_value,
            {"path", "sha256", "size", "truncated", "privateDataScan"},
            where,
        )
        path = require_relative_path(entry["path"], _where(where, "path"))
        require_sha256(entry["sha256"], _where(where, "sha256"))
        require_int(entry["size"], _where(where, "size"))
        require_bool(entry["truncated"], _where(where, "truncated"))
        require_enum(
            entry["privateDataScan"],
            {"passed", "failed", "not-run"},
            _where(where, "privateDataScan"),
        )
        if path in paths:
            fail("PF-EVIDENCE-INVARIANT", f"duplicate log path: {path}")
        paths.add(path)
        result.append(entry)
    log_order = [entry["path"] for entry in result]
    require_sorted_unique(log_order, "$.logs")
    return result


def _validate_claim_path_namespace(
    inputs: list[dict[str, object]],
    artifacts: list[dict[str, object]],
    logs: list[dict[str, object]],
) -> None:
    """Keep every declared bundle pathname globally unambiguous."""
    exact: dict[str, str] = {}
    portable: dict[str, tuple[str, str]] = {}
    groups = (("input", inputs), ("artifact", artifacts), ("log", logs))
    for kind, entries in groups:
        for entry in entries:
            path = entry["path"]
            if not isinstance(path, str):
                fail("PF-EVIDENCE-SCHEMA", f"{kind} path must be a string")
            previous_kind = exact.get(path)
            if previous_kind is not None:
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    f"bundle claim path is reused by {previous_kind} and {kind}: "
                    f"{_diagnostic_repr(path)}",
                )
            exact[path] = kind
            alias = unicodedata.normalize("NFC", path).casefold()
            previous = portable.get(alias)
            if previous is not None:
                previous_kind, previous_path = previous
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    f"bundle claim paths collide under NFC/casefold: "
                    f"{previous_kind} {_diagnostic_repr(previous_path)} and "
                    f"{kind} {_diagnostic_repr(path)}",
                )
            portable[alias] = (kind, path)


def _validate_skip_authorization(value: object, result: str) -> None:
    where = "$.skipAuthorization"
    if result == "skipped":
        obj = require_keys(value, {"id", "reason"}, where)
        require_safe_id(obj["id"], _where(where, "id"))
        require_text(obj["reason"], _where(where, "reason"), max_bytes=4096)
    elif value is not None:
        fail("PF-EVIDENCE-INVARIANT", f"{where} must be null unless result is skipped")


def _attempt_is_success(attempt: dict[str, object]) -> bool:
    return (
        attempt["exitCode"] == 0
        and attempt["signal"] is None
        and attempt["timedOut"] is False
    )


def validate_evidence(value: object) -> dict[str, object]:
    """Validate one complete ``proof-forge.evidence.v1`` document."""
    root = require_keys(
        value,
        {
            "schema",
            "id",
            "gate",
            "repository",
            "hostAttestation",
            "environment",
            "sandboxPolicies",
            "tools",
            "command",
            "inputs",
            "artifacts",
            "artifactSetSha256",
            "observations",
            "logs",
            "result",
            "skipAuthorization",
        },
        "$",
    )
    if root["schema"] != SCHEMA:
        fail("PF-EVIDENCE-SCHEMA", f"$.schema must be {SCHEMA!r}")
    evidence_id = require_pattern(root["id"], EVIDENCE_ID_RE, "$.id")
    try:
        evidence_date = dt.datetime.strptime(evidence_id[3:11], "%Y%m%d").date()
    except ValueError:
        fail("PF-EVIDENCE-SCHEMA", "$.id contains a nonexistent UTC calendar date")
    result = require_enum(root["result"], {"passed", "failed", "skipped"}, "$.result")
    qualification, _ = _validate_gate(root["gate"])
    repository = _validate_repository(root["repository"])
    host = _validate_host(root["hostAttestation"])
    environment = _validate_environment(root["environment"])
    policies = _validate_sandbox_policies(root["sandboxPolicies"])
    tools = _validate_tools(root["tools"])
    command = _validate_command(root["command"], result)
    inputs = _validate_inputs(root["inputs"])
    artifacts = _validate_artifacts(root["artifacts"])
    artifact_set = require_sha256(root["artifactSetSha256"], "$.artifactSetSha256")
    expected_artifact_set = artifact_set_sha256(artifacts)
    if artifact_set != expected_artifact_set:
        fail(
            "PF-EVIDENCE-INVARIANT",
            "$.artifactSetSha256 does not match the domain-separated canonical artifact array",
        )
    observations = _validate_observations(root["observations"])
    logs = _validate_logs(root["logs"])
    _validate_claim_path_namespace(inputs, artifacts, logs)
    _validate_skip_authorization(root["skipAuthorization"], result)

    _, ended_utc = require_utc(command["endedUtc"], "$.command.endedUtc")
    if evidence_date != ended_utc.date():
        fail(
            "PF-EVIDENCE-INVARIANT",
            "$.id UTC date must equal $.command.endedUtc UTC date",
        )

    attempts = require_array(command["attempts"], "$.command.attempts")
    if result == "skipped" and attempts:
        fail("PF-EVIDENCE-INVARIANT", "skipped evidence requires command.attempts=[]")
    if result == "passed":
        if not attempts or not _attempt_is_success(attempts[-1]):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "passed evidence requires a successful final command attempt",
            )
        if repository["unchangedDuringRun"] is not True:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "passed evidence requires an unchanged candidate during the run",
            )
        for policy in policies:
            probes = require_array(policy["probes"], "$.sandboxPolicies[].probes")
            if any(probe["status"] != "passed" for probe in probes):
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    "passed evidence requires every sandbox probe to pass",
                )
        if any(observation["status"] != "passed" for observation in observations):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "passed evidence requires every observation to pass",
            )
        if any(log["truncated"] or log["privateDataScan"] == "failed" for log in logs):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "passed evidence rejects truncated logs and failed private-data scans",
            )
        candidate_inputs = [entry for entry in inputs if entry["role"] == "candidate-archive"]
        archive = repository["archive"]
        if not isinstance(archive, dict):
            fail("PF-EVIDENCE-SCHEMA", "$.repository.archive must be an object")
        if (
            len(candidate_inputs) != 1
            or candidate_inputs[0]["sha256"] != archive["sha256"]
            or candidate_inputs[0]["size"] != archive["size"]
        ):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "passed evidence requires exactly one candidate-archive input matching repository.archive",
            )
    elif result == "failed" and attempts:
        final_success = _attempt_is_success(attempts[-1])
        probes_green = all(
            probe["status"] == "passed"
            for policy in policies
            for probe in policy["probes"]
        )
        observations_green = all(
            observation["status"] == "passed" for observation in observations
        )
        logs_green = all(
            not log["truncated"] and log["privateDataScan"] == "passed" for log in logs
        )
        if final_success and probes_green and observations_green and logs_green:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "failed evidence contradicts a successful final attempt and all-green checks",
            )

    log_paths = {entry["path"] for entry in logs}
    for index, attempt in enumerate(attempts):
        for stream in ("stdoutLog", "stderrLog"):
            if attempt[stream] not in log_paths:
                fail(
                    "PF-EVIDENCE-INVARIANT",
                    f"$.command.attempts[{index}].{stream} does not reference $.logs",
                )

    if qualification == "formal" and result == "passed":
        if host["eligibleForHermetic"] is not True:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires an eligible hermetic host",
            )
        if repository["dirty"] is not False or repository["dirtyDigest"] is not None:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires a clean repository",
            )
        if repository["anchorSource"] != "external":
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires an external candidate anchor",
            )
        if environment["cleanRoom"] is not True:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires a clean-room environment",
            )
        if environment["sourceDateEpoch"] != 0:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires sourceDateEpoch 0",
            )
        if not policies or any(policy["defaultAction"] != "deny" for policy in policies):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires deny-default sandbox policies",
            )
        if not any(policy["network"] == "deny-all" for policy in policies):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires at least one deny-all network policy",
            )
        if not tools:
            fail("PF-EVIDENCE-INVARIANT", "formal passed evidence requires tools")
        if len(attempts) != 1:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires exactly one command attempt",
            )
        if not inputs or not artifacts:
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires inputs and artifacts",
            )
        if not observations or any(entry["status"] != "passed" for entry in observations):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires passed observations",
            )
        if any(entry["retained"] is not True for entry in artifacts):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires every artifact to be retained",
            )
        if any(entry["truncated"] or entry["privateDataScan"] != "passed" for entry in logs):
            fail(
                "PF-EVIDENCE-INVARIANT",
                "formal passed evidence requires complete, private-data-scanned logs",
            )

    return root


def _read_regular_file(path: Path) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        fail("PF-EVIDENCE-IO", f"cannot open input {path}: {exc.strerror}")
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            fail("PF-EVIDENCE-IO", f"input is not a regular file: {path}")
        if before.st_size > MAX_INPUT_BYTES:
            fail("PF-EVIDENCE-LIMIT", f"input exceeds {MAX_INPUT_BYTES} bytes: {path}")
        chunks: list[bytes] = []
        remaining = before.st_size + 1
        while remaining:
            chunk = os.read(descriptor, min(remaining, 128 * 1024))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        after = os.fstat(descriptor)
        stable_fields = (
            "st_dev",
            "st_ino",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if any(getattr(before, field) != getattr(after, field) for field in stable_fields):
            fail("PF-EVIDENCE-IO", f"input changed while being read: {path}")
        if len(data) != before.st_size:
            fail("PF-EVIDENCE-IO", f"input length changed while being read: {path}")
        return data
    except EvidenceError:
        raise
    except OSError as exc:
        fail("PF-EVIDENCE-IO", f"cannot read input {path}: {exc.strerror}")
    finally:
        os.close(descriptor)


def load_evidence(path: Path, *, require_canonical: bool) -> tuple[dict[str, object], bytes]:
    data = _read_regular_file(path)
    value = validate_evidence(decode_json(data))
    encoded = canonical_bytes(value)
    if require_canonical and data != encoded:
        fail(
            "PF-EVIDENCE-NONCANONICAL",
            "evidence bytes are not canonical ASCII-key JSON",
        )
    return value, encoded


def _normalized_cli_path(text: str, where: str) -> Path:
    if (
        not text
        or "\x00" in text
        or unicodedata.normalize("NFC", text) != text
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in text)
        or os.path.normpath(text) != text
    ):
        fail("PF-EVIDENCE-PATH", f"{where} must be a normalized filesystem path")
    path = Path(text)
    if path.name in {"", ".", ".."} or any(part == ".." for part in path.parts):
        fail("PF-EVIDENCE-PATH", f"{where} must name a file")
    return path


def _normalized_cli_directory(text: str, where: str) -> Path:
    if (
        not text
        or "\x00" in text
        or unicodedata.normalize("NFC", text) != text
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in text)
        or os.path.normpath(text) != text
    ):
        fail("PF-EVIDENCE-PATH", f"{where} must be a normalized filesystem directory")
    path = Path(text)
    if any(part == ".." for part in path.parts):
        fail("PF-EVIDENCE-PATH", f"{where} contains parent traversal")
    return path


def _require_secure_directory(metadata: os.stat_result, where: str, *, final: bool) -> None:
    if not stat.S_ISDIR(metadata.st_mode):
        fail("PF-EVIDENCE-PUBLISH", f"{where} is not a directory")
    allowed_owners = {0, os.geteuid()}
    if metadata.st_uid not in allowed_owners or (final and metadata.st_uid != os.geteuid()):
        fail("PF-EVIDENCE-PUBLISH", f"{where} has an untrusted owner")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        fail("PF-EVIDENCE-PUBLISH", f"{where} is group/world writable")


def _open_secure_directory(path: Path, where: str) -> int:
    """Open every directory component without following symlinks."""
    if not hasattr(os, "O_NOFOLLOW") or os.open not in os.supports_dir_fd:
        fail("PF-EVIDENCE-PUBLISH", "platform lacks required O_NOFOLLOW/openat support")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    absolute = path.is_absolute()
    anchor = Path("/") if absolute else Path(".")
    components = list(path.parts[1:] if absolute else path.parts)
    if components == ["."]:
        components = []
    try:
        current = os.open(anchor, flags)
    except OSError as exc:
        fail("PF-EVIDENCE-PUBLISH", f"cannot open {where} anchor: {exc.strerror}")
    try:
        _require_secure_directory(
            os.fstat(current), f"{where} anchor", final=not components
        )
        for index, component in enumerate(components):
            if component in {"", ".", ".."}:
                fail("PF-EVIDENCE-PATH", f"{where} contains an unsafe directory component")
            try:
                following = os.open(component, flags, dir_fd=current)
            except OSError as exc:
                fail(
                    "PF-EVIDENCE-PUBLISH",
                    f"cannot safely open {where} component {_diagnostic_repr(component)}: "
                    f"{exc.strerror}",
                )
            try:
                _require_secure_directory(
                    os.fstat(following),
                    f"{where} component {_diagnostic_repr(component)}",
                    final=index == len(components) - 1,
                )
            except BaseException:
                os.close(following)
                raise
            os.close(current)
            current = following
        return current
    except BaseException:
        os.close(current)
        raise


def _same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def _read_open_file(descriptor: int, maximum: int) -> bytes:
    chunks: list[bytes] = []
    remaining = maximum + 1
    while remaining:
        chunk = os.read(descriptor, min(remaining, 128 * 1024))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _cleanup_link(directory: int, name: str) -> None:
    try:
        os.unlink(name, dir_fd=directory)
    except FileNotFoundError:
        return
    except OSError:
        return
    try:
        os.fsync(directory)
    except OSError:
        pass


def atomic_publish(
    data: bytes,
    output: Path,
    *,
    evidence_id: str,
    gate_id: str,
) -> None:
    """Publish bytes without clobbering or trusting a replaced staging path."""
    expected_name = f"{evidence_id}.json"
    if output.name != expected_name or output.parent.name != gate_id:
        fail(
            "PF-EVIDENCE-PATH",
            f"OUTPUT must use <trusted-root>/{gate_id}/{expected_name}",
        )
    parent = output.parent
    name = output.name
    directory = _open_secure_directory(parent, "OUTPUT parent")
    temporary = f".{name}.tmp-{os.getpid()}-{secrets.token_hex(12)}"
    staging: int | None = None
    final: int | None = None
    temporary_present = False
    linked = False
    published = False
    try:
        try:
            staging = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                0o600,
                dir_fd=directory,
            )
            temporary_present = True
            offset = 0
            while offset < len(data):
                written = os.write(staging, data[offset:])
                if written <= 0:
                    fail("PF-EVIDENCE-PUBLISH", "short write while staging evidence")
                offset += written
            os.fsync(staging)
            os.fchmod(staging, 0o444)
            os.fsync(staging)
            staged = os.fstat(staging)
            if (
                not stat.S_ISREG(staged.st_mode)
                or staged.st_uid != os.geteuid()
                or staged.st_size != len(data)
                or staged.st_nlink != 1
                or stat.S_IMODE(staged.st_mode) != 0o444
            ):
                fail("PF-EVIDENCE-PUBLISH", "staging inode failed its pre-link invariant")

            _require_secure_directory(os.fstat(directory), "OUTPUT parent", final=True)
            try:
                os.link(
                    temporary,
                    name,
                    src_dir_fd=directory,
                    dst_dir_fd=directory,
                    follow_symlinks=False,
                )
                linked = True
            except FileExistsError:
                fail("PF-EVIDENCE-EXISTS", f"refusing to replace existing evidence: {output}")

            final = os.open(name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=directory)
            staged_linked = os.fstat(staging)
            final_before = os.fstat(final)
            if (
                not _same_inode(staged_linked, final_before)
                or not stat.S_ISREG(final_before.st_mode)
                or staged_linked.st_nlink != 2
                or final_before.st_nlink != 2
                or final_before.st_size != len(data)
                or final_before.st_uid != os.geteuid()
                or stat.S_IMODE(final_before.st_mode) != 0o444
            ):
                fail(
                    "PF-EVIDENCE-PUBLISH",
                    "published pathname does not identify the open staging inode",
                )
            readback = _read_open_file(final, len(data))
            final_after = os.fstat(final)
            path_after = os.stat(name, dir_fd=directory, follow_symlinks=False)
            stable = ("st_dev", "st_ino", "st_size", "st_nlink", "st_mtime_ns", "st_ctime_ns")
            if (
                any(getattr(final_before, field) != getattr(final_after, field) for field in stable)
                or not _same_inode(staged_linked, path_after)
                or path_after.st_nlink != 2
                or readback != data
                or hashlib.sha256(readback).digest() != hashlib.sha256(data).digest()
            ):
                fail("PF-EVIDENCE-PUBLISH", "published evidence failed exact inode/readback checks")
            os.fsync(final)
            os.fsync(directory)

            os.unlink(temporary, dir_fd=directory)
            temporary_present = False
            os.fsync(directory)
            staged_final = os.fstat(staging)
            path_final = os.stat(name, dir_fd=directory, follow_symlinks=False)
            _require_secure_directory(os.fstat(directory), "OUTPUT parent", final=True)
            if (
                not _same_inode(staged_final, path_final)
                or staged_final.st_nlink != 1
                or path_final.st_nlink != 1
                or path_final.st_size != len(data)
            ):
                fail("PF-EVIDENCE-PUBLISH", "final evidence inode changed during publication")
            published = True
        except EvidenceError:
            raise
        except OSError as exc:
            fail("PF-EVIDENCE-PUBLISH", f"atomic publication failed: {exc.strerror}")
    finally:
        if not published and linked:
            _cleanup_link(directory, name)
        if final is not None:
            os.close(final)
        if staging is not None:
            os.close(staging)
        if temporary_present:
            _cleanup_link(directory, temporary)
        os.close(directory)


def _verify_open_bundle_file(
    root: int,
    relative_path: str,
    expected_size: int,
    expected_sha256: str,
) -> tuple[int, int]:
    components = relative_path.split("/")
    current = os.dup(root)
    descriptor: int | None = None
    try:
        for component in components[:-1]:
            try:
                following = os.open(
                    component,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                    dir_fd=current,
                )
            except OSError as exc:
                fail(
                    "PF-EVIDENCE-BUNDLE",
                    f"cannot safely open bundle component {_diagnostic_repr(component)}: "
                    f"{exc.strerror}",
                )
            try:
                _require_secure_directory(
                    os.fstat(following),
                    f"bundle component {_diagnostic_repr(component)}",
                    final=True,
                )
            except BaseException:
                os.close(following)
                raise
            os.close(current)
            current = following
        name = components[-1]
        try:
            descriptor = os.open(
                name,
                os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=current,
            )
        except OSError as exc:
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"cannot safely open bundle file {_diagnostic_repr(relative_path)}: {exc.strerror}",
            )
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.geteuid()
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) & 0o022
            or before.st_size != expected_size
        ):
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"bundle file metadata mismatch: {_diagnostic_repr(relative_path)}",
            )
        digest = hashlib.sha256()
        total = 0
        while True:
            chunk = os.read(descriptor, 128 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > expected_size:
                fail(
                    "PF-EVIDENCE-BUNDLE",
                    f"bundle file grew while reading: {_diagnostic_repr(relative_path)}",
                )
            digest.update(chunk)
        after = os.fstat(descriptor)
        path_after = os.stat(name, dir_fd=current, follow_symlinks=False)
        stable = ("st_dev", "st_ino", "st_size", "st_nlink", "st_mtime_ns", "st_ctime_ns")
        if (
            total != expected_size
            or digest.hexdigest() != expected_sha256
            or any(getattr(before, field) != getattr(after, field) for field in stable)
            or not _same_inode(before, path_after)
        ):
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"bundle file content changed or hash mismatched: {_diagnostic_repr(relative_path)}",
            )
        return (before.st_dev, before.st_ino)
    except EvidenceError:
        raise
    except OSError as exc:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"bundle file I/O failed for {_diagnostic_repr(relative_path)}: {exc.strerror}",
        )
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(current)


def verify_bundle(document: dict[str, object], root_path: Path) -> int:
    """Verify referenced bundle files; this is not gate-catalog attestation."""
    document = validate_evidence(document)
    records: dict[str, tuple[int, str]] = {}
    portable_paths: dict[str, str] = {}

    def register(path: object, size: object, digest: object) -> None:
        checked_path = require_relative_path(path, "bundle claim path")
        checked_size = require_int(size, "bundle claim size")
        checked_digest = require_sha256(digest, "bundle claim sha256")
        if checked_size > MAX_BUNDLE_FILE_BYTES:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"bundle claim exceeds {MAX_BUNDLE_FILE_BYTES} bytes: "
                f"{_diagnostic_repr(checked_path)}",
            )
        expected = (checked_size, checked_digest)
        if checked_path in records:
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"duplicate bundle claim path: {_diagnostic_repr(checked_path)}",
            )
        alias = unicodedata.normalize("NFC", checked_path).casefold()
        previous_path = portable_paths.get(alias)
        if previous_path is not None:
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"bundle claim paths collide under NFC/casefold: "
                f"{_diagnostic_repr(previous_path)} and {_diagnostic_repr(checked_path)}",
            )
        records[checked_path] = expected
        portable_paths[alias] = checked_path

    inputs = require_array(document["inputs"], "$.inputs")
    artifacts = require_array(document["artifacts"], "$.artifacts")
    logs = require_array(document["logs"], "$.logs")
    for entry in inputs:
        register(entry["path"], entry["size"], entry["sha256"])
    for entry in artifacts:
        if entry["retained"] is True:
            register(entry["path"], entry["size"], entry["sha256"])
    for entry in logs:
        register(entry["path"], entry["size"], entry["sha256"])

    if len(records) > MAX_BUNDLE_FILES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            f"bundle contains more than {MAX_BUNDLE_FILES} declared files",
        )
    total_size = sum(size for size, _ in records.values())
    if total_size > MAX_BUNDLE_TOTAL_BYTES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            f"bundle claims exceed {MAX_BUNDLE_TOTAL_BYTES} total bytes",
        )

    root = _open_secure_directory(root_path, "ROOT")
    try:
        identities: dict[tuple[int, int], str] = {}
        for path in sorted(records):
            expected_size, expected_digest = records[path]
            identity = _verify_open_bundle_file(root, path, expected_size, expected_digest)
            previous_path = identities.get(identity)
            if previous_path is not None:
                fail(
                    "PF-EVIDENCE-BUNDLE",
                    f"distinct bundle claims resolve to one inode: "
                    f"{_diagnostic_repr(previous_path)} and {_diagnostic_repr(path)}",
                )
            identities[identity] = path
        _require_secure_directory(os.fstat(root), "ROOT", final=True)
    except EvidenceError:
        raise
    except OSError as exc:
        fail("PF-EVIDENCE-BUNDLE", f"bundle verification I/O failed: {exc.strerror}")
    finally:
        os.close(root)
    return len(records)


def _sample_document(*, formal: bool = False) -> dict[str, object]:
    digit = lambda char: char * 64
    document: dict[str, object] = {
        "schema": SCHEMA,
        "id": "EV-20260715-9999",
        "gate": {
            "id": "v2-clean-room-alpha",
            "taskId": "TASK-D0-03",
            "testIds": ["TST-EVIDENCE-001", "TST-ISO-002"],
            "qualification": "formal" if formal else "development",
        },
        "repository": {
            "commit": "a" * 40,
            "subtree": ".",
            "treeObjectId": "b" * 40,
            "anchorSource": "external" if formal else "derived-development",
            "dirty": False,
            "dirtyDigest": None,
            "unchangedDuringRun": True,
            "archive": {"format": "git-tar", "sha256": digit("c"), "size": 4096},
        },
        "hostAttestation": {
            "scope": "local-point-in-time",
            "remoteAttestation": False,
            "profileId": "darwin-arm64-test",
            "eligibleForHermetic": formal,
            "bootstrapLockSha256": digit("1"),
            "hostProfileLockSha256": digit("2"),
            "toolchainLockSha256": digit("3"),
            "launcherSha256": digit("4"),
            "verifierSha256": digit("5"),
            "observationSha256": digit("6"),
        },
        "environment": {
            "os": "macOS 26.4.1",
            "arch": "arm64",
            "environmentSha256": digit("7"),
            "sourceDateEpoch": 0,
            "cleanRoom": True,
            "buildCache": "empty",
            "assetCache": "locked-read-only",
        },
        "sandboxPolicies": [
            {
                "id": "core-no-network",
                "engine": "sandbox-exec",
                "engineSha256": digit("8"),
                "defaultAction": "deny",
                "network": "deny-all",
                "templateSha256": digit("9"),
                "renderedSha256": digit("a"),
                "probes": [{"id": "network-denied", "status": "passed"}],
            },
            {
                "id": "evm-runtime-exact-port",
                "engine": "sandbox-exec",
                "engineSha256": digit("8"),
                "defaultAction": "deny",
                "network": "exact-local-port",
                "networkPort": 8545,
                "templateSha256": digit("b"),
                "renderedSha256": digit("c"),
                "probes": [
                    {"id": "adjacent-port-denied", "status": "passed"},
                    {"id": "lan-refused", "status": "passed"},
                ],
            }
        ],
        "tools": [
            {
                "id": "lean",
                "version": "4.31.0",
                "source": "content-addressed-cache",
                "assetSha256": digit("b"),
                "executableSha256": digit("c"),
                "closureSha256": digit("d"),
            }
        ],
        "command": {
            "argv": ["scripts/verify_isolation.sh"],
            "cwdRelative": ".",
            "startedUtc": "2026-07-15T00:00:00.000Z",
            "endedUtc": "2026-07-15T00:00:00.125Z",
            "durationMs": 125,
            "attempts": [
                {
                    "number": 1,
                    "exitCode": 0,
                    "signal": None,
                    "timedOut": False,
                    "stdoutLog": "build/logs/gate.stdout",
                    "stderrLog": "build/logs/gate.stderr",
                }
            ],
        },
        "inputs": [
            {
                "role": "candidate-archive",
                "path": "candidate.tar",
                "sha256": digit("c"),
                "size": 4096,
            }
        ],
        "artifacts": [
            {
                "target": "evm",
                "role": "bytecode",
                "path": "build/evm/Counter.bin",
                "mediaType": "application/octet-stream",
                "sha256": digit("e"),
                "size": 32,
                "retained": True,
            }
        ],
        "artifactSetSha256": "",
        "observations": (
            [
                {
                    "step": "counter-runtime",
                    "status": "passed",
                    "return": 3,
                    "logicalState": {"count": 3},
                    "effects": [],
                    "errorClass": None,
                }
            ]
            if formal
            else []
        ),
        "logs": [
            {
                "path": "build/logs/gate.stderr",
                "sha256": digit("2"),
                "size": 0,
                "truncated": False,
                "privateDataScan": "passed" if formal else "not-run",
            },
            {
                "path": "build/logs/gate.stdout",
                "sha256": digit("1"),
                "size": 100,
                "truncated": False,
                "privateDataScan": "passed" if formal else "not-run",
            },
        ],
        "result": "passed",
        "skipAuthorization": None,
    }
    document["artifactSetSha256"] = artifact_set_sha256(document["artifacts"])
    return document


def _expect_rejected(label: str, operation: object) -> None:
    try:
        if callable(operation):
            operation()
        else:
            validate_evidence(operation)
    except EvidenceError:
        return
    fail("PF-EVIDENCE-SELF-TEST", f"negative self-test was accepted: {label}")


def _self_test_literal_dict_keys() -> None:
    """Reject duplicate string keys hidden by Python dict-literal semantics."""
    try:
        source = Path(__file__).read_text(encoding="utf-8")
        tree = ast.parse(source, filename=__file__)
    except (OSError, SyntaxError, UnicodeError) as exc:
        fail("PF-EVIDENCE-SELF-TEST", f"cannot parse evidence source for duplicate keys: {exc}")
    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        seen: set[str] = set()
        for key in node.keys:
            if not isinstance(key, ast.Constant) or not isinstance(key.value, str):
                continue
            if key.value in seen:
                fail(
                    "PF-EVIDENCE-SELF-TEST",
                    f"duplicate literal dict key at source line {key.lineno}: "
                    f"{_diagnostic_repr(key.value)}",
                )
            seen.add(key.value)


def self_test() -> None:
    _self_test_literal_dict_keys()
    development = _sample_document()
    formal = _sample_document(formal=True)
    validate_evidence(development)
    validate_evidence(formal)
    _require_development_publish(development)
    _expect_rejected("formal publication without catalog finalizer", lambda: _require_development_publish(formal))
    encoded = canonical_bytes(development)
    if canonical_bytes(validate_evidence(decode_json(encoded))) != encoded:
        fail("PF-EVIDENCE-SELF-TEST", "canonical round trip changed bytes")

    _expect_rejected(
        "duplicate key",
        lambda: decode_json(b'{"schema":"a","schema":"b"}'),
    )
    _expect_rejected("float", lambda: decode_json(b'{"n":1.0}'))
    safe_numbers = decode_json(
        f'{{"high":{MAX_SAFE_INTEGER},"low":{-MAX_SAFE_INTEGER}}}'.encode("ascii")
    )
    if safe_numbers != {"high": MAX_SAFE_INTEGER, "low": -MAX_SAFE_INTEGER}:
        fail("PF-EVIDENCE-SELF-TEST", "safe-integer boundary did not round trip")
    _expect_rejected(
        "unsafe positive integer",
        lambda: decode_json(f'{{"n":{MAX_SAFE_INTEGER + 1}}}'.encode("ascii")),
    )
    _expect_rejected(
        "unsafe negative integer",
        lambda: decode_json(f'{{"n":{-MAX_SAFE_INTEGER - 1}}}'.encode("ascii")),
    )
    _expect_rejected(
        "non-ASCII object key",
        lambda: decode_json('{"\u952e":1}'.encode("utf-8")),
    )
    _expect_rejected("non-graphic object key", lambda: decode_json(b'{"bad key":1}'))
    try:
        decode_json(b'{"\\u001b[31m":1}')
    except EvidenceError as exc:
        if "\x1b" in str(exc):
            fail("PF-EVIDENCE-SELF-TEST", "diagnostic reflected an ANSI escape")
    else:
        fail("PF-EVIDENCE-SELF-TEST", "ANSI object key was accepted")
    long_key = "k" * 257
    _expect_rejected(
        "overlong object key",
        lambda: decode_json(("{" + json.dumps(long_key) + ":1}").encode("ascii")),
    )
    escaped = {"a": "\b\t\n\f\r\"\\", "z": "\u96ea"}
    expected_escape = b'{"a":"\\b\\t\\n\\f\\r\\\"\\\\","z":"' + "\u96ea".encode("utf-8") + b'"}'
    if canonical_bytes(escaped) != expected_escape:
        fail("PF-EVIDENCE-SELF-TEST", "JCS string escaping changed")
    if artifact_set_sha256([]) != "fa68023676104d95f750e5c7aba9a837eda0982548b95a3cb96b74ec93c16155":
        fail("PF-EVIDENCE-SELF-TEST", "artifact-set domain vector changed")

    unknown = copy.deepcopy(development)
    unknown["unknown"] = True
    _expect_rejected("unknown field", unknown)
    traversal = copy.deepcopy(development)
    traversal["logs"][0]["path"] = "../private.log"  # type: ignore[index]
    _expect_rejected("relative path traversal", traversal)
    control_path = copy.deepcopy(development)
    control_path["logs"][0]["path"] = "build/logs/private\n.log"  # type: ignore[index]
    _expect_rejected("relative path control character", control_path)
    _expect_rejected(
        "CLI parent traversal",
        lambda: _normalized_cli_path("../EV-20260715-9999.json", "OUTPUT"),
    )
    _expect_rejected(
        "CLI control character",
        lambda: _normalized_cli_path("bad\n.json", "OUTPUT"),
    )
    _expect_rejected(
        "CLI non-NFC path",
        lambda: _normalized_cli_path("e\u0301.json", "OUTPUT"),
    )

    nonexistent_date = copy.deepcopy(development)
    nonexistent_date["id"] = "EV-20260230-9999"
    _expect_rejected("nonexistent evidence date", nonexistent_date)
    mismatched_date = copy.deepcopy(development)
    mismatched_date["id"] = "EV-20260714-9999"
    _expect_rejected("evidence/ended UTC date mismatch", mismatched_date)
    wrong_archive_format = copy.deepcopy(development)
    wrong_archive_format["repository"]["archive"]["format"] = "tar"  # type: ignore[index]
    _expect_rejected("non-git archive format", wrong_archive_format)
    wrong_scope = copy.deepcopy(development)
    wrong_scope["hostAttestation"]["scope"] = "development"  # type: ignore[index]
    _expect_rejected("non-local host scope", wrong_scope)
    remote_claim = copy.deepcopy(development)
    remote_claim["hostAttestation"]["remoteAttestation"] = True  # type: ignore[index]
    _expect_rejected("unsupported remote attestation", remote_claim)
    bad_artifact_set = copy.deepcopy(development)
    bad_artifact_set["artifactSetSha256"] = "0" * 64
    _expect_rejected("artifact-set digest mismatch", bad_artifact_set)

    legacy_loopback = copy.deepcopy(development)
    legacy_loopback_policy = legacy_loopback["sandboxPolicies"][1]  # type: ignore[index]
    legacy_loopback_policy["network"] = "loopback-only"
    legacy_loopback_policy.pop("networkPort")
    validate_evidence(legacy_loopback)

    legacy_deny_all = copy.deepcopy(development)
    legacy_deny_all["sandboxPolicies"] = [
        legacy_deny_all["sandboxPolicies"][0]  # type: ignore[index]
    ]
    validate_evidence(legacy_deny_all)

    missing_exact_port = copy.deepcopy(development)
    missing_exact_port["sandboxPolicies"][1].pop("networkPort")  # type: ignore[index]
    _expect_rejected("exact-local-port without networkPort", missing_exact_port)

    for boundary_port in (1, 65535):
        valid_exact_port = copy.deepcopy(development)
        valid_exact_port["sandboxPolicies"][1]["networkPort"] = boundary_port  # type: ignore[index]
        validate_evidence(valid_exact_port)

    port_on_deny_all = copy.deepcopy(development)
    port_on_deny_all["sandboxPolicies"][0]["networkPort"] = 8545  # type: ignore[index]
    _expect_rejected("networkPort on deny-all policy", port_on_deny_all)

    port_on_loopback = copy.deepcopy(legacy_loopback)
    port_on_loopback["sandboxPolicies"][1]["networkPort"] = 8545  # type: ignore[index]
    _expect_rejected("networkPort on loopback-only policy", port_on_loopback)

    for label, invalid_port in (
        ("negative", -1),
        ("zero", 0),
        ("above maximum", 65536),
        ("boolean", True),
        ("float", 8545.0),
        ("string", "8545"),
        ("null", None),
    ):
        invalid_exact_port = copy.deepcopy(development)
        invalid_exact_port["sandboxPolicies"][1]["networkPort"] = invalid_port  # type: ignore[index]
        _expect_rejected(f"exact-local-port {label} networkPort", invalid_exact_port)

    unknown_network = copy.deepcopy(development)
    unknown_network["sandboxPolicies"][1]["network"] = "localhost"  # type: ignore[index]
    _expect_rejected("unknown sandbox network policy", unknown_network)

    unknown_network_field = copy.deepcopy(development)
    unknown_network_field["sandboxPolicies"][1]["networkPortTypo"] = 8545  # type: ignore[index]
    _expect_rejected("unknown sandbox network field", unknown_network_field)

    formal_without_deny_all = copy.deepcopy(formal)
    formal_without_deny_all["sandboxPolicies"] = [
        formal_without_deny_all["sandboxPolicies"][1]  # type: ignore[index]
    ]
    _expect_rejected("formal exact-local-port without deny-all policy", formal_without_deny_all)

    for probe_status in ("failed", "skipped"):
        nonpassing_exact_probe = copy.deepcopy(development)
        nonpassing_exact_probe["sandboxPolicies"][1]["probes"][0]["status"] = probe_status  # type: ignore[index]
        _expect_rejected(
            f"passed evidence with {probe_status} exact-local-port probe",
            nonpassing_exact_probe,
        )

    ordering_mutations: list[tuple[str, dict[str, object]]] = []
    candidate = copy.deepcopy(development)
    candidate["gate"]["testIds"].reverse()  # type: ignore[index]
    ordering_mutations.append(("test id ordering", candidate))
    candidate = copy.deepcopy(development)
    extra = copy.deepcopy(candidate["sandboxPolicies"][0])  # type: ignore[index]
    extra["id"] = "aaa-policy"
    candidate["sandboxPolicies"].append(extra)  # type: ignore[union-attr]
    ordering_mutations.append(("sandbox policy ordering", candidate))
    candidate = copy.deepcopy(development)
    candidate["sandboxPolicies"][0]["probes"].append(  # type: ignore[index]
        {"id": "aaa-probe", "status": "passed"}
    )
    ordering_mutations.append(("sandbox probe ordering", candidate))
    candidate = copy.deepcopy(development)
    extra = copy.deepcopy(candidate["tools"][0])  # type: ignore[index]
    extra["id"] = "aaa-tool"
    candidate["tools"].append(extra)  # type: ignore[union-attr]
    ordering_mutations.append(("tool ordering", candidate))
    candidate = copy.deepcopy(development)
    candidate["inputs"].append(  # type: ignore[union-attr]
        {"role": "aaa-input", "path": "aaa.in", "sha256": "0" * 64, "size": 0}
    )
    ordering_mutations.append(("input ordering", candidate))
    candidate = copy.deepcopy(development)
    extra = copy.deepcopy(candidate["artifacts"][0])  # type: ignore[index]
    extra["target"] = "aaa-target"
    extra["path"] = "build/aaa.bin"
    candidate["artifacts"].append(extra)  # type: ignore[union-attr]
    candidate["artifactSetSha256"] = artifact_set_sha256(candidate["artifacts"])
    ordering_mutations.append(("artifact ordering", candidate))
    candidate = copy.deepcopy(development)
    candidate["logs"].reverse()  # type: ignore[union-attr]
    ordering_mutations.append(("log ordering", candidate))
    for label, mutation in ordering_mutations:
        _expect_rejected(label, mutation)

    duplicate_tests = copy.deepcopy(development)
    duplicate_tests["gate"]["testIds"] = ["TST-EVIDENCE-001", "TST-EVIDENCE-001"]  # type: ignore[index]
    _expect_rejected("duplicate set-like entry", duplicate_tests)

    failed_observation = copy.deepcopy(development)
    failed_observation["observations"] = [
        {
            "step": "failure",
            "status": "failed",
            "return": None,
            "logicalState": None,
            "effects": [],
            "errorClass": "PF-TEST",
        }
    ]
    _expect_rejected("passed evidence with failed observation", failed_observation)
    failed_scan = copy.deepcopy(development)
    failed_scan["logs"][0]["privateDataScan"] = "failed"  # type: ignore[index]
    _expect_rejected("passed evidence with failed private scan", failed_scan)
    truncated_development = copy.deepcopy(development)
    truncated_development["logs"][0]["truncated"] = True  # type: ignore[index]
    _expect_rejected("passed evidence with truncated log", truncated_development)
    missing_candidate = copy.deepcopy(development)
    missing_candidate["inputs"] = []
    _expect_rejected("missing candidate archive input", missing_candidate)
    mismatched_candidate = copy.deepcopy(development)
    mismatched_candidate["inputs"][0]["sha256"] = "0" * 64  # type: ignore[index]
    _expect_rejected("mismatched candidate archive input", mismatched_candidate)
    duplicate_candidate = copy.deepcopy(development)
    duplicate_candidate["inputs"] = [
        {
            "role": "candidate-archive",
            "path": "a.tar",
            "sha256": "0" * 64,
            "size": 1,
        },
        duplicate_candidate["inputs"][0],
    ]
    _expect_rejected("multiple candidate archive inputs", duplicate_candidate)

    formal_mutations: list[tuple[str, tuple[str, ...], object]] = [
        ("ineligible host", ("hostAttestation", "eligibleForHermetic"), False),
        ("dirty repository", ("repository", "dirty"), True),
        ("changed candidate", ("repository", "unchangedDuringRun"), False),
        ("derived formal anchor", ("repository", "anchorSource"), "derived-development"),
        ("allow-default sandbox", ("sandboxPolicies", "0", "defaultAction"), "allow"),
        ("truncated log", ("logs", "0", "truncated"), True),
        ("unscanned log", ("logs", "0", "privateDataScan"), "not-run"),
    ]
    for label, path, replacement in formal_mutations:
        candidate = copy.deepcopy(formal)
        cursor: object = candidate
        for component in path[:-1]:
            cursor = cursor[int(component)] if component.isdigit() else cursor[component]  # type: ignore[index]
        cursor[path[-1]] = replacement  # type: ignore[index]
        if label == "dirty repository":
            candidate["repository"]["dirtyDigest"] = "0" * 64  # type: ignore[index]
        _expect_rejected(label, candidate)

    for label, field in (
        ("missing sandbox policies", "sandboxPolicies"),
        ("missing tools", "tools"),
        ("missing logs", "logs"),
    ):
        candidate = copy.deepcopy(formal)
        candidate[field] = []
        _expect_rejected(label, candidate)

    retry = copy.deepcopy(formal)
    retry_attempt = copy.deepcopy(retry["command"]["attempts"][0])  # type: ignore[index]
    retry_attempt["number"] = 2
    retry["command"]["attempts"].append(retry_attempt)  # type: ignore[index]
    _expect_rejected("formal retry", retry)
    unretained = copy.deepcopy(formal)
    unretained["artifacts"][0]["retained"] = False  # type: ignore[index]
    unretained["artifactSetSha256"] = artifact_set_sha256(unretained["artifacts"])
    _expect_rejected("formal unretained artifact", unretained)

    development_retry = copy.deepcopy(development)
    second_attempt = copy.deepcopy(development_retry["command"]["attempts"][0])  # type: ignore[index]
    second_attempt["number"] = 2
    development_retry["command"]["attempts"].append(second_attempt)  # type: ignore[index]
    validate_evidence(development_retry)
    invalid_timeout = copy.deepcopy(development)
    invalid_timeout["command"]["attempts"][0]["timedOut"] = True  # type: ignore[index]
    _expect_rejected("timeout with exit code", invalid_timeout)
    missing_terminal = copy.deepcopy(development)
    missing_terminal["command"]["attempts"][0]["exitCode"] = None  # type: ignore[index]
    _expect_rejected("attempt without terminal state", missing_terminal)
    duplicate_terminal = copy.deepcopy(development)
    duplicate_terminal["command"]["attempts"][0]["signal"] = 9  # type: ignore[index]
    _expect_rejected("attempt with exit and signal", duplicate_terminal)
    skipped_with_attempt = copy.deepcopy(development)
    skipped_with_attempt["result"] = "skipped"
    skipped_with_attempt["skipAuthorization"] = {"id": "DOSS-1", "reason": "authorized"}
    _expect_rejected("skipped evidence with attempt", skipped_with_attempt)
    valid_skipped = copy.deepcopy(development)
    valid_skipped["result"] = "skipped"
    valid_skipped["skipAuthorization"] = {"id": "DOSS-1", "reason": "authorized"}
    valid_skipped["command"]["attempts"] = []  # type: ignore[index]
    validate_evidence(valid_skipped)
    contradictory_failure = copy.deepcopy(formal)
    contradictory_failure["result"] = "failed"
    _expect_rejected("failed evidence with all-green facts", contradictory_failure)
    valid_timeout_failure = copy.deepcopy(development)
    valid_timeout_failure["result"] = "failed"
    valid_timeout_failure["command"]["attempts"][0].update(  # type: ignore[index]
        {"exitCode": None, "signal": None, "timedOut": True}
    )
    validate_evidence(valid_timeout_failure)

    with tempfile.TemporaryDirectory(prefix="pf-evidence-self-test-") as temporary:
        temporary_root = Path(temporary).resolve(strict=True)
        noncanonical = temporary_root / "input.json"
        noncanonical.write_text(json.dumps(development, indent=2), encoding="utf-8")
        _expect_rejected(
            "noncanonical validate",
            lambda: load_evidence(noncanonical, require_canonical=True),
        )
        loaded, loaded_bytes = load_evidence(noncanonical, require_canonical=False)
        if loaded["id"] != development["id"] or loaded_bytes != encoded:
            fail("PF-EVIDENCE-SELF-TEST", "publish input did not canonicalize")
        gate_directory = temporary_root / development["gate"]["id"]  # type: ignore[index]
        gate_directory.mkdir(mode=0o700)
        output = gate_directory / "EV-20260715-9999.json"
        publish_arguments = {
            "evidence_id": development["id"],
            "gate_id": development["gate"]["id"],  # type: ignore[index]
        }
        atomic_publish(encoded, output, **publish_arguments)  # type: ignore[arg-type]
        if output.read_bytes() != encoded or stat.S_IMODE(output.stat().st_mode) != 0o444:
            fail("PF-EVIDENCE-SELF-TEST", "atomic publish changed bytes or mode")
        _expect_rejected(
            "no-clobber publish",
            lambda: atomic_publish(encoded, output, **publish_arguments),  # type: ignore[arg-type]
        )
        _expect_rejected(
            "wrong publication basename",
            lambda: atomic_publish(  # type: ignore[arg-type]
                encoded, gate_directory / "wrong.json", **publish_arguments
            ),
        )
        wrong_parent = temporary_root / "wrong-gate"
        wrong_parent.mkdir(mode=0o700)
        _expect_rejected(
            "wrong publication gate directory",
            lambda: atomic_publish(  # type: ignore[arg-type]
                encoded, wrong_parent / "EV-20260715-9999.json", **publish_arguments
            ),
        )

        insecure_root = temporary_root / "insecure"
        insecure_gate = insecure_root / development["gate"]["id"]  # type: ignore[index]
        insecure_gate.mkdir(parents=True, mode=0o700)
        insecure_gate.chmod(0o770)
        _expect_rejected(
            "group-writable output parent",
            lambda: atomic_publish(  # type: ignore[arg-type]
                encoded, insecure_gate / "EV-20260715-9999.json", **publish_arguments
            ),
        )

        symlink_root = temporary_root / "symlink-root"
        symlink_root.mkdir(mode=0o700)
        real_gate = temporary_root / "real-gate"
        real_gate.mkdir(mode=0o700)
        symlink_gate = symlink_root / development["gate"]["id"]  # type: ignore[index]
        symlink_gate.symlink_to(real_gate, target_is_directory=True)
        _expect_rejected(
            "symlink output parent",
            lambda: atomic_publish(  # type: ignore[arg-type]
                encoded, symlink_gate / "EV-20260715-9999.json", **publish_arguments
            ),
        )

        attack_root = temporary_root / "attack"
        attack_gate = attack_root / development["gate"]["id"]  # type: ignore[index]
        attack_gate.mkdir(parents=True, mode=0o700)
        attack_output = attack_gate / "EV-20260715-9999.json"
        real_link = os.link

        def replace_staging_link(
            source: str,
            destination: str,
            *,
            src_dir_fd: int | None = None,
            dst_dir_fd: int | None = None,
            follow_symlinks: bool = True,
        ) -> None:
            if src_dir_fd is None or dst_dir_fd is None:
                raise RuntimeError("TOCTOU self-test requires dir_fd link semantics")
            os.unlink(source, dir_fd=src_dir_fd)
            attacker = os.open(
                source,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                0o600,
                dir_fd=src_dir_fd,
            )
            try:
                os.write(attacker, b"attacker-controlled")
                os.fsync(attacker)
            finally:
                os.close(attacker)
            real_link(
                source,
                destination,
                src_dir_fd=src_dir_fd,
                dst_dir_fd=dst_dir_fd,
                follow_symlinks=follow_symlinks,
            )

        os.link = replace_staging_link
        try:
            _expect_rejected(
                "staging pathname replacement TOCTOU",
                lambda: atomic_publish(  # type: ignore[arg-type]
                    encoded, attack_output, **publish_arguments
                ),
            )
        finally:
            os.link = real_link
        if attack_output.exists() or any(attack_gate.iterdir()):
            fail("PF-EVIDENCE-SELF-TEST", "TOCTOU rejection left a published/staging file")

        bundle_document = copy.deepcopy(development)
        bundle_root = temporary_root / "bundle"
        (bundle_root / "build" / "evm").mkdir(parents=True, mode=0o700)
        (bundle_root / "build" / "logs").mkdir(parents=True, mode=0o700)
        bundle_files = {
            "candidate.tar": b"candidate archive",
            "build/evm/Counter.bin": b"counter bytecode",
            "build/logs/gate.stderr": b"",
            "build/logs/gate.stdout": b"gate output",
        }
        for relative, body in bundle_files.items():
            destination = bundle_root / relative
            destination.write_bytes(body)
            destination.chmod(0o444)
        claims = (
            list(bundle_document["inputs"])
            + list(bundle_document["artifacts"])
            + list(bundle_document["logs"])
        )
        for claim in claims:
            body = bundle_files[claim["path"]]
            claim["size"] = len(body)
            claim["sha256"] = hashlib.sha256(body).hexdigest()
        bundle_document["repository"]["archive"]["size"] = len(bundle_files["candidate.tar"])  # type: ignore[index]
        bundle_document["repository"]["archive"]["sha256"] = hashlib.sha256(  # type: ignore[index]
            bundle_files["candidate.tar"]
        ).hexdigest()
        bundle_document["artifactSetSha256"] = artifact_set_sha256(bundle_document["artifacts"])
        validate_evidence(bundle_document)

        reused_path = copy.deepcopy(bundle_document)
        reused_path["artifacts"][0]["path"] = "candidate.tar"  # type: ignore[index]
        reused_path["artifactSetSha256"] = artifact_set_sha256(reused_path["artifacts"])
        _expect_rejected("bundle claim path reused across roles", reused_path)
        casefold_alias = copy.deepcopy(bundle_document)
        casefold_alias["artifacts"][0]["path"] = "CANDIDATE.TAR"  # type: ignore[index]
        casefold_alias["artifactSetSha256"] = artifact_set_sha256(casefold_alias["artifacts"])
        _expect_rejected("bundle claim casefold alias", casefold_alias)

        oversized = copy.deepcopy(bundle_document)
        oversized["inputs"][0]["size"] = MAX_BUNDLE_FILE_BYTES + 1  # type: ignore[index]
        oversized["repository"]["archive"]["size"] = MAX_BUNDLE_FILE_BYTES + 1  # type: ignore[index]
        _expect_rejected(
            "bundle per-file byte limit",
            lambda: verify_bundle(oversized, bundle_root),
        )
        over_total = copy.deepcopy(bundle_document)
        for claim in list(over_total["inputs"]) + list(over_total["artifacts"]) + list(over_total["logs"]):
            claim["size"] = MAX_BUNDLE_FILE_BYTES
        over_total["repository"]["archive"]["size"] = MAX_BUNDLE_FILE_BYTES  # type: ignore[index]
        over_total["logs"].append(  # type: ignore[union-attr]
            {
                "path": "build/logs/zz-extra.log",
                "sha256": "0" * 64,
                "size": MAX_BUNDLE_FILE_BYTES,
                "truncated": False,
                "privateDataScan": "passed",
            }
        )
        over_total["artifactSetSha256"] = artifact_set_sha256(over_total["artifacts"])
        _expect_rejected(
            "bundle aggregate byte limit",
            lambda: verify_bundle(over_total, bundle_root),
        )

        if verify_bundle(bundle_document, bundle_root) != len(bundle_files):
            fail("PF-EVIDENCE-SELF-TEST", "bundle verifier checked the wrong file count")

        original_bundle_reader = globals()["_verify_open_bundle_file"]

        def injected_shared_inode(
            _root: int, _path: str, _size: int, _digest: str
        ) -> tuple[int, int]:
            return (7, 11)

        globals()["_verify_open_bundle_file"] = injected_shared_inode
        try:
            _expect_rejected(
                "distinct claims sharing one observed inode",
                lambda: verify_bundle(bundle_document, bundle_root),
            )
        finally:
            globals()["_verify_open_bundle_file"] = original_bundle_reader

        original_os_read = os.read

        def injected_read_error(_descriptor: int, _size: int) -> bytes:
            raise OSError(5, "injected I/O failure")

        os.read = injected_read_error
        try:
            _expect_rejected(
                "bundle read I/O normalization",
                lambda: verify_bundle(bundle_document, bundle_root),
            )
        finally:
            os.read = original_os_read

        (bundle_root / "build" / "evm" / "Counter.bin").chmod(0o644)
        (bundle_root / "build" / "evm" / "Counter.bin").write_bytes(b"tampered")
        _expect_rejected(
            "bundle content mutation",
            lambda: verify_bundle(bundle_document, bundle_root),
        )
        artifact_path = bundle_root / "build" / "evm" / "Counter.bin"
        artifact_path.unlink()
        outside = temporary_root / "outside.bin"
        outside.write_bytes(bundle_files["build/evm/Counter.bin"])
        outside.chmod(0o444)
        artifact_path.symlink_to(outside)
        _expect_rejected(
            "bundle symlink",
            lambda: verify_bundle(bundle_document, bundle_root),
        )
        artifact_path.unlink()
        artifact_path.write_bytes(bundle_files["build/evm/Counter.bin"])
        artifact_path.chmod(0o444)
        os.link(artifact_path, bundle_root / "artifact-hardlink")
        _expect_rejected(
            "bundle hardlink",
            lambda: verify_bundle(bundle_document, bundle_root),
        )


def _require_isolated_runtime() -> None:
    if not sys.flags.isolated or not sys.flags.no_site:
        fail(
            "PF-EVIDENCE-PYTHON-MODE",
            "invoke with the Stage-0-pinned direct Python using -I -S",
        )


def _require_development_publish(document: dict[str, object]) -> None:
    qualification, _ = _validate_gate(document["gate"])
    if qualification != "development":
        fail(
            "PF-EVIDENCE-FORMAL-UNVERIFIED",
            "formal evidence publication requires the future gate-catalog finalizer; "
            "schema or bundle integrity alone is insufficient",
        )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser(
        "validate", help="validate only the canonical evidence schema and invariants"
    )
    validate_parser.add_argument("input")
    verify_parser = subparsers.add_parser(
        "verify-bundle",
        help="verify declared bundle file size/hash without asserting the gate catalog",
    )
    verify_parser.add_argument("input")
    verify_parser.add_argument("root")
    publish_parser = subparsers.add_parser(
        "publish", help="validate, canonicalize, and atomically publish evidence"
    )
    publish_parser.add_argument("input")
    publish_parser.add_argument("output")
    subparsers.add_parser("self-test", help="run positive, negative, and atomicity tests")
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        _require_isolated_runtime()
        arguments = _build_parser().parse_args(argv)
        if arguments.command == "validate":
            input_path = _normalized_cli_path(arguments.input, "INPUT")
            document, encoded = load_evidence(input_path, require_canonical=True)
            print(
                f"schema-validated {document['id']} claims-not-verified "
                f"sha256={hashlib.sha256(encoded).hexdigest()} size={len(encoded)}"
            )
        elif arguments.command == "verify-bundle":
            input_path = _normalized_cli_path(arguments.input, "INPUT")
            root_path = _normalized_cli_directory(arguments.root, "ROOT")
            document, encoded = load_evidence(input_path, require_canonical=True)
            checked = verify_bundle(document, root_path)
            print(
                f"bundle-integrity-verified {document['id']} gate-catalog-not-verified "
                f"files={checked} schemaSha256={hashlib.sha256(encoded).hexdigest()}"
            )
        elif arguments.command == "publish":
            input_path = _normalized_cli_path(arguments.input, "INPUT")
            output_path = _normalized_cli_path(arguments.output, "OUTPUT")
            document, encoded = load_evidence(input_path, require_canonical=False)
            _require_development_publish(document)
            _, gate_id = _validate_gate(document["gate"])
            evidence_id = require_pattern(document["id"], EVIDENCE_ID_RE, "$.id")
            atomic_publish(
                encoded,
                output_path,
                evidence_id=evidence_id,
                gate_id=gate_id,
            )
            print(
                f"development-schema-published {document['id']} claims-not-verified {output_path} "
                f"sha256={hashlib.sha256(encoded).hexdigest()} size={len(encoded)}"
            )
        elif arguments.command == "self-test":
            self_test()
            print("gate evidence self-test passed")
        else:
            fail("PF-EVIDENCE-CLI", f"unsupported command: {arguments.command}")
        return 0
    except EvidenceError as exc:
        print(f"{exc.code}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
