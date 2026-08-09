/-
  Tests.Semantic.PreservationShapeV1 — generic shape-family packaging.

  Typechecks reusable callable constructors and production Reference-step
  wrappers without importing any contract-specific golden or proof instance.
-/
import ProofForgeV2.Semantic.PreservationShapeV1

namespace Tests.Semantic.PreservationShapeV1

open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

/-- Increment-by-two constructor is definitionally closed. -/
theorem increment_add_two_shape_rfl :
    incrementAddTwoCallableV1 0 (some "increment") 0 0 =
      incrementAddTwoCallableV1 0 (some "increment") 0 0 :=
  rfl

/-- Single-state view constructor is definitionally closed. -/
theorem view_load_shape_rfl :
    viewLoadCallableV1 1 (some "get") 0 0 =
      viewLoadCallableV1 1 (some "get") 0 0 :=
  rfl

/-- UInt64 parity invariant constructor is definitionally closed. -/
theorem uint64_parity_shape_rfl :
    uint64ParityInvariantCallableV1 2 (some "even") 0 1 0 .public_ (some 7) =
      uint64ParityInvariantCallableV1 2 (some "even") 0 1 0 .public_ (some 7) :=
  rfl

/-- Triple store-constant constructor is definitionally closed. -/
theorem triple_clear_shape_rfl :
    storeConstantClearTripleCallableV1 0 (some "clearAll") 0 zero8BytesV1 =
      storeConstantClearTripleCallableV1 0 (some "clearAll") 0 zero8BytesV1 :=
  rfl

/-- Triple view-load constructor is definitionally closed. -/
theorem triple_get_shape_rfl :
    viewLoadTripleSlot2CallableV1 1 (some "getReserve") 0 2 =
      viewLoadTripleSlot2CallableV1 1 (some "getReserve") 0 2 :=
  rfl

/-- Packaging theorem signatures elaborate without a contract-local theorem. -/
def test_packaging_types_elaborate : IO Unit := do
  let _ := increment_add_two_shape_rfl
  let _ := view_load_shape_rfl
  let _ := uint64_parity_shape_rfl
  let _ := triple_clear_shape_rfl
  let _ := triple_get_shape_rfl
  let _thmClear :=
    @stepReturned_of_readyStoreConstantClearZeroV1
  let _thmGet :=
    @stepReturned_of_readyViewLoadV1
  let _thmInc :=
    @stepReturned_of_readyIncrementAddTwoV1
  let _thmIncTrap :=
    @stepTrapped_of_readyIncrementAddTwo_nonemptyResponsesV1
  let _thmIncOvf :=
    @stepNotReturned_of_readyIncrementAddTwo_overflowV1
  let _thmTriple :=
    @stepReturned_of_readyStoreConstantClearTripleZeroV1
  let _thmTripleGet :=
    @stepReturned_of_readyViewLoadTripleSlot2V1
  let _thmPresClear :=
    @preservationReturned_of_readyStoreConstantClearZeroV1
  let _thmPresGet :=
    @preservationReturned_of_readyViewLoad_postEqPreV1
  let _thmPresInc :=
    @preservationReturned_of_readyIncrementAddTwoV1
  let _thmPresTriple :=
    @preservationReturned_of_readyStoreConstantClearTripleZeroV1
  let _thmPresTripleGet :=
    @preservationReturned_of_readyViewLoadTripleSlot2_postEqPreV1
  expect true "PreservationShapeV1 packaging theorems elaborate"

def run : IO Unit := do
  test_packaging_types_elaborate
  IO.println "Tests.Semantic.PreservationShapeV1: ok"

end Tests.Semantic.PreservationShapeV1
