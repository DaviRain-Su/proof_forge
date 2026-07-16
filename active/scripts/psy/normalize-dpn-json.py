#!/usr/bin/env python3
"""Normalize Dargo `DPNFunctionCircuitDefinition[]` JSON for stable golden diffs.

Strips path-local noise and sorts only where order is not semantically fixed.
Keeps method order as emitted (entrypoint order is part of the contract).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def normalize_method(method: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {
        "name": method.get("name"),
        "method_id": method.get("method_id"),
        "circuit_inputs": method.get("circuit_inputs") or [],
        "circuit_outputs": method.get("circuit_outputs") or [],
        "state_commands": method.get("state_commands") or [],
        "state_command_resolution_indices": method.get("state_command_resolution_indices")
        or [],
        "assertions": method.get("assertions") or [],
        "definitions": method.get("definitions") or [],
        "events": method.get("events") or [],
    }
    # Drop unknown top-level keys that dargo may add later only if empty noise;
    # preserve extras under _extra for visibility when present and non-empty.
    known = set(out)
    extra = {k: v for k, v in method.items() if k not in known and v not in (None, [], {}, "")}
    if extra:
        out["_extra"] = {k: extra[k] for k in sorted(extra)}
    return out


def normalize_document(data: Any) -> list[dict[str, Any]]:
    if not isinstance(data, list):
        raise SystemExit("DPN document must be a JSON array of method circuits")
    methods: list[dict[str, Any]] = []
    for i, method in enumerate(data):
        if not isinstance(method, dict):
            raise SystemExit(f"method[{i}] must be an object")
        for key in ("name", "method_id", "definitions"):
            if key not in method:
                raise SystemExit(f"method[{i}] missing required key {key!r}")
        methods.append(normalize_method(method))
    return methods


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize DPN circuit JSON")
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument("--check", action="store_true", help="validate only")
    args = parser.parse_args()
    raw = json.loads(args.input.read_text())
    normalized = normalize_document(raw)
    text = json.dumps(normalized, indent=2, sort_keys=False) + "\n"
    if args.check:
        print(f"normalize-dpn-json: ok methods={len(normalized)} file={args.input}")
        return 0
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
