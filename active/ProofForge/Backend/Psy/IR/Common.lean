/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Psy IR Lowering Common State and Validation Helpers

Shared error, storage-layout, type, identifier, and assignment helpers for the
Psy portable IR lowering pipeline.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Psy.Plan

namespace ProofForge.Backend.Psy.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

def diagnosticError (err : Diagnostic) : LowerError := {
  message := err.render
}

/-- Look up a struct declaration by name. -/
def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? fun decl => decl.name == name

/-- Look up a struct field by name within a struct declaration. -/
def findStructField? (decl : StructDecl) (fieldName : String) : Option StructField :=
  decl.fields.find? fun field => field.id == fieldName

open ProofForge.Backend.Psy.Plan (StorageLayout StorageShape StorageStatePlan)

/-- Build context: carries the portable IR module plus the pre-resolved
storage layout from the semantic plan. Builder functions look up storage
shapes from `layout` instead of re-resolving `findState?` inline. Struct
field lookups still use `module` since structs are not part of the storage
layout plan. -/
structure BuildContext where
  module : Module
  layout : StorageLayout

/-- Look up a storage state plan from the context's layout. -/
def lookupState? (ctx : BuildContext) (stateId : String) : Option StorageStatePlan :=
  ProofForge.Backend.Psy.Plan.findState? ctx.layout stateId

/-- Require that a state is scalar storage. -/
def requireScalarStateCtx (ctx : BuildContext) (stateId : String) : Except LowerError Unit :=
  match lookupState? ctx stateId with
  | some { shape := .scalar _, .. } => .ok ()
  | some { shape := .map _ _ _, .. } => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | some { shape := .array _ _ _, .. } => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | some { shape := .structRef _, .. } => .ok ()
  | none => .error { message := s!"unknown scalar state `{stateId}`" }

/-- Require that a state is map storage. -/
def requireMapStateCtx (ctx : BuildContext) (stateId : String) : Except LowerError Unit :=
  match lookupState? ctx stateId with
  | some { shape := .map _ _ _, .. } => .ok ()
  | some { shape := .scalar _, .. } => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | some { shape := .array _ _ _, .. } => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | some { shape := .structRef _, .. } => .error { message := s!"state `{stateId}` is struct ref storage, not a map" }
  | none => .error { message := s!"unknown map state `{stateId}`" }

/-- Require that a state is array storage. -/
def requireArrayStateCtx (ctx : BuildContext) (stateId : String) : Except LowerError Unit :=
  match lookupState? ctx stateId with
  | some { shape := .array _ _ _, .. } => .ok ()
  | some { shape := .scalar _, .. } => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
  | some { shape := .map _ _ _, .. } => .error { message := s!"state `{stateId}` is map storage, not an array" }
  | some { shape := .structRef _, .. } => .error { message := s!"state `{stateId}` is struct ref storage, not an array" }
  | none => .error { message := s!"unknown array state `{stateId}`" }

/-- Require that a state is struct scalar storage referencing a struct with
the given field. -/
def requireStructScalarStateCtx (ctx : BuildContext) (stateId fieldName : String) : Except LowerError Unit :=
  match lookupState? ctx stateId with
  | some { shape := .structRef type, .. } =>
      match type with
      | .structType typeName =>
          match findStruct? ctx.module typeName with
          | some decl =>
              if decl.fields.any (fun field => field.id == fieldName) then .ok ()
              else .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"state `{stateId}` references unknown struct `{typeName}`" }
      | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
  | some { shape := .scalar _, .. } => .error { message := s!"state `{stateId}` has scalar type, not struct storage" }
  | some { shape := .map _ _ _, .. } => .error { message := s!"state `{stateId}` is map storage, not struct scalar storage" }
  | some { shape := .array _ _ _, .. } => .error { message := s!"state `{stateId}` is array storage, not struct scalar storage" }
  | none => .error { message := s!"unknown struct state `{stateId}`" }

/-- Require that a state is struct array storage referencing a deriveStorage
struct with the given field. -/
def requireStructArrayStateCtx (ctx : BuildContext) (stateId fieldName : String) : Except LowerError Unit :=
  match lookupState? ctx stateId with
  | some { shape := .array elementType _ _, .. } =>
      match elementType with
      | .structType typeName =>
          match findStruct? ctx.module typeName with
          | some decl =>
              if !decl.deriveStorage then
                .error { message := s!"array state `{stateId}` uses struct `{typeName}`, but the struct is not marked deriveStorage" }
              else if decl.fields.any (fun field => field.id == fieldName) then .ok ()
              else .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"array state `{stateId}` references unknown struct `{typeName}`" }
      | other => .error { message := s!"array state `{stateId}` has element type `{other.name}`, not struct array storage" }
  | some { shape := .scalar _, .. } => .error { message := s!"state `{stateId}` is scalar storage, not struct array storage" }
  | some { shape := .map _ _ _, .. } => .error { message := s!"state `{stateId}` is map storage, not struct array storage" }
  | some { shape := .structRef _, .. } => .error { message := s!"state `{stateId}` is struct ref storage, not struct array storage" }
  | none => .error { message := s!"unknown struct array state `{stateId}`" }

