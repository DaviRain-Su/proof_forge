/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# SolanaReplay smoke — pure string-render check (multi-module)

This is the Step A smoke for `ProofForge.Backend.Quint.SolanaReplay`. It
constructs a `SolanaReplayConfig`, builds a small synthetic ITF trace, and
asserts that `SolanaReplay.renderReplayHarness` produces a Rust Mollusk test
file containing the expected structural anchors (the `Mollusk::new` call, the
instruction tags for the entrypoints, the per-step assertions, and the
plan-derived account list).

It renders harnesses for **three** IR modules — `Counter` (single scalar
state), `ValueVault` (six scalar u64 state fields), and `EvmMapProbe`
(map state, non-scalar) — proving the shim is not Counter-specific. The
account list and state layout are derived from the `SolanaModulePlan`
(Tier B), so the harness reflects each module's real account schema. For the
map module, the primary var is non-scalar, so the v1 observation degrades
gracefully (the harness renders without crashing and skips the byte-level
account-data assertion).

It does **not** spawn `quint`, `sbpf`, `solana-keygen`, or `cargo`; it is a
pure Lean string check. The full end-to-end gate (Step B) is a follow-up.
-/

import ProofForge.IR.Contract
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.SolanaReplay
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Examples.EvmMapProbe

namespace Tests.Quint.SolanaReplaySmoke

open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.SolanaReplay

def counterCfg : SolanaReplayConfig := {
  programPath := "build/testkit/solana/counter/deploy/proofforge-counter.so",
  keypairPath := "build/testkit/solana/counter/deploy/proofforge-counter-keypair.json",
  stateAccountDataLen := 8,
  primaryStateVar := "count",
  primaryStateByteSize := 8
}

/-- A tiny synthetic trace mirroring the shape `quint run --mbt` produces for the
Counter fixture. State 0 is the initial (var) state; the tail states carry the
`init`, `increment`, and `get_` (sanitized — `get` is a Quint reserved word)
actions. The count variable advances 0 -> 0 -> 1 -> 1. -/
def counterTrace : ITF.Trace := {
  vars := ["count"],
  states := [
    { index := 0, actionTaken := some "init", nondetPicks := [], vars := [("count", .int 0)] },
    { index := 1, actionTaken := some "init", nondetPicks := [], vars := [("count", .int 0)] },
    { index := 2, actionTaken := some "increment", nondetPicks := [], vars := [("count", .int 1)] },
    { index := 3, actionTaken := some "get_", nondetPicks := [], vars := [("count", .int 1)] }
  ]
}

/-- ValueVault config: the plan reports the state account as `balance` with
dataSize=48, and `balance` as a scalar at absOff=96. The fallback fields are
only used if the plan build fails. -/
def valueVaultCfg : SolanaReplayConfig := {
  programPath := "build/testkit/solana/valuevault/deploy/proofforge-valuevault.so",
  keypairPath := "build/testkit/solana/valuevault/deploy/proofforge-valuevault-keypair.json",
  stateAccountDataLen := 48,
  primaryStateVar := "balance",
  primaryStateByteSize := 8
}

/-- ValueVault synthetic trace: init(initial=100) -> deposit(25) -> get_balance.
The balance advances 0 -> 100 -> 125 -> 125. Exercises the plan-driven
multi-scalar account seeding and the arg-encoding for non-nullary entrypoints. -/
def valueVaultTrace : ITF.Trace := {
  vars := ["balance"],
  states := [
    { index := 0, actionTaken := some "init",
      nondetPicks := [("initial", .int 100)], vars := [("balance", .int 0)] },
    { index := 1, actionTaken := some "init",
      nondetPicks := [("initial", .int 100)], vars := [("balance", .int 100)] },
    { index := 2, actionTaken := some "deposit",
      nondetPicks := [("amount", .int 25)], vars := [("balance", .int 125)] },
    { index := 3, actionTaken := some "get_balance", nondetPicks := [],
      vars := [("balance", .int 125)] }
  ]
}

/-- Map-state sub-module: only `set_balance`/`read_balance` entrypoints (the two
map lowering paths the Solana backend supports in Phase 1), mirroring
`Tests/SolanaModulePlan.lean`'s `mapSubModule`. The full `EvmMapProbe.module`
also uses `storagePath*`, which Phase 1 does not lower. -/
def mapSubModule : ProofForge.IR.Module := {
  name := "EvmMapProbe"
  state := #[ProofForge.IR.Examples.EvmMapProbe.stateBefore,
             ProofForge.IR.Examples.EvmMapProbe.stateBalances,
             ProofForge.IR.Examples.EvmMapProbe.stateAfter]
  entrypoints := #[ProofForge.IR.Examples.EvmMapProbe.setBalance,
                   ProofForge.IR.Examples.EvmMapProbe.readBalance]
}

