import ProofForgeV2

open ProofForgeV2.Language

program PriorityCallableBeforeInvariant where
  entry helper(value : UInt64) : UInt64 do
    return value
  fn helper(other : UInt64) : UInt64 do
    return other
  invariant Holds : 1
  invariant Holds : 2

  entry ping() : UInt64 do
    return 0