/-- Check whether a storage state is a felt-backed U32 array. -/
def isFeltBackedU32ArrayCtx (ctx : BuildContext) (stateId : String) : Bool :=
  match lookupState? ctx stateId with
  | some { shape := .array _ _ true, .. } => true
  | _ => false

/-- Decide whether a resolved storage path should use the Felt-backed U32 rewrite.
    True only when the root state is a felt-backed U32 array and the path is a
    valid index/field path into that array. -/
def storagePathFeltBacked (ctx : BuildContext) (stateId : String) (pathType : ValueType) : Bool :=
  isFeltBackedU32ArrayCtx ctx stateId && pathType == .u32

/-- Recursively resolve storage path segments against the module struct graph. -/
partial def resolvePathSegments (module : Module) : ValueType → List StoragePathSegment → Except LowerError ValueType
  | type, [] => .ok type
  | type, .field fieldName :: rest => do
      match type with
      | .structType typeName =>
          match findStruct? module typeName with
          | some decl =>
              match findStructField? decl fieldName with
              | some field => resolvePathSegments module field.type rest
              | none => .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          | none => .error { message := s!"unknown struct `{typeName}` in storage path" }
      | other => .error { message := s!"storage path field `{fieldName}` requires struct, got `{other.name}`" }
  | type, .index _ :: rest => do
      match type with
      | .fixedArray element _ => resolvePathSegments module element rest
      | other => .error { message := s!"storage path index requires fixed array, got `{other.name}`" }
  | type, .mapKey _ :: rest => do
      match type with
      | .structType _ => resolvePathSegments module type rest
      | other => .error { message := s!"storage path map key requires struct/map value, got `{other.name}`" }

/-- Resolve the type of a storage path from the layout + module struct graph. -/
partial def resolveStoragePathTypeCtx (ctx : BuildContext) (stateId : String) (path : Array StoragePathSegment) : Except LowerError ValueType := do
  if path.isEmpty then .error { message := s!"storage path for state `{stateId}` must contain at least one segment" }
  match lookupState? ctx stateId with
  | some { shape := .scalar type, .. } =>
      if path.toList matches .mapKey _ :: _ then
        .error { message := s!"storage path state `{stateId}` is scalar storage, not map storage" }
      else
        resolvePathSegments ctx.module type path.toList
  | some { shape := .structRef type, .. } =>
      if path.toList matches .mapKey _ :: _ then
        .error { message := s!"storage path state `{stateId}` is struct ref storage, not map storage" }
      else
        resolvePathSegments ctx.module type path.toList
  | some { shape := .map _ valueType _, .. } =>
      match path.toList with
      | .mapKey _ :: rest => resolvePathSegments ctx.module valueType rest
      | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
  | some { shape := .array elementType length _, .. } =>
      if path.toList matches .mapKey _ :: _ then
        .error { message := s!"storage path state `{stateId}` is array storage, not map storage" }
      else
        resolvePathSegments ctx.module (.fixedArray elementType length) path.toList
  | none => .error { message := s!"unknown storage path state `{stateId}`" }

/-- The Psy surface type name for the native field element (`Felt`). -/
def psyFeltTypeName : String := "Felt"

def valueTypeName : ValueType → Except LowerError String
  | .unit => .ok "()"
  | .bool => .ok "bool"
  | .u32 => .ok "u32"
  | .u64 => .ok psyFeltTypeName
  | .hash => .ok "Hash"
  | .u8 => .ok "U8"
  | .address => .ok "Address"
  | .u128 => .error { message := "Psy IR v0 does not support U128" }
  | .bytes => .error { message := "Psy IR v0 does not support Bytes" }
  | .string => .error { message := "Psy IR v0 does not support String" }
  | .fixedArray element length => do
      if length == 0 then
        .error { message := "Psy IR v0 fixed arrays must have non-zero length" }
      .ok s!"[{← valueTypeName element}; {length}]"
  | .structType name => .ok name
  | .array _ => .error { message := "Psy IR v0 does not support dynamic arrays" }

def asciiLetters : String :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def isPsyIdentifierStart (ch : Char) : Bool :=
  ch == '_' || asciiLetters.contains ch

