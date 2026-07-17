import ProofForgeV2

open ProofForgeV2.Language

program MissingFieldId where
  state value : Field

  view get() : UInt64 do
    return 0
