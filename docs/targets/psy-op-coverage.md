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
- LoopSum: session matches official single-call (loop body shape)

**Schema-only / not emitted by PF (not a session bug):**

- hash gadgets (`hashNoPad` / `hashPad` / `keccak256` / `hashTwoToOne` / merkle)
- IMT state commands (not in PF `StateCmdV1`; official-only)
- secp256k1Verify, exp/divRem variants, many u32 const forms
- ContextRead / Commit / result-bearing call / schedule (Plan FC)

**PARTIAL:**

- events (emitter encodes; session does not assert event list)
- void `InvokeExternalContractFunctionSync` (shape only)
- Map dense put: **fixed** (wire-resolved sub_slot + def-step resolution + encoded bool ops); MapMini put/get official+session green

## Regenerating

```bash
just psy-example-matrix   # builds examples + sessions + refreshes JSON
just psy-dpn-diff         # official vs session + continuity
just psy-dpn-op-coverage  # from build/v2/psy-op-audit or default
```
