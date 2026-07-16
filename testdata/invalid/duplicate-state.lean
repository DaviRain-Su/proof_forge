import ProofForgeV2

open ProofForgeV2.Language

program DuplicateState where
  state value : UInt64
  state value : UInt64

  view get() : UInt64 do
    return value
