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
# Solana StateCell production subject — kernel projections

Staged out of `SbpfStateCellProductionV1` so CFG block getElem runs in a
fresh Lean process after TypeKey usage-closure. Engineering only.

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

theorem exceptToOptionGetSuccessV1 {ε α : Type}
    (result : Except ε α) (success : result.toOption.isSome = true) :
    result = .ok (result.toOption.get success) := by
  cases result with
  | error _ => simp [Except.toOption] at success
  | ok _ => rfl

theorem exceptUnitSuccessV1 {ε : Type}
    (result : Except ε Unit) (success : result.toOption.isSome = true) :
    result = .ok () := by
  simpa using exceptToOptionGetSuccessV1 result success

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellProgramLoweringTablesSomeV1 :
    (prepareProgramLoweringTablesV1
      StateCell.Source.subjectV1.program).toOption.isSome = true := by
  decide

def stateCellProgramLoweringTablesV1 : ProgramLoweringTablesV1 :=
  (prepareProgramLoweringTablesV1
    StateCell.Source.subjectV1.program).toOption.get
      stateCellProgramLoweringTablesSomeV1

theorem stateCellProgramLoweringTablesSuccessV1 :
    prepareProgramLoweringTablesV1 StateCell.Source.subjectV1.program =
      .ok stateCellProgramLoweringTablesV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramLoweringTablesSomeV1

def stateCellCallableLoweringState0V1 :=
  initialProgramCallableLoweringStateV1 stateCellProgramLoweringTablesV1

def stateCellStateItemV1 :=
  StateCell.Source.subjectV1.program.items[0]'(by decide)

def stateCellInitializeItemV1 :=
  StateCell.Source.subjectV1.program.items[1]'(by decide)

def stateCellIncrementItemV1 :=
  StateCell.Source.subjectV1.program.items[2]'(by decide)

def stateCellGetItemV1 :=
  StateCell.Source.subjectV1.program.items[3]'(by decide)

theorem stateCellProgramItemsV1 :
    StateCell.Source.subjectV1.program.items.toList =
      [stateCellStateItemV1, stateCellInitializeItemV1,
        stateCellIncrementItemV1, stateCellGetItemV1] := by
  decide

theorem stateCellStateItemLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1 stateCellStateItemV1 =
        .ok stateCellCallableLoweringState0V1 := by
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInitializeLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1
      stateCellInitializeItemV1).toOption.isSome = true := by
  decide

def stateCellCallableLoweringState1V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState0V1
    stateCellInitializeItemV1).toOption.get stateCellInitializeLoweringSomeV1

theorem stateCellInitializeLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState0V1 stateCellInitializeItemV1 =
        .ok stateCellCallableLoweringState1V1 :=
  exceptToOptionGetSuccessV1 _ stateCellInitializeLoweringSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellIncrementLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState1V1
      stateCellIncrementItemV1).toOption.isSome = true := by
  decide

def stateCellCallableLoweringState2V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState1V1
    stateCellIncrementItemV1).toOption.get stateCellIncrementLoweringSomeV1

theorem stateCellIncrementLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState1V1 stateCellIncrementItemV1 =
        .ok stateCellCallableLoweringState2V1 :=
  exceptToOptionGetSuccessV1 _ stateCellIncrementLoweringSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellGetLoweringSomeV1 :
    (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState2V1
      stateCellGetItemV1).toOption.isSome = true := by
  decide

def stateCellCallableLoweringState3V1 :
    ProgramCallableLoweringStateV1 :=
  (lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState2V1
    stateCellGetItemV1).toOption.get stateCellGetLoweringSomeV1

theorem stateCellGetLoweringSuccessV1 :
    lowerProgramCallableItemV1 stateCellProgramLoweringTablesV1
      stateCellCallableLoweringState2V1 stateCellGetItemV1 =
        .ok stateCellCallableLoweringState3V1 :=
  exceptToOptionGetSuccessV1 _ stateCellGetLoweringSomeV1

theorem stateCellProgramCallableBodiesSuccessV1 :
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
theorem stateCellProgramFinalizationCoreSomeV1 :
    (prepareProgramLoweringFinalizationCoreV1
      stateCellCallableLoweringState3V1.toBodies).toOption.isSome = true := by
  decide

def stateCellProgramFinalizationCoreV1 :
    ProgramLoweringFinalizationCoreV1 :=
  (prepareProgramLoweringFinalizationCoreV1
    stateCellCallableLoweringState3V1.toBodies).toOption.get
      stateCellProgramFinalizationCoreSomeV1

