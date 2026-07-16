import ProofForge.Backend.WasmHost.WasmExec

/-!
Soroban host-model lemmas for the generic Wasm execution core (Phase 4 WASM host family).

`WasmExec.lean` stays chain-agnostic; this file instantiates the host-call hook
for the Stellar Soroban host surface (`_put` / `_get` / `set_return_data` /
`log_from_slice` / `require_auth_for_args` / `invoke_contract`). The storage
model is intentionally identical to NEAR's and CosmWasm's (`lookupStorage?` /
`writeStorage`) so contract-axis proofs can reuse the same abstract scalar
reasoning; only host-call names and stack arities differ.

This is the third WASM host adapter (after `NearHost` facts embedded in
`WasmInterpreter` and `CosmWasmHost.lean`). It proves the WASM host-family
thesis: a new WASM chain is a thin `*Host.lean` on top of the shared `WasmExec`
core, not a forked EmitWat.

Keep this file thin: generic stack-machine lemmas live in `WasmExec.lean`, and
contract-specific refinements belong in `CounterSorobanRefinement.lean` /
future `ValueVaultSorobanExec.lean`.
-/

namespace ProofForge.Backend.WasmHost.SorobanHost

open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.WasmHost.WasmExec

set_option linter.unusedSimpArgs false

abbrev Bytes := WasmExec.Bytes
abbrev Storage := WasmExec.Storage
abbrev State := WasmExec.State

theorem runHostCall_soroban_eq_hook (state : State) (name : String)
    (hbridge : state.host.bridge = .soroban) :
    runHostCall name state =
      runHostCallWith (hostArity .soroban) runSorobanHostCall name state := by
  unfold runHostCall
  rw [hbridge]

theorem sorobanHost_get_hit_ok
    (state : State) (keyPtr keyLen : Nat) (key value : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = some value) :
    runSorobanHostCall "_get" #[keyPtr, keyLen] state =
      .ok { state with valueStack := state.valueStack.push (leBytesToNat value) } := by
  simp [runSorobanHostCall, hkey, hlookup]

theorem sorobanHost_get_miss_ok
    (state : State) (keyPtr keyLen : Nat) (key : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = none) :
    runSorobanHostCall "_get" #[keyPtr, keyLen] state =
      .ok { state with valueStack := state.valueStack.push 0 } := by
  simp [runSorobanHostCall, hkey, hlookup]

theorem sorobanHost_put_ok
    (state : State) (keyPtr keyLen valuePtr valueLen : Nat) (key value : Bytes)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hvalue : readBytes state.memory valuePtr valueLen = value) :
    runSorobanHostCall "_put" #[keyPtr, keyLen, valuePtr, valueLen] state =
      .ok { state with
        host := { state.host with storage := writeStorage state.host.storage key value } } := by
  simp [runSorobanHostCall, hkey, hvalue]

theorem sorobanHost_set_return_data_ok
    (state : State) (ptr len : Nat) (value : Bytes)
    (hvalue : readBytes state.memory ptr len = value) :
    runSorobanHostCall "set_return_data" #[ptr, len] state =
      .ok { state with host := { state.host with returnValue := value } } := by
  simp [runSorobanHostCall, hvalue]

theorem sorobanHost_log_ok
    (state : State) (ptr len : Nat) :
    runSorobanHostCall "log_from_slice" #[ptr, len] state = .ok state := by
  simp [runSorobanHostCall]

theorem sorobanHost_require_auth_ok
    (state : State) (argsPtr argsLen : Nat)
    (hauth : state.host.sorobanAuthDenied = false := by rfl) :
    runSorobanHostCall "require_auth_for_args" #[argsPtr, argsLen] state =
      .ok (stackPush state 1) := by
  simp [runSorobanHostCall, hauth]

theorem sorobanHost_require_auth_denied
    (state : State) (argsPtr argsLen : Nat)
    (hauth : state.host.sorobanAuthDenied = true) :
    runSorobanHostCall "require_auth_for_args" #[argsPtr, argsLen] state =
      .error "soroban require_auth_for_args denied (host.sorobanAuthDenied)" := by
  simp [runSorobanHostCall, hauth]

