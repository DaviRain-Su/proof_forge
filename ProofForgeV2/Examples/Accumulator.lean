import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program Accumulator where
  state total : UInt64

  init(seed : UInt64) do
    total := seed

  entry add(amount : UInt64) : UInt64 do
    total := total + amount
    return total

  view current() : UInt64 do
    return total

end ProofForgeV2.Examples
