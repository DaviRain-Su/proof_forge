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
      | some (_, tag) =>
          .error { message := s!"unexpected ITF option tag: {repr tag}" }
      | none => .ok (.map entries)
  | other => .ok other

def parseHashComponents (parts : List String) : Except ReplayError (Nat × Nat × Nat × Nat) := do
  match parts with
  | [a, b, c, d] =>
      match a.toNat?, b.toNat?, c.toNat?, d.toNat? with
      | some a, some b, some c, some d => .ok (a, b, c, d)
      | _, _, _, _ => .error { message := s!"invalid hash components: {parts}" }
  | _ => .error { message := s!"invalid hash literal: {parts}" }

def parseHashString (s : String) : Except ReplayError ProofForge.IR.Semantics.Value :=
  if s.startsWith "hash:" then
    parseHashComponents ((s.drop 5).toString.splitOn ":")
      |>.map (fun (a, b, c, d) => .hash a b c d)
  else
    .error { message := s!"expected hash string, got: {s}" }

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
  | .str s =>
      match t with
      | .hash => parseHashString s
      | .address => .ok (.address (s.drop 4 |>.toNat?.getD 0))
      | _ => .ok (.string s)
  | other => .error { message := s!"cannot convert ITF value to IR: {repr other}" }

def writeStructStateFromItf (decl : StateDecl) (structs : Array StructDecl) (_structDecl : StructDecl)
    (itfState : ITF.State) (state : State) : Except ReplayError State := do
  let flat := Lower.flatFieldsForStateDecl decl structs
  if flat.isEmpty then
    let mut next := state
    for field in _structDecl.fields do
      let fieldVar := Lower.structFieldVarName decl.id field.id
      match itfState.vars.find? (fun (k, _) => k == fieldVar) with
      | some (_, v) => do
          let v ← unwrapItfOption v
          let irv ← itfValueToIr field.type v
          next := next.write (fieldKey decl.id field.id) irv
      | none => .error { message := s!"missing ITF field `{fieldVar}` for struct state `{decl.id}`" }
    pure next
  else
    let mut next := state
    for field in flat do
      match itfState.vars.find? (fun (k, _) => k == field.varName) with
      | some (_, v) => do
          let v ← unwrapItfOption v
          let irv ← itfValueToIr field.type v
          next := next.write field.storageKey irv
      | none => .error { message := s!"missing ITF field `{field.varName}` for struct state `{decl.id}`" }
    pure next

def mapEntryStorageKey (declId keyStr : String) : String :=
  if keyStr.startsWith "{" then
    declId ++ keyStr
  else
    mapKey declId keyStr

def writeMapValueFromItf (valueType : ValueType) (v : ITF.Value) : Except ReplayError ProofForge.IR.Semantics.Value :=
  match valueType with
  | .hash =>
      match v with
      | .str s => parseHashString s
      | other => .error { message := s!"expected string hash map value in ITF, got: {repr other}" }
  | .u64 =>
      match v with
      | .int n => .ok (.u64 n)
      | other => .error { message := s!"expected int u64 map value in ITF, got: {repr other}" }
  | _ => itfValueToIr valueType v

def writeMapStateFromItf (decl : StateDecl) (v : ITF.Value) (state : State) : Except ReplayError State :=
  match v with
  | .map entries => do
      let mut next := state
      for (keyValue, valueValue) in entries do
        let keyStr ← match keyValue with
          | .str s => .ok s
          | other => .error { message := s!"expected string map key in ITF, got: {repr other}" }
        let irValue ← writeMapValueFromItf decl.type valueValue
        let storageKey := mapEntryStorageKey decl.id keyStr
        next := next.write storageKey irValue
        next := next.write (storageKey ++ ".present") (.bool true)
      pure next
  | _ =>
      .error { message := s!"expected ITF map for state `{decl.id}`" }

/-- Write one state declaration from an ITF value into IR storage. -/
def writeArrayStructStateFromItf (decl : StateDecl) (structs : Array StructDecl) (_cap : Nat)
    (itfState : ITF.State) (state : State) : Except ReplayError State := do
  let flat := Lower.flatFieldsForStateDecl decl structs
  if flat.isEmpty then
    .error { message := s!"array struct state `{decl.id}` has no flattened fields" }
  else
    let mut next := state
    for field in flat do
      match itfState.vars.find? (fun (k, _) => k == field.varName) with
      | some (_, v) => do
          let v ← unwrapItfOption v
          let irv ← itfValueToIr field.type v
          next := next.write field.storageKey irv
      | none => .error { message := s!"missing ITF field `{field.varName}` for array struct state `{decl.id}`" }
    pure next

