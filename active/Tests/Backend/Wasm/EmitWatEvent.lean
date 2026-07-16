import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR ProofForge.Backend.WasmHost.EmitWat

/-! Event probe: emit a JSON event with U64 + Bool fields, captured as a log. -/

def emitEp : Entrypoint := {
  name := "emitEvent", returns := .unit,
  body := #[.effect (.eventEmit "Seen" #[("value", .literal (.u64 42)), ("ok", .literal (.bool true))])] }

def eventModule : Module := { name := "EventProbe", state := #[], entrypoints := #[emitEp] }

def main : IO UInt32 := do
  match renderModule eventModule with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-event.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-event.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
