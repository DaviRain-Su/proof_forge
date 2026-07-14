/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# IR ↔ FullProgramHost refinement (Counter fragment, pointwise)

Lifts the full-program solanalib host (`FullProgramHost`) into the shared
`executableSimulationTraceOk` / `executableStepSimulationOk` shape used by
`ProofForge.Backend.Solana.Refinement` for the PF `SbpfInterpreter`.

This is still **pointwise** (fixed Counter scenario + concrete prefixes), not
universal all-input simulation. The induction substrate is
`traceSimulation_lift` / `executableSimulationTraceOk_sound` from
`ProofForge.Backend.Refinement.Core`.

```
IR.Semantics.runEntrypointObservable
        │ paired-step (executableSimulationTraceOk)
        ▼
FullProgramHost.traceStep  (solanalib step + PF layout + syscall stubs)
```

Portable IR remains the multi-chain source of truth.
-/

import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.IR.Examples.Counter
import ProofForge.IR.StepSemantics
import ProofForgeFormal.Solana.FullProgramHost
import ProofForgeFormal.Solana.HostBridge

namespace ProofForge.Backend.Solana.CounterHostRefinement

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.FullProgramHost
open ProofForge.Backend.Solana.HostBridge

/-- Machine state for the full-program solanalib host. -/
structure FullHostMachineState where
  program : FullProgram
  module : Module
  memory : Memory := #[]
  returnData : Option Nat := none

def FullHostMachineState.traceStep (state : FullHostMachineState) (call : TraceCall) :
    Except String (FullHostMachineState × ObservableStep) := do
  let (memory, hs) ← runFullEntrypoint state.program state.module state.memory call
  let ret ← observeHost call.entrypoint hs
  .ok ({
    state with
      memory
      returnData := hs.returnData
  }, {
    entrypointName := call.entrypoint.name
    returnValue := ret
  })

/-- Scalar storage relation: IR `count` ↔ host memory at `countOff`. -/
def fullHostSimulationRel
    (irState : ProofForge.IR.Semantics.State)
    (machine : FullHostMachineState) : Bool :=
  RMemoryOptional
    ProofForge.IR.Examples.Counter.module "count" irState machine.memory

def fullHostInitial
    (program : FullProgram) : FullHostMachineState :=
  {
    program
    module := ProofForge.IR.Examples.Counter.module
    memory := #[]
  }

