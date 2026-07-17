import ProofForgeV2

open ProofForgeV2.Language

program QualifiedBytesType where
  state value : Std.Bytes 32

  view get() : UInt64 do
    return 0
