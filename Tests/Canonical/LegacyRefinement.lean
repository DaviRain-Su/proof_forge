import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import TestFixtures.Legacy.Refinement
import ProofForge.Contract.Spec

namespace Tests.Canonical.LegacyRefinement

open ProofForge.IR
open ProofForge.IR.Examples.Counter
open ProofForge.IR.Examples.ValueVault
open TestFixtures.Legacy.Refinement
open ProofForge.Contract

/-- Fixture that uses a rejected constructor (`whileLoop`). -/
def whileLoopModule : Module := {
  name := "WhileLoop",
  state := #[],
  entrypoints := #[{
    name := "run",
    body := #[.whileLoop (.literal (.bool true)) #[]]
  }]
}

/-- `LegacyScalarFragment` holds for the canonical Counter fixture. -/
example : legacyScalarFragmentB (ContractSpec.fromIR ProofForge.IR.Examples.Counter.module) = true := by
  native_decide

/-- `LegacyScalarFragment` holds for the canonical ValueVault fixture. -/
example : legacyScalarFragmentB (ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module) = true := by
  native_decide

/-- `LegacyScalarFragment` fails for a module that uses a rejected constructor. -/
example : legacyScalarFragmentB (ContractSpec.fromIR whileLoopModule) = false := by
  native_decide

end Tests.Canonical.LegacyRefinement

#check TestFixtures.Legacy.Refinement.observableRelation_of_match
