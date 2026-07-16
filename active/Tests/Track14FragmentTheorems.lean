import ProofForge.Backend.Evm.Refinement
import ProofForge.Backend.Solana.Refinement
import ProofForge.Backend.WasmHost.Refinement
import ProofForge.Backend.Refinement.CounterUniversal

/-! ## Track 1.4 fragment theorem smoke

Exercises the two-predicate fragment machinery (proven `fragmentAccepts` /
lowerable `lowerableAccepts`) and the three Track 1.4 theorems across the
EVM, Solana sBPF, and Wasm/NEAR backends on the canonical Counter module,
plus the PF-P3-01 structural split:

1. `*_lowering_total` — `lowerModule Counter.module = .ok _` (lowerable ⇒
   lowering-total bridge, `native_decide`).
2. `*_proven_subset_lowerable` — structural `∀ m, proved m → lowerable m`.
3. `*_capability_accept_implies_lowerable_counter` — capability resolution
   ⇒ lowerable.
4. Renamed Counter witnesses: `lowerable ∧ ¬proved` and lowering-total.

This is the machine-checked replacement for the ad-hoc
`check-ir-coverage-manifest.py` scripts for the Counter proven fragment.
-/

namespace ProofForge.Tests.Track14FragmentTheorems

open ProofForge.Backend.Evm.Refinement
open ProofForge.Backend.Solana.Refinement
open ProofForge.Backend.WasmHost.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.Refinement

#check evm_counter_lowering_total
#check solana_counter_lowering_total
#check wasm_near_counter_lowering_total

#check evm_proven_subset_lowerable
#check solana_proven_subset_lowerable
#check wasm_near_proven_subset_lowerable

#check evm_proven_subset_lowerable_counter
#check solana_proven_subset_lowerable_counter
#check wasm_near_proven_subset_lowerable_counter

#check evm_lowerable_implies_lowering_total_counter
#check solana_lowerable_implies_lowering_total_counter
#check wasm_near_lowerable_implies_lowering_total_counter

#check evm_fragment_subset_lowerable_counter
#check solana_fragment_subset_lowerable_counter
#check wasm_near_fragment_subset_lowerable_counter

#check evm_capability_accept_implies_lowerable_counter
#check solana_capability_accept_implies_lowerable_counter
#check wasm_near_capability_accept_implies_lowerable_counter

-- PF-P3-01: structural proved ⇒ lowerable is not limited to Counter.module.
#check isCounterModule_implies_shape_lowerable
#check isCounterShapeLowerable_implies_isCounterModule_with_canonical_name
#check isCounterShapeLowerable_independent_of_name
#check withCanonicalCounterName

-- PF-P3-01: checked lowerable ∧ ¬proved witnesses (renamed Counter shape).
#check evm_renamed_counter_lowerable_not_proved
#check solana_renamed_counter_lowerable_not_proved
#check wasm_near_renamed_counter_lowerable_not_proved
#check evm_renamed_counter_lowering_total
#check solana_renamed_counter_lowering_total
#check wasm_near_renamed_counter_lowering_total
#check evm_lowerable_implies_lowering_total_witnesses
#check evm_renamed_witness_canonicalizes_to_proved
#check evm_renamed_witness_canonical_lowering_total
#check solana_renamed_witness_canonicalizes_to_proved
#check solana_renamed_witness_canonical_lowering_total
#check wasm_near_renamed_witness_canonicalizes_to_proved
#check wasm_near_renamed_witness_canonical_lowering_total

-- PF-P3-01: finite name-family lowering-total (beyond single Counter constant).
#check evm_counter_shape_name_family_lowerable_total
#check evmCounterShapeNameFamily
#check evm_shape_name_VaultCounter_lowerable_total

def nearAllocatorMismatchWitness : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with
    allocator := ProofForge.IR.AllocatorConfig.cosmWasmRegion }

theorem near_allocator_mismatch_is_not_lowerable :
    wasmNearTargetSemantics.lowerableAccepts nearAllocatorMismatchWitness = false := by
  native_decide

theorem near_allocator_mismatch_is_rejected_by_lowerer :
    (ProofForge.Backend.WasmHost.EmitWat.lowerModule nearAllocatorMismatchWitness).isOk = false := by
  native_decide

-- PF-P3-01 progressive structural skeleton (constrained IR unique under lowerable).
#check isCounterShapeLowerable_skeleton
#check isCounterShapeLowerable_flags
#check isCounterStateDecl_eq
#check isCounterInitializeEntrypoint_fields
#check isCounterInitializeEntrypoint_body_array
#check isCounterShapeLowerable_state_array
#check isCounterShapeLowerable_entrypoints_array
#check isCounterInitializeEntrypoint_eq
#check counterShapeModule
#check isCounterShapeLowerable_matches_counterShapeModule
#check isCounterShapeLowerable_eq_counterShapeModule
#check evm_lowerable_implies_counter_skeleton
#check evm_lowerable_state_eq_counter
#check evm_counter_module_eq_counterShapeModule
#check evm_counterShapeModule_Counter_lowering_total
#check evm_lowerable_eq_counterShapeModule
#check evm_withCanonical_of_lowerable_eq_counter
#check evm_lowerable_implies_canonical_lowering_total
#check evm_lowerable_implies_lowering_total_of_name_indep
#check counterShapeModule_eq_evmCounterShapeWithName
#check evm_lowerable_implies_lowering_total_of_family_name
#check evm_lowerModuleCore_counterShape_Counter_isOk
#check evm_shape_lowerable_implies_lowering_total
#check evm_lowerable_implies_lowering_total

end ProofForge.Tests.Track14FragmentTheorems

def main : IO UInt32 := do
  IO.println "track14-fragment-theorems-smoke: triad proven⊂lowerable + allocator guard + finite name-family + structural skeleton"
  return 0
