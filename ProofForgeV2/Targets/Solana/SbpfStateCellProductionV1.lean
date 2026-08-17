import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.Solana.ProductionCompositionV1
import ProofForgeV2.Targets.Solana.ProductionMethodV1
import ProofForgeV2.Targets.Solana.SbpfHandlerJoinV1
import ProofForgeV2.Targets.Solana.SbpfStateCellTypedV1

/-!
# Solana StateCell production subject

Pure, fail-closed reconstruction of the concrete StateCell certification
subjects from the exact Source AST captured by the actual `program StateCell`
declaration. The captured fields re-enter the production source validator and
must canonically encode to the declaration's actual export bytes. The resolvers
then follow the existing compiler, Solana capability, full-body HandlerIR,
assembly emitter, strict artifact parser, and identity-bound provider path.
They contain no copied IR/program and introduce no alternate lowering or
business semantics.

`get` and `initialize` retain dedicated 55-step certified joins. Successful
`increment` retains its dedicated 70-step certified join, and overflowing
`increment` retains its dedicated 56-step certified join.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1

-- Kernel-checked ownership of the exact source AST and export bytes produced
-- by the real `program StateCell` declaration. This discharges the first
-- production preparation stage without a copied AST, runtime-only assertion,
-- or contract-specific source validator.
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCanonicalSourceBindingV1 :
    ∃ binding,
      bindElaboratedSourceToCanonicalBytesV1
        StateCell.Source.subjectV1 StateCell.bytes = .ok binding := by
  have checked :
      (match bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes with
        | .ok _ => true
        | .error _ => false) = true := by
    decide
  cases hbinding : bindElaboratedSourceToCanonicalBytesV1
      StateCell.Source.subjectV1 StateCell.bytes with
  | error _ =>
      rw [hbinding] at checked
      contradiction
  | ok binding => exact ⟨binding, rfl⟩

private theorem exceptToOptionGetSuccessV1 {ε α : Type}
    (result : Except ε α) (success : result.toOption.isSome = true) :
    result = .ok (result.toOption.get success) := by
  cases result with
  | error _ => simp [Except.toOption] at success
  | ok _ => rfl

private theorem exceptUnitSuccessV1 {ε : Type}
    (result : Except ε Unit) (success : result.toOption.isSome = true) :
    result = .ok () := by
  simpa using exceptToOptionGetSuccessV1 result success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellProgramLoweringTablesSomeV1 :
    (prepareProgramLoweringTablesV1
      StateCell.Source.subjectV1.program).toOption.isSome = true := by
  decide

private def stateCellProgramLoweringTablesV1 : ProgramLoweringTablesV1 :=
  (prepareProgramLoweringTablesV1
    StateCell.Source.subjectV1.program).toOption.get
      stateCellProgramLoweringTablesSomeV1

private theorem stateCellProgramLoweringTablesSuccessV1 :
    prepareProgramLoweringTablesV1 StateCell.Source.subjectV1.program =
      .ok stateCellProgramLoweringTablesV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramLoweringTablesSomeV1

private def stateCellCallableLoweringState0V1 :=
  initialProgramCallableLoweringStateV1 stateCellProgramLoweringTablesV1

private def stateCellStateItemV1 :=
  StateCell.Source.subjectV1.program.items[0]'(by decide)

private def stateCellInitializeItemV1 :=
  StateCell.Source.subjectV1.program.items[1]'(by decide)

private def stateCellIncrementItemV1 :=
  StateCell.Source.subjectV1.program.items[2]'(by decide)

private def stateCellGetItemV1 :=
  StateCell.Source.subjectV1.program.items[3]'(by decide)

private theorem stateCellProgramItemsV1 :
    StateCell.Source.subjectV1.program.items.toList =
      [stateCellStateItemV1, stateCellInitializeItemV1,
        stateCellIncrementItemV1, stateCellGetItemV1] := by
  decide

private theorem stateCellStateItemLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1 stateCellStateItemV1 =
        .ok stateCellCallableLoweringState0V1 := by
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellInitializeLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1
      stateCellInitializeItemV1).toOption.isSome = true := by
  decide

private def stateCellCallableLoweringState1V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState0V1
    stateCellInitializeItemV1).toOption.get stateCellInitializeLoweringSomeV1

private theorem stateCellInitializeLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1 stateCellInitializeItemV1 =
        .ok stateCellCallableLoweringState1V1 :=
  exceptToOptionGetSuccessV1 _ stateCellInitializeLoweringSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellIncrementLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState1V1
      stateCellIncrementItemV1).toOption.isSome = true := by
  decide

private def stateCellCallableLoweringState2V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState1V1
    stateCellIncrementItemV1).toOption.get stateCellIncrementLoweringSomeV1

private theorem stateCellIncrementLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState1V1 stateCellIncrementItemV1 =
        .ok stateCellCallableLoweringState2V1 :=
  exceptToOptionGetSuccessV1 _ stateCellIncrementLoweringSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellGetLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState2V1
      stateCellGetItemV1).toOption.isSome = true := by
  decide

private def stateCellCallableLoweringState3V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState2V1
    stateCellGetItemV1).toOption.get stateCellGetLoweringSomeV1

private theorem stateCellGetLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState2V1 stateCellGetItemV1 =
        .ok stateCellCallableLoweringState3V1 :=
  exceptToOptionGetSuccessV1 _ stateCellGetLoweringSomeV1

