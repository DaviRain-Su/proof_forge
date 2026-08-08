/-
  Closed MiniAmm empty-pool instance engineering tests (wave-3 bf3-preserve data).

  Product-aligned Root.MiniAmmEmptyPool (2342B) with P1 emptyPool predicate.
  Structure/encode/admission certificates live in MiniAmmEmptyPoolV1.
  Full PreservationTheoremV1 / decode bridge follow (same queue).
-/
import ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.MiniAmmEmptyPoolV1

open ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

def test_spine_and_encode : IO Unit := do
  expect (canonicalSpine.length == 2342) "canonical spine length 2342"
  expect (canonicalBytes.size == 2342) "canonical bytes size 2342"
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

def test_empty_pool_shape : IO Unit := do
  expect (qualifiedName.components.toArray == #["Root", "MiniAmmEmptyPool"])
    "QN Root.MiniAmmEmptyPool"
  expect (emptyPoolInvariant.name == "emptyPool") "invariant name emptyPool"
  expect (clearCallable.name == some "clear") "entry clear"
  expect (getCallable.name == some "getTotalSupply") "view getTotalSupply"
  expect (data.logicalState.size == 3) "three state slots"
  expect (data.invariants.size == 1) "single emptyPool invariant"

def run : IO Unit := do
  test_spine_and_encode
  test_structure_and_admission
  test_program_validate_roundtrip
  test_empty_pool_shape
  IO.println "Tests.Semantic.MiniAmmEmptyPoolV1: ok"

end Tests.Semantic.MiniAmmEmptyPoolV1

def main : IO Unit :=
  Tests.Semantic.MiniAmmEmptyPoolV1.run
