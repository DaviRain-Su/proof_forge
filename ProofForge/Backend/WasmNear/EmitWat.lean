/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EmitWat — lowers the portable IR (`ProofForge.IR.Contract`) to a `Wasm.Module`
that `Wasm.Printer` renders to WAT, deployable to the NEAR VM via `wat2wasm`.

Canonical wasm-near backend (decision D-023). Scope: scalar value types
U32/U64/Bool/Hash plus flat structs/fixed arrays — literals, locals,
arithmetic, bitwise, shift, comparisons, boolean ops, casts, scalar/map/array
storage, path storage, context, events, bounded control flow, explicit release,
and NEAR `value_return` for U32/U64/Bool/Hash.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.IR.Ownership
import ProofForge.Compiler.Wasm.AST
import ProofForge.Compiler.Wasm.Printer
import ProofForge.Target.Check
import ProofForge.Target.Plan
import ProofForge.Target.Registry

namespace ProofForge.Backend.WasmNear.EmitWat

open ProofForge.IR
open ProofForge.Compiler.Wasm

def indexedEventUnsupportedMessage (name : String) : String :=
  s!"EmitWat: event `{name}` uses indexed fields, but NEAR logs do not support EVM-style topic indexing"

def crosscallUnsupportedMessage : String :=
  "EmitWat: crosscall.invoke maps to NEAR Promise-based execution, but EmitWat v0 has no Promise lowering yet"

structure EmitError where
  message : String
  deriving Repr, Inhabited

def err (msg : String) : Except EmitError α := .error { message := msg }

-- Memory layout
def KEY_BUF   : Nat := 4096
def RET_BUF   : Nat := 8192
def TRUE_PTR  : Nat := 12000
def FALSE_PTR : Nat := 12006
def MAPKEY_BUF : Nat := 12500    -- scratch for building map storage keys (prefix ++ key bytes)
def HASH_HEAP : Nat := 30000       -- bump-allocator base for hash (32-byte) temporaries
def ARR_HEAP : Nat := 60000       -- bump-allocator base for array-value temporaries
def HASH_CONCAT_BUF : Nat := 40000 -- 64-byte scratch for hash_two_to_one
def CTX_BUF : Nat := 41000          -- 128-byte scratch for account-id → sha256 → u64
def EVENT_BUF : Nat := 42000       -- 256-byte scratch for building event JSON
def EVT_KEY_PTR : Nat := 42800     -- fixed "event" key string (5 bytes)
def STRING_BASE : Nat := 43000     -- event/field name string pool base
def INPUT_BUF : Nat := 44000       -- 1 KB scratch for Borsh input args
def PARAM_HASH_BUF : Nat := 46000  -- 32-byte slots for decoded hash params (one per hash param)
def ZERO_HASH_BUF : Nat := 50000  -- 32 zero bytes returned for missing hash-valued map entries
def OLD_HASH_BUF   : Nat := 50500  -- 32-byte slot holding the previous value for hash-valued map set/insert
def STRUCT_BUF      : Nat := 52000  -- buffer for reading/writing struct-valued scalar state

-- Value type → Wasm
def wasmTypeOf : ValueType → ValType
  | .u32 => .i32 | .u64 => .i64 | .bool => .i32 | .hash => .i32 | _ => .i32
def widthOf : ValueType → String
  | .u32 => "i32" | .u64 => "i64" | .bool => "i32" | .hash => "i32" | _ => "i32"
def isNumeric (t : ValueType) : Bool := match t with | .u32 | .u64 => true | _ => false
def isScalarBorshType (t : ValueType) : Bool :=
  match t with | .u32 | .u64 | .bool | .hash => true | _ => false
def scalarWidth : ValueType → Nat
  | .u32 => 4 | .u64 => 8 | .bool => 1 | .hash => 32 | _ => 8
def loadOpFor : ValueType → String
  | .u32 => "i32.load" | .u64 => "i64.load" | .bool => "i32.load8_u" | _ => "i64.load"
def storeOpFor : ValueType → String
  | .u32 => "i32.store" | .u64 => "i64.store" | .bool => "i32.store8" | _ => "i64.store"
def typeSuffix (vt : ValueType) : String :=
  match vt with | .u32 => "u32" | .u64 => "u64" | .bool => "bool" | .hash => "hash" | _ => "x"
def readName  (vt : ValueType) : String := "__pf_read_"  ++ typeSuffix vt
def writeName (vt : ValueType) : String := "__pf_write_" ++ typeSuffix vt
def returnU64Name  : String := "__pf_return_u64"
def returnBoolName : String := "__pf_return_bool"

-- Host imports
def hostImport (name : String) (params results : Array ValType) : Import :=
  { module_ := "env", name := name, funcName := name, type := { params := params, results := results } }

def valTypeOfString : String → ValType
  | "i32" => .i32 | "i64" => .i64 | _ => .i32

def hostFunctionImport (hf : ProofForge.Target.HostFunction) : Import :=
  hostImport hf.name (hf.params.map valTypeOfString) (hf.results.map valTypeOfString)

def bridgeBaseImports (bridge : ProofForge.Target.HostBridge) : Array Import :=
  bridge.hostFunctions.map hostFunctionImport

def nearImports : Array Import := bridgeBaseImports .near

-- Helpers (per scalar type)
def readFunc (vt : ValueType) : Func :=
  { name := readName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }],
    results := #[wasmTypeOf vt],
    locals := #[{ name := "found", type := .i64 }, { name := "r", type := wasmTypeOf vt }],
    body := { insns := #[
      .const (wasmTypeOf vt) "0", .localSet "r",
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 0, .call "storage_read", .localSet "found",
      .localGet "found", .i64Const 0, .plain "i64.ne",
      .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                        .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
      .localGet "r" ] } }

def writeFunc (vt : ValueType) : Func :=
  { name := writeName vt,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := wasmTypeOf vt }],
    results := #[],
    body := { insns := #[
      .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0, .call "storage_write", .drop ] } }

def returnU32Name  : String := "__pf_return_u32"

def returnU64Func : Func :=
  { name := returnU64Name, params := #[{ name := "v", type := .i64 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i64.store" 0,
      .i64Const 8, .i64Const RET_BUF, .call "value_return" ] } }

def returnU32Func : Func :=
  { name := returnU32Name, params := #[{ name := "v", type := .i32 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i32.store" 0,
      .i64Const 4, .i64Const RET_BUF, .call "value_return" ] } }

def returnBoolFunc : Func :=
  { name := returnBoolName, params := #[{ name := "v", type := .i32 }],
    body := { insns := #[
      .i32Const RET_BUF, .localGet "v", .store "i32.store8" 0,
      .i64Const 1, .i64Const RET_BUF, .call "value_return" ] } }

def powName (vt : ValueType) : String := "__pf_pow_" ++ typeSuffix vt

/-- `__pf_pow_<t>(base, exp)`: integer exponentiation by squaring (log2(exp) iterations). -/
def powFunc (vt : ValueType) : Func :=
  let w := widthOf vt
  { name := powName vt,
    params := #[{ name := "base", type := wasmTypeOf vt }, { name := "exp", type := wasmTypeOf vt }],
    results := #[wasmTypeOf vt],
    locals := #[{ name := "r", type := wasmTypeOf vt }],
    body := { insns := #[
      .const (wasmTypeOf vt) "1", .localSet "r",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "exp", .const (wasmTypeOf vt) "0", .plain (w ++ ".eq"), .brIf 1,
        .localGet "exp", .const (wasmTypeOf vt) "1", .plain (w ++ ".and"), .const (wasmTypeOf vt) "0", .plain (w ++ ".ne"),
        .if_ { insns := #[ .localGet "r", .localGet "base", .plain (w ++ ".mul"), .localSet "r" ] } { insns := #[] },
        .localGet "base", .localGet "base", .plain (w ++ ".mul"), .localSet "base",
        .localGet "exp", .const (wasmTypeOf vt) "1", .plain (w ++ ".shr_u"), .localSet "exp",
        .br 0 ] } ] },
      .localGet "r" ] } }

def helperFuncs : Array Func :=
  #[ readFunc .u32, writeFunc .u32, readFunc .u64, writeFunc .u64,
     readFunc .bool, writeFunc .bool, returnU64Func, returnU32Func, returnBoolFunc,
     powFunc .u32, powFunc .u64 ]

-- Map helpers ----------------------------------------------------------
-- Map<U64, T>: storage key = prefix(stateId ++ ":") ++ 8 key bytes.

def mapReadName  (vt : ValueType) : String := "__pf_map_read_"  ++ typeSuffix vt
def mapWriteName (vt : ValueType) : String := "__pf_map_write_" ++ typeSuffix vt
def mapContainsName : String := "__pf_map_contains"
def mapBuildkeyName  : String := "__pf_map_buildkey"
def memcpyName        : String := "__pf_memcpy"

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

def mapReadFunc (vt : ValueType) : Func :=
  if vt == .hash then
    { name := mapReadName vt,
      params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
      results := #[.i32],
      locals := #[{ name := "found", type := .i64 }, { name := "r", type := .i32 }],
      body := { insns := #[
        .i32Const ZERO_HASH_BUF, .localSet "r",
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
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
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
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
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                          .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
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
        .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
        .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }

def mapContainsFunc : Func :=
  { name := mapContainsName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "k", type := .i64 }],
    results := #[.i64],
    body := { insns := #[
      .localGet "pp", .localGet "pl", .localGet "k", .call mapBuildkeyName,
      .localGet "pl", .i32Const 8, .plain "i32.add", .plain "i64.extend_i32_u",
      .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

/-- storage_has_key import (added only when a map is present; see lowerModule). -/
def storageHasKeyImport : Import :=
  hostImport "storage_has_key" #[.i64, .i64] #[.i64]

def mapHelperFuncs : Array Func :=
  #[ mapBuildkeyFunc, mapReadFunc .u32, mapWriteFunc .u32, mapReadFunc .u64, mapWriteFunc .u64,
     mapReadFunc .bool, mapWriteFunc .bool, mapReadFunc .hash, mapWriteFunc .hash, mapContainsFunc ]

-- Map<Hash, T>: storage key = prefix ++ 32 key bytes (key is a hash pointer).

def mapBuildkeyHashName  : String := "__pf_map_buildkey_hash"
def mapReadHashName  (vt : ValueType) : String := "__pf_map_read_hash_"  ++ typeSuffix vt
def mapWriteHashName (vt : ValueType) : String := "__pf_map_write_hash_" ++ typeSuffix vt
def mapContainsHashName : String := "__pf_map_contains_hash"

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
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
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
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
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
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const OLD_HASH_BUF, .call "read_register",
                          .i32Const OLD_HASH_BUF, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .i32Const 32, .call memcpyName,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
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
        .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read", .localSet "found",
        .localGet "found", .i64Const 0, .plain "i64.ne",
        .if_ { insns := #[ .i64Const 0, .i64Const KEY_BUF, .call "read_register",
                          .i32Const KEY_BUF, .load (loadOpFor vt) 0, .localSet "r" ] } { insns := #[] },
        .i32Const KEY_BUF, .localGet "v", .store (storeOpFor vt) 0,
        .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
        .i64Const MAPKEY_BUF, .i64Const (scalarWidth vt), .i64Const KEY_BUF, .i64Const 0,
        .call "storage_write", .drop,
        .localGet "r" ] } }

def mapContainsHashFunc : Func :=
  { name := mapContainsHashName,
    params := #[{ name := "pp", type := .i32 }, { name := "pl", type := .i32 }, { name := "kp", type := .i32 }],
    results := #[.i64],
    body := { insns := #[
      .localGet "pp", .localGet "pl", .localGet "kp", .call mapBuildkeyHashName,
      .localGet "pl", .i32Const 32, .plain "i32.add", .plain "i64.extend_i32_u",
      .i64Const MAPKEY_BUF, .call "storage_has_key" ] } }

def mapHashHelperFuncs : Array Func :=
  #[ mapBuildkeyHashFunc, mapReadHashFunc .u32, mapWriteHashFunc .u32, mapReadHashFunc .u64, mapWriteHashFunc .u64,
     mapReadHashFunc .bool, mapWriteHashFunc .bool, mapReadHashFunc .hash, mapWriteHashFunc .hash, mapContainsHashFunc ]

-- Hash helpers ---------------------------------------------------------
-- Hash = 32-byte memory region (4×u64), referenced by an i32 pointer. A
-- mutable global `hash_ptr` bump-allocates a fresh 32-byte slot per temp
-- (reset each NEAR call since the instance is fresh).

