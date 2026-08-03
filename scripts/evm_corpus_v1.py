#!/usr/bin/env python3
"""Closed validator for proof-forge.evm-corpus-case.v1 / evm-observation.v1.

Pure structural schema foundation (EVMOZ-002). Not an evidence envelope, not a
product import, not an OZ/family claim oracle.

Requires isolated no-site Python: /usr/bin/python3 -I -S
"""

from __future__ import annotations

import json
import posixpath
import re
import sys
import unicodedata
from pathlib import Path
from typing import Callable, NoReturn


SCHEMA_CASE = "proof-forge.evm-corpus-case.v1"
SCHEMA_OBS = "proof-forge.evm-observation.v1"

MAX_CASE_BYTES = 64 * 1024
MAX_OBS_BYTES = 256 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_ACTORS = 8
MAX_STEPS = 32
MAX_LOGS = 32
MAX_TOPICS = 4
MAX_DIAG_PATTERNS = 8
MAX_DIAG_PATTERN_BYTES = 128
MAX_REASON_BYTES = 128

CASE_CLASSES = frozenset(
    {"primitive", "adapter", "oz-behavior", "abi", "blocked", "oos"}
)
LEGS = frozenset({"reference", "pf-anvil", "oz-anvil"})
VERDICTS = frozenset({"pass", "fail", "skip", "tool-blocked", "proposal"})
SHARED_STATUS = frozenset({"success", "revert", "trap", "blocked"})
COMPARE_MODES = frozenset({"shared", "shared-projection", "full-evm", "none"})
RUNNERS = frozenset(
    {"lean-focused", "product-cli", "anvil-matrix", "schema-only"}
)
ACTOR_ROLES = frozenset({"eoa", "contract", "system"})
STEP_ACTIONS = frozenset({"call", "deploy", "view", "assert-blocked"})
BLOCKED_PHASES = frozenset(
    {"capability", "plan", "lower", "type", "normalize"}
)
BLOCKED_REASON_KINDS = frozenset(
    {"planInvariant", "capabilityMissing", "unsupportedShape"}
)
FORBIDDEN_EARLY_FAILURE = (
    "toolchain-mismatch",
    "parse-error",
    "unrelated-type-error",
    "missing-tool",
)
OZ_PROJECTION_REQUIRED = (
    "authSubject",
    "stateDelta",
    "returnValue",
    "revertStatus",
    "rollback",
)

SHA256_RE = re.compile(r"[0-9a-f]{64}")
GIT_OBJECT_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")
SAFE_ID_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._:+-]{0,254}[A-Za-z0-9])?")
HEX_BYTES_RE = re.compile(r"0x(?:[0-9a-f]{2})*")
# Exact EVM storage word: 32 raw bytes as 0x + 64 lowercase hex digits.
STORAGE_WORD32_RE = re.compile(r"0x[0-9a-f]{64}")
ADDRESS20_RE = re.compile(r"0x[0-9a-f]{40}")
UINT_DECIMAL_RE = re.compile(r"0|[1-9][0-9]*")

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "testdata" / "evm-corpus" / "v1" / "schema-tests"

# Disk negative fixtures: basename → exact expected CorpusError.code.
# Any other code (or acceptance) fails the self-test.
NEGATIVE_FIXTURE_CODES: dict[str, str] = {
    "case-abi-no-same-call-bytes.json": "PF-CORPUS-INVARIANT",
    "case-adapter-family-credit.json": "PF-CORPUS-INVARIANT",
    "case-blocked-missing.json": "PF-CORPUS-INVARIANT",
    "case-duplicate-actor.json": "PF-CORPUS-INVARIANT",
    "case-duplicate-key.json": "PF-CORPUS-DUPLICATE-KEY",
    "case-invalid-class.json": "PF-CORPUS-SCHEMA",
    "case-non-canonical.json": "PF-CORPUS-CANONICAL",
    "case-oos-draft-decision.json": "PF-CORPUS-INVARIANT",
    "case-oversize.json": "PF-CORPUS-LIMIT",
    "case-oz-missing-projection.json": "PF-CORPUS-INVARIANT",
    "case-path-traversal.json": "PF-CORPUS-PATH",
    "case-skip-as-pass.json": "PF-CORPUS-INVARIANT",
    "case-unknown-field.json": "PF-CORPUS-SCHEMA",
    "obs-reference-with-evm.json": "PF-CORPUS-INVARIANT",
    "obs-skip-as-pass.json": "PF-CORPUS-INVARIANT",
    "obs-storage-slot-wrong-width.json": "PF-CORPUS-SCHEMA",
    "obs-storage-slots-unsorted.json": "PF-CORPUS-INVARIANT",
}


class CorpusError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code

    def render(self) -> str:
        return f"{self.code}: {self}"


def fail(code: str, message: str) -> NoReturn:
    raise CorpusError(code, message)


def _where(parent: str, field: str) -> str:
    return f"{parent}.{field}" if parent else field


def _diagnostic_repr(value: str, *, limit: int = 96) -> str:
    rendered = ascii(value)
    if len(rendered) > limit:
        rendered = rendered[: limit - 3] + "..."
    return rendered


def _require_json_key(key: object, where: str) -> str:
    if not isinstance(key, str):
        fail("PF-CORPUS-KEY", f"{where} contains a non-string object key")
    if (
        len(key) > 256
        or not key
        or any(ord(char) < 0x21 or ord(char) > 0x7E for char in key)
    ):
        fail(
            "PF-CORPUS-KEY",
            f"{where} contains an object key outside the ASCII-graphic/256 "
            f"profile: {_diagnostic_repr(key)}",
        )
    return key


def require_keys(
    value: object,
    required: set[str],
    where: str,
    optional: set[str] | None = None,
) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("PF-CORPUS-SCHEMA", f"{where} must be an object")
    optional = optional or set()
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required - optional)
    if missing:
        fail(
            "PF-CORPUS-SCHEMA",
            f"{where} is missing required fields: {', '.join(missing)}",
        )
    if unknown:
        fail(
            "PF-CORPUS-SCHEMA",
            f"{where} contains unknown fields: "
            f"{', '.join(_diagnostic_repr(field) for field in unknown)}",
        )
    return value  # type: ignore[return-value]


def require_array(
    value: object, where: str, *, nonempty: bool = False
) -> list[object]:
    if not isinstance(value, list):
        fail("PF-CORPUS-SCHEMA", f"{where} must be an array")
    if nonempty and not value:
        fail("PF-CORPUS-INVARIANT", f"{where} must be non-empty")
    return value  # type: ignore[return-value]


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
        fail("PF-CORPUS-SCHEMA", f"{where} must be {qualifier}")
    if "\x00" in value or any(0xD800 <= ord(char) <= 0xDFFF for char in value):
        fail("PF-CORPUS-SCHEMA", f"{where} contains an invalid Unicode scalar")
    if ascii_only and not value.isascii():
        fail("PF-CORPUS-SCHEMA", f"{where} must be ASCII")
    if len(value.encode("utf-8")) > max_bytes:
        fail("PF-CORPUS-LIMIT", f"{where} exceeds {max_bytes} UTF-8 bytes")
    return value


def require_bool(value: object, where: str) -> bool:
    if type(value) is not bool:
        fail("PF-CORPUS-SCHEMA", f"{where} must be a boolean")
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
            "PF-CORPUS-SCHEMA",
            f"{where} must be an integer in [{minimum}, {maximum}]",
        )
    return value


def require_enum(value: object, allowed: set[str] | frozenset[str], where: str) -> str:
    text = require_text(value, where, ascii_only=True)
    if text not in allowed:
        fail(
            "PF-CORPUS-SCHEMA",
            f"{where} must be one of: {', '.join(sorted(allowed))}",
        )
    return text


def require_pattern(value: object, pattern: re.Pattern[str], where: str) -> str:
    text = require_text(value, where, ascii_only=True)
    if pattern.fullmatch(text) is None:
        fail("PF-CORPUS-SCHEMA", f"{where} has an invalid format")
    return text


def require_sha256(value: object, where: str) -> str:
    return require_pattern(value, SHA256_RE, where)


def require_safe_id(value: object, where: str) -> str:
    return require_pattern(value, SAFE_ID_RE, where)


def require_case_id(value: object, where: str) -> str:
    text = require_safe_id(value, where)
    if "." not in text:
        fail("PF-CORPUS-SCHEMA", f"{where} must be a dotted case-id")
    return text


def require_hex_bytes(value: object, where: str) -> str:
    return require_pattern(value, HEX_BYTES_RE, where)


def require_storage_word32(value: object, where: str) -> str:
    """Exact 32-byte EVM storage slot or value (0x + 64 lowercase hex)."""
    return require_pattern(value, STORAGE_WORD32_RE, where)


def require_address20(value: object, where: str) -> str:
    return require_pattern(value, ADDRESS20_RE, where)


def require_uint_decimal(value: object, where: str) -> str:
    return require_pattern(value, UINT_DECIMAL_RE, where)


