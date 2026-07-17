import ProofForgeV2

open ProofForgeV2.Language

program UnknownFieldId where
  state value : Field pasta_fp

  view get() : UInt64 do
    return 0
