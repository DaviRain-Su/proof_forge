#!/usr/bin/env python3

from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from contracts import SCENARIO_SCHEMA  # noqa: E402
from runner import (  # noqa: E402
    ExternalAction,
    LogicalAccount,
    LogicalActor,
    LogicalClock,
    NormalizedValue,
    ResourceObservation,
    RunnerContext,
    RunnerContractError,
    RunnerResult,
    StepResult,
    compare_results,
)


DIMENSIONS = (
    "callStatus",
    "returnValue",
    "state",
    "balances",
    "events",
    "externalActions",
    "interface",
    "resources",
)


def context(native_suffix: str = "evm", tick: int = 0) -> RunnerContext:
    return RunnerContext(
        accounts=(
            LogicalAccount("contract", f"contract.{native_suffix}", ("contract",)),
            LogicalAccount("alice", f"alice.{native_suffix}", ("caller",)),
        ),
        actors=(LogicalActor("alice", "alice", ("caller",)),),
        clock=LogicalClock(tick=tick, native_height=100, timestamp_ns=1_000_000),
    )


def observations(target_family: str = "evm") -> dict[str, object]:
    return {
        "callStatus": {"status": "success", "errorCategory": None, "errorData": None},
        "returnValue": NormalizedValue.u64(1).to_json(),
        "state": {"count": NormalizedValue.u64(1).to_json()},
        "balances": {"alice": NormalizedValue.u128(100).to_json()},
        "events": [{"name": "Incremented", "fields": {"value": NormalizedValue.u64(1).to_json()}}],
        "externalActions": [
            ExternalAction(
                "portable.call",
                target_family,
                {"method": "notify"},
                {"opcode": "CALL" if target_family == "evm" else "target-native"},
            ).to_json()
        ],
        "interface": {"entrypoint": "increment", "mutable": True},
        "resources": ResourceObservation(
            target_family,
            {"execution": {"value": 21000, "unit": "gas" if target_family == "evm" else "computeUnits"}},
        ).to_json(),
    }


def scenario(required: tuple[str, ...] = DIMENSIONS, divergences: list[dict[str, str]] | None = None) -> dict[str, object]:
    return {
        "schema": SCENARIO_SCHEMA,
        "id": "portable-counter",
        "kind": "portable",
        "targetFamily": "portable",
        "steps": [{"id": "increment", "action": "increment"}],
        "requiredObservations": list(required),
        "allowedDivergences": divergences or [],
    }


def result(
    runner_name: str,
    *,
    target_family: str = "evm",
    values: dict[str, object] | None = None,
    coverage: tuple[str, ...] = DIMENSIONS,
    status: str = "executed",
    reason: str | None = None,
    provenance_complete: bool = True,
    runner_context: RunnerContext | None = None,
) -> RunnerResult:
    steps = () if status != "executed" else (StepResult("increment", values or observations(target_family)),)
    return RunnerResult(
        scenario_id="portable-counter",
        target_family=target_family,
        runner_name=runner_name,
        status=status,
        provenance_complete=provenance_complete,
        context=runner_context or context(target_family),
        declared_coverage=coverage if status == "executed" else (),
        steps=steps,
        reason=reason,
    )


