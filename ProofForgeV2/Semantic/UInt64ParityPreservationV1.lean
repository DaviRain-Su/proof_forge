import ProofForgeV2.Semantic.UInt64ParitySubjectV1

/-
  ProofForgeV2.Semantic.UInt64ParityPreservationV1 — no-pin same-file
  preservation family for one public UInt64 slot.

  Contract-agnostic API for the shape:
    * one public UInt64 logical-state slot (StateId/TypeId 0)
    * nullary entry CallableId 0: x := x + 2; return x
    * nullary view CallableId 1: return x
    * nullary invariant CallableId 2: (x % 2) == 0

  The theorem is parameterized by the product SemanticProgramV1 carrier,
  decoded SemanticProgramDataV1, validation/admission facts, and exact shape
  facts. It does not import or mention residual pins, ProofInstances,
  ParityCounter, ZeroCounter, or ClosedSubjectPin.
-/

namespace ProofForgeV2.Semantic.UInt64ParityPreservationV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationPackagingV1
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

/-- Canonical TypeId 0 shape for the one-slot UInt64 parity family. -/
def uint64Decl0V1 : TypeDeclV1 :=
  { id := 0, name := none, shape := .uint 64 }

/-- Canonical TypeId 1 shape for the one-slot UInt64 parity family. -/
def boolDecl1V1 : TypeDeclV1 :=
  { id := 1, name := none, shape := .bool }

/-- Canonical public StateId 0 declaration for the one-slot UInt64 parity family. -/
def singlePublicUInt64State0V1 (stateName : String) : StateDeclV1 :=
  { id := 0, name := stateName, typeId := 0, visibility := .public_ }

private theorem no_initializer_of_shape
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (entryName viewName invName : Option String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hcallables : data.callables = #[
      incrementAddTwoCallableV1 0 entryName 0 0,
      viewLoadCallableV1 1 viewName 0 0,
      uint64ParityInvariantCallableV1 2 invName 0 1 0 .public_ (some 7)]) :
    ¬ HasInitializerV1 program :=
  not_hasInitializerV1_of_validate_and_any_eq_false
    program data hvalidate (by
      rw [hcallables]
      simp [incrementAddTwoCallableV1, viewLoadCallableV1,
        uint64ParityInvariantCallableV1]
      repeat constructor <;> decide)

private theorem admit_exists_of_data_admission
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hadmission : validateReferenceProgramDataAdmissionV1 data = .ok ()) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 program = .ok admitted :=
  admitReferenceProgramSliceV1_exists_of_checks
    program data hvalidate hadmission

private theorem admit_ok_implies_data
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (admitted : AdmittedReferenceSliceV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    admitted.program = program ∧ admitted.data = data :=
  admitReferenceProgramSliceV1_ok_implies program data admitted hvalidate hadmit

/-- Generic evaluator packaging: decoded even UInt64 overlay satisfies the
    ordinal-selected parity invariant. -/
theorem evalParityTrue_of_countEvenV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (invName : String)
    (stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstate0 : data.logicalState[0]? = some (singlePublicUInt64State0V1 stateName))
    (hparityCallable : data.callables[2]? = some
      (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)))
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok ())
    (heven : leBytesToNatV1 countBytes % 2 = 0) :
    evalInvariantV1 program ordinal state = .returnedTrue := by
  have hrun : runInvariantCallableV1 data 2 state = .returnedTrue :=
    runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_even
      data state countBytes 2 0 1 0 (some invName) .public_ stateName
      hinit hdecode htypeU htypeB rfl hstate0 hparityCallable
      hcan hcanTwo hcanZero hcanTrue heven
  exact evalInvariantV1_eq_of_validated_selection
    program data ordinal { id := ordinal, name := invName, callableId := 2 }
    state #[countBytes] .returnedTrue hvalidate hinit hdecode hselection
    (by simpa using hrun)

/-- Converse evaluator packaging: true parity invariant on a decoded UInt64
    overlay implies the payload is even. -/
