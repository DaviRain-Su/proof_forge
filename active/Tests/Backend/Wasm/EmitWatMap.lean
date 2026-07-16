import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR ProofForge.Backend.WasmHost.EmitWat

/-! Map<U64, U64> storage probe: set / get / contains, default-on-missing. -/

def balances : StateDecl := { id := "balances", kind := .map .u64 16, type := .u64 }

def setHundred : Entrypoint := {
  name := "setHundred", returns := .unit,
  body := #[.effect (.storageMapSet "balances" (.literal (.u64 5)) (.literal (.u64 100)))] }

def getFive : Entrypoint := {
  name := "getFive", returns := .u64,
  body := #[.return (.effect (.storageMapGet "balances" (.literal (.u64 5))))] }

def getMissing : Entrypoint := {
  name := "getMissing", returns := .u64,
  body := #[.return (.effect (.storageMapGet "balances" (.literal (.u64 999))))] }

def hasFive : Entrypoint := {
  name := "hasFive", returns := .bool,
  body := #[.return (.effect (.storageMapContains "balances" (.literal (.u64 5))))] }

def mapModule : Module := {
  name := "MapProbe", state := #[balances],
  entrypoints := #[setHundred, getFive, getMissing, hasFive] }

def main : IO UInt32 := do
  match renderModule mapModule with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-map.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-map.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
