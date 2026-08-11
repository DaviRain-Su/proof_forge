import ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1
import ProofForgeV2.Semantic.StateModelV1

/-!
  Generic Reference preservation for the exact name-parameterized
  initializer/view/two-field-equality family. Execution and invariant
  evaluation remain exclusively in the production Reference semantics.
-/

namespace ProofForgeV2.Semantic.InitializerViewEqualityPreservationV1

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
    (state0Name state1Name viewName invariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hinvariantName : validateIdentifierComponent invariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hviewInvariant : viewName ≠ invariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1
        qualifiedName state0Name state1Name viewName invariantName)
    (hbody : encodeSemanticProgramDataBodyV1 subjectData = .ok bytes) :
    PreservationTheoremV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 0 := by
  let data :=
    ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1
      qualifiedName state0Name state1Name viewName invariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily : encodeSemanticProgramDataBodyV1 data = .ok bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal : ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.StructureLegalV1
      qualifiedName state0Name state1Name viewName invariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hviewName, hinvariantName,
      hstate01, hviewInvariant⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.structureV1
        qualifiedName state0Name state1Name viewName invariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name viewName invariantName
        hstate0Name hstate1Name hviewName hinvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure hbodyFamily hinvert
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.referenceAdmissionV1
        qualifiedName state0Name state1Name viewName invariantName
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks program data hvalidate hadmission
  have hadmittedData : admitted.data = data :=
    (admitReferenceProgramSliceV1_ok_implies program data admitted hvalidate hadmit).2
  have hordinal : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
    rw [SemanticProgramV1.invariants_eq_of_validate program data hvalidate]
    change 0 < 1
    decide
  have hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    rfl
  have hinitializerReturned :
      ∀ (pre post : LogicalStateV1)
        (invocation : InvocationV1)
        (responses : ExternalResponsesV1)
        (vault : ReferenceVaultSeedV1)
        (overlay : Array ByteArray)
        (context : Array ContextInputV1)
        (value : Option ReferenceValueV1)
        (effects : Array OrderedEffectV1),
        gateInvocation admitted pre invocation =
          .ready (initializerStoreZeroTwoCallableV1 0 0 1)
            overlay context true →
        stepReferenceSliceV1 admitted pre invocation responses vault =
          .returned post value effects →
        evalInvariantV1 program 0 post = .returnedTrue := by
    intro pre post invocation responses vault overlay context value effects
      hgate hstep
    have hdecode := gateInvocation_ready_decodeV1 admitted pre invocation
      (initializerStoreZeroTwoCallableV1 0 0 1) overlay context true hgate
    rw [hadmittedData] at hdecode
    have hoverlaySize := decodeLogicalStateValuesV1_size data pre overlay hdecode
    have hoverlaySizeTwo : overlay.size = 2 := by
      simpa [data,
        ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1]
        using hoverlaySize
    obtain ⟨before0, before1, hoverlayEq⟩ :
        ∃ before0 before1, overlay = #[before0, before1] := by
      exact ⟨overlay[0]'(by omega), overlay[1]'(by omega),
        Array.ext (by simp [hoverlaySizeTwo]) (by
          intro i hi hj
          match i with | 0 => simp | 1 => simp | n + 2 => omega)⟩
    have hpostEncode : encodeLogicalStateValuesV1 data true
        #[zero8BytesV1, zero8BytesV1] = .ok post := by
      apply postEncode_of_readyInitializerStoreZeroTwoV1 admitted pre post
        invocation data before0 before1 0 1 state0Name state1Name 0 context
        responses vault value effects hadmittedData
      · rfl
      · rfl
      · rfl
      · rfl
      · exact hcanZero
      · simpa [hoverlayEq] using hgate
      · exact hstep
    have hdecodePost := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true #[zero8BytesV1, zero8BytesV1] post hpostEncode
    have hpostInitialized : post.initialized = true :=
      LogicalStateV1.initialized_of_encodeLogicalStateValuesV1 data true
        #[zero8BytesV1, zero8BytesV1] post hpostEncode
    exact (evalInvariantV1_returnedTrue_iff_two_state_bytes_eq program data 0 0
      invariantName post #[zero8BytesV1, zero8BytesV1] zero8BytesV1
      zero8BytesV1 2 0 2 0 1 (some invariantName) .public_ .public_
      .public_ state0Name state1Name hvalidate hpostInitialized hdecodePost
      rfl rfl rfl rfl rfl rfl rfl).2 rfl
  have hhasInitializer : HasInitializerV1 program := by
    refine ⟨0, ?_⟩
    change isInitializerCallableIdV1 program 0 = true
    unfold isInitializerCallableIdV1
    rw [hvalidate]
    rfl
  let initial : LogicalStateV1 := {
    initialized := false
    canonicalValues := doubleUint64CanonicalV1 zero8BytesV1 zero8BytesV1
  }
  have hinitial : initialLogicalStateV1 program = .ok initial := by
    simpa [initial, data, zero8BytesV1] using
      initialLogicalStateV1_double_uint64_eq_ok program data
        (StateDeclV1.mk 0 state0Name 0 .public_)
        (StateDeclV1.mk 1 state1Name 0 .public_)
        (TypeDeclV1.mk 0 none (.uint 64)) true hvalidate rfl rfl rfl rfl
        (by
          simp [data,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1,
            show
              ((initializerStoreZeroTwoCallableV1 0 0 1).kind ==
                CallableKindV1.initializer) = true by rfl])
        (by rfl) (by rfl)
  have hbaseWithInitializer :
      PreservationBaseWithInitializerV1 program 0 admitted := by
    apply preservationBaseWithInitializerV1_of_returnedV1 program 0 admitted
      initial hinitial
    intro invocation responses vault post value effects hinitializer hstep
    have hready := stepReturnedImpliesGateReadyV1 admitted initial invocation
      responses vault post value effects hstep
    cases hgate : gateInvocation admitted initial invocation with
    | invalidInvocation =>
        rw [hgate] at hready
        exact False.elim hready
    | lifecycle candidate =>
        rw [hgate] at hready
        exact False.elim hready
    | ready callable overlay context isInitializer =>
        have hlookup :=
          (gateInvocation_ready_callable_lookup admitted initial invocation
            callable overlay context isInitializer hgate).1
        rw [hadmittedData] at hlookup
        unfold IsInitializerInvocationV1 isInitializerInvocationV1 at hinitializer
        unfold isInitializerCallableIdV1 at hinitializer
        rw [hvalidate] at hinitializer
        have hkind : (callable.kind == CallableKindV1.initializer) = true := by
          simpa [hlookup] using hinitializer
        have hindexBound : invocation.callableId.toNat < 3 := by
          exact (Array.getElem?_eq_some_iff.mp hlookup).1
        match hindex : invocation.callableId.toNat with
        | 0 =>
            have hlookup0 := hlookup
            rw [hindex] at hlookup0
            have hcallable : callable = initializerStoreZeroTwoCallableV1 0 0 1 := by
              simpa [data,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
                using hlookup0.symm
            subst callable
            have hisInitializer : isInitializer = true := by
              have hkindInit :=
                (gateInvocation_ready_callable_lookup admitted initial invocation
                  (initializerStoreZeroTwoCallableV1 0 0 1) overlay context
                    isInitializer hgate).2
              change isInitializer = true at hkindInit
              exact hkindInit
            rw [hisInitializer] at hgate
            exact hinitializerReturned initial post invocation responses vault
              overlay context value effects hgate hstep
        | 1 =>
            have hlookup1 := hlookup
            rw [hindex] at hlookup1
            have hcallable : callable = viewLoadCallableV1 1 (some viewName) 0 0 := by
              simpa [data,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
                using hlookup1.symm
            subst callable
            change false = true at hkind
            contradiction
        | 2 =>
            have hlookup2 := hlookup
            rw [hindex] at hlookup2
            have hcallable : callable =
                twoStateCompareInvariantCallableV1 2 (some invariantName)
                  0 2 0 1 .eq .public_ (some 5) := by
              simpa [data,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
                ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
                using hlookup2.symm
            subst callable
            change false = true at hkind
            contradiction
        | n + 3 => omega
  have hbase : PreservationBaseV1 program 0 admitted :=
    preservationBaseV1_of_initializerV1 program 0 admitted hhasInitializer
      hbaseWithInitializer
  have hreturned : PreservationReturnedCallablesV1 program 0 admitted := by
    apply preservationReturnedCallablesV1_of_rowsV1 program 0 admitted data
      hadmittedData
    intro index
    match index with
    | ⟨0, _⟩ =>
      intro pre invocation responses vault overlay context isInitializer post
        value effects hcallableId _hconforms _heval hgate hstep
      have hisInitializer : isInitializer = true := by
        have hkind := (gateInvocation_ready_callable_lookup admitted pre invocation
          data.callables[0] overlay context isInitializer hgate).2
        have hkind' :
            isInitializer =
              ((initializerStoreZeroTwoCallableV1 0 0 1).kind ==
                CallableKindV1.initializer) := by
          simpa [data,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
            using hkind
        change isInitializer = true at hkind'
        exact hkind'
      change gateInvocation admitted pre invocation =
        .ready (initializerStoreZeroTwoCallableV1 0 0 1) overlay context
          isInitializer at hgate
      rw [hisInitializer] at hgate
      exact hinitializerReturned pre post invocation responses vault overlay
        context value effects hgate hstep
    | ⟨1, _⟩ =>
      intro pre invocation responses vault overlay context isInitializer post
        value effects hcallableId _hconforms heval hgate hstep
      have hisInitializer : isInitializer = false := by
        have hkind := (gateInvocation_ready_callable_lookup admitted pre invocation
          data.callables[1] overlay context isInitializer hgate).2
        have hkind' :
            isInitializer =
              ((viewLoadCallableV1 1 (some viewName) 0 0).kind ==
                CallableKindV1.initializer) := by
          simpa [data,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
            using hkind
        change isInitializer = false at hkind'
        exact hkind'
      have hdecode := gateInvocation_ready_decodeV1 admitted pre invocation
        data.callables[1] overlay context isInitializer hgate
      rw [hadmittedData] at hdecode
      have hoverlaySize := decodeLogicalStateValuesV1_size data pre overlay hdecode
      have hoverlayNonempty : 0 < overlay.size := by
        have : overlay.size = 2 := by
          simpa [data,
            ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1]
            using hoverlaySize
        omega
      let loadedBytes := overlay[0]'hoverlayNonempty
      have hloaded : overlay[0]? = some loadedBytes := by
        exact Array.getElem?_eq_getElem hoverlayNonempty
      change gateInvocation admitted pre invocation =
        .ready (viewLoadCallableV1 1 (some viewName) 0 0) overlay context
          isInitializer at hgate
      rw [hisInitializer] at hgate
      have hpostEq := postEqPre_of_readyViewLoadV1 admitted pre post invocation
        data overlay loadedBytes 0 0 state0Name 1 (some viewName) context
        responses vault value effects hadmittedData rfl rfl hloaded hgate hstep
      simpa [hpostEq] using heval
    | ⟨2, _⟩ =>
      intro pre invocation responses vault overlay context isInitializer post
        value effects hcallableId _hconforms _heval hgate _hstep
      simp [gateInvocation, hadmittedData, hcallableId, data,
        ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
        ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1,
        twoStateCompareInvariantCallableV1,
        show (CallableKindV1.invariant == CallableKindV1.initializer) = false by decide,
        show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
        show (CallableKindV1.invariant == CallableKindV1.view) = false by decide]
        at hgate
    | ⟨n + 3, hlt⟩ =>
      have : n + 3 < 3 := by
        simpa [data,
          ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.subjectDataV1,
          ProofForgeV2.Semantic.InitializerViewEqualitySubjectV1.callablesV1]
          using hlt
      omega
  exact preservationTheoremV1_of_callableObligationsV1 program 0 admitted hordinal
    hadmit hbase hreturned

end ProofForgeV2.Semantic.InitializerViewEqualityPreservationV1
