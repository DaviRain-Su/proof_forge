import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstPatternCodecV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstSpineCodecV1

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstPatternCodecV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireCodecV1

private def fail (detail : String) : Except String α :=
  .error detail

private def blockEmptyErr := "block statements must be nonempty"
private def stmtArmsEmptyErr := "stmt match arms must be nonempty"
private def exprArmsEmptyErr := "expr match arms must be nonempty"
private def forBoundErr := "for bound must be 0..4096"

mutual
  def encodePlaceV1 : PlaceV1 → Except String ByteArray
    | .name n => do
        let b ← encodeSourceNameComponentV1 n
        encodeTagged "Place.Name" #[b]
    | .field base field => do
        let bb ← encodePlaceV1 base
        let fb ← encodeSourceNameComponentV1 field
        encodeTagged "Place.Field" #[bb, fb]
    | .index base idx => do
        let bb ← encodePlaceV1 base
        let ib ← encodeExprV1 idx
        encodeTagged "Place.Index" #[bb, ib]
    termination_by structural p => p

  def encodeExprV1 : ExprV1 → Except String ByteArray
    | .literal v => do
        let b ← encodeLiteralV1 v
        encodeTagged "Expr.Literal" #[b]
    | .place p => do
        let b ← encodePlaceV1 p
        encodeTagged "Expr.Place" #[b]
    | .constructor ctor args => do
        let cb ← encodeSourceQualifiedIdV1 ctor
        let chunks ← encodeExprArrayV1 args
        let ab ← encodeArray pure chunks
        encodeTagged "Expr.Constructor" #[cb, ab]
    | .unary op operand => do
        let ob ← encodeUnaryOpV1 op
        let eb ← encodeExprV1 operand
        encodeTagged "Expr.Unary" #[ob, eb]
    | .binary op lhs rhs => do
        let ob ← encodeBinaryOpV1 op
        let lb ← encodeExprV1 lhs
        let rb ← encodeExprV1 rhs
        encodeTagged "Expr.Binary" #[ob, lb, rb]
    | .localCall callee args => do
        let cb ← encodeSourceNameComponentV1 callee
        let chunks ← encodeExprArrayV1 args
        let ab ← encodeArray pure chunks
        encodeTagged "Expr.LocalCall" #[cb, ab]
    | .match_ scrutinee arms => do
        unless arms.size ≥ 1 do
          return ← fail exprArmsEmptyErr
        let sb ← encodeExprV1 scrutinee
        let chunks ← encodeExprMatchArmArrayV1 arms
        let ab ← encodeArray pure chunks
        encodeTagged "Expr.Match" #[sb, ab]
    | .externalCall call => do
        let b ← encodeExternalCallExprV1 call
        encodeTagged "Expr.ExternalCall" #[b]
    termination_by structural e => e

  private def encodeExprArrayV1 : Array ExprV1 → Except String (Array ByteArray)
    | ⟨xs⟩ => encodeExprListV1 xs #[]
    termination_by structural a => a

  private def encodeExprListV1 :
      List ExprV1 → Array ByteArray → Except String (Array ByteArray)
    | [], chunks => pure chunks
    | x :: xs, chunks => do
        let chunk ← encodeExprV1 x
        encodeExprListV1 xs (chunks.push chunk)
    termination_by structural xs => xs

  def encodeExprMatchArmV1 : ExprMatchArmV1 → Except String ByteArray
    | ⟨pat, val⟩ => do
        let pb ← encodePatternV1 pat
        let vb ← encodeExprV1 val
        encodeTagged "ExprMatchArm" #[pb, vb]
    termination_by structural a => a

  private def encodeExprMatchArmArrayV1 :
      Array ExprMatchArmV1 → Except String (Array ByteArray)
    | ⟨xs⟩ => encodeExprMatchArmListV1 xs #[]
    termination_by structural a => a

  private def encodeExprMatchArmListV1 :
      List ExprMatchArmV1 → Array ByteArray → Except String (Array ByteArray)
    | [], chunks => pure chunks
    | x :: xs, chunks => do
        let chunk ← encodeExprMatchArmV1 x
        encodeExprMatchArmListV1 xs (chunks.push chunk)
    termination_by structural xs => xs

  def encodeExternalCallExprV1 : ExternalCallExprV1 → Except String ByteArray
    | ⟨callee, args⟩ => do
        let cb ← encodeSourceQualifiedIdV1 callee
        let chunks ← encodeExprArrayV1 args
        let ab ← encodeArray pure chunks
        encodeTagged "ExternalCallExpr" #[cb, ab]

  def encodeBlockV1 : BlockV1 → Except String ByteArray
    | ⟨stmts⟩ => do
        unless stmts.size ≥ 1 do
          return ← fail blockEmptyErr
        let chunks ← encodeStmtArrayV1 stmts
        let sb ← encodeArray pure chunks
        encodeTagged "Block" #[sb]
    termination_by structural b => b

  def encodeStmtMatchArmV1 : StmtMatchArmV1 → Except String ByteArray
    | ⟨pat, body⟩ => do
        let pb ← encodePatternV1 pat
        let bb ← encodeBlockV1 body
        encodeTagged "StmtMatchArm" #[pb, bb]
    termination_by structural a => a

  private def encodeStmtMatchArmArrayV1 :
      Array StmtMatchArmV1 → Except String (Array ByteArray)
    | ⟨xs⟩ => encodeStmtMatchArmListV1 xs #[]
    termination_by structural a => a

  private def encodeStmtMatchArmListV1 :
      List StmtMatchArmV1 → Array ByteArray → Except String (Array ByteArray)
    | [], chunks => pure chunks
    | x :: xs, chunks => do
        let chunk ← encodeStmtMatchArmV1 x
        encodeStmtMatchArmListV1 xs (chunks.push chunk)
    termination_by structural xs => xs

  def encodeStmtV1 : StmtV1 → Except String ByteArray
    | .let_ n ty v => do
        let nb ← encodeSourceNameComponentV1 n
        let tb ← encodeOption encodeTypeV1 ty
        let vb ← encodeExprV1 v
        encodeTagged "Stmt.Let" #[nb, tb, vb]
    | .assign t v => do
        let tb ← encodePlaceV1 t
        let vb ← encodeExprV1 v
        encodeTagged "Stmt.Assign" #[tb, vb]
    | .if_ c th el => do
        let cb ← encodeExprV1 c
        let tb ← encodeBlockV1 th
        let eb ← match el with
          | none => pure (encodeU8 0)
          | some b => do
              let bb ← encodeBlockV1 b
              pure ((encodeU8 1).append bb)
        encodeTagged "Stmt.If" #[cb, tb, eb]
    | .match_ s arms => do
        unless arms.size ≥ 1 do
          return ← fail stmtArmsEmptyErr
        let sb ← encodeExprV1 s
        let chunks ← encodeStmtMatchArmArrayV1 arms
        let ab ← encodeArray pure chunks
        encodeTagged "Stmt.Match" #[sb, ab]
    | .for_ b st en bd body => do
        unless bd.toNat ≤ 4096 do
          return ← fail forBoundErr
        let bb ← encodeSourceNameComponentV1 b
        let sb ← encodeExprV1 st
        let eb ← encodeExprV1 en
        let bodyB ← encodeBlockV1 body
        encodeTagged "Stmt.For" #[bb, sb, eb, encodeU32le bd, bodyB]
    | .assert_ c err => do
        let cb ← encodeExprV1 c
        let eb ← encodeOption encodeSourceNameComponentV1 err
        encodeTagged "Stmt.Assert" #[cb, eb]
    | .revert e args => do
        let eb ← encodeSourceNameComponentV1 e
        let chunks ← encodeExprArrayV1 args
        let ab ← encodeArray pure chunks
        encodeTagged "Stmt.Revert" #[eb, ab]
    | .emit ev args => do
        let eb ← encodeSourceNameComponentV1 ev
        let chunks ← encodeExprArrayV1 args
        let ab ← encodeArray pure chunks
        encodeTagged "Stmt.Emit" #[eb, ab]
    | .return_ v => do
        let vb ← match v with
          | none => pure (encodeU8 0)
          | some e => do
              let eb ← encodeExprV1 e
              pure ((encodeU8 1).append eb)
        encodeTagged "Stmt.Return" #[vb]
    | .call c => do
        let cb ← encodeExternalCallExprV1 c
        encodeTagged "Stmt.Call" #[cb]
    | .schedule c => do
        let cb ← encodeExternalCallExprV1 c
        encodeTagged "Stmt.Schedule" #[cb]
    termination_by structural s => s

  private def encodeStmtArrayV1 : Array StmtV1 → Except String (Array ByteArray)
    | ⟨xs⟩ => encodeStmtListV1 xs #[]
    termination_by structural a => a

  private def encodeStmtListV1 :
      List StmtV1 → Array ByteArray → Except String (Array ByteArray)
    | [], chunks => pure chunks
    | x :: xs, chunks => do
        let chunk ← encodeStmtV1 x
        encodeStmtListV1 xs (chunks.push chunk)
    termination_by structural xs => xs
end

end ProofForgeV2.Source.AstSpineCodecV1
