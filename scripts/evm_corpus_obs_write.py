#!/usr/bin/env python3
"""Write one proof-forge.evm-observation.v1 (canonical) for EVMOZ-004 harnesses.

Usage:
  python3 -I -S scripts/evm_corpus_obs_write.py OUT_DIR CASE_ID LEG STEP \\
    STATUS RETURN_JSON LOGICAL_JSON EFFECTS_JSON ROLLBACK \\
    [EVM_JSON_OR_null]

RETURN/LOGICAL/EFFECTS are JSON text. EVM is JSON object or the token null.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 10:
        print("usage: evm_corpus_obs_write.py OUT CASE LEG STEP STATUS RET LOGIC EFF RB [EVM]", file=sys.stderr)
        return 2
    out_dir = Path(argv[1])
    case_id = argv[2]
    leg = argv[3]
    step = int(argv[4])
    status = argv[5]
    ret = json.loads(argv[6])
    logical = json.loads(argv[7])
    effects = json.loads(argv[8])
    rb = argv[9].lower() == "true"
    evm = None
    if len(argv) > 10 and argv[10] != "null":
        evm = json.loads(argv[10])

    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location(
        "evm_corpus_v1", root / "scripts" / "evm_corpus_v1.py"
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)

    verdict = "pass"
    skip_reason = None
    if leg == "reference":
        evm = None
    raw = mod.mint_observation_from_shared(
        case_id=case_id,
        leg=leg,
        step_index=step,
        status=status,
        return_value=ret,
        logical_state=logical,
        effects=effects,
        rollback_equal=rb,
        evm=evm,
        verdict=verdict,
        skip_reason=skip_reason,
    )
    dest = out_dir / case_id
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{leg}-step-{step}.json"
    path.write_bytes(raw)
    print(f"evm-corpus-obs-write: {path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
