import ProofForgeV2

open ProofForgeV2.Language

program ReservedEnumIdentifier where
  enum A where
    | «enum»

  entry ping() : UInt64 do
    return 0
