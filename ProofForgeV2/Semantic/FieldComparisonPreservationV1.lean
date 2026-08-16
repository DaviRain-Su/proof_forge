import ProofForgeV2.Semantic.FieldComparisonSubjectV1
import ProofForgeV2.Semantic.StateModelV1
import ProofForgeV2.Semantic.SubjectDataBridgeV1

/-!
  Generic Reference preservation for the exact name-parameterized
  `FieldComparisonSubjectV1` family.  Only invariant ordinals 0 (literal-true)
  and 1 (two-state `.eq` on state ids 1 and 2) are packaged: the product
  all-zero initial state does not satisfy ordinal 2 (two-state `.ne` on the
  same pair).
-/

namespace ProofForgeV2.Semantic.FieldComparisonPreservationV1

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

private theorem returnedCallablesV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (program : SemanticProgramV1)
    (admitted : AdmittedReferenceSliceV1)
    (ordinal : InvariantOrdinalV1)
    (hadmittedData : admitted.data =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName) :
    PreservationReturnedCallablesV1 program ordinal admitted := by
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  have hadmittedData' : admitted.data = data := by
    simpa [data] using hadmittedData
  apply preservationReturnedCallablesV1_of_rowsV1 program ordinal admitted data
    hadmittedData'
  intro index
  match index with
  | ⟨0, _⟩ =>
    intro pre invocation responses vault overlay context isInitializer post
      value effects hcallableId _hconforms heval hgate hstep
    have hisInitializer : isInitializer = false := by
      have hk := (gateInvocation_ready_callable_lookup admitted pre invocation
        data.callables[0] overlay context isInitializer hgate).2
      have hkFalse :
          (data.callables[0].kind == CallableKindV1.initializer) = false := by
        change (CallableKindV1.view == CallableKindV1.initializer) = false
        decide
      exact hk.trans hkFalse
    have _hdecode := gateInvocation_ready_decodeV1 admitted pre invocation
      data.callables[0] overlay context isInitializer hgate
    rw [hadmittedData'] at _hdecode
    change gateInvocation admitted pre invocation =
      .ready (literalReturnCallableV1 0 .view (some viewName) 1 (encodeU8 1)
        .public_ none) overlay context isInitializer at hgate
    rw [hisInitializer] at hgate
    have hpostEq := postEqPre_of_readyLiteralReturnV1 admitted pre post
      invocation data overlay 1 (encodeU8 1) 0 (some viewName) context
      responses vault value effects hadmittedData' rfl rfl hgate hstep
    simpa [hpostEq] using heval
  | ⟨1, _⟩ =>
    intro pre invocation responses vault overlay context isInitializer post
      value effects hcallableId _hconforms _heval hgate _hstep
    simp [gateInvocation, hadmittedData', hcallableId, data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      literalReturnCallableV1,
      show (CallableKindV1.invariant == CallableKindV1.initializer) = false
        by decide,
      show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
      show (CallableKindV1.invariant == CallableKindV1.view) = false by decide]
      at hgate
  | ⟨2, _⟩ =>
    intro pre invocation responses vault overlay context isInitializer post
      value effects hcallableId _hconforms _heval hgate _hstep
    simp [gateInvocation, hadmittedData', hcallableId, data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      twoStateCompareInvariantCallableV1,
      show (CallableKindV1.invariant == CallableKindV1.initializer) = false
        by decide,
      show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
      show (CallableKindV1.invariant == CallableKindV1.view) = false by decide]
      at hgate
  | ⟨3, _⟩ =>
    intro pre invocation responses vault overlay context isInitializer post
      value effects hcallableId _hconforms _heval hgate _hstep
    simp [gateInvocation, hadmittedData', hcallableId, data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      twoStateCompareInvariantCallableV1,
      show (CallableKindV1.invariant == CallableKindV1.initializer) = false
        by decide,
      show (CallableKindV1.invariant == CallableKindV1.entry) = false by decide,
      show (CallableKindV1.invariant == CallableKindV1.view) = false by decide]
      at hgate
  | ⟨n + 4, hlt⟩ =>
    have : n + 4 < 4 := by
      simpa [data,
        ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
        ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1] using hlt
    omega

theorem preservationTheorem_of_subjectBodyV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName)
    (hbody :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1
        subjectData bytes) :
    PreservationTheoremV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 0 := by
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1 data
        bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.StructureLegalV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hstate2Name, hviewName,
      hliteralInvariantName, heqInvariantName, hneInvariantName, hstate01,
      hstate02, hstate12, hviewLiteral, hviewEq, hviewNe, hliteralEq,
      hliteralNe, heqNe⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
        hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data,
          ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.referenceAdmissionV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks program data hvalidate
      hadmission
  have hadmittedData : admitted.data = data :=
    (admitReferenceProgramSliceV1_ok_implies program data admitted hvalidate
      hadmit).2
  have hordinal : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
    rw [SemanticProgramV1.invariants_eq_of_validate program data hvalidate]
    change 0 < 3
    decide
  have hnoInitAny :
      data.callables.any (fun c => c.kind == .initializer) = false := by
    simp [data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      literalReturnCallableV1, twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hbaseNoInit : PreservationBaseNoInitializerV1 program 0 := by
    let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
    let initial : LogicalStateV1 := {
      initialized := true
      canonicalValues := tripleUint64CanonicalV1 zero zero zero
    }
    have hinitial : initialLogicalStateV1 program = .ok initial := by
      simpa [initial, zero, data] using
        initialLogicalStateV1_triple_uint64_no_initializer_eq_ok program data
          (StateDeclV1.mk 0 state0Name 0 .public_)
          (StateDeclV1.mk 1 state1Name 0 .public_)
          (StateDeclV1.mk 2 state2Name 0 .public_)
          (TypeDeclV1.mk 0 none (.uint 64)) hvalidate rfl rfl rfl rfl
          (by rfl) hnoInitAny rfl rfl rfl
    have hencode : encodeLogicalStateValuesV1 data true
        #[zero, zero, zero] = .ok initial := by
      simpa [initial, zero] using
        encodeLogicalStateValuesV1_triple_uint64_eq_ok data
          (StateDeclV1.mk 0 state0Name 0 .public_)
          (StateDeclV1.mk 1 state1Name 0 .public_)
          (StateDeclV1.mk 2 state2Name 0 .public_)
          zero zero zero true rfl rfl rfl rfl rfl rfl rfl
    have hdecode := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true #[zero, zero, zero] initial hencode
    have hconforms : StateConformsV1 program initial :=
      stateConformsV1_intro_of_validate_eq_ok program data initial
        #[zero, zero, zero] hvalidate rfl hdecode
    have hrun : runInvariantCallableV1 data 1 initial = .returnedTrue :=
      runInvariantCallableV1_eq_returnedTrue_of_single_nullary_literal_true
        data initial #[zero, zero, zero] 1 1 (some literalInvariantName)
        .public_ none rfl hdecode rfl rfl rfl
    have heval : evalInvariantV1 program 0 initial = .returnedTrue :=
      evalInvariantV1_eq_of_validated_selection program data 0
        { id := 0, name := literalInvariantName, callableId := 1 }
        initial #[zero, zero, zero] .returnedTrue hvalidate rfl hdecode rfl
        hrun
    exact ⟨initial, hinitial, hconforms, heval⟩
  have hreturned : PreservationReturnedCallablesV1 program 0 admitted :=
    returnedCallablesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName program
      admitted 0 (by simpa [data] using hadmittedData)
  exact preservationTheoremV1_of_callableObligationsV1 program 0 admitted
    hordinal hadmit
    (preservationBaseV1_of_noInitializerV1 program 0 admitted
      (not_hasInitializerV1_of_validate_and_any_eq_false program data
        hvalidate hnoInitAny)
      hbaseNoInit)
    hreturned

theorem preservationTheorem_of_subjectBodyV1_ord1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName)
    (hbody :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1
        subjectData bytes) :
    PreservationTheoremV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 1 := by
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1 data
        bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.StructureLegalV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hstate2Name, hviewName,
      hliteralInvariantName, heqInvariantName, hneInvariantName, hstate01,
      hstate02, hstate12, hviewLiteral, hviewEq, hviewNe, hliteralEq,
      hliteralNe, heqNe⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
        hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data,
          ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.referenceAdmissionV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks program data hvalidate
      hadmission
  have hadmittedData : admitted.data = data :=
    (admitReferenceProgramSliceV1_ok_implies program data admitted hvalidate
      hadmit).2
  have hordinal : (1 : InvariantOrdinalV1).toNat < program.invariants.size := by
    rw [SemanticProgramV1.invariants_eq_of_validate program data hvalidate]
    change 1 < 3
    decide
  have hnoInitAny :
      data.callables.any (fun c => c.kind == .initializer) = false := by
    simp [data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      literalReturnCallableV1, twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hbaseNoInit : PreservationBaseNoInitializerV1 program 1 := by
    let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
    let initial : LogicalStateV1 := {
      initialized := true
      canonicalValues := tripleUint64CanonicalV1 zero zero zero
    }
    have hinitial : initialLogicalStateV1 program = .ok initial := by
      simpa [initial, zero, data] using
        initialLogicalStateV1_triple_uint64_no_initializer_eq_ok program data
          (StateDeclV1.mk 0 state0Name 0 .public_)
          (StateDeclV1.mk 1 state1Name 0 .public_)
          (StateDeclV1.mk 2 state2Name 0 .public_)
          (TypeDeclV1.mk 0 none (.uint 64)) hvalidate rfl rfl rfl rfl
          (by rfl) hnoInitAny rfl rfl rfl
    have hencode : encodeLogicalStateValuesV1 data true
        #[zero, zero, zero] = .ok initial := by
      simpa [initial, zero] using
        encodeLogicalStateValuesV1_triple_uint64_eq_ok data
          (StateDeclV1.mk 0 state0Name 0 .public_)
          (StateDeclV1.mk 1 state1Name 0 .public_)
          (StateDeclV1.mk 2 state2Name 0 .public_)
          zero zero zero true rfl rfl rfl rfl rfl rfl rfl
    have hdecode := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      data true #[zero, zero, zero] initial hencode
    have hconforms : StateConformsV1 program initial :=
      stateConformsV1_intro_of_validate_eq_ok program data initial
        #[zero, zero, zero] hvalidate rfl hdecode
    have heval : evalInvariantV1 program 1 initial = .returnedTrue :=
      (evalInvariantV1_returnedTrue_iff_two_state_bytes_eq program data 1 1
        eqInvariantName initial #[zero, zero, zero] zero zero 2 0 1 1 2
        (some eqInvariantName) .public_ .public_ .public_ state1Name
        state2Name hvalidate rfl hdecode rfl rfl rfl rfl rfl rfl rfl).2 rfl
    exact ⟨initial, hinitial, hconforms, heval⟩
  have hreturned : PreservationReturnedCallablesV1 program 1 admitted :=
    returnedCallablesV1 qualifiedName state0Name state1Name state2Name
      viewName literalInvariantName eqInvariantName neInvariantName program
      admitted 1 (by simpa [data] using hadmittedData)
  exact preservationTheoremV1_of_callableObligationsV1 program 1 admitted
    hordinal hadmit
    (preservationBaseV1_of_noInitializerV1 program 1 admitted
      (not_hasInitializerV1_of_validate_and_any_eq_false program data
        hvalidate hnoInitAny)
      hbaseNoInit)
    hreturned

/-- Product all-zero initial carrier for this no-initializer family. -/
def productAllZeroInitialV1 : LogicalStateV1 := {
  initialized := true
  canonicalValues :=
    tripleUint64CanonicalV1
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
      (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0])
}

