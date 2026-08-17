import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootV1
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
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
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

private def stateCellRequirement0V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[0]'(by decide)

private def stateCellRequirement1V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[1]'(by decide)

private def stateCellRequirement2V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[2]'(by decide)

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
private theorem stateCellTypeValuesV1 :
    stateCellType0V1 = { id := 0, name := none, shape := .uint 64 } ∧
      stateCellType1V1 = { id := 1, name := none, shape := .unit } := by
  constructor <;> rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellLogicalStateV1 :
    stateCellSemanticProgramDataV1.logicalState = #[stateCellState0V1] := by
  apply Array.ext
  · decide
  · intro index hleft _hright
    match index with
    | 0 => rfl
    | n + 1 =>
        have hsize : stateCellSemanticProgramDataV1.logicalState.size = 1 := by
          decide
        rw [hsize] at hleft
        omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellState0ValueV1 :
    stateCellState0V1 = {
      id := 0
      name := "count"
      typeId := 0
      visibility := .public_
    } := by
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellEmptySemanticTablesV1 :
    stateCellSemanticProgramDataV1.constants = #[] ∧
      stateCellSemanticProgramDataV1.events = #[] ∧
      stateCellSemanticProgramDataV1.errors = #[] ∧
      stateCellSemanticProgramDataV1.invariants = #[] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellRequirementItemsV1 :
    stateCellSemanticProgramDataV1.requirements.items =
      #[stateCellRequirement0V1, stateCellRequirement1V1,
        stateCellRequirement2V1] := by
  apply Array.ext
  · decide
  · intro index hleft _hright
    have hsize : stateCellSemanticProgramDataV1.requirements.items.size = 3 := by
      decide
    rw [hsize] at hleft
    match index with
    | 0 => rfl
    | 1 => rfl
    | 2 => rfl
    | n + 3 => omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellRequirementFieldValuesV1 :
    stateCellRequirement0V1.id = "failure.atomic-rollback" ∧
      stateCellRequirement0V1.version = s2RequirementVersionV1 ∧
      stateCellRequirement0V1.digest = {
        algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1
      } ∧
      stateCellRequirement0V1.predicates = #[] ∧
    stateCellRequirement1V1.id = "state.persistent" ∧
      stateCellRequirement1V1.version = s2RequirementVersionV1 ∧
      stateCellRequirement1V1.digest = {
        algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1
      } ∧
      stateCellRequirement1V1.predicates = #[] ∧
    stateCellRequirement2V1.id = "value.checked-arithmetic" ∧
      stateCellRequirement2V1.version = s2RequirementVersionV1 ∧
      stateCellRequirement2V1.digest = {
        algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1
      } ∧
      stateCellRequirement2V1.predicates = #[] := by
  repeat' apply And.intro
  all_goals rfl

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
  rcases stateCellTypeValuesV1 with ⟨htype0, htype1⟩
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

private def stateCellCallable0Parameter0V1 : ParameterV1 :=
  stateCellCallable0V1.params[0]'(by decide)

private def stateCellCallable1Parameter0V1 : ParameterV1 :=
  stateCellCallable1V1.params[0]'(by decide)

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
private theorem stateCellCallableFieldValuesV1 :
    stateCellCallable0V1.id = 0 ∧
      stateCellCallable0V1.kind = .initializer ∧
      stateCellCallable0V1.name = none ∧
      stateCellCallable0V1.params = #[stateCellCallable0Parameter0V1] ∧
      stateCellCallable0Parameter0V1 = {
        valueId := 0, name := "initial", typeId := 0, visibility := .public_
      } ∧
      stateCellCallable0V1.result = { typeId := 1, visibility := .public_ } ∧
      stateCellCallable0V1.entryBlock = 0 ∧
      stateCellCallable0V1.loopBounds = #[] ∧
      stateCellCallable0V1.invariantSteps = none ∧
    stateCellCallable1V1.id = 1 ∧
      stateCellCallable1V1.kind = .entry ∧
      stateCellCallable1V1.name = some "increment" ∧
      stateCellCallable1V1.params = #[stateCellCallable1Parameter0V1] ∧
      stateCellCallable1Parameter0V1 = {
        valueId := 0, name := "delta", typeId := 0, visibility := .public_
      } ∧
      stateCellCallable1V1.result = { typeId := 0, visibility := .public_ } ∧
      stateCellCallable1V1.entryBlock = 0 ∧
      stateCellCallable1V1.loopBounds = #[] ∧
      stateCellCallable1V1.invariantSteps = none ∧
    stateCellCallable2V1.id = 2 ∧
      stateCellCallable2V1.kind = .view ∧
      stateCellCallable2V1.name = some "get" ∧
      stateCellCallable2V1.params = #[] ∧
      stateCellCallable2V1.result = { typeId := 0, visibility := .public_ } ∧
      stateCellCallable2V1.entryBlock = 0 ∧
      stateCellCallable2V1.loopBounds = #[] ∧
      stateCellCallable2V1.invariantSteps = none := by
  repeat' apply And.intro
  all_goals rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellBlockFieldValuesV1 :
    stateCellCallable0BlockV1.id = 0 ∧
      stateCellCallable0BlockV1.params = #[] ∧
      stateCellCallable0BlockV1.terminator = .return_ none ∧
    stateCellCallable1BlockV1.id = 0 ∧
      stateCellCallable1BlockV1.params = #[] ∧
      stateCellCallable1BlockV1.terminator = .return_ (some 3) ∧
    stateCellCallable2BlockV1.id = 0 ∧
      stateCellCallable2BlockV1.params = #[] ∧
      stateCellCallable2BlockV1.terminator = .return_ (some 0) := by
  repeat' apply And.intro
  all_goals rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellInstructionFieldValuesV1 :
    stateCellCallable0Instruction0V1.result = none ∧
      stateCellCallable0Instruction0V1.op = .stateStore 0 0 ∧
    stateCellCallable1Instruction0V1.result = some { valueId := 1, typeId := 0 } ∧
      stateCellCallable1Instruction0V1.op = .stateLoad 0 ∧
    stateCellCallable1Instruction1V1.result = some { valueId := 2, typeId := 0 } ∧
      stateCellCallable1Instruction1V1.op = .binary .add 1 0 ∧
    stateCellCallable1Instruction2V1.result = none ∧
      stateCellCallable1Instruction2V1.op = .stateStore 0 2 ∧
    stateCellCallable1Instruction3V1.result = some { valueId := 3, typeId := 0 } ∧
      stateCellCallable1Instruction3V1.op = .stateLoad 0 ∧
    stateCellCallable2Instruction0V1.result = some { valueId := 0, typeId := 0 } ∧
      stateCellCallable2Instruction0V1.op = .stateLoad 0 := by
  repeat' apply And.intro
  all_goals rfl

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

