import ProofForgeV2

open ProofForgeV2.Language

program QualifiedUnitType where
  state value : Std.Unit

  view get() : UInt64 do
    return 0
