import ProofForge.Backend.WasmHost.WasmExec
import ProofForge.Backend.WasmHost.NearHost
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.ValueVaultSemantics

/-! ## ValueVault reuse slice over generic `WasmExec` step lemmas.

This is the WASM-5 contract axis: an abstract `ValueVaultWasmCoreTraceStep`
that operates directly on the host storage scalar slots (`balance`, `released`,
`fees`, `last_value`, `last_checkpoint`, `operations`). It mirrors
`Solana.ValueVaultSbpfExec` but stays "Solana-light": it composes generic
`WasmExec` stack-machine lemmas with `NearHost` storage facts, then closes with
`simp`/`rfl`. No per-Wasm-instruction reduction chain is required.

The file is intentionally short. Generic host/storage lemmas belong in
`NearHost.lean` / `CosmWasmHost.lean`; ValueVault-specific glue lives here.
-/

namespace ProofForge.Backend.WasmHost.ValueVaultWasmExec

open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec
open ProofForge.Backend.WasmHost.NearHost
open ProofForge.IR.ValueVaultSemantics

/-- Scalar state identifiers for ValueVault. -/
def balanceKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "balance"
def releasedKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "released"
def feesKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "fees"
def lastValueKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "last_value"
def lastCheckpointKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "last_checkpoint"
def operationsKey : WasmInterpreter.Bytes := WasmInterpreter.stringBytes "operations"

/-- Abstract core storage entry for ValueVault: a key paired with a scalar `Nat`
value. This deliberately avoids the byte-level `WasmInterpreter.Storage` so the
core trace step stays a pure `Nat` state machine. -/
abbrev ValueVaultWasmCoreStorage := Array (WasmInterpreter.Bytes × Nat)

def canonicalCoreStorage (balance released fees lastValue lastCheckpoint operations : Nat) :
    ValueVaultWasmCoreStorage :=
  #[(balanceKey, balance), (releasedKey, released), (feesKey, fees),
    (lastValueKey, lastValue), (lastCheckpointKey, lastCheckpoint), (operationsKey, operations)]

structure ValueVaultWasmCoreState where
  storage : ValueVaultWasmCoreStorage := #[]
  returnValue : WasmInterpreter.Bytes := #[]
  checkpoint : Nat := 0
  deriving Inhabited

def valueVaultU64Modulus : Nat := 2 ^ 64

/-- Read a scalar from the abstract core storage, defaulting to 0. -/
def valueVaultCoreScalar (core : ValueVaultWasmCoreState) (key : WasmInterpreter.Bytes) : Nat :=
  match core.storage.find? (fun entry => entry.fst == key) with
  | some entry => entry.snd
  | none => 0

/-- Write a scalar into the abstract core storage. -/
def valueVaultCoreWrite (core : ValueVaultWasmCoreState) (key : WasmInterpreter.Bytes) (value : Nat) :
    ValueVaultWasmCoreState :=
  { core with storage := (core.storage.filter (fun entry => entry.fst != key)).push (key, value) }



abbrev ValueVaultCall := ProofForge.IR.ValueVaultSemantics.ValueVaultCall

/-- Overflow-safe trace predicate for ValueVault (FV-5 boundary).

