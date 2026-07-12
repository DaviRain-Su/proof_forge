/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Common
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
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.LoweringEnv
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

/-! Scalar storage, return, and arithmetic helper functions for EmitWat. -/

/-- U128 arithmetic/comparison helper names. U128 is represented as two i64
    values (lo, hi); declared up here so all lowerings can reference them. -/
def u128AddName : String := "__pf_u128_add"
def u128SubName : String := "__pf_u128_sub"
def u128MulName : String := "__pf_u128_mul"
def u128EqName  : String := "__pf_u128_eq"
def u128LtName  : String := "__pf_u128_lt"
def u128Divmod10Name : String := "__pf_u128_divmod10"
def u128FmtName      : String := "__pf_fmt_u128"

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

def packEnsureFunc (packSize : Nat) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  let loadInsns := match bridge with
    | .soroban =>
      -- Soroban: _get returns i32 found flag; if found, data is at the
      -- key pointer location (Soroban writes directly to memory).
      -- For pack buffer, use _get then copy 0..packSize to PACK_BUF.
      #[.i32Const PACK_KEY_PTR, .i32Const PACK_KEY_LEN, .call "_get",
        .i32Const PACK_KEY_PTR, .i32Const PACK_BUF, .i32Const packSize, .call "__pf_memcpy"]
    | _ =>
      -- NEAR: storage_read → read_register into PACK_BUF
      #[.i64Const PACK_KEY_LEN, .i64Const PACK_KEY_PTR, .i64Const 0, .call "storage_read",
        .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[.i64Const 0, .i64Const PACK_BUF, .call "read_register"] }
           { insns := packZeroInsns packSize }]
  { name := packEnsureName,
    locals := if packSize % 8 == 0 then #[] else #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .globalGet packLoadedGlobal, .plain "i32.eqz",
      .if_ { insns := loadInsns ++ #[
          .i32Const 1, .globalSet packLoadedGlobal
        ] } { insns := #[] }
    ] } }

def packFlushFunc (packSize : Nat) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  let storeInsns := match bridge with
    | .soroban =>
      -- Soroban: _put(PACK_KEY_PTR, PACK_KEY_LEN, PACK_BUF, packSize)
      #[.i32Const PACK_KEY_PTR, .i32Const PACK_KEY_LEN,
        .i32Const PACK_BUF, .i32Const packSize, .call "_put"]
    | _ =>
      -- NEAR: storage_write(key_len, key_ptr, pack_size, pack_buf, 0)
      #[.i64Const PACK_KEY_LEN, .i64Const PACK_KEY_PTR,
        .i64Const packSize, .i64Const PACK_BUF, .i64Const 0,
        .call "storage_write", .drop]
  { name := packFlushName,
    body := { insns := #[
      .globalGet packDirtyGlobal,
      .if_ { insns := storeInsns ++ #[
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
    | .nearPromiseResultStatus base | .nearPromiseResultU64 base | .nearPromiseResultU128 base =>
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
    | .crosscallNamed _ _ args _ =>
        args.any (exprReadsPackedScalar scalars)
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
    | .storageMapContains _ k | .storageMapGet _ k | .storageMapDelete _ k => exprReadsPackedScalar scalars k
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

    | .checkErc1155BatchReceived a b c d e =>
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

/-- Conservative packed-state read scan. This remains useful for analysis, but
code generation must not infer a definite full overwrite merely from `false`:
an entrypoint may write only one field in a multi-field blob. -/
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
  else if stateInfo.type == .u128 then
    -- U128 is two i64 words: stage 16 bytes at KEY_BUF then reload lo/hi.
    (#[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen, .call (readName .u128),
      .i32Const KEY_BUF, .load "i64.load" 0,
      .i32Const (KEY_BUF + 8), .load "i64.load" 0], .u128)
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
  else if stateInfo.type == .u128 then
    -- U128 assignOp via the two-word (lo, hi) convention. Stack discipline:
    --   push kp,kl (reserved for the final write)
    --   read_u128(kp,kl) -> KEY_BUF; reload (lo,hi)
    --   valueInsns push (lo2,hi2)
    --   u128_{add,sub} consumes the top four words -> U128_RESULT_BUF (void)
    --   reload result (lo,hi); write_u128(kp,kl,lo,hi)
    let readPart : Array Insn :=
      #[.i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen,
        .i32Const stateInfo.keyPtr, .i32Const stateInfo.keyLen, .call (readName .u128),
        .i32Const KEY_BUF, .load "i64.load" 0,
        .i32Const (KEY_BUF + 8), .load "i64.load" 0]
    let writePart : Array Insn :=
      #[.i32Const U128_RESULT_BUF, .load "i64.load" 0,
        .i32Const (U128_RESULT_BUF + 8), .load "i64.load" 0,
        .call (writeName .u128)]
    match op with
    | .add => .ok (readPart ++ valueInsns ++ #[.call u128AddName] ++ writePart)
    | .sub => .ok (readPart ++ valueInsns ++ #[.call u128SubName] ++ writePart)
    | _ => err s!"EmitWat: U128 scalar assignOp `{assignOpName op}` not yet supported (`{id}`); only add/sub"
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

/-- Soroban spike ABI: `_get(key_ptr, key_len) → i64` little-endian scalar. -/
def readFuncSoroban (vt : ValueType) : Func :=
  let coerce : Array Insn :=
    match vt with
    | .u64 => #[]
    | .u32 | .bool => #[.plain "i32.wrap_i64"]
    | _ => #[]
  { name := readName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[wasmTypeOf vt],
    body := { insns := #[.localGet "kp", .localGet "kl", .call "_get"] ++ coerce } }

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
  | .cosmWasm | .soroban =>
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
  | .cosmWasm | .soroban =>
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
  | .cosmWasm | .soroban =>
      { name := returnBoolName, params := #[{ name := "v", type := .i32 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i32.store8" 0,
          .i32Const RET_BUF, .i32Const 1, .call "set_return_data" ] } }
  | _ =>
      { name := returnBoolName, params := #[{ name := "v", type := .i32 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "v", .store "i32.store8" 0,
          .i64Const 1, .i64Const RET_BUF, .call "value_return" ] } }

