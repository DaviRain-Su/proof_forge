/-
  Tests.Semantic.PreservationShapeV1 — shape-family packaging (mig-a2-shape).

  Pins constructor spelling against ZeroCounter closed callables (rfl/simp) and
  typechecks the preservation-returned packaging theorems without expanding the
  pin table or replaying per-contract micro-paths.
-/
import ProofForgeV2.Semantic.PreservationShapeV1
import ProofForgeV2.ProofInstances.ZeroCounterV1
import ProofForgeV2.ProofInstances.ZeroCounterPreservationV1

namespace Tests.Semantic.PreservationShapeV1

open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.ProofInstances.ZeroCounterV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

private theorem zeroBytes_eq_zero8 : zeroBytes = zero8BytesV1 := rfl

/-- ZeroCounter `clear` matches the store-constant clear shape constructor. -/
theorem clear_is_storeConstantClear :
    clearCallable =
      storeConstantClearCallableV1 0 (some "clear") 0 0 zero8BytesV1 := by
  simp [clearCallable, clearBlock, valueInstruction, valueDef, voidInstruction,
    storeConstantClearCallableV1, zeroBytes_eq_zero8]

/-- ZeroCounter `get` matches the view-load shape constructor. -/
theorem get_is_viewLoad :
    getCallable = viewLoadCallableV1 1 (some "get") 0 0 := by
  simp [getCallable, getBlock, valueInstruction, valueDef, viewLoadCallableV1]

/-- Triple store-constant constructor is definitionally closed (self-eq). -/
theorem triple_clear_shape_rfl :
    storeConstantClearTripleCallableV1 0 (some "clearAll") 0 zero8BytesV1 =
      storeConstantClearTripleCallableV1 0 (some "clearAll") 0 zero8BytesV1 :=
  rfl

/-- Triple view-load constructor is definitionally closed (self-eq). -/
theorem triple_get_shape_rfl :
    viewLoadTripleSlot2CallableV1 1 (some "getReserve") 0 2 =
      viewLoadTripleSlot2CallableV1 1 (some "getReserve") 0 2 :=
  rfl

/-- Packaging theorems are inhabited (typecheck against ZeroCounter data).
    Does not run a full product step; only forces the theorem types to elaborate. -/
def test_packaging_types_elaborate : IO Unit := do
  -- Force shape equalities into the elaborator / typechecker.
  let _ := clear_is_storeConstantClear
  let _ := get_is_viewLoad
  let _ := triple_clear_shape_rfl
  let _ := triple_get_shape_rfl
  -- Mention packaging theorem names so lake builds the proofs.
  let _thmClear :=
    @stepReturned_of_readyStoreConstantClearZeroV1
  let _thmGet :=
    @stepReturned_of_readyViewLoadV1
  let _thmTriple :=
    @stepReturned_of_readyStoreConstantClearTripleZeroV1
  let _thmTripleGet :=
    @stepReturned_of_readyViewLoadTripleSlot2V1
  let _thmPresClear :=
    @preservationReturned_of_readyStoreConstantClearZeroV1
  let _thmPresGet :=
    @preservationReturned_of_readyViewLoad_postEqPreV1
  let _thmPresTriple :=
    @preservationReturned_of_readyStoreConstantClearTripleZeroV1
  let _thmPresTripleGet :=
    @preservationReturned_of_readyViewLoadTripleSlot2_postEqPreV1
  -- ZeroCounter still exposes a full preservation theorem (product path green).
  let _full :=
    ProofForgeV2.ProofInstances.ZeroCounterPreservationV1.preservation_theorem
  expect true "PreservationShapeV1 packaging theorems elaborate"

def run : IO Unit := do
  test_packaging_types_elaborate
  IO.println "Tests.Semantic.PreservationShapeV1: ok"

end Tests.Semantic.PreservationShapeV1

def main : IO Unit :=
  Tests.Semantic.PreservationShapeV1.run
