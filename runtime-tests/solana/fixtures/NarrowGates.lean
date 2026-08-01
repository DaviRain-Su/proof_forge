import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program NarrowGates where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry u8AddOk() : UInt64 do
    let a : UInt8 := 10
    let b : UInt8 := a + 5
    if b > 12 then
      count := count + 1
    return count

  entry u8AddOvf() : UInt64 do
    let c : UInt8 := 250
    let d : UInt8 := c + 10
    if d > 0 then
      count := count + 1
    return count

  entry u16MulOk() : UInt64 do
    let a : UInt16 := 1000
    let b : UInt16 := a * 3
    if b > 2000 then
      count := count + 1
    return count

  entry u32ShlOk() : UInt64 do
    let a : UInt32 := 1
    let b : UInt32 := a << 4
    if b > 10 then
      count := count + 1
    return count

  entry u8BitNotOk() : UInt64 do
    let a : UInt8 := 10
    let b : UInt8 := ~a
    if b > 200 then
      count := count + 1
    return count

  view get() : UInt64 do
    return count

end ProofForgeV2.Examples
