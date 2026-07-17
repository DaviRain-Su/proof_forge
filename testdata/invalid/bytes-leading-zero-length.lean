import ProofForgeV2

open ProofForgeV2.Language

program BytesLeadingZeroLength where
  state value : Bytes 007

  view get() : UInt64 do
    return 0
