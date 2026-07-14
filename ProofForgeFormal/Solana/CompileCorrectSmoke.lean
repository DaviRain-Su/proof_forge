/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Smoke entry for the opt-in solanalib CompileCorrect surface.
-/

import ProofForgeFormal.Solana.CompileCorrect
import ProofForgeFormal.Solana.CounterHostRefinement
import ProofForgeFormal.Solana.CoreTailHostComposition
import ProofForgeFormal.Solana.ValueVaultHostRefinement
import ProofForgeFormal.Solana.FullHostTargetSemantics

namespace ProofForge.Backend.Solana.CompileCorrectSmoke

open ProofForge.Backend.Solana.CompileCorrect
open ProofForge.Backend.Solana.CounterHostRefinement
open ProofForge.Backend.Solana.CoreTailHostComposition
open ProofForge.Backend.Solana.ValueVaultHostRefinement
open ProofForge.Backend.Solana.FullHostTargetSemantics
open ProofForge.Backend.Solana.SolanalibAdapter

#check counter_bpf_encode_ok
#check counter_solanalib_pipeline_ok
#check counter_compile_pipeline_ok
#check verified_instr_step_ne_err
#check counter_labeled_view_ok
#check counter_direct_lift_verify_ok
#check counter_direct_lift_eq_decode
#check counter_core_tail_host_bridge_ok
#check counter_full_program_host_bridge_ok
#check counter_full_program_diff_bridge_ok
#check value_vault_full_program_host_bridge_ok
#check value_vault_full_program_diff_bridge_ok
#check counter_host_ir_trace_simulation_ok
#check counter_host_counter_call_trace_bridge_ok
#check counter_host_trace_simulation_sound_checked
#check counter_host_counter_call_trace_sound_checked
#check counter_core_tail_host_composition_ok
#check host_core_tail_matches_abstract_grid
#check value_vault_host_trace_simulation_ok
#check value_vault_host_trace_simulation_sound_checked
#check full_host_target_semantics_counter_ok
#check full_host_target_semantics_executable_counter_ok

end ProofForge.Backend.Solana.CompileCorrectSmoke

def main : IO UInt32 := do
  IO.println "solana-solanalib-compile-correct-smoke: full Solana host stack (Counter+ValueVault+composition+TargetSemantics) checked"
  pure 0
