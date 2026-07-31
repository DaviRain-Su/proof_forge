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
unsafe def main : IO Unit := do
  Tests.Language.ProgramV1MatchStatements.run
  Tests.Language.ProgramV1MatchExpressions.run
  Tests.Language.ProgramV1ConstructorPatterns.run
  Tests.Language.ProgramV1FieldPlaces.run
  Tests.Language.ProgramV1IndexedPlaces.run
  Tests.Language.ProgramV1PlaceSuffixes.run
  Tests.Language.ProgramV1TypeSurface.run
  Tests.Language.ProgramV1SpanJoin.run
  Tests.Language.ProgramV1OriginJoin.run
  Tests.Language.ProgramV1DiagnosticLocate.run
  Tests.Language.ProgramV1Diagnostics.run
  Tests.Language.ProgramV1Bounds.run
  Tests.Language.ProgramV1SourceFullTagGolden.run
  IO.println "shard-language-heavy: ok"
