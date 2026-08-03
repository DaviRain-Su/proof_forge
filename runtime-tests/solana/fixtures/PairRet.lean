import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-12 / B-RET-ABI: named Struct entry/view return → setReturnDataMulti
-- packs 2×UInt64 leaves into one sol_set_return_data of 16 LE bytes.
-- Layout leaves: p_a, p_b (shared source_id 0, preorder field order).
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
