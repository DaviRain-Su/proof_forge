import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Lower

namespace ProofForge.Backend.Quint.Replay

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Backend.Quint

structure ReplayError where
  message : String

def ReplayError.render (err : ReplayError) : String := err.message

/-- Quint encodes optional nondet picks as `{ tag: "Some", value: ... }`.
    Unwrap the inner value, or fail on None/unexpected shapes. -/
def unwrapItfOption (v : ITF.Value) : Except ReplayError ITF.Value :=
  match v with
  | .map entries =>
      match entries.find? (fun (k, _) => k == .str "tag") with
      | some (_, .str "Some") =>
          match entries.find? (fun (k, _) => k == .str "value") with
          | some (_, v) => .ok v
          | none => .error { message := "ITF Some value missing value field" }
      | some (_, .str "None") =>
          .error { message := "unexpected None in ITF nondet pick" }
      | _ =>
          .error { message := s!"cannot convert ITF value to IR: {repr entries}" }
  | other => .ok other

/-- Convert an ITF value to an IR scalar Value. Defaults to U64 for integers. -/
def itfValueToIr (t : ValueType) : ITF.Value → Except ReplayError ProofForge.IR.Semantics.Value
  | .int n =>
      match t with
      | .u8 => .ok (.u8 n)
      | .u32 => .ok (.u32 n)
      | .u64 => .ok (.u64 n)
      | .u128 => .ok (.u128 n)
      | .bool => .ok (.bool (n != 0))
      | _ => .ok (.u64 n)
  | .bool b => .ok (.bool b)
  | .str s => .ok (.string s)
  | other => .error { message := s!"cannot convert ITF value to IR: {repr other}" }

/-- Build the initial IR state from the first ITF state using the IR module's
    state declarations to determine types. -/
def buildInitialState (module : ProofForge.IR.Module) (itfState : ITF.State) : Except ReplayError State := do
  let mut state := State.empty
  for decl in module.state do
    match itfState.vars.find? (fun (k, _) => k == decl.id) with
    | some (_, v) =>
        let v ← unwrapItfOption v
        let irv ← itfValueToIr decl.type v
        state := state.write decl.id irv
    | none =>
        -- State variable not present in ITF; zero-initialize.
        let irv ← match decl.type with
          | .bool => .ok (.bool false)
          | .u8 => .ok (.u8 0)
          | .u32 => .ok (.u32 0)
          | .u64 => .ok (.u64 0)
          | .u128 => .ok (.u128 0)
          | _ => .error { message := s!"cannot zero-initialize state variable `{decl.id}` of type {decl.type.name}" }
        state := state.write decl.id irv
  pure state

/-- Build a lookup from sanitized entrypoint name to original entrypoint. -/
def entrypointMap (module : ProofForge.IR.Module) : Std.HashMap String Entrypoint :=
  module.entrypoints.foldl (fun m ep => m.insert (sanitizeName ep.name) ep) {}

/-- Convert ITF nondet picks to IR argument values using the entrypoint's param types. -/
def buildArgs (entrypoint : Entrypoint) (picks : List (String × ITF.Value)) : Except ReplayError (Array ProofForge.IR.Semantics.Value) := do
  let mut args := #[]
  for (name, t) in entrypoint.params do
    match picks.find? (fun (k, _) => k == name) with
    | some (_, v) =>
        let v ← unwrapItfOption v
        let irv ← itfValueToIr t v
        args := args.push irv
    | none =>
      .error { message := s!"missing nondet pick for entrypoint parameter `{name}`" }
  pure args

/-- Compare two IR states by checking every expected state variable. -/
def compareStates (expected actual : State) : Except ReplayError Unit := do
  for (name, expectedValue) in expected.storage do
    match actual.read name with
    | some actualValue =>
        if expectedValue != actualValue then
          .error { message := s!"state mismatch for `{name}`: expected {repr expectedValue}, got {repr actualValue}" }
    | none =>
      .error { message := s!"state variable `{name}` missing in actual state" }

/-- Replay an ITF trace against the IR semantics and check that every step
    produces the expected state. -/
def replayTrace (module : ProofForge.IR.Module) (trace : ITF.Trace) : Except ReplayError Unit := do
  if trace.states.isEmpty then
    .error { message := "empty ITF trace" }
  let epMap := entrypointMap module
  let initState ← buildInitialState module trace.states.head!
  let rec loop (state : State) (remaining : List ITF.State) : Except ReplayError Unit :=
    match remaining with
    | [] => .ok ()
    | nextState :: rest => do
        let actionName ← match nextState.actionTaken with
          | some n => .ok n
          | none => .error { message := s!"missing actionTaken at state {nextState.index}" }
        let entrypoint ← match Std.HashMap.get? epMap actionName with
          | some ep => .ok ep
          | none => .error { message := s!"unknown entrypoint `{actionName}`" }
        let args ← buildArgs entrypoint nextState.nondetPicks
        let (actualState, _ret) ←
          if actionName == "init" then
            -- Quint `init` resets state; trust the ITF state's values for the reset.
            let resetState ← buildInitialState module nextState
            .ok (resetState, none)
          else
            match runEntrypointWithArgs state entrypoint args with
            | .ok r => .ok r
            | .error e => .error { message := s!"IR execution failed at state {nextState.index}: {e}" }
        let expectedState ← buildInitialState module nextState
        compareStates expectedState actualState
        loop actualState rest
  loop initState trace.states.tail!

end ProofForge.Backend.Quint.Replay
