#!/usr/bin/env python3
"""Closed validator for proof-forge.evm-corpus-case.v1 / observation / manifest.v1.

Pure structural schema foundation (EVMOZ-002) plus EVMOZ-006 closed inventory
manifest authority. Not an evidence envelope, not a product import, not an
OZ/family claim oracle.

Requires isolated no-site Python: /usr/bin/python3 -I -S
"""

from __future__ import annotations

import hashlib
import json
import os
import posixpath
import re
import stat as stat_mod
import sys
import unicodedata
from pathlib import Path
from typing import Callable, NoReturn


SCHEMA_CASE = "proof-forge.evm-corpus-case.v1"
SCHEMA_OBS = "proof-forge.evm-observation.v1"
SCHEMA_MANIFEST = "proof-forge.evm-corpus-manifest.v1"

MAX_MANIFEST_BYTES = 256 * 1024
MAX_MANIFEST_FILES = 256
MANIFEST_ROLES = frozenset({"case", "source", "schema-fixture", "runner"})
MANIFEST_REL_PATH = "testdata/evm-corpus/v1/manifest.json"
CORPUS_V1_REL = "testdata/evm-corpus/v1"
CASES_REL = "testdata/evm-corpus/v1/cases"
# Sole full-runtime harness inventory (validator + reference + runtime call chain
# + two Lean corpus suites). Exact set; role=runner in the corpus manifest.
REQUIRED_RUNNER_PATHS = (
    "scripts/evm_corpus_v1.py",
    "scripts/evm_corpus_reference.sh",
    "scripts/evm_corpus_runtime.sh",
    "scripts/evm_corpus_obs_write.py",
    "scripts/evm_anvil_differential.sh",
    "scripts/smoke_evm.sh",
    "scripts/evm_token_anvil_smoke.sh",
    "scripts/evm_tipjar_anvil_smoke.sh",
    "scripts/evm_tokenjar_anvil_smoke.sh",
    "Tests/Materialization/EvmCorpusPrimitiveV1.lean",
    "Tests/Materialization/EvmCorpusBlockedV1.lean",
)
# Closed roots for case pins.sourcePath (.lean only).
ALLOWED_SOURCE_ROOTS = (
    "Examples/",
    "testdata/valid/",
    "testdata/evm-corpus/v1/programs/",
)
EXPECTED_REFERENCE_OBS_COUNT = 23

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
# Case-level exact closure (engineering corpus; not formal C-3)
# ---------------------------------------------------------------------------


def _log_matches_expectation(actual: dict[str, object], exp: dict[str, object]) -> bool:
    exp_addr = exp.get("address")
    if exp_addr is not None:
        if (actual.get("address") or "").lower() != str(exp_addr).lower():
            return False
    exp_topics = exp.get("topics") or []
    act_topics = actual.get("topics") or []
    if len(exp_topics) != len(act_topics):
        return False
    for a, b in zip(exp_topics, act_topics):
        if str(a).lower() != str(b).lower():
            return False
    exp_data = exp.get("data")
    if exp_data is not None:
        act_data = actual.get("data") or "0x"
        if str(act_data).lower() != str(exp_data).lower():
            return False
    return True


def close_case(
    case: dict[str, object],
    observations: list[dict[str, object]],
) -> dict[str, object]:
    """Exact case-level observation closure.

    Rejects duplicate/extra/missing (leg, stepIndex), required-leg non-pass,
    primitive shared inequality, status/log mismatches. Success message only
    after full closure.
    """
    case = validate_case(case)
    case_id = case["id"]  # type: ignore[index]
    case_class = case["class"]  # type: ignore[index]
    oracle = case["oracle"]  # type: ignore[index]
    legs: list[str] = list(oracle["legs"])  # type: ignore[index]
    steps: list[dict[str, object]] = list(case["steps"])  # type: ignore[index]
    skip_policy = case["skipPolicy"]  # type: ignore[index]
    optional_legs = set(skip_policy["optionalLegs"])  # type: ignore[index]
    required_legs = [leg for leg in legs if leg not in optional_legs]

    expected_keys: set[tuple[str, int]] = set()
    for leg in legs:
        for step in steps:
            expected_keys.add((leg, int(step["index"])))  # type: ignore[arg-type]

    index: dict[tuple[str, int], dict[str, object]] = {}
    for obs in observations:
        o = validate_observation(obs)
        if o["caseId"] != case_id:
            fail(
                "PF-CORPUS-INVARIANT",
                f"observation caseId {o['caseId']!r} != case id {case_id!r}",
            )
        key = (str(o["leg"]), int(o["stepIndex"]))  # type: ignore[arg-type]
        if key in index:
            fail(
                "PF-CORPUS-INVARIANT",
                f"duplicate observation for leg={key[0]} step={key[1]}",
            )
        if key not in expected_keys:
            fail(
                "PF-CORPUS-INVARIANT",
                f"extra observation for leg={key[0]} step={key[1]}",
            )
        index[key] = o

    missing = sorted(expected_keys - set(index))
    if missing:
        miss_s = ", ".join(f"{leg}@{step}" for leg, step in missing)
        fail("PF-CORPUS-INVARIANT", f"missing observation(s): {miss_s}")

    # Required legs: every observation must be verdict=pass (skip/tool-blocked/proposal ≠ pass).
    for leg in required_legs:
        for step in steps:
            idx = int(step["index"])  # type: ignore[arg-type]
            o = index[(leg, idx)]
            if o["verdict"] != "pass":
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"required leg={leg} step={idx} verdict={o['verdict']!r} "
                    "(required leg cannot skip/tool-blocked/proposal/fail as pass)",
                )

    # Optional legs: ONLY whole-leg all-pass or whole-leg all-skip.
    # Mixed skip+pass, tool-blocked, proposal, fail → fail closed (never case pass).
    optional_all_skip = True
    for leg in sorted(optional_legs):
        verdicts = {
            index[(leg, int(step["index"]))]["verdict"]  # type: ignore[arg-type]
            for step in steps
        }
        if verdicts == {"pass"}:
            optional_all_skip = False
            continue
        if verdicts == {"skip"}:
            continue
        fail(
            "PF-CORPUS-INVARIANT",
            f"optional leg={leg} verdicts={sorted(str(v) for v in verdicts)} "
            "must be all-pass or all-skip "
            "(tool-blocked/proposal/fail/mixed are not pass)",
        )
    if not optional_legs:
        optional_all_skip = False

    # Per-step status + expectedLogs (against pf-anvil when present and pass).
    for step in steps:
        idx = int(step["index"])  # type: ignore[arg-type]
        expected_status = step["expectedSharedStatus"]
        for leg in legs:
            o = index[(leg, idx)]
            if o["verdict"] != "pass":
                continue
            shared = o["shared"]  # type: ignore[index]
            if shared["status"] != expected_status:
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"leg={leg} step={idx} shared.status {shared['status']!r} "
                    f"!= case expected {expected_status!r}",
                )
        # expectedLogs vs pf-anvil EVM logs when that leg is pass.
        if ("pf-anvil", idx) in index and index[("pf-anvil", idx)]["verdict"] == "pass":
            o = index[("pf-anvil", idx)]
            evm = o["evm"]  # type: ignore[index]
            assert isinstance(evm, dict)
            actual_logs = list(evm.get("logs") or [])
            expected_logs = list(step.get("expectedLogs") or [])
            if len(actual_logs) != len(expected_logs):
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"pf-anvil step={idx} log count {len(actual_logs)} "
                    f"!= expectedLogs {len(expected_logs)}",
                )
            for li, (act, exp) in enumerate(zip(actual_logs, expected_logs)):
                if not isinstance(act, dict) or not isinstance(exp, dict):
                    fail(
                        "PF-CORPUS-INVARIANT",
                        f"pf-anvil step={idx} log[{li}] type mismatch",
                    )
                if not _log_matches_expectation(act, exp):
                    fail(
                        "PF-CORPUS-INVARIANT",
                        f"pf-anvil step={idx} log[{li}] does not match expectedLogs",
                    )

    # Primitive: shared exact equality across required legs per step.
    if case_class == "primitive":
        for step in steps:
            idx = int(step["index"])  # type: ignore[arg-type]
            shared_vals = []
            for leg in required_legs:
                o = index[(leg, idx)]
                shared_vals.append(o["shared"])
            if len(shared_vals) >= 2:
                base = shared_vals[0]
                for other in shared_vals[1:]:
                    if other != base:
                        fail(
                            "PF-CORPUS-INVARIANT",
                            f"primitive step={idx} shared mismatch across required legs",
                        )

    # Whole-case result:
    # - required legs all pass (enforced above)
    # - optional all-pass → pass; optional all-skip with no required → skip
    # - optional all-skip with required present → pass (required satisfied)
    if optional_legs and optional_all_skip and not required_legs:
        return {
            "caseId": case_id,
            "class": case_class,
            "result": "skip",
            "reason": "optional-leg-skip",
        }

    return {
        "caseId": case_id,
        "class": case_class,
        "result": "pass",
    }


