import ProofForge.IR.Prelude

namespace ProofForge.IR.Legacy.Core

abbrev UInt128 := BitVec 128

inductive CoreType
  | unit | bool | u8 | u32 | u64 | u128
  | address
  | bytes | string | hash
  | fixedArray (element : CoreType) (length : Nat)
  | array (element : CoreType)
  | structType (name : String)
  deriving BEq, Repr

inductive CoreLiteral
  | unitLit
  | boolLit (b : Bool)
  | u8Lit  (n : UInt8)
  | u32Lit (n : UInt32)
  | u64Lit (n : UInt64)
  | u128Lit (n : UInt128)
  | addressLit (s : String)
  | bytesLit (b : ByteArray)
  | stringLit (s : String)
  | hashLit (s : String)
  deriving BEq, Repr

inductive UnaryOp
  | not | neg
  deriving BEq, Repr

inductive BinaryOp
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or | xor | shl | shr
  deriving BEq, Repr

inductive ContextKind
  | sender | value | blockNumber | blockTimestamp | gas | contractAddress
  deriving BEq, Repr

-- Phase 2 extension point; keep opaque in Phase 1.
def HostOpId := String

deriving instance BEq, Repr for HostOpId

mutual

structure CrosscallSpec where
  family : String
  gas : Option CoreExpr
  value : Option CoreExpr
  deriving BEq, Repr

inductive StoragePath
  | scalar (slot : Nat)
  | mapKey (slot : Nat) (key : CoreExpr)
  | arrayIndex (slot : Nat) (idx : CoreExpr)
  | field (base : StoragePath) (field : String)
  deriving BEq, Repr

inductive LValue
  | local (name : String)
  | storage (path : StoragePath)
  | memory (base : CoreExpr) (offset : Nat) (ty : CoreType)
  deriving BEq, Repr

inductive CoreExpr
  | literal (val : CoreLiteral)
  | local (name : String)
  | fieldAccess (base : CoreExpr) (field : String)
  | arrayIndex (base : CoreExpr) (index : CoreExpr)
  | unary (op : UnaryOp) (arg : CoreExpr)
  | binary (op : BinaryOp) (lhs rhs : CoreExpr)
  | cast (fromTy toTy : CoreType) (arg : CoreExpr)
  | hash (arg : CoreExpr)
  | contextRead (kind : ContextKind)
  | storageRead (path : StoragePath)
  | crosscall (spec : CrosscallSpec) (args : List CoreExpr)
  | hostOpStub (op : HostOpId) (args : List CoreExpr)
  deriving BEq, Repr

inductive CoreEffect
  | storageRead  (path : StoragePath)
  | storageWrite (path : StoragePath) (val : CoreExpr)
  | memoryRead   (base : CoreExpr) (offset : Nat) (ty : CoreType)
  | memoryWrite  (base : CoreExpr) (offset : Nat) (val : CoreExpr)
  | eventEmit    (name : String) (args : List CoreExpr)
  | contextReadEffect (kind : ContextKind)
  | crosscallEffect (spec : CrosscallSpec) (args : List CoreExpr)
  | assert       (cond : CoreExpr) (msg : Option String)
  | revert       (msg : Option String)
  | hostOpStubEffect (op : HostOpId) (args : List CoreExpr)
  deriving BEq, Repr

inductive CoreStmt
  | letBind    (name : String) (ty : CoreType) (val : CoreExpr)
  | letMutBind (name : String) (ty : CoreType) (val : CoreExpr)
  | assign     (lhs : LValue) (rhs : CoreExpr)
  | assignOp   (lhs : LValue) (op : BinaryOp) (rhs : CoreExpr)
  | effect     (e : CoreEffect)
  | ifElse     (cond : CoreExpr) (thenBranch elseBranch : List CoreStmt)
  | boundedFor (iter : String) (bound : CoreExpr) (body : List CoreStmt)
  | whileLoop  (cond : CoreExpr) (body : List CoreStmt)
  | return     (val : CoreExpr)
  deriving BEq, Repr

end

structure CoreStruct where
  name : String
  fields : List (String × CoreType)
  deriving BEq, Repr

structure CoreStateDecl where
  name : String
  ty : CoreType
  initializer : Option CoreExpr
  deriving BEq, Repr

structure CoreEntrypoint where
  name : String
  params : List (String × CoreType)
  retTy : CoreType
  body : List CoreStmt
  deriving BEq, Repr

structure CoreEvent where
  name : String
  fields : List (String × CoreType)
  deriving BEq, Repr

structure CoreModule where
  name : String
  structs : List CoreStruct
  state : List CoreStateDecl
  entrypoints : List CoreEntrypoint
  events : List CoreEvent
  deriving Repr

end ProofForge.IR.Legacy.Core
