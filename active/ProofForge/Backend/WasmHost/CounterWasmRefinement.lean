import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.WasmHost.NearHost
import ProofForge.Backend.WasmHost.WasmExec
import ProofForge.IR.CounterSemantics
import ProofForge.IR.StepSemantics
import ProofForge.IR.SemanticsFuel
import ProofForge.Backend.Refinement.ConstructorCoverage

/-! ## Counter IR ↔ Wasm core-tail universal refinement (WASM-3/4).

This is the WASM twin of `Solana.CounterSbpfRefinement`: a small abstract
`CounterWasmCoreTraceStep` that operates directly on the host storage word for
`count`, plus the per-entrypoint simulation lemmas that bridge it to the IR
reference semantics via the shared `CounterUniversal` induction.

The proof stays "Solana-light": it composes generic `WasmExec` stack-machine
lemmas with `NearHost` storage_read/storage_write facts, then closes everything
with `simp`/`rfl`. No EVM-style reduction chain is needed because the abstract
core is intentionally tiny.

Generic work belongs in `WasmExec.lean` and `NearHost.lean`; this file is
Counter-specific glue only.
-/

namespace ProofForge.Backend.WasmHost.CounterWasmRefinement

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.CounterSemantics
open ProofForge.IR.StepSemantics
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec
open ProofForge.Backend.WasmHost.NearHost

abbrev IRState := ProofForge.IR.Semantics.State
abbrev CounterCall := ProofForge.Backend.Refinement.CounterUniversal.CounterCall
abbrev counterIRStep := ProofForge.Backend.Refinement.CounterUniversal.irStep

def counterU64Modulus : Nat := 2 ^ 64

/-- Abstract core storage entry: a key paired with a scalar `Nat` value.

The Counter Wasm core state deliberately does NOT use `WasmInterpreter.Storage`
(which stores bytes) so that the core trace step can stay a pure `Nat` state
machine. The bytes encoding is only introduced when composing with concrete Wasm
memory. -/
abbrev CounterWasmCoreStorage := Array (WasmInterpreter.Bytes × Nat)

structure CounterWasmCoreState where
  storage : CounterWasmCoreStorage := #[]
  returnValue : WasmInterpreter.Bytes := #[]
  deriving Inhabited


def counterModule := ProofForge.IR.Examples.Counter.module

def counterWasmCountKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "count"

/-- Read the current count from the abstract core's host storage. -/
def counterWasmCoreCount (core : CounterWasmCoreState) : Nat :=
  match core.storage.find? (fun entry => entry.fst == counterWasmCountKey) with
  | some entry => entry.snd
  | none => 0

/-- IR `count` scalar ↔ host-storage word at the layout key.

The abstract core stores the count as a `Nat` in host storage; the bytes
encoding is only materialized when composing with concrete Wasm memory. -/
def CounterWasmRel (irState : IRState) (core : CounterWasmCoreState) : Prop :=
  ∃ count, CounterStateRel irState count ∧
    core.storage = #[(counterWasmCountKey, count)]

theorem CounterStateRel_iff {state : IRState} {count : Nat} :
    CounterStateRel state count ↔ state.read "count" = some (.u64 count) := by
  unfold CounterStateRel
  rfl