def require_relative_path(value: object, where: str) -> str:
    path = require_text(value, where, max_bytes=4096)
    if unicodedata.normalize("NFC", path) != path:
        fail("PF-CORPUS-PATH", f"{where} must be Unicode NFC")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in path):
        fail("PF-CORPUS-PATH", f"{where} contains an ASCII control character")
    if (
        path == "."
        or path.startswith("/")
        or path.endswith("/")
        or "\\" in path
        or posixpath.normpath(path) != path
    ):
        fail("PF-CORPUS-PATH", f"{where} must be a normalized relative POSIX path")
    parts = path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        fail("PF-CORPUS-PATH", f"{where} contains a forbidden path component")
    return path


def require_sorted_unique_strings(values: list[str], where: str) -> None:
    if len(set(values)) != len(values):
        fail("PF-CORPUS-INVARIANT", f"{where} contains duplicate entries")
    if values != sorted(values):
        fail("PF-CORPUS-INVARIANT", f"{where} must use stable ascending order")


def _reject_float(_: str) -> NoReturn:
    fail("PF-CORPUS-NUMBER", "floating-point JSON numbers are forbidden")


def _parse_safe_int(text: str) -> int:
    value = int(text, 10)
    if abs(value) > MAX_SAFE_INTEGER:
        fail(
            "PF-CORPUS-NUMBER",
            f"JSON integer exceeds the interoperable range: {text}",
        )
    return value


def _reject_constant(text: str) -> NoReturn:
    fail("PF-CORPUS-NUMBER", f"non-finite JSON number is forbidden: {text}")


def _object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        _require_json_key(key, "JSON")
        if key in result:
            fail(
                "PF-CORPUS-DUPLICATE-KEY",
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
            fail("PF-CORPUS-LIMIT", f"JSON exceeds {MAX_JSON_NODES} values")
        if depth > MAX_JSON_DEPTH:
            fail("PF-CORPUS-LIMIT", f"JSON exceeds depth {MAX_JSON_DEPTH}")
        if current is None or type(current) is bool:
            continue
        if type(current) is int:
            if abs(current) > MAX_SAFE_INTEGER:
                fail("PF-CORPUS-NUMBER", f"{where} contains an unsafe integer")
            continue
        if isinstance(current, float):
            fail("PF-CORPUS-NUMBER", f"{where} contains a float")
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
        fail("PF-CORPUS-SCHEMA", f"{where} contains a non-JSON value")


def decode_json(data: bytes, *, max_bytes: int) -> object:
    if len(data) > max_bytes:
        fail("PF-CORPUS-LIMIT", f"input exceeds {max_bytes} bytes")
    if data.startswith(b"\xef\xbb\xbf"):
        fail("PF-CORPUS-JSON", "UTF-8 BOM is forbidden")
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        fail("PF-CORPUS-JSON", f"input is not UTF-8: byte {exc.start}")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_object_pairs,
            parse_int=_parse_safe_int,
            parse_float=_reject_float,
            parse_constant=_reject_constant,
        )
    except CorpusError:
        raise
    except (json.JSONDecodeError, RecursionError, ValueError) as exc:
        fail("PF-CORPUS-JSON", f"invalid JSON: {exc}")
    _validate_json_tree(value)
    return value


def canonical_bytes(value: object) -> bytes:
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
        fail("PF-CORPUS-JSON", f"cannot encode canonical JSON: {exc}")
    return text.encode("utf-8")


def decode_canonical(data: bytes, *, max_bytes: int) -> object:
    value = decode_json(data, max_bytes=max_bytes)
    encoded = canonical_bytes(value)
    if encoded != data:
        fail(
            "PF-CORPUS-CANONICAL",
            "input bytes are not the restricted PF-JCS canonical encoding",
        )
    return value


def _validate_string_pattern_list(value: object, where: str) -> list[str]:
    items = require_array(value, where)
    if len(items) > MAX_DIAG_PATTERNS:
        fail(
            "PF-CORPUS-LIMIT",
            f"{where} exceeds {MAX_DIAG_PATTERNS} diagnostic patterns",
        )
    out: list[str] = []
    for index, item in enumerate(items):
        text = require_text(
            item, f"{where}[{index}]", max_bytes=MAX_DIAG_PATTERN_BYTES
        )
        out.append(text)
    if len(set(out)) != len(out):
        fail("PF-CORPUS-INVARIANT", f"{where} contains duplicate entries")
    if out != sorted(out):
        fail("PF-CORPUS-INVARIANT", f"{where} must use stable ascending order")
    return out


def _validate_log_expectation(value: object, where: str) -> dict[str, object]:
    obj = require_keys(value, {"address", "topics", "data"}, where)
    address = obj["address"]
    if address is not None:
        require_address20(address, _where(where, "address"))
    topics = require_array(obj["topics"], _where(where, "topics"))
    if len(topics) > MAX_TOPICS:
        fail("PF-CORPUS-LIMIT", f"{where}.topics exceeds {MAX_TOPICS}")
    for index, topic in enumerate(topics):
        require_hex_bytes(topic, f"{where}.topics[{index}]")
    data = obj["data"]
    if data is not None:
        require_hex_bytes(data, _where(where, "data"))
    return obj


def _validate_pins(value: object, case_class: str) -> dict[str, object]:
    where = "$.pins"
    obj = require_keys(
        value,
        {
            "pfCommit",
            "sourcePath",
            "sourceHash",
            "semanticHash",
            "ozCommit",
            "target",
            "profile",
            "toolLockDigest",
            "solcVersion",
            "anvilVersion",
            "hardfork",
            "runner",
        },
        where,
    )
    require_pattern(obj["pfCommit"], GIT_OBJECT_RE, _where(where, "pfCommit"))
    require_relative_path(obj["sourcePath"], _where(where, "sourcePath"))
    require_sha256(obj["sourceHash"], _where(where, "sourceHash"))
    require_sha256(obj["semanticHash"], _where(where, "semanticHash"))
    oz = obj["ozCommit"]
    if oz is None:
        if case_class in {"oz-behavior", "abi"}:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where}.ozCommit is required for class={case_class}",
            )
    else:
        require_pattern(oz, GIT_OBJECT_RE, _where(where, "ozCommit"))
        if case_class in {"primitive", "blocked"}:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where}.ozCommit must be null for class={case_class}",
            )
    target = require_text(obj["target"], _where(where, "target"), ascii_only=True)
    if target != "evm":
        fail("PF-CORPUS-SCHEMA", f"{where}.target must be 'evm'")
    require_safe_id(obj["profile"], _where(where, "profile"))
    require_sha256(obj["toolLockDigest"], _where(where, "toolLockDigest"))
    require_safe_id(obj["solcVersion"], _where(where, "solcVersion"))
    require_safe_id(obj["anvilVersion"], _where(where, "anvilVersion"))
    require_safe_id(obj["hardfork"], _where(where, "hardfork"))
    require_enum(obj["runner"], RUNNERS, _where(where, "runner"))
    return obj


def _validate_actors(value: object) -> list[dict[str, object]]:
    where = "$.actors"
    items = require_array(value, where, nonempty=True)
    if len(items) > MAX_ACTORS:
        fail("PF-CORPUS-LIMIT", f"{where} exceeds {MAX_ACTORS} actors")
    actors: list[dict[str, object]] = []
    ids: list[str] = []
    for index, item in enumerate(items):
        item_where = f"{where}[{index}]"
        obj = require_keys(item, {"id", "role"}, item_where)
        actor_id = require_safe_id(obj["id"], _where(item_where, "id"))
        require_enum(obj["role"], ACTOR_ROLES, _where(item_where, "role"))
        ids.append(actor_id)
        actors.append(obj)
    if len(set(ids)) != len(ids):
        fail("PF-CORPUS-INVARIANT", f"{where} contains duplicate actor ids")
    if ids != sorted(ids):
        fail("PF-CORPUS-INVARIANT", f"{where} must be sorted by id ascending")
    return actors