/-! U128 values flow as TWO i64 stack words (lo, hi) throughout EmitWat (see
    `u128AddFunc` / literal lowering). The return helper consumes those two
    words directly, staging them into RET_BUF and returning 16 little-endian
    bytes — the Borsh U128 wire shape. This avoids a `__pf_memcpy` dependency. -/
def returnU128Func (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .cosmWasm | .soroban =>
      { name := returnU128Name,
        params := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "lo", .store "i64.store" 0,
          .i32Const (RET_BUF + 8), .localGet "hi", .store "i64.store" 0,
          .i32Const RET_BUF, .i32Const 16, .call "set_return_data" ] } }
  | _ =>
      { name := returnU128Name,
        params := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 }],
        body := { insns := #[
          .i32Const RET_BUF, .localGet "lo", .store "i64.store" 0,
          .i32Const (RET_BUF + 8), .localGet "hi", .store "i64.store" 0,
          .i64Const 16, .i64Const RET_BUF, .call "value_return" ] } }

/-- `__pf_read_u128(kp, kl)`: void. NEAR register ABI: `storage_read` into
    register 0, `read_register` into KEY_BUF (16 bytes, lo@0 hi@8). The caller
    reloads the two i64 words from KEY_BUF. -/
def readU128FuncNear : Func :=
  { name := readName .u128,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[],
    body := { insns := #[
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 0, .call "storage_read", .drop,
      .i64Const 0, .i64Const KEY_BUF, .call "read_register" ] } }

/-- `__pf_write_u128(kp, kl, lo, hi)`: void. Stages (lo, hi) into KEY_BUF as 16
    little-endian bytes and writes them with `storage_write`. -/
def writeU128FuncNear : Func :=
  { name := writeName .u128,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 },
      { name := "lo", type := .i64 }, { name := "hi", type := .i64 }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "lo", .store "i64.store" 0,
      .i32Const (KEY_BUF + 8), .localGet "hi", .store "i64.store" 0,
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 16, .i64Const KEY_BUF, .i64Const 0, .call "storage_write", .drop ] } }

