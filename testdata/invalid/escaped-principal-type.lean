import ProofForgeV2

open ProofForgeV2.Language

program EscapedPrincipalType where
  state value : «Principal»

  view get() : UInt64 do
    return 0
