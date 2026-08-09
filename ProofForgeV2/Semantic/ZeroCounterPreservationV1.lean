import ProofForgeV2.Semantic.ZeroCounterDecodeV1
import ProofForgeV2.Semantic.PreservationPackagingV1

namespace ProofForgeV2.Semantic.ZeroCounterPreservationV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationPackagingV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Semantic.ZeroCounterShapeV1

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

theorem validate_ok : validateSemanticProgramV1 program = .ok data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode_bridge
    data canonicalBytes encode_ok ZeroCounterDecodeV1.decode_ok

theorem admission_bool_ok' :
    referenceProgramDataAdmissionOkV1 data = true := by
  decide

theorem admission_check_ok' :
    validateReferenceProgramDataAdmissionV1 data = .ok () :=
  validateReferenceProgramDataAdmissionV1_eq_ok_of_bool data admission_bool_ok'

theorem admit_exists : ∃ admitted : AdmittedReferenceSliceV1,
    admitReferenceProgramSliceV1 program = .ok admitted :=
  admitReferenceProgramSliceV1_exists_of_checks
    program data validate_ok admission_check_ok'

theorem no_initializer : ¬ HasInitializerV1 program :=
  not_hasInitializerV1_of_validate_and_any_eq_false
    program data validate_ok (by
      simp [data, clearCallable, getCallable, zeroCallable] <;> decide)

def initialState : LogicalStateV1 := {
  initialized := true
  canonicalValues := (encodeU32le 8).append zeroBytes
}

private theorem zeroBytes_eq_zero8 : zeroBytes = zero8BytesV1 := rfl

theorem zero_canonical :
    validateValueBytesV1 types 0 zeroBytes = .ok () := by
  apply validateValueBytesV1_uint64_eq_ok types 0 uint64Type
    0 0 0 0 0 0 0 0
  · rfl
  · rfl

theorem true_canonical :
    validateValueBytesV1 types 1 (encodeU8 1) = .ok () := by
  have henc : encodeU8 1 = ByteArray.mk #[1] := rfl
  simp [types, boolType, encodeU8, validateValueBytesV1, henc,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

theorem false_canonical :
    validateValueBytesV1 types 1 (encodeU8 0) = .ok () := by
  have henc : encodeU8 0 = ByteArray.mk #[0] := rfl
  simp [types, boolType, encodeU8, validateValueBytesV1, henc,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

theorem initial_state_ok : initialLogicalStateV1 program = .ok initialState := by
  simpa [initialState, zeroBytes] using
    initialLogicalStateV1_single_uint64_no_initializer_eq_ok
      program data countState uint64Type validate_ok (by rfl) (by rfl) (by rfl)
      (by simp [data, clearCallable, getCallable, zeroCallable] <;> decide)
      (by simpa [data, types, countState, zeroBytes] using zero_canonical)

theorem initial_state_decode :
    decodeLogicalStateValuesV1 data initialState = .ok #[zeroBytes] := by
  rfl

theorem initial_state_conforms : StateConformsV1 program initialState :=
  stateConformsV1_intro_of_validate_eq_ok
    program data initialState #[zeroBytes] validate_ok rfl initial_state_decode

/-- Closed zero-callable shape. -/
theorem zero_callable_eq_shape :
    data.callables[2]? = some {
      id := 2
      kind := .invariant
      name := some "zero"
      params := #[]
      result := { typeId := 1, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := 0 },
            op := .stateLoad 0 },
          { result := some { valueId := 1, typeId := 0 },
            op := .literal 0 zero8BytesV1 },
          { result := some { valueId := 2, typeId := 1 },
            op := .binary .eq 0 1 }
        ]
        terminator := .return_ (some 2)
      }]
      loopBounds := #[]
      invariantSteps := some 5
    } := by
  simp [data, zeroCallable, zeroBlock, valueInstruction, valueDef,
    zeroBytes_eq_zero8]

theorem initial_run_zero :
    runInvariantCallableV1 data 2 initialState = .returnedTrue := by
  have hdecode' :
      decodeLogicalStateValuesV1 data initialState = .ok #[zero8BytesV1] := by
    simpa [zeroBytes_eq_zero8] using initial_state_decode
  have hcanZero :
      validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
  have hcanTrue :
      validateValueBytesV1 data.types 1 (encodeU8 1) = .ok () := by
    simpa [data, types] using true_canonical
  exact runInvariantCallableV1_eq_returnedTrue_of_uint64_eq_zero
    data initialState 2 0 1 0 (some "zero") .public_ "count"
    rfl hdecode'
    (by simp [data, types, uint64Type])
    (by simp [data, types, boolType])
    rfl
    (by simp [data, countState])
    zero_callable_eq_shape
    hcanZero hcanTrue

