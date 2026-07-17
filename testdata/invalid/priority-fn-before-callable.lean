import ProofForgeV2

open ProofForgeV2.Language

program PriorityFnBeforeCallable where
  entry helper(value : UInt64) : UInt64 do
    return value
  fn helper(first : UInt64) : UInt64 do
    return first
  fn helper(second : UInt64) : UInt64 do
    return second

  entry ping() : UInt64 do
    return 0