/-- Ordinal 2 is two-state `.ne` on state ids 1 and 2. The product all-zero
    initial state has equal payloads, so the evaluator is not
    `.returnedTrue`. -/
theorem evalInvariantV1_ord2_not_returnedTrue_of_subjectBodyV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName)
    (hbody :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1
        subjectData bytes) :
    evalInvariantV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 2
      productAllZeroInitialV1 ≠ .returnedTrue := by
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1 data
        bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.StructureLegalV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hstate2Name, hviewName,
      hliteralInvariantName, heqInvariantName, hneInvariantName, hstate01,
      hstate02, hstate12, hviewLiteral, hviewEq, hviewNe, hliteralEq,
      hliteralNe, heqNe⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
        hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data,
          ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  let zero := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]
  have hencode : encodeLogicalStateValuesV1 data true
      #[zero, zero, zero] = .ok productAllZeroInitialV1 := by
    simpa [productAllZeroInitialV1, zero] using
      encodeLogicalStateValuesV1_triple_uint64_eq_ok data
        (StateDeclV1.mk 0 state0Name 0 .public_)
        (StateDeclV1.mk 1 state1Name 0 .public_)
        (StateDeclV1.mk 2 state2Name 0 .public_)
        zero zero zero true rfl rfl rfl rfl rfl rfl rfl
  have hdecode := decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
    data true #[zero, zero, zero] productAllZeroInitialV1 hencode
  have hiff :=
    evalInvariantV1_returnedTrue_iff_two_state_bytes_ne program data 2 2
      neInvariantName productAllZeroInitialV1 #[zero, zero, zero] zero zero
      3 0 1 1 2 (some neInvariantName) .public_ .public_ .public_
      state1Name state2Name hvalidate rfl hdecode rfl rfl rfl rfl rfl rfl rfl
  intro heval
  exact (hiff.mp heval) rfl

