import ProofForgeV2.ProofInstances.EvenCounterDecodeV1

namespace ProofForgeV2.ProofInstances.EvenCounterPreservationV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.ProofInstances.EvenCounterV1

set_option maxHeartbeats 80000000
set_option maxRecDepth 400000

theorem validate_ok : validateSemanticProgramV1 program = .ok data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode_bridge
    data canonicalBytes encode_ok EvenCounterDecodeV1.decode_ok

theorem admission_bool_ok :
    referenceProgramDataAdmissionOkV1 data = true := by
  decide

theorem admission_check_ok :
    validateReferenceProgramDataAdmissionV1 data = .ok () :=
  validateReferenceProgramDataAdmissionV1_eq_ok_of_bool data admission_bool_ok

theorem admit_exists : ∃ admitted : AdmittedReferenceSliceV1,
    admitReferenceProgramSliceV1 program = .ok admitted :=
  admitReferenceProgramSliceV1_exists_of_checks
    program data validate_ok admission_check_ok

theorem no_initializer : ¬ HasInitializerV1 program :=
  not_hasInitializerV1_of_validate_and_any_eq_false
    program data validate_ok (by
      simp [data, incrementCallable, getCallable, evenCallable] <;> decide)

def initialState : LogicalStateV1 := {
  initialized := true
  canonicalValues := (encodeU32le 8).append zeroBytes
}

theorem zero_canonical :
    validateValueBytesV1 types 0 zeroBytes = .ok () := by
  apply validateValueBytesV1_uint64_eq_ok types 0 uint64Type
    0 0 0 0 0 0 0 0
  · rfl
  · rfl

theorem two_canonical :
    validateValueBytesV1 types 0 twoBytes = .ok () := by
  apply validateValueBytesV1_uint64_eq_ok types 0 uint64Type
    2 0 0 0 0 0 0 0
  · rfl
  · rfl

theorem true_canonical :
    validateValueBytesV1 types 1 (encodeU8 1) = .ok () := by
  -- Match SimpleClosure's closed Bool-true validation pattern.
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
      (by simp [data, incrementCallable, getCallable, evenCallable] <;> decide)
      (by simpa [data, types, countState, zeroBytes] using zero_canonical)

theorem initial_state_decode :
    decodeLogicalStateValuesV1 data initialState = .ok #[zeroBytes] := by
  rfl

theorem initial_state_conforms : StateConformsV1 program initialState :=
  stateConformsV1_intro_of_validate_eq_ok
    program data initialState #[zeroBytes] validate_ok rfl initial_state_decode

private theorem zeroBytes_eq_zero8 : zeroBytes = zero8BytesV1 := rfl
private theorem twoBytes_eq_two8 : twoBytes = two8BytesV1 := rfl

/-! ### Closed even-callable shape (shared by zero/general parity paths) -/

/-- The closed EvenCounter invariant callable matches the UInt64 parity micro-path. -/
theorem even_callable_parity_shape :
    data.callables[2]? = some {
      id := 2
      kind := .invariant
      name := some "even"
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
            op := .literal 0 two8BytesV1 },
          { result := some { valueId := 2, typeId := 0 },
            op := .binary .mod 0 1 },
          { result := some { valueId := 3, typeId := 0 },
            op := .literal 0 zero8BytesV1 },
          { result := some { valueId := 4, typeId := 1 },
            op := .binary .eq 2 3 }
        ]
        terminator := .return_ (some 4)
      }]
      loopBounds := #[]
      invariantSteps := some 7
    } := by
  simp [data, evenCallable, evenBlock, valueInstruction, valueDef,
    twoBytes_eq_two8, zeroBytes_eq_zero8]

/-- Zero-state base: the closed parity invariant returns true on the product
    default overlay. Uses the zero-specialized micro-path (no general LE decode). -/
theorem initial_run_even :
    runInvariantCallableV1 data 2 initialState = .returnedTrue := by
  have hdecode' :
      decodeLogicalStateValuesV1 data initialState = .ok #[zero8BytesV1] := by
    simpa [zeroBytes_eq_zero8] using initial_state_decode
  have hcanZero :
      validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
  have hcanTwo :
      validateValueBytesV1 data.types 0 two8BytesV1 = .ok () := by
    simpa [data, types, twoBytes_eq_two8] using two_canonical
  have hcanTrue :
      validateValueBytesV1 data.types 1 (encodeU8 1) = .ok () := by
    simpa [data, types] using true_canonical
  exact runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_zero
    data initialState 2 0 1 0 (some "even") .public_ "count"
    rfl hdecode'
    (by simp [data, types, uint64Type])
    (by simp [data, types, boolType])
    rfl
    (by simp [data, countState])
    even_callable_parity_shape
    hcanZero hcanTwo hcanTrue

