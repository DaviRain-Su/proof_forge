import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEntryParam where
  entry run(value : UInt64, value : UInt64) : UInt64 do
    return value