theorem countEven_of_evalParityTrueV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (invName : String)
    (stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstate0 : data.logicalState[0]? = some (singlePublicUInt64State0V1 stateName))
    (hparityCallable : data.callables[2]? = some
      (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)))
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanFalse : validateValueBytesV1 data.types 1 (encodeU8 0) = .ok ())
    (heval : evalInvariantV1 program ordinal state = .returnedTrue) :
    leBytesToNatV1 countBytes % 2 = 0 := by
  by_cases he : leBytesToNatV1 countBytes % 2 = 0
  · exact he
  · have hodd : leBytesToNatV1 countBytes % 2 = 1 := by omega
    have hrun : runInvariantCallableV1 data 2 state = .returnedFalse :=
      runInvariantCallableV1_eq_returnedFalse_of_uint64_parity_odd
        data state countBytes 2 0 1 0 (some invName) .public_ stateName
        hinit hdecode htypeU htypeB rfl hstate0 hparityCallable
        hcan hcanTwo hcanZero hcanFalse hodd
    have heval' : evalInvariantV1 program ordinal state = .returnedFalse :=
      evalInvariantV1_eq_of_validated_selection
        program data ordinal { id := ordinal, name := invName, callableId := 2 }
        state #[countBytes] .returnedFalse hvalidate hinit hdecode hselection
        (by simpa using hrun)
    rw [heval] at heval'
    cases heval'

private theorem countBytes_size_of_canV1
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ()) :
    countBytes.size = 8 :=
  uint64BytesSizeOfValidateV1 data.types 0 uint64Decl0V1 countBytes htypeU rfl hcan

private theorem encode_even_overlay_eq_okV1
    (data : SemanticProgramDataV1)
    (stateName : String)
    (countBytes : ByteArray)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8) :
    encodeLogicalStateValuesV1 data true #[countBytes] = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append countBytes
    } :=
  encodeLogicalStateValuesV1_single_uint64_eq_ok data
    (singlePublicUInt64State0V1 stateName) countBytes true hstateTable hcan hsize

private theorem get_encode_post_eq_preV1
    (data : SemanticProgramDataV1)
    (stateName : String)
    (pre post : LogicalStateV1)
    (countBytes : ByteArray)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hencode : encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    post = pre :=
  encode_of_singleton_decode_eq data (singlePublicUInt64State0V1 stateName)
    pre post countBytes hstateTable hinit hdecode hcan hencode

private theorem encode_increment_sum_eq_okV1
    (data : SemanticProgramDataV1)
    (stateName : String)
    (countBytes : ByteArray)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    encodeLogicalStateValuesV1 data true #[sumBytes] = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append sumBytes
    } := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have hsum := add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  have hcanSum : validateValueBytesV1 data.types 0 sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Decl0V1 sumBytes
      htypeU rfl hsum.1
  simpa [sumBytes] using
    encodeLogicalStateValuesV1_single_uint64_eq_ok data
      (singlePublicUInt64State0V1 stateName) sumBytes true hstateTable hcanSum hsum.1

