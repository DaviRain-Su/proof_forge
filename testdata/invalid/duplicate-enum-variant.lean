import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEnumVariant where
  enum First where
    | Value
    | Value(UInt64)
  enum Second where
    | Other
    | Other

  entry ping() : UInt64 do
    return 0
