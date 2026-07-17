import ProofForgeV2

open ProofForgeV2.Language

program QualifiedPrincipalType where
  state value : Std.Principal

  view get() : UInt64 do
    return 0
