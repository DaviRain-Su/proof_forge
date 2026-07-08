import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.Solana.CounterSbpfExec
import ProofForge.IR.CounterSemantics
import ProofForge.IR.StepSemantics

/-!
Counter IR ↔ sBPF core-tail universal refinement (SOL-3).

Bridges the IR reference semantics to the composed `CounterSbpfExec` core programs
via the shared `traceSimulation_lift` induction. Per-entrypoint simulation is proved
from `SbpfExec` composition lemmas, not `native_decide` on the full lowered program.

The existing `ProofForge.Backend.Solana.Refinement` `native_decide` obligations remain
as regression smoke for the full interpreter path. This module is frozen: generic
work belongs in `SbpfExec.lean`; keep this file only for `just solana-counter-sbpf-regression`.
-/

namespace ProofForge.Backend.Solana.CounterSbpfRefinement

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.CounterSemantics
open ProofForge.IR.StepSemantics
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.CounterSbpfExec

abbrev IRState := ProofForge.IR.Semantics.State
abbrev CounterCall := ProofForge.Backend.Refinement.CounterUniversal.CounterCall
abbrev counterIRStep := ProofForge.Backend.Refinement.CounterUniversal.irStep

def counterU64Modulus : Nat := 2 ^ 64

structure CounterCoreState where
  memory : Memory := #[]
  returnData : Option Nat := none
  deriving Inhabited

def counterModule := ProofForge.IR.Examples.Counter.module

theorem countOff_module_layout :
    stateFieldOffset? counterModule "count" = some countOff := by
  simpa [counterModule] using countOff_matches_layout

theorem CounterStateRel_iff {state : IRState} {count : Nat} :
    CounterStateRel state count ↔ state.read "count" = some (.u64 count) := by
  unfold CounterStateRel
  rfl

/-- IR `count` scalar ↔ account-data word at the layout offset. -/
def CounterSbpfRel (irState : IRState) (core : CounterCoreState) : Prop :=
  ∃ count, CounterStateRel irState count ∧ core.memory.read countOff = count

def CounterSbpfRelOptional (irState : IRState) (core : CounterCoreState) : Prop :=
  RMemoryOptional counterModule "count" irState core.memory = true

theorem irU64State?_write_count (state : IRState) (count : Nat) :
    irU64State? (state.write "count" (.u64 count)) "count" = some count := by
  unfold irU64State?
  simp [State.read, State.write, lookup_insert_same]

theorem RMemoryOptional_write_count (memory : Memory) (count : Nat) (irState : IRState) :
    RMemoryOptional counterModule "count"
      (irState.write "count" (.u64 count))
      (memory.write countOff count) = true := by
  unfold RMemoryOptional
  rw [countOff_module_layout]
  simp [Memory.read?, Memory.write, irU64State?_write_count, Memory.find?_write]

theorem counterSbpfRel_write_count (memory : Memory) (count : Nat) (irState : IRState) :
    CounterSbpfRel (irState.write "count" (.u64 count))
      { memory := memory.write countOff count } := by
  refine ⟨count, counter_state_rel_write_count irState count, ?_⟩
  exact Memory.read_write memory countOff count

theorem counterSbpfRel_after_initialize (irState : IRState) (core : CounterCoreState) :
    CounterSbpfRel (irState.write "count" (.u64 0))
      { core with memory := core.memory.write countOff 0 } := by
  exact counterSbpfRel_write_count core.memory 0 irState

theorem counterSbpfRel_optional_write_count (memory : Memory) (count : Nat) (irState : IRState) :
    CounterSbpfRelOptional (irState.write "count" (.u64 count))
      { memory := memory.write countOff count } := by
  unfold CounterSbpfRelOptional
  exact RMemoryOptional_write_count memory count irState

theorem counterSbpfRel_left_counterStateRel {irState : IRState} {core : CounterCoreState}
    (hrel : CounterSbpfRel irState core) :
    ∃ count, CounterStateRel irState count := by
  rcases hrel with ⟨count, hcounter, _⟩
  exact ⟨count, hcounter⟩

def counterSbpfCoreTraceStep (core : CounterCoreState) (call : CounterCall) :
    Except String (CounterCoreState × ObservableReturn) :=
  match call with
  | .initialize =>
      .ok ({ memory := core.memory.write countOff 0, returnData := none }, .none)
  | .increment =>
      let count := core.memory.read countOff
      .ok ({ memory := core.memory.write countOff (count + 1), returnData := none }, .none)
  | .get =>
      let count := core.memory.read countOff
      .ok ({ memory := core.memory, returnData := some count }, .u64 count)

/-! ### Overflow-safe trace predicate (FV-5 Solana boundary) -/

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

