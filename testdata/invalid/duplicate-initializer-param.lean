import ProofForgeV2

open ProofForgeV2.Language

program DuplicateInitializerParam where
  state value : UInt64

  init(seed : UInt64, seed : UInt64) do
    value := seed

  view get() : UInt64 do
    return value
