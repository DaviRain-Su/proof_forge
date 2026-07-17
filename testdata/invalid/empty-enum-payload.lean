import ProofForgeV2

open ProofForgeV2.Language

program EmptyEnumPayload where
  enum A where
    | Empty()

  entry ping() : UInt64 do
    return 0