def _validate_steps(
    value: object, actor_ids: set[str], case_class: str
) -> list[dict[str, object]]:
    where = "$.steps"
    items = require_array(value, where, nonempty=True)
    if len(items) > MAX_STEPS:
        fail("PF-CORPUS-LIMIT", f"{where} exceeds {MAX_STEPS} steps")
    steps: list[dict[str, object]] = []
    for index, item in enumerate(items):
        item_where = f"{where}[{index}]"
        obj = require_keys(
            item,
            {
                "index",
                "action",
                "actor",
                "entry",
                "args",
                "valueWei",
                "expectedSharedStatus",
                "expectedLogs",
            },
            item_where,
        )
        step_index = require_int(
            obj["index"], _where(item_where, "index"), maximum=MAX_STEPS - 1
        )
        if step_index != index:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{item_where}.index must equal array position {index}",
            )
        action = require_enum(obj["action"], STEP_ACTIONS, _where(item_where, "action"))
        actor = require_safe_id(obj["actor"], _where(item_where, "actor"))
        if actor not in actor_ids:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{item_where}.actor is not declared in $.actors",
            )
        entry = obj["entry"]
        if action in {"call", "view"}:
            require_safe_id(entry, _where(item_where, "entry"))
        else:
            if entry is not None:
                require_safe_id(entry, _where(item_where, "entry"))
        require_array(obj["args"], _where(item_where, "args"))
        require_uint_decimal(obj["valueWei"], _where(item_where, "valueWei"))
        status = require_enum(
            obj["expectedSharedStatus"],
            SHARED_STATUS,
            _where(item_where, "expectedSharedStatus"),
        )
        logs = require_array(obj["expectedLogs"], _where(item_where, "expectedLogs"))
        if len(logs) > MAX_LOGS:
            fail(
                "PF-CORPUS-LIMIT",
                f"{item_where}.expectedLogs exceeds {MAX_LOGS}",
            )
        for log_index, log in enumerate(logs):
            _validate_log_expectation(
                log, f"{item_where}.expectedLogs[{log_index}]"
            )
        if case_class == "blocked":
            if action != "assert-blocked" or status != "blocked":
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"{item_where} blocked class requires action=assert-blocked "
                    "and expectedSharedStatus=blocked",
                )
        else:
            if action == "assert-blocked" or status == "blocked":
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"{item_where} assert-blocked/blocked status only allowed "
                    "for class=blocked",
                )
        steps.append(obj)
    return steps


def _validate_oracle(
    value: object, case_class: str, oz_commit: object
) -> dict[str, object]:
    where = "$.oracle"
    obj = require_keys(value, {"legs", "compare", "sameCallBytes"}, where)
    legs_raw = require_array(obj["legs"], _where(where, "legs"), nonempty=True)
    legs: list[str] = []
    for index, leg in enumerate(legs_raw):
        legs.append(require_enum(leg, LEGS, f"{where}.legs[{index}]"))
    if len(set(legs)) != len(legs):
        fail("PF-CORPUS-INVARIANT", f"{where}.legs contains duplicate legs")
    compare = require_enum(obj["compare"], COMPARE_MODES, _where(where, "compare"))
    same = require_bool(obj["sameCallBytes"], _where(where, "sameCallBytes"))

    leg_set = set(legs)
    if case_class == "primitive":
        if leg_set != {"reference", "pf-anvil"} or compare != "shared" or same:
            fail(
                "PF-CORPUS-INVARIANT",
                "primitive oracle must be legs={reference,pf-anvil} "
                "compare=shared sameCallBytes=false",
            )
    elif case_class == "adapter":
        if "oz-anvil" in leg_set and oz_commit is None:
            fail(
                "PF-CORPUS-INVARIANT",
                "adapter oz-anvil leg requires pins.ozCommit",
            )
        if compare not in {"shared", "shared-projection"}:
            fail(
                "PF-CORPUS-INVARIANT",
                "adapter oracle.compare must be shared or shared-projection",
            )
        if same:
            fail(
                "PF-CORPUS-INVARIANT",
                "adapter must not claim sameCallBytes=true",
            )
    elif case_class == "oz-behavior":
        if leg_set != {"reference", "pf-anvil", "oz-anvil"}:
            fail(
                "PF-CORPUS-INVARIANT",
                "oz-behavior requires legs reference+pf-anvil+oz-anvil",
            )
        if compare != "shared-projection" or same:
            fail(
                "PF-CORPUS-INVARIANT",
                "oz-behavior requires compare=shared-projection "
                "sameCallBytes=false",
            )
    elif case_class == "abi":
        if leg_set != {"reference", "pf-anvil", "oz-anvil"}:
            fail(
                "PF-CORPUS-INVARIANT",
                "abi requires legs reference+pf-anvil+oz-anvil",
            )
        if compare != "full-evm" or not same:
            fail(
                "PF-CORPUS-INVARIANT",
                "abi requires compare=full-evm sameCallBytes=true",
            )
    elif case_class == "blocked":
        if legs != ["reference"] or compare != "none" or same:
            fail(
                "PF-CORPUS-INVARIANT",
                "blocked oracle must be legs=[reference] compare=none "
                "sameCallBytes=false",
            )
    elif case_class == "oos":
        if compare != "none" or same:
            fail(
                "PF-CORPUS-INVARIANT",
                "oos oracle must use compare=none sameCallBytes=false",
            )
    return obj


def _validate_skip_policy(
    value: object, oracle_legs: list[str]
) -> dict[str, object]:
    where = "$.skipPolicy"
    obj = require_keys(
        value,
        {
            "optionalLegs",
            "requiredTools",
            "missingOptionalTool",
            "requiredToolFailure",
        },
        where,
    )
    optional_raw = require_array(obj["optionalLegs"], _where(where, "optionalLegs"))
    optional: list[str] = []
    for index, leg in enumerate(optional_raw):
        optional.append(
            require_enum(leg, LEGS, f"{where}.optionalLegs[{index}]")
        )
    require_sorted_unique_strings(optional, _where(where, "optionalLegs"))
    for leg in optional:
        if leg not in oracle_legs:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where}.optionalLegs entry {leg!r} is not in oracle.legs",
            )
    tools_raw = require_array(obj["requiredTools"], _where(where, "requiredTools"))
    tools: list[str] = []
    for index, tool in enumerate(tools_raw):
        tools.append(require_safe_id(tool, f"{where}.requiredTools[{index}]"))
    require_sorted_unique_strings(tools, _where(where, "requiredTools"))
    missing = require_text(
        obj["missingOptionalTool"],
        _where(where, "missingOptionalTool"),
        ascii_only=True,
    )
    if missing != "skip-leg":
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.missingOptionalTool must be 'skip-leg' "
            "(skip is not pass; only optional legs may skip)",
        )
    required_fail = require_text(
        obj["requiredToolFailure"],
        _where(where, "requiredToolFailure"),
        ascii_only=True,
    )
    if required_fail != "fail":
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.requiredToolFailure must be 'fail' "
            "(required tool failure cannot skip or pass)",
        )
    return obj


def _validate_claims(value: object, case_class: str) -> dict[str, object]:
    where = "$.claims"
    obj = require_keys(
        value, {"familyCredit", "abiCredit", "standardCredit"}, where
    )
    family = require_bool(obj["familyCredit"], _where(where, "familyCredit"))
    abi = require_bool(obj["abiCredit"], _where(where, "abiCredit"))
    standard = require_bool(obj["standardCredit"], _where(where, "standardCredit"))
    if case_class in {"primitive", "adapter", "blocked", "oos"}:
        if family or abi or standard:
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where} must be all-false for class={case_class}",
            )
    elif case_class == "oz-behavior":
        if abi or standard:
            fail(
                "PF-CORPUS-INVARIANT",
                "oz-behavior forbids abiCredit/standardCredit",
            )
    elif case_class == "abi":
        if family:
            fail(
                "PF-CORPUS-INVARIANT",
                "abi class forbids familyCredit (family status is separate)",
            )
    return obj


def _validate_adapter_body(value: object) -> dict[str, object]:
    where = "$.adapter"
    obj = require_keys(
        value,
        {"pfDriver", "ozDriver", "retainedFields", "discardedFields"},
        where,
    )
    require_safe_id(obj["pfDriver"], _where(where, "pfDriver"))
    require_safe_id(obj["ozDriver"], _where(where, "ozDriver"))
    retained = _validate_field_name_list(
        obj["retainedFields"], _where(where, "retainedFields"), nonempty=True
    )
    discarded = _validate_field_name_list(
        obj["discardedFields"], _where(where, "discardedFields")
    )
    overlap = sorted(set(retained) & set(discarded))
    if overlap:
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where} retained/discarded overlap: {', '.join(overlap)}",
        )
    return obj


def _validate_field_name_list(
    value: object, where: str, *, nonempty: bool = False
) -> list[str]:
    items = require_array(value, where, nonempty=nonempty)
    out: list[str] = []
    for index, item in enumerate(items):
        out.append(require_safe_id(item, f"{where}[{index}]"))
    require_sorted_unique_strings(out, where)
    return out


def _validate_shared_projection(value: object) -> dict[str, object]:
    where = "$.sharedProjection"
    obj = require_keys(
        value,
        {"schemaId", "retainedFields", "discardedFields"},
        where,
    )
    require_safe_id(obj["schemaId"], _where(where, "schemaId"))
    retained = _validate_field_name_list(
        obj["retainedFields"], _where(where, "retainedFields"), nonempty=True
    )
    discarded = _validate_field_name_list(
        obj["discardedFields"], _where(where, "discardedFields")
    )
    missing = [field for field in OZ_PROJECTION_REQUIRED if field not in retained]
    if missing:
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.retainedFields missing required scene fields: "
            f"{', '.join(missing)}",
        )
    forbidden_drop = [
        field for field in OZ_PROJECTION_REQUIRED if field in discarded
    ]
    if forbidden_drop:
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.discardedFields must not drop scene-critical fields: "
            f"{', '.join(forbidden_drop)}",
        )
    overlap = sorted(set(retained) & set(discarded))
    if overlap:
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where} retained/discarded overlap: {', '.join(overlap)}",
        )
    return obj


