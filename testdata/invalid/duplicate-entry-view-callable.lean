import ProofForgeV2

open ProofForgeV2.Language

program DuplicateEntryViewCallable where
  entry helper(value : UInt64) : UInt64 do
    return value
  view helper(other : UInt64) : UInt64 do
    return other
