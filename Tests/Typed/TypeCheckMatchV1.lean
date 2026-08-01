import Tests.Language.ParserSession
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.ModelV1
import ProofForgeV2.Typed.NameResolutionV1
import ProofForgeV2.Typed.TypeCheckV1

namespace Tests.Typed.TypeCheckMatchV1

open ProofForgeV2
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.ModelV1
open ProofForgeV2.Typed.NameResolutionV1
open ProofForgeV2.Typed.TypeCheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def resultMessages (res : TypeCheckResultV1) : Array String :=
  res.diagnostics.map (·.message)

private def programMessages (res : TypeCheckProgramResultV1) : Array String :=
  res.diagnostics.map (·.message)

private def contains (haystack : Array String) (needle : String) : Bool :=
  haystack.any (·.contains needle)

private def mkName (raw : String) : IO SourceNameComponentV1 :=
  match parseSourceNameComponentV1 raw with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"mkName: {e}"

private def mkQn (raws : Array String) : IO SourceQualifiedNameV1 :=
  match parseSourceQualifiedNameV1 raws with
  | .ok q => pure q
  | .error e => throw <| IO.userError s!"mkQn: {e}"

private def u (n : Nat) : ExprV1 := .literal (.integer n)
private def b (v : Bool) : ExprV1 := .literal (.bool v)
private def place (raw : String) : IO ExprV1 := do
  pure (.place (.name (← mkName raw)))

