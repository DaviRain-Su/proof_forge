namespace ProofForge.IR.Core

/- Identifiers are resolved numeric identities. A separate symbol table and
source map retain display names. -/

structure TypeId where value : Nat
structure StateId where value : Nat
structure FunctionId where value : Nat
structure EventId where value : Nat
structure BlockId where value : Nat
structure ValueId where value : Nat

deriving instance BEq, Repr, Inhabited for TypeId
deriving instance BEq, Repr, Inhabited for StateId
deriving instance BEq, Repr, Inhabited for FunctionId
deriving instance BEq, Repr, Inhabited for EventId
deriving instance BEq, Repr, Inhabited for BlockId
deriving instance BEq, Repr, Inhabited for ValueId

end ProofForge.IR.Core
