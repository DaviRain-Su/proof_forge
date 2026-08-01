import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program MultiField where
  state a : UInt64
  state b : UInt64

  init(x : UInt64, y : UInt64) do
    a := x
    b := y

  entry swap(x : UInt64, mode : UInt64) : UInt64 do
    if mode == 0 then
      a := x
    else
      if mode == 1 then
        b := x
      else
        a := x + b
    return a

  view getA() : UInt64 do
    return a

  view getB() : UInt64 do
    return b

end ProofForgeV2.Examples
