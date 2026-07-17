#!/usr/bin/env python3
"""Pre-acceptance RED/GREEN tests for the D0-08 supply-chain identity core.

This is intentionally independent from the legacy TASK-D0-05 generator.  It
pins the first D0-08 implementation seam only: strict JSON/PF-JCS, the sole
ToolLockV2Digest authority, typed raw-vs-structured lock binding, logical
component identity, and the synthetic candidate BOM root.  It does not claim
the full TST-SBOM-002 closure or publication acceptance.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType
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

    invalid = (
        b'{"a":1,"a":1}',
        b'{"a":1.0}',
        b'{"a":NaN}',
        b'{"a":9007199254740992}',
        b'{"a":"\\ud800"}',
        b'{"a":"\xff"}',
    )
    for raw in invalid:
        expect_error(
            module,
            "PF-SBOM-JSON",
            lambda raw=raw: module.decode_json_document(raw),
        )


def test_tool_lock_identity(module: ModuleType) -> None:
    raw = (ROOT / "toolchains.lock.json").read_bytes()
    identity = module.compute_tool_lock_identity(raw)
    if identity.toolchain_lock_sha256 != RAW_TOOL_LOCK_SHA256:
        raise AssertionError("raw tool lock SHA-256 drifted without freeze review")
    if identity.tool_lock_v2_digest != TOOL_LOCK_V2_DIGEST:
        raise AssertionError("ToolLockV2Digest drifted without freeze review")

    value = json.loads(raw.decode("utf-8"))
    alternate_layout = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    alternate = module.compute_tool_lock_identity(alternate_layout)
    if alternate.tool_lock_v2_digest != identity.tool_lock_v2_digest:
        raise AssertionError("semantic ToolLockV2Digest depends on JSON layout")
    if alternate.toolchain_lock_sha256 == identity.toolchain_lock_sha256:
        raise AssertionError("raw tool lock SHA-256 ignored exact retained bytes")

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
    test_logical_component_identity(module)
    print("supply-chain-core-self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
