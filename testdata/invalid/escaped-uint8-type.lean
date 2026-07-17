import ProofForgeV2

open ProofForgeV2.Language

program EscapedUint8Type where
  state value : «UInt8»

  view get() : UInt64 do
    return 0
