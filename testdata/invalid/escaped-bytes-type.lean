import ProofForgeV2

open ProofForgeV2.Language

program EscapedBytesType where
  state value : «Bytes» 32

  view get() : UInt64 do
    return 0