def writeStateDeclFromItf (irModule : ProofForge.IR.Module) (decl : StateDecl) (v : ITF.Value) (state : State)
    (itfState : ITF.State) : Except ReplayError State :=
  match decl.kind with
  | StateKind.array cap =>
      match decl.type with
      | .structType typeName =>
          match Lower.lookupStructDecl irModule.structs typeName with
          | some _ => writeArrayStructStateFromItf decl irModule.structs cap itfState state
          | none =>
              match v with
              | .list values =>
                  if values.length != cap then
                    .error { message := s!"ITF list length {values.length} != array capacity {cap} for `{decl.id}`" }
                  else
                    (values.zip (List.range values.length)).foldlM (fun st (elem, index) => do
                      let irv ← itfValueToIr decl.type elem
                      pure (st.write (arrayKey decl.id index) irv)) state
              | _ =>
                  .error { message := s!"expected ITF list for array state `{decl.id}`" }
      | _ =>
          match v with
          | .list values =>
              if values.length != cap then
                .error { message := s!"ITF list length {values.length} != array capacity {cap} for `{decl.id}`" }
              else
                (values.zip (List.range values.length)).foldlM (fun st (elem, index) => do
                  let irv ← itfValueToIr decl.type elem
                  pure (st.write (arrayKey decl.id index) irv)) state
          | _ =>
              .error { message := s!"expected ITF list for array state `{decl.id}`" }
  | ProofForge.IR.StateKind.map _ _ =>
      writeMapStateFromItf decl v state
  | _ =>
      match decl.type with
      | .structType typeName =>
          match Lower.lookupStructDecl irModule.structs typeName with
          | some structDecl => writeStructStateFromItf decl irModule.structs structDecl itfState state
          | none => do
              let irv ← itfValueToIr decl.type v
              .ok (state.write decl.id irv)
      | _ => do
          let irv ← itfValueToIr decl.type v
          .ok (state.write decl.id irv)

def zeroArrayStructField (fieldType : ValueType) : Except ReplayError ProofForge.IR.Semantics.Value :=
  match fieldType with
  | .bool => .ok (.bool false)
  | .u8 => .ok (.u8 0)
  | .u32 => .ok (.u32 0)
  | .u64 => .ok (.u64 0)
  | .u128 => .ok (.u128 0)
  | .hash => .ok (.hash 0 0 0 0)
  | _ => .error { message := s!"cannot zero-initialize array struct field type {fieldType.name}" }

def zeroStateDecl (irModule : ProofForge.IR.Module) (decl : StateDecl) : Except ReplayError State := do
  match decl.kind with
  | StateKind.array cap =>
      match decl.type with
      | .structType _ =>
          let flat := Lower.flatFieldsForStateDecl decl irModule.structs
          if !flat.isEmpty then do
              let mut st := State.empty
              for field in flat do
                let irv ← zeroArrayStructField field.type
                st := st.write field.storageKey irv
              .ok st
          else do
              let mut st := State.empty
              for index in [0:cap] do
                let irv ← match decl.type with
                  | .bool => .ok (.bool false)
                  | .u8 => .ok (.u8 0)
                  | .u32 => .ok (.u32 0)
                  | .u64 => .ok (.u64 0)
                  | .u128 => .ok (.u128 0)
                  | _ => .error { message := s!"cannot zero-initialize array element type for `{decl.id}`" }
                st := st.write (arrayKey decl.id index) irv
              .ok st
      | _ => do
          let mut st := State.empty
          for index in [0:cap] do
            let irv ← match decl.type with
              | .bool => .ok (.bool false)
              | .u8 => .ok (.u8 0)
              | .u32 => .ok (.u32 0)
              | .u64 => .ok (.u64 0)
              | .u128 => .ok (.u128 0)
              | _ => .error { message := s!"cannot zero-initialize array element type for `{decl.id}`" }
            st := st.write (arrayKey decl.id index) irv
          .ok st
  | ProofForge.IR.StateKind.map _ _ => .ok State.empty
  | _ =>
      match decl.type with
      | .structType typeName =>
          let flat := Lower.flatFieldsForStateDecl decl irModule.structs
          if !flat.isEmpty then do
              let mut st := State.empty
              for field in flat do
                let irv ← zeroArrayStructField field.type
                st := st.write field.storageKey irv
              .ok st
          else
            match Lower.lookupStructDecl irModule.structs typeName with
            | some structDecl => do
                let mut st := State.empty
                for field in structDecl.fields do
                  let irv ← match field.type with
                    | .bool => .ok (.bool false)
                    | .u8 => .ok (.u8 0)
                    | .u32 => .ok (.u32 0)
                    | .u64 => .ok (.u64 0)
                    | .u128 => .ok (.u128 0)
                    | _ => .error { message := s!"cannot zero-initialize struct field `{decl.id}.{field.id}`" }
                  st := st.write (fieldKey decl.id field.id) irv
                .ok st
            | none => .error { message := s!"unknown struct type `{typeName}` for state `{decl.id}`" }
      | _ => do
          let irv ← match decl.type with
            | .bool => .ok (.bool false)
            | .u8 => .ok (.u8 0)
            | .u32 => .ok (.u32 0)
            | .u64 => .ok (.u64 0)
            | .u128 => .ok (.u128 0)
            | .hash => .ok (.hash 0 0 0 0)
            | _ => .error { message := s!"cannot zero-initialize state variable `{decl.id}` of type {decl.type.name}" }
          .ok (State.empty.write decl.id irv)

