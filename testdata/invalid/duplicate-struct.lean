import ProofForgeV2

open ProofForgeV2.Language

program DuplicateStruct where
  struct A where
    value : UInt64
  struct A where
    other : Bool

  entry ping() : UInt64 do
    return 0
