import ProofForge.IR.Core.Storage

namespace ProofForge.IR.Core

/- Cross-call specification. Gas and value are optional value references. -/

structure CoreCrosscallSpec where
  family : String
  gas : Option ValueRef
  value : Option ValueRef
  deriving BEq, Repr

/- Typed host-operation identifiers (Wave 3 extension point). Exact versions
are required; there is no implicit version range. -/

structure HostOpVersion where
  major : Nat
  minor : Nat
  patch : Nat
  deriving BEq, Repr

structure HostOpId where
  namespace_ : String
  name : String
  version : HostOpVersion
  deriving BEq, Repr

structure HostOpCall where
  id : HostOpId
  args : Array ValueRef
  deriving BEq, Repr

/- Pure operations are side-effect-free and can appear inside ANF
instructions. -/

inductive PureOp
  | literal (value : CoreLiteral)
  | unary (op : UnaryOp) (arg : ValueRef)
  | arithmetic (op : ArithmeticOp) (mode : OverflowMode) (lhs rhs : ValueRef)
  | compare (op : CompareOp) (lhs rhs : ValueRef)
  | cast (to : CoreType) (arg : ValueRef)
  | hash (arg : ValueRef)
  deriving BEq, Repr

/- Instructions are the unit of effect in Core. Every value-producing effect
binds explicit result IDs; nested effectful expressions are not allowed. -/

inductive InstructionOp
  | pure (op : PureOp)
  | storageLoad (path : StorageRef)
  | storageContains (path : StorageRef)
  | storageStore (path : StorageRef) (value : ValueRef)
  | storageLength (root : StateId)
  | storageResize (root : StateId) (length : ValueRef)
  | memoryAlloc (type : CoreType) (length : ValueRef)
  | memoryLoad (base index : ValueRef)
  | memoryStore (base index value : ValueRef)
  | memoryRelease (base : ValueRef)
  | contextRead (field : ContextField)
  | emit (event : EventId) (args : Array ValueRef)
  | assert (condition : ValueRef) (error : CoreErrorRef)
  | crosscall (spec : CoreCrosscallSpec) (args : Array ValueRef)
  | hostCall (call : HostOpCall)
  deriving BEq, Repr

structure Instruction where
  results : Array ValueDef
  op : InstructionOp
  deriving BEq, Repr

/- Loop bounds preserve intent for targets with different unbounded-loop
capabilities. A cycle without a bound is invalid. -/

inductive LoopBound
  | atMost (iterations : Nat)
  | requiresUnbounded
  deriving BEq, Repr

/- Terminators are the single exit point of a basic block. -/

inductive Terminator
  | jump (target : BlockId) (args : Array ValueRef) (backedgeBound : Option LoopBound := none)
  | branch (condition : ValueRef) (onTrue onFalse : BlockId)
  | return (values : Array ValueRef)
  | revert (error : CoreErrorRef)
  deriving BEq, Repr

/- Basic blocks carry parameters for SSA/CFG value merging and a single
terminator. -/

structure Block where
  id : BlockId
  params : Array ValueDef := #[]
  instructions : Array Instruction
  terminator : Terminator
  deriving BEq, Repr

/- Functions are named CFGs with an explicit entry block. -/

structure Function where
  id : FunctionId
  params : Array ValueDef
  retType : CoreType
  blocks : Array Block
  entry : BlockId
  deriving BEq, Repr

/- Module-level declarations. -/

structure Struct where
  id : TypeId
  fields : Array ValueDef
  deriving BEq, Repr

structure Event where
  id : EventId
  fields : Array ValueDef
  deriving BEq, Repr

structure StateDecl where
  id : StateId
  shape : StateShape
  deriving BEq, Repr

/- A Core module contains portable runtime semantics: resolved symbols,
structs, logical state, functions, events, and stable context operations. -/

structure Module where
  name : String
  structs : Array Struct := #[]
  state : Array StateDecl := #[]
  functions : Array Function := #[]
  events : Array Event := #[]
  deriving Repr

end ProofForge.IR.Core
