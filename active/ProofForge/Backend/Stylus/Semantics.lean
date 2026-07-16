/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.Plan

namespace ProofForge.Backend.Stylus.Semantics

open ProofForge.Backend.Stylus

abbrev Word := StylusBytes

structure Context where
  sender : Word := #[]
  value : Word := #[]
  blockNumber : Nat := 0
  timestamp : Nat := 0
  deriving Repr, BEq

inductive TraceEvent where
  | storageLoad (slot value : Word)
  | storageCache (slot value : Word)
  | storageFlush (writes : Nat)
  | result (bytes : Word)
  | revert (bytes : Word)
  deriving Repr, BEq

structure HostState where
  storage : Array (Word × Word) := #[]
  cache : Array (Word × Word) := #[]
  calldata : Word := #[]
  result : Word := #[]
  revertData : Word := #[]
  logs : Array Word := #[]
  calls : Array Word := #[]
  context : Context := {}
  gas : Nat := 0
  ink : Nat := 0
  trace : Array TraceEvent := #[]
  deriving Repr, BEq

private def lookup (entries : Array (Word × Word)) (slot : Word) : Option Word :=
  (entries.find? fun entry => entry.1 == slot).map (fun entry => entry.2)

private def insert (entries : Array (Word × Word)) (slot value : Word) : Array (Word × Word) :=
  if entries.any (fun entry => entry.1 == slot) then
    entries.map fun entry => if entry.1 == slot then (slot, value) else entry
  else entries.push (slot, value)

def storageLoad (state : HostState) (slot : Word) : HostState × Word :=
  let value := (lookup state.cache slot).orElse (fun _ => lookup state.storage slot) |>.getD #[]
  ({ state with trace := state.trace.push (.storageLoad slot value) }, value)

def storageCache (state : HostState) (slot value : Word) : HostState :=
  { state with
    cache := insert state.cache slot value
    trace := state.trace.push (.storageCache slot value) }

def storageFlush (state : HostState) : HostState :=
  let committed := state.cache.foldl (fun storage entry => insert storage entry.1 entry.2) state.storage
  { state with
    storage := committed
    cache := #[]
    trace := state.trace.push (.storageFlush state.cache.size) }

def finish (state : HostState) (bytes : Word) : HostState :=
  { state with result := bytes, revertData := #[], trace := state.trace.push (.result bytes) }

def revert (state : HostState) (bytes : Word) : HostState :=
  { state with
    cache := #[]
    result := #[]
    revertData := bytes
    trace := state.trace.push (.revert bytes) }

def encodeU64 (value : Nat) : Word :=
  (List.range 32).toArray.map fun index =>
    UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

def decodeU64 (word : Word) : Nat :=
  word.foldl (fun value byte => value * 256 + byte.toNat) 0

def overflowBytes : Word := "checked arithmetic overflow".toUTF8.data

inductive CounterCall where
  | initialize | increment | get
  deriving Repr, BEq, DecidableEq

def CounterCall.name : CounterCall -> String
  | .initialize => "initialize" | .increment => "increment" | .get => "get"

def slotZero : Word := encodeU64 0

def executeCounter (plan : StylusPlan) (state : HostState) (call : CounterCall) :
    Except String HostState := do
  let some method := plan.abi.methods.find? (fun method => method.name == call.name)
    | .error s!"Stylus Counter plan has no `{call.name}` method"
  let state := { state with calldata := method.selector, result := #[], revertData := #[], trace := #[] }
  match call with
  | .initialize =>
      pure <| finish (storageFlush (storageCache state slotZero (encodeU64 0))) #[]
  | .increment =>
      let (state, currentWord) := storageLoad state slotZero
      let current := decodeU64 currentWord
      if current == 2 ^ 64 - 1 then
        pure <| revert state overflowBytes
      else
        pure <| finish (storageFlush (storageCache state slotZero (encodeU64 (current + 1)))) #[]
  | .get =>
      let (state, currentWord) := storageLoad state slotZero
      pure <| finish state (encodeU64 (decodeU64 currentWord))

end ProofForge.Backend.Stylus.Semantics
