import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.Lower

set_option linter.unusedVariables false

open ProofForge.IR (ValueType Literal Statement Entrypoint StateDecl StructDecl Effect AssignOp StoragePathSegment)
open ProofForge.Backend.Quint

structure LowerError where
  message : String

def LowerError.render (err : LowerError) : String := err.message

/-- Quint reserved words that cannot be used as action or variable names. -/
abbrev LocalEnv := List (String × Expr)

def LocalEnv.lookup (name : String) (env : LocalEnv) : Option Expr :=
  match env with
  | [] => none
  | (k, v) :: rest =>
      if k == name then some v else LocalEnv.lookup name rest

def LocalEnv.bind (name : String) (value : Expr) (env : LocalEnv) : LocalEnv :=
  (name, value) :: env

def LocalEnv.upsert (name : String) (value : Expr) (env : LocalEnv) : LocalEnv :=
  match env with
  | [] => [(name, value)]
  | (k, v) :: rest =>
      if k == name then (name, value) :: rest else (k, v) :: LocalEnv.upsert name value rest

/-- Lowering context: local bindings, shadowed state values, and guards. -/
structure LowerCtx where
  locals : LocalEnv := []
  state : LocalEnv := []
  /-- Parallel slot expressions rebuilt from `.local` bases for return cross-checks. -/
  mutationTrack : LocalEnv := []
  /-- Storage-path effects applied in the current entrypoint body (for return expectations). -/
  effectTrace : Array Effect := #[]
  guards : Array ActionClause := #[]
  stateDecls : Array StateDecl := #[]
  structs : Array StructDecl := #[]
  pureDefs : Array PureDef := #[]
  maxLoopUnroll : Nat := 10
  /-- When false, `__while_*` step locals stay symbolic during unrolling. -/
  expandLocals : Bool := true
  /-- Entrypoint parameter types for crosscall arg coercion during lowering. -/
  paramTypes : Array (String × ValueType) := #[]
  /-- Local binding types for aggregate crosscall argument flattening. -/
  localTypes : Array (String × ValueType) := #[]

def hashLiteralStr (a b c d : Nat) : String :=
  s!"hash:{a}:{b}:{c}:{d}"

def structFieldVarName (stateId fieldName : String) : String :=
  s!"{stateId}_{fieldName}"

def nestedFieldVarName (varPrefix : String) (path : List String) : String :=
  match path with
  | [] => varPrefix
  | _ => varPrefix ++ "_" ++ String.intercalate "_" path

def arrayStructFieldVarName (stateId : String) (index : Nat) (fieldName : String) : String :=
  s!"{stateId}_{index}_{fieldName}"

def arrayNestedFieldVarName (stateId : String) (index : Nat) (path : List String) : String :=
  nestedFieldVarName (s!"{stateId}_{index}") path

def lookupStructDecl (structs : Array StructDecl) (name : String) : Option StructDecl :=
  structs.find? (fun s => s.name == name)

structure FlatStateField where
  varName : String
  storageKey : String
  type : ValueType

partial def flattenStructFields (structs : Array StructDecl) (varPrefix storagePrefix : String)
    (structDecl : StructDecl) : Array FlatStateField :=
  structDecl.fields.foldl (fun acc field =>
    let fieldVar := nestedFieldVarName varPrefix [field.id]
    let fieldStorage := storagePrefix ++ "." ++ field.id
    match field.type, field.isRef with
    | .structType typeName, true =>
      match lookupStructDecl structs typeName with
      | some inner => acc ++ flattenStructFields structs fieldVar fieldStorage inner
      | none => acc.push { varName := fieldVar, storageKey := fieldStorage, type := field.type }
    | ty, _ =>
      acc.push { varName := fieldVar, storageKey := fieldStorage, type := ty }) #[]

def collectFieldPathSegments (segments : List StoragePathSegment) : Option (List String) :=
  let rec go (rest : List StoragePathSegment) (acc : List String) : Option (List String) :=
    match rest with
    | [] => some acc
    | .field fieldName :: rest => go rest (acc ++ [fieldName])
    | _ => none
  go segments []

def irExprNat? (e : ProofForge.IR.Expr) : Option Nat :=
  match e with
  | .literal (.u8 n) | .literal (.u32 n) | .literal (.u64 n) | .literal (.u128 n) => some n
  | _ => none

