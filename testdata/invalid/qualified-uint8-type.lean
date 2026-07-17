import ProofForgeV2

open ProofForgeV2.Language

program QualifiedUint8Type where
  state value : Std.UInt8

  view get() : UInt64 do
    return 0
