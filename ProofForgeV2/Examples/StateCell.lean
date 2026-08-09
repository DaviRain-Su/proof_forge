import ProofForgeV2.Language.ProgramElaborationV1

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

-- Neutral single-slot state fixture used by compiler and target tests.
program StateCell where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count

/-- Canonical source text for non-CLI library tests. -/
def stateCellSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program StateCell where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

def stateCellModuleNameV1 : String := "Examples.StateCell"

end ProofForgeV2.Examples
