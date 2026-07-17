import ProofForgeV2

open ProofForgeV2.Language

program PriorityFnBeforeInitializerParam where
  fn helper(value : UInt64) : UInt64 do
    return value
  fn helper(other : UInt64) : UInt64 do
    return other
  init(value : UInt64, value : Bool) do
    return 0

  entry ping() : UInt64 do
    return 0
