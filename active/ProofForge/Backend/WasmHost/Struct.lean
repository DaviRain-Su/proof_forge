/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Types

namespace ProofForge.Backend.WasmHost.Struct

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Types

/-! Struct layout and storage-buffer helpers for EmitWat lowering. -/

def findStruct? (structs : Array ProofForge.IR.StructDecl) (name : String) : Option ProofForge.IR.StructDecl :=
  structs.find? (fun s => s.name == name)

structure ScalarStructStateInfo where
  state : StateInfo
  typeName : String
  structDecl : ProofForge.IR.StructDecl

structure ArrayStructInfo where
  mapInfo : MapInfo
  typeName : String
  structDecl : ProofForge.IR.StructDecl

def scalarStructStateInfo (scalars : Array StateInfo) (structs : Array ProofForge.IR.StructDecl)
    (id operationName : String) : Except EmitError ScalarStructStateInfo :=
  match findScalarState? scalars id with
  | none => err s!"EmitWat: unknown scalar state `{id}`"
  | some stateInfo =>
    match stateInfo.type with
    | .structType typeName =>
      match findStruct? structs typeName with
      | none => err s!"EmitWat: unknown struct `{typeName}`"
      | some structDecl => .ok { state := stateInfo, typeName := typeName, structDecl := structDecl }
    | _ => err s!"EmitWat: {operationName} expects a struct state, got `{stateInfo.type.name}`"

def arrayStructMapInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findArrayState? maps id with
  | none => err s!"EmitWat: unknown array state `{id}`"
  | some mapInfo =>
    if mapInfo.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
    else .ok mapInfo

def arrayStructInfo (structs : Array ProofForge.IR.StructDecl) (mapInfo : MapInfo)
    (operationName : String) : Except EmitError ArrayStructInfo :=
  match mapInfo.valueType with
  | .structType typeName =>
    match findStruct? structs typeName with
    | none => err s!"EmitWat: unknown struct `{typeName}`"
    | some structDecl => .ok { mapInfo := mapInfo, typeName := typeName, structDecl := structDecl }
  | _ => err s!"EmitWat: {operationName} expects a struct-valued array, got `{mapInfo.valueType.name}`"

/-- Field offset = prefix sum of `scalarWidth` of preceding fields; total size = sum all. -/
def structTotalSize (s : ProofForge.IR.StructDecl) : Nat :=
  s.fields.foldl (fun acc f => acc + scalarWidth f.type) 0

def structFieldOffset? (s : ProofForge.IR.StructDecl) (fieldName : String) : Option Nat :=
  let rec go (i acc : Nat) : Option Nat :=
    if h : i < s.fields.size then
      let f := s.fields[i]
      if f.id == fieldName then some acc else go (i+1) (acc + scalarWidth f.type)
    else none
  go 0 0

def structFieldType? (s : ProofForge.IR.StructDecl) (fieldName : String) : Option ValueType :=
  (s.fields.find? (fun f => f.id == fieldName)).map (fun f => f.type)

def structLitName (typeName : String) : String := "__pf_struct_lit_" ++ typeName

def isStructStorageFieldType : ValueType → Bool
  | .u32 | .u64 | .bool => true
  | _ => false

def isIndexedStorageValueType : ValueType → Bool
  | .u32 | .u64 | .bool | .hash => true
  | _ => false

def structStorageFieldsSupported (s : ProofForge.IR.StructDecl) : Bool :=
  s.fields.all (fun f => isStructStorageFieldType f.type)

def structStorageFieldInfo (sd : ProofForge.IR.StructDecl) (typeName fieldName label : String) :
    Except EmitError (Nat × ValueType) :=
  if !structStorageFieldsSupported sd then
    err s!"EmitWat: {label} struct `{typeName}` storage fields must be U32/U64/Bool"
  else match structFieldOffset? sd fieldName, structFieldType? sd fieldName with
    | some offset, some fieldType =>
      if !isStructStorageFieldType fieldType then
        err s!"EmitWat: {label} struct field `{typeName}.{fieldName}` has unsupported type `{fieldType.name}`"
      else .ok (offset, fieldType)
    | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"

