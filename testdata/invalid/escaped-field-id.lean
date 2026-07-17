import ProofForgeV2

open ProofForgeV2.Language

program EscapedFieldId where
  state value : Field «bn254_fr»

  view get() : UInt64 do
    return 0
