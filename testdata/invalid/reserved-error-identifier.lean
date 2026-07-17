import ProofForgeV2

open ProofForgeV2.Language

program ReservedErrorIdentifier where
  error Failed(error : UInt64)

  entry ping() : UInt64 do
    return 0