def hashAllocName    : String := "__pf_hash_alloc"
def hashMakeName      : String := "__pf_hash_make"
def hashSName         : String := "__pf_hash"
def hashTwoName       : String := "__pf_hash_two_to_one"
def hashEqName        : String := "__pf_hash_eq"
def readHashName      : String := "__pf_read_hash"
def writeHashName     : String := "__pf_write_hash"
def hashPtrGlobal     : String := "hash_ptr"

def sha256Import : Import := hostImport "sha256" #[.i64, .i64, .i64] #[]
def logUtf8Import : Import := hostImport "log_utf8" #[.i64, .i64] #[]
def inputImport : Import := hostImport "input" #[.i64] #[]
def panicImport : Import := hostImport "panic" #[.i64, .i64] #[]
def predecessorImport : Import := hostImport "predecessor_account_id" #[.i64] #[]
def currentAcctImport : Import := hostImport "current_account_id" #[.i64] #[]
def signerImport : Import := hostImport "signer_account_id" #[.i64] #[]
def depositImport : Import := hostImport "attached_deposit" #[] #[.i64]
def registerLenImport : Import := hostImport "register_len" #[.i64] #[.i64]
def blockHeightImport : Import := hostImport "block_index" #[] #[.i64]
def ctxUserIdName : String := "__pf_ctx_user_id"
def ctxContractIdName : String := "__pf_ctx_contract_id"
def ctxSignerName : String := "__pf_ctx_signer_id"

def hashPtrGlobalDecl : Global :=
  { name := hashPtrGlobal, type := .i32, init := toString HASH_HEAP, isMutable := true }

def hashAllocFunc : Func :=
  { name := hashAllocName, results := #[.i32],
    body := { insns := #[ .globalGet hashPtrGlobal,
      .globalGet hashPtrGlobal, .i32Const 32, .plain "i32.add", .globalSet hashPtrGlobal ] } }

-- Array-value bump allocator (for arrayLit temporaries). Returns current ptr and
-- advances by the byte count; the caller stores elements into [ptr, ptr+n).
def arrPtrGlobal     : String := "arr_ptr"
def arrFreeGlobal    : String := "arr_free"
def arrAllocName     : String := "__pf_arr_alloc"
def allocImportName   : String := "pf_alloc"
def deallocImportName : String := "pf_dealloc"
def arrayLitName (elemType : ValueType) (len : Nat) : String :=
  "__pf_arr_lit_" ++ typeSuffix elemType ++ "_" ++ toString len
def arrEqName (elemType : ValueType) (len : Nat) : String :=
  "__pf_arr_eq_" ++ typeSuffix elemType ++ "_" ++ toString len
def findStruct? (structs : Array ProofForge.IR.StructDecl) (name : String) : Option ProofForge.IR.StructDecl :=
  structs.find? (fun s => s.name == name)
/-- Field offset = prefix sum of `scalarWidth` of preceding fields; total size = sum all. -/
def structTotalSize (s : ProofForge.IR.StructDecl) : Nat :=
  s.fields.foldl (fun acc f => acc + scalarWidth f.type) 0
def structFieldOffset? (s : ProofForge.IR.StructDecl) (fieldName : String) : Option Nat :=
  let rec go (i acc : Nat) : Option Nat :=
    if h : i < s.fields.size then
      let f := s.fields[i]
      if f.id == fieldName then some acc else go (i+1) (acc + scalarWidth f.type)
    else none
  go 0 0
def structFieldType? (s : ProofForge.IR.StructDecl) (fieldName : String) : Option ValueType :=
  (s.fields.find? (fun f => f.id == fieldName)).map (fun f => f.type)
def structLitName (typeName : String) : String := "__pf_struct_lit_" ++ typeName
def isStructStorageFieldType : ValueType → Bool
  | .u32 | .u64 | .bool => true
  | _ => false
def isIndexedStorageValueType : ValueType → Bool
  | .u32 | .u64 | .bool | .hash => true
  | _ => false
def structStorageFieldsSupported (s : ProofForge.IR.StructDecl) : Bool :=
  s.fields.all (fun f => isStructStorageFieldType f.type)
def zeroStructBufInsns (s : ProofForge.IR.StructDecl) : Array Insn :=
  (s.fields.foldl (fun st f =>
      (st.1 + scalarWidth f.type,
       st.2 ++ #[.i32Const st.1, .i32Const STRUCT_BUF, .plain "i32.add",
                 .const (wasmTypeOf f.type) "0", .store (storeOpFor f.type) 0]))
    (0, (#[] : Array Insn))).2
/-- The `arr_ptr` mutable global holds the bump frontier; only emitted for
    chain-deployment allocators (offline imported allocators have no frontier). -/
def arrPtrGlobalDecl (heapBase : Nat) : Global :=
  { name := arrPtrGlobal, type := .i32, init := toString heapBase, isMutable := true }
def arrFreeGlobalDecl : Global :=
  { name := arrFreeGlobal, type := .i32, init := "0", isMutable := true }
/-- `__pf_arr_alloc(n) -> i32` lowered per allocator mode: no-free deployment
    advances the frontier; NEAR/minimal deployment emits a wasm-internal
    first-fit allocator; offline experiments forward to `pf_alloc`. -/
def arrAllocFunc (cfg : ProofForge.IR.AllocatorConfig) : Func :=
  if cfg.usesMinimalMallocShape then
    { name := arrAllocName, params := #[{ name := "n", type := .i64 }], results := #[.i32],
      locals := #[{ name := "need", type := .i32 }, { name := "prev", type := .i32 },
                  { name := "curr", type := .i32 }, { name := "next", type := .i32 },
                  { name := "block", type := .i32 }, { name := "end", type := .i32 }],
      body := { insns := #[
        -- total block size = align8(payload bytes + 8-byte header)
        .localGet "n", .i64Const 15, .plain "i64.add", .const .i64 "-8", .plain "i64.and",
        .plain "i32.wrap_i64", .localSet "need",
        .i32Const 0, .localSet "prev",
        .globalGet arrFreeGlobal, .localSet "curr",
        .block_ { insns := #[ .loop_ { insns := #[
          .localGet "curr", .plain "i32.eqz", .brIf 1,
          .localGet "curr", .load "i32.load" 0, .localGet "need", .plain "i32.ge_u",
          .if_ { insns := #[
            .localGet "curr", .load "i32.load" 4, .localSet "next",
            .localGet "prev", .plain "i32.eqz",
            .if_ { insns := #[ .localGet "next", .globalSet arrFreeGlobal ] }
                 { insns := #[ .localGet "prev", .localGet "next", .store "i32.store" 4 ] },
            .localGet "curr", .i32Const 8, .plain "i32.add", .return_ ] } { insns := #[] },
          .localGet "curr", .localSet "prev",
          .localGet "curr", .load "i32.load" 4, .localSet "curr",
          .br 0 ] } ] },
        .globalGet arrPtrGlobal, .localSet "block",
        .localGet "block", .localGet "need", .plain "i32.add", .localSet "end",
        .localGet "end", .plain "memory.size", .i32Const 65536, .plain "i32.mul", .plain "i32.gt_u",
        .if_ { insns := #[
          .localGet "end", .plain "memory.size", .i32Const 65536, .plain "i32.mul", .plain "i32.sub",
          .i32Const 65535, .plain "i32.add", .i32Const 16, .plain "i32.shr_u",
          .plain "memory.grow", .const .i32 "-1", .plain "i32.eq",
          .if_ { insns := #[.unreachable] } { insns := #[] } ] } { insns := #[] },
        .localGet "end", .globalSet arrPtrGlobal,
        .localGet "block", .localGet "need", .store "i32.store" 0,
        .localGet "block", .i32Const 0, .store "i32.store" 4,
        .localGet "block", .i32Const 8, .plain "i32.add" ] } }
  else
    { name := arrAllocName, params := #[{ name := "n", type := .i64 }], results := #[.i32],
      body := { insns :=
        if cfg.requiresHost then #[.localGet "n", .call allocImportName]
        else #[ .globalGet arrPtrGlobal,
          .globalGet arrPtrGlobal, .localGet "n", .plain "i32.wrap_i64", .plain "i32.add", .globalSet arrPtrGlobal ] } }
/-- `__pf_arr_dealloc(ptr, n)`: no-op for no-free deployment strategies, host
    forwarder for offline experiments, and wasm-internal free-list update for
    chain deployment allocators with reuse. `Statement.release` lowers to this
    helper for heap-backed locals. -/
def arrDeallocFunc (cfg : ProofForge.IR.AllocatorConfig) : Func :=
  if cfg.usesMinimalMallocShape then
    { name := "__pf_arr_dealloc", params := #[{ name := "p", type := .i32 }, { name := "n", type := .i64 }],
      results := #[], locals := #[{ name := "block", type := .i32 }],
      body := { insns := #[
        .localGet "p", .plain "i32.eqz",
        .if_ { insns := #[.return_] } { insns := #[] },
        .localGet "p", .i32Const 8, .plain "i32.sub", .localSet "block",
        .localGet "block", .globalGet arrFreeGlobal, .store "i32.store" 4,
        .localGet "block", .globalSet arrFreeGlobal ] } }
  else
    { name := "__pf_arr_dealloc", params := #[{ name := "p", type := .i32 }, { name := "n", type := .i64 }],
      results := #[],
      body := { insns := if cfg.requiresHost then #[.localGet "p", .localGet "n", .call deallocImportName] else #[] } }
/-- Host imports for reuse-capable strategies: `pf_alloc` + `pf_dealloc`.
    `(import "env" "pf_alloc"   (func (param i64) (result i32)))`
    `(import "env" "pf_dealloc" (func (param i32 i64)))` -/
def allocImport : Import :=
  hostImport allocImportName #[.i64] #[.i32]
def deallocImport : Import :=
  hostImport deallocImportName #[.i32, .i64] #[]

def hashMakeFunc : Func :=
  { name := hashMakeName,
    params := #[{ name := "a", type := .i64 }, { name := "b", type := .i64 },
                { name := "c", type := .i64 }, { name := "d", type := .i64 }],
    results := #[.i32], locals := #[{ name := "p", type := .i32 }],
    body := { insns := #[
      .call hashAllocName, .localSet "p",
      .localGet "p", .localGet "a", .store "i64.store" 0,
      .localGet "p", .localGet "b", .store "i64.store" 8,
      .localGet "p", .localGet "c", .store "i64.store" 16,
      .localGet "p", .localGet "d", .store "i64.store" 24,
      .localGet "p" ] } }

def hashSFunc : Func :=
  { name := hashSName, params := #[{ name := "preimage", type := .i32 }], results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns := #[
      .i64Const 32, .localGet "preimage", .plain "i64.extend_i32_u", .i64Const 0, .call "sha256",
      .call hashAllocName, .localSet "p",
      .i64Const 0, .localGet "p", .plain "i64.extend_i32_u", .call "read_register",
      .localGet "p" ] } }

def memcpyFunc : Func :=
  { name := memcpyName,
    params := #[{ name := "dst", type := .i32 }, { name := "src", type := .i32 }, { name := "n", type := .i32 }],
    locals := #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .localGet "n", .plain "i32.ge_u", .brIf 1,
        .localGet "i", .localGet "dst", .plain "i32.add",
        .localGet "i", .localGet "src", .plain "i32.add", .load "i32.load8_u" 0,
        .store "i32.store8" 0,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0 ] } ] } ] } }

def hashTwoFunc : Func :=
  { name := hashTwoName,
    params := #[{ name := "l", type := .i32 }, { name := "r", type := .i32 }], results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns := #[
      .i32Const HASH_CONCAT_BUF, .localGet "l", .i32Const 32, .call memcpyName,
      .i32Const (HASH_CONCAT_BUF + 32), .localGet "r", .i32Const 32, .call memcpyName,
      .i64Const 64, .i64Const HASH_CONCAT_BUF, .i64Const 0, .call "sha256",
      .call hashAllocName, .localSet "p",
      .i64Const 0, .localGet "p", .plain "i64.extend_i32_u", .call "read_register",
      .localGet "p" ] } }

