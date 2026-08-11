import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1

/-!
  ProofForgeV2.Semantic.FieldComparisonSubjectV1 — parameterized production
  subject-data and root-codec certificate for the first field-comparison
  authoring family.

  This module fixes only the lowering shape:

    * anonymous UInt64 / Bool types;
    * three public UInt64 state rows;
    * literal-true view and invariant;
    * UInt64 field equality and inequality invariants;
    * `state.persistent` / `value.bool` production requirements.

  Qualified name and every source declaration name remain parameters. There
  is no second codec, validator, evaluator, State/Effect model, or pinned
  whole-program byte string.
-/

namespace ProofForgeV2.Semantic.FieldComparisonSubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

/-- Requirement row helper using the production S2 version and digest spine. -/
def requirementV1 (id : String) (digestBytes : ByteArray) : RequirementRequestV1 := {
  id
  version := s2RequirementVersionV1
  digest := { algorithm := .sha256, bytes := digestBytes }
  predicates := #[]
}

def persistentStateRequirementV1 : RequirementRequestV1 :=
  requirementV1 s2StatePersistentIdV1 s2StatePersistentDigestBytesV1

def boolRequirementV1 : RequirementRequestV1 :=
  requirementV1 s2ValueBoolIdV1 s2ValueBoolDigestBytesV1

def requirementsV1 : ProgramRequirementsV1 := {
  items := #[persistentStateRequirementV1, boolRequirementV1]
}

/-- Anonymous production types used by field-comparison lowering. -/
def typesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .uint 64 },
  { id := 1, name := none, shape := .bool }
]

/-- Exact source-order callable table shared by codec and structure phases. -/
def callablesV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    Array CallableV1 := #[
  literalReturnCallableV1 0 .view (some viewName) 1 (encodeU8 1)
    .public_ none,
  literalReturnCallableV1 1 .invariant (some literalInvariantName) 1
    (encodeU8 1) .public_ (some 3),
  twoStateCompareInvariantCallableV1 2 (some eqInvariantName)
    0 1 1 2 .eq .public_ (some 5),
  twoStateCompareInvariantCallableV1 3 (some neInvariantName)
    0 1 1 2 .ne .public_ (some 5)
]

/-- Contract-name-parametric semantic data for the field-comparison family. -/
def subjectDataV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    SemanticProgramDataV1 := {
  qualifiedName
  types := typesV1
  constants := #[]
  logicalState := #[
    { id := 0, name := state0Name, typeId := 0, visibility := .public_ },
    { id := 1, name := state1Name, typeId := 0, visibility := .public_ },
    { id := 2, name := state2Name, typeId := 0, visibility := .public_ }
  ]
  events := #[]
  errors := #[]
  callables := callablesV1 viewName literalInvariantName eqInvariantName
    neInvariantName
  invariants := #[
    { id := 0, name := literalInvariantName, callableId := 1 },
    { id := 1, name := eqInvariantName, callableId := 2 },
    { id := 2, name := neInvariantName, callableId := 3 }
  ]
  requirements := requirementsV1
}

theorem exactAtRoot_typesV1 :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1)
      #[{ id := 0, name := none, shape := .uint 64 },
        { id := 1, name := none, shape := .bool }] 1 :=
  exactAt_array_two_of_exactAtV1 encodeTypeDeclV1 decodeTypeDeclV1
    maxTableElements (by decide) (by decide)
    ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
    ({ id := 1, name := none, shape := .bool } : TypeDeclV1) 1
    (exactAt_typeDecl_uint_noneV1 0 64 1 (by decide))
    (exactAt_typeDecl_bool_noneV1 1 1 (by decide))

theorem exactAtRoot_statesV1
    (state0Name state1Name state2Name : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ()) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeStateDeclV1)
      (decodeArray maxTableElements decodeStateDeclV1)
      #[{ id := 0, name := state0Name, typeId := 0, visibility := .public_ },
        { id := 1, name := state1Name, typeId := 0, visibility := .public_ },
        { id := 2, name := state2Name, typeId := 0, visibility := .public_ }] 1 :=
  exactAt_array_three_of_exactAtV1 encodeStateDeclV1 decodeStateDeclV1
    maxTableElements (by decide)
    (StateDeclV1.mk 0 state0Name 0 .public_)
    (StateDeclV1.mk 1 state1Name 0 .public_)
    (StateDeclV1.mk 2 state2Name 0 .public_) 1
    (exactAt_stateDecl_publicV1 0 0 state0Name hstate0Name 1 (by decide))
    (exactAt_stateDecl_publicV1 1 0 state1Name hstate1Name 1 (by decide))
    (exactAt_stateDecl_publicV1 2 0 state2Name hstate2Name 1 (by decide))

