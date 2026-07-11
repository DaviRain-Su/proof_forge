/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EmitWat — lowers the portable IR (`ProofForge.IR.Contract`) to a `Wasm.Module`
that `Wasm.Printer` renders to WAT, then `wat2wasm`.

**Wasm-family backend** (`ProofForge.Backend.WasmHost`): one EmitWat core,
parameterized by `ProofForge.Target.HostBridge`:

| Bridge | Registry targets (examples) | Storage / crosscall materialization |
|--------|----------------------------|-------------------------------------|
| `.near` | `wasm-near` | `storage_*` / `promise_create` |
| `.soroban` | `wasm-stellar-soroban` | `_get`/`_put` / `invoke_contract` |
| `.cosmWasm` | `wasm-cosmwasm` | `db_read`/`db_write` (+ Counter spike exports) |

Historical package name was `Backend.WasmNear` (NEAR-first). Prefer
`Backend.WasmHost`. Target id `wasm-near` remains the NEAR product target.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.IR.Ownership
import ProofForge.Target.ProtocolMaterialize
import ProofForge.Compiler.Wasm.AST
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Backend.WasmHost.Aggregate
import ProofForge.Backend.WasmHost.Assert
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Capabilities
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Context
import ProofForge.Backend.WasmHost.CosmWasm.EmitWat
import ProofForge.Backend.WasmHost.Crosscall
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.ExprAnalysis
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.Imports
import ProofForge.Backend.WasmHost.JsonEncode
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Locals
import ProofForge.Backend.WasmHost.LoweringEnv
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.ModuleAssembly
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.PortableCrosscall
import ProofForge.Backend.WasmHost.Promise
import ProofForge.Backend.WasmHost.Return
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Statement
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.PeerMap
import ProofForge.Target.Plan
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmHost.EmitWat

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Aggregate
open ProofForge.Backend.WasmHost.Assert
open ProofForge.Backend.WasmHost.ArrayHeap
open ProofForge.Backend.WasmHost.Capabilities
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Context
open ProofForge.Backend.WasmHost.Crosscall
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Event
open ProofForge.Backend.WasmHost.ExprAnalysis
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.Imports
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Locals
open ProofForge.Backend.WasmHost.LoweringEnv
open ProofForge.Backend.WasmHost.Map
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.ModuleAssembly
open ProofForge.Backend.WasmHost.Params
open ProofForge.Backend.WasmHost.Promise
open ProofForge.Backend.WasmHost.Return
open ProofForge.Backend.WasmHost.Scalar
open ProofForge.Backend.WasmHost.Statement
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

