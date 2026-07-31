import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Evm.LowerSemanticV1
import ProofForgeV2.Targets.Evm.ValidatePlanV1
import ProofForgeV2.Targets.Evm.EmitIRV1

/-!
# ProofForgeV2.Targets.Evm — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. Yul/ABI emission and
`irFromCapability`/`buildFromCapability` live in `EmitIRV1`.
`FinalizeV1` / `Keccak` remain separate submodules.
-/

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.evm

/-- Capability-gated public Plan entry (Wave 2 EVM pilot). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1, never residual alpha.
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .evm where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Evm
