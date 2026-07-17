import ProofForgeV2

open ProofForgeV2.Language

program PriorityFnParamBeforeEmptyBody where
  fn helper(value : UInt64, value : Bool) : UInt64 do

  entry ping() : UInt64 do
    return 0
