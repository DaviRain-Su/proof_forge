import EvmRefinement.CounterRefinement

/-! ## EVM powdr Counter bytecode refinement smoke (opt-in, mathlib)

Pins the opt-in powdr EVM bytecode lane for Counter:
- compiled Counter bytecode runs through powdr `stepF`/`runBytecode` and
  produces the expected observables;
- the same `TraceObligation` passes both the IR reference trace and the
  powdr bytecode trace (delivery-boundary pin);
- the universal fragment refinement theorem covers all Counter-shaped modules.

This test imports `EvmRefinement` and therefore pulls powdr + mathlib; it is
intentionally not on the default `lake build` path.
-/

namespace ProofForge.Tests.EvmPowdrCounterRefinement

open ProofForge.Backend.Evm.CounterRefinement

theorem counter_packed_count_uses_low_64_bits :
    counterPackedCountValue 7 = EvmSemantics.UInt256.ofNat 7 := by
  native_decide

theorem counter_padded_count_preserves_high_192_bits :
    counterPaddedCountValue 7 123 =
      EvmSemantics.UInt256.ofNat (7 + 123 * 2 ^ 64) := by
  native_decide

theorem counter_initialize_clears_low_64_bits_and_preserves_high_192_bits :
    counterInitializeStorageWord
        (EvmSemantics.UInt256.ofNat (7 + 123 * 2 ^ 64)) =
      EvmSemantics.UInt256.ofNat (123 * 2 ^ 64) := by
  native_decide

theorem counterCompiledPowdr_irStateRel_is_CounterStorageRel
    (irState : IRState) (evmState : EvmState) :
    counterCompiledPowdrTargetSemantics.irStateRel irState evmState ↔
      CounterStorageRel irState evmState := by
  rfl

theorem counterCompiledPowdr_initialMachineState_none
    (module : ProofForge.IR.Module) :
    counterCompiledPowdrTargetSemantics.initialMachineState module = none := by
  rfl

theorem counter_compiled_runtime_hex_is_valid :
    EvmRefinement.HexWitness.decodeHex? counterCompiledRuntimeHex =
      some counterCompiledRuntimeCode :=
  counterCompiledRuntimeHex_decodes

theorem counter_compiled_runtime_tracks_narrow_arithmetic :
    counterCompiledRuntimeCode.size = 262 ∧
      LegacyHighPacked.byteArrayHasSliceAt counterCompiledRuntimeCode
        (ByteArray.mk #[
          0x5b, 0x90, 0x81, 0x11, 0x60, 0xe5, 0x57, 0x90, 0x56, 0x5b, 0x5f,
          0x80, 0xfd]) 220 = true := by
  exact ⟨counterCompiledRuntimeCode_size,
    counterCompiledRuntimeCode_checks_u64_narrowing⟩

#check counterCompiledPowdr_executable_trace_ok
#check counterCompiledPowdr_ir_and_target_trace_match
#check counterCompiledPowdr_initialize_executable_smoke
#check counterCompiledPowdr_get_zero_executable_smoke
#check counterCompiledPowdr_increment_preserves_high_padding
#check counterCompiledPowdr_initialize_preserves_high_padding
#check counterCompiledPowdr_initialize_increment_get_executable_smoke
#check evmCompiledPowdr_fragment_refines_all

end ProofForge.Tests.EvmPowdrCounterRefinement

def main : IO UInt32 := do
  IO.println "evm-powdr-counter-refinement-smoke: Counter IR↔powdr bytecode delivery boundary pinned"
  return 0