def _validate_blocked_body(value: object) -> dict[str, object]:
    where = "$.blocked"
    obj = require_keys(
        value,
        {
            "phase",
            "target",
            "reason",
            "reasonKind",
            "diagnosticPatterns",
            "forbiddenEarlyFailure",
        },
        where,
    )
    require_enum(obj["phase"], BLOCKED_PHASES, _where(where, "phase"))
    target = require_text(obj["target"], _where(where, "target"), ascii_only=True)
    if target != "evm":
        fail("PF-CORPUS-SCHEMA", f"{where}.target must be 'evm'")
    require_text(obj["reason"], _where(where, "reason"), max_bytes=MAX_REASON_BYTES)
    require_enum(
        obj["reasonKind"], BLOCKED_REASON_KINDS, _where(where, "reasonKind")
    )
    _validate_string_pattern_list(
        obj["diagnosticPatterns"], _where(where, "diagnosticPatterns")
    )
    early = require_array(
        obj["forbiddenEarlyFailure"], _where(where, "forbiddenEarlyFailure")
    )
    early_text = [
        require_text(item, f"{where}.forbiddenEarlyFailure[{index}]", ascii_only=True)
        for index, item in enumerate(early)
    ]
    if early_text != list(FORBIDDEN_EARLY_FAILURE):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.forbiddenEarlyFailure must equal the fixed contract "
            f"tuple order {list(FORBIDDEN_EARLY_FAILURE)} "
            f"(not ASCII sort / not a reorderable set)",
        )
    return obj


def _validate_oos_body(value: object) -> dict[str, object]:
    where = "$.oos"
    obj = require_keys(
        value, {"decisionId", "decisionStatus", "decisionRef"}, where
    )
    require_safe_id(obj["decisionId"], _where(where, "decisionId"))
    status = require_text(
        obj["decisionStatus"], _where(where, "decisionStatus"), ascii_only=True
    )
    if status != "accepted":
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.decisionStatus must be 'accepted' "
            "(research proposals cannot use oos)",
        )
    require_relative_path(obj["decisionRef"], _where(where, "decisionRef"))
    return obj


def validate_case(value: object) -> dict[str, object]:
    root = require_keys(
        value,
        {
            "schema",
            "id",
            "class",
            "pins",
            "actors",
            "initialLogicalState",
            "steps",
            "oracle",
            "skipPolicy",
            "claims",
            "adapter",
            "sharedProjection",
            "blocked",
            "oos",
        },
        "$",
    )
    schema = require_text(root["schema"], "$.schema", ascii_only=True)
    if schema != SCHEMA_CASE:
        fail("PF-CORPUS-SCHEMA", f"$.schema must be {SCHEMA_CASE!r}")
    require_case_id(root["id"], "$.id")
    case_class = require_enum(root["class"], CASE_CLASSES, "$.class")
    pins = _validate_pins(root["pins"], case_class)
    actors = _validate_actors(root["actors"])
    actor_ids = {str(actor["id"]) for actor in actors}
    if not isinstance(root["initialLogicalState"], dict):
        fail("PF-CORPUS-SCHEMA", "$.initialLogicalState must be an object")
    _validate_json_tree(root["initialLogicalState"])
    _validate_steps(root["steps"], actor_ids, case_class)
    oracle = _validate_oracle(root["oracle"], case_class, pins["ozCommit"])
    legs = [
        require_enum(leg, LEGS, f"$.oracle.legs[{index}]")
        for index, leg in enumerate(require_array(oracle["legs"], "$.oracle.legs"))
    ]
    _validate_skip_policy(root["skipPolicy"], legs)
    _validate_claims(root["claims"], case_class)

    adapter = root["adapter"]
    projection = root["sharedProjection"]
    blocked = root["blocked"]
    oos = root["oos"]

    if case_class == "adapter":
        if adapter is None:
            fail("PF-CORPUS-INVARIANT", "$.adapter is required for class=adapter")
        _validate_adapter_body(adapter)
    elif adapter is not None:
        fail("PF-CORPUS-INVARIANT", "$.adapter must be null unless class=adapter")

    if case_class == "oz-behavior":
        if projection is None:
            fail(
                "PF-CORPUS-INVARIANT",
                "$.sharedProjection is required for class=oz-behavior",
            )
        _validate_shared_projection(projection)
    elif projection is not None:
        fail(
            "PF-CORPUS-INVARIANT",
            "$.sharedProjection must be null unless class=oz-behavior",
        )

    if case_class == "blocked":
        if blocked is None:
            fail("PF-CORPUS-INVARIANT", "$.blocked is required for class=blocked")
        _validate_blocked_body(blocked)
    elif blocked is not None:
        fail("PF-CORPUS-INVARIANT", "$.blocked must be null unless class=blocked")

    if case_class == "oos":
        if oos is None:
            fail("PF-CORPUS-INVARIANT", "$.oos is required for class=oos")
        _validate_oos_body(oos)
    elif oos is not None:
        fail("PF-CORPUS-INVARIANT", "$.oos must be null unless class=oos")

    return root


def _validate_evm_observation(value: object, where: str) -> dict[str, object]:
    obj = require_keys(
        value,
        {
            "calldata",
            "returndata",
            "storageSlots",
            "logs",
            "revertData",
            "externalCalls",
            "balances",
        },
        where,
    )
    require_hex_bytes(obj["calldata"], _where(where, "calldata"))
    require_hex_bytes(obj["returndata"], _where(where, "returndata"))
    slots = require_array(obj["storageSlots"], _where(where, "storageSlots"))
    slot_keys: list[str] = []
    for index, slot in enumerate(slots):
        slot_where = f"{where}.storageSlots[{index}]"
        slot_obj = require_keys(slot, {"slot", "value"}, slot_where)
        key = require_storage_word32(slot_obj["slot"], _where(slot_where, "slot"))
        require_storage_word32(slot_obj["value"], _where(slot_where, "value"))
        slot_keys.append(key)
    if len(set(slot_keys)) != len(slot_keys):
        fail("PF-CORPUS-INVARIANT", f"{where}.storageSlots has duplicate slots")
    # Lexicographic order of exact storage-word32 wire strings (fixed 64-hex
    # left-zero-padded form ⇒ equals unsigned big-endian numeric slot order).
    if slot_keys != sorted(slot_keys):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.storageSlots must be sorted by slot wire string ascending",
        )
    logs = require_array(obj["logs"], _where(where, "logs"))
    if len(logs) > MAX_LOGS:
        fail("PF-CORPUS-LIMIT", f"{where}.logs exceeds {MAX_LOGS}")
    for index, log in enumerate(logs):
        log_where = f"{where}.logs[{index}]"
        log_obj = require_keys(log, {"address", "topics", "data"}, log_where)
        require_address20(log_obj["address"], _where(log_where, "address"))
        topics = require_array(log_obj["topics"], _where(log_where, "topics"))
        if len(topics) > MAX_TOPICS:
            fail("PF-CORPUS-LIMIT", f"{log_where}.topics exceeds {MAX_TOPICS}")
        for t_index, topic in enumerate(topics):
            require_hex_bytes(topic, f"{log_where}.topics[{t_index}]")
        require_hex_bytes(log_obj["data"], _where(log_where, "data"))
    revert = obj["revertData"]
    if revert is not None:
        require_hex_bytes(revert, _where(where, "revertData"))
    calls = require_array(obj["externalCalls"], _where(where, "externalCalls"))
    for index, call in enumerate(calls):
        call_where = f"{where}.externalCalls[{index}]"
        call_obj = require_keys(
            call,
            {"target", "valueWei", "calldata", "returndata"},
            call_where,
        )
        require_address20(call_obj["target"], _where(call_where, "target"))
        require_uint_decimal(call_obj["valueWei"], _where(call_where, "valueWei"))
        require_hex_bytes(call_obj["calldata"], _where(call_where, "calldata"))
        require_hex_bytes(call_obj["returndata"], _where(call_where, "returndata"))
    balances = require_array(obj["balances"], _where(where, "balances"))
    balance_ids: list[str] = []
    for index, bal in enumerate(balances):
        bal_where = f"{where}.balances[{index}]"
        bal_obj = require_keys(bal, {"id", "wei"}, bal_where)
        balance_ids.append(require_safe_id(bal_obj["id"], _where(bal_where, "id")))
        require_uint_decimal(bal_obj["wei"], _where(bal_where, "wei"))
    if len(set(balance_ids)) != len(balance_ids):
        fail("PF-CORPUS-INVARIANT", f"{where}.balances has duplicate ids")
    if balance_ids != sorted(balance_ids):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where}.balances must be sorted by id ascending",
        )
    return obj


