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
- `Ctx.fromPlanSeed` rebuilds an `EmitWat.Ctx` from the plan's seed + layout
  (delegating to `EmitWat.Ctx.fromPlanSeed`, which owns the `Ctx` type).
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
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Compiler.Wasm.Printer

namespace ProofForge.Backend.WasmNear.NearModulePlan

open ProofForge.IR
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.EmitWat

/-- One scalar state slot's plan: the storage key pointer in linear memory.
Carries the `ValueType` so `Ctx.fromPlanSeed` can rebuild `StateInfo.type`
(which drives `readName`/`readHashName` dispatch). -/
structure NearStatePlan where
  id : String
  type : ValueType
  keyPtr : Nat
  keyLen : Nat
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
  lowerCtxSeed : NearLowerCtxSeed
  deriving Repr

/-- Render a `ValueType` using the IR's own naming (so the plan text matches the
IR module, not the Wasm type). -/
def renderValueType (vt : ValueType) : String := vt.name

/-- Project the scalar-state subset of `mod.state` into plan entries, reusing
`EmitWat.stateLayout` (the exact function `EmitWat.lowerModule` calls) so the
pointers are byte-identical to the current inline computation. -/
def buildScalars (mod : Module) : Array NearStatePlan :=
  (stateLayout mod).map fun s =>
    { id := s.id, type := s.type, keyPtr := s.keyPtr, keyLen := s.keyLen }

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
plan. Delegates to `EmitWat.Ctx.fromPlanSeed` (the `Ctx` owner) so the plan path
and the `EmitWat.lowerModule` lowering entry share one reconstruction path and
cannot drift. The frozen scratch-region base addresses in the seed are carried
for the plan artifact's inspectability but are not needed for `Ctx`
reconstruction (the absolute pointers are baked into the layout arrays). -/
def Ctx.fromPlanSeed (seed : NearLowerCtxSeed) (layout : NearLayoutPlan) : EmitWat.Ctx :=
  EmitWat.Ctx.fromPlanSeed
    (layout.scalars.map fun s =>
      { id := s.id, type := s.type, keyPtr := s.keyPtr, keyLen := s.keyLen : EmitWat.StateInfo })
    (layout.maps.map fun m =>
      { id := m.id, keyType := m.keyType, valueType := m.valueType,
        prefixPtr := m.prefixPtr, prefixLen := m.prefixLen, isArray := m.isArray : EmitWat.MapInfo })
    (layout.strings.map fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    (layout.panics.map fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    (layout.crosscallStrings.map fun e =>
      { str := e.str, ptr := e.ptr, len := e.len : EmitWat.StringInfo })
    seed.structs seed.allocator

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
    Except EmitWat.EmitError ProofForge.Compiler.Wasm.Module := do
  let ctx := Ctx.fromPlanSeed plan.lowerCtxSeed plan.layout
  EmitWat.validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  EmitWat.lowerModuleCoreWithCtx mod plan.surface ctx

/-- Render a module to WAT text via the plan-driven path. -/
def renderModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except EmitWat.EmitError String := do
  let m ← lowerModuleFromPlan mod plan
  .ok (ProofForge.Compiler.Wasm.Printer.render m)

end ProofForge.Backend.WasmNear.NearModulePlan