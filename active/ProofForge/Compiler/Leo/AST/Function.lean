import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Statement

namespace ProofForge.Compiler.Leo.AST

inductive Variant where
  | fn
  | finalFn
  | entryPoint
  | view
  deriving BEq, Repr, Inhabited

structure Input where
  name : Identifier
  ty : LeoType
  mode : Mode := .public_
  deriving Repr

structure Output where
  ty : LeoType
  mode : Mode := .public_
  deriving Repr

structure Function where
  annotations : Array Annotation
  variant : Variant
  identifier : Identifier
  constParameters : Array Identifier
  input : Array Input
  output : Array Output
  outputType : LeoType
  block : Block
  deriving Repr

end ProofForge.Compiler.Leo.AST
