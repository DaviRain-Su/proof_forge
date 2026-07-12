import ProofForge.IR.Canonical
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Examples.Counter
import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core

/-!
# Wasm-Host Plan Preservation Test

Verifies that extracting a neutral `WasmHostModulePlan` preserves NEAR
canonical behavior byte-for-byte. The test:

1. Builds a Counter ContractSpec through the legacy adapter.
2. Runs `validateCanonical` to get a checked contract.
3. Calls `WasmHostModulePlan.Core.buildFromCore` with `targetId := "wasm-near"`.
4. Compares the neutral plan's output with `NearModulePlan.Core.buildFromCore`.

If the extraction is correct, the neutral plan and the NEAR plan produce
identical `targetId`, `moduleName`, `layout`, and `functions` fields.

Before the extraction, this file fails to compile because
`ProofForge.Backend.WasmHost.ModulePlan` does not exist.
-/

open ProofForge.IR.Canonical
open ProofForge.Backend.WasmHost

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Build a NEAR plan from the Counter IR via the existing path. -/
def buildNearPlan (checked : CheckedCanonicalContract) :
    Except String NearModulePlan.NearModulePlan := do
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near",
    calls := checked.contract.requirements,
    metadata := #[]
  }
  match NearModulePlan.Core.buildFromCore checked capPlan with
  | .ok plan => .ok plan
  | .error e => .error e.message

/-- Build a neutral WasmHost plan from the Counter IR via the new path. -/
def buildNeutralPlan (checked : CheckedCanonicalContract) :
    Except String ModulePlan.WasmHostModulePlan := do
  let capPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near",
    calls := checked.contract.requirements,
    metadata := #[]
  }
  match ModulePlan.Core.buildFromCore checked capPlan with
  | .ok plan => .ok plan
  | .error e => .error e.message

def main : IO Unit := do
  -- Build Counter spec
  let counterSpec := ProofForge.Contract.ContractSpec.fromIR
    ProofForge.IR.Examples.Counter.module
  let bundle ← match ProofForge.IR.Legacy.Adapter.adaptLegacy counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  let checked ← match validateCanonical bundle.contract.contract with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"

  -- Build both plans
  let nearPlan ← match buildNearPlan checked with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"near plan failed: {e}"
  let neutralPlan ← match buildNeutralPlan checked with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"neutral plan failed: {e}"

  -- Verify the public neutral plan owns the complete target data contract.
  require (neutralPlan.targetId == "wasm-near")
    s!"neutral plan targetId should be wasm-near, got {neutralPlan.targetId}"
  require (neutralPlan.targetId == nearPlan.targetId)
    "neutral and NEAR plans have different targetId"
  require (neutralPlan.moduleName == nearPlan.moduleName)
    "neutral and NEAR plans have different moduleName"

  require (neutralPlan.hostBridge.bridge == .near)
    s!"neutral plan bridge should be near, got {repr neutralPlan.hostBridge.bridge}"

  -- Preservation is asserted at the final WAT boundary, not by sampling a few
  -- plan fields that could miss layout, ABI, helper, or function-body drift.
  let nearWasm <- match NearModulePlan.lowerFromPlan nearPlan with
    | .ok wasm => pure wasm
    | .error error => throw <| IO.userError s!"near lowering failed: {error.message}"
  let neutralWasm <- match ModulePlan.lowerFromPlan neutralPlan with
    | .ok wasm => pure wasm
    | .error error => throw <| IO.userError s!"neutral lowering failed: {error.message}"
  let nearWat := ProofForge.Compiler.Wasm.Printer.render nearWasm
  let neutralWat := ProofForge.Compiler.Wasm.Printer.render neutralWasm
  require (neutralWat == nearWat) "neutral Wasm-host plan changed canonical NEAR WAT"

  -- B3: Soroban now builds a plan (reusing NEAR layout with soroban bridge)
  -- but lowering is still deferred. Verify the plan builds and the bridge
  -- is correctly set to soroban.
  let sorobanPlan : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-stellar-soroban", calls := checked.contract.requirements, metadata := #[] }
  match ModulePlan.Core.buildFromCore checked sorobanPlan with
  | .ok plan =>
      require (plan.hostBridge.bridge == .soroban)
        s!"soroban plan bridge should be soroban, got {repr plan.hostBridge.bridge}"
      require (plan.targetId == "wasm-stellar-soroban")
        s!"soroban plan targetId should be wasm-stellar-soroban, got {plan.targetId}"
      -- Lowering still fails closed for Soroban until EmitWat supports it
      match ModulePlan.lowerFromPlan plan with
      | .ok _ => throw <| IO.userError "soroban lowering should fail (not implemented)"
      | .error _ => pure ()
  | .error error =>
      throw <| IO.userError s!"soroban plan should build (B3), got: {error.message}"

  let mismatchedPlan := { neutralPlan with
    hostBridge := { targetId := "wasm-cosmwasm", bridge := .cosmWasm } }
  match ModulePlan.lowerFromPlan mismatchedPlan with
  | .ok _ => throw <| IO.userError "neutral lowering accepted a mismatched bridge target"
  | .error error =>
      require (error.message.contains "disagree")
        s!"unexpected bridge mismatch diagnostic: {error.message}"

  IO.println "wasm-host-plan-preservation: ok"
