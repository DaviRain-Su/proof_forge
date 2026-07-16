import ProofForgeV2

open ProofForgeV2.Language

program PriorityInitializerParamBeforeEntryParam where
  init(seed : UInt64, seed : UInt64) do

  entry run(value : UInt64, value : UInt64) : UInt64 do
    return value
