/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# NearModulePlan — Tier B data-layout plan for the NEAR (WasmNear) backend

This is the Step B plan-driven lowering from RFC 0014 Phase 4
(see `docs/multi-backend-moduleplan-design.md`). It defines the field-level
`NearModulePlan` that *extends* the existing `WasmNear.Plan.ModulePlan` (the
host-import/helper-discovery surface already consumed by `EmitWat.lowerModule`)
with the data-layout surface (scalar key pointers, map prefix pointers, string
pool, panic pool, crosscall string pool) that `EmitWat` previously built inline
as `Ctx`.

The canonical production entry is `lowerFromPlan`: it consumes only the
target-owned `NearModulePlan` and does not accept an `IR.Module`. Compatibility
builders and lowerers for the retired v1 IR live in `NearModulePlan.Legacy` so
they cannot enter the canonical builder's dependency graph implicitly.
-/

import ProofForge.IR.Allocator
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearAbiPlan
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge
import ProofForge.Backend.WasmHost.HostABI
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Backend.WasmHost.Imports
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.JsonReturn
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.StringCmp
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Crosscall
import ProofForge.Backend.WasmHost.Promise
import ProofForge.Backend.WasmHost.Context

namespace ProofForge.Backend.WasmHost.NearModulePlan

open ProofForge.IR
open ProofForge.Backend.WasmHost.Types
open ProofForge.Target.HostBridge
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.NearAbiPlan
open ProofForge.Backend.WasmHost.EmitWat

/-- One scalar state slot's plan: the storage key pointer in linear memory.
Carries the `ValueType` so `Ctx.fromPlanSeed` can rebuild `StateInfo.type`

(which drives `readName`/`readHashName` dispatch). -/
abbrev NearStatePlan := ProofForge.Backend.WasmHost.ModulePlan.StatePlan

/-- One map/array state slot's plan: the `id ++ ":"` prefix pointer. Carries
the key/value `ValueType`s so `Ctx.fromPlanSeed` can rebuild `MapInfo`. -/
abbrev NearMapPlan := ProofForge.Backend.WasmHost.ModulePlan.MapPlan

/-- One string-pool entry (event/field name, panic message, or crosscall string). -/
abbrev NearStringPoolEntry := ProofForge.Backend.WasmHost.ModulePlan.StringPoolEntry

/-- The data-layout surface: everything `EmitWat.Ctx` holds that is a deterministic
function of the module. These six fields are currently rebuilt inline at the top of
`EmitWat.lowerModule`; the plan promotes them to an inspectable artifact. -/
abbrev NearLayoutPlan := ProofForge.Backend.WasmHost.ModulePlan.LayoutPlan

abbrev NearValuePlan := ProofForge.Backend.WasmHost.ModulePlan.ValuePlan

abbrev NearArithmeticPlan := ProofForge.Backend.WasmHost.ModulePlan.ArithmeticPlan

abbrev NearComparePlan := ProofForge.Backend.WasmHost.ModulePlan.ComparePlan

abbrev NearOpPlan := ProofForge.Backend.WasmHost.ModulePlan.OpPlan

abbrev NearTerminatorPlan := ProofForge.Backend.WasmHost.ModulePlan.TerminatorPlan

abbrev NearBlockPlan := ProofForge.Backend.WasmHost.ModulePlan.BlockPlan

abbrev NearFunctionPlan := ProofForge.Backend.WasmHost.ModulePlan.FunctionPlan

/-- The frozen scratch-region base addresses (constants in `EmitWat`). The seed
makes them plan-owned so the lowering is a pure function of the plan + IR module,
mirroring `SolanaLowerCtxSeed`. -/
abbrev NearLowerCtxSeed := ProofForge.Backend.WasmHost.ModulePlan.LowerCtxSeed

/-- The top-level plan. `surface` is the existing `WasmNear.Plan.ModulePlan`
(host imports / helpers); `layout` is the new data-layout surface; `lowerCtxSeed`
carries the frozen base addresses and read-only type metadata. -/
abbrev NearModulePlan := ProofForge.Backend.WasmHost.ModulePlan.WasmHostModulePlan

/-- Render a `ValueType` using the IR's own naming (so the plan text matches the
IR module, not the Wasm type). -/
def renderValueType (vt : ValueType) : String := vt.name

-- ----------------------------------------------------------------------------
-- Rendering (stable, diff-friendly text artifact; mirrors SolanaModulePlan.render)
-- ----------------------------------------------------------------------------

def renderNat (n : Nat) : String := toString n
def renderBool (b : Bool) : String := if b then "true" else "false"

def renderScalar (s : NearStatePlan) : String :=
  s!"  {s.id}: type={renderValueType s.type} keyPtr={renderNat s.keyPtr} keyLen={renderNat s.keyLen}"

def renderMap (m : NearMapPlan) : String :=
  s!"  {m.id}: keyType={renderValueType m.keyType} valueType={renderValueType m.valueType} prefixPtr={renderNat m.prefixPtr} prefixLen={renderNat m.prefixLen} isArray={renderBool m.isArray}"

def renderStringEntry (e : NearStringPoolEntry) : String :=
  s!"  \"{e.str}\": ptr={renderNat e.ptr} len={renderNat e.len}"

def renderSurfaceBool (label : String) (b : Bool) : String :=
  s!"  {label}: {renderBool b}"

def renderSurfaceTypes (label : String) (ts : Array ValueType) : String :=
  s!"  {label}: [{String.intercalate ", " (ts.toList.map renderValueType)}]"

def renderEntrypointAbi (abi : EntrypointPlan) : String :=
  s!"  {abi.name}: input={abi.inputCodec.id}/{abi.inputByteWidth} output={abi.outputCodec.id}/{abi.outputByteWidth} return={abi.returnType.name}"