def counterHostCalls : List TraceCall := [
  { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
  { entrypoint := ProofForge.IR.Examples.Counter.get },
  { entrypoint := ProofForge.IR.Examples.Counter.increment },
  { entrypoint := ProofForge.IR.Examples.Counter.get }
]

def counterHostStateAfterPrefix
    (program : FullProgram)
    (callPrefix : List TraceCall) :
    Except String (ProofForge.IR.Semantics.State × FullHostMachineState) := do
  let (irState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    runEntrypointObservable callPrefix ProofForge.IR.Semantics.State.empty
  let (targetState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    FullHostMachineState.traceStep callPrefix (fullHostInitial program)
  .ok (irState, targetState)

def counterHostStepSimulationOkAfter
    (callPrefix : List TraceCall) (call : TraceCall) : Bool :=
  match lowerFullModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok program =>
      match counterHostStateAfterPrefix program callPrefix with
      | .error _ => false
      | .ok (irState, targetState) =>
          executableStepSimulationOk
            runEntrypointObservable
            FullHostMachineState.traceStep
            fullHostSimulationRel
            call
            irState
            targetState

def counterHostTraceSimulationOk : Bool :=
  match lowerFullModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok program =>
      executableSimulationTraceOk
        runEntrypointObservable
        FullHostMachineState.traceStep
        fullHostSimulationRel
        counterHostCalls
        ProofForge.IR.Semantics.State.empty
        (fullHostInitial program)

/-! ### Pointwise anchors (native_decide) -/

theorem counter_host_initialize_step_ok :
    counterHostStepSimulationOkAfter []
      { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint } = true := by
  native_decide

theorem counter_host_get_after_init_step_ok :
    counterHostStepSimulationOkAfter
      [{ entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }]
      { entrypoint := ProofForge.IR.Examples.Counter.get } = true := by
  native_decide

theorem counter_host_increment_after_init_step_ok :
    counterHostStepSimulationOkAfter
      [{ entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }]
      { entrypoint := ProofForge.IR.Examples.Counter.increment } = true := by
  native_decide

theorem counter_host_get_after_increment_step_ok :
    counterHostStepSimulationOkAfter
      [ { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }
      , { entrypoint := ProofForge.IR.Examples.Counter.increment } ]
      { entrypoint := ProofForge.IR.Examples.Counter.get } = true := by
  native_decide

theorem counter_host_trace_simulation_ok :
    counterHostTraceSimulationOk = true := by
  native_decide

/-! ### Soundness bridges (kernel-checked wrappers over native_decide premises) -/

theorem counter_host_step_simulation_sound_after
    (callPrefix : List TraceCall) (call : TraceCall) :
    counterHostStepSimulationOkAfter callPrefix call = true →
      match lowerFullModule ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok program =>
          match counterHostStateAfterPrefix program callPrefix with
          | .error _ => True
          | .ok (irState, targetState) =>
              ∃ nextIr nextTarget observable,
                runEntrypointObservable irState call =
                  .ok (nextIr, observable) ∧
                FullHostMachineState.traceStep targetState call =
                  .ok (nextTarget, observable) ∧
                fullHostSimulationRel nextIr nextTarget = true := by
  intro h
  unfold counterHostStepSimulationOkAfter at h
  cases hmod : lowerFullModule ProofForge.IR.Examples.Counter.module with
  | error _ => trivial
  | ok program =>
      simp [hmod] at h
      cases hprefix : counterHostStateAfterPrefix program callPrefix with
      | error _ =>
          simp [hprefix]
      | ok pair =>
          rcases pair with ⟨irState, targetState⟩
          simp [hprefix] at h
          simpa [hmod, hprefix] using
            executableStepSimulationOk_sound
              runEntrypointObservable
              FullHostMachineState.traceStep
              fullHostSimulationRel
              call irState targetState h

theorem counter_host_initialize_step_sound_checked :
    match lowerFullModule ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok program =>
        match counterHostStateAfterPrefix program [] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState
                  { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint } =
                .ok (nextIr, observable) ∧
              FullHostMachineState.traceStep targetState
                  { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint } =
                .ok (nextTarget, observable) ∧
              fullHostSimulationRel nextIr nextTarget = true :=
  counter_host_step_simulation_sound_after []
    { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }
    counter_host_initialize_step_ok

theorem counter_host_trace_simulation_sound :
    counterHostTraceSimulationOk = true →
      match lowerFullModule ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok program =>
          ∃ finalIr finalTarget observables,
            ProofForge.IR.StepSemantics.runTraceListGen
              runEntrypointObservable
              counterHostCalls
              ProofForge.IR.Semantics.State.empty =
                .ok (finalIr, observables) ∧
            ProofForge.IR.StepSemantics.runTraceListGen
              FullHostMachineState.traceStep
              counterHostCalls
              (fullHostInitial program) =
                .ok (finalTarget, observables) ∧
            fullHostSimulationRel finalIr finalTarget = true := by
  intro h
  unfold counterHostTraceSimulationOk at h
  cases hmod : lowerFullModule ProofForge.IR.Examples.Counter.module with
  | error _ => trivial
  | ok program =>
      simp [hmod] at h
      exact executableSimulationTraceOk_sound
        runEntrypointObservable
        FullHostMachineState.traceStep
        fullHostSimulationRel
        counterHostCalls
        ProofForge.IR.Semantics.State.empty
        (fullHostInitial program)
        h

theorem counter_host_trace_simulation_sound_checked :
    match lowerFullModule ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok program =>
        ∃ finalIr finalTarget observables,
          ProofForge.IR.StepSemantics.runTraceListGen
            runEntrypointObservable
            counterHostCalls
            ProofForge.IR.Semantics.State.empty =
              .ok (finalIr, observables) ∧
          ProofForge.IR.StepSemantics.runTraceListGen
            FullHostMachineState.traceStep
            counterHostCalls
            (fullHostInitial program) =
              .ok (finalTarget, observables) ∧
          fullHostSimulationRel finalIr finalTarget = true :=
  counter_host_trace_simulation_sound counter_host_trace_simulation_ok

/-! ### Bridge to CounterCall (shared fragment vocabulary) -/

def counterCallToTraceCall : CounterCall → TraceCall
  | .initialize => { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }
  | .increment => { entrypoint := ProofForge.IR.Examples.Counter.increment }
  | .get => { entrypoint := ProofForge.IR.Examples.Counter.get }

def fullHostTraceStepCounterCall (state : FullHostMachineState) (call : CounterCall) :
    Except String (FullHostMachineState × ObservableReturn) := do
  let (next, step) ← FullHostMachineState.traceStep state (counterCallToTraceCall call)
  .ok (next, step.returnValue)

/-- IR CounterCall step paired with full-host CounterCall step over the
canonical scenario, using `ObservableReturn` (not full `ObservableStep`). -/
def counterHostCounterCallTraceOk : Bool :=
  match lowerFullModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok program =>
      executableSimulationTraceOk
        irStep
        fullHostTraceStepCounterCall
        (fun irState machine => fullHostSimulationRel irState machine)
        [.initialize, .get, .increment, .get]
        ProofForge.IR.Semantics.State.empty
        (fullHostInitial program)

theorem counter_host_counter_call_trace_ok :
    counterHostCounterCallTraceOk = true := by
  native_decide

theorem counter_host_counter_call_trace_sound_checked :
    match lowerFullModule ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok program =>
        ∃ finalIr finalTarget observables,
          ProofForge.IR.StepSemantics.runTraceListGen
            irStep
            [.initialize, .get, .increment, .get]
            ProofForge.IR.Semantics.State.empty =
              .ok (finalIr, observables) ∧
          ProofForge.IR.StepSemantics.runTraceListGen
            fullHostTraceStepCounterCall
            [.initialize, .get, .increment, .get]
            (fullHostInitial program) =
              .ok (finalTarget, observables) ∧
          fullHostSimulationRel finalIr finalTarget = true := by
  have h := counter_host_counter_call_trace_ok
  unfold counterHostCounterCallTraceOk at h
  cases hmod : lowerFullModule ProofForge.IR.Examples.Counter.module with
  | error _ => trivial
  | ok program =>
      simp [hmod] at h
      exact executableSimulationTraceOk_sound
        irStep
        fullHostTraceStepCounterCall
        (fun irState machine => fullHostSimulationRel irState machine)
        [.initialize, .get, .increment, .get]
        ProofForge.IR.Semantics.State.empty
        (fullHostInitial program)
        h

end ProofForge.Backend.Solana.CounterHostRefinement
