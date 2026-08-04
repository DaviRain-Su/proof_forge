import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Anonymous Array UInt64 2 entry/view return → N×8 LE value_return (N-ANON-RESULT / BL-20).
-- Engineering sandbox fixture only; not formal Reference↔sandbox.
program ArrayRet where
  state slots : Array UInt64 2

  init(a : UInt64, b : UInt64) do
    slots[0] := a
    slots[1] := b

  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do
    slots[0] := a
    slots[1] := b
    return slots

  view getArr() : Array UInt64 2 do
    return slots

end Examples
