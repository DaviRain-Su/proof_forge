import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Legacy.Adapter
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"adaptLegacy failed: {repr error}"
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus"
    calls := bundle.contract.contract.requirements
  }
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract capabilityPlan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"buildFromCore failed: {error.message}"
  require (plan.moduleName == "ValueVault") "canonical ValueVault module identity changed"
  require (plan.functions.size == 7) "canonical ValueVault must retain all seven functions"
  require (plan.storage.words.size == 6) "canonical ValueVault must retain all six state words"
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"direct lowering failed: {error.message}"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"Rust rendering failed: {error.message}"
  IO.FS.createDirAll "build/stylus/value-vault-canonical"
  IO.FS.writeFile "build/stylus/value-vault-canonical/value-vault.wat"
    (ProofForge.Compiler.Wasm.Printer.render direct)
  let cratePath := System.FilePath.mk "build/stylus/value-vault-canonical/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.message
  IO.println "stylus-value-vault-canonical: ok"