private theorem stateCellInstructionInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable0Instruction0V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction0V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction1V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction2V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction3V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable2Instruction0V1 3 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨h00Result, h00Op, h10Result, h10Op, h11Result, h11Op,
      h12Result, h12Op, h13Result, h13Op, h20Result, h20Op⟩
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable0Instruction0V1 3
      (by decide)
    · rw [h00Result]
      exact exactAt_optionValueDefV1 none 4 (by decide)
    · rw [h00Op]
      exact exactAt_semanticOp_stateStoreV1 0 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction0V1 3
      (by decide)
    · rw [h10Result]
      exact exactAt_optionValueDefV1 (some { valueId := 1, typeId := 0 }) 4
        (by decide)
    · rw [h10Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction1V1 3
      (by decide)
    · rw [h11Result]
      exact exactAt_optionValueDefV1 (some { valueId := 2, typeId := 0 }) 4
        (by decide)
    · rw [h11Op]
      exact exactAt_semanticOp_binaryAddV1 1 0 4 (by decide) (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction2V1 3
      (by decide)
    · rw [h12Result]
      exact exactAt_optionValueDefV1 none 4 (by decide)
    · rw [h12Op]
      exact exactAt_semanticOp_stateStoreV1 0 2 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction3V1 3
      (by decide)
    · rw [h13Result]
      exact exactAt_optionValueDefV1 (some { valueId := 3, typeId := 0 }) 4
        (by decide)
    · rw [h13Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable2Instruction0V1 3
      (by decide)
    · rw [h20Result]
      exact exactAt_optionValueDefV1 (some { valueId := 0, typeId := 0 }) 4
        (by decide)
    · rw [h20Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)

private theorem stateCellBlockInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable0BlockV1 2 ∧
      ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable1BlockV1 2 ∧
      ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable2BlockV1 2 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_h0Id, h0Params, h0Terminator, _h1Id, h1Params, h1Terminator,
      _h2Id, h2Params, h2Terminator⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨h0Instructions, h1Instructions, h2Instructions⟩
  rcases stateCellInstructionInversionsV1 with
    ⟨h00, h10, h11, h12, h13, h20⟩
  refine ⟨?_, ?_, ?_⟩
  · apply exactAt_block_of_fieldsV1 stateCellCallable0BlockV1 2 (by decide)
    · rw [h0Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h0Instructions]
      exact exactAt_array_one_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide)
        stateCellCallable0Instruction0V1 3 h00
    · rw [h0Terminator]
      exact exactAt_terminatorReturnV1 none 3 (by decide)
  · apply exactAt_block_of_fieldsV1 stateCellCallable1BlockV1 2 (by decide)
    · rw [h1Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h1Instructions]
      exact exactAt_array_four_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide) (by decide)
        stateCellCallable1Instruction0V1 stateCellCallable1Instruction1V1
        stateCellCallable1Instruction2V1 stateCellCallable1Instruction3V1
        3 h10 h11 h12 h13
    · rw [h1Terminator]
      exact exactAt_terminatorReturnV1 (some 3) 3 (by decide)
  · apply exactAt_block_of_fieldsV1 stateCellCallable2BlockV1 2 (by decide)
    · rw [h2Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h2Instructions]
      exact exactAt_array_one_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide)
        stateCellCallable2Instruction0V1 3 h20
    · rw [h2Terminator]
      exact exactAt_terminatorReturnV1 (some 0) 3 (by decide)

