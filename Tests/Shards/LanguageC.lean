import Tests.Language.ProgramV1EqualityExpressions
import Tests.Language.ProgramV1OrderingComparisons
import Tests.Language.ProgramV1BitwiseExpressions
import Tests.Language.ProgramV1LogicalExpressions
import Tests.Language.ProgramV1CoreStatements
import Tests.Language.Loader
import Tests.Language.ProgramV1RevertEmitStatements
import Tests.Language.ProgramV1StringLiterals
unsafe def main : IO Unit := do
  Tests.Language.ProgramV1EqualityExpressions.run
  Tests.Language.ProgramV1OrderingComparisons.run
  Tests.Language.ProgramV1BitwiseExpressions.run
  Tests.Language.ProgramV1LogicalExpressions.run
  Tests.Language.ProgramV1CoreStatements.run
  Tests.Language.Loader.run
  Tests.Language.ProgramV1RevertEmitStatements.run
  Tests.Language.ProgramV1StringLiterals.run
  IO.println "shard-language-c: ok"