def structBufFieldPtrInsns (offset : Nat) : Array Insn :=
  #[.i32Const offset, .i32Const STRUCT_BUF, .plain "i32.add"]

def mapInfoPrefixInsns (m : MapInfo) : Array Insn :=
  #[.i32Const m.prefixPtr, .i32Const m.prefixLen]

def zeroStructBufInsns (s : ProofForge.IR.StructDecl) : Array Insn :=
  (s.fields.foldl (fun st f =>
      (st.1 + scalarWidth f.type,
       st.2 ++ structBufFieldPtrInsns st.1 ++
         #[.const (wasmTypeOf f.type) "0", .store (storeOpFor f.type) 0]))
    (0, (#[] : Array Insn))).2

def readStructBufOrZeroInsns (keyLen keyPtr : Nat) (sd : ProofForge.IR.StructDecl) : Array Insn :=
  #[.i64Const keyLen, .i64Const keyPtr, .i64Const 0, .call "storage_read",
    .i64Const 0, .plain "i64.ne",
    .if_ { insns := #[.i64Const 0, .i64Const STRUCT_BUF, .call "read_register"] }
         { insns := zeroStructBufInsns sd }]

def readScalarStructBufInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) : Array Insn :=
  readStructBufOrZeroInsns s.keyLen s.keyPtr sd

def scalarStructFieldReadInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) (offset : Nat)
    (fieldType : ValueType) : Array Insn × ValueType :=
  (readScalarStructBufInsns s sd ++
    structBufFieldPtrInsns offset ++ #[.load (loadOpFor fieldType) 0],
    fieldType)

def scalarStructFieldWriteInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) (offset : Nat)
    (fieldType : ValueType) (valueInsns : Array Insn) : Array Insn :=
  readScalarStructBufInsns s sd ++
    structBufFieldPtrInsns offset ++ valueInsns ++
    #[.store (storeOpFor fieldType) 0,
      .i64Const s.keyLen, .i64Const s.keyPtr, .i64Const (structTotalSize sd),
      .i64Const STRUCT_BUF, .i64Const 0, .call "storage_write", .drop]

def readArrayStructBufInsns (m : MapInfo) (s : ProofForge.IR.StructDecl) : Array Insn :=
  readStructBufOrZeroInsns (m.prefixLen + 8) MAPKEY_BUF s

def arrayStructFieldReadInsns (m : MapInfo) (sd : ProofForge.IR.StructDecl)
    (indexInsns buildKeyCall : Array Insn) (offset : Nat) (fieldType : ValueType) :
    Array Insn × ValueType :=
  (mapInfoPrefixInsns m ++ indexInsns ++ buildKeyCall ++
    readArrayStructBufInsns m sd ++
    structBufFieldPtrInsns offset ++ #[.load (loadOpFor fieldType) 0],
    fieldType)

def arrayStructFieldWriteInsns (m : MapInfo) (sd : ProofForge.IR.StructDecl)
    (readKeyInsns writeKeyInsns buildKeyCall valueInsns : Array Insn) (offset : Nat)
    (fieldType : ValueType) : Array Insn :=
  mapInfoPrefixInsns m ++ readKeyInsns ++ buildKeyCall ++
    readArrayStructBufInsns m sd ++
    structBufFieldPtrInsns offset ++ valueInsns ++
    #[.store (storeOpFor fieldType) 0] ++
    mapInfoPrefixInsns m ++ writeKeyInsns ++ buildKeyCall ++
    #[.i64Const (m.prefixLen + 8), .i64Const MAPKEY_BUF,
      .i64Const (structTotalSize sd), .i64Const STRUCT_BUF, .i64Const 0,
      .call "storage_write", .drop]

end ProofForge.Backend.WasmHost.Struct
