#!/usr/bin/env python3
"""Pure pre-freeze primitives for the candidate-bound supply-chain pipeline.

This module is a pre-freeze preparation slice adjacent to pending TASK-D0-08.
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
MAX_LOGICAL_COMPONENTS = 4_096

TOOL_LOCK_DOMAIN = "proof-forge.toolchains.v2"
COMPONENT_DOMAIN = "proof-forge.supply-chain-component.v1"

DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}")
DOMAIN_RE = re.compile(
    r"[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*"
)
COMPONENT_ID_RE = re.compile(r"[a-z0-9][a-z0-9._-]{0,126}")
TOOL_LOCK_REF_ID_RE = re.compile(
    r"[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?"
)

TOOL_LOCK_LEAF_KINDS = frozenset(
    {
        "asset",
        "bundle-file",
        "compiler-executable",
        "tool-executable",
        "tool-runtime-file",
    }
)
DIRECT_TOOL_COMPONENT_KINDS = frozenset(
    {
        "download-asset",
        "compiler-executable",
        "tool-executable",
        "runtime-dylib",
    }
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


@dataclass(frozen=True, order=True)
class ToolLockLeafRef:
    """Exact identity of one authoritative direct Tool Lock leaf."""

    kind: str
    id: str
    path: str | None


@dataclass(frozen=True)
class ToolLockLeaf:
    """Validated leaf identity plus content metadata needed by later joins."""

    ref: ToolLockLeafRef
    asset_id: str
    size: int | None
    digest: str


@dataclass(frozen=True)
class ToolLockComponentSource:
    """Narrow pre-inventory mapping from one logical kind to Tool Lock refs."""

    component_id: str
    component_kind: str
    lock_refs: tuple[ToolLockLeafRef, ...]


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


def _decode_validated_tool_lock(raw: bytes) -> dict[str, object]:
    return _validate_tool_lock(decode_json_document(raw))


def _leaf_ref_sort_key(ref: ToolLockLeafRef) -> tuple[str, str, str]:
    return (ref.kind, ref.id, "" if ref.path is None else ref.path)


def _require_tool_lock_leaf_ref(value: object) -> ToolLockLeafRef:
    if type(value) is not ToolLockLeafRef:
        fail("PF-SBOM-CLOSURE", "Tool Lock component ref has the wrong type")
    assert isinstance(value, ToolLockLeafRef)
    if type(value.kind) is not str or value.kind not in TOOL_LOCK_LEAF_KINDS:
        fail("PF-SBOM-CLOSURE", "Tool Lock component ref has an unknown kind")
    if (
        type(value.id) is not str
        or TOOL_LOCK_REF_ID_RE.fullmatch(value.id) is None
    ):
        fail("PF-SBOM-CLOSURE", "Tool Lock component ref has an invalid id")
    if value.kind == "asset":
        if value.path is not None:
            fail("PF-SBOM-CLOSURE", "asset Tool Lock ref must have a null path")
    elif type(value.path) is not str or not value.path:
        fail("PF-SBOM-CLOSURE", "non-asset Tool Lock ref needs a path")
    return value


def _typed_leaf_digest(raw_digest: object) -> str:
    if type(raw_digest) is not str or re.fullmatch(r"[0-9a-f]{64}", raw_digest) is None:
        fail("PF-SBOM-CLOSURE", "validated Tool Lock leaf digest is malformed")
    assert isinstance(raw_digest, str)
    return "sha256:" + raw_digest


def enumerate_tool_lock_leaves(raw: bytes) -> tuple[ToolLockLeaf, ...]:
    """Enumerate the exact five-class direct-leaf denominator.

    The authoritative Tool Lock validator runs first.  The returned immutable
    records retain logical ref identity separately from shared content
    metadata, so equal bytes cannot merge asset/executable roles.
    """

    lock = _decode_validated_tool_lock(raw)
    leaves: list[ToolLockLeaf] = []

    assets = lock["assets"]
    compiler = lock["compilerToolchain"]
    bundle_files = lock["bundleFiles"]
    tools = lock["tools"]
    assert isinstance(assets, list)
    assert isinstance(compiler, dict)
    assert isinstance(bundle_files, list)
    assert isinstance(tools, list)

    bundle_by_path: dict[str, dict[str, object]] = {}
    for raw_bundle in bundle_files:
        assert isinstance(raw_bundle, dict)
        path = raw_bundle["path"]
        assert isinstance(path, str)
        bundle_by_path[path] = raw_bundle

    for raw_asset in assets:
        assert isinstance(raw_asset, dict)
        asset_id = raw_asset["id"]
        size = raw_asset["size"]
        assert isinstance(asset_id, str)
        assert type(size) is int
        leaves.append(
            ToolLockLeaf(
                ref=ToolLockLeafRef("asset", asset_id, None),
                asset_id=asset_id,
                size=size,
                digest=_typed_leaf_digest(raw_asset["sha256"]),
            )
        )

    compiler_id = compiler["id"]
    compiler_asset_id = compiler["assetId"]
    compiler_executables = compiler["executables"]
    assert isinstance(compiler_id, str)
    assert isinstance(compiler_asset_id, str)
    assert isinstance(compiler_executables, list)
    for raw_executable in compiler_executables:
        assert isinstance(raw_executable, dict)
        path = raw_executable["path"]
        assert isinstance(path, str)
        leaves.append(
            ToolLockLeaf(
                ref=ToolLockLeafRef(
                    "compiler-executable",
                    compiler_id,
                    path,
                ),
                asset_id=compiler_asset_id,
                size=None,
                digest=_typed_leaf_digest(raw_executable["sha256"]),
            )
        )

    for raw_bundle in bundle_files:
        assert isinstance(raw_bundle, dict)
        asset_id = raw_bundle["assetId"]
        path = raw_bundle["path"]
        size = raw_bundle["size"]
        assert isinstance(asset_id, str)
        assert isinstance(path, str)
        assert type(size) is int
        leaves.append(
            ToolLockLeaf(
                ref=ToolLockLeafRef("bundle-file", asset_id, path),
                asset_id=asset_id,
                size=size,
                digest=_typed_leaf_digest(raw_bundle["sha256"]),
            )
        )

    for raw_tool in tools:
        assert isinstance(raw_tool, dict)
        tool_id = raw_tool["id"]
        tool_asset_id = raw_tool["assetId"]
        executable = raw_tool["executable"]
        runtime_files = raw_tool["runtimeFiles"]
        assert isinstance(tool_id, str)
        assert isinstance(tool_asset_id, str)
        assert isinstance(executable, str)
        assert isinstance(runtime_files, list)
        executable_bundle = bundle_by_path[executable]
        executable_size = executable_bundle["size"]
        assert type(executable_size) is int
        leaves.append(
            ToolLockLeaf(
                ref=ToolLockLeafRef("tool-executable", tool_id, executable),
                asset_id=tool_asset_id,
                size=executable_size,
                digest=_typed_leaf_digest(raw_tool["executableSha256"]),
            )
        )
        for raw_runtime in runtime_files:
            assert isinstance(raw_runtime, dict)
            runtime_path = raw_runtime["path"]
            assert isinstance(runtime_path, str)
            runtime_bundle = bundle_by_path[runtime_path]
            runtime_asset_id = runtime_bundle["assetId"]
            runtime_size = runtime_bundle["size"]
            assert isinstance(runtime_asset_id, str)
            assert type(runtime_size) is int
            leaves.append(
                ToolLockLeaf(
                    ref=ToolLockLeafRef(
                        "tool-runtime-file",
                        tool_id,
                        runtime_path,
                    ),
                    asset_id=runtime_asset_id,
                    size=runtime_size,
                    digest=_typed_leaf_digest(raw_runtime["sha256"]),
                )
            )

    leaves.sort(key=lambda leaf: _leaf_ref_sort_key(leaf.ref))
    refs = tuple(leaf.ref for leaf in leaves)
    if len(refs) != len(set(refs)):
        fail("PF-SBOM-CLOSURE", "Tool Lock direct-leaf identities are not unique")
    return tuple(leaves)


def _require_component_source(value: object) -> ToolLockComponentSource:
    if type(value) is not ToolLockComponentSource:
        fail("PF-SBOM-CLOSURE", "Tool Lock component source has the wrong type")
    assert isinstance(value, ToolLockComponentSource)
    if (
        type(value.component_id) is not str
        or COMPONENT_ID_RE.fullmatch(value.component_id) is None
    ):
        fail("PF-SBOM-CLOSURE", "Tool Lock component source has an invalid id")
    if (
        type(value.component_kind) is not str
        or value.component_kind not in DIRECT_TOOL_COMPONENT_KINDS
    ):
        fail("PF-SBOM-CLOSURE", "Tool Lock component source has an invalid kind")
    if type(value.lock_refs) is not tuple or not value.lock_refs:
        fail("PF-SBOM-CLOSURE", "Tool Lock component source refs must be nonempty")
    checked_refs = tuple(_require_tool_lock_leaf_ref(ref) for ref in value.lock_refs)
    if checked_refs != tuple(sorted(checked_refs, key=_leaf_ref_sort_key)):
        fail("PF-SBOM-CLOSURE", "Tool Lock component refs are not sorted")
    if len(checked_refs) != len(set(checked_refs)):
        fail("PF-SBOM-CLOSURE", "Tool Lock component refs are duplicated")
    return value


def _validate_component_ref_shape(source: ToolLockComponentSource) -> None:
    kinds = tuple(ref.kind for ref in source.lock_refs)
    if source.component_kind == "download-asset":
        valid = kinds == ("asset",)
    elif source.component_kind == "compiler-executable":
        valid = kinds == ("compiler-executable",)
    elif source.component_kind == "tool-executable":
        valid = kinds == ("bundle-file", "tool-executable")
    else:
        valid = (
            len(kinds) >= 2
            and kinds[0] == "bundle-file"
            and all(kind == "tool-runtime-file" for kind in kinds[1:])
        )
    if not valid:
        fail(
            "PF-SBOM-CLOSURE",
            f"logical component {source.component_id} has incompatible Tool Lock refs",
        )


def _same_leaf_content(left: ToolLockLeaf, right: ToolLockLeaf) -> bool:
    return (
        left.asset_id == right.asset_id
        and left.size == right.size
        and hmac.compare_digest(left.digest, right.digest)
        and left.ref.path == right.ref.path
    )


def validate_direct_tool_lock_ref_coverage(
    raw: bytes,
    component_sources: tuple[ToolLockComponentSource, ...],
) -> tuple[ToolLockLeaf, ...]:
    """Require one compatible logical owner for every direct Tool Lock leaf."""

    if type(component_sources) is not tuple:
        fail("PF-SBOM-CLOSURE", "Tool Lock component sources must be a tuple")
    if len(component_sources) > MAX_LOGICAL_COMPONENTS:
        fail("PF-SBOM-LIMIT", "logical component count exceeds 4,096")
    leaves = enumerate_tool_lock_leaves(raw)
    leaf_by_ref = {leaf.ref: leaf for leaf in leaves}
    checked = tuple(_require_component_source(source) for source in component_sources)
    component_ids = tuple(source.component_id for source in checked)
    if component_ids != tuple(sorted(component_ids)) or len(component_ids) != len(
        set(component_ids)
    ):
        fail("PF-SBOM-CLOSURE", "Tool Lock component source IDs are not unique sorted")

    owners: dict[ToolLockLeafRef, str] = {}
    for source in checked:
        _validate_component_ref_shape(source)
        resolved: list[ToolLockLeaf] = []
        for ref in source.lock_refs:
            leaf = leaf_by_ref.get(ref)
            if leaf is None:
                fail(
                    "PF-SBOM-CLOSURE",
                    f"logical component {source.component_id} references an unknown Tool Lock leaf",
                )
            previous = owners.get(ref)
            if previous is not None:
                fail(
                    "PF-SBOM-CLOSURE",
                    "Tool Lock leaf has multiple logical owners: "
                    f"{previous}, {source.component_id}",
                )
            owners[ref] = source.component_id
            resolved.append(leaf)

        if source.component_kind == "tool-executable":
            if not _same_leaf_content(resolved[0], resolved[1]):
                fail(
                    "PF-SBOM-CLOSURE",
                    f"tool executable {source.component_id} does not join its bundle leaf",
                )
        elif source.component_kind == "runtime-dylib":
            if any(
                not _same_leaf_content(resolved[0], owner)
                for owner in resolved[1:]
            ):
                fail(
                    "PF-SBOM-CLOSURE",
                    f"runtime component {source.component_id} does not join all owner refs",
                )

    missing = sorted(
        set(leaf_by_ref) - set(owners),
        key=_leaf_ref_sort_key,
    )
    if missing:
        first = missing[0]
        fail(
            "PF-SBOM-CLOSURE",
            "Tool Lock leaf has no logical owner: "
            f"{first.kind}/{first.id}/{first.path}",
        )
    return leaves


def compute_tool_lock_identity(raw: bytes) -> ToolLockIdentity:
    """Validate Tool Lock v2, then derive canonical and exact-byte identities."""

    value = _decode_validated_tool_lock(raw)
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
    "ToolLockComponentSource",
    "ToolLockIdentity",
    "ToolLockLeaf",
    "ToolLockLeafRef",
    "candidate_root_bom_ref",
    "canonical_pf_jcs",
    "compute_tool_lock_identity",
    "decode_json_document",
    "derive_component_identity",
    "domain_digest",
    "enumerate_tool_lock_leaves",
    "raw_sha256",
    "validate_direct_tool_lock_ref_coverage",
    "verify_tool_lock_binding",
)
