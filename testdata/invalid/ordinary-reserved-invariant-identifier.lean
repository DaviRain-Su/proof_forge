import ProofForgeV2

open ProofForgeV2.Language

program OrdinaryReservedInvariantIdentifier where
  invariant invariant : 1

  entry ping() : UInt64 do
    return 0
