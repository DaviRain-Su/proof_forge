import ProofForge.Backend.Solana.SbpfExec
import ProofForge.Backend.Solana.SbpfExecSmoke
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Examples.ControlFlowAssertProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmAssignOpProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.ValueVault

/-! Contract-agnostic sBPF step-lemma smoke (SOL-1 active surface). -/

namespace ProofForge.Tests.SolanaSbpfExec

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.SbpfAsm
open ProofForge.Backend.Solana.SbpfExec
open ProofForge.Backend.Solana.SbpfExecSmoke

/-- Supported array-state fixture used by the Solana module-plan gate. -/
def arraySubModule : Module := {
  name := "EvmStorageArrayProbe"
  state := #[ProofForge.IR.Examples.EvmStorageArrayProbe.stateBefore,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateValues,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmStorageArrayProbe.storageLifecycle,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.readValue,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.writeValue]
}

/-- Supported map-state fixture used by the Solana module-plan gate. -/
def mapSubModule : Module := {
  name := "EvmMapProbe"
  state := #[ProofForge.IR.Examples.EvmMapProbe.stateBefore,
             ProofForge.IR.Examples.EvmMapProbe.stateBalances,
             ProofForge.IR.Examples.EvmMapProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmMapProbe.setBalance,
                   ProofForge.IR.Examples.EvmMapProbe.readBalance]
}

/-- Supported struct-state fixture used by the Solana module-plan gate. -/
def structSubModule : Module := {
  name := "EvmStorageStructProbe"
  structs := #[ProofForge.IR.Examples.EvmStorageStructProbe.pointStruct]
  state := #[ProofForge.IR.Examples.EvmStorageStructProbe.stateBefore,
             ProofForge.IR.Examples.EvmStorageStructProbe.stateCurrent,
             ProofForge.IR.Examples.EvmStorageStructProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmStorageStructProbe.structLifecycle]
}

def opcodeSamples : List (String × Module) := [
  ("Counter", ProofForge.IR.Examples.Counter.module),
  ("ValueVault", ProofForge.IR.Examples.ValueVault.module),
  ("ControlFlowAssertProbe", ProofForge.IR.Examples.ControlFlowAssertProbe.module),
  ("EvmAssignOpProbe", ProofForge.IR.Examples.EvmAssignOpProbe.module),
  ("EvmStorageArrayProbe", arraySubModule),
  ("EvmMapProbe", mapSubModule),
  ("EvmStorageStructProbe", structSubModule)
]

def loweredInstructionOpcodes (nodes : Array AstNode) : Array Opcode :=
  nodes.foldl
    (fun acc node =>
      match node with
      | .instruction inst => acc.push inst.opcode
      | _ => acc)
    #[]

def uncoveredLoweredOpcodes (nodes : Array AstNode) : Array Opcode :=
  (loweredInstructionOpcodes nodes).filter
    (fun opcode => loweredOpcodeCoveredBySbpfExec opcode == false)

def loweredOpcodeCoverageOk (module : Module) : Bool :=
  match lowerModule module with
  | .error _ => false
  | .ok nodes => (uncoveredLoweredOpcodes nodes).size == 0

def allSampleLoweredOpcodesCovered : Bool :=
  opcodeSamples.all (fun sample => loweredOpcodeCoverageOk sample.snd)

theorem sample_lowered_opcodes_covered_by_sbpfExec :
    allSampleLoweredOpcodesCovered = true := by
  native_decide

def opcodeListString (opcodes : Array Opcode) : String :=
  String.intercalate ", " (opcodes.toList.map Opcode.render)

def checkLoweredOpcodeCoverage (name : String) (module : Module) : IO Bool := do
  match lowerModule module with
  | .error err =>
      IO.eprintln s!"solana-sbpf-exec: {name} failed to lower: {err.render}"
      return false
  | .ok nodes =>
      let uncovered := uncoveredLoweredOpcodes nodes
      if uncovered.size == 0 then
        return true
      else
        IO.eprintln s!"solana-sbpf-exec: {name} uncovered opcode(s): {opcodeListString uncovered}"
        return false

