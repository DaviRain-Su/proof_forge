/-
  Tests.Semantic.ProofedCertV1 — Normalize literal-true simple-closure certificate
  for the elaborator-generated Proofed inline proof subject.

  Goal: closed `ProofedProof.safe : Proofed.Proof.safe` via production
  encode/decode witnesses + literal-true runner. No axiom/sorry/native_decide/
  ofReduceBool/second model.
-/
import Tests.Language.InlineProofAuthoringV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

namespace Tests.Semantic.ProofedCertV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

/-! ### Exact Normalize data (matches product lower+encode for Proofed) -/

def qn : QualifiedName :=
  { components := ⟨"Tests", #["Language", "InlineProofAuthoringV1", "Proofed"]⟩ }

def boolT : TypeDeclV1 := { id := 0, name := none, shape := .bool }
def u64T : TypeDeclV1 := { id := 1, name := none, shape := .uint 64 }

def litTrue : InstructionV1 :=
  { result := some { valueId := 0, typeId := 0 }, op := .literal 0 (encodeU8 1) }

def singleBlock : BlockV1 :=
  { id := 0, params := #[], instructions := #[litTrue], terminator := .return_ (some 0) }

def viewC : CallableV1 := {
  id := 0, kind := .view, name := some "alive", params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0, blocks := #[singleBlock]
  loopBounds := #[], invariantSteps := none
}

def invC : CallableV1 := {
  id := 1, kind := .invariant, name := some "safe", params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0, blocks := #[singleBlock]
  loopBounds := #[], invariantSteps := some 3
}

/-- Engineering digest for closed S2 `value.bool`. Transparent precomputed
    spine (exact `s2ValueBoolDigestBytesV1`) so encode/decode certificates
    can join by definitional equality without reducing SHA. -/
private def boolReqDigest : Digest := {
  algorithm := .sha256
  bytes := s2ValueBoolDigestBytesV1
}

/-- Closed singleton `value.bool` row used by the Normalize simple-closure
    carrier. Id/version/predicates are definitionally fixed for structure. -/
def boolReq : RequirementRequestV1 := {
  id := "value.bool"
  version := s2RequirementVersionV1
  digest := boolReqDigest
  predicates := #[]
}

def proofedData : SemanticProgramDataV1 := {
  qualifiedName := qn
  types := #[boolT, u64T]
  constants := #[]
  logicalState := #[]
  events := #[]
  errors := #[]
  callables := #[viewC, invC]
  invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  requirements := { items := #[boolReq] }
}

/-- Product bytes are the elaborator spine (sole product identity). -/
def proofedBytes : ByteArray := Proofed.Proof.subjectBytesV1

theorem subjectBytes_def :
    Proofed.Proof.subjectBytesV1 = proofedBytes := rfl

theorem subjectProgram_def :
    Proofed.Proof.subjectProgramV1 = ⟨proofedBytes⟩ := rfl

/-! ### Structure phases -/

theorem structurePrelude_proofed :
    validateSemanticProgramStructurePreludeV1 proofedData = .ok () := by
  have hqn : 2 ≤
      ({ head := "Tests", tail := #["Language", "InlineProofAuthoringV1", "Proofed"] } :
        NonEmptyArray String).toArray.size := by
    decide
  simp [validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    validateProgramQualifiedNameShapeV1, proofedData, qn, boolT, u64T,
    viewC, invC, singleBlock, litTrue, Pure.pure, Except.pure, Bind.bind, Except.bind,
    checkTypeShapeRefs, checkTypeIdInRange, checkCallableIdInRange, checkIdEqualsIndex,
    hqn]

theorem typesStructure_proofed :
    validateTypesStructureV1 proofedData.types = .ok () := by
  simp [validateTypesStructureV1, validateTypeDeclShapeV1, validateTypeDeclNamedRuleV1,
    proofedData, boolT, u64T, legalIntegerWidthV1_64, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

theorem typeKeyNamedPrefix_proofed :
    validateNamedPrefixRankV1 proofedData.types = .ok () := by
  simp [validateNamedPrefixRankV1, proofedData, boolT, u64T, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

private def boolTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private def uint64TypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private theorem encodeTypeShape_bool_proofed :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytes := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

/-- UInt64 TypeShape production encoding (tag + width u16le 64). -/
private theorem encodeTypeShape_uint64_proofed :
    encodeTypeShapeV1 (.uint 64) = .ok uint64TypeShapeBytes := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok uint64TypeShapeBytes
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem compare_bool_uint64_proofed :
    compareByteArrayLex boolTypeShapeBytes uint64TypeShapeBytes = .lt := by
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

theorem typeKeyPrimitiveLeaf_proofed :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 proofedData.types = .ok () := by
  simp [validatePrimitiveAnonymousTypeKeyUniquenessV1, proofedData, boolT, u64T,
    encodeTypeShape_bool_proofed, encodeTypeShape_uint64_proofed,
    compare_bool_uint64_proofed, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem typeKeyRecursiveAnonymous_proofed :
    validateRecursiveAnonymousTypeKeyUniquenessV1 proofedData.types = .ok () := by
  simp [validateRecursiveAnonymousTypeKeyUniquenessV1, proofedData, boolT, u64T,
    Pure.pure, Except.pure]

theorem typeKeyNamedBodyCycle_proofed :
    validateNamedBodyOptionCycleLegalityV1 proofedData.types = .ok () := by
  simp [validateNamedBodyOptionCycleLegalityV1, proofedData, boolT, u64T,
    Pure.pure, Except.pure]

theorem typeKeyPhases_proofed :
    validateTypeKeyPhasesV1 proofedData.types = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · exact typeKeyNamedPrefix_proofed
  · exact typeKeyPrimitiveLeaf_proofed
  · exact typeKeyRecursiveAnonymous_proofed
  · exact typeKeyNamedBodyCycle_proofed

theorem namedTypeNames_proofed :
    validateNamedTypeNameUniquenessV1 proofedData.types = .ok () := by
  simp [validateNamedTypeNameUniquenessV1, checkUniqueDeclarationNamesV1, proofedData,
    boolT, u64T, Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem constantsValueBytes_proofed :
    validateConstantsValueBytesV1 proofedData.types proofedData.constants
      maxCanonicalProgramBytes = .ok maxCanonicalProgramBytes := by
  simp [validateConstantsValueBytesV1, proofedData, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

theorem callablesValueBytes_proofed :
    validateCallablesValueBytesV1 proofedData.types proofedData.callables
      maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 4) := by
  have henc : encodeU8 1 = ByteArray.mk #[1] := rfl
  have htrue :
      validateOpValueBytesV1 proofedData.types
        (.literal 0 (ByteArray.mk #[1])) maxCanonicalProgramBytes =
        .ok (maxCanonicalProgramBytes - 2) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok proofedData.types 0 boolT 1
    · rfl
    · rfl
    · exact Or.inr rfl
    · decide
  have htrue2 :
      validateOpValueBytesV1 proofedData.types
        (.literal 0 (ByteArray.mk #[1])) (maxCanonicalProgramBytes - 2) =
        .ok (maxCanonicalProgramBytes - 4) := by
    apply validateOpValueBytesV1_literal_bool_eq_ok proofedData.types 0 boolT 1
    · rfl
    · rfl
    · exact Or.inr rfl
    · decide
  have hop0 :
      validateOpValueBytesV1 proofedData.types litTrue.op maxCanonicalProgramBytes =
        .ok (maxCanonicalProgramBytes - 2) := by
    simp [litTrue, henc, htrue]
  have hop1 :
      validateOpValueBytesV1 proofedData.types litTrue.op (maxCanonicalProgramBytes - 2) =
        .ok (maxCanonicalProgramBytes - 4) := by
    simp [litTrue, henc, htrue2]
  have hterm (b : Nat) :
      validateTerminatorValueBytesV1 proofedData.types singleBlock.terminator b = .ok b := by
    simp [singleBlock, validateTerminatorValueBytesV1, Pure.pure, Except.pure]
  change validateCallablesValueBytesV1 proofedData.types #[viewC, invC]
    maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 4)
  apply validateCallablesValueBytesV1_two_single_op (types := proofedData.types)
    viewC invC singleBlock singleBlock litTrue litTrue
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 2) (maxCanonicalProgramBytes - 4)
  · rfl
  · rfl
  · rfl
  · rfl
  · exact hterm (maxCanonicalProgramBytes - 2)
  · exact hterm (maxCanonicalProgramBytes - 4)
  · exact hop0
  · exact hop1

theorem constantNames_proofed :
    validateConstantNameUniquenessV1 proofedData.constants = .ok () := by
  simp [validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1, proofedData,
    Pure.pure, Except.pure]

theorem logicalStateNames_proofed :
    validateLogicalStateNameUniquenessV1 proofedData.logicalState = .ok () := by
  simp [validateLogicalStateNameUniquenessV1, checkUniqueDeclarationNamesV1, proofedData,
    Pure.pure, Except.pure]

theorem eventNames_proofed :
    validateEventNameUniquenessV1 proofedData.events = .ok () := by
  simp [validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1, proofedData,
    Pure.pure, Except.pure]

theorem errorNames_proofed :
    validateErrorNameUniquenessV1 proofedData.errors = .ok () := by
  simp [validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1, proofedData,
    Pure.pure, Except.pure]

theorem interfaceFieldNames_proofed :
    validateInterfaceFieldNameUniquenessV1 proofedData.events proofedData.errors =
      .ok () := by
  simp [validateInterfaceFieldNameUniquenessV1, proofedData, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- Bool true valueBytes are canonical for typeId 0 on `proofedData`. -/
theorem boolLiteralTrue_canonical :
    validateValueBytesV1 proofedData.types 0 (encodeU8 1) = .ok () := by
  simp [proofedData, boolT, u64T, encodeU8, validateValueBytesV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

/-! ### Callable signatures, InvariantDecl join, identifier names -/

/-- View + invariant kind/name uniqueness, entry/view presence, Bool-public
    invariant result, empty params/loops, non-closure view steps=none, and
    invariant root steps=some. -/
theorem callableSignatures_proofed :
    validateCallableSignaturePhasesV1 proofedData.types proofedData.callables =
      .ok () := by
  have hViewInit : ((.view : CallableKindV1) == .initializer) = false := by decide
  have hInvariantInit : ((.invariant : CallableKindV1) == .initializer) = false := by decide
  have hViewInvariant : ((.view : CallableKindV1) == .invariant) = false := by decide
  have hInvariantInvariant : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  have hPublicPublic : ((.public_ : VisibilityV1) == .public_) = true := by decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals simp [proofedData, boolT, u64T, viewC, invC, singleBlock, litTrue,
    validateCallableKindNamePresenceV1, validateCallableNameUniquenessV1,
    validateCallableParameterNameUniquenessV1, validateCallableEntryViewPresenceV1,
    validateInitializerCardinalityV1, validateInitializerResultShapeV1,
    validateInvariantResultShapeV1, validateInvariantParameterShapeV1,
    validateInvariantLoopBoundsShapeV1, validateNonClosureCallableInvariantStepsV1,
    validateInvariantRootStepsPresenceV1, hViewInit, hInvariantInit, hViewInvariant,
    hInvariantInvariant, hPublicPublic, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Single InvariantDecl joins the sole invariant callable (id 1, name "safe"). -/
theorem invariantDeclarationJoin_proofed :
    validateInvariantDeclarationJoinV1 proofedData.callables proofedData.invariants =
      .ok () := by
  have hViewInvariant : ((.view : CallableKindV1) == .invariant) = false := by decide
  have hInvariantInvariant : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  simp [validateInvariantDeclarationJoinV1, proofedData, viewC, invC, singleBlock,
    litTrue, hViewInvariant, hInvariantInvariant, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- Declaration/callable/invariant names pass the sole SPEC-COMMON identifier
    authority: "alive" (view) and "safe" (invariant + InvariantDecl). -/
theorem declarationIdentifierNames_proofed :
    validateDeclarationIdentifierNamesV1 proofedData = .ok () := by
  have identifierOk (name : String)
      (hcommon : validateIdentifierComponent name = .ok ()) :
      validateIdentifierNameV1 name = .ok () :=
    validateIdentifierNameV1_eq_ok_of_common name hcommon
  have halive : validateIdentifierNameV1 "alive" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "alive" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  have hsafe : validateIdentifierNameV1 "safe" = .ok () := by
    apply identifierOk
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [ProofForgeV2.Core.Unicode.requireNfc_eq_ok_of_isAscii "safe" (by decide),
      Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl
  simp [validateDeclarationIdentifierNamesV1, validateTypeShapeIdentifierNamesV1,
    proofedData, boolT, u64T, viewC, invC, singleBlock, litTrue, halive, hsafe,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-! ### Two-callable literal-true CFG -/

private theorem literalTrue_opUses_empty :
    opValueUses litTrue.op = #[] := by
  simp [litTrue, opValueUses]

/-- View `alive`: single Bool-true literal return block. -/
theorem viewCfg_proofed :
    validateCallableCfgShape viewC proofedData.types.size proofedData.types
      proofedData = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    viewC proofedData.types.size proofedData.types proofedData #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases viewC #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok viewC litTrue
      · rfl
      · exact literalTrue_opUses_empty
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok viewC litTrue
      · rfl
      · exact literalTrue_opUses_empty
  · rfl

/-- Invariant `safe`: same single Bool-true literal return block. -/
theorem invCfg_proofed :
    validateCallableCfgShape invC proofedData.types.size proofedData.types
      proofedData = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    invC proofedData.types.size proofedData.types proofedData #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases invC #[true] #[(0, 0)]
    · rfl
    · rfl
    · apply checkValueIdUsesExist_single_local_return_eq_ok invC litTrue
      · rfl
      · exact literalTrue_opUses_empty
    · apply validateCallableDominanceOfUse_single_local_return_eq_ok invC litTrue
      · rfl
      · exact literalTrue_opUses_empty
  · rfl

/-- Generic CFG phase: both callables + empty ContextRead catalog. -/
theorem genericCfgPhases_proofed :
    validateGenericCfgPhasesV1 proofedData = .ok () := by
  apply validateGenericCfgPhasesV1_two_eq_ok proofedData viewC invC
  · rfl
  · exact viewCfg_proofed
  · exact invCfg_proofed
  · rfl

/-! ### Invariant closure membership #[false,true], DAG, no-backedge, fuel 3 -/

def closureMembers : Array Bool := #[false, true]

theorem computeInvariantClosureMembership_proofed :
    invariantClosureMembershipResultV1 proofedData.callables = .ok closureMembers := by
  simp [invariantClosureMembershipResultV1, closureMembers, proofedData, viewC,
    invC, singleBlock, litTrue]
  rfl

theorem invariantClosureMembershipPhases_proofed :
    validateInvariantClosureMembershipPhasesV1 proofedData.callables =
      .ok closureMembers := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · rfl
  · exact computeInvariantClosureMembership_proofed
  · apply validatePureFnInvariantClosureMembershipTwoV1 viewC invC <;> rfl

theorem invariantClosureDagPhases_proofed :
    validateInvariantClosureDagPhasesV1 proofedData.callables =
      .ok closureMembers := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact invariantClosureMembershipPhases_proofed
  · apply validateInvariantClosureDagCanonicalTwoV1
    · rfl
    · rfl
    · rfl

theorem invariantClosurePhases_proofed :
    validateInvariantClosurePhasesV1 proofedData.callables =
      .ok closureMembers := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact invariantClosureDagPhases_proofed
  · exact (validateInvariantClosurePostDagCanonicalTwoV1
      viewC invC singleBlock (by rfl) (by rfl) (by rfl) (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalTwoV1
      viewC invC singleBlock (by rfl) (by rfl) (by rfl) (by rfl)).2

theorem validateInvariantFuelPhases_proofed :
    validateInvariantFuelPhasesV1 proofedData.callables closureMembers = .ok () := by
  apply validateInvariantFuelCanonicalTwoV1
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

theorem validateCfgInvariantPhases_proofed :
    validateCfgInvariantPhasesV1 proofedData = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok proofedData closureMembers
  · exact genericCfgPhases_proofed
  · exact invariantClosurePhases_proofed
  · exact validateInvariantFuelPhases_proofed

/-! ### Requirements: value.bool row; empty ContextRead/Commit -/

/-- Single S2 `value.bool` catalog row (empty predicates) passes the production
    requirements structure gate. -/
theorem programRequirementsStructure_proofed :
    validateProgramRequirementsStructure proofedData.requirements = .ok () := by
  change validateProgramRequirementsStructure {
    items := #[{
      id := "value.bool"
      version := s2RequirementVersionV1
      digest := boolReqDigest
      predicates := #[]
    }]
  } = .ok ()
  exact validateProgramRequirementsStructure_singleton_value_bool_eq_ok
    s2RequirementVersionV1 boolReqDigest

theorem contextReadRequirements_proofed :
    validateContextReadRequirementsV1 proofedData = .ok () := by
  rfl

theorem commitRequirements_proofed :
    validateCommitRequirementsV1 proofedData = .ok () := by
  rfl

/-! ### Full structure composition -/

/-- Every production structure phase closes for the Proofed simple carrier. -/
theorem structure_proofed :
    validateSemanticProgramStructureV1 proofedData = .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases proofedData
    maxCanonicalProgramBytes (maxCanonicalProgramBytes - 4)
  · exact structurePrelude_proofed
  · exact typesStructure_proofed
  · exact typeKeyPhases_proofed
  · exact namedTypeNames_proofed
  · exact constantsValueBytes_proofed
  · exact callablesValueBytes_proofed
  · exact constantNames_proofed
  · exact logicalStateNames_proofed
  · exact eventNames_proofed
  · exact errorNames_proofed
  · exact interfaceFieldNames_proofed
  · exact callableSignatures_proofed
  · exact invariantDeclarationJoin_proofed
  · exact declarationIdentifierNames_proofed
  · exact validateCfgInvariantPhases_proofed
  · exact programRequirementsStructure_proofed
  · exact contextReadRequirements_proofed
  · exact commitRequirements_proofed

private def proofedProgram : SemanticProgramV1 := { canonicalBytes := proofedBytes }

/-- Evaluator half for ordinal 0 on any conforming state, once validation of
    `proofedData` is available. -/
theorem eval_safe_of_validate
    (hvalidate : validateSemanticProgramV1 proofedProgram = .ok proofedData)
    (st : LogicalStateV1)
    (hconforms : StateConformsV1 proofedProgram st) :
    evalInvariantV1 proofedProgram 0 st = .returnedTrue := by
  obtain ⟨hinitialized, overlay, hdecodeState⟩ :=
    stateConformsV1_elim_of_validate_eq_ok proofedProgram proofedData st
      hvalidate hconforms
  have hrun : runInvariantCallableV1 proofedData 1 st = .returnedTrue := by
    apply runInvariantCallableV1_eq_returnedTrue_of_single_nullary_literal_true
      proofedData st overlay 1 0 (some "safe") .public_ none
      hinitialized hdecodeState
    · rfl
    · rfl
    · exact boolLiteralTrue_canonical
  apply evalInvariantV1_eq_of_validated_selection
    proofedProgram proofedData 0 { id := 0, name := "safe", callableId := 1 }
    st overlay .returnedTrue hvalidate hinitialized hdecodeState
  · rfl
  · exact hrun

/-- Closed theorem once carrier validation is established. -/
theorem invariantTheorem_proofed_of_validate
    (hvalidate : validateSemanticProgramV1 proofedProgram = .ok proofedData) :
    InvariantTheoremV1 proofedProgram 0 := by
  apply invariantTheoremV1_of_validate_eq_ok proofedProgram proofedData 0 hvalidate
  · change 0 < proofedData.invariants.size
    decide
  · intro st hconforms
    exact eval_safe_of_validate hvalidate st hconforms

/-- Ordinal mutation negative (OOR). -/
theorem not_safe_ordinal_1_of_validate
    (hvalidate : validateSemanticProgramV1 proofedProgram = .ok proofedData) :
    ¬ InvariantTheoremV1 proofedProgram 1 :=
  not_invariantTheoremV1_of_oob_ordinal proofedProgram proofedData 1 hvalidate
    (by decide)

/-- Byte-mutation negative: any mutated carrier that still transport-decodes to
    `proofedData` but differs in bytes is nonCanonical. -/
theorem validate_error_on_mutated_bytes_of_encode
    (bytes mutated : ByteArray)
    (hencode : encodeSemanticProgramDataV1 proofedData = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 mutated = .ok proofedData)
    (hmismatch : (bytes == mutated) = false) :
    validateSemanticProgramV1 { canonicalBytes := mutated } = .error .nonCanonical :=
  validateSemanticProgramV1_eq_error_of_encode_decode_mismatch proofedData bytes
    mutated hencode hdecode hmismatch

end Tests.Semantic.ProofedCertV1

/-! ### Public theorem name expected by `proof safe using ProofedProof.safe` -/

namespace ProofedProof

open Tests.Semantic.ProofedCertV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

/-- Composition: subject validation ⇒ exact inline obligation. -/
theorem safe_of_validate
    (hvalidate :
      validateSemanticProgramV1 Proofed.Proof.subjectProgramV1 = .ok proofedData) :
    Proofed.Proof.safe := by
  change InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0
  have hprog : Proofed.Proof.subjectProgramV1 = proofedProgram := by
    simp [proofedProgram, proofedBytes, subjectProgram_def]
  rw [hprog]
  exact invariantTheorem_proofed_of_validate (hprog ▸ hvalidate)

end ProofedProof