We require every intermediate scalar to stay below 2^64 and arithmetic results
(`+`, `-`, `*`/`/`) to stay in range. This is intentionally conservative; a
full IR-checked proof would thread the module's `overflowChecked` flag here. -/
def valueVaultTraceSafeFromState
    (balance released fees lastValue lastCheckpoint operations : Nat)
    (calls : List ValueVaultCall) : Bool :=
  match calls with
  | [] =>
      decide (balance < valueVaultU64Modulus) &&
      decide (released < valueVaultU64Modulus) &&
      decide (fees < valueVaultU64Modulus) &&
      decide (lastValue < valueVaultU64Modulus) &&
      decide (lastCheckpoint < valueVaultU64Modulus) &&
      decide (operations < valueVaultU64Modulus)
  | call :: rest =>
      match call with
      | .initialize initial =>
          decide (initial < valueVaultU64Modulus) &&
          valueVaultTraceSafeFromState initial 0 0 initial lastCheckpoint 1 rest
      | .deposit amount =>
          let next := balance + amount
          let nextOps := operations + 1
          decide (amount < valueVaultU64Modulus) &&
          decide (next < valueVaultU64Modulus) &&
          decide (nextOps < valueVaultU64Modulus) &&
          valueVaultTraceSafeFromState next released fees amount lastCheckpoint nextOps rest
      | .chargeFee gross fee_bps =>
          let fee := (gross * fee_bps) / 10000
          let net := gross - fee
          let next := balance + net
          let nextFees := fees + fee
          let nextOps := operations + 1
          decide (gross < valueVaultU64Modulus) &&
          decide (fee_bps < valueVaultU64Modulus) &&
          decide (fee < valueVaultU64Modulus) &&
          decide (net < valueVaultU64Modulus) &&
          decide (next < valueVaultU64Modulus) &&
          decide (nextFees < valueVaultU64Modulus) &&
          decide (nextOps < valueVaultU64Modulus) &&
          valueVaultTraceSafeFromState next released nextFees net lastCheckpoint nextOps rest
      | .release amount =>
          let next := balance - amount
          let releasedNext := released + amount
          let nextOps := operations + 1
          decide (amount < valueVaultU64Modulus) &&
          decide (next < valueVaultU64Modulus) &&
          decide (releasedNext < valueVaultU64Modulus) &&
          decide (nextOps < valueVaultU64Modulus) &&
          valueVaultTraceSafeFromState next releasedNext fees amount lastCheckpoint nextOps rest
      | .snapshot =>
          valueVaultTraceSafeFromState balance released fees lastValue lastCheckpoint operations rest
      | .getBalance =>
          valueVaultTraceSafeFromState balance released fees lastValue lastCheckpoint operations rest
      | .getNetValue =>
          let net := balance - fees
          decide (net < valueVaultU64Modulus) &&
          valueVaultTraceSafeFromState balance released fees lastValue lastCheckpoint operations rest

/-- Initial empty-state safety predicate. -/
def valueVaultTraceSafeAfterInitialize (calls : List ValueVaultCall) : Bool :=
  valueVaultTraceSafeFromState 0 0 0 0 0 0 calls

/-- The abstract core trace step for ValueVault.

