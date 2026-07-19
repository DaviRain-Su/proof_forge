import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramExportFixtures.OrderAB
import Tests.Language.ProgramExportFixtures.OrderBA
import Tests.Language.ProgramExportSnapshot
import Tests.Language.ProgramIdentityFixtures.Duplicate
import Tests.Language.ProgramIdentityFixtures.Conflict
import Tests.Language.ProgramIdentityFixtures.Priority
import Tests.Language.ProgramBindingFixtures.MismatchSingle
import Tests.Language.ProgramBindingFixtures.Priority004
import Tests.Language.ProgramShortNameFixtures.Mismatch
import Tests.Language.ProgramShortNameFixtures.Priority004
import ProofForgeV2.Language.ProgramExport
import Lean

namespace Tests.Language.ProgramExportAcceptance
open Tests.Language.ProgramExportAcceptanceEmpty
open ProofForgeV2.Language.ProgramExport
open Lean

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def expectedRows : Array ProgramExportRow := #[
  { schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.A.AProg" },
  { schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.B.BProg" },
  { schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.Shared.SharedProg" }]

/-- TST-SRC-006/007 characterization packaging; consumes empty snapshot + isolated fixtures only. -/
unsafe def run : IO Unit := do
  -- empty registry (snapshotted before polluted imports)
  expect (emptyExportCount == 0 && emptyPayloadCount == 0) "empty exports/payloads"
  -- schema constant
  expect (programExportSchemaV1 == "proof-forge.program-export.v1") "exact schema"
  -- exact normalize diagnostics
  match normalizeProgramExports #[{
      schema := "proof-forge.program-export.v0"
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg }] with
  | .ok _ => throw <| IO.userError "unknown schema must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: unknown program export schema") s!"unknown: {m}"
  match normalizeProgramExports #[
      { schema := programExportSchemaV1
        declaration := `Tests.Language.ProgramExportFixtures.A.AProg },
      { schema := programExportSchemaV1
        declaration := `Tests.Language.ProgramExportFixtures.A.AProg }] with
  | .ok _ => throw <| IO.userError "structural duplicate must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: duplicate program export declaration") s!"dup: {m}"
  let nDot := Name.str .anonymous "foo.bar"
  let nEsc := Name.str .anonymous "«foo.bar»"
  expect (nDot != nEsc) "rendered-conflict Names must be non-BEq"
  expect (nDot.toString == nEsc.toString) "rendered-conflict Names same toString"
  match normalizeProgramExports #[
      { schema := programExportSchemaV1, declaration := nDot },
      { schema := programExportSchemaV1, declaration := nEsc }] with
  | .ok _ => throw <| IO.userError "rendered-name conflict must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: conflicting program export name") s!"render: {m}"
  -- AB/BA diamond table
  expect (orderABExports == expectedRows) "OrderAB exact table"
  expect (orderBAExports == expectedRows) "OrderBA exact table"
  expect (orderABExports == orderBAExports) "AB==BA"
  expect (orderABExports.size == 3) "Shared once (size 3)"
  expect (orderABExports.all fun r =>
      r.declaration != "Tests.Language.ProgramExportFixtures.A.sharedManualAlias")
    "unattributed alias absent"
  -- cross-row identities
  expect (Tests.Language.ProgramIdentityFixtures.Duplicate.duplicateIdentityError ==
    "PF-EXPORT-001: duplicate exported program identity") "dup identity"
  expect (Tests.Language.ProgramIdentityFixtures.Conflict.conflictIdentityError ==
    "PF-EXPORT-001: conflicting exported program identity") "conflict identity"
  -- 004 priorities: decode before identity / binding / short-name
  expect (Tests.Language.ProgramIdentityFixtures.Priority.priorityDecodeError.startsWith
    "PF-EXPORT-004") "004 before identity"
  expect (Tests.Language.ProgramBindingFixtures.Priority004.priority004Error.startsWith
    "PF-EXPORT-004") "004 before binding"
  expect (Tests.Language.ProgramShortNameFixtures.Priority004.shortPriority004Error.startsWith
    "PF-EXPORT-004") "004 before short-name"
  -- PA84 qname before PA85 short-name (dual-liar yields identity diagnostic)
  expect (Tests.Language.ProgramBindingFixtures.MismatchSingle.mismatchSingleError ==
    "PF-EXPORT-001: exported program identity does not match declaration")
    "qname-before-short (PA84)"
  expect (Tests.Language.ProgramShortNameFixtures.Mismatch.shortMismatchSingleError ==
    "PF-EXPORT-001: exported program short name does not match declaration")
    "short-name exact (PA85)"
  expect (Tests.Language.ProgramShortNameFixtures.Mismatch.shortMismatchTableError ==
    "PF-EXPORT-001: exported program short name does not match declaration")
    "short-name table exact"

end Tests.Language.ProgramExportAcceptance
