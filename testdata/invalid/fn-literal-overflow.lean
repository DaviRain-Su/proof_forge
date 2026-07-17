import ProofForgeV2

open ProofForgeV2.Language

program FnLiteralOverflow where
  fn helper(value : UInt64) : UInt64 do
    return 18446744073709551616

  entry ping() : UInt64 do
    return 0
