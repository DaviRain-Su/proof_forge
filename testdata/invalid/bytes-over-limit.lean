import ProofForgeV2

open ProofForgeV2.Language

program BytesOverLimit where
  state value : Bytes 4097

  view get() : UInt64 do
    return 0