theorem exactAtRoot_invariantsV1
    (literalInvariantName eqInvariantName neInvariantName : String) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1)
      #[{ id := 0, name := literalInvariantName, callableId := 1 },
        { id := 1, name := eqInvariantName, callableId := 2 },
        { id := 2, name := neInvariantName, callableId := 3 }] 1 :=
  exactAt_array_three_of_exactAtV1 encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide)
    ({ id := 0, name := literalInvariantName, callableId := 1 } : InvariantDeclV1)
    ({ id := 1, name := eqInvariantName, callableId := 2 } : InvariantDeclV1)
    ({ id := 2, name := neInvariantName, callableId := 3 } : InvariantDeclV1) 1
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))

theorem exactAtRoot_requirementsV1 :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 requirementsV1 1 := by
  apply exactAt_programRequirements_of_itemsV1 requirementsV1 1 (by decide)
  simpa [requirementsV1] using
    exactAt_array_two_of_exactAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 maxArrayElements (by decide) (by decide)
      persistentStateRequirementV1 boolRequirementV1 2
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          s2StatePersistentIdV1 s2RequirementVersionV1
          { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion)
        (by decide))
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          s2ValueBoolIdV1 s2RequirementVersionV1
          { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion)
        (by decide))

/-- Whole-program production-codec inversion for the parameterized family.
    This certificate does not imply structure or validation success. -/
theorem rootFieldInvertV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ()) :
    RootFieldInvertV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) := by
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
  · simpa [subjectDataV1, typesV1] using exactAtRoot_typesV1
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      exactAtRoot_statesV1 state0Name state1Name state2Name
        hstate0Name hstate1Name hstate2Name
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1] using
      (exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
        maxTableElements 1)
  · simpa [subjectDataV1, callablesV1] using
      exactAt_literalFieldComparisonCallableTableV1 0 1 2 3 viewName
        literalInvariantName eqInvariantName neInvariantName 0 1 1 2
        (encodeU8 1) (encodeU8 1) hviewName hliteralInvariantName
        heqInvariantName hneInvariantName
  · simpa [subjectDataV1] using
      exactAtRoot_invariantsV1 literalInvariantName eqInvariantName neInvariantName
  · simpa [subjectDataV1] using exactAtRoot_requirementsV1

/-! ### Production structure foundation -/

private def uint64TypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private def boolTypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private theorem encodeTypeShape_uint64V1 :
    encodeTypeShapeV1 (.uint 64) = .ok uint64TypeShapeBytesV1 := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok uint64TypeShapeBytesV1
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem encodeTypeShape_boolV1 :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytesV1 := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytesV1
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem compare_uint64_boolV1 :
    compareByteArrayLex uint64TypeShapeBytesV1 boolTypeShapeBytesV1 = .gt := by
  rw [compareByteArrayLex]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 2 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 3 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 4 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 5 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 6 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 7 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 8 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_gt
  · decide
  · decide

