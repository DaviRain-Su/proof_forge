import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Option UInt64 state → tag+payload 2×8 LE KV leaves (B-OPT-STATE / BL-30).
-- none default = (0,0); some v = (1,v); clear zeroes payload. Engineering
-- sandbox fixture only; not formal Reference↔sandbox.
program OptionState where
  state slot : Option UInt64

  init() do
    slot := Option.none()

  entry setSome(v : UInt64) : UInt64 do
    slot := Option.some(v)
    return v

  entry clear() : UInt64 do
    slot := Option.none()
    return 0

  view peek() : UInt64 do
    match slot with
    | Option.some(x) => do
      return x
    | _ => do
      return 0

  view getSlot() : Option UInt64 do
    return slot

end Examples
