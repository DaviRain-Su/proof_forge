import ProofForgeV2.Semantic.FieldComparisonSubjectV1

/-!
  ProofForgeV2.Semantic.StatefulEqualitySubjectV1 — parameterized production
  subject data, codec/structure certificates, and Reference admission check for
  a unary state-changing entry that restores a two-field equality invariant.

  This module fixes only the lowering shape. Qualified name and all source
  declaration names remain parameters. Execution stays exclusively in
  `ReferenceMachineV1`; this module defines no State, Effect, step, evaluator,
  alternate validator, or pinned whole-program bytes.
-/

namespace ProofForgeV2.Semantic.StatefulEqualitySubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

/-- Reuse the exact production anonymous UInt64/Bool type table. -/
def typesV1 : Array TypeDeclV1 :=
  ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1

/-- State mutation requires the sole production persistent-state request. The
    equality operator itself carries no Bool literal payload requirement. -/
def requirementsV1 : ProgramRequirementsV1 := {
  items := #[
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.persistentStateRequirementV1
  ]
}

def callablesV1
    (entryName parameterName invariantName : String) : Array CallableV1 := #[
  storeParameterTwoReturnCallableV1 0 (some entryName) parameterName
    0 0 1 .public_,
  twoStateCompareInvariantCallableV1 1 (some invariantName)
    0 1 0 1 .eq .public_ (some 5)
]

/-- Contract-name-parametric semantic data for the state-changing equality
    family. -/
def subjectDataV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    SemanticProgramDataV1 := {
  qualifiedName
  types := typesV1
  constants := #[]
  logicalState := #[
    { id := 0, name := state0Name, typeId := 0, visibility := .public_ },
    { id := 1, name := state1Name, typeId := 0, visibility := .public_ }
  ]
  events := #[]
  errors := #[]
  callables := callablesV1 entryName parameterName invariantName
  invariants := #[{ id := 0, name := invariantName, callableId := 1 }]
  requirements := requirementsV1
}

theorem exactAtRoot_typesV1 :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1)
      typesV1 1 := by
  simpa [typesV1, ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.exactAtRoot_typesV1

theorem exactAtRoot_statesV1
    (state0Name state1Name : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeStateDeclV1)
      (decodeArray maxTableElements decodeStateDeclV1)
      #[{ id := 0, name := state0Name, typeId := 0, visibility := .public_ },
        { id := 1, name := state1Name, typeId := 0,
          visibility := .public_ }] 1 :=
  exactAt_array_two_of_exactAtV1 encodeStateDeclV1 decodeStateDeclV1
    maxTableElements (by decide) (by decide)
    (StateDeclV1.mk 0 state0Name 0 .public_)
    (StateDeclV1.mk 1 state1Name 0 .public_) 1
    (exactAt_stateDecl_publicV1 0 0 state0Name hstate0Name 1 (by decide))
    (exactAt_stateDecl_publicV1 1 0 state1Name hstate1Name 1 (by decide))

theorem exactAtRoot_invariantsV1 (invariantName : String) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
      #[{ id := 0, name := invariantName, callableId := 1 }] 1 :=
  exactAt_array_one_of_exactAtV1 encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide)
    ({ id := 0, name := invariantName, callableId := 1 } : InvariantDeclV1) 1
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))

theorem exactAtRoot_requirementsV1 :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 requirementsV1 1 := by
  apply exactAt_programRequirements_of_itemsV1 requirementsV1 1 (by decide)
  simpa [requirementsV1] using
    exactAt_array_one_of_exactAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 maxArrayElements (by decide)
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.persistentStateRequirementV1
      2
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          s2StatePersistentIdV1 s2RequirementVersionV1
          { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion)
        (by decide))

/-- Whole-program production-codec inversion for the parameterized family.
    This certificate alone does not imply structure or validation success. -/
