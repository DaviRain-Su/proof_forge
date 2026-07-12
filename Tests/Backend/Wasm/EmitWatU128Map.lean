import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.U128MapProbe

open ProofForge.IR.Examples U128MapProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render U128MapProbe (hash-keyed Map<hash, u128>) via EmitWat for real-VM
    execution. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-u128-map.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1
