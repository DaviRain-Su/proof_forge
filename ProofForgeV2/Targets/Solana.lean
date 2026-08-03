import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Solana.LowerSemanticV1
import ProofForgeV2.Targets.Solana.ValidatePlanV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

/-!
# ProofForgeV2.Targets.Solana — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. IR emission and
`irFromCapability` live in `EmitIRV1`. Product `buildFromCapability` (plan vs
elf profile emit) and typed-IR → SBPF assembly (`.s` text) live in
`EmitSbpfAsmV1`. Registered `solana-sbpf-cpi-elf-v1` remains inert on this
product façade and is rejected before legacy Plan construction. #118's
`CpiPreflight*` modules are deliberately not imported here: they retain an
activation-denied authority and can only generate test-preactivation assembly,
not `OutputFile` or product artifacts. `FinalizeV1` remains a separate
submodule (plan: zero-tool; elf: locked `sbpf` → `{name}.so`).
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only.
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .solana where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Solana
