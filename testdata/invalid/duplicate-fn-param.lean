import ProofForgeV2

open ProofForgeV2.Language

program DuplicateFnParam where
  fn first(value : UInt64, value : Bool) : UInt64 do
    return 0
  fn second(other : UInt64, other : Bool) : UInt64 do
    return 0

  entry ping() : UInt64 do
    return 0
