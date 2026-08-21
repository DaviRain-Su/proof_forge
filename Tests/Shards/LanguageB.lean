import Tests.Shards.Runner
import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1DeclarationNegatives
import Tests.Language.ProgramV1ExternalStatements
import Tests.Language.ProgramV1ControlFlow
import Tests.Language.ProgramV1ExpressionForms
import Tests.Language.ProgramV1UnaryExpressions
import Tests.Language.ProgramV1ArithmeticExpressions
import Tests.Language.ProgramV1ShiftExpressions

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.ProgramV1Declarations" Tests.Language.ProgramV1Declarations.run
  runSuite "Tests.Language.ProgramV1DeclarationNegatives"
    Tests.Language.ProgramV1DeclarationNegatives.run
  runSuite "Tests.Language.ProgramV1ExternalStatements"
    Tests.Language.ProgramV1ExternalStatements.run
  runSuite "Tests.Language.ProgramV1ControlFlow" Tests.Language.ProgramV1ControlFlow.run
  runSuite "Tests.Language.ProgramV1ExpressionForms" Tests.Language.ProgramV1ExpressionForms.run
  runSuite "Tests.Language.ProgramV1UnaryExpressions" Tests.Language.ProgramV1UnaryExpressions.run
  runSuite "Tests.Language.ProgramV1ArithmeticExpressions"
    Tests.Language.ProgramV1ArithmeticExpressions.run
  runSuite "Tests.Language.ProgramV1ShiftExpressions" Tests.Language.ProgramV1ShiftExpressions.run
  IO.println "shard-language-b: ok"