def _validate_shared_observation(value: object) -> dict[str, object]:
    where = "$.shared"
    obj = require_keys(
        value,
        {
            "status",
            "returnValue",
            "logicalState",
            "effects",
            "rollbackEqual",
        },
        where,
    )
    require_enum(obj["status"], SHARED_STATUS, _where(where, "status"))
    # returnValue is any profile JSON value including null
    if not isinstance(obj["logicalState"], dict):
        fail("PF-CORPUS-SCHEMA", f"{where}.logicalState must be an object")
    require_array(obj["effects"], _where(where, "effects"))
    require_bool(obj["rollbackEqual"], _where(where, "rollbackEqual"))
    return obj


def validate_observation(value: object) -> dict[str, object]:
    root = require_keys(
        value,
        {
            "schema",
            "caseId",
            "leg",
            "stepIndex",
            "verdict",
            "skipReason",
            "shared",
            "evm",
        },
        "$",
    )
    schema = require_text(root["schema"], "$.schema", ascii_only=True)
    if schema != SCHEMA_OBS:
        fail("PF-CORPUS-SCHEMA", f"$.schema must be {SCHEMA_OBS!r}")
    require_case_id(root["caseId"], "$.caseId")
    leg = require_enum(root["leg"], LEGS, "$.leg")
    require_int(root["stepIndex"], "$.stepIndex", maximum=MAX_STEPS - 1)
    verdict = require_enum(root["verdict"], VERDICTS, "$.verdict")
    skip_reason = root["skipReason"]
    if verdict == "pass":
        if skip_reason is not None:
            fail(
                "PF-CORPUS-INVARIANT",
                "$.skipReason must be null when verdict=pass (skip is not pass)",
            )
    elif verdict in {"skip", "tool-blocked", "proposal"}:
        require_text(
            skip_reason, "$.skipReason", max_bytes=MAX_REASON_BYTES
        )
    else:  # fail
        if skip_reason is not None:
            fail(
                "PF-CORPUS-INVARIANT",
                "$.skipReason must be null when verdict=fail",
            )
    _validate_shared_observation(root["shared"])
    evm = root["evm"]
    if leg == "reference":
        if evm is not None:
            fail(
                "PF-CORPUS-INVARIANT",
                "$.evm must be null for reference leg "
                "(Reference must not fill EVM-only raw fields)",
            )
    else:
        if evm is None:
            fail(
                "PF-CORPUS-INVARIANT",
                f"$.evm is required for leg={leg}",
            )
        _validate_evm_observation(evm, "$.evm")
    return root


