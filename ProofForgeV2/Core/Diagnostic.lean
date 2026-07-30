import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2

inductive CompileError where
  | unknownTarget (input : String)
  | targetNotImplemented (target : TargetKind)
  /-- V1 request unknown / wrong version / wrong digest / no exact support.
      Wire code `PF-REQ-UNSUPPORTED` (engineering resolver path; not SupportClaim). -/
  | unsupportedRequirementV1 (message : String)
  /-- Nonempty or unsatisfied requirement predicate.
      Wire code `PF-REQ-PRECONDITION`. Empty-predicates-only engineering slice. -/
  | requirementPrecondition (message : String)
  | invalidProgram (message : String)
  | resourceBound (message : String)
  | effectDisallowed (message : String)
  | visibilityViolation (message : String)
  | unknownEntry (name : String)
  | wrongArity (expected actual : Nat)
  | arithmeticOverflow
  | invalidState (name : String)
  | planInvariant (target : TargetKind) (message : String)
  | toolchainMissing (tool : String)
  | toolchainMismatch (tool : String) (expected actual : String)
  | artifactNondeployable (target : TargetKind) (reason : String)
  | unknownProfile (input : String)
  | registryDuplicate (message : String)
  | registryInvalid (message : String)
  deriving BEq, Repr

namespace CompileError

def code : CompileError → String
  | .unknownTarget .. => "PF-TARGET-UNKNOWN"
  | .targetNotImplemented .. => "PF-TARGET-NOT-IMPLEMENTED"
  | .unsupportedRequirementV1 .. => "PF-REQ-UNSUPPORTED"
  | .requirementPrecondition .. => "PF-REQ-PRECONDITION"
  | .invalidProgram .. => "PF-SRC-INVALID"
  | .resourceBound .. => "PF-BOUND-001"
  | .effectDisallowed .. => "PF-EFFECT-001"
  | .visibilityViolation .. => "PF-VIS-001"
  | .unknownEntry .. => "PF-SEM-UNKNOWN-ENTRY"
  | .wrongArity .. => "PF-SEM-WRONG-ARITY"
  | .arithmeticOverflow => "PF-SEM-ARITHMETIC-OVERFLOW"
  | .invalidState .. => "PF-SEM-INVALID-STATE"
  | .planInvariant .. => "PF-PLAN-INVARIANT"
  | .toolchainMissing .. => "PF-TOOLCHAIN-MISSING"
  | .toolchainMismatch .. => "PF-TOOLCHAIN-MISMATCH"
  | .artifactNondeployable .. => "PF-ARTIFACT-NONDEPLOYABLE"
  | .unknownProfile .. => "PF-PROFILE-UNKNOWN"
  | .registryDuplicate .. => "PF-REGISTRY-DUPLICATE"
  | .registryInvalid .. => "PF-REGISTRY-INVALID"

def message : CompileError → String
  | .unknownTarget input => s!"unknown target '{input}'"
  | .targetNotImplemented target => s!"target '{target}' has research metadata but no compiler implementation"
  | .unsupportedRequirementV1 detail => detail
  | .requirementPrecondition detail => detail
  | .invalidProgram detail => detail
  | .resourceBound detail => detail
  | .effectDisallowed detail => detail
  | .visibilityViolation detail => detail
  | .unknownEntry name => s!"unknown entry '{name}'"
  | .wrongArity expected actual => s!"expected {expected} arguments, received {actual}"
  | .arithmeticOverflow => "checked UInt64 arithmetic overflow"
  | .invalidState name => s!"unknown state cell '{name}'"
  | .planInvariant target detail => s!"invalid {target} plan: {detail}"
  | .toolchainMissing tool => s!"required toolchain '{tool}' is not available"
  | .toolchainMismatch tool expected actual =>
      s!"toolchain '{tool}' expected '{expected}', found '{actual}'"
  | .artifactNondeployable target reason => s!"{target} output is not deployable: {reason}"
  | .unknownProfile input => s!"unknown codegen profile '{input}'"
  | .registryDuplicate detail => detail
  | .registryInvalid detail => detail

def render (error : CompileError) : String :=
  s!"{error.code}: {error.message}"

end CompileError

abbrev CompileResult (α : Type) := Except CompileError α

end ProofForgeV2
