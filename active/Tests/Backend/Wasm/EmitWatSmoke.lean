import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.Counter

open ProofForge.Backend.WasmHost.EmitWat

/-! EmitWat smoke: lower the portable IR Counter to WAT and write it out,
    then (out of band) `wat2wasm` + deploy to near-sandbox. -/

def main : IO UInt32 := do
  match renderModule ProofForge.IR.Examples.Counter.module with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-counter.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-counter.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