private theorem eval_even_after_increment_formV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (countBytes : ByteArray)
    (invName stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hstate0 : data.logicalState[0]? = some (singlePublicUInt64State0V1 stateName))
    (hparityCallable : data.callables[2]? = some
      (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)))
    (_hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    evalInvariantV1 program ordinal {
      initialized := true
      canonicalValues := (encodeU32le 8).append sumBytes
    } = .returnedTrue := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have hsum := add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  have hcanSum : validateValueBytesV1 data.types 0 sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Decl0V1 sumBytes
      htypeU rfl hsum.1
  have hdecode : decodeLogicalStateValuesV1 data {
      initialized := true
      canonicalValues := (encodeU32le 8).append sumBytes
    } = .ok #[sumBytes] := by
    simpa [sumBytes] using
      decodeLogicalStateValuesV1_of_single_uint64_encode data
        (singlePublicUInt64State0V1 stateName) sumBytes true
        hstateTable hcanSum hsum.1
  exact evalParityTrue_of_countEvenV1 program data ordinal
    { initialized := true, canonicalValues := (encodeU32le 8).append sumBytes }
    sumBytes invName stateName hvalidate hselection rfl hdecode htypeU htypeB
    hstate0 hparityCallable hcanSum hcanTwo hcanZero hcanTrue hsum.2.1

/-- Universal one-step preservation for the one-slot UInt64 parity family. -/
theorem preservationStep_uint64ParityIncrementAddTwoV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1)
    (entryName viewName : Option String)
    (invName stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hcallables : data.callables = #[
      incrementAddTwoCallableV1 0 entryName 0 0,
      viewLoadCallableV1 1 viewName 0 0,
      uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)])
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok ())
    (hcanFalse : validateValueBytesV1 data.types 1 (encodeU8 0) = .ok ()) :
    PreservationStepV1 program ordinal admitted := by
  intro pre invocation responses vault hconf heval
  have ⟨_hprog, hdata⟩ := admit_ok_implies_data program data admitted hvalidate hadmit
  have ⟨hinit, ⟨values, hdecode⟩⟩ :=
    stateConformsV1_elim_of_validate_eq_ok program data pre hvalidate hconf
  have hstateDecl : data.logicalState[0]? = some (singlePublicUInt64State0V1 stateName) := by
    simp [hstateTable]
  have ⟨countBytes, hvals, hcan⟩ :=
    decodeLogicalStateValuesV1_singleton_eq data (singlePublicUInt64State0V1 stateName)
      pre values hstateTable hdecode
  have hdecode' : decodeLogicalStateValuesV1 data pre = .ok #[countBytes] := by
    simpa [hvals] using hdecode
  have hparityCallable : data.callables[2]? = some
      (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)) := by
    simp [hcallables]
  have heven :=
    countEven_of_evalParityTrueV1 program data ordinal pre countBytes invName
      stateName hvalidate hselection hinit hdecode' htypeU htypeB hstateDecl
      hparityCallable hcan hcanTwo hcanZero hcanFalse heval
  have hsize := countBytes_size_of_canV1 data countBytes htypeU hcan
  have hfail := preservationStepFailureArmsV1 admitted pre invocation responses vault
  have hadmitted_data : admitted.data = data := hdata
  have htable := hcallables
  generalize hstep : stepReferenceSliceV1 admitted pre invocation responses vault = outcome
  cases outcome with
  | returned post value effects =>
      have hready :=
        stepReturnedImpliesGateReadyV1 admitted pre invocation responses vault
          post value effects hstep
      cases hgate : gateInvocation admitted pre invocation with
      | invalidInvocation =>
          rw [hgate] at hready
          exact False.elim hready
      | lifecycle _cand =>
          rw [hgate] at hready
          exact False.elim hready
      | ready callable overlay context isInitializer =>
          have hlookup_full :=
            gateInvocation_ready_callable_lookup admitted pre invocation
              callable overlay context isInitializer hgate
          have hlookup : admitted.data.callables[invocation.callableId.toNat]? =
              some callable := hlookup_full.1
          have hisInitEq : isInitializer =
              (callable.kind == CallableKindV1.initializer) := hlookup_full.2
          have hlookup' : data.callables[invocation.callableId.toNat]? = some callable := by
            simpa [hdata] using hlookup
          have hsz : data.callables.size = 3 := by simp [htable]
          have hidx_lt : invocation.callableId.toNat < 3 := by
            have : invocation.callableId.toNat < data.callables.size := by
              by_cases hlt : invocation.callableId.toNat < data.callables.size
              · exact hlt
              · have hnone : data.callables[invocation.callableId.toNat]? = none :=
                  Array.getElem?_eq_none (Nat.not_lt.mp hlt)
                rw [hnone] at hlookup'
                cases hlookup'
            omega
          match hidx : invocation.callableId.toNat with
          | 0 =>
            have hcall : callable = incrementAddTwoCallableV1 0 entryName 0 0 := by
              have : data.callables[0]? = some callable := by simpa [hidx] using hlookup'
              have : some (incrementAddTwoCallableV1 0 entryName 0 0) = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hisInit : isInitializer = false := by
              have h := hisInitEq
              rw [hcall] at h
              simp [incrementAddTwoCallableV1] at h
              exact h
            have hgate' : gateInvocation admitted pre invocation =
                .ready (incrementAddTwoCallableV1 0 entryName 0 0) overlay context false := by
              simpa [hcall, hisInit] using hgate
            have hgate_dec :=
              gateInvocation_ready_noninit_decode admitted pre invocation
                (incrementAddTwoCallableV1 0 entryName 0 0) overlay context hgate'
            have hoverlay : overlay = #[countBytes] := by
              have hdec_data : decodeLogicalStateValuesV1 data pre = .ok overlay := by
                simpa [hdata] using hgate_dec.1
              have h1 := hdecode'; have h2 := hdec_data
              rw [h2] at h1
              exact Except.ok.inj h1
            have hgate_inc : gateInvocation admitted pre invocation =
                .ready (incrementAddTwoCallableV1 0 entryName 0 0) #[countBytes] context false := by
              simpa [hgate', hoverlay]
            by_cases hov : leBytesToNatV1 countBytes + 2 < 2 ^ 64
            · by_cases hresp : responses.size = 0
              · let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
                have henc' := encode_increment_sum_eq_okV1 data stateName countBytes
                  hstateTable htypeU hsize heven hov
                let postInc : LogicalStateV1 := {
                  initialized := true
                  canonicalValues := (encodeU32le 8).append sumBytes
                }
                have heval_post : evalInvariantV1 program ordinal postInc = .returnedTrue := by
                  simpa [postInc, sumBytes] using
                    eval_even_after_increment_formV1 program data ordinal countBytes
                      invName stateName hvalidate hselection htypeU htypeB hstateTable
                      hstateDecl hparityCallable hcan hcanTwo hcanZero hcanTrue hsize
                      heven hov
                exact preservationReturned_of_readyIncrementAddTwoV1
                  program ordinal admitted pre invocation data countBytes 0 0 stateName
                  0 entryName postInc responses vault context hadmitted_data htypeU
                  hstateDecl rfl hcan hcanTwo hov hinit henc' hresp hgate_inc
                  heval_post post value effects hstep
              · have htrap :=
                  stepTrapped_of_readyIncrementAddTwo_nonemptyResponsesV1
                    admitted pre invocation data countBytes 0 0 stateName 0 entryName
                    responses vault context hadmitted_data htypeU hstateDecl rfl hcan
                    hcanTwo hov (by exact hresp) hgate_inc
                rw [htrap] at hstep; cases hstep
            · have hne :=
                stepNotReturned_of_readyIncrementAddTwo_overflowV1
                  admitted pre invocation data countBytes 0 0 stateName 0 entryName
                  responses vault context post value effects hadmitted_data htypeU
                  hstateDecl rfl hcan hcanTwo hov hgate_inc
              exact absurd hstep hne
          | 1 =>
            have hcall : callable = viewLoadCallableV1 1 viewName 0 0 := by
              have : data.callables[1]? = some callable := by simpa [hidx] using hlookup'
              have : some (viewLoadCallableV1 1 viewName 0 0) = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hisInit : isInitializer = false := by
              have h := hisInitEq
              rw [hcall] at h
              simp [viewLoadCallableV1] at h
              exact h
            have hgate' : gateInvocation admitted pre invocation =
                .ready (viewLoadCallableV1 1 viewName 0 0) overlay context false := by
              simpa [hcall, hisInit] using hgate
            have hgate_dec :=
              gateInvocation_ready_noninit_decode admitted pre invocation
                (viewLoadCallableV1 1 viewName 0 0) overlay context hgate'
            have hoverlay : overlay = #[countBytes] := by
              have hdec_data : decodeLogicalStateValuesV1 data pre = .ok overlay := by
                simpa [hdata] using hgate_dec.1
              have h1 := hdecode'; have h2 := hdec_data
              rw [h2] at h1
              exact Except.ok.inj h1
            have hgate_get : gateInvocation admitted pre invocation =
                .ready (viewLoadCallableV1 1 viewName 0 0) #[countBytes] context false := by
              simpa [hgate', hoverlay]
            by_cases hresp : responses.size = 0
            · have henc' := encode_even_overlay_eq_okV1 data stateName countBytes
                hstateTable hcan hsize
              let postGet : LogicalStateV1 := {
                initialized := true
                canonicalValues := (encodeU32le 8).append countBytes
              }
              have hpost_pre0 :=
                get_encode_post_eq_preV1 data stateName pre postGet countBytes
                  hstateTable hinit hdecode' hcan henc'
              exact preservationReturned_of_readyViewLoad_postEqPreV1
                program ordinal admitted pre invocation data countBytes 0 0 stateName
                1 viewName postGet responses vault context hadmitted_data htypeU
                hstateDecl rfl hcan hinit henc' hresp hgate_get hpost_pre0
                heval post value effects hstep
            · have htrap :=
                stepTrapped_of_readyViewLoad_nonemptyResponsesV1 admitted
                  pre invocation data countBytes 0 0 stateName 1 viewName
                  responses vault context hadmitted_data htypeU hstateDecl rfl hcan
                  (by exact hresp) hgate_get
              rw [htrap] at hstep; cases hstep
          | 2 =>
            have hcall : callable =
                uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7) := by
              have : data.callables[2]? = some callable := by simpa [hidx] using hlookup'
              have : some (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)) = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hkind : callable.kind = .invariant := by
              simp [hcall, uint64ParityInvariantCallableV1]
            have hkindOk :
                (callable.kind == CallableKindV1.initializer ||
                  callable.kind == .entry || callable.kind == .view) = false := by
              rw [hkind]
              decide
            have : gateInvocation admitted pre invocation = .invalidInvocation := by
              unfold gateInvocation
              simp only [hlookup, hkindOk, Bool.not_false, ↓reduceIte]
            rw [this] at hgate
            cases hgate
          | n + 3 =>
            have : n + 3 < 3 := by simpa [hidx] using hidx_lt
            omega
  | reverted reason unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeRevertedUnchangedV1] using hfail
  | trapped fault unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeTrappedUnchangedV1] using hfail

