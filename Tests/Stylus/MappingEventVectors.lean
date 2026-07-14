import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize

open ProofForge.Backend.Stylus
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def mapModule : ProofForge.IR.Module := {
  name := "StylusMapProbe"
  state := #[
    { id := "values", kind := .map .u64 64, type := .u64 },
    { id := "wide", kind := .map .address 64, type := .u128 }
  ]
  eventAbiWords := #[
    { eventName := "Transfer", fieldName := "value", abiWord := "uint256" },
    { eventName := "Approval", fieldName := "value", abiWord := "uint256" }
  ]
  entrypoints := #[
    { name := "set", selector? := some "1ab06ee5", params := #[
        ("key", .u64), ("value", .u64)]
      body := #[
        .effect (.storagePathWrite "values" #[.mapKey (.local "key")] (.local "value")),
        .effect (.eventEmitIndexed "ValueSet" #[("key", .local "key")]
          #[("value", .local "value")])
      ] },
    { name := "get", selector? := some "9507d39a", mutability := .view,
      params := #[("key", .u64)], returns := .u64
      body := #[.return (.effect (.storagePathRead "values" #[.mapKey (.local "key")]))] },
    { name := "setWide", selector? := some "aabbcc01", params := #[
        ("key", .address), ("value", .u128)]
      body := #[.effect (.storagePathWrite "wide" #[.mapKey (.local "key")] (.local "value"))] },
    { name := "getWide", selector? := some "aabbcc02", mutability := .view,
      params := #[("key", .address)], returns := .u128
      body := #[.return (.effect (.storagePathRead "wide" #[.mapKey (.local "key")]))] },
    { name := "emitTransfer", selector? := some "aabbcc03", params := #[
        ("from", .address), ("to", .address), ("value", .u128)]
      body := #[.effect (.eventEmitIndexed "Transfer"
        #[("from", .local "from"), ("to", .local "to")] #[("value", .local "value")])] },
    { name := "emitApproval", selector? := some "aabbcc04", params := #[
        ("owner", .address), ("spender", .address), ("value", .u128)]
      body := #[.effect (.eventEmitIndexed "Approval"
        #[("owner", .local "owner"), ("spender", .local "spender")]
        #[("value", .local "value")])] }
  ]
}

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR mapModule
  let bundle <- match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"normalizeContractSpec failed: {repr error}"
  let capabilityPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-arbitrum-stylus", calls := bundle.contract.contract.requirements }
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract capabilityPlan with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"buildFromCore failed: {error.message}"
  require (plan.storage.words.size == 2) "map plan must own both base storage words"
  require (plan.functions.size == 6) "map plan must retain map and standard event methods"
  let some transfer := plan.events.find? (fun event => event.id == "Transfer")
    | throw <| IO.userError "Transfer event plan missing"
  let some approval := plan.events.find? (fun event => event.id == "Approval")
    | throw <| IO.userError "Approval event plan missing"
  require (transfer.canonicalSignature == "Transfer(address,address,uint256)")
    "Transfer ABI override was not preserved"
  require (approval.canonicalSignature == "Approval(address,address,uint256)")
    "Approval ABI override was not preserved"
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"direct map lowering failed: {error.message}"
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"Rust map rendering failed: {error.message}"
  IO.FS.createDirAll "build/stylus/mapping-events"
  IO.FS.writeFile "build/stylus/mapping-events/map.wat"
    (ProofForge.Compiler.Wasm.Printer.render direct)
  let cratePath := System.FilePath.mk "build/stylus/mapping-events/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.message
  IO.println "stylus-mapping-events: ok"
