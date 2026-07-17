import ProofForgeV2

open ProofForgeV2.Language

program DuplicateInvariant where
  invariant Holds : 1
  invariant Holds : 2

  entry ping() : UInt64 do
    return 0