/-- Positive no-initializer base for the one-slot UInt64 parity family. -/
theorem preservationBaseNoInitializer_uint64ParityV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (entryName viewName : Option String)
    (invName stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hcallables : data.callables = #[
      incrementAddTwoCallableV1 0 entryName 0 0,
      viewLoadCallableV1 1 viewName 0 0,
      uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)])
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok ()) :
    PreservationBaseNoInitializerV1 program ordinal := by
  let initialState : LogicalStateV1 := {
    initialized := true
    canonicalValues := (encodeU32le 8).append zero8BytesV1
  }
  have hstate0 : data.logicalState[0]? = some (singlePublicUInt64State0V1 stateName) := by
    simp [hstateTable]
  have hnoInitAny : data.callables.any (fun c => c.kind == .initializer) = false := by
    rw [hcallables]
    simp [incrementAddTwoCallableV1, viewLoadCallableV1,
      uint64ParityInvariantCallableV1]
    repeat constructor <;> decide
  have hinitial : initialLogicalStateV1 program = .ok initialState := by
    simpa [initialState, zero8BytesV1] using
      initialLogicalStateV1_single_uint64_no_initializer_eq_ok
        program data (singlePublicUInt64State0V1 stateName) uint64Decl0V1
        hvalidate hstateTable htypeU rfl hnoInitAny
        (by simpa [singlePublicUInt64State0V1, zero8BytesV1] using hcanZero)
  have hdecode : decodeLogicalStateValuesV1 data initialState = .ok #[zero8BytesV1] := by
    simpa [initialState] using
      decodeLogicalStateValuesV1_of_single_uint64_encode data
        (singlePublicUInt64State0V1 stateName) zero8BytesV1 true hstateTable
        hcanZero rfl
  have hconforms : StateConformsV1 program initialState :=
    stateConformsV1_intro_of_validate_eq_ok
      program data initialState #[zero8BytesV1] hvalidate rfl hdecode
  have hparityCallable : data.callables[2]? = some
      (uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)) := by
    simp [hcallables]
  have heven0 : leBytesToNatV1 zero8BytesV1 % 2 = 0 := by decide
  have heval : evalInvariantV1 program ordinal initialState = .returnedTrue :=
    evalParityTrue_of_countEvenV1 program data ordinal initialState zero8BytesV1
      invName stateName hvalidate hselection rfl hdecode htypeU htypeB hstate0
      hparityCallable hcanZero hcanTwo hcanZero hcanTrue heven0
  exact ⟨initialState, hinitial, hconforms, heval⟩

