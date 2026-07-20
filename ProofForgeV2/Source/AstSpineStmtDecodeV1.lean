import ProofForgeV2.Source.AstPatternDecodeV1
import ProofForgeV2.Source.AstSpineDecodeV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstTypeDecodeV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstSpineStmtDecodeV1

open ProofForgeV2.Source.AstPatternDecodeV1
open ProofForgeV2.Source.AstSpineDecodeV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstTypeDecodeV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α := .error detail

private def blockEmptyErr := "block statements must be nonempty"
private def stmtArmsEmptyErr := "stmt match arms must be nonempty"
private def forBoundErr := "for bound must be 0..4096"

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | n + 1 => pure { remainingNodes := n }

/-- Closed 11-tag Stmt field table. Unknown fails before fieldCount. -/
private def stmtFieldCount (tag : String) : Except String Nat :=
  match tag with
  | "Stmt.Let" | "Stmt.If" => pure 3
  | "Stmt.Assign" | "Stmt.Match" | "Stmt.Assert" |
      "Stmt.Revert" | "Stmt.Emit" => pure 2
  | "Stmt.For" => pure 5
  | "Stmt.Return" | "Stmt.Call" | "Stmt.Schedule" => pure 1
  | _ => fail s!"unknown stmt tag '{tag}'"

private def stmtHead : DecoderV1 String := fun c => do
  let (tag, c) ← decodeTagV1 c
  let expected ← stmtFieldCount tag
  let ((), c) ← decodeFieldCountV1 tag expected c
  pure (tag, c)

private def singletonHead (expected : String) (family : String) (count : Nat) :
    DecoderV1 Unit := fun c => do
  let (tag, c) ← decodeTagV1 c
  unless tag == expected do
    return ← fail s!"unknown {family} tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag count c
  pure ((), c)

private def blockHead := singletonHead "Block" "block" 1
private def armHead := singletonHead "StmtMatchArm" "stmt-match-arm" 2