example : True := by
  have _ := @step_mov64_imm_ok
  have _ := @step_mov32_imm_ok
  have _ := @step_add64_reg_ok
  have _ := @step_add64_imm_ok
  have _ := @step_sub64_reg_ok
  have _ := @step_sub64_imm_ok
  have _ := @step_mul64_reg_ok
  have _ := @step_div64_reg_ok
  have _ := @step_mod64_reg_ok
  have _ := @step_lsh64_reg_ok
  have _ := @step_rsh64_reg_ok
  have _ := @step_lddw_ok
  have _ := @step_ldxdw_ok
  have _ := @step_ldxb_ok
  have _ := @step_ldxw_ok
  have _ := @step_stdw_ok
  have _ := @step_stxdw_ok
  have _ := @step_xor64_reg_ok
  have _ := @step_xor64_imm_ok
  have _ := @step_jge_reg_taken_ok
  have _ := @step_jlt_imm_taken_ok
  have _ := @step_jgt_reg_taken_ok
  have _ := @step_jle_reg_taken_ok
  have _ := @step_exit_ok
  have _ := @step_syscall_set_return_data_ok
  have _ := @runSteps_of_stepPath_done
  have _ := @ProofForge.Backend.Solana.SbpfExec.ReadyOpcodeAt
  have _ := @ProofForge.Backend.Solana.SbpfExec.StepReductionChain
  have _ := @ProofForge.Backend.Solana.SbpfExec.ReductionChainProvider
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regs_size_nextPc_setReg
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_nextPc_setReg_same_of_lt
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_nextPc_setReg_of_ne
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regs_size_execLddw
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execLddw_same_of_lt
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execLddw_of_ne
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regs_size_execGetClockSysvar
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regs_size_execLog64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execGetClockSysvar_r0_of_lt
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execGetClockSysvar_of_ne
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execLog64_r0_of_lt
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.regGet_execLog64_of_ne
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execLoad
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_execLddw
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execLddw
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execMov64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execGetClockSysvar
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execGetClockSysvar_of_ne
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_execLog64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execLog64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_nextPc_setReg
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_execSetReturnData
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execSetReturnData
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.memory_read_execExit
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execExit
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execLddw
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execMov64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execGetClockSysvar
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execLog64
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.returnData_execSetReturnData
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.pc_nextPc
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.pc_execLoad
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.pc_execJump
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.pc_execExit
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.halted_execLoad
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.halted_execJump
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.halted_execExit
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.entryR0_execLoad
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.entryR0_execJump
  have _ := @ProofForge.Backend.Solana.SbpfInterpreter.entryR0_execExit
  have _ := @runSteps_of_reductionChain
  have _ := @reduction_mov64_imm_at_ok
  have _ := @reduction_lddw_at_ok
  have _ := @reduction_syscall_get_clock_sysvar_at_ok
  have _ := @reduction_syscall_log64_at_ok
  have _ := @reduction_and64_reg_at_ok
  have _ := @reduction_or64_reg_at_ok
  have _ := @reduction_add64_imm_at_ok
  have _ := @reduction_sub64_imm_at_ok
  have _ := @reduction_mul64_reg_at_ok
  have _ := @reduction_div64_reg_at_ok
  have _ := @reduction_mod64_reg_at_ok
  have _ := @reduction_lsh64_reg_at_ok
  have _ := @reduction_rsh64_reg_at_ok
  have _ := @reduction_xor64_reg_at_ok
  have _ := @reduction_xor64_imm_at_ok
  have _ := @reduction_ldxb_at_ok
  have _ := @reduction_ldxh_at_ok
  have _ := @reduction_ldxw_at_ok
  have _ := @reduction_stb_at_ok
  have _ := @reduction_sth_at_ok
  have _ := @reduction_stw_at_ok
  have _ := @reduction_stdw_at_ok
  have _ := @reduction_stxb_at_ok
  have _ := @reduction_stxh_at_ok
  have _ := @reduction_stxw_at_ok
  have _ := @reduction_jeq_imm_taken_at_ok
  have _ := @reduction_jeq_reg_taken_at_ok
  have _ := @reduction_jne_imm_taken_at_ok
  have _ := @reduction_jne_reg_taken_at_ok
  have _ := @reduction_jge_reg_taken_at_ok
  have _ := @reduction_jlt_imm_taken_at_ok
  have _ := @reduction_jgt_reg_taken_at_ok
  have _ := @reduction_jle_reg_taken_at_ok
  have _ := @reduction_jset_imm_taken_at_ok
  have _ := @reduction_jset_reg_fallthrough_at_ok
  have _ := @loweredOpcodeSet_covered_by_sbpfExec
  have _ := @smoke_runSteps
  have _ := @smoke_runSteps_via_provider
  have _ := @jump_taken_reductionChain
  have _ := @jeq_taken_reductionChain
  have _ := @smoke_jump_jne_taken_runSteps
  have _ := @smoke_jump_jeq_taken_runSteps
  have _ := @smoke_jump_jne_taken_runSteps_via_provider
  have _ := @smoke_jump_jeq_taken_runSteps_via_provider
  have _ := @sample_lowered_opcodes_covered_by_sbpfExec
  exact True.intro

end ProofForge.Tests.SolanaSbpfExec

def main : IO UInt32 := do
  let mut ok := true
  for sample in ProofForge.Tests.SolanaSbpfExec.opcodeSamples do
    let sampleOk ←
      ProofForge.Tests.SolanaSbpfExec.checkLoweredOpcodeCoverage sample.fst sample.snd
    ok := ok && sampleOk
  if ok then
    IO.println "solana-sbpf-exec: generic step lemmas and lowered opcode coverage checked"
    return 0
  else
    return 1
