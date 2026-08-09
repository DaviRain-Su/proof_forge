import ProofForgeV2

/-
  The sole Counter example.

  The business program, executable invariant, proof binding, and ordinary Lean
  preservation theorem live together in this file. The theorem uses only the
  generated subject declarations and contract-agnostic Semantic/Reference
  libraries; there is no Counter registry, closed byte golden, pin, alternate
  decoder, or contract-specific compiler branch.

  Engineering L1 example only. It does not claim target refinement, formal
  TASK/TST completion, hermeticity, or release qualification.
-/

namespace Examples

open ProofForgeV2.Language

program Counter where
  state count : UInt64

  entry increment() : UInt64 do
    count := count + 2
    return count

  view get() : UInt64 do
    return count

  invariant even : count % 2 == 0
  proof even preserving using CounterProof.even

/- The ordinal-zero parity invariant is preserved by every admitted Reference
   step of this exact generated subject, including checked-arithmetic rollback. -/
theorem CounterProof.even : Counter.ProofPreserving.even := by
  exact
    ProofForgeV2.Semantic.UInt64ParityPreservationV1.preservationTheorem_of_subjectBodyV1
      Counter.Proof.subjectDataV1.qualifiedName
      "count" "increment" "get" "even" Counter.Proof.subjectBytesV1
      (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by decide)
      Counter.Proof.subjectBodyEncodeOkV1

end Examples
