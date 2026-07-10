import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

/-! # EVM storage and helper plan primitives

Storage layout, helper sets, slot/target plans, and module-level helper discovery
shared by the EVM semantic plan and lowering passes.
-/

namespace ProofForge.Backend.Evm.Plan

open ProofForge.IR
open ProofForge.Target

structure PlanError where
  message : String
  deriving Repr, Inhabited

def PlanError.render (err : PlanError) : String :=
  err.message

instance : ProofForge.Backend.Diagnostic.LoweringError PlanError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "evm" }

def PlanError.fromDiagnostic (err : Diagnostic) : PlanError := {
  message := err.render
}

def stateSlotSpan (module : Module) (state : StateDecl) : Nat :=
  match state.kind, state.type with
  | .scalar, .structType typeName =>
      match module.structs.find? (fun decl => decl.name == typeName) with
      | some decl => decl.fields.size
      | none => 1
  | .array length, .structType typeName =>
      match module.structs.find? (fun decl => decl.name == typeName) with
      | some decl => length * decl.fields.size
      | none => length
  | .array length, _ => length
  | .dynamicArray, _ => 1
  | .scalar, _ | .map _ _, _ => 1

structure StorageStatePlan where
  id : String
  slot : Nat
  span : Nat
  kind : StateKind
  type : ValueType
  byteOffset : Nat := 0
  byteWidth : Nat := 32
  deriving Repr

structure StorageLayout where
  states : Array StorageStatePlan
  deriving Repr

def storageLayout (module : Module) : StorageLayout := {
  states := go 0 0 0 module.state #[]
}
where
  go (idx slot usedBytes : Nat) (states : Array StateDecl) (acc : Array StorageStatePlan) : Array StorageStatePlan :=
    if h : idx < states.size then
      let state := states[idx]
      let span := stateSlotSpan module state
      let w := state.type.byteWidth
      -- Only scalar states with byteWidth > 0 and < 32 can be packed.
      -- Arrays, maps, structs, hash (32 bytes), bytes/string always start a new slot.
      let canPack := state.kind == .scalar && w > 0 && w < 32
      if canPack && usedBytes + w <= 32 then
        -- Pack into current slot
        go (idx + 1) slot (usedBytes + w) states (acc.push {
          id := state.id
          slot
          span := 0
          kind := state.kind
          type := state.type
          byteOffset := usedBytes
          byteWidth := w
        })
      else if canPack then
        -- Packed scalar that doesn't fit current slot: start a new slot, span 0
        let nextSlot := if usedBytes > 0 then slot + 1 else slot
        go (idx + 1) nextSlot w states (acc.push {
          id := state.id
          slot := nextSlot
          span := 0
          kind := state.kind
          type := state.type
          byteOffset := 0
          byteWidth := w
        })
      else
        -- Non-packable state: start a new slot with its span
        let nextSlot := if usedBytes > 0 then slot + 1 else slot
        go (idx + 1) (nextSlot + span) 0 states (acc.push {
          id := state.id
          slot := nextSlot
          span
          kind := state.kind
          type := state.type
          byteOffset := 0
          byteWidth := if canPack then w else 32
        })
    else
      acc

def StorageLayout.find? (layout : StorageLayout) (stateId : String) : Option StorageStatePlan :=
  layout.states.find? (fun state => state.id == stateId)

def stateInfo? (module : Module) (stateId : String) : Option (Nat × StateDecl) :=
  match module.state.find? (fun s => s.id == stateId) with
  | some state =>
    match storageLayout module |>.find? stateId with
    | some plan => some (plan.slot, state)
    | none => none
  | none => none

def stateSlot? (module : Module) (stateId : String) : Option Nat :=
  match stateInfo? module stateId with
  | some (slot, _) => some slot
  | none => none

inductive Helper where
  | mapSlot
  | mapPresenceSlot
  | mapWrite
  | mapSetReturn
  | mapAssign (op : AssignOp)
  | arraySlot
  | structArraySlot
  | dynamicArraySlot
  | memoryArrayNew
  | memoryArrayGet
  | hashWord
  | hashPair
  | ecrecover
  | eip712PermitDigest
  deriving DecidableEq, Repr

