#!/usr/bin/env python3
"""Pure identity primitives for the candidate-bound supply-chain pipeline.

This module is the first pre-acceptance implementation slice for TASK-D0-08.
It deliberately performs no filesystem publication and does not implement the
inventory, runtime-closure, CycloneDX, SPDX, or release-binding validators.
Those layers may consume these primitives, but this module alone is not a
TST-SBOM-002 completion claim.
"""

from __future__ import annotations

import hashlib
import hmac
import importlib.util
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import NoReturn


MAX_JSON_INPUT_BYTES = 16_777_216
MAX_SAFE_INTEGER = (1 << 53) - 1

TOOL_LOCK_DOMAIN = "proof-forge.toolchains.v2"
COMPONENT_DOMAIN = "proof-forge.supply-chain-component.v1"

DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}")
DOMAIN_RE = re.compile(
    r"[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*"
)

COMPONENT_PREIMAGE_FIELDS = frozenset(
    {
        "id",
        "kind",
        "name",
        "version",
        "supplier",
        "source",
        "content",
        "licenseSpdx",
        "licenseTextComponentIds",
        "redistributable",
        "dependencies",
    }
)


class SupplyChainError(RuntimeError):
    """Stable fail-closed error carrying one SPEC-TOOL-001 error family."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


def fail(code: str, detail: str) -> NoReturn:
    raise SupplyChainError(code, detail)


@dataclass(frozen=True)
class ToolLockIdentity:
    """The distinct structured and retained-byte identities of Tool Lock v2."""

    tool_lock_v2_digest: str
    toolchain_lock_sha256: str


@dataclass(frozen=True)
class ComponentIdentity:
    """Identity fields derived from an already validated resolved component."""

    component_digest: str
    bom_ref: str


@dataclass(frozen=True)
class _IntegerToken:
    text: str


@dataclass(frozen=True)
class _NonIntegerNumberToken:
    text: str


@dataclass(frozen=True)
class _NonJsonConstantToken:
    text: str


def _require_scalar_string(value: object, where: str, code: str) -> str:
    if type(value) is not str:
        fail(code, f"{where} must be a Unicode scalar string")
    assert isinstance(value, str)
    if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
        fail(code, f"{where} contains a lone surrogate")
    return value


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        checked = _require_scalar_string(key, "JSON object key", "PF-SBOM-JSON")
        if checked in result:
            fail("PF-SBOM-JSON", f"duplicate JSON object key {checked!r}")
        result[checked] = value
    return result


def _parse_integer_token(text: str) -> _IntegerToken:
    return _IntegerToken(text)


def _parse_non_integer_number_token(text: str) -> _NonIntegerNumberToken:
    return _NonIntegerNumberToken(text)


def _parse_non_json_constant_token(text: str) -> _NonJsonConstantToken:
    return _NonJsonConstantToken(text)


def _snapshot_json_tree(value: object, code: str, active: set[int]) -> object:
    """Create a private JSON-data snapshot and reject mutation/cycles."""

    if type(value) is _IntegerToken:
        assert isinstance(value, _IntegerToken)
        text = value.text
        if text == "-0":
            fail("PF-SBOM-SCHEMA", "negative zero is outside the PF-JCS profile")
        digits = text[1:] if text.startswith("-") else text
        maximum = str(MAX_SAFE_INTEGER)
        if (
            len(digits) > len(maximum)
            or (len(digits) == len(maximum) and digits > maximum)
        ):
            fail(
                "PF-SBOM-SCHEMA",
                "JSON integer exceeds the signed I-JSON safe range",
            )
        return int(text, 10)
    if type(value) is _NonIntegerNumberToken:
        assert isinstance(value, _NonIntegerNumberToken)
        fail(
            "PF-SBOM-SCHEMA",
            f"forbidden non-integer JSON number {value.text!r}",
        )
    if type(value) is _NonJsonConstantToken:
        assert isinstance(value, _NonJsonConstantToken)
        fail("PF-SBOM-JSON", f"forbidden non-JSON constant {value.text!r}")
    if value is None or type(value) is bool:
        return value
    if type(value) is int:
        assert isinstance(value, int)
        if abs(value) > MAX_SAFE_INTEGER:
            fail(code, "JSON integer exceeds the signed I-JSON safe range")
        return value
    if type(value) is str:
        return _require_scalar_string(value, "JSON string", code)
    if type(value) is list:
        assert isinstance(value, list)
        identity = id(value)
        if identity in active:
            fail(code, "JSON value contains a cycle")
        active.add(identity)
        try:
            try:
                items = tuple(value)
            except RuntimeError:
                fail(code, "JSON array changed while being snapshotted")
            return [_snapshot_json_tree(item, code, active) for item in items]
        finally:
            active.remove(identity)
    if type(value) is dict:
        assert isinstance(value, dict)
        identity = id(value)
        if identity in active:
            fail(code, "JSON value contains a cycle")
        active.add(identity)
        try:
            try:
                items = tuple(value.items())
            except RuntimeError:
                fail(code, "JSON object changed while being snapshotted")
            result: dict[str, object] = {}
            for key, item in items:
                checked = _require_scalar_string(key, "JSON object key", code)
                result[checked] = _snapshot_json_tree(item, code, active)
            return result
        finally:
            active.remove(identity)
    fail(code, f"value of type {type(value).__name__} is outside PF-JCS")


def decode_json_document(data: bytes) -> object:
    """Decode bounded JSON while rejecting duplicates and non-PF-JCS scalars.

    Input layout need not itself be canonical.  Schema owners validate the
    decoded object and canonical_pf_jcs supplies the structured digest bytes.
    """

    if type(data) is not bytes:
        fail("PF-SBOM-JSON", "JSON input must be exact bytes")
    if len(data) > MAX_JSON_INPUT_BYTES:
        fail("PF-SBOM-LIMIT", "JSON input exceeds 16,777,216 bytes")
    if data.startswith(b"\xef\xbb\xbf"):
        fail("PF-SBOM-JSON", "UTF-8 BOM is forbidden")
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        fail("PF-SBOM-JSON", "JSON input is not valid UTF-8")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_int=_parse_integer_token,
            parse_float=_parse_non_integer_number_token,
            parse_constant=_parse_non_json_constant_token,
        )
    except SupplyChainError:
        raise
    except (json.JSONDecodeError, RecursionError, ValueError):
        fail("PF-SBOM-JSON", "JSON input is malformed")
    try:
        return _snapshot_json_tree(value, "PF-SBOM-JSON", set())
    except RecursionError:
        fail("PF-SBOM-JSON", "JSON input nesting is unsupported")


def _utf16_sort_key(value: str) -> bytes:
    _require_scalar_string(value, "JSON object key", "PF-SBOM-SCHEMA")
    return value.encode("utf-16-be", errors="strict")


def _render_string(value: str) -> bytes:
    _require_scalar_string(value, "JSON string", "PF-SBOM-SCHEMA")
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        fail("PF-SBOM-SCHEMA", "cannot encode PF-JCS string")


def _render_pf_jcs(value: object, active: set[int]) -> bytes:
    if value is None:
        return b"null"
    if type(value) is bool:
        return b"true" if value else b"false"
    if type(value) is int:
        assert isinstance(value, int)
        if abs(value) > MAX_SAFE_INTEGER:
            fail("PF-SBOM-SCHEMA", "PF-JCS integer exceeds the safe range")
        return str(value).encode("ascii")
    if type(value) is str:
        assert isinstance(value, str)
        return _render_string(value)
    if type(value) is list:
        assert isinstance(value, list)
        identity = id(value)
        if identity in active:
            fail("PF-SBOM-SCHEMA", "PF-JCS value contains a cycle")
        active.add(identity)
        try:
            return b"[" + b",".join(
                _render_pf_jcs(item, active) for item in value
            ) + b"]"
        finally:
            active.remove(identity)
    if type(value) is dict:
        assert isinstance(value, dict)
        identity = id(value)
        if identity in active:
            fail("PF-SBOM-SCHEMA", "PF-JCS value contains a cycle")
        active.add(identity)
        try:
            keys: list[str] = []
            for key in value:
                keys.append(
                    _require_scalar_string(
                        key,
                        "JSON object key",
                        "PF-SBOM-SCHEMA",
                    )
                )
            keys.sort(key=_utf16_sort_key)
            fields = (
                _render_string(key) + b":" + _render_pf_jcs(value[key], active)
                for key in keys
            )
            return b"{" + b",".join(fields) + b"}"
        finally:
            active.remove(identity)
    fail(
        "PF-SBOM-SCHEMA",
        f"value of type {type(value).__name__} is outside PF-JCS",
    )


def _canonical_pf_jcs_snapshot(value: object) -> tuple[object, bytes]:
    try:
        snapshot = _snapshot_json_tree(value, "PF-SBOM-SCHEMA", set())
        encoded = _render_pf_jcs(snapshot, set())
    except RecursionError:
        fail("PF-SBOM-SCHEMA", "PF-JCS value nesting is unsupported")
    return snapshot, encoded


def canonical_pf_jcs(value: object) -> bytes:
    """Encode restricted PF-JCS v1 with UTF-16 key ordering.

    This pure codec does not guess a schema-specific output limit.  JSON input
    size is enforced by decode_json_document; closure/BOM/binding publishers
    must apply their distinct sidecar and aggregate maxima before publication.
    """

    return _canonical_pf_jcs_snapshot(value)[1]


def _require_domain(value: object) -> str:
    if type(value) is not str or DOMAIN_RE.fullmatch(value) is None:
        fail("PF-SBOM-SCHEMA", "digest domain is not a canonical profile-style ID")
    assert isinstance(value, str)
    if len(value.encode("ascii")) > 127:
        fail("PF-SBOM-SCHEMA", "digest domain exceeds 127 bytes")
    return value


def _require_digest_wire(value: object, code: str, where: str) -> str:
    if type(value) is not str or DIGEST_RE.fullmatch(value) is None:
        fail(code, f"{where} must be sha256:<64 lowercase hex>")
    assert isinstance(value, str)
    return value


def raw_sha256(data: bytes) -> str:
    if type(data) is not bytes:
        fail("PF-SBOM-SCHEMA", "SHA-256 input must be exact bytes")
    return "sha256:" + hashlib.sha256(data).hexdigest()


def domain_digest(domain: str, canonical_bytes: bytes) -> str:
    """Hash already-canonical bytes in a schema-owned NUL-separated domain."""

    checked_domain = _require_domain(domain)
    if type(canonical_bytes) is not bytes:
        fail("PF-SBOM-SCHEMA", "domain digest input must be exact bytes")
    digest = hashlib.sha256(
        checked_domain.encode("ascii") + b"\x00" + canonical_bytes
    ).hexdigest()
    return "sha256:" + digest


_TOOLCHAIN_ASSETS_MODULE: ModuleType | None = None


def _require_toolchain_assets_abi(module: ModuleType) -> ModuleType:
    if not callable(getattr(module, "validate_tool_lock", None)):
        fail("PF-SBOM-SCHEMA", "authoritative Tool Lock validator API is missing")
    asset_error = getattr(module, "AssetError", None)
    if not isinstance(asset_error, type) or not issubclass(asset_error, Exception):
        fail("PF-SBOM-SCHEMA", "authoritative Tool Lock error type is missing")
    closure_error = getattr(module, "ToolLockClosureError", None)
    if (
        not isinstance(closure_error, type)
        or not issubclass(closure_error, asset_error)
    ):
        fail("PF-SBOM-SCHEMA", "authoritative Tool Lock closure error is missing")
    return module


def _authoritative_toolchain_assets() -> ModuleType:
    global _TOOLCHAIN_ASSETS_MODULE
    if _TOOLCHAIN_ASSETS_MODULE is not None:
        return _require_toolchain_assets_abi(_TOOLCHAIN_ASSETS_MODULE)
    path = Path(__file__).resolve().with_name("toolchain_assets.py")
    spec = importlib.util.spec_from_file_location(
        "_proof_forge_supply_chain_toolchain_assets",
        path,
    )
    if spec is None or spec.loader is None:
        fail("PF-SBOM-SCHEMA", "authoritative Tool Lock validator is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        fail("PF-SBOM-SCHEMA", "authoritative Tool Lock validator failed to load")
    _TOOLCHAIN_ASSETS_MODULE = _require_toolchain_assets_abi(module)
    return _TOOLCHAIN_ASSETS_MODULE


def _validate_tool_lock(value: object) -> dict[str, object]:
    if type(value) is not dict:
        fail("PF-SBOM-SCHEMA", "Tool Lock v2 root must be an object")
    assert isinstance(value, dict)
    module = _authoritative_toolchain_assets()
    asset_error = getattr(module, "AssetError")
    closure_error = getattr(module, "ToolLockClosureError")
    before = canonical_pf_jcs(value)
    classification: str | None = None
    detail = ""
    validated: object = None
    try:
        validated = module.validate_tool_lock(value)
    except closure_error as error:
        classification = "PF-SBOM-CLOSURE"
        detail = f"invalid Tool Lock v2 closure: {error}"
    except asset_error as error:
        classification = "PF-SBOM-SCHEMA"
        detail = f"invalid Tool Lock v2: {error}"
    except Exception:
        classification = "PF-SBOM-SCHEMA"
        detail = "Tool Lock v2 validation failed closed"
    after = canonical_pf_jcs(value)
    if not hmac.compare_digest(before, after):
        fail("PF-SBOM-SCHEMA", "Tool Lock validator mutated its input")
    if classification is not None:
        fail(classification, detail)
    if validated is not value:
        fail("PF-SBOM-SCHEMA", "Tool Lock validator returned a different object")
    return value


def compute_tool_lock_identity(raw: bytes) -> ToolLockIdentity:
    """Validate Tool Lock v2, then derive canonical and exact-byte identities."""

    value = _validate_tool_lock(decode_json_document(raw))
    return ToolLockIdentity(
        tool_lock_v2_digest=domain_digest(
            TOOL_LOCK_DOMAIN,
            canonical_pf_jcs(value),
        ),
        toolchain_lock_sha256=raw_sha256(raw),
    )


def verify_tool_lock_binding(
    raw: bytes,
    *,
    tool_lock_v2_digest: str,
    toolchain_lock_sha256: str,
) -> ToolLockIdentity:
    """Recompute and exactly verify both typed lock identities."""

    actual = compute_tool_lock_identity(raw)
    expected_structured = _require_digest_wire(
        tool_lock_v2_digest,
        "PF-SBOM-BIND",
        "toolLockV2Digest",
    )
    expected_raw = _require_digest_wire(
        toolchain_lock_sha256,
        "PF-SBOM-BIND",
        "toolchainLockSha256",
    )
    if not hmac.compare_digest(actual.tool_lock_v2_digest, expected_structured):
        fail("PF-SBOM-BIND", "ToolLockV2Digest mismatch")
    if not hmac.compare_digest(actual.toolchain_lock_sha256, expected_raw):
        fail("PF-SBOM-BIND", "raw toolchainLockSha256 mismatch")
    return actual


def derive_component_identity(component_fields: dict[str, object]) -> ComponentIdentity:
    """Derive identity from validated fields excluding componentDigest/bomRef.

    The caller remains responsible for the complete inventory/source/content/
    graph validation mandated by SPEC-TOOL-001.  This helper enforces the exact
    identity preimage shape so computed identity fields cannot self-reference.
    """

    if type(component_fields) is not dict:
        fail("PF-SBOM-SCHEMA", "component identity preimage must be an object")
    first_snapshot, first_bytes = _canonical_pf_jcs_snapshot(component_fields)
    _, second_bytes = _canonical_pf_jcs_snapshot(component_fields)
    if not hmac.compare_digest(first_bytes, second_bytes):
        fail("PF-SBOM-SCHEMA", "component identity input changed during snapshot")
    if type(first_snapshot) is not dict:
        fail("PF-SBOM-SCHEMA", "component identity snapshot must be an object")
    assert isinstance(first_snapshot, dict)
    for key in first_snapshot:
        if type(key) is not str:
            fail("PF-SBOM-SCHEMA", "component identity field name must be text")
    actual_fields = set(first_snapshot)
    if actual_fields != COMPONENT_PREIMAGE_FIELDS:
        missing = sorted(COMPONENT_PREIMAGE_FIELDS - actual_fields)
        extra = sorted(actual_fields - COMPONENT_PREIMAGE_FIELDS)
        fail(
            "PF-SBOM-SCHEMA",
            f"component identity preimage fields differ: missing={missing}, extra={extra}",
        )
    digest = domain_digest(COMPONENT_DOMAIN, first_bytes)
    return ComponentIdentity(
        component_digest=digest,
        bom_ref="urn:proofforge:component:" + digest[7:],
    )


def candidate_root_bom_ref(candidate_digest: str) -> str:
    """Derive the synthetic candidate root ref from raw digest bytes."""

    checked = _require_digest_wire(
        candidate_digest,
        "PF-SBOM-SCHEMA",
        "candidate.digest",
    )
    return "urn:proofforge:candidate:" + checked[7:]


__all__ = (
    "ComponentIdentity",
    "SupplyChainError",
    "ToolLockIdentity",
    "candidate_root_bom_ref",
    "canonical_pf_jcs",
    "compute_tool_lock_identity",
    "decode_json_document",
    "derive_component_identity",
    "domain_digest",
    "raw_sha256",
    "verify_tool_lock_binding",
)
