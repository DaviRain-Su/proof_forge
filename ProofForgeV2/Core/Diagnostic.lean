namespace ProofForgeV2

inductive TargetId where
  | evm
  | solana
  | near
  | cosmwasm
  | soroban
  | icp
  | noir
  | openvm
  | aleo
  | psy
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace TargetId

def toString : TargetId → String
  | .evm => "evm"
  | .solana => "solana"
  | .near => "near"
  | .cosmwasm => "cosmwasm"
  | .soroban => "soroban"
  | .icp => "icp"
  | .noir => "noir"
  | .openvm => "openvm"
  | .aleo => "aleo"
  | .psy => "psy"

instance : ToString TargetId := ⟨toString⟩

def parse? : String → Option TargetId
  | "evm" => some .evm
  | "solana" => some .solana
  | "near" => some .near
  | "cosmwasm" => some .cosmwasm
  | "soroban" => some .soroban
  | "icp" => some .icp
  | "noir" => some .noir
  | "openvm" => some .openvm
  | "aleo" => some .aleo
  | "psy" => some .psy
  | _ => none

end TargetId

inductive ProgramRequirement where
  | persistentState
  | checkedArithmetic
  | transactionalRollback
  | synchronousCall
  | asynchronousWorkflow
  | privateWitness
  | eventEmission
  | callerContext
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace ProgramRequirement

def id : ProgramRequirement → String
  | .persistentState => "state.persistent"
  | .checkedArithmetic => "value.checked-arithmetic"
  | .transactionalRollback => "failure.atomic-rollback"
  | .synchronousCall => "effect.synchronous-call"
  | .asynchronousWorkflow => "effect.asynchronous-workflow"
  | .privateWitness => "disclosure.private-witness"
  | .eventEmission => "effect.event"
  | .callerContext => "context.caller"

instance : ToString ProgramRequirement := ⟨id⟩

end ProgramRequirement

inductive CompileError where
  | unknownTarget (input : String)
  | targetNotImplemented (target : TargetId)
  | unsupportedRequirement (requirement : ProgramRequirement) (target : TargetId)
  | invalidProgram (message : String)
  | unknownEntry (name : String)
  | wrongArity (expected actual : Nat)
  | arithmeticOverflow
  | invalidState (name : String)
  | planInvariant (target : TargetId) (message : String)
  | toolchainMissing (tool : String)
  | toolchainMismatch (tool : String) (expected actual : String)
  | artifactNondeployable (target : TargetId) (reason : String)
  deriving BEq, Repr

namespace CompileError

def code : CompileError → String
  | .unknownTarget .. => "PF-TARGET-UNKNOWN"
  | .targetNotImplemented .. => "PF-TARGET-NOT-IMPLEMENTED"
  | .unsupportedRequirement .. => "PF-REQ-UNSUPPORTED"
  | .invalidProgram .. => "PF-SRC-INVALID"
  | .unknownEntry .. => "PF-SEM-UNKNOWN-ENTRY"
  | .wrongArity .. => "PF-SEM-WRONG-ARITY"
  | .arithmeticOverflow => "PF-SEM-ARITHMETIC-OVERFLOW"
  | .invalidState .. => "PF-SEM-INVALID-STATE"
  | .planInvariant .. => "PF-PLAN-INVARIANT"
  | .toolchainMissing .. => "PF-TOOLCHAIN-MISSING"
  | .toolchainMismatch .. => "PF-TOOLCHAIN-MISMATCH"
  | .artifactNondeployable .. => "PF-ARTIFACT-NONDEPLOYABLE"

def message : CompileError → String
  | .unknownTarget input => s!"unknown target '{input}'"
  | .targetNotImplemented target => s!"target '{target}' has research metadata but no compiler implementation"
  | .unsupportedRequirement requirement target =>
      s!"target '{target}' cannot preserve requirement '{requirement}'"
  | .invalidProgram detail => detail
  | .unknownEntry name => s!"unknown entry '{name}'"
  | .wrongArity expected actual => s!"expected {expected} arguments, received {actual}"
  | .arithmeticOverflow => "checked UInt64 arithmetic overflow"
  | .invalidState name => s!"unknown state cell '{name}'"
  | .planInvariant target detail => s!"invalid {target} plan: {detail}"
  | .toolchainMissing tool => s!"required toolchain '{tool}' is not available"
  | .toolchainMismatch tool expected actual =>
      s!"toolchain '{tool}' expected '{expected}', found '{actual}'"
  | .artifactNondeployable target reason => s!"{target} output is not deployable: {reason}"

def render (error : CompileError) : String :=
  s!"{error.code}: {error.message}"

end CompileError

abbrev CompileResult (α : Type) := Except CompileError α

end ProofForgeV2