theorem initial_eval_even :
    evalInvariantV1 program 0 initialState = .returnedTrue :=
  evalInvariantV1_eq_of_validated_selection
    program data 0 evenInvariant initialState #[zeroBytes] .returnedTrue
    validate_ok rfl initial_state_decode (by rfl)
    (by
      change runInvariantCallableV1 data evenInvariant.callableId initialState =
        .returnedTrue
      simpa [evenInvariant] using initial_run_even)

theorem base_no_initializer : PreservationBaseNoInitializerV1 program 0 :=
  ⟨initialState, initial_state_ok, initial_state_conforms, initial_eval_even⟩

/-- No-initializer base arm of `PreservationBaseV1` for ordinal 0. -/
theorem preservation_base_no_init (admitted : AdmittedReferenceSliceV1) :
    PreservationBaseV1 program 0 admitted :=
  Or.inr ⟨no_initializer, base_no_initializer⟩

/-! ### Step packing (failure arms closed; returned deferred to micro-paths) -/

/-- Revert/trap outcomes of the sole production step always reattach the exact
    pre-state. The returned branch is left as `True` here so failure arms can
    be shared by the full step theorem. -/
theorem preservation_step_failure_arms
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1) :
    match stepReferenceSliceV1 admitted pre invocation responses vault with
    | .returned _ _ _ => True
    | .reverted reason unchangedState =>
        OutcomeRevertedUnchangedV1 pre reason unchangedState
    | .trapped fault unchangedState =>
        OutcomeTrappedUnchangedV1 pre fault unchangedState := by
  have hfail :=
    stepReferenceSliceV1_failureStateUnchangedV1 admitted pre invocation
      responses vault
  generalize hstep :
    stepReferenceSliceV1 admitted pre invocation responses vault = outcome
  cases outcome with
  | returned post value effects =>
      trivial
  | reverted reason unchanged =>
      have hfail' : OutcomeFailureStateUnchangedV1 pre
          (OutcomeV1.reverted reason unchanged) := by
        simpa [hstep] using hfail
      exact hfail'
  | trapped fault unchanged =>
      have hfail' : OutcomeFailureStateUnchangedV1 pre
          (OutcomeV1.trapped fault unchanged) := by
        simpa [hstep] using hfail
      exact hfail'

/-- Ordinal 0 is in range for the closed EvenCounter invariant table. -/
theorem ordinal_in_range : (0 : InvariantOrdinalV1).toNat < program.invariants.size := by
  -- Prefer `invariants_eq_of_validate` over unfolding the raw `validate` match:
  -- the latter can force kernel evaluation of the full wire gate under `decide`.
  rw [SemanticProgramV1.invariants_eq_of_validate program data validate_ok]
  decide

/-! ### Admission projection for step packing -/

