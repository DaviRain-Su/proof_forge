#!/usr/bin/env python3
"""Generate Psy DPN op/state-cmd coverage report (schema × emitter × session × artifacts)."""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Official schema OpTypeV1 (SchemaV1.lean toUInt16) — kept in sync manually with pin.
SCHEMA_OPS: dict[int, str] = {
    0: "inputTarget",
    1: "constant",
    2: "constantTrue",
    3: "constantFalse",
    4: "add",
    5: "sub",
    6: "mul",
    7: "div",
    8: "boolNot",
    9: "boolAnd",
    10: "boolOr",
    11: "xor",
    12: "nor",
    13: "eq",
    14: "lte",
    15: "gte",
    16: "gt",
    17: "lt",
    18: "splitBits",
    19: "sumBits",
    20: "targetAt",
    21: "hashNoPad",
    22: "hashPad",
    23: "select",
    24: "exp",
    25: "expConstantPower",
    26: "expConstantBase",
    27: "mod_",
    28: "modConstantDividend",
    29: "modConstantDivisor",
    30: "divRem4",
    31: "castU32",
    32: "u32And",
    33: "u32AndConstant",
    34: "u32Or",
    35: "u32OrConstant",
    36: "u32Xor",
    37: "u32XorConstant",
    38: "u32ShiftLeft",
    40: "u32ShiftLeftConstantBitDistance",
    41: "u32ShiftLeftConstantValue",
    42: "u32ShiftRight",
    43: "u32ShiftRightConstantBitDistance",
    44: "u32ShiftRightConstantValue",
    45: "calculateMerkleRoot",
    46: "getUserId",
    47: "getContractId",
    48: "getCheckpointId",
    49: "getNonce",
    50: "getUserPublicKeyHash",
    51: "getStateQueryResult",
    52: "getStateQueryResultSingle",
    53: "getStateCommandResultHash",
    54: "getStateCommandResultSingle",
    55: "getStateCommandResultArray",
    64: "unaryInverse",
    65: "unaryNegative",
    66: "u32InputTarget",
    67: "constantU32",
    68: "u32Add",
    69: "u32Sub",
    70: "u32Mul",
    71: "u32Div",
    72: "castFelt",
    73: "castBool",
    74: "boolInputTarget",
    75: "u32Mod",
    76: "u32Exp",
    77: "secp256k1Verify",
    78: "hashTwoToOne",
    79: "getCallerContractId",
    80: "getSessionProofTreeRoot",
    81: "keccak256",
}

SCHEMA_STATE_CMDS = [
    "GetSelfUserCurrentContractStateSlotSingle",
    "SetContractStateSlotSingle",
    "GetSelfUserCurrentContractStateSlotHash",
    "SetContractStateSlotHash",
    "InvokeExternalContractFunctionSync",
]

# Ops that LowerPlanV1 can push (static scan of emitter source + known u32 paths).
EMITTER_REACHABLE = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 23, 27,
    32, 34, 36, 38, 42, 46, 47, 48, 54, 72,
}

# Session implemented (fail-closed otherwise).
SESSION_IMPLEMENTED = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 23, 27,
    31, 32, 33, 34, 35, 36, 37, 38, 40, 42, 43, 46, 47, 48, 53, 54, 55,
    65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75,
}

SESSION_STATE = {
    "GetSelfUserCurrentContractStateSlotSingle": "implemented",
    "SetContractStateSlotSingle": "implemented",
    "GetSelfUserCurrentContractStateSlotHash": "implemented",
    "SetContractStateSlotHash": "implemented",
    "InvokeExternalContractFunctionSync": "partial",  # recorded, not nested-exec
}

# Official schema state cmds not in PF schema (fail-closed at codec).
OFFICIAL_ONLY_STATE = [
    "SetContractStateSlotRange",
    "ClearEntireTree",
    "InvokeExternalContractFunctionDeferred",
    "GetSelfUserCurrentContractStateSlotRange",
    "GetSelfUserExternalContractStateSlotHash",
    "GetSelfUserExternalContractStateSlotSingle",
    "GetSelfUserExternalContractStateSlotRange",
    "GetOtherUserContractStateSlotHash",
    "GetOtherUserContractStateSlotSingle",
    "GetOtherUserContractStateSlotRange",
    "GetCheckpointLeafStats",
    "GetContractLeaf",
    "GetGlobalStateRoots",
    "SetIMTContractStateValue",
    "GetSelfUserCurrentIMTContractStateValue",
    "GetSelfUserExternalIMTContractStateValue",
    "GetOtherUserIMTContractStateValue",
    "ContainsSelfUserCurrentIMTContractStateValue",
    "ContainsOtherUserIMTContractStateValue",
]


def scan_emitter_ops() -> set[int]:
    """Best-effort: map OpType names used in LowerPlan to ids."""
    text = (ROOT / "ProofForgeV2/Targets/Psy/Dpn/LowerPlanV1.lean").read_text()
    names = set(re.findall(r"\.(inputTarget|constant|constantTrue|constantFalse|add|sub|mul|div|boolNot|boolAnd|boolOr|xor|nor|eq|lte|gte|gt|lt|select|mod_|castU32|u32And|u32Or|u32Xor|u32ShiftLeft|u32ShiftRight|getUserId|getContractId|getCheckpointId|getStateCommandResultSingle|getStateCommandResultHash|getStateCommandResultArray|castFelt|unaryNegative|unaryInverse)", text))
    inv = {v: k for k, v in SCHEMA_OPS.items()}
    out = set()
    for n in names:
        if n in inv:
            out.add(inv[n])
    return out or set(EMITTER_REACHABLE)


