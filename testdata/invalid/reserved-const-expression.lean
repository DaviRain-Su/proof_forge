import ProofForgeV2

open ProofForgeV2.Language

program ReservedConstExpression where
  const Value : UInt64 := const

  entry ping() : UInt64 do
    return 0