/-- Successful admission recovers the closed program/data pair. -/
theorem admit_ok_of_exists
    (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    admitted.program = program ∧ admitted.data = data :=
  admitReferenceProgramSliceV1_ok_implies program data admitted
    validate_ok hadmit

/-- Any initialized single-slot even UInt64 overlay evaluates the ordinal-0
    invariant to `returnedTrue`. Thin packaging over the general parity micro-path.
    Callers must supply evenness of `leBytesToNatV1 countBytes`. -/
theorem eval_even_of_count_even
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (heven : leBytesToNatV1 countBytes % 2 = 0) :
    evalInvariantV1 program 0 state = .returnedTrue := by
  have hcanTwo :
      validateValueBytesV1 data.types 0 two8BytesV1 = .ok () := by
    simpa [data, types, twoBytes_eq_two8] using two_canonical
  have hcanZero :
      validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
    simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
  have hcanTrue :
      validateValueBytesV1 data.types 1 (encodeU8 1) = .ok () := by
    simpa [data, types] using true_canonical
  have hrun :
      runInvariantCallableV1 data 2 state = .returnedTrue :=
    runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_even
      data state countBytes 2 0 1 0 (some "even") .public_ "count"
      hinit hdecode
      (by simp [data, types, uint64Type])
      (by simp [data, types, boolType])
      rfl
      (by simp [data, countState])
      even_callable_parity_shape
      hcan hcanTwo hcanZero hcanTrue heven
  exact evalInvariantV1_eq_of_validated_selection
    program data 0 evenInvariant state #[countBytes] .returnedTrue
    validate_ok hinit hdecode (by rfl)
    (by
      change runInvariantCallableV1 data evenInvariant.callableId state =
        .returnedTrue
      simpa [evenInvariant] using hrun)

/-- Converse packaging: ordinal-0 true on a decoded UInt64 overlay implies even
    payload. Uses the closed odd micro-path for contradiction. -/
theorem count_even_of_eval_true
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (heval : evalInvariantV1 program 0 state = .returnedTrue) :
    leBytesToNatV1 countBytes % 2 = 0 := by
  by_cases he : leBytesToNatV1 countBytes % 2 = 0
  · exact he
  · have hodd : leBytesToNatV1 countBytes % 2 = 1 := by omega
    have hcanTwo :
        validateValueBytesV1 data.types 0 two8BytesV1 = .ok () := by
      simpa [data, types, twoBytes_eq_two8] using two_canonical
    have hcanZero :
        validateValueBytesV1 data.types 0 zero8BytesV1 = .ok () := by
      simpa [data, types, zeroBytes_eq_zero8] using zero_canonical
    have hcanFalse :
        validateValueBytesV1 data.types 1 (encodeU8 0) = .ok () := by
      simpa [data, types] using false_canonical
    have hrun :
        runInvariantCallableV1 data 2 state = .returnedFalse :=
      runInvariantCallableV1_eq_returnedFalse_of_uint64_parity_odd
        data state countBytes 2 0 1 0 (some "even") .public_ "count"
        hinit hdecode
        (by simp [data, types, uint64Type])
        (by simp [data, types, boolType])
        rfl
        (by simp [data, countState])
        even_callable_parity_shape
        hcan hcanTwo hcanZero hcanFalse hodd
    have heval' :
        evalInvariantV1 program 0 state = .returnedFalse :=
      evalInvariantV1_eq_of_validated_selection
        program data 0 evenInvariant state #[countBytes] .returnedFalse
        validate_ok hinit hdecode (by rfl)
        (by
          change runInvariantCallableV1 data evenInvariant.callableId state =
            .returnedFalse
          simpa [evenInvariant] using hrun)
    rw [heval] at heval'
    cases heval'

/-! ### Get-returned packaging (no heavy evenness extract)

    Callers that already hold `leBytesToNatV1 countBytes % 2 = 0` (e.g. from a
    future extract module, or a specialized micro-path) can re-evaluate after
    the production single-slot encode used by get finalize.
-/

/-- Even overlay encoded as the closed single-slot layout evaluates true. -/
theorem eval_even_of_encoded_uint64
    (countBytes : ByteArray)
    (initialized : Bool)
    (hinit : initialized = true)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0) :
    evalInvariantV1 program 0 {
      initialized
      canonicalValues := (encodeU32le 8).append countBytes
    } = .returnedTrue := by
  let state : LogicalStateV1 := {
    initialized
    canonicalValues := (encodeU32le 8).append countBytes
  }
  have hdecode :
      decodeLogicalStateValuesV1 data state = .ok #[countBytes] := by
    simpa [state, data, countState] using
      decodeLogicalStateValuesV1_of_single_uint64_encode data countState
        countBytes initialized (by simp [data, countState]) hcan hsize
  have hinit' : state.initialized = true := by simpa [state] using hinit
  simpa [state] using
    eval_even_of_count_even state countBytes hinit' hdecode hcan heven

/-- Encode of a single even UInt64 overlay is the post-state get finalize uses. -/
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

/-- After get-shaped encode of an even overlay, the invariant still holds. -/
theorem eval_even_after_get_encode
    (countBytes : ByteArray)
    (post : LogicalStateV1)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    evalInvariantV1 program 0 post = .returnedTrue := by
  have henc := encode_even_overlay_eq_ok countBytes hcan hsize
  have hpost :
      post = {
        initialized := true
        canonicalValues := (encodeU32le 8).append countBytes
      } := by
    have : encodeLogicalStateValuesV1 data true #[countBytes] =
        .ok {
          initialized := true
          canonicalValues := (encodeU32le 8).append countBytes
        } := henc
    rw [this] at hencode
    exact (Except.ok.inj hencode).symm
  rw [hpost]
  exact eval_even_of_encoded_uint64 countBytes true rfl hcan hsize heven

