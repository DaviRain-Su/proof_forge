/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Types

namespace ProofForge.Backend.WasmHost.Layout

open ProofForge.IR
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Types

/-! Pure storage/data layout helpers for EmitWat. These compute storage-key
offsets and literal string pools; instruction generation stays in EmitWat. -/

structure StateInfo where
  id : String
  type : ValueType
  keyPtr : Nat
  keyLen : Nat
  /-- Byte offset within the packed scalar blob when `packed = true`. -/
  packOffset : Nat := 0
  /-- When true, NEAR EmitWat batches this scalar into one storage key (`__pf_s`). -/
  packed : Bool := false

def isPackableScalarType : ValueType → Bool
  | .u32 | .u64 | .bool => true
  | _ => false

/-- True when packing multi-scalar state into one storage key is worthwhile:
every scalar is u32/u64/bool and there are **at least two** scalars. Single-field
modules (Counter) keep the classic one-key-per-scalar layout. -/
def moduleScalarsPackable (mod : ProofForge.IR.Module) : Bool :=
  let scalars := mod.state.filter (fun s => s.kind == .scalar)
  scalars.size >= 2 && scalars.all (fun s => isPackableScalarType s.type)

def stateLayout (mod : ProofForge.IR.Module) : Array StateInfo :=
  let step (acc : Array StateInfo) (offset : Nat) (s : StateDecl) : Array StateInfo × Nat :=
    match s.kind with
    | .scalar =>
      (acc.push {
          id := s.id, type := s.type, keyPtr := offset, keyLen := s.id.length,
          packOffset := 0, packed := false },
        offset + s.id.length + 1)
    | _ => (acc, offset)
  let result : Array StateInfo × Nat := mod.state.foldl (init := (#[], 0))
    fun (acc, offset) s => step acc offset s
  result.fst

/-- Pack all packable scalars into one storage key `__pf_s` with sequential
byte offsets. Only used on the NEAR EmitWat path when `moduleScalarsPackable`. -/
def stateLayoutPacked (mod : ProofForge.IR.Module) : Array StateInfo × Nat :=
  let step (acc : Array StateInfo) (packOff : Nat) (s : StateDecl) : Array StateInfo × Nat :=
    match s.kind with
    | .scalar =>
      let w := scalarWidth s.type
      (acc.push {
          id := s.id, type := s.type,
          keyPtr := PACK_KEY_PTR, keyLen := PACK_KEY_LEN,
          packOffset := packOff, packed := true },
        packOff + w)
    | _ => (acc, packOff)
  mod.state.foldl (init := (#[], 0)) fun (acc, packOff) s => step acc packOff s

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

/-- Composite JSON event header stored in the string pool: `{"event":"<name>"`.
One putstr emits the whole static prefix (no per-char / multi-fragment assembly). -/
def eventHeaderPoolString (name : String) : String :=
  "{\"event\":\"" ++ name ++ "\""

/-- Composite JSON field key fragment: `,"field":` — one putstr per field. -/
def eventFieldPoolString (field : String) : String :=
  ",\"" ++ field ++ "\":"

/-- Collect composite event header/field strings into a deduped pool at STRING_BASE. -/
def stringPool (mod : ProofForge.IR.Module) : Array StringInfo :=
  let raw : Array String := mod.entrypoints.foldl (init := #[]) fun acc ep =>
    ep.body.foldl (init := acc) fun acc' s =>
      match s with
      | .effect (.eventEmit name fields) =>
          acc' ++ #[eventHeaderPoolString name] ++
            fields.map (fun (n, _) => eventFieldPoolString n)
      | .effect (.eventEmitIndexed name indexedFields dataFields) =>
          acc' ++ #[eventHeaderPoolString name] ++
            indexedFields.map (fun (n, _) => eventFieldPoolString n) ++
            dataFields.map (fun (n, _) => eventFieldPoolString n)
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

end ProofForge.Backend.WasmHost.Layout
