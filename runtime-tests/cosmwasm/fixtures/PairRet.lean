import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- B-RET-ABI CosmWasm Pair return fixture: named Struct flattens to 2×UInt64
-- leaves. Execute setPair returns result attribute "[x,y]"; query getPair
-- returns {"ok":"[x,y]"} (decimal JSON array string, matching scalar decimal
-- idiom). Not wasmd / formal.
program PairRet where
  struct Pair where
    a : UInt64
    b : UInt64

  state p : Pair

  init(x : UInt64, y : UInt64) do
    p := Pair.new(x, y)

  entry setPair(x : UInt64, y : UInt64) : Pair do
    p := Pair.new(x, y)
    return p

  view getPair() : Pair do
    return p

end ProofForgeV2.Examples
