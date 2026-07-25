import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1OrderingComparisons

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
  "program OrderingComparisons where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, flag : Bool, other : Bool, «raw.with.dot» : UInt64) : Bool do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-ordering-comparisons-" ++ label ++ ">")
      "Tests.ProgramV1OrderingComparisons" none with
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
      ("<program-v1-ordering-negative-" ++ label ++ ">")
      "Tests.ProgramV1OrderingComparisons" none with
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

private def expectDifferentHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect ((← sourceHash left (label ++ " left")) !=
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 unexpectedly aliased"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  for (label, op, sourceExpr) in [
      ("lt", BinaryOpV1.lt, "x < 1"),
      ("le", BinaryOpV1.le, "x <= 2"),
      ("gt", BinaryOpV1.gt, "x > 3"),
      ("ge", BinaryOpV1.ge, "x >= 4")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    expectPlaceName lhs "x" s!"{label}: lhs source order or raw place identity changed"
    match label with
    | "lt" => expectLiteral rhs 1 s!"{label}: rhs source order or integer literal identity changed"
    | "le" => expectLiteral rhs 2 s!"{label}: rhs source order or integer literal identity changed"
    | "gt" => expectLiteral rhs 3 s!"{label}: rhs source order or integer literal identity changed"
    | _ => expectLiteral rhs 4 s!"{label}: rhs source order or integer literal identity changed"

  let (reverseLhs, reverseRhs) ← expectBinary
    (← decodeReturnExpr session "gt-source-order" "1 > x") .gt
    "greater-than must preserve lhs/rhs source order"
  expectLiteral reverseLhs 1 "greater-than lhs literal source order"
  expectPlaceName reverseRhs "x" "greater-than rhs place source order"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» <= y") .le
    "whole escaped dotted place ordering"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "y" "escaped-place rhs changed"

  let (shiftLhs, shiftRhs) ← expectBinary
    (← decodeReturnExpr session "shift-over-lt" "1 << 2 < 4 >> 1") .lt
    "ShiftExpr must bind above ordering comparisons"
  let (shlLhs, shlRhs) ← expectBinary shiftLhs .shl "ordering lhs shift child"
  expectLiteral shlLhs 1 "ordering shift lhs first operand"
  expectLiteral shlRhs 2 "ordering shift lhs second operand"
  let (shrLhs, shrRhs) ← expectBinary shiftRhs .shr "ordering rhs shift child"
  expectLiteral shrLhs 4 "ordering shift rhs first operand"
  expectLiteral shrRhs 1 "ordering shift rhs second operand"

  let (addMulLhs, addMulRhs) ← expectBinary
    (← decodeReturnExpr session "add-mul-over-ge" "1 + 2 * 3 >= 7") .ge
    "AddExpr and MulExpr must bind above ordering comparisons"
  let (addLhs, addRhs) ← expectBinary addMulLhs .add "ordering lhs additive child"
  expectLiteral addLhs 1 "ordering additive first operand"
  let (mulLhs, mulRhs) ← expectBinary addRhs .mul "ordering lhs multiplicative child"
  expectLiteral mulLhs 2 "ordering multiplicative first operand"
  expectLiteral mulRhs 3 "ordering multiplicative second operand"
  expectLiteral addMulRhs 7 "ordering rhs literal"

  let (unaryLhs, unaryRhs) ← expectBinary
    (← decodeReturnExpr session "unary-over-gt" "-x > ~2") .gt
    "UnaryExpr must bind above ordering comparisons"
  expectPlaceName (← expectUnary unaryLhs .neg "unary-over-gt lhs") "x"
    "unary-over-gt lhs place"
  expectLiteral (← expectUnary unaryRhs .bitNot "unary-over-gt rhs") 2
    "unary-over-gt rhs literal"

  let (groupOuterLhs, groupOuterRhs) ← expectBinary
    (← decodeReturnExpr session "grouped-ordering-primary-lhs" "(1 < 2) == true") .eq
    "parenthesized ordering comparison must be a PrimaryExpr lhs"
  let (groupInnerLhs, groupInnerRhs) ← expectBinary groupOuterLhs .lt
    "parenthesized ordering lhs tree"
  expectLiteral groupInnerLhs 1 "grouped ordering lhs first operand"
  expectLiteral groupInnerRhs 2 "grouped ordering lhs second operand"
  expectBool groupOuterRhs true "grouped ordering rhs Bool"

  let (groupRhsOuterLhs, groupRhsOuterRhs) ← expectBinary
    (← decodeReturnExpr session "grouped-ordering-primary-rhs" "false != (3 >= 2)") .ne
    "parenthesized ordering comparison must be a PrimaryExpr rhs"
  expectBool groupRhsOuterLhs false "grouped ordering lhs Bool"
  let (groupRhsInnerLhs, groupRhsInnerRhs) ← expectBinary groupRhsOuterRhs .ge
    "parenthesized ordering rhs tree"
  expectLiteral groupRhsInnerLhs 3 "grouped rhs ordering first operand"
  expectLiteral groupRhsInnerRhs 2 "grouped rhs ordering second operand"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "x < 1 + 2")
    (← decodeSource session "redundant-b" "((x)) < (((1) + (2)))")
    "redundant grouping must preserve canonical identity"

  expectDifferentHash (← decodeSource session "non-alias-lt" "x < y")
    (← decodeSource session "non-alias-le" "x <= y")
    "operator tag lt/le must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-gt" "x > y")
    (← decodeSource session "non-alias-ge" "x >= y")
    "operator tag gt/ge must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "x < y")
    (← decodeSource session "non-alias-order-b" "y < x")
    "operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-equality-ordering" "x == y")
    (← decodeSource session "non-alias-ordering-equality" "x < y")
    "shared comparison tier operator tags must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-group-tree-a" "(1 < 2) == true")
    (← decodeSource session "non-alias-group-tree-b" "1 < (2 == true)")
    "different comparison grouping trees must be hash-bound"

  for (label, expr) in [
      ("missing-lhs-lt", "< 1"),
      ("missing-rhs-lt", "1 <"),
      ("missing-lhs-le", "<= 1"),
      ("missing-rhs-le", "1 <="),
      ("missing-lhs-gt", "> 1"),
      ("missing-rhs-gt", "1 >"),
      ("missing-lhs-ge", ">= 1"),
      ("missing-rhs-ge", "1 >="),
      ("spaced-less-equal-token", "1 < = 2"),
      ("spaced-greater-equal-token", "1 > = 2"),
      ("triple-less-token", "1 <<< 2"),
      ("triple-greater-token", "1 >>> 2"),
      ("adjacent-less-greater", "1 < > 2"),
      ("adjacent-greater-less", "1 > < 2"),
      ("same-lt-chain", "1 < 2 < 3"),
      ("same-le-chain", "1 <= 2 <= 3"),
      ("same-gt-chain", "1 > 2 > 3"),
      ("same-ge-chain", "1 >= 2 >= 3"),
      ("mixed-ordering-chain", "1 < 2 >= 3"),
      ("order-eq-chain", "1 < 2 == 3"),
      ("eq-order-chain", "1 == 2 < 3"),
      ("order-ne-chain", "1 <= 2 != 3"),
      ("ne-order-chain", "1 != 2 >= 3"),
      ("extra-payload", "1 < 2 3"),
      ("parser-boundary", "1 < 2)")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "hostile-qualified-lhs" "A.x < «if»"
    "source name component must contain exactly one Lean Name component"
  expectReject session "hostile-reserved-lhs-before-rhs" "«if» < A.x"
    "reserved portable identifier 'if'"
  expectReject session "hostile-valid-lhs-before-rhs" "x < A.y"
    "source name component must contain exactly one Lean Name component"

end Tests.Language.ProgramV1OrderingComparisons
