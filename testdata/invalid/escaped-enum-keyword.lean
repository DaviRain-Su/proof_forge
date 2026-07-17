import ProofForgeV2

open ProofForgeV2.Language

program EscapedEnumKeyword where
  «enum» A where
    | Value

  entry ping() : UInt64 do
    return 0