def hashEqFunc : Func :=
  { name := hashEqName,
    params := #[{ name := "a", type := .i32 }, { name := "b", type := .i32 }], results := #[.i32],
    body := { insns := #[
      .localGet "a", .load "i64.load" 0, .localGet "b", .load "i64.load" 0, .plain "i64.eq",
      .localGet "a", .load "i64.load" 8, .localGet "b", .load "i64.load" 8, .plain "i64.eq", .plain "i32.and",
      .localGet "a", .load "i64.load" 16, .localGet "b", .load "i64.load" 16, .plain "i64.eq", .plain "i32.and",
      .localGet "a", .load "i64.load" 24, .localGet "b", .load "i64.load" 24, .plain "i64.eq", .plain "i32.and" ] } }

def readHashFunc : Func :=
  { name := readHashName,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }], results := #[.i32],
    locals := #[{ name := "found", type := .i64 }, { name := "p", type := .i32 }],
    body := { insns := #[
      .call hashAllocName, .localSet "p",
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 0, .call "storage_read", .localSet "found",
      .localGet "found", .i64Const 0, .plain "i64.ne",
      .if_ { insns := #[ .i64Const 0, .localGet "p", .plain "i64.extend_i32_u", .call "read_register" ] } { insns := #[] },
      .localGet "p" ] } }

def writeHashFunc : Func :=
  { name := writeHashName,
    params := #[{ name := "kp", type := .i32 }, { name := "kl", type := .i32 }, { name := "v", type := .i32 }],
    body := { insns := #[
      .localGet "kl", .plain "i64.extend_i32_u", .localGet "kp", .plain "i64.extend_i32_u",
      .i64Const 32, .localGet "v", .plain "i64.extend_i32_u", .i64Const 0, .call "storage_write", .drop ] } }

def hashHelperFuncs : Array Func :=
  #[ hashAllocFunc, hashMakeFunc, hashSFunc, memcpyFunc, hashTwoFunc, hashEqFunc,
     readHashFunc, writeHashFunc ]

-- Context helpers ------------------------------------------------------
-- userId/contractId: sha256(account_id_bytes)[0..8] as u64.

def ctxUserIdFunc : Func :=
  { name := ctxUserIdName, results := #[.i64], locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "predecessor_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len", .i64Const CTX_BUF, .i64Const 1, .call "sha256",
      .i64Const 1, .i64Const CTX_BUF, .call "read_register",
      .i32Const CTX_BUF, .load "i64.load" 0 ] } }

def ctxContractIdFunc : Func :=
  { name := ctxContractIdName, results := #[.i64], locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "current_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len", .i64Const CTX_BUF, .i64Const 1, .call "sha256",
      .i64Const 1, .i64Const CTX_BUF, .call "read_register",
      .i32Const CTX_BUF, .load "i64.load" 0 ] } }

/-- Signer account id: sha256(signer_account_id_bytes)[0..8] as u64.
    Maps to IR `ContextField.origin` (tx.origin equivalent). On NEAR the signer
    is the account that signed the transaction, distinct from the predecessor
    (the immediate caller). -/
def ctxSignerFunc : Func :=
  { name := ctxSignerName, results := #[.i64], locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "signer_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len", .i64Const CTX_BUF, .i64Const 1, .call "sha256",
      .i64Const 1, .i64Const CTX_BUF, .call "read_register",
      .i32Const CTX_BUF, .load "i64.load" 0 ] } }

def ctxHelperFuncs : Array Func := #[ ctxUserIdFunc, ctxContractIdFunc, ctxSignerFunc ]
def ctxImports : Array Import := #[ predecessorImport, currentAcctImport, registerLenImport, blockHeightImport ]

-- Event helpers --------------------------------------------------------
-- Build a JSON event string in EVENT_BUF via an append pointer, then log_utf8.

def fmtU64Name    : String := "__pf_fmt_u64"
def evtPtrGlobal   : String := "evt_ptr"
def evtStartName   : String := "__pf_evt_start"
def evtPutcName    : String := "__pf_evt_putc"
def evtPutstrName  : String := "__pf_evt_putstr"
def evtPutu64Name  : String := "__pf_evt_putu64"
def evtPutboolName : String := "__pf_evt_putbool"
def evtLogName     : String := "__pf_evt_log"

def evtPtrGlobalDecl : Global :=
  { name := evtPtrGlobal, type := .i32, init := toString EVENT_BUF, isMutable := true }

def fmtU64Func : Func :=
  { name := fmtU64Name, params := #[{ name := "v", type := .i64 }], results := #[.i32],
    locals := #[{ name := "tmp", type := .i64 }, { name := "p", type := .i32 }, { name := "d", type := .i32 }],
    body := { insns := #[
      .localGet "v", .localSet "tmp",
      .i32Const (RET_BUF + 20), .localSet "p",
      .localGet "tmp", .plain "i64.eqz",
      .if_ { insns := #[ .i32Const (RET_BUF + 19), .i32Const 48, .store "i32.store8" 0,
                        .i32Const (RET_BUF + 19), .localSet "p" ] }
         { insns := #[ .block_ { insns := #[ .loop_ { insns := #[
            .localGet "tmp", .plain "i64.eqz", .brIf 1,
            .localGet "tmp", .i64Const 10, .plain "i64.rem_u", .plain "i32.wrap_i64", .localSet "d",
            .localGet "tmp", .i64Const 10, .plain "i64.div_u", .localSet "tmp",
            .localGet "p", .i32Const 1, .plain "i32.sub", .localTee "p",
            .i32Const 48, .localGet "d", .plain "i32.add", .store "i32.store8" 0, .br 0 ] } ] } ] },
      .localGet "p" ] } }

def evtStartFunc : Func :=
  { name := evtStartName, body := { insns := #[ .i32Const EVENT_BUF, .globalSet evtPtrGlobal ] } }

def evtPutcFunc : Func :=
  { name := evtPutcName, params := #[{ name := "c", type := .i32 }],
    body := { insns := #[
      .globalGet evtPtrGlobal, .localGet "c", .store "i32.store8" 0,
      .globalGet evtPtrGlobal, .i32Const 1, .plain "i32.add", .globalSet evtPtrGlobal ] } }

def evtPutstrFunc : Func :=
  { name := evtPutstrName, params := #[{ name := "ptr", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .globalGet evtPtrGlobal, .localGet "ptr", .localGet "len", .call memcpyName,
      .globalGet evtPtrGlobal, .localGet "len", .plain "i32.add", .globalSet evtPtrGlobal ] } }

def evtPutu64Func : Func :=
  { name := evtPutu64Name, params := #[{ name := "v", type := .i64 }],
    locals := #[{ name := "p", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .localGet "v", .call fmtU64Name, .localSet "p",
      .i32Const (RET_BUF + 20), .localGet "p", .plain "i32.sub", .localSet "len",
      .globalGet evtPtrGlobal, .localGet "p", .localGet "len", .call memcpyName,
      .globalGet evtPtrGlobal, .localGet "len", .plain "i32.add", .globalSet evtPtrGlobal ] } }