private theorem stateCellProgramCallableBodiesSuccessV1 :
    lowerProgramCallableBodiesV1 StateCell.Source.subjectV1.program
      stateCellProgramLoweringTablesV1 =
        .ok stateCellCallableLoweringState3V1.toBodies := by
  unfold lowerProgramCallableBodiesV1
  rw [stateCellProgramItemsV1]
  simp only [lowerProgramCallableItemsV1]
  rw [show lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      (initialProgramCallableLoweringStateV1 stateCellProgramLoweringTablesV1)
      stateCellStateItemV1 = .ok stateCellCallableLoweringState0V1 by
    simpa [stateCellCallableLoweringState0V1] using
      stateCellStateItemLoweringSuccessV1]
  simp only [Bind.bind, Except.bind]
  rw [stateCellInitializeLoweringSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellIncrementLoweringSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellGetLoweringSuccessV1]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellProgramFinalizationCoreSomeV1 :
    (prepareProgramLoweringFinalizationCoreV1
      stateCellCallableLoweringState3V1.toBodies).toOption.isSome = true := by
  decide

private def stateCellProgramFinalizationCoreV1 :
    ProgramLoweringFinalizationCoreV1 :=
  (prepareProgramLoweringFinalizationCoreV1
    stateCellCallableLoweringState3V1.toBodies).toOption.get
      stateCellProgramFinalizationCoreSomeV1

private theorem stateCellProgramFinalizationCoreSuccessV1 :
    prepareProgramLoweringFinalizationCoreV1
      stateCellCallableLoweringState3V1.toBodies =
        .ok stateCellProgramFinalizationCoreV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramFinalizationCoreSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellProgramS2RequirementsSomeV1 :
    (freezeProgramLoweringS2RequirementsV1
      StateCell.Source.subjectV1.program).toOption.isSome = true := by
  decide

private def stateCellProgramS2RequirementsV1 : ProgramRequirementsV1 :=
  (freezeProgramLoweringS2RequirementsV1
    StateCell.Source.subjectV1.program).toOption.get
      stateCellProgramS2RequirementsSomeV1

private theorem stateCellProgramS2RequirementsSuccessV1 :
    freezeProgramLoweringS2RequirementsV1 StateCell.Source.subjectV1.program =
      .ok stateCellProgramS2RequirementsV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramS2RequirementsSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellProgramRequirementsSomeV1 :
    (mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
      stateCellCallableLoweringState3V1.toBodies).toOption.isSome = true := by
  decide

private def stateCellProgramRequirementsV1 : ProgramRequirementsV1 :=
  (mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
    stateCellCallableLoweringState3V1.toBodies).toOption.get
      stateCellProgramRequirementsSomeV1

private theorem stateCellProgramRequirementsSuccessV1 :
    mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
      stateCellCallableLoweringState3V1.toBodies =
        .ok stateCellProgramRequirementsV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramRequirementsSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellQualifiedNameSomeV1 :
    (programIdentityToQualifiedNameV1
      StateCell.Source.subjectV1.programIdentity).toOption.isSome = true := by
  decide

private def stateCellQualifiedNameV1 :=
  (programIdentityToQualifiedNameV1
    StateCell.Source.subjectV1.programIdentity).toOption.get
      stateCellQualifiedNameSomeV1

private theorem stateCellQualifiedNameSuccessV1 :
    programIdentityToQualifiedNameV1
      StateCell.Source.subjectV1.programIdentity = .ok stateCellQualifiedNameV1 :=
  exceptToOptionGetSuccessV1 _ stateCellQualifiedNameSomeV1

private def stateCellSemanticProgramDataV1 : SemanticProgramDataV1 :=
  assembleProgramLoweringDataV1 stateCellQualifiedNameV1
    stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState3V1.toBodies
    stateCellProgramFinalizationCoreV1 stateCellProgramRequirementsV1

private def stateCellType0V1 : TypeDeclV1 :=
  stateCellSemanticProgramDataV1.types[0]'(by decide)

private def stateCellType1V1 : TypeDeclV1 :=
  stateCellSemanticProgramDataV1.types[1]'(by decide)

private def stateCellState0V1 : StateDeclV1 :=
  stateCellSemanticProgramDataV1.logicalState[0]'(by decide)

private def stateCellCallable0V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[0]'(by decide)

private def stateCellCallable1V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[1]'(by decide)

private def stateCellCallable2V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[2]'(by decide)

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellTypesV1 :
    stateCellSemanticProgramDataV1.types =
      #[stateCellType0V1, stateCellType1V1] := by
  apply Array.ext
  · decide
  · intro index hleft _hright
    have hsize : stateCellSemanticProgramDataV1.types.size = 2 := by decide
    rw [hsize] at hleft
    match index with
    | 0 => rfl
    | 1 => rfl
    | n + 2 =>
        have : n + 2 < 2 := by
          simpa using hleft
        omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallablesV1 :
    stateCellSemanticProgramDataV1.callables =
      #[stateCellCallable0V1, stateCellCallable1V1, stateCellCallable2V1] := by
  apply Array.ext
  · decide
  · intro index hleft _hright
    have hsize : stateCellSemanticProgramDataV1.callables.size = 3 := by decide
    rw [hsize] at hleft
    match index with
    | 0 => rfl
    | 1 => rfl
    | 2 => rfl
    | n + 3 =>
        have : n + 3 < 3 := by
          simpa using hleft
        omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellTypeShapeClassifiersV1 :
    (match stateCellType0V1.shape with
      | .array _ _ | .map _ _ | .option _ => true
      | _ => false) = false ∧
    (match stateCellType1V1.shape with
      | .array _ _ | .map _ _ | .option _ => true
      | _ => false) = false ∧
    (match stateCellType0V1.shape with
      | .array _ _ | .map _ _ | .struct _ | .enum _ => true
      | _ => false) = false ∧
    (match stateCellType1V1.shape with
      | .array _ _ | .map _ _ | .struct _ | .enum _ => true
      | _ => false) = false := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellProgramFinalizationSuccessV1 :
    finishProgramLoweringV1 stateCellQualifiedNameV1
      StateCell.Source.subjectV1.program stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState3V1.toBodies =
        .ok stateCellSemanticProgramDataV1 := by
  unfold finishProgramLoweringV1
  rw [stateCellProgramFinalizationCoreSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellProgramS2RequirementsSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellProgramRequirementsSuccessV1]
  -- StateCell anonymous first-seen order (UInt64 before Unit) is already the
  -- SPEC §5 canonical rank, so the Stage A canonicalizer is an exact identity
  -- on the assembled data (kernel-evaluated).
  rfl

