import ProofForgeV2

open ProofForgeV2.Language

program PriorityEntryParamDeclarationOrder where
  entry first(value : UInt64, value : UInt64) : UInt64 do
    return value

  entry second(other : UInt64, other : UInt64) : UInt64 do
    return other
