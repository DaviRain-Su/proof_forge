/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.LoweringEnv
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Scalar

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.LoweringEnv
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

/-! Scalar storage, return, and arithmetic helper functions for EmitWat. -/

def storageScalarStateInfo (scalars : Array StateInfo) (id : String) :
    Except EmitError StateInfo :=
  match findScalarState? scalars id with
  | some stateInfo => .ok stateInfo
  | none => err s!"EmitWat: unknown scalar state `{id}`"

/-- Packed-scalar helpers (NEAR): one storage key `__pf_s`, entry-local load/flush. -/
def packLoadedGlobal : String := "pack_loaded"
def packDirtyGlobal : String := "pack_dirty"
def packEnsureName : String := "__pf_pack_ensure"
def packFlushName : String := "__pf_pack_flush"
def packBeginName : String := "__pf_pack_begin"
/-- Zero pack buffer + mark loaded without `storage_read` (write-only entrypoints). -/
def packBeginFreshName : String := "__pf_pack_begin_fresh"
def packWriteName (vt : ValueType) : String := "__pf_pack_write_" ++ typeSuffix vt
def packReadName (vt : ValueType) : String := "__pf_pack_read_" ++ typeSuffix vt

def packGlobals : Array Global :=
  #[{ name := packLoadedGlobal, type := .i32, init := "0", isMutable := true },
    { name := packDirtyGlobal, type := .i32, init := "0", isMutable := true }]

def packBeginFunc : Func :=
  { name := packBeginName, body := { insns := #[
      .i32Const 0, .globalSet packLoadedGlobal,
      .i32Const 0, .globalSet packDirtyGlobal ] } }

/-- Zero `packSize` bytes at PACK_BUF. Prefer unrolled `i64.store` when size is
8-aligned (ValueVault pack = 48 → six stores, no loop). -/
def packZeroInsns (packSize : Nat) : Array Insn :=
  if packSize % 8 == 0 then
    (Array.range (packSize / 8)).foldl (init := #[]) fun acc i =>
      acc ++ #[.i32Const (PACK_BUF + i * 8), .i64Const 0, .store "i64.store" 0]
  else
    #[.i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .i32Const packSize, .plain "i32.ge_u", .brIf 1,
        .i32Const PACK_BUF, .localGet "i", .plain "i32.add",
        .i32Const 0, .store "i32.store8" 0,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i",
        .br 0 ] } ] }]

def packBeginFreshFunc (packSize : Nat) : Func :=
  { name := packBeginFreshName,
    locals := if packSize % 8 == 0 then #[] else #[{ name := "i", type := .i32 }],
    body := { insns :=
      packZeroInsns packSize ++ #[
        .i32Const 1, .globalSet packLoadedGlobal,
        .i32Const 0, .globalSet packDirtyGlobal ] } }

def packEnsureFunc (packSize : Nat) : Func :=
  { name := packEnsureName,
    locals := if packSize % 8 == 0 then #[] else #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .globalGet packLoadedGlobal, .plain "i32.eqz",
      .if_ { insns := #[
          .i64Const PACK_KEY_LEN, .i64Const PACK_KEY_PTR, .i64Const 0, .call "storage_read",
          .i64Const 0, .plain "i64.ne",
          .if_ { insns := #[.i64Const 0, .i64Const PACK_BUF, .call "read_register"] }
             { insns := packZeroInsns packSize },
          .i32Const 1, .globalSet packLoadedGlobal
        ] } { insns := #[] }
    ] } }

def packFlushFunc (packSize : Nat) : Func :=
  { name := packFlushName,
    body := { insns := #[
      .globalGet packDirtyGlobal,
      .if_ { insns := #[
          .i64Const PACK_KEY_LEN, .i64Const PACK_KEY_PTR,
          .i64Const packSize, .i64Const PACK_BUF, .i64Const 0,
          .call "storage_write", .drop,
          .i32Const 0, .globalSet packDirtyGlobal
        ] } { insns := #[] }
    ] } }

