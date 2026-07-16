#!/usr/bin/env python3
"""Validate ProofForge benchmark result JSON rows (B1.1).

Pure-Python checker (no jsonschema dependency). Enforces the structural rules
in docs/benchmarks.md and benchmarks/schema/result.schema.json.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

SCHEMA_ID = "proof-forge.benchmark-result.v1"
SCHEMA_VERSION = 1
IMPLEMENTATIONS = {"proofforge", "native"}
TARGETS = {
    "evm",
    "solana-sbpf-asm",
    "wasm-near",
    "psy-dpn",
    "aleo-leo",
}
# Allowed cost field names per target (docs/benchmarks.md).
COST_KEYS: dict[str, set[str]] = {
    "evm": {"evm_gas"},
    "solana-sbpf-asm": {"solana_cu"},
    "wasm-near": {"wasmtime_fuel_cumulative", "wasmtime_fuel_delta", "near_gas"},
    "psy-dpn": {"dpn_definition_count", "dpn_op_count", "execute_wall_ms"},
    "aleo-leo": {"aleo_constraints", "aleo_proof_ms", "aleo_verify_ms"},
}
REQUIRED_ROOT = [
    "schema",
    "schemaVersion",
    "scenario",
    "target",
    "implementation",
    "commit",
    "toolVersions",
    "behavior",
    "costs",
    "artifactBytes",
]
OPTIONAL_ROOT = {"notes"}
SCENARIO_RE = re.compile(r"^bm-[a-z0-9-]+$")


def fail(message: str) -> None:
    print(f"benchmark-result-schema: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(cond: bool, message: str) -> None:
    if not cond:
        fail(message)


def validate_costs(path: pathlib.Path, target: str, costs: Any) -> None:
    require(isinstance(costs, dict), f"{path}: costs must be an object")
    allowed = COST_KEYS[target]
    for key, value in costs.items():
        require(
            key in allowed,
            f"{path}: costs key {key!r} not allowed for target {target!r}; "
            f"allowed={sorted(allowed)}",
        )
        if isinstance(value, dict):
            for step, amount in value.items():
                require(
                    isinstance(step, str) and step,
                    f"{path}: costs.{key} step names must be non-empty strings",
                )
                require(
                    isinstance(amount, (int, float)) and not isinstance(amount, bool),
                    f"{path}: costs.{key}.{step} must be a number",
                )
                require(amount >= 0, f"{path}: costs.{key}.{step} must be >= 0")
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            require(value >= 0, f"{path}: costs.{key} must be >= 0")
        else:
            fail(f"{path}: costs.{key} must be a number or per-step object")


def validate_behavior(path: pathlib.Path, behavior: Any) -> None:
    require(isinstance(behavior, dict), f"{path}: behavior must be an object")
    require("ok" in behavior, f"{path}: behavior.ok required")
    require("steps" in behavior, f"{path}: behavior.steps required")
    require(isinstance(behavior["ok"], bool), f"{path}: behavior.ok must be bool")
    steps = behavior["steps"]
    require(isinstance(steps, list), f"{path}: behavior.steps must be an array")
    for i, step in enumerate(steps):
        require(isinstance(step, dict), f"{path}: behavior.steps[{i}] must be object")
        require("name" in step, f"{path}: behavior.steps[{i}].name required")
        require(
            isinstance(step["name"], str) and step["name"],
            f"{path}: behavior.steps[{i}].name must be non-empty string",
        )
        if "return" in step:
            ret = step["return"]
            require(
                ret is None or isinstance(ret, str),
                f"{path}: behavior.steps[{i}].return must be string or null",
            )
        if "storage" in step:
            require(
                isinstance(step["storage"], dict),
                f"{path}: behavior.steps[{i}].storage must be object",
            )
        if "events" in step:
            require(
                isinstance(step["events"], list),
                f"{path}: behavior.steps[{i}].events must be array",
            )
        if "error" in step:
            err = step["error"]
            require(
                err is None or isinstance(err, str),
                f"{path}: behavior.steps[{i}].error must be string or null",
            )
        allowed_step = {"name", "return", "storage", "events", "error"}
        extra = set(step.keys()) - allowed_step
        require(not extra, f"{path}: behavior.steps[{i}] unexpected fields: {sorted(extra)}")

    # Honest skip/fail: when not ok, notes should explain (checked at root).
    if not behavior["ok"] and not steps:
        # Empty steps with ok=false is allowed (tool missing).
        pass


def validate_row(path: pathlib.Path, data: Any) -> None:
    require(isinstance(data, dict), f"{path}: root must be a JSON object")
    missing = [f for f in REQUIRED_ROOT if f not in data]
    require(not missing, f"{path}: missing root fields: {', '.join(missing)}")
    allowed_root = set(REQUIRED_ROOT) | OPTIONAL_ROOT
    extra = [k for k in data.keys() if k not in allowed_root]
    require(not extra, f"{path}: unexpected root fields: {', '.join(extra)}")

    require(data["schema"] == SCHEMA_ID, f"{path}: schema must be {SCHEMA_ID!r}")
    require(
        data["schemaVersion"] == SCHEMA_VERSION,
        f"{path}: schemaVersion must be {SCHEMA_VERSION}",
    )
    require(
        isinstance(data["scenario"], str) and SCENARIO_RE.match(data["scenario"]),
        f"{path}: scenario must match ^bm-[a-z0-9-]+$ (got {data['scenario']!r})",
    )
    require(
        data["target"] in TARGETS,
        f"{path}: target {data['target']!r} not in {sorted(TARGETS)}",
    )
    require(
        data["implementation"] in IMPLEMENTATIONS,
        f"{path}: implementation must be proofforge|native",
    )
    require(
        isinstance(data["commit"], str) and data["commit"],
        f"{path}: commit must be non-empty string",
    )
    require(
        isinstance(data["toolVersions"], dict),
        f"{path}: toolVersions must be an object",
    )
    for tool, ver in data["toolVersions"].items():
        require(isinstance(tool, str) and tool, f"{path}: toolVersions keys must be strings")
        require(isinstance(ver, str), f"{path}: toolVersions[{tool!r}] must be string")

    validate_behavior(path, data["behavior"])
    validate_costs(path, data["target"], data["costs"])

    require(
        isinstance(data["artifactBytes"], int) and not isinstance(data["artifactBytes"], bool),
        f"{path}: artifactBytes must be integer",
    )
    require(data["artifactBytes"] >= 0, f"{path}: artifactBytes must be >= 0")

    if "notes" in data:
        require(isinstance(data["notes"], str), f"{path}: notes must be string")

    # Rule: failed/skipped rows should not claim success costs as proof of parity.
    if not data["behavior"]["ok"]:
        require(
            "notes" in data and data["notes"].strip(),
            f"{path}: behavior.ok=false requires non-empty notes (honest skip/fail)",
        )


def load_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        fail(f"{path}: invalid JSON: {exc}")


def validate_file(path: pathlib.Path) -> None:
    data = load_json(path)
    if isinstance(data, list):
        require(data, f"{path}: empty array not allowed")
        for i, row in enumerate(data):
            validate_row(path.with_name(f"{path.name}[{i}]"), row)
    else:
        validate_row(path, data)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate ProofForge benchmark result JSON (B1.1)"
    )
    parser.add_argument(
        "paths",
        nargs="+",
        type=pathlib.Path,
        help="Result JSON file(s); each may be one row or an array of rows",
    )
    args = parser.parse_args()
    for path in args.paths:
        if not path.exists():
            fail(f"{path}: file does not exist")
        validate_file(path)
    print(f"benchmark-result-schema: ok ({len(args.paths)} file(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
