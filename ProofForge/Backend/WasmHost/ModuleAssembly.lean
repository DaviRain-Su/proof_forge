/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Aggregate
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Context
import ProofForge.Backend.WasmHost.Crosscall
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.JsonReturn
import ProofForge.Backend.WasmHost.StringCmp
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.LoweringEnv
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.Promise
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.ModuleAssembly

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Aggregate
open ProofForge.Backend.WasmHost.ArrayHeap
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Context
open ProofForge.Backend.WasmHost.Crosscall
open ProofForge.Backend.WasmHost.Event
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.JsonReturn
open ProofForge.Backend.WasmHost.StringCmp
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.LoweringEnv
open ProofForge.Backend.WasmHost.Map
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Params
open ProofForge.Backend.WasmHost.Promise
open ProofForge.Backend.WasmHost.Scalar

/-! Pure module-assembly helpers for the canonical wasm-near EmitWat backend. -/

def moduleStringPoolEnd (strings : Array StringInfo) : Nat :=
  strings.foldl (init := STRING_BASE) fun acc s => max acc (s.ptr + s.len + 1)

def loweringCtxForModule (mod : ProofForge.IR.Module)
    (bridge : ProofForge.Target.HostBridge := .near) : Ctx :=
  let strings := stringPool mod
  let panics := panicPool mod (moduleStringPoolEnd strings)
  let pack := bridge == ProofForge.Target.HostBridge.near && moduleScalarsPackable mod
  let (scalars, packSize) :=
    if pack then stateLayoutPacked mod else (stateLayout mod, 0)
  {
    scalars := scalars
    maps := mapLayout mod
    strings := strings
    panics := panics
    crosscallStrings := crosscallStringInfos mod.crosscallStrings CROSSCALL_STRING_BASE
    structs := mod.structs
    allocator := mod.allocator
    bridge := bridge
    packScalars := pack
    packSize := packSize
  }

def dataSegmentsForModulePlan (modulePlan : ModulePlan) (ctx : Ctx) : Array DataSegment :=
  let scalarData :=
    if ctx.packScalars then
      #[{ offset := PACK_KEY_PTR, bytes := "__pf_s" : DataSegment }]
    else
      ctx.scalars.map fun s => { offset := s.keyPtr, bytes := s.id : DataSegment }
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
  let packHelpers :=
    if ctx.packScalars then packHelperFuncs ctx.packSize modulePlan else #[]
  let scalarHelpers :=
    if ctx.packScalars then #[]
    else scalarStorageHelperFuncsForModulePlan modulePlan ctx.bridge
  let jsonReturnHelpers :=
    let jsonAbis := ctx.entrypointAbis.filter (fun abi => abi.outputJson?.isSome)
    if jsonAbis.isEmpty then #[] else
      let schemaFuncs := jsonAbis.filterMap fun abi =>
        abi.outputJson?.bind fun schema =>
          (JsonReturn.buildReturnFunc abi.name ctx.structs schema abi.returnType).toOption
      #[memcpyFunc, fmtU64Func, u128Divmod10Func, u128FmtFunc] ++
        JsonReturn.runtimeFuncs ++ schemaFuncs
  let jsonInputHelpers :=
    (if ctx.entrypointAbis.any (fun abi =>
        abi.inputCodec == .json && abi.params.any (fun param =>
          param.type == .u128 || param.type == .u64 || param.type == .u32)) then
      #[parseU128DecimalFunc]
    else #[]) ++
    (if ctx.entrypointAbis.any (fun abi =>
        abi.inputCodec == .json && abi.params.any (fun param => param.type == .string)) then
      #[parseJsonHex4Func, writeJsonUtf8Func]
    else #[])
  let funcs := scalarHelpers ++ packHelpers ++
    returnHelperFuncsForModulePlan modulePlan ctx.bridge ++
    powHelperFuncsForModulePlan modulePlan ++ hashExprHelperFuncsForModulePlan modulePlan ++
    hashStorageHelperFuncsForModulePlan modulePlan ++ ctxHelperFuncsForModulePlan modulePlan ++
    StringCmp.strEqFuncsForModulePlan modulePlan ++
    evtHelperFuncsForModulePlan modulePlan ++ crosscallArgsHelperFuncsForModulePlan modulePlan ++
    promiseHelperFuncsForModulePlan modulePlan ++
    crosscallPoolHelperFuncs ctx.crosscallStrings ++
    mapHelperFuncsForModulePlan modulePlan ctx.bridge ++
    mapHashHelperFuncsForModulePlan modulePlan ctx.bridge ++
    mapStringHelperFuncsForModulePlan modulePlan ctx.bridge ++
    u128ArithFuncs ++ jsonInputHelpers ++ jsonReturnHelpers ++
    aggregateHelperFuncsForModulePlan modulePlan mod ++
    (if modulePlan.usesMemcpy then #[memcpyFunc] else #[]) ++ entryFuncs
  funcs.foldl (fun unique function =>
    if unique.any (fun prior => prior.name == function.name) then unique
    else unique.push function) #[]

def globalsForModulePlan (modulePlan : ModulePlan) (allocator : ProofForge.IR.AllocatorConfig)
    (packScalars : Bool := false) (usesJsonReturn : Bool := false) : Array Global :=
  let arrPtrDecls :=
    if allocator.requiresHost || !modulePlanUsesArrHeap modulePlan then #[]
    else if allocator.usesMinimalMallocShape then
      #[arrPtrGlobalDecl allocator.heapBase, arrFreeGlobalDecl]
    else #[arrPtrGlobalDecl allocator.heapBase]
  let hashGlobals := if modulePlanUsesHashAlloc modulePlan then #[hashPtrGlobalDecl] else #[]
  let packG := if packScalars then packGlobals else #[]
  hashGlobals ++ packG ++ (if modulePlan.usesEventApi then evtGlobals else #[]) ++
    (if usesJsonReturn then #[JsonReturn.ptrGlobalDecl] else #[]) ++
    crosscallGlobalsForModulePlan modulePlan ++ arrPtrDecls

end ProofForge.Backend.WasmHost.ModuleAssembly
