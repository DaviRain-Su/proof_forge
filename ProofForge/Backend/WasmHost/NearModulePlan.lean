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

Step C (RFC 0014 Phase 4) makes the plan-driven path the ONLY lowering path.
The inline ad-hoc `Ctx` construction that previously lived at the top of
`EmitWat.lowerModule` is deleted; `EmitWat.lowerModule` now derives its `Ctx`
via `EmitWat.buildLowerCtx` → `EmitWat.Ctx.fromPlanSeed`, the same reconstruction
`NearModulePlan.Ctx.fromPlanSeed` uses here, so the `*ModulePlan` is the
authoritative source for lowering decisions and the two paths cannot drift.

Step B fills in the plan-driven lowering path:
- `NearLowerCtxSeed` carries the frozen scratch base addresses and read-only
  type metadata needed to reconstruct `EmitWat.Ctx`.
- `Ctx.fromPlanSeed` rebuilds an `EmitWat.Ctx` from the plan's seed + layout.
- `lowerModuleFromPlan` drives lowering by handing the reconstructed `Ctx` to
  the shared `EmitWat.lowerModuleCoreWithCtx` body, after running the same
  `EmitWat.validateScratchCapacities` gate the lowering entry runs, so the
  plan path and the lowering entry reject oversize scratch identically.

The dual-path parity check that landed in Step B/B.2 is retired in Step C:
there is now only one lowering path, so `Tests/NearModulePlan.lean` is a
single-path golden check (plan-driven WAT renders cleanly + the plan golden
diff pins the layout artifact).
-/

import ProofForge.IR.Contract
import ProofForge.IR.Allocator
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.ModulePlan
import ProofForge.Backend.WasmHost.NearAbiPlan
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Types
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Target.HostBridge
import ProofForge.Backend.WasmHost.HostABI
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Backend.WasmHost.Imports
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Hash
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

