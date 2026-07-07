/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# NearReplay smoke — pure string-render check (multi-module)

This is the Step A smoke for `ProofForge.Backend.Quint.NearReplay`. It constructs
a `NearReplayConfig`, builds a small synthetic ITF trace, and asserts that
`NearReplay.renderOfflineHostArgs` produces an arg list containing the expected
export names and the `--inputs-hex` flag.

It renders harnesses for **two** IR modules — `Counter` (scalar state, nullary
entrypoints) and `ValueVault` (multi-scalar state, entrypoints with args) —
proving the shim is not Counter-specific. The render function is already
module-agnostic (it reuses shared replay arg parsing + `encodeArgsLe`); the
multi-module coverage comes from the smoke supplying a ValueVault config +
trace.

It does **not** spawn `quint` or the offline-host; it is a pure Lean string check.
The full end-to-end gate (Step B) is a follow-up.
-/

import ProofForge.IR.Contract
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.NearReplay
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

namespace Tests.Quint.NearReplaySmoke

open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.NearReplay

/-- Counter config: read back `count` via the `get` export. -/
def counterCfg : NearReplayConfig := {
  watPath := "build/wasm-near/emitwat-counter.wat",
  primaryStateExport := "get",
  primaryStateVar := "count"
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

/-- ValueVault config: read back `balance` via the `get_balance` export. The
WAT artifact exists at `Examples/WasmNear/ValueVault.golden.wat`. -/
def valueVaultCfg : NearReplayConfig := {
  watPath := "build/wasm-near/emitwat-valuevault.wat",
  primaryStateExport := "get_balance",
  primaryStateVar := "balance"
}

/-- ValueVault synthetic trace: init(initial=100) -> deposit(25) -> get_balance.
The balance advances 0 -> 100 -> 125 -> 125. The mutating entrypoints carry ABI
args in their nondet picks, exercising `encodeArgsLe` for non-nullary calls. -/
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

def runCase (label : String) (irModule : ProofForge.IR.Module) (cfg : NearReplayConfig)
    (trace : ITF.Trace) (checks : List (String × String)) : IO Bool := do
  match renderOfflineHostArgs irModule trace cfg with
  | .error err =>
    IO.eprintln s!"FAIL {label}: render: {err.message}"
    pure false
  | .ok args =>
    let results := checks.map (fun (name, expected) =>
      (name, if args.contains expected then "ok" else "FAIL"))
    let failed := results.filter (fun (_, v) => v != "ok")
    if !failed.isEmpty then
      for (name, _) in failed do
        IO.eprintln s!"FAIL {label}: {name}: args = {args}"
      pure false
    else
      IO.println s!"PASS {label} args = {args}"
      pure true

def main : IO UInt32 := do
  let counterChecks : List (String × String) := [
    ("Counter: starts with run + wat path",
      "run build/wasm-near/emitwat-counter.wat"),
    ("Counter: contains initialize export",
      "initialize"),
    ("Counter: contains increment export",
      "increment"),
    ("Counter: contains get read-back",
      " get")
  ]
  let vvChecks : List (String × String) := [
    ("ValueVault: starts with run + wat path",
      "run build/wasm-near/emitwat-valuevault.wat"),
    ("ValueVault: contains initialize export",
      "initialize"),
    ("ValueVault: contains deposit export",
      "deposit"),
    ("ValueVault: contains get_balance read-back export",
      "get_balance"),
    ("ValueVault: encodes deposit args (inputs-hex)",
      "--inputs-hex")
  ]
  let r1 ← runCase "Counter" ProofForge.IR.Examples.Counter.module counterCfg counterTrace counterChecks
  let r2 ← runCase "ValueVault" ProofForge.IR.Examples.ValueVault.module valueVaultCfg valueVaultTrace vvChecks
  let hexOk ←
    match encodeArgLe (ProofForge.IR.Semantics.Value.u8 10),
          encodeArgLe (ProofForge.IR.Semantics.Value.u64 15) with
    | .ok "0a", .ok "0f00000000000000" => pure true
    | gotA, gotB =>
        IO.eprintln s!"FAIL NearReplaySmoke: padded hex encoding got {repr gotA}, {repr gotB}"
        pure false
  if r1 && r2 && hexOk then
    IO.println "PASS NearReplaySmoke"
    pure 0
  else
    IO.eprintln "FAIL NearReplaySmoke"
    pure 1

end Tests.Quint.NearReplaySmoke

def main : IO UInt32 := Tests.Quint.NearReplaySmoke.main
