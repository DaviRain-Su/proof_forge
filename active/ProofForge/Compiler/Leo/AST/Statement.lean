import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Literal

namespace ProofForge.Compiler.Leo.AST

abbrev Path := Array Identifier

inductive BinaryOperation where
  | add | addWrapped | and | bitwiseAnd | div | divWrapped | eq | gte | gt | lte | lt
  | mod | mul | mulWrapped | nand | neq | nor | or | bitwiseOr | pow | powWrapped
  | rem | remWrapped | shl | shlWrapped | shr | shrWrapped | sub | subWrapped | xor
  deriving BEq, Repr

inductive UnaryOperation where
  | abs | absWrapped | double | inverse | negate | not | square | squareRoot
  | toXCoordinate | toYCoordinate
  deriving BEq, Repr

mutual
  inductive DefinitionPlace where
    | single (name : Identifier)
    | multiple (names : Array Identifier)
    deriving Repr

  inductive Statement where
    | assert (condition : Expression) (message? : Option Expression)
    | assign (place : Expression) (value : Expression)
    | block (b : Block)
    | conditional (condition : Expression) (thenBranch : Block) (elseBranch? : Option Statement)
    | constDecl (name : Identifier) (ty? : Option LeoType) (value : Expression)
    | definition (place : DefinitionPlace) (ty? : Option LeoType) (value : Expression)
    | expression (e : Expression)
    | iteration (var : Identifier) (ty? : Option LeoType) (start stop : Expression) (inclusive : Bool) (body : Block)
    | returnSt (value? : Option Expression)
    deriving Repr

  structure Block where
    statements : Array Statement
    deriving Repr

  structure CallExpression where
    function : Path
    constArguments : Array Expression
    arguments : Array Expression
    deriving Repr

  structure MemberAccess where
    inner : Expression
    name : Identifier
    deriving Repr

  structure BinaryExpression where
    op : BinaryOperation
    left : Expression
    right : Expression
    deriving Repr

  structure UnaryExpression where
    op : UnaryOperation
    receiver : Expression
    deriving Repr

  structure CastExpression where
    value : Expression
    target : LeoType
    deriving Repr

  inductive Expression where
    | arrayAccess (e : ArrayAccess)
    | async (b : Block)
    | array (values : Array Expression)
    | binary (e : BinaryExpression)
    | call (e : CallExpression)
    | cast (e : CastExpression)
    | composite (name : Identifier) (fields : Array (Identifier × Expression))
    | err
    | identifier (name : Identifier)
    | literal (l : Literal)
    | memberAccess (e : MemberAccess)
    | repeat (value : Expression) (count : Nat)
    | ternary (cond : Expression) (thenExpr : Expression) (elseExpr : Expression)
    | tuple (values : Array Expression)
    | unary (e : UnaryExpression)
    | unit
    deriving Repr

  structure ArrayAccess where
    array : Expression
    index : Expression
    deriving Repr
end

end ProofForge.Compiler.Leo.AST
