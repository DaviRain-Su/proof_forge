import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.LoopProbe

open ProofForge.IR.Examples ConditionalProbe LoopProbe
open ProofForge.Backend.WasmHost.EmitWat

/-! Render ConditionalProbe (if/else) and LoopProbe (boundedFor) via EmitWat. -/

def write (name : String) : IO UInt32 := do
  match renderModule (match name with | "cond" => (ConditionalProbe.module) | _ => (LoopProbe.module)) with
  | .ok wat =>
      let path := s!"build/wasm-near/emitwat-{name}.wat"
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
  | .error e => IO.eprintln e.message *> pure 1

def main : IO UInt32 := do
  let _ ← write "cond"
  let _ ← write "loop"
  pure 0
