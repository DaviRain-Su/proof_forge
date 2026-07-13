import ProofForge.IR.Core
import ProofForge.IR.Core.HostOp
import ProofForge.Target.HostOpRegistry
import ProofForge.Target.Capability
import ProofForge.Target.HostOps.Near

/-! # NEAR HostOp Plan Handlers

Target-specific plan operations for typed host calls on the `wasm-near`
target. Each handler maps a `HostOpId` to `NearOpPlan` operations that the
plan builder can consume. The handler does not emit `Wasm.Insn`; it produces
plan-level operations consumed by `NearModulePlan.Core`.
-/

namespace ProofForge.Backend.WasmHost.NearModulePlan.HostOps

open ProofForge.IR.Core
open ProofForge.Target

/-- Plan-level operations for NEAR host calls. These are NOT `Wasm.Insn`;
they are consumed by the plan builder to set surface flags and import names. -/
inductive NearOpPlan
  | promiseCreate
  | promiseResultsCount
  | promiseResultStatus
  | promiseResultU64
  | promiseResultU128
  | storageUsage
  | promiseTransfer
  deriving Repr, BEq

instance : Inhabited NearOpPlan := ⟨.promiseCreate⟩
instance : Inhabited (HostOpHandler NearOpPlan) := ⟨{ targetId := "", id := { namespace_ := "", name := "", version := { major := 0, minor := 0, patch := 0 } }, lower := #[] }⟩
/-- The exact `near.promise.create@1.0.0` HostOpId. -/
def promiseCreateId : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseCreateSig.id

def promiseResultU64Id : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseResultU64Sig.id

def promiseResultU128Id : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseResultU128Sig.id

def promiseResultsCountId : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseResultsCountSig.id
def promiseResultStatusId : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseResultStatusSig.id
def storageUsageId : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.storageUsageSig.id
def promiseTransferId : ProofForge.Target.HostOpId := ProofForge.Target.HostOps.Near.promiseTransferSig.id

/-- Registry for the supported `near.promise` host operations. -/
def nearPromiseRegistry : Except String (HostOpRegistry NearOpPlan) :=
  do
  let registry ← HostOpRegistry.register (HostOpRegistry.empty NearOpPlan) {
    targetId := "wasm-near",
    id := promiseCreateId,
    lower := #[NearOpPlan.promiseCreate]
  }
  let registry ← HostOpRegistry.register registry {
    targetId := "wasm-near",
    id := promiseResultU64Id,
    lower := #[NearOpPlan.promiseResultU64]
  }
  let registry ← HostOpRegistry.register registry {
    targetId := "wasm-near",
    id := promiseResultU128Id,
    lower := #[NearOpPlan.promiseResultU128]
  }
  let registry ← HostOpRegistry.register registry {
    targetId := "wasm-near", id := promiseResultsCountId,
    lower := #[NearOpPlan.promiseResultsCount] }
  let registry ← HostOpRegistry.register registry {
    targetId := "wasm-near", id := promiseResultStatusId,
    lower := #[NearOpPlan.promiseResultStatus] }
  let registry ← HostOpRegistry.register registry {
    targetId := "wasm-near", id := storageUsageId,
    lower := #[NearOpPlan.storageUsage] }
  HostOpRegistry.register registry {
    targetId := "wasm-near", id := promiseTransferId,
    lower := #[NearOpPlan.promiseTransfer] }

/-- Check whether a host-op ID has a handler for `wasm-near`. -/
def hasNearHandler (id : ProofForge.Target.HostOpId) : Bool :=
  match nearPromiseRegistry with
  | Except.ok reg => HostOpRegistry.hasHandler reg "wasm-near" id
  | Except.error _ => false

/-- Check whether a host-op ID has a handler for a given target.
EVM and Solana have no handlers; returns false (missingHostOpHandler). -/
def hasHandlerFor (targetId : String) (id : ProofForge.Target.HostOpId) : Bool :=
  match targetId with
  | "wasm-near" => hasNearHandler id
  | _ => false

end ProofForge.Backend.WasmHost.NearModulePlan.HostOps
