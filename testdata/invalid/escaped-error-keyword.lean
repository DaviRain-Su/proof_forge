import ProofForgeV2

open ProofForgeV2.Language

program EscapedErrorKeyword where
  «error» Failed

  entry ping() : UInt64 do
    return 0
