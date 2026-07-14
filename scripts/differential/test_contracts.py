#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from contracts import (  # noqa: E402
    ContractError,
    OBSERVATION_SCHEMA,
    REFERENCE_SCHEMA,
    SCENARIO_SCHEMA,
    migrate_manifest,
    validate_observation,
    validate_reference,
    validate_scenario,
)
from inventory import generate_inventory  # noqa: E402


def valid_reference() -> dict[str, object]:
    return {
        "schema": REFERENCE_SCHEMA,
        "id": "evm-counter-solidity",
        "targetFamily": "evm",
        "program": "counter",
        "framework": "solidity",
        "source": {"path": "benchmarks/native/evm/Counter.sol", "language": "solidity"},
        "provenance": {
            "status": "complete",
            "origin": {"name": "ProofForge benchmark", "url": None},
            "revision": "local-v1",
            "license": "Apache-2.0",
            "toolchain": [{"name": "solc", "version": "0.8.30"}],
            "missing": [],
        },
        "semanticEligibility": {"eligible": True, "reasons": []},
    }


def valid_scenario() -> dict[str, object]:
    return {
        "schema": SCENARIO_SCHEMA,
        "id": "portable-counter",
        "kind": "portable",
        "targetFamily": "portable",
        "steps": [
            {"id": "initialize", "action": "initialize"},
            {"id": "get-zero", "action": "get"},
        ],
        "requiredObservations": ["callStatus", "returnValue", "state"],
        "allowedDivergences": [],
    }


def valid_observation() -> dict[str, object]:
    return {
        "schema": OBSERVATION_SCHEMA,
        "scenarioId": "portable-counter",
        "runner": {"name": "synthetic", "status": "executed"},
        "provenanceComplete": True,
        "observedMatch": True,
        "observationCoverage": {
            "required": ["callStatus", "returnValue", "state"],
            "covered": ["callStatus", "returnValue", "state"],
            "missing": [],
        },
        "steps": [
            {"id": "initialize", "observations": {"callStatus": {"status": "success"}}},
            {"id": "get-zero", "observations": {"returnValue": 0, "state": {"count": 0}}},
        ],
        "semanticMatch": True,
    }