def load_observations_dir(obs_dir: Path, case_id: str) -> list[dict[str, object]]:
    """Load canonical observation files for a case from a directory tree.

    Skips intermediate `*.raw.json` files written by the Lean Reference runner.
    """
    root = obs_dir / case_id
    if not root.is_dir():
        candidates = sorted(obs_dir.glob(f"*{case_id}*.json"))
        paths = candidates
    else:
        paths = sorted(root.rglob("*.json"))
    out: list[dict[str, object]] = []
    for path in paths:
        if path.name.endswith(".raw.json") or ".raw." in path.name:
            continue
        out.append(load_and_validate_observation(path))
    return out


# Tool lock files exceed case byte caps; still use closed duplicate-rejecting decoder.
MAX_TOOL_LOCK_BYTES = 8 * 1024 * 1024

# Darwin ToolLockV4Digest KAT (domain-separated PF-JCS of validated lock).
DARWIN_TOOL_LOCK_V4_DIGEST_KAT = (
    "26c269f80aa300902f2ab61e2ca65e4d38e88db89ccdf9a38aa80144e8db635b"
)
# Raw retained-file SHA-256 of toolchains.lock.json (distinct type).
DARWIN_TOOL_LOCK_RAW_SHA256_KAT = (
    "80e5d3aaf792f2f7fb80cde4d95d0df9a6f89e4f9c37fd178d94456688f12255"
)

# Exact EVMOZ-004 full-runtime pin surface for runnable anvil-matrix cases.
RUNNABLE_PIN_EXPECT = {
    "target": "evm",
    "profile": "evm-yul-solc-0.8.34-cancun-v1",
    "hardfork": "cancun",
    "toolLockDigest": DARWIN_TOOL_LOCK_V4_DIGEST_KAT,
    "solcVersion": "0.8.34",
    "anvilVersion": "0.3.0",
    "runner": "anvil-matrix",
}
EXPECTED_RUNNABLE_IDS = (
    "pf.adapter.token.conservation.v1",
    "pf.primitive.accumulator.overflow-hold.v1",
    "pf.primitive.arithops.bitnot-scale.v1",
    "pf.primitive.counter.overflow-hold.v1",
    "pf.primitive.eventflow.emit-cap.v1",
)
PRIMITIVE_REQUIRED_TOOLS = (
    "anvil",
    "cast",
    "lake",
    "lean",
    "proof-forge-next",
    "solc",
)


def darwin_tool_lock_v4_digest(lock_path: Path) -> str:
    """Recompute Darwin ToolLockV4Digest from lock file bytes (PF-JCS re-encode).

    Uses the closed duplicate-rejecting decoder (not plain json.loads).
    """
    import hashlib

    raw = lock_path.read_bytes()
    # Decode with object_pairs_hook that rejects duplicate keys.
    value = decode_json(raw, max_bytes=MAX_TOOL_LOCK_BYTES)
    canon = canonical_bytes(value)
    digest = hashlib.sha256(b"proof-forge.toolchains.v4\x00" + canon).hexdigest()
    return digest


def require_safe_obs_root(obs_root: Path, repo_root: Path) -> Path:
    """OBS root must be a proper subdirectory of repo_root/build/.

    Zero external side effects before validation completes, except:
    - may create a *real* directory ``repo/build`` when it does not exist
    - never creates parents of the candidate obs path
    - if ``build`` exists as a symlink or non-directory → reject immediately

    Uses lexical absolute paths for membership, rejects any existing symlink
    component on the path from build/ to obs (even if the target stays inside
    build/), and rechecks final resolve (strict=False) stays under build.
    """
    import os

    if not repo_root.exists() or not repo_root.is_dir():
        fail("PF-CORPUS-PATH", f"repo root is not a directory: {repo_root}")
    repo = repo_root.resolve()
    build = repo / "build"

    if build.is_symlink():
        fail("PF-CORPUS-PATH", "repo build/ must not be a symlink")
    if build.exists() and not build.is_dir():
        fail("PF-CORPUS-PATH", "repo build/ exists and is not a directory")
    if not build.exists():
        # Only create the real build/ directory itself (not obs parents).
        build.mkdir(mode=0o755)

    build_abs = Path(os.path.abspath(str(build)))
    build_real = build.resolve()

    obs_in = Path(os.path.expanduser(str(obs_root)))
    if not obs_in.is_absolute():
        obs_in = repo / obs_in
    obs_abs = Path(os.path.abspath(str(obs_in)))

    if obs_abs == repo or obs_abs == build_abs:
        fail(
            "PF-CORPUS-PATH",
            f"obs root must be a proper subdirectory of build/ (got {obs_abs})",
        )
    try:
        rel = obs_abs.relative_to(build_abs)
    except ValueError:
        fail(
            "PF-CORPUS-PATH",
            f"obs root {obs_abs} must be under {build_abs}",
        )
    if not rel.parts or any(part in {".", ".."} for part in rel.parts):
        fail("PF-CORPUS-PATH", f"obs root relative path illegal: {rel}")

    # Reject any existing symlink component on build → obs (including inside build).
    cursor = build_abs
    for part in rel.parts:
        cursor = cursor / part
        if cursor.is_symlink():
            fail(
                "PF-CORPUS-PATH",
                f"symlink component rejected on obs path: {cursor}",
            )

    # Final resolve check (strict=False semantics): nonexistent leaf OK.
    if obs_abs.exists():
        obs_real = obs_abs.resolve()
    else:
        parent = obs_abs.parent
        if parent.exists():
            if parent.is_symlink():
                fail(
                    "PF-CORPUS-PATH",
                    f"symlink parent rejected on obs path: {parent}",
                )
            obs_real = parent.resolve() / obs_abs.name
        else:
            # Parent missing: membership already lexical under build; do not create.
            obs_real = obs_abs
    try:
        obs_real.relative_to(build_real)
    except ValueError:
        fail(
            "PF-CORPUS-PATH",
            f"resolved obs root {obs_real} escapes {build_real}",
        )
    return obs_abs


def list_runnable_cases(cases_dir: Path) -> list[dict[str, object]]:
    """Return cases with class in {primitive,adapter} and runner=anvil-matrix."""
    out: list[dict[str, object]] = []
    for path in sorted(cases_dir.glob("*.json")):
        case = load_and_validate_case(path)
        if case["class"] in {"primitive", "adapter"} and case["pins"]["runner"] == "anvil-matrix":  # type: ignore[index]
            out.append(case)
    return out


