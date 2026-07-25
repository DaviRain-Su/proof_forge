import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1UnaryExpressions

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (expr : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program UnaryExpressions where\n" ++
  "  entry run(x : UInt64, flag : Bool, «raw.with.dot» : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-unary-expressions-" ++ label ++ ">")
      "Tests.ProgramV1UnaryExpressions" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeReturnExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ExprV1 := do
  let value ← decodeSource session label expr
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.return_ (some value)] => pure value
      | other => throw <| IO.userError s!"'{label}' did not decode one return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label expr expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-unary-expression-negative-" ++ label ++ ">")
      "Tests.ProgramV1UnaryExpressions" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def expectLiteral (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer literal, got {repr other}"

private def expectBool (expr : ExprV1) (expected : Bool) (label : String) : IO Unit :=
  match expr with
  | .literal (.bool value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected Bool literal, got {repr other}"

private def expectPlaceName (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) label
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

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

private def expectSameProgramAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program == right.program)
    s!"{label}: grouping changed ProgramV1 AST instead of only parse grouping"
  let leftBytes ← match canonicalValidatedSourceAstBytesV1 left with
    | .ok bytes => pure bytes
    | .error error => throw <| IO.userError s!"{label}: left canonical bytes failed: {error}"
  let rightBytes ← match canonicalValidatedSourceAstBytesV1 right with
    | .ok bytes => pure bytes
    | .error error => throw <| IO.userError s!"{label}: right canonical bytes failed: {error}"
  expect (leftBytes == rightBytes) s!"{label}: grouping changed canonical ProgramV1 bytes"
  let leftHash ← match sourceHashV1 left with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"{label}: left sourceHashV1 failed: {error}"
  let rightHash ← match sourceHashV1 right with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"{label}: right sourceHashV1 failed: {error}"
  expect (leftHash == rightHash) s!"{label}: grouping changed sourceHashV1"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  expectLiteral (← expectUnary (← decodeReturnExpr session "neg-literal" "-2") .neg
    "neg literal") 2 "neg literal operand"
  expectLiteral (← expectUnary (← decodeReturnExpr session "bitnot-literal" "~2") .bitNot
    "bitNot literal") 2 "bitNot literal operand"
  expectBool (← expectUnary (← decodeReturnExpr session "not-bool" "!true") .not
    "not Bool literal") true "not Bool operand"
  expectPlaceName (← expectUnary (← decodeReturnExpr session "not-place" "!flag") .not
    "not Bool place") "flag" "not Bool place operand"
  expectPlaceName (← expectUnary (← decodeReturnExpr session "neg-escaped-place" "-«raw.with.dot»")
    .neg "neg escaped dotted place") "raw.with.dot"
    "whole-escaped dotted raw component must remain one place component"

  let nestedNeg ← expectUnary (← decodeReturnExpr session "nested-neg" "- -2") .neg
    "nested neg outer"
  expectLiteral (← expectUnary nestedNeg .neg "nested neg inner") 2 "nested neg operand"
  let nestedBitNot ← expectUnary (← decodeReturnExpr session "nested-bitnot" "~~2") .bitNot
    "nested bitNot outer"
  expectLiteral (← expectUnary nestedBitNot .bitNot "nested bitNot inner") 2
    "nested bitNot operand"
  let nestedNot ← expectUnary (← decodeReturnExpr session "nested-not" "!!flag") .not
    "nested not outer"
  expectPlaceName (← expectUnary nestedNot .not "nested not inner") "flag"
    "nested not operand"
  let mixedNegBit ← expectUnary (← decodeReturnExpr session "mixed-neg-bitnot" "- ~2") .neg
    "mixed -~ outer"
  expectLiteral (← expectUnary mixedNegBit .bitNot "mixed -~ inner") 2
    "mixed -~ operand"
  let mixedBitNeg ← expectUnary (← decodeReturnExpr session "mixed-bitnot-neg" "~ -2") .bitNot
    "mixed ~- outer"
  expectLiteral (← expectUnary mixedBitNeg .neg "mixed ~- inner") 2
    "mixed ~- operand"
  let mixedNegNot ← expectUnary (← decodeReturnExpr session "mixed-neg-not" "- !flag") .neg
    "mixed -! outer"
  expectPlaceName (← expectUnary mixedNegNot .not "mixed -! inner") "flag"
    "mixed -! operand"
  let mixedNotNeg ← expectUnary (← decodeReturnExpr session "mixed-not-neg" "! -2") .not
    "mixed !- outer"
  expectLiteral (← expectUnary mixedNotNeg .neg "mixed !- inner") 2
    "mixed !- operand"
  let mixedBitNot ← expectUnary (← decodeReturnExpr session "mixed-bit-not" "~ !flag") .bitNot
    "mixed ~! outer"
  expectPlaceName (← expectUnary mixedBitNot .not "mixed ~! inner") "flag"
    "mixed ~! operand"
  let mixedNotBit ← expectUnary (← decodeReturnExpr session "mixed-not-bitnot" "! ~2") .not
    "mixed !~ outer"
  expectLiteral (← expectUnary mixedNotBit .bitNot "mixed !~ inner") 2
    "mixed !~ operand"

  let (mulLhs, mulRhs) ← expectBinary (← decodeReturnExpr session "precedence-mul" "-2 * 3")
    .mul "unary before mul"
  expectLiteral (← expectUnary mulLhs .neg "unary before mul lhs") 2
    "unary before mul operand"
  expectLiteral mulRhs 3 "unary before mul rhs"
  let (addLhs, addRhs) ← expectBinary (← decodeReturnExpr session "precedence-add" "1 + ~2")
    .add "unary as add rhs"
  expectLiteral addLhs 1 "unary add lhs"
  expectLiteral (← expectUnary addRhs .bitNot "unary add rhs") 2 "unary add rhs operand"
  let (subLhs, subRhs) ← expectBinary (← decodeReturnExpr session "precedence-sub" "1 - -2")
    .sub "unary as binary-sub rhs"
  expectLiteral subLhs 1 "unary sub lhs"
  expectLiteral (← expectUnary subRhs .neg "unary sub rhs") 2 "unary sub rhs operand"
  let groupedMul ← decodeReturnExpr session "grouped-precedence" "-(1 + 2) * 3"
  let (groupMulLhs, groupMulRhs) ← expectBinary groupedMul .mul "grouped unary before mul"
  let groupedUnaryOperand ← expectUnary groupMulLhs .neg "grouped unary operand"
  let (innerAddLhs, innerAddRhs) ← expectBinary groupedUnaryOperand .add "grouped inner add"
  expectLiteral innerAddLhs 1 "grouped add lhs"
  expectLiteral innerAddRhs 2 "grouped add rhs"
  expectLiteral groupMulRhs 3 "grouped mul rhs"

  expectSameProgramAndHash (← decodeSource session "group-literal-a" "-2")
    (← decodeSource session "group-literal-b" "(-2)") "outer grouping on unary literal"
  expectSameProgramAndHash (← decodeSource session "group-place-a" "!flag")
    (← decodeSource session "group-place-b" "((!flag))") "nested grouping on unary place"
  expectSameProgramAndHash (← decodeSource session "group-precedence-a" "-(1 + 2)")
    (← decodeSource session "group-precedence-b" "-((1 + 2))")
    "grouping must preserve canonical ProgramV1 identity and sourceHashV1"

  for (label, expr) in [
      ("bare-neg", "-"),
      ("bare-bitnot", "~"),
      ("bare-not", "!"),
      ("missing-neg-group", "-()"),
      ("missing-bitnot-group", "~()"),
      ("missing-not-group", "!()"),
      ("empty-group", "()"),
      ("invalid-neg-star", "-*2"),
      ("invalid-bitnot-plus", "~+2"),
      ("invalid-not-star", "!*2"),
      ("extra-payload-neg", "-2 3"),
      ("extra-payload-bitnot", "~2 3"),
      ("extra-payload-not", "!true false"),
      ("bang-equals-split", "! = 2")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "invalid-field-neg-child" "-A.«return»"
    "reserved portable identifier 'return'"
  expectReject session "reserved-not-child" "!«if»"
    "reserved portable identifier 'if'"
  expectReject session "nested-child-left-first" "-(A.«return» + «if»)"
    "reserved portable identifier 'return'"
  expectReject session "nested-child-left-before-right" "!(«if» + A.x)"
    "reserved portable identifier 'if'"

end Tests.Language.ProgramV1UnaryExpressions
