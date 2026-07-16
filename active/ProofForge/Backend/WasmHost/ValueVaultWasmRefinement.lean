import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.WasmHost.ValueVaultWasmExec
import ProofForge.IR.StepSemantics
import ProofForge.IR.ValueVaultSemantics

/-! ## ValueVault IR ↔ Wasm core universal refinement (WASM-5 continuation).

Target step uses the abstract `valueVaultWasmCoreTraceStep` (six-slot storage).
IR reference is `ValueVaultSemantics.valueVaultIrStep`. Observables are aligned
via a small `coreObservable` map on the core's returned `Nat`.
-/

namespace ProofForge.Backend.WasmHost.ValueVaultWasmRefinement

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.StepSemantics
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.WasmHost.ValueVaultWasmExec

abbrev IRState := State
abbrev CoreState := ValueVaultWasmCoreState
abbrev Call := ProofForge.IR.ValueVaultSemantics.ValueVaultCall
open ProofForge.IR.ValueVaultSemantics (ValueVaultStateRel valueVaultIrStep valueVaultPreInitIr
  lookup_insert_other valueVaultStateRel_preInit valueVault_initialize_simulates
  valueVault_deposit_simulates valueVault_chargeFee_simulates valueVault_release_simulates
  valueVault_snapshot_simulates valueVault_getBalance_simulates valueVault_getNetValue_simulates)

def coreObservable (call : Call) (retNat : Nat) : ObservableReturn :=
  match call with
  | .initialize _ | .deposit _ | .chargeFee _ _ | .release _ => .none
  | .snapshot | .getBalance | .getNetValue => .u64 retNat

def valueVaultWasmTargetStep (core : CoreState) (call : Call) :
    Except String (CoreState × ObservableReturn) := do
  let (nextCore, retNat) ← valueVaultWasmCoreTraceStep core call
  .ok (nextCore, coreObservable call retNat)

def ValueVaultWasmRel (irState : IRState) (core : CoreState) : Prop :=
  ∃ balance released fees lastValue lastCheckpoint operations,
    ValueVaultStateRel irState balance released fees lastValue lastCheckpoint operations ∧
      core.storage = canonicalCoreStorage balance released fees lastValue lastCheckpoint operations ∧
      core.checkpoint = 0

