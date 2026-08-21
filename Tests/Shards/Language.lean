import Tests.Shards.Runner
import Tests.Language.ProgramExports
import Tests.Language.ProgramExportAcceptance
import Tests.Language.ProgramExportAcceptanceEmpty
import Tests.Language.ProgramCommandAcceptance
import Tests.Language.ProgramSyntax

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.ProgramExports" Tests.Language.ProgramExports.run
  runSuite "Tests.Language.ProgramExportAcceptance" Tests.Language.ProgramExportAcceptance.run
  runSuite "Tests.Language.ProgramExportAcceptanceEmpty"
    Tests.Language.ProgramExportAcceptanceEmpty.run
  runSuite "Tests.Language.ProgramCommandAcceptance" Tests.Language.ProgramCommandAcceptance.run
  runSuite "Tests.Language.ProgramSyntax" Tests.Language.ProgramSyntax.run
  IO.println "shard-language: ok"