/-- Root shape, dense IDs, and shallow production references for the family. -/
theorem structurePreludeV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()) :
    validateSemanticProgramStructurePreludeV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  simp [subjectDataV1, typesV1, callablesV1, literalReturnCallableV1,
    literalReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateSemanticProgramStructurePreludeV1,
    checkTableIdsV1, checkTypeShapeRefs, checkTypeIdInRange,
    checkCallableIdInRange, checkIdEqualsIndex, hnameShape,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Type-shape legality for the fixed anonymous UInt64/Bool table. -/
theorem typesStructureV1 : validateTypesStructureV1 typesV1 = .ok () := by
  simp [typesV1, validateTypesStructureV1, validateTypeDeclShapeV1,
    validateTypeDeclNamedRuleV1, legalIntegerWidthV1_64,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Full production TypeKey phase for the fixed anonymous UInt64/Bool table. -/
theorem typeKeyPhasesV1 : validateTypeKeyPhasesV1 typesV1 = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · simp [typesV1, validateNamedPrefixRankV1,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · simp [typesV1, validatePrimitiveAnonymousTypeKeyUniquenessV1,
      collectPrimitiveAnonymousTypeKeysV1,
      encodeTypeShape_uint64V1, encodeTypeShape_boolV1, compare_uint64_boolV1,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · simp [typesV1, validateRecursiveAnonymousTypeKeyUniquenessV1,
      Pure.pure, Except.pure]
  · simp [typesV1, validateNamedBodyOptionCycleLegalityV1,
      Pure.pure, Except.pure]

/-- There are no named TypeDecl rows in this lowering family. -/
theorem namedTypeNamesV1 :
    validateNamedTypeNameUniquenessV1 typesV1 = .ok () := by
  simp [typesV1, validateNamedTypeNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

/-! ### Production values, names, signatures, and requirements -/

/-- Exact hypotheses needed by the remaining name-sensitive structure phases.
    Every field is a production validator fact or source-namespace
    distinctness fact that ProgramElaboration can construct. -/
structure StructureLegalV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    Prop where
  hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
  hstate0Name : validateIdentifierComponent state0Name = .ok ()
  hstate1Name : validateIdentifierComponent state1Name = .ok ()
  hstate2Name : validateIdentifierComponent state2Name = .ok ()
  hviewName : validateIdentifierComponent viewName = .ok ()
  hliteralInvariantName :
    validateIdentifierComponent literalInvariantName = .ok ()
  heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ()
  hneInvariantName : validateIdentifierComponent neInvariantName = .ok ()
  hstate01 : state0Name ≠ state1Name
  hstate02 : state0Name ≠ state2Name
  hstate12 : state1Name ≠ state2Name
  hviewLiteral : viewName ≠ literalInvariantName
  hviewEq : viewName ≠ eqInvariantName
  hviewNe : viewName ≠ neInvariantName
  hliteralEq : literalInvariantName ≠ eqInvariantName
  hliteralNe : literalInvariantName ≠ neInvariantName
  heqNe : eqInvariantName ≠ neInvariantName

theorem constantsValueBytesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateConstantsValueBytesV1 typesV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [subjectDataV1, validateConstantsValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- The two Bool literals consume two work units each; state loads and Eq/Ne
    consume no valueBytes budget. -/
theorem callablesValueBytesV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateCallablesValueBytesV1 typesV1
      (callablesV1 viewName literalInvariantName eqInvariantName neInvariantName)
      maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 4) := by
  have htrue :
      validateOpValueBytesV1 typesV1 (.literal 1 (encodeU8 1))
        maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 2) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok typesV1 1
      ({ id := 1, name := none, shape := .bool } : TypeDeclV1) 1
    · rfl
    · rfl
    · exact Or.inr rfl
    · decide
  have htrue2 :
      validateOpValueBytesV1 typesV1 (.literal 1 (encodeU8 1))
        (maxCanonicalProgramBytes - 2) =
        .ok (maxCanonicalProgramBytes - 4) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok typesV1 1
      ({ id := 1, name := none, shape := .bool } : TypeDeclV1) 1
    · rfl
    · rfl
    · exact Or.inr rfl
    · decide
  have hterm (value : Option ValueIdV1) (budget : Nat) :
      validateTerminatorValueBytesV1 typesV1 (.return_ value) budget =
        .ok budget := rfl
  have hload (stateId : StateIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.stateLoad stateId) budget =
        .ok budget := rfl
  have hbinary (op : BinaryOpV1) (left right : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.binary op left right) budget =
        .ok budget := rfl
  simp [validateCallablesValueBytesV1, callablesV1, literalReturnCallableV1,
    literalReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, htrue, htrue2, hterm, hload, hbinary,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem constantNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateConstantNameUniquenessV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).constants =
      .ok () := by
  simp [subjectDataV1, validateConstantNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem logicalStateNamesV1
    (state0Name state1Name state2Name : String)
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name) :
    validateLogicalStateNameUniquenessV1 #[
      { id := 0, name := state0Name, typeId := 0, visibility := .public_ },
      { id := 1, name := state1Name, typeId := 0, visibility := .public_ },
      { id := 2, name := state2Name, typeId := 0, visibility := .public_ }
    ] = .ok () := by
  have h01 : (state0Name == state1Name) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hstate01)
  have h02 : (state0Name == state2Name) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hstate02)
  have h12 : (state1Name == state2Name) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hstate12)
  simp [validateLogicalStateNameUniquenessV1, checkUniqueDeclarationNamesV1,
    h01, h02, h12, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem callableSignaturesV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName) :
    validateCallableSignaturePhasesV1 typesV1
      (callablesV1 viewName literalInvariantName eqInvariantName
        neInvariantName) = .ok () := by
  have hVL : (viewName == literalInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hviewLiteral)
  have hVE : (viewName == eqInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hviewEq)
  have hVN : (viewName == neInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hviewNe)
  have hLE : (literalInvariantName == eqInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hliteralEq)
  have hLN : (literalInvariantName == neInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hliteralNe)
  have hEN : (eqInvariantName == neInvariantName) = false := by
    exact Bool.eq_false_iff.mpr (by simpa [BEq.beq] using heqNe)
  have hViewInit : ((.view : CallableKindV1) == .initializer) = false := by
    decide
  have hInvInit : ((.invariant : CallableKindV1) == .initializer) = false := by
    decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false := by
    decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by
    decide
  have hPublic : ((.public_ : VisibilityV1) == .public_) = true := by
    decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [typesV1, callablesV1, literalReturnCallableV1,
      literalReturnBlockV1, twoStateCompareInvariantCallableV1,
      twoStateCompareInvariantBlockV1, validateCallableKindNamePresenceV1,
      validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1,
      validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
      validateInitializerResultShapeV1, validateInvariantResultShapeV1,
      validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
      validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, hVL, hVE, hVN, hLE, hLN, hEN,
      hViewInit, hInvInit, hViewInv, hInvInv, hPublic,
      Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem invariantDeclarationJoinV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateInvariantDeclarationJoinV1
      (callablesV1 viewName literalInvariantName eqInvariantName neInvariantName)
      #[{ id := 0, name := literalInvariantName, callableId := 1 },
        { id := 1, name := eqInvariantName, callableId := 2 },
        { id := 2, name := neInvariantName, callableId := 3 }] = .ok () := by
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false := by
    decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by
    decide
  simp [callablesV1, literalReturnCallableV1, literalReturnBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
    validateInvariantDeclarationJoinV1, hViewInv, hInvInv,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem declarationIdentifierNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ()) :
    validateDeclarationIdentifierNamesV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  have hstate0 := validateIdentifierNameV1_eq_ok_of_common state0Name hstate0Name
  have hstate1 := validateIdentifierNameV1_eq_ok_of_common state1Name hstate1Name
  have hstate2 := validateIdentifierNameV1_eq_ok_of_common state2Name hstate2Name
  have hview := validateIdentifierNameV1_eq_ok_of_common viewName hviewName
  have hliteral := validateIdentifierNameV1_eq_ok_of_common
    literalInvariantName hliteralInvariantName
  have heq := validateIdentifierNameV1_eq_ok_of_common
    eqInvariantName heqInvariantName
  have hne := validateIdentifierNameV1_eq_ok_of_common
    neInvariantName hneInvariantName
  simp [subjectDataV1, typesV1, callablesV1, literalReturnCallableV1,
    literalReturnBlockV1, twoStateCompareInvariantCallableV1,
    twoStateCompareInvariantBlockV1, validateDeclarationIdentifierNamesV1,
    validateTypeShapeIdentifierNamesV1, hstate0, hstate1, hstate2, hview,
    hliteral, heq, hne, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem programRequirementsStructureV1 :
    validateProgramRequirementsStructure requirementsV1 = .ok () := by
  simpa [requirementsV1, persistentStateRequirementV1, boolRequirementV1,
    requirementV1, s2StatePersistentIdV1, s2ValueBoolIdV1] using
    validateProgramRequirementsStructure_state_bool_eq_ok
      s2RequirementVersionV1 s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
      { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 }

theorem emptyOperationRequirementsV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateContextReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
          literalInvariantName eqInvariantName neInvariantName) = .ok () ∧
      validateCommitRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
          literalInvariantName eqInvariantName neInvariantName) = .ok () ∧
      validateEnvReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
          literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  exact ⟨rfl, rfl, rfl⟩