theorem valueVaultWasm_step_simulates
    (call : Call) {irState : IRState} {core : CoreState}
    (hrel : ValueVaultWasmRel irState core) :
    ∃ nextIr nextCore observable,
      valueVaultIrStep irState call = .ok (nextIr, observable) ∧
      valueVaultWasmTargetStep core call = .ok (nextCore, observable) ∧
      ValueVaultWasmRel nextIr nextCore := by
  rcases hrel with ⟨balance, released, fees, lastValue, lastCheckpoint, operations, hstate, hstorage, hcp⟩
  have hb := valueVaultCoreScalar_balance_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  have hr := valueVaultCoreScalar_released_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  have hf := valueVaultCoreScalar_fees_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  have hlv := valueVaultCoreScalar_lastValue_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  have hlc := valueVaultCoreScalar_lastCheckpoint_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  have hop := valueVaultCoreScalar_operations_of_storage core balance released fees lastValue lastCheckpoint operations hstorage
  match call with
  | .initialize initial =>
      obtain ⟨nextIr, hir, hstateNext⟩ := valueVault_initialize_simulates hstate initial
      refine ⟨nextIr, { storage := canonicalCoreStorage initial 0 0 initial 0 1, returnValue := #[], checkpoint := 0 },
        .none, hir, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, coreObservable]
        rw [valueVaultCoreTraceStep_initialize]
        rfl
      · refine ⟨initial, 0, 0, initial, 0, 1, hstateNext, ?_, rfl⟩
        simp
  | .deposit amount =>
      obtain ⟨nextIr, hir, hstateNext⟩ := valueVault_deposit_simulates hstate (amount := amount)
      refine ⟨nextIr,
        { storage := canonicalCoreStorage (balance + amount) released fees amount lastCheckpoint (operations + 1),
          returnValue := #[], checkpoint := 0 },
        .none, hir, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hr, hf, hlc, hop, hcp]
        rfl
      · refine ⟨balance + amount, released, fees, amount, lastCheckpoint, operations + 1, hstateNext, ?_, rfl⟩
        simp
  | .chargeFee gross feeBps =>
      obtain ⟨nextIr, hir, hstateNext⟩ := valueVault_chargeFee_simulates hstate (gross := gross) (feeBps := feeBps)
      let fee := (gross * feeBps) / 10000
      let net := gross - fee
      refine ⟨nextIr,
        { storage := canonicalCoreStorage (balance + net) released (fees + fee) net lastCheckpoint (operations + 1),
          returnValue := #[], checkpoint := 0 },
        .none, hir, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hr, hf, hlc, hop, hcp]; rfl
      · refine ⟨balance + net, released, fees + fee, net, lastCheckpoint, operations + 1, hstateNext, ?_, rfl⟩
        simp
  | .release amount =>
      obtain ⟨nextIr, hir, hstateNext⟩ := valueVault_release_simulates hstate (amount := amount)
      refine ⟨nextIr,
        { storage := canonicalCoreStorage (balance - amount) (released + amount) fees amount lastCheckpoint (operations + 1),
          returnValue := #[], checkpoint := 0 },
        .none, hir, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hr, hf, hlc, hop, hcp]; rfl
      · refine ⟨balance - amount, released + amount, fees, amount, lastCheckpoint, operations + 1, hstateNext, ?_, rfl⟩
        simp
  | .snapshot =>
      obtain ⟨nextIr, hir, hstateNext⟩ := valueVault_snapshot_simulates hstate
      refine ⟨nextIr,
        { storage := canonicalCoreStorage balance released fees lastValue 0 operations,
          returnValue := #[], checkpoint := 0 },
        .u64 balance, hir, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hr, hf, hlv, hop, hcp]; rfl
      · refine ⟨balance, released, fees, lastValue, 0, operations, hstateNext, ?_, rfl⟩
        simp
  | .getBalance =>
      refine ⟨irState, core, .u64 balance, valueVault_getBalance_simulates hstate, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hcp]; rfl
      · refine ⟨balance, released, fees, lastValue, lastCheckpoint, operations, hstate, hstorage, hcp⟩
  | .getNetValue =>
      refine ⟨irState, core, .u64 (balance - fees), valueVault_getNetValue_simulates hstate, ?_, ?_⟩
      · dsimp [valueVaultWasmTargetStep, valueVaultWasmCoreTraceStep, coreObservable]
        simp only [hb, hf, hcp]; rfl
      · refine ⟨balance, released, fees, lastValue, lastCheckpoint, operations, hstate, hstorage, hcp⟩

