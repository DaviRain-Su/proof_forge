import ProofForgeV2.Source.AstPatternDecodeV1
import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstSpineDecodeV1

open ProofForgeV2.Source.AstPatternDecodeV1
open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α := .error detail

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | n + 1 => pure { remainingNodes := n }

private def exprArmsEmptyErr := "expr match arms must be nonempty"

/-- Closed Place tag table. Dispatch completes before field-count decoding. -/
private def placeFieldCount (tag : String) : Except String Nat :=
  match tag with
  | "Place.Name" => pure 1
  | "Place.Field" | "Place.Index" => pure 2
  | _ => fail s!"unknown place tag '{tag}'"

/-- Closed Expr tag table. Dispatch completes before field-count decoding. -/
private def exprFieldCount (tag : String) : Except String Nat :=
  match tag with
  | "Expr.Literal" | "Expr.Place" => pure 1
  | "Expr.Constructor" | "Expr.Unary" | "Expr.LocalCall" | "Expr.Match" => pure 2
  | "Expr.Binary" => pure 3
  | _ => fail s!"unknown expr tag '{tag}'"

private def placeHead : DecoderV1 String := fun c => do
  let (tag, c) ← decodeTagV1 c
  let expected ← placeFieldCount tag
  let ((), c) ← decodeFieldCountV1 tag expected c
  pure (tag, c)

private def exprHead : DecoderV1 String := fun c => do
  let (tag, c) ← decodeTagV1 c
  let expected ← exprFieldCount tag
  let ((), c) ← decodeFieldCountV1 tag expected c
  pure (tag, c)

private def armHead : DecoderV1 Unit := fun c => do
  let (tag, c) ← decodeTagV1 c
  unless tag == "ExprMatchArm" do
    return ← fail s!"unknown expr-match-arm tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag 2 c
  pure ((), c)

private def extHead : DecoderV1 Unit := fun c => do
  let (tag, c) ← decodeTagV1 c
  unless tag == "ExternalCallExpr" do
    return ← fail s!"unknown external-call tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag 2 c
  pure ((), c)

-- Kernel-total mutual Place/Expr/Arm/ExternalCall decoder.
-- Priority: tag → unknown → fieldCount → depth → node charge → ordered fields.
-- Array siblings share child depth and thread residual node budget; Match is
-- scrutinee then count then nonempty then cap then arms.
mutual
  def decodePlaceV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (PlaceV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let (_tag, _c) ← placeHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let (tag, c) ← placeHead c
        let budget ← chargeNode budget
        match tag with
        | "Place.Name" => do
            let (name, c) ← decodeSourceNameComponentV1 c
            pure ((.name name, budget), c)
        | "Place.Field" => do
            let ((base, budget), c) ← decodePlaceV1 remainingDepth budget c
            let (field, c) ← decodeSourceNameComponentV1 c
            pure ((.field base field, budget), c)
        | "Place.Index" => do
            let ((base, budget), c) ← decodePlaceV1 remainingDepth budget c
            let ((idx, budget), c) ← decodeExprV1 remainingDepth budget c
            pure ((.index base idx, budget), c)
        | _ => fail "unreachable place dispatch"
    termination_by d => d

  def decodeExprV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (ExprV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let (_tag, _c) ← exprHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let (tag, c) ← exprHead c
        let budget ← chargeNode budget
        match tag with
        | "Expr.Literal" => do
            let (v, c) ← decodeLiteralV1 c
            pure ((.literal v, budget), c)
        | "Expr.Place" => do
            let ((p, budget), c) ← decodePlaceV1 remainingDepth budget c
            pure ((.place p, budget), c)
        | "Expr.Constructor" => do
            let (ctor, c) ← decodeSourceQualifiedIdV1 c
            let (countU, c) ← decodeU32le c
            let count := countU.toNat
            if count > budget.remainingNodes then
              return ← fail "array count exceeds caller limit"
            let mut args : Array ExprV1 := #[]
            let mut budget := budget
            let mut c := c
            for _ in [:count] do
              let ((e, b'), c') ← decodeExprV1 remainingDepth budget c
              args := args.push e
              budget := b'
              c := c'
            pure ((.constructor ctor args, budget), c)
        | "Expr.Unary" => do
            let (op, c) ← decodeUnaryOpV1 c
            let ((operand, budget), c) ← decodeExprV1 remainingDepth budget c
            pure ((.unary op operand, budget), c)
        | "Expr.Binary" => do
            let (op, c) ← decodeBinaryOpV1 c
            let ((lhs, budget), c) ← decodeExprV1 remainingDepth budget c
            let ((rhs, budget), c) ← decodeExprV1 remainingDepth budget c
            pure ((.binary op lhs rhs, budget), c)
        | "Expr.LocalCall" => do
            let (callee, c) ← decodeSourceNameComponentV1 c
            let (countU, c) ← decodeU32le c
            let count := countU.toNat
            if count > budget.remainingNodes then
              return ← fail "array count exceeds caller limit"
            let mut args : Array ExprV1 := #[]
            let mut budget := budget
            let mut c := c
            for _ in [:count] do
              let ((e, b'), c') ← decodeExprV1 remainingDepth budget c
              args := args.push e
              budget := b'
              c := c'
            pure ((.localCall callee args, budget), c)
        | "Expr.Match" => do
            let ((scrut, budget), c) ← decodeExprV1 remainingDepth budget c
            let (countU, c) ← decodeU32le c
            let count := countU.toNat
            if count == 0 then
              return ← fail exprArmsEmptyErr
            if count > budget.remainingNodes then
              return ← fail "array count exceeds caller limit"
            let mut arms : Array ExprMatchArmV1 := #[]
            let mut budget := budget
            let mut c := c
            for _ in [:count] do
              let ((arm, b'), c') ← decodeExprMatchArmV1 remainingDepth budget c
              arms := arms.push arm
              budget := b'
              c := c'
            pure ((.match_ scrut arms, budget), c)
        | _ => fail "unreachable expr dispatch"
    termination_by d => d

  def decodeExprMatchArmV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (ExprMatchArmV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let ((), _c) ← armHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let ((), c) ← armHead c
        let budget ← chargeNode budget
        let ((pat, budget), c) ← decodePatternV1 remainingDepth budget c
        let ((val, budget), c) ← decodeExprV1 remainingDepth budget c
        pure (({ pattern := pat, value := val }, budget), c)
    termination_by d => d

  def decodeExternalCallExprV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (ExternalCallExprV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let ((), _c) ← extHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let ((), c) ← extHead c
        let budget ← chargeNode budget
        let (callee, c) ← decodeSourceQualifiedIdV1 c
        let (countU, c) ← decodeU32le c
        let count := countU.toNat
        if count > budget.remainingNodes then
          return ← fail "array count exceeds caller limit"
        let mut args : Array ExprV1 := #[]
        let mut budget := budget
        let mut c := c
        for _ in [:count] do
          let ((e, b'), c') ← decodeExprV1 remainingDepth budget c
          args := args.push e
          budget := b'
          c := c'
        pure (({ callee, args }, budget), c)
    termination_by d => d
end

end ProofForgeV2.Source.AstSpineDecodeV1
