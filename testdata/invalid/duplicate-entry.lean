import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEntry where
  entry run() : UInt64 do
    return 0

  entry run() : UInt64 do
    return 1
