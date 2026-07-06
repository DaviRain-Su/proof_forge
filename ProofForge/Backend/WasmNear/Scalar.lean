/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.Struct
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Scalar

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.Struct
open ProofForge.Backend.WasmNear.Types

/-! Scalar storage, return, and arithmetic helper functions for EmitWat. -/

def storageScalarStateInfo (scalars : Array StateInfo) (id : String) :
    Except EmitError StateInfo :=
  match findScalarState? scalars id with
  | some stateInfo => .ok stateInfo
  | none => err s!"EmitWat: unknown scalar state `{id}`"

def storageScalarWriteInsns (structs : Array ProofForge.IR.StructDecl)
    (stateInfo : StateInfo) (id : String) (valueInsns : Array Insn)
    (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != stateInfo.type then
    err s!"EmitWat: scalar write `{id}` expected `{stateInfo.type.name}`, got `{valueType.name}`"
  else match stateInfo.type with
    | .structType typeName =>
      match findStruct? structs typeName with
      | none => err s!"EmitWat: unknown struct `{typeName}`"
      | some structDecl =>
        .ok (#[.i64Const stateInfo.keyLen, .i64Const stateInfo.keyPtr,
                 .i64Const (structTotalSize structDecl)]
              ++ valueInsns ++ #[.plain "i64.extend_i32_u", .i64Const 0,
                 .call "storage_write", .drop])
    | _ =>
      .ok (#[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen] ++ valueInsns ++
        #[.call (writeName stateInfo.type)])

def storageScalarAssignOpTargetType (stateInfo : StateInfo) (id : String) :
    Except EmitError ValueType :=
  if stateInfo.type == .hash then
    err s!"EmitWat: storageScalarAssignOp not supported on Hash scalars (`{id}`)"
  else .ok stateInfo.type

def storageScalarAssignOpInsns (stateInfo : StateInfo) (id : String) (op : AssignOp)
    (valueInsns : Array Insn) (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != stateInfo.type then
    err s!"EmitWat: scalar assignOp `{id}` expected `{stateInfo.type.name}`, got `{valueType.name}`"
  else
    .ok (#[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen,
             .i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen,
             .call (readName stateInfo.type)] ++ valueInsns
          ++ #[.plain (widthOf stateInfo.type ++ "." ++ assignOpName op),
             .call (writeName stateInfo.type)])

def readFunc (vt : ValueType) : Func :=
  { name := readName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[wasmTypeOf vt],
    locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
    body := { insns := #[
      .const (wasmTypeOf vt) "0", .localSet "r",
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 0, .call "storage_read", .localSet "found",
      .localGet "found", .i64Const 0, .plain "i64.ne",
      .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                        .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
      .localGet "r" ] } }

def writeFunc (vt : ValueType) : Func :=
  { name := writeName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0, .call "storage_write", .drop ] } }

def returnU64Func : Func :=
  { name := returnU64Name, params := #[{ name := "v", type := .i64 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i64.store" 0,
      .i64Const 8, .i64Const RET_BUF, .call "value_return" ] } }

def returnU32Func : Func :=
  { name := returnU32Name, params := #[{ name := "v", type := .i32 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i32.store" 0,
      .i64Const 4, .i64Const RET_BUF, .call "value_return" ] } }

def returnBoolFunc : Func :=
  { name := returnBoolName, params := #[{ name := "v", type := .i32 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i32.store8" 0,
      .i64Const 1, .i64Const RET_BUF, .call "value_return" ] } }

def powName (vt : ValueType) : String := "__pf_pow_" ++ typeSuffix vt

/-- `__pf_pow_<t>(base, exp)`: integer exponentiation by squaring (log2(exp) iterations). -/
def powFunc (vt : ValueType) : Func :=
  let w := widthOf vt
  { name := powName vt,
    params := #[{ name := "base", type := wasmTypeOf vt }, { name := "exp", type := wasmTypeOf vt }],
    results := #[wasmTypeOf vt],
    locals := #[{ name := "r", type := wasmTypeOf vt }],
    body := { insns := #[
      .const (wasmTypeOf vt) "1", .localSet "r",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "exp", .const (wasmTypeOf vt) "0", .plain (w ++ ".eq"), .brIf 1,
        .localGet "exp", .const (wasmTypeOf vt) "1", .plain (w ++ ".and"), .const (wasmTypeOf vt) "0", .plain (w ++ ".ne"),
        .if_ { insns := #[ .localGet "r", .localGet "base", .plain (w ++ ".mul"), .localSet "r" ] } { insns := #[] },
        .localGet "base", .localGet "base", .plain (w ++ ".mul"), .localSet "base",
        .localGet "exp", .const (wasmTypeOf vt) "1", .plain (w ++ ".shr_u"), .localSet "exp",
        .br 0 ] } ] },
      .localGet "r" ] } }

def scalarStorageHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  let scalarTypes : Array ValueType := #[.u32, .u64, .bool]
  let funcs := scalarTypes.foldl (init := #[]) fun acc type =>
    let acc :=
      if plan.scalarReadTypes.contains type then
        acc.push (readFunc type)
      else
        acc
    if plan.scalarWriteTypes.contains type then
      acc.push (writeFunc type)
    else
      acc
  funcs

def returnHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.returnTypes.contains .u64 then #[returnU64Func] else #[]) ++
    (if plan.returnTypes.contains .u32 then #[returnU32Func] else #[]) ++
    (if plan.returnTypes.contains .bool then #[returnBoolFunc] else #[])

def powHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesPowU32 then #[powFunc .u32] else #[]) ++
    (if plan.usesPowU64 then #[powFunc .u64] else #[])

end ProofForge.Backend.WasmNear.Scalar
