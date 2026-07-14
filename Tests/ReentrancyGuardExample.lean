import Examples.Product.ReentrancyGuard
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.ReentrancyGuardExample

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def capabilityPlan (profile : TargetProfile)
    (bundle : ProofForge.IR.Canonical.CanonicalBundle) : IO CapabilityPlan := do
  match requireCapabilityPlan profile {
      targetId := profile.id
      calls := bundle.contract.contract.requirements
    } with
  | .ok plan => pure plan
  | .error error =>
      throw <| IO.userError s!"ReentrancyGuard {profile.id} capability plan: {error.render}"

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "acquire" => some "a7134f73"
      | "release" => some "86d1a69f"
      | "locked" => some "cf309012"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let interface := { checked.contract.interface with entrypoints }
  match ProofForge.IR.Canonical.validateCanonical { checked.contract with interface } with
  | .ok result => pure result
  | .error error =>
      throw <| IO.userError s!"ReentrancyGuard EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let product := Examples.Product.ReentrancyGuard.contract
  require (product.name == "ReentrancyGuard") "ReentrancyGuard authored identity drift"
  require (product.state.map (·.name) == #["lock"])
    "ReentrancyGuard authored state drift"
  require (product.entrypoints.map (·.name) == #["acquire", "release", "locked"])
    "ReentrancyGuard authored entrypoint drift"

  let bundle <- match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored product with
    | .ok bundle => pure bundle
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard normalization failed: {repr error}"
  let operations := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)
  require (operations.any fun operation => match operation with
      | .pure (.compare .eq _ _) => true
      | _ => false)
    "Product ReentrancyGuard Core lost its acquire guard"
  require (operations.any fun operation => match operation with
      | .pure (.compare .ne _ _) => true
      | _ => false)
    "Product ReentrancyGuard Core lost its release guard"
  require ((operations.filter fun operation => match operation with
      | .storageStore _ _ => true
      | _ => false).size >= 2)
    "Product ReentrancyGuard Core lost its lock transitions"

  let evmCapabilities <- capabilityPlan evm bundle
  let evmChecked <- withEvmSelectors bundle.contract
  let evmPlan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore
      evmChecked evmCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard EVM plan failed: {error.message}"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan evmPlan with
  | .ok yul =>
      require (yul.contains "revert" && yul.contains "sload" && yul.contains "sstore")
        "ReentrancyGuard EVM plan lost guards or lock transitions"
  | .error error =>
      throw <| IO.userError s!"ReentrancyGuard EVM render failed: {error.message}"

  let solanaCapabilities <- capabilityPlan solanaSbpfAsm bundle
  let solanaPlan <- match ProofForge.Backend.Solana.Plan.Core.buildFromCore
      bundle.contract solanaCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard Solana plan failed: {error.message}"
  let package <- match ProofForge.Backend.Solana.Package.renderPackageFromPlan
      "reentrancyguard" solanaPlan with
    | .ok package => pure package
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard Solana package failed: {error.message}"
  let some assembly := package.files.find? (·.path == package.asmPath)
    | throw <| IO.userError "ReentrancyGuard Solana package has no assembly"
  require (assembly.contents.contains "assert_fail" && assembly.contents.contains "stxdw [r1+96]")
    "ReentrancyGuard Solana assembly lost guards or lock transitions"

  let nearCapabilities <- capabilityPlan wasmNear bundle
  let nearPlan <- match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore
      bundle.contract nearCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard NEAR plan failed: {error.message}"
  require (nearPlan.functions.size == 3 && nearPlan.layout.scalars.size == 1)
    "ReentrancyGuard NEAR plan lost functions or lock state"
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan nearPlan with
  | .ok wasmModule =>
      require (wasmModule.funcs.any fun function => function.name == "release")
        "ReentrancyGuard NEAR module lost release"
  | .error error =>
      throw <| IO.userError s!"ReentrancyGuard NEAR lowering failed: {error.message}"

  let sorobanCapabilities <- capabilityPlan wasmStellarSoroban bundle
  let sorobanPlan <- match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore
      bundle.contract sorobanCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ReentrancyGuard Soroban plan failed: {error.message}"
  match ProofForge.Backend.WasmHost.ModulePlan.lowerFromPlan sorobanPlan with
  | .ok wasmModule =>
      require (wasmModule.funcs.any fun function => function.name == "acquire")
        "ReentrancyGuard Soroban module lost acquire"
  | .error error =>
      throw <| IO.userError s!"ReentrancyGuard Soroban lowering failed: {error.message}"
  IO.println "reentrancy-guard-example: ok"

end ProofForge.Tests.ReentrancyGuardExample

def main : IO Unit :=
  ProofForge.Tests.ReentrancyGuardExample.main
