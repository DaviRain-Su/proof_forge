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
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Types
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Target.HostBridge
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Backend.WasmHost.Imports
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.Event

namespace ProofForge.Backend.WasmHost.NearModulePlan

open ProofForge.IR
open ProofForge.Backend.WasmHost.Types
open ProofForge.Target.HostBridge
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.EmitWat

/-- One scalar state slot's plan: the storage key pointer in linear memory.
Carries the `ValueType` so `Ctx.fromPlanSeed` can rebuild `StateInfo.type`

(which drives `readName`/`readHashName` dispatch). -/
structure NearStatePlan where
  id : String
  type : ValueType
  keyPtr : Nat
  keyLen : Nat
  packOffset : Nat := 0
  packed : Bool := false
  deriving Repr, BEq

/-- One map/array state slot's plan: the `id ++ ":"` prefix pointer. Carries
the key/value `ValueType`s so `Ctx.fromPlanSeed` can rebuild `MapInfo`. -/
structure NearMapPlan where
  id : String
  keyType : ValueType
  valueType : ValueType
  prefixPtr : Nat
  prefixLen : Nat
  isArray : Bool
  deriving Repr, BEq

/-- One string-pool entry (event/field name, panic message, or crosscall string). -/
structure NearStringPoolEntry where
  str : String
  ptr : Nat
  len : Nat
  deriving Repr, BEq

/-- The data-layout surface: everything `EmitWat.Ctx` holds that is a deterministic
function of the module. These six fields are currently rebuilt inline at the top of
`EmitWat.lowerModule`; the plan promotes them to an inspectable artifact. -/
structure NearLayoutPlan where
  scalars : Array NearStatePlan
  maps : Array NearMapPlan
  strings : Array NearStringPoolEntry
  panics : Array NearStringPoolEntry
  crosscallStrings : Array NearStringPoolEntry
  stringPoolEnd : Nat
  deriving Repr, BEq

structure NearValuePlan where
  id : Nat
  typeName : String
  deriving Repr, BEq, Inhabited

inductive NearArithmeticPlan where
  | add | sub | mul | div | mod | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
  deriving Repr, BEq, Inhabited

inductive NearComparePlan where
  | eq | ne | lt | le | gt | ge
  deriving Repr, BEq, Inhabited

inductive NearOpPlan where
  | literal (result : NearValuePlan) (value : Nat)
  | boolLiteral (result : NearValuePlan) (value : Bool)
  | loadState (result : NearValuePlan) (stateId : Nat)
  | storeState (stateId : Nat) (value : NearValuePlan)
  | loadMap (result : NearValuePlan) (stateId : Nat) (key : NearValuePlan)
  | storeMap (stateId : Nat) (key value : NearValuePlan)
  | arithmetic (result : NearValuePlan) (op : NearArithmeticPlan)
      (checked : Bool) (lhs rhs : NearValuePlan)
  | compare (result : NearValuePlan) (op : NearComparePlan) (lhs rhs : NearValuePlan)
  | context (result : NearValuePlan) (field : String)
  | log (eventName : String) (fields : Array (String × NearValuePlan))
  | assert (condition : NearValuePlan) (errorCode : Nat)
  deriving Repr, BEq, Inhabited

inductive NearTerminatorPlan where
  | jump (target : Nat) (args : Array NearValuePlan)
  | branch (condition : NearValuePlan) (ifTrue ifFalse : Nat)
  | return (values : Array NearValuePlan)
  | revert (errorCode : Nat)
  deriving Repr, BEq, Inhabited

structure NearBlockPlan where
  id : Nat
  params : Array NearValuePlan
  ops : Array NearOpPlan
  terminator : NearTerminatorPlan
  deriving Repr, BEq, Inhabited

structure NearFunctionPlan where
  id : Nat
  name : String
  params : Array NearValuePlan
  returnType : String
  blocks : Array NearBlockPlan
  deriving Repr, BEq, Inhabited

/-- The frozen scratch-region base addresses (constants in `EmitWat`). The seed
makes them plan-owned so the lowering is a pure function of the plan + IR module,
mirroring `SolanaLowerCtxSeed`. -/
structure NearLowerCtxSeed where
  keyBuf : Nat
  mapkeyBuf : Nat
  stringBase : Nat
  crosscallStringBase : Nat
  structs : Array StructDecl
  allocator : AllocatorConfig
  deriving Repr

