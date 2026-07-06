/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan

namespace ProofForge.Backend.WasmNear.ModuleAssembly

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan

/-! Pure module-assembly helpers for the canonical wasm-near EmitWat backend. -/

def moduleStringPoolEnd (strings : Array StringInfo) : Nat :=
  strings.foldl (init := STRING_BASE) fun acc s => max acc (s.ptr + s.len + 1)

def loweringCtxForModule (mod : ProofForge.IR.Module) : Ctx :=
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
  }

def dataSegmentsForModulePlan (modulePlan : ModulePlan) (ctx : Ctx) : Array DataSegment :=
  let scalarData := ctx.scalars.map fun s => { offset := s.keyPtr, bytes := s.id : DataSegment }
  let mapData := ctx.maps.map fun m => { offset := m.prefixPtr, bytes := m.id ++ ":" : DataSegment }
  let boolData : Array DataSegment :=
    #[{ offset := TRUE_PTR, bytes := "true" },
      { offset := FALSE_PTR, bytes := "false" },
      { offset := HEX_LUT_PTR, bytes := "0123456789abcdef" }]
  let evtKeySegments :=
    if modulePlan.usesEventApi then #[{ offset := EVT_KEY_PTR, bytes := "event" : DataSegment }] else #[]
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

end ProofForge.Backend.WasmNear.ModuleAssembly
