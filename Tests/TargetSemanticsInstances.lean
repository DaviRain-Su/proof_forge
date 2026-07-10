import ProofForge.Backend.Evm.Refinement
import ProofForge.Backend.Evm.YulHostRefinement
import ProofForge.Backend.Solana.Refinement
import ProofForge.Backend.WasmHost.Refinement
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.IR.StepSemantics

/-! ## Shared TargetSemantics instance smoke

Pins that the existing EVM/Yul, Solana sBPF, and Wasm/NEAR executable trace
runners are reachable through the shared `TargetSemantics` interface.
-/

namespace ProofForge.Tests.TargetSemanticsInstances

open ProofForge.Backend.Refinement
open ProofForge.IR.StepSemantics

#check ProofForge.Backend.Evm.Refinement.evmYulTargetSemantics
#check ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics
#check ProofForge.Backend.WasmHost.Refinement.wasmNearTargetSemantics
#check TargetSemantics.runTrace_sound

theorem evm_counter_target_semantics_trace_ok :
    ProofForge.Backend.Evm.Refinement.evmYulTargetSemantics.executableTraceOk
      ProofForge.Backend.Evm.Refinement.counterTraceObligation = true := by
  native_decide

theorem evmYul_irStateRel_is_counterYulSimulationRel
    (irState : ProofForge.IR.Semantics.State)
    (machine : ProofForge.Backend.Evm.Refinement.EvmYulMachineState) :
    ProofForge.Backend.Evm.Refinement.evmYulTargetSemantics.irStateRel irState machine ↔
      ProofForge.Backend.Evm.YulHostRefinement.counterYulSimulationRel
        irState machine = true := by
  rfl

def evmYulCounterInitialStateExists : Bool :=
  match ProofForge.Backend.Evm.Refinement.evmYulTargetSemantics.initialMachineState
      ProofForge.IR.Examples.Counter.module with
  | some _ => true
  | none => false

theorem evm_yul_counter_initial_state_exists :
    evmYulCounterInitialStateExists = true := by
  native_decide

theorem solana_counter_target_semantics_trace_ok :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.executableTraceOk
      ProofForge.Backend.Solana.Refinement.counterTraceObligation = true := by
  native_decide

theorem solana_counter_target_semantics_fragment_ok :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.supportedFragment
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem wasm_counter_target_semantics_trace_ok :
    ProofForge.Backend.WasmHost.Refinement.wasmNearTargetSemantics.executableTraceOk
      ProofForge.Backend.WasmHost.Refinement.counterTraceObligation = true := by
  native_decide

#check (fun (object : Lean.Compiler.Yul.Object) calls storage =>
  TargetSemantics.runTrace_sound
    ProofForge.Backend.Evm.Refinement.evmYulTargetSemantics calls
    ({ object, storage } : ProofForge.Backend.Evm.Refinement.EvmYulMachineState))

#check (fun (program : ProofForge.Backend.Solana.SbpfInterpreter.SbpfProgram)
    (module : ProofForge.IR.Module) calls memory =>
  TargetSemantics.runTrace_sound
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics calls
    ({ program, module, memory } :
      ProofForge.Backend.Solana.Refinement.SolanaSbpfMachineState))

#check (fun (wasm : ProofForge.Compiler.Wasm.Module) calls state =>
  TargetSemantics.runTrace_sound
    ProofForge.Backend.WasmHost.Refinement.wasmNearTargetSemantics calls
    ({ wasm, state } : ProofForge.Backend.WasmHost.Refinement.WasmHostMachineState))

/-! ## FV-9.1: generic simulation relation is a first-class TargetSemantics field

The `irStateRel` / `initialMachineState` / `initialRelHolds` fields added in
FV-9.1 are reachable on every existing target instance, and the counter-model
target carries the real `CounterStateRel`-based relation with a proved base
case (no related initial state pre-initialize — the trace proofs establish
the relation post-initialize). This is the substrate FV-9.3's ∀-contract
induction will consume. -/

open ProofForge.Backend.Refinement.CounterUniversal

-- Every target carries the FV-9.1 fields.
#check (TargetSemantics.irStateRel :
    (sem : TargetSemantics) → ProofForge.IR.Semantics.State → sem.MachineState → Prop)
#check (TargetSemantics.initialMachineState :
    (sem : TargetSemantics) → ProofForge.IR.Module → Option sem.MachineState)
#check (TargetSemantics.initialRelHolds :
    (sem : TargetSemantics) → ∀ (m : ProofForge.IR.Module) (ms : sem.MachineState),
      sem.initialMachineState m = some ms → sem.irStateRel ProofForge.IR.Semantics.State.empty ms)

-- The counter-model target's relation is the real `CounterStateRel`, not the
-- trivial default.
theorem counterModel_irStateRel_is_CounterStateRel
    (irState : ProofForge.IR.Semantics.State) (count : Nat) :
    counterModelTargetSemantics.irStateRel irState count ↔ CounterStateRel irState count := by
  rfl

-- The counter-model base case: no related initial state pre-initialize.
theorem counterModel_initialMachineState_none (m : ProofForge.IR.Module) :
    counterModelTargetSemantics.initialMachineState m = none := by
  rfl

theorem counterModel_initialRelHolds_sound (m : ProofForge.IR.Module) (ms : Nat)
    (h : counterModelTargetSemantics.initialMachineState m = some ms) :
    counterModelTargetSemantics.irStateRel ProofForge.IR.Semantics.State.empty ms :=
  counterModelTargetSemantics.initialRelHolds m ms h

end ProofForge.Tests.TargetSemanticsInstances

def main : IO UInt32 := do
  IO.println "target-semantics-instances-smoke: EVM/Yul, Solana sBPF, and Wasm/NEAR executable trace runners are wired through TargetSemantics (incl. FV-9.1 irStateRel/initialRelHolds fields)"
  return 0
