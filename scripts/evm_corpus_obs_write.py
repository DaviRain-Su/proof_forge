#!/usr/bin/env python3
"""Write one proof-forge.evm-observation.v1 (canonical) for EVMOZ-004 harnesses.

Usage:
  python3 -I -S scripts/evm_corpus_obs_write.py OUT_DIR CASE_ID LEG STEP \\
    STATUS RETURN_JSON LOGICAL_JSON EFFECTS_JSON ROLLBACK \\
    SOURCE_HASH SEMANTIC_HASH [EVM_JSON_OR_null]

RETURN/LOGICAL/EFFECTS are JSON text. SOURCE_HASH / SEMANTIC_HASH are the
mandatory lowercase 64-hex subject-program identity digests (identity-bound
observation; no identity-less writing path). EVM is JSON object or the token
null.

Shared fields must stay Outcome-projection-honest: status/logicalState/effects/
rollbackEqual present; returnValue null on revert/trap. Do not invent
standardRevertCode or OutcomeWire leaves absent from Anvil observation.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 12:
        print(
            "usage: evm_corpus_obs_write.py OUT CASE LEG STEP STATUS RET LOGIC "
            "EFF RB SRC_HASH SEM_HASH [EVM]",
            file=sys.stderr,
        )
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
    source_hash = argv[10]
    semantic_hash = argv[11]
    evm = None
    if len(argv) > 12 and argv[12] != "null":
        evm = json.loads(argv[12])

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
        source_hash=source_hash,
        semantic_hash=semantic_hash,
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
