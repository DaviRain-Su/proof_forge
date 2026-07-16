import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

inductive Literal where
  | address (value : String)
  | boolean (value : Bool)
  | field (value : String)
  | group (value : String)
  | integer (ty : IntegerType) (value : Nat)
  | none
  | scalar (value : String)
  | signature (value : String)
  | string (value : String)
  deriving Repr, Inhabited

end ProofForge.Compiler.Leo.AST