theorem initial_eval_zero :
    evalInvariantV1 program 0 initialState = .returnedTrue :=
  evalInvariantV1_eq_of_validated_selection
    program data 0 zeroInvariant initialState #[zeroBytes] .returnedTrue
    validate_ok rfl initial_state_decode (by rfl)
    (by
      change runInvariantCallableV1 data zeroInvariant.callableId initialState =
        .returnedTrue
      simpa [zeroInvariant] using initial_run_zero)

theorem base_no_initializer : PreservationBaseNoInitializerV1 program 0 :=
  ⟨initialState, initial_state_ok, initial_state_conforms, initial_eval_zero⟩

theorem preservation_base_no_init (admitted : AdmittedReferenceSliceV1) :
    PreservationBaseV1 program 0 admitted :=
  Or.inr ⟨no_initializer, base_no_initializer⟩

theorem ordinal_in_range : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
  rw [SemanticProgramV1.invariants_eq_of_validate program data validate_ok]
  decide

theorem admit_ok_of_exists
    (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    admitted.program = program ∧ admitted.data = data :=
  admitReferenceProgramSliceV1_ok_implies program data admitted
    validate_ok hadmit

theorem eval_zero_of_count_zero
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hzero : countBytes = zero8BytesV1) :
    evalInvariantV1 program 0 state = .returnedTrue := by
  have hcanZero :
      validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
  have hcanTrue :
      validateValueBytesV1 data.types 1 (encodeU8 1) = .ok () := by
    simpa [data, types] using true_canonical
  have hdecode' : decodeLogicalStateValuesV1 data state = .ok #[zero8BytesV1] := by
    simpa [hzero] using hdecode
  have hrun :
      runInvariantCallableV1 data 2 state = .returnedTrue :=
    runInvariantCallableV1_eq_returnedTrue_of_uint64_eq_zero
      data state 2 0 1 0 (some "zero") .public_ "count"
      hinit hdecode'
      (by simp [data, types, uint64Type])
      (by simp [data, types, boolType])
      rfl
      (by simp [data, countState])
      zero_callable_eq_shape
      hcanZero hcanTrue
  exact evalInvariantV1_eq_of_validated_selection
    program data 0 zeroInvariant state #[countBytes] .returnedTrue
    validate_ok hinit hdecode (by rfl)
    (by
      change runInvariantCallableV1 data zeroInvariant.callableId state =
        .returnedTrue
      simpa [zeroInvariant, hzero] using hrun)

theorem count_zero_of_eval_true
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (heval : evalInvariantV1 program 0 state = .returnedTrue) :
    countBytes = zero8BytesV1 := by
  by_cases hbeq : (countBytes == zero8BytesV1) = true
  · -- ByteArray BEq is data-array equality (sole production BEq).
    cases countBytes with
    | mk d1 =>
        have hdata : zero8BytesV1 = ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0] := rfl
        rw [hdata] at hbeq ⊢
        change (d1 == (#[0, 0, 0, 0, 0, 0, 0, 0] : Array UInt8)) = true at hbeq
        have hd : d1 = #[0, 0, 0, 0, 0, 0, 0, 0] :=
          (beq_iff_eq (a := d1)
            (b := (#[0, 0, 0, 0, 0, 0, 0, 0] : Array UInt8))).mp hbeq
        simpa [hd]
  · have hne : (countBytes == zero8BytesV1) = false := by
      cases h : (countBytes == zero8BytesV1) <;> simp_all
    have hcanZero :
        validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
      simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
    have hcanFalse :
        validateValueBytesV1 data.types 1 (encodeU8 0) = .ok () := by
      simpa [data, types] using false_canonical
    have hrun :
        runInvariantCallableV1 data 2 state = .returnedFalse :=
      runInvariantCallableV1_eq_returnedFalse_of_uint64_ne_zero
        data state countBytes 2 0 1 0 (some "zero") .public_ "count"
        hinit hdecode
        (by simp [data, types, uint64Type])
        (by simp [data, types, boolType])
        rfl
        (by simp [data, countState])
        zero_callable_eq_shape
        hcan hcanZero hcanFalse hne
    have heval' :
        evalInvariantV1 program 0 state = .returnedFalse :=
      evalInvariantV1_eq_of_validated_selection
        program data 0 zeroInvariant state #[countBytes] .returnedFalse
        validate_ok hinit hdecode (by rfl)
        (by
          change runInvariantCallableV1 data zeroInvariant.callableId state =
            .returnedFalse
          simpa [zeroInvariant] using hrun)
    rw [heval] at heval'
    cases heval'

theorem countBytes_size_of_can
    (countBytes : ByteArray)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ()) :
    countBytes.size = 8 := by
  have hlookup : data.types[0]? = some uint64Type := by
    simp [data, types, uint64Type]
  exact uint64BytesSizeOfValidateV1 data.types 0 uint64Type countBytes
    hlookup rfl hcan

theorem get_callable_ready_shape :
    getCallable = {
      id := 1
      kind := .view
      name := some "get"
      params := #[]
      result := { typeId := 0, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := 0 }
          op := .stateLoad 0
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := none
    } := by
  simp [getCallable, getBlock, valueInstruction, valueDef]

theorem clear_callable_ready_shape :
    clearCallable = {
      id := 0
      kind := .entry
      name := some "clear"
      params := #[]
      result := { typeId := 0, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := 0 },
            op := .literal 0 zero8BytesV1 },
          { result := none, op := .stateStore 0 0 },
          { result := some { valueId := 1, typeId := 0 },
            op := .stateLoad 0 }
        ]
        terminator := .return_ (some 1)
      }]
      loopBounds := #[]
      invariantSteps := none
    } := by
  simp [clearCallable, clearBlock, valueInstruction, valueDef, voidInstruction,
    zeroBytes_eq_zero8]

