/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Memory

namespace ProofForge.Backend.WasmNear.ModuleAssembly

open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Memory

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

end ProofForge.Backend.WasmNear.ModuleAssembly
