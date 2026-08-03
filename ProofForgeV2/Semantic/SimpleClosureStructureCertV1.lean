import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.SimpleClosureStructureCertV1 — production structure
  certificate for the name/module-parameterized simple-closure family.

  Goal (B-SC-STRUCT): under a sufficiently precise params legality witness
  constructible by ProgramElaboration from ValidatedSource / Normalize shape,

    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ()

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
    * no hardcoded Tests FQN / fixture bytes
    * no second structure model — every phase premise names a production
      Wire validator result
    * does not claim encode/decode/product-positive (B-SC-ENC / B-SC-DEC)

  Witness covers:
    * every QN component + view/invariant names under shared
      `validateIdentifierComponent` (Unicode 17 NFC + Lean identifier grammar)
    * viewName ≠ invName
    * fixed CFG / signature / fuel / requirement phases of the family
-/

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

namespace ProofForgeV2.Semantic.SimpleClosureStructureCertV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

/-! ### Params legality witness (elaborator-constructible) -/

/-- Sufficient params legality for structure (and later encode name spines).
    Stronger than `SimpleClosureParamsWellFormedV1`: every free name site is
    closed under the sole SPEC-COMMON identifier authority. ProgramElaboration
    can mint this from ValidatedSource / Normalize names without Tests FQN. -/
structure SimpleClosureParamsLegalV1 (p : SimpleClosureParamsV1) : Prop where
  /-- Program root has at least two components (structure step 0). -/
  hqnSize : 2 ≤ p.qnSize
  /-- Program root stays within Common `validateQualifiedName` component cap
      (encode path `renderQualifiedNameComponents` / structure share the same
      256 bound). Elaborator-constructible; not an encode field-ok premise. -/
  hqnCap : p.qnSize ≤ 256
  /-- View and invariant declaration names are distinct (callable uniqueness). -/
  hdistinct : p.viewName ≠ p.invName
  /-- QN head passes shared identifier/NFC grammar. -/
  hqnHead : validateIdentifierComponent p.qnHead = .ok ()
  /-- Every QN tail component passes shared identifier/NFC grammar. -/
  hqnTail :
    ∀ (i : Nat) (hi : i < p.qnTail.size),
      validateIdentifierComponent p.qnTail[i] = .ok ()
  /-- View name passes shared identifier/NFC grammar. -/
  hview : validateIdentifierComponent p.viewName = .ok ()
  /-- Invariant name passes shared identifier/NFC grammar. -/
  hinv : validateIdentifierComponent p.invName = .ok ()

/-- Identifier success implies positive UTF-8 byte size (hence nonempty name).
    Stronger than `WellFormed`'s character-length field and what elaborators
    already discharge via `validateIdentifierComponent`. -/
theorem utf8ByteSize_pos_of_identifierOk (name : String)
    (h : validateIdentifierComponent name = .ok ()) : 1 ≤ name.utf8ByteSize := by
  unfold validateIdentifierComponent at h
  by_cases hgate : 1 ≤ name.utf8ByteSize ∧ name.utf8ByteSize ≤ 240
  · exact hgate.1
  · simp [hgate, Pure.pure, Except.pure, Bind.bind, Except.bind] at h

/-- Materialized root QN component count equals free `qnSize`. -/
theorem materialize_qnSize (p : SimpleClosureParamsV1) :
    (materializeSimpleClosureDataV1 p).qualifiedName.components.toArray.size =
      p.qnSize := by
  simp [materializeSimpleClosureDataV1, SimpleClosureParamsV1.toQualifiedName,
    NonEmptyArray.toArray, SimpleClosureParamsV1.qnSize, Array.size_append]
  omega

/-! ### Fixed family type-shape bytes (name-independent) -/

private def simpleClosureBoolTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private def simpleClosureUInt64TypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private theorem encodeTypeShape_bool_simpleClosure :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok simpleClosureBoolTypeShapeBytes := by
  change encodeNullary "Type.Bool" = .ok simpleClosureBoolTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem encodeTypeShape_uint64_simpleClosure :
    encodeTypeShapeV1 (.uint 64) = .ok simpleClosureUInt64TypeShapeBytes := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok simpleClosureUInt64TypeShapeBytes
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem compare_bool_uint64_simpleClosure :
    compareByteArrayLex simpleClosureBoolTypeShapeBytes
      simpleClosureUInt64TypeShapeBytes = .lt := by
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
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-! ### Phase: prelude -/

