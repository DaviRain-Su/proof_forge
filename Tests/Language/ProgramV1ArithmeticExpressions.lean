import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ArithmeticExpressions

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
  "program ArithmeticExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, «raw.with.dot» : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-arithmetic-expressions-" ++ label ++ ">")
      "Tests.ProgramV1ArithmeticExpressions" none with
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
      ("<program-v1-arithmetic-negative-" ++ label ++ ">")
      "Tests.ProgramV1ArithmeticExpressions" none with
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
      ("add", BinaryOpV1.add, "x + 1"),
      ("sub", BinaryOpV1.sub, "x - 1"),
      ("mul", BinaryOpV1.mul, "x * 1"),
      ("div", BinaryOpV1.div, "x / 1"),
      ("mod", BinaryOpV1.mod, "x % 1")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    expectPlaceName lhs "x" s!"{label}: lhs source order or raw place identity changed"
    expectLiteral rhs 1 s!"{label}: rhs source order or literal identity changed"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» + y") .add
    "whole escaped dotted place arithmetic"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "y" "escaped-place rhs changed"

  let (addOuterLhs, addOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-add" "1 + 2 + 3") .add
    "same-tier add left associativity outer"
  let (addInnerLhs, addInnerRhs) ← expectBinary addOuterLhs .add
    "same-tier add left associativity inner"
  expectLiteral addInnerLhs 1 "left-assoc add first operand"
  expectLiteral addInnerRhs 2 "left-assoc add second operand"
  expectLiteral addOuterRhs 3 "left-assoc add third operand"

  let (subOuterLhs, subOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-sub" "1 - 2 - 3") .sub
    "same-tier sub left associativity outer"
  let (subInnerLhs, subInnerRhs) ← expectBinary subOuterLhs .sub
    "same-tier sub left associativity inner"
  expectLiteral subInnerLhs 1 "left-assoc sub first operand"
  expectLiteral subInnerRhs 2 "left-assoc sub second operand"
  expectLiteral subOuterRhs 3 "left-assoc sub third operand"

  let (mulOuterLhs, mulOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-mul" "1 * 2 * 3") .mul
    "same-tier mul left associativity outer"
  let (mulInnerLhs, mulInnerRhs) ← expectBinary mulOuterLhs .mul
    "same-tier mul left associativity inner"
  expectLiteral mulInnerLhs 1 "left-assoc mul first operand"
  expectLiteral mulInnerRhs 2 "left-assoc mul second operand"
  expectLiteral mulOuterRhs 3 "left-assoc mul third operand"

  let (divOuterLhs, divOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-div" "8 / 4 / 2") .div
    "same-tier div left associativity outer"
  let (divInnerLhs, divInnerRhs) ← expectBinary divOuterLhs .div
    "same-tier div left associativity inner"
  expectLiteral divInnerLhs 8 "left-assoc div first operand"
  expectLiteral divInnerRhs 4 "left-assoc div second operand"
  expectLiteral divOuterRhs 2 "left-assoc div third operand"

  let (modOuterLhs, modOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-mod" "8 % 5 % 2") .mod
    "same-tier mod left associativity outer"
  let (modInnerLhs, modInnerRhs) ← expectBinary modOuterLhs .mod
    "same-tier mod left associativity inner"
  expectLiteral modInnerLhs 8 "left-assoc mod first operand"
  expectLiteral modInnerRhs 5 "left-assoc mod second operand"
  expectLiteral modOuterRhs 2 "left-assoc mod third operand"

  let (mixOuterLhs, mixOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-mul-div-mod" "1 * 2 / 3 % 4") .mod
    "mixed multiplicative left associativity outer"
  let (mixMidLhs, mixMidRhs) ← expectBinary mixOuterLhs .div
    "mixed multiplicative left associativity middle"
  let (mixInnerLhs, mixInnerRhs) ← expectBinary mixMidLhs .mul
    "mixed multiplicative left associativity inner"
  expectLiteral mixInnerLhs 1 "mixed chain first operand"
  expectLiteral mixInnerRhs 2 "mixed chain second operand"
  expectLiteral mixMidRhs 3 "mixed chain third operand"
  expectLiteral mixOuterRhs 4 "mixed chain fourth operand"

  let (precedenceAddLhs, precedenceAddRhs) ← expectBinary
    (← decodeReturnExpr session "mul-over-add" "1 + 2 * 3") .add
    "MulExpr must bind above AddExpr"
  expectLiteral precedenceAddLhs 1 "mul-over-add lhs"
  let (precedenceMulLhs, precedenceMulRhs) ← expectBinary precedenceAddRhs .mul
    "mul-over-add rhs"
  expectLiteral precedenceMulLhs 2 "mul-over-add multiplicative lhs"
  expectLiteral precedenceMulRhs 3 "mul-over-add multiplicative rhs"

  let (unaryMulLhs, unaryMulRhs) ← expectBinary
    (← decodeReturnExpr session "unary-over-mul" "-x * ~2") .mul
    "unary must bind above multiplicative"
  expectPlaceName (← expectUnary unaryMulLhs .neg "unary-over-mul lhs") "x"
    "unary-over-mul lhs place"
  expectLiteral (← expectUnary unaryMulRhs .bitNot "unary-over-mul rhs") 2
    "unary-over-mul rhs literal"

  let (groupOuterLhs, groupOuterRhs) ← expectBinary
    (← decodeReturnExpr session "grouping-override" "(1 + 2) * 3") .mul
    "grouping must override precedence"
  let (groupInnerLhs, groupInnerRhs) ← expectBinary groupOuterLhs .add
    "grouping override inner add"
  expectLiteral groupInnerLhs 1 "grouping override first operand"
  expectLiteral groupInnerRhs 2 "grouping override second operand"
  expectLiteral groupOuterRhs 3 "grouping override third operand"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "1 + 2 * 3")
    (← decodeSource session "redundant-b" "((1)) + (((2) * (3)))")
    "redundant grouping must preserve canonical identity"

  let (divZeroLhs, divZeroRhs) ← expectBinary
    (← decodeReturnExpr session "div-zero-source-ast" "x / 0") .div
    "division by zero stays Source AST"
  expectPlaceName divZeroLhs "x" "div-zero lhs"
  expectLiteral divZeroRhs 0 "div-zero rhs literal"
  let (modZeroLhs, modZeroRhs) ← expectBinary
    (← decodeReturnExpr session "mod-zero-source-ast" "x % 0") .mod
    "modulo by zero stays Source AST"
  expectPlaceName modZeroLhs "x" "mod-zero lhs"
  expectLiteral modZeroRhs 0 "mod-zero rhs literal"

  expectDifferentHash (← decodeSource session "non-alias-add" "x + y")
    (← decodeSource session "non-alias-sub" "x - y")
    "operator tag add/sub must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-sub-tag" "x - y")
    (← decodeSource session "non-alias-mul" "x * y")
    "operator tag sub/mul must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-mul-tag" "x * y")
    (← decodeSource session "non-alias-div" "x / y")
    "operator tag mul/div must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-div-tag" "x / y")
    (← decodeSource session "non-alias-mod" "x % y")
    "operator tag div/mod must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "x - y")
    (← decodeSource session "non-alias-order-b" "y - x")
    "operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-group-tree-a" "1 + 2 * 3")
    (← decodeSource session "non-alias-group-tree-b" "(1 + 2) * 3")
    "grouping tree must be hash-bound when it changes AST shape"

  -- `- 1` is intentionally a valid unary expression, so binary subtraction has no
  -- missing-lhs parser-negative spelling distinct from unary negation.
  for (label, expr) in [
      ("missing-lhs-add", "+ 1"),
      ("missing-rhs-add", "1 +"),
      ("missing-rhs-sub", "1 -"),
      ("missing-lhs-mul", "* 1"),
      ("missing-rhs-mul", "1 *"),
      ("missing-lhs-div", "/ 1"),
      ("missing-rhs-div", "1 /"),
      ("missing-lhs-mod", "% 1"),
      ("missing-rhs-mod", "1 %"),
      ("duplicate-add", "1 ++ 2"),
      ("duplicate-mul", "1 ** 2"),
      ("invalid-adjacent", "1 + * 2"),
      ("extra-payload", "1 + 2 3"),
      ("parser-boundary", "1 + 2)")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "invalid-field-lhs-before-rhs" "A.«return» + «if»"
    "reserved portable identifier 'return'"
  expectReject session "hostile-lhs-before-rhs" "«if» + A.x"
    "reserved portable identifier 'if'"
  expectReject session "valid-lhs-before-invalid-field-rhs" "x + A.«return»"
    "reserved portable identifier 'return'"

end Tests.Language.ProgramV1ArithmeticExpressions
