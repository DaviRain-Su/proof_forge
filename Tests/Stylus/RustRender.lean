import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def readGolden (path : String) : IO String :=
  IO.FS.readFile path

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus"
      calls := bundle.contract.contract.requirements
    } with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"renderCrate failed: {e.message}"
  require (crate.files.size == 2) "Counter Rust crate must contain exactly two files"
  let cargo <- match crate.find? "Cargo.toml" with
    | some value => pure value
    | none => throw <| IO.userError "Cargo.toml missing"
  let lib <- match crate.find? "src/lib.rs" with
    | some value => pure value
    | none => throw <| IO.userError "src/lib.rs missing"
  require (cargo == (← readGolden "Tests/fixtures/stylus/counter/Cargo.toml.golden"))
    "generated Cargo.toml differs from golden"
  let libGolden <- readGolden "Tests/fixtures/stylus/counter/src/lib.rs.golden"
  unless lib == libGolden do
    IO.eprintln "generated src/lib.rs:"
    IO.eprintln lib
    throw <| IO.userError "generated src/lib.rs differs from golden"
  let crateAgain <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"second render failed: {e.message}"
  require (crate == crateAgain) "Rust crate rendering is not deterministic"
  IO.println "stylus-rust-render: ok"
