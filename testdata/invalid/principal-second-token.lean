import ProofForgeV2

open ProofForgeV2.Language

program PrincipalSecondToken where
  state value : Principal bn254_fr

  view get() : UInt64 do
    return 0
