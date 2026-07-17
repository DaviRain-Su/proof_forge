import ProofForgeV2

open ProofForgeV2.Language

program DuplicateFn where
  fn helper(value : UInt64) : UInt64 do
    return value
  fn helper(other : UInt64) : UInt64 do
    return other

  entry ping() : UInt64 do
    return 0