/-- Full no-pin `PreservationTheoremV1` for the one-slot UInt64 parity family. -/
theorem preservationTheorem_uint64ParityIncrementAddTwoV1
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (ordinal : InvariantOrdinalV1)
    (entryName viewName : Option String)
    (invName stateName : String)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hadmission : validateReferenceProgramDataAdmissionV1 data = .ok ())
    (hordinal : ordinal.toNat < program.invariants.size)
    (hselection : data.invariants[ordinal.toNat]? = some
      { id := ordinal, name := invName, callableId := 2 })
    (htypeU : data.types[0]? = some uint64Decl0V1)
    (htypeB : data.types[1]? = some boolDecl1V1)
    (hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName])
    (hcallables : data.callables = #[
      incrementAddTwoCallableV1 0 entryName 0 0,
      viewLoadCallableV1 1 viewName 0 0,
      uint64ParityInvariantCallableV1 2 (some invName) 0 1 0 .public_ (some 7)])
    (hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok ())
    (hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok ())
    (hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok ())
    (hcanFalse : validateValueBytesV1 data.types 1 (encodeU8 0) = .ok ()) :
    PreservationTheoremV1 program ordinal := by
  refine ⟨hordinal, ?_⟩
  rcases admit_exists_of_data_admission program data hvalidate hadmission with
    ⟨admitted, hadmit⟩
  have hbase :=
    preservationBaseNoInitializer_uint64ParityV1 program data ordinal entryName
      viewName invName stateName hvalidate hselection htypeU htypeB hstateTable
      hcallables hcanTwo hcanZero hcanTrue
  exact ⟨admitted, hadmit,
    Or.inr ⟨no_initializer_of_shape program data entryName viewName (some invName)
      hvalidate hcallables, hbase⟩,
    preservationStep_uint64ParityIncrementAddTwoV1 program data ordinal admitted
      entryName viewName invName stateName hvalidate hadmit hselection htypeU htypeB
      hstateTable hcallables hcanTwo hcanZero hcanTrue hcanFalse⟩

