import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.U128PromiseResultProbe

open ProofForge.IR.Examples U128PromiseResultProbe
open ProofForge.Backend.WasmHost.EmitWat

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-u128-promiseresult.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1
