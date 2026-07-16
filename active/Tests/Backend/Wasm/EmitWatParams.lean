import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR ProofForge.Backend.WasmHost.EmitWat

/-! Borsh input params: setN(v) reads one u64; setSum(a,b) reads two (offset 0,8). -/

def nState : StateDecl := { id := "n", kind := .scalar, type := .u64 }

def setN : Entrypoint := {
  name := "setN", params := #[("v", .u64)], returns := .unit,
  body := #[.effect (.storageScalarWrite "n" (.local "v"))] }

def setSum : Entrypoint := {
  name := "setSum", params := #[("a", .u64), ("b", .u64)], returns := .unit,
  body := #[.effect (.storageScalarWrite "n" (.add (.local "a") (.local "b")))] }

def getN : Entrypoint := {
  name := "getN", returns := .u64,
  body := #[.return (.effect (.storageScalarRead "n"))] }

def paramModule : Module := {
  name := "ParamProbe", state := #[nState],
  entrypoints := #[setN, setSum, getN] }

def main : IO UInt32 := do
  match renderModule paramModule with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-params.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-params.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
