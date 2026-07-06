import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Emit
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Invariants

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
  guards : Array ActionClause := #[]
  stateDecls : Array StateDecl := #[]
  structs : Array StructDecl := #[]
  pureDefs : Array PureDef := #[]
  maxLoopUnroll : Nat := 10
  /-- When false, `__while_*` step locals stay symbolic during unrolling. -/
  expandLocals : Bool := true

def hashLiteralStr (a b c d : Nat) : String :=
  s!"hash:{a}:{b}:{c}:{d}"

def structFieldVarName (stateId fieldName : String) : String :=
  s!"{stateId}_{fieldName}"

def arrayStructFieldVarName (stateId : String) (index : Nat) (fieldName : String) : String :=
  s!"{stateId}_{index}_{fieldName}"

def lookupStructDecl (structs : Array StructDecl) (name : String) : Option StructDecl :=
  structs.find? (fun s => s.name == name)

def irExprNat? (e : ProofForge.IR.Expr) : Option Nat :=
  match e with
  | .literal (.u8 n) | .literal (.u32 n) | .literal (.u64 n) | .literal (.u128 n) => some n
  | _ => none

inductive StoragePathTarget where
  | flatVar (name : String)
  | arraySlot (stateId : String) (cap : Nat) (index : ProofForge.IR.Expr)
  | arrayStructFieldSlot (stateId : String) (cap : Nat) (index : ProofForge.IR.Expr) (fieldName : String)
  | mapSlot (stateId : String) (key : ProofForge.IR.Expr)
  | nestedMapSlot (stateId : String) (key1 key2 : ProofForge.IR.Expr)
  deriving Repr, Nonempty

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

partial def resolveStoragePathSegments (structs : Array StructDecl) (stateId : String)
    (current : ValueType) (segments : List StoragePathSegment) : Except LowerError StoragePathTarget :=
  match segments with
  | [] =>
      .error { message := s!"storage path for state `{stateId}` must contain at least one segment" }
  | [.field fieldName] =>
      match current with
      | .structType _ => .ok (.flatVar (structFieldVarName stateId fieldName))
      | other => .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | [.index index] =>
      match current with
      | .fixedArray (.structType _) _ =>
          .error { message := s!"storage path index on struct array `{stateId}` requires a following field segment" }
      | .fixedArray _ length => .ok (.arraySlot stateId length index)
      | other => .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | [.index index, .field fieldName] =>
      match current with
      | .fixedArray (.structType _) length =>
          match irExprNat? index with
          | some n =>
              if n >= length then
                .error { message := s!"storage path index {n} out of bounds for array `{stateId}` (length {length})" }
              else
                .ok (.flatVar (arrayStructFieldVarName stateId n fieldName))
          | none => .ok (.arrayStructFieldSlot stateId length index fieldName)
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
                  resolveStoragePathSegments structs stateId field.type segments.tail!
              | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"storage path references unknown struct `{typeName}`" }
      | other => .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | .index _ :: rest =>
      match current with
      | .fixedArray element length =>
          resolveStoragePathSegments structs stateId element rest
      | other => .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | .mapKey _ :: _ =>
      .error { message := "nested map-key storage paths beyond two segments are not supported in Quint lowering v1" }

def resolveStoragePathTarget (structs : Array StructDecl) (state : StateDecl)
    (path : Array StoragePathSegment) : Except LowerError StoragePathTarget := do
  if path.isEmpty then
    .error { message := s!"storage path for state `{state.id}` must contain at least one segment" }
  match state.kind, path.toList with
  | .map _ _, [.mapKey key] => .ok (.mapSlot state.id key)
  | .map _ _, [.mapKey key1, .mapKey key2] => .ok (.nestedMapSlot state.id key1 key2)
  | .map _ _, _ =>
      .error { message := s!"map storage path for `{state.id}` must be one or two consecutive mapKey segments" }
  | _, _ => do
      let (start, segments) ← storagePathStartType state path
      resolveStoragePathSegments structs state.id start segments

