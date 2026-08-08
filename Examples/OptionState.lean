import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Option UInt64 state (tag+payload) for Psy local-VM execute differential.
-- Entry is setSome (not set) because Psy Storage derive owns set/get.
-- Use only -- line comments; module-doc openers before program break the parser.
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

end Examples
