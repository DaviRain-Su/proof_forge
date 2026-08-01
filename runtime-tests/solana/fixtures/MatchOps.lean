import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program MatchOps where
  state a : UInt64

  init(initial : UInt64) do
    a := initial

  entry classify(x : UInt64) : UInt64 do
    match x with
    | 0 => do
      a := 1
    | 1 => do
      a := 2
    | _ => do
      a := x + 1
    return a

  view get() : UInt64 do
    return a

end ProofForgeV2.Examples
