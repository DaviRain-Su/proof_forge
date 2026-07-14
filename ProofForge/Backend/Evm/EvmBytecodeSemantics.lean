import ProofForge.Backend.Evm.Refinement

/-! Tier C-proof Phase 6b — `powdr-labs/evm-semantics` adapter seam.

**Status: preferred target selected; opt-in powdr adapter wired (2026-07-07).**

The intended integration target is now
[`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics),
not `EVMYulLean`. `powdr-labs/evm-semantics` currently pins the same Lean
toolchain as ProofForge (`leanprover/lean4:v4.31.0`) and pulls
`mathlib @ v4.31.0`. Its surface is a relational EVM bytecode semantics:

- `EvmSemantics.EVM.State` — opcode-granular EVM state;
- `Step : State → State → Prop` and `Eval` / `Steps` — proof-facing
  small-step and big-step relations;
- `stepF` — executable shadow for fast differential checks, with a soundness
  theorem from `stepF` results to `Step`.

The remaining cost is not a toolchain blocker; it is dependency isolation.
ProofForge's default build is intentionally mathlib-free, so the real powdr
dependency lives behind the opt-in `ProofForgeFormalEvm` target. This file keeps the
default-build adapter signature and a sorry-free stub body; the real powdr
wrapper lives in `ProofForgeFormal/Evm/PowdrAdapter.lean`.

This file therefore provides the seam so that:

1. `lake build` stays green for the existing ProofForge build — this module
   compiles with NO external dependency (it imports only
   `ProofForge.Backend.Evm.Refinement`, which already builds).
2. The opt-in `ProofForgeFormalEvm` target provides real powdr-backed `State` /
   `Step` / `stepF` / `runBytecode` wrappers without changing callers in
   `Refinement.lean`.
3. The `sorry`-free stub theorems below (`stepF_sound`, `runBytecode_empty`)
   type-check today and will be replaced or strengthened
   by the real per-entrypoint simulation lemmas in Phase 6c.
-/

namespace ProofForge.Backend.Evm.EvmBytecodeSemantics

open ProofForge.Backend.Refinement

/-- Stub EVM bytecode state.

The real type is `EvmSemantics.EVM.State` from
`powdr-labs/evm-semantics` (`EvmSemantics/EVM/State.lean`), which models the
full EVM state. This stub is an opaque placeholder so the adapter signature
compiles without pulling the opt-in powdr/mathlib dependency into the default
build. -/
structure State where
  -- Placeholder payload. Opaque in the default build; the real
  -- `EvmSemantics.EVM.State` has many fields and is not isomorphic to this.
  deriving Repr

/-- Construct an empty stub EVM state (the adapter's entry point). -/
def empty : State := ⟨⟩

/-- Stub relational single-step semantics.

The real relation is powdr's proof-facing `EvmSemantics.EVM.Step`. This
stub only records the reflexive no-op transition so downstream proof shapes
can already target a `Prop`-valued relation. -/
inductive Step : State → State → Prop where
  | noop (s : State) : Step s s

/-- Stub executable shadow for the relational EVM step.

The real executable is powdr's `stepF`; its soundness theorem maps successful
execution into the relational `Step`. This stub returns the state unchanged. -/
def stepF (s : State) : Except String State := .ok s

/-- Halting predicate for the bytecode driver. Stub: never halts (the
executable shadow has no halting state), so `runBytecode` is bounded by
`maxSteps`. -/
def isHalted (_s : State) : Bool := false

/-- Bytecode driver aligned with ProofForge's `ObservableStep`
(`Refinement.ObservableStep`).

The stub returns immediately with no observables. The real driver (Phase 6c)
will project each EVM
`Step` / `stepF` transition into an `ObservableStep` via the simulation relation
`R : IR.State ↔ EVM.State`; this stub returns the initial state and an
empty observable array, which is the trivial base case. -/
def runBytecode (init : State) (_maxSteps : Nat) :
    Except String (State × Array ObservableStep) :=
  .ok (init, (#[] : Array ObservableStep))

/-- Stub executable-shadow soundness. The real theorem is supplied by
`powdr-labs/evm-semantics` and will bridge `stepF` executions to `Step`
derivations. -/
theorem stepF_sound {s s' : State} (h : stepF s = .ok s') : Step s s' := by
  cases h
  exact Step.noop s

/-- The stub driver returns the initial state and no observables. This is
the trivial base case for the (future) trace-lifting induction. -/
theorem runBytecode_empty (init : State) (maxSteps : Nat) :
    runBytecode init maxSteps = .ok (init, (#[] : Array ObservableStep)) := rfl

end ProofForge.Backend.Evm.EvmBytecodeSemantics