def packWriteFunc (vt : ValueType) : Func :=
  { name := packWriteName vt,
    params := #[{ name := "off", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    body := { insns := #[
      .call packEnsureName,
      .i32Const PACK_BUF, .localGet "off", .plain "i32.add",
      .localGet "v", .store (storeOpFor vt) 0,
      .i32Const 1, .globalSet packDirtyGlobal
    ] } }

def packReadFunc (vt : ValueType) : Func :=
  { name := packReadName vt,
    params := #[{ name := "off", type := .i32 }],
    results := #[wasmTypeOf vt],
    body := { insns := #[
      .call packEnsureName,
      .i32Const PACK_BUF, .localGet "off", .plain "i32.add",
      .load (loadOpFor vt) 0
    ] } }

def packBeginInsns : Array Insn := #[.call packBeginName]
def packBeginFreshInsns : Array Insn := #[.call packBeginFreshName]
def packFlushInsns : Array Insn := #[.call packFlushName]

/-- True when `id` is a packed scalar in the current layout. -/
def isPackedScalarId (scalars : Array StateInfo) (id : String) : Bool :=
  match findScalarState? scalars id with
  | some s => s.packed
  | none => false

-- Conservative: any read (or RMW) of packed scalar storage forbids begin_fresh.
mutual
  partial def exprReadsPackedScalar (scalars : Array StateInfo) : Expr → Bool
    | .effect eff => effectReadsPackedScalar scalars eff
    | .literal _ | .local _ | .nativeValue | .nearPromiseResultsCount => false
    | .arrayLit _ vs => vs.any (exprReadsPackedScalar scalars)
    | .arrayGet a i | .memoryArrayGet a i | .hashTwoToOne a i
    | .add a i _ | .sub a i _ | .mul a i _ | .div a i | .mod a i | .pow a i
    | .bitAnd a i | .bitOr a i | .bitXor a i | .shiftLeft a i | .shiftRight a i
    | .eq a i | .ne a i | .lt a i | .le a i | .gt a i | .ge a i
    | .boolAnd a i | .boolOr a i =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars i
    | .field base _ | .cast base _ | .boolNot base | .hash base
    | .memoryArrayLength base | .memoryArrayNew _ base
    | .nearPromiseResultStatus base | .nearPromiseResultU64 base =>
        exprReadsPackedScalar scalars base
    | .structLit _ fields => fields.any (fun f => exprReadsPackedScalar scalars f.snd)
    | .hashValue a b c d =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars b ||
          exprReadsPackedScalar scalars c || exprReadsPackedScalar scalars d
    | .ecrecover a b c d =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars b ||
          exprReadsPackedScalar scalars c || exprReadsPackedScalar scalars d
    | .eip712PermitDigest a b c d e f =>
        #[a, b, c, d, e, f].any (exprReadsPackedScalar scalars)
    | .crosscallAbiPacked t _ _ _ _ _ _ _ _ => exprReadsPackedScalar scalars t
    | .crosscallInvoke t m args
    | .crosscallInvokeTyped t m args _
    | .crosscallInvokeStaticTyped t m args _
    | .crosscallInvokeDelegateTyped t m args _ =>
        exprReadsPackedScalar scalars t || exprReadsPackedScalar scalars m ||
          args.any (exprReadsPackedScalar scalars)
    | .crosscallInvokeValueTyped t m v args _ =>
        exprReadsPackedScalar scalars t || exprReadsPackedScalar scalars m ||
          exprReadsPackedScalar scalars v || args.any (exprReadsPackedScalar scalars)
    | .crosscallCreate v _ => exprReadsPackedScalar scalars v
    | .crosscallCreate2 v s _ =>
        exprReadsPackedScalar scalars v || exprReadsPackedScalar scalars s
    | .nearCrosscallInvokePool a m args d =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars m ||
          exprReadsPackedScalar scalars d || args.any (exprReadsPackedScalar scalars)
    | .nearPromiseThen p c args d =>
        exprReadsPackedScalar scalars p || exprReadsPackedScalar scalars c ||
          exprReadsPackedScalar scalars d || args.any (exprReadsPackedScalar scalars)

  partial def effectReadsPackedScalar (scalars : Array StateInfo) : Effect → Bool
    | .storageScalarRead id => isPackedScalarId scalars id
    | .storageScalarAssignOp id _ v =>
        isPackedScalarId scalars id || exprReadsPackedScalar scalars v
    | .storageStructFieldRead id _ => isPackedScalarId scalars id
    | .storagePathRead id path =>
        isPackedScalarId scalars id ||
          path.any (fun seg => match seg with
            | .index e | .mapKey e => exprReadsPackedScalar scalars e
            | .field _ => false)
    | .storageScalarWrite _ v => exprReadsPackedScalar scalars v
    | .storageMapContains _ k | .storageMapGet _ k => exprReadsPackedScalar scalars k
    | .storageMapInsert _ k v | .storageMapSet _ k v =>
        exprReadsPackedScalar scalars k || exprReadsPackedScalar scalars v
    | .storageArrayRead _ i | .storageArrayStructFieldRead _ i _ =>
        exprReadsPackedScalar scalars i
    | .storageArrayWrite _ i v | .storageArrayStructFieldWrite _ i _ v =>
        exprReadsPackedScalar scalars i || exprReadsPackedScalar scalars v
    | .storageDynamicArrayPush _ v | .storageStructFieldWrite _ _ v =>
        exprReadsPackedScalar scalars v
    | .storageDynamicArrayPop _ | .contextRead _ => false
    | .memoryArraySet _ i v =>
        exprReadsPackedScalar scalars i || exprReadsPackedScalar scalars v
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        path.any (fun seg => match seg with
          | .index e | .mapKey e => exprReadsPackedScalar scalars e
          | .field _ => false) ||
          exprReadsPackedScalar scalars v
    | .eventEmit _ fields =>
        fields.any (fun f => exprReadsPackedScalar scalars f.snd)
    | .eventEmitIndexed _ indexed data =>
        indexed.any (fun f => exprReadsPackedScalar scalars f.snd) ||
          data.any (fun f => exprReadsPackedScalar scalars f.snd)
    -- EVM-only ERC-721/1155 receive checks (PF-P2-02); still scan child exprs.
    | .checkErc721Received a b c d =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars b ||
          exprReadsPackedScalar scalars c || exprReadsPackedScalar scalars d
    | .checkErc1155Received a b c d e =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars b ||
          exprReadsPackedScalar scalars c || exprReadsPackedScalar scalars d ||
          exprReadsPackedScalar scalars e

  partial def stmtReadsPackedScalar (scalars : Array StateInfo) : Statement → Bool
    | .letBind _ _ e | .letMutBind _ _ e | .assign _ e | .assignOp _ _ e | .return e =>
        exprReadsPackedScalar scalars e
    | .effect eff => effectReadsPackedScalar scalars eff
    | .assert cond _ _ => exprReadsPackedScalar scalars cond
    | .assertEq a b _ _ =>
        exprReadsPackedScalar scalars a || exprReadsPackedScalar scalars b
    | .release _ | .revert _ | .revertWithError _ => false
    | .ifElse cond thenBody elseBody =>
        exprReadsPackedScalar scalars cond ||
          thenBody.any (stmtReadsPackedScalar scalars) ||
          elseBody.any (stmtReadsPackedScalar scalars)
    | .boundedFor _ _ _ body => body.any (stmtReadsPackedScalar scalars)
    | .whileLoop cond body =>
        exprReadsPackedScalar scalars cond || body.any (stmtReadsPackedScalar scalars)
