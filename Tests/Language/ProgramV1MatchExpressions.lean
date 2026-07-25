import Tests.Language.ParserSession
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1MatchExpressions

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program MatchExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
  body

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-match-expressions-" ++ label ++ ">")
      "Tests.ProgramV1MatchExpressions" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeReturnExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO ExprV1 := do
  let value ← decodeSource session label body
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.return_ (some value)] => pure value
      | other => throw <| IO.userError s!"'{label}' did not decode one return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def decodeAssertCondition
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO ExprV1 := do
  let value ← decodeSource session label body
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.assert_ condition none] => pure condition
      | other => throw <| IO.userError s!"'{label}' did not decode one assert: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-match-expressions-negative-" ++ label ++ ">")
      "Tests.ProgramV1MatchExpressions" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def canonicalBytes (source : ValidatedSourceV1) (label : String) : IO ByteArray :=
  match canonicalValidatedSourceAstBytesV1 source with
  | .ok bytes => pure bytes
  | .error error => throw <| IO.userError s!"{label}: canonical bytes failed: {error}"

private def sourceHash (source : ValidatedSourceV1) (label : String) : IO ProofForgeV2.Core.Common.Digest :=
  match sourceHashV1 source with
  | .ok digest => pure digest
  | .error error => throw <| IO.userError s!"{label}: sourceHashV1 failed: {error}"

