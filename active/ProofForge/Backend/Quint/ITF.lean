import Lean.Data.Json

namespace ProofForge.Backend.Quint.ITF

open Lean

/-- A parsed ITF value. Integers are represented as Nat (bounded models
    keep them small). -/
inductive Value where
  | int (value : Nat)
  | bool (value : Bool)
  | str (value : String)
  | set (values : List Value)
  | list (values : List Value)
  | map (entries : List (Value × Value))
  deriving Repr, BEq

structure State where
  index : Nat
  actionTaken : Option String
  nondetPicks : List (String × Value)
  vars : List (String × Value)
  deriving Repr, BEq, Inhabited

structure Trace where
  vars : List String
  states : List State
  deriving Repr, BEq, Inhabited

partial def parseValue (json : Json) : Except String Value := do
  if let .ok n := json.getNat? then
    .ok (.int n)
  else if let .ok b := json.getBool? then
    .ok (.bool b)
  else if let .ok s := json.getStr? then
    .ok (.str s)
  else if let .ok arr := json.getArr? then
    let vs ← arr.toList.mapM parseValue
    .ok (.list vs)
  else if let .ok obj := json.getObj? then
    if let .ok (Json.str n) := Json.getObjVal? json "#bigint" then
      match n.toNat? with
      | some n => .ok (.int n)
      | none => .error s!"invalid #bigint value: {n}"
    else if let .ok (Json.arr pairs) := Json.getObjVal? json "#map" then
      let entries ← pairs.toList.mapM (fun pairJson => do
        match pairJson.getArr? with
        | .ok arr =>
            if arr.size != 2 then
              .error s!"expected map pair of length 2, got: {pairJson.compress}"
            else
              let k ← parseValue arr[0]!
              let v ← parseValue arr[1]!
              pure (k, v)
        | .error e => .error s!"expected map pair array in #map: {e}")
      .ok (.map entries)
    else
      let entries ← Std.TreeMap.Raw.toList obj |>.mapM (fun (k, v) => do
        let pv ← parseValue v
        pure (.str k, pv))
      .ok (.map entries)
  else
    .error s!"unsupported ITF value: {json.compress}"

def parseState (json : Json) : Except String State := do
  let obj ← Json.getObj? json
  let metaJson ← Json.getObjVal? json "#meta"
  let index ← do
    let idxJson ← Json.getObjVal? metaJson "index"
    match idxJson.getNat? with
    | .ok n => pure n
    | .error e => .error s!"non-integer #meta.index in ITF state: {e}"
  let actionTaken :=
    match Json.getObjVal? json "mbt::actionTaken" with
    | .ok j => j.getStr? |>.toOption
    | .error _ => none
  let nondetPicks ← match Json.getObjVal? json "mbt::nondetPicks" with
    | .ok (Json.obj picks) =>
        Std.TreeMap.Raw.toList picks |>.mapM (fun (k, v) => do
          let pv ← parseValue v
          pure (k, pv))
    | .ok other => .error s!"expected object for mbt::nondetPicks, got: {other.compress}"
    | .error _ => .ok []
  let vars ← Std.TreeMap.Raw.toList obj |>.filterMapM (fun (k, v) =>
    if k == "#meta" || k == "mbt::actionTaken" || k == "mbt::nondetPicks" then
      .ok none
    else do
      let pv ← parseValue v
      .ok (some (k, pv)))
  pure { index, actionTaken, nondetPicks, vars }

def parseTrace (json : Json) : Except String Trace := do
  let varsJson ← Json.getObjVal? json "vars"
  let vars ← match varsJson.getArr? with
    | .ok vs => .ok (vs.toList.filterMap (fun v => v.getStr? |>.toOption))
    | .error e => .error s!"missing vars array in ITF trace: {e}"
  let statesJson ← Json.getObjVal? json "states"
  let states ← match statesJson.getArr? with
    | .ok ss => ss.toList.mapM parseState
    | .error e => .error s!"missing states array in ITF trace: {e}"
  pure { vars, states }

def parse (jsonString : String) : Except String Trace := do
  let json ← match Json.parse jsonString with
    | .ok j => .ok j
    | .error e => .error s!"JSON parse error: {e}"
  parseTrace json

end ProofForge.Backend.Quint.ITF
