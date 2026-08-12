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

/-- One capability-scoped static proof chain for a selected nullary UInt64
    entry. The exact retained semantic program, public Plan/IR inspections,
    production base build, recognized Method/MethodIR alignment, and both
    method-scoped WAT/ABI renderer graphs are carried together. This is still
    static provenance: it neither parses emitted text nor defines or proves
    WAT, Wasm, or NEAR execution semantics. -/
structure CapabilityEntryStaticEmissionV1
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String) : Prop where
  retainedProgram :
    CompiledSemanticV1.semanticV1Of
      (ResolvedEngineeringBuildV1.compiledOf capability) = program
  planResult : planFromCapability capability = .ok plan
  irResult : irFromCapability capability = .ok ir
  buildResult : buildFromCapability capability = .ok files
  staticAlignment :
    ProductionNullaryUInt64ViewStaticAlignmentV1 program data plan ir.keys
      binding viewName method markerRegion fieldRegion methodIR
  baseEmission :
    EntryBaseEmissionV1 plan ir files entryIndex method methodIR
      watFile abiFile watMethodText abiMethodText

/-- Combine existing capability, static-alignment, lowering, and renderer
    graphs into one exact selected-entry witness. The theorem calls no alternate
    Plan constructor, lowering, emitter, or renderer. -/
theorem capabilityEntryStaticEmissionV1_of_graphs
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding : UInt64StateBindingV1)
    (viewName : String)
    (method : Method)
    (markerRegion fieldRegion : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hretained :
      CompiledSemanticV1.semanticV1Of
        (ResolvedEngineeringBuildV1.compiledOf capability) = program)
    (hplan : planFromCapability capability = .ok plan)
    (hir : irFromCapability capability = .ok ir)
    (hbuild : buildFromCapability capability = .ok files)
    (hstatic :
      ProductionNullaryUInt64ViewStaticAlignmentV1 program data plan ir.keys
        binding viewName method markerRegion fieldRegion methodIR)
    (hentry : plan.entries[entryIndex]? = some method)
    (hmethodIR : ir.methods[entryIndex + 1]? = some methodIR)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile) :
    ∃ watMethodText abiMethodText,
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText := by
  have hgraphs :=
    planAndIRFromCapability_eq_ok_graphsV1 capability plan ir hplan hir
  have hemissions : IREmissionV1 ir files := by
    obtain ⟨emittedPlan, emittedIR, _, hemittedIR, hemittedLowering,
        hemissions⟩ :=
      buildFromCapability_eq_ok_graphsV1 capability files hbuild
    have hemittedIREq : emittedIR = ir :=
      Except.ok.inj (hemittedIR.symm.trans hir)
    subst emittedIR
    have hemittedPlanEq : emittedPlan = plan :=
      (planIRLoweringV1_sourcePlan emittedPlan ir hemittedLowering).symm.trans
        hgraphs.1
    subst emittedPlan
    exact hemissions
  obtain ⟨watMethodText, abiMethodText, hbase⟩ :=
    irEmissionV1_entryBaseEmissionV1 plan ir files entryIndex method methodIR
      watFile abiFile hgraphs.2.2 hemissions hwatFile habiFile hentry hmethodIR
  exact ⟨watMethodText, abiMethodText, {
    retainedProgram := hretained
    planResult := hplan
    irResult := hir
    buildResult := hbuild
    staticAlignment := hstatic
    baseEmission := hbase
  }⟩

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Near
