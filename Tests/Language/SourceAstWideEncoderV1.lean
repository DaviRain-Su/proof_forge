import ProofForgeV2.Source.AstPatternCodecV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstSpineCodecV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstWideEncoderV1

open ProofForgeV2.Source.AstPatternCodecV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineCodecV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: {detail}"

private def expectError (label expected : String) (result : Except String α) : IO Unit :=
  match result with
  | .error detail => expect (detail == expected) s!"{label}: expected {expected}, got {detail}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectBytes (label : String) (expected : ByteArray)
    (result : Except String ByteArray) : IO Unit := do
  let actual ← lift label result
  expect (actual == expected) s!"{label}: canonical bytes differ"

private def u16 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256)]

private def u32 (value : Nat) : ByteArray :=
  ByteArray.mk #[UInt8.ofNat value, UInt8.ofNat (value / 256),
    UInt8.ofNat (value / 65536), UInt8.ofNat (value / 16777216)]

private def stringBytes (value : String) : ByteArray :=
  u32 value.utf8ByteSize ++ value.toUTF8

private def tagged (tag : String) (fields : Array ByteArray) : ByteArray :=
  stringBytes tag ++ u16 fields.size ++ fields.foldl (· ++ ·) ByteArray.empty

private def nameArray (values : Array String) : ByteArray :=
  u32 values.size ++ values.foldl (fun output value => output ++ stringBytes value) ByteArray.empty

private def repeatBytes (chunk : ByteArray) (count : Nat) : ByteArray := Id.run do
  let mut output := ByteArray.emptyWithCapacity (chunk.size * count)
  for _ in [:count] do
    output := output ++ chunk
  pure output

private def qn (values : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 values)

private def name (value : String) : IO SourceNameComponentV1 :=
  lift value (parseSourceNameComponentV1 value)

