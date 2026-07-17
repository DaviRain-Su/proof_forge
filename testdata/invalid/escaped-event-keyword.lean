import ProofForgeV2

open ProofForgeV2.Language

program EscapedEventKeyword where
  «event» Changed()

  entry ping() : UInt64 do
    return 0
