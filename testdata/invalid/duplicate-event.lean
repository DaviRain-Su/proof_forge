import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEvent where
  event Changed()
  event Changed()

  entry ping() : UInt64 do
    return 0
