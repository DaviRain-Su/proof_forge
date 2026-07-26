import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Typed.NameResolutionV1
import Tests.Typed.TypeCheckExpressionsV1
import Tests.Typed.TypeCheckCallsV1
import Tests.Language.ProgramV1Declarations
import Tests.Language.ProgramV1DeclarationNegatives
import Tests.Language.ProgramV1ExternalStatements
import Tests.Language.ProgramV1ControlFlow
import Tests.Language.ProgramV1ExpressionForms
import Tests.Language.ProgramV1UnaryExpressions
import Tests.Language.ProgramV1ArithmeticExpressions
import Tests.Language.ProgramV1ShiftExpressions
import Tests.Language.ProgramV1EqualityExpressions
import Tests.Language.ProgramV1OrderingComparisons
import Tests.Language.ProgramV1BitwiseExpressions
import Tests.Language.ProgramV1LogicalExpressions
import Tests.Language.ProgramV1CoreStatements
import Tests.Language.ProgramV1MatchStatements
import Tests.Language.ProgramV1MatchExpressions
import Tests.Language.ProgramV1ConstructorPatterns
import Tests.Language.ProgramV1FieldPlaces
import Tests.Language.ProgramV1IndexedPlaces
import Tests.Language.ProgramV1PlaceSuffixes
import Tests.Language.ProgramV1RevertEmitStatements
import Tests.Language.ProgramV1StringLiterals
import Tests.Language.ProgramV1TypeSurface
import Tests.Language.ProgramV1SpanJoin
import Tests.Language.ProgramV1Diagnostics
import Tests.Core.DiagnosticV1
import Tests.Product.CounterV1Evm
import Tests.CLI.Emit
import Tests.CLI.ToolchainPolicy

unsafe def main : IO Unit := do
  Tests.Compiler.ValidatedSourceV1Pipeline.run
  Tests.Typed.NameResolutionV1.run
  Tests.Typed.TypeCheckExpressionsV1.run
  Tests.Typed.TypeCheckCallsV1.run
  Tests.Language.ProgramV1Declarations.run
  Tests.Language.ProgramV1DeclarationNegatives.run
  Tests.Language.ProgramV1ExternalStatements.run
  Tests.Language.ProgramV1ControlFlow.run
  Tests.Language.ProgramV1ExpressionForms.run
  Tests.Language.ProgramV1UnaryExpressions.run
  Tests.Language.ProgramV1ArithmeticExpressions.run
  Tests.Language.ProgramV1ShiftExpressions.run
  Tests.Language.ProgramV1EqualityExpressions.run
  Tests.Language.ProgramV1OrderingComparisons.run
  Tests.Language.ProgramV1BitwiseExpressions.run
  Tests.Language.ProgramV1LogicalExpressions.run
  Tests.Language.ProgramV1CoreStatements.run
  Tests.Language.ProgramV1MatchStatements.run
  Tests.Language.ProgramV1MatchExpressions.run
  Tests.Language.ProgramV1ConstructorPatterns.run
  Tests.Language.ProgramV1FieldPlaces.run
  Tests.Language.ProgramV1IndexedPlaces.run
  Tests.Language.ProgramV1PlaceSuffixes.run
  Tests.Language.ProgramV1RevertEmitStatements.run
  Tests.Language.ProgramV1StringLiterals.run
  Tests.Language.ProgramV1TypeSurface.run
  Tests.Language.ProgramV1SpanJoin.run
  Tests.Language.ProgramV1Diagnostics.run
  Tests.Core.DiagnosticV1.run
  Tests.Product.CounterV1Evm.run
  Tests.CLI.Emit.run
  Tests.CLI.ToolchainPolicy.run
  IO.println "proof-forge-next-fast-tests: ok"