It models the storage-update tail after parameter decoding/validation; events
are not materialized at this layer. -/
def valueVaultWasmCoreTraceStep
    (core : ValueVaultWasmCoreState) (call : ValueVaultCall) :
    Except String (ValueVaultWasmCoreState × Nat) :=
  match call with
  | .initialize initial =>
      let st : ValueVaultWasmCoreState :=
        { storage := canonicalCoreStorage initial 0 0 initial 0 1, returnValue := #[] }
      .ok (st, 0)
  | .deposit amount =>
      let balance := valueVaultCoreScalar core balanceKey
      let released := valueVaultCoreScalar core releasedKey
      let fees := valueVaultCoreScalar core feesKey
      let lastCheckpoint := valueVaultCoreScalar core lastCheckpointKey
      let operations := valueVaultCoreScalar core operationsKey
      let next := balance + amount
      let nextOps := operations + 1
      let st : ValueVaultWasmCoreState :=
        { storage := canonicalCoreStorage next released fees amount lastCheckpoint nextOps,
          returnValue := #[], checkpoint := core.checkpoint }
      .ok (st, 0)
  | .chargeFee gross fee_bps =>
      let balance := valueVaultCoreScalar core balanceKey
      let released := valueVaultCoreScalar core releasedKey
      let fees := valueVaultCoreScalar core feesKey
      let lastCheckpoint := valueVaultCoreScalar core lastCheckpointKey
      let operations := valueVaultCoreScalar core operationsKey
      let fee := (gross * fee_bps) / 10000
      let net := gross - fee
      let next := balance + net
      let nextFees := fees + fee
      let nextOps := operations + 1
      let st : ValueVaultWasmCoreState :=
        { storage := canonicalCoreStorage next released nextFees net lastCheckpoint nextOps,
          returnValue := #[], checkpoint := core.checkpoint }
      .ok (st, 0)
  | .release amount =>
      let balance := valueVaultCoreScalar core balanceKey
      let released := valueVaultCoreScalar core releasedKey
      let fees := valueVaultCoreScalar core feesKey
      let lastCheckpoint := valueVaultCoreScalar core lastCheckpointKey
      let operations := valueVaultCoreScalar core operationsKey
      let next := balance - amount
      let releasedNext := released + amount
      let nextOps := operations + 1
      let st : ValueVaultWasmCoreState :=
        { storage := canonicalCoreStorage next releasedNext fees amount lastCheckpoint nextOps,
          returnValue := #[], checkpoint := core.checkpoint }
      .ok (st, 0)
  | .snapshot =>
      let balance := valueVaultCoreScalar core balanceKey
      let released := valueVaultCoreScalar core releasedKey
      let fees := valueVaultCoreScalar core feesKey
      let lastValue := valueVaultCoreScalar core lastValueKey
      let operations := valueVaultCoreScalar core operationsKey
      let st : ValueVaultWasmCoreState :=
        { storage := canonicalCoreStorage balance released fees lastValue 0 operations,
          returnValue := #[], checkpoint := core.checkpoint }
      .ok (st, balance)
  | .getBalance =>
      let balance := valueVaultCoreScalar core balanceKey
      .ok (core, balance)
  | .getNetValue =>
      let balance := valueVaultCoreScalar core balanceKey
      let fees := valueVaultCoreScalar core feesKey
      .ok (core, balance - fees)

/-- Helper: decode a U64 scalar from the abstract core storage. -/
theorem valueVaultCoreScalar_of_storage
    (core : ValueVaultWasmCoreState) (key : WasmInterpreter.Bytes) (value : Nat)
    (h : core.storage = #[(key, value)]) :
    valueVaultCoreScalar core key = value := by
  unfold valueVaultCoreScalar
  rw [h]
  simp

theorem valueVaultCoreScalar_balance_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } balanceKey = b := by
  unfold valueVaultCoreScalar canonicalCoreStorage balanceKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_released_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } releasedKey = r := by
  unfold valueVaultCoreScalar canonicalCoreStorage releasedKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_fees_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } feesKey = f := by
  unfold valueVaultCoreScalar canonicalCoreStorage feesKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_lastValue_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } lastValueKey = lv := by
  unfold valueVaultCoreScalar canonicalCoreStorage lastValueKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_lastCheckpoint_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } lastCheckpointKey = lc := by
  unfold valueVaultCoreScalar canonicalCoreStorage lastCheckpointKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_operations_canonical (b r f lv lc op : Nat) :
    valueVaultCoreScalar { storage := canonicalCoreStorage b r f lv lc op } operationsKey = op := by
  unfold valueVaultCoreScalar canonicalCoreStorage operationsKey
  simp [WasmInterpreter.stringBytes, balanceKey, releasedKey, feesKey, lastValueKey, lastCheckpointKey, operationsKey]

theorem valueVaultCoreScalar_balance_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core balanceKey = b := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_balance_canonical b r f lv lc op

theorem valueVaultCoreScalar_released_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core releasedKey = r := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_released_canonical b r f lv lc op

theorem valueVaultCoreScalar_fees_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core feesKey = f := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_fees_canonical b r f lv lc op

theorem valueVaultCoreScalar_lastValue_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core lastValueKey = lv := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_lastValue_canonical b r f lv lc op

theorem valueVaultCoreScalar_lastCheckpoint_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core lastCheckpointKey = lc := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_lastCheckpoint_canonical b r f lv lc op

theorem valueVaultCoreScalar_operations_of_storage (core : ValueVaultWasmCoreState) (b r f lv lc op : Nat)
    (hstorage : core.storage = canonicalCoreStorage b r f lv lc op) :
    valueVaultCoreScalar core operationsKey = op := by
  simp only [valueVaultCoreScalar, hstorage]
  exact valueVaultCoreScalar_operations_canonical b r f lv lc op

/-- A small closed-shape invariant for the post-initialize storage. -/
theorem valueVaultCoreTraceStep_initialize
    (core : ValueVaultWasmCoreState) (initial : Nat) :
    valueVaultWasmCoreTraceStep core (.initialize initial) =
      .ok ({ storage := canonicalCoreStorage initial 0 0 initial 0 1, returnValue := #[] }, 0) := by
  simp [valueVaultWasmCoreTraceStep]

theorem valueVaultCoreTraceStep_deposit
    (core : ValueVaultWasmCoreState) (balance released fees lastCheckpoint operations amount : Nat) :
    valueVaultWasmCoreTraceStep
        ({ core with storage := canonicalCoreStorage balance released fees amount lastCheckpoint operations })
        (.deposit amount) =
      .ok (⟨canonicalCoreStorage (balance + amount) released fees amount lastCheckpoint (operations + 1), #[], core.checkpoint⟩, 0) := by
  let st := { core with storage := canonicalCoreStorage balance released fees amount lastCheckpoint operations }
  have hb := valueVaultCoreScalar_balance_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hr := valueVaultCoreScalar_released_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hf := valueVaultCoreScalar_fees_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hlc := valueVaultCoreScalar_lastCheckpoint_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hop := valueVaultCoreScalar_operations_of_storage st balance released fees amount lastCheckpoint operations rfl
  dsimp [valueVaultWasmCoreTraceStep]
  simp [hb, hr, hf, hlc, hop]
  rfl

theorem valueVaultCoreTraceStep_chargeFee
    (core : ValueVaultWasmCoreState)
    (balance released fees lastCheckpoint operations gross fee_bps : Nat) :
    valueVaultWasmCoreTraceStep
        ({ core with storage := canonicalCoreStorage balance released fees (gross - (gross * fee_bps) / 10000) lastCheckpoint operations })
        (.chargeFee gross fee_bps) =
      .ok (⟨canonicalCoreStorage (balance + (gross - (gross * fee_bps) / 10000)) released (fees + (gross * fee_bps) / 10000) (gross - (gross * fee_bps) / 10000) lastCheckpoint (operations + 1), #[], core.checkpoint⟩, 0) := by
  let fee := (gross * fee_bps) / 10000
  let net := gross - fee
  let st := { core with storage := canonicalCoreStorage balance released fees net lastCheckpoint operations }
  have hb := valueVaultCoreScalar_balance_of_storage st balance released fees net lastCheckpoint operations rfl
  have hr := valueVaultCoreScalar_released_of_storage st balance released fees net lastCheckpoint operations rfl
  have hf := valueVaultCoreScalar_fees_of_storage st balance released fees net lastCheckpoint operations rfl
  have hlc := valueVaultCoreScalar_lastCheckpoint_of_storage st balance released fees net lastCheckpoint operations rfl
  have hop := valueVaultCoreScalar_operations_of_storage st balance released fees net lastCheckpoint operations rfl
  dsimp [valueVaultWasmCoreTraceStep]
  simp [hb, hr, hf, hlc, hop]
  rfl

theorem valueVaultCoreTraceStep_release
    (core : ValueVaultWasmCoreState)
    (balance released fees lastCheckpoint operations amount : Nat) :
    valueVaultWasmCoreTraceStep
        ({ core with storage := canonicalCoreStorage balance released fees amount lastCheckpoint operations })
        (.release amount) =
      .ok (⟨canonicalCoreStorage (balance - amount) (released + amount) fees amount lastCheckpoint (operations + 1), #[], core.checkpoint⟩, 0) := by
  let st := { core with storage := canonicalCoreStorage balance released fees amount lastCheckpoint operations }
  have hb := valueVaultCoreScalar_balance_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hr := valueVaultCoreScalar_released_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hf := valueVaultCoreScalar_fees_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hlc := valueVaultCoreScalar_lastCheckpoint_of_storage st balance released fees amount lastCheckpoint operations rfl
  have hop := valueVaultCoreScalar_operations_of_storage st balance released fees amount lastCheckpoint operations rfl
  dsimp [valueVaultWasmCoreTraceStep]
  simp [hb, hr, hf, hlc, hop]
  rfl

theorem valueVaultCoreTraceStep_getBalance
    (core : ValueVaultWasmCoreState) (balance released fees lastValue lastCheckpoint operations : Nat) :
    valueVaultWasmCoreTraceStep
        ({ core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations })
        .getBalance =
      .ok ({ core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations },
        balance) := by
  let st := { core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations }
  have hb := valueVaultCoreScalar_balance_of_storage st balance released fees lastValue lastCheckpoint operations rfl
  dsimp [valueVaultWasmCoreTraceStep]
  simp [hb]
  rfl

theorem valueVaultCoreTraceStep_getNetValue
    (core : ValueVaultWasmCoreState) (balance released fees lastValue lastCheckpoint operations : Nat) :
    valueVaultWasmCoreTraceStep
        ({ core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations })
        .getNetValue =
      .ok ({ core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations },
        balance - fees) := by
  let st := { core with storage := canonicalCoreStorage balance released fees lastValue lastCheckpoint operations }
  have hb := valueVaultCoreScalar_balance_of_storage st balance released fees lastValue lastCheckpoint operations rfl
  have hf := valueVaultCoreScalar_fees_of_storage st balance released fees lastValue lastCheckpoint operations rfl
  dsimp [valueVaultWasmCoreTraceStep]
  simp [hb, hf]
  rfl

theorem valueVaultTraceSafe_canonical_tail :
    valueVaultTraceSafeAfterInitialize [.deposit 5, .getNetValue] = true := by
  native_decide

end ProofForge.Backend.WasmHost.ValueVaultWasmExec
