import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ShiftExpressions

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
  "program ShiftExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, flag : Bool, «raw.with.dot» : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-shift-expressions-" ++ label ++ ">")
      "Tests.ProgramV1ShiftExpressions" none with
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
      ("<program-v1-shift-negative-" ++ label ++ ">")
      "Tests.ProgramV1ShiftExpressions" none with
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
      ("shl", BinaryOpV1.shl, "x << 1"),
      ("shr", BinaryOpV1.shr, "y >> 0")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    if label == "shl" then
      expectPlaceName lhs "x" s!"{label}: lhs source order or raw place identity changed"
      expectLiteral rhs 1 s!"{label}: rhs source order or literal identity changed"
    else
      expectPlaceName lhs "y" s!"{label}: lhs source order or raw place identity changed"
      expectLiteral rhs 0 s!"{label}: rhs source order or literal identity changed"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» << y") .shl
    "whole escaped dotted place shift"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "y" "escaped-place rhs changed"

  let (shlOuterLhs, shlOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-shl" "1 << 2 << 3") .shl
    "same-operator shl left associativity outer"
  let (shlInnerLhs, shlInnerRhs) ← expectBinary shlOuterLhs .shl
    "same-operator shl left associativity inner"
  expectLiteral shlInnerLhs 1 "left-assoc shl first operand"
  expectLiteral shlInnerRhs 2 "left-assoc shl second operand"
  expectLiteral shlOuterRhs 3 "left-assoc shl third operand"

  let (shrOuterLhs, shrOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-shr" "8 >> 2 >> 1") .shr
    "same-operator shr left associativity outer"
  let (shrInnerLhs, shrInnerRhs) ← expectBinary shrOuterLhs .shr
    "same-operator shr left associativity inner"
  expectLiteral shrInnerLhs 8 "left-assoc shr first operand"
  expectLiteral shrInnerRhs 2 "left-assoc shr second operand"
  expectLiteral shrOuterRhs 1 "left-assoc shr third operand"

  let (crossRightOuterLhs, crossRightOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-shl-shr" "1 << 2 >> 3") .shr
    "cross-operator shift left associativity outer"
  let (crossRightInnerLhs, crossRightInnerRhs) ← expectBinary crossRightOuterLhs .shl
    "cross-operator shift left associativity inner"
  expectLiteral crossRightInnerLhs 1 "cross shift first operand"
  expectLiteral crossRightInnerRhs 2 "cross shift second operand"
  expectLiteral crossRightOuterRhs 3 "cross shift third operand"

  let (crossLeftOuterLhs, crossLeftOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-shr-shl" "8 >> 2 << 1") .shl
    "cross-operator reverse shift left associativity outer"
  let (crossLeftInnerLhs, crossLeftInnerRhs) ← expectBinary crossLeftOuterLhs .shr
    "cross-operator reverse shift left associativity inner"
  expectLiteral crossLeftInnerLhs 8 "reverse cross shift first operand"
  expectLiteral crossLeftInnerRhs 2 "reverse cross shift second operand"
  expectLiteral crossLeftOuterRhs 1 "reverse cross shift third operand"

  let (addMulLhs, addMulRhs) ← expectBinary
    (← decodeReturnExpr session "add-mul-over-shift" "1 + 2 << 3 * 4") .shl
    "AddExpr and MulExpr must bind above ShiftExpr"
  let (addLhs, addRhs) ← expectBinary addMulLhs .add "shift lhs additive child"
  expectLiteral addLhs 1 "shift additive first operand"
  expectLiteral addRhs 2 "shift additive second operand"
  let (mulLhs, mulRhs) ← expectBinary addMulRhs .mul "shift rhs multiplicative child"
  expectLiteral mulLhs 3 "shift multiplicative first operand"
  expectLiteral mulRhs 4 "shift multiplicative second operand"

  let (unaryLhs, unaryRhs) ← expectBinary
    (← decodeReturnExpr session "unary-over-shift" "-x << ~2") .shl
    "UnaryExpr must bind above ShiftExpr"
  expectPlaceName (← expectUnary unaryLhs .neg "unary-over-shift lhs") "x"
    "unary-over-shift lhs place"
  expectLiteral (← expectUnary unaryRhs .bitNot "unary-over-shift rhs") 2
    "unary-over-shift rhs literal"

  let (groupRightLhs, groupRightRhs) ← expectBinary
    (← decodeReturnExpr session "grouping-override-rhs" "1 << (2 >> 3)") .shl
    "grouping must override same-tier left associativity"
  expectLiteral groupRightLhs 1 "grouping override rhs first operand"
  let (groupRightInnerLhs, groupRightInnerRhs) ← expectBinary groupRightRhs .shr
    "grouping override rhs inner shift"
  expectLiteral groupRightInnerLhs 2 "grouping override rhs second operand"
  expectLiteral groupRightInnerRhs 3 "grouping override rhs third operand"

  let (groupAddLhs, groupAddRhs) ← expectBinary
    (← decodeReturnExpr session "grouping-override-precedence" "(1 << 2) + 3") .add
    "grouping must override ShiftExpr/AddExpr precedence"
  let (groupAddInnerLhs, groupAddInnerRhs) ← expectBinary groupAddLhs .shl
    "grouping override precedence inner shift"
  expectLiteral groupAddInnerLhs 1 "grouping precedence first operand"
  expectLiteral groupAddInnerRhs 2 "grouping precedence second operand"
  expectLiteral groupAddRhs 3 "grouping precedence third operand"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "x << 1 + 2")
    (← decodeSource session "redundant-b" "((x)) << (((1) + (2)))")
    "redundant grouping must preserve canonical identity"

  let (zeroLhs, zeroRhs) ← expectBinary
    (← decodeReturnExpr session "shift-count-zero-source-ast" "x << 0") .shl
    "shift count zero stays Source AST"
  expectPlaceName zeroLhs "x" "shift count zero lhs"
  expectLiteral zeroRhs 0 "shift count zero rhs literal"
  let (sixtyFourLhs, sixtyFourRhs) ← expectBinary
    (← decodeReturnExpr session "shift-count-64-source-ast" "x >> 64") .shr
    "shift count 64 stays Source AST"
  expectPlaceName sixtyFourLhs "x" "shift count 64 lhs"
  expectLiteral sixtyFourRhs 64 "shift count 64 rhs literal"

  expectDifferentHash (← decodeSource session "non-alias-shl" "x << y")
    (← decodeSource session "non-alias-shr" "x >> y")
    "operator tag shl/shr must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "x << y")
    (← decodeSource session "non-alias-order-b" "y << x")
    "operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-group-tree-a" "1 << 2 + 3")
    (← decodeSource session "non-alias-group-tree-b" "(1 << 2) + 3")
    "grouping tree must be hash-bound when it changes AST shape"

  for (label, expr) in [
      ("missing-lhs-shl", "<< 1"),
      ("missing-rhs-shl", "1 <<"),
      ("missing-lhs-shr", ">> 1"),
      ("missing-rhs-shr", "1 >>"),
      ("spaced-angle-left", "1 < < 2"),
      ("spaced-angle-right", "1 > > 2"),
      ("triple-angle-left", "1 <<< 2"),
      ("triple-angle-right", "1 >>> 2"),
      ("invalid-adjacent-shl-shr", "1 << >> 2"),
      ("invalid-adjacent-shl-mul", "1 << * 2"),
      ("extra-payload", "1 << 2 3"),
      ("parser-boundary", "1 << 2)")
    ] do
    expectReject session label expr "failed to parse file"

  expectReject session "invalid-field-lhs-before-rhs" "A.«return» << «if»"
    "reserved portable identifier 'return'"
  expectReject session "hostile-reserved-lhs-before-rhs" "«if» << A.x"
    "reserved portable identifier 'if'"
  expectReject session "valid-lhs-before-invalid-field-rhs" "x << A.«return»"
    "reserved portable identifier 'return'"

end Tests.Language.ProgramV1ShiftExpressions