/-- `__pf_return_bytes(ptr)`: Borsh dynamic return. The buffer at `ptr` has a
4-byte LE length prefix at `ptr - 4`, followed by the payload. Computes
`total = 4 + len` and calls `value_return(total, ptr - 4)`. -/
def returnBytesFunc (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .cosmWasm | .soroban =>
      { name := returnBytesName, params := #[{ name := "ptr", type := .i32 }],
        body := { insns := #[
          .localGet "ptr", .i32Const 4, .plain "i32.sub", .localSet "ptr",
          .localGet "ptr", .load "i32.load" 0, .plain "i64.extend_i32_u",
          .i64Const 4, .plain "i64.add",
          .localGet "ptr", .plain "i64.extend_i32_u",
          .call "set_return_data" ] } }
  | _ =>
      { name := returnBytesName, params := #[{ name := "ptr", type := .i32 }],
        body := { insns := #[
          .localGet "ptr", .i32Const 4, .plain "i32.sub", .localSet "ptr",
          .localGet "ptr", .load "i32.load" 0, .plain "i64.extend_i32_u",
          .i64Const 4, .plain "i64.add",
          .localGet "ptr", .plain "i64.extend_i32_u",
          .call "value_return" ] } }

/-- `__pf_u128_add(alo, ahi, blo, bhi)`: void; writes (lo, hi) = a + b to
    `U128_RESULT_BUF`. NEAR VM disables `multi_value`, so u128 helpers return
    void and stash their (lo, hi) result in a 16-byte scratch slot; callers
    reload both words onto the stack immediately after the call. -/
def u128AddFunc : Func :=
  { name := u128AddName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 },
                { name := "blo", type := .i64 }, { name := "bhi", type := .i64 }],
    results := #[],
    locals := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 },
               { name := "carry", type := .i64 }],
    body := { insns := #[
      .localGet "alo", .localGet "blo", .plain "i64.add", .localSet "lo",
      .localGet "lo", .localGet "alo", .plain "i64.lt_u", .plain "i64.extend_i32_u",
      .i64Const 1, .plain "i64.and", .localSet "carry",
      .localGet "ahi", .localGet "bhi", .plain "i64.add", .localGet "carry", .plain "i64.add", .localSet "hi",
      .i32Const U128_RESULT_BUF, .localGet "lo", .store "i64.store" 0,
      .i32Const (U128_RESULT_BUF + 8), .localGet "hi", .store "i64.store" 0
    ] } }

/-- `__pf_u128_sub(alo, ahi, blo, bhi)`: void; writes (lo, hi) = a - b to
    `U128_RESULT_BUF`. See `u128AddFunc` for the multi_value workaround. -/
def u128SubFunc : Func :=
  { name := u128SubName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 },
                { name := "blo", type := .i64 }, { name := "bhi", type := .i64 }],
    results := #[],
    locals := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 },
               { name := "borrow", type := .i64 }],
    body := { insns := #[
      .localGet "alo", .localGet "blo", .plain "i64.sub", .localSet "lo",
      .localGet "alo", .localGet "blo", .plain "i64.lt_u", .plain "i64.extend_i32_u",
      .i64Const 1, .plain "i64.and", .localSet "borrow",
      .localGet "ahi", .localGet "bhi", .plain "i64.sub", .localGet "borrow", .plain "i64.sub", .localSet "hi",
      .i32Const U128_RESULT_BUF, .localGet "lo", .store "i64.store" 0,
      .i32Const (U128_RESULT_BUF + 8), .localGet "hi", .store "i64.store" 0
    ] } }

/-- `__pf_u128_mul(alo, ahi, blo, bhi)`: void; writes (lo, hi) = a * b to
    `U128_RESULT_BUF`. Simplified: only computes lo = alo * blo,
    hi = alo * bhi + ahi * blo (cross terms). Full 128-bit mul would need
    192-bit intermediates; this handles common cases. See `u128AddFunc` for
    the multi_value workaround. -/
def u128MulFunc : Func :=
  { name := u128MulName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 },
                { name := "blo", type := .i64 }, { name := "bhi", type := .i64 }],
    results := #[],
    locals := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 }],
    body := { insns := #[
      .localGet "alo", .localGet "blo", .plain "i64.mul", .localSet "lo",
      .localGet "alo", .localGet "bhi", .plain "i64.mul",
      .localGet "ahi", .localGet "blo", .plain "i64.mul",
      .plain "i64.add", .localSet "hi",
      .i32Const U128_RESULT_BUF, .localGet "lo", .store "i64.store" 0,
      .i32Const (U128_RESULT_BUF + 8), .localGet "hi", .store "i64.store" 0
     ] } }

