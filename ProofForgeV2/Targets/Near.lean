import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Near.LowerSemanticV1
import ProofForgeV2.Targets.Near.ValidatePlanV1
import ProofForgeV2.Targets.Near.PlanSchemaV1
import ProofForgeV2.Targets.Near.EmitIRV1
import ProofForgeV2.Targets.Near.StaticAlignmentV1

/-!
# ProofForgeV2.Targets.Near — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. IR emission and
`irFromCapability`/`buildFromCapability` live in `EmitIRV1`.
`FinalizeV1` remains a separate submodule.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only.
    Authority chain: semanticV1Of → makePlanFromSemanticV1 → validatePlan
    (validateSemanticProgramV1 already ran at capability mint). -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

/-- Successful public Plan and IR inspection results for one capability are
    connected to the same production materialization and private lowering. -/
theorem planAndIRFromCapability_eq_ok_graphsV1
    (capability : ResolvedEngineeringBuildV1) (plan : Plan) (ir : IR)
    (hplan : planFromCapability capability = .ok plan)
    (hir : irFromCapability capability = .ok ir) :
    ir.sourcePlan = plan ∧
    KeyRegionsV1 plan ir.keys ∧
    PlanIRLoweringV1 plan ir := by
  obtain ⟨loweredPlan, hloweredPlan, hgraph⟩ :=
    irFromCapability_eq_ok_graphsV1 capability ir hir
  have hmaterialized : materializePlanFromCapabilityV1 capability = .ok plan := by
    cases hraw : materializePlanFromCapabilityV1 capability with
    | error error =>
        simp [planFromCapability, hraw, Bind.bind, Except.bind] at hplan
    | ok rawPlan =>
        cases hvalidate : validatePlan rawPlan with
        | error error =>
            simp [planFromCapability, hraw, hvalidate, Bind.bind, Except.bind] at hplan
        | ok _ =>
            have : rawPlan = plan := by
              have hok : (Except.ok rawPlan : CompileResult Plan) = .ok plan := by
                simpa [planFromCapability, hraw, hvalidate, Bind.bind, Except.bind,
                  Pure.pure, Except.pure] using hplan
              exact Except.ok.inj hok
            simpa [this] using hraw
  have hsame : loweredPlan = plan := by
    exact Except.ok.inj (hloweredPlan.symm.trans hmaterialized)
  subst loweredPlan
  exact ⟨planIRLoweringV1_sourcePlan plan ir hgraph,
    planIRLoweringV1_keyRegions plan ir hgraph, hgraph⟩

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Near