private def stateCellCertifiedProgramLoweringV1
    (binding : CanonicalSourceBindingV1
      StateCell.Source.subjectV1 StateCell.bytes) :
    CertifiedProgramLoweringV1 binding.validated := {
  qualifiedName := stateCellQualifiedNameV1
  qualifiedNameSuccess := by
    rw [binding.programIdentity_eq]
    exact stateCellQualifiedNameSuccessV1
  tables := stateCellProgramLoweringTablesV1
  tablesSuccess := by
    rw [binding.program_eq]
    exact stateCellProgramLoweringTablesSuccessV1
  bodies := stateCellCallableLoweringState3V1.toBodies
  bodiesSuccess := by
    rw [binding.program_eq]
    exact stateCellProgramCallableBodiesSuccessV1
  data := stateCellSemanticProgramDataV1
  finishSuccess := by
    rw [binding.program_eq]
    exact stateCellProgramFinalizationSuccessV1
}

/-- Exact whole-program production lowering for every canonical binding of the
    real StateCell declaration. The result is the data retained by the existing
    staged production certificate, not a supplied or copied Semantic AST. -/
theorem stateCellProgramLoweringSuccessV1
    (binding : CanonicalSourceBindingV1
      StateCell.Source.subjectV1 StateCell.bytes) :
    lowerProgramDataV1 binding.validated =
      .ok stateCellSemanticProgramDataV1 :=
  (stateCellCertifiedProgramLoweringV1 binding).lowerProgramData_success

/-- Unconditional kernel certificate for the concrete production StateCell
    source lowering. The witness is assembled from source-order equations for
    the real declaration, `initialize`, `increment`, and `get` items; no
    expected Semantic AST or alternate lowerer is supplied. -/
theorem stateCellProgramLoweringCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (certified : CertifiedProgramLoweringV1 binding.validated),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        certifyProgramLoweringV1 binding.validated = .ok certified := by
  rcases stateCellCanonicalSourceBindingV1 with ⟨binding, bindingSuccess⟩
  let certified := stateCellCertifiedProgramLoweringV1 binding
  exact ⟨binding, certified, bindingSuccess,
    certifyProgramLoweringV1_eq_ok certified⟩

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellTypeKeyPhasesSuccessV1 :
    validateTypeKeyPhasesV1 stateCellSemanticProgramDataV1.types = .ok () := by
  have htype0 : stateCellType0V1 =
      { id := 0, name := none, shape := .uint 64 } := by
    rfl
  have htype1 : stateCellType1V1 =
      { id := 1, name := none, shape := .unit } := by
    rfl
  apply validateTypeKeyPhasesV1_eq_ok_of_prefix_phases
  · apply exceptUnitSuccessV1
    rw [stateCellTypesV1, htype0, htype1]
    decide
  · apply exceptUnitSuccessV1
    rw [stateCellTypesV1, htype0, htype1]
    decide
  · apply validateRecursiveAnonymousTypeKeyUniquenessV1_eq_ok_of_none
    rw [stateCellTypesV1]
    rcases stateCellTypeShapeClassifiersV1 with ⟨h0, h1, _h2, _h3⟩
    rw [Array.any_eq_false]
    intro index hindex
    match index with
    | 0 => simpa [h0]
    | 1 => simpa [h1]
    | n + 2 =>
        have : n + 2 < 2 := by simpa using hindex
        omega
  · apply validateNamedBodyOptionCycleLegalityV1_eq_ok_of_none
    rw [stateCellTypesV1]
    rcases stateCellTypeShapeClassifiersV1 with ⟨_h0, _h1, h2, h3⟩
    rw [Array.any_eq_false]
    intro index hindex
    match index with
    | 0 => simpa [h2]
    | 1 => simpa [h3]
    | n + 2 =>
        have : n + 2 < 2 := by simpa using hindex
        omega
  · rw [stateCellTypesV1]
    exact validateAnonymousTypeKeyRankV1_uint64_unit_eq_ok
      stateCellType0V1 stateCellType1V1 htype0 htype1

private theorem stateCellConstantNamesSuccessV1 :
    validateConstantNameUniquenessV1
      stateCellSemanticProgramDataV1.constants = .ok () := by
  simp [validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.constants.size ≤ 1 by decide,
    Pure.pure, Except.pure]

private theorem stateCellStateNamesSuccessV1 :
    validateLogicalStateNameUniquenessV1
      stateCellSemanticProgramDataV1.logicalState = .ok () := by
  simp [validateLogicalStateNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.logicalState.size ≤ 1 by decide,
    Pure.pure, Except.pure]

private theorem stateCellEventNamesSuccessV1 :
    validateEventNameUniquenessV1 stateCellSemanticProgramDataV1.events =
      .ok () := by
  simp [validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.events.size ≤ 1 by decide,
    Pure.pure, Except.pure]

