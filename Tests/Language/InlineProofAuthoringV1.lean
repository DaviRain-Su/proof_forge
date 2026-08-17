import ProofForgeV2.Language.ProgramElaborationV1
import ProofForgeV2.Semantic.FieldComparisonPreservationV1
import ProofForgeV2.Semantic.FieldComparisonSubjectV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1

open ProofForgeV2.Language
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Lean
open Lean.Elab.Command

namespace Tests.Language.InlineProofAuthoringV1

#check ProofForgeV2.Semantic.StateModelV1.encodeBool_boolOfDecodedStateValueV1

program Proofed where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using ProofedProof.safe

theorem ProofedProof.safe : Proofed.Proof.safe := by
  exact Proofed.Proof.generatedSafeV1

#check Proofed.Proof.subjectProgramV1
#check Proofed.Proof.safe
#check Proofed.Model.State
#check Proofed.Model.encodeState
#check Proofed.Model.decodeState
#check Proofed.Model.decode_encode
#check Proofed.Model.encode_injective_of_eq_ok
#check Proofed.Model.decode_existsUnique_of_conforms
#check Proofed.Model.encode_decode_of_conforms
#check Proofed.Model.conforms_of_encode
#check Proofed.Model.conforms_iff_exists_encode

example : Proofed.Proof.safe =
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := rfl

example : Proofed.Model.State = Unit := rfl

example : Proofed.Model.encodeState () = .ok {
    initialized := true
    canonicalValues := ByteArray.empty
  } := rfl

example
    (hvalidate :
      validateSemanticProgramV1 Proofed.Proof.subjectProgramV1 =
        .ok Proofed.Proof.subjectDataV1) :
    ∃ typedState : Proofed.Model.State,
      Proofed.Model.decodeState {
        initialized := true
        canonicalValues := ByteArray.empty
      } = .ok typedState ∧
      Proofed.Model.encodeState typedState = .ok {
        initialized := true
        canonicalValues := ByteArray.empty
      } := by
  apply Proofed.Model.encode_decode_of_conforms _ hvalidate
  apply Proofed.Model.conforms_of_encode () _ hvalidate
  rfl

#check Proofed.Proof.subjectBytesV1
-- Structured subject data (mig-a3-elab): preferred author surface; encode of
-- this spine must recover product subject bytes (runtime check in `run`).
#check Proofed.Proof.subjectDataV1
#check Proofed.Proof.subjectRootGatesOkV1
#check Proofed.Proof.subjectStructureOkV1
#check Proofed.Proof.subjectValidationOkV1

example :
    validateProgramQualifiedNameShapeV1
          Proofed.Proof.subjectDataV1.qualifiedName = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.types.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.constants.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.logicalState.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.events.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.errors.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.callables.size = .ok () ∧
      checkTableSize Proofed.Proof.subjectDataV1.invariants.size = .ok () :=
  Proofed.Proof.subjectRootGatesOkV1

example :
    validateSemanticProgramStructureV1 Proofed.Proof.subjectDataV1 = .ok () :=
  Proofed.Proof.subjectStructureOkV1

example :
    validateSemanticProgramV1 Proofed.Proof.subjectProgramV1 =
      .ok Proofed.Proof.subjectDataV1 :=
  Proofed.Proof.subjectValidationOkV1

-- Name/module-parameterized certificate AST emitted for the literal-true
-- simple-closure family (foundation for product-positive cert generation).
#check Proofed.Proof.simpleClosureParamsV1
#check Proofed.Proof.simpleClosureDataV1

-- B-SC-ELAB-THM close: concrete Legal witness, compatibility bridge, and
-- premise-free generated theorem consumed by the ordinary adjacent theorem.
#check Proofed.Proof.simpleClosureQnTailLegalV1
#check Proofed.Proof.simpleClosureParamsLegalV1
#check Proofed.Proof.generatedSafeV1Name
#check Proofed.Proof.generatedSafeV1_of_wireTrace
#check Proofed.Proof.generatedSafeV1
#check ProofedProof.safe

example : Proofed.Proof.generatedSafeV1Name = "generatedSafeV1" := rfl

example : Proofed.Proof.safe := Proofed.Proof.generatedSafeV1
example : Proofed.Proof.safe := ProofedProof.safe

example : generatedSimpleClosureTheoremNameV1 "safe" = "generatedSafeV1" := rfl
example : generatedSimpleClosureTheoremNameV1 "balance" = "generatedBalanceV1" := rfl
example : generatedSimpleClosureTheoremBridgeNameV1 "safe" =
    "generatedSafeV1_of_wireTrace" := rfl
example : generatedSimpleClosureTheoremNameDefV1 "safe" =
    "generatedSafeV1Name" := rfl

program PreservingSurface where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using PreservingSurfaceProof.holds
  proof safe preserving using PreservingSurfaceProof.safe

theorem PreservingSurfaceProof.holds : PreservingSurface.Proof.safe := by
  exact PreservingSurface.Proof.generatedSafeV1

