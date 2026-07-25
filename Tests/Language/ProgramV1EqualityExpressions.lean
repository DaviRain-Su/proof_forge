import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1EqualityExpressions

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
  "program EqualityExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, flag : Bool, other : Bool, «raw.with.dot» : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-equality-expressions-" ++ label ++ ">")
      "Tests.ProgramV1EqualityExpressions" none with
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
      ("<program-v1-equality-negative-" ++ label ++ ">")
      "Tests.ProgramV1EqualityExpressions" none with
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
      ("eq", BinaryOpV1.eq, "x == 1"),
      ("ne", BinaryOpV1.ne, "x != 1")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    expectPlaceName lhs "x" s!"{label}: lhs source order or raw place identity changed"
    expectLiteral rhs 1 s!"{label}: rhs source order or integer literal identity changed"

  let (boolLhs, boolRhs) ← expectBinary
    (← decodeReturnExpr session "bool-identity" "flag == false") .eq
    "Bool equality"
  expectPlaceName boolLhs "flag" "Bool equality lhs place identity changed"
  expectBool boolRhs false "Bool equality rhs literal identity changed"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» != y") .ne
    "whole escaped dotted place equality"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "y" "escaped-place rhs changed"

  let (shiftLhs, shiftRhs) ← expectBinary
    (← decodeReturnExpr session "shift-over-eq" "1 << 2 == 4 >> 1") .eq
    "ShiftExpr must bind above equality"
  let (shlLhs, shlRhs) ← expectBinary shiftLhs .shl "equality lhs shift child"
  expectLiteral shlLhs 1 "equality shift lhs first operand"
  expectLiteral shlRhs 2 "equality shift lhs second operand"
  let (shrLhs, shrRhs) ← expectBinary shiftRhs .shr "equality rhs shift child"
  expectLiteral shrLhs 4 "equality shift rhs first operand"
  expectLiteral shrRhs 1 "equality shift rhs second operand"

  let (addMulLhs, addMulRhs) ← expectBinary
    (← decodeReturnExpr session "add-mul-over-ne" "1 + 2 * 3 != 7") .ne
    "AddExpr and MulExpr must bind above equality"
  let (addLhs, addRhs) ← expectBinary addMulLhs .add "equality lhs additive child"
  expectLiteral addLhs 1 "equality additive first operand"
  let (mulLhs, mulRhs) ← expectBinary addRhs .mul "equality lhs multiplicative child"
  expectLiteral mulLhs 2 "equality multiplicative first operand"
  expectLiteral mulRhs 3 "equality multiplicative second operand"
  expectLiteral addMulRhs 7 "equality rhs literal"

  let (unaryLhs, unaryRhs) ← expectBinary
    (← decodeReturnExpr session "unary-over-eq" "-x == !flag") .eq
    "UnaryExpr must bind above equality"
  expectPlaceName (← expectUnary unaryLhs .neg "unary-over-eq lhs") "x"
    "unary-over-eq lhs place"
  expectPlaceName (← expectUnary unaryRhs .not "unary-over-eq rhs") "flag"
    "unary-over-eq rhs place"

  let (groupOuterLhs, groupOuterRhs) ← expectBinary
    (← decodeReturnExpr session "grouped-compare-primary-lhs" "(1 == 2) != false") .ne
    "parenthesized comparison must be a PrimaryExpr lhs"
  let (groupInnerLhs, groupInnerRhs) ← expectBinary groupOuterLhs .eq
    "parenthesized comparison lhs tree"
  expectLiteral groupInnerLhs 1 "grouped comparison lhs first operand"
  expectLiteral groupInnerRhs 2 "grouped comparison lhs second operand"
  expectBool groupOuterRhs false "grouped comparison rhs Bool"

  let (groupRhsOuterLhs, groupRhsOuterRhs) ← expectBinary
    (← decodeReturnExpr session "grouped-compare-primary-rhs" "true == (1 != 2)") .eq
    "parenthesized comparison must be a PrimaryExpr rhs"
  expectBool groupRhsOuterLhs true "grouped comparison lhs Bool"
  let (groupRhsInnerLhs, groupRhsInnerRhs) ← expectBinary groupRhsOuterRhs .ne
    "parenthesized comparison rhs tree"
  expectLiteral groupRhsInnerLhs 1 "grouped rhs comparison first operand"
  expectLiteral groupRhsInnerRhs 2 "grouped rhs comparison second operand"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "x == 1 + 2")
    (← decodeSource session "redundant-b" "((x)) == (((1) + (2)))")
    "redundant grouping must preserve canonical identity"

  expectDifferentHash (← decodeSource session "non-alias-eq" "x == y")
    (← decodeSource session "non-alias-ne" "x != y")
    "operator tag eq/ne must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "x == y")
    (← decodeSource session "non-alias-order-b" "y == x")
    "operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-bool-a" "flag == true")
    (← decodeSource session "non-alias-bool-b" "flag == false")
    "Bool value must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-group-tree-a" "(1 == 2) != false")
    (← decodeSource session "non-alias-group-tree-b" "1 == (2 != false)")
    "different equality grouping trees must be hash-bound"

  for (label, expr) in [
      ("missing-lhs-eq", "== 1"),
      ("missing-rhs-eq", "1 =="),
      ("missing-lhs-ne", "!= 1"),
      ("missing-rhs-ne", "1 !="),
      ("single-equal-token", "1 = 2"),
      ("spaced-equal-token", "1 = = 2"),
      ("triple-equal-token", "1 === 2"),
      ("spaced-bang-equals-token", "1 ! = 2"),
      ("bang-equals-token", "1 !== 2"),
      ("same-eq-chain", "1 == 2 == 3"),
      ("same-ne-chain", "1 != 2 != 3"),
      ("mixed-eq-ne-chain", "1 == 2 != 3"),
      ("mixed-ne-eq-chain", "1 != 2 == 3"),
      ("extra-payload", "1 == 2 3"),
      ("parser-boundary", "1 == 2)")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "hostile-qualified-lhs" "A.x == «if»"
    "source name component must contain exactly one Lean Name component"
  expectReject session "hostile-reserved-lhs-before-rhs" "«if» == A.x"
    "reserved portable identifier 'if'"
  expectReject session "hostile-valid-lhs-before-rhs" "x == A.y"
    "source name component must contain exactly one Lean Name component"

end Tests.Language.ProgramV1EqualityExpressions
