import ProofForgeV2
open ProofForgeV2.Language
program IntMul where
  state x : Int64
  init() do
    x := 0
  entry armMin() : Int64 do
    let m : Int64 := (0 - 9223372036854775807) - 1
    x := (0 - 1) * m
    return x
  view get() : Int64 do
    return x