theorem structurePrelude_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateSemanticProgramStructurePreludeV1 (materializeSimpleClosureDataV1 p) =
      .ok () := by
  -- `qnSize = tail.size + 1`, and `toArray.size = 1 + tail.size`.
  have hqn : 2 ≤ 1 + p.qnTail.size := by
    have h := legal.hqnSize
    simp only [SimpleClosureParamsV1.qnSize] at h
    omega
  simp [validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    validateProgramQualifiedNameShapeV1, materializeSimpleClosureDataV1,
    SimpleClosureParamsV1.toQualifiedName, NonEmptyArray.toArray,
    Array.size_append, simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1,
    simpleClosureViewCallableV1, simpleClosureInvCallableV1,
    simpleClosureBlockV1, simpleClosureLitTrueV1, simpleClosureInvariantDeclV1,
    simpleClosureBoolRequirementV1, checkTypeShapeRefs, checkTypeIdInRange,
    checkCallableIdInRange, checkIdEqualsIndex, hqn, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-! ### Phase: types / TypeKey / named-type uniqueness (name-independent) -/

theorem typesStructure_simpleClosure (p : SimpleClosureParamsV1) :
    validateTypesStructureV1 (materializeSimpleClosureDataV1 p).types = .ok () := by
  simp [materializeSimpleClosureDataV1, validateTypesStructureV1,
    validateTypeDeclShapeV1, validateTypeDeclNamedRuleV1, simpleClosureBoolTypeV1,
    simpleClosureUInt64TypeV1, legalIntegerWidthV1_64, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

theorem typeKeyNamedPrefix_simpleClosure (p : SimpleClosureParamsV1) :
    validateNamedPrefixRankV1 (materializeSimpleClosureDataV1 p).types = .ok () := by
  simp [materializeSimpleClosureDataV1, validateNamedPrefixRankV1,
    simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

theorem typeKeyPrimitiveLeaf_simpleClosure (p : SimpleClosureParamsV1) :
    validatePrimitiveAnonymousTypeKeyUniquenessV1
      (materializeSimpleClosureDataV1 p).types = .ok () := by
  simp [materializeSimpleClosureDataV1, validatePrimitiveAnonymousTypeKeyUniquenessV1,
    simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1,
    encodeTypeShape_bool_simpleClosure, encodeTypeShape_uint64_simpleClosure,
    compare_bool_uint64_simpleClosure, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

theorem typeKeyRecursiveAnonymous_simpleClosure (p : SimpleClosureParamsV1) :
    validateRecursiveAnonymousTypeKeyUniquenessV1
      (materializeSimpleClosureDataV1 p).types = .ok () := by
  simp [materializeSimpleClosureDataV1, validateRecursiveAnonymousTypeKeyUniquenessV1,
    simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1, Pure.pure, Except.pure]

theorem typeKeyNamedBodyCycle_simpleClosure (p : SimpleClosureParamsV1) :
    validateNamedBodyOptionCycleLegalityV1
      (materializeSimpleClosureDataV1 p).types = .ok () := by
  simp [materializeSimpleClosureDataV1, validateNamedBodyOptionCycleLegalityV1,
    simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1, Pure.pure, Except.pure]

theorem typeKeyPhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateTypeKeyPhasesV1 (materializeSimpleClosureDataV1 p).types = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · exact typeKeyNamedPrefix_simpleClosure p
  · exact typeKeyPrimitiveLeaf_simpleClosure p
  · exact typeKeyRecursiveAnonymous_simpleClosure p
  · exact typeKeyNamedBodyCycle_simpleClosure p

theorem namedTypeNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateNamedTypeNameUniquenessV1 (materializeSimpleClosureDataV1 p).types =
      .ok () := by
  simp [materializeSimpleClosureDataV1, validateNamedTypeNameUniquenessV1,
    checkUniqueDeclarationNamesV1, simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Phase: valueBytes + empty declaration-name uniqueness -/

theorem constantsValueBytes_simpleClosure (p : SimpleClosureParamsV1) :
    validateConstantsValueBytesV1 (materializeSimpleClosureDataV1 p).types
      (materializeSimpleClosureDataV1 p).constants maxCanonicalProgramBytes =
      .ok maxCanonicalProgramBytes := by
  simp [materializeSimpleClosureDataV1, validateConstantsValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem callablesValueBytes_simpleClosure (p : SimpleClosureParamsV1) :
    validateCallablesValueBytesV1 (materializeSimpleClosureDataV1 p).types
      (materializeSimpleClosureDataV1 p).callables maxCanonicalProgramBytes =
      .ok (maxCanonicalProgramBytes - 4) := by
  let data := materializeSimpleClosureDataV1 p
  let viewC := simpleClosureViewCallableV1 p.viewName
  let invC := simpleClosureInvCallableV1 p.invName
  have henc : encodeU8 1 = ByteArray.mk #[1] := rfl
  have htrue :
      validateOpValueBytesV1 data.types
        (.literal 0 (ByteArray.mk #[1])) maxCanonicalProgramBytes =
        .ok (maxCanonicalProgramBytes - 2) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok data.types 0
      simpleClosureBoolTypeV1 1
    · simp [data, materializeSimpleClosureDataV1, simpleClosureBoolTypeV1]
    · rfl
    · exact Or.inr rfl
    · decide
  have htrue2 :
      validateOpValueBytesV1 data.types
        (.literal 0 (ByteArray.mk #[1])) (maxCanonicalProgramBytes - 2) =
        .ok (maxCanonicalProgramBytes - 4) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok data.types 0
      simpleClosureBoolTypeV1 1
    · simp [data, materializeSimpleClosureDataV1, simpleClosureBoolTypeV1]
    · rfl
    · exact Or.inr rfl
    · decide
  have hop0 :
      validateOpValueBytesV1 data.types simpleClosureLitTrueV1.op
        maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 2) := by
    simp [simpleClosureLitTrueV1, henc, htrue]
  have hop1 :
      validateOpValueBytesV1 data.types simpleClosureLitTrueV1.op
        (maxCanonicalProgramBytes - 2) = .ok (maxCanonicalProgramBytes - 4) := by
    simp [simpleClosureLitTrueV1, henc, htrue2]
  have hterm (b : Nat) :
      validateTerminatorValueBytesV1 data.types simpleClosureBlockV1.terminator b =
        .ok b := by
    simp [simpleClosureBlockV1, validateTerminatorValueBytesV1, Pure.pure,
      Except.pure]
  change validateCallablesValueBytesV1 data.types #[viewC, invC]
    maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 4)
  apply validateCallablesValueBytesV1_two_single_op (types := data.types)
    viewC invC simpleClosureBlockV1 simpleClosureBlockV1
    simpleClosureLitTrueV1 simpleClosureLitTrueV1
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 2)
    (maxCanonicalProgramBytes - 4)
  · rfl
  · rfl
  · rfl
  · rfl
  · exact hterm (maxCanonicalProgramBytes - 2)
  · exact hterm (maxCanonicalProgramBytes - 4)
  · exact hop0
  · exact hop1

theorem constantNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateConstantNameUniquenessV1 (materializeSimpleClosureDataV1 p).constants =
      .ok () := by
  simp [materializeSimpleClosureDataV1, validateConstantNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem logicalStateNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateLogicalStateNameUniquenessV1
      (materializeSimpleClosureDataV1 p).logicalState = .ok () := by
  simp [materializeSimpleClosureDataV1, validateLogicalStateNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem eventNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateEventNameUniquenessV1 (materializeSimpleClosureDataV1 p).events =
      .ok () := by
  simp [materializeSimpleClosureDataV1, validateEventNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem errorNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateErrorNameUniquenessV1 (materializeSimpleClosureDataV1 p).errors =
      .ok () := by
  simp [materializeSimpleClosureDataV1, validateErrorNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

theorem interfaceFieldNames_simpleClosure (p : SimpleClosureParamsV1) :
    validateInterfaceFieldNameUniquenessV1
      (materializeSimpleClosureDataV1 p).events
      (materializeSimpleClosureDataV1 p).errors = .ok () := by
  simp [materializeSimpleClosureDataV1, validateInterfaceFieldNameUniquenessV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Phase: callable signatures + InvariantDecl join -/

private theorem view_ne_initializer :
    ((.view : CallableKindV1) == .initializer) = false := by decide
private theorem invariant_ne_initializer :
    ((.invariant : CallableKindV1) == .initializer) = false := by decide
private theorem view_ne_invariant :
    ((.view : CallableKindV1) == .invariant) = false := by decide
private theorem invariant_eq_invariant :
    ((.invariant : CallableKindV1) == .invariant) = true := by decide
private theorem public_eq_public :
    ((.public_ : VisibilityV1) == .public_) = true := by decide

theorem callableSignatures_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateCallableSignaturePhasesV1
      (materializeSimpleClosureDataV1 p).types
      (materializeSimpleClosureDataV1 p).callables = .ok () := by
  have hne : (p.viewName == p.invName) = false := by
    simpa [beq_eq_false_iff_ne] using legal.hdistinct
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [materializeSimpleClosureDataV1, simpleClosureBoolTypeV1,
      simpleClosureUInt64TypeV1, simpleClosureViewCallableV1,
      simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1,
      validateCallableKindNamePresenceV1, validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1, validateCallableEntryViewPresenceV1,
      validateInitializerCardinalityV1, validateInitializerResultShapeV1,
      validateInvariantResultShapeV1, validateInvariantParameterShapeV1,
      validateInvariantLoopBoundsShapeV1, validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, view_ne_initializer,
      invariant_ne_initializer, view_ne_invariant, invariant_eq_invariant,
      public_eq_public, hne, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem invariantDeclarationJoin_simpleClosure (p : SimpleClosureParamsV1) :
    validateInvariantDeclarationJoinV1
      (materializeSimpleClosureDataV1 p).callables
      (materializeSimpleClosureDataV1 p).invariants = .ok () := by
  simp [materializeSimpleClosureDataV1, validateInvariantDeclarationJoinV1,
    simpleClosureViewCallableV1, simpleClosureInvCallableV1, simpleClosureBlockV1,
    simpleClosureLitTrueV1, simpleClosureInvariantDeclV1, view_ne_invariant,
    invariant_eq_invariant, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Phase: declaration identifier names (view + inv) -/

theorem declarationIdentifierNames_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateDeclarationIdentifierNamesV1 (materializeSimpleClosureDataV1 p) =
      .ok () := by
  have hview : validateIdentifierNameV1 p.viewName = .ok () :=
    validateIdentifierNameV1_eq_ok_of_common p.viewName legal.hview
  have hinv : validateIdentifierNameV1 p.invName = .ok () :=
    validateIdentifierNameV1_eq_ok_of_common p.invName legal.hinv
  simp [validateDeclarationIdentifierNamesV1, validateTypeShapeIdentifierNamesV1,
    materializeSimpleClosureDataV1, simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1,
    simpleClosureViewCallableV1, simpleClosureInvCallableV1, simpleClosureBlockV1,
    simpleClosureLitTrueV1, simpleClosureInvariantDeclV1, hview, hinv,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Phase: two-callable literal-true CFG -/

private theorem simpleClosureLitTrue_opUses_empty :
    opValueUses simpleClosureLitTrueV1.op = #[] := by
  simp [simpleClosureLitTrueV1, opValueUses]

private theorem viewCfg_simpleClosure (p : SimpleClosureParamsV1) :
    let data := materializeSimpleClosureDataV1 p
    let viewC := simpleClosureViewCallableV1 p.viewName
    validateCallableCfgShape viewC data.types.size data.types data = .ok () := by
  let data := materializeSimpleClosureDataV1 p
  let viewC := simpleClosureViewCallableV1 p.viewName
  refine validateCallableCfgShape_eq_ok_of_phases
    viewC data.types.size data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases viewC #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok viewC
        simpleClosureLitTrueV1
      · rfl
      · exact simpleClosureLitTrue_opUses_empty
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok viewC
        simpleClosureLitTrueV1
      · rfl
      · exact simpleClosureLitTrue_opUses_empty
  · rfl

private theorem invCfg_simpleClosure (p : SimpleClosureParamsV1) :
    let data := materializeSimpleClosureDataV1 p
    let invC := simpleClosureInvCallableV1 p.invName
    validateCallableCfgShape invC data.types.size data.types data = .ok () := by
  let data := materializeSimpleClosureDataV1 p
  let invC := simpleClosureInvCallableV1 p.invName
  refine validateCallableCfgShape_eq_ok_of_phases
    invC data.types.size data.types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases invC #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok invC
        simpleClosureLitTrueV1
      · rfl
      · exact simpleClosureLitTrue_opUses_empty
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok invC
        simpleClosureLitTrueV1
      · rfl
      · exact simpleClosureLitTrue_opUses_empty
  · rfl

theorem genericCfgPhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateGenericCfgPhasesV1 (materializeSimpleClosureDataV1 p) = .ok () := by
  let data := materializeSimpleClosureDataV1 p
  let viewC := simpleClosureViewCallableV1 p.viewName
  let invC := simpleClosureInvCallableV1 p.invName
  apply validateGenericCfgPhasesV1_two_eq_ok data viewC invC
  · rfl
  · exact viewCfg_simpleClosure p
  · exact invCfg_simpleClosure p
  · rfl

/-! ### Phase: invariant closure membership / DAG / fuel -/

def simpleClosureMembersV1 : Array Bool := #[false, true]

theorem computeInvariantClosureMembership_simpleClosure
    (p : SimpleClosureParamsV1) :
    invariantClosureMembershipResultV1
      (materializeSimpleClosureDataV1 p).callables =
      .ok simpleClosureMembersV1 := by
  simp [invariantClosureMembershipResultV1, simpleClosureMembersV1,
    materializeSimpleClosureDataV1, simpleClosureViewCallableV1,
    simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1]
  rfl

theorem invariantClosureMembershipPhases_simpleClosure
    (p : SimpleClosureParamsV1) :
    validateInvariantClosureMembershipPhasesV1
      (materializeSimpleClosureDataV1 p).callables =
      .ok simpleClosureMembersV1 := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · -- root direct ops: only Bool literal
    rfl
  · exact computeInvariantClosureMembership_simpleClosure p
  · apply validatePureFnInvariantClosureMembershipTwoV1
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName) <;> rfl

theorem invariantClosureDagPhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateInvariantClosureDagPhasesV1
      (materializeSimpleClosureDataV1 p).callables =
      .ok simpleClosureMembersV1 := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact invariantClosureMembershipPhases_simpleClosure p
  · apply validateInvariantClosureDagCanonicalTwoV1
    · simp [materializeSimpleClosureDataV1, simpleClosureViewCallableV1,
        simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1]
      rfl
    · rfl
    · rfl

theorem invariantClosurePhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateInvariantClosurePhasesV1
      (materializeSimpleClosureDataV1 p).callables =
      .ok simpleClosureMembersV1 := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact invariantClosureDagPhases_simpleClosure p
  · exact (validateInvariantClosurePostDagCanonicalTwoV1
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName)
      simpleClosureBlockV1 (by rfl) (by rfl) (by rfl) (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalTwoV1
      (simpleClosureViewCallableV1 p.viewName)
      (simpleClosureInvCallableV1 p.invName)
      simpleClosureBlockV1 (by rfl) (by rfl) (by rfl) (by rfl)).2

theorem invariantFuelPhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateInvariantFuelPhasesV1
      (materializeSimpleClosureDataV1 p).callables
      simpleClosureMembersV1 = .ok () := by
  apply validateInvariantFuelCanonicalTwoV1
  · rfl
  · simp [materializeSimpleClosureDataV1, simpleClosureViewCallableV1,
      simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1]
    rfl
  · rfl
  · simp [materializeSimpleClosureDataV1, simpleClosureViewCallableV1,
      simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1]
    rfl
  · simp [materializeSimpleClosureDataV1, simpleClosureViewCallableV1,
      simpleClosureInvCallableV1, simpleClosureBlockV1, simpleClosureLitTrueV1]
    rfl

theorem cfgInvariantPhases_simpleClosure (p : SimpleClosureParamsV1) :
    validateCfgInvariantPhasesV1 (materializeSimpleClosureDataV1 p) = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok
    (materializeSimpleClosureDataV1 p) simpleClosureMembersV1
  · exact genericCfgPhases_simpleClosure p
  · exact invariantClosurePhases_simpleClosure p
  · exact invariantFuelPhases_simpleClosure p

/-! ### Phase: requirements + empty ContextRead/Commit -/

theorem programRequirementsStructure_simpleClosure (p : SimpleClosureParamsV1) :
    validateProgramRequirementsStructure
      (materializeSimpleClosureDataV1 p).requirements = .ok () := by
  change validateProgramRequirementsStructure {
    items := #[{
      id := "value.bool"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2ValueBoolDigestBytesV1
      }
      predicates := #[]
    }]
  } = .ok ()
  exact validateProgramRequirementsStructure_singleton_value_bool_eq_ok
    s2RequirementVersionV1
    { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 }

theorem contextReadRequirements_simpleClosure (p : SimpleClosureParamsV1) :
    validateContextReadRequirementsV1 (materializeSimpleClosureDataV1 p) =
      .ok () := by
  rfl

theorem commitRequirements_simpleClosure (p : SimpleClosureParamsV1) :
    validateCommitRequirementsV1 (materializeSimpleClosureDataV1 p) = .ok () := by
  rfl

/-! ### Full structure composition -/

/-- B-SC-STRUCT: every production structure phase closes for any legal
    name/module-parameterized simple-closure materialization. -/
theorem structure_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) =
      .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
    (materializeSimpleClosureDataV1 p)
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 4)
  · exact structurePrelude_of_legal p legal
  · exact typesStructure_simpleClosure p
  · exact typeKeyPhases_simpleClosure p
  · exact namedTypeNames_simpleClosure p
  · exact constantsValueBytes_simpleClosure p
  · exact callablesValueBytes_simpleClosure p
  · exact constantNames_simpleClosure p
  · exact logicalStateNames_simpleClosure p
  · exact eventNames_simpleClosure p
  · exact errorNames_simpleClosure p
  · exact interfaceFieldNames_simpleClosure p
  · exact callableSignatures_of_legal p legal
  · exact invariantDeclarationJoin_simpleClosure p
  · exact declarationIdentifierNames_of_legal p legal
  · exact cfgInvariantPhases_simpleClosure p
  · exact programRequirementsStructure_simpleClosure p
  · exact contextReadRequirements_simpleClosure p
  · exact commitRequirements_simpleClosure p

/-- Alias with the exact statement demanded by B-SC-STRUCT. -/
theorem validateSemanticProgramStructureV1_materialize_eq_ok_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) =
      .ok () :=
  structure_of_legal p legal

/-! ### QN identifier coverage (for elaborator / encode readiness) -/

/-- Head + every tail component under a legal witness pass the shared
    identifier authority (structure only needs size ≥ 2; encode later needs
    full NFC/grammar). -/
theorem qnComponents_identifierOk_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateIdentifierComponent p.qnHead = .ok () ∧
      (∀ (i : Nat) (hi : i < p.qnTail.size),
        validateIdentifierComponent p.qnTail[i] = .ok ()) :=
  ⟨legal.hqnHead, legal.hqnTail⟩

/-- View and invariant names under a legal witness pass the shared identifier
    authority (consumed by declaration-name structure phase). -/
theorem viewInv_identifierOk_of_legal (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p) :
    validateIdentifierComponent p.viewName = .ok () ∧
      validateIdentifierComponent p.invName = .ok () :=
  ⟨legal.hview, legal.hinv⟩

end ProofForgeV2.Semantic.SimpleClosureStructureCertV1

/-!
  ## B-SC-STRUCT status

  Closed: parametric
  `validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 p) = .ok ()`
  for all `SimpleClosureParamsLegalV1 p`.

  Remaining product-positive blockers (unchanged):
    B-SC-ENC / B-SC-DEC / B-SC-ELAB-THM / B-SC-PRODUCT
-/
