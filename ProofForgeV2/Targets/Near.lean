import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Near.LowerSemanticV1
import ProofForgeV2.Targets.Near.ValidatePlanV1
import ProofForgeV2.Targets.Near.PlanSchemaV1
import ProofForgeV2.Targets.Near.EmitIRV1
import ProofForgeV2.Targets.Near.StaticAlignmentV1
import ProofForgeV2.Targets.Near.MethodSemanticsV1
import ProofForgeV2.Targets.Near.WATSemanticsV1

/-!
# ProofForgeV2.Targets.Near — public façade

Plan types and Semantic→Plan lowering live in `LowerSemanticV1`
(`materializePlanFromCapabilityV1` → private `makePlanFromSemanticV1`, with
`semanticV1Of` / `validateSemanticProgramV1` comments on the carrier path).
Plan canonicity lives in `ValidatePlanV1`. IR emission and
`irFromCapability`/`buildFromCapability` live in `EmitIRV1`.
The first bounded target recipe and typed-WAT execution semantics live in
`MethodSemanticsV1` and `WATSemanticsV1`; they are not Wasm binary or complete
NEAR protocol semantics.
`FinalizeV1` remains a separate submodule.
-/

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1

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

/-- Capability-scoped production chain for the selected two-UInt64 initializer.
    It binds retained semantic data, Plan/IR/build results, exact initializer
    alignment, and the sole WAT/ABI renderer graphs at method index zero. -/
structure CapabilityInitializerStaticEmissionV1
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
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
    ProductionNullaryZeroTwoUInt64InitializerStaticAlignmentV1 program data plan
      ir.keys binding0 binding1 initializerName method markerRegion field0Region
        field1Region methodIR
  baseEmission :
    InitializerBaseEmissionV1 plan ir files method methodIR watFile abiFile
      watMethodText abiMethodText

/-- Combine the existing capability, production lowering, exact initializer
    alignment, and renderer graphs. No alternate constructor or emitter is
    introduced. -/
theorem capabilityInitializerStaticEmissionV1_of_graphs
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hretained :
      CompiledSemanticV1.semanticV1Of
        (ResolvedEngineeringBuildV1.compiledOf capability) = program)
    (hplan : planFromCapability capability = .ok plan)
    (hir : irFromCapability capability = .ok ir)
    (hbuild : buildFromCapability capability = .ok files)
    (hstatic :
      ProductionNullaryZeroTwoUInt64InitializerStaticAlignmentV1 program data
        plan ir.keys binding0 binding1 initializerName method markerRegion
          field0Region field1Region methodIR)
    (hinitializer : plan.initializer = method)
    (hmethodIR : ir.methods[0]? = some methodIR)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile) :
    ∃ watMethodText abiMethodText,
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText := by
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
    irEmissionV1_initializerBaseEmissionV1 plan ir files method methodIR watFile
      abiFile hgraphs.2.2 hemissions hwatFile habiFile hinitializer hmethodIR
  exact ⟨watMethodText, abiMethodText, {
    retainedProgram := hretained
    planResult := hplan
    irResult := hir
    buildResult := hbuild
    staticAlignment := hstatic
    baseEmission := hbase
  }⟩

/-- The capability-selected initializer is byte-for-byte rendered from its
    validated typed-WAT sequence by the sole production renderer. -/
theorem capabilityInitializerStaticEmissionV1_validatedMethodWATEmissionV1
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hdeposit :
      ir.memory.depositOffset + 16 ≤
        ir.memory.minPages * wasmPageBytes)
    (hvalue :
      ir.memory.valueOffset + 8 ≤
        ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyMethodWATEmissionV1 ir 0 methodIR watFile.contents
      watMethodText
      (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
        field0Region field1Region plan.storage.markerValue) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
          markerRegion field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_nullaryZeroTwoUInt64Initializer ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  refine ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir 0 methodIR
      watFile.contents watMethodText _ hchain.baseEmission.watMethodEmission
        hlower,
    ?_
  ⟩
  rw [halignment.methodIRExact]
  exact validateReadOnlyWATMethodV1_nullaryZeroTwoUInt64Initializer ir.keys
    ir.registers ir.memory markerRegion field0Region field1Region
      plan.storage.markerValue
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys 0 markerRegion
        hchain.staticAlignment.markerLookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding0.physicalFieldIndex + 1) field0Region
          hchain.staticAlignment.field0Lookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding1.physicalFieldIndex + 1) field1Region
          hchain.staticAlignment.field1Lookup)
      hdeposit hvalue

/-- The same initializer witness owns the complete validated production module
    surrounding its exact typed-WAT fragment. This closes the capability-level
    framing asymmetry with the selected entry recipes; it still stops before
    `wat2wasm`, Wasm binary execution, and NEAR host semantics. -/
