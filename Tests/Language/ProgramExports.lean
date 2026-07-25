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
    schema := "proof-forge.program-export.v2"
    declaration := "Tests.Language.ProgramExportFixtures.A.AProg"
  },
  {
    schema := "proof-forge.program-export.v2"
    declaration := "Tests.Language.ProgramExportFixtures.B.BProg"
  },
  {
    schema := "proof-forge.program-export.v2"
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
  let reversed : Array ProgramExportV2 := #[
    {
      schema := programExportSchemaV2
      declaration := `Tests.Language.ProgramExportFixtures.Shared.SharedProg
    },
    {
      schema := programExportSchemaV2
      declaration := `Tests.Language.ProgramExportFixtures.B.BProg
    },
    {
      schema := programExportSchemaV2
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports reversed with
  | .error error =>
      throw <| IO.userError s!"reversed entries must normalize: {error}"
  | .ok table => do
      let decls := table.map fun e => e.declaration.toString
      let expected := expectedRows.map fun row => row.declaration
      expect (decls == expected)
        "reversed raw entries must canonicalize to UTF-8 FQN order"
  let badSchema : Array ProgramExportV2 := #[
    {
      schema := "proof-forge.program-export.v1"
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports badSchema with
  | .ok _ => throw <| IO.userError "v1 schema must not return a table"
  | .error message =>
      expect (message.startsWith "PF-EXPORT-001")
        s!"v1 schema must fail with PF-EXPORT-001, got {message}"
  let duplicate : Array ProgramExportV2 := #[
    {
      schema := programExportSchemaV2
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    },
    {
      schema := programExportSchemaV2
      declaration := `Tests.Language.ProgramExportFixtures.A.AProg
    }
  ]
  match normalizeProgramExports duplicate with
  | .ok _ => throw <| IO.userError "duplicate declaration must not return a table"
  | .error message =>
      expect (message.startsWith "PF-EXPORT-001")
        s!"duplicate declaration must fail with PF-EXPORT-001, got {message}"

end Tests.Language.ProgramExports
