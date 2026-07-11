import ProofForge.Frontend.Surface
import Examples.Product.Canonical.SetRegistry
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core

/-! Task 15 structural normalization tests for bounded Surface sets. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def testSet := Examples.Product.Canonical.SetRegistry.registry
def setContract := Examples.Product.Canonical.SetRegistry.contract

def evmDeclarationContext : ProofForge.IR.Module := {
  name := "SetRegistry"
  state := #[
    { id := testSet.membersName, kind := .map .u64 100, type := .bool },
    { id := testSet.cardinalityName, kind := .scalar, type := .u64 }]
  entrypoints := #[
    { name := "initialize", selector? := some "8129fc1c", body := #[] },
    { name := "insert", selector? := some "e1c7392a", params := #[("key", .u64)], body := #[] },
    { name := "remove", selector? := some "4cc82215", params := #[("key", .u64)], body := #[] },
    { name := "contains", selector? := some "5b4b73a9", mutability := .view,
      params := #[("key", .u64)], returns := .bool, body := #[] }]
}

def main : IO Unit := do
  IO.FS.createDirAll "build/canonical/set/evm"
  IO.FS.createDirAll "build/canonical/set/solana"
  IO.FS.createDirAll "build/canonical/set/near"
  let expanded := testSet.expand
  require (expanded.size == 2) "Set expansion size"
  require (expanded[0]!.name == testSet.membersName && expanded[0]!.generated) "members name/provenance"
  require (expanded[1]!.name == testSet.cardinalityName && expanded[1]!.generated) "cardinality name/provenance"
  match expanded[0]!.kind with
  | .map .u64 .bool (some 100) => pure ()
  | shape => throw <| IO.userError s!"wrong members shape: {repr shape}"
  match SurfaceSetDecl.validate { id := 1, elementType := .u64, capacity := 0 } with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "zero-capacity Set accepted"

  let bundle ← match normalizeSurface setContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"Set normalization failed: {repr e}"
  require (bundle.contract.contract.module.state.size == 2) "Core Set state count"
  let insert ← match bundle.contract.contract.module.functions[1]? with
    | some function => pure function
    | none => throw <| IO.userError "Set insert function missing"
  let hasMapRead := insert.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageLoad { path := #[.mapKey _], .. } => true
    | _ => false
  let hasMapWrite := insert.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageStore { path := #[.mapKey _], .. } _ => true
    | _ => false
  require hasMapRead "Set insert emitted no Core map read"
  require hasMapWrite "Set insert emitted no Core map write"
  require (insert.blocks.any fun block => match block.terminator with | .branch _ _ _ => true | _ => false)
    "Set insert emitted no idempotency branch"
  let evmCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "evm", calls := bundle.contract.contract.requirements, metadata := #[] }
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract evmCapabilities with
  | .ok plan =>
      match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan evmDeclarationContext plan with
      | .ok yul =>
          require (!yul.isEmpty) "EVM Set lowering emitted no Yul"
          IO.FS.writeFile "build/canonical/set/evm/contract.yul" yul
      | .error e => throw <| IO.userError s!"EVM Set lowering failed: {e.message}"
  | .error e => throw <| IO.userError s!"EVM rejected normalized Set Core: {e.message}"
  let solanaCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "solana-sbpf-asm", calls := bundle.contract.contract.requirements, metadata := #[] }
  let solanaPlan ← match ProofForge.Backend.Solana.Plan.Core.buildFromCore
      bundle.contract solanaCapabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"Solana rejected normalized Set Core: {e.message}"
  match ProofForge.Backend.Solana.Plan.lowerFromPlan solanaPlan with
  | .ok nodes =>
      require (!nodes.isEmpty) "Solana Set lowering emitted no assembly"
      IO.FS.writeFile "build/canonical/set/solana/contract.s"
        (ProofForge.Backend.Solana.Asm.renderNodes nodes)
  | .error e => throw <| IO.userError s!"Solana Set lowering failed: {e.message}"
  let nearCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near", calls := bundle.contract.contract.requirements, metadata := #[] }
  let nearPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore
      bundle.contract nearCapabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"NEAR rejected normalized Set Core: {e.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan nearPlan with
  | .ok module =>
      require (!module.funcs.isEmpty) "NEAR Set lowering emitted no functions"
      IO.FS.writeFile "build/canonical/set/near/contract.wat"
        (ProofForge.Compiler.Wasm.Printer.render module)
  | .error e => throw <| IO.userError s!"NEAR Set lowering failed: {e.message}"

  let spoofed : SurfaceContract := { setContract with
    state := #[{ name := "$surface.set.7.members", kind := .map .u64 .bool (some 1) }] }
  match normalizeSurface spoofed with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "user-authored reserved Set state accepted"
  let collision : SurfaceContract := { setContract with state := testSet.expand ++ testSet.expand }
  match normalizeSurface collision with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "generated Set name collision accepted"

  IO.println "set-normalize: ok"