def load_and_validate_case(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    value = decode_canonical(data, max_bytes=MAX_CASE_BYTES)
    return validate_case(value)


def load_and_validate_observation(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    value = decode_canonical(data, max_bytes=MAX_OBS_BYTES)
    return validate_observation(value)


def dumps_canonical(value: object) -> bytes:
    return canonical_bytes(value)


# ---------------------------------------------------------------------------
# Fixture builders / self-test
# ---------------------------------------------------------------------------


def _sha(n: int = 1) -> str:
    return format(n, "064x")


def _git(n: int = 1) -> str:
    return format(n, "040x")


def _base_pins(**overrides: object) -> dict[str, object]:
    pins: dict[str, object] = {
        "pfCommit": _git(1),
        "sourcePath": "Examples/Counter.lean",
        "sourceHash": _sha(1),
        "semanticHash": _sha(2),
        "ozCommit": None,
        "target": "evm",
        "profile": "evm-yul-solc-0.8.34-cancun-v1",
        "toolLockDigest": _sha(3),
        "solcVersion": "0.8.34",
        "anvilVersion": "0.3.0",
        "hardfork": "cancun",
        "runner": "schema-only",
    }
    pins.update(overrides)
    return pins


def _step(
    index: int = 0,
    *,
    action: str = "call",
    actor: str = "deployer",
    entry: object = "inc",
    status: str = "success",
) -> dict[str, object]:
    return {
        "index": index,
        "action": action,
        "actor": actor,
        "entry": entry,
        "args": [],
        "valueWei": "0",
        "expectedSharedStatus": status,
        "expectedLogs": [],
    }


def _claims(
    family: bool = False, abi: bool = False, standard: bool = False
) -> dict[str, object]:
    return {
        "familyCredit": family,
        "abiCredit": abi,
        "standardCredit": standard,
    }


def _skip(
    optional: list[str] | None = None,
    tools: list[str] | None = None,
) -> dict[str, object]:
    return {
        "optionalLegs": list(optional or []),
        "requiredTools": list(tools or []),
        "missingOptionalTool": "skip-leg",
        "requiredToolFailure": "fail",
    }


def make_primitive_case() -> dict[str, object]:
    return {
        "schema": SCHEMA_CASE,
        "id": "pf.primitive.counter.overflow-hold.v1",
        "class": "primitive",
        "pins": _base_pins(runner="product-cli"),
        "actors": [{"id": "deployer", "role": "eoa"}],
        "initialLogicalState": {"count": 0},
        "steps": [_step(0, entry="inc")],
        "oracle": {
            "legs": ["reference", "pf-anvil"],
            "compare": "shared",
            "sameCallBytes": False,
        },
        "skipPolicy": _skip(optional=["pf-anvil"], tools=["anvil", "solc"]),
        "claims": _claims(),
        "adapter": None,
        "sharedProjection": None,
        "blocked": None,
        "oos": None,
    }


def make_adapter_case() -> dict[str, object]:
    return {
        "schema": SCHEMA_CASE,
        "id": "pf.adapter.token.conservation.v1",
        "class": "adapter",
        "pins": _base_pins(ozCommit=_git(9), sourcePath="Examples/Token.lean"),
        "actors": [
            {"id": "alice", "role": "eoa"},
            {"id": "bob", "role": "eoa"},
        ],
        "initialLogicalState": {},
        "steps": [_step(0, actor="alice", entry="transfer")],
        "oracle": {
            "legs": ["pf-anvil", "oz-anvil"],
            "compare": "shared-projection",
            "sameCallBytes": False,
        },
        "skipPolicy": _skip(tools=["anvil"]),
        "claims": _claims(),
        "adapter": {
            "pfDriver": "pf-uint64-token",
            "ozDriver": "oz-erc20-fixture",
            "retainedFields": ["balanceDelta", "conservation", "rollback"],
            "discardedFields": ["erc20Selector", "indexedTopics"],
        },
        "sharedProjection": None,
        "blocked": None,
        "oos": None,
    }


def make_oz_behavior_case() -> dict[str, object]:
    retained = sorted(
        [
            "authSubject",
            "stateDelta",
            "returnValue",
            "revertStatus",
            "rollback",
            "owner",
        ]
    )
    return {
        "schema": SCHEMA_CASE,
        "id": "oz.f01.ownable.onlyowner.behavior.v1",
        "class": "oz-behavior",
        "pins": _base_pins(ozCommit=_git(57)),
        "actors": [
            {"id": "owner", "role": "eoa"},
            {"id": "stranger", "role": "eoa"},
        ],
        "initialLogicalState": {},
        "steps": [_step(0, actor="stranger", entry="transferOwnership", status="revert")],
        "oracle": {
            "legs": ["oz-anvil", "pf-anvil", "reference"],
            "compare": "shared-projection",
            "sameCallBytes": False,
        },
        "skipPolicy": _skip(tools=["anvil"]),
        "claims": _claims(family=True),
        "adapter": None,
        "sharedProjection": {
            "schemaId": "oz.ownable.shared.v1",
            "retainedFields": retained,
            "discardedFields": ["gasUsed", "rawCalldata"],
        },
        "blocked": None,
        "oos": None,
    }


def make_abi_case() -> dict[str, object]:
    return {
        "schema": SCHEMA_CASE,
        "id": "oz.f03.erc20.transfer.abi.v1",
        "class": "abi",
        "pins": _base_pins(ozCommit=_git(57)),
        "actors": [{"id": "alice", "role": "eoa"}],
        "initialLogicalState": {},
        "steps": [_step(0, actor="alice", entry="transfer")],
        "oracle": {
            "legs": ["reference", "oz-anvil", "pf-anvil"],
            "compare": "full-evm",
            "sameCallBytes": True,
        },
        "skipPolicy": _skip(tools=["anvil", "solc"]),
        "claims": _claims(family=False, abi=True, standard=True),
        "adapter": None,
        "sharedProjection": None,
        "blocked": None,
        "oos": None,
    }


def make_blocked_case() -> dict[str, object]:
    return {
        "schema": SCHEMA_CASE,
        "id": "oz.f01.ownable.onlyowner.blocked.v1",
        "class": "blocked",
        "pins": _base_pins(runner="lean-focused", sourcePath="Examples/OwnableLike.lean"),
        "actors": [{"id": "owner", "role": "eoa"}],
        "initialLogicalState": {},
        "steps": [
            _step(
                0,
                action="assert-blocked",
                actor="owner",
                entry=None,
                status="blocked",
            )
        ],
        "oracle": {
            "legs": ["reference"],
            "compare": "none",
            "sameCallBytes": False,
        },
        "skipPolicy": _skip(),
        "claims": _claims(),
        "adapter": None,
        "sharedProjection": None,
        "blocked": {
            "phase": "plan",
            "target": "evm",
            "reason": "context.caller has no EVM address mapping",
            "reasonKind": "planInvariant",
            "diagnosticPatterns": ["context.caller", "planInvariant"],
            "forbiddenEarlyFailure": list(FORBIDDEN_EARLY_FAILURE),
        },
        "oos": None,
    }


def make_oos_case() -> dict[str, object]:
    return {
        "schema": SCHEMA_CASE,
        "id": "oz.f11.proxy.delegatecall.oos.v1",
        "class": "oos",
        "pins": _base_pins(runner="schema-only"),
        "actors": [{"id": "system", "role": "system"}],
        "initialLogicalState": {},
        "steps": [_step(0, action="view", actor="system", entry="noop")],
        "oracle": {
            "legs": ["reference"],
            "compare": "none",
            "sameCallBytes": False,
        },
        "skipPolicy": _skip(),
        "claims": _claims(),
        "adapter": None,
        "sharedProjection": None,
        "blocked": None,
        "oos": {
            "decisionId": "DEC-EVM-PROXY-OOS-001",
            "decisionStatus": "accepted",
            "decisionRef": "docs/research/17-openzeppelin-ethereum-coverage-audit.md",
        },
    }


def make_reference_observation() -> dict[str, object]:
    return {
        "schema": SCHEMA_OBS,
        "caseId": "pf.primitive.counter.overflow-hold.v1",
        "leg": "reference",
        "stepIndex": 0,
        "verdict": "pass",
        "skipReason": None,
        "shared": {
            "status": "revert",
            "returnValue": None,
            "logicalState": {"count": 0},
            "effects": [],
            "rollbackEqual": True,
        },
        "evm": None,
    }


def make_pf_anvil_observation() -> dict[str, object]:
    return {
        "schema": SCHEMA_OBS,
        "caseId": "pf.primitive.counter.overflow-hold.v1",
        "leg": "pf-anvil",
        "stepIndex": 0,
        "verdict": "pass",
        "skipReason": None,
        "shared": {
            "status": "revert",
            "returnValue": None,
            "logicalState": {"count": 0},
            "effects": [],
            "rollbackEqual": True,
        },
        "evm": {
            "calldata": "0x371303c0",
            "returndata": "0x",
            "storageSlots": [
                {
                    "slot": "0x" + "00" * 32,  # storage-word32: 32 zero bytes
                    "value": "0x" + "00" * 32,
                }
            ],
            "logs": [],
            "revertData": "0x",
            "externalCalls": [],
            "balances": [{"id": "deployer", "wei": "0"}],
        },
    }


def _expect_error(label: str, code: str, thunk: Callable[[], object]) -> None:
    try:
        thunk()
    except CorpusError as exc:
        if exc.code != code:
            raise AssertionError(
                f"{label}: expected {code}, got {exc.code}: {exc}"
            ) from exc
        return
    raise AssertionError(f"{label}: expected {code}")


def _roundtrip_case(case: dict[str, object]) -> None:
    raw = dumps_canonical(case)
    assert len(raw) <= MAX_CASE_BYTES, len(raw)
    decoded = decode_canonical(raw, max_bytes=MAX_CASE_BYTES)
    validate_case(decoded)
    assert dumps_canonical(decoded) == raw


def _roundtrip_obs(obs: dict[str, object]) -> None:
    raw = dumps_canonical(obs)
    assert len(raw) <= MAX_OBS_BYTES, len(raw)
    decoded = decode_canonical(raw, max_bytes=MAX_OBS_BYTES)
    validate_observation(decoded)
    assert dumps_canonical(decoded) == raw


def _mutate(
    obj: dict[str, object], mutator: Callable[[dict[str, object]], None]
) -> dict[str, object]:
    import copy

    cloned = copy.deepcopy(obj)
    mutator(cloned)
    return cloned


def _storage_word(byte_value: int = 0) -> str:
    return "0x" + format(byte_value, "064x")


def _probe_negative_fixture(path: Path) -> str:
    """Decode+validate a negative fixture; return the raised CorpusError.code."""
    data = path.read_bytes()
    name = path.name
    try:
        if name.startswith("obs-"):
            # Observation negatives are under obs byte cap unless named oversize.
            value = decode_json(data, max_bytes=MAX_OBS_BYTES)
            encoded = dumps_canonical(value)
            if encoded != data:
                decode_canonical(data, max_bytes=MAX_OBS_BYTES)
            else:
                validate_observation(value)
        elif len(data) > MAX_CASE_BYTES:
            decode_canonical(data, max_bytes=MAX_CASE_BYTES)
        else:
            value = decode_json(data, max_bytes=MAX_CASE_BYTES)
            encoded = dumps_canonical(value)
            if encoded != data:
                decode_canonical(data, max_bytes=MAX_CASE_BYTES)
            else:
                validate_case(value)
    except CorpusError as exc:
        return exc.code
    raise AssertionError(f"negative fixture unexpectedly accepted: {path}")


def _actors(n: int) -> list[dict[str, object]]:
    # ids a00.. sorted ascending for n<=100
    return [{"id": f"a{index:02d}", "role": "eoa"} for index in range(n)]


def _steps(n: int, actor: str = "a00") -> list[dict[str, object]]:
    return [
        _step(index, actor=actor, entry="inc") for index in range(n)
    ]


def _logs(n: int) -> list[dict[str, object]]:
    # empty topics/data; address null allowed on case expectedLogs
    return [{"address": None, "topics": [], "data": None} for _ in range(n)]


def _topics(n: int) -> list[str]:
    return ["0x" + format(index, "064x") for index in range(n)]


def _diag_patterns(n: int, *, item: str = "p") -> list[str]:
    # ascending unique short patterns
    return [f"{item}{index:02d}" for index in range(n)]


def _utf8_of_len(n: int, unit: str = "x") -> str:
    """Build a string whose UTF-8 encoding is exactly n bytes using `unit`."""
    unit_bytes = unit.encode("utf-8")
    if n % len(unit_bytes) != 0:
        raise AssertionError(
            f"utf8 pad unit {unit!r} ({len(unit_bytes)} bytes) does not divide {n}"
        )
    return unit * (n // len(unit_bytes))


def _padded_case_bytes(target_len: int) -> bytes:
    """Return canonical case bytes with len == target_len via pad field."""
    base = make_primitive_case()
    base["initialLogicalState"] = {"pad": ""}
    empty = dumps_canonical(base)
    # {"pad":""} contributes fixed overhead; grow the pad string.
    # dumps: ... "pad":"<PAD>" ...
    overhead = len(empty)
    if target_len < overhead:
        raise AssertionError(f"target_len {target_len} < overhead {overhead}")
    pad_len = target_len - overhead
    # each pad char 'x' is one UTF-8 byte; json string has no extra escape
    base["initialLogicalState"] = {"pad": "x" * pad_len}
    raw = dumps_canonical(base)
    if len(raw) != target_len:
        # json may not need escapes for 'x'; adjust if mismatch (should not)
        delta = target_len - len(raw)
        if delta == 0:
            return raw
        base["initialLogicalState"] = {"pad": "x" * (pad_len + delta)}
        raw = dumps_canonical(base)
    if len(raw) != target_len:
        raise AssertionError(
            f"failed to build case of length {target_len}, got {len(raw)}"
        )
    return raw


def _padded_obs_bytes(target_len: int) -> bytes:
    base = make_reference_observation()
    base["shared"] = {
        "status": "success",
        "returnValue": None,
        "logicalState": {"pad": ""},
        "effects": [],
        "rollbackEqual": True,
    }
    empty = dumps_canonical(base)
    overhead = len(empty)
    if target_len < overhead:
        raise AssertionError(f"target_len {target_len} < overhead {overhead}")
    pad_len = target_len - overhead
    base["shared"] = {
        "status": "success",
        "returnValue": None,
        "logicalState": {"pad": "x" * pad_len},
        "effects": [],
        "rollbackEqual": True,
    }
    raw = dumps_canonical(base)
    if len(raw) != target_len:
        delta = target_len - len(raw)
        base["shared"] = {
            "status": "success",
            "returnValue": None,
            "logicalState": {"pad": "x" * (pad_len + delta)},
            "effects": [],
            "rollbackEqual": True,
        }
        raw = dumps_canonical(base)
    if len(raw) != target_len:
        raise AssertionError(
            f"failed to build obs of length {target_len}, got {len(raw)}"
        )
    return raw


def _run_resource_boundary_tests() -> None:
    # --- actors 8 accept / 9 reject ---
    case8 = make_primitive_case()
    case8["actors"] = _actors(8)
    case8["steps"] = _steps(1, actor="a00")
    validate_case(case8)
    case9 = make_primitive_case()
    case9["actors"] = _actors(9)
    case9["steps"] = _steps(1, actor="a00")
    _expect_error(
        "actors-9",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(case9),
    )

    # --- steps 32 accept / 33 reject ---
    case32 = make_primitive_case()
    case32["actors"] = [{"id": "a00", "role": "eoa"}]
    case32["steps"] = _steps(32, actor="a00")
    validate_case(case32)
    case33 = make_primitive_case()
    case33["actors"] = [{"id": "a00", "role": "eoa"}]
    case33["steps"] = _steps(33, actor="a00")
    _expect_error(
        "steps-33",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(case33),
    )

    # --- expectedLogs 32 accept / 33 reject ---
    case_logs32 = make_primitive_case()
    step = dict(case_logs32["steps"][0])  # type: ignore[index]
    step["expectedLogs"] = _logs(32)
    case_logs32["steps"] = [step]
    validate_case(case_logs32)
    case_logs33 = make_primitive_case()
    step33 = dict(case_logs33["steps"][0])  # type: ignore[index]
    step33["expectedLogs"] = _logs(33)
    case_logs33["steps"] = [step33]
    _expect_error(
        "logs-33",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(case_logs33),
    )

    # --- topics 4 accept / 5 reject (case expectedLogs) ---
    case_t4 = make_primitive_case()
    st4 = dict(case_t4["steps"][0])  # type: ignore[index]
    st4["expectedLogs"] = [{"address": None, "topics": _topics(4), "data": None}]
    case_t4["steps"] = [st4]
    validate_case(case_t4)
    case_t5 = make_primitive_case()
    st5 = dict(case_t5["steps"][0])  # type: ignore[index]
    st5["expectedLogs"] = [{"address": None, "topics": _topics(5), "data": None}]
    case_t5["steps"] = [st5]
    _expect_error(
        "topics-5",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(case_t5),
    )

    # --- diagnosticPatterns 8 accept / 9 reject ---
    blocked8 = make_blocked_case()
    body8 = dict(blocked8["blocked"])  # type: ignore[arg-type]
    body8["diagnosticPatterns"] = _diag_patterns(8)
    blocked8["blocked"] = body8
    validate_case(blocked8)
    blocked9 = make_blocked_case()
    body9 = dict(blocked9["blocked"])  # type: ignore[arg-type]
    body9["diagnosticPatterns"] = _diag_patterns(9)
    blocked9["blocked"] = body9
    _expect_error(
        "diag-patterns-9",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(blocked9),
    )

    # --- reason UTF-8 byte cap 128 accept / 129 reject (ASCII) ---
    blocked_r = make_blocked_case()
    body_r = dict(blocked_r["blocked"])  # type: ignore[arg-type]
    body_r["reason"] = _utf8_of_len(MAX_REASON_BYTES, "r")
    blocked_r["blocked"] = body_r
    validate_case(blocked_r)
    body_r2 = dict(body_r)
    body_r2["reason"] = _utf8_of_len(MAX_REASON_BYTES + 1, "r")
    blocked_r["blocked"] = body_r2
    _expect_error(
        "reason-129",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(blocked_r),
    )

    # --- reason multi-byte UTF-8 (U+00E9 = 2 bytes) 128 accept / 130 reject ---
    # 64 * 2-byte chars = 128; 65 * 2 = 130 > 128
    blocked_mb = make_blocked_case()
    body_mb = dict(blocked_mb["blocked"])  # type: ignore[arg-type]
    body_mb["reason"] = _utf8_of_len(MAX_REASON_BYTES, "é")
    assert len(body_mb["reason"].encode("utf-8")) == MAX_REASON_BYTES
    blocked_mb["blocked"] = body_mb
    validate_case(blocked_mb)
    body_mb2 = dict(body_mb)
    body_mb2["reason"] = "é" * ((MAX_REASON_BYTES // 2) + 1)
    assert len(body_mb2["reason"].encode("utf-8")) == MAX_REASON_BYTES + 2
    blocked_mb["blocked"] = body_mb2
    _expect_error(
        "reason-multibyte-over",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(blocked_mb),
    )

    # --- diagnostic pattern item 128 accept / 129 reject (multi-byte) ---
    blocked_p = make_blocked_case()
    body_p = dict(blocked_p["blocked"])  # type: ignore[arg-type]
    body_p["diagnosticPatterns"] = [_utf8_of_len(MAX_DIAG_PATTERN_BYTES, "é")]
    blocked_p["blocked"] = body_p
    validate_case(blocked_p)
    body_p2 = dict(body_p)
    body_p2["diagnosticPatterns"] = ["é" * ((MAX_DIAG_PATTERN_BYTES // 2) + 1)]
    blocked_p["blocked"] = body_p2
    _expect_error(
        "diag-pattern-multibyte-over",
        "PF-CORPUS-LIMIT",
        lambda: validate_case(blocked_p),
    )

    # --- case raw byte cap: exact MAX accept, MAX+1 reject ---
    exact_case = _padded_case_bytes(MAX_CASE_BYTES)
    assert len(exact_case) == MAX_CASE_BYTES
    validate_case(decode_canonical(exact_case, max_bytes=MAX_CASE_BYTES))
    over_case = _padded_case_bytes(MAX_CASE_BYTES + 1)
    assert len(over_case) == MAX_CASE_BYTES + 1
    _expect_error(
        "case-bytes-max-plus-one",
        "PF-CORPUS-LIMIT",
        lambda: decode_canonical(over_case, max_bytes=MAX_CASE_BYTES),
    )

    # --- observation raw byte cap: exact MAX accept, MAX+1 reject ---
    # 256 KiB is fine as a one-shot in-memory self-test.
    exact_obs = _padded_obs_bytes(MAX_OBS_BYTES)
    assert len(exact_obs) == MAX_OBS_BYTES
    validate_observation(decode_canonical(exact_obs, max_bytes=MAX_OBS_BYTES))
    over_obs = _padded_obs_bytes(MAX_OBS_BYTES + 1)
    assert len(over_obs) == MAX_OBS_BYTES + 1
    _expect_error(
        "obs-bytes-max-plus-one",
        "PF-CORPUS-LIMIT",
        lambda: decode_canonical(over_obs, max_bytes=MAX_OBS_BYTES),
    )

    # --- obs logs 32 accept / 33 reject ---
    obs_l32 = make_pf_anvil_observation()
    evm32 = dict(obs_l32["evm"])  # type: ignore[arg-type]
    evm32["logs"] = [
        {
            "address": "0x" + "11" * 20,
            "topics": [],
            "data": "0x",
        }
        for _ in range(32)
    ]
    obs_l32["evm"] = evm32
    validate_observation(obs_l32)
    obs_l33 = make_pf_anvil_observation()
    evm33 = dict(obs_l33["evm"])  # type: ignore[arg-type]
    evm33["logs"] = [
        {
            "address": "0x" + "11" * 20,
            "topics": [],
            "data": "0x",
        }
        for _ in range(33)
    ]
    obs_l33["evm"] = evm33
    _expect_error(
        "obs-logs-33",
        "PF-CORPUS-LIMIT",
        lambda: validate_observation(obs_l33),
    )

    # --- obs topics 4 accept / 5 reject ---
    obs_t4 = make_pf_anvil_observation()
    evm_t4 = dict(obs_t4["evm"])  # type: ignore[arg-type]
    evm_t4["logs"] = [
        {
            "address": "0x" + "11" * 20,
            "topics": _topics(4),
            "data": "0x",
        }
    ]
    obs_t4["evm"] = evm_t4
    validate_observation(obs_t4)
    obs_t5 = make_pf_anvil_observation()
    evm_t5 = dict(obs_t5["evm"])  # type: ignore[arg-type]
    evm_t5["logs"] = [
        {
            "address": "0x" + "11" * 20,
            "topics": _topics(5),
            "data": "0x",
        }
    ]
    obs_t5["evm"] = evm_t5
    _expect_error(
        "obs-topics-5",
        "PF-CORPUS-LIMIT",
        lambda: validate_observation(obs_t5),
    )


def _run_storage_word_tests() -> None:
    # accept two slots sorted by wire string
    obs = make_pf_anvil_observation()
    evm = dict(obs["evm"])  # type: ignore[arg-type]
    evm["storageSlots"] = [
        {"slot": _storage_word(1), "value": _storage_word(10)},
        {"slot": _storage_word(2), "value": _storage_word(20)},
    ]
    obs["evm"] = evm
    validate_observation(obs)

    # wrong width (2 bytes) rejected
    bad = make_pf_anvil_observation()
    evm_bad = dict(bad["evm"])  # type: ignore[arg-type]
    evm_bad["storageSlots"] = [{"slot": "0x01", "value": _storage_word(0)}]
    bad["evm"] = evm_bad
    _expect_error(
        "storage-slot-short",
        "PF-CORPUS-SCHEMA",
        lambda: validate_observation(bad),
    )

    # uppercase rejected
    bad_u = make_pf_anvil_observation()
    evm_u = dict(bad_u["evm"])  # type: ignore[arg-type]
    evm_u["storageSlots"] = [
        {"slot": "0x" + "0A" + "00" * 31, "value": _storage_word(0)}
    ]
    bad_u["evm"] = evm_u
    _expect_error(
        "storage-slot-upper",
        "PF-CORPUS-SCHEMA",
        lambda: validate_observation(bad_u),
    )

    # unsorted rejected
    unsorted = make_pf_anvil_observation()
    evm_us = dict(unsorted["evm"])  # type: ignore[arg-type]
    evm_us["storageSlots"] = [
        {"slot": _storage_word(2), "value": _storage_word(0)},
        {"slot": _storage_word(1), "value": _storage_word(0)},
    ]
    unsorted["evm"] = evm_us
    _expect_error(
        "storage-slots-unsorted",
        "PF-CORPUS-INVARIANT",
        lambda: validate_observation(unsorted),
    )


def _run_forbidden_early_order_test() -> None:
    # ASCII-sorted permutation is NOT the fixed contract order.
    blocked = make_blocked_case()
    body = dict(blocked["blocked"])  # type: ignore[arg-type]
    body["forbiddenEarlyFailure"] = sorted(FORBIDDEN_EARLY_FAILURE)
    assert body["forbiddenEarlyFailure"] != list(FORBIDDEN_EARLY_FAILURE)
    blocked["blocked"] = body
    _expect_error(
        "forbidden-early-ascii-sort",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(blocked),
    )


def run_self_tests() -> None:
    # Positive class roundtrips (schema shapes only; not product OZ credit).
    for builder in (
        make_primitive_case,
        make_adapter_case,
        make_oz_behavior_case,
        make_abi_case,
        make_blocked_case,
        make_oos_case,
    ):
        _roundtrip_case(builder())
    _roundtrip_obs(make_reference_observation())
    _roundtrip_obs(make_pf_anvil_observation())

    # Disk fixtures when present.
    positive_dir = FIXTURE_ROOT / "positive"
    negative_dir = FIXTURE_ROOT / "negative"
    if positive_dir.is_dir():
        for path in sorted(positive_dir.glob("*.json")):
            data = path.read_bytes()
            value = decode_canonical(
                data,
                max_bytes=max(MAX_CASE_BYTES, MAX_OBS_BYTES),
            )
            assert isinstance(value, dict)
            schema = value.get("schema")
            if schema == SCHEMA_CASE:
                validate_case(value)
                assert len(data) <= MAX_CASE_BYTES
            elif schema == SCHEMA_OBS:
                validate_observation(value)
                assert len(data) <= MAX_OBS_BYTES
            else:
                raise AssertionError(f"unknown fixture schema in {path}")

    if negative_dir.is_dir():
        on_disk = {path.name for path in negative_dir.glob("*.json")}
        expected_names = set(NEGATIVE_FIXTURE_CODES)
        missing = sorted(expected_names - on_disk)
        extra = sorted(on_disk - expected_names)
        if missing:
            raise AssertionError(
                f"missing negative fixtures for code map: {missing}"
            )
        if extra:
            raise AssertionError(
                f"negative fixtures without exact code map entries: {extra}"
            )
        for name, expected_code in sorted(NEGATIVE_FIXTURE_CODES.items()):
            path = negative_dir / name
            actual = _probe_negative_fixture(path)
            if actual != expected_code:
                raise AssertionError(
                    f"{name}: expected {expected_code}, got {actual}"
                )

    # Programmatic adversarial probes (duplicate of disk where useful).
    _expect_error(
        "unknown-field",
        "PF-CORPUS-SCHEMA",
        lambda: validate_case(
            _mutate(make_primitive_case(), lambda c: c.__setitem__("extra", 1))
        ),
    )

    def dup_actors(c: dict[str, object]) -> None:
        c["actors"] = [
            {"id": "deployer", "role": "eoa"},
            {"id": "deployer", "role": "contract"},
        ]

    _expect_error(
        "duplicate-actor",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_primitive_case(), dup_actors)),
    )

    huge = make_primitive_case()
    huge["initialLogicalState"] = {"pad": "x" * (MAX_CASE_BYTES)}
    raw_huge = dumps_canonical(huge)
    assert len(raw_huge) > MAX_CASE_BYTES
    _expect_error(
        "oversize-case",
        "PF-CORPUS-LIMIT",
        lambda: decode_canonical(raw_huge, max_bytes=MAX_CASE_BYTES),
    )

    _expect_error(
        "invalid-class",
        "PF-CORPUS-SCHEMA",
        lambda: validate_case(
            _mutate(make_primitive_case(), lambda c: c.__setitem__("class", "unit"))
        ),
    )

    def ref_with_evm(o: dict[str, object]) -> None:
        o["evm"] = make_pf_anvil_observation()["evm"]

    _expect_error(
        "reference-with-evm",
        "PF-CORPUS-INVARIANT",
        lambda: validate_observation(
            _mutate(make_reference_observation(), ref_with_evm)
        ),
    )

    def skip_as_pass(c: dict[str, object]) -> None:
        policy = dict(c["skipPolicy"])  # type: ignore[arg-type]
        policy["requiredToolFailure"] = "skip"
        c["skipPolicy"] = policy

    _expect_error(
        "skip-as-pass-policy",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_primitive_case(), skip_as_pass)),
    )

    def pass_with_skip(o: dict[str, object]) -> None:
        o["skipReason"] = "optional tool missing"

    _expect_error(
        "skip-as-pass-verdict",
        "PF-CORPUS-INVARIANT",
        lambda: validate_observation(
            _mutate(make_reference_observation(), pass_with_skip)
        ),
    )

    def traversal(c: dict[str, object]) -> None:
        pins = dict(c["pins"])  # type: ignore[arg-type]
        pins["sourcePath"] = "../secret.lean"
        c["pins"] = pins

    _expect_error(
        "path-traversal",
        "PF-CORPUS-PATH",
        lambda: validate_case(_mutate(make_primitive_case(), traversal)),
    )

    def adapter_credit(c: dict[str, object]) -> None:
        c["claims"] = _claims(family=True)

    _expect_error(
        "adapter-family-credit",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_adapter_case(), adapter_credit)),
    )

    def drop_projection(c: dict[str, object]) -> None:
        c["sharedProjection"] = None

    _expect_error(
        "oz-missing-projection",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_oz_behavior_case(), drop_projection)),
    )

    def abi_no_same(c: dict[str, object]) -> None:
        oracle = dict(c["oracle"])  # type: ignore[arg-type]
        oracle["sameCallBytes"] = False
        c["oracle"] = oracle

    _expect_error(
        "abi-same-call-bytes",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_abi_case(), abi_no_same)),
    )

    def drop_blocked(c: dict[str, object]) -> None:
        c["blocked"] = None

    _expect_error(
        "blocked-missing",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_blocked_case(), drop_blocked)),
    )

    def oos_draft(c: dict[str, object]) -> None:
        body = dict(c["oos"])  # type: ignore[arg-type]
        body["decisionStatus"] = "draft"
        c["oos"] = body

    _expect_error(
        "oos-not-accepted",
        "PF-CORPUS-INVARIANT",
        lambda: validate_case(_mutate(make_oos_case(), oos_draft)),
    )

    raw = dumps_canonical(make_primitive_case())
    _expect_error(
        "non-canonical",
        "PF-CORPUS-CANONICAL",
        lambda: decode_canonical(raw + b"\n", max_bytes=MAX_CASE_BYTES),
    )

    _expect_error(
        "duplicate-key",
        "PF-CORPUS-DUPLICATE-KEY",
        lambda: decode_json(b'{"a":1,"a":2}', max_bytes=MAX_CASE_BYTES),
    )

    _run_resource_boundary_tests()
    _run_storage_word_tests()
    _run_forbidden_early_order_test()

    print("evm-corpus-v1: self-test ok")


def _cmd_validate_case(path: Path) -> None:
    load_and_validate_case(path)
    print(f"corpus-schema-validated case {path.as_posix()} claims-not-verified")


def _cmd_validate_observation(path: Path) -> None:
    load_and_validate_observation(path)
    print(
        f"corpus-schema-validated observation {path.as_posix()} claims-not-verified"
    )


def main(argv: list[str] | None = None) -> None:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args == ["self-test"]:
        run_self_tests()
        return
    if len(args) == 2 and args[0] == "validate-case":
        _cmd_validate_case(Path(args[1]))
        return
    if len(args) == 2 and args[0] == "validate-observation":
        _cmd_validate_observation(Path(args[1]))
        return
    print(
        "usage: evm_corpus_v1.py self-test"
        " | validate-case PATH"
        " | validate-observation PATH",
        file=sys.stderr,
    )
    raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except CorpusError as error:
        print(error.render(), file=sys.stderr)
        raise SystemExit(1)
