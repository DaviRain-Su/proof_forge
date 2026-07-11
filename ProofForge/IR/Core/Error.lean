namespace ProofForge.IR.Core.Error

/- Surface → Core elaboration errors. Used by the legacy spike elaborator and
the future independent Surface normalizer. -/

inductive ElabError
  | unsupported (node : String)
  | typeMismatch (expected : String) (actual : String)
  | unknownState (name : String)
  | other (msg : String)
  deriving Repr

/- Canonical Core validation errors. These cover the checks performed by
`validateCanonical` on the typed ANF/CFG representation. -/

inductive ValidationError
  | duplicateName (name : String)
  | unknownType (name : String)
  | uninitializedState (name : String)
  | duplicateId (kind : String) (id : String)
  | unknownState (id : String)
  | unknownFunction (id : String)
  | unknownBlock (id : String)
  | unknownValue (id : String)
  | unknownEvent (id : String)
  | typeMismatch (expected : String) (actual : String)
  | invalidStoragePath (reason : String)
  | invalidLoopBound (reason : String)
  | unboundedLoop (block : String)
  | missingReturn (function : String)
  | useBeforeDefinition (id : String)
  | invalidTerminator (reason : String)
  | other (msg : String)
  deriving Repr

/- Capability and target-plan resolution errors. -/

inductive CapabilityError
  | unsupported (target : String) (construct : String)
  deriving Repr

end ProofForge.IR.Core.Error