def assert_runnable_set(cases: list[dict[str, object]]) -> None:
    ids = sorted(str(c["id"]) for c in cases)
    expected = sorted(EXPECTED_RUNNABLE_IDS)
    if ids != expected:
        fail(
            "PF-CORPUS-INVARIANT",
            f"runnable case set {ids} != expected {expected}",
        )


def assert_case_pins(case: dict[str, object]) -> None:
    """Exact join of full-runtime pin surface for a runnable case."""
    case = validate_case(case)
    pins = case["pins"]  # type: ignore[index]
    for key, expected in RUNNABLE_PIN_EXPECT.items():
        actual = pins[key]
        if actual != expected:
            fail(
                "PF-CORPUS-INVARIANT",
                f"case {case['id']} pins.{key}={actual!r} != {expected!r}",
            )
    # Primitive requiredTools exact matrix.
    if case["class"] == "primitive":
        tools = list(case["skipPolicy"]["requiredTools"])  # type: ignore[index]
        if tools != list(PRIMITIVE_REQUIRED_TOOLS):
            fail(
                "PF-CORPUS-INVARIANT",
                f"case {case['id']} requiredTools={tools} "
                f"!= {list(PRIMITIVE_REQUIRED_TOOLS)}",
            )
    if case["class"] == "adapter":
        tools = list(case["skipPolicy"]["requiredTools"])  # type: ignore[index]
        if tools != []:
            fail(
                "PF-CORPUS-INVARIANT",
                f"adapter {case['id']} requiredTools must be [] (optional leg)",
            )


def mint_observation_from_shared(
    *,
    case_id: str,
    leg: str,
    step_index: int,
    status: str,
    return_value: object,
    logical_state: dict[str, object],
    effects: list[object],
    rollback_equal: bool,
    evm: object,
    verdict: str = "pass",
    skip_reason: object = None,
) -> bytes:
    """Build canonical observation bytes (shared authority for harness emitters)."""
    obs = {
        "schema": SCHEMA_OBS,
        "caseId": case_id,
        "leg": leg,
        "stepIndex": step_index,
        "verdict": verdict,
        "skipReason": skip_reason,
        "shared": {
            "status": status,
            "returnValue": return_value,
            "logicalState": logical_state,
            "effects": effects,
            "rollbackEqual": rollback_equal,
        },
        "evm": evm,
    }
    validate_observation(obs)
    return dumps_canonical(obs)


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
    _run_close_case_negative_tests()
    _run_tool_lock_and_obs_root_tests()
    _run_manifest_self_tests()

    print("evm-corpus-v1: self-test ok")


def _mk_pass_obs(
    case_id: str,
    leg: str,
    step: int,
    *,
    status: str = "success",
    shared_extra: dict[str, object] | None = None,
) -> dict[str, object]:
    shared: dict[str, object] = {
        "status": status,
        "returnValue": None,
        "logicalState": {"count": "0"},
        "effects": [],
        "rollbackEqual": True,
    }
    if shared_extra:
        shared.update(shared_extra)
    evm: object
    if leg == "reference":
        evm = None
    else:
        evm = {
            "balances": [],
            "calldata": "0x",
            "externalCalls": [],
            "logs": [],
            "returndata": "0x",
            "revertData": None,
            "storageSlots": [],
        }
    return {
        "schema": SCHEMA_OBS,
        "caseId": case_id,
        "leg": leg,
        "stepIndex": step,
        "verdict": "pass",
        "skipReason": None,
        "shared": shared,
        "evm": evm,
    }


def _run_close_case_negative_tests() -> None:
    """Minimal negatives: missing Reference, sparse steps, dup/extra, shared mismatch, required skip."""
    case = make_primitive_case()
    # Ensure single-step primitive with both legs required.
    case["skipPolicy"] = _skip(optional=[], tools=["anvil", "solc"])
    case["steps"] = [_step(0, entry="inc", status="success")]
    case_id = str(case["id"])

    # Happy path for control: two matching pass obs.
    ok_obs = [
        _mk_pass_obs(case_id, "reference", 0),
        _mk_pass_obs(case_id, "pf-anvil", 0),
    ]
    result = close_case(case, ok_obs)
    if result.get("result") != "pass":
        raise AssertionError(f"close-case happy expected pass, got {result}")

    def expect_close_fail(label: str, obs: list[dict[str, object]]) -> None:
        try:
            close_case(case, obs)
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(
                    f"{label}: expected PF-CORPUS-INVARIANT, got {err.code}"
                ) from err
            return
        raise AssertionError(f"{label}: expected close_case failure")

    # Missing Reference leg.
    expect_close_fail(
        "missing-reference",
        [_mk_pass_obs(case_id, "pf-anvil", 0)],
    )
    # Sparse step (missing step index 0 for one leg already covered; multi-step sparse).
    multi = dict(case)
    multi["steps"] = [
        _step(0, entry="inc", status="success"),
        _step(1, entry="inc", status="success"),
    ]
    sparse = [
        _mk_pass_obs(case_id, "reference", 0),
        _mk_pass_obs(case_id, "pf-anvil", 0),
        _mk_pass_obs(case_id, "reference", 1),
        # missing pf-anvil@1
    ]
    try:
        close_case(multi, sparse)
        raise AssertionError("sparse-step: expected failure")
    except CorpusError as err:
        if err.code != "PF-CORPUS-INVARIANT":
            raise AssertionError(f"sparse-step: wrong code {err.code}") from err

    # Duplicate observation.
    dup = ok_obs + [_mk_pass_obs(case_id, "reference", 0)]
    expect_close_fail("duplicate-obs", dup)

    # Extra observation (wrong step).
    extra = ok_obs + [_mk_pass_obs(case_id, "reference", 1)]
    expect_close_fail("extra-obs", extra)

    # Shared mismatch between legs.
    bad_shared = [
        _mk_pass_obs(case_id, "reference", 0, shared_extra={"logicalState": {"count": "1"}}),
        _mk_pass_obs(case_id, "pf-anvil", 0, shared_extra={"logicalState": {"count": "2"}}),
    ]
    expect_close_fail("shared-mismatch", bad_shared)

    # Required leg skip cannot pass.
    skip_obs = [
        {
            **_mk_pass_obs(case_id, "reference", 0),
            "verdict": "skip",
            "skipReason": "missing-reference-runner",
        },
        _mk_pass_obs(case_id, "pf-anvil", 0),
    ]
    expect_close_fail("required-leg-skip", skip_obs)

    # Optional leg: all tool-blocked must NOT pass.
    adapter = make_adapter_case()
    adapter["oracle"] = {
        "legs": ["pf-anvil"],
        "compare": "shared-projection",
        "sameCallBytes": False,
    }
    adapter["skipPolicy"] = _skip(optional=["pf-anvil"], tools=[])
    adapter["pins"] = _base_pins(
        ozCommit=None, sourcePath="Examples/Token.lean", runner="anvil-matrix"
    )
    # Re-validate adapter after pin/oracle mutation.
    adapter_id = str(adapter["id"])

    def _skip_like(verdict: str, reason: str) -> dict[str, object]:
        o = _mk_pass_obs(adapter_id, "pf-anvil", 0)
        o["verdict"] = verdict
        o["skipReason"] = reason
        return o

    try:
        close_case(adapter, [_skip_like("tool-blocked", "toolchain")])
        raise AssertionError("optional-all-tool-blocked: expected failure")
    except CorpusError as err:
        if err.code != "PF-CORPUS-INVARIANT":
            raise AssertionError(
                f"optional-all-tool-blocked: wrong code {err.code}"
            ) from err

    try:
        close_case(adapter, [_skip_like("proposal", "design-only")])
        raise AssertionError("optional-all-proposal: expected failure")
    except CorpusError as err:
        if err.code != "PF-CORPUS-INVARIANT":
            raise AssertionError(
                f"optional-all-proposal: wrong code {err.code}"
            ) from err

    # Mixed skip + tool-blocked across steps.
    adapter["steps"] = [
        _step(0, actor="alice", entry="transfer", status="success"),
        _step(1, actor="alice", entry="transfer", status="success"),
    ]
    mixed = [
        {
            **_mk_pass_obs(adapter_id, "pf-anvil", 0),
            "verdict": "skip",
            "skipReason": "stack-too-deep",
        },
        {
            **_mk_pass_obs(adapter_id, "pf-anvil", 1),
            "verdict": "tool-blocked",
            "skipReason": "missing-anvil",
        },
    ]
    try:
        close_case(adapter, mixed)
        raise AssertionError("optional-mixed-skip-tool-blocked: expected failure")
    except CorpusError as err:
        if err.code != "PF-CORPUS-INVARIANT":
            raise AssertionError(
                f"optional-mixed: wrong code {err.code}"
            ) from err

    # All-skip optional → case skip (not pass).
    adapter["steps"] = [_step(0, actor="alice", entry="transfer", status="success")]
    skipped = close_case(
        adapter,
        [
            {
                **_mk_pass_obs(adapter_id, "pf-anvil", 0),
                "verdict": "skip",
                "skipReason": "stack-too-deep",
            }
        ],
    )
    if skipped.get("result") != "skip":
        raise AssertionError(f"optional-all-skip expected skip, got {skipped}")


