import ProofForgeV2

open ProofForgeV2.Language

program UnknownFieldConstructor where
  state value : Scalar bn254_fr

  view get() : UInt64 do
    return 0