end

/-- Entrypoint only writes packed scalars (no prior pack read/RMW) → safe to
skip cold `storage_read` via `__pf_pack_begin_fresh`. -/
def entrypointReadsPackedScalar (scalars : Array StateInfo) (ep : Entrypoint) : Bool :=
  ep.body.any (stmtReadsPackedScalar scalars)

def packHelperFuncs (packSize : Nat) (plan : ModulePlan) : Array Func :=
  #[packBeginFunc, packBeginFreshFunc packSize, packEnsureFunc packSize, packFlushFunc packSize] ++
    (if plan.scalarWriteTypes.contains .u64 then #[packWriteFunc .u64] else #[]) ++
    (if plan.scalarReadTypes.contains .u64 then #[packReadFunc .u64] else #[]) ++
    (if plan.scalarWriteTypes.contains .u32 then #[packWriteFunc .u32] else #[]) ++
    (if plan.scalarReadTypes.contains .u32 then #[packReadFunc .u32] else #[]) ++
    (if plan.scalarWriteTypes.contains .bool then #[packWriteFunc .bool] else #[]) ++
    (if plan.scalarReadTypes.contains .bool then #[packReadFunc .bool] else #[])

def storageScalarWriteInsns (structs : Array ProofForge.IR.StructDecl)
    (stateInfo : StateInfo) (id : String) (valueInsns : Array Insn)
    (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != stateInfo.type then
    err s!"EmitWat: scalar write `{id}` expected `{stateInfo.type.name}`, got `{valueType.name}`"
  else if stateInfo.packed then
    -- stack order: off (i32), then value (matches packWrite params)
    .ok (#[.i32Const stateInfo.packOffset] ++ valueInsns ++
      #[.call (packWriteName stateInfo.type)])
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

def storageScalarReadInsns (stateInfo : StateInfo) : Array Insn × ValueType :=
  if stateInfo.packed then
    (#[.i32Const stateInfo.packOffset, .call (packReadName stateInfo.type)], stateInfo.type)
  else
    let callName := if stateInfo.type == .hash then readHashName else readName stateInfo.type
    (#[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen, .call callName], stateInfo.type)

def storageScalarAssignOpTargetType (stateInfo : StateInfo) (id : String) :
    Except EmitError ValueType :=
  if stateInfo.type == .hash then
    err s!"EmitWat: storageScalarAssignOp not supported on Hash scalars (`{id}`)"
  else .ok stateInfo.type

def storageScalarAssignOpInsns (stateInfo : StateInfo) (id : String) (op : AssignOp)
    (valueInsns : Array Insn) (valueType : ValueType) : Except EmitError (Array Insn) :=
  if valueType != stateInfo.type then
    err s!"EmitWat: scalar assignOp `{id}` expected `{stateInfo.type.name}`, got `{valueType.name}`"
  else if stateInfo.packed then
    -- read; apply op; stage result in KEY_BUF; pack_write(offset, result)
    .ok (#[.i32Const stateInfo.packOffset, .call (packReadName stateInfo.type)] ++ valueInsns
          ++ #[.plain (widthOf stateInfo.type ++ "." ++ assignOpName op),
             .i32Const KEY_BUF, .store (storeOpFor stateInfo.type) 0,
             .i32Const stateInfo.packOffset,
             .i32Const KEY_BUF, .load (loadOpFor stateInfo.type) 0,
             .call (packWriteName stateInfo.type)])
  else
    .ok (#[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen,
             .i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen,
             .call (readName stateInfo.type)] ++ valueInsns
          ++ #[.plain (widthOf stateInfo.type ++ "." ++ assignOpName op),
             .call (writeName stateInfo.type)])

/-- NEAR register ABI: storage_read → read_register into KEY_BUF. -/
def readFuncNear (vt : ValueType) : Func :=
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

/-- Soroban host ABI (C.8): `_get(key_ptr, key_len) → i32` le-scalar; extend to value width. -/
def readFuncSoroban (vt : ValueType) : Func :=
  let extend : Array Insn :=
    match vt with
    | .u64 => #[.plain "i64.extend_i32_u"]
    | .u32 | .bool => #[]
    | _ => #[]
  { name := readName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[wasmTypeOf vt],
    body := { insns := #[.localGet "kp", .localGet "kl", .call "_get"] ++ extend } }

/-- CosmWasm host ABI: `db_read(key_ptr, key_len) → i64` (le scalar word). -/
def readFuncCosmWasm (vt : ValueType) : Func :=
  let narrow : Array Insn :=
    match vt with
    | .u64 => #[]
    | .u32 | .bool => #[.plain "i32.wrap_i64"]
    | _ => #[]
  { name := readName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[wasmTypeOf vt],
    body := { insns := #[.localGet "kp", .localGet "kl", .call "db_read"] ++ narrow } }

def readFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban => readFuncSoroban vt
  | .cosmWasm => readFuncCosmWasm vt
  | .near => readFuncNear vt

def writeFuncNear (vt : ValueType) : Func :=
  { name := writeName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0, .call "storage_write", .drop ] } }

/-- Soroban host ABI (C.8): stage value at KEY_BUF, `_put(key_ptr, key_len, val_ptr, val_len)`. -/
def writeFuncSoroban (vt : ValueType) : Func :=
  { name := writeName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      .localGet "kp", .localGet "kl", .i32Const KEY_BUF, .i32Const (scalarWidth vt),
      .call "_put" ] } }

/-- CosmWasm host ABI: stage value, `db_write(key_ptr, key_len, val_ptr, val_len)`. -/
def writeFuncCosmWasm (vt : ValueType) : Func :=
  { name := writeName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      .localGet "kp", .localGet "kl", .i32Const KEY_BUF, .i32Const (scalarWidth vt),
      .call "db_write" ] } }

def writeFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban => writeFuncSoroban vt
  | .cosmWasm => writeFuncCosmWasm vt
  | .near => writeFuncNear vt

def returnU64Func (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .cosmWasm =>
      { name := returnU64Name, params := #[{ name := "v", type := .i64 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i64.store" 0,
          .i32Const RET_BUF, .i32Const 8, .call "set_return_data" ] } }
  | _ =>
      { name := returnU64Name, params := #[{ name := "v", type := .i64 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i64.store" 0,
          .i64Const 8, .i64Const RET_BUF, .call "value_return" ] } }

def returnU32Func (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .cosmWasm =>
      { name := returnU32Name, params := #[{ name := "v", type := .i32 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i32.store" 0,
          .i32Const RET_BUF, .i32Const 4, .call "set_return_data" ] } }
  | _ =>
      { name := returnU32Name, params := #[{ name := "v", type := .i32 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i32.store" 0,
          .i64Const 4, .i64Const RET_BUF, .call "value_return" ] } }

def returnBoolFunc (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .cosmWasm =>
      { name := returnBoolName, params := #[{ name := "v", type := .i32 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i32.store8" 0,
          .i32Const RET_BUF, .i32Const 1, .call "set_return_data" ] } }
  | _ =>
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

def scalarStorageHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  let scalarTypes : Array ValueType := #[.u32, .u64, .bool]
  let funcs := scalarTypes.foldl (init := #[]) fun acc type =>
    let acc :=
      if plan.scalarReadTypes.contains type then
        acc.push (readFunc type bridge)
      else
        acc
    if plan.scalarWriteTypes.contains type then
      acc.push (writeFunc type bridge)
    else
      acc
  funcs

def returnHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  (if plan.returnTypes.contains .u64 then #[returnU64Func bridge] else #[]) ++
    (if plan.returnTypes.contains .u32 then #[returnU32Func bridge] else #[]) ++
    (if plan.returnTypes.contains .bool then #[returnBoolFunc bridge] else #[])

def powHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesPowU32 then #[powFunc .u32] else #[]) ++
    (if plan.usesPowU64 then #[powFunc .u64] else #[])

end ProofForge.Backend.WasmHost.Scalar