def _run_tool_lock_and_obs_root_tests() -> None:
    lock = REPO_ROOT / "toolchains.lock.json"
    if lock.is_file():
        digest = darwin_tool_lock_v4_digest(lock)
        if digest != DARWIN_TOOL_LOCK_V4_DIGEST_KAT:
            raise AssertionError(
                f"ToolLockV4Digest KAT mismatch: {digest} != "
                f"{DARWIN_TOOL_LOCK_V4_DIGEST_KAT}"
            )
        import hashlib

        raw = hashlib.sha256(lock.read_bytes()).hexdigest()
        if raw != DARWIN_TOOL_LOCK_RAW_SHA256_KAT:
            raise AssertionError(
                f"raw toolchains.lock.json SHA-256 mismatch: {raw} != "
                f"{DARWIN_TOOL_LOCK_RAW_SHA256_KAT}"
            )
        if digest == raw:
            raise AssertionError("ToolLockV4Digest must not equal raw lock SHA-256")
        # Duplicate-key rejection on lock-sized input.
        try:
            decode_json(b'{"a":1,"a":2}', max_bytes=MAX_TOOL_LOCK_BYTES)
            raise AssertionError("duplicate key must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-DUPLICATE-KEY":
                raise AssertionError(f"dup-key wrong code {err.code}") from err

    # Safe obs root negatives (no deletion / no outside parent creation).
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        (repo / "build").mkdir()
        sentinel = repo / "SENTINEL"
        sentinel.write_text("keep", encoding="utf-8")
        # Good path (spaces) round-trip.
        spaced = Path("build/v2/my obs dir")
        good = require_safe_obs_root(spaced, repo)
        if "my obs dir" not in str(good):
            raise AssertionError(f"spaces path lost: {good}")
        # Outside nonexistent parent must remain nonexistent after reject.
        outside_parent = repo / "nope-parent" / "child"
        if outside_parent.parent.exists():
            raise AssertionError("precondition: outside parent must not exist")
        try:
            require_safe_obs_root(outside_parent, repo)
            raise AssertionError("expected reject for outside nonexistent parent")
        except CorpusError as err:
            if err.code != "PF-CORPUS-PATH":
                raise AssertionError(f"outside parent wrong code {err.code}") from err
        if outside_parent.parent.exists():
            raise AssertionError(
                "require_safe_obs_root must not create outside parent directories"
            )
        for bad in [
            Path("/"),
            repo,
            repo / "build",
            repo / "outside",
            Path("/tmp"),
        ]:
            try:
                require_safe_obs_root(bad, repo)
                raise AssertionError(f"expected reject for {bad}")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"obs-root {bad}: wrong code {err.code}"
                    ) from err
        # Symlink escape: build/evil -> /
        evil = repo / "build" / "evil-link"
        try:
            evil.symlink_to("/")
            try:
                require_safe_obs_root(evil, repo)
                raise AssertionError("symlink escape must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"symlink escape wrong code {err.code}"
                    ) from err
        except OSError:
            pass
        # build itself as symlink (temp fixture; never touch real repo build)
        repo2 = Path(tmp) / "repo2"
        repo2.mkdir()
        (repo2 / "real-build").mkdir()
        try:
            (repo2 / "build").symlink_to(repo2 / "real-build")
            try:
                require_safe_obs_root(Path("build/v2/x"), repo2)
                raise AssertionError("build symlink must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"build symlink wrong code {err.code}"
                    ) from err
        except OSError:
            pass
        # In-build symlink component rejected even if target stays in build.
        inner = repo / "build" / "real-sub"
        inner.mkdir()
        link = repo / "build" / "link-sub"
        try:
            link.symlink_to(inner)
            try:
                require_safe_obs_root(link / "leaf", repo)
                raise AssertionError("in-build symlink component must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"in-build symlink wrong code {err.code}"
                    ) from err
        except OSError:
            pass
        if sentinel.read_text(encoding="utf-8") != "keep":
            raise AssertionError("obs-root checks must not delete sentinel")



# ---------------------------------------------------------------------------
# Manifest authority (EVMOZ-006) — closed inventory; not formal evidence.
# ---------------------------------------------------------------------------


def validate_manifest_document(value: object) -> dict[str, object]:
    """Structural validate of decoded manifest object (no disk I/O)."""
    obj = require_keys(value, {"schema", "files"}, "manifest")
    schema = require_text(obj["schema"], "manifest.schema", ascii_only=True)
    if schema != SCHEMA_MANIFEST:
        fail("PF-CORPUS-SCHEMA", f"manifest.schema must be {SCHEMA_MANIFEST}")
    files = require_array(obj["files"], "manifest.files")
    if len(files) == 0:
        fail("PF-CORPUS-INVARIANT", "manifest.files must be nonempty")
    if len(files) > MAX_MANIFEST_FILES:
        fail(
            "PF-CORPUS-LIMIT",
            f"manifest.files exceeds {MAX_MANIFEST_FILES} entries",
        )
    out_files: list[dict[str, object]] = []
    paths: list[str] = []
    for index, item in enumerate(files):
        where = f"manifest.files[{index}]"
        entry = require_keys(item, {"path", "role", "size", "sha256"}, where)
        path = require_relative_path(entry["path"], f"{where}.path")
        role = require_text(entry["role"], f"{where}.role", ascii_only=True)
        if role not in MANIFEST_ROLES:
            fail(
                "PF-CORPUS-SCHEMA",
                f"{where}.role unknown (closed enum): {role!r}",
            )
        size = entry["size"]
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            fail("PF-CORPUS-SCHEMA", f"{where}.size must be a non-negative integer")
        if size > MAX_SAFE_INTEGER:
            fail("PF-CORPUS-NUMBER", f"{where}.size exceeds safe integer range")
        digest = require_sha256(entry["sha256"], f"{where}.sha256")
        if path == MANIFEST_REL_PATH:
            fail(
                "PF-CORPUS-INVARIANT",
                "manifest must not list itself (self-reference forbidden)",
            )
        out_files.append(
            {"path": path, "role": role, "size": size, "sha256": digest}
        )
        paths.append(path)
    if len(set(paths)) != len(paths):
        fail("PF-CORPUS-INVARIANT", "manifest.files contains duplicate path")
    if paths != sorted(paths):
        fail(
            "PF-CORPUS-INVARIANT",
            "manifest.files must be strictly path-ascending",
        )
    return {"schema": SCHEMA_MANIFEST, "files": out_files}


