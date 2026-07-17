import ProofForgeV2

open ProofForgeV2.Language

program EscapedUnitType where
  state value : «Unit»

  view get() : UInt64 do
    return 0
