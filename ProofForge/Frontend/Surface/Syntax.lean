import ProofForge.Frontend.Surface.Type
import ProofForge.IR.Core

/-! # Surface AST — Independent Syntax

Surface-owned expression, statement, state, event, error, entrypoint,
and contract types. These do NOT alias `IR.Expr`, `IR.Effect`,
`IR.Statement`, or `IR.Module`.
-/

namespace ProofForge.Frontend.Surface

/-- A source span for evidence tracking. -/
structure SourceSpan where
  file : String
  line : Nat
  col : Nat
  deriving Repr

/-- Surface-level literals. -/
inductive SurfaceLiteral
  | unitLit
  | boolLit (b : Bool)
  | u8Lit (n : Nat)
  | u32Lit (n : Nat)
  | u64Lit (n : Nat)
  | u128Lit (n : Nat)
  | addressLit (s : String)
  | stringLit (s : String)
  | hashLit (s : String)
  | bytesLit (data : ByteArray)
  deriving Repr

/-- Surface-level binary arithmetic ops. -/
inductive SurfaceArithOp
  | add | sub | mul | div | mod
  | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
  deriving Repr

/-- Surface-level comparison ops. -/
inductive SurfaceCompareOp
  | eq | ne | lt | le | gt | ge
  deriving Repr

/-- Surface-level unary ops. -/
inductive SurfaceUnaryOp
  | not | neg
  deriving Repr

/-- Surface-level context fields. -/
inductive SurfaceContextField
  | sender
  | value
  | blockNumber
  | blockTimestamp
  | gas
  | contractAddress
  deriving Repr

/-- Portable crosscall semantics. Target ABI and scheduling stay out of Surface. -/
inductive SurfaceCrosscallMode
  | invoke
  | staticInvoke
  | delegateInvoke
  deriving Repr

/-- Surface-level lvalues (assignment targets). -/
inductive SurfaceLValue
  | local (name : String)
  | stateField (name : String)
  deriving Repr


/-- Surface-level expressions. -/
inductive SurfaceExpr
  | literal (lit : SurfaceLiteral)
  | peerRef (logicalId : String)
  | local (name : String)
  | stateRead (stateName : String)
  | mapRead (stateName : String) (key : SurfaceExpr)
  | arrayRead (stateName : String) (index : SurfaceExpr)
  | memoryArray (elementType : SurfaceType) (values : Array SurfaceExpr)
  | field (base : SurfaceExpr) (fieldName : String)
  | index (base : SurfaceExpr) (idx : SurfaceExpr)
  | unary (op : SurfaceUnaryOp) (arg : SurfaceExpr)
  | arith (op : SurfaceArithOp) (checked : Bool) (lhs rhs : SurfaceExpr)
  | compare (op : SurfaceCompareOp) (lhs rhs : SurfaceExpr)
  | boolAnd (lhs rhs : SurfaceExpr)
  | boolOr (lhs rhs : SurfaceExpr)
  | cast (to : SurfaceType) (arg : SurfaceExpr)
  | hash (arg : SurfaceExpr)
  | hashPair (lhs rhs : SurfaceExpr)
  | contextRead (field : SurfaceContextField)
  | nativeValue
  | hostCall (id : ProofForge.Target.HostOpId) (args : Array SurfaceExpr)
  | crosscall (mode : SurfaceCrosscallMode) (target method : SurfaceExpr)
      (args : Array SurfaceExpr) (returnType : SurfaceType)
  deriving Repr

