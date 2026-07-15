/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Observe dual-run — Lean EVM ModulePlan vs export package surface

Dumps `lean-evm-observe.v0.json` from Lean `buildFromCore`, writes the Seam A
export package, for Rust `dual-run-observe` against the storage sketch.

Covers Counter (LR-2d), ValueVault (LR-2e), and product Ownable (LR-2f).
-/
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.ExportCore
import ProofForge.Contract.Spec
import Examples.Product.Ownable
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Core.Export
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
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

/-- Align dual-run with product EVM when selectors are absent on portable IR.

Uses pure Lean keccak (LR-S3); no Foundry `cast` required. -/
def hydrateSpecSelectors (label : String) (spec : ProofForge.Contract.ContractSpec) :
    IO ProofForge.Contract.ContractSpec := do
  try
    let before := (spec.module.entrypoints.filter (·.selector?.isNone)).size
    let module ← ProofForge.Cli.hydrateEvmSelectorsMissingLean spec.module
    let after := (module.entrypoints.filter (·.selector?.isNone)).size
    if before > after then
      IO.println s!"{label}: filled {before - after} missing selector(s) via Lean keccak"
    pure { spec with module }
  catch e =>
    IO.println s!"{label}: selector hydrate failed ({e}); continuing without"
    pure spec

def mutabilityName : InterfaceMutability → String
  | .call => "call"
  | .view => "view"

def stateKindName : ProofForge.IR.StateKind → String
  | .scalar => "scalar"
  | .map _ _ => "map"
  | .array _ => "array"
  | .dynamicArray => "dynamicArray"

def observeSchema : String := "lean-evm-observe.v0"

def coreShapeKind : ProofForge.IR.Core.StateShape → String
  | .scalar _ => "scalar"
  | .map _ _ _ => "map"
  | .mapN _ _ _ => "map"
  | .fixedArray _ _ => "array"
  | .dynamicArray _ => "dynamicArray"
  | .record _ => "record"

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

/-- Seam A surface dump when full EVM `buildFromCore` is unavailable (e.g. missing
selectors). Uses interface entrypoints + sequential Core scalar slots — the same
dimensions dual-run-observe compares against the Rust sketch. -/
def leanObserveFromSurface
    (moduleName : String)
    (iface : InterfaceContract)
    (core : ProofForge.IR.Core.Module) : String :=
  let storage := jsonArray (core.state.mapIdx fun i st =>
    jsonObject #[
      ("name", jsonString s!"state_{st.id.value}"),
      ("slot", toString i),
      ("span", "1"),
      ("kind", jsonString (coreShapeKind st.shape))
    ])
  let entrypoints := jsonArray (iface.entrypoints.map fun ep =>
    jsonObject #[
      ("name", jsonString ep.name),
      ("mutability", jsonString (mutabilityName ep.mutability)),
      ("selector", jsonString (ep.selector?.getD "")),
      ("paramCount", toString ep.params.size)
    ])
  let ifaceNames := jsonArray (iface.entrypoints.map fun ep => jsonString ep.name)
  jsonObject #[
    ("schemaVersion", "0"),
    ("observeSchema", jsonString observeSchema),
    ("moduleName", jsonString moduleName),
    ("targetId", jsonString "evm"),
    ("storage", storage),
    ("entrypoints", entrypoints),
    ("interfaceEntrypointNames", ifaceNames)
  ]

/-- Export package + Lean observe dump for one ContractSpec (fixture or product).

Selector hydrate uses Foundry `cast` (same as product EVM Yul path) so portable
products like Ownable can take the full `buildFromCore` observe dump when cast
is available. Without cast, surface dump remains valid for Seam A dimensions. -/
def observeSpec
    (label : String)
    (spec0 : ProofForge.Contract.ContractSpec)
    (outRel : String)
    (minEntrypoints minStates : Nat)
    (sourceKind : String := "portable-ir-fixture") : IO Unit := do
  let spec ← hydrateSpecSelectors label spec0
  let bundle ← match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
    | .ok b => pure b
    | .error e => throw (IO.userError s!"{label}: normalize failed: {repr e}")
  let checked := bundle.contract
  let iface := checked.contract.interface
  let core := checked.contract.module
  let capPlan : CapabilityPlan := {
    targetId := ProofForge.Target.evm.id
    calls := checked.contract.requirements
  }

  require (iface.entrypoints.size ≥ minEntrypoints)
    s!"{label}: expected ≥{minEntrypoints} entrypoints, got {iface.entrypoints.size}"
  require (core.state.size ≥ minStates)
    s!"{label}: expected ≥{minStates} storage states, got {core.state.size}"

  -- Prefer full EVM ModulePlan dump (product-aligned after selector hydrate).
  let observe ← match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
    | .ok plan =>
      match plan.storage.states[0]? with
      | some st => require (st.slot == 0) s!"{label}: first storage slot should be 0"
      | none => throw (IO.userError s!"{label}: empty storage layout")
      let planNames := plan.entrypoints.map (·.name)
      let ifaceNames := iface.entrypoints.map (·.name)
      require (planNames == ifaceNames)
        s!"{label}: plan entrypoint names must match interface order"
      IO.println s!"{label}: buildFromCore observe dump (ModulePlan)"
      pure (leanObserveJson plan iface)
    | .error e =>
      IO.println s!"{label}: buildFromCore unavailable ({e.message}); using interface+Core surface dump"
      for st in core.state do
        match st.shape with
        | .scalar _ => pure ()
        | _ => throw (IO.userError s!"{label}: surface fallback only supports scalar Core state")
      pure (leanObserveFromSurface core.name iface core)

  let outDir := System.FilePath.mk outRel
  -- Export uses original/hydrated IR-backed package (selectors not in contentHash body).
  let code ← exportContractSpec "evm" outDir spec sourceKind s!"{label} dual-run observe"
  require (code == 0) s!"{label}: exportContractSpec failed exit={code}"

  let observePath := outDir / "lean-evm-observe.v0.json"
  IO.FS.writeFile observePath (observe ++ "\n")
  IO.println s!"wrote {observePath}"
  IO.println s!"dual-run-observe: ok Lean dump for {label}"

/-- IR fixture helper (wraps `ContractSpec.fromIR`). -/
def observeFixture
    (label : String)
    (module : ProofForge.IR.Module)
    (outRel : String)
    (minEntrypoints minStates : Nat) : IO Unit :=
  observeSpec label (ProofForge.Contract.ContractSpec.fromIR module)
    outRel minEntrypoints minStates "portable-ir-fixture"

def main : IO UInt32 := do
  observeFixture "Counter" ProofForge.IR.Examples.Counter.module
    "build/export/lr2d-dual-run/counter-evm" 3 1
  observeFixture "ValueVault" ProofForge.IR.Examples.ValueVault.module
    "build/export/lr2e-dual-run/value-vault-evm" 7 6
  observeSpec "Ownable" Examples.Product.Ownable.spec
    "build/export/lr2f-dual-run/ownable-evm" 4 1 "product-source"
  IO.println "dual-run-observe: ok (Counter + ValueVault + Ownable Lean plan dumps)"
  pure 0

end ProofForge.Tests.Canonical.DualRunObserve

def main : IO UInt32 :=
  ProofForge.Tests.Canonical.DualRunObserve.main