/-- Render the plan as a stable, diff-friendly text artifact. The format mirrors
`SolanaModulePlan.render`: simple key-value lines so small plan changes produce
readable golden diffs. -/
def NearModulePlan.render (plan : NearModulePlan) : String :=
  let surf := plan.surface
  let lines := #[
    s!"targetId: {plan.targetId}",
    s!"artifactKind: {plan.artifactKind}",
    s!"irVersion: {plan.irVersion}",
    s!"moduleName: {plan.moduleName}",
    "surface:",
    renderSurfaceBool "usesEventApi" surf.usesEventApi,
    renderSurfaceBool "usesPromiseCreate" surf.usesPromiseCreate,
    renderSurfaceBool "usesPromiseThen" surf.usesPromiseThen,
    renderSurfaceBool "usesPromiseResults" surf.usesPromiseResults,
    renderSurfaceBool "usesStorageRead" surf.usesStorageRead,
    renderSurfaceBool "usesStorageWrite" surf.usesStorageWrite,
    renderSurfaceBool "usesNativeValue" surf.usesNativeValue,
    renderSurfaceBool "usesHashMake" surf.usesHashMake,
    renderSurfaceBool "usesHashPreimage" surf.usesHashPreimage,
    renderSurfaceBool "usesHashTwoToOne" surf.usesHashTwoToOne,
    renderSurfaceBool "usesHashEq" surf.usesHashEq,
    renderSurfaceBool "usesPowU32" surf.usesPowU32,
    renderSurfaceBool "usesPowU64" surf.usesPowU64,
    renderSurfaceBool "usesMemcpy" surf.usesMemcpy,
    renderSurfaceBool "usesArrAlloc" surf.usesArrAlloc,
    renderSurfaceBool "usesArrDealloc" surf.usesArrDealloc,
    renderSurfaceTypes "scalarReadTypes" surf.scalarReadTypes,
    renderSurfaceTypes "scalarWriteTypes" surf.scalarWriteTypes,
    renderSurfaceTypes "u64IndexedReadTypes" surf.u64IndexedReadTypes,
    renderSurfaceTypes "u64IndexedWriteTypes" surf.u64IndexedWriteTypes,
    renderSurfaceTypes "hashIndexedReadTypes" surf.hashIndexedReadTypes,
    renderSurfaceTypes "hashIndexedWriteTypes" surf.hashIndexedWriteTypes,
    renderSurfaceTypes "returnTypes" surf.returnTypes,
    renderSurfaceBool "usesInputParams" surf.usesInputParams,
    "entrypointAbis:",
    plan.entrypointAbis.map renderEntrypointAbi
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "layout:",
    s!"  stringPoolEnd: {renderNat plan.layout.stringPoolEnd}",
    "  scalars:",
    plan.layout.scalars.map renderScalar
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "  maps:",
    plan.layout.maps.map renderMap
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "  strings:",
    plan.layout.strings.map renderStringEntry
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "  panics:",
    plan.layout.panics.map renderStringEntry
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "  crosscallStrings:",
    plan.layout.crosscallStrings.map renderStringEntry
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "lowerCtxSeed:",
    s!"  keyBuf: {renderNat plan.lowerCtxSeed.keyBuf}",
    s!"  mapkeyBuf: {renderNat plan.lowerCtxSeed.mapkeyBuf}",
    s!"  stringBase: {renderNat plan.lowerCtxSeed.stringBase}",
    s!"  crosscallStringBase: {renderNat plan.lowerCtxSeed.crosscallStringBase}",
    s!"  structs: [{String.intercalate ", " (plan.lowerCtxSeed.structs.toList.map (fun s => s.name))}]"
  ]
  String.intercalate "\n" (lines.toList.filter (!·.isEmpty))

-- ============================================================================
-- Plan-driven lowering (Tier B contract) — Step B
-- ============================================================================

private def canonicalNearType (name : String) : ValueType :=
  if name.endsWith "bool" then .bool
  else if name.endsWith "u32" then .u32
  else if name.endsWith "u128" then .u128
  else if name.endsWith "hash" then .hash
  else if name.endsWith "string" then .string
  else if name.endsWith "address" then .address
  else if name.contains "structType" then .structType ""
  else .u64