/-! ### Production generic CFG/SSA/typing phase -/

private theorem literalCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (callableId : CallableIdV1) (kind : CallableKindV1)
    (callableName : String) (invariantSteps : Option UInt64) :
    validateCallableCfgShape
      (literalReturnCallableV1 callableId kind (some callableName) 1
        (encodeU8 1) .public_ invariantSteps)
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).types.size
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).types
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  let data := subjectDataV1 qualifiedName state0Name state1Name state2Name
    viewName literalInvariantName eqInvariantName neInvariantName
  let callable := literalReturnCallableV1 callableId kind (some callableName) 1
    (encodeU8 1) .public_ invariantSteps
  let instruction : InstructionV1 := {
    result := some { valueId := 0, typeId := 1 }
    op := .literal 1 (encodeU8 1)
  }
  refine validateCallableCfgShape_eq_ok_of_phases callable data.types.size
    data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      callable #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok callable instruction
      · rfl
      · rfl
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok
        callable instruction
      · rfl
      · rfl
  · rfl

private theorem compareCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (callableId : CallableIdV1) (callableName : String)
    (op : BinaryOpV1) (hop : op = .eq ∨ op = .ne) :
    validateCallableCfgShape
      (twoStateCompareInvariantCallableV1 callableId (some callableName)
        0 1 1 2 op .public_ (some 5))
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).types.size
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName).types
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  rcases hop with rfl | rfl
  all_goals
    refine validateCallableCfgShape_eq_ok_of_phases
      (twoStateCompareInvariantCallableV1 callableId (some callableName)
        0 1 1 2 _ .public_ (some 5)) 2
      #[{ id := 0, name := none, shape := .uint 64 },
        { id := 1, name := none, shape := .bool }]
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) #[true]
      ?_ ?_ ?_ ?_ ?_
    · rfl
    · rfl
    · rfl
    · apply validateCallableCfgValueFlow_eq_ok_of_phases
        (twoStateCompareInvariantCallableV1 callableId (some callableName)
          0 1 1 2 _ .public_ (some 5)) #[true]
        #[(0, 0), (1, 0), (2, 0)]
      · rfl
      · rfl
      · simp [checkValueIdUsesExist, twoStateCompareInvariantCallableV1,
          twoStateCompareInvariantBlockV1, opValueUses, terminatorValueUses,
          Pure.pure, Except.pure, Bind.bind, Except.bind]
      · rfl
    · rfl

