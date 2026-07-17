import ProofForgeV2

open ProofForgeV2.Language

program PriorityEnumBeforeConst where
  enum Choice where
    | A
  enum Choice where
    | B
  const Value : UInt64 := 1
  const Value : UInt64 := 2

  entry ping() : UInt64 do
    return 0
