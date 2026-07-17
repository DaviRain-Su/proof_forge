import ProofForgeV2

open ProofForgeV2.Language

program EscapedFnKeyword where
  «fn» helper(value : UInt64) : UInt64 do
    return value

  entry ping() : UInt64 do
    return 0
