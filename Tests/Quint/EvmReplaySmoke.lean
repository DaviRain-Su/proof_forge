/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# EvmReplay smoke — pure string-render check (multi-module)

This is the pure string-render smoke for `ProofForge.Backend.Quint.EvmReplay`.
It renders a Foundry test source from a synthetic ITF trace for **two** IR
modules — `Counter` (scalar state, nullary entrypoints) and `ValueVault`
(multi-scalar state, entrypoints with args) — and asserts the rendered source
contains the expected structural anchors (the `initialize`/mutating/read
entrypoint signatures, the encoded arg literals, and the read-back assertions).

It does **not** spawn `quint`, `forge`, or `proof-forge emit`; it is a pure Lean
string check. The end-to-end Counter gate (`Tests/Quint/CounterEvmReplay.lean` +
`scripts/quint/evm-backend-replay-gate.sh`) remains the CI-visible artifact.

The ValueVault case proves the shim is no longer Counter-specific: it renders a
sensible Foundry harness for a module whose entrypoints take ABI args
(`initialize(uint256)`, `deposit(uint256)`, `charge_fee(uint256,uint256)`,
`release(uint256)`) and whose primary scalar observation is `balance` (read via
`get_balance()`), not `count`/`get()`.
-/

import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.EvmReplay
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

namespace Tests.Quint.EvmReplaySmoke

open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.EvmReplay

def counterCfg : EvmReplayConfig := {
  bytecodeHex := "deadbeef",
  readSignature := "get()",
  primaryStateVar := "count"
}

/-- Counter synthetic trace: init -> increment -> get_. The count advances
0 -> 0 -> 1 -> 1. `get_` is the sanitized Quint action name (`get` is reserved). -/
def counterTrace : ITF.Trace := {
  vars := ["count"],
  states := [
    { index := 0, actionTaken := some "init", nondetPicks := [], vars := [("count", .int 0)] },
    { index := 1, actionTaken := some "init", nondetPicks := [], vars := [("count", .int 0)] },
    { index := 2, actionTaken := some "increment", nondetPicks := [], vars := [("count", .int 1)] },
    { index := 3, actionTaken := some "get_", nondetPicks := [], vars := [("count", .int 1)] }
  ]
}

def valueVaultCfg : EvmReplayConfig := {
  bytecodeHex := "cafebabe",
  readSignature := "get_balance()",
  primaryStateVar := "balance",
  initSignature := "initialize(uint256)"
}

/-- ValueVault synthetic trace: init(initial=100) -> deposit(25) -> get_balance
-> charge_fee(100,250) -> get_balance. The balance advances
0 -> 100 -> 125 -> 125 -> 223 -> 223. The mutating entrypoints carry ABI args in
their nondet picks, exercising the generalized arg encoder. -/
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
      vars := [("balance", .int 125)] },
    { index := 4, actionTaken := some "charge_fee",
      nondetPicks := [("gross", .int 100), ("fee_bps", .int 250)],
      vars := [("balance", .int 223)] },
    { index := 5, actionTaken := some "get_balance", nondetPicks := [],
      vars := [("balance", .int 223)] }
  ]
}

def runCase (label : String) (irModule : ProofForge.IR.Module) (cfg : EvmReplayConfig)
    (trace : ITF.Trace) (checks : List (String × String)) : IO Bool := do
  match renderFoundryTest irModule trace cfg with
  | .error err =>
    IO.eprintln s!"FAIL {label}: render: {err.message}"
    pure false
  | .ok src =>
    let results := checks.map (fun (name, expected) =>
      (name, if src.contains expected then "ok" else "FAIL"))
    let failed := results.filter (fun (_, v) => v != "ok")
    if !failed.isEmpty then
      for (name, _) in failed do
        IO.eprintln s!"FAIL {label}: {name}"
      IO.eprintln "--- rendered source ---"
      IO.eprintln src
      pure false
    else
      IO.println s!"PASS {label} ({src.length} chars)"
      pure true

def main : IO UInt32 := do
  let counterChecks : List (String × String) := [
    ("Counter: readState get()",
      "abi.encodeWithSignature(\"get()\")"),
    ("Counter: initialize()",
      "abi.encodeWithSignature(\"initialize()\")"),
    ("Counter: increment()",
      "abi.encodeWithSignature(\"increment()\")"),
    ("Counter: read-back assertion",
      "assertEq(readState(target),")
  ]
  let vvChecks : List (String × String) := [
    ("ValueVault: get_balance() readState",
      "abi.encodeWithSignature(\"get_balance()\")"),
    ("ValueVault: initialize(uint256) with arg 100",
      "abi.encodeWithSignature(\"initialize(uint256)\", 100)"),
    ("ValueVault: deposit(uint256) with arg 25",
      "abi.encodeWithSignature(\"deposit(uint256)\", 25)"),
    ("ValueVault: charge_fee(uint256,uint256) with args",
      "abi.encodeWithSignature(\"charge_fee(uint256, uint256)\", 100, 250)"),
    ("ValueVault: balance read-back",
      "assertEq(readState(target), 100);")
  ]
  let r1 ← runCase "Counter" ProofForge.IR.Examples.Counter.module counterCfg counterTrace counterChecks
  let r2 ← runCase "ValueVault" ProofForge.IR.Examples.ValueVault.module valueVaultCfg valueVaultTrace vvChecks
  if r1 && r2 then
    IO.println "PASS EvmReplaySmoke"
    pure 0
  else
    IO.eprintln "FAIL EvmReplaySmoke"
    pure 1

end Tests.Quint.EvmReplaySmoke

def main : IO UInt32 := Tests.Quint.EvmReplaySmoke.main