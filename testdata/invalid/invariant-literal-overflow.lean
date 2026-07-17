import ProofForgeV2

open ProofForgeV2.Language

program InvariantLiteralOverflow where
  invariant Holds : 18446744073709551616

  entry ping() : UInt64 do
    return 0
