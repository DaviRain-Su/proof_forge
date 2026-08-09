/-
  ClosedSubjectPinV1 engineering tests (bf-unpin-1 / mig-b1 / mig-b2).

  Pin table is a golden accelerator only: non-matching bytes resolve to none;
  unknown names are not pin members; packaging/preservation transport does not
  require pin membership. EvenCounter and ZeroCounter left ProofInstances
  (parity-counter / store-zero shapes under Semantic); pin golden remains for
  product nullary exact.
-/
import ProofForgeV2.Semantic.ClosedSubjectPinV1
import ProofForgeV2.Semantic.ParityCounterShapeV1
import ProofForgeV2.Semantic.ParityCounterPreservationV1
import ProofForgeV2.Semantic.ZeroCounterShapeV1
import ProofForgeV2.Semantic.ZeroCounterPreservationV1

namespace Tests.Semantic.ClosedSubjectPinV1

open ProofForgeV2.Semantic.ClosedSubjectPinV1
open ProofForgeV2.Semantic

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

/-- Pin resolves for exact parity-counter (EvenCounter) closed bytes. -/
def test_pin_parity_counter : IO Unit := do
  match resolveClosedSubjectBytesPinNameV1 ParityCounterShapeV1.canonicalBytes with
  | some n =>
      expect (n == ``ProofForgeV2.Semantic.ParityCounterShapeV1.canonicalBytes)
        "pin name must be ParityCounterShapeV1.canonicalBytes"
      match closedSubjectBytePinBytesV1 n with
      | some b =>
          expect (b == ParityCounterShapeV1.canonicalBytes)
            "pin bytes must equal closed parity-counter bytes"
      | none => throw <| IO.userError "pin bytes missing for registered name"
  | none => throw <| IO.userError "parity-counter closed bytes must pin"

/-- Pin resolves for exact ZeroCounter product-aligned closed bytes. -/
def test_pin_zero_counter : IO Unit := do
  match resolveClosedSubjectBytesPinNameV1 ZeroCounterShapeV1.canonicalBytes with
  | some n =>
      expect (n == ``ProofForgeV2.Semantic.ZeroCounterShapeV1.canonicalBytes)
        "pin name must be ZeroCounterShapeV1.canonicalBytes"
      match closedSubjectBytePinBytesV1 n with
      | some b =>
          expect (b == ZeroCounterShapeV1.canonicalBytes)
            "pin bytes must equal closed ZeroCounter bytes"
      | none => throw <| IO.userError "ZeroCounter pin bytes missing"
  | none => throw <| IO.userError "ZeroCounter closed bytes must pin"
  expect (ParityCounterShapeV1.canonicalBytes != ZeroCounterShapeV1.canonicalBytes)
    "parity-counter and ZeroCounter pins must be distinct"

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
  let p := ParityCounterShapeV1.program
  let h : p.canonicalBytes = ParityCounterShapeV1.canonicalBytes := rfl
  let _thm :=
    ParityCounterPreservationV1.preservation_theorem_of_eq_bytes p h
  let p0 := ZeroCounterShapeV1.program
  let h0 : p0.canonicalBytes = ZeroCounterShapeV1.canonicalBytes := rfl
  let _thm0 :=
    ZeroCounterPreservationV1.preservation_theorem_of_eq_bytes p0 h0
  expect true "preservation_theorem_of_eq_bytes typechecks without pin lookup"

def run : IO Unit := do
  test_pin_parity_counter
  test_pin_zero_counter
  test_non_pin_bytes_miss
  test_eq_bytes_transport_without_pin_api
  IO.println "Tests.Semantic.ClosedSubjectPinV1: ok"

end Tests.Semantic.ClosedSubjectPinV1

def main : IO Unit :=
  Tests.Semantic.ClosedSubjectPinV1.run
