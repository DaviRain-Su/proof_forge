import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.ArrayProbe
open ProofForge.IR.Examples ArrayProbe ProofForge.Backend.WasmHost.EmitWat

/-! Render the full ArrayProbe module: sumLiteral (arrayLit+arrayGet) + storageLifecycle + arrayPredicates (array equality). -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-array-full.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e => IO.eprintln e.message *> pure 1
