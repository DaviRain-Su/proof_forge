import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- T8b-Solana: UInt8/16/32 state + params on 8-byte slots (no packing).
-- Entry results stay UInt64. Account data is the primary oracle surface.
program NarrowAbi where
  state a : UInt8
  state b : UInt16
  state c : UInt32

  init(x : UInt8, y : UInt16, z : UInt32) do
    a := x
    b := y
    c := z

  entry bump8(delta : UInt8) : UInt64 do
    a := a + delta
    return 0

  entry bump16(delta : UInt16) : UInt64 do
    b := b + delta
    return 0

  entry bump32(delta : UInt32) : UInt64 do
    c := c + delta
    return 0

  view peek() : UInt64 do
    return 0

end ProofForgeV2.Examples
