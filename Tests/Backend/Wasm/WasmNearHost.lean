import ProofForge.Backend.WasmHost.NearHost

/-! ## NEAR host-model smoke

Pins the first Wasm host instantiation layer. The generic `WasmExec` hook stays
host-neutral; these checks prove NEAR storage/register/return/context host ops
compose through that hook.
-/

namespace ProofForge.Tests.WasmNearHost

open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec
open ProofForge.Backend.WasmHost.NearHost

abbrev Bytes := ProofForge.Backend.WasmHost.NearHost.Bytes
abbrev State := ProofForge.Backend.WasmHost.NearHost.State

def key : Bytes := #[1, 2, 3]
def value : Bytes := #[9, 8, 7]

def storedState : State :=
  { memory := writeBytes (writeBytes #[] 10 key) 20 value
    host := { storage := #[(key, value)], signerAccountId := #[42], attachedDeposit := 55 } }

theorem storedState_read_value :
    readBytes storedState.memory 20 3 = value := by
  native_decide

example : True := by
  have _ := @runHostCall_near_eq_hook
  have _ := @nearHost_input_ok
  have _ := @nearHost_read_register_hit_ok
  have _ := @nearHost_read_register_miss_ok
  have _ := @nearHost_storage_read_hit_ok
  have _ := @nearHost_storage_read_miss_ok
  have _ := @nearHost_storage_write_fresh_ok
  have _ := @nearHost_storage_write_replace_ok
  have _ := @nearHost_value_return_ok
  have _ := @nearHost_log_utf8_ok
  have _ := @nearHost_block_index_ok
  have _ := @nearHost_signer_account_id_ok
  have _ := @nearHost_attached_deposit_ok
  have _ := @nearHost_hook_ok
  have _ := @runHostCall_near_input_stack_ok
  have _ := @runHostCall_near_storage_read_hit_stack_ok
  have _ := @runHostCall_near_storage_read_miss_stack_ok
  have _ := @runHostCall_near_storage_write_fresh_stack_ok
  have _ := @runHostCall_near_storage_write_replace_stack_ok
  have _ := @runHostCall_near_value_return_stack_ok
  have _ := @runHostCall_near_attached_deposit_stack_ok
  have _ := @hostCallStep_near_input_stack_reduction
  have _ := @hostCallStep_near_storage_read_hit_stack_reduction
  have _ := @hostCallStep_near_storage_read_miss_stack_reduction
  have _ := @hostCallStep_near_storage_write_fresh_stack_reduction
  have _ := @hostCallStep_near_storage_write_replace_stack_reduction
  have _ := @hostCallStep_near_value_return_stack_reduction
  have _ := @hostCallStep_near_attached_deposit_stack_reduction
  have _ := @nearHost_storage_read_after_write_same
  exact True.intro

theorem run_host_storage_read_hit_sample :
    runHostCall "storage_read"
        (stackPush (stackPush (stackPush storedState 3) 10) 0) =
      .ok (stackPush
        { storedState with
          host := { storedState.host with
            registers := writeRegister storedState.host.registers 0 value } }
        1) := by
  exact runHostCall_near_storage_read_hit_stack_ok storedState 3 10 0 value rfl
    (by native_decide)

theorem storage_read_hit_sample :
    runNearHostCall "storage_read" #[3, 10, 0] storedState =
      .ok (stackPush
        { storedState with
          host := { storedState.host with
            registers := writeRegister storedState.host.registers 0 value } }
        1) := by
  exact nearHost_storage_read_hit_ok storedState 3 10 0 value (by native_decide)

theorem value_return_sample :
    runNearHostCall "value_return" #[3, 20] storedState =
      .ok { storedState with host := { storedState.host with returnValue := value } } := by
  rw [storedState_read_value.symm]
  exact nearHost_value_return_ok storedState 3 20

theorem run_host_value_return_sample :
    runHostCall "value_return" (stackPush (stackPush storedState 3) 20) =
      .ok { storedState with host := { storedState.host with returnValue := value } } := by
  rw [storedState_read_value.symm]
  exact runHostCall_near_value_return_stack_ok storedState 3 20 rfl

theorem host_step_reduction_chain_value_return_sample :
    StateStepReductionChain [pushStep 3, pushStep 20, hostCallStep "value_return"]
        storedState
      { storedState with
        host := { storedState.host with returnValue := readBytes storedState.memory 20 3 } } := by
  apply StateStepReductionChain.cons
  · exact pushStep_ok storedState 3
  · apply StateStepReductionChain.cons
    · exact pushStep_ok (stackPush storedState 3) 20
    · apply StateStepReductionChain.cons
      · exact hostCallStep_near_value_return_stack_reduction storedState 3 20 rfl
      · exact StateStepReductionChain.nil
          { storedState with
            host := { storedState.host with returnValue := readBytes storedState.memory 20 3 } }

/-- near-sys ABI: write u128 LE at balance_ptr (here 0); attachedDeposit=55 → lo=55, hi=0. -/
theorem attached_deposit_sample :
    runNearHostCall "attached_deposit" #[0] storedState =
      .ok { storedState with
        memory := writeBytes storedState.memory 0
          (natToLEBytes 8 55 ++ natToLEBytes 8 0) } := by
  have h := nearHost_attached_deposit_ok storedState 0
  -- attachedDeposit = 55 ⇒ lo = 55, hi = 0
  simpa [storedState, Nat.mod_eq_of_lt (by decide : (55 : Nat) < 1 <<< 64),
    Nat.div_eq_of_lt (by decide : (55 : Nat) < 1 <<< 64)] using h

theorem run_host_attached_deposit_sample :
    runHostCall "attached_deposit" (stackPush storedState 0) =
      .ok { storedState with
        memory := writeBytes storedState.memory 0
          (natToLEBytes 8 55 ++ natToLEBytes 8 0) } := by
  have h := runHostCall_near_attached_deposit_stack_ok storedState 0 rfl
  simpa [storedState, Nat.mod_eq_of_lt (by decide : (55 : Nat) < 1 <<< 64),
    Nat.div_eq_of_lt (by decide : (55 : Nat) < 1 <<< 64)] using h

end ProofForge.Tests.WasmNearHost

def main : IO UInt32 := do
  IO.println "wasm-near-host-smoke: NEAR host hook lemmas checked"
  return 0
