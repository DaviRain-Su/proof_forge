import ProofForge.Backend.WasmHost.WasmExec

/-!
NEAR host-model lemmas for the generic Wasm execution core.

`WasmExec.lean` stays chain-agnostic: it proves stack/local/memory effects and
the host-call hook. This file is the first host instantiation layer. Later
CosmWasm/Soroban-style hosts should mirror this shape without changing the
generic Wasm core.
-/

namespace ProofForge.Backend.WasmHost.NearHost

open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec

set_option linter.unusedSimpArgs false

abbrev Bytes := WasmExec.Bytes
abbrev Storage := WasmExec.Storage
abbrev State := WasmExec.State

theorem runHostCall_near_eq_hook (state : State) (name : String)
    (hbridge : state.host.bridge = .near) :
    runHostCall name state =
      runHostCallWith (hostArity .near) runNearHostCall name state := by
  unfold runHostCall
  rw [hbridge]

theorem nearHost_input_ok (state : State) (registerId : Nat) :
    runNearHostCall "input" #[registerId] state =
      .ok { state with
        host := { state.host with
          registers := writeRegister state.host.registers registerId state.host.input } } := by
  rfl

theorem nearHost_read_register_hit_ok
    (state : State) (registerId ptr : Nat) (bytes : Bytes)
    (hlookup : lookupRegister? state.host.registers registerId = some bytes) :
    runNearHostCall "read_register" #[registerId, ptr] state =
      .ok { state with memory := writeBytes state.memory ptr bytes } := by
  simp [runNearHostCall, hostReadRegister, hlookup]

theorem nearHost_read_register_miss_ok
    (state : State) (registerId ptr : Nat)
    (hlookup : lookupRegister? state.host.registers registerId = none) :
    runNearHostCall "read_register" #[registerId, ptr] state = .ok state := by
  simp [runNearHostCall, hostReadRegister, hlookup]

theorem nearHost_storage_read_hit_ok
    (state : State) (keyLen keyPtr registerId : Nat) (value : Bytes)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some value) :
    runNearHostCall "storage_read" #[keyLen, keyPtr, registerId] state =
      .ok (stackPush
        { state with
          host := { state.host with
            registers := writeRegister state.host.registers registerId value } }
        1) := by
  simp [runNearHostCall, hlookup]

theorem nearHost_storage_read_miss_ok
    (state : State) (keyLen keyPtr registerId : Nat)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    runNearHostCall "storage_read" #[keyLen, keyPtr, registerId] state =
      .ok (stackPush state 0) := by
  simp [runNearHostCall, hlookup]

theorem nearHost_storage_write_fresh_ok
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    runNearHostCall "storage_write"
        #[keyLen, keyPtr, valueLen, valuePtr, registerId] state =
      .ok (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := state.host.registers } }
        0) := by
  simp [runNearHostCall, hlookup]

theorem nearHost_storage_write_replace_ok
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (old : Bytes)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some old) :
    runNearHostCall "storage_write"
        #[keyLen, keyPtr, valueLen, valuePtr, registerId] state =
      .ok (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := writeRegister state.host.registers registerId old } }
        1) := by
  simp [runNearHostCall, hlookup]

theorem nearHost_value_return_ok (state : State) (len ptr : Nat) :
    runNearHostCall "value_return" #[len, ptr] state =
      .ok { state with
        host := { state.host with returnValue := readBytes state.memory ptr len } } := by
  rfl

theorem nearHost_log_utf8_ok (state : State) (len ptr : Nat) :
    runNearHostCall "log_utf8" #[len, ptr] state =
      .ok { state with
        host := { state.host with
          logs := state.host.logs.push (readBytes state.memory ptr len) } } := by
  rfl

theorem nearHost_block_index_ok (state : State) :
    runNearHostCall "block_index" #[] state =
      .ok (stackPush state state.host.blockIndex) := by
  rfl

theorem nearHost_signer_account_id_ok (state : State) (registerId : Nat) :
    runNearHostCall "signer_account_id" #[registerId] state =
      .ok { state with
        host := { state.host with
          registers :=
            writeRegister state.host.registers registerId state.host.signerAccountId } } := by
  rfl

