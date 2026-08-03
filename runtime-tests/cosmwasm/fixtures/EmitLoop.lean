import ProofForgeV2
open ProofForgeV2.Language
program EmitLoop where
  state n : UInt64
  event tick(v : UInt64)
  init() do
    n := 0
  entry loop() : UInt64 do
    for i in (n - n) ..< (n + 40) bounded 64 do
      emit tick(i)
    n := 40
    return n
  view get() : UInt64 do
    return n