def _stable_read_regular(abs_path: Path, *, where: str) -> tuple[bytes, int, str]:
    """Stable observation of a regular single-link file (engineering only).

    Rejects symlink/hardlink/nonregular. Opens with O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK
    when the platform exposes those flags (never follows a race-replaced symlink
    leaf). fstat → read → fstat identity compare. Not a race-free/hermetic claim.
    """
    if abs_path.is_symlink():
        fail("PF-CORPUS-PATH", f"{where}: symlink rejected: {abs_path}")
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NONBLOCK"):
        flags |= os.O_NONBLOCK
    try:
        fd = os.open(str(abs_path), flags)
    except OSError as exc:
        fail("PF-CORPUS-PATH", f"{where}: cannot open {abs_path}: {exc}")
    try:
        try:
            st0 = os.fstat(fd)
        except OSError as exc:
            fail("PF-CORPUS-PATH", f"{where}: cannot fstat {abs_path}: {exc}")
        if not stat_mod.S_ISREG(st0.st_mode):
            fail(
                "PF-CORPUS-PATH",
                f"{where}: non-regular file rejected: {abs_path}",
            )
        if st0.st_nlink != 1:
            fail(
                "PF-CORPUS-PATH",
                f"{where}: hardlink (nlink={st0.st_nlink}) rejected: {abs_path}",
            )
        if st0.st_size > MAX_SAFE_INTEGER:
            fail(
                "PF-CORPUS-LIMIT",
                f"{where}: file size exceeds safe integer range",
            )
        chunks: list[bytes] = []
        remaining = st0.st_size
        try:
            while remaining > 0:
                piece = os.read(fd, min(remaining, 1024 * 1024))
                if not piece:
                    break
                chunks.append(piece)
                remaining -= len(piece)
            # Probe one extra byte: oversize race → fail closed.
            extra = os.read(fd, 1)
            if extra:
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"{where}: file grew during stable read: {abs_path}",
                )
        except OSError as exc:
            fail("PF-CORPUS-PATH", f"{where}: cannot read {abs_path}: {exc}")
        data = b"".join(chunks)
        try:
            st1 = os.fstat(fd)
        except OSError as exc:
            fail("PF-CORPUS-PATH", f"{where}: cannot re-fstat {abs_path}: {exc}")
        if not stat_mod.S_ISREG(st1.st_mode):
            fail(
                "PF-CORPUS-PATH",
                f"{where}: type changed during read: {abs_path}",
            )
        if (
            st0.st_ino != st1.st_ino
            or st0.st_dev != st1.st_dev
            or st0.st_mode != st1.st_mode
            or st0.st_size != st1.st_size
            or st0.st_nlink != st1.st_nlink
            or st0.st_mtime_ns != st1.st_mtime_ns
        ):
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where}: file changed during stable read: {abs_path}",
            )
        if st0.st_size != len(data):
            fail(
                "PF-CORPUS-INVARIANT",
                f"{where}: size {st0.st_size} != len(bytes) {len(data)}",
            )
        digest = hashlib.sha256(data).hexdigest()
        return data, st0.st_size, digest
    finally:
        os.close(fd)


def _reject_symlink_components(repo: Path, rel: str, *, where: str) -> Path:
    """Reject any existing symlink component on repo → rel (including leaf)."""
    parts = rel.split("/")
    if not parts or any(part in {"", ".", ".."} for part in parts):
        fail("PF-CORPUS-PATH", f"{where}: illegal relative path {rel!r}")
    cursor = repo
    for part in parts:
        cursor = cursor / part
        try:
            st = cursor.lstat()
        except FileNotFoundError:
            # Intermediate missing is fine for resolve checks; leaf missing
            # handled by callers that require existence.
            continue
        except OSError as exc:
            fail("PF-CORPUS-PATH", f"{where}: cannot lstat {cursor}: {exc}")
        if stat_mod.S_ISLNK(st.st_mode):
            fail(
                "PF-CORPUS-PATH",
                f"{where}: symlink component rejected: {cursor.relative_to(repo).as_posix()}",
            )
    return repo.joinpath(*parts)


def _walk_corpus_regular_files(repo: Path) -> set[str]:
    """Project-relative paths of every regular file under corpus v1 (no follow).

    Explicitly rejects symlink directories in dirnames (followlinks=False only
    skips descent; it does not reject the entry).
    """
    corpus = repo / CORPUS_V1_REL
    if corpus.is_symlink():
        fail("PF-CORPUS-PATH", f"corpus root must not be a symlink: {corpus}")
    if not corpus.is_dir():
        fail("PF-CORPUS-PATH", f"corpus root missing or not a directory: {corpus}")
    found: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(corpus, followlinks=False):
        base = Path(dirpath)
        if base.is_symlink():
            fail("PF-CORPUS-PATH", f"symlink directory rejected: {base}")
        # Explicitly reject symlink children that would appear as dirnames.
        for name in list(dirnames):
            child = base / name
            try:
                st = child.lstat()
            except OSError as exc:
                fail(
                    "PF-CORPUS-PATH",
                    f"cannot lstat corpus dirent {child}: {exc}",
                )
            if stat_mod.S_ISLNK(st.st_mode):
                rel = child.relative_to(repo).as_posix()
                fail(
                    "PF-CORPUS-PATH",
                    f"symlink directory under corpus rejected: {rel}",
                )
            if not stat_mod.S_ISDIR(st.st_mode):
                rel = child.relative_to(repo).as_posix()
                fail(
                    "PF-CORPUS-PATH",
                    f"non-directory dirent under corpus rejected: {rel}",
                )
        dirnames.sort()
        for name in sorted(filenames):
            p = base / name
            rel = p.relative_to(repo).as_posix()
            try:
                st = p.lstat()
            except OSError as exc:
                fail("PF-CORPUS-PATH", f"cannot lstat corpus file {rel}: {exc}")
            if stat_mod.S_ISLNK(st.st_mode):
                fail("PF-CORPUS-PATH", f"symlink under corpus rejected: {rel}")
            if not stat_mod.S_ISREG(st.st_mode):
                fail(
                    "PF-CORPUS-PATH",
                    f"non-regular under corpus rejected: {rel}",
                )
            found.add(rel)
    return found


def _role_for_corpus_path(rel: str) -> str:
    if rel.startswith(f"{CASES_REL}/") and rel.endswith(".json"):
        return "case"
    if rel.startswith(f"{CORPUS_V1_REL}/programs/"):
        return "source"
    if rel.startswith(f"{CORPUS_V1_REL}/schema-tests/"):
        return "schema-fixture"
    fail(
        "PF-CORPUS-INVARIANT",
        f"corpus path has no closed role mapping: {rel}",
    )


def _require_allowed_source_path(source_path: str, *, where: str) -> str:
    """sourcePath must be .lean under closed roots (no hidden components)."""
    # require_relative_path already bans abs/.. /empty; re-check.
    path = require_relative_path(source_path, where)
    if not path.endswith(".lean"):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where} must be a .lean source path, got {path!r}",
        )
    if any(part.startswith(".") for part in path.split("/")):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where} must not contain hidden path components: {path!r}",
        )
    if not any(path.startswith(root) for root in ALLOWED_SOURCE_ROOTS):
        fail(
            "PF-CORPUS-INVARIANT",
            f"{where} outside closed source roots {ALLOWED_SOURCE_ROOTS}: {path}",
        )
    return path


