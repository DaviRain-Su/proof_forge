import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-19 / N-ANON-RESULT Solana ABI: anonymous Array UInt64 2 entry/view return
-- → setReturnDataMulti packs 2×UInt64 leaves into one sol_set_return_data of
-- 16 LE bytes (same wire as named Struct). Layout: slots_0, slots_1.
program ArrayRet where
  state slots : Array UInt64 2

  init(x : UInt64, y : UInt64) do
    slots[0] := x
    slots[1] := y

  entry setArr(x : UInt64, y : UInt64) : Array UInt64 2 do
    slots[0] := x
    slots[1] := y
    return slots

  view getArr() : Array UInt64 2 do
    return slots

end ProofForgeV2.Examples
