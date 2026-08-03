import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program EventFlowTon where
  state bal : UInt64

  event Moved(src : UInt64, dst : UInt64)
  error Cap(limit : UInt64)

  init(initial : UInt64) do
    bal := initial

  entry bump(n : UInt64) : UInt64 do
    emit Moved(bal, n)
    if n > 10 then
      revert Cap(n)
    else
      bal := bal + n
    return bal

  view get() : UInt64 do
    return bal

end ProofForgeV2.Examples
