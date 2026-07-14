#!/usr/bin/env python3
"""Normalized runner results and fail-closed native differential comparison."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from contracts import (
    OBSERVATION_DIMENSIONS,
    OBSERVATION_SCHEMA,
    TARGET_FAMILIES,
    ContractError,
    validate_observation,
    validate_scenario,
)


RUNNER_RESULT_SCHEMA = "proof-forge.differential.runner-result.v1"
VALUE_TYPES = frozenset(
    {"unit", "bool", "u64", "u128", "i64", "string", "bytes", "address", "accountId", "list", "record"}
)
ERROR_CATEGORIES = frozenset(
    {"assertion", "authorization", "invalidInput", "unsupported", "externalFailure", "outOfResource", "trap"}
)


class RunnerContractError(ContractError):
    pass


def _nonempty(value: str, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RunnerContractError(f"{path}: expected non-empty string")
    return value


def _unique(values: Sequence[str], path: str) -> tuple[str, ...]:
    result = tuple(_nonempty(value, f"{path}[{index}]") for index, value in enumerate(values))
    if len(result) != len(set(result)):
        raise RunnerContractError(f"{path}: contains duplicates")
    return result


@dataclass(frozen=True)
class NormalizedValue:
    type: str
    value: Any = None

    def __post_init__(self) -> None:
        if self.type not in VALUE_TYPES:
            raise RunnerContractError(f"value.type: unknown normalized type {self.type!r}")
        if self.type == "unit":
            if self.value is not None:
                raise RunnerContractError("value: unit must use null")
        elif self.type == "bool":
            if not isinstance(self.value, bool):
                raise RunnerContractError("value: bool requires a boolean")
        elif self.type in {"u64", "u128", "i64"}:
            if not isinstance(self.value, str) or not self.value.lstrip("-").isdigit():
                raise RunnerContractError(f"value: {self.type} requires a canonical decimal string")
            parsed = int(self.value)
            limits = {
                "u64": (0, 2**64 - 1),
                "u128": (0, 2**128 - 1),
                "i64": (-(2**63), 2**63 - 1),
            }
            lower, upper = limits[self.type]
            if not lower <= parsed <= upper or str(parsed) != self.value:
                raise RunnerContractError(f"value: {self.type} is not canonical or is out of range")
        elif self.type == "bytes":
            if not isinstance(self.value, str) or len(self.value) % 2 or any(ch not in "0123456789abcdef" for ch in self.value):
                raise RunnerContractError("value: bytes requires lowercase even-length hex without a prefix")
        elif self.type in {"string", "address", "accountId"}:
            _nonempty(self.value, "value")
        elif self.type == "list":
            if not isinstance(self.value, list) or not all(isinstance(item, dict) and "type" in item for item in self.value):
                raise RunnerContractError("value: list requires normalized value objects")
        elif self.type == "record":
            if not isinstance(self.value, dict) or not all(
                isinstance(name, str) and name and isinstance(item, dict) and "type" in item
                for name, item in self.value.items()
            ):
                raise RunnerContractError("value: record requires named normalized value objects")

    @classmethod
    def unit(cls) -> "NormalizedValue":
        return cls("unit", None)

    @classmethod
    def bool(cls, value: bool) -> "NormalizedValue":
        return cls("bool", value)

    @classmethod
    def u64(cls, value: int) -> "NormalizedValue":
        return cls("u64", str(value))

    @classmethod
    def u128(cls, value: int) -> "NormalizedValue":
        return cls("u128", str(value))

    @classmethod
    def string(cls, value: str) -> "NormalizedValue":
        return cls("string", value)

    @classmethod
    def bytes(cls, value: bytes) -> "NormalizedValue":
        return cls("bytes", value.hex())

    def to_json(self) -> dict[str, Any]:
        return {"type": self.type, "value": self.value}


@dataclass(frozen=True)
class LogicalAccount:
    id: str
    native_id: str | None = None
    roles: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        _nonempty(self.id, "account.id")
        if self.native_id is not None:
            _nonempty(self.native_id, "account.nativeId")
        object.__setattr__(self, "roles", _unique(self.roles, "account.roles"))

    def to_json(self) -> dict[str, Any]:
        return {"id": self.id, "nativeId": self.native_id, "roles": list(self.roles)}

    def semantic_view(self) -> dict[str, Any]:
        return {"id": self.id, "roles": list(self.roles)}


@dataclass(frozen=True)
class LogicalActor:
    id: str
    account_id: str
    roles: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        _nonempty(self.id, "actor.id")
        _nonempty(self.account_id, "actor.accountId")
        object.__setattr__(self, "roles", _unique(self.roles, "actor.roles"))

    def to_json(self) -> dict[str, Any]:
        return {"id": self.id, "accountId": self.account_id, "roles": list(self.roles)}


@dataclass(frozen=True)
class LogicalClock:
    tick: int
    native_height: int | None = None
    timestamp_ns: int | None = None

    def __post_init__(self) -> None:
        for name, value in (
            ("tick", self.tick),
            ("nativeHeight", self.native_height),
            ("timestampNs", self.timestamp_ns),
        ):
            if value is not None and (not isinstance(value, int) or value < 0):
                raise RunnerContractError(f"clock.{name}: expected a non-negative integer")

    def to_json(self) -> dict[str, Any]:
        return {"tick": self.tick, "nativeHeight": self.native_height, "timestampNs": self.timestamp_ns}

    def semantic_view(self) -> dict[str, Any]:
        return {"tick": self.tick}


@dataclass(frozen=True)
class RunnerContext:
    accounts: tuple[LogicalAccount, ...]
    actors: tuple[LogicalActor, ...]
    clock: LogicalClock

    def __post_init__(self) -> None:
        account_ids = [account.id for account in self.accounts]
        actor_ids = [actor.id for actor in self.actors]
        if len(account_ids) != len(set(account_ids)):
            raise RunnerContractError("context.accounts: duplicate logical account IDs")
        if len(actor_ids) != len(set(actor_ids)):
            raise RunnerContractError("context.actors: duplicate logical actor IDs")
        known_accounts = set(account_ids)
        for actor in self.actors:
            if actor.account_id not in known_accounts:
                raise RunnerContractError(
                    f"context.actors: actor {actor.id!r} references unknown account {actor.account_id!r}"
                )

    def to_json(self) -> dict[str, Any]:
        return {
            "accounts": [account.to_json() for account in self.accounts],
            "actors": [actor.to_json() for actor in self.actors],
            "clock": self.clock.to_json(),
        }

    def semantic_view(self) -> dict[str, Any]:
        return {
            "accounts": [account.semantic_view() for account in self.accounts],
            "actors": [actor.to_json() for actor in self.actors],
            "clock": self.clock.semantic_view(),
        }


@dataclass(frozen=True)
class ExternalAction:
    logical_kind: str
    target_family: str
    logical_payload: Mapping[str, Any]
    native_payload: Mapping[str, Any]

    def __post_init__(self) -> None:
        _nonempty(self.logical_kind, "externalAction.logicalKind")
        if self.target_family not in TARGET_FAMILIES - {"portable"}:
            raise RunnerContractError(f"externalAction.targetFamily: unsupported {self.target_family!r}")
        if not isinstance(self.logical_payload, Mapping):
            raise RunnerContractError("externalAction.logicalPayload: expected object")
        if not isinstance(self.native_payload, Mapping):
            raise RunnerContractError("externalAction.nativePayload: expected object")

    def to_json(self) -> dict[str, Any]:
        return {
            "logicalKind": self.logical_kind,
            "logicalPayload": dict(self.logical_payload),
            "targetFamily": self.target_family,
            "nativePayload": dict(self.native_payload),
        }


@dataclass(frozen=True)
class ResourceObservation:
    target_family: str
    metrics: Mapping[str, Mapping[str, Any]]

    def __post_init__(self) -> None:
        if self.target_family not in TARGET_FAMILIES - {"portable"}:
            raise RunnerContractError(f"resources.targetFamily: unsupported {self.target_family!r}")
        if not self.metrics:
            raise RunnerContractError("resources.metrics: must not be empty")
        forbidden = {"score", "totalScore", "crossChainScore"}
        if forbidden & set(self.metrics):
            raise RunnerContractError("resources.metrics: aggregate cross-chain scores are forbidden")
        for name, metric in self.metrics.items():
            _nonempty(name, "resources.metrics.name")
            if not isinstance(metric, Mapping) or set(metric) != {"value", "unit"}:
                raise RunnerContractError(f"resources.metrics.{name}: expected exactly value and unit")
            if not isinstance(metric["value"], (int, float)) or isinstance(metric["value"], bool) or metric["value"] < 0:
                raise RunnerContractError(f"resources.metrics.{name}.value: expected non-negative number")
            _nonempty(metric["unit"], f"resources.metrics.{name}.unit")

    def to_json(self) -> dict[str, Any]:
        return {"targetFamily": self.target_family, "metrics": {name: dict(value) for name, value in self.metrics.items()}}


@dataclass(frozen=True)
class StepResult:
    id: str
    observations: Mapping[str, Any]

    def __post_init__(self) -> None:
        _nonempty(self.id, "step.id")
        unknown = sorted(set(self.observations) - OBSERVATION_DIMENSIONS)
        if unknown:
            raise RunnerContractError(f"step.observations: unknown dimensions: {', '.join(unknown)}")

    def to_json(self) -> dict[str, Any]:
        return {"id": self.id, "observations": dict(self.observations)}


def _validate_typed_value(value: Any, path: str) -> None:
    if not isinstance(value, dict) or set(value) != {"type", "value"}:
        raise RunnerContractError(f"{path}: expected a normalized typed value")
    NormalizedValue(value["type"], value["value"])


def _validate_step_observations(step: StepResult, target_family: str) -> None:
    for dimension, value in step.observations.items():
        path = f"runnerResult.steps[{step.id}].observations.{dimension}"
        if dimension == "callStatus":
            if not isinstance(value, dict) or value.get("status") not in {"success", "revert", "error"}:
                raise RunnerContractError(f"{path}: expected success, revert, or error status")
            if value["status"] != "success" and value.get("errorCategory") not in ERROR_CATEGORIES:
                raise RunnerContractError(f"{path}: non-success status requires a classified errorCategory")
        elif dimension == "returnValue":
            _validate_typed_value(value, path)
        elif dimension in {"state", "balances"}:
            if not isinstance(value, dict):
                raise RunnerContractError(f"{path}: expected named values")
            for name, item in value.items():
                _nonempty(name, f"{path}.name")
                _validate_typed_value(item, f"{path}.{name}")
        elif dimension == "events":
            if not isinstance(value, list):
                raise RunnerContractError(f"{path}: expected ordered event array")
            for index, event in enumerate(value):
                if not isinstance(event, dict) or not isinstance(event.get("fields"), dict):
                    raise RunnerContractError(f"{path}[{index}]: expected event name and fields")
                _nonempty(event.get("name"), f"{path}[{index}].name")
                for name, item in event["fields"].items():
                    _nonempty(name, f"{path}[{index}].fields.name")
                    _validate_typed_value(item, f"{path}[{index}].fields.{name}")
        elif dimension == "externalActions":
            if not isinstance(value, list):
                raise RunnerContractError(f"{path}: expected ordered external action array")
            for index, action in enumerate(value):
                if not isinstance(action, dict) or set(action) != {
                    "logicalKind",
                    "logicalPayload",
                    "targetFamily",
                    "nativePayload",
                }:
                    raise RunnerContractError(f"{path}[{index}]: expected logical and target-owned payloads")
                if action["targetFamily"] != target_family:
                    raise RunnerContractError(f"{path}[{index}]: target family does not match runner")
                _nonempty(action["logicalKind"], f"{path}[{index}].logicalKind")
                if not isinstance(action["logicalPayload"], dict) or not isinstance(action["nativePayload"], dict):
                    raise RunnerContractError(f"{path}[{index}]: payloads must be objects")
        elif dimension == "interface":
            if not isinstance(value, dict):
                raise RunnerContractError(f"{path}: expected interface assertion object")
        elif dimension == "resources":
            if not isinstance(value, dict) or value.get("targetFamily") != target_family:
                raise RunnerContractError(f"{path}: target family does not match runner")
            ResourceObservation(target_family, value.get("metrics", {}))


@dataclass(frozen=True)
class RunnerResult:
    scenario_id: str
    target_family: str
    runner_name: str
    status: str
    provenance_complete: bool
    context: RunnerContext
    declared_coverage: tuple[str, ...]
    steps: tuple[StepResult, ...]
    reason: str | None = None

    def __post_init__(self) -> None:
        _nonempty(self.scenario_id, "runnerResult.scenarioId")
        if self.target_family not in TARGET_FAMILIES - {"portable"}:
            raise RunnerContractError(f"runnerResult.targetFamily: unsupported {self.target_family!r}")
        _nonempty(self.runner_name, "runnerResult.runner.name")
        if self.status not in {"executed", "skipped", "error"}:
            raise RunnerContractError("runnerResult.runner.status: expected executed, skipped, or error")
        if self.status != "executed":
            _nonempty(self.reason, "runnerResult.runner.reason")
        coverage = _unique(self.declared_coverage, "runnerResult.declaredCoverage")
        unknown = sorted(set(coverage) - OBSERVATION_DIMENSIONS)
        if unknown:
            raise RunnerContractError(f"runnerResult.declaredCoverage: unknown dimensions: {', '.join(unknown)}")
        object.__setattr__(self, "declared_coverage", coverage)
        step_ids = [step.id for step in self.steps]
        if len(step_ids) != len(set(step_ids)):
            raise RunnerContractError("runnerResult.steps: duplicate step IDs")
        for step in self.steps:
            _validate_step_observations(step, self.target_family)
        observed = set().union(*(set(step.observations) for step in self.steps)) if self.steps else set()
        unsupported_claims = set(coverage) - observed
        if self.status == "executed" and unsupported_claims:
            raise RunnerContractError(
                "runnerResult.declaredCoverage: claims unobserved dimensions: " + ", ".join(sorted(unsupported_claims))
            )

    def to_json(self) -> dict[str, Any]:
        runner = {"name": self.runner_name, "status": self.status}
        if self.reason is not None:
            runner["reason"] = self.reason
        return {
            "schema": RUNNER_RESULT_SCHEMA,
            "scenarioId": self.scenario_id,
            "targetFamily": self.target_family,
            "runner": runner,
            "provenanceComplete": self.provenance_complete,
            "context": self.context.to_json(),
            "declaredCoverage": list(self.declared_coverage),
            "steps": [step.to_json() for step in self.steps],
        }


@dataclass
class _Diff:
    dimension: str
    scope: str
    baseline: Any
    candidate: Any

    def to_json(self) -> dict[str, Any]:
        return {"dimension": self.dimension, "scope": self.scope, "baseline": self.baseline, "candidate": self.candidate}


def _json_diffs(dimension: str, baseline: Any, candidate: Any, scope: str) -> list[_Diff]:
    if type(baseline) is not type(candidate):
        return [_Diff(dimension, scope, baseline, candidate)]
    if isinstance(baseline, dict):
        diffs: list[_Diff] = []
        for key in sorted(set(baseline) | set(candidate)):
            child = f"{scope}/{key}"
            if key not in baseline:
                diffs.append(_Diff(dimension, child, None, candidate[key]))
            elif key not in candidate:
                diffs.append(_Diff(dimension, child, baseline[key], None))
            else:
                diffs.extend(_json_diffs(dimension, baseline[key], candidate[key], child))
        return diffs
    if isinstance(baseline, list):
        diffs = []
        for index in range(max(len(baseline), len(candidate))):
            child = f"{scope}/{index}"
            if index >= len(baseline):
                diffs.append(_Diff(dimension, child, None, candidate[index]))
            elif index >= len(candidate):
                diffs.append(_Diff(dimension, child, baseline[index], None))
            else:
                diffs.extend(_json_diffs(dimension, baseline[index], candidate[index], child))
        return diffs
    return [] if baseline == candidate else [_Diff(dimension, scope, baseline, candidate)]


def _allowed(diff: _Diff, divergences: Sequence[Mapping[str, Any]]) -> bool:
    return any(item["dimension"] == diff.dimension and item["scope"] == diff.scope for item in divergences)


def _portable_external_actions(actions: Any) -> Any:
    if not isinstance(actions, list):
        return actions
    return [
        {"logicalKind": action.get("logicalKind"), "logicalPayload": action.get("logicalPayload")}
        if isinstance(action, dict)
        else action
        for action in actions
    ]


def compare_results(scenario: Mapping[str, Any], baseline: RunnerResult, candidate: RunnerResult) -> dict[str, Any]:
    validate_scenario(scenario)
    scenario_id = scenario["id"]
    if baseline.scenario_id != scenario_id or candidate.scenario_id != scenario_id:
        raise RunnerContractError("comparison: runner scenarioId does not match scenario")

    scenario_steps = [step["id"] for step in scenario["steps"]]
    required = list(scenario["requiredObservations"])
    baseline_steps = {step.id: step for step in baseline.steps}
    candidate_steps = {step.id: step for step in candidate.steps}
    exact_steps = set(baseline_steps) == set(scenario_steps) == set(candidate_steps)
    runner_executed = baseline.status == "executed" and candidate.status == "executed"

    baseline_observed = set().union(*(set(step.observations) for step in baseline.steps)) if baseline.steps else set()
    candidate_observed = set().union(*(set(step.observations) for step in candidate.steps)) if candidate.steps else set()
    covered = [
        dimension
        for dimension in required
        if runner_executed
        and dimension in baseline.declared_coverage
        and dimension in candidate.declared_coverage
        and dimension in baseline_observed
        and dimension in candidate_observed
    ]
    missing = [dimension for dimension in required if dimension not in covered]

    context_diffs = _json_diffs("callStatus", baseline.context.semantic_view(), candidate.context.semantic_view(), "/context")
    observed_diffs: list[_Diff] = list(context_diffs)
    allowed_diffs: list[_Diff] = []
    step_observations: list[dict[str, Any]] = []
    divergences = scenario["allowedDivergences"]

    for step_id in scenario_steps:
        compared: dict[str, Any] = {}
        left = baseline_steps.get(step_id)
        right = candidate_steps.get(step_id)
        if left is None or right is None:
            continue
        for dimension in sorted(set(left.observations) & set(right.observations)):
            baseline_value = left.observations[dimension]
            candidate_value = right.observations[dimension]
            relation = "compared"
            diffs: list[_Diff]
            if dimension == "resources" and baseline.target_family != candidate.target_family:
                relation = "targetLocalNotCompared"
                diffs = []
            elif dimension == "externalActions" and baseline.target_family != candidate.target_family:
                relation = "logicalActionComparedNativePayloadRetained"
                diffs = _json_diffs(
                    dimension,
                    _portable_external_actions(baseline_value),
                    _portable_external_actions(candidate_value),
                    f"/steps/{step_id}/observations/{dimension}",
                )
            else:
                diffs = _json_diffs(
                    dimension,
                    baseline_value,
                    candidate_value,
                    f"/steps/{step_id}/observations/{dimension}",
                )
            unallowed: list[_Diff] = []
            for diff in diffs:
                if _allowed(diff, divergences):
                    allowed_diffs.append(diff)
                else:
                    unallowed.append(diff)
                    observed_diffs.append(diff)
            compared[dimension] = {
                "relation": relation,
                "matched": not unallowed,
                "baseline": baseline_value,
                "candidate": candidate_value,
            }
        step_observations.append({"id": step_id, "observations": compared})

    if not exact_steps:
        observed_diffs.append(
            _Diff("callStatus", "/steps", sorted(baseline_steps), sorted(candidate_steps))
        )
    observed_match = runner_executed and exact_steps and not observed_diffs
    provenance_complete = baseline.provenance_complete and candidate.provenance_complete
    semantic_match = observed_match and provenance_complete and not missing
    if not runner_executed:
        status = "error" if "error" in {baseline.status, candidate.status} else "skipped"
        reason = f"baseline={baseline.status}; candidate={candidate.status}"
    else:
        status = "executed"
        reason = None
    runner: dict[str, Any] = {"name": f"compare:{baseline.runner_name}:{candidate.runner_name}", "status": status}
    if reason is not None:
        runner["reason"] = reason
    report = {
        "schema": OBSERVATION_SCHEMA,
        "scenarioId": scenario_id,
        "runner": runner,
        "provenanceComplete": provenance_complete,
        "observedMatch": observed_match,
        "observationCoverage": {"required": required, "covered": covered, "missing": missing},
        "steps": step_observations,
        "semanticMatch": semantic_match,
        "comparison": {
            "baseline": {"targetFamily": baseline.target_family, "runner": baseline.runner_name},
            "candidate": {"targetFamily": candidate.target_family, "runner": candidate.runner_name},
            "mismatches": [diff.to_json() for diff in observed_diffs],
            "allowedDifferences": [diff.to_json() for diff in allowed_diffs],
            "resourcePolicy": "target-local-only; no cross-target score",
        },
    }
    validate_observation(report)
    return report