export ProofForge.Backend.WasmHost.Aggregate (
  arrayLitName arrEqName collectArrayLitsPathSegment collectArrayLitsPath
  collectArrayLitsExpr collectArrayLitsEffect collectStructLitsExpr
  collectStructLitsPathSegment collectStructLitsPath collectStructLitsEffect
  collectArrayLitsStmt dedupArrayLits moduleArrayLits arrLitFunc
  arrLitHelperFuncs arrEqFunc arrEqHelperFuncs structLitFunc
  collectStructLitsStmt dedupStrings moduleStructLitNames
  structLitHelperFuncs arrayLitFuncsForModulePlan arrayEqFuncsForModulePlan
  structLitFuncsForModulePlan aggregateHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmHost.Assert (
  assertFailInsns
)

export ProofForge.Backend.WasmHost.ArrayHeap (
  arrPtrGlobal arrFreeGlobal arrAllocName arrPtrGlobalDecl arrFreeGlobalDecl
  arrAllocFunc arrDeallocFunc modulePlanUsesArrHeap
  arrHeapHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmHost.Capabilities (
  emitWatCapabilities checkCapabilities checkTargetPlan
)

export ProofForge.Backend.WasmHost.Common (
  memcpyName memcpyFunc
)

export ProofForge.Backend.WasmHost.Context (
  ctxUserIdName ctxUserHashName ctxContractIdName ctxSignerName
  ctxRandomSeedName ctxUserIdFunc ctxUserHashFunc ctxContractIdFunc
  ctxSignerFunc ctxRandomSeedFunc ctxHelperFuncsForModulePlan
  lowerContextExprPlan
)

export ProofForge.Backend.WasmHost.Crosscall (
  crosscallPtrGlobal crosscallArgsStartName crosscallArgsPutcName
  crosscallArgsPutu64Name crosscallArgsPutboolName crosscallArgsPuthashName
  crosscallPtrGlobalDecl crosscallArgsStartFunc crosscallArgsPutcFunc
  crosscallArgsPutstrName crosscallArgsPutstrFunc crosscallArgsPutu64Func
  crosscallArgsPutboolFunc crosscallArgsPuthashFunc
  crosscallArgsHelperFuncsForModulePlan crosscallGlobalsForModulePlan
  poolLookupSetBody crosscallPoolPtrFunc crosscallPoolLenFunc
  crosscallPoolHelperFuncs
)

export ProofForge.Backend.WasmHost.Diagnostics (
  nativeValueUnsupportedMessage indexedEventUnsupportedMessage
  crosscallUnsupportedMessage crosscallEvmOnlyMessage
  crosscallTypedUnsupportedMessage
  sorobanNearPromiseUnsupportedMessage
  EmitError err
)

export ProofForge.Backend.WasmHost.Event (
  fmtU64Name evtPtrGlobal evtStartName evtPutcName evtPutstrName
  evtPutu64Name evtPutboolName evtPutHashName evtLogName evtPtrGlobalDecl
  fmtU64Func evtStartFunc evtPutcFunc evtPutstrFunc evtPutu64Func
  evtPutboolFunc evtPutHashFunc evtLogFunc evtHelperFuncsForModulePlan
  evtGlobals evtPutcInsns evtHeaderInsns evtValueInsnsForType
  evtFieldInsns evtFooterInsns
)

export ProofForge.Backend.WasmHost.ExprAnalysis (
  canDuplicateExpr exprReturnsNearPromise
)

export ProofForge.Backend.WasmHost.Hash (
  modulePlanUsesHashAlloc hashAllocName hashMakeName hashSName hashTwoName
  hashEqName readHashName writeHashName hashPtrGlobal hashPtrGlobalDecl
  hashAllocFunc hashMakeFunc hashSFunc hashTwoFunc hashEqFunc readHashFunc
  writeHashFunc hashExprHelperFuncsForModulePlan
  hashStorageHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmHost.Imports (
  hostImport valTypeOfString hostFunctionImport dedupeImports bridgeBaseImports
  nearImports storageHasKeyImport sha256Import logUtf8Import inputImport
  panicImport predecessorImport currentAcctImport signerImport depositImport
  registerLenImport blockHeightImport epochHeightImport randomSeedImport
  allocImportName deallocImportName allocImport deallocImport
  modulePlanUsesSha256 nearImportsForModulePlan ctxImportsForModulePlan
  promiseCtxImportsForModulePlan promiseResultImportsForModulePlan
  hostAllocatorImportsForModulePlan importsForModulePlan
)

export ProofForge.Backend.WasmHost.Layout (
  StateInfo isPackableScalarType moduleScalarsPackable stateLayout
  stateLayoutPacked findScalarState? MapInfo mapLayout findMapState?
  findArrayState? StringInfo eventHeaderPoolString eventFieldPoolString
  stringPool panicMessage panicPool findString? crosscallStringInfos
)

export ProofForge.Backend.WasmHost.LoweringEnv (
  Ctx LBind LocalTypes lookupLocal? assignOpName resolveCrosscallStringRef
)

export ProofForge.Backend.WasmHost.Locals (
  collectLocalsFrom collectLocals
)

export ProofForge.Backend.WasmHost.Map (
  mapReadName mapWriteName mapContainsName mapBuildkeyName mapBuildkeyFunc
  mapWriteStateInfo mapWriteCall mapWriteValueInsns
  mapReadStateInfo mapReadCall mapReadValueInsns
  mapContainsStateInfo mapContainsCall mapContainsValueInsns
  storageArrayStateInfo storageArrayReadInsns
  storageArrayWriteStateInfo storageArrayWriteInsns
  nestedMapReadStateInfo nestedMapReadValueInsns
  nestedMapWriteStateInfo nestedMapWriteValueInsns
  mapReadFunc mapWriteFunc mapContainsFunc mapHelperFuncsForModulePlan
  mapBuildkeyHashName mapReadHashName mapWriteHashName mapContainsHashName
  mapBuildkeyHashFunc mapReadHashFunc mapWriteHashFunc mapContainsHashFunc
  mapHashHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmHost.Memory (
  KEY_BUF RET_BUF TRUE_PTR FALSE_PTR HEX_LUT_PTR MAPKEY_BUF HASH_HEAP ARR_HEAP
  HASH_CONCAT_BUF CTX_BUF EVENT_BUF EVT_KEY_PTR STRING_BASE INPUT_BUF
  CROSSCALL_BUF CROSSCALL_ARGS_EMPTY_PTR CROSSCALL_ARGS_EMPTY_LEN
  CROSSCALL_STRING_BASE crosscallDefaultGas PARAM_HASH_BUF ZERO_HASH_BUF
  OLD_HASH_BUF STRUCT_BUF PROMISE_RESULT_BUF crosscallPoolPtrName
  crosscallPoolLenName disjointRegions memoryLayoutNonoverlap
  memoryLayoutNonoverlap_valid
)

export ProofForge.Backend.WasmHost.ModuleAssembly (
  moduleStringPoolEnd loweringCtxForModule dataSegmentsForModulePlan
  helperFuncsForModulePlan globalsForModulePlan
)

export ProofForge.Backend.WasmHost.Params (
  loadParams
)

export ProofForge.Backend.WasmHost.Promise (
  promiseCurrentAccountName promiseCurrentAccountFunc promiseResultU64Name
  promiseResultU64Func promiseHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmHost.Return (
  returnInsnsForLoweredExpr
)

export ProofForge.Backend.WasmHost.Scalar (
  storageScalarStateInfo storageScalarWriteInsns
  storageScalarAssignOpTargetType storageScalarAssignOpInsns
  readFunc writeFunc returnU64Func returnU32Func returnBoolFunc powName
  powFunc scalarStorageHelperFuncsForModulePlan returnHelperFuncsForModulePlan
  powHelperFuncsForModulePlan
  u128AddName u128SubName u128MulName u128EqName u128ArithFuncs
)

export ProofForge.Backend.WasmHost.Statement (
  localLetBindInsns localAssignInsns localAssignOpTargetType localAssignOpInsns
  storagePathAssignOpTargetType storagePathAssignOpValueInsns releaseInsns
  dropResultInsns appendInsnChunks appendInsnChunksM requireDuplicableExpr ifElseInsns boundedForInsns
)

export ProofForge.Backend.WasmHost.Struct (
  findStruct? ScalarStructStateInfo scalarStructStateInfo
  ArrayStructInfo arrayStructMapInfo arrayStructInfo
  structTotalSize structFieldOffset? structFieldType?
  structLitName isStructStorageFieldType isIndexedStorageValueType
  structStorageFieldsSupported structStorageFieldInfo zeroStructBufInsns readScalarStructBufInsns
  scalarStructFieldReadInsns scalarStructFieldWriteInsns
  readArrayStructBufInsns arrayStructFieldReadInsns arrayStructFieldWriteInsns
)

export ProofForge.Backend.WasmHost.Types (
  wasmTypeOf widthOf isNumeric isScalarBorshType scalarWidth loadOpFor
  storeOpFor typeSuffix readName writeName returnU32Name returnU64Name
  returnBoolName
)

def stringInfoEnd (base : Nat) (strings : Array StringInfo) : Nat :=
  strings.foldl (init := base) fun acc s => max acc (s.ptr + s.len + 1)

/-- Flat Borsh width for param buffer sizing (struct uses worst-case until layout known). -/
def borshFlatWidth (ty : ProofForge.IR.ValueType) : Nat :=
  match ty with
  | .u32 => 4
  | .u64 => 8
  | .bool => 1
  | .hash => 32
  | .u128 => 16
  | .fixedArray elem n => scalarWidth elem * n
  | .structType _ => 512
  | .bytes | .string => 260
  | _ => 0

/-- Exact Borsh payload size for supported aggregate return types (N1.2). -/
def borshReturnPayloadBytes (structs : Array ProofForge.IR.StructDecl) (ty : ProofForge.IR.ValueType)
    : Except EmitError (Option Nat) :=
  match ty with
  | .u32 | .u64 | .bool | .hash | .u128 | .unit => .ok none
  | .fixedArray elem n =>
    if !(isScalarBorshType elem) then
      err s!"EmitWat: return fixedArray element type `{elem.name}` is not a scalar Borsh type"
    else
      .ok (some (scalarWidth elem * n))
  | .structType typeName =>
    match structs.find? (fun s => s.name == typeName) with
    | none => err s!"EmitWat: return type references unknown struct `{typeName}`"
    | some sd =>
      if !structStorageFieldsSupported sd then
        err s!"EmitWat: return struct `{typeName}` has non-scalar fields \
(only u32/u64/bool/hash supported in Borsh returns)"
      else
        .ok (some (structTotalSize sd))
  | .bytes | .string => .ok none
  | _ => err s!"EmitWat: return type `{ty.name}` is not supported"

def entrypointInputBytes (_structs : Array ProofForge.IR.StructDecl) (ep : ProofForge.IR.Entrypoint) : Nat :=
  ep.params.foldl (fun acc param => acc + borshFlatWidth param.snd) 0

def entrypointHashParamCount (ep : ProofForge.IR.Entrypoint) : Nat :=
  ep.params.foldl (fun acc param => if param.snd == ProofForge.IR.ValueType.hash then acc + 1 else acc) 0

def eventPayloadBound (name : String) (fieldCount : Nat) (fieldNameBytes : Nat) : Nat :=
  16 + name.length + fieldNameBytes + fieldCount * 96

def crosscallArgsBound (argCount : Nat) : Nat :=
  2 + argCount * 96

def validateScratchCapacities
    (mod : ProofForge.IR.Module)
    (strs panics crosscallStrs : Array StringInfo) : Except EmitError Unit := do
  let stringEnd := stringInfoEnd STRING_BASE (strs ++ panics)
  if stringEnd > INPUT_BUF then
    err s!"EmitWat: event/panic string pool requires {stringEnd - STRING_BASE} bytes, limit is {INPUT_BUF - STRING_BASE}"
  let crosscallStringEnd := stringInfoEnd CROSSCALL_STRING_BASE crosscallStrs
  if crosscallStringEnd > ZERO_HASH_BUF then
    err s!"EmitWat: NEAR crosscall string pool requires {crosscallStringEnd - CROSSCALL_STRING_BASE} bytes, limit is {ZERO_HASH_BUF - CROSSCALL_STRING_BASE}"
  for ep in mod.entrypoints do
    let inputBytes := entrypointInputBytes mod.structs ep
    if inputBytes > PARAM_HASH_BUF - INPUT_BUF then
      err s!"EmitWat: entrypoint `{ep.name}` Borsh input requires {inputBytes} bytes, limit is {PARAM_HASH_BUF - INPUT_BUF}"
    let hashSlots := entrypointHashParamCount ep
    if hashSlots * 32 > CROSSCALL_BUF - PARAM_HASH_BUF then
      err s!"EmitWat: entrypoint `{ep.name}` hash params require {hashSlots * 32} bytes, limit is {CROSSCALL_BUF - PARAM_HASH_BUF}"
    for stmt in ep.body do
      match stmt with
      | .effect (.eventEmit name fields) =>
          let fieldNameBytes := fields.foldl (fun acc field => acc + field.fst.length) 0
          let required := eventPayloadBound name fields.size fieldNameBytes
          if required > EVT_KEY_PTR - EVENT_BUF then
            err s!"EmitWat: event `{name}` JSON scratch requires up to {required} bytes, limit is {EVT_KEY_PTR - EVENT_BUF}"
      | .effect (.eventEmitIndexed name indexedFields dataFields) =>
          let fieldNameBytes :=
            indexedFields.foldl (fun acc field => acc + field.fst.length) 0 +
              dataFields.foldl (fun acc field => acc + field.fst.length) 0
          let fieldCount := indexedFields.size + dataFields.size
          let required := eventPayloadBound name fieldCount fieldNameBytes
          if required > EVT_KEY_PTR - EVENT_BUF then
            err s!"EmitWat: event `{name}` JSON scratch requires up to {required} bytes, limit is {EVT_KEY_PTR - EVENT_BUF}"
      | .letBind _ _ (.nearCrosscallInvokePool _ _ args _)
      | .letMutBind _ _ (.nearCrosscallInvokePool _ _ args _)
      | .return (.nearCrosscallInvokePool _ _ args _) =>
          let required := crosscallArgsBound args.size
          if required > CROSSCALL_ARGS_EMPTY_PTR - CROSSCALL_BUF then
            err s!"EmitWat: NEAR crosscall args require up to {required} bytes, limit is {CROSSCALL_ARGS_EMPTY_PTR - CROSSCALL_BUF}"
      | .letBind _ _ (.nearPromiseThen _ _ args _)
      | .letMutBind _ _ (.nearPromiseThen _ _ args _)
      | .return (.nearPromiseThen _ _ args _) =>
          let required := crosscallArgsBound args.size
          if required > CROSSCALL_ARGS_EMPTY_PTR - CROSSCALL_BUF then
            err s!"EmitWat: NEAR promise callback args require up to {required} bytes, limit is {CROSSCALL_ARGS_EMPTY_PTR - CROSSCALL_BUF}"
      | _ => pure ()

def crosscallArgsLenInsns (args : Array Expr) (argsLenMarker : Nat) : Array Insn :=
  if args.isEmpty then
    #[.i64Const argsLenMarker]
  else
    #[.globalGet crosscallPtrGlobal, .i32Const CROSSCALL_BUF, .plain "i32.sub", .plain "i64.extend_i32_u"]

def crosscallArgsPtrInsns (argsPtr : Nat) : Array Insn :=
  #[.i32Const argsPtr, .plain "i64.extend_i32_u"]

def stringInfoLenPtrInsns (si : StringInfo) : Array Insn :=
  #[.i64Const si.len, .i32Const si.ptr, .plain "i64.extend_i32_u"]

-- Type-directed expression lowering (mutually recursive)
mutual
  partial def lowerCrosscallArgValue (ctx : Ctx) (env : LocalTypes) (arg : Expr) :
      Except EmitError (Array Insn × Array Insn) := do
    let (vis, vt) ← lowerExpr ctx env arg
    match vt with
    | .u64 => .ok (vis, #[.call crosscallArgsPutu64Name])
    | .u32 => .ok (vis ++ #[.plain "i64.extend_i32_u"], #[.call crosscallArgsPutu64Name])
    | .bool => .ok (vis, #[.call crosscallArgsPutboolName])
    | .hash => .ok (vis, #[.call crosscallArgsPuthashName])
    | _ => err s!"EmitWat: NEAR crosscall argument type `{vt.name}` is not supported yet"

  /-- Pool index as i64: address-literal handles (peerHandle) or U32/U64. -/
  partial def lowerPoolIndexI64 (ctx : Ctx) (env : LocalTypes) (idxExpr : Expr) :
      Except EmitError (Array Insn) :=
    match idxExpr with
    | .literal (.address idx) => .ok #[.i64Const idx]
    | _ => lowerU32OrU64AsI64 ctx env "NEP-141 account pool index" idxExpr

  /-- `JsonEncode.strPoolIdx` leaf from a pool-index expr. -/
  partial def jsonStrPoolIdx (ctx : Ctx) (env : LocalTypes) (idxExpr : Expr) :
      Except EmitError ProofForge.Backend.WasmHost.JsonEncode.Node := do
    requireDuplicableExpr idxExpr "EmitWat: NEP-141 account pool index must be duplicable"
    let idxInsns ← lowerPoolIndexI64 ctx env idxExpr
    .ok (.strPoolIdx idxInsns)

  /-- `JsonEncode.u64Str` leaf (quoted decimal) from U32/U64 expr. -/
  partial def jsonU64Str (ctx : Ctx) (env : LocalTypes) (amount : Expr) :
      Except EmitError ProofForge.Backend.WasmHost.JsonEncode.Node := do
    let (vis, vt) ← lowerExpr ctx env amount
    if !(vt == .u64 || vt == .u32) then
      err s!"EmitWat: NEP-141 amount expected U32/U64, got `{vt.name}`"
    else
      let conv := if vt == .u64 then vis else vis ++ #[.plain "i64.extend_i32_u"]
      .ok (.u64Str conv)

  /-- Lower a JsonEncode node into the crosscall args buffer. -/
  partial def lowerJsonEncodeCrosscall
      (root : ProofForge.Backend.WasmHost.JsonEncode.Node) :
      Except EmitError (Array Insn × Nat × Nat) :=
    match ProofForge.Backend.WasmHost.JsonEncode.lowerCrosscallArgs root CROSSCALL_BUF with
    | .ok r => .ok r
    | .error msg => err s!"EmitWat: JsonEncode: {msg}"

  /-- NEP-141 `ft_transfer` via JsonEncode object schema. -/
  partial def lowerNep141FtTransferArgs (ctx : Ctx) (env : LocalTypes) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) := do
    match args[0]?, args[1]? with
    | some recv, some amount =>
        if args.size != 2 then
          err s!"EmitWat: NEP-141 ft_transfer expects 2 args [receiver_pool_idx, amount], got {args.size}"
        else
          let recvN ← jsonStrPoolIdx ctx env recv
          let amountN ← jsonU64Str ctx env amount
          lowerJsonEncodeCrosscall (.obj #[
            ProofForge.Backend.WasmHost.JsonEncode.field "receiver_id" recvN,
            ProofForge.Backend.WasmHost.JsonEncode.field "amount" amountN,
            ProofForge.Backend.WasmHost.JsonEncode.field "memo" .null_
          ])
    | _, _ =>
        err s!"EmitWat: NEP-141 ft_transfer expects 2 args [receiver_pool_idx, amount], got {args.size}"

  /-- NEP-141 `ft_transfer_call` via JsonEncode. -/
  partial def lowerNep141FtTransferCallArgs (ctx : Ctx) (env : LocalTypes) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) := do
    match args[0]?, args[1]? with
    | some recv, some amount =>
        if args.size < 2 || args.size > 3 then
          err s!"EmitWat: NEP-141 ft_transfer_call expects 2–3 args [receiver, amount, msg?], got {args.size}"
        else
          let recvN ← jsonStrPoolIdx ctx env recv
          let amountN ← jsonU64Str ctx env amount
          let msgN ←
            match args[2]? with
            | some msg => jsonU64Str ctx env msg
            | none => .ok (.strLit "")
          lowerJsonEncodeCrosscall (.obj #[
            ProofForge.Backend.WasmHost.JsonEncode.field "receiver_id" recvN,
            ProofForge.Backend.WasmHost.JsonEncode.field "amount" amountN,
            ProofForge.Backend.WasmHost.JsonEncode.field "msg" msgN
          ])
    | _, _ =>
        err s!"EmitWat: NEP-141 ft_transfer_call expects 2–3 args [receiver, amount, msg?], got {args.size}"

  /-- NEP-141 `ft_balance_of` via JsonEncode. -/
  partial def lowerNep141FtBalanceOfArgs (ctx : Ctx) (env : LocalTypes) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) := do
    match args[0]? with
    | some acct =>
        if args.size != 1 then
          err s!"EmitWat: NEP-141 ft_balance_of expects 1 arg [account_pool_idx], got {args.size}"
        else
          let acctN ← jsonStrPoolIdx ctx env acct
          lowerJsonEncodeCrosscall
            (.obj #[ProofForge.Backend.WasmHost.JsonEncode.field "account_id" acctN])
    | none =>
        err s!"EmitWat: NEP-141 ft_balance_of expects 1 arg [account_pool_idx], got {args.size}"

  /-- Empty JSON object `{}` for query methods with no args. -/
  partial def lowerJsonEmptyObjectArgs : Except EmitError (Array Insn × Nat × Nat) :=
    lowerJsonEncodeCrosscall (.obj #[])

  /-- Dispatch: NEP-141 object JSON for known methods; else legacy JSON array of scalars.
  Accepts portable aliases (`transfer` → `ft_transfer`) via ProtocolMaterialize. -/
  partial def lowerCrosscallArgsForMethod (ctx : Ctx) (env : LocalTypes)
      (methodName : String) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) :=
    let native :=
      match ProofForge.Target.ProtocolMaterialize.nearMethod? methodName with
      | some m => m
      | none => methodName
    match native with
    | "ft_transfer" => lowerNep141FtTransferArgs ctx env args
    | "ft_transfer_call" => lowerNep141FtTransferCallArgs ctx env args
    | "ft_balance_of" => lowerNep141FtBalanceOfArgs ctx env args
    | "ft_total_supply" | "ft_metadata" =>
        if args.isEmpty then lowerJsonEmptyObjectArgs
        else err s!"EmitWat: NEP-141 `{methodName}` expects 0 args, got {args.size}"
    | _ => lowerCrosscallArgsJson ctx env args

  partial def lowerCrosscallArgsJson (ctx : Ctx) (env : LocalTypes) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) := do
    if args.isEmpty then
      -- near-sdk zero-arg methods expect empty input (not JSON `[]`).
      .ok (#[], CROSSCALL_ARGS_EMPTY_PTR, 0)
    else
      let (body, _) ← args.foldlM (fun (accInsns, isFirst) arg => do
        let (vis, putInsn) ← lowerCrosscallArgValue ctx env arg
        let sep := if isFirst then #[] else #[.i32Const 44, .call crosscallArgsPutcName]
        .ok (accInsns ++ sep ++ vis ++ putInsn, false))
        (#[.call crosscallArgsStartName, .i32Const 91, .call crosscallArgsPutcName], true)
      let body := body ++ #[.i32Const 93, .call crosscallArgsPutcName]
      .ok (body, CROSSCALL_BUF, 0)

  /-- near-sys `promise_create` / `promise_then` take `amount_ptr` (u128 LE), not a
  raw yocto value. Encode U64 deposit as low 64 bits at `RET_BUF`, zero high 64,
  and push `RET_BUF` as the pointer. Constant-zero deposit reuses `ZERO_HASH_BUF`. -/
  partial def lowerNearDeposit (ctx : Ctx) (env : LocalTypes) (label : String) (deposit : Expr) :
      Except EmitError (Array Insn) := do
    match deposit with
    | .literal (.u64 0) =>
        .ok #[.i64Const ZERO_HASH_BUF]
    | _ =>
      let (depositInsns, depositType) ← lowerExpr ctx env deposit
      if depositType != .u64 then
        err s!"EmitWat: {label} deposit expected `U64`, got `{depositType.name}`"
      else
        -- stack after depositInsns: value; store [addr,value]; zero hi; push ptr
        .ok (#[.i32Const RET_BUF] ++ depositInsns ++ #[
          .store "i64.store" 0,
          .i32Const (RET_BUF + 8), .i64Const 0, .store "i64.store" 0,
          .i64Const RET_BUF
        ])

  partial def lowerU32OrU64AsI64 (ctx : Ctx) (env : LocalTypes) (label : String) (value : Expr) :
      Except EmitError (Array Insn) := do
    let (valueInsns, valueType) ← lowerExpr ctx env value
    if !(valueType == .u32 || valueType == .u64) then
      err s!"EmitWat: {label} expected U32/U64, got `{valueType.name}`"
    else
      let conv := if valueType == .u64 then #[] else #[.plain "i64.extend_i32_u"]
      .ok (valueInsns ++ conv)

  partial def lowerNearCrosscallInvokePool (ctx : Ctx) (env : LocalTypes) (accountIndex method : Expr)
      (args : Array Expr) (deposit : Expr) : Except EmitError (Array Insn × ValueType) := do
    if ctx.crosscallStrings.isEmpty then
      err "EmitWat: NEAR crosscall pool invoke requires `module.nearCrosscallStrings` to be populated"
    let accountConv ← lowerU32OrU64AsI64 ctx env "NEAR crosscall pool account index" accountIndex
    requireDuplicableExpr accountIndex "EmitWat: NEAR crosscall pool account index must be duplicable"
    let methodSi ← resolveCrosscallStringRef ctx method "method name"
    let (argBuildInsns, argsPtr, argsLenMarker) ←
      lowerCrosscallArgsForMethod ctx env methodSi.str args
    let depositInsns ← lowerNearDeposit ctx env "NEAR crosscall" deposit
    let argsLenInsns := crosscallArgsLenInsns args argsLenMarker
    let argsPtrInsns := crosscallArgsPtrInsns argsPtr
    .ok (argBuildInsns ++ accountConv ++ #[
      .call crosscallPoolLenName
    ] ++ accountConv ++ #[
      .call crosscallPoolPtrName
    ] ++ stringInfoLenPtrInsns methodSi ++ argsLenInsns ++ argsPtrInsns ++ depositInsns ++ #[
      .i64Const crosscallDefaultGas,
      .call "promise_create"
    ], .u64)

  /-- Shared string-pool + JSON-args packing for host-bridge remote invoke
  (Soroban `invoke_contract`, CosmWasm `execute_msg`). Not NEAR promise. -/
  partial def lowerHostBridgeRemoteInvoke (ctx : Ctx) (env : LocalTypes)
      (target method : Expr) (args : Array Expr) (hostFn bridgeLabel : String) :
      Except EmitError (Array Insn × ValueType) := do
    if ctx.crosscallStrings.isEmpty then
      err s!"EmitWat: {bridgeLabel} remote requires `module.nearCrosscallStrings` for contract/method names"
    let contract ← resolveCrosscallStringRef ctx target "target contract id"
    let methodSi ← resolveCrosscallStringRef ctx method "method name"
    let (argBuildInsns, argsPtr, argsLenMarker) ← lowerCrosscallArgsJson ctx env args
    let argsLenInsns := crosscallArgsLenInsns args argsLenMarker
    let argsPtrInsns := crosscallArgsPtrInsns argsPtr
    .ok (argBuildInsns ++
      stringInfoLenPtrInsns contract ++
      stringInfoLenPtrInsns methodSi ++
      argsLenInsns ++ argsPtrInsns ++ #[
      .call hostFn
    ], .u64)

  /-- Portable crosscall → Soroban host `invoke_contract` (not NEAR promise). -/
  partial def lowerSorobanInvoke (ctx : Ctx) (env : LocalTypes) (target method : Expr)
      (args : Array Expr) : Except EmitError (Array Insn × ValueType) :=
    lowerHostBridgeRemoteInvoke ctx env target method args "invoke_contract" "Soroban"

  /-- **SPIKE / STUB (U7.2):** portable crosscall → CosmWasm host `execute_msg`
  (WasmMsg-shaped). Real CosmWasm submessage encoding, reply handling, and
  Gate G1a M3/M4 are **not** started. Do not treat as production CosmWasm CPI. -/
  partial def lowerCosmWasmExecuteMsg (ctx : Ctx) (env : LocalTypes) (target method : Expr)
      (args : Array Expr) : Except EmitError (Array Insn × ValueType) :=
    lowerHostBridgeRemoteInvoke ctx env target method args "execute_msg" "CosmWasm"

  partial def lowerNearPromiseCreate (ctx : Ctx) (env : LocalTypes) (target method : Expr)
      (args : Array Expr) (deposit : Expr) : Except EmitError (Array Insn × ValueType) := do
    if ctx.crosscallStrings.isEmpty then
      err "EmitWat: NEAR crosscall requires `module.nearCrosscallStrings` to be populated"
    let account ← resolveCrosscallStringRef ctx target "target account id"
    let methodSi ← resolveCrosscallStringRef ctx method "method name"
    let (argBuildInsns, argsPtr, argsLenMarker) ←
      lowerCrosscallArgsForMethod ctx env methodSi.str args
    let depositInsns ← lowerNearDeposit ctx env "NEAR crosscall" deposit
    let argsLenInsns := crosscallArgsLenInsns args argsLenMarker
    let argsPtrInsns := crosscallArgsPtrInsns argsPtr
    .ok (argBuildInsns ++
      stringInfoLenPtrInsns account ++
      stringInfoLenPtrInsns methodSi ++
      argsLenInsns ++ argsPtrInsns ++ depositInsns ++ #[
      .i64Const crosscallDefaultGas,
      .call "promise_create"
    ], .u64)

  partial def lowerCrosscallInvoke (ctx : Ctx) (env : LocalTypes) (target method : Expr) (args : Array Expr)
      (deposit : Expr) : Except EmitError (Array Insn × ValueType) :=
    match ctx.bridge with
    | .soroban => lowerSorobanInvoke ctx env target method args
    | .cosmWasm => lowerCosmWasmExecuteMsg ctx env target method args
    | .near => lowerNearPromiseCreate ctx env target method args deposit

  partial def lowerNearPromiseThen (ctx : Ctx) (env : LocalTypes) (parentPromise callbackMethod : Expr)
      (args : Array Expr) (deposit : Expr) : Except EmitError (Array Insn × ValueType) := do
    if ctx.crosscallStrings.isEmpty then
      err "EmitWat: NEAR promise_then requires `module.nearCrosscallStrings` for callback method names"
    let (parentInsns, parentType) ← lowerExpr ctx env parentPromise
    if parentType != .u64 then
      err s!"EmitWat: NEAR promise_then parent expected `U64` promise id, got `{parentType.name}`"
    let methodSi ← resolveCrosscallStringRef ctx callbackMethod "callback method name"
    let (argBuildInsns, argsPtr, argsLenMarker) ← lowerCrosscallArgsJson ctx env args
    let depositInsns ← lowerNearDeposit ctx env "NEAR promise_then" deposit
    let argsLenInsns := crosscallArgsLenInsns args argsLenMarker
    let argsPtrInsns := crosscallArgsPtrInsns argsPtr
    .ok (parentInsns ++ argBuildInsns ++ #[
      .call promiseCurrentAccountName,
      .i32Const CTX_BUF, .plain "i64.extend_i32_u"
    ] ++ stringInfoLenPtrInsns methodSi ++ argsLenInsns ++ argsPtrInsns ++ depositInsns ++ #[
      .i64Const crosscallDefaultGas,
      .call "promise_then"
    ], .u64)

  partial def lowerNearPromiseResultIndex (ctx : Ctx) (env : LocalTypes) (index : Expr) :
      Except EmitError (Array Insn) :=
    lowerU32OrU64AsI64 ctx env "NEAR promise_result index" index

  partial def lowerExpr (ctx : Ctx) (env : LocalTypes) (e : Expr)
      : Except EmitError (Array Insn × ValueType) :=
    match e with
    | .literal (.u32 n) => .ok (#[.const .i32 (toString n)], .u32)
    | .literal (.u64 n) => .ok (#[.const .i64 (toString n)], .u64)
    | .literal (.u128 n) =>
      -- U128 literal: split into low 64 bits and high 64 bits.
      -- For Phase 1, we only support values that fit in 64 bits (high = 0).
      -- Full U128 literal support requires data segment or multi-word construction.
      if n < 18446744073709551616 then
        .ok (#[.i64Const n, .i64Const 0], .u128)
      else
        err "EmitWat: U128 literal exceeds U64 range (full U128 literal lowering not yet supported)"
    | .literal (.bool b) => .ok (#[.const .i32 (if b then "1" else "0")], .bool)
    | .literal (.hash4 a b c d) => .ok (#[.i64Const a, .i64Const b, .i64Const c, .i64Const d, .call hashMakeName], .hash)
    | .literal (.bytes _) =>
      err "EmitWat: bytes literal lowering not yet supported (use memoryArrayNew + store)"
    | .literal (.string _) =>
      err "EmitWat: string literal lowering not yet supported (use memoryArrayNew + store)"
    | .hashValue a b c d => do
      let (ia, ta) ← lowerExpr ctx env a
      let (ib, tb) ← lowerExpr ctx env b
      let (ic, tc) ← lowerExpr ctx env c
      let (id_, td) ← lowerExpr ctx env d
      if !(ta == .u64 && tb == .u64 && tc == .u64 && td == .u64) then err "EmitWat: hashValue expects four U64 limbs"
      else .ok (ia ++ ib ++ ic ++ id_ ++ #[.call hashMakeName], .hash)
    | .hash preimage => do
      let (is, t) ← lowerExpr ctx env preimage
      if t != .hash then err s!"EmitWat: hash preimage expected Hash, got `{t.name}`"
      else .ok (is ++ #[.call hashSName], .hash)
    | .hashTwoToOne l r => do
      let (la, ta) ← lowerExpr ctx env l
      let (lb, tb) ← lowerExpr ctx env r
      if !(ta == .hash && tb == .hash) then err "EmitWat: hash_two_to_one expects two Hash operands"
      else .ok (la ++ lb ++ #[.call hashTwoName], .hash)
    | .ecrecover _ _ _ _ | .eip712PermitDigest _ _ _ _ _ _ =>
      err "EmitWat: ecrecover / EIP-712 permit require crypto.ecrecover (EVM-only)"
    | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
      err "EmitWat: crosscallAbiPacked (compile-time ABI Call[]) is EVM-only"
    | .local name =>
      match lookupLocal? env name with
      | some t => .ok (#[.localGet name], t)
      | none => err s!"EmitWat: unknown local `{name}`"
    | .add a b _ => lowerAddSubMul ctx env "add" a b
    | .sub a b _ => lowerAddSubMul ctx env "sub" a b
    | .mul a b _ => lowerAddSubMul ctx env "mul" a b
    | .div a b => lowerNumBin ctx env "div_u" a b
    | .mod a b => lowerNumBin ctx env "rem_u" a b
    | .bitAnd a b => lowerNumBin ctx env "and" a b
    | .bitOr a b => lowerNumBin ctx env "or" a b
    | .bitXor a b => lowerNumBin ctx env "xor" a b
    | .shiftLeft a b => lowerNumBin ctx env "shl" a b
    | .shiftRight a b => lowerNumBin ctx env "shr_u" a b
    | .pow a b => do
      let (la, lb, t) ← lowerMatchingNumericOperands ctx env "pow" a b
      if t == .u128 then
        err "EmitWat: U128 pow not yet supported (use U64 or U32)"
      else
        .ok (la ++ lb ++ #[.call (powName t)], t)
    | .eq a b => lowerCmp ctx env "eq" a b
    | .ne a b => lowerCmp ctx env "ne" a b
    | .lt a b => lowerCmp ctx env "lt_u" a b
    | .le a b => lowerCmp ctx env "le_u" a b
    | .gt a b => lowerCmp ctx env "gt_u" a b
    | .ge a b => lowerCmp ctx env "ge_u" a b
    | .boolAnd a b => lowerBoolBin ctx env "and" a b
    | .boolOr a b => lowerBoolBin ctx env "or" a b
    | .boolNot a => do
      let (is, t) ← lowerExpr ctx env a
      if t != .bool then err s!"EmitWat: boolean not operand expected Bool, got `{t.name}`"
      else .ok (is ++ #[.plain "i32.eqz"], .bool)
    | .cast value target => lowerCast ctx env value target
    | .nativeValue =>
      -- NEAR `attached_deposit(balance_ptr)` writes u128 LE at ptr (near-sys).
      -- IR models nativeValue as U64: use the low 64 bits (scenario deposits
      -- stay well below 2^64). Full U128 nativeValue is a future enhancement.
      .ok (#[.i64Const RET_BUF, .call "attached_deposit",
             .i32Const RET_BUF, .load "i64.load" 0], .u64)
    | .effect (.storageScalarRead id) =>
      match findScalarState? ctx.scalars id with
      | some s => .ok (storageScalarReadInsns s)
      | none => err s!"EmitWat: unknown scalar state `{id}`"
    | .effect (.storageMapGet id key) => lowerMapGet ctx env id key
    | .effect (.storageMapContains id key) => lowerMapContains ctx env id key
    | .effect (.contextRead field) =>
      match buildContextExprPlan field with
      | .ok plan => lowerContextExprPlan plan
      | .error planErr => err s!"EmitWat: {planErr.message}"
    | .effect (.storageMapSet id key value) | .effect (.storageMapInsert id key value) =>
      lowerMapWrite ctx env id key value
    | .effect (.storageMapDelete id key) =>
      lowerMapDelete ctx env id key
    | .effect (.storageArrayRead id index) => lowerStorageArrayRead ctx env id index
    | .effect (.storageArrayStructFieldRead id index fieldName) =>
      lowerArrayStructFieldRead ctx env id index fieldName
    | .effect (.storageStructFieldRead id fieldName) =>
      lowerScalarStructFieldRead ctx id fieldName
    | .effect (.storagePathRead id path) =>
      lowerStoragePathRead ctx env id path
    | .arrayLit elementType values => do
      let elementInsns ← appendInsnChunksM values fun v => do
        let (is, t) ← lowerExpr ctx env v
        if t != elementType then err s!"EmitWat: arrayLit element expected `{elementType.name}`, got `{t.name}`"
        else .ok is
      .ok (elementInsns ++ #[.call (arrayLitName elementType values.size)],
            .fixedArray elementType values.size)
    | .arrayGet array index => do
      let (pa, ta) ← lowerExpr ctx env array
      let (pi, ti) ← lowerExpr ctx env index
      match ta with
      | .fixedArray elemType _ =>
        if !(ti == .u32 || ti == .u64) then
          err s!"EmitWat: arrayGet index must be U32/U64, got `{ti.name}`"
        else do
          let conv := if ti == .u64 then #[.plain "i32.wrap_i64"] else #[]
          .ok (pa ++ pi ++ conv ++ #[.i32Const (scalarWidth elemType), .plain "i32.mul",
                .plain "i32.add", .load (loadOpFor elemType) 0], elemType)
      | _ => err s!"EmitWat: arrayGet expected an array value, got `{ta.name}`"
    | .memoryArrayNew _ _ =>
      err "EmitWat: memory arrays are not supported by wasm-near IR v0"
    | .memoryArrayLength _ =>
      err "EmitWat: memory arrays are not supported by wasm-near IR v0"
    | .memoryArrayGet _ _ =>
      err "EmitWat: memory arrays are not supported by wasm-near IR v0"
    | .structLit typeName fields => do
      match findStruct? ctx.structs typeName with
      | none => err s!"EmitWat: unknown struct `{typeName}`"
      | some s =>
        let argInsns ← appendInsnChunksM s.fields fun f =>
          match fields.find? (fun (n, _) => n == f.id) with
          | none => err s!"EmitWat: structLit `{typeName}` missing field `{f.id}`"
          | some (_, vexpr) => do
            let (vis, vt) ← lowerExpr ctx env vexpr
            if vt != f.type then
              err s!"EmitWat: struct field `{typeName}.{f.id}` expected `{f.type.name}`, got `{vt.name}`"
            else .ok vis
        .ok (argInsns ++ #[.call (structLitName typeName)],
              .structType typeName)
    | .field base fieldName => do
      let (pb, tb) ← lowerExpr ctx env base
      match tb with
      | .structType typeName =>
        match findStruct? ctx.structs typeName with
        | none => err s!"EmitWat: unknown struct `{typeName}`"
        | some s =>
          match structFieldOffset? s fieldName, structFieldType? s fieldName with
          | some off, some ft =>
            .ok (pb ++ #[.i32Const off, .plain "i32.add", .load (loadOpFor ft) 0], ft)
          | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
      | _ => err s!"EmitWat: field access expects a struct value, got `{tb.name}`"
    | .crosscallInvoke target method args =>
      lowerCrosscallInvoke ctx env target method args (.literal (.u64 0))
    | .crosscallInvokeValueTyped target method callValue args _ =>
      lowerCrosscallInvoke ctx env target method args callValue
    | .crosscallInvokeTyped _ _ _ _ =>
      err crosscallTypedUnsupportedMessage
    | .crosscallInvokeStaticTyped _ _ _ _ =>
      err (crosscallEvmOnlyMessage "crosscallInvokeStaticTyped")
    | .crosscallInvokeDelegateTyped _ _ _ _ =>
      err (crosscallEvmOnlyMessage "crosscallInvokeDelegateTyped")
    | .crosscallCreate _ _ =>
      err (crosscallEvmOnlyMessage "crosscallCreate")
    | .crosscallCreate2 _ _ _ =>
      err (crosscallEvmOnlyMessage "crosscallCreate2")
    | .crosscallNamed _ _ _ _ =>
      err "EmitWat: crosscallNamed (named-callee cross-program call) is a ZK-lane construct; not lowered on Wasm hosts — use crosscallInvoke* / NEAR promise forms"
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
      if ctx.bridge == .soroban then err sorobanNearPromiseUnsupportedMessage
      else lowerNearCrosscallInvokePool ctx env accountIndex methodId args deposit
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
      if ctx.bridge == .soroban then err sorobanNearPromiseUnsupportedMessage
      else lowerNearPromiseThen ctx env parentPromise callbackMethod args deposit
    | .nearPromiseResultsCount =>
      if ctx.bridge == .soroban then err sorobanNearPromiseUnsupportedMessage
      else .ok (#[.call "promise_results_count"], .u64)
    | .nearPromiseResultStatus index =>
      if ctx.bridge == .soroban then err sorobanNearPromiseUnsupportedMessage
      else do
        let indexInsns ← lowerNearPromiseResultIndex ctx env index
        .ok (indexInsns ++ #[.i64Const 0, .call "promise_result"], .u64)
    | .nearPromiseResultU64 index =>
      if ctx.bridge == .soroban then err sorobanNearPromiseUnsupportedMessage
      else do
        let indexInsns ← lowerNearPromiseResultIndex ctx env index
        .ok (indexInsns ++ #[.call promiseResultU64Name], .u64)
    | _ => err "EmitWat: this expression form is not yet supported"

  partial def lowerMatchingNumericOperands (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if !(isNumeric ta && ta == tb) then
      err s!"EmitWat: `{op}` expected matching U32/U64/U128 operands, got `{ta.name}`/`{tb.name}`"
    else
      .ok (la, lb, ta)

  partial def lowerNumBin (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, lb, t) ← lowerMatchingNumericOperands ctx env op a b
    .ok (la ++ lb ++ #[.plain (widthOf t ++ "." ++ op)], t)

  /-- Lower add/sub/mul for U32/U64 (native Wasm ops) or U128 (dedicated helper calls). -/
  partial def lowerAddSubMul (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, lb, t) ← lowerMatchingNumericOperands ctx env op a b
    match t with
    | .u128 =>
      let helperName := match op with
        | "add" => u128AddName
        | "sub" => u128SubName
        | "mul" => u128MulName
        | _ => ""
      if helperName.isEmpty then
        err s!"EmitWat: U128 operation `{op}` not supported"
      else
        .ok (la ++ lb ++ #[.call helperName], .u128)
    | _ =>
      .ok (la ++ lb ++ #[.plain (widthOf t ++ "." ++ op)], t)

  partial def lowerCmp (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if ta != tb then err s!"EmitWat: `{op}` expected matching operand types, got `{ta.name}`/`{tb.name}`"
    else if ta == .hash && op == "eq" then .ok (la ++ lb ++ #[.call hashEqName], .bool)
    else if ta == .hash && op == "ne" then .ok (la ++ lb ++ #[.call hashEqName, .plain "i32.eqz"], .bool)
    else if ta == .u128 && op == "eq" then .ok (la ++ lb ++ #[.call u128EqName], .bool)
    else if ta == .u128 && op == "ne" then .ok (la ++ lb ++ #[.call u128EqName, .plain "i32.eqz"], .bool)
    else if ta == .u128 then
      err s!"EmitWat: U128 comparison `{op}` not yet supported (only eq/ne)"
    else match ta with
      | .fixedArray elemType len =>
        if op == "eq" then .ok (la ++ lb ++ #[.call (arrEqName elemType len)], .bool)
        else if op == "ne" then .ok (la ++ lb ++ #[.call (arrEqName elemType len), .plain "i32.eqz"], .bool)
        else err s!"EmitWat: `{op}` not supported on array values"
      | _ => .ok (la ++ lb ++ #[.plain (widthOf ta ++ "." ++ op)], .bool)

  partial def lowerBoolBin (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if !(ta == .bool && tb == .bool) then err s!"EmitWat: boolean `{op}` expected Bool operands"
    else .ok (la ++ lb ++ #[.plain ("i32." ++ op)], .bool)

  partial def lowerCast (ctx : Ctx) (env : LocalTypes) (value : Expr) (target : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    let (is, src) ← lowerExpr ctx env value
    let extra ←
      match src, target with
      | .u32, .u64 => .ok #[.plain "i64.extend_i32_u"]
      | .u64, .u32 => .ok #[.plain "i32.wrap_i64"]
      | .u32, .bool => .ok #[.i32Const 0, .plain "i32.ne"]
      | .u64, .bool => .ok #[.i64Const 0, .plain "i64.ne"]
      | .bool, .u32 => .ok #[]
      | .bool, .u64 => .ok #[.plain "i64.extend_i32_u"]
      | .u32, .u128 => .ok #[.plain "i64.extend_i32_u", .i64Const 0]
      | .u64, .u128 => .ok #[.i64Const 0]
      | .u128, .u64 => .ok #[]  -- truncate: drop high 64 bits
      | .u128, .u32 => .ok #[.plain "i32.wrap_i64"]  -- truncate: wrap low 64 to i32
      | .u128, .bool => .ok #[.i64Const 0, .plain "i64.ne", .plain "i32.wrap_i64"]
      | _, _ => err s!"EmitWat: cast from `{src.name}` to `{target.name}` is not supported"
    .ok (is ++ extra, target)

  partial def lowerMapKeyTyped (ctx : Ctx) (env : LocalTypes) (expected : ValueType) (key : Expr)
      : Except EmitError (Array Insn) := do
    let (is, t) ← lowerExpr ctx env key
    if t != expected then err s!"EmitWat: map key expected {expected.name}, got `{t.name}`"
    else .ok is

  partial def lowerMapKeyU64 (ctx : Ctx) (env : LocalTypes) (key : Expr)
      : Except EmitError (Array Insn) :=
    lowerMapKeyTyped ctx env .u64 key

  partial def lowerMapKeyHash (ctx : Ctx) (env : LocalTypes) (key : Expr)
      : Except EmitError (Array Insn) :=
    lowerMapKeyTyped ctx env .hash key

  partial def lowerMapKeyFor (ctx : Ctx) (env : LocalTypes) (keyType : ValueType) (key : Expr)
      : Except EmitError (Array Insn) :=
    if keyType == .hash then lowerMapKeyHash ctx env key else lowerMapKeyU64 ctx env key

  partial def lowerMapGet (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← mapReadStateInfo ctx.maps id
    let readCall ← mapReadCall mapInfo id
    let keyInsns ← lowerMapKeyFor ctx env mapInfo.keyType key
    .ok (mapReadValueInsns mapInfo keyInsns readCall)

  /-- Nested map read: Map<K1, Map<K2, V>>. Builds compound key:
      mapBuildkey writes prefix + key1 to MAPKEY_BUF, then we manually
      append key2 bytes at MAPKEY_BUF + prefixLen + 8.
      Then call storage_read with extended key length = prefixLen + 16. -/
  partial def lowerNestedMapGet (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← nestedMapReadStateInfo ctx.maps id
    let key1Insns ← lowerMapKeyU64 ctx env key1
    let key2Insns ← lowerMapKeyU64 ctx env key2
    .ok (nestedMapReadValueInsns mapInfo key1Insns key2Insns)

  partial def lowerMapContains (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← mapContainsStateInfo ctx.maps id
    let containsCall ← mapContainsCall mapInfo
    let keyInsns ← lowerMapKeyFor ctx env mapInfo.keyType key
    .ok (mapContainsValueInsns mapInfo keyInsns containsCall)

  partial def lowerMapWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← mapWriteStateInfo ctx.maps id
    let writeCall ← mapWriteCall mapInfo
    let keyInsns ← lowerMapKeyFor ctx env mapInfo.keyType key
    mapWriteValueInsns mapInfo id keyInsns valueInsns writeCall valueType

  partial def lowerMapWrite (ctx : Ctx) (env : LocalTypes) (id : String) (key value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerMapWriteValue ctx env id key vis vt

  partial def lowerMapDelete (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← mapWriteStateInfo ctx.maps id
    let deleteCall ← mapDeleteCall mapInfo
    let keyInsns ← lowerMapKeyFor ctx env mapInfo.keyType key
    .ok (mapDeleteValueInsns mapInfo keyInsns deleteCall)

  /-- Nested map write with pre-evaluated value instructions. -/
  partial def lowerNestedMapWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← nestedMapWriteStateInfo ctx.maps id valueType
    let key1Insns ← lowerMapKeyU64 ctx env key1
    let key2Insns ← lowerMapKeyU64 ctx env key2
    .ok (nestedMapWriteValueInsns mapInfo key1Insns key2Insns valueInsns)

  /-- Nested map write: Map<K1, Map<K2, V>>. -/
  partial def lowerNestedMapWrite (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerNestedMapWriteValue ctx env id key1 key2 vis vt

  partial def lowerStorageArrayRead (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let arrayInfo ← storageArrayStateInfo ctx.maps id
    let indexInsns ← lowerMapKeyU64 ctx env index
    .ok (storageArrayReadInsns arrayInfo indexInsns)

  partial def lowerStorageArrayWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    let arrayInfo ← storageArrayWriteStateInfo ctx.maps id valueType
    let indexInsns ← lowerMapKeyU64 ctx env index
    .ok (storageArrayWriteInsns arrayInfo indexInsns valueInsns)

  partial def lowerStorageArrayWrite (ctx : Ctx) (env : LocalTypes) (id : String) (index value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerStorageArrayWriteValue ctx env id index vis vt

  partial def lowerScalarStructFieldRead (ctx : Ctx) (id fieldName : String)
      : Except EmitError (Array Insn × ValueType) := do
    let stateInfo ← scalarStructStateInfo ctx.scalars ctx.structs id "storageStructFieldRead"
    let (off, ft) ← structStorageFieldInfo stateInfo.structDecl stateInfo.typeName fieldName "scalar"
    .ok (scalarStructFieldReadInsns stateInfo.state stateInfo.structDecl off ft)

  partial def lowerScalarStructFieldWriteValue (ctx : Ctx) (id fieldName : String)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn) := do
    let stateInfo ← scalarStructStateInfo ctx.scalars ctx.structs id "storageStructFieldWrite"
    let (off, ft) ← structStorageFieldInfo stateInfo.structDecl stateInfo.typeName fieldName "scalar"
    if valueType != ft then
      err s!"EmitWat: struct field write `{id}.{fieldName}` expected `{ft.name}`, got `{valueType.name}`"
    else
      .ok (scalarStructFieldWriteInsns stateInfo.state stateInfo.structDecl off ft valueInsns)

  partial def lowerScalarStructFieldWrite (ctx : Ctx) (env : LocalTypes) (id fieldName : String) (value : Expr)
      : Except EmitError (Array Insn) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerScalarStructFieldWriteValue ctx id fieldName vis vt

  partial def lowerArrayStructFieldRead (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String)
      : Except EmitError (Array Insn × ValueType) := do
    let mapInfo ← arrayStructMapInfo ctx.maps id
    let structInfo ← arrayStructInfo ctx.structs mapInfo "storageArrayStructFieldRead"
    let (off, ft) ← structStorageFieldInfo structInfo.structDecl structInfo.typeName fieldName "array"
    let kis ← lowerMapKeyU64 ctx env index
    .ok (arrayStructFieldReadInsns structInfo.mapInfo structInfo.structDecl kis #[.call mapBuildkeyName] off ft)

  partial def lowerArrayStructFieldWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn) := do
    let mapInfo ← arrayStructMapInfo ctx.maps id
    requireDuplicableExpr index "EmitWat: storage array struct field path index must be a pure expression until key temporaries are lowered"
    let structInfo ← arrayStructInfo ctx.structs mapInfo "storageArrayStructFieldWrite"
    let (off, ft) ← structStorageFieldInfo structInfo.structDecl structInfo.typeName fieldName "array"
    if valueType != ft then
      err s!"EmitWat: array struct field write `{id}[].{fieldName}` expected `{ft.name}`, got `{valueType.name}`"
    else do
      let readKey ← lowerMapKeyU64 ctx env index
      let writeKey ← lowerMapKeyU64 ctx env index
      .ok (arrayStructFieldWriteInsns structInfo.mapInfo structInfo.structDecl readKey writeKey
        #[.call mapBuildkeyName] valueInsns off ft)

  partial def lowerArrayStructFieldWrite (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String) (value : Expr)
      : Except EmitError (Array Insn) := do
    requireDuplicableExpr value "EmitWat: storageArrayStructFieldWrite value must be a pure expression while STRUCT_BUF is the field patch buffer"
    let (vis, vt) ← lowerExpr ctx env value
    lowerArrayStructFieldWriteValue ctx env id index fieldName vis vt

  partial def lowerStoragePathRead (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment)
      : Except EmitError (Array Insn × ValueType) := do
    match path.toList with
    | [.mapKey key] => lowerMapGet ctx env id key
    | [.index index] => lowerStorageArrayRead ctx env id index
    | [.field fieldName] => lowerScalarStructFieldRead ctx id fieldName
    | [.index index, .field fieldName] => lowerArrayStructFieldRead ctx env id index fieldName
    | [.mapKey key1, .mapKey key2] =>
      -- Nested map: Map<K1, Map<K2, V>>. Encode as compound key:
      -- prefix ++ key1_bytes ++ key2_bytes in MAPKEY_BUF.
      lowerNestedMapGet ctx env id key1 key2
    | _ => err "EmitWat: storagePathRead supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def lowerStoragePathWrite (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment) (value : Expr)
      : Except EmitError (Array Insn) := do
    match path.toList with
    | [.mapKey key] => do
      let (is, _) ← lowerMapWrite ctx env id key value
      .ok (dropResultInsns is)
    | [.index index] => do
      let (is, _) ← lowerStorageArrayWrite ctx env id index value
      .ok (dropResultInsns is)
    | [.field fieldName] => do
      requireDuplicableExpr value "EmitWat: storagePathWrite field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      lowerScalarStructFieldWrite ctx env id fieldName value
    | [.index index, .field fieldName] =>
      lowerArrayStructFieldWrite ctx env id index fieldName value
    | [.mapKey key1, .mapKey key2] => do
      let (is, _) ← lowerNestedMapWrite ctx env id key1 key2 value
      .ok (dropResultInsns is)
    | _ => err "EmitWat: storagePathWrite supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def lowerStoragePathAssignOp (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment)
      (op : AssignOp) (value : Expr) : Except EmitError (Array Insn) := do
    match path.toList with
    | [.mapKey key] => do
      requireDuplicableExpr key "EmitWat: storagePathAssignOp mapKey must be a pure expression until key temporaries are lowered"
      let (currentInsns, currentType) ← lowerMapGet ctx env id key
      let currentType ← storagePathAssignOpTargetType "map values" currentType
      let (valueInsns, valueType) ← lowerExpr ctx env value
      let computed ← storagePathAssignOpValueInsns op currentInsns currentType valueInsns valueType
      let (writeInsns, _) ← lowerMapWriteValue ctx env id key computed currentType
      .ok (dropResultInsns writeInsns)
    | [.index index] => do
      requireDuplicableExpr index "EmitWat: storagePathAssignOp index must be a pure expression until key temporaries are lowered"
      let (currentInsns, currentType) ← lowerStorageArrayRead ctx env id index
      let currentType ← storagePathAssignOpTargetType "array values" currentType
      let (valueInsns, valueType) ← lowerExpr ctx env value
      let computed ← storagePathAssignOpValueInsns op currentInsns currentType valueInsns valueType
      let (writeInsns, _) ← lowerStorageArrayWriteValue ctx env id index computed currentType
      .ok (dropResultInsns writeInsns)
    | [.field fieldName] => do
      requireDuplicableExpr value "EmitWat: storagePathAssignOp field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      let (currentInsns, currentType) ← lowerScalarStructFieldRead ctx id fieldName
      let currentType ← storagePathAssignOpTargetType "struct fields" currentType
      let (valueInsns, valueType) ← lowerExpr ctx env value
      let computed ← storagePathAssignOpValueInsns op currentInsns currentType valueInsns valueType
      lowerScalarStructFieldWriteValue ctx id fieldName computed currentType
    | [.index index, .field fieldName] => do
      requireDuplicableExpr value "EmitWat: storagePathAssignOp index+field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      let (currentInsns, currentType) ← lowerArrayStructFieldRead ctx env id index fieldName
      let currentType ← storagePathAssignOpTargetType "array struct fields" currentType
      let (valueInsns, valueType) ← lowerExpr ctx env value
      let computed ← storagePathAssignOpValueInsns op currentInsns currentType valueInsns valueType
      lowerArrayStructFieldWriteValue ctx env id index fieldName computed currentType
    | [.mapKey key1, .mapKey key2] => do
      let (currentInsns, currentType) ← lowerNestedMapGet ctx env id key1 key2
      let currentType ← storagePathAssignOpTargetType "nested map values" currentType
      let (valueInsns, valueType) ← lowerExpr ctx env value
      let computed ← storagePathAssignOpValueInsns op currentInsns currentType valueInsns valueType
      let (writeInsns, _) ← lowerNestedMapWriteValue ctx env id key1 key2 computed currentType
      .ok (dropResultInsns writeInsns)
    | _ => err "EmitWat: storagePathAssignOp supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

end

def lowerReturn (ctx : Ctx) (env : LocalTypes) (expected : ValueType) (e : Expr)
    : Except EmitError (Array Insn) := do
  let (is, t) ← lowerExpr ctx env e
  let aggBytes? ← borshReturnPayloadBytes ctx.structs expected
  returnInsnsForLoweredExpr expected e is t ctx.bridge ctx.packScalars aggBytes?

partial def lowerEventEmit (ctx : Ctx) (env : LocalTypes) (name : String) (fields : Array (String × Expr))
    : Except EmitError (Array Insn) := do
  let headerKey := eventHeaderPoolString name
  let some nameSi ← pure (findString? ctx.strings headerKey)
    | err s!"EmitWat: event header `{headerKey}` not in string pool"
  let header := evtHeaderInsns nameSi
  let fieldInsns ← appendInsnChunksM fields fun f => do
    let (fname, vexpr) := f
    let fieldKey := eventFieldPoolString fname
    let some fsi ← pure (findString? ctx.strings fieldKey)
      | err s!"EmitWat: event field key `{fieldKey}` not in string pool"
    let (vis, vt) ← lowerExpr ctx env vexpr
    evtFieldInsns fname fsi vis vt
  .ok (header ++ fieldInsns ++ evtFooterInsns)

partial def lowerStmt (ctx : Ctx) (env : LocalTypes) (returns : ValueType)
    (s : Statement) : Except EmitError (Array Insn) :=
  match s with
  | .letBind name t e | .letMutBind name t e => do
    let (is, te) ← lowerExpr ctx env e
    localLetBindInsns name t is te
  | .assign (.local name) e => do
    let (is, _) ← lowerExpr ctx env e
    localAssignInsns env name is
  | .assign _ _ => err "EmitWat: assignment target must be a local"
  | .assignOp (.local name) op e => do
    let localType ← localAssignOpTargetType env name
    let (is, t) ← lowerExpr ctx env e
    localAssignOpInsns name op localType is t
  | .assignOp _ _ _ => err "EmitWat: compound assignment target must be a local"
  | .effect (.storageScalarWrite id e) => do
    let s ← storageScalarStateInfo ctx.scalars id
    let (is, t) ← lowerExpr ctx env e
    storageScalarWriteInsns ctx.structs s id is t
  | .effect (.storageStructFieldWrite id fieldName value) => do
    lowerScalarStructFieldWrite ctx env id fieldName value
  | .effect (.storagePathWrite id path value) => do
    lowerStoragePathWrite ctx env id path value
  | .effect (.storagePathAssignOp id path op value) => do
    lowerStoragePathAssignOp ctx env id path op value
  | .effect (.storageScalarAssignOp id op value) => do
    let s ← storageScalarStateInfo ctx.scalars id
    let _ ← storageScalarAssignOpTargetType s id
    let (vis, vt) ← lowerExpr ctx env value
    storageScalarAssignOpInsns s id op vis vt
  | .effect (.storageMapSet id key value) | .effect (.storageMapInsert id key value) => do
    let (is, _) ← lowerMapWrite ctx env id key value
    .ok (dropResultInsns is)
  | .effect (.storageMapDelete id key) => do
    let (is, _) ← lowerMapDelete ctx env id key
    .ok (dropResultInsns is)
  | .effect (.storageArrayWrite id index value) => do
    let (is, _) ← lowerStorageArrayWrite ctx env id index value
    .ok (dropResultInsns is)
  | .effect (.storageArrayStructFieldWrite id index fieldName value) => do
    lowerArrayStructFieldWrite ctx env id index fieldName value
  | .effect (.eventEmit name fields) => lowerEventEmit ctx env name fields
  | .effect (.eventEmitIndexed name indexedFields dataFields) =>
      -- NEAR events are log_utf8 strings; indexed/data distinction is EVM-specific.
      -- Flatten all fields into a single JSON event log (same as non-indexed).
      lowerEventEmit ctx env name (indexedFields ++ dataFields)
  | .assert cond _ errorRef? => do
    let (is, t) ← lowerExpr ctx env cond
    if t != .bool then err "EmitWat: assert condition must be Bool"
    else
      let failInsns := assertFailInsns ctx.panics errorRef?
      .ok (is ++ #[.plain "i32.eqz", .if_ { insns := failInsns } { insns := #[] }])
  | .assertEq a b _ errorRef? => do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if ta != tb then err "EmitWat: assertEq operands must share a type"
    else
      let eqInsn := match ta with
        | .hash => #[.call hashEqName]
        | .fixedArray elemType len => #[.call (arrEqName elemType len)]
        | _ => #[.plain (widthOf ta ++ ".eq")]
      let failInsns := assertFailInsns ctx.panics errorRef?
      .ok (la ++ lb ++ eqInsn ++ #[.plain "i32.eqz",
                            .if_ { insns := failInsns } { insns := #[] }])
  | .release name => do
    releaseInsns ctx env name
  | .return e => lowerReturn ctx env returns e
  | .ifElse cond thenBody elseBody => do
    let (cis, ct) ← lowerExpr ctx env cond
    if ct != .bool then err "EmitWat: if/else condition must be Bool"
    else do
      let thenInsns ← appendInsnChunksM thenBody fun s => lowerStmt ctx env returns s
      let elseInsns ← appendInsnChunksM elseBody fun s => lowerStmt ctx env returns s
      .ok (ifElseInsns cis thenInsns elseInsns)
  | .boundedFor indexName start stop body => do
    let bodyInsns ← appendInsnChunksM body fun s => lowerStmt ctx env returns s
    .ok (boundedForInsns indexName start stop bodyInsns)
  | _ => err "EmitWat: this statement form is not yet supported"

/-- **SPIKE / STUB (U7.2):** Soroban host auth when entrypoint reads caller/userId.
`require_auth_for_args` is **always authorised in the in-Lean interpreter** —
not real Env auth. Real Soroban authorization is future work. Authors still
write only `guard_owner` / `caller`. -/
def sorobanAuthPrologue (ctx : Ctx) (ep : Entrypoint) : Array Insn :=
  if ctx.bridge == ProofForge.Target.HostBridge.soroban &&
      ep.capabilities.any (fun c => c == ProofForge.Target.Capability.callerSender) then
    #[.i32Const 0, .i32Const 0, .call "require_auth_for_args", .drop]
  else
    #[]

def lowerEntrypoint (ctx : Ctx) (ep : Entrypoint) : Except EmitError Func := do
  let bodyLocals ← collectLocals ep.body
  let (paramPrologue, paramLocals) ← loadParams ctx.structs ep.params ctx.bridge
  let allLocalTypes : LocalTypes :=
    (ep.params.map (fun (n, t) => { name := n, vt := t : LBind })) ++ bodyLocals
  let locals := paramLocals ++ bodyLocals.map (fun b => { name := b.name, type := wasmTypeOf b.vt : Local })
  let bodyInsns ← appendInsnChunksM ep.body fun s => lowerStmt ctx allLocalTypes ep.returns s
  let resetPrefix : Array Insn :=
    if ctx.allocator.usesEntryReset then
      #[.i32Const ctx.allocator.heapBase, .globalSet arrPtrGlobal]
    else #[]
  -- require_auth is Soroban-only.
  let authPrefix :=
    if ctx.bridge == ProofForge.Target.HostBridge.soroban then
      sorobanAuthPrologue ctx ep
    else
      #[]
  let packPrefix :=
    if !ctx.packScalars then #[]
    else packBeginInsns
  let packSuffix := if ctx.packScalars then packFlushInsns else #[]
  .ok {
    name := ep.name
    locals := locals
    body := {
      insns := resetPrefix ++ authPrefix ++ packPrefix ++ paramPrologue ++ bodyInsns ++ packSuffix
    }
    exportName := ep.name
  }

/- Core lowering body once the surface `ModulePlan` and the data-layout `Ctx`
have been derived. Exposed so the plan-driven path
(`ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan`) can reuse the
exact same body without re-deriving the layout inline. This mirrors Solana's
`lowerModuleCoreWithSeed` extraction in `SbpfAsm.lean`. The body is a pure
function of `(mod, modulePlan, ctx)` — it does not re-derive any layout. -/
def lowerModuleCoreWithCtx (mod : ProofForge.IR.Module) (modulePlan : ModulePlan)
    (ctx : Ctx) : Except EmitError ProofForge.Compiler.Wasm.Module := do
  let entryFuncs ← mod.entrypoints.mapM (lowerEntrypoint ctx)
  let hasPanic := !ctx.panics.isEmpty
  let imports := importsForModulePlan modulePlan mod.allocator hasPanic ctx.bridge
  let funcs := helperFuncsForModulePlan modulePlan mod ctx entryFuncs
  let globals := globalsForModulePlan modulePlan mod.allocator ctx.packScalars
  .ok { imports := imports, globals := globals, funcs := funcs,
        memory := some { min := 1 },
        dataSegments := dataSegmentsForModulePlan modulePlan ctx }

def lowerModule (mod : ProofForge.IR.Module)
    (bridge : ProofForge.Target.HostBridge := ProofForge.Target.HostBridge.near)
    (peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity) :
    Except EmitError ProofForge.Compiler.Wasm.Module := do
  -- C.6: deploy-time logical peer → host identity (before layout / string pool).
  let mod := ProofForge.Target.PeerMap.applyToModule mod peerMap
  if mod.allocator.isCosmWasmRegion && bridge != ProofForge.Target.HostBridge.cosmWasm then
    err "EmitWat: alloc.cosmwasm_region requires HostBridge.cosmWasm"
  -- Non-NEAR hosts: NEAR Promise host-extension constructors never lower.
  if bridge == ProofForge.Target.HostBridge.soroban ||
      bridge == ProofForge.Target.HostBridge.cosmWasm then
    if ProofForge.Backend.WasmHost.PortableCrosscall.moduleUsesPromiseExtension mod then
      err sorobanNearPromiseUnsupportedMessage
  let modulePlan ←
    match buildModulePlan mod with
    | .ok plan => pure plan
    | .error planErr => err s!"EmitWat: {planErr.message}"
  let ctx := loweringCtxForModule mod bridge
  validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  lowerModuleCoreWithCtx mod modulePlan ctx

def renderCheckedModule (mod : ProofForge.IR.Module)
    (bridge : ProofForge.Target.HostBridge := .near)
    (peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity) :
    Except EmitError String := do
  match ProofForge.IR.Ownership.checkModule mod with
  | .ok _ => pure ()
  | .error error => err s!"EmitWat: {error.render}"
  let m ← lowerModule mod bridge peerMap
  .ok (Printer.render m)

/-- Unified Wasm-family render entry.

* `.near` / `.soroban` / `.cosmWasm` — shared IR → WAT lowering via
  `HostBridge` (`storage_*` / `_get`/`_put` / `db_read`/`db_write`).
* The legacy CosmWasm Counter **spike** adapter (`WasmHost.CosmWasm.EmitWat`,
  region ABI + `interface_version_8`) remains available via CLI fixture emit
  (`--emit-counter-ir-cosmwasm` / `just cosmwasm-counter-smoke`) for
  `cosmwasm-check` goldens — not via product `contract_source` build.
-/
def renderModule (mod : ProofForge.IR.Module)
    (bridge : ProofForge.Target.HostBridge := .near)
    (peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity) :
    Except EmitError String := do
  checkCapabilities mod
  renderCheckedModule mod bridge peerMap

def renderModuleWithPlan
    (mod : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan)
    (bridge : ProofForge.Target.HostBridge := .near)
    (peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity) :
    Except EmitError String := do
  checkTargetPlan plan
  renderCheckedModule mod bridge peerMap


end ProofForge.Backend.WasmHost.EmitWat