private theorem stateCellErrorNamesSuccessV1 :
    validateErrorNameUniquenessV1 stateCellSemanticProgramDataV1.errors =
      .ok () := by
  simp [validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.errors.size ≤ 1 by decide,
    Pure.pure, Except.pure]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableParameterNamesSuccessV1 :
    validateCallableParameterNameUniquenessV1
      stateCellSemanticProgramDataV1.callables = .ok () := by
  have h0 : stateCellCallable0V1.params.size ≤ 1 := by decide
  have h1 : stateCellCallable1V1.params.size ≤ 1 := by decide
  have h2 : stateCellCallable2V1.params.size ≤ 1 := by decide
  simp [validateCallableParameterNameUniquenessV1, stateCellCallablesV1,
    h0, h1, h2, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableSignaturePhasesSuccessV1 :
    validateCallableSignaturePhasesV1 stateCellSemanticProgramDataV1.types
      stateCellSemanticProgramDataV1.callables = .ok () := by
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallableParameterNamesSuccessV1
  all_goals
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable0V1).toOption.isSome = true := by
  decide

private def stateCellCallable0ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable0V1).toOption.get
    stateCellCallable0ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable1V1).toOption.isSome = true := by
  decide

private def stateCellCallable1ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable1V1).toOption.get
    stateCellCallable1ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable2V1).toOption.isSome = true := by
  decide

private def stateCellCallable2ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable2V1).toOption.get
    stateCellCallable2ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableReachabilityValuesV1 :
    stateCellCallable0ReachabilityV1 = #[true] ∧
      stateCellCallable1ReachabilityV1 = #[true] ∧
      stateCellCallable2ReachabilityV1 = #[true] := by
  decide

private def stateCellCallable0DefSitesV1 :=
  collectValueDefSites stateCellCallable0V1

private def stateCellCallable1DefSitesV1 :=
  collectValueDefSites stateCellCallable1V1

private def stateCellCallable2DefSitesV1 :=
  collectValueDefSites stateCellCallable2V1

private def stateCellCallable0BlockV1 : BlockV1 :=
  stateCellCallable0V1.blocks[0]'(by decide)

private def stateCellCallable1BlockV1 : BlockV1 :=
  stateCellCallable1V1.blocks[0]'(by decide)

private def stateCellCallable2BlockV1 : BlockV1 :=
  stateCellCallable2V1.blocks[0]'(by decide)

private def stateCellCallable0Instruction0V1 : InstructionV1 :=
  stateCellCallable0BlockV1.instructions[0]'(by decide)

private def stateCellCallable1Instruction0V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[0]'(by decide)

private def stateCellCallable1Instruction1V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[1]'(by decide)

private def stateCellCallable1Instruction2V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[2]'(by decide)

private def stateCellCallable1Instruction3V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[3]'(by decide)

private def stateCellCallable2Instruction0V1 : InstructionV1 :=
  stateCellCallable2BlockV1.instructions[0]'(by decide)

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableBlockTablesV1 :
    stateCellCallable0V1.blocks = #[stateCellCallable0BlockV1] ∧
      stateCellCallable1V1.blocks = #[stateCellCallable1BlockV1] ∧
      stateCellCallable2V1.blocks = #[stateCellCallable2BlockV1] := by
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable0V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable1V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable2V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableInstructionTablesV1 :
    stateCellCallable0BlockV1.instructions =
        #[stateCellCallable0Instruction0V1] ∧
      stateCellCallable1BlockV1.instructions =
        #[stateCellCallable1Instruction0V1, stateCellCallable1Instruction1V1,
          stateCellCallable1Instruction2V1, stateCellCallable1Instruction3V1] ∧
      stateCellCallable2BlockV1.instructions =
        #[stateCellCallable2Instruction0V1] := by
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable0BlockV1.instructions.size = 1 := by decide
          rw [hsize] at hleft
          omega
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      have hsize : stateCellCallable1BlockV1.instructions.size = 4 := by decide
      rw [hsize] at hleft
      match index with
      | 0 => rfl
      | 1 => rfl
      | 2 => rfl
      | 3 => rfl
      | n + 4 => omega
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable2BlockV1.instructions.size = 1 := by decide
          rw [hsize] at hleft
          omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableUsesV1 :
    opValueUses stateCellCallable0Instruction0V1.op = #[0] ∧
      terminatorValueUses stateCellCallable0BlockV1.terminator = #[] ∧
      opValueUses stateCellCallable1Instruction0V1.op = #[] ∧
      opValueUses stateCellCallable1Instruction1V1.op = #[1, 0] ∧
      opValueUses stateCellCallable1Instruction2V1.op = #[2] ∧
      opValueUses stateCellCallable1Instruction3V1.op = #[] ∧
      terminatorValueUses stateCellCallable1BlockV1.terminator = #[3] ∧
      opValueUses stateCellCallable2Instruction0V1.op = #[] ∧
      terminatorValueUses stateCellCallable2BlockV1.terminator = #[0] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableDefSitesValuesV1 :
    stateCellCallable0DefSitesV1 = #[(0, 0)] ∧
      stateCellCallable1DefSitesV1 = #[(0, 0), (1, 0), (2, 0), (3, 0)] ∧
      stateCellCallable2DefSitesV1 = #[(0, 0)] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable0V1
      stateCellCallable0ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.1]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable0V1
      #[true] stateCellCallable0DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.1]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.1]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.1]
    rcases stateCellCallableUsesV1 with
      ⟨hop, hterm, _hop10, _hop11, _hop12, _hop13, _hterm1, _hop2, _hterm2⟩
    simp [stateCellCallableInstructionTablesV1.1, hop, hterm,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.1]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.1]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable1V1
      stateCellCallable1ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.2.1]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable1V1
      #[true] stateCellCallable1DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.2.1]
    rcases stateCellCallableUsesV1 with
      ⟨_hop0, _hterm0, hop10, hop11, hop12, hop13, hterm, _hop2, _hterm2⟩
    simp [stateCellCallableInstructionTablesV1.2.1, hop10, hop11, hop12,
      hop13, hterm, Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.2.1]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable2V1
      stateCellCallable2ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.2.2]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable2V1
      #[true] stateCellCallable2DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.2.2]
    rcases stateCellCallableUsesV1 with
      ⟨_hop0, _hterm0, _hop10, _hop11, _hop12, _hop13, _hterm1, hop, hterm⟩
    simp [stateCellCallableInstructionTablesV1.2.2, hop, hterm,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.2.2]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable0V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable0V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable0ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable0ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable0ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable1V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable1V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable1ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable1ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable1ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable2V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable2V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable2ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable2ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable2ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellGenericCfgSuccessV1 :
    validateGenericCfgPhasesV1 stateCellSemanticProgramDataV1 = .ok () := by
  apply validateGenericCfgPhasesV1_three_eq_ok stateCellSemanticProgramDataV1
      stateCellCallable0V1 stateCellCallable1V1 stateCellCallable2V1
  · exact stateCellCallablesV1
  · exact stateCellCallable0CfgSuccessV1
  · exact stateCellCallable1CfgSuccessV1
  · exact stateCellCallable2CfgSuccessV1
  · apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellInvariantClosureSomeV1 :
    (validateInvariantClosurePhasesV1
      stateCellSemanticProgramDataV1.callables).toOption.isSome = true := by
  decide

