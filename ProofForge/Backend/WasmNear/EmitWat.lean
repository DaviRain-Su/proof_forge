/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EmitWat — lowers the portable IR (`ProofForge.IR.Contract`) to a `Wasm.Module`
that `Wasm.Printer` renders to WAT, deployable to the NEAR VM via `wat2wasm`.

Canonical wasm-near backend (decision D-023). Scope: scalar value types
U32/U64/Bool/Hash plus flat structs/fixed arrays — literals, locals,
arithmetic, bitwise, shift, comparisons, boolean ops, casts, scalar/map/array
storage, path storage, context, events, bounded control flow, explicit release,
and NEAR `value_return` for U32/U64/Bool/Hash.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.IR.Ownership
import ProofForge.Compiler.Wasm.AST
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Backend.WasmNear.Aggregate
import ProofForge.Backend.WasmNear.Assert
import ProofForge.Backend.WasmNear.ArrayHeap
import ProofForge.Backend.WasmNear.Capabilities
import ProofForge.Backend.WasmNear.Common
import ProofForge.Backend.WasmNear.Context
import ProofForge.Backend.WasmNear.Crosscall
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.Event
import ProofForge.Backend.WasmNear.ExprAnalysis
import ProofForge.Backend.WasmNear.Hash
import ProofForge.Backend.WasmNear.Imports
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.Locals
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Map
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.ModuleAssembly
import ProofForge.Backend.WasmNear.Params
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.Promise
import ProofForge.Backend.WasmNear.Return
import ProofForge.Backend.WasmNear.Scalar
import ProofForge.Backend.WasmNear.Statement
import ProofForge.Backend.WasmNear.Struct
import ProofForge.Backend.WasmNear.Types
import ProofForge.Target.Plan
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmNear.EmitWat

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Aggregate
open ProofForge.Backend.WasmNear.Assert
open ProofForge.Backend.WasmNear.ArrayHeap
open ProofForge.Backend.WasmNear.Capabilities
open ProofForge.Backend.WasmNear.Common
open ProofForge.Backend.WasmNear.Context
open ProofForge.Backend.WasmNear.Crosscall
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.Event
open ProofForge.Backend.WasmNear.ExprAnalysis
open ProofForge.Backend.WasmNear.Hash
open ProofForge.Backend.WasmNear.Imports
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.Locals
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Map
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.ModuleAssembly
open ProofForge.Backend.WasmNear.Params
open ProofForge.Backend.WasmNear.Promise
open ProofForge.Backend.WasmNear.Return
open ProofForge.Backend.WasmNear.Scalar
open ProofForge.Backend.WasmNear.Statement
open ProofForge.Backend.WasmNear.Struct
open ProofForge.Backend.WasmNear.Types

