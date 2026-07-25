import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy

unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  IO.println "proof-forge-next-fast-tests: ok"
