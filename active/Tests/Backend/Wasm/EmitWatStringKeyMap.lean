import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.StringKeyMapProbe

open ProofForge.IR.Examples StringKeyMapProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render StringKeyMapProbe (string-keyed Map<string, u128>) via EmitWat for
    real-VM execution. The entrypoint takes a Borsh string parameter (the
    AccountId map key), so the probe must be invoked with `--input-hex`. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-string-key-map.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1