theorem PreservingSurfaceProof.safe :
    PreservingSurface.ProofPreserving.safe := by
  have hvalidate :
      validateSemanticProgramV1 PreservingSurface.Proof.subjectProgramV1 =
        .ok PreservingSurface.Proof.subjectDataV1 :=
    PreservingSurface.Proof.subjectValidationOkV1
  have hadmission :
      validateReferenceProgramDataAdmissionV1
          PreservingSurface.Proof.subjectDataV1 = .ok () := by
    rfl
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks
      PreservingSurface.Proof.subjectProgramV1
      PreservingSurface.Proof.subjectDataV1 hvalidate hadmission
  have hinvariant :
      InvariantTheoremV1 PreservingSurface.Proof.subjectProgramV1 0 :=
    PreservingSurface.Proof.generatedSafeV1
  have hnoInitializerAny :
      PreservingSurface.Proof.subjectDataV1.callables.any
          (fun callable => callable.kind == .initializer) = false := by
    simp [PreservingSurface.Proof.subjectDataV1] <;> decide
  have hemptyState :
      PreservingSurface.Proof.subjectDataV1.logicalState = #[] := by
    simp [PreservingSurface.Proof.subjectDataV1]
  have hreturned :
      ∀ (callableId : CallableIdV1) (callable : CallableV1),
        PreservationReturnedCallableV1
          PreservingSurface.Proof.subjectProgramV1 0 admitted callableId
            callable := by
    intro callableId callable pre invocation responses vault overlay context
      isInitializer postState value effects _hcallableId hconforms _heval
      _hgate hstep
    have hinitialized : pre.initialized = true :=
      (stateConformsV1_elim_of_validate_eq_ok
        PreservingSurface.Proof.subjectProgramV1
        PreservingSurface.Proof.subjectDataV1 pre hvalidate hconforms).1
    apply hinvariant.2 postState
    exact
      stepReferenceSliceV1_returned_stateConformsV1_of_initialized
        PreservingSurface.Proof.subjectProgramV1 admitted pre postState invocation
        responses vault value effects hadmit hinitialized hstep
  have htypedReturned :
      PreservingSurface.ProofPreserving.safe.callable0TypedReturnedV1 admitted
        hadmit := by
    intro pre post value effects invocation responses vault _hcallableId
      hpreInvariant _htransition
    have hstate : post = pre := Subsingleton.elim post pre
    simpa [hstate] using hpreInvariant
  apply
    PreservingSurface.ProofPreserving.safe.ofRowObligationsV1 admitted hvalidate
      hadmit
  · apply
      ProofForgeV2.Semantic.PreservationPackagingV1.preservationBaseV1_of_noInitializerV1
    · exact
        not_hasInitializerV1_of_validate_and_any_eq_false
          PreservingSurface.Proof.subjectProgramV1
          PreservingSurface.Proof.subjectDataV1 hvalidate hnoInitializerAny
    · let initial : LogicalStateV1 := {
        initialized := true
        canonicalValues := ByteArray.empty
      }
      have hinitial :
          initialLogicalStateV1 PreservingSurface.Proof.subjectProgramV1 =
            .ok initial := by
        simpa [initial] using
          initialLogicalStateV1_empty_no_initializer_eq_ok
            PreservingSurface.Proof.subjectProgramV1
            PreservingSurface.Proof.subjectDataV1 hvalidate hemptyState
              hnoInitializerAny
      have hconforms :
          StateConformsV1 PreservingSurface.Proof.subjectProgramV1 initial := by
        apply stateConformsV1_intro_of_validate_eq_ok
          PreservingSurface.Proof.subjectProgramV1
          PreservingSurface.Proof.subjectDataV1 initial #[] hvalidate rfl
        rfl
      exact ⟨initial, hinitial, hconforms, hinvariant.2 initial hconforms⟩
  · exact
      PreservingSurface.ProofPreserving.safe.callable0ReturnedV1_of_typed
        admitted hvalidate hadmit htypedReturned
  · exact hreturned 1
      (PreservingSurface.Proof.subjectDataV1.callables[1]'(by decide))

#check PreservingSurface.Proof.subjectProgramV1
#check PreservingSurface.Proof.subjectStructureOkV1
#check PreservingSurface.Proof.subjectValidationOkV1
#check PreservingSurface.Proof.generatedSafeV1
#check PreservingSurface.ProofPreserving.safe
#check PreservingSurface.ProofPreserving.safe.BaseV1
#check PreservingSurface.ProofPreserving.safe.WithInitializerBaseV1
#check PreservingSurface.ProofPreserving.safe.NoInitializerBaseV1
#check PreservingSurface.ProofPreserving.safe.ReturnedCallablesV1
#check PreservingSurface.ProofPreserving.safe.ReturnedRowsV1
#check PreservingSurface.ProofPreserving.safe.callable0ReturnedV1
#check PreservingSurface.ProofPreserving.safe.callable1ReturnedV1
#check PreservingSurface.ProofPreserving.safe.callable0TypedReturnedV1
#check PreservingSurface.ProofPreserving.safe.callable0ReturnedV1_of_typed
#check PreservingSurface.ProofPreserving.safe.returnedRowsV1
#check PreservingSurface.ProofPreserving.safe.returnedCallablesOfRowsV1
#check PreservingSurface.ProofPreserving.safe.ofCallableObligationsV1
#check PreservingSurface.ProofPreserving.safe.ofRowObligationsV1

example :
    validateSemanticProgramStructureV1
        PreservingSurface.Proof.subjectDataV1 = .ok () :=
  PreservingSurface.Proof.subjectStructureOkV1

example :
    validateSemanticProgramV1 PreservingSurface.Proof.subjectProgramV1 =
      .ok PreservingSurface.Proof.subjectDataV1 :=
  PreservingSurface.Proof.subjectValidationOkV1

example : PreservingSurface.ProofPreserving.safe =
    ProofForgeV2.Semantic.PreservationABI.PreservationTheoremV1
      PreservingSurface.Proof.subjectProgramV1 0 := rfl

example (admitted : AdmittedReferenceSliceV1) :
    PreservingSurface.ProofPreserving.safe.callable0ReturnedV1 admitted =
      PreservationReturnedCallableV1
        PreservingSurface.Proof.subjectProgramV1 0 admitted 0
        (PreservingSurface.Proof.subjectDataV1.callables[0]'(by decide)) := rfl

example (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1
      PreservingSurface.Proof.subjectProgramV1 = .ok admitted)
    (hbase : PreservingSurface.ProofPreserving.safe.BaseV1 admitted)
    (hreturned :
      PreservingSurface.ProofPreserving.safe.ReturnedCallablesV1 admitted) :
    PreservingSurface.ProofPreserving.safe :=
  PreservingSurface.ProofPreserving.safe.ofCallableObligationsV1 admitted
    PreservingSurface.Proof.subjectValidationOkV1 hadmit hbase hreturned

example (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1
      PreservingSurface.Proof.subjectProgramV1 = .ok admitted)
    (hbase : PreservingSurface.ProofPreserving.safe.BaseV1 admitted)
    (hcallable0 :
      PreservingSurface.ProofPreserving.safe.callable0ReturnedV1 admitted)
    (hcallable1 :
      PreservingSurface.ProofPreserving.safe.callable1ReturnedV1 admitted) :
    PreservingSurface.ProofPreserving.safe :=
  PreservingSurface.ProofPreserving.safe.ofRowObligationsV1 admitted
    PreservingSurface.Proof.subjectValidationOkV1 hadmit hbase hcallable0
      hcallable1

program DualKindSurface where
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using DualKindSurfaceProof.holds
  proof safe preserving using DualKindSurfaceProof.keeps

#check DualKindSurface.Proof.subjectProgramV1
#check DualKindSurface.Proof.safe
#check DualKindSurface.ProofPreserving.safe
#check DualKindSurface.Proof.generatedSafeV1

example : DualKindSurface.ProofPreserving.safe =
    ProofForgeV2.Semantic.PreservationABI.PreservationTheoremV1
      DualKindSurface.Proof.subjectProgramV1 0 := rfl

program TypedStateSurface where
  state count : UInt64
  state total : UInt64
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using TypedStateSurfaceProof.safe

#check TypedStateSurface.Model.State
#check TypedStateSurface.Model.State.count
#check TypedStateSurface.Model.State.total
#check TypedStateSurface.Model.encodeState
#check TypedStateSurface.Model.encode_exists
#check TypedStateSurface.Model.decodeState
#check TypedStateSurface.Model.decode_encode
#check TypedStateSurface.Model.encode_injective_of_eq_ok
#check TypedStateSurface.Model.decode_existsUnique_of_conforms
#check TypedStateSurface.Model.encode_decode_of_conforms
#check TypedStateSurface.Model.conforms_of_encode
#check TypedStateSurface.Model.conforms_iff_exists_encode
#check TypedStateSurface.Model.safe
#check TypedStateSurface.Model.Invariant.safe_iff_eval

private def typedStateSampleV1 : TypedStateSurface.Model.State := {
  count := 7
  total := 11
}

private def typedStateLogicalV1 : LogicalStateV1 := {
  initialized := true
  canonicalValues :=
    encodeU32le 8 ++ encodeU64le 7 ++ encodeU32le 8 ++ encodeU64le 11
}

/-- Generated fields preserve StateId/source order in the production wire
    layout; no contract-specific codec participates in this equality. -/
example : TypedStateSurface.Model.encodeState typedStateSampleV1 =
    .ok typedStateLogicalV1 := by
  rfl

/-- The generated author-facing theorem is the generic production-codec
    inverse specialized to this exact lowered subject. -/
example : TypedStateSurface.Model.decodeState typedStateLogicalV1 =
    .ok typedStateSampleV1 := by
  apply TypedStateSurface.Model.decode_encode
  rfl

example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    StateConformsV1 TypedStateSurface.Proof.subjectProgramV1 typedStateLogicalV1 := by
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

/-- Production conformance is sufficient for existence and uniqueness of the
    generated typed projection; no contract-local decoder premise is needed. -/
example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    ∃ typedState : TypedStateSurface.Model.State,
      TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok typedState ∧
        ∀ other : TypedStateSurface.Model.State,
          TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok other →
            typedState = other := by
  apply TypedStateSurface.Model.decode_existsUnique_of_conforms
    typedStateLogicalV1 hvalidate
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

/-- Production conformance also selects a typed projection whose generated
    encoding is byte-for-byte the original production logical state. -/
example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    ∃ typedState : TypedStateSurface.Model.State,
      TypedStateSurface.Model.decodeState typedStateLogicalV1 = .ok typedState ∧
        TypedStateSurface.Model.encodeState typedState =
          .ok typedStateLogicalV1 := by
  apply TypedStateSurface.Model.encode_decode_of_conforms
    typedStateLogicalV1 hvalidate
  apply TypedStateSurface.Model.conforms_of_encode typedStateSampleV1
    typedStateLogicalV1 hvalidate
  rfl

example
    (hvalidate :
      validateSemanticProgramV1 TypedStateSurface.Proof.subjectProgramV1 =
        .ok TypedStateSurface.Proof.subjectDataV1) :
    StateConformsV1 TypedStateSurface.Proof.subjectProgramV1 typedStateLogicalV1 ↔
      ∃ typedState : TypedStateSurface.Model.State,
        TypedStateSurface.Model.encodeState typedState =
          .ok typedStateLogicalV1 :=
  TypedStateSurface.Model.conforms_iff_exists_encode
    typedStateLogicalV1 hvalidate

private def typedStateUninitializedV1 : LogicalStateV1 :=
  { typedStateLogicalV1 with initialized := false }

example : TypedStateSurface.Model.decodeState typedStateUninitializedV1 =
    .error .nonCanonical := by
  rfl

/- Encoder totality concludes through the generated wrapper around the sole
   production codec. -/
example (typedState : TypedStateSurface.Model.State) :
    ∃ logicalState : LogicalStateV1,
      TypedStateSurface.Model.encodeState typedState =
        .ok logicalState :=
  TypedStateSurface.Model.encode_exists typedState

/-- The generated author predicate is definitionally only the exact production
    state encoder plus `evalInvariantV1` at the lowered invariant ordinal. -/
example (typedState : TypedStateSurface.Model.State) :
    TypedStateSurface.Model.safe typedState =
      TypedInvariantV1 TypedStateSurface.Model.encodeState
        TypedStateSurface.Proof.subjectProgramV1 0 typedState := rfl

/-- Once encoding fixes the logical carrier, the generated bridge is an exact
    equivalence with the sole production invariant evaluator. -/
example
    (typedState : TypedStateSurface.Model.State)
    (logicalState : LogicalStateV1)
    (hencode :
      TypedStateSurface.Model.encodeState typedState = .ok logicalState) :
    TypedStateSurface.Model.safe typedState ↔
      evalInvariantV1 TypedStateSurface.Proof.subjectProgramV1 0 logicalState =
        .returnedTrue :=
  TypedStateSurface.Model.Invariant.safe_iff_eval
    typedState logicalState hencode

/-- The generic typed predicate itself exposes the production encoder and
    evaluator directly; no generated invariant interpreter is hidden here. -/
example
    {State : Type}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (semanticProgram : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (typedState : State) :
    TypedInvariantV1 encodeState semanticProgram ordinal typedState ↔
      ∃ logicalState,
        encodeState typedState = .ok logicalState ∧
          evalInvariantV1 semanticProgram ordinal logicalState =
            .returnedTrue := by
  rfl

/-- Encoder failure cannot satisfy the predicate by choosing another logical
    state; the evaluator-backed projection is positive rather than vacuous. -/
example (semanticProgram : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) :
    ¬ TypedInvariantV1
      (fun _ : Unit => .error .nonCanonical) semanticProgram ordinal () := by
  simp [TypedInvariantV1]

/- The first ordinary mathematical invariant view is recognized from the
   exact lowered CFG. Nonzero state IDs and invariant ordinal ensure the
   emitter does not assume either table starts at the equality operands. -/
program TypedInvariantFieldEqualitySurface where
  state nonce : UInt64
  state reserves : UInt64
  state shares : UInt64
  view alive() : Bool do
    return true
  invariant primary : true
  invariant solvent : reserves == shares
  invariant nonsolvent : reserves != shares
  proof primary using TypedInvariantFieldEqualitySurfaceProof.primary
  proof solvent using TypedInvariantFieldEqualitySurfaceProof.solvent
  proof nonsolvent using TypedInvariantFieldEqualitySurfaceProof.nonsolvent

#check TypedInvariantFieldEqualitySurface.Model.solvent
#check TypedInvariantFieldEqualitySurface.Model.encode_exists
#check TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_eval
#check TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_fields
#check TypedInvariantFieldEqualitySurface.Model.Invariant.nonsolvent_iff_fields
#check TypedInvariantFieldEqualitySurface.Proof.subjectStructureOkV1
#check TypedInvariantFieldEqualitySurface.Proof.subjectValidationOkV1

/-- The generated subject is definitionally the parameterized production
    field-comparison family; no admission carrier supplies these fields. -/
theorem typedInvariantFieldEqualitySubject_subjectData_eq :
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
        "nonce" "reserves" "shares" "alive" "primary" "solvent"
        "nonsolvent" := rfl

/-- The actual generated subject now has a whole-program production-codec
    inversion package. Structure and full validation remain separate gates. -/
theorem typedInvariantFieldEqualitySubject_rootFieldInvertV1 :
    RootFieldInvertV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  exact
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
      "nonce" "reserves" "shares" "alive" "primary" "solvent"
      "nonsolvent" (by rfl) (by rfl) (by rfl) (by rfl)
      (by rfl) (by rfl) (by rfl)

/-- The actual generated subject passes the production generic CFG/SSA/typing
    phase; this does not bypass the later invariant closure/fuel phases. -/
theorem typedInvariantFieldEqualitySubject_genericCfgPhasesV1 :
    validateGenericCfgPhasesV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 = .ok () := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  exact ProofForgeV2.Semantic.FieldComparisonSubjectV1.genericCfgPhasesV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"

/-- The generated subject passes the complete production CFG/invariant
    segment, including no-PureCall closure and exact 3/5/5 fuel. -/
theorem typedInvariantFieldEqualitySubject_cfgInvariantPhasesV1 :
    validateCfgInvariantPhasesV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 = .ok () := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  exact ProofForgeV2.Semantic.FieldComparisonSubjectV1.cfgInvariantPhasesV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"

/-- The generated subject's root shape, dense table IDs, and shallow
    references pass the production structure prelude. -/
theorem typedInvariantFieldEqualitySubject_structurePreludeV1 :
    validateSemanticProgramStructurePreludeV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 = .ok () := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  apply ProofForgeV2.Semantic.FieldComparisonSubjectV1.structurePreludeV1
  rfl

/-- The generated anonymous UInt64/Bool table passes the production TypeKey
    phase; this is not a closed whole-structure claim. -/
theorem typedInvariantFieldEqualitySubject_typeKeyPhasesV1 :
    validateTypeKeyPhasesV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.types = .ok () := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  exact ProofForgeV2.Semantic.FieldComparisonSubjectV1.typeKeyPhasesV1

/-- The actual generated subject now passes every production structure phase.
    Its witness contains only source-name legality and namespace distinctness. -/
theorem typedInvariantFieldEqualitySubject_structureV1 :
    validateSemanticProgramStructureV1
      TypedInvariantFieldEqualitySurface.Proof.subjectDataV1 = .ok () := by
  rw [typedInvariantFieldEqualitySubject_subjectData_eq]
  apply ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
  exact {
    hnameShape := by rfl
    hstate0Name := by rfl
    hstate1Name := by rfl
    hstate2Name := by rfl
    hviewName := by rfl
    hliteralInvariantName := by rfl
    heqInvariantName := by rfl
    hneInvariantName := by rfl
    hstate01 := by decide
    hstate02 := by decide
    hstate12 := by decide
    hviewLiteral := by decide
    hviewEq := by decide
    hviewNe := by decide
    hliteralEq := by decide
    hliteralNe := by decide
    heqNe := by decide
  }

theorem typedInvariantFieldEqualitySubject_preservation_ordinal0 :
    PreservationTheoremV1
      TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 0 :=
  ProofForgeV2.Semantic.FieldComparisonPreservationV1.preservationTheorem_of_subjectBodyV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1
    TypedInvariantFieldEqualitySurface.Proof.subjectBytesV1
    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by rfl)
    TypedInvariantFieldEqualitySurface.Proof.subjectBodyEncodeOkV1

theorem typedInvariantFieldEqualitySubject_preservation_ordinal1 :
    PreservationTheoremV1
      TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 1 :=
  ProofForgeV2.Semantic.FieldComparisonPreservationV1.preservationTheorem_of_subjectBodyV1_ord1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1
    TypedInvariantFieldEqualitySurface.Proof.subjectBytesV1
    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by rfl)
    TypedInvariantFieldEqualitySurface.Proof.subjectBodyEncodeOkV1

/-- Product all-zero init makes ordinal 2 (two-state Ne) false. -/
theorem typedInvariantFieldEqualitySubject_eval_ordinal2_not_returnedTrue :
    evalInvariantV1
        TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 2
        ProofForgeV2.Semantic.FieldComparisonPreservationV1.productAllZeroInitialV1 ≠
      .returnedTrue :=
  ProofForgeV2.Semantic.FieldComparisonPreservationV1.evalInvariantV1_ord2_not_returnedTrue_of_subjectBodyV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1
    TypedInvariantFieldEqualitySurface.Proof.subjectBytesV1
    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by rfl)
    TypedInvariantFieldEqualitySurface.Proof.subjectBodyEncodeOkV1

