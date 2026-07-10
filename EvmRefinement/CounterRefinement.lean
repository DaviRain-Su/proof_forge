import EvmRefinement.PowdrExec
import EvmRefinement.HexWitness
import EvmRefinement.CounterRuntime
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Backend.Evm.Refinement
import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.IR.SemanticsFuel
import ProofForge.Backend.Refinement.ConstructorCoverage

/-! Counter IR/powdr-EVM storage relation.

This is the first E3 relation layer: it ties the Counter IR state's `count`
binding to the storage word that ProofForge's EVM layout assigns to `count`,
using the real powdr `AccountMap`/`Storage` model under the opt-in
`EvmRefinement` target.
-/

/-! The original hand-expanded witness is retained under an explicit legacy
namespace. It proves the pre-Solidity-layout runtime that packed `count` into
the high 64 bits; canonical definitions for the current low-order layout follow
after this namespace. -/
namespace ProofForge.Backend.Evm.CounterRefinement.LegacyHighPacked

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Backend.Refinement

abbrev IRState := ProofForge.IR.Semantics.State
abbrev EvmState := ProofForge.Backend.Evm.PowdrAdapter.State
abbrev EvmStepFEPath := ProofForge.Backend.Evm.PowdrAdapter.StepFEPath
abbrev PowdrStepFEReady := ProofForge.Backend.Evm.PowdrExec.StepFEReady
abbrev CounterCall := ProofForge.Backend.Refinement.CounterUniversal.CounterCall
abbrev counterIRStep := ProofForge.Backend.Refinement.CounterUniversal.irStep

def counterCountSlotNat : Nat := 0

/-- The EVM layout assigns Counter.count to scalar storage slot 0. -/
theorem counter_count_slot_from_layout :
    ProofForge.Backend.Evm.Plan.stateSlot?
      ProofForge.IR.Examples.Counter.module "count" = some counterCountSlotNat := by
  native_decide

def counterCountSlot : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat counterCountSlotNat

def counterU64Modulus : Nat := 2 ^ 64

def counterU64StorageShift : Nat := 2 ^ 192

/-- The generated EVM runtime stores `count : U64` in the high 64 bits of slot 0. -/
def counterPackedCountNat (count : Nat) : Nat :=
  count * counterU64StorageShift

def counterPackedCountValue (count : Nat) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat (counterPackedCountNat count)

def counterPaddedCountValue (count padding : Nat) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat (counterPackedCountNat count + padding)

def counterLowPaddingNat (word : EvmSemantics.UInt256) : Nat :=
  word.toNat % counterU64StorageShift

def counterInitializeStorageWord (word : EvmSemantics.UInt256) : EvmSemantics.UInt256 :=
  counterPaddedCountValue 0 (counterLowPaddingNat word)

/-- The generated runtime stores `count : U64` in the high 64 bits and leaves
the lower 192 bits as padding/other-packed-field space. The relation therefore
tracks the high-bit count while allowing arbitrary low padding. -/
def CounterStorageWordRel (word : EvmSemantics.UInt256) (count : Nat) : Prop :=
  ∃ padding,
    padding < counterU64StorageShift ∧
    word = EvmSemantics.UInt256.ofNat (counterPackedCountNat count + padding)

theorem counterStorageWordRel_packed (count : Nat) :
    CounterStorageWordRel (counterPackedCountValue count) count := by
  refine ⟨0, ?_, ?_⟩
  · native_decide
  · simp [counterPackedCountValue, counterPackedCountNat]

theorem counterStorageWordRel_padded {count padding : Nat}
    (hpadding : padding < counterU64StorageShift) :
    CounterStorageWordRel (counterPaddedCountValue count padding) count := by
  exact ⟨padding, hpadding, rfl⟩

theorem counterLowPaddingNat_lt (word : EvmSemantics.UInt256) :
    counterLowPaddingNat word < counterU64StorageShift := by
  unfold counterLowPaddingNat
  have hshift : 0 < counterU64StorageShift := by
    native_decide
  exact Nat.mod_lt word.toNat hshift

theorem counterInitializeStorageWord_rel_zero (word : EvmSemantics.UInt256) :
    CounterStorageWordRel (counterInitializeStorageWord word) 0 := by
  unfold counterInitializeStorageWord
  exact counterStorageWordRel_padded (counterLowPaddingNat_lt word)

theorem counterUInt256_ext_toNat {a b : EvmSemantics.UInt256}
    (h : a.toNat = b.toNat) : a = b := by
  cases a with
  | mk aval =>
    cases b with
    | mk bval =>
      simp [EvmSemantics.UInt256.toNat] at h
      cases aval with
      | mk aval avalLt =>
        cases bval with
        | mk bval bvalLt =>
          simp at h
          subst bval
          rfl

theorem counterUInt256_land_toNat
    (a b : EvmSemantics.UInt256) :
    (EvmSemantics.UInt256.land a b).toNat = a.toNat &&& b.toNat := by
  unfold EvmSemantics.UInt256.land EvmSemantics.UInt256.toNat
  change (a.val &&& b.val).val = a.val.val &&& b.val.val
  exact Fin.and_val a.val b.val

theorem counterUInt256_lor_toNat
    (a b : EvmSemantics.UInt256) :
    (EvmSemantics.UInt256.lor a b).toNat = a.toNat ||| b.toNat := by
  unfold EvmSemantics.UInt256.lor EvmSemantics.UInt256.toNat
  change (a.val ||| b.val).val = a.val.val ||| b.val.val
  rw [Fin.or_val]
  rw [Nat.mod_eq_of_lt]
  exact Nat.or_lt_two_pow (by simp [EvmSemantics.UInt256.size])
    (by simp [EvmSemantics.UInt256.size])

theorem counterUInt256_ofNat_toNat_of_lt {n : Nat}
    (h : n < EvmSemantics.UInt256.size) :
    (EvmSemantics.UInt256.ofNat n).toNat = n := by
  unfold EvmSemantics.UInt256.ofNat EvmSemantics.UInt256.toNat
  rw [Fin.val_ofNat]
  exact Nat.mod_eq_of_lt h

theorem counterUInt256_ofNat_zero_toNat :
    (EvmSemantics.UInt256.ofNat 0).toNat = 0 :=
  counterUInt256_ofNat_toNat_of_lt (by native_decide)

/-- The `PUSH0; PUSH1 0xc0; SHL` segment in the compiled initialize body. -/
def counterInitializeSetValue : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.shiftLeft
    (EvmSemantics.UInt256.ofNat 0)
    (EvmSemantics.UInt256.ofNat 192)

/-- The low-192-bit preserve mask built by the compiled initialize body. -/
def counterInitializeLowMask : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.lnot
    (EvmSemantics.UInt256.shiftLeft
      (EvmSemantics.UInt256.ofNat (2 ^ 64 - 1))
      (EvmSemantics.UInt256.ofNat 192))

def counterInitializeBodyWriteWord
    (oldWord : EvmSemantics.UInt256) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.lor
    (EvmSemantics.UInt256.land oldWord counterInitializeLowMask)
    counterInitializeSetValue

theorem counterInitializeSetValue_eq_zero :
    counterInitializeSetValue = EvmSemantics.UInt256.ofNat 0 := by
  native_decide

theorem counterInitializeLowMask_eq :
    counterInitializeLowMask =
      EvmSemantics.UInt256.ofNat (counterU64StorageShift - 1) := by
  native_decide

theorem counterInitializeLandLowMask_toNat (word : EvmSemantics.UInt256) :
    (EvmSemantics.UInt256.land word
        (EvmSemantics.UInt256.ofNat (counterU64StorageShift - 1))).toNat =
      counterLowPaddingNat word := by
  unfold counterLowPaddingNat counterU64StorageShift
  rw [counterUInt256_land_toNat]
  unfold EvmSemantics.UInt256.toNat EvmSemantics.UInt256.ofNat
  simp only [Fin.val_ofNat]
  rw [Nat.mod_eq_of_lt]
  · rw [Nat.and_two_pow_sub_one_eq_mod]
  · unfold EvmSemantics.UInt256.size
    native_decide

theorem counterLowPaddingNat_lt_uint256Size (word : EvmSemantics.UInt256) :
    counterLowPaddingNat word < EvmSemantics.UInt256.size :=
  Nat.lt_trans (counterLowPaddingNat_lt word) (by native_decide)

theorem counterInitializeBodyWriteWord_eq_storageWord
    (word : EvmSemantics.UInt256) :
    counterInitializeBodyWriteWord word = counterInitializeStorageWord word := by
  unfold counterInitializeBodyWriteWord
  rw [counterInitializeLowMask_eq, counterInitializeSetValue_eq_zero]
  apply counterUInt256_ext_toNat
  rw [counterUInt256_lor_toNat, counterInitializeLandLowMask_toNat,
    counterUInt256_ofNat_zero_toNat]
  simp only [Nat.or_zero]
  unfold counterInitializeStorageWord counterPaddedCountValue counterPackedCountNat
  simp only [Nat.zero_mul, Nat.zero_add]
  rw [counterUInt256_ofNat_toNat_of_lt
    (counterLowPaddingNat_lt_uint256Size word)]

theorem counterInitializeBodyWriteWord_rel_zero
    (word : EvmSemantics.UInt256) :
    CounterStorageWordRel (counterInitializeBodyWriteWord word) 0 := by
  rw [counterInitializeBodyWriteWord_eq_storageWord]
  exact counterInitializeStorageWord_rel_zero word

/-- Placeholder contract account address for the storage relation.

The later bytecode-entrypoint proof should replace this default with the
address from powdr's execution environment for the deployed Counter code. -/
def counterContractAddress : EvmSemantics.AccountAddress :=
  EvmSemantics.AccountAddress.ofNat 0

def counterAccount (address : EvmSemantics.AccountAddress) (state : EvmState) :
    EvmSemantics.Account :=
  state.accountMap address

def counterStorageValue (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (state : EvmState) : EvmSemantics.UInt256 :=
  (counterAccount address state).storage slot

def setCounterStorage (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (state : EvmState) (value : Nat) : EvmState :=
  let account := state.accountMap address
  let storage := account.storage.set slot (counterPackedCountValue value)
  { state with
    accountMap := state.accountMap.set address { account with storage := storage } }

def setCounterStorageWord (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (state : EvmState)
    (word : EvmSemantics.UInt256) : EvmState :=
  let account := state.accountMap address
  let storage := account.storage.set slot word
  { state with
    accountMap := state.accountMap.set address { account with storage := storage } }

@[simp] theorem counterStorageValue_setCounterStorage_same
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) (value : Nat) :
    counterStorageValue address slot (setCounterStorage address slot state value) =
      counterPackedCountValue value := by
  simp [counterStorageValue, counterAccount, setCounterStorage]

@[simp] theorem counterStorageValue_setCounterStorageWord_same
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) (word : EvmSemantics.UInt256) :
    counterStorageValue address slot (setCounterStorageWord address slot state word) =
      word := by
  simp [counterStorageValue, counterAccount, setCounterStorageWord]

@[simp] theorem counterStorageValue_accountMap_set_storage_same
    (state : EvmState) (address : EvmSemantics.AccountAddress)
    (slot word : EvmSemantics.UInt256) :
    counterStorageValue address slot
      { state with
        accountMap := state.accountMap.set address
          { state.accountMap address with
            storage := (state.accountMap address).storage.set slot word } } =
      word := by
  simp [counterStorageValue, counterAccount]

@[simp] theorem counterStorageValue_consumeGas
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) (gas : Nat) (hgas : gas ≤ state.gasAvailable) :
    counterStorageValue address slot (state.consumeGas gas hgas) =
      counterStorageValue address slot state := by
  simp [counterStorageValue, counterAccount, EvmSemantics.EVM.State.consumeGas]

@[simp] theorem counterStorageValue_incrPC
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) :
    counterStorageValue address slot state.incrPC =
      counterStorageValue address slot state := by
  simp [counterStorageValue, counterAccount, EvmSemantics.EVM.State.incrPC]

@[simp] theorem counterStorageValue_replaceStackAndIncrPC
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) (stack : List EvmSemantics.UInt256) (pcΔ : Nat) :
    counterStorageValue address slot
        (state.replaceStackAndIncrPC stack (pcΔ := pcΔ)) =
      counterStorageValue address slot state := by
  simp [counterStorageValue, counterAccount,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

@[simp] theorem counterStorageValue_with_pc_stack
    (address : EvmSemantics.AccountAddress) (slot : EvmSemantics.UInt256)
    (state : EvmState) (pc : EvmSemantics.UInt256)
    (stack : List EvmSemantics.UInt256) :
    counterStorageValue address slot ({ state with pc := pc, stack := stack } : EvmState) =
      counterStorageValue address slot state := by
  simp [counterStorageValue, counterAccount]

def counterPush0Op : EvmSemantics.Operation.PushOp :=
  { width := ⟨0, by decide⟩ }

def counterPush1Op : EvmSemantics.Operation.PushOp :=
  { width := ⟨1, by decide⟩ }

def counterPush4Op : EvmSemantics.Operation.PushOp :=
  { width := ⟨4, by decide⟩ }

def counterDup1Op : EvmSemantics.Operation.DupOp :=
  { idx := ⟨0, by decide⟩ }

def counterDup2Op : EvmSemantics.Operation.DupOp :=
  { idx := ⟨1, by decide⟩ }

def counterSwap1Op : EvmSemantics.Operation.SwapOp :=
  { idx := ⟨0, by decide⟩ }

def counterStepFEReady (state : EvmState) (op : EvmSemantics.Operation) : Prop :=
  state.halt = .Running ∧
    EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
      state.executionEnv.codeAddr = false ∧
    ¬ state.stack.length + op.pushArity > 1024 + op.popArity ∧
    EvmSemantics.EVM.Gas.baseCost state.fork op ≤ state.gasAvailable

theorem counterStepFEReady_to_powdr
    {state : EvmState} {op : EvmSemantics.Operation}
    (hready : counterStepFEReady state op) :
    PowdrStepFEReady state op := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  exact ⟨hrunning, hprecompile, hstackOk, hgas⟩

theorem counterStack_of_push0_ok
    {state gasState nextState : EvmState}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hstep :
      EvmSemantics.EVM.stepF.push state gasState counterPush0Op argOpt =
        .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.ofNat 0 :: state.stack := by
  unfold EvmSemantics.EVM.stepF.push counterPush0Op at hstep
  simp at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC,
    EvmSemantics.UInt256.ofNat]

theorem counterState_of_push0_ok
    {state gasState nextState : EvmState}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hstep :
      EvmSemantics.EVM.stepF.push state gasState counterPush0Op argOpt =
        .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack) := by
  unfold EvmSemantics.EVM.stepF.push counterPush0Op at hstep
  simp at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC,
    EvmSemantics.UInt256.ofNat]

theorem counterStack_of_stepFE_push0_ok
    {state nextState : EvmState}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Push counterPush0Op, argOpt))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush0Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush0Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush0Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.ofNat 0 :: state.stack := by
  have hready : PowdrStepFEReady state (.Push counterPush0Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_push0_ok
      (op := counterPush0Op) (argOpt := argOpt) (by rfl) hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_stepFE_push0_ok
    {state nextState : EvmState}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Push counterPush0Op, argOpt))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush0Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush0Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush0Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush0Op : EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack) := by
  have hready : PowdrStepFEReady state (.Push counterPush0Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_push0_ok
      (op := counterPush0Op) (argOpt := argOpt) (by rfl) hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_push0_ok
    {state nextState : EvmState}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Push counterPush0Op, argOpt))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush0Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush0Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush0Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_push0_ok hrunning hprecompile hdecoded
      hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_push1_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hstep :
      EvmSemantics.EVM.stepF.push state gasState counterPush1Op
        (some (value, argBytes)) = .ok nextState) :
    nextState.stack = value :: state.stack := by
  unfold EvmSemantics.EVM.stepF.push counterPush1Op at hstep
  simp at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_push1_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded = some (.Push counterPush1Op, some (value, argBytes)))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = value :: state.stack := by
  have hready : PowdrStepFEReady state (.Push counterPush1Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_push_data_ok
      (op := counterPush1Op) (value := value) (argBytes := argBytes)
      (widthPred := 0) (by rfl) hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_push1_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hstep :
      EvmSemantics.EVM.stepF.push state gasState counterPush1Op
        (some (value, argBytes)) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC (value :: state.stack)
        (pcΔ := argBytes + 1) := by
  unfold EvmSemantics.EVM.stepF.push counterPush1Op at hstep
  simp at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_push1_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded = some (.Push counterPush1Op, some (value, argBytes)))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (value :: state.stack) (pcΔ := argBytes + 1) := by
  have hready : PowdrStepFEReady state (.Push counterPush1Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_push_data_ok
      (op := counterPush1Op) (value := value) (argBytes := argBytes)
      (widthPred := 0) (by rfl) hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_push1_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded = some (.Push counterPush1Op, some (value, argBytes)))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_push1_ok hrunning hprecompile hdecoded
      hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_push4_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hstep :
      EvmSemantics.EVM.stepF.push state gasState counterPush4Op
        (some (value, argBytes)) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC (value :: state.stack)
        (pcΔ := argBytes + 1) := by
  unfold EvmSemantics.EVM.stepF.push counterPush4Op at hstep
  simp at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_push4_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded = some (.Push counterPush4Op, some (value, argBytes)))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush4Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush4Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush4Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush4Op : EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (value :: state.stack) (pcΔ := argBytes + 1) := by
  have hready : PowdrStepFEReady state (.Push counterPush4Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_push_data_ok
      (op := counterPush4Op) (value := value) (argBytes := argBytes)
      (widthPred := 3) (by rfl) hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_push4_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {argBytes : Nat}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded = some (.Push counterPush4Op, some (value, argBytes)))
    (hstackOk :
      ¬ state.stack.length +
          (.Push counterPush4Op : EvmSemantics.Operation).pushArity >
        1024 + (.Push counterPush4Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Push counterPush4Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_push4_ok hrunning hprecompile hdecoded
      hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_env_calldataload_ok
    {state gasState nextState : EvmState}
    {offset : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = offset :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.env state gasState
        (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest) := by
  unfold EvmSemantics.EVM.stepF.env at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_env_calldataload_ok
    {state nextState : EvmState}
    {offset : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none))
    (hstack : state.stack = offset :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_calldataload_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_env_calldataload_ok
    {state nextState : EvmState}
    {offset : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none))
    (hstack : state.stack = offset :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_env_calldataload_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_dup1_ok
    {state gasState nextState : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = top :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.dup state gasState counterDup1Op =
        .ok nextState) :
    nextState.stack = top :: top :: rest := by
  unfold EvmSemantics.EVM.stepF.dup counterDup1Op at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_dup1_ok
    {state gasState nextState : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = top :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.dup state gasState counterDup1Op =
        .ok nextState) :
    nextState = gasState.replaceStackAndIncrPC (top :: top :: rest) := by
  unfold EvmSemantics.EVM.stepF.dup counterDup1Op at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterStack_of_stepFE_dup1_ok
    {state nextState : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Dup counterDup1Op, none))
    (hstack : state.stack = top :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.Dup counterDup1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Dup counterDup1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Dup counterDup1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = top :: top :: rest := by
  have hready : PowdrStepFEReady state (.Dup counterDup1Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_dup_ok
      (op := counterDup1Op) (value := top) hready hdecoded
      (by simp [counterDup1Op, hstack])
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_stepFE_dup1_ok
    {state nextState : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Dup counterDup1Op, none))
    (hstack : state.stack = top :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.Dup counterDup1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Dup counterDup1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Dup counterDup1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Dup counterDup1Op : EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (top :: top :: rest) := by
  have hready : PowdrStepFEReady state (.Dup counterDup1Op) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hindex : state.stack[counterDup1Op.idx.val]? = some top := by
    simp [counterDup1Op, hstack]
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_dup_ok
      (op := counterDup1Op) (value := top) hready hdecoded hindex
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [hstack, EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterCallStack_of_stepFE_dup1_ok
    {state nextState : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded : state.decoded = some (.Dup counterDup1Op, none))
    (hstack : state.stack = top :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.Dup counterDup1Op : EvmSemantics.Operation).pushArity >
        1024 + (.Dup counterDup1Op : EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.Dup counterDup1Op : EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_dup1_ok hrunning hprecompile hdecoded hstack
      hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_compBit_shl_ok
    {state gasState nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = shift :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.shiftLeft value shift :: rest := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_compBit_shl_ok
    {state gasState nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = shift :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftLeft value shift :: rest) := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterCallStack_of_compBit_shl_ok
    {state gasState nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = shift :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_compBit_shl_ok
    {state nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.shiftLeft value shift :: rest := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_shl_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_stepFE_compBit_shl_ok
    {state nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftLeft value shift :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_shl_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_compBit_shl_ok
    {state nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_compBit_shl_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_compBit_shr_ok
    {state gasState nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = shift :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.SHR : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest) := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_compBit_shr_ok
    {state nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_shr_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_compBit_shr_ok
    {state nextState : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = shift :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_compBit_shr_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_compBit_eq_ok
    {state gasState nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest) := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_compBit_eq_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_eq_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_compBit_eq_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_compBit_eq_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_compBit_not_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.NOT : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.lnot value :: rest := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_compBit_not_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.NOT : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState =
      gasState.replaceStackAndIncrPC (EvmSemantics.UInt256.lnot value :: rest) := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterCallStack_of_compBit_not_ok
    {state gasState nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.NOT : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_compBit_not_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.lnot value :: rest := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_not_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_stepFE_compBit_not_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.lnot value :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_not_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_compBit_not_ok
    {state nextState : EvmState}
    {value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_compBit_not_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stopArith_sub_ok
    {state gasState nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stopArith state gasState
        (.SUB : EvmSemantics.Operation.StopArithOps) = .ok nextState) :
    nextState.stack = (a - b) :: rest := by
  unfold EvmSemantics.EVM.stepF.stopArith at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_stopArith_sub_ok
    {state gasState nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stopArith state gasState
        (.SUB : EvmSemantics.Operation.StopArithOps) = .ok nextState) :
    nextState = gasState.replaceStackAndIncrPC ((a - b) :: rest) := by
  unfold EvmSemantics.EVM.stepF.stopArith at hstep
  simp [hstack] at hstep
  cases hstep
  rfl

theorem counterCallStack_of_stopArith_sub_ok
    {state gasState nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stopArith state gasState
        (.SUB : EvmSemantics.Operation.StopArithOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.stopArith at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_stopArith_sub_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = (a - b) :: rest := by
  have hready :
      PowdrStepFEReady state
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sub_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_stepFE_stopArith_sub_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC
        ((a - b) :: rest) := by
  have hready :
      PowdrStepFEReady state
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)) :=
    counterStepFEReady_to_powdr
      ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sub_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_stopArith_sub_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_stopArith_sub_ok hrunning hprecompile hdecoded
      hstack hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterInitializeU64MaskBase_eq :
    (EvmSemantics.UInt256.shiftLeft
        (EvmSemantics.UInt256.ofNat 1)
        (EvmSemantics.UInt256.ofNat 64) -
      EvmSemantics.UInt256.ofNat 1) =
      EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) := by
  native_decide

theorem counterCountSlot_eq_zero :
    counterCountSlot = EvmSemantics.UInt256.ofNat 0 := by
  rfl

theorem counterStack_of_initialize_prefix_to_sload_ok
    {s0 g0 s1 g1 s2 g2 s3 g3 s4 g4 s5 g5 s6 g6 s7 g7 s8 g8
      s9 g9 s10 g10 s11 g11 s12 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hp0 :
      EvmSemantics.EVM.stepF.push s0 g0 counterPush0Op none = .ok s1)
    (hp192a :
      EvmSemantics.EVM.stepF.push s1 g1 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 192, 1)) = .ok s2)
    (hshlSet :
      EvmSemantics.EVM.stepF.compBit s2 g2
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s3)
    (hp1a :
      EvmSemantics.EVM.stepF.push s3 g3 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 1, 1)) = .ok s4)
    (hdup1 :
      EvmSemantics.EVM.stepF.dup s4 g4 counterDup1Op = .ok s5)
    (hp64 :
      EvmSemantics.EVM.stepF.push s5 g5 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 64, 1)) = .ok s6)
    (hshl64 :
      EvmSemantics.EVM.stepF.compBit s6 g6
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s7)
    (hsub :
      EvmSemantics.EVM.stepF.stopArith s7 g7
        (.SUB : EvmSemantics.Operation.StopArithOps) = .ok s8)
    (hp192b :
      EvmSemantics.EVM.stepF.push s8 g8 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 192, 1)) = .ok s9)
    (hshlMask :
      EvmSemantics.EVM.stepF.compBit s9 g9
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s10)
    (hnot :
      EvmSemantics.EVM.stepF.compBit s10 g10
        (.NOT : EvmSemantics.Operation.CompareBitwiseOps) = .ok s11)
    (hp0Slot :
      EvmSemantics.EVM.stepF.push s11 g11 counterPush0Op none = .ok s12) :
    s12.stack =
      counterCountSlot :: counterInitializeLowMask ::
        counterInitializeSetValue :: rest := by
  have h1 : s1.stack = EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [counterStack_of_push0_ok hp0, h0]
  have h2 :
      s2.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [counterStack_of_push1_ok hp192a, h1]
  have h3 : s3.stack = counterInitializeSetValue :: rest := by
    rw [counterStack_of_compBit_shl_ok h2 hshlSet]
    rfl
  have h4 :
      s4.stack =
        EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue :: rest := by
    rw [counterStack_of_push1_ok hp1a, h3]
  have h5 :
      s5.stack =
        EvmSemantics.UInt256.ofNat 1 :: EvmSemantics.UInt256.ofNat 1 ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_dup1_ok h4 hdup1]
  have h6 :
      s6.stack =
        EvmSemantics.UInt256.ofNat 64 :: EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [counterStack_of_push1_ok hp64, h5]
  have h7 :
      s7.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat 1)
          (EvmSemantics.UInt256.ofNat 64) ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [counterStack_of_compBit_shl_ok h6 hshl64]
  have h8 :
      s8.stack =
        EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stopArith_sub_ok h7 hsub,
      counterInitializeU64MaskBase_eq]
  have h9 :
      s9.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
            counterInitializeSetValue :: rest := by
    rw [counterStack_of_push1_ok hp192b, h8]
  have h10 :
      s10.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat (2 ^ 64 - 1))
          (EvmSemantics.UInt256.ofNat 192) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_compBit_shl_ok h9 hshlMask]
  have h11 :
      s11.stack = counterInitializeLowMask :: counterInitializeSetValue ::
        rest := by
    rw [counterStack_of_compBit_not_ok h10 hnot]
    rfl
  rw [counterStack_of_push0_ok hp0Slot, h11, counterCountSlot_eq_zero]

theorem counterStack_of_sload_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (haddr : state.executionEnv.address = counterContractAddress)
    (hstack : state.stack = slot :: rest)
    (hslot : slot = counterCountSlot)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState.stack =
      counterStorageValue counterContractAddress counterCountSlot state :: rest := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack] at hstep
  by_cases hgas : EvmSemantics.EVM.Gas.sloadTotal state slot ≤ state.gasAvailable
  · simp [hgas] at hstep
    cases hstep
    simp [counterStorageValue, counterAccount,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, haddr, hslot]
  · simp [hgas] at hstep

theorem counterCallStack_of_sload_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = slot :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState.callStack = state.callStack := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack] at hstep
  by_cases hgas : EvmSemantics.EVM.Gas.sloadTotal state slot ≤ state.gasAvailable
  · simp [hgas] at hstep
    cases hstep
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  · simp [hgas] at hstep

theorem counterState_of_stackMemFlow_jumpdest_ok
    {state gasState nextState : EvmState}
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState = gasState.incrPC := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_stackMemFlow_jumpdest_ok
    {state nextState : EvmState}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation)) hgas).incrPC := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_jumpdest_ok hready hdecoded
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_stackMemFlow_jumpdest_ok
    {state nextState : EvmState}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning hprecompile
      hdecoded hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC]

theorem counterState_of_stackMemFlow_jump_ok
    {state gasState nextState : EvmState}
    {dest : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState = { gasState with pc := dest, stack := rest } := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack, hvalid] at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_stackMemFlow_jump_ok
    {state nextState : EvmState}
    {dest : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation)) hgas with
        pc := dest, stack := rest } := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_jump_ok
      hready hdecoded hstack hvalid
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_stackMemFlow_jump_ok
    {state nextState : EvmState}
    {dest : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jump_ok hrunning hprecompile
      hdecoded hstack hvalid hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas]

theorem counterState_of_stackMemFlow_jumpi_taken_ok
    {state gasState nextState : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState = { gasState with pc := dest, stack := rest } := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  simp [hstack, hcond, hvalid] at hstep
  cases hstep
  rfl

theorem counterState_of_stepFE_stackMemFlow_jumpi_taken_ok
    {state nextState : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation)) hgas with
        pc := dest, stack := rest } := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_jumpi_taken_ok
      hready hdecoded hstack hcond hvalid
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterCallStack_of_stepFE_stackMemFlow_jumpi_taken_ok
    {state nextState : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        dest.toNat = true)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning hprecompile
      hdecoded hstack hcond hvalid hstackOk hgas hstep
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas]

theorem counterState_of_stepFE_stackMemFlow_jumpi_not_taken_ok
    {state nextState : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState =
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation)) hgas).replaceStackAndIncrPC rest := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_jumpi_not_taken_ok
      hready hdecoded hstack hcond
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  rfl

theorem counterReadPadded_zero_zero (bytes : ByteArray) :
    EvmSemantics.MachineState.readPadded bytes 0 0 = ByteArray.empty := by
  simp [EvmSemantics.MachineState.readPadded]
  rfl

theorem counterState_of_system_return_empty_ok
    {state gasState nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat 0 :: EvmSemantics.UInt256.ofNat 0 :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.system state gasState
        (.RETURN : EvmSemantics.Operation.SystemOps) = .ok nextState) :
    nextState.halt = .Returned ∧
      nextState.hReturn = ByteArray.empty ∧
      nextState.stack = rest ∧
      nextState.callStack = gasState.callStack ∧
      counterStorageValue counterContractAddress counterCountSlot nextState =
        counterStorageValue counterContractAddress counterCountSlot gasState := by
  have hzero : (EvmSemantics.UInt256.ofNat 0).toNat = 0 := by
    native_decide
  unfold EvmSemantics.EVM.stepF.system at hstep
  simp [hstack, hzero, EvmSemantics.EVM.chargeMem,
    EvmSemantics.EVM.State.canExpandMemory,
    EvmSemantics.EVM.State.consumeMemExp,
    EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.MachineState.memExpansionDelta,
    EvmSemantics.MachineState.activeWordsAfter,
    counterReadPadded_zero_zero] at hstep
  cases hstep
  simp [counterStorageValue, counterAccount]

theorem counterState_of_stepFE_system_return_empty_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.System
          (.RETURN : EvmSemantics.Operation.SystemOps), none))
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat 0 :: EvmSemantics.UInt256.ofNat 0 :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.halt = .Returned ∧
      nextState.hReturn = ByteArray.empty ∧
      nextState.stack = rest ∧
      nextState.callStack = state.callStack ∧
      counterStorageValue counterContractAddress counterCountSlot nextState =
        counterStorageValue counterContractAddress counterCountSlot state := by
  have hready :
      PowdrStepFEReady state
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hmem :
      (state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.System (.RETURN : EvmSemantics.Operation.SystemOps) :
            EvmSemantics.Operation)) hgas).canExpandMemory 0 0 := by
    simp [EvmSemantics.EVM.State.canExpandMemory,
      EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.MachineState.memExpansionDelta,
      EvmSemantics.MachineState.activeWordsAfter]
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_return_ok
      (offset := EvmSemantics.UInt256.ofNat 0)
      (size := EvmSemantics.UInt256.ofNat 0)
      (rest := rest) hready hdecoded hstack
      (by simpa [counterUInt256_ofNat_zero_toNat] using hmem)
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [counterUInt256_ofNat_zero_toNat, counterReadPadded_zero_zero,
    counterStorageValue, counterAccount, EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.consumeMemExp]

theorem counterStack_of_stepFE_stackMemFlow_sload_ok
    {state nextState : EvmState} {slot : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none))
    (haddr : state.executionEnv.address = counterContractAddress)
    (hstack : state.stack = slot :: rest)
    (hslot : slot = counterCountSlot)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack =
      counterStorageValue counterContractAddress counterCountSlot state :: rest := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstackGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sload_success_stack_ok
      hready hdecoded hstack hstep
  rw [hstackGeneric]
  simp [counterStorageValue, counterAccount, haddr, hslot]

theorem counterCallStack_of_stepFE_stackMemFlow_sload_ok
    {state nextState : EvmState} {slot : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = slot :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  exact ProofForge.Backend.Evm.PowdrExec.stepFE_sload_success_callStack_ok
    hready hdecoded hstack hstep

theorem counterStack_of_compBit_and_ok
    {state gasState nextState : EvmState} {a b : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.land a b :: rest := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterCallStack_of_compBit_and_ok
    {state gasState nextState : EvmState} {a b : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_compBit_and_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.land a b :: rest := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_and_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterCallStack_of_stepFE_compBit_and_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_and_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_compBit_or_ok
    {state gasState nextState : EvmState} {a b : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.lor a b :: rest := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterCallStack_of_compBit_or_ok
    {state gasState nextState : EvmState} {a b : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = a :: b :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.compBit state gasState
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.compBit at hstep
  simp [hstack] at hstep
  cases hstep
  simp [EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_stepFE_compBit_or_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = EvmSemantics.UInt256.lor a b :: rest := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_or_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterCallStack_of_stepFE_compBit_or_ok
    {state nextState : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none))
    (hstack : state.stack = a :: b :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hready :
      PowdrStepFEReady state
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstepGeneric :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_or_ok
      hready hdecoded hstack
  rw [hstep] at hstepGeneric
  cases hstepGeneric
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterStack_of_initialize_sload_and_or_ok
    {sloadState sloadGas afterSload andGas afterAnd orGas afterOr : EvmState}
    {mask setValue : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (haddr : sloadState.executionEnv.address = counterContractAddress)
    (hstack : sloadState.stack = counterCountSlot :: mask :: setValue :: rest)
    (hsload :
      EvmSemantics.EVM.stepF.stackMemFlow sloadState sloadGas
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok afterSload)
    (hand :
      EvmSemantics.EVM.stepF.compBit afterSload andGas
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterAnd)
    (hor :
      EvmSemantics.EVM.stepF.compBit afterAnd orGas
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterOr) :
    afterOr.stack =
      EvmSemantics.UInt256.lor
        (EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          mask)
        setValue :: rest := by
  have hsloadStack :
      afterSload.stack =
        counterStorageValue counterContractAddress counterCountSlot sloadState ::
          mask :: setValue :: rest :=
    counterStack_of_sload_stackMemFlow_ok haddr hstack rfl hsload
  have handStack :
      afterAnd.stack =
        EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          mask :: setValue :: rest :=
    counterStack_of_compBit_and_ok hsloadStack hand
  exact counterStack_of_compBit_or_ok handStack hor

theorem counterStack_of_initialize_sload_and_or_storageWord_ok
    {sloadState sloadGas afterSload andGas afterAnd orGas afterOr : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddr : sloadState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hsload :
      EvmSemantics.EVM.stepF.stackMemFlow sloadState sloadGas
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok afterSload)
    (hand :
      EvmSemantics.EVM.stepF.compBit afterSload andGas
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterAnd)
    (hor :
      EvmSemantics.EVM.stepF.compBit afterAnd orGas
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterOr) :
    afterOr.stack =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
  have hstackAfter :=
    counterStack_of_initialize_sload_and_or_ok haddr hstack hsload hand hor
  rw [hstackAfter]
  change counterInitializeBodyWriteWord
      (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
        rest =
    counterInitializeStorageWord
      (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
        rest
  rw [counterInitializeBodyWriteWord_eq_storageWord]

theorem counterStorageValue_of_sstore_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (haddr : state.executionEnv.address = counterContractAddress)
    (hstack : state.stack = slot :: value :: rest)
    (hslot : slot = counterCountSlot)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState = value := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  cases hperm : state.executionEnv.permitStateMutation
  · simp [hperm, EvmSemantics.EVM.static] at hstep
  · simp [hperm] at hstep
    by_cases hsentry :
        EvmSemantics.EVM.Gas.sstoreSentry state.fork gasState.gasAvailable
    · simp [hsentry] at hstep
    · simp [hsentry, hstack] at hstep
      by_cases hgas :
          EvmSemantics.EVM.Gas.sstoreCost state.fork
              (state.substate.originalStorage state.executionEnv.address slot)
              ((state.accountMap state.executionEnv.address).storage slot) value +
            EvmSemantics.EVM.Gas.sstoreColdSurcharge state slot ≤ gasState.gasAvailable
      · simp [hgas] at hstep
        cases hstep
        simp [counterStorageValue, counterAccount,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, haddr, hslot]
      · simp [hgas] at hstep

theorem counterStorageValue_of_stepFE_stackMemFlow_sstore_ok
    {state nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (haddr : state.executionEnv.address = counterContractAddress)
    (hstack : state.stack = slot :: value :: rest)
    (hslot : slot = counterCountSlot)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState = value := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hdispatch :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sstore_dispatch_ok hready hdecoded
  rw [hdispatch] at hstep
  exact counterStorageValue_of_sstore_stackMemFlow_ok haddr hstack hslot hstep

theorem counterStack_of_sstore_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = slot :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState.stack = rest := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  cases hperm : state.executionEnv.permitStateMutation
  · simp [hperm, EvmSemantics.EVM.static] at hstep
  · simp [hperm] at hstep
    by_cases hsentry :
        EvmSemantics.EVM.Gas.sstoreSentry state.fork gasState.gasAvailable
    · simp [hsentry] at hstep
    · simp [hsentry, hstack] at hstep
      by_cases hgas :
          EvmSemantics.EVM.Gas.sstoreCost state.fork
              (state.substate.originalStorage state.executionEnv.address slot)
              ((state.accountMap state.executionEnv.address).storage slot) value +
            EvmSemantics.EVM.Gas.sstoreColdSurcharge state slot ≤ gasState.gasAvailable
      · simp [hgas] at hstep
        cases hstep
        simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC]
      · simp [hgas] at hstep

theorem counterCallStack_of_sstore_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = slot :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState.callStack = gasState.callStack := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  cases hperm : state.executionEnv.permitStateMutation
  · simp [hperm, EvmSemantics.EVM.static] at hstep
  · simp [hperm] at hstep
    by_cases hsentry :
        EvmSemantics.EVM.Gas.sstoreSentry state.fork gasState.gasAvailable
    · simp [hsentry] at hstep
    · simp [hsentry, hstack] at hstep
      by_cases hgas :
          EvmSemantics.EVM.Gas.sstoreCost state.fork
              (state.substate.originalStorage state.executionEnv.address slot)
              ((state.accountMap state.executionEnv.address).storage slot) value +
            EvmSemantics.EVM.Gas.sstoreColdSurcharge state slot ≤ gasState.gasAvailable
      · simp [hgas] at hstep
        cases hstep
        simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC]
      · simp [hgas] at hstep

theorem counterStack_of_stepFE_stackMemFlow_sstore_ok
    {state nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = slot :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.stack = rest := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hdispatch :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sstore_dispatch_ok hready hdecoded
  rw [hdispatch] at hstep
  exact counterStack_of_sstore_stackMemFlow_ok hstack hstep

theorem counterCallStack_of_stepFE_stackMemFlow_sstore_ok
    {state nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = slot :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.callStack = state.callStack := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hdispatch :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sstore_dispatch_ok hready hdecoded
  rw [hdispatch] at hstep
  have hcallStack := counterCallStack_of_sstore_stackMemFlow_ok hstack hstep
  simpa [EvmSemantics.EVM.State.consumeGas] using hcallStack

theorem counterCodePcFork_of_sstore_stackMemFlow_ok
    {state gasState nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = slot :: value :: rest)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    nextState.executionEnv.code = gasState.executionEnv.code ∧
      nextState.pc = gasState.pc + EvmSemantics.UInt256.ofNat 1 ∧
      nextState.executionEnv.fork = gasState.executionEnv.fork := by
  unfold EvmSemantics.EVM.stepF.stackMemFlow at hstep
  cases hperm : state.executionEnv.permitStateMutation
  · simp [hperm, EvmSemantics.EVM.static] at hstep
  · simp [hperm] at hstep
    by_cases hsentry :
        EvmSemantics.EVM.Gas.sstoreSentry state.fork gasState.gasAvailable
    · simp [hsentry] at hstep
    · simp [hsentry, hstack] at hstep
      by_cases hgas :
          EvmSemantics.EVM.Gas.sstoreCost state.fork
              (state.substate.originalStorage state.executionEnv.address slot)
              ((state.accountMap state.executionEnv.address).storage slot) value +
            EvmSemantics.EVM.Gas.sstoreColdSurcharge state slot ≤ gasState.gasAvailable
      · simp [hgas] at hstep
        cases hstep
        simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC]
      · simp [hgas] at hstep

theorem counterCodePcFork_of_stepFE_stackMemFlow_sstore_ok
    {state nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hrunning : state.halt = .Running)
    (hprecompile :
      EvmSemantics.EVM.Precompile.isPrecompile state.executionEnv.fork
        state.executionEnv.codeAddr = false)
    (hdecoded :
      state.decoded =
        some (.StackMemFlow
          (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none))
    (hstack : state.stack = slot :: value :: rest)
    (hstackOk :
      ¬ state.stack.length +
          (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).pushArity >
        1024 + (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).popArity)
    (hgas :
      EvmSemantics.EVM.Gas.baseCost state.fork
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
          EvmSemantics.Operation) ≤ state.gasAvailable)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    nextState.executionEnv.code = state.executionEnv.code ∧
      nextState.pc = state.pc + EvmSemantics.UInt256.ofNat 1 ∧
      nextState.executionEnv.fork = state.executionEnv.fork := by
  have hready :
      PowdrStepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)) :=
    ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hdispatch :=
    ProofForge.Backend.Evm.PowdrExec.stepFE_sstore_dispatch_ok hready hdecoded
  rw [hdispatch] at hstep
  obtain ⟨hcode, hpc, hfork⟩ :=
    counterCodePcFork_of_sstore_stackMemFlow_ok hstack hstep
  refine ⟨?_, ?_, ?_⟩
  · simpa [EvmSemantics.EVM.State.consumeGas] using hcode
  · simpa [EvmSemantics.EVM.State.consumeGas] using hpc
  · simpa [EvmSemantics.EVM.State.consumeGas] using hfork

theorem counterInitializeStorageValue_of_sstore_stackMemFlow_ok
    {state gasState nextState : EvmState} {rest : List EvmSemantics.UInt256}
    (haddr : state.executionEnv.address = counterContractAddress)
    (hstack :
      state.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot state) ::
          rest)
    (hstep :
      EvmSemantics.EVM.stepF.stackMemFlow state gasState
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot state) :=
  counterStorageValue_of_sstore_stackMemFlow_ok haddr hstack rfl hstep

theorem counterStorageValue_of_initialize_sload_and_or_push_sstore_ok
    {sloadState sloadGas afterSload andGas afterAnd orGas afterOr pushGas
      sstoreState sstoreGas nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : sloadState.executionEnv.address = counterContractAddress)
    (haddrSstore : sstoreState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hsload :
      EvmSemantics.EVM.stepF.stackMemFlow sloadState sloadGas
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok afterSload)
    (hand :
      EvmSemantics.EVM.stepF.compBit afterSload andGas
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterAnd)
    (hor :
      EvmSemantics.EVM.stepF.compBit afterAnd orGas
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterOr)
    (hpushSlot :
      EvmSemantics.EVM.stepF.push afterOr pushGas counterPush0Op none =
        .ok sstoreState)
    (hsstore :
      EvmSemantics.EVM.stepF.stackMemFlow sstoreState sstoreGas
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) := by
  have horStack :=
    counterStack_of_initialize_sload_and_or_storageWord_ok haddrSload hstack
      hsload hand hor
  have hsstoreStack :
      sstoreState.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_push0_ok hpushSlot, horStack]
    rw [← counterCountSlot_eq_zero]
  exact counterStorageValue_of_sstore_stackMemFlow_ok haddrSstore
    hsstoreStack rfl hsstore

theorem counterStorageValue_of_initialize_body_helpers_ok
    {s0 g0 s1 g1 s2 g2 s3 g3 s4 g4 s5 g5 s6 g6 s7 g7 s8 g8
      s9 g9 s10 g10 s11 g11 s12 sloadGas afterSload andGas afterAnd
      orGas afterOr pushGas sstoreState sstoreGas nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (haddrSstore : sstoreState.executionEnv.address = counterContractAddress)
    (h0 : s0.stack = rest)
    (hp0 :
      EvmSemantics.EVM.stepF.push s0 g0 counterPush0Op none = .ok s1)
    (hp192a :
      EvmSemantics.EVM.stepF.push s1 g1 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 192, 1)) = .ok s2)
    (hshlSet :
      EvmSemantics.EVM.stepF.compBit s2 g2
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s3)
    (hp1a :
      EvmSemantics.EVM.stepF.push s3 g3 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 1, 1)) = .ok s4)
    (hdup1 :
      EvmSemantics.EVM.stepF.dup s4 g4 counterDup1Op = .ok s5)
    (hp64 :
      EvmSemantics.EVM.stepF.push s5 g5 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 64, 1)) = .ok s6)
    (hshl64 :
      EvmSemantics.EVM.stepF.compBit s6 g6
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s7)
    (hsub :
      EvmSemantics.EVM.stepF.stopArith s7 g7
        (.SUB : EvmSemantics.Operation.StopArithOps) = .ok s8)
    (hp192b :
      EvmSemantics.EVM.stepF.push s8 g8 counterPush1Op
        (some (EvmSemantics.UInt256.ofNat 192, 1)) = .ok s9)
    (hshlMask :
      EvmSemantics.EVM.stepF.compBit s9 g9
        (.SHL : EvmSemantics.Operation.CompareBitwiseOps) = .ok s10)
    (hnot :
      EvmSemantics.EVM.stepF.compBit s10 g10
        (.NOT : EvmSemantics.Operation.CompareBitwiseOps) = .ok s11)
    (hp0Slot :
      EvmSemantics.EVM.stepF.push s11 g11 counterPush0Op none = .ok s12)
    (hsload :
      EvmSemantics.EVM.stepF.stackMemFlow s12 sloadGas
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) = .ok afterSload)
    (hand :
      EvmSemantics.EVM.stepF.compBit afterSload andGas
        (.AND : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterAnd)
    (hor :
      EvmSemantics.EVM.stepF.compBit afterAnd orGas
        (.OR : EvmSemantics.Operation.CompareBitwiseOps) = .ok afterOr)
    (hpushSlot :
      EvmSemantics.EVM.stepF.push afterOr pushGas counterPush0Op none =
        .ok sstoreState)
    (hsstore :
      EvmSemantics.EVM.stepF.stackMemFlow sstoreState sstoreGas
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot s12) := by
  have hsloadStack :=
    counterStack_of_initialize_prefix_to_sload_ok h0 hp0 hp192a hshlSet
      hp1a hdup1 hp64 hshl64 hsub hp192b hshlMask hnot hp0Slot
  exact counterStorageValue_of_initialize_sload_and_or_push_sstore_ok
    haddrSload haddrSstore hsloadStack hsload hand hor hpushSlot hsstore

def irCounterCount? (state : IRState) : Option Nat :=
  match state.read "count" with
  | some (.u64 count) => some count
  | _ => none

theorem irCounterCount?_write_count (state : IRState) (count : Nat) :
    irCounterCount? (state.write "count" (.u64 count)) = some count := by
  simp [irCounterCount?, State.read, State.write,
    ProofForge.Backend.Refinement.CounterUniversal.lookup_insert_same]

def CounterStorageRelAt (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (irState : IRState) (evmState : EvmState) : Prop :=
  ∃ count,
    irCounterCount? irState = some count ∧
    count < counterU64Modulus ∧
    CounterStorageWordRel (counterStorageValue address slot evmState) count

def CounterStorageRel : IRState → EvmState → Prop :=
  CounterStorageRelAt counterContractAddress counterCountSlot

theorem counterStorageRel_left_counterStateRel
    {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ count,
      ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel irState count := by
  rcases hrel with ⟨count, hcount, _hbound, _hstorage⟩
  refine ⟨count, ?_⟩
  unfold ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel
  unfold irCounterCount? at hcount
  cases hread : irState.read "count" with
  | none =>
      simp [hread] at hcount
  | some value =>
      cases value <;> simp [hread] at hcount
      case u64 value =>
        cases hcount
        rfl

theorem counterStateRel_irCounterCount?
    {irState : IRState} {count : Nat}
    (hcounter : ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel
      irState count) :
    irCounterCount? irState = some count := by
  unfold ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel at hcounter
  unfold irCounterCount?
  rw [hcounter]

theorem counterStateRel_of_irCounterCount?
    {irState : IRState} {count : Nat}
    (hcount : irCounterCount? irState = some count) :
    ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel irState count := by
  unfold ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel
  unfold irCounterCount? at hcount
  cases hread : irState.read "count" with
  | none =>
      simp [hread] at hcount
  | some value =>
      cases value <;> simp [hread] at hcount
      case u64 value =>
        cases hcount
        rfl

theorem counterStorageRel_count_bound
    {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ count,
      irCounterCount? irState = some count ∧
      count < counterU64Modulus := by
  rcases hrel with ⟨count, hcount, hbound, _hstorage⟩
  exact ⟨count, hcount, hbound⟩

theorem counterStorageRelAt_set_count (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (irState : IRState) (evmState : EvmState)
    (count : Nat) (hbound : count < counterU64Modulus) :
    CounterStorageRelAt address slot
      (irState.write "count" (.u64 count))
      (setCounterStorage address slot evmState count) := by
  refine ⟨count, irCounterCount?_write_count irState count, hbound, ?_⟩
  simp [counterStorageWordRel_packed]

theorem counterStorageRel_set_count (irState : IRState) (evmState : EvmState)
    (count : Nat) (hbound : count < counterU64Modulus) :
    CounterStorageRel
      (irState.write "count" (.u64 count))
      (setCounterStorage counterContractAddress counterCountSlot evmState count) :=
  counterStorageRelAt_set_count counterContractAddress counterCountSlot irState evmState count hbound

theorem counterStorageRelAt_set_padded_count (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (irState : IRState) (evmState : EvmState)
    (count padding : Nat) (hbound : count < counterU64Modulus)
    (hpadding : padding < counterU64StorageShift) :
    CounterStorageRelAt address slot
      (irState.write "count" (.u64 count))
      (setCounterStorageWord address slot evmState
        (counterPaddedCountValue count padding)) := by
  refine ⟨count, irCounterCount?_write_count irState count, hbound, ?_⟩
  simp [counterStorageWordRel_padded hpadding]

theorem counterStorageRel_set_padded_count (irState : IRState) (evmState : EvmState)
    (count padding : Nat) (hbound : count < counterU64Modulus)
    (hpadding : padding < counterU64StorageShift) :
    CounterStorageRel
      (irState.write "count" (.u64 count))
      (setCounterStorageWord counterContractAddress counterCountSlot evmState
        (counterPaddedCountValue count padding)) :=
  counterStorageRelAt_set_padded_count counterContractAddress counterCountSlot
    irState evmState count padding hbound hpadding

def counterCallSelector : CounterCall → String
  | .initialize => "8129fc1c"
  | .increment => "d09de08a"
  | .get => "6d4ce63c"

theorem counterCallSelector_matches_entrypoint (call : CounterCall) :
    call.entrypoint.selector? = some (counterCallSelector call) := by
  cases call <;> rfl

def counterCallCalldata : CounterCall → ByteArray
  | .initialize => ByteArray.mk #[0x81, 0x29, 0xfc, 0x1c]
  | .increment => ByteArray.mk #[0xd0, 0x9d, 0xe0, 0x8a]
  | .get => ByteArray.mk #[0x6d, 0x4c, 0xe6, 0x3c]

theorem counterCallCalldata_size (call : CounterCall) :
    (counterCallCalldata call).size = 4 := by
  cases call <;> rfl

def counterCallSelectorNat : CounterCall → Nat
  | .initialize => 2167012380
  | .increment => 3500007562
  | .get => 1833756220

def counterCallCalldataWord (call : CounterCall) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat (counterCallSelectorNat call * 2 ^ 224)

theorem counterCall_calldataload_zero_eq (call : CounterCall) :
    EvmSemantics.UInt256.ofNat
        (EvmSemantics.Data.Bytes.bytesToBigEndianNat
          (EvmSemantics.MachineState.readPadded
            (counterCallCalldata call) 0 32)) =
      counterCallCalldataWord call := by
  cases call <;> native_decide

theorem counterCall_selector_shr224_eq (call : CounterCall) :
    EvmSemantics.UInt256.shiftRight (counterCallCalldataWord call)
        (EvmSemantics.UInt256.ofNat 224) =
      EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) := by
  cases call <;> native_decide

theorem counterCall_selector_eq_true (call : CounterCall) :
    EvmSemantics.UInt256.eq
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat call))
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat call)) =
      EvmSemantics.UInt256.ofNat 1 := by
  cases call <;> native_decide

theorem counterCall_initialize_selector_eq_zero_of_ne
    {call : CounterCall} (h : call ≠ .initialize) :
    EvmSemantics.UInt256.eq
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat .initialize))
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat call)) =
      EvmSemantics.UInt256.ofNat 0 := by
  cases call
  · contradiction
  · native_decide
  · native_decide

theorem counterCall_initialize_selector_condition_zero_of_ne
    {call : CounterCall} (h : call ≠ .initialize) :
    (EvmSemantics.UInt256.eq
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat .initialize))
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat call))).toNat = 0 := by
  rw [counterCall_initialize_selector_eq_zero_of_ne h]
  native_decide

theorem counterCall_selector_condition_nonzero (_call : CounterCall) :
    (EvmSemantics.UInt256.ofNat 1).toNat ≠ 0 := by
  native_decide

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

def CounterTraceSafeAtState (irState : IRState) (calls : List CounterCall) : Prop :=
  ∀ count, irCounterCount? irState = some count →
    counterTraceSafeFromCount count calls = true

theorem counterTraceSafe_initialize_get_increment_get :
    counterTraceSafeAfterInitialize [.get, .increment, .get] = true := by
  native_decide

theorem counterTraceUnsafe_increment_at_u64_max :
    counterTraceSafeFromCount (counterU64Modulus - 1) [.increment] = false := by
  native_decide

def byteArrayHasSliceAt (bytes needle : ByteArray) (offset : Nat) : Bool :=
  offset + needle.size <= bytes.size &&
    bytes.extract offset (offset + needle.size) == needle

/-! The concrete Counter runtime emitted by:
`lake env proof-forge emit --target evm --fixture counter --format bytecode`.

This fixes the bytecode-side witness for the opt-in powdr lane. If the EVM
emitter or pinned `solc` changes, regenerate this literal and re-check the
selector-offset theorems below; the Yul-to-bytecode hop remains the documented
`solc` trust boundary.
-/
def counterCompiledRuntimeCode : ByteArray :=
  ByteArray.mk #[
    0x5f, 0x35, 0x60, 0xe0, 0x1c, 0x80, 0x63, 0x81, 0x29, 0xfc, 0x1c, 0x14,
    0x60, 0x3c, 0x57, 0x80, 0x63, 0xd0, 0x9d, 0xe0, 0x8a, 0x14, 0x60, 0x32,
    0x57, 0x63, 0x6d, 0x4c, 0xe6, 0x3c, 0x14, 0x60, 0x25, 0x57, 0x5f, 0x80,
    0xfd, 0x5b, 0x60, 0x2b, 0x60, 0x87, 0x56, 0x5b, 0x5f, 0x52, 0x60, 0x20,
    0x5f, 0xf3, 0x5b, 0x60, 0x38, 0x60, 0x5d, 0x56, 0x5b, 0x5f, 0x80, 0xf3,
    0x5b, 0x60, 0x42, 0x60, 0x46, 0x56, 0x5b, 0x5f, 0x80, 0xf3, 0x5b, 0x5f,
    0x60, 0xc0, 0x1b, 0x60, 0x01, 0x80, 0x60, 0x40, 0x1b, 0x03, 0x60, 0xc0,
    0x1b, 0x19, 0x5f, 0x54, 0x16, 0x17, 0x5f, 0x55, 0x56, 0x5b, 0x60, 0x71,
    0x60, 0x01, 0x80, 0x80, 0x60, 0x40, 0x1b, 0x03, 0x5f, 0x54, 0x60, 0xc0,
    0x1c, 0x16, 0x60, 0x97, 0x56, 0x5b, 0x60, 0xc0, 0x1b, 0x60, 0x01, 0x80,
    0x60, 0x40, 0x1b, 0x03, 0x60, 0xc0, 0x1b, 0x19, 0x5f, 0x54, 0x16, 0x17,
    0x5f, 0x55, 0x56, 0x5b, 0x60, 0x01, 0x80, 0x60, 0x40, 0x1b, 0x03, 0x5f,
    0x54, 0x60, 0xc0, 0x1c, 0x16, 0x90, 0x56, 0x5b, 0x81, 0x5f, 0x19, 0x03,
    0x81, 0x11, 0x60, 0xa4, 0x57, 0x01, 0x90, 0x56, 0x5b, 0x5f, 0x80, 0xfd,
    0xa1, 0x64, 0x73, 0x6f, 0x6c, 0x63, 0x43, 0x00, 0x08, 0x22, 0x00, 0x0a
  ]

theorem counterCompiledRuntimeCode_size :
    counterCompiledRuntimeCode.size = 180 := by
  native_decide

theorem counterCompiledRuntimeCode_dispatches_initialize :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      (counterCallCalldata .initialize) 7 = true := by
  native_decide

theorem counterCompiledRuntimeCode_dispatches_increment :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      (counterCallCalldata .increment) 17 = true := by
  native_decide

theorem counterCompiledRuntimeCode_dispatches_get :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      (counterCallCalldata .get) 26 = true := by
  native_decide

def counterGetTrampolineOffset : Nat := 37

def counterGetReturnOffset : Nat := 43

def counterGetBodyOffset : Nat := 135

def counterGetSelectorNat : Nat := 1833756220

theorem counterGetSelectorNat_eq :
    counterGetSelectorNat = counterCallSelectorNat .get := rfl

def counterGetTrampolineBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x60, 0x2b, 0x60, 0x87, 0x56]

theorem counterGetTrampolineBytes_size :
    counterGetTrampolineBytes.size = 6 := by
  native_decide

theorem counterCompiledRuntimeCode_has_get_trampoline :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterGetTrampolineBytes counterGetTrampolineOffset = true := by
  native_decide

def counterGetReturnBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x5f, 0x52, 0x60, 0x20, 0x5f, 0xf3]

theorem counterGetReturnBytes_size :
    counterGetReturnBytes.size = 7 := by
  native_decide

theorem counterCompiledRuntimeCode_has_get_return :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterGetReturnBytes counterGetReturnOffset = true := by
  native_decide

def counterGetBodyBytes : ByteArray :=
  ByteArray.mk #[
    0x5b, 0x60, 0x01, 0x80, 0x60, 0x40, 0x1b, 0x03, 0x5f, 0x54, 0x60,
    0xc0, 0x1c, 0x16, 0x90, 0x56
  ]

theorem counterGetBodyBytes_size :
    counterGetBodyBytes.size = 16 := by
  native_decide

theorem counterCompiledRuntimeCode_has_get_body :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterGetBodyBytes counterGetBodyOffset = true := by
  native_decide

def counterIncrementTrampolineOffset : Nat := 50

def counterIncrementReturnOffset : Nat := 56

def counterIncrementBodyOffset : Nat := 93

def counterIncrementWriteBodyOffset : Nat := 113

def counterIncrementCheckedAddOffset : Nat := 151

def counterIncrementOverflowRevertOffset : Nat := 164

def counterIncrementSelectorNat : Nat := 3500007562

theorem counterIncrementSelectorNat_eq :
    counterIncrementSelectorNat = counterCallSelectorNat .increment := rfl

def counterIncrementTrampolineBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x60, 0x38, 0x60, 0x5d, 0x56]

theorem counterIncrementTrampolineBytes_size :
    counterIncrementTrampolineBytes.size = 6 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_trampoline :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementTrampolineBytes counterIncrementTrampolineOffset = true := by
  native_decide

def counterIncrementReturnBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x5f, 0x80, 0xf3]

theorem counterIncrementReturnBytes_size :
    counterIncrementReturnBytes.size = 4 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_return :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementReturnBytes counterIncrementReturnOffset = true := by
  native_decide

def counterIncrementBodyBytes : ByteArray :=
  ByteArray.mk #[
    0x5b, 0x60, 0x71, 0x60, 0x01, 0x80, 0x80, 0x60, 0x40, 0x1b,
    0x03, 0x5f, 0x54, 0x60, 0xc0, 0x1c, 0x16, 0x60, 0x97, 0x56
  ]

theorem counterIncrementBodyBytes_size :
    counterIncrementBodyBytes.size = 20 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_body :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementBodyBytes counterIncrementBodyOffset = true := by
  native_decide

def counterIncrementWriteBodyBytes : ByteArray :=
  ByteArray.mk #[
    0x5b, 0x60, 0xc0, 0x1b, 0x60, 0x01, 0x80, 0x60, 0x40, 0x1b,
    0x03, 0x60, 0xc0, 0x1b, 0x19, 0x5f, 0x54, 0x16, 0x17, 0x5f,
    0x55, 0x56
  ]

theorem counterIncrementWriteBodyBytes_size :
    counterIncrementWriteBodyBytes.size = 22 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_write_body :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementWriteBodyBytes counterIncrementWriteBodyOffset = true := by
  native_decide

def counterIncrementCheckedAddBytes : ByteArray :=
  ByteArray.mk #[
    0x5b, 0x81, 0x5f, 0x19, 0x03, 0x81, 0x11, 0x60, 0xa4, 0x57,
    0x01, 0x90, 0x56
  ]

theorem counterIncrementCheckedAddBytes_size :
    counterIncrementCheckedAddBytes.size = 13 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_checked_add :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementCheckedAddBytes counterIncrementCheckedAddOffset = true := by
  native_decide

def counterIncrementOverflowRevertBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x5f, 0x80, 0xfd]

theorem counterIncrementOverflowRevertBytes_size :
    counterIncrementOverflowRevertBytes.size = 4 := by
  native_decide

theorem counterCompiledRuntimeCode_has_increment_overflow_revert :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterIncrementOverflowRevertBytes counterIncrementOverflowRevertOffset = true := by
  native_decide

def counterInitializeTrampolineOffset : Nat := 60

def counterInitializeSelectorNat : Nat := 2167012380

theorem counterInitializeSelectorNat_eq :
    counterInitializeSelectorNat = counterCallSelectorNat .initialize := rfl

def counterInitializeCalldataWord : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat (counterInitializeSelectorNat * 2 ^ 224)

theorem counterInitializeCalldataWord_eq :
    counterInitializeCalldataWord = counterCallCalldataWord .initialize := by
  rfl

theorem counterInitialize_calldataload_zero_eq :
    EvmSemantics.UInt256.ofNat
        (EvmSemantics.Data.Bytes.bytesToBigEndianNat
          (EvmSemantics.MachineState.readPadded
            (counterCallCalldata .initialize) 0 32)) =
      counterInitializeCalldataWord := by
  native_decide

theorem counterInitialize_selector_shr224_eq :
    EvmSemantics.UInt256.shiftRight counterInitializeCalldataWord
        (EvmSemantics.UInt256.ofNat 224) =
      EvmSemantics.UInt256.ofNat counterInitializeSelectorNat := by
  native_decide

theorem counterInitialize_selector_eq_true :
    EvmSemantics.UInt256.eq
        (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
        (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat) =
      EvmSemantics.UInt256.ofNat 1 := by
  native_decide

theorem counterInitialize_selector_condition_nonzero :
    (EvmSemantics.UInt256.ofNat 1).toNat ≠ 0 := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_first_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 0 =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_calldataload :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 1 =
      some (.Env
        (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_selector_shift_push224 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 2 =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 224, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_selector_shr :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 4 =
      some (.CompBit
        (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_selector_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 5 =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_initialize_selector_push4 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 6 =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_initialize_eq :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 11 =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_initialize_trampoline_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 12 =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_initialize_jumpi :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 14 =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 15 =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_push4 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 16 =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat, 4)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_increment_eq :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 21 =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_increment_trampoline_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 22 =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_increment_jumpi :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 24 =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_get_selector_push4 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 25 =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterGetSelectorNat, 4)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_get_eq :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 30 =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_get_trampoline_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 31 =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_dispatcher_get_jumpi :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode 33 =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterGetTrampolineOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_get_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterGetTrampolineOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_trampoline_return_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetTrampolineOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterGetReturnOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_trampoline_body_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetTrampolineOffset + 3) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterGetBodyOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_trampoline_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetTrampolineOffset + 5) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterGetReturnOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_get_return_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterGetReturnOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetReturnOffset + 1) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return_mstore :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetReturnOffset + 2) =
      some (.StackMemFlow
        (.MSTORE : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return_size_push32 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetReturnOffset + 3) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 32, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return_offset_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetReturnOffset + 5) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_return :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetReturnOffset + 6) =
      some (.System
        (.RETURN : EvmSemantics.Operation.SystemOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_body_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterGetBodyOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_get_body_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterGetBodyOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_mask_push1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 1, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_mask_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 3) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_mask_push64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 4) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 64, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_mask_shl64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 6) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_mask_sub :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 7) =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_sload_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 8) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_sload :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 9) =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_shift_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 10) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_shift_shr192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 12) =
      some (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_and :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 13) =
      some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_swap1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 14) =
      some (.Swap counterSwap1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_get_body_return_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterGetBodyOffset + 15) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementTrampolineOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementTrampolineOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_trampoline_return_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementTrampolineOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementReturnOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_trampoline_body_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementTrampolineOffset + 3) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementBodyOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_trampoline_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementTrampolineOffset + 5) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_return_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementReturnOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_return_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementReturnOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_return_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementReturnOffset + 1) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_return_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementReturnOffset + 2) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_return :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementReturnOffset + 3) =
      some (.System
        (.RETURN : EvmSemantics.Operation.SystemOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_body_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementBodyOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_body_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementBodyOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_body_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementWriteBodyOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_one_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 3) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 1, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_one_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 5) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_value_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 6) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_mask_push64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 7) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 64, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_mask_shl64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 9) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_mask_sub :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 10) =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_sload_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 11) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_sload :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 12) =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_shift_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 13) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_shift_shr192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 15) =
      some (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_and :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 16) =
      some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 17) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementCheckedAddOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_body_checked_add_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementBodyOffset + 19) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_body_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementWriteBodyOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_write_body_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementWriteBodyOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_setvalue_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_setvalue_shl :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 3) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_push1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 4) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 1, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 6) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_push64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 7) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 64, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_shl64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 9) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_sub :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 10) =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 11) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_shl192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 13) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_mask_not :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 14) =
      some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_sload_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 15) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_sload :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 16) =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_and :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 17) =
      some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_or :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 18) =
      some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_sstore_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 19) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_sstore :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 20) =
      some (.StackMemFlow
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_write_body_return_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementWriteBodyOffset + 21) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementCheckedAddOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_checked_add_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementCheckedAddOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_dup2_a :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 1) =
      some (.Dup counterDup2Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 2) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_not :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 3) =
      some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_sub :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 4) =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_dup2_b :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 5) =
      some (.Dup counterDup2Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_gt :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 6) =
      some (.CompBit (.GT : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_revert_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 7) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementOverflowRevertOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_jumpi :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 9) =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_add :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 10) =
      some (.StopArith (.ADD : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_swap1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 11) =
      some (.Swap counterSwap1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_checked_add_return_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementCheckedAddOffset + 12) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_overflow_revert_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterIncrementOverflowRevertOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_increment_overflow_revert_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterIncrementOverflowRevertOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_overflow_revert_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementOverflowRevertOffset + 1) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_overflow_revert_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementOverflowRevertOffset + 2) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_increment_overflow_revert :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterIncrementOverflowRevertOffset + 3) =
      some (.System
        (.REVERT : EvmSemantics.Operation.SystemOps), none) := by
  native_decide

def counterInitializeReturnOffset : Nat := 66

def counterInitializeTrampolineBytes : ByteArray :=
  ByteArray.mk #[0x5b, 0x60, 0x42, 0x60, 0x46, 0x56]

theorem counterInitializeTrampolineBytes_size :
    counterInitializeTrampolineBytes.size = 6 := by
  native_decide

theorem counterCompiledRuntimeCode_has_initialize_trampoline :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterInitializeTrampolineBytes counterInitializeTrampolineOffset = true := by
  native_decide

def counterInitializeBodyOffset : Nat := 70

def counterInitializeBodyBytes : ByteArray :=
  ByteArray.mk #[
    0x5b, 0x5f, 0x60, 0xc0, 0x1b, 0x60, 0x01, 0x80, 0x60, 0x40, 0x1b,
    0x03, 0x60, 0xc0, 0x1b, 0x19, 0x5f, 0x54, 0x16, 0x17, 0x5f, 0x55,
    0x56
  ]

theorem counterInitializeBodyBytes_size :
    counterInitializeBodyBytes.size = 23 := by
  native_decide

theorem counterCompiledRuntimeCode_has_initialize_body :
    byteArrayHasSliceAt counterCompiledRuntimeCode
      counterInitializeBodyBytes counterInitializeBodyOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterInitializeTrampolineOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_initialize_trampoline_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterInitializeTrampolineOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_trampoline_return_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeTrampolineOffset + 1) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_trampoline_body_push :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeTrampolineOffset + 3) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_trampoline_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeTrampolineOffset + 5) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_body_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterInitializeBodyOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_initialize_body_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterInitializeBodyOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_first_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 1) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_setvalue_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 2) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_setvalue_shl :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 4) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_push1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 5) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 1, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 7) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_push64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 8) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 64, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_shl64 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 10) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_sub :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 11) =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_push192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 12) =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_shl192 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 14) =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_mask_not :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 15) =
      some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_sload_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 16) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_sload :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 17) =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_and :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 18) =
      some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_or :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 19) =
      some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_sstore_slot_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 20) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_sstore :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 21) =
      some (.StackMemFlow
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_body_return_jump :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeBodyOffset + 22) =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_valid_initialize_return_jumpdest :
    EvmSemantics.EVM.Decode.isValidJumpDest counterCompiledRuntimeCode
        counterInitializeReturnOffset = true := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_return_jumpdest :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        counterInitializeReturnOffset =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_return_push0 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeReturnOffset + 1) =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_return_dup1 :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeReturnOffset + 2) =
      some (.Dup counterDup1Op, none) := by
  native_decide

theorem counterCompiledRuntimeCode_decodes_initialize_return :
    EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode
        (counterInitializeReturnOffset + 3) =
      some (.System
        (.RETURN : EvmSemantics.Operation.SystemOps), none) := by
  native_decide

def counterCompiledStateAt (state : EvmState) (pc : Nat) : Prop :=
  state.executionEnv.code = counterCompiledRuntimeCode ∧
    state.pc = EvmSemantics.UInt256.ofNat pc ∧
    EvmSemantics.Fork.Shanghai ≤ state.executionEnv.fork

theorem counterReadyOpcodeAt_of_compiledStateAt
    {state : EvmState}
    {pc : Nat} {op : EvmSemantics.Operation}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hat : counterCompiledStateAt state pc)
    (hpcNat : (EvmSemantics.UInt256.ofNat pc).toNat = pc)
    (hdecode :
      EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode pc =
        some (op, argOpt))
    (hready : counterStepFEReady state op)
    (havailable : op.availableInFork state.executionEnv.fork = true) :
    ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
      counterCompiledRuntimeCode pc op argOpt state := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  exact
    { decoded :=
        { codePc := ⟨hcode, hpc⟩
          pcNat := hpcNat
          decodedAt := hdecode
          available := havailable }
      ready := counterStepFEReady_to_powdr hready }

theorem counterState_decoded_of_code_pc
    {state : EvmState}
    {pc : Nat} {op : EvmSemantics.Operation}
    {argOpt : Option (EvmSemantics.UInt256 × Nat)}
    (hcode : state.executionEnv.code = counterCompiledRuntimeCode)
    (hpc : state.pc = EvmSemantics.UInt256.ofNat pc)
    (hpcNat : (EvmSemantics.UInt256.ofNat pc).toNat = pc)
    (hdecode :
      EvmSemantics.EVM.Decode.decodeAt counterCompiledRuntimeCode pc =
        some (op, argOpt))
    (havailable : op.availableInFork state.executionEnv.fork = true) :
    state.decoded =
      some (op, argOpt) := by
  unfold EvmSemantics.EVM.State.decoded
  rw [hcode, hpc, hpcNat, hdecode]
  change (if op.availableInFork state.executionEnv.fork then some (op, argOpt)
    else none) = some (op, argOpt)
  simp [havailable]

theorem counterPreparedDispatcherFirstPush0_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 0) :
    state.decoded =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 0).toNat = 0 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_first_push0 havailable

theorem counterPreparedDispatcherFirstPush0_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 0)
    (hready : counterStepFEReady state (.Push counterPush0Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush0Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: state.stack)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 0).toNat = 0 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    rcases hat with ⟨_hcode, _hpc, hfork⟩
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 0 (.Push counterPush0Op)
        (some (EvmSemantics.UInt256.ofNat 0, 0)) state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_first_push0
      hready havailable
  simpa using
    (ProofForge.Backend.Evm.PowdrExec.reduction_push0_at_ok
      (op := counterPush0Op)
      (argOpt := some (EvmSemantics.UInt256.ofNat 0, 0))
      hreadyAt (by native_decide))

theorem counterPreparedDispatcherCalldataload_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 1) :
    state.decoded =
      some (.Env
        (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 1).toNat = 1 := by
    native_decide
  have havailable :
      ((.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_calldataload havailable

theorem counterPreparedDispatcherCalldataload_reduction
    {state : EvmState} {offset : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 1)
    (hready :
      counterStepFEReady state
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstack : state.stack = offset :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              state.executionEnv.calldata offset.toNat 32)) :: rest)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 1).toNat = 1 := by
    native_decide
  have havailable :
      ((.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_calldataload
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_calldataload_at_ok
    hreadyAt hstack

theorem counterPreparedDispatcherSelectorShiftPush224_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 2) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 224, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 2).toNat = 2 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_selector_shift_push224 havailable

theorem counterPreparedDispatcherSelectorShiftPush224_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 2)
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 224 :: state.stack) (pcΔ := 2)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 2).toNat = 2 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 2 (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat 224, 1)) state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_selector_shift_push224
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op) (value := EvmSemantics.UInt256.ofNat 224)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedDispatcherSelectorShr_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 4) :
    state.decoded =
      some (.CompBit
        (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 4).toNat = 4 := by
    native_decide
  have hconstantinople :
      EvmSemantics.Fork.Constantinople ≤ state.executionEnv.fork := by
    change EvmSemantics.Fork.Shanghai.toOrd ≤
      state.executionEnv.fork.toOrd at hfork
    change EvmSemantics.Fork.Constantinople.toOrd ≤
      state.executionEnv.fork.toOrd
    exact Nat.le_trans (by decide) hfork
  have havailable :
      ((.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, hconstantinople]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_selector_shr havailable

theorem counterPreparedDispatcherSelectorShr_reduction
    {state : EvmState}
    {shift value : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 4)
    (hready :
      counterStepFEReady state
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstack : state.stack = shift :: value :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight value shift :: rest)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 4).toNat = 4 := by
    native_decide
  have hconstantinople :
      EvmSemantics.Fork.Constantinople ≤ state.executionEnv.fork := by
    change EvmSemantics.Fork.Shanghai.toOrd ≤
      state.executionEnv.fork.toOrd at hfork
    change EvmSemantics.Fork.Constantinople.toOrd ≤
      state.executionEnv.fork.toOrd
    exact Nat.le_trans (by decide) hfork
  have havailable :
      ((.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, hconstantinople]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 4
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt ⟨hcode, hpc, hfork⟩ hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_selector_shr
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_shr_at_ok
    hreadyAt hstack

theorem counterPreparedDispatcherSelectorDup1_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 5) :
    state.decoded = some (.Dup counterDup1Op, none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 5).toNat = 5 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_selector_dup1 havailable

theorem counterPreparedDispatcherSelectorDup1_reduction
    {state : EvmState} {value : EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 5)
    (hready : counterStepFEReady state (.Dup counterDup1Op))
    (hindex : state.stack[counterDup1Op.idx.val]? = some value) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Dup counterDup1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (value :: state.stack)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 5).toNat = 5 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 5 (.Dup counterDup1Op) none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_selector_dup1
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_dup_at_ok
    hreadyAt hindex

theorem counterPreparedDispatcherInitializeSelectorPush4_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 6) :
    state.decoded =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 6).toNat = 6 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_initialize_selector_push4 havailable

theorem counterPreparedDispatcherInitializeSelectorPush4_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 6)
    (hready : counterStepFEReady state (.Push counterPush4Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush4Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: state.stack)
        (pcΔ := 5)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 6).toNat = 6 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 6 (.Push counterPush4Op)
        (some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_initialize_selector_push4
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush4Op)
    (value := EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
    (argBytes := 4) (widthPred := 3) hreadyAt (by native_decide)

theorem counterPreparedDispatcherInitializeEq_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 11) :
    state.decoded =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 11).toNat = 11 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_initialize_eq havailable

theorem counterPreparedDispatcherInitializeEq_reduction
    {state : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 11)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstack : state.stack = a :: b :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 11).toNat = 11 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 11
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_initialize_eq
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_eq_at_ok
    hreadyAt hstack

theorem counterPreparedDispatcherInitializeTrampolinePush_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 12) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 12).toNat = 12 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_initialize_trampoline_push havailable

theorem counterPreparedDispatcherInitializeTrampolinePush_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 12)
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset ::
          state.stack)
        (pcΔ := 2)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 12).toNat = 12 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 12 (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset, 1))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_initialize_trampoline_push
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op)
    (value := EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedDispatcherInitializeJumpi_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 14) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 14).toNat = 14 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_initialize_jumpi havailable

theorem counterPreparedDispatcherInitializeJumpiTaken_reduction
    {state : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 14)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest
        counterCompiledRuntimeCode dest.toNat = true) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas with
        pc := dest
        stack := rest } := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 14).toNat = 14 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 14
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_initialize_jumpi
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpi_taken_at_ok
    hreadyAt hstack hcond hvalid

theorem counterPreparedDispatcherInitializeJumpiNotTaken_reduction
    {state : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 14)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas).replaceStackAndIncrPC
        rest) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 14).toNat = 14 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 14
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_initialize_jumpi
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpi_not_taken_at_ok
    hreadyAt hstack hcond

theorem counterPreparedDispatcherIncrementSelectorDup1_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 15) :
    state.decoded = some (.Dup counterDup1Op, none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 15).toNat = 15 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_dup1
    havailable

theorem counterPreparedDispatcherIncrementSelectorDup1_reduction
    {state : EvmState}
    {top : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 15)
    (hready : counterStepFEReady state (.Dup counterDup1Op))
    (hstack : state.stack = top :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Dup counterDup1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC (top :: top :: rest)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 15).toNat = 15 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 15 (.Dup counterDup1Op) none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_dup1
      hready havailable
  have hindex : state.stack[counterDup1Op.idx.val]? = some top := by
    simp [counterDup1Op, hstack]
  simpa [hstack] using
    ProofForge.Backend.Evm.PowdrExec.reduction_dup_at_ok
      hreadyAt hindex

theorem counterPreparedDispatcherIncrementSelectorPush4_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 16) :
    state.decoded =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat, 4)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 16).toNat = 16 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_push4
    havailable

theorem counterPreparedDispatcherIncrementSelectorPush4_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 16)
    (hready : counterStepFEReady state (.Push counterPush4Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush4Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat :: state.stack)
        (pcΔ := 5)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 16).toNat = 16 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 16 (.Push counterPush4Op)
        (some (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat, 4))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_selector_push4
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush4Op)
    (value := EvmSemantics.UInt256.ofNat counterIncrementSelectorNat)
    (argBytes := 4) (widthPred := 3) hreadyAt (by native_decide)

theorem counterPreparedDispatcherIncrementEq_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 21) :
    state.decoded =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 21).toNat = 21 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_increment_eq havailable

theorem counterPreparedDispatcherIncrementEq_reduction
    {state : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 21)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstack : state.stack = a :: b :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 21).toNat = 21 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 21
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_eq
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_eq_at_ok
    hreadyAt hstack

theorem counterPreparedDispatcherIncrementTrampolinePush_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 22) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 22).toNat = 22 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_increment_trampoline_push
    havailable

theorem counterPreparedDispatcherIncrementTrampolinePush_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 22)
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset ::
          state.stack)
        (pcΔ := 2)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 22).toNat = 22 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 22 (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset, 1))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_trampoline_push
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op)
    (value := EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedDispatcherIncrementJumpi_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 24) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 24).toNat = 24 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_increment_jumpi
    havailable

theorem counterPreparedDispatcherIncrementJumpiTaken_reduction
    {state : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 24)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest
        counterCompiledRuntimeCode dest.toNat = true) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas with
        pc := dest
        stack := rest } := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 24).toNat = 24 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 24
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_jumpi
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpi_taken_at_ok
    hreadyAt hstack hcond hvalid

theorem counterPreparedDispatcherIncrementJumpiNotTaken_reduction
    {state : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 24)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat = 0) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas).replaceStackAndIncrPC
        rest) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 24).toNat = 24 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 24
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_increment_jumpi
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpi_not_taken_at_ok
    hreadyAt hstack hcond

theorem counterPreparedDispatcherGetSelectorPush4_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 25) :
    state.decoded =
      some (.Push counterPush4Op,
        some (EvmSemantics.UInt256.ofNat counterGetSelectorNat, 4)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 25).toNat = 25 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_get_selector_push4
    havailable

theorem counterPreparedDispatcherGetSelectorPush4_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 25)
    (hready : counterStepFEReady state (.Push counterPush4Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush4Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterGetSelectorNat :: state.stack)
        (pcΔ := 5)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 25).toNat = 25 := by
    native_decide
  have havailable :
      ((.Push counterPush4Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush4Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 25 (.Push counterPush4Op)
        (some (EvmSemantics.UInt256.ofNat counterGetSelectorNat, 4))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_get_selector_push4
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush4Op)
    (value := EvmSemantics.UInt256.ofNat counterGetSelectorNat)
    (argBytes := 4) (widthPred := 3) hreadyAt (by native_decide)

theorem counterPreparedDispatcherGetEq_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 30) :
    state.decoded =
      some (.CompBit
        (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 30).toNat = 30 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_get_eq havailable

theorem counterPreparedDispatcherGetEq_reduction
    {state : EvmState}
    {a b : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 30)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstack : state.stack = a :: b :: rest) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.eq a b :: rest)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 30).toNat = 30 := by
    native_decide
  have havailable :
      ((.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 30
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_get_eq
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_eq_at_ok
    hreadyAt hstack

theorem counterPreparedDispatcherGetTrampolinePush_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 31) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 31).toNat = 31 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_get_trampoline_push
    havailable

theorem counterPreparedDispatcherGetTrampolinePush_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state 31)
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset ::
          state.stack)
        (pcΔ := 2)) := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 31).toNat = 31 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 31 (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset, 1))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_get_trampoline_push
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op)
    (value := EvmSemantics.UInt256.ofNat counterGetTrampolineOffset)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedDispatcherGetJumpi_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state 33) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat : (EvmSemantics.UInt256.ofNat 33).toNat = 33 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_dispatcher_get_jumpi havailable

theorem counterPreparedDispatcherGetJumpiTaken_reduction
    {state : EvmState}
    {dest cond : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state 33)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest
        counterCompiledRuntimeCode dest.toNat = true) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas with
        pc := dest
        stack := rest } := by
  have hpcNat : (EvmSemantics.UInt256.ofNat 33).toNat = 33 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode 33
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_dispatcher_get_jumpi
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpi_taken_at_ok
    hreadyAt hstack hcond hvalid

theorem counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = rest)
    (hat : counterCompiledStateAt state 0)
    (hready : counterStepFEReady state (.Push counterPush0Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 1 ∧
      nextState.decoded =
        some (.Env
          (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none) ∧
      nextState.stack = EvmSemantics.UInt256.ofNat 0 :: rest ∧
      nextState.executionEnv.calldata = state.executionEnv.calldata := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push0_ok hrunning hprecompile
      (counterPreparedDispatcherFirstPush0_decoded hat) hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 1 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherCalldataload_decoded hnextAt, ?_, ?_⟩
  · rw [hstate]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]
  · rw [hstate]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]

theorem counterState_of_dispatcher_calldataload_stepFE_to_shift_push_for_call_ok
    {state nextState : EvmState}
    {call : CounterCall}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = EvmSemantics.UInt256.ofNat 0 :: rest)
    (hcalldata : state.executionEnv.calldata = counterCallCalldata call)
    (hat : counterCompiledStateAt state 1)
    (hready :
      counterStepFEReady state
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 2 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat 224, 1)) ∧
      nextState.stack = counterCallCalldataWord call :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_env_calldataload_ok hrunning hprecompile
      (counterPreparedDispatcherCalldataload_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 2 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherSelectorShiftPush224_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hcalldata,
    counterUInt256_ofNat_zero_toNat, counterCall_calldataload_zero_eq]

theorem counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = EvmSemantics.UInt256.ofNat 0 :: rest)
    (hcalldata : state.executionEnv.calldata = counterCallCalldata .initialize)
    (hat : counterCompiledStateAt state 1)
    (hready :
      counterStepFEReady state
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 2 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat 224, 1)) ∧
      nextState.stack = counterInitializeCalldataWord :: rest := by
  simpa [counterInitializeCalldataWord_eq] using
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_for_call_ok
      (call := .initialize) hstack hcalldata hat hready hstep

theorem counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_for_word_ok
    {state nextState : EvmState}
    {word : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = word :: rest)
    (hat : counterCompiledStateAt state 2)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 4 ∧
      nextState.decoded =
        some (.CompBit
          (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat 224 :: word :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push1_ok hrunning hprecompile
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat) hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 4 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherSelectorShr_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = counterInitializeCalldataWord :: rest)
    (hat : counterCompiledStateAt state 2)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 4 ∧
      nextState.decoded =
        some (.CompBit
          (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat 224 :: counterInitializeCalldataWord ::
          rest := by
  exact
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_for_word_ok
      (word := counterInitializeCalldataWord) hstack hat hready hstep

theorem counterState_of_dispatcher_selector_shr_stepFE_to_dup_for_call_ok
    {state nextState : EvmState}
    {call : CounterCall}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat 224 :: counterCallCalldataWord call :: rest)
    (hat : counterCompiledStateAt state 4)
    (hready :
      counterStepFEReady state
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 5 ∧
      nextState.decoded = some (.Dup counterDup1Op, none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_compBit_shr_ok hrunning hprecompile
      (counterPreparedDispatcherSelectorShr_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 5 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherSelectorDup1_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack,
    counterCall_selector_shr224_eq]

theorem counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat 224 :: counterInitializeCalldataWord :: rest)
    (hat : counterCompiledStateAt state 4)
    (hready :
      counterStepFEReady state
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 5 ∧
      nextState.decoded = some (.Dup counterDup1Op, none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  simpa [counterInitializeCalldataWord_eq, counterInitializeSelectorNat_eq] using
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_for_call_ok
      (call := .initialize)
      (hstack := by
        simpa [counterInitializeCalldataWord_eq] using hstack)
      hat hready hstep

theorem counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_for_call_ok
    {state nextState : EvmState}
    {call : CounterCall}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: rest)
    (hat : counterCompiledStateAt state 5)
    (hready : counterStepFEReady state (.Dup counterDup1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 6 ∧
      nextState.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) ::
          EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_dup1_ok hrunning hprecompile
      (counterPreparedDispatcherSelectorDup1_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 6 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherInitializeSelectorPush4_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest)
    (hat : counterCompiledStateAt state 5)
    (hready : counterStepFEReady state (.Dup counterDup1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 6 ∧
      nextState.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  simpa [counterInitializeSelectorNat_eq] using
    counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_for_call_ok
      (call := .initialize)
      (hstack := by
        simpa [counterInitializeSelectorNat_eq] using hstack)
      hat hready hstep

theorem counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_for_actual_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        actualSelector :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 6)
    (hready : counterStepFEReady state (.Push counterPush4Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 11 ∧
      nextState.decoded =
        some (.CompBit
          (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          actualSelector :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push4_ok hrunning hprecompile
      (counterPreparedDispatcherInitializeSelectorPush4_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 11 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherInitializeEq_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest)
    (hat : counterCompiledStateAt state 6)
    (hready : counterStepFEReady state (.Push counterPush4Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 11 ∧
      nextState.decoded =
        some (.CompBit
          (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  exact
    counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_for_actual_ok
      (actualSelector := EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
      hstack hat hready hstep

theorem counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_for_actual_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          actualSelector :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 11)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 12 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset, 1)) ∧
      nextState.stack =
        EvmSemantics.UInt256.eq
          (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
          actualSelector :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_compBit_eq_ok hrunning hprecompile
      (counterPreparedDispatcherInitializeEq_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 12 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherInitializeTrampolinePush_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest)
    (hat : counterCompiledStateAt state 11)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 12 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset, 1)) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  simpa [counterInitialize_selector_eq_true] using
    counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_for_actual_ok
      (actualSelector := EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
      hstack hat hready hstep

theorem counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_for_actual_ok
    {state nextState : EvmState}
    {cond actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack = cond :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 12)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 14 ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset ::
          cond :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push1_ok hrunning hprecompile
      (counterPreparedDispatcherInitializeTrampolinePush_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 14 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherInitializeJumpi_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest)
    (hat : counterCompiledStateAt state 12)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 14 ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset ::
          EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  exact
    counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_for_actual_ok
      (cond := EvmSemantics.UInt256.ofNat 1)
      (actualSelector := EvmSemantics.UInt256.ofNat counterInitializeSelectorNat)
      hstack hat hready hstep

theorem counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset ::
          EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest)
    (hat : counterCompiledStateAt state 14)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState counterInitializeTrampolineOffset ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hdestNat :
      (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        counterInitializeTrampolineOffset := by
    native_decide
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        true := by
    rw [hcode, hdestNat]
    exact counterCompiledRuntimeCode_valid_initialize_trampoline_jumpdest
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning hprecompile
      (counterPreparedDispatcherInitializeJumpi_decoded ⟨hcode, hpc, hfork⟩)
      hstack counterInitialize_selector_condition_nonzero hvalid hstackOk hgas hstep
  have hnextAt :
      counterCompiledStateAt nextState counterInitializeTrampolineOffset := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, hcode]
    · constructor
      · simp
      · simpa [EvmSemantics.EVM.State.consumeGas] using hfork
  have hdecodedNext :
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
    rcases hnextAt with ⟨hcodeNext, hpcNext, _hforkNext⟩
    have hpcNat :
        (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
          counterInitializeTrampolineOffset := by
      native_decide
    have havailable :
        ((.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation).availableInFork nextState.executionEnv.fork) =
          true := by
      simp [EvmSemantics.Operation.availableInFork]
    exact counterState_decoded_of_code_pc hcodeNext hpcNext hpcNat
      counterCompiledRuntimeCode_decodes_initialize_trampoline_jumpdest havailable
  refine ⟨hnextAt, hdecodedNext, ?_⟩
  rw [hstate]

theorem counterState_of_dispatcher_initialize_jumpi_not_taken_stepFE_to_increment_dup_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset ::
          EvmSemantics.UInt256.ofNat 0 :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 14)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 15 ∧
      nextState.decoded = some (.Dup counterDup1Op, none) ∧
      nextState.stack = actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hcond : (EvmSemantics.UInt256.ofNat 0).toNat = 0 := by
    native_decide
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_not_taken_ok
      hrunning hprecompile
      (counterPreparedDispatcherInitializeJumpi_decoded hat)
      hstack hcond hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 15 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherIncrementSelectorDup1_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_increment_selector_dup_stepFE_to_selector_push_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = actualSelector :: rest)
    (hat : counterCompiledStateAt state 15)
    (hready : counterStepFEReady state (.Dup counterDup1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 16 ∧
      nextState.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat, 4)) ∧
      nextState.stack = actualSelector :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_dup1_ok hrunning hprecompile
      (counterPreparedDispatcherIncrementSelectorDup1_decoded hat)
      hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 16 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherIncrementSelectorPush4_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_increment_selector_push_stepFE_to_eq_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = actualSelector :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 16)
    (hready : counterStepFEReady state (.Push counterPush4Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 21 ∧
      nextState.decoded =
        some (.CompBit
          (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterIncrementSelectorNat ::
          actualSelector :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push4_ok hrunning hprecompile
      (counterPreparedDispatcherIncrementSelectorPush4_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 21 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherIncrementEq_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_increment_eq_stepFE_to_trampoline_push_for_actual_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterIncrementSelectorNat ::
          actualSelector :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 21)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 22 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset, 1)) ∧
      nextState.stack =
        EvmSemantics.UInt256.eq
          (EvmSemantics.UInt256.ofNat counterIncrementSelectorNat)
          actualSelector :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_compBit_eq_ok hrunning hprecompile
      (counterPreparedDispatcherIncrementEq_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 22 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherIncrementTrampolinePush_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_increment_trampoline_push_stepFE_to_jumpi_ok
    {state nextState : EvmState}
    {cond actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = cond :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 22)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 24 ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset ::
          cond :: actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push1_ok hrunning hprecompile
      (counterPreparedDispatcherIncrementTrampolinePush_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 24 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherIncrementJumpi_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterPreparedIncrementTrampolineJumpdest_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state counterIncrementTrampolineOffset) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset).toNat =
        counterIncrementTrampolineOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_increment_trampoline_jumpdest havailable

theorem counterState_of_dispatcher_increment_jumpi_stepFE_to_trampoline_ok
    {state nextState : EvmState}
    {cond actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset ::
          cond :: actualSelector :: rest)
    (hcond : cond.toNat ≠ 0)
    (hat : counterCompiledStateAt state 24)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState counterIncrementTrampolineOffset ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack = actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hdestNat :
      (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset).toNat =
        counterIncrementTrampolineOffset := by
    native_decide
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset).toNat =
        true := by
    rw [hcode, hdestNat]
    exact counterCompiledRuntimeCode_valid_increment_trampoline_jumpdest
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning hprecompile
      (counterPreparedDispatcherIncrementJumpi_decoded ⟨hcode, hpc, hfork⟩)
      hstack hcond hvalid hstackOk hgas hstep
  have hnextAt :
      counterCompiledStateAt nextState counterIncrementTrampolineOffset := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, hcode]
    · constructor
      · simp
      · simpa [EvmSemantics.EVM.State.consumeGas] using hfork
  refine ⟨hnextAt, counterPreparedIncrementTrampolineJumpdest_decoded hnextAt, ?_⟩
  rw [hstate]

theorem counterState_of_dispatcher_increment_jumpi_not_taken_stepFE_to_get_push_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterIncrementTrampolineOffset ::
          EvmSemantics.UInt256.ofNat 0 :: actualSelector :: rest)
    (hat : counterCompiledStateAt state 24)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 25 ∧
      nextState.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterGetSelectorNat, 4)) ∧
      nextState.stack = actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hcond : (EvmSemantics.UInt256.ofNat 0).toNat = 0 := by
    native_decide
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_not_taken_ok
      hrunning hprecompile
      (counterPreparedDispatcherIncrementJumpi_decoded hat)
      hstack hcond hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 25 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherGetSelectorPush4_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_get_selector_push_stepFE_to_eq_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = actualSelector :: rest)
    (hat : counterCompiledStateAt state 25)
    (hready : counterStepFEReady state (.Push counterPush4Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 30 ∧
      nextState.decoded =
        some (.CompBit
          (.EQ : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterGetSelectorNat ::
          actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push4_ok hrunning hprecompile
      (counterPreparedDispatcherGetSelectorPush4_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 30 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherGetEq_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_get_eq_stepFE_to_trampoline_push_for_actual_ok
    {state nextState : EvmState}
    {actualSelector : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterGetSelectorNat ::
          actualSelector :: rest)
    (hat : counterCompiledStateAt state 30)
    (hready :
      counterStepFEReady state
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 31 ∧
      nextState.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset, 1)) ∧
      nextState.stack =
        EvmSemantics.UInt256.eq
          (EvmSemantics.UInt256.ofNat counterGetSelectorNat)
          actualSelector :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_compBit_eq_ok hrunning hprecompile
      (counterPreparedDispatcherGetEq_decoded hat) hstack hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 31 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherGetTrampolinePush_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterState_of_dispatcher_get_trampoline_push_stepFE_to_jumpi_ok
    {state nextState : EvmState}
    {cond : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = cond :: rest)
    (hat : counterCompiledStateAt state 31)
    (hready : counterStepFEReady state (.Push counterPush1Op))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState 33 ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPI : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack =
        EvmSemantics.UInt256.ofNat counterGetTrampolineOffset ::
          cond :: rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_push1_ok hrunning hprecompile
      (counterPreparedDispatcherGetTrampolinePush_decoded hat)
      hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState 33 := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork
  refine ⟨hnextAt, counterPreparedDispatcherGetJumpi_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas,
    EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack]

theorem counterPreparedGetTrampolineJumpdest_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state counterGetTrampolineOffset) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset).toNat =
        counterGetTrampolineOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_get_trampoline_jumpdest havailable

theorem counterState_of_dispatcher_get_jumpi_stepFE_to_trampoline_ok
    {state nextState : EvmState}
    {cond : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hstack :
      state.stack =
        EvmSemantics.UInt256.ofNat counterGetTrampolineOffset :: cond :: rest)
    (hcond : cond.toNat ≠ 0)
    (hat : counterCompiledStateAt state 33)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState counterGetTrampolineOffset ∧
      nextState.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      nextState.stack = rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hdestNat :
      (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset).toNat =
        counterGetTrampolineOffset := by
    native_decide
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest state.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterGetTrampolineOffset).toNat =
        true := by
    rw [hcode, hdestNat]
    exact counterCompiledRuntimeCode_valid_get_trampoline_jumpdest
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning hprecompile
      (counterPreparedDispatcherGetJumpi_decoded ⟨hcode, hpc, hfork⟩)
      hstack hcond hvalid hstackOk hgas hstep
  have hnextAt :
      counterCompiledStateAt nextState counterGetTrampolineOffset := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, hcode]
    · constructor
      · simp
      · simpa [EvmSemantics.EVM.State.consumeGas] using hfork
  refine ⟨hnextAt, counterPreparedGetTrampolineJumpdest_decoded hnextAt, ?_⟩
  rw [hstate]

theorem counterPreparedInitializeTrampolineJumpdest_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state counterInitializeTrampolineOffset) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        counterInitializeTrampolineOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_trampoline_jumpdest havailable

theorem counterPreparedInitializeTrampolineReturnPush_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 1)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeTrampolineOffset + 1)).toNat =
        counterInitializeTrampolineOffset + 1 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_trampoline_return_push havailable

theorem counterPreparedInitializeTrampolineBodyPush_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 3)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeTrampolineOffset + 3)).toNat =
        counterInitializeTrampolineOffset + 3 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_trampoline_body_push havailable

theorem counterPreparedInitializeTrampolineJump_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 5)) :
    state.decoded =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeTrampolineOffset + 5)).toNat =
        counterInitializeTrampolineOffset + 5 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_trampoline_jump havailable

theorem counterPreparedInitializeBodyJumpdest_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state counterInitializeBodyOffset) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat =
        counterInitializeBodyOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_body_jumpdest havailable

theorem counterPreparedInitializeTrampolineJumpdest_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state counterInitializeTrampolineOffset)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).incrPC) := by
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        counterInitializeTrampolineOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode counterInitializeTrampolineOffset
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_initialize_trampoline_jumpdest
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpdest_at_ok hreadyAt

theorem counterPreparedInitializeTrampolineReturnPush_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 1))
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset ::
          state.stack)
        (pcΔ := 2)) := by
  have hpcNat :
      (EvmSemantics.UInt256.ofNat
        (counterInitializeTrampolineOffset + 1)).toNat =
        counterInitializeTrampolineOffset + 1 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode (counterInitializeTrampolineOffset + 1)
        (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset, 1))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_initialize_trampoline_return_push
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op)
    (value := EvmSemantics.UInt256.ofNat counterInitializeReturnOffset)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedInitializeTrampolineBodyPush_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 3))
    (hready : counterStepFEReady state (.Push counterPush1Op)) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.Push counterPush1Op : EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset :: state.stack)
        (pcΔ := 2)) := by
  have hpcNat :
      (EvmSemantics.UInt256.ofNat
        (counterInitializeTrampolineOffset + 3)).toNat =
        counterInitializeTrampolineOffset + 3 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode (counterInitializeTrampolineOffset + 3)
        (.Push counterPush1Op)
        (some (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset, 1))
        state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_initialize_trampoline_body_push
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_push_data_at_ok
    (op := counterPush1Op)
    (value := EvmSemantics.UInt256.ofNat counterInitializeBodyOffset)
    (argBytes := 1) (widthPred := 0) hreadyAt (by native_decide)

theorem counterPreparedInitializeTrampolineJump_reduction
    {state : EvmState}
    {dest : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state (counterInitializeTrampolineOffset + 5))
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstack : state.stack = dest :: rest)
    (hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest
        counterCompiledRuntimeCode dest.toNat = true) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      { state.consumeGas
          (EvmSemantics.EVM.Gas.baseCost state.fork
            (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
              EvmSemantics.Operation))
          (counterStepFEReady_to_powdr hready).gas with
        pc := dest
        stack := rest } := by
  have hpcNat :
      (EvmSemantics.UInt256.ofNat
        (counterInitializeTrampolineOffset + 5)).toNat =
        counterInitializeTrampolineOffset + 5 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode (counterInitializeTrampolineOffset + 5)
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_initialize_trampoline_jump
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jump_at_ok
    hreadyAt hstack hvalid

theorem counterPreparedInitializeBodyJumpdest_reduction
    {state : EvmState}
    (hat : counterCompiledStateAt state counterInitializeBodyOffset)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state
      ((state.consumeGas
        (EvmSemantics.EVM.Gas.baseCost state.fork
          (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
            EvmSemantics.Operation))
        (counterStepFEReady_to_powdr hready).gas
       ).incrPC) := by
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat =
        counterInitializeBodyOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  have hreadyAt :
      ProofForge.Backend.Evm.PowdrExec.ReadyOpcodeAt
        counterCompiledRuntimeCode counterInitializeBodyOffset
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
        none state :=
    counterReadyOpcodeAt_of_compiledStateAt hat hpcNat
      counterCompiledRuntimeCode_decodes_initialize_body_jumpdest
      hready havailable
  exact ProofForge.Backend.Evm.PowdrExec.reduction_jumpdest_at_ok hreadyAt

theorem counterState_of_initialize_trampoline_stepFE_to_body_ok
    {s0 s1 s2 s3 s4 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 counterInitializeTrampolineOffset)
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeTrampolineOffset + 1))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeTrampolineOffset + 3))
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeTrampolineOffset + 5))
    (hready3 :
      counterStepFEReady s3
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    counterCompiledStateAt s4 counterInitializeBodyOffset ∧
      s4.decoded =
        some (.StackMemFlow
          (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) ∧
      s4.stack = EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  have hstate1 :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning0 hprecompile0
      (counterPreparedInitializeTrampolineJumpdest_decoded hat0) hstackOk0
      hgas0 hstep0
  have hstack1 : s1.stack = rest := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC, h0]
  have hstate2 :=
    counterState_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeTrampolineReturnPush_decoded hat1) hstackOk1
      hgas1 hstep1
  have hstack2 :
      s2.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack1]
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedInitializeTrampolineBodyPush_decoded hat2) hstackOk2
      hgas2 hstep2
  have hstack3 :
      s3.stack =
        EvmSemantics.UInt256.ofNat counterInitializeBodyOffset ::
          EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack2]
  have hdecoded3 := counterPreparedInitializeTrampolineJump_decoded hat3
  rcases hat3 with ⟨hcode3, _hpc3, hfork3⟩
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s3.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat = true := by
    rw [hcode3]
    have hbodyNat :
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat =
          counterInitializeBodyOffset := by
      native_decide
    rw [hbodyNat]
    exact counterCompiledRuntimeCode_valid_initialize_body_jumpdest
  have hstate4 :=
    counterState_of_stepFE_stackMemFlow_jump_ok hrunning3 hprecompile3
      hdecoded3 hstack3 hvalid hstackOk3 hgas3 hstep3
  have hfinalAt : counterCompiledStateAt s4 counterInitializeBodyOffset := by
    unfold counterCompiledStateAt
    rw [hstate4]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, hcode3]
    · constructor
      · simp
      · simpa [EvmSemantics.EVM.State.consumeGas] using hfork3
  refine ⟨hfinalAt, counterPreparedInitializeBodyJumpdest_decoded hfinalAt, ?_⟩
  rw [hstate4]

theorem counterCallStack_of_initialize_trampoline_stepFE_to_body_ok
    {s0 s1 s2 s3 s4 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 counterInitializeTrampolineOffset)
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeTrampolineOffset + 1))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeTrampolineOffset + 3))
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeTrampolineOffset + 5))
    (hready3 :
      counterStepFEReady s3
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    s4.callStack = s0.callStack := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  have hstate1 :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning0 hprecompile0
      (counterPreparedInitializeTrampolineJumpdest_decoded hat0) hstackOk0
      hgas0 hstep0
  have hstack1 : s1.stack = rest := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC, h0]
  have hcallStack1 : s1.callStack = s0.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_jumpdest_ok hrunning0 hprecompile0
      (counterPreparedInitializeTrampolineJumpdest_decoded hat0) hstackOk0
      hgas0 hstep0
  have hstate2 :=
    counterState_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeTrampolineReturnPush_decoded hat1) hstackOk1
      hgas1 hstep1
  have hstack2 :
      s2.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack1]
  have hcallStack2 : s2.callStack = s1.callStack :=
    counterCallStack_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeTrampolineReturnPush_decoded hat1) hstackOk1
      hgas1 hstep1
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedInitializeTrampolineBodyPush_decoded hat2) hstackOk2
      hgas2 hstep2
  have hstack3 :
      s3.stack =
        EvmSemantics.UInt256.ofNat counterInitializeBodyOffset ::
          EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack2]
  have hcallStack3 : s3.callStack = s2.callStack :=
    counterCallStack_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedInitializeTrampolineBodyPush_decoded hat2) hstackOk2
      hgas2 hstep2
  have hdecoded3 := counterPreparedInitializeTrampolineJump_decoded hat3
  rcases hat3 with ⟨hcode3, _hpc3, _hfork3⟩
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s3.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat = true := by
    rw [hcode3]
    have hbodyNat :
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat =
          counterInitializeBodyOffset := by
      native_decide
    rw [hbodyNat]
    exact counterCompiledRuntimeCode_valid_initialize_body_jumpdest
  have hcallStack4 : s4.callStack = s3.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_jump_ok hrunning3 hprecompile3
      hdecoded3 hstack3 hvalid hstackOk3 hgas3 hstep3
  exact hcallStack4.trans
    (hcallStack3.trans (hcallStack2.trans hcallStack1))

theorem counterStorageValue_of_initialize_trampoline_stepFE_to_body_ok
    {s0 s1 s2 s3 s4 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 counterInitializeTrampolineOffset)
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeTrampolineOffset + 1))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeTrampolineOffset + 3))
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeTrampolineOffset + 5))
    (hready3 :
      counterStepFEReady s3
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    counterStorageValue counterContractAddress counterCountSlot s4 =
      counterStorageValue counterContractAddress counterCountSlot s0 := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  have hstate1 :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning0 hprecompile0
      (counterPreparedInitializeTrampolineJumpdest_decoded hat0) hstackOk0
      hgas0 hstep0
  have hstack1 : s1.stack = rest := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC, h0]
  have hstate2 :=
    counterState_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeTrampolineReturnPush_decoded hat1) hstackOk1
      hgas1 hstep1
  have hstack2 :
      s2.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack1]
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedInitializeTrampolineBodyPush_decoded hat2) hstackOk2
      hgas2 hstep2
  have hstack3 :
      s3.stack =
        EvmSemantics.UInt256.ofNat counterInitializeBodyOffset ::
          EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack2]
  have hdecoded3 := counterPreparedInitializeTrampolineJump_decoded hat3
  rcases hat3 with ⟨hcode3, _hpc3, _hfork3⟩
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s3.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat = true := by
    rw [hcode3]
    have hbodyNat :
        (EvmSemantics.UInt256.ofNat counterInitializeBodyOffset).toNat =
          counterInitializeBodyOffset := by
      native_decide
    rw [hbodyNat]
    exact counterCompiledRuntimeCode_valid_initialize_body_jumpdest
  have hstate4 :=
    counterState_of_stepFE_stackMemFlow_jump_ok hrunning3 hprecompile3
      hdecoded3 hstack3 hvalid hstackOk3 hgas3 hstep3
  simp [hstate4, hstate3, hstate2, hstate1]

theorem counterPreparedInitializeFirstPush0_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 1)) :
    state.decoded =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 1)).toNat =
        counterInitializeBodyOffset + 1 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_first_push0 havailable

theorem counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok
    {state nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstack : state.stack = rest)
    (hat : counterCompiledStateAt state counterInitializeBodyOffset)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState (counterInitializeBodyOffset + 1) ∧
      nextState.decoded =
        some (.Push counterPush0Op,
          some (EvmSemantics.UInt256.ofNat 0, 0)) ∧
      nextState.stack = rest := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  have hstate :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning hprecompile
      (counterPreparedInitializeBodyJumpdest_decoded hat) hstackOk hgas hstep
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hnextAt : counterCompiledStateAt nextState (counterInitializeBodyOffset + 1) := by
    unfold counterCompiledStateAt
    rw [hstate]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.incrPC, hcode]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC, hpc]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.incrPC] using hfork
  refine ⟨hnextAt, counterPreparedInitializeFirstPush0_decoded hnextAt, ?_⟩
  rw [hstate]
  simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC, hstack]

theorem counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hcalldata0 : s0.executionEnv.calldata = counterCallCalldata .initialize)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14) :
    counterCompiledStateAt s14 (counterInitializeBodyOffset + 1) ∧
      s14.decoded =
        some (.Push counterPush0Op,
          some (EvmSemantics.UInt256.ofNat 0, 0)) ∧
      s14.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: rest := by
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1From0⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      h0 hat0 hready0 hstep0
  have hcalldata1 : s1.executionEnv.calldata = counterCallCalldata .initialize := by
    rw [hcalldata1From0, hcalldata0]
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok
      hstack1 hcalldata1 hat1 hready1 hstep1
  obtain ⟨hat3, _hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok
      hstack2 hat2 hready2 hstep2
  obtain ⟨hat4, _hdecoded4, hstack4⟩ :=
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok
      hstack3 hat3 hready3 hstep3
  obtain ⟨hat5, _hdecoded5, hstack5⟩ :=
    counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok
      hstack4 hat4 hready4 hstep4
  obtain ⟨hat6, _hdecoded6, hstack6⟩ :=
    counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok
      hstack5 hat5 hready5 hstep5
  obtain ⟨hat7, _hdecoded7, hstack7⟩ :=
    counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok
      hstack6 hat6 hready6 hstep6
  obtain ⟨hat8, _hdecoded8, hstack8⟩ :=
    counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok
      hstack7 hat7 hready7 hstep7
  obtain ⟨hat9, _hdecoded9, hstack9⟩ :=
    counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok
      hstack8 hat8 hready8 hstep8
  obtain ⟨hat13, _hdecoded13, hstack13⟩ :=
    counterState_of_initialize_trampoline_stepFE_to_body_ok
      hstack9 hat9 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
  exact counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok
    hstack13 hat13 hready13 hstep13

theorem counterCallStack_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hcalldata0 : s0.executionEnv.calldata = counterCallCalldata .initialize)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14) :
    s14.callStack = s0.callStack := by
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1From0⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      h0 hat0 hready0 hstep0
  have hcalldata1 : s1.executionEnv.calldata = counterCallCalldata .initialize := by
    rw [hcalldata1From0, hcalldata0]
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok
      hstack1 hcalldata1 hat1 hready1 hstep1
  obtain ⟨hat3, _hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok
      hstack2 hat2 hready2 hstep2
  obtain ⟨hat4, _hdecoded4, hstack4⟩ :=
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok
      hstack3 hat3 hready3 hstep3
  obtain ⟨hat5, _hdecoded5, hstack5⟩ :=
    counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok
      hstack4 hat4 hready4 hstep4
  obtain ⟨hat6, _hdecoded6, hstack6⟩ :=
    counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok
      hstack5 hat5 hready5 hstep5
  obtain ⟨hat7, _hdecoded7, hstack7⟩ :=
    counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok
      hstack6 hat6 hready6 hstep6
  obtain ⟨hat8, _hdecoded8, hstack8⟩ :=
    counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok
      hstack7 hat7 hready7 hstep7
  obtain ⟨hat9, _hdecoded9, hstack9⟩ :=
    counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok
      hstack8 hat8 hready8 hstep8
  obtain ⟨hat13, _hdecoded13, hstack13⟩ :=
    counterState_of_initialize_trampoline_stepFE_to_body_ok
      hstack9 hat9 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  rcases hready5 with ⟨hrunning5, hprecompile5, hstackOk5, hgas5⟩
  rcases hready6 with ⟨hrunning6, hprecompile6, hstackOk6, hgas6⟩
  rcases hready7 with ⟨hrunning7, hprecompile7, hstackOk7, hgas7⟩
  rcases hready8 with ⟨hrunning8, hprecompile8, hstackOk8, hgas8⟩
  rcases hready13 with ⟨hrunning13, hprecompile13, hstackOk13, hgas13⟩
  have hcallStack1 : s1.callStack = s0.callStack :=
    counterCallStack_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  have hcallStack2 : s2.callStack = s1.callStack :=
    counterCallStack_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1) hstack1 hstackOk1
      hgas1 hstep1
  have hcallStack3 : s3.callStack = s2.callStack :=
    counterCallStack_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat2)
      hstackOk2 hgas2 hstep2
  have hcallStack4 : s4.callStack = s3.callStack :=
    counterCallStack_of_stepFE_compBit_shr_ok hrunning3 hprecompile3
      (counterPreparedDispatcherSelectorShr_decoded hat3) hstack3 hstackOk3
      hgas3 hstep3
  have hcallStack5 : s5.callStack = s4.callStack :=
    counterCallStack_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedDispatcherSelectorDup1_decoded hat4) hstack4 hstackOk4
      hgas4 hstep4
  have hcallStack6 : s6.callStack = s5.callStack :=
    counterCallStack_of_stepFE_push4_ok hrunning5 hprecompile5
      (counterPreparedDispatcherInitializeSelectorPush4_decoded hat5)
      hstackOk5 hgas5 hstep5
  have hcallStack7 : s7.callStack = s6.callStack :=
    counterCallStack_of_stepFE_compBit_eq_ok hrunning6 hprecompile6
      (counterPreparedDispatcherInitializeEq_decoded hat6) hstack6 hstackOk6
      hgas6 hstep6
  have hcallStack8 : s8.callStack = s7.callStack :=
    counterCallStack_of_stepFE_push1_ok hrunning7 hprecompile7
      (counterPreparedDispatcherInitializeTrampolinePush_decoded hat7)
      hstackOk7 hgas7 hstep7
  rcases hat8 with ⟨hcode8, _hpc8, _hfork8⟩
  have hdestNat :
      (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        counterInitializeTrampolineOffset := by
    native_decide
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s8.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        true := by
    rw [hcode8, hdestNat]
    exact counterCompiledRuntimeCode_valid_initialize_trampoline_jumpdest
  have hcallStack9 : s9.callStack = s8.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning8 hprecompile8
      (counterPreparedDispatcherInitializeJumpi_decoded ⟨hcode8, _hpc8, _hfork8⟩)
      hstack8 counterInitialize_selector_condition_nonzero hvalid hstackOk8 hgas8
      hstep8
  have hcallStack13 : s13.callStack = s9.callStack :=
    counterCallStack_of_initialize_trampoline_stepFE_to_body_ok
      hstack9 hat9 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
  have hcallStack14 : s14.callStack = s13.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_jumpdest_ok hrunning13 hprecompile13
      (counterPreparedInitializeBodyJumpdest_decoded hat13) hstackOk13 hgas13
      hstep13
  exact hcallStack14.trans
    (hcallStack13.trans
      (hcallStack9.trans
        (hcallStack8.trans
          (hcallStack7.trans
            (hcallStack6.trans
              (hcallStack5.trans
                (hcallStack4.trans
                  (hcallStack3.trans
                    (hcallStack2.trans hcallStack1)))))))))

theorem counterStorageValue_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hcalldata0 : s0.executionEnv.calldata = counterCallCalldata .initialize)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14) :
    counterStorageValue counterContractAddress counterCountSlot s14 =
      counterStorageValue counterContractAddress counterCountSlot s0 := by
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1From0⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      h0 hat0 hready0 hstep0
  have hcalldata1 : s1.executionEnv.calldata = counterCallCalldata .initialize := by
    rw [hcalldata1From0, hcalldata0]
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok
      hstack1 hcalldata1 hat1 hready1 hstep1
  obtain ⟨hat3, _hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok
      hstack2 hat2 hready2 hstep2
  obtain ⟨hat4, _hdecoded4, hstack4⟩ :=
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok
      hstack3 hat3 hready3 hstep3
  obtain ⟨hat5, _hdecoded5, hstack5⟩ :=
    counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok
      hstack4 hat4 hready4 hstep4
  obtain ⟨hat6, _hdecoded6, hstack6⟩ :=
    counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok
      hstack5 hat5 hready5 hstep5
  obtain ⟨hat7, _hdecoded7, hstack7⟩ :=
    counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok
      hstack6 hat6 hready6 hstep6
  obtain ⟨hat8, _hdecoded8, hstack8⟩ :=
    counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok
      hstack7 hat7 hready7 hstep7
  obtain ⟨hat9, _hdecoded9, hstack9⟩ :=
    counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok
      hstack8 hat8 hready8 hstep8
  obtain ⟨hat13, _hdecoded13, hstack13⟩ :=
    counterState_of_initialize_trampoline_stepFE_to_body_ok
      hstack9 hat9 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  rcases hready5 with ⟨hrunning5, hprecompile5, hstackOk5, hgas5⟩
  rcases hready6 with ⟨hrunning6, hprecompile6, hstackOk6, hgas6⟩
  rcases hready7 with ⟨hrunning7, hprecompile7, hstackOk7, hgas7⟩
  rcases hready8 with ⟨hrunning8, hprecompile8, hstackOk8, hgas8⟩
  rcases hready13 with ⟨hrunning13, hprecompile13, hstackOk13, hgas13⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  have hstate2 :=
    counterState_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1) hstack1 hstackOk1
      hgas1 hstep1
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat2)
      hstackOk2 hgas2 hstep2
  have hstate4 :=
    counterState_of_stepFE_compBit_shr_ok hrunning3 hprecompile3
      (counterPreparedDispatcherSelectorShr_decoded hat3) hstack3 hstackOk3
      hgas3 hstep3
  have hstate5 :=
    counterState_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedDispatcherSelectorDup1_decoded hat4) hstack4 hstackOk4
      hgas4 hstep4
  have hstate6 :=
    counterState_of_stepFE_push4_ok hrunning5 hprecompile5
      (counterPreparedDispatcherInitializeSelectorPush4_decoded hat5)
      hstackOk5 hgas5 hstep5
  have hstate7 :=
    counterState_of_stepFE_compBit_eq_ok hrunning6 hprecompile6
      (counterPreparedDispatcherInitializeEq_decoded hat6) hstack6 hstackOk6
      hgas6 hstep6
  have hstate8 :=
    counterState_of_stepFE_push1_ok hrunning7 hprecompile7
      (counterPreparedDispatcherInitializeTrampolinePush_decoded hat7)
      hstackOk7 hgas7 hstep7
  rcases hat8 with ⟨hcode8, _hpc8, _hfork8⟩
  have hdestNat :
      (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        counterInitializeTrampolineOffset := by
    native_decide
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s8.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeTrampolineOffset).toNat =
        true := by
    rw [hcode8, hdestNat]
    exact counterCompiledRuntimeCode_valid_initialize_trampoline_jumpdest
  have hstate9 :=
    counterState_of_stepFE_stackMemFlow_jumpi_taken_ok hrunning8 hprecompile8
      (counterPreparedDispatcherInitializeJumpi_decoded ⟨hcode8, _hpc8, _hfork8⟩)
      hstack8 counterInitialize_selector_condition_nonzero hvalid hstackOk8 hgas8
      hstep8
  have hstorage9 :
      counterStorageValue counterContractAddress counterCountSlot s9 =
        counterStorageValue counterContractAddress counterCountSlot s0 := by
    simp [hstate9, hstate8, hstate7, hstate6, hstate5, hstate4, hstate3,
      hstate2, hstate1]
  have hstorage13 :
      counterStorageValue counterContractAddress counterCountSlot s13 =
        counterStorageValue counterContractAddress counterCountSlot s9 :=
    counterStorageValue_of_initialize_trampoline_stepFE_to_body_ok
      hstack9 hat9 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
  have hstate14 :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning13 hprecompile13
      (counterPreparedInitializeBodyJumpdest_decoded hat13) hstackOk13 hgas13
      hstep13
  have hstorage14 :
      counterStorageValue counterContractAddress counterCountSlot s14 =
        counterStorageValue counterContractAddress counterCountSlot s13 := by
    simp [hstate14]
  exact hstorage14.trans (hstorage13.trans hstorage9)

theorem counterPreparedInitializeSetValuePush192_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 2)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 2)).toNat =
        counterInitializeBodyOffset + 2 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_setvalue_push192 havailable

theorem counterPreparedInitializeSetValueShl_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 4)) :
    state.decoded =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 4)).toNat =
        counterInitializeBodyOffset + 4 := by
    native_decide
  have hconstantinople :
      EvmSemantics.Fork.Constantinople ≤ state.executionEnv.fork := by
    change EvmSemantics.Fork.Shanghai.toOrd ≤
      state.executionEnv.fork.toOrd at hfork
    change EvmSemantics.Fork.Constantinople.toOrd ≤
      state.executionEnv.fork.toOrd
    exact Nat.le_trans (by decide) hfork
  have havailable :
      ((.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, hconstantinople]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_setvalue_shl havailable

theorem counterPreparedInitializeMaskPush1_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 5)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 1, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 5)).toNat =
        counterInitializeBodyOffset + 5 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_push1 havailable

theorem counterPreparedInitializeMaskDup1_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 7)) :
    state.decoded = some (.Dup counterDup1Op, none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 7)).toNat =
        counterInitializeBodyOffset + 7 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_dup1 havailable

theorem counterPreparedInitializeMaskPush64_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 8)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 64, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 8)).toNat =
        counterInitializeBodyOffset + 8 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_push64 havailable

theorem counterPreparedInitializeMaskShl64_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 10)) :
    state.decoded =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 10)).toNat =
        counterInitializeBodyOffset + 10 := by
    native_decide
  have hconstantinople :
      EvmSemantics.Fork.Constantinople ≤ state.executionEnv.fork := by
    change EvmSemantics.Fork.Shanghai.toOrd ≤
      state.executionEnv.fork.toOrd at hfork
    change EvmSemantics.Fork.Constantinople.toOrd ≤
      state.executionEnv.fork.toOrd
    exact Nat.le_trans (by decide) hfork
  have havailable :
      ((.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, hconstantinople]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_shl64 havailable

theorem counterPreparedInitializeMaskSub_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 11)) :
    state.decoded =
      some (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 11)).toNat =
        counterInitializeBodyOffset + 11 := by
    native_decide
  have havailable :
      ((.StopArith (.SUB : EvmSemantics.Operation.StopArithOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_sub havailable

theorem counterPreparedInitializeMaskPush192_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 12)) :
    state.decoded =
      some (.Push counterPush1Op,
        some (EvmSemantics.UInt256.ofNat 192, 1)) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 12)).toNat =
        counterInitializeBodyOffset + 12 := by
    native_decide
  have havailable :
      ((.Push counterPush1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush1Op]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_push192 havailable

theorem counterPreparedInitializeMaskShl192_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 14)) :
    state.decoded =
      some (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 14)).toNat =
        counterInitializeBodyOffset + 14 := by
    native_decide
  have hconstantinople :
      EvmSemantics.Fork.Constantinople ≤ state.executionEnv.fork := by
    change EvmSemantics.Fork.Shanghai.toOrd ≤
      state.executionEnv.fork.toOrd at hfork
    change EvmSemantics.Fork.Constantinople.toOrd ≤
      state.executionEnv.fork.toOrd
    exact Nat.le_trans (by decide) hfork
  have havailable :
      ((.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, hconstantinople]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_shl192 havailable

theorem counterPreparedInitializeMaskNot_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 15)) :
    state.decoded =
      some (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 15)).toNat =
        counterInitializeBodyOffset + 15 := by
    native_decide
  have havailable :
      ((.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_mask_not havailable

theorem counterPreparedInitializeSloadSlotPush0_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 16)) :
    state.decoded =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 16)).toNat =
        counterInitializeBodyOffset + 16 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_sload_slot_push0 havailable

theorem counterPreparedInitializeSload_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 17)) :
    state.decoded =
      some (.StackMemFlow
        (.SLOAD : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 17)).toNat =
        counterInitializeBodyOffset + 17 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_sload havailable

theorem counterPreparedInitializeAnd_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 18)) :
    state.decoded =
      some (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 18)).toNat =
        counterInitializeBodyOffset + 18 := by
    native_decide
  have havailable :
      ((.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_and havailable

theorem counterPreparedInitializeOr_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 19)) :
    state.decoded =
      some (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 19)).toNat =
        counterInitializeBodyOffset + 19 := by
    native_decide
  have havailable :
      ((.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_or havailable

theorem counterPreparedInitializeSstoreSlotPush0_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 20)) :
    state.decoded =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 20)).toNat =
        counterInitializeBodyOffset + 20 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_sstore_slot_push0 havailable

theorem counterPreparedInitializeSstore_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 21)) :
    state.decoded =
      some (.StackMemFlow
        (.SSTORE : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 21)).toNat =
        counterInitializeBodyOffset + 21 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_sstore havailable

theorem counterPreparedInitializeBodyReturnJump_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 22)) :
    state.decoded =
      some (.StackMemFlow
        (.JUMP : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeBodyOffset + 22)).toNat =
        counterInitializeBodyOffset + 22 := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_body_return_jump havailable

theorem counterCompiledStateAt_of_initialize_sstore_stepFE_ok
    {state nextState : EvmState} {slot value : EvmSemantics.UInt256}
    {rest : List EvmSemantics.UInt256}
    (hat : counterCompiledStateAt state (counterInitializeBodyOffset + 21))
    (hstack : state.stack = slot :: value :: rest)
    (hready :
      counterStepFEReady state
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    counterCompiledStateAt nextState (counterInitializeBodyOffset + 22) := by
  rcases hready with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  rcases hat with ⟨hcode, hpc, hfork⟩
  obtain ⟨hcodeNext, hpcNext, hforkNext⟩ :=
    counterCodePcFork_of_stepFE_stackMemFlow_sstore_ok hrunning hprecompile
      (counterPreparedInitializeSstore_decoded ⟨hcode, hpc, hfork⟩) hstack
      hstackOk hgas hstep
  refine ⟨?_, ?_, ?_⟩
  · rw [hcodeNext]
    exact hcode
  · rw [hpcNext, hpc]
    native_decide
  · rw [hforkNext]
    exact hfork

theorem counterPreparedInitializeReturnJumpdest_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state counterInitializeReturnOffset) :
    state.decoded =
      some (.StackMemFlow
        (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset).toNat =
        counterInitializeReturnOffset := by
    native_decide
  have havailable :
      ((.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_return_jumpdest havailable

theorem counterPreparedInitializeReturnPush0_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeReturnOffset + 1)) :
    state.decoded =
      some (.Push counterPush0Op,
        some (EvmSemantics.UInt256.ofNat 0, 0)) := by
  rcases hat with ⟨hcode, hpc, hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeReturnOffset + 1)).toNat =
        counterInitializeReturnOffset + 1 := by
    native_decide
  have havailable :
      ((.Push counterPush0Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork, counterPush0Op, hfork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_return_push0 havailable

theorem counterPreparedInitializeReturnDup1_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeReturnOffset + 2)) :
    state.decoded = some (.Dup counterDup1Op, none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeReturnOffset + 2)).toNat =
        counterInitializeReturnOffset + 2 := by
    native_decide
  have havailable :
      ((.Dup counterDup1Op : EvmSemantics.Operation).availableInFork
        state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_return_dup1 havailable

theorem counterPreparedInitializeReturn_decoded
    {state : EvmState}
    (hat : counterCompiledStateAt state (counterInitializeReturnOffset + 3)) :
    state.decoded =
      some (.System
        (.RETURN : EvmSemantics.Operation.SystemOps), none) := by
  rcases hat with ⟨hcode, hpc, _hfork⟩
  have hpcNat :
      (EvmSemantics.UInt256.ofNat (counterInitializeReturnOffset + 3)).toNat =
        counterInitializeReturnOffset + 3 := by
    native_decide
  have havailable :
      ((.System (.RETURN : EvmSemantics.Operation.SystemOps) :
        EvmSemantics.Operation).availableInFork state.executionEnv.fork) = true := by
    simp [EvmSemantics.Operation.availableInFork]
  exact counterState_decoded_of_code_pc hcode hpc hpcNat
    counterCompiledRuntimeCode_decodes_initialize_return havailable

theorem counterState_of_initialize_return_stepFE_to_returned_empty_ok
    {s0 s1 s2 s3 s4 s5 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 :
      s0.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 22))
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush0Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Dup counterDup1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    s5.halt = .Returned ∧
      s5.hReturn = ByteArray.empty ∧
      s5.toResult = .returned ByteArray.empty ∧
      s5.stack = rest ∧
      s5.callStack = s0.callStack ∧
      counterStorageValue counterContractAddress counterCountSlot s5 =
        counterStorageValue counterContractAddress counterCountSlot s0 := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  have hdecoded0 := counterPreparedInitializeBodyReturnJump_decoded hat0
  rcases hat0 with ⟨hcode0, _hpc0, hfork0⟩
  have hvalid :
      EvmSemantics.EVM.Decode.isValidJumpDest s0.executionEnv.code
        (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset).toNat = true := by
    rw [hcode0]
    have hreturnNat :
        (EvmSemantics.UInt256.ofNat counterInitializeReturnOffset).toNat =
          counterInitializeReturnOffset := by
      native_decide
    rw [hreturnNat]
    exact counterCompiledRuntimeCode_valid_initialize_return_jumpdest
  have hstate1 :=
    counterState_of_stepFE_stackMemFlow_jump_ok hrunning0 hprecompile0
      hdecoded0 h0 hvalid hstackOk0 hgas0 hstep0
  have hat1 : counterCompiledStateAt s1 counterInitializeReturnOffset := by
    unfold counterCompiledStateAt
    rw [hstate1]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, hcode0]
    · constructor
      · simp
      · simpa [EvmSemantics.EVM.State.consumeGas] using hfork0
  have hstack1 : s1.stack = rest := by
    rw [hstate1]
  have hstate2 :=
    counterState_of_stepFE_stackMemFlow_jumpdest_ok hrunning1 hprecompile1
      (counterPreparedInitializeReturnJumpdest_decoded hat1) hstackOk1 hgas1
      hstep1
  rcases hat1 with ⟨hcode1, hpc1, hfork1⟩
  have hat2 : counterCompiledStateAt s2 (counterInitializeReturnOffset + 1) := by
    unfold counterCompiledStateAt
    rw [hstate2]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC,
        hcode1]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC,
          hpc1]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.incrPC] using hfork1
  have hstack2 : s2.stack = rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.incrPC,
      hstack1]
  have hstate3 :=
    counterState_of_stepFE_push0_ok hrunning2 hprecompile2
      (counterPreparedInitializeReturnPush0_decoded hat2) hstackOk2 hgas2
      hstep2
  rcases hat2 with ⟨hcode2, hpc2, hfork2⟩
  have hat3 : counterCompiledStateAt s3 (counterInitializeReturnOffset + 2) := by
    unfold counterCompiledStateAt
    rw [hstate3]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode2]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc2]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork2
  have hstack3 :
      s3.stack = EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack2]
  have hstate4 :=
    counterState_of_stepFE_dup1_ok hrunning3 hprecompile3
      (counterPreparedInitializeReturnDup1_decoded hat3) hstack3 hstackOk3
      hgas3 hstep3
  rcases hat3 with ⟨hcode3, hpc3, hfork3⟩
  have hat4 : counterCompiledStateAt s4 (counterInitializeReturnOffset + 3) := by
    unfold counterCompiledStateAt
    rw [hstate4]
    constructor
    · simp [EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.replaceStackAndIncrPC, hcode3]
    · constructor
      · simp [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, hpc3]
        native_decide
      · simpa [EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC] using hfork3
  have hstack4 :
      s4.stack =
        EvmSemantics.UInt256.ofNat 0 :: EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hstack3]
  obtain ⟨hhalt, hreturn, hstack5, hcallStack5, hstorage5⟩ :=
    counterState_of_stepFE_system_return_empty_ok hrunning4 hprecompile4
      (counterPreparedInitializeReturn_decoded hat4) hstack4 hstackOk4 hgas4
      hstep4
  have hresult : s5.toResult = .returned ByteArray.empty := by
    simp [EvmSemantics.EVM.State.toResult, hhalt, hreturn]
  have hcallStack : s5.callStack = s0.callStack := by
    have hcallStack4 : s4.callStack = s0.callStack := by
      simp [hstate4, hstate3, hstate2, hstate1,
        EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.incrPC,
        EvmSemantics.EVM.State.replaceStackAndIncrPC]
    exact hcallStack5.trans hcallStack4
  have hstorage : counterStorageValue counterContractAddress counterCountSlot s5 =
      counterStorageValue counterContractAddress counterCountSlot s0 := by
    have hstorage4 :
        counterStorageValue counterContractAddress counterCountSlot s4 =
          counterStorageValue counterContractAddress counterCountSlot s0 := by
      simp [hstate4, hstate3, hstate2, hstate1, counterStorageValue, counterAccount,
        EvmSemantics.EVM.State.consumeGas,
        EvmSemantics.EVM.State.incrPC,
        EvmSemantics.EVM.State.replaceStackAndIncrPC]
    exact hstorage5.trans hstorage4
  exact ⟨hhalt, hreturn, hresult, hstack5, hcallStack, hstorage⟩

theorem counterStack_of_initialize_prefix_stepFE_to_sload_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12) :
    s12.stack =
      counterCountSlot :: counterInitializeLowMask ::
        counterInitializeSetValue :: rest := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  rcases hready5 with ⟨hrunning5, hprecompile5, hstackOk5, hgas5⟩
  rcases hready6 with ⟨hrunning6, hprecompile6, hstackOk6, hgas6⟩
  rcases hready7 with ⟨hrunning7, hprecompile7, hstackOk7, hgas7⟩
  rcases hready8 with ⟨hrunning8, hprecompile8, hstackOk8, hgas8⟩
  rcases hready9 with ⟨hrunning9, hprecompile9, hstackOk9, hgas9⟩
  rcases hready10 with ⟨hrunning10, hprecompile10, hstackOk10, hgas10⟩
  rcases hready11 with ⟨hrunning11, hprecompile11, hstackOk11, hgas11⟩
  have h1 : s1.stack = EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [counterStack_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedInitializeFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0,
      h0]
  have h2 :
      s2.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [counterStack_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeSetValuePush192_decoded hat1) hstackOk1 hgas1
      hstep1, h1]
  have h3 : s3.stack = counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning2 hprecompile2
      (counterPreparedInitializeSetValueShl_decoded hat2) h2 hstackOk2 hgas2 hstep2]
    rfl
  have h4 :
      s4.stack =
        EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_push1_ok hrunning3 hprecompile3
      (counterPreparedInitializeMaskPush1_decoded hat3) hstackOk3 hgas3 hstep3, h3]
  have h5 :
      s5.stack =
        EvmSemantics.UInt256.ofNat 1 :: EvmSemantics.UInt256.ofNat 1 ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedInitializeMaskDup1_decoded hat4) h4 hstackOk4 hgas4 hstep4]
  have h6 :
      s6.stack =
        EvmSemantics.UInt256.ofNat 64 :: EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [counterStack_of_stepFE_push1_ok hrunning5 hprecompile5
      (counterPreparedInitializeMaskPush64_decoded hat5) hstackOk5 hgas5 hstep5, h5]
  have h7 :
      s7.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat 1)
          (EvmSemantics.UInt256.ofNat 64) ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning6 hprecompile6
      (counterPreparedInitializeMaskShl64_decoded hat6) h6 hstackOk6 hgas6 hstep6]
  have h8 :
      s8.stack =
        EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_stopArith_sub_ok hrunning7 hprecompile7
      (counterPreparedInitializeMaskSub_decoded hat7) h7 hstackOk7 hgas7 hstep7,
      counterInitializeU64MaskBase_eq]
  have h9 :
      s9.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
            counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_push1_ok hrunning8 hprecompile8
      (counterPreparedInitializeMaskPush192_decoded hat8) hstackOk8 hgas8
      hstep8, h8]
  have h10 :
      s10.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat (2 ^ 64 - 1))
          (EvmSemantics.UInt256.ofNat 192) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning9 hprecompile9
      (counterPreparedInitializeMaskShl192_decoded hat9) h9 hstackOk9 hgas9 hstep9]
  have h11 :
      s11.stack = counterInitializeLowMask :: counterInitializeSetValue ::
        rest := by
    rw [counterStack_of_stepFE_compBit_not_ok hrunning10 hprecompile10
      (counterPreparedInitializeMaskNot_decoded hat10) h10 hstackOk10 hgas10 hstep10]
    rfl
  rw [counterStack_of_stepFE_push0_ok hrunning11 hprecompile11
    (counterPreparedInitializeSloadSlotPush0_decoded hat11) hstackOk11 hgas11
    hstep11, h11, counterCountSlot_eq_zero]

theorem counterCallStack_of_initialize_prefix_stepFE_to_sload_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12) :
    s12.callStack = s0.callStack := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  rcases hready5 with ⟨hrunning5, hprecompile5, hstackOk5, hgas5⟩
  rcases hready6 with ⟨hrunning6, hprecompile6, hstackOk6, hgas6⟩
  rcases hready7 with ⟨hrunning7, hprecompile7, hstackOk7, hgas7⟩
  rcases hready8 with ⟨hrunning8, hprecompile8, hstackOk8, hgas8⟩
  rcases hready9 with ⟨hrunning9, hprecompile9, hstackOk9, hgas9⟩
  rcases hready10 with ⟨hrunning10, hprecompile10, hstackOk10, hgas10⟩
  rcases hready11 with ⟨hrunning11, hprecompile11, hstackOk11, hgas11⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedInitializeFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  have h1Stack : s1.stack = EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h0]
  have h1CallStack : s1.callStack = s0.callStack := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate2 :=
    counterState_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeSetValuePush192_decoded hat1) hstackOk1 hgas1
      hstep1
  have h2Stack :
      s2.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h1Stack]
  have h2CallStack : s2.callStack = s1.callStack := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have h3Stack : s3.stack = counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning2 hprecompile2
      (counterPreparedInitializeSetValueShl_decoded hat2) h2Stack hstackOk2 hgas2 hstep2]
    rfl
  have h3CallStack : s3.callStack = s2.callStack :=
    counterCallStack_of_stepFE_compBit_shl_ok hrunning2 hprecompile2
      (counterPreparedInitializeSetValueShl_decoded hat2) h2Stack hstackOk2 hgas2 hstep2
  have hstate4 :=
    counterState_of_stepFE_push1_ok hrunning3 hprecompile3
      (counterPreparedInitializeMaskPush1_decoded hat3) hstackOk3 hgas3 hstep3
  have h4Stack :
      s4.stack =
        EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue :: rest := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h3Stack]
  have h4CallStack : s4.callStack = s3.callStack := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate5 :=
    counterState_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedInitializeMaskDup1_decoded hat4) h4Stack hstackOk4 hgas4 hstep4
  have h5Stack :
      s5.stack =
        EvmSemantics.UInt256.ofNat 1 :: EvmSemantics.UInt256.ofNat 1 ::
          counterInitializeSetValue :: rest := by
    rw [hstate5]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h4Stack]
  have h5CallStack : s5.callStack = s4.callStack := by
    rw [hstate5]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate6 :=
    counterState_of_stepFE_push1_ok hrunning5 hprecompile5
      (counterPreparedInitializeMaskPush64_decoded hat5) hstackOk5 hgas5 hstep5
  have h6Stack :
      s6.stack =
        EvmSemantics.UInt256.ofNat 64 :: EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [hstate6]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h5Stack]
  have h6CallStack : s6.callStack = s5.callStack := by
    rw [hstate6]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have h7Stack :
      s7.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat 1)
          (EvmSemantics.UInt256.ofNat 64) ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning6 hprecompile6
      (counterPreparedInitializeMaskShl64_decoded hat6) h6Stack hstackOk6 hgas6 hstep6]
  have h7CallStack : s7.callStack = s6.callStack :=
    counterCallStack_of_stepFE_compBit_shl_ok hrunning6 hprecompile6
      (counterPreparedInitializeMaskShl64_decoded hat6) h6Stack hstackOk6 hgas6 hstep6
  have h8Stack :
      s8.stack =
        EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_stopArith_sub_ok hrunning7 hprecompile7
      (counterPreparedInitializeMaskSub_decoded hat7) h7Stack hstackOk7 hgas7 hstep7,
      counterInitializeU64MaskBase_eq]
  have h8CallStack : s8.callStack = s7.callStack :=
    counterCallStack_of_stepFE_stopArith_sub_ok hrunning7 hprecompile7
      (counterPreparedInitializeMaskSub_decoded hat7) h7Stack hstackOk7 hgas7 hstep7
  have hstate9 :=
    counterState_of_stepFE_push1_ok hrunning8 hprecompile8
      (counterPreparedInitializeMaskPush192_decoded hat8) hstackOk8 hgas8 hstep8
  have h9Stack :
      s9.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
            counterInitializeSetValue :: rest := by
    rw [hstate9]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h8Stack]
  have h9CallStack : s9.callStack = s8.callStack := by
    rw [hstate9]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have h10Stack :
      s10.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat (2 ^ 64 - 1))
          (EvmSemantics.UInt256.ofNat 192) ::
          counterInitializeSetValue :: rest := by
    rw [counterStack_of_stepFE_compBit_shl_ok hrunning9 hprecompile9
      (counterPreparedInitializeMaskShl192_decoded hat9) h9Stack hstackOk9 hgas9 hstep9]
  have h10CallStack : s10.callStack = s9.callStack :=
    counterCallStack_of_stepFE_compBit_shl_ok hrunning9 hprecompile9
      (counterPreparedInitializeMaskShl192_decoded hat9) h9Stack hstackOk9 hgas9 hstep9
  have h11Stack :
      s11.stack = counterInitializeLowMask :: counterInitializeSetValue ::
        rest := by
    rw [counterStack_of_stepFE_compBit_not_ok hrunning10 hprecompile10
      (counterPreparedInitializeMaskNot_decoded hat10) h10Stack hstackOk10 hgas10 hstep10]
    rfl
  have h11CallStack : s11.callStack = s10.callStack :=
    counterCallStack_of_stepFE_compBit_not_ok hrunning10 hprecompile10
      (counterPreparedInitializeMaskNot_decoded hat10) h10Stack hstackOk10 hgas10 hstep10
  have hstate12 :=
    counterState_of_stepFE_push0_ok hrunning11 hprecompile11
      (counterPreparedInitializeSloadSlotPush0_decoded hat11) hstackOk11 hgas11
      hstep11
  have h12CallStack : s12.callStack = s11.callStack := by
    rw [hstate12]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  exact h12CallStack.trans
    (h11CallStack.trans
      (h10CallStack.trans
        (h9CallStack.trans
          (h8CallStack.trans
            (h7CallStack.trans
              (h6CallStack.trans
                (h5CallStack.trans
                  (h4CallStack.trans
                    (h3CallStack.trans
                      (h2CallStack.trans h1CallStack))))))))))

theorem counterStorageValue_of_initialize_prefix_stepFE_to_sload_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12) :
    counterStorageValue counterContractAddress counterCountSlot s12 =
      counterStorageValue counterContractAddress counterCountSlot s0 := by
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  rcases hready5 with ⟨hrunning5, hprecompile5, hstackOk5, hgas5⟩
  rcases hready6 with ⟨hrunning6, hprecompile6, hstackOk6, hgas6⟩
  rcases hready7 with ⟨hrunning7, hprecompile7, hstackOk7, hgas7⟩
  rcases hready8 with ⟨hrunning8, hprecompile8, hstackOk8, hgas8⟩
  rcases hready9 with ⟨hrunning9, hprecompile9, hstackOk9, hgas9⟩
  rcases hready10 with ⟨hrunning10, hprecompile10, hstackOk10, hgas10⟩
  rcases hready11 with ⟨hrunning11, hprecompile11, hstackOk11, hgas11⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedInitializeFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  have h1Stack : s1.stack = EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate1]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h0]
  have hstate2 :=
    counterState_of_stepFE_push1_ok hrunning1 hprecompile1
      (counterPreparedInitializeSetValuePush192_decoded hat1) hstackOk1 hgas1
      hstep1
  have h2Stack :
      s2.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat 0 :: rest := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h1Stack]
  have hstate3 :=
    counterState_of_stepFE_compBit_shl_ok hrunning2 hprecompile2
      (counterPreparedInitializeSetValueShl_decoded hat2) h2Stack hstackOk2
      hgas2 hstep2
  have h3Stack : s3.stack = counterInitializeSetValue :: rest := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
    rfl
  have hstate4 :=
    counterState_of_stepFE_push1_ok hrunning3 hprecompile3
      (counterPreparedInitializeMaskPush1_decoded hat3) hstackOk3 hgas3 hstep3
  have h4Stack :
      s4.stack =
        EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue :: rest := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h3Stack]
  have hstate5 :=
    counterState_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedInitializeMaskDup1_decoded hat4) h4Stack hstackOk4 hgas4 hstep4
  have h5Stack :
      s5.stack =
        EvmSemantics.UInt256.ofNat 1 :: EvmSemantics.UInt256.ofNat 1 ::
          counterInitializeSetValue :: rest := by
    rw [hstate5]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h4Stack]
  have hstate6 :=
    counterState_of_stepFE_push1_ok hrunning5 hprecompile5
      (counterPreparedInitializeMaskPush64_decoded hat5) hstackOk5 hgas5 hstep5
  have h6Stack :
      s6.stack =
        EvmSemantics.UInt256.ofNat 64 :: EvmSemantics.UInt256.ofNat 1 ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [hstate6]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h5Stack]
  have hstate7 :=
    counterState_of_stepFE_compBit_shl_ok hrunning6 hprecompile6
      (counterPreparedInitializeMaskShl64_decoded hat6) h6Stack hstackOk6
      hgas6 hstep6
  have h7Stack :
      s7.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat 1)
          (EvmSemantics.UInt256.ofNat 64) ::
          EvmSemantics.UInt256.ofNat 1 :: counterInitializeSetValue ::
            rest := by
    rw [hstate7]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate8 :=
    counterState_of_stepFE_stopArith_sub_ok hrunning7 hprecompile7
      (counterPreparedInitializeMaskSub_decoded hat7) h7Stack hstackOk7
      hgas7 hstep7
  have h8Stack :
      s8.stack =
        EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
          counterInitializeSetValue :: rest := by
    rw [hstate8, counterInitializeU64MaskBase_eq]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate9 :=
    counterState_of_stepFE_push1_ok hrunning8 hprecompile8
      (counterPreparedInitializeMaskPush192_decoded hat8) hstackOk8 hgas8
      hstep8
  have h9Stack :
      s9.stack =
        EvmSemantics.UInt256.ofNat 192 ::
          EvmSemantics.UInt256.ofNat (2 ^ 64 - 1) ::
            counterInitializeSetValue :: rest := by
    rw [hstate9]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, h8Stack]
  have hstate10 :=
    counterState_of_stepFE_compBit_shl_ok hrunning9 hprecompile9
      (counterPreparedInitializeMaskShl192_decoded hat9) h9Stack hstackOk9
      hgas9 hstep9
  have h10Stack :
      s10.stack =
        EvmSemantics.UInt256.shiftLeft
          (EvmSemantics.UInt256.ofNat (2 ^ 64 - 1))
          (EvmSemantics.UInt256.ofNat 192) ::
            counterInitializeSetValue :: rest := by
    rw [hstate10]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hstate11 :=
    counterState_of_stepFE_compBit_not_ok hrunning10 hprecompile10
      (counterPreparedInitializeMaskNot_decoded hat10) h10Stack hstackOk10
      hgas10 hstep10
  have hstate12 :=
    counterState_of_stepFE_push0_ok hrunning11 hprecompile11
      (counterPreparedInitializeSloadSlotPush0_decoded hat11) hstackOk11 hgas11
      hstep11
  simp [hstate12, hstate11, hstate10, hstate9, hstate8, hstate7,
    hstate6, hstate5, hstate4, hstate3, hstate2, hstate1]

theorem counterStorageValue_of_dispatcher_initialize_prefix_stepFE_to_sload_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 s23 s24 s25 s26 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hcalldata0 : s0.executionEnv.calldata = counterCallCalldata .initialize)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 : counterStepFEReady s14 (.Push counterPush0Op))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 2))
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 4))
    (hready16 :
      counterStepFEReady s16
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hat17 : counterCompiledStateAt s17 (counterInitializeBodyOffset + 5))
    (hready17 : counterStepFEReady s17 (.Push counterPush1Op))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hat18 : counterCompiledStateAt s18 (counterInitializeBodyOffset + 7))
    (hready18 : counterStepFEReady s18 (.Dup counterDup1Op))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hat19 : counterCompiledStateAt s19 (counterInitializeBodyOffset + 8))
    (hready19 : counterStepFEReady s19 (.Push counterPush1Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hat20 : counterCompiledStateAt s20 (counterInitializeBodyOffset + 10))
    (hready20 :
      counterStepFEReady s20
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hat21 : counterCompiledStateAt s21 (counterInitializeBodyOffset + 11))
    (hready21 :
      counterStepFEReady s21
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22)
    (hat22 : counterCompiledStateAt s22 (counterInitializeBodyOffset + 12))
    (hready22 : counterStepFEReady s22 (.Push counterPush1Op))
    (hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23)
    (hat23 : counterCompiledStateAt s23 (counterInitializeBodyOffset + 14))
    (hready23 :
      counterStepFEReady s23
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24)
    (hat24 : counterCompiledStateAt s24 (counterInitializeBodyOffset + 15))
    (hready24 :
      counterStepFEReady s24
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25)
    (hat25 : counterCompiledStateAt s25 (counterInitializeBodyOffset + 16))
    (hready25 : counterStepFEReady s25 (.Push counterPush0Op))
    (hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26) :
    counterStorageValue counterContractAddress counterCountSlot s26 =
      counterStorageValue counterContractAddress counterCountSlot s0 := by
  obtain ⟨hat14, _hdecoded14, hstack14⟩ :=
    counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
      h0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1 hready2 hstep2
      hready3 hstep3 hready4 hstep4 hready5 hstep5 hready6 hstep6
      hready7 hstep7 hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12 hready13 hstep13
  have hdispatcher :
      counterStorageValue counterContractAddress counterCountSlot s14 =
        counterStorageValue counterContractAddress counterCountSlot s0 :=
    counterStorageValue_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
      h0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1
      hready2 hstep2 hready3 hstep3 hready4 hstep4
      hready5 hstep5 hready6 hstep6 hready7 hstep7
      hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
      hready13 hstep13
  have hbody :
      counterStorageValue counterContractAddress counterCountSlot s26 =
        counterStorageValue counterContractAddress counterCountSlot s14 :=
    counterStorageValue_of_initialize_prefix_stepFE_to_sload_ok
      hstack14 hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16 hat17 hready17 hstep17
      hat18 hready18 hstep18 hat19 hready19 hstep19
      hat20 hready20 hstep20 hat21 hready21 hstep21
      hat22 hready22 hstep22 hat23 hready23 hstep23
      hat24 hready24 hstep24 hat25 hready25 hstep25
  exact hbody.trans hdispatcher

theorem counterStack_of_initialize_tail_stepFE_to_sstore_ok
    {sloadState afterSload afterAnd afterOr sstoreState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : sloadState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hatSload : counterCompiledStateAt sloadState (counterInitializeBodyOffset + 17))
    (hreadySload :
      counterStepFEReady sloadState
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hsload : EvmSemantics.EVM.stepFE sloadState = .ok afterSload)
    (hatAnd : counterCompiledStateAt afterSload (counterInitializeBodyOffset + 18))
    (hreadyAnd :
      counterStepFEReady afterSload
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hand : EvmSemantics.EVM.stepFE afterSload = .ok afterAnd)
    (hatOr : counterCompiledStateAt afterAnd (counterInitializeBodyOffset + 19))
    (hreadyOr :
      counterStepFEReady afterAnd
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hor : EvmSemantics.EVM.stepFE afterAnd = .ok afterOr)
    (hatPush :
      counterCompiledStateAt afterOr (counterInitializeBodyOffset + 20))
    (hreadyPush : counterStepFEReady afterOr (.Push counterPush0Op))
    (hpush : EvmSemantics.EVM.stepFE afterOr = .ok sstoreState) :
    sstoreState.stack =
      counterCountSlot ::
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
        rest := by
  rcases hreadySload with ⟨hrunningSload, hprecompileSload, hstackOkSload,
    hgasSload⟩
  rcases hreadyAnd with ⟨hrunningAnd, hprecompileAnd, hstackOkAnd, hgasAnd⟩
  rcases hreadyOr with ⟨hrunningOr, hprecompileOr, hstackOkOr, hgasOr⟩
  rcases hreadyPush with ⟨hrunningPush, hprecompilePush, hstackOkPush, hgasPush⟩
  have hsloadStack :
      afterSload.stack =
        counterStorageValue counterContractAddress counterCountSlot sloadState ::
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_stackMemFlow_sload_ok hrunningSload
      hprecompileSload (counterPreparedInitializeSload_decoded hatSload)
      haddrSload hstack rfl hstackOkSload hgasSload hsload
  have handStack :
      afterAnd.stack =
        EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_compBit_and_ok hrunningAnd hprecompileAnd
      (counterPreparedInitializeAnd_decoded hatAnd) hsloadStack hstackOkAnd
      hgasAnd hand
  have horStack :
      afterOr.stack =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_compBit_or_ok hrunningOr hprecompileOr
      (counterPreparedInitializeOr_decoded hatOr) handStack hstackOkOr hgasOr hor]
    change counterInitializeBodyWriteWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest
    rw [counterInitializeBodyWriteWord_eq_storageWord]
  rw [counterStack_of_stepFE_push0_ok hrunningPush hprecompilePush
    (counterPreparedInitializeSstoreSlotPush0_decoded hatPush) hstackOkPush
    hgasPush hpush, horStack, counterCountSlot_eq_zero]

theorem counterStorageValue_of_initialize_tail_stepFE_ok
    {sloadState afterSload afterAnd afterOr sstoreState nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : sloadState.executionEnv.address = counterContractAddress)
    (haddrSstore : sstoreState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hatSload : counterCompiledStateAt sloadState (counterInitializeBodyOffset + 17))
    (hreadySload :
      counterStepFEReady sloadState
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hsload : EvmSemantics.EVM.stepFE sloadState = .ok afterSload)
    (hatAnd : counterCompiledStateAt afterSload (counterInitializeBodyOffset + 18))
    (hreadyAnd :
      counterStepFEReady afterSload
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hand : EvmSemantics.EVM.stepFE afterSload = .ok afterAnd)
    (hatOr : counterCompiledStateAt afterAnd (counterInitializeBodyOffset + 19))
    (hreadyOr :
      counterStepFEReady afterAnd
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hor : EvmSemantics.EVM.stepFE afterAnd = .ok afterOr)
    (hatPush :
      counterCompiledStateAt afterOr (counterInitializeBodyOffset + 20))
    (hreadyPush : counterStepFEReady afterOr (.Push counterPush0Op))
    (hpush : EvmSemantics.EVM.stepFE afterOr = .ok sstoreState)
    (hatSstore : counterCompiledStateAt sstoreState (counterInitializeBodyOffset + 21))
    (hreadySstore :
      counterStepFEReady sstoreState
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hsstore : EvmSemantics.EVM.stepFE sstoreState = .ok nextState) :
    counterStorageValue counterContractAddress counterCountSlot nextState =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) := by
  rcases hreadySload with ⟨hrunningSload, hprecompileSload, hstackOkSload,
    hgasSload⟩
  rcases hreadyAnd with ⟨hrunningAnd, hprecompileAnd, hstackOkAnd, hgasAnd⟩
  rcases hreadyOr with ⟨hrunningOr, hprecompileOr, hstackOkOr, hgasOr⟩
  rcases hreadyPush with ⟨hrunningPush, hprecompilePush, hstackOkPush, hgasPush⟩
  rcases hreadySstore with ⟨hrunningSstore, hprecompileSstore, hstackOkSstore,
    hgasSstore⟩
  have hsloadStack :
      afterSload.stack =
        counterStorageValue counterContractAddress counterCountSlot sloadState ::
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_stackMemFlow_sload_ok hrunningSload
      hprecompileSload (counterPreparedInitializeSload_decoded hatSload)
      haddrSload hstack rfl hstackOkSload hgasSload hsload
  have handStack :
      afterAnd.stack =
        EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_compBit_and_ok hrunningAnd hprecompileAnd
      (counterPreparedInitializeAnd_decoded hatAnd) hsloadStack hstackOkAnd
      hgasAnd hand
  have horStack :
      afterOr.stack =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_compBit_or_ok hrunningOr hprecompileOr
      (counterPreparedInitializeOr_decoded hatOr) handStack hstackOkOr hgasOr hor]
    change counterInitializeBodyWriteWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest
    rw [counterInitializeBodyWriteWord_eq_storageWord]
  have hsstoreStack :
      sstoreState.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_push0_ok hrunningPush hprecompilePush
      (counterPreparedInitializeSstoreSlotPush0_decoded hatPush) hstackOkPush
      hgasPush hpush, horStack, counterCountSlot_eq_zero]
  exact counterStorageValue_of_stepFE_stackMemFlow_sstore_ok hrunningSstore
    hprecompileSstore (counterPreparedInitializeSstore_decoded hatSstore)
    haddrSstore hsstoreStack rfl hstackOkSstore hgasSstore hsstore

theorem counterCallStack_of_initialize_tail_stepFE_ok
    {sloadState afterSload afterAnd afterOr sstoreState nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : sloadState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hatSload : counterCompiledStateAt sloadState (counterInitializeBodyOffset + 17))
    (hreadySload :
      counterStepFEReady sloadState
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hsload : EvmSemantics.EVM.stepFE sloadState = .ok afterSload)
    (hatAnd : counterCompiledStateAt afterSload (counterInitializeBodyOffset + 18))
    (hreadyAnd :
      counterStepFEReady afterSload
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hand : EvmSemantics.EVM.stepFE afterSload = .ok afterAnd)
    (hatOr : counterCompiledStateAt afterAnd (counterInitializeBodyOffset + 19))
    (hreadyOr :
      counterStepFEReady afterAnd
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hor : EvmSemantics.EVM.stepFE afterAnd = .ok afterOr)
    (hatPush :
      counterCompiledStateAt afterOr (counterInitializeBodyOffset + 20))
    (hreadyPush : counterStepFEReady afterOr (.Push counterPush0Op))
    (hpush : EvmSemantics.EVM.stepFE afterOr = .ok sstoreState)
    (hatSstore : counterCompiledStateAt sstoreState (counterInitializeBodyOffset + 21))
    (hreadySstore :
      counterStepFEReady sstoreState
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hsstore : EvmSemantics.EVM.stepFE sstoreState = .ok nextState) :
    nextState.callStack = sloadState.callStack := by
  rcases hreadySload with ⟨hrunningSload, hprecompileSload, hstackOkSload,
    hgasSload⟩
  rcases hreadyAnd with ⟨hrunningAnd, hprecompileAnd, hstackOkAnd, hgasAnd⟩
  rcases hreadyOr with ⟨hrunningOr, hprecompileOr, hstackOkOr, hgasOr⟩
  rcases hreadyPush with ⟨hrunningPush, hprecompilePush, hstackOkPush, hgasPush⟩
  rcases hreadySstore with ⟨hrunningSstore, hprecompileSstore, hstackOkSstore,
    hgasSstore⟩
  have hsloadStack :
      afterSload.stack =
        counterStorageValue counterContractAddress counterCountSlot sloadState ::
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_stackMemFlow_sload_ok hrunningSload
      hprecompileSload (counterPreparedInitializeSload_decoded hatSload)
      haddrSload hstack rfl hstackOkSload hgasSload hsload
  have hsloadCallStack :
      afterSload.callStack = sloadState.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_sload_ok hrunningSload
      hprecompileSload (counterPreparedInitializeSload_decoded hatSload)
      hstack hstackOkSload hgasSload hsload
  have handStack :
      afterAnd.stack =
        EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_compBit_and_ok hrunningAnd hprecompileAnd
      (counterPreparedInitializeAnd_decoded hatAnd) hsloadStack hstackOkAnd
      hgasAnd hand
  have handCallStack : afterAnd.callStack = afterSload.callStack :=
    counterCallStack_of_stepFE_compBit_and_ok hrunningAnd hprecompileAnd
      (counterPreparedInitializeAnd_decoded hatAnd) hsloadStack hstackOkAnd
      hgasAnd hand
  have horStack :
      afterOr.stack =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_compBit_or_ok hrunningOr hprecompileOr
      (counterPreparedInitializeOr_decoded hatOr) handStack hstackOkOr hgasOr hor]
    change counterInitializeBodyWriteWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest
    rw [counterInitializeBodyWriteWord_eq_storageWord]
  have horCallStack : afterOr.callStack = afterAnd.callStack :=
    counterCallStack_of_stepFE_compBit_or_ok hrunningOr hprecompileOr
      (counterPreparedInitializeOr_decoded hatOr) handStack hstackOkOr hgasOr hor
  have hpushState :=
    counterState_of_stepFE_push0_ok hrunningPush hprecompilePush
      (counterPreparedInitializeSstoreSlotPush0_decoded hatPush)
      hstackOkPush hgasPush hpush
  have hpushCallStack : sstoreState.callStack = afterOr.callStack := by
    rw [hpushState]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hsstoreStack :
      sstoreState.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [hpushState, horStack, counterCountSlot_eq_zero]
    simp [EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hsstoreCallStack : nextState.callStack = sstoreState.callStack :=
    counterCallStack_of_stepFE_stackMemFlow_sstore_ok hrunningSstore
      hprecompileSstore (counterPreparedInitializeSstore_decoded hatSstore)
      hsstoreStack hstackOkSstore hgasSstore hsstore
  exact hsstoreCallStack.trans
    (hpushCallStack.trans
      (horCallStack.trans (handCallStack.trans hsloadCallStack)))

theorem counterStack_of_initialize_tail_stepFE_ok
    {sloadState afterSload afterAnd afterOr sstoreState nextState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (haddrSload : sloadState.executionEnv.address = counterContractAddress)
    (hstack :
      sloadState.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest)
    (hatSload : counterCompiledStateAt sloadState (counterInitializeBodyOffset + 17))
    (hreadySload :
      counterStepFEReady sloadState
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hsload : EvmSemantics.EVM.stepFE sloadState = .ok afterSload)
    (hatAnd : counterCompiledStateAt afterSload (counterInitializeBodyOffset + 18))
    (hreadyAnd :
      counterStepFEReady afterSload
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hand : EvmSemantics.EVM.stepFE afterSload = .ok afterAnd)
    (hatOr : counterCompiledStateAt afterAnd (counterInitializeBodyOffset + 19))
    (hreadyOr :
      counterStepFEReady afterAnd
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hor : EvmSemantics.EVM.stepFE afterAnd = .ok afterOr)
    (hatPush :
      counterCompiledStateAt afterOr (counterInitializeBodyOffset + 20))
    (hreadyPush : counterStepFEReady afterOr (.Push counterPush0Op))
    (hpush : EvmSemantics.EVM.stepFE afterOr = .ok sstoreState)
    (hatSstore : counterCompiledStateAt sstoreState (counterInitializeBodyOffset + 21))
    (hreadySstore :
      counterStepFEReady sstoreState
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hsstore : EvmSemantics.EVM.stepFE sstoreState = .ok nextState) :
    nextState.stack = rest := by
  rcases hreadySload with ⟨hrunningSload, hprecompileSload, hstackOkSload,
    hgasSload⟩
  rcases hreadyAnd with ⟨hrunningAnd, hprecompileAnd, hstackOkAnd, hgasAnd⟩
  rcases hreadyOr with ⟨hrunningOr, hprecompileOr, hstackOkOr, hgasOr⟩
  rcases hreadyPush with ⟨hrunningPush, hprecompilePush, hstackOkPush, hgasPush⟩
  rcases hreadySstore with ⟨hrunningSstore, hprecompileSstore, hstackOkSstore,
    hgasSstore⟩
  have hsloadStack :
      afterSload.stack =
        counterStorageValue counterContractAddress counterCountSlot sloadState ::
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_stackMemFlow_sload_ok hrunningSload
      hprecompileSload (counterPreparedInitializeSload_decoded hatSload)
      haddrSload hstack rfl hstackOkSload hgasSload hsload
  have handStack :
      afterAnd.stack =
        EvmSemantics.UInt256.land
          (counterStorageValue counterContractAddress counterCountSlot sloadState)
          counterInitializeLowMask :: counterInitializeSetValue :: rest :=
    counterStack_of_stepFE_compBit_and_ok hrunningAnd hprecompileAnd
      (counterPreparedInitializeAnd_decoded hatAnd) hsloadStack hstackOkAnd
      hgasAnd hand
  have horStack :
      afterOr.stack =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_compBit_or_ok hrunningOr hprecompileOr
      (counterPreparedInitializeOr_decoded hatOr) handStack hstackOkOr hgasOr hor]
    change counterInitializeBodyWriteWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest
    rw [counterInitializeBodyWriteWord_eq_storageWord]
  have hsstoreStack :
      sstoreState.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot sloadState) ::
          rest := by
    rw [counterStack_of_stepFE_push0_ok hrunningPush hprecompilePush
      (counterPreparedInitializeSstoreSlotPush0_decoded hatPush) hstackOkPush
      hgasPush hpush, horStack, counterCountSlot_eq_zero]
  exact counterStack_of_stepFE_stackMemFlow_sstore_ok hrunningSstore
    hprecompileSstore (counterPreparedInitializeSstore_decoded hatSstore)
    hsstoreStack hstackOkSstore hgasSstore hsstore

theorem counterStack_of_initialize_body_stepFE_to_sstore_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 :
      EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeBodyOffset + 17))
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hat13 : counterCompiledStateAt s13 (counterInitializeBodyOffset + 18))
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hat14 : counterCompiledStateAt s14 (counterInitializeBodyOffset + 19))
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 20))
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16) :
    s16.stack =
      counterCountSlot ::
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s12) ::
        rest := by
  have hstack12 :
      s12.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest :=
    counterStack_of_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
  exact counterStack_of_initialize_tail_stepFE_to_sstore_ok
    haddrSload hstack12
    hat12 hready12 hstep12 hat13 hready13 hstep13
    hat14 hready14 hstep14 hat15 hready15 hstep15

theorem counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17 :
      EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeBodyOffset + 17))
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hat13 : counterCompiledStateAt s13 (counterInitializeBodyOffset + 18))
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hat14 : counterCompiledStateAt s14 (counterInitializeBodyOffset + 19))
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 20))
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 21))
    (haddrSstore : s16.executionEnv.address = counterContractAddress)
    (hready16 :
      counterStepFEReady s16
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17) :
    counterStorageValue counterContractAddress counterCountSlot s17 =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot s12) := by
  have hstack12 :
      s12.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest :=
    counterStack_of_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
  exact counterStorageValue_of_initialize_tail_stepFE_ok
    haddrSload haddrSstore hstack12
    hat12 hready12 hstep12 hat13 hready13 hstep13
    hat14 hready14 hstep14 hat15 hready15 hstep15
    hat16 hready16 hstep16

theorem counterStack_of_initialize_body_stepFE_from_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17 :
      EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeBodyOffset + 17))
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hat13 : counterCompiledStateAt s13 (counterInitializeBodyOffset + 18))
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hat14 : counterCompiledStateAt s14 (counterInitializeBodyOffset + 19))
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 20))
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 21))
    (hready16 :
      counterStepFEReady s16
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17) :
    s17.stack = rest := by
  have hstack12 :
      s12.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest :=
    counterStack_of_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
  exact counterStack_of_initialize_tail_stepFE_ok
    haddrSload hstack12
    hat12 hready12 hstep12 hat13 hready13 hstep13
    hat14 hready14 hstep14 hat15 hready15 hstep15
    hat16 hready16 hstep16

theorem counterCallStack_of_initialize_body_stepFE_from_first_opcode_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17 :
      EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeBodyOffset + 17))
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hat13 : counterCompiledStateAt s13 (counterInitializeBodyOffset + 18))
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hat14 : counterCompiledStateAt s14 (counterInitializeBodyOffset + 19))
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 20))
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 21))
    (hready16 :
      counterStepFEReady s16
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17) :
    s17.callStack = s0.callStack := by
  have hstack12 :
      s12.stack =
        counterCountSlot :: counterInitializeLowMask ::
          counterInitializeSetValue :: rest :=
    counterStack_of_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
  have hprefixCallStack : s12.callStack = s0.callStack :=
    counterCallStack_of_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
  have htailCallStack : s17.callStack = s12.callStack :=
    counterCallStack_of_initialize_tail_stepFE_ok
      haddrSload hstack12
      hat12 hready12 hstep12 hat13 hready13 hstep13
      hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16
  exact htailCallStack.trans hprefixCallStack

def counterRuntimeGasAvailable : Nat := 1000000

def counterRuntimeBlockGasLimit : Nat := 30000000

def counterRuntimeChainId : Nat := 31337

def counterCallerAddress : EvmSemantics.AccountAddress :=
  EvmSemantics.AccountAddress.ofNat 1

def installCounterRuntimeCode (runtimeCode : ByteArray) (state : EvmState) :
    EvmState :=
  let account := state.accountMap counterContractAddress
  { state with
    accountMap := state.accountMap.set counterContractAddress
      { account with code := runtimeCode } }

def counterCallExecutionEnv (runtimeCode : ByteArray) (call : CounterCall)
    (state : EvmState) : EvmSemantics.ExecutionEnv := {
  state.executionEnv with
    address := counterContractAddress
    origin := counterCallerAddress
    caller := counterCallerAddress
    weiValue := EvmSemantics.UInt256.ofNat 0
    calldata := counterCallCalldata call
    code := runtimeCode
    codeAddr := counterContractAddress
    gasPrice := EvmSemantics.UInt256.ofNat 0
    header := {
      state.executionEnv.header with
        gasLimit := EvmSemantics.UInt256.ofNat counterRuntimeBlockGasLimit
        chainId := EvmSemantics.UInt256.ofNat counterRuntimeChainId
    }
    depth := 0
    permitStateMutation := true
    blobVersionedHashes := #[]
    fork := EvmSemantics.Fork.Cancun
}

/-- Prepare a top-level powdr frame for executing one Counter selector.

The runtime bytecode is an explicit parameter: the later proof should pass the
actual ProofForge EVM artifact bytes here, rather than replacing the compiler
pipeline with a handwritten bytecode fixture. -/
def prepareCounterCall (runtimeCode : ByteArray) (call : CounterCall)
    (state : EvmState) : EvmState :=
  let state := installCounterRuntimeCode runtimeCode state
  { state with
    gasAvailable := counterRuntimeGasAvailable
    activeWords := EvmSemantics.UInt256.ofNat 0
    memory := ByteArray.empty
    returnData := ByteArray.empty
    hReturn := ByteArray.empty
    executionEnv := counterCallExecutionEnv runtimeCode call state
    pc := EvmSemantics.UInt256.ofNat 0
    stack := []
    execLength := 0
    halt := .Running
    callStack := [] }

theorem counterStorageValue_installCounterRuntimeCode
    (runtimeCode : ByteArray) (state : EvmState) :
    counterStorageValue counterContractAddress counterCountSlot
        (installCounterRuntimeCode runtimeCode state) =
      counterStorageValue counterContractAddress counterCountSlot state := by
  simp [installCounterRuntimeCode, counterStorageValue, counterAccount]

theorem counterStorageValue_prepareCounterCall
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    counterStorageValue counterContractAddress counterCountSlot
        (prepareCounterCall runtimeCode call state) =
      counterStorageValue counterContractAddress counterCountSlot state := by
  simp [prepareCounterCall, counterStorageValue, counterAccount, installCounterRuntimeCode]

theorem counterStorageRel_prepareCounterCall
    {irState : IRState} {evmState : EvmState}
    (runtimeCode : ByteArray) (call : CounterCall)
    (hrel : CounterStorageRel irState evmState) :
    CounterStorageRel irState (prepareCounterCall runtimeCode call evmState) := by
  rcases hrel with ⟨count, hcount, hbound, hstorage⟩
  refine ⟨count, hcount, hbound, ?_⟩
  rw [counterStorageValue_prepareCounterCall]
  exact hstorage

@[simp] theorem prepareCounterCall_gasAvailable
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).gasAvailable =
      counterRuntimeGasAvailable := rfl

@[simp] theorem prepareCounterCall_pc
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).pc = EvmSemantics.UInt256.ofNat 0 := rfl

@[simp] theorem prepareCounterCall_stack
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).stack = [] := rfl

@[simp] theorem prepareCounterCall_halt
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).halt = .Running := rfl

@[simp] theorem prepareCounterCall_callStack
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).callStack = [] := rfl

@[simp] theorem prepareCounterCall_calldata
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).executionEnv.calldata =
      counterCallCalldata call := rfl

@[simp] theorem prepareCounterCall_code
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).executionEnv.code =
      runtimeCode := rfl

@[simp] theorem prepareCounterCall_isDone
    (runtimeCode : ByteArray) (call : CounterCall) (state : EvmState) :
    (prepareCounterCall runtimeCode call state).isDone = false := by
  simp [prepareCounterCall, EvmSemantics.EVM.State.isDone,
    EvmSemantics.EVM.State.isHalted, EvmSemantics.EVM.State.isRunning]

structure PowdrCounterConfig where
  runtimeCode : ByteArray
  fuel : Nat

def counterCompiledRuntimeFuel : Nat := 5000

def counterCompiledPowdrConfig : PowdrCounterConfig := {
  runtimeCode := counterCompiledRuntimeCode
  fuel := counterCompiledRuntimeFuel
}

def counterBaseEvmState : EvmState :=
  { (default : EvmState) with
    gasAvailable := counterRuntimeGasAvailable
    executionEnv := {
      (default : EvmSemantics.ExecutionEnv) with
        address := counterContractAddress
        origin := counterCallerAddress
        caller := counterCallerAddress
        weiValue := EvmSemantics.UInt256.ofNat 0
        calldata := ByteArray.empty
        code := counterCompiledRuntimeCode
        codeAddr := counterContractAddress
        gasPrice := EvmSemantics.UInt256.ofNat 0
        header := { (default : EvmSemantics.BlockHeader) with
          gasLimit := EvmSemantics.UInt256.ofNat counterRuntimeBlockGasLimit
          chainId := EvmSemantics.UInt256.ofNat counterRuntimeChainId }
        depth := 0
        permitStateMutation := true
        fork := EvmSemantics.Fork.Cancun }
    pc := EvmSemantics.UInt256.ofNat 0
    stack := []
    execLength := 0
    halt := .Running
    callStack := [] }

def counterUnitObservableFromResult (name : String) :
    EvmSemantics.EVM.ExecutionResult → Except String ObservableReturn
  | .success => .ok .none
  | .returned output =>
      if output.size == 0 then
        .ok .none
      else
        .error s!"Counter.{name} returned unexpected EVM output bytes"
  | .reverted _ => .ok (.reverted s!"Counter.{name} reverted")
  | .exception _ => .error s!"Counter.{name} halted with an EVM exception"

def counterGetObservableFromResult :
    EvmSemantics.EVM.ExecutionResult → Except String ObservableReturn
  | .returned output =>
      .ok (.u64 (EvmSemantics.MachineState.readWord output 0).toNat)
  | .success => .error "Counter.get stopped without EVM return data"
  | .reverted _ => .ok (.reverted "Counter.get reverted")
  | .exception _ => .error "Counter.get halted with an EVM exception"

def counterObservableFromResult (call : CounterCall)
    (result : EvmSemantics.EVM.ExecutionResult) : Except String ObservableReturn :=
  match call with
  | .initialize => counterUnitObservableFromResult "initialize" result
  | .increment => counterUnitObservableFromResult "increment" result
  | .get => counterGetObservableFromResult result

theorem counterInitializeObservable_of_returned_empty :
    counterObservableFromResult .initialize
      (.returned ByteArray.empty) = .ok .none := by
  simp [counterObservableFromResult, counterUnitObservableFromResult]

theorem counterInitializeReturn_preserves_storage_model_stepFE_ok
    {s0 s1 s2 s3 s4 s5 sloadState : EvmState}
    {rest : List EvmSemantics.UInt256}
    (hstorage0 :
      counterStorageValue counterContractAddress counterCountSlot s0 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState))
    (h0 :
      s0.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 22))
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush0Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Dup counterDup1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    s5.halt = .Returned ∧
      counterStorageValue counterContractAddress counterCountSlot s5 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState) ∧
      s5.callStack = s0.callStack ∧
      counterObservableFromResult .initialize s5.toResult = .ok .none := by
  obtain ⟨hhalt, _hreturn, hresult, _hstack, hcallStack, hstorage⟩ :=
    counterState_of_initialize_return_stepFE_to_returned_empty_ok
      h0 hat0 hready0 hstep0 hready1 hstep1 hready2 hstep2 hready3 hstep3
      hready4 hstep4
  refine ⟨hhalt, ?_, hcallStack, ?_⟩
  · rw [hstorage, hstorage0]
  · rw [hresult]
    exact counterInitializeObservable_of_returned_empty

theorem counterStepFEReduction_of_ready_step
    {state nextState : EvmState} {op : EvmSemantics.Operation}
    (hready : counterStepFEReady state op)
    (hstep : EvmSemantics.EVM.stepFE state = .ok nextState) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReduction state nextState := by
  exact ProofForge.Backend.Evm.PowdrExec.StepFEReduction.of_step hready.1 hstep

theorem counterStepFEPath_initialize_return_segment_ok
    {s0 s1 s2 s3 s4 s5 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush0Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Dup counterDup1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    EvmStepFEPath s0 5 s5 := by
  exact ProofForge.Backend.Evm.PowdrExec.stepFEPath_five
    hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
    hready3.1 hstep3 hready4.1 hstep4

theorem counterRunBytecode_initialize_return_segment_ok
    {s0 s1 s2 s3 s4 s5 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush0Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Dup counterDup1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 5 =
      .ok (s5, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
    (ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_five
      (counterStepFEReduction_of_ready_step hready0 hstep0)
      (counterStepFEReduction_of_ready_step hready1 hstep1)
      (counterStepFEReduction_of_ready_step hready2 hstep2)
      (counterStepFEReduction_of_ready_step hready3 hstep3)
      (counterStepFEReduction_of_ready_step hready4 hstep4))

theorem counterStepFEPath_get_return_segment_ok
    {s0 s1 s2 s3 s4 s5 s6 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Push counterPush0Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 :
      counterStepFEReady s2
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Push counterPush0Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 :
      counterStepFEReady s5
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6) :
    EvmStepFEPath s0 6 s6 := by
  exact ProofForge.Backend.Evm.PowdrExec.stepFEPath_six
    hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
    hready3.1 hstep3 hready4.1 hstep4 hready5.1 hstep5

theorem counterRunBytecode_get_return_segment_ok
    {s0 s1 s2 s3 s4 s5 s6 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Push counterPush0Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 :
      counterStepFEReady s2
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Push counterPush0Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 :
      counterStepFEReady s5
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 6 =
      .ok (s6, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
    (ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_six
      (counterStepFEReduction_of_ready_step hready0 hstep0)
      (counterStepFEReduction_of_ready_step hready1 hstep1)
      (counterStepFEReduction_of_ready_step hready2 hstep2)
      (counterStepFEReduction_of_ready_step hready3 hstep3)
      (counterStepFEReduction_of_ready_step hready4 hstep4)
      (counterStepFEReduction_of_ready_step hready5 hstep5))

theorem counterStepFEPath_get_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 : EvmState}
    (hready0 : counterStepFEReady s0 (.Push counterPush1Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Dup counterDup1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush0Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hready10 : counterStepFEReady s10 (.Swap counterSwap1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hready11 :
      counterStepFEReady s11
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 : counterStepFEReady s13 (.Push counterPush0Op))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 :
      counterStepFEReady s14
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hready16 : counterStepFEReady s16 (.Push counterPush0Op))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 :
      counterStepFEReady s17
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18) :
    EvmStepFEPath s0 18 s18 := by
  have hbody : EvmStepFEPath s0 12 s12 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEPath_twelve
      hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
      hready3.1 hstep3 hready4.1 hstep4 hready5.1 hstep5
      hready6.1 hstep6 hready7.1 hstep7 hready8.1 hstep8
      hready9.1 hstep9 hready10.1 hstep10 hready11.1 hstep11
  have hreturn :=
    counterStepFEPath_get_return_segment_ok
      hready12 hstep12 hready13 hstep13 hready14 hstep14
      hready15 hstep15 hready16 hstep16 hready17 hstep17
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ProofForge.Backend.Evm.PowdrExec.stepFEPath_append hbody hreturn

theorem counterRunBytecode_get_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 : EvmState}
    (hready0 : counterStepFEReady s0 (.Push counterPush1Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Dup counterDup1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 :
      counterStepFEReady s4
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush0Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hready10 : counterStepFEReady s10 (.Swap counterSwap1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hready11 :
      counterStepFEReady s11
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 : counterStepFEReady s13 (.Push counterPush0Op))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 :
      counterStepFEReady s14
        (.StackMemFlow (.MSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hready16 : counterStepFEReady s16 (.Push counterPush0Op))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 :
      counterStepFEReady s17
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 18 =
      .ok (s18, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
  have hbody :
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 12 s12 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_twelve
      (counterStepFEReduction_of_ready_step hready0 hstep0)
      (counterStepFEReduction_of_ready_step hready1 hstep1)
      (counterStepFEReduction_of_ready_step hready2 hstep2)
      (counterStepFEReduction_of_ready_step hready3 hstep3)
      (counterStepFEReduction_of_ready_step hready4 hstep4)
      (counterStepFEReduction_of_ready_step hready5 hstep5)
      (counterStepFEReduction_of_ready_step hready6 hstep6)
      (counterStepFEReduction_of_ready_step hready7 hstep7)
      (counterStepFEReduction_of_ready_step hready8 hstep8)
      (counterStepFEReduction_of_ready_step hready9 hstep9)
      (counterStepFEReduction_of_ready_step hready10 hstep10)
      (counterStepFEReduction_of_ready_step hready11 hstep11)
  have hreturn :
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s12 6 s18 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_six
      (counterStepFEReduction_of_ready_step hready12 hstep12)
      (counterStepFEReduction_of_ready_step hready13 hstep13)
      (counterStepFEReduction_of_ready_step hready14 hstep14)
      (counterStepFEReduction_of_ready_step hready15 hstep15)
      (counterStepFEReduction_of_ready_step hready16 hstep16)
      (counterStepFEReduction_of_ready_step hready17 hstep17)
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
    (by
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.append
          hbody hreturn)

theorem counterStepFEPath_increment_return_segment_ok
    {s0 s1 s2 s3 s4 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Push counterPush0Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Dup counterDup1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    EvmStepFEPath s0 4 s4 := by
  exact ProofForge.Backend.Evm.PowdrExec.stepFEPath_four
    hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
    hready3.1 hstep3

theorem counterRunBytecode_increment_return_segment_ok
    {s0 s1 s2 s3 s4 : EvmState}
    (hready0 :
      counterStepFEReady s0
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Push counterPush0Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Dup counterDup1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 4 =
      .ok (s4, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
  exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
    (ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_four
      (counterStepFEReduction_of_ready_step hready0 hstep0)
      (counterStepFEReduction_of_ready_step hready1 hstep1)
      (counterStepFEReduction_of_ready_step hready2 hstep2)
      (counterStepFEReduction_of_ready_step hready3 hstep3))

theorem counterStepFEPath_initialize_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 : EvmState}
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hready16 :
      counterStepFEReady s16
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 :
      counterStepFEReady s17
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hready18 :
      counterStepFEReady s18
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hready19 : counterStepFEReady s19 (.Push counterPush0Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hready20 : counterStepFEReady s20 (.Dup counterDup1Op))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hready21 :
      counterStepFEReady s21
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22) :
    EvmStepFEPath s0 22 s22 := by
  have hpathToReturn : EvmStepFEPath s0 17 s17 :=
    .cons hready0.1 hstep0
      (.cons hready1.1 hstep1
        (.cons hready2.1 hstep2
          (.cons hready3.1 hstep3
            (.cons hready4.1 hstep4
              (.cons hready5.1 hstep5
                (.cons hready6.1 hstep6
                  (.cons hready7.1 hstep7
                    (.cons hready8.1 hstep8
                      (.cons hready9.1 hstep9
                        (.cons hready10.1 hstep10
                          (.cons hready11.1 hstep11
                            (.cons hready12.1 hstep12
                              (.cons hready13.1 hstep13
                                (.cons hready14.1 hstep14
                                  (.cons hready15.1 hstep15
                                    (.cons hready16.1 hstep16
                                      (.nil s17)))))))))))))))))
  have hpathReturn :=
    counterStepFEPath_initialize_return_segment_ok
      hready17 hstep17 hready18 hstep18 hready19 hstep19
      hready20 hstep20 hready21 hstep21
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ProofForge.Backend.Evm.PowdrAdapter.stepFEPath_append
      hpathToReturn hpathReturn

theorem counterRunBytecode_initialize_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 : EvmState}
    {selector : EvmSemantics.UInt256} {rest : List EvmSemantics.UInt256}
    (h0 :
      s0.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset :: selector :: rest)
    (hat0 : counterCompiledStateAt s0 (counterInitializeBodyOffset + 1))
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hat1 : counterCompiledStateAt s1 (counterInitializeBodyOffset + 2))
    (hready1 : counterStepFEReady s1 (.Push counterPush1Op))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hat2 : counterCompiledStateAt s2 (counterInitializeBodyOffset + 4))
    (hready2 :
      counterStepFEReady s2
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hat3 : counterCompiledStateAt s3 (counterInitializeBodyOffset + 5))
    (hready3 : counterStepFEReady s3 (.Push counterPush1Op))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hat4 : counterCompiledStateAt s4 (counterInitializeBodyOffset + 7))
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hat5 : counterCompiledStateAt s5 (counterInitializeBodyOffset + 8))
    (hready5 : counterStepFEReady s5 (.Push counterPush1Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hat6 : counterCompiledStateAt s6 (counterInitializeBodyOffset + 10))
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hat7 : counterCompiledStateAt s7 (counterInitializeBodyOffset + 11))
    (hready7 :
      counterStepFEReady s7
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hat8 : counterCompiledStateAt s8 (counterInitializeBodyOffset + 12))
    (hready8 : counterStepFEReady s8 (.Push counterPush1Op))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hat9 : counterCompiledStateAt s9 (counterInitializeBodyOffset + 14))
    (hready9 :
      counterStepFEReady s9
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeBodyOffset + 15))
    (hready10 :
      counterStepFEReady s10
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeBodyOffset + 16))
    (hready11 : counterStepFEReady s11 (.Push counterPush0Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeBodyOffset + 17))
    (haddrSload : s12.executionEnv.address = counterContractAddress)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hat13 : counterCompiledStateAt s13 (counterInitializeBodyOffset + 18))
    (hready13 :
      counterStepFEReady s13
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hat14 : counterCompiledStateAt s14 (counterInitializeBodyOffset + 19))
    (hready14 :
      counterStepFEReady s14
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 20))
    (hready15 : counterStepFEReady s15 (.Push counterPush0Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 21))
    (haddrSstore : s16.executionEnv.address = counterContractAddress)
    (hready16 :
      counterStepFEReady s16
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 :
      counterStepFEReady s17
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hready18 :
      counterStepFEReady s18
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hready19 : counterStepFEReady s19 (.Push counterPush0Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hready20 : counterStepFEReady s20 (.Dup counterDup1Op))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hready21 :
      counterStepFEReady s21
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 22 =
        .ok (s22, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) ∧
      s22.halt = .Returned ∧
      counterStorageValue counterContractAddress counterCountSlot s22 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s12) ∧
      s22.callStack = s17.callStack ∧
      s22.callStack = s0.callStack ∧
      counterObservableFromResult .initialize s22.toResult = .ok .none := by
  have hstack16 :
      s16.stack =
        counterCountSlot ::
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot s12) ::
          EvmSemantics.UInt256.ofNat counterInitializeReturnOffset ::
          selector :: rest :=
    counterStack_of_initialize_body_stepFE_to_sstore_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
      hat12 haddrSload hready12 hstep12 hat13 hready13 hstep13
      hat14 hready14 hstep14 hat15 hready15 hstep15
  have hat17 : counterCompiledStateAt s17 (counterInitializeBodyOffset + 22) :=
    counterCompiledStateAt_of_initialize_sstore_stepFE_ok
      hat16 hstack16 hready16 hstep16
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 22 =
        .ok (s22, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
    have hbody0 :
        ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 12 s12 :=
      ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_twelve
        (counterStepFEReduction_of_ready_step hready0 hstep0)
        (counterStepFEReduction_of_ready_step hready1 hstep1)
        (counterStepFEReduction_of_ready_step hready2 hstep2)
        (counterStepFEReduction_of_ready_step hready3 hstep3)
        (counterStepFEReduction_of_ready_step hready4 hstep4)
        (counterStepFEReduction_of_ready_step hready5 hstep5)
        (counterStepFEReduction_of_ready_step hready6 hstep6)
        (counterStepFEReduction_of_ready_step hready7 hstep7)
        (counterStepFEReduction_of_ready_step hready8 hstep8)
        (counterStepFEReduction_of_ready_step hready9 hstep9)
        (counterStepFEReduction_of_ready_step hready10 hstep10)
        (counterStepFEReduction_of_ready_step hready11 hstep11)
    have hbody1 :
        ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s12 5 s17 :=
      ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_five
        (counterStepFEReduction_of_ready_step hready12 hstep12)
        (counterStepFEReduction_of_ready_step hready13 hstep13)
        (counterStepFEReduction_of_ready_step hready14 hstep14)
        (counterStepFEReduction_of_ready_step hready15 hstep15)
        (counterStepFEReduction_of_ready_step hready16 hstep16)
    have hreturn :
        ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s17 5 s22 :=
      ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_five
        (counterStepFEReduction_of_ready_step hready17 hstep17)
        (counterStepFEReduction_of_ready_step hready18 hstep18)
        (counterStepFEReduction_of_ready_step hready19 hstep19)
        (counterStepFEReduction_of_ready_step hready20 hstep20)
        (counterStepFEReduction_of_ready_step hready21 hstep21)
    have hbody :=
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.append
        hbody0 hbody1
    exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
      (by
        simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
          ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.append
            hbody hreturn)
  have hstorage17 :
      counterStorageValue counterContractAddress counterCountSlot s17 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s12) :=
    counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
      hat12 haddrSload hready12 hstep12 hat13 hready13 hstep13
      hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 haddrSstore hready16 hstep16
  have hstack17 :
      s17.stack =
        EvmSemantics.UInt256.ofNat counterInitializeReturnOffset ::
          selector :: rest :=
    counterStack_of_initialize_body_stepFE_from_first_opcode_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
      hat12 haddrSload hready12 hstep12 hat13 hready13 hstep13
      hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16
  obtain ⟨hhalt22, hstorage22, hcallStack22, hobs22⟩ :=
    counterInitializeReturn_preserves_storage_model_stepFE_ok
      hstorage17 hstack17 hat17 hready17 hstep17 hready18 hstep18
      hready19 hstep19 hready20 hstep20 hready21 hstep21
  have hcallStack17 : s17.callStack = s0.callStack :=
    counterCallStack_of_initialize_body_stepFE_from_first_opcode_ok
      h0 hat0 hready0 hstep0 hat1 hready1 hstep1
      hat2 hready2 hstep2 hat3 hready3 hstep3
      hat4 hready4 hstep4 hat5 hready5 hstep5
      hat6 hready6 hstep6 hat7 hready7 hstep7
      hat8 hready8 hstep8 hat9 hready9 hstep9
      hat10 hready10 hstep10 hat11 hready11 hstep11
      hat12 haddrSload hready12 hstep12 hat13 hready13 hstep13
      hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16
  exact ⟨hrun, hhalt22, hstorage22, hcallStack22,
    hcallStack22.trans hcallStack17, hobs22⟩

theorem counterStepFEPath_initialize_dispatcher_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 s23 s24 s25 s26 s27 s28 s29 s30 s31 s32 s33
      s34 s35 s36 : EvmState}
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 : counterStepFEReady s14 (.Push counterPush0Op))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hready16 :
      counterStepFEReady s16
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 : counterStepFEReady s17 (.Push counterPush1Op))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hready18 : counterStepFEReady s18 (.Dup counterDup1Op))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hready19 : counterStepFEReady s19 (.Push counterPush1Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hready20 :
      counterStepFEReady s20
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hready21 :
      counterStepFEReady s21
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22)
    (hready22 : counterStepFEReady s22 (.Push counterPush1Op))
    (hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23)
    (hready23 :
      counterStepFEReady s23
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24)
    (hready24 :
      counterStepFEReady s24
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25)
    (hready25 : counterStepFEReady s25 (.Push counterPush0Op))
    (hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26)
    (hready26 :
      counterStepFEReady s26
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep26 : EvmSemantics.EVM.stepFE s26 = .ok s27)
    (hready27 :
      counterStepFEReady s27
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep27 : EvmSemantics.EVM.stepFE s27 = .ok s28)
    (hready28 :
      counterStepFEReady s28
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep28 : EvmSemantics.EVM.stepFE s28 = .ok s29)
    (hready29 : counterStepFEReady s29 (.Push counterPush0Op))
    (hstep29 : EvmSemantics.EVM.stepFE s29 = .ok s30)
    (hready30 :
      counterStepFEReady s30
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep30 : EvmSemantics.EVM.stepFE s30 = .ok s31)
    (hready31 :
      counterStepFEReady s31
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep31 : EvmSemantics.EVM.stepFE s31 = .ok s32)
    (hready32 :
      counterStepFEReady s32
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep32 : EvmSemantics.EVM.stepFE s32 = .ok s33)
    (hready33 : counterStepFEReady s33 (.Push counterPush0Op))
    (hstep33 : EvmSemantics.EVM.stepFE s33 = .ok s34)
    (hready34 : counterStepFEReady s34 (.Dup counterDup1Op))
    (hstep34 : EvmSemantics.EVM.stepFE s34 = .ok s35)
    (hready35 :
      counterStepFEReady s35
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep35 : EvmSemantics.EVM.stepFE s35 = .ok s36) :
    EvmStepFEPath s0 36 s36 := by
  have hpathDispatcher : EvmStepFEPath s0 14 s14 :=
    .cons hready0.1 hstep0
      (.cons hready1.1 hstep1
        (.cons hready2.1 hstep2
          (.cons hready3.1 hstep3
            (.cons hready4.1 hstep4
              (.cons hready5.1 hstep5
                (.cons hready6.1 hstep6
                  (.cons hready7.1 hstep7
                    (.cons hready8.1 hstep8
                      (.cons hready9.1 hstep9
                        (.cons hready10.1 hstep10
                          (.cons hready11.1 hstep11
                            (.cons hready12.1 hstep12
                              (.cons hready13.1 hstep13
                                (.nil s14))))))))))))))
  have hpathBody :=
    counterStepFEPath_initialize_body_and_return_ok
      hready14 hstep14 hready15 hstep15 hready16 hstep16
      hready17 hstep17 hready18 hstep18 hready19 hstep19
      hready20 hstep20 hready21 hstep21 hready22 hstep22
      hready23 hstep23 hready24 hstep24 hready25 hstep25
      hready26 hstep26 hready27 hstep27 hready28 hstep28
      hready29 hstep29 hready30 hstep30 hready31 hstep31
      hready32 hstep32 hready33 hstep33 hready34 hstep34
      hready35 hstep35
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ProofForge.Backend.Evm.PowdrAdapter.stepFEPath_append
      hpathDispatcher hpathBody

theorem counterStepFEReductionChain_initialize_dispatcher_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 s23 s24 s25 s26 s27 s28 s29 s30 s31 s32 s33
      s34 s35 s36 : EvmState}
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 : counterStepFEReady s14 (.Push counterPush0Op))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hready16 :
      counterStepFEReady s16
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hready17 : counterStepFEReady s17 (.Push counterPush1Op))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hready18 : counterStepFEReady s18 (.Dup counterDup1Op))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hready19 : counterStepFEReady s19 (.Push counterPush1Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hready20 :
      counterStepFEReady s20
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hready21 :
      counterStepFEReady s21
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22)
    (hready22 : counterStepFEReady s22 (.Push counterPush1Op))
    (hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23)
    (hready23 :
      counterStepFEReady s23
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24)
    (hready24 :
      counterStepFEReady s24
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25)
    (hready25 : counterStepFEReady s25 (.Push counterPush0Op))
    (hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26)
    (hready26 :
      counterStepFEReady s26
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep26 : EvmSemantics.EVM.stepFE s26 = .ok s27)
    (hready27 :
      counterStepFEReady s27
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep27 : EvmSemantics.EVM.stepFE s27 = .ok s28)
    (hready28 :
      counterStepFEReady s28
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep28 : EvmSemantics.EVM.stepFE s28 = .ok s29)
    (hready29 : counterStepFEReady s29 (.Push counterPush0Op))
    (hstep29 : EvmSemantics.EVM.stepFE s29 = .ok s30)
    (hready30 :
      counterStepFEReady s30
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep30 : EvmSemantics.EVM.stepFE s30 = .ok s31)
    (hready31 :
      counterStepFEReady s31
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep31 : EvmSemantics.EVM.stepFE s31 = .ok s32)
    (hready32 :
      counterStepFEReady s32
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep32 : EvmSemantics.EVM.stepFE s32 = .ok s33)
    (hready33 : counterStepFEReady s33 (.Push counterPush0Op))
    (hstep33 : EvmSemantics.EVM.stepFE s33 = .ok s34)
    (hready34 : counterStepFEReady s34 (.Dup counterDup1Op))
    (hstep34 : EvmSemantics.EVM.stepFE s34 = .ok s35)
    (hready35 :
      counterStepFEReady s35
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep35 : EvmSemantics.EVM.stepFE s35 = .ok s36) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 36 s36 := by
  have hchain0_12 :
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 12 s12 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_twelve
      (counterStepFEReduction_of_ready_step hready0 hstep0)
      (counterStepFEReduction_of_ready_step hready1 hstep1)
      (counterStepFEReduction_of_ready_step hready2 hstep2)
      (counterStepFEReduction_of_ready_step hready3 hstep3)
      (counterStepFEReduction_of_ready_step hready4 hstep4)
      (counterStepFEReduction_of_ready_step hready5 hstep5)
      (counterStepFEReduction_of_ready_step hready6 hstep6)
      (counterStepFEReduction_of_ready_step hready7 hstep7)
      (counterStepFEReduction_of_ready_step hready8 hstep8)
      (counterStepFEReduction_of_ready_step hready9 hstep9)
      (counterStepFEReduction_of_ready_step hready10 hstep10)
      (counterStepFEReduction_of_ready_step hready11 hstep11)
  have hchain12_24 :
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s12 12 s24 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_twelve
      (counterStepFEReduction_of_ready_step hready12 hstep12)
      (counterStepFEReduction_of_ready_step hready13 hstep13)
      (counterStepFEReduction_of_ready_step hready14 hstep14)
      (counterStepFEReduction_of_ready_step hready15 hstep15)
      (counterStepFEReduction_of_ready_step hready16 hstep16)
      (counterStepFEReduction_of_ready_step hready17 hstep17)
      (counterStepFEReduction_of_ready_step hready18 hstep18)
      (counterStepFEReduction_of_ready_step hready19 hstep19)
      (counterStepFEReduction_of_ready_step hready20 hstep20)
      (counterStepFEReduction_of_ready_step hready21 hstep21)
      (counterStepFEReduction_of_ready_step hready22 hstep22)
      (counterStepFEReduction_of_ready_step hready23 hstep23)
  have hchain24_36 :
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s24 12 s36 :=
    ProofForge.Backend.Evm.PowdrExec.stepFEReductionChain_twelve
      (counterStepFEReduction_of_ready_step hready24 hstep24)
      (counterStepFEReduction_of_ready_step hready25 hstep25)
      (counterStepFEReduction_of_ready_step hready26 hstep26)
      (counterStepFEReduction_of_ready_step hready27 hstep27)
      (counterStepFEReduction_of_ready_step hready28 hstep28)
      (counterStepFEReduction_of_ready_step hready29 hstep29)
      (counterStepFEReduction_of_ready_step hready30 hstep30)
      (counterStepFEReduction_of_ready_step hready31 hstep31)
      (counterStepFEReduction_of_ready_step hready32 hstep32)
      (counterStepFEReduction_of_ready_step hready33 hstep33)
      (counterStepFEReduction_of_ready_step hready34 hstep34)
      (counterStepFEReduction_of_ready_step hready35 hstep35)
  have hchain0_24 :=
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.append
      hchain0_12 hchain12_24
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.append
      hchain0_24 hchain24_36

theorem counterRunBytecode_initialize_dispatcher_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 s23 s24 s25 s26 s27 s28 s29 s30 s31 s32 s33
      s34 s35 s36 : EvmState}
    {rest : List EvmSemantics.UInt256}
    (h0 : s0.stack = rest)
    (hat0 : counterCompiledStateAt s0 0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hcalldata0 : s0.executionEnv.calldata = counterCallCalldata .initialize)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 : counterStepFEReady s14 (.Push counterPush0Op))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 2))
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 4))
    (hready16 :
      counterStepFEReady s16
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hat17 : counterCompiledStateAt s17 (counterInitializeBodyOffset + 5))
    (hready17 : counterStepFEReady s17 (.Push counterPush1Op))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hat18 : counterCompiledStateAt s18 (counterInitializeBodyOffset + 7))
    (hready18 : counterStepFEReady s18 (.Dup counterDup1Op))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hat19 : counterCompiledStateAt s19 (counterInitializeBodyOffset + 8))
    (hready19 : counterStepFEReady s19 (.Push counterPush1Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hat20 : counterCompiledStateAt s20 (counterInitializeBodyOffset + 10))
    (hready20 :
      counterStepFEReady s20
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hat21 : counterCompiledStateAt s21 (counterInitializeBodyOffset + 11))
    (hready21 :
      counterStepFEReady s21
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22)
    (hat22 : counterCompiledStateAt s22 (counterInitializeBodyOffset + 12))
    (hready22 : counterStepFEReady s22 (.Push counterPush1Op))
    (hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23)
    (hat23 : counterCompiledStateAt s23 (counterInitializeBodyOffset + 14))
    (hready23 :
      counterStepFEReady s23
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24)
    (hat24 : counterCompiledStateAt s24 (counterInitializeBodyOffset + 15))
    (hready24 :
      counterStepFEReady s24
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25)
    (hat25 : counterCompiledStateAt s25 (counterInitializeBodyOffset + 16))
    (hready25 : counterStepFEReady s25 (.Push counterPush0Op))
    (hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26)
    (hat26 : counterCompiledStateAt s26 (counterInitializeBodyOffset + 17))
    (haddrSload : s26.executionEnv.address = counterContractAddress)
    (hready26 :
      counterStepFEReady s26
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep26 : EvmSemantics.EVM.stepFE s26 = .ok s27)
    (hat27 : counterCompiledStateAt s27 (counterInitializeBodyOffset + 18))
    (hready27 :
      counterStepFEReady s27
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep27 : EvmSemantics.EVM.stepFE s27 = .ok s28)
    (hat28 : counterCompiledStateAt s28 (counterInitializeBodyOffset + 19))
    (hready28 :
      counterStepFEReady s28
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep28 : EvmSemantics.EVM.stepFE s28 = .ok s29)
    (hat29 : counterCompiledStateAt s29 (counterInitializeBodyOffset + 20))
    (hready29 : counterStepFEReady s29 (.Push counterPush0Op))
    (hstep29 : EvmSemantics.EVM.stepFE s29 = .ok s30)
    (hat30 : counterCompiledStateAt s30 (counterInitializeBodyOffset + 21))
    (haddrSstore : s30.executionEnv.address = counterContractAddress)
    (hready30 :
      counterStepFEReady s30
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep30 : EvmSemantics.EVM.stepFE s30 = .ok s31)
    (hready31 :
      counterStepFEReady s31
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep31 : EvmSemantics.EVM.stepFE s31 = .ok s32)
    (hready32 :
      counterStepFEReady s32
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep32 : EvmSemantics.EVM.stepFE s32 = .ok s33)
    (hready33 : counterStepFEReady s33 (.Push counterPush0Op))
    (hstep33 : EvmSemantics.EVM.stepFE s33 = .ok s34)
    (hready34 : counterStepFEReady s34 (.Dup counterDup1Op))
    (hstep34 : EvmSemantics.EVM.stepFE s34 = .ok s35)
    (hready35 :
      counterStepFEReady s35
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep35 : EvmSemantics.EVM.stepFE s35 = .ok s36) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 36 =
        .ok (s36, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) ∧
      s36.halt = .Returned ∧
      counterStorageValue counterContractAddress counterCountSlot s36 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s26) ∧
      counterStorageValue counterContractAddress counterCountSlot s26 =
        counterStorageValue counterContractAddress counterCountSlot s0 ∧
      s36.callStack = s31.callStack ∧
      s36.callStack = s14.callStack ∧
      s36.callStack = s0.callStack ∧
      counterObservableFromResult .initialize s36.toResult = .ok .none := by
  obtain ⟨hat14, _hdecoded14, hstack14⟩ :=
    counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
      h0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1 hready2 hstep2
      hready3 hstep3 hready4 hstep4 hready5 hstep5 hready6 hstep6
      hready7 hstep7 hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12 hready13 hstep13
  have hrunTail :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode s14 22 =
        .ok (s36, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) ∧
      s36.halt = .Returned ∧
      counterStorageValue counterContractAddress counterCountSlot s36 =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s26) ∧
      s36.callStack = s31.callStack ∧
      s36.callStack = s14.callStack ∧
      counterObservableFromResult .initialize s36.toResult = .ok .none :=
    counterRunBytecode_initialize_body_and_return_ok
      hstack14 hat14 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16 hat17 hready17 hstep17
      hat18 hready18 hstep18 hat19 hready19 hstep19
      hat20 hready20 hstep20 hat21 hready21 hstep21
      hat22 hready22 hstep22 hat23 hready23 hstep23
      hat24 hready24 hstep24 hat25 hready25 hstep25
      hat26 haddrSload hready26 hstep26 hat27 hready27 hstep27
      hat28 hready28 hstep28 hat29 hready29 hstep29
      hat30 haddrSstore hready30 hstep30 hready31 hstep31
      hready32 hstep32 hready33 hstep33 hready34 hstep34
      hready35 hstep35
  rcases hrunTail with
    ⟨_hrunTail, hhalt, hstorage, hcallStackReturn, hcallStackBody, hobs⟩
  have hcallStackDispatcher : s14.callStack = s0.callStack :=
    counterCallStack_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok
      h0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1
      hready2 hstep2 hready3 hstep3 hready4 hstep4
      hready5 hstep5 hready6 hstep6 hready7 hstep7
      hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
      hready13 hstep13
  have hstoragePrefix :
      counterStorageValue counterContractAddress counterCountSlot s26 =
        counterStorageValue counterContractAddress counterCountSlot s0 :=
    counterStorageValue_of_dispatcher_initialize_prefix_stepFE_to_sload_ok
      h0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1
      hready2 hstep2 hready3 hstep3 hready4 hstep4
      hready5 hstep5 hready6 hstep6 hready7 hstep7
      hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
      hready13 hstep13 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16 hat17 hready17 hstep17
      hat18 hready18 hstep18 hat19 hready19 hstep19
      hat20 hready20 hstep20 hat21 hready21 hstep21
      hat22 hready22 hstep22 hat23 hready23 hstep23
      hat24 hready24 hstep24 hat25 hready25 hstep25
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 36 =
        .ok (s36, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) := by
    exact ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain
      (counterStepFEReductionChain_initialize_dispatcher_body_and_return_ok
        hready0 hstep0 hready1 hstep1 hready2 hstep2
        hready3 hstep3 hready4 hstep4 hready5 hstep5
        hready6 hstep6 hready7 hstep7 hready8 hstep8
        hready9 hstep9 hready10 hstep10 hready11 hstep11
        hready12 hstep12 hready13 hstep13 hready14 hstep14
        hready15 hstep15 hready16 hstep16 hready17 hstep17
        hready18 hstep18 hready19 hstep19 hready20 hstep20
        hready21 hstep21 hready22 hstep22 hready23 hstep23
        hready24 hstep24 hready25 hstep25 hready26 hstep26
        hready27 hstep27 hready28 hstep28 hready29 hstep29
        hready30 hstep30 hready31 hstep31 hready32 hstep32
        hready33 hstep33 hready34 hstep34 hready35 hstep35)
  exact ⟨hrun, hhalt, hstorage, hstoragePrefix, hcallStackReturn, hcallStackBody,
    hcallStackBody.trans hcallStackDispatcher, hobs⟩

def counterPowdrPreparedTraceStep (cfg : PowdrCounterConfig) (preparedState : EvmState)
    (call : CounterCall) : Except String (EvmState × ObservableReturn) := do
  let (finalState, _observations) ←
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState cfg.fuel
  let observable ← counterObservableFromResult call finalState.toResult
  .ok (finalState, observable)

theorem counterRunBytecode_extend_to_compiled_fuel
    {state finalState : EvmState}
    {observations : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep}
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode state 36 =
        .ok (finalState, observations))
    (hHalted : ProofForge.Backend.Evm.PowdrAdapter.isHalted finalState = true) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode state counterCompiledRuntimeFuel =
      .ok (finalState, observations) := by
  exact ProofForge.Backend.Evm.PowdrAdapter.runBytecode_extend_to_fuel
    (fuel := 36)
    (targetFuel := counterCompiledRuntimeFuel)
    (extra := counterCompiledRuntimeFuel - 36)
    hrun hHalted (by native_decide)

theorem counterRunBytecode_extend_to_compiled_fuel_from
    {fuel : Nat} {state finalState : EvmState}
    {observations : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep}
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode state fuel =
        .ok (finalState, observations))
    (hHalted : ProofForge.Backend.Evm.PowdrAdapter.isHalted finalState = true)
    (hle : fuel ≤ counterCompiledRuntimeFuel) :
    ProofForge.Backend.Evm.PowdrAdapter.runBytecode state counterCompiledRuntimeFuel =
      .ok (finalState, observations) := by
  exact ProofForge.Backend.Evm.PowdrAdapter.runBytecode_extend_to_fuel
    (fuel := fuel)
    (targetFuel := counterCompiledRuntimeFuel)
    (extra := counterCompiledRuntimeFuel - fuel)
    hrun hHalted (by
      exact (Nat.sub_add_cancel hle).symm)

theorem counterPowdrPreparedTraceStep_initialize_of_run36_ok
    {preparedState finalState : EvmState}
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState 36 =
        .ok (finalState, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)))
    (hHalted : ProofForge.Backend.Evm.PowdrAdapter.isHalted finalState = true)
    (hobs : counterObservableFromResult .initialize finalState.toResult = .ok .none) :
    counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState .initialize =
      .ok (finalState, .none) := by
  have hrunCompiled :=
    counterRunBytecode_extend_to_compiled_fuel hrun hHalted
  unfold counterPowdrPreparedTraceStep
  simp [counterCompiledPowdrConfig, hrunCompiled]
  change Except.bind (counterObservableFromResult .initialize finalState.toResult)
      (fun observable : ObservableReturn => Except.ok (finalState, observable)) =
    Except.ok (finalState, .none)
  rw [hobs]
  rfl

theorem counterPowdrPreparedTraceStep_initialize_of_run36_returned_top_level_ok
    {preparedState finalState : EvmState}
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState 36 =
        .ok (finalState, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)))
    (hhalt : finalState.halt = .Returned)
    (hcallStack : finalState.callStack = [])
    (hobs : counterObservableFromResult .initialize finalState.toResult = .ok .none) :
    counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState .initialize =
      .ok (finalState, .none) := by
  exact counterPowdrPreparedTraceStep_initialize_of_run36_ok hrun
    (ProofForge.Backend.Evm.PowdrAdapter.isHalted_of_returned_top_level hhalt hcallStack)
    hobs

def counterPowdrTraceStep (cfg : PowdrCounterConfig) (state : EvmState)
    (call : CounterCall) : Except String (EvmState × ObservableReturn) := do
  counterPowdrPreparedTraceStep cfg (prepareCounterCall cfg.runtimeCode call state) call

def CounterPreparedCall (cfg : PowdrCounterConfig) (call : CounterCall)
    (state : EvmState) : Prop :=
  ∃ sourceState, state = prepareCounterCall cfg.runtimeCode call sourceState

theorem counterPreparedCall_callStack
    {cfg : PowdrCounterConfig} {call : CounterCall} {state : EvmState}
    (hprepared : CounterPreparedCall cfg call state) :
    state.callStack = [] := by
  rcases hprepared with ⟨sourceState, rfl⟩
  exact prepareCounterCall_callStack cfg.runtimeCode call sourceState

theorem counterPowdrPreparedTraceStep_of_run_returned_prepared_ok
    {preparedState finalState : EvmState} {call : CounterCall}
    {fuel : Nat} {observable : ObservableReturn}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState)
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState fuel =
        .ok (finalState, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)))
    (hhalt : finalState.halt = .Returned)
    (hcallStackPrepared : finalState.callStack = preparedState.callStack)
    (hobs : counterObservableFromResult call finalState.toResult = .ok observable)
    (hle : fuel ≤ counterCompiledRuntimeFuel) :
    counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState call =
      .ok (finalState, observable) := by
  have hrunCompiled :=
    counterRunBytecode_extend_to_compiled_fuel_from hrun
      (ProofForge.Backend.Evm.PowdrAdapter.isHalted_of_returned_top_level hhalt
        (hcallStackPrepared.trans (counterPreparedCall_callStack hprepared)))
      hle
  unfold counterPowdrPreparedTraceStep
  simp [counterCompiledPowdrConfig, hrunCompiled]
  change Except.bind (counterObservableFromResult call finalState.toResult)
      (fun observable : ObservableReturn => Except.ok (finalState, observable)) =
    Except.ok (finalState, observable)
  rw [hobs]
  rfl

theorem counterPowdrPreparedTraceStep_initialize_of_run36_returned_prepared_ok
    {preparedState finalState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState 36 =
        .ok (finalState, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)))
    (hhalt : finalState.halt = .Returned)
    (hcallStackPrepared : finalState.callStack = preparedState.callStack)
    (hobs : counterObservableFromResult .initialize finalState.toResult = .ok .none) :
    counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState .initialize =
      .ok (finalState, .none) := by
  exact counterPowdrPreparedTraceStep_of_run_returned_prepared_ok
    hprepared hrun hhalt hcallStackPrepared hobs (by native_decide)

theorem counterCompiledPreparedInitialize_storage_model_of_run36_returned_sload_ok
    {preparedState sloadState finalState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState 36 =
        .ok (finalState, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)))
    (hhalt : finalState.halt = .Returned)
    (hcallStackPrepared : finalState.callStack = preparedState.callStack)
    (hstorageRun :
      counterStorageValue counterContractAddress counterCountSlot finalState =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot sloadState))
    (hstoragePrefix :
      counterStorageValue counterContractAddress counterCountSlot sloadState =
        counterStorageValue counterContractAddress counterCountSlot preparedState)
    (hobs : counterObservableFromResult .initialize finalState.toResult = .ok .none) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot preparedState) := by
  have hstep :=
    counterPowdrPreparedTraceStep_initialize_of_run36_returned_prepared_ok
      hprepared hrun hhalt hcallStackPrepared hobs
  have hstorage :
      counterStorageValue counterContractAddress counterCountSlot finalState =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot preparedState) := by
    rw [hstorageRun, hstoragePrefix]
  exact ⟨finalState, hstep, hstorage⟩

theorem counterCompiledPreparedCall_entry_facts
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    counterCompiledStateAt preparedState 0 ∧
      preparedState.stack = [] ∧
      preparedState.executionEnv.calldata = counterCallCalldata call ∧
      preparedState.executionEnv.address = counterContractAddress ∧
      preparedState.callStack = [] := by
  rcases hprepared with ⟨sourceState, rfl⟩
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · unfold counterCompiledStateAt
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv]
    change EvmSemantics.Fork.Shanghai.toOrd ≤ EvmSemantics.Fork.Cancun.toOrd
    decide
  · rfl
  · rfl
  · rfl
  · rfl

theorem counterCompiledPreparedInitialize_entry_facts
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    counterCompiledStateAt preparedState 0 ∧
      preparedState.stack = [] ∧
      preparedState.executionEnv.calldata = counterCallCalldata .initialize ∧
      preparedState.executionEnv.address = counterContractAddress ∧
      preparedState.callStack = [] := by
  exact counterCompiledPreparedCall_entry_facts hprepared

theorem counterCompiledPreparedCall_first_ready
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    counterStepFEReady preparedState (.Push counterPush0Op) := by
  rcases hprepared with ⟨sourceState, rfl⟩
  unfold counterStepFEReady
  simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
    counterRuntimeGasAvailable, counterContractAddress, EvmSemantics.EVM.State.fork]
  constructor
  · native_decide
  · constructor
    · native_decide
    · native_decide

theorem counterCompiledPreparedInitialize_first_ready
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    counterStepFEReady preparedState (.Push counterPush0Op) := by
  exact counterCompiledPreparedCall_first_ready hprepared

theorem counterCompiledPreparedCall_first_stepFE_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s1,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      counterCompiledStateAt s1 1 ∧
      s1.decoded =
        some (.Env
          (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none) ∧
      s1.stack = [EvmSemantics.UInt256.ofNat 0] ∧
      s1.executionEnv.calldata = counterCallCalldata call := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedCall_entry_facts hprepared
  have hreadyFull := counterCompiledPreparedCall_first_ready hprepared
  have hreadyForHelper := hreadyFull
  rcases hreadyFull with ⟨hrunning, hprecompile, hstackOk, hgas⟩
  let s1 :=
    (preparedState.consumeGas
      (EvmSemantics.EVM.Gas.baseCost preparedState.fork (.Push counterPush0Op))
      hgas).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 0 :: preparedState.stack)
  have hstep : EvmSemantics.EVM.stepFE preparedState = .ok s1 := by
    have hdecoded0 := counterPreparedDispatcherFirstPush0_decoded hat0
    unfold s1
    unfold EvmSemantics.EVM.stepFE
    simp only [Id.run]
    split
    · split
      · rename_i hprecompileActual
        rw [hprecompile] at hprecompileActual
        contradiction
      · simp [hdecoded0, EvmSemantics.EVM.stepF.push, counterPush0Op]
        have hstackIf :
            ¬ 1024 + (EvmSemantics.Operation.Push { width := 0 }).popArity <
              preparedState.stack.length +
                (EvmSemantics.Operation.Push { width := 0 }).pushArity := by
          simpa [counterPush0Op] using hstackOk
        have hgasIf :
            EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork preparedState)
                (EvmSemantics.Operation.Push { width := 0 }) ≤
              preparedState.gasAvailable := by
          simpa [counterPush0Op] using hgas
        simp [hstackIf, hgasIf, EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC, EvmSemantics.UInt256.ofNat]
    · rename_i hnotRunning
      rw [hrunning] at hnotRunning
      contradiction
  obtain ⟨hat1, hdecoded1, hstack1, hcalldata1⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      hstack0 hat0 hreadyForHelper hstep
  refine ⟨s1, hstep, hat1, hdecoded1, ?_, hcalldata1.trans ?_⟩
  · simpa [hstack0] using hstack1
  · exact (counterCompiledPreparedCall_entry_facts hprepared).2.2.1

theorem counterCompiledPreparedInitialize_first_stepFE_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s1,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      counterCompiledStateAt s1 1 ∧
      s1.decoded =
        some (.Env
          (.CALLDATALOAD : EvmSemantics.Operation.EnvOps), none) ∧
      s1.stack = [EvmSemantics.UInt256.ofNat 0] ∧
      s1.executionEnv.calldata = counterCallCalldata .initialize := by
  exact counterCompiledPreparedCall_first_stepFE_ok hprepared

theorem counterCompiledPreparedCall_second_ready
    {preparedState s1 : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1) :
    counterStepFEReady s1
      (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)) := by
  obtain ⟨hat0, _hstack0, _hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedCall_entry_facts hprepared
  have hready0 := counterCompiledPreparedCall_first_ready hprepared
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  rcases hprepared with ⟨sourceState, rfl⟩
  rw [hstate1]
  unfold counterStepFEReady
  simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
    counterRuntimeGasAvailable, counterContractAddress, EvmSemantics.EVM.State.fork,
    EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.replaceStackAndIncrPC]
  constructor
  · native_decide
  · constructor
    · native_decide
    · native_decide

theorem counterCompiledPreparedInitialize_second_ready
    {preparedState s1 : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1) :
    counterStepFEReady s1
      (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)) := by
  exact counterCompiledPreparedCall_second_ready hprepared hstep0

theorem counterCompiledPreparedCall_first_two_stepFE_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s1 s2,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      counterCompiledStateAt s2 2 ∧
      s2.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat 224, 1)) ∧
      s2.stack = [counterCallCalldataWord call] := by
  obtain ⟨s1, hstep0, hat1, hdecoded1, hstack1, hcalldata1⟩ :=
    counterCompiledPreparedCall_first_stepFE_ok hprepared
  have hready1 :=
    counterCompiledPreparedCall_second_ready hprepared hstep0
  have hreadyForHelper := hready1
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  let s2 :=
    (s1.consumeGas
      (EvmSemantics.EVM.Gas.baseCost s1.fork
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
          EvmSemantics.Operation)) hgas1).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat
          (EvmSemantics.Data.Bytes.bytesToBigEndianNat
            (EvmSemantics.MachineState.readPadded
              s1.executionEnv.calldata (EvmSemantics.UInt256.ofNat 0).toNat 32)) :: [])
  have hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2 := by
    unfold s2
    unfold EvmSemantics.EVM.stepFE
    simp only [Id.run]
    split
    · split
      · rename_i hprecompileActual
        rw [hprecompile1] at hprecompileActual
        contradiction
      · simp [hdecoded1, EvmSemantics.EVM.stepF.env]
        have hstackIf :
            ¬ 1024 +
                (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
                  EvmSemantics.Operation).popArity <
              s1.stack.length +
                (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
                  EvmSemantics.Operation).pushArity := by
          simpa using hstackOk1
        have hgasIf :
            EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s1)
                (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
                  EvmSemantics.Operation) ≤ s1.gasAvailable := by
          simpa using hgas1
        have hstackIfConcrete :
            ¬ 1024 +
                (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
                  EvmSemantics.Operation).popArity <
              1 + (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
                  EvmSemantics.Operation).pushArity := by
          native_decide
        simp [hstackIfConcrete, hgasIf, hstack1, EvmSemantics.EVM.State.consumeGas,
          EvmSemantics.EVM.State.replaceStackAndIncrPC]
    · rename_i hnotRunning
      rw [hrunning1] at hnotRunning
      contradiction
  obtain ⟨hat2, hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_for_call_ok
      (by simpa using hstack1) hcalldata1 hat1 hreadyForHelper hstep1
  exact ⟨s1, s2, hstep0, hstep1, hat2, hdecoded2, by simpa using hstack2⟩

theorem counterCompiledPreparedInitialize_first_two_stepFE_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s1 s2,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      counterCompiledStateAt s2 2 ∧
      s2.decoded =
        some (.Push counterPush1Op,
          some (EvmSemantics.UInt256.ofNat 224, 1)) ∧
      s2.stack = [counterInitializeCalldataWord] := by
  simpa [counterInitializeCalldataWord_eq] using
    counterCompiledPreparedCall_first_two_stepFE_ok
      (call := .initialize) hprepared

theorem counterCompiledPreparedCall_third_ready
    {preparedState s1 s2 : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2) :
    counterStepFEReady s2 (.Push counterPush1Op) := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedCall_entry_facts hprepared
  have hready0 := counterCompiledPreparedCall_first_ready hprepared
  have hready0ForState := hready0
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  obtain ⟨hat1, _hdecoded1, hstack1, _hcalldata1⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      hstack0 hat0 hready0ForState hstep0
  have hready1 := counterCompiledPreparedCall_second_ready hprepared hstep0
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  have hstate2 :=
    counterState_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1)
      (by simpa using hstack1) hstackOk1 hgas1 hstep1
  rcases hprepared with ⟨sourceState, rfl⟩
  have hs1Fork : s1.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs1Gas :
      s1.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  rw [hstate2]
  unfold counterStepFEReady
  simp [counterRuntimeGasAvailable, EvmSemantics.EVM.State.fork,
    EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.replaceStackAndIncrPC,
    hrunning1, hs1Fork, hs1Gas]
  constructor
  · simpa [EvmSemantics.EVM.State.fork, hs1Fork] using hprecompile1
  · constructor
    · native_decide
    · native_decide

theorem counterCompiledPreparedInitialize_third_ready
    {preparedState s1 s2 : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2) :
    counterStepFEReady s2 (.Push counterPush1Op) := by
  exact counterCompiledPreparedCall_third_ready hprepared hstep0 hstep1

theorem counterCompiledPreparedCall_first_three_stepFE_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s1 s2 s3,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      counterCompiledStateAt s3 4 ∧
      s3.decoded =
        some (.CompBit
          (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      s3.stack =
        EvmSemantics.UInt256.ofNat 224 :: counterCallCalldataWord call :: [] := by
  obtain ⟨s1, s2, hstep0, hstep1, hat2, hdecoded2, hstack2⟩ :=
    counterCompiledPreparedCall_first_two_stepFE_ok hprepared
  have hready2 :=
    counterCompiledPreparedCall_third_ready hprepared hstep0 hstep1
  have hreadyForHelper := hready2
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  let s3 :=
    (s2.consumeGas
      (EvmSemantics.EVM.Gas.baseCost s2.fork
        (.Push counterPush1Op : EvmSemantics.Operation)) hgas2).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat 224 :: s2.stack) (pcΔ := 2)
  have hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3 := by
    unfold s3
    unfold EvmSemantics.EVM.stepFE
    simp only [Id.run]
    split
    · split
      · rename_i hprecompileActual
        rw [hprecompile2] at hprecompileActual
        contradiction
      · simp [hdecoded2, EvmSemantics.EVM.stepF.push, counterPush1Op]
        by_cases hoverflow :
            1024 + (EvmSemantics.Operation.Push { width := 1 }).popArity <
              s2.stack.length +
                (EvmSemantics.Operation.Push { width := 1 }).pushArity
        · rw [hstack2] at hoverflow
          have hnoOverflow :
              ¬ 1024 + (EvmSemantics.Operation.Push { width := 1 }).popArity <
                1 + (EvmSemantics.Operation.Push { width := 1 }).pushArity := by
            native_decide
          exact False.elim (hnoOverflow hoverflow)
        · simp [hoverflow]
          have hgasIf :
              EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s2)
                  (EvmSemantics.Operation.Push { width := 1 }) ≤
                s2.gasAvailable := by
            simpa [counterPush1Op] using hgas2
          simp [hgasIf, hstack2, EvmSemantics.EVM.State.consumeGas,
            EvmSemantics.EVM.State.replaceStackAndIncrPC, EvmSemantics.UInt256.ofNat]
    · rename_i hnotRunning
      rw [hrunning2] at hnotRunning
      contradiction
  obtain ⟨hat3, hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_for_word_ok
      (word := counterCallCalldataWord call) hstack2 hat2 hreadyForHelper hstep2
  exact ⟨s1, s2, s3, hstep0, hstep1, hstep2, hat3, hdecoded3, by simpa using hstack3⟩

theorem counterCompiledPreparedInitialize_first_three_stepFE_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s1 s2 s3,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      counterCompiledStateAt s3 4 ∧
      s3.decoded =
        some (.CompBit
          (.SHR : EvmSemantics.Operation.CompareBitwiseOps), none) ∧
      s3.stack =
        EvmSemantics.UInt256.ofNat 224 :: counterInitializeCalldataWord :: [] := by
  simpa [counterInitializeCalldataWord_eq] using
    counterCompiledPreparedCall_first_three_stepFE_ok
      (call := .initialize) hprepared

theorem counterCompiledPreparedCall_fourth_ready
    {preparedState s1 s2 s3 : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3) :
    counterStepFEReady s3
      (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)) := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedCall_entry_facts hprepared
  have hready0 := counterCompiledPreparedCall_first_ready hprepared
  have hready0ForState := hready0
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      hstack0 hat0 hready0ForState hstep0
  have hready1 := counterCompiledPreparedCall_second_ready hprepared hstep0
  have hready1ForState := hready1
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  have hstate2 :=
    counterState_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1)
      (by simpa using hstack1) hstackOk1 hgas1 hstep1
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_for_call_ok
      (by simpa using hstack1) (hcalldata1.trans hcalldata0) hat1
      hready1ForState hstep1
  have hready2 := counterCompiledPreparedCall_third_ready
    hprepared hstep0 hstep1
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat2)
      hstackOk2 hgas2 hstep2
  rcases hprepared with ⟨sourceState, rfl⟩
  have hs1Fork : s1.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs1Gas :
      s1.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs2Fork : s2.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork]
  have hs2Gas :
      s2.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork, hs1Gas]
  rw [hstate3]
  unfold counterStepFEReady
  simp [counterRuntimeGasAvailable, EvmSemantics.EVM.State.fork,
    EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.replaceStackAndIncrPC,
    hrunning2, hs2Fork, hs2Gas, hstack2]
  constructor
  · simpa [EvmSemantics.EVM.State.fork, hs2Fork] using hprecompile2
  · constructor
    · native_decide
    · native_decide

theorem counterCompiledPreparedInitialize_fourth_ready
    {preparedState s1 s2 s3 : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3) :
    counterStepFEReady s3
      (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)) := by
  exact counterCompiledPreparedCall_fourth_ready
    hprepared hstep0 hstep1 hstep2

theorem counterCompiledPreparedCall_first_four_stepFE_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s1 s2 s3 s4,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      EvmSemantics.EVM.stepFE s3 = .ok s4 ∧
      counterCompiledStateAt s4 5 ∧
      s4.decoded = some (.Dup counterDup1Op, none) ∧
      s4.stack =
        [EvmSemantics.UInt256.ofNat (counterCallSelectorNat call)] := by
  obtain ⟨s1, s2, s3, hstep0, hstep1, hstep2, hat3, hdecoded3, hstack3⟩ :=
    counterCompiledPreparedCall_first_three_stepFE_ok hprepared
  have hready3 :=
    counterCompiledPreparedCall_fourth_ready hprepared hstep0 hstep1 hstep2
  have hreadyForHelper := hready3
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  let s4 :=
    (s3.consumeGas
      (EvmSemantics.EVM.Gas.baseCost s3.fork
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
          EvmSemantics.Operation)) hgas3).replaceStackAndIncrPC
        (EvmSemantics.UInt256.shiftRight (counterCallCalldataWord call)
          (EvmSemantics.UInt256.ofNat 224) :: [])
  have hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4 := by
    unfold s4
    unfold EvmSemantics.EVM.stepFE
    simp only [Id.run]
    split
    · split
      · rename_i hprecompileActual
        rw [hprecompile3] at hprecompileActual
        contradiction
      · simp [hdecoded3, EvmSemantics.EVM.stepF.compBit]
        by_cases hoverflow :
            1024 +
                (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
                  EvmSemantics.Operation).popArity <
              s3.stack.length +
                (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
                  EvmSemantics.Operation).pushArity
        · rw [hstack3] at hoverflow
          have hnoOverflow :
              ¬ 1024 +
                  (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
                    EvmSemantics.Operation).popArity <
                2 + (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
                    EvmSemantics.Operation).pushArity := by
            native_decide
          exact False.elim (hnoOverflow hoverflow)
        · simp [hoverflow]
          have hgasIf :
              EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s3)
                  (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
                    EvmSemantics.Operation) ≤
                s3.gasAvailable := by
            simpa using hgas3
          simp [hgasIf, hstack3, EvmSemantics.EVM.State.consumeGas,
            EvmSemantics.EVM.State.replaceStackAndIncrPC]
    · rename_i hnotRunning
      rw [hrunning3] at hnotRunning
      contradiction
  obtain ⟨hat4, hdecoded4, hstack4⟩ :=
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_for_call_ok
      (call := call)
      hstack3 hat3 hreadyForHelper hstep3
  exact ⟨s1, s2, s3, s4, hstep0, hstep1, hstep2, hstep3,
    hat4, hdecoded4, by simpa using hstack4⟩

theorem counterCompiledPreparedInitialize_first_four_stepFE_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s1 s2 s3 s4,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      EvmSemantics.EVM.stepFE s3 = .ok s4 ∧
      counterCompiledStateAt s4 5 ∧
      s4.decoded = some (.Dup counterDup1Op, none) ∧
      s4.stack =
        [EvmSemantics.UInt256.ofNat counterInitializeSelectorNat] := by
  simpa [counterInitializeCalldataWord_eq, counterInitializeSelectorNat_eq] using
    counterCompiledPreparedCall_first_four_stepFE_ok
      (call := .initialize) hprepared

theorem counterCompiledPreparedInitialize_first_four_path_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s4,
      EvmStepFEPath preparedState 4 s4 ∧
      counterCompiledStateAt s4 5 ∧
      s4.decoded = some (.Dup counterDup1Op, none) ∧
      s4.stack =
        [EvmSemantics.UInt256.ofNat counterInitializeSelectorNat] := by
  obtain ⟨s1, s2, s3, s4, hstep0, hstep1, hstep2, hstep3,
      hat4, hdecoded4, hstack4⟩ :=
    counterCompiledPreparedInitialize_first_four_stepFE_ok hprepared
  have hready0 := counterCompiledPreparedInitialize_first_ready hprepared
  have hready1 := counterCompiledPreparedInitialize_second_ready hprepared hstep0
  have hready2 := counterCompiledPreparedInitialize_third_ready hprepared hstep0 hstep1
  have hready3 :=
    counterCompiledPreparedInitialize_fourth_ready hprepared hstep0 hstep1 hstep2
  refine ⟨s4, ?_, hat4, hdecoded4, hstack4⟩
  exact ProofForge.Backend.Evm.PowdrExec.stepFEPath_four
    hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
    hready3.1 hstep3

theorem counterCompiledPreparedCall_fifth_ready
    {preparedState s1 s2 s3 s4 : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    counterStepFEReady s4 (.Dup counterDup1Op) := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedCall_entry_facts hprepared
  have hready0 := counterCompiledPreparedCall_first_ready hprepared
  have hready0ForState := hready0
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      hstack0 hat0 hready0ForState hstep0
  have hready1 := counterCompiledPreparedCall_second_ready hprepared hstep0
  have hready1ForState := hready1
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  have hstate2 :=
    counterState_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1)
      (by simpa using hstack1) hstackOk1 hgas1 hstep1
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_for_call_ok
      (by simpa using hstack1) (hcalldata1.trans hcalldata0) hat1
      hready1ForState hstep1
  have hready2 := counterCompiledPreparedCall_third_ready
    hprepared hstep0 hstep1
  have hready2ForState := hready2
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat2)
      hstackOk2 hgas2 hstep2
  obtain ⟨hat3, _hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_for_word_ok
      (word := counterCallCalldataWord call)
      hstack2 hat2 hready2ForState hstep2
  have hready3 :=
    counterCompiledPreparedCall_fourth_ready hprepared hstep0 hstep1 hstep2
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  have hstate4 :=
    counterState_of_stepFE_compBit_shr_ok hrunning3 hprecompile3
      (counterPreparedDispatcherSelectorShr_decoded hat3)
      hstack3 hstackOk3 hgas3 hstep3
  rcases hprepared with ⟨sourceState, rfl⟩
  have hs1Fork : s1.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs1Gas :
      s1.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs2Fork : s2.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork]
  have hs2Gas :
      s2.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork, hs1Gas]
  have hs3Fork : s3.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs2Fork]
  have hs3Gas :
      s3.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush1Op : EvmSemantics.Operation) := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs2Fork, hs2Gas]
  rw [hstate4]
  unfold counterStepFEReady
  simp [counterRuntimeGasAvailable, EvmSemantics.EVM.State.fork,
    EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.replaceStackAndIncrPC,
    hrunning3, hs3Fork, hs3Gas, hstack3]
  constructor
  · simpa [EvmSemantics.EVM.State.fork, hs3Fork] using hprecompile3
  · constructor
    · native_decide
    · native_decide

theorem counterCompiledPreparedInitialize_fifth_ready
    {preparedState s1 s2 s3 s4 : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4) :
    counterStepFEReady s4 (.Dup counterDup1Op) := by
  exact counterCompiledPreparedCall_fifth_ready
    hprepared hstep0 hstep1 hstep2 hstep3

theorem counterCompiledPreparedCall_first_five_stepFE_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s1 s2 s3 s4 s5,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      EvmSemantics.EVM.stepFE s3 = .ok s4 ∧
      EvmSemantics.EVM.stepFE s4 = .ok s5 ∧
      counterCompiledStateAt s5 6 ∧
      s5.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      s5.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) ::
          EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: [] := by
  obtain ⟨s1, s2, s3, s4, hstep0, hstep1, hstep2, hstep3,
      hat4, hdecoded4, hstack4⟩ :=
    counterCompiledPreparedCall_first_four_stepFE_ok hprepared
  have hready4 :=
    counterCompiledPreparedCall_fifth_ready hprepared
      hstep0 hstep1 hstep2 hstep3
  have hreadyForHelper := hready4
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  let s5 :=
    (s4.consumeGas
      (EvmSemantics.EVM.Gas.baseCost s4.fork
        (.Dup counterDup1Op : EvmSemantics.Operation)) hgas4).replaceStackAndIncrPC
        (EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) ::
          EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: [])
  have hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5 := by
    unfold s5
    unfold EvmSemantics.EVM.stepFE
    simp only [Id.run]
    split
    · split
      · rename_i hprecompileActual
        rw [hprecompile4] at hprecompileActual
        contradiction
      · simp [hdecoded4, EvmSemantics.EVM.stepF.dup, counterDup1Op]
        by_cases hoverflow :
            1024 + (EvmSemantics.Operation.Dup counterDup1Op).popArity <
              s4.stack.length +
                (EvmSemantics.Operation.Dup counterDup1Op).pushArity
        · rw [hstack4] at hoverflow
          have hnoOverflow :
              ¬ 1024 + (EvmSemantics.Operation.Dup counterDup1Op).popArity <
                1 + (EvmSemantics.Operation.Dup counterDup1Op).pushArity := by
            native_decide
          exact False.elim (hnoOverflow hoverflow)
        ·
          have hgasIf :
              EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s4)
                  (EvmSemantics.Operation.Dup counterDup1Op) ≤
                s4.gasAvailable := by
            simpa using hgas4
          have hnoOverflowConcrete :
              ¬ 1024 + (EvmSemantics.Operation.Dup { idx := 0 }).popArity <
                1 + (EvmSemantics.Operation.Dup { idx := 0 }).pushArity := by
            native_decide
          have hgasIfConcrete :
              EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s4)
                  (EvmSemantics.Operation.Dup { idx := 0 }) ≤
                s4.gasAvailable := by
            change EvmSemantics.EVM.Gas.baseCost (EvmSemantics.EVM.State.fork s4)
                  (EvmSemantics.Operation.Dup counterDup1Op) ≤
                s4.gasAvailable
            exact hgas4
          simp [hnoOverflowConcrete, hgasIfConcrete, hstack4,
            EvmSemantics.EVM.State.consumeGas,
            EvmSemantics.EVM.State.replaceStackAndIncrPC]
    · rename_i hnotRunning
      rw [hrunning4] at hnotRunning
      contradiction
  obtain ⟨hat5, hdecoded5, hstack5⟩ :=
    counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_for_call_ok
      (call := call)
      hstack4 hat4 hreadyForHelper hstep4
  exact ⟨s1, s2, s3, s4, s5, hstep0, hstep1, hstep2, hstep3, hstep4,
    hat5, hdecoded5, by simpa using hstack5⟩

theorem counterCompiledPreparedInitialize_first_five_stepFE_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s1 s2 s3 s4 s5,
      EvmSemantics.EVM.stepFE preparedState = .ok s1 ∧
      EvmSemantics.EVM.stepFE s1 = .ok s2 ∧
      EvmSemantics.EVM.stepFE s2 = .ok s3 ∧
      EvmSemantics.EVM.stepFE s3 = .ok s4 ∧
      EvmSemantics.EVM.stepFE s4 = .ok s5 ∧
      counterCompiledStateAt s5 6 ∧
      s5.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      s5.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: [] := by
  simpa [counterInitializeSelectorNat_eq] using
    counterCompiledPreparedCall_first_five_stepFE_ok
      (call := .initialize) hprepared

theorem counterCompiledPreparedCall_first_five_path_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s5,
      EvmStepFEPath preparedState 5 s5 ∧
      counterCompiledStateAt s5 6 ∧
      s5.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      s5.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) ::
          EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: [] := by
  obtain ⟨s1, s2, s3, s4, s5, hstep0, hstep1, hstep2, hstep3, hstep4,
      hat5, hdecoded5, hstack5⟩ :=
    counterCompiledPreparedCall_first_five_stepFE_ok hprepared
  have hready0 := counterCompiledPreparedCall_first_ready hprepared
  have hready1 := counterCompiledPreparedCall_second_ready hprepared hstep0
  have hready2 := counterCompiledPreparedCall_third_ready hprepared hstep0 hstep1
  have hready3 :=
    counterCompiledPreparedCall_fourth_ready hprepared hstep0 hstep1 hstep2
  have hready4 :=
    counterCompiledPreparedCall_fifth_ready hprepared
      hstep0 hstep1 hstep2 hstep3
  refine ⟨s5, ?_, hat5, hdecoded5, hstack5⟩
  exact ProofForge.Backend.Evm.PowdrExec.stepFEPath_five
    hready0.1 hstep0 hready1.1 hstep1 hready2.1 hstep2
    hready3.1 hstep3 hready4.1 hstep4

theorem counterCompiledPreparedCall_selector_prefix_reduction_chain_ok
    {preparedState : EvmState}
    {call : CounterCall}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig call preparedState) :
    ∃ s5,
      ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain
        preparedState 5 s5 ∧
      counterCompiledStateAt s5 6 ∧
      s5.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      s5.stack =
        EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) ::
          EvmSemantics.UInt256.ofNat (counterCallSelectorNat call) :: [] := by
  obtain ⟨s5, path, hat5, hdecoded5, hstack5⟩ :=
    counterCompiledPreparedCall_first_five_path_ok hprepared
  exact ⟨s5,
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain.of_stepFEPath path,
    hat5, hdecoded5, hstack5⟩

theorem counterCompiledPreparedInitialize_first_five_path_ok
    {preparedState : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState) :
    ∃ s5,
      EvmStepFEPath preparedState 5 s5 ∧
      counterCompiledStateAt s5 6 ∧
      s5.decoded =
        some (.Push counterPush4Op,
          some (EvmSemantics.UInt256.ofNat counterInitializeSelectorNat, 4)) ∧
      s5.stack =
        EvmSemantics.UInt256.ofNat counterInitializeSelectorNat ::
          EvmSemantics.UInt256.ofNat counterInitializeSelectorNat :: [] := by
  simpa [counterInitializeSelectorNat_eq] using
    counterCompiledPreparedCall_first_five_path_ok
      (call := .initialize) hprepared

theorem counterCompiledPreparedInitialize_sixth_ready
    {preparedState s1 s2 s3 s4 s5 : EvmState}
    (hprepared :
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState)
    (hstep0 : EvmSemantics.EVM.stepFE preparedState = .ok s1)
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5) :
    counterStepFEReady s5 (.Push counterPush4Op) := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedInitialize_entry_facts hprepared
  have hready0 := counterCompiledPreparedInitialize_first_ready hprepared
  have hready0ForState := hready0
  rcases hready0 with ⟨hrunning0, hprecompile0, hstackOk0, hgas0⟩
  have hstate1 :=
    counterState_of_stepFE_push0_ok hrunning0 hprecompile0
      (counterPreparedDispatcherFirstPush0_decoded hat0) hstackOk0 hgas0 hstep0
  obtain ⟨hat1, _hdecoded1, hstack1, hcalldata1⟩ :=
    counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok
      hstack0 hat0 hready0ForState hstep0
  have hready1 := counterCompiledPreparedInitialize_second_ready hprepared hstep0
  have hready1ForState := hready1
  rcases hready1 with ⟨hrunning1, hprecompile1, hstackOk1, hgas1⟩
  have hstate2 :=
    counterState_of_stepFE_env_calldataload_ok hrunning1 hprecompile1
      (counterPreparedDispatcherCalldataload_decoded hat1)
      (by simpa using hstack1) hstackOk1 hgas1 hstep1
  obtain ⟨hat2, _hdecoded2, hstack2⟩ :=
    counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok
      (by simpa using hstack1) (hcalldata1.trans hcalldata0) hat1
      hready1ForState hstep1
  have hready2 := counterCompiledPreparedInitialize_third_ready
    hprepared hstep0 hstep1
  have hready2ForState := hready2
  rcases hready2 with ⟨hrunning2, hprecompile2, hstackOk2, hgas2⟩
  have hstate3 :=
    counterState_of_stepFE_push1_ok hrunning2 hprecompile2
      (counterPreparedDispatcherSelectorShiftPush224_decoded hat2)
      hstackOk2 hgas2 hstep2
  obtain ⟨hat3, _hdecoded3, hstack3⟩ :=
    counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok
      hstack2 hat2 hready2ForState hstep2
  have hready3 :=
    counterCompiledPreparedInitialize_fourth_ready hprepared hstep0 hstep1 hstep2
  have hready3ForState := hready3
  rcases hready3 with ⟨hrunning3, hprecompile3, hstackOk3, hgas3⟩
  have hstate4 :=
    counterState_of_stepFE_compBit_shr_ok hrunning3 hprecompile3
      (counterPreparedDispatcherSelectorShr_decoded hat3)
      hstack3 hstackOk3 hgas3 hstep3
  obtain ⟨hat4, _hdecoded4, hstack4⟩ :=
    counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok
      hstack3 hat3 hready3ForState hstep3
  have hready4 :=
    counterCompiledPreparedInitialize_fifth_ready hprepared
      hstep0 hstep1 hstep2 hstep3
  rcases hready4 with ⟨hrunning4, hprecompile4, hstackOk4, hgas4⟩
  have hstate5 :=
    counterState_of_stepFE_dup1_ok hrunning4 hprecompile4
      (counterPreparedDispatcherSelectorDup1_decoded hat4)
      hstack4 hstackOk4 hgas4 hstep4
  rcases hprepared with ⟨sourceState, rfl⟩
  have hs1Fork : s1.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs1Gas :
      s1.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) := by
    rw [hstate1]
    simp [counterCompiledPowdrConfig, prepareCounterCall, counterCallExecutionEnv,
      EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC]
  have hs2Fork : s2.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork]
  have hs2Gas :
      s2.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) := by
    rw [hstate2]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs1Fork, hs1Gas]
  have hs3Fork : s3.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs2Fork]
  have hs3Gas :
      s3.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush1Op : EvmSemantics.Operation) := by
    rw [hstate3]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs2Fork, hs2Gas]
  have hs4Fork : s4.fork = EvmSemantics.Fork.Cancun := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs3Fork]
  have hs4Gas :
      s4.gasAvailable =
        counterRuntimeGasAvailable -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush0Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps) :
              EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.Push counterPush1Op : EvmSemantics.Operation) -
          EvmSemantics.EVM.Gas.baseCost EvmSemantics.Fork.Cancun
            (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps) :
              EvmSemantics.Operation) := by
    rw [hstate4]
    simp [EvmSemantics.EVM.State.fork, EvmSemantics.EVM.State.consumeGas,
      EvmSemantics.EVM.State.replaceStackAndIncrPC, hs3Fork, hs3Gas]
  rw [hstate5]
  unfold counterStepFEReady
  simp [counterRuntimeGasAvailable, EvmSemantics.EVM.State.fork,
    EvmSemantics.EVM.State.consumeGas, EvmSemantics.EVM.State.replaceStackAndIncrPC,
    hrunning4, hs4Fork, hs4Gas, hstack4]
  constructor
  · simpa [EvmSemantics.EVM.State.fork, hs4Fork] using hprecompile4
  · constructor
    · native_decide
    · native_decide

structure CounterPreparedInitializeStepFEPath (s0 s36 : EvmState) where
  s1 : EvmState
  s2 : EvmState
  s3 : EvmState
  s4 : EvmState
  s5 : EvmState
  s6 : EvmState
  s7 : EvmState
  s8 : EvmState
  s9 : EvmState
  s10 : EvmState
  s11 : EvmState
  s12 : EvmState
  s13 : EvmState
  s14 : EvmState
  s15 : EvmState
  s16 : EvmState
  s17 : EvmState
  s18 : EvmState
  s19 : EvmState
  s20 : EvmState
  s21 : EvmState
  s22 : EvmState
  s23 : EvmState
  s24 : EvmState
  s25 : EvmState
  s26 : EvmState
  s27 : EvmState
  s28 : EvmState
  s29 : EvmState
  s30 : EvmState
  s31 : EvmState
  s32 : EvmState
  s33 : EvmState
  s34 : EvmState
  s35 : EvmState
  hready0 : counterStepFEReady s0 (.Push counterPush0Op)
  hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1
  hready1 :
    counterStepFEReady s1
      (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps))
  hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2
  hready2 : counterStepFEReady s2 (.Push counterPush1Op)
  hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3
  hready3 :
    counterStepFEReady s3
      (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps))
  hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4
  hready4 : counterStepFEReady s4 (.Dup counterDup1Op)
  hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5
  hready5 : counterStepFEReady s5 (.Push counterPush4Op)
  hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6
  hready6 :
    counterStepFEReady s6
      (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps))
  hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7
  hready7 : counterStepFEReady s7 (.Push counterPush1Op)
  hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8
  hready8 :
    counterStepFEReady s8
      (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps))
  hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9
  hready9 :
    counterStepFEReady s9
      (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
  hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10
  hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1)
  hready10 : counterStepFEReady s10 (.Push counterPush1Op)
  hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11
  hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3)
  hready11 : counterStepFEReady s11 (.Push counterPush1Op)
  hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12
  hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5)
  hready12 :
    counterStepFEReady s12
      (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps))
  hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13
  hready13 :
    counterStepFEReady s13
      (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
  hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14
  hready14 : counterStepFEReady s14 (.Push counterPush0Op)
  hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15
  hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 2)
  hready15 : counterStepFEReady s15 (.Push counterPush1Op)
  hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16
  hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 4)
  hready16 :
    counterStepFEReady s16
      (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps))
  hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17
  hat17 : counterCompiledStateAt s17 (counterInitializeBodyOffset + 5)
  hready17 : counterStepFEReady s17 (.Push counterPush1Op)
  hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18
  hat18 : counterCompiledStateAt s18 (counterInitializeBodyOffset + 7)
  hready18 : counterStepFEReady s18 (.Dup counterDup1Op)
  hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19
  hat19 : counterCompiledStateAt s19 (counterInitializeBodyOffset + 8)
  hready19 : counterStepFEReady s19 (.Push counterPush1Op)
  hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20
  hat20 : counterCompiledStateAt s20 (counterInitializeBodyOffset + 10)
  hready20 :
    counterStepFEReady s20
      (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps))
  hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21
  hat21 : counterCompiledStateAt s21 (counterInitializeBodyOffset + 11)
  hready21 :
    counterStepFEReady s21
      (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps))
  hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22
  hat22 : counterCompiledStateAt s22 (counterInitializeBodyOffset + 12)
  hready22 : counterStepFEReady s22 (.Push counterPush1Op)
  hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23
  hat23 : counterCompiledStateAt s23 (counterInitializeBodyOffset + 14)
  hready23 :
    counterStepFEReady s23
      (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps))
  hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24
  hat24 : counterCompiledStateAt s24 (counterInitializeBodyOffset + 15)
  hready24 :
    counterStepFEReady s24
      (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps))
  hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25
  hat25 : counterCompiledStateAt s25 (counterInitializeBodyOffset + 16)
  hready25 : counterStepFEReady s25 (.Push counterPush0Op)
  hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26
  hat26 : counterCompiledStateAt s26 (counterInitializeBodyOffset + 17)
  haddrSload : s26.executionEnv.address = counterContractAddress
  hready26 :
    counterStepFEReady s26
      (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps))
  hstep26 : EvmSemantics.EVM.stepFE s26 = .ok s27
  hat27 : counterCompiledStateAt s27 (counterInitializeBodyOffset + 18)
  hready27 :
    counterStepFEReady s27
      (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps))
  hstep27 : EvmSemantics.EVM.stepFE s27 = .ok s28
  hat28 : counterCompiledStateAt s28 (counterInitializeBodyOffset + 19)
  hready28 :
    counterStepFEReady s28
      (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps))
  hstep28 : EvmSemantics.EVM.stepFE s28 = .ok s29
  hat29 : counterCompiledStateAt s29 (counterInitializeBodyOffset + 20)
  hready29 : counterStepFEReady s29 (.Push counterPush0Op)
  hstep29 : EvmSemantics.EVM.stepFE s29 = .ok s30
  hat30 : counterCompiledStateAt s30 (counterInitializeBodyOffset + 21)
  haddrSstore : s30.executionEnv.address = counterContractAddress
  hready30 :
    counterStepFEReady s30
      (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps))
  hstep30 : EvmSemantics.EVM.stepFE s30 = .ok s31
  hready31 :
    counterStepFEReady s31
      (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps))
  hstep31 : EvmSemantics.EVM.stepFE s31 = .ok s32
  hready32 :
    counterStepFEReady s32
      (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps))
  hstep32 : EvmSemantics.EVM.stepFE s32 = .ok s33
  hready33 : counterStepFEReady s33 (.Push counterPush0Op)
  hstep33 : EvmSemantics.EVM.stepFE s33 = .ok s34
  hready34 : counterStepFEReady s34 (.Dup counterDup1Op)
  hstep34 : EvmSemantics.EVM.stepFE s34 = .ok s35
  hready35 :
    counterStepFEReady s35
      (.System (.RETURN : EvmSemantics.Operation.SystemOps))
  hstep35 : EvmSemantics.EVM.stepFE s35 = .ok s36

theorem counterPreparedInitializeStepFEPath_to_path
    {s0 s36 : EvmState}
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    EvmStepFEPath s0 36 s36 := by
  exact counterStepFEPath_initialize_dispatcher_body_and_return_ok
    path.hready0 path.hstep0 path.hready1 path.hstep1
    path.hready2 path.hstep2 path.hready3 path.hstep3
    path.hready4 path.hstep4 path.hready5 path.hstep5
    path.hready6 path.hstep6 path.hready7 path.hstep7
    path.hready8 path.hstep8 path.hready9 path.hstep9
    path.hready10 path.hstep10 path.hready11 path.hstep11
    path.hready12 path.hstep12 path.hready13 path.hstep13
    path.hready14 path.hstep14 path.hready15 path.hstep15
    path.hready16 path.hstep16 path.hready17 path.hstep17
    path.hready18 path.hstep18 path.hready19 path.hstep19
    path.hready20 path.hstep20 path.hready21 path.hstep21
    path.hready22 path.hstep22 path.hready23 path.hstep23
    path.hready24 path.hstep24 path.hready25 path.hstep25
    path.hready26 path.hstep26 path.hready27 path.hstep27
    path.hready28 path.hstep28 path.hready29 path.hstep29
    path.hready30 path.hstep30 path.hready31 path.hstep31
    path.hready32 path.hstep32 path.hready33 path.hstep33
    path.hready34 path.hstep34 path.hready35 path.hstep35

theorem counterPreparedInitializeStepFEPath_to_reductionChain
    {s0 s36 : EvmState}
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 36 s36 := by
  exact counterStepFEReductionChain_initialize_dispatcher_body_and_return_ok
    path.hready0 path.hstep0 path.hready1 path.hstep1
    path.hready2 path.hstep2 path.hready3 path.hstep3
    path.hready4 path.hstep4 path.hready5 path.hstep5
    path.hready6 path.hstep6 path.hready7 path.hstep7
    path.hready8 path.hstep8 path.hready9 path.hstep9
    path.hready10 path.hstep10 path.hready11 path.hstep11
    path.hready12 path.hstep12 path.hready13 path.hstep13
    path.hready14 path.hstep14 path.hready15 path.hstep15
    path.hready16 path.hstep16 path.hready17 path.hstep17
    path.hready18 path.hstep18 path.hready19 path.hstep19
    path.hready20 path.hstep20 path.hready21 path.hstep21
    path.hready22 path.hstep22 path.hready23 path.hstep23
    path.hready24 path.hstep24 path.hready25 path.hstep25
    path.hready26 path.hstep26 path.hready27 path.hstep27
    path.hready28 path.hstep28 path.hready29 path.hstep29
    path.hready30 path.hstep30 path.hready31 path.hstep31
    path.hready32 path.hstep32 path.hready33 path.hstep33
    path.hready34 path.hstep34 path.hready35 path.hstep35

def counterPreparedInitializeSegmentPre (state : EvmState) : Prop :=
  CounterPreparedCall counterCompiledPowdrConfig .initialize state

def counterPreparedInitializeSegmentPost (state finalState : EvmState) : Prop :=
  finalState.halt = .Returned ∧
    finalState.callStack = state.callStack ∧
    counterStorageValue counterContractAddress counterCountSlot finalState =
      counterInitializeStorageWord
        (counterStorageValue counterContractAddress counterCountSlot state) ∧
    counterObservableFromResult .initialize finalState.toResult = .ok .none

structure CounterPreparedInitializeSegmentModel (s0 s36 : EvmState) where
  segment :
    ProofForge.Backend.Evm.PowdrExec.ExecutionSegment 36
      counterPreparedInitializeSegmentPost s0 s36

structure CounterPreparedInitializeReductionChainModel (s0 s36 : EvmState) where
  chain :
    ProofForge.Backend.Evm.PowdrExec.StepFEReductionChain s0 36 s36
  postcondition : counterPreparedInitializeSegmentPost s0 s36

theorem counterCompiledPreparedInitialize_storage_model_of_dispatcher_body_and_return_ok
    {s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17
      s18 s19 s20 s21 s22 s23 s24 s25 s26 s27 s28 s29 s30 s31 s32 s33
      s34 s35 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (hready0 : counterStepFEReady s0 (.Push counterPush0Op))
    (hstep0 : EvmSemantics.EVM.stepFE s0 = .ok s1)
    (hready1 :
      counterStepFEReady s1
        (.Env (.CALLDATALOAD : EvmSemantics.Operation.EnvOps)))
    (hstep1 : EvmSemantics.EVM.stepFE s1 = .ok s2)
    (hready2 : counterStepFEReady s2 (.Push counterPush1Op))
    (hstep2 : EvmSemantics.EVM.stepFE s2 = .ok s3)
    (hready3 :
      counterStepFEReady s3
        (.CompBit (.SHR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep3 : EvmSemantics.EVM.stepFE s3 = .ok s4)
    (hready4 : counterStepFEReady s4 (.Dup counterDup1Op))
    (hstep4 : EvmSemantics.EVM.stepFE s4 = .ok s5)
    (hready5 : counterStepFEReady s5 (.Push counterPush4Op))
    (hstep5 : EvmSemantics.EVM.stepFE s5 = .ok s6)
    (hready6 :
      counterStepFEReady s6
        (.CompBit (.EQ : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep6 : EvmSemantics.EVM.stepFE s6 = .ok s7)
    (hready7 : counterStepFEReady s7 (.Push counterPush1Op))
    (hstep7 : EvmSemantics.EVM.stepFE s7 = .ok s8)
    (hready8 :
      counterStepFEReady s8
        (.StackMemFlow (.JUMPI : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep8 : EvmSemantics.EVM.stepFE s8 = .ok s9)
    (hready9 :
      counterStepFEReady s9
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep9 : EvmSemantics.EVM.stepFE s9 = .ok s10)
    (hat10 : counterCompiledStateAt s10 (counterInitializeTrampolineOffset + 1))
    (hready10 : counterStepFEReady s10 (.Push counterPush1Op))
    (hstep10 : EvmSemantics.EVM.stepFE s10 = .ok s11)
    (hat11 : counterCompiledStateAt s11 (counterInitializeTrampolineOffset + 3))
    (hready11 : counterStepFEReady s11 (.Push counterPush1Op))
    (hstep11 : EvmSemantics.EVM.stepFE s11 = .ok s12)
    (hat12 : counterCompiledStateAt s12 (counterInitializeTrampolineOffset + 5))
    (hready12 :
      counterStepFEReady s12
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep12 : EvmSemantics.EVM.stepFE s12 = .ok s13)
    (hready13 :
      counterStepFEReady s13
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep13 : EvmSemantics.EVM.stepFE s13 = .ok s14)
    (hready14 : counterStepFEReady s14 (.Push counterPush0Op))
    (hstep14 : EvmSemantics.EVM.stepFE s14 = .ok s15)
    (hat15 : counterCompiledStateAt s15 (counterInitializeBodyOffset + 2))
    (hready15 : counterStepFEReady s15 (.Push counterPush1Op))
    (hstep15 : EvmSemantics.EVM.stepFE s15 = .ok s16)
    (hat16 : counterCompiledStateAt s16 (counterInitializeBodyOffset + 4))
    (hready16 :
      counterStepFEReady s16
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep16 : EvmSemantics.EVM.stepFE s16 = .ok s17)
    (hat17 : counterCompiledStateAt s17 (counterInitializeBodyOffset + 5))
    (hready17 : counterStepFEReady s17 (.Push counterPush1Op))
    (hstep17 : EvmSemantics.EVM.stepFE s17 = .ok s18)
    (hat18 : counterCompiledStateAt s18 (counterInitializeBodyOffset + 7))
    (hready18 : counterStepFEReady s18 (.Dup counterDup1Op))
    (hstep18 : EvmSemantics.EVM.stepFE s18 = .ok s19)
    (hat19 : counterCompiledStateAt s19 (counterInitializeBodyOffset + 8))
    (hready19 : counterStepFEReady s19 (.Push counterPush1Op))
    (hstep19 : EvmSemantics.EVM.stepFE s19 = .ok s20)
    (hat20 : counterCompiledStateAt s20 (counterInitializeBodyOffset + 10))
    (hready20 :
      counterStepFEReady s20
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep20 : EvmSemantics.EVM.stepFE s20 = .ok s21)
    (hat21 : counterCompiledStateAt s21 (counterInitializeBodyOffset + 11))
    (hready21 :
      counterStepFEReady s21
        (.StopArith (.SUB : EvmSemantics.Operation.StopArithOps)))
    (hstep21 : EvmSemantics.EVM.stepFE s21 = .ok s22)
    (hat22 : counterCompiledStateAt s22 (counterInitializeBodyOffset + 12))
    (hready22 : counterStepFEReady s22 (.Push counterPush1Op))
    (hstep22 : EvmSemantics.EVM.stepFE s22 = .ok s23)
    (hat23 : counterCompiledStateAt s23 (counterInitializeBodyOffset + 14))
    (hready23 :
      counterStepFEReady s23
        (.CompBit (.SHL : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep23 : EvmSemantics.EVM.stepFE s23 = .ok s24)
    (hat24 : counterCompiledStateAt s24 (counterInitializeBodyOffset + 15))
    (hready24 :
      counterStepFEReady s24
        (.CompBit (.NOT : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep24 : EvmSemantics.EVM.stepFE s24 = .ok s25)
    (hat25 : counterCompiledStateAt s25 (counterInitializeBodyOffset + 16))
    (hready25 : counterStepFEReady s25 (.Push counterPush0Op))
    (hstep25 : EvmSemantics.EVM.stepFE s25 = .ok s26)
    (hat26 : counterCompiledStateAt s26 (counterInitializeBodyOffset + 17))
    (haddrSload : s26.executionEnv.address = counterContractAddress)
    (hready26 :
      counterStepFEReady s26
        (.StackMemFlow (.SLOAD : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep26 : EvmSemantics.EVM.stepFE s26 = .ok s27)
    (hat27 : counterCompiledStateAt s27 (counterInitializeBodyOffset + 18))
    (hready27 :
      counterStepFEReady s27
        (.CompBit (.AND : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep27 : EvmSemantics.EVM.stepFE s27 = .ok s28)
    (hat28 : counterCompiledStateAt s28 (counterInitializeBodyOffset + 19))
    (hready28 :
      counterStepFEReady s28
        (.CompBit (.OR : EvmSemantics.Operation.CompareBitwiseOps)))
    (hstep28 : EvmSemantics.EVM.stepFE s28 = .ok s29)
    (hat29 : counterCompiledStateAt s29 (counterInitializeBodyOffset + 20))
    (hready29 : counterStepFEReady s29 (.Push counterPush0Op))
    (hstep29 : EvmSemantics.EVM.stepFE s29 = .ok s30)
    (hat30 : counterCompiledStateAt s30 (counterInitializeBodyOffset + 21))
    (haddrSstore : s30.executionEnv.address = counterContractAddress)
    (hready30 :
      counterStepFEReady s30
        (.StackMemFlow (.SSTORE : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep30 : EvmSemantics.EVM.stepFE s30 = .ok s31)
    (hready31 :
      counterStepFEReady s31
        (.StackMemFlow (.JUMP : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep31 : EvmSemantics.EVM.stepFE s31 = .ok s32)
    (hready32 :
      counterStepFEReady s32
        (.StackMemFlow (.JUMPDEST : EvmSemantics.Operation.StackMemFlowOps)))
    (hstep32 : EvmSemantics.EVM.stepFE s32 = .ok s33)
    (hready33 : counterStepFEReady s33 (.Push counterPush0Op))
    (hstep33 : EvmSemantics.EVM.stepFE s33 = .ok s34)
    (hready34 : counterStepFEReady s34 (.Dup counterDup1Op))
    (hstep34 : EvmSemantics.EVM.stepFE s34 = .ok s35)
    (hready35 :
      counterStepFEReady s35
        (.System (.RETURN : EvmSemantics.Operation.SystemOps)))
    (hstep35 : EvmSemantics.EVM.stepFE s35 = .ok s36) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig s0 .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s0) := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedInitialize_entry_facts hprepared
  obtain ⟨hrun, hhalt, hstorageRun, hstoragePrefix, _hcallStackReturn,
      _hcallStackBody, hcallStackPrepared, hobs⟩ :=
    counterRunBytecode_initialize_dispatcher_body_and_return_ok
      hstack0 hat0 hready0 hstep0 hcalldata0 hready1 hstep1
      hready2 hstep2 hready3 hstep3 hready4 hstep4
      hready5 hstep5 hready6 hstep6 hready7 hstep7
      hready8 hstep8 hready9 hstep9 hat10 hready10 hstep10
      hat11 hready11 hstep11 hat12 hready12 hstep12
      hready13 hstep13 hready14 hstep14 hat15 hready15 hstep15
      hat16 hready16 hstep16 hat17 hready17 hstep17
      hat18 hready18 hstep18 hat19 hready19 hstep19
      hat20 hready20 hstep20 hat21 hready21 hstep21
      hat22 hready22 hstep22 hat23 hready23 hstep23
      hat24 hready24 hstep24 hat25 hready25 hstep25
      hat26 haddrSload hready26 hstep26 hat27 hready27 hstep27
      hat28 hready28 hstep28 hat29 hready29 hstep29
      hat30 haddrSstore hready30 hstep30 hready31 hstep31
      hready32 hstep32 hready33 hstep33 hready34 hstep34
      hready35 hstep35
  exact counterCompiledPreparedInitialize_storage_model_of_run36_returned_sload_ok
    hprepared hrun hhalt hcallStackPrepared hstorageRun hstoragePrefix hobs

theorem counterPreparedInitializeSegmentModel_of_stepFE_path
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    CounterPreparedInitializeSegmentModel s0 s36 := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedInitialize_entry_facts hprepared
  obtain ⟨_hrun, hhalt, hstorageRun, hstoragePrefix, _hcallStackReturn,
      _hcallStackBody, hcallStackPrepared, hobs⟩ :=
    counterRunBytecode_initialize_dispatcher_body_and_return_ok
      hstack0 hat0 path.hready0 path.hstep0 hcalldata0 path.hready1 path.hstep1
      path.hready2 path.hstep2 path.hready3 path.hstep3 path.hready4 path.hstep4
      path.hready5 path.hstep5 path.hready6 path.hstep6 path.hready7 path.hstep7
      path.hready8 path.hstep8 path.hready9 path.hstep9 path.hat10
      path.hready10 path.hstep10 path.hat11 path.hready11 path.hstep11
      path.hat12 path.hready12 path.hstep12 path.hready13 path.hstep13
      path.hready14 path.hstep14 path.hat15 path.hready15 path.hstep15
      path.hat16 path.hready16 path.hstep16 path.hat17 path.hready17
      path.hstep17 path.hat18 path.hready18 path.hstep18 path.hat19
      path.hready19 path.hstep19 path.hat20 path.hready20 path.hstep20
      path.hat21 path.hready21 path.hstep21 path.hat22 path.hready22
      path.hstep22 path.hat23 path.hready23 path.hstep23 path.hat24
      path.hready24 path.hstep24 path.hat25 path.hready25 path.hstep25
      path.hat26 path.haddrSload path.hready26 path.hstep26 path.hat27
      path.hready27 path.hstep27 path.hat28 path.hready28 path.hstep28
      path.hat29 path.hready29 path.hstep29 path.hat30 path.haddrSstore
      path.hready30 path.hstep30 path.hready31 path.hstep31 path.hready32
      path.hstep32 path.hready33 path.hstep33 path.hready34 path.hstep34
      path.hready35 path.hstep35
  refine
    { segment :=
        ProofForge.Backend.Evm.PowdrExec.executionSegment_of_stepFEPath
          (counterPreparedInitializeStepFEPath_to_path path) ?_ }
  refine ⟨hhalt, hcallStackPrepared, ?_, hobs⟩
  rw [hstorageRun, hstoragePrefix]

def counterPreparedInitializeReductionChainModel_of_segmentModel
    {s0 s36 : EvmState}
    (path : CounterPreparedInitializeStepFEPath s0 s36)
    (model : CounterPreparedInitializeSegmentModel s0 s36) :
    CounterPreparedInitializeReductionChainModel s0 s36 where
  chain := counterPreparedInitializeStepFEPath_to_reductionChain path
  postcondition := model.segment.postcondition

def counterPreparedInitializeSegmentModel_of_reductionChainModel
    {s0 s36 : EvmState}
    (model : CounterPreparedInitializeReductionChainModel s0 s36) :
    CounterPreparedInitializeSegmentModel s0 s36 where
  segment :=
    ProofForge.Backend.Evm.PowdrExec.executionSegment_of_reductionChain
      model.chain model.postcondition

def counterPreparedInitializeReductionChainModel_of_stepFE_path
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    CounterPreparedInitializeReductionChainModel s0 s36 := by
  obtain ⟨hat0, hstack0, hcalldata0, _haddr0, _hcallStack0⟩ :=
    counterCompiledPreparedInitialize_entry_facts hprepared
  obtain ⟨_hrun, hhalt, hstorageRun, hstoragePrefix, _hcallStackReturn,
      _hcallStackBody, hcallStackPrepared, hobs⟩ :=
    counterRunBytecode_initialize_dispatcher_body_and_return_ok
      hstack0 hat0 path.hready0 path.hstep0 hcalldata0 path.hready1 path.hstep1
      path.hready2 path.hstep2 path.hready3 path.hstep3 path.hready4 path.hstep4
      path.hready5 path.hstep5 path.hready6 path.hstep6 path.hready7 path.hstep7
      path.hready8 path.hstep8 path.hready9 path.hstep9 path.hat10
      path.hready10 path.hstep10 path.hat11 path.hready11 path.hstep11
      path.hat12 path.hready12 path.hstep12 path.hready13 path.hstep13
      path.hready14 path.hstep14 path.hat15 path.hready15 path.hstep15
      path.hat16 path.hready16 path.hstep16 path.hat17 path.hready17
      path.hstep17 path.hat18 path.hready18 path.hstep18 path.hat19
      path.hready19 path.hstep19 path.hat20 path.hready20 path.hstep20
      path.hat21 path.hready21 path.hstep21 path.hat22 path.hready22
      path.hstep22 path.hat23 path.hready23 path.hstep23 path.hat24
      path.hready24 path.hstep24 path.hat25 path.hready25 path.hstep25
      path.hat26 path.haddrSload path.hready26 path.hstep26 path.hat27
      path.hready27 path.hstep27 path.hat28 path.hready28 path.hstep28
      path.hat29 path.hready29 path.hstep29 path.hat30 path.haddrSstore
      path.hready30 path.hstep30 path.hready31 path.hstep31 path.hready32
      path.hstep32 path.hready33 path.hstep33 path.hready34 path.hstep34
      path.hready35 path.hstep35
  refine
    { chain := counterPreparedInitializeStepFEPath_to_reductionChain path
      postcondition := ?_ }
  refine ⟨hhalt, hcallStackPrepared, ?_, hobs⟩
  rw [hstorageRun, hstoragePrefix]

theorem counterCompiledPreparedInitialize_storage_model_of_segment_model_ok
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (model : CounterPreparedInitializeSegmentModel s0 s36) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig s0 .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s0) := by
  rcases model.segment.postcondition with
    ⟨hreturned, hcallStack, hstorageModel, hobservable⟩
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 36 =
        .ok (s36, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) :=
    ProofForge.Backend.Evm.PowdrExec.runSteps_of_executionSegment model.segment
  have hstep :=
    counterPowdrPreparedTraceStep_initialize_of_run36_returned_prepared_ok
      hprepared hrun hreturned hcallStack hobservable
  exact ⟨s36, hstep, hstorageModel⟩

theorem counterCompiledPreparedInitialize_storage_model_of_reduction_chain_model_ok
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (model : CounterPreparedInitializeReductionChainModel s0 s36) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig s0 .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s0) := by
  rcases model.postcondition with
    ⟨hreturned, hcallStack, hstorageModel, hobservable⟩
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode s0 36 =
        .ok (s36, (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) :=
    ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain model.chain
  have hstep :=
    counterPowdrPreparedTraceStep_initialize_of_run36_returned_prepared_ok
      hprepared hrun hreturned hcallStack hobservable
  exact ⟨s36, hstep, hstorageModel⟩

theorem counterCompiledPreparedInitialize_storage_model_of_stepFE_path_ok
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig s0 .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s0) := by
  exact counterCompiledPreparedInitialize_storage_model_of_reduction_chain_model_ok
    hprepared
    (counterPreparedInitializeReductionChainModel_of_stepFE_path hprepared path)

theorem counterCompiledPreparedInitialize_storage_model_of_stepFE_path_chain_ok
    {s0 s36 : EvmState}
    (hprepared : CounterPreparedCall counterCompiledPowdrConfig .initialize s0)
    (path : CounterPreparedInitializeStepFEPath s0 s36) :
    ∃ nextEvm,
      counterPowdrPreparedTraceStep counterCompiledPowdrConfig s0 .initialize =
        .ok (nextEvm, .none) ∧
      counterStorageValue counterContractAddress counterCountSlot nextEvm =
        counterInitializeStorageWord
          (counterStorageValue counterContractAddress counterCountSlot s0) := by
  exact counterCompiledPreparedInitialize_storage_model_of_stepFE_path_ok
    hprepared path

abbrev CounterPreparedInitializeSegmentProvider :=
  ProofForge.Backend.Evm.PowdrExec.SegmentProvider
    counterPreparedInitializeSegmentPre 36
    counterPreparedInitializeSegmentPost

abbrev CounterPreparedInitializeReductionChainProvider :=
  ProofForge.Backend.Evm.PowdrExec.ReductionChainProvider
    counterPreparedInitializeSegmentPre 36
    counterPreparedInitializeSegmentPost

def counterPreparedInitializeSegmentProviderOfReductionChainProvider
    (provider : CounterPreparedInitializeReductionChainProvider) :
    CounterPreparedInitializeSegmentProvider :=
  ProofForge.Backend.Evm.PowdrExec.segmentProvider_of_reductionChainProvider
    provider

def counterPreparedInitializeSegmentModel_of_executionSegment
    {s0 s36 : EvmState}
    (segment :
      ProofForge.Backend.Evm.PowdrExec.ExecutionSegment 36
        counterPreparedInitializeSegmentPost s0 s36) :
    CounterPreparedInitializeSegmentModel s0 s36 where
  segment := segment

theorem counterCompiledPreparedInitialize_storage_model_of_segment_provider_ok
    (provider : CounterPreparedInitializeSegmentProvider) :
    ∀ {preparedState},
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
            .initialize =
          .ok (nextEvm, .none) ∧
        counterStorageValue counterContractAddress counterCountSlot nextEvm =
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot
              preparedState) := by
  intro preparedState hprepared
  obtain ⟨finalState, segment⟩ :=
    provider.segment hprepared
  exact counterCompiledPreparedInitialize_storage_model_of_segment_model_ok
    hprepared
    (counterPreparedInitializeSegmentModel_of_executionSegment segment)

theorem counterCompiledPreparedInitialize_storage_model_of_reduction_chain_provider_ok
    (provider : CounterPreparedInitializeReductionChainProvider) :
    ∀ {preparedState},
      CounterPreparedCall counterCompiledPowdrConfig .initialize preparedState →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
            .initialize =
          .ok (nextEvm, .none) ∧
        counterStorageValue counterContractAddress counterCountSlot nextEvm =
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot
              preparedState) := by
  intro preparedState hprepared
  obtain ⟨finalState, chain, hpost⟩ :=
    provider.chain hprepared
  exact counterCompiledPreparedInitialize_storage_model_of_reduction_chain_model_ok
    hprepared
    ({ chain := chain
       postcondition := hpost } :
      CounterPreparedInitializeReductionChainModel preparedState finalState)

def counterPreparedIncrementSegmentPre (count : Nat) (state : EvmState) : Prop :=
  CounterPreparedCall counterCompiledPowdrConfig .increment state ∧
    count + 1 < counterU64Modulus ∧
    CounterStorageWordRel
      (counterStorageValue counterContractAddress counterCountSlot state) count

def counterPreparedIncrementSegmentPost
    (count : Nat) (state finalState : EvmState) : Prop :=
  finalState.halt = .Returned ∧
    finalState.callStack = state.callStack ∧
    CounterStorageWordRel
      (counterStorageValue counterContractAddress counterCountSlot finalState)
      (count + 1) ∧
    counterObservableFromResult .increment finalState.toResult = .ok .none

def counterPreparedGetSegmentPre (count : Nat) (state : EvmState) : Prop :=
  CounterPreparedCall counterCompiledPowdrConfig .get state ∧
    count < counterU64Modulus ∧
    CounterStorageWordRel
      (counterStorageValue counterContractAddress counterCountSlot state) count

def counterPreparedGetSegmentPost
    (count : Nat) (state finalState : EvmState) : Prop :=
  finalState.halt = .Returned ∧
    finalState.callStack = state.callStack ∧
    CounterStorageWordRel
      (counterStorageValue counterContractAddress counterCountSlot finalState)
      count ∧
    counterObservableFromResult .get finalState.toResult = .ok (.u64 count)

abbrev CounterPreparedIncrementReductionChainProvider (fuel : Nat) :=
  ∀ count,
    ProofForge.Backend.Evm.PowdrExec.ReductionChainProvider
      (counterPreparedIncrementSegmentPre count) fuel
      (counterPreparedIncrementSegmentPost count)

abbrev CounterPreparedGetReductionChainProvider (fuel : Nat) :=
  ∀ count,
    ProofForge.Backend.Evm.PowdrExec.ReductionChainProvider
      (counterPreparedGetSegmentPre count) fuel
      (counterPreparedGetSegmentPost count)

theorem counterCompiledPreparedIncrement_storage_model_of_reduction_chain_provider_ok
    {fuel : Nat}
    (provider : CounterPreparedIncrementReductionChainProvider fuel)
    (hle : fuel ≤ counterCompiledRuntimeFuel) :
    ∀ {preparedState count},
      CounterPreparedCall counterCompiledPowdrConfig .increment preparedState →
      count + 1 < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState)
        count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
            .increment =
          .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm)
          (count + 1) := by
  intro preparedState count hprepared hbound hstorage
  obtain ⟨finalState, chain, hpost⟩ :=
    (provider count).chain ⟨hprepared, hbound, hstorage⟩
  rcases hpost with ⟨hhalt, hcallStack, hstorageNext, hobs⟩
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState fuel =
        .ok (finalState,
          (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) :=
    ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain chain
  have hstep :=
    counterPowdrPreparedTraceStep_of_run_returned_prepared_ok
      hprepared hrun hhalt hcallStack hobs hle
  exact ⟨finalState, hstep, hstorageNext⟩

theorem counterCompiledPreparedGet_storage_model_of_reduction_chain_provider_ok
    {fuel : Nat}
    (provider : CounterPreparedGetReductionChainProvider fuel)
    (hle : fuel ≤ counterCompiledRuntimeFuel) :
    ∀ {preparedState count},
      CounterPreparedCall counterCompiledPowdrConfig .get preparedState →
      count < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState)
        count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState .get =
          .ok (nextEvm, .u64 count) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm)
          count := by
  intro preparedState count hprepared hbound hstorage
  obtain ⟨finalState, chain, hpost⟩ :=
    (provider count).chain ⟨hprepared, hbound, hstorage⟩
  rcases hpost with ⟨hhalt, hcallStack, hstorageNext, hobs⟩
  have hrun :
      ProofForge.Backend.Evm.PowdrAdapter.runBytecode preparedState fuel =
        .ok (finalState,
          (#[] : Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep)) :=
    ProofForge.Backend.Evm.PowdrExec.runSteps_of_reductionChain chain
  have hstep :=
    counterPowdrPreparedTraceStep_of_run_returned_prepared_ok
      hprepared hrun hhalt hcallStack hobs hle
  exact ⟨finalState, hstep, hstorageNext⟩

theorem counterPreparedCall_isDone
    {cfg : PowdrCounterConfig} {call : CounterCall} {state : EvmState}
    (hprepared : CounterPreparedCall cfg call state) :
    state.isDone = false := by
  rcases hprepared with ⟨sourceState, rfl⟩
  exact prepareCounterCall_isDone cfg.runtimeCode call sourceState

theorem counterPreparedCall_not_isDone
    {cfg : PowdrCounterConfig} {call : CounterCall} {state : EvmState}
    (hprepared : CounterPreparedCall cfg call state) :
    ¬ state.isDone := by
  rw [counterPreparedCall_isDone hprepared]
  simp

theorem counterPreparedCall_stepF_ok
    {cfg : PowdrCounterConfig} {call : CounterCall} {state : EvmState}
    (hprepared : CounterPreparedCall cfg call state) :
    ProofForge.Backend.Evm.PowdrAdapter.stepF state =
      .ok (ProofForge.Backend.Evm.PowdrAdapter.rawStepF state) := by
  unfold ProofForge.Backend.Evm.PowdrAdapter.stepF
  rw [counterPreparedCall_isDone hprepared]
  rfl

theorem counterPreparedCall_stepF_step
    {cfg : PowdrCounterConfig} {call : CounterCall} {state : EvmState}
    (hprepared : CounterPreparedCall cfg call state) :
    ProofForge.Backend.Evm.PowdrAdapter.Step state
      (ProofForge.Backend.Evm.PowdrAdapter.rawStepF state) :=
  ProofForge.Backend.Evm.PowdrAdapter.raw_stepF_sound state
    (counterPreparedCall_not_isDone hprepared)

theorem counterPowdrTraceStep_steps {cfg : PowdrCounterConfig}
    {state finalState : EvmState} {call : CounterCall}
    {obs : ObservableReturn}
    (h : counterPowdrTraceStep cfg state call = .ok (finalState, obs)) :
    EvmSemantics.EVM.Steps
      (prepareCounterCall cfg.runtimeCode call state) finalState := by
  unfold counterPowdrTraceStep at h
  unfold counterPowdrPreparedTraceStep at h
  cases hrun : ProofForge.Backend.Evm.PowdrAdapter.runBytecode
      (prepareCounterCall cfg.runtimeCode call state) cfg.fuel with
  | error message =>
      rw [hrun] at h
      change (Except.bind (Except.error message)
        (fun result : EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep =>
          Except.bind (counterObservableFromResult call result.fst.toResult)
            (fun observable : ObservableReturn =>
              Except.ok (result.fst, observable)))) = Except.ok (finalState, obs) at h
      simp [Except.bind] at h
  | ok result =>
      rcases result with ⟨runFinalState, observations⟩
      have hsteps :=
        ProofForge.Backend.Evm.PowdrAdapter.runBytecode_steps hrun
      rw [hrun] at h
      change (Except.bind (Except.ok
        ((runFinalState, observations) :
          EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep))
        (fun result : EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep =>
              Except.bind (counterObservableFromResult call result.fst.toResult)
                (fun observable : ObservableReturn =>
                  Except.ok (result.fst, observable)))) = Except.ok (finalState, obs) at h
      change (Except.bind (counterObservableFromResult call runFinalState.toResult)
        (fun observable : ObservableReturn =>
          Except.ok (runFinalState, observable))) = Except.ok (finalState, obs) at h
      cases hobs : counterObservableFromResult call runFinalState.toResult with
      | error message =>
          rw [hobs] at h
          change (Except.error message : Except String (EvmState × ObservableReturn)) =
            Except.ok (finalState, obs) at h
          cases h
      | ok targetObservable =>
          rw [hobs] at h
          change Except.ok (runFinalState, targetObservable) =
            Except.ok (finalState, obs) at h
          cases h
          exact hsteps

theorem counterPowdrTraceStep_observable {cfg : PowdrCounterConfig}
    {state finalState : EvmState} {call : CounterCall}
    {obs : ObservableReturn}
    (h : counterPowdrTraceStep cfg state call = .ok (finalState, obs)) :
    counterObservableFromResult call finalState.toResult = .ok obs := by
  unfold counterPowdrTraceStep at h
  unfold counterPowdrPreparedTraceStep at h
  cases hrun : ProofForge.Backend.Evm.PowdrAdapter.runBytecode
      (prepareCounterCall cfg.runtimeCode call state) cfg.fuel with
  | error message =>
      rw [hrun] at h
      change (Except.bind (Except.error message)
        (fun result : EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep =>
          Except.bind (counterObservableFromResult call result.fst.toResult)
            (fun observable : ObservableReturn =>
              Except.ok (result.fst, observable)))) = Except.ok (finalState, obs) at h
      simp [Except.bind] at h
  | ok result =>
      rcases result with ⟨runFinalState, observations⟩
      rw [hrun] at h
      change (Except.bind (Except.ok
        ((runFinalState, observations) :
          EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep))
        (fun result : EvmState × Array ProofForge.Backend.Evm.PowdrAdapter.ObservableStep =>
              Except.bind (counterObservableFromResult call result.fst.toResult)
                (fun observable : ObservableReturn =>
                  Except.ok (result.fst, observable)))) = Except.ok (finalState, obs) at h
      change (Except.bind (counterObservableFromResult call runFinalState.toResult)
        (fun observable : ObservableReturn =>
          Except.ok (runFinalState, observable))) = Except.ok (finalState, obs) at h
      cases hobs : counterObservableFromResult call runFinalState.toResult with
      | error message =>
          rw [hobs] at h
          change (Except.error message : Except String (EvmState × ObservableReturn)) =
            Except.ok (finalState, obs) at h
          cases h
      | ok targetObservable =>
          rw [hobs] at h
          change Except.ok (runFinalState, targetObservable) =
            Except.ok (finalState, obs) at h
          cases h
          exact hobs

def counterPowdrRunTrace (cfg : PowdrCounterConfig) :
    List CounterCall → EvmState → Except String (EvmState × Array ObservableReturn) :=
  ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg)

def counterPowdrStepReturns (cfg : PowdrCounterConfig) (state : EvmState)
    (call : CounterCall) (expected : ObservableReturn) : Bool :=
  match counterPowdrTraceStep cfg state call with
  | .ok (_, observable) => observable == expected
  | .error _ => false

def counterPowdrTraceReturns (cfg : PowdrCounterConfig) (calls : List CounterCall)
    (state : EvmState) (expected : Array ObservableReturn) : Bool :=
  match counterPowdrRunTrace cfg calls state with
  | .ok (_, observables) => observables == expected
  | .error _ => false

theorem counterCompiledPowdr_initialize_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig counterBaseEvmState
      .initialize .none = true := by
  native_decide

theorem counterCompiledPowdr_get_zero_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig counterBaseEvmState
      .get (.u64 0) = true := by
  native_decide

theorem counterCompiledPowdr_get_packed_seven_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig
      (setCounterStorage counterContractAddress counterCountSlot counterBaseEvmState 7)
      .get (.u64 7) = true := by
  native_decide

theorem counterCompiledPowdr_get_padded_seven_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig
      (setCounterStorageWord counterContractAddress counterCountSlot counterBaseEvmState
        (counterPaddedCountValue 7 123))
      .get (.u64 7) = true := by
  native_decide

theorem counterCompiledPowdr_increment_packed_seven_executable_smoke :
    counterPowdrTraceReturns counterCompiledPowdrConfig
      [.increment, .get]
      (setCounterStorage counterContractAddress counterCountSlot counterBaseEvmState 7)
      #[.none, .u64 8] = true := by
  native_decide

theorem counterCompiledPowdr_initialize_padded_get_executable_smoke :
    counterPowdrTraceReturns counterCompiledPowdrConfig
      [.initialize, .get]
      (setCounterStorageWord counterContractAddress counterCountSlot counterBaseEvmState
        (counterPaddedCountValue 7 123))
      #[.none, .u64 0] = true := by
  native_decide

theorem counterCompiledPowdr_initialize_increment_get_executable_smoke :
    counterPowdrTraceReturns counterCompiledPowdrConfig
      [.initialize, .increment, .get] counterBaseEvmState
      #[.none, .none, .u64 1] = true := by
  native_decide

theorem counterPowdrRunTrace_eq_traceStep (cfg : PowdrCounterConfig)
    (calls : List CounterCall) (state : EvmState) :
    counterPowdrRunTrace cfg calls state =
      ProofForge.IR.StepSemantics.runTraceListGen
        (counterPowdrTraceStep cfg) calls state := rfl

def counterCallFromTraceCall? (call : TraceCall) : Option CounterCall :=
  if call.args.size == 0 && call.evmArgs.size == 0 then
    if isCounterInitializeEntrypoint call.entrypoint then
      some .initialize
    else if isCounterIncrementEntrypoint call.entrypoint then
      some .increment
    else if isCounterGetEntrypoint call.entrypoint then
      some .get
    else
      none
  else
    none

def counterCallsFromTraceCalls? : List TraceCall → Option (List CounterCall)
  | [] => some []
  | call :: rest => do
      let counterCall ← counterCallFromTraceCall? call
      let counterRest ← counterCallsFromTraceCalls? rest
      some (counterCall :: counterRest)

def counterExpectedStepMatches (call : CounterCall)
    (observable : ObservableReturn) (expected : ObservableStep) : Bool :=
  expected.entrypointName == call.entrypoint.name &&
    expected.selector == counterCallSelector call &&
    expected.returnValue == observable &&
    expected.logs.isEmpty

def counterExpectedTraceMatches :
    List CounterCall → List ObservableReturn → List ObservableStep → Bool
  | [], [], [] => true
  | call :: calls, observable :: observables, expected :: expectedRest =>
      counterExpectedStepMatches call observable expected &&
        counterExpectedTraceMatches calls observables expectedRest
  | _, _, _ => false

def counterPowdrExecutableTraceOk (cfg : PowdrCounterConfig) (state : EvmState)
    (obligation : TraceObligation) : Bool :=
  FormalFragment.counter.acceptsModule obligation.module &&
    match counterCallsFromTraceCalls? obligation.calls.toList with
    | none => false
    | some calls =>
        match counterPowdrRunTrace cfg calls state with
        | .ok (_, observables) =>
            counterExpectedTraceMatches calls observables.toList obligation.expected.toList
        | .error _ => false

def counterPowdrTargetSemantics (cfg : PowdrCounterConfig) : TargetSemantics := {
  id := "evm-powdr-counter"
  supportedFragments := #[.counter]
  fragmentAccepts := isCounterModule
  lowerableAccepts := isCounterShapeLowerable
  MachineState := EvmState
  Call := CounterCall
  Obs := ObservableReturn
  traceStep := counterPowdrTraceStep cfg
  runTrace := counterPowdrRunTrace cfg
  runTrace_eq_traceStep := counterPowdrRunTrace_eq_traceStep cfg
  executableTraceOk := fun _ => false
  initialRelHolds := by intros; trivial
}

def counterCompiledPowdrExecutableTraceOk (obligation : TraceObligation) : Bool :=
  counterPowdrExecutableTraceOk counterCompiledPowdrConfig counterBaseEvmState obligation

def counterCompiledPowdrTargetSemantics : TargetSemantics :=
  { counterPowdrTargetSemantics counterCompiledPowdrConfig with
    executableTraceOk := counterCompiledPowdrExecutableTraceOk }

def counterCompiledPowdrTraceObligation : TraceObligation := {
  name := "Counter.powdr.initialize-get-increment-get"
  module := ProofForge.IR.Examples.Counter.module
  calls := #[
    { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
    { entrypoint := ProofForge.IR.Examples.Counter.get },
    { entrypoint := ProofForge.IR.Examples.Counter.increment },
    { entrypoint := ProofForge.IR.Examples.Counter.get }
  ]
  expected := #[
    { entrypointName := "initialize", selector := "8129fc1c", returnValue := .none },
    { entrypointName := "get", selector := "6d4ce63c", returnValue := .u64 0 },
    { entrypointName := "increment", selector := "d09de08a", returnValue := .none },
    { entrypointName := "get", selector := "6d4ce63c", returnValue := .u64 1 }
  ]
}

theorem counterCompiledPowdr_executable_trace_ok :
    counterCompiledPowdrTargetSemantics.executableTraceOk
      counterCompiledPowdrTraceObligation = true := by
  native_decide

/-- Delivery-boundary pin: the same Counter `TraceObligation` passes both the
IR reference trace (`irTraceOk`) and the compiled powdr bytecode trace
(`counterCompiledPowdrExecutableTraceOk`). This is the opt-in EVM bytecode
lane's end-to-end delivery check against the Portable-IR reference. -/
theorem counterCompiledPowdr_ir_and_target_trace_match :
    ProofForge.Backend.Evm.Refinement.irTraceOk
      counterCompiledPowdrTraceObligation = true ∧
    counterCompiledPowdrExecutableTraceOk counterCompiledPowdrTraceObligation = true := by
  native_decide

structure CounterPowdrEntrypointObligations (cfg : PowdrCounterConfig) where
  initialize_simulates :
    ∀ {irState evmState nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .initialize = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm
  increment_simulates :
    ∀ {irState evmState nextIr observable},
      CounterStorageRel irState evmState →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .increment = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm
  get_simulates :
    ∀ {irState evmState nextIr observable},
      CounterStorageRel irState evmState →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .get = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm

def CounterStepSafe (call : CounterCall) (irState : IRState) : Prop :=
  match call with
  | .initialize => True
  | .get =>
      ∀ count, irCounterCount? irState = some count → count < counterU64Modulus
  | .increment =>
      ∀ count, irCounterCount? irState = some count → count + 1 < counterU64Modulus

structure CounterPowdrSafeEntrypointObligations (cfg : PowdrCounterConfig) where
  initialize_simulates :
    ∀ {irState evmState nextIr observable},
      counterIRStep irState .initialize = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .initialize = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm
  increment_simulates :
    ∀ {irState evmState nextIr observable},
      CounterStorageRel irState evmState →
      CounterStepSafe .increment irState →
      counterIRStep irState .increment = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .increment = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm
  get_simulates :
    ∀ {irState evmState nextIr observable},
      CounterStorageRel irState evmState →
      CounterStepSafe .get irState →
      counterIRStep irState .get = .ok (nextIr, observable) →
        ∃ nextEvm,
          counterPowdrTraceStep cfg evmState .get = .ok (nextEvm, observable) ∧
          CounterStorageRel nextIr nextEvm

structure CounterPowdrEvmPostconditions (cfg : PowdrCounterConfig) where
  initialize_writes_zero :
    ∀ {evmState},
      ∃ nextEvm,
        counterPowdrTraceStep cfg evmState .initialize = .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) 0
  increment_writes_succ :
    ∀ {evmState count},
      count + 1 < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot evmState) count →
      ∃ nextEvm,
        counterPowdrTraceStep cfg evmState .increment = .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) (count + 1)
  get_returns_count :
    ∀ {evmState count},
      count < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot evmState) count →
      ∃ nextEvm,
        counterPowdrTraceStep cfg evmState .get = .ok (nextEvm, .u64 count) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) count

structure CounterPowdrPreparedEvmPostconditions (cfg : PowdrCounterConfig) where
  initialize_writes_zero :
    ∀ {preparedState},
      CounterPreparedCall cfg .initialize preparedState →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .initialize =
          .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) 0
  increment_writes_succ :
    ∀ {preparedState count},
      CounterPreparedCall cfg .increment preparedState →
      count + 1 < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState) count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .increment =
          .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) (count + 1)
  get_returns_count :
    ∀ {preparedState count},
      CounterPreparedCall cfg .get preparedState →
      count < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState) count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .get = .ok (nextEvm, .u64 count) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) count

structure CounterPowdrPreparedStorageModels (cfg : PowdrCounterConfig) where
  initialize_writes_storage_model :
    ∀ {preparedState},
      CounterPreparedCall cfg .initialize preparedState →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .initialize =
          .ok (nextEvm, .none) ∧
        counterStorageValue counterContractAddress counterCountSlot nextEvm =
          counterInitializeStorageWord
            (counterStorageValue counterContractAddress counterCountSlot preparedState)
  increment_writes_succ :
    ∀ {preparedState count},
      CounterPreparedCall cfg .increment preparedState →
      count + 1 < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState) count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .increment =
          .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) (count + 1)
  get_returns_count :
    ∀ {preparedState count},
      CounterPreparedCall cfg .get preparedState →
      count < counterU64Modulus →
      CounterStorageWordRel
        (counterStorageValue counterContractAddress counterCountSlot preparedState) count →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .get = .ok (nextEvm, .u64 count) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) count

theorem counterPreparedInitializePostconditionOfStorageModel
    (cfg : PowdrCounterConfig)
    (hmodel :
      ∀ {preparedState},
        CounterPreparedCall cfg .initialize preparedState →
        ∃ nextEvm,
          counterPowdrPreparedTraceStep cfg preparedState .initialize =
            .ok (nextEvm, .none) ∧
          counterStorageValue counterContractAddress counterCountSlot nextEvm =
            counterInitializeStorageWord
              (counterStorageValue counterContractAddress counterCountSlot preparedState)) :
    ∀ {preparedState},
      CounterPreparedCall cfg .initialize preparedState →
      ∃ nextEvm,
        counterPowdrPreparedTraceStep cfg preparedState .initialize =
          .ok (nextEvm, .none) ∧
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot nextEvm) 0 := by
  intro preparedState hprepared
  obtain ⟨nextEvm, hstep, hstorage⟩ := hmodel hprepared
  refine ⟨nextEvm, hstep, ?_⟩
  rw [hstorage]
  exact counterInitializeStorageWord_rel_zero
    (counterStorageValue counterContractAddress counterCountSlot preparedState)

def counterPowdrPreparedEvmPostconditionsOfStorageModels
    (cfg : PowdrCounterConfig) (models : CounterPowdrPreparedStorageModels cfg) :
    CounterPowdrPreparedEvmPostconditions cfg where
  initialize_writes_zero :=
    counterPreparedInitializePostconditionOfStorageModel cfg
      models.initialize_writes_storage_model
  increment_writes_succ := models.increment_writes_succ
  get_returns_count := models.get_returns_count

def counterPowdrEvmPostconditionsOfPrepared
    (cfg : PowdrCounterConfig) (post : CounterPowdrPreparedEvmPostconditions cfg) :
    CounterPowdrEvmPostconditions cfg where
  initialize_writes_zero := by
    intro evmState
    exact post.initialize_writes_zero ⟨evmState, rfl⟩
  increment_writes_succ := by
    intro evmState count hbound hstorage
    have hstoragePrepared :
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            (prepareCounterCall cfg.runtimeCode .increment evmState)) count := by
      rw [counterStorageValue_prepareCounterCall]
      exact hstorage
    exact post.increment_writes_succ ⟨evmState, rfl⟩ hbound hstoragePrepared
  get_returns_count := by
    intro evmState count hbound hstorage
    have hstoragePrepared :
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            (prepareCounterCall cfg.runtimeCode .get evmState)) count := by
      rw [counterStorageValue_prepareCounterCall]
      exact hstorage
    exact post.get_returns_count ⟨evmState, rfl⟩ hbound hstoragePrepared

def counterPowdrSafeEntrypointObligationsOfPostconditions
    (cfg : PowdrCounterConfig) (post : CounterPowdrEvmPostconditions cfg) :
    CounterPowdrSafeEntrypointObligations cfg where
  initialize_simulates := by
    intro irState evmState nextIr observable hirStep
    obtain ⟨modelNextIr, nextCount, modelObservable, hirModel, htargetStep,
      hcounterNext⟩ :=
        ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
          irState 0
    change ProofForge.Backend.Refinement.CounterUniversal.irStep irState .initialize =
      .ok (nextIr, observable) at hirStep
    rw [hirModel] at hirStep
    cases hirStep
    cases htargetStep
    obtain ⟨nextEvm, hpowdrStep, hstorageNext⟩ :=
      post.initialize_writes_zero (evmState := evmState)
    refine ⟨nextEvm, hpowdrStep, ?_⟩
    refine ⟨0, counterStateRel_irCounterCount? hcounterNext, ?_, hstorageNext⟩
    native_decide
  increment_simulates := by
    intro irState evmState nextIr observable hrel hsafe hirStep
    rcases hrel with ⟨count, hcount, _hbound, hstorage⟩
    have hcounter := counterStateRel_of_irCounterCount? hcount
    have hnextBound : count + 1 < counterU64Modulus := hsafe count hcount
    obtain ⟨modelNextIr, nextCount, modelObservable, hirModel, htargetStep,
      hcounterNext⟩ :=
        ProofForge.Backend.Refinement.CounterUniversal.counter_increment_simulates
          hcounter
    change ProofForge.Backend.Refinement.CounterUniversal.irStep irState .increment =
      .ok (nextIr, observable) at hirStep
    rw [hirModel] at hirStep
    cases hirStep
    cases htargetStep
    obtain ⟨nextEvm, hpowdrStep, hstorageNext⟩ :=
      post.increment_writes_succ hnextBound hstorage
    refine ⟨nextEvm, hpowdrStep, ?_⟩
    exact ⟨count + 1, counterStateRel_irCounterCount? hcounterNext,
      hnextBound, hstorageNext⟩
  get_simulates := by
    intro irState evmState nextIr observable hrel hsafe hirStep
    rcases hrel with ⟨count, hcount, hbound, hstorage⟩
    have hcounter := counterStateRel_of_irCounterCount? hcount
    obtain ⟨modelNextIr, nextCount, modelObservable, hirModel, htargetStep,
      hcounterNext⟩ :=
        ProofForge.Backend.Refinement.CounterUniversal.counter_get_simulates
          hcounter
    change ProofForge.Backend.Refinement.CounterUniversal.irStep irState .get =
      .ok (nextIr, observable) at hirStep
    rw [hirModel] at hirStep
    cases hirStep
    cases htargetStep
    obtain ⟨nextEvm, hpowdrStep, hstorageNext⟩ :=
      post.get_returns_count hbound hstorage
    refine ⟨nextEvm, hpowdrStep, ?_⟩
    exact ⟨count, counterStateRel_irCounterCount? hcounterNext, hbound, hstorageNext⟩

def counterPowdrSafeEntrypointObligationsOfPreparedStorageModels
    (cfg : PowdrCounterConfig) (models : CounterPowdrPreparedStorageModels cfg) :
    CounterPowdrSafeEntrypointObligations cfg :=
  counterPowdrSafeEntrypointObligationsOfPostconditions cfg
    (counterPowdrEvmPostconditionsOfPrepared cfg
      (counterPowdrPreparedEvmPostconditionsOfStorageModels cfg models))

theorem counterPowdr_step_simulates_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrEntrypointObligations cfg)
    (call : CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ nextIr nextEvm observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterPowdrTraceStep cfg evmState call = .ok (nextEvm, observable) ∧
      CounterStorageRel nextIr nextEvm := by
  obtain ⟨count, hcounter⟩ := counterStorageRel_left_counterStateRel hrel
  cases call
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
        irState count
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.initialize_simulates hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_increment_simulates
        hcounter
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.increment_simulates hrel hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_get_simulates
        hcounter
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.get_simulates hrel hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩

theorem counterPowdr_safe_step_simulates_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrSafeEntrypointObligations cfg)
    (call : CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState)
    (hsafe : CounterStepSafe call irState) :
    ∃ nextIr nextEvm observable,
      counterIRStep irState call = .ok (nextIr, observable) ∧
      counterPowdrTraceStep cfg evmState call = .ok (nextEvm, observable) ∧
      CounterStorageRel nextIr nextEvm := by
  obtain ⟨count, hcounter⟩ := counterStorageRel_left_counterStateRel hrel
  cases call
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
        irState count
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.initialize_simulates hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_increment_simulates
        hcounter
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.increment_simulates hrel hsafe hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩
  · obtain ⟨nextIr, _nextCount, observable, hirStep, _htargetStep, _hcounterNext⟩ :=
      ProofForge.Backend.Refinement.CounterUniversal.counter_get_simulates
        hcounter
    have hsafeGet : CounterStepSafe .get irState := by
      exact hsafe
    obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
      obligations.get_simulates hrel hsafeGet hirStep
    exact ⟨nextIr, nextEvm, observable, hirStep, hpowdrStep, hrelNext⟩

theorem counterPowdr_safe_trace_simulates_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrSafeEntrypointObligations cfg)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState} {count : Nat}
    (hrel : CounterStorageRel irState evmState)
    (hcounter : ProofForge.Backend.Refinement.CounterUniversal.CounterStateRel
      irState count)
    (hsafe : counterTraceSafeFromCount count calls = true) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep cfg) evmState calls observables := by
  induction calls generalizing irState evmState count with
  | nil =>
      refine ⟨irState, evmState, #[], rfl, rfl, hrel,
        ProofForge.IR.StepSemantics.IRTraceMatches.nil,
        ProofForge.IR.StepSemantics.IRTraceMatches.nil⟩
  | cons call rest ih =>
      cases call
      · have hsafeRest : counterTraceSafeFromCount 0 rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
            irState count
        cases htargetStep
        obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
          obligations.initialize_simulates hirStep
        obtain ⟨finalIr, finalEvm, restObservables, hirRest, hpowdrRest,
            hrelFinal, hirTraceRest, hpowdrTraceRest⟩ :=
          ih (irState := nextIr) (evmState := nextEvm) (count := 0)
            hrelNext hcounterNext hsafeRest
        refine ⟨finalIr, finalEvm, #[.none] ++ restObservables, ?_, ?_,
          hrelFinal,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hirStep hirTraceRest,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hpowdrStep hpowdrTraceRest⟩
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            counterIRStep .initialize rest irState nextIr .none
            finalIr restObservables hirStep hirRest
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            (counterPowdrTraceStep cfg) .initialize rest evmState nextEvm .none
            finalEvm restObservables hpowdrStep hpowdrRest
      · have hsafePair :
            (count + 1 < counterU64Modulus) ∧
              counterTraceSafeFromCount (count + 1) rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        have hstepSafe : CounterStepSafe .increment irState := by
          intro count' hcount'
          have hread := counterStateRel_irCounterCount? hcounter
          rw [hread] at hcount'
          cases hcount'
          exact hsafePair.left
        obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          ProofForge.Backend.Refinement.CounterUniversal.counter_increment_simulates
            hcounter
        cases htargetStep
        obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
          obligations.increment_simulates hrel hstepSafe hirStep
        obtain ⟨finalIr, finalEvm, restObservables, hirRest, hpowdrRest,
            hrelFinal, hirTraceRest, hpowdrTraceRest⟩ :=
          ih (irState := nextIr) (evmState := nextEvm) (count := count + 1)
            hrelNext hcounterNext hsafePair.right
        refine ⟨finalIr, finalEvm, #[.none] ++ restObservables, ?_, ?_,
          hrelFinal,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hirStep hirTraceRest,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hpowdrStep hpowdrTraceRest⟩
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            counterIRStep .increment rest irState nextIr .none
            finalIr restObservables hirStep hirRest
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            (counterPowdrTraceStep cfg) .increment rest evmState nextEvm .none
            finalEvm restObservables hpowdrStep hpowdrRest
      · have hsafePair :
            (count < counterU64Modulus) ∧
              counterTraceSafeFromCount count rest = true := by
          simpa [counterTraceSafeFromCount] using hsafe
        have hstepSafe : CounterStepSafe .get irState := by
          intro count' hcount'
          have hread := counterStateRel_irCounterCount? hcounter
          rw [hread] at hcount'
          cases hcount'
          exact hsafePair.left
        obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
          ProofForge.Backend.Refinement.CounterUniversal.counter_get_simulates
            hcounter
        cases htargetStep
        obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
          obligations.get_simulates hrel hstepSafe hirStep
        obtain ⟨finalIr, finalEvm, restObservables, hirRest, hpowdrRest,
            hrelFinal, hirTraceRest, hpowdrTraceRest⟩ :=
          ih (irState := nextIr) (evmState := nextEvm) (count := count)
            hrelNext hcounterNext hsafePair.right
        refine ⟨finalIr, finalEvm, #[.u64 count] ++ restObservables, ?_, ?_,
          hrelFinal,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hirStep hirTraceRest,
          ProofForge.IR.StepSemantics.IRTraceMatches.cons hpowdrStep hpowdrTraceRest⟩
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            counterIRStep .get rest irState nextIr (.u64 count)
            finalIr restObservables hirStep hirRest
        · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
            (counterPowdrTraceStep cfg) .get rest evmState nextEvm (.u64 count)
            finalEvm restObservables hpowdrStep hpowdrRest

theorem counterPowdr_safe_trace_simulates_from_state_safe_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrSafeEntrypointObligations cfg)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState)
    (hsafe : CounterTraceSafeAtState irState calls) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep cfg) evmState calls observables := by
  obtain ⟨count, hcounter⟩ := counterStorageRel_left_counterStateRel hrel
  exact counterPowdr_safe_trace_simulates_from_obligations
    cfg obligations calls hrel hcounter (hsafe count (counterStateRel_irCounterCount? hcounter))

theorem counterPowdr_trace_simulates_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrEntrypointObligations cfg)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep cfg) evmState calls observables :=
  ProofForge.Backend.Refinement.traceSimulation_lift
    counterIRStep (counterPowdrTraceStep cfg) CounterStorageRel
    (fun call {_irState} {_targetState} hrel =>
      counterPowdr_step_simulates_from_obligations cfg obligations call hrel)
    calls hrel

theorem counterPowdr_trace_simulates_after_initialize_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrEntrypointObligations cfg)
    (calls : List CounterCall) (irState : IRState) (evmState : EvmState) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep
          (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg)
          (.initialize :: calls) evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState (.initialize :: calls) observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep cfg) evmState (.initialize :: calls) observables := by
  obtain ⟨nextIr, _nextCount, observable, hirStep, htargetStep, _hcounterNext⟩ :=
    ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
      irState 0
  cases htargetStep
  obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalEvm, restObservables, hirRest, hpowdrRest,
      hrelFinal, hirTraceRest, hpowdrTraceRest⟩ :=
    counterPowdr_trace_simulates_from_obligations
      cfg obligations calls hrelNext
  refine ⟨finalIr, finalEvm, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    ProofForge.IR.StepSemantics.IRTraceMatches.cons hirStep hirTraceRest,
    ProofForge.IR.StepSemantics.IRTraceMatches.cons hpowdrStep hpowdrTraceRest⟩
  · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
      counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
      (counterPowdrTraceStep cfg) .initialize calls evmState nextEvm .none
      finalEvm restObservables hpowdrStep hpowdrRest

theorem counterPowdr_safe_trace_simulates_after_initialize_from_obligations
    (cfg : PowdrCounterConfig) (obligations : CounterPowdrSafeEntrypointObligations cfg)
    (calls : List CounterCall) (irState : IRState) (evmState : EvmState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep
          (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen (counterPowdrTraceStep cfg)
          (.initialize :: calls) evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState (.initialize :: calls) observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep cfg) evmState (.initialize :: calls) observables := by
  obtain ⟨nextIr, nextCount, observable, hirStep, htargetStep, hcounterNext⟩ :=
    ProofForge.Backend.Refinement.CounterUniversal.counter_initialize_simulates
      irState 0
  cases htargetStep
  have hsafeRest : counterTraceSafeFromCount 0 calls = true := by
    simpa [counterTraceSafeAfterInitialize] using hsafe
  obtain ⟨nextEvm, hpowdrStep, hrelNext⟩ :=
    obligations.initialize_simulates hirStep
  obtain ⟨finalIr, finalEvm, restObservables, hirRest, hpowdrRest,
      hrelFinal, hirTraceRest, hpowdrTraceRest⟩ :=
    counterPowdr_safe_trace_simulates_from_obligations
      cfg obligations calls hrelNext hcounterNext hsafeRest
  refine ⟨finalIr, finalEvm, #[.none] ++ restObservables, ?_, ?_,
    hrelFinal,
    ProofForge.IR.StepSemantics.IRTraceMatches.cons hirStep hirTraceRest,
    ProofForge.IR.StepSemantics.IRTraceMatches.cons hpowdrStep hpowdrTraceRest⟩
  · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
      counterIRStep .initialize calls irState nextIr .none
      finalIr restObservables hirStep hirRest
  · exact ProofForge.IR.StepSemantics.runTraceListGen_cons_ok
      (counterPowdrTraceStep cfg) .initialize calls evmState nextEvm .none
      finalEvm restObservables hpowdrStep hpowdrRest

abbrev CounterCompiledPowdrEntrypointObligations :=
  CounterPowdrEntrypointObligations counterCompiledPowdrConfig

abbrev CounterCompiledPowdrEvmPostconditions :=
  CounterPowdrEvmPostconditions counterCompiledPowdrConfig

abbrev CounterCompiledPowdrPreparedEvmPostconditions :=
  CounterPowdrPreparedEvmPostconditions counterCompiledPowdrConfig

abbrev CounterCompiledPowdrPreparedStorageModels :=
  CounterPowdrPreparedStorageModels counterCompiledPowdrConfig

def counterCompiledPowdrPreparedStorageModelsOfInitializeSegmentProvider
    (provider : CounterPreparedInitializeSegmentProvider)
    (increment_writes_succ :
      ∀ {preparedState count},
        CounterPreparedCall counterCompiledPowdrConfig .increment preparedState →
        count + 1 < counterU64Modulus →
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            preparedState) count →
        ∃ nextEvm,
          counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
              .increment =
            .ok (nextEvm, .none) ∧
          CounterStorageWordRel
            (counterStorageValue counterContractAddress counterCountSlot nextEvm)
            (count + 1))
    (get_returns_count :
      ∀ {preparedState count},
        CounterPreparedCall counterCompiledPowdrConfig .get preparedState →
        count < counterU64Modulus →
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            preparedState) count →
        ∃ nextEvm,
          counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
              .get =
            .ok (nextEvm, .u64 count) ∧
          CounterStorageWordRel
            (counterStorageValue counterContractAddress counterCountSlot nextEvm)
            count) :
    CounterCompiledPowdrPreparedStorageModels where
  initialize_writes_storage_model :=
    counterCompiledPreparedInitialize_storage_model_of_segment_provider_ok provider
  increment_writes_succ := increment_writes_succ
  get_returns_count := get_returns_count

def counterCompiledPowdrPreparedStorageModelsOfInitializeReductionChainProvider
    (provider : CounterPreparedInitializeReductionChainProvider)
    (increment_writes_succ :
      ∀ {preparedState count},
        CounterPreparedCall counterCompiledPowdrConfig .increment preparedState →
        count + 1 < counterU64Modulus →
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            preparedState) count →
        ∃ nextEvm,
          counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
              .increment =
            .ok (nextEvm, .none) ∧
          CounterStorageWordRel
            (counterStorageValue counterContractAddress counterCountSlot nextEvm)
            (count + 1))
    (get_returns_count :
      ∀ {preparedState count},
        CounterPreparedCall counterCompiledPowdrConfig .get preparedState →
        count < counterU64Modulus →
        CounterStorageWordRel
          (counterStorageValue counterContractAddress counterCountSlot
            preparedState) count →
        ∃ nextEvm,
          counterPowdrPreparedTraceStep counterCompiledPowdrConfig preparedState
              .get =
            .ok (nextEvm, .u64 count) ∧
          CounterStorageWordRel
            (counterStorageValue counterContractAddress counterCountSlot nextEvm)
            count) :
    CounterCompiledPowdrPreparedStorageModels where
  initialize_writes_storage_model :=
    counterCompiledPreparedInitialize_storage_model_of_reduction_chain_provider_ok
      provider
  increment_writes_succ := increment_writes_succ
  get_returns_count := get_returns_count

def counterCompiledPowdrPreparedStorageModelsOfReductionChainProviders
    {incrementFuel getFuel : Nat}
    (initializeProvider : CounterPreparedInitializeReductionChainProvider)
    (incrementProvider :
      CounterPreparedIncrementReductionChainProvider incrementFuel)
    (getProvider : CounterPreparedGetReductionChainProvider getFuel)
    (hincrementFuel : incrementFuel ≤ counterCompiledRuntimeFuel)
    (hgetFuel : getFuel ≤ counterCompiledRuntimeFuel) :
    CounterCompiledPowdrPreparedStorageModels where
  initialize_writes_storage_model :=
    counterCompiledPreparedInitialize_storage_model_of_reduction_chain_provider_ok
      initializeProvider
  increment_writes_succ :=
    counterCompiledPreparedIncrement_storage_model_of_reduction_chain_provider_ok
      incrementProvider hincrementFuel
  get_returns_count :=
    counterCompiledPreparedGet_storage_model_of_reduction_chain_provider_ok
      getProvider hgetFuel

def counterCompiledPowdrEvmPostconditionsOfPrepared
    (post : CounterCompiledPowdrPreparedEvmPostconditions) :
    CounterCompiledPowdrEvmPostconditions :=
  counterPowdrEvmPostconditionsOfPrepared counterCompiledPowdrConfig post

abbrev CounterCompiledPowdrSafeEntrypointObligations :=
  CounterPowdrSafeEntrypointObligations counterCompiledPowdrConfig

def counterCompiledPowdrSafeEntrypointObligationsOfPostconditions
    (post : CounterCompiledPowdrEvmPostconditions) :
    CounterCompiledPowdrSafeEntrypointObligations :=
  counterPowdrSafeEntrypointObligationsOfPostconditions
    counterCompiledPowdrConfig post

def counterCompiledPowdrPreparedEvmPostconditionsOfStorageModels
    (models : CounterCompiledPowdrPreparedStorageModels) :
    CounterCompiledPowdrPreparedEvmPostconditions :=
  counterPowdrPreparedEvmPostconditionsOfStorageModels counterCompiledPowdrConfig models

def counterCompiledPowdrSafeEntrypointObligationsOfPreparedStorageModels
    (models : CounterCompiledPowdrPreparedStorageModels) :
    CounterCompiledPowdrSafeEntrypointObligations :=
  counterPowdrSafeEntrypointObligationsOfPreparedStorageModels
    counterCompiledPowdrConfig models

theorem counterCompiledPowdr_trace_simulates_after_initialize_from_obligations
    (obligations : CounterCompiledPowdrEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (evmState : EvmState) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep
          (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig)
          (.initialize :: calls) evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState (.initialize :: calls) observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState (.initialize :: calls) observables :=
  counterPowdr_trace_simulates_after_initialize_from_obligations
    counterCompiledPowdrConfig obligations calls irState evmState

theorem counterCompiledPowdr_safe_trace_simulates_after_initialize_from_obligations
    (obligations : CounterCompiledPowdrSafeEntrypointObligations)
    (calls : List CounterCall) (irState : IRState) (evmState : EvmState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep
          (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig)
          (.initialize :: calls) evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState (.initialize :: calls) observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState (.initialize :: calls) observables :=
  counterPowdr_safe_trace_simulates_after_initialize_from_obligations
    counterCompiledPowdrConfig obligations calls irState evmState hsafe

theorem counterCompiledPowdr_safe_trace_simulates_after_initialize_from_prepared_storage_models
    (models : CounterCompiledPowdrPreparedStorageModels)
    (calls : List CounterCall) (irState : IRState) (evmState : EvmState)
    (hsafe : counterTraceSafeAfterInitialize calls = true) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep
          (.initialize :: calls) irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig)
          (.initialize :: calls) evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState (.initialize :: calls) observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState (.initialize :: calls) observables :=
  counterCompiledPowdr_safe_trace_simulates_after_initialize_from_obligations
    (counterCompiledPowdrSafeEntrypointObligationsOfPreparedStorageModels models)
    calls irState evmState hsafe

theorem counterCompiledPowdr_safe_trace_simulates_from_state_safe_obligations
    (obligations : CounterCompiledPowdrSafeEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState)
    (hsafe : CounterTraceSafeAtState irState calls) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState calls observables :=
  counterPowdr_safe_trace_simulates_from_state_safe_obligations
    counterCompiledPowdrConfig obligations calls hrel hsafe

theorem counterCompiledPowdr_safe_trace_simulates_from_state_safe_prepared_storage_models
    (models : CounterCompiledPowdrPreparedStorageModels)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState)
    (hsafe : CounterTraceSafeAtState irState calls) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen counterIRStep calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches counterIRStep
        irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState calls observables :=
  counterCompiledPowdr_safe_trace_simulates_from_state_safe_obligations
    (counterCompiledPowdrSafeEntrypointObligationsOfPreparedStorageModels models)
    calls hrel hsafe

/-! ### FV-9.5 EVM cap: content-honest `∀ (m : Module)` EVM/powdr fragment-refines

`moduleIrStep m` runs **`m`'s own entrypoint bodies**; bridge via
`moduleIrStep_eq_irStep_of_isCounterModule`, then
`counterPowdr_trace_simulates_from_obligations`. -/

open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.Refinement.ConstructorCoverage

theorem evmCompiledPowdr_fragment_refines_all
    (m : Module) (hm : isCounterModule m = true)
    ( _hcovered : moduleInCoveredFragment m = true)
    (obligations : CounterCompiledPowdrEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen (moduleIrStep m) calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches (moduleIrStep m) irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig) evmState calls observables := by
  have hfun : moduleIrStep m = irStep :=
    funext fun s => funext fun c => moduleIrStep_eq_irStep_of_isCounterModule hm c s
  rw [hfun]
  exact counterPowdr_trace_simulates_from_obligations counterCompiledPowdrConfig obligations calls hrel

end ProofForge.Backend.Evm.CounterRefinement.LegacyHighPacked

namespace ProofForge.Backend.Evm.CounterRefinement

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal
open ProofForge.Backend.Refinement.ConstructorCoverage

abbrev IRState := ProofForge.IR.Semantics.State
abbrev EvmState := ProofForge.Backend.Evm.PowdrAdapter.State
abbrev CounterCall := ProofForge.Backend.Refinement.CounterUniversal.CounterCall
abbrev counterIRStep := ProofForge.Backend.Refinement.CounterUniversal.irStep

def counterCountSlotNat : Nat := 0

theorem counter_count_slot_from_layout :
    ProofForge.Backend.Evm.Plan.stateSlot?
      ProofForge.IR.Examples.Counter.module "count" = some counterCountSlotNat := by
  native_decide

def counterCountSlot : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat counterCountSlotNat

def counterU64Modulus : Nat := 2 ^ 64

def counterHighPaddingModulus : Nat := 2 ^ 192

/-! `byteOffset = 0` follows Solidity storage layout: the first packed field
occupies the least-significant bytes of its slot. -/
def counterPackedCountNat (count : Nat) : Nat := count

def counterPackedCountValue (count : Nat) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat (counterPackedCountNat count)

/-- `padding` is the neighboring high-order 192-bit payload. -/
def counterPaddedCountValue (count padding : Nat) : EvmSemantics.UInt256 :=
  EvmSemantics.UInt256.ofNat
    (counterPackedCountNat count + padding * counterU64Modulus)

def counterHighPaddingNat (word : EvmSemantics.UInt256) : Nat :=
  word.toNat / counterU64Modulus

/-- Initializing `count` clears only its low 64 bits. -/
def counterInitializeStorageWord (word : EvmSemantics.UInt256) :
    EvmSemantics.UInt256 :=
  counterPaddedCountValue 0 (counterHighPaddingNat word)

def CounterStorageWordRel (word : EvmSemantics.UInt256) (count : Nat) : Prop :=
  ∃ padding,
    padding < counterHighPaddingModulus ∧
    word = counterPaddedCountValue count padding

theorem counterStorageWordRel_packed (count : Nat) :
    CounterStorageWordRel (counterPackedCountValue count) count := by
  refine ⟨0, ?_, ?_⟩
  · native_decide
  · simp [counterPackedCountValue, counterPaddedCountValue,
      counterPackedCountNat]

theorem counterStorageWordRel_padded {count padding : Nat}
    (hpadding : padding < counterHighPaddingModulus) :
    CounterStorageWordRel (counterPaddedCountValue count padding) count :=
  ⟨padding, hpadding, rfl⟩

theorem counterHighPaddingNat_lt (word : EvmSemantics.UInt256) :
    counterHighPaddingNat word < counterHighPaddingModulus := by
  unfold counterHighPaddingNat counterU64Modulus counterHighPaddingModulus
  rw [Nat.div_lt_iff_lt_mul (by native_decide)]
  exact word.val.isLt

theorem counterInitializeStorageWord_rel_zero (word : EvmSemantics.UInt256) :
    CounterStorageWordRel (counterInitializeStorageWord word) 0 := by
  unfold counterInitializeStorageWord
  exact counterStorageWordRel_padded (counterHighPaddingNat_lt word)

abbrev counterContractAddress := LegacyHighPacked.counterContractAddress
abbrev counterAccount := LegacyHighPacked.counterAccount
abbrev counterStorageValue := LegacyHighPacked.counterStorageValue

def setCounterStorage (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (state : EvmState) (value : Nat) : EvmState :=
  let account := state.accountMap address
  let storage := account.storage.set slot (counterPackedCountValue value)
  { state with
    accountMap := state.accountMap.set address { account with storage := storage } }

def setCounterStorageWord (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (state : EvmState)
    (word : EvmSemantics.UInt256) : EvmState :=
  let account := state.accountMap address
  let storage := account.storage.set slot word
  { state with
    accountMap := state.accountMap.set address { account with storage := storage } }

def irCounterCount? (state : IRState) : Option Nat :=
  match state.read "count" with
  | some (.u64 count) => some count
  | _ => none

def CounterStorageRelAt (address : EvmSemantics.AccountAddress)
    (slot : EvmSemantics.UInt256) (irState : IRState) (evmState : EvmState) : Prop :=
  ∃ count,
    irCounterCount? irState = some count ∧
    count < counterU64Modulus ∧
    CounterStorageWordRel (counterStorageValue address slot evmState) count

def CounterStorageRel : IRState → EvmState → Prop :=
  CounterStorageRelAt counterContractAddress counterCountSlot

abbrev counterCallSelector := LegacyHighPacked.counterCallSelector
abbrev counterCallCalldata := LegacyHighPacked.counterCallCalldata

/-! Current CLI-emitted Counter runtime, pinned to solc 0.8.30 (the CI
toolchain). Its storage reads use `SHR 0`; writes mask the value before `SHL 0`
and preserve the upper 192 bits. -/
def counterCompiledRuntimeHex : String :=
  EvmRefinement.CounterRuntime.hex

def counterCompiledRuntimeCode : ByteArray :=
  (EvmRefinement.HexWitness.decodeHex? counterCompiledRuntimeHex).getD
    (ByteArray.mk #[])

theorem counterCompiledRuntimeHex_decodes :
    EvmRefinement.HexWitness.decodeHex? counterCompiledRuntimeHex =
      some counterCompiledRuntimeCode := by
  native_decide

theorem counterCompiledRuntimeCode_size :
    counterCompiledRuntimeCode.size = 262 := by
  native_decide

theorem counterCompiledRuntimeCode_reads_count_from_low_64_bits :
    LegacyHighPacked.byteArrayHasSliceAt counterCompiledRuntimeCode
      (ByteArray.mk #[
        0x60, 0x01, 0x80, 0x60, 0x40, 0x1b, 0x03, 0x5f, 0x54, 0x5f, 0x1c,
        0x16, 0x90, 0x56]) 206 = true := by
  native_decide

theorem counterCompiledRuntimeCode_checks_u64_narrowing :
    LegacyHighPacked.byteArrayHasSliceAt counterCompiledRuntimeCode
      (ByteArray.mk #[
        0x5b, 0x90, 0x81, 0x11, 0x60, 0xe5, 0x57, 0x90, 0x56, 0x5b, 0x5f,
        0x80, 0xfd]) 220 = true := by
  native_decide

theorem counterCompiledRuntimeCode_checks_increment_addition :
    LegacyHighPacked.byteArrayHasSliceAt counterCompiledRuntimeCode
      (ByteArray.mk #[
        0x5b, 0x81, 0x5f, 0x19, 0x03, 0x81, 0x11, 0x60, 0xf6, 0x57, 0x01,
        0x90, 0x56, 0x5b, 0x5f, 0x80, 0xfd]) 233 = true := by
  native_decide

abbrev PowdrCounterConfig := LegacyHighPacked.PowdrCounterConfig

def counterCompiledRuntimeFuel : Nat := 5000

def counterCompiledPowdrConfig : PowdrCounterConfig := {
  runtimeCode := counterCompiledRuntimeCode
  fuel := counterCompiledRuntimeFuel
}

def counterBaseEvmState : EvmState :=
  let base := LegacyHighPacked.counterBaseEvmState
  { base with
    executionEnv := { base.executionEnv with code := counterCompiledRuntimeCode } }

abbrev counterPowdrPreparedTraceStep := LegacyHighPacked.counterPowdrPreparedTraceStep
abbrev counterPowdrTraceStep := LegacyHighPacked.counterPowdrTraceStep
abbrev counterPowdrRunTrace := LegacyHighPacked.counterPowdrRunTrace
abbrev counterPowdrStepReturns := LegacyHighPacked.counterPowdrStepReturns
abbrev counterPowdrTraceReturns := LegacyHighPacked.counterPowdrTraceReturns

theorem counterCompiledPowdr_initialize_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig counterBaseEvmState
      .initialize .none = true := by
  native_decide

theorem counterCompiledPowdr_get_zero_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig counterBaseEvmState
      .get (.u64 0) = true := by
  native_decide

theorem counterCompiledPowdr_get_packed_seven_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig
      (setCounterStorage counterContractAddress counterCountSlot counterBaseEvmState 7)
      .get (.u64 7) = true := by
  native_decide

theorem counterCompiledPowdr_get_padded_seven_executable_smoke :
    counterPowdrStepReturns counterCompiledPowdrConfig
      (setCounterStorageWord counterContractAddress counterCountSlot counterBaseEvmState
        (counterPaddedCountValue 7 123))
      .get (.u64 7) = true := by
  native_decide

def counterCompiledPowdrIncrementPreservesHighPadding : Bool :=
  match counterPowdrRunTrace counterCompiledPowdrConfig [.increment, .get]
      (setCounterStorageWord counterContractAddress counterCountSlot counterBaseEvmState
        (counterPaddedCountValue 7 123)) with
  | .ok (finalState, observables) =>
      observables == #[.none, .u64 8] &&
      counterStorageValue counterContractAddress counterCountSlot finalState ==
        counterPaddedCountValue 8 123
  | .error _ => false

theorem counterCompiledPowdr_increment_preserves_high_padding :
    counterCompiledPowdrIncrementPreservesHighPadding = true := by
  native_decide

def counterCompiledPowdrInitializePreservesHighPadding : Bool :=
  match counterPowdrRunTrace counterCompiledPowdrConfig [.initialize, .get]
      (setCounterStorageWord counterContractAddress counterCountSlot counterBaseEvmState
        (counterPaddedCountValue 7 123)) with
  | .ok (finalState, observables) =>
      observables == #[.none, .u64 0] &&
      counterStorageValue counterContractAddress counterCountSlot finalState ==
        counterPaddedCountValue 0 123
  | .error _ => false

theorem counterCompiledPowdr_initialize_preserves_high_padding :
    counterCompiledPowdrInitializePreservesHighPadding = true := by
  native_decide

theorem counterCompiledPowdr_initialize_increment_get_executable_smoke :
    counterPowdrTraceReturns counterCompiledPowdrConfig
      [.initialize, .increment, .get] counterBaseEvmState
      #[.none, .none, .u64 1] = true := by
  native_decide

def counterCompiledPowdrExecutableTraceOk (obligation : TraceObligation) : Bool :=
  LegacyHighPacked.counterPowdrExecutableTraceOk
    counterCompiledPowdrConfig counterBaseEvmState obligation

def counterCompiledPowdrTargetSemantics : TargetSemantics :=
  { LegacyHighPacked.counterPowdrTargetSemantics counterCompiledPowdrConfig with
    executableTraceOk := counterCompiledPowdrExecutableTraceOk
    irStateRel := CounterStorageRel
    initialMachineState := fun _ => none
    initialRelHolds := by
      intros _ _ h
      simp at h }

def counterCompiledPowdrTraceObligation : TraceObligation :=
  LegacyHighPacked.counterCompiledPowdrTraceObligation

theorem counterCompiledPowdr_executable_trace_ok :
    counterCompiledPowdrTargetSemantics.executableTraceOk
      counterCompiledPowdrTraceObligation = true := by
  native_decide

theorem counterCompiledPowdr_ir_and_target_trace_match :
    ProofForge.Backend.Evm.Refinement.irTraceOk
        counterCompiledPowdrTraceObligation = true ∧
      counterCompiledPowdrExecutableTraceOk
        counterCompiledPowdrTraceObligation = true := by
  native_decide

structure CounterCompiledPowdrEntrypointObligations where
  step_simulates :
    ∀ (call : CounterCall) {irState : IRState} {evmState : EvmState},
      CounterStorageRel irState evmState →
      ∃ nextIr nextEvm observable,
        counterIRStep irState call = .ok (nextIr, observable) ∧
        counterPowdrTraceStep counterCompiledPowdrConfig evmState call =
          .ok (nextEvm, observable) ∧
        CounterStorageRel nextIr nextEvm

/-! The universal cap remains assumption-explicit: concrete powdr execution is
pinned above, while full per-entrypoint preservation is supplied as an
obligation until the compiler-independent automation layer exists. -/
theorem evmCompiledPowdr_fragment_refines_all
    (m : Module) (hm : isCounterModule m = true)
    (_hcovered : moduleInCoveredFragment m = true)
    (obligations : CounterCompiledPowdrEntrypointObligations)
    (calls : List CounterCall) {irState : IRState} {evmState : EvmState}
    (hrel : CounterStorageRel irState evmState) :
    ∃ finalIr finalEvm observables,
      ProofForge.IR.StepSemantics.runTraceListGen (moduleIrStep m) calls irState =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          (counterPowdrTraceStep counterCompiledPowdrConfig) calls evmState =
        .ok (finalEvm, observables) ∧
      CounterStorageRel finalIr finalEvm ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (moduleIrStep m) irState calls observables ∧
      ProofForge.IR.StepSemantics.IRTraceMatches
        (counterPowdrTraceStep counterCompiledPowdrConfig)
        evmState calls observables := by
  have hfun : moduleIrStep m = irStep :=
    funext fun state => funext fun call =>
      moduleIrStep_eq_irStep_of_isCounterModule hm call state
  rw [hfun]
  exact ProofForge.Backend.Refinement.traceSimulation_lift
    counterIRStep (counterPowdrTraceStep counterCompiledPowdrConfig)
    CounterStorageRel
    (fun call {_irState} {_targetState} related =>
      obligations.step_simulates call related)
    calls hrel

end ProofForge.Backend.Evm.CounterRefinement
