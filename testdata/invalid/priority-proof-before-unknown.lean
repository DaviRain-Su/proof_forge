import ProofForgeV2

open ProofForgeV2.Language

program PriorityProofBeforeUnknown where
  invariant Holds : 1
  proof Holds using Pkg.First
  proof Holds using Pkg.Second
  proof Missing using Pkg.Missing

  entry ping() : UInt64 do
    return 0