theorem typedInvariantFieldEqualitySubject_not_base_ordinal2 :
    ¬ PreservationBaseNoInitializerV1
        TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 2 :=
  ProofForgeV2.Semantic.FieldComparisonPreservationV1.not_preservationBaseNoInitializerV1_ord2_of_subjectBodyV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1
    TypedInvariantFieldEqualitySurface.Proof.subjectBytesV1
    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by rfl)
    TypedInvariantFieldEqualitySurface.Proof.subjectBodyEncodeOkV1

theorem typedInvariantFieldEqualitySubject_not_preservation_ordinal2 :
    ¬ PreservationTheoremV1
        TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1 2 :=
  ProofForgeV2.Semantic.FieldComparisonPreservationV1.not_preservationTheoremV1_ord2_of_subjectBodyV1
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1.qualifiedName
    "nonce" "reserves" "shares" "alive" "primary" "solvent" "nonsolvent"
    TypedInvariantFieldEqualitySurface.Proof.subjectDataV1
    TypedInvariantFieldEqualitySurface.Proof.subjectBytesV1
    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by rfl)
    TypedInvariantFieldEqualitySurface.Proof.subjectBodyEncodeOkV1

run_cmd do
  let env ← getEnv
  let packagedOrd2 :=
    `ProofForgeV2.Semantic.FieldComparisonPreservationV1.preservationTheorem_of_subjectBodyV1_ord2
  if env.contains packagedOrd2 then
    throwError "FieldComparisonPreservationV1 must not package ordinal 2"

/-- Ordinary field mathematics now consumes the premise-free generated
    production validation certificate, matching the intended same-file style. -/
example (typedState : TypedInvariantFieldEqualitySurface.Model.State) :
    TypedInvariantFieldEqualitySurface.Model.solvent typedState ↔
      typedState.reserves = typedState.shares :=
  TypedInvariantFieldEqualitySurface.Model.Invariant.solvent_iff_fields
    typedState
    TypedInvariantFieldEqualitySurface.Proof.subjectValidationOkV1

example (typedState : TypedInvariantFieldEqualitySurface.Model.State) :
    TypedInvariantFieldEqualitySurface.Model.nonsolvent typedState ↔
      typedState.reserves ≠ typedState.shares :=
  TypedInvariantFieldEqualitySurface.Model.Invariant.nonsolvent_iff_fields
    typedState TypedInvariantFieldEqualitySurface.Proof.subjectValidationOkV1

/- Unsupported invariant CFGs keep their evaluator bridge but fail closed for
    the optional field-level mathematical theorem. -/
run_cmd do
  let env ← getEnv
  let unsupportedFieldBridge :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantFieldEqualitySurface.Model.Invariant.primary_iff_fields
  if env.contains unsupportedFieldBridge then
    throwError "literal-true invariant must not emit a field comparison bridge"

/- A composition around a supported comparison remains evaluator-backed but
   must not be mistaken for the exact three-instruction comparison rule. -/
program TypedInvariantFieldComparisonNearMiss where
  state reserves : UInt64
  state shares : UInt64
  view alive() : Bool do
    return true
  invariant nonsolvent : reserves != shares && true
  proof nonsolvent using TypedInvariantFieldComparisonNearMissProof.nonsolvent

#check TypedInvariantFieldComparisonNearMiss.Model.Invariant.nonsolvent_iff_eval

run_cmd do
  let env ← getEnv
  let nearMissFieldBridge :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantFieldComparisonNearMiss.Model.Invariant.nonsolvent_iff_fields
  if env.contains nearMissFieldBridge then
    throwError "composed inequality must not emit an exact field comparison bridge"

/- Invariant predicates are selected from the exact lowered invariant table;
   in particular, a second declaration is not silently hard-coded to zero. -/
program TypedInvariantOrdinalSurface where
  state count : UInt64
  view alive() : Bool do
    return true
  invariant primary : true
  invariant secondary : true
  proof primary using TypedInvariantOrdinalSurfaceProof.primary
  proof secondary using TypedInvariantOrdinalSurfaceProof.secondary
  proof secondary preserving using TypedInvariantOrdinalSurfaceProof.secondaryPreserving

#check TypedInvariantOrdinalSurface.Model.primary
#check TypedInvariantOrdinalSurface.Model.secondary
#check TypedInvariantOrdinalSurface.Model.Invariant.primary_iff_eval
#check TypedInvariantOrdinalSurface.Model.Invariant.secondary_iff_eval
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.callable0ReturnedV1
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.callable0TypedReturnedV1
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.callable0ReturnedV1_of_typed
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.ReturnedCallablesV1
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.ofCallableObligationsV1
#check TypedInvariantOrdinalSurface.ProofPreserving.secondary.ofRowObligationsV1

example (admitted : AdmittedReferenceSliceV1) :
    TypedInvariantOrdinalSurface.ProofPreserving.secondary.ReturnedCallablesV1
        admitted =
      PreservationReturnedCallablesV1
        TypedInvariantOrdinalSurface.Proof.subjectProgramV1 1 admitted := rfl

example (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1
      TypedInvariantOrdinalSurface.Proof.subjectProgramV1 = .ok admitted) :
    TypedInvariantOrdinalSurface.ProofPreserving.secondary.callable0TypedReturnedV1
        admitted hadmit =
      TypedReturnedPreservationV1
        TypedInvariantOrdinalSurface.Model.encodeState
        TypedInvariantOrdinalSurface.Model.alive.encodeResult 1
        ⟨admitted, hadmit⟩ 0 := rfl

run_cmd do
  let env ← getEnv
  let nearMissStructure :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantOrdinalSurface.Proof.subjectStructureOkV1
  if env.contains nearMissStructure then
    throwError "near-miss invariant tables must not emit a structure certificate"
  let nearMissValidation :=
    `Tests.Language.InlineProofAuthoringV1.TypedInvariantOrdinalSurface.Proof.subjectValidationOkV1
  if env.contains nearMissValidation then
    throwError "near-miss invariant tables must not emit a validation certificate"

example (typedState : TypedInvariantOrdinalSurface.Model.State) :
    TypedInvariantOrdinalSurface.Model.secondary typedState =
      TypedInvariantV1 TypedInvariantOrdinalSurface.Model.encodeState
        TypedInvariantOrdinalSurface.Proof.subjectProgramV1 1 typedState := rfl

example :
    TypedInvariantOrdinalSurface.Proof.subjectDataV1.invariants[1]?.map
        (fun invariant => invariant.name) =
      some "secondary" := rfl

program TypedCallableSurface where
  state count : UInt64
  entry add(delta : UInt64) : UInt64 do
    count := count + delta
    return count
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using TypedCallableSurfaceProof.safe

#check TypedCallableSurface.Model.ReferenceSubject
#check TypedCallableSurface.Model.admitReferenceSubject
#check TypedCallableSurface.Model.Outcome
#check TypedCallableSurface.Model.add.invocation
#check TypedCallableSurface.Model.add.invocation_complete_of_ready
#check TypedCallableSurface.Model.add.Result
#check TypedCallableSurface.Model.add.encodeResult
#check TypedCallableSurface.Model.add.decodeResult
#check TypedCallableSurface.Model.add.decode_encode_result
#check TypedCallableSurface.Model.add.decodeResult_complete_of_conforms
#check TypedCallableSurface.Model.add.decodeResult_existsUnique_of_conforms
#check TypedCallableSurface.Model.add.decodeResult_complete_of_returned
#check TypedCallableSurface.Model.add.decodeResult_existsUnique_of_returned
#check TypedCallableSurface.Model.add.decodeState_complete_of_returned
#check TypedCallableSurface.Model.add.decodeState_existsUnique_of_returned
#check TypedCallableSurface.Model.add.encodeResult_injective
#check TypedCallableSurface.Model.add.Outcome
#check TypedCallableSurface.Model.add.Transition
#check TypedCallableSurface.Model.add.transition_returned_of_step
#check TypedCallableSurface.Model.add.transition_reverted_of_step
#check TypedCallableSurface.Model.add.transition_trapped_of_step
#check TypedCallableSurface.Model.add.transition_exists
#check TypedCallableSurface.Model.add.outcome_unique
#check TypedCallableSurface.Model.alive.invocation
#check TypedCallableSurface.Model.alive.invocation_complete_of_ready
#check TypedCallableSurface.Model.alive.Result
#check TypedCallableSurface.Model.alive.encodeResult
#check TypedCallableSurface.Model.alive.decodeResult
#check TypedCallableSurface.Model.alive.decode_encode_result
#check TypedCallableSurface.Model.alive.decodeResult_complete_of_conforms
#check TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_conforms
#check TypedCallableSurface.Model.alive.decodeResult_complete_of_returned
#check TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_returned
#check TypedCallableSurface.Model.alive.decodeState_complete_of_returned
#check TypedCallableSurface.Model.alive.decodeState_existsUnique_of_returned
#check TypedCallableSurface.Model.alive.encodeResult_injective
#check TypedCallableSurface.Model.alive.Outcome
#check TypedCallableSurface.Model.alive.Transition
#check TypedCallableSurface.Model.alive.transition_returned_of_step
#check TypedCallableSurface.Model.alive.transition_reverted_of_step
#check TypedCallableSurface.Model.alive.transition_trapped_of_step
#check TypedCallableSurface.Model.alive.transition_exists
#check TypedCallableSurface.Model.alive.outcome_unique

