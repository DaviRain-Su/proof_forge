import ProofForgeV2

open ProofForgeV2.Language

program UnitSecondToken where
  state value : Unit bn254_fr

  view get() : UInt64 do
    return 0
