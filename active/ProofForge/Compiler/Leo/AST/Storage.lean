import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure StorageVariable where
  identifier : Identifier
  ty : LeoType
  deriving Repr

end ProofForge.Compiler.Leo.AST