run_cmd do
  let env ← getEnv
  let structureCertificate :=
    `Tests.Language.InlineProofAuthoringV1.TypedCallableSurface.Proof.subjectStructureOkV1
  if env.contains structureCertificate then
    throwError "unsupported structural families must not emit a structure certificate"
  let validationCertificate :=
    `Tests.Language.InlineProofAuthoringV1.TypedCallableSurface.Proof.subjectValidationOkV1
  if env.contains validationCertificate then
    throwError "unsupported structural families must not emit a validation certificate"

/-- Typed arguments are encoded as canonical Reference values using the exact
    callable and TypeIds from the generated semantic subject. -/
example : TypedCallableSurface.Model.add.invocation 3 #[] = ({
    callableId := 0
    args := #[{ typeId := 1, valueBytes := encodeU64le 3 }]
    context := #[]
  } : InvocationV1) := rfl

example : TypedCallableSurface.Model.alive.invocation #[] = ({
    callableId := 1
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

/-- The generated projection consumes the sole production gate and recovers
    the named UInt64 argument without interpreting the callable body again. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (logicalPre : LogicalStateV1)
    (rawInvocation : InvocationV1)
    (argumentOverlay : Array ByteArray)
    (context : Array ContextInputV1)
    (isInitializer : Bool)
    (hvalidate :
      validateSemanticProgramV1
          TypedCallableSurface.Proof.subjectProgramV1 =
        .ok TypedCallableSurface.Proof.subjectDataV1)
    (hcallableId : rawInvocation.callableId = 0)
    (hgate :
      gateInvocation subject.admitted logicalPre rawInvocation =
        .ready
          (TypedCallableSurface.Proof.subjectDataV1.callables[0]'(by decide))
          argumentOverlay context isInitializer) :
    ∃ deltaArg : UInt64,
      rawInvocation = TypedCallableSurface.Model.add.invocation
        deltaArg rawInvocation.context :=
  TypedCallableSurface.Model.add.invocation_complete_of_ready
    subject logicalPre rawInvocation argumentOverlay context isInitializer
      hvalidate hcallableId hgate

/- Exact generated proof views for the two-zero initializer, stuttering view,
   and two-field equality family used by the business-level Vault slice. -/
program InitializerViewEqualitySurface where
  state reserves : UInt64
  state shares : UInt64
  init() do
    reserves := 0
    shares := 0
  view status() : UInt64 do
    return reserves
  invariant solvent : reserves == shares
  proof solvent preserving using InitializerViewEqualitySurfaceProof.solvent

theorem initializerViewEqualitySurface_subjectData_eq :
    InitializerViewEqualitySurface.Proof.subjectDataV1 =
      ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1
        InitializerViewEqualitySurface.Proof.subjectDataV1.qualifiedName
        "reserves" "shares" "status" "solvent" := by
  rfl

#check InitializerViewEqualitySurface.Proof.subjectStructureOkV1
#check InitializerViewEqualitySurface.Proof.subjectValidationOkV1
#check InitializerViewEqualitySurface.Model.LifecycleState
#check InitializerViewEqualitySurface.Model.initialLifecycleState
#check InitializerViewEqualitySurface.Model.init.Transition
#check InitializerViewEqualitySurface.Model.status.Transition
#check InitializerViewEqualitySurface.Model.solvent
#check InitializerViewEqualitySurface.Model.Invariant.solvent_iff_eval
#check InitializerViewEqualitySurface.Model.Invariant.solvent_iff_fields
#check InitializerViewEqualitySurface.ProofPreserving.solvent.WithInitializerBaseV1
#check InitializerViewEqualitySurface.ProofPreserving.solvent.callable0ReturnedV1
#check InitializerViewEqualitySurface.ProofPreserving.solvent.callable1TypedReturnedV1
#check InitializerViewEqualitySurface.ProofPreserving.solvent.callable1ReturnedV1_of_typed
#check InitializerViewEqualitySurface.ProofPreserving.solvent.callable2ReturnedV1

/- Alpha-renamed initializer/additive-entry/view/equality surface. This proves
   that the production elaborator recognizes the generic semantic shape rather
   than the business names used by `Examples.VerifiedVaultPF`. -/
program InitializerDepositViewEqualitySurface where
  state assets : UInt64
  state liabilities : UInt64
  init() do
    assets := 0
    liabilities := 0
  entry contribute(quantity : UInt64) : UInt64 do
    assets := assets + quantity
    liabilities := liabilities + quantity
    return liabilities
  view readAssets() : UInt64 do
    return assets
  invariant balanced : assets == liabilities
  proof balanced preserving using InitializerDepositViewEqualitySurfaceProof.balanced

theorem initializerDepositViewEqualitySurface_subjectData_eq :
    InitializerDepositViewEqualitySurface.Proof.subjectDataV1 =
      ProofForgeV2.Semantic.InitializerDepositViewEqualitySubjectV1.subjectDataV1
        InitializerDepositViewEqualitySurface.Proof.subjectDataV1.qualifiedName
        "assets" "liabilities" "contribute" "quantity" "readAssets" "balanced" := by
  rfl

#check InitializerDepositViewEqualitySurface.Proof.subjectStructureOkV1
#check InitializerDepositViewEqualitySurface.Proof.subjectValidationOkV1
#check InitializerDepositViewEqualitySurface.Model.init.Transition
#check InitializerDepositViewEqualitySurface.Model.contribute.Transition
#check InitializerDepositViewEqualitySurface.Model.readAssets.Transition
#check InitializerDepositViewEqualitySurface.Model.Invariant.balanced_iff_eval
#check InitializerDepositViewEqualitySurface.Model.Invariant.balanced_iff_fields
#check InitializerDepositViewEqualitySurface.ProofPreserving.balanced.callable0ReturnedV1
#check InitializerDepositViewEqualitySurface.ProofPreserving.balanced.callable1ReturnedV1
#check InitializerDepositViewEqualitySurface.ProofPreserving.balanced.callable2ReturnedV1
#check InitializerDepositViewEqualitySurface.ProofPreserving.balanced.callable3ReturnedV1

theorem InitializerDepositViewEqualitySurfaceProof.balanced :
    InitializerDepositViewEqualitySurface.ProofPreserving.balanced := by
  exact
    ProofForgeV2.Semantic.InitializerDepositViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      InitializerDepositViewEqualitySurface.Proof.subjectDataV1.qualifiedName
      "assets" "liabilities" "contribute" "quantity" "readAssets" "balanced"
      InitializerDepositViewEqualitySurface.Proof.subjectDataV1
      InitializerDepositViewEqualitySurface.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by decide) (by decide) (by rfl)
      InitializerDepositViewEqualitySurface.Proof.subjectBodyEncodeOkV1

/- Exact five-callable family, alpha-renamed away from the shipped vault. -/
program InitializerDepositWithdrawViewEqualitySurface where
  state assets : UInt64
  state liabilities : UInt64
  init() do
    assets := 0
    liabilities := 0
  entry contribute(quantity : UInt64) : UInt64 do
    assets := assets + quantity
    liabilities := liabilities + quantity
    return liabilities
  entry redeem(quantity : UInt64) : Unit do
    assert quantity <= assets
    assert quantity <= liabilities
    assets := assets - quantity
    liabilities := liabilities - quantity
  view readAssets() : UInt64 do
    return assets
  invariant balanced : assets == liabilities
  proof balanced preserving using InitializerDepositWithdrawViewEqualitySurfaceProof.balanced

theorem initializerDepositWithdrawViewEqualitySurface_subjectData_eq :
    InitializerDepositWithdrawViewEqualitySurface.Proof.subjectDataV1 =
      ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualitySubjectV1.subjectDataV1
        InitializerDepositWithdrawViewEqualitySurface.Proof.subjectDataV1.qualifiedName
        "assets" "liabilities" "contribute" "quantity" "redeem" "quantity"
        "readAssets" "balanced" := by
  rfl

#check InitializerDepositWithdrawViewEqualitySurface.Proof.subjectStructureOkV1
#check InitializerDepositWithdrawViewEqualitySurface.Proof.subjectValidationOkV1
#check InitializerDepositWithdrawViewEqualitySurface.Model.init.Transition
#check InitializerDepositWithdrawViewEqualitySurface.Model.contribute.Transition
#check InitializerDepositWithdrawViewEqualitySurface.Model.redeem.Transition
#check InitializerDepositWithdrawViewEqualitySurface.Model.readAssets.Transition
#check InitializerDepositWithdrawViewEqualitySurface.Model.Invariant.balanced_iff_eval
#check InitializerDepositWithdrawViewEqualitySurface.Model.Invariant.balanced_iff_fields
#check InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced.callable0ReturnedV1
#check InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced.callable1ReturnedV1
#check InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced.callable2ReturnedV1
#check InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced.callable3ReturnedV1
#check InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced.callable4ReturnedV1

