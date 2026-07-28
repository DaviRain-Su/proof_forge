import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir
import ProofForgeV2.Targets.BuildSelectionV1

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Targets.BuildSelectionV1

/-- All static registrations in canonical TargetId storage order (product seed). -/
def allRegistrations : CompileResult (Array StaticBuildRegistrationV1) :=
  productRegistrations

def maturityLabel (target : TargetId) : CompileResult (Option String) := do
  let reg? ← registration? target
  return reg?.map (·.maturityLabel)

def descriptorForKind? : TargetKind → Option TargetDescriptor
  | .evm => some Evm.descriptor
  | .solana => some Solana.descriptor
  | .near => some Near.descriptor
  | .noir => some Noir.descriptor
  | _ => none

/-- Residual alpha descriptor join via product registration seed. -/
def descriptor? (target : TargetId) : CompileResult (Option TargetDescriptor) := do
  let reg? ← registration? target
  match reg? with
  | none => return none
  | some reg =>
      if reg.implemented then
        return descriptorForKind? reg.kind
      else
        return none

def checkSupport (selection : ResolvedBuildSelectionV1) (program : SemanticProgram) :
    CompileResult Unit := do
  let descriptor ← match descriptorForKind? selection.kind with
    | some descriptor => .ok descriptor
    | none => .error <| .targetNotImplemented selection.kind
  unless descriptor.targetId == selection.targetId do
    throw <| .registryInvalid "descriptor target identity diverges from resolved selection"
  unless descriptor.codegenProfile == selection.codegenProfile do
    throw <| .registryInvalid "descriptor codegen profile diverges from resolved selection"
  validateRequirementEnvelope program
  for requirement in program.requirements do
    unless descriptor.supportedRequirements.contains requirement do
      throw <| .unsupportedRequirement requirement selection.kind

/-- Aggregate materialization consumes a resolved build selection only. No raw
TargetId product overload. Dispatches residual alpha target pipelines by kind. -/
def materializeResult (selection : ResolvedBuildSelectionV1) (program : SemanticProgram) :
    CompileResult OutputSet := do
  checkSupport selection program
  match selection.kind with
  | .evm =>
      let resolved ← resolve .evm Evm.descriptor program
      let plan ← Evm.makePlan resolved
      let ir ← Evm.lower plan
      let files ← Evm.emit ir
      return makeOutput Evm.descriptor program false files
  | .solana =>
      let resolved ← resolve .solana Solana.descriptor program
      let plan ← Solana.makePlan resolved
      let ir ← Solana.lower plan
      let files ← Solana.emit ir
      return makeOutput Solana.descriptor program false files
  | .near =>
      let resolved ← resolve .near Near.descriptor program
      let plan ← Near.makePlan resolved
      let ir ← Near.lower plan
      let files ← Near.emit ir
      return makeOutput Near.descriptor program false files
  | .noir =>
      let resolved ← resolve .noir Noir.descriptor program
      let plan ← Noir.makePlan resolved
      let ir ← Noir.lower plan
      let files ← Noir.emit ir
      return makeOutput Noir.descriptor program false files
  | other => .error <| .targetNotImplemented other

def materialize (selection : ResolvedBuildSelectionV1) (program : SemanticProgram) :
    IO OutputSet :=
  match materializeResult selection program with
  | .ok output => pure output
  | .error error => throw <| IO.userError error.render

end ProofForgeV2.Targets