def Helper.beq : Helper → Helper → Bool
  | .mapSlot, .mapSlot => true
  | .mapPresenceSlot, .mapPresenceSlot => true
  | .mapWrite, .mapWrite => true
  | .mapSetReturn, .mapSetReturn => true
  | .mapAssign lhs, .mapAssign rhs => lhs == rhs
  | .arraySlot, .arraySlot => true
  | .structArraySlot, .structArraySlot => true
  | .dynamicArraySlot, .dynamicArraySlot => true
  | .memoryArrayNew, .memoryArrayNew => true
  | .memoryArrayGet, .memoryArrayGet => true
  | .hashWord, .hashWord => true
  | .hashPair, .hashPair => true
  | .ecrecover, .ecrecover => true
  | .eip712PermitDigest, .eip712PermitDigest => true
  | _, _ => false

instance : BEq Helper := ⟨Helper.beq⟩

def assignOpHelperSuffix : AssignOp → String
  | .add => "add"
  | .sub => "sub"
  | .mul => "mul"
  | .div => "div"
  | .mod => "mod"
  | .bitAnd => "and"
  | .bitOr => "or"
  | .bitXor => "xor"
  | .shiftLeft => "shl"
  | .shiftRight => "shr"

def Helper.name : Helper → String
  | .mapSlot => "__proof_forge_map_slot"
  | .mapPresenceSlot => "__proof_forge_map_presence_slot"
  | .mapWrite => "__proof_forge_map_write"
  | .mapSetReturn => "__proof_forge_map_set_return"
  | .mapAssign op => s!"__proof_forge_map_assign_{assignOpHelperSuffix op}"
  | .arraySlot => "__proof_forge_array_slot"
  | .structArraySlot => "__proof_forge_struct_array_slot"
  | .dynamicArraySlot => "__proof_forge_dynamic_array_slot"
  | .memoryArrayNew => "__proof_forge_memory_array_new"
  | .memoryArrayGet => "__proof_forge_memory_array_get"
  | .hashWord => "__proof_forge_hash_word"
  | .hashPair => "__proof_forge_hash_pair"
  | .ecrecover => "__proof_forge_ecrecover"
  | .eip712PermitDigest => "__proof_forge_eip712_permit_digest"

abbrev HelperSet := Array Helper

namespace HelperSet

def contains (helpers : HelperSet) (helper : Helper) : Bool :=
  helpers.any (fun existing => existing == helper)

def insert (helpers : HelperSet) (helper : Helper) : HelperSet :=
  if contains helpers helper then
    helpers
  else
    helpers.push helper

end HelperSet

inductive ValuePlan where
  | irExpr (expr : Expr)
  deriving Repr

def ValuePlan.fromExpr (expr : Expr) : ValuePlan :=
  .irExpr expr

inductive StorageSlotPlan where
  | scalarSlot (slot : Nat)
  | fixedSlot (slotHex : String)
  | mapValueSlot (rootSlot : Nat) (keys : Array ValuePlan)
  | mapPresenceSlot (rootSlot : Nat) (keys : Array ValuePlan)
  | arraySlot (rootSlot length : Nat) (index : ValuePlan)
  | structArrayFieldSlot (rootSlot length fieldCount fieldOffset : Nat) (index : ValuePlan)
  | dynamicArraySlot (rootSlot : Nat) (index : ValuePlan)
  deriving Repr

/-- Destination-width behavior for scalar storage writes.

This is part of the semantic plan so the ToYul pass never has to infer write
behavior from the shape of the value expression. -/
inductive ScalarStorageWriteSemantics where
  | checked
  | wrapping
  deriving BEq, Repr

def ScalarStorageWriteSemantics.fromOverflowChecked : Bool → ScalarStorageWriteSemantics
  | true => .checked
  | false => .wrapping

def ScalarStorageWriteSemantics.overflowChecked : ScalarStorageWriteSemantics → Bool
  | .checked => true
  | .wrapping => false

