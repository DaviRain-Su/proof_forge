import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-12 / B-RET-ABI: named Enum entry/view return = tag + max-payload slots.
-- Maybe = 2 leaves (tag UInt64 + one payload slot). Layout: m_tag, m_p0.
-- Variant tags are declaration-order indices: None=0, Some=1.
program MaybeRet where
  enum Maybe where
    | None
    | Some(UInt64)

  state m : Maybe

  init() do
    m := Maybe.None()

  entry put(v : UInt64) : Maybe do
    m := Maybe.Some(v)
    return m

  entry clear() : Maybe do
    m := Maybe.None()
    return m

  view peek() : Maybe do
    return m

end ProofForgeV2.Examples