structure CounterSbpfCoreEntrypointObligations where
  initialize_simulates :
    ∀ {irState core nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore
  increment_simulates :
    ∀ {irState core nextIr observable},
      CounterSbpfRel irState core →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .increment = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore
  get_simulates :
    ∀ {irState core nextIr observable},
      CounterSbpfRel irState core →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .get = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore

structure CounterSbpfCoreSafeEntrypointObligations where
  initialize_simulates :
    ∀ {irState core nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore
  increment_simulates :
    ∀ {irState core nextIr observable},
      CounterSbpfRel irState core →
      CounterStepSafe .increment irState →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .increment = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore
  get_simulates :
    ∀ {irState core nextIr observable},
      CounterSbpfRel irState core →
      CounterStepSafe .get irState →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextCore,
          counterSbpfCoreTraceStep core .get = .ok (nextCore, observable) ∧
          CounterSbpfRel nextIr nextCore

theorem counterSbpfCore_initialize_simulates
    {irState core nextIr observable}
    (hirStep : counterIRStep irState .initialize = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterSbpfCoreTraceStep core .initialize = .ok (nextCore, observable) ∧
      CounterSbpfRel nextIr nextCore := by
  refine ⟨{ memory := core.memory.write countOff 0, returnData := none }, ?_, ?_⟩
  · simp [counterSbpfCoreTraceStep]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [initialize_total_ok] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [initialize_total_ok] at hirStep
    cases hirStep
    exact counterSbpfRel_after_initialize irState core

theorem counterSbpfCore_increment_simulates
    {irState core nextIr observable}
    (hrel : CounterSbpfRel irState core)
    (hirStep : counterIRStep irState .increment = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterSbpfCoreTraceStep core .increment = .ok (nextCore, observable) ∧
      CounterSbpfRel nextIr nextCore := by
  rcases hrel with ⟨count, hcounter, hmem⟩
  refine ⟨{ memory := core.memory.write countOff (count + 1), returnData := none }, ?_, ?_⟩
  · simp [counterSbpfCoreTraceStep, hmem]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [increment_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [increment_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    exact counterSbpfRel_write_count core.memory (count + 1) irState

theorem counterSbpfCore_get_simulates
    {irState core nextIr observable}
    (hrel : CounterSbpfRel irState core)
    (hirStep : counterIRStep irState .get = .ok (nextIr, observable)) :
    ∃ nextCore,
      counterSbpfCoreTraceStep core .get = .ok (nextCore, observable) ∧
      CounterSbpfRel nextIr nextCore := by
  rcases hrel with ⟨count, hcounter, hmem⟩
  refine ⟨{ memory := core.memory, returnData := some count }, ?_, ?_⟩
  · simp [counterSbpfCoreTraceStep, hmem]
    unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [get_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    rfl
  · unfold counterIRStep irStep CounterCall.entrypoint at hirStep
    rw [get_total_ok_of_count (CounterStateRel_iff.mp hcounter)] at hirStep
    cases hirStep
    exact ⟨count, hcounter, hmem⟩

def counterSbpfCoreObligations : CounterSbpfCoreEntrypointObligations where
  initialize_simulates := fun {_irState} {_core} {_nextIr} {_observable} hirStep =>
    counterSbpfCore_initialize_simulates hirStep
  increment_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel hirStep =>
    counterSbpfCore_increment_simulates hrel hirStep
  get_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel hirStep =>
    counterSbpfCore_get_simulates hrel hirStep

def counterSbpfCoreSafeObligations : CounterSbpfCoreSafeEntrypointObligations where
  initialize_simulates := fun {_irState} {_core} {_nextIr} {_observable} hirStep =>
    counterSbpfCore_initialize_simulates hirStep
  increment_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel _hsafe hirStep =>
    counterSbpfCore_increment_simulates hrel hirStep
  get_simulates := fun {_irState} {_core} {_nextIr} {_observable} hrel _hsafe hirStep =>
    counterSbpfCore_get_simulates hrel hirStep

theorem counterSbpfCore_step_simulates_from_obligations
    (obligations : CounterSbpfCoreEntrypointObligations)
    (call : CounterCall) {irState : IRState} {core : CounterCoreState}
    (hrel : CounterSbpfRel irState core) :
    ∃ nextIr nextCore observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterSbpfCoreTraceStep core call = .ok (nextCore, observable) ∧
      CounterSbpfRel nextIr nextCore := by
  obtain ⟨count, hcounter⟩ := counterSbpfRel_left_counterStateRel hrel
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

theorem counterSbpfCore_safe_step_simulates_from_obligations
    (obligations : CounterSbpfCoreSafeEntrypointObligations)
    (call : CounterCall) {irState : IRState} {core : CounterCoreState}
    (hrel : CounterSbpfRel irState core)
    (hsafe : CounterStepSafe call irState) :
    ∃ nextIr nextCore observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterSbpfCoreTraceStep core call = .ok (nextCore, observable) ∧
      CounterSbpfRel nextIr nextCore := by
  obtain ⟨count, hcounter⟩ := counterSbpfRel_left_counterStateRel hrel
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

theorem counterSbpfCore_trace_simulates_from_obligations
    (obligations : CounterSbpfCoreEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {core : CounterCoreState}
    (hrel : CounterSbpfRel irState core) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState calls observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core calls observables :=
  traceSimulation_lift counterIRStep counterSbpfCoreTraceStep CounterSbpfRel
    (fun call {_irState} {_targetState} hrel' =>
      counterSbpfCore_step_simulates_from_obligations obligations call hrel')
    calls hrel

theorem counterSbpfCore_safe_trace_simulates_from_obligations
    (obligations : CounterSbpfCoreSafeEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {core : CounterCoreState}
    {count : Nat}
    (hrel : CounterSbpfRel irState core)
    (hcounter : CounterStateRel irState count)
    (hsafe : counterTraceSafeFromCount count calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep calls core = .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState calls observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core calls observables := by
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
        · exact runTraceListGen_cons_ok counterSbpfCoreTraceStep .initialize rest core nextCore .none
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
        · exact runTraceListGen_cons_ok counterSbpfCoreTraceStep .increment rest core nextCore .none
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
        · exact runTraceListGen_cons_ok counterSbpfCoreTraceStep .get rest core nextCore (.u64 count)
            finalCore restObservables hcoreStep hcoreRest

theorem counterSbpfCore_trace_simulates_after_initialize_from_obligations
    (obligations : CounterSbpfCoreEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (core : CounterCoreState) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core (.initialize :: calls) observables := by
  obtain ⟨nextIr, _nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
    counter_initialize_simulates irState 0
  cases htargetStep
  obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
      hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
    counterSbpfCore_trace_simulates_from_obligations obligations calls hrelNext
  refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    IRTraceMatches.cons hirStep hirTraceRest,
    IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
  · exact runTraceListGen_cons_ok counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact runTraceListGen_cons_ok counterSbpfCoreTraceStep .initialize calls core nextCore .none
      finalCore restObservables hcoreStep hcoreRest

theorem counterSbpfCore_safe_trace_simulates_after_initialize_from_obligations
    (obligations : CounterSbpfCoreSafeEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (core : CounterCoreState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core (.initialize :: calls) observables := by
  obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
    counter_initialize_simulates irState 0
  cases htargetStep
  have hsafeRest : counterTraceSafeFromCount 0 calls = true := by
    simpa [counterTraceSafeAfterInitialize] using hsafe
  obtain ⟨nextCore, hcoreStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
      hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
    counterSbpfCore_safe_trace_simulates_from_obligations
      obligations calls hrelNext hcounterNext hsafeRest
  refine ⟨finalIr, finalCore, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    IRTraceMatches.cons hirStep hirTraceRest,
    IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
  · exact runTraceListGen_cons_ok counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact runTraceListGen_cons_ok counterSbpfCoreTraceStep .initialize calls core nextCore .none
      finalCore restObservables hcoreStep hcoreRest

/-! ### Exported universal theorems (default obligations) -/

theorem counterSbpfCore_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CounterCoreState) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core (.initialize :: calls) observables :=
  counterSbpfCore_trace_simulates_after_initialize_from_obligations
    counterSbpfCoreObligations calls irState core

theorem counterSbpfCore_safe_trace_simulates_after_initialize
    (calls : List CounterCall) (irState : IRState) (core : CounterCoreState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep (.initialize :: calls) core =
        .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore ∧
      IRTraceMatches counterIRStep irState (.initialize :: calls) observables ∧
      IRTraceMatches counterSbpfCoreTraceStep core (.initialize :: calls) observables :=
  counterSbpfCore_safe_trace_simulates_after_initialize_from_obligations
    counterSbpfCoreSafeObligations calls irState core hsafe

theorem counterSbpfCore_canonical_safe_trace_simulates :
    ∃ finalIr finalCore observables,
      runTraceListGen counterIRStep
        (.initialize :: [.get, .increment, .get]) State.empty =
        .ok (finalIr, observables) ∧
      runTraceListGen counterSbpfCoreTraceStep
        (.initialize :: [.get, .increment, .get]) { memory := #[] } =
        .ok (finalCore, observables) ∧
      CounterSbpfRel finalIr finalCore := by
  obtain ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal, _, _⟩ :=
    counterSbpfCore_safe_trace_simulates_after_initialize
      [.get, .increment, .get] State.empty { memory := #[] }
      counterTraceSafe_initialize_get_increment_get
  exact ⟨finalIr, finalCore, observables, hirTrace, hcoreTrace, hrelFinal⟩

end ProofForge.Backend.Solana.CounterSbpfRefinement