theorem types_uint64 : data.types[0]? = some {
    id := 0, name := none, shape := .uint 64 } := by
  simp [data, types, uint64Type]

theorem state_count : data.logicalState[0]? = some {
    id := 0, name := "count", typeId := 0, visibility := .public_ } := by
  simp [data, countState]

theorem can_zero :
    validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
  simpa [data, types, zeroBytes_eq_zero8] using zero_canonical

theorem encode_zero_overlay_eq_ok :
    encodeLogicalStateValuesV1 data true #[zero8BytesV1] = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append zero8BytesV1
    } :=
  encodeLogicalStateValuesV1_single_uint64_eq_ok data countState zero8BytesV1 true
    (by simp [data, countState]) can_zero (by rfl)

theorem get_encode_post_eq_pre
    (pre post : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    post = pre :=
  encode_of_singleton_decode_eq data countState pre post countBytes
    (by simp [data, countState]) hinit hdecode hcan hencode

theorem encode_even_overlay_eq_ok
    (countBytes : ByteArray)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8) :
    encodeLogicalStateValuesV1 data true #[countBytes] = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append countBytes
    } :=
  encodeLogicalStateValuesV1_single_uint64_eq_ok data countState countBytes true
    (by simp [data, countState]) hcan hsize

/-- Universal one-step preservation for ordinal 0 on closed ZeroCounter. -/
theorem preservation_step
    (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    PreservationStepV1 program 0 admitted := by
  intro pre invocation responses vault hconf heval
  have ⟨_hprog, hdata⟩ := admit_ok_of_exists admitted hadmit
  have ⟨hinit, ⟨values, hdecode⟩⟩ :=
    stateConformsV1_elim_of_validate_eq_ok program data pre validate_ok hconf
  have ⟨countBytes, hvals, hcan⟩ :=
    decodeLogicalStateValuesV1_singleton_eq data countState pre values
      (by simp [data, countState]) hdecode
  have hdecode' : decodeLogicalStateValuesV1 data pre = .ok #[countBytes] := by
    simpa [hvals] using hdecode
  have hzero :=
    count_zero_of_eval_true pre countBytes hinit hdecode' hcan heval
  have hsize := countBytes_size_of_can countBytes hcan
  have hfail :=
    preservationStepFailureArmsV1 admitted pre invocation responses vault
  have hadmitted_data : admitted.data = data := hdata
  have htypeU := types_uint64
  have hstate := state_count
  have hcanZ := can_zero
  have htable :
      data.callables = #[clearCallable, getCallable, zeroCallable] := rfl
  generalize hstep :
    stepReferenceSliceV1 admitted pre invocation responses vault = outcome
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
          have hlookup' :
              data.callables[invocation.callableId.toNat]? = some callable := by
            simpa [hdata] using hlookup
          have hsz : data.callables.size = 3 := by simp [htable]
          have hidx_lt : invocation.callableId.toNat < 3 := by
            have : invocation.callableId.toNat < data.callables.size := by
              by_cases hlt : invocation.callableId.toNat < data.callables.size
              · exact hlt
              · have hnone :
                    data.callables[invocation.callableId.toNat]? = none :=
                  Array.getElem?_eq_none (Nat.not_lt.mp hlt)
                rw [hnone] at hlookup'
                cases hlookup'
            omega
          match hidx : invocation.callableId.toNat with
          | 0 =>
            have hcall : callable = clearCallable := by
              have : data.callables[0]? = some callable := by
                simpa [hidx] using hlookup'
              have : some clearCallable = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hisInit : isInitializer = false := by
              have h := hisInitEq
              rw [hcall] at h
              change isInitializer = (clearCallable.kind == .initializer) at h
              simp only [clearCallable, BEq.beq, decide_false, Bool.false_eq]
                at h
              exact h
            have hgate' :
                gateInvocation admitted pre invocation =
                  .ready clearCallable overlay context false := by
              simpa [hcall, hisInit] using hgate
            have hgate_dec :=
              gateInvocation_ready_noninit_decode admitted pre invocation
                clearCallable overlay context hgate'
            have hoverlay : overlay = #[countBytes] := by
              have hdec_data :
                  decodeLogicalStateValuesV1 data pre = .ok overlay := by
                simpa [hdata] using hgate_dec.1
              have h1 := hdecode'; have h2 := hdec_data
              rw [h2] at h1
              exact Except.ok.inj h1
            have hgate_clr :
                gateInvocation admitted pre invocation =
                  .ready {
                    id := 0, kind := .entry, name := some "clear",
                    params := #[],
                    result := { typeId := 0, visibility := .public_ },
                    entryBlock := 0,
                    blocks := #[{
                      id := 0, params := #[],
                      instructions := #[
                        { result := some { valueId := 0, typeId := 0 },
                          op := .literal 0 zero8BytesV1 },
                        { result := none, op := .stateStore 0 0 },
                        { result := some { valueId := 1, typeId := 0 },
                          op := .stateLoad 0 }],
                      terminator := .return_ (some 1) }],
                    loopBounds := #[], invariantSteps := none
                  } #[countBytes] context false := by
              have hshape := clear_callable_ready_shape
              simpa [hgate', hoverlay, hshape, hcall]
            by_cases hresp : responses.size = 0
            · have henc' := encode_zero_overlay_eq_ok
              have hstep_clr :=
                stepReferenceSliceV1_ready_clear_returned admitted pre
                  invocation data countBytes 0 0 "count" 0 (some "clear")
                  {
                    initialized := true
                    canonicalValues := (encodeU32le 8).append zero8BytesV1
                  } responses vault context hadmitted_data htypeU hstate rfl
                  hcanZ hinit henc' hresp hgate_clr
              have hpost :
                  post = {
                    initialized := true
                    canonicalValues := (encodeU32le 8).append zero8BytesV1
                  } := by
                have h1 := hstep; have h2 := hstep_clr
                rw [h2] at h1
                injection h1 with hpost' _ _
                exact hpost'.symm
              -- post is zero encode → eval true
              have hpost_state :
                  evalInvariantV1 program 0 post = .returnedTrue := by
                rw [hpost]
                exact eval_zero_of_count_zero
                  {
                    initialized := true
                    canonicalValues := (encodeU32le 8).append zero8BytesV1
                  }
                  zero8BytesV1 rfl
                  (by
                    simpa [data, countState] using
                      decodeLogicalStateValuesV1_of_single_uint64_encode
                        data countState zero8BytesV1 true
                        (by simp [data, countState]) hcanZ (by rfl))
                  hcanZ rfl
              exact hpost_state
            · have htrap :=
                stepReferenceSliceV1_ready_clear_nonempty_responses_traps
                  admitted pre invocation data countBytes 0 0 "count" 0
                  (some "clear") responses vault context hadmitted_data
                  htypeU hstate rfl hcanZ (by exact hresp) hgate_clr
              rw [htrap] at hstep; cases hstep
          | 1 =>
            have hcall : callable = getCallable := by
              have : data.callables[1]? = some callable := by
                simpa [hidx] using hlookup'
              have : some getCallable = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hisInit : isInitializer = false := by
              have h := hisInitEq
              rw [hcall] at h
              change isInitializer = (getCallable.kind == .initializer) at h
              simp only [getCallable, BEq.beq, decide_false, Bool.false_eq] at h
              exact h
            have hgate' :
                gateInvocation admitted pre invocation =
                  .ready getCallable overlay context false := by
              simpa [hcall, hisInit] using hgate
            have hgate_dec :=
              gateInvocation_ready_noninit_decode admitted pre invocation
                getCallable overlay context hgate'
            have hoverlay : overlay = #[countBytes] := by
              have hdec_data :
                  decodeLogicalStateValuesV1 data pre = .ok overlay := by
                simpa [hdata] using hgate_dec.1
              have h1 := hdecode'; have h2 := hdec_data
              rw [h2] at h1
              exact Except.ok.inj h1
            have hgate_get :
                gateInvocation admitted pre invocation =
                  .ready {
                    id := 1, kind := .view, name := some "get", params := #[],
                    result := { typeId := 0, visibility := .public_ },
                    entryBlock := 0,
                    blocks := #[{
                      id := 0, params := #[],
                      instructions := #[{
                        result := some { valueId := 0, typeId := 0 },
                        op := .stateLoad 0 }],
                      terminator := .return_ (some 0) }],
                    loopBounds := #[], invariantSteps := none
                  } #[countBytes] context false := by
              have hshape := get_callable_ready_shape
              simpa [hgate', hoverlay, hshape, hcall]
            by_cases hresp : responses.size = 0
            · have henc' := encode_even_overlay_eq_ok countBytes hcan hsize
              have hstep_get :=
                stepReferenceSliceV1_ready_get_returned admitted pre invocation
                  data countBytes 0 0 "count" 1 (some "get")
                  {
                    initialized := true
                    canonicalValues := (encodeU32le 8).append countBytes
                  } responses vault context hadmitted_data htypeU hstate rfl
                  hcan hinit henc' hresp hgate_get
              have hpost :
                  post = {
                    initialized := true
                    canonicalValues := (encodeU32le 8).append countBytes
                  } := by
                have h1 := hstep; have h2 := hstep_get
                rw [h2] at h1
                injection h1 with hpost' _ _
                exact hpost'.symm
              have henc_post :
                  encodeLogicalStateValuesV1 data true #[countBytes] =
                    .ok post := by
                rw [hpost]; exact henc'
              have hpost_pre :=
                get_encode_post_eq_pre pre post countBytes hinit hdecode' hcan
                  henc_post
              exact preservationStepReturnedPostEqPreV1 program 0 pre post heval
                hpost_pre
            · have htrap :=
                stepReferenceSliceV1_ready_get_nonempty_responses_traps admitted
                  pre invocation data countBytes 0 0 "count" 1 (some "get")
                  responses vault context hadmitted_data htypeU hstate rfl hcan
                  (by exact hresp) hgate_get
              rw [htrap] at hstep; cases hstep
          | 2 =>
            have hcall : callable = zeroCallable := by
              have : data.callables[2]? = some callable := by
                simpa [hidx] using hlookup'
              have : some zeroCallable = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hkind : callable.kind = .invariant := by
              simp [hcall, zeroCallable]
            have hkindOk :
                (callable.kind == .initializer ||
                  callable.kind == .entry ||
                  callable.kind == .view) = false := by
              rw [hkind]
              decide
            have : gateInvocation admitted pre invocation =
                .invalidInvocation := by
              unfold gateInvocation
              simp only [hlookup, hkindOk, Bool.not_false, ↓reduceIte]
            rw [this] at hgate
            cases hgate
          | n + 3 =>
            have : n + 3 < 3 := by simpa [hidx] using hidx_lt
            omega
  | reverted reason unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeRevertedUnchangedV1] using
        hfail
  | trapped fault unchanged =>
      rw [hstep] at hfail
      simpa [OutcomeFailureStateUnchangedV1, OutcomeTrappedUnchangedV1] using
        hfail

theorem preservation_theorem :
    PreservationTheoremV1 program 0 := by
  refine ⟨ordinal_in_range, ?_⟩
  rcases admit_exists with ⟨admitted, hadmit⟩
  exact ⟨admitted, hadmit, preservation_base_no_init admitted,
    preservation_step admitted hadmit⟩

theorem preservation_theorem_of_eq_bytes
    (p : SemanticProgramV1)
    (h : p.canonicalBytes = canonicalBytes) :
    PreservationTheoremV1 p 0 := by
  have hp : p = program := by
    cases p with
    | mk b =>
        change ({ canonicalBytes := b } : SemanticProgramV1) = program
        have hb : b = canonicalBytes := h
        subst hb
        rfl
  simpa [hp] using preservation_theorem

end ProofForgeV2.Semantic.ZeroCounterPreservationV1