/-- The top-level plan. `surface` is the existing `WasmNear.Plan.ModulePlan`
(host imports / helpers); `layout` is the new data-layout surface; `lowerCtxSeed`
carries the frozen base addresses and read-only type metadata. -/
structure NearModulePlan where
  moduleName : String
  targetId : String
  artifactKind : String
  irVersion : String
  surface : ModulePlan
  layout : NearLayoutPlan
  functions : Array NearFunctionPlan := #[]
  lowerCtxSeed : NearLowerCtxSeed
  deriving Repr

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
def Ctx.fromPlanSeed (seed : NearLowerCtxSeed) (layout : NearLayoutPlan) : EmitWat.Ctx :=
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
  let ctx := Ctx.fromPlanSeed plan.lowerCtxSeed plan.layout
  EmitWat.validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  EmitWat.lowerModuleCoreWithCtx mod plan.surface ctx

/-- Render a module to WAT text via the plan-driven path. -/
def renderModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError String := do
  let m ← lowerModuleFromPlan mod plan
  .ok (ProofForge.Compiler.Wasm.Printer.render m)

private def canonicalNearType (name : String) : ValueType :=
  if name.endsWith "bool" then .bool else if name.endsWith "u32" then .u32 else .u64

private def canonicalNearLocal (value : NearValuePlan) : ProofForge.Compiler.Wasm.Local :=
  { name := s!"v{value.id}", type := Types.wasmTypeOf (canonicalNearType value.typeName) }

private def canonicalNearState? (plan : NearModulePlan) (id : Nat) : Option Layout.StateInfo :=
  plan.layout.scalars.find? (fun state => state.id == toString id) |>.map fun state => {
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

private def lowerCanonicalNearOp (plan : NearModulePlan) (eventStrings : Array Layout.StringInfo) :
    NearOpPlan -> Except Diagnostics.EmitError (Array ProofForge.Compiler.Wasm.Insn)
  | .literal result value => .ok #[.const (Types.wasmTypeOf (canonicalNearType result.typeName)) (toString value), .localSet s!"v{result.id}"]
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
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.id == toString stateId) with
        | some entry => pure entry
        | none => Diagnostics.err s!"canonical NEAR references unknown map state {stateId}"
      let mapInfo : Layout.MapInfo := {
        id := mapPlan.id, keyType := mapPlan.keyType, valueType := mapPlan.valueType,
        prefixPtr := mapPlan.prefixPtr, prefixLen := mapPlan.prefixLen, isArray := false }
      let readCall ← Map.mapReadCall mapInfo mapInfo.id
      let (instructions, _) := Map.mapReadValueInsns mapInfo #[.localGet s!"v{key.id}"] readCall
      return instructions ++ #[.localSet s!"v{result.id}"]
  | .storeMap stateId key value => do
      let mapPlan ← match plan.layout.maps.find? (fun entry => entry.id == toString stateId) with
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
      .ok #[.localGet s!"v{lhs.id}", .localGet s!"v{rhs.id}",
        .plain (canonicalNearCompare ty op), .localSet s!"v{result.id}"]
  | .context result field =>
      if field.endsWith "blockNumber" then
        .ok #[.call "block_index", .localSet s!"v{result.id}"]
      else if field.endsWith "blockTimestamp" then
        .ok #[.call "block_timestamp", .localSet s!"v{result.id}"]
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

