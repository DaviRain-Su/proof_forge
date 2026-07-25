import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1BitwiseExpressions

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
  "program BitwiseExpressions where\n" ++
  "  entry run(x : UInt64, y : UInt64, z : UInt64, flag : Bool, other : Bool, «raw.with.dot» : UInt64) : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source expr)
      ("<program-v1-bitwise-expressions-" ++ label ++ ">")
      "Tests.ProgramV1BitwiseExpressions" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeFullSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label fullSource : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 fullSource
      ("<program-v1-bitwise-full-" ++ label ++ ">")
      "Tests.ProgramV1BitwiseExpressions" none with
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
      ("<program-v1-bitwise-negative-" ++ label ++ ">")
      "Tests.ProgramV1BitwiseExpressions" none with
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

private def enumAndBitOrSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program EnumPipeCoexistence where\n" ++
  "  enum Choice where\n" ++
  "    | Left\n" ++
  "    | Right(UInt64)\n" ++
  "  entry run(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    return x | y\n"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  for (label, op, sourceExpr) in [
      ("bit-and", BinaryOpV1.bitAnd, "x & 1"),
      ("bit-xor", BinaryOpV1.bitXor, "x ^ 2"),
      ("bit-or", BinaryOpV1.bitOr, "x | 3")
    ] do
    let (lhs, rhs) ← expectBinary (← decodeReturnExpr session label sourceExpr) op label
    expectPlaceName lhs "x" s!"{label}: lhs source order or raw place identity changed"
    match label with
    | "bit-and" => expectLiteral rhs 1 s!"{label}: rhs source order or integer literal identity changed"
    | "bit-xor" => expectLiteral rhs 2 s!"{label}: rhs source order or integer literal identity changed"
    | _ => expectLiteral rhs 3 s!"{label}: rhs source order or integer literal identity changed"

  let (reverseLhs, reverseRhs) ← expectBinary
    (← decodeReturnExpr session "bit-or-source-order" "1 | x") .bitOr
    "bit-or must preserve lhs/rhs source order"
  expectLiteral reverseLhs 1 "bit-or lhs literal source order"
  expectPlaceName reverseRhs "x" "bit-or rhs place source order"

  let (escapedLhs, escapedRhs) ← expectBinary
    (← decodeReturnExpr session "escaped-place" "«raw.with.dot» & y") .bitAnd
    "whole escaped dotted place bitwise"
  expectPlaceName escapedLhs "raw.with.dot"
    "whole-escaped embedded-dot component must stay one raw place component"
  expectPlaceName escapedRhs "y" "escaped-place rhs changed"

  let (andOuterLhs, andOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-bit-and" "1 & 2 & 3") .bitAnd
    "same-tier bit-and left associativity outer"
  let (andInnerLhs, andInnerRhs) ← expectBinary andOuterLhs .bitAnd
    "same-tier bit-and left associativity inner"
  expectLiteral andInnerLhs 1 "left-assoc bit-and first operand"
  expectLiteral andInnerRhs 2 "left-assoc bit-and second operand"
  expectLiteral andOuterRhs 3 "left-assoc bit-and third operand"

  let (xorOuterLhs, xorOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-bit-xor" "1 ^ 2 ^ 3") .bitXor
    "same-tier bit-xor left associativity outer"
  let (xorInnerLhs, xorInnerRhs) ← expectBinary xorOuterLhs .bitXor
    "same-tier bit-xor left associativity inner"
  expectLiteral xorInnerLhs 1 "left-assoc bit-xor first operand"
  expectLiteral xorInnerRhs 2 "left-assoc bit-xor second operand"
  expectLiteral xorOuterRhs 3 "left-assoc bit-xor third operand"

  let (orOuterLhs, orOuterRhs) ← expectBinary
    (← decodeReturnExpr session "left-assoc-bit-or" "1 | 2 | 3") .bitOr
    "same-tier bit-or left associativity outer"
  let (orInnerLhs, orInnerRhs) ← expectBinary orOuterLhs .bitOr
    "same-tier bit-or left associativity inner"
  expectLiteral orInnerLhs 1 "left-assoc bit-or first operand"
  expectLiteral orInnerRhs 2 "left-assoc bit-or second operand"
  expectLiteral orOuterRhs 3 "left-assoc bit-or third operand"

  let (groupAndLhs, groupAndRhs) ← expectBinary
    (← decodeReturnExpr session "right-nested-bit-and" "1 & (2 & 3)") .bitAnd
    "grouping must allow explicit right-nested bit-and"
  expectLiteral groupAndLhs 1 "right-nested bit-and first operand"
  let (groupAndInnerLhs, groupAndInnerRhs) ← expectBinary groupAndRhs .bitAnd
    "right-nested bit-and rhs"
  expectLiteral groupAndInnerLhs 2 "right-nested bit-and second operand"
  expectLiteral groupAndInnerRhs 3 "right-nested bit-and third operand"

  let (compareOuterLhs, compareOuterRhs) ← expectBinary
    (← decodeReturnExpr session "compare-over-bit-and" "1 < 2 & 3 >= 4") .bitAnd
    "CompareExpr must bind above bit-and"
  let (compareLhsA, compareRhsA) ← expectBinary compareOuterLhs .lt
    "bit-and lhs comparison child"
  expectLiteral compareLhsA 1 "bit-and comparison lhs first operand"
  expectLiteral compareRhsA 2 "bit-and comparison lhs second operand"
  let (compareLhsB, compareRhsB) ← expectBinary compareOuterRhs .ge
    "bit-and rhs comparison child"
  expectLiteral compareLhsB 3 "bit-and comparison rhs first operand"
  expectLiteral compareRhsB 4 "bit-and comparison rhs second operand"

  let (bitAndOverXorLhs, bitAndOverXorRhs) ← expectBinary
    (← decodeReturnExpr session "bit-and-over-xor" "1 & 2 ^ 3 & 4") .bitXor
    "bit-and must bind above bit-xor"
  let (bitAndLeftLhs, bitAndLeftRhs) ← expectBinary bitAndOverXorLhs .bitAnd
    "bit-xor lhs bit-and child"
  expectLiteral bitAndLeftLhs 1 "bit-xor lhs first operand"
  expectLiteral bitAndLeftRhs 2 "bit-xor lhs second operand"
  let (bitAndRightLhs, bitAndRightRhs) ← expectBinary bitAndOverXorRhs .bitAnd
    "bit-xor rhs bit-and child"
  expectLiteral bitAndRightLhs 3 "bit-xor rhs first operand"
  expectLiteral bitAndRightRhs 4 "bit-xor rhs second operand"

  let (bitXorOverOrLhs, bitXorOverOrRhs) ← expectBinary
    (← decodeReturnExpr session "bit-xor-over-or" "1 ^ 2 | 3 ^ 4") .bitOr
    "bit-xor must bind above bit-or"
  let (bitXorLeftLhs, bitXorLeftRhs) ← expectBinary bitXorOverOrLhs .bitXor
    "bit-or lhs bit-xor child"
  expectLiteral bitXorLeftLhs 1 "bit-or lhs first operand"
  expectLiteral bitXorLeftRhs 2 "bit-or lhs second operand"
  let (bitXorRightLhs, bitXorRightRhs) ← expectBinary bitXorOverOrRhs .bitXor
    "bit-or rhs bit-xor child"
  expectLiteral bitXorRightLhs 3 "bit-or rhs first operand"
  expectLiteral bitXorRightRhs 4 "bit-or rhs second operand"

  let (shiftAddLhs, shiftAddRhs) ← expectBinary
    (← decodeReturnExpr session "higher-ops-over-bitwise" "-x + 2 * 3 << 1 & ~y") .bitAnd
    "unary/arithmetic/shift tiers must bind above bitwise"
  let (shiftChildLhs, shiftChildRhs) ← expectBinary shiftAddLhs .shl
    "bitwise lhs shift child"
  let (addChildLhs, addChildRhs) ← expectBinary shiftChildLhs .add
    "shift lhs additive child"
  expectPlaceName (← expectUnary addChildLhs .neg "higher ops unary lhs") "x"
    "higher ops unary place"
  let (mulChildLhs, mulChildRhs) ← expectBinary addChildRhs .mul
    "higher ops multiplicative child"
  expectLiteral mulChildLhs 2 "higher ops mul lhs"
  expectLiteral mulChildRhs 3 "higher ops mul rhs"
  expectLiteral shiftChildRhs 1 "higher ops shift rhs"
  expectPlaceName (← expectUnary shiftAddRhs .bitNot "higher ops bitwise rhs unary") "y"
    "higher ops bitwise rhs place"

  expectSameProgramBytesAndHash (← decodeSource session "redundant-a" "x & y ^ z | 1")
    (← decodeSource session "redundant-b" "(((x)) & ((y))) ^ (((z))) | ((1))")
    "redundant grouping must preserve canonical identity"

  expectDifferentHash (← decodeSource session "non-alias-and" "x & y")
    (← decodeSource session "non-alias-xor" "x ^ y")
    "operator tag bit-and/bit-xor must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-xor-tag" "x ^ y")
    (← decodeSource session "non-alias-or" "x | y")
    "operator tag bit-xor/bit-or must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-order-a" "x & y")
    (← decodeSource session "non-alias-order-b" "y & x")
    "operand order must be hash-bound"
  expectDifferentHash (← decodeSource session "non-alias-assoc-a" "x & y & z")
    (← decodeSource session "non-alias-assoc-b" "x & (y & z)")
    "association tree must be hash-bound"

  let enumFixture ← decodeFullSource session "enum-pipe-coexistence" enumAndBitOrSource
  match enumFixture.program.items[0]? with
  | some (ProgramItemV1.enum declaration) =>
      match declaration.variants.toList with
      | [left, right] =>
          expect (declaration.name.raw == "Choice" && left.name.raw == "Left" &&
              left.payloadTypes.isEmpty && right.name.raw == "Right" &&
              right.payloadTypes == #[.uint 64])
            "enum variant introducer pipes were reclassified"
      | variants => throw <| IO.userError s!"enum variants are incomplete: {repr variants}"
  | other => throw <| IO.userError s!"enum fixture item 0 is not enum: {repr other}"
  match enumFixture.program.items[1]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.return_ (some expr)] =>
          let (lhs, rhs) ← expectBinary expr .bitOr
            "expression pipe in enum fixture must decode as bit-or"
          expectPlaceName lhs "x" "enum fixture bit-or lhs"
          expectPlaceName rhs "y" "enum fixture bit-or rhs"
      | other => throw <| IO.userError s!"enum fixture entry body changed: {repr other}"
  | other => throw <| IO.userError s!"enum fixture item 1 is not entry: {repr other}"

  for (label, expr) in [
      ("missing-lhs-bit-and", "& 1"),
      ("missing-rhs-bit-and", "1 &"),
      ("missing-lhs-bit-xor", "^ 1"),
      ("missing-rhs-bit-xor", "1 ^"),
      ("missing-lhs-bit-or", "| 1"),
      ("missing-rhs-bit-or", "1 |"),
      ("spaced-double-ampersand", "1 & & 2"),
      ("spaced-double-pipe", "1 | | 2"),
      ("mixed-adjacent-bit-and-xor", "1 & ^ 2"),
      ("mixed-adjacent-bit-or-xor", "1 | ^ 2"),
      ("extra-payload", "1 & 2 3"),
      ("parser-boundary", "1 | 2)")
    ] do
    expectReject session label expr "failed to parse file"

  let (logicalAndLhs, logicalAndRhs) ← expectBinary
    (← decodeReturnExpr session "logical-and-token-boundary" "flag && other") .logicalAnd
    "&& must remain the logical-and token, not two bit-and tokens"
  expectPlaceName logicalAndLhs "flag" "logical-and lhs"
  expectPlaceName logicalAndRhs "other" "logical-and rhs"
  let (logicalOrLhs, logicalOrRhs) ← expectBinary
    (← decodeReturnExpr session "logical-or-token-boundary" "flag || other") .logicalOr
    "|| must remain the logical-or token, not two bit-or tokens"
  expectPlaceName logicalOrLhs "flag" "logical-or lhs"
  expectPlaceName logicalOrRhs "other" "logical-or rhs"

  expectReject session "hostile-qualified-lhs" "A.x & «if»"
    "source name component must contain exactly one Lean Name component"
  expectReject session "hostile-reserved-lhs-before-rhs" "«if» & A.x"
    "reserved portable identifier 'if'"
  expectReject session "hostile-valid-lhs-before-rhs" "x | A.y"
    "source name component must contain exactly one Lean Name component"

end Tests.Language.ProgramV1BitwiseExpressions
