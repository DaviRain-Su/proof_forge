import ProofForge.Backend.Refinement.Core
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.CounterLowerableAllocator

open ProofForge.Backend.Refinement

def nearAllocatorMismatchWitness : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with
    allocator := ProofForge.IR.AllocatorConfig.cosmWasmRegion }

theorem near_allocator_mismatch_is_not_shape_lowerable :
    isCounterShapeLowerableForWasmBridge .near nearAllocatorMismatchWitness = false := by
  native_decide

end ProofForge.Tests.CounterLowerableAllocator

def main : IO UInt32 := do
  IO.println "counter-lowerable-allocator: ok"
  pure 0
