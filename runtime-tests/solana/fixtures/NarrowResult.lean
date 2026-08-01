import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- T9a-Solana: entry/view return UInt8/16/32 (set_return_data lengths 1/2/4).
program NarrowResult where
  state count : UInt64

  init(i : UInt64) do
    count := i

  entry get8(x : UInt8) : UInt8 do
    return x

  entry get16(x : UInt16) : UInt16 do
    return x

  entry get32(x : UInt32) : UInt32 do
    return x

  view peek() : UInt64 do
    return count

end ProofForgeV2.Examples
