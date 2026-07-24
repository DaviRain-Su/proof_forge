import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit

unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  IO.println "proof-forge-next-fast-tests: ok"
