import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.NearAbiPlan.Legacy
import ProofForge.Backend.WasmHost.Plan.Legacy
import ProofForge.Backend.WasmHost.StructPlan.Legacy
import ProofForge.Compiler.Wasm.Printer

/-! Legacy `IR.Module` compatibility for the NEAR plan pipeline.

New production code must use `NearModulePlan.Core.buildFromCore` followed by
`NearModulePlan.lowerFromPlan`. This module is isolated so remaining v1 tests
and fixtures can be migrated and deleted without contaminating the canonical
builder's import graph.
-/

namespace ProofForge.Backend.WasmHost.NearModulePlan

open ProofForge.IR
open ProofForge.Backend.WasmHost.Types
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.NearAbiPlan
open ProofForge.Backend.WasmHost.EmitWat

def buildScalars (mod : Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Array NearStatePlan :=
  let layout :=
    if bridge == .near && moduleScalarsPackable mod then
      (stateLayoutPacked mod).1
    else
      stateLayout mod
  layout.map fun state => {
    id := state.id, type := state.type, keyPtr := state.keyPtr, keyLen := state.keyLen,
    packOffset := state.packOffset, packed := state.packed
  }

def buildMaps (mod : Module) : Array NearMapPlan :=
  (mapLayout mod).map fun map => {
    id := map.id, keyType := map.keyType, valueType := map.valueType,
    prefixPtr := map.prefixPtr, prefixLen := map.prefixLen, isArray := map.isArray
  }

def buildStrings (mod : Module) : Array NearStringPoolEntry :=
  (stringPool mod).map fun entry => { str := entry.str, ptr := entry.ptr, len := entry.len }

def buildPanics (mod : Module) (stringPoolEnd : Nat) : Array NearStringPoolEntry :=
  (panicPool mod stringPoolEnd).map fun entry =>
    { str := entry.str, ptr := entry.ptr, len := entry.len }

def buildCrosscallStrings (mod : Module) : Array NearStringPoolEntry :=
  (crosscallStringInfos mod.crosscallStrings CROSSCALL_STRING_BASE).map fun entry =>
    { str := entry.str, ptr := entry.ptr, len := entry.len }

def buildNearModulePlan (mod : Module) : Except PlanError NearModulePlan := do
  let surface ← buildModulePlan mod
  let entrypointAbis ← match buildModulePlans mod with
    | .ok plans => pure plans
    | .error message => .error { message }
  let scalars := buildScalars mod
  let maps := buildMaps mod
  let loweringCtx := EmitWat.loweringCtxForModule mod
  let stringsInfo := loweringCtx.strings
  let stringPoolEnd := stringInfoEnd STRING_BASE stringsInfo
  let strings := stringsInfo.map fun entry =>
    { str := entry.str, ptr := entry.ptr, len := entry.len : NearStringPoolEntry }
  let panics := loweringCtx.panics.map fun entry =>
    { str := entry.str, ptr := entry.ptr, len := entry.len : NearStringPoolEntry }
  let crosscallStrings := loweringCtx.crosscallStrings.map fun entry =>
    { str := entry.str, ptr := entry.ptr, len := entry.len : NearStringPoolEntry }
  .ok {
    moduleName := mod.name
    targetId := "wasm-near"
    artifactKind := "wasm-wat"
    irVersion := "portable-ir-v0"
    surface
    entrypointAbis
    layout := { scalars, maps, strings, panics, crosscallStrings, stringPoolEnd }
    lowerCtxSeed := {
      keyBuf := KEY_BUF
      mapkeyBuf := MAPKEY_BUF
      stringBase := STRING_BASE
      crosscallStringBase := CROSSCALL_STRING_BASE
      structs := mod.structs.map ProofForge.Backend.WasmHost.StructPlan.Legacy.ofIR
    }
  }

def Ctx.fromPlanSeed (_seed : NearLowerCtxSeed) (layout : NearLayoutPlan)
    (structs : Array StructDecl) (allocator : ProofForge.IR.AllocatorConfig)
    (entrypointAbis : Array EntrypointPlan := #[]) : EmitWat.Ctx :=
  let pack := layout.scalars.any (fun state => state.packed)
  let packSize := layout.scalars.foldl (init := 0) fun size state =>
    if state.packed then Nat.max size (state.packOffset + scalarWidth state.type) else size
  {
    scalars := layout.scalars.map fun state => {
      id := state.id, type := state.type, keyPtr := state.keyPtr, keyLen := state.keyLen,
      packOffset := state.packOffset, packed := state.packed : EmitWat.StateInfo
    }
    maps := layout.maps.map fun map => {
      id := map.id, keyType := map.keyType, valueType := map.valueType,
      prefixPtr := map.prefixPtr, prefixLen := map.prefixLen, isArray := map.isArray : EmitWat.MapInfo
    }
    strings := layout.strings.map fun entry =>
      { str := entry.str, ptr := entry.ptr, len := entry.len : EmitWat.StringInfo }
    panics := layout.panics.map fun entry =>
      { str := entry.str, ptr := entry.ptr, len := entry.len : EmitWat.StringInfo }
    crosscallStrings := layout.crosscallStrings.map fun entry =>
      { str := entry.str, ptr := entry.ptr, len := entry.len : EmitWat.StringInfo }
    structs
    allocator
    entrypointAbis
    packScalars := pack
    packSize
  }

def lowerModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError ProofForge.Compiler.Wasm.Module := do
  let ctx := Ctx.fromPlanSeed plan.lowerCtxSeed plan.layout mod.structs mod.allocator plan.entrypointAbis
  EmitWat.validateScratchCapacities mod ctx.strings ctx.panics ctx.crosscallStrings
  EmitWat.lowerModuleCoreWithCtx mod plan.surface ctx

def renderModuleFromPlan (mod : Module) (plan : NearModulePlan) :
    Except ProofForge.Backend.WasmHost.Diagnostics.EmitError String := do
  let module ← lowerModuleFromPlan mod plan
  .ok (ProofForge.Compiler.Wasm.Printer.render module)

end ProofForge.Backend.WasmHost.NearModulePlan
