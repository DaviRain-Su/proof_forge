import ProofForge.Backend.Evm.EvmBytecodeSemantics

/-! ## EVM bytecode-semantics seam smoke

Pins the Phase 6b adapter surface for the preferred
`powdr-labs/evm-semantics` target. This does not import powdr or mathlib; it
keeps the default ProofForge build mathlib-free while ensuring the local seam
stays type-correct.
-/

namespace ProofForge.Tests.EvmBytecodeSemantics

open ProofForge.Backend.Evm.EvmBytecodeSemantics

#check State
#check Step
#check stepF
#check stepF_sound
#check runBytecode
#check runBytecode_empty

theorem empty_stepF_sound :
    Step empty empty :=
  stepF_sound (s := empty) (s' := empty) rfl

theorem empty_runBytecode_base :
    runBytecode empty 0 =
      .ok (empty, (#[] : Array ProofForge.Backend.Refinement.ObservableStep)) :=
  runBytecode_empty empty 0

end ProofForge.Tests.EvmBytecodeSemantics

def main : IO UInt32 := do
  IO.println "evm-bytecode-semantics-smoke: powdr-target adapter seam type-checks without external mathlib dependency"
  return 0
