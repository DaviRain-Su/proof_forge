import ProofForgeV2.Semantic.Wire.CodecInvertTypeTableV1
import ProofForgeV2.Semantic.Wire.CodecInvertDeclTablesV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootV1

/-!
  ProofForgeV2.Semantic.Wire.CodecInvertRootFieldsV1 — assembling
  `RootFieldInvertV1` for **arbitrary** programs.

  Seven of the nine root fields of `RootFieldInvertV1` are discharged here for
  arbitrary data, using only the production encoders/decoders:

    * `qualifiedName` (`Wire.CodecInvertFieldsV1`),
    * `types`         (`Wire.CodecInvertTypeTableV1`),
    * `constants`, `logicalState`, `events`, `errors`
                      (`Wire.CodecInvertDeclTablesV1`),
    * `invariants`    (`Wire.CodecInvertFieldsV1`).

  The remaining two fields — `callables` and `requirements` — stay explicit
  hypotheses, so the residual of the generic encode→decode roundtrip is exactly
  those two families.

  The table-size side conditions are *not* extra assumptions: they are extracted
  from the production `checkTableSize` gates of a successful root encode.

  No axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common

/-! ### Gate extraction from a successful root encode -/

theorem except_bind_unit_okV1 {ε α : Type} {x : Except ε Unit} {y : Except ε α}
    {a : α} (h : x >>= (fun _ => y) = .ok a) : x = .ok () ∧ y = .ok a := by
  cases x with
  | error e => simp only [Bind.bind, Except.bind] at h; cases h
  | ok u =>
      cases u
      simp only [Bind.bind, Except.bind] at h
      exact ⟨rfl, h⟩

theorem checkTableSize_ok_leV1 (n : Nat) (h : checkTableSize n = .ok ()) :
    n ≤ maxTableElements := by
  by_cases hn : n ≤ maxTableElements
  · exact hn
  · exfalso
    simp only [checkTableSize, hn, Bool.false_eq_true, ↓reduceIte, err, Bind.bind,
      Except.bind, decide_false] at h
    cases h

/-- The production root encoder's `checkTableSize` gates, read off a successful
    encode. -/
theorem encodeSemanticProgramData_ok_table_sizesV1 (p : SemanticProgramDataV1)
    (bytes : ByteArray) (h : encodeSemanticProgramDataV1 p = .ok bytes) :
    p.types.size ≤ maxTableElements ∧ p.constants.size ≤ maxTableElements ∧
      p.logicalState.size ≤ maxTableElements ∧ p.events.size ≤ maxTableElements ∧
      p.errors.size ≤ maxTableElements ∧ p.callables.size ≤ maxTableElements ∧
      p.invariants.size ≤ maxTableElements := by
  simp only [encodeSemanticProgramDataV1] at h
  obtain ⟨_, h⟩ := except_bind_unit_okV1 h
  obtain ⟨htypes, h⟩ := except_bind_unit_okV1 h
  obtain ⟨hconstants, h⟩ := except_bind_unit_okV1 h
  obtain ⟨hstate, h⟩ := except_bind_unit_okV1 h
  obtain ⟨hevents, h⟩ := except_bind_unit_okV1 h
  obtain ⟨herrors, h⟩ := except_bind_unit_okV1 h
  obtain ⟨hcallables, h⟩ := except_bind_unit_okV1 h
  obtain ⟨hinvariants, _⟩ := except_bind_unit_okV1 h
  exact ⟨checkTableSize_ok_leV1 _ htypes, checkTableSize_ok_leV1 _ hconstants,
    checkTableSize_ok_leV1 _ hstate, checkTableSize_ok_leV1 _ hevents,
    checkTableSize_ok_leV1 _ herrors, checkTableSize_ok_leV1 _ hcallables,
    checkTableSize_ok_leV1 _ hinvariants⟩

/-! ### The remaining generic root fields -/

