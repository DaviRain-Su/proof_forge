import Examples.Product.ArrayExample
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.ArrayExample

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
      throw <| IO.userError s!"ArrayExample {profile.id} capability plan: {error.render}"

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "sizeOf3" => some "8c471d33"
      | "getElem" => some "ff170768"
      | "sumOf3" => some "6d666075"
      | "outOfBounds" => some "c1ea953e"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let interface := { checked.contract.interface with entrypoints }
  match ProofForge.IR.Canonical.validateCanonical { checked.contract with interface } with
  | .ok result => pure result
  | .error error =>
      throw <| IO.userError s!"ArrayExample EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let product := Examples.Product.ArrayExample.contract
  require (product.name == "ArrayExample") "ArrayExample authored identity drift"
  require product.state.isEmpty "ArrayExample unexpectedly gained persistent state"
  require (product.entrypoints.map (·.name) ==
      #["sizeOf3", "getElem", "sumOf3", "outOfBounds"])
    "ArrayExample authored entrypoint drift"

  let bundle <- match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored product with
    | .ok bundle => pure bundle
    | .error error =>
        throw <| IO.userError s!"ArrayExample normalization failed: {repr error}"
  let operations := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)
  require ((operations.filter fun operation => match operation with
      | .memoryAlloc .u64 _ => true
      | _ => false).size == 3)
    "Product ArrayExample Core must allocate exactly three local arrays"
  require ((operations.filter fun operation => match operation with
      | .memoryStore _ _ _ => true
      | _ => false).size == 9)
    "Product ArrayExample Core must initialize all nine array elements"
  require ((operations.filter fun operation => match operation with
      | .memoryLoad _ _ => true
      | _ => false).size == 5)
    "Product ArrayExample Core must retain all five array reads"

  let evmCapabilities <- capabilityPlan evm bundle
  let evmChecked <- withEvmSelectors bundle.contract
  let evmPlan <- match ProofForge.Backend.Evm.Plan.Core.buildFromCore
      evmChecked evmCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ArrayExample EVM plan failed: {error.message}"
  require (evmPlan.hasHelper .memoryArrayNew && evmPlan.hasHelper .memoryArrayGet)
    "ArrayExample EVM plan did not close over local array helpers"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan evmPlan with
  | .ok yul =>
      require (yul.contains "__proof_forge_memory_array_new" &&
          yul.contains "__proof_forge_memory_array_get")
        "ArrayExample EVM plan lost local array allocation or access"
  | .error error =>
      throw <| IO.userError s!"ArrayExample EVM render failed: {error.message}"

  let solanaCapabilities <- capabilityPlan solanaSbpfAsm bundle
  let solanaPlan <- match ProofForge.Backend.Solana.Plan.Core.buildFromCore
      bundle.contract solanaCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ArrayExample Solana plan failed: {error.message}"
  let package <- match ProofForge.Backend.Solana.Package.renderPackageFromPlan
      "arrayexample" solanaPlan with
    | .ok package => pure package
    | .error error =>
        throw <| IO.userError s!"ArrayExample Solana package failed: {error.message}"
  let some assembly := package.files.find? (·.path == package.asmPath)
    | throw <| IO.userError "ArrayExample Solana package has no assembly"
  require (assembly.contents.contains "array.get: compute element address")
    "ArrayExample Solana assembly lost local array access"

  let nearCapabilities <- capabilityPlan wasmNear bundle
  let nearPlan <- match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore
      bundle.contract nearCapabilities with
    | .ok plan => pure plan
    | .error error =>
        throw <| IO.userError s!"ArrayExample NEAR plan failed: {error.message}"
  require (nearPlan.functions.size == 4 && nearPlan.layout.scalars.isEmpty)
    "ArrayExample NEAR plan lost functions or invented persistent state"
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan nearPlan with
  | .ok wasmModule =>
      require (wasmModule.funcs.any fun function => function.name == "sumOf3")
        "ArrayExample NEAR module lost sumOf3"
      require (wasmModule.funcs.any fun function => function.name == "outOfBounds")
        "ArrayExample NEAR module lost outOfBounds"
  | .error error =>
      throw <| IO.userError s!"ArrayExample NEAR lowering failed: {error.message}"
  IO.println "array-example: ok"

end ProofForge.Tests.ArrayExample

def main : IO Unit :=
  ProofForge.Tests.ArrayExample.main