export ProofForge.Backend.WasmNear.Aggregate (
  arrayLitName arrEqName collectArrayLitsPathSegment collectArrayLitsPath
  collectArrayLitsExpr collectArrayLitsEffect collectStructLitsExpr
  collectStructLitsPathSegment collectStructLitsPath collectStructLitsEffect
  collectArrayLitsStmt dedupArrayLits moduleArrayLits arrLitFunc
  arrLitHelperFuncs arrEqFunc arrEqHelperFuncs structLitFunc
  collectStructLitsStmt dedupStrings moduleStructLitNames
  structLitHelperFuncs arrayLitFuncsForModulePlan arrayEqFuncsForModulePlan
  structLitFuncsForModulePlan aggregateHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmNear.Assert (
  assertFailInsns
)

export ProofForge.Backend.WasmNear.ArrayHeap (
  arrPtrGlobal arrFreeGlobal arrAllocName arrPtrGlobalDecl arrFreeGlobalDecl
  arrAllocFunc arrDeallocFunc modulePlanUsesArrHeap
  arrHeapHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmNear.Capabilities (
  emitWatCapabilities checkCapabilities checkTargetPlan
)

export ProofForge.Backend.WasmNear.Common (
  memcpyName memcpyFunc
)

export ProofForge.Backend.WasmNear.Context (
  ctxUserIdName ctxUserHashName ctxContractIdName ctxSignerName
  ctxRandomSeedName ctxUserIdFunc ctxUserHashFunc ctxContractIdFunc
  ctxSignerFunc ctxRandomSeedFunc ctxHelperFuncsForModulePlan
  lowerContextExprPlan
)

export ProofForge.Backend.WasmNear.Crosscall (
  crosscallPtrGlobal crosscallArgsStartName crosscallArgsPutcName
  crosscallArgsPutu64Name crosscallArgsPutboolName crosscallArgsPuthashName
  crosscallPtrGlobalDecl crosscallArgsStartFunc crosscallArgsPutcFunc
  crosscallArgsPutstrName crosscallArgsPutstrFunc crosscallArgsPutu64Func
  crosscallArgsPutboolFunc crosscallArgsPuthashFunc
  crosscallArgsHelperFuncsForModulePlan crosscallGlobalsForModulePlan
  poolLookupSetBody crosscallPoolPtrFunc crosscallPoolLenFunc
  crosscallPoolHelperFuncs
)

export ProofForge.Backend.WasmNear.Diagnostics (
  nativeValueUnsupportedMessage indexedEventUnsupportedMessage
  crosscallUnsupportedMessage crosscallEvmOnlyMessage
  crosscallTypedUnsupportedMessage EmitError err
)

export ProofForge.Backend.WasmNear.Event (
  fmtU64Name evtPtrGlobal evtStartName evtPutcName evtPutstrName
  evtPutu64Name evtPutboolName evtPutHashName evtLogName evtPtrGlobalDecl
  fmtU64Func evtStartFunc evtPutcFunc evtPutstrFunc evtPutu64Func
  evtPutboolFunc evtPutHashFunc evtLogFunc evtHelperFuncsForModulePlan
  evtGlobals evtPutcInsns evtHeaderInsns evtValueInsnsForType
  evtFieldInsns evtFooterInsns
)

export ProofForge.Backend.WasmNear.ExprAnalysis (
  canDuplicateExpr exprReturnsNearPromise
)

export ProofForge.Backend.WasmNear.Hash (
  modulePlanUsesHashAlloc hashAllocName hashMakeName hashSName hashTwoName
  hashEqName readHashName writeHashName hashPtrGlobal hashPtrGlobalDecl
  hashAllocFunc hashMakeFunc hashSFunc hashTwoFunc hashEqFunc readHashFunc
  writeHashFunc hashExprHelperFuncsForModulePlan
  hashStorageHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmNear.Imports (
  hostImport valTypeOfString hostFunctionImport dedupeImports bridgeBaseImports
  nearImports storageHasKeyImport sha256Import logUtf8Import inputImport
  panicImport predecessorImport currentAcctImport signerImport depositImport
  registerLenImport blockHeightImport epochHeightImport randomSeedImport
  allocImportName deallocImportName allocImport deallocImport
  modulePlanUsesSha256 nearImportsForModulePlan ctxImportsForModulePlan
  promiseCtxImportsForModulePlan promiseResultImportsForModulePlan
  hostAllocatorImportsForModulePlan importsForModulePlan
)

export ProofForge.Backend.WasmNear.Layout (
  StateInfo stateLayout findScalarState? MapInfo mapLayout findMapState?
  findArrayState? StringInfo stringPool panicMessage panicPool findString?
  crosscallStringInfos
)

export ProofForge.Backend.WasmNear.LoweringEnv (
  Ctx LBind LocalTypes lookupLocal? assignOpName resolveCrosscallStringRef
)

export ProofForge.Backend.WasmNear.Locals (
  collectLocalsFrom collectLocals
)

export ProofForge.Backend.WasmNear.Map (
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

export ProofForge.Backend.WasmNear.Memory (
  KEY_BUF RET_BUF TRUE_PTR FALSE_PTR HEX_LUT_PTR MAPKEY_BUF HASH_HEAP ARR_HEAP
  HASH_CONCAT_BUF CTX_BUF EVENT_BUF EVT_KEY_PTR STRING_BASE INPUT_BUF
  CROSSCALL_BUF CROSSCALL_ARGS_EMPTY_PTR CROSSCALL_ARGS_EMPTY_LEN
  CROSSCALL_STRING_BASE crosscallDefaultGas PARAM_HASH_BUF ZERO_HASH_BUF
  OLD_HASH_BUF STRUCT_BUF PROMISE_RESULT_BUF crosscallPoolPtrName
  crosscallPoolLenName disjointRegions memoryLayoutNonoverlap
  memoryLayoutNonoverlap_valid
)

export ProofForge.Backend.WasmNear.ModuleAssembly (
  moduleStringPoolEnd loweringCtxForModule dataSegmentsForModulePlan
  helperFuncsForModulePlan globalsForModulePlan
)

export ProofForge.Backend.WasmNear.Params (
  loadParams
)

export ProofForge.Backend.WasmNear.Promise (
  promiseCurrentAccountName promiseCurrentAccountFunc promiseResultU64Name
  promiseResultU64Func promiseHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmNear.Return (
  returnInsnsForLoweredExpr
)

export ProofForge.Backend.WasmNear.Scalar (
  storageScalarStateInfo storageScalarWriteInsns
  storageScalarAssignOpTargetType storageScalarAssignOpInsns
  readFunc writeFunc returnU64Func returnU32Func returnBoolFunc powName
  powFunc scalarStorageHelperFuncsForModulePlan returnHelperFuncsForModulePlan
  powHelperFuncsForModulePlan
)

export ProofForge.Backend.WasmNear.Statement (
  localLetBindInsns localAssignInsns localAssignOpTargetType localAssignOpInsns
  storagePathAssignOpTargetType storagePathAssignOpValueInsns releaseInsns
  dropResultInsns appendInsnChunks appendInsnChunksM requireDuplicableExpr ifElseInsns boundedForInsns
)

export ProofForge.Backend.WasmNear.Struct (
  findStruct? ScalarStructStateInfo scalarStructStateInfo
  ArrayStructInfo arrayStructMapInfo arrayStructInfo
  structTotalSize structFieldOffset? structFieldType?
  structLitName isStructStorageFieldType isIndexedStorageValueType
  structStorageFieldsSupported structStorageFieldInfo zeroStructBufInsns readScalarStructBufInsns
  scalarStructFieldReadInsns scalarStructFieldWriteInsns
  readArrayStructBufInsns arrayStructFieldReadInsns arrayStructFieldWriteInsns
)

export ProofForge.Backend.WasmNear.Types (
  wasmTypeOf widthOf isNumeric isScalarBorshType scalarWidth loadOpFor
  storeOpFor typeSuffix readName writeName returnU32Name returnU64Name
  returnBoolName
)

def stringInfoEnd (base : Nat) (strings : Array StringInfo) : Nat :=
  strings.foldl (init := base) fun acc s => max acc (s.ptr + s.len + 1)

def borshFlatWidth (ty : ProofForge.IR.ValueType) : Nat :=
  match ty with
  | .u32 => 4
  | .u64 => 8
  | .bool => 1
  | .hash => 32
  | .fixedArray elem n => scalarWidth elem * n
  | .structType _ => 512
  | _ => 0

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

  partial def lowerCrosscallArgsJson (ctx : Ctx) (env : LocalTypes) (args : Array Expr) :
      Except EmitError (Array Insn × Nat × Nat) := do
    if args.isEmpty then
      .ok (#[], CROSSCALL_ARGS_EMPTY_PTR, CROSSCALL_ARGS_EMPTY_LEN)
    else
      let (body, _) ← args.foldlM (fun (accInsns, isFirst) arg => do
        let (vis, putInsn) ← lowerCrosscallArgValue ctx env arg
        let sep := if isFirst then #[] else #[.i32Const 44, .call crosscallArgsPutcName]
        .ok (accInsns ++ sep ++ vis ++ putInsn, false))
        (#[.call crosscallArgsStartName, .i32Const 91, .call crosscallArgsPutcName], true)
      let body := body ++ #[.i32Const 93, .call crosscallArgsPutcName]
      .ok (body, CROSSCALL_BUF, 0)

  partial def lowerNearDeposit (ctx : Ctx) (env : LocalTypes) (label : String) (deposit : Expr) :
      Except EmitError (Array Insn) := do
    let (depositInsns, depositType) ← lowerExpr ctx env deposit
    if depositType != .u64 then
      err s!"EmitWat: {label} deposit expected `U64`, got `{depositType.name}`"
    else
      .ok depositInsns

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
    let (argBuildInsns, argsPtr, argsLenMarker) ← lowerCrosscallArgsJson ctx env args
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

  partial def lowerCrosscallInvoke (ctx : Ctx) (env : LocalTypes) (target method : Expr) (args : Array Expr)
      (deposit : Expr) : Except EmitError (Array Insn × ValueType) := do
    if ctx.crosscallStrings.isEmpty then
      err "EmitWat: NEAR crosscall requires `module.nearCrosscallStrings` to be populated"
    let account ← resolveCrosscallStringRef ctx target "target account id"
    let methodSi ← resolveCrosscallStringRef ctx method "method name"
    let (argBuildInsns, argsPtr, argsLenMarker) ← lowerCrosscallArgsJson ctx env args
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
    | .literal (.bool b) => .ok (#[.const .i32 (if b then "1" else "0")], .bool)
    | .literal (.hash4 a b c d) => .ok (#[.i64Const a, .i64Const b, .i64Const c, .i64Const d, .call hashMakeName], .hash)
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
    | .local name =>
      match lookupLocal? env name with
      | some t => .ok (#[.localGet name], t)
      | none => err s!"EmitWat: unknown local `{name}`"
    | .add a b _ => lowerNumBin ctx env "add" a b
    | .sub a b _ => lowerNumBin ctx env "sub" a b
    | .mul a b _ => lowerNumBin ctx env "mul" a b
    | .div a b => lowerNumBin ctx env "div_u" a b
    | .mod a b => lowerNumBin ctx env "rem_u" a b
    | .bitAnd a b => lowerNumBin ctx env "and" a b
    | .bitOr a b => lowerNumBin ctx env "or" a b
    | .bitXor a b => lowerNumBin ctx env "xor" a b
    | .shiftLeft a b => lowerNumBin ctx env "shl" a b
    | .shiftRight a b => lowerNumBin ctx env "shr_u" a b
    | .pow a b => do
      let (la, lb, t) ← lowerMatchingNumericOperands ctx env "pow" a b
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
      -- NEAR attached_deposit returns U128, but IR v0 treats nativeValue as U64.
      -- For deposits within U64 range (< 2^64), the low 64 bits are the amount.
      -- Call attached_deposit (returns i64 = low 64 bits) and use directly.
      .ok (#[.call "attached_deposit"], .u64)
    | .effect (.storageScalarRead id) =>
      match findScalarState? ctx.scalars id with
      | some s =>
        let callName := if s.type == .hash then readHashName else readName s.type
        .ok (#[.i32Const s.keyPtr, .i32Const s.keyLen, .call callName], s.type)
      | none => err s!"EmitWat: unknown scalar state `{id}`"
    | .effect (.storageMapGet id key) => lowerMapGet ctx env id key
    | .effect (.storageMapContains id key) => lowerMapContains ctx env id key
    | .effect (.contextRead field) =>
      match buildContextExprPlan field with
      | .ok plan => lowerContextExprPlan plan
      | .error planErr => err s!"EmitWat: {planErr.message}"
    | .effect (.storageMapSet id key value) | .effect (.storageMapInsert id key value) =>
      lowerMapWrite ctx env id key value
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
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
      lowerNearCrosscallInvokePool ctx env accountIndex methodId args deposit
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
      lowerNearPromiseThen ctx env parentPromise callbackMethod args deposit
    | .nearPromiseResultsCount =>
      .ok (#[.call "promise_results_count"], .u64)
    | .nearPromiseResultStatus index => do
      let indexInsns ← lowerNearPromiseResultIndex ctx env index
      .ok (indexInsns ++ #[.i64Const 0, .call "promise_result"], .u64)
    | .nearPromiseResultU64 index => do
      let indexInsns ← lowerNearPromiseResultIndex ctx env index
      .ok (indexInsns ++ #[.call promiseResultU64Name], .u64)
    | _ => err "EmitWat: this expression form is not yet supported"

  partial def lowerMatchingNumericOperands (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if !(isNumeric ta && ta == tb) then
      err s!"EmitWat: `{op}` expected matching U32/U64 operands, got `{ta.name}`/`{tb.name}`"
    else
      .ok (la, lb, ta)

  partial def lowerNumBin (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, lb, t) ← lowerMatchingNumericOperands ctx env op a b
    .ok (la ++ lb ++ #[.plain (widthOf t ++ "." ++ op)], t)

  partial def lowerCmp (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if ta != tb then err s!"EmitWat: `{op}` expected matching operand types, got `{ta.name}`/`{tb.name}`"
    else if ta == .hash && op == "eq" then .ok (la ++ lb ++ #[.call hashEqName], .bool)
    else if ta == .hash && op == "ne" then .ok (la ++ lb ++ #[.call hashEqName, .plain "i32.eqz"], .bool)
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
  returnInsnsForLoweredExpr expected e is t

partial def lowerEventEmit (ctx : Ctx) (env : LocalTypes) (name : String) (fields : Array (String × Expr))
    : Except EmitError (Array Insn) := do
  let some nameSi ← pure (findString? ctx.strings name) | err s!"EmitWat: event name `{name}` not in string pool"
  let header := evtHeaderInsns nameSi
  let fieldInsns ← appendInsnChunksM fields fun f => do
    let (fname, vexpr) := f
    let some fsi ← pure (findString? ctx.strings fname) | err s!"EmitWat: field name `{fname}` not in string pool"
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

def lowerEntrypoint (ctx : Ctx) (ep : Entrypoint) : Except EmitError Func := do
  let bodyLocals ← collectLocals ep.body
  let (paramPrologue, paramLocals) ← loadParams ctx.structs ep.params
  let allLocalTypes : LocalTypes :=
    (ep.params.map (fun (n, t) => { name := n, vt := t : LBind })) ++ bodyLocals
  let locals := paramLocals ++ bodyLocals.map (fun b => { name := b.name, type := wasmTypeOf b.vt : Local })
  let bodyInsns ← appendInsnChunksM ep.body fun s => lowerStmt ctx allLocalTypes ep.returns s
  let resetPrefix : Array Insn :=
    if ctx.allocator.usesEntryReset then
      #[.i32Const ctx.allocator.heapBase, .globalSet arrPtrGlobal]
    else #[]
  .ok { name := ep.name, locals := locals, body := { insns := resetPrefix ++ paramPrologue ++ bodyInsns }, exportName := ep.name }

/- Core lowering body once the surface `ModulePlan` and the data-layout `Ctx`
have been derived. Exposed so the plan-driven path
(`ProofForge.Backend.WasmNear.NearModulePlan.lowerModuleFromPlan`) can reuse the
exact same body without re-deriving the layout inline. This mirrors Solana's
`lowerModuleCoreWithSeed` extraction in `SbpfAsm.lean`. The body is a pure
function of `(mod, modulePlan, ctx)` — it does not re-derive any layout. -/
def lowerModuleCoreWithCtx (mod : ProofForge.IR.Module) (modulePlan : ModulePlan)
    (ctx : Ctx) : Except EmitError ProofForge.Compiler.Wasm.Module := do
  let entryFuncs ← mod.entrypoints.mapM (lowerEntrypoint ctx)
  let hasPanic := !ctx.panics.isEmpty
  let imports := importsForModulePlan modulePlan mod.allocator hasPanic
  let funcs := helperFuncsForModulePlan modulePlan mod ctx entryFuncs
  let globals := globalsForModulePlan modulePlan mod.allocator
  .ok { imports := imports, globals := globals, funcs := funcs,
        memory := some { min := 1 },
        dataSegments := dataSegmentsForModulePlan modulePlan ctx }

def lowerModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := ProofForge.Target.HostBridge.near) : Except EmitError ProofForge.Compiler.Wasm.Module := do
  if bridge == ProofForge.Target.HostBridge.cosmWasm then
    err "EmitWat: CosmWasm bridge lowering is implemented in Backend.CosmWasm.EmitWat; use that module for wasm-cosmwasm"
  if mod.allocator.isCosmWasmRegion then
    err "EmitWat: alloc.cosmwasm_region is for the CosmWasm adapter, not wasm-near EmitWat"
  let modulePlan ←
    match buildModulePlan mod with
    | .ok plan => pure plan
    | .error planErr => err s!"EmitWat: {planErr.message}"
  let ctx := loweringCtxForModule mod
  validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  lowerModuleCoreWithCtx mod modulePlan ctx

def renderCheckedModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Except EmitError String := do
  match ProofForge.IR.Ownership.checkModule mod with
  | .ok _ => pure ()
  | .error error => err s!"EmitWat: {error.render}"
  let m ← lowerModule mod bridge
  .ok (Printer.render m)

def renderModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Except EmitError String := do
  checkCapabilities mod
  renderCheckedModule mod bridge

def renderModuleWithPlan
    (mod : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Except EmitError String := do
  checkTargetPlan plan
  renderCheckedModule mod bridge


end ProofForge.Backend.WasmNear.EmitWat
