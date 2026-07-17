import ProofForgeV2

open ProofForgeV2.Language

program EscapedReservedConstIdentifier where
  const «const» : UInt64 := 1

  entry ping() : UInt64 do
    return 0
