import ProofForgeV2

open ProofForgeV2.Language

program UnknownFnResult where
  fn helper(value : UInt64) : Unknown do
    return value

  entry ping() : UInt64 do
    return 0
