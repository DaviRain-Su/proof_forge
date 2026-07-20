import Tests.Language.ProgramIdentityFixtures.Positive
import Tests.Language.ProgramIdentityFixtures.Duplicate
import Tests.Language.ProgramIdentityFixtures.Conflict
import Tests.Language.ProgramIdentityFixtures.Priority
import Tests.Language.ProgramIdentityFixtures.Snapshot

namespace Tests.Language.ProgramIdentities
open Tests.Language.ProgramIdentityFixtures.Positive
open Tests.Language.ProgramIdentityFixtures.Duplicate
open Tests.Language.ProgramIdentityFixtures.Conflict
open Tests.Language.ProgramIdentityFixtures.Priority

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

unsafe def run : IO Unit := do
  expect (positiveIdentityRows.size == 2) "two positive rows"
  let some r0 := positiveIdentityRows[0]? | throw <| IO.userError "row0"
  let some r1 := positiveIdentityRows[1]? | throw <| IO.userError "row1"
  expect (r0.declaration < r1.declaration) "PA81 FQN order"
  expect (r0.declaration.endsWith "Alpha" && r1.declaration.endsWith "Beta") "FQNs"
  expect (r0.qualifiedName != r1.qualifiedName) "distinct qnames"
  expect (r0.sourceHash != r1.sourceHash) "distinct hashes"
  expect (r0.qualifiedName == Alpha.qualifiedName &&
    r1.qualifiedName == Beta.qualifiedName) "qname match"
  expect (r0.sourceHash == Alpha.sourceHash && r1.sourceHash == Beta.sourceHash)
    "hash match"
  expect (DupA.qualifiedName == DupB.qualifiedName &&
    DupA.sourceHash == DupB.sourceHash) "duplicate fixture identity"
  expect (ConA.qualifiedName == ConB.qualifiedName &&
    ConA.sourceHash != ConB.sourceHash) "conflict fixture identity"
  expect (duplicateIdentityError ==
    "PF-EXPORT-001: duplicate exported program identity") "dup exact"
  expect (conflictIdentityError ==
    "PF-EXPORT-001: conflicting exported program identity") "conflict exact"
  expect (priorityDecodeError.startsWith "PF-EXPORT-004") "decode-before-identity"

end Tests.Language.ProgramIdentities