inductive StoragePathTarget where
  | flatVar (name : String)
  | nestedStructRef (varPrefix : String) (structType : String)
  | arraySlot (stateId : String) (cap : Nat) (index : ProofForge.IR.Expr)
  | arrayStructFieldSlot (stateId : String) (cap : Nat) (index : ProofForge.IR.Expr) (fieldName : String)
  | arrayNestedFieldSlot (stateId : String) (cap : Nat) (index : ProofForge.IR.Expr)
      (fieldPath : List String)
  | mapKeyPath (stateId : String) (keys : Array ProofForge.IR.Expr)
  deriving Repr, Nonempty

def mapPathKeys? (segments : List StoragePathSegment) : Option (Array ProofForge.IR.Expr) :=
  let rec go (rest : List StoragePathSegment) (acc : Array ProofForge.IR.Expr) :
      Option (Array ProofForge.IR.Expr) :=
    match rest with
    | [] => some acc
    | .mapKey key :: rest => go rest (acc.push key)
    | _ => none
  go segments #[]

def storagePathStartType (state : StateDecl) (path : Array StoragePathSegment) :
    Except LowerError (ValueType × List StoragePathSegment) :=
  match state.kind with
  | .scalar =>
      match path.toList with
      | .mapKey _ :: _ =>
          .error { message := s!"storage path state `{state.id}` is scalar storage, not map storage" }
      | segments => .ok (state.type, segments)
  | .array length =>
      if length == 0 then
        .error { message := s!"array state `{state.id}` must have non-zero length" }
      else
        match path.toList with
        | .mapKey _ :: _ =>
            .error { message := s!"storage path state `{state.id}` is array storage, not map storage" }
        | segments => .ok (.fixedArray state.type length, segments)
  | .map _ capacity =>
      if capacity == 0 then
        .error { message := s!"map state `{state.id}` must have non-zero capacity" }
      else
        match path.toList with
        | .mapKey _ :: _ => .error { message := "map storage paths are resolved separately" }
        | _ =>
            .error { message := s!"storage path state `{state.id}` is map storage; path must be a map key" }
  | .dynamicArray =>
      .error { message := s!"storage path state `{state.id}` is dynamic array storage; not supported in Quint lowering v1" }

partial def resolveStoragePathSegments (structs : Array StructDecl) (namePrefix : String)
    (current : ValueType) (segments : List StoragePathSegment) : Except LowerError StoragePathTarget :=
  match segments with
  | [] =>
      .error { message := s!"storage path for `{namePrefix}` must contain at least one segment" }
  | [.field fieldName] =>
      match current with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some decl =>
              match decl.fields.find? (fun f => f.id == fieldName) with
              | some { type := .structType innerName, isRef := true, .. } =>
                  .ok (.nestedStructRef (nestedFieldVarName namePrefix [fieldName]) innerName)
              | some _ =>
                  .ok (.flatVar (nestedFieldVarName namePrefix [fieldName]))
              | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"storage path references unknown struct `{typeName}`" }
      | other => .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | [.index index] =>
      match current with
      | .fixedArray (.structType _) _ =>
          .error { message := s!"storage path index on struct array `{namePrefix}` requires a following field segment" }
      | .fixedArray _ length => .ok (.arraySlot namePrefix length index)
      | other => .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | [.index index, .field fieldName] =>
      match current with
      | .fixedArray (.structType _) length =>
          match irExprNat? index with
          | some n =>
              if n >= length then
                .error { message := s!"storage path index {n} out of bounds for array `{namePrefix}` (length {length})" }
              else
                .ok (.flatVar (arrayStructFieldVarName namePrefix n fieldName))
          | none => .ok (.arrayStructFieldSlot namePrefix length index fieldName)
      | .fixedArray element length =>
          .error { message := s!"storage path field `{fieldName}` after index cannot be selected from `{element.name}`" }
      | other =>
          .error { message := s!"storage path index+field cannot be selected from `{other.name}`" }
  | .field fieldName :: _ =>
      match current with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some decl =>
              match decl.fields.find? (fun f => f.id == fieldName) with
              | some field =>
                  resolveStoragePathSegments structs (nestedFieldVarName namePrefix [fieldName])
                    field.type segments.tail!
              | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"storage path references unknown struct `{typeName}`" }
      | other => .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | .index index :: rest =>
      match current with
      | .fixedArray element length =>
          match irExprNat? index with
          | some n =>
              if n >= length then
                .error { message := s!"storage path index {n} out of bounds for array `{namePrefix}` (length {length})" }
              else
                resolveStoragePathSegments structs (s!"{namePrefix}_{n}") element rest
          | none =>
              match collectFieldPathSegments rest with
              | some fieldPath => .ok (.arrayNestedFieldSlot namePrefix length index fieldPath)
              | none =>
                  .error { message := s!"dynamic storage path index on `{namePrefix}` requires field segments" }
      | other => .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | .mapKey _ :: _ =>
      .error { message := "map-key segments on non-map storage paths are not supported in Quint lowering v1" }

