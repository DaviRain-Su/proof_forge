import ProofForgeV2

open ProofForgeV2.Language

program PluralOptionType where
  state value : Options UInt64

  view get() : UInt64 do
    return 0