/-- Frozen D1-PA-119: 5 wide exact-byte positives and 10 ordered dual-fault negatives. -/
def run : IO Unit := do
  let goodQid ← qn #["Option", "some"]
  let badQid ← qn #["Only"]
  let binder ← name "i"
  let qidBytes := nameArray #["Option", "some"]
  let wildcardBytes := tagged "Pattern.Wildcard" #[]
  let boolLiteralBytes := tagged "Literal.Bool" #[ByteArray.mk #[1]]
  let boolExprBytes := tagged "Expr.Literal" #[boolLiteralBytes]
  let returnNoneBytes := tagged "Stmt.Return" #[ByteArray.mk #[0]]
  let oneReturnBlockBytes := tagged "Block" #[u32 1 ++ returnNoneBytes]
  let exprArmBytes := tagged "ExprMatchArm" #[wildcardBytes, boolExprBytes]
  let stmtArmBytes := tagged "StmtMatchArm" #[wildcardBytes, oneReturnBlockBytes]
  let boolExpr : ExprV1 := .literal (.bool true)
  let returnNone : StmtV1 := .return_ none
  let oneReturnBlock : BlockV1 := { statements := #[returnNone] }

  let patterns : Array PatternV1 := Array.replicate 99999 .wildcard
  let expectedPatterns := tagged "Pattern.Constructor" #[qidBytes,
    u32 patterns.size ++ repeatBytes wildcardBytes patterns.size]
  expectBytes "wide-pattern-100000" expectedPatterns
    (encodePatternV1 (.constructor goodQid patterns))

  let expressions : Array ExprV1 := Array.replicate 99999 boolExpr
  let expectedExpressions := tagged "Expr.Constructor" #[qidBytes,
    u32 expressions.size ++ repeatBytes boolExprBytes expressions.size]
  expectBytes "wide-expr-100000" expectedExpressions
    (encodeExprV1 (.constructor goodQid expressions))

  let exprArm : ExprMatchArmV1 := { pattern := .wildcard, value := boolExpr }
  let exprArms : Array ExprMatchArmV1 := Array.replicate 33332 exprArm
  let expectedExprMatch := tagged "Expr.Match" #[boolExprBytes,
    u32 exprArms.size ++ repeatBytes exprArmBytes exprArms.size]
  expectBytes "wide-expr-arms-99998" expectedExprMatch
    (encodeExprV1 (.match_ boolExpr exprArms))

  let stmtArm : StmtMatchArmV1 := { pattern := .wildcard, body := oneReturnBlock }
  let stmtArms : Array StmtMatchArmV1 := Array.replicate 24999 stmtArm
  let expectedStmtMatch := tagged "Stmt.Match" #[boolExprBytes,
    u32 stmtArms.size ++ repeatBytes stmtArmBytes stmtArms.size]
  expectBytes "wide-stmt-arms-99998" expectedStmtMatch
    (encodeStmtV1 (.match_ boolExpr stmtArms))

  let statements : Array StmtV1 := Array.replicate 99999 returnNone
  let expectedBlock := tagged "Block" #[u32 statements.size ++
    repeatBytes returnNoneBytes statements.size]
  expectBytes "wide-block-100000" expectedBlock
    (encodeBlockV1 { statements })

  let qidErr := "source qualified id must contain 2..256 components"
  let magnitudeErr := "u256 magnitude exceeds 2^256-1"
  let blockErr := "block statements must be nonempty"
  let boundErr := "for bound must be 0..4096"
  let armsErr := "stmt match arms must be nonempty"
  let badPatternQid : PatternV1 := .constructor badQid #[]
  let badPatternMagnitude : PatternV1 := .literal (.integer (2 ^ 256))
  expectError "pattern-order-qid" qidErr
    (encodePatternV1 (.constructor goodQid #[badPatternQid, badPatternMagnitude]))
  expectError "pattern-order-magnitude" magnitudeErr
    (encodePatternV1 (.constructor goodQid #[badPatternMagnitude, badPatternQid]))

  let badExprMagnitude : ExprV1 := .literal (.integer (2 ^ 256))
  let badExprQid : ExprV1 := .constructor badQid #[]
  expectError "expr-order-magnitude" magnitudeErr
    (encodeExprV1 (.constructor goodQid #[badExprMagnitude, badExprQid]))
  expectError "expr-order-qid" qidErr
    (encodeExprV1 (.constructor goodQid #[badExprQid, badExprMagnitude]))

  let patternBadArm : ExprMatchArmV1 := { pattern := badPatternQid, value := boolExpr }
  let valueBadArm : ExprMatchArmV1 := { pattern := .wildcard, value := badExprMagnitude }
  expectError "expr-arm-order-pattern" qidErr
    (encodeExprV1 (.match_ boolExpr #[patternBadArm, valueBadArm]))
  expectError "expr-arm-order-value" magnitudeErr
    (encodeExprV1 (.match_ boolExpr #[valueBadArm, patternBadArm]))

  let stmtPatternBad : StmtMatchArmV1 := { pattern := badPatternQid, body := oneReturnBlock }
  let stmtBodyBad : StmtMatchArmV1 := { pattern := .wildcard, body := { statements := #[] } }
  expectError "stmt-arm-order-pattern" qidErr
    (encodeStmtV1 (.match_ boolExpr #[stmtPatternBad, stmtBodyBad]))
  expectError "stmt-arm-order-body" blockErr
    (encodeStmtV1 (.match_ boolExpr #[stmtBodyBad, stmtPatternBad]))

  let badFor : StmtV1 := .for_ binder boolExpr boolExpr (UInt32.ofNat 4097) oneReturnBlock
  let badMatch : StmtV1 := .match_ boolExpr #[]
  expectError "stmt-order-bound" boundErr
    (encodeBlockV1 { statements := #[badFor, badMatch] })
  expectError "stmt-order-arms" armsErr
    (encodeBlockV1 { statements := #[badMatch, badFor] })

end Tests.Language.SourceAstWideEncoderV1
