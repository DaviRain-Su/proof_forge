import ProofForgeV2

open ProofForgeV2.Language

program PriorityEntryBeforeCallable where
  entry helper(value : UInt64) : UInt64 do
    return value
  entry helper(other : UInt64) : UInt64 do
    return other
  fn helper(extra : UInt64) : UInt64 do
    return extra

  entry ping() : UInt64 do
    return 0