def collect_artifact_ops(paths: list[Path]) -> tuple[Counter, Counter, dict[str, set[int]]]:
    ops: Counter = Counter()
    cmds: Counter = Counter()
    by_ex: dict[str, set[int]] = defaultdict(set)
    for p in paths:
        try:
            data = json.loads(p.read_text())
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        ex = p.parent.name
        for fn in data:
            for d in fn.get("definitions") or []:
                oid = int(d.get("op_type", -1))
                ops[oid] += 1
                by_ex[ex].add(oid)
            for c in fn.get("state_commands") or []:
                cmds[c.get("type", "?")] += 1
    return ops, cmds, by_ex


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifact-root", type=Path, default=ROOT / "build/v2/psy-op-audit")
    ap.add_argument("-o", type=Path, default=ROOT / "docs/targets/psy-op-coverage.v1.json")
    args = ap.parse_args()

    emitter = scan_emitter_ops() | set(EMITTER_REACHABLE)
    art_paths = list(args.artifact_root.rglob("*.dpn.json")) if args.artifact_root.exists() else []
    art_ops, art_cmds, by_ex = collect_artifact_ops(art_paths)

    ops_report = []
    for oid, name in sorted(SCHEMA_OPS.items()):
        in_emitter = oid in emitter
        in_session = oid in SESSION_IMPLEMENTED
        in_art = oid in art_ops
        if in_emitter and in_session and in_art:
            status = "covered"
        elif in_emitter and in_session:
            status = "emitter+session-no-artifact"
        elif in_emitter and not in_session:
            status = "P0-emitter-without-session"
        elif not in_emitter and in_session:
            status = "session-extra"
        else:
            status = "schema-only-not-emitted"
        ops_report.append(
            {
                "opId": oid,
                "name": name,
                "officialSchema": True,
                "pfEmitter": "reachable" if in_emitter else "not-reachable",
                "session": "implemented" if in_session else "unsupported",
                "seenInArtifacts": in_art,
                "artifactCount": int(art_ops.get(oid, 0)),
                "examples": sorted(ex for ex, s in by_ex.items() if oid in s),
                "status": status,
            }
        )

    state_report = []
    for name in SCHEMA_STATE_CMDS:
        state_report.append(
            {
                "name": name,
                "pfSchema": True,
                "session": SESSION_STATE.get(name, "unsupported"),
                "seenInArtifacts": name in art_cmds,
                "artifactCount": int(art_cmds.get(name, 0)),
            }
        )
    for name in OFFICIAL_ONLY_STATE:
        state_report.append(
            {
                "name": name,
                "pfSchema": False,
                "session": "unsupported",
                "seenInArtifacts": False,
                "artifactCount": 0,
                "note": "official psy_vm only; PF codec fail-closed",
            }
        )

    p0 = [r for r in ops_report if r["status"] == "P0-emitter-without-session"]
    summary = {
        "schemaOpCount": len(SCHEMA_OPS),
        "emitterReachableCount": len(emitter),
        "sessionImplementedCount": len(SESSION_IMPLEMENTED),
        "artifactOpKinds": len(art_ops),
        "artifactFiles": len(art_paths),
        "p0EmitterWithoutSession": [r["name"] for r in p0],
        "featureBacklog": [
            {
                "id": "hash-gadgets",
                "ops": ["hashNoPad", "hashPad", "hashTwoToOne", "keccak256", "calculateMerkleRoot"],
                "status": "hashNoPad+hashTwoToOne+keccak256 open; Array UInt64 4 full HashOut for hashNoPad/twoToOne only (HashOutProbe); keccak/context limb0; hashPad emit-only; merkle FC",
            },
            {
                "id": "IMT-state-cmds",
                "status": "self+external+other-user open via pf.imt.* (ImtProbe); CalculateMerkleRoot still FC (official todo!)",
            },
            {
                "id": "external-call-result",
                "status": "void-sync PARTIAL CallProbe covered (shape+hashes+args); nested exec absent; result/deferred FC",
            },
            {
                "id": "events",
                "status": "PARTIAL: EmitProbe official+session event data aligned; no ordered-event runtime gate",
            },
            {
                "id": "Map-dense-put",
                "status": "fixed 2026-08-10 + P1 diff/multi-key: wire-resolved sub_slot, def-step resolution, encoded bool ops",
            },
            {
                "id": "ContextRead-Commit",
                "status": "EVM context.* FC; pf.context.* open (limb0); Commit FC by ADR-0041 until PI checklist; merkle official todo!",
            },
            {
                "id": "wide-u128-u256",
                "status": "emitter schoolbook; session via u32 ops when present",
            },
        ],
        "layers": {
            "officialVm": "full official DPN via psy_user_cli simulate / psy_vm",
            "pfEmitter": "capability-gated ProgramV1 subset → DPN",
            "pfSession": "engineering multi-step harness; not full VM",
            "differential": "StateCell + expanded matrix in psy_dpn_diff_matrix.sh",
        },
    }

    out = {
        "version": "psy-op-coverage.v1",
        "updated": "2026-08-10",
        "authority": "supply-chain/psy-node-dpn-authority.v1.json",
        "summary": summary,
        "ops": ops_report,
        "stateCommands": state_report,
        "artifactOps": {str(k): v for k, v in sorted(art_ops.items())},
        "artifactStateCmds": dict(art_cmds),
    }
    args.o.parent.mkdir(parents=True, exist_ok=True)
    args.o.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.o}")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
