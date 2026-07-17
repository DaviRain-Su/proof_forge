import ProofForgeV2

open ProofForgeV2.Language

program Principal64Type where
  state value : Principal64

  view get() : UInt64 do
    return 0
