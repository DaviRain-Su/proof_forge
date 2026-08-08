import ProofForgeV2.ProofInstances.EvenCounterDecodeV1
import ProofForgeV2.Semantic.PreservationPackagingV1

namespace ProofForgeV2.ProofInstances.EvenCounterPreservationV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationPackagingV1
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

-- Failure-arm packaging is sole-owned by
-- `PreservationPackagingV1.preservationStepFailureArmsV1` (no instance alias).

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

/-- Get finalize of a pre-state that already decodes to a singleton overlay is
    identity on the carrier (`post = pre`). Avoids re-extracting evenness. -/
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

/-- Get-returned: if pre is even and finalize re-encodes the same overlay,
    post remains even by carrier-identity packaging (`post = pre`). -/
theorem eval_even_after_get_returned
    (pre post : LogicalStateV1)
    (countBytes : ByteArray)
    (hinit : pre.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data pre = .ok #[countBytes])
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post) :
    evalInvariantV1 program 0 post = .returnedTrue :=
  preservationStepReturnedPostEqPreV1 program 0 pre post
    (eval_even_of_count_even pre countBytes hinit hdecode hcan heven)
    (get_encode_post_eq_pre pre post countBytes hinit hdecode hcan hencode)

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

/-! ### PreservationStep packing (partial)

    Gate analysis helpers + failure arms are closed. Full `PreservationStepV1`
    still needs ready-overlay equality from `gateInvocation` joined to the
    get/increment `runMachine` micro-paths (next slice).
-/

/-- EvenCounter get/increment callables are nullary. -/
theorem get_params_empty : getCallable.params = #[] := rfl
theorem increment_params_empty : incrementCallable.params = #[] := rfl

-- Returned-gate and post=pre packaging are sole-owned by
-- `PreservationPackagingV1.stepReturnedImpliesGateReadyV1` and
-- `preservationStepReturnedPostEqPreV1` (no instance aliases).

/-- Returned arm when post is the non-overflowing +2 encode of an even pre overlay. -/
theorem preservation_step_returned_increment_form
    (countBytes : ByteArray)
    (post : LogicalStateV1)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ())
    (hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hpost :
      post = {
        initialized := true
        canonicalValues :=
          (encodeU32le 8).append
            (natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8)
      }) :
    evalInvariantV1 program 0 post = .returnedTrue := by
  rw [hpost]
  exact eval_even_after_increment_encode countBytes hcan hsize heven hnoOverflow

/-- Payload size 8 for validated UInt64 countBytes on EvenCounter.
    Uses program-agnostic UInt64 size packaging. -/
theorem countBytes_size_of_can
    (countBytes : ByteArray)
    (hcan : validateValueBytesV1 data.types 0 countBytes = .ok ()) :
    countBytes.size = 8 := by
  have hlookup : data.types[0]? = some uint64Type := by
    simp [data, types, uint64Type]
  exact uint64BytesSizeOfValidateV1 data.types 0 uint64Type countBytes
    hlookup rfl hcan

/-- Closed get-callable shape used by the ready-get step packaging. -/
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

/-- Closed increment-callable shape used by the ready-increment packaging. -/
theorem increment_callable_ready_shape :
    incrementCallable = {
      id := 0
      kind := .entry
      name := some "increment"
      params := #[]
      result := { typeId := 0, visibility := .public_ }
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
            op := .binary .add 0 1 },
          { result := none, op := .stateStore 0 2 },
          { result := some { valueId := 3, typeId := 0 },
            op := .stateLoad 0 }
        ]
        terminator := .return_ (some 3)
      }]
      loopBounds := #[]
      invariantSteps := none
    } := by
  simp [incrementCallable, incrementBlock, valueInstruction, valueDef,
    voidInstruction, twoBytes_eq_two8]

/-- Type / state table facts for EvenCounter packaging. -/
theorem types_uint64 : data.types[0]? = some {
    id := 0, name := none, shape := .uint 64 } := by
  simp [data, types, uint64Type]

theorem state_count : data.logicalState[0]? = some {
    id := 0, name := "count", typeId := 0, visibility := .public_ } := by
  simp [data, countState]

theorem can_two :
    validateValueBytesV1 data.types 0 two8BytesV1 = .ok () := by
  simpa [data, types, twoBytes_eq_two8] using two_canonical

