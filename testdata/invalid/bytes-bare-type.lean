import ProofForgeV2

open ProofForgeV2.Language

program BytesBareType where
  state value : Bytes

  view get() : UInt64 do
    return 0
