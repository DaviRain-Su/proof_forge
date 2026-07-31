import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1DeclarationNegatives
import Tests.Language.ProgramV1ExternalStatements
import Tests.Language.ProgramV1ControlFlow
import Tests.Language.ProgramV1ExpressionForms
import Tests.Language.ProgramV1UnaryExpressions
import Tests.Language.ProgramV1ArithmeticExpressions
import Tests.Language.ProgramV1ShiftExpressions
unsafe def main : IO Unit := do
  Tests.Language.ProgramV1Declarations.run
  Tests.Language.ProgramV1DeclarationNegatives.run
  Tests.Language.ProgramV1ExternalStatements.run
  Tests.Language.ProgramV1ControlFlow.run
  Tests.Language.ProgramV1ExpressionForms.run
  Tests.Language.ProgramV1UnaryExpressions.run
  Tests.Language.ProgramV1ArithmeticExpressions.run
  Tests.Language.ProgramV1ShiftExpressions.run
  IO.println "shard-language-b: ok"
