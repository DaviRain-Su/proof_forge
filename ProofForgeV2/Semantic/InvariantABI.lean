import ProofForgeV2.Semantic.InvariantFoundationV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.ReferenceMachineV1

/-
  ProofForgeV2.Semantic.InvariantABI — public invariant proof ABI façade.

  The state carrier, canonical state codec/defaults, and StateConformsV1 are
  defined by the lower InvariantFoundationV1 module under this same namespace.
  This façade owns evalInvariantV1 / InvariantTheoremV1 and depends on the
  lower machine without creating a cycle back through the public façade.

  N5b note (engineering): invariant callables cannot contain `Op.ContextRead`
  or `Op.Commit` (Wire structure gate on roots and reachable pureFn closure).
  `evalInvariantV1` therefore never supplies invocation context and never
  steps those ops; ContextRead/Commit product step semantics live solely on
  `stepReferenceSliceV1` for init/entry/view roots.
-/

namespace ProofForgeV2.Semantic.InvariantABI

open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Total canonical invariant evaluator (SPEC-SEM-WIRE-001 §8).

    The carrier is validated before ordinal/state selection. Execution uses
    only the selected invariant callable and its Wire-validated pure closure;
    it never consults whole-program engineering admission or external inputs. -/
def evalInvariantV1
    (program : SemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (state : LogicalStateV1) : InvariantEvalResultV1 :=
  match validateSemanticProgramV1 program with
  | .error _ => .trapped
  | .ok data =>
      match data.invariants[invariantOrdinal.toNat]? with
      | none => .trapped
      | some invariant =>
          if !state.initialized then
            .trapped
          else
            match decodeLogicalStateValuesV1 data state with
            | .error _ => .trapped
            | .ok _ => runInvariantCallableV1 data invariant.callableId state

/-- Canonical invariant theorem proposition (SPEC-SEM-WIRE-001 §8). -/
def InvariantTheoremV1
    (program : SemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1) : Prop :=
  invariantOrdinal.toNat < program.invariants.size ∧
  ∀ state : LogicalStateV1,
    StateConformsV1 program state →
    evalInvariantV1 program invariantOrdinal state = .returnedTrue

/-- Compose one exact public evaluator result without unfolding a closed
    carrier at the proof site. Every premise is an equality from the sole
    production validation, state decoder, ordinal table, and invariant runner. -/
theorem evalInvariantV1_eq_of_validated_selection
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (state : LogicalStateV1)
    (overlay : Array ByteArray)
    (result : InvariantEvalResultV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok overlay)
    (hselection : data.invariants[invariantOrdinal.toNat]? = some invariant)
    (hrun : runInvariantCallableV1 data invariant.callableId state = result) :
    evalInvariantV1 program invariantOrdinal state = result := by
  simp only [evalInvariantV1, hvalidate, hinitialized, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, hselection, hdecode, hrun]

/-- Close the exact public invariant proposition from a successful production
    validation, the decoded table bound, and the production evaluator theorem. -/
theorem invariantTheoremV1_of_validate_eq_ok
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hbound : invariantOrdinal.toNat < data.invariants.size)
    (heval : ∀ state : LogicalStateV1,
      StateConformsV1 program state →
      evalInvariantV1 program invariantOrdinal state = .returnedTrue) :
    InvariantTheoremV1 program invariantOrdinal := by
  constructor
  · unfold SemanticProgramV1.invariants
    rw [hvalidate]
    exact hbound
  · exact heval

/-- Close `InvariantTheoremV1` from a proof-carrying validated carrier (exact
    product program + production validation witness). Authors still prove the
    evaluator obligation; wire validation is already packaged. -/
theorem invariantTheoremV1_of_validated
    (carrier : ValidatedSemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (hbound : invariantOrdinal.toNat < carrier.data.invariants.size)
    (heval : ∀ state : LogicalStateV1,
      StateConformsV1 carrier.program state →
      evalInvariantV1 carrier.program invariantOrdinal state = .returnedTrue) :
    InvariantTheoremV1 carrier.program invariantOrdinal :=
  invariantTheoremV1_of_validate_eq_ok
    carrier.program carrier.data invariantOrdinal carrier.hvalidate hbound heval

/-- Out-of-range ordinals never satisfy `InvariantTheoremV1` on a validated
    carrier (ordinal mutation negative). -/
theorem not_invariantTheoremV1_of_oob_ordinal
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hoob : ¬ invariantOrdinal.toNat < data.invariants.size) :
    ¬ InvariantTheoremV1 program invariantOrdinal := by
  intro htheorem
  have hbound := htheorem.1
  have hinv : program.invariants = data.invariants :=
    SemanticProgramV1.invariants_eq_of_validate program data hvalidate
  rw [hinv] at hbound
  exact hoob hbound

/-- Close validation (and therefore the wire half of the theorem bridge) from
    sole production encode + decode of the same data. -/
theorem validateSemanticProgramV1_eq_ok_of_encode_decode_bridge
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    validateSemanticProgramV1 ⟨bytes⟩ = .ok data :=
  validateSemanticProgramV1_eq_ok_of_encode_decode data bytes hencode hdecode

end ProofForgeV2.Semantic.InvariantABI
