/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-2d: observe dual-run — Lean EVM ModulePlan vs export package surface

Dumps `lean-evm-observe.v0.json` from Lean `buildFromCore` for Counter, writes
the Seam A export package, and records the observe schema for Rust comparison
against `evm-storage-sketch.v0.json`.
-/
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Cli.ExportCore
import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Core.Export
import ProofForge.IR.Examples.Counter
import ProofForge.Target
import ProofForge.Util.Json

namespace ProofForge.Tests.Canonical.DualRunObserve

open ProofForge.Cli.ExportCore
open ProofForge.IR.Core.Export
open ProofForge.Util.Json
open ProofForge.Target
open ProofForge.Backend.Evm.Plan
open ProofForge.IR.Canonical

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def mutabilityName : InterfaceMutability → String
  | .call => "call"
  | .view => "view"

def stateKindName : ProofForge.IR.StateKind → String
  | .scalar => "scalar"
  | .map _ _ => "map"
  | .array _ => "array"
  | .dynamicArray => "dynamicArray"

def observeSchema : String := "lean-evm-observe.v0"

def leanObserveJson
    (plan : ModulePlan)
    (iface : InterfaceContract) : String :=
  let storage := jsonArray (plan.storage.states.map fun st =>
    jsonObject #[
      ("name", jsonString st.id),
      ("slot", toString st.slot),
      ("span", toString st.span),
      ("kind", jsonString (stateKindName st.kind))
    ])
  let entrypoints := jsonArray (plan.entrypoints.map fun ep =>
    jsonObject #[
      ("name", jsonString ep.name),
      ("mutability", jsonString (mutabilityName ep.mutability)),
      ("selector", jsonString ep.selector),
      ("paramCount", toString ep.params.size)
    ])
  let ifaceNames := jsonArray (iface.entrypoints.map fun ep => jsonString ep.name)
  jsonObject #[
    ("schemaVersion", "0"),
    ("observeSchema", jsonString observeSchema),
    ("moduleName", jsonString plan.name),
    ("targetId", jsonString "evm"),
    ("storage", storage),
    ("entrypoints", entrypoints),
    ("interfaceEntrypointNames", ifaceNames)
  ]

def main : IO UInt32 := do
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let bundle ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
    | .ok b => pure b
    | .error e => throw (IO.userError s!"normalize failed: {repr e}")
  let checked := bundle.contract
  let capPlan : CapabilityPlan := {
    targetId := ProofForge.Target.evm.id
    calls := checked.contract.requirements
  }
  let plan ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
    | .ok p => pure p
    | .error e => throw (IO.userError s!"buildFromCore failed: {e.message}")

  require (plan.entrypoints.size == 3) s!"expected 3 entrypoints, got {plan.entrypoints.size}"
  require (plan.storage.states.size == 1) s!"expected 1 storage state, got {plan.storage.states.size}"
  let firstSlot :=
    match plan.storage.states[0]? with
    | some st => st.slot
    | none => 9999
  require (firstSlot == 0) "first storage slot should be 0"

  let outDir := System.FilePath.mk "build/export/lr2d-dual-run/counter-evm"
  let code ← exportContractSpec "evm" outDir spec "portable-ir-fixture" "Counter dual-run observe"
  require (code == 0) s!"exportContractSpec failed exit={code}"

  let observe := leanObserveJson plan checked.contract.interface
  let observePath := outDir / "lean-evm-observe.v0.json"
  IO.FS.writeFile observePath (observe ++ "\n")
  IO.println s!"wrote {observePath}"

  -- Surface-level Lean self-check: interface names match plan entrypoint names.
  let planNames := plan.entrypoints.map (·.name)
  let ifaceNames := checked.contract.interface.entrypoints.map (·.name)
  require (planNames == ifaceNames) "plan entrypoint names must match interface order"

  IO.println "dual-run-observe: ok (Lean plan dump + export package for Counter)"
  pure 0

end ProofForge.Tests.Canonical.DualRunObserve

def main : IO UInt32 :=
  ProofForge.Tests.Canonical.DualRunObserve.main
