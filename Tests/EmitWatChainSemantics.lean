import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.IR.Contract
import ProofForge.IR.Examples.NearCrosscallProbe

namespace ProofForge.Tests.EmitWatChainSemantics

open ProofForge.IR
open ProofForge.Backend.WasmNear.EmitWat

def requireError (name : String) (module : Module) (expected : String) : IO Unit :=
  match renderModule module with
  | .error error =>
      if error.message == expected then
        pure ()
      else do
        IO.eprintln s!"{name}: unexpected EmitWat error"
        IO.eprintln s!"  expected: {expected}"
        IO.eprintln s!"  actual:   {error.message}"
        throw <| IO.userError s!"{name}: EmitWat error mismatch"
  | .ok _ => do
      IO.eprintln s!"{name}: expected EmitWat to reject the module"
      throw <| IO.userError s!"{name}: EmitWat unexpectedly accepted module"

def requireRenderedContains (name : String) (module : Module) (needles : Array String) : IO Unit :=
  match renderModule module with
  | .ok wat => do
      for needle in needles do
        if !wat.contains needle then do
          IO.eprintln s!"{name}: rendered WAT missing `{needle}`"
          throw <| IO.userError s!"{name}: EmitWat rendered output mismatch"
  | .error error => do
      IO.eprintln s!"{name}: expected EmitWat to render the module"
      IO.eprintln s!"  actual error: {error.message}"
      throw <| IO.userError s!"{name}: EmitWat unexpectedly rejected module"

def indexedEventModule : Module := {
  name := "IndexedEventProbe"
  state := #[]
  entrypoints := #[{
    name := "emit_indexed"
    returns := .unit
    body := #[
      .effect (.eventEmitIndexed "Seen"
        #[("account", .literal (.u64 1))]
        #[("value", .literal (.u64 2))])
    ]
  }]
}

def crosscallModule := ProofForge.IR.Examples.NearCrosscallProbe.module

def main : IO UInt32 := do
  requireRenderedContains "indexed event" indexedEventModule #["Seen", "account", "value", "log_utf8"]
  requireRenderedContains "crosscall promise" crosscallModule #[
    "promise_create", "promise_return", "promise_then", "promise_results_count",
    "promise_result", "__pf_promise_result_u64", "read_register",
    "callee.testnet", "remote_call", "handle_remote"
  ]
  IO.println "emitwat-chain-semantics: ok"
  return 0

end ProofForge.Tests.EmitWatChainSemantics

def main : IO UInt32 :=
  ProofForge.Tests.EmitWatChainSemantics.main