/-- Build the initial IR state from the first ITF state using the IR module's
    state declarations to determine types. -/
def usesFlattenedItfVars (decl : StateDecl) : Bool :=
  match decl.type with
  | .structType _ => true
  | _ =>
      match decl.kind with
      | .array _ =>
          match decl.type with
          | .structType _ => true
          | _ => false
      | _ => false

def buildInitialState (module : ProofForge.IR.Module) (itfState : ITF.State) : Except ReplayError State := do
  let mut state := State.empty
  for decl in module.state do
    if usesFlattenedItfVars decl then
      state ← writeStateDeclFromItf module decl (.map []) state itfState
    else
      match itfState.vars.find? (fun (k, _) => k == decl.id) with
      | some (_, v) =>
          let v ← unwrapItfOption v
          state ← writeStateDeclFromItf module decl v state itfState
      | none =>
          let zeroed ← zeroStateDecl module decl
          for (key, value) in zeroed.storage do
            state := state.write key value
  pure state

/-- Build a lookup from sanitized entrypoint name to original entrypoint. -/
def entrypointMap (module : ProofForge.IR.Module) : Std.HashMap String Entrypoint :=
  module.entrypoints.foldl (fun m ep => m.insert (sanitizeName ep.name) ep) {}

/-- Quint MBT sometimes leaves `mbt::actionTaken` empty for `step = any { nondet ... call }`. -/
def nondetPickPresent (v : ITF.Value) : Bool :=
  match v with
  | .map entries =>
      match entries.find? (fun (k, _) => k == .str "tag") with
      | some (_, .str "Some") => true
      | _ => false
  | _ => false

def inferActionFromPicks (module : ProofForge.IR.Module) (picks : List (String × ITF.Value)) :
    Except ReplayError String := do
  let candidates := module.entrypoints.filter (fun ep =>
    !ep.params.isEmpty &&
    ep.params.all (fun (n, _) =>
      match picks.find? (fun (k, _) => k == n) with
      | some (_, v) => nondetPickPresent v
      | none => false))
  match candidates.toList with
  | [] => .error { message := "cannot infer entrypoint from nondet picks" }
  | [ep] => .ok (sanitizeName ep.name)
  | _ => .error { message := "ambiguous entrypoint inference from nondet picks" }

def resolveActionName (module : ProofForge.IR.Module) (actionTaken : Option String)
    (picks : List (String × ITF.Value)) : Except ReplayError String :=
  match actionTaken with
  | some name =>
      if name.isEmpty then
        inferActionFromPicks module picks
      else
        .ok name
  | none => .error { message := "missing actionTaken in ITF state" }

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
        let actionName ← resolveActionName module nextState.actionTaken nextState.nondetPicks
        let entrypoint ← match Std.HashMap.get? epMap actionName with
          | some ep => .ok ep
          | none => .error { message := s!"unknown entrypoint `{actionName}`" }
        let args ← buildArgs entrypoint nextState.nondetPicks
        let (actualState, _ret) ←
          if actionName == "init" then
            let resetState ← buildInitialState module nextState
            .ok (resetState, none)
          else
            match runEntrypointWithArgs state entrypoint args module.structs with
            | .ok r => .ok r
            | .error e => .error { message := s!"IR execution failed at state {nextState.index}: {e}" }
        let expectedState ← buildInitialState module nextState
        compareStates expectedState actualState
        loop actualState rest
  loop initState trace.states.tail!

end ProofForge.Backend.Quint.Replay