theorem capabilityInitializerStaticEmissionV1_validatedWATModule
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hdeposit :
      ir.memory.depositOffset + 16 ≤ ir.memory.minPages * wasmPageBytes)
    (hvalue :
      ir.memory.valueOffset + 8 ≤ ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyWATModuleEmissionV1 ir 0 methodIR watFile.contents
      watMethodText
      (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
        field0Region field1Region plan.storage.markerValue) := by
  exact validatedReadOnlyWATModuleEmissionV1_of_irEmissionV1 ir files 0 methodIR
    watFile.contents watMethodText _ hchain.baseEmission.irEmission
      (capabilityInitializerStaticEmissionV1_validatedMethodWATEmissionV1
        capability program data plan ir files binding0 binding1 initializerName
        method markerRegion field0Region field1Region methodIR watFile abiFile
        watMethodText abiMethodText hchain hdeposit hvalue)

/-- Under one pre-storage observation, the capability-selected production
    initializer MethodIR and its exact typed-WAT fragment commit the same two
    UInt64 zero rows and final initialized marker. -/
theorem capabilityInitializerStaticEmissionV1_execute
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker : storage.lookup markerRegion.key = none)
    (hfield0 : storage.lookup field0Region.key = none)
    (hfield1 : storage.lookup field1Region.key = none)
    (hfield10 : field1Region.key ≠ field0Region.key)
    (hmarker0 : markerRegion.key ≠ field0Region.key)
    (hmarker1 : markerRegion.key ≠ field1Region.key) :
    ReadOnlyMethodWATEmissionV1 ir 0 methodIR watFile.contents watMethodText
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) ∧
      executeMethodV1 methodIR ByteArray.empty 0 0 storage =
        .returned none
          (zeroTwoUInt64InitializerPostStorageV1 storage markerRegion
            field0Region field1Region plan.storage.markerValue) ∧
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty 0 0 storage =
          .returned none
            (zeroTwoUInt64InitializerPostStorageV1 storage markerRegion
              field0Region field1Region plan.storage.markerValue) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
          markerRegion field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_nullaryZeroTwoUInt64Initializer ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  refine ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir 0 methodIR
      watFile.contents watMethodText _ hchain.baseEmission.watMethodEmission
        hlower,
    ?_,
    ?_
  ⟩
  · exact executeMethodV1_of_nullaryZeroTwoUInt64InitializerStaticAlignment data
      plan.storage binding0 binding1 initializerName method markerRegion
      field0Region field1Region methodIR storage halignment hmarker hfield0
      hfield1 hfield10 hmarker0 hmarker1
  · exact executeMethodWATV1_nullaryZeroTwoUInt64Initializer ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
      storage hmarker hfield0 hfield1 hfield10 hmarker0 hmarker1

/-- Nonempty initializer input fails before either bounded target evaluator can
    inspect or change storage; their canonical observations agree on rollback. -/
theorem capabilityInitializerStaticEmissionV1_nonemptyInputFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (input : ByteArray)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hinput : UInt64.ofNat input.size ≠ 0) :
    executeMethodV1 methodIR input 0 0 storage =
        .trapped .inputLengthMismatch ∧
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        input 0 0 storage = .trapped .trap ∧
      observeMethodV1 methodIR input 0 0 storage =
        observeMethodWATV1 initializerName 2
          (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
            markerRegion field0Region field1Region plan.storage.markerValue)
          input 0 0 storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR input 0 0 storage =
        .trapped .inputLengthMismatch := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonempty_input
      initializerName markerRegion field0Region field1Region
      plan.storage.markerValue input storage (by
        intro hsize
        simp [hsize] at hinput)
  have hwat :
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        input 0 0 storage = .trapped .trap :=
    executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonempty_input
      ir.registers ir.memory markerRegion field0Region field1Region
      plan.storage.markerValue input storage hinput
  have hname : methodIR.name = initializerName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- Re-initialization traps in both bounded target semantics before any write;
    their canonical observations expose the original storage snapshot. -/