def resolveStoragePathTarget (structs : Array StructDecl) (state : StateDecl)
    (path : Array StoragePathSegment) : Except LowerError StoragePathTarget := do
  if path.isEmpty then
    .error { message := s!"storage path for state `{state.id}` must contain at least one segment" }
  match state.kind, path.toList with
  | .map _ _, segments =>
      match mapPathKeys? segments with
      | some keys =>
          if keys.isEmpty then
            .error { message := s!"map storage path for `{state.id}` must contain at least one mapKey segment" }
          else
            .ok (.mapKeyPath state.id keys)
      | none =>
          .error { message := s!"map storage path for `{state.id}` must be consecutive mapKey segments" }
  | _, _ => do
      let (start, segments) ← storagePathStartType state path
      resolveStoragePathSegments structs state.id start segments

def flatFieldsForStateDecl (decl : StateDecl) (structs : Array StructDecl) : Array FlatStateField :=
  match decl.kind with
  | .array cap =>
      match decl.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl =>
              (List.range cap).foldl (fun acc index =>
                acc ++ flattenStructFields structs (s!"{decl.id}_{index}") (s!"{decl.id}[{index}]") structDecl) #[]
          | none => #[]
      | _ => #[]
  | .scalar | .dynamicArray =>
      match decl.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => flattenStructFields structs decl.id decl.id structDecl
          | none => #[]
      | _ => #[]
  | .map _ _ => #[]

def stateVarEntries (decl : StateDecl) (structs : Array StructDecl) :
    Except LowerError (Array (String × ValueType)) := do
  let flat := flatFieldsForStateDecl decl structs
  if !flat.isEmpty then
    .ok (flat.map (fun f => (f.varName, f.type)))
  else
    match decl.kind with
    | .array _ | .scalar | .dynamicArray => pure #[(decl.id, decl.type)]
    | .map _ _ => pure #[(decl.id, decl.type)]

def mapKeysExpr (mapExpr : Expr) : Expr :=
  .methodCall mapExpr "keys" #[]

def mapContainsExpr (key mapExpr : Expr) : Expr :=
  .methodCall key "in" #[mapKeysExpr mapExpr]

def emptyMapExpr : Expr :=
  .app "Map" #[]

def hashZeroExpr : Expr :=
  .literalStr (hashLiteralStr 0 0 0 0)

def expandedStateIds (state : Array StateDecl) (structs : Array StructDecl) : Array String :=
  Id.run do
    let mut ids := #[]
    for decl in state do
      match stateVarEntries decl structs with
      | .ok entries => ids := ids ++ entries.map Prod.fst
      | .error _ => ids := ids.push decl.id
    ids

def whileStepLocalName (stateId : String) (step : Nat) : String :=
  s!"__while_{stateId}_{step}"

def isWhileStepLocal (name : String) : Bool :=
  name.startsWith "__while_"

def LowerCtx.stateValue (ctx : LowerCtx) (stateId : String) : Expr :=
  match ctx.state.lookup stateId with
  | some value => value
  | none => .local stateId

def LowerCtx.mutationTrackValue (ctx : LowerCtx) (stateId : String) : Expr :=
  match ctx.mutationTrack.lookup stateId with
  | some value => value
  | none => .local stateId

def LowerCtx.lookupStateDecl (ctx : LowerCtx) (stateId : String) : Option StateDecl :=
  ctx.stateDecls.find? (fun s => s.id == stateId)

