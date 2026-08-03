import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- N-ANON-RESULT CosmWasm Option return fixture: anonymous Option UInt64
-- = tag + payload leaves (none=(0,0), some v=(1,v)). Query asNone returns
-- {"ok":"[0,0]"}; asSomeOfSeed returns {"ok":"[1,<seed>]"}; execute asSome
-- result attribute "[1,v]". Engineering mock-runtime only; not wasmd / formal.
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

end ProofForgeV2.Examples
