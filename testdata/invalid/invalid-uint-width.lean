import ProofForgeV2

open ProofForgeV2.Language

program InvalidUintWidth where
  state value : UInt7

  view get() : UInt64 do
    return 0
