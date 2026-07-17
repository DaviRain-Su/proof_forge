import ProofForgeV2

open ProofForgeV2.Language

program ReservedEventIdentifier where
  event event()

  entry ping() : UInt64 do
    return 0