private def lowerCanonicalNearTerminator : NearTerminatorPlan -> Array ProofForge.Compiler.Wasm.Insn
  | .return values => match values[0]? with
      | some value => #[.localGet s!"v{value.id}", .call (match canonicalNearType value.typeName with
          | .u32 => Types.returnU32Name | .bool => Types.returnBoolName | _ => Types.returnU64Name), .return_]
      | none => #[.return_]
  | .revert _ => #[.unreachable]
  | .jump target _ => #[.i32Const target, .localSet "pc"]
  | .branch condition ifTrue ifFalse => #[.localGet s!"v{condition.id}",
      .if_ { insns := #[.i32Const ifTrue, .localSet "pc"] }
        { insns := #[.i32Const ifFalse, .localSet "pc"] }]

private def lowerCanonicalNearFunction (plan : NearModulePlan) (eventStrings : Array Layout.StringInfo)
    (fn : NearFunctionPlan) : Except Diagnostics.EmitError ProofForge.Compiler.Wasm.Func := do
  if fn.blocks.isEmpty then Diagnostics.err s!"canonical NEAR function `{fn.name}` has no blocks"
  let values := (fn.params ++ fn.blocks.flatMap (fun block =>
    block.params ++ block.ops.flatMap fun op => match op with
      | .literal result _ | .boolLiteral result _ | .loadState result _ | .loadMap result .. |
        .arithmetic result .. | .compare result .. | .context result _ => #[result]
      | _ => #[])).foldl (fun acc value => if acc.any (fun old => old.id == value.id) then acc else acc.push value) #[]
  let mut dispatch := #[]
  for block in fn.blocks do
    let mut body := #[]
    for op in block.ops do body := body ++ (<- lowerCanonicalNearOp plan eventStrings op)
    body := body ++ lowerCanonicalNearTerminator block.terminator
    dispatch := dispatch ++ #[.localGet "pc", .i32Const block.id, .plain "i32.eq",
      .if_ { insns := body } { insns := #[] }]
  let inputParams := fn.params.map (fun value => (s!"v{value.id}", canonicalNearType value.typeName))
  let (paramPrologue, _) <- Params.loadParams #[] inputParams
  return {
    name := fn.name, exportName := some fn.name
    locals := #[{ name := "pc", type := .i32 }] ++ values.map canonicalNearLocal
    body := { insns := paramPrologue ++ #[.i32Const fn.blocks[0]!.id, .localSet "pc",
      .loop_ { insns := dispatch ++ #[.br 0] }] }
  }

/-- Canonical NEAR lowering boundary: consumes only the complete target plan. -/
def lowerFromPlan (plan : NearModulePlan) : Except Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  unless plan.targetId == "wasm-near" do Diagnostics.err "canonical NEAR plan has wrong target"
  let eventStrings := canonicalEventStrings plan
  let funcs <- plan.functions.mapM (lowerCanonicalNearFunction plan eventStrings)
  let scalarTypes := plan.layout.scalars.foldl (fun acc state =>
    if acc.contains state.type then acc else acc.push state.type) #[]
  let helperFuncs := scalarTypes.foldl (fun acc ty =>
    let acc := if plan.surface.scalarReadTypes.contains ty then acc.push (Scalar.readFunc ty) else acc
    if plan.surface.scalarWriteTypes.contains ty then acc.push (Scalar.writeFunc ty) else acc) #[]
  let mapHelpers := Map.mapHelperFuncsForModulePlan plan.surface
  let returnFuncs := (if plan.surface.returnTypes.contains .u64 then #[Scalar.returnU64Func] else #[]) ++
    (if plan.surface.returnTypes.contains .u32 then #[Scalar.returnU32Func] else #[]) ++
    (if plan.surface.returnTypes.contains .bool then #[Scalar.returnBoolFunc] else #[])
  let eventHelpers := if eventStrings.isEmpty then #[] else #[EmitWat.memcpyFunc] ++ Event.evtHelperFuncsForModulePlan plan.surface
  let imports := Imports.importsForModulePlan plan.surface defaultAllocator false
  let data := plan.layout.scalars.map (fun state => { offset := state.keyPtr, bytes := state.id : ProofForge.Compiler.Wasm.DataSegment }) ++
    plan.layout.maps.map (fun state => { offset := state.prefixPtr, bytes := state.id ++ ":" : ProofForge.Compiler.Wasm.DataSegment }) ++
    #[{ offset := Memory.TRUE_PTR, bytes := "true" },
      { offset := Memory.FALSE_PTR, bytes := "false" },
      { offset := Memory.HEX_LUT_PTR, bytes := "0123456789abcdef" }] ++
    (if eventStrings.isEmpty then #[] else #[{
      offset := Memory.EVT_PUNCT_BASE, bytes := "{\"event\":\"" ++ "\"" ++ ",\"" ++ "\":" ++ "}"
    }]) ++ eventStrings.map (fun entry => { offset := entry.ptr, bytes := entry.str : ProofForge.Compiler.Wasm.DataSegment })
  return { imports := imports, globals := if eventStrings.isEmpty then #[] else Event.evtGlobals, funcs := helperFuncs ++ mapHelpers ++ returnFuncs ++ eventHelpers ++ funcs, memory := some { min := 1 }, dataSegments := data }

end ProofForge.Backend.WasmHost.NearModulePlan
