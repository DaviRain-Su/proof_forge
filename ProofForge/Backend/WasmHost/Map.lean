/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Map

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

/-! Indexed map storage helper functions for EmitWat. -/

-- Map<U64, T>: storage key = prefix(stateId ++ ":") ++ 8 key bytes.

def mapReadName  (vt : ValueType) : String := "__pf_map_read_"  ++ typeSuffix vt
def mapWriteName (vt : ValueType) : String := "__pf_map_write_" ++ typeSuffix vt
def mapDeleteName (vt : ValueType) : String := "__pf_map_delete_" ++ typeSuffix vt
def mapDeleteHashName (vt : ValueType) : String := "__pf_map_delete_hash_" ++ typeSuffix vt
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

/-- NEAR: storage_read(key_len_i64, key_ptr_i64, register 0) → found i64. -/
def mapStorageReadHostInsnsNear (keyBytes : Nat) : Array Insn :=
  mapKeyByteLenInsns keyBytes ++ #[.i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read"]

/-- Soroban: `_get(key_ptr, key_len) → i32` le-scalar (no register ABI). -/
def mapStorageReadHostInsnsSoroban (keyBytes : Nat) : Array Insn :=
  #[
    .i32Const MAPKEY_BUF,
    .localGet "pl", .i32Const keyBytes, .plain "i32.add",
    .call "_get"
  ]

/-- CosmWasm: `db_read(key_ptr, key_len) → i64` le-word. -/
def mapStorageReadHostInsnsCosmWasm (keyBytes : Nat) : Array Insn :=
  #[
    .i32Const MAPKEY_BUF,
    .localGet "pl", .i32Const keyBytes, .plain "i32.add",
    .call "db_read"
  ]

def mapStorageReadHostInsns (keyBytes : Nat)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Insn :=
  match bridge with
  | .soroban => mapStorageReadHostInsnsSoroban keyBytes
  | .cosmWasm => mapStorageReadHostInsnsCosmWasm keyBytes
  | .near => mapStorageReadHostInsnsNear keyBytes

def mapStorageWriteHostInsnsNear (keyBytes valBytes : Nat) : Array Insn :=
  mapKeyByteLenInsns keyBytes ++ #[
    .i64Const MAPKEY_BUF, .i64Const valBytes, .i64Const KEY_BUF, .i64Const 0,
    .call "storage_write", .drop
  ]

def mapStorageWriteHostInsnsSoroban (keyBytes valBytes : Nat) : Array Insn :=
  #[
    .i32Const MAPKEY_BUF,
    .localGet "pl", .i32Const keyBytes, .plain "i32.add",
    .i32Const KEY_BUF, .i32Const valBytes,
    .call "_put"
  ]

def mapStorageWriteHostInsnsCosmWasm (keyBytes valBytes : Nat) : Array Insn :=
  #[
    .i32Const MAPKEY_BUF,
    .localGet "pl", .i32Const keyBytes, .plain "i32.add",
    .i32Const KEY_BUF, .i32Const valBytes,
    .call "db_write"
  ]

def mapStorageWriteHostInsns (keyBytes valBytes : Nat)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Insn :=
  match bridge with
  | .soroban => mapStorageWriteHostInsnsSoroban keyBytes valBytes
  | .cosmWasm => mapStorageWriteHostInsnsCosmWasm keyBytes valBytes
  | .near => mapStorageWriteHostInsnsNear keyBytes valBytes

/-- Widen/narrow host scalar after register-less map read (Soroban i32 / CosmWasm i64). -/
def mapRegisterlessReadCoerce (bridge : ProofForge.Target.HostBridge) (vt : ValueType) : Array Insn :=
  match bridge, vt with
  | .soroban, .u64 => #[.plain "i64.extend_i32_u"]
  | .cosmWasm, .u32 | .cosmWasm, .bool => #[.plain "i32.wrap_i64"]
  | _, _ => #[]

def mapReadFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      if vt == .hash then
        { name := mapReadName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
          results := #[.i32],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
            .i32Const ZERO_HASH_BUF
          ] } }
      else
        { name := mapReadName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
          results := #[wasmTypeOf vt],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
          ] ++ mapStorageReadHostInsns 8 bridge ++ mapRegisterlessReadCoerce bridge vt } }
  | _ =>
      if vt == .hash then
        { name := mapReadName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
          results := #[.i32],
          locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
          body := { insns := #[
            .i32Const ZERO_HASH_BUF, .localSet "r",
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
          ] ++ mapStorageReadHostInsns 8 .near ++ #[
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
          ] ++ mapStorageReadHostInsns 8 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                              .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
            .localGet "r" ] } }

def mapWriteFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      if vt == .hash then
        { name := mapWriteName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "k", type := .i64 }, { name := "v", type := .i32 }],
          results := #[.i32],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
            .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName
          ] ++ mapStorageWriteHostInsns 8 32 bridge ++ #[
            .i32Const ZERO_HASH_BUF
          ] } }
      else
        { name := mapWriteName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "k", type := .i64 }, { name := "v", type := wasmTypeOf vt }],
          results := #[wasmTypeOf vt],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
            .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
          ] ++ mapStorageWriteHostInsns 8 (scalarWidth vt) bridge ++ #[
            .localGet "v"
          ] } }
  | _ =>
      if vt == .hash then
        { name := mapWriteName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "k", type := .i64 }, { name := "v", type := .i32 }],
          results := #[.i32],
          locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
          body := { insns := #[
            .i32Const ZERO_HASH_BUF, .localSet "r",
            .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
          ] ++ mapStorageReadHostInsns 8 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                              .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
            .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName
          ] ++ mapStorageWriteHostInsns 8 32 .near ++ #[
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
          ] ++ mapStorageReadHostInsns 8 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                              .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
            .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
          ] ++ mapStorageWriteHostInsns 8 (scalarWidth vt) .near ++ #[
            .localGet "r" ] } }

/-- NEAR: storage_remove(key_len_i64, key_ptr_i64) → found i64. -/
def mapStorageRemoveHostInsnsNear (keyBytes : Nat) : Array Insn :=
  mapKeyByteLenInsns keyBytes ++ #[.i64Const MAPKEY_BUF, .call "storage_remove"]

def mapDeleteFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      -- Soroban/CosmWasm don't have a direct remove; use _put with zero-length value as a best-effort delete.
      { name := mapDeleteName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
          .i32Const MAPKEY_BUF,
          .localGet "pl", .i32Const 8, .plain "i32.add",
          .i32Const KEY_BUF, .i32Const 0,
          .call "_put",
          .i64Const 0
        ] } }
  | .near =>
      { name := mapDeleteName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
        ] ++ mapStorageRemoveHostInsnsNear 8 } }

def mapDeleteCall (mapInfo : MapInfo) : Except EmitError (Array Insn) :=
  match mapInfo.keyType with
  | .u64 => .ok #[.call (mapDeleteName mapInfo.valueType)]
  | .hash => .ok #[.call (mapDeleteHashName mapInfo.valueType)]
  | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported for delete"

def mapContainsFunc (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban =>
      { name := mapContainsName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
          .i32Const MAPKEY_BUF, .localGet "pl", .i32Const 8, .plain "i32.add", .call "_get",
          .plain "i64.extend_i32_u", .i64Const 0, .plain "i64.ne", .plain "i64.extend_i32_u"
        ] } }
  | .cosmWasm =>
      { name := mapContainsName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
          .i32Const MAPKEY_BUF, .localGet "pl", .i32Const 8, .plain "i32.add", .call "db_read",
          .i64Const 0, .plain "i64.ne", .plain "i64.extend_i32_u"
        ] } }
  | .near =>
      { name := mapContainsName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName
        ] ++ mapKeyByteLenInsns 8 ++ #[
          .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

/-- Nested Map<U64, Map<U64, V>> helpers: compound key = prefix ++ k1 ++ k2 (16 key bytes). -/
def mapReadNestedName (vt : ValueType) : String := "__pf_map_read_nested_" ++ typeSuffix vt
def mapWriteNestedName (vt : ValueType) : String := "__pf_map_write_nested_" ++ typeSuffix vt

/-- After `mapBuildkey(pp,pl,k1)`, store `k2` at MAPKEY_BUF+pl+8. -/
def appendNestedKey2Insns : Array Insn :=
  #[
    .i32Const MAPKEY_BUF, .localGet "pl", .plain "i32.add", .i32Const 8, .plain "i32.add",
    .localGet "k2", .store "i64.store" 0
  ]

def mapReadNestedFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      { name := mapReadNestedName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                    { name := "k1", type := .i64 }, { name := "k2", type := .i64 }],
        results := #[wasmTypeOf vt],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k1", .call mapBuildkeyName
        ] ++ appendNestedKey2Insns ++ mapStorageReadHostInsns 16 bridge ++
          mapRegisterlessReadCoerce bridge vt } }
  | _ =>
      { name := mapReadNestedName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                    { name := "k1", type := .i64 }, { name := "k2", type := .i64 }],
        results := #[wasmTypeOf vt],
        locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
        body := { insns := #[
          .const (wasmTypeOf vt) "0", .localSet "r",
          .localGet "pp", .localGet "pl", .localGet "k1", .call mapBuildkeyName
        ] ++ appendNestedKey2Insns ++ mapStorageReadHostInsns 16 .near ++ #[
          .localSet "found",
          .localGet "found", .i64Const 0, .plain "i64.ne",
          .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                            .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
          .localGet "r" ] } }

def mapWriteNestedFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      { name := mapWriteNestedName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                    { name := "k1", type := .i64 }, { name := "k2", type := .i64 },
                    { name := "v", type := wasmTypeOf vt }],
        results := #[wasmTypeOf vt],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "k1", .call mapBuildkeyName
        ] ++ appendNestedKey2Insns ++ #[
          .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
        ] ++ mapStorageWriteHostInsns 16 (scalarWidth vt) bridge ++ #[
          .localGet "v"
        ] } }
  | _ =>
      { name := mapWriteNestedName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                    { name := "k1", type := .i64 }, { name := "k2", type := .i64 },
                    { name := "v", type := wasmTypeOf vt }],
        results := #[wasmTypeOf vt],
        locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
        body := { insns := #[
          .const (wasmTypeOf vt) "0", .localSet "r",
          .localGet "pp", .localGet "pl", .localGet "k1", .call mapBuildkeyName
        ] ++ appendNestedKey2Insns ++ mapStorageReadHostInsns 16 .near ++ #[
          .localSet "found",
          .localGet "found", .i64Const 0, .plain "i64.ne",
          .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                            .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
          .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
        ] ++ mapStorageWriteHostInsns 16 (scalarWidth vt) .near ++ #[
          .localGet "r"
        ] } }

def mapHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  let nestedReads :=
    plan.u64IndexedReadTypes.foldl (init := (#[] : Array Func)) fun acc type =>
      if type == .hash then acc else acc.push (mapReadNestedFunc type bridge)
  let nestedWrites :=
    plan.u64IndexedWriteTypes.foldl (init := (#[] : Array Func)) fun acc type =>
      if type == .hash then acc else acc.push (mapWriteNestedFunc type bridge)
  (if plan.usesU64IndexedBuildKey then #[mapBuildkeyFunc] else #[]) ++
    (plan.u64IndexedReadTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapReadFunc type bridge]) ++
    (plan.u64IndexedWriteTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapWriteFunc type bridge]) ++
    (plan.u64IndexedWriteTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapDeleteFunc type bridge]) ++
    (if plan.usesU64IndexedContains then #[mapContainsFunc bridge] else #[]) ++
    nestedReads ++ nestedWrites

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

def mapDeleteValueInsns (mapInfo : MapInfo) (keyInsns deleteCall : Array Insn) :
    Array Insn × ValueType :=
  (mapPrefixInsns mapInfo ++ keyInsns ++ deleteCall, mapInfo.valueType)

def nestedMapReadStateInfo (maps : Array MapInfo) (id : String) : Except EmitError MapInfo :=
  match findMapState? maps id with
  | none => err s!"EmitWat: unknown map state `{id}`"
  | some mapInfo =>
    if mapInfo.keyType != .u64 then
      err s!"EmitWat: nested map key must be U64 (`{id}` has key `{mapInfo.keyType.name}`)"
    else .ok mapInfo

def nestedMapReadValueInsns (mapInfo : MapInfo) (key1Insns key2Insns : Array Insn) :
    Array Insn × ValueType :=
  -- Call `__pf_map_read_nested_* (pp, pl, k1, k2)` — compound key prefix||k1||k2.
  (mapPrefixInsns mapInfo ++ key1Insns ++ key2Insns ++
    #[.call (mapReadNestedName mapInfo.valueType)], mapInfo.valueType)

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
    #[.call (mapWriteNestedName mapInfo.valueType)],
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

def mapReadHashFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      if vt == .hash then
        { name := mapReadHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
          results := #[.i32],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
            .i32Const ZERO_HASH_BUF
          ] } }
      else
        { name := mapReadHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
          results := #[wasmTypeOf vt],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
          ] ++ mapStorageReadHostInsns 32 bridge ++ mapRegisterlessReadCoerce bridge vt } }
  | _ =>
      if vt == .hash then
        { name := mapReadHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
          results := #[.i32],
          locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
          body := { insns := #[
            .i32Const ZERO_HASH_BUF, .localSet "r",
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
          ] ++ mapStorageReadHostInsns 32 .near ++ #[
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
          ] ++ mapStorageReadHostInsns 32 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                              .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
            .localGet "r" ] } }

def mapWriteHashFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      if vt == .hash then
        { name := mapWriteHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "kp", type := .i32 }, { name := "v", type := .i32 }],
          results := #[.i32],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
            .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName
          ] ++ mapStorageWriteHostInsns 32 32 bridge ++ #[
            .i32Const ZERO_HASH_BUF
          ] } }
      else
        { name := mapWriteHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "kp", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
          results := #[wasmTypeOf vt],
          body := { insns := #[
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
            .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
          ] ++ mapStorageWriteHostInsns 32 (scalarWidth vt) bridge ++ #[
            .localGet "v"
          ] } }
  | _ =>
      if vt == .hash then
        { name := mapWriteHashName vt,
          params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 },
                      { name := "kp", type := .i32 }, { name := "v", type := .i32 }],
          results := #[.i32],
          locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
          body := { insns := #[
            .i32Const ZERO_HASH_BUF, .localSet "r",
            .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
          ] ++ mapStorageReadHostInsns 32 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                              .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
            .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName
          ] ++ mapStorageWriteHostInsns 32 32 .near ++ #[
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
          ] ++ mapStorageReadHostInsns 32 .near ++ #[
            .localSet "found",
            .localGet "found", .i64Const 0, .plain "i64.ne",
            .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                              .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
            .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0
          ] ++ mapStorageWriteHostInsns 32 (scalarWidth vt) .near ++ #[
            .localGet "r" ] } }

def mapDeleteHashFunc (vt : ValueType) (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban | .cosmWasm =>
      { name := mapDeleteHashName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
          .i32Const MAPKEY_BUF,
          .localGet "pl", .i32Const 32, .plain "i32.add",
          .i32Const KEY_BUF, .i32Const 0,
          .call "_put",
          .i64Const 0
        ] } }
  | .near =>
      { name := mapDeleteHashName vt,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
        ] ++ mapStorageRemoveHostInsnsNear 32 } }

def mapContainsHashFunc (bridge : ProofForge.Target.HostBridge := .near) : Func :=
  match bridge with
  | .soroban =>
      { name := mapContainsHashName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
          .i32Const MAPKEY_BUF, .localGet "pl", .i32Const 32, .plain "i32.add", .call "_get",
          .plain "i64.extend_i32_u", .i64Const 0, .plain "i64.ne", .plain "i64.extend_i32_u"
        ] } }
  | .cosmWasm =>
      { name := mapContainsHashName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
          .i32Const MAPKEY_BUF, .localGet "pl", .i32Const 32, .plain "i32.add", .call "db_read",
          .i64Const 0, .plain "i64.ne", .plain "i64.extend_i32_u"
        ] } }
  | .near =>
      { name := mapContainsHashName,
        params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
        results := #[.i64],
        body := { insns := #[
          .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName
        ] ++ mapKeyByteLenInsns 32 ++ #[
          .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

def mapHashHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  (if plan.usesHashIndexedBuildKey then #[mapBuildkeyHashFunc] else #[]) ++
    (plan.hashIndexedReadTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapReadHashFunc type bridge]) ++
    (plan.hashIndexedWriteTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapWriteHashFunc type bridge]) ++
    (plan.hashIndexedWriteTypes.foldl (init := #[]) fun acc type =>
      acc ++ #[mapDeleteHashFunc type bridge]) ++
    (if plan.usesHashIndexedContains then #[mapContainsHashFunc bridge] else #[])

end ProofForge.Backend.WasmHost.Map
