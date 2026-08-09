/-
  ZeroCounter closed-instance engineering tests (second non-AMM L1 wave / mig-b2).

  Different predicate from EvenCounter (`count == 0`). Checks structure/encode/
  admission of package-owned Semantic.ZeroCounterShapeV1 data. Full
  `ZeroCounterPreservationV1.preservation_theorem` closed; product-aligned
  spine (1306B, sole state.persistent) for pin/certifier golden.
-/
import ProofForgeV2.Semantic.ZeroCounterShapeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.ZeroCounterV1

open ProofForgeV2.Semantic.ZeroCounterShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

def test_spine_and_encode : IO Unit := do
  expect (canonicalSpine.length == 1306) "canonical spine length 1306"
  expect (canonicalBytes.size == 1306) "canonical bytes size 1306"
  match encodeSemanticProgramDataV1 data with
  | .error e => throw <| IO.userError s!"encode: {repr e}"
  | .ok bytes =>
      expect (bytes == canonicalBytes) "encode must equal pinned canonicalBytes"

def test_structure_and_admission : IO Unit := do
  match validateSemanticProgramStructureV1 data with
  | .error e => throw <| IO.userError s!"structure: {repr e}"
  | .ok () => pure ()
  expect (referenceProgramDataAdmissionOkV1 data == true)
    "Reference admission bool must be true"
  match validateReferenceProgramDataAdmissionV1 data with
  | .error e => throw <| IO.userError s!"admission: {repr e}"
  | .ok () => pure ()

def test_program_validate_roundtrip : IO Unit := do
  match validateSemanticProgramV1 program with
  | .error e => throw <| IO.userError s!"validate program: {repr e}"
  | .ok d =>
      expect (d == data) "validated program data must equal closed data"

def test_not_evencounter : IO Unit := do
  -- Genericity: different QN / predicate surface from EvenCounter.
  expect (qualifiedName.components.toArray == #["Root", "ZeroCounter"])
    "QN Root.ZeroCounter"
  expect (zeroInvariant.name == "zero") "invariant name zero"
  expect (clearCallable.name == some "clear") "entry clear"
  expect (data.invariants.size == 1) "single zero invariant"

def run : IO Unit := do
  test_spine_and_encode
  test_structure_and_admission
  test_program_validate_roundtrip
  test_not_evencounter
  IO.println "Tests.Semantic.ZeroCounterV1: ok"

end Tests.Semantic.ZeroCounterV1

def main : IO Unit :=
  Tests.Semantic.ZeroCounterV1.run
