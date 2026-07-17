import ProofForgeV2

open ProofForgeV2.Language

program UnknownType where
  state value : Mystery

  view get() : UInt64 do
    return 0