/-- Surface-level statements. -/
inductive SurfaceStmt
  | bind (name : String) (type : SurfaceType) (value : SurfaceExpr)
  | mutBind (name : String) (type : SurfaceType) (value : SurfaceExpr)
  | assign (target : SurfaceLValue) (value : SurfaceExpr)
  | stateWrite (stateName : String) (value : SurfaceExpr)
  | mapWrite (stateName : String) (key value : SurfaceExpr)
  | arrayWrite (stateName : String) (index value : SurfaceExpr)
  | emit (eventName : String) (args : Array SurfaceExpr)
  | assert (condition : SurfaceExpr) (message : String)
  | revert (message : String)
  | branch (condition : SurfaceExpr) (thenBody elseBody : Array SurfaceStmt)
  | boundedLoop (indexName : String) (start stopExclusive : Nat) (body : Array SurfaceStmt)
  | hostCallBind (name : String) (type : SurfaceType) (id : ProofForge.Target.HostOpId) (args : Array SurfaceExpr)
  | returnExpr (value : SurfaceExpr)
  | returnUnit
  deriving Repr

/-- Surface-level state declarations. -/
inductive SurfaceStateKind
  | scalar (type : SurfaceType)
  | map (keyType valueType : SurfaceType) (capacity : Option Nat)
  | fixedArray (element : SurfaceType) (length : Nat)
  | dynamicArray (element : SurfaceType)
  | record (typeName : String)
  deriving Repr, Inhabited

structure SurfaceStateDecl where
  name : String
  kind : SurfaceStateKind
  generated : Bool := false
  deriving Repr, Inhabited

/-- Surface-level event field. -/
structure SurfaceEventField where
  name : String
  type : SurfaceType
  indexed : Bool
  deriving Repr

structure SurfaceEventDecl where
  name : String
  fields : Array SurfaceEventField
  deriving Repr

/-- Surface-level entrypoint. -/
inductive SurfaceEntrypointKind
  | function
  | fallback
  | receive
  deriving Repr

inductive SurfaceMutability
  | call
  | view
  deriving Repr

structure SurfaceParam where
  name : String
  type : SurfaceType
  deriving Repr

structure SurfaceEntrypoint where
  name : String
  kind : SurfaceEntrypointKind
  mutability : SurfaceMutability
  selector? : Option String := none
  params : Array SurfaceParam
  retType : SurfaceType
  body : Array SurfaceStmt
  span : Option SourceSpan := none
  deriving Repr

/-- Surface-level struct field. -/
structure SurfaceStructField where
  name : String
  type : SurfaceType
  deriving Repr

structure SurfaceStructDecl where
  name : String
  fields : Array SurfaceStructField
  deriving Repr

/-- Surface-level constructor binding. -/
inductive SurfaceConstructorBindingKind
  | scalarU64
  | addressWord
  | addressKeccak
  | stringLength
  | stringKeccak
  | bytesLength
  | bytesKeccak
  | arrayLength
  | arraySumU64
  deriving Repr

structure SurfaceConstructorBinding where
  stateName : String
  paramName : String
  kind : SurfaceConstructorBindingKind
  deriving Repr

structure SurfaceConstructorParam where
  name : String
  abiType : String
  deriving Repr

/-- Surface-level error declaration. -/
structure SurfaceErrorDecl where
  name : String
  message : String
  params : Array SurfaceType
  deriving Repr

/-- Surface-level interface intent (maps to canonical MaterializationIntent). -/
inductive SurfaceIntentKind
  | module
  | state
  | entrypoint
  | capability
  deriving Repr

structure SurfaceIntent where
  kind : SurfaceIntentKind
  label : String
  capability? : Option ProofForge.Target.Capability := none
  metadata : Array ProofForge.Target.TargetMetadata := #[]
  source? : Option String := none
  deriving Repr

/-- A complete Surface contract. -/
structure SurfaceContract where
  name : String
  structs : Array SurfaceStructDecl
  state : Array SurfaceStateDecl
  events : Array SurfaceEventDecl
  errors : Array SurfaceErrorDecl
  entrypoints : Array SurfaceEntrypoint
  constructorParams : Array SurfaceConstructorParam
  constructorBindings : Array SurfaceConstructorBinding
  intents : Array SurfaceIntent := #[]
  deriving Repr

end ProofForge.Frontend.Surface
