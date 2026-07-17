import ProofForgeV2

open ProofForgeV2.Language

program PriorityConstBeforeInitializerParam where
  const Value : UInt64 := 1
  const Value : UInt64 := 2
  init(value : UInt64, value : UInt64) do
    return 0

  entry ping() : UInt64 do
    return 0
