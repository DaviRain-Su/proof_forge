import Tests.Language.ProgramExports
import Tests.Language.ProgramExportAcceptance
import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramCommandAcceptance
import Tests.Language.ProgramSyntax
unsafe def main : IO Unit := do
  Tests.Language.ProgramExports.run
  Tests.Language.ProgramExportAcceptance.run
  Tests.Language.ProgramExportAcceptanceEmpty.run
  Tests.Language.ProgramCommandAcceptance.run
  Tests.Language.ProgramSyntax.run
  IO.println "shard-language: ok"
