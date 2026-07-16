import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.U32StorageScalarProbe

open ProofForge.IR.Examples U32StorageScalarProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render U32StorageScalarProbe (uses `.storageScalarAssignOp`) via EmitWat.
    storage_lifecycle: write 7 → n=read → write n → n+=5 → result=read == 12 (asserted)
    → returns cast(result) u64 = 12. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-scalar.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1