/-- Option TypeV1: marker then optional Type child at shared child depth. -/
private def decodeTypeOption (d : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (Option TypeV1 × DecodeBudgetV1) := fun c => do
  let (marker, c) ← decodeU8 c
  match marker.toNat with
  | 0 => pure ((none, budget), c)
  | 1 => do
      let ((value, budget), c) ← decodeTypeV1 d budget c
      pure ((some value, budget), c)
  | _ => fail "invalid option marker"

/-- Option ExprV1: marker then optional Expr child at shared child depth. -/
private def decodeExprOption (d : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (Option ExprV1 × DecodeBudgetV1) := fun c => do
  let (marker, c) ← decodeU8 c
  match marker.toNat with
  | 0 => pure ((none, budget), c)
  | 1 => do
      let ((value, budget), c) ← decodeExprV1 d budget c
      pure ((some value, budget), c)
  | _ => fail "invalid option marker"

/-- Non-SCC Expr array (Revert/Emit args). Cap vs residual after parent charge. -/
private def decodeExprArray (d : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (Array ExprV1 × DecodeBudgetV1) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > budget.remainingNodes then
    return ← fail "array count exceeds caller limit"
  let mut values : Array ExprV1 := #[]
  let mut budget := budget
  let mut c := c
  for _ in [:count] do
    let ((value, nextBudget), nextCursor) ← decodeExprV1 d budget c
    values := values.push value
    budget := nextBudget
    c := nextCursor
  pure ((values, budget), c)

-- Kernel-total mutual Stmt/Block/StmtMatchArm decoder.
-- Priority: tag → unknown → FC → depth → node → fields.
-- Block/Match: count → nonempty → residual cap → inline loop.
-- For: bound 0..4096 after endpoints, before body.
mutual
  def decodeStmtV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (StmtV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let (_tag, _c) ← stmtHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let (tag, c) ← stmtHead c
        let budget ← chargeNode budget
        match tag with
        | "Stmt.Let" => do
            let (name, c) ← decodeSourceNameComponentV1 c
            let ((typeAnn, budget), c) ← decodeTypeOption remainingDepth budget c
            let ((value, budget), c) ← decodeExprV1 remainingDepth budget c
            pure ((.let_ name typeAnn value, budget), c)
        | "Stmt.Assign" => do
            let ((target, budget), c) ← decodePlaceV1 remainingDepth budget c
            let ((value, budget), c) ← decodeExprV1 remainingDepth budget c
            pure ((.assign target value, budget), c)
        | "Stmt.If" => do
            let ((condition, budget), c) ← decodeExprV1 remainingDepth budget c
            let ((thenBlock, budget), c) ← decodeBlockV1 remainingDepth budget c
            let (marker, c) ← decodeU8 c
            match marker.toNat with
            | 0 => pure ((.if_ condition thenBlock none, budget), c)
            | 1 => do
                let ((elseBlock, budget), c) ← decodeBlockV1 remainingDepth budget c
                pure ((.if_ condition thenBlock (some elseBlock), budget), c)
            | _ => fail "invalid option marker"
        | "Stmt.Match" => do
            let ((scrutinee, budget), c) ← decodeExprV1 remainingDepth budget c
            let (countU, c) ← decodeU32le c
            let count := countU.toNat
            if count == 0 then
              return ← fail stmtArmsEmptyErr
            if count > budget.remainingNodes then
              return ← fail "array count exceeds caller limit"
            let mut arms : Array StmtMatchArmV1 := #[]
            let mut budget := budget
            let mut c := c
            for _ in [:count] do
              let ((arm, b'), c') ← decodeStmtMatchArmV1 remainingDepth budget c
              arms := arms.push arm
              budget := b'
              c := c'
            pure ((.match_ scrutinee arms, budget), c)
        | "Stmt.For" => do
            let (binder, c) ← decodeSourceNameComponentV1 c
            let ((start, budget), c) ← decodeExprV1 remainingDepth budget c
            let ((endExclusive, budget), c) ← decodeExprV1 remainingDepth budget c
            let (bound, c) ← decodeU32le c
            unless bound.toNat ≤ 4096 do
              return ← fail forBoundErr
            let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
            pure ((.for_ binder start endExclusive bound body, budget), c)
        | "Stmt.Assert" => do
            let ((condition, budget), c) ← decodeExprV1 remainingDepth budget c
            let (error, c) ← decodeOption decodeSourceNameComponentV1 c
            pure ((.assert_ condition error, budget), c)
        | "Stmt.Revert" => do
            let (error, c) ← decodeSourceNameComponentV1 c
            let ((args, budget), c) ← decodeExprArray remainingDepth budget c
            pure ((.revert error args, budget), c)
        | "Stmt.Emit" => do
            let (event, c) ← decodeSourceNameComponentV1 c
            let ((args, budget), c) ← decodeExprArray remainingDepth budget c
            pure ((.emit event args, budget), c)
        | "Stmt.Return" => do
            let ((value, budget), c) ← decodeExprOption remainingDepth budget c
            pure ((.return_ value, budget), c)
        | "Stmt.Call" => do
            let ((call, budget), c) ← decodeExternalCallExprV1 remainingDepth budget c
            pure ((.call call, budget), c)
        | "Stmt.Schedule" => do
            let ((call, budget), c) ← decodeExternalCallExprV1 remainingDepth budget c
            pure ((.schedule call, budget), c)
        | _ => fail "unreachable stmt dispatch"
    termination_by d => d

  def decodeBlockV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (BlockV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let ((), _c) ← blockHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let ((), c) ← blockHead c
        let budget ← chargeNode budget
        let (countU, c) ← decodeU32le c
        let count := countU.toNat
        if count == 0 then
          return ← fail blockEmptyErr
        if count > budget.remainingNodes then
          return ← fail "array count exceeds caller limit"
        let mut statements : Array StmtV1 := #[]
        let mut budget := budget
        let mut c := c
        for _ in [:count] do
          let ((st, b'), c') ← decodeStmtV1 remainingDepth budget c
          statements := statements.push st
          budget := b'
          c := c'
        pure (({ statements }, budget), c)
    termination_by d => d

  def decodeStmtMatchArmV1 : (d : Nat) → (budget : DecodeBudgetV1) →
      DecoderV1 (StmtMatchArmV1 × DecodeBudgetV1)
    | 0, _budget => fun c => do
        let ((), _c) ← armHead c
        fail "depth budget exhausted"
    | remainingDepth + 1, budget => fun c => do
        let ((), c) ← armHead c
        let budget ← chargeNode budget
        let ((pattern, budget), c) ← decodePatternV1 remainingDepth budget c
        let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
        pure (({ pattern, body }, budget), c)
    termination_by d => d
end

end ProofForgeV2.Source.AstSpineStmtDecodeV1