theorem not_preservationBaseNoInitializerV1_ord2_of_subjectBodyV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName)
    (hbody :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1
        subjectData bytes) :
    ¬ PreservationBaseNoInitializerV1
        ({ canonicalBytes := bytes } : SemanticProgramV1) 2 := by
  intro hbase
  rcases hbase with ⟨initial, hinitial, _hconforms, heval⟩
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1 data
        bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.StructureLegalV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hstate2Name, hviewName,
      hliteralInvariantName, heqInvariantName, hneInvariantName, hstate01,
      hstate02, hstate12, hviewLiteral, hviewEq, hviewNe, hliteralEq,
      hliteralNe, heqNe⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
        hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data,
          ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  have hnoInitAny :
      data.callables.any (fun c => c.kind == .initializer) = false := by
    simp [data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      literalReturnCallableV1, twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hproduct : initialLogicalStateV1 program = .ok productAllZeroInitialV1 := by
    simpa [productAllZeroInitialV1, data] using
      initialLogicalStateV1_triple_uint64_no_initializer_eq_ok program data
        (StateDeclV1.mk 0 state0Name 0 .public_)
        (StateDeclV1.mk 1 state1Name 0 .public_)
        (StateDeclV1.mk 2 state2Name 0 .public_)
        (TypeDeclV1.mk 0 none (.uint 64)) hvalidate rfl rfl rfl rfl
        (by rfl) hnoInitAny rfl rfl rfl
  have heq : initial = productAllZeroInitialV1 :=
    Except.ok.inj (hinitial.symm.trans hproduct)
  rw [heq] at heval
  exact
    (evalInvariantV1_ord2_not_returnedTrue_of_subjectBodyV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName subjectData bytes
      hnameShape hstate0Name hstate1Name hstate2Name hviewName
      hliteralInvariantName heqInvariantName hneInvariantName hstate01
      hstate02 hstate12 hviewLiteral hviewEq hviewNe hliteralEq hliteralNe
      heqNe hsubject hbody)
      heval

theorem not_preservationTheoremV1_ord2_of_subjectBodyV1
    (qualifiedName : QualifiedName)
    (state0Name state1Name state2Name : String)
    (viewName literalInvariantName eqInvariantName neInvariantName : String)
    (subjectData : SemanticProgramDataV1)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstate0Name : validateIdentifierComponent state0Name = .ok ())
    (hstate1Name : validateIdentifierComponent state1Name = .ok ())
    (hstate2Name : validateIdentifierComponent state2Name = .ok ())
    (hviewName : validateIdentifierComponent viewName = .ok ())
    (hliteralInvariantName :
      validateIdentifierComponent literalInvariantName = .ok ())
    (heqInvariantName : validateIdentifierComponent eqInvariantName = .ok ())
    (hneInvariantName : validateIdentifierComponent neInvariantName = .ok ())
    (hstate01 : state0Name ≠ state1Name)
    (hstate02 : state0Name ≠ state2Name)
    (hstate12 : state1Name ≠ state2Name)
    (hviewLiteral : viewName ≠ literalInvariantName)
    (hviewEq : viewName ≠ eqInvariantName)
    (hviewNe : viewName ≠ neInvariantName)
    (hliteralEq : literalInvariantName ≠ eqInvariantName)
    (hliteralNe : literalInvariantName ≠ neInvariantName)
    (heqNe : eqInvariantName ≠ neInvariantName)
    (hsubject : subjectData =
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName)
    (hbody :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1
        subjectData bytes) :
    ¬ PreservationTheoremV1
        ({ canonicalBytes := bytes } : SemanticProgramV1) 2 := by
  intro hpreserves
  rcases hpreserves.2 with ⟨_admitted, _hadmit, hbase, _hstep⟩
  let data :=
    ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1
      qualifiedName state0Name state1Name state2Name viewName
      literalInvariantName eqInvariantName neInvariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hbodyFamily :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1 data
        bytes := by
    rw [hsubject] at hbody
    simpa [data] using hbody
  have legal :
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.StructureLegalV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName :=
    ⟨hnameShape, hstate0Name, hstate1Name, hstate2Name, hviewName,
      hliteralInvariantName, heqInvariantName, hneInvariantName, hstate01,
      hstate02, hstate12, hviewLiteral, hviewEq, hviewNe, hliteralEq,
      hliteralNe, heqNe⟩
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.structureV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName legal
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.rootFieldInvertV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName
        hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes (by
        change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
        exact hnameShape)
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data,
          ProofForgeV2.Semantic.FieldComparisonSubjectV1.bodyEncodeOkV1]
          using hbodyFamily)
      hinvert
  have hnoInitAny :
      data.callables.any (fun c => c.kind == .initializer) = false := by
    simp [data,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.subjectDataV1,
      ProofForgeV2.Semantic.FieldComparisonSubjectV1.callablesV1,
      literalReturnCallableV1, twoStateCompareInvariantCallableV1]
    constructor <;> decide
  have hnoInit : ¬ HasInitializerV1 program :=
    not_hasInitializerV1_of_validate_and_any_eq_false program data hvalidate
      hnoInitAny
  rcases hbase with ⟨hHas, _hwith⟩ | ⟨_, hNoInit⟩
  · exact hnoInit hHas
  · exact
      (not_preservationBaseNoInitializerV1_ord2_of_subjectBodyV1
        qualifiedName state0Name state1Name state2Name viewName
        literalInvariantName eqInvariantName neInvariantName subjectData
        bytes hnameShape hstate0Name hstate1Name hstate2Name hviewName
        hliteralInvariantName heqInvariantName hneInvariantName hstate01
        hstate02 hstate12 hviewLiteral hviewEq hviewNe hliteralEq hliteralNe
        heqNe hsubject hbody)
        hNoInit

end ProofForgeV2.Semantic.FieldComparisonPreservationV1
