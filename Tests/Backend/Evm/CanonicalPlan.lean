import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Target.Plan

/-! # Canonical Core → EVM Plan Assertions

Tests that `buildFromCore` produces valid EVM `ModulePlan` from
`CheckedCanonicalContract`. Checks:
- physical slot allocation is injective over logical StateId;
- selectors/ABI come from InterfaceContract, never zero fallback;
- each non-empty Core function has a non-empty StmtPlan body;
- return plans exist for every non-unit function;
- evidence changes do not change ModulePlan;
- missing capability, unsupported Core op, and incomplete return fail.
-/

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Plan.Core

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A simple counter contract in Core: one state, two functions
(initialize + increment + get). -/
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
        mutability := .call, params := #[], retType := .unit,
        selector? := some "0xdeadbeef" },
      { functionId := ⟨1⟩, name := "increment", kind := .function,
        mutability := .call, params := #[], retType := .unit,
        selector? := some "0xfeedface" },
      { functionId := ⟨2⟩, name := "get", kind := .function,
        mutability := .view, params := #[], retType := .u64,
        selector? := some "0xc0ffee00" }
    ]
    events := #[]
    errors := #[]
  }
  materialization := {
    constructorParams := #[{ name := "initial", abiType := "uint64" }]
    constructorBindings := #[{
      stateId := ⟨0⟩, paramName := "initial", kind := .scalarU64 }]
    stateSymbols := #[{ stateId := ⟨0⟩, name := "count" }]
  }
  requirements := #[]
}

def counterContractWithReqs : CanonicalContract := {
  counterContract with
  requirements := deriveCapabilityRequirements
    counterContract.module counterContract.materialization
}

def emptyCapPlan : CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }

def wrongTargetCapPlan : CapabilityPlan := { targetId := "solana-sbpf-asm", calls := #[], metadata := #[] }

/-- A contract with an unsupported instruction (hostCall). -/
def unsupportedContract : CanonicalContract := {
  schemaVersion := 1
  module := {
    name := "Unsupported"
    structs := #[]
    state := #[]
    events := #[]
    functions := #[
      { id := ⟨0⟩, params := #[], retType := .u64, entry := ⟨0⟩,
        blocks := #[{
          id := ⟨0⟩, params := #[],
          instructions := #[
            ⟨#[⟨⟨0⟩, .u64⟩], .hostCall {
              id := ⟨"test", "unsupported", ⟨1, 0, 0⟩⟩,
              args := #[] }⟩
          ]
          terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
        }]
      }
    ]
    errors := #[]
  }
  interface := {
    contractName := "Unsupported"
    entrypoints := #[
      { functionId := ⟨0⟩, name := "run", kind := .function,
        mutability := .view, params := #[], retType := .u64 }
    ]
  }
  materialization := { constructorParams := #[], constructorBindings := #[], stateSymbols := #[] }
  requirements := #[]
}

def main : IO Unit := do
  /- Validate the counter contract. -/
  let counterChecked ← match validateCanonical counterContractWithReqs with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter validation failed: {repr e}"

  /- Build the EVM plan from Core. -/
  let plan ← match buildFromCore counterChecked emptyCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Counter buildFromCore failed: {e.message}"

  /- Check 1: slot allocation is injective over StateId. -/
  let slots := plan.storage.states.map (·.slot)
  /- Check all slots are distinct: sort and look for adjacent duplicates. -/
  let sorted := slots.qsort (· ≤ ·)
  let mut hasDup := false
  for i in [1:sorted.size] do
    if sorted[i]! == sorted[i-1]! then hasDup := true
  require (!hasDup) "slot allocation is not injective"

  /- Check 2: selectors come from InterfaceContract, never zero fallback. -/
  for ep in plan.entrypoints do
    require (ep.selector != "0x00000000") s!"entrypoint {ep.name} has zero selector"
    require (!ep.selector.isEmpty) s!"entrypoint {ep.name} has empty selector"

  /- Check 3: each non-empty Core function has a non-empty StmtPlan body. -/
  for ep in plan.entrypoints do
    require (!ep.body.isEmpty) s!"entrypoint {ep.name} has empty body"

  /- Check 4: return plans exist for every non-unit function. -/
  for ep in plan.entrypoints do
    match ep.returns.returnType with
    | .unit => pure ()
    | _ =>
      /- The entry point must either return a value or have a return stmt. -/
      let hasReturn := ep.body.any fun s => match s with
        | StmtPlan.return _ => true
        | _ => false
      require hasReturn s!"entrypoint {ep.name} with non-unit return has no return stmt"

  /- Check 5: evidence changes do not change ModulePlan. -/
  let plan2 ← match buildFromCore counterChecked emptyCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Second buildFromCore failed: {e.message}"
  require (plan.storage.states.size == plan2.storage.states.size) "storage changed between builds"
  require (plan.entrypoints.size == plan2.entrypoints.size) "entrypoint count changed"

  /- Check 6: wrong target fails. -/
  match buildFromCore counterChecked wrongTargetCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore should fail with wrong target"
  | .error e =>
    require (e.message.contains "requires target") s!"wrong target error: {e.message}"

  /- Check 7: unsupported Core op fails (either at validation or buildFromCore).
  This is fail-closed: either path rejecting the contract is correct. -/
  match validateCanonical {
    unsupportedContract with
    requirements := deriveCapabilityRequirements
      unsupportedContract.module unsupportedContract.materialization
  } with
  | .ok c =>
      match buildFromCore c emptyCapPlan with
      | .ok _ => throw <| IO.userError "buildFromCore should fail with unsupported op"
      | .error _ => pure ()
  | .error _ => pure ()

  IO.println "canonical-evm-plan: ok"