structure ScalarStorageTargetPlan where
  slot : StorageSlotPlan
  byteOffset : Nat
  byteWidth : Nat
  writeSemantics : ScalarStorageWriteSemantics := .checked
  deriving Repr

inductive StoragePathWriteTargetPlan where
  | mapWrite (rootSlot : Nat) (key : ValuePlan)
  | singleSlot (slot : StorageSlotPlan)
  | mapValuePresence (valueSlot presenceSlot : StorageSlotPlan)
  deriving Repr

def StorageSlotPlan.keyCount : StorageSlotPlan → Nat
  | .scalarSlot _ => 0
  | .fixedSlot _ => 0
  | .mapValueSlot _ keys => keys.size
  | .mapPresenceSlot _ keys => keys.size
  | .arraySlot .. => 0
  | .structArrayFieldSlot .. => 0
  | .dynamicArraySlot .. => 0

def StorageSlotPlan.requiredHelpers : StorageSlotPlan → HelperSet
  | .scalarSlot _ => #[]
  | .fixedSlot _ => #[]
  | .mapValueSlot _ _ => #[Helper.mapSlot]
  | .mapPresenceSlot _ keys =>
      let helpers : HelperSet := #[Helper.mapPresenceSlot]
      if keys.size > 1 then
        HelperSet.insert helpers Helper.mapSlot
      else
        helpers
  | .arraySlot .. => #[Helper.arraySlot]
  | .structArrayFieldSlot .. => #[Helper.structArraySlot]
  | .dynamicArraySlot .. => #[Helper.dynamicArraySlot]

structure MapStatePlan where
  stateId : String
  rootSlot : Nat
  keyType : ValueType
  valueType : ValueType
  capacity : Nat
  deriving Repr

structure MapWriteTargetPlan where
  rootSlot : Nat
  deriving Repr

structure MapReadTargetPlan where
  rootSlot : Nat
  deriving Repr

structure ArrayWriteTargetPlan where
  rootSlot : Nat
  length : Nat
  deriving Repr

structure ArrayReadTargetPlan where
  rootSlot : Nat
  length : Nat
  deriving Repr

structure DynamicArrayTargetPlan where
  rootSlot : Nat
  deriving Repr

structure StructFieldWriteTargetPlan where
  slot : StorageSlotPlan
  deriving Repr

structure StructFieldReadTargetPlan where
  slot : StorageSlotPlan
  deriving Repr

structure StructArrayFieldWriteTargetPlan where
  rootSlot : Nat
  length : Nat
  fieldCount : Nat
  fieldOffset : Nat
  deriving Repr

structure StructArrayFieldReadTargetPlan where
  rootSlot : Nat
  length : Nat
  fieldCount : Nat
  fieldOffset : Nat
  deriving Repr

def requireState (module : Module) (stateId : String) : Except PlanError (Nat × StateDecl) :=
  match stateInfo? module stateId with
  | some info => .ok info
  | none => .error { message := s!"unknown EVM state '{stateId}'" }

def requireMapState (module : Module) (stateId : String) : Except PlanError MapStatePlan := do
  let (slot, state) ← requireState module stateId
  match state.kind with
  | .map keyType capacity => .ok {
      stateId
      rootSlot := slot
      keyType
      valueType := state.type
      capacity
    }
  | .scalar | .array _ | .dynamicArray =>
      .error { message := s!"EVM storage state '{stateId}' is not a map" }

def mapWriteTargetPlan (module : Module) (stateId : String) : Except PlanError MapWriteTargetPlan := do
  let mapState ← requireMapState module stateId
  .ok { rootSlot := mapState.rootSlot }

def mapReadTargetPlan (module : Module) (stateId : String) : Except PlanError MapReadTargetPlan := do
  let mapState ← requireMapState module stateId
  .ok { rootSlot := mapState.rootSlot }

def scalarSlotPlan (module : Module) (stateId : String) : Except PlanError StorageSlotPlan := do
  if stateId == "$eip1967.implementation" then
    .ok (.fixedSlot "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")
  else
    let (slot, state) ← requireState module stateId
    match state.kind with
    | .scalar => .ok (.scalarSlot slot)
    | .map _ _ | .array _ | .dynamicArray =>
        .error { message := s!"EVM storage state '{stateId}' is not a scalar slot" }

