import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.Semantics
import Tests.Compiler.Pipeline
import Tests.Compiler.TypedNameIndex
import Tests.Language.ProgramSyntax
import Tests.Language.FrontendParity
import Tests.Language.Loader
import Tests.Materialization.Targets
import Tests.Materialization.NearHostModel
import Tests.Materialization.NoirRelationModel
import Tests.CLI.Emit

unsafe def main : IO Unit := do
  Tests.Core.Common.run
  Tests.Core.CommonRemaining.run
  Tests.Core.CommonScalars.run
  Tests.Core.Unicode.run
  Tests.Core.run
  Tests.Compiler.run
  Tests.Compiler.TypedNameIndex.run
  Tests.Language.run
  Tests.Language.FrontendParity.run
  Tests.Language.Loader.run
  Tests.Materialization.run
  Tests.Materialization.NearHostModel.run
  Tests.Materialization.NoirRelationModel.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-tests: ok"
