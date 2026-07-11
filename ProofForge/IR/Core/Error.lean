import ProofForge.IR.Core.Id

namespace ProofForge.IR.Core.Error

/- Source locations are retained in `CanonicalEvidence.sourceMap`; validation
produces structured diagnostics and decoration adds a span without changing
semantics. -/

structure SourceLocation where
  file : String
  line : Nat
  column : Nat
  deriving Repr, BEq

/- Surface → Core elaboration errors. Used by the legacy spike elaborator and
the future independent Surface normalizer. -/

inductive ElabError
  | unsupported (node : String)
  | typeMismatch (expected : String) (actual : String)
  | unknownState (name : String)
  | other (msg : String)
  deriving Repr

/- Canonical Core validation error tags. Each error records its tag, the pass
that produced it, the semantic node where it occurred, and a reason. -/

inductive ValidationErrorTag
  | duplicateId
  | unknownReference
  | literalOutOfRange
  | invalidDominance
  | typeMismatch
  | invalidStoragePath
  | missingLoopBound
  | invalidReturn
  | invalidInterface
  | invalidMaterialization
  deriving BEq, Repr

structure ValidationError where
  tag : ValidationErrorTag
  pass : String
  function : Option ProofForge.IR.Core.FunctionId
  block : Option ProofForge.IR.Core.BlockId
  instruction : Option Nat
  sourceLocation : Option SourceLocation
  reason : String
  deriving Repr, BEq

def ValidationError.mkSimple (tag : ValidationErrorTag) (pass : String)
    (reason : String) : ValidationError := {
  tag := tag
  pass := pass
  function := none
  block := none
  instruction := none
  sourceLocation := none
  reason := reason
}

def ValidationError.withLocation (loc : SourceLocation) (e : ValidationError) :
    ValidationError := { e with sourceLocation := some loc }

/- Capability and target-plan resolution errors. -/

inductive CapabilityError
  | unsupported (target : String) (construct : String)
  deriving Repr

end ProofForge.IR.Core.Error