theorem stateCellProgramFinalizationCoreSuccessV1 :
    prepareProgramLoweringFinalizationCoreV1
      stateCellCallableLoweringState3V1.toBodies =
        .ok stateCellProgramFinalizationCoreV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramFinalizationCoreSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellProgramS2RequirementsSomeV1 :
    (freezeProgramLoweringS2RequirementsV1
      StateCell.Source.subjectV1.program).toOption.isSome = true := by
  decide

def stateCellProgramS2RequirementsV1 : ProgramRequirementsV1 :=
  (freezeProgramLoweringS2RequirementsV1
    StateCell.Source.subjectV1.program).toOption.get
      stateCellProgramS2RequirementsSomeV1

theorem stateCellProgramS2RequirementsSuccessV1 :
    freezeProgramLoweringS2RequirementsV1 StateCell.Source.subjectV1.program =
      .ok stateCellProgramS2RequirementsV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramS2RequirementsSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellProgramRequirementsSomeV1 :
    (mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
      stateCellCallableLoweringState3V1.toBodies).toOption.isSome = true := by
  decide

def stateCellProgramRequirementsV1 : ProgramRequirementsV1 :=
  (mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
    stateCellCallableLoweringState3V1.toBodies).toOption.get
      stateCellProgramRequirementsSomeV1

theorem stateCellProgramRequirementsSuccessV1 :
    mergeProgramLoweringRequirementsV1 stateCellProgramS2RequirementsV1
      stateCellCallableLoweringState3V1.toBodies =
        .ok stateCellProgramRequirementsV1 :=
  exceptToOptionGetSuccessV1 _ stateCellProgramRequirementsSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellQualifiedNameSomeV1 :
    (programIdentityToQualifiedNameV1
      StateCell.Source.subjectV1.programIdentity).toOption.isSome = true := by
  decide

def stateCellQualifiedNameV1 :=
  (programIdentityToQualifiedNameV1
    StateCell.Source.subjectV1.programIdentity).toOption.get
      stateCellQualifiedNameSomeV1

theorem stateCellQualifiedNameSuccessV1 :
    programIdentityToQualifiedNameV1
      StateCell.Source.subjectV1.programIdentity = .ok stateCellQualifiedNameV1 :=
  exceptToOptionGetSuccessV1 _ stateCellQualifiedNameSomeV1