/-- Exact production generic CFG phase for all four family callables. This
    proves reachability, loop/effect IDs, SSA uses/dominance, state lookup, and
    UInt64 Eq/Ne result typing; invariant closure/fuel remain separate. -/
theorem genericCfgPhasesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateGenericCfgPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  let data := subjectDataV1 qualifiedName state0Name state1Name state2Name
    viewName literalInvariantName eqInvariantName neInvariantName
  let viewCallable := literalReturnCallableV1 0 .view (some viewName) 1
    (encodeU8 1) .public_ none
  let literalInvariantCallable := literalReturnCallableV1 1 .invariant
    (some literalInvariantName) 1 (encodeU8 1) .public_ (some 3)
  let eqCallable := twoStateCompareInvariantCallableV1 2 (some eqInvariantName)
    0 1 1 2 .eq .public_ (some 5)
  let neCallable := twoStateCompareInvariantCallableV1 3 (some neInvariantName)
    0 1 1 2 .ne .public_ (some 5)
  apply validateGenericCfgPhasesV1_four_eq_ok data viewCallable
    literalInvariantCallable eqCallable neCallable
  · rfl
  · exact literalCfgV1 qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName 0 .view viewName none
  · exact literalCfgV1 qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName 1 .invariant
      literalInvariantName (some 3)
  · exact compareCfgV1 qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName 2 eqInvariantName
      .eq (Or.inl rfl)
  · exact compareCfgV1 qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName 3 neInvariantName
      .ne (Or.inr rfl)
  · rfl