/-- Project the scalar-state subset of `mod.state` into plan entries, reusing
`EmitWat.stateLayout` (the exact function `EmitWat.lowerModule` calls) so the
pointers are byte-identical to the current inline computation. -/
def buildScalars (mod : Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Array NearStatePlan :=
  let layout :=
    if bridge == .near && moduleScalarsPackable mod then
      (stateLayoutPacked mod).1
    else
      stateLayout mod
  layout.map fun s =>
    { id := s.id, type := s.type, keyPtr := s.keyPtr, keyLen := s.keyLen,
      packOffset := s.packOffset, packed := s.packed }

/-- Project the map/array-state subset of `mod.state` into plan entries, reusing
`EmitWat.mapLayout`. -/
def buildMaps (mod : Module) : Array NearMapPlan :=
  (mapLayout mod).map fun m =>
    { id := m.id, keyType := m.keyType, valueType := m.valueType,
      prefixPtr := m.prefixPtr, prefixLen := m.prefixLen, isArray := m.isArray }

/-- Project the event/field-name string pool, reusing `EmitWat.stringPool`.
The end offset is returned by `stringInfoEnd` on the `StringInfo` array before
projection; callers should use `buildNearModulePlan` which handles that. -/
def buildStrings (mod : Module) : Array NearStringPoolEntry :=
  (stringPool mod).map fun s => { str := s.str, ptr := s.ptr, len := s.len }

/-- Project the panic-message pool, reusing `EmitWat.panicPool` with the same
`stringPoolEnd` argument `EmitWat.lowerModule` computes. -/
def buildPanics (mod : Module) (stringPoolEnd : Nat) : Array NearStringPoolEntry :=
  (panicPool mod stringPoolEnd).map fun s => { str := s.str, ptr := s.ptr, len := s.len }

/-- Project the NEAR crosscall string pool, reusing `EmitWat.crosscallStringInfos`
with the same `CROSSCALL_STRING_BASE` constant `EmitWat.lowerModule` uses. -/
def buildCrosscallStrings (mod : Module) : Array NearStringPoolEntry :=
  (crosscallStringInfos mod.nearCrosscallStrings CROSSCALL_STRING_BASE).map
    fun s => { str := s.str, ptr := s.ptr, len := s.len }

/-- Build the full `NearModulePlan` for a module. The `surface` reuses
`WasmNear.Plan.buildModulePlan` (already consumed by EmitWat); the `layout`
reuses the exact `EmitWat` layout functions so the plan is byte-compatible with
the current inline `Ctx`. -/
def buildNearModulePlan (mod : Module) : Except PlanError NearModulePlan := do
  let surface ← buildModulePlan mod
  let entrypointAbis ← match buildModulePlans mod with
    | .ok plans => pure plans
    | .error message => .error { message }
  let scalars := buildScalars mod
  let maps := buildMaps mod
  let strsInfos := stringPool mod
  let stringPoolEnd := stringInfoEnd STRING_BASE strsInfos
  let strs := strsInfos.map fun s => { str := s.str, ptr := s.ptr, len := s.len : NearStringPoolEntry }
  let panics := buildPanics mod stringPoolEnd
  let crosscallStrs := buildCrosscallStrings mod
  .ok {
    moduleName := mod.name,
    targetId := "wasm-near",
    artifactKind := "wasm-wat",
    irVersion := "portable-ir-v0",
    surface := surface,
    entrypointAbis := entrypointAbis,
    layout := {
      scalars := scalars,
      maps := maps,
      strings := strs,
      panics := panics,
      crosscallStrings := crosscallStrs,
      stringPoolEnd := stringPoolEnd
    },
    lowerCtxSeed := {
      keyBuf := KEY_BUF,
      mapkeyBuf := MAPKEY_BUF,
      stringBase := STRING_BASE,
      crosscallStringBase := CROSSCALL_STRING_BASE,
      structs := mod.structs,
      allocator := mod.allocator
    }
  }

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

/-- Reconstruct an `EmitWat.Ctx` from the plan's seed + layout. This is the
plan-driven `Ctx` builder: the layout arrays are projected back to
`StateInfo`/`MapInfo`/`StringInfo`, and the read-only `structs`/`allocator` come
from the seed. There is no lowering-local mutable state in `Ctx` (unlike
Solana's `locals`/`nextLabel`), so the whole `Ctx` is reconstructable from the
plan. The frozen scratch-region base addresses in the seed are carried for the
plan artifact's inspectability but are not needed for `Ctx` reconstruction (the
absolute pointers are baked into the layout arrays). -/
def Ctx.fromPlanSeed (seed : NearLowerCtxSeed) (layout : NearLayoutPlan)
    (entrypointAbis : Array EntrypointPlan := #[]) : EmitWat.Ctx :=
  let pack := layout.scalars.any (fun s => s.packed)
  let packSize :=
    layout.scalars.foldl (init := 0) fun acc s =>
      if s.packed then Nat.max acc (s.packOffset + scalarWidth s.type) else acc
  {
    scalars := layout.scalars.map (fun s =>
      { id := s.id, type := s.type, keyPtr := s.keyPtr, keyLen := s.keyLen,
        packOffset := s.packOffset, packed := s.packed : EmitWat.StateInfo })
    maps := layout.maps.map (fun m =>
      { id := m.id, keyType := m.keyType, valueType := m.valueType,
        prefixPtr := m.prefixPtr, prefixLen := m.prefixLen, isArray := m.isArray : EmitWat.MapInfo })
    strings := layout.strings.map (fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    panics := layout.panics.map (fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    crosscallStrings := layout.crosscallStrings.map (fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    structs := seed.structs
    allocator := seed.allocator
    entrypointAbis := entrypointAbis
    packScalars := pack
    packSize := packSize
  }

/-- Lower a module using a pre-built `NearModulePlan`. This is the Tier B
contract entry point: the lowering is a pure function of the plan (plus the IR
module's statement bodies). The reconstructed `Ctx` is handed to the shared
`EmitWat.lowerModuleCoreWithCtx` body — the exact same body `EmitWat.lowerModule`
uses (Step C made it the only path) — so the plan-driven output is identical to
the lowering entry's output. The surface `ModulePlan` is taken from the plan's
`surface` field. Runs `EmitWat.validateScratchCapacities` on the reconstructed
pools first so the plan path rejects oversize scratch exactly as the lowering
entry does. -/
def lowerModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  let ctx := Ctx.fromPlanSeed plan.lowerCtxSeed plan.layout plan.entrypointAbis
  EmitWat.validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  EmitWat.lowerModuleCoreWithCtx mod plan.surface ctx

/-- Render a module to WAT text via the plan-driven path. -/
def renderModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError String := do
  let m ← lowerModuleFromPlan mod plan
  .ok (ProofForge.Compiler.Wasm.Printer.render m)

private def canonicalNearType (name : String) : ValueType :=
  if name.endsWith "bool" then .bool
  else if name.endsWith "u32" then .u32
  else if name.endsWith "hash" then .hash
  else .u64

private def canonicalNearLocal (value : NearValuePlan) : ProofForge.Compiler.Wasm.Local :=
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
            for value in #[Layout.eventHeaderPoolString event] ++ fields.map (fun field => Layout.eventFieldPoolString field.fst) do
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

private def canonicalCrosscallArgs (args : Array NearValuePlan) : Array ProofForge.Compiler.Wasm.Insn := Id.run do
  if args.isEmpty then
    return #[]
  let mut insns := #[.call Crosscall.crosscallArgsStartName, .i32Const 0x5b,
    .call Crosscall.crosscallArgsPutcName]
  for index in [:args.size] do
    if index > 0 then
      insns := insns ++ #[.i32Const 0x2c, .call Crosscall.crosscallArgsPutcName]
    let arg := args[index]!
    if arg.typeName.endsWith "bool" then
      insns := insns ++ #[.localGet s!"v{arg.id}", .call Crosscall.crosscallArgsPutboolName]
    else if arg.typeName.endsWith "hash" then
      insns := insns ++ #[.localGet s!"v{arg.id}", .call Crosscall.crosscallArgsPuthashName]
    else
      insns := insns ++ #[.localGet s!"v{arg.id}"]
      if canonicalNearType arg.typeName == .u32 then
        insns := insns ++ #[.plain "i64.extend_i32_u"]
      insns := insns ++ #[.call Crosscall.crosscallArgsPutu64Name]
  insns ++ #[.i32Const 0x5d, .call Crosscall.crosscallArgsPutcName]

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
    (eventStrings promiseStrings : Array Layout.StringInfo) :
    NearOpPlan -> Except Diagnostics.EmitError (Array ProofForge.Compiler.Wasm.Insn)
  | .literal result value => .ok #[.const (Types.wasmTypeOf (canonicalNearType result.typeName)) (toString value), .localSet s!"v{result.id}"]
  | .hashLiteral result a b c d => .ok #[
      .i64Const a, .i64Const b, .i64Const c, .i64Const d,
      .call Hash.hashMakeName, .localSet s!"v{result.id}"]
  | .boolLiteral result value => .ok #[.i32Const (if value then 1 else 0), .localSet s!"v{result.id}"]
  | .loadState result stateId => do
      let state <- match canonicalNearState? plan stateId with
        | some state => pure state
        | none => Diagnostics.err s!"canonical NEAR references unknown scalar state {stateId}"
      let (insns, _) := Scalar.storageScalarReadInsns state
      return insns ++ #[.localSet s!"v{result.id}"]
  | .storeState stateId value => do
      let state <- match canonicalNearState? plan stateId with
        | some state => pure state
        | none => Diagnostics.err s!"canonical NEAR references unknown scalar state {stateId}"
      Scalar.storageScalarWriteInsns #[] state state.id #[.localGet s!"v{value.id}"]
        (canonicalNearType value.typeName)
  | .loadMap result stateId key => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.coreId? == some stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let readCall ← Map.mapReadCall mapInfo mapInfo.id
      let (instructions, _) := Map.mapReadValueInsns mapInfo #[.localGet s!"v{key.id}"] readCall
      return instructions ++ #[.localSet s!"v{result.id}"]
  | .storeMap stateId key value => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.coreId? == some stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let writeCall ← Map.mapWriteCall mapInfo
      let (instructions, _) ← Map.mapWriteValueInsns mapInfo mapInfo.id
        #[.localGet s!"v{key.id}"] #[.localGet s!"v{value.id}"] writeCall mapInfo.valueType
      return instructions ++ #[.drop]
  | .arithmetic result op checked lhs rhs =>
      let ty := canonicalNearType result.typeName
      let calculation := #[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}",
        .plain (canonicalNearArithmetic ty op), .localSet s!"v{result.id}"]
      if !checked then .ok calculation else
        match op with
        | .add => .ok (calculation ++ #[.localGet s!"v{result.id}", .localGet s!"v{lhs.id}",
            .plain (Types.widthOf ty ++ ".lt_u"), .if_ { insns := #[.unreachable] } { insns := #[] }])
        | .sub => .ok (#[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}",
            .plain (Types.widthOf ty ++ ".lt_u"), .if_ { insns := #[.unreachable] } { insns := #[] }] ++ calculation)
        | .div | .mod => .ok (#[.localGet s!"v{rhs.id}",
            .plain (Types.widthOf ty ++ ".eqz"), .if_ { insns := #[.unreachable] } { insns := #[] }] ++ calculation)
        | .mul => .ok (calculation ++ #[
            .localGet s!"v{rhs.id}", .plain (Types.widthOf ty ++ ".eqz"),
            .if_ { insns := #[] } { insns := #[
              .localGet s!"v{result.id}", .localGet s!"v{rhs.id}",
              .plain (Types.widthOf ty ++ ".div_u"), .localGet s!"v{lhs.id}",
              .plain (Types.widthOf ty ++ ".ne"),
              .if_ { insns := #[.unreachable] } { insns := #[] }] }])
        | _ => .ok calculation
  | .compare result op lhs rhs =>
      let ty := canonicalNearType lhs.typeName
      if ty == .hash && (op == .eq || op == .ne) then
        .ok (#[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}", .call Hash.hashEqName] ++
          (if op == .ne then #[.plain "i32.eqz"] else #[]) ++ #[.localSet s!"v{result.id}"])
      else
        .ok #[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}",
          .plain (canonicalNearCompare ty op), .localSet s!"v{result.id}"]
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
      else if field.endsWith "origin" then
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
    else if field.endsWith "origin" then
      .ok #[.call Context.ctxSignerName, .localSet s!"v{result.id}"]
    else if field.endsWith "value" then
      .ok #[.i64Const Memory.RET_BUF, .call "attached_deposit",
        .i32Const Memory.RET_BUF, .load "i64.load" 0, .localSet s!"v{result.id}"]
    else if field.endsWith "sender" then
      .ok #[.call Context.ctxUserIdName, .localSet s!"v{result.id}"]
    else if field.endsWith "contractAddress" then
      .ok #[.call Context.ctxContractIdName, .localSet s!"v{result.id}"]
    else Diagnostics.err s!"canonical NEAR context `{field}` has no handler"
  | .assert condition _ => .ok #[.localGet s!"v{condition.id}", .plain "i32.eqz",
      .if_ { insns := #[.unreachable] } { insns := #[] }]
  | .log event fields => do
      let header <- match eventStrings.find? (fun entry => entry.str == Layout.eventHeaderPoolString event) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR event header `{event}` is missing"
      let mut insns := Event.evtHeaderInsns header
      for (field, value) in fields do
        let key <- match eventStrings.find? (fun entry => entry.str == Layout.eventFieldPoolString field) with
          | some entry => pure entry
          | none => Diagnostics.err s!"canonical NEAR event field `{field}` is missing"
        insns := insns ++ (<- Event.evtFieldInsns field key #[.localGet s!"v{value.id}"]
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
  | .promiseCreatePool result accountIndex methodIndex args deposit =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseCreatePool is not supported on Soroban (NEAR-only pool invoke)"
      else
      return canonicalCrosscallArgs args ++ canonicalDepositPtr deposit ++
        canonicalNearI64 accountIndex ++ #[.call Memory.crosscallPoolLenName] ++
        canonicalNearI64 accountIndex ++ #[.call Memory.crosscallPoolPtrName] ++
        canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolLenName] ++
        canonicalNearI64 methodIndex ++ #[.call Memory.crosscallPoolPtrName] ++
        canonicalCrosscallArgsLenPtr args ++ #[
          .i64Const Memory.RET_BUF, .i64Const Memory.crosscallDefaultGas,
          .call "promise_create", .localSet s!"v{result.id}"]
  | .promiseThen result parent methodIndex args deposit =>
      if plan.hostBridge.bridge == .soroban then
        Diagnostics.err "promiseThen is not supported on Soroban (NEAR-only promise callback)"
      else
        return canonicalCrosscallArgs args ++ canonicalDepositPtr deposit ++
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

private def lowerCanonicalNearTerminator (blocks : Array NearBlockPlan) :
    NearTerminatorPlan -> Except Diagnostics.EmitError (Array ProofForge.Compiler.Wasm.Insn)
  | .return values => match values[0]? with
      | some value =>
          pure <| if value.typeName == "promiseReturn" then #[.return_]
          else match canonicalNearType value.typeName with
            | .hash => #[.i64Const 32, .localGet s!"v{value.id}", .plain "i64.extend_i32_u",
                .call "value_return", .return_]
            | .u32 => #[.localGet s!"v{value.id}", .call Types.returnU32Name, .return_]
            | .bool => #[.localGet s!"v{value.id}", .call Types.returnBoolName, .return_]
            | _ => #[.localGet s!"v{value.id}", .call Types.returnU64Name, .return_]
      | none => pure #[.return_]
  | .revert _ => pure #[.unreachable]
  | .jump target args => do
      let some targetBlock := blocks.find? (·.id == target)
        | Diagnostics.err s!"canonical NEAR jump targets missing block {target}"
      unless targetBlock.params.size == args.size do
        Diagnostics.err s!"canonical NEAR jump to block {target} has {args.size} arguments, expected {targetBlock.params.size}"
      let pushArgs := args.map fun arg => .localGet s!"v{arg.id}"
      let bindParams := targetBlock.params.reverse.map fun param => .localSet s!"v{param.id}"
      pure <| pushArgs ++ bindParams ++ #[.i32Const target, .localSet "pc"]
  | .branch condition ifTrue ifFalse => pure #[.localGet s!"v{condition.id}",
      .if_ { insns := #[.i32Const ifTrue, .localSet "pc"] }
        { insns := #[.i32Const ifFalse, .localSet "pc"] }]

private def lowerCanonicalNearFunction (plan : NearModulePlan) (eventStrings : Array Layout.StringInfo)
    (fn : NearFunctionPlan) : Except Diagnostics.EmitError ProofForge.Compiler.Wasm.Func := do
  if fn.blocks.isEmpty then Diagnostics.err s!"canonical NEAR function `{fn.name}` has no blocks"
  let values := (fn.params ++ fn.blocks.flatMap (fun block =>
    block.params ++ block.ops.flatMap fun op => match op with
      | .literal result _ | .hashLiteral result .. | .boolLiteral result _ | .loadState result _ | .loadMap result .. |
        .arithmetic result .. | .compare result .. | .hash result _ | .hashTwoToOne result .. | .cast result _ |
        .context result _ |
        .promiseCreate result .. | .portableCrosscall result .. | .promiseCreatePool result .. |
        .promiseThen result .. | .promiseResultU64 result .. |
        .promiseResultsCount result | .promiseResultStatus result .. => #[result]
      | _ => #[])).foldl (fun acc value => if acc.any (fun old => old.id == value.id) then acc else acc.push value) #[]
  let authPrologue :=
    if plan.hostBridge.bridge == .soroban &&
        plan.surface.contextOps.any (fun op => op == .userId || op == .userIdHash || op == .origin) then
      #[.i32Const 0, .i32Const 0, .call "require_auth_for_args", .drop]
    else
      #[]
  let mut dispatch := #[]
  let promiseStrings := canonicalPromiseStrings plan
  for block in fn.blocks do
    let mut body := #[]
    for op in block.ops do
      body := body ++ (<- lowerCanonicalNearOp plan eventStrings promiseStrings op)
    body := body ++ (<- lowerCanonicalNearTerminator fn.blocks block.terminator)
    dispatch := dispatch ++ #[.localGet "pc", .i32Const block.id, .plain "i32.eq",
      .if_ { insns := body } { insns := #[] }]
  let abiPlan ← match plan.entrypointAbis.find? (fun abi => abi.name == fn.name) with
    | some abiPlan => pure abiPlan
    | none => Diagnostics.err s!"canonical NEAR function `{fn.name}` has no ABI plan"
  let inputParams := fn.params.map (fun value => (s!"v{value.id}", canonicalNearType value.typeName))
  let loweringParams := (abiPlan.params.zip fn.params).map fun (param, value) =>
    { param with name? := some s!"v{value.id}" }
  let loweringAbiPlan := { abiPlan with params := loweringParams }
  let (paramPrologue, _) ← Params.loadParams #[] inputParams loweringAbiPlan plan.hostBridge.bridge
  return {
    name := fn.name, exportName := some fn.name
    locals := #[{ name := "pc", type := .i32 }] ++ values.map canonicalNearLocal
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
  let promiseStrings := canonicalPromiseStrings plan
  if promiseStrings.any (fun entry => entry.ptr + entry.len > Memory.ZERO_HASH_BUF) then
    Diagnostics.err "canonical NEAR promise string pool exceeds reserved memory"
  let funcs <- plan.functions.mapM (lowerCanonicalNearFunction plan eventStrings)
  let scalarTypes := plan.layout.scalars.foldl (fun acc state =>
    if acc.contains state.type then acc else acc.push state.type) #[]
  let helperFuncs := scalarTypes.foldl (fun acc ty =>
    if ty == .hash then acc else
      let acc := if plan.surface.scalarReadTypes.contains ty then acc.push (Scalar.readFunc ty bridge) else acc
      if plan.surface.scalarWriteTypes.contains ty then acc.push (Scalar.writeFunc ty bridge) else acc) #[]
  let mapHelpers := Map.mapHelperFuncsForModulePlan plan.surface bridge ++
    Map.mapHashHelperFuncsForModulePlan plan.surface bridge
  let hashHelpers := Hash.hashExprHelperFuncsForModulePlan plan.surface
  let hashStorageHelpers := Hash.hashStorageHelperFuncsForModulePlan plan.surface bridge
  let crosscallHelpers := Crosscall.crosscallArgsHelperFuncsForModulePlan plan.surface ++
    (if plan.surface.usesCrosscallArgs then
      Crosscall.crosscallPoolHelperFuncs (plan.layout.crosscallStrings.map fun entry =>
        { str := entry.str, ptr := entry.ptr, len := entry.len })
    else #[])
  let promiseHelpers := Promise.promiseHelperFuncsForModulePlan plan.surface
  let contextHelpers := Context.ctxHelperFuncsForModulePlan plan.surface bridge
  let returnFuncs := (if plan.surface.returnTypes.contains .u64 then #[Scalar.returnU64Func bridge] else #[]) ++
    (if plan.surface.returnTypes.contains .u32 then #[Scalar.returnU32Func bridge] else #[]) ++
    (if plan.surface.returnTypes.contains .bool then #[Scalar.returnBoolFunc bridge] else #[])
  let eventHelpers := if eventStrings.isEmpty then #[] else #[EmitWat.memcpyFunc] ++ Event.evtHelperFuncsForModulePlan plan.surface bridge
  let imports := Imports.importsForModulePlan plan.surface defaultAllocator false bridge
  let data := plan.layout.scalars.map (fun state => { offset := state.keyPtr, bytes := state.id : ProofForge.Compiler.Wasm.DataSegment }) ++
    plan.layout.maps.map (fun state => { offset := state.prefixPtr, bytes := state.id ++ ":" : ProofForge.Compiler.Wasm.DataSegment }) ++
    #[{ offset := Memory.TRUE_PTR, bytes := "true" },
      { offset := Memory.FALSE_PTR, bytes := "false" },
      { offset := Memory.HEX_LUT_PTR, bytes := "0123456789abcdef" }] ++
    (if eventStrings.isEmpty then #[] else #[{
      offset := Memory.EVT_PUNCT_BASE, bytes := "{\"event\":\"" ++ "\"" ++ ",\"" ++ "\":" ++ "}"
    }]) ++ eventStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment }) ++
    promiseStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment }) ++
    (if plan.surface.usesCrosscallArgs then
      plan.layout.crosscallStrings.map (fun entry =>
        { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment })
    else #[])
  return {
    imports := imports
    globals := (if Hash.modulePlanUsesHashAlloc plan.surface then #[Hash.hashPtrGlobalDecl] else #[]) ++
      (if eventStrings.isEmpty then #[] else Event.evtGlobals) ++
      Crosscall.crosscallGlobalsForModulePlan plan.surface
    funcs := helperFuncs ++ hashStorageHelpers ++ mapHelpers ++ hashHelpers ++ crosscallHelpers ++ promiseHelpers ++ contextHelpers ++
      returnFuncs ++ eventHelpers ++ funcs
    memory := some { min := 1 }
    dataSegments := data }

end ProofForge.Backend.WasmHost.NearModulePlan
