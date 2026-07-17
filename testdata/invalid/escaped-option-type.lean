import ProofForgeV2

open ProofForgeV2.Language

program EscapedOptionType where
  state value : «Option» UInt64

  view get() : UInt64 do
    return 0
