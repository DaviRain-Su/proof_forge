import Tests.Language.ProgramExportFixtures.OrderAB
import Tests.Language.ProgramExportFixtures.OrderBA
import Tests.Language.ProgramExportSnapshot
import ProofForgeV2.Language.ProgramExport

namespace Tests.Language.ProgramExports

open ProofForgeV2.Language.ProgramExport

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectedRows : Array ProgramExportRow := #[
  {
    schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.A.AProg"
  },
  {
    schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.B.BProg"
  },
  {
    schema := "proof-forge.program-export.v1"
    declaration := "Tests.Language.ProgramExportFixtures.Shared.SharedProg"
  }
]

unsafe def run : IO Unit := do
  expect (orderABExports == expectedRows)
    "OrderAB snapshot must match expected three-row schema/FQN table"
  expect (orderBAExports == expectedRows)
    "OrderBA snapshot must match expected three-row schema/FQN table"
  expect (orderABExports == orderBAExports)
    "AB and BA import orders must yield identical export tables"
  expect (orderABExports.size == 3)
    "diamond fixture must export exactly three programs"
  expect (orderABExports.all fun row =>
      row.declaration != "Tests.Language.ProgramExportFixtures.A.sharedManualAlias")
    "manual unattributed Source.Program alias must be absent"
  let reversed : Array ProgramExportV1 := #[
    {
      schema := programExportSchemaV1
      declaration := `Tests.Language.ProgramExportFixtures.Shared.SharedProg
    },
    {
      schema := programExportSchemaV1
      declaration := `Tests.Language.ProgramExportFixtures.B.BProg
    },
    {
      schema := programExportSchemaV1
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports reversed with
  | .error error =>
      throw <| IO.userError s!"reversed entries must normalize: {error}"
  | .ok table =>
      let decls := table.map fun entry => entry.declaration.toString
      let expected := expectedRows.map fun row => row.declaration
      expect (decls == expected)
        "reversed raw entries must canonicalize to UTF-8 FQN order"
  let badSchema : Array ProgramExportV1 := #[
    {
      schema := "proof-forge.program-export.v0"
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports badSchema with
  | .ok _ => throw <| IO.userError "wrong schema must not return a table"
  | .error message =>
      expect (message.startsWith "PF-EXPORT-001")
        s!"wrong schema must fail with PF-EXPORT-001, got {message}"
  let duplicate : Array ProgramExportV1 := #[
    {
      schema := programExportSchemaV1
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    },
    {
      schema := programExportSchemaV1
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports duplicate with
  | .ok _ => throw <| IO.userError "duplicate declaration must not return a table"
  | .error message =>
      expect (message.startsWith "PF-EXPORT-001")
        s!"duplicate declaration must fail with PF-EXPORT-001, got {message}"

end Tests.Language.ProgramExports
