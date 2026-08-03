import ProofForgeV2

open ProofForgeV2.Language

-- Engineering emit/revert fixture for EVM Anvil differential / corpus
-- (pf.primitive.eventflow.emit-cap.v1). log1 Moved(src,dst); Cap revert arm.
-- Committed under testdata/evm-corpus/v1/programs/ — not generated under build/.
program EventFlow where
  state count : UInt64

  event Moved(src : UInt64, dst : UInt64)
  error Cap(limit : UInt64)

  init(initial : UInt64) do
    count := initial

  entry bump(delta : UInt64) : UInt64 do
    emit Moved(count, delta)
    if count > delta then
      revert Cap(delta)
    else
      count := count + delta
    return count

  view get() : UInt64 do
    return count
