/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# SolanaModulePlan golden smoke

Build the Solana semantic plan for a named fixture and write its rendered form
to a path provided on the command line. The shell gate compares the output to
the golden copy at `Examples/Solana/<Fixture>/golden/plan.txt`.

Fixtures covered (RFC 0014 Tier B — array/map/struct state extension):
- `Counter`              — scalar state (the original MVP)
- `EvmStorageArrayProbe` — array state (`values`, length 3)
- `EvmMapProbe`          — map state (`balances`, capacity 128)
- `EvmStorageStructProbe` — struct state (`current` : Point)

Each fixture uses a sub-module whose entrypoints only exercise lowering paths
the Solana backend already supports, so the plan-driven lowering produces
valid, deterministic assembly for every fixture.
-/

import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.Backend.Solana.Plan

namespace ProofForge.Tests.SolanaModulePlan

open ProofForge.Backend.Solana.Plan
open ProofForge.IR

/-- Array-state sub-module: only `storageArrayRead`/`storageArrayWrite` entrypoints.
The full `EvmStorageArrayProbe.module` also uses `storagePath*` with `.index`
segments, which the Phase 1 Solana backend does not lower. This sub-module
exercises the array state layout (`values`, length 3) via the supported
lowering paths, so the plan-driven assembly emits cleanly. -/
def arraySubModule : Module := {
  name := "EvmStorageArrayProbe"
  state := #[ProofForge.IR.Examples.EvmStorageArrayProbe.stateBefore,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateValues,
             ProofForge.IR.Examples.EvmStorageArrayProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmStorageArrayProbe.storageLifecycle,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.readValue,
                   ProofForge.IR.Examples.EvmStorageArrayProbe.writeValue]
}

/-- Map-state sub-module: u64-keyed map using only `storageMapGet` (expr) and
`storageMapSet` (statement) — the two map lowering paths the Solana backend
fully supports in Phase 1. -/
def mapSubModule : Module := {
  name := "EvmMapProbe"
  state := #[ProofForge.IR.Examples.EvmMapProbe.stateBefore,
             ProofForge.IR.Examples.EvmMapProbe.stateBalances,
             ProofForge.IR.Examples.EvmMapProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmMapProbe.setBalance,
                   ProofForge.IR.Examples.EvmMapProbe.readBalance]
}

/-- Struct-state sub-module: `current : Point` scalar struct state exercised via
`storageStructFieldRead`/`storageStructFieldWrite` (no whole-struct literal
write, which is Phase 2). -/
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
  | "EvmStorageArrayProbe" => some arraySubModule
  | "EvmMapProbe" => some mapSubModule
  | "EvmStorageStructProbe" => some structSubModule
  | _ => none

def main (args : List String) : IO UInt32 := do
  let fixtureName := args[0]?.getD "Counter"
  let path := args[1]?.getD (s!"build/solana/{fixtureName}.plan.txt")
  if args.length > 2 then
    IO.eprintln "usage: SolanaModulePlan <fixture> <output-path>"
    return 2
  match moduleFor fixtureName with
  | none =>
    IO.eprintln s!"unknown fixture: {fixtureName}"
    return 2
  | some module =>
    match buildSolanaModulePlan module with
    | .error err =>
      IO.eprintln s!"failed to build SolanaModulePlan for {fixtureName}: {err.render}"
      return 1
    | .ok plan =>
      let rendered := plan.render
      IO.FS.writeFile path rendered
      IO.println s!"wrote SolanaModulePlan ({fixtureName}) to {path}"
      return 0

end ProofForge.Tests.SolanaModulePlan

def main : List String → IO UInt32 :=
  ProofForge.Tests.SolanaModulePlan.main
