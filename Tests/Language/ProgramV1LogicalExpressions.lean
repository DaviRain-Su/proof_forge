import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1LogicalExpressions

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
  "program LogicalExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, flag : Bool, other : Bool, third : Bool, «raw.with.dot» : Bool) : Bool do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-logical-expressions-" ++ label ++ ">")
      "Tests.ProgramV1LogicalExpressions" none with
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
      ("<program-v1-logical-negative-" ++ label ++ ">")
      "Tests.ProgramV1LogicalExpressions" none with
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
      ("logical-and", BinaryOpV1.logicalAnd, "flag && true"),
      ("logical-or", BinaryOpV1.logicalOr, "flag || false")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    expectPlaceName lhs "flag" s!"{label}: lhs source order or raw place identity changed"
    match label with
    | "logical-and" => expectBool rhs true s!"{label}: rhs source order or Bool identity changed"
    | _ => expectBool rhs false s!"{label}: rhs source order or Bool identity changed"

  let (reverseLhs, reverseRhs) ← expectBinary
    (← decodeReturnExpr session "logical-or-source-order" "false || flag") .logicalOr
    "logical-or must preserve lhs/rhs source order"
  expectBool reverseLhs false "logical-or lhs Bool source order"
  expectPlaceName reverseRhs "flag" "logical-or rhs place source order"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» && other") .logicalAnd
    "whole escaped dotted place logical-and"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "other" "escaped-place rhs changed"
  let (escapedOrLhs, escapedOrRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place-logical-or" "«raw.with.dot» || other") .logicalOr
    "whole escaped dotted place logical-or"
  expectPlaceName escapedOrLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component for logical-or"
  expectPlaceName escapedOrRhs "other" "escaped-place logical-or rhs changed"

  let (andOuterLhs, andOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-logical-and" "flag && other && third") .logicalAnd
    "same-tier logical-and left associativity outer"
  let (andInnerLhs, andInnerRhs) ← expectBinary andOuterLhs .logicalAnd
    "same-tier logical-and left associativity inner"
  expectPlaceName andInnerLhs "flag" "left-assoc logical-and first operand"
  expectPlaceName andInnerRhs "other" "left-assoc logical-and second operand"
  expectPlaceName andOuterRhs "third" "left-assoc logical-and third operand"

  let (orOuterLhs, orOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-logical-or" "flag || other || third") .logicalOr
    "same-tier logical-or left associativity outer"
  let (orInnerLhs, orInnerRhs) ← expectBinary orOuterLhs .logicalOr
    "same-tier logical-or left associativity inner"
  expectPlaceName orInnerLhs "flag" "left-assoc logical-or first operand"
  expectPlaceName orInnerRhs "other" "left-assoc logical-or second operand"
  expectPlaceName orOuterRhs "third" "left-assoc logical-or third operand"

  let (groupAndLhs, groupAndRhs) ← expectBinary
    (← decodeReturnExpr session "right-nested-logical-and" "flag && (other && third)") .logicalAnd
    "grouping must allow explicit right-nested logical-and"
  expectPlaceName groupAndLhs "flag" "right-nested logical-and first operand"
  let (groupAndInnerLhs, groupAndInnerRhs) ← expectBinary groupAndRhs .logicalAnd
    "right-nested logical-and rhs"
  expectPlaceName groupAndInnerLhs "other" "right-nested logical-and second operand"
  expectPlaceName groupAndInnerRhs "third" "right-nested logical-and third operand"

  let (groupOrLhs, groupOrRhs) ← expectBinary
    (← decodeReturnExpr session "right-nested-logical-or" "flag || (other || third)") .logicalOr
    "grouping must allow explicit right-nested logical-or"
  expectPlaceName groupOrLhs "flag" "right-nested logical-or first operand"
  let (groupOrInnerLhs, groupOrInnerRhs) ← expectBinary groupOrRhs .logicalOr
    "right-nested logical-or rhs"
  expectPlaceName groupOrInnerLhs "other" "right-nested logical-or second operand"
  expectPlaceName groupOrInnerRhs "third" "right-nested logical-or third operand"

  let (fullTowerLhs, fullTowerRhs) ← expectBinary
    (← decodeReturnExpr session "full-precedence-tower"
      "1 < 2 & 3 == 4 ^ 5 <= 6 | 7 != 8 && !flag || other") .logicalOr
    "logical-or must be the loosest tier in the full precedence tower"
  let (logicalAndLhs, logicalAndRhs) ← expectBinary fullTowerLhs .logicalAnd
    "logical-and must bind above logical-or"
  let (orLhs, orRhs) ← expectBinary logicalAndLhs .bitOr
    "bit-or must bind above logical-and"
  let (xorLhs, xorRhs) ← expectBinary orLhs .bitXor
    "bit-xor must bind above bit-or"
  let (andLhs, andRhs) ← expectBinary xorLhs .bitAnd
    "bit-and must bind above bit-xor"
  let (ltLhs, ltRhs) ← expectBinary andLhs .lt
    "compare must bind above bit-and lhs"
  expectLiteral ltLhs 1 "full tower less-than lhs"
  expectLiteral ltRhs 2 "full tower less-than rhs"
  let (eqLhs, eqRhs) ← expectBinary andRhs .eq
    "compare/equality must bind above bit-and rhs"
  expectLiteral eqLhs 3 "full tower equality lhs"
  expectLiteral eqRhs 4 "full tower equality rhs"
  let (leLhs, leRhs) ← expectBinary xorRhs .le
    "compare must bind above bit-xor rhs"
  expectLiteral leLhs 5 "full tower less-equal lhs"
  expectLiteral leRhs 6 "full tower less-equal rhs"
  let (neLhs, neRhs) ← expectBinary orRhs .ne
    "compare/equality must bind above bit-or rhs"
  expectLiteral neLhs 7 "full tower not-equal lhs"
  expectLiteral neRhs 8 "full tower not-equal rhs"
  expectPlaceName (← expectUnary logicalAndRhs .not "full tower logical-and rhs unary") "flag"
    "logical-not unary child changed"
  expectPlaceName fullTowerRhs "other" "full tower logical-or rhs changed"

  let (shiftAddLhs, shiftAddRhs) ← expectBinary
    (← decodeReturnExpr session "higher-ops-over-logical" "-x + 2 * 3 << 1 < 9 && ~y != 0") .logicalAnd
    "unary/arithmetic/shift/compare tiers must bind above logical operators"
  let (compareLhs, compareRhs) ← expectBinary shiftAddLhs .lt
    "logical lhs comparison child"
  let (shiftChildLhs, shiftChildRhs) ← expectBinary compareLhs .shl
    "logical comparison lhs shift child"
  let (addChildLhs, addChildRhs) ← expectBinary shiftChildLhs .add
    "logical shift lhs additive child"
  expectPlaceName (← expectUnary addChildLhs .neg "higher ops unary lhs") "x"
    "higher ops unary place"
  let (mulChildLhs, mulChildRhs) ← expectBinary addChildRhs .mul
    "higher ops multiplicative child"
  expectLiteral mulChildLhs 2 "higher ops mul lhs"
  expectLiteral mulChildRhs 3 "higher ops mul rhs"
  expectLiteral shiftChildRhs 1 "higher ops shift rhs"
  expectLiteral compareRhs 9 "higher ops comparison rhs"
  let (neUnaryLhs, neUnaryRhs) ← expectBinary shiftAddRhs .ne
    "logical rhs comparison child"
  expectPlaceName (← expectUnary neUnaryLhs .bitNot "higher ops logical rhs unary") "y"
    "higher ops logical rhs place"
  expectLiteral neUnaryRhs 0 "higher ops logical rhs literal"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "flag && other || third")
    (← decodeSource session "redundant-b" "(((flag)) && ((other))) || (((third)))")
    "redundant grouping must preserve canonical identity"

  expectDifferentHash (← decodeSource session "non-alias-and" "flag && other")
    (← decodeSource session "non-alias-or" "flag || other")
    "operator tag logical-and/logical-or must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-bit-or" "flag | other")
    (← decodeSource session "non-alias-logical-or" "flag || other")
    "bit-or/logical-or operator token boundary must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "flag && other")
    (← decodeSource session "non-alias-order-b" "other && flag")
    "logical-and operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-or-order-a" "flag || other")
    (← decodeSource session "non-alias-or-order-b" "other || flag")
    "logical-or operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-assoc-a" "flag && other && third")
    (← decodeSource session "non-alias-assoc-b" "flag && (other && third)")
    "logical-and association tree must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-or-assoc-a" "flag || other || third")
    (← decodeSource session "non-alias-or-assoc-b" "flag || (other || third)")
    "logical-or association tree must be hash-bound"

  for (label, expr) in [
      ("missing-lhs-logical-and", "&& true"),
      ("missing-rhs-logical-and", "true &&"),
      ("missing-lhs-logical-or", "|| true"),
      ("missing-rhs-logical-or", "true ||"),
      ("spaced-double-ampersand", "true & & false"),
      ("spaced-double-pipe", "true | | false"),
      ("mixed-adjacent-logical-and-or", "true && || false"),
      ("mixed-adjacent-logical-or-and", "true || && false"),
      ("triple-ampersand-token", "true &&& false"),
      ("triple-pipe-token", "true ||| false"),
      ("parser-boundary", "true || false)")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "hostile-qualified-lhs" "A.x && «if»"
    "source name component must contain exactly one Lean Name component"
  expectReject session "hostile-reserved-lhs-before-rhs" "«if» && A.x"
    "reserved portable identifier 'if'"
  expectReject session "hostile-valid-lhs-before-rhs" "flag || A.y"
    "source name component must contain exactly one Lean Name component"

end Tests.Language.ProgramV1LogicalExpressions
