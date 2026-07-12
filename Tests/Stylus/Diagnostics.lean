import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.Validate
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Legacy.Adapter
import ProofForge.Contract.Spec

open ProofForge.Backend.Stylus

def requireErrorContains (needle : String) (result : Except PlanError α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected error containing `{needle}`, got success"
  | .error e =>
      unless e.message.contains needle do
        throw <| IO.userError s!"expected `{needle}`, got `{e.message}`"

def main : IO Unit := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok value => pure value
    | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  requireErrorContains "wrong target"
    (ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-near", calls := bundle.contract.contract.requirements })
  requireErrorContains "does not match canonical requirements"
    (ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract {
      targetId := "wasm-arbitrum-stylus", calls := #[] })

  let invalidTypePlan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus"
    moduleName := "Invalid"
    abi := {
      methods := #[{
        name := "bad"
        canonicalSignature := "bad(uint24)"
        selector := #[0, 0, 0, 0]
        params := #[{ name := "value", type := .uint 24 }]
      }]
      errors := #[]
    }
    storage := { words := #[] }
    functions := #[]
    events := #[]
    calls := #[]
    hostOps := #[]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  requireErrorContains "uint24" (validatePlan invalidTypePlan)

  let incomplete := { invalidTypePlan with
    abi := { methods := #[], errors := #[] }
    hostOps := #[{
      id := "host-0", functionId := "bad", operation := .storageLoad
      support := { rustSdk := .unsupported "not implemented", directWasm := .planned }
    }]
  }
  requireErrorContains "renderer rust-sdk" (validateForRenderer .rustSdk incomplete)
  requireErrorContains "renderer direct-wasm" (validateForRenderer .directWasm incomplete)
  IO.println "stylus-diagnostics: ok"
