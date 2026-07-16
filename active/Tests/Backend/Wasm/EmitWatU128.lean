import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.U128StorageScalarProbe

open ProofForge.IR.Examples U128StorageScalarProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render U128StorageScalarProbe via EmitWat and write the WAT for real-VM
    execution. A correct lowering returns the 16-byte little-endian Borsh
    encoding of u128 7. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-u128.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1
