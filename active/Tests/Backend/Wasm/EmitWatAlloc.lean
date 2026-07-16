import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Examples.ArrayProbe
open ProofForge.IR.Examples ArrayProbe ProofForge.Backend.WasmHost.EmitWat

/-! Render allocator-strategy variants of ArrayProbe.sumLiteral:
    bumpReset (entrypoint-boundary reset), minimalMalloc/NEAR deployment
    (wasm-internal), external host-bump, and release fixtures.
    Imported allocators return wasm linear-memory offsets, not native host
    pointers. Jemalloc-shaped experiments are intentionally kept out of the
    NEAR smoke surface until a wasm-linked allocator path exists. -/

def main : IO UInt32 := do
  let render (m : ProofForge.IR.Module) (fname : String) : IO UInt32 := do
    match renderModule m with
    | .ok wat =>
        let path := s!"build/wasm-near/{fname}"
        IO.FS.createDirAll "build/wasm-near"
        IO.FS.writeFile path wat
        IO.println s!"wrote {path} ({wat.length} bytes)"
        pure 0
    | .error e => IO.eprintln e.message *> pure 1
  let r1 ← render emitWatSumResetModule "emitwat-alloc-reset.wat"
  let r2 ← render emitWatSumExternalModule "emitwat-alloc-external.wat"
  let r3 ← render emitWatSumMinimalMallocModule "emitwat-alloc-minimal.wat"
  let r4 ← render emitWatSumNearAllocatorModule "emitwat-alloc-near.wat"
  let r5 ← render emitWatReleaseMinimalMallocModule "emitwat-release-minimal.wat"
  let r6 ← render emitWatReleaseExternalModule "emitwat-release-external.wat"
  if r1 == 0 && r2 == 0 && r3 == 0 && r4 == 0 && r5 == 0 && r6 == 0 then pure 0 else pure 1
