import ProofForgeV2

open ProofForgeV2.Language

program PriorityFnResultBeforeBody where
  fn helper(value : UInt64) : Unknown do
    return 18446744073709551616

  entry ping() : UInt64 do
    return 0
