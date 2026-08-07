import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

program WideCounter where
  state total : UInt128

  init(initial : UInt128) do
    total := initial

  entry add(delta : UInt128) : UInt128 do
    total := total + delta
    return total

  entry subtract(delta : UInt128) : UInt128 do
    total := total - delta
    return total

  entry multiply(factor : UInt128) : UInt128 do
    total := total * factor
    return total

  entry divide(divisor : UInt128) : UInt128 do
    total := total / divisor
    return total

  entry remainder(divisor : UInt128) : UInt128 do
    total := total % divisor
    return total

  view leq(bound : UInt128) : Bool do
    return total <= bound

  view get() : UInt128 do
    return total

end Examples