/-! ### Production invariant closure and fuel phases -/

def closureMembersV1 : Array Bool := #[false, true, true, true]

/-- The three invariant roots are independent closure members and the view is
    outside the closure. There are no `PureCall` edges or PureFn metadata. -/
theorem invariantClosurePhasesV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateInvariantClosurePhasesV1
      (callablesV1 viewName literalInvariantName eqInvariantName
        neInvariantName) = .ok closureMembersV1 := by
  simp [validateInvariantClosurePhasesV1,
    validateInvariantClosureDagPhasesV1,
    validateInvariantClosureMembershipPhasesV1,
    invariantClosureMembershipResultV1, callablesV1, closureMembersV1,
    literalReturnCallableV1, literalReturnBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1]
  rfl

/-- Intrinsic production fuel is exactly 3 for literal true and 5 for each
    two-load comparison; with no closure edges, carried and intrinsic totals
    coincide. -/
theorem invariantFuelPhasesV1
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateInvariantFuelPhasesV1
      (callablesV1 viewName literalInvariantName eqInvariantName
        neInvariantName) closureMembersV1 = .ok () := by
  rfl

/-- Complete production CFG/invariant segment for the family. -/
theorem cfgInvariantPhasesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String) :
    validateCfgInvariantPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok
    (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName) closureMembersV1
  · exact genericCfgPhasesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName
  · simpa [subjectDataV1] using
      invariantClosurePhasesV1 viewName literalInvariantName eqInvariantName
        neInvariantName
  · simpa [subjectDataV1] using
      invariantFuelPhasesV1 viewName literalInvariantName eqInvariantName
        neInvariantName

/-! ### Full production structure composition -/

/-- Every production structure phase accepts the parameterized
    field-comparison family under exact source-name legality and namespace
    distinctness. No whole-validator reduction or alternate validity predicate
    participates in this certificate. -/
theorem structureV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (legal : StructureLegalV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName) :
    validateSemanticProgramStructureV1
      (subjectDataV1 qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) = .ok () := by
  let data := subjectDataV1 qualifiedName state0Name state1Name state2Name
    viewName literalInvariantName eqInvariantName neInvariantName
  apply validateSemanticProgramStructureV1_eq_ok_of_phases data
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 4)
  · exact structurePreludeV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName
      legal.hnameShape
  · simpa [data, subjectDataV1] using typesStructureV1
  · simpa [data, subjectDataV1] using typeKeyPhasesV1
  · simpa [data, subjectDataV1] using namedTypeNamesV1
  · exact constantsValueBytesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName
  · simpa [data, subjectDataV1] using
      callablesValueBytesV1 viewName literalInvariantName eqInvariantName
        neInvariantName
  · exact constantNamesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName
  · simpa [data, subjectDataV1] using
      logicalStateNamesV1 state0Name state1Name state2Name legal.hstate01
        legal.hstate02 legal.hstate12
  · simp [data, subjectDataV1, validateEventNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateErrorNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateInterfaceFieldNameUniquenessV1,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · simpa [data, subjectDataV1] using
      callableSignaturesV1 viewName literalInvariantName eqInvariantName
        neInvariantName legal.hviewLiteral legal.hviewEq legal.hviewNe
        legal.hliteralEq legal.hliteralNe legal.heqNe
  · simpa [data, subjectDataV1] using
      invariantDeclarationJoinV1 viewName literalInvariantName eqInvariantName
        neInvariantName
  · exact declarationIdentifierNamesV1 qualifiedName state0Name state1Name
      state2Name viewName literalInvariantName eqInvariantName neInvariantName
      legal.hstate0Name legal.hstate1Name legal.hstate2Name legal.hviewName
      legal.hliteralInvariantName legal.heqInvariantName legal.hneInvariantName
  · exact cfgInvariantPhasesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName
  · simpa [data, subjectDataV1] using programRequirementsStructureV1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      state2Name viewName literalInvariantName eqInvariantName neInvariantName).1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      state2Name viewName literalInvariantName eqInvariantName
      neInvariantName).2.1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      state2Name viewName literalInvariantName eqInvariantName
      neInvariantName).2.2

end ProofForgeV2.Semantic.FieldComparisonSubjectV1