/-! Two-word value conventions (mirrors the legacy path):
    * u128 `v{id}` occupies `v{id}` (lo) + `v{id}__hi` (hi); get pushes both
      (lo then hi); set consumes hi then lo.
    * string `v{id}` occupies `v{id}` (ptr) + `v{id}_len (len); get pushes
      (ptr then len); set consumes len then ptr. -/

private def canonicalNearGet (id : Nat) (typeName : String) :
    Array ProofForge.Compiler.Wasm.Insn :=
  if canonicalNearType typeName == .u128 then
    #[.localGet s!"v{id}", .localGet (Types.u128HiName s!"v{id}")]
  else if canonicalNearType typeName == .string then
    #[.localGet s!"v{id}", .localGet (s!"v{id}_len")]
  else #[.localGet s!"v{id}"]

private def canonicalNearSet (id : Nat) (typeName : String) :
    Array ProofForge.Compiler.Wasm.Insn :=
  if canonicalNearType typeName == .u128 then
    #[.localSet (Types.u128HiName s!"v{id}"), .localSet s!"v{id}"]
  else if canonicalNearType typeName == .string then
    #[.localSet (s!"v{id}_len"), .localSet s!"v{id}"]
  else #[.localSet s!"v{id}"]

private def canonicalNearLocals (value : NearValuePlan) : Array ProofForge.Compiler.Wasm.Local :=
  if canonicalNearType value.typeName == .u128 then
    #[{ name := s!"v{value.id}", type := .i64 },
      { name := Types.u128HiName s!"v{value.id}", type := .i64 }]
  else if canonicalNearType value.typeName == .string then
    #[{ name := s!"v{value.id}", type := .i32 },
      { name := s!"v{value.id}_len", type := .i32 }]
  else
    #[{ name := s!"v{value.id}", type := Types.wasmTypeOf (canonicalNearType value.typeName) }]

private def canonicalNearLocal (value : NearValuePlan) : ProofForge.Compiler.Wasm.Local :=
  if canonicalNearType value.typeName == .string then
    { name := s!"v{value.id}", type := .i32 }
  else
    { name := s!"v{value.id}", type := Types.wasmTypeOf (canonicalNearType value.typeName) }

private def canonicalNearState? (plan : NearModulePlan) (id : Nat) : Option Layout.StateInfo :=
  plan.layout.scalars.find? (fun state => state.coreId? == some id) |>.map fun state => {
    id := state.id, type := state.type, keyPtr := state.keyPtr, keyLen := state.keyLen,
    packOffset := state.packOffset, packed := state.packed
  }

private def canonicalNearArithmetic (ty : ValueType) : NearArithmeticPlan -> String
  | .add => Types.widthOf ty ++ ".add" | .sub => Types.widthOf ty ++ ".sub"
  | .mul => Types.widthOf ty ++ ".mul" | .div => Types.widthOf ty ++ ".div_u"
  | .mod => Types.widthOf ty ++ ".rem_u" | .bitAnd => Types.widthOf ty ++ ".and"
  | .bitOr => Types.widthOf ty ++ ".or" | .bitXor => Types.widthOf ty ++ ".xor"
  | .shiftLeft => Types.widthOf ty ++ ".shl" | .shiftRight => Types.widthOf ty ++ ".shr_u"

private def canonicalNearCompare (ty : ValueType) : NearComparePlan -> String
  | .eq => Types.widthOf ty ++ ".eq" | .ne => Types.widthOf ty ++ ".ne"
  | .lt => Types.widthOf ty ++ ".lt_u" | .le => Types.widthOf ty ++ ".le_u"
  | .gt => Types.widthOf ty ++ ".gt_u" | .ge => Types.widthOf ty ++ ".ge_u"

private def canonicalEventStrings (plan : NearModulePlan) : Array Layout.StringInfo := Id.run do
  let mut strings := #[]
  let mut ptr := Memory.STRING_BASE
  for fn in plan.functions do
    for block in fn.blocks do
      for op in block.ops do
        match op with
        | .log event fields =>
            for value in #[Layout.eventHeaderPoolString event] ++
                fields.mapIdx (fun index field => Layout.eventFieldPoolString index field.fst) do
              if !strings.any (fun entry => entry.str == value) then
                strings := strings.push { str := value, ptr, len := value.length }
                ptr := ptr + value.length
        | _ => pure ()
  strings

private def canonicalPromiseStrings (plan : NearModulePlan) : Array Layout.StringInfo := Id.run do
  let mut strings := #[]
  let mut ptr := Memory.CROSSCALL_STRING_BASE
  for fn in plan.functions do
    for block in fn.blocks do
      for op in block.ops do
        match op with
        | .promiseCreate _ accountId methodName _ _ _
        | .portableCrosscall _ accountId methodName _ _ _ =>
            for value in #[accountId, methodName] do
              if !strings.any (fun entry => entry.str == value) then
                strings := strings.push { str := value, ptr, len := value.length }
                ptr := ptr + value.length
        | _ => pure ()
  strings

private def canonicalLiteralStrings (plan : NearModulePlan)
    (eventStrings : Array Layout.StringInfo) : Array Layout.StringInfo := Id.run do
  let mut strings := #[]
  let mut ptr := eventStrings.foldl (fun end_ entry => max end_ (entry.ptr + entry.len))
    Memory.STRING_BASE
  for fn in plan.functions do
    for block in fn.blocks do
      for op in block.ops do
        match op with
        | .stringLiteral _ value =>
            if !strings.any (fun entry => entry.str == value) then
              strings := strings.push { str := value, ptr, len := value.length }
              ptr := ptr + value.length
        | _ => pure ()
  strings

private def canonicalStaticJsonBytes (value : String) : Array ProofForge.Compiler.Wasm.Insn :=
  value.toUTF8.data.foldl (init := #[]) fun insns byte =>
    insns ++ #[.i32Const byte.toNat, .call Crosscall.crosscallArgsPutcName]

private def canonicalCrosscallArgs (args : Array NearValuePlan) (argNames : Array String) :
    Array ProofForge.Compiler.Wasm.Insn := Id.run do
  if args.isEmpty then
    return #[]
  let objectMode := !argNames.isEmpty
  let mut insns := #[.call Crosscall.crosscallArgsStartName,
    .i32Const (if objectMode then 0x7b else 0x5b),
    .call Crosscall.crosscallArgsPutcName]
  for index in [:args.size] do
    if index > 0 then
      insns := insns ++ #[.i32Const 0x2c, .call Crosscall.crosscallArgsPutcName]
    if objectMode then
      insns := insns ++ canonicalStaticJsonBytes s!"\"{argNames[index]!}\":"
    let arg := args[index]!
    if arg.typeName.endsWith "bool" then
      insns := insns ++ #[.localGet s!"v{arg.id}", .call Crosscall.crosscallArgsPutboolName]
    else if arg.typeName.endsWith "hash" then
      insns := insns ++ #[.localGet s!"v{arg.id}", .call Crosscall.crosscallArgsPuthashName]
    else if arg.typeName.endsWith "string" then
      -- JSON-quoted UTF-8 string arg (two-slot ptr+len local).
      insns := insns ++ #[.localGet s!"v{arg.id}", .localGet (s!"v{arg.id}_len"),
        .call Crosscall.crosscallArgsPutJsonStringName]
    else if canonicalNearType arg.typeName == .u128 then
      -- u128 crosscall arg: two-word (lo, hi) → decimal string via putu128.
      insns := insns ++ #[.localGet s!"v{arg.id}", .localGet (Types.u128HiName s!"v{arg.id}"),
        .call Crosscall.crosscallArgsPutu128Name]
    else
      insns := insns ++ #[.localGet s!"v{arg.id}"]
      if canonicalNearType arg.typeName == .u32 then
        insns := insns ++ #[.plain "i64.extend_i32_u"]
      insns := insns ++ #[.call Crosscall.crosscallArgsPutu64Name]
  insns ++ #[.i32Const (if objectMode then 0x7d else 0x5d),
    .call Crosscall.crosscallArgsPutcName]

private def canonicalCrosscallArgsLenPtr (args : Array NearValuePlan) :
    Array ProofForge.Compiler.Wasm.Insn :=
  if args.isEmpty then
    #[.i64Const 0, .i64Const Memory.CROSSCALL_ARGS_EMPTY_PTR]
  else
    #[.globalGet Crosscall.crosscallPtrGlobal, .i32Const Memory.CROSSCALL_BUF,
      .plain "i32.sub", .plain "i64.extend_i32_u", .i64Const Memory.CROSSCALL_BUF]

private def canonicalNearI64 (value : NearValuePlan) : Array ProofForge.Compiler.Wasm.Insn :=
  #[.localGet s!"v{value.id}"] ++
    (if canonicalNearType value.typeName == .u32 then #[.plain "i64.extend_i32_u"] else #[])

private def canonicalDepositPtr (deposit : NearValuePlan) : Array ProofForge.Compiler.Wasm.Insn :=
  #[.i32Const Memory.RET_BUF] ++ canonicalNearI64 deposit ++ #[.store "i64.store" 0,
    .i32Const (Memory.RET_BUF + 8), .i64Const 0, .store "i64.store" 0]

private def lowerCanonicalNearOp (plan : NearModulePlan)
    (eventStrings promiseStrings literalStrings : Array Layout.StringInfo) :
    NearOpPlan -> Except Diagnostics.EmitError (Array ProofForge.Compiler.Wasm.Insn)
  | .literal result value =>
      if canonicalNearType result.typeName == .u128 then
        .ok (#[.i64Const value, .i64Const 0] ++ canonicalNearSet result.id result.typeName)
      else
        .ok #[.const (Types.wasmTypeOf (canonicalNearType result.typeName)) (toString value), .localSet s!"v{result.id}"]
  | .stringLiteral result value => do
      let some info := literalStrings.find? (fun entry => entry.str == value)
        | Diagnostics.err s!"canonical NEAR string literal is missing from the data pool"
      return #[.i32Const info.ptr, .localSet s!"v{result.id}",
        .i32Const info.len, .localSet s!"v{result.id}_len"]
  | .hashLiteral result a b c d => .ok #[
      .i64Const a, .i64Const b, .i64Const c, .i64Const d,
      .call Hash.hashMakeName, .localSet s!"v{result.id}"]
  | .boolLiteral result value => .ok #[.i32Const (if value then 1 else 0), .localSet s!"v{result.id}"]
  | .structLit result _ fields => do
      let total := fields.foldl (fun size field => size + Types.scalarWidth (canonicalNearType field.typeName)) 0
      let mut offset := 0
      let mut stores : Array ProofForge.Compiler.Wasm.Insn := #[]
      for field in fields do
        let ty := canonicalNearType field.typeName
        let address := #[.localGet s!"v{result.id}", .i32Const offset, .plain "i32.add"]
        if ty == .u128 then
          stores := stores ++ address ++ #[.localGet s!"v{field.id}", .store "i64.store" 0] ++
            #[.localGet s!"v{result.id}", .i32Const (offset + 8), .plain "i32.add",
              .localGet (Types.u128HiName s!"v{field.id}"), .store "i64.store" 0]
        else if ty == .string || ty == .bytes then
          stores := stores ++ address ++ #[.localGet s!"v{field.id}", .store "i32.store" 0] ++
            #[.localGet s!"v{result.id}", .i32Const (offset + 4), .plain "i32.add",
              .localGet s!"v{field.id}_len", .store "i32.store" 0]
        else
          stores := stores ++ address ++ canonicalNearGet field.id field.typeName ++
            #[.store (Types.storeOpFor ty) 0]
        offset := offset + Types.scalarWidth ty
      .ok (#[.i64Const total, .call ArrayHeap.arrAllocName, .localSet s!"v{result.id}"] ++ stores)
  | .loadState result stateId => do
      let state <- match canonicalNearState? plan stateId with
        | some state => pure state
        | none => Diagnostics.err s!"canonical NEAR references unknown scalar state {stateId}"
      let (insns, _) := Scalar.storageScalarReadInsns state
      return insns ++ canonicalNearSet result.id result.typeName
  | .storeState stateId value => do
      let state <- match canonicalNearState? plan stateId with
        | some state => pure state
        | none => Diagnostics.err s!"canonical NEAR references unknown scalar state {stateId}"
      Scalar.storageScalarWriteInsns #[] state state.id
        (canonicalNearGet value.id value.typeName) state.type
  | .loadMap result stateId key => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.coreId? == some stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let readCall ← Map.mapReadCall mapInfo mapInfo.id
      let (instructions, _) := Map.mapReadValueInsns mapInfo
        (canonicalNearGet key.id key.typeName) readCall
      return instructions ++ canonicalNearSet result.id result.typeName
  | .storeMap stateId key value => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.coreId? == some stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let writeCall ← Map.mapWriteCall mapInfo
      let (instructions, outType) ← Map.mapWriteValueInsns mapInfo mapInfo.id
        (canonicalNearGet key.id key.typeName)
        (canonicalNearGet value.id value.typeName) writeCall mapInfo.valueType
      -- A U128 map write yields Unit (the void write helper cannot return the
      -- prior value as two words); skip the drop for Unit, mirror the legacy path.
      return instructions ++ (if outType == .unit then #[] else #[.drop])
  | .removeMap stateId key => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.coreId? == some stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let deleteCall ← Map.mapDeleteCall mapInfo
      let (instructions, _) := Map.mapDeleteValueInsns mapInfo
        (canonicalNearGet key.id key.typeName) deleteCall
      return instructions ++ #[.drop]
  | .arithmetic result op checked lhs rhs =>
      let ty := canonicalNearType result.typeName
      if ty == .u128 then
        -- u128 arithmetic: two-word operands → __pf_u128_add/sub (void, writes
        -- U128_RESULT_BUF) → reload lo/hi → set result. Checked-overflow on
        -- u128 is not yet wired (the FT's +!/-! on amounts stays unchecked here).
        let arithName : String := match op with
          | .add => Scalar.u128AddName
          | .sub => Scalar.u128SubName
          | .mul => Scalar.u128MulName
          | _ => ""
        if arithName.isEmpty then
          Diagnostics.err s!"canonical NEAR: u128 arithmetic not yet supported (only add/sub/mul)"
        else
          .ok (canonicalNearGet lhs.id lhs.typeName ++
            canonicalNearGet rhs.id rhs.typeName ++
            #[.call arithName,
              .i32Const Memory.U128_RESULT_BUF, .load "i64.load" 0,
              .i32Const (Memory.U128_RESULT_BUF + 8), .load "i64.load" 0]
            ++ canonicalNearSet result.id result.typeName)
      else
      let calculation := canonicalNearGet lhs.id lhs.typeName ++
        canonicalNearGet rhs.id rhs.typeName ++
        #[.plain (canonicalNearArithmetic ty op)] ++ canonicalNearSet result.id result.typeName
      if !checked then .ok calculation else
        match op with
        | .add => .ok (calculation ++ canonicalNearGet result.id result.typeName ++
            canonicalNearGet lhs.id lhs.typeName ++
            #[.plain (Types.widthOf ty ++ ".lt_u"), .if_ { insns := #[.unreachable] } { insns := #[] }])
        | .sub => .ok (canonicalNearGet lhs.id lhs.typeName ++
            canonicalNearGet rhs.id rhs.typeName ++
            #[.plain (Types.widthOf ty ++ ".lt_u"), .if_ { insns := #[.unreachable] } { insns := #[] }] ++ calculation)
        | .div | .mod => .ok (canonicalNearGet rhs.id rhs.typeName ++
            #[.plain (Types.widthOf ty ++ ".eqz"), .if_ { insns := #[.unreachable] } { insns := #[] }] ++ calculation)
        | .mul => .ok (calculation ++ canonicalNearGet rhs.id rhs.typeName ++
            #[.plain (Types.widthOf ty ++ ".eqz"),
            .if_ { insns := #[] } { insns := (canonicalNearGet result.id result.typeName ++
              canonicalNearGet rhs.id rhs.typeName ++
              #[.plain (Types.widthOf ty ++ ".div_u")] ++ canonicalNearGet lhs.id lhs.typeName ++
              #[.plain (Types.widthOf ty ++ ".ne"),
              .if_ { insns := #[.unreachable] } { insns := #[] }]) }])
        | _ => .ok calculation
  | .compare result op lhs rhs =>
      let ty := canonicalNearType lhs.typeName
      if ty == .hash && (op == .eq || op == .ne) then
        .ok (#[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}", .call Hash.hashEqName] ++
          (if op == .ne then #[.plain "i32.eqz"] else #[]) ++ #[.localSet s!"v{result.id}"])
      else if ty == .string && (op == .eq || op == .ne) then
        -- string comparison: two-slot operands (ptr, len) each → __pf_str_eq.
        .ok (canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName ++
          #[.call StringCmp.strEqName] ++
          (if op == .ne then #[.plain "i32.eqz"] else #[]) ++ #[.localSet s!"v{result.id}"])
      else if ty == .u128 then
        -- u128 comparison: two-word operands → __pf_u128_eq / __pf_u128_lt.
        -- eq/ne → u128_eq (+ eqz for ne); ge → u128_lt + eqz;
        -- lt → u128_lt; gt → swapped u128_lt; le → swapped + eqz.
        let cmpInsns : Array ProofForge.Compiler.Wasm.Insn :=
          match op with
          | .eq => canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName
                    ++ #[.call Scalar.u128EqName]
          | .ne => canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName
                    ++ #[.call Scalar.u128EqName, .plain "i32.eqz"]
          | .lt => canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName
                    ++ #[.call Scalar.u128LtName]
          | .ge => canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName
                    ++ #[.call Scalar.u128LtName, .plain "i32.eqz"]
          | .gt => canonicalNearGet rhs.id rhs.typeName ++ canonicalNearGet lhs.id lhs.typeName
                    ++ #[.call Scalar.u128LtName]
          | .le => canonicalNearGet rhs.id rhs.typeName ++ canonicalNearGet lhs.id lhs.typeName
                    ++ #[.call Scalar.u128LtName, .plain "i32.eqz"]
        .ok (cmpInsns ++ #[.localSet s!"v{result.id}"])
      else
        .ok (canonicalNearGet lhs.id lhs.typeName ++ canonicalNearGet rhs.id rhs.typeName ++
          #[.plain (canonicalNearCompare ty op), .localSet s!"v{result.id}"])
  | .hashTwoToOne result lhs rhs =>
      .ok #[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}",
        .call Hash.hashTwoName, .localSet s!"v{result.id}"]
  | .hash result value =>
      if value.typeName.endsWith "address" then
        .ok #[.call Context.ctxUserHashName, .localSet s!"v{result.id}"]
      else
        .ok #[.localGet s!"v{value.id}", .call Hash.hashSName,
          .localSet s!"v{result.id}"]
  | .cast result value =>
      .ok (canonicalNearI64 value ++ #[.localSet s!"v{result.id}"])
  | .context result field =>
    if plan.hostBridge.bridge == .soroban then
      -- Soroban context lowering: block/timestamp/epoch use retained NEAR
      -- imports (not real Soroban Env). Sender uses ctxUserId (NEAR-style,
      -- retained). Value/deposit is not supported. Fail closed on unsupported
      -- context fields to avoid silent NEAR import mismatches.
      if field.endsWith "blockNumber" then
        .ok #[.call "block_index", .localSet s!"v{result.id}"]
      else if field.endsWith "blockTimestamp" then
        .ok #[.call "block_timestamp", .localSet s!"v{result.id}"]
      else if field.endsWith "epochHeight" then
        .ok #[.call "epoch_height", .localSet s!"v{result.id}"]
      else if field.endsWith "sender" then
        .ok #[.call Context.ctxUserIdName, .localSet s!"v{result.id}"]
      else if field.endsWith "signer" then
        .ok #[.call Context.ctxSignerName, .localSet s!"v{result.id}"]
      else if field.endsWith "contractAddress" then
        .ok #[.call Context.ctxContractIdName, .localSet s!"v{result.id}"]
      else Diagnostics.err s!"canonical Soroban context `{field}` has no handler"
    else if field.endsWith "blockNumber" then
      .ok #[.call "block_index", .localSet s!"v{result.id}"]
    else if field.endsWith "blockTimestamp" then
      .ok #[.call "block_timestamp", .localSet s!"v{result.id}"]
    else if field.endsWith "epochHeight" then
      .ok #[.call "epoch_height", .localSet s!"v{result.id}"]
    else if field.endsWith "randomSeed" then
      .ok #[.call Context.ctxRandomSeedName, .localSet s!"v{result.id}"]
    else if field.endsWith "signer" then
      .ok #[.call Context.ctxSignerName, .localSet s!"v{result.id}"]
    else if field.endsWith "value" then
      if canonicalNearType result.typeName == .u128 then
        .ok (#[.i64Const Memory.RET_BUF, .call "attached_deposit",
          .i32Const Memory.RET_BUF, .load "i64.load" 0,
          .i32Const (Memory.RET_BUF + 8), .load "i64.load" 0] ++
          canonicalNearSet result.id result.typeName)
      else
        .ok #[.i64Const Memory.RET_BUF, .call "attached_deposit",
          .i32Const Memory.RET_BUF, .load "i64.load" 0, .localSet s!"v{result.id}"]
    else if field.endsWith "sender" then
      .ok #[.call Context.ctxUserIdName, .localSet s!"v{result.id}"]
    else if field.endsWith "accountId" then
      -- Raw predecessor_account_id string (no sha256). The VOID helper stages
      -- the bytes at ACCT_ID_BUF and the 4-byte LE length at ACCT_ID_LEN;
      -- materialize (ptr, len) into the two-slot string local.
      .ok (#[.call Context.ctxAccountIdName,
        .i32Const Memory.ACCT_ID_BUF,
        .i32Const Memory.ACCT_ID_LEN, .load "i32.load" 0]
        ++ canonicalNearSet result.id result.typeName)
    else if field.endsWith "contractAddress" then
      .ok #[.call Context.ctxContractIdName, .localSet s!"v{result.id}"]
    else Diagnostics.err s!"canonical NEAR context `{field}` has no handler"
  | .hostContext result hostOpId =>
    if plan.hostBridge.bridge != .near then
      Diagnostics.err s!"target HostOp context `{hostOpId.render}` is only supported by wasm-near"
    else if hostOpId == HostOps.predecessorAccountIdId then
      .ok (#[.call Context.ctxAccountIdName,
        .i32Const Memory.ACCT_ID_BUF,
        .i32Const Memory.ACCT_ID_LEN, .load "i32.load" 0] ++
        canonicalNearSet result.id result.typeName)
    else if hostOpId == HostOps.currentAccountIdId then
      .ok (#[.call Context.ctxCurrentAccountIdName,
        .i32Const Memory.ACCT_ID_BUF,
        .i32Const Memory.ACCT_ID_LEN, .load "i32.load" 0] ++
        canonicalNearSet result.id result.typeName)
    else if hostOpId == HostOps.epochHeightId then
      .ok #[.call "epoch_height", .localSet s!"v{result.id}"]
    else if hostOpId == HostOps.randomSeedId then
      .ok #[.call Context.ctxRandomSeedName, .localSet s!"v{result.id}"]
    else if hostOpId == HostOps.prepaidGasId then
      .ok #[.call "prepaid_gas", .localSet s!"v{result.id}"]
    else if hostOpId == HostOps.usedGasId then
      .ok #[.call "used_gas", .localSet s!"v{result.id}"]
    else
      Diagnostics.err s!"canonical NEAR target context `{hostOpId.render}` has no handler"
  | .assert condition _ => .ok #[.localGet s!"v{condition.id}", .plain "i32.eqz",
      .if_ { insns := #[.unreachable] } { insns := #[] }]
  | .log event fields => do
      let header <- match eventStrings.find? (fun entry => entry.str == Layout.eventHeaderPoolString event) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR event header `{event}` is missing"
      let mut insns := Event.evtHeaderInsns header
      for (field, value) in fields, index in [0:fields.size] do
        let key <- match eventStrings.find? (fun entry => entry.str == Layout.eventFieldPoolString index field) with
          | some entry => pure entry
          | none => Diagnostics.err s!"canonical NEAR event field `{field}` is missing"
        insns := insns ++ (<- Event.evtFieldInsns event field key (canonicalNearGet value.id value.typeName)
          (canonicalNearType value.typeName))
      return insns ++ Event.evtFooterInsns
  | .promiseCreate result accountId methodName args deposit gas => do
      let account ← match promiseStrings.find? (fun entry => entry.str == accountId) with
        | some entry => pure entry
        | none => Diagnostics.err "canonical NEAR promise account id is missing from the data plan"
      let method ← match promiseStrings.find? (fun entry => entry.str == methodName) with
        | some entry => pure entry
        | none => Diagnostics.err "canonical NEAR promise method name is missing from the data plan"
      let mut argStores := #[]
      for index in [:args.size] do
        argStores := argStores ++ #[
          .i32Const (Memory.CROSSCALL_BUF + index),
          .i32Const args[index]!.toNat,
          .store "i32.store8" 0]
      let wordMod := 18446744073709551616
      return argStores ++ #[
        .i32Const Memory.RET_BUF, .i64Const (deposit % wordMod), .store "i64.store" 0,
        .i32Const (Memory.RET_BUF + 8), .i64Const (deposit / wordMod), .store "i64.store" 0,
        .i64Const account.len, .i64Const account.ptr,
        .i64Const method.len, .i64Const method.ptr,
        .i64Const args.size, .i64Const Memory.CROSSCALL_BUF,
        .i64Const Memory.RET_BUF, .i64Const gas,
        .call (HostABI.crosscallName plan.hostBridge.bridge), .localSet s!"v{result.id}"]
  | .portableCrosscall result accountId methodName args deposit gas => do
      let account ← match promiseStrings.find? (fun entry => entry.str == accountId) with
        | some entry => pure entry
        | none => Diagnostics.err "canonical NEAR crosscall account id is missing from the data plan"
      let method ← match promiseStrings.find? (fun entry => entry.str == methodName) with
        | some entry => pure entry
        | none => Diagnostics.err "canonical NEAR crosscall method name is missing from the data plan"
      let mut argStores := #[]
      for index in [:args.size] do
        argStores := argStores ++ #[
          .i32Const (Memory.CROSSCALL_BUF + index),
          .i32Const args[index]!.toNat,
          .store "i32.store8" 0]
      let wordMod := 18446744073709551616
      return argStores ++ #[
        .i32Const Memory.RET_BUF, .i64Const (deposit % wordMod), .store "i64.store" 0,
        .i32Const (Memory.RET_BUF + 8), .i64Const (deposit / wordMod), .store "i64.store" 0,
        .i64Const account.len, .i64Const account.ptr,
        .i64Const method.len, .i64Const method.ptr,
        .i64Const args.size, .i64Const Memory.CROSSCALL_BUF,
        .i64Const Memory.RET_BUF, .i64Const gas,
        .call (HostABI.crosscallName plan.hostBridge.bridge), .localSet s!"v{result.id}"] ++
        (if plan.hostBridge.bridge == .soroban then #[] else #[.localGet s!"v{result.id}", .call "promise_return"])
  | .promiseCreatePool result accountIndex methodIndex args deposit argNames =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseCreatePool is not supported on Soroban (NEAR-only pool invoke)"
      else
      let accountLenPtr :=
        if canonicalNearType accountIndex.typeName == .string then #[
          .localGet s!"v{accountIndex.id}_len", .plain "i64.extend_i32_u",
          .localGet s!"v{accountIndex.id}", .plain "i64.extend_i32_u"]
        else canonicalNearI64 accountIndex ++ #[.call Memory.crosscallPoolLenName] ++
          canonicalNearI64 accountIndex ++ #[.call Memory.crosscallPoolPtrName]
      return canonicalCrosscallArgs args argNames ++ canonicalDepositPtr deposit ++
        accountLenPtr ++
        canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolLenName] ++
        canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolPtrName] ++
        canonicalCrosscallArgsLenPtr args ++ #[
          .i64Const Memory.RET_BUF, .i64Const Memory.crosscallDefaultGas,
          .call "promise_create", .localSet s!"v{result.id}"]
  | .promiseThen result parent methodIndex args deposit argNames =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseThen is not supported on Soroban (NEAR-only promise callback)"
      else
        return canonicalCrosscallArgs args argNames ++ canonicalDepositPtr deposit ++
          canonicalNearI64 parent ++ #[.call Promise.promiseCurrentAccountName,
            .i32Const Memory.CTX_BUF, .plain "i64.extend_i32_u"] ++
          canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolLenName] ++
          canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolPtrName] ++
          canonicalCrosscallArgsLenPtr args ++ #[
            .i64Const Memory.RET_BUF, .i64Const Memory.crosscallDefaultGas,
            .call "promise_then", .localSet s!"v{result.id}",
            .localGet s!"v{result.id}", .call "promise_return"]
  | .promiseResultU64 result index =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseResultU64 is not supported on Soroban (NEAR-only)"
      else
        return canonicalNearI64 index ++ #[.call Promise.promiseResultU64Name,
          .localSet s!"v{result.id}"]
  | .promiseResultU128 result index =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseResultU128 is not supported on Soroban (NEAR-only)"
      else
        -- promiseResultU128 is void (stages PROMISE_RESULT_BUF); reload lo/hi
        -- and set the two-word u128 result local (mirrors the legacy path).
        return canonicalNearI64 index ++ #[.call Promise.promiseResultU128Name,
          .i32Const Memory.PROMISE_RESULT_BUF, .load "i64.load" 0,
          .i32Const (Memory.PROMISE_RESULT_BUF + 8), .load "i64.load" 0]
          ++ canonicalNearSet result.id result.typeName
  | .promiseResultsCount result =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseResultsCount is not supported on Soroban (NEAR-only)"
      else
        return #[.call "promise_results_count", .localSet s!"v{result.id}"]
  | .promiseResultStatus result index =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseResultStatus is not supported on Soroban (NEAR-only)"
      else
        return canonicalNearI64 index ++ #[.i64Const 0, .call "promise_result",
          .localSet s!"v{result.id}"]
  | .storageUsage result =>
      if plan.hostBridge.bridge != .near then
        Diagnostics.err "storageUsage is supported only on NEAR"
      else
        return #[.call "storage_usage", .localSet s!"v{result.id}"]
  | .promiseTransfer result account amount =>
      if plan.hostBridge.bridge != .near then
        Diagnostics.err "promiseTransfer is supported only on NEAR"
      else if canonicalNearType account.typeName != .string then
        Diagnostics.err "promiseTransfer account must be a runtime String"
      else if canonicalNearType amount.typeName != .u128 then
        Diagnostics.err "promiseTransfer amount must be U128"
      else
        return canonicalNearGet account.id account.typeName ++
          canonicalNearGet amount.id amount.typeName ++
          #[.call Promise.promiseTransferName, .localSet s!"v{result.id}"]

private def lowerCanonicalNearTerminator (blocks : Array NearBlockPlan)
    (entrypointName : String) (outputCodec : ProofForge.Backend.WasmHost.AbiPlan.Codec) :
    NearTerminatorPlan -> Except Diagnostics.EmitError (Array ProofForge.Compiler.Wasm.Insn)
  | .return values => match values[0]? with
      | some value =>
          pure <| if value.typeName == "promiseReturn" then #[.return_]
          else if outputCodec == .json then canonicalNearGet value.id value.typeName ++ #[
            .call (JsonReturn.helperName entrypointName), .return_]
          else match canonicalNearType value.typeName with
            | .hash => #[.i64Const 32, .localGet s!"v{value.id}", .plain "i64.extend_i32_u",
                .call "value_return", .return_]
            | .u32 => #[.localGet s!"v{value.id}", .call Types.returnU32Name, .return_]
            | .u128 => canonicalNearGet value.id value.typeName ++ #[
                .call Types.returnU128Name, .return_]
            | .bool => #[.localGet s!"v{value.id}", .call Types.returnBoolName, .return_]
            | _ => #[.localGet s!"v{value.id}", .call Types.returnU64Name, .return_]
      | none => pure #[.return_]
  | .revert _ => pure #[.unreachable]
  | .jump target args => do
      let some targetBlock := blocks.find? (·.id == target)
        | Diagnostics.err s!"canonical NEAR jump targets missing block {target}"
      unless targetBlock.params.size == args.size do
        Diagnostics.err s!"canonical NEAR jump to block {target} has {args.size} arguments, expected {targetBlock.params.size}"
      let pushArgs := args.flatMap fun arg => canonicalNearGet arg.id arg.typeName
      let bindParams := targetBlock.params.reverse.flatMap fun param =>
        canonicalNearSet param.id param.typeName
      pure <| pushArgs ++ bindParams ++ #[.i32Const target, .localSet "pc"]
  | .branch condition ifTrue ifFalse => pure #[.localGet s!"v{condition.id}",
      .if_ { insns := #[.i32Const ifTrue, .localSet "pc"] }
        { insns := #[.i32Const ifFalse, .localSet "pc"] }]

private def lowerCanonicalNearFunction (plan : NearModulePlan) (eventStrings literalStrings : Array Layout.StringInfo)
    (fn : NearFunctionPlan) : Except Diagnostics.EmitError ProofForge.Compiler.Wasm.Func := do
  if fn.blocks.isEmpty then Diagnostics.err s!"canonical NEAR function `{fn.name}` has no blocks"
  let abiPlan ← match plan.entrypointAbis.find? (fun abi => abi.name == fn.name) with
    | some abiPlan => pure abiPlan
    | none => Diagnostics.err s!"canonical NEAR function `{fn.name}` has no ABI plan"
  let values := (fn.params ++ fn.blocks.flatMap (fun block =>
    block.params ++ block.ops.flatMap fun op => match op with
      | .literal result _ | .stringLiteral result _ | .hashLiteral result .. | .boolLiteral result _ |
        .loadState result _ | .loadMap result .. |
        .arithmetic result .. | .compare result .. | .hash result _ | .hashTwoToOne result .. | .cast result _ |
        .structLit result .. |
        .context result _ | .hostContext result _ |
        .storageUsage result |
        .promiseCreate result .. | .portableCrosscall result .. | .promiseCreatePool result .. |
        .promiseThen result .. | .promiseTransfer result .. |
        .promiseResultU64 result .. | .promiseResultU128 result .. |
        .promiseResultsCount result | .promiseResultStatus result .. => #[result]
      | _ => #[])).foldl (fun acc value => if acc.any (fun old => old.id == value.id) then acc else acc.push value) #[]
  let authPrologue :=
    if plan.hostBridge.bridge == .soroban &&
        plan.surface.contextOps.any (fun op => op == .userId || op == .userIdHash || op == .signer) then
      #[.i32Const 0, .i32Const 0, .call "require_auth_for_args", .drop]
    else
      #[]
  let mut dispatch := #[]
  let promiseStrings := canonicalPromiseStrings plan
  for block in fn.blocks do
    let mut body := #[]
    for op in block.ops do
      body := body ++ (<- lowerCanonicalNearOp plan eventStrings promiseStrings literalStrings op)
    body := body ++ (<- lowerCanonicalNearTerminator fn.blocks fn.name abiPlan.outputCodec block.terminator)
    dispatch := dispatch ++ #[.localGet "pc", .i32Const block.id, .plain "i32.eq",
      .if_ { insns := body } { insns := #[] }]
  let inputParams := fn.params.map (fun value => (s!"v{value.id}", canonicalNearType value.typeName))
  let loweringParams := (abiPlan.params.zip fn.params).map fun (param, value) =>
    { param with name? := some s!"v{value.id}" }
  let loweringAbiPlan := { abiPlan with params := loweringParams }
  let wireParamNames := abiPlan.params.map (fun param => param.name?.getD "")
  let (paramPrologue, paramLocals) ←
    Params.loadParams #[] inputParams loweringAbiPlan plan.hostBridge.bridge (some wireParamNames)
  let pcLocal : ProofForge.Compiler.Wasm.Local := { name := "pc", type := .i32 }
  let locals := paramLocals.foldl
    (fun (acc : Array ProofForge.Compiler.Wasm.Local)
        (newLocal : ProofForge.Compiler.Wasm.Local) =>
      if acc.any (fun old => old.name == newLocal.name) then acc else acc.push newLocal)
    (#[pcLocal] ++ values.flatMap canonicalNearLocals)
  return {
    name := fn.name, exportName := some fn.name
    locals
    body := { insns := authPrologue ++ paramPrologue ++ #[.i32Const fn.blocks[0]!.id, .localSet "pc",
      .loop_ { insns := dispatch ++ #[.br 0] }] }
  }

/-- Canonical Wasm-host lowering boundary: consumes only the complete target
plan. The bridge is taken from the plan's hostBridge. Scalar and map helpers
are bridge-aware; hash/crosscall/promise/context helpers are still NEAR-only
(they produce empty arrays for contracts that don't use those features). -/
def lowerFromPlan (plan : NearModulePlan) : Except Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  let bridge := plan.hostBridge.bridge
  unless bridge == .near || plan.targetId == "wasm-near" do
    Diagnostics.err s!"canonical plan target `{plan.targetId}` does not match NEAR bridge"
  if bridge == .soroban &&
      (plan.surface.scalarReadTypes.contains .hash ||
       plan.surface.scalarWriteTypes.contains .hash ||
       plan.surface.u64IndexedReadTypes.contains .hash ||
       plan.surface.u64IndexedWriteTypes.contains .hash ||
       plan.surface.hashIndexedReadTypes.contains .hash ||
       plan.surface.hashIndexedWriteTypes.contains .hash) then
    Diagnostics.err "canonical Soroban lowering does not support 32-byte Hash storage with the scalar `_get` ABI"
  let eventStrings := canonicalEventStrings plan
  let literalStrings := canonicalLiteralStrings plan eventStrings
  let promiseStrings := canonicalPromiseStrings plan
  if promiseStrings.any (fun entry => entry.ptr + entry.len > Memory.ZERO_HASH_BUF) then
    Diagnostics.err "canonical NEAR promise string pool exceeds reserved memory"
  let funcs <- plan.functions.mapM (lowerCanonicalNearFunction plan eventStrings literalStrings)
  let scalarTypes := plan.layout.scalars.foldl (fun acc state =>
    if acc.contains state.type then acc else acc.push state.type) #[]
  let helperFuncs := scalarTypes.foldl (fun acc ty =>
    if ty == .hash then acc else
      if ty == .u128 then
        -- u128 scalar storage uses the two-word read/write helpers, not the
        -- single-word generic readFunc/writeFunc.
        let acc := if plan.surface.scalarReadTypes.contains ty then acc.push Scalar.readU128FuncNear else acc
        if plan.surface.scalarWriteTypes.contains ty then acc.push Scalar.writeU128FuncNear else acc
      else
        let acc := if plan.surface.scalarReadTypes.contains ty then acc.push (Scalar.readFunc ty bridge) else acc
        if plan.surface.scalarWriteTypes.contains ty then acc.push (Scalar.writeFunc ty bridge) else acc) #[]
  let mapHelpers := Map.mapHelperFuncsForModulePlan plan.surface bridge ++
    Map.mapHashHelperFuncsForModulePlan plan.surface bridge ++
    Map.mapStringHelperFuncsForModulePlan plan.surface bridge
  let hashHelpers := Hash.hashExprHelperFuncsForModulePlan plan.surface
  let hashStorageHelpers := Hash.hashStorageHelperFuncsForModulePlan plan.surface bridge
  let crosscallHelpers := Crosscall.crosscallArgsHelperFuncsForModulePlan plan.surface ++
    (if plan.surface.usesCrosscallArgs then
      Crosscall.crosscallPoolHelperFuncs (plan.layout.crosscallStrings.map fun entry =>
        { str := entry.str, ptr := entry.ptr, len := entry.len })
    else #[])
  let promiseHelpers := Promise.promiseHelperFuncsForModulePlan plan.surface
  let contextHelpers := Context.ctxHelperFuncsForModulePlan plan.surface bridge
  let strEqHelpers := StringCmp.strEqFuncsForModulePlan plan.surface
  let arrHeapHelpers := ArrayHeap.arrHeapHelperFuncsForModulePlan plan.surface defaultAllocator
  let returnFuncs :=
    (if plan.surface.returnTypes.contains .u64 || plan.surface.returnTypes.contains .address then
      #[Scalar.returnU64Func bridge] else #[]) ++
    (if plan.surface.returnTypes.contains .u32 then #[Scalar.returnU32Func bridge] else #[]) ++
    (if plan.surface.returnTypes.contains .u128 then #[Scalar.returnU128Func bridge] else #[]) ++
    (if plan.surface.returnTypes.contains .bool then #[Scalar.returnBoolFunc bridge] else #[])
  -- u128 arithmetic / comparison / formatter helpers are needed whenever any
  -- u128 value is used (scalar, map, arithmetic, comparison, events, crosscall).
  let usesU128 := plan.surface.scalarReadTypes.contains .u128 ||
    plan.surface.scalarWriteTypes.contains .u128 ||
    plan.surface.returnTypes.contains .u128 ||
    plan.surface.hashIndexedReadTypes.contains .u128 ||
    plan.surface.hashIndexedWriteTypes.contains .u128 ||
    plan.surface.u64IndexedReadTypes.contains .u128 ||
    plan.surface.u64IndexedWriteTypes.contains .u128
  let u128ArithHelpers := if usesU128 then Scalar.u128ArithFuncs else #[]
  let jsonReturnHelpers ← do
    let jsonAbis := plan.entrypointAbis.filter (fun abi => abi.outputJson?.isSome)
    if jsonAbis.isEmpty then pure #[] else
      let schemaFuncs ← jsonAbis.mapM fun abi => do
        let some schema := abi.outputJson?
          | Diagnostics.err s!"canonical NEAR JSON ABI `{abi.name}` is missing its output schema"
        match JsonReturn.buildReturnFunc abi.name plan.lowerCtxSeed.structs schema abi.returnType with
        | .ok func => pure func
        | .error message => Diagnostics.err s!"canonical NEAR JSON ABI `{abi.name}`: {message}"
      pure <| #[EmitWat.memcpyFunc, Event.fmtU64Func, Scalar.u128Divmod10Func,
        Scalar.u128FmtFunc] ++ JsonReturn.runtimeFuncs ++ schemaFuncs
  let jsonInputHelpers :=
    (if plan.entrypointAbis.any (fun abi =>
        abi.inputCodec == .json && abi.params.any (fun param =>
          param.type == .u128 || param.type == .u64 || param.type == .u32)) then
      #[Params.parseU128DecimalFunc]
    else #[]) ++
    (if plan.entrypointAbis.any (fun abi =>
        abi.inputCodec == .json && abi.params.any (fun param => param.type == .string)) then
      #[Params.parseJsonHex4Func, Params.writeJsonUtf8Func]
    else #[])
  let eventHelpers := if eventStrings.isEmpty then #[] else #[EmitWat.memcpyFunc] ++ Event.evtHelperFuncsForModulePlan plan.surface bridge
  let imports := Imports.importsForModulePlan plan.surface defaultAllocator false bridge
  let data := plan.layout.scalars.map (fun state => { offset := state.keyPtr, bytes := state.id : ProofForge.Compiler.Wasm.DataSegment }) ++
    plan.layout.maps.map (fun state => { offset := state.prefixPtr, bytes := state.id ++ ":" : ProofForge.Compiler.Wasm.DataSegment }) ++
    #[{ offset := Memory.TRUE_PTR, bytes := "true" },
      { offset := Memory.FALSE_PTR, bytes := "false" },
      { offset := Memory.HEX_LUT_PTR, bytes := "0123456789abcdef" }] ++
    (if eventStrings.isEmpty then #[] else #[{
      offset := Memory.EVT_PUNCT_BASE, bytes := "}]}"
    }]) ++ eventStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment }) ++
    literalStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment }) ++
    promiseStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment }) ++
    (if plan.surface.usesCrosscallArgs then
      plan.layout.crosscallStrings.map (fun entry =>
        { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment })
    else #[])
  return {
    imports := imports
    globals := (if Hash.modulePlanUsesHashAlloc plan.surface then #[Hash.hashPtrGlobalDecl] else #[]) ++
      (if eventStrings.isEmpty then #[] else Event.evtGlobals) ++
      (if plan.entrypointAbis.any (fun abi => abi.outputJson?.isSome) then
        #[JsonReturn.ptrGlobalDecl] else #[]) ++
      Crosscall.crosscallGlobalsForModulePlan plan.surface ++
      (if ArrayHeap.modulePlanUsesArrHeap plan.surface && !defaultAllocator.requiresHost then
        #[ArrayHeap.arrPtrGlobalDecl defaultAllocator.heapBase] else #[])
    funcs := (helperFuncs ++ hashStorageHelpers ++ mapHelpers ++ hashHelpers ++ crosscallHelpers ++ promiseHelpers ++ contextHelpers ++
      strEqHelpers ++ arrHeapHelpers ++ returnFuncs ++ eventHelpers ++ u128ArithHelpers ++
      jsonInputHelpers ++ jsonReturnHelpers ++ funcs).foldl
      (fun acc f => if acc.any (fun g => g.name == f.name) then acc else acc.push f) #[]
    memory := some { min := 1 }
    dataSegments := data }

end ProofForge.Backend.WasmHost.NearModulePlan
