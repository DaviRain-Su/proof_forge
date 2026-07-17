import ProofForgeV2

open ProofForgeV2.Language

program EscapedStructKeyword where
  «struct» A where
    value : UInt64

  entry ping() : UInt64 do
    return 0
