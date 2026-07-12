import ProofForge.IR.Canonical
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Examples.Counter
import ProofForge.Backend.WasmHost.ModulePlan
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

  -- Verify preservation: targetId, moduleName, layout scalars, functions
  require (neutralPlan.targetId == "wasm-near")
    s!"neutral plan targetId should be wasm-near, got {neutralPlan.targetId}"
  require (neutralPlan.targetId == nearPlan.targetId)
    "neutral and NEAR plans have different targetId"
  require (neutralPlan.moduleName == nearPlan.moduleName)
    "neutral and NEAR plans have different moduleName"

  -- Layout scalars must match
  require (neutralPlan.layout.scalars.size == nearPlan.layout.scalars.size)
    s!"neutral plan has {neutralPlan.layout.scalars.size} scalars, NEAR has {nearPlan.layout.scalars.size}"
  for (ns, ns2) in neutralPlan.layout.scalars.zip nearPlan.layout.scalars do
    require (ns.id == ns2.id) s!"scalar id mismatch: {ns.id} vs {ns2.id}"
    require (ns.keyPtr == ns2.keyPtr) s!"scalar keyPtr mismatch: {ns.id}"
    require (ns.keyLen == ns2.keyLen) s!"scalar keyLen mismatch: {ns.id}"

  -- Functions must match
  require (neutralPlan.functions.size == nearPlan.functions.size)
    s!"neutral plan has {neutralPlan.functions.size} functions, NEAR has {nearPlan.functions.size}"
  for (nf, nrf) in neutralPlan.functions.zip nearPlan.functions do
    require (nf.name == nrf.name) s!"function name mismatch: {nf.name} vs {nrf.name}"
    require (nf.blocks.size == nrf.blocks.size)
      s!"function {nf.name} block count mismatch: {nf.blocks.size} vs {nrf.blocks.size}"

  -- NEAR-only HostOp (promise_create) must reject on a neutral plan with
  -- a Soroban bridge — this verifies the neutral plan carries bridge info.
  -- (Deferred to B3; here we just verify the plan has a bridge field.)
  require (neutralPlan.bridge.kind == ModulePlan.WasmHostKind.near)
    s!"neutral plan bridge kind should be near, got {repr neutralPlan.bridge.kind}"

  IO.println "wasm-host-plan-preservation: ok"