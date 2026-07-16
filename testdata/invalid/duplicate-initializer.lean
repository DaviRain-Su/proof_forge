import ProofForgeV2

open ProofForgeV2.Language

program DuplicateInitializer where
  init() do
  init() do

  view get() : UInt64 do
    return 0