/-- IR and Quint both use 0-based list indices. -/
def irIndexToQuint (idx : Expr) : Expr := idx

partial def listGetAt (current : Expr) (pos : Nat) : Expr :=
  match current with
  | .listLit elems =>
      match elems[pos]? with
      | some elem => elem
      | none => .literalInt 0
  | _ =>
      .index current (.literalInt (Int.ofNat pos))

def listSetAtLiteral (current : Expr) (cap : Nat) (idx : Nat) (value : Expr) : Expr :=
  let elems := (List.range cap).map (fun pos =>
    if pos == idx then value
    else listGetAt current pos)
  .listLit elems.toArray

def listSetAtExpr (current : Expr) (cap : Nat) (idx : Expr) (value : Expr) : Expr :=
  let quintIdx := irIndexToQuint idx
  let elems := (List.range cap).map (fun pos =>
    let quintPos := .literalInt (Int.ofNat pos)
    let atPos := listGetAt current pos
    .ite (.binOp .eq quintIdx quintPos) value atPos)
  .listLit elems.toArray

def lowerType (t : ValueType) : Except LowerError QuintType := do
  match t with
  | .unit => .ok .int
  | .bool => .ok .bool
  | .u8 | .u32 | .u64 | .u128 => .ok .int
  | .address => .ok .str
  | .hash => .ok .hashStr
  | .fixedArray elem _ => .ok (.list (← lowerType elem))
  | .array elem => .ok (.list (← lowerType elem))
  | .structType _ => .ok (.map .str .int)
  | .bytes | .string =>
      .error { message := s!"unsupported IR value type for Quint lowering: {t.name}" }

def lowerStateVarType (s : StateDecl) : Except LowerError QuintType := do
  match s.kind with
  | .array _ => .ok (.list (← lowerType s.type))
  | .map _ _ => .ok (.map .str (← lowerType s.type))
  | _ => lowerType s.type

def quintStateVars (state : Array StateDecl) (structs : Array StructDecl) :
    Except LowerError (Array (String × QuintType)) := do
  let mut vars := #[]
  for decl in state do
    let entries ← stateVarEntries decl structs
    for (name, ty) in entries do
      let qtype ←
        if name == decl.id then
          lowerStateVarType decl
        else
          lowerType ty
      vars := vars.push (name, qtype)
  pure vars

def lowerLiteral (lit : Literal) : Except LowerError Expr :=
  match lit with
  | .u8 n | .u32 n | .u64 n | .u128 n => .ok (.literalInt (Int.ofNat n))
  | .bool b => .ok (.literalBool b)
  | .address n => .ok (.literalStr s!"addr{n}")
  | .hash4 a b c d => .ok (.literalStr (hashLiteralStr a b c d))
  | .bytes _ => .error { message := "Quint: bytes literal not supported" }
  | .string s => .ok (.literalStr s)

def lowerAssignOp (op : AssignOp) : BinOp :=
  match op with
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .and
  | .bitOr => .or
  | .bitXor => .or
  | .shiftLeft => .add
  | .shiftRight => .sub

def hashKeySampleStrs : Array String := #[
  "hash:1001:0:0:0",
  "hash:2002:0:0:0",
  "hash:3003:0:0:0"
]

def hashKeySamples : Array Expr :=
  hashKeySampleStrs.map .literalStr

def crosscallArgTypeFromExpr (ctx : LowerCtx) (arg : ProofForge.IR.Expr) : ValueType :=
  match arg with
  | .literal (.bool _) => .bool
  | .literal (.u32 _) => .u32
  | .literal (.u64 _) => .u64
  | .literal (.u8 _) => .u8
  | .literal (.hash4 _ _ _ _) => .hash
  | .local name =>
      match ctx.localTypes.find? (fun (n, _) => n == name) with
      | some (_, ty) => ty
      | none =>
          ctx.paramTypes.find? (fun (n, _) => n == name) |>.map Prod.snd |>.getD .u64
  | _ => .u64

def hashExprToStubInt (hashExpr : Expr) : Expr :=
  .ite (.binOp .eq hashExpr (.literalStr "hash:1001:0:0:0")) (.literalInt 1001)
    (.ite (.binOp .eq hashExpr (.literalStr "hash:2002:0:0:0")) (.literalInt 2002)
      (.literalInt 3003))

