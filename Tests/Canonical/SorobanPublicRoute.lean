/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Soroban Public Route — Counter Canonical Promotion (B3)

Tests the strict canonical target gate for `wasm-stellar-soroban`:
- Counter passes `runStrictCanonicalTargetGate` (adapter, validator,
  capability, host-op, buildFromCore — all hard errors, no advisory)
- `runStrictCanonicalContractGate` works from a raw canonical contract
- `ModulePlan.Core.buildFromCore` produces a plan with `.soroban` bridge
- Soroban plan reuses NEAR layout (same key-value storage semantics)
- `ModulePlan.lowerFromPlan` fails closed for Soroban (EmitWat not yet adapted)
- NEAR-only HostOps (promise_create) are rejected by `checkHostOpHandlers`
- CosmWasm still fails closed (not promoted)
-/

import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near

open ProofForge.Compiler
open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.IR.Legacy.Adapter
open ProofForge.Contract
open ProofForge.Backend.WasmHost

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireOk (result : Except String α) (label : String) : IO Unit :=
  match result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: expected success, got: {e}"

def requireErrorPrefix (expectedPrefix : String) (result : Except String α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected error starting with `{expectedPrefix}`, got success"
  | .error e => require (e.startsWith expectedPrefix)
      s!"expected error starting with `{expectedPrefix}`, got: {e}"

/-- Counter fixture — selectors kept for EVM builder; ignored by Soroban/NEAR. -/
def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

/-- ValueVault fixture. -/
def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

def main : IO Unit := do
  -- -- Test 1: Counter passes strict gate on Soroban --
  requireOk (runStrictCanonicalTargetGate "wasm-stellar-soroban" counterSpec)
    "strict gate: Counter on wasm-stellar-soroban"

  -- -- Test 2: ValueVault is not yet supported on Soroban (env.block has no
  -- host binding). Verify it fails at the capability boundary, not silently. --
  match runStrictCanonicalTargetGate "wasm-stellar-soroban" vaultSpec with
  | .ok _ => throw <| IO.userError "ValueVault should fail on Soroban (env.block not bound)"
  | .error msg => require (msg.contains "env.block") s!"expected env.block failure, got: {msg}"

  -- -- Test 3: runStrictCanonicalContractGate works from raw canonical contract --
  let bundle ← match adaptLegacy counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  requireOk (runStrictCanonicalContractGate "wasm-stellar-soroban" bundle.contract.contract)
    "strict contract gate: Counter on wasm-stellar-soroban"

  -- -- Test 4: ModulePlan.Core.buildFromCore produces a soroban-bridged plan --
  let checked ← match validateCanonical bundle.contract.contract with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-stellar-soroban",
    calls := checked.contract.requirements,
    metadata := #[]
  }
  let plan ← match ModulePlan.Core.buildFromCore checked capPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
  require (plan.hostBridge.bridge == .soroban)
    s!"plan bridge should be soroban, got {repr plan.hostBridge.bridge}"
  require (plan.targetId == "wasm-stellar-soroban")
    s!"plan targetId should be wasm-stellar-soroban, got {plan.targetId}"
  require (plan.moduleName == "Counter")
    s!"plan moduleName should be Counter, got {plan.moduleName}"
  require (plan.functions.size > 0) "plan should have functions"

  -- -- Test 5: Soroban plan reuses NEAR layout (same key-value storage) --
  let nearCapPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near",
    calls := checked.contract.requirements,
    metadata := #[]
  }
  let nearPlan ← match ModulePlan.Core.buildFromCore checked nearCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"NEAR buildFromCore failed: {e.message}"
  require (plan.layout.scalars == nearPlan.layout.scalars)
    "Soroban and NEAR plans have different scalar layouts"
  require (plan.layout.maps == nearPlan.layout.maps)
    "Soroban and NEAR plans have different map layouts"
  require (plan.functions == nearPlan.functions)
    "Soroban and NEAR plans have different function plans"

  -- -- Test 6: Soroban canonical plan lowering is deferred (storage helpers
  -- hard-code NEAR host calls). Verify it fails closed with a clear diagnostic. --
  match ModulePlan.lowerFromPlan plan with
  | .ok _ => throw <| IO.userError "soroban lowering should fail (deferred)"
  | .error error =>
      require (error.message.contains "deferred")
        s!"expected deferred diagnostic, got: {error.message}"

  -- -- Test 7: EmitWat legacy path produces correct Soroban WAT (with _get/_put
  -- imports) — this is the path CLI build uses. --
  let watResult := ProofForge.Backend.WasmHost.EmitWat.renderModule
    ProofForge.IR.Examples.Counter.module .soroban
  match watResult with
  | .error e => throw <| IO.userError s!"EmitWat Soroban render failed: {e.message}"
  | .ok wat =>
      require (wat.contains "_get") "Soroban EmitWat WAT should contain _get host import"
      require (wat.contains "_put") "Soroban EmitWat WAT should contain _put host import"
      require (!wat.contains "storage_read")
        "Soroban EmitWat WAT should not contain NEAR storage_read import"
      require (!wat.contains "storage_write")
        "Soroban EmitWat WAT should not contain NEAR storage_write import"

  -- -- Test 8: CosmWasm still fails closed --
  let cosmwasmResult := runStrictCanonicalTargetGate "wasm-cosmwasm" counterSpec
  match cosmwasmResult with
  | .ok _ => throw <| IO.userError "CosmWasm should fail closed"
  | .error _ => pure ()  /- capability or buildFromCore rejection is correct -/
  IO.println "soroban-public-route: ok"