def _collect_case_source_paths(repo: Path, corpus_expected: set[str]) -> set[str]:
    """Decode business cases from fixed cases/ authority only (not arbitrary listed).

    Case bytes are opened via `_stable_read_regular` (O_NOFOLLOW descriptor path)
    after symlink-component checks — never `Path.read_bytes()` / race-follow.
    Standalone `load_and_validate_case` / `validate-case` CLI remain unchanged.
    """
    cases_dir = repo / CASES_REL
    if cases_dir.is_symlink():
        fail("PF-CORPUS-PATH", f"cases dir must not be a symlink: {cases_dir}")
    if not cases_dir.is_dir():
        fail("PF-CORPUS-PATH", f"missing cases dir {cases_dir}")
    case_ids: set[str] = set()
    required_sources: set[str] = set()
    for case_file in sorted(cases_dir.iterdir()):
        if case_file.name.startswith("."):
            continue
        # Only regular *.json; symlink/nonregular rejected before open.
        rel = case_file.relative_to(repo).as_posix()
        if case_file.is_symlink():
            fail("PF-CORPUS-PATH", f"symlink case file rejected: {rel}")
        if not case_file.name.endswith(".json"):
            # Non-json under cases/ is still corpus inventory; skip non-cases here.
            continue
        if rel not in corpus_expected:
            fail(
                "PF-CORPUS-INVARIANT",
                f"case file not in corpus inventory walk: {rel}",
            )
        where = f"case[{rel}]"
        _reject_symlink_components(repo, rel, where=where)
        # O_NOFOLLOW stable observation — rejects hardlink (nlink!=1) / nonregular.
        data, size, _digest = _stable_read_regular(case_file, where=where)
        if size > MAX_CASE_BYTES:
            fail(
                "PF-CORPUS-LIMIT",
                f"{where}: case exceeds {MAX_CASE_BYTES} bytes ({size})",
            )
        value = decode_canonical(data, max_bytes=MAX_CASE_BYTES)
        case = validate_case(value)
        case_id = str(case["id"])
        stem = case_file.stem
        if case_id != stem:
            fail(
                "PF-CORPUS-INVARIANT",
                f"case id {case_id!r} must equal filename stem {stem!r}",
            )
        if case_id in case_ids:
            fail("PF-CORPUS-INVARIANT", f"duplicate case id {case_id}")
        case_ids.add(case_id)
        source_path = _require_allowed_source_path(
            str(case["pins"]["sourcePath"]),  # type: ignore[index]
            where=f"case[{case_id}].pins.sourcePath",
        )
        required_sources.add(source_path)
    if not case_ids:
        fail("PF-CORPUS-INVARIANT", "no business cases under cases/")
    return required_sources


def validate_manifest_at(manifest_path: Path, repo_root: Path | None = None) -> dict[str, object]:
    """Load + structure-validate manifest and exact-join against disk inventory.

    Security order (engineering stable observation; not race-free):
      1. read sole canonical manifest path only;
      2. walk corpus + decode fixed cases/ authority → required sources;
      3. build exact allowlist = corpus ∪ sources ∪ REQUIRED_RUNNER_PATHS;
      4. listed paths must equal allowlist (extra/missing/role fail first);
      5. only then stable-read allowlisted paths for size/hash join.

    Never reads arbitrary listed external paths (e.g. .env) before allowlist.
    """
    # Consistent absolute identity (macOS /var vs /private/var). Prefer
    # os.path.abspath over Path.resolve() so temp trees and live trees join.
    repo = Path(os.path.abspath(str(repo_root or REPO_ROOT)))
    if Path(repo).is_symlink():
        fail("PF-CORPUS-PATH", f"repo root must not be a symlink: {repo}")

    man_in = manifest_path if manifest_path.is_absolute() else (repo / manifest_path)
    man_abs = Path(os.path.abspath(str(man_in)))
    try:
        man_rel = man_abs.relative_to(repo).as_posix()
    except ValueError:
        fail("PF-CORPUS-PATH", f"manifest path escapes repo: {man_abs}")
    if man_rel != MANIFEST_REL_PATH:
        fail(
            "PF-CORPUS-PATH",
            f"sole canonical manifest path is {MANIFEST_REL_PATH}, got {man_rel}",
        )
    _reject_symlink_components(repo, man_rel, where="manifest")

    raw, size, _ = _stable_read_regular(repo / man_rel, where="manifest")
    if size > MAX_MANIFEST_BYTES:
        fail(
            "PF-CORPUS-LIMIT",
            f"manifest exceeds {MAX_MANIFEST_BYTES} bytes ({size})",
        )
    value = decode_canonical(raw, max_bytes=MAX_MANIFEST_BYTES)
    manifest = validate_manifest_document(value)

    listed: dict[str, dict[str, object]] = {}
    for entry in manifest["files"]:  # type: ignore[index]
        listed[str(entry["path"])] = entry  # type: ignore[index]

    # 1) Exact corpus inventory (exclude manifest self). No external reads yet.
    corpus_files = _walk_corpus_regular_files(repo)
    corpus_expected = {p for p in corpus_files if p != MANIFEST_REL_PATH}
    listed_under_corpus = {
        p for p in listed if p == CORPUS_V1_REL or p.startswith(CORPUS_V1_REL + "/")
    }
    missing_corpus = sorted(corpus_expected - listed_under_corpus)
    extra_corpus = sorted(listed_under_corpus - corpus_expected)
    if missing_corpus:
        fail(
            "PF-CORPUS-INVARIANT",
            f"manifest missing corpus file(s): {missing_corpus[:5]}",
        )
    if extra_corpus:
        fail(
            "PF-CORPUS-INVARIANT",
            f"manifest lists extra/nonexistent corpus path(s): {extra_corpus[:5]}",
        )

    # 2) Decode cases from fixed cases/ authority → required sources.
    required_sources = _collect_case_source_paths(repo, corpus_expected)
    required_runners = set(REQUIRED_RUNNER_PATHS)

    # 3) Exact allowlist before any external/stable hash read of listed paths.
    allowlist = set(corpus_expected) | required_sources | required_runners
    listed_paths = set(listed.keys())
    extra_listed = sorted(listed_paths - allowlist)
    missing_listed = sorted(allowlist - listed_paths)
    if extra_listed:
        fail(
            "PF-CORPUS-INVARIANT",
            f"manifest lists path(s) outside exact allowlist "
            f"(not read): {extra_listed[:5]}",
        )
    if missing_listed:
        fail(
            "PF-CORPUS-INVARIANT",
            f"manifest missing required path(s): {missing_listed[:5]}",
        )

    # External (non-corpus) listed set must equal sources∪runners exactly.
    listed_external = {
        p for p in listed_paths if not (
            p == CORPUS_V1_REL or p.startswith(CORPUS_V1_REL + "/")
        )
    }
    expected_external = {
        p for p in (required_sources | required_runners)
        if not (p == CORPUS_V1_REL or p.startswith(CORPUS_V1_REL + "/"))
    }
    if listed_external != expected_external:
        fail(
            "PF-CORPUS-INVARIANT",
            f"listed external paths {sorted(listed_external)[:8]} != "
            f"required external {sorted(expected_external)[:8]}",
        )

    # Role pre-checks (no file content reads yet for external).
    for src in required_sources:
        if listed[src]["role"] != "source":
            fail(
                "PF-CORPUS-INVARIANT",
                f"sourcePath role must be source: {src}",
            )
    for runner in required_runners:
        if listed[runner]["role"] != "runner":
            fail(
                "PF-CORPUS-INVARIANT",
                f"runner path role must be runner: {runner}",
            )
    for path, entry in listed.items():
        if entry["role"] == "case":
            if not path.startswith(f"{CASES_REL}/") or not path.endswith(".json"):
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"case role path must live under {CASES_REL}/: {path}",
                )
        if path in corpus_expected:
            expected_role = _role_for_corpus_path(path)
            if entry["role"] != expected_role:
                fail(
                    "PF-CORPUS-INVARIANT",
                    f"role for {path} must be {expected_role}, got {entry['role']}",
                )
        if entry["role"] == "runner" and path not in required_runners:
            fail(
                "PF-CORPUS-INVARIANT",
                f"runner role only allowed for REQUIRED_RUNNER_PATHS: {path}",
            )

    # 4) Only after allowlist/role gates: stable-read each listed path.
    for path in sorted(listed.keys()):
        entry = listed[path]
        _reject_symlink_components(repo, path, where=f"file[{path}]")
        abs_p = repo / path
        if not abs_p.exists():
            fail("PF-CORPUS-INVARIANT", f"manifest path missing on disk: {path}")
        _data, disk_size, disk_sha = _stable_read_regular(
            abs_p, where=f"file[{path}]"
        )
        if disk_size != entry["size"]:
            fail(
                "PF-CORPUS-INVARIANT",
                f"size mismatch for {path}: disk={disk_size} manifest={entry['size']}",
            )
        if disk_sha != entry["sha256"]:
            fail(
                "PF-CORPUS-INVARIANT",
                f"sha256 mismatch for {path}: disk={disk_sha} manifest={entry['sha256']}",
            )

    return manifest


