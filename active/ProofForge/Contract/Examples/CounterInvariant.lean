import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.LeanInvariant
import ProofForge.IR.Semantics

/-! ## FV-8 user-authored Lean invariants — Counter authoring example

Canonical Counter instance of the FV-8 user-invariant authoring mode (Track
1.7). The author declares a `countBounded` Lean invariant (parallel to the
`quint_invariant` annotation, which is a string expression for Quint MBT) and
machine-checks it holds after a scenario pre-codegen.
-/

namespace ProofForge.Contract.Examples.CounterInvariant

open ProofForge.IR
open ProofForge.Contract.LeanInvariant

abbrev SemState := ProofForge.IR.Semantics.State

def module : Module :=
  ProofForge.Contract.Examples.Counter.module

/-! ### User-declared Lean invariant -/

/-- `countBounded`: after a bounded-increment scenario, the count does not
exceed the scenario bound. This is the Lean-side invariant corresponding to
the `quint_invariant countBounded := "count <= MAX_UINT"` annotation, but
checked here by Lean reduction rather than Quint MBT. -/
def countBounded (bound : Nat) (state : SemState) : Bool :=
  readU64D state "count" <= bound

/-- Non-negative count: the count is never negative (trivially true for
`Nat`-backed storage, but illustrates the authoring pattern for a
purely-Lean invariant that does not mirror a Quint annotation). -/
def countNonNegative (state : SemState) : Bool :=
  readU64D state "count" >= 0

def counterInvariants (bound : Nat) : ContractInvariants :=
  { moduleName := module.name
    invariants := #[
      InvariantSpec.declare "countBounded" (countBounded bound),
      InvariantSpec.declare "countNonNegative" countNonNegative
    ] }

/-! ### Scenario: initialize then increment `n` times -/

def incrementScenario (n : Nat) : Array ScenarioStep :=
  #[{ entrypointName := "initialize" }] ++
    (List.replicate n { entrypointName := "increment" } |>.toArray)

def initialState : SemState := ProofForge.IR.Semantics.State.empty

/-! ### Pre-codegen machine check -/

def verified (bound n : Nat) : Bool :=
  verifyInvariantsAfterScenario module (counterInvariants bound)
    initialState (incrementScenario n)

/-- After `n` increments from the empty state, `countBounded n` holds (the count
is exactly `n`, hence `≤ n`), and `countNonNegative` holds trivially. -/
theorem counter_invariants_hold_after_scenario :
    verified 3 3 = true := by
  native_decide

/-- Soundness bridge for the Counter invariants. -/
theorem counter_invariants_sound (bound n : Nat)
    (h : verified bound n = true) :
    ∃ finalState, allInvariantsHold (counterInvariants bound) finalState = true ∧
      (∃ observed, runScenario module initialState (incrementScenario n) = .ok (finalState, observed)) := by
  unfold verified at h
  exact invariants_hold_after_scenario module (counterInvariants bound)
    initialState (incrementScenario n) h

end ProofForge.Contract.Examples.CounterInvariant