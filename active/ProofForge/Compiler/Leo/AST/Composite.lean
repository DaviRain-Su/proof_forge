import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure Member where
  name : Identifier
  ty : LeoType
  deriving Repr

structure Composite where
  identifier : Identifier
  members : Array Member
  isRecord : Bool := false
  deriving Repr

end ProofForge.Compiler.Leo.AST
