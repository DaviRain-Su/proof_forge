namespace ProofForge.IR.Core

/- Identifiers are resolved numeric identities. A separate symbol table and
source map retain display names. -/

structure TypeId where value : Nat
structure StateId where value : Nat
structure FunctionId where value : Nat
structure EventId where value : Nat
structure EventFieldId where value : Nat
structure ErrorId where value : Nat
structure BlockId where value : Nat
structure ValueId where value : Nat

deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for TypeId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for StateId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for FunctionId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for EventId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for EventFieldId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for ErrorId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for BlockId
deriving instance BEq, ReflBEq, LawfulBEq, DecidableEq, Repr, Inhabited, Hashable for ValueId

end ProofForge.IR.Core
