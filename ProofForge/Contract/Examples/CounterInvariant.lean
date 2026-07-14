import ProofForge.Contract.Examples.Counter
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.IR.Core.Semantics

/-! ## Counter invariants over checked Canonical Core

The author-facing annotation names the predicates in this module. The executable
gate normalizes the single Product source and runs Core reference semantics; it
does not reconstruct the retired `ContractSpec` or v1 `IR.Module`.
-/

namespace ProofForge.Contract.Examples.CounterInvariant

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics

abbrev SemState := LogicalState

def host : HostSemantics where
  handle call _ _ := .error (.unknownHostOp call.id)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def initialState : SemState := default

def readCount (state : SemState) : Nat :=
  match state.storage ⟨0⟩ with
  | some (.scalar (.u64 value)) => value.toNat
  | _ => 0

/-- The count remains within the scenario bound. -/
def countBounded (bound : Nat) (state : SemState) : Bool :=
  readCount state <= bound

/-- The Core `u64` representation is non-negative by construction. -/
def countNonNegative (state : SemState) : Bool :=
  readCount state >= 0

def runCall (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (functionId : Nat) (state : SemState) : Except String SemState :=
  match execute host 100 checked ⟨functionId⟩ #[] state with
  | .ok result => .ok result.finalState
  | .error error => .error s!"Core execution failed: {repr error}"

def runIncrements (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    Nat → SemState → Except String SemState
  | 0, state => .ok state
  | n + 1, state => do
      let next ← runCall checked 1 state
      runIncrements checked n next

def runScenario (n : Nat) : Except String SemState := do
  let bundle ← match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      ProofForge.Contract.Examples.Counter.contract with
    | .ok bundle => .ok bundle
    | .error error => .error s!"Counter normalization failed: {repr error}"
  let initialized ← runCall bundle.contract 0 initialState
  runIncrements bundle.contract n initialized

def verified (bound n : Nat) : Bool :=
  match runScenario n with
  | .ok finalState => countBounded bound finalState && countNonNegative finalState
  | .error _ => false

theorem counter_invariants_hold_after_scenario :
    verified 3 3 = true := by
  native_decide

theorem counter_invariants_sound (bound n : Nat)
    (h : verified bound n = true) :
    ∃ finalState,
      (countBounded bound finalState && countNonNegative finalState) = true ∧
      runScenario n = .ok finalState := by
  unfold verified at h
  cases hsc : runScenario n with
  | error message => simp [hsc] at h
  | ok finalState =>
      refine ⟨finalState, by simpa [hsc] using h, ?_⟩
      simpa [hsc]

end ProofForge.Contract.Examples.CounterInvariant