theorem valueVaultWasm_trace_simulates
    (calls : List Call) {irState : IRState} {core : CoreState}
    (hrel : ValueVaultWasmRel irState core) :
    ∃ finalIr finalCore observables,
      runTraceListGen valueVaultIrStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen valueVaultWasmTargetStep calls core = .ok (finalCore, observables) ∧
      ValueVaultWasmRel finalIr finalCore ∧
      IRTraceMatches valueVaultIrStep irState calls observables ∧
      IRTraceMatches valueVaultWasmTargetStep core calls observables :=
  traceSimulation_lift valueVaultIrStep valueVaultWasmTargetStep ValueVaultWasmRel
    (fun call {_irState} {_targetState} hrel' =>
      valueVaultWasm_step_simulates call hrel')
    calls hrel

def postInitIr : IRState :=
  State.empty
    |>.write "balance" (.u64 10)
    |>.write "released" (.u64 0)
    |>.write "fees" (.u64 0)
    |>.write "last_value" (.u64 10)
    |>.write "last_checkpoint" (.u64 0)
    |>.write "operations" (.u64 1)

def postInitCore : CoreState :=
  { storage := canonicalCoreStorage 10 0 0 10 0 1, returnValue := #[], checkpoint := 0 }

def zeroedCore : CoreState :=
  { storage := canonicalCoreStorage 0 0 0 0 0 0, returnValue := #[], checkpoint := 0 }

theorem valueVaultWasmRel_preInit :
    ValueVaultWasmRel valueVaultPreInitIr zeroedCore :=
  ⟨0, 0, 0, 0, 0, 0, valueVaultStateRel_preInit, rfl, rfl⟩

/-- From pre-init-shaped state: `initialize initial` then any tail `calls`. -/
theorem valueVaultWasm_trace_simulates_after_initialize
    (initial : Nat) (calls : List Call) :
    ∃ finalIr finalCore observables,
      runTraceListGen valueVaultIrStep (.initialize initial :: calls) valueVaultPreInitIr =
        .ok (finalIr, observables) ∧
      runTraceListGen valueVaultWasmTargetStep (.initialize initial :: calls) zeroedCore =
        .ok (finalCore, observables) ∧
      ValueVaultWasmRel finalIr finalCore ∧
      IRTraceMatches valueVaultIrStep valueVaultPreInitIr (.initialize initial :: calls) observables ∧
      IRTraceMatches valueVaultWasmTargetStep zeroedCore (.initialize initial :: calls) observables := by
  obtain ⟨nextIr', nextCore', obsInit, hirStep, hcoreStep, hrelNext⟩ :=
    valueVaultWasm_step_simulates (.initialize initial) valueVaultWasmRel_preInit
  obtain ⟨finalIr, finalCore, restObservables, hirRest, hcoreRest,
      hrelFinal, hirTraceRest, hcoreTraceRest⟩ :=
    valueVaultWasm_trace_simulates calls hrelNext
  refine ⟨finalIr, finalCore, #[obsInit] ++ restObservables, ?_, ?_,
    hrelFinal,
    IRTraceMatches.cons hirStep hirTraceRest,
    IRTraceMatches.cons hcoreStep hcoreTraceRest⟩
  · exact runTraceListGen_cons_ok valueVaultIrStep (.initialize initial) calls valueVaultPreInitIr nextIr' obsInit
      finalIr restObservables hirStep hirRest
  · exact runTraceListGen_cons_ok valueVaultWasmTargetStep (.initialize initial) calls zeroedCore nextCore' obsInit
      finalCore restObservables hcoreStep hcoreRest

def canonicalTailCalls : List Call := [.deposit 5, .getNetValue]

def canonicalFullCalls : List Call := [.initialize 10, .deposit 5, .getNetValue]

/-- Portable anchor: `initialize 10` → `deposit 5` → `getNetValue` from pre-init IR + zeroed core. -/
theorem valueVaultWasm_canonical_full_trace_simulates :
    ∃ finalIr finalCore observables,
      runTraceListGen valueVaultIrStep canonicalFullCalls valueVaultPreInitIr =
        .ok (finalIr, observables) ∧
      runTraceListGen valueVaultWasmTargetStep canonicalFullCalls zeroedCore =
        .ok (finalCore, observables) ∧
      ValueVaultWasmRel finalIr finalCore := by
  obtain ⟨finalIr, finalCore, observables, hir, hcore, hrel, _, _⟩ :=
    valueVaultWasm_trace_simulates_after_initialize 10 [.deposit 5, .getNetValue]
  exact ⟨finalIr, finalCore, observables, hir, hcore, hrel⟩

/-- After init-shaped state: `deposit 5` then `getNetValue`. -/
theorem valueVaultWasm_canonical_tail_trace_simulates :
    ∃ finalIr finalCore observables,
      runTraceListGen valueVaultIrStep canonicalTailCalls postInitIr =
        .ok (finalIr, observables) ∧
      runTraceListGen valueVaultWasmTargetStep canonicalTailCalls postInitCore =
        .ok (finalCore, observables) ∧
      ValueVaultWasmRel finalIr finalCore := by
  have hstate : ValueVaultStateRel postInitIr 10 0 0 10 0 1 := by
    constructor
    · simp [postInitIr, State.read, State.write, lookup_insert_other, lookup_insert_same, State.empty]
    · simp [postInitIr, State.read, State.write, lookup_insert_other, lookup_insert_same, State.empty]
    · simp [postInitIr, State.read, State.write, lookup_insert_other, lookup_insert_same, State.empty]
    · simp [postInitIr, State.read, State.write, lookup_insert_other, lookup_insert_same, State.empty]
    · simp [postInitIr, State.read, State.write, lookup_insert_other, lookup_insert_same, State.empty]
    · simp [postInitIr, State.read, State.write, lookup_insert_same, State.empty]
  obtain ⟨finalIr, finalCore, observables, hir, hcore, hrel, _, _⟩ :=
    valueVaultWasm_trace_simulates canonicalTailCalls
      (irState := postInitIr) (core := postInitCore)
      ⟨10, 0, 0, 10, 0, 1, hstate, rfl, rfl⟩
  exact ⟨finalIr, finalCore, observables, hir, hcore, hrel⟩

end ProofForge.Backend.WasmHost.ValueVaultWasmRefinement