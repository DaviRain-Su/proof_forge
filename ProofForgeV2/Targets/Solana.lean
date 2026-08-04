import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Solana.LowerSemanticV1
import ProofForgeV2.Targets.Solana.ValidatePlanV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.MaterializationV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

/-!
# ProofForgeV2.Targets.Solana — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. Legacy IR emission lives in
`EmitIRV1` (`legacyIrFromCapabilityV1`).

#125 materializer integration (`MaterializationV1`):
* Tagged sum `SolanaPlanFromCapabilityV1` / `SolanaIRFromCapabilityV1`
  (aliases `SolanaMaterializationPlanV1` / `SolanaMaterializationIRV1`)
* Exhaustive profile dispatch in `planFromCapability` / `irFromCapability`
  (plan-v1 + elf-v1 → legacy; cpi-elf-v1 → product CPI; unknown → FC)
* Product core entries `productPlanFromCapabilityV1` /
  `productIrFromCapabilityV1` / `productPlanDigestFromCapabilityV1` /
  `productBaseFilesFromCapabilityV1` under `CpiV1`
* `buildFromCapability` in `EmitSbpfAsmV1` mirrors the same exhaustive branch
* Single `Materializer .solana` associated types = tagged sums (no second
  TargetKind)

`FinalizeV1`: plan profile zero-tool; elf + cpi-elf locked `sbpf` with CPI
pre-IO revalidation of capability/profile/base files/planDigest.
Legacy ExternalCall/Schedule remain unreachable and byte-stable on no-call
programs. Default profile remains `solana-sbpf-plan-v1`.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Materializer associated types are the #125 tagged sums (legacy | cpi).
    Aggregate Registry still sole-mints via one `.solana` kind dispatch. -/
instance : Materializer .solana where
  Plan := SolanaPlanFromCapabilityV1
  TargetIR := SolanaIRFromCapabilityV1

end ProofForgeV2.Targets.Solana