theorem capabilityInitializerStaticEmissionV1_doubleInitFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (markerBytes : ByteArray)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker : storage.lookup markerRegion.key = some markerBytes) :
    executeMethodV1 methodIR ByteArray.empty 0 0 storage =
        .trapped .storageAlreadyPresent ∧
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty 0 0 storage = .trapped .trap ∧
      observeMethodV1 methodIR ByteArray.empty 0 0 storage =
        observeMethodWATV1 initializerName 2
          (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
            markerRegion field0Region field1Region plan.storage.markerValue)
          ByteArray.empty 0 0 storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR ByteArray.empty 0 0 storage =
        .trapped .storageAlreadyPresent := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_nullaryZeroTwoUInt64Initializer_double_init
      initializerName markerRegion field0Region field1Region
      plan.storage.markerValue markerBytes storage hmarker
  have hwat :
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty 0 0 storage = .trapped .trap :=
    executeMethodWATV1_nullaryZeroTwoUInt64Initializer_double_init ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
      markerBytes storage hmarker
  have hname : methodIR.name = initializerName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- A nonzero low attached-deposit limb fails before either bounded evaluator
    can inspect or change storage, with the same canonical rollback view. -/
theorem capabilityInitializerStaticEmissionV1_nonzeroDepositFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (depositLow : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hdeposit : depositLow ≠ 0) :
    executeMethodV1 methodIR ByteArray.empty depositLow 0 storage =
        .trapped .attachedDepositNotZero ∧
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty depositLow 0 storage = .trapped .trap ∧
      observeMethodV1 methodIR ByteArray.empty depositLow 0 storage =
        observeMethodWATV1 initializerName 2
          (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
            markerRegion field0Region field1Region plan.storage.markerValue)
          ByteArray.empty depositLow 0 storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR ByteArray.empty depositLow 0 storage =
        .trapped .attachedDepositNotZero := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit
      initializerName markerRegion field0Region field1Region
      plan.storage.markerValue depositLow storage hdeposit
  have hwat :
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty depositLow 0 storage = .trapped .trap :=
    executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit
      ir.registers ir.memory markerRegion field0Region field1Region
      plan.storage.markerValue depositLow storage hdeposit
  have hname : methodIR.name = initializerName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- A nonzero high attached-deposit limb is rejected at the second u128 check
    and has the same no-write observation in both bounded target semantics. -/
theorem capabilityInitializerStaticEmissionV1_nonzeroDepositHighFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (binding0 binding1 : UInt64StateBindingV1)
    (initializerName : String)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (depositHigh : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityInitializerStaticEmissionV1 capability program data plan ir
        files binding0 binding1 initializerName method markerRegion field0Region
          field1Region methodIR watFile abiFile watMethodText abiMethodText)
    (hdeposit : depositHigh ≠ 0) :
    executeMethodV1 methodIR ByteArray.empty 0 depositHigh storage =
        .trapped .attachedDepositNotZero ∧
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty 0 depositHigh storage = .trapped .trap ∧
      observeMethodV1 methodIR ByteArray.empty 0 depositHigh storage =
        observeMethodWATV1 initializerName 2
          (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory
            markerRegion field0Region field1Region plan.storage.markerValue)
          ByteArray.empty 0 depositHigh storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR ByteArray.empty 0 depositHigh storage =
        .trapped .attachedDepositNotZero := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
      initializerName markerRegion field0Region field1Region
      plan.storage.markerValue depositHigh storage hdeposit
  have hwat :
      executeMethodWATV1 2
        (nullaryZeroTwoUInt64InitializerWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        ByteArray.empty 0 depositHigh storage = .trapped .trap :=
    executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
      ir.registers ir.memory markerRegion field0Region field1Region
      plan.storage.markerValue depositHigh storage hdeposit
  have hname : methodIR.name = initializerName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- Capability-scoped production chain for the bounded unary checked-add
    entry. It binds one retained semantic program, Plan/IR/build results, the
    exact two-UInt64 deposit alignment, and the sole WAT/ABI renderer graphs.
    This is reusable target provenance, not a contract-specific evaluator. -/
structure CapabilityUnaryAddTwoUInt64DepositStaticEmissionV1
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
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
    ProductionUnaryAddTwoUInt64DepositStaticAlignmentV1 program data plan
      ir.keys binding0 binding1 entryName parameterName parameterSourceId method
        markerRegion field0Region field1Region methodIR
  baseEmission :
    EntryBaseEmissionV1 plan ir files entryIndex method methodIR watFile abiFile
      watMethodText abiMethodText

/-- Combine the existing capability, production lowering, deposit alignment,
    and renderer graphs. No alternate Plan, MethodIR, or renderer is minted. -/
theorem capabilityUnaryAddTwoUInt64DepositStaticEmissionV1_of_graphs
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hretained :
      CompiledSemanticV1.semanticV1Of
        (ResolvedEngineeringBuildV1.compiledOf capability) = program)
    (hplan : planFromCapability capability = .ok plan)
    (hir : irFromCapability capability = .ok ir)
    (hbuild : buildFromCapability capability = .ok files)
    (hstatic :
      ProductionUnaryAddTwoUInt64DepositStaticAlignmentV1 program data plan
        ir.keys binding0 binding1 entryName parameterName parameterSourceId
          method markerRegion field0Region field1Region methodIR)
    (hentry : plan.entries[entryIndex]? = some method)
    (hmethodIR : ir.methods[entryIndex + 1]? = some methodIR)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile) :
    ∃ watMethodText abiMethodText,
      CapabilityUnaryAddTwoUInt64DepositStaticEmissionV1 capability program data
        plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText := by
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

