import ProofForgeV2.Semantic.FieldComparisonSubjectV1
import ProofForgeV2.Semantic.SubjectDataBridgeV1
import ProofForgeV2.Semantic.UInt64ParitySubjectV1

set_option maxHeartbeats 4000000

/-!
  Parameterized production subject certificates for the lowering family with
  a two-slot UInt64-zero initializer, unary additive and guarded-subtractive entries, a nullary UInt64
  view, and a two-state equality invariant. Names remain parameters; semantics
  remain solely in `ReferenceMachineV1`.
-/

namespace ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualitySubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

def typesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .uint 64 },
  { id := 1, name := none, shape := .unit },
  { id := 2, name := none, shape := .bool }
]

def requirementsV1 : ProgramRequirementsV1 := {
  items := #[
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.rollbackRequirementV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.persistentStateRequirementV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.checkedArithmeticRequirementV1
  ]
}

def callablesV1 (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) : Array CallableV1 := #[
  initializerStoreZeroTwoCallableV1 0 0 1,
  addParameterTwoReturnCallableV1 1 (some depositName) depositParameterName 0 0 1 .public_,
  guardedSubParameterTwoUnitCallableV1 2 (some withdrawName) withdrawParameterName
    0 2 1 0 1 .public_,
  viewLoadCallableV1 3 (some viewName) 0 0,
  twoStateCompareInvariantCallableV1 4 (some invariantName)
    0 2 0 1 .eq .public_ (some 5)
]

def subjectDataV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
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
  callables := callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
  invariants := #[{ id := 0, name := invariantName, callableId := 4 }]
  requirements := requirementsV1
}

theorem exactAtRoot_typesV1 :
    ExactMidOffsetInvertAtV1 (encodeArray encodeTypeDeclV1)
      (decodeArray maxTableElements decodeTypeDeclV1) typesV1 1 := by
  simpa [typesV1] using
    exactAt_array_three_of_exactAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      maxTableElements (by decide)
      ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
      ({ id := 1, name := none, shape := .unit } : TypeDeclV1)
      ({ id := 2, name := none, shape := .bool } : TypeDeclV1) 1
      (exactAt_typeDecl_uint_noneV1 0 64 1 (by decide))
      (exactAt_typeDecl_unit_noneV1 1 1 (by decide))
      (exactAt_typeDecl_bool_noneV1 2 1 (by decide))

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
      #[{ id := 0, name := invariantName, callableId := 4 }] 1 :=
  exactAt_array_one_of_exactAtV1 encodeInvariantDeclV1 decodeInvariantDeclV1
    maxTableElements (by decide)
    ({ id := 0, name := invariantName, callableId := 4 } : InvariantDeclV1) 1
    (ExactMidOffsetInvertAtV1.ofGlobal
      midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl _ (by decide))

theorem exactAtRoot_requirementsV1 :
    ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 requirementsV1 1 := by
  simpa [requirementsV1] using
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.exactAtRoot_requirementsV1

theorem rootFieldInvertV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hdepositName : validateIdentifierComponent depositName = .ok ())
    (hdepositParameterName : validateIdentifierComponent depositParameterName = .ok ())
    (hwithdrawName : validateIdentifierComponent withdrawName = .ok ())
    (hwithdrawParameterName : validateIdentifierComponent withdrawParameterName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    RootFieldInvertV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) := by
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
      exactAt_initializerAddGuardedSubViewEqualityCallableTableV1 0 1 2 3 4
        depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
        0 2 1 0 1 hdepositName hdepositParameterName hwithdrawName
        hwithdrawParameterName hviewName hinvariantName
  · simpa [subjectDataV1] using exactAtRoot_invariantsV1 invariantName
  · simpa [subjectDataV1] using exactAtRoot_requirementsV1

/-! ### Production structure phases -/

