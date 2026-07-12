import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Target.HostBridge

/-!
# Neutral Wasm-Host Module Plan

Extraction layer that decouples the Wasm-host plan from NEAR-specific
naming. The existing `NearModulePlan` types (layout, value, op, block,
function, lowerCtxSeed) are already implementation-neutral — they don't
encode NEAR-specific semantics in their structure, only in the builder
that fills them.

B1 extracts a neutral `WasmHostModulePlan` type by wrapping
`NearModulePlan` with a `HostBridgePlan` discriminator. NEAR remains
the only populated bridge; Soroban and CosmWasm are added in B3+.

The `ModulePlan.Core.buildFromCore` function delegates to the existing
`NearModulePlan.Core.buildFromCore` for `wasm-near` and rejects other
targets until their builders are implemented (B3+).
-/

namespace ProofForge.Backend.WasmHost.ModulePlan

/-- Wasm-host bridge kind. -/
inductive WasmHostKind where
  | near
  | soroban
  | cosmWasm
  deriving BEq, Repr

/-- Host bridge plan: identifies the target chain's host interface model. -/
structure HostBridgePlan where
  kind : WasmHostKind
  storageModel : String
  authModel : String
  crosscallModel : String
  deriving Repr, BEq

/-- The neutral Wasm-host module plan. Reuses NearModulePlan fields
because they are already implementation-neutral. The `bridge` field
discriminates the target-specific host interface. -/
structure WasmHostModulePlan where
  moduleName : String
  targetId : String
  artifactKind : String
  irVersion : String
  surface : ProofForge.Backend.WasmHost.Plan.ModulePlan
  entrypointAbis : Array NearAbiPlan.EntrypointPlan
  layout : NearModulePlan.NearLayoutPlan
  functions : Array NearModulePlan.NearFunctionPlan := #[]
  lowerCtxSeed : NearModulePlan.NearLowerCtxSeed
  bridge : HostBridgePlan
  deriving Repr

/-- NEAR bridge plan constant. -/
def nearBridge : HostBridgePlan := {
  kind := .near,
  storageModel := "storage_read/storage_write",
  authModel := "predecessor_account_id",
  crosscallModel := "promise_create"
}

/-- Soroban bridge plan constant (for future B3). -/
def sorobanBridge : HostBridgePlan := {
  kind := .soroban,
  storageModel := "_get/_put",
  authModel := "require_auth_for_args",
  crosscallModel := "invoke_contract"
}

/-- CosmWasm bridge plan constant (for future CosmWasm promotion). -/
def cosmWasmBridge : HostBridgePlan := {
  kind := .cosmWasm,
  storageModel := "db_read/db_write",
  authModel := "none",
  crosscallModel := "execute_msg"
}

/-- Resolve a bridge plan from a target ID. -/
def bridgeForTarget (targetId : String) : Except String HostBridgePlan :=
  match targetId with
  | "wasm-near" => .ok nearBridge
  | "wasm-stellar-soroban" => .ok sorobanBridge
  | "wasm-cosmwasm" => .ok cosmWasmBridge
  | _ => .error s!"no Wasm-host bridge for target `{targetId}`"

namespace Core

/-- Build a neutral Wasm-host module plan from a checked canonical contract.

For `wasm-near`: delegates to the existing `NearModulePlan.Core.buildFromCore`
and wraps the result with `nearBridge`.

For other targets: fails closed until their builders are implemented
(B3 for Soroban, future tasks for CosmWasm). -/
def buildFromCore (checked : ProofForge.IR.Canonical.CheckedCanonicalContract)
    (capPlan : ProofForge.Target.CapabilityPlan) :
    Except ProofForge.Backend.WasmHost.Plan.PlanError WasmHostModulePlan := do
  let bridge ← match bridgeForTarget capPlan.targetId with
  | .ok b => pure b
  | .error e => .error { message := e }
  match bridge.kind with
  | .near =>
    let nearPlan ← NearModulePlan.Core.buildFromCore checked capPlan
    pure {
      moduleName := nearPlan.moduleName
      targetId := nearPlan.targetId
      artifactKind := nearPlan.artifactKind
      irVersion := nearPlan.irVersion
      surface := nearPlan.surface
      entrypointAbis := nearPlan.entrypointAbis
      layout := nearPlan.layout
      functions := nearPlan.functions
      lowerCtxSeed := nearPlan.lowerCtxSeed
      bridge := bridge
    }
  | .soroban =>
    .error { message := "Soroban buildFromCore is not yet implemented (B3)" }
  | .cosmWasm =>
    .error { message := "CosmWasm buildFromCore is not yet implemented" }

end Core

end ProofForge.Backend.WasmHost.ModulePlan