class ContractTests(unittest.TestCase):
    def test_checked_in_schema_documents_match_contract_ids(self) -> None:
        expected = {
            "reference-provenance.v1.schema.json": REFERENCE_SCHEMA,
            "logical-scenario.v1.schema.json": SCENARIO_SCHEMA,
            "normalized-observation.v1.schema.json": OBSERVATION_SCHEMA,
            "runner-result.v1.schema.json": "proof-forge.differential.runner-result.v1",
            "inventory.v1.schema.json": "proof-forge.differential.inventory.v1",
        }
        schema_root = REPO_ROOT / "testkit/differential/schemas"
        for filename, schema_id in expected.items():
            with (schema_root / filename).open(encoding="utf-8") as handle:
                document = json.load(handle)
            self.assertEqual(schema_id, document["$id"])

    def test_valid_v1_contracts(self) -> None:
        validate_reference(valid_reference())
        validate_scenario(valid_scenario())
        validate_observation(valid_observation())

    def test_missing_provenance_is_rejected(self) -> None:
        reference = valid_reference()
        del reference["provenance"]
        with self.assertRaisesRegex(ContractError, "provenance"):
            validate_reference(reference)

    def test_duplicate_step_ids_are_rejected(self) -> None:
        scenario = valid_scenario()
        scenario["steps"][1]["id"] = "initialize"
        with self.assertRaisesRegex(ContractError, "duplicate step IDs"):
            validate_scenario(scenario)

    def test_unknown_observation_dimension_is_rejected(self) -> None:
        observation = valid_observation()
        observation["observationCoverage"]["required"].append("nearPromise")
        with self.assertRaisesRegex(ContractError, "unknown observation dimensions"):
            validate_observation(observation)

    def test_semantic_success_with_missing_coverage_is_rejected(self) -> None:
        observation = valid_observation()
        observation["observationCoverage"]["covered"].remove("state")
        observation["observationCoverage"]["missing"] = ["state"]
        with self.assertRaisesRegex(ContractError, "incomplete observation coverage"):
            validate_observation(observation)

    def test_runner_skip_cannot_be_semantic_success(self) -> None:
        observation = valid_observation()
        observation["runner"] = {"name": "synthetic", "status": "skipped", "reason": "tool unavailable"}
        with self.assertRaisesRegex(ContractError, "runner skips"):
            validate_observation(observation)

    def test_all_near_v0_manifests_migrate_fail_closed(self) -> None:
        paths = sorted((REPO_ROOT / "testkit/compare/near").glob("*/reference-manifest.json"))
        self.assertEqual(25, len(paths))
        for path in paths:
            migrated = migrate_manifest(path, REPO_ROOT)
            self.assertFalse(migrated["reference"]["semanticEligibility"]["eligible"])
            self.assertFalse(migrated["observation"]["semanticMatch"])

    def test_all_solana_v0_manifests_migrate_fail_closed(self) -> None:
        paths = sorted((REPO_ROOT / "references/solana/pinocchio").glob("*/reference-manifest.json"))
        self.assertEqual(7, len(paths))
        for path in paths:
            migrated = migrate_manifest(path, REPO_ROOT)
            self.assertFalse(migrated["reference"]["semanticEligibility"]["eligible"])
            self.assertFalse(migrated["observation"]["semanticMatch"])

    def test_generated_inventory_has_no_semantic_overclaim(self) -> None:
        inventory = generate_inventory()
        self.assertEqual(30, inventory["summary"]["semanticVerifiedCount"])
        verified_ids = {
            item["id"] for item in inventory["assets"] if item["semanticEvidence"] == "verified"
        }
        self.assertEqual(
            {
                "cmp3-gate-ownable-primary-triad",
                "cmp3-gate-pausable-primary-triad",
                "cmp3-gate-reentrancy-guard-primary-triad",
                "cmp3-reference-evm-value-vault",
                "cmp3-reference-evm-ownable",
                "cmp3-reference-evm-pausable",
                "cmp3-reference-evm-reentrancy-guard",
                "cmp3-reference-near-value-vault",
                "cmp3-reference-near-ownable",
                "cmp3-reference-near-pausable",
                "cmp3-reference-near-reentrancy-guard",
                "cmp3-reference-solana-value-vault",
                "cmp3-reference-solana-ownable",
                "cmp3-reference-solana-pausable",
                "cmp3-reference-solana-reentrancy-guard",
                "cmp3-runner-ownable-primary-triad",
                "cmp3-runner-pausable-primary-triad",
                "cmp3-runner-reentrancy-guard-primary-triad",
                "cmp3-scenario-ownable-primary-triad",
                "cmp3-scenario-pausable-primary-triad",
                "cmp3-scenario-reentrancy-guard-primary-triad",
                "cmp3-scenario-value-vault-primary-triad",
                "cmp3-runner-value-vault-primary-triad",
                "cmp3-gate-value-vault-primary-triad",
            },
            {asset_id for asset_id in verified_ids if asset_id.startswith("cmp3-")},
        )
        families = inventory["summary"]["byTargetFamily"]
        for family in ("evm", "solana", "near", "stylus"):
            self.assertGreater(families[family], 0)

    def test_cmp2_manifests_pin_the_checked_in_reference_sources(self) -> None:
        root = REPO_ROOT / "testkit/differential/counter"
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        for family in ("evm", "solana", "near"):
            manifest = json.loads(
                (root / "references" / f"{family}.v1.json").read_text(encoding="utf-8")
            )
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")

    def test_cmp3_value_vault_scenario_and_references_are_pinned(self) -> None:
        root = REPO_ROOT / "testkit/differential/value-vault"
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        self.assertEqual(13, len(scenario["steps"]))
        rejected = next(step for step in scenario["steps"] if step["id"] == "release-too-much")
        self.assertEqual("arithmetic-underflow", rejected["expectError"])

        manifests = sorted((root / "references").glob("*.v1.json"))
        self.assertEqual(["evm.v1.json", "near.v1.json", "solana.v1.json"], [p.name for p in manifests])
        for manifest_path in manifests:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")
            source_text = source.read_text(encoding="utf-8")
            self.assertNotIn("proof_forge::", source_text)
            self.assertNotIn("ProofForge/", source_text)

        evm_source = (REPO_ROOT / "benchmarks/native/evm/ValueVault.sol").read_text(encoding="utf-8")
        near_source = (
            REPO_ROOT / "testkit/compare/near/value-vault/src/lib.rs"
        ).read_text(encoding="utf-8")
        for method in ("charge_fee", "release", "snapshot", "get_net_value"):
            self.assertIn(f"{method}(", evm_source)
            self.assertIn(f"{method}(", near_source)
        for event in (
            "VaultInitialized",
            "ValueDeposited",
            "ValueCharged",
            "ValueReleased",
            "ValueSnapshot",
        ):
            self.assertIn(event, evm_source)
            self.assertIn(event, near_source)

    def test_cmp3_ownable_scenario_and_references_are_pinned(self) -> None:
        root = REPO_ROOT / "testkit/differential/ownable"
        self.assertFalse(
            (REPO_ROOT / "testkit/compare/near/ownable/reference-manifest.json").exists()
        )
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        self.assertEqual(10, len(scenario["steps"]))
        rejected = {
            step["id"]: step["expectError"]
            for step in scenario["steps"]
            if "expectError" in step
        }
        self.assertEqual(
            {
                "unauthorized-transfer": "authorization",
                "zero-address-transfer": "zero-address",
                "old-owner-renounce": "authorization",
                "reinitialize-after-renounce": "already-initialized",
            },
            rejected,
        )
        self.assertEqual(len(scenario["steps"]), len(scenario["allowedDivergences"]))

        manifests = sorted((root / "references").glob("*.v1.json"))
        self.assertEqual(
            ["evm.v1.json", "near.v1.json", "solana.v1.json"],
            [path.name for path in manifests],
        )
        for manifest_path in manifests:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")
            source_text = source.read_text(encoding="utf-8")
            self.assertNotIn("proof_forge::", source_text)
            self.assertNotIn("ProofForge/", source_text)

        evm_source = (REPO_ROOT / "benchmarks/native/evm/Ownable.sol").read_text(
            encoding="utf-8"
        )
        solana_source = (
            REPO_ROOT / "benchmarks/native/solana/ownable/src/lib.rs"
        ).read_text(encoding="utf-8")
        near_source = (
            REPO_ROOT / "testkit/compare/near/ownable/src/lib.rs"
        ).read_text(encoding="utf-8")
        self.assertIn("bool private initialized", evm_source)
        self.assertIn("event OwnershipTransferred", evm_source)
        self.assertIn("const STATE_LEN: usize = 16", solana_source)
        self.assertIn("state.owned_by(program_id)", solana_source)
        self.assertIn("fn ownership_transferred", solana_source)
        self.assertIn("EVENT_JSON:", near_source)
        self.assertIn("OwnershipTransferred", near_source)
        near_compare = (REPO_ROOT / "testkit/compare/src/main.rs").read_text(encoding="utf-8")
        self.assertIn(
            '"testkit/differential/ownable/references/near.v1.json"', near_compare
        )

        inventory = generate_inventory()
        ownable_assets = {
            item["id"]: item["semanticEvidence"]
            for item in inventory["assets"]
            if item["id"].startswith("cmp3-") and "ownable" in item["id"]
        }
        self.assertEqual(
            {
                "cmp3-gate-ownable-primary-triad": "verified",
                "cmp3-reference-evm-ownable": "verified",
                "cmp3-reference-near-ownable": "verified",
                "cmp3-reference-solana-ownable": "verified",
                "cmp3-runner-ownable-primary-triad": "verified",
                "cmp3-scenario-ownable-primary-triad": "verified",
            },
            ownable_assets,
        )

    def test_cmp3_pausable_scenario_and_references_are_pinned(self) -> None:
        root = REPO_ROOT / "testkit/differential/pausable"
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        self.assertEqual(9, len(scenario["steps"]))
        rejected = {
            step["id"]: step["expectError"]
            for step in scenario["steps"]
            if "expectError" in step
        }
        self.assertEqual(
            {
                "unpause-while-unpaused": "not-paused",
                "pause-while-paused": "already-paused",
            },
            rejected,
        )
        self.assertEqual(len(scenario["steps"]), len(scenario["allowedDivergences"]))

        manifests = sorted((root / "references").glob("*.v1.json"))
        self.assertEqual(
            ["evm.v1.json", "near.v1.json", "solana.v1.json"],
            [path.name for path in manifests],
        )
        for manifest_path in manifests:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")
            source_text = source.read_text(encoding="utf-8")
            self.assertNotIn("proof_forge::", source_text)
            self.assertNotIn("ProofForge/", source_text)

        evm_source = (REPO_ROOT / "benchmarks/native/evm/Pausable.sol").read_text(
            encoding="utf-8"
        )
        solana_source = (
            REPO_ROOT / "benchmarks/native/solana/pausable/src/lib.rs"
        ).read_text(encoding="utf-8")
        near_source = (
            REPO_ROOT / "testkit/compare/near/pausable/src/lib.rs"
        ).read_text(encoding="utf-8")
        self.assertIn("error AlreadyPaused", evm_source)
        self.assertIn("error NotPaused", evm_source)
        self.assertIn("const STATE_LEN: usize = 8", solana_source)
        self.assertIn("state.owned_by(program_id)", solana_source)
        self.assertIn('env::panic_str("already paused")', near_source)
        self.assertIn('env::panic_str("not paused")', near_source)
        near_compare = (REPO_ROOT / "testkit/compare/src/main.rs").read_text(encoding="utf-8")
        self.assertIn(
            '"testkit/differential/pausable/references/near.v1.json"', near_compare
        )

        inventory = generate_inventory()
        pausable_assets = {
            item["id"]: item["semanticEvidence"]
            for item in inventory["assets"]
            if item["id"].startswith("cmp3-") and "pausable" in item["id"]
        }
        self.assertEqual(
            {
                "cmp3-gate-pausable-primary-triad": "verified",
                "cmp3-reference-evm-pausable": "verified",
                "cmp3-reference-near-pausable": "verified",
                "cmp3-reference-solana-pausable": "verified",
                "cmp3-runner-pausable-primary-triad": "verified",
                "cmp3-scenario-pausable-primary-triad": "verified",
            },
            pausable_assets,
        )

    def test_cmp3_reentrancy_guard_scenario_and_references_are_pinned(self) -> None:
        root = REPO_ROOT / "testkit/differential/reentrancy-guard"
        self.assertFalse(
            (REPO_ROOT / "testkit/compare/near/reentrancy-guard/reference-manifest.json").exists()
        )
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        self.assertEqual(9, len(scenario["steps"]))
        rejected = {
            step["id"]: step["expectError"]
            for step in scenario["steps"]
            if "expectError" in step
        }
        self.assertEqual(
            {
                "release-while-unlocked": "lock-not-held",
                "acquire-while-locked": "reentrant-call",
            },
            rejected,
        )
        self.assertEqual(len(scenario["steps"]), len(scenario["allowedDivergences"]))

        manifests = sorted((root / "references").glob("*.v1.json"))
        self.assertEqual(
            ["evm.v1.json", "near.v1.json", "solana.v1.json"],
            [path.name for path in manifests],
        )
        for manifest_path in manifests:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")
            source_text = source.read_text(encoding="utf-8")
            self.assertNotIn("proof_forge::", source_text)
            self.assertNotIn("ProofForge/", source_text)

        evm_source = (
            REPO_ROOT / "benchmarks/native/evm/ReentrancyGuard.sol"
        ).read_text(encoding="utf-8")
        solana_source = (
            REPO_ROOT / "benchmarks/native/solana/reentrancy-guard/src/lib.rs"
        ).read_text(encoding="utf-8")
        near_source = (
            REPO_ROOT / "testkit/compare/near/reentrancy-guard/src/lib.rs"
        ).read_text(encoding="utf-8")
        self.assertIn("error ReentrantCall", evm_source)
        self.assertIn("error LockNotHeld", evm_source)
        self.assertIn("const STATE_LEN: usize = 8", solana_source)
        self.assertIn("state.owned_by(program_id)", solana_source)
        self.assertIn('env::panic_str("reentrant call")', near_source)
        self.assertIn('env::panic_str("lock not held")', near_source)
        near_compare = (REPO_ROOT / "testkit/compare/src/main.rs").read_text(encoding="utf-8")
        self.assertIn(
            '"testkit/differential/reentrancy-guard/references/near.v1.json"', near_compare
        )

        inventory = generate_inventory()
        guard_assets = {
            item["id"]: item["semanticEvidence"]
            for item in inventory["assets"]
            if item["id"].startswith("cmp3-") and "reentrancy-guard" in item["id"]
        }
        self.assertEqual(
            {
                "cmp3-gate-reentrancy-guard-primary-triad": "verified",
                "cmp3-reference-evm-reentrancy-guard": "verified",
                "cmp3-reference-near-reentrancy-guard": "verified",
                "cmp3-reference-solana-reentrancy-guard": "verified",
                "cmp3-runner-reentrancy-guard-primary-triad": "verified",
                "cmp3-scenario-reentrancy-guard-primary-triad": "verified",
            },
            guard_assets,
        )

    def test_cmp3_array_example_scenario_and_references_are_pinned(self) -> None:
        root = REPO_ROOT / "testkit/differential/array-example"
        scenario = json.loads((root / "scenario.v1.json").read_text(encoding="utf-8"))
        validate_scenario(scenario)
        self.assertEqual(
            set(scenario["requiredObservations"]),
            {
                "callStatus",
                "returnValue",
                "state",
                "balances",
                "events",
                "externalActions",
                "interface",
                "resources",
            },
        )
        self.assertEqual(
            ["size-of-3", "get-element", "sum-of-3", "out-of-bounds"],
            [step["id"] for step in scenario["steps"]],
        )
        self.assertEqual(
            "array-index-out-of-bounds",
            scenario["steps"][-1]["expectError"],
        )
        self.assertEqual(len(scenario["steps"]), len(scenario["allowedDivergences"]))

        manifests = sorted((root / "references").glob("*.v1.json"))
        self.assertEqual(
            ["evm.v1.json", "near.v1.json", "solana.v1.json"],
            [path.name for path in manifests],
        )
        for manifest_path in manifests:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            validate_reference(manifest)
            source = REPO_ROOT / manifest["source"]["path"]
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertEqual(manifest["provenance"]["revision"], f"sha256:{digest}")
            source_text = source.read_text(encoding="utf-8")
            self.assertNotIn("proof_forge::", source_text)
            self.assertNotIn("ProofForge/", source_text)

        product_source = (REPO_ROOT / "Examples/Product/ArrayExample.lean").read_text(
            encoding="utf-8"
        )
        evm_source = (REPO_ROOT / "benchmarks/native/evm/ArrayExample.sol").read_text(
            encoding="utf-8"
        )
        solana_source = (
            REPO_ROOT / "benchmarks/native/solana/array-example/src/lib.rs"
        ).read_text(encoding="utf-8")
        near_source = (
            REPO_ROOT / "testkit/compare/near/array-example/src/lib.rs"
        ).read_text(encoding="utf-8")
        self.assertIn("query outOfBounds returns(.u64)", product_source)
        self.assertIn("error ArrayIndexOutOfBounds", evm_source)
        self.assertIn("const ARRAY_INDEX_OUT_OF_BOUNDS", solana_source)
        self.assertIn('env::panic_str("array index out of bounds")', near_source)
        near_compare = (REPO_ROOT / "testkit/compare/src/main.rs").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            '"testkit/differential/array-example/references/near.v1.json"',
            near_compare,
        )

        inventory = generate_inventory()
        array_assets = {
            item["id"]: item["semanticEvidence"]
            for item in inventory["assets"]
            if item["id"].startswith("cmp3-") and "array-example" in item["id"]
        }
        self.assertEqual(
            {
                "cmp3-reference-evm-array-example": "none",
                "cmp3-reference-near-array-example": "none",
                "cmp3-reference-solana-array-example": "none",
                "cmp3-scenario-array-example-primary-triad": "none",
            },
            array_assets,
        )

    def test_compiler_does_not_import_comparison_contracts(self) -> None:
        needles = (
            "proof-forge.differential.reference.v1",
            "proof-forge.differential.scenario.v1",
            "proof-forge.differential.observation.v1",
            "proof-forge.differential.runner-result.v1",
            "testkit/differential",
        )
        offenders: list[str] = []
        for path in (REPO_ROOT / "ProofForge").rglob("*.lean"):
            text = path.read_text(encoding="utf-8")
            if any(needle in text for needle in needles):
                offenders.append(path.relative_to(REPO_ROOT).as_posix())
        self.assertEqual([], offenders)


if __name__ == "__main__":
    unittest.main()
