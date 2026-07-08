import ProofForge.Backend.WasmNear.WasmExec

/-!
CosmWasm host-model lemmas for the generic Wasm execution core.

`WasmExec.lean` stays chain-agnostic; this file instantiates the host-call hook
for CosmWasm (`db_read` / `db_write` / `set_return_data`). The storage model is
intentionally identical to NEAR's (`lookupStorage?` / `writeStorage`) so
contract-axis proofs can reuse the same abstract scalar reasoning; only host-call
names and stack arities differ.

Keep this file thin: generic stack-machine lemmas live in `WasmExec.lean`, and
contract-specific refinements live in `CounterCosmWasmRefinement.lean` /
`ValueVaultWasmExec.lean`.
-/

namespace ProofForge.Backend.WasmNear.CosmWasmHost

open ProofForge.Backend.WasmNear.WasmInterpreter
open ProofForge.Backend.WasmNear.WasmExec

set_option linter.unusedSimpArgs false

abbrev Bytes := WasmExec.Bytes
abbrev Storage := WasmExec.Storage
abbrev State := WasmExec.State

theorem runHostCall_cosmWasm_eq_hook (state : State) (name : String)
    (hbridge : state.host.bridge = .cosmWasm) :
    runHostCall name state =
      runHostCallWith (hostArity .cosmWasm) runCosmWasmHostCall name state := by
  unfold runHostCall
  rw [hbridge]

theorem cosmWasmHost_db_read_hit_ok
    (state : State) (keyPtr keyLen : Nat) (key value : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = some value) :
    runCosmWasmHostCall "db_read" #[keyPtr, keyLen] state =
      .ok { state with valueStack := state.valueStack.push (leBytesToNat value) } := by
  simp [runCosmWasmHostCall, hkey, hlookup]

theorem cosmWasmHost_db_read_miss_ok
    (state : State) (keyPtr keyLen : Nat) (key : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = none) :
    runCosmWasmHostCall "db_read" #[keyPtr, keyLen] state =
      .ok { state with valueStack := state.valueStack.push 0 } := by
  simp [runCosmWasmHostCall, hkey, hlookup]

theorem cosmWasmHost_db_write_ok
    (state : State) (keyPtr keyLen valuePtr valueLen : Nat) (key value : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hvalue : readBytes state.memory valuePtr valueLen = value) :
    runCosmWasmHostCall "db_write" #[keyPtr, keyLen, valuePtr, valueLen] state =
      .ok { state with
        host := { state.host with storage := writeStorage state.host.storage key value } } := by
  simp [runCosmWasmHostCall, hkey, hvalue]

theorem cosmWasmHost_set_return_data_ok
    (state : State) (ptr len : Nat) (value : Bytes)
    (hvalue : readBytes state.memory ptr len = value) :
    runCosmWasmHostCall "set_return_data" #[ptr, len] state =
      .ok { state with host := { state.host with returnValue := value } } := by
  simp [runCosmWasmHostCall, hvalue]

theorem cosmWasmHost_hook_ok
    (name : String) (state argsState finalState : State)
    (argCount : Nat) (args : Array Nat)
    (harity : hostArity .cosmWasm name = .ok argCount)
    (hsplit : splitStackArgs state argCount = .ok (args, argsState))
    (hrun : runCosmWasmHostCall name args argsState = .ok finalState) :
    runHostCallWith (hostArity .cosmWasm) runCosmWasmHostCall name state = .ok finalState :=
  runHostCallWith_ok (hostArity .cosmWasm) runCosmWasmHostCall name state argsState
    finalState argCount args harity hsplit hrun

