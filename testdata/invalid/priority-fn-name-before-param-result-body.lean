import ProofForgeV2

open ProofForgeV2.Language

program PriorityFnNameBeforeParamResultBody where
  fn const(fn : UInt64) : Unknown do
    return 18446744073709551616

  entry ping() : UInt64 do
    return 0