theorem rootFieldInvertV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hparameterName : validateIdentifierComponent parameterName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    RootFieldInvertV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) := by
  refine {
    qualifiedName := ?_
    types := ?_
    constants := ?_
    logicalState := ?_
    events := ?_
    errors := ?_
    callables := ?_
    invariants := ?_
    requirements := ?_
  }
  · simpa [subjectDataV1] using
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_qualifiedName qualifiedName)
        (by decide : 1 < maxNesting))
  · simpa [subjectDataV1] using exactAtRoot_typesV1
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      exactAtRoot_statesV1 state0Name state1Name hstate0Name hstate1Name
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1, callablesV1] using
      exactAt_storeParameterEqualityCallableTableV1 0 1 entryName
        parameterName invariantName 0 1 0 1 hentryName hparameterName
        hinvariantName
  · simpa [subjectDataV1] using exactAtRoot_invariantsV1 invariantName
  · simpa [subjectDataV1] using exactAtRoot_requirementsV1

/-! ### Production structure phases -/

/-- Exact hypotheses needed by the name-sensitive production phases. -/
structure StructureLegalV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    Prop where
  hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
  hstate0Name : validateIdentifierComponent state0Name = .ok ()
  hstate1Name : validateIdentifierComponent state1Name = .ok ()
  hentryName : validateIdentifierComponent entryName = .ok ()
  hparameterName : validateIdentifierComponent parameterName = .ok ()
  hinvariantName : validateIdentifierComponent invariantName = .ok ()
  hstate01 : state0Name ≠ state1Name
  hentryInvariant : entryName ≠ invariantName

