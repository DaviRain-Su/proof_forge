import ProofForgeV2

open ProofForgeV2.Language

program ConstLiteralOverflow where
  const Value : UInt64 := 18446744073709551616

  entry ping() : UInt64 do
    return 0