def crosscallArgToIntExpr (raw : Expr) (argType : ValueType) : Expr :=
  match argType with
  | .hash => hashExprToStubInt raw
  | .bool => .ite raw (.literalInt 1) (.literalInt 0)
  | _ => raw

partial def lowerQuintValueToCrosscallInt (expr : Expr) : Expr :=
  match expr with
  | .literalBool _ => .ite expr (.literalInt 1) (.literalInt 0)
  | .literalStr s =>
      if s.startsWith "hash:" then hashExprToStubInt expr else expr
  | .mapLit entries =>
      entries.foldl (fun acc (_, v) => .binOp .add acc (lowerQuintValueToCrosscallInt v)) (.literalInt 0)
  | .listLit elems =>
      elems.foldl (fun acc e => .binOp .add acc (lowerQuintValueToCrosscallInt e)) (.literalInt 0)
  | .ite cond t e =>
      .ite cond (lowerQuintValueToCrosscallInt t) (lowerQuintValueToCrosscallInt e)
  | _ => expr

def crosscallHashStubExpr (sum : Expr) : Expr :=
  let mod3 := .binOp .mod sum (.literalInt 3)
  .ite (.binOp .eq mod3 (.literalInt 0)) (.literalStr "hash:1001:0:0:0")
    (.ite (.binOp .eq mod3 (.literalInt 1)) (.literalStr "hash:2002:0:0:0")
      (.literalStr "hash:3003:0:0:0"))

def crosscallStaticTagExpr : Expr := .literalInt 1000000
def crosscallDelegateTagExpr : Expr := .literalInt 2000000
def crosscallCreateTagExpr : Expr := .literalInt 3000000
def crosscallCreate2TagExpr : Expr := .literalInt 4000000

partial def lowerCrosscallCastReturnAt (ctx : LowerCtx) (sum : Expr) (offset : Nat) (returnType : ValueType)
    (aggregateSlot : Bool := false) : Except LowerError (Expr × Nat) := do
  let atSum := .binOp .add sum (.literalInt offset)
  match returnType with
  | .u64 => pure (atSum, offset + 1)
  | .u32 => pure (.binOp .mod atSum (.literalInt 4294967296), offset + 1)
  | .bool =>
      let boolExpr := .binOp .eq (.binOp .mod atSum (.literalInt 2)) (.literalInt 1)
      if aggregateSlot then
        pure (.ite boolExpr (.literalInt 1) (.literalInt 0), offset + 1)
      else
        pure (boolExpr, offset + 1)
  | .hash =>
      if aggregateSlot then
        .error { message := "hash fields in aggregate crosscall returns are not supported in Quint lowering v1" }
      else
        pure (crosscallHashStubExpr atSum, offset + 1)
  | .structType typeName =>
      match lookupStructDecl ctx.structs typeName with
      | none =>
          .error { message := s!"unknown struct `{typeName}` for crosscall aggregate return" }
      | some structDecl => do
          let mut off := offset
          let mut entries := #[]
          for field in structDecl.fields do
            let (fieldExpr, nextOff) ← lowerCrosscallCastReturnAt ctx sum off field.type (aggregateSlot := true)
            entries := entries.push (.literalStr field.id, fieldExpr)
            off := nextOff
          pure (.mapLit entries, off)
  | .fixedArray elem length => do
    let rec go (i off : Nat) (acc : Array Expr) : Except LowerError (Expr × Nat) := do
      if i >= length then
        pure (.listLit acc, off)
      else
        let (elemExpr, nextOff) ← lowerCrosscallCastReturnAt ctx sum off elem (aggregateSlot := true)
        go (i + 1) nextOff (acc.push elemExpr)
    go 0 offset #[]
  | _ => .error {
      message :=
        s!"typed crosscall return `{returnType.name}` is not supported in Quint lowering v1" }

def lowerCrosscallCastReturn (ctx : LowerCtx) (sum : Expr) (returnType : ValueType) : Except LowerError Expr := do
  let (expr, _) ← lowerCrosscallCastReturnAt ctx sum 0 returnType
  pure expr

end ProofForge.Backend.Quint.Lower
