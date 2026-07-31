import ProofForgeV2.Semantic.InvariantFoundationV1
import ProofForgeV2.Semantic.ReferenceMachineV1

/-
  ProofForgeV2.Semantic.InvariantABI — public invariant proof ABI façade.

  The state carrier, canonical state codec/defaults, and StateConformsV1 are
  defined by the lower InvariantFoundationV1 module under this same namespace.
  This façade owns evalInvariantV1 / InvariantTheoremV1 and depends on the
  lower machine without creating a cycle back through the public façade.
-/

namespace ProofForgeV2.Semantic.InvariantABI

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

end ProofForgeV2.Semantic.InvariantABI
