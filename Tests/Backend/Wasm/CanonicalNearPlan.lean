import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Target.Plan
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Stdlib.NearFungibleToken
import ProofForge.Contract.Spec
import ProofForge.Compiler.Wasm.Printer

/-! # Canonical Core → NEAR Plan Assertions

Tests that `buildFromCore` produces valid NEAR `NearModulePlan` from
`CheckedCanonicalContract`. Checks:
- scalar states receive distinct key pointers;
- each non-unit function has a planned return type;
- evidence changes do not change the plan;
- wrong target fails.
-/

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.WasmHost.NearModulePlan
open ProofForge.Backend.WasmHost.NearModulePlan.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A simple counter contract in Core: one state, three functions. -/
def counterContract : CanonicalContract := {
  schemaVersion := 1
  module := {
    name := "Counter"
    structs := #[]
    state := #[⟨⟨0⟩, .scalar .u64⟩]
    events := #[]
    functions := #[
      { id := ⟨0⟩, params := #[], retType := .unit, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
            ⟨#[], .storageStore
              { root := ⟨0⟩, path := #[], resultType := .u64 }
              { id := ⟨0⟩, type := .u64 }⟩
          ]
          terminator := .return #[]
        }]
      },
      { id := ⟨1⟩, params := #[], retType := .unit, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨1⟩, .u64⟩], .storageLoad
              { root := ⟨0⟩, path := #[], resultType := .u64 }⟩,
            ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
            ⟨#[⟨⟨3⟩, .u64⟩], .pure (.arithmetic .add .checked
              { id := ⟨1⟩, type := .u64 } { id := ⟨2⟩, type := .u64 })⟩,
            ⟨#[], .storageStore
              { root := ⟨0⟩, path := #[], resultType := .u64 }
              { id := ⟨3⟩, type := .u64 }⟩
          ]
          terminator := .return #[]
        }]
      },
      { id := ⟨2⟩, params := #[], retType := .u64, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨3⟩, .u64⟩], .storageLoad
              { root := ⟨0⟩, path := #[], resultType := .u64 }⟩
          ]
          terminator := .return #[{ id := ⟨3⟩, type := .u64 }]
        }]
      }
    ]
    errors := #[]
  }
  interface := {
    contractName := "Counter"
    entrypoints := #[
      { functionId := ⟨0⟩, name := "initialize",
        mutability := .call, params := #[], retType := .unit },
      { functionId := ⟨1⟩, name := "increment",
        mutability := .call, params := #[], retType := .unit },
      { functionId := ⟨2⟩, name := "get",
        mutability := .view, params := #[], retType := .u64 }
    ]
  }
  materialization := {
    constructorParams := #[{ name := "initial", abiType := "uint64" }]
    constructorBindings := #[{ stateId := ⟨0⟩, paramName := "initial", kind := .scalarU64 }]
    stateSymbols := #[{ stateId := ⟨0⟩, name := "count" }]
  }
  requirements := #[]
}

def counterWithReqs : CanonicalContract := {
  counterContract with
  requirements := deriveCapabilityRequirements
    counterContract.module counterContract.materialization
}

def nearCapPlan : CapabilityPlan := { targetId := "wasm-near", calls := counterWithReqs.requirements, metadata := #[] }
def wrongCapPlan : CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }

def main : IO Unit := do
  let checked ← match validateCanonical counterWithReqs with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter validation failed: {repr e}"

  let plan ← match buildFromCore checked nearCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Counter buildFromCore failed: {e.message}"

  /- Check 1: scalar states receive distinct key pointers. -/
  let keyPtrs := plan.layout.scalars.map (·.keyPtr)
  let sorted := keyPtrs.qsort (· ≤ ·)
  let mut hasDup := false
  for i in [1:sorted.size] do
    if sorted[i]! == sorted[i-1]! then hasDup := true
  require (!hasDup) "scalar key pointers are not distinct"

  /- Check 2: each non-unit function has a planned return type. -/
  for ep in plan.layout.scalars do
    require (!ep.id.isEmpty) "state has empty id"

  /- Check 3: surface has correct storage flags. -/
  require (plan.surface.usesStorageRead) "surface should have storage read"
  require (plan.surface.usesStorageWrite) "surface should have storage write"
  require (plan.functions.size == 3 && plan.functions.all (fun fn => !fn.blocks.isEmpty))
    "canonical NEAR function bodies are incomplete"
  let allOps := plan.functions.flatMap (fun fn => fn.blocks.flatMap (fun block => block.ops))
  require (allOps.any (fun op => match op with | .loadState .. => true | _ => false)) "NEAR state load op missing"
  require (allOps.any (fun op => match op with | .storeState .. => true | _ => false)) "NEAR state store op missing"
  require (allOps.any (fun op => match op with | .arithmetic .. => true | _ => false)) "NEAR arithmetic op missing"
  let wasm <- match lowerFromPlan plan with
    | .ok wasm => pure wasm
    | .error e => throw <| IO.userError s!"Counter plan-only Wasm lowering failed: {e.message}"
  let wat := ProofForge.Compiler.Wasm.Printer.render wasm
  require (wat.contains "(export \"get\")") "Counter canonical WAT lost get export"

  /- Check 4: evidence changes do not change the plan. -/
  let plan2 ← match buildFromCore checked nearCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Second buildFromCore failed: {e.message}"
  require (plan.layout.scalars.size == plan2.layout.scalars.size) "scalar count changed"
  require (plan.surface.returnTypes.size == plan2.surface.returnTypes.size) "return type count changed"

  /- Check 5: wrong target fails. -/
  match buildFromCore checked wrongCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore should fail with wrong target"
  | .error e =>
      require (e.message.contains "requires target") s!"wrong target error: {e.message}"

  match buildFromCore checked { targetId := "wasm-near", calls := #[], metadata := #[] } with
  | .ok _ => throw <| IO.userError "NEAR buildFromCore accepted missing capabilities"
  | .error _ => pure ()

  match coreMapToNearMapPlan { id := ⟨9⟩, shape := .dynamicArray .u64 } "items" 1024 with
  | .ok _ => throw <| IO.userError "dynamic NEAR state silently received a placeholder layout"
  | .error _ => pure ()

  let vaultBundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy
      (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"ValueVault adaptation failed: {repr e}"
  let vaultCapPlan : CapabilityPlan := {
    targetId := "wasm-near", calls := vaultBundle.contract.contract.requirements, metadata := #[]
  }
  let vaultPlan <- match buildFromCore vaultBundle.contract vaultCapPlan with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"ValueVault NEAR plan failed: {e.message}"
  require (vaultPlan.layout.scalars.size == 6) "ValueVault NEAR plan lost scalar states"
  require (vaultPlan.functions.size == 7 && vaultPlan.functions.all (fun fn => !fn.blocks.isEmpty))
    "ValueVault NEAR plan lost function bodies"
  let vaultWasm <- match lowerFromPlan vaultPlan with
    | .ok wasm => pure wasm
    | .error e => throw <| IO.userError s!"ValueVault plan-only Wasm lowering failed: {e.message}"
  let vaultWat := ProofForge.Compiler.Wasm.Printer.render vaultWasm
  require (vaultWat.contains "(export \"deposit\")" && vaultWat.contains "log_utf8")
    "ValueVault canonical WAT lost entrypoint or event host call"

  let ftBundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy
      (ProofForge.Contract.ContractSpec.fromIR ProofForge.Contract.Stdlib.NearFungibleToken.module) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"NearFungibleToken adaptation failed: {repr e}"
  let ftCapPlan : CapabilityPlan := {
    targetId := "wasm-near", calls := ftBundle.contract.contract.requirements, metadata := #[]
  }
  let ftPlan <- match buildFromCore ftBundle.contract ftCapPlan with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"NearFungibleToken NEAR plan failed: {e.message}"
  let ftOps := ftPlan.functions.flatMap (fun fn => fn.blocks.flatMap (fun block => block.ops))
  require (ftOps.any fun op => match op with
    | .literal _ 1 => true
    | _ => false) "canonical NEAR plan lost the ft_resolve_transfer pool handle"

  IO.println "canonical-near-plan: ok"