/-- `__pf_u128_eq(alo, ahi, blo, bhi)`: returns i32 (1 if equal, 0 otherwise).
    Uses: hi_eq = (ahi == bhi); lo_eq = (alo == blo); result = hi_eq & lo_eq. -/
def u128EqFunc : Func :=
  { name := u128EqName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 },
                { name := "blo", type := .i64 }, { name := "bhi", type := .i64 }],
    results := #[.i32],
    locals := #[{ name := "hi_eq", type := .i32 }, { name := "lo_eq", type := .i32 }],
    body := { insns := #[
      .localGet "ahi", .localGet "bhi", .plain "i64.eq", .localSet "hi_eq",
      .localGet "alo", .localGet "blo", .plain "i64.eq", .localSet "lo_eq",
      .localGet "hi_eq", .localGet "lo_eq", .plain "i32.and"
    ] } }

/-! `__pf_u128_lt(alo, ahi, blo, bhi)`: returns i32 (1 if a < b unsigned).
    `a < b` iff `ahi < bhi || (ahi == bhi && alo < blo)`. Unsigned (lt_u);
    NEP-141 token amounts are non-negative. -/
def u128LtFunc : Func :=
  { name := u128LtName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 },
                { name := "blo", type := .i64 }, { name := "bhi", type := .i64 }],
    results := #[.i32],
    locals := #[{ name := "hi_lt", type := .i32 }, { name := "hi_gt", type := .i32 },
      { name := "lo_lt", type := .i32 }],
    body := { insns := #[
      .localGet "ahi", .localGet "bhi", .plain "i64.lt_u", .localSet "hi_lt",
      .localGet "ahi", .localGet "bhi", .plain "i64.gt_u", .localSet "hi_gt",
      .localGet "alo", .localGet "blo", .plain "i64.lt_u", .localSet "lo_lt",
      .localGet "hi_lt",
      .localGet "hi_gt", .plain "i32.eqz",
      .localGet "lo_lt", .plain "i32.and",
      .plain "i32.or" ] } }

def u128Divmod10Func : Func :=
  { name := u128Divmod10Name,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 }],
    results := #[.i64],
    locals := #[{ name := "rem", type := .i64 }, { name := "cur", type := .i64 },
      { name := "ql0", type := .i64 }, { name := "ql1", type := .i64 },
      { name := "ql2", type := .i64 }, { name := "ql3", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .localSet "rem",
      -- limb3 = ahi >> 32 ; cur = (rem << 32) | l3
      .localGet "rem", .i64Const 32, .plain "i64.shl",
      .localGet "ahi", .i64Const 32, .plain "i64.shr_u", .plain "i64.or", .localTee "cur",
      .i64Const 10, .plain "i64.div_u", .localSet "ql3",
      .localGet "cur", .i64Const 10, .plain "i64.rem_u", .localSet "rem",
      -- limb2 = ahi & 0xffffffff
      .localGet "rem", .i64Const 32, .plain "i64.shl",
      .localGet "ahi", .i64Const 0xffffffff, .plain "i64.and", .plain "i64.or", .localTee "cur",
      .i64Const 10, .plain "i64.div_u", .localSet "ql2",
      .localGet "cur", .i64Const 10, .plain "i64.rem_u", .localSet "rem",
      -- limb1 = alo >> 32
      .localGet "rem", .i64Const 32, .plain "i64.shl",
      .localGet "alo", .i64Const 32, .plain "i64.shr_u", .plain "i64.or", .localTee "cur",
      .i64Const 10, .plain "i64.div_u", .localSet "ql1",
      .localGet "cur", .i64Const 10, .plain "i64.rem_u", .localSet "rem",
      -- limb0 = alo & 0xffffffff
      .localGet "rem", .i64Const 32, .plain "i64.shl",
      .localGet "alo", .i64Const 0xffffffff, .plain "i64.and", .plain "i64.or", .localTee "cur",
      .i64Const 10, .plain "i64.div_u", .localSet "ql0",
      .localGet "cur", .i64Const 10, .plain "i64.rem_u", .localSet "rem",
      -- reassemble quotient and write to U128_RESULT_BUF
      .i32Const U128_RESULT_BUF,
        .localGet "ql0", .localGet "ql1", .i64Const 32, .plain "i64.shl", .plain "i64.or",
        .store "i64.store" 0,
      .i32Const (U128_RESULT_BUF + 8),
        .localGet "ql2", .localGet "ql3", .i64Const 32, .plain "i64.shl", .plain "i64.or",
        .store "i64.store" 0,
      .localGet "rem" ] } }

