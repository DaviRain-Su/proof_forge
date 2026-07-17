import ProofForgeV2

open ProofForgeV2.Language

program UnqualifiedProofTheorem where
  invariant Holds : 1
  proof Holds using Theorem

  entry ping() : UInt64 do
    return 0
