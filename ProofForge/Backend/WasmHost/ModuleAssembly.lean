/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Aggregate
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Context
import ProofForge.Backend.WasmHost.Crosscall
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.LoweringEnv
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Promise
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.ModuleAssembly

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Aggregate
open ProofForge.Backend.WasmHost.ArrayHeap
open ProofForge.Backend.WasmHost.Context
open ProofForge.Backend.WasmHost.Crosscall
open ProofForge.Backend.WasmHost.Event
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.LoweringEnv
open ProofForge.Backend.WasmHost.Map
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Promise
open ProofForge.Backend.WasmHost.Scalar

/-! Pure module-assembly helpers for the canonical wasm-near EmitWat backend. -/

def moduleStringPoolEnd (strings : Array StringInfo) : Nat :=
  strings.foldl (init := STRING_BASE) fun acc s => max acc (s.ptr + s.len + 1)

def loweringCtxForModule (mod : ProofForge.IR.Module)
    (bridge : ProofForge.Target.HostBridge := .near) : Ctx :=
  let strings := stringPool mod
  let panics := panicPool mod (moduleStringPoolEnd strings)
  {
    scalars := stateLayout mod
    maps := mapLayout mod
    strings := strings
    panics := panics
    crosscallStrings := crosscallStringInfos mod.nearCrosscallStrings CROSSCALL_STRING_BASE
    structs := mod.structs
    allocator := mod.allocator
    bridge := bridge
  }

def dataSegmentsForModulePlan (modulePlan : ModulePlan) (ctx : Ctx) : Array DataSegment :=
  let scalarData := ctx.scalars.map fun s => { offset := s.keyPtr, bytes := s.id : DataSegment }
  let mapData := ctx.maps.map fun m => { offset := m.prefixPtr, bytes := m.id ++ ":" : DataSegment }
  let boolData : Array DataSegment :=
    #[{ offset := TRUE_PTR, bytes := "true" },
      { offset := FALSE_PTR, bytes := "false" },
      { offset := HEX_LUT_PTR, bytes := "0123456789abcdef" }]
  -- Static JSON punctuation for event logs (see Memory.EVT_PUNCT_* layout).
  -- One packed segment keeps data-section noise low and enables putstr-based
  -- assembly instead of per-character putc (gas + code size).
  let evtKeySegments :=
    if modulePlan.usesEventApi then
      #[{ offset := EVT_PUNCT_BASE
          bytes := "{\"event\":\"" ++ "\"" ++ ",\"" ++ "\":" ++ "}" : DataSegment }]
    else #[]
  let usesCrosscallStrings := modulePlan.usesPromiseCreate || modulePlan.usesPromiseThen
  let crosscallStringData :=
    if usesCrosscallStrings then
      ctx.crosscallStrings.map fun si => { offset := si.ptr, bytes := si.str : DataSegment }
    else #[]
  let crosscallArgsData :=
    if modulePlan.usesPromiseCreate then #[{ offset := CROSSCALL_ARGS_EMPTY_PTR, bytes := "[]" : DataSegment }] else #[]
  let stringData := ctx.strings.map fun si => { offset := si.ptr, bytes := si.str : DataSegment }
  let panicData := ctx.panics.map fun si => { offset := si.ptr, bytes := si.str : DataSegment }
  scalarData ++ mapData ++ boolData ++ evtKeySegments ++ stringData ++
    crosscallStringData ++ crosscallArgsData ++ (if ctx.panics.isEmpty then #[] else panicData)

def helperFuncsForModulePlan (modulePlan : ModulePlan) (mod : ProofForge.IR.Module)
    (ctx : Ctx) (entryFuncs : Array Func) : Array Func :=
  scalarStorageHelperFuncsForModulePlan modulePlan ctx.bridge ++
    returnHelperFuncsForModulePlan modulePlan ctx.bridge ++
    powHelperFuncsForModulePlan modulePlan ++ hashExprHelperFuncsForModulePlan modulePlan ++
    hashStorageHelperFuncsForModulePlan modulePlan ++ ctxHelperFuncsForModulePlan modulePlan ++
    evtHelperFuncsForModulePlan modulePlan ++ crosscallArgsHelperFuncsForModulePlan modulePlan ++
    promiseHelperFuncsForModulePlan modulePlan ++
    crosscallPoolHelperFuncs ctx.crosscallStrings ++
    mapHelperFuncsForModulePlan modulePlan ctx.bridge ++
    mapHashHelperFuncsForModulePlan modulePlan ctx.bridge ++
    aggregateHelperFuncsForModulePlan modulePlan mod ++ entryFuncs

def globalsForModulePlan (modulePlan : ModulePlan) (allocator : ProofForge.IR.AllocatorConfig) :
    Array Global :=
  let arrPtrDecls :=
    if allocator.requiresHost || !modulePlanUsesArrHeap modulePlan then #[]
    else if allocator.usesMinimalMallocShape then
      #[arrPtrGlobalDecl allocator.heapBase, arrFreeGlobalDecl]
    else #[arrPtrGlobalDecl allocator.heapBase]
  let hashGlobals := if modulePlanUsesHashAlloc modulePlan then #[hashPtrGlobalDecl] else #[]
  hashGlobals ++ (if modulePlan.usesEventApi then evtGlobals else #[]) ++
    crosscallGlobalsForModulePlan modulePlan ++ arrPtrDecls

end ProofForge.Backend.WasmHost.ModuleAssembly
