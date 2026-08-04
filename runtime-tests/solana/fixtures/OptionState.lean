import ProofForgeV2

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- BL-29 / B-OPT-STATE: anonymous Option UInt64 state = Enum-shaped 2-leaf
-- layout (slot_tag + slot_p0). none = (0, 0); some v = (1, v). none-reset
-- must zero the payload so a prior Some value cannot survive.
program OptionState where
  state slot : Option UInt64

  init() do
    slot := Option.none()

  entry set(v : UInt64) : UInt64 do
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

  view getOpt() : Option UInt64 do
    return slot

end ProofForgeV2.Examples
