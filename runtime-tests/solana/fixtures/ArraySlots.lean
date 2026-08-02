import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- C-5: Solana ArrayState (Array UInt64 2) → flattened slots_0/slots_1 leaves.
-- Product Plan flattens fixed Array state; Mollusk exercises IndexGet/IndexSet.
program ArraySlots where
  state slots : Array UInt64 2

  init(x : UInt64, y : UInt64) do
    slots[0] := x
    slots[1] := y

  entry set0(v : UInt64) : UInt64 do
    slots[0] := v
    return v

  entry set1(v : UInt64) : UInt64 do
    slots[1] := v
    return v

  view get0() : UInt64 do
    return slots[0]

  view get1() : UInt64 do
    return slots[1]

end ProofForgeV2.Examples
