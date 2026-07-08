import ProofForge.Backend.Solana.SbpfExec
import ProofForge.Backend.Solana.SbpfExecSmoke

/-! Contract-agnostic sBPF step-lemma smoke (SOL-1 active surface). -/

namespace ProofForge.Tests.SolanaSbpfExec

open ProofForge.Backend.Solana.SbpfExec
open ProofForge.Backend.Solana.SbpfExecSmoke

#check step_mov64_imm_ok
#check step_add64_reg_ok
#check step_ldxdw_ok
#check step_stxdw_ok
#check step_exit_ok
#check step_syscall_set_return_data_ok
#check runSteps_of_stepPath_done
#check ReadyOpcodeAt
#check StepReductionChain
#check ReductionChainProvider
#check runSteps_of_reductionChain
#check reduction_mov64_imm_at_ok
#check reduction_and64_reg_at_ok
#check reduction_or64_reg_at_ok
#check reduction_jeq_imm_taken_at_ok
#check reduction_jeq_reg_taken_at_ok
#check reduction_jne_imm_taken_at_ok
#check reduction_jne_reg_taken_at_ok

#check smoke_runSteps
#check smoke_runSteps_via_provider
#check jump_taken_reductionChain
#check jeq_taken_reductionChain
#check smoke_jump_jne_taken_runSteps
#check smoke_jump_jeq_taken_runSteps
#check smoke_jump_jne_taken_runSteps_via_provider
#check smoke_jump_jeq_taken_runSteps_via_provider

end ProofForge.Tests.SolanaSbpfExec

def main : IO UInt32 := do
  IO.println "solana-sbpf-exec: generic step lemmas checked"
  return 0