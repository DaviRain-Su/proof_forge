import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-15 CosmWasm multi-width fixture: UInt8 state cell with checked overflow trap.
-- Runtime pins init/increment/get plus UInt8 overflow and out-of-range JSON
-- param reject. Physical KV is 8-byte LE with high bytes zero.
program NarrowStateCell where
  state count : UInt8

  init(initial : UInt8) do
    count := initial

  entry increment(delta : UInt8) : UInt8 do
    count := count + delta
    return count

  view get() : UInt8 do
    return count

end ProofForgeV2.Examples
