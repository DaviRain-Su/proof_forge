"""Pure validation core for canonical ``proof-forge.evidence.v1`` objects.

This module intentionally performs no file, command-line, environment, or
network I/O.  Callers supply the exact evidence bytes or an already-decoded
JSON value and decide how trusted bytes are obtained and retained.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import posixpath
import re
import unicodedata
from typing import NoReturn


__all__ = [
    "EvidenceError",
    "artifact_set_sha256",
    "canonical_bytes",
    "decode_json",
    "validate_evidence",
]


SCHEMA = "proof-forge.evidence.v1"
GATE_CATALOG_SCHEMA = "proof-forge.gate-catalog.v1"
ARTIFACT_SET_DOMAIN = b"pf.evidence.artifact-set.v1\x00"
MAX_INPUT_BYTES = 4 * 1024 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1

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
    r"(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z"
)
SEMVER_RE = re.compile(
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)"
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


def _require_typed_field(
    obj: dict[str, object],
    field: str,
    enabled: bool,
    where: str,
) -> None:
    present = field in obj
    field_where = _where(where, field)
    if enabled and not present:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{field_where} is required when $.gateCatalog is present",
        )
    if not enabled and present:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{field_where} is forbidden when $.gateCatalog is absent",
        )


def _validate_role_path_ref(
    value: object,
    where: str,
    *,
    expected_role: str,
) -> dict[str, object]:
    obj = require_keys(value, {"role", "path"}, where)
    role = require_safe_id(obj["role"], _where(where, "role"))
    require_relative_path(obj["path"], _where(where, "path"))
    if role != expected_role:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.role must be {expected_role!r}",
        )
    return obj


def _validate_gate_catalog_ref(value: object) -> dict[str, object]:
    where = "$.gateCatalog"
    obj = require_keys(
        value,
        {"schema", "id", "version", "contentSha256", "catalogDigest"},
        where,
    )
    schema = require_text(obj["schema"], _where(where, "schema"), ascii_only=True)
    if schema != GATE_CATALOG_SCHEMA:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where}.schema must be {GATE_CATALOG_SCHEMA!r}",
        )
    require_safe_id(obj["id"], _where(where, "id"))
    require_pattern(obj["version"], SEMVER_RE, _where(where, "version"))
    require_sha256(obj["contentSha256"], _where(where, "contentSha256"))
    require_sha256(obj["catalogDigest"], _where(where, "catalogDigest"))
    return obj


def require_utc(value: object, where: str) -> tuple[str, dt.datetime]:
    text = require_text(value, where, ascii_only=True)
    if UTC_RE.fullmatch(text) is None:
        fail(
            "PF-EVIDENCE-SCHEMA",
            f"{where} must be RFC 3339 UTC with whole-second precision",
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


def _validate_host(
    value: object,
    *,
    typed_bindings: bool = False,
) -> dict[str, object]:
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
    obj = require_keys(value, fields, where, optional={"observationInput"})
    _require_typed_field(obj, "observationInput", typed_bindings, where)
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
    if typed_bindings:
        _validate_role_path_ref(
            obj["observationInput"],
            _where(where, "observationInput"),
            expected_role="host-observation",
        )
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


def _validate_probe_receipt(value: object, where: str) -> dict[str, object]:
    receipt = require_keys(
        value,
        {
            "invocationContextInput",
            "role",
            "path",
            "stdoutLog",
            "stderrLog",
        },
        where,
    )
    _validate_role_path_ref(
        receipt["invocationContextInput"],
        _where(where, "invocationContextInput"),
        expected_role="sandbox-invocation-context",
    )
    role = require_safe_id(receipt["role"], _where(where, "role"))
    if role != "sandbox-invocation-receipt":
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.role must be 'sandbox-invocation-receipt'",
        )
    require_relative_path(receipt["path"], _where(where, "path"))
    require_relative_path(receipt["stdoutLog"], _where(where, "stdoutLog"))
    require_relative_path(receipt["stderrLog"], _where(where, "stderrLog"))
    return receipt


def _validate_sandbox_policies(
    value: object,
    *,
    typed_bindings: bool = False,
) -> list[dict[str, object]]:
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
            optional={"networkPort", "renderedPolicyInput"},
        )
        _require_typed_field(
            policy,
            "renderedPolicyInput",
            typed_bindings,
            where,
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
        if typed_bindings:
            _validate_role_path_ref(
                policy["renderedPolicyInput"],
                _where(where, "renderedPolicyInput"),
                expected_role="sandbox-rendered-policy",
            )
        probes = require_array(policy["probes"], _where(where, "probes"), nonempty=True)
        probe_ids: set[str] = set()
        for probe_index, probe_value in enumerate(probes):
            probe_where = f"{where}.probes[{probe_index}]"
            probe = require_keys(
                probe_value,
                {"id", "status"},
                probe_where,
                optional={"receipt"},
            )
            _require_typed_field(probe, "receipt", typed_bindings, probe_where)
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
            if typed_bindings:
                _validate_probe_receipt(
                    probe["receipt"],
                    _where(probe_where, "receipt"),
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
    require_int(obj["durationMs"], _where(where, "durationMs"))
    if ended < started:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where}.endedUtc must not precede startedUtc",
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


def _require_single_input_role(
    inputs: list[dict[str, object]],
    role: str,
) -> dict[str, object]:
    matches = [entry for entry in inputs if entry["role"] == role]
    if len(matches) != 1:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"$.inputs must contain exactly one {role!r} role claim",
        )
    return matches[0]


def _resolve_input_ref(
    ref: dict[str, object],
    inputs_by_key: dict[tuple[object, object], dict[str, object]],
    where: str,
) -> tuple[tuple[object, object], dict[str, object]]:
    key = (ref["role"], ref["path"])
    claim = inputs_by_key.get(key)
    if claim is None:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"{where} does not reference a declared $.inputs role/path claim",
        )
    return key, claim


def _require_unreused_ref(
    key: tuple[object, object],
    used: set[tuple[object, object]],
    where: str,
) -> None:
    if key in used:
        fail("PF-EVIDENCE-INVARIANT", f"{where} reuses a typed input claim")
    used.add(key)


def _require_exact_role_refs(
    inputs: list[dict[str, object]],
    role: str,
    referenced: set[tuple[object, object]],
) -> None:
    claimed = {
        (entry["role"], entry["path"])
        for entry in inputs
        if entry["role"] == role
    }
    if claimed != referenced:
        fail(
            "PF-EVIDENCE-INVARIANT",
            f"$.inputs role {role!r} must be referenced exactly once without dangling claims",
        )


def _validate_typed_bindings(
    root: dict[str, object],
    catalog: dict[str, object],
    host: dict[str, object],
    policies: list[dict[str, object]],
    inputs: list[dict[str, object]],
    logs: list[dict[str, object]],
) -> None:
    inputs_by_key = {
        (entry["role"], entry["path"]): entry
        for entry in inputs
    }
    logs_by_path = {entry["path"]: entry for entry in logs}

    catalog_claim = _require_single_input_role(inputs, "gate-catalog")
    if catalog_claim["sha256"] != catalog["contentSha256"]:
        fail(
            "PF-EVIDENCE-INVARIANT",
            "the gate-catalog input SHA-256 must equal $.gateCatalog.contentSha256",
        )

    run_context_claim = _require_single_input_role(inputs, "clean-room-run-context")
    run_context_ref = root["runContextInput"]
    if not isinstance(run_context_ref, dict):
        fail("PF-EVIDENCE-SCHEMA", "$.runContextInput must be an object")
    _, resolved_run_context = _resolve_input_ref(
        run_context_ref,
        inputs_by_key,
        "$.runContextInput",
    )
    if resolved_run_context is not run_context_claim:
        fail(
            "PF-EVIDENCE-INVARIANT",
            "$.runContextInput must reference the unique clean-room-run-context claim",
        )

    observation_claim = _require_single_input_role(inputs, "host-observation")
    observation_ref = host["observationInput"]
    if not isinstance(observation_ref, dict):
        fail("PF-EVIDENCE-SCHEMA", "$.hostAttestation.observationInput must be an object")
    _, resolved_observation = _resolve_input_ref(
        observation_ref,
        inputs_by_key,
        "$.hostAttestation.observationInput",
    )
    if resolved_observation is not observation_claim:
        fail(
            "PF-EVIDENCE-INVARIANT",
            "$.hostAttestation.observationInput must reference the unique host-observation claim",
        )
    if observation_claim["sha256"] != host["observationSha256"]:
        fail(
            "PF-EVIDENCE-INVARIANT",
            "the host-observation input SHA-256 must equal hostAttestation.observationSha256",
        )

    _require_single_input_role(inputs, "sandbox-policy-renderer")

    rendered_refs: set[tuple[object, object]] = set()
    context_refs: set[tuple[object, object]] = set()
    receipt_refs: set[tuple[object, object]] = set()
    stream_paths: set[object] = set()
    for policy_index, policy in enumerate(policies):
        rendered_ref = policy["renderedPolicyInput"]
        if not isinstance(rendered_ref, dict):
            fail(
                "PF-EVIDENCE-SCHEMA",
                f"$.sandboxPolicies[{policy_index}].renderedPolicyInput must be an object",
            )
        rendered_key, rendered_claim = _resolve_input_ref(
            rendered_ref,
            inputs_by_key,
            f"$.sandboxPolicies[{policy_index}].renderedPolicyInput",
        )
        _require_unreused_ref(
            rendered_key,
            rendered_refs,
            f"$.sandboxPolicies[{policy_index}].renderedPolicyInput",
        )
        if rendered_claim["sha256"] != policy["renderedSha256"]:
            fail(
                "PF-EVIDENCE-INVARIANT",
                f"$.sandboxPolicies[{policy_index}].renderedPolicyInput SHA-256 "
                "must equal renderedSha256",
            )

        probes = require_array(
            policy["probes"],
            f"$.sandboxPolicies[{policy_index}].probes",
            nonempty=True,
        )
        for probe_index, probe in enumerate(probes):
            if not isinstance(probe, dict):
                fail(
                    "PF-EVIDENCE-SCHEMA",
                    f"$.sandboxPolicies[{policy_index}].probes[{probe_index}] must be an object",
                )
            receipt = probe["receipt"]
            if not isinstance(receipt, dict):
                fail(
                    "PF-EVIDENCE-SCHEMA",
                    f"$.sandboxPolicies[{policy_index}].probes[{probe_index}].receipt must be an object",
                )
            receipt_where = (
                f"$.sandboxPolicies[{policy_index}].probes[{probe_index}].receipt"
            )
            context_ref = receipt["invocationContextInput"]
            if not isinstance(context_ref, dict):
                fail(
                    "PF-EVIDENCE-SCHEMA",
                    f"{receipt_where}.invocationContextInput must be an object",
                )
            context_key, _ = _resolve_input_ref(
                context_ref,
                inputs_by_key,
                f"{receipt_where}.invocationContextInput",
            )
            _require_unreused_ref(
                context_key,
                context_refs,
                f"{receipt_where}.invocationContextInput",
            )
            receipt_ref = {"role": receipt["role"], "path": receipt["path"]}
            receipt_key, _ = _resolve_input_ref(
                receipt_ref,
                inputs_by_key,
                receipt_where,
            )
            _require_unreused_ref(receipt_key, receipt_refs, receipt_where)
            for stream in ("stdoutLog", "stderrLog"):
                path = receipt[stream]
                if path in stream_paths:
                    fail(
                        "PF-EVIDENCE-INVARIANT",
                        f"{receipt_where}.{stream} reuses a sandbox probe stream path",
                    )
                stream_paths.add(path)
                if path not in logs_by_path:
                    fail(
                        "PF-EVIDENCE-INVARIANT",
                        f"{receipt_where}.{stream} does not reference $.logs",
                    )

    _require_exact_role_refs(
        inputs,
        "sandbox-rendered-policy",
        rendered_refs,
    )
    _require_exact_role_refs(
        inputs,
        "sandbox-invocation-context",
        context_refs,
    )
    _require_exact_role_refs(
        inputs,
        "sandbox-invocation-receipt",
        receipt_refs,
    )


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
        optional={"gateCatalog", "runContextInput"},
    )
    if root["schema"] != SCHEMA:
        fail("PF-EVIDENCE-SCHEMA", f"$.schema must be {SCHEMA!r}")
    evidence_id = require_pattern(root["id"], EVIDENCE_ID_RE, "$.id")
    try:
        evidence_date = dt.datetime.strptime(evidence_id[3:11], "%Y%m%d").date()
    except ValueError:
        fail("PF-EVIDENCE-SCHEMA", "$.id contains a nonexistent UTC calendar date")
    result = require_enum(root["result"], {"passed", "failed", "skipped"}, "$.result")
    typed_bindings = "gateCatalog" in root
    _require_typed_field(root, "runContextInput", typed_bindings, "$")
    catalog: dict[str, object] | None = None
    if typed_bindings:
        catalog = _validate_gate_catalog_ref(root["gateCatalog"])
        _validate_role_path_ref(
            root["runContextInput"],
            "$.runContextInput",
            expected_role="clean-room-run-context",
        )
    qualification, _ = _validate_gate(root["gate"])
    repository = _validate_repository(root["repository"])
    host = _validate_host(root["hostAttestation"], typed_bindings=typed_bindings)
    environment = _validate_environment(root["environment"])
    policies = _validate_sandbox_policies(
        root["sandboxPolicies"],
        typed_bindings=typed_bindings,
    )
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
    if catalog is not None:
        _validate_typed_bindings(root, catalog, host, policies, inputs, logs)
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
