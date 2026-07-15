import Tests.Core.Semantics
import Tests.Compiler.Pipeline
import Tests.Compiler.Bound
import Tests.Language.ProgramSyntax
import Tests.Language.SourceIdentity
import Tests.Language.Loader
import Tests.Materialization.Targets
import Tests.CLI.Emit

unsafe def main : IO Unit := do
  Tests.Core.run
  Tests.Compiler.run
  Tests.Compiler.Bound.run
  Tests.Language.run
  Tests.Language.SourceIdentity.run
  Tests.Language.Loader.run
  Tests.Materialization.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-tests: ok"
