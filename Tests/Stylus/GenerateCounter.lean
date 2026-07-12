import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

def main (args : List String) : IO UInt32 := do
  let output <- match args with
    | [path] => pure (System.FilePath.mk path)
    | _ => throw <| IO.userError "usage: GenerateCounter <output-directory>"
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let .ok bundle := ProofForge.IR.Legacy.Adapter.adaptLegacy spec
    | throw <| IO.userError "failed to adapt canonical Counter"
  let .ok plan := ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus"
      calls := bundle.contract.contract.requirements
    }
    | throw <| IO.userError "failed to build Stylus Counter plan"
  let .ok crate := ProofForge.Backend.Stylus.RustSdk.renderCrate plan
    | throw <| IO.userError "failed to render Stylus Counter crate"
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate output with
  | .ok () => return 0
  | .error error => throw <| IO.userError error.message
