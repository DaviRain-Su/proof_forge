import ProofForgeV2

open ProofForgeV2.Language

program DuplicateProofReference where
  invariant Holds : 1
  proof Holds using Pkg.Theorem
  proof Holds using Pkg.Theorem

  entry ping() : UInt64 do
    return 0
