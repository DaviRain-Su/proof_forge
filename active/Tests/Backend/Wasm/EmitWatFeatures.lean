import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR ProofForge.Backend.WasmHost.EmitWat

/-! Exercises the broader scalar EmitWat surface: U32 state + arithmetic +
    comparison → Bool state + U32/Bool returns. Deployed & asserted out of band. -/

def nState : StateDecl := { id := "n", kind := .scalar, type := .u32 }
def flagState : StateDecl := { id := "flag", kind := .scalar, type := .bool }

def initEp : Entrypoint := {
  name := "init", returns := .unit,
  body := #[
    .effect (.storageScalarWrite "n" (.literal (.u32 0))),
    .effect (.storageScalarWrite "flag" (.literal (.bool false)))
  ] }

def bumpEp : Entrypoint := {
  name := "bump", returns := .unit,
  body := #[
    .letBind "old" .u32 (.effect (.storageScalarRead "n")),
    .letBind "new" .u32 (.add (.local "old") (.literal (.u32 5))),
    .effect (.storageScalarWrite "n" (.local "new")),
    .effect (.storageScalarWrite "flag" (.gt (.local "new") (.literal (.u32 10))))
  ] }

def getNEp : Entrypoint := {
  name := "getN", returns := .u32,
  body := #[.return (.effect (.storageScalarRead "n"))] }

def getFlagEp : Entrypoint := {
  name := "getFlag", returns := .bool,
  body := #[.return (.effect (.storageScalarRead "flag"))] }

def featuresModule : Module := {
  name := "Features",
  state := #[nState, flagState],
  entrypoints := #[initEp, bumpEp, getNEp, getFlagEp]
}

def main : IO UInt32 := do
  match renderModule featuresModule with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-features.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-features.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
