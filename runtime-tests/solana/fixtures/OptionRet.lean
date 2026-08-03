import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-19 / N-ANON-RESULT Solana ABI: anonymous Option UInt64 entry/view return
-- = tag + payload (2×UInt64 leaves). none = (0, 0); some v = (1, v).
-- State is a scalar pad only (Option state remains fail-closed).
program OptionRet where
  state pad : UInt64

  init() do
    pad := 0

  entry putSome(v : UInt64) : Option UInt64 do
    pad := v
    return Option.some(v)

  entry putNone() : Option UInt64 do
    pad := 0
    return Option.none()

  view peekSome() : Option UInt64 do
    return Option.some(pad)

  view peekNone() : Option UInt64 do
    return Option.none()

end ProofForgeV2.Examples
