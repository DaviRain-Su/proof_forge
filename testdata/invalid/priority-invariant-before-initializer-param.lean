import ProofForgeV2

open ProofForgeV2.Language

program PriorityInvariantBeforeInitializerParam where
  invariant Holds : 1
  invariant Holds : 2
  init(value : UInt64, value : Bool) do
    return 0

  entry ping() : UInt64 do
    return 0