private def stateCellInvariantClosureMembersV1 : Array Bool :=
  (validateInvariantClosurePhasesV1
    stateCellSemanticProgramDataV1.callables).toOption.get
      stateCellInvariantClosureSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCfgInvariantPhasesSuccessV1 :
    validateCfgInvariantPhasesV1 stateCellSemanticProgramDataV1 = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok stateCellSemanticProgramDataV1
      stateCellInvariantClosureMembersV1
  · exact stateCellGenericCfgSuccessV1
  · exact exceptToOptionGetSuccessV1 _ stateCellInvariantClosureSomeV1
  · apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellSemanticStructureSuccessV1 :
    validateSemanticProgramStructureV1 stateCellSemanticProgramDataV1 =
      .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
      stateCellSemanticProgramDataV1 maxCanonicalProgramBytes
        maxCanonicalProgramBytes
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellTypeKeyPhasesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptToOptionGetSuccessV1
    decide
  · apply exceptToOptionGetSuccessV1
    decide
  · exact stateCellConstantNamesSuccessV1
  · exact stateCellStateNamesSuccessV1
  · exact stateCellEventNamesSuccessV1
  · exact stateCellErrorNamesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallableSignaturePhasesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCfgInvariantPhasesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide

/-- The concrete values consumed by the existing certified StateCell `get`
    HandlerIR/provider join. The private constructor prevents callers from
    presenting a hand-built tuple as the production subject; the sole resolver
    below reconstructs every field from the exported production source. -/
structure ResolvedStateCellGetProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .view (some "get") "get"
  referencePre : LogicalStateV1
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[] #[] #[] {}
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1
  returnBytes : Array UInt8
  value : SbpfSemantics.Word

namespace ResolvedStateCellGetProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.admitted

def ir (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.referenceExecution.outcome

def returnTypeId (subject : ResolvedStateCellGetProductionSubjectV1) :=
  subject.method.callable.result.typeId

end ResolvedStateCellGetProductionSubjectV1

private def compileResultV1 (result : CompileResult α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error error => .error error.render

/-- Reconstruct the exact production subject without IO or a parser session.

    Source authority is the AST captured by `program StateCell`, revalidated by
    the production source validator and checked against that declaration's
    canonical export bytes. The validated source then enters the same compiler/
    capability/lowering/emitter path used by product construction. The exact
    `.s` SHA-256 is checked before the strict parser may mint the provider
    artifact. -/
def resolveStateCellGetProductionSubjectV1 :
    Except String ResolvedStateCellGetProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let ir := preparation.productionIR
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .view (some "get") "get"
  let data := preparation.data
  let handler := method.handler
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let logicalValue : UInt64 := 41
  let referencePre ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le logicalValue] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell get pre-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre
      #[] #[] #[] {}
  let value := BitVec.ofNat 64 logicalValue.toNat
  let returnBytes := (encodeU64le logicalValue).data
  let accountData :=
    (SbpfSemantics.wordToLE
      (BitVec.ofNat 64 ir.stateAccount.initializedMarker.toNat)).append
      returnBytes
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)
  }
  let handlerInvocation :=
    nullaryUInt64ViewInvocationV1 ⟨accountData⟩ discriminator
  pure <| ResolvedStateCellGetProductionSubjectV1.mk preparation method
    referencePre referenceExecution handlerInvocation loaderInvocation returnBytes
    value

/-- Single fail-closed gate over the pure production subject and the existing
    certified HandlerIR/provider checker. Any source, compiler, profile,
    artifact, handler, or invocation failure returns `false`. -/
def checkStateCellGetProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellGetProductionSubjectV1 fun subject =>
    checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation subject.returnBytes subject.value

/-- The pure production gate remains proof-producing rather than treating its
    executable result as a theorem. Once the Boolean is discharged, this
    theorem recovers both the exact resolved production subject and the
    existing certified 55-step HandlerIR/provider carrier. -/
theorem checkStateCellGetProductionSubjectV1_sound
    (checked : checkStateCellGetProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellGetProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellGetExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation subject.returnBytes subject.value) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellGetProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value)
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation subject.returnBytes subject.value hchecked

/-- D5 production gate for the read-only `get(41)` slice. It composes the
    source-derived sole Reference result with the dedicated 55-step provider
    certificate; the production account remains unchanged. -/
def checkStateCellGetReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellGetProductionSubjectV1
    (fun subject =>
      checkUInt64ReturnedHandlerObservationRelV1 subject.data
        subject.returnTypeId subject.referencePre subject.referenceOutcome
        ⟨subject.returnBytes⟩
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation subject.returnBytes subject.value)

/-- A successful get D5 gate recovers one composed
    Reference→HandlerIR→provider carrier. The Boolean premise remains explicit;
    this does not cover ELF, linker, loader, or SVM runtime semantics. -/
