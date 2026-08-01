import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program LoopSum where
  state acc : UInt64

  init(initial : UInt64) do
    acc := initial

  entry sum(n : UInt64) : UInt64 do
    for i in (n - n) ..< n bounded 64 do
      acc := acc + i
    return acc

  view get() : UInt64 do
    return acc

end ProofForgeV2.Examples
