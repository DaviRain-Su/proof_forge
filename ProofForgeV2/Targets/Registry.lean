import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.Near
import ProofForgeV2.Targets.Noir
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- All static registrations in canonical TargetId storage order (product seed). -/
def allRegistrations : CompileResult (Array StaticBuildRegistrationV1) :=
  productRegistrations

def maturityLabel (target : TargetId) : CompileResult (Option String) := do
  let reg? ← registration? target
  return reg?.map (·.maturityLabel)

/-- Residual descriptor for an implemented kind (shared DescriptorDataV1). -/
def descriptorForKind? : TargetKind → Option TargetDescriptor :=
  DescriptorDataV1.descriptorForKind?

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

/-- Aggregate materialization consumes only the private engineering capability.
    Residual alpha is extracted **after** capability solely as temporary
    Plan-body data for existing target-owned Plan/IR algorithms
    (`CompiledProgramV1.alphaResidualOf`) — never as support authority.
    Support was decided at `resolveEngineeringRequirementsV1`.
    No residual Common resolve, no public makePlan, no
    supportedRequirements membership acceptance. Formal SupportClaim still
    pending; not SemanticProgramV1 native Plan lowering. -/
def materializeResult (capability : ResolvedEngineeringBuildV1) :
    CompileResult OutputSet := do
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  -- Temporary Plan-body data only (post-capability); not support authority.
  let program := CompiledProgramV1.alphaResidualOf compiled
  match selection.kind with
  | .evm =>
      let files ← Evm.buildFromCapability capability
      return makeOutput Evm.descriptor program false files
  | .solana =>
      let files ← Solana.buildFromCapability capability
      return makeOutput Solana.descriptor program false files
  | .near =>
      let files ← Near.buildFromCapability capability
      return makeOutput Near.descriptor program false files
  | .noir =>
      let files ← Noir.buildFromCapability capability
      return makeOutput Noir.descriptor program false files
  | other => .error <| .targetNotImplemented other

def materialize (capability : ResolvedEngineeringBuildV1) : IO OutputSet :=
  match materializeResult capability with
  | .ok output => pure output
  | .error error => throw <| IO.userError error.render

end ProofForgeV2.Targets