/-- Author-facing no-pin wrapper for generated subjects of this exact generic
    shape. It derives production structure, root codec inversion, validation,
    admission, and the static shape facts from the structured subject plus the
    ordinary identifier/distinctness premises. No contract name or byte golden
    is embedded in this theorem. -/
theorem preservationTheorem_of_subjectBodyV1
    (qualifiedName : ProofForgeV2.Core.Common.QualifiedName)
    (stateName entryName viewName invariantName : String)
    (bytes : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 qualifiedName = .ok ())
    (hstateName : ProofForgeV2.Core.Common.validateIdentifierComponent stateName = .ok ())
    (hentryName : ProofForgeV2.Core.Common.validateIdentifierComponent entryName = .ok ())
    (hviewName : ProofForgeV2.Core.Common.validateIdentifierComponent viewName = .ok ())
    (hinvariantName : ProofForgeV2.Core.Common.validateIdentifierComponent invariantName = .ok ())
    (hentryView : entryName ≠ viewName)
    (hentryInvariant : entryName ≠ invariantName)
    (hviewInvariant : viewName ≠ invariantName)
    (hbody : ProofForgeV2.Semantic.UInt64ParitySubjectV1.bodyEncodeOkV1
      (ProofForgeV2.Semantic.UInt64ParitySubjectV1.subjectDataV1
        qualifiedName stateName entryName viewName invariantName) bytes) :
    PreservationTheoremV1 ({ canonicalBytes := bytes } : SemanticProgramV1) 0 := by
  let data := ProofForgeV2.Semantic.UInt64ParitySubjectV1.subjectDataV1
    qualifiedName stateName entryName viewName invariantName
  let program : SemanticProgramV1 := { canonicalBytes := bytes }
  have hstructure : validateSemanticProgramStructureV1 data = .ok () := by
    simpa [data] using
      (ProofForgeV2.Semantic.UInt64ParitySubjectV1.structureOkV1
        qualifiedName stateName entryName viewName invariantName hnameShape
        hstateName hentryName hviewName hinvariantName hentryView
        hentryInvariant hviewInvariant)
  have hinvert : RootFieldInvertV1 data := by
    simpa [data] using
      (ProofForgeV2.Semantic.UInt64ParitySubjectV1.rootFieldInvertV1
        qualifiedName stateName entryName viewName invariantName
        hstateName hentryName hviewName hinvariantName)
  have hnameShapeData :
      validateProgramQualifiedNameShapeV1 data.qualifiedName = .ok () := by
    change validateProgramQualifiedNameShapeV1 qualifiedName = .ok ()
    exact hnameShape
  have hvalidate : validateSemanticProgramV1 program = .ok data := by
    change validateSemanticProgramV1 ⟨bytes⟩ = .ok data
    exact ProofForgeV2.Semantic.SubjectDataBridgeV1.validate_of_subjectData_body_gates_invert
      data bytes hnameShapeData
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      hstructure
      (by
        simpa [data, ProofForgeV2.Semantic.UInt64ParitySubjectV1.bodyEncodeOkV1]
          using hbody)
      hinvert
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    rfl
  have hordinal : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
    rw [SemanticProgramV1.invariants_eq_of_validate program data hvalidate]
    change 0 < 1
    decide
  have hselection : data.invariants[0]? = some
      { id := 0, name := invariantName, callableId := 2 } := by
    rfl
  have htypeU : data.types[0]? = some uint64Decl0V1 := by
    rfl
  have htypeB : data.types[1]? = some boolDecl1V1 := by
    rfl
  have hstateTable : data.logicalState = #[singlePublicUInt64State0V1 stateName] := by
    rfl
  have hcallables : data.callables = #[
      incrementAddTwoCallableV1 0 (some entryName) 0 0,
      viewLoadCallableV1 1 (some viewName) 0 0,
      uint64ParityInvariantCallableV1 2 (some invariantName) 0 1 0 .public_ (some 7)] := by
    rfl
  have hcanTwo : validateValueBytesV1 data.types 0 two8BytesV1 = .ok () := by
    exact validateValueBytesV1_uint64_eq_ok data.types 0 uint64Decl0V1
      2 0 0 0 0 0 0 0 htypeU rfl
  have hcanZero : validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    exact validateValueBytesV1_uint64_eq_ok data.types 0 uint64Decl0V1
      0 0 0 0 0 0 0 0 htypeU rfl
  have hcanTrue : validateValueBytesV1 data.types 1 (encodeU8 1) = .ok () := by
    rfl
  have hcanFalse : validateValueBytesV1 data.types 1 (encodeU8 0) = .ok () := by
    rfl
  simpa [program] using
    preservationTheorem_uint64ParityIncrementAddTwoV1
      program data 0 (some entryName) (some viewName) invariantName stateName
      hvalidate hadmission hordinal hselection htypeU htypeB hstateTable
      hcallables hcanTwo hcanZero hcanTrue hcanFalse

end ProofForgeV2.Semantic.UInt64ParityPreservationV1
