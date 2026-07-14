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
        self.assertEqual(28, len(paths))
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
        self.assertEqual(6, inventory["summary"]["semanticVerifiedCount"])
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
