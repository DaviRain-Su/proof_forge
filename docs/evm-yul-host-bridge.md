# EVM Yul-subset ↔ IR Host Bridge

Status: **landed** (2026-07) — mathlib-free IR ↔ in-tree `YulSemantics`
paired simulation for Counter + ValueVault default scenario.

**Update (2026-07-10):** ValueVault now carries a multi-field storage relation
(balance / released / fees / last_value packed in slot 0; last_checkpoint /
operations packed in slot 1), not only return-value lockstep.

## Goal

Mirror the Solana solanalib host lane for EVM **without** leaving Portable IR
and **without** requiring powdr/mathlib on the default path:

```
Portable IR.Semantics
        │ executableSimulationTraceOk
        ▼
EvmYulMachineState  (lowered Yul object + WordBindings storage)
        │
        ├── product: Yul text → solc → bytecode  (unchanged)
        └── opt-in: EvmRefinement → powdr stepF   (bytecode lane)
```

## What landed

| Piece | Module | Gate |
|-------|--------|------|
| IR ↔ Yul Counter paired simulation | `ProofForge/Backend/Evm/YulHostRefinement.lean` | `just evm-yul-host-refinement-smoke` |
| CounterCall vocabulary lockstep | same | same |
| ValueVault default scenario lockstep + multi-field storage relation | same | same |
| Existing executable-trace anchors re-checked | same | same |
| Counter IR↔powdr bytecode delivery boundary | `EvmRefinement/CounterRefinement.lean` | `just evm-powdr-counter-refinement-smoke` |
| Counter runtime bytecode matches CLI emit witness | `scripts/evm/powdr-counter-runtime-smoke.sh` | `just evm-powdr-counter-runtime` |
| Counter Yul→bytecode verified via external `solc` | `scripts/evm/yul-compiler-counter-smoke.sh` | `just evm-yul-compiler-counter-smoke` |

### Storage relation (Counter)

IR `count : U64` relates to the low 64 bits of Yul storage slot `0`
(`word % 2^64`). The relation reads slot, byte offset, and byte width from the
canonical EVM storage plan, matching Solidity-compatible low-order packing.

### Storage relation (ValueVault)

All six `U64` scalar fields are packed by the standard EVM layout
(`ProofForge.Backend.Evm.Plan.storageLayout`) into two storage slots:

| Field | Slot | Byte offset | Extraction |
|-------|------|-------------|------------|
| `balance` | 0 | 0 | `word % 2^64` |
| `released` | 0 | 8 | `(word / 2^64) % 2^64` |
| `fees` | 0 | 16 | `(word / 2^128) % 2^64` |
| `last_value` | 0 | 24 | `(word / 2^192) % 2^64` |
| `last_checkpoint` | 1 | 0 | `word % 2^64` |
| `operations` | 1 | 8 | `(word / 2^64) % 2^64` |

The relation is checked at every step by `valueVaultYulTraceOk` and
witnessed by `value_vault_yul_trace_simulation_sound_checked`.

### Honest claims

- **Tier C-diff:** fixed Counter and ValueVault scenarios match IR observables
  under `YulSemantics` (pointwise `native_decide`).
- **Delivery boundary (Counter):** the CLI-emitted Counter runtime bytecode
  matches the embedded powdr witness (`just evm-powdr-counter-runtime`), and
  compiling the emitted Yul with external `solc --strict-assembly` reproduces
  that runtime code (`just evm-yul-compiler-counter-smoke`).
- **Not claimed:** universal all-input IR↔Yul refinement; powdr bytecode
  equivalence beyond Counter; solc hop for products other than Counter.
  Those remain opt-in / future work.

## Relation to Solana lane

| Solana | EVM |
|--------|-----|
| `BpfEncode` + solanalib host | `IR.lowerModule` + `YulSemantics` |
| `FullProgramHost` | `EvmYulMachineState` (already in `Evm.Refinement`) |
| `CounterHostRefinement` | `YulHostRefinement` |
| `just solana-solanalib-adapter` | `just evm-yul-host-refinement-smoke` |

## Next work

1. ~~Multi-field storage relation for ValueVault (not only observables).~~ ✅ Done.
2. ~~Strengthen powdr delivery boundary (opt-in) for Counter bytecode.~~ ✅ Done.
3. ~~Optional: yul-compiler integration for verified Yul→bytecode (external).~~ ✅ Done for Counter.

Future: extend the external `solc` Yul→bytecode verification to ValueVault and
other product sources as their powdr/bytecode witnesses land.
