import ProofForge.Compiler.Leo.AST.Core
import ProofForge.Compiler.Leo.AST.Type
import ProofForge.Compiler.Leo.AST.Function
import ProofForge.Compiler.Leo.AST.Composite
import ProofForge.Compiler.Leo.AST.Mapping
import ProofForge.Compiler.Leo.AST.Storage

namespace ProofForge.Compiler.Leo.AST

structure Import where
  programId : ProgramId
  deriving Repr, Inhabited

structure Constructor where
  annotations : Array Annotation
  block : Block
  deriving Repr

structure Interface where
  identifier : Identifier
  parents : Array LeoType
  members : Array Function
  deriving Repr

structure ConstDeclaration where
  identifier : Identifier
  ty? : Option LeoType
  value : Expression
  deriving Repr

structure ProgramScope where
  programId : ProgramId
  parents : Array LeoType
  consts : Array (Identifier × ConstDeclaration)
  composites : Array (Identifier × Composite)
  mappings : Array (Identifier × Mapping)
  storageVariables : Array (Identifier × StorageVariable)
  functions : Array (Identifier × Function)
  interfaces : Array (Identifier × Interface)
  constructor : Option Constructor
  deriving Repr

structure Program where
  imports : Array Import
  scopes : Array (Identifier × ProgramScope)
  deriving Repr

end ProofForge.Compiler.Leo.AST