theorem InitializerDepositWithdrawViewEqualitySurfaceProof.balanced :
    InitializerDepositWithdrawViewEqualitySurface.ProofPreserving.balanced := by
  exact
    ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1
      InitializerDepositWithdrawViewEqualitySurface.Proof.subjectDataV1.qualifiedName
      "assets" "liabilities" "contribute" "quantity" "redeem" "quantity"
      "readAssets" "balanced"
      InitializerDepositWithdrawViewEqualitySurface.Proof.subjectDataV1
      InitializerDepositWithdrawViewEqualitySurface.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by rfl) (by rfl)
      (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
      (by decide) (by rfl)
      InitializerDepositWithdrawViewEqualitySurface.Proof.subjectBodyEncodeOkV1

/- Typed-valid but shape-inexact: the second checked subtraction/store is absent. -/
program InitializerDepositWithdrawViewEqualityNearMiss where
  state assets : UInt64
  state liabilities : UInt64
  init() do
    assets := 0
    liabilities := 0
  entry contribute(quantity : UInt64) : UInt64 do
    assets := assets + quantity
    liabilities := liabilities + quantity
    return liabilities
  entry redeem(quantity : UInt64) : Unit do
    assert quantity <= assets
    assert quantity <= liabilities
    assets := assets - quantity
  view readAssets() : UInt64 do
    return assets
  invariant balanced : assets == liabilities
  proof balanced preserving using InitializerDepositWithdrawViewEqualityNearMissProof.balanced

run_cmd do
  let env ← getEnv
  if env.contains `Tests.Language.InlineProofAuthoringV1.InitializerDepositWithdrawViewEqualityNearMiss.Proof.subjectStructureOkV1 ||
      env.contains `Tests.Language.InlineProofAuthoringV1.InitializerDepositWithdrawViewEqualityNearMiss.Proof.subjectValidationOkV1 then
    throwError "five-callable near miss must not emit production certificates"

/- The first state-dependent, genuinely mutating business-preservation fixture.
   Its generated certificate belongs to a name-parameterized production
   subject family rather than a contract-qualified closed proof. -/
program StateChangingPreservationSurface where
  state reserves : UInt64
  state shares : UInt64
  entry sync(amount : UInt64) : UInt64 do
    reserves := amount
    shares := amount
    return shares
  invariant solvent : reserves == shares
  proof solvent preserving using StateChangingPreservationSurfaceProof.aggregate

/-- The generated data is exactly the parameterized production validation
    family; no contract-qualified pin or alternate validity predicate is used. -/
theorem stateChangingPreservationSurface_subjectData_eq :
    StateChangingPreservationSurface.Proof.subjectDataV1 =
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1
        StateChangingPreservationSurface.Proof.subjectDataV1.qualifiedName
        "reserves" "shares" "sync" "amount" "solvent" := by
  rfl

#check StateChangingPreservationSurface.Model.sync.invocation
#check StateChangingPreservationSurface.Model.sync.invocation_complete_of_ready
#check StateChangingPreservationSurface.Model.sync.Transition
#check StateChangingPreservationSurface.Model.solvent
#check StateChangingPreservationSurface.Model.Invariant.solvent_iff_eval
#check StateChangingPreservationSurface.Model.Invariant.solvent_iff_fields
#check StateChangingPreservationSurface.ProofPreserving.solvent.callable0TypedReturnedV1
#check StateChangingPreservationSurface.Proof.subjectStructureOkV1
#check StateChangingPreservationSurface.Proof.subjectValidationOkV1

/- Pin the exact production CFG consumed by the business proof. Any Normalize
   drift changes this equality instead of silently selecting another shape. -/
theorem stateChangingPreservationSurface_sync_callable_shape :
    StateChangingPreservationSurface.Proof.subjectDataV1.callables[0] = {
      id := 0
      kind := .entry
      name := some "sync"
      params := #[{
        valueId := 0
        name := "amount"
        typeId := 1
        visibility := .public_
      }]
      result := { typeId := 1, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := none, op := .stateStore 0 0 },
          { result := none, op := .stateStore 1 0 },
          { result := some { valueId := 1, typeId := 1 },
            op := .stateLoad 1 }
        ]
        terminator := .return_ (some 1)
      }]
      loopBounds := #[]
      invariantSteps := none
    } := rfl

/-- A successful production-backed typed relation for `sync` exposes the exact
    accepted UInt64 argument and exact typed post-state. The proof inverts the
    sole Reference step through the fixed generated CFG above. -/
theorem StateChangingPreservationSurfaceProof.sync_returned_post_eq
    (admitted : AdmittedReferenceSliceV1)
    (hadmit :
      admitReferenceProgramSliceV1
          StateChangingPreservationSurface.Proof.subjectProgramV1 =
        .ok admitted)
    (pre post : StateChangingPreservationSurface.Model.State)
    (result : StateChangingPreservationSurface.Model.sync.Result)
    (effects : Array OrderedEffectV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (hcallableId : invocation.callableId = 0)
    (htransition :
      TypedCallableRelationV1
        StateChangingPreservationSurface.Model.encodeState
        StateChangingPreservationSurface.Model.sync.encodeResult
        ⟨admitted, hadmit⟩ pre invocation responses vault
        (.returned post result effects)) :
    ∃ amount : UInt64,
      invocation =
          StateChangingPreservationSurface.Model.sync.invocation amount
            invocation.context ∧
        post = ({ reserves := amount, shares := amount } :
          StateChangingPreservationSurface.Model.State) := by
  have hvalidate :=
    StateChangingPreservationSurface.Proof.subjectValidationOkV1
  unfold TypedCallableRelationV1 at htransition
  obtain ⟨logicalPre, hencodePre, logicalPost, hencodePost, hstep⟩ :=
    htransition
  have hready :=
    ProofForgeV2.Semantic.PreservationPackagingV1.stepReturnedImpliesGateReadyV1
      admitted logicalPre invocation responses vault logicalPost
        (StateChangingPreservationSurface.Model.sync.encodeResult result)
        effects hstep
  cases hgate : gateInvocation admitted logicalPre invocation with
  | invalidInvocation =>
      rw [hgate] at hready
      exact False.elim hready
  | lifecycle candidate =>
      rw [hgate] at hready
      exact False.elim hready
  | ready callable overlay gateContext isInitializer =>
      have hadmittedData :
          admitted.data =
            StateChangingPreservationSurface.Proof.subjectDataV1 :=
        (admitReferenceProgramSliceV1_ok_implies
          StateChangingPreservationSurface.Proof.subjectProgramV1
          StateChangingPreservationSurface.Proof.subjectDataV1 admitted
          hvalidate hadmit).2
      have hlookup :=
        (gateInvocation_ready_callable_lookup admitted logicalPre invocation
          callable overlay gateContext isInitializer hgate).1
      have hlookup0 :
          StateChangingPreservationSurface.Proof.subjectDataV1.callables[0]? =
            some callable := by
        rw [hadmittedData] at hlookup
        simpa [hcallableId] using hlookup
      have hcallable :
          callable =
            StateChangingPreservationSurface.Proof.subjectDataV1.callables[0] := by
        have hrow :
            StateChangingPreservationSurface.Proof.subjectDataV1.callables[0]? =
              some
                StateChangingPreservationSurface.Proof.subjectDataV1.callables[0] :=
          rfl
        exact Option.some.inj (hlookup0.symm.trans hrow)
      have hgateRow :
          gateInvocation admitted logicalPre invocation =
            .ready
              StateChangingPreservationSurface.Proof.subjectDataV1.callables[0]
              overlay gateContext isInitializer := by
        simpa [hcallable] using hgate
      obtain ⟨amount, hinvocation⟩ :=
        StateChangingPreservationSurface.Model.sync.invocation_complete_of_ready
          ⟨admitted, hadmit⟩ logicalPre invocation overlay gateContext
            isInitializer hvalidate hcallableId hgateRow
      have hisInitializer : isInitializer = false := by
        have hkind :=
          (gateInvocation_ready_callable_lookup admitted logicalPre invocation
            callable overlay gateContext isInitializer hgate).2
        rw [hcallable] at hkind
        rw [stateChangingPreservationSurface_sync_callable_shape] at hkind
        exact hkind.trans (by decide)
      have hgateNoninit :
          gateInvocation admitted logicalPre invocation =
            .ready
              StateChangingPreservationSurface.Proof.subjectDataV1.callables[0]
              overlay gateContext false := by
        simpa [hisInitializer] using hgateRow
      have hdecodeGate :
          decodeLogicalStateValuesV1
              StateChangingPreservationSurface.Proof.subjectDataV1 logicalPre =
            .ok overlay := by
        have hdecode :=
          (gateInvocation_ready_noninit_decode admitted logicalPre invocation
            StateChangingPreservationSurface.Proof.subjectDataV1.callables[0]
            overlay gateContext hgateNoninit).1
        simpa [hadmittedData] using hdecode
      have hencodeValues :
          encodeLogicalStateValuesV1
              StateChangingPreservationSurface.Proof.subjectDataV1 true #[
                encodeU64le pre.reserves,
                encodeU64le pre.shares
              ] = .ok logicalPre := by
        unfold StateChangingPreservationSurface.Model.encodeState at hencodePre
        exact hencodePre
      have hdecodePre :
          decodeLogicalStateValuesV1
              StateChangingPreservationSurface.Proof.subjectDataV1 logicalPre =
            .ok #[encodeU64le pre.reserves, encodeU64le pre.shares] :=
        decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
          StateChangingPreservationSurface.Proof.subjectDataV1 true
          #[encodeU64le pre.reserves, encodeU64le pre.shares] logicalPre
          hencodeValues
      have hoverlay :
          overlay = #[encodeU64le pre.reserves, encodeU64le pre.shares] := by
        rw [hdecodeGate] at hdecodePre
        exact Except.ok.inj hdecodePre
      have hcanonical :
          validateValueBytesV1
              StateChangingPreservationSurface.Proof.subjectDataV1.types 1
              (encodeU64le amount) = .ok () := by
        apply validateValueBytesV1_uint64_of_size
          StateChangingPreservationSurface.Proof.subjectDataV1.types 1
          (StateChangingPreservationSurface.Proof.subjectDataV1.types[1])
          (encodeU64le amount)
        · rfl
        · rfl
        · exact encodeU64le_size amount
      have hgateSync := hgateNoninit
      have hstepSync := hstep
      rw [hinvocation, hoverlay] at hgateSync
      rw [hinvocation] at hstepSync
      have hpostEncode :
          encodeLogicalStateValuesV1
              StateChangingPreservationSurface.Proof.subjectDataV1 true
              #[encodeU64le amount, encodeU64le amount] = .ok logicalPost := by
        apply stepReferenceSliceV1_ready_store_parameter_two_returned_post_encode
          admitted logicalPre logicalPost
          StateChangingPreservationSurface.Proof.subjectDataV1
          (encodeU64le pre.reserves) (encodeU64le pre.shares)
          (encodeU64le amount) 1 "reserves" "shares" "amount" 0
          (some "sync") invocation.context gateContext responses vault
          (StateChangingPreservationSurface.Model.sync.encodeResult result)
          effects hadmittedData
        · rfl
        · rfl
        · rfl
        · exact hcanonical
        · simpa [StateChangingPreservationSurface.Model.sync.invocation,
            stateChangingPreservationSurface_sync_callable_shape] using hgateSync
        · simpa [StateChangingPreservationSurface.Model.sync.invocation] using
            hstepSync
      let expected : StateChangingPreservationSurface.Model.State := {
        reserves := amount
        shares := amount
      }
      have hencodeExpected :
          StateChangingPreservationSurface.Model.encodeState expected =
            .ok logicalPost := by
        unfold StateChangingPreservationSurface.Model.encodeState
        simpa [expected] using hpostEncode
      have hpost : post = expected :=
        StateChangingPreservationSurface.Model.encode_injective_of_eq_ok
          post expected logicalPost hencodePost hencodeExpected
      exact ⟨amount, hinvocation, by simpa [expected] using hpost⟩

/-- The actual generated typed returned-row obligation is discharged by
    ordinary field mathematics after the sole Reference execution is inverted. -/