/-- The selected production deposit method is byte-for-byte rendered from its
    exact typed-WAT lowering and validated within the complete production
    module framing. This stops before Wasm binary and NEAR runtime semantics. -/
theorem capabilityUnaryAddTwoUInt64DepositStaticEmissionV1_validatedWATModule
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityUnaryAddTwoUInt64DepositStaticEmissionV1 capability program data
        plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hinput :
      ir.memory.inputOffset + 8 ≤ ir.memory.minPages * wasmPageBytes)
    (hdeposit :
      ir.memory.depositOffset + 16 ≤ ir.memory.minPages * wasmPageBytes)
    (hvalue :
      ir.memory.valueOffset + 8 ≤ ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyWATModuleEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
      (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
        field0Region field1Region plan.storage.markerValue) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_unaryAddTwoUInt64Deposit ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  have hvalidated :
      ValidatedReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
        watFile.contents watMethodText
        (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) := by
    refine ⟨
      readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
        methodIR watFile.contents watMethodText _
          hchain.baseEmission.watMethodEmission hlower,
      ?_
    ⟩
    rw [halignment.methodIRExact]
    exact validateMethodWATV1_unaryAddTwoUInt64Deposit ir.keys ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys 0 markerRegion
        hchain.staticAlignment.markerLookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding0.physicalFieldIndex + 1) field0Region
          hchain.staticAlignment.field0Lookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding1.physicalFieldIndex + 1) field1Region
          hchain.staticAlignment.field1Lookup)
      hinput hdeposit hvalue
  exact validatedReadOnlyWATModuleEmissionV1_of_irEmissionV1 ir files
    (entryIndex + 1) methodIR watFile.contents watMethodText _
      hchain.baseEmission.irEmission hvalidated

/-- Under one shared storage observation, the capability-selected production
    MethodIR and its exact typed-WAT fragment return the same checked-add bytes
    and the same two-row post-storage. -/
