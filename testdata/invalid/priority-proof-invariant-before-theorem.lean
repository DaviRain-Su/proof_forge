import ProofForgeV2

open ProofForgeV2.Language

program PriorityProofInvariantBeforeTheorem where
  proof proof using «Pkg.Invalid.Theorem»

  entry ping() : UInt64 do
    return 0