/-- Get finalize of a pre-state that already decodes to an 8-byte overlay is
    identity on the carrier (`post = pre`). Avoids re-extracting evenness. -/
theorem get_encode_post_eq_pre
    (pre post : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    post = pre :=
  encode_of_singleton_uint64_decode_eq data countState pre post countBytes
    (by simp [data, countState]) hinit hdecode hcan hsize hencode

/-- Get-returned: if pre is even and finalize re-encodes the same overlay,
    post remains even by `post = pre`. -/
theorem eval_even_after_get_returned
    (pre post : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    evalInvariantV1 program 0 post = .returnedTrue := by
  have hpost : post = pre :=
    get_encode_post_eq_pre pre post countBytes hinit hdecode hcan hsize hencode
  rw [hpost]
  exact eval_even_of_count_even pre countBytes hinit hdecode hcan heven

/-! ### Increment packaging (encode form; runMachine path still open)

    After a successful non-overflowing +2, the sum payload is still even and
    size-8, so the single-slot encode form evaluates the invariant true.
-/

/-- Sum bytes after a legal UInt64 +2 stay even and size-8. -/
theorem increment_sum_bytes_even
    (countBytes : ByteArray)
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    sumBytes.size = 8 ∧ leBytesToNatV1 sumBytes % 2 = 0 := by
  have h :=
    add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  exact ⟨h.1, h.2.1⟩

/-- Encoded post-state after increment +2 (no overflow) keeps the invariant. -/
theorem eval_even_after_increment_encode
    (countBytes : ByteArray)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    evalInvariantV1 program 0 {
      initialized := true
      canonicalValues := (encodeU32le 8).append sumBytes
    } = .returnedTrue := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have hsum :=
    add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  have hcanSum :
      validateValueBytesV1 data.types 0 sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Type sumBytes
      (by simp [data, types, uint64Type]) (by rfl) hsum.1
  -- silence unused pre-canonicity (documents pre overlay was gated)
  let _ := hcan
  exact eval_even_of_encoded_uint64 sumBytes true rfl hcanSum hsum.1 hsum.2.1

/-- Encode of the +2 sum overlay under EvenCounter data. -/
theorem encode_increment_sum_eq_ok
    (countBytes : ByteArray)
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    encodeLogicalStateValuesV1 data true #[sumBytes] = .ok {
      initialized := true
      canonicalValues := (encodeU32le 8).append sumBytes
    } := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have hsum :=
    add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  have hcanSum :
      validateValueBytesV1 data.types 0 sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Type sumBytes
      (by simp [data, types, uint64Type]) (by rfl) hsum.1
  simpa [sumBytes] using
    encodeLogicalStateValuesV1_single_uint64_eq_ok data countState sumBytes true
      (by simp [data, countState]) hcanSum hsum.1

/-- After increment micro-path finalize encode of the +2 overlay, invariant holds. -/
theorem eval_even_after_increment_finalize
    (countBytes : ByteArray)
    (post : LogicalStateV1)
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8] = .ok post) :
    evalInvariantV1 program 0 post = .returnedTrue := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have henc := encode_increment_sum_eq_ok countBytes hsize heven hnoOverflow
  have hpost :
      post = {
        initialized := true
        canonicalValues := (encodeU32le 8).append sumBytes
      } := by
    have :
        encodeLogicalStateValuesV1 data true #[sumBytes] = .ok {
          initialized := true
          canonicalValues := (encodeU32le 8).append sumBytes
        } := henc
    change encodeLogicalStateValuesV1 data true #[sumBytes] = .ok post at hencode
    rw [this] at hencode
    exact (Except.ok.inj hencode).symm
  rw [hpost]
  have hsum :=
    add_two_uint64_sum_bytes_even countBytes hsize heven hnoOverflow
  have hcanSum :
      validateValueBytesV1 data.types 0 sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Type sumBytes
      (by simp [data, types, uint64Type]) (by rfl) hsum.1
  exact eval_even_of_encoded_uint64 sumBytes true rfl hcanSum hsum.1 hsum.2.1

end ProofForgeV2.ProofInstances.EvenCounterPreservationV1