theorem StateChangingPreservationSurfaceProof.sync_typed_preserves_solvent
    (admitted : AdmittedReferenceSliceV1)
    (hadmit :
      admitReferenceProgramSliceV1
          StateChangingPreservationSurface.Proof.subjectProgramV1 =
        .ok admitted) :
    StateChangingPreservationSurface.ProofPreserving.solvent.callable0TypedReturnedV1
      admitted hadmit := by
  have hvalidate :=
    StateChangingPreservationSurface.Proof.subjectValidationOkV1
  intro pre post result effects invocation responses vault hcallableId
    _hpreInvariant htransition
  obtain ⟨amount, _hinvocation, hpost⟩ :=
    StateChangingPreservationSurfaceProof.sync_returned_post_eq
      admitted hadmit pre post result effects invocation responses
        vault hcallableId htransition
  subst post
  apply
    (StateChangingPreservationSurface.Model.Invariant.solvent_iff_fields
      { reserves := amount, shares := amount } hvalidate).2
  rfl

/-- Same-file program-level preservation for the state-changing equality
    family. Validation, Reference admission, initial-state construction, and
    both exact callable rows are all discharged through production APIs. -/
theorem StateChangingPreservationSurfaceProof.aggregate :
    StateChangingPreservationSurface.ProofPreserving.solvent := by
  have hvalidate :=
    StateChangingPreservationSurface.Proof.subjectValidationOkV1
  have hadmission :
      validateReferenceProgramDataAdmissionV1
          StateChangingPreservationSurface.Proof.subjectDataV1 = .ok () := by
    rw [stateChangingPreservationSurface_subjectData_eq]
    exact
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.referenceAdmissionV1
        StateChangingPreservationSurface.Proof.subjectDataV1.qualifiedName
        "reserves" "shares" "sync" "amount" "solvent"
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks
      StateChangingPreservationSurface.Proof.subjectProgramV1
      StateChangingPreservationSurface.Proof.subjectDataV1 hvalidate hadmission
  have hadmittedData :
      admitted.data = StateChangingPreservationSurface.Proof.subjectDataV1 :=
    (admitReferenceProgramSliceV1_ok_implies
      StateChangingPreservationSurface.Proof.subjectProgramV1
      StateChangingPreservationSurface.Proof.subjectDataV1 admitted hvalidate
        hadmit).2
  have hnoInitializerAny :
      StateChangingPreservationSurface.Proof.subjectDataV1.callables.any
          (fun callable => callable.kind == .initializer) = false := by
    rw [stateChangingPreservationSurface_subjectData_eq]
    simp [ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1,
      ProofForgeV2.Semantic.PreservationShapeV1.storeParameterTwoReturnCallableV1,
      ProofForgeV2.Semantic.PreservationShapeV1.twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hbase :
      StateChangingPreservationSurface.ProofPreserving.solvent.BaseV1
        admitted := by
    apply
      ProofForgeV2.Semantic.PreservationPackagingV1.preservationBaseV1_of_noInitializerV1
    · exact
        not_hasInitializerV1_of_validate_and_any_eq_false
          StateChangingPreservationSurface.Proof.subjectProgramV1
          StateChangingPreservationSurface.Proof.subjectDataV1 hvalidate
            hnoInitializerAny
    · let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
      let initial : LogicalStateV1 := {
        initialized := true
        canonicalValues := doubleUint64CanonicalV1 zero zero
      }
      have hinitial :
          initialLogicalStateV1
              StateChangingPreservationSurface.Proof.subjectProgramV1 =
            .ok initial := by
        simpa [initial, zero] using
          initialLogicalStateV1_double_uint64_no_initializer_eq_ok
            StateChangingPreservationSurface.Proof.subjectProgramV1
            StateChangingPreservationSurface.Proof.subjectDataV1
            (StateDeclV1.mk 0 "reserves" 1 .public_)
            (StateDeclV1.mk 1 "shares" 1 .public_)
            (TypeDeclV1.mk 1 none (.uint 64))
            hvalidate rfl rfl rfl rfl hnoInitializerAny rfl rfl
      let typedInitial : StateChangingPreservationSurface.Model.State := {
        reserves := 0
        shares := 0
      }
      have hencodeInitial :
          StateChangingPreservationSurface.Model.encodeState typedInitial =
            .ok initial := by
        have hzeroEncode : encodeU64le 0 = zero := by rfl
        unfold StateChangingPreservationSurface.Model.encodeState
        simpa [typedInitial, initial, hzeroEncode] using
          encodeLogicalStateValuesV1_double_uint64_eq_ok
            StateChangingPreservationSurface.Proof.subjectDataV1
            (StateDeclV1.mk 0 "reserves" 1 .public_)
            (StateDeclV1.mk 1 "shares" 1 .public_)
            (encodeU64le 0) (encodeU64le 0) true rfl rfl rfl rfl rfl
      have hconforms :
          StateConformsV1
            StateChangingPreservationSurface.Proof.subjectProgramV1 initial :=
        StateChangingPreservationSurface.Model.conforms_of_encode
          typedInitial initial hvalidate hencodeInitial
      have htypedInvariant :
          StateChangingPreservationSurface.Model.solvent typedInitial := by
        apply
          (StateChangingPreservationSurface.Model.Invariant.solvent_iff_fields
            typedInitial hvalidate).2
        rfl
      have heval :
          evalInvariantV1
              StateChangingPreservationSurface.Proof.subjectProgramV1 0
              initial = .returnedTrue :=
        (StateChangingPreservationSurface.Model.Invariant.solvent_iff_eval
          typedInitial initial hencodeInitial).1 htypedInvariant
      exact ⟨initial, hinitial, hconforms, heval⟩
  have hcallable0 :
      StateChangingPreservationSurface.ProofPreserving.solvent.callable0ReturnedV1
        admitted :=
    StateChangingPreservationSurface.ProofPreserving.solvent.callable0ReturnedV1_of_typed
      admitted hvalidate hadmit
        (StateChangingPreservationSurfaceProof.sync_typed_preserves_solvent
          admitted hadmit)
  have hcallable1 :
      StateChangingPreservationSurface.ProofPreserving.solvent.callable1ReturnedV1
        admitted := by
    intro pre invocation responses vault overlay context isInitializer
      postState value effects hcallableId _hconforms _heval hgate _hstep
    simp [gateInvocation, hadmittedData, hcallableId,
      StateChangingPreservationSurface.Proof.subjectDataV1,
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1,
      ProofForgeV2.Semantic.PreservationShapeV1.twoStateCompareInvariantCallableV1,
      show (CallableKindV1.invariant == CallableKindV1.initializer) = false by
        decide,
      show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
      show (CallableKindV1.invariant == CallableKindV1.view) = false by decide]
      at hgate
  exact
    StateChangingPreservationSurface.ProofPreserving.solvent.ofRowObligationsV1
      admitted hvalidate hadmit hbase hcallable0 hcallable1

/- A nearby entry that updates only one field must not inherit the exact
   stateful-equality family's production certificates. -/
program StateChangingPreservationNearMiss where
  state reserves : UInt64
  state shares : UInt64
  entry sync(amount : UInt64) : UInt64 do
    reserves := amount
    return reserves
  invariant solvent : reserves == shares
  proof solvent preserving using StateChangingPreservationNearMissProof.aggregate

run_cmd do
  let env ← getEnv
  let structureCertificate :=
    `Tests.Language.InlineProofAuthoringV1.StateChangingPreservationNearMiss.Proof.subjectStructureOkV1
  let validationCertificate :=
    `Tests.Language.InlineProofAuthoringV1.StateChangingPreservationNearMiss.Proof.subjectValidationOkV1
  if env.contains structureCertificate || env.contains validationCertificate then
    throwError "stateful equality near miss must not emit production certificates"

/-- Generated result decoding checks the exact lowered TypeId and delegates
    canonical payload validation to the production valueBytes validator. -/
example : TypedCallableSurface.Model.add.decodeResult
    (TypedCallableSurface.Model.add.encodeResult 9) = .ok 9 :=
  TypedCallableSurface.Model.add.decode_encode_result 9

example : TypedCallableSurface.Model.alive.decodeResult
    (TypedCallableSurface.Model.alive.encodeResult false) = .ok false :=
  TypedCallableSurface.Model.alive.decode_encode_result false

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[0]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.add.Result,
      TypedCallableSurface.Model.add.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedCallableSurface.Model.add.Result,
          TypedCallableSurface.Model.add.decodeResult referenceValue = .ok other →
            value = other :=
  TypedCallableSurface.Model.add.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[1]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.alive.Result,
      TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedCallableSurface.Model.alive.Result,
          TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok other →
            value = other :=
  TypedCallableSurface.Model.alive.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

/-- A conforming Bool result does not merely decode: canonical re-encoding
    recovers the exact Reference carrier needed by the typed relation. -/
example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedCallableSurface.Proof.subjectDataV1
        (TypedCallableSurface.Proof.subjectDataV1.callables[1]'(by decide)).result
        referenceValue) :
    ∃ value : TypedCallableSurface.Model.alive.Result,
      TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok value ∧
        TypedCallableSurface.Model.alive.encodeResult value = referenceValue ∧
          ∀ other : TypedCallableSurface.Model.alive.Result,
            TypedCallableSurface.Model.alive.decodeResult referenceValue = .ok other →
              value = other :=
  TypedCallableSurface.Model.alive.decodeResult_complete_of_conforms
    referenceValue hconforms

example : TypedCallableSurface.Model.alive.decodeResult
    (TypedCallableSurface.Model.alive.encodeResult true) = .ok true :=
  TypedCallableSurface.Model.alive.decode_encode_result true

/-- A payload with another lowered TypeId is rejected before projection. -/
example : TypedCallableSurface.Model.alive.decodeResult (some {
    typeId := 1
    valueBytes := encodeBool true
  }) = .error .nonCanonical := by
  rfl

/-- The exact Bool TypeId is still insufficient when production canonical
    valueBytes validation rejects the payload. -/
example : TypedCallableSurface.Model.alive.decodeResult (some {
    typeId := 0
    valueBytes := ByteArray.mk #[2]
  }) = .error .nonCanonical := by
  rfl

/-- The generated relation is only a typed view over the generic relation. It
    retains context, responses, and vault instead of silently fixing them. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (delta : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedCallableSurface.Model.add.Outcome) :
    TypedCallableSurface.Model.add.Transition
        subject pre delta context responses vault outcome =
      TypedCallableRelationV1
        TypedCallableSurface.Model.encodeState
        (fun value : UInt64 => some {
          typeId := 1
          valueBytes := encodeU64le value
        })
        subject pre
        (TypedCallableSurface.Model.add.invocation delta context)
        responses vault outcome := rfl

/-- Bool callable results retain their exact lowered TypeId and use the
    production Bool value codec; this does not add Bool logical-state support. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedCallableSurface.Model.alive.Outcome) :
    TypedCallableSurface.Model.alive.Transition
        subject pre context responses vault outcome =
      TypedCallableRelationV1
        TypedCallableSurface.Model.encodeState
        (fun value : Bool => some {
          typeId := 0
          valueBytes := encodeBool value
        })
        subject pre
        (TypedCallableSurface.Model.alive.invocation context)
        responses vault outcome := rfl