structure StructureLegalV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) : Prop where
  hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
  hstate0Name : validateIdentifierComponent state0Name = .ok ()
  hstate1Name : validateIdentifierComponent state1Name = .ok ()
  hdepositName : validateIdentifierComponent depositName = .ok ()
  hdepositParameterName : validateIdentifierComponent depositParameterName = .ok ()
  hwithdrawName : validateIdentifierComponent withdrawName = .ok ()
  hwithdrawParameterName : validateIdentifierComponent withdrawParameterName = .ok ()
  hviewName : validateIdentifierComponent viewName = .ok ()
  hinvariantName : validateIdentifierComponent invariantName = .ok ()
  hstate01 : state0Name ≠ state1Name
  hdepositWithdraw : depositName ≠ withdrawName
  hdepositView : depositName ≠ viewName
  hdepositInvariant : depositName ≠ invariantName
  hwithdrawView : withdrawName ≠ viewName
  hwithdrawInvariant : withdrawName ≠ invariantName
  hviewInvariant : viewName ≠ invariantName

theorem structurePreludeV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()) :
    validateSemanticProgramStructurePreludeV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  simp [subjectDataV1, typesV1, callablesV1,
    initializerStoreZeroTwoCallableV1, initializerStoreZeroTwoBlockV1,
    addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
    guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
    viewLoadCallableV1, viewLoadBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
    validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    checkTypeShapeRefs, checkTypeIdInRange, checkCallableIdInRange,
    checkIdEqualsIndex, hnameShape,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typesStructureV1 : validateTypesStructureV1 typesV1 = .ok () := by
  rfl

private def uint64TypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private def unitTypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 110, 105, 116, 0, 0]

