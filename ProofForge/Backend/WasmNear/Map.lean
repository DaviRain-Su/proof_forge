/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Common
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.Struct
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Map

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Common
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.Struct
open ProofForge.Backend.WasmNear.Types

/-! Indexed map storage helper functions for EmitWat. -/

-- Map<U64, T>: storage key = prefix(stateId ++ ":") ++ 8 key bytes.

def mapReadName  (vt : ValueType) : String := "__pf_map_read_"  ++ typeSuffix vt
def mapWriteName (vt : ValueType) : String := "__pf_map_write_" ++ typeSuffix vt
def mapContainsName : String := "__pf_map_contains"
def mapBuildkeyName  : String := "__pf_map_buildkey"

/- `__pf_map_buildkey(pp, pl, k)`: write prefix[pp..pp+pl] then 8 key bytes to MAPKEY_BUF. -/
def mapBuildkeyFunc : Func :=
  { name := mapBuildkeyName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
    locals := #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .localGet "pl", .plain "i32.ge_u", .brIf 1,
        .localGet "i", .i32Const MAPKEY_BUF, .plain "i32.add",
        .localGet "i", .localGet "pp", .plain "i32.add", .load "i32.load8_u" 0,
        .store "i32.store8" 0,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0 ] } ] } ,
      .i32Const MAPKEY_BUF, .localGet "pl", .plain "i32.add", .localGet "k", .store "i64.store" 0 ] } }

def mapKeyByteLenInsns (keyBytes : Nat) : Array Insn :=
  #[.localGet "pl", .i32Const keyBytes, .plain "i32.add", .plain "i64.extend_i32_u"]

def mapStorageReadHostInsns (keyBytes : Nat) : Array Insn :=
  mapKeyByteLenInsns keyBytes ++ #[.i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read"]

def mapReadFunc (vt : ValueType) : Func :=
  if vt == .hash then
    { name := mapReadName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
      results := #[.i32],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
      body := { insns := #[
        .i32Const ZERO_HASH_BUF, .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
      ] ++ mapStorageReadHostInsns 8 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .localSet "r" ] } { insns := #[] },
        .localGet "r" ] } }
  else
    { name := mapReadName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
      results := #[wasmTypeOf vt],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
      body := { insns := #[
        .const (wasmTypeOf vt) "0", .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
      ] ++ mapStorageReadHostInsns 8 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .localGet "r" ] } }

def mapWriteFunc (vt : ValueType) : Func :=
  if vt == .hash then
    { name := mapWriteName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                  { name := "k", type := .i64 }, { name := "v", type := .i32 }],
      results := #[.i32],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
      body := { insns := #[
        .i32Const ZERO_HASH_BUF, .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
      ] ++ mapStorageReadHostInsns 8 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                          .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName,
      ] ++ mapKeyByteLenInsns 8 ++ #[
        .i64Const MAPKEY_BUF, .i64Const 32, .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }
  else
    { name := mapWriteName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                  { name := "k", type := .i64 }, { name := "v", type := wasmTypeOf vt }],
      results := #[wasmTypeOf vt],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
      body := { insns := #[
        .const (wasmTypeOf vt) "0", .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
      ] ++ mapStorageReadHostInsns 8 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      ] ++ mapKeyByteLenInsns 8 ++ #[
        .i64Const MAPKEY_BUF, .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }

def mapContainsFunc : Func :=
  { name := mapContainsName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
    results := #[.i64],
    body := { insns := #[
      .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
    ] ++ mapKeyByteLenInsns 8 ++ #[
      .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

def mapHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesU64IndexedBuildKey then #[mapBuildkeyFunc] else #[]) ++
    (plan.u64IndexedReadTypes.foldl (init := #[]) fun acc type => acc ++ #[mapReadFunc type]) ++
    (plan.u64IndexedWriteTypes.foldl (init := #[]) fun acc type => acc ++ #[mapWriteFunc type]) ++
    (if plan.usesU64IndexedContains then #[mapContainsFunc] else #[])

-- Map<Hash, T>: storage key = prefix ++ 32 key bytes (key is a hash pointer).

def mapBuildkeyHashName  : String := "__pf_map_buildkey_hash"
def mapReadHashName  (vt : ValueType) : String := "__pf_map_read_hash_"  ++ typeSuffix vt
def mapWriteHashName (vt : ValueType) : String := "__pf_map_write_hash_" ++ typeSuffix vt
def mapContainsHashName : String := "__pf_map_contains_hash"

def mapWriteStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.isArray then
      err s!"EmitWat: state `{id}` is an array; use storageArrayWrite or an index storage path"
    else .ok mapInfo

def mapWriteCall (mapInfo : MapInfo) : Except EmitError (Array Insn) :=
  match mapInfo.keyType with
  | .u64 => .ok #[.call (mapWriteName mapInfo.valueType)]
  | .hash => .ok #[.call (mapWriteHashName mapInfo.valueType)]
  | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported"

def mapPrefixInsns (mapInfo : MapInfo) : Array Insn :=
  #[.i32Const mapInfo.prefixPtr, .i32Const mapInfo.prefixLen]

def mapWriteValueInsns (mapInfo : MapInfo) (id : String) (keyInsns valueInsns writeCall : Array Insn)
    (valueType : ValueType) : Except EmitError (Array Insn × ValueType) :=
  if valueType != mapInfo.valueType then
    err s!"EmitWat: map write `{id}` expected `{mapInfo.valueType.name}`, got `{valueType.name}`"
  else
    .ok (mapPrefixInsns mapInfo ++ keyInsns ++ valueInsns ++ writeCall, mapInfo.valueType)

def mapReadStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.isArray then
      err s!"EmitWat: state `{id}` is an array; use storageArrayRead or an index storage path"
    else .ok mapInfo

def mapReadCall (mapInfo : MapInfo) (id : String) : Except EmitError (Array Insn) :=
  match mapInfo.keyType with
  | .u64 => .ok #[.call (mapReadName mapInfo.valueType)]
  | .hash => .ok #[.call (mapReadHashName mapInfo.valueType)]
  | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported (`{id}` has key `{mapInfo.keyType.name}`)"

def mapReadValueInsns (mapInfo : MapInfo) (keyInsns readCall : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ keyInsns ++ readCall, mapInfo.valueType)

def mapContainsStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.isArray then
      err s!"EmitWat: state `{id}` is an array; map contains is only valid for map state"
    else .ok mapInfo

def mapContainsCall (mapInfo : MapInfo) : Except EmitError (Array Insn) :=
  match mapInfo.keyType with
  | .u64 => .ok #[.call mapContainsName]
  | .hash => .ok #[.call mapContainsHashName]
  | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported"

def mapContainsValueInsns (mapInfo : MapInfo) (keyInsns containsCall : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ keyInsns ++ containsCall ++ #[.plain "i32.wrap_i64"], .bool)

def nestedMapReadStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.keyType != .u64 then
      err s!"EmitWat: nested map key must be U64 (`{id}` has key `{mapInfo.keyType.name}`)"
    else .ok mapInfo

def nestedMapReadValueInsns (mapInfo : MapInfo) (key1Insns key2Insns : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ key1Insns ++ key2Insns ++
    #[.call (mapReadName mapInfo.valueType)], mapInfo.valueType)

def storageArrayStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findArrayState? maps id with
  | none => err s!"EmitWat: unknown array state `{id}`"
  | some mapInfo =>
    if mapInfo.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
    else if !isIndexedStorageValueType mapInfo.valueType then
      err s!"EmitWat: indexed storage path `{id}` has unsupported element type `{mapInfo.valueType.name}`; use index+field for struct arrays"
    else .ok mapInfo

def storageArrayReadInsns (mapInfo : MapInfo) (indexInsns : Array Insn) : Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ indexInsns ++ #[.call (mapReadName mapInfo.valueType)],
    mapInfo.valueType)

def storageArrayWriteStateInfo (maps : Array MapInfo) (id : String) (valueType : ValueType) :
    Except EmitError MapInfo := do
  let mapInfo ← storageArrayStateInfo maps id
  if valueType != mapInfo.valueType then
    err s!"EmitWat: array write `{id}` expected `{mapInfo.valueType.name}`, got `{valueType.name}`"
  else .ok mapInfo

def storageArrayWriteInsns (mapInfo : MapInfo) (indexInsns valueInsns : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ indexInsns ++ valueInsns ++
    #[.call (mapWriteName mapInfo.valueType)], mapInfo.valueType)

def nestedMapWriteStateInfo (maps : Array MapInfo) (id : String) (valueType : ValueType) :
    Except EmitError MapInfo := do
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.keyType != .u64 then err s!"EmitWat: nested map key must be U64"
    else if valueType != mapInfo.valueType then
      err s!"EmitWat: nested map write `{id}` expected `{mapInfo.valueType.name}`, got `{valueType.name}`"
    else .ok mapInfo

def nestedMapWriteValueInsns (mapInfo : MapInfo) (key1Insns key2Insns valueInsns : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ key1Insns ++ key2Insns ++ valueInsns ++
    #[.call (mapWriteName mapInfo.valueType)],
    mapInfo.valueType)

def mapBuildkeyHashFunc : Func :=
  { name := mapBuildkeyHashName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
    locals := #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .localGet "pl", .plain "i32.ge_u", .brIf 1,
        .localGet "i", .i32Const MAPKEY_BUF, .plain "i32.add",
        .localGet "i", .localGet "pp", .plain "i32.add", .load "i32.load8_u" 0,
        .store "i32.store8" 0,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0 ] } ] } ,
      .i32Const MAPKEY_BUF, .localGet "pl", .plain "i32.add", .localGet "kp", .i32Const 32, .call memcpyName ] } }

def mapReadHashFunc (vt : ValueType) : Func :=
  if vt == .hash then
    { name := mapReadHashName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
      results := #[.i32],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
      body := { insns := #[
        .i32Const ZERO_HASH_BUF, .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
      ] ++ mapStorageReadHostInsns 32 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .localSet "r" ] } { insns := #[] },
        .localGet "r" ] } }
  else
    { name := mapReadHashName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
      results := #[wasmTypeOf vt],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
      body := { insns := #[
        .const (wasmTypeOf vt) "0", .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
      ] ++ mapStorageReadHostInsns 32 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .localGet "r" ] } }

