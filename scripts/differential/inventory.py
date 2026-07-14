#!/usr/bin/env python3
"""Generate and verify the tracked native-differential asset inventory."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from contracts import (
    INVENTORY_SCHEMA,
    migrate_manifest,
    validate_inventory,
    validate_reference,
    validate_scenario,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPO_ROOT / "testkit/differential/inventory.v1.json"


def relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def asset(
    asset_id: str,
    target_family: str,
    kind: str,
    path: Path,
    maturity: str,
    evidence: str,
    notes: str,
    **extra: object,
) -> dict[str, object]:
    result: dict[str, object] = {
        "id": asset_id,
        "targetFamily": target_family,
        "kind": kind,
        "path": relative(path),
        "maturity": maturity,
        "semanticEvidence": evidence,
        "notes": notes,
    }
    result.update(extra)
    return result


def recipe_names(prefixes: tuple[str, ...]) -> list[str]:
    text = (REPO_ROOT / "justfile").read_text(encoding="utf-8")
    names = re.findall(r"^([a-z0-9][a-z0-9-]*):", text, flags=re.MULTILINE)
    return sorted(name for name in names if name.startswith(prefixes))


def generate_inventory() -> dict[str, object]:
    assets: list[dict[str, object]] = []

    for schema in sorted((REPO_ROOT / "testkit/differential/schemas").glob("*.schema.json")):
        assets.append(
            asset(
                f"schema-{schema.name.removesuffix('.schema.json')}",
                "portable",
                "schema",
                schema,
                "versionedContract",
                "none",
                "test-only versioned comparison contract; production compiler imports are forbidden",
            )
        )

    for manifest in sorted((REPO_ROOT / "testkit/compare/near").glob("*/reference-manifest.json")):
        migrated = migrate_manifest(manifest, REPO_ROOT)
        reference = migrated["reference"]
        assets.append(
            asset(
                f"near-reference-{manifest.parent.name}",
                "near",
                "nativeReference",
                manifest,
                "referenceManifestV0",
                "none",
                "near-sdk Rust reference; explicit v0 migration remains semantically ineligible until provenance and normalized coverage are complete",
                sourcePaths=[reference["source"]["path"]],
                sourceSchema=reference["migration"]["sourceSchema"],
            )
        )

    for manifest in sorted((REPO_ROOT / "references/solana/pinocchio").glob("*/reference-manifest.json")):
        migrated = migrate_manifest(manifest, REPO_ROOT)
        reference = migrated["reference"]
        assets.append(
            asset(
                f"solana-reference-{manifest.parent.name}",
                "solana",
                "nativeReference",
                manifest,
                "referenceManifestV0",
                "partial",
                "Pinocchio Rust reference with structural gates; v0 manifest lacks complete provenance and normalized observation coverage",
                sourcePaths=[reference["source"]["path"]],
                sourceSchema=reference["migration"]["sourceSchema"],
            )
        )

    for source in sorted((REPO_ROOT / "benchmarks/native/evm").glob("*.sol")):
        assets.append(
            asset(
                f"evm-reference-{source.stem.lower()}",
                "evm",
                "nativeReference",
                source,
                "structuralReference",
                "none",
                "handwritten Solidity reference without a v1 provenance manifest or normalized differential report",
            )
        )

    cmp2_root = REPO_ROOT / "testkit/differential/counter"
    for manifest in sorted((cmp2_root / "references").glob("*.v1.json")):
        reference = json.loads(manifest.read_text(encoding="utf-8"))
        validate_reference(reference, relative(manifest))
        assets.append(
            asset(
                f"cmp2-reference-{reference['targetFamily']}-counter",
                reference["targetFamily"],
                "nativeReference",
                manifest,
                "referenceManifestV1",
                "verified",
                "CMP-2 independent Counter reference with source digest, license, and pinned toolchain",
                sourcePaths=[reference["source"]["path"]],
            )
        )

    cmp2_scenario = cmp2_root / "scenario.v1.json"
    if cmp2_scenario.is_file():
        scenario_document = json.loads(cmp2_scenario.read_text(encoding="utf-8"))
        validate_scenario(scenario_document, relative(cmp2_scenario))
        assets.append(
            asset(
                "cmp2-scenario-counter-primary-triad",
                "portable",
                "scenario",
                cmp2_scenario,
                "portableScenarioV1",
                "verified",
                "four-step Counter lifecycle with complete eight-dimension observation coverage",
            )
        )
        assets.append(
            asset(
                "cmp2-runner-counter-primary-triad",
                "portable",
                "runner",
                REPO_ROOT / "scripts/differential/counter_pilot.py",
                "deterministicRunner",
                "verified",
                "direct Authored artifacts compared with native Solidity, Pinocchio, and near-sdk execution",
            )
        )
        assets.append(
            asset(
                "cmp2-gate-counter-primary-triad",
                "portable",
                "gate",
                REPO_ROOT / "justfile",
                "focusedGate",
                "verified",
                "focused fail-closed CMP-2 gate",
                selectors=["differential-counter"],
            )
        )

    cmp3_root = REPO_ROOT / "testkit/differential/value-vault"
    for manifest in sorted((cmp3_root / "references").glob("*.v1.json")):
        reference = json.loads(manifest.read_text(encoding="utf-8"))
        validate_reference(reference, relative(manifest))
        assets.append(
            asset(
                f"cmp3-reference-{reference['targetFamily']}-value-vault",
                reference["targetFamily"],
                "nativeReference",
                manifest,
                "referenceManifestV1",
                "verified",
                "CMP-3 independent ValueVault reference with pinned provenance and primary-triad VM evidence",
                sourcePaths=[reference["source"]["path"]],
            )
        )

    cmp3_scenario = cmp3_root / "scenario.v1.json"
    if cmp3_scenario.is_file():
        scenario_document = json.loads(cmp3_scenario.read_text(encoding="utf-8"))
        validate_scenario(scenario_document, relative(cmp3_scenario))
        assets.append(
            asset(
                "cmp3-scenario-value-vault-primary-triad",
                "portable",
                "scenario",
                cmp3_scenario,
                "portableScenarioV1",
                "verified",
                "stateful ValueVault lifecycle and arithmetic-underflow case executed on both implementations for every primary target",
            )
        )
        assets.append(
            asset(
                "cmp3-runner-value-vault-primary-triad",
                "portable",
                "runner",
                REPO_ROOT / "scripts/differential/value_vault_pilot.py",
                "deterministicRunner",
                "verified",
                "direct Authored artifacts compared with native Solidity, Pinocchio, and near-sdk execution",
            )
        )
        assets.append(
            asset(
                "cmp3-gate-value-vault-primary-triad",
                "portable",
                "gate",
                REPO_ROOT / "justfile",
                "focusedGate",
                "verified",
                "focused fail-closed CMP-3 ValueVault gate",
                selectors=["differential-value-vault"],
            )
        )

    cmp3_ownable_root = REPO_ROOT / "testkit/differential/ownable"
    for manifest in sorted((cmp3_ownable_root / "references").glob("*.v1.json")):
        reference = json.loads(manifest.read_text(encoding="utf-8"))
        validate_reference(reference, relative(manifest))
        assets.append(
            asset(
                f"cmp3-reference-{reference['targetFamily']}-ownable",
                reference["targetFamily"],
                "nativeReference",
                manifest,
                "referenceManifestV1",
                "verified",
                "CMP-3 independent Ownable reference with pinned provenance and primary-triad VM evidence",
                sourcePaths=[reference["source"]["path"]],
            )
        )

    cmp3_ownable_scenario = cmp3_ownable_root / "scenario.v1.json"
    if cmp3_ownable_scenario.is_file():
        scenario_document = json.loads(cmp3_ownable_scenario.read_text(encoding="utf-8"))
        validate_scenario(scenario_document, relative(cmp3_ownable_scenario))
        assets.append(
            asset(
                "cmp3-scenario-ownable-primary-triad",
                "portable",
                "scenario",
                cmp3_ownable_scenario,
                "portableScenarioV1",
                "verified",
                "ten-step authorization lifecycle and negative cases executed on both implementations for every primary target",
            )
        )
        assets.append(
            asset(
                "cmp3-runner-ownable-primary-triad",
                "portable",
                "runner",
                REPO_ROOT / "scripts/differential/ownable_pilot.py",
                "deterministicRunner",
                "verified",
                "direct Authored artifacts compared with native Solidity, Pinocchio, and near-sdk execution",
            )
        )
        assets.append(
            asset(
                "cmp3-gate-ownable-primary-triad",
                "portable",
                "gate",
                REPO_ROOT / "justfile",
                "focusedGate",
                "verified",
                "focused fail-closed CMP-3 Ownable gate",
                selectors=["differential-ownable"],
            )
        )

    cmp3_pausable_root = REPO_ROOT / "testkit/differential/pausable"
    for manifest in sorted((cmp3_pausable_root / "references").glob("*.v1.json")):
        reference = json.loads(manifest.read_text(encoding="utf-8"))
        validate_reference(reference, relative(manifest))
        assets.append(
            asset(
                f"cmp3-reference-{reference['targetFamily']}-pausable",
                reference["targetFamily"],
                "nativeReference",
                manifest,
                "referenceManifestV1",
                "none",
                "CMP-3e independent Pausable reference with pinned provenance; VM evidence is pending",
                sourcePaths=[reference["source"]["path"]],
            )
        )

    cmp3_pausable_scenario = cmp3_pausable_root / "scenario.v1.json"
    if cmp3_pausable_scenario.is_file():
        scenario_document = json.loads(cmp3_pausable_scenario.read_text(encoding="utf-8"))
        validate_scenario(scenario_document, relative(cmp3_pausable_scenario))
        assets.append(
            asset(
                "cmp3-scenario-pausable-primary-triad",
                "portable",
                "scenario",
                cmp3_pausable_scenario,
                "portableScenarioV1",
                "none",
                "nine-step Pausable lifecycle is pinned but has not completed primary-triad VM execution",
            )
        )

    for scenario in sorted((REPO_ROOT / "testkit/scenarios").glob("*.toml")):
        assets.append(
            asset(
                f"portable-scenario-{scenario.stem}",
                "portable",
                "scenario",
                scenario,
                "portableScenarioV0",
                "none",
                "existing artifact/runtime scenario; it predates the versioned logical-step and coverage contract",
            )
        )

    runner_specs = [
        ("near-offline-runner", "near", "testkit/compare/src/main.rs", "deterministicRunner", "partial", "offline Wasmtime size/fuel comparison runner"),
        ("near-sandbox-runner", "near", "testkit/compare/near/sandbox/src/main.rs", "liveRunner", "partial", "NEAR Sandbox runner; historical reports do not satisfy v1 coverage"),
        ("near-matrix-generator", "near", "scripts/near/compare-matrix-snapshot.py", "deterministicRunner", "none", "historical matrix generator with fail-closed measurement-only labels"),
        ("evm-revm-runner", "evm", "testkit/harness-evm/src/lib.rs", "deterministicRunner", "partial", "revm execution harness without shared v1 observation output"),
        ("evm-foundry-runner", "evm", "scripts/evm/foundry-smoke.sh", "liveRunner", "partial", "Foundry behavior gate; not yet paired with all native references"),
        ("evm-anvil-runner", "evm", "scripts/evm/anvil-deploy-smoke.sh", "liveRunner", "partial", "Anvil deployment gate; not a normalized native differential"),
        ("stylus-vm-runner", "stylus", "tools/stylus-vm-runner/src/main.rs", "deterministicRunner", "partial", "Stylus VM conformance runner; shared v1 output is pending CMP-STYLUS"),
        ("stylus-host-runner", "stylus", "runtime/stylus-host/src/main.rs", "deterministicRunner", "partial", "Rust host semantic runner used by focused differentials"),
    ]
    for spec in runner_specs:
        runner_id, family, path, maturity, evidence, notes = spec
        assets.append(asset(runner_id, family, "runner", REPO_ROOT / path, maturity, evidence, notes))

    for script in sorted((REPO_ROOT / "scripts/solana").glob("pinocchio*equivalence.sh")):
        live = "live" in script.name
        assets.append(
            asset(
                f"solana-runner-{script.stem}",
                "solana",
                "runner",
                script,
                "liveRunner" if live else "deterministicRunner",
                "partial",
                "Pinocchio dual-artifact behavior runner" if live else "Pinocchio static structural equivalence runner",
            )
        )

    for script in sorted((REPO_ROOT / "scripts/stylus").glob("*differential.sh")):
        assets.append(
            asset(
                f"stylus-runner-{script.stem}",
                "stylus",
                "runner",
                script,
                "deterministicRunner",
                "partial",
                "focused abstract/Rust/direct-Wasm comparison without a v1 provenance manifest",
            )
        )

    assets.append(
        asset(
            "near-historical-matrix",
            "near",
            "reportCatalog",
            REPO_ROOT / "testkit/compare/MATRIX.md",
            "measurementOnly",
            "none",
            "28 historical live reports are explicitly excluded from semantic verification because normalized coverage is absent",
        )
    )

    gate_specs = [
        ("near-comparison-gates", "near", ("near-compare",), "NEAR offline, sandbox, and matrix recipes"),
        ("solana-comparison-gates", "solana", ("solana-pinocchio",), "Solana Pinocchio static and live equivalence recipes"),
        ("stylus-comparison-gates", "stylus", ("stylus-",), "Stylus differential, VM, Nitro, and SDK recipes"),
        ("evm-comparison-gates", "evm", ("evm-foundry", "evm-anvil", "evm-dynamic-constructor-anvil"), "EVM Foundry and Anvil execution recipes"),
    ]
    for gate_id, family, prefixes, notes in gate_specs:
        assets.append(
            asset(
                gate_id,
                family,
                "gate",
                REPO_ROOT / "justfile",
                "ciGate",
                "partial",
                notes + "; recipe presence does not imply normalized semantic verification",
                selectors=recipe_names(prefixes),
            )
        )
    assets.append(
        asset(
            "github-comparison-ci",
            "portable",
            "gate",
            REPO_ROOT / ".github/workflows/ci.yml",
            "ciGate",
            "partial",
            "hosted CI lanes that invoke existing target gates; normalized v1 comparison promotion is not yet wired",
        )
    )
    assets.append(
        asset(
            "woodpecker-comparison-ci",
            "portable",
            "gate",
            REPO_ROOT / ".woodpecker.yml",
            "ciGate",
            "partial",
            "Woodpecker invokes aggregate gates; normalized v1 comparison promotion is not yet wired",
        )
    )

    assets.sort(key=lambda item: item["id"])
    inventory: dict[str, object] = {
        "schema": INVENTORY_SCHEMA,
        "scope": "tracked comparison assets through verified ValueVault and Ownable plus pinned Pausable CMP-3 slices",
        "summary": {
            "assetCount": len(assets),
            "semanticVerifiedCount": sum(1 for item in assets if item["semanticEvidence"] == "verified"),
            "byTargetFamily": {
                family: sum(1 for item in assets if item["targetFamily"] == family)
                for family in ("portable", "evm", "solana", "near", "stylus")
            },
        },
        "assets": assets,
    }
    validate_inventory(inventory)
    for item in assets:
        if not (REPO_ROOT / str(item["path"])).is_file():
            raise RuntimeError(f"inventory asset does not exist: {item['path']}")
        for source_path in item.get("sourcePaths", []):
            if not (REPO_ROOT / str(source_path)).is_file():
                raise RuntimeError(f"inventory reference source does not exist: {source_path}")
    return inventory


def encoded(inventory: dict[str, object]) -> str:
    return json.dumps(inventory, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else REPO_ROOT / args.output
    expected = encoded(generate_inventory())
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != expected:
            print(f"stale differential inventory: regenerate {relative(output)}", file=sys.stderr)
            return 1
        print("differential-inventory: ok")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(expected, encoding="utf-8")
    print(f"wrote {relative(output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
