import ProofForgeV2

open ProofForgeV2.Language

program Uint8SecondToken where
  state value : UInt8 bn254_fr

  view get() : UInt64 do
    return 0
