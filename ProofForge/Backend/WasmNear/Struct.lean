/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Struct

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Types

/-! Struct layout and storage-buffer helpers for EmitWat lowering. -/

def findStruct? (structs : Array ProofForge.IR.StructDecl) (name : String) : Option ProofForge.IR.StructDecl :=
  structs.find? (fun s => s.name == name)

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

def zeroStructBufInsns (s : ProofForge.IR.StructDecl) : Array Insn :=
  (s.fields.foldl (fun st f =>
      (st.1 + scalarWidth f.type,
       st.2 ++ #[.i32Const st.1, .i32Const STRUCT_BUF, .plain "i32.add",
                 .const (wasmTypeOf f.type) "0", .store (storeOpFor f.type) 0]))
    (0, (#[] : Array Insn))).2

def readScalarStructBufInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) : Array Insn :=
  #[.i64Const s.keyLen, .i64Const s.keyPtr, .i64Const 0, .call "storage_read",
    .i64Const 0, .plain "i64.ne",
    .if_ { insns := #[.i64Const 0, .i64Const STRUCT_BUF, .call "read_register"] }
         { insns := zeroStructBufInsns sd }]

def scalarStructFieldReadInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) (offset : Nat)
    (fieldType : ValueType) : Array Insn × ValueType :=
  (readScalarStructBufInsns s sd ++
    #[.i32Const offset, .i32Const STRUCT_BUF, .plain "i32.add", .load (loadOpFor fieldType) 0],
    fieldType)

def scalarStructFieldWriteInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) (offset : Nat)
    (fieldType : ValueType) (valueInsns : Array Insn) : Array Insn :=
  readScalarStructBufInsns s sd ++
    #[.i32Const offset, .i32Const STRUCT_BUF, .plain "i32.add"] ++ valueInsns ++
    #[.store (storeOpFor fieldType) 0,
      .i64Const s.keyLen, .i64Const s.keyPtr, .i64Const (structTotalSize sd),
      .i64Const STRUCT_BUF, .i64Const 0, .call "storage_write", .drop]

def readArrayStructBufInsns (m : MapInfo) (s : ProofForge.IR.StructDecl) : Array Insn :=
  #[.i64Const (m.prefixLen + 8), .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read",
    .i64Const 0, .plain "i64.ne",
    .if_ { insns := #[.i64Const 0, .i64Const STRUCT_BUF, .call "read_register"] }
         { insns := zeroStructBufInsns s }]

def arrayStructFieldReadInsns (m : MapInfo) (sd : ProofForge.IR.StructDecl)
    (indexInsns buildKeyCall : Array Insn) (offset : Nat) (fieldType : ValueType) :
    Array Insn × ValueType :=
  (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ indexInsns ++ buildKeyCall ++
    readArrayStructBufInsns m sd ++
    #[.i32Const offset, .i32Const STRUCT_BUF, .plain "i32.add", .load (loadOpFor fieldType) 0],
    fieldType)

def arrayStructFieldWriteInsns (m : MapInfo) (sd : ProofForge.IR.StructDecl)
    (readKeyInsns writeKeyInsns buildKeyCall valueInsns : Array Insn) (offset : Nat)
    (fieldType : ValueType) : Array Insn :=
  #[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ readKeyInsns ++ buildKeyCall ++
    readArrayStructBufInsns m sd ++
    #[.i32Const offset, .i32Const STRUCT_BUF, .plain "i32.add"] ++ valueInsns ++
    #[.store (storeOpFor fieldType) 0] ++
    #[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ writeKeyInsns ++ buildKeyCall ++
    #[.i64Const (m.prefixLen + 8), .i64Const MAPKEY_BUF,
      .i64Const (structTotalSize sd), .i64Const STRUCT_BUF, .i64Const 0,
      .call "storage_write", .drop]

end ProofForge.Backend.WasmNear.Struct