theorem checkStateCellGetReferenceProviderSubjectV1_sound
    (checked : checkStateCellGetReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellGetProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value,
        UInt64ReferenceHandlerSbpfJoinV1 subject.data subject.returnTypeId
          subject.referencePre subject.referenceOutcome ⟨subject.returnBytes⟩
          certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellGetProductionSubjectV1
      (fun subject =>
        checkUInt64ReturnedHandlerObservationRelV1 subject.data
          subject.returnTypeId subject.referencePre subject.referenceOutcome
          ⟨subject.returnBytes⟩
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value)
      (fun subject hreference =>
        (checkUInt64ReturnedHandlerObservationRelV1_eq_true_iff subject.data
          subject.returnTypeId subject.referencePre subject.referenceOutcome
          ⟨subject.returnBytes⟩
          (observeHandlerIRV1 subject.handler subject.handlerInvocation)).mp
            hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellGetExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation subject.returnBytes subject.value hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- Concrete values consumed by the generic StateCell `initialize`
    HandlerIR/provider join. Same private-ctor discipline as `get`. -/
structure ResolvedStateCellInitializeProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .initializer none
    "initialize"
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  binding : UInt64StateAccountBindingV1
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  postData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellInitializeProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.admitted

def plan (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionPlan

def ir (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome
    (subject : ResolvedStateCellInitializeProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellInitializeProductionSubjectV1

/-- Reconstruct the initialize production subject from the same exported
    StateCell source. Prestate is the uninitialized one-field account used by
    the existing executable observation; the argument is `7`. -/
def resolveStateCellInitializeProductionSubjectV1 :
    Except String ResolvedStateCellInitializeProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let referenceProgram := preparation.referenceProgram
  let data := preparation.data
  let plan := preparation.productionPlan
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .initializer none "initialize"
  let handler := method.handler
  let referencePre ← match initialLogicalStateV1 referenceProgram with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell initial logical state failed: {repr error}"
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let argument : UInt64 := 7
  let stateRow ← match data.logicalState[0]? with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no state row 0"
  let field ← match plan.stateAccount.fields[0]? with
    | some value => pure value
    | none => throw "production StateCell Plan has no state field 0"
  let binding : UInt64StateAccountBindingV1 := {
    semanticStateId := stateRow.id
    semanticTypeId := stateRow.typeId
    stateName := stateRow.name
    physicalFieldIndex := 0
    accountIndex := field.accountIndex
    byteOffset := field.byteOffset
  }
  let referencePost ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le argument] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell initialize post-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let postData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker argument
  let staleValue : UInt64 := 999
  let accountData :=
    (SbpfSemantics.wordToLE (BitVec.ofNat 64 0)).append
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 staleValue.toNat))
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isSigner := true
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 ⟨accountData⟩ discriminator argument true true
  pure <| ResolvedStateCellInitializeProductionSubjectV1.mk preparation method
    referencePre referencePost binding argument referenceExecution postData
    handlerInvocation loaderInvocation

def checkStateCellInitializeProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellInitializeProductionSubjectV1 fun subject =>
    checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)

theorem checkStateCellInitializeProductionSubjectV1_sound
    (checked : checkStateCellInitializeProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellInitializeProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellInitializeProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate: run the sole Reference machine on the source-derived
    `initialize(7)` subject and compose its exact observation relation with the
    dedicated 55-step provider certificate. The gate remains fail closed and
    proof-producing; it does not define another transition or lowering. -/
def checkStateCellInitializeReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellInitializeProductionSubjectV1
    (fun subject =>
      checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
        subject.plan subject.binding subject.referencePost
        subject.referenceOutcome subject.postData subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful D5 gate recovers the exact source-derived subject, dedicated
    sparse provider certificate, and composed Reference→provider carrier. The
    Boolean premise is intentional: this theorem does not claim an
    unconditional ELF or SVM-runtime refinement. -/
theorem checkStateCellInitializeReferenceProviderSubjectV1_sound
    (checked : checkStateCellInitializeReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellInitializeProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64InitializerReferenceHandlerSbpfJoinV1 subject.data subject.plan
          subject.binding subject.referencePost subject.referenceOutcome
          subject.postData subject.argument certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellInitializeProductionSubjectV1
      (fun subject =>
        checkUInt64InitializerReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64InitializerReturnedHandlerObservationRelV1_eq_true_iff
          subject.data subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.argument
          (observeHandlerIRV1 subject.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellInitializeExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.argument.toNat)
          hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- Concrete values consumed by the certified StateCell `increment` success
    HandlerIR/provider join. The selected scenario starts at `41` and adds
    `1` along the exact 70-step provider path. -/
structure ResolvedStateCellIncrementProductionSubjectV1 where
  private mk ::
  preparation : CertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  method : CertifiedSolanaProductionMethodV1 preparation .entry
    (some "increment") "increment"
  referencePre : LogicalStateV1
  referencePost : LogicalStateV1
  binding : UInt64StateAccountBindingV1
  before : UInt64
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1 method
    referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  postData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellIncrementProductionSubjectV1

def sourceBinding (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.sourceBinding

def referenceProgram (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.referenceProgram

def data (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.data

def admitted (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.admitted

def plan (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionPlan

def ir (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionIR

def assembly (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.productionAssembly

def boundArtifact (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.preparation.boundArtifact

def handler (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.method.handler

def referenceOutcome
    (subject : ResolvedStateCellIncrementProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellIncrementProductionSubjectV1

/-- Reconstruct the increment-success subject from the same production source,
    compiler, assembly emitter, identity gate, and provider artifact as `get`
    and `initialize`. -/
def resolveStateCellIncrementProductionSubjectV1 :
    Except String ResolvedStateCellIncrementProductionSubjectV1 := do
  unless StateCell.schema == Language.ProgramExport.programExportSchemaV2 do
    throw "StateCell program export schema is not proof-forge.program-export.v2"
  let preparation ← resolveCertifiedSolanaProductionPreparationV1
    StateCell.Source.subjectV1 StateCell.bytes stateCellProductionSbpfSha256V1
  let data := preparation.data
  let plan := preparation.productionPlan
  let method ← resolveCertifiedSolanaProductionMethodV1 preparation
    .entry (some "increment") "increment"
  let handler := method.handler
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 handler.discriminator
  let before : UInt64 := 41
  let argument : UInt64 := 1
  let stateRow ← match data.logicalState[0]? with
    | some value => pure value
    | none => throw "production StateCell Semantic program has no state row 0"
  let field ← match plan.stateAccount.fields[0]? with
    | some value => pure value
    | none => throw "production StateCell Plan has no state field 0"
  let binding : UInt64StateAccountBindingV1 := {
    semanticStateId := stateRow.id
    semanticTypeId := stateRow.typeId
    stateName := stateRow.name
    physicalFieldIndex := 0
    accountIndex := field.accountIndex
    byteOffset := field.byteOffset
  }
  let referencePre ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le before] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment pre-state encoding failed: {repr error}"
  let referencePost ← match encodeLogicalStateValuesV1 data true
      #[encodeU64le (before + argument)] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment post-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 method referencePre #[{
      typeId := binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let postData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker (before + argument)
  let accountData := oneFieldUInt64AccountDataV1
    plan.stateAccount.initializedMarker before
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData := accountData.data
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 accountData discriminator argument false true
  pure <| ResolvedStateCellIncrementProductionSubjectV1.mk preparation method
    referencePre referencePost binding before argument referenceExecution postData
    handlerInvocation loaderInvocation

/-- Fail-closed certified agreement for the pinned increment-success subject. -/
def checkStateCellIncrementProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellIncrementProductionSubjectV1 fun subject =>
    checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
      subject.boundArtifact subject.handler subject.handlerInvocation
      subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

/-- Successful increment checking recovers the exact production subject and a
    carrier whose equations retain both existing evaluators and the exact
    70-step sparse provider certificate. -/
theorem checkStateCellIncrementProductionSubjectV1_sound
    (checked : checkStateCellIncrementProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
    subject.boundArtifact subject.handler subject.handlerInvocation
    subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
    (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate for the successful `increment(41, 1)` slice. It
    composes the source-derived sole Reference outcome with the dedicated
    70-step provider certificate. -/
def checkStateCellIncrementReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellIncrementProductionSubjectV1
    (fun subject =>
      checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
        subject.plan subject.binding subject.referencePost
        subject.referenceOutcome subject.postData subject.before subject.argument
        (observeHandlerIRV1 subject.handler subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
        subject.boundArtifact subject.handler subject.handlerInvocation
        subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful D5 increment gate returns one composed
    Reference→HandlerIR→provider carrier. Its Boolean premise is retained; this
    is not an unconditional ELF or SVM-runtime theorem. -/
theorem checkStateCellIncrementReferenceProviderSubjectV1_sound
    (checked : checkStateCellIncrementReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64CheckedAddReferenceHandlerSbpfJoinV1 subject.data subject.plan
          subject.binding subject.referencePost subject.referenceOutcome
          subject.postData subject.before subject.argument
          certified.executed.handlerObservation stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellIncrementProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddReturnedHandlerObservationRelV1 subject.data
          subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.before
          subject.argument
          (observeHandlerIRV1 subject.handler subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64CheckedAddReturnedHandlerObservationRelV1_eq_true_iff
          subject.data subject.plan subject.binding subject.referencePost
          subject.referenceOutcome subject.postData subject.before
          subject.argument
          (observeHandlerIRV1 subject.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellIncrementExecutedHandlerSbpfJoinV1_sound
          subject.boundArtifact subject.handler subject.handlerInvocation
          subject.loaderInvocation (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat) hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

/-- The pinned arithmetic-overflow invocation over the exact increment
    production subject. Reusing that private subject guarantees the same source,
    HandlerIR, assembly, and identity-bound provider artifact. -/
structure ResolvedStateCellIncrementOverflowProductionSubjectV1 where
  private mk ::
  production : ResolvedStateCellIncrementProductionSubjectV1
  referencePre : LogicalStateV1
  before : UInt64
  argument : UInt64
  referenceExecution : CertifiedSolanaProductionMethodReferenceV1
    production.method referencePre #[{
      typeId := production.binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  accountData : ByteArray
  handlerInvocation : InvocationObservationV1
  loaderInvocation : LoaderV3SingleAccountInvocationV1

namespace ResolvedStateCellIncrementOverflowProductionSubjectV1

def referenceOutcome
    (subject : ResolvedStateCellIncrementOverflowProductionSubjectV1) :=
  subject.referenceExecution.outcome

end ResolvedStateCellIncrementOverflowProductionSubjectV1

/-- Reconstruct `UInt64.max + 1` without another compiler or artifact path.
    The sole Reference machine and existing HandlerIR evaluator must both
    retain their exact pre-state snapshots; the provider join must observe
    status `0x1001` with the same production account bytes. -/
def resolveStateCellIncrementOverflowProductionSubjectV1 :
    Except String ResolvedStateCellIncrementOverflowProductionSubjectV1 := do
  let production ← resolveStateCellIncrementProductionSubjectV1
  let discriminator ← compileResultV1 <|
    discriminatorToLeU64V1 production.handler.discriminator
  let before : UInt64 := 0xffffffffffffffff
  let argument : UInt64 := 1
  let referencePre ← match encodeLogicalStateValuesV1 production.data true
      #[encodeU64le before] with
    | .ok value => pure value
    | .error error =>
        throw s!"StateCell increment overflow pre-state encoding failed: {repr error}"
  let referenceExecution :=
    executeCertifiedSolanaProductionMethodReferenceV1 production.method
      referencePre #[{
      typeId := production.binding.semanticTypeId
      valueBytes := encodeU64le argument
    }] #[] #[] {}
  let accountData := oneFieldUInt64AccountDataV1
    production.plan.stateAccount.initializedMarker before
  let programId := Array.replicate 32 (0x42 : UInt8)
  let loaderInvocation : LoaderV3SingleAccountInvocationV1 := {
    accountKey := Array.replicate 32 (0x24 : UInt8)
    owner := programId
    programId
    accountData := accountData.data
    instructionData :=
      (SbpfSemantics.wordToLE (BitVec.ofNat 64 discriminator.toNat)).append
        (SbpfSemantics.wordToLE (BitVec.ofNat 64 argument.toNat))
    isWritable := true
  }
  let handlerInvocation :=
    unaryUInt64InvocationV1 accountData discriminator argument false true
  pure <| ResolvedStateCellIncrementOverflowProductionSubjectV1.mk production
    referencePre before argument referenceExecution accountData handlerInvocation
    loaderInvocation

/-- Fail-closed certified agreement for the pinned increment-overflow subject. -/
def checkStateCellIncrementOverflowProductionSubjectV1 : Bool :=
  checkCertifiedSolanaProductionSubjectV1
    resolveStateCellIncrementOverflowProductionSubjectV1 fun subject =>
    checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
      subject.production.boundArtifact subject.production.handler
      subject.handlerInvocation subject.loaderInvocation
      (BitVec.ofNat 64 subject.before.toNat)
      (BitVec.ofNat 64 subject.argument.toNat)

/-- Successful checking recovers the exact 56-step provider certificate and an
    executed carrier binding the actual Handler arithmetic trap to it. -/
theorem checkStateCellIncrementOverflowProductionSubjectV1_sound
    (checked : checkStateCellIncrementOverflowProductionSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementOverflowProductionSubjectV1 = .ok subject ∧
      Nonempty (CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
        subject.production.boundArtifact subject.production.handler
        subject.handlerInvocation subject.loaderInvocation
        (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat)) := by
  rcases checkCertifiedSolanaProductionSubjectV1_sound
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      checked with ⟨subject, hsubject, hchecked⟩
  refine ⟨subject, hsubject, ?_⟩
  exact checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
    subject.production.boundArtifact subject.production.handler
    subject.handlerInvocation subject.loaderInvocation
    (BitVec.ofNat 64 subject.before.toNat)
    (BitVec.ofNat 64 subject.argument.toNat) hchecked

/-- D5 production gate for `increment(UInt64.max, 1)`. It composes the actual
    source-derived Reference overflow with the dedicated 56-step provider
    certificate and exact unchanged production account snapshot. -/
def checkStateCellIncrementOverflowReferenceProviderSubjectV1 : Bool :=
  checkCertifiedSolanaProductionCompositionV1
    resolveStateCellIncrementOverflowProductionSubjectV1
    (fun subject =>
      checkUInt64CheckedAddOverflowHandlerObservationRelV1
        subject.production.data subject.production.plan
        subject.production.binding subject.referencePre subject.referenceOutcome
        subject.accountData subject.before
        (observeHandlerIRV1 subject.production.handler
          subject.handlerInvocation))
    (fun subject =>
      checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
        subject.production.boundArtifact subject.production.handler
        subject.handlerInvocation subject.loaderInvocation
        (BitVec.ofNat 64 subject.before.toNat)
        (BitVec.ofNat 64 subject.argument.toNat))

/-- A successful overflow D5 gate recovers one composed
    Reference→HandlerIR→provider carrier. Its Boolean premise is retained; this
    is not an unconditional ELF, linker, loader, or SVM-runtime theorem. -/
theorem checkStateCellIncrementOverflowReferenceProviderSubjectV1_sound
    (checked :
      checkStateCellIncrementOverflowReferenceProviderSubjectV1 = true) :
    ∃ subject,
      resolveStateCellIncrementOverflowProductionSubjectV1 = .ok subject ∧
      ∃ certified : CertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat),
        UInt64CheckedAddOverflowReferenceHandlerSbpfJoinV1
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          certified.executed.handlerObservation
          stateCellProductionSbpfSha256V1
          certified.executed.sbpfObservation := by
  exact checkCertifiedSolanaProductionCompositionV1_sound_of_witnesses
      resolveStateCellIncrementOverflowProductionSubjectV1
      (fun subject =>
        checkUInt64CheckedAddOverflowHandlerObservationRelV1
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          (observeHandlerIRV1 subject.production.handler
            subject.handlerInvocation))
      (fun subject =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat))
      (fun subject hreference =>
        (checkUInt64CheckedAddOverflowHandlerObservationRelV1_eq_true_iff
          subject.production.data subject.production.plan
          subject.production.binding subject.referencePre
          subject.referenceOutcome subject.accountData subject.before
          (observeHandlerIRV1 subject.production.handler
            subject.handlerInvocation)).mp hreference)
      (fun subject hprovider =>
        checkCertifiedStateCellIncrementOverflowExecutedHandlerSbpfJoinV1_sound
          subject.production.boundArtifact subject.production.handler
          subject.handlerInvocation subject.loaderInvocation
          (BitVec.ofNat 64 subject.before.toNat)
          (BitVec.ofNat 64 subject.argument.toNat) hprovider)
      (fun _ certified referenceHandler =>
        certified.referenceJoin (by
          simpa [certified.executed.handlerExecution] using referenceHandler))
      checked

end ProofForgeV2.Targets.Solana