def stateCellSemanticProgramDataV1 : SemanticProgramDataV1 :=
  assembleProgramLoweringDataV1 stateCellQualifiedNameV1
    stateCellProgramLoweringTablesV1
    stateCellCallableLoweringState3V1.toBodies
    stateCellProgramFinalizationCoreV1 stateCellProgramRequirementsV1

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellType0V1 : TypeDeclV1 :=
  stateCellSemanticProgramDataV1.types[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellType1V1 : TypeDeclV1 :=
  stateCellSemanticProgramDataV1.types[1]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellState0V1 : StateDeclV1 :=
  stateCellSemanticProgramDataV1.logicalState[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable0V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[1]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable2V1 : CallableV1 :=
  stateCellSemanticProgramDataV1.callables[2]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellRequirement0V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellRequirement1V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[1]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellRequirement2V1 : RequirementRequestV1 :=
  stateCellSemanticProgramDataV1.requirements.items[2]'(by decide)

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellTypesV1 :
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
theorem stateCellCallablesV1 :
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
theorem stateCellTypeValuesV1 :
    stateCellType0V1 = { id := 0, name := none, shape := .uint 64 } ∧
      stateCellType1V1 = { id := 1, name := none, shape := .unit } := by
  constructor <;> rfl

theorem stateCellTypesExactV1 :
    stateCellSemanticProgramDataV1.types =
      #[{ id := 0, name := none, shape := .uint 64 },
        { id := 1, name := none, shape := .unit }] := by
  rcases stateCellTypeValuesV1 with ⟨h0, h1⟩
  rw [stateCellTypesV1, h0, h1]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellLogicalStateV1 :
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
theorem stateCellState0ValueV1 :
    stateCellState0V1 = {
      id := 0
      name := "count"
      typeId := 0
      visibility := .public_
    } := by
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallable0ResultV1 :
    stateCellCallable0V1.result = { typeId := 1, visibility := .public_ } := by
  rfl

/-- Usage-closure from logical-state UInt64 and initializer Unit result.
    Does not unfold instruction CFGs. -/
theorem stateCellUsageClosureSuccessV1 :
    validateAnonymousTypeUsageClosureV1 stateCellSemanticProgramDataV1 =
      .ok () := by
  apply validateAnonymousTypeUsageClosureV1_uint64_unit_coreMarked_eq_ok
  · exact stateCellTypesExactV1
  · rw [anonymousTypeUsageBitmapV1_allAnonymousLeaf_uint64Unit
      stateCellSemanticProgramDataV1 stateCellTypesExactV1]
    apply foldBoolUInt64CoreRootsV1_of_mem
    · have hs :
          stateCellState0V1 ∈ stateCellSemanticProgramDataV1.logicalState := by
        rw [stateCellLogicalStateV1]
        simp
      have hty : stateCellState0V1.typeId = 0 := by
        rw [stateCellState0ValueV1]
      simpa [hty] using
        collectCoreTypeSlotRootsV1_mem_logicalState
          stateCellSemanticProgramDataV1 stateCellState0V1 hs
    · have hc :
          stateCellCallable0V1 ∈ stateCellSemanticProgramDataV1.callables := by
        rw [stateCellCallablesV1]
        simp
      have hres : stateCellCallable0V1.result.typeId = 1 := by
        rw [stateCellCallable0ResultV1]
      simpa [hres] using
        collectCoreTypeSlotRootsV1_mem_callable_result
          stateCellSemanticProgramDataV1 stateCellCallable0V1 hc

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellEmptySemanticTablesV1 :
    stateCellSemanticProgramDataV1.constants = #[] ∧
      stateCellSemanticProgramDataV1.events = #[] ∧
      stateCellSemanticProgramDataV1.errors = #[] ∧
      stateCellSemanticProgramDataV1.invariants = #[] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellRequirementItemsV1 :
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
theorem stateCellRequirementFieldValuesV1 :
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
theorem stateCellTypeShapeClassifiersV1 :
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
theorem stateCellProgramFinalizationSuccessV1 :
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

def stateCellCertifiedProgramLoweringV1
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
theorem stateCellTypeKeyPhasesSuccessV1 :
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

theorem stateCellConstantNamesSuccessV1 :
    validateConstantNameUniquenessV1
      stateCellSemanticProgramDataV1.constants = .ok () := by
  simp [validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.constants.size ≤ 1 by decide,
    Pure.pure, Except.pure]

theorem stateCellStateNamesSuccessV1 :
    validateLogicalStateNameUniquenessV1
      stateCellSemanticProgramDataV1.logicalState = .ok () := by
  simp [validateLogicalStateNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.logicalState.size ≤ 1 by decide,
    Pure.pure, Except.pure]

theorem stateCellEventNamesSuccessV1 :
    validateEventNameUniquenessV1 stateCellSemanticProgramDataV1.events =
      .ok () := by
  simp [validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.events.size ≤ 1 by decide,
    Pure.pure, Except.pure]

theorem stateCellErrorNamesSuccessV1 :
    validateErrorNameUniquenessV1 stateCellSemanticProgramDataV1.errors =
      .ok () := by
  simp [validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1,
    show stateCellSemanticProgramDataV1.errors.size ≤ 1 by decide,
    Pure.pure, Except.pure]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableParameterNamesSuccessV1 :
    validateCallableParameterNameUniquenessV1
      stateCellSemanticProgramDataV1.callables = .ok () := by
  have h0 : stateCellCallable0V1.params.size ≤ 1 := by decide
  have h1 : stateCellCallable1V1.params.size ≤ 1 := by decide
  have h2 : stateCellCallable2V1.params.size ≤ 1 := by decide
  simp [validateCallableParameterNameUniquenessV1, stateCellCallablesV1,
    h0, h1, h2, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableSignaturePhasesSuccessV1 :
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
theorem stateCellCallable0ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable0V1).toOption.isSome = true := by
  decide

def stateCellCallable0ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable0V1).toOption.get
    stateCellCallable0ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallable1ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable1V1).toOption.isSome = true := by
  decide

def stateCellCallable1ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable1V1).toOption.get
    stateCellCallable1ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallable2ReachabilitySomeV1 :
    (validateCallableCfgShapeReachability
      stateCellCallable2V1).toOption.isSome = true := by
  decide

def stateCellCallable2ReachabilityV1 : Array Bool :=
  (validateCallableCfgShapeReachability stateCellCallable2V1).toOption.get
    stateCellCallable2ReachabilitySomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableReachabilityValuesV1 :
    stateCellCallable0ReachabilityV1 = #[true] ∧
      stateCellCallable1ReachabilityV1 = #[true] ∧
      stateCellCallable2ReachabilityV1 = #[true] := by
  decide

def stateCellCallable0DefSitesV1 :=
  collectValueDefSites stateCellCallable0V1

def stateCellCallable1DefSitesV1 :=
  collectValueDefSites stateCellCallable1V1

def stateCellCallable2DefSitesV1 :=
  collectValueDefSites stateCellCallable2V1

end ProofForgeV2.Targets.Solana