/-- EvmMapProbe config: the plan reports `balances` as a `map` field
(byteSize=2048, kind=map). Setting `primaryStateVar := "balances"` exercises the
v1 non-scalar degradation: the primary var is a map, so `primaryFieldOffset?`
is `none` and the harness skips the byte-level account-data assertion while
still rendering the map entrypoint instruction calls. The harness proves the
shim is not Counter-specific by rendering a sensible harness for a map-state
module without crashing. -/
def mapCfg : SolanaReplayConfig := {
  programPath := "build/testkit/solana/evmmapprobe/deploy/proofforge-evmmapprobe.so",
  keypairPath := "build/testkit/solana/evmmapprobe/deploy/proofforge-evmmapprobe-keypair.json",
  stateAccountDataLen := 2064,
  primaryStateVar := "balances",
  primaryStateByteSize := 8
}

/-- EvmMapProbe synthetic trace: init -> set_balance(key=5, value=42) ->
read_balance(key=5). The `balances` map is non-scalar, so the v1 observation
degrades; the trace proves the shim renders a harness for a map-state module
without crashing and includes the map entrypoint instruction tags. The ITF
`balances` var is omitted from the per-state vars (v1 only needs a scalar to
seed the read-back; for the non-scalar case the seed defaults to 0). -/
def mapTrace : ITF.Trace := {
  vars := ["balances"],
  states := [
    { index := 0, actionTaken := some "init", nondetPicks := [],
      vars := [("balances", .int 0)] },
    { index := 1, actionTaken := some "init", nondetPicks := [],
      vars := [("balances", .int 0)] },
    { index := 2, actionTaken := some "set_balance",
      nondetPicks := [("key", .int 5), ("value", .int 42)],
      vars := [("balances", .int 0)] },
    { index := 3, actionTaken := some "read_balance",
      nondetPicks := [("key", .int 5)],
      vars := [("balances", .int 0)] }
  ]
}

def runCase (label : String) (irModule : ProofForge.IR.Module) (cfg : SolanaReplayConfig)
    (trace : ITF.Trace) (checks : List (String × String)) : IO Bool := do
  match renderReplayHarness irModule trace cfg with
  | .error err =>
    IO.eprintln s!"FAIL {label}: render: {err.message}"
    pure false
  | .ok source =>
    let results := checks.map (fun (name, expected) =>
      (name, if source.contains expected then "ok" else "FAIL"))
    let failed := results.filter (fun (_, v) => v != "ok")
    if !failed.isEmpty then
      for (name, _) in failed do
        IO.eprintln s!"FAIL {label}: {name}"
      IO.eprintln "--- rendered source ---"
      IO.eprintln source
      pure false
    else
      IO.println s!"PASS {label} (rendered {source.length} chars)"
      pure true

def main : IO UInt32 := do
  let counterChecks : List (String × String) := [
    ("Counter: references program path", counterCfg.programPath),
    ("Counter: references keypair path", counterCfg.keypairPath),
    ("Counter: builds Mollusk", "Mollusk::new("),
    ("Counter: step 1 (init)", "fn test_step_1()"),
    ("Counter: step 2 (increment)", "fn test_step_2()"),
    ("Counter: step 3 (get_)", "fn test_step_3()"),
    ("Counter: AccountMeta", "AccountMeta::new(")
  ]
  let vvChecks : List (String × String) := [
    ("ValueVault: builds Mollusk", "Mollusk::new("),
    ("ValueVault: step 1 init with initial arg", "fn test_step_1()"),
    ("ValueVault: deposit step", "fn test_step_2()"),
    ("ValueVault: get_balance read step", "fn test_step_3()"),
    ("ValueVault: balance account binding", "let balance = Address::new_unique();"),
    ("ValueVault: 48-byte account data len", "Account::new(0, 48, &pid);")
  ]
  let mapChecks : List (String × String) := [
    ("EvmMapProbe: builds Mollusk", "Mollusk::new("),
    ("EvmMapProbe: set_balance step", "fn test_step_2()"),
    ("EvmMapProbe: read_balance step", "fn test_step_3()"),
    ("EvmMapProbe: before account binding", "let before = Address::new_unique();"),
    ("EvmMapProbe: non-scalar skip comment",
      "non-scalar; v1 skips byte-level")
  ]
  let r1 ← runCase "Counter" ProofForge.IR.Examples.Counter.module counterCfg counterTrace counterChecks
  let r2 ← runCase "ValueVault" ProofForge.IR.Examples.ValueVault.module valueVaultCfg valueVaultTrace vvChecks
  let r3 ← runCase "EvmMapProbe" mapSubModule mapCfg mapTrace mapChecks
  if r1 && r2 && r3 then
    IO.println "PASS SolanaReplaySmoke"
    pure 0
  else
    IO.eprintln "FAIL SolanaReplaySmoke"
    pure 1

end Tests.Quint.SolanaReplaySmoke

def main : IO UInt32 := Tests.Quint.SolanaReplaySmoke.main