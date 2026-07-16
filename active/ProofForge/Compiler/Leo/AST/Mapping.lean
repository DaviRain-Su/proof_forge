import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type

namespace ProofForge.Compiler.Leo.AST

structure Mapping where
  identifier : Identifier
  keyType : LeoType
  valueType : LeoType
  deriving Repr

end ProofForge.Compiler.Leo.AST
