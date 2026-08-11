---
id: TARGET-PSY-OP-COVERAGE
title: Psy DPN OP and feature coverage
status: draft
owner: engineering
updated: 2026-08-10
normative: false
---

# Psy DPN OP / feature coverage

Machine-readable: [`psy-op-coverage.v1.json`](psy-op-coverage.v1.json)  
Generator: `scripts/psy_dpn_op_coverage.py` · `just psy-dpn-op-coverage`

## Three layers (do not conflate)

| Layer | What it is | Full official OP surface? |
|---|---|---|
| Official `psy_vm` / `psy_user_cli simulate` | Host tool | Yes (official DPN) |
| PF emitter (`LowerPlanV1`) | ProgramV1 → DPN subset | **No** — capability-gated |
| PF session (`psy_dpn_session.py`) | Multi-step engineering harness | **No** — implements emitted subset + fail-closed |

## What is covered today

**Emitted + session + differential (strong):**

- StateCell: `initialize` / `increment` / `get` (continuity 7→12)
- OptionState: multi-leaf tag+payload (`setSome` / `peek` / `clear`)
- Accumulator, WideCounter (UInt128 limbs via u32 ops)
- MapMini: official put/get + session multi-key (`put`/`get`, overwrite, miss→0)
- EmitProbe: `emit` events (PARTIAL) official+session data/user/contract align
- CallProbe: void `call` → InvokeExternalContractFunctionSync (PARTIAL; no nested exec)
- ContextProbe: `pf.context.userId|contractId|checkpointId|nonce|callerContractId|userPublicKeyHash`
- ImtProbe: `pf.imt.set|get|contains` self-current (UInt64→limb0 pack); session multi-key continuity; store+return CSE (single SetIMT)
- HashProbe: `hashNoPad`/`hashTwoToOne`/`keccak256` official; `hashPad` emit-only; session fail-closed
- LoopSum: official run(0)/run(5) → +4; session continuity init(10)+run(0)=14

**Schema-only / not emitted by PF (not a session bug):**

- hash gadgets: **hashNoPad + hashTwoToOne + keccak256 open**; hashPad emit (official software-eval gap); merkle closed (`CalculateMerkleRoot` official `todo!`)
- IMT external/other-user cmds still FC; self-current Set/Get/Contains open (ImtProbe)
- secp256k1Verify, exp/divRem variants, many u32 const forms
- EVM-style ContextRead / Commit / result-bearing call / schedule (Plan FC)

**PARTIAL:**

- events: **EmitProbe covered** (session collects conditioned events; ordered-event runtime gate still PARTIAL)
- void call: **CallProbe covered** (shape + hashed QN + args; nested callee not executed)
- Map dense put: **fixed** (wire-resolved sub_slot + def-step resolution + encoded bool ops); MapMini put/get official+session green

## Regenerating

```bash
just psy-example-matrix   # builds examples + sessions + refreshes JSON
just psy-dpn-diff         # official vs session + continuity
just psy-dpn-op-coverage  # from build/v2/psy-op-audit or default
```

## Design gates (not bugs)

- Hash gadgets: [`../adr/0039-psy-hash-gadgets-gate.md`](../adr/0039-psy-hash-gadgets-gate.md)
- ContextRead / Commit (P3): [`psy-p3-context-commit-gate.md`](psy-p3-context-commit-gate.md)

