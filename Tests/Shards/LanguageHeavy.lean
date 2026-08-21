import Tests.Shards.Runner
import Tests.Language.ProgramV1MatchStatements
import Tests.Language.ProgramV1MatchExpressions
import Tests.Language.ProgramV1ConstructorPatterns
import Tests.Language.ProgramV1FieldPlaces
import Tests.Language.ProgramV1IndexedPlaces
import Tests.Language.ProgramV1PlaceSuffixes
import Tests.Language.ProgramV1TypeSurface
import Tests.Language.ProgramV1SpanJoin
import Tests.Language.ProgramV1OriginJoin
import Tests.Language.ProgramV1DiagnosticLocate
import Tests.Language.ProgramV1Diagnostics
import Tests.Language.ProgramV1Bounds
import Tests.Language.ProgramV1SourceFullTagGolden

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Language.ProgramV1MatchStatements" Tests.Language.ProgramV1MatchStatements.run
  runSuite "Tests.Language.ProgramV1MatchExpressions"
    Tests.Language.ProgramV1MatchExpressions.run
  runSuite "Tests.Language.ProgramV1ConstructorPatterns"
    Tests.Language.ProgramV1ConstructorPatterns.run
  runSuite "Tests.Language.ProgramV1FieldPlaces" Tests.Language.ProgramV1FieldPlaces.run
  runSuite "Tests.Language.ProgramV1IndexedPlaces" Tests.Language.ProgramV1IndexedPlaces.run
  runSuite "Tests.Language.ProgramV1PlaceSuffixes" Tests.Language.ProgramV1PlaceSuffixes.run
  runSuite "Tests.Language.ProgramV1TypeSurface" Tests.Language.ProgramV1TypeSurface.run
  runSuite "Tests.Language.ProgramV1SpanJoin" Tests.Language.ProgramV1SpanJoin.run
  runSuite "Tests.Language.ProgramV1OriginJoin" Tests.Language.ProgramV1OriginJoin.run
  runSuite "Tests.Language.ProgramV1DiagnosticLocate"
    Tests.Language.ProgramV1DiagnosticLocate.run
  runSuite "Tests.Language.ProgramV1Diagnostics" Tests.Language.ProgramV1Diagnostics.run
  runSuite "Tests.Language.ProgramV1Bounds" Tests.Language.ProgramV1Bounds.run
  runSuite "Tests.Language.ProgramV1SourceFullTagGolden"
    Tests.Language.ProgramV1SourceFullTagGolden.run
  IO.println "shard-language-heavy: ok"
