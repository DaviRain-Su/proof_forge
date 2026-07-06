/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Memory

namespace ProofForge.Backend.WasmNear.Layout

open ProofForge.IR
open ProofForge.Backend.WasmNear.Memory

/-! Pure storage/data layout helpers for EmitWat. These compute storage-key
offsets and literal string pools; instruction generation stays in EmitWat. -/

structure StateInfo where
  id : String
  type : ValueType
  keyPtr : Nat
  keyLen : Nat

def stateLayout (mod : ProofForge.IR.Module) : Array StateInfo :=
  let step (acc : Array StateInfo) (offset : Nat) (s : StateDecl) : Array StateInfo × Nat :=
    match s.kind with
    | .scalar => (acc.push { id := s.id, type := s.type, keyPtr := offset, keyLen := s.id.length }, offset + s.id.length + 1)
    | _ => (acc, offset)
  let result : Array StateInfo × Nat := mod.state.foldl (init := (#[], 0))
    fun (acc, offset) s => step acc offset s
  result.fst

def findScalarState? (layout : Array StateInfo) (id : String) : Option StateInfo :=
  layout.find? (fun s => s.id == id)

structure MapInfo where
  id        : String
  keyType   : ValueType
  valueType : ValueType
  prefixPtr : Nat
  prefixLen : Nat
  isArray   : Bool

/-- Map state -> prefix data segment `id ++ ":"` laid out back-to-back from a high offset. -/
def mapLayout (mod : ProofForge.IR.Module) : Array MapInfo :=
  let step (acc : Array MapInfo) (offset : Nat) (s : StateDecl) : Array MapInfo × Nat :=
    match s.kind with
    | .map kt _ => (acc.push { id := s.id, keyType := kt, valueType := s.type, prefixPtr := offset, prefixLen := s.id.length + 1, isArray := false }, offset + s.id.length + 2)
    | .array _ => (acc.push { id := s.id, keyType := .u64, valueType := s.type, prefixPtr := offset, prefixLen := s.id.length + 1, isArray := true }, offset + s.id.length + 2)
    | _ => (acc, offset)
  let result : Array MapInfo × Nat := mod.state.foldl (init := (#[], 20000)) fun (acc, offset) s => step acc offset s
  result.fst

def findMapState? (layout : Array MapInfo) (id : String) : Option MapInfo :=
  layout.find? (fun m => m.id == id)

def findArrayState? (layout : Array MapInfo) (id : String) : Option MapInfo :=
  layout.find? (fun m => m.id == id && m.isArray)

structure StringInfo where
  str : String
  ptr : Nat
  len : Nat

/-- Collect event-name + field-name strings into a deduped pool at STRING_BASE. -/
def stringPool (mod : ProofForge.IR.Module) : Array StringInfo :=
  let raw : Array String := mod.entrypoints.foldl (init := #[]) fun acc ep =>
    ep.body.foldl (init := acc) fun acc' s =>
      match s with
      | .effect (.eventEmit name fields) => acc' ++ #[name] ++ fields.map (fun (n, _) => n)
      | .effect (.eventEmitIndexed name indexedFields dataFields) =>
          acc' ++ #[name] ++ indexedFields.map (fun (n, _) => n) ++ dataFields.map (fun (n, _) => n)
      | _ => acc'
  let unique : Array String := raw.foldl (init := #[]) fun acc s => if acc.contains s then acc else acc.push s
  let result : Array StringInfo × Nat :=
    unique.foldl (init := (#[], STRING_BASE)) fun (acc, offset) s =>
      (acc.push { str := s, ptr := offset, len := s.length }, offset + s.length + 1)
  result.fst

def panicMessage (ref : ProofForge.IR.ErrorRef) : String :=
  let code := ref.userCode?.getD ""
  s!"PF:{ref.assertionId}:{code}"

/-- Collect assertion error messages into a deduped pool placed after the event/field string pool. -/
def panicPool (mod : ProofForge.IR.Module) (stringPoolEnd : Nat) : Array StringInfo :=
  let base := stringPoolEnd
  let raw : Array String := mod.entrypoints.foldl (init := #[]) fun acc ep =>
    ep.body.foldl (init := acc) fun acc' s =>
      match s with
      | .assert _ _ (some ref) => acc'.push (panicMessage ref)
      | .assertEq _ _ _ (some ref) => acc'.push (panicMessage ref)
      | _ => acc'
  let unique : Array String := raw.foldl (init := #[]) fun acc s => if acc.contains s then acc else acc.push s
  let result : Array StringInfo × Nat :=
    unique.foldl (init := (#[], base)) fun (acc, offset) s =>
      (acc.push { str := s, ptr := offset, len := s.length }, offset + s.length + 1)
  result.fst

def findString? (pool : Array StringInfo) (s : String) : Option StringInfo :=
  pool.find? (fun si => si.str == s)

def crosscallStringInfos (strings : Array String) (base : Nat) : Array StringInfo :=
  let result : Array StringInfo × Nat :=
    strings.foldl (init := (#[], base)) fun (acc, offset) s =>
      (acc.push { str := s, ptr := offset, len := s.length }, offset + s.length + 1)
  result.fst

end ProofForge.Backend.WasmNear.Layout
