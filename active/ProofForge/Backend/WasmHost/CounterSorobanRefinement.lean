import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.WasmHost.CounterWasmRefinement
import ProofForge.Backend.WasmHost.SorobanHost
import ProofForge.Backend.WasmHost.WasmExec
import ProofForge.IR.CounterSemantics
import ProofForge.IR.StepSemantics

/-! ## Counter IR ↔ Wasm core universal refinement on Soroban host (Phase 4 WASM host family).

Chain-genericity test: Counter reuses the SAME host-agnostic
`counterWasmCoreTraceStep` from `CounterWasmRefinement` (the shared `WasmExec`
core tail). Only the host instantiation differs — Soroban `_put`/`_get` via
`SorobanHost` instead of NEAR `storage_read`/`storage_write` or CosmWasm
`db_read`/`db_write`. The abstract storage-word core and universal induction
are unchanged. This is the **third** WASM host adapter proving the WASM
host-family thesis: a new WASM chain is a thin `*Host.lean` + per-host
refinement reusing the shared core, not a forked EmitWat. -/

namespace ProofForge.Backend.WasmHost.CounterSorobanRefinement

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.CounterSemantics
open ProofForge.IR.StepSemantics
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec
open ProofForge.Backend.WasmHost.SorobanHost
open ProofForge.Backend.WasmHost.CounterWasmRefinement

abbrev IRState := CounterWasmRefinement.IRState
abbrev CounterCall := CounterWasmRefinement.CounterCall
abbrev counterIRStep := CounterWasmRefinement.counterIRStep
abbrev CoreState := CounterWasmRefinement.CounterWasmCoreState
abbrev CounterWasmRel := CounterWasmRefinement.CounterWasmRel
abbrev counterWasmCoreTraceStep := CounterWasmRefinement.counterWasmCoreTraceStep
abbrev counterTraceSafeAfterInitialize := CounterWasmRefinement.counterTraceSafeAfterInitialize
abbrev CounterStepSafe := CounterWasmRefinement.CounterStepSafe

/-! ### Per-entrypoint simulation (same abstract core, Soroban host axis) -/

theorem counterSoroban_initialize_simulates
    {irState core nextIr observable}
    (hirStep : counterIRStep irState .initialize = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore :=
  counterWasmCore_initialize_simulates hirStep

theorem counterSoroban_increment_simulates
    {irState core nextIr observable}
    (hrel : CounterWasmRel irState core)
    (hirStep : counterIRStep irState .increment = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .increment = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore :=
  counterWasmCore_increment_simulates hrel hirStep

theorem counterSoroban_get_simulates
    {irState core nextIr observable}
    (hrel : CounterWasmRel irState core)
    (hirStep : counterIRStep irState .get = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .get = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore :=
  counterWasmCore_get_simulates hrel hirStep

theorem counterSoroban_step_simulates
    (call : CounterCall) {irState : IRState} {core : CoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ nextIr nextCore observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterWasmCoreTraceStep core call = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore :=
  counterWasmCore_step_simulates_from_obligations counterWasmCoreObligations call hrel

theorem counterSoroban_trace_simulates
    (calls : List CounterCall) {irState : IRState} {core : CoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState calls observables ∧
      IRTraceMatches counterWasmCoreTraceStep core calls observables :=
  counterWasmCore_trace_simulates_from_obligations counterWasmCoreObligations calls hrel

theorem counterSoroban_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CoreState) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterWasmCoreTraceStep core (.initialize :: calls) observables :=
  counterWasmCore_trace_simulates_after_initialize_from_obligations
    counterWasmCoreObligations calls irState core

theorem counterSoroban_safe_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CoreState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterWasmCoreTraceStep core (.initialize :: calls) observables :=
  counterWasmCore_safe_trace_simulates_after_initialize_from_obligations
    counterWasmCoreSafeObligations calls irState core hsafe

theorem counterSoroban_canonical_safe_trace_simulates :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep
        (.initialize :: [.get, .increment, .get]) State.empty =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep
        (.initialize :: [.get, .increment, .get]) { storage := #[], returnValue := #[] } =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore := by
  obtain ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal, _, _⟩ :=
    counterSoroban_safe_trace_simulates_after_initialize
      [.get, .increment, .get] State.empty { storage := #[], returnValue := #[] }
      counterTraceSafe_initialize_get_increment_get
  exact ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal⟩

/-- Chain axis: Soroban `_put` updates the shared byte-level storage table that
all three host families use; the abstract Counter core reads the same scalar
`count` regardless of bridge. This is the Soroban analogue of
`counterCosmWasm_host_db_write_preserves_count_storage`. -/
theorem counterSoroban_host_put_preserves_count_storage
    (state : WasmExec.State) (keyPtr keyLen valuePtr valueLen : Nat) (count : Nat)
    (hbridge : state.host.bridge = ProofForge.Target.HostBridge.soroban)
    (hkey : readBytes state.memory keyPtr keyLen = counterWasmCountKey)
    (hvalue : readBytes state.memory valuePtr valueLen = natToLEBytes 8 count) :
    runHostCall "_put"
        (stackPush
          (stackPush
            (stackPush
              (stackPush state keyPtr) keyLen) valuePtr) valueLen) =
      .ok { state with
        host := { state.host with
          storage := writeStorage state.host.storage counterWasmCountKey (natToLEBytes 8 count) } } :=
  runHostCall_soroban_put_stack_ok state keyPtr keyLen valuePtr valueLen
    counterWasmCountKey (natToLEBytes 8 count) hbridge hkey hvalue

end ProofForge.Backend.WasmHost.CounterSorobanRefinement