def scalarStorageTargetPlan (module : Module) (stateId : String) : Except PlanError ScalarStorageTargetPlan := do
  let slot ← scalarSlotPlan module stateId
  let writeSemantics :=
    ScalarStorageWriteSemantics.fromOverflowChecked module.overflowChecked
  if stateId == "$eip1967.implementation" then
    .ok {
      slot
      byteOffset := 0
      byteWidth := 32
      writeSemantics
    }
  else
    match storageLayout module |>.find? stateId with
    | some plan =>
        match plan.kind, plan.type with
        | .scalar, .structType typeName =>
            .error { message := s!"EVM scalar storage target plan does not support struct state '{stateId}' of type '{typeName}'" }
        | .scalar, _ =>
            .ok {
              slot
              byteOffset := plan.byteOffset
              byteWidth := plan.byteWidth
              writeSemantics
            }
        | .map _ _, _ | .array _, _ | .dynamicArray, _ =>
            .error { message := s!"EVM storage state '{stateId}' is not a scalar target" }
    | none =>
        .error { message := s!"unknown EVM state '{stateId}'" }

def mapValueSlotPlan (module : Module) (stateId : String) (keys : Array Expr) : Except PlanError StorageSlotPlan := do
  let mapState ← requireMapState module stateId
  if keys.isEmpty then
    .error { message := s!"EVM map storage path for '{stateId}' must contain at least one mapKey segment" }
  else
    .ok (.mapValueSlot mapState.rootSlot (keys.map ValuePlan.fromExpr))

def mapPresenceSlotPlan (module : Module) (stateId : String) (keys : Array Expr) : Except PlanError StorageSlotPlan := do
  let mapState ← requireMapState module stateId
  if keys.isEmpty then
    .error { message := s!"EVM map storage path for '{stateId}' must contain at least one mapKey segment" }
  else
    .ok (.mapPresenceSlot mapState.rootSlot (keys.map ValuePlan.fromExpr))

def storagePathMapKeys? (path : Array StoragePathSegment) : Option (Array Expr) :=
  go 0 #[]
where
  go (idx : Nat) (acc : Array Expr) : Option (Array Expr) :=
    if h : idx < path.size then
      match path[idx] with
      | .mapKey key => go (idx + 1) (acc.push key)
      | .field _ | .index _ => none
    else if acc.isEmpty then
      none
    else
      some acc

def storagePathMapValueSlotPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathSegment) : Except PlanError StorageSlotPlan :=
  match storagePathMapKeys? path with
  | some keys => mapValueSlotPlan module stateId keys
  | none =>
      .error { message := "EVM plan supports map storage paths only as one or more mapKey segments" }

def storagePathMapPresenceSlotPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathSegment) : Except PlanError StorageSlotPlan :=
  match storagePathMapKeys? path with
  | some keys => mapPresenceSlotPlan module stateId keys
  | none =>
      .error { message := "EVM plan supports map storage paths only as one or more mapKey segments" }

def isStorageWordType : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? (fun decl => decl.name == name)

def findStructFieldWithOffset? (decl : StructDecl) (fieldName : String) : Option (Nat × StructField) :=
  Id.run do
    let mut found : Option (Nat × StructField) := none
    for h : idx in [0:decl.fields.size] do
      if found.isNone then
        let field := decl.fields[idx]
        if field.id == fieldName then
          found := some (idx, field)
    pure found

def requireArrayState (module : Module) (stateId : String) : Except PlanError (Nat × Nat × ValueType) := do
  let (slot, state) ← requireState module stateId
  match state.kind, state.type with
  | .array length, elementType =>
      if length == 0 then
        .error { message := s!"EVM array state '{stateId}' must have non-zero length" }
      else if isStorageWordType elementType then
        .ok (slot, length, elementType)
      else
        .error { message := s!"EVM array state '{stateId}' has unsupported slot element type '{elementType.name}'" }
  | .scalar, _ | .map _ _, _ | .dynamicArray, _ =>
      .error { message := s!"EVM storage state '{stateId}' is not a fixed array" }