def evtPutboolFunc : Func :=
  { name := evtPutboolName, params := #[{ name := "b", type := .i32 }],
    body := { insns := #[
      .localGet "b", .plain "i32.eqz",
      .if_ { insns := #[ .i32Const FALSE_PTR, .i32Const 5, .call evtPutstrName ] }
         { insns := #[ .i32Const TRUE_PTR, .i32Const 4, .call evtPutstrName ] } ] } }

def evtLogFunc : Func :=
  { name := evtLogName,
    body := { insns := #[
      .globalGet evtPtrGlobal, .i32Const EVENT_BUF, .plain "i32.sub", .plain "i64.extend_i32_u",
      .i64Const EVENT_BUF, .call "log_utf8" ] } }

def evtHelperFuncs : Array Func :=
  #[ fmtU64Func, evtStartFunc, evtPutcFunc, evtPutstrFunc, evtPutu64Func, evtPutboolFunc, evtLogFunc ]
def evtGlobals : Array Global := #[ evtPtrGlobalDecl ]

-- State layout
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

def readScalarStructBufInsns (s : StateInfo) (sd : ProofForge.IR.StructDecl) : Array Insn :=
  #[.i64Const s.keyLen, .i64Const s.keyPtr, .i64Const 0, .call "storage_read",
    .i64Const 0, .plain "i64.ne",
    .if_ { insns := #[.i64Const 0, .i64Const STRUCT_BUF, .call "read_register"] }
         { insns := zeroStructBufInsns sd }]

structure MapInfo where
  id        : String
  keyType   : ValueType
  valueType : ValueType
  prefixPtr : Nat
  prefixLen : Nat
  isArray   : Bool

/-- Map state → prefix data segment `id ++ ":"` laid out back-to-back from a high offset. -/
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

def readArrayStructBufInsns (m : MapInfo) (s : ProofForge.IR.StructDecl) : Array Insn :=
  #[.i64Const (m.prefixLen + 8), .i64Const MAPKEY_BUF, .i64Const 0, .call "storage_read",
    .i64Const 0, .plain "i64.ne",
    .if_ { insns := #[.i64Const 0, .i64Const STRUCT_BUF, .call "read_register"] }
         { insns := zeroStructBufInsns s }]

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

-- Type-directed expression lowering (mutually recursive)
structure Ctx where
  scalars : Array StateInfo
  maps    : Array MapInfo
  strings : Array StringInfo
  panics  : Array StringInfo
  structs : Array ProofForge.IR.StructDecl
  allocator : ProofForge.IR.AllocatorConfig

structure LBind where
  name : String
  vt : ValueType
abbrev LocalTypes := Array LBind

def lookupLocal? (env : LocalTypes) (name : String) : Option ValueType :=
  match env.find? (fun b => b.name == name) with
  | some b => some b.vt
  | none => none

def assignOpName : AssignOp → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .div => "div_u" | .mod => "rem_u"
  | .bitAnd => "and" | .bitOr => "or" | .bitXor => "xor"
  | .shiftLeft => "shl" | .shiftRight => "shr_u"

mutual
  partial def canDuplicateExpr : Expr → Bool
    | .literal _ => true
    | .local _ => true
    | .arrayLit _ values => values.all canDuplicateExpr
    | .arrayGet array index => canDuplicateExpr array && canDuplicateExpr index
    | .structLit _ fields => fields.all (fun field => canDuplicateExpr field.snd)
    | .field base _ => canDuplicateExpr base
    | .add lhs rhs
    | .sub lhs rhs
    | .mul lhs rhs
    | .div lhs rhs
    | .mod lhs rhs
    | .pow lhs rhs
    | .bitAnd lhs rhs
    | .bitOr lhs rhs
    | .bitXor lhs rhs
    | .shiftLeft lhs rhs
    | .shiftRight lhs rhs
    | .eq lhs rhs
    | .ne lhs rhs
    | .lt lhs rhs
    | .le lhs rhs
    | .gt lhs rhs
    | .ge lhs rhs
    | .boolAnd lhs rhs
    | .boolOr lhs rhs
    | .hashTwoToOne lhs rhs => canDuplicateExpr lhs && canDuplicateExpr rhs
    | .cast value _ => canDuplicateExpr value
    | .boolNot value => canDuplicateExpr value
    | .hashValue a b c d =>
        canDuplicateExpr a && canDuplicateExpr b && canDuplicateExpr c && canDuplicateExpr d
    | .hash preimage => canDuplicateExpr preimage
    | .nativeValue => false
    | .crosscallInvoke _ _ _
    | .crosscallInvokeTyped _ _ _ _
    | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _
    | .crosscallInvokeDelegateTyped _ _ _ _
    | .crosscallCreate _ _
    | .crosscallCreate2 _ _ _
    | .effect _ => false
end

mutual
  partial def lowerExpr (ctx : Ctx) (env : LocalTypes) (e : Expr)
      : Except EmitError (Array Insn × ValueType) :=
    match e with
    | .literal (.u32 n) => .ok (#[.const .i32 (toString n)], .u32)
    | .literal (.u64 n) => .ok (#[.const .i64 (toString n)], .u64)
    | .literal (.bool b) => .ok (#[.const .i32 (if b then "1" else "0")], .bool)
    | .literal (.hash4 a b c d) => .ok (#[.i64Const a, .i64Const b, .i64Const c, .i64Const d, .call hashMakeName], .hash)
    | .hashValue a b c d => do
      let (ia, ta) ← lowerExpr ctx env a
      let (ib, tb) ← lowerExpr ctx env b
      let (ic, tc) ← lowerExpr ctx env c
      let (id_, td) ← lowerExpr ctx env d
      if !(ta == .u64 && tb == .u64 && tc == .u64 && td == .u64) then err "EmitWat: hashValue expects four U64 limbs"
      else .ok (ia ++ ib ++ ic ++ id_ ++ #[.call hashMakeName], .hash)
    | .hash preimage => do
      let (is, t) ← lowerExpr ctx env preimage
      if t != .hash then err s!"EmitWat: hash preimage expected Hash, got `{t.name}`"
      else .ok (is ++ #[.call hashSName], .hash)
    | .hashTwoToOne l r => do
      let (la, ta) ← lowerExpr ctx env l
      let (lb, tb) ← lowerExpr ctx env r
      if !(ta == .hash && tb == .hash) then err "EmitWat: hash_two_to_one expects two Hash operands"
      else .ok (la ++ lb ++ #[.call hashTwoName], .hash)
    | .local name =>
      match lookupLocal? env name with
      | some t => .ok (#[.localGet name], t)
      | none => err s!"EmitWat: unknown local `{name}`"
    | .add a b => lowerNumBin ctx env "add" a b
    | .sub a b => lowerNumBin ctx env "sub" a b
    | .mul a b => lowerNumBin ctx env "mul" a b
    | .div a b => lowerNumBin ctx env "div_u" a b
    | .mod a b => lowerNumBin ctx env "rem_u" a b
    | .bitAnd a b => lowerNumBin ctx env "and" a b
    | .bitOr a b => lowerNumBin ctx env "or" a b
    | .bitXor a b => lowerNumBin ctx env "xor" a b
    | .shiftLeft a b => lowerNumBin ctx env "shl" a b
    | .shiftRight a b => lowerNumBin ctx env "shr_u" a b
    | .pow a b => do
      let (la, ta) ← lowerExpr ctx env a
      let (lb, tb) ← lowerExpr ctx env b
      if !(isNumeric ta && ta == tb) then
        err s!"EmitWat: `pow` expected matching U32/U64 operands, got `{ta.name}`/`{tb.name}`"
      else .ok (la ++ lb ++ #[.call (powName ta)], ta)
    | .eq a b => lowerCmp ctx env "eq" a b
    | .ne a b => lowerCmp ctx env "ne" a b
    | .lt a b => lowerCmp ctx env "lt_u" a b
    | .le a b => lowerCmp ctx env "le_u" a b
    | .gt a b => lowerCmp ctx env "gt_u" a b
    | .ge a b => lowerCmp ctx env "ge_u" a b
    | .boolAnd a b => lowerBoolBin ctx env "and" a b
    | .boolOr a b => lowerBoolBin ctx env "or" a b
    | .boolNot a => do
      let (is, t) ← lowerExpr ctx env a
      if t != .bool then err s!"EmitWat: boolean not operand expected Bool, got `{t.name}`"
      else .ok (is ++ #[.plain "i32.eqz"], .bool)
    | .cast value target => lowerCast ctx env value target
    | .nativeValue =>
      -- NEAR attached_deposit returns U128, but IR v0 treats nativeValue as U64.
      -- For deposits within U64 range (< 2^64), the low 64 bits are the amount.
      -- Call attached_deposit (returns i64 = low 64 bits) and use directly.
      .ok (#[.call "attached_deposit"], .u64)
    | .effect (.storageScalarRead id) =>
      match findScalarState? ctx.scalars id with
      | some s =>
        let callName := if s.type == .hash then readHashName else readName s.type
        .ok (#[.i32Const s.keyPtr, .i32Const s.keyLen, .call callName], s.type)
      | none => err s!"EmitWat: unknown scalar state `{id}`"
    | .effect (.storageMapGet id key) => lowerMapGet ctx env id key
    | .effect (.storageMapContains id key) => lowerMapContains ctx env id key
    | .effect (.contextRead .userId) => .ok (#[.call ctxUserIdName], .u64)
    | .effect (.contextRead .contractId) => .ok (#[.call ctxContractIdName], .u64)
    | .effect (.contextRead .checkpointId) => .ok (#[.call "block_index"], .u64)
    | .effect (.contextRead .origin) => .ok (#[.call ctxSignerName], .u64)
    | .effect (.storageMapSet id key value) | .effect (.storageMapInsert id key value) =>
      lowerMapWrite ctx env id key value
    | .effect (.storageArrayRead id index) => lowerStorageArrayRead ctx env id index
    | .effect (.storageArrayStructFieldRead id index fieldName) =>
      lowerArrayStructFieldRead ctx env id index fieldName
    | .effect (.storageStructFieldRead id fieldName) =>
      lowerScalarStructFieldRead ctx id fieldName
    | .effect (.storagePathRead id path) =>
      lowerStoragePathRead ctx env id path
    | .arrayLit elementType values => do
      let lowered ← values.mapM fun v => do
        let (is, t) ← lowerExpr ctx env v
        if t != elementType then err s!"EmitWat: arrayLit element expected `{elementType.name}`, got `{t.name}`"
        else .ok is
      .ok (lowered.foldl (fun acc is => acc ++ is) #[] ++ #[.call (arrayLitName elementType values.size)],
            .fixedArray elementType values.size)
    | .arrayGet array index => do
      let (pa, ta) ← lowerExpr ctx env array
      let (pi, ti) ← lowerExpr ctx env index
      match ta with
      | .fixedArray elemType _ =>
        if !(ti == .u32 || ti == .u64) then
          err s!"EmitWat: arrayGet index must be U32/U64, got `{ti.name}`"
        else do
          let conv := if ti == .u64 then #[.plain "i32.wrap_i64"] else #[]
          .ok (pa ++ pi ++ conv ++ #[.i32Const (scalarWidth elemType), .plain "i32.mul",
                .plain "i32.add", .load (loadOpFor elemType) 0], elemType)
      | _ => err s!"EmitWat: arrayGet expected an array value, got `{ta.name}`"
    | .structLit typeName fields => do
      match findStruct? ctx.structs typeName with
      | none => err s!"EmitWat: unknown struct `{typeName}`"
      | some s =>
        let argInsns ← s.fields.mapM fun f =>
          match fields.find? (fun (n, _) => n == f.id) with
          | none => err s!"EmitWat: structLit `{typeName}` missing field `{f.id}`"
          | some (_, vexpr) => do
            let (vis, vt) ← lowerExpr ctx env vexpr
            if vt != f.type then
              err s!"EmitWat: struct field `{typeName}.{f.id}` expected `{f.type.name}`, got `{vt.name}`"
            else .ok vis
        .ok (argInsns.foldl (fun acc is => acc ++ is) #[] ++ #[.call (structLitName typeName)],
              .structType typeName)
    | .field base fieldName => do
      let (pb, tb) ← lowerExpr ctx env base
      match tb with
      | .structType typeName =>
        match findStruct? ctx.structs typeName with
        | none => err s!"EmitWat: unknown struct `{typeName}`"
        | some s =>
          match structFieldOffset? s fieldName, structFieldType? s fieldName with
          | some off, some ft =>
            .ok (pb ++ #[.i32Const off, .plain "i32.add", .load (loadOpFor ft) 0], ft)
          | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
      | _ => err s!"EmitWat: field access expects a struct value, got `{tb.name}`"
    | .crosscallInvokeTyped _ _ _ _ | .crosscallInvoke _ _ _ | .crosscallInvokeValueTyped _ _ _ _ _
    | .crosscallInvokeStaticTyped _ _ _ _ | .crosscallInvokeDelegateTyped _ _ _ _
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ =>
      -- Cross-contract call / contract creation via NEAR Promise API.
      -- For create/create2: NEAR has no CREATE opcode equivalent; log and
      -- return 0 as a promise index placeholder.
      .ok (#[
        .i32Const 4, .i32Const EVT_KEY_PTR, .call "log_utf8",
        .i64Const 0, .call "current_account_id",
        .i64Const 0, .call "register_len",
        .i64Const 0, .i32Const CTX_BUF, .call "read_register",
        .i64Const 0, .call "register_len",
        .i32Const CTX_BUF,
        .i32Const CTX_BUF, .i64Const 0,
        .i64Const 0, .i64Const 0, .i64Const 10000000000000,
        .call "promise_create"
      ], .u64)
    | _ => err "EmitWat: this expression form is not yet supported"

  partial def lowerNumBin (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if !(isNumeric ta && ta == tb) then
      err s!"EmitWat: `{op}` expected matching U32/U64 operands, got `{ta.name}`/`{tb.name}`"
    else .ok (la ++ lb ++ #[.plain (widthOf ta ++ "." ++ op)], ta)

  partial def lowerCmp (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if ta != tb then err s!"EmitWat: `{op}` expected matching operand types, got `{ta.name}`/`{tb.name}`"
    else if ta == .hash && op == "eq" then .ok (la ++ lb ++ #[.call hashEqName], .bool)
    else if ta == .hash && op == "ne" then .ok (la ++ lb ++ #[.call hashEqName, .plain "i32.eqz"], .bool)
    else match ta with
      | .fixedArray elemType len =>
        if op == "eq" then .ok (la ++ lb ++ #[.call (arrEqName elemType len)], .bool)
        else if op == "ne" then .ok (la ++ lb ++ #[.call (arrEqName elemType len), .plain "i32.eqz"], .bool)
        else err s!"EmitWat: `{op}` not supported on array values"
      | _ => .ok (la ++ lb ++ #[.plain (widthOf ta ++ "." ++ op)], .bool)

  partial def lowerBoolBin (ctx : Ctx) (env : LocalTypes) (op : String) (a b : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if !(ta == .bool && tb == .bool) then err s!"EmitWat: boolean `{op}` expected Bool operands"
    else .ok (la ++ lb ++ #[.plain ("i32." ++ op)], .bool)

  partial def lowerCast (ctx : Ctx) (env : LocalTypes) (value : Expr) (target : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    let (is, src) ← lowerExpr ctx env value
    let extra ←
      match src, target with
      | .u32, .u64 => .ok #[.plain "i64.extend_i32_u"]
      | .u64, .u32 => .ok #[.plain "i32.wrap_i64"]
      | .u32, .bool => .ok #[.i32Const 0, .plain "i32.ne"]
      | .u64, .bool => .ok #[.i64Const 0, .plain "i64.ne"]
      | .bool, .u32 => .ok #[]
      | .bool, .u64 => .ok #[.plain "i64.extend_i32_u"]
      | _, _ => err s!"EmitWat: cast from `{src.name}` to `{target.name}` is not supported"
    .ok (is ++ extra, target)

  partial def lowerMapKeyU64 (ctx : Ctx) (env : LocalTypes) (key : Expr)
      : Except EmitError (Array Insn) := do
    let (is, t) ← lowerExpr ctx env key
    if t != .u64 then err s!"EmitWat: map key expected U64, got `{t.name}`"
    else .ok is

  partial def lowerMapKeyHash (ctx : Ctx) (env : LocalTypes) (key : Expr)
      : Except EmitError (Array Insn) := do
    let (is, t) ← lowerExpr ctx env key
    if t != .hash then err s!"EmitWat: map key expected Hash, got `{t.name}`"
    else .ok is

  partial def lowerMapGet (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    match findMapState? ctx.maps id with
    | none => err s!"EmitWat: unknown map state `{id}`"
    | some m =>
      if m.isArray then err s!"EmitWat: state `{id}` is an array; use storageArrayRead or an index storage path"
      else do
        let readCall ← match m.keyType with
          | .u64 => do pure #[.call (mapReadName m.valueType)]
          | .hash => do pure #[.call (mapReadHashName m.valueType)]
          | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported (`{id}` has key `{m.keyType.name}`)"
        let kis ← if m.keyType == .hash then lowerMapKeyHash ctx env key else lowerMapKeyU64 ctx env key
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ readCall, m.valueType)

  /-- Nested map read: Map<K1, Map<K2, V>>. Builds compound key:
      mapBuildkey writes prefix + key1 to MAPKEY_BUF, then we manually
      append key2 bytes at MAPKEY_BUF + prefixLen + 8.
      Then call storage_read with extended key length = prefixLen + 16. -/
  partial def lowerNestedMapGet (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    match findMapState? ctx.maps id with
    | none => err s!"EmitWat: unknown map state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: nested map key must be U64 (`{id}` has key `{m.keyType.name}`)"
      else do
        let readCall := #[.call (mapReadName m.valueType)]
        let ki1 ← lowerMapKeyU64 ctx env key1
        let ki2 ← lowerMapKeyU64 ctx env key2
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ ki1 ++ ki2 ++ readCall, m.valueType)

  partial def lowerMapContains (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    match findMapState? ctx.maps id with
    | none => err s!"EmitWat: unknown map state `{id}`"
    | some m =>
      if m.isArray then err s!"EmitWat: state `{id}` is an array; map contains is only valid for map state"
      else do
        let containsCall ← match m.keyType with
          | .u64 => do pure #[.call mapContainsName]
          | .hash => do pure #[.call mapContainsHashName]
          | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported"
        let kis ← if m.keyType == .hash then lowerMapKeyHash ctx env key else lowerMapKeyU64 ctx env key
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ containsCall ++ #[.plain "i32.wrap_i64"], .bool)
  partial def lowerMapWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (key : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    match findMapState? ctx.maps id with
    | none => err s!"EmitWat: unknown map state `{id}`"
    | some m =>
      if m.isArray then err s!"EmitWat: state `{id}` is an array; use storageArrayWrite or an index storage path"
      else do
        let writeCall ← match m.keyType with
          | .u64 => pure #[.call (mapWriteName m.valueType)]
          | .hash => pure #[.call (mapWriteHashName m.valueType)]
          | _ => err s!"EmitWat: only Map<U64|Hash, T> is supported"
        let kis ← if m.keyType == .hash then lowerMapKeyHash ctx env key else lowerMapKeyU64 ctx env key
        if valueType != m.valueType then err s!"EmitWat: map write `{id}` expected `{m.valueType.name}`, got `{valueType.name}`"
        else .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ valueInsns ++ writeCall, m.valueType)

  partial def lowerMapWrite (ctx : Ctx) (env : LocalTypes) (id : String) (key value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerMapWriteValue ctx env id key vis vt

  /-- Nested map write with pre-evaluated value instructions. -/
  partial def lowerNestedMapWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    match findMapState? ctx.maps id with
    | none => err s!"EmitWat: unknown map state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: nested map key must be U64"
      else if valueType != m.valueType then err s!"EmitWat: nested map write `{id}` expected `{m.valueType.name}`, got `{valueType.name}`"
      else do
        let writeCall := #[.call (mapWriteName m.valueType)]
        let ki1 ← lowerMapKeyU64 ctx env key1
        let ki2 ← lowerMapKeyU64 ctx env key2
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ ki1 ++ ki2 ++ valueInsns ++ writeCall, m.valueType)

  /-- Nested map write: Map<K1, Map<K2, V>>. -/
  partial def lowerNestedMapWrite (ctx : Ctx) (env : LocalTypes) (id : String) (key1 key2 value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerNestedMapWriteValue ctx env id key1 key2 vis vt

  partial def lowerStorageArrayRead (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    match findArrayState? ctx.maps id with
    | none => err s!"EmitWat: unknown array state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
      else if !isIndexedStorageValueType m.valueType then
        err s!"EmitWat: indexed storage path `{id}` has unsupported element type `{m.valueType.name}`; use index+field for struct arrays"
      else do
        let kis ← lowerMapKeyU64 ctx env index
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ #[.call (mapReadName m.valueType)], m.valueType)

  partial def lowerStorageArrayWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn × ValueType) := do
    match findArrayState? ctx.maps id with
    | none => err s!"EmitWat: unknown array state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
      else if !isIndexedStorageValueType m.valueType then
        err s!"EmitWat: indexed storage path `{id}` has unsupported element type `{m.valueType.name}`; use index+field for struct arrays"
      else if valueType != m.valueType then
        err s!"EmitWat: array write `{id}` expected `{m.valueType.name}`, got `{valueType.name}`"
      else do
        let kis ← lowerMapKeyU64 ctx env index
        .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ valueInsns ++ #[.call (mapWriteName m.valueType)], m.valueType)

  partial def lowerStorageArrayWrite (ctx : Ctx) (env : LocalTypes) (id : String) (index value : Expr)
      : Except EmitError (Array Insn × ValueType) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerStorageArrayWriteValue ctx env id index vis vt

  partial def lowerScalarStructFieldRead (ctx : Ctx) (id fieldName : String)
      : Except EmitError (Array Insn × ValueType) := do
    match findScalarState? ctx.scalars id with
    | none => err s!"EmitWat: unknown scalar state `{id}`"
    | some s => match s.type with
      | .structType typeName =>
        match findStruct? ctx.structs typeName with
        | none => err s!"EmitWat: unknown struct `{typeName}`"
        | some sd =>
          if !structStorageFieldsSupported sd then
            err s!"EmitWat: scalar struct `{typeName}` storage fields must be U32/U64/Bool"
          else match structFieldOffset? sd fieldName, structFieldType? sd fieldName with
            | some off, some ft =>
              if !isStructStorageFieldType ft then
                err s!"EmitWat: scalar struct field `{typeName}.{fieldName}` has unsupported type `{ft.name}`"
              else
                .ok (readScalarStructBufInsns s sd ++
                  #[.i32Const off, .i32Const STRUCT_BUF, .plain "i32.add", .load (loadOpFor ft) 0], ft)
            | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
      | _ => err s!"EmitWat: storageStructFieldRead expects a struct state, got `{s.type.name}`"

  partial def lowerScalarStructFieldWriteValue (ctx : Ctx) (id fieldName : String)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn) := do
    match findScalarState? ctx.scalars id with
    | none => err s!"EmitWat: unknown scalar state `{id}`"
    | some s => match s.type with
      | .structType typeName =>
        match findStruct? ctx.structs typeName with
        | none => err s!"EmitWat: unknown struct `{typeName}`"
        | some sd =>
          if !structStorageFieldsSupported sd then
            err s!"EmitWat: scalar struct `{typeName}` storage fields must be U32/U64/Bool"
          else match structFieldOffset? sd fieldName, structFieldType? sd fieldName with
            | some off, some ft =>
              if !isStructStorageFieldType ft then
                err s!"EmitWat: scalar struct field `{typeName}.{fieldName}` has unsupported type `{ft.name}`"
              else if valueType != ft then
                err s!"EmitWat: struct field write `{id}.{fieldName}` expected `{ft.name}`, got `{valueType.name}`"
              else
                .ok (readScalarStructBufInsns s sd ++
                  #[.i32Const off, .i32Const STRUCT_BUF, .plain "i32.add"] ++ valueInsns ++
                  #[.store (storeOpFor ft) 0,
                    .i64Const s.keyLen, .i64Const s.keyPtr, .i64Const (structTotalSize sd),
                    .i64Const STRUCT_BUF, .i64Const 0, .call "storage_write", .drop])
            | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
      | _ => err s!"EmitWat: storageStructFieldWrite expects a struct state, got `{s.type.name}`"

  partial def lowerScalarStructFieldWrite (ctx : Ctx) (env : LocalTypes) (id fieldName : String) (value : Expr)
      : Except EmitError (Array Insn) := do
    let (vis, vt) ← lowerExpr ctx env value
    lowerScalarStructFieldWriteValue ctx id fieldName vis vt

  partial def lowerArrayStructFieldRead (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String)
      : Except EmitError (Array Insn × ValueType) := do
    match findArrayState? ctx.maps id with
    | none => err s!"EmitWat: unknown array state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
      else match m.valueType with
        | .structType typeName =>
          match findStruct? ctx.structs typeName with
          | none => err s!"EmitWat: unknown struct `{typeName}`"
          | some sd =>
            if !structStorageFieldsSupported sd then
              err s!"EmitWat: array struct `{typeName}` storage fields must be U32/U64/Bool"
            else match structFieldOffset? sd fieldName, structFieldType? sd fieldName with
              | some off, some ft =>
                if !isStructStorageFieldType ft then
                  err s!"EmitWat: array struct field `{typeName}.{fieldName}` has unsupported type `{ft.name}`"
                else do
                  let kis ← lowerMapKeyU64 ctx env index
                  .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ kis ++ #[.call mapBuildkeyName]
                        ++ readArrayStructBufInsns m sd
                        ++ #[.i32Const off, .i32Const STRUCT_BUF, .plain "i32.add", .load (loadOpFor ft) 0],
                        ft)
              | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
        | _ => err s!"EmitWat: storageArrayStructFieldRead expects a struct-valued array, got `{m.valueType.name}`"

  partial def lowerArrayStructFieldWriteValue (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String)
      (valueInsns : Array Insn) (valueType : ValueType)
      : Except EmitError (Array Insn) := do
    match findArrayState? ctx.maps id with
    | none => err s!"EmitWat: unknown array state `{id}`"
    | some m =>
      if m.keyType != .u64 then err s!"EmitWat: storage array `{id}` index must be U64"
      else if !canDuplicateExpr index then
        err "EmitWat: storage array struct field path index must be a pure expression until key temporaries are lowered"
      else match m.valueType with
        | .structType typeName =>
          match findStruct? ctx.structs typeName with
          | none => err s!"EmitWat: unknown struct `{typeName}`"
          | some sd =>
            if !structStorageFieldsSupported sd then
              err s!"EmitWat: array struct `{typeName}` storage fields must be U32/U64/Bool"
            else match structFieldOffset? sd fieldName, structFieldType? sd fieldName with
              | some off, some ft =>
                if !isStructStorageFieldType ft then
                  err s!"EmitWat: array struct field `{typeName}.{fieldName}` has unsupported type `{ft.name}`"
                else if valueType != ft then
                  err s!"EmitWat: array struct field write `{id}[].{fieldName}` expected `{ft.name}`, got `{valueType.name}`"
                else do
                  let readKey ← lowerMapKeyU64 ctx env index
                  let writeKey ← lowerMapKeyU64 ctx env index
                  .ok (#[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ readKey ++ #[.call mapBuildkeyName]
                        ++ readArrayStructBufInsns m sd
                        ++ #[.i32Const off, .i32Const STRUCT_BUF, .plain "i32.add"] ++ valueInsns ++ #[.store (storeOpFor ft) 0]
                        ++ #[.i32Const m.prefixPtr, .i32Const m.prefixLen] ++ writeKey ++
                        #[.call mapBuildkeyName, .i64Const (m.prefixLen + 8), .i64Const MAPKEY_BUF,
                          .i64Const (structTotalSize sd), .i64Const STRUCT_BUF, .i64Const 0, .call "storage_write", .drop])
              | _, _ => err s!"EmitWat: struct `{typeName}` has no field `{fieldName}`"
        | _ => err s!"EmitWat: storageArrayStructFieldWrite expects a struct-valued array, got `{m.valueType.name}`"

  partial def lowerArrayStructFieldWrite (ctx : Ctx) (env : LocalTypes) (id : String) (index : Expr) (fieldName : String) (value : Expr)
      : Except EmitError (Array Insn) := do
    if !canDuplicateExpr value then
      err "EmitWat: storageArrayStructFieldWrite value must be a pure expression while STRUCT_BUF is the field patch buffer"
    let (vis, vt) ← lowerExpr ctx env value
    lowerArrayStructFieldWriteValue ctx env id index fieldName vis vt

  partial def lowerStoragePathRead (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment)
      : Except EmitError (Array Insn × ValueType) := do
    match path.toList with
    | [.mapKey key] => lowerMapGet ctx env id key
    | [.index index] => lowerStorageArrayRead ctx env id index
    | [.field fieldName] => lowerScalarStructFieldRead ctx id fieldName
    | [.index index, .field fieldName] => lowerArrayStructFieldRead ctx env id index fieldName
    | [.mapKey key1, .mapKey key2] =>
      -- Nested map: Map<K1, Map<K2, V>>. Encode as compound key:
      -- prefix ++ key1_bytes ++ key2_bytes in MAPKEY_BUF.
      lowerNestedMapGet ctx env id key1 key2
    | _ => err "EmitWat: storagePathRead supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def lowerStoragePathWrite (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment) (value : Expr)
      : Except EmitError (Array Insn) := do
    match path.toList with
    | [.mapKey key] => do
      let (is, _) ← lowerMapWrite ctx env id key value
      .ok (is ++ #[.drop])
    | [.index index] => do
      let (is, _) ← lowerStorageArrayWrite ctx env id index value
      .ok (is ++ #[.drop])
    | [.field fieldName] => do
      if !canDuplicateExpr value then
        err "EmitWat: storagePathWrite field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      lowerScalarStructFieldWrite ctx env id fieldName value
    | [.index index, .field fieldName] =>
      lowerArrayStructFieldWrite ctx env id index fieldName value
    | [.mapKey key1, .mapKey key2] => do
      let (is, _) ← lowerNestedMapWrite ctx env id key1 key2 value
      .ok (is ++ #[.drop])
    | _ => err "EmitWat: storagePathWrite supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def lowerStoragePathAssignOp (ctx : Ctx) (env : LocalTypes) (id : String) (path : Array StoragePathSegment)
      (op : AssignOp) (value : Expr) : Except EmitError (Array Insn) := do
    match path.toList with
    | [.mapKey key] => do
      if !canDuplicateExpr key then
        err "EmitWat: storagePathAssignOp mapKey must be a pure expression until key temporaries are lowered"
      let (currentInsns, currentType) ← lowerMapGet ctx env id key
      if !isNumeric currentType then
        err s!"EmitWat: storagePathAssignOp requires U32/U64 map values, got `{currentType.name}`"
      let (valueInsns, valueType) ← lowerExpr ctx env value
      if valueType != currentType then
        err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
      let computed := currentInsns ++ valueInsns ++ #[.plain (widthOf currentType ++ "." ++ assignOpName op)]
      let (writeInsns, _) ← lowerMapWriteValue ctx env id key computed currentType
      .ok (writeInsns ++ #[.drop])
    | [.index index] => do
      if !canDuplicateExpr index then
        err "EmitWat: storagePathAssignOp index must be a pure expression until key temporaries are lowered"
      let (currentInsns, currentType) ← lowerStorageArrayRead ctx env id index
      if !isNumeric currentType then
        err s!"EmitWat: storagePathAssignOp requires U32/U64 array values, got `{currentType.name}`"
      let (valueInsns, valueType) ← lowerExpr ctx env value
      if valueType != currentType then
        err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
      let computed := currentInsns ++ valueInsns ++ #[.plain (widthOf currentType ++ "." ++ assignOpName op)]
      let (writeInsns, _) ← lowerStorageArrayWriteValue ctx env id index computed currentType
      .ok (writeInsns ++ #[.drop])
    | [.field fieldName] => do
      if !canDuplicateExpr value then
        err "EmitWat: storagePathAssignOp field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      let (currentInsns, currentType) ← lowerScalarStructFieldRead ctx id fieldName
      if !isNumeric currentType then
        err s!"EmitWat: storagePathAssignOp requires U32/U64 struct fields, got `{currentType.name}`"
      let (valueInsns, valueType) ← lowerExpr ctx env value
      if valueType != currentType then
        err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
      let computed := currentInsns ++ valueInsns ++ #[.plain (widthOf currentType ++ "." ++ assignOpName op)]
      lowerScalarStructFieldWriteValue ctx id fieldName computed currentType
    | [.index index, .field fieldName] => do
      if !canDuplicateExpr value then
        err "EmitWat: storagePathAssignOp index+field value must be a pure expression while STRUCT_BUF is the field patch buffer"
      let (currentInsns, currentType) ← lowerArrayStructFieldRead ctx env id index fieldName
      if !isNumeric currentType then
        err s!"EmitWat: storagePathAssignOp requires U32/U64 array struct fields, got `{currentType.name}`"
      let (valueInsns, valueType) ← lowerExpr ctx env value
      if valueType != currentType then
        err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
      let computed := currentInsns ++ valueInsns ++ #[.plain (widthOf currentType ++ "." ++ assignOpName op)]
      lowerArrayStructFieldWriteValue ctx env id index fieldName computed currentType
    | [.mapKey key1, .mapKey key2] => do
      let (currentInsns, currentType) ← lowerNestedMapGet ctx env id key1 key2
      if !isNumeric currentType then
        err s!"EmitWat: storagePathAssignOp requires U32/U64 nested map values, got `{currentType.name}`"
      let (valueInsns, valueType) ← lowerExpr ctx env value
      if valueType != currentType then
        err s!"EmitWat: storagePathAssignOp expected `{currentType.name}`, got `{valueType.name}`"
      let opInsn : Insn := .plain (widthOf currentType ++ "." ++ assignOpName op)
      let computed := currentInsns ++ valueInsns ++ #[opInsn]
      let (writeInsns, _) ← lowerNestedMapWriteValue ctx env id key1 key2 computed currentType
      .ok (writeInsns ++ #[.drop])
    | _ => err "EmitWat: storagePathAssignOp supports mapKey, index, field, index+field, or nested mapKey+mapKey paths"

  partial def collectArrayLitsPathSegment (segment : StoragePathSegment) : Array (ValueType × Nat) :=
    match segment with
    | .field _ => #[]
    | .index index => collectArrayLitsExpr index
    | .mapKey key => collectArrayLitsExpr key
  partial def collectArrayLitsPath (path : Array StoragePathSegment) : Array (ValueType × Nat) :=
    path.foldl (fun acc segment => acc ++ collectArrayLitsPathSegment segment) #[]

  partial def collectArrayLitsExpr (e : Expr) : Array (ValueType × Nat) :=
    match e with
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit elementType values =>
        #[(elementType, values.size)] ++ values.foldl (fun acc v => acc ++ collectArrayLitsExpr v) #[]
    | .arrayGet array index => collectArrayLitsExpr array ++ collectArrayLitsExpr index
    | .structLit _ fields => fields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
    | .field base _ => collectArrayLitsExpr base
    | .add a b | .sub a b | .mul a b | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b => collectArrayLitsExpr a ++ collectArrayLitsExpr b
    | .cast value _ => collectArrayLitsExpr value
    | .boolNot value => collectArrayLitsExpr value
    | .hashValue a b c d => collectArrayLitsExpr a ++ collectArrayLitsExpr b ++ collectArrayLitsExpr c ++ collectArrayLitsExpr d
    | .hash preimage => collectArrayLitsExpr preimage
    | .hashTwoToOne a b => collectArrayLitsExpr a ++ collectArrayLitsExpr b
    | .nativeValue => #[]
    | .crosscallInvoke t m args => collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallInvokeTyped t m args _
    | .crosscallInvokeStaticTyped t m args _
    | .crosscallInvokeDelegateTyped t m args _ =>
        collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallInvokeValueTyped t m v args _ =>
        collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ collectArrayLitsExpr v ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallCreate value _ => collectArrayLitsExpr value
    | .crosscallCreate2 value salt _ => collectArrayLitsExpr value ++ collectArrayLitsExpr salt
    | .effect eff => collectArrayLitsEffect eff
  partial def collectArrayLitsEffect (eff : Effect) : Array (ValueType × Nat) :=
    match eff with
    | .storageScalarWrite _ v => collectArrayLitsExpr v
    | .storageScalarAssignOp _ _ v => collectArrayLitsExpr v
    | .storageMapContains _ k => collectArrayLitsExpr k
    | .storageMapGet _ k => collectArrayLitsExpr k
    | .storageMapInsert _ k v | .storageMapSet _ k v => collectArrayLitsExpr k ++ collectArrayLitsExpr v
    | .storageArrayRead _ i => collectArrayLitsExpr i
    | .storageArrayWrite _ i v => collectArrayLitsExpr i ++ collectArrayLitsExpr v
    | .storageArrayStructFieldRead _ i _ => collectArrayLitsExpr i
    | .storageArrayStructFieldWrite _ i _ v => collectArrayLitsExpr i ++ collectArrayLitsExpr v
    | .storageDynamicArrayPush _ v => collectArrayLitsExpr v
    | .storageDynamicArrayPop _ => #[]
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ v => collectArrayLitsExpr v
    | .storagePathRead _ path => collectArrayLitsPath path
    | .storagePathWrite _ path v => collectArrayLitsPath path ++ collectArrayLitsExpr v
    | .storagePathAssignOp _ path _ v => collectArrayLitsPath path ++ collectArrayLitsExpr v
    | .contextRead _ => #[]
    | .eventEmit _ fields => fields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
        dataFields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) indexed
    | .storageScalarRead _ => #[]
  partial def collectStructLitsExpr (e : Expr) : Array String :=
    match e with
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values => values.foldl (fun acc v => acc ++ collectStructLitsExpr v) #[]
    | .arrayGet a i => collectStructLitsExpr a ++ collectStructLitsExpr i
    | .structLit typeName fields => #[typeName] ++ fields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
    | .field base _ => collectStructLitsExpr base
    | .add a b | .sub a b | .mul a b | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b => collectStructLitsExpr a ++ collectStructLitsExpr b
    | .cast value _ | .boolNot value => collectStructLitsExpr value
    | .hash preimage => collectStructLitsExpr preimage
    | .hashValue a b c d => collectStructLitsExpr a ++ collectStructLitsExpr b ++ collectStructLitsExpr c ++ collectStructLitsExpr d
    | .hashTwoToOne a b => collectStructLitsExpr a ++ collectStructLitsExpr b
    | .crosscallInvoke t m args => collectStructLitsExpr t ++ collectStructLitsExpr m ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallInvokeTyped t m args _
    | .crosscallInvokeStaticTyped t m args _
    | .crosscallInvokeDelegateTyped t m args _ =>
        collectStructLitsExpr t ++ collectStructLitsExpr m ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallInvokeValueTyped t m v args _ =>
        collectStructLitsExpr t ++ collectStructLitsExpr m ++ collectStructLitsExpr v ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallCreate value _ => collectStructLitsExpr value
    | .crosscallCreate2 value salt _ => collectStructLitsExpr value ++ collectStructLitsExpr salt
    | .effect eff => collectStructLitsEffect eff
  partial def collectStructLitsPathSegment (segment : StoragePathSegment) : Array String :=
    match segment with
    | .field _ => #[]
    | .index index => collectStructLitsExpr index
    | .mapKey key => collectStructLitsExpr key
  partial def collectStructLitsPath (path : Array StoragePathSegment) : Array String :=
    path.foldl (fun acc segment => acc ++ collectStructLitsPathSegment segment) #[]
  partial def collectStructLitsEffect (eff : Effect) : Array String :=
    match eff with
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v => collectStructLitsExpr v
    | .storageMapContains _ k | .storageMapGet _ k => collectStructLitsExpr k
    | .storageMapInsert _ k v | .storageMapSet _ k v => collectStructLitsExpr k ++ collectStructLitsExpr v
    | .storageArrayRead _ i => collectStructLitsExpr i
    | .storageArrayWrite _ i v => collectStructLitsExpr i ++ collectStructLitsExpr v
    | .storageArrayStructFieldRead _ i _ => collectStructLitsExpr i
    | .storageArrayStructFieldWrite _ i _ v => collectStructLitsExpr i ++ collectStructLitsExpr v
    | .storageDynamicArrayPush _ v => collectStructLitsExpr v
    | .storageDynamicArrayPop _ => #[]
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ v => collectStructLitsExpr v
    | .storagePathRead _ path => collectStructLitsPath path
    | .storagePathWrite _ path v => collectStructLitsPath path ++ collectStructLitsExpr v
    | .storagePathAssignOp _ path _ v => collectStructLitsPath path ++ collectStructLitsExpr v
    | .contextRead _ => #[]
    | .eventEmit _ fields => fields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
        dataFields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) indexed
    | .storageScalarRead _ => #[]
end

-- Statements
partial def collectArrayLitsStmt (s : Statement) : Array (ValueType × Nat) :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v => collectArrayLitsExpr v
  | .assign _ v | .assignOp _ _ v => collectArrayLitsExpr v
  | .effect eff => collectArrayLitsEffect eff
  | .assert c _ _ => collectArrayLitsExpr c
  | .assertEq a b _ _ => collectArrayLitsExpr a ++ collectArrayLitsExpr b
  | .ifElse c t e => collectArrayLitsExpr c ++ t.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[] ++ e.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
  | .boundedFor _ _ _ body => body.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
  | .release _ | .revert _ | .revertWithError _ => #[]
  | .return v => collectArrayLitsExpr v
def dedupArrayLits (xs : Array (ValueType × Nat)) : Array (ValueType × Nat) :=
  xs.foldl (fun acc x => if acc.any (fun y => y.1 == x.1 && y.2 == x.2) then acc else acc.push x) #[]
def moduleArrayLits (mod : ProofForge.IR.Module) : Array (ValueType × Nat) :=
  dedupArrayLits (mod.entrypoints.foldl (fun acc ep => acc ++ ep.body.foldl (fun a st => a ++ collectArrayLitsStmt st) #[]) #[])
def arrLitFunc (elemType : ValueType) (len : Nat) : Func :=
  let w := scalarWidth elemType
  { name := arrayLitName elemType len,
    params := (Array.range len).map (fun i => { name := s!"e{i}", type := wasmTypeOf elemType }),
    results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns :=
      #[.i64Const (len * w), .call arrAllocName, .localSet "p"] ++
      ((Array.range len).map fun i => #[
        .i32Const (w * i), .localGet "p", .plain "i32.add",
        .localGet s!"e{i}", .store (storeOpFor elemType) 0
      ]).flatten ++ #[.localGet "p"] } }
def arrLitHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleArrayLits mod |>.map (fun (e, n) => arrLitFunc e n)
/-- `__pf_arr_eq_<elem>_<len>(pa, pb) -> i32`: element-wise equality.
    Returns 1 if all len elements match, 0 on first mismatch. -/
def arrEqFunc (elemType : ValueType) (len : Nat) : Func :=
  let w   := scalarWidth elemType
  let lop := loadOpFor elemType
  let neq := if elemType == .u64 then "i64.ne" else "i32.ne"
  { name := arrEqName elemType len,
    params := #[{ name := "pa", type := .i32 }, { name := "pb", type := .i32 }],
    results := #[.i32],
    locals := #[{ name := "eq", type := .i32 }, { name := "i", type := .i32 }],
    body := { insns := #[.i32Const 1, .localSet "eq",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .i32Const len, .plain "i32.ge_u", .brIf 1,
        .localGet "pa", .localGet "i", .i32Const w, .plain "i32.mul", .plain "i32.add", .load lop 0,
        .localGet "pb", .localGet "i", .i32Const w, .plain "i32.mul", .plain "i32.add", .load lop 0,
        .plain neq,
        .if_ { insns := #[.i32Const 0, .localSet "eq", .br 2] } { insns := #[] },
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] } ] },
      .localGet "eq"] } }
def arrEqHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleArrayLits mod |>.map (fun (e, n) => arrEqFunc e n)
/-- `__pf_struct_lit_<name>(f0,f1,..) -> i32`: alloc totalSize bytes, store each
    field at its cumulative offset, return the base pointer. -/
def structLitFunc (s : ProofForge.IR.StructDecl) : Func :=
  let total := structTotalSize s
  let stores : Array Insn :=
    (s.fields.foldl (fun st f =>
        (st.1 + scalarWidth f.type,
         st.2 ++ #[.i32Const st.1, .localGet "p", .plain "i32.add",
                   .localGet f.id, .store (storeOpFor f.type) 0]))
      (0, (#[] : Array Insn))).2
  { name := structLitName s.name,
    params := s.fields.map (fun f => { name := f.id, type := wasmTypeOf f.type }),
    results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns :=
      #[.i64Const total, .call arrAllocName, .localSet "p"] ++ stores ++ #[.localGet "p"] } }
partial def collectStructLitsStmt (s : Statement) : Array String :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v => collectStructLitsExpr v
  | .assign _ v | .assignOp _ _ v => collectStructLitsExpr v
  | .effect eff => collectStructLitsEffect eff
  | .assert c _ _ => collectStructLitsExpr c
  | .assertEq a b _ _ => collectStructLitsExpr a ++ collectStructLitsExpr b
  | .ifElse c t e => collectStructLitsExpr c ++ t.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[] ++ e.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
  | .boundedFor _ _ _ body => body.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
  | .release _ | .revert _ | .revertWithError _ => #[]
  | .return v => collectStructLitsExpr v
def dedupStrings (xs : Array String) : Array String :=
  xs.foldl (fun acc x => if acc.any (fun y => y == x) then acc else acc.push x) #[]
def moduleStructLitNames (mod : ProofForge.IR.Module) : Array String :=
  dedupStrings (mod.entrypoints.foldl (fun acc ep => acc ++ ep.body.foldl (fun a st => a ++ collectStructLitsStmt st) #[]) #[])
def structLitHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleStructLitNames mod |>.filterMap (fun name => (mod.structs.find? (fun s => s.name == name)).map structLitFunc)

partial def collectLocalsFrom (acc : LocalTypes) (s : Statement) : Except EmitError LocalTypes := do
  match s with
  | .letBind name t _ | .letMutBind name t _ =>
    if isNumeric t || t == .bool || t == .hash then .ok (acc.push { name := name, vt := t })
    else match t with
      | .fixedArray _ _ | .structType _ => .ok (acc.push { name := name, vt := t })
      | _ => err s!"EmitWat: only U32/U64/Bool/Hash/FixedArray/Struct locals are supported (got `{t.name}`)"
  | .ifElse _ thenBody elseBody =>
    let acc ← thenBody.foldlM (init := acc) collectLocalsFrom
    elseBody.foldlM (init := acc) collectLocalsFrom
  | .boundedFor indexName _ _ body =>
    let acc := acc.push { name := indexName, vt := .u64 }
    body.foldlM (init := acc) collectLocalsFrom
  | .release _ => .ok acc
  | _ => .ok acc

def collectLocals (body : Array Statement) : Except EmitError LocalTypes :=
  body.foldlM (init := #[]) collectLocalsFrom

def lowerReturn (ctx : Ctx) (env : LocalTypes) (expected : ValueType) (e : Expr)
    : Except EmitError (Array Insn) := do
  let (is, t) ← lowerExpr ctx env e
  if t != expected then err s!"EmitWat: return expected `{expected.name}`, got `{t.name}`"
  else match t with
    | .u64 => .ok (is ++ #[.call returnU64Name])
    | .u32 => .ok (is ++ #[.call returnU32Name])
    | .bool => .ok (is ++ #[.call returnBoolName])
    | .hash => .ok (#[.i64Const 32] ++ is ++ #[.plain "i64.extend_i32_u", .call "value_return"])
    | _ => err s!"EmitWat: return type `{t.name}` is not supported"

partial def lowerEventEmit (ctx : Ctx) (env : LocalTypes) (name : String) (fields : Array (String × Expr))
    : Except EmitError (Array Insn) := do
  let some nameSi ← pure (findString? ctx.strings name) | err s!"EmitWat: event name `{name}` not in string pool"
  let putc (c : Nat) : Array Insn := #[.i32Const c, .call evtPutcName]
  let header : Array Insn := #[.call evtStartName] ++ putc 0x7B ++ putc 0x22
    ++ #[.i32Const EVT_KEY_PTR, .i32Const 5, .call evtPutstrName] ++ putc 0x22 ++ putc 0x3A ++ putc 0x22
    ++ #[.i32Const nameSi.ptr, .i32Const nameSi.len, .call evtPutstrName] ++ putc 0x22
  let fieldInsns ← fields.foldlM (init := #[]) fun acc f => do
    let (fname, vexpr) := f
    let some fsi ← pure (findString? ctx.strings fname) | err s!"EmitWat: field name `{fname}` not in string pool"
    let (vis, vt) ← lowerExpr ctx env vexpr
    let valInsn ←
      match vt with
      | .u64 => .ok #[.call evtPutu64Name]
      | .u32 => .ok #[.plain "i64.extend_i32_u", .call evtPutu64Name]
      | .bool => .ok #[.call evtPutboolName]
      | _ => err s!"EmitWat: event field `{fname}` has unsupported type `{vt.name}`"
    .ok (acc ++ putc 0x2C ++ putc 0x22 ++ #[.i32Const fsi.ptr, .i32Const fsi.len, .call evtPutstrName]
            ++ putc 0x22 ++ putc 0x3A ++ vis ++ valInsn)
  .ok (header ++ fieldInsns ++ putc 0x7D ++ #[.call evtLogName])

partial def lowerStmt (ctx : Ctx) (env : LocalTypes) (returns : ValueType)
    (s : Statement) : Except EmitError (Array Insn) :=
  match s with
  | .letBind name t e | .letMutBind name t e => do
    let (is, te) ← lowerExpr ctx env e
    if te != t then err s!"EmitWat: let `{name}` expected `{t.name}`, got `{te.name}`"
    else .ok (is ++ #[.localSet name])
  | .assign (.local name) e => do
    let (is, _) ← lowerExpr ctx env e
    if (lookupLocal? env name).isNone then err s!"EmitWat: assignment to unknown local `{name}`"
    else .ok (is ++ #[.localSet name])
  | .assign _ _ => err "EmitWat: assignment target must be a local"
  | .assignOp (.local name) op e => do
    let some lt ← pure (lookupLocal? env name) | err s!"EmitWat: compound assignment to unknown local `{name}`"
    if !(isNumeric lt) then err "EmitWat: compound assignment requires U32/U64 local"
    else do
      let (is, t) ← lowerExpr ctx env e
      if t != lt then err s!"EmitWat: compound `{assignOpName op}` expected `{lt.name}`, got `{t.name}`"
      else .ok (#[.localGet name] ++ is ++ #[.plain (widthOf lt ++ "." ++ assignOpName op), .localSet name])
  | .assignOp _ _ _ => err "EmitWat: compound assignment target must be a local"
  | .effect (.storageScalarWrite id e) => do
    let some s ← pure (findScalarState? ctx.scalars id) | err s!"EmitWat: unknown scalar state `{id}`"
    let (is, t) ← lowerExpr ctx env e
    if t != s.type then err s!"EmitWat: scalar write `{id}` expected `{s.type.name}`, got `{t.name}`"
    else match s.type with
      | .structType typeName =>
        match findStruct? ctx.structs typeName with
        | none => err s!"EmitWat: unknown struct `{typeName}`"
        | some sd => .ok (#[.i64Const s.keyLen, .i64Const s.keyPtr, .i64Const (structTotalSize sd)]
                          ++ is ++ #[.plain "i64.extend_i32_u", .i64Const 0, .call "storage_write", .drop])
      | _ =>
        let callName := if s.type == .hash then writeHashName else writeName s.type
        .ok (#[.i32Const s.keyPtr, .i32Const s.keyLen] ++ is ++ #[.call callName])
  | .effect (.storageStructFieldWrite id fieldName value) => do
    lowerScalarStructFieldWrite ctx env id fieldName value
  | .effect (.storagePathWrite id path value) => do
    lowerStoragePathWrite ctx env id path value
  | .effect (.storagePathAssignOp id path op value) => do
    lowerStoragePathAssignOp ctx env id path op value
  | .effect (.storageScalarAssignOp id op value) => do
    let some s ← pure (findScalarState? ctx.scalars id) | err s!"EmitWat: unknown scalar state `{id}`"
    if s.type == .hash then err s!"EmitWat: storageScalarAssignOp not supported on Hash scalars (`{id}`)"
    else do
      let (vis, vt) ← lowerExpr ctx env value
      if vt != s.type then err s!"EmitWat: scalar assignOp `{id}` expected `{s.type.name}`, got `{vt.name}`"
      else .ok (#[.i32Const s.keyPtr, .i32Const s.keyLen, .i32Const s.keyPtr, .i32Const s.keyLen,
                     .call (readName s.type)] ++ vis
                ++ #[.plain (widthOf s.type ++ "." ++ assignOpName op), .call (writeName s.type)])
  | .effect (.storageMapSet id key value) | .effect (.storageMapInsert id key value) => do
    let (is, _) ← lowerMapWrite ctx env id key value
    .ok (is ++ #[.drop])
  | .effect (.storageArrayWrite id index value) => do
    let (is, _) ← lowerStorageArrayWrite ctx env id index value
    .ok (is ++ #[.drop])
  | .effect (.storageArrayStructFieldWrite id index fieldName value) => do
    lowerArrayStructFieldWrite ctx env id index fieldName value
  | .effect (.eventEmit name fields) => lowerEventEmit ctx env name fields
  | .effect (.eventEmitIndexed name indexedFields dataFields) =>
      -- NEAR events are log_utf8 strings; indexed/data distinction is EVM-specific.
      -- Flatten all fields into a single JSON event log (same as non-indexed).
      lowerEventEmit ctx env name (indexedFields ++ dataFields)
  | .assert cond _ errorRef? => do
    let (is, t) ← lowerExpr ctx env cond
    if t != .bool then err "EmitWat: assert condition must be Bool"
    else
      let failInsns := match errorRef? with
        | none => #[.unreachable]
        | some ref =>
          let msg := panicMessage ref
          match ctx.panics.find? (fun si => si.str == msg) with
          | none => #[.unreachable]
          | some si => #[.i64Const si.len, .i64Const si.ptr, .call "panic"]
      .ok (is ++ #[.plain "i32.eqz", .if_ { insns := failInsns } { insns := #[] }])
  | .assertEq a b _ errorRef? => do
    let (la, ta) ← lowerExpr ctx env a
    let (lb, tb) ← lowerExpr ctx env b
    if ta != tb then err "EmitWat: assertEq operands must share a type"
    else
      let eqInsn := match ta with
        | .hash => #[.call hashEqName]
        | .fixedArray elemType len => #[.call (arrEqName elemType len)]
        | _ => #[.plain (widthOf ta ++ ".eq")]
      let failInsns := match errorRef? with
        | none => #[.unreachable]
        | some ref =>
          let msg := panicMessage ref
          match ctx.panics.find? (fun si => si.str == msg) with
          | none => #[.unreachable]
          | some si => #[.i64Const si.len, .i64Const si.ptr, .call "panic"]
      .ok (la ++ lb ++ eqInsn ++ #[.plain "i32.eqz",
                            .if_ { insns := failInsns } { insns := #[] }])
  | .release name => do
    let some vt ← pure (lookupLocal? env name) | err s!"EmitWat: release of unknown local `{name}`"
    match vt with
    | .fixedArray elemType len =>
      .ok #[.localGet name, .i64Const (len * scalarWidth elemType), .call "__pf_arr_dealloc"]
    | .structType typeName =>
      match findStruct? ctx.structs typeName with
      | none => err s!"EmitWat: release refers to unknown struct `{typeName}`"
      | some sd => .ok #[.localGet name, .i64Const (structTotalSize sd), .call "__pf_arr_dealloc"]
    | _ => err s!"EmitWat: release expects a heap-backed FixedArray/Struct local, got `{vt.name}`"
  | .return e => lowerReturn ctx env returns e
  | .ifElse cond thenBody elseBody => do
    let (cis, ct) ← lowerExpr ctx env cond
    if ct != .bool then err "EmitWat: if/else condition must be Bool"
    else do
      let thenInsns ← thenBody.foldlM (init := #[]) fun acc s => return acc ++ (← lowerStmt ctx env returns s)
      let elseInsns ← elseBody.foldlM (init := #[]) fun acc s => return acc ++ (← lowerStmt ctx env returns s)
      .ok (cis ++ #[.if_ { insns := thenInsns } { insns := elseInsns }])
  | .boundedFor indexName start stop body => do
    let bodyInsns ← body.foldlM (init := #[]) fun acc s => return acc ++ (← lowerStmt ctx env returns s)
    .ok (#[.i64Const start, .localSet indexName,
           .block_ { insns := #[ .loop_ { insns := #[
             .localGet indexName, .i64Const stop, .plain "i64.ge_u", .brIf 1 ] ++ bodyInsns ++ #[
             .localGet indexName, .i64Const 1, .plain "i64.add", .localSet indexName, .br 0 ] } ] } ])
  | _ => err "EmitWat: this statement form is not yet supported"

/-- Build the Borsh input prologue: env.input -> INPUT_BUF, then load each
    param at its cumulative Borsh offset into a local. Entrypoint params have
    no wasm-level params; they are decoded from input and held in locals.

    Scalar types (u32/u64/bool) load directly. Hash loads 32 bytes into a
    param hash slot. Fixed arrays of scalars and flat structs are decoded
    from Borsh (fields/elements laid out sequentially) into heap-allocated
    memory, with the local holding an i32 pointer. -/
def loadParams (structs : Array ProofForge.IR.StructDecl)
    (params : Array (String × ValueType))
    : Except EmitError (Array Insn × Array Local) := do
  let prologue : Array Insn :=
    #[.i64Const 0, .call "input", .i64Const 0, .i64Const INPUT_BUF, .call "read_register"]
  let result ← params.foldlM (init := (prologue, (#[] : Array Local), 0, 0))
    fun (insns, locals, offset, hslot) p =>
      let (name, vt) := p
      match vt with
      | .u32 | .u64 | .bool =>
        let loadInsns := #[.i32Const (INPUT_BUF + offset), .load (loadOpFor vt) 0, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + scalarWidth vt, hslot)
      | .hash =>
        let slot := PARAM_HASH_BUF + hslot * 32
        let loadInsns := #[.i32Const slot, .i32Const (INPUT_BUF + offset), .i32Const 32, .call memcpyName,
                           .i32Const slot, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + 32, hslot + 1)
      | .fixedArray elemType n =>
        if !(isScalarBorshType elemType) then
          err s!"EmitWat: param `{name}` has unsupported fixedArray element type `{elemType.name}` (only scalar elements supported in Borsh params)"
        else
          let elemWidth := scalarWidth elemType
          let totalBytes := n * elemWidth
          let loadInsns :=
            #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
            (Array.range n).foldl (fun (acc : Array Insn) i =>
              let srcOff := INPUT_BUF + offset + i * elemWidth
              let dstOff := i * elemWidth
              let loadElem :=
                if elemType == ProofForge.IR.ValueType.hash then
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .i32Const 32, .call memcpyName]
                else
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .load (loadOpFor elemType) 0,
                    .store (storeOpFor elemType) 0]
              acc ++ loadElem) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | .structType typeName =>
        match structs.find? (fun s => s.name == typeName) with
        | none => err s!"EmitWat: param `{name}` references unknown struct `{typeName}`"
        | some sd =>
          if !structStorageFieldsSupported sd then
            err s!"EmitWat: param `{name}` struct `{typeName}` has non-scalar fields (only u32/u64/bool/hash supported in Borsh params)"
          else
            let totalBytes := structTotalSize sd
            let loadInsns :=
              #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
              sd.fields.foldl (fun (acc : Array Insn) f =>
                let fieldOff := structFieldOffset? sd f.id |>.getD 0
                let srcOff := INPUT_BUF + offset + fieldOff
                let dstOff := fieldOff
                let loadField :=
                  if f.type == ProofForge.IR.ValueType.hash then
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .i32Const 32, .call memcpyName]
                  else
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .load (loadOpFor f.type) 0,
                      .store (storeOpFor f.type) 0]
                acc ++ loadField) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | _ => err s!"EmitWat: param `{name}` has unsupported Borsh type `{vt.name}`"
  pure (result.fst, result.snd.fst)

def lowerEntrypoint (ctx : Ctx) (ep : Entrypoint) : Except EmitError Func := do
  let bodyLocals ← collectLocals ep.body
  let (paramPrologue, paramLocals) ← loadParams ctx.structs ep.params
  let allLocalTypes : LocalTypes :=
    (ep.params.map (fun (n, t) => { name := n, vt := t : LBind })) ++ bodyLocals
  let locals := paramLocals ++ bodyLocals.map (fun b => { name := b.name, type := wasmTypeOf b.vt : Local })
  let bodyInsns ← ep.body.foldlM (init := #[]) fun acc s => return acc ++ (← lowerStmt ctx allLocalTypes ep.returns s)
  let resetPrefix : Array Insn :=
    if ctx.allocator.usesEntryReset then
      #[.i32Const ctx.allocator.heapBase, .globalSet arrPtrGlobal]
    else #[]
  .ok { name := ep.name, locals := locals, body := { insns := resetPrefix ++ paramPrologue ++ bodyInsns }, exportName := ep.name }

def lowerModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := .near) : Except EmitError ProofForge.Compiler.Wasm.Module := do
  if bridge == .cosmWasm then
    err "EmitWat: CosmWasm bridge lowering is implemented in Backend.CosmWasm.EmitWat; use that module for wasm-cosmwasm"
  if mod.allocator.isCosmWasmRegion then
    err "EmitWat: alloc.cosmwasm_region is for the CosmWasm adapter, not wasm-near EmitWat"
  let scalars := stateLayout mod
  let maps := mapLayout mod
  let strs := stringPool mod
  let stringPoolEnd := strs.foldl (init := STRING_BASE) fun acc s => max acc (s.ptr + s.len + 1)
  let panics := panicPool mod stringPoolEnd
  let ctx := { scalars := scalars, maps := maps, strings := strs, panics := panics, structs := mod.structs, allocator := mod.allocator : Ctx }
  let entryFuncs ← mod.entrypoints.mapM (lowerEntrypoint ctx)
  let scalarData := scalars.map fun s => { offset := s.keyPtr, bytes := s.id : DataSegment }
  let mapData := maps.map fun m => { offset := m.prefixPtr, bytes := m.id ++ ":" : DataSegment }
  let boolData : Array DataSegment :=
    #[{ offset := TRUE_PTR, bytes := "true" }, { offset := FALSE_PTR, bytes := "false" }]
  let evtKeyData : DataSegment := { offset := EVT_KEY_PTR, bytes := "event" }
  let stringData := strs.map fun si => { offset := si.ptr, bytes := si.str : DataSegment }
  let panicData := panics.map fun si => { offset := si.ptr, bytes := si.str : DataSegment }
  let hasPanic := !panics.isEmpty
  let baseImports := (nearImports.push sha256Import |>.push logUtf8Import |>.push inputImport) ++ (if hasPanic then #[panicImport] else #[])
  let isHost := mod.allocator.requiresHost
  let extraImports := if isHost then #[allocImport, deallocImport] else #[]
  let imports := baseImports ++ ctxImports ++ (if maps.isEmpty then #[] else #[storageHasKeyImport]) ++ extraImports
  let arrFuncs := arrLitHelperFuncs mod ++ arrEqHelperFuncs mod ++ structLitHelperFuncs mod
    ++ #[arrAllocFunc mod.allocator, arrDeallocFunc mod.allocator]
  let funcs := helperFuncs ++ hashHelperFuncs ++ ctxHelperFuncs ++ evtHelperFuncs ++ (if maps.isEmpty then #[] else mapHelperFuncs) ++ (if maps.any (fun m => m.keyType == .hash) then mapHashHelperFuncs else #[]) ++ arrFuncs ++ entryFuncs
  let arrPtrDecls :=
    if isHost then #[]
    else if mod.allocator.usesMinimalMallocShape then
      #[arrPtrGlobalDecl mod.allocator.heapBase, arrFreeGlobalDecl]
    else #[arrPtrGlobalDecl mod.allocator.heapBase]
  let globals := #[hashPtrGlobalDecl] ++ evtGlobals ++ arrPtrDecls
  .ok { imports := imports, globals := globals, funcs := funcs,
        memory := some { min := 1 },
        dataSegments := scalarData ++ mapData ++ boolData ++ #[evtKeyData] ++ stringData ++ (if hasPanic then panicData else #[]) }

/-! EmitWat supports the same capability surface as the `wasmNear` target profile,
    plus `controlConditional` and `controlBoundedLoop` (if/else + boundedFor are
    lowered natively in WAT). This set is intentionally kept in sync with the
    `wasmNear` profile so that the target-adapter capability gate and EmitWat's
    own gate reject the same shapes. Aggregate entrypoint params (structs/arrays)
    and cross-contract calls are NOT in this set; they stay rejected until the
    profile explicitly opens them. -/
def emitWatCapabilities : ProofForge.Target.CapabilitySet :=
  ProofForge.Target.wasmNear.capabilities

def checkCapabilities (mod : ProofForge.IR.Module) : Except EmitError Unit :=
  mod.capabilities.foldlM (fun _ c =>
    if emitWatCapabilities.contains c then .ok ()
    else if c == .crosscallInvoke then .error { message := crosscallUnsupportedMessage }
    else .error { message := s!"EmitWat: capability `{c.id}` is not supported by the EmitWat backend" }) ()

def checkTargetPlan (plan : ProofForge.Target.CapabilityPlan) : Except EmitError Unit :=
  if plan.targetId == ProofForge.Target.wasmNear.id then
    .ok ()
  else
    .error { message := s!"EmitWat plan requires target `wasm-near`, got `{plan.targetId}`" }

def renderCheckedModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Except EmitError String := do
  match ProofForge.IR.Ownership.checkModule mod with
  | .ok _ => pure ()
  | .error error => err s!"EmitWat: {error.render}"
  let m ← lowerModule mod bridge
  .ok (Printer.render m)

def renderModule (mod : ProofForge.IR.Module) (bridge : ProofForge.Target.HostBridge := .near) :
    Except EmitError String := do
  checkCapabilities mod
  renderCheckedModule mod bridge

def renderModuleWithPlan
    (mod : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Except EmitError String := do
  checkTargetPlan plan
  renderCheckedModule mod bridge


end ProofForge.Backend.WasmNear.EmitWat
