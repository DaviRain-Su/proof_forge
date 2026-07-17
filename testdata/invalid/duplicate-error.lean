import ProofForgeV2

open ProofForgeV2.Language

program DuplicateError where
  error Failed
  error Failed()

  entry ping() : UInt64 do
    return 0
