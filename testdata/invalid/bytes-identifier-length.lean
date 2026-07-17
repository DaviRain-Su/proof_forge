import ProofForgeV2

open ProofForgeV2.Language

program BytesIdentifierLength where
  state value : Bytes Foo

  view get() : UInt64 do
    return 0
