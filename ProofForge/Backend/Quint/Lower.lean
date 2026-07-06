import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Emit
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Invariants
import ProofForge.Backend.Quint.Liveness

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

mutual
  partial def lowerExpr (ctx : LowerCtx) (e : ProofForge.IR.Expr) : Except LowerError Expr := do
    match e with
    | .literal lit => lowerLiteral lit
    | .local name =>
        if !ctx.expandLocals && isWhileStepLocal name then
          .ok (.local name)
        else
          match ctx.locals.lookup name with
          | some expr => .ok expr
          | none => .ok (.local name)
    | .add lhs rhs => .ok (.binOp .add (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .sub lhs rhs =>
        let l ← lowerExpr ctx lhs
        let r ← lowerExpr ctx rhs
        .ok (.ite (.binOp .ge l r) (.binOp .sub l r) (.literalInt 0))
    | .mul lhs rhs => .ok (.binOp .mul (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .div lhs rhs =>
        let l ← lowerExpr ctx lhs
        let r ← lowerExpr ctx rhs
        .ok (.ite (.binOp .eq r (.literalInt 0)) (.literalInt 0) (.binOp .div l r))
    | .mod lhs rhs => .ok (.binOp .mod (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .eq lhs rhs => .ok (.binOp .eq (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .ne lhs rhs => .ok (.binOp .ne (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .lt lhs rhs => .ok (.binOp .lt (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .le lhs rhs => .ok (.binOp .le (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .gt lhs rhs => .ok (.binOp .gt (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .ge lhs rhs => .ok (.binOp .ge (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolAnd lhs rhs => .ok (.binOp .and (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolOr lhs rhs => .ok (.binOp .or (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolNot value => .ok (.unOp .not (← lowerExpr ctx value))
    | .cast value _ => lowerExpr ctx value
    | .arrayLit _ values => do
        let elems ← values.mapM (lowerExpr ctx)
        .ok (.listLit elems)
    | .arrayGet arr idx => do
        let arr' ← lowerExpr ctx arr
        let idx' ← lowerExpr ctx idx
        .ok (.index arr' (irIndexToQuint idx'))
    | .structLit typeName fields => do
        let entries ← fields.mapM (fun (fieldName, fieldExpr) => do
          let lowered ← lowerExpr ctx fieldExpr
          let value ← match lookupStructDecl ctx.structs typeName with
            | some structDecl =>
                match structDecl.fields.find? (fun field => field.id == fieldName) with
                | some { type := .bool, .. } => pure (.ite lowered (.literalInt 1) (.literalInt 0))
                | _ => pure lowered
            | none => pure lowered
          pure (.literalStr fieldName, value))
        .ok (.mapLit entries)
    | .field base fieldName => do
        let base' ← lowerExpr ctx base
        .ok (.methodCall base' "get" #[.literalStr fieldName])
    | .effect eff => lowerEffectExpr ctx eff
    | .crosscallInvoke target methodId args =>
        lowerCrosscallInvokeExpr ctx target methodId args
    | .crosscallInvokeTyped target methodId args returnType =>
        lowerCrosscallInvokeTypedExpr ctx target methodId args returnType
    | .crosscallInvokeValueTyped target methodId callValue args returnType =>
        lowerCrosscallInvokeValueTypedExpr ctx target methodId callValue args returnType
    | .crosscallInvokeStaticTyped target methodId args returnType =>
        lowerCrosscallInvokeStaticTypedExpr ctx target methodId args returnType
    | .crosscallInvokeDelegateTyped target methodId args returnType =>
        lowerCrosscallInvokeDelegateTypedExpr ctx target methodId args returnType
    | .nativeValue =>
        .ok (.literalInt 0)
    | .crosscallCreate callValue _ =>
        lowerCrosscallCreateExpr ctx callValue
    | .crosscallCreate2 callValue salt _ =>
        lowerCrosscallCreate2Expr ctx callValue salt
    | _ => .error { message := "unsupported IR expression for Quint lowering v1" }

  /-- Flatten one crosscall argument (scalar or aggregate) into a deterministic int contribution. -/
  partial def lowerCrosscallArgContributionFromIr (ctx : LowerCtx) (arg : ProofForge.IR.Expr) :
      Except LowerError Expr :=
    match arg with
    | .structLit _ fields => do
        let mut result := .literalInt 0
        for (_, fieldExpr) in fields do
          let contrib ← lowerCrosscallArgContributionFromIr ctx fieldExpr
          result := .binOp .add result contrib
        pure result
    | .arrayLit _ elems => do
        let mut result := .literalInt 0
        for elem in elems do
          let contrib ← lowerCrosscallArgContributionFromIr ctx elem
          result := .binOp .add result contrib
        pure result
    | .field base fieldName => do
        let baseType := crosscallArgTypeFromExpr ctx base
        match baseType with
        | .structType typeName =>
            match lookupStructDecl ctx.structs typeName with
            | none => .error { message := s!"unknown struct `{typeName}` for crosscall aggregate argument" }
            | some structDecl =>
                match structDecl.fields.find? (fun field => field.id == fieldName) with
                | none => .error { message := s!"unknown struct field `{fieldName}` for crosscall aggregate argument" }
                | some field => do
                    let raw ← lowerExpr ctx arg
                    match field.type with
                    | .bool => pure raw
                    | _ => pure (crosscallArgToIntExpr raw field.type)
        | _ => .error { message := "field access in crosscall argument expects struct base" }
    | .arrayGet arr index => do
        let arrType := crosscallArgTypeFromExpr ctx arr
        match arrType with
        | .fixedArray elem _ =>
            let raw ← lowerExpr ctx arg
            pure (crosscallArgToIntExpr raw elem)
        | _ => .error { message := "array element in crosscall argument expects fixed array base" }
    | .local name =>
        match ctx.localTypes.find? (fun (n, _) => n == name) with
        | some (_, .structType typeName) =>
            match lookupStructDecl ctx.structs typeName with
            | none => .error { message := s!"unknown struct `{typeName}` for crosscall aggregate argument" }
            | some structDecl => do
                let mut result := .literalInt 0
                for field in structDecl.fields do
                  let contrib ← lowerCrosscallArgContributionFromIr ctx (.field (.local name) field.id)
                  result := .binOp .add result contrib
                pure result
        | some (_, .fixedArray elem length) => do
            let mut result := .literalInt 0
            for index in [0:length] do
              let contrib ← lowerCrosscallArgContributionFromIr ctx
                (.arrayGet (.local name) (.literal (.u64 index)))
              result := .binOp .add result contrib
            pure result
        | _ => do
            let raw ← lowerExpr ctx arg
            let argType := crosscallArgTypeFromExpr ctx arg
            pure (crosscallArgToIntExpr raw argType)
    | _ => do
        let raw ← lowerExpr ctx arg
        let argType := crosscallArgTypeFromExpr ctx arg
        pure (crosscallArgToIntExpr raw argType)

  partial def lowerCrosscallArgContributionExpr (ctx : LowerCtx) (arg : ProofForge.IR.Expr) :
      Except LowerError Expr :=
    lowerCrosscallArgContributionFromIr ctx arg

  /-- Deterministic crosscall stub: sum target, method, and scalar args (MBT/replay aligned with IR semantics). -/
  partial def lowerCrosscallInvokeSumExpr (ctx : LowerCtx) (target methodId : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) : Except LowerError Expr := do
    let target' ← lowerExpr ctx target
    let method' ← lowerExpr ctx methodId
    let mut result := .binOp .add target' method'
    for arg in args do
      let arg' ← lowerCrosscallArgContributionExpr ctx arg
      result := .binOp .add result arg'
    pure result

  partial def lowerCrosscallInvokeExpr (ctx : LowerCtx) (target methodId : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) : Except LowerError Expr :=
    lowerCrosscallInvokeSumExpr ctx target methodId args

  partial def lowerCrosscallInvokeTypedExpr (ctx : LowerCtx) (target methodId : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) (returnType : ValueType) : Except LowerError Expr := do
    let sum ← lowerCrosscallInvokeSumExpr ctx target methodId args
    lowerCrosscallCastReturn ctx sum returnType

  partial def lowerCrosscallInvokeValueTypedExpr (ctx : LowerCtx) (target methodId callValue : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) (returnType : ValueType) : Except LowerError Expr := do
    let sum ← lowerCrosscallInvokeSumExpr ctx target methodId args
    let callValue' ← lowerExpr ctx callValue
    lowerCrosscallCastReturn ctx (.binOp .add sum callValue') returnType

  partial def lowerCrosscallInvokeStaticTypedExpr (ctx : LowerCtx) (target methodId : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) (returnType : ValueType) : Except LowerError Expr := do
    let sum ← lowerCrosscallInvokeSumExpr ctx target methodId args
    lowerCrosscallCastReturn ctx (.binOp .add sum crosscallStaticTagExpr) returnType

  partial def lowerCrosscallInvokeDelegateTypedExpr (ctx : LowerCtx) (target methodId : ProofForge.IR.Expr)
      (args : Array ProofForge.IR.Expr) (returnType : ValueType) : Except LowerError Expr := do
    let sum ← lowerCrosscallInvokeSumExpr ctx target methodId args
    lowerCrosscallCastReturn ctx (.binOp .add sum crosscallDelegateTagExpr) returnType

  partial def lowerCrosscallCreateExpr (ctx : LowerCtx) (callValue : ProofForge.IR.Expr) :
      Except LowerError Expr := do
    let callValue' ← lowerExpr ctx callValue
    pure (.binOp .add callValue' crosscallCreateTagExpr)

  partial def lowerCrosscallCreate2Expr (ctx : LowerCtx) (callValue salt : ProofForge.IR.Expr) :
      Except LowerError Expr := do
    let callValue' ← lowerExpr ctx callValue
    let salt' ← lowerExpr ctx salt
    let saltInt := crosscallArgToIntExpr salt' .hash
    pure (.binOp .add (.binOp .add callValue' saltInt) crosscallCreate2TagExpr)

  partial def lowerMapKeyExpr (ctx : LowerCtx) (key : ProofForge.IR.Expr) : Except LowerError Expr :=
    match key with
    | .literal (.hash4 a b c d) => .ok (.literalStr (hashLiteralStr a b c d))
    | .literal (.u64 n) => .ok (.literalStr s!"u64:{n}")
    | other => lowerExpr ctx other

  partial def mapPathSegmentLiteral? (key : ProofForge.IR.Expr) : Option String :=
    match key with
    | .literal (.hash4 a b c d) => some ("{" ++ hashLiteralStr a b c d ++ "}")
    | .literal (.u64 n) => some ("{u64:" ++ toString n ++ "}")
    | _ => none

  partial def bracedHashSampleStr (sample : String) : String :=
    "{" ++ sample ++ "}"

  /-- Split consecutive literal mapKey prefix from a dynamic tail. -/
  partial def splitLiteralPrefixDynamicTail (keys : Array ProofForge.IR.Expr) :
      String × Array ProofForge.IR.Expr :=
    let rec go (i : Nat) (accPrefix : String) (dynamic : Array ProofForge.IR.Expr) (seenDynamic : Bool) :
        String × Array ProofForge.IR.Expr :=
      if h : i < keys.size then
        let key := keys[i]
        if seenDynamic then
          go (i + 1) accPrefix (dynamic.push key) true
        else
          match mapPathSegmentLiteral? key with
          | some seg => go (i + 1) (accPrefix ++ seg) dynamic false
          | none => go (i + 1) accPrefix (dynamic.push key) true
      else
        (accPrefix, dynamic)
    go 0 "" #[] false

  partial def dynamicMapKeyCondition (loweredKey sample : Expr) : Expr :=
    .binOp .eq loweredKey sample

  /-- Unfold a dynamic mapKey tail over the finite MBT hash sample domain. -/
  partial def unfoldDynamicCompositeMapKeyExpr (ctx : LowerCtx) (litPrefix : String)
      (dynKeys : Array ProofForge.IR.Expr) : Except LowerError Expr := do
    if dynKeys.isEmpty then
      .error { message := "dynamic map path requires at least one non-literal key segment" }
    let loweredKeys ← dynKeys.mapM (lowerMapKeyExpr ctx)
    let defaultComposite := litPrefix ++ bracedHashSampleStr hashKeySampleStrs[0]!
    let rec buildCombo (idx : Nat) (accCond : Expr) (accSuffix : String) :
        Except LowerError (Array (Expr × String)) := do
      if h : idx < dynKeys.size then
        let mut rows := #[]
        for sampleStr in hashKeySampleStrs do
          let sample := .literalStr sampleStr
          let cond := dynamicMapKeyCondition loweredKeys[idx]! sample
          let nextRows ← buildCombo (idx + 1) (.binOp .and accCond cond)
            (accSuffix ++ bracedHashSampleStr sampleStr)
          rows := rows ++ nextRows
        pure rows
      else
        pure #[(accCond, litPrefix ++ accSuffix)]
    let rows ← buildCombo 0 (.literalBool true) ""
    let mut result := .literalStr defaultComposite
    for (cond, composite) in rows do
      result := .ite cond (.literalStr composite) result
    pure result

  partial def literalCompositeMapKey? (keys : Array ProofForge.IR.Expr) : Option String :=
    let rec go (i : Nat) (acc : String) : Option String :=
      if h : i < keys.size then
        match mapPathSegmentLiteral? keys[i] with
        | some seg => go (i + 1) (acc ++ seg)
        | none => none
      else
        some acc
    go 0 ""

  partial def compositeMapKeyExpr (ctx : LowerCtx) (keys : Array ProofForge.IR.Expr) : Except LowerError Expr := do
    match literalCompositeMapKey? keys with
    | some composite => .ok (.literalStr composite)
    | none =>
      let (litPrefix, dynTail) := splitLiteralPrefixDynamicTail keys
      if dynTail.isEmpty then
        .error { message := "map path requires at least one key segment" }
      else
        unfoldDynamicCompositeMapKeyExpr ctx litPrefix dynTail

  /-- Single-segment keys use `u64:n` / `hash:...`; multi-segment keys use braced concatenation. -/
  partial def mapPathKeyExpr (ctx : LowerCtx) (keys : Array ProofForge.IR.Expr) : Except LowerError Expr := do
    let some first := keys[0]?
      | .error { message := "map path requires at least one key segment" }
    if keys.size == 1 then
      lowerMapKeyExpr ctx first
    else
      compositeMapKeyExpr ctx keys

  partial def mapAbsentZero (ctx : LowerCtx) (stateId : String) : Except LowerError Expr :=
    match ctx.lookupStateDecl stateId with
    | some { type := .hash, .. } => .ok hashZeroExpr
    | some { type := .bool, .. } => .ok (.literalBool false)
    | some { type := .address, .. } => .ok (.literalStr "")
    | some { type := ty, .. } =>
        match ty with
        | .u8 | .u32 | .u64 | .u128 | .unit => .ok (.literalInt 0)
        | _ => .ok hashZeroExpr
    | none => .ok hashZeroExpr

  partial def lowerMapGetAtKey (ctx : LowerCtx) (stateId : String) (key : Expr) : Except LowerError Expr := do
    let mapExpr := ctx.stateValue stateId
    let present := mapContainsExpr key mapExpr
    let zero ← mapAbsentZero ctx stateId
    .ok (.ite present (.methodCall mapExpr "get" #[key]) zero)

  partial def lowerMapGetExpr (ctx : LowerCtx) (stateId : String) (key : ProofForge.IR.Expr) : Except LowerError Expr := do
    let key' ← lowerMapKeyExpr ctx key
    lowerMapGetAtKey ctx stateId key'

  partial def targetPresenceGuard (ctx : LowerCtx) (target : StoragePathTarget) : Except LowerError (Option Expr) :=
    match target with
    | .mapKeyPath stateId keys => do
        let mapExpr := ctx.stateValue stateId
        let key' ← mapPathKeyExpr ctx keys
        .ok (some (mapContainsExpr key' mapExpr))
    | _ => .ok none

  partial def arrayStructFieldReadExpr (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldName : String) : Except LowerError Expr := do
    let idx' ← lowerExpr ctx index
    let mut result := .literalInt 0
    for i in [0:cap] do
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let atI := ctx.stateValue (arrayStructFieldVarName stateId i fieldName)
      result := .ite cond atI result
    .ok result

  partial def arrayStructFieldTrackReadExpr (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldName : String) : Except LowerError Expr := do
    let idx' ← lowerExpr ctx index
    let mut result := .literalInt 0
    for i in [0:cap] do
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let atI := ctx.mutationTrackValue (arrayStructFieldVarName stateId i fieldName)
      result := .ite cond atI result
    .ok result

  partial def arrayStructFieldWriteCtx (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldName : String) (value : ProofForge.IR.Expr)
      (combine : Expr → Expr → Expr → Expr) : Except LowerError LowerCtx := do
    let idx' ← lowerExpr ctx index
    let value' ← lowerExpr ctx value
    let mut nextCtx := ctx
    for i in [0:cap] do
      let name := arrayStructFieldVarName stateId i fieldName
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let curState := nextCtx.stateValue name
      let curTrack := nextCtx.mutationTrackValue name
      let updatedState := combine cond value' curState
      let updatedTrack := combine cond value' curTrack
      nextCtx := {
        nextCtx with
        state := nextCtx.state.upsert name updatedState,
        mutationTrack := nextCtx.mutationTrack.upsert name updatedTrack }
    .ok nextCtx

  partial def arrayNestedFieldReadExpr (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldPath : List String) : Except LowerError Expr := do
    let idx' ← lowerExpr ctx index
    let mut result := .literalInt 0
    for i in [0:cap] do
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let atI := ctx.stateValue (arrayNestedFieldVarName stateId i fieldPath)
      result := .ite cond atI result
    .ok result

  partial def arrayNestedFieldTrackReadExpr (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldPath : List String) : Except LowerError Expr := do
    let idx' ← lowerExpr ctx index
    let mut result := .literalInt 0
    for i in [0:cap] do
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let atI := ctx.mutationTrackValue (arrayNestedFieldVarName stateId i fieldPath)
      result := .ite cond atI result
    .ok result

  partial def arrayNestedFieldWriteCtx (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldPath : List String) (value : ProofForge.IR.Expr)
      (combine : Expr → Expr → Expr → Expr) : Except LowerError LowerCtx := do
    let idx' ← lowerExpr ctx index
    let value' ← lowerExpr ctx value
    let mut nextCtx := ctx
    for i in [0:cap] do
      let name := arrayNestedFieldVarName stateId i fieldPath
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let curState := nextCtx.stateValue name
      let curTrack := nextCtx.mutationTrackValue name
      let updatedState := combine cond value' curState
      let updatedTrack := combine cond value' curTrack
      nextCtx := {
        nextCtx with
        state := nextCtx.state.upsert name updatedState,
        mutationTrack := nextCtx.mutationTrack.upsert name updatedTrack }
    .ok nextCtx

  partial def writeStructLitFields (ctx : LowerCtx) (varPrefix : String) (typeName : String)
      (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError LowerCtx := do
    match lookupStructDecl ctx.structs typeName with
    | none => .error { message := s!"unknown struct type `{typeName}` for struct literal write" }
    | some decl => do
        let mut nextCtx := ctx
        for (fieldName, fieldExpr) in fields do
          match decl.fields.find? (fun f => f.id == fieldName) with
          | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | some field =>
              match fieldExpr, field.type, field.isRef with
              | .structLit innerType innerFields, .structType expectedInner, true =>
                  if innerType == expectedInner then
                    nextCtx ← writeStructLitFields nextCtx (nestedFieldVarName varPrefix [fieldName])
                      innerType innerFields
                  else
                    .error { message := s!"nested struct field `{fieldName}` expected `{expectedInner}`, got `{innerType}`" }
              | _, _, _ => do
                  let value' ← lowerExpr nextCtx fieldExpr
                  nextCtx := { nextCtx with
                    state := nextCtx.state.upsert (nestedFieldVarName varPrefix [fieldName]) value' }
        .ok nextCtx

  partial def targetReadExpr (ctx : LowerCtx) (target : StoragePathTarget) : Except LowerError Expr :=
    match target with
    | .flatVar name => .ok (ctx.stateValue name)
    | .arraySlot stateId cap index => do
        let idx' ← lowerExpr ctx index
        .ok (.index (ctx.stateValue stateId) (irIndexToQuint idx'))
    | .arrayStructFieldSlot stateId cap index fieldName =>
        arrayStructFieldReadExpr ctx stateId cap index fieldName
    | .arrayNestedFieldSlot stateId cap index fieldPath =>
        arrayNestedFieldReadExpr ctx stateId cap index fieldPath
    | .nestedStructRef _ _ =>
        .error { message := "nested struct ref path read requires a leaf field segment" }
    | .mapKeyPath stateId keys => do
        let key' ← mapPathKeyExpr ctx keys
        lowerMapGetAtKey ctx stateId key'

  partial def targetTrackReadExpr (ctx : LowerCtx) (target : StoragePathTarget) : Except LowerError Expr :=
    match target with
    | .flatVar name => .ok (ctx.mutationTrackValue name)
    | .arraySlot stateId _ index => do
        let idx' ← lowerExpr ctx index
        .ok (.index (ctx.mutationTrackValue stateId) (irIndexToQuint idx'))
    | .arrayStructFieldSlot stateId cap index fieldName =>
        arrayStructFieldTrackReadExpr ctx stateId cap index fieldName
    | .arrayNestedFieldSlot stateId cap index fieldPath =>
        arrayNestedFieldTrackReadExpr ctx stateId cap index fieldPath
    | .nestedStructRef _ _ =>
        .error { message := "nested struct ref path track read requires a leaf field segment" }
    | .mapKeyPath stateId keys => do
        let key' ← mapPathKeyExpr ctx keys
        lowerMapGetAtKey ctx stateId key'

  partial def targetWriteCtx (ctx : LowerCtx) (target : StoragePathTarget) (value : ProofForge.IR.Expr) :
      Except LowerError LowerCtx :=
    match target with
    | .flatVar name => do
        let value' ← lowerExpr ctx value
        .ok { ctx with state := ctx.state.upsert name value' }
    | .arraySlot stateId cap index => do
        let current := ctx.stateValue stateId
        let key' ← lowerExpr ctx index
        let value' ← lowerExpr ctx value
        let updated :=
          match key' with
          | .literalInt n =>
              if n >= 0 && n.toNat < cap then
                listSetAtLiteral current cap n.toNat value'
              else
                listSetAtExpr current cap key' value'
          | _ => listSetAtExpr current cap key' value'
        .ok { ctx with state := ctx.state.upsert stateId updated }
    | .arrayStructFieldSlot stateId cap index fieldName =>
        arrayStructFieldWriteCtx ctx stateId cap index fieldName value
          (fun (cond : Expr) (value' : Expr) (cur : Expr) => .ite cond value' cur)
    | .arrayNestedFieldSlot stateId cap index fieldPath =>
        arrayNestedFieldWriteCtx ctx stateId cap index fieldPath value
          (fun (cond : Expr) (value' : Expr) (cur : Expr) => .ite cond value' cur)
    | .nestedStructRef varPrefix structType =>
        match value with
        | .structLit typeName fields =>
            if typeName != structType then
              .error { message := s!"nested struct path write expected `{structType}`, got `{typeName}`" }
            else
              writeStructLitFields ctx varPrefix typeName fields
        | _ => .error { message := "nested struct ref path write expects a struct literal value" }
    | .mapKeyPath stateId keys => do
        let mapExpr := ctx.stateValue stateId
        let key' ← mapPathKeyExpr ctx keys
        let value' ← lowerExpr ctx value
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok { ctx with state := ctx.state.upsert stateId updated }

  partial def targetMapAssignOpCtx (ctx : LowerCtx) (stateId : String) (key : Expr) (op : AssignOp)
      (value : ProofForge.IR.Expr) : Except LowerError LowerCtx := do
    let mapExpr := ctx.stateValue stateId
    let value' ← lowerExpr ctx value
    let updated ← match ctx.lookupStateDecl stateId with
      | some { type := .hash, .. } =>
          -- Hash-valued map assignOp is a replace stub (MBT/replay aligned with IR semantics).
          pure (.methodCall mapExpr "put" #[key, value'])
      | _ => do
          let old ← lowerMapGetAtKey ctx stateId key
          let qop := lowerAssignOp op
          pure (.methodCall mapExpr "put" #[key, .binOp qop old value'])
    .ok { ctx with state := ctx.state.upsert stateId updated }

  partial def targetAssignOpCtx (ctx : LowerCtx) (target : StoragePathTarget) (op : AssignOp)
      (value : ProofForge.IR.Expr) : Except LowerError LowerCtx :=
    match target with
    | .flatVar name => do
        let cur := ctx.stateValue name
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        .ok { ctx with state := ctx.state.upsert name (.binOp qop cur value') }
    | .arraySlot stateId cap index => do
        let current := ctx.stateValue stateId
        let key' ← lowerExpr ctx index
        let atIdx := .index current (irIndexToQuint key')
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        let updatedElem := .binOp qop atIdx value'
        let updated :=
          match key' with
          | .literalInt n =>
              if n >= 0 && n.toNat < cap then
                listSetAtLiteral current cap n.toNat updatedElem
              else
                listSetAtExpr current cap key' updatedElem
          | _ => listSetAtExpr current cap key' updatedElem
        .ok { ctx with state := ctx.state.upsert stateId updated }
    | .arrayStructFieldSlot stateId cap index fieldName => do
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        arrayStructFieldWriteCtx ctx stateId cap index fieldName value
          (fun (cond : Expr) (_ : Expr) (cur : Expr) => .ite cond (.binOp qop cur value') cur)
    | .arrayNestedFieldSlot stateId cap index fieldPath => do
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        arrayNestedFieldWriteCtx ctx stateId cap index fieldPath value
          (fun (cond : Expr) (_ : Expr) (cur : Expr) => .ite cond (.binOp qop cur value') cur)
    | .nestedStructRef _ _ =>
        .error { message := "nested struct ref path assignOp requires a leaf field segment" }
    | .mapKeyPath stateId keys => do
        let key' ← mapPathKeyExpr ctx keys
        targetMapAssignOpCtx ctx stateId key' op value

  partial def effectPresenceGuard (ctx : LowerCtx) (eff : Effect) : Except LowerError (Option Expr) :=
    match eff with
    | .storageMapGet stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        .ok (some (mapContainsExpr key' mapExpr))
    | .storagePathRead stateId path =>
        match ctx.lookupStateDecl stateId with
        | some decl =>
            match resolveStoragePathTarget ctx.structs decl path with
            | .ok target => targetPresenceGuard ctx target
            | .error err => .error err
        | none => .error { message := s!"unknown state `{stateId}` for storagePathRead guard" }
    | _ => .ok none

  partial def lowerEffectExpr (ctx : LowerCtx) (eff : Effect) : Except LowerError Expr :=
    match eff with
    | .storageScalarRead stateId => .ok (ctx.stateValue stateId)
    | .storageArrayRead stateId key => do
        let key' ← lowerExpr ctx key
        .ok (.index (ctx.stateValue stateId) (irIndexToQuint key'))
    | .storageMapContains stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        .ok (mapContainsExpr key' mapExpr)
    | .storageMapGet stateId key =>
        lowerMapGetExpr ctx stateId key
    | .storagePathRead stateId path =>
        match ctx.lookupStateDecl stateId with
        | some decl =>
            match resolveStoragePathTarget ctx.structs decl path with
            | .ok target => targetReadExpr ctx target
            | .error err => .error err
        | none => .error { message := s!"unknown state `{stateId}` for storagePathRead" }
    | .storageStructFieldRead stateId fieldName =>
        .ok (ctx.stateValue (structFieldVarName stateId fieldName))
    | .contextRead field =>
        match field with
        | .userId | .contractId | .checkpointId | .timestamp | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao =>
            .ok (.literalInt 0)
        | _ => .error { message := s!"unsupported context field for Quint lowering v1: {field.name}" }
    | _ => .error { message := "unsupported effect as expression for Quint lowering v1" }

  partial def expectedReturnFromEffectTrace (ctx : LowerCtx) (eff : Effect) : Except LowerError (Option Expr) :=
    match eff with
    | .storagePathRead stateId _ =>
        let (base, delta) := ctx.effectTrace.foldl (fun (acc : Option Nat × Nat) traced =>
          match traced with
          | .storagePathWrite sid _ value =>
              if sid == stateId then
                (irExprNat? value, acc.2)
              else acc
          | .storagePathAssignOp sid _ op value =>
              if sid == stateId then
                let nextDelta :=
                  match op, irExprNat? value with
                  | .add, some n => acc.2 + n
                  | .sub, some n => acc.2 - n
                  | _, _ => acc.2
                (acc.1, nextDelta)
              else acc
          | _ => acc) (none, 0)
        match base with
        | some b => .ok (some (.literalInt (Int.ofNat (b + delta))))
        | none => .ok none
    | _ => .ok none

  partial def lowerMutationTrackEffectExpr (ctx : LowerCtx) (eff : Effect) : Except LowerError Expr :=
    match eff with
    | .storageScalarRead stateId => .ok (ctx.mutationTrackValue stateId)
    | .storageArrayRead stateId key => do
        let key' ← lowerExpr ctx key
        .ok (.index (ctx.mutationTrackValue stateId) (irIndexToQuint key'))
    | .storageMapContains stateId key => do
        let mapExpr := ctx.mutationTrackValue stateId
        let key' ← lowerExpr ctx key
        .ok (mapContainsExpr key' mapExpr)
    | .storageMapGet stateId key => do
        let key' ← lowerMapKeyExpr ctx key
        lowerMapGetAtKey { ctx with state := ctx.mutationTrack } stateId key'
    | .storagePathRead stateId path =>
        match ctx.lookupStateDecl stateId with
        | some decl =>
            match resolveStoragePathTarget ctx.structs decl path with
            | .ok target => targetTrackReadExpr ctx target
            | .error err => .error err
        | none => .error { message := s!"unknown state `{stateId}` for storagePathRead track read" }
    | .storageStructFieldRead stateId fieldName =>
        .ok (ctx.mutationTrackValue (structFieldVarName stateId fieldName))
    | _ => lowerEffectExpr ctx eff

  partial def lowerMutatingEffectBinding (ctx : LowerCtx) (eff : Effect) :
      Except LowerError (LowerCtx × Expr) :=
    match eff with
    | .storageMapInsert stateId key value
    | .storageMapSet stateId key value => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        let value' ← lowerExpr ctx value
        let present := mapContainsExpr key' mapExpr
        let old := .ite present (.methodCall mapExpr "get" #[key']) hashZeroExpr
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok ({ ctx with state := ctx.state.upsert stateId updated }, old)
    | _ => do
        let expr ← lowerEffectExpr ctx eff
        .ok (ctx, expr)

  partial def applyEffect (ctx : LowerCtx) (eff : Effect) : Except LowerError LowerCtx := do
    match eff with
    | .storageScalarWrite stateId value =>
        match value with
        | .structLit typeName fields =>
            match lookupStructDecl ctx.structs typeName with
            | some _ => writeStructLitFields ctx stateId typeName fields
            | none => .error { message := s!"unknown struct type `{typeName}` for storage write `{stateId}`" }
        | _ =>
            let value' ← lowerExpr ctx value
            .ok { ctx with state := ctx.state.upsert stateId value' }
    | .storageScalarAssignOp stateId op value =>
        let cur := ctx.stateValue stateId
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        .ok { ctx with state := ctx.state.upsert stateId (.binOp qop cur value') }
    | .storageArrayWrite stateId key value =>
        match ctx.lookupStateDecl stateId with
        | some decl@{ kind := .array cap, type := .structType typeName, .. } =>
            if !(flatFieldsForStateDecl decl ctx.structs).isEmpty then
              match value with
              | .structLit litType fields =>
                  if litType != typeName then
                    .error { message := s!"struct array write expected `{typeName}`, got `{litType}`" }
                  else
                    match irExprNat? key with
                    | some index =>
                        if index >= cap then
                          .error { message := s!"storage array index {index} out of bounds for `{stateId}` (length {cap})" }
                        else
                          writeStructLitFields ctx (s!"{stateId}_{index}") typeName fields
                    | none =>
                        .error { message := s!"flattened struct array write on `{stateId}` requires a static index in Quint lowering v1" }
              | _ =>
                  .error { message := s!"flattened struct array write on `{stateId}` expects a struct literal value" }
            else do
              let current := ctx.stateValue stateId
              let key' ← lowerExpr ctx key
              let value' ← lowerExpr ctx value
              let updated :=
                match key' with
                | .literalInt n =>
                    if n >= 0 && n.toNat < cap then
                      listSetAtLiteral current cap n.toNat value'
                    else
                      listSetAtExpr current cap key' value'
                | _ => listSetAtExpr current cap key' value'
              .ok { ctx with state := ctx.state.upsert stateId updated }
        | some { kind := .array cap, .. } =>
            let current := ctx.stateValue stateId
            let key' ← lowerExpr ctx key
            let value' ← lowerExpr ctx value
            let updated :=
              match key' with
              | .literalInt n =>
                  if n >= 0 && n.toNat < cap then
                    listSetAtLiteral current cap n.toNat value'
                  else
                    listSetAtExpr current cap key' value'
              | _ => listSetAtExpr current cap key' value'
            .ok { ctx with state := ctx.state.upsert stateId updated }
        | _ =>
            .error { message := s!"storageArrayWrite on unknown or non-array state `{stateId}`" }
    | .storageMapSet stateId key value => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        let value' ← lowerExpr ctx value
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok { ctx with state := ctx.state.upsert stateId updated }
    | .storagePathWrite stateId path value => do
        let ctx' ← match ctx.lookupStateDecl stateId with
          | some decl =>
              match resolveStoragePathTarget ctx.structs decl path with
              | .ok target => targetWriteCtx ctx target value
              | .error err => .error err
          | none => .error { message := s!"unknown state `{stateId}` for storagePathWrite" }
        .ok { ctx' with effectTrace := ctx'.effectTrace.push (.storagePathWrite stateId path value) }
    | .storagePathAssignOp stateId path op value => do
        let ctx' ← match ctx.lookupStateDecl stateId with
          | some decl =>
              match resolveStoragePathTarget ctx.structs decl path with
              | .ok target => targetAssignOpCtx ctx target op value
              | .error err => .error err
          | none => .error { message := s!"unknown state `{stateId}` for storagePathAssignOp" }
        .ok { ctx' with effectTrace := ctx'.effectTrace.push (.storagePathAssignOp stateId path op value) }
    | .storageStructFieldWrite stateId fieldName value => do
        let value' ← lowerExpr ctx value
        .ok { ctx with
          state := ctx.state.upsert (structFieldVarName stateId fieldName) value' }
    | .eventEmit _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.literalBool true)) }
    | _ => .error { message := "unsupported effect statement for Quint lowering v1" }

  partial def mergeBranchState (pre : LowerCtx) (cond : Expr) (thenCtx elseCtx : LowerCtx) : LocalEnv :=
    let branchIds :=
      (thenCtx.state ++ elseCtx.state).map Prod.fst |>.eraseDups
    branchIds.foldl (fun merged stateId =>
      let preVal := { pre with state := merged }.stateValue stateId
      let thenVal := match thenCtx.state.lookup stateId with | some v => v | none => preVal
      let elseVal := match elseCtx.state.lookup stateId with | some v => v | none => preVal
      merged.upsert stateId (.ite cond thenVal elseVal)) pre.state

  partial def wrapBranchGuards (cond : Expr) (negate : Bool) (guards : Array ActionClause) : Array ActionClause :=
    if guards.isEmpty then #[] else
      let guard := if negate then .guard (.unOp .not cond) else .guard cond
      #[.all (#[guard] ++ guards)]

  partial def lowerStatements (ctx : LowerCtx) (stmts : Array Statement) : Except LowerError LowerCtx := do
    stmts.foldlM (fun ctx stmt => lowerStatement ctx stmt) ctx

  partial def lowerStatement (ctx : LowerCtx) (s : Statement) : Except LowerError LowerCtx := do
    match s with
    | .letBind name ty value =>
        match value with
        | .effect eff =>
            let (ctx', expr) ← lowerMutatingEffectBinding ctx eff
            .ok { ctx' with
              locals := ctx'.locals.bind name expr,
              localTypes := ctx'.localTypes.push (name, ty) }
        | _ =>
            .ok { ctx with
              locals := ctx.locals.bind name (← lowerExpr ctx value),
              localTypes := ctx.localTypes.push (name, ty) }
    | .letMutBind name ty value =>
        .ok { ctx with
          locals := ctx.locals.bind name (← lowerExpr ctx value),
          localTypes := ctx.localTypes.push (name, ty) }
    | .assign target value =>
        match target with
        | .local name => do
            let value' ← lowerExpr ctx value
            .ok { ctx with locals := ctx.locals.upsert name value' }
        | _ =>
            .error { message := "local assignment target must be a scalar local for Quint lowering v1" }
    | .assignOp target op value =>
        match target with
        | .local name => do
            let rhs ← lowerExpr ctx value
            let lhs ← match ctx.locals.lookup name with
              | some bound => pure bound
              | none => pure (.local name)
            let updated := .binOp (lowerAssignOp op) lhs rhs
            .ok { ctx with locals := ctx.locals.upsert name updated }
        | _ =>
            .error { message := "compound local assignment target must be a scalar local for Quint lowering v1" }
    | .effect eff =>
        applyEffect ctx eff
    | .assert condition _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (← lowerExpr ctx condition)) }
    | .assertEq lhs rhs _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.binOp .eq (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))) }
    | .revert _ | .revertWithError _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.literalBool false)) }
    | .ifElse condition thenBody elseBody =>
        let cond ← lowerExpr ctx condition
        let thenCtx ← lowerStatements ctx thenBody
        let elseCtx ← lowerStatements ctx elseBody
        let mergedState := mergeBranchState ctx cond thenCtx elseCtx
        let thenWrapped := wrapBranchGuards cond false thenCtx.guards
        let elseWrapped := wrapBranchGuards cond true elseCtx.guards
        let branchGuards := thenWrapped ++ elseWrapped
        let branchClause :=
          if branchGuards.isEmpty then #[] else #[.any branchGuards]
        .ok { ctx with
          state := mergedState,
          guards := ctx.guards ++ branchClause }
    | .boundedFor indexName start stopExclusive body =>
        let mut stateAcc := ctx.state
        let mut guardsAcc := ctx.guards
        for i in [start:stopExclusive] do
          let loopCtx := {
            ctx with
            locals := ctx.locals.bind indexName (.literalInt (Int.ofNat i)),
            state := stateAcc,
            guards := #[] }
          let bodyCtx ← lowerStatements loopCtx body
          stateAcc := bodyCtx.state
          guardsAcc := guardsAcc ++ bodyCtx.guards
        .ok { ctx with state := stateAcc, guards := guardsAcc }
    | .whileLoop condition body =>
        let stateIds := expandedStateIds ctx.stateDecls ctx.structs
        let mut stepLocals : LocalEnv :=
          stateIds.foldl (fun (acc : LocalEnv) id =>
            acc.upsert (whileStepLocalName id 0) (ctx.stateValue id)) []
        let mut pureDefsAcc := ctx.pureDefs
        for id in stateIds do
          pureDefsAcc := pureDefsAcc.push {
            name := whileStepLocalName id 0,
            ret := .int,
            body := ctx.stateValue id }
        let mut guardsAcc := ctx.guards
        for step in [0:ctx.maxLoopUnroll] do
          let loopState := stateIds.foldl (fun (acc : LocalEnv) id =>
            acc.upsert id (.local (whileStepLocalName id step))) []
          let loopCtx := {
            ctx with
            locals := stepLocals,
            state := loopState,
            guards := #[],
            expandLocals := false }
          let cond ← lowerExpr loopCtx condition
          let thenCtx ← lowerStatements loopCtx body
          for id in stateIds do
            let preVal := .local (whileStepLocalName id step)
            let thenVal := match thenCtx.state.lookup id with | some v => v | none => preVal
            let binding := .ite cond thenVal preVal
            stepLocals := stepLocals.upsert (whileStepLocalName id (step + 1)) binding
            pureDefsAcc := pureDefsAcc.push {
              name := whileStepLocalName id (step + 1),
              ret := .int,
              body := binding }
          guardsAcc := guardsAcc ++ wrapBranchGuards cond false thenCtx.guards
        let finalState := stateIds.foldl (fun (acc : LocalEnv) id =>
          acc.upsert id (.local (whileStepLocalName id ctx.maxLoopUnroll))) []
        .ok { ctx with state := finalState, guards := guardsAcc, pureDefs := pureDefsAcc }
    | .return (.effect eff) => do
        let (retExpr, expectedExpr) ← lowerReturnGuardPair ctx eff
        let mut guards := ctx.guards
        match ← effectPresenceGuard ctx eff with
        | some guard => guards := guards.push (.guard guard)
        | none => pure ()
        guards := guards.push (.guard (.binOp .eq retExpr expectedExpr))
        .ok { ctx with guards := guards }
    | .return value => do
        let retExpr ← lowerExpr ctx value
        .ok { ctx with guards := ctx.guards.push (.guard (.binOp .eq retExpr retExpr)) }
    | .release _ =>
        .ok ctx

  /-- Lower the read expression and its expected value for a return effect guard. -/
  partial def lowerReturnGuardPair (ctx : LowerCtx) (eff : Effect) : Except LowerError (Expr × Expr) := do
    let retExpr ← lowerEffectExpr ctx eff
    let expectedExpr ← do
      let folded? ← expectedReturnFromEffectTrace ctx eff
      match folded? with
      | some folded => pure folded
      | none => lowerMutationTrackEffectExpr ctx eff
    pure (retExpr, expectedExpr)

end

structure LoweredEntrypoint where
  action : Action
  pureDefs : Array PureDef := #[]

def ctxToActionClauses (ctx : LowerCtx) : Array ActionClause :=
  let assigns := ctx.state.toArray.map (fun (stateId, value) =>
    ActionClause.assign (.prime (.local stateId)) value)
  assigns ++ ctx.guards

partial def assignedStateVars (clause : ActionClause) : List String :=
  match clause with
  | .assign (.prime (.local name)) _ => [name]
  | .all clauses | .any clauses =>
      clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  | .nondet _ _ body => assignedStateVars body
  | _ => []

def lowerEntrypoint (ep : Entrypoint) (stateIds : Array String) (stateDecls : Array StateDecl)
    (structs : Array StructDecl) (maxLoopUnroll : Nat) : Except LowerError LoweredEntrypoint := do
  let params ← ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t))
  let ctx ← lowerStatements {
    stateDecls := stateDecls,
    structs := structs,
    maxLoopUnroll := maxLoopUnroll,
    paramTypes := ep.params,
    localTypes := #[] } ep.body
  let clauses := ctxToActionClauses ctx
  let assigned := clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  let identityClauses := stateIds.filterMap (fun id =>
    if assigned.contains id then none else some (.assign (.prime (.local id)) (.local id)))
  let body := ActionClause.all (clauses ++ identityClauses)
  pure {
    action := {
      name := sanitizeName ep.name,
      params := params,
      ret? := some .bool,
      body := body },
    pureDefs := ctx.pureDefs
  }

def zeroExpr (t : ValueType) : Except LowerError Expr :=
  match t with
  | .bool => .ok (.literalBool false)
  | .u8 | .u32 | .u64 | .u128 | .unit => .ok (.literalInt 0)
  | .address => .ok (.literalStr "")
  | .hash => .ok hashZeroExpr
  | .fixedArray _ _ | .array _ => .ok (.listLit #[])
  | .structType _ => .ok (.mapLit #[])
  | .bytes | .string =>
      .error { message := s!"cannot zero-initialize type for Quint: {t.name}" }

def zeroExprForState (s : StateDecl) (structs : Array StructDecl) : Except LowerError (Array (String × Expr)) := do
  let flat := flatFieldsForStateDecl s structs
  if !flat.isEmpty then do
      let mut entries := #[]
      for field in flat do
        entries := entries.push (field.varName, ← zeroExpr field.type)
      .ok entries
  else
    match s.kind with
    | .array cap =>
        let z ← zeroExpr s.type
        .ok #[(s.id, .listLit (Array.replicate cap z))]
    | .map _ _ =>
        .ok #[(s.id, emptyMapExpr)]
    | .scalar | .dynamicArray =>
        let z ← zeroExpr s.type
        .ok #[(s.id, z)]

def initAction (state : Array StateDecl) (structs : Array StructDecl) : Except LowerError Action := do
  let mut clauses := #[]
  for decl in state do
    let zeros ← zeroExprForState decl structs
    for (name, value) in zeros do
      clauses := clauses.push (.assign (.prime (.local name)) value)
  let body :=
    if clauses.isEmpty then
      ActionClause.all #[.guard (.literalBool true)]
    else
      ActionClause.all clauses
  pure {
    name := "init",
    body := body,
    ret? := none
  }

def paramDomainExpr (scenario : Scenario.Config) (t : QuintType) : Expr :=
  match t with
  | .str => .oneOf (.local "USERS")
  | .hashStr => .oneOf (.setLit hashKeySamples)
  | .bool => .oneOf (.setLit #[.literalBool true, .literalBool false])
  | _ =>
      let low := if scenario.indexFromZero then .literalInt 0 else .literalInt 1
      .oneOf (.range low (.local "MAX_UINT"))

def entrypointStepCall (scenario : Scenario.Config) (ep : Entrypoint) (params : Array (String × QuintType)) : ActionClause :=
  let rec buildNondet (remaining : List (String × QuintType)) (call : ActionClause) : ActionClause :=
    match remaining with
    | [] => call
    | (n, t) :: rest => buildNondet rest (.nondet n (paramDomainExpr scenario t) call)
  let baseCall := ActionClause.call (sanitizeName ep.name) (params.map (fun (n, _) => .local n))
  if params.isEmpty then
    baseCall
  else
    buildNondet params.toList.reverse baseCall

def stepAction (scenario : Scenario.Config) (entrypoints : Array Entrypoint) (loweredParams : Array (Array (String × QuintType))) : Action :=
  let pairs := Array.zip entrypoints loweredParams
  let calls := pairs.map (fun (ep, params) => entrypointStepCall scenario ep params)
  {
    name := "step",
    body := ActionClause.any calls,
    ret? := none
  }

def lowerModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError Module := do
  let stateVarPairs ← quintStateVars module.state module.structs
  let vars := stateVarPairs.map (fun (name, type) => { name, type })
  let init ← initAction module.state module.structs
  let stateIds := expandedStateIds module.state module.structs
  let loweredEps ← module.entrypoints.mapM (fun ep =>
    lowerEntrypoint ep stateIds module.state module.structs scenario.maxLoopUnroll)
  let epActions := loweredEps.map (·.action)
  let whilePureDefs := loweredEps.foldl (fun acc ep => acc ++ ep.pureDefs) #[]
  let epParams ← module.entrypoints.mapM (fun ep => do
    ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t)))
  let step := stepAction scenario module.entrypoints epParams
  let vals ← match Invariants.derive module scenario with
    | .ok vs => .ok vs
    | .error e => .error { message := e }
  let temporals ← match Liveness.derive module scenario with
    | .ok ts => .ok ts
    | .error e => .error { message := e }
  pure {
    name := s!"{module.name}Model",
    constants := #[],
    vars := vars,
    pureDefs := scenario.quintPureDefs ++ whilePureDefs,
    actions := #[init] ++ epActions ++ #[step],
    vals := vals,
    temporals := temporals
  }

def renderModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError String := do
  let qm ← lowerModule module scenario
  pure (Emit.emitModule qm)

end ProofForge.Backend.Quint.Lower