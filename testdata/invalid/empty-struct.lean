import ProofForgeV2

open ProofForgeV2.Language

program EmptyStruct where
  struct Empty where

  entry ping() : UInt64 do
    return 0
