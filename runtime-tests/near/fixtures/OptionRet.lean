import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Anonymous Option UInt64 entry/view return → tag+payload 2×8 LE (N-ANON-RESULT / BL-20).
-- none = (0,0), some v = (1,v). Engineering sandbox fixture only; not formal.
program OptionRet where
  state seed : UInt64

  init(x : UInt64) do
    seed := x

  entry asSome(v : UInt64) : Option UInt64 do
    return Option.some(v)

  view asNone() : Option UInt64 do
    return Option.none()

  view asSomeOfSeed() : Option UInt64 do
    return Option.some(seed)

end Examples
