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
  types := #[
    { id := 0, name := none, shape := .uint 64 },
    { id := 1, name := none, shape := .bool }
  ]
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
  · simpa [subjectDataV1] using exactAtRoot_typesV1
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

end ProofForgeV2.Semantic.FieldComparisonSubjectV1
