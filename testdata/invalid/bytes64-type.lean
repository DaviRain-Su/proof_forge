import ProofForgeV2

open ProofForgeV2.Language

program Bytes64Type where
  state value : Bytes64

  view get() : UInt64 do
    return 0
