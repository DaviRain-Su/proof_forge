#!/usr/bin/env python3
"""Strict ProofForge V2 gate-evidence validation and publication.

This module intentionally uses only the Python standard library.  Gate
invocations must use the Stage-0-pinned direct Python with ``-I -S`` so user and
site packages cannot influence parsing, validation, or canonical encoding.
"""

from __future__ import annotations

_frame_probe_holder = []


def _capture_executing_module_frame():
    yield _frame_probe_holder[0].gi_frame.f_back


_frame_probe_generator = _capture_executing_module_frame()
_frame_probe_holder.append(_frame_probe_generator)
_executing_frame = _frame_probe_generator.send(None)
_frame_probe_generator.close()
_EXECUTING_MODULE_CODE = _executing_frame.f_code
_EXECUTING_MODULE_HAS_CALLER = _executing_frame.f_back is not None
del _capture_executing_module_frame
del _executing_frame
del _frame_probe_generator
del _frame_probe_holder

if _EXECUTING_MODULE_HAS_CALLER and (
    __name__ == "__main__" or _EXECUTING_MODULE_CODE.co_filename == "<stdin>"
):
    _early_os = __import__("os")
    _early_os.write(
        2,
        b"PF-EVIDENCE-FINALIZER-IDENTITY: finalizer module is not a direct stdin root frame\n",
    )
    _early_os._exit(2)
    raise SystemExit(2)

import argparse
import ast
import copy
import datetime as dt
import fcntl
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
from types import ModuleType
from typing import NoReturn


SCHEMA = "proof-forge.evidence.v1"
GATE_CATALOG_SCHEMA = "proof-forge.gate-catalog.v1"
GATE_CATALOG_DOMAIN = b"pf.gate-catalog.v1\x00"
ARTIFACT_SET_DOMAIN = b"pf.evidence.artifact-set.v1\x00"
MAX_INPUT_BYTES = 4 * 1024 * 1024
MAX_JSON_DEPTH = 64
MAX_JSON_NODES = 100_000
MAX_STRING_BYTES = 1024 * 1024
MAX_SAFE_INTEGER = (1 << 53) - 1
MAX_BUNDLE_FILES = 1024
MAX_BUNDLE_FILE_BYTES = 64 * 1024 * 1024
MAX_BUNDLE_TOTAL_BYTES = 256 * 1024 * 1024
MAX_SNAPSHOT_FILE_BYTES = 4 * 1024 * 1024
MAX_SNAPSHOT_TOTAL_BYTES = 64 * 1024 * 1024
CLAIM_SET_DOMAIN = b"pf.evidence.claim-set.v1\x00"

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
INVOCATION_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,47}")
ENVIRONMENT_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,254}")


class _CapturedBundleFile:
    __slots__ = ("relative_path", "content", "metadata", "sha256", "identity")

    def __init__(
        self,
        *,
        relative_path: str,
        content: bytes | None,
        metadata: os.stat_result,
        sha256: str,
        identity: tuple[int, ...],
    ) -> None:
        self.relative_path = relative_path
        self.content = content
        self.metadata = metadata
        self.sha256 = sha256
        self.identity = identity


class _DevelopmentBundleSnapshot:
    __slots__ = (
        "root_text",
        "evidence",
        "files",
        "checked_file_count",
        "claim_set_sha256",
        "identities",
    )

    def __init__(
        self,
        *,
        root_text: str,
        evidence: _CapturedBundleFile,
        files: dict[str, _CapturedBundleFile],
        checked_file_count: int,
        claim_set_sha256: str,
        identities: tuple[tuple[str, tuple[int, ...]], ...],
    ) -> None:
        self.root_text = root_text
        self.evidence = evidence
        self.files = files
        self.checked_file_count = checked_file_count
        self.claim_set_sha256 = claim_set_sha256
        self.identities = identities