def _cmd_validate_manifest(path: Path) -> None:
    validate_manifest_at(path, REPO_ROOT)
    print(
        f"corpus-manifest-validated {path.as_posix()} "
        f"claims-not-verified (engineering inventory; not formal evidence)"
    )


def _run_manifest_self_tests() -> None:
    """Negative + positive validate-manifest coverage (temp trees)."""
    import shutil
    import tempfile

    # Positive: committed repo manifest must validate.
    man = REPO_ROOT / MANIFEST_REL_PATH
    if not man.is_file():
        raise AssertionError(f"committed manifest missing: {man}")
    validate_manifest_at(man, REPO_ROOT)

    def _copy_minimal_repo(dst: Path) -> None:
        # Copy just enough for inventory: corpus tree + external sources + runners.
        for rel in [
            CORPUS_V1_REL,
            "Examples/Counter.lean",
            "Examples/Accumulator.lean",
            "Examples/Token.lean",
            "testdata/valid/ArithOps.lean",
            *REQUIRED_RUNNER_PATHS,
        ]:
            src = REPO_ROOT / rel
            target = dst / rel
            if src.is_dir():
                shutil.copytree(src, target, symlinks=False)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, target)

    def _rewrite_manifest(repo: Path, mutate) -> Path:
        man_path = repo / MANIFEST_REL_PATH
        data = json.loads(man_path.read_text(encoding="utf-8"))
        mutate(data)
        raw = canonical_bytes(data)
        man_path.write_bytes(raw)
        return man_path

    def _entry(path: str, role: str, payload: bytes) -> dict[str, object]:
        return {
            "path": path,
            "role": role,
            "size": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        }

    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        _copy_minimal_repo(repo)
        # Baseline must pass.
        validate_manifest_at(repo / MANIFEST_REL_PATH, repo)

        # Stale hash.
        def stale_hash(data):
            data["files"][0]["sha256"] = "0" * 64

        _rewrite_manifest(repo, stale_hash)
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("stale hash must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"stale hash wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Stale size.
        def stale_size(data):
            data["files"][0]["size"] = int(data["files"][0]["size"]) + 1

        _rewrite_manifest(repo, stale_size)
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("stale size must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"stale size wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Missing listed path (delete a source).
        victim = repo / "Examples/Counter.lean"
        victim.unlink()
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("missing path must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"missing path wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Extra corpus file not listed.
        extra = repo / CORPUS_V1_REL / "cases" / "extra.evil.json"
        extra.write_text("{}", encoding="utf-8")
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("extra corpus file must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"extra corpus wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Duplicate path entries.
        def dup_path(data):
            files = list(data["files"])
            files.append(dict(files[0]))
            files.sort(key=lambda e: e["path"])
            data["files"] = files

        _rewrite_manifest(repo, dup_path)
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("duplicate path must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"dup path wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Unknown role.
        def unknown_role(data):
            data["files"][0]["role"] = "oracle"

        _rewrite_manifest(repo, unknown_role)
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("unknown role must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-SCHEMA":
                raise AssertionError(f"unknown role wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Manifest self-list.
        def self_list(data):
            self_entry = {
                "path": MANIFEST_REL_PATH,
                "role": "runner",
                "size": 1,
                "sha256": "0" * 64,
            }
            files = list(data["files"]) + [self_entry]
            files.sort(key=lambda e: e["path"])
            data["files"] = files

        _rewrite_manifest(repo, self_list)
        try:
            validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
            raise AssertionError("manifest self-list must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-INVARIANT":
                raise AssertionError(f"self-list wrong code {err.code}") from err

        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)

        # Path escape via .. component is rejected at document decode.
        try:
            validate_manifest_document(
                {
                    "schema": SCHEMA_MANIFEST,
                    "files": [
                        {
                            "path": "../secret",
                            "role": "source",
                            "size": 1,
                            "sha256": "0" * 64,
                        }
                    ],
                }
            )
            raise AssertionError("path escape must fail")
        except CorpusError as err:
            if err.code != "PF-CORPUS-PATH":
                raise AssertionError(f"path escape wrong code {err.code}") from err

        # --- Malicious external allowlist: .env must not be read ---
        secret = repo / ".env"
        secret.write_text("SUPER_SECRET_TOKEN=do-not-read\n", encoding="utf-8")
        secret_bytes = secret.read_bytes()

        def inject_env(data):
            files = list(data["files"])
            files.append(_entry(".env", "source", secret_bytes))
            files.sort(key=lambda e: e["path"])
            data["files"] = files

        _rewrite_manifest(repo, inject_env)
        # Probe: wrap _stable_read_regular to detect .env open.
        opened: list[str] = []
        real_stable = _stable_read_regular

        def tracking_stable(abs_path: Path, *, where: str):
            opened.append(str(abs_path))
            return real_stable(abs_path, where=where)

        # Patch same-module symbol so validate_manifest_at uses the probe.
        import sys as _sys
        mod = _sys.modules[__name__]
        setattr(mod, "_stable_read_regular", tracking_stable)
        try:
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("malicious .env listing must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-INVARIANT":
                    raise AssertionError(
                        f"malicious .env wrong code {err.code}"
                    ) from err
                if "allowlist" not in str(err) and ".env" not in str(err):
                    raise AssertionError(
                        f"malicious .env error must cite allowlist/.env: {err}"
                    ) from err
            # Ensure secret path was never opened by stable reader.
            for path in opened:
                if path.endswith("/.env") or path.endswith(".env"):
                    raise AssertionError(
                        f"validator must not stable-read .env, opened {path}"
                    )
        finally:
            setattr(mod, "_stable_read_regular", real_stable)

        # Case sourcePath pointing at .env (authority case rewrite).
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        secret = repo / ".env"
        secret.write_text("SUPER_SECRET_TOKEN=case-source\n", encoding="utf-8")
        # Rewrite a business case pins.sourcePath to .env (canonical).
        case_path = (
            repo / CASES_REL / "pf.primitive.counter.overflow-hold.v1.json"
        )
        case_obj = json.loads(case_path.read_bytes().decode("utf-8"))
        case_obj["pins"]["sourcePath"] = ".env"
        case_path.write_bytes(canonical_bytes(case_obj))
        # Manifest still lists Counter source; after case decode, allowlist
        # will require .env and reject it as outside closed source roots
        # before any .env read — or reject sourcePath validation.
        opened2: list[str] = []

        def tracking_stable2(abs_path: Path, *, where: str):
            opened2.append(str(abs_path))
            return real_stable(abs_path, where=where)

        setattr(mod, "_stable_read_regular", tracking_stable2)
        try:
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("case sourcePath=.env must fail")
            except CorpusError as err:
                if err.code not in {"PF-CORPUS-INVARIANT", "PF-CORPUS-PATH"}:
                    raise AssertionError(
                        f"case sourcePath .env wrong code {err.code}"
                    ) from err
            for path in opened2:
                if path.endswith("/.env") or path.endswith(".env"):
                    raise AssertionError(
                        f"case sourcePath .env must not be stable-read: {path}"
                    )
        finally:
            setattr(mod, "_stable_read_regular", real_stable)

        # Runner-role disguise of .env rejected by allowlist/role before read.
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        secret = repo / ".env"
        secret.write_text("SUPER_SECRET_TOKEN=runner-disguise\n", encoding="utf-8")
        secret_bytes = secret.read_bytes()

        def inject_env_runner(data):
            files = list(data["files"])
            files.append(_entry(".env", "runner", secret_bytes))
            files.sort(key=lambda e: e["path"])
            data["files"] = files

        _rewrite_manifest(repo, inject_env_runner)
        opened3: list[str] = []

        def tracking_stable3(abs_path: Path, *, where: str):
            opened3.append(str(abs_path))
            return real_stable(abs_path, where=where)

        setattr(mod, "_stable_read_regular", tracking_stable3)
        try:
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("runner-disguised .env must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-INVARIANT":
                    raise AssertionError(
                        f"runner .env wrong code {err.code}"
                    ) from err
            for path in opened3:
                if path.endswith("/.env") or path.endswith(".env"):
                    raise AssertionError(
                        f"runner-disguised .env must not be stable-read: {path}"
                    )
        finally:
            setattr(mod, "_stable_read_regular", real_stable)

        # Symlink under corpus rejected.
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        link = repo / CORPUS_V1_REL / "cases" / "link-case.json"
        try:
            if link.exists():
                link.unlink()
            target_case = next((repo / CASES_REL).glob("*.json"))
            link.symlink_to(target_case.name)
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("symlink under corpus must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(f"symlink wrong code {err.code}") from err
        except OSError:
            pass
        finally:
            if link.is_symlink() or link.exists():
                link.unlink()

        # Symlink directory under corpus rejected (dirnames entry).
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        real_sub = repo / CORPUS_V1_REL / "schema-tests" / "positive"
        evil_dir = repo / CORPUS_V1_REL / "schema-tests" / "evil-link-dir"
        try:
            evil_dir.symlink_to(real_sub)
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("symlink directory under corpus must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"symlink dir wrong code {err.code}"
                    ) from err
                if "symlink directory" not in str(err) and "symlink" not in str(err):
                    raise AssertionError(
                        f"symlink dir error must mention symlink: {err}"
                    ) from err
        except OSError:
            pass
        finally:
            if evil_dir.is_symlink() or evil_dir.exists():
                evil_dir.unlink()

        # Parent-path symlink component for listed external source.
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        examples = repo / "Examples"
        real_examples = repo / "Examples-real"
        try:
            examples.rename(real_examples)
            examples.symlink_to(real_examples)
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("parent symlink Examples/ must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"parent symlink wrong code {err.code}"
                    ) from err
        except OSError:
            # Restore if rename failed mid-flight.
            if real_examples.exists() and not examples.exists():
                real_examples.rename(examples)
        finally:
            if examples.is_symlink():
                examples.unlink()
            if real_examples.exists() and not examples.exists():
                real_examples.rename(examples)

        # Hardlink of a listed external source rejected when nlink>1.
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        target = repo / "Examples/Counter.lean"
        hard = repo / "Examples/Counter.hardlink.lean"
        try:
            os.link(target, hard)
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("hardlink nlink>1 must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(f"hardlink wrong code {err.code}") from err
        except OSError:
            pass
        finally:
            if hard.exists():
                hard.unlink()

        # Case-file hardlink (alias outside corpus) raises nlink on the case
        # authority during allowlist-build stable read — not Path.read_bytes.
        shutil.rmtree(repo)
        repo.mkdir()
        _copy_minimal_repo(repo)
        case_target = next((repo / CASES_REL).glob("*.json"))
        # Keep alias outside corpus walk so inventory join does not fire first.
        case_hard = repo / "case-hardlink-alias.json"
        try:
            os.link(case_target, case_hard)
            try:
                validate_manifest_at(repo / MANIFEST_REL_PATH, repo)
                raise AssertionError("case hardlink nlink>1 must fail")
            except CorpusError as err:
                if err.code != "PF-CORPUS-PATH":
                    raise AssertionError(
                        f"case hardlink wrong code {err.code}: {err}"
                    ) from err
                if "hardlink" not in str(err) and "nlink" not in str(err):
                    raise AssertionError(
                        f"case hardlink error must cite hardlink/nlink: {err}"
                    ) from err
        except OSError:
            pass
        finally:
            if case_hard.exists():
                case_hard.unlink()


def _cmd_validate_case(path: Path) -> None:
    load_and_validate_case(path)
    print(f"corpus-schema-validated case {path.as_posix()} claims-not-verified")


def _cmd_validate_observation(path: Path) -> None:
    load_and_validate_observation(path)
    print(
        f"corpus-schema-validated observation {path.as_posix()} claims-not-verified"
    )


def _cmd_close_case(case_path: Path, obs_dir: Path) -> None:
    case = load_and_validate_case(case_path)
    case_id = str(case["id"])
    observations = load_observations_dir(obs_dir, case_id)
    result = close_case(case, observations)
    # Success wording only after exact closure.
    if result.get("result") == "pass":
        print(
            f"corpus-case-closed-pass {case_id} claims-not-verified "
            f"(engineering corpus closure; not formal C-3; no OZ credit)"
        )
    elif result.get("result") == "skip":
        print(
            f"corpus-case-closed-skip {case_id} reason={result.get('reason')} "
            f"claims-not-verified (explicit skip; not pass; not formal C-3)"
        )
    else:
        fail("PF-CORPUS-INVARIANT", f"unexpected close result {result!r}")


def _cmd_safe_obs_root(repo: Path, obs: Path) -> None:
    # Sole stdout line: resolved path (spaces-safe; no banner prefix).
    print(require_safe_obs_root(obs, repo))


def _cmd_tool_lock_digest(lock_path: Path) -> None:
    print(darwin_tool_lock_v4_digest(lock_path))


def _cmd_list_runnable(cases_dir: Path) -> None:
    cases = list_runnable_cases(cases_dir)
    assert_runnable_set(cases)
    for case in cases:
        assert_case_pins(case)
        print(case["id"])


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
    if len(args) == 3 and args[0] == "close-case":
        _cmd_close_case(Path(args[1]), Path(args[2]))
        return
    if len(args) == 3 and args[0] == "safe-obs-root":
        _cmd_safe_obs_root(Path(args[1]), Path(args[2]))
        return
    if len(args) == 2 and args[0] == "tool-lock-digest":
        _cmd_tool_lock_digest(Path(args[1]))
        return
    if len(args) == 2 and args[0] == "list-runnable-cases":
        _cmd_list_runnable(Path(args[1]))
        return
    if len(args) == 2 and args[0] == "validate-manifest":
        _cmd_validate_manifest(Path(args[1]))
        return
    print(
        "usage: evm_corpus_v1.py self-test"
        " | validate-case PATH"
        " | validate-observation PATH"
        " | validate-manifest PATH"
        " | close-case CASE.json OBS_DIR"
        " | safe-obs-root REPO OBS"
        " | tool-lock-digest LOCK.json"
        " | list-runnable-cases CASES_DIR",
        file=sys.stderr,
    )
    raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except CorpusError as error:
        print(error.render(), file=sys.stderr)
        raise SystemExit(1)