private def resultProgram (prelude body result : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckMatch where\n" ++
  prelude ++
  "  entry run() : " ++ result ++ " do\n" ++
  body

private unsafe def typeCheckResult
    (session : Language.Loader.ParserSession) (label prelude body result : String) :
    IO TypeCheckProgramResultV1 := do
  match ← session.selectProgramV1 (resultProgram prelude body result)
      ("<type-check-match-" ++ label ++ ">")
      "Tests.TypeCheckMatchV1" none with
  | .ok validated => pure (typeCheckProgramV1 validated.program (resolveProgramV1 validated))
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def typeCheckUnit
    (session : Language.Loader.ParserSession) (label prelude body : String) :
    IO TypeCheckProgramResultV1 := do
  typeCheckResult session label prelude body "Unit"

private unsafe def expectProgramOk
    (session : Language.Loader.ParserSession) (label prelude body result : String) :
    IO Unit := do
  let res ← typeCheckResult session label prelude body result
  unless res.ok do
    throw <| IO.userError s!"{label}: expected ok, got {programMessages res}"

private unsafe def expectProgramDiag
    (res : TypeCheckProgramResultV1) (label needle : String) : IO Unit := do
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got ok"
  unless contains (programMessages res) needle do
    throw <| IO.userError s!"{label}: expected diagnostic containing '{needle}', got {programMessages res}"

private unsafe def expectExprOk
    (label : String) (res : TypeCheckResultV1) (expectedType : TypeV1) : IO Unit := do
  unless res.diagnostics.isEmpty do
    throw <| IO.userError s!"{label}: expected no diagnostics, got {resultMessages res}"
  unless res.type == expectedType do
    throw <| IO.userError s!"{label}: expected type {repr expectedType}, got {repr res.type}"

private unsafe def expectExprDiag
    (label : String) (res : TypeCheckResultV1) (needle : String) : IO Unit := do
  if res.diagnostics.isEmpty then
    throw <| IO.userError s!"{label}: expected diagnostics, got clean result {repr res.type}"
  unless contains (resultMessages res) needle do
    throw <| IO.userError s!"{label}: expected diagnostic containing '{needle}', got {resultMessages res}"

private def preludeProgram (prelude : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeCheckMatch where\n" ++
  prelude ++
  "  entry dummy() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def resolvePrelude
    (session : Language.Loader.ParserSession) (label prelude : String) :
    IO NameResolutionResultV1 := do
  match ← session.selectProgramV1 (preludeProgram prelude)
      ("<type-check-match-raw-" ++ label ++ ">")
      "Tests.TypeCheckMatchV1" none with
  | .ok validated => pure (resolveProgramV1 validated)
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def testWildcardBool
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | _ => false\n"
  expectProgramOk session "wildcard-bool" "" body "Bool"

private unsafe def testBindBool
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | b => b\n"
  expectProgramOk session "bind-bool" "" body "Bool"

private unsafe def testBoolLiteralPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | true => false\n" ++
    "      | false => true\n" ++
    "      | _ => false\n"
  expectProgramOk session "bool-literal-pattern" "" body "Bool"

private unsafe def testIntegerPatternWidth
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state n : UInt8\n"
  let body :=
    "    return\n" ++
    "      match n with\n" ++
    "      | 0 => 0\n" ++
    "      | 255 => 255\n" ++
    "      | _ => 1\n"
  expectProgramOk session "integer-pattern-width" prelude body "UInt8"

private unsafe def testIntegerPatternOutOfRange
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state n : UInt8\n"
  let body :=
    "    return\n" ++
    "      match n with\n" ++
    "      | 256 => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "integer-pattern-range" prelude body "UInt8"
  expectProgramDiag res "integer-pattern-range" "out of range"
  expectProgramDiag res "integer-pattern-range" "UInt8"

private unsafe def testEnumConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | Color.Red() => 0\n" ++
    "      | Color.Green() => 1\n" ++
    "      | Color.Blue() => 2\n"
  expectProgramOk session "enum-constructor-pattern" prelude body "UInt64"

private unsafe def testEnumConstructorWithPayload
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Shape where\n" ++
    "    | Circle(UInt64)\n" ++
    "    | Rect(UInt64, UInt64)\n"
  let body :=
    "    let s : Shape := Shape.Circle(5)\n" ++
    "    return\n" ++
    "      match s with\n" ++
    "      | Shape.Circle(r) => r\n" ++
    "      | Shape.Rect(w, h) => w * h\n"
  expectProgramOk session "enum-payload-pattern" prelude body "UInt64"

private unsafe def testStringPatternOnNonStringRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | \"hello\" => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "string-pattern" "" body "UInt64"
  expectProgramDiag res "string-pattern" "expected String"

private unsafe def testWrongTypeLiteralPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | 1 => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "wrong-type-literal" "" body "UInt64"
  expectProgramDiag res "wrong-type-literal" "Bool"

private unsafe def testExpressionArmMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | true => 0\n" ++
    "      | false => true\n" ++
    "      | _ => 0\n"
  let res ← typeCheckResult session "expr-arm-mismatch" "" body "UInt64"
  expectProgramDiag res "expr-arm-mismatch" "match arm 1"
  expectProgramDiag res "expr-arm-mismatch" "UInt64"
  expectProgramDiag res "expr-arm-mismatch" "Bool"

private unsafe def testStatementMatchBodyInResultContext
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  state total : UInt64\n"
  let body :=
    "    match true with\n" ++
    "    | true => do\n" ++
    "      total := 1\n" ++
    "      return 10\n" ++
    "    | false => do\n" ++
    "      total := 2\n" ++
    "      return 20\n" ++
    "    | _ => do\n" ++
    "      total := 0\n" ++
    "      return 0\n"
  expectProgramOk session "stmt-body-result" prelude body "UInt64"

private unsafe def testStatementMatchBodyMismatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  state total : UInt64\n"
  let body :=
    "    match true with\n" ++
    "    | true => do\n" ++
    "      total := 1\n" ++
    "      return true\n" ++
    "    | false => do\n" ++
    "      total := 2\n" ++
    "      return 20\n" ++
    "    | _ => do\n" ++
    "      total := 0\n" ++
    "      return 0\n"
  let res ← typeCheckResult session "stmt-body-mismatch" prelude body "UInt64"
  expectProgramDiag res "stmt-body-mismatch" "UInt64"
  expectProgramDiag res "stmt-body-mismatch" "Bool"

private unsafe def testExhaustiveEnumByWildcard
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | _ => 0\n"
  expectProgramOk session "exhaustive-wildcard" prelude body "UInt64"

private unsafe def testExhaustiveEnumByBind
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | color => 0\n"
  expectProgramOk session "exhaustive-bind" prelude body "UInt64"

private unsafe def testExhaustiveEnumByVariants
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | Color.Red() => 0\n" ++
    "      | Color.Green() => 1\n" ++
    "      | Color.Blue() => 2\n"
  expectProgramOk session "exhaustive-variants" prelude body "UInt64"

private unsafe def testMissingVariant
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | Color.Red() => 0\n" ++
    "      | Color.Green() => 1\n"
  let res ← typeCheckResult session "missing-variant" prelude body "UInt64"
  expectProgramDiag res "missing-variant" "not exhaustive"
  expectProgramDiag res "missing-variant" "Blue"

private unsafe def testMissingVariantsInDeclarationOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | Color.Green() => 1\n"
  let res ← typeCheckResult session "missing-variants-order" prelude body "UInt64"
  expectProgramDiag res "missing-variants-order" "not exhaustive"
  expectProgramDiag res "missing-variants-order" "Red, Blue"

private unsafe def testNonEnumRequiresCatchAll
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state n : UInt64\n"
  let body :=
    "    return\n" ++
    "      match n with\n" ++
    "      | 0 => 0\n" ++
    "      | 1 => 1\n"
  let res ← typeCheckResult session "non-enum-no-catchall" prelude body "UInt64"
  expectProgramDiag res "non-enum-no-catchall" "not exhaustive"

private unsafe def testUnreachableAfterCatchAllStillChecked
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | _ => 0\n" ++
    "      | true => 1\n" ++
    "      | false => 2\n"
  expectProgramOk session "unreachable-after-catchall" "" body "UInt64"

private unsafe def testUnreachableWithTypeErrorStillChecked
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | _ => 0\n" ++
    "      | true => true\n" ++
    "      | false => 2\n"
  let res ← typeCheckResult session "unreachable-type-error" "" body "UInt64"
  expectProgramDiag res "unreachable-type-error" "match arm 1"

private unsafe def testSourceOrderScrutineeBeforeArms
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match 1 with\n" ++
    "      | true => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "order-scrutinee" "" body "UInt64"
  let msgs := programMessages res
  unless msgs.size >= 2 do
    throw <| IO.userError s!"order-scrutinee: expected >=2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "integer literal" do
    throw <| IO.userError s!"order-scrutinee: first diag should mention integer literal, got {msgs}"
  unless msgs[1]!.contains "Bool" do
    throw <| IO.userError s!"order-scrutinee: second diag should mention Bool, got {msgs}"

private unsafe def testSourceOrderPatternBeforeArmValue
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | 0 => true\n" ++
    "      | _ => 0\n"
  let res ← typeCheckResult session "order-pattern-value" "" body "UInt64"
  let msgs := programMessages res
  unless msgs.size >= 2 do
    throw <| IO.userError s!"order-pattern-value: expected >=2 diagnostics, got {msgs}"
  unless msgs[0]!.contains "Bool" do
    throw <| IO.userError s!"order-pattern-value: first diag should mention Bool, got {msgs}"
  unless msgs[1]!.contains "UInt64" do
    throw <| IO.userError s!"order-pattern-value: second diag should mention UInt64, got {msgs}"

private unsafe def testSourceOrderEarlierArmBeforeLater
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | true => 0\n" ++
    "      | false => true\n" ++
    "      | _ => true\n"
  let res ← typeCheckResult session "order-earlier-later" "" body "UInt64"
  let msgs := programMessages res
  let armDiagIndices := (msgs.toList.zip (List.range msgs.size))
    |>.filter (fun (m, _) => m.contains "match arm")
    |>.map (·.2)
  unless armDiagIndices.length >= 2 do
    throw <| IO.userError s!"order-earlier-later: expected >=2 arm mismatch diagnostics, got {msgs}"
  unless armDiagIndices[0]! < armDiagIndices[1]! do
    throw <| IO.userError s!"order-earlier-later: arm diagnostics out of order, got {msgs}"
  unless msgs.any (fun m => m.contains "match arm 1") do
    throw <| IO.userError s!"order-earlier-later: expected arm 1 diagnostic, got {msgs}"
  unless msgs.any (fun m => m.contains "match arm 2") do
    throw <| IO.userError s!"order-earlier-later: expected arm 2 diagnostic, got {msgs}"

private unsafe def testExpressionMatchResultTypePropagated
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    return\n" ++
    "      match true with\n" ++
    "      | true => 1\n" ++
    "      | false => 2\n" ++
    "      | _ => 0\n"
  expectProgramOk session "expr-result-propagated" "" body "UInt64"

private unsafe def testStatementMatchNoLeak
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "    match true with\n" ++
    "    | b => do\n" ++
    "      return\n" ++
    "    | _ => do\n" ++
    "      return\n" ++
    "    return b\n"
  let res ← typeCheckUnit session "stmt-no-leak" "" body
  expectProgramDiag res "stmt-no-leak" "unknown name 'b'"

/-- AST-direct helpers: the ProgramV1 parser rejects single-component constructor
    patterns (`Point(a, b)`), so struct-pattern coverage is driven by constructing
    the `ExprV1`/`PatternV1` values directly against a name-resolved program. -/
private unsafe def resolvePreludeToScope
    (session : Language.Loader.ParserSession) (label prelude : String) :
    IO (TypeCheckScopeV1 × TypedDeclTablesV1) := do
  let resolved ← resolvePrelude session label prelude
  unless resolved.ok do
    throw <| IO.userError s!"{label}: name resolution failed: {repr resolved.diagnostics}"
  pure (scopeFromTables resolved.tables, resolved.tables)

private unsafe def testStructConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n"
  let (scope, tables) ← resolvePreludeToScope session "struct-ctor-pattern" prelude
  let scrutinee ← place "p"
  let pattern := .constructor (← mkQn #["Point"]) #[
    .bind (← mkName "a"),
    .bind (← mkName "b")]
  let value := .binary .add (.place (.name (← mkName "a"))) (.place (.name (← mkName "b")))
  let catchAll := { pattern := .wildcard, value := u 0 }
  let expr := .match_ scrutinee #[{ pattern, value }, catchAll]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprOk "struct-ctor-pattern" res (.uint 64)

private unsafe def testNestedStructConstructorPattern
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  struct Line where\n" ++
    "    a : Point\n" ++
    "    b : Point\n" ++
    "  state l : Line\n"
  let (scope, tables) ← resolvePreludeToScope session "nested-struct-pattern" prelude
  let scrutinee ← place "l"
  let point ← mkQn #["Point"]
  let line ← mkQn #["Line"]
  let a1 ← mkName "a1"
  let a2 ← mkName "a2"
  let b1 ← mkName "b1"
  let b2 ← mkName "b2"
  let pattern := .constructor line #[
    .constructor point #[.bind a1, .bind a2],
    .constructor point #[.bind b1, .bind b2]]
  let value :=
    .binary .add
      (.binary .add (.place (.name a1)) (.place (.name a2)))
      (.binary .add (.place (.name b1)) (.place (.name b2)))
  let catchAll := { pattern := .wildcard, value := u 0 }
  let expr := .match_ scrutinee #[{ pattern, value }, catchAll]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprOk "nested-struct-pattern" res (.uint 64)

private unsafe def testConstructorOnNonNamed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state n : UInt64\n"
  let (scope, tables) ← resolvePreludeToScope session "ctor-non-named" prelude
  let scrutinee ← place "n"
  let pattern := .constructor (← mkQn #["Point"]) #[
    .bind (← mkName "a"),
    .bind (← mkName "b")]
  let value := .binary .add (.place (.name (← mkName "a"))) (.place (.name (← mkName "b")))
  let expr := .match_ scrutinee #[{ pattern, value }]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprDiag "ctor-non-named" res "UInt64"
  expectExprDiag "ctor-non-named" res "Point"

private unsafe def testStructRequiresCatchAll
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n"
  let (scope, tables) ← resolvePreludeToScope session "struct-no-catchall" prelude
  let scrutinee ← place "p"
  let pattern := .constructor (← mkQn #["Point"]) #[
    .bind (← mkName "a"),
    .bind (← mkName "b")]
  let value := .binary .add (.place (.name (← mkName "a"))) (.place (.name (← mkName "b")))
  let expr := .match_ scrutinee #[{ pattern, value }]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprDiag "struct-no-catchall" res "not exhaustive"

private unsafe def testWrongConstructorArgCount
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n"
  let (scope, tables) ← resolvePreludeToScope session "ctor-arg-count" prelude
  let scrutinee ← place "p"
  let pattern := .constructor (← mkQn #["Point"]) #[.bind (← mkName "a")]
  let value := .place (.name (← mkName "a"))
  let expr := .match_ scrutinee #[{ pattern, value }]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprDiag "ctor-arg-count" res "2"
  expectExprDiag "ctor-arg-count" res "1"

private unsafe def testWrongSubPatternType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n"
  let (scope, tables) ← resolvePreludeToScope session "subpattern-type" prelude
  let scrutinee ← place "p"
  let pattern := .constructor (← mkQn #["Pair"]) #[
    .literal (.bool true),
    .bind (← mkName "b")]
  let value := .place (.name (← mkName "b"))
  let expr := .match_ scrutinee #[{ pattern, value }]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprDiag "subpattern-type" res "UInt64"
  expectExprDiag "subpattern-type" res "Bool"

private unsafe def testBoolLiteralOnIntegerScrutinee
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state n : UInt64\n"
  let body :=
    "    return\n" ++
    "      match n with\n" ++
    "      | true => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "bool-literal-on-int" prelude body "UInt64"
  expectProgramDiag res "bool-literal-on-int" "Bool"
  expectProgramDiag res "bool-literal-on-int" "UInt64"

private unsafe def testSignedIntegerPatternBoundary
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state n : Int8\n"
  let body :=
    "    return\n" ++
    "      match n with\n" ++
    "      | 128 => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "signed-int-boundary" prelude body "UInt64"
  expectProgramDiag res "signed-int-boundary" "out of range"
  expectProgramDiag res "signed-int-boundary" "Int8"

private unsafe def testConstructorPatternOnDifferentEnum
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum A where\n" ++
    "    | A1\n" ++
    "  enum B where\n" ++
    "    | B1\n"
  let body :=
    "    let a : A := A.A1()\n" ++
    "    return\n" ++
    "      match a with\n" ++
    "      | B.B1() => 0\n" ++
    "      | _ => 1\n"
  let res ← typeCheckResult session "ctor-different-enum" prelude body "UInt64"
  expectProgramDiag res "ctor-different-enum" "A"
  expectProgramDiag res "ctor-different-enum" "B"

private unsafe def testStatementMatchEnumMissingVariant
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Green\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    match c with\n" ++
    "    | Color.Red() => do\n" ++
    "      return\n" ++
    "    | Color.Green() => do\n" ++
    "      return\n"
  let res ← typeCheckUnit session "stmt-missing-variant" prelude body
  expectProgramDiag res "stmt-missing-variant" "not exhaustive"
  expectProgramDiag res "stmt-missing-variant" "Blue"

private unsafe def testEmptyMatchExpression
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (scope, tables) ← resolvePreludeToScope session "empty-match" ""
  let expr := ExprV1.match_ (b true) #[]
  let res := typeCheckExpr scope tables (some (.uint 64)) expr
  expectExprDiag "empty-match" res "empty match expression"

private unsafe def testStatementMatchUnreachableBodyTypeError
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude := "  state total : UInt64\n"
  let body :=
    "    match true with\n" ++
    "    | _ => do\n" ++
    "      total := 0\n" ++
    "      return\n" ++
    "    | true => do\n" ++
    "      total := 1\n" ++
    "      return true\n"
  let res ← typeCheckUnit session "stmt-unreachable-body-error" prelude body
  expectProgramDiag res "stmt-unreachable-body-error" "Bool"
  expectProgramDiag res "stmt-unreachable-body-error" "Unit"

/-- N-A2: multi-arm same outer constructor with distinguishable nested ctors. -/
private unsafe def testMultiArmSameOuterNestedCtor
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Inner where\n" ++
    "    | A\n" ++
    "    | B\n" ++
    "  enum Outer where\n" ++
    "    | Wrap(Inner)\n" ++
    "    | Empty\n"
  let body :=
    "    let o : Outer := Outer.Wrap(Inner.A())\n" ++
    "    return\n" ++
    "      match o with\n" ++
    "      | Outer.Wrap(Inner.A()) => 1\n" ++
    "      | Outer.Wrap(Inner.B()) => 2\n" ++
    "      | Outer.Empty() => 0\n"
  expectProgramOk session "multi-arm-nested-ctor" prelude body "UInt64"

/-- N-A2: multi-arm same outer with nested integer literals. -/
private unsafe def testMultiArmSameOuterNestedLit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n"
  let body :=
    "    let m : Maybe := Maybe.Some(1)\n" ++
    "    return\n" ++
    "      match m with\n" ++
    "      | Maybe.Some(1) => 10\n" ++
    "      | Maybe.Some(2) => 20\n" ++
    "      | Maybe.None() => 0\n" ++
    "      | _ => 99\n"
  expectProgramOk session "multi-arm-nested-lit" prelude body "UInt64"

/-- N-A2: identical nested patterns on same outer ctor → duplicate. -/
private unsafe def testMultiArmSameOuterDuplicateRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n"
  let body :=
    "    let m : Maybe := Maybe.Some(1)\n" ++
    "    return\n" ++
    "      match m with\n" ++
    "      | Maybe.Some(x) => x\n" ++
    "      | Maybe.Some(y) => y\n" ++
    "      | Maybe.None() => 0\n"
  let res ← typeCheckResult session "multi-arm-dup" prelude body "UInt64"
  expectProgramDiag res "multi-arm-dup" "duplicate pattern"

/-- N-A2: identical nested literal patterns → duplicate. -/
private unsafe def testMultiArmSameOuterDuplicateLitRejected
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n"
  let body :=
    "    let m : Maybe := Maybe.Some(1)\n" ++
    "    return\n" ++
    "      match m with\n" ++
    "      | Maybe.Some(1) => 10\n" ++
    "      | Maybe.Some(1) => 11\n" ++
    "      | _ => 0\n"
  let res ← typeCheckResult session "multi-arm-dup-lit" prelude body "UInt64"
  expectProgramDiag res "multi-arm-dup-lit" "duplicate pattern"

/-- N-A2: source-order — later duplicate arm is reported by index. -/
private unsafe def testMultiArmDuplicateSourceOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let prelude :=
    "  enum Color where\n" ++
    "    | Red\n" ++
    "    | Blue\n"
  let body :=
    "    let c : Color := Color.Red()\n" ++
    "    return\n" ++
    "      match c with\n" ++
    "      | Color.Red() => 1\n" ++
    "      | Color.Red() => 2\n" ++
    "      | Color.Blue() => 3\n"
  let res ← typeCheckResult session "multi-arm-dup-order" prelude body "UInt64"
  expectProgramDiag res "multi-arm-dup-order" "duplicate pattern"
  expectProgramDiag res "multi-arm-dup-order" "match arm 1"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testWildcardBool session
  testBindBool session
  testBoolLiteralPattern session
  testIntegerPatternWidth session
  testIntegerPatternOutOfRange session
  testEnumConstructorPattern session
  testEnumConstructorWithPayload session
  testStringPatternOnNonStringRejected session
  testWrongTypeLiteralPattern session
  testExpressionArmMismatch session
  testStatementMatchBodyInResultContext session
  testStatementMatchBodyMismatch session
  testExhaustiveEnumByWildcard session
  testExhaustiveEnumByBind session
  testExhaustiveEnumByVariants session
  testMissingVariant session
  testMissingVariantsInDeclarationOrder session
  testNonEnumRequiresCatchAll session
  testUnreachableAfterCatchAllStillChecked session
  testUnreachableWithTypeErrorStillChecked session
  testSourceOrderScrutineeBeforeArms session
  testSourceOrderPatternBeforeArmValue session
  testSourceOrderEarlierArmBeforeLater session
  testExpressionMatchResultTypePropagated session
  testStatementMatchNoLeak session
  testStructConstructorPattern session
  testNestedStructConstructorPattern session
  testConstructorOnNonNamed session
  testStructRequiresCatchAll session
  testWrongConstructorArgCount session
  testWrongSubPatternType session
  testBoolLiteralOnIntegerScrutinee session
  testSignedIntegerPatternBoundary session
  testConstructorPatternOnDifferentEnum session
  testStatementMatchEnumMissingVariant session
  testEmptyMatchExpression session
  testStatementMatchUnreachableBodyTypeError session
  testMultiArmSameOuterNestedCtor session
  testMultiArmSameOuterNestedLit session
  testMultiArmSameOuterDuplicateRejected session
  testMultiArmSameOuterDuplicateLitRejected session
  testMultiArmDuplicateSourceOrder session
  IO.println "Tests.Typed.TypeCheckMatchV1: ok"

end Tests.Typed.TypeCheckMatchV1
