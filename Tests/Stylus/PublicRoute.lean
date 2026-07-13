import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Cli.TargetDriver
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.NearCrosscallProbe
import ProofForge.Contract.Spec
import ProofForge.Target.BackendRegistry

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  let some profile := find? "wasm-arbitrum-stylus"
    | throw <| IO.userError "Stylus target is not registered"
  require (profile.family == .wasmHost) "Stylus must be classified as wasmHost"
  require (profile.support.maturity == .research) "Stylus must remain research"
  require (profile.support.allowsInput .contractSource) "Stylus must accept contract_source"
  require (profile.support.allowsCommand .build) "Stylus must advertise build"
  require (!profile.support.outputStages.contains .finalDeployable)
    "Stylus must not advertise final deployability before direct-Wasm evidence"
  require (!isPrimaryTriad profile.id) "Stylus must not enter the primary triad"
  require (ProofForge.Cli.findCliDriver? profile.id).isSome "Stylus CLI driver is missing"
  let tokenRoute := ProofForge.Cli.stylusResolveBuild {
    input? := some "Examples/Product/FungibleToken.lean", token := true }
  match tokenRoute with
  | .ok route =>
      require (route.nativeOp? == some .stylusContractSource)
        "Stylus token did not select the renderer-neutral contract-source compiler"
  | .error error => throw <| IO.userError s!"Stylus token route was rejected: {error}"
  match ProofForge.Cli.stylusResolveBuild {
      input? := some "Examples/Product/FungibleToken.lean", nft := true } with
  | .ok _ => throw <| IO.userError "Stylus NFT route was accepted before implementation"
  | .error _ => pure ()
  let counter := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  match runStrictCanonicalTargetGate profile.id counter with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"Stylus Counter strict gate failed: {error}"
  let promise := ContractSpec.fromIR ProofForge.IR.Examples.NearCrosscallProbe.module
  match runStrictCanonicalTargetGate profile.id promise with
  | .ok () => throw <| IO.userError "Stylus accepted NEAR Promise operations"
  | .error error => do
      require (error.contains "near.promise" || error.contains "NEAR")
        s!"Stylus Promise rejection was not named: {error}"
  IO.println "stylus-public-route: ok"