def arrayWriteTargetPlan (module : Module) (stateId : String) : Except PlanError ArrayWriteTargetPlan := do
  let (rootSlot, length, _) ← requireArrayState module stateId
  .ok { rootSlot, length }

def arrayReadTargetPlan (module : Module) (stateId : String) : Except PlanError ArrayReadTargetPlan := do
  let (rootSlot, length, _) ← requireArrayState module stateId
  .ok { rootSlot, length }

def requireStructArrayStateField
    (module : Module)
    (stateId fieldName : String) : Except PlanError (Nat × Nat × Nat × Nat × StructField) := do
  let (slot, state) ← requireState module stateId
  match state.kind, state.type with
  | .array length, .structType typeName => do
      if length == 0 then
        .error { message := s!"EVM array state '{stateId}' must have non-zero length" }
      let some decl := findStruct? module typeName
        | .error { message := s!"EVM array state '{stateId}' uses unknown struct '{typeName}'" }
      let some (fieldOffset, field) := findStructFieldWithOffset? decl fieldName
        | .error { message := s!"EVM struct array state '{stateId}' has no field '{fieldName}'" }
      .ok (slot, length, decl.fields.size, fieldOffset, field)
  | .array _, other =>
      .error { message := s!"EVM storage state '{stateId}' is array storage, but not a struct array; got '{other.name}'" }
  | .dynamicArray, other =>
      .error { message := s!"EVM storage state '{stateId}' is a dynamic array, not a fixed struct array; got '{other.name}'" }
  | .scalar, _ | .map _ _, _ =>
      .error { message := s!"EVM storage state '{stateId}' is not a struct array" }

def arraySlotPlan (module : Module) (stateId : String) (index : Expr) : Except PlanError StorageSlotPlan := do
  let (slot, length, _) ← requireArrayState module stateId
  .ok (.arraySlot slot length (ValuePlan.fromExpr index))

def requireDynamicArrayState (module : Module) (stateId : String) : Except PlanError (Nat × ValueType) := do
  let (slot, state) ← requireState module stateId
  match state.kind, state.type with
  | .dynamicArray, elementType =>
      if isStorageWordType elementType then
        .ok (slot, elementType)
      else
        .error { message := s!"EVM dynamic array state '{stateId}' has unsupported element type '{elementType.name}'; only word types are supported" }
  | .scalar, _ | .map _ _, _ | .array _, _ =>
      .error { message := s!"EVM storage state '{stateId}' is not a dynamic array" }

def dynamicArrayTargetPlan (module : Module) (stateId : String) :
    Except PlanError DynamicArrayTargetPlan := do
  let (rootSlot, _) ← requireDynamicArrayState module stateId
  .ok { rootSlot }

def dynamicArraySlotPlan (module : Module) (stateId : String) (index : Expr) : Except PlanError StorageSlotPlan := do
  let (slot, _) ← requireDynamicArrayState module stateId
  .ok (.dynamicArraySlot slot (ValuePlan.fromExpr index))

def structArrayFieldSlotPlan
    (module : Module)
    (stateId : String)
    (index : Expr)
    (fieldName : String) : Except PlanError StorageSlotPlan := do
  let (slot, length, fieldCount, fieldOffset, _) ← requireStructArrayStateField module stateId fieldName
  .ok (.structArrayFieldSlot slot length fieldCount fieldOffset (ValuePlan.fromExpr index))

def structArrayFieldWriteTargetPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StructArrayFieldWriteTargetPlan := do
  let (rootSlot, length, fieldCount, fieldOffset, _) ←
    requireStructArrayStateField module stateId fieldName
  .ok { rootSlot, length, fieldCount, fieldOffset }

def structArrayFieldReadTargetPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StructArrayFieldReadTargetPlan := do
  let (rootSlot, length, fieldCount, fieldOffset, _) ←
    requireStructArrayStateField module stateId fieldName
  .ok { rootSlot, length, fieldCount, fieldOffset }

