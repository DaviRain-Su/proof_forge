import ProofForgeV2

open ProofForgeV2.Language

program ReservedProofTheoremComponent where
  invariant Holds : 1
  proof Holds using Pkg.«proof»

  entry ping() : UInt64 do
    return 0
