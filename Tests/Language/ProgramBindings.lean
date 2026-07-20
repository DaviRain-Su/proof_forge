import Tests.Language.ProgramBindingFixtures.Positive
import Tests.Language.ProgramBindingFixtures.MismatchSingle
import Tests.Language.ProgramBindingFixtures.MismatchTable
import Tests.Language.ProgramBindingFixtures.Priority004
import Tests.Language.ProgramBindingFixtures.Snapshot

namespace Tests.Language.ProgramBindings
open Tests.Language.ProgramBindingFixtures.Positive
open Tests.Language.ProgramBindingFixtures.MismatchSingle
open Tests.Language.ProgramBindingFixtures.MismatchTable
open Tests.Language.ProgramBindingFixtures.Priority004

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def exactBinding : String :=
  "PF-EXPORT-001: exported program identity does not match declaration"

/-- Snapshot constants only; does not call programPayloads on polluted envs. -/
unsafe def run : IO Unit := do
  expect (positiveBindingTable.size ≥ 2) "table has DSL + hand rows"
  for row in positiveBindingTable do
    expect (row.declaration == row.qualifiedName) s!"table align {row.declaration}"
    expect (row.declaration.contains "ProgramBindingFixtures.Positive") "positive ns"
  expect (positiveEscSingle.declaration == positiveEscSingle.qualifiedName)
    "escaped single API align"
  expect (positiveEscSingle.declaration.contains "«ns-1»") "escaped marker in FQN"
  expect (positiveHandSingle.declaration == positiveHandSingle.qualifiedName)
    "hand single API align"
  expect (positiveHandSingle.declaration.endsWith "HandOk") "hand FQN"
  expect (mismatchSingleError == exactBinding) "single programPayload binding"
  expect (mismatchTableError == exactBinding) "table programPayloads binding"
  expect (priority004Error.startsWith "PF-EXPORT-004")
    "decode-all before binding (004 not binding 001)"

end Tests.Language.ProgramBindings
