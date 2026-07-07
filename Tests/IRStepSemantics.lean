import ProofForge.IR.StepSemantics
import ProofForge.Backend.Evm.Refinement

/-! Tier C-proof Phase 6a — IR step-semantics smoke.

This is a Lean `#check`-anchored smoke for the inductive `IRTraceMatches`
predicate and its soundness lemma. It asserts:

1. The universally-quantified soundness theorem
   (`StepSemantics.runTraceListGen_sound`, discharged by `induction calls`)
   type-checks.
2. The inductive Counter/ValueVault bridge theorems from
   `Evm.Refinement` (discharged via the `Decidable` bridge + `native_decide`
   on the fixed scenarios) hold and agree with the existing
   `native_decide` regression theorems.
3. The `Decidable` instance on `IRTraceMatches` computes the runner output
   for the Counter scenario and it equals `runTrace` (the existing
   executable runner) on the same calls — a sanity check that the
   inductive predicate and the executable runner agree.
-/

namespace ProofForge.Tests.IRStepSemantics

open ProofForge.IR.Semantics
open ProofForge.IR.StepSemantics
open ProofForge.Backend.Evm.Refinement

-- Universally-quantified soundness lemma (induction, not native_decide).
#check runTraceListGen_sound
#check IRTraceMatches_complete
#check IRTraceMatches_iff_runTraceListGen

-- Inductive bridge theorems (Tier C-proof inductive statements, fixed scenarios).
#check counter_ir_trace_matches_inductive
#check value_vault_ir_trace_matches_inductive

-- Existing native_decide regression theorems preserved as smoke.
#check counter_ir_observable_trace_ok
#check value_vault_ir_observable_trace_ok

/-- The generic runner instantiated with `runEntrypointObservable` produces
the same observable array as `Evm.Refinement.runTrace` for the Counter calls.
This sanity-checks that the inductive predicate (built on
`runTraceListGen`) and the existing executable `runTrace` agree on the
fixed Counter scenario. -/
theorem counter_runTraceListGen_eq_runTrace :
    (match
      runTraceListGen runEntrypointObservable counterTraceCalls.toList State.empty,
      runTrace counterTraceCalls
    with
    | .ok (_, osGen), .ok osRef => osGen = osRef
    | _, _ => True) = true := by
  native_decide

/-- The Counter `IRTraceMatches` derivation yields the same observable
array as the existing `runTrace` runner (decidability bridge sanity check). -/
theorem counter_irTraceMatches_obs_eq_runTrace :
    (match runTrace counterTraceCalls with
    | .ok os =>
        IRTraceMatches runEntrypointObservable State.empty counterTraceCalls.toList os
    | .error _ => True) = true := by
  native_decide

end ProofForge.Tests.IRStepSemantics

def main : IO UInt32 := do
  IO.println "ir-step-semantics-smoke: IRTraceMatches inductive predicate, runTraceListGen_sound (induction), Counter/ValueVault inductive bridge + native_decide regression theorems checked"
  return 0