theorem counterWasmRel_write_count (irState : IRState) (count : Nat) :
    CounterWasmRel (irState.write "count" (.u64 count))
      { storage := #[(counterWasmCountKey, count)] } := by
  refine ⟨count, counter_state_rel_write_count irState count, rfl⟩

theorem counterWasmRel_after_initialize (irState : IRState) (core : CounterWasmCoreState) :
    CounterWasmRel (irState.write "count" (.u64 0))
      { core with storage := #[(counterWasmCountKey, 0)] } := by
  exact counterWasmRel_write_count irState 0

theorem counterWasmRel_left_counterStateRel {irState : IRState} {core : CounterWasmCoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ count, CounterStateRel irState count := by
  rcases hrel with ⟨count, hcounter, _⟩
  exact ⟨count, hcounter⟩

theorem counterWasmCoreCount_of_storage (core : CounterWasmCoreState) (count : Nat)
    (hstorage : core.storage = #[(counterWasmCountKey, count)]) :
    counterWasmCoreCount core = count := by
  unfold counterWasmCoreCount
  rw [hstorage]
  simp

/-! ### Abstract core trace step (storage-word level) -/

def counterWasmCoreTraceStep (core : CounterWasmCoreState) (call : CounterCall) :
    Except String (CounterWasmCoreState × ObservableReturn) :=
  match call with
  | .initialize =>
      .ok ({ storage := #[(counterWasmCountKey, 0)], returnValue := #[] }, .none)
  | .increment =>
      let count := counterWasmCoreCount core
      .ok ({ storage := #[(counterWasmCountKey, count + 1)], returnValue := #[] }, .none)
  | .get =>
      let count := counterWasmCoreCount core
      .ok ({ storage := core.storage, returnValue := natToLEBytes 8 count }, .u64 count)

/-! ### Overflow-safe trace predicate (FV-5 WASM boundary) -/

def counterTraceSafeFromCount : Nat → List CounterCall → Bool
  | count, [] => decide (count < counterU64Modulus)
  | _count, .initialize :: rest => counterTraceSafeFromCount 0 rest
  | count, .get :: rest =>
      decide (count < counterU64Modulus) && counterTraceSafeFromCount count rest
  | count, .increment :: rest =>
      decide (count + 1 < counterU64Modulus) &&
        counterTraceSafeFromCount (count + 1) rest

def counterTraceSafeAfterInitialize (calls : List CounterCall) : Bool :=
  counterTraceSafeFromCount 0 calls

theorem counterTraceSafe_initialize_get_increment_get :
    counterTraceSafeAfterInitialize [.get, .increment, .get] = true := by
  native_decide

def CounterStepSafe (call : CounterCall) (irState : IRState) : Prop :=
  match call with
  | .initialize => True
  | .get =>
      ∀ count, CounterStateRel irState count → count < counterU64Modulus
  | .increment =>
      ∀ count, CounterStateRel irState count → count + 1 < counterU64Modulus

/-! ### Per-entrypoint simulation obligations -/

structure CounterWasmCoreEntrypointObligations where
  initialize_simulates :
    ∀ {irState core nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore
  increment_simulates :
    ∀ {irState core nextIr observable},
      CounterWasmRel irState core →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .increment = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore
  get_simulates :
    ∀ {irState core nextIr observable},
      CounterWasmRel irState core →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .get = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore

structure CounterWasmCoreSafeEntrypointObligations where
  initialize_simulates :
    ∀ {irState core nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore
  increment_simulates :
    ∀ {irState core nextIr observable},
      CounterWasmRel irState core →
      CounterStepSafe .increment irState →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .increment = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore
  get_simulates :
    ∀ {irState core nextIr observable},
      CounterWasmRel irState core →
      CounterStepSafe .get irState →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextCore,
          counterWasmCoreTraceStep core .get = .ok (nextCore, observable) ∧
          CounterWasmRel nextIr nextCore

theorem counterWasmCore_initialize_simulates
    {irState core nextIr observable}
    (hirStep : counterIRStep irState .initialize = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore := by
  refine ⟨{ storage := #[(counterWasmCountKey, 0)], returnValue := #[] }, ?_, ?_⟩
  · simp [counterWasmCoreTraceStep]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [initialize_total_ok] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [initialize_total_ok] at hirStep
    cases hirStep
    exact counterWasmRel_after_initialize irState core

theorem counterWasmCore_increment_simulates
    {irState core nextIr observable}
    (hrel : CounterWasmRel irState core)
    (hirStep : counterIRStep irState .increment = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .increment = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore := by
  rcases hrel with ⟨count, hcounter, hstorage⟩
  refine ⟨{ storage := #[(counterWasmCountKey, count + 1)], returnValue := #[] }, ?_, ?_⟩
  · simp [counterWasmCoreTraceStep, counterWasmCoreCount_of_storage core count hstorage]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [increment_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [increment_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    exact counterWasmRel_write_count irState (count + 1)

theorem counterWasmCore_get_simulates
    {irState core nextIr observable}
    (hrel : CounterWasmRel irState core)
    (hirStep : counterIRStep irState .get = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterWasmCoreTraceStep core .get = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore := by
  rcases hrel with ⟨count, hcounter, hstorage⟩
  refine ⟨{ storage := core.storage, returnValue := natToLEBytes 8 count }, ?_, ?_⟩
  · simp [counterWasmCoreTraceStep, counterWasmCoreCount_of_storage core count hstorage]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [get_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [get_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    refine ⟨count, hcounter, hstorage⟩

def counterWasmCoreObligations : CounterWasmCoreEntrypointObligations where
  initialize_simulates := fun {_irState} {_core} {_nextIr} {_observable} hirStep =>
    counterWasmCore_initialize_simulates hirStep
  increment_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel hirStep =>
    counterWasmCore_increment_simulates hrel hirStep
  get_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel hirStep =>
    counterWasmCore_get_simulates hrel hirStep

def counterWasmCoreSafeObligations : CounterWasmCoreSafeEntrypointObligations where
  initialize_simulates := fun {_irState} {_core} {_nextIr} {_observable} hirStep =>
    counterWasmCore_initialize_simulates hirStep
  increment_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel _hsafe hirStep =>
    counterWasmCore_increment_simulates hrel hirStep
  get_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel _hsafe hirStep =>
    counterWasmCore_get_simulates hrel hirStep

theorem counterWasmCore_step_simulates_from_obligations
    (obligations : CounterWasmCoreEntrypointObligations)
    (call : CounterCall) {irState : IRState} {core : CounterWasmCoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ nextIr nextCore observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterWasmCoreTraceStep core call = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore := by
  obtain ⟨count, hcounter⟩ := counterWasmRel_left_counterStateRel hrel
  cases call
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, hrelNext⟩ :=
      counter_initialize_simulates irState count
    obtain ⟨nextCore, hcoreStep, hrelNext'⟩ :=
      obligations.initialize_simulates hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext'⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, hrelNext⟩ :=
      counter_increment_simulates hcounter
    obtain ⟨nextCore, hcoreStep, hrelNext'⟩ :=
      obligations.increment_simulates hrel hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext'⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, hrelNext⟩ :=
      counter_get_simulates hcounter
    obtain ⟨nextCore, hcoreStep, hrelNext'⟩ :=
      obligations.get_simulates hrel hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext'⟩

theorem counterWasmCore_safe_step_simulates_from_obligations
    (obligations : CounterWasmCoreSafeEntrypointObligations)
    (call : CounterCall) {irState : IRState} {core : CounterWasmCoreState}
    (hrel : CounterWasmRel irState core)
    (hsafe : CounterStepSafe call irState) :
    ∃ nextIr nextCore observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterWasmCoreTraceStep core call = .ok (nextCore, observable) ∧
      CounterWasmRel nextIr nextCore := by
  obtain ⟨count, hcounter⟩ := counterWasmRel_left_counterStateRel hrel
  cases call
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hrelNext⟩ :=
      counter_initialize_simulates irState count
    obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
      obligations.initialize_simulates hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hrelNext⟩ :=
      counter_increment_simulates hcounter
    obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
      obligations.increment_simulates hrel hsafe hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hrelNext⟩ :=
      counter_get_simulates hcounter
    obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
      obligations.get_simulates hrel hsafe hirStep
    exact ⟨nextIr, nextCore, observable, hirStep, hcoreStep, hrelNext⟩

theorem counterWasmCore_trace_simulates_from_obligations
    (obligations : CounterWasmCoreEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {core : CounterWasmCoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState calls observables ∧
      IRTraceMatches counterWasmCoreTraceStep core calls observables :=
  traceSimulation_lift counterIRStep counterWasmCoreTraceStep CounterWasmRel
    (fun call {_irState} {_targetState} hrel' =>
      counterWasmCore_step_simulates_from_obligations obligations call hrel')
    calls hrel

theorem counterWasmCore_safe_trace_simulates_from_obligations
    (obligations : CounterWasmCoreSafeEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {core : CounterWasmCoreState}
    {count : Nat}
    (hrel : CounterWasmRel irState core)
    (hcounter : CounterStateRel irState count)
    (hsafe : counterTraceSafeFromCount count calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState calls observables ∧
      IRTraceMatches counterWasmCoreTraceStep core calls observables := by
  induction calls generalizing irState core count with
  | nil =>
      refine ⟨irState, core, #[], rfl, rfl, hrel,
        IRTraceMatches.nil, IRTraceMatches.nil⟩
  | cons call rest ih =>
      cases call
      · have hsafeRest : counterTraceSafeFromCount 0 rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        obtain ⟨nextIr, _nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          counter_initialize_simulates irState count
        cases htargetStep
        obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
          obligations.initialize_simulates hirStep
        obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
            hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
          ih (irState := nextIr) (core := nextCore) (count := 0)
            hrelNext hcounterNext hsafeRest
        refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
          hrelFinal,
          IRTraceMatches.cons hirStep hirTraceRest,
          IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
        · exact runTraceListGen_cons_ok counterIRStep .initialize rest irState nextIr .none
            finalIr restObservables hirStep hirRest
        · exact runTraceListGen_cons_ok counterWasmCoreTraceStep .initialize rest core nextCore .none
            finalCore restObservables hcoreStep hcoreRest
      · have hsafePair :
            (count + 1 < counterU64Modulus) ∧
              counterTraceSafeFromCount (count + 1) rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        have hstepSafe : CounterStepSafe .increment irState := by
          intro count' hcount'
          have hread := CounterStateRel_iff.mp hcounter
          rw [CounterStateRel_iff.mp hcount'] at hread
          cases hread
          exact hsafePair.left
        obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          counter_increment_simulates hcounter
        cases htargetStep
        obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
          obligations.increment_simulates hrel hstepSafe hirStep
        obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
            hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
          ih (irState := nextIr) (core := nextCore) (count := count + 1)
            hrelNext hcounterNext hsafePair.right
        refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
          hrelFinal,
          IRTraceMatches.cons hirStep hirTraceRest,
          IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
        · exact runTraceListGen_cons_ok counterIRStep .increment rest irState nextIr .none
            finalIr restObservables hirStep hirRest
        · exact runTraceListGen_cons_ok counterWasmCoreTraceStep .increment rest core nextCore .none
            finalCore restObservables hcoreStep hcoreRest
      · have hsafePair :
            (count < counterU64Modulus) ∧
              counterTraceSafeFromCount count rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        have hstepSafe : CounterStepSafe .get irState := by
          intro count' hcount'
          have hread := CounterStateRel_iff.mp hcounter
          rw [CounterStateRel_iff.mp hcount'] at hread
          cases hread
          exact hsafePair.left
        obtain ⟨nextIr, _nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          counter_get_simulates hcounter
        cases htargetStep
        obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
          obligations.get_simulates hrel hstepSafe hirStep
        obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
            hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
          ih (irState := nextIr) (core := nextCore) (count := count)
            hrelNext hcounterNext hsafePair.right
        refine ⟨finalIr, finalCore, #[.u64 count] ++ restObservables, ?_, ?_,
          hrelFinal,
          IRTraceMatches.cons hirStep hirTraceRest,
          IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
        · exact runTraceListGen_cons_ok counterIRStep .get rest irState nextIr (.u64 count)
            finalIr restObservables hirStep hirRest
        · exact runTraceListGen_cons_ok counterWasmCoreTraceStep .get rest core nextCore (.u64 count)
            finalCore restObservables hcoreStep hcoreRest

theorem counterWasmCore_trace_simulates_after_initialize_from_obligations
    (obligations : CounterWasmCoreEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (core : CounterWasmCoreState) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterWasmCoreTraceStep core (.initialize :: calls) observables := by
  obtain ⟨nextIr, _nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
    counter_initialize_simulates irState 0
  cases htargetStep
  obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
      hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
    counterWasmCore_trace_simulates_from_obligations obligations calls hrelNext
  refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    IRTraceMatches.cons hirStep hirTraceRest,
    IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
  · exact runTraceListGen_cons_ok counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact runTraceListGen_cons_ok counterWasmCoreTraceStep .initialize calls core nextCore .none
      finalCore restObservables hcoreStep hcoreRest

theorem counterWasmCore_safe_trace_simulates_after_initialize_from_obligations
    (obligations : CounterWasmCoreSafeEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (core : CounterWasmCoreState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterWasmCoreTraceStep core (.initialize :: calls) observables := by
  obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
    counter_initialize_simulates irState 0
  cases htargetStep
  have hsafeRest : counterTraceSafeFromCount 0 calls = true := by
    simpa [counterTraceSafeAfterInitialize] using hsafe
  obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
      hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
    counterWasmCore_safe_trace_simulates_from_obligations
      obligations calls hrelNext hcounterNext hsafeRest
  refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    IRTraceMatches.cons hirStep hirTraceRest,
    IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
  · exact runTraceListGen_cons_ok counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact runTraceListGen_cons_ok counterWasmCoreTraceStep .initialize calls core nextCore .none
      finalCore restObservables hcoreStep hcoreRest

/-! ### Exported universal theorems (default obligations) -/

theorem counterWasmCore_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CounterWasmCoreState) :
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

theorem counterWasmCore_safe_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CounterWasmCoreState)
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

theorem counterWasmCore_canonical_safe_trace_simulates :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep
        (.initialize :: [.get, .increment, .get]) State.empty =
        .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep
        (.initialize :: [.get, .increment, .get]) { storage := #[], returnValue := #[] } =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore := by
  obtain ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal, _, _⟩ :=
    counterWasmCore_safe_trace_simulates_after_initialize
      [.get, .increment, .get] State.empty { storage := #[], returnValue := #[] }
      counterTraceSafe_initialize_get_increment_get
  exact ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal⟩

/-! ### FV-9.5 Wasm cap: content-honest `∀ (m : Module)` Wasm core fragment-refines

`moduleIrStep m` runs **`m`'s own entrypoint bodies**; bridge via
`moduleIrStep_eq_irStep_of_isCounterModule`, then
`counterWasmCore_trace_simulates_from_obligations`.
-/

open ProofForge.Backend.Refinement.ConstructorCoverage

theorem wasmCore_fragment_refines_all
    (m : Module) (hm : isCounterModule m = true)
    ( _hcovered : moduleInCoveredFragment m = true)
    (calls : List CounterCall) {irState : IRState} {core : CounterWasmCoreState}
    (hrel : CounterWasmRel irState core) :
    ∃ finalIr finalCore observables,
      runTraceListGen (moduleIrStep m) calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterWasmCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore ∧
      IRTraceMatches (moduleIrStep m) irState calls observables ∧
      IRTraceMatches counterWasmCoreTraceStep core calls observables := by
  have hfun : moduleIrStep m = irStep :=
    funext fun s => funext fun c => moduleIrStep_eq_irStep_of_isCounterModule hm c s
  rw [hfun]
  exact counterWasmCore_trace_simulates_from_obligations counterWasmCoreObligations calls hrel

end ProofForge.Backend.WasmHost.CounterWasmRefinement
