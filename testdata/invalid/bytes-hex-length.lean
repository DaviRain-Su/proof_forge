import ProofForgeV2

open ProofForgeV2.Language

program BytesHexLength where
  state value : Bytes 0x20

  view get() : UInt64 do
    return 0