/-- Universal one-step preservation for ordinal 0 on closed EvenCounter. -/
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
  have heven :=
    count_even_of_eval_true pre countBytes hinit hdecode' hcan heval
  have hsize := countBytes_size_of_can countBytes hcan
  have hfail :=
    preservationStepFailureArmsV1 admitted pre invocation responses vault
  have hadmitted_data : admitted.data = data := hdata
  have htypeU := types_uint64
  have hstate := state_count
  have hcanTwo := can_two
  have htable :
      data.callables = #[incrementCallable, getCallable, evenCallable] := rfl
  generalize hstep :
    stepReferenceSliceV1 admitted pre invocation responses vault = outcome
  cases outcome with
  | returned post value effects =>
      -- Gate packaging: returned forces ready (invalid/lifecycle are False).
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
          -- Membership in the closed three-row table.
          have hsz : data.callables.size = 3 := by simp [htable]
          have hidx_lt : invocation.callableId.toNat < 3 := by
            have : invocation.callableId.toNat < data.callables.size := by
              -- `some` lookup implies in-range index.
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
            have hcall : callable = incrementCallable := by
              have : data.callables[0]? = some callable := by
                simpa [hidx] using hlookup'
              have : some incrementCallable = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hisInit : isInitializer = false := by
              have h := hisInitEq
              rw [hcall] at h
              -- entry kind ⇒ not initializer flag
              change isInitializer = (incrementCallable.kind == .initializer) at h
              simp only [incrementCallable, BEq.beq, decide_false, Bool.false_eq]
                at h
              exact h
            have hgate' :
                gateInvocation admitted pre invocation =
                  .ready incrementCallable overlay context false := by
              simpa [hcall, hisInit] using hgate
            have hgate_dec :=
              gateInvocation_ready_noninit_decode admitted pre invocation
                incrementCallable overlay context hgate'
            have hoverlay : overlay = #[countBytes] := by
              have hdec_data :
                  decodeLogicalStateValuesV1 data pre = .ok overlay := by
                simpa [hdata] using hgate_dec.1
              have h1 := hdecode'; have h2 := hdec_data
              rw [h2] at h1
              exact Except.ok.inj h1
            have hgate_inc :
                gateInvocation admitted pre invocation =
                  .ready {
                    id := 0, kind := .entry, name := some "increment",
                    params := #[],
                    result := { typeId := 0, visibility := .public_ },
                    entryBlock := 0,
                    blocks := #[{
                      id := 0, params := #[],
                      instructions := #[
                        { result := some { valueId := 0, typeId := 0 },
                          op := .stateLoad 0 },
                        { result := some { valueId := 1, typeId := 0 },
                          op := .literal 0 two8BytesV1 },
                        { result := some { valueId := 2, typeId := 0 },
                          op := .binary .add 0 1 },
                        { result := none, op := .stateStore 0 2 },
                        { result := some { valueId := 3, typeId := 0 },
                          op := .stateLoad 0 }],
                      terminator := .return_ (some 3) }],
                    loopBounds := #[], invariantSteps := none
                  } #[countBytes] context false := by
              have hshape := increment_callable_ready_shape
              simpa [hgate', hoverlay, hshape, hcall]
            by_cases hov : leBytesToNatV1 countBytes + 2 < 2 ^ 64
            · by_cases hresp : responses.size = 0
              · let sumBytes :=
                  natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
                have henc' :=
                  encode_increment_sum_eq_ok countBytes hsize heven hov
                have hstep_inc :=
                  stepReferenceSliceV1_ready_increment_returned admitted pre
                    invocation data countBytes 0 0 "count" 0 (some "increment")
                    {
                      initialized := true
                      canonicalValues := (encodeU32le 8).append sumBytes
                    } responses vault context hadmitted_data htypeU hstate
                    rfl hcan hcanTwo hov hinit henc' hresp hgate_inc
                have hpost :
                    post = {
                      initialized := true
                      canonicalValues := (encodeU32le 8).append sumBytes
                    } := by
                  have h1 := hstep; have h2 := hstep_inc
                  rw [h2] at h1
                  injection h1 with hpost' _ _
                  exact hpost'.symm
                exact preservation_step_returned_increment_form countBytes post
                  hcan hsize heven hov hpost
              · have htrap :=
                  stepReferenceSliceV1_ready_increment_nonempty_responses_traps
                    admitted pre invocation data countBytes 0 0 "count" 0
                    (some "increment") responses vault context hadmitted_data
                    htypeU hstate rfl hcan hcanTwo hov (by exact hresp)
                    hgate_inc
                rw [htrap] at hstep; cases hstep
            · have hne :=
                stepReferenceSliceV1_ready_increment_overflow_not_returned
                  admitted pre invocation data countBytes 0 0 "count" 0
                  (some "increment") responses vault context post value effects
                  hadmitted_data htypeU hstate rfl hcan hcanTwo hov hgate_inc
              exact absurd hstep hne
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
            have hcall : callable = evenCallable := by
              have : data.callables[2]? = some callable := by
                simpa [hidx] using hlookup'
              have : some evenCallable = some callable := by
                simpa [htable] using this
              exact (Option.some.inj this).symm
            have hkind : callable.kind = .invariant := by
              simp [hcall, evenCallable]
            have hkindOk :
                (callable.kind == .initializer ||
                  callable.kind == .entry ||
                  callable.kind == .view) = false := by
              rw [hkind]
              decide
            -- Ready requires kind initializer|entry|view; invariant fails.
            -- With invariant kind, the gate kind filter yields invalidInvocation.
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

/-- Full L1 preservation theorem for EvenCounter ordinal 0. -/
theorem preservation_theorem :
    PreservationTheoremV1 program 0 := by
  refine ⟨ordinal_in_range, ?_⟩
  rcases admit_exists with ⟨admitted, hadmit⟩
  exact ⟨admitted, hadmit, preservation_base_no_init admitted,
    preservation_step admitted hadmit⟩

/-- Product-facing transport: any `SemanticProgramV1` whose exact canonical
    bytes match the closed EvenCounter instance inherits ordinal-0 preservation.
    Product author theorems use this with `EvenCounter.Proof.subjectProgramV1`
    once subject bytes are definitionally the closed instance. -/
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


end ProofForgeV2.ProofInstances.EvenCounterPreservationV1
