import Tests.Shards.Runner
import Tests.Language.ProgramV1EqualityExpressions
import Tests.Language.ProgramV1OrderingComparisons
import Tests.Language.ProgramV1BitwiseExpressions
import Tests.Language.ProgramV1LogicalExpressions
import Tests.Language.ProgramV1CoreStatements
import Tests.Language.Loader
import Tests.Language.TheoremInventoryV1
import Tests.Language.ProgramV1RevertEmitStatements
import Tests.Language.ProgramV1StringLiterals

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.ProgramV1EqualityExpressions"
    Tests.Language.ProgramV1EqualityExpressions.run
  runSuite "Tests.Language.ProgramV1OrderingComparisons"
    Tests.Language.ProgramV1OrderingComparisons.run
  runSuite "Tests.Language.ProgramV1BitwiseExpressions"
    Tests.Language.ProgramV1BitwiseExpressions.run
  runSuite "Tests.Language.ProgramV1LogicalExpressions"
    Tests.Language.ProgramV1LogicalExpressions.run
  runSuite "Tests.Language.ProgramV1CoreStatements" Tests.Language.ProgramV1CoreStatements.run
  runSuite "Tests.Language.Loader" Tests.Language.Loader.run
  runSuite "Tests.Language.TheoremInventoryV1" Tests.Language.TheoremInventoryV1.run
  runSuite "Tests.Language.ProgramV1RevertEmitStatements"
    Tests.Language.ProgramV1RevertEmitStatements.run
  runSuite "Tests.Language.ProgramV1StringLiterals" Tests.Language.ProgramV1StringLiterals.run
  IO.println "shard-language-c: ok"
