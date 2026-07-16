import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- A second portable business program used to prove that target backends lower
-- semantic structure instead of recognizing the Counter fixture by name/shape.
program Accumulator where
  state total : UInt64

  init(seed : UInt64) do
    total := seed

  entry add(amount : UInt64) : UInt64 do
    total := total + amount
    return total

  view current() : UInt64 do
    return total

def accumulator : ProofForgeV2.Source.Program := Accumulator

end ProofForgeV2.Examples
