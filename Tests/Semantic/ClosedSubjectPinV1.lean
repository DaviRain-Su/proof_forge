/-
  ClosedSubjectPinV1 engineering tests (bf-unpin-1).

  Pin table is a golden accelerator only: non-matching bytes resolve to none;
  unknown names are not pin members; packaging/preservation transport does not
  require pin membership.
-/
import ProofForgeV2.Semantic.ClosedSubjectPinV1
import ProofForgeV2.ProofInstances.EvenCounterV1
import ProofForgeV2.ProofInstances.EvenCounterPreservationV1
import ProofForgeV2.ProofInstances.ZeroCounterV1
import ProofForgeV2.ProofInstances.ZeroCounterPreservationV1

namespace Tests.Semantic.ClosedSubjectPinV1

open ProofForgeV2.Semantic.ClosedSubjectPinV1
open ProofForgeV2.ProofInstances

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

/-- Pin resolves for exact EvenCounter closed bytes. -/
def test_pin_exact_match : IO Unit := do
  match resolveClosedSubjectBytesPinNameV1 EvenCounterV1.canonicalBytes with
  | some n =>
      expect (n == ``ProofForgeV2.ProofInstances.EvenCounterV1.canonicalBytes)
        "pin name must be EvenCounterV1.canonicalBytes"
      match closedSubjectBytePinBytesV1 n with
      | some b =>
          expect (b == EvenCounterV1.canonicalBytes)
            "pin bytes must equal closed EvenCounter bytes"
      | none => throw <| IO.userError "pin bytes missing for registered name"
  | none => throw <| IO.userError "EvenCounter closed bytes must pin"

/-- Pin resolves for exact ZeroCounter product-aligned closed bytes. -/
def test_pin_zero_counter : IO Unit := do
  match resolveClosedSubjectBytesPinNameV1 ZeroCounterV1.canonicalBytes with
  | some n =>
      expect (n == ``ProofForgeV2.ProofInstances.ZeroCounterV1.canonicalBytes)
        "pin name must be ZeroCounterV1.canonicalBytes"
      match closedSubjectBytePinBytesV1 n with
      | some b =>
          expect (b == ZeroCounterV1.canonicalBytes)
            "pin bytes must equal closed ZeroCounter bytes"
      | none => throw <| IO.userError "ZeroCounter pin bytes missing"
  | none => throw <| IO.userError "ZeroCounter closed bytes must pin"
  expect (EvenCounterV1.canonicalBytes != ZeroCounterV1.canonicalBytes)
    "EvenCounter and ZeroCounter pins must be distinct"

/-- Arbitrary / empty bytes are unpinned (non-pin author path). -/
def test_non_pin_bytes_miss : IO Unit := do
  let empty : ByteArray := ByteArray.empty
  expect ((resolveClosedSubjectBytesPinNameV1 empty).isNone)
    "empty bytes must not pin"
  let junk := ByteArray.mk #[0, 1, 2, 3]
  expect ((resolveClosedSubjectBytesPinNameV1 junk).isNone)
    "junk bytes must not pin"
  expect (!isClosedSubjectBytePinNameV1 ``Nat.add)
    "foreign name must not be a pin member"
  expect ((closedSubjectBytePinBytesV1 ``Nat.add).isNone)
    "foreign name must have no pin bytes"

/-- Byte-equality transport does not consult the pin table. -/
def test_eq_bytes_transport_without_pin_api : IO Unit := do
  -- Construction only: of_eq_bytes is pure Lean; pin APIs are unused.
  let p := EvenCounterV1.program
  let h : p.canonicalBytes = EvenCounterV1.canonicalBytes := rfl
  let _thm :=
    EvenCounterPreservationV1.preservation_theorem_of_eq_bytes p h
  let p0 := ZeroCounterV1.program
  let h0 : p0.canonicalBytes = ZeroCounterV1.canonicalBytes := rfl
  let _thm0 :=
    ZeroCounterPreservationV1.preservation_theorem_of_eq_bytes p0 h0
  expect true "preservation_theorem_of_eq_bytes typechecks without pin lookup"

def run : IO Unit := do
  test_pin_exact_match
  test_pin_zero_counter
  test_non_pin_bytes_miss
  test_eq_bytes_transport_without_pin_api
  IO.println "Tests.Semantic.ClosedSubjectPinV1: ok"

end Tests.Semantic.ClosedSubjectPinV1

def main : IO Unit :=
  Tests.Semantic.ClosedSubjectPinV1.run
