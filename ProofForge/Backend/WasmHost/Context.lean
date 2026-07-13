/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan

namespace ProofForge.Backend.WasmHost.Context

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Hash
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan

/-! NEAR context host helper functions and context expression lowering. -/

def ctxUserIdName : String := "__pf_ctx_user_id"
def ctxUserHashName : String := "__pf_ctx_user_hash"
def ctxAccountIdName : String := "__pf_ctx_account_id"
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

/-! Raw predecessor_account_id as a variable-length string (Phase 3 NEP-141
    interop). VOID: stages the account-id bytes at `ACCT_ID_BUF` and the 4-byte
    LE length at `ACCT_ID_LEN` (NEAR has no multi-value return, so the caller
    materializes `(ptr, len)` from the staged slots). No sha256 — identity is
    not hash-truncated. -/
def ctxAccountIdFunc : Func :=
  { name := ctxAccountIdName, results := #[],
    locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "predecessor_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const ACCT_ID_BUF, .call "read_register",
      .i32Const ACCT_ID_LEN, .localGet "len", .plain "i32.wrap_i64",
      .store "i32.store" 0 ] } }

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

def ctxHelperFuncsForModulePlan (plan : ModulePlan)
    (bridge : ProofForge.Target.HostBridge := .near) : Array Func :=
  match bridge with
  | .soroban =>
    -- Soroban: caller identity is authenticated via require_auth_for_args
    -- (in auth prologue). Context helpers use retained NEAR-style imports
    -- (predecessor_account_id etc.) for account-id hashing. randomSeed and
    -- gas are not supported — fail closed by not emitting helpers.
    (if plan.contextOps.contains .userId then #[ctxUserIdFunc] else #[]) ++
      (if plan.contextOps.contains .userIdHash then #[ctxUserHashFunc] else #[]) ++
      (if plan.contextOps.contains .contractId then #[ctxContractIdFunc] else #[]) ++
      (if plan.contextOps.contains .origin then #[ctxSignerFunc] else #[])
      -- randomSeed: NOT supported on Soroban (no import)
  | _ =>
    (if plan.contextOps.contains .userId then #[ctxUserIdFunc] else #[]) ++
      (if plan.contextOps.contains .userIdHash then #[ctxUserHashFunc] else #[]) ++
      (if plan.contextOps.contains .accountId then #[ctxAccountIdFunc] else #[]) ++
      (if plan.contextOps.contains .contractId then #[ctxContractIdFunc] else #[]) ++
      (if plan.contextOps.contains .origin then #[ctxSignerFunc] else #[]) ++
      (if plan.contextOps.contains .randomSeed then #[ctxRandomSeedFunc] else #[])

def lowerContextExprPlan :
    ContextExprPlan → Except EmitError (Array Insn × ValueType)
  | .userId => .ok (#[.call ctxUserIdName], .u64)
  | .userIdHash => .ok (#[.call ctxUserHashName], .hash)
  | .accountId =>
    -- VOID helper stages the raw predecessor_account_id at ACCT_ID_BUF and the
    -- length at ACCT_ID_LEN; materialize `(ptr, len)` from the staged slots.
    .ok (#[.call ctxAccountIdName, .i32Const ACCT_ID_BUF,
         .i32Const ACCT_ID_LEN, .load "i32.load" 0], .string)
  | .contractId => .ok (#[.call ctxContractIdName], .u64)
  | .checkpointId => .ok (#[.call "block_index"], .u64)
  | .timestamp => .ok (#[.call "block_timestamp"], .u64)
  | .epochHeight => .ok (#[.call "epoch_height"], .u64)
  | .randomSeed => .ok (#[.call ctxRandomSeedName], .hash)
  | .origin => .ok (#[.call ctxSignerName], .u64)
  | .prepaidGas => .ok (#[.call "prepaid_gas"], .u64)
  | .usedGas => .ok (#[.call "used_gas"], .u64)

end ProofForge.Backend.WasmHost.Context
