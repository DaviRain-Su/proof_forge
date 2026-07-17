import ProofForgeV2

open ProofForgeV2.Language

program PriorityUnknownBeforeInitializerParam where
  proof Missing using Pkg.Missing
  init(value : UInt64, value : Bool) do
    return 0

  entry ping() : UInt64 do
    return 0
