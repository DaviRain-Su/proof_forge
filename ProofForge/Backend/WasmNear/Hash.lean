/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Common
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Hash

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Common
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.Types

/-! Hash storage and expression helper functions for EmitWat. -/

def modulePlanUsesHashAlloc (plan : ModulePlan) : Bool :=
  plan.usesHashMake || plan.usesHashPreimage || plan.usesHashTwoToOne ||
    plan.scalarReadTypes.contains .hash || plan.contextOps.contains .randomSeed ||
    plan.contextOps.contains .userIdHash

def hashAllocName    : String := "__pf_hash_alloc"
def hashMakeName      : String := "__pf_hash_make"
def hashSName         : String := "__pf_hash"
def hashTwoName       : String := "__pf_hash_two_to_one"
def hashEqName        : String := "__pf_hash_eq"
def readHashName      : String := "__pf_read_hash"
def writeHashName     : String := "__pf_write_hash"
def hashPtrGlobal     : String := "hash_ptr"

def hashPtrGlobalDecl : Global :=
  { name := hashPtrGlobal, type := .i32, init := toString HASH_HEAP, isMutable := true }

def hashAllocFunc : Func :=
  { name := hashAllocName, results := #[.i32],
    body := { insns := #[ .globalGet hashPtrGlobal,
      .globalGet hashPtrGlobal, .i32Const 32, .plain "i32.add", .globalSet hashPtrGlobal ] } }

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

def hashExprHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if modulePlanUsesHashAlloc plan then #[hashAllocFunc] else #[]) ++
    (if plan.usesHashMake then #[hashMakeFunc] else #[]) ++
    (if plan.usesHashPreimage then #[hashSFunc] else #[]) ++
    (if plan.usesMemcpy then #[memcpyFunc] else #[]) ++
    (if plan.usesHashTwoToOne then #[hashTwoFunc] else #[]) ++
    (if plan.usesHashEq then #[hashEqFunc] else #[])

def hashStorageHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.scalarReadTypes.contains .hash then #[readHashFunc] else #[]) ++
    (if plan.scalarWriteTypes.contains .hash then #[writeHashFunc] else #[])

end ProofForge.Backend.WasmNear.Hash
