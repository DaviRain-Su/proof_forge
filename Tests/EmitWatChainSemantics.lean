import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.IR.Contract

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

def nativeValueModule : Module := {
  name := "NativeValueProbe"
  state := #[]
  entrypoints := #[{
    name := "native_value"
    returns := .u64
    body := #[.return .nativeValue]
  }]
}

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

def crosscallModule : Module := {
  name := "CrosscallProbe"
  state := #[]
  entrypoints := #[{
    name := "call_remote"
    returns := .u64
    body := #[
      .return (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[])
    ]
  }]
}

def main : IO UInt32 := do
  requireError "native value" nativeValueModule ProofForge.Backend.WasmNear.EmitWat.nativeValueUnsupportedMessage
  requireError "indexed event" indexedEventModule (ProofForge.Backend.WasmNear.EmitWat.indexedEventUnsupportedMessage "Seen")
  requireError "crosscall" crosscallModule ProofForge.Backend.WasmNear.EmitWat.crosscallUnsupportedMessage
  IO.println "emitwat-chain-semantics: ok"
  return 0

end ProofForge.Tests.EmitWatChainSemantics

def main : IO UInt32 :=
  ProofForge.Tests.EmitWatChainSemantics.main
