import ProofForgeV2

open ProofForgeV2.Language

program EscapedReservedInvariantIdentifier where
  invariant «invariant» : 1

  entry ping() : UInt64 do
    return 0