/-- Fixed typed inputs cannot relate to two distinct typed outcomes. The
    generated theorem combines the single Reference step with state/result
    codec injectivity; it does not execute the callable. -/
example
    (subject : TypedCallableSurface.Model.ReferenceSubject)
    (pre : TypedCallableSurface.Model.State)
    (delta : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (left right : TypedCallableSurface.Model.add.Outcome)
    (hleft : TypedCallableSurface.Model.add.Transition
      subject pre delta context responses vault left)
    (hright : TypedCallableSurface.Model.add.Transition
      subject pre delta context responses vault right) :
    left = right :=
  TypedCallableSurface.Model.add.outcome_unique
    subject pre delta context responses vault left right hleft hright

/-- Expanding the sole generic relation exposes the exact production step and
    all three canonical outcomes; there is no generated evaluator. -/
example
    {State Result : Type}
    {semanticProgram : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 semanticProgram)
    (pre : State)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) :
    TypedCallableRelationV1 encodeState encodeResult subject pre invocation
        responses vault outcome ↔
      ∃ logicalPre,
        encodeState pre = .ok logicalPre ∧
          match outcome with
          | .returned post value effects =>
              ∃ logicalPost,
                encodeState post = .ok logicalPost ∧
                  stepReferenceSliceV1 subject.admitted logicalPre invocation
                      responses vault =
                    .returned logicalPost (encodeResult value) effects
          | .reverted reason =>
              stepReferenceSliceV1 subject.admitted logicalPre invocation
                  responses vault =
                .reverted reason logicalPre
          | .trapped fault =>
              stepReferenceSliceV1 subject.admitted logicalPre invocation
                  responses vault =
                .trapped fault logicalPre :=
  by
    unfold TypedCallableRelationV1
    rfl

/- Initializer authoring has a separate production lifecycle pre-state. It is
   not emitted as an ordinary initialized callable relation. -/
program TypedInitializerSurface where
  state count : UInt64
  init(seed : UInt64) do
    count := seed
  view get() : UInt64 do
    return count
  invariant safe : true
  proof safe using TypedInitializerSurfaceProof.safe

#check TypedInitializerSurface.Model.LifecycleState
#check TypedInitializerSurface.Model.initialLifecycleState
#check TypedInitializerSurface.Model.init.invocation
#check TypedInitializerSurface.Model.init.Result
#check TypedInitializerSurface.Model.init.encodeResult
#check TypedInitializerSurface.Model.init.decodeResult
#check TypedInitializerSurface.Model.init.decode_encode_result
#check TypedInitializerSurface.Model.init.decodeResult_complete_of_conforms
#check TypedInitializerSurface.Model.init.decodeResult_complete_of_returned
#check TypedInitializerSurface.Model.init.decodeState_complete_of_returned
#check TypedInitializerSurface.Model.init.encodeResult_injective
#check TypedInitializerSurface.Model.init.Outcome
#check TypedInitializerSurface.Model.init.Transition
#check TypedInitializerSurface.Model.init.transition_returned_of_step
#check TypedInitializerSurface.Model.init.transition_reverted_of_step
#check TypedInitializerSurface.Model.init.transition_trapped_of_step
#check TypedInitializerSurface.Model.init.transition_exists
#check TypedInitializerSurface.Model.init.outcome_unique
#check TypedInitializerSurface.Model.get.Transition
#check TypedInitializerSurface.Model.safe

/-- Initializer lifecycle input remains a separate type: invariant predicates
    are properties only of initialized generated business states. -/
example : TypedInitializerSurface.Model.State → Prop :=
  TypedInitializerSurface.Model.safe

example : TypedInitializerSurface.Model.init.invocation 7 #[] = ({
    callableId := 0
    args := #[{ typeId := 1, valueBytes := encodeU64le 7 }]
    context := #[]
  } : InvocationV1) := rfl

example :
    TypedInitializerSurface.Proof.subjectDataV1.callables[0]?.map
        (fun callable => callable.kind) =
      some CallableKindV1.initializer := rfl

example : TypedInitializerSurface.Model.get.invocation #[] = ({
    callableId := 1
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

/-- The generated lifecycle carrier is definitionally bound to the exact
    production initial-state constructor. -/
example (pre : TypedInitializerSurface.Model.LifecycleState) :
    initialLogicalStateV1 TypedInitializerSurface.Proof.subjectProgramV1 =
      .ok pre.logical :=
  pre.hinitial

/-- Expanding the initializer relation reaches the sole generic production
    Reference relation, with different pre/post state types. -/
example
    (subject : TypedInitializerSurface.Model.ReferenceSubject)
    (pre : TypedInitializerSurface.Model.LifecycleState)
    (seed : UInt64)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedInitializerSurface.Model.init.Outcome) :
    TypedInitializerSurface.Model.init.Transition
        subject pre seed context responses vault outcome ↔
      TypedInitializerRelationV1
        TypedInitializerSurface.Model.encodeState
        TypedInitializerSurface.Model.init.encodeResult subject pre
        (TypedInitializerSurface.Model.init.invocation seed context)
        responses vault outcome := by
  rfl

/-- The generic initializer relation itself unfolds directly to the production
    step in every outcome branch; it does not hide a generated evaluator. -/
example
    {State Result : Type}
    {semanticProgram : SemanticProgramV1}
    (encodeState : State → Except SemanticWireErrorV1 LogicalStateV1)
    (encodeResult : Result → Option ReferenceValueV1)
    (subject : AdmittedSubjectV1 semanticProgram)
    (pre : InitialLifecycleStateV1 semanticProgram)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (outcome : TypedOutcomeV1 State Result) :
    TypedInitializerRelationV1 encodeState encodeResult subject pre invocation
        responses vault outcome ↔
      match outcome with
      | .returned post value effects =>
          ∃ logicalPost,
            encodeState post = .ok logicalPost ∧
              stepReferenceSliceV1 subject.admitted pre.logical invocation
                  responses vault =
                .returned logicalPost (encodeResult value) effects
      | .reverted reason =>
          stepReferenceSliceV1 subject.admitted pre.logical invocation
              responses vault =
            .reverted reason pre.logical
      | .trapped fault =>
          stepReferenceSliceV1 subject.admitted pre.logical invocation
              responses vault =
            .trapped fault pre.logical := by
  unfold TypedInitializerRelationV1
  rfl

/- Initializer invocation identity comes from the lowered callable row rather
   than assuming source `init` is callable zero. -/
program NonzeroInitializerSurface where
  state count : UInt64
  view get() : UInt64 do
    return count
  init(seed : UInt64) do
    count := seed
  invariant safe : true
  proof safe using NonzeroInitializerSurfaceProof.safe

example : NonzeroInitializerSurface.Model.get.invocation #[] = ({
    callableId := 0
    args := #[]
    context := #[]
  } : InvocationV1) := rfl

example : NonzeroInitializerSurface.Model.init.invocation 9 #[] = ({
    callableId := 1
    args := #[{ typeId := 1, valueBytes := encodeU64le 9 }]
    context := #[]
  } : InvocationV1) := rfl

example :
    NonzeroInitializerSurface.Proof.subjectDataV1.callables[1]?.map
        (fun callable => callable.kind) =
      some CallableKindV1.initializer := rfl

/- An initializer outside the supported typed parameter subset withholds only
   the optional initializer lifecycle surface. Supported ordinary callables
   continue to receive initialized-state relations. -/
program UnsupportedInitializerModelSurface where
  state count : UInt64
  init(_seed : UInt128) do
    count := 0
  view get() : UInt64 do
    return count
  invariant safe : true
  proof safe using UnsupportedInitializerModelSurfaceProof.safe

#check UnsupportedInitializerModelSurface.Model.State
#check UnsupportedInitializerModelSurface.Model.get.Transition

run_cmd do
  let env ← getEnv
  let lifecycleState :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInitializerModelSurface.Model.LifecycleState
  if env.contains lifecycleState then
    throwError "unsupported initializer params must not emit a lifecycle state surface"
  let initializerTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInitializerModelSurface.Model.init.Transition
  if env.contains initializerTransition then
    throwError "unsupported initializer params must not emit a typed transition relation"

/- Unit is represented by `none` on the canonical Reference result surface.
    A declared-revert entry supplies an accepted lowering path for exercising
    the generated Unit relation without inventing a Unit-valued return literal. -/
program TypedUnitCallableSurface where
  state count : UInt64
  error Nope
  entry clear() do
    revert Nope()
  invariant safe : true
  proof safe using TypedUnitCallableSurfaceProof.safe

#check TypedUnitCallableSurface.Model.clear.invocation
#check TypedUnitCallableSurface.Model.clear.invocation_complete_of_ready
#check TypedUnitCallableSurface.Model.clear.Result
#check TypedUnitCallableSurface.Model.clear.encodeResult
#check TypedUnitCallableSurface.Model.clear.decodeResult
#check TypedUnitCallableSurface.Model.clear.decode_encode_result
#check TypedUnitCallableSurface.Model.clear.decodeResult_complete_of_conforms
#check TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_conforms
#check TypedUnitCallableSurface.Model.clear.decodeResult_complete_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeState_complete_of_returned
#check TypedUnitCallableSurface.Model.clear.decodeState_existsUnique_of_returned
#check TypedUnitCallableSurface.Model.clear.encodeResult_injective
#check TypedUnitCallableSurface.Model.clear.Outcome
#check TypedUnitCallableSurface.Model.clear.Transition
#check TypedUnitCallableSurface.Model.clear.transition_returned_of_step
#check TypedUnitCallableSurface.Model.clear.transition_reverted_of_step
#check TypedUnitCallableSurface.Model.clear.transition_trapped_of_step
#check TypedUnitCallableSurface.Model.clear.transition_exists
#check TypedUnitCallableSurface.Model.clear.outcome_unique

example : TypedUnitCallableSurface.Model.clear.Outcome =
    TypedOutcomeV1 TypedUnitCallableSurface.Model.State Unit := rfl

example : TypedUnitCallableSurface.Model.clear.decodeResult
    (TypedUnitCallableSurface.Model.clear.encodeResult ()) = .ok () :=
  TypedUnitCallableSurface.Model.clear.decode_encode_result ()

