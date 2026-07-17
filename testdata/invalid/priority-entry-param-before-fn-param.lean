import ProofForgeV2

open ProofForgeV2.Language

program PriorityEntryParamBeforeFnParam where
  fn helper(arg : UInt64, arg : Bool) : UInt64 do
    return 0
  entry run(value : UInt64, value : Bool) : UInt64 do
    return 0

  entry ping() : UInt64 do
    return 0
