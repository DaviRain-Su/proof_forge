import ProofForge.Backend.Evm.Refinement

/-! Tier C-proof Phase 6b — `EVMYulLean` EVM bytecode semantics adapter.

**Status: BLOCKED — seam/stub only (2026-07-07).**

The intended integration is to add `leonardoalt/EVMYulLean` as a `lake`
dependency and expose a thin adapter around its `EvmYul.EVM.Semantics.step`
(opcode-granular EVM bytecode step, conformance-tested against the official
`ethereum/tests` Cancun suite — 22,330/22,332 passing) aligned with
ProofForge's `ObservableStep` (defined in `Refinement.lean`).

That integration is currently blocked by a **Lean toolchain version
mismatch** (see `docs/phase-6b-integration-blockers.md` for the full
record):

- `EVMYulLean` pins `leanprover/lean4:v4.22.0` in its `lean-toolchain` and
  `require mathlib from git "https://github.com/leanprover-community/mathlib4.git"@"v4.22.0"`
  in its `lakefile.lean`. mathlib v4.22.0 is tightly coupled to the
  v4.22.0 toolchain and will not compile under a newer Lean.
- ProofForge pins `leanprover/lean4:v4.31.0` in its `lean-toolchain` and has
  no mathlib dependency. A single lake workspace uses one toolchain; we
  cannot have both v4.22.0 (for EVMYulLean+mathlib) and v4.31.0 (for
  ProofForge) simultaneously.
- Per the Phase 6b task constraint, ProofForge is NOT downgraded to
  v4.22.0 — that would break the existing 378-job build. The mismatch is
  documented as a blocker and the seam is left for a CI/local-with-network
  run once the toolchains align (see the resolution path in
  `docs/phase-6b-integration-blockers.md`).

This file therefore provides the **adapter signature** with a stub body so
that:

1. `lake build` stays green for the existing ProofForge build — this
   module compiles with NO external dependency (it imports only
   `ProofForge.Backend.Evm.Refinement`, which already builds).
2. The seam is ready: when the toolchain blocker is resolved, replace the
   stub `State`/`step`/`runBytecode` bodies with the real
   `EvmYul.EVM.State` / `EvmYul.EVM.Semantics.step` imports and the driver
   logic, without changing the adapter's public surface or any caller in
   `Refinement.lean` (theorems there are untouched — wiring is Phase 6c).
3. The `sorry`-free stub theorems below (`step_noop`, `runBytecode_empty`)
   type-check today and will be replaced by real simulation lemmas in 6c.

This stub does NOT pull the `EthereumTests` submodule (too heavy; CI-only)
and does NOT add a `require` entry to `lakefile.lean`.
-/

namespace ProofForge.Backend.Evm.EvmBytecodeSemantics

open ProofForge.Backend.Evm.Refinement

/-- Stub EVM bytecode state.

The real type is `EvmYul.EVM.State` from
`leonardoalt/EVMYulLean` (`EvmYul/EVM/State.lean`), which models the full EVM
state (stack, memory, storage, code, pc, gas, …). It is not available as a
lake dependency yet (toolchain mismatch — see the module docstring above).
This stub is an opaque placeholder so the adapter signature compiles. -/
structure State where
  -- Placeholder payload. Opaque until EVMYulLean is wired; the real
  -- `EvmYul.EVM.State` has many fields and is not isomorphic to this.
  deriving Repr

/-- Construct an empty stub EVM state (the adapter's entry point). -/
def empty : State := ⟨⟩

/-- Stub single opcode-granular EVM step.

The real signature mirrors `EvmYul.EVM.Semantics.step` (an EVM state
transition at opcode granularity). Until EVMYulLean is wired, this is a
no-op that returns the state unchanged, which lets the adapter compile and
gives a reflexive `step_noop` theorem below. -/
def step (s : State) : State := s

/-- Halting predicate for the bytecode driver. Stub: never halts (the
no-op `step` runs forever), so `runBytecode` is bounded by `maxSteps`. -/
def isHalted (_s : State) : Bool := false

/-- Bytecode driver aligned with ProofForge's `ObservableStep`
(`Refinement.ObservableStep`).

Runs `step` up to `maxSteps` times, stopping when `isHalted` holds, and
collects observable steps. The real driver (Phase 6c) will project each EVM
`step` into an `ObservableStep` via the simulation relation
`R : IR.State ↔ EVM.State`; this stub returns the initial state and an
empty observable array, which is the trivial base case. -/
def runBytecode (init : State) (_maxSteps : Nat) :
    Except String (State × Array ObservableStep) :=
  .ok (init, #[])

/-- The stub step is a no-op (reflexive). This is a `sorry`-free stub
theorem that type-checks today; it is NOT a simulation lemma and will be
replaced by the real per-entrypoint simulation in Phase 6c. -/
theorem step_noop (s : State) : step s = s := rfl

/-- The stub driver returns the initial state and no observables. This is
the trivial base case for the (future) trace-lifting induction. -/
theorem runBytecode_empty (init : State) (maxSteps : Nat) :
    runBytecode init maxSteps = .ok (init, #[]) := rfl

end ProofForge.Backend.Evm.EvmBytecodeSemantics