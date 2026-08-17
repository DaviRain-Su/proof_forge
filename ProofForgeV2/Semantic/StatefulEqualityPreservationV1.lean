import ProofForgeV2.Semantic.StatefulEqualitySubjectV1
import ProofForgeV2.Semantic.StateModelV1

/-!
  Generic Reference preservation for the exact name-parameterized
  `StatefulEqualitySubjectV1` family.  This module only composes production
  validation, codec, Reference-machine, invariant, and preservation APIs.
-/

namespace ProofForgeV2.Semantic.StatefulEqualityPreservationV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationPackagingV1
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.StateModelV1
open ProofForgeV2.Semantic.WireV1

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

theorem preservationTheorem_of_subjectBodyV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name entryName parameterName invariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hentryName : validateIdentifierComponent entryName = .ok ())
    (hparameterName : validateIdentifierComponent parameterName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hentryInvariant : entryName ≠ invariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1 qualifiedName
        state0Name state1Name entryName parameterName invariantName)
    (hbody : ProofForgeV2.Semantic.StatefulEqualitySubjectV1.bodyEncodeOkV1
      subjectData bytes) :
    PreservationTheoremV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 0 := by
  let data := ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1
    qualifiedName state0Name state1Name entryName parameterName invariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.bodyEncodeOkV1 data bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal : ProofForgeV2.Semantic.StatefulEqualitySubjectV1.StructureLegalV1
      qualifiedName state0Name state1Name entryName parameterName invariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hentryName, hparameterName,
      hinvariantName, hstate01, hentryInvariant⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.structureV1
        qualifiedName state0Name state1Name entryName parameterName invariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name entryName parameterName invariantName
        hstate0Name hstate1Name hentryName hparameterName hinvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data, ProofForgeV2.Semantic.StatefulEqualitySubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.referenceAdmissionV1
        qualifiedName state0Name state1Name entryName parameterName invariantName
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks program data hvalidate hadmission
  have hadmittedData : admitted.data = data :=
    (admitReferenceProgramSliceV1_ok_implies program data admitted hvalidate hadmit).2
  have hordinal : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
    rw [SemanticProgramV1.invariants_eq_of_validate program data hvalidate]
    change 0 < 1
    decide
  have hnoInitAny : data.callables.any (fun c => c.kind == .initializer) = false := by
    simp [data, ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1,
      storeParameterTwoReturnCallableV1, twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hbaseNoInit : PreservationBaseNoInitializerV1 program 0 := by
    let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
    let initial : LogicalStateV1 := {
      initialized := true
      canonicalValues := doubleUint64CanonicalV1 zero zero
    }
    have hinitial : initialLogicalStateV1 program = .ok initial := by
      simpa [initial, zero, data] using
        initialLogicalStateV1_double_uint64_no_initializer_eq_ok program data
          (StateDeclV1.mk 0 state0Name 1 .public_)
          (StateDeclV1.mk 1 state1Name 1 .public_)
          (TypeDeclV1.mk 1 none (.uint 64)) hvalidate rfl rfl rfl rfl
          hnoInitAny rfl rfl
    have hencode : encodeLogicalStateValuesV1 data true #[zero, zero] = .ok initial := by
      simpa [initial, zero] using
        encodeLogicalStateValuesV1_double_uint64_eq_ok data
          (StateDeclV1.mk 0 state0Name 1 .public_)
          (StateDeclV1.mk 1 state1Name 1 .public_) zero zero true
          rfl rfl rfl rfl rfl
    have hdecode := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true #[zero, zero] initial hencode
    have hconforms : StateConformsV1 program initial :=
      stateConformsV1_intro_of_validate_eq_ok program data initial #[zero, zero]
        hvalidate rfl hdecode
    have heval : evalInvariantV1 program 0 initial = .returnedTrue :=
      (evalInvariantV1_returnedTrue_iff_two_state_bytes_eq program data 0 0
        invariantName initial #[zero, zero] zero zero 1 1 0 0 1
        (some invariantName) .public_ .public_ .public_ state0Name state1Name
        hvalidate rfl hdecode rfl rfl rfl rfl rfl rfl rfl).2 rfl
    exact ⟨initial, hinitial, hconforms, heval⟩
  have hreturned : PreservationReturnedCallablesV1 program 0 admitted := by
    apply preservationReturnedCallablesV1_of_rowsV1 program 0 admitted data hadmittedData
    intro index
    match index with
    | ⟨0, _⟩ =>
      intro pre invocation responses vault overlay context isInitializer post value effects
        hcallableId _hconforms _heval hgate hstep
      have hisInitializer : isInitializer = false := by
        have hk := (gateInvocation_ready_callable_lookup admitted pre invocation
          data.callables[0] overlay context isInitializer hgate).2
        have hkFalse : (data.callables[0].kind == CallableKindV1.initializer) = false := by
          change (CallableKindV1.entry == CallableKindV1.initializer) = false
          decide
        exact hk.trans hkFalse
      obtain ⟨argument, harg⟩ := gateInvocation_ready_uint64_argumentV1 admitted pre
        invocation data.callables[0] overlay context isInitializer 0 (by change 0 < 1; decide) 1
        (by rfl) ({ id := 1, name := none, shape := .uint 64 } : TypeDeclV1)
        (by rw [hadmittedData]; rfl) (by rfl) hgate
      have harity := gateInvocation_ready_arity admitted pre invocation data.callables[0]
        overlay context isInitializer hgate
      have hinvocation : invocation = {
          callableId := 0
          args := #[{ typeId := 1, valueBytes := encodeU64le argument }]
          context := invocation.context } := by
        cases invocation with
        | mk cid args ctx =>
          simp only at hcallableId harg harity ⊢
          subst cid
          congr 1
          apply Array.ext_getElem?
          intro i
          match i with
          | 0 => simpa using harg
          | n + 1 =>
            have hsize : args.size = 1 := by
              simpa [data, ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
                ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1,
                storeParameterTwoReturnCallableV1] using harity
            simp [Array.getElem?_eq_none, hsize]
      have hdecode := (gateInvocation_ready_noninit_decode admitted pre invocation
        data.callables[0] overlay context (by simpa [hisInitializer] using hgate)).1
      rw [hadmittedData] at hdecode
      have hoverlay : overlay.size = 2 := by
        have hs := decodeLogicalStateValuesV1_size data pre overlay hdecode
        simpa [data, ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1] using hs
      obtain ⟨before0, before1, hoverlayEq⟩ : ∃ b0 b1, overlay = #[b0, b1] := by
        exact ⟨overlay[0]'(by omega), overlay[1]'(by omega), Array.ext (by simp [hoverlay]) (by
          intro i hi hj
          match i with | 0 => simp | 1 => simp | n + 2 => omega)⟩
      have hcanonical : validateValueBytesV1 data.types 1 (encodeU64le argument) = .ok () := by
        apply validateValueBytesV1_uint64_of_size data.types 1
          ({ id := 1, name := none, shape := .uint 64 } : TypeDeclV1)
        · rfl
        · rfl
        · exact encodeU64le_size argument
      have hpostEncode : encodeLogicalStateValuesV1 data true
          #[encodeU64le argument, encodeU64le argument] = .ok post := by
        apply stepReferenceSliceV1_ready_store_parameter_two_returned_post_encode
          admitted pre post data before0 before1 (encodeU64le argument) 1 state0Name
          state1Name parameterName 0 (some entryName) invocation.context context
          responses vault value effects hadmittedData rfl rfl rfl hcanonical
        · change gateInvocation admitted pre invocation = .ready
            (storeParameterTwoReturnCallableV1 0 (some entryName) parameterName
              1 0 1 .public_) overlay context isInitializer at hgate
          rw [hinvocation, hoverlayEq, hisInitializer] at hgate
          exact hgate
        · rw [hinvocation] at hstep
          exact hstep
      have hdecodePost := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1 data true
        #[encodeU64le argument, encodeU64le argument] post hpostEncode
      have hpostInitialized : post.initialized = true :=
        LogicalStateV1.initialized_of_encodeLogicalStateValuesV1 data true
          #[encodeU64le argument, encodeU64le argument] post hpostEncode
      exact (evalInvariantV1_returnedTrue_iff_two_state_bytes_eq program data 0 0
        invariantName post #[encodeU64le argument, encodeU64le argument]
        (encodeU64le argument) (encodeU64le argument) 1 1 0 0 1
        (some invariantName) .public_ .public_ .public_ state0Name state1Name
        hvalidate hpostInitialized hdecodePost rfl rfl rfl rfl rfl rfl rfl).2 rfl
    | ⟨1, _⟩ =>
      intro pre invocation responses vault overlay context isInitializer post value effects
        hcallableId _hconforms _heval hgate _hstep
      simp [gateInvocation, hadmittedData, hcallableId, data,
        ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
        ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1,
        twoStateCompareInvariantCallableV1,
        show (CallableKindV1.invariant == CallableKindV1.initializer) = false by decide,
        show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
        show (CallableKindV1.invariant == CallableKindV1.view) = false by decide] at hgate
    | ⟨n + 2, hlt⟩ =>
      have : n + 2 < 2 := by
        simpa [data, ProofForgeV2.Semantic.StatefulEqualitySubjectV1.subjectDataV1,
          ProofForgeV2.Semantic.StatefulEqualitySubjectV1.callablesV1] using hlt
      omega
  exact preservationTheoremV1_of_callableObligationsV1 program 0 admitted hordinal hadmit
    (preservationBaseV1_of_noInitializerV1 program 0 admitted
      (not_hasInitializerV1_of_validate_and_any_eq_false program data hvalidate hnoInitAny)
      hbaseNoInit) hreturned

end ProofForgeV2.Semantic.StatefulEqualityPreservationV1
