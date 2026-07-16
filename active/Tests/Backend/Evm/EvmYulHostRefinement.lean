import ProofForge.Backend.Evm.YulHostRefinement

/-! ## EVM Yul-host IR paired simulation smoke (mathlib-free) -/

namespace ProofForge.Tests.EvmYulHostRefinement

open ProofForge.Backend.Evm.YulHostRefinement

def storagePlanMatches
    (module : ProofForge.IR.Module)
    (stateId : String)
    (slot byteOffset byteWidth : Nat) : Bool :=
  match (ProofForge.Backend.Evm.Plan.storageLayout module).find? stateId with
  | some state =>
      state.slot == slot &&
      state.byteOffset == byteOffset &&
      state.byteWidth == byteWidth
  | none => false

example : storagePlanMatches ProofForge.IR.Examples.Counter.module "count" 0 0 8 = true := by
  native_decide

example :
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "balance" 0 0 8 &&
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "released" 0 8 8 &&
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "fees" 0 16 8 &&
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "last_value" 0 24 8 &&
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "last_checkpoint" 1 0 8 &&
    storagePlanMatches ProofForge.Backend.Evm.Refinement.valueVaultEvmModule "operations" 1 8 8 = true := by
  native_decide

def adjacentPackedU64Word : Nat := 7 + 11 * 2 ^ 64

example : packedU64FromWord adjacentPackedU64Word 0 8 = 7 := by
  native_decide

example : packedU64FromWord adjacentPackedU64Word 8 8 = 11 := by
  native_decide

#check counter_yul_trace_simulation_ok
#check counter_yul_trace_simulation_sound_checked
#check counter_yul_counter_call_trace_ok
#check counter_yul_counter_call_trace_sound_checked
#check value_vault_yul_trace_simulation_ok
#check value_vault_yul_trace_simulation_sound_checked
#check value_vault_yul_executable_still_ok
#check counter_yul_executable_still_ok

end ProofForge.Tests.EvmYulHostRefinement

def main : IO UInt32 := do
  IO.println "evm-yul-host-refinement-smoke: Counter IR↔Yul paired simulation + ValueVault lockstep + executable traces checked"
  return 0