/-- Host invoke records packed slices and returns handle `0`. -/
theorem sorobanHost_invoke_contract_ok
    (state : State)
    (contractLen contractPtr methodLen methodPtr argsLen argsPtr : Nat)
    (contract method callArgs : Bytes)
    (hc : readBytes state.memory contractPtr contractLen = contract)
    (hm : readBytes state.memory methodPtr methodLen = method)
    (ha : readBytes state.memory argsPtr argsLen = callArgs) :
    runSorobanHostCall "invoke_contract"
        #[contractLen, contractPtr, methodLen, methodPtr, argsLen, argsPtr] state =
      .ok (stackPush {
        state with
        host := {
          state.host with
          sorobanInvokes := state.host.sorobanInvokes.push (contract, method, callArgs)
        }
      } 0) := by
  simp [runSorobanHostCall, stackPush, hc, hm, ha]

theorem sorobanHost_hook_ok
    (name : String) (state argsState finalState : State)
    (argCount : Nat) (args : Array Nat)
    (harity : hostArity .soroban name = .ok argCount)
    (hsplit : splitStackArgs state argCount = .ok (args, argsState))
    (hrun : runSorobanHostCall name args argsState = .ok finalState) :
    runHostCallWith (hostArity .soroban) runSorobanHostCall name state = .ok finalState :=
  runHostCallWith_ok (hostArity .soroban) runSorobanHostCall name state argsState
    finalState argCount args harity hsplit hrun

theorem runHostCall_soroban_get_hit_stack_ok
    (state : State) (keyPtr keyLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .soroban)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hlookup : lookupStorage? state.host.storage key = some value) :
    runHostCall "_get" (stackPush (stackPush state keyPtr) keyLen) =
      .ok { state with valueStack := state.valueStack.push (leBytesToNat value) } := by
  rw [runHostCall_soroban_eq_hook (stackPush (stackPush state keyPtr) keyLen)
    "_get" (by simp [stackPush, hbridge])]
  exact sorobanHost_hook_ok
    (name := "_get")
    (state := stackPush (stackPush state keyPtr) keyLen)
    (argsState := state)
    (finalState := { state with valueStack := state.valueStack.push (leBytesToNat value) })
    (argCount := 2)
    (args := #[keyPtr, keyLen])
    rfl
    (splitStackArgs_stackPush2 state keyPtr keyLen)
    (sorobanHost_get_hit_ok state keyPtr keyLen key value hkey hlookup)

theorem runHostCall_soroban_put_stack_ok
    (state : State) (keyPtr keyLen valuePtr valueLen : Nat) (key value : Bytes)
    (hbridge : state.host.bridge = .soroban)
    (hkey : readBytes state.memory keyPtr keyLen = key)
    (hvalue : readBytes state.memory valuePtr valueLen = value) :
    runHostCall "_put"
        (stackPush
          (stackPush
            (stackPush
              (stackPush state keyPtr) keyLen) valuePtr) valueLen) =
      .ok { state with
        host := { state.host with storage := writeStorage state.host.storage key value } } := by
  rw [runHostCall_soroban_eq_hook
    (stackPush
      (stackPush
        (stackPush
          (stackPush state keyPtr) keyLen) valuePtr) valueLen)
    "_put" (by simp [stackPush, hbridge])]
  exact sorobanHost_hook_ok
    (name := "_put")
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
    (sorobanHost_put_ok state keyPtr keyLen valuePtr valueLen key value hkey hvalue)

/-- Smoke: the Soroban host bridge dispatches `_get` / `log_from_slice` /
`require_auth_for_args` / `invoke_contract` on a `.soroban`-bridged state without
error. Machine-checked witness that the third WASM host adapter plugs into the
shared `runHostCall` dispatch, including portable crosscall materialization. -/
def sorobanHostSmoke : Bool :=
  let state : State := { host := { bridge := .soroban } }
  match runHostCall "_get" (stackPush (stackPush state 0) 0) with
  | .ok _ =>
      match runHostCall "log_from_slice" (stackPush (stackPush state 0) 0) with
      | .ok _ =>
          match runHostCall "require_auth_for_args" (stackPush (stackPush state 0) 0) with
          | .ok _ =>
              -- invoke_contract: 6 stack args all zero → empty slices, handle 0
              let st6 :=
                stackPush (stackPush (stackPush (stackPush (stackPush (stackPush state 0) 0) 0) 0) 0) 0
              match runHostCall "invoke_contract" st6 with
              | .ok _ => true
              | .error _ => false
          | .error _ => false
      | .error _ => false
  | .error _ => false

theorem soroban_host_smoke_ok : sorobanHostSmoke = true := by
  native_decide

end ProofForge.Backend.WasmHost.SorobanHost