class RunnerContractTests(unittest.TestCase):
    def test_normalized_scalars_are_typed_and_range_checked(self) -> None:
        self.assertEqual({"type": "u64", "value": "42"}, NormalizedValue.u64(42).to_json())
        self.assertEqual({"type": "bytes", "value": "00ff"}, NormalizedValue.bytes(b"\x00\xff").to_json())
        with self.assertRaisesRegex(RunnerContractError, "out of range"):
            NormalizedValue.u64(2**64)

    def test_context_rejects_duplicate_or_unknown_accounts(self) -> None:
        with self.assertRaisesRegex(RunnerContractError, "duplicate logical account"):
            RunnerContext(
                accounts=(LogicalAccount("alice"), LogicalAccount("alice")),
                actors=(),
                clock=LogicalClock(0),
            )
        with self.assertRaisesRegex(RunnerContractError, "unknown account"):
            RunnerContext(
                accounts=(LogicalAccount("alice"),),
                actors=(LogicalActor("bob", "bob"),),
                clock=LogicalClock(0),
            )

    def test_complete_equal_results_are_semantic_match(self) -> None:
        report = compare_results(scenario(), result("native"), result("proof-forge"))
        self.assertTrue(report["observedMatch"])
        self.assertEqual([], report["observationCoverage"]["missing"])
        self.assertTrue(report["semanticMatch"])

    def test_every_observation_dimension_can_fail_independently(self) -> None:
        mutations = {
            "callStatus": {"status": "revert", "errorCategory": "assertion", "errorData": "01"},
            "returnValue": NormalizedValue.u64(2).to_json(),
            "state": {"count": NormalizedValue.u64(2).to_json()},
            "balances": {"alice": NormalizedValue.u128(99).to_json()},
            "events": [{"name": "Different", "fields": {}}],
            "externalActions": [ExternalAction("portable.call", "evm", {"method": "other"}, {"opcode": "CALL"}).to_json()],
            "interface": {"entrypoint": "increment", "mutable": False},
            "resources": ResourceObservation("evm", {"execution": {"value": 22000, "unit": "gas"}}).to_json(),
        }
        for dimension, replacement in mutations.items():
            with self.subTest(dimension=dimension):
                candidate = observations()
                candidate[dimension] = replacement
                report = compare_results(scenario(), result("native"), result("proof-forge", values=candidate))
                self.assertFalse(report["observedMatch"])
                self.assertFalse(report["semanticMatch"])
                self.assertTrue(any(item["dimension"] == dimension for item in report["comparison"]["mismatches"]))

    def test_missing_required_coverage_fails_closed(self) -> None:
        candidate = observations()
        del candidate["state"]
        coverage = tuple(dimension for dimension in DIMENSIONS if dimension != "state")
        report = compare_results(
            scenario(),
            result("native"),
            result("proof-forge", values=candidate, coverage=coverage),
        )
        self.assertTrue(report["observedMatch"])
        self.assertEqual(["state"], report["observationCoverage"]["missing"])
        self.assertFalse(report["semanticMatch"])

    def test_skip_error_and_incomplete_provenance_fail_closed(self) -> None:
        skipped = result("proof-forge", status="skipped", reason="tool unavailable")
        skip_report = compare_results(scenario(), result("native"), skipped)
        self.assertEqual("skipped", skip_report["runner"]["status"])
        self.assertFalse(skip_report["semanticMatch"])

        incomplete = result("proof-forge", provenance_complete=False)
        provenance_report = compare_results(scenario(), result("native"), incomplete)
        self.assertTrue(provenance_report["observedMatch"])
        self.assertFalse(provenance_report["semanticMatch"])

    def test_native_account_ids_and_clock_values_do_not_erase_logical_context(self) -> None:
        baseline = result("native", runner_context=context("native"))
        candidate_context = RunnerContext(
            accounts=(
                LogicalAccount("contract", "0x1234", ("contract",)),
                LogicalAccount("alice", "alice.near", ("caller",)),
            ),
            actors=(LogicalActor("alice", "alice", ("caller",)),),
            clock=LogicalClock(tick=0, native_height=999, timestamp_ns=8_000_000),
        )
        report = compare_results(scenario(), baseline, result("proof-forge", runner_context=candidate_context))
        self.assertTrue(report["semanticMatch"])

        changed_tick = result("proof-forge", runner_context=context("proof-forge", tick=1))
        mismatch = compare_results(scenario(), baseline, changed_tick)
        self.assertFalse(mismatch["observedMatch"])

    def test_exact_scoped_allowed_divergence_does_not_remove_coverage(self) -> None:
        candidate = observations()
        candidate["returnValue"] = NormalizedValue.u64(2).to_json()
        divergence = {
            "dimension": "returnValue",
            "scope": "/steps/increment/observations/returnValue/value",
            "reason": "scenario explicitly accepts this target projection",
        }
        report = compare_results(
            scenario(divergences=[divergence]),
            result("native"),
            result("proof-forge", values=candidate),
        )
        self.assertTrue(report["semanticMatch"])
        self.assertEqual(DIMENSIONS, tuple(report["observationCoverage"]["covered"]))
        self.assertEqual(1, len(report["comparison"]["allowedDifferences"]))

    def test_resources_are_target_local_and_never_aggregated(self) -> None:
        required = ("callStatus", "resources")
        evm_values = {
            "callStatus": {"status": "success"},
            "resources": ResourceObservation("evm", {"execution": {"value": 21000, "unit": "gas"}}).to_json(),
        }
        solana_values = {
            "callStatus": {"status": "success"},
            "resources": ResourceObservation("solana", {"execution": {"value": 500, "unit": "computeUnits"}}).to_json(),
        }
        report = compare_results(
            scenario(required),
            result("evm", target_family="evm", values=evm_values, coverage=required),
            result("solana", target_family="solana", values=solana_values, coverage=required),
        )
        self.assertTrue(report["semanticMatch"])
        relation = report["steps"][0]["observations"]["resources"]["relation"]
        self.assertEqual("targetLocalNotCompared", relation)
        self.assertNotIn("score", report["comparison"])
        self.assertNotIn("score", report["steps"][0]["observations"]["resources"]["baseline"])

        with self.assertRaisesRegex(RunnerContractError, "scores are forbidden"):
            ResourceObservation("evm", {"crossChainScore": {"value": 1, "unit": "score"}})

    def test_external_actions_compare_logical_payload_and_retain_native_payload(self) -> None:
        required = ("callStatus", "externalActions")
        evm_values = {
            "callStatus": {"status": "success"},
            "externalActions": [
                ExternalAction("portable.call", "evm", {"method": "notify"}, {"opcode": "CALL"}).to_json()
            ],
        }
        near_values = {
            "callStatus": {"status": "success"},
            "externalActions": [
                ExternalAction("portable.call", "near", {"method": "notify"}, {"promiseId": 7}).to_json()
            ],
        }
        report = compare_results(
            scenario(required),
            result("evm", target_family="evm", values=evm_values, coverage=required),
            result("near", target_family="near", values=near_values, coverage=required),
        )
        self.assertTrue(report["semanticMatch"])
        action = report["steps"][0]["observations"]["externalActions"]
        self.assertEqual("logicalActionComparedNativePayloadRetained", action["relation"])
        self.assertEqual({"opcode": "CALL"}, action["baseline"][0]["nativePayload"])
        self.assertEqual({"promiseId": 7}, action["candidate"][0]["nativePayload"])

        near_values["externalActions"][0]["logicalPayload"]["method"] = "different"
        mismatch = compare_results(
            scenario(required),
            result("evm", target_family="evm", values=evm_values, coverage=required),
            result("near", target_family="near", values=near_values, coverage=required),
        )
        self.assertFalse(mismatch["semanticMatch"])

    def test_same_target_resource_difference_is_a_mismatch(self) -> None:
        baseline = observations()
        candidate = copy.deepcopy(baseline)
        candidate["resources"]["metrics"]["execution"]["value"] = 22000
        report = compare_results(scenario(), result("native", values=baseline), result("pf", values=candidate))
        self.assertFalse(report["semanticMatch"])

    def test_runner_contract_rejects_unknown_dimensions_and_false_coverage_claims(self) -> None:
        with self.assertRaisesRegex(RunnerContractError, "unknown dimensions"):
            StepResult("increment", {"nearPromise": {}})
        with self.assertRaisesRegex(RunnerContractError, "claims unobserved"):
            result("bad", values={"callStatus": {"status": "success"}}, coverage=("callStatus", "state"))
        with self.assertRaisesRegex(RunnerContractError, "classified errorCategory"):
            result("bad", values={"callStatus": {"status": "revert"}}, coverage=("callStatus",))


if __name__ == "__main__":
    unittest.main()
