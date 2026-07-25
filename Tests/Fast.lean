import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1ExternalStatements
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy

unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Language.ProgramV1Declarations.run
  Tests.Language.ProgramV1ExternalStatements.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  IO.println "proof-forge-next-fast-tests: ok"
