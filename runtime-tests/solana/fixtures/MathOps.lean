import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program MathOps where
  state slot : UInt64

  init(initial : UInt64) do
    slot := initial

  entry run(x : UInt64, y : UInt64) : UInt64 do
    let m := x * 3
    let d := x / y
    let r := x % y
    let sl := x << 2
    let sr := x >> 1
    let a := x & 255
    let o := x | 1
    let xr := x ^ 3
    let bn := ~x
    let t0 := m ^ d
    let t1 := t0 ^ r
    let t2 := t1 ^ sl
    let t3 := t2 ^ sr
    let t4 := t3 ^ a
    let t5 := t4 ^ o
    let t6 := t5 ^ xr
    slot := t6 ^ bn
    return slot

  entry div(x : UInt64, y : UInt64) : UInt64 do
    return x / y

  entry mulhuge(a : UInt64, b : UInt64) : UInt64 do
    return a * b

  entry badShift(x : UInt64) : UInt64 do
    return x << (32 + 32)

  entry shlOne(x : UInt64) : UInt64 do
    return x << 1

  entry guarded(x : UInt64) : UInt64 do
    assert x > 0
    return x

  view get() : UInt64 do
    return slot

end ProofForgeV2.Examples
