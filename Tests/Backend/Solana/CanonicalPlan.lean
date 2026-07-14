import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Target.Plan
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec

/-! # Canonical Core → Solana Plan Assertions

Tests that `buildFromCore` produces valid Solana `SolanaModulePlan` from
`CheckedCanonicalContract`. Checks:
- state fields receive distinct account-data offsets;
- entrypoint discriminators are non-empty;
- evidence changes do not change the plan;
- wrong target fails;
- unsupported Core op fails.
-/

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Solana.Plan
open ProofForge.Backend.Solana.Plan.Core
open ProofForge.IR.Legacy.Adapter

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
        mutability := .call, params := #[], retType := .unit,
        selector? := some "0xdeadbeef" },
      { functionId := ⟨1⟩, name := "increment",
        mutability := .call, params := #[], retType := .unit,
        selector? := some "0xfeedface" },
      { functionId := ⟨2⟩, name := "get",
        mutability := .view, params := #[], retType := .u64,
        selector? := some "0xc0ffee00" }
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

def solanaCapPlan : CapabilityPlan := {
  targetId := "solana-sbpf-asm", calls := counterWithReqs.requirements, metadata := #[]
}
def wrongCapPlan : CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }

def main : IO Unit := do
  let checked ← match validateCanonical counterWithReqs with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"Counter validation failed: {repr e}"

  let plan ← match buildFromCore checked solanaCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Counter buildFromCore failed: {e.message}"

  /- Check 1: state fields receive distinct offsets. -/
  let offsets := plan.stateFields.map (·.absOff)
  let sorted := offsets.qsort (· ≤ ·)
  let mut hasDup := false
  for i in [1:sorted.size] do
    if sorted[i]! == sorted[i-1]! then hasDup := true
  require (!hasDup) "state field offsets are not distinct"

  /- Check 2: entrypoint discriminators are non-empty. -/
  for ep in plan.entrypoints do
    require (!ep.discriminator.bytes.isEmpty) s!"entrypoint {ep.name} has empty discriminator"

  require (plan.functions.size == 3) "canonical function bodies are missing"
  require (plan.functions.all (fun fn => !fn.blocks.isEmpty)) "canonical function has no blocks"
  let allOps := plan.functions.flatMap (fun fn => fn.blocks.flatMap (fun block => block.ops))
  require (allOps.any (fun op => match op with | .loadState .. => true | _ => false)) "state load plan missing"
  require (allOps.any (fun op => match op with | .storeState .. => true | _ => false)) "state store plan missing"
  require (allOps.any (fun op => match op with | .arithmetic .. => true | _ => false)) "arithmetic plan missing"
  require (plan.functions.any (fun fn => fn.blocks.any (fun block =>
    match block.terminator with | .return values => !values.isEmpty | _ => false))) "value return plan missing"
  let canonicalNodes <- match lowerFromPlan plan with
    | .ok nodes => pure nodes
    | .error e => throw <| IO.userError s!"plan-only lowering failed: {e.message}"
  require (!canonicalNodes.isEmpty) "plan-only lowering emitted an empty program"
  match ProofForge.Backend.Solana.BpfEncode.toBpfBin canonicalNodes with
  | .ok bytes => require (bytes.size > 0) "plan-only lowering encoded no bytes"
  | .error e => throw <| IO.userError s!"plan-only encoding failed: {e.render}"

  /- Check 3: evidence changes do not change the plan. -/
  let plan2 ← match buildFromCore checked solanaCapPlan with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"Second buildFromCore failed: {e.message}"
  require (plan.stateFields.size == plan2.stateFields.size) "state field count changed"
  require (plan.entrypoints.size == plan2.entrypoints.size) "entrypoint count changed"

  /- Check 4: wrong target fails. -/
  match buildFromCore checked wrongCapPlan with
  | .ok _ => throw <| IO.userError "buildFromCore should fail with wrong target"
  | .error e =>
      require (e.message.contains "requires target") s!"wrong target error: {e.message}"

  match buildFromCore checked { targetId := "solana-sbpf-asm", calls := #[], metadata := #[] } with
  | .ok _ => throw <| IO.userError "buildFromCore accepted a missing capability"
  | .error e => require (e.message.contains "missing") s!"missing capability error: {e.message}"

  match coreStateByteSize (.dynamicArray .u64) with
  | .ok _ => throw <| IO.userError "dynamic state silently received a zero-sized layout"
  | .error _ => pure ()

  let unsupportedParam : InterfaceEntrypoint := {
    functionId := ⟨0⟩, name := "bad", mutability := .call,
    params := #[{ valueId := ⟨0⟩, name := "payload", type := .bytes }], retType := .unit
  }
  match coreEntrypointToPlan unsupportedParam 0 with
  | .ok _ => throw <| IO.userError "unsupported ABI parameter silently received byteSize zero"
  | .error _ => pure ()

  let malformedSelector : InterfaceEntrypoint := {
    functionId := ⟨0⟩, name := "bad-selector", mutability := .call,
    params := #[], retType := .unit, selector? := some "zzzzzzzzzzzzzzzz"
  }
  match coreEntrypointToPlan malformedSelector 0 with
  | .ok _ => throw <| IO.userError "malformed discriminator silently fell back to an internal tag"
  | .error _ => pure ()

  let vaultSpec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
  let vaultBundle <- match adaptLegacy vaultSpec with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"ValueVault canonical adaptation failed: {repr e}"
  let vaultChecked := vaultBundle.contract
  let vaultCapPlan : CapabilityPlan := {
    targetId := "solana-sbpf-asm", calls := vaultChecked.contract.requirements, metadata := #[]
  }
  let vaultPlan <- match buildFromCore vaultChecked vaultCapPlan with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"ValueVault Solana plan failed: {e.message}"
  require (vaultPlan.stateFields.size == 6) "ValueVault did not retain six state fields"
  let vaultOffsets := vaultPlan.stateFields.map (fun field => field.absOff)
  require (vaultOffsets.all (fun offset => (vaultOffsets.filter (· == offset)).size == 1))
    "ValueVault state ranges overlap"
  require (vaultPlan.functions.size == 7 && vaultPlan.functions.all (fun fn => !fn.blocks.isEmpty))
    "ValueVault semantic function bodies are incomplete"
  match lowerFromPlan vaultPlan with
  | .ok nodes => require (!nodes.isEmpty) "ValueVault plan-only lowering emitted no instructions"
  | .error e => throw <| IO.userError s!"ValueVault plan-only lowering failed: {e.message}"

  IO.println "canonical-solana-plan: ok"