/-! `__pf_fmt_u128(alo, ahi) -> i32 ptr`: write the unsigned decimal string of
    the u128 backwards into RET_BUF (end = RET_BUF + 40; max 39 digits) and
    return the start pointer. Reuses `__pf_u128_divmod10` per digit. This is
    the JSON U128 primitive shared by event fields, crosscall args, and view
    returns (Phase 4). -/
def u128FmtFunc : Func :=
  { name := u128FmtName,
    params := #[{ name := "alo", type := .i64 }, { name := "ahi", type := .i64 }],
    results := #[.i32],
    locals := #[{ name := "ql", type := .i64 }, { name := "qh", type := .i64 },
      { name := "rem", type := .i64 }, { name := "p", type := .i32 }],
    body := { insns := #[
      .localGet "alo", .localSet "ql",
      .localGet "ahi", .localSet "qh",
      .i32Const (RET_BUF + 40), .localSet "p",
      -- zero case: emit a single '0'
      .localGet "ql", .plain "i64.eqz",
      .localGet "qh", .plain "i64.eqz", .plain "i32.and",
      .if_ { insns := #[
        .i32Const (RET_BUF + 39), .i32Const 48, .store "i32.store8" 0,
        .i32Const (RET_BUF + 39), .localSet "p" ] }
        { insns := #[ .block_ { insns := #[ .loop_ { insns := #[
          .localGet "ql", .plain "i64.eqz",
          .localGet "qh", .plain "i64.eqz", .plain "i32.and", .brIf 1,
          .localGet "ql", .localGet "qh", .call u128Divmod10Name, .localSet "rem",
          .i32Const U128_RESULT_BUF, .load "i64.load" 0, .localSet "ql",
          .i32Const (U128_RESULT_BUF + 8), .load "i64.load" 0, .localSet "qh",
          .localGet "p", .i32Const 1, .plain "i32.sub", .localTee "p",
          .i32Const 48, .localGet "rem", .plain "i32.wrap_i64", .plain "i32.add",
          .store "i32.store8" 0, .br 0 ] } ] } ] },
      .localGet "p" ] } }

def u128ArithFuncs : Array Func :=
  #[u128AddFunc, u128SubFunc, u128MulFunc, u128EqFunc, u128LtFunc, u128Divmod10Func, u128FmtFunc]

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
  -- U128 storage uses a distinct two-word (lo, hi) register ABI on NEAR; the
  -- single-word `readFunc`/`writeFunc` above do not fit it. Soroban/CosmWasm
  -- U128 storage is not materialized in this slice.
  let u128Funcs :=
    if bridge == .near then
      (if plan.scalarReadTypes.contains .u128 then #[readU128FuncNear] else #[]) ++
        (if plan.scalarWriteTypes.contains .u128 then #[writeU128FuncNear] else #[])
    else
      #[]
  funcs ++ u128Funcs

def returnHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  (if plan.returnTypes.contains .u64 then #[returnU64Func bridge] else #[]) ++
    (if plan.returnTypes.contains .u32 then #[returnU32Func bridge] else #[]) ++
    (if plan.returnTypes.contains .bool then #[returnBoolFunc bridge] else #[]) ++
    (if plan.returnTypes.contains .u128 then #[returnU128Func bridge] else #[]) ++
    (if plan.returnTypes.contains .bytes || plan.returnTypes.contains .string then
      #[returnBytesFunc bridge] else #[])

def powHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesPowU32 then #[powFunc .u32] else #[]) ++
    (if plan.usesPowU64 then #[powFunc .u64] else #[])

end ProofForge.Backend.WasmHost.Scalar
