import ProofForge.Backend.Move.Sui
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.SuiDiagnostics

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def expectErrorContains
    (result : Except ProofForge.Backend.Move.Sui.EmitError α)
    (needles : Array String)
    (context : String) : IO Unit := do
  match result with
  | .ok _ => throw <| IO.userError s!"{context}: expected Sui diagnostic"
  | .error err =>
      for needle in needles do
        require (contains err.message needle) s!"{context}: diagnostic `{err.message}` missing `{needle}`"

def mapStateModule : Module := {
  name := "MapCounter"
  state := #[{
    id := "counts"
    kind := .map .address 16
    type := .u64
  }]
  entrypoints := #[]
}

def u32StateModule : Module := {
  name := "U32Counter"
  state := #[{
    id := "count"
    kind := .scalar
    type := .u32
  }]
  entrypoints := #[]
}

def crosscallModule : Module := {
  name := "CrosscallCounter"
  state := ProofForge.IR.Examples.Counter.module.state
  entrypoints := #[{
    name := "poke"
    params := #[("target", .address), ("method", .hash)]
    returns := .unit
    body := #[
      .letBind "result" .u64 (.crosscallInvokeTyped (.local "target") (.local "method") #[] .u64)
    ]
  }]
}

def main : IO UInt32 := do
  match ProofForge.Backend.Move.Sui.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok files =>
      require (files.any (fun file => file.path == "Move.toml")) "Sui Counter package missing Move.toml"
      require (files.any (fun file => file.path == "sources/counter.move")) "Sui Counter package missing source"
      require (files.any (fun file => file.path == "tests/counter_tests.move")) "Sui Counter package missing tests"
  | .error err =>
      throw <| IO.userError s!"Sui Counter package unexpectedly failed: {err.message}"

  expectErrorContains
    (ProofForge.Backend.Move.Sui.renderPackage mapStateModule)
    #["Sui Counter MVP", "storage.map"]
    "map state"
  expectErrorContains
    (ProofForge.Backend.Move.Sui.renderPackage u32StateModule)
    #["Sui Counter MVP", "u64"]
    "non-u64 state"
  expectErrorContains
    (ProofForge.Backend.Move.Sui.renderPackage crosscallModule)
    #["Sui Counter MVP", "crosscall.invoke"]
    "crosscall capability"

  IO.println "sui-diagnostics: ok"
  return 0

end ProofForge.Tests.SuiDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.SuiDiagnostics.main