theorem capabilityUnaryAddTwoUInt64DepositStaticEmissionV1_execute
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityUnaryAddTwoUInt64DepositStaticEmissionV1 capability program data
        plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker :
      storage.lookup markerRegion.key =
        some (encodeU64le plan.storage.markerValue))
    (hfield0 :
      storage.lookup field0Region.key = some (encodeU64le before0))
    (hfield1 :
      storage.lookup field1Region.key = some (encodeU64le before1))
    (hfield10 : field1Region.key ≠ field0Region.key)
    (hinputValue : ir.memory.inputOffset ≠ ir.memory.valueOffset)
    (hinputDepositLow : ir.memory.inputOffset ≠ ir.memory.depositOffset)
    (hinputDepositHigh :
      ir.memory.inputOffset ≠ ir.memory.depositOffset + 8)
    (hadd0 : before0.toNat + amount.toNat < 2 ^ 64)
    (hadd1 : before1.toNat + amount.toNat < 2 ^ 64) :
    ReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
        watFile.contents watMethodText
        (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) ∧
      executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .returned (some (checkedAddUInt64BytesV1 before1 amount))
          (unaryAddTwoUInt64DepositPostStorageV1 storage field0Region
            field1Region before0 before1 amount) ∧
      executeMethodWATV1 7
        (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage =
          .returned (some (checkedAddUInt64BytesV1 before1 amount))
            (unaryAddTwoUInt64DepositPostStorageV1 storage field0Region
              field1Region before0 before1 amount) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (unaryAddTwoUInt64DepositWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_unaryAddTwoUInt64Deposit ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  refine ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
      methodIR watFile.contents watMethodText _
        hchain.baseEmission.watMethodEmission hlower,
    ?_,
    ?_
  ⟩
  · exact executeMethodV1_of_unaryAddTwoUInt64DepositStaticAlignment data
      plan.storage binding0 binding1 entryName parameterName parameterSourceId
      method markerRegion field0Region field1Region methodIR before0 before1
      amount storage halignment hmarker hfield0 hfield1 hfield10 hadd0 hadd1
  · exact executeMethodWATV1_unaryAddTwoUInt64Deposit ir.registers ir.memory
      markerRegion field0Region field1Region plan.storage.markerValue before0
      before1 amount storage hmarker hfield0 hfield1 hfield10 hinputValue
      hinputDepositLow hinputDepositHigh hadd0 hadd1

/-- Capability-scoped production chain for the bounded guarded checked-sub
    entry. It binds the retained semantic program, production Plan/IR/build,
    exact withdraw alignment, and the sole WAT/ABI renderer graphs. -/
structure CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
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
    ProductionGuardedSubTwoUInt64WithdrawStaticAlignmentV1 program data plan
      ir.keys binding0 binding1 entryName parameterName parameterSourceId method
        markerRegion field0Region field1Region methodIR
  baseEmission :
    EntryBaseEmissionV1 plan ir files entryIndex method methodIR watFile abiFile
      watMethodText abiMethodText

/-- Combine the existing production graphs and exact withdraw alignment without
    constructing another Plan, MethodIR, lowering, or renderer. -/
theorem capabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1_of_graphs
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (hretained :
      CompiledSemanticV1.semanticV1Of
        (ResolvedEngineeringBuildV1.compiledOf capability) = program)
    (hplan : planFromCapability capability = .ok plan)
    (hir : irFromCapability capability = .ok ir)
    (hbuild : buildFromCapability capability = .ok files)
    (hstatic :
      ProductionGuardedSubTwoUInt64WithdrawStaticAlignmentV1 program data plan
        ir.keys binding0 binding1 entryName parameterName parameterSourceId
          method markerRegion field0Region field1Region methodIR)
    (hentry : plan.entries[entryIndex]? = some method)
    (hmethodIR : ir.methods[entryIndex + 1]? = some methodIR)
    (hwatFile : files[0]? = some watFile)
    (habiFile : files[1]? = some abiFile) :
    ∃ watMethodText abiMethodText,
      CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1 capability program
        data plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText := by
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

/-- The selected production withdraw is rendered from its exact typed-WAT
    lowering and validated inside the complete production module framing. -/
theorem capabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1_validatedWATModule
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1 capability program
        data plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hinput :
      ir.memory.inputOffset + 8 ≤ ir.memory.minPages * wasmPageBytes)
    (hdeposit :
      ir.memory.depositOffset + 16 ≤ ir.memory.minPages * wasmPageBytes)
    (hvalue :
      ir.memory.valueOffset + 8 ≤ ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyWATModuleEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
      (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
        field0Region field1Region plan.storage.markerValue) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory
          markerRegion field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_guardedSubTwoUInt64Withdraw ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  have hvalidated :
      ValidatedReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
        watFile.contents watMethodText
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) := by
    refine ⟨
      readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
        methodIR watFile.contents watMethodText _
          hchain.baseEmission.watMethodEmission hlower,
      ?_
    ⟩
    rw [halignment.methodIRExact]
    exact validateMethodWATV1_guardedSubTwoUInt64Withdraw ir.keys ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys 0 markerRegion
        hchain.staticAlignment.markerLookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding0.physicalFieldIndex + 1) field0Region
          hchain.staticAlignment.field0Lookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding1.physicalFieldIndex + 1) field1Region
          hchain.staticAlignment.field1Lookup)
      hinput hdeposit hvalue
  exact validatedReadOnlyWATModuleEmissionV1_of_irEmissionV1 ir files
    (entryIndex + 1) methodIR watFile.contents watMethodText _
      hchain.baseEmission.irEmission hvalidated

/-- Under one shared storage observation, the capability-selected production
    MethodIR and exact typed-WAT withdraw both return Unit and the same checked
    subtraction post-storage. -/
