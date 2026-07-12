import ProofForge.Backend.Stylus.CounterRefinement
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.Semantics

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def counterPlan : Except String StylusPlan := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- (ProofForge.IR.Legacy.Adapter.adaptLegacy spec).mapError (fun error => s!"{repr error}")
  (ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
    targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements
  }).mapError (fun error => error.message)

def flushCount (state : HostState) : Nat :=
  state.trace.foldl (fun count event => match event with | .storageFlush _ => count + 1 | _ => count) 0

def main : IO Unit := do
  let plan <- match counterPlan with | .ok plan => pure plan | .error e => throw <| IO.userError e
  let initialized <- match executeCounter plan {} .initialize with
    | .ok state => pure state | .error e => throw <| IO.userError e
  require (decodeU64 ((initialized.storage.find? fun entry => entry.1 == slotZero).get!.2) == 0)
    "initialize must commit zero to slot zero"
  require (initialized.calldata == #[0x81, 0x29, 0xfc, 0x1c])
    "initialize calldata must use the Solidity ABI selector"
  require (flushCount initialized == 1) "initialize must flush exactly once"
  let incremented <- match executeCounter plan initialized .increment with
    | .ok state => pure state | .error e => throw <| IO.userError e
  require (decodeU64 ((incremented.storage.find? fun entry => entry.1 == slotZero).get!.2) == 1)
    "increment must commit one"
  require (flushCount incremented == 1) "increment must flush exactly once"
  require (incremented.calldata == #[0xd0, 0x9d, 0xe0, 0x8a])
    "increment calldata must use the Solidity ABI selector"
  let got <- match executeCounter plan incremented .get with
    | .ok state => pure state | .error e => throw <| IO.userError e
  require (got.result == encodeU64 1) "get must return exact 32-byte ABI uint64"
  require (got.calldata == #[0x6d, 0x4c, 0xe6, 0x3c])
    "get calldata must use the Solidity ABI selector"
  require (flushCount got == 0) "get must not flush"
  let high := 2 ^ 40 + 7
  let seeded : HostState := { storage := #[(slotZero, encodeU64 high)] }
  let highGot <- match executeCounter plan seeded .get with
    | .ok state => pure state | .error e => throw <| IO.userError e
  require (decodeU64 highGot.result == high) "host-seeded value above 2^32 was truncated"
  let maximum := 2 ^ 64 - 1
  let maxState : HostState := { storage := #[(slotZero, encodeU64 maximum)] }
  let rejected <- match executeCounter plan maxState .increment with
    | .ok state => pure state | .error e => throw <| IO.userError e
  require (rejected.revertData == overflowBytes) "overflow must return deterministic revert bytes"
  require (rejected.storage == maxState.storage) "overflow must leave committed storage unchanged"
  require rejected.cache.isEmpty "overflow must discard cache"
  require (flushCount rejected == 0) "rejected increment must not flush"
  let some firstWord := plan.storage.words[0]?
    | throw <| IO.userError "Counter storage plan is empty"
  require (firstWord.slot == .literal slotZero) "Counter storage must use slot zero"
  IO.println "stylus-counter-lifecycle: ok"
