import ProofForgeV2
namespace Examples
open ProofForgeV2.Language

-- Body-only UInt128 multiword shift probe (T9e).
-- ABI surface stays UInt64/UInt32 params; UInt128 lives only in lets.
-- Pins that Plan admits `<<` / `>>` on UInt128 (Emit multiword path).
-- CosmWasm + NEAR (near-sandbox WideShiftProbe suite).
program WideShiftProbe where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  entry shiftOneLeft(count : UInt32) : UInt64 do
    let x : UInt128 := 1
    let y : UInt128 := x << count
    assert y > 0
    pad := pad + 1
    return pad

  entry shiftOneRight(count : UInt32) : UInt64 do
    let x : UInt128 := 1024
    let y : UInt128 := x >> count
    assert y > 0 || count >= 10
    pad := pad + 1
    return pad

  -- Overflow pin: 1 << 127 ok; 1 << 128 traps at count≥bitWidth.
  entry shiftMaxBit() : UInt64 do
    let x : UInt128 := 1
    let c : UInt32 := 127
    let y : UInt128 := x << c
    assert y > 0
    pad := pad + 1
    return pad

  view get() : UInt64 do
    return pad
end Examples
