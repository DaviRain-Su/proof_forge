import ProofForge.Backend.Solana.Refinement

/-! ## Solana sBPF refinement smoke

The first Solana refinement anchor (Counter IR trace + sBPF artifact surface).
Mirrors the shape of `Tests/NearWasmFormal.lean` for the NEAR path: it
`#check`s the `native_decide`-discharged theorems and runs an entry-point that
prints which anchors were verified.
-/

namespace ProofForge.Tests.SolanaRefinement

open ProofForge.Backend.Solana.Refinement
open ProofForge.Backend.Solana.SbpfInterpreter

-- Counter IR observable trace (same scenario as EVM/NEAR refinement layers).
#check counter_ir_observable_trace_ok

-- Counter sBPF artifact-surface obligation (rendered assembly surfaces every
-- entrypoint name).
#check counter_sbpf_artifact_surface_ok

-- Counter sBPF executable-trace obligation: the in-Lean interpreter runs the
-- lowered AST to the same observable trace as the IR reference semantics.
#check counter_interpreter_smoke_ok
#check counter_sbpf_executable_trace_ok
#check counter_sbpf_initialize_step_simulation_ok
#check counter_sbpf_get_after_initialize_step_simulation_ok
#check counter_sbpf_increment_after_initialize_step_simulation_ok
#check counter_sbpf_get_after_increment_step_simulation_ok
#check counter_sbpf_initialize_step_simulation_sound_checked
#check counter_sbpf_get_after_initialize_step_simulation_sound_checked
#check counter_sbpf_increment_after_initialize_step_simulation_sound_checked
#check counter_sbpf_get_after_increment_step_simulation_sound_checked
#check counter_sbpf_trace_simulation_ok
#check counter_sbpf_trace_simulation_sound_checked
#check value_vault_ir_observable_trace_ok
#check value_vault_sbpf_executable_trace_ok
#check array_storage_ir_observable_trace_ok
#check array_storage_sbpf_executable_trace_ok
#check map_storage_ir_observable_trace_ok
#check map_storage_sbpf_executable_trace_ok

-- Counter scalar simulation relation at the account-data offset computed by
-- the Solana state layout.
#check counter_R_after_initialize_ok
#check counter_R_after_increment_ok

-- Revert-aware trace obligation: a contract revert is observed as
-- `ObservableReturn.reverted`, and state is not advanced (rollback semantics).
#check revert_rollback_ir_trace_ok

end ProofForge.Tests.SolanaRefinement

def main : IO UInt32 := do
  IO.println "solana-refinement-smoke: Counter + ValueVault + array/map IR/sBPF executable traces, Counter entrypoint/trace paired simulation, scalar R, and revert rollback checked"
  return 0
