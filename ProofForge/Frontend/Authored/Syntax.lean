import ProofForge.Frontend.Authored.Type
import ProofForge.IR.Core

/-! # Authored AST — Independent Syntax

Authored-owned expression, statement, state, event, error, entrypoint,
and contract types. These do NOT alias `IR.Expr`, `IR.Effect`,
`IR.Statement`, or `IR.Module`.
-/

namespace ProofForge.Frontend.Authored

/-- A source span for evidence tracking. -/
structure SourceSpan where
  file : String
  line : Nat
  col : Nat
  deriving Repr

/-- Authored-level literals. -/
inductive AuthoredLiteral
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

/-- Authored-level binary arithmetic ops. -/
inductive AuthoredArithOp
  | add | sub | mul | div | mod
  | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
  deriving Repr

/-- Authored-level comparison ops. -/
inductive AuthoredCompareOp
  | eq | ne | lt | le | gt | ge
  deriving Repr

/-- Authored-level unary ops. -/
inductive AuthoredUnaryOp
  | not | neg
  deriving Repr

/-- Authored-level context fields. -/
inductive AuthoredContextField
  | sender
  | value
  | blockNumber
  | blockTimestamp
  | gas
  | contractAddress
  deriving Repr

/-- Portable crosscall semantics. Target ABI and scheduling stay out of Authored syntax. -/
inductive AuthoredCrosscallMode
  | invoke
  | staticInvoke
  | delegateInvoke
  deriving Repr

/-- Authored-level lvalues (assignment targets). -/
inductive AuthoredLValue
  | local (name : String)
  | stateField (name : String)
  deriving Repr


/-- Authored-level expressions. -/
inductive AuthoredExpr
  | literal (lit : AuthoredLiteral)
  | peerRef (logicalId : String)
  | local (name : String)
  | stateRead (stateName : String)
  | mapRead (stateName : String) (key : AuthoredExpr)
  | arrayRead (stateName : String) (index : AuthoredExpr)
  | memoryArray (elementType : AuthoredType) (values : Array AuthoredExpr)
  | field (base : AuthoredExpr) (fieldName : String)
  | index (base : AuthoredExpr) (idx : AuthoredExpr)
  | unary (op : AuthoredUnaryOp) (arg : AuthoredExpr)
  | arith (op : AuthoredArithOp) (checked : Bool) (lhs rhs : AuthoredExpr)
  | compare (op : AuthoredCompareOp) (lhs rhs : AuthoredExpr)
  | boolAnd (lhs rhs : AuthoredExpr)
  | boolOr (lhs rhs : AuthoredExpr)
  | cast (to : AuthoredType) (arg : AuthoredExpr)
  | hash (arg : AuthoredExpr)
  | hashPair (lhs rhs : AuthoredExpr)
  | contextRead (field : AuthoredContextField)
  | nativeValue
  | hostCall (id : ProofForge.Target.HostOpId) (args : Array AuthoredExpr)
      (returnType : AuthoredType)
  | crosscall (mode : AuthoredCrosscallMode) (target method : AuthoredExpr)
      (args : Array AuthoredExpr) (returnType : AuthoredType)
  deriving Repr

/-- Authored-level statements. -/
inductive AuthoredStmt
  | bind (name : String) (type : AuthoredType) (value : AuthoredExpr)
  | mutBind (name : String) (type : AuthoredType) (value : AuthoredExpr)
  | assign (target : AuthoredLValue) (value : AuthoredExpr)
  | stateWrite (stateName : String) (value : AuthoredExpr)
  | mapWrite (stateName : String) (key value : AuthoredExpr)
  | arrayWrite (stateName : String) (index value : AuthoredExpr)
  | emit (eventName : String) (args : Array AuthoredExpr)
  | assert (condition : AuthoredExpr) (message : String)
  | assertError (condition : AuthoredExpr) (errorName : String) (args : Array AuthoredExpr)
  | revert (message : String)
  | revertError (errorName : String) (args : Array AuthoredExpr)
  | branch (condition : AuthoredExpr) (thenBody elseBody : Array AuthoredStmt)
  | boundedLoop (indexName : String) (start stopExclusive : Nat) (body : Array AuthoredStmt)
  | hostCallBind (name : String) (type : AuthoredType) (id : ProofForge.Target.HostOpId) (args : Array AuthoredExpr)
  | returnExpr (value : AuthoredExpr)
  | returnUnit
  deriving Repr