private def boolTypeShapeBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private theorem encodeTypeShape_uint64V1 :
    encodeTypeShapeV1 (.uint 64) = .ok uint64TypeShapeBytesV1 := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] =
    .ok uint64TypeShapeBytesV1
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem encodeTypeShape_unitV1 :
    encodeTypeShapeV1 (.unit : TypeShapeV1) = .ok unitTypeShapeBytesV1 := by
  change encodeNullary "Type.Unit" = .ok unitTypeShapeBytesV1
  rw [encodeNullary_eq_okV1 "Type.Unit" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_boolV1 :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytesV1 := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytesV1
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem compare_uint64_unitV1 :
    compareByteArrayLex uint64TypeShapeBytesV1 unitTypeShapeBytesV1 = .lt := by
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
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 9 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

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

private theorem compare_unit_boolV1 :
    compareByteArrayLex unitTypeShapeBytesV1 boolTypeShapeBytesV1 = .gt := by
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

private theorem typeKeyNamedPrefixV1 :
    validateNamedPrefixRankV1 typesV1 = .ok () := by
  simp [typesV1, validateNamedPrefixRankV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem collectPrimitiveTypeKeysV1 :
    collectPrimitiveAnonymousTypeKeysV1 typesV1 =
      .ok #[uint64TypeShapeBytesV1, unitTypeShapeBytesV1,
        boolTypeShapeBytesV1] := by
  simp [typesV1, collectPrimitiveAnonymousTypeKeysV1,
    encodeTypeShape_uint64V1, encodeTypeShape_unitV1,
    encodeTypeShape_boolV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typeKeyPrimitiveLeafV1 :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 typesV1 = .ok () := by
  apply validatePrimitiveAnonymousTypeKeyUniquenessV1_collect_three_eq_ok
    typesV1 uint64TypeShapeBytesV1 unitTypeShapeBytesV1 boolTypeShapeBytesV1
    collectPrimitiveTypeKeysV1
  · rw [compare_uint64_unitV1]
    decide
  · rw [compare_uint64_boolV1]
    decide
  · rw [compare_unit_boolV1]
    decide

private theorem typeKeyRecursiveAnonymousV1 :
    validateRecursiveAnonymousTypeKeyUniquenessV1 typesV1 = .ok () := by
  simp [typesV1, validateRecursiveAnonymousTypeKeyUniquenessV1,
    Pure.pure, Except.pure]

private theorem typeKeyNamedBodyCycleV1 :
    validateNamedBodyOptionCycleLegalityV1 typesV1 = .ok () := by
  simp [typesV1, validateNamedBodyOptionCycleLegalityV1,
    Pure.pure, Except.pure]

theorem typeKeyPhasesV1 : validateTypeKeyPhasesV1 typesV1 = .ok () := by
  exact validateTypeKeyPhasesV1_eq_ok_of_phases typesV1
    typeKeyNamedPrefixV1 typeKeyPrimitiveLeafV1 typeKeyRecursiveAnonymousV1
    typeKeyNamedBodyCycleV1

theorem namedTypeNamesV1 :
    validateNamedTypeNameUniquenessV1 typesV1 = .ok () := by
  rfl

theorem constantsValueBytesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateConstantsValueBytesV1 typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName).constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [subjectDataV1, validateConstantsValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem callablesValueBytesV1 (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCallablesValueBytesV1 typesV1
      (callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName) maxCanonicalProgramBytes =
        .ok (maxCanonicalProgramBytes - 18) := by
  have hzero0 :
      validateOpValueBytesV1 typesV1 (.literal 0 zero8BytesV1)
        maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 9) := by
    simpa [typesV1, zero8BytesV1] using
      validateOpValueBytesV1_literal_uint64_eq_ok typesV1 0
        ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
        0 0 0 0 0 0 0 0 maxCanonicalProgramBytes (by rfl) (by rfl)
        (by decide)
  have hzero1 :
      validateOpValueBytesV1 typesV1 (.literal 0 zero8BytesV1)
        (maxCanonicalProgramBytes - 9) =
          .ok (maxCanonicalProgramBytes - 18) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok typesV1 0
      ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
      0 0 0 0 0 0 0 0 (maxCanonicalProgramBytes - 9)
      (by rfl) (by rfl) (by decide)
    have hbudget : maxCanonicalProgramBytes - 9 - 9 =
        maxCanonicalProgramBytes - 18 := by omega
    rw [hbudget] at h
    simpa [typesV1, zero8BytesV1] using h
  have hload (stateId : StateIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.stateLoad stateId) budget =
        .ok budget := rfl
  have hstore (stateId : StateIdV1) (valueId : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.stateStore stateId valueId) budget =
        .ok budget := rfl
  have hbinary (op : BinaryOpV1) (left right : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.binary op left right) budget =
        .ok budget := rfl
  have hreturn (value : Option ValueIdV1) (budget : Nat) :
      validateTerminatorValueBytesV1 typesV1 (.return_ value) budget =
        .ok budget := rfl
  have hassert (condition : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 typesV1 (.assert_ condition none #[]) budget =
        .ok budget := rfl
  simp [callablesV1, initializerStoreZeroTwoCallableV1,
    initializerStoreZeroTwoBlockV1,
    addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
    guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
    viewLoadCallableV1, viewLoadBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
    validateCallablesValueBytesV1, hzero0, hzero1, hload, hstore, hbinary,
    hreturn, hassert,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem constantNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateConstantNameUniquenessV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName).constants = .ok () := by
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
  have h01 : (state0Name == state1Name) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hstate01)
  simp [validateLogicalStateNameUniquenessV1,
    checkUniqueDeclarationNamesV1, h01,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem callableSignaturesV1
    (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String)
    (hdepositWithdraw : depositName ≠ withdrawName)
    (hdepositView : depositName ≠ viewName)
    (hdepositInvariant : depositName ≠ invariantName)
    (hwithdrawView : withdrawName ≠ viewName)
    (hwithdrawInvariant : withdrawName ≠ invariantName)
    (hviewInvariant : viewName ≠ invariantName) :
    validateCallableSignaturePhasesV1 typesV1
      (callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName) = .ok () := by
  have hdepositWithdraw' : (depositName == withdrawName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hdepositWithdraw)
  have hwithdrawView' : (withdrawName == viewName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hwithdrawView)
  have hwithdrawInvariant' : (withdrawName == invariantName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hwithdrawInvariant)
  have hnames : (viewName == invariantName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hviewInvariant)
  have hdepositView' : (depositName == viewName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hdepositView)
  have hdepositInvariant' : (depositName == invariantName) = false :=
    Bool.eq_false_iff.mpr (by simpa [BEq.beq] using hdepositInvariant)
  have hInitInit : ((.initializer : CallableKindV1) == .initializer) = true :=
    by decide
  have hViewInit : ((.view : CallableKindV1) == .initializer) = false :=
    by decide
  have hEntryInit : ((.entry : CallableKindV1) == .initializer) = false :=
    by decide
  have hInvInit : ((.invariant : CallableKindV1) == .initializer) = false :=
    by decide
  have hInitInv : ((.initializer : CallableKindV1) == .invariant) = false :=
    by decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false :=
    by decide
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false :=
    by decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true :=
    by decide
  have hPublic : ((.public_ : VisibilityV1) == .public_) = true := by
    decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [typesV1, callablesV1, initializerStoreZeroTwoCallableV1,
      initializerStoreZeroTwoBlockV1,
      addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
      guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
      viewLoadCallableV1, viewLoadBlockV1,
      twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
      validateCallableKindNamePresenceV1,
      validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1,
      validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
      validateInitializerResultShapeV1, validateInvariantResultShapeV1,
      validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
      validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, hnames, hdepositView',
      hdepositInvariant', hdepositWithdraw', hwithdrawView', hwithdrawInvariant', hInitInit, hEntryInit, hViewInit,
      hInvInit, hInitInv, hEntryInv, hViewInv, hInvInv, hPublic,
      Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem invariantDeclarationJoinV1
    (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateInvariantDeclarationJoinV1 (callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName)
      #[{ id := 0, name := invariantName, callableId := 4 }] = .ok () := by
  have hInitInv : ((.initializer : CallableKindV1) == .invariant) = false :=
    by decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false :=
    by decide
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false :=
    by decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true :=
    by decide
  simp [callablesV1, initializerStoreZeroTwoCallableV1,
    initializerStoreZeroTwoBlockV1,
    addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
    guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
    viewLoadCallableV1, viewLoadBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
    validateInvariantDeclarationJoinV1, hInitInv, hEntryInv, hViewInv, hInvInv,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem declarationIdentifierNamesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String)
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hdepositName : validateIdentifierComponent depositName = .ok ())
    (hdepositParameterName : validateIdentifierComponent depositParameterName = .ok ())
    (hwithdrawName : validateIdentifierComponent withdrawName = .ok ())
    (hwithdrawParameterName : validateIdentifierComponent withdrawParameterName = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ()) :
    validateDeclarationIdentifierNamesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  have hstate0 := validateIdentifierNameV1_eq_ok_of_common _ hstate0Name
  have hstate1 := validateIdentifierNameV1_eq_ok_of_common _ hstate1Name
  have hdeposit := validateIdentifierNameV1_eq_ok_of_common _ hdepositName
  have hparameter := validateIdentifierNameV1_eq_ok_of_common _ hdepositParameterName
  have hwithdraw := validateIdentifierNameV1_eq_ok_of_common _ hwithdrawName
  have hwithdrawParameter := validateIdentifierNameV1_eq_ok_of_common _ hwithdrawParameterName
  have hview := validateIdentifierNameV1_eq_ok_of_common _ hviewName
  have hinvariant := validateIdentifierNameV1_eq_ok_of_common _ hinvariantName
  simp [subjectDataV1, typesV1, callablesV1,
    initializerStoreZeroTwoCallableV1, initializerStoreZeroTwoBlockV1,
    addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
    guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
    viewLoadCallableV1, viewLoadBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1,
    validateDeclarationIdentifierNamesV1,
    validateTypeShapeIdentifierNamesV1, hstate0, hstate1, hdeposit,
    hparameter, hwithdraw, hwithdrawParameter, hview, hinvariant,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem programRequirementsStructureV1 :
    validateProgramRequirementsStructure requirementsV1 = .ok () := by
  simpa [requirementsV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.rollbackRequirementV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.persistentStateRequirementV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.checkedArithmeticRequirementV1,
    ProofForgeV2.Semantic.UInt64ParitySubjectV1.requirementV1] using
    (validateProgramRequirementsStructure_failure_state_checked_eq_ok
      s2RequirementVersionV1 s2RequirementVersionV1 s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 }
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
      { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 })

theorem emptyOperationRequirementsV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateContextReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
          invariantName) = .ok () ∧
      validateCommitRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
          invariantName) = .ok () ∧
      validateEnvReadRequirementsV1
        (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
          invariantName) = .ok () := by
  exact ⟨rfl, rfl, rfl⟩

/-! ### Production generic CFG, closure, and fuel phases -/

private theorem initializerCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCallableCfgShape
      (initializerStoreZeroTwoCallableV1 0 0 1)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  let callable := initializerStoreZeroTwoCallableV1 0 0 1
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
    invariantName
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
        initializerStoreZeroTwoCallableV1, initializerStoreZeroTwoBlockV1,
        opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem viewCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCallableCfgShape
      (viewLoadCallableV1 3 (some viewName) 0 0)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  let callable := viewLoadCallableV1 3 (some viewName) 0 0
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
    invariantName
  refine validateCallableCfgShape_eq_ok_of_phases callable typesV1.size
    typesV1 data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      callable #[true] #[(0, 0)]
    · rfl
    · rfl
    · simp [callable, checkValueIdUsesExist, viewLoadCallableV1,
        viewLoadBlockV1, opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem entryCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCallableCfgShape
      (addParameterTwoReturnCallableV1 1 (some depositName) depositParameterName
        0 0 1 .public_)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName
        depositParameterName withdrawName withdrawParameterName viewName invariantName) = .ok () := by
  let callable := addParameterTwoReturnCallableV1 1 (some depositName)
    depositParameterName 0 0 1 .public_
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName
    depositParameterName withdrawName withdrawParameterName viewName invariantName
  refine validateCallableCfgShape_eq_ok_of_phases callable typesV1.size
    typesV1 data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases
      callable #[true] #[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0)]
    · rfl
    · rfl
    · simp [callable, checkValueIdUsesExist,
        addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
        opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem withdrawCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName
      viewName invariantName : String) :
    validateCallableCfgShape
      (guardedSubParameterTwoUnitCallableV1 2 (some withdrawName) withdrawParameterName
        0 2 1 0 1 .public_)
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName
        withdrawName withdrawParameterName viewName invariantName) = .ok () := by
  let callable := guardedSubParameterTwoUnitCallableV1 2 (some withdrawName)
    withdrawParameterName 0 2 1 0 1 .public_
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName
    withdrawName withdrawParameterName viewName invariantName
  refine validateCallableCfgShape_eq_ok_of_phases callable typesV1.size
    typesV1 data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases callable #[true]
      #[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0), (8, 0)]
    · rfl
    · rfl
    · simp [callable, checkValueIdUsesExist,
        guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
        opValueUses, terminatorValueUses,
        Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem invariantCfgV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCallableCfgShape
      (twoStateCompareInvariantCallableV1 4 (some invariantName)
        0 2 0 1 .eq .public_ (some 5))
      typesV1.size typesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  let callable := twoStateCompareInvariantCallableV1 4 (some invariantName)
    0 2 0 1 .eq .public_ (some 5)
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
    invariantName
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
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateGenericCfgPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  apply validateGenericCfgPhasesV1_five_eq_ok
    (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName)
    (initializerStoreZeroTwoCallableV1 0 0 1)
    (addParameterTwoReturnCallableV1 1 (some depositName) depositParameterName
      0 0 1 .public_)
    (guardedSubParameterTwoUnitCallableV1 2 (some withdrawName) withdrawParameterName
      0 2 1 0 1 .public_)
    (viewLoadCallableV1 3 (some viewName) 0 0)
    (twoStateCompareInvariantCallableV1 4 (some invariantName)
      0 2 0 1 .eq .public_ (some 5))
  · rfl
  · exact initializerCfgV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · exact entryCfgV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName
      viewName invariantName
  · exact withdrawCfgV1 qualifiedName state0Name state1Name depositName depositParameterName
      withdrawName withdrawParameterName viewName invariantName
  · exact viewCfgV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
  · exact invariantCfgV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · rfl

def closureMembersV1 : Array Bool := #[false, false, false, false, true]

theorem invariantClosurePhasesV1
    (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateInvariantClosurePhasesV1
      (callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName) = .ok closureMembersV1 := by
  simp [validateInvariantClosurePhasesV1,
    validateInvariantClosureDagPhasesV1,
    validateInvariantClosureMembershipPhasesV1,
    invariantClosureMembershipResultV1, callablesV1, closureMembersV1,
    initializerStoreZeroTwoCallableV1, initializerStoreZeroTwoBlockV1,
    addParameterTwoReturnCallableV1, addParameterTwoReturnBlockV1,
    guardedSubParameterTwoUnitCallableV1, guardedSubParameterTwoUnitBlockV1,
    viewLoadCallableV1, viewLoadBlockV1,
    twoStateCompareInvariantCallableV1, twoStateCompareInvariantBlockV1]
  rfl

theorem invariantFuelPhasesV1
    (depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateInvariantFuelPhasesV1
      (callablesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName) closureMembersV1 = .ok () := by
  rfl

theorem cfgInvariantPhasesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateCfgInvariantPhasesV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok
    (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName)
    closureMembersV1
  · exact genericCfgPhasesV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · simpa [subjectDataV1] using
      invariantClosurePhasesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
  · simpa [subjectDataV1] using
      invariantFuelPhasesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName

/-! ### Full production structure composition and admission -/

theorem structureV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String)
    (legal : StructureLegalV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName) :
    validateSemanticProgramStructureV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  let data := subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
    invariantName
  apply validateSemanticProgramStructureV1_eq_ok_of_phases data
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 18)
  · exact structurePreludeV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName legal.hnameShape
  · simpa [data, subjectDataV1] using typesStructureV1
  · simpa [data, subjectDataV1] using typeKeyPhasesV1
  · simpa [data, subjectDataV1] using namedTypeNamesV1
  · exact constantsValueBytesV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · simpa [data, subjectDataV1] using
      callablesValueBytesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
  · exact constantNamesV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · simpa [data, subjectDataV1] using
      logicalStateNamesV1 state0Name state1Name legal.hstate01
  · simp [data, subjectDataV1, validateEventNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateErrorNameUniquenessV1,
      checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]
  · simp [data, subjectDataV1, validateInterfaceFieldNameUniquenessV1,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · simpa [data, subjectDataV1] using
      callableSignaturesV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
        legal.hdepositWithdraw legal.hdepositView legal.hdepositInvariant
        legal.hwithdrawView legal.hwithdrawInvariant legal.hviewInvariant
  · simpa [data, subjectDataV1] using
      invariantDeclarationJoinV1 depositName depositParameterName withdrawName withdrawParameterName viewName invariantName
  · exact declarationIdentifierNamesV1 qualifiedName state0Name state1Name
      depositName depositParameterName withdrawName withdrawParameterName viewName invariantName legal.hstate0Name
      legal.hstate1Name legal.hdepositName legal.hdepositParameterName legal.hwithdrawName
      legal.hwithdrawParameterName legal.hviewName
      legal.hinvariantName
  · exact cfgInvariantPhasesV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
      invariantName
  · simpa [data, subjectDataV1] using programRequirementsStructureV1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      depositName depositParameterName withdrawName withdrawParameterName viewName invariantName).1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      depositName depositParameterName withdrawName withdrawParameterName viewName invariantName).2.1
  · exact (emptyOperationRequirementsV1 qualifiedName state0Name state1Name
      depositName depositParameterName withdrawName withdrawParameterName viewName invariantName).2.2

theorem referenceAdmissionV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName invariantName : String) :
    validateReferenceProgramDataAdmissionV1
      (subjectDataV1 qualifiedName state0Name state1Name depositName depositParameterName withdrawName withdrawParameterName viewName
        invariantName) = .ok () := by
  rfl

end ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualitySubjectV1