theorem capabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1_execute
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1 capability program
        data plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker :
      storage.lookup markerRegion.key =
        some (encodeU64le plan.storage.markerValue))
    (hfield0 :
      storage.lookup field0Region.key = some (encodeU64le before0))
    (hfield1 :
      storage.lookup field1Region.key = some (encodeU64le before1))
    (hfield10 : field1Region.key ≠ field0Region.key)
    (hinputValue : ir.memory.inputOffset ≠ ir.memory.valueOffset)
    (hinputDepositLow : ir.memory.inputOffset ≠ ir.memory.depositOffset)
    (hinputDepositHigh :
      ir.memory.inputOffset ≠ ir.memory.depositOffset + 8)
    (hguard0 : amount.toNat ≤ before0.toNat)
    (hguard1 : amount.toNat ≤ before1.toNat) :
    ReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
        watFile.contents watMethodText
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue) ∧
      executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .returned none
          (guardedSubTwoUInt64WithdrawPostStorageV1 storage field0Region
            field1Region before0 before1 amount) ∧
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage =
          .returned none
            (guardedSubTwoUInt64WithdrawPostStorageV1 storage field0Region
              field1Region before0 before1 amount) := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hlower :
      lowerMethodWATOperationsV1 ir.registers ir.memory methodIR.operations =
        some (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory
          markerRegion field0Region field1Region plan.storage.markerValue) := by
    rw [halignment.methodIRExact]
    exact lowerMethodWATOperationsV1_guardedSubTwoUInt64Withdraw ir.registers
      ir.memory markerRegion field0Region field1Region plan.storage.markerValue
  refine ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
      methodIR watFile.contents watMethodText _
        hchain.baseEmission.watMethodEmission hlower,
    ?_,
    ?_
  ⟩
  · exact executeMethodV1_of_guardedSubTwoUInt64WithdrawStaticAlignment data
      plan.storage binding0 binding1 entryName parameterName parameterSourceId
      method markerRegion field0Region field1Region methodIR before0 before1
      amount storage halignment hmarker hfield0 hfield1 hfield10 hguard0 hguard1
  · exact executeMethodWATV1_guardedSubTwoUInt64Withdraw ir.registers ir.memory
      markerRegion field0Region field1Region plan.storage.markerValue before0
      before1 amount storage hmarker hfield0 hfield1 hfield10 hinputValue
      hinputDepositLow hinputDepositHigh hguard0 hguard1

/-- The capability-selected production withdraw traps in both bounded target
    semantics when its first guard fails. Although the evaluator-specific trap
    codes differ, their canonical observations agree and roll storage back to
    the supplied pre-state. -/
theorem capabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1_firstGuardFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (before0 amount : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1 capability program
        data plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker :
      storage.lookup markerRegion.key =
        some (encodeU64le plan.storage.markerValue))
    (hfield0 :
      storage.lookup field0Region.key = some (encodeU64le before0))
    (hinputValue : ir.memory.inputOffset ≠ ir.memory.valueOffset)
    (hinputDepositLow : ir.memory.inputOffset ≠ ir.memory.depositOffset)
    (hinputDepositHigh :
      ir.memory.inputOffset ≠ ir.memory.depositOffset + 8)
    (hguard0 : ¬ amount.toNat ≤ before0.toNat) :
    executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .trapped .assertionFailed ∧
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage = .trapped .trap ∧
      observeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        observeMethodWATV1 entryName 12
          (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
            field0Region field1Region plan.storage.markerValue)
          (encodeU64le amount) 0 0 storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .trapped .assertionFailed := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_guardedSubTwoUInt64Withdraw_first_guard_failure
      entryName parameterName parameterSourceId markerRegion field0Region
        field1Region plan.storage.markerValue before0 amount storage hmarker
          hfield0 hguard0
  have hwat :
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage = .trapped .trap :=
    executeMethodWATV1_guardedSubTwoUInt64Withdraw_first_guard_failure
      ir.registers ir.memory markerRegion field0Region field1Region
        plan.storage.markerValue before0 amount storage hmarker hfield0
          hinputValue hinputDepositLow hinputDepositHigh hguard0
  have hname : methodIR.name = entryName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- The second withdraw guard has the same capability-scoped failure agreement:
    both bounded target semantics trap before either storage write and their
    canonical observations expose the original storage snapshot. -/