def ensureStructFieldWordType (typeName fieldName : String) (type : ValueType) : Except PlanError Unit :=
  if isStorageWordType type then
    .ok ()
  else
    .error {
      message :=
        s!"field `{fieldName}` in struct `{typeName}` has unsupported EVM IR v0 local struct field type `{type.name}`; local structs support U32, U64, Bool, Hash, or Address fields"
    }

def requireStructState
    (module : Module)
    (stateId : String) : Except PlanError (Nat × String × StructDecl) := do
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown struct state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .scalar, .structType typeName => do
          let some decl := findStruct? module typeName
            | .error { message := s!"state `{stateId}` uses unknown struct `{typeName}`" }
          if decl.fields.isEmpty then
            .error { message := s!"state `{stateId}` uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
          for field in decl.fields do
            ensureStructFieldWordType typeName field.id field.type
          .ok (slot, typeName, decl)
      | .scalar, other =>
          .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{other.name}`; expected struct storage" }
      | .array _, _ | .dynamicArray, _ =>
          .error { message := s!"state `{stateId}` is array storage, not scalar struct storage" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not scalar struct storage" }

def requireStructStateField
    (module : Module)
    (stateId fieldName : String) : Except PlanError (Nat × StructField) := do
  let (slot, typeName, decl) ← requireStructState module stateId
  let some (offset, field) := findStructFieldWithOffset? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  ensureStructFieldWordType typeName field.id field.type
  .ok (slot + offset, field)

def structFieldSlotPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StorageSlotPlan := do
  let (slot, _) ← requireStructStateField module stateId fieldName
  .ok (.scalarSlot slot)

def structFieldWriteTargetPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StructFieldWriteTargetPlan := do
  .ok { slot := (← structFieldSlotPlan module stateId fieldName) }

def structFieldReadTargetPlan
    (module : Module)
    (stateId fieldName : String) : Except PlanError StructFieldReadTargetPlan := do
  .ok { slot := (← structFieldSlotPlan module stateId fieldName) }

def storagePathWriteTargetPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathSegment) : Except PlanError StoragePathWriteTargetPlan :=
  match path.toList with
  | [StoragePathSegment.mapKey key] => do
      let mapState ← requireMapState module stateId
      .ok (.mapWrite mapState.rootSlot (ValuePlan.fromExpr key))
  | [StoragePathSegment.index index] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .array _ => .ok (.singleSlot (← arraySlotPlan module stateId index))
      | .dynamicArray => .ok (.singleSlot (← dynamicArraySlotPlan module stateId index))
      | .scalar | .map _ _ => .error { message := s!"storage path state `{stateId}` does not support index access" }
  | [StoragePathSegment.field fieldName] => do
      .ok (.singleSlot (← structFieldSlotPlan module stateId fieldName))
  | [StoragePathSegment.index index, StoragePathSegment.field fieldName] => do
      .ok (.singleSlot (← structArrayFieldSlotPlan module stateId index fieldName))
  | [] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .dynamicArray => .error { message := s!"storage path state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage paths" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.write" }
  | _ =>
      match storagePathMapKeys? path with
      | some _ => do
          .ok (.mapValuePresence
            (← storagePathMapValueSlotPlan module stateId path)
            (← storagePathMapPresenceSlotPlan module stateId path))
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

def storagePathReadSlotPlan
    (module : Module)
    (stateId : String)
    (path : Array StoragePathSegment) : Except PlanError StorageSlotPlan :=
  match path.toList with
  | [StoragePathSegment.mapKey key] =>
      mapValueSlotPlan module stateId #[key]
  | [StoragePathSegment.index index] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .array _ => arraySlotPlan module stateId index
      | .dynamicArray => dynamicArraySlotPlan module stateId index
      | .scalar | .map _ _ => .error { message := s!"storage path state `{stateId}` does not support index access" }
  | [StoragePathSegment.field fieldName] =>
      structFieldSlotPlan module stateId fieldName
  | [StoragePathSegment.index index, StoragePathSegment.field fieldName] =>
      structArrayFieldSlotPlan module stateId index fieldName
  | [] => do
      let (_, state) ← requireState module stateId
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .dynamicArray => .error { message := s!"storage path state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage paths" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.read" }
  | _ =>
      match storagePathMapKeys? path with
      | some _ =>
          storagePathMapValueSlotPlan module stateId path
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

def isSupportedMapState (state : StateDecl) : Bool :=
  match state.kind, state.type with
  | .map keyType _, valueType => isStorageWordType keyType && isStorageWordType valueType
  | _, _ => false

def moduleUsesSupportedMap (module : Module) : Bool :=
  module.state.any isSupportedMapState

def isSupportedArrayState (state : StateDecl) : Bool :=
  match state.kind, state.type with
  | .array length, elementType => length > 0 && isStorageWordType elementType
  | _, _ => false

def moduleUsesSupportedArray (module : Module) : Bool :=
  module.state.any isSupportedArrayState

def isSupportedDynamicArrayState (state : StateDecl) : Bool :=
  match state.kind, state.type with
  | .dynamicArray, elementType => isStorageWordType elementType
  | _, _ => false

def moduleUsesSupportedDynamicArray (module : Module) : Bool :=
  module.state.any isSupportedDynamicArrayState

def moduleUsesSupportedStructArray (module : Module) : Bool :=
  module.state.any fun state =>
    match state.kind, state.type with
    | .array length, .structType typeName =>
        length > 0 && (findStruct? module typeName).isSome
    | _, _ => false

def moduleUsesHash (module : Module) : Bool :=
  module.capabilities.contains .cryptoHash

def pushAssignOpIfMissing (acc : Array AssignOp) (value : AssignOp) : Array AssignOp :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeAssignOpSets (lhs rhs : Array AssignOp) : Array AssignOp :=
  rhs.foldl pushAssignOpIfMissing lhs

mutual
  partial def storagePathAssignOpsStatement : Statement → Array AssignOp
    | .effect (.storagePathAssignOp _ _ op _) =>
        #[op]
    | .ifElse _ thenBody elseBody =>
        mergeAssignOpSets (storagePathAssignOpsStatements thenBody) (storagePathAssignOpsStatements elseBody)
    | .boundedFor _ _ _ body =>
        storagePathAssignOpsStatements body
    | _ =>
        #[]

  partial def storagePathAssignOpsStatements (statements : Array Statement) : Array AssignOp :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeAssignOpSets acc (storagePathAssignOpsStatement stmt)
end

def moduleStoragePathAssignOps (module : Module) : Array AssignOp :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeAssignOpSets acc (storagePathAssignOpsStatements entrypoint.body)

def baseMapHelpers : HelperSet := #[
  .mapSlot,
  .mapPresenceSlot,
  .mapWrite,
  .mapSetReturn
]

def moduleHelpers (module : Module) : HelperSet :=
  let helpers : HelperSet :=
    if moduleUsesSupportedMap module then baseMapHelpers else #[]
  let helpers :=
    if moduleUsesSupportedMap module then
      moduleStoragePathAssignOps module |>.foldl
        (fun acc op => HelperSet.insert acc (.mapAssign op))
        helpers
    else
      helpers
  let helpers :=
    if moduleUsesSupportedArray module then
      HelperSet.insert helpers .arraySlot
    else
      helpers
  let helpers :=
    if moduleUsesSupportedStructArray module then
      HelperSet.insert helpers .structArraySlot
    else
      helpers
  let helpers :=
    if moduleUsesSupportedDynamicArray module then
      HelperSet.insert helpers .dynamicArraySlot
    else
      helpers
  let helpers :=
    if module.capabilities.contains .dataDynamicArray then
      HelperSet.insert (HelperSet.insert helpers .memoryArrayNew) .memoryArrayGet
    else
      helpers
  if moduleUsesHash module then
    HelperSet.insert (HelperSet.insert helpers .hashWord) .hashPair
  else
    helpers

def helperMapAssignOps (helpers : HelperSet) : Array AssignOp :=
  helpers.foldl
    (fun acc helper =>
      match helper with
      | .mapAssign op => pushAssignOpIfMissing acc op
      | _ => acc)
    #[]


end ProofForge.Backend.Evm.Plan
