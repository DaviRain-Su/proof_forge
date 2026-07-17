import ProofForgeV2

open ProofForgeV2.Language

program OrdinaryReservedStructIdentifier where
  struct struct where
    value : UInt64

  entry ping() : UInt64 do
    return 0
