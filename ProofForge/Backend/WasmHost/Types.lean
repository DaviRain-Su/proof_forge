/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST

namespace ProofForge.Backend.WasmHost.Types

open ProofForge.IR
open ProofForge.Compiler.Wasm

/-! Pure Wasm-NEAR type mapping helpers shared by EmitWat lowering and
artifact-surface obligations. -/

def wasmTypeOf : ValueType → ValType
  | .u32 => .i32 | .u64 => .i64 | .bool => .i32 | .hash => .i32 | .u128 => .i64 | _ => .i32

def widthOf : ValueType → String
  | .u32 => "i32" | .u64 => "i64" | .bool => "i32" | .hash => "i32" | .u128 => "i64" | _ => "i32"

def isNumeric (t : ValueType) : Bool :=
  match t with
  | .u32 | .u64 | .u128 => true
  | _ => false

def isScalarBorshType (t : ValueType) : Bool :=
  match t with
  | .u32 | .u64 | .bool | .hash | .u128 => true
  | _ => false

def scalarWidth : ValueType → Nat
  | .u32 => 4 | .u64 => 8 | .bool => 1 | .hash => 32 | .u128 => 16 | _ => 8

def loadOpFor : ValueType → String
  | .u32 => "i32.load" | .u64 => "i64.load" | .bool => "i32.load8_u" | .u128 => "i64.load" | _ => "i64.load"

def storeOpFor : ValueType → String
  | .u32 => "i32.store" | .u64 => "i64.store" | .bool => "i32.store8" | .u128 => "i64.store" | _ => "i64.store"

def typeSuffix (vt : ValueType) : String :=
  match vt with
  | .u32 => "u32"
  | .u64 => "u64"
  | .bool => "bool"
  | .hash => "hash"
  | .u128 => "u128"
  | _ => "x"

def readName  (vt : ValueType) : String := "__pf_read_"  ++ typeSuffix vt
def writeName (vt : ValueType) : String := "__pf_write_" ++ typeSuffix vt

def returnU32Name  : String := "__pf_return_u32"
def returnU64Name  : String := "__pf_return_u64"
def returnBoolName : String := "__pf_return_bool"
def returnBytesName : String := "__pf_return_bytes"
def returnU128Name : String := "__pf_return_u128"

end ProofForge.Backend.WasmHost.Types
