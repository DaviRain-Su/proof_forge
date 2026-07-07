/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# NearReplay — Tier C-diff replay shim for the NEAR (WasmNear) backend

This is the Step A type-only stub from RFC 0014 Phase 5, Path 5a
(see `docs/quint-cdiff-multi-backend-design.md`). It generalizes the EVM C-diff
shim (`ProofForge.Backend.Quint.EvmReplay.lean`) to NEAR: the same Quint MBT ITF
traces that `Replay.replayTrace` consumes for Tier A (IR self-replay) are rendered
into a `runtime/offline-host` CLI argument list that replays the trace against the
emitted WAT artifact.

The shim is **not** wired into any `*-backend-replay-gate.sh` and does not spawn
the offline-host. It only renders the arg list deterministically and provides the
type definitions. Step B (the wrapping test that spawns `quint` + offline-host,
the gate script, the `justfile` recipe) is a follow-up.

Design shape (v1, mirrors `EvmReplay` v1):

- Config: `watPath`, `primaryStateExport` (Wasm export used to read back primary
  state, e.g. "get"), `primaryStateVar` (ITF/IR state variable name being checked).
- `renderOfflineHostArgs`: lower `(IR.Module, ITF.Trace, NearReplayConfig)` to a
  single string of the form

    ```
    run <wat> <export1> <export2> ... <exportN> --inputs-hex <hex1>,<hex2>,...,<hexN>
    ```

  where each `exportI` is a trace step's entrypoint name and `hexI` is the
  little-endian encoding of that step's IR arguments (empty for nullary
  entrypoints). After each mutating step a trailing `primaryStateExport` call is
  appended (v1 read-back-after-each-step, matching `EvmReplay` v1).

The chain-neutral trace interpretation (`resolveActionName`, `entrypointMap`,
`buildArgs`, `itfValueToIr`) is imported unchanged from `Replay.lean`.
-/

import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Replay

namespace ProofForge.Backend.Quint.NearReplay

open ProofForge.IR.Semantics
open ProofForge.Backend.Quint.Replay

structure NearReplayError where
  message : String

/-- Per-backend config: where the WAT artifact lives and how to observe primary
state. Mirrors `EvmReplayConfig` but with a Wasm export name instead of a
Solidity getter signature. -/
structure NearReplayConfig where
  watPath : String
  primaryStateExport : String
  primaryStateVar : String

/-- Encode an IR scalar value as little-endian bytes (the NEAR offline-host input
format, matching `ScenarioStep.portable_input_bytes_le` in the testkit core).
Only scalar argument types are supported in v1; aggregates are deferred. -/
def encodeArgLe (v : Value) : Except NearReplayError String :=
  match v with
  | .u8 n => .ok (toLeHex 1 n)
  | .u32 n => .ok (toLeHex 4 n)
  | .u64 n => .ok (toLeHex 8 n)
  | .u128 n => .ok (toLeHex 16 n)
  | .bool b => .ok (toLeHex 1 (if b then 1 else 0))
  | .address n => .ok (toLeHex 8 n)
  | .hash a b c d =>
      -- 32 bytes: a||b||c||d, each 8 bytes little-endian
      let s := toLeHex 8 a ++ toLeHex 8 b ++ toLeHex 8 c ++ toLeHex 8 d
      .ok s
  | .unit => .ok ""
  | other => .error { message := s!"NearReplay v1 cannot encode argument: {repr other}" }
where
  toLeHex (byteLen : Nat) (n : Nat) : String :=
    let bytes := (List.range byteLen).map (fun i => (n / (256 ^ i)) % 256)
    String.intercalate "" (bytes.map (fun b => Nat.toDigits 16 b |>.foldl (fun acc d => acc ++ s!"{d}") ""))

/-- Encode an array of IR argument values as a single hex string (concatenated
little-endian bytes). -/
def encodeArgsLe (args : Array Value) : Except NearReplayError String := do
  let mut out := ""
  for arg in args do
    out := out ++ (← encodeArgLe arg)
  pure out

/-- Whether an entrypoint is a read (returns a non-unit value) vs a mutating call.
Used to decide whether to append a trailing getter read-back (v1). -/
def isReadEntrypoint (ep : ProofForge.IR.Entrypoint) : Bool :=
  ep.returns != .unit && !ep.params.isEmpty == false || (ep.returns != .unit && ep.params.isEmpty)

/-- Render the offline-host argument list for one trace step. Returns the export
name to invoke and its hex input (empty string for nullary entrypoints). -/
def renderStep (irModule : ProofForge.IR.Module)
    (epMap : Std.HashMap String ProofForge.IR.Entrypoint) (state : ITF.State)
    : Except NearReplayError (String × String) := do
  let actionName ← resolveActionName irModule state.actionTaken state.nondetPicks
    |>.mapError (fun err => { message := err.message })
  if actionName == "init" then
    -- NEAR `initialize` is a normal export; the offline-host persists state across
    -- calls, so init runs first. If the module's `initialize` takes args (e.g.
    -- ValueVault's `initialize(initial)`), encode them from the ITF nondet picks;
    -- for nullary `initialize` (Counter) the hex is empty, matching the v1 path.
    match Std.HashMap.get? epMap "initialize" with
    | some ep =>
      let args ← buildArgs ep state.nondetPicks
        |>.mapError (fun err => { message := err.message })
      let hex ← encodeArgsLe args
      pure ("initialize", hex)
    | none => pure ("initialize", "")
  else
    let entrypoint ← match Std.HashMap.get? epMap actionName with
      | some ep => .ok ep
      | none => .error { message := s!"unknown entrypoint `{actionName}` for NEAR replay" }
    let args ← buildArgs entrypoint state.nondetPicks
      |>.mapError (fun err => { message := err.message })
    let hex ← encodeArgsLe args
    pure (entrypoint.name, hex)

/-- Render the full offline-host argument list for a trace (v1: mutating step +
trailing getter read-back). The result is a single string suitable for passing
to `cargo run --manifest-path runtime/offline-host/Cargo.toml -- <args>`. -/
def renderOfflineHostArgs (irModule : ProofForge.IR.Module) (trace : ITF.Trace)
    (cfg : NearReplayConfig) : Except NearReplayError String := do
  if trace.states.isEmpty then
    .error { message := "empty ITF trace" }
  let epMap := entrypointMap irModule
  let mut exports : List String := [cfg.watPath]
  let mut inputs : List String := []
  for state in trace.states.tail! do
    let (exportName, hex) ← renderStep irModule epMap state
    exports := exports.concat exportName
    inputs := inputs.concat hex
    -- v1 read-back-after-each-step: append a getter call after each step so the
    -- offline-host stdout carries the observable state for comparison.
    exports := exports.concat cfg.primaryStateExport
    inputs := inputs.concat ""
  let hasInputs := inputs.any (fun s => !s.isEmpty)
  let base := String.intercalate " " (["run"] ++ exports)
  if hasInputs then
    pure (base ++ " --inputs-hex " ++ String.intercalate "," inputs)
  else
    pure base

end ProofForge.Backend.Quint.NearReplay