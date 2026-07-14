/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# IR ↔ FullProgramHost paired simulation (ValueVault default scenario)

Pointwise lockstep between `IR.Semantics` and the full-program solanalib host
for the ValueVault default scenario — the multi-field companion to
`CounterHostRefinement`.
-/

import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Solana.Refinement
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForge.IR.StepSemantics
import ProofForgeFormal.Solana.CounterHostRefinement
import ProofForgeFormal.Solana.FullProgramHost

namespace ProofForge.Backend.Solana.ValueVaultHostRefinement

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.FullProgramHost
open ProofForge.Backend.Solana.CounterHostRefinement

/-- Multi-field relation: every IR u64 state binding matches host memory at
the layout offset (optional missing/missing ok). -/
def valueVaultHostRel
    (irState : ProofForge.IR.Semantics.State)
    (machine : FullHostMachineState) : Bool :=
  let module := ProofForge.Contract.Examples.ValueVaultInvariant.module
  module.state.all fun decl =>
    match decl.kind, decl.type with
    | .scalar, .u64 =>
        RMemoryOptional module decl.id irState machine.memory
    | _, _ => true

def valueVaultHostInitial (program : FullProgram) : FullHostMachineState :=
  {
    program
    module := ProofForge.Contract.Examples.ValueVaultInvariant.module
    memory := #[]
  }

def valueVaultHostTraceOk : Bool :=
  match lowerFullModule ProofForge.Contract.Examples.ValueVaultInvariant.module with
  | .error _ => false
  | .ok program =>
      executableSimulationTraceOk
        runEntrypointObservable
        FullHostMachineState.traceStep
        valueVaultHostRel
        ProofForge.Backend.Solana.Refinement.valueVaultTraceCalls.toList
        ProofForge.IR.Semantics.State.empty
        (valueVaultHostInitial program)

theorem value_vault_host_trace_simulation_ok :
    valueVaultHostTraceOk = true := by
  native_decide

theorem value_vault_host_trace_simulation_sound_checked :
    match lowerFullModule ProofForge.Contract.Examples.ValueVaultInvariant.module with
    | .error _ => True
    | .ok program =>
        ∃ finalIr finalTarget observables,
          ProofForge.IR.StepSemantics.runTraceListGen
            runEntrypointObservable
            ProofForge.Backend.Solana.Refinement.valueVaultTraceCalls.toList
            ProofForge.IR.Semantics.State.empty =
              .ok (finalIr, observables) ∧
          ProofForge.IR.StepSemantics.runTraceListGen
            FullHostMachineState.traceStep
            ProofForge.Backend.Solana.Refinement.valueVaultTraceCalls.toList
            (valueVaultHostInitial program) =
              .ok (finalTarget, observables) ∧
          valueVaultHostRel finalIr finalTarget = true := by
  have h := value_vault_host_trace_simulation_ok
  unfold valueVaultHostTraceOk at h
  cases hmod : lowerFullModule ProofForge.Contract.Examples.ValueVaultInvariant.module with
  | error _ => trivial
  | ok program =>
      simp [hmod] at h
      exact executableSimulationTraceOk_sound
        runEntrypointObservable
        FullHostMachineState.traceStep
        valueVaultHostRel
        ProofForge.Backend.Solana.Refinement.valueVaultTraceCalls.toList
        ProofForge.IR.Semantics.State.empty
        (valueVaultHostInitial program)
        h

end ProofForge.Backend.Solana.ValueVaultHostRefinement
