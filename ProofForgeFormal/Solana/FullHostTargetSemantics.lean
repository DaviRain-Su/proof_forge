/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# TargetSemantics instance for the full-program solanalib host

Registers the Counter-capable full-program host as a `TargetSemantics` so the
shared FV-9 substrate can name it alongside PF `solanaSbpfTargetSemantics`
and the tiny `counter-model`.
-/

import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.IR.Examples.Counter
import ProofForge.IR.StepSemantics
import ProofForgeFormal.Solana.CounterHostRefinement
import ProofForgeFormal.Solana.FullProgramHost

namespace ProofForgeFormal.Solana.FullHostTargetSemantics

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForgeFormal.Solana.FullProgramHost
open ProofForgeFormal.Solana.CounterHostRefinement

def fullHostTargetSemantics : TargetSemantics where
  id := "solana-sbpf-solanalib-host"
  supportedFragments := #[.counter]
  fragmentAccepts := isCounterModule
  lowerableAccepts := isCounterShapeLowerable
  MachineState := FullHostMachineState
  Call := TraceCall
  Obs := ObservableStep
  traceStep := FullHostMachineState.traceStep
  runTrace := fun calls state =>
    ProofForge.IR.StepSemantics.runTraceListGen FullHostMachineState.traceStep calls state
  runTrace_eq_traceStep := by
    intro calls state
    rfl
  executableTraceOk := fun obligation =>
    match lowerFullModule obligation.module with
    | .error _ => false
    | .ok p =>
        match runFullTraceList p obligation.module obligation.calls.toList #[] with
        | .error _ => false
        | .ok (_, steps) => steps == obligation.expected
  irStateRel := fun irState machine =>
    fullHostSimulationRel irState machine = true
  initialMachineState := fun _ => none
  initialRelHolds := by
    intro m ms h
    cases h

theorem full_host_target_semantics_counter_ok :
    fullHostTargetSemantics.fragmentAccepts
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem full_host_target_semantics_executable_counter_ok :
    fullHostTargetSemantics.executableTraceOk {
      name := "counter-host-target"
      module := ProofForge.IR.Examples.Counter.module
      calls := #[
        { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
        { entrypoint := ProofForge.IR.Examples.Counter.get },
        { entrypoint := ProofForge.IR.Examples.Counter.increment },
        { entrypoint := ProofForge.IR.Examples.Counter.get }
      ]
      expected := #[
        { entrypointName := "initialize", returnValue := .none },
        { entrypointName := "get", returnValue := .u64 0 },
        { entrypointName := "increment", returnValue := .none },
        { entrypointName := "get", returnValue := .u64 1 }
      ]
    } = true := by
  native_decide

end ProofForgeFormal.Solana.FullHostTargetSemantics
