import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program EventFlow where
  state bal : UInt64

  event Moved(src : UInt64, dst : UInt64)
  error Cap(limit : UInt64)

  init(initial : UInt64) do
    bal := initial

  entry move(d : UInt64) : UInt64 do
    emit Moved(bal, d)
    if d > 10 then
      revert Cap(d)
    else
      bal := bal + d
    return bal

  view get() : UInt64 do
    return bal

end ProofForgeV2.Examples
