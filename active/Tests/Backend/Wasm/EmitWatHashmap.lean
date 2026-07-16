import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.MapProbe

open ProofForge.IR.Examples MapProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render the EmitWat-compatible `MapProbe.emitWatFullModule` (Map\u003cHash, Hash\u003e, hash-keyed)
    to WAT for the hash-map smoke test. The full `MapProbe.module` uses
    `storageMapInsert` and `pathLifecycle` (struct/path storage) which EmitWat
    does not lower; `emitWatModule` is the supported subset (get/has/set). -/

def main : IO UInt32 := do
  match renderModule emitWatFullModule with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-maphash.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1