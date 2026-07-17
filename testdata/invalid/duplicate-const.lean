import ProofForgeV2

open ProofForgeV2.Language

program DuplicateConst where
  const Value : UInt64 := 1
  const Value : UInt64 := 2

  entry ping() : UInt64 do
    return 0
