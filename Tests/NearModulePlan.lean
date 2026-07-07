/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# NearModulePlan golden + single-path render smoke

Build the `NearModulePlan` for a named fixture and write its rendered form to a
path provided on the command line. The shell gate compares the output to the
golden copy at `Examples/WasmNear/<Fixture>/golden/plan.txt`.

Step C (RFC 0014 Phase 4) retired the dual-path parity check that landed in
Step B/B.2: there is now only one lowering path. `EmitWat.lowerModule` derives
its `Ctx` via `EmitWat.buildLowerCtx` → `EmitWat.Ctx.fromPlanSeed`, the same
reconstruction `NearModulePlan.Ctx.fromPlanSeed` uses, so the two paths cannot
drift and a "two paths agree" check is no longer meaningful. This smoke is now
a single-path regression gate:
- the plan golden diff pins the layout artifact (`plan.txt`), and
- the `--render` flag renders the module via the plan-driven path
  (`NearModulePlan.renderModuleFromPlan`) and asserts the WAT emits cleanly,
  reporting the char count so byte-churn is observable in CI logs.

Fixtures covered:
- `Counter`               — scalar state (the original MVP)
- `EvmMapProbe`           — map state (`balances`, u64-keyed, sub-module)
- `EvmStorageArrayProbe` — array state (`values`, length 3, sub-module)
- `EvmStorageStructProbe` — struct state (`current` : Point, sub-module)
-/

import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.WasmNear.NearModulePlan
import ProofForge.Backend.WasmNear.EmitWat

namespace ProofForge.Tests.NearModulePlan

open ProofForge.Backend.WasmNear.NearModulePlan
open ProofForge.Backend.WasmNear.EmitWat
open ProofForge.IR

/-- Map-state sub-module: u64-keyed map using only `storageMapGet` (expr) and
`storageMapSet` (statement) — the two map lowering paths the NEAR backend fully
supports. Mirrors the Solana `mapSubModule` shape so plan-driven WAT emits
cleanly. -/
def mapSubModule : Module := {
  name := "EvmMapProbe"
  state := #[ProofForge.IR.Examples.EvmMapProbe.stateBefore,
             ProofForge.IR.Examples.EvmMapProbe.stateBalances,
             ProofForge.IR.Examples.EvmMapProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmMapProbe.setBalance,
                   ProofForge.IR.Examples.EvmMapProbe.readBalance]
}

/-- Array-state sub-module: fixed-length u64 array (`values`, length 3) using
only `storageArrayRead`/`storageArrayWrite` — the array lowering paths the NEAR
backend supports via `dataFixedArray`. Mirrors the Solana `arraySubModule`. -/
def arraySubModule : Module := {
  name := "EvmStorageArrayProbe"
  state := #[ProofForge.IR.Examples.EvmStorageArrayProbe.stateBefore,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateValues,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmStorageArrayProbe.storageLifecycle,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.readValue,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.writeValue]
}

/-- Struct-state sub-module: `current : Point` scalar struct state exercised via
`storageStructFieldRead`/`storageStructFieldWrite` (no whole-struct literal
write). Mirrors the Solana `structSubModule`. -/
def structSubModule : Module := {
  name := "EvmStorageStructProbe"
  structs := #[ProofForge.IR.Examples.EvmStorageStructProbe.pointStruct]
  state := #[ProofForge.IR.Examples.EvmStorageStructProbe.stateBefore,
             ProofForge.IR.Examples.EvmStorageStructProbe.stateCurrent,
             ProofForge.IR.Examples.EvmStorageStructProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmStorageStructProbe.structLifecycle]
}

/-- Resolve a fixture name to its IR module. -/
def moduleFor (name : String) : Option Module :=
  match name with
  | "Counter" => some ProofForge.IR.Examples.Counter.module
  | "EvmMapProbe" => some mapSubModule
  | "EvmStorageArrayProbe" => some arraySubModule
  | "EvmStorageStructProbe" => some structSubModule
  | _ => none

/-- Single-path render check: lower `mod` via the plan-driven path
(`NearModulePlan.renderModuleFromPlan`) and return `ok n` (the WAT char count)
if the WAT emits cleanly, or `error msg` otherwise. Step C retired the
dual-path parity check; this is now the regression gate that confirms the
plan-driven lowering still emits for each fixture, with the char count
surfaced in CI logs so byte-churn is observable. -/
def renderCheck (mod : Module) : Except String Nat := do
  let plan ← match buildNearModulePlan mod with
    | .ok p => pure p
    | .error e => .error s!"plan build failed: {e.message}"
  let wat ← match renderModuleFromPlan mod plan with
    | .ok s => pure s
    | .error e => .error s!"plan-driven render failed: {e.message}"
  .ok wat.length

def main (args : List String) : IO UInt32 := do
  let fixtureName := args[0]?.getD "Counter"
  let path := args[1]?.getD (s!"build/wasm-near/{fixtureName}.plan.txt")
  let runRender := args.contains "--render"
  if args.length > 3 then
    IO.eprintln "usage: NearModulePlan <fixture> <output-path> [--render]"
    return 2
  match moduleFor fixtureName with
  | none =>
    IO.eprintln s!"unknown fixture: {fixtureName}"
    return 2
  | some module =>
    match buildNearModulePlan module with
    | .error err =>
      IO.eprintln s!"failed to build NearModulePlan for {fixtureName}: {err.message}"
      return 1
    | .ok plan =>
      let rendered := plan.render
      IO.FS.writeFile path rendered
      IO.println s!"wrote NearModulePlan ({fixtureName}) to {path}"
      if runRender then
        match renderCheck module with
        | .error msg =>
          IO.eprintln s!"RENDER FAIL ({fixtureName}): {msg}"
          return 1
        | .ok n =>
          IO.println s!"RENDER OK ({fixtureName}): {n} chars"
      return 0

end ProofForge.Tests.NearModulePlan

def main : List String → IO UInt32 :=
  ProofForge.Tests.NearModulePlan.main