class EvidenceError(RuntimeError):
    """Stable, user-facing evidence rejection."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def fail(code: str, message: str) -> NoReturn:
    raise EvidenceError(code, message)


_EVIDENCE_V1_CORE_PUBLIC = (
    "EvidenceError",
    "artifact_set_sha256",
    "canonical_bytes",
    "decode_json",
    "validate_evidence",
)
_PINNED_EVIDENCE_V1_CORE_SHA256 = (
    "7868d7ec30af6a32ebcbadec8cf794743ae9b0d14db4ba96e12e489b57d257e7"
)


_IMPLEMENTATION_STABLE_FIELDS = (
    "st_dev",
    "st_ino",
    "st_mode",
    "st_uid",
    "st_nlink",
    "st_size",
    "st_mtime_ns",
    "st_ctime_ns",
)


def _implementation_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return tuple(
        int(getattr(metadata, field)) for field in _IMPLEMENTATION_STABLE_FIELDS
    )


def _stable_read_open_implementation(
    descriptor: int,
    *,
    where: str,
    code: str = "PF-EVIDENCE-CATALOG-DIGEST",
) -> tuple[bytes, tuple[int, ...]]:
    """Capture an already-open regular implementation without changing its offset."""
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid not in {0, os.geteuid()}
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) & 0o022
            or before.st_size <= 0
            or before.st_size > MAX_INPUT_BYTES
        ):
            fail(
                code,
                f"{where} implementation metadata is outside the stable source profile",
            )
        chunks: list[bytes] = []
        offset = 0
        while offset <= before.st_size:
            chunk = os.pread(
                descriptor,
                min(before.st_size + 1 - offset, 128 * 1024),
                offset,
            )
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
        data = b"".join(chunks)
        after = os.fstat(descriptor)
        before_identity = _implementation_identity(before)
        if len(data) != before.st_size or before_identity != _implementation_identity(after):
            fail(code, f"{where} implementation changed during stable capture")
        return data, before_identity
    except EvidenceError:
        raise
    except OSError as exc:
        fail(code, f"cannot stable-read {where} implementation: {exc.strerror}")


def _stable_read_implementation(
    path: Path,
    *,
    where: str,
    code: str = "PF-EVIDENCE-CATALOG-DIGEST",
) -> tuple[bytes, tuple[int, ...]]:
    """Capture one implementation file without following or reopening its pathname."""
    flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    descriptor: int | None = None
    try:
        descriptor = os.open(path, flags)
        data, before_identity = _stable_read_open_implementation(
            descriptor,
            where=where,
            code=code,
        )
        try:
            pathname = os.stat(path, follow_symlinks=False)
        except OSError as exc:
            fail(
                code,
                f"cannot restat {where} implementation: {exc.strerror}",
            )
        if before_identity != _implementation_identity(pathname):
            fail(
                code,
                f"{where} implementation changed during stable capture",
            )
        return data, before_identity
    except EvidenceError:
        raise
    except OSError as exc:
        fail(
            code,
            f"cannot stable-read {where} implementation: {exc.strerror}",
        )
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _bootstrap_executing_source_argument() -> Path:
    option = "--executing-source"
    positions = [index for index, value in enumerate(sys.argv[1:], start=1) if value == option]
    if (
        len(positions) != 1
        or positions[0] + 1 >= len(sys.argv)
        or any(value.startswith(option + "=") for value in sys.argv[1:])
    ):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "fd-bound finalization requires exactly one separate --executing-source argument",
        )
    value = sys.argv[positions[0] + 1]
    try:
        value_bytes = value.encode("utf-8")
    except UnicodeError:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "--executing-source must be scalar Unicode encodable as UTF-8",
        )
    if (
        not value
        or len(value_bytes) > 4096
        or unicodedata.normalize("NFC", value) != value
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
        or not os.path.isabs(value)
        or os.path.abspath(value) != value
    ):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "--executing-source must be one normalized absolute pathname",
        )
    source = Path(value)
    if source.name != "gate_evidence.py":
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "--executing-source must name gate_evidence.py",
        )
    try:
        if source.resolve(strict=True) != source:
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "--executing-source must not traverse a symlinked pathname",
            )
    except OSError as exc:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            f"cannot resolve --executing-source: {exc.strerror}",
        )
    return source


def _capture_bound_finalizer_context() -> dict[str, object] | None:
    stdin_code = _EXECUTING_MODULE_CODE.co_filename == "<stdin>"
    stdin_file = os.fspath(__file__) == "<stdin>"
    stdin_argv = bool(sys.argv) and sys.argv[0] == "-"
    if not stdin_code and not stdin_file and not stdin_argv:
        return None
    if not stdin_code or not stdin_file or not stdin_argv:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "stdin finalizer source markers are internally inconsistent",
        )
    if _EXECUTING_MODULE_HAS_CALLER:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "finalizer module must be the root frame of direct Python stdin execution",
        )
    executing_descriptor = 0
    source_path = _bootstrap_executing_source_argument()
    directory_descriptor: int | None = None
    source_descriptor: int | None = None
    core_descriptor: int | None = None
    retained = False
    flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    try:
        descriptor_flags = fcntl.fcntl(executing_descriptor, fcntl.F_GETFL)
        if descriptor_flags & os.O_ACCMODE != os.O_RDONLY:
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "finalizer stdin source descriptor must be read-only",
            )
        directory_descriptor = os.open(
            source_path.parent,
            flags | getattr(os, "O_DIRECTORY", 0),
        )
        directory = os.fstat(directory_descriptor)
        if (
            not stat.S_ISDIR(directory.st_mode)
            or directory.st_uid not in {0, os.geteuid()}
            or stat.S_IMODE(directory.st_mode) & 0o022
        ):
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "executing-source directory is outside the stable source profile",
            )
        executing_bytes, executing_identity = _stable_read_open_implementation(
            executing_descriptor,
            where="executing finalizer descriptor",
            code="PF-EVIDENCE-FINALIZER-IDENTITY",
        )
        source_descriptor = os.open(
            source_path.name,
            flags,
            dir_fd=directory_descriptor,
        )
        source_bytes, source_identity = _stable_read_open_implementation(
            source_descriptor,
            where="executing finalizer pathname",
            code="PF-EVIDENCE-FINALIZER-IDENTITY",
        )
        if executing_identity != source_identity or executing_bytes != source_bytes:
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "executing descriptor and executing-source pathname are not one source image",
            )
        compiled = compile(
            executing_bytes,
            os.fspath(__file__),
            "exec",
            dont_inherit=True,
            optimize=sys.flags.optimize,
        )
        if compiled != _EXECUTING_MODULE_CODE:
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "captured finalizer bytes do not compile to the executing module code",
            )
        core_path = source_path.with_name("evidence_v1_core.py")
        core_descriptor = os.open(
            core_path.name,
            flags,
            dir_fd=directory_descriptor,
        )
        core_bytes, core_identity = _stable_read_open_implementation(
            core_descriptor,
            where="evidence schema core sibling",
            code="PF-EVIDENCE-FINALIZER-IDENTITY",
        )
        os.close(source_descriptor)
        source_descriptor = None
        retained = True
        return {
            "coreBytes": core_bytes,
            "coreDescriptor": core_descriptor,
            "coreIdentity": core_identity,
            "corePath": core_path,
            "directoryDescriptor": directory_descriptor,
            "directoryIdentity": _implementation_identity(directory),
            "executingBytes": executing_bytes,
            "executingDescriptor": executing_descriptor,
            "executingIdentity": executing_identity,
            "sourcePath": source_path,
        }
    except EvidenceError:
        raise
    except (OSError, SyntaxError, UnicodeError, ValueError) as exc:
        detail = getattr(exc, "strerror", None) or str(exc)
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            f"cannot bind the executing finalizer source image: {detail}",
        )
    finally:
        if source_descriptor is not None:
            os.close(source_descriptor)
        if core_descriptor is not None and not retained:
            os.close(core_descriptor)
        if directory_descriptor is not None and not retained:
            os.close(directory_descriptor)


try:
    _BOUND_FINALIZER_CONTEXT = _capture_bound_finalizer_context()
except EvidenceError as _bootstrap_error:
    print(f"{_bootstrap_error.code}: {_bootstrap_error}", file=sys.stderr)
    raise SystemExit(2) from None


def _load_evidence_v1_core(
) -> tuple[ModuleType, Path, bytes, tuple[int, ...]]:
    """Execute the exact stable-captured sibling without consulting ``sys.path``."""
    if _BOUND_FINALIZER_CONTEXT is None:
        gate_path = Path(os.path.abspath(__file__))
        core_path = gate_path.with_name("evidence_v1_core.py")
        core_bytes, core_identity = _stable_read_implementation(
            core_path,
            where="evidence schema core",
        )
    else:
        core_path = _BOUND_FINALIZER_CONTEXT["corePath"]
        core_bytes = _BOUND_FINALIZER_CONTEXT["coreBytes"]
        core_identity = _BOUND_FINALIZER_CONTEXT["coreIdentity"]
        if (
            not isinstance(core_path, Path)
            or not isinstance(core_bytes, bytes)
            or not isinstance(core_identity, tuple)
        ):
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "captured evidence core context has an invalid internal shape",
            )
    if hashlib.sha256(core_bytes).hexdigest() != _PINNED_EVIDENCE_V1_CORE_SHA256:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "exact sibling evidence_v1_core.py does not match the finalizer source pin",
        )
    module = ModuleType("_proof_forge_gate_evidence_v1_core")
    module.__file__ = os.fspath(core_path)
    module.__package__ = ""
    try:
        code = compile(core_bytes, os.fspath(core_path), "exec", dont_inherit=True)
        exec(code, module.__dict__)
    except (SyntaxError, UnicodeError) as exc:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            f"cannot execute the captured evidence schema core: {exc}",
        )
    except Exception as exc:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "captured evidence schema core raised during loading: "
            f"{type(exc).__name__}",
        )
    if tuple(module.__dict__.get("__all__", ())) != _EVIDENCE_V1_CORE_PUBLIC:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "evidence v1 core public surface does not match the pinned ABI",
        )
    return module, core_path, core_bytes, core_identity


try:
    (
        _EVIDENCE_V1_CORE,
        _EVIDENCE_V1_CORE_PATH,
        _EVIDENCE_V1_CORE_BYTES,
        _EVIDENCE_V1_CORE_IDENTITY,
    ) = _load_evidence_v1_core()
except EvidenceError as _core_bootstrap_error:
    print(f"{_core_bootstrap_error.code}: {_core_bootstrap_error}", file=sys.stderr)
    raise SystemExit(2) from None


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


# Keep the legacy definitions above during the low-risk extraction, but route
# every pure symbol consumed by the CLI/bundle layer to the exact sibling core.
# Bound functions retain the core module's own globals, so their validation
# behavior cannot fall back to the legacy definitions in this module.
_EVIDENCE_V1_CORE_ROUTED = (
    "EvidenceError",
    "fail",
    "_diagnostic_repr",
    "require_array",
    "require_int",
    "require_pattern",
    "require_sha256",
    "require_relative_path",
    "decode_json",
    "canonical_bytes",
    "artifact_set_sha256",
    "_validate_gate",
    "validate_evidence",
)
EvidenceError = _EVIDENCE_V1_CORE.__dict__["EvidenceError"]
fail = _EVIDENCE_V1_CORE.__dict__["fail"]
_diagnostic_repr = _EVIDENCE_V1_CORE.__dict__["_diagnostic_repr"]
require_array = _EVIDENCE_V1_CORE.__dict__["require_array"]
require_int = _EVIDENCE_V1_CORE.__dict__["require_int"]
require_pattern = _EVIDENCE_V1_CORE.__dict__["require_pattern"]
require_sha256 = _EVIDENCE_V1_CORE.__dict__["require_sha256"]
require_relative_path = _EVIDENCE_V1_CORE.__dict__["require_relative_path"]
decode_json = _EVIDENCE_V1_CORE.__dict__["decode_json"]
canonical_bytes = _EVIDENCE_V1_CORE.__dict__["canonical_bytes"]
artifact_set_sha256 = _EVIDENCE_V1_CORE.__dict__["artifact_set_sha256"]
_validate_gate = _EVIDENCE_V1_CORE.__dict__["_validate_gate"]
validate_evidence = _EVIDENCE_V1_CORE.__dict__["validate_evidence"]


_CATALOG_LOCK_FIELDS = {
    "hostBootstrapSha256",
    "hostProfileLockSha256",
    "toolchainLockSha256",
    "stage0LauncherSha256",
    "stage0VerifierSha256",
    "sandboxEngineSha256",
    "sandboxRendererSha256",
    "sandboxLauncherSha256",
    "sandboxProbeWrapperSha256",
    "evidenceValidatorSha256",
    "evidenceSchemaCoreSha256",
    "finalizerSha256",
}
_CATALOG_STRUCTURAL_INPUT_ROLES = {
    "gate-catalog",
    "clean-room-run-context",
    "host-observation",
    "host-bootstrap-lock",
    "host-profile-lock",
    "toolchain-lock",
    "host-stage0-launcher",
    "host-stage0-verifier",
    "sandbox-launcher",
    "sandbox-policy-renderer",
    "sandbox-probe-wrapper",
    "evidence-schema-core",
    "sandbox-rendered-policy",
    "sandbox-invocation-context",
    "sandbox-invocation-receipt",
}
_SNAPSHOT_SEMANTIC_INPUT_ROLES = _CATALOG_STRUCTURAL_INPUT_ROLES | {
    "gate-launcher",
}


def _validate_catalog_role_path(
    value: object,
    where: str,
    *,
    expected_role: str | None = None,
) -> dict[str, object]:
    reference = require_keys(value, {"role", "path"}, where)
    role = require_safe_id(reference["role"], _where(where, "role"))
    require_relative_path(reference["path"], _where(where, "path"))
    if expected_role is not None and role != expected_role:
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.role must be {expected_role!r}",
        )
    return reference


def _validate_catalog_value_matcher(value: object, where: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("PF-EVIDENCE-CATALOG", f"{where} must be a value matcher object")
    kind = value.get("kind")
    if kind == "literal":
        matcher = require_keys(value, {"kind", "value"}, where)
        literal = matcher["value"]
        if isinstance(literal, bool) or not isinstance(literal, (str, int)):
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{where}.value must be a string or integer literal",
            )
        if isinstance(literal, str):
            require_text(
                literal,
                _where(where, "value"),
                allow_empty=True,
                max_bytes=65536,
            )
        else:
            require_int(literal, _where(where, "value"))
        return matcher
    if kind in {"binding", "binding-decimal"}:
        matcher = require_keys(value, {"kind", "name"}, where)
        require_safe_id(matcher["name"], _where(where, "name"))
        return matcher
    if kind == "run-path":
        matcher = require_keys(value, {"kind", "relative"}, where)
        require_relative_path(matcher["relative"], _where(where, "relative"))
        return matcher
    fail("PF-EVIDENCE-CATALOG", f"{where}.kind is not a supported value matcher")


def _validate_catalog_executable(value: object, where: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("PF-EVIDENCE-CATALOG", f"{where} must be an executable reference object")
    kind = value.get("kind")
    if kind == "tool":
        reference = require_keys(value, {"kind", "id"}, where)
        require_safe_id(reference["id"], _where(where, "id"))
        return reference
    if kind == "input":
        reference = require_keys(value, {"kind", "role", "path"}, where)
        require_safe_id(reference["role"], _where(where, "role"))
        require_relative_path(reference["path"], _where(where, "path"))
        return reference
    if kind == "artifact":
        reference = require_keys(
            value,
            {"kind", "target", "role", "path"},
            where,
        )
        require_safe_id(reference["target"], _where(where, "target"))
        require_safe_id(reference["role"], _where(where, "role"))
        require_relative_path(reference["path"], _where(where, "path"))
        return reference
    fail("PF-EVIDENCE-CATALOG", f"{where}.kind is not a supported executable reference")


def _validate_catalog_probe(
    value: object,
    where: str,
) -> tuple[dict[str, object], tuple[str, str], dict[str, object]]:
    probe = require_keys(
        value,
        {
            "id",
            "stage",
            "invocation",
            "outcome",
            "invocationContextInput",
            "receiptInput",
            "stdoutLog",
            "stderrLog",
            "denial",
            "command",
        },
        where,
    )
    require_safe_id(probe["id"], _where(where, "id"))
    stage = require_enum(
        probe["stage"],
        {"materialize", "core", "evm-runtime"},
        _where(where, "stage"),
    )
    invocation = require_pattern(
        probe["invocation"],
        INVOCATION_RE,
        _where(where, "invocation"),
    )
    outcome = require_enum(
        probe["outcome"],
        {"success", "permission-denied"},
        _where(where, "outcome"),
    )
    context_reference = _validate_catalog_role_path(
        probe["invocationContextInput"],
        _where(where, "invocationContextInput"),
        expected_role="sandbox-invocation-context",
    )
    receipt_reference = _validate_catalog_role_path(
        probe["receiptInput"],
        _where(where, "receiptInput"),
        expected_role="sandbox-invocation-receipt",
    )
    stdout_log = require_relative_path(probe["stdoutLog"], _where(where, "stdoutLog"))
    stderr_log = require_relative_path(probe["stderrLog"], _where(where, "stderrLog"))
    fixed_paths = {
        "invocationContextInput": (
            context_reference["path"],
            f"contexts/sandbox-{stage}-{invocation}.json",
        ),
        "receiptInput": (
            receipt_reference["path"],
            f"policies/sandbox-{stage}-{invocation}.receipt.json",
        ),
        "stdoutLog": (
            stdout_log,
            f"policies/sandbox-{stage}-{invocation}.stdout.log",
        ),
        "stderrLog": (
            stderr_log,
            f"policies/sandbox-{stage}-{invocation}.stderr.log",
        ),
    }
    for field, (actual_path, expected_path) in fixed_paths.items():
        if actual_path != expected_path:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{where}.{field} must use the fixed stage/invocation path",
            )
    denial = probe["denial"]
    denial_object: dict[str, object] | None = None
    if outcome == "success":
        if denial is not None:
            fail("PF-EVIDENCE-CATALOG", f"{where}.denial must be null for success")
    else:
        denial_object = require_keys(
            denial,
            {"operation", "allowedErrnos"},
            _where(where, "denial"),
        )
        require_enum(
            denial_object["operation"],
            {"file-read", "file-write", "process-exec", "tcp-connect", "tcp-bind"},
            _where(_where(where, "denial"), "operation"),
        )
        errnos = require_array(
            denial_object["allowedErrnos"],
            _where(_where(where, "denial"), "allowedErrnos"),
        )
        if errnos != ["EACCES", "EPERM"]:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{where}.denial.allowedErrnos must be ['EACCES', 'EPERM']",
            )

    command_where = _where(where, "command")
    command = require_keys(
        probe["command"],
        {"executable", "argv", "environment"},
        command_where,
    )
    executable = _validate_catalog_executable(
        command["executable"],
        _where(command_where, "executable"),
    )
    argv = require_array(
        command["argv"],
        _where(command_where, "argv"),
        nonempty=True,
    )
    for index, matcher in enumerate(argv):
        _validate_catalog_value_matcher(
            matcher,
            f"{command_where}.argv[{index}]",
        )
    environment = require_array(
        command["environment"],
        _where(command_where, "environment"),
    )
    names: list[str] = []
    for index, entry_value in enumerate(environment):
        entry_where = f"{command_where}.environment[{index}]"
        entry = require_keys(entry_value, {"name", "value"}, entry_where)
        name = require_pattern(
            entry["name"],
            ENVIRONMENT_NAME_RE,
            _where(entry_where, "name"),
        )
        names.append(name)
        _validate_catalog_value_matcher(entry["value"], _where(entry_where, "value"))
    require_sorted_unique(names, _where(command_where, "environment"))
    if outcome == "permission-denied":
        if denial_object is None:
            fail("PF-EVIDENCE-CATALOG", f"{where}.denial is not a validated object")
        executable_path = executable.get("path")
        if (
            executable.get("kind") != "input"
            or executable.get("role") != "sandbox-probe-wrapper"
            or not isinstance(executable_path, str)
        ):
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{command_where}.executable must be the sandbox-probe-wrapper input",
            )
        required_prefix = [
            {"kind": "run-path", "relative": executable_path},
            {"kind": "literal", "value": denial_object["operation"]},
        ]
        if len(argv) < len(required_prefix) or argv[:2] != required_prefix:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{command_where}.argv must begin with wrapper path and denial operation",
            )
    return probe, (stage, invocation), executable


def _validate_catalog_policy(
    value: object,
    where: str,
) -> tuple[dict[str, object], list[tuple[str, str]], list[dict[str, object]]]:
    policy = require_keys(
        value,
        {
            "id",
            "engine",
            "engineSha256",
            "defaultAction",
            "network",
            "networkPort",
            "templateSha256",
            "renderedPolicyInput",
            "probes",
        },
        where,
    )
    require_safe_id(policy["id"], _where(where, "id"))
    require_safe_id(policy["engine"], _where(where, "engine"))
    require_sha256(policy["engineSha256"], _where(where, "engineSha256"))
    require_enum(policy["defaultAction"], {"allow", "deny"}, _where(where, "defaultAction"))
    network = require_enum(
        policy["network"],
        {"deny-all", "exact-local-port", "loopback-only"},
        _where(where, "network"),
    )
    if network == "exact-local-port":
        matcher = _validate_catalog_value_matcher(
            policy["networkPort"],
            _where(where, "networkPort"),
        )
        if matcher["kind"] != "binding":
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{where}.networkPort must use an integer binding matcher",
            )
    elif policy["networkPort"] is not None:
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.networkPort must be null unless network is exact-local-port",
        )
    require_sha256(policy["templateSha256"], _where(where, "templateSha256"))
    _validate_catalog_role_path(
        policy["renderedPolicyInput"],
        _where(where, "renderedPolicyInput"),
        expected_role="sandbox-rendered-policy",
    )
    probes = require_array(policy["probes"], _where(where, "probes"), nonempty=True)
    probe_ids: list[str] = []
    invocations: list[tuple[str, str]] = []
    executable_consumers: list[dict[str, object]] = []
    for index, probe_value in enumerate(probes):
        probe, invocation, executable = _validate_catalog_probe(
            probe_value,
            f"{where}.probes[{index}]",
        )
        probe_id = probe["id"]
        if not isinstance(probe_id, str):
            fail("PF-EVIDENCE-CATALOG", f"{where}.probes[{index}].id must be a string")
        probe_ids.append(probe_id)
        invocations.append(invocation)
        executable_consumers.append(executable)
    require_sorted_unique(probe_ids, _where(where, "probes"))
    stages = {stage for stage, _ in invocations}
    if len(stages) != 1:
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.probes must all use one rendered-policy stage",
        )
    stage = next(iter(stages))
    rendered = policy["renderedPolicyInput"]
    if not isinstance(rendered, dict) or rendered.get("path") != f"policies/{stage}.sb":
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.renderedPolicyInput.path must be policies/{stage}.sb",
        )
    return policy, invocations, executable_consumers


def _validate_catalog_tool(value: object, where: str) -> dict[str, object]:
    tool = require_keys(
        value,
        {
            "id",
            "version",
            "source",
            "assetSha256",
            "executableSha256",
            "closureSha256",
            "usage",
            "closureOf",
        },
        where,
    )
    require_safe_id(tool["id"], _where(where, "id"))
    require_text(tool["version"], _where(where, "version"), max_bytes=512)
    require_text(tool["source"], _where(where, "source"), max_bytes=2048)
    require_nullable_sha256(tool["assetSha256"], _where(where, "assetSha256"))
    require_sha256(tool["executableSha256"], _where(where, "executableSha256"))
    require_sha256(tool["closureSha256"], _where(where, "closureSha256"))
    usage = require_enum(
        tool["usage"],
        {"invoked", "closure-only"},
        _where(where, "usage"),
    )
    if usage == "invoked":
        if tool["closureOf"] is not None:
            fail("PF-EVIDENCE-CATALOG", f"{where}.closureOf must be null for invoked tools")
    else:
        require_safe_id(tool["closureOf"], _where(where, "closureOf"))
    return tool


def _validate_catalog_observation(value: object, where: str) -> dict[str, object]:
    observation = require_keys(
        value,
        {"step", "status", "return", "logicalState", "effects", "errorClass"},
        where,
    )
    require_safe_id(observation["step"], _where(where, "step"))
    require_enum(
        observation["status"],
        {"passed", "failed", "skipped"},
        _where(where, "status"),
    )
    if observation["errorClass"] is not None:
        require_safe_id(observation["errorClass"], _where(where, "errorClass"))
    return observation


def _validate_catalog_gate_path_sets(gate: dict[str, object], where: str) -> None:
    """Reject static claim aliases before any evidence/bundle evaluator runs."""
    claims: list[tuple[str, str]] = []

    def add(path: object, claim_where: str) -> None:
        if not isinstance(path, str):
            fail("PF-EVIDENCE-CATALOG", f"{claim_where} is not a validated path")
        claims.append((path, claim_where))

    host = gate["hostPolicy"]
    if not isinstance(host, dict) or not isinstance(host.get("observationInput"), dict):
        fail("PF-EVIDENCE-CATALOG", f"{where}.hostPolicy is not a validated object")
    add(
        host["observationInput"].get("path"),
        f"{where}.hostPolicy.observationInput.path",
    )

    policies = gate["policies"]
    if not isinstance(policies, list):
        fail("PF-EVIDENCE-CATALOG", f"{where}.policies is not a validated array")
    for policy_index, policy_value in enumerate(policies):
        policy_where = f"{where}.policies[{policy_index}]"
        if not isinstance(policy_value, dict):
            fail("PF-EVIDENCE-CATALOG", f"{policy_where} is not a validated object")
        rendered = policy_value.get("renderedPolicyInput")
        probes = policy_value.get("probes")
        if not isinstance(rendered, dict) or not isinstance(probes, list):
            fail("PF-EVIDENCE-CATALOG", f"{policy_where} is not structurally validated")
        add(rendered.get("path"), f"{policy_where}.renderedPolicyInput.path")
        for probe_index, probe_value in enumerate(probes):
            probe_where = f"{policy_where}.probes[{probe_index}]"
            if not isinstance(probe_value, dict):
                fail("PF-EVIDENCE-CATALOG", f"{probe_where} is not a validated object")
            context = probe_value.get("invocationContextInput")
            receipt = probe_value.get("receiptInput")
            if not isinstance(context, dict) or not isinstance(receipt, dict):
                fail("PF-EVIDENCE-CATALOG", f"{probe_where} is not structurally validated")
            add(context.get("path"), f"{probe_where}.invocationContextInput.path")
            add(receipt.get("path"), f"{probe_where}.receiptInput.path")
            add(probe_value.get("stdoutLog"), f"{probe_where}.stdoutLog")
            add(probe_value.get("stderrLog"), f"{probe_where}.stderrLog")

    for field in ("requiredInputs", "requiredArtifacts", "requiredLogs"):
        values = gate[field]
        if not isinstance(values, list):
            fail("PF-EVIDENCE-CATALOG", f"{where}.{field} is not a validated array")
        for index, value in enumerate(values):
            if not isinstance(value, dict):
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.{field}[{index}] is not a validated object",
                )
            add(value.get("path"), f"{where}.{field}[{index}].path")

    exact: dict[str, str] = {}
    folded: dict[str, tuple[str, str]] = {}
    for path, claim_where in claims:
        previous = exact.get(path)
        if previous is not None:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{claim_where} reuses static claim path {path!r} from {previous}",
            )
        exact[path] = claim_where
        folded_key = unicodedata.normalize("NFC", path).casefold()
        folded_previous = folded.get(folded_key)
        if folded_previous is not None:
            previous_path, previous_where = folded_previous
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{claim_where} casefold-aliases {previous_path!r} from {previous_where}",
            )
        folded[folded_key] = (path, claim_where)


def _validate_catalog_gate(value: object, where: str) -> dict[str, object]:
    gate = require_keys(
        value,
        {
            "id",
            "taskId",
            "testIds",
            "candidatePolicy",
            "hostPolicy",
            "commandPolicy",
            "requiredTools",
            "policies",
            "requiredInputs",
            "requiredArtifacts",
            "requiredObservations",
            "requiredLogs",
        },
        where,
    )
    require_safe_id(gate["id"], _where(where, "id"))
    require_pattern(gate["taskId"], TASK_ID_RE, _where(where, "taskId"))
    tests = require_array(gate["testIds"], _where(where, "testIds"), nonempty=True)
    test_ids = [
        require_pattern(test_id, TEST_ID_RE, f"{where}.testIds[{index}]")
        for index, test_id in enumerate(tests)
    ]
    require_sorted_unique(test_ids, _where(where, "testIds"))

    candidate_where = _where(where, "candidatePolicy")
    candidate = require_keys(
        gate["candidatePolicy"],
        {"subtree", "anchorSource", "dirty", "unchangedDuringRun", "archiveFormat"},
        candidate_where,
    )
    require_relative_path(candidate["subtree"], _where(candidate_where, "subtree"), allow_dot=True)
    require_enum(
        candidate["anchorSource"],
        {"derived-development", "external"},
        _where(candidate_where, "anchorSource"),
    )
    require_bool(candidate["dirty"], _where(candidate_where, "dirty"))
    require_bool(
        candidate["unchangedDuringRun"],
        _where(candidate_where, "unchangedDuringRun"),
    )
    require_enum(candidate["archiveFormat"], {"git-tar"}, _where(candidate_where, "archiveFormat"))

    host_where = _where(where, "hostPolicy")
    host = require_keys(
        gate["hostPolicy"],
        {
            "scope",
            "remoteAttestation",
            "profileId",
            "eligibleForHermetic",
            "observationInput",
        },
        host_where,
    )
    require_enum(host["scope"], {"local-point-in-time"}, _where(host_where, "scope"))
    if require_bool(host["remoteAttestation"], _where(host_where, "remoteAttestation")):
        fail("PF-EVIDENCE-CATALOG", f"{host_where}.remoteAttestation must be false")
    require_safe_id(host["profileId"], _where(host_where, "profileId"))
    require_bool(host["eligibleForHermetic"], _where(host_where, "eligibleForHermetic"))
    _validate_catalog_role_path(
        host["observationInput"],
        _where(host_where, "observationInput"),
        expected_role="host-observation",
    )

    command_where = _where(where, "commandPolicy")
    command = require_keys(
        gate["commandPolicy"],
        {"argv", "cwdRelative", "environmentSha256", "attempts", "result"},
        command_where,
    )
    argv = require_array(command["argv"], _where(command_where, "argv"), nonempty=True)
    for index, matcher in enumerate(argv):
        _validate_catalog_value_matcher(matcher, f"{command_where}.argv[{index}]")
    launcher_matcher = argv[0]
    if not isinstance(launcher_matcher, dict) or launcher_matcher.get("kind") != "run-path":
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{command_where}.argv[0] must be a retained run-path launcher",
        )
    launcher_relative = launcher_matcher.get("relative")
    if not isinstance(launcher_relative, str):
        fail("PF-EVIDENCE-CATALOG", f"{command_where}.argv[0] is not typed")
    require_relative_path(command["cwdRelative"], _where(command_where, "cwdRelative"), allow_dot=True)
    _validate_catalog_value_matcher(
        command["environmentSha256"],
        _where(command_where, "environmentSha256"),
    )
    attempts = require_int(command["attempts"], _where(command_where, "attempts"), minimum=1)
    if attempts != 1:
        fail("PF-EVIDENCE-CATALOG", f"{command_where}.attempts must be exactly 1")
    require_enum(command["result"], {"passed"}, _where(command_where, "result"))

    tools = require_array(gate["requiredTools"], _where(where, "requiredTools"), nonempty=True)
    tool_ids: list[str] = []
    tool_records: dict[str, dict[str, object]] = {}
    for index, tool_value in enumerate(tools):
        tool = _validate_catalog_tool(tool_value, f"{where}.requiredTools[{index}]")
        tool_id = tool["id"]
        if not isinstance(tool_id, str):
            fail("PF-EVIDENCE-CATALOG", f"{where}.requiredTools[{index}].id must be a string")
        tool_ids.append(tool_id)
        tool_records[tool_id] = tool
    require_sorted_unique(tool_ids, _where(where, "requiredTools"))

    policies = require_array(gate["policies"], _where(where, "policies"), nonempty=True)
    policy_ids: list[str] = []
    invocation_keys: list[tuple[str, str]] = []
    executable_consumers: list[dict[str, object]] = []
    for index, policy_value in enumerate(policies):
        policy, policy_invocations, policy_executables = _validate_catalog_policy(
            policy_value,
            f"{where}.policies[{index}]",
        )
        policy_id = policy["id"]
        if not isinstance(policy_id, str):
            fail("PF-EVIDENCE-CATALOG", f"{where}.policies[{index}].id must be a string")
        policy_ids.append(policy_id)
        invocation_keys.extend(policy_invocations)
        executable_consumers.extend(policy_executables)
    require_sorted_unique(policy_ids, _where(where, "policies"))
    if len(set(invocation_keys)) != len(invocation_keys):
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.policies reuses a stage/invocation identity",
        )
    consumed_tools = {
        executable["id"]
        for executable in executable_consumers
        if executable.get("kind") == "tool" and isinstance(executable.get("id"), str)
    }
    for tool_id, tool in tool_records.items():
        if tool["usage"] == "invoked":
            if tool_id not in consumed_tools:
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.requiredTools invoked tool is not consumed: {tool_id}",
                )
        else:
            closure_of = tool["closureOf"]
            if closure_of not in tool_records or tool_records[closure_of]["usage"] != "invoked":
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.requiredTools closure-only tool has no invoked closure owner",
                )
            if tool_id in consumed_tools:
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.requiredTools closure-only tool is an executable consumer",
                )
    unknown_tool_consumers = consumed_tools - set(tool_records)
    if unknown_tool_consumers:
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{where}.policies references an undeclared required tool",
        )

    required_inputs = require_array(gate["requiredInputs"], _where(where, "requiredInputs"))
    input_keys: list[tuple[str, str]] = []
    for index, reference_value in enumerate(required_inputs):
        reference = _validate_catalog_role_path(
            reference_value,
            f"{where}.requiredInputs[{index}]",
        )
        role = reference["role"]
        path = reference["path"]
        if not isinstance(role, str) or not isinstance(path, str):
            fail("PF-EVIDENCE-CATALOG", f"{where}.requiredInputs[{index}] is not typed")
        if role in _CATALOG_STRUCTURAL_INPUT_ROLES:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"{where}.requiredInputs duplicates structural role {role!r}",
            )
        input_keys.append((role, path))
    require_sorted_unique(input_keys, _where(where, "requiredInputs"))
    launcher_inputs = [key for key in input_keys if key[1] == launcher_relative]
    if len(launcher_inputs) != 1:
        fail(
            "PF-EVIDENCE-CATALOG",
            f"{command_where}.argv[0] must uniquely match one required input",
        )

    required_artifacts = require_array(
        gate["requiredArtifacts"],
        _where(where, "requiredArtifacts"),
    )
    artifact_keys: list[tuple[str, str, str]] = []
    artifact_records: dict[tuple[str, str, str], dict[str, object]] = {}
    for index, artifact_value in enumerate(required_artifacts):
        artifact_where = f"{where}.requiredArtifacts[{index}]"
        artifact = require_keys(
            artifact_value,
            {"target", "role", "path", "mediaType", "retained"},
            artifact_where,
        )
        target = require_safe_id(artifact["target"], _where(artifact_where, "target"))
        role = require_safe_id(artifact["role"], _where(artifact_where, "role"))
        path = require_relative_path(artifact["path"], _where(artifact_where, "path"))
        require_pattern(artifact["mediaType"], MEDIA_TYPE_RE, _where(artifact_where, "mediaType"))
        require_bool(artifact["retained"], _where(artifact_where, "retained"))
        key = (target, role, path)
        artifact_keys.append(key)
        artifact_records[key] = artifact
    require_sorted_unique(artifact_keys, _where(where, "requiredArtifacts"))

    declared_input_keys = set(input_keys)
    observation_input = host["observationInput"]
    if not isinstance(observation_input, dict):
        fail("PF-EVIDENCE-CATALOG", f"{host_where}.observationInput is not validated")
    observation_role = observation_input.get("role")
    observation_path = observation_input.get("path")
    if not isinstance(observation_role, str) or not isinstance(observation_path, str):
        fail("PF-EVIDENCE-CATALOG", f"{host_where}.observationInput is not typed")
    declared_input_keys.add((observation_role, observation_path))
    for policy_value in policies:
        if not isinstance(policy_value, dict):
            fail("PF-EVIDENCE-CATALOG", f"{where}.policies is not validated")
        rendered = policy_value.get("renderedPolicyInput")
        probes_value = policy_value.get("probes")
        if not isinstance(rendered, dict) or not isinstance(probes_value, list):
            fail("PF-EVIDENCE-CATALOG", f"{where}.policies is not structurally validated")
        rendered_role = rendered.get("role")
        rendered_path = rendered.get("path")
        if not isinstance(rendered_role, str) or not isinstance(rendered_path, str):
            fail("PF-EVIDENCE-CATALOG", f"{where}.policies rendered input is not typed")
        declared_input_keys.add((rendered_role, rendered_path))
        for probe_value in probes_value:
            if not isinstance(probe_value, dict):
                fail("PF-EVIDENCE-CATALOG", f"{where}.policies probe is not validated")
            for field in ("invocationContextInput", "receiptInput"):
                reference = probe_value.get(field)
                if not isinstance(reference, dict):
                    fail("PF-EVIDENCE-CATALOG", f"{where}.policies probe input is not typed")
                role = reference.get("role")
                path = reference.get("path")
                if not isinstance(role, str) or not isinstance(path, str):
                    fail("PF-EVIDENCE-CATALOG", f"{where}.policies probe input is not typed")
                declared_input_keys.add((role, path))

    path_deferred_singletons = _CATALOG_STRUCTURAL_INPUT_ROLES - {
        "host-observation",
        "sandbox-rendered-policy",
        "sandbox-invocation-context",
        "sandbox-invocation-receipt",
    }
    for executable in executable_consumers:
        kind = executable.get("kind")
        if kind == "input":
            role = executable.get("role")
            path = executable.get("path")
            if (
                not isinstance(role, str)
                or not isinstance(path, str)
                or (
                    (role, path) not in declared_input_keys
                    and role not in path_deferred_singletons
                )
            ):
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.policies has an input executable outside the effective input set",
                )
        elif kind == "artifact":
            target = executable.get("target")
            role = executable.get("role")
            path = executable.get("path")
            key = (target, role, path)
            artifact = artifact_records.get(key)  # type: ignore[arg-type]
            if artifact is None or artifact.get("retained") is not True:
                fail(
                    "PF-EVIDENCE-CATALOG",
                    f"{where}.policies has a missing or non-retained artifact executable",
                )

    observations = require_array(
        gate["requiredObservations"],
        _where(where, "requiredObservations"),
    )
    for index, observation in enumerate(observations):
        _validate_catalog_observation(
            observation,
            f"{where}.requiredObservations[{index}]",
        )

    required_logs = require_array(gate["requiredLogs"], _where(where, "requiredLogs"))
    log_paths: list[str] = []
    for index, log_value in enumerate(required_logs):
        log_where = f"{where}.requiredLogs[{index}]"
        log = require_keys(
            log_value,
            {"path", "truncated", "privateDataScan"},
            log_where,
        )
        path = require_relative_path(log["path"], _where(log_where, "path"))
        require_bool(log["truncated"], _where(log_where, "truncated"))
        require_enum(
            log["privateDataScan"],
            {"passed", "failed", "not-run"},
            _where(log_where, "privateDataScan"),
        )
        log_paths.append(path)
    require_sorted_unique(log_paths, _where(where, "requiredLogs"))
    _validate_catalog_gate_path_sets(gate, where)
    return gate


def _parse_development_catalog(data: bytes) -> dict[str, object]:
    """Parse every gate in one closed, canonical development catalog."""
    try:
        value = decode_json(data)
        if canonical_bytes(value) != data:
            fail("PF-EVIDENCE-CATALOG", "gate catalog bytes are not canonical PF JCS")
        catalog = require_keys(
            value,
            {"schema", "id", "version", "qualification", "requiredTestSet", "locks", "gates"},
            "catalog",
        )
        if catalog["schema"] != GATE_CATALOG_SCHEMA:
            fail(
                "PF-EVIDENCE-CATALOG",
                f"catalog.schema must be {GATE_CATALOG_SCHEMA!r}",
            )
        require_safe_id(catalog["id"], "catalog.id")
        require_pattern(catalog["version"], SEMVER_RE, "catalog.version")
        require_enum(catalog["qualification"], {"development"}, "catalog.qualification")
        if catalog["requiredTestSet"] is not None:
            fail(
                "PF-EVIDENCE-CATALOG",
                "development catalog.requiredTestSet must be explicit null",
            )
        locks = require_keys(catalog["locks"], _CATALOG_LOCK_FIELDS, "catalog.locks")
        for field in sorted(_CATALOG_LOCK_FIELDS):
            require_sha256(locks[field], f"catalog.locks.{field}")
        gates = require_array(catalog["gates"], "catalog.gates", nonempty=True)
        gate_ids: list[str] = []
        for index, gate_value in enumerate(gates):
            gate = _validate_catalog_gate(gate_value, f"catalog.gates[{index}]")
            gate_id = gate["id"]
            if not isinstance(gate_id, str):
                fail("PF-EVIDENCE-CATALOG", f"catalog.gates[{index}].id must be a string")
            gate_ids.append(gate_id)
        require_sorted_unique(gate_ids, "catalog.gates")
        return catalog
    except EvidenceError as exc:
        if exc.code == "PF-EVIDENCE-CATALOG":
            raise
        fail("PF-EVIDENCE-CATALOG", f"invalid gate catalog: {exc}")


def _require_catalog_cli_sha256(value: object, where: str) -> str:
    try:
        return require_sha256(value, where)
    except EvidenceError as exc:
        fail("PF-EVIDENCE-CATALOG-DIGEST", f"{where} is not a lowercase SHA-256: {exc}")


def _require_single_input_claim(
    document: dict[str, object],
    role: str,
    *,
    code: str,
) -> dict[str, object]:
    inputs = document["inputs"]
    if not isinstance(inputs, list):
        fail(code, "validated evidence inputs are not an array")
    matches = [
        entry
        for entry in inputs
        if isinstance(entry, dict) and entry.get("role") == role
    ]
    if len(matches) != 1:
        fail(code, f"evidence must contain exactly one input with role {role!r}")
    return matches[0]


def _join_development_catalog_identity(
    document: dict[str, object],
    catalog: dict[str, object],
    catalog_bytes: bytes,
    catalog_metadata: os.stat_result,
    *,
    catalog_relative: str,
    expected_content_sha256: str,
    expected_catalog_digest: str,
) -> dict[str, object]:
    content_sha256 = hashlib.sha256(catalog_bytes).hexdigest()
    catalog_digest = hashlib.sha256(GATE_CATALOG_DOMAIN + catalog_bytes).hexdigest()
    identity = {
        "schema": catalog["schema"],
        "id": catalog["id"],
        "version": catalog["version"],
        "contentSha256": content_sha256,
        "catalogDigest": catalog_digest,
    }
    if (
        expected_content_sha256 != content_sha256
        or expected_catalog_digest != catalog_digest
    ):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "caller catalog identity does not match the captured canonical catalog bytes",
        )
    if document.get("gateCatalog") != identity:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "evidence gateCatalog identity is split from the captured catalog bytes",
        )
    claim = _require_single_input_claim(
        document,
        "gate-catalog",
        code="PF-EVIDENCE-CATALOG-DIGEST",
    )
    if (
        claim.get("path") != catalog_relative
        or claim.get("sha256") != content_sha256
        or claim.get("size") != len(catalog_bytes)
        or catalog_metadata.st_size != len(catalog_bytes)
    ):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "catalog CLI path, evidence claim, and captured bytes are not exact",
        )
    return identity


def _select_development_catalog_gate(
    document: dict[str, object],
    catalog: dict[str, object],
) -> dict[str, object]:
    evidence_gate = document["gate"]
    if not isinstance(evidence_gate, dict):
        fail("PF-EVIDENCE-CATALOG-GATE", "validated evidence gate is not an object")
    gate_id = evidence_gate.get("id")
    gates = catalog["gates"]
    if not isinstance(gates, list):
        fail("PF-EVIDENCE-CATALOG", "validated catalog gates are not an array")
    selected = [
        gate
        for gate in gates
        if isinstance(gate, dict) and gate.get("id") == gate_id
    ]
    if len(selected) != 1:
        fail(
            "PF-EVIDENCE-CATALOG",
            "evidence gate id does not select exactly one catalog gate",
        )
    selected_gate = selected[0]
    if (
        catalog.get("qualification") != "development"
        or evidence_gate.get("qualification") != "development"
        or selected_gate.get("taskId") != evidence_gate.get("taskId")
        or selected_gate.get("testIds") != evidence_gate.get("testIds")
    ):
        fail(
            "PF-EVIDENCE-CATALOG-GATE",
            "selected catalog gate qualification/task/tests do not equal the evidence gate",
        )
    return selected_gate


def _join_development_candidate_host(
    document: dict[str, object],
    selected_gate: dict[str, object],
) -> None:
    repository = document["repository"]
    host = document["hostAttestation"]
    if not isinstance(repository, dict) or not isinstance(host, dict):
        fail(
            "PF-EVIDENCE-CANDIDATE-BINDING",
            "validated candidate or host record is not an object",
        )
    archive = repository.get("archive")
    if not isinstance(archive, dict):
        fail("PF-EVIDENCE-CANDIDATE-BINDING", "validated candidate archive is not an object")
    expected_candidate = {
        "subtree": repository.get("subtree"),
        "anchorSource": repository.get("anchorSource"),
        "dirty": repository.get("dirty"),
        "unchangedDuringRun": repository.get("unchangedDuringRun"),
        "archiveFormat": archive.get("format"),
    }
    if selected_gate.get("candidatePolicy") != expected_candidate:
        fail(
            "PF-EVIDENCE-CANDIDATE-BINDING",
            "selected catalog candidate policy does not equal the evidence candidate facts",
        )
    expected_host = {
        "scope": host.get("scope"),
        "remoteAttestation": host.get("remoteAttestation"),
        "profileId": host.get("profileId"),
        "eligibleForHermetic": host.get("eligibleForHermetic"),
        "observationInput": host.get("observationInput"),
    }
    if selected_gate.get("hostPolicy") != expected_host:
        fail(
            "PF-EVIDENCE-HOST-BINDING",
            "selected catalog host policy does not equal the evidence host facts",
        )


def _require_bound_development_execution(executing_source: object) -> dict[str, object]:
    context = _BOUND_FINALIZER_CONTEXT
    if context is None:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "development finalization requires fd-bound gate_evidence.py execution",
        )
    source_path = context.get("sourcePath")
    if (
        not isinstance(executing_source, str)
        or not isinstance(source_path, Path)
        or executing_source != os.fspath(source_path)
    ):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "parsed --executing-source does not equal the stdin-bound source pathname",
        )
    return context


def _join_development_implementation_closure(
    document: dict[str, object],
    catalog: dict[str, object],
    snapshot: _DevelopmentBundleSnapshot,
    executing_source: object,
) -> tuple[str, str]:
    context = _require_bound_development_execution(executing_source)
    source_path = context.get("sourcePath")
    if not isinstance(source_path, Path):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "fd-bound finalizer source path has an invalid internal shape",
        )
    executing_descriptor = context.get("executingDescriptor")
    directory_descriptor = context.get("directoryDescriptor")
    core_descriptor = context.get("coreDescriptor")
    executing_bytes = context.get("executingBytes")
    executing_identity = context.get("executingIdentity")
    directory_identity = context.get("directoryIdentity")
    core_bytes = context.get("coreBytes")
    core_identity = context.get("coreIdentity")
    core_path = context.get("corePath")
    if (
        not isinstance(executing_descriptor, int)
        or not isinstance(directory_descriptor, int)
        or not isinstance(core_descriptor, int)
        or not isinstance(executing_bytes, bytes)
        or not isinstance(executing_identity, tuple)
        or not isinstance(directory_identity, tuple)
        or not isinstance(core_bytes, bytes)
        or not isinstance(core_identity, tuple)
        or not isinstance(core_path, Path)
    ):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "fd-bound finalizer context has an invalid internal shape",
        )
    fresh_directory_descriptor: int | None = None
    try:
        current_gate_bytes, current_gate_identity = _stable_read_open_implementation(
            executing_descriptor,
            where="executing finalizer descriptor",
            code="PF-EVIDENCE-FINALIZER-IDENTITY",
        )
        current_core_bytes, current_core_identity = _stable_read_open_implementation(
            core_descriptor,
            where="evidence schema core descriptor",
            code="PF-EVIDENCE-FINALIZER-IDENTITY",
        )
        current_source_entry = os.stat(
            source_path.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        current_core_entry = os.stat(
            core_path.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        current_directory = os.fstat(directory_descriptor)
        if source_path.resolve(strict=True) != source_path:
            fail(
                "PF-EVIDENCE-FINALIZER-IDENTITY",
                "executing-source pathname became symlinked after bootstrap capture",
            )
        fresh_directory_descriptor = os.open(
            source_path.parent,
            os.O_RDONLY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
            | getattr(os, "O_DIRECTORY", 0),
        )
        fresh_directory = os.fstat(fresh_directory_descriptor)
        fresh_source_entry = os.stat(
            source_path.name,
            dir_fd=fresh_directory_descriptor,
            follow_symlinks=False,
        )
        fresh_core_entry = os.stat(
            core_path.name,
            dir_fd=fresh_directory_descriptor,
            follow_symlinks=False,
        )
    except EvidenceError:
        raise
    except OSError as exc:
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            f"cannot revalidate the fd-bound finalizer closure: {exc.strerror}",
        )
    finally:
        if fresh_directory_descriptor is not None:
            os.close(fresh_directory_descriptor)
    if (
        current_gate_bytes != executing_bytes
        or current_gate_identity != executing_identity
        or _implementation_identity(current_source_entry) != executing_identity
        or _implementation_identity(current_directory) != directory_identity
        or _implementation_identity(fresh_directory) != directory_identity
        or _implementation_identity(fresh_source_entry) != executing_identity
        or current_core_bytes != core_bytes
        or current_core_identity != core_identity
        or _implementation_identity(current_core_entry) != core_identity
        or _implementation_identity(fresh_core_entry) != core_identity
        or current_core_bytes != _EVIDENCE_V1_CORE_BYTES
        or current_core_identity != _EVIDENCE_V1_CORE_IDENTITY
    ):
        fail(
            "PF-EVIDENCE-FINALIZER-IDENTITY",
            "stdin-bound finalizer or exact sibling core changed after source capture",
        )
    gate_sha256 = hashlib.sha256(executing_bytes).hexdigest()
    core_sha256 = hashlib.sha256(_EVIDENCE_V1_CORE_BYTES).hexdigest()
    locks = catalog["locks"]
    if not isinstance(locks, dict):
        fail("PF-EVIDENCE-CATALOG-DIGEST", "validated catalog locks are not an object")
    if (
        locks.get("evidenceValidatorSha256") != gate_sha256
        or locks.get("finalizerSha256") != gate_sha256
        or locks.get("evidenceSchemaCoreSha256") != core_sha256
    ):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "catalog implementation locks do not equal the stable wrapper/core closure",
        )
    core_claim = _require_single_input_claim(
        document,
        "evidence-schema-core",
        code="PF-EVIDENCE-CATALOG-DIGEST",
    )
    core_claim_path = core_claim.get("path")
    if not isinstance(core_claim_path, str):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "evidence-schema-core input path is not a validated relative path",
        )
    retained_core = snapshot.files.get(core_claim_path)
    if retained_core is None or retained_core.content is None:
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "retained evidence-schema-core is absent from the single bundle snapshot",
        )
    retained_core_bytes = retained_core.content
    retained_metadata = retained_core.metadata
    if (
        retained_core_bytes != _EVIDENCE_V1_CORE_BYTES
        or retained_metadata.st_size != len(_EVIDENCE_V1_CORE_BYTES)
        or core_claim.get("sha256") != core_sha256
        or core_claim.get("size") != len(_EVIDENCE_V1_CORE_BYTES)
    ):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "retained evidence-schema-core is not the exact loaded sibling implementation",
        )
    return gate_sha256, core_sha256


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


def _capture_bundle_file_at(
    root: int,
    relative_path: str,
    *,
    maximum: int,
    capture_content: bool,
    expected_size: int | None = None,
    expected_sha256: str | None = None,
    directory_fds: dict[str, int] | None = None,
    error_code: str = "PF-EVIDENCE-BUNDLE",
) -> _CapturedBundleFile:
    """Capture one member from a retained bundle root without reopening the root."""
    checked_path = require_relative_path(relative_path, "bundle member path")
    components = checked_path.split("/")
    directory_fds = directory_fds or {}
    current: int | None = None
    descriptor: int | None = None
    try:
        if components[0] in directory_fds:
            if len(components) != 2:
                fail(
                    "PF-EVIDENCE-BUNDLE",
                    f"dedicated bundle directory member must be a direct child: "
                    f"{_diagnostic_repr(checked_path)}",
                )
            current = os.dup(directory_fds[components[0]])
            remaining_components = components[1:]
        else:
            current = os.dup(root)
            remaining_components = components
        for component in remaining_components[:-1]:
            try:
                following = os.open(
                    component,
                    os.O_RDONLY
                    | os.O_DIRECTORY
                    | os.O_CLOEXEC
                    | os.O_NOFOLLOW
                    | getattr(os, "O_NONBLOCK", 0),
                    dir_fd=current,
                )
            except OSError as exc:
                fail(
                    error_code,
                    f"cannot safely open bundle component {_diagnostic_repr(component)}: "
                    f"{exc.strerror}",
                )
            try:
                _require_secure_directory(
                    os.fstat(following),
                    f"evidence component {_diagnostic_repr(component)}",
                    final=True,
                )
            except BaseException:
                os.close(following)
                raise
            os.close(current)
            current = following
        name = remaining_components[-1]
        try:
            descriptor = os.open(
                name,
                os.O_RDONLY
                | os.O_CLOEXEC
                | os.O_NOFOLLOW
                | getattr(os, "O_NONBLOCK", 0),
                dir_fd=current,
            )
        except OSError as exc:
            fail(
                error_code,
                f"cannot safely open bundle file {_diagnostic_repr(checked_path)}: "
                f"{exc.strerror}",
            )
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.geteuid()
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) & 0o022
        ):
            fail(
                error_code,
                f"bundle file metadata mismatch: {_diagnostic_repr(checked_path)}",
            )
        if before.st_size > maximum:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"bundle member exceeds {maximum} bytes: {_diagnostic_repr(checked_path)}",
            )
        if expected_size is not None and before.st_size != expected_size:
            fail(
                error_code,
                f"bundle file size mismatched its claim: {_diagnostic_repr(checked_path)}",
            )
        digest = hashlib.sha256()
        chunks: list[bytes] | None = [] if capture_content else None
        total = 0
        while total <= maximum:
            chunk = os.read(descriptor, min(maximum + 1 - total, 128 * 1024))
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
            if chunks is not None:
                chunks.append(chunk)
        if total > maximum:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"bundle member grew beyond {maximum} bytes: {_diagnostic_repr(checked_path)}",
            )
        after = os.fstat(descriptor)
        try:
            path_after = os.stat(name, dir_fd=current, follow_symlinks=False)
        except OSError as exc:
            fail(
                error_code,
                f"cannot restat bundle file {_diagnostic_repr(checked_path)}: "
                f"{exc.strerror}",
            )
        identity = _implementation_identity(before)
        actual_sha256 = digest.hexdigest()
        if (
            total != before.st_size
            or identity != _implementation_identity(after)
            or identity != _implementation_identity(path_after)
            or (expected_sha256 is not None and actual_sha256 != expected_sha256)
        ):
            fail(
                error_code,
                f"bundle file content or identity mismatched: "
                f"{_diagnostic_repr(checked_path)}",
            )
        return _CapturedBundleFile(
            relative_path=checked_path,
            content=b"".join(chunks) if chunks is not None else None,
            metadata=before,
            sha256=actual_sha256,
            identity=identity,
        )
    except EvidenceError:
        raise
    except OSError as exc:
        fail(
            error_code,
            f"bundle file I/O failed for {_diagnostic_repr(checked_path)}: {exc.strerror}",
        )
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if current is not None:
            os.close(current)


def _read_bundle_relative_file(
    root_path: Path,
    relative_path: str,
    *,
    maximum: int,
) -> tuple[bytes, os.stat_result]:
    """Compatibility wrapper for one standalone bounded bundle-relative read."""
    root = _open_secure_directory(root_path, "BUNDLE_ROOT")
    try:
        captured = _capture_bundle_file_at(
            root,
            relative_path,
            maximum=maximum,
            capture_content=True,
        )
        if captured.content is None:
            fail("PF-EVIDENCE-BUNDLE", "bundle capture omitted requested file content")
        return captured.content, captured.metadata
    finally:
        os.close(root)


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
    captured = _capture_bundle_file_at(
        root,
        relative_path,
        maximum=MAX_BUNDLE_FILE_BYTES,
        capture_content=False,
        expected_size=expected_size,
        expected_sha256=expected_sha256,
    )
    return (captured.metadata.st_dev, captured.metadata.st_ino)


def _collect_bundle_claims(
    document: dict[str, object],
    *,
    enforce_semantic_limits: bool,
    semantic_input_keys: set[tuple[str, str]] | None = None,
) -> tuple[dict[str, tuple[int, str, bool, str | None]], str]:
    """Build the one closed claim registry and reject all limits before I/O."""
    records: dict[str, tuple[int, str, bool, str | None]] = {}
    portable_paths: dict[str, str] = {}
    selected_semantic_inputs = semantic_input_keys or set()

    def register(
        entry: object,
        *,
        semantic: bool,
        role: str | None,
    ) -> None:
        if not isinstance(entry, dict):
            fail("PF-EVIDENCE-BUNDLE", "validated bundle claim is not an object")
        checked_path = require_relative_path(entry.get("path"), "bundle claim path")
        checked_size = require_int(entry.get("size"), "bundle claim size")
        checked_digest = require_sha256(entry.get("sha256"), "bundle claim sha256")
        if checked_size > MAX_BUNDLE_FILE_BYTES:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"bundle claim exceeds {MAX_BUNDLE_FILE_BYTES} bytes: "
                f"{_diagnostic_repr(checked_path)}",
            )
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
        records[checked_path] = (checked_size, checked_digest, semantic, role)
        portable_paths[alias] = checked_path

    inputs = require_array(document["inputs"], "$.inputs")
    artifacts = require_array(document["artifacts"], "$.artifacts")
    logs = require_array(document["logs"], "$.logs")
    for entry in inputs:
        if not isinstance(entry, dict):
            fail("PF-EVIDENCE-BUNDLE", "validated input claim is not an object")
        role_value = entry.get("role")
        if not isinstance(role_value, str):
            fail("PF-EVIDENCE-BUNDLE", "validated input role is not a string")
        register(
            entry,
            semantic=(
                role_value in _SNAPSHOT_SEMANTIC_INPUT_ROLES
                or (role_value, entry["path"]) in selected_semantic_inputs
            ),
            role=role_value,
        )
    for entry in artifacts:
        if not isinstance(entry, dict):
            fail("PF-EVIDENCE-BUNDLE", "validated artifact claim is not an object")
        if entry.get("retained") is True:
            register(entry, semantic=False, role=None)
    for entry in logs:
        register(entry, semantic=True, role=None)

    if len(records) > MAX_BUNDLE_FILES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            f"bundle contains more than {MAX_BUNDLE_FILES} declared files",
        )
    total_size = sum(size for size, _, _, _ in records.values())
    if total_size > MAX_BUNDLE_TOTAL_BYTES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            f"bundle claims exceed {MAX_BUNDLE_TOTAL_BYTES} total bytes",
        )
    if enforce_semantic_limits:
        semantic_records = [
            (path, size)
            for path, (size, _, semantic, _) in records.items()
            if semantic
        ]
        oversized = [path for path, size in semantic_records if size > MAX_SNAPSHOT_FILE_BYTES]
        if oversized:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"semantic snapshot member exceeds {MAX_SNAPSHOT_FILE_BYTES} bytes: "
                f"{_diagnostic_repr(sorted(oversized)[0])}",
            )
        semantic_total = sum(size for _, size in semantic_records)
        if semantic_total > MAX_SNAPSHOT_TOTAL_BYTES:
            fail(
                "PF-EVIDENCE-BUNDLE-LIMIT",
                f"semantic snapshot exceeds {MAX_SNAPSHOT_TOTAL_BYTES} total bytes",
            )

    claim_set = {
        "inputs": document["inputs"],
        "artifacts": document["artifacts"],
        "logs": document["logs"],
    }
    claim_set_sha256 = hashlib.sha256(
        CLAIM_SET_DOMAIN + canonical_bytes(claim_set)
    ).hexdigest()
    return records, claim_set_sha256


def _open_snapshot_directory(root: int, name: str) -> tuple[int, tuple[int, ...]]:
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY
            | os.O_DIRECTORY
            | os.O_CLOEXEC
            | os.O_NOFOLLOW
            | getattr(os, "O_NONBLOCK", 0),
            dir_fd=root,
        )
    except OSError as exc:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"cannot open dedicated bundle directory {_diagnostic_repr(name)}: {exc.strerror}",
        )
    try:
        metadata = os.fstat(descriptor)
        _require_secure_directory(metadata, f"bundle {name} directory", final=True)
        pathname = os.stat(name, dir_fd=root, follow_symlinks=False)
        identity = _implementation_identity(metadata)
        if identity != _implementation_identity(pathname):
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"dedicated bundle directory identity mismatch: {_diagnostic_repr(name)}",
            )
        return descriptor, identity
    except BaseException:
        os.close(descriptor)
        raise


def _require_snapshot_directory_entries(
    descriptor: int,
    name: str,
    expected: set[str],
) -> None:
    try:
        entries = os.listdir(descriptor)
    except OSError as exc:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"cannot enumerate dedicated bundle directory {_diagnostic_repr(name)}: "
            f"{exc.strerror}",
        )
    if len(entries) > MAX_BUNDLE_FILES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            f"dedicated bundle directory {name!r} exceeds {MAX_BUNDLE_FILES} entries",
        )
    actual = set(entries)
    if len(actual) != len(entries) or actual != expected:
        missing = sorted(expected - actual)[:4]
        extra = sorted(actual - expected)[:4]
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"dedicated bundle directory {name!r} is not the exact selected-gate set "
            f"missing={[_diagnostic_repr(item) for item in missing]} "
            f"extra={[_diagnostic_repr(item) for item in extra]}",
        )


def _revalidate_snapshot_directory(
    root: int,
    descriptor: int,
    name: str,
    expected_identity: tuple[int, ...],
) -> None:
    try:
        descriptor_identity = _implementation_identity(os.fstat(descriptor))
        pathname_identity = _implementation_identity(
            os.stat(name, dir_fd=root, follow_symlinks=False)
        )
    except OSError as exc:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"cannot revalidate dedicated bundle directory {_diagnostic_repr(name)}: "
            f"{exc.strerror}",
        )
    if descriptor_identity != expected_identity or pathname_identity != expected_identity:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"dedicated bundle directory changed during snapshot: {_diagnostic_repr(name)}",
        )


def _selected_gate_directory_entries(
    selected_gate: dict[str, object],
) -> dict[str, set[str]]:
    expected = {"policies": set(), "contexts": set()}

    def add(path_value: object, directory: str, where: str) -> None:
        path = require_relative_path(path_value, where)
        components = path.split("/")
        if len(components) != 2 or components[0] != directory:
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"{where} must be a direct member of {directory!r}",
            )
        expected[directory].add(components[1])

    policies = selected_gate.get("policies")
    if not isinstance(policies, list):
        fail("PF-EVIDENCE-BUNDLE", "selected gate policies are not validated")
    for policy_index, policy_value in enumerate(policies):
        if not isinstance(policy_value, dict):
            fail("PF-EVIDENCE-BUNDLE", "selected gate policy is not an object")
        rendered = policy_value.get("renderedPolicyInput")
        probes = policy_value.get("probes")
        if not isinstance(rendered, dict) or not isinstance(probes, list):
            fail("PF-EVIDENCE-BUNDLE", "selected gate policy refs are not validated")
        add(
            rendered.get("path"),
            "policies",
            f"selectedGate.policies[{policy_index}].renderedPolicyInput.path",
        )
        for probe_index, probe_value in enumerate(probes):
            if not isinstance(probe_value, dict):
                fail("PF-EVIDENCE-BUNDLE", "selected gate probe is not an object")
            context = probe_value.get("invocationContextInput")
            receipt = probe_value.get("receiptInput")
            if not isinstance(context, dict) or not isinstance(receipt, dict):
                fail("PF-EVIDENCE-BUNDLE", "selected gate probe refs are not validated")
            prefix = f"selectedGate.policies[{policy_index}].probes[{probe_index}]"
            add(context.get("path"), "contexts", f"{prefix}.invocationContextInput.path")
            add(receipt.get("path"), "policies", f"{prefix}.receiptInput.path")
            add(probe_value.get("stdoutLog"), "policies", f"{prefix}.stdoutLog")
            add(probe_value.get("stderrLog"), "policies", f"{prefix}.stderrLog")
    return expected


def _selected_gate_semantic_input_keys(
    selected_gate: dict[str, object],
) -> dict[tuple[str, str], str]:
    """Return selected input executables/launchers that require captured bytes."""
    required_inputs = selected_gate.get("requiredInputs")
    if not isinstance(required_inputs, list):
        fail("PF-EVIDENCE-CATALOG-GATE", "selected gate inputs are not validated")
    required_by_path: dict[str, tuple[str, str]] = {}
    for reference in required_inputs:
        if not isinstance(reference, dict):
            fail("PF-EVIDENCE-CATALOG-GATE", "selected gate input is not an object")
        role = reference.get("role")
        path = reference.get("path")
        if not isinstance(role, str) or not isinstance(path, str):
            fail("PF-EVIDENCE-CATALOG-GATE", "selected gate input is not typed")
        required_by_path[path] = (role, path)

    semantic: dict[tuple[str, str], str] = {}
    command_policy = selected_gate.get("commandPolicy")
    if not isinstance(command_policy, dict):
        fail("PF-EVIDENCE-CATALOG-GATE", "selected gate command is not validated")
    command_argv = command_policy.get("argv")
    if not isinstance(command_argv, list) or not command_argv:
        fail("PF-EVIDENCE-CATALOG-GATE", "selected gate command argv is empty")
    launcher_matcher = command_argv[0]
    if isinstance(launcher_matcher, dict) and launcher_matcher.get("kind") == "run-path":
        relative = launcher_matcher.get("relative")
        if not isinstance(relative, str) or relative not in required_by_path:
            fail(
                "PF-EVIDENCE-CATALOG-GATE",
                "selected gate run-path launcher is not a required input",
            )
        semantic[required_by_path[relative]] = "PF-EVIDENCE-CATALOG-GATE"

    policies = selected_gate.get("policies")
    if not isinstance(policies, list):
        fail("PF-EVIDENCE-CATALOG-PROBES", "selected gate policies are not validated")
    for policy in policies:
        if not isinstance(policy, dict) or not isinstance(policy.get("probes"), list):
            fail("PF-EVIDENCE-CATALOG-PROBES", "selected gate probes are not validated")
        for probe in policy["probes"]:
            if not isinstance(probe, dict) or not isinstance(probe.get("command"), dict):
                fail("PF-EVIDENCE-CATALOG-PROBES", "selected gate probe is not typed")
            executable = probe["command"].get("executable")
            if not isinstance(executable, dict):
                fail("PF-EVIDENCE-CATALOG-PROBES", "probe executable is not validated")
            if executable.get("kind") != "input":
                continue
            role = executable.get("role")
            path = executable.get("path")
            if not isinstance(role, str) or not isinstance(path, str):
                fail("PF-EVIDENCE-CATALOG-PROBES", "probe input executable is not typed")
            semantic[(role, path)] = "PF-EVIDENCE-CATALOG-PROBES"
    return semantic


def _capture_development_bundle_snapshot(
    root: int,
    root_text: str,
    document: dict[str, object],
    selected_gate: dict[str, object],
    *,
    root_identity: tuple[int, ...],
    evidence_capture: _CapturedBundleFile,
    catalog_capture: _CapturedBundleFile,
) -> _DevelopmentBundleSnapshot:
    """Verify all claims once and retain only the bounded semantic member bytes."""
    semantic_input_codes = _selected_gate_semantic_input_keys(selected_gate)
    records, claim_set_sha256 = _collect_bundle_claims(
        document,
        enforce_semantic_limits=True,
        semantic_input_keys=set(semantic_input_codes),
    )
    claimed_semantic_bytes = sum(
        size for size, _, semantic, _ in records.values() if semantic
    )
    if evidence_capture.metadata.st_size + claimed_semantic_bytes > MAX_SNAPSHOT_TOTAL_BYTES:
        fail(
            "PF-EVIDENCE-BUNDLE-LIMIT",
            "preliminary evidence plus semantic snapshot members exceed "
            f"{MAX_SNAPSHOT_TOTAL_BYTES} total bytes",
        )
    for (role, path), code in semantic_input_codes.items():
        record = records.get(path)
        if record is None or record[3] != role:
            fail(code, "selected executable input is absent from the evidence claim set")
    expected_entries = _selected_gate_directory_entries(selected_gate)
    expected_paths = {
        f"{directory}/{entry}"
        for directory, entries in expected_entries.items()
        for entry in entries
    }
    missing_claims = sorted(expected_paths - set(records))
    if missing_claims:
        fail(
            "PF-EVIDENCE-BUNDLE",
            f"selected gate references an undeclared snapshot member: "
            f"{_diagnostic_repr(missing_claims[0])}",
        )
    evidence_alias = unicodedata.normalize(
        "NFC", evidence_capture.relative_path
    ).casefold()
    for claim_path in records:
        if unicodedata.normalize("NFC", claim_path).casefold() == evidence_alias:
            fail(
                "PF-EVIDENCE-BUNDLE",
                "preliminary evidence path aliases a declared bundle claim",
            )
    catalog_record = records.get(catalog_capture.relative_path)
    if catalog_record is None:
        fail("PF-EVIDENCE-CATALOG-DIGEST", "captured catalog is absent from bundle claims")
    catalog_size, catalog_sha256, _, _ = catalog_record
    if (
        catalog_capture.metadata.st_size != catalog_size
        or catalog_capture.sha256 != catalog_sha256
        or catalog_capture.content is None
    ):
        fail(
            "PF-EVIDENCE-CATALOG-DIGEST",
            "preloaded catalog does not equal its retained bundle claim",
        )

    directory_fds: dict[str, int] = {}
    directory_identities: dict[str, tuple[int, ...]] = {}
    files: dict[str, _CapturedBundleFile] = {}
    inode_paths: dict[tuple[int, int], str] = {}

    def register(captured: _CapturedBundleFile, *, evidence: bool = False) -> None:
        inode = (captured.metadata.st_dev, captured.metadata.st_ino)
        previous_path = inode_paths.get(inode)
        if previous_path is not None and previous_path != captured.relative_path:
            fail(
                "PF-EVIDENCE-BUNDLE",
                f"distinct snapshot members resolve to one inode: "
                f"{_diagnostic_repr(previous_path)} and "
                f"{_diagnostic_repr(captured.relative_path)}",
            )
        inode_paths[inode] = captured.relative_path
        if not evidence:
            if captured.relative_path in files:
                fail(
                    "PF-EVIDENCE-BUNDLE",
                    f"snapshot member captured twice: "
                    f"{_diagnostic_repr(captured.relative_path)}",
                )
            files[captured.relative_path] = captured

    register(evidence_capture, evidence=True)
    register(catalog_capture)
    try:
        for name in ("policies", "contexts"):
            descriptor, identity = _open_snapshot_directory(root, name)
            directory_fds[name] = descriptor
            directory_identities[name] = identity
            _require_snapshot_directory_entries(
                descriptor,
                name,
                expected_entries[name],
            )

        for path in sorted(records):
            if path == catalog_capture.relative_path:
                continue
            expected_size, expected_sha256, semantic, role = records[path]
            captured = _capture_bundle_file_at(
                root,
                path,
                maximum=(
                    MAX_SNAPSHOT_FILE_BYTES if semantic else MAX_BUNDLE_FILE_BYTES
                ),
                capture_content=semantic,
                expected_size=expected_size,
                expected_sha256=expected_sha256,
                directory_fds=directory_fds,
                error_code=(
                    "PF-EVIDENCE-CATALOG-DIGEST"
                    if role == "evidence-schema-core"
                    else "PF-EVIDENCE-BUNDLE"
                ),
            )
            register(captured)

        for name in ("policies", "contexts"):
            _require_snapshot_directory_entries(
                directory_fds[name],
                name,
                expected_entries[name],
            )
            _revalidate_snapshot_directory(
                root,
                directory_fds[name],
                name,
                directory_identities[name],
            )
        current_root = os.fstat(root)
        _require_secure_directory(current_root, "BUNDLE_ROOT", final=True)
        if _implementation_identity(current_root) != root_identity:
            fail("PF-EVIDENCE-BUNDLE", "bundle root changed during single snapshot")
    except EvidenceError:
        raise
    except OSError as exc:
        fail("PF-EVIDENCE-BUNDLE", f"bundle snapshot I/O failed: {exc.strerror}")
    finally:
        for descriptor in directory_fds.values():
            os.close(descriptor)

    identities = tuple(
        sorted(
            [(evidence_capture.relative_path, evidence_capture.identity)]
            + [(path, captured.identity) for path, captured in files.items()]
        )
    )
    return _DevelopmentBundleSnapshot(
        root_text=root_text,
        evidence=evidence_capture,
        files=files,
        checked_file_count=len(records),
        claim_set_sha256=claim_set_sha256,
        identities=identities,
    )


def verify_bundle(document: dict[str, object], root_path: Path) -> int:
    """Verify referenced bundle files; this is not gate-catalog attestation."""
    document = validate_evidence(document)
    records, _ = _collect_bundle_claims(
        document,
        enforce_semantic_limits=False,
    )

    root = _open_secure_directory(root_path, "ROOT")
    try:
        identities: dict[tuple[int, int], str] = {}
        for path in sorted(records):
            expected_size, expected_digest, _, _ = records[path]
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
            "startedUtc": "2026-07-15T00:00:00Z",
            "endedUtc": "2026-07-15T00:00:00Z",
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


def _sample_typed_catalog_document() -> dict[str, object]:
    """Return the smallest complete generic-reader typed-binding fixture."""
    document = _sample_document()
    policy = document["sandboxPolicies"][0]  # type: ignore[index]
    probe = policy["probes"][0]  # type: ignore[index]
    document["sandboxPolicies"] = [policy]
    policy["probes"] = [probe]  # type: ignore[index]
    catalog_ref = {
        "schema": "proof-forge.gate-catalog.v1",
        "id": "development-alpha",
        "version": "1.0.0",
        "contentSha256": "d" * 64,
        "catalogDigest": "e" * 64,
    }
    document["gateCatalog"] = catalog_ref
    document["runContextInput"] = {
        "role": "clean-room-run-context",
        "path": "run-context.json",
    }
    document["hostAttestation"]["observationInput"] = {  # type: ignore[index]
        "role": "host-observation",
        "path": "host-observation.json",
    }
    policy["renderedPolicyInput"] = {  # type: ignore[index]
        "role": "sandbox-rendered-policy",
        "path": "policies/core.sb",
    }
    probe["receipt"] = {  # type: ignore[index]
        "invocationContextInput": {
            "role": "sandbox-invocation-context",
            "path": "contexts/sandbox-core-network-denied.json",
        },
        "role": "sandbox-invocation-receipt",
        "path": "policies/sandbox-core-network-denied.receipt.json",
        "stdoutLog": "build/logs/gate.stdout",
        "stderrLog": "build/logs/gate.stderr",
    }
    document["inputs"].extend([  # type: ignore[union-attr]
        {
            "role": "clean-room-run-context",
            "path": "run-context.json",
            "sha256": "1" * 64,
            "size": 1,
        },
        {
            "role": "gate-catalog",
            "path": "catalog.json",
            "sha256": catalog_ref["contentSha256"],
            "size": 1,
        },
        {
            "role": "host-observation",
            "path": "host-observation.json",
            "sha256": document["hostAttestation"]["observationSha256"],  # type: ignore[index]
            "size": 1,
        },
        {
            "role": "sandbox-invocation-context",
            "path": "contexts/sandbox-core-network-denied.json",
            "sha256": "2" * 64,
            "size": 1,
        },
        {
            "role": "sandbox-invocation-receipt",
            "path": "policies/sandbox-core-network-denied.receipt.json",
            "sha256": "3" * 64,
            "size": 1,
        },
        {
            "role": "sandbox-policy-renderer",
            "path": "scripts/sandbox_policy.py",
            "sha256": "4" * 64,
            "size": 1,
        },
        {
            "role": "sandbox-rendered-policy",
            "path": "policies/core.sb",
            "sha256": policy["renderedSha256"],  # type: ignore[index]
            "size": 1,
        },
    ])
    document["inputs"].sort(key=lambda entry: (entry["role"], entry["path"]))  # type: ignore[union-attr,index]
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


def _self_test_core_routing() -> None:
    """Prove the CLI validation surface is the exact sibling core surface."""
    for name in _EVIDENCE_V1_CORE_ROUTED:
        if globals().get(name) is not _EVIDENCE_V1_CORE.__dict__.get(name):
            fail(
                "PF-EVIDENCE-SELF-TEST",
                f"gate evidence symbol is not routed through evidence_v1_core: {name}",
            )


def _self_test_literal_dict_keys() -> None:
    """Reject duplicate string keys hidden by Python dict-literal semantics."""
    source_paths = (
        Path(__file__).resolve(strict=True),
        Path(_EVIDENCE_V1_CORE.__file__).resolve(strict=True),
    )
    for source_path in source_paths:
        try:
            source = source_path.read_text(encoding="utf-8")
            tree = ast.parse(source, filename=str(source_path))
        except (OSError, SyntaxError, UnicodeError) as exc:
            fail(
                "PF-EVIDENCE-SELF-TEST",
                f"cannot parse evidence source for duplicate keys: {exc}",
            )
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
                        f"duplicate literal dict key at {source_path.name}:"
                        f"{key.lineno}: {_diagnostic_repr(key.value)}",
                    )
                seen.add(key.value)


def self_test() -> None:
    _self_test_core_routing()
    _self_test_literal_dict_keys()
    development = _sample_document()
    formal = _sample_document(formal=True)
    typed = _sample_typed_catalog_document()
    validate_evidence(development)
    validate_evidence(formal)
    validate_evidence(typed)
    typed_encoded = canonical_bytes(typed)
    if canonical_bytes(validate_evidence(decode_json(typed_encoded))) != typed_encoded:
        fail("PF-EVIDENCE-SELF-TEST", "typed binding canonical round trip changed bytes")

    typed_without_catalog = copy.deepcopy(typed)
    typed_without_catalog.pop("gateCatalog")
    _expect_rejected("typed fields without gate catalog", typed_without_catalog)

    for label, mutator in (
        (
            "legacy root run-context extension",
            lambda candidate: candidate.update(
                {"runContextInput": copy.deepcopy(typed["runContextInput"])}
            ),
        ),
        (
            "legacy host observation extension",
            lambda candidate: candidate["hostAttestation"].update(  # type: ignore[union-attr]
                {
                    "observationInput": copy.deepcopy(
                        typed["hostAttestation"]["observationInput"]  # type: ignore[index]
                    )
                }
            ),
        ),
        (
            "legacy rendered-policy extension",
            lambda candidate: candidate["sandboxPolicies"][0].update(  # type: ignore[index,union-attr]
                {
                    "renderedPolicyInput": copy.deepcopy(
                        typed["sandboxPolicies"][0]["renderedPolicyInput"]  # type: ignore[index]
                    )
                }
            ),
        ),
        (
            "legacy probe-receipt extension",
            lambda candidate: candidate["sandboxPolicies"][0]["probes"][0].update(  # type: ignore[index,union-attr]
                {
                    "receipt": copy.deepcopy(
                        typed["sandboxPolicies"][0]["probes"][0]["receipt"]  # type: ignore[index]
                    )
                }
            ),
        ),
    ):
        candidate = copy.deepcopy(development)
        mutator(candidate)
        _expect_rejected(label, candidate)

    for label, path in (
        ("catalog without run-context binding", ("runContextInput",)),
        (
            "catalog without host-observation binding",
            ("hostAttestation", "observationInput"),
        ),
        (
            "catalog without rendered-policy binding",
            ("sandboxPolicies", "0", "renderedPolicyInput"),
        ),
        (
            "catalog without probe-receipt binding",
            ("sandboxPolicies", "0", "probes", "0", "receipt"),
        ),
    ):
        candidate = copy.deepcopy(typed)
        cursor: object = candidate
        for component in path[:-1]:
            cursor = cursor[int(component)] if component.isdigit() else cursor[component]  # type: ignore[index]
        cursor.pop(path[-1])  # type: ignore[union-attr]
        _expect_rejected(label, candidate)

    for label, field, replacement in (
        ("wrong catalog schema", "schema", "proof-forge.gate-catalog.v2"),
        ("catalog SemVer leading zero", "version", "01.0.0"),
        ("catalog SemVer range", "version", "^1.0.0"),
        ("malformed catalog content digest", "contentSha256", "sha256:" + "0" * 64),
        ("malformed catalog domain digest", "catalogDigest", "0" * 63),
    ):
        candidate = copy.deepcopy(typed)
        candidate["gateCatalog"][field] = replacement  # type: ignore[index]
        _expect_rejected(label, candidate)

    wrong_run_role = copy.deepcopy(typed)
    wrong_run_role["runContextInput"]["role"] = "candidate-archive"  # type: ignore[index]
    _expect_rejected("wrong run-context role", wrong_run_role)
    wrong_run_path = copy.deepcopy(typed)
    wrong_run_path["runContextInput"]["path"] = "missing-run-context.json"  # type: ignore[index]
    _expect_rejected("dangling run-context path", wrong_run_path)
    for label, path, replacement in (
        (
            "wrong host-observation role",
            ("hostAttestation", "observationInput", "role"),
            "candidate-archive",
        ),
        (
            "dangling host-observation path",
            ("hostAttestation", "observationInput", "path"),
            "missing-host-observation.json",
        ),
        (
            "wrong rendered-policy role",
            ("sandboxPolicies", "0", "renderedPolicyInput", "role"),
            "candidate-archive",
        ),
        (
            "dangling rendered-policy path",
            ("sandboxPolicies", "0", "renderedPolicyInput", "path"),
            "policies/missing.sb",
        ),
        (
            "wrong invocation-context role",
            (
                "sandboxPolicies",
                "0",
                "probes",
                "0",
                "receipt",
                "invocationContextInput",
                "role",
            ),
            "candidate-archive",
        ),
        (
            "dangling invocation-context path",
            (
                "sandboxPolicies",
                "0",
                "probes",
                "0",
                "receipt",
                "invocationContextInput",
                "path",
            ),
            "contexts/missing.json",
        ),
        (
            "wrong invocation-receipt role",
            ("sandboxPolicies", "0", "probes", "0", "receipt", "role"),
            "candidate-archive",
        ),
        (
            "dangling invocation-receipt path",
            ("sandboxPolicies", "0", "probes", "0", "receipt", "path"),
            "policies/missing.receipt.json",
        ),
    ):
        candidate = copy.deepcopy(typed)
        cursor = candidate
        for component in path[:-1]:
            cursor = cursor[int(component)] if component.isdigit() else cursor[component]  # type: ignore[index]
        cursor[path[-1]] = replacement  # type: ignore[index]
        _expect_rejected(label, candidate)
    unknown_receipt_field = copy.deepcopy(typed)
    unknown_receipt_field["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
        "unknown"
    ] = True
    _expect_rejected("unknown probe receipt field", unknown_receipt_field)

    for label, role in (
        ("missing gate-catalog claim", "gate-catalog"),
        ("missing clean-room run-context claim", "clean-room-run-context"),
        ("missing host-observation claim", "host-observation"),
        ("missing sandbox policy renderer claim", "sandbox-policy-renderer"),
    ):
        candidate = copy.deepcopy(typed)
        candidate["inputs"] = [  # type: ignore[index]
            entry for entry in candidate["inputs"] if entry["role"] != role  # type: ignore[index]
        ]
        _expect_rejected(label, candidate)

    duplicate_catalog_claim = copy.deepcopy(typed)
    duplicate_catalog_claim["inputs"].append(  # type: ignore[union-attr]
        {
            "role": "gate-catalog",
            "path": "catalog-copy.json",
            "sha256": duplicate_catalog_claim["gateCatalog"]["contentSha256"],  # type: ignore[index]
            "size": 1,
        }
    )
    duplicate_catalog_claim["inputs"].sort(  # type: ignore[union-attr]
        key=lambda entry: (entry["role"], entry["path"])
    )
    _expect_rejected("duplicate gate-catalog role claim", duplicate_catalog_claim)

    for label, role, path in (
        (
            "duplicate clean-room run-context role claim",
            "clean-room-run-context",
            "run-context-copy.json",
        ),
        (
            "duplicate host-observation role claim",
            "host-observation",
            "host-observation-copy.json",
        ),
        (
            "duplicate sandbox policy renderer role claim",
            "sandbox-policy-renderer",
            "scripts/sandbox_policy_copy.py",
        ),
    ):
        candidate = copy.deepcopy(typed)
        candidate["inputs"].append(  # type: ignore[union-attr]
            {"role": role, "path": path, "sha256": "9" * 64, "size": 1}
        )
        candidate["inputs"].sort(  # type: ignore[union-attr]
            key=lambda entry: (entry["role"], entry["path"])
        )
        _expect_rejected(label, candidate)

    for label, role in (
        ("gate-catalog claim hash mismatch", "gate-catalog"),
        ("host-observation claim hash mismatch", "host-observation"),
        ("rendered-policy claim hash mismatch", "sandbox-rendered-policy"),
    ):
        candidate = copy.deepcopy(typed)
        next(entry for entry in candidate["inputs"] if entry["role"] == role)[  # type: ignore[index]
            "sha256"
        ] = "0" * 64
        _expect_rejected(label, candidate)

    dangling_context = copy.deepcopy(typed)
    dangling_context["inputs"].append(  # type: ignore[union-attr]
        {
            "role": "sandbox-invocation-context",
            "path": "contexts/dangling.json",
            "sha256": "0" * 64,
            "size": 1,
        }
    )
    dangling_context["inputs"].sort(  # type: ignore[union-attr]
        key=lambda entry: (entry["role"], entry["path"])
    )
    _expect_rejected("dangling invocation-context claim", dangling_context)
    for label, role, path in (
        (
            "dangling rendered-policy claim",
            "sandbox-rendered-policy",
            "policies/dangling.sb",
        ),
        (
            "dangling invocation-receipt claim",
            "sandbox-invocation-receipt",
            "policies/dangling.receipt.json",
        ),
    ):
        candidate = copy.deepcopy(typed)
        candidate["inputs"].append(  # type: ignore[union-attr]
            {"role": role, "path": path, "sha256": "9" * 64, "size": 1}
        )
        candidate["inputs"].sort(  # type: ignore[union-attr]
            key=lambda entry: (entry["role"], entry["path"])
        )
        _expect_rejected(label, candidate)

    missing_probe_log = copy.deepcopy(typed)
    missing_probe_log["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
        "stdoutLog"
    ] = "build/logs/missing.stdout"
    _expect_rejected("probe receipt missing stdout log", missing_probe_log)

    two_probe = copy.deepcopy(typed)
    second_probe = copy.deepcopy(two_probe["sandboxPolicies"][0]["probes"][0])  # type: ignore[index]
    second_probe["id"] = "second-probe"
    second_probe["receipt"] = {  # type: ignore[index]
        "invocationContextInput": {
            "role": "sandbox-invocation-context",
            "path": "contexts/sandbox-core-second-probe.json",
        },
        "role": "sandbox-invocation-receipt",
        "path": "policies/sandbox-core-second-probe.receipt.json",
        "stdoutLog": "build/logs/second-probe.stdout",
        "stderrLog": "build/logs/second-probe.stderr",
    }
    two_probe["sandboxPolicies"][0]["probes"].append(second_probe)  # type: ignore[index]
    two_probe["inputs"].extend(  # type: ignore[union-attr]
        [
            {
                "role": "sandbox-invocation-context",
                "path": "contexts/sandbox-core-second-probe.json",
                "sha256": "5" * 64,
                "size": 1,
            },
            {
                "role": "sandbox-invocation-receipt",
                "path": "policies/sandbox-core-second-probe.receipt.json",
                "sha256": "6" * 64,
                "size": 1,
            },
        ]
    )
    two_probe["inputs"].sort(  # type: ignore[union-attr]
        key=lambda entry: (entry["role"], entry["path"])
    )
    two_probe["logs"].extend(  # type: ignore[union-attr]
        [
            {
                "path": "build/logs/second-probe.stderr",
                "sha256": "7" * 64,
                "size": 0,
                "truncated": False,
                "privateDataScan": "not-run",
            },
            {
                "path": "build/logs/second-probe.stdout",
                "sha256": "8" * 64,
                "size": 0,
                "truncated": False,
                "privateDataScan": "not-run",
            },
        ]
    )
    two_probe["logs"].sort(key=lambda entry: entry["path"])  # type: ignore[union-attr]
    validate_evidence(two_probe)

    two_policy = copy.deepcopy(two_probe)
    first_policy = two_policy["sandboxPolicies"][0]  # type: ignore[index]
    second_policy = copy.deepcopy(first_policy)
    second_policy["id"] = "second-policy"
    second_policy["renderedSha256"] = "9" * 64
    second_policy["renderedPolicyInput"] = {
        "role": "sandbox-rendered-policy",
        "path": "policies/second.sb",
    }
    second_policy["probes"] = [first_policy["probes"].pop()]  # type: ignore[index]
    two_policy["sandboxPolicies"].append(second_policy)  # type: ignore[union-attr]
    two_policy["inputs"].append(  # type: ignore[union-attr]
        {
            "role": "sandbox-rendered-policy",
            "path": "policies/second.sb",
            "sha256": "9" * 64,
            "size": 1,
        }
    )
    two_policy["inputs"].sort(  # type: ignore[union-attr]
        key=lambda entry: (entry["role"], entry["path"])
    )
    validate_evidence(two_policy)

    reused_rendered_cross_policy = copy.deepcopy(two_policy)
    reused_rendered_cross_policy["sandboxPolicies"][1][  # type: ignore[index]
        "renderedPolicyInput"
    ] = copy.deepcopy(
        reused_rendered_cross_policy["sandboxPolicies"][0][  # type: ignore[index]
            "renderedPolicyInput"
        ]
    )
    _expect_rejected(
        "rendered-policy claim reused across policies",
        reused_rendered_cross_policy,
    )
    reused_context_cross_policy = copy.deepcopy(two_policy)
    reused_context_cross_policy["sandboxPolicies"][1]["probes"][0]["receipt"][  # type: ignore[index]
        "invocationContextInput"
    ] = copy.deepcopy(
        reused_context_cross_policy["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
            "invocationContextInput"
        ]
    )
    _expect_rejected(
        "invocation-context claim reused across policies",
        reused_context_cross_policy,
    )
    reused_receipt_cross_policy = copy.deepcopy(two_policy)
    reused_receipt_cross_policy["sandboxPolicies"][1]["probes"][0]["receipt"][  # type: ignore[index]
        "path"
    ] = reused_receipt_cross_policy["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
        "path"
    ]
    _expect_rejected(
        "invocation-receipt claim reused across policies",
        reused_receipt_cross_policy,
    )
    reused_stream_cross_policy = copy.deepcopy(two_policy)
    reused_stream_cross_policy["sandboxPolicies"][1]["probes"][0]["receipt"][  # type: ignore[index]
        "stdoutLog"
    ] = reused_stream_cross_policy["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
        "stdoutLog"
    ]
    _expect_rejected(
        "sandbox stream reused across policies",
        reused_stream_cross_policy,
    )

    reused_context = copy.deepcopy(two_probe)
    reused_context["sandboxPolicies"][0]["probes"][1]["receipt"][  # type: ignore[index]
        "invocationContextInput"
    ] = copy.deepcopy(
        reused_context["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
            "invocationContextInput"
        ]
    )
    _expect_rejected("invocation-context claim reused across probes", reused_context)
    reused_receipt = copy.deepcopy(two_probe)
    reused_receipt["sandboxPolicies"][0]["probes"][1]["receipt"]["path"] = (  # type: ignore[index]
        reused_receipt["sandboxPolicies"][0]["probes"][0]["receipt"]["path"]  # type: ignore[index]
    )
    _expect_rejected("receipt claim reused across probes", reused_receipt)
    reused_stream = copy.deepcopy(two_probe)
    reused_stream["sandboxPolicies"][0]["probes"][1]["receipt"][  # type: ignore[index]
        "stdoutLog"
    ] = reused_stream["sandboxPolicies"][0]["probes"][0]["receipt"][  # type: ignore[index]
        "stdoutLog"
    ]
    _expect_rejected("stream log reused across probes", reused_stream)

    fractional_utc = copy.deepcopy(development)
    fractional_utc["command"]["endedUtc"] = "2026-07-15T00:00:00.125Z"  # type: ignore[index]
    _expect_rejected("fractional UTC wire form", fractional_utc)
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
    finalizer_parser = subparsers.add_parser(
        "finalize-development",
        help="finalize one development gate against an exact retained catalog bundle",
    )
    finalizer_parser.add_argument("--executing-source")
    finalizer_parser.add_argument("--catalog", required=True)
    finalizer_parser.add_argument("--catalog-sha256", required=True)
    finalizer_parser.add_argument("--catalog-digest", required=True)
    finalizer_parser.add_argument("--run-binding-sha256", required=True)
    finalizer_parser.add_argument("--evidence", required=True)
    finalizer_parser.add_argument("--bundle-root", required=True)
    finalizer_parser.add_argument("--output", required=True)
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
        elif arguments.command == "finalize-development":
            bundle_root = _normalized_cli_directory(arguments.bundle_root, "BUNDLE_ROOT")
            if not bundle_root.is_absolute():
                fail("PF-EVIDENCE-PATH", "BUNDLE_ROOT must be an absolute canonical path")
            bundle_root_text = os.fspath(bundle_root)
            evidence_relative = require_relative_path(arguments.evidence, "EVIDENCE")
            root = _open_secure_directory(bundle_root, "BUNDLE_ROOT")
            try:
                root_identity = _implementation_identity(os.fstat(root))
                evidence_capture = _capture_bundle_file_at(
                    root,
                    evidence_relative,
                    maximum=MAX_INPUT_BYTES,
                    capture_content=True,
                )
                evidence_bytes = evidence_capture.content
                if evidence_bytes is None:
                    fail("PF-EVIDENCE-BUNDLE", "preliminary evidence capture omitted bytes")
                evidence_value = decode_json(evidence_bytes)
                document = validate_evidence(evidence_value)
                if canonical_bytes(document) != evidence_bytes:
                    fail(
                        "PF-EVIDENCE-NONCANONICAL",
                        "evidence bytes are not canonical ASCII-key JSON",
                    )
                _require_development_publish(document)
                _require_bound_development_execution(arguments.executing_source)
                expected_content_sha256 = _require_catalog_cli_sha256(
                    arguments.catalog_sha256,
                    "CATALOG_SHA256",
                )
                expected_catalog_digest = _require_catalog_cli_sha256(
                    arguments.catalog_digest,
                    "CATALOG_DIGEST",
                )
                _require_catalog_cli_sha256(
                    arguments.run_binding_sha256,
                    "RUN_BINDING_SHA256",
                )
                catalog_relative = require_relative_path(arguments.catalog, "CATALOG")
                catalog_claim = _require_single_input_claim(
                    document,
                    "gate-catalog",
                    code="PF-EVIDENCE-CATALOG-DIGEST",
                )
                if catalog_claim.get("path") != catalog_relative:
                    fail(
                        "PF-EVIDENCE-CATALOG-DIGEST",
                        "--catalog must exactly equal the evidence gate-catalog input path",
                    )
                catalog_capture = _capture_bundle_file_at(
                    root,
                    catalog_relative,
                    maximum=MAX_INPUT_BYTES,
                    capture_content=True,
                )
                catalog_bytes = catalog_capture.content
                if catalog_bytes is None:
                    fail("PF-EVIDENCE-BUNDLE", "catalog capture omitted bytes")
                catalog = _parse_development_catalog(catalog_bytes)
                _join_development_catalog_identity(
                    document,
                    catalog,
                    catalog_bytes,
                    catalog_capture.metadata,
                    catalog_relative=catalog_relative,
                    expected_content_sha256=expected_content_sha256,
                    expected_catalog_digest=expected_catalog_digest,
                )
                selected_gate = _select_development_catalog_gate(document, catalog)
                snapshot = _capture_development_bundle_snapshot(
                    root,
                    bundle_root_text,
                    document,
                    selected_gate,
                    root_identity=root_identity,
                    evidence_capture=evidence_capture,
                    catalog_capture=catalog_capture,
                )
            finally:
                os.close(root)
            _join_development_implementation_closure(
                document,
                catalog,
                snapshot,
                arguments.executing_source,
            )
            _join_development_candidate_host(document, selected_gate)
            fail(
                "PF-EVIDENCE-CATALOG-POLICIES",
                "catalog schema, identity, selected gate, implementation closure, and "
                "candidate/host static bindings verified; the context/policy/receipt "
                "evaluator is not implemented by this slice",
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
