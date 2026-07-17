import ProofForgeV2

open ProofForgeV2.Language

program UnknownOptionElement where
  state value : Option Mystery

  view get() : UInt64 do
    return 0
