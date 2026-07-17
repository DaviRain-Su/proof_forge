import ProofForgeV2

open ProofForgeV2.Language

program EscapedConstKeyword where
  «const» Value : UInt64 := 1

  entry ping() : UInt64 do
    return 0
