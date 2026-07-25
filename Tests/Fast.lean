import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1ExternalStatements
import Tests.Language.ProgramV1ControlFlow
import Tests.Language.ProgramV1ExpressionForms
import Tests.Language.ProgramV1UnaryExpressions
import Tests.Language.ProgramV1ArithmeticExpressions
import Tests.Language.ProgramV1ShiftExpressions
import Tests.Language.ProgramV1EqualityExpressions
import Tests.Language.ProgramV1OrderingComparisons
import Tests.Language.ProgramV1BitwiseExpressions
import Tests.Language.ProgramV1CoreStatements
import Tests.Language.ProgramV1RevertEmitStatements
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy

unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Language.ProgramV1Declarations.run
  Tests.Language.ProgramV1ExternalStatements.run
  Tests.Language.ProgramV1ControlFlow.run
  Tests.Language.ProgramV1ExpressionForms.run
  Tests.Language.ProgramV1UnaryExpressions.run
  Tests.Language.ProgramV1ArithmeticExpressions.run
  Tests.Language.ProgramV1ShiftExpressions.run
  Tests.Language.ProgramV1EqualityExpressions.run
  Tests.Language.ProgramV1OrderingComparisons.run
  Tests.Language.ProgramV1BitwiseExpressions.run
  Tests.Language.ProgramV1CoreStatements.run
  Tests.Language.ProgramV1RevertEmitStatements.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  IO.println "proof-forge-next-fast-tests: ok"
