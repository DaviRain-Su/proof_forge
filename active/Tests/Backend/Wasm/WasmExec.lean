import ProofForge.Backend.WasmHost.WasmExec

/-! ## Generic WasmExec smoke

Pins the chain-agnostic Wasm stack/state helper surface used by the WASM-1
proof track. This intentionally avoids NEAR host calls and contract fixtures.
-/

namespace ProofForge.Tests.WasmExec

open ProofForge.Backend.WasmHost.WasmExec

example : True := by
  have _ := @runStateSteps
  have _ := @StateStepReduction
  have _ := @StateStepReduction.of_step
  have _ := @StateStepReductionChain
  have _ := @runStateSteps_of_reductionChain
  have _ := @StateStepReductionChain.append
  have _ := @ExecutionSegment
  have _ := @runStateSteps_of_executionSegment
  have _ := @executionSegment_of_reductionChain
  have _ := @executionSegment_append
  have _ := @StateStepProvider
  have _ := @stateStepProvider_single
  have _ := @stateStepProvider_append
  have _ := @runStateSteps_post_of_provider
  have _ := @pushStep
  have _ := @dropStep
  have _ := @constStep
  have _ := @plainStep
  have _ := @localGetStep
  have _ := @localSetStep
  have _ := @localTeeStep
  have _ := @globalGetStep
  have _ := @globalSetStep
  have _ := @loadStep
  have _ := @storeStep
  have _ := @hostCallStep
  have _ := @pushStep_ok
  have _ := @valueStack_stackPush
  have _ := @locals_stackPush
  have _ := @globals_stackPush
  have _ := @memory_stackPush
  have _ := @host_stackPush
  have _ := @stackPeek_stackPush
  have _ := @stackPop_stackPush
  have _ := @splitStackArgs_zero
  have _ := @splitStackArgs_stackPush1
  have _ := @splitStackArgs_stackPush2
  have _ := @splitStackArgs_stackPush3
  have _ := @splitStackArgs_stackPush5
  have _ := @evalPlain_unary_stackPush
  have _ := @plainStep_unary_stackPush
  have _ := @evalPlain_binary_stackPush
  have _ := @plainStep_binary_stackPush
  have _ := @execDrop_stackPush
  have _ := @dropStep_stackPush
  have _ := @execConst_ok
  have _ := @constStep_ok
  have _ := @execLocalGet_ok
  have _ := @localGetStep_ok
  have _ := @execLocalSet_stackPush
  have _ := @localSetStep_stackPush
  have _ := @execLocalTee_stackPush
  have _ := @localTeeStep_stackPush
  have _ := @execGlobalGet_ok
  have _ := @globalGetStep_ok
  have _ := @execGlobalSet_stackPush
  have _ := @globalSetStep_stackPush
  have _ := @execLoad_stackPush
  have _ := @loadStep_stackPush
  have _ := @execStore_stackPush
  have _ := @storeStep_stackPush
  have _ := @runHostCallWith_ok
  have _ := @hostCallStep_ok
  have _ := @lookupLocal_writeLocal_same
  have _ := @lookupGlobal_writeGlobal_same
  have _ := @lookupRegister_writeRegister_same
  have _ := @lookupStorage_writeStorage_same
  have _ := @host_beginCall_input
  have _ := @host_beginCall_registers
  have _ := @host_beginCall_returnValue
  exact True.intro

theorem stack_roundtrip_sample :
    ProofForge.Backend.WasmHost.WasmInterpreter.stackPop
      (ProofForge.Backend.WasmHost.WasmInterpreter.stackPush ({} : State) 7) =
        Except.ok (7, ({} : State)) := by
  exact stackPop_stackPush ({} : State) 7

theorem local_write_sample :
    ProofForge.Backend.WasmHost.WasmInterpreter.lookupLocal?
      (ProofForge.Backend.WasmHost.WasmInterpreter.writeLocal (#[] : Locals) "x" 9)
      "x" = some 9 := by
  exact lookupLocal_writeLocal_same (#[] : Locals) "x" 9

theorem state_step_reduction_chain_sample :
    StateStepReductionChain [pushStep 7, localSetStep "x"] ({} : State)
      { ({} : State) with locals :=
          ProofForge.Backend.WasmHost.WasmInterpreter.writeLocal (#[] : Locals) "x" 7 } := by
  apply StateStepReductionChain.cons
  · exact pushStep_ok ({} : State) 7
  · apply StateStepReductionChain.cons
    · exact localSetStep_stackPush ({} : State) "x" 7
    · exact StateStepReductionChain.nil
        { ({} : State) with locals :=
            ProofForge.Backend.WasmHost.WasmInterpreter.writeLocal (#[] : Locals) "x" 7 }

theorem run_state_steps_chain_sample :
    runStateSteps [pushStep 7, localSetStep "x"] ({} : State) =
      .ok { ({} : State) with locals :=
          ProofForge.Backend.WasmHost.WasmInterpreter.writeLocal (#[] : Locals) "x" 7 } := by
  exact runStateSteps_of_reductionChain state_step_reduction_chain_sample

end ProofForge.Tests.WasmExec

def main : IO UInt32 := do
  IO.println "wasm-exec-smoke: generic Wasm stack/state helper lemmas checked"
  return 0
