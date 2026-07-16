# Solana sBPF ↔ solanalib Bridge (Scheme 1 + Scheme 2 Phase A/B + host)

Status: **Counter + ValueVault host stack landed** (2026-07) — mathlib-free
encode + labeled view + solanalib lift/verify + core-tail/full-program hosts +
IR paired simulation + composition + TargetSemantics registration.

**Portable IR is mandatory.** See
[portable-ir-semantics-anchor.md](portable-ir-semantics-anchor.md). This bridge
never bypasses `IR.Module` / `IR.Semantics`.

## Goal

Hook ProofForge's EmitSBPF output into
[`solana-foundation/leanprover-solanalib`](https://github.com/solana-foundation/leanprover-solanalib)
for **post-hoc** verification, without changing the product emit path
(`IR → AstNode → .s → sbpf → ELF`).

This is the Solana counterpart of the EVM `ProofForgeFormalEvm` / powdr adapter:

| Lane | Default (mathlib-free) | Opt-in (external semantics) |
|------|------------------------|-----------------------------|
| EVM | `EvmBytecodeSemantics` | `ProofForgeFormalEvm` → powdr `stepF` |
| Solana | `BpfEncode` + `LabeledSbpf` + `SbpfInterpreter` | `ProofForgeFormalSolana` → solanalib lift / `bpfInterp` / `verifyInstr` |

## Architecture

```
Portable IR.Module  (+ IR.Semantics — multi-chain source of truth)
   │ SbpfAsm.lowerModule
   ▼
Array AstNode  ──render──►  .s text  ──sbpf──►  ELF   (product path, unchanged)
   │
   │ LabeledSbpf.fromNodes       ← Scheme 2 Phase A (labeled register asm)
   ▼
LabeledProgram / ResolvedInst[]
   │ BpfEncode.toBpfBin          ← default path, no mathlib
   ▼
BpfBinBytes (Array Nat)
   │
   ├─ SolanalibAdapter.toBpfBin + decodeAll     ← byte path
   │
   └─ LabeledToSolanalib.liftSlots              ← Scheme 2 Phase B (direct lift)
         ▼
List BpfInstruction
   │ verifyInstr  (+ step_ne_err)
   │ bpfInterp    (host bridge still open)
   ▼
BpfState
```

## What landed

| Piece | Module | Gate |
|-------|--------|------|
| Binary encoder | `ProofForge/Backend/Solana/BpfEncode.lean` | `just solana-bpf-encode-smoke` |
| Labeled sBPF view | `ProofForge/Backend/Solana/LabeledSbpf.lean` | same |
| Unit + Counter/ValueVault encode | `Tests/Backend/Solana/SolanaBpfEncode.lean` | same |
| solanalib adapter | `ProofForgeFormal/Solana/SolanalibAdapter.lean` | `just solana-solanalib-adapter` |
| Direct lift ResolvedInst→BpfInstruction | `ProofForgeFormal/Solana/LabeledToSolanalib.lean` | same |
| Host bridge (Counter core-tail) | `ProofForgeFormal/Solana/HostBridge.lean` | same |
| Full EmitSBPF Counter host | `ProofForgeFormal/Solana/FullProgramHost.lean` | same |
| IR ↔ full-host paired simulation | `ProofForgeFormal/Solana/CounterHostRefinement.lean` | same |
| Core-tail host ≡ abstract model | `ProofForgeFormal/Solana/CoreTailHostComposition.lean` | same |
| ValueVault IR ↔ host lockstep | `ProofForgeFormal/Solana/ValueVaultHostRefinement.lean` | same |
| Full-host `TargetSemantics` | `ProofForgeFormal/Solana/FullHostTargetSemantics.lean` | same |
| CompileCorrect sketch | `ProofForgeFormal/Solana/CompileCorrect.lean` | same |
| Smoke entry | `ProofForgeFormal/Solana/CompileCorrectSmoke.lean` | same |
| IR semantics anchor note | `docs/portable-ir-semantics-anchor.md` | docs |

### Encode conventions

- Instruction layout matches solanalib `findInstr` (8-byte slots; `lddw` = 16).
- Jump offsets are **relative** slot deltas `target - (pc + 1)`.
- Label PCs are remapped from ProofForge instruction indices to **slot**
  indices so `lddw` (2 slots) does not desync relative jumps.
- Stack-relative mem ops (`base = r10`) encode offset as **negative i16**
  (AST stores a positive distance; the text printer already shows `[r10-off]`).
- Syscall `call` immediates use a fixed murmur3-32 table for the covered
  fragment (`sol_set_return_data`, `sol_log_64_`, clock, …).

## Honest claims (Tier language)

Use the tiers in [formal-verification.md](formal-verification.md):

- **Tier C-diff (encode):** Counter/ValueVault lower to well-formed bytecode
  (`moduleEncodesOk`, `native_decide`).
- **Tier C-diff (labeled):** labeled view builds and matches encode
  (`moduleLabeledOk`, `labeledMatchesEncode`).
- **Tier C-diff (solanalib pipeline):** encoded Counter bytes decode under
  solanalib and pass `verifyInstr` v1 (`counter_solanalib_pipeline_ok`).
- **Tier C-diff (direct lift):** `liftResolved` instruction list equals
  `decodeAll ∘ encode` and verifies (`counter_lift_matches_decode`).
- **Tier C-diff (host bridge):** Counter core-tail programs
  (`initialize` / `increment` / `get`) run on a syscall-aware solanalib step
  driver with word↔byte memory + `sol_set_return_data` stub; success `r0`,
  `countOff`, and return-data match ProofForge core-tail finals; sequential
  init→get→inc→get yields observables `none, 0, none, 1`
  (`counter_core_tail_bridge_ok`, `sequential_core_tail_trace_ok`).
- **Tier C-diff (full program):** complete EmitSBPF Counter (account scan,
  owner checks, discriminator dispatch, entrypoint bodies) runs on
  `FullProgramHost` with zero-default loads + PF `stackBase`/`initialMemory`;
  scenario observables match PF `SbpfInterpreter.runTrace`
  (`counter_full_program_host_ok`, `counter_full_program_diff_ok`).
- **Tier C-diff / C-proof bridge (IR↔host):** pointwise
  `executableSimulationTraceOk` between `IR.Semantics` and
  `FullProgramHost.traceStep` over init→get→inc→get, plus
  `executableSimulationTraceOk_sound` kernel wrappers and a
  `CounterCall`-vocabulary variant (`CounterHostRefinement`).
- **Structural re-export:** `verified_instr_step_ne_err` names solanalib
  Lemma 6.4 (`step_ne_err`) for ProofForge-facing proofs.
- **Tier C-diff (ValueVault full program):** default ValueVault scenario on
  full host matches PF interpreter (`value_vault_full_program_*`).
- **Not claimed:** universal all-input `IR ⇝ host` refinement (still
  pointwise on fixed scenarios); broad syscall fidelity. Product path still
  emits text via EmitSBPF.

## Build / CI

```bash
# Default path (no solanalib download beyond existing deps)
just solana-bpf-encode-smoke

# Opt-in (pulls solanalib + mathlib; mirrors just evm-powdr-adapter)
just solana-solanalib-adapter
```

`solana-solanalib-adapter` is **not** on the required `just product` /
`just check` path (same policy as `evm-powdr-adapter`).

## Completion checklist (Solana host lane)

1. ~~Host bridge for Counter core-tail (init/inc)~~ ✅.
2. ~~`get` + `sol_set_return_data` stub + sequential init→get→inc→get~~ ✅.
3. ~~Full EmitSBPF Counter + PF interpreter differential~~ ✅.
4. ~~IR ↔ full-host paired simulation (pointwise)~~ ✅.
5. ~~ValueVault full-program host + PF differential~~ ✅.
6. ~~Core-tail host ≡ abstract `counterSbpfCoreTraceStep` grid + IR lockstep~~ ✅.
7. ~~ValueVault IR ↔ host paired simulation~~ ✅.
8. ~~`TargetSemantics` registration for full host~~ ✅.

**Remaining research (not blocking this lane):** universal all-input
per-entrypoint simulation on the full host (no fixed scenarios); Scheme 2
Phase C assembler-in-Lean; broader syscalls. Product text emission is
unchanged.
