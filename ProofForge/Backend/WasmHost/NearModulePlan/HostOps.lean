import ProofForge.IR.Core
import ProofForge.IR.Core.HostOp
import ProofForge.Target.HostOpRegistry
import ProofForge.Target.Capability

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
  deriving Repr, BEq

instance : Inhabited NearOpPlan := ⟨.promiseCreate⟩
instance : Inhabited (HostOpHandler NearOpPlan) := ⟨{ targetId := "", id := { namespace_ := "", name := "", version := { major := 0, minor := 0, patch := 0 } }, lower := #[] }⟩
/-- The exact `near.promise.create@1.0.0` HostOpId. -/
def promiseCreateId : HostOpId := {
  namespace_ := "near.promise",
  name := "create",
  version := { major := 1, minor := 0, patch := 0 }
}

def promiseResultU64Id : HostOpId := {
  namespace_ := "near.promise",
  name := "result_u64",
  version := { major := 1, minor := 0, patch := 0 }
}

def promiseResultsCountId : HostOpId := ProofForge.IR.Core.HostOp.nearPromiseResultsCountSig.id
def promiseResultStatusId : HostOpId := ProofForge.IR.Core.HostOp.nearPromiseResultStatusSig.id

/-- A registry with only the `near.promise.create@1.0.0` handler. -/
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
    targetId := "wasm-near", id := promiseResultsCountId,
    lower := #[NearOpPlan.promiseResultsCount] }
  HostOpRegistry.register registry {
    targetId := "wasm-near", id := promiseResultStatusId,
    lower := #[NearOpPlan.promiseResultStatus] }

/-- Check whether a host-op ID has a handler for `wasm-near`. -/
def hasNearHandler (id : HostOpId) : Bool :=
  match nearPromiseRegistry with
  | Except.ok reg => HostOpRegistry.hasHandler reg "wasm-near" id
  | Except.error _ => false

/-- Check whether a host-op ID has a handler for a given target.
EVM and Solana have no handlers; returns false (missingHostOpHandler). -/
def hasHandlerFor (targetId : String) (id : HostOpId) : Bool :=
  match targetId with
  | "wasm-near" => hasNearHandler id
  | _ => false

end ProofForge.Backend.WasmHost.NearModulePlan.HostOps
