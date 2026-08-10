#!/usr/bin/env python3
"""Derive a frontend/CLI ABI JSON from a ProofForge *.dpn.json package.

Official `dargo generate-abi` needs Psy-lang source (Dargo project). PF's product
artifact is DPN-only, so we synthesize a minimal ABI from circuit_inputs/outputs
+ method_id/name for wallets and pf execute docs.

Schemas emitted:
  - proof-forge.psy.abi.v1  (PF frontend)
  - optional official-shaped methods list for psy_user_cli --abi-path experiments

Engineering only — not a substitute for dargo ABI on full Psy-lang projects.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def dpn_to_abi(dpn: list, program: str) -> dict:
    methods = []
    for fn in dpn:
        name = fn.get("name") or "unknown"
        mid = int(fn.get("method_id") or 0)
        n_in = len(fn.get("circuit_inputs") or [])
        n_out = len(fn.get("circuit_outputs") or [])
        mode = "initialize" if name in ("initialize", "init") else (
            "view" if n_out and not any(
                "Set" in (c.get("type") or "") for c in (fn.get("state_commands") or [])
            ) else "entry"
        )
        # Heuristic view: no Set* state cmds
        is_view = not any(
            str(c.get("type", "")).startswith("Set") for c in (fn.get("state_commands") or [])
        )
        params = [
            {
                "name": f"arg{i}",
                "type": "u64",
                "feltSize": 1,
            }
            for i in range(n_in)
        ]
        returns = [{"name": f"ret{i}", "type": "u64", "feltSize": 1} for i in range(n_out)]
        methods.append(
            {
                "name": name,
                "methodId": mid,
                "mode": mode,
                "isView": is_view,
                "params": params,
                "returns": returns,
                "arity": {"inputs": n_in, "outputs": n_out},
                "callInputsJson": "[]" if n_in == 0 else "[" + ",".join(["0"] * n_in) + "]",
            }
        )
    return {
        "schema": "proof-forge.psy.abi.v1",
        "program": program,
        "target": "psy",
        "source": "derived-from-dpn",
        "note": "Synthesized from DPN; dargo generate-abi still preferred when .psy source exists",
        "methods": methods,
        # Official-ish thin projection (best-effort for tooling that expects methods[].method_id)
        "officialProjection": {
            "contract_name": program,
            "methods": [
                {
                    "name": m["name"],
                    "method_id": m["methodId"],
                    "is_view": m["isView"],
                    "params": [
                        {"name": p["name"], "param_type": "u64", "felt_size": 1}
                        for p in m["params"]
                    ],
                }
                for m in methods
            ],
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dpn", type=Path, required=True)
    ap.add_argument("-o", "--output", type=Path, help="Write ABI JSON (default stdout)")
    ap.add_argument("--program", default=None)
    args = ap.parse_args()
    data = json.loads(args.dpn.read_text())
    if not isinstance(data, list):
        print("DPN must be JSON array", file=sys.stderr)
        return 2
    program = args.program or args.dpn.name.replace(".dpn.json", "").replace(".json", "")
    abi = dpn_to_abi(data, program)
    text = json.dumps(abi, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
        print(f"wrote {args.output} methods={len(abi['methods'])}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
