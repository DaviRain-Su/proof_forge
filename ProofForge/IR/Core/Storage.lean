import ProofForge.IR.Core.Type

namespace ProofForge.IR.Core

/- Record field identity. -/

structure FieldId where value : Nat

deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for FieldId

/- State shapes describe the logical layout of a persistent state variable.
They contain no target allocation information such as EVM slots, Solana
account offsets, or target storage prefixes. -/

inductive StateShape
  | scalar (value : CoreType)
  | map (key value : CoreType) (capacity : Option Nat)
  | mapN (keys : Array CoreType) (value : CoreType) (capacity : Option Nat)
  | fixedArray (element : CoreType) (length : Nat)
  | dynamicArray (element : CoreType)
  | record (type : TypeId)
  deriving BEq, Repr

/- A storage path segment is either a map key, an array index, or a record
field. Segments are typed and validated against the root `StateShape`. -/

inductive StorageSegment
  | mapKey (key : ValueRef)
  | index (index : ValueRef)
  | field (field : FieldId)
  deriving BEq, Repr

/- A storage reference roots at a logical `StateId` and follows a typed path.
The expected result type is recorded so that loads/stores are fully typed. -/

structure StorageRef where
  root : StateId
  path : Array StorageSegment := #[]
  resultType : CoreType
  deriving BEq, Repr

end ProofForge.IR.Core