theorem runHostCall_cosmWasm_db_read_hit_stack_ok
    (state : State) (keyPtr keyLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = some value) :
    runHostCall "db_read" (stackPush (stackPush state keyPtr) keyLen) =
      .ok { state with valueStack := state.valueStack.push (leBytesToNat value) } := by
  rw [runHostCall_cosmWasm_eq_hook (stackPush (stackPush state keyPtr) keyLen)
    "db_read" (by simp [stackPush, hbridge])]
  exact cosmWasmHost_hook_ok
    (name := "db_read")
    (state := stackPush (stackPush state keyPtr) keyLen)
    (argsState := state)
    (finalState := { state with valueStack := state.valueStack.push (leBytesToNat value) })
    (argCount := 2)
    (args := #[keyPtr, keyLen])
    rfl
    (splitStackArgs_stackPush2 state keyPtr keyLen)
    (cosmWasmHost_db_read_hit_ok state keyPtr keyLen key value hkey hlookup)

theorem runHostCall_cosmWasm_db_read_miss_stack_ok
    (state : State) (keyPtr keyLen : Nat) (key : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = none) :
    runHostCall "db_read" (stackPush (stackPush state keyPtr) keyLen) =
      .ok { state with valueStack := state.valueStack.push 0 } := by
  rw [runHostCall_cosmWasm_eq_hook (stackPush (stackPush state keyPtr) keyLen)
    "db_read" (by simp [stackPush, hbridge])]
  exact cosmWasmHost_hook_ok
    (name := "db_read")
    (state := stackPush (stackPush state keyPtr) keyLen)
    (argsState := state)
    (finalState := { state with valueStack := state.valueStack.push 0 })
    (argCount := 2)
    (args := #[keyPtr, keyLen])
    rfl
    (splitStackArgs_stackPush2 state keyPtr keyLen)
    (cosmWasmHost_db_read_miss_ok state keyPtr keyLen key hkey hlookup)

theorem runHostCall_cosmWasm_db_write_stack_ok
    (state : State) (keyPtr keyLen valuePtr valueLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hvalue : readBytes state.memory valuePtr valueLen = value) :
    runHostCall "db_write"
        (stackPush
          (stackPush
            (stackPush
              (stackPush state keyPtr) keyLen) valuePtr) valueLen) =
      .ok { state with
        host := { state.host with storage := writeStorage state.host.storage key value } } := by
  rw [runHostCall_cosmWasm_eq_hook
    (stackPush
      (stackPush
        (stackPush
          (stackPush state keyPtr) keyLen) valuePtr) valueLen)
    "db_write" (by simp [stackPush, hbridge])]
  exact cosmWasmHost_hook_ok
    (name := "db_write")
    (state := stackPush
      (stackPush
        (stackPush
          (stackPush state keyPtr) keyLen) valuePtr) valueLen)
    (argsState := state)
    (finalState := { state with
      host := { state.host with storage := writeStorage state.host.storage key value } })
    (argCount := 4)
    (args := #[keyPtr, keyLen, valuePtr, valueLen])
    rfl
    (splitStackArgs_stackPush4 state keyPtr keyLen valuePtr valueLen)
    (cosmWasmHost_db_write_ok state keyPtr keyLen valuePtr valueLen key value hkey hvalue)

theorem runHostCall_cosmWasm_set_return_data_stack_ok
    (state : State) (ptr len : Nat) (value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hvalue : readBytes state.memory ptr len = value) :
    runHostCall "set_return_data" (stackPush (stackPush state ptr) len) =
      .ok { state with host := { state.host with returnValue := value } } := by
  rw [runHostCall_cosmWasm_eq_hook (stackPush (stackPush state ptr) len)
    "set_return_data" (by simp [stackPush, hbridge])]
  exact cosmWasmHost_hook_ok
    (name := "set_return_data")
    (state := stackPush (stackPush state ptr) len)
    (argsState := state)
    (finalState := { state with host := { state.host with returnValue := value } })
    (argCount := 2)
    (args := #[ptr, len])
    rfl
    (splitStackArgs_stackPush2 state ptr len)
    (cosmWasmHost_set_return_data_ok state ptr len value hvalue)

theorem hostCallStep_cosmWasm_db_read_hit_stack_reduction
    (state : State) (keyPtr keyLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = some value) :
    StateStepReduction (hostCallStep "db_read")
        (stackPush (stackPush state keyPtr) keyLen)
      { state with valueStack := state.valueStack.push (leBytesToNat value) } :=
  hostCallStep_ok "db_read" (stackPush (stackPush state keyPtr) keyLen) _ <|
    runHostCall_cosmWasm_db_read_hit_stack_ok state keyPtr keyLen key value hbridge hkey hlookup

theorem hostCallStep_cosmWasm_db_read_miss_stack_reduction
    (state : State) (keyPtr keyLen : Nat) (key : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = none) :
    StateStepReduction (hostCallStep "db_read")
        (stackPush (stackPush state keyPtr) keyLen)
      { state with valueStack := state.valueStack.push 0 } :=
  hostCallStep_ok "db_read" (stackPush (stackPush state keyPtr) keyLen) _ <|
    runHostCall_cosmWasm_db_read_miss_stack_ok state keyPtr keyLen key hbridge hkey hlookup

theorem hostCallStep_cosmWasm_db_write_stack_reduction
    (state : State) (keyPtr keyLen valuePtr valueLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hvalue : readBytes state.memory valuePtr valueLen = value) :
    StateStepReduction (hostCallStep "db_write")
        (stackPush
          (stackPush
            (stackPush
              (stackPush state keyPtr) keyLen) valuePtr) valueLen)
      { state with
        host := { state.host with storage := writeStorage state.host.storage key value } } :=
  hostCallStep_ok "db_write"
    (stackPush
      (stackPush
        (stackPush
          (stackPush state keyPtr) keyLen) valuePtr) valueLen) _ <|
    runHostCall_cosmWasm_db_write_stack_ok state keyPtr keyLen valuePtr valueLen key value
      hbridge hkey hvalue

theorem hostCallStep_cosmWasm_set_return_data_stack_reduction
    (state : State) (ptr len : Nat) (value : Bytes)
    (hbridge : state.host.bridge = .cosmWasm)
    (hvalue : readBytes state.memory ptr len = value) :
    StateStepReduction (hostCallStep "set_return_data")
        (stackPush (stackPush state ptr) len)
      { state with host := { state.host with returnValue := value } } :=
  hostCallStep_ok "set_return_data" (stackPush (stackPush state ptr) len) _ <|
    runHostCall_cosmWasm_set_return_data_stack_ok state ptr len value hbridge hvalue

theorem cosmWasmHost_storage_read_after_write_same
    (storage : Storage) (key value : Bytes) :
    lookupStorage? (writeStorage storage key value) key = some value :=
  lookupStorage_writeStorage_same storage key value

end ProofForge.Backend.WasmNear.CosmWasmHost