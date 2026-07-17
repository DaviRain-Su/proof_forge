import ProofForgeV2

open ProofForgeV2.Language

program EscapedProofKeyword where
  invariant Holds : 1
  «proof» Holds using Pkg.Theorem

  entry ping() : UInt64 do
    return 0