private theorem stateCellCallableInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable0V1 1 ∧
      ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable1V1 1 ∧
      ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable2V1 1 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_h0Id, h0Kind, h0Name, h0Params, h0Parameter, h0Result, _h0Entry,
      h0Loops, h0Steps, _h1Id, h1Kind, h1Name, h1Params, h1Parameter,
      h1Result, _h1Entry, h1Loops, h1Steps, _h2Id, h2Kind, h2Name,
      h2Params, h2Result, _h2Entry, h2Loops, h2Steps⟩
  rcases stateCellCallableBlockTablesV1 with ⟨h0Blocks, h1Blocks, h2Blocks⟩
  rcases stateCellBlockInversionsV1 with ⟨h0Block, h1Block, h2Block⟩
  refine ⟨?_, ?_, ?_⟩
  · apply exactAt_callable_of_fieldsV1 stateCellCallable0V1 1 (by decide)
    · rw [h0Kind]
      exact exactAt_callableKindV1 .initializer 2 (by decide)
    · rw [h0Name]
      exact exactAt_option_noneV1 encodeString decodeString 2
    · rw [h0Params]
      apply exactAt_array_one_of_exactAtV1 encodeParameterV1 decodeParameterV1
        maxArrayElements (by decide) stateCellCallable0Parameter0V1 2
      rw [h0Parameter]
      exact exactAt_parameter_publicV1 0 0 "initial" (by rfl) 2 (by decide)
    · rw [h0Result]
      exact exactAt_callableResultV1
        ({ typeId := 1, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h0Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable0BlockV1 2 h0Block
    · rw [h0Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h0Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2
  · apply exactAt_callable_of_fieldsV1 stateCellCallable1V1 1 (by decide)
    · rw [h1Kind]
      exact exactAt_callableKindV1 .entry 2 (by decide)
    · rw [h1Name]
      exact exactAt_optionString_some_identifierV1 "increment" (by rfl) 2
    · rw [h1Params]
      apply exactAt_array_one_of_exactAtV1 encodeParameterV1 decodeParameterV1
        maxArrayElements (by decide) stateCellCallable1Parameter0V1 2
      rw [h1Parameter]
      exact exactAt_parameter_publicV1 0 0 "delta" (by rfl) 2 (by decide)
    · rw [h1Result]
      exact exactAt_callableResultV1
        ({ typeId := 0, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h1Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable1BlockV1 2 h1Block
    · rw [h1Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h1Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2
  · apply exactAt_callable_of_fieldsV1 stateCellCallable2V1 1 (by decide)
    · rw [h2Kind]
      exact exactAt_callableKindV1 .view 2 (by decide)
    · rw [h2Name]
      exact exactAt_optionString_some_identifierV1 "get" (by rfl) 2
    · rw [h2Params]
      exact exactAt_array_emptyV1 encodeParameterV1 decodeParameterV1
        maxArrayElements 2
    · rw [h2Result]
      exact exactAt_callableResultV1
        ({ typeId := 0, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h2Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable2BlockV1 2 h2Block
    · rw [h2Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h2Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2

/-- Source-derived qualified-name topology. The equation observes the output of
    the sole production identity lowerer; it is not a supplied Semantic AST. -/
private theorem stateCellQualifiedNameComponentsV1 :
    renderQualifiedNameComponents stateCellSemanticProgramDataV1.qualifiedName =
      .ok #["ProofForgeV2", "Examples", "StateCell", "ProofForgeV2",
        "Examples", "StateCell"] := by
  rfl

private theorem encodePublicVisibilityV1 :
    encodeVisibilityV1 (.public_ : VisibilityV1) =
      .ok (taggedBytesV1 "Visibility.Public" #[]) := by
  simp only [encodeVisibilityV1, encodeNullary]
  exact encodeTagged_eq_okV1 "Visibility.Public" #[]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem stateCellQualifiedNameEncodingV1 :
    ∃ bytes,
      encodeQualifiedName stateCellSemanticProgramDataV1.qualifiedName = .ok bytes ∧
        bytes.size ≤ 1024 := by
  let b0 := (encodeU32le (UInt32.ofNat "ProofForgeV2".toUTF8.size)).append
    "ProofForgeV2".toUTF8
  let b1 := (encodeU32le (UInt32.ofNat "Examples".toUTF8.size)).append
    "Examples".toUTF8
  let b2 := (encodeU32le (UInt32.ofNat "StateCell".toUTF8.size)).append
    "StateCell".toUTF8
  have h0 : encodeString "ProofForgeV2" = .ok b0 := by
    exact encodeString_eq_okV1 "ProofForgeV2"
      (requireNfc_eq_ok_of_isAscii "ProofForgeV2" (by decide)) (by decide)
  have h1 : encodeString "Examples" = .ok b1 := by
    exact encodeString_eq_okV1 "Examples"
      (requireNfc_eq_ok_of_isAscii "Examples" (by decide)) (by decide)
  have h2 : encodeString "StateCell" = .ok b2 := by
    exact encodeString_eq_okV1 "StateCell"
      (requireNfc_eq_ok_of_isAscii "StateCell" (by decide)) (by decide)
  let bytes := (encodeU32le 6).append
    (((((b0.append b1).append b2).append b0).append b1).append b2)
  have harray :
      encodeArray encodeString
          #["ProofForgeV2", "Examples", "StateCell", "ProofForgeV2",
            "Examples", "StateCell"] =
        .ok bytes := by
    simpa only [bytes] using
      encodeArray_sixV1 encodeString "ProofForgeV2" "Examples" "StateCell"
        "ProofForgeV2" "Examples" "StateCell" b0 b1 b2 b0 b1 b2
        h0 h1 h2 h0 h1 h2
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeQualifiedName, mapCommon,
      stateCellQualifiedNameComponentsV1, harray, Bind.bind, Except.bind]
  · decide

private theorem stateCellTypesEncodingV1 :
    ∃ bytes,
      encodeArray encodeTypeDeclV1 stateCellSemanticProgramDataV1.types = .ok bytes ∧
        bytes.size ≤ 512 := by
  rcases stateCellTypeValuesV1 with ⟨htype0, htype1⟩
  let uintShapeB := taggedBytesV1 "Type.UInt" #[encodeU16le 64]
  let unitShapeB := taggedBytesV1 "Type.Unit" #[]
  let type0B := taggedBytesV1 "TypeDecl"
    #[encodeU32le 0, encodeU8 0, uintShapeB]
  let type1B := taggedBytesV1 "TypeDecl"
    #[encodeU32le 1, encodeU8 0, unitShapeB]
  have huint : encodeTypeShapeV1 (.uint 64) = .ok uintShapeB := by
    simp only [encodeTypeShapeV1, uintShapeB]
    exact encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have hunit : encodeTypeShapeV1 .unit = .ok unitShapeB := by
    simp only [encodeTypeShapeV1, encodeNullary, unitShapeB]
    exact encodeTagged_eq_okV1 "Type.Unit" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have htype0 : encodeTypeDeclV1 stateCellType0V1 = .ok type0B := by
    rw [htype0]
    simp only [encodeTypeDeclV1, encodeOption, huint, type0B, Bind.bind,
      Except.bind]
    exact encodeTagged_eq_okV1 "TypeDecl"
      #[encodeU32le 0, encodeU8 0, uintShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have htype1 : encodeTypeDeclV1 stateCellType1V1 = .ok type1B := by
    rw [htype1]
    simp only [encodeTypeDeclV1, encodeOption, hunit, type1B, Bind.bind,
      Except.bind]
    exact encodeTagged_eq_okV1 "TypeDecl"
      #[encodeU32le 1, encodeU8 0, unitShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := (encodeU32le 2).append (type0B.append type1B)
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellTypesV1]
    simpa only [bytes] using encodeArray_twoV1 encodeTypeDeclV1
      stateCellType0V1 stateCellType1V1 type0B type1B htype0 htype1
  · decide

private theorem stateCellLogicalStateEncodingV1 :
    ∃ bytes,
      encodeArray encodeStateDeclV1 stateCellSemanticProgramDataV1.logicalState =
          .ok bytes ∧
        bytes.size ≤ 512 := by
  let nameB := (encodeU32le (UInt32.ofNat "count".toUTF8.size)).append
    "count".toUTF8
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let stateB := taggedBytesV1 "StateDecl"
    #[encodeU32le 0, nameB, encodeU32le 0, visibilityB]
  have hname : encodeString "count" = .ok nameB := by
    exact encodeString_eq_okV1 "count"
      (requireNfc_eq_ok_of_isAscii "count" (by decide)) (by decide)
  have hstate : encodeStateDeclV1 stateCellState0V1 = .ok stateB := by
    rw [stateCellState0ValueV1]
    simp only [encodeStateDeclV1, hname, encodePublicVisibilityV1, stateB,
      visibilityB, Bind.bind, Except.bind]
    exact encodeTagged_eq_okV1 "StateDecl"
      #[encodeU32le 0, nameB, encodeU32le 0, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := (encodeU32le 1).append stateB
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellLogicalStateV1]
    simpa only [bytes] using encodeArray_oneV1 encodeStateDeclV1
      stateCellState0V1 stateB hstate
  · decide

private theorem stateCellEmptySemanticTableEncodingsV1 :
    encodeArray encodeConstantV1 stateCellSemanticProgramDataV1.constants =
        .ok (encodeU32le 0) ∧
      encodeArray encodeEventDeclV1 stateCellSemanticProgramDataV1.events =
        .ok (encodeU32le 0) ∧
      encodeArray encodeErrorDeclV1 stateCellSemanticProgramDataV1.errors =
        .ok (encodeU32le 0) ∧
      encodeArray encodeInvariantDeclV1 stateCellSemanticProgramDataV1.invariants =
        .ok (encodeU32le 0) := by
  rcases stateCellEmptySemanticTablesV1 with ⟨hconstants, hevents, herrors, hinvariants⟩
  rw [hconstants, hevents, herrors, hinvariants]
  exact ⟨encodeArray_zeroV1 encodeConstantV1,
    encodeArray_zeroV1 encodeEventDeclV1,
    encodeArray_zeroV1 encodeErrorDeclV1,
    encodeArray_zeroV1 encodeInvariantDeclV1⟩

private theorem encodeOptionalValueDefNoneV1 :
    encodeOption encodeValueDefV1 (none : Option ValueDefV1) = .ok (encodeU8 0) ∧
      (encodeU8 0).size ≤ 256 := by
  exact ⟨rfl, by rw [encodeU8_size]; decide⟩

private theorem encodeOptionalValueDefSomeV1 (value : ValueDefV1) :
    ∃ bytes,
      encodeOption encodeValueDefV1 (some value) = .ok bytes ∧ bytes.size ≤ 256 := by
  let valueB := taggedBytesV1 "ValueDef"
    #[encodeU32le value.valueId, encodeU32le value.typeId]
  have hvalue : encodeValueDefV1 value = .ok valueB := by
    simp only [encodeValueDefV1, valueB]
    exact encodeTagged_eq_okV1 "ValueDef"
      #[encodeU32le value.valueId, encodeU32le value.typeId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  let bytes := (encodeU8 1).append valueB
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeOption, hvalue, bytes, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  · simp only [bytes]
    rw [ByteArray_size_append, encodeU8_size, taggedBytesV1_size,
      foldl_size_two, encodeU32le_size, encodeU32le_size]
    have ht : "ValueDef".toUTF8.size = 8 := by decide
    rw [ht]
    decide

private theorem encodeStateLoadOpV1 (stateId : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.stateLoad stateId) = .ok bytes ∧ bytes.size ≤ 256 := by
  let bytes := taggedBytesV1 "Op.StateLoad" #[encodeU32le stateId]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, bytes]
    exact encodeTagged_eq_okV1 "Op.StateLoad" #[encodeU32le stateId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one, encodeU32le_size]
    have ht : "Op.StateLoad".toUTF8.size = 12 := by decide
    rw [ht]
    decide

private theorem encodeStateStoreOpV1 (stateId valueId : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.stateStore stateId valueId) = .ok bytes ∧
        bytes.size ≤ 256 := by
  let bytes := taggedBytesV1 "Op.StateStore"
    #[encodeU32le stateId, encodeU32le valueId]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, bytes]
    exact encodeTagged_eq_okV1 "Op.StateStore"
      #[encodeU32le stateId, encodeU32le valueId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_two, encodeU32le_size,
      encodeU32le_size]
    have ht : "Op.StateStore".toUTF8.size = 13 := by decide
    rw [ht]
    decide

private theorem encodeBinaryAddOpV1 (lhs rhs : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.binary .add lhs rhs) = .ok bytes ∧ bytes.size ≤ 256 := by
  let operatorB := taggedBytesV1 "Binary.Add" #[]
  have hoperator : encodeBinaryOpV1 .add = .ok operatorB := by
    simp only [encodeBinaryOpV1, encodeNullary, operatorB]
    exact encodeTagged_eq_okV1 "Binary.Add" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := taggedBytesV1 "Op.Binary"
    #[operatorB, encodeU32le lhs, encodeU32le rhs]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, hoperator, bytes, Bind.bind, Except.bind]
    exact encodeTagged_eq_okV1 "Op.Binary"
      #[operatorB, encodeU32le lhs, encodeU32le rhs]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_three, encodeU32le_size,
      encodeU32le_size]
    have houter : "Op.Binary".toUTF8.size = 9 := by decide
    have hoperatorSize : operatorB.size = 16 := by
      simp only [operatorB]
      rw [taggedBytesV1_size]
      decide
    rw [houter, hoperatorSize]
    decide

private theorem encodeInstructionV1_ok_size_of_fields
    (instruction : InstructionV1) (resultB opB : ByteArray)
    (hresult : encodeOption encodeValueDefV1 instruction.result = .ok resultB)
    (hop : encodeSemanticOpV1 instruction.op = .ok opB)
    (hresultSize : resultB.size ≤ 256) (hopSize : opB.size ≤ 256) :
    ∃ bytes, encodeInstructionV1 instruction = .ok bytes ∧ bytes.size ≤ 1024 := by
  let bytes := taggedBytesV1 "Instruction" #[resultB, opB]
  have htag : encodeTagged "Instruction" #[resultB, opB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Instruction" #[resultB, opB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes,
    encodeInstructionV1_eq_of_fields instruction resultB opB bytes hresult hop htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_two]
  have ht : "Instruction".toUTF8.size = 11 := by decide
  rw [ht]
  omega

private theorem stateCellCallable0Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable0Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨hresult, hop, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  rcases encodeOptionalValueDefNoneV1 with ⟨hresultB, hresultSize⟩
  rcases encodeStateStoreOpV1 0 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable0Instruction0V1
    (encodeU8 0) opB
  · simpa only [hresult] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, hresult, hop, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 1, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction0V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction1EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction1V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, hresult, hop, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 2, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeBinaryAddOpV1 1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction1V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction2EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction2V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, hresult,
      hop, _hresult13, _hop13, _hresult20, _hop20⟩
  rcases encodeOptionalValueDefNoneV1 with ⟨hresultB, hresultSize⟩
  rcases encodeStateStoreOpV1 0 2 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction2V1
    (encodeU8 0) opB
  · simpa only [hresult] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction3EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction3V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, hresult, hop, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 3, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction3V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable2Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable2Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, hresult, hop⟩
  let value : ValueDefV1 := { valueId := 0, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable2Instruction0V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem encodeReturnTerminatorV1 (value : Option UInt32) :
    ∃ bytes,
      encodeTerminatorV1 (.return_ value) = .ok bytes ∧ bytes.size ≤ 256 := by
  let valueB := match value with
    | none => encodeU8 0
    | some id => (encodeU8 1).append (encodeU32le id)
  have hvalue :
      encodeOption (fun id => pure (encodeU32le id)) value = .ok valueB := by
    cases value <;> rfl
  let bytes := taggedBytesV1 "Term.Return" #[valueB]
  have htag : encodeTagged "Term.Return" #[valueB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Term.Return" #[valueB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeTerminatorV1, hvalue, htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one]
    have htagSize : "Term.Return".toUTF8.size = 11 := by decide
    have hvalueSize : valueB.size ≤ 5 := by
      cases value with
      | none =>
          simp only [valueB, encodeU8_size]
          decide
      | some id =>
          simp only [valueB, ByteArray_size_append, encodeU8_size,
            encodeU32le_size]
          decide
    rw [htagSize]
    omega

private theorem encodeBlockV1_ok_size_of_fields
    (block : BlockV1) (paramsB instructionsB terminatorB : ByteArray)
    (hparams : encodeArray encodeBlockParameterV1 block.params = .ok paramsB)
    (hinstructions : encodeArray encodeInstructionV1 block.instructions =
      .ok instructionsB)
    (hterminator : encodeTerminatorV1 block.terminator = .ok terminatorB)
    (hparamsSize : paramsB.size ≤ 256)
    (hinstructionsSize : instructionsB.size ≤ 8192)
    (hterminatorSize : terminatorB.size ≤ 256) :
    ∃ bytes, encodeBlockV1 block = .ok bytes ∧ bytes.size ≤ 65536 := by
  let bytes := taggedBytesV1 "Block"
    #[encodeU32le block.id, paramsB, instructionsB, terminatorB]
  have htag :
      encodeTagged "Block"
          #[encodeU32le block.id, paramsB, instructionsB, terminatorB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Block"
      #[encodeU32le block.id, paramsB, instructionsB, terminatorB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, encodeBlockV1_eq_of_fields block paramsB instructionsB
    terminatorB bytes hparams hinstructions hterminator htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_four, encodeU32le_size]
  have htagSize : "Block".toUTF8.size = 5 := by decide
  rw [htagSize]
  omega

private theorem stateCellCallable0BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable0BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid, hparams, hterminator, _hid1, _hparams1, _hterminator1,
      _hid2, _hparams2, _hterminator2⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨hinstructions, _hinstructions1, _hinstructions2⟩
  rcases stateCellCallable0Instruction0EncodingV1 with
    ⟨instructionB, hinstruction, hinstructionSize⟩
  let instructionsB := (encodeU32le 1).append instructionB
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable0BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_oneV1 encodeInstructionV1
      stateCellCallable0Instruction0V1 instructionB hinstruction
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 none with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable0BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem stateCellCallable1BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable1BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid0, _hparams0, _hterminator0, _hid, hparams, hterminator,
      _hid2, _hparams2, _hterminator2⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, hinstructions, _hinstructions2⟩
  rcases stateCellCallable1Instruction0EncodingV1 with
    ⟨instruction0B, hinstruction0, hinstruction0Size⟩
  rcases stateCellCallable1Instruction1EncodingV1 with
    ⟨instruction1B, hinstruction1, hinstruction1Size⟩
  rcases stateCellCallable1Instruction2EncodingV1 with
    ⟨instruction2B, hinstruction2, hinstruction2Size⟩
  rcases stateCellCallable1Instruction3EncodingV1 with
    ⟨instruction3B, hinstruction3, hinstruction3Size⟩
  let instructionsB := (encodeU32le 4).append
    (((instruction0B.append instruction1B).append instruction2B).append
      instruction3B)
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable1BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_fourV1 encodeInstructionV1
      stateCellCallable1Instruction0V1 stateCellCallable1Instruction1V1
      stateCellCallable1Instruction2V1 stateCellCallable1Instruction3V1
      instruction0B instruction1B instruction2B instruction3B hinstruction0
      hinstruction1 hinstruction2 hinstruction3
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 (some 3) with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable1BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem stateCellCallable2BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable2BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid0, _hparams0, _hterminator0, _hid1, _hparams1, _hterminator1,
      _hid, hparams, hterminator⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, _hinstructions1, hinstructions⟩
  rcases stateCellCallable2Instruction0EncodingV1 with
    ⟨instructionB, hinstruction, hinstructionSize⟩
  let instructionsB := (encodeU32le 1).append instructionB
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable2BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_oneV1 encodeInstructionV1
      stateCellCallable2Instruction0V1 instructionB hinstruction
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 (some 0) with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable2BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem encodeInitializerCallableKindV1 :
    encodeCallableKindV1 .initializer =
        .ok (taggedBytesV1 "Callable.Initializer" #[]) ∧
      (taggedBytesV1 "Callable.Initializer" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.Initializer" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeEntryCallableKindV1 :
    encodeCallableKindV1 .entry =
        .ok (taggedBytesV1 "Callable.Entry" #[]) ∧
      (taggedBytesV1 "Callable.Entry" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.Entry" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeViewCallableKindV1 :
    encodeCallableKindV1 .view =
        .ok (taggedBytesV1 "Callable.View" #[]) ∧
      (taggedBytesV1 "Callable.View" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.View" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeOptionalAsciiStringSomeV1 (value : String)
    (hascii : isAscii value = true) (hsize : value.toUTF8.size ≤ 240) :
    ∃ bytes,
      encodeOption encodeString (some value) = .ok bytes ∧ bytes.size ≤ 512 := by
  let stringB := (encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8
  have hstring : encodeString value = .ok stringB := by
    exact encodeString_eq_okV1 value (requireNfc_eq_ok_of_isAscii value hascii)
      (Nat.le_trans hsize (by decide))
  let bytes := (encodeU8 1).append stringB
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeOption, hstring, bytes, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  · simp only [bytes, stringB, ByteArray_size_append, encodeU8_size,
      encodeU32le_size]
    omega

private theorem encodePublicParameterV1 (valueId typeId : UInt32) (name : String)
    (hascii : isAscii name = true) (hsize : name.toUTF8.size ≤ 240) :
    ∃ bytes,
      encodeParameterV1 {
        valueId, name, typeId, visibility := .public_
      } = .ok bytes ∧ bytes.size ≤ 512 := by
  let nameB := (encodeU32le (UInt32.ofNat name.toUTF8.size)).append name.toUTF8
  have hname : encodeString name = .ok nameB := by
    exact encodeString_eq_okV1 name (requireNfc_eq_ok_of_isAscii name hascii)
      (Nat.le_trans hsize (by decide))
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let bytes := taggedBytesV1 "Parameter"
    #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB]
  have htag :
      encodeTagged "Parameter"
          #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Parameter"
      #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeParameterV1, hname, encodePublicVisibilityV1, visibilityB,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_four, encodeU32le_size,
      encodeU32le_size]
    have htagSize : "Parameter".toUTF8.size = 9 := by decide
    have hnameSize : nameB.size = 4 + name.toUTF8.size := by
      simp only [nameB, ByteArray_size_append, encodeU32le_size]
    have hvisibilitySize : visibilityB.size = 23 := by
      simp only [visibilityB]
      rw [taggedBytesV1_size]
      decide
    rw [htagSize, hnameSize, hvisibilitySize]
    omega

private theorem encodePublicCallableResultV1 (typeId : UInt32) :
    ∃ bytes,
      encodeCallableResultV1 { typeId, visibility := .public_ } = .ok bytes ∧
        bytes.size ≤ 256 := by
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let bytes := taggedBytesV1 "CallableResult" #[encodeU32le typeId, visibilityB]
  have htag :
      encodeTagged "CallableResult" #[encodeU32le typeId, visibilityB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "CallableResult"
      #[encodeU32le typeId, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeCallableResultV1, encodePublicVisibilityV1, visibilityB,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_two, encodeU32le_size]
    have htagSize : "CallableResult".toUTF8.size = 14 := by decide
    have hvisibilitySize : visibilityB.size = 23 := by
      simp only [visibilityB]
      rw [taggedBytesV1_size]
      decide
    rw [htagSize, hvisibilitySize]
    decide

private theorem encodeCallableV1_ok_size_of_fields
    (callable : CallableV1)
    (kindB nameB paramsB resultB blocksB loopB stepsB : ByteArray)
    (hkind : encodeCallableKindV1 callable.kind = .ok kindB)
    (hname : encodeOption encodeString callable.name = .ok nameB)
    (hparams : encodeArray encodeParameterV1 callable.params = .ok paramsB)
    (hresult : encodeCallableResultV1 callable.result = .ok resultB)
    (hblocks : encodeArray encodeBlockV1 callable.blocks = .ok blocksB)
    (hloop : encodeArray encodeLoopBoundV1 callable.loopBounds = .ok loopB)
    (hsteps : encodeOption (fun v => pure (encodeU64le v))
      callable.invariantSteps = .ok stepsB)
    (hkindSize : kindB.size ≤ 64) (hnameSize : nameB.size ≤ 512)
    (hparamsSize : paramsB.size ≤ 1024) (hresultSize : resultB.size ≤ 256)
    (hblocksSize : blocksB.size ≤ 131072) (hloopSize : loopB.size ≤ 256)
    (hstepsSize : stepsB.size ≤ 16) :
    ∃ bytes, encodeCallableV1 callable = .ok bytes ∧ bytes.size ≤ 262144 := by
  let bytes := taggedBytesV1 "Callable" #[encodeU32le callable.id, kindB,
    nameB, paramsB, resultB, encodeU32le callable.entryBlock, blocksB, loopB,
    stepsB]
  have htag :
      encodeTagged "Callable" #[encodeU32le callable.id, kindB, nameB, paramsB,
          resultB, encodeU32le callable.entryBlock, blocksB, loopB, stepsB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Callable"
      #[encodeU32le callable.id, kindB, nameB, paramsB, resultB,
        encodeU32le callable.entryBlock, blocksB, loopB, stepsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, encodeCallableV1_eq_of_fields callable kindB nameB paramsB
    resultB blocksB loopB stepsB bytes hkind hname hparams hresult hblocks hloop
    hsteps htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_nine, encodeU32le_size,
    encodeU32le_size]
  have htagSize : "Callable".toUTF8.size = 8 := by decide
  rw [htagSize]
  omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable0V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid, hkind, hname, hparams, hparameter, hresult, _hentry, hloop, hsteps,
      _hid1, _hkind1, _hname1, _hparams1, _hparameter1, _hresult1, _hentry1,
      _hloop1, _hsteps1, _hid2, _hkind2, _hname2, _hparams2, _hresult2,
      _hentry2, _hloop2, _hsteps2⟩
  rcases stateCellCallableBlockTablesV1 with ⟨hblocks, _hblocks1, _hblocks2⟩
  rcases encodeInitializerCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodePublicParameterV1 0 0 "initial" (by decide) (by decide) with
    ⟨parameterB, hparameterB, hparameterSize⟩
  have hparameterB' :
      encodeParameterV1 stateCellCallable0Parameter0V1 = .ok parameterB := by
    simpa only [hparameter] using hparameterB
  let paramsB := (encodeU32le 1).append parameterB
  have hparamsB : encodeArray encodeParameterV1 stateCellCallable0V1.params =
      .ok paramsB := by
    rw [hparams]
    simpa only [paramsB] using encodeArray_oneV1 encodeParameterV1
      stateCellCallable0Parameter0V1 parameterB hparameterB'
  have hparamsSize : paramsB.size ≤ 1024 := by
    simp only [paramsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodePublicCallableResultV1 1 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable0BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable0V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable0BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable0V1
    (taggedBytesV1 "Callable.Initializer" #[]) (encodeU8 0) paramsB resultB
    blocksB (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · rw [hname]
    rfl
  · exact hparamsB
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · rw [encodeU8_size]
    decide
  · exact hparamsSize
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable1V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparameter0, _hresult0, _hentry0,
      _hloop0, _hsteps0, _hid, hkind, hname, hparams, hparameter, hresult,
      _hentry, hloop, hsteps, _hid2, _hkind2, _hname2, _hparams2, _hresult2,
      _hentry2, _hloop2, _hsteps2⟩
  rcases stateCellCallableBlockTablesV1 with ⟨_hblocks0, hblocks, _hblocks2⟩
  rcases encodeEntryCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodeOptionalAsciiStringSomeV1 "increment" (by decide) (by decide) with
    ⟨nameB, hnameB, hnameSize⟩
  rcases encodePublicParameterV1 0 0 "delta" (by decide) (by decide) with
    ⟨parameterB, hparameterB, hparameterSize⟩
  have hparameterB' :
      encodeParameterV1 stateCellCallable1Parameter0V1 = .ok parameterB := by
    simpa only [hparameter] using hparameterB
  let paramsB := (encodeU32le 1).append parameterB
  have hparamsB : encodeArray encodeParameterV1 stateCellCallable1V1.params =
      .ok paramsB := by
    rw [hparams]
    simpa only [paramsB] using encodeArray_oneV1 encodeParameterV1
      stateCellCallable1Parameter0V1 parameterB hparameterB'
  have hparamsSize : paramsB.size ≤ 1024 := by
    simp only [paramsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodePublicCallableResultV1 0 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable1BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable1V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable1BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable1V1
    (taggedBytesV1 "Callable.Entry" #[]) nameB paramsB resultB blocksB
    (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · simpa only [hname] using hnameB
  · exact hparamsB
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · exact hnameSize
  · exact hparamsSize
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable2V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparameter0, _hresult0, _hentry0,
      _hloop0, _hsteps0, _hid1, _hkind1, _hname1, _hparams1, _hparameter1,
      _hresult1, _hentry1, _hloop1, _hsteps1, _hid, hkind, hname, hparams,
      hresult, _hentry, hloop, hsteps⟩
  rcases stateCellCallableBlockTablesV1 with ⟨_hblocks0, _hblocks1, hblocks⟩
  rcases encodeViewCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodeOptionalAsciiStringSomeV1 "get" (by decide) (by decide) with
    ⟨nameB, hnameB, hnameSize⟩
  rcases encodePublicCallableResultV1 0 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable2BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable2V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable2BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable2V1
    (taggedBytesV1 "Callable.View" #[]) nameB (encodeU32le 0) resultB blocksB
    (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · simpa only [hname] using hnameB
  · simpa only [hparams] using encodeArray_zeroV1 encodeParameterV1
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · exact hnameSize
  · rw [encodeU32le_size]
    decide
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallablesEncodingV1 :
    ∃ bytes,
      encodeArray encodeCallableV1 stateCellSemanticProgramDataV1.callables =
          .ok bytes ∧
        bytes.size ≤ 1048576 := by
  rcases stateCellCallable0EncodingV1 with ⟨callable0B, hcallable0, hsize0⟩
  rcases stateCellCallable1EncodingV1 with ⟨callable1B, hcallable1, hsize1⟩
  rcases stateCellCallable2EncodingV1 with ⟨callable2B, hcallable2, hsize2⟩
  let bytes := (encodeU32le 3).append
    ((callable0B.append callable1B).append callable2B)
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellCallablesV1]
    simpa only [bytes] using encodeArray_threeV1 encodeCallableV1
      stateCellCallable0V1 stateCellCallable1V1 stateCellCallable2V1
      callable0B callable1B callable2B hcallable0 hcallable1 hcallable2
  · simp only [bytes, ByteArray_size_append, encodeU32le_size]
    omega

private theorem encodeRequirementRequestV1_ok_size_of_fields
    (request : RequirementRequestV1)
    (idB versionB digestB predicatesB : ByteArray)
    (hid : encodeString request.id = .ok idB)
    (hversion : encodeSemVer request.version = .ok versionB)
    (hdigest : encodeDigest request.digest = .ok digestB)
    (hpredicates : encodeArray encodeRequirementPredicateV1 request.predicates =
      .ok predicatesB)
    (hidSize : idB.size ≤ 512) (hversionSize : versionB.size ≤ 512)
    (hdigestSize : digestB.size ≤ 64) (hpredicatesSize : predicatesB.size ≤ 256) :
    ∃ bytes,
      encodeRequirementRequestV1 request = .ok bytes ∧ bytes.size ≤ 2048 := by
  let bytes := taggedBytesV1 "RequirementRequest"
    #[idB, versionB, digestB, predicatesB]
  have htag :
      encodeTagged "RequirementRequest" #[idB, versionB, digestB, predicatesB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "RequirementRequest"
      #[idB, versionB, digestB, predicatesB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeRequirementRequestV1, hid, hversion, hdigest, hpredicates,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_four]
    have htagSize : "RequirementRequest".toUTF8.size = 18 := by decide
    rw [htagSize]
    omega

private theorem encodeClosedS2RequirementV1
    (request : RequirementRequestV1) (id : String) (digestBytes : ByteArray)
    (hid : request.id = id)
    (hversion : request.version = s2RequirementVersionV1)
    (hdigest : request.digest = { algorithm := .sha256, bytes := digestBytes })
    (hpredicates : request.predicates = #[])
    (hascii : isAscii id = true) (hidSize : id.toUTF8.size ≤ 240)
    (hdigestSize : digestBytes.size = 32) :
    ∃ bytes,
      encodeRequirementRequestV1 request = .ok bytes ∧ bytes.size ≤ 2048 := by
  let idB := (encodeU32le (UInt32.ofNat id.toUTF8.size)).append id.toUTF8
  have hidB : encodeString request.id = .ok idB := by
    rw [hid]
    exact encodeString_eq_okV1 id (requireNfc_eq_ok_of_isAscii id hascii)
      (Nat.le_trans hidSize (by decide))
  let versionB := (encodeU32le 5).append "1.0.0".toUTF8
  have hversionB : encodeSemVer request.version = .ok versionB := by
    rw [hversion]
    have hstring :
        encodeString "1.0.0" = .ok versionB := by
      exact encodeString_eq_okV1 "1.0.0"
        (requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)) (by decide)
    simp only [encodeSemVer, mapCommon,
      show renderSemVer s2RequirementVersionV1 = .ok "1.0.0" by rfl,
      hstring, Bind.bind, Except.bind]
  have hdigestB : encodeDigest request.digest = .ok digestBytes := by
    rw [hdigest]
    have hdigestValid :
        validateDigest ({ algorithm := .sha256, bytes := digestBytes } : Digest) =
          .ok () := by
      simp [validateDigest, hdigestSize]
      rfl
    simp only [encodeDigest, mapCommon, hdigestValid, Bind.bind, Pure.pure,
      Except.bind, Except.pure]
  have hpredicatesB :
      encodeArray encodeRequirementPredicateV1 request.predicates =
        .ok (encodeU32le 0) := by
    rw [hpredicates]
    exact encodeArray_zeroV1 encodeRequirementPredicateV1
  apply encodeRequirementRequestV1_ok_size_of_fields request idB versionB
    digestBytes (encodeU32le 0) hidB hversionB hdigestB hpredicatesB
  · simp only [idB, ByteArray_size_append, encodeU32le_size]
    omega
  · simp only [versionB, ByteArray_size_append, encodeU32le_size]
    decide
  · omega
  · rw [encodeU32le_size]
    decide

private theorem stateCellRequirementsEncodingV1 :
    ∃ bytes,
      encodeProgramRequirementsV1 stateCellSemanticProgramDataV1.requirements =
          .ok bytes ∧
        bytes.size ≤ 8192 := by
  rcases stateCellRequirementFieldValuesV1 with
    ⟨hid0, hversion0, hdigest0, hpredicates0, hid1, hversion1, hdigest1,
      hpredicates1, hid2, hversion2, hdigest2, hpredicates2⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement0V1
      "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1 hid0
      hversion0 hdigest0 hpredicates0 (by decide) (by decide) (by rfl) with
    ⟨request0B, hrequest0, hrequest0Size⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement1V1
      "state.persistent" s2StatePersistentDigestBytesV1 hid1 hversion1 hdigest1
      hpredicates1 (by decide) (by decide) (by rfl) with
    ⟨request1B, hrequest1, hrequest1Size⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement2V1
      "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1 hid2
      hversion2 hdigest2 hpredicates2 (by decide) (by decide) (by rfl) with
    ⟨request2B, hrequest2, hrequest2Size⟩
  let itemsB := (encodeU32le 3).append
    ((request0B.append request1B).append request2B)
  have hitems :
      encodeArray encodeRequirementRequestV1
          stateCellSemanticProgramDataV1.requirements.items = .ok itemsB := by
    rw [stateCellRequirementItemsV1]
    simpa only [itemsB] using encodeArray_threeV1 encodeRequirementRequestV1
      stateCellRequirement0V1 stateCellRequirement1V1 stateCellRequirement2V1
      request0B request1B request2B hrequest0 hrequest1 hrequest2
  have hitemsSize : itemsB.size ≤ 7168 := by
    simp only [itemsB, ByteArray_size_append, encodeU32le_size]
    omega
  let bytes := taggedBytesV1 "ProgramRequirements" #[itemsB]
  have htag : encodeTagged "ProgramRequirements" #[itemsB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "ProgramRequirements" #[itemsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeProgramRequirementsV1, hitems, htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one]
    have htagSize : "ProgramRequirements".toUTF8.size = 19 := by decide
    rw [htagSize]
    omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellRootFieldInvertV1 :
    RootFieldInvertV1 stateCellSemanticProgramDataV1 := by
  rcases stateCellTypeValuesV1 with ⟨htype0, htype1⟩
  rcases stateCellEmptySemanticTablesV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  rcases stateCellCallableInversionsV1 with
    ⟨hcallable0, hcallable1, hcallable2⟩
  rcases stateCellRequirementFieldValuesV1 with
    ⟨hid0, hversion0, hdigest0, hpredicates0, hid1, hversion1, hdigest1,
      hpredicates1, hid2, hversion2, hdigest2, hpredicates2⟩
  have hrequest0 : stateCellRequirement0V1 = {
      id := "failure.atomic-rollback"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2FailureAtomicRollbackDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement0V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid0 hversion0 hdigest0 hpredicates0
        simp only [hid0, hversion0, hdigest0, hpredicates0]
  have hrequest1 : stateCellRequirement1V1 = {
      id := "state.persistent"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2StatePersistentDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement1V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid1 hversion1 hdigest1 hpredicates1
        simp only [hid1, hversion1, hdigest1, hpredicates1]
  have hrequest2 : stateCellRequirement2V1 = {
      id := "value.checked-arithmetic"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2ValueCheckedArithmeticDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement2V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid2 hversion2 hdigest2 hpredicates2
        simp only [hid2, hversion2, hdigest2, hpredicates2]
  constructor
  · exact ExactMidOffsetInvertAtV1.ofExact
      (exactMidOffsetInvert_qualifiedName
        stateCellSemanticProgramDataV1.qualifiedName) (by decide)
  · rw [stateCellTypesV1, htype0, htype1]
    exact exactAt_array_two_of_exactAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      maxTableElements (by decide) (by decide)
      ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
      ({ id := 1, name := none, shape := .unit } : TypeDeclV1) 1
      (exactAt_typeDecl_uint_noneV1 0 64 1 (by decide))
      (exactAt_typeDecl_unit_noneV1 1 1 (by decide))
  · rw [hconstants]
    exact exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
      maxTableElements 1
  · rw [stateCellLogicalStateV1]
    apply exactAt_array_one_of_exactAtV1 encodeStateDeclV1 decodeStateDeclV1
      maxTableElements (by decide) stateCellState0V1 1
    rw [stateCellState0ValueV1]
    exact exactAt_stateDecl_publicV1 0 0 "count" (by rfl) 1 (by decide)
  · rw [hevents]
    exact exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
      maxTableElements 1
  · rw [herrors]
    exact exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
      maxTableElements 1
  · rw [stateCellCallablesV1]
    exact exactAt_array_three_of_exactAtV1 encodeCallableV1 decodeCallableV1
      maxTableElements (by decide) stateCellCallable0V1 stateCellCallable1V1
      stateCellCallable2V1 1 hcallable0 hcallable1 hcallable2
  · rw [hinvariants]
    exact exactAt_array_emptyV1 encodeInvariantDeclV1 decodeInvariantDeclV1
      maxTableElements 1
  · apply exactAt_programRequirements_of_itemsV1
      stateCellSemanticProgramDataV1.requirements 1 (by decide)
    rw [stateCellRequirementItemsV1, hrequest0, hrequest1, hrequest2]
    exact exactAt_array_three_of_exactAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 maxArrayElements (by decide)
      ({
        id := "failure.atomic-rollback"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2FailureAtomicRollbackDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      ({
        id := "state.persistent"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2StatePersistentDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      ({
        id := "value.checked-arithmetic"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2ValueCheckedArithmeticDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      2
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "failure.atomic-rollback" s2RequirementVersionV1
          { algorithm := .sha256,
            bytes := s2FailureAtomicRollbackDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "state.persistent" s2RequirementVersionV1
          { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "value.checked-arithmetic" s2RequirementVersionV1
          { algorithm := .sha256,
            bytes := s2ValueCheckedArithmeticDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellRootEncodingGatesV1 :
    validateProgramQualifiedNameShapeV1
        stateCellSemanticProgramDataV1.qualifiedName = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.types.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.constants.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.logicalState.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.events.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.errors.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.callables.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.invariants.size = .ok () := by
  rcases stateCellEmptySemanticTablesV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · rfl
  · rw [stateCellTypesV1]
    rfl
  · rw [hconstants]
    rfl
  · rw [stateCellLogicalStateV1]
    rfl
  · rw [hevents]
    rfl
  · rw [herrors]
    rfl
  · rw [stateCellCallablesV1]
    rfl
  · rw [hinvariants]
    rfl

/- Exact canonical wire certificate for the data produced by the sole
    StateCell source normalizer. Every witness is composed from production
    field encoders; no materialized root bytes or alternate encoder is used. -/
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellSemanticEncodingSuccessV1 :
    ∃ bytes,
      encodeSemanticProgramDataV1 stateCellSemanticProgramDataV1 = .ok bytes ∧
        bytes.size ≤ maxCanonicalProgramBytes := by
  rcases stateCellRootEncodingGatesV1 with
    ⟨hnameShape, htypesSize, hconstantsSize, hstateSize, heventsSize,
      herrorsSize, hcallablesSize, hinvariantsSize⟩
  rcases stateCellQualifiedNameEncodingV1 with
    ⟨qualifiedNameB, hqualifiedName, hqualifiedNameSize⟩
  rcases stateCellTypesEncodingV1 with ⟨typesB, htypes, htypesBSize⟩
  rcases stateCellLogicalStateEncodingV1 with ⟨stateB, hstate, hstateBSize⟩
  rcases stateCellEmptySemanticTableEncodingsV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  rcases stateCellCallablesEncodingV1 with
    ⟨callablesB, hcallables, hcallablesBSize⟩
  rcases stateCellRequirementsEncodingV1 with
    ⟨requirementsB, hrequirements, hrequirementsBSize⟩
  let emptyB := encodeU32le 0
  let body := taggedBytesV1 "SemanticProgram.Data"
    #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
      emptyB, requirementsB]
  have hbody :
      encodeTagged "SemanticProgram.Data"
          #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
            emptyB, requirementsB] = .ok body := by
    simpa only [body] using encodeTagged_eq_okV1 "SemanticProgram.Data"
      #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
        emptyB, requirementsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  have hemptySize : emptyB.size = 4 := by
    simp only [emptyB, encodeU32le_size]
  have hbodySize : body.size ≤ 2097152 := by
    simp only [body]
    rw [taggedBytesV1_size, foldl_size_nine]
    have htagSize : "SemanticProgram.Data".toUTF8.size = 20 := by decide
    rw [htagSize, hemptySize]
    omega
  have houtSize :
      ((encodeMagicPrefix semanticProgramMagicV1).append body).size ≤
        maxCanonicalProgramBytes := by
    rw [ByteArray_size_append, encodeMagicPrefix_size]
    have hmagicSize : semanticProgramMagicV1.toUTF8.size + 1 ≤ 64 := by decide
    have hcap : 64 + 2097152 ≤ maxCanonicalProgramBytes := by decide
    omega
  let bytes := (encodeMagicPrefix semanticProgramMagicV1).append body
  refine ⟨bytes, ?_, ?_⟩
  · apply encodeSemanticProgramDataV1_eq_of_fields stateCellSemanticProgramDataV1
      qualifiedNameB typesB emptyB stateB emptyB emptyB callablesB emptyB
      requirementsB body hnameShape htypesSize hconstantsSize hstateSize
      heventsSize herrorsSize hcallablesSize hinvariantsSize
      stateCellSemanticStructureSuccessV1 hqualifiedName htypes hconstants hstate
      hevents herrors hcallables hinvariants hrequirements hbody houtSize
  · simpa only [bytes] using houtSize

/-- Unconditional source-to-carrier certificate for the real exported StateCell
    declaration. It composes the already certified Typed and lowering stages
    with the production wire theorem above. -/
theorem stateCellCanonicalCarrierCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (carrier : SemanticProgramV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        normalizeProgramV1 binding.validated = .ok carrier := by
  rcases stateCellCanonicalSourceBindingV1 with ⟨binding, hbinding⟩
  rcases stateCellSemanticEncodingSuccessV1 with ⟨bytes, hencode, _hsize⟩
  let carrier : SemanticProgramV1 := ⟨bytes⟩
  have hcarrier : encodeCarrierV1 stateCellSemanticProgramDataV1 = .ok carrier := by
    simpa only [carrier] using encodeCarrierV1_eq_ok_of_encode
      stateCellSemanticProgramDataV1 bytes hencode
  refine ⟨binding, carrier, hbinding, ?_⟩
  exact normalizeProgramV1_eq_ok_of_stages binding.validated
    stateCellSemanticProgramDataV1 carrier
    (stateCellTypedCheckSuccessV1 binding)
    (stateCellProgramLoweringSuccessV1 binding) hcarrier

/-- The exact StateCell carrier round-trips through the sole production decoder
    and explicit structure gate. The inverse is assembled from reusable field
    codec certificates rather than evaluating or copying the root bytes. -/
theorem stateCellSemanticValidationSuccessV1 :
    ∃ bytes,
      encodeSemanticProgramDataV1 stateCellSemanticProgramDataV1 = .ok bytes ∧
        validateSemanticProgramV1 ⟨bytes⟩ =
          .ok stateCellSemanticProgramDataV1 := by
  rcases stateCellSemanticEncodingSuccessV1 with ⟨bytes, hencode, _hsize⟩
  have hdecode :
      decodeSemanticProgramDataV1 bytes = .ok stateCellSemanticProgramDataV1 :=
    decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert
      stateCellSemanticProgramDataV1 bytes hencode stateCellRootFieldInvertV1
  exact ⟨bytes, hencode,
    validateSemanticProgramV1_eq_ok_of_encode_decode
      stateCellSemanticProgramDataV1 bytes hencode hdecode⟩

/- Unconditional source-to-`CompiledSemanticV1` identity certificate for the
    real exported StateCell declaration. Source and semantic digests remain
    exact symbolic results of the sole production SHA-256 implementation; no
    concrete digest or alternate compiler is supplied. -/
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCompiledSemanticCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (carrier : SemanticProgramV1)
      (compiled : CompiledSemanticV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        normalizeProgramV1 binding.validated = .ok carrier ∧
        compileValidatedSourceV1 binding.validated = .ok compiled ∧
        validateSemanticProgramV1 carrier =
          .ok stateCellSemanticProgramDataV1 ∧
        CompiledSemanticV1.semanticV1Of compiled = carrier ∧
        CompiledSemanticV1.artifactProgramNameOf compiled = "StateCell" ∧
        CompiledSemanticV1.sourceDigestOf compiled = sha256Bytes
          (("pf.source.v1".toUTF8.push 0).append StateCell.bytes) ∧
        CompiledSemanticV1.semanticDigestOf compiled =
          sha256Bytes carrier.canonicalBytes := by
  rcases stateCellCanonicalSourceBindingV1 with ⟨binding, hbinding⟩
  rcases stateCellSemanticValidationSuccessV1 with
    ⟨bytes, hencode, hvalidate⟩
  let carrier : SemanticProgramV1 := ⟨bytes⟩
  have hcarrier : encodeCarrierV1 stateCellSemanticProgramDataV1 = .ok carrier := by
    simpa only [carrier] using encodeCarrierV1_eq_ok_of_encode
      stateCellSemanticProgramDataV1 bytes hencode
  have hnormalize : normalizeProgramV1 binding.validated = .ok carrier :=
    normalizeProgramV1_eq_ok_of_stages binding.validated
      stateCellSemanticProgramDataV1 carrier
      (stateCellTypedCheckSuccessV1 binding)
      (stateCellProgramLoweringSuccessV1 binding) hcarrier
  have hvalidateCarrier :
      validateSemanticProgramV1 carrier = .ok stateCellSemanticProgramDataV1 := by
    simpa only [carrier] using hvalidate
  have hname :
      (stateCellSemanticProgramDataV1.qualifiedName.components.toArray.back! ==
        ProofForgeV2.Source.NameComponentV1.SourceNameComponentV1.raw
          binding.validated.program.name) = true := by
    rw [binding.program_eq]
    rfl
  let sourceDigest := sha256Bytes
    (("pf.source.v1".toUTF8.push 0).append StateCell.bytes)
  have hsourceHash : sourceHashV1 binding.validated = .ok sourceDigest := by
    simp only [sourceHashV1, binding.canonicalBytes_eq, domainSeparatedSha256,
      show validateProfileIdValue "pf.source.v1" = .ok () by rfl,
      Bind.bind, Pure.pure, Except.bind, Except.pure, sourceDigest]
  let semanticDigest := sha256Bytes bytes
  have hsemanticHash : semanticHashV1 carrier = .ok semanticDigest := by
    simp only [semanticHashV1, hvalidateCarrier, Bind.bind, Pure.pure,
      Except.bind, Except.pure, semanticDigest, carrier]
  rcases compileValidatedSourceV1_eq_ok_of_stages binding.validated carrier
      stateCellSemanticProgramDataV1 sourceDigest semanticDigest hnormalize
      hvalidateCarrier hname hsourceHash hsemanticHash
      (validateDigest_sha256Bytes
        (("pf.source.v1".toUTF8.push 0).append StateCell.bytes))
      (validateDigest_sha256Bytes bytes) with
    ⟨compiled, hcompile, hcompiledCarrier, hcompiledName,
      hcompiledSource, hcompiledSemantic⟩
  refine ⟨binding, carrier, compiled, hbinding, hnormalize, hcompile,
    hvalidateCarrier, hcompiledCarrier, ?_, ?_, ?_⟩
  · exact hcompiledName.trans (by rfl)
  · simpa only [sourceDigest] using hcompiledSource
  · simpa only [semanticDigest, carrier] using hcompiledSemantic

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellReferenceAdmissionOkV1 :
    referenceProgramDataAdmissionOkV1 stateCellSemanticProgramDataV1 = true := by
  decide

/-- StateCell has crossed the source-dependent ingress of production
    preparation. The witnesses come from the same canonical source and sole
    compiler certificate, while Reference admission reuses the production
    data-only check. No partial preparation value or alternate resolver is
    minted here; static selection remains the next exact stage. -/
theorem stateCellProductionPreparationIngressCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (compiled : CompiledSemanticV1)
      (admitted : AdmittedReferenceSliceV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        compileValidatedSourceV1 binding.validated = .ok compiled ∧
        validateSemanticProgramV1
            (CompiledSemanticV1.semanticV1Of compiled) =
          .ok stateCellSemanticProgramDataV1 ∧
        admitReferenceProgramSliceV1
            (CompiledSemanticV1.semanticV1Of compiled) = .ok admitted := by
  rcases stateCellCompiledSemanticCertificateV1 with
    ⟨binding, carrier, compiled, hbinding, _hnormalize, hcompiled,
      hvalidate, hcompiledCarrier, _hname, _hsourceDigest,
      _hsemanticDigest⟩
  have hcompiledValidation :
      validateSemanticProgramV1
          (CompiledSemanticV1.semanticV1Of compiled) =
        .ok stateCellSemanticProgramDataV1 := by
    simpa only [hcompiledCarrier] using hvalidate
  have hadmissionCheck :
      validateReferenceProgramDataAdmissionV1
        stateCellSemanticProgramDataV1 = .ok () :=
    validateReferenceProgramDataAdmissionV1_eq_ok_of_bool
      stateCellSemanticProgramDataV1 stateCellReferenceAdmissionOkV1
  rcases admitReferenceProgramSliceV1_exists_of_checks
      (CompiledSemanticV1.semanticV1Of compiled)
      stateCellSemanticProgramDataV1 hcompiledValidation hadmissionCheck with
    ⟨admitted, hadmitted⟩
  exact ⟨binding, compiled, admitted, hbinding, hcompiled,
    hcompiledValidation, hadmitted⟩

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
