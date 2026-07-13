import ProofForge.IR.Core.Storage
import ProofForge.Target.HostOp

namespace ProofForge.IR.Core

/- Portable cross-calls have closed semantic modes and explicit typed operands.
Target-specific ABI, account-layout, deployment, and scheduling forms remain
typed extensions or target-plan data. -/

inductive CoreCrosscallMode
  | invoke
  | staticInvoke
  | delegateInvoke
  /-- Invoke a named remote endpoint. Target plans decide how names are bound. -/
  | namedInvoke
  /-- Schedule an invocation after a prior asynchronous result handle. -/
  | continuation
  deriving BEq, DecidableEq, Repr, Inhabited

structure CoreCrosscallSpec where
  mode : CoreCrosscallMode
  target : ValueRef
  method : ValueRef
  gas : Option ValueRef := none
  value : Option ValueRef := none
  paramTypes : Array CoreType := #[]
  /-- Wire names for JSON-object arguments. Empty means the historical JSON
  array encoding; otherwise this must match `paramTypes` one-for-one. -/
  argNames : Array String := #[]
  returnType : CoreType
  deriving BEq, Repr

/- Compatibility aliases while call sites migrate to the Target extension
protocol. Identity ownership is `ProofForge.Target`, not Canonical Core. -/

abbrev HostOpVersion := ProofForge.Target.HostOpVersion
abbrev HostOpId := ProofForge.Target.HostOpId

structure HostOpCall where
  id : ProofForge.Target.HostOpId
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
  | hashTwoToOne (lhs rhs : ValueRef)
  | structLit (typeId : TypeId) (fields : Array ValueRef)
  deriving BEq, Repr

/- Instructions are the unit of effect in Core. Every value-producing effect
binds explicit result IDs; nested effectful expressions are not allowed. -/

inductive InstructionOp
  | pure (op : PureOp)
  | storageLoad (path : StorageRef)
  | storageContains (path : StorageRef)
  | storageStore (path : StorageRef) (value : ValueRef)
  | storageRemove (path : StorageRef)
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

inductive FieldOwnership
  | value
  | reference
  deriving BEq, Repr, Inhabited

inductive StructSemantics
  | value
  | linearRecord
  deriving BEq, Repr, Inhabited

structure FieldDecl where
  id : FieldId
  type : CoreType
  ownership : FieldOwnership := .value
  deriving BEq, Repr, Inhabited

structure EventFieldDecl where
  id : EventFieldId
  type : CoreType
  deriving BEq, Repr, Inhabited

structure ErrorDecl where
  id : ErrorId
  namespace_ : String
  name : String
  code : Nat
  params : Array CoreType := #[]
  deriving BEq, Repr, Inhabited

structure Struct where
  id : TypeId
  fields : Array FieldDecl
  semantics : StructSemantics := .value
  deriving BEq, Repr

structure Event where
  id : EventId
  fields : Array EventFieldDecl
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
  errors : Array ErrorDecl := #[]
  deriving BEq, Repr, Inhabited

end ProofForge.IR.Core