def stateVarEntries (decl : StateDecl) (structs : Array StructDecl) :
    Except LowerError (Array (String × ValueType)) := do
  match decl.kind with
  | .array cap =>
      match decl.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => do
              let mut entries := #[]
              for index in [0:cap] do
                for field in structDecl.fields do
                  entries := entries.push (
                    arrayStructFieldVarName decl.id index field.id,
                    field.type)
              .ok entries
          | none => pure #[(decl.id, decl.type)]
      | _ => pure #[(decl.id, decl.type)]
  | .scalar | .dynamicArray =>
      match decl.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => .ok (structDecl.fields.map (fun field =>
              (structFieldVarName decl.id field.id, field.type)))
          | none => pure #[(decl.id, decl.type)]
      | _ => pure #[(decl.id, decl.type)]
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
    | .structLit _ fields => do
        let entries ← fields.mapM (fun (fieldName, fieldExpr) => do
          pure (.literalStr fieldName, ← lowerExpr ctx fieldExpr))
        .ok (.mapLit entries)
    | .field base fieldName => do
        let base' ← lowerExpr ctx base
        .ok (.methodCall base' "get" #[.literalStr fieldName])
    | .effect eff => lowerEffectExpr ctx eff
    | _ => .error { message := "unsupported IR expression for Quint lowering v1" }

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

  partial def mapPathSegmentExpr (_ : LowerCtx) (key : ProofForge.IR.Expr) : Except LowerError Expr :=
    match mapPathSegmentLiteral? key with
    | some segment => .ok (.literalStr segment)
    | none =>
        .error { message := "map path key segments require literal keys in Quint lowering v1" }

  partial def nestedMapKeyExpr (ctx : LowerCtx) (key1 key2 : ProofForge.IR.Expr) : Except LowerError Expr := do
    let seg1 ← mapPathSegmentExpr ctx key1
    let seg2 ← mapPathSegmentExpr ctx key2
    match seg1, seg2 with
    | .literalStr s1, .literalStr s2 => .ok (.literalStr (s1 ++ s2))
    | _, _ =>
        .error { message := "nested map path keys require literal keys in Quint lowering v1" }

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
    | .mapSlot stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerMapKeyExpr ctx key
        .ok (some (mapContainsExpr key' mapExpr))
    | .nestedMapSlot stateId key1 key2 => do
        let mapExpr := ctx.stateValue stateId
        let key' ← nestedMapKeyExpr ctx key1 key2
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

  partial def arrayStructFieldWriteCtx (ctx : LowerCtx) (stateId : String) (cap : Nat)
      (index : ProofForge.IR.Expr) (fieldName : String) (value : ProofForge.IR.Expr)
      (combine : Expr → Expr → Expr → Expr) : Except LowerError LowerCtx := do
    let idx' ← lowerExpr ctx index
    let value' ← lowerExpr ctx value
    let mut nextCtx := ctx
    for i in [0:cap] do
      let name := arrayStructFieldVarName stateId i fieldName
      let cond := .binOp .eq idx' (.literalInt (Int.ofNat i))
      let cur := ctx.stateValue name
      let updated := combine cond value' cur
      nextCtx := { nextCtx with state := nextCtx.state.upsert name updated }
    .ok nextCtx

  partial def targetReadExpr (ctx : LowerCtx) (target : StoragePathTarget) : Except LowerError Expr :=
    match target with
    | .flatVar name => .ok (ctx.stateValue name)
    | .arraySlot stateId cap index => do
        let idx' ← lowerExpr ctx index
        .ok (.index (ctx.stateValue stateId) (irIndexToQuint idx'))
    | .arrayStructFieldSlot stateId cap index fieldName =>
        arrayStructFieldReadExpr ctx stateId cap index fieldName
    | .mapSlot stateId key => lowerMapGetExpr ctx stateId key
    | .nestedMapSlot stateId key1 key2 => do
        let key' ← nestedMapKeyExpr ctx key1 key2
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
    | .mapSlot stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerMapKeyExpr ctx key
        let value' ← lowerExpr ctx value
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok { ctx with state := ctx.state.upsert stateId updated }
    | .nestedMapSlot stateId key1 key2 => do
        let mapExpr := ctx.stateValue stateId
        let key' ← nestedMapKeyExpr ctx key1 key2
        let value' ← lowerExpr ctx value
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok { ctx with state := ctx.state.upsert stateId updated }

  partial def targetMapAssignOpCtx (ctx : LowerCtx) (stateId : String) (key : Expr) (op : AssignOp)
      (value : ProofForge.IR.Expr) : Except LowerError LowerCtx := do
    let mapExpr := ctx.stateValue stateId
    let old ← lowerMapGetAtKey ctx stateId key
    let value' ← lowerExpr ctx value
    let qop := lowerAssignOp op
    let updated := .methodCall mapExpr "put" #[key, .binOp qop old value']
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
    | .mapSlot stateId key => do
        let key' ← lowerMapKeyExpr ctx key
        targetMapAssignOpCtx ctx stateId key' op value
    | .nestedMapSlot stateId key1 key2 => do
        let key' ← nestedMapKeyExpr ctx key1 key2
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
            | some _ =>
                let mut nextCtx := ctx
                for (fieldName, fieldExpr) in fields do
                  let fieldValue ← lowerExpr nextCtx fieldExpr
                  nextCtx := { nextCtx with
                    state := nextCtx.state.upsert (structFieldVarName stateId fieldName) fieldValue }
                .ok nextCtx
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
    | .storagePathWrite stateId path value =>
        match ctx.lookupStateDecl stateId with
        | some decl =>
            match resolveStoragePathTarget ctx.structs decl path with
            | .ok target => targetWriteCtx ctx target value
            | .error err => .error err
        | none => .error { message := s!"unknown state `{stateId}` for storagePathWrite" }
    | .storagePathAssignOp stateId path op value =>
        match ctx.lookupStateDecl stateId with
        | some decl =>
            match resolveStoragePathTarget ctx.structs decl path with
            | .ok target => targetAssignOpCtx ctx target op value
            | .error err => .error err
        | none => .error { message := s!"unknown state `{stateId}` for storagePathAssignOp" }
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
    | .letBind name _ value =>
        match value with
        | .effect eff =>
            let (ctx', expr) ← lowerMutatingEffectBinding ctx eff
            .ok { ctx' with locals := ctx'.locals.bind name expr }
        | _ =>
            .ok { ctx with locals := ctx.locals.bind name (← lowerExpr ctx value) }
    | .letMutBind name _ value =>
        .ok { ctx with locals := ctx.locals.bind name (← lowerExpr ctx value) }
    | .assign _ _ =>
        .error { message := "local assignment not supported in Quint lowering v1" }
    | .assignOp _ _ _ =>
        .error { message := "compound local assignment not supported in Quint lowering v1" }
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
        .ok { ctx with
          state := mergedState,
          guards := ctx.guards ++ thenWrapped ++ elseWrapped }
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
        match ← effectPresenceGuard ctx eff with
        | some guard => .ok { ctx with guards := ctx.guards.push (.guard guard) }
        | none => .ok ctx
    | .return _ | .release _ =>
        .ok ctx

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
    maxLoopUnroll := maxLoopUnroll } ep.body
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
  match s.kind with
  | .array cap =>
      match s.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => do
              let mut entries := #[]
              for index in [0:cap] do
                for field in structDecl.fields do
                  entries := entries.push (
                    arrayStructFieldVarName s.id index field.id,
                    ← zeroExpr field.type)
              .ok entries
          | none => do
              let z ← zeroExpr s.type
              .ok #[(s.id, .listLit (Array.replicate cap z))]
      | _ => do
          let z ← zeroExpr s.type
          .ok #[(s.id, .listLit (Array.replicate cap z))]
  | .map _ _ =>
      .ok #[(s.id, emptyMapExpr)]
  | .scalar | .dynamicArray =>
      match s.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => do
              let mut entries := #[]
              for field in structDecl.fields do
                entries := entries.push (structFieldVarName s.id field.id, ← zeroExpr field.type)
              .ok entries
          | none =>
              let z ← zeroExpr s.type
              .ok #[(s.id, z)]
      | _ =>
          let z ← zeroExpr s.type
          .ok #[(s.id, z)]

def initAction (state : Array StateDecl) (structs : Array StructDecl) : Except LowerError Action := do
  let mut clauses := #[]
  for decl in state do
    let zeros ← zeroExprForState decl structs
    for (name, value) in zeros do
      clauses := clauses.push (.assign (.prime (.local name)) value)
  pure {
    name := "init",
    body := ActionClause.all clauses,
    ret? := none
  }

def hashKeySamples : Array Expr := #[
  .literalStr "hash:1001:0:0:0",
  .literalStr "hash:2002:0:0:0",
  .literalStr "hash:3003:0:0:0"
]

def paramDomainExpr (t : QuintType) : Expr :=
  match t with
  | .str => .oneOf (.local "USERS")
  | .hashStr => .oneOf (.setLit hashKeySamples)
  | _ => .oneOf (.range (.literalInt 1) (.local "MAX_UINT"))

def entrypointStepCall (ep : Entrypoint) (params : Array (String × QuintType)) : ActionClause :=
  let rec buildNondet (remaining : List (String × QuintType)) (call : ActionClause) : ActionClause :=
    match remaining with
    | [] => call
    | (n, t) :: rest => buildNondet rest (.nondet n (paramDomainExpr t) call)
  let baseCall := ActionClause.call (sanitizeName ep.name) (params.map (fun (n, _) => .local n))
  if params.isEmpty then
    baseCall
  else
    buildNondet params.toList.reverse baseCall

def stepAction (entrypoints : Array Entrypoint) (loweredParams : Array (Array (String × QuintType))) : Action :=
  let pairs := Array.zip entrypoints loweredParams
  let calls := pairs.map (fun (ep, params) => entrypointStepCall ep params)
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
  let step := stepAction module.entrypoints epParams
  let vals ← match Invariants.derive module scenario with
    | .ok vs => .ok vs
    | .error e => .error { message := e }
  pure {
    name := s!"{module.name}Model",
    constants := #[],
    vars := vars,
    pureDefs := scenario.quintPureDefs ++ whilePureDefs,
    actions := #[init] ++ epActions ++ #[step],
    vals := vals
  }

def renderModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError String := do
  let qm ← lowerModule module scenario
  pure (Emit.emitModule qm)

end ProofForge.Backend.Quint.Lower