/-- The `qualifiedName` field of `RootFieldInvertV1`, for an arbitrary name. -/
theorem exactMidOffsetInvertAt_qualifiedNameV1 (name : QualifiedName) :
    ExactMidOffsetInvertAtV1 encodeQualifiedName decodeQualifiedName name 1 :=
  ExactMidOffsetInvertAtV1.ofExact (exactMidOffsetInvert_qualifiedName name) (by decide)

/-- The `invariants` field of `RootFieldInvertV1`, for an arbitrary table within
    the production table-size gate. -/
theorem exactMidOffsetInvertAt_invariantsTableV1 (xs : Array InvariantDeclV1)
    (hsize : xs.size ≤ maxTableElements) :
    ExactMidOffsetInvertAtV1 (encodeArray encodeInvariantDeclV1)
      (decodeArray maxTableElements decodeInvariantDeclV1) xs 1 := by
  refine exactMidOffsetInvertAt_of_fieldReadV1 (fun b hb => ?_)
  obtain ⟨_, hall⟩ := encodeArray_ok_inversionV1 _ xs b hb
  refine fieldRead_arrayV1 _ _ maxTableElements xs b 1 hsize (by decide)
    (Nat.le_trans hsize (by decide)) hall ?_ hb
  intro x _
  exact ExactMidOffsetInvertAtV1.ofGlobal
    midOffsetInvert_encodeInvariantDecl_decodeInvariantDecl x (by decide)

/-! ### Root assembly -/

/-- `RootFieldInvertV1` for an **arbitrary** program, modulo the two residual
    field families `callables` and `requirements`. -/
theorem rootFieldInvertV1_of_callables_requirementsV1 (data : SemanticProgramDataV1)
    (htypes : data.types.size ≤ maxTableElements)
    (hconstants : data.constants.size ≤ maxTableElements)
    (hstate : data.logicalState.size ≤ maxTableElements)
    (hevents : data.events.size ≤ maxTableElements)
    (herrors : data.errors.size ≤ maxTableElements)
    (hinvariants : data.invariants.size ≤ maxTableElements)
    (hcallables : ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1) data.callables 1)
    (hrequirements : ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 data.requirements 1) :
    RootFieldInvertV1 data where
  qualifiedName := exactMidOffsetInvertAt_qualifiedNameV1 data.qualifiedName
  types := exactMidOffsetInvertAt_typeTableV1 data.types htypes
  constants := exactMidOffsetInvertAt_constantsTableV1 data.constants hconstants
  logicalState := exactMidOffsetInvertAt_logicalStateTableV1 data.logicalState hstate
  events := exactMidOffsetInvertAt_eventsTableV1 data.events hevents
  errors := exactMidOffsetInvertAt_errorsTableV1 data.errors herrors
  callables := hcallables
  invariants := exactMidOffsetInvertAt_invariantsTableV1 data.invariants hinvariants
  requirements := hrequirements

/-- Generic encode→decode roundtrip of the production semantic-program codec,
    for an **arbitrary** program, modulo invertibility of the two residual field
    families `callables` and `requirements`.

    All table-size side conditions are discharged from the production gates of
    the successful encode itself. -/
theorem decodeSemanticProgramDataV1_of_encode_ok_of_callables_requirementsV1
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hcallables : ExactMidOffsetInvertAtV1 (encodeArray encodeCallableV1)
      (decodeArray maxTableElements decodeCallableV1) data.callables 1)
    (hrequirements : ExactMidOffsetInvertAtV1 encodeProgramRequirementsV1
      decodeProgramRequirementsV1 data.requirements 1) :
    decodeSemanticProgramDataV1 bytes = .ok data := by
  obtain ⟨htypes, hconstants, hstate, hevents, herrors, _, hinvariants⟩ :=
    encodeSemanticProgramData_ok_table_sizesV1 data bytes hencode
  exact decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert data bytes hencode
    (rootFieldInvertV1_of_callables_requirementsV1 data htypes hconstants hstate
      hevents herrors hinvariants hcallables hrequirements)

end ProofForgeV2.Semantic.WireV1
