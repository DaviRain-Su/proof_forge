import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEventParam where
  event First(value : UInt64, value : UInt64)
  event Second(other : UInt64, other : UInt64)

  entry ping() : UInt64 do
    return 0
