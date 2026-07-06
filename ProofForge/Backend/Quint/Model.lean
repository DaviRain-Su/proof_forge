import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Backend.Quint

/-- Quint value types used by the model generator. -/
inductive QuintType where
  | int
  | bool
  | str
  | set (elem : QuintType)
  | map (key val : QuintType)
  | list (elem : QuintType)
  | custom (name : String)

def QuintType.name : QuintType → String
  | .int => "int"
  | .bool => "bool"
  | .str => "str"
  | .set elem => s!"Set[{elem.name}]"
  | .map key val => s!"Map[{key.name}, {val.name}]"
  | .list elem => s!"List[{elem.name}]"
  | .custom name => name

/-- Binary operators supported in generated Quint expressions. -/
inductive BinOp where
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or

def BinOp.symbol : BinOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .and => "and"
  | .or => "or"

/-- Quint reserved words that cannot be used as action or variable names. -/
def reservedNames : List String := [
  "action", "all", "and", "any", "as", "bool", "const", "def", "else",
  "export", "false", "from", "get", "if", "import", "int", "list", "map",
  "module", "nondet", "not", "oneOf", "or", "pure", "set", "step", "str",
  "true", "type", "val", "var"
]

def sanitizeName (name : String) : String :=
  if reservedNames.contains name then name ++ "_" else name

/-- Unary operators supported in generated Quint expressions. -/
inductive UnOp where
  | not | neg

def UnOp.symbol : UnOp → String
  | .not => "not"
  | .neg => "-"

/-- Quint expressions. -/
inductive Expr where
  | literalInt (value : Int)
  | literalBool (value : Bool)
  | literalStr (value : String)
  | local (name : String)
  | binOp (op : BinOp) (lhs rhs : Expr)
  | unOp (op : UnOp) (value : Expr)
  | prime (value : Expr)
  | app (fn : String) (args : Array Expr)
  | oneOf (set : Expr)
  | range (low high : Expr)
  | setLit (values : Array Expr)
  | listLit (values : Array Expr)
  | mapLit (entries : Array (Expr × Expr))
  | ite (cond thenExpr elseExpr : Expr)
  deriving Inhabited

/-- A clause inside an action body. -/
inductive ActionClause where
  | assign (target value : Expr)
  | guard (expr : Expr)
  | call (name : String) (args : Array Expr)
  | nondet (name : String) (domain : Expr) (body : ActionClause)
  | all (clauses : Array ActionClause)
  | any (clauses : Array ActionClause)
  deriving Inhabited

/-- A Quint action (entrypoint or step). -/
structure Action where
  name : String
  params : Array (String × QuintType) := #[]
  ret? : Option QuintType := none
  body : ActionClause

/-- A pure helper definition. -/
structure PureDef where
  name : String
  params : Array (String × QuintType) := #[]
  ret : QuintType
  body : Expr

/-- A module-level constant. -/
structure Constant where
  name : String
  type : QuintType

/-- A state variable declaration. -/
structure Var where
  name : String
  type : QuintType

/-- An invariant (val) declaration. -/
structure Val where
  name : String
  body : Expr

/-- A Quint module. -/
structure Module where
  name : String
  constants : Array Constant := #[]
  vars : Array Var := #[]
  pureDefs : Array PureDef := #[]
  actions : Array Action := #[]
  vals : Array Val := #[]
  deriving Inhabited

end ProofForge.Backend.Quint