private def expectSameProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program == right.program) s!"{label}: ProgramV1 AST changed"
  expect ((← canonicalBytes left (label ++ " left")) ==
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes changed"
  expect ((← sourceHash left (label ++ " left")) ==
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 changed"

private def expectDifferentProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program != right.program) s!"{label}: ProgramV1 AST unexpectedly aliased"
  expect ((← canonicalBytes left (label ++ " left")) !=
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes unexpectedly aliased"
  expect ((← sourceHash left (label ++ " left")) !=
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 unexpectedly aliased"

private def expectPlaceNameExpr (expr : ExprV1) (expected label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) s!"{label}: place name changed"
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

private def expectLiteral (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer literal, got {repr other}"

private def exprAt (exprs : Array ExprV1) (index : Nat) (label : String) : IO ExprV1 :=
  match exprs[index]? with
  | some expr => pure expr
  | none => throw <| IO.userError s!"{label}: missing expression {index}"

private def expectUnary (expr : ExprV1) (expected : UnaryOpV1) (label : String) : IO ExprV1 := do
  match expr with
  | .unary op operand =>
      expect (op == expected) s!"{label}: unary operator changed"
      pure operand
  | other => throw <| IO.userError s!"{label}: expected unary, got {repr other}"

private def expectBinary (expr : ExprV1) (expected : BinaryOpV1) (label : String) :
    IO (ExprV1 × ExprV1) := do
  match expr with
  | .binary op lhs rhs =>
      expect (op == expected) s!"{label}: binary operator changed"
      pure (lhs, rhs)
  | other => throw <| IO.userError s!"{label}: expected binary, got {repr other}"

private def expectMatch (expr : ExprV1) (label : String) : IO (ExprV1 × Array ExprMatchArmV1) := do
  match expr with
  | .match_ scrutinee arms => pure (scrutinee, arms)
  | other => throw <| IO.userError s!"{label}: expected match expression, got {repr other}"

private def armAt (arms : Array ExprMatchArmV1) (index : Nat) (label : String) : IO ExprMatchArmV1 :=
  match arms[index]? with
  | some arm => pure arm
  | none => throw <| IO.userError s!"{label}: missing arm {index}"

/-- Test-side shape description so we never need to construct private AST carriers. -/
inductive PatternShape
  | wildcard
  | bind (raw : String)
  | boolLiteral (value : Bool)
  | intLiteral (value : Nat)
  | stringLiteral (value : String)
  | constructor (path : List String) (args : Array PatternShape)
  deriving Repr

private partial def checkPattern (pattern : PatternV1) (shape : PatternShape) (label : String) : IO Unit := do
  match pattern, shape with
  | .wildcard, .wildcard => pure ()
  | .bind name, .bind expected =>
      expect (name.raw == expected) s!"{label}: bind raw '{name.raw}' != '{expected}'"
  | .literal (.bool value), .boolLiteral expected =>
      expect (value == expected) s!"{label}: bool literal changed"
  | .literal (.integer value), .intLiteral expected =>
      expect (value == expected) s!"{label}: integer literal changed"
  | .literal (.string value), .stringLiteral expected =>
      expect (value == expected) s!"{label}: string literal changed"
  | .constructor qualified args, .constructor expectedPath expectedArgs =>
      let raws : List String := Array.toList ((NonEmptyArray.toArray qualified.components).map (·.raw))
      expect (raws == expectedPath)
        s!"{label}: constructor path '{repr raws}' != '{repr expectedPath}'"
      expect (args.size == expectedArgs.size)
        s!"{label}: constructor arg count {args.size} != {expectedArgs.size}"
      let pairs := List.zip args.toList expectedArgs.toList
      let indexed := List.zip (List.range pairs.length) pairs
      for (i, (arg, shape)) in indexed do
        checkPattern arg shape s!"{label}: arg {i}"
  | _, _ =>
      throw <| IO.userError s!"{label}: pattern shape mismatch: got {repr pattern}, expected {repr shape}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Return position: simplest form with one wildcard arm.
  let (scrutinee, arms) ← expectMatch (← decodeReturnExpr session "wildcard-return"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => 0\n"))
    "wildcard return"
  expectPlaceNameExpr scrutinee "x" "wildcard scrutinee"
  expect (arms.size == 1) "wildcard arm count"
  let arm0 ← armAt arms 0 "wildcard arm"
  checkPattern arm0.pattern .wildcard "wildcard pattern"
  expectLiteral arm0.value 0 "wildcard value"

  -- All pattern kinds in expression arms preserve source order and raw identity.
  let (scrutinee2, arms2) ← expectMatch (← decodeReturnExpr session "all-patterns"
    ("    return\n" ++
     "      match y with\n" ++
     "      | _ => 0\n" ++
     "      | value => 1\n" ++
     "      | true => 2\n" ++
     "      | false => 3\n" ++
     "      | 42 => 4\n" ++
     "      | \"ok\" => 5\n" ++
     "      | «whole.bind» => 6\n" ++
     "      | A.B() => 7\n" ++
     "      | Option.Some(z) => 8\n"))
    "all patterns"
  expectPlaceNameExpr scrutinee2 "y" "all-patterns scrutinee"
  expect (arms2.size == 9) "all-patterns arm count"
  checkPattern (← armAt arms2 0 "wildcard").pattern .wildcard "arm 0 wildcard"
  checkPattern (← armAt arms2 1 "bind").pattern (.bind "value") "arm 1 bind"
  checkPattern (← armAt arms2 2 "true").pattern (.boolLiteral true) "arm 2 true"
  checkPattern (← armAt arms2 3 "false").pattern (.boolLiteral false) "arm 3 false"
  checkPattern (← armAt arms2 4 "int").pattern (.intLiteral 42) "arm 4 int"
  checkPattern (← armAt arms2 5 "string").pattern (.stringLiteral "ok") "arm 5 string"
  checkPattern (← armAt arms2 6 "escaped bind").pattern (.bind "whole.bind") "arm 6 escaped bind"
  checkPattern (← armAt arms2 7 "empty ctor").pattern
    (.constructor ["A", "B"] #[]) "arm 7 empty constructor"
  checkPattern (← armAt arms2 8 "ctor arg").pattern
    (.constructor ["Option", "Some"] #[.bind "z"]) "arm 8 constructor arg"
  for i in [0:9] do
    expectLiteral (← armAt arms2 i s!"arm {i}").value i s!"arm {i} value source order"

  -- Expression match is allowed in assert conditions (value position, not statement).
  let condition ← decodeAssertCondition session "assert-condition"
    ("    assert match x with\n" ++
     "           | _ => true\n")
  let (assertScrutinee, assertArms) ← expectMatch condition "assert condition"
  expectPlaceNameExpr assertScrutinee "x" "assert scrutinee"
  expect (assertArms.size == 1) "assert arm count"

  -- Nested match expression as the body of an expression arm.
  let (nestedScrutinee, nestedArms) ← expectMatch (← decodeReturnExpr session "nested-arm-body"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => match y with\n" ++
     "             | _ => 0\n"))
    "nested arm body"
  expectPlaceNameExpr nestedScrutinee "x" "nested outer scrutinee"
  expect (nestedArms.size == 1) "nested outer arm count"
  let inner ← expectMatch (← armAt nestedArms 0 "outer arm").value "nested inner match"
  expectPlaceNameExpr inner.1 "y" "nested inner scrutinee"
  expect (inner.2.size == 1) "nested inner arm count"

  -- Parenthesized match expression as a binary operand.
  let (addLhs, addRhs) ← expectBinary
    (← decodeReturnExpr session "grouped-operand"
      ("    return\n" ++
       "      (match x with\n" ++
       "       | _ => 1) + 2\n"))
    .add "grouped match as add operand"
  let (groupScrutinee, groupArms) ← expectMatch addLhs "grouped match lhs"
  expectPlaceNameExpr groupScrutinee "x" "grouped match scrutinee"
  expect (groupArms.size == 1) "grouped match arm count"
  expectLiteral addRhs 2 "grouped match add rhs"

  -- Arm values are full precedence-0 expressions: an ungrouped binary operator
  -- inside an arm value must decode with exact operator and operand order.
  let (binScrutinee, binArms) ← expectMatch (← decodeReturnExpr session "binary-arm-value"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => 1 + 2\n"))
    "binary arm value"
  expectPlaceNameExpr binScrutinee "x" "binary arm value scrutinee"
  let (binLhs, binRhs) ← expectBinary (← armAt binArms 0 "binary value arm").value .add
    "binary arm value operator"
  expectLiteral binLhs 1 "binary arm value lhs"
  expectLiteral binRhs 2 "binary arm value rhs"

  -- Match expression as a let value.
  match (← decodeSource session "let-value"
    ("    let result := match x with\n" ++
     "                  | _ => 1\n" ++
     "    return result\n")).program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.let_ binder none value, .return_ (some (.place (.name returned)))] =>
          expect (binder.raw == "result") "let-value binder changed"
          let (letScrutinee, letArms) ← expectMatch value "let value match"
          expectPlaceNameExpr letScrutinee "x" "let value scrutinee"
          expect (letArms.size == 1) "let value arm count"
          expect (returned.raw == "result") "let value return changed"
      | other => throw <| IO.userError s!"let-value body changed: {repr other}"
  | other => throw <| IO.userError s!"let-value item changed: {repr other}"

  -- Match expression as a local-call argument.
  match (← decodeReturnExpr session "local-call-arg"
    ("    return\n" ++
     "      f(match x with\n" ++
     "        | _ => 1)\n")) with
  | .localCall callee args =>
      expect (callee.raw == "f") "local-call arg callee changed"
      expect (args.size == 1) "local-call arg count changed"
      let (callScrutinee, callArms) ← expectMatch (← exprAt args 0 "local-call arg")
        "local-call arg match"
      expectPlaceNameExpr callScrutinee "x" "local-call arg scrutinee"
      expect (callArms.size == 1) "local-call arg arm count"
  | other => throw <| IO.userError s!"local-call arg shape changed: {repr other}"

  -- Match expression as a constructor argument.
  match (← decodeReturnExpr session "ctor-arg"
    ("    return\n" ++
     "      A.B(match x with\n" ++
     "          | _ => 1)\n")) with
  | .constructor ctor args =>
      let path := ctor.components.toArray.map (·.raw)
      expect (path == #["A", "B"]) "constructor arg path changed"
      expect (args.size == 1) "constructor arg count changed"
      let (ctorScrutinee, ctorArms) ← expectMatch (← exprAt args 0 "constructor arg")
        "constructor arg match"
      expectPlaceNameExpr ctorScrutinee "x" "constructor arg scrutinee"
      expect (ctorArms.size == 1) "constructor arg arm count"
  | other => throw <| IO.userError s!"constructor arg shape changed: {repr other}"

  -- Match expression as scrutinee of another match expression.
  let (outerScrutinee, outerArms) ← expectMatch (← decodeReturnExpr session "match-as-scrutinee"
    ("    return\n" ++
     "      match match x with\n" ++
     "            | _ => y\n" ++
     "            with\n" ++
     "      | _ => 0\n"))
    "match as scrutinee"
  let (innerScrutinee, innerArms) ← expectMatch outerScrutinee "inner match"
  expectPlaceNameExpr innerScrutinee "x" "inner match scrutinee"
  expect (innerArms.size == 1) "inner match arm count"
  expectPlaceNameExpr (← armAt innerArms 0 "inner arm").value "y" "inner arm value"
  expect (outerArms.size == 1) "outer match arm count"

  -- Canonical identity: redundant grouping of scrutinee and value preserves bytes/hash.
  expectSameProgramBytesAndHash
    (← decodeSource session "grouped-scrutinee-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "grouped-scrutinee-b"
      ("    return\n" ++
       "      match (x) with\n" ++
       "      | _ => 0\n"))
    "redundant scrutinee grouping must preserve identity"
  expectSameProgramBytesAndHash
    (← decodeSource session "grouped-value-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "grouped-value-b"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => (0)\n"))
    "redundant value grouping must preserve identity"

  -- Hash non-aliasing across shape differences.
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-scrutinee-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "non-alias-scrutinee-b"
      ("    return\n" ++
       "      match y with\n" ++
       "      | _ => 0\n"))
    "different scrutinees must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-pattern-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "non-alias-pattern-b"
      ("    return\n" ++
       "      match x with\n" ++
       "      | true => 0\n"))
    "different patterns must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-value-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "non-alias-value-b"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 1\n"))
    "different arm values must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-arm-order-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | true => 1\n" ++
       "      | false => 2\n"))
    (← decodeSource session "non-alias-arm-order-b"
      ("    return\n" ++
       "      match x with\n" ++
       "      | false => 2\n" ++
       "      | true => 1\n"))
    "arm order must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-count-a"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n"))
    (← decodeSource session "non-alias-count-b"
      ("    return\n" ++
       "      match x with\n" ++
       "      | _ => 0\n" ++
       "      | _ => 1\n"))
    "arm count must be hash-bound"

  -- Match expression must not become a binary/unary operand without grouping.
  expectReject session "binary-operand"
    ("    return\n" ++
     "      x + match y with\n" ++
     "            | _ => 1\n")
    "failed to parse file"
  expectReject session "unary-operand"
    ("    return\n" ++
     "      - match y with\n" ++
     "        | _ => 1\n")
    "failed to parse file"

  -- Statement/expr arm categories are strictly separated.
  expectReject session "do-in-expression-arm"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => do\n" ++
     "        return 0\n")
    "failed to parse file"
  expectReject session "missing-with"
    ("    return\n" ++
     "      match x\n" ++
     "      | _ => 0\n")
    "failed to parse file"
  expectReject session "missing-bar"
    ("    return\n" ++
     "      match x with\n" ++
     "        _ => 0\n")
    "failed to parse file"
  expectReject session "missing-arrow"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ 0\n")
    "failed to parse file"
  expectReject session "zero-arms"
    ("    return\n" ++
     "      match x with\n")
    "failed to parse file"
  expectReject session "empty-arm-value"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ =>\n")
    "failed to parse file"
  expectReject session "trailing-payload"
    ("    return\n" ++
     "      match x with extra\n" ++
     "      | _ => 0\n")
    "failed to parse file"
  expectReject session "misaligned-arm"
    ("    return\n" ++
     "      match x with\n" ++
     "        | _ => 0\n")
    "failed to parse file"

  -- Expression match is not a place: it cannot take suffixes or be an assignment target.
  expectReject session "match-as-assignment-target"
    ("    match x with\n" ++
     "    | _ => 0 := 1\n")
    "failed to parse file"
  expectReject session "match-with-place-suffix"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => 0 .field\n")
    "failed to parse file"

  -- Error priority: scrutinee before arms.
  expectReject session "scrutinee-before-arms"
    ("    return\n" ++
     "      match «if» with\n" ++
     "      | _ => «let»\n")
    "reserved portable identifier 'if'"
  -- Earlier arm pattern before its value before later arms.
  expectReject session "pattern-before-value-before-later"
    ("    return\n" ++
     "      match x with\n" ++
     "      | «let» => «if»\n" ++
     "      | _ => 0\n")
    "reserved portable identifier 'let'"
  -- First arm value before second arm pattern.
  expectReject session "value-before-later-arm"
    ("    return\n" ++
     "      match x with\n" ++
     "      | _ => «if»\n" ++
     "      | «let» => 0\n")
    "reserved portable identifier 'if'"


end Tests.Language.ProgramV1MatchExpressions