def isPsyIdentifierContinue (ch : Char) : Bool :=
  isPsyIdentifierStart ch || ch.isDigit

def psyReservedIdentifiers : Array String := #[
  "as",
  "bool",
  "else",
  "false",
  "fn",
  "for",
  "if",
  "impl",
  "in",
  "let",
  "mut",
  "new",
  "pub",
  "return",
  "struct",
  "true",
  "Felt",
  "Hash",
  "Map",
  "ContractMetadata"
]

def validatePsyIdentifier (context name : String) : Except LowerError Unit :=
  match name.toList with
  | [] =>
      .error { message := s!"{context} must be a non-empty Psy identifier" }
  | first :: rest => do
      if !isPsyIdentifierStart first || !rest.all isPsyIdentifierContinue then
        .error { message := s!"{context} `{name}` is not a valid Psy identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`" }
      if psyReservedIdentifiers.any (fun reserved => reserved == name) then
        .error { message := s!"{context} `{name}` is reserved in Psy" }

def validateDistinctNames (context : String) (names : Array String) : Except LowerError Unit := do
  let _ ← names.foldlM (init := #[]) fun seen name =>
    if seen.any (fun existing => existing == name) then
      .error { message := s!"duplicate {context} `{name}`" }
    else
      .ok (seen.push name)
  pure ()

def findState? (module : Module) (stateId : String) : Option StateDecl :=
  module.state.find? fun state => state.id == stateId

def storagePathStartType (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError (ValueType × List StoragePathSegment) :=
  match findState? module stateId with
  | some state =>
      match state.kind with
      | .scalar =>
          match path.toList with
          | .mapKey _ :: _ =>
              .error { message := s!"storage path state `{stateId}` is scalar storage, not map storage" }
          | segments =>
              .ok (state.type, segments)
      | .array length =>
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          else
            match path.toList with
            | .mapKey _ :: _ =>
                .error { message := s!"storage path state `{stateId}` is array storage, not map storage" }
            | segments =>
                .ok (.fixedArray state.type length, segments)
      | .map _ capacity =>
          if capacity == 0 then
            .error { message := s!"map state `{stateId}` must have non-zero capacity" }
          else
            match path.toList with
            | .mapKey _ :: rest => .ok (state.type, rest)
            | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .dynamicArray =>
          .error { message := s!"storage path state `{stateId}` is dynamic array storage; Psy IR v0 does not lower portable dynamic array storage" }
  | none => .error { message := s!"unknown storage path state `{stateId}`" }

partial def resolveStoragePathSegments (module : Module) : ValueType → List StoragePathSegment → Except LowerError ValueType
  | current, [] => .ok current
  | .structType typeName, .field fieldName :: rest => do
      let some decl := findStruct? module typeName
        | .error { message := s!"storage path references unknown struct `{typeName}`" }
      if !decl.deriveStorage then
        .error { message := s!"storage path traverses struct `{typeName}`, but the struct is not marked deriveStorage" }
      let some field := findStructField? decl fieldName
        | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
      match field.type with
      | .structType _ =>
          if !field.isRef then
            .error { message := s!"storage path field `{fieldName}` in struct `{typeName}` must be marked ref to access nested storage" }
          else
            resolveStoragePathSegments module field.type rest
      | _ =>
          resolveStoragePathSegments module field.type rest
  | other, .field fieldName :: _ =>
      .error { message := s!"storage path field `{fieldName}` cannot be selected from `{other.name}`" }
  | .fixedArray element length, .index _ :: rest => do
      if length == 0 then
        .error { message := "storage path fixed array segment must have non-zero length" }
      else
        resolveStoragePathSegments module element rest
  | other, .index _ :: _ =>
      .error { message := s!"storage path index cannot be selected from `{other.name}`" }
  | other, .mapKey _ :: _ =>
      .error { message := s!"storage path map key cannot be selected from `{other.name}`" }

def resolveStoragePathType (module : Module) (stateId : String) (path : Array StoragePathSegment) : Except LowerError ValueType := do
  if path.isEmpty then
    .error { message := s!"storage path for state `{stateId}` must contain at least one segment" }
  let (start, segments) ← storagePathStartType module stateId path
  resolveStoragePathSegments module start segments

partial def validateValueType (module : Module) (type : ValueType) : Except LowerError Unit := do
  match type with
  | .unit => .error { message := "Psy IR v0 does not support Unit as a stored or structured value type" }
  | .bool | .u8 | .u32 | .u64 | .hash | .address => pure ()
  | .bytes | .string | .u128 =>
      .error { message := "Psy IR v0 does not support Bytes, String, or U128 as stored or structured value types" }
  | .array _ =>
      .error { message := "Psy IR v0 does not support dynamic arrays as stored or structured value types" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := "Psy IR v0 fixed arrays must have non-zero length" }
      validateValueType module element
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"unknown struct type `{name}`" }

partial def validateAbiValueType (module : Module) (type : ValueType) (context : String) (allowUnit : Bool) : Except LowerError Unit := do
  match type with
  | .unit =>
      if allowUnit then
        pure ()
      else
        .error { message := s!"{context} uses Unit; Psy IR v0 entrypoint parameters must use Felt, U32, Bool, Hash, Address, fixed arrays, or declared structs" }
  | .bool | .u8 | .u32 | .u64 | .hash | .address => pure ()
  | .bytes | .string | .u128 =>
      .error { message := s!"{context} uses Bytes, String, or U128; Psy IR v0 entrypoint parameters must use Felt, U8, U32, Bool, Hash, Address, fixed arrays, or declared structs" }
  | .array _ =>
      .error { message := s!"{context} uses dynamic array; Psy IR v0 entrypoint parameters must use Felt, U8, U32, Bool, Hash, Address, fixed arrays, or declared structs" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := s!"{context} uses a zero-length fixed array; Psy IR v0 fixed arrays must have non-zero length" }
      validateAbiValueType module element context false
  | .structType name =>
      match findStruct? module name with
      | some _ => pure ()
      | none => .error { message := s!"{context} references unknown struct type `{name}`" }

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool := false
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  match findLocal? env name with
  | some _ => .error { message := s!"local `{name}` is already defined" }
  | none => .ok <| env.push { name, type, isMutable }

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

def ensureIndexType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | other => .error { message := s!"{context} expected `U32` or `U64`, got `{other.name}`" }

def ensureNumericType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | other => .error { message := s!"{context} expected numeric `U32` or `U64`, got `{other.name}`" }

def ensureSameNumericType (operator : String) (lhs rhs : ValueType) : Except LowerError ValueType := do
  ensureNumericType s!"{operator} left operand" lhs
  ensureType s!"{operator} right operand" lhs rhs
  .ok lhs

def assignOpDiagnosticName : AssignOp → String
  | .add => "addition"
  | .sub => "subtraction"
  | .mul => "multiplication"
  | .div => "division"
  | .mod => "modulo"
  | .bitAnd => "bitwise and"
  | .bitOr => "bitwise or"
  | .bitXor => "bitwise xor"
  | .shiftLeft => "shift-left"
  | .shiftRight => "shift-right"

def assignOpSymbol : AssignOp → String
  | .add => "+="
  | .sub => "-="
  | .mul => "*="
  | .div => "/="
  | .mod => "%="
  | .bitAnd => "&="
  | .bitOr => "|="
  | .bitXor => "^="
  | .shiftLeft => "<<="
  | .shiftRight => ">>="

def assignOpBinarySymbol : AssignOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .bitAnd => "&"
  | .bitOr => "|"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"

def ensureAssignOpTypes (op : AssignOp) (targetType valueType : ValueType) : Except LowerError Unit := do
  discard <| ensureSameNumericType s!"compound assignment {assignOpDiagnosticName op}" targetType valueType

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .unit =>
      .error { message := s!"{context} does not support Unit equality" }
  | .bool | .u8 | .u32 | .u64 | .hash | .address | .fixedArray _ _ | .structType _ | .bytes | .string | .u128 | .array _ =>
      .ok ()

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u32, .u64 => .ok ()
  | .u64, .u32 => .ok ()
  | .u32, .bool => .ok ()
  | .bool, .u64 => .ok ()
  | .bool, .u32 => .ok ()
  | .u64, .bool => .ok ()
  | source, target =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by Psy IR v0" }

def ensureHashValuePart (partName : String) (type : ValueType) : Except LowerError Unit :=
  ensureType s!"hash value part {partName}" .u64 type

def structFieldType (module : Module) (typeName fieldName : String) : Except LowerError ValueType := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct type `{typeName}`" }
  let some field := findStructField? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  .ok field.type

def stateDeclOf (module : Module) (stateId : String) (kind : String) : Except LowerError StateDecl :=
  match findState? module stateId with
  | some state => .ok state
  | none => .error { message := s!"unknown {kind} state `{stateId}`" }

def scalarStateType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "scalar"
  match state.kind with
  | .scalar => .ok state.type
  | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is a dynamic array, not scalar storage" }

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def arrayStateElementType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "array"
  match state.kind with
  | .array _ => .ok state.type
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
  | .map _ _ => .error { message := s!"state `{stateId}` is map storage, not an array" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not an array" }

end ProofForge.Backend.Psy.IR
