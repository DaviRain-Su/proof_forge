import ProofForgeV2

open ProofForgeV2.Language

program DuplicateStructField where
  struct First where
    value : UInt64
    value : Bool
  struct Second where
    other : UInt64
    other : Bool

  entry ping() : UInt64 do
    return 0
