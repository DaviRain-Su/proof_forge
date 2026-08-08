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
  have hroot : data.callables[2]? = some evenCallable := by
    simp [data, evenCallable]
  -- Align the closed EvenCounter evenCallable with the micro-path shape.
  have hshape :
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
  exact runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_zero
    data initialState 2 0 1 0 (some "even") .public_ "count"
    rfl hdecode'
    (by simp [data, types, uint64Type])
    (by simp [data, types, boolType])
    rfl
    (by simp [data, countState])
    hshape
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
  unfold SemanticProgramV1.invariants
  rw [validate_ok]
  decide

end ProofForgeV2.ProofInstances.EvenCounterPreservationV1
