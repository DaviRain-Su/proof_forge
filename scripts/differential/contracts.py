#!/usr/bin/env python3
"""Versioned, fail-closed contracts for native differential test evidence."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


REFERENCE_SCHEMA = "proof-forge.differential.reference.v1"
SCENARIO_SCHEMA = "proof-forge.differential.scenario.v1"
OBSERVATION_SCHEMA = "proof-forge.differential.observation.v1"
INVENTORY_SCHEMA = "proof-forge.differential.inventory.v1"

NEAR_V0_SCHEMA = "proof-forge.near.reference-equivalence.v0"
SOLANA_V0_SCHEMA = "proof-forge.solana.reference-equivalence.v0"

OBSERVATION_DIMENSIONS = frozenset(
    {
        "callStatus",
        "returnValue",
        "state",
        "balances",
        "events",
        "externalActions",
        "interface",
        "resources",
    }
)
TARGET_FAMILIES = frozenset({"portable", "evm", "solana", "near", "stylus"})


class ContractError(ValueError):
    pass


def _fail(path: str, message: str) -> None:
    raise ContractError(f"{path}: {message}")


def _object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(path, "expected object")
    return value


def _list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        _fail(path, "expected array")
    return value


def _string(value: Any, path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        _fail(path, "expected non-empty string")
    return value


def _boolean(value: Any, path: str) -> bool:
    if not isinstance(value, bool):
        _fail(path, "expected boolean")
    return value


def _unique_strings(value: Any, path: str) -> list[str]:
    items = _list(value, path)
    result = [_string(item, f"{path}[{index}]") for index, item in enumerate(items)]
    if len(result) != len(set(result)):
        _fail(path, "contains duplicates")
    return result


def _known_dimensions(value: Any, path: str) -> list[str]:
    result = _unique_strings(value, path)
    unknown = sorted(set(result) - OBSERVATION_DIMENSIONS)
    if unknown:
        _fail(path, f"unknown observation dimensions: {', '.join(unknown)}")
    return result


def _expect_schema(document: dict[str, Any], expected: str, path: str) -> None:
    actual = document.get("schema")
    if actual != expected:
        _fail(f"{path}.schema", f"expected {expected!r}, got {actual!r}")


def validate_reference(document: Any, path: str = "reference") -> dict[str, Any]:
    reference = _object(document, path)
    _expect_schema(reference, REFERENCE_SCHEMA, path)
    _string(reference.get("id"), f"{path}.id")
    target_family = _string(reference.get("targetFamily"), f"{path}.targetFamily")
    if target_family not in TARGET_FAMILIES - {"portable"}:
        _fail(f"{path}.targetFamily", f"unsupported target family {target_family!r}")
    _string(reference.get("program"), f"{path}.program")
    _string(reference.get("framework"), f"{path}.framework")

    source = _object(reference.get("source"), f"{path}.source")
    _string(source.get("path"), f"{path}.source.path")
    _string(source.get("language"), f"{path}.source.language")

    provenance = _object(reference.get("provenance"), f"{path}.provenance")
    status = _string(provenance.get("status"), f"{path}.provenance.status")
    if status not in {"complete", "incomplete"}:
        _fail(f"{path}.provenance.status", "expected 'complete' or 'incomplete'")
    origin = _object(provenance.get("origin"), f"{path}.provenance.origin")
    _string(origin.get("name"), f"{path}.provenance.origin.name")
    if origin.get("url") is not None:
        _string(origin.get("url"), f"{path}.provenance.origin.url")
    revision = provenance.get("revision")
    if revision is not None:
        _string(revision, f"{path}.provenance.revision")
    license_name = provenance.get("license")
    if license_name is not None:
        _string(license_name, f"{path}.provenance.license")
    toolchain = _list(provenance.get("toolchain"), f"{path}.provenance.toolchain")
    for index, tool in enumerate(toolchain):
        tool_obj = _object(tool, f"{path}.provenance.toolchain[{index}]")
        _string(tool_obj.get("name"), f"{path}.provenance.toolchain[{index}].name")
        version = tool_obj.get("version")
        if version is not None:
            _string(version, f"{path}.provenance.toolchain[{index}].version")
    missing = _unique_strings(provenance.get("missing"), f"{path}.provenance.missing")
    allowed_missing = {"revision", "license", "toolchainVersions"}
    unknown_missing = sorted(set(missing) - allowed_missing)
    if unknown_missing:
        _fail(f"{path}.provenance.missing", f"unknown fields: {', '.join(unknown_missing)}")

    complete_facts = (
        revision is not None
        and license_name is not None
        and bool(toolchain)
        and all(tool.get("version") is not None for tool in toolchain)
        and not missing
    )
    if status == "complete" and not complete_facts:
        _fail(f"{path}.provenance", "complete provenance must pin revision, license, and toolchain versions")
    if status == "incomplete" and not missing:
        _fail(f"{path}.provenance.missing", "incomplete provenance must enumerate missing fields")

    eligibility = _object(reference.get("semanticEligibility"), f"{path}.semanticEligibility")
    eligible = _boolean(eligibility.get("eligible"), f"{path}.semanticEligibility.eligible")
    reasons = _unique_strings(eligibility.get("reasons"), f"{path}.semanticEligibility.reasons")
    if eligible != complete_facts:
        _fail(f"{path}.semanticEligibility.eligible", "must exactly reflect complete provenance")
    if eligible and reasons:
        _fail(f"{path}.semanticEligibility.reasons", "eligible reference cannot have exclusion reasons")
    if not eligible and not reasons:
        _fail(f"{path}.semanticEligibility.reasons", "ineligible reference must explain why")
    return reference


def validate_scenario(document: Any, path: str = "scenario") -> dict[str, Any]:
    scenario = _object(document, path)
    _expect_schema(scenario, SCENARIO_SCHEMA, path)
    _string(scenario.get("id"), f"{path}.id")
    kind = _string(scenario.get("kind"), f"{path}.kind")
    if kind not in {"portable", "targetExtension"}:
        _fail(f"{path}.kind", "expected 'portable' or 'targetExtension'")
    target_family = _string(scenario.get("targetFamily"), f"{path}.targetFamily")
    if target_family not in TARGET_FAMILIES:
        _fail(f"{path}.targetFamily", f"unsupported target family {target_family!r}")
    if kind == "portable" and target_family != "portable":
        _fail(f"{path}.targetFamily", "portable scenario must use targetFamily='portable'")
    if kind == "targetExtension" and target_family == "portable":
        _fail(f"{path}.targetFamily", "target extension scenario must name its target family")

    steps = _list(scenario.get("steps"), f"{path}.steps")
    if not steps:
        _fail(f"{path}.steps", "must not be empty")
    step_ids: list[str] = []
    for index, step in enumerate(steps):
        step_obj = _object(step, f"{path}.steps[{index}]")
        step_ids.append(_string(step_obj.get("id"), f"{path}.steps[{index}].id"))
        _string(step_obj.get("action"), f"{path}.steps[{index}].action")
    if len(step_ids) != len(set(step_ids)):
        _fail(f"{path}.steps", "duplicate step IDs")

    _known_dimensions(scenario.get("requiredObservations"), f"{path}.requiredObservations")
    divergences = _list(scenario.get("allowedDivergences"), f"{path}.allowedDivergences")
    for index, divergence in enumerate(divergences):
        item = _object(divergence, f"{path}.allowedDivergences[{index}]")
        dimensions = _known_dimensions([item.get("dimension")], f"{path}.allowedDivergences[{index}].dimension")
        if len(dimensions) != 1:
            _fail(f"{path}.allowedDivergences[{index}].dimension", "expected one dimension")
        _string(item.get("scope"), f"{path}.allowedDivergences[{index}].scope")
        _string(item.get("reason"), f"{path}.allowedDivergences[{index}].reason")
    return scenario


def validate_observation(document: Any, path: str = "observation") -> dict[str, Any]:
    observation = _object(document, path)
    _expect_schema(observation, OBSERVATION_SCHEMA, path)
    _string(observation.get("scenarioId"), f"{path}.scenarioId")
    runner = _object(observation.get("runner"), f"{path}.runner")
    _string(runner.get("name"), f"{path}.runner.name")
    runner_status = _string(runner.get("status"), f"{path}.runner.status")
    if runner_status not in {"executed", "skipped", "error"}:
        _fail(f"{path}.runner.status", "expected executed, skipped, or error")
    if runner_status != "executed":
        _string(runner.get("reason"), f"{path}.runner.reason")

    provenance_complete = _boolean(observation.get("provenanceComplete"), f"{path}.provenanceComplete")
    observed_match = _boolean(observation.get("observedMatch"), f"{path}.observedMatch")
    semantic_match = _boolean(observation.get("semanticMatch"), f"{path}.semanticMatch")
    coverage = _object(observation.get("observationCoverage"), f"{path}.observationCoverage")
    required = _known_dimensions(coverage.get("required"), f"{path}.observationCoverage.required")
    covered = _known_dimensions(coverage.get("covered"), f"{path}.observationCoverage.covered")
    missing = _known_dimensions(coverage.get("missing"), f"{path}.observationCoverage.missing")
    if set(covered) - set(required):
        _fail(f"{path}.observationCoverage.covered", "cannot cover dimensions that were not required")
    expected_missing = set(required) - set(covered)
    if set(missing) != expected_missing:
        _fail(f"{path}.observationCoverage.missing", "must equal required minus covered")

    steps = _list(observation.get("steps"), f"{path}.steps")
    step_ids: list[str] = []
    for index, step in enumerate(steps):
        step_obj = _object(step, f"{path}.steps[{index}]")
        step_ids.append(_string(step_obj.get("id"), f"{path}.steps[{index}].id"))
        dimensions = _object(step_obj.get("observations"), f"{path}.steps[{index}].observations")
        unknown = sorted(set(dimensions) - OBSERVATION_DIMENSIONS)
        if unknown:
            _fail(f"{path}.steps[{index}].observations", f"unknown dimensions: {', '.join(unknown)}")
    if len(step_ids) != len(set(step_ids)):
        _fail(f"{path}.steps", "duplicate step IDs")

    if semantic_match:
        if runner_status != "executed":
            _fail(f"{path}.semanticMatch", "runner skips and errors fail closed")
        if not provenance_complete:
            _fail(f"{path}.semanticMatch", "incomplete provenance fails closed")
        if not observed_match:
            _fail(f"{path}.semanticMatch", "observed mismatch fails closed")
        if missing:
            _fail(f"{path}.semanticMatch", "incomplete observation coverage fails closed")
    return observation


def validate_inventory(document: Any, path: str = "inventory") -> dict[str, Any]:
    inventory = _object(document, path)
    _expect_schema(inventory, INVENTORY_SCHEMA, path)
    assets = _list(inventory.get("assets"), f"{path}.assets")
    ids: list[str] = []
    for index, asset in enumerate(assets):
        item_path = f"{path}.assets[{index}]"
        item = _object(asset, item_path)
        ids.append(_string(item.get("id"), f"{item_path}.id"))
        family = _string(item.get("targetFamily"), f"{item_path}.targetFamily")
        if family not in TARGET_FAMILIES:
            _fail(f"{item_path}.targetFamily", f"unsupported target family {family!r}")
        kind = _string(item.get("kind"), f"{item_path}.kind")
        if kind not in {"nativeReference", "runner", "scenario", "gate", "reportCatalog"}:
            _fail(f"{item_path}.kind", f"unsupported asset kind {kind!r}")
        _string(item.get("path"), f"{item_path}.path")
        maturity = _string(item.get("maturity"), f"{item_path}.maturity")
        if maturity not in {
            "referenceManifestV0",
            "structuralReference",
            "deterministicRunner",
            "liveRunner",
            "portableScenarioV0",
            "measurementOnly",
            "ciGate",
        }:
            _fail(f"{item_path}.maturity", f"unsupported maturity {maturity!r}")
        evidence = _string(item.get("semanticEvidence"), f"{item_path}.semanticEvidence")
        if evidence not in {"none", "partial", "verified"}:
            _fail(f"{item_path}.semanticEvidence", "expected none, partial, or verified")
        if maturity == "measurementOnly" and evidence == "verified":
            _fail(f"{item_path}.semanticEvidence", "measurement-only asset cannot claim verified semantics")
        _string(item.get("notes"), f"{item_path}.notes")
    if len(ids) != len(set(ids)):
        _fail(f"{path}.assets", "duplicate asset IDs")
    summary = _object(inventory.get("summary"), f"{path}.summary")
    if summary.get("assetCount") != len(assets):
        _fail(f"{path}.summary.assetCount", "does not match assets length")
    if summary.get("semanticVerifiedCount") != sum(
        1 for asset in assets if asset["semanticEvidence"] == "verified"
    ):
        _fail(f"{path}.summary.semanticVerifiedCount", "does not match assets")
    return inventory


def _slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "step"


def _migration_observation(scenario: dict[str, Any], source_schema: str) -> dict[str, Any]:
    required = list(scenario["requiredObservations"])
    return {
        "schema": OBSERVATION_SCHEMA,
        "scenarioId": scenario["id"],
        "runner": {
            "name": "v0-manifest-adapter",
            "status": "skipped",
            "reason": f"{source_schema} does not contain normalized observations",
        },
        "provenanceComplete": False,
        "observedMatch": False,
        "observationCoverage": {"required": required, "covered": [], "missing": required},
        "steps": [{"id": step["id"], "observations": {}} for step in scenario["steps"]],
        "semanticMatch": False,
    }


def _near_required(manifest: dict[str, Any]) -> list[str]:
    required = ["callStatus"]
    steps = manifest.get("scenario", {}).get("steps", [])
    if any(
        "view" in step or "expect" in step or any(key.startswith("expectReturn") for key in step)
        for step in steps
    ):
        required.append("returnValue")
    if manifest.get("state"):
        required.append("state")
    return required


def migrate_near_v0(manifest: dict[str, Any], source_path: str) -> dict[str, Any]:
    if manifest.get("schema") != NEAR_V0_SCHEMA:
        _fail("manifest.schema", f"expected {NEAR_V0_SCHEMA!r}")
    program = _string(manifest.get("program"), "manifest.program")
    inferred: list[str] = []
    framework = manifest.get("framework")
    if not framework:
        framework = "near-sdk-rs"
        inferred.append("framework=near-sdk-rs")
    framework = _string(framework, "manifest.framework")
    source = manifest.get("source")
    if not source:
        source = "src/lib.rs"
        inferred.append("source=src/lib.rs")
    source = _string(source, "manifest.source")
    upstream = _object(manifest.get("upstream", {}), "manifest.upstream")
    origin_name = upstream.get("name") or f"checked-in {framework} reference"
    steps: list[dict[str, Any]] = []
    raw_steps = manifest.get("scenario", {}).get("steps", [])
    for index, raw_step in enumerate(raw_steps, start=1):
        step = _object(raw_step, f"manifest.scenario.steps[{index - 1}]")
        action = _string(step.get("call") or step.get("view"), f"manifest.scenario.steps[{index - 1}].call-or-view")
        steps.append(
            {
                "id": f"step-{index:02d}-{_slug(action)}",
                "action": action,
                "inputs": {k: v for k, v in step.items() if k not in {"call", "view"}},
            }
        )
    if not steps:
        offline_steps = manifest.get("scenario", {}).get("offline", [])
        for index, raw_action in enumerate(offline_steps, start=1):
            action = _string(raw_action, f"manifest.scenario.offline[{index - 1}]")
            steps.append({"id": f"step-{index:02d}-{_slug(action)}", "action": action, "inputs": {}})
        if steps:
            inferred.append("scenario.steps from scenario.offline text")
    if not steps:
        for index, raw_entrypoint in enumerate(manifest.get("entrypoints", []), start=1):
            entrypoint = _object(raw_entrypoint, f"manifest.entrypoints[{index - 1}]")
            action = _string(entrypoint.get("name"), f"manifest.entrypoints[{index - 1}].name")
            steps.append({"id": f"step-{index:02d}-{_slug(action)}", "action": action, "inputs": {}})
        if steps:
            inferred.append("scenario.steps from entrypoints")
    if not steps:
        _fail("manifest", "cannot infer any scenario steps")
    scenario = {
        "schema": SCENARIO_SCHEMA,
        "id": f"near-{_slug(program)}-v0",
        "kind": "targetExtension",
        "targetFamily": "near",
        "steps": steps,
        "requiredObservations": _near_required(manifest),
        "allowedDivergences": [],
        "migration": {"sourceSchema": NEAR_V0_SCHEMA, "sourcePath": source_path, "inferred": inferred},
    }
    reference = {
        "schema": REFERENCE_SCHEMA,
        "id": f"near-{_slug(program)}",
        "targetFamily": "near",
        "program": program,
        "framework": framework,
        "source": {"path": str(Path(source_path).parent / source), "language": "rust"},
        "provenance": {
            "status": "incomplete",
            "origin": {"name": origin_name, "url": upstream.get("url")},
            "revision": None,
            "license": None,
            "toolchain": [{"name": framework, "version": None}],
            "missing": ["revision", "license", "toolchainVersions"],
        },
        "proofForge": {
            "source": manifest.get("proofForgeSource"),
            "target": manifest.get("proofForgeTarget"),
            "module": manifest.get("proofForgeModule"),
        },
        "semanticEligibility": {
            "eligible": False,
            "reasons": ["v0 manifest does not pin revision, license, or toolchain versions"],
        },
        "migration": {"sourceSchema": NEAR_V0_SCHEMA, "sourcePath": source_path, "inferred": inferred},
    }
    result = {"reference": reference, "scenario": scenario, "observation": _migration_observation(scenario, NEAR_V0_SCHEMA)}
    validate_reference(reference)
    validate_scenario(scenario)
    validate_observation(result["observation"])
    return result


def migrate_solana_v0(manifest: dict[str, Any], source_path: str) -> dict[str, Any]:
    if manifest.get("schema") != SOLANA_V0_SCHEMA:
        _fail("manifest.schema", f"expected {SOLANA_V0_SCHEMA!r}")
    inferred: list[str] = []
    program = manifest.get("program")
    if not program:
        program = Path(source_path).parent.name
        inferred.append(f"program={program}")
    program = _string(program, "manifest.program")
    framework = manifest.get("framework")
    if not framework:
        framework = "pinocchio"
        inferred.append("framework=pinocchio")
    framework = _string(framework, "manifest.framework")
    source = manifest.get("source")
    if not source:
        source = "src/lib.rs"
        inferred.append("source=src/lib.rs")
    source = _string(source, "manifest.source")
    raw_entrypoints = [manifest["entrypoint"]] if isinstance(manifest.get("entrypoint"), dict) else manifest.get("entrypoints", [])
    if not raw_entrypoints:
        _fail("manifest", "expected entrypoint or entrypoints")
    steps: list[dict[str, Any]] = []
    for index, raw_entrypoint in enumerate(raw_entrypoints, start=1):
        entrypoint = _object(raw_entrypoint, f"manifest.entrypoints[{index - 1}]")
        action = _string(entrypoint.get("name"), f"manifest.entrypoints[{index - 1}].name")
        steps.append({"id": f"step-{index:02d}-{_slug(action)}", "action": action, "inputs": {}})
    required = ["callStatus", "interface"]
    if manifest.get("cpis"):
        required.append("externalActions")
    if manifest.get("stateWrites"):
        required.append("state")
    scenario = {
        "schema": SCENARIO_SCHEMA,
        "id": f"solana-{_slug(program)}-v0",
        "kind": "targetExtension",
        "targetFamily": "solana",
        "steps": steps,
        "requiredObservations": required,
        "allowedDivergences": [],
        "migration": {"sourceSchema": SOLANA_V0_SCHEMA, "sourcePath": source_path, "inferred": inferred},
    }
    reference = {
        "schema": REFERENCE_SCHEMA,
        "id": f"solana-{_slug(program)}",
        "targetFamily": "solana",
        "program": program,
        "framework": framework,
        "source": {"path": str(Path(source_path).parent / source), "language": "rust"},
        "provenance": {
            "status": "incomplete",
            "origin": {"name": f"checked-in {framework} reference", "url": None},
            "revision": None,
            "license": None,
            "toolchain": [{"name": framework, "version": None}],
            "missing": ["revision", "license", "toolchainVersions"],
        },
        "proofForge": {
            "fixture": manifest.get("proofForgeFixture"),
            "sourceFixture": manifest.get("proofForgeSourceFixture"),
        },
        "semanticEligibility": {
            "eligible": False,
            "reasons": ["v0 manifest does not pin revision, license, or toolchain versions"],
        },
        "migration": {"sourceSchema": SOLANA_V0_SCHEMA, "sourcePath": source_path, "inferred": inferred},
    }
    result = {"reference": reference, "scenario": scenario, "observation": _migration_observation(scenario, SOLANA_V0_SCHEMA)}
    validate_reference(reference)
    validate_scenario(scenario)
    validate_observation(result["observation"])
    return result


def migrate_manifest(path: Path, repo_root: Path) -> dict[str, Any]:
    relative = path.relative_to(repo_root).as_posix()
    with path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    schema = manifest.get("schema")
    if schema == NEAR_V0_SCHEMA:
        return migrate_near_v0(manifest, relative)
    if schema == SOLANA_V0_SCHEMA:
        return migrate_solana_v0(manifest, relative)
    _fail("manifest.schema", f"unsupported schema {schema!r}")
