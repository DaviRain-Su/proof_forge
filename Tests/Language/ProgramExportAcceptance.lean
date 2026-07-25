import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramExportFixtures.OrderAB
import Tests.Language.ProgramExportFixtures.OrderBA
import Tests.Language.ProgramExportSnapshot
import ProofForgeV2.Language.ProgramExport
import Lean

namespace Tests.Language.ProgramExportAcceptance
open Tests.Language.ProgramExportAcceptanceEmpty
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.QualifiedNameV1
open Lean

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def expectedRows : Array ProgramExportRow := #[
  { schema := "proof-forge.program-export.v2"
    declaration := "Tests.Language.ProgramExportFixtures.A.AProg" },
  { schema := "proof-forge.program-export.v2"
    declaration := "Tests.Language.ProgramExportFixtures.B.BProg" },
  { schema := "proof-forge.program-export.v2"
    declaration := "Tests.Language.ProgramExportFixtures.Shared.SharedProg" }]

/-- TST-SRC-006/007 v2 characterization packaging. -/
unsafe def run : IO Unit := do
  -- empty registry (snapshotted before polluted imports)
  expect (emptyExportCount == 0 && emptyPayloadCount == 0) "empty exports/payloads"
  -- schema constant
  expect (programExportSchemaV2 == "proof-forge.program-export.v2") "exact v2 schema"
  -- exact normalize diagnostics
  match normalizeProgramExports #[{
      schema := "proof-forge.program-export.v1"
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg }] with
  | .ok _ => throw <| IO.userError "v1 schema must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: unknown program export schema") s!"v1 schema: {m}"
  match normalizeProgramExports #[
      { schema := programExportSchemaV2
        declaration := `Tests.Language.ProgramExportFixtures.A.AProg },
      { schema := programExportSchemaV2
        declaration := `Tests.Language.ProgramExportFixtures.A.AProg }] with
  | .ok _ => throw <| IO.userError "structural duplicate must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: duplicate program export declaration") s!"dup: {m}"
  -- Invalid raw declaration components are rejected at the export boundary.
  let invalidDecl := Name.str .anonymous "foo»bar"
  match normalizeProgramExports #[{
      schema := programExportSchemaV2,
      declaration := invalidDecl }] with
  | .ok _ => throw <| IO.userError "invalid declaration component must fail"
  | .error m =>
      expect (m == "PF-EXPORT-001: source name component must not contain closing guillemet")
        s!"invalid decl component: {m}"
  -- AB/BA diamond table
  expect (orderABExports == expectedRows) "OrderAB exact table"
  expect (orderBAExports == expectedRows) "OrderBA exact table"
  expect (orderABExports == orderBAExports) "AB==BA"
  expect (orderABExports.size == 3) "Shared once (size 3)"
  -- Reconstruction of the shared fixture succeeds and identity matches.
  Lean.initSearchPath (← Lean.findSysroot "lean")
  let env ← Lean.importModules
    (imports := #[{ module := `Tests.Language.ProgramExportFixtures.Shared }])
    (opts := {})
    (trustLevel := 0)
  match programPayloadV2 env `Tests.Language.ProgramExportFixtures.Shared.SharedProg with
  | .error m => throw <| IO.userError s!"shared payload reconstruction failed: {m}"
  | .ok source =>
      let identity := (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
      expect (identity == #["Tests", "Language", "ProgramExportFixtures", "Shared", "SharedProg"])
        "v2 payload identity is moduleName ++ declaration raw components"

end Tests.Language.ProgramExportAcceptance