/-- Root shape, dense IDs, and shallow production references. -/
theorem structurePreludeV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()) :
    validateSemanticProgramStructurePreludeV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  simp [subjectDataV1, typesV1,
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1,
    callablesV1, storeParameterTwoReturnCallableV1,
    storeParameterTwoReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateSemanticProgramStructurePreludeV1,
    checkTableIdsV1, checkTypeShapeRefs, checkTypeIdInRange,
    checkCallableIdInRange, checkIdEqualsIndex, hnameShape,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typesStructureV1 : validateTypesStructureV1 typesV1 = .ok () := by
  simpa [typesV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesStructureV1

theorem typeKeyPhasesV1 : validateTypeKeyPhasesV1 typesV1 = .ok () := by
  simpa [typesV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.typeKeyPhasesV1

theorem namedTypeNamesV1 :
    validateNamedTypeNameUniquenessV1 typesV1 = .ok () := by
  simpa [typesV1] using
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.namedTypeNamesV1

theorem constantsValueBytesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateConstantsValueBytesV1 typesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName).constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [subjectDataV1, validateConstantsValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- This family has no literal payloads, so callable valueBytes validation
    preserves the complete production budget. -/
theorem callablesValueBytesV1
    (entryName parameterName invariantName : String) :
    validateCallablesValueBytesV1 typesV1
      (callablesV1 entryName parameterName invariantName)
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [typesV1, ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1,
    callablesV1, storeParameterTwoReturnCallableV1,
    storeParameterTwoReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateCallablesValueBytesV1,
    validateOpValueBytesV1, validateTerminatorValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem constantNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateConstantNameUniquenessV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName).constants = .ok () := by
  simp [subjectDataV1, validateConstantNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem logicalStateNamesV1
    (state0Name state1Name : String)
    (hstate01 : state0Name ≠ state1Name) :
    validateLogicalStateNameUniquenessV1 #[
      { id := 0, name := state0Name, typeId := 0, visibility := .public_ },
      { id := 1, name := state1Name, typeId := 0,
        visibility := .public_ }
    ] = .ok () := by
  have h01 : (state0Name == state1Name) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hstate01)
  simp [validateLogicalStateNameUniquenessV1,
    checkUniqueDeclarationNamesV1, h01,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem callableSignaturesV1
    (entryName parameterName invariantName : String)
    (hentryInvariant : entryName ≠ invariantName) :
    validateCallableSignaturePhasesV1 typesV1
      (callablesV1 entryName parameterName invariantName) = .ok () := by
  have hnames : (entryName == invariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hentryInvariant)
  have hEntryInit : ((.entry : CallableKindV1) == .initializer) = false := by
    decide
  have hInvInit : ((.invariant : CallableKindV1) == .initializer) = false := by
    decide
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false := by
    decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by
    decide
  have hPublic : ((.public_ : VisibilityV1) == .public_) = true := by
    decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [typesV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1,
      callablesV1, storeParameterTwoReturnCallableV1,
      storeParameterTwoReturnBlockV1, twoStateCompareInvariantCallableV1,
      twoStateCompareInvariantBlockV1, validateCallableKindNamePresenceV1,
      validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1,
      validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
      validateInitializerResultShapeV1, validateInvariantResultShapeV1,
      validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
      validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, hnames, hEntryInit, hInvInit,
      hEntryInv, hInvInv, hPublic,
      Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem invariantDeclarationJoinV1
    (entryName parameterName invariantName : String) :
    validateInvariantDeclarationJoinV1
      (callablesV1 entryName parameterName invariantName)
      #[{ id := 0, name := invariantName, callableId := 1 }] = .ok () := by
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false := by
    decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by
    decide
  simp [callablesV1, storeParameterTwoReturnCallableV1,
    storeParameterTwoReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateInvariantDeclarationJoinV1,
    hEntryInv, hInvInv, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem declarationIdentifierNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hparameterName : validateIdentifierComponent parameterName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    validateDeclarationIdentifierNamesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  have hstate0 := validateIdentifierNameV1_eq_ok_of_common state0Name hstate0Name
  have hstate1 := validateIdentifierNameV1_eq_ok_of_common state1Name hstate1Name
  have hentry := validateIdentifierNameV1_eq_ok_of_common entryName hentryName
  have hparameter :=
    validateIdentifierNameV1_eq_ok_of_common parameterName hparameterName
  have hinvariant :=
    validateIdentifierNameV1_eq_ok_of_common invariantName hinvariantName
  simp [subjectDataV1, typesV1,
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.typesV1,
    callablesV1, storeParameterTwoReturnCallableV1,
    storeParameterTwoReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateDeclarationIdentifierNamesV1,
    validateTypeShapeIdentifierNamesV1, hstate0, hstate1, hentry, hparameter,
    hinvariant, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem programRequirementsStructureV1 :
    validateProgramRequirementsStructure requirementsV1 = .ok () := by
  simpa [requirementsV1,
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.persistentStateRequirementV1,
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.requirementV1,
    s2StatePersistentIdV1] using
    validateProgramRequirementsStructure_singleton_state_persistent_eq_ok
      s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }

theorem emptyOperationRequirementsV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateContextReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name entryName
          parameterName invariantName) = .ok () ∧
      validateCommitRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name entryName
          parameterName invariantName) = .ok () ∧
      validateEnvReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name entryName
          parameterName invariantName) = .ok () := by
  exact ⟨rfl, rfl, rfl⟩

/-! ### Production generic CFG, closure, and fuel phases -/

private theorem entryCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateCallableCfgShape
      (storeParameterTwoReturnCallableV1 0 (some entryName) parameterName
        0 0 1 .public_)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  let callable := storeParameterTwoReturnCallableV1 0 (some entryName)
    parameterName 0 0 1 .public_
  let data := subjectDataV1 qualifiedName state0Name state1Name entryName
    parameterName invariantName
  refine validateCallableCfgShape_eq_ok_of_phases callable typesV1.size
    typesV1 data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      callable #[true] #[(0, 0), (1, 0)]
    · rfl
    · rfl
    · simp [callable, checkValueIdUsesExist,
        storeParameterTwoReturnCallableV1, storeParameterTwoReturnBlockV1,
        opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem invariantCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateCallableCfgShape
      (twoStateCompareInvariantCallableV1 1 (some invariantName)
        0 1 0 1 .eq .public_ (some 5))
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  let callable := twoStateCompareInvariantCallableV1 1 (some invariantName)
    0 1 0 1 .eq .public_ (some 5)
  let data := subjectDataV1 qualifiedName state0Name state1Name entryName
    parameterName invariantName
  refine validateCallableCfgShape_eq_ok_of_phases callable typesV1.size
    typesV1 data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      callable #[true] #[(0, 0), (1, 0), (2, 0)]
    · rfl
    · rfl
    · simp [callable, checkValueIdUsesExist,
        twoStateCompareInvariantCallableV1,
        twoStateCompareInvariantBlockV1, opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

theorem genericCfgPhasesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateGenericCfgPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  apply validateGenericCfgPhasesV1_two_eq_ok
    (subjectDataV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName)
    (storeParameterTwoReturnCallableV1 0 (some entryName) parameterName
      0 0 1 .public_)
    (twoStateCompareInvariantCallableV1 1 (some invariantName)
      0 1 0 1 .eq .public_ (some 5))
  · rfl
  · exact entryCfgV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · exact invariantCfgV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · rfl

def closureMembersV1 : Array Bool := #[false, true]

theorem invariantClosurePhasesV1
    (entryName parameterName invariantName : String) :
    validateInvariantClosurePhasesV1
      (callablesV1 entryName parameterName invariantName) =
        .ok closureMembersV1 := by
  simp [validateInvariantClosurePhasesV1,
    validateInvariantClosureDagPhasesV1,
    validateInvariantClosureMembershipPhasesV1,
    invariantClosureMembershipResultV1, callablesV1, closureMembersV1,
    storeParameterTwoReturnCallableV1, storeParameterTwoReturnBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1]
  rfl

theorem invariantFuelPhasesV1
    (entryName parameterName invariantName : String) :
    validateInvariantFuelPhasesV1
      (callablesV1 entryName parameterName invariantName)
      closureMembersV1 = .ok () := by
  rfl

theorem cfgInvariantPhasesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    validateCfgInvariantPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok
    (subjectDataV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName) closureMembersV1
  · exact genericCfgPhasesV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · simpa [subjectDataV1] using
      invariantClosurePhasesV1 entryName parameterName invariantName
  · simpa [subjectDataV1] using
      invariantFuelPhasesV1 entryName parameterName invariantName

/-! ### Full production structure composition -/

/-- Every production structure phase accepts the parameterized state-changing
    equality family under exact source-name legality and namespace
    distinctness. -/
theorem structureV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (legal : StructureLegalV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName) :
    validateSemanticProgramStructureV1
      (subjectDataV1 qualifiedName state0Name state1Name entryName
        parameterName invariantName) = .ok () := by
  let data := subjectDataV1 qualifiedName state0Name state1Name entryName
    parameterName invariantName
  apply validateSemanticProgramStructureV1_eq_ok_of_phases data
    maxCanonicalProgramBytes maxCanonicalProgramBytes
  · exact structurePreludeV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName legal.hnameShape
  · simpa [data, subjectDataV1] using typesStructureV1
  · simpa [data, subjectDataV1] using typeKeyPhasesV1
  · simpa [data, subjectDataV1] using namedTypeNamesV1
  · exact constantsValueBytesV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · simpa [data, subjectDataV1] using
      callablesValueBytesV1 entryName parameterName invariantName
  · exact constantNamesV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · simpa [data, subjectDataV1] using
      logicalStateNamesV1 state0Name state1Name legal.hstate01
  · simp [data, subjectDataV1, validateEventNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateErrorNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateInterfaceFieldNameUniquenessV1,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · simpa [data, subjectDataV1] using
      callableSignaturesV1 entryName parameterName invariantName
        legal.hentryInvariant
  · simpa [data, subjectDataV1] using
      invariantDeclarationJoinV1 entryName parameterName invariantName
  · exact declarationIdentifierNamesV1 qualifiedName state0Name state1Name
      entryName parameterName invariantName legal.hstate0Name legal.hstate1Name
      legal.hentryName legal.hparameterName legal.hinvariantName
  · exact cfgInvariantPhasesV1 qualifiedName state0Name state1Name entryName
      parameterName invariantName
  · simpa [data, subjectDataV1] using programRequirementsStructureV1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      entryName parameterName invariantName).1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      entryName parameterName invariantName).2.1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      entryName parameterName invariantName).2.2

/-- The parameterized family also passes the sole production Reference resource
    admission scan. This proves a check result; the private admitted carrier is
    still minted only by `admitReferenceProgramSliceV1`. -/
theorem referenceAdmissionV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String) :
    ProofForgeV2.Semantic.ReferenceV1.validateReferenceProgramDataAdmissionV1
        (subjectDataV1 qualifiedName state0Name state1Name entryName
          parameterName invariantName) = .ok () := by
  rfl

end ProofForgeV2.Semantic.StatefulEqualitySubjectV1
