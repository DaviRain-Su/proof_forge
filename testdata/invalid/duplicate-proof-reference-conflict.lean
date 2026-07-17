import ProofForgeV2

open ProofForgeV2.Language

program DuplicateProofReferenceConflict where
  invariant Holds : 1
  proof Holds using Pkg.First
  proof Holds using Pkg.Second

  entry ping() : UInt64 do
    return 0
