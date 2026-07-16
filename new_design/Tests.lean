import Tests.Core.Semantics
import Tests.Compiler.Pipeline
import Tests.Language.ProgramSyntax
import Tests.Language.Loader
import Tests.Materialization.Targets
import Tests.Materialization.NearHostModel
import Tests.CLI.Emit

unsafe def main : IO Unit := do
  Tests.Core.run
  Tests.Compiler.run
  Tests.Language.run
  Tests.Language.Loader.run
  Tests.Materialization.run
  Tests.Materialization.NearHostModel.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-tests: ok"
