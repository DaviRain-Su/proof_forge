import Examples.Product.Ownable
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.OwnableExample

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def normalizeProduct : IO ProofForge.IR.Canonical.CanonicalBundle := do
  match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      Examples.Product.Ownable.contract with
  | .ok bundle => pure bundle
  | .error error => throw <| IO.userError s!"Ownable normalization failed: {repr error}"

def capabilityPlan (profile : TargetProfile)
    (bundle : ProofForge.IR.Canonical.CanonicalBundle) : IO CapabilityPlan := do
  match requireCapabilityPlan profile {
      targetId := profile.id
      calls := bundle.contract.contract.requirements
    } with
  | .ok plan => pure plan
  | .error error => throw <| IO.userError s!"Ownable {profile.id} capability plan: {error.render}"

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "init" => some "e1c7392a"
      | "owner" => some "8da5cb5b"
      | "transferOwnership" => some "f2fde38b"
      | "renounceOwnership" => some "715018a6"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let interface := { checked.contract.interface with entrypoints }
  match ProofForge.IR.Canonical.validateCanonical { checked.contract with interface } with
  | .ok result => pure result
  | .error error => throw <| IO.userError s!"Ownable EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let product := Examples.Product.Ownable.contract
  require (product.name == "Ownable") "Ownable authored identity drift"
  require (product.state.map (·.name) == #["owner", "initialized"])
    "Ownable authored state drift"
  require (product.entrypoints.map (·.name) ==
      #["init", "owner", "transferOwnership", "renounceOwnership"])
    "Ownable authored entrypoint drift"
  require (product.events.map (·.name) == #["OwnershipTransferred"])
    "Ownable authored event drift"

  let productBundle <- normalizeProduct
  let operations := productBundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)
  require (operations.any fun operation => match operation with
      | .contextRead .sender => true
      | _ => false)
    "Product Ownable Core lost portable caller context"
  require (operations.any fun operation => match operation with
      | .pure (.compare .eq _ _) => true
      | _ => false)
    "Product Ownable Core lost equality authorization"
  require (operations.any fun operation => match operation with
      | .pure (.compare .ne _ _) => true
      | _ => false)
    "Product Ownable Core lost zero-address rejection"

  let evmCapabilities <- capabilityPlan evm productBundle
  let evmChecked <- withEvmSelectors productBundle.contract
  let evmPlan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore evmChecked evmCapabilities with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"Ownable EVM plan failed: {error.message}"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan evmPlan with
  | .ok yul =>
      require (yul.contains "caller()" && yul.contains "revert")
        "Ownable EVM plan lost caller authorization"
  | .error error => throw <| IO.userError s!"Ownable EVM render failed: {error.message}"

  let solanaCapabilities <- capabilityPlan solanaSbpfAsm productBundle
  let solanaPlan <- match ProofForge.Backend.Solana.Plan.Core.buildFromCore
      productBundle.contract solanaCapabilities with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"Ownable Solana plan failed: {error.message}"
  require (solanaPlan.accounts.any fun account => account.name == "authority" && account.signer)
    "Ownable Solana plan lost its caller authority"
  let package <- match ProofForge.Backend.Solana.Package.renderPackageFromPlan
      "ownable" solanaPlan with
    | .ok package => pure package
    | .error error => throw <| IO.userError s!"Ownable Solana package failed: {error.message}"
  let some assembly := package.files.find? (·.path == package.asmPath)
    | throw <| IO.userError "Ownable Solana package has no assembly"
  require (assembly.contents.contains "assert" && assembly.contents.contains "authority")
    "Ownable Solana assembly lost authorization checks"

  let nearCapabilities <- capabilityPlan wasmNear productBundle
  let nearPlan <- match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore
      productBundle.contract nearCapabilities with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError s!"Ownable NEAR plan failed: {error.message}"
  require (nearPlan.functions.size == 4 && nearPlan.layout.scalars.size == 2)
    "Ownable NEAR plan lost functions or state"
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan nearPlan with
  | .ok wasmModule =>
      require (wasmModule.funcs.any fun function => function.name == "transferOwnership")
        "Ownable NEAR module lost transferOwnership"
  | .error error =>
      throw <| IO.userError s!"Ownable NEAR lowering failed: {error.message}"
  IO.println "ownable-example: ok"

end ProofForge.Tests.OwnableExample

def main : IO Unit :=
  ProofForge.Tests.OwnableExample.main
