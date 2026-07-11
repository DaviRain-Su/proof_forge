namespace ProofForge.IR.Core.Error

inductive ElabError
  | unsupported (node : String)
  | typeMismatch (expected : String) (actual : String)
  | other (msg : String)
  deriving Repr

inductive ValidationError
  | duplicateName (name : String)
  | unknownType (name : String)
  | uninitializedState (name : String)
  | other (msg : String)
  deriving Repr

inductive CapabilityError
  | unsupported (target : String) (construct : String)
  deriving Repr

end ProofForge.IR.Core.Error