/-- near-sys: `attached_deposit(balance_ptr)` writes little-endian u128 at ptr.
IR uses the low 64 bits as `nativeValue` U64. -/
theorem nearHost_attached_deposit_ok (state : State) (balancePtr : Nat) :
    runNearHostCall "attached_deposit" #[balancePtr] state =
      .ok { state with
        memory := writeBytes state.memory balancePtr
          (natToLEBytes 8 (state.host.attachedDeposit % (1 <<< 64)) ++
            natToLEBytes 8 (state.host.attachedDeposit / (1 <<< 64))) } := by
  simp [runNearHostCall]

theorem nearHost_hook_ok
    (name : String) (state argsState finalState : State)
    (argCount : Nat) (args : Array Nat)
    (harity : hostArity .near name = .ok argCount)
    (hsplit : splitStackArgs state argCount = .ok (args, argsState))
    (hrun : runNearHostCall name args argsState = .ok finalState) :
    runHostCallWith (hostArity .near) runNearHostCall name state = .ok finalState :=
  runHostCallWith_ok (hostArity .near) runNearHostCall name state argsState
    finalState argCount args harity hsplit hrun

theorem runHostCall_near_input_stack_ok
    (state : State) (registerId : Nat)
    (hbridge : state.host.bridge = .near) :
    runHostCall "input" (stackPush state registerId) =
      .ok { state with
        host := { state.host with
          registers := writeRegister state.host.registers registerId state.host.input } } := by
  rw [runHostCall_near_eq_hook (stackPush state registerId) "input"
    (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "input")
    (state := stackPush state registerId)
    (argsState := state)
    (finalState := { state with
      host := { state.host with
        registers := writeRegister state.host.registers registerId state.host.input } })
    (argCount := 1)
    (args := #[registerId])
    rfl
    (splitStackArgs_stackPush1 state registerId)
    (nearHost_input_ok state registerId)

theorem runHostCall_near_storage_read_hit_stack_ok
    (state : State) (keyLen keyPtr registerId : Nat) (value : Bytes)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some value) :
    runHostCall "storage_read"
        (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId) =
      .ok (stackPush
        { state with
          host := { state.host with
            registers := writeRegister state.host.registers registerId value } }
        1) := by
  rw [runHostCall_near_eq_hook
    (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
    "storage_read" (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "storage_read")
    (state := stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
    (argsState := state)
    (finalState := stackPush
      { state with
        host := { state.host with
          registers := writeRegister state.host.registers registerId value } }
      1)
    (argCount := 3)
    (args := #[keyLen, keyPtr, registerId])
    rfl
    (splitStackArgs_stackPush3 state keyLen keyPtr registerId)
    (nearHost_storage_read_hit_ok state keyLen keyPtr registerId value hlookup)

theorem runHostCall_near_storage_read_miss_stack_ok
    (state : State) (keyLen keyPtr registerId : Nat)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    runHostCall "storage_read"
        (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId) =
      .ok (stackPush state 0) := by
  rw [runHostCall_near_eq_hook
    (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
    "storage_read" (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "storage_read")
    (state := stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
    (argsState := state)
    (finalState := stackPush state 0)
    (argCount := 3)
    (args := #[keyLen, keyPtr, registerId])
    rfl
    (splitStackArgs_stackPush3 state keyLen keyPtr registerId)
    (nearHost_storage_read_miss_ok state keyLen keyPtr registerId hlookup)

theorem runHostCall_near_storage_write_fresh_stack_ok
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    runHostCall "storage_write"
        (stackPush
          (stackPush
            (stackPush
              (stackPush
                (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId) =
      .ok (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := state.host.registers } }
        0) := by
  rw [runHostCall_near_eq_hook
    (stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
    "storage_write" (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "storage_write")
    (state := stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
    (argsState := state)
    (finalState := stackPush
      { state with
        host := { state.host with
          storage :=
            writeStorage state.host.storage
              (readBytes state.memory keyPtr keyLen)
              (readBytes state.memory valuePtr valueLen),
          registers := state.host.registers } }
      0)
    (argCount := 5)
    (args := #[keyLen, keyPtr, valueLen, valuePtr, registerId])
    rfl
    (splitStackArgs_stackPush5 state keyLen keyPtr valueLen valuePtr registerId)
    (nearHost_storage_write_fresh_ok state keyLen keyPtr valueLen valuePtr
      registerId hlookup)

theorem runHostCall_near_storage_write_replace_stack_ok
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (old : Bytes)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some old) :
    runHostCall "storage_write"
        (stackPush
          (stackPush
            (stackPush
              (stackPush
                (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId) =
      .ok (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := writeRegister state.host.registers registerId old } }
        1) := by
  rw [runHostCall_near_eq_hook
    (stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
    "storage_write" (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "storage_write")
    (state := stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
    (argsState := state)
    (finalState := stackPush
      { state with
        host := { state.host with
          storage :=
            writeStorage state.host.storage
              (readBytes state.memory keyPtr keyLen)
              (readBytes state.memory valuePtr valueLen),
          registers := writeRegister state.host.registers registerId old } }
      1)
    (argCount := 5)
    (args := #[keyLen, keyPtr, valueLen, valuePtr, registerId])
    rfl
    (splitStackArgs_stackPush5 state keyLen keyPtr valueLen valuePtr registerId)
    (nearHost_storage_write_replace_ok state keyLen keyPtr valueLen valuePtr
      registerId old hlookup)

theorem runHostCall_near_value_return_stack_ok
    (state : State) (len ptr : Nat)
    (hbridge : state.host.bridge = .near) :
    runHostCall "value_return" (stackPush (stackPush state len) ptr) =
      .ok { state with
        host := { state.host with returnValue := readBytes state.memory ptr len } } := by
  rw [runHostCall_near_eq_hook (stackPush (stackPush state len) ptr)
    "value_return" (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "value_return")
    (state := stackPush (stackPush state len) ptr)
    (argsState := state)
    (finalState := { state with
      host := { state.host with returnValue := readBytes state.memory ptr len } })
    (argCount := 2)
    (args := #[len, ptr])
    rfl
    (splitStackArgs_stackPush2 state len ptr)
    (nearHost_value_return_ok state len ptr)

theorem runHostCall_near_attached_deposit_stack_ok
    (state : State) (balancePtr : Nat)
    (hbridge : state.host.bridge = .near) :
    runHostCall "attached_deposit" (stackPush state balancePtr) =
      .ok { state with
        memory := writeBytes state.memory balancePtr
          (natToLEBytes 8 (state.host.attachedDeposit % (1 <<< 64)) ++
            natToLEBytes 8 (state.host.attachedDeposit / (1 <<< 64))) } := by
  rw [runHostCall_near_eq_hook (stackPush state balancePtr) "attached_deposit"
    (by simp [stackPush, hbridge])]
  exact nearHost_hook_ok
    (name := "attached_deposit")
    (state := stackPush state balancePtr)
    (argsState := state)
    (finalState := { state with
      memory := writeBytes state.memory balancePtr
        (natToLEBytes 8 (state.host.attachedDeposit % (1 <<< 64)) ++
          natToLEBytes 8 (state.host.attachedDeposit / (1 <<< 64))) })
    (argCount := 1)
    (args := #[balancePtr])
    rfl
    (splitStackArgs_stackPush1 state balancePtr)
    (nearHost_attached_deposit_ok state balancePtr)

theorem hostCallStep_near_input_stack_reduction
    (state : State) (registerId : Nat)
    (hbridge : state.host.bridge = .near) :
    StateStepReduction (hostCallStep "input") (stackPush state registerId)
      { state with
        host := { state.host with
          registers := writeRegister state.host.registers registerId state.host.input } } :=
  hostCallStep_ok "input" (stackPush state registerId) _ <|
    runHostCall_near_input_stack_ok state registerId hbridge

theorem hostCallStep_near_storage_read_hit_stack_reduction
    (state : State) (keyLen keyPtr registerId : Nat) (value : Bytes)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some value) :
    StateStepReduction (hostCallStep "storage_read")
        (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
      (stackPush
        { state with
          host := { state.host with
            registers := writeRegister state.host.registers registerId value } }
        1) :=
  hostCallStep_ok "storage_read"
    (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId) _ <|
    runHostCall_near_storage_read_hit_stack_ok state keyLen keyPtr registerId
      value hbridge hlookup

theorem hostCallStep_near_storage_read_miss_stack_reduction
    (state : State) (keyLen keyPtr registerId : Nat)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    StateStepReduction (hostCallStep "storage_read")
        (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId)
      (stackPush state 0) :=
  hostCallStep_ok "storage_read"
    (stackPush (stackPush (stackPush state keyLen) keyPtr) registerId) _ <|
    runHostCall_near_storage_read_miss_stack_ok state keyLen keyPtr registerId
      hbridge hlookup

theorem hostCallStep_near_storage_write_fresh_stack_reduction
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = none) :
    StateStepReduction (hostCallStep "storage_write")
        (stackPush
          (stackPush
            (stackPush
              (stackPush
                (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
      (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := state.host.registers } }
        0) :=
  hostCallStep_ok "storage_write"
    (stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId) _ <|
    runHostCall_near_storage_write_fresh_stack_ok state keyLen keyPtr valueLen
      valuePtr registerId hbridge hlookup

theorem hostCallStep_near_storage_write_replace_stack_reduction
    (state : State) (keyLen keyPtr valueLen valuePtr registerId : Nat)
    (old : Bytes)
    (hbridge : state.host.bridge = .near)
    (hlookup :
      lookupStorage? state.host.storage (readBytes state.memory keyPtr keyLen) = some old) :
    StateStepReduction (hostCallStep "storage_write")
        (stackPush
          (stackPush
            (stackPush
              (stackPush
                (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId)
      (stackPush
        { state with
          host := { state.host with
            storage :=
              writeStorage state.host.storage
                (readBytes state.memory keyPtr keyLen)
                (readBytes state.memory valuePtr valueLen),
            registers := writeRegister state.host.registers registerId old } }
        1) :=
  hostCallStep_ok "storage_write"
    (stackPush
      (stackPush
        (stackPush
          (stackPush
            (stackPush state keyLen) keyPtr) valueLen) valuePtr) registerId) _ <|
    runHostCall_near_storage_write_replace_stack_ok state keyLen keyPtr valueLen
      valuePtr registerId old hbridge hlookup

theorem hostCallStep_near_value_return_stack_reduction
    (state : State) (len ptr : Nat)
    (hbridge : state.host.bridge = .near) :
    StateStepReduction (hostCallStep "value_return")
        (stackPush (stackPush state len) ptr)
      { state with
        host := { state.host with returnValue := readBytes state.memory ptr len } } :=
  hostCallStep_ok "value_return" (stackPush (stackPush state len) ptr) _ <|
    runHostCall_near_value_return_stack_ok state len ptr hbridge

theorem hostCallStep_near_attached_deposit_stack_reduction
    (state : State) (balancePtr : Nat)
    (hbridge : state.host.bridge = .near) :
    StateStepReduction (hostCallStep "attached_deposit") (stackPush state balancePtr)
      { state with
        memory := writeBytes state.memory balancePtr
          (natToLEBytes 8 (state.host.attachedDeposit % (1 <<< 64)) ++
            natToLEBytes 8 (state.host.attachedDeposit / (1 <<< 64))) } :=
  hostCallStep_ok "attached_deposit" (stackPush state balancePtr) _ <|
    runHostCall_near_attached_deposit_stack_ok state balancePtr hbridge

theorem nearHost_storage_read_after_write_same
    (storage : NearHost.Storage) (key value : Bytes) :
    lookupStorage? (writeStorage storage key value) key = some value :=
  lookupStorage_writeStorage_same storage key value

end ProofForge.Backend.WasmHost.NearHost
