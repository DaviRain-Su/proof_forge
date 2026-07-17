import ProofForgeV2

open ProofForgeV2.Language

program DuplicateErrorParam where
  error First(value : UInt64, value : UInt64)
  error Second(other : UInt64, other : UInt64)

  entry ping() : UInt64 do
    return 0
