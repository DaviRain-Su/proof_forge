import ProofForgeV2

open ProofForgeV2.Language

program PriorityConstTypeBeforeValue where
  const Value : Unknown := 18446744073709551616

  entry ping() : UInt64 do
    return 0
