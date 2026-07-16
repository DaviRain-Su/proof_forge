import ProofForge.IR.Semantics
import ProofForge.IR.Contract

/-! ## FV-8 user-authored Lean invariants (product differentiator)

This module provides the reusable authoring surface for user-declared Lean
invariants (Track 1.7 / FV-8). Authors state invariants next to
`contract_source`, proven pre-codegen against the IR semantics — a pure-Lean,
backend-agnostic product surface that differentiates ProofForge from
Reach/Solang.

Unlike `quintInvariants` (string expressions for Quint MBT), Lean invariants
are *executable predicates* over `IR.Semantics.State`. Because functions are
not storable in the serialized `ContractSpec`, the authoring pattern is:

1. Author writes a top-level `def <contract>_invariant (state : State) : Bool`
   next to `contract_source`.
2. Author bundles the invariant name + predicate into an `InvariantSpec`
   via `InvariantSpec.declare`.
3. A `verifyInvariants` gate runs a scenario trace and checks each invariant
   holds on the final state; the theorem `invariants_hold_after_scenario`
   witnesses this via `native_decide`.

This turns `ValueVaultInvariant` from a one-off scenario test into a reusable
authoring mode: any contract can declare invariants this way, and the gate
machine-checks them pre-codegen.
-/

namespace ProofForge.Contract.LeanInvariant

open ProofForge.IR.Semantics

/-- A user-authored Lean invariant: a name plus a decidable predicate over
the IR semantics state. -/
structure InvariantSpec where
  name : String
  predicate : State → Bool

/-- Declare a named Lean invariant. -/
def InvariantSpec.declare (name : String) (predicate : State → Bool) : InvariantSpec :=
  { name, predicate }

/-- Read a `u64` state scalar, returning `0` if absent or wrong-typed. -/
def readU64D (state : State) (name : String) : Nat :=
  match state.read name with
  | some (.u64 value) => value
  | _ => 0

/-- Read a `u64` state scalar as `Option Nat`. -/
def readU64? (state : State) (name : String) : Option Nat :=
  match state.read name with
  | some (.u64 value) => some value
  | _ => none

/-- A bundle of invariants for a contract, keyed by the contract/module name. -/
structure ContractInvariants where
  moduleName : String
  invariants : Array InvariantSpec := #[]

/-- Add an invariant to a contract's invariant bundle. -/
def ContractInvariants.add (bundle : ContractInvariants) (inv : InvariantSpec) :
    ContractInvariants :=
  { bundle with invariants := bundle.invariants.push inv }

/-- Check whether a single invariant holds on a state. -/
def invariantHolds (inv : InvariantSpec) (state : State) : Bool :=
  inv.predicate state

/-- Check whether all invariants in a bundle hold on a state. -/
def allInvariantsHold (bundle : ContractInvariants) (state : State) : Bool :=
  bundle.invariants.all (fun inv => invariantHolds inv state)

/-- A scenario step: run a named entrypoint with args, producing the next
state and an optional return value. -/
structure ScenarioStep where
  entrypointName : String
  args : Array Value := #[]

/-- Run a named entrypoint on a state, returning the next state and optional
return value. -/
def runStep (module : ProofForge.IR.Module) (state : State)
    (step : ScenarioStep) : Except String (State × Option Value) := do
  let entrypoint ←
    match module.entrypoints.find? (fun e => e.name == step.entrypointName) with
    | some e => .ok e
    | none => .error s!"entrypoint `{step.entrypointName}` not found in module `{module.name}`"
  runEntrypointWithArgs state entrypoint step.args

/-- Run a scenario (list of steps) from an initial state, returning the final
state and the list of observed returns. -/
def runScenario (module : ProofForge.IR.Module) (initial : State)
    (steps : Array ScenarioStep) : Except String (State × Array (Option Value)) := do
  let mut state := initial
  let mut observed := #[]
  for step in steps do
    let (nextState, ret?) ← runStep module state step
    state := nextState
    observed := observed.push ret?
  .ok (state, observed)

/-- Verify all invariants in a bundle hold after running a scenario from an
initial state. Returns `true` iff the scenario ran successfully and every
invariant holds on the final state. -/
def verifyInvariantsAfterScenario (module : ProofForge.IR.Module)
    (bundle : ContractInvariants) (initial : State)
    (steps : Array ScenarioStep) : Bool :=
  match runScenario module initial steps with
  | .ok (finalState, _) => allInvariantsHold bundle finalState
  | .error _ => false

/-- Soundness bridge: if `verifyInvariantsAfterScenario` returns `true`, then
the scenario ran successfully and all invariants hold on the final state.
Discharged by `native_decide` on concrete scenarios (the universal `∀ state`
form requires a structural invariant over the IR interpreter; the scenario-bound
form is the machine-checked authoring surface). -/
theorem invariants_hold_after_scenario (module : ProofForge.IR.Module)
    (bundle : ContractInvariants) (initial : State) (steps : Array ScenarioStep)
    (h : verifyInvariantsAfterScenario module bundle initial steps = true) :
    ∃ finalState, allInvariantsHold bundle finalState = true ∧
      (∃ observed, runScenario module initial steps = .ok (finalState, observed)) := by
  unfold verifyInvariantsAfterScenario at h
  cases hsc : runScenario module initial steps with
  | error msg =>
      simp [hsc] at h
  | ok result =>
      obtain ⟨finalState, observed⟩ := result
      simp only [hsc] at h
      refine ⟨finalState, h, observed, rfl⟩

end ProofForge.Contract.LeanInvariant