theorem capabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1_secondGuardFailure
    (capability : ResolvedEngineeringBuildV1)
    (program : ProofForgeV2.Semantic.WireV1.SemanticProgramV1)
    (data : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1)
    (plan : Plan)
    (ir : IR)
    (files : Array OutputFile)
    (entryIndex : Nat)
    (binding0 binding1 : UInt64StateBindingV1)
    (entryName parameterName : String)
    (parameterSourceId : Nat)
    (method : Method)
    (markerRegion field0Region field1Region : KeyRegion)
    (methodIR : MethodIR)
    (watFile abiFile : OutputFile)
    (watMethodText abiMethodText : String)
    (before0 before1 amount : UInt64)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityGuardedSubTwoUInt64WithdrawStaticEmissionV1 capability program
        data plan ir files entryIndex binding0 binding1 entryName parameterName
          parameterSourceId method markerRegion field0Region field1Region
            methodIR watFile abiFile watMethodText abiMethodText)
    (hmarker :
      storage.lookup markerRegion.key =
        some (encodeU64le plan.storage.markerValue))
    (hfield0 :
      storage.lookup field0Region.key = some (encodeU64le before0))
    (hfield1 :
      storage.lookup field1Region.key = some (encodeU64le before1))
    (hinputValue : ir.memory.inputOffset ≠ ir.memory.valueOffset)
    (hinputDepositLow : ir.memory.inputOffset ≠ ir.memory.depositOffset)
    (hinputDepositHigh :
      ir.memory.inputOffset ≠ ir.memory.depositOffset + 8)
    (hguard0 : amount.toNat ≤ before0.toNat)
    (hguard1 : ¬ amount.toNat ≤ before1.toNat) :
    executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .trapped .assertionFailed ∧
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage = .trapped .trap ∧
      observeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        observeMethodWATV1 entryName 12
          (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
            field0Region field1Region plan.storage.markerValue)
          (encodeU64le amount) 0 0 storage := by
  have halignment := hchain.staticAlignment.staticAlignment
  have hmethod :
      executeMethodV1 methodIR (encodeU64le amount) 0 0 storage =
        .trapped .assertionFailed := by
    rw [halignment.methodIRExact]
    exact executeMethodV1_guardedSubTwoUInt64Withdraw_second_guard_failure
      entryName parameterName parameterSourceId markerRegion field0Region
        field1Region plan.storage.markerValue before0 before1 amount storage
          hmarker hfield0 hfield1 hguard0 hguard1
  have hwat :
      executeMethodWATV1 12
        (guardedSubTwoUInt64WithdrawWATV1 ir.registers ir.memory markerRegion
          field0Region field1Region plan.storage.markerValue)
        (encodeU64le amount) 0 0 storage = .trapped .trap :=
    executeMethodWATV1_guardedSubTwoUInt64Withdraw_second_guard_failure
      ir.registers ir.memory markerRegion field0Region field1Region
        plan.storage.markerValue before0 before1 amount storage hmarker hfield0
          hfield1 hinputValue hinputDepositLow hinputDepositHigh hguard0 hguard1
  have hname : methodIR.name = entryName :=
    congrArg MethodIR.name halignment.methodIRExact
  refine ⟨hmethod, hwat, ?_⟩
  simp [observeMethodV1, observeMethodWATV1, hmethod, hwat, hname]

/-- The bounded typed-WAT fragment selected by a production capability chain
    passes its own static validator when the production scratch block is in
    bounds. The validator checks only this typed subset's locals, exact key
    annotations, memory accesses, constants, and return width; it is not a
    textual WAT or general Wasm validation theorem. -/
theorem capabilityEntryStaticEmissionV1_validateReadOnlyWATMethodV1
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
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText)
    (hmemory :
      ir.memory.valueOffset + 8 ≤
        ir.memory.minPages * wasmPageBytes) :
    validateReadOnlyWATMethodV1 ir.keys ir.memory methodIR.tempCount
      (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
        plan.storage.markerValue fieldRegion) = .ok () := by
  rcases hchain.staticAlignment with
    ⟨_, _, hmarkerLookup, hfieldLookup, _, halignment⟩
  rcases halignment with ⟨_, _, _, _, _, _, hmethodIR⟩
  rw [hmethodIR]
  exact validateReadOnlyWATMethodV1_nullaryUInt64View ir.keys ir.registers
    ir.memory markerRegion fieldRegion plan.storage.markerValue
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys 0 markerRegion
        hmarkerLookup)
      (readOnlyWATKeyRegionBoundV1_of_getElem?_eq_some ir.keys
        (binding.physicalFieldIndex + 1) fieldRegion hfieldLookup)
      hmemory

/-- The selected production method is byte-for-byte rendered from the exact
    bounded typed-WAT sequence and that sequence passes its static validator.
    This closes a generated method-fragment identity boundary only; it does not
    parse or validate arbitrary textual WAT or the complete Wasm module. -/