def mapWriteHashFunc (vt : ValueType) : Func :=
  if vt == .hash then
    { name := mapWriteHashName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                  { name := "kp", type := .i32 }, { name := "v", type := .i32 }],
      results := #[.i32],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
      body := { insns := #[
        .i32Const ZERO_HASH_BUF, .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
      ] ++ mapStorageReadHostInsns 32 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                          .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName,
      ] ++ mapKeyByteLenInsns 32 ++ #[
        .i64Const MAPKEY_BUF, .i64Const 32, .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }
  else
    { name := mapWriteHashName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                  { name := "kp", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
      results := #[wasmTypeOf vt],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
      body := { insns := #[
        .const (wasmTypeOf vt) "0", .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
      ] ++ mapStorageReadHostInsns 32 ++ #[
        .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      ] ++ mapKeyByteLenInsns 32 ++ #[
        .i64Const MAPKEY_BUF, .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }

def mapContainsHashFunc : Func :=
  { name := mapContainsHashName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
    results := #[.i64],
    body := { insns := #[
      .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
    ] ++ mapKeyByteLenInsns 32 ++ #[
      .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

def mapHashHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesHashIndexedBuildKey then #[mapBuildkeyHashFunc] else #[]) ++
    (plan.hashIndexedReadTypes.foldl (init := #[]) fun acc type => acc ++ #[mapReadHashFunc type]) ++
    (plan.hashIndexedWriteTypes.foldl (init := #[]) fun acc type => acc ++ #[mapWriteHashFunc type]) ++
    (if plan.usesHashIndexedContains then #[mapContainsHashFunc] else #[])

end ProofForge.Backend.WasmNear.Map