/-- Authored-level state declarations. -/
inductive AuthoredStateKind
  | scalar (type : AuthoredType)
  | map (keyType valueType : AuthoredType) (capacity : Option Nat)
  | fixedArray (element : AuthoredType) (length : Nat)
  | dynamicArray (element : AuthoredType)
  | record (typeName : String)
  deriving Repr, Inhabited

structure AuthoredStateDecl where
  name : String
  kind : AuthoredStateKind
  generated : Bool := false
  deriving Repr, Inhabited

/-- Authored-level event field. -/
structure AuthoredEventField where
  name : String
  type : AuthoredType
  indexed : Bool
  /-- Host ABI carrier override. This is interface metadata and never enters
  the executable Core module. -/
  abiWord? : Option String := none
  deriving Repr

structure AuthoredEventDecl where
  name : String
  fields : Array AuthoredEventField
  deriving Repr

/-- Authored-level entrypoint. -/
inductive AuthoredEntrypointKind
  | function
  | fallback
  | receive
  deriving Repr

inductive AuthoredMutability
  | call
  | view
  deriving Repr

structure AuthoredParam where
  name : String
  type : AuthoredType
  /-- Host ABI carrier override preserved only by Canonical Interface. -/
  abiWord? : Option String := none
  deriving Repr

structure AuthoredEntrypoint where
  name : String
  kind : AuthoredEntrypointKind
  mutability : AuthoredMutability
  selector? : Option String := none
  params : Array AuthoredParam
  retType : AuthoredType
  /-- Host ABI carrier override for the return word. -/
  returnAbiWord? : Option String := none
  body : Array AuthoredStmt
  span : Option SourceSpan := none
  deriving Repr

/-- Authored-level struct field. -/
structure AuthoredStructField where
  name : String
  type : AuthoredType
  deriving Repr

structure AuthoredStructDecl where
  name : String
  fields : Array AuthoredStructField
  deriving Repr

/-- Authored-level constructor binding. -/
inductive AuthoredConstructorBindingKind
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

structure AuthoredConstructorBinding where
  stateName : String
  paramName : String
  kind : AuthoredConstructorBindingKind
  deriving Repr

structure AuthoredConstructorParam where
  name : String
  abiType : String
  deriving Repr

/-- Authored-level error declaration. -/
structure AuthoredErrorDecl where
  name : String
  message : String
  params : Array AuthoredType
  deriving Repr

/-- Authored-level interface intent (maps to canonical MaterializationIntent). -/
inductive AuthoredIntentKind
  | module
  | state
  | entrypoint
  | capability
  deriving Repr

structure AuthoredIntent where
  kind : AuthoredIntentKind
  operation : ProofForge.Target.CapabilityOperation
  capability? : Option ProofForge.Target.Capability := none
  metadata : Array ProofForge.Target.TargetMetadata := #[]
  source? : Option String := none
  deriving Repr

/-- A complete authored contract before checked Canonical Core normalization. -/
structure AuthoredContract where
  name : String
  structs : Array AuthoredStructDecl
  state : Array AuthoredStateDecl
  events : Array AuthoredEventDecl
  errors : Array AuthoredErrorDecl
  entrypoints : Array AuthoredEntrypoint
  constructorParams : Array AuthoredConstructorParam
  constructorBindings : Array AuthoredConstructorBinding
  intents : Array AuthoredIntent := #[]
  deriving Repr

end ProofForge.Frontend.Authored
