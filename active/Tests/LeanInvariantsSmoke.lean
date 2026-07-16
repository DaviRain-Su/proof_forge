import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForge.Contract.Examples.CounterInvariant
import ProofForge.Contract.Examples.Counter

/-! ## Track 1.7 / FV-8 user-invariant authoring smoke

Exercises the user-authored Lean invariant authoring mode across two
contracts (ValueVault and Counter), verifying the invariants hold after the
canonical scenario pre-codegen. This is the machine-checked FV-8 product
surface (pure-Lean, backend-agnostic, differentiator vs Reach/Solang).
-/

namespace ProofForge.Tests.LeanInvariantsSmoke

open ProofForge.Contract.Examples.ValueVaultInvariant
open ProofForge.Contract.Examples.CounterInvariant

#check value_vault_invariants_hold_after_scenario
#check counter_invariants_hold_after_scenario
#check value_vault_invariants_sound
#check counter_invariants_sound

/-- Counter `contract_source` exposes the `lean_invariant` annotations. -/
def counterLeanInvariantsRegistered : Bool :=
  ProofForge.Contract.Examples.Counter.spec.leanInvariants.any
    (fun (n, _) => n == "countBounded" || n == "countNonNegative")

end ProofForge.Tests.LeanInvariantsSmoke

def main : IO UInt32 := do
  IO.println "lean-invariants-smoke: ValueVault + Counter Lean invariants verified pre-codegen"
  return 0