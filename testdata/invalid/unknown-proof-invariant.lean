import ProofForgeV2

open ProofForgeV2.Language

program UnknownProofInvariant where
  proof Missing using Pkg.Theorem

  entry ping() : UInt64 do
    return 0
