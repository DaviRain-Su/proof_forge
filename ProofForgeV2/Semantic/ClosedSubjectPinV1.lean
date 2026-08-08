import Lean
import ProofForgeV2.ProofInstances.EvenCounterPreservationV1
import ProofForgeV2.ProofInstances.EvenCounterV1

/-!
  Closed semantic-byte pins for product proof subjects.

  Product elaborator emits `subjectBytesV1` / `subjectProgramV1` for every
  program that normalizes. When the carrier bytes exactly match a registered
  closed instance, subject bytes are defined as **that shared constant** so
  author theorems can `exact` instance-level `PreservationTheoremV1` /
  `InvariantTheoremV1` proofs without large spine reduction.

  **Product env coupling:** the product session imports only
  `ProgramElaborationV1` (and its transitive graph). Closed-instance *proof*
  modules (e.g. `EvenCounterPreservationV1`) must therefore be imported from
  this pin module (or another ProgramElaboration dependency) so author
  theorems can name them. New closed instances: add pin row + import proof
  module. Unpinned / arbitrary contracts need no pin; authors prove against
  `subjectProgramV1` with generic lemmas.

  Engineering table only — not formal completeness of all contracts.
-/

namespace ProofForgeV2.Semantic.ClosedSubjectPinV1

open ProofForgeV2.ProofInstances

/-- Fully-qualified `ByteArray` constants that product `subjectBytesV1` may
    alias. Certifier may follow exactly one hop into these names. -/
def closedSubjectBytePinNamesV1 : Array Lean.Name := #[
  ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes
]

/-- Runtime pin lookup by exact carrier bytes (elaborator meta path). -/
def resolveClosedSubjectBytesPinNameV1 (bytes : ByteArray) : Option Lean.Name :=
  if bytes == EvenCounterV1.canonicalBytes then
    some ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes
  else
    none

/-- Membership for certifier one-hop const follow (fail closed on unknown). -/
def isClosedSubjectBytePinNameV1 (name : Lean.Name) : Bool :=
  closedSubjectBytePinNamesV1.any (· == name)

/-- Exact bytes for a registered pin name (certifier identity; no Expr eval). -/
def closedSubjectBytePinBytesV1 (name : Lean.Name) : Option ByteArray :=
  if name == ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes then
    some EvenCounterV1.canonicalBytes
  else
    none

end ProofForgeV2.Semantic.ClosedSubjectPinV1
