import ProofForgeV2

open ProofForgeV2.Language

program EscapedInvariantKeyword where
  «invariant» Holds : 1

  entry ping() : UInt64 do
    return 0
