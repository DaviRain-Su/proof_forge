/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.Hash
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan

namespace ProofForge.Backend.WasmNear.Context

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.Hash
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan

/-! NEAR context host helper functions and context expression lowering. -/

def ctxUserIdName : String := "__pf_ctx_user_id"
def ctxUserHashName : String := "__pf_ctx_user_hash"
def ctxContractIdName : String := "__pf_ctx_contract_id"
def ctxSignerName : String := "__pf_ctx_signer_id"
def ctxRandomSeedName : String := "__pf_ctx_random_seed"

def ctxUserIdFunc : Func :=
  { name := ctxUserIdName, results := #[.i64], locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "predecessor_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len", .i64Const CTX_BUF, .i64Const 1, .call "sha256",
      .i64Const 1, .i64Const CTX_BUF, .call "read_register",
      .i32Const CTX_BUF, .load "i64.load" 0 ] } }

/-- Full sha256(predecessor_account_id_bytes) as a 32-byte hash pointer. -/
def ctxUserHashFunc : Func :=
  { name := ctxUserHashName, results := #[.i32], locals := #[{ name := "len", type := .i64 }, { name := "p", type := .i32 }],
    body := { insns := #[
      .i64Const 0, .call "predecessor_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len", .i64Const CTX_BUF, .i64Const 1, .call "sha256",
      .call hashAllocName, .localSet "p",
      .i64Const 1, .localGet "p", .plain "i64.extend_i32_u", .call "read_register",
      .localGet "p" ] } }

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

def ctxRandomSeedFunc : Func :=
  { name := ctxRandomSeedName, results := #[.i32], locals := #[{ name := "p", type := .i32 }],
    body := { insns := #[
      .i64Const 0, .call "random_seed",
      .call hashAllocName, .localSet "p",
      .i64Const 0, .localGet "p", .plain "i64.extend_i32_u", .call "read_register",
      .localGet "p" ] } }

def ctxHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.contextOps.contains .userId then #[ctxUserIdFunc] else #[]) ++
    (if plan.contextOps.contains .userIdHash then #[ctxUserHashFunc] else #[]) ++
    (if plan.contextOps.contains .contractId then #[ctxContractIdFunc] else #[]) ++
    (if plan.contextOps.contains .origin then #[ctxSignerFunc] else #[]) ++
    (if plan.contextOps.contains .randomSeed then #[ctxRandomSeedFunc] else #[])

def lowerContextExprPlan :
    ContextExprPlan → Except EmitError (Array Insn × ValueType)
  | .userId => .ok (#[.call ctxUserIdName], .u64)
  | .userIdHash => .ok (#[.call ctxUserHashName], .hash)
  | .contractId => .ok (#[.call ctxContractIdName], .u64)
  | .checkpointId => .ok (#[.call "block_index"], .u64)
  | .timestamp => .ok (#[.call "block_timestamp"], .u64)
  | .epochHeight => .ok (#[.call "epoch_height"], .u64)
  | .randomSeed => .ok (#[.call ctxRandomSeedName], .hash)
  | .origin => .ok (#[.call ctxSignerName], .u64)

end ProofForge.Backend.WasmNear.Context
