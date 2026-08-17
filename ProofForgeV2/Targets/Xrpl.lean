import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Xrpl.LowerSemanticV1
import ProofForgeV2.Targets.Xrpl.ValidatePlanV1
import ProofForgeV2.Targets.Xrpl.PlanSchemaV1
import ProofForgeV2.Targets.Xrpl.EmitIRV1

/-!
# ProofForgeV2.Targets.Xrpl — public façade

Capability-gated source-only XRPL Bedrock Q0 target leaf (ADR-0049).

Consumes retained `SemanticProgramV1` via `ResolvedEngineeringBuildV1`.
Plan types and Semantic→Plan lowering live in `LowerSemanticV1`; plan
canonicity in `ValidatePlanV1`; structured IR + `{name}.rs` emission in
`EmitIRV1`; zero-tool finalization in `FinalizeV1`.

Q0 envelope: public UInt64 state/params; Unit/UInt64/Bool results;
single-block callables; pureFn inline (depth ≤ 64); checked `+`/`-`/`*`/`/`/`%`;
bare assert; zero-payload declared revert. No Int64, aggregates, events,
call/schedule, ContextRead, Commit, invariants, Escrow/Vault, Hooks, or
EVM sidechain. Zero-tool finalize — no rustc/bedrock/AlphaNet/mainnet.
-/

namespace ProofForgeV2.Targets.Xrpl

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.DescriptorDataV1

def descriptor : TargetDescriptor := DescriptorDataV1.xrpl

def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .xrpl where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Xrpl
