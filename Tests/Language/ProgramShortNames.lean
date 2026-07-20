import Tests.Language.ProgramShortNameFixtures.Positive
import Tests.Language.ProgramShortNameFixtures.Mismatch
import Tests.Language.ProgramShortNameFixtures.Priority004

namespace Tests.Language.ProgramShortNames
open Tests.Language.ProgramShortNameFixtures.Positive
open Tests.Language.ProgramShortNameFixtures.Mismatch
open Tests.Language.ProgramShortNameFixtures.Priority004

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def exactShort :=
  "PF-EXPORT-001: exported program short name does not match declaration"

unsafe def run : IO Unit := do
  expect (positiveShortTable.size ≥ 4) "simple+hyphen+dot+hand"
  expect (positiveSimpleSingle.payloadName == "simple") "simple"
  expect (positiveHyphenSingle.payloadName == "«hyphen-prog»") "hyphen"
  expect (positiveDotSingle.payloadName == "«dot.prog»") "dot"
  expect (positiveHandSingle.payloadName == "HandOk") "hand"
  expect (shortMismatchSingleError == exactShort) "single"
  expect (shortMismatchTableError == exactShort) "table"
  expect (shortPriority004Error.startsWith "PF-EXPORT-004") "004 priority"
end Tests.Language.ProgramShortNames
