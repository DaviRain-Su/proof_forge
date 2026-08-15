import ProofForgeV2.Language.ProgramElaborationV1

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- Neutral Option-state fixture used to exercise aggregate layouts and
-- branch-shaped target recipes through the ordinary compiler pipeline.
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

/-- Canonical OptionState source text for non-CLI library tests. -/
def optionStateSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program OptionState where\n" ++
  "  state slot : Option UInt64\n\n" ++
  "  init() do\n" ++
  "    slot := Option.none()\n\n" ++
  "  entry set(v : UInt64) : UInt64 do\n" ++
  "    slot := Option.some(v)\n" ++
  "    return v\n\n" ++
  "  entry clear() : UInt64 do\n" ++
  "    slot := Option.none()\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    match slot with\n" ++
  "    | Option.some(x) => do\n" ++
  "      return x\n" ++
  "    | _ => do\n" ++
  "      return 0\n\n" ++
  "  view getOpt() : Option UInt64 do\n" ++
  "    return slot\n\n" ++
  "end ProofForgeV2.Examples\n"

def optionStateModuleNameV1 : String := "Examples.OptionState"

end ProofForgeV2.Examples
