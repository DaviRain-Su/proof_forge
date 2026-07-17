import ProofForgeV2

open ProofForgeV2.Language

program Unit64Type where
  state value : Unit64

  view get() : UInt64 do
    return 0
