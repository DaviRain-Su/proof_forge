import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program FnCall where
  state count : UInt64

  fn double(x : UInt64) : UInt64 do
    return x + x

  fn absDelta(x : UInt64, y : UInt64) : UInt64 do
    if x > y then
      return x - y
    else
      return y - x

  fn pick(x : UInt64, g : UInt64) : UInt64 do
    if g > 0 then
      return x
    return x + 1

  init(initial : UInt64) do
    count := double(initial)

  entry run(x : UInt64, y : UInt64, g : UInt64) : UInt64 do
    count := double(x)
    count := absDelta(count, y)
    count := pick(count, g)
    return count

  view get() : UInt64 do
    return count

end ProofForgeV2.Examples
