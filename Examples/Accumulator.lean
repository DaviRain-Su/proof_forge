import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

program Accumulator where
  state total : UInt64

  init(seed : UInt64) do
    total := seed

  -- Portable entry name. Aleo Instructions rejects opcode-reserved identifiers
  -- (`add`) at official load — target fails closed rather than silently renaming.
  entry add(amount : UInt64) : UInt64 do
    total := total + amount
    return total

  view current() : UInt64 do
    return total

end Examples
