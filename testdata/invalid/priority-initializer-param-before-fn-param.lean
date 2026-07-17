import ProofForgeV2

open ProofForgeV2.Language

program PriorityInitializerParamBeforeFnParam where
  init(value : UInt64, value : Bool) do
    return 0
  fn helper(arg : UInt64, arg : Bool) : UInt64 do
    return 0

  entry ping() : UInt64 do
    return 0
