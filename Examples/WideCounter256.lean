import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

program WideCounter256 where
  state total : UInt256

  init(initial : UInt256) do
    total := initial

  entry add(delta : UInt256) : UInt256 do
    total := total + delta
    return total

  entry subtract(delta : UInt256) : UInt256 do
    total := total - delta
    return total

  entry multiply(factor : UInt256) : UInt256 do
    total := total * factor
    return total

  entry divide(divisor : UInt256) : UInt256 do
    total := total / divisor
    return total

  entry remainder(divisor : UInt256) : UInt256 do
    total := total % divisor
    return total

  entry bitand(mask : UInt256) : UInt256 do
    total := total & mask
    return total

  entry shiftLeft(count : UInt32) : UInt256 do
    total := total << count
    return total

  entry shiftRight(count : UInt32) : UInt256 do
    total := total >> count
    return total

  view get() : UInt256 do
    return total

end Examples
