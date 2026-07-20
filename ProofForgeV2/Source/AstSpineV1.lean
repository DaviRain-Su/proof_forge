import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.AstSpineV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

mutual
  inductive PlaceV1 where
    | name (name : SourceNameComponentV1)
    | field (base : PlaceV1) (field : SourceNameComponentV1)
    | index (base : PlaceV1) (index : ExprV1)
    deriving Repr

  inductive ExprV1 where
    | literal (value : LiteralV1)
    | place (place : PlaceV1)
    | constructor (ctor : SourceQualifiedNameV1) (args : Array ExprV1)
    | unary (op : UnaryOpV1) (operand : ExprV1)
    | binary (op : BinaryOpV1) (lhs rhs : ExprV1)
    | localCall (callee : SourceNameComponentV1) (args : Array ExprV1)
    | match_ (scrutinee : ExprV1) (arms : Array ExprMatchArmV1)
    deriving Repr

  structure ExprMatchArmV1 where
    pattern : PatternV1
    value : ExprV1
    deriving Repr

  structure ExternalCallExprV1 where
    callee : SourceQualifiedNameV1
    args : Array ExprV1
    deriving Repr

  inductive StmtV1 where
    | let_ (name : SourceNameComponentV1) (typeAnn : Option TypeV1) (value : ExprV1)
    | assign (target : PlaceV1) (value : ExprV1)
    | if_ (condition : ExprV1) (thenBlock : BlockV1) (elseBlock : Option BlockV1)
    | match_ (scrutinee : ExprV1) (arms : Array StmtMatchArmV1)
    | for_ (binder : SourceNameComponentV1) (start endExclusive : ExprV1)
        (bound : UInt32) (body : BlockV1)
    | assert_ (condition : ExprV1) (error : Option SourceNameComponentV1)
    | revert (error : SourceNameComponentV1) (args : Array ExprV1)
    | emit (event : SourceNameComponentV1) (args : Array ExprV1)
    | return_ (value : Option ExprV1)
    | call (call : ExternalCallExprV1)
    | schedule (call : ExternalCallExprV1)
    deriving Repr

  structure StmtMatchArmV1 where
    pattern : PatternV1
    body : BlockV1
    deriving Repr

  structure BlockV1 where
    statements : Array StmtV1
    deriving Repr
end

end ProofForgeV2.Source.AstSpineV1
