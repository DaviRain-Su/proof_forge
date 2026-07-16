import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.CallerAccountIdMapProbe

open ProofForge.IR.Examples CallerAccountIdMapProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render CallerAccountIdMapProbe (string-keyed Map<string, u128> keyed by the
    raw predecessor account id) via EmitWat for real-VM execution. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-caller-account-id-map.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1