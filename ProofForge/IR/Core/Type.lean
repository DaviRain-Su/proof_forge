import ProofForge.IR.Core.Id
import ProofForge.IR.Prelude

namespace ProofForge.IR.Core

abbrev UInt128 := BitVec 128

def maxLogicalCollectionLength : Nat := 1048576

/- Core types are target-neutral fixed-width scalar and reference types plus
structured aggregates. -/

inductive CoreType
  | unit | bool | u8 | u32 | u64 | u128
  | address
  | bytes | string | hash
  | fixedArray (element : CoreType) (length : Nat)
  | array (element : CoreType)
  | memoryRef (element : CoreType)
  | structType (type : TypeId)
  deriving BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable

/- A `ValueDef` names a value that is being defined by an instruction. A
`ValueRef` names a value that is being used. Both carry the value's Core type
so that every use site is typed. -/

structure ValueDef where
  id : ValueId
  type : CoreType
  deriving BEq, Repr, Inhabited

structure ValueRef where
  id : ValueId
  type : CoreType
  deriving BEq, Repr, Inhabited

/- Literals for every Core type. -/

inductive CoreLiteral
  | unitLit
  | boolLit (b : Bool)
  | u8Lit  (n : Nat)
  | u32Lit (n : Nat)
  | u64Lit (n : Nat)
  | u128Lit (n : Nat)
  | addressLit (s : String)
  | bytesLit (b : ByteArray)
  | stringLit (s : String)
  | hashLit (s : String)
  deriving BEq, Repr

/- Arithmetic can be wrapping or checked. The mode is preserved so that targets
without checked arithmetic can fail closed. -/

inductive OverflowMode
  | wrapping
  | checked
  deriving BEq, Repr

/- Pure unary and binary operations. Effectful operations are instructions. -/

inductive UnaryOp
  | not | neg
  deriving BEq, Repr

inductive ArithmeticOp
  | add | sub | mul | div | mod
  | and | or | xor | shl | shr
  deriving BEq, Repr

inductive CompareOp
  | eq | ne | lt | le | gt | ge
  deriving BEq, Repr

/- Context fields that every target plan must support or reject explicitly. -/

inductive ContextField
  | sender | value | blockNumber | blockTimestamp | epochHeight | randomSeed
  | origin | gas | contractAddress | accountId
  deriving BEq, DecidableEq, Repr

/- Reference to a structured error declared in the module's error schema. -/

structure CoreErrorRef where
  id : ErrorId
  args : Array ValueRef := #[]
  deriving BEq, Repr, Inhabited

end ProofForge.IR.Core
