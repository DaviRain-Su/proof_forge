import ProofForgeV2

open ProofForgeV2.Language

program OrdinaryReservedEnumIdentifier where
  enum enum where
    | Value

  entry ping() : UInt64 do
    return 0
