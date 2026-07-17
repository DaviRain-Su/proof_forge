import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEnum where
  enum A where
    | X
  enum A where
    | Y

  entry ping() : UInt64 do
    return 0
