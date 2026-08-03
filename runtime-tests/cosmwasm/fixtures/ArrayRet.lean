import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- N-ANON-RESULT CosmWasm Array return fixture: anonymous Array UInt64 2
-- flattens to 2×UInt64 leaves. Execute setArr returns result attribute
-- "[a,b]"; query getArr returns {"ok":"[a,b]"} (decimal JSON array string).
-- Engineering mock-runtime only; not wasmd / formal.
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

end ProofForgeV2.Examples
