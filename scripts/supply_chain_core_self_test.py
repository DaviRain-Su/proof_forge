#!/usr/bin/env python3
"""Pre-acceptance RED/GREEN tests for the D0-08 supply-chain identity core.

This is intentionally independent from the legacy TASK-D0-05 generator.  It
pins pre-freeze D0-08 implementation seams only: strict JSON/PF-JCS, the sole
ToolLockV2Digest authority, typed raw-vs-structured lock binding, the direct
Tool Lock leaf census/owner join, logical component identity, and the synthetic
candidate BOM root.  It does not claim the full TST-SBOM-002 closure or
publication acceptance.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "supply_chain_core.py"

RAW_TOOL_LOCK_SHA256 = (
    "sha256:1f32aed697bd9d769bb3934a31387b8c62b43af2f192a1000301278a328bf0b4"
)
TOOL_LOCK_V2_DIGEST = (
    "sha256:36de2d6f30de9ec541419f8a3085be7e24c406669a10d43ea58a4f894d39aa62"
)
LEGACY_TOOL_LOCK_DIGEST = (
    "sha256:d35cac0437ddaf1054cd5b5eabe7f2721b9f257ca557c2dc57ddf6e879291d36"
)
SOLC_CONTENT_DIGEST = (
    "sha256:0a2829292697dda542e4e365bb63fbd6d3ed51537140222a880ab760cffa7746"
)
SOLC_ASSET_COMPONENT_DIGEST = (
    "sha256:d4177fab8375e4e39e00a6ab402ba589ba1798f1f72ac0eee75cc60cedbafe70"
)
SOLC_EXECUTABLE_COMPONENT_DIGEST = (
    "sha256:a426c5a55c3e207d351f57abcf6d6e9deae2c2665a18ecab7aaeff1a1c51f733"
)

EXPECTED_TOOL_LOCK_LEAF_KEYS = (
    ("asset", "foundry-v0.3.0-darwin-arm64", None),
    ("asset", "lean-4.31.0-darwin-arm64", None),
    ("asset", "openssl-3.6.3-homebrew-arm64-tahoe", None),
    ("asset", "sbom-utility-v0.19.2-darwin-arm64", None),
    ("asset", "solc-0.8.34-macos-universal", None),
    ("asset", "wabt-1.0.41-macos-arm64", None),
    ("bundle-file", "foundry-v0.3.0-darwin-arm64", "anvil"),
    ("bundle-file", "foundry-v0.3.0-darwin-arm64", "cast"),
    (
        "bundle-file",
        "openssl-3.6.3-homebrew-arm64-tahoe",
        "lib/libcrypto.3.dylib",
    ),
    (
        "bundle-file",
        "sbom-utility-v0.19.2-darwin-arm64",
        "sbom-utility",
    ),
    ("bundle-file", "solc-0.8.34-macos-universal", "solc"),
    ("bundle-file", "wabt-1.0.41-macos-arm64", "wat2wasm"),
    ("compiler-executable", "lean", "bin/lake"),
    ("compiler-executable", "lean", "bin/lean"),
    ("tool-executable", "anvil", "anvil"),
    ("tool-executable", "cast", "cast"),
    ("tool-executable", "sbom-utility", "sbom-utility"),
    ("tool-executable", "solc", "solc"),
    ("tool-executable", "wat2wasm", "wat2wasm"),
    ("tool-runtime-file", "wat2wasm", "lib/libcrypto.3.dylib"),
)

SBOM_UTILITY_ASSET_SHA256 = (
    "9cfdf6b2308fc39b182e64438c78f847a58514899858792f44846bf95026fedf"
)
SBOM_UTILITY_EXECUTABLE_SHA256 = (
    "5d707f542cfc6f06b0c50abe1645ed18ec54263c29ed58bc67c2fe26c0058881"
)


def load_core() -> ModuleType:
    if not CORE.is_file():
        raise AssertionError(
            "RED: scripts/supply_chain_core.py does not exist; "
            "the legacy D0-05 generator cannot satisfy the D0-08 identity API"
        )
    spec = importlib.util.spec_from_file_location("supply_chain_core", CORE)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load supply-chain core")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expect_error(module: ModuleType, code: str, operation: Callable[[], object]) -> None:
    try:
        operation()
    except module.SupplyChainError as error:
        if error.code != code:
            raise AssertionError(f"expected {code}, got {error.code}: {error}") from error
        return
    raise AssertionError(f"expected {code}")


def test_pf_jcs(module: ModuleType) -> None:
    # U+10000 sorts before U+E000 by UTF-16 code units, the reverse of Unicode
    # code-point order.  This fixed vector catches Python sort_keys=True.
    value = {
        "\ue000": 2,
        "\U00010000": 1,
        "a": "line\nquoted\"",
    }
    golden = (
        b'{"a":"line\\nquoted\\\"",'
        b'"\xf0\x90\x80\x80":1,"\xee\x80\x80":2}'
    )
    if module.canonical_pf_jcs(value) != golden:
        raise AssertionError("PF-JCS UTF-16 ordering/escaping drifted")

    decoded = module.decode_json_document(b' { "a" : [true, null, -1] }\n')
    if decoded != {"a": [True, None, -1]}:
        raise AssertionError("strict JSON decoder changed valid scalar semantics")

    invalid_json = (
        b'{"a":1,"a":1}',
        b'{"a":-00}',
        b'{"a":-01}',
        b'{"a":-0x1}',
        b'{"a":NaN}',
        b'{"a":Infinity}',
        b'{"a":-Infinity}',
        b'{"a":"\\ud800"}',
        b'{"a":"\xff"}',
    )
    for raw in invalid_json:
        expect_error(
            module,
            "PF-SBOM-JSON",
            lambda raw=raw: module.decode_json_document(raw),
        )
    invalid_profile = (
        b'{"a":1.0}',
        b'{"a":1e0}',
        b'{"a":-0}',
        b'{"a":9007199254740992}',
        b'{"a":-9007199254740992}',
    )
    for raw in invalid_profile:
        expect_error(
            module,
            "PF-SBOM-SCHEMA",
            lambda raw=raw: module.decode_json_document(raw),
        )

    shared: list[object] = []
    if module.canonical_pf_jcs([shared, shared]) != b"[[],[]]":
        raise AssertionError("shared acyclic JSON value was rejected")
    cycle: list[object] = []
    cycle.append(cycle)
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.canonical_pf_jcs(cycle),
    )
    if module.domain_digest("a", b"{}") != (
        "sha256:6d8a39a291dba279b0299a38b5835a23958de12a951f847f1f5ec91e743b3ad4"
    ):
        raise AssertionError("profile-style single-segment digest domain drifted")
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.domain_digest("a..b", b"{}"),
    )


def test_tool_lock_identity(module: ModuleType) -> None:
    raw = (ROOT / "toolchains.lock.json").read_bytes()
    identity = module.compute_tool_lock_identity(raw)
    if identity.toolchain_lock_sha256 != RAW_TOOL_LOCK_SHA256:
        raise AssertionError("raw tool lock SHA-256 drifted without freeze review")
    if identity.tool_lock_v2_digest != TOOL_LOCK_V2_DIGEST:
        raise AssertionError("ToolLockV2Digest drifted without freeze review")

    value = json.loads(raw.decode("utf-8"))
    def reverse_object_layout(current: object) -> object:
        if isinstance(current, dict):
            return {
                key: reverse_object_layout(item)
                for key, item in reversed(tuple(current.items()))
            }
        if isinstance(current, list):
            return [reverse_object_layout(item) for item in current]
        return current

    alternate_layout = json.dumps(
        reverse_object_layout(value),
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    alternate = module.compute_tool_lock_identity(alternate_layout)
    if alternate.tool_lock_v2_digest != identity.tool_lock_v2_digest:
        raise AssertionError("semantic ToolLockV2Digest depends on JSON layout")
    if alternate.toolchain_lock_sha256 == identity.toolchain_lock_sha256:
        raise AssertionError("raw tool lock SHA-256 ignored exact retained bytes")
    whitespace_only = module.compute_tool_lock_identity(raw + b" ")
    if whitespace_only.tool_lock_v2_digest != identity.tool_lock_v2_digest:
        raise AssertionError("semantic ToolLockV2Digest depends on trailing whitespace")
    if whitespace_only.toolchain_lock_sha256 == identity.toolchain_lock_sha256:
        raise AssertionError("raw tool lock SHA-256 ignored trailing whitespace")

    verified = module.verify_tool_lock_binding(
        raw,
        tool_lock_v2_digest=TOOL_LOCK_V2_DIGEST,
        toolchain_lock_sha256=RAW_TOOL_LOCK_SHA256,
    )
    if verified != identity:
        raise AssertionError("verified tool lock binding changed identity")

    expect_error(
        module,
        "PF-SBOM-BIND",
        lambda: module.verify_tool_lock_binding(
            raw,
            tool_lock_v2_digest=RAW_TOOL_LOCK_SHA256,
            toolchain_lock_sha256=TOOL_LOCK_V2_DIGEST,
        ),
    )
    expect_error(
        module,
        "PF-SBOM-BIND",
        lambda: module.verify_tool_lock_binding(
            raw,
            tool_lock_v2_digest=LEGACY_TOOL_LOCK_DIGEST,
            toolchain_lock_sha256=RAW_TOOL_LOCK_SHA256,
        ),
    )
    expect_error(
        module,
        "PF-SBOM-BIND",
        lambda: module.verify_tool_lock_binding(
            raw,
            tool_lock_v2_digest=TOOL_LOCK_V2_DIGEST,
            toolchain_lock_sha256=LEGACY_TOOL_LOCK_DIGEST,
        ),
    )
    expect_error(
        module,
        "PF-SBOM-JSON",
        lambda: module.verify_tool_lock_binding(
            b'{"schema":',
            tool_lock_v2_digest="malformed",
            toolchain_lock_sha256="malformed",
        ),
    )

    legacy_schema = copy.deepcopy(value)
    legacy_schema["schema"] = "proof-forge.toolchain-lock.v1"
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(legacy_schema, separators=(",", ":")).encode("utf-8")
        ),
    )
    bool_size = copy.deepcopy(value)
    bool_size["assets"][0]["size"] = True
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(bool_size, separators=(",", ":")).encode("utf-8")
        ),
    )
    bool_strip_components = copy.deepcopy(value)
    bool_strip_components["compilerToolchain"]["stripComponents"] = True
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(
                bool_strip_components,
                separators=(",", ":"),
            ).encode("utf-8")
        ),
    )
    broken_cross_reference = copy.deepcopy(value)
    broken_cross_reference["tools"][0]["assetId"] = (
        broken_cross_reference["compilerToolchain"]["assetId"]
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.compute_tool_lock_identity(
            json.dumps(
                broken_cross_reference,
                separators=(",", ":"),
            ).encode("utf-8")
        ),
    )
    invalid_compiler_version = copy.deepcopy(value)
    invalid_compiler_version["compilerToolchain"]["version"] = "latest"
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(
                invalid_compiler_version,
                separators=(",", ":"),
            ).encode("utf-8")
        ),
    )
    invalid_tool_version = copy.deepcopy(value)
    invalid_tool_version["tools"][0]["version"] = "01.0.0"
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(
                invalid_tool_version,
                separators=(",", ":"),
            ).encode("utf-8")
        ),
    )
    invalid_unresolved_version = copy.deepcopy(value)
    invalid_unresolved_version["unresolved"]["nearSandbox"] = "^2.13"
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.compute_tool_lock_identity(
            json.dumps(
                invalid_unresolved_version,
                separators=(",", ":"),
            ).encode("utf-8")
        ),
    )
    valid_prerelease = copy.deepcopy(value)
    valid_prerelease["unresolved"]["nearSandbox"] = "2.13.0-rc.1+build.7"
    module.compute_tool_lock_identity(
        json.dumps(valid_prerelease, separators=(",", ":")).encode("utf-8")
    )
    valid_long_build = copy.deepcopy(value)
    valid_long_build["unresolved"]["nearSandbox"] = "1.0.0+" + "a" * 300
    module.compute_tool_lock_identity(
        json.dumps(valid_long_build, separators=(",", ":")).encode("utf-8")
    )
    maximum_u64 = "18446744073709551615"
    over_u64 = "18446744073709551616"
    for index in range(3):
        accepted_components = ["0", "0", "0"]
        accepted_components[index] = maximum_u64
        accepted_version = copy.deepcopy(value)
        accepted_version["unresolved"]["nearSandbox"] = ".".join(
            accepted_components
        )
        module.compute_tool_lock_identity(
            json.dumps(accepted_version, separators=(",", ":")).encode("utf-8")
        )

        rejected_components = ["0", "0", "0"]
        rejected_components[index] = over_u64
        rejected_version = copy.deepcopy(value)
        rejected_version["unresolved"]["nearSandbox"] = ".".join(
            rejected_components
        )
        expect_error(
            module,
            "PF-SBOM-SCHEMA",
            lambda rejected_version=rejected_version: module.compute_tool_lock_identity(
                json.dumps(
                    rejected_version,
                    separators=(",", ":"),
                ).encode("utf-8")
            ),
        )

    class InjectedAssetError(RuntimeError):
        pass

    class InjectedClosureError(InjectedAssetError):
        pass

    def mutating_validator(candidate: dict[str, object]) -> dict[str, object]:
        candidate.pop("unexpected")
        return candidate

    injected = SimpleNamespace(
        AssetError=InjectedAssetError,
        ToolLockClosureError=InjectedClosureError,
        validate_tool_lock=mutating_validator,
    )
    original_validator_module = module._TOOLCHAIN_ASSETS_MODULE
    module._TOOLCHAIN_ASSETS_MODULE = injected
    try:
        normalized_attack = copy.deepcopy(value)
        normalized_attack["unexpected"] = True
        expect_error(
            module,
            "PF-SBOM-SCHEMA",
            lambda: module.compute_tool_lock_identity(
                json.dumps(
                    normalized_attack,
                    separators=(",", ":"),
                ).encode("utf-8")
            ),
        )
    finally:
        module._TOOLCHAIN_ASSETS_MODULE = original_validator_module


def test_locked_cyclonedx_validator() -> None:
    """Pin the offline validator before the formal D0-08 denominator freeze."""

    lock = json.loads((ROOT / "toolchains.lock.json").read_text(encoding="utf-8"))
    assets = [
        item for item in lock["assets"]
        if item["id"] == "sbom-utility-v0.19.2-darwin-arm64"
    ]
    if assets != [{
        "id": "sbom-utility-v0.19.2-darwin-arm64",
        "url": (
            "https://github.com/CycloneDX/sbom-utility/releases/download/"
            "v0.19.2/sbom-utility-v0.19.2-darwin-arm64.tar.gz"
        ),
        "size": 7_827_764,
        "sha256": SBOM_UTILITY_ASSET_SHA256,
        "format": "tar.gz",
    }]:
        raise AssertionError("offline CycloneDX validator asset is not exactly pinned")

    bundle_files = [
        item for item in lock["bundleFiles"] if item["path"] == "sbom-utility"
    ]
    if bundle_files != [{
        "path": "sbom-utility",
        "assetId": "sbom-utility-v0.19.2-darwin-arm64",
        "member": "sbom-utility",
        "size": 16_037_250,
        "sha256": SBOM_UTILITY_EXECUTABLE_SHA256,
        "mode": "0555",
    }]:
        raise AssertionError("offline CycloneDX validator executable is not pinned")

    tools = [item for item in lock["tools"] if item["id"] == "sbom-utility"]
    if tools != [{
        "id": "sbom-utility",
        "version": "0.19.2",
        "sourceUrl": (
            "https://github.com/CycloneDX/sbom-utility/releases/tag/v0.19.2"
        ),
        "platform": "darwin-arm64",
        "assetId": "sbom-utility-v0.19.2-darwin-arm64",
        "executable": "sbom-utility",
        "defaultPath": (
            "~/.cache/proof-forge-v2/tool-root/darwin-arm64/sbom-utility"
        ),
        "executableSha256": SBOM_UTILITY_EXECUTABLE_SHA256,
        "runtimeLibrarySubdir": None,
        "runtimeFiles": [],
        "versionArgs": ["version"],
        "expectedVersion": "v0.19.2",
        "licenseSpdx": "Apache-2.0",
        "requiredByProfiles": ["supply-chain-cyclonedx-1.6-v1"],
    }]:
        raise AssertionError("offline CycloneDX validator tool identity drifted")

    policies = [
        item for item in lock["machoPolicy"]["files"]
        if item["path"] == "sbom-utility"
    ]
    if policies != [{
        "path": "sbom-utility",
        "installId": None,
        "externalLoads": [],
    }]:
        raise AssertionError("offline CycloneDX validator runtime closure drifted")


def direct_tool_component_sources(module: ModuleType) -> tuple[object, ...]:
    ref = module.ToolLockLeafRef
    source = module.ToolLockComponentSource

    def refs(*items: tuple[str, str, str | None]) -> tuple[object, ...]:
        return tuple(ref(*item) for item in items)

    return (
        source(
            "asset-foundry",
            "download-asset",
            refs(("asset", "foundry-v0.3.0-darwin-arm64", None)),
        ),
        source(
            "asset-lean",
            "download-asset",
            refs(("asset", "lean-4.31.0-darwin-arm64", None)),
        ),
        source(
            "asset-openssl",
            "download-asset",
            refs(("asset", "openssl-3.6.3-homebrew-arm64-tahoe", None)),
        ),
        source(
            "asset-sbom-utility",
            "download-asset",
            refs(("asset", "sbom-utility-v0.19.2-darwin-arm64", None)),
        ),
        source(
            "asset-solc",
            "download-asset",
            refs(("asset", "solc-0.8.34-macos-universal", None)),
        ),
        source(
            "asset-wabt",
            "download-asset",
            refs(("asset", "wabt-1.0.41-macos-arm64", None)),
        ),
        source(
            "compiler-lake",
            "compiler-executable",
            refs(("compiler-executable", "lean", "bin/lake")),
        ),
        source(
            "compiler-lean",
            "compiler-executable",
            refs(("compiler-executable", "lean", "bin/lean")),
        ),
        source(
            "runtime-libcrypto",
            "runtime-dylib",
            refs(
                (
                    "bundle-file",
                    "openssl-3.6.3-homebrew-arm64-tahoe",
                    "lib/libcrypto.3.dylib",
                ),
                (
                    "tool-runtime-file",
                    "wat2wasm",
                    "lib/libcrypto.3.dylib",
                ),
            ),
        ),
        source(
            "tool-anvil",
            "tool-executable",
            refs(
                ("bundle-file", "foundry-v0.3.0-darwin-arm64", "anvil"),
                ("tool-executable", "anvil", "anvil"),
            ),
        ),
        source(
            "tool-cast",
            "tool-executable",
            refs(
                ("bundle-file", "foundry-v0.3.0-darwin-arm64", "cast"),
                ("tool-executable", "cast", "cast"),
            ),
        ),
        source(
            "tool-sbom-utility",
            "tool-executable",
            refs(
                (
                    "bundle-file",
                    "sbom-utility-v0.19.2-darwin-arm64",
                    "sbom-utility",
                ),
                ("tool-executable", "sbom-utility", "sbom-utility"),
            ),
        ),
        source(
            "tool-solc",
            "tool-executable",
            refs(
                ("bundle-file", "solc-0.8.34-macos-universal", "solc"),
                ("tool-executable", "solc", "solc"),
            ),
        ),
        source(
            "tool-wat2wasm",
            "tool-executable",
            refs(
                ("bundle-file", "wabt-1.0.41-macos-arm64", "wat2wasm"),
                ("tool-executable", "wat2wasm", "wat2wasm"),
            ),
        ),
    )


def test_direct_tool_lock_leaf_coverage(module: ModuleType) -> None:
    raw = (ROOT / "toolchains.lock.json").read_bytes()
    leaves = module.enumerate_tool_lock_leaves(raw)
    actual_keys = tuple(
        (leaf.ref.kind, leaf.ref.id, leaf.ref.path) for leaf in leaves
    )
    if actual_keys != EXPECTED_TOOL_LOCK_LEAF_KEYS:
        raise AssertionError(
            "Tool Lock direct-leaf denominator drifted from the reviewed pre-freeze baseline"
        )
    if len(leaves) != 20:
        raise AssertionError(
            "Tool Lock direct-leaf count is not the reviewed pre-freeze baseline"
        )

    baseline = direct_tool_component_sources(module)
    verified = module.validate_direct_tool_lock_ref_coverage(raw, baseline)
    if verified != leaves:
        raise AssertionError("direct Tool Lock coverage returned a different snapshot")
    if len(baseline) != 14:
        raise AssertionError("direct logical component count is not the baseline")

    by_id = {source.component_id: source for source in baseline}
    source = module.ToolLockComponentSource
    ref = module.ToolLockLeafRef

    trailing_punctuation_id = tuple(
        source("asset-foundry-", item.component_kind, item.lock_refs)
        if item.component_id == "asset-foundry"
        else item
        for item in baseline
    )
    module.validate_direct_tool_lock_ref_coverage(raw, trailing_punctuation_id)

    component_id_127 = "a" * 127
    max_component_id = tuple(
        sorted(
            (
                source(component_id_127, item.component_kind, item.lock_refs)
                if item.component_id == "asset-foundry"
                else item
                for item in baseline
            ),
            key=lambda item: item.component_id,
        )
    )
    module.validate_direct_tool_lock_ref_coverage(raw, max_component_id)

    component_id_128 = "a" * 128
    oversized_component_id = tuple(
        sorted(
            (
                source(component_id_128, item.component_kind, item.lock_refs)
                if item.component_id == "asset-foundry"
                else item
                for item in baseline
            ),
            key=lambda item: item.component_id,
        )
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            raw, oversized_component_id
        ),
    )

    compiler_id_128 = "b" * 128
    max_tool_lock_id = json.loads(raw.decode("utf-8"))
    max_tool_lock_id["compilerToolchain"]["id"] = compiler_id_128
    max_tool_lock_raw = json.dumps(
        max_tool_lock_id, separators=(",", ":")
    ).encode("utf-8")
    max_tool_lock_sources = tuple(
        source(
            item.component_id,
            item.component_kind,
            tuple(
                ref(
                    lock_ref.kind,
                    compiler_id_128
                    if lock_ref.kind == "compiler-executable"
                    else lock_ref.id,
                    lock_ref.path,
                )
                for lock_ref in item.lock_refs
            ),
        )
        for item in baseline
    )
    module.validate_direct_tool_lock_ref_coverage(
        max_tool_lock_raw, max_tool_lock_sources
    )

    oversized_tool_lock_id = json.loads(raw.decode("utf-8"))
    oversized_tool_lock_id["compilerToolchain"]["id"] = "b" * 129
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.enumerate_tool_lock_leaves(
            json.dumps(
                oversized_tool_lock_id, separators=(",", ":")
            ).encode("utf-8")
        ),
    )

    def replace_refs(
        sources: tuple[object, ...],
        component_id: str,
        lock_refs: tuple[object, ...] | list[object],
    ) -> tuple[object, ...]:
        return tuple(
            source(item.component_id, item.component_kind, lock_refs)
            if item.component_id == component_id
            else item
            for item in sources
        )

    representative_refs = (
        ("asset-foundry", ref("asset", "foundry-v0.3.0-darwin-arm64", None)),
        (
            "compiler-lake",
            ref("compiler-executable", "lean", "bin/lake"),
        ),
        (
            "tool-anvil",
            ref("bundle-file", "foundry-v0.3.0-darwin-arm64", "anvil"),
        ),
        ("tool-anvil", ref("tool-executable", "anvil", "anvil")),
        (
            "runtime-libcrypto",
            ref(
                "tool-runtime-file",
                "wat2wasm",
                "lib/libcrypto.3.dylib",
            ),
        ),
    )
    for component_id, representative in representative_refs:
        original_refs = by_id[component_id].lock_refs
        missing_ref = tuple(
            lock_ref for lock_ref in original_refs if lock_ref != representative
        )
        expect_error(
            module,
            "PF-SBOM-CLOSURE",
            lambda component_id=component_id, missing_ref=missing_ref: (
                module.validate_direct_tool_lock_ref_coverage(
                    raw,
                    replace_refs(baseline, component_id, missing_ref),
                )
            ),
        )

        duplicated_refs = tuple(
            sorted(
                original_refs + (representative,),
                key=lambda lock_ref: (
                    lock_ref.kind,
                    lock_ref.id,
                    "" if lock_ref.path is None else lock_ref.path,
                ),
            )
        )
        expect_error(
            module,
            "PF-SBOM-CLOSURE",
            lambda component_id=component_id, duplicated_refs=duplicated_refs: (
                module.validate_direct_tool_lock_ref_coverage(
                    raw,
                    replace_refs(baseline, component_id, duplicated_refs),
                )
            ),
        )

        extra_ref = ref(
            representative.kind,
            "unknown",
            None if representative.kind == "asset" else "unknown",
        )
        extra_refs = tuple(
            sorted(
                original_refs + (extra_ref,),
                key=lambda lock_ref: (
                    lock_ref.kind,
                    lock_ref.id,
                    "" if lock_ref.path is None else lock_ref.path,
                ),
            )
        )
        expect_error(
            module,
            "PF-SBOM-CLOSURE",
            lambda component_id=component_id, extra_refs=extra_refs: (
                module.validate_direct_tool_lock_ref_coverage(
                    raw,
                    replace_refs(baseline, component_id, extra_refs),
                )
            ),
        )

    reversed_refs = replace_refs(
        baseline,
        "tool-anvil",
        tuple(reversed(by_id["tool-anvil"].lock_refs)),
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, reversed_refs),
    )

    same_asset_wrong_path = replace_refs(
        baseline,
        "tool-anvil",
        (
            ref("bundle-file", "foundry-v0.3.0-darwin-arm64", "cast"),
            ref("tool-executable", "anvil", "anvil"),
        ),
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            raw, same_asset_wrong_path
        ),
    )

    wrong_runtime_join = replace_refs(
        baseline,
        "runtime-libcrypto",
        (
            ref("bundle-file", "wabt-1.0.41-macos-arm64", "wat2wasm"),
            ref(
                "tool-runtime-file",
                "wat2wasm",
                "lib/libcrypto.3.dylib",
            ),
        ),
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            raw, wrong_runtime_join
        ),
    )

    shared_runtime_lock = json.loads(raw.decode("utf-8"))
    macho_files = shared_runtime_lock["machoPolicy"]["files"]
    anvil_macho = next(item for item in macho_files if item["path"] == "anvil")
    wat2wasm_macho = next(
        item for item in macho_files if item["path"] == "wat2wasm"
    )
    anvil_macho["externalLoads"] = copy.deepcopy(
        wat2wasm_macho["externalLoads"]
    )
    shared_tools = shared_runtime_lock["tools"]
    anvil_tool = next(item for item in shared_tools if item["id"] == "anvil")
    wat2wasm_tool = next(
        item for item in shared_tools if item["id"] == "wat2wasm"
    )
    anvil_tool["runtimeLibrarySubdir"] = "lib"
    anvil_tool["runtimeFiles"] = copy.deepcopy(wat2wasm_tool["runtimeFiles"])
    shared_runtime_raw = json.dumps(
        shared_runtime_lock, separators=(",", ":")
    ).encode("utf-8")
    shared_runtime_refs = (
        ref(
            "bundle-file",
            "openssl-3.6.3-homebrew-arm64-tahoe",
            "lib/libcrypto.3.dylib",
        ),
        ref("tool-runtime-file", "anvil", "lib/libcrypto.3.dylib"),
        ref("tool-runtime-file", "wat2wasm", "lib/libcrypto.3.dylib"),
    )
    shared_runtime_sources = replace_refs(
        baseline,
        "runtime-libcrypto",
        shared_runtime_refs,
    )
    module.validate_direct_tool_lock_ref_coverage(
        shared_runtime_raw, shared_runtime_sources
    )

    split_shared_runtime = tuple(
        item
        for item in shared_runtime_sources
        if item.component_id != "runtime-libcrypto"
    ) + (
        source(
            "runtime-libcrypto-anvil",
            "runtime-dylib",
            shared_runtime_refs[:2],
        ),
        source(
            "runtime-libcrypto-wat2wasm",
            "runtime-dylib",
            (shared_runtime_refs[0], shared_runtime_refs[2]),
        ),
    )
    split_shared_runtime = tuple(
        sorted(split_shared_runtime, key=lambda item: item.component_id)
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            shared_runtime_raw, split_shared_runtime
        ),
    )

    merged_solc = tuple(
        item
        for item in baseline
        if item.component_id not in {"asset-solc", "tool-solc"}
    ) + (
        source(
            "tool-solc",
            "tool-executable",
            by_id["asset-solc"].lock_refs + by_id["tool-solc"].lock_refs,
        ),
    )
    merged_solc = tuple(sorted(merged_solc, key=lambda item: item.component_id))
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, merged_solc),
    )

    runtime = by_id["runtime-libcrypto"]
    missing_runtime_owner = tuple(
        source(item.component_id, item.component_kind, runtime.lock_refs[:1])
        if item.component_id == runtime.component_id
        else item
        for item in baseline
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            raw, missing_runtime_owner
        ),
    )

    split_runtime_owner = tuple(
        item for item in baseline if item.component_id != runtime.component_id
    ) + (
        source(
            "runtime-libcrypto",
            "runtime-dylib",
            runtime.lock_refs[:1],
        ),
        source(
            "runtime-libcrypto-owner",
            "runtime-dylib",
            runtime.lock_refs[1:],
        ),
    )
    split_runtime_owner = tuple(
        sorted(split_runtime_owner, key=lambda item: item.component_id)
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(
            raw, split_runtime_owner
        ),
    )

    missing_component = tuple(
        item for item in baseline if item.component_id != "tool-cast"
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, missing_component),
    )

    duplicated_ref = tuple(
        source(
            item.component_id,
            item.component_kind,
            item.lock_refs + item.lock_refs[-1:],
        )
        if item.component_id == "tool-anvil"
        else item
        for item in baseline
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, duplicated_ref),
    )

    duplicate_owner = tuple(
        source(
            item.component_id,
            item.component_kind,
            by_id["asset-foundry"].lock_refs,
        )
        if item.component_id == "asset-lean"
        else item
        for item in baseline
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, duplicate_owner),
    )

    unknown_ref = tuple(
        sorted(
            baseline
            + (
                source(
                    "tool-unknown",
                    "tool-executable",
                    (
                        ref("bundle-file", "unknown-asset", "unknown"),
                        ref("tool-executable", "unknown", "unknown"),
                    ),
                ),
            ),
            key=lambda item: item.component_id,
        )
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, unknown_ref),
    )

    wrong_bundle_join = tuple(
        source(
            item.component_id,
            item.component_kind,
            (
                ref("bundle-file", "wabt-1.0.41-macos-arm64", "wat2wasm"),
                item.lock_refs[1],
            ),
        )
        if item.component_id == "tool-solc"
        else item
        for item in baseline
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, wrong_bundle_join),
    )

    malformed_ref = tuple(
        source(
            item.component_id,
            item.component_kind,
            (ref([], "lean-4.31.0-darwin-arm64", None),),
        )
        if item.component_id == "asset-lean"
        else item
        for item in baseline
    )
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.validate_direct_tool_lock_ref_coverage(raw, malformed_ref),
    )

    malformed_values = (
        replace_refs(
            baseline,
            "asset-lean",
            (ref("asset", [], None),),
        ),
        replace_refs(
            baseline,
            "tool-anvil",
            (
                ref("bundle-file", "foundry-v0.3.0-darwin-arm64", []),
                by_id["tool-anvil"].lock_refs[1],
            ),
        ),
        tuple(
            source([], item.component_kind, item.lock_refs)
            if item.component_id == "asset-lean"
            else item
            for item in baseline
        ),
        tuple(
            source(item.component_id, [], item.lock_refs)
            if item.component_id == "asset-lean"
            else item
            for item in baseline
        ),
        replace_refs(
            baseline,
            "asset-lean",
            list(by_id["asset-lean"].lock_refs),
        ),
    )
    for malformed_value in malformed_values:
        expect_error(
            module,
            "PF-SBOM-CLOSURE",
            lambda malformed_value=malformed_value: (
                module.validate_direct_tool_lock_ref_coverage(raw, malformed_value)
            ),
        )

    original_enumerator = module.enumerate_tool_lock_leaves

    def unexpected_enumerator(_: bytes) -> tuple[object, ...]:
        raise AssertionError("Tool Lock enumeration ran before the source limit")

    module.enumerate_tool_lock_leaves = unexpected_enumerator
    try:
        expect_error(
            module,
            "PF-SBOM-LIMIT",
            lambda: module.validate_direct_tool_lock_ref_coverage(
                b"not parsed",
                tuple(object() for _ in range(4_097)),
            ),
        )
    finally:
        module.enumerate_tool_lock_leaves = original_enumerator

    digest_mismatch = json.loads(raw.decode("utf-8"))
    next(
        tool for tool in digest_mismatch["tools"] if tool["id"] == "solc"
    )["executableSha256"] = "0" * 64
    expect_error(
        module,
        "PF-SBOM-CLOSURE",
        lambda: module.enumerate_tool_lock_leaves(
            json.dumps(digest_mismatch, separators=(",", ":")).encode("utf-8")
        ),
    )


def solc_asset_component() -> dict[str, object]:
    return {
        "id": "solc-0.8.34-asset",
        "kind": "download-asset",
        "name": "solc",
        "version": "0.8.34",
        "supplier": "Argot Collective",
        "source": {
            "kind": "tool-lock",
            "lockRefs": [
                {
                    "kind": "asset",
                    "id": "solc-0.8.34-macos-universal",
                    "path": None,
                }
            ],
        },
        "content": {"kind": "file", "digest": SOLC_CONTENT_DIGEST},
        "licenseSpdx": "GPL-3.0-or-later",
        "licenseTextComponentIds": ["gpl-3.0-text"],
        "redistributable": False,
        "dependencies": [],
    }


def solc_executable_component() -> dict[str, object]:
    return {
        "id": "solc-0.8.34-executable",
        "kind": "tool-executable",
        "name": "solc",
        "version": "0.8.34",
        "supplier": "Argot Collective",
        "source": {
            "kind": "tool-lock",
            "lockRefs": [
                {
                    "kind": "bundle-file",
                    "id": "solc-0.8.34-macos-universal",
                    "path": "solc",
                },
                {"kind": "tool-executable", "id": "solc", "path": "solc"},
            ],
        },
        "content": {"kind": "file", "digest": SOLC_CONTENT_DIGEST},
        "licenseSpdx": "GPL-3.0-or-later",
        "licenseTextComponentIds": ["gpl-3.0-text"],
        "redistributable": False,
        "dependencies": [
            {"kind": "derived-from", "to": "solc-0.8.34-asset"}
        ],
    }


def test_logical_component_identity(module: ModuleType) -> None:
    asset = module.derive_component_identity(solc_asset_component())
    executable = module.derive_component_identity(solc_executable_component())
    if asset.component_digest != SOLC_ASSET_COMPONENT_DIGEST:
        raise AssertionError("download-asset component identity drifted")
    if executable.component_digest != SOLC_EXECUTABLE_COMPONENT_DIGEST:
        raise AssertionError("tool-executable component identity drifted")
    if asset.component_digest == executable.component_digest:
        raise AssertionError("same content collapsed two logical component identities")
    role_only = solc_asset_component()
    role_only["kind"] = "tool-executable"
    if module.derive_component_identity(role_only).component_digest == asset.component_digest:
        raise AssertionError("component kind is absent from the logical identity preimage")
    if asset.bom_ref != "urn:proofforge:component:" + SOLC_ASSET_COMPONENT_DIGEST[7:]:
        raise AssertionError("component bom-ref did not use raw digest bytes")
    if executable.bom_ref != (
        "urn:proofforge:component:" + SOLC_EXECUTABLE_COMPONENT_DIGEST[7:]
    ):
        raise AssertionError("executable bom-ref did not use raw digest bytes")

    self_describing = solc_asset_component()
    self_describing["componentDigest"] = SOLC_ASSET_COMPONENT_DIGEST
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.derive_component_identity(self_describing),
    )
    mixed_key_types = solc_asset_component()
    mixed_key_types[1] = "unexpected"
    mixed_key_types["unexpected"] = True
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.derive_component_identity(mixed_key_types),
    )

    changing = solc_asset_component()
    original_snapshot = module._canonical_pf_jcs_snapshot
    snapshot_calls = 0

    def mutate_between_snapshots(value: object) -> tuple[object, bytes]:
        nonlocal snapshot_calls
        result = original_snapshot(value)
        if value is changing:
            snapshot_calls += 1
            if snapshot_calls == 1:
                changing.pop("id")
        return result

    module._canonical_pf_jcs_snapshot = mutate_between_snapshots
    try:
        expect_error(
            module,
            "PF-SBOM-SCHEMA",
            lambda: module.derive_component_identity(changing),
        )
    finally:
        module._canonical_pf_jcs_snapshot = original_snapshot
    self_describing = solc_asset_component()
    self_describing["bomRef"] = (
        "urn:proofforge:component:" + SOLC_ASSET_COMPONENT_DIGEST[7:]
    )
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.derive_component_identity(self_describing),
    )

    candidate_digest = "sha256:" + "0123456789abcdef" * 4
    expected_root = "urn:proofforge:candidate:" + "0123456789abcdef" * 4
    if module.candidate_root_bom_ref(candidate_digest) != expected_root:
        raise AssertionError("synthetic candidate root identity drifted")
    expect_error(
        module,
        "PF-SBOM-SCHEMA",
        lambda: module.candidate_root_bom_ref("0123456789abcdef" * 4),
    )


def main() -> int:
    module = load_core()
    test_pf_jcs(module)
    test_tool_lock_identity(module)
    test_locked_cyclonedx_validator()
    test_direct_tool_lock_leaf_coverage(module)
    test_logical_component_identity(module)
    print("supply-chain-core-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
