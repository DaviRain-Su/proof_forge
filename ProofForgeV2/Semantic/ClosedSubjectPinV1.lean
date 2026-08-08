import Lean
import ProofForgeV2.ProofInstances.EvenCounterPreservationV1
import ProofForgeV2.ProofInstances.EvenCounterV1
import ProofForgeV2.ProofInstances.ZeroCounterPreservationV1
import ProofForgeV2.ProofInstances.ZeroCounterV1

/-!
  Closed semantic-byte pins for product proof subjects.

  Product elaborator emits `subjectBytesV1` / `subjectProgramV1` for every
  program that normalizes. When the carrier bytes exactly match a registered
  closed instance, subject bytes are defined as **that shared constant** so
  author theorems can `exact` instance-level `PreservationTheoremV1` /
  `InvariantTheoremV1` proofs without large spine reduction.

  ## Non-pin author path (primary for arbitrary contracts)

  Pin is an **optional golden accelerator**, not the product obligation surface.

  1. **Unpinned program** (no table row): elaborator emits a structural
     `subjectBytesV1` spine. Certifier follows product `subjectBytesV1` →
     structural decode (no pin hop). Authors prove
     `PreservationTheoremV1 subjectProgramV1 ordinal` with
     `PreservationPackagingV1` lemmas + instance-specific step packing, or
     transport via byte-equality (e.g. `preservation_theorem_of_eq_bytes`
     when a closed package theorem exists for matching bytes).
  2. **Pinned golden** (exact byte match): elaborator aliases
     `subjectBytesV1` to the shared pin constant; certifier may take **one**
     pin-name hop for identity. Convenience only.
  3. **Never** grow the pin table as the only way to prove a new contract.

  **Product env coupling:** the product session imports only
  `ProgramElaborationV1` (and its transitive graph). Closed-instance *proof*
  modules (e.g. `EvenCounterPreservationV1`, `ZeroCounterPreservationV1`) must
  therefore be imported from this pin module (or another ProgramElaboration
  dependency) so author theorems can name them. New closed instances: add pin
  row + import proof module **only when** golden exact-defeq is wanted.

  Engineering table only — not formal completeness of all contracts.
-/

namespace ProofForgeV2.Semantic.ClosedSubjectPinV1

open ProofForgeV2.ProofInstances

/-- Fully-qualified `ByteArray` constants that product `subjectBytesV1` may
    alias. Certifier may follow exactly one hop into these names. -/
def closedSubjectBytePinNamesV1 : Array Lean.Name := #[
  ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes,
  ``ProofForgeV2.ProofInstances.ZeroCounterV1.canonicalBytes
]

/-- Runtime pin lookup by exact carrier bytes (elaborator meta path). -/
def resolveClosedSubjectBytesPinNameV1 (bytes : ByteArray) : Option Lean.Name :=
  if bytes == EvenCounterV1.canonicalBytes then
    some ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes
  else if bytes == ZeroCounterV1.canonicalBytes then
    some ``ProofForgeV2.ProofInstances.ZeroCounterV1.canonicalBytes
  else
    none

/-- Membership for certifier one-hop const follow (fail closed on unknown). -/
def isClosedSubjectBytePinNameV1 (name : Lean.Name) : Bool :=
  closedSubjectBytePinNamesV1.any (· == name)

/-- Exact bytes for a registered pin name (certifier identity; no Expr eval). -/
def closedSubjectBytePinBytesV1 (name : Lean.Name) : Option ByteArray :=
  if name == ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes then
    some EvenCounterV1.canonicalBytes
  else if name == ``ProofForgeV2.ProofInstances.ZeroCounterV1.canonicalBytes then
    some ZeroCounterV1.canonicalBytes
  else
    none

end ProofForgeV2.Semantic.ClosedSubjectPinV1
