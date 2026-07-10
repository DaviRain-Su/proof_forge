/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Target.Plan
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmHost.Capabilities

open ProofForge.Backend.WasmHost.Diagnostics

/-! Capability and target-plan gates for the canonical wasm-near EmitWat backend. -/

/-! EmitWat supports the same capability surface as the `wasmNear` target profile,
    plus `controlConditional` and `controlBoundedLoop` (if/else + boundedFor are
    lowered natively in WAT). This set is intentionally kept in sync with the
    `wasmNear` profile so that the target-adapter capability gate and EmitWat's
    own gate reject the same shapes. Aggregate entrypoint params (structs/arrays)
    and cross-contract calls are enabled for EmitWat via Promise lowering even
    though wasm-near Rust sourcegen v0 still rejects them. -/
def emitWatCapabilities : ProofForge.Target.CapabilitySet :=
  (ProofForge.Target.wasmNear.capabilities.push .crosscallInvoke).push .nearPromise

def checkCapabilities (mod : ProofForge.IR.Module) : Except EmitError Unit :=
  mod.capabilities.foldlM (fun _ c =>
    if emitWatCapabilities.contains c then .ok ()
    else .error { message := s!"EmitWat: capability `{c.id}` is not supported by the EmitWat backend" }) ()

/-- EmitWat serves the Wasm-host family (NEAR, Soroban, CosmWasm). Plans must
name one of those registered host targets (PF-P0-04: do not force NEAR). -/
def checkTargetPlan (plan : ProofForge.Target.CapabilityPlan) : Except EmitError Unit :=
  if plan.targetId == ProofForge.Target.wasmNear.id ||
     plan.targetId == ProofForge.Target.wasmStellarSoroban.id ||
     plan.targetId == ProofForge.Target.wasmCosmWasm.id then
    .ok ()
  else
    .error {
      message :=
        s!"EmitWat plan requires a Wasm-host target (wasm-near | wasm-stellar-soroban | wasm-cosmwasm), got `{plan.targetId}`"
    }

end ProofForge.Backend.WasmHost.Capabilities
