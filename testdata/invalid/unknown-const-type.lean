import ProofForgeV2

open ProofForgeV2.Language

program UnknownConstType where
  const Value : Unknown := 1

  entry ping() : UInt64 do
    return 0