example
    (referenceValue : Option ReferenceValueV1)
    (hconforms :
      ReferenceResultConformsV1 TypedUnitCallableSurface.Proof.subjectDataV1
        (TypedUnitCallableSurface.Proof.subjectDataV1.callables[0]'(by decide)).result
        referenceValue) :
    ∃ value : TypedUnitCallableSurface.Model.clear.Result,
      TypedUnitCallableSurface.Model.clear.decodeResult referenceValue = .ok value ∧
        ∀ other : TypedUnitCallableSurface.Model.clear.Result,
          TypedUnitCallableSurface.Model.clear.decodeResult referenceValue = .ok other →
            value = other :=
  TypedUnitCallableSurface.Model.clear.decodeResult_existsUnique_of_conforms
    referenceValue hconforms

example : TypedUnitCallableSurface.Model.clear.decodeResult (some {
    typeId := 0
    valueBytes := ByteArray.empty
  }) = .error .nonCanonical := by
  rfl

program UnsupportedCallableModelSurface where
  state count : UInt64
  entry addWide(delta : UInt128) : UInt64 do
    return count
  view alive() : Bool do
    return true
  entry Outcome() : UInt64 do
    return count
  invariant safe : true
  proof safe using UnsupportedCallableModelSurfaceProof.safe

#check UnsupportedCallableModelSurface.Model.State
#check UnsupportedCallableModelSurface.Model.alive.Transition

run_cmd do
  let env ← getEnv
  let unsupportedTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedCallableModelSurface.Model.addWide.Transition
  if env.contains unsupportedTransition then
    throwError "unsupported callable params must not emit a typed transition relation"
  let reservedTransition :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedCallableModelSurface.Model.Outcome.Transition
  if env.contains reservedTransition then
    throwError "reserved Model surface names must not emit a callable transition relation"

/- `rec` is legal in the DSL but owned by generated Lean structures. The
    existing program and Proof surfaces must keep elaborating; only the optional
    typed Model surface is withheld. -/
program ModelReservedStateName where
  state «rec» : UInt64
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe preserving using ModelReservedStateNameProof.safe

#check ModelReservedStateName.Proof.subjectProgramV1
#check ModelReservedStateName.Proof.subjectDataV1
#check ModelReservedStateName.ProofPreserving.safe

run_cmd do
  let env ← getEnv
  let modelStateName :=
    `Tests.Language.InlineProofAuthoringV1.ModelReservedStateName.Model.State
  if env.contains modelStateName then
    throwError "reserved structure field name must withhold only the Model surface"
  let invariantBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ModelReservedStateName.Model.Invariant.safe_iff_eval
  if env.contains invariantBridgeName then
    throwError "unsupported typed state must not emit a dangling invariant bridge"
  let typedPreservationName :=
    `Tests.Language.InlineProofAuthoringV1.ModelReservedStateName.ProofPreserving.safe.callable0TypedReturnedV1
  if env.contains typedPreservationName then
    throwError "unsupported typed state must not emit a dangling preservation bridge"

/- A generated-root collision with an invariant name withholds only that
   optional typed invariant predicate/bridge, preserving Proof subject aliases. -/
program ReservedInvariantModelSurface where
  state count : UInt64
  view alive() : Bool do
    return true
  invariant Outcome : true
  invariant Invariant : true
  invariant safe : true
  proof Outcome using ReservedInvariantModelSurfaceProof.holds
  proof Invariant using ReservedInvariantModelSurfaceProof.namespaceCollision
  proof safe using ReservedInvariantModelSurfaceProof.safe

#check ReservedInvariantModelSurface.Proof.subjectProgramV1
#check ReservedInvariantModelSurface.Proof.Outcome
#check ReservedInvariantModelSurface.Proof.Invariant
#check ReservedInvariantModelSurface.Proof.safe
#check ReservedInvariantModelSurface.Model.State
#check ReservedInvariantModelSurface.Model.safe
#check ReservedInvariantModelSurface.Model.Invariant.safe_iff_eval

/-- Filtering reserved Model names must not renumber surviving evaluator rows. -/
example (typedState : ReservedInvariantModelSurface.Model.State) :
    ReservedInvariantModelSurface.Model.safe typedState =
      TypedInvariantV1 ReservedInvariantModelSurface.Model.encodeState
        ReservedInvariantModelSurface.Proof.subjectProgramV1 2 typedState := rfl

example
    (typedState : ReservedInvariantModelSurface.Model.State)
    (logicalState : LogicalStateV1)
    (hencode :
      ReservedInvariantModelSurface.Model.encodeState typedState =
        .ok logicalState) :
    ReservedInvariantModelSurface.Model.safe typedState ↔
      evalInvariantV1 ReservedInvariantModelSurface.Proof.subjectProgramV1 2
          logicalState = .returnedTrue :=
  ReservedInvariantModelSurface.Model.Invariant.safe_iff_eval
    typedState logicalState hencode

run_cmd do
  let env ← getEnv
  let outcomeBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ReservedInvariantModelSurface.Model.Invariant.Outcome_iff_eval
  if env.contains outcomeBridgeName then
    throwError "reserved Model invariant name must not emit an evaluator bridge"
  let namespaceBridgeName :=
    `Tests.Language.InlineProofAuthoringV1.ReservedInvariantModelSurface.Model.Invariant.Invariant_iff_eval
  if env.contains namespaceBridgeName then
    throwError "Model.Invariant namespace collision must not emit an evaluator bridge"

/- Accepted state shapes outside the current generated scalar subset must keep
   their Proof aliases while withholding the whole optional Model surface. -/
program UnsupportedInvariantStateSurface where
  state wide : UInt128
  view alive() : Bool do
    return true
  invariant safe : true
  proof safe using UnsupportedInvariantStateSurfaceProof.safe

#check UnsupportedInvariantStateSurface.Proof.subjectProgramV1
#check UnsupportedInvariantStateSurface.Proof.safe

run_cmd do
  let env ← getEnv
  let modelStateName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.State
  if env.contains modelStateName then
    throwError "unsupported state scalar must not emit a typed Model.State"
  let predicateName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.safe
  if env.contains predicateName then
    throwError "unsupported state scalar must not emit a typed invariant predicate"
  let bridgeName :=
    `Tests.Language.InlineProofAuthoringV1.UnsupportedInvariantStateSurface.Model.Invariant.safe_iff_eval
  if env.contains bridgeName then
    throwError "unsupported state scalar must not emit a dangling invariant bridge"

/-- Bridge has the exact product Prop-alias conclusion under a wire-trace
    premise (no free hyps beyond `t`). -/
example :
    (Proofed.Proof.generatedSafeV1_of_wireTrace :
      SimpleClosureWireTraceV1
          Proofed.Proof.simpleClosureParamsV1
          Proofed.Proof.subjectBytesV1 →
        Proofed.Proof.safe) =
      Proofed.Proof.generatedSafeV1_of_wireTrace :=
  rfl

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let subject := Proofed.Proof.subjectProgramV1
  expect (subject.canonicalBytes.size > 0)
    "inline subjectProgramV1 must embed non-empty product bytes (transparent spine)"
  expect (Proofed.Proof.subjectBytesV1.size == subject.canonicalBytes.size)
    "subjectBytesV1 matches subjectProgramV1 carrier"
  -- mig-a3-elab: structured subjectData encodes to the same product bytes.
  match encodeSemanticProgramDataV1 Proofed.Proof.subjectDataV1 with
  | .ok encoded =>
      expect (encoded == Proofed.Proof.subjectBytesV1)
        "subjectDataV1 encode must recover subjectBytesV1"
  | .error error =>
      throw <| IO.userError s!"subjectDataV1 encode failed: {repr error}"
  expect (Proofed.Proof.generatedSafeV1Name == "generatedSafeV1")
    "generated theorem product name for inv safe"
  expect (generatedSimpleClosureTheoremNameV1 "safe" ==
      Proofed.Proof.generatedSafeV1Name)
    "naming helper matches elaborator Name def"
  match TypedStateSurface.Model.decodeState typedStateLogicalV1 with
  | .ok decoded =>
      expect (decoded == typedStateSampleV1)
        "typed state decode must preserve all fields in source order"
  | .error error =>
      throw <| IO.userError s!"typed state decode failed: {repr error}"
  let missingSlot : LogicalStateV1 := {
    initialized := true
    canonicalValues := encodeU32le 8 ++ encodeU64le 7
  }
  match TypedStateSurface.Model.decodeState missingSlot with
  | .ok _ => throw <| IO.userError "typed state decode must reject a missing slot"
  | .error _ => pure ()
  let extraSlot : LogicalStateV1 := {
    initialized := true
    canonicalValues := typedStateLogicalV1.canonicalValues ++ encodeU32le 0
  }
  match TypedStateSurface.Model.decodeState extraSlot with
  | .ok _ => throw <| IO.userError "typed state decode must reject trailing slot bytes"
  | .error _ => pure ()
  match validateSemanticProgramV1 subject with
  | .error error =>
      throw <| IO.userError s!"generated inline proof subject invalid: {repr error}"
  | .ok data =>
      expect (data == Proofed.Proof.subjectDataV1)
        "subjectDataV1 must equal structure-gated validated data"
      expect (data.invariants.size == 1) "generated invariant count"
      let invariant ← match data.invariants[0]? with
        | some value => pure value
        | none => throw <| IO.userError "generated invariant missing"
      expect (invariant.name == "safe") "generated invariant name"
      expect (invariant.id == 0) "generated invariant ordinal"
      let callable ← match data.callables[invariant.callableId.toNat]? with
        | some value => pure value
        | none => throw <| IO.userError "generated invariant callable missing"
      expect (callable.kind == CallableKindV1.invariant)
        "generated invariant callable kind"
      expect (callable.invariantSteps == some 3) "literal-true invariant fuel is 3"
      -- Happy path: ordinal 0 returns true on initialized empty state.
      let st ← match initialLogicalStateV1 subject with
        | .ok s => pure { s with initialized := true }
        | .error e => throw <| IO.userError s!"initial state: {repr e}"
      expect (stateConformsBoolV1 subject st) "conforming empty state"
      match evalInvariantV1 subject 0 st with
      | .returnedTrue => pure ()
      | other => throw <| IO.userError s!"safe ordinal must return true: {repr other}"
      -- Byte mutation of the generated subject fails closed.
      let mutated :=
        Id.run do
          let mut out := subject.canonicalBytes
          let b0 := out.get! 0
          out := out.set! 0 (b0 <<< 1 ||| 1)
          pure out
      expect ((subject.canonicalBytes == mutated) == false) "subject mutation changes bytes"
      match validateSemanticProgramV1 ⟨mutated⟩ with
      | .ok _ => throw <| IO.userError "mutated inline subject must not validate"
      | .error _ => pure ()
      -- Ordinal mutation: OOR traps.
      match evalInvariantV1 subject 1 st with
      | .trapped => pure ()
      | other => throw <| IO.userError s!"OOR ordinal must trap: {repr other}"
  -- Field-comparison product initial: ordinal 2 (.ne) is false at all-zero.
  let fe := TypedInvariantFieldEqualitySurface.Proof.subjectProgramV1
  match initialLogicalStateV1 fe with
  | .error e =>
      throw <| IO.userError s!"field-comparison initial state: {repr e}"
  | .ok st =>
      match evalInvariantV1 fe 2 st with
      | .returnedTrue =>
          throw <| IO.userError
            "field-comparison ordinal 2 must not hold on all-zero init"
      | _ => pure ()
  IO.println "Tests.Language.InlineProofAuthoringV1: ok"

end Tests.Language.InlineProofAuthoringV1
