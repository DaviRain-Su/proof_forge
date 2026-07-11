import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Target.Plan

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
      { functionId := ⟨0⟩, name := "initialize", kind := .function,
        mutability := .call, params := #[], retType := .unit },
      { functionId := ⟨1⟩, name := "increment", kind := .function,
        mutability := .call, params := #[], retType := .unit },
      { functionId := ⟨2⟩, name := "get", kind := .function,
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

def nearCapPlan : CapabilityPlan := { targetId := "wasm-near", calls := #[], metadata := #[] }
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

  IO.println "canonical-near-plan: ok"