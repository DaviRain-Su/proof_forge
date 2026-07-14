import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Contract.Spec
import ProofForge.Target.InterfaceOps.Evm
import ProofForge.Backend.Evm.Plan.Core

open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.Contract

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def proxyModule (pattern : String) : ProofForge.IR.Module := {
  name := "EvmProxyExtension"
  state := #[]
  entrypoints := #[]
  proxyPattern? := some pattern
}

private def proxySpec (pattern : ProxyPattern) : ContractSpec := {
  ContractSpec.fromIR (proxyModule pattern.kind) with
  proxyPattern? := some pattern
}

private def capabilityPlan : ProofForge.Target.CapabilityPlan := {
  targetId := "evm"
  calls := #[]
}

def main : IO Unit := do
  let checked ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec (proxySpec .uups) with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"UUPS adaptation failed: {repr error}")
  let extension ← match checked.contract.interfaceExtensions.find?
      (·.id == ProofForge.Target.InterfaceOps.Evm.proxyPatternId) with
    | some extension => pure extension
    | none => throw (IO.userError "UUPS proxy extension missing")
  require (extension.subject == .contract && extension.args == #[.string "uups"])
    "UUPS proxy extension payload changed"
  require ((ProofForge.Compiler.checkInterfaceOpHandlers "evm" checked).isEmpty)
    "EVM rejected its proxy extension"
  require ((ProofForge.Compiler.checkInterfaceOpHandlers "wasm-near" checked).size == 1)
    "NEAR accepted the EVM proxy extension"
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capabilityPlan with
    | .ok plan => pure plan
    | .error error => throw (IO.userError s!"UUPS planning failed: {error.message}")
  require (plan.dispatch.default == .uupsProxy)
    "UUPS attachment did not select the EVM proxy dispatch plan"

  let transparent ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec (proxySpec .transparent) with
    | .ok bundle => pure bundle.contract
    | .error error => throw (IO.userError s!"transparent adaptation failed: {repr error}")
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore transparent capabilityPlan with
  | .error error =>
      require (error.message.contains "transparent proxy")
        "transparent proxy rejection lost its target-owned diagnostic"
  | .ok _ => throw (IO.userError "unimplemented transparent proxy was accepted")

  let mismatched : ContractSpec := {
    ContractSpec.fromIR (proxyModule "transparent") with
    proxyPattern? := some .uups
  }
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec mismatched with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "mismatched legacy proxy declarations were accepted")
  IO.println "evm-proxy-extension: ok"
