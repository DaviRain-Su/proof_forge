import ProofForgeV2

open ProofForgeV2.Language

program EscapedBoolType where
  state enabled : «Bool»

  view get() : UInt64 do
    return 0
