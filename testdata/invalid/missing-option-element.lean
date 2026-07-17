import ProofForgeV2

open ProofForgeV2.Language

program MissingOptionElement where
  state value : Option

  view get() : UInt64 do
    return 0
