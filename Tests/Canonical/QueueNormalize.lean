import ProofForge.Frontend.Surface
import Examples.Product.Canonical.BoundedQueue
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core

/-! Task 16 structural normalization and target materialization for bounded queues. -/

open ProofForge.Frontend.Surface
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def testQueue := Examples.Product.Canonical.BoundedQueue.queue
def queueContract := Examples.Product.Canonical.BoundedQueue.contract

def main : IO Unit := do
  IO.FS.createDirAll "build/canonical/queue/evm"
  IO.FS.createDirAll "build/canonical/queue/solana"
  IO.FS.createDirAll "build/canonical/queue/near"
  let expanded := testQueue.expand
  require (expanded.size == 3) "Queue expansion size"
  require (expanded.all (fun state => state.generated)) "Queue expansion provenance"
  match expanded[0]!.kind with
  | .fixedArray .u64 3 => pure ()
  | shape => throw <| IO.userError s!"wrong Queue items shape: {repr shape}"
  match SurfaceQueueDecl.validate { id := 1, elementType := .u64, capacity := 0 } with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "zero-capacity Queue accepted"

  let bundle ← match normalizeSurface queueContract with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"Queue normalization failed: {repr e}"
  require (bundle.contract.contract.module.state.size == 3) "Core Queue state count"
  let enqueue ← match bundle.contract.contract.module.functions[1]? with
    | some function => pure function
    | none => throw <| IO.userError "Queue enqueue function missing"
  let dequeue ← match bundle.contract.contract.module.functions[2]? with
    | some function => pure function
    | none => throw <| IO.userError "Queue dequeue function missing"
  let hasIndexWrite := enqueue.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageStore { path := #[.index _], .. } _ => true
    | _ => false
  let hasIndexRead := dequeue.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with
    | .storageLoad { path := #[.index _], .. } => true
    | _ => false
  require hasIndexWrite "Queue enqueue emitted no Core indexed write"
  require hasIndexRead "Queue dequeue emitted no Core indexed read"
  require (enqueue.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with | .assert _ error => error.id.value == 0 | _ => false)
    "QueueFull identity was not preserved"
  require (dequeue.blocks.any fun block => block.instructions.any fun instruction =>
    match instruction.op with | .assert _ error => error.id.value == 1 | _ => false)
    "QueueEmpty identity was not preserved"

  let evmCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "evm", calls := bundle.contract.contract.requirements, metadata := #[] }
  let evmPlan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract evmCapabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"EVM rejected Queue Core: {e.message}"
  match ProofForge.Backend.Evm.IR.renderCanonicalModuleWithPlan evmPlan with
  | .ok yul => IO.FS.writeFile "build/canonical/queue/evm/contract.yul" yul
  | .error e => throw <| IO.userError s!"EVM Queue lowering failed: {e.message}"

  let solanaCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "solana-sbpf-asm", calls := bundle.contract.contract.requirements, metadata := #[] }
  let solanaPlan ← match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract solanaCapabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"Solana rejected Queue Core: {e.message}"
  match ProofForge.Backend.Solana.Plan.lowerFromPlan solanaPlan with
  | .ok nodes =>
      IO.FS.writeFile "build/canonical/queue/solana/contract.s"
        (ProofForge.Backend.Solana.Asm.renderNodes nodes)
  | .error e => throw <| IO.userError s!"Solana Queue lowering failed: {e.message}"

  let nearCapabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near", calls := bundle.contract.contract.requirements, metadata := #[] }
  let nearPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract nearCapabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"NEAR rejected Queue Core: {e.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan nearPlan with
  | .ok module =>
      IO.FS.writeFile "build/canonical/queue/near/contract.wat"
        (ProofForge.Compiler.Wasm.Printer.render module)
  | .error e => throw <| IO.userError s!"NEAR Queue lowering failed: {e.message}"

  let spoofed : SurfaceContract := { queueContract with
    state := #[{ name := "$surface.queue.0.items", kind := .fixedArray .u64 3 }] }
  match normalizeSurface spoofed with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "user-authored reserved Queue state accepted"
  let collision : SurfaceContract := { queueContract with state := testQueue.expand ++ testQueue.expand }
  match normalizeSurface collision with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "generated Queue name collision accepted"
  IO.println "queue-normalize: ok"
