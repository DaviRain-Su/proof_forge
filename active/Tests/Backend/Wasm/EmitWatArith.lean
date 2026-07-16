import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.U32ArithmeticProbe

open ProofForge.IR.Examples U32ArithmeticProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render U32ArithmeticProbe (which uses `.pow`) via EmitWat to verify the
    pow helper. The probe asserts `z ^ a == 289` (17^2) among other arithmetic;
    with a=2, b=3 every assertEq holds and it returns 1. -/

def main : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
      let path := "build/wasm-near/emitwat-arith.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e =>
      IO.eprintln e.message
      pure 1