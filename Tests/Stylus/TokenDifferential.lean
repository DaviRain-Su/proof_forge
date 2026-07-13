import Examples.Product.FungibleToken
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Token
import ProofForge.Backend.Stylus.TokenSemantics
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.Package
import ProofForge.Compiler.Wasm.Printer
import ProofForge.IR.Legacy.Adapter

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let source := ProofForge.Backend.Stylus.Token.specFor Examples.Product.FungibleToken.spec
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy source with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"token canonicalization failed: {repr error}"
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements } with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"token Stylus plan failed: {error.message}"
  require (plan.functions.any fun function => function.id == "balanceOf") "balanceOf plan missing"
  require (plan.functions.any fun function => function.id == "allowance") "allowance plan missing"
  require (plan.functions.any fun function => function.id == "transfer") "transfer plan missing"
  require (plan.functions.any fun function => function.id == "approve") "approve plan missing"
  require (plan.functions.any fun function => function.id == "transferFrom") "transferFrom plan missing"
  let some transferAbi := plan.abi.methods.find? (fun method => method.name == "transfer")
    | throw <| IO.userError "transfer ABI plan missing"
  let some approveAbi := plan.abi.methods.find? (fun method => method.name == "approve")
    | throw <| IO.userError "approve ABI plan missing"
  require (transferAbi.canonicalSignature == "transfer(address,uint256)")
    "transfer canonical ABI override missing"
  require (approveAbi.canonicalSignature == "approve(address,uint256)")
    "approve canonical ABI override missing"
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"token direct lowering failed: {error.message}"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"token Rust rendering failed: {error.message}"
  IO.FS.createDirAll "build/stylus/token"
  IO.FS.writeFile "build/stylus/token/token.wat"
    (ProofForge.Compiler.Wasm.Printer.render direct)
  IO.FS.writeFile "build/stylus/token/abstract-trace.json"
    (ProofForge.Backend.Stylus.TokenSemantics.normalizedScenarioJson ++ "\n")
  let abstractTrace := ProofForge.Backend.Stylus.TokenSemantics.normalizedScenario
  require (abstractTrace.size == 5) "abstract token scenario step count changed"
  let some spent := abstractTrace[3]?
    | throw <| IO.userError "abstract transferFrom step missing"
  let some rejected := abstractTrace[4]?
    | throw <| IO.userError "abstract transferFrom failure step missing"
  require (rejected.status == 1 && rejected.state == spent.state)
    "abstract failed transferFrom did not roll back state"
  let cratePath := System.FilePath.mk "build/stylus/token/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.message
  IO.println "stylus-token-differential: canonical-plan/direct/rust ok"
