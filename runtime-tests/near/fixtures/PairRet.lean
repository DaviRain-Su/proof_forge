import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Named Struct entry/view return → N×8 LE value_return (B-RET-ABI / BL-4).
-- Engineering sandbox fixture only; not formal Reference↔sandbox.
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

end Examples