theorem capabilityEntryStaticEmissionV1_validatedReadOnlyMethodWATEmissionV1
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
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText)
    (hmemory :
      ir.memory.valueOffset + 8 ≤
        ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
      (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
        plan.storage.markerValue fieldRegion) := by
  rcases hchain.staticAlignment with ⟨_, _, _, _, _, halignment⟩
  have hlower :
      lowerReadOnlyWATOperationsV1 ir.registers ir.memory
          methodIR.operations =
        some (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
          plan.storage.markerValue fieldRegion) := by
    rw [halignment.2.2.2.2.2.2]
    exact lowerReadOnlyWATOperationsV1_nullaryUInt64View ir.registers
      ir.memory markerRegion fieldRegion plan.storage.markerValue
  exact ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
      methodIR watFile.contents watMethodText _
      hchain.baseEmission.watMethodEmission hlower,
    capabilityEntryStaticEmissionV1_validateReadOnlyWATMethodV1 capability
      program data plan ir files entryIndex binding viewName method markerRegion
      fieldRegion methodIR watFile abiFile watMethodText abiMethodText hchain
      hmemory
  ⟩

/-- The same capability chain owns the complete validated-IR production module
    framing around the selected validated typed-WAT method. This still does not
    parse or generally validate textual WAT, Wasm binaries, or NEAR execution. -/
theorem capabilityEntryStaticEmissionV1_validatedReadOnlyWATModuleEmissionV1
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
    (watMethodText abiMethodText : String)
    (hchain :
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText)
    (hmemory :
      ir.memory.valueOffset + 8 ≤
        ir.memory.minPages * wasmPageBytes) :
    ValidatedReadOnlyWATModuleEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
      (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
        plan.storage.markerValue fieldRegion) := by
  exact validatedReadOnlyWATModuleEmissionV1_of_irEmissionV1 ir files
    (entryIndex + 1) methodIR watFile.contents watMethodText _
    hchain.baseEmission.irEmission
    (capabilityEntryStaticEmissionV1_validatedReadOnlyMethodWATEmissionV1
      capability program data plan ir files entryIndex binding viewName method
      markerRegion fieldRegion methodIR watFile abiFile watMethodText
      abiMethodText hchain hmemory)

/-- A capability-scoped production entry executes in the first target recipe
    semantics whenever its logical/KV representation relation holds. This
    theorem connects the exact production Plan/IR/build chain to target
    execution; WAT/Wasm/NEAR correctness remains a later refinement boundary. -/
theorem capabilityEntryStaticEmissionV1_executeReadOnlyMethodV1
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
    (watMethodText abiMethodText : String)
    (logical : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (decodedValues : Array ByteArray)
    (valueBytes : ByteArray)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText)
    (hstorage :
      InitializedUInt64StorageRelV1 data plan.storage binding logical
        decodedValues valueBytes storage)
    (hvalueSize : valueBytes.size = 8) :
    executeReadOnlyMethodV1 methodIR ByteArray.empty storage =
      .returned (some valueBytes) := by
  rcases hchain.staticAlignment with ⟨_, _, _, _, _, halignment⟩
  exact
    executeReadOnlyMethodV1_of_nullaryUInt64ViewStaticAlignment data
      plan.storage binding viewName method markerRegion fieldRegion methodIR
      logical decodedValues valueBytes storage halignment hstorage hvalueSize

/-- The selected production method fragment is rendered from the exact typed
    WAT sequence whose bounded execution returns the represented UInt64 bytes.
    The full base WAT remains tied to the sole production emitter. This stops
    before generic WAT validation, Wasm binary translation, or NEAR runtime
    semantics. -/
theorem capabilityEntryStaticEmissionV1_executeReadOnlyWATV1
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
    (watMethodText abiMethodText : String)
    (logical : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
    (decodedValues : Array ByteArray)
    (valueBytes : ByteArray)
    (storage : StorageObservationV1)
    (hchain :
      CapabilityEntryStaticEmissionV1 capability program data plan ir files
        entryIndex binding viewName method markerRegion fieldRegion methodIR
          watFile abiFile watMethodText abiMethodText)
    (hstorage :
      InitializedUInt64StorageRelV1 data plan.storage binding logical
        decodedValues valueBytes storage)
    (hvalueSize : valueBytes.size = 8) :
    ReadOnlyMethodWATEmissionV1 ir (entryIndex + 1) methodIR
      watFile.contents watMethodText
      (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
        plan.storage.markerValue fieldRegion) ∧
    executeReadOnlyWATV1 1
      (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
        plan.storage.markerValue fieldRegion)
      ByteArray.empty storage = .returned (some valueBytes) := by
  rcases hchain.staticAlignment with ⟨_, _, _, _, _, halignment⟩
  have hlower :
      lowerReadOnlyWATOperationsV1 ir.registers ir.memory
          methodIR.operations =
        some (nullaryUInt64ViewWATV1 ir.registers ir.memory markerRegion
          plan.storage.markerValue fieldRegion) := by
    rw [halignment.2.2.2.2.2.2]
    exact lowerReadOnlyWATOperationsV1_nullaryUInt64View ir.registers
      ir.memory markerRegion fieldRegion plan.storage.markerValue
  refine ⟨
    readOnlyMethodWATEmissionV1_of_methodWATEmissionV1 ir (entryIndex + 1)
      methodIR watFile.contents watMethodText _
      hchain.baseEmission.watMethodEmission hlower,
    ?_
  ⟩
  exact executeReadOnlyWATV1_of_nullaryUInt64ViewStaticAlignment data
    plan.storage binding viewName method markerRegion fieldRegion methodIR
    ir.registers ir.memory logical decodedValues valueBytes storage halignment
    hstorage hvalueSize

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Near
