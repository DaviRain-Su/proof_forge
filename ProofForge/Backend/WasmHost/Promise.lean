/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan

namespace ProofForge.Backend.WasmHost.Promise

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan

/-! Helper functions for NEAR Promise chaining and callback result decoding. -/

def promiseCurrentAccountName : String := "__pf_promise_current_account"

/-- Load the current contract account id into `CTX_BUF` and return its byte length. -/
def promiseCurrentAccountFunc : Func :=
  { name := promiseCurrentAccountName, results := #[.i64],
    locals := #[{ name := "len", type := .i64 }],
    body := { insns := #[
      .i64Const 0, .call "current_account_id",
      .i64Const 0, .call "register_len", .localSet "len",
      .i64Const 0, .i64Const CTX_BUF, .call "read_register",
      .localGet "len" ] } }

def promiseResultU64Name : String := "__pf_promise_result_u64"

/-- Read promise result at `idx`, Borsh-decode register 0 as U64 (0 on failure). -/
def promiseResultU64Func : Func :=
  { name := promiseResultU64Name,
    params := #[{ name := "idx", type := .i64 }],
    results := #[.i64],
    locals := #[{ name := "status", type := .i64 }, { name := "r", type := .i64 }],
    body := { insns := #[
      .localGet "idx", .i64Const 0, .call "promise_result", .localSet "status",
      .i64Const 0, .localSet "r",
      .localGet "status", .i64Const 1, .plain "i64.eq",
      .if_ { insns := #[
        .i64Const 0, .i64Const PROMISE_RESULT_BUF, .call "read_register",
        .i32Const PROMISE_RESULT_BUF, .load "i64.load" 0, .localSet "r"
      ] } { insns := #[] },
      .localGet "r" ] } }

def promiseResultU128Name : String := "__pf_promise_result_u128"

/-! `__pf_promise_result_u128(idx)`: void. Reads the promise result at `idx`
    into PROMISE_RESULT_BUF as 16 little-endian bytes (zeros on failure); the
    caller reloads (lo, hi). Two-word u128 convention. -/
def promiseResultU128Func : Func :=
  { name := promiseResultU128Name,
    params := #[{ name := "idx", type := .i64 }],
    results := #[],
    locals := #[{ name := "status", type := .i64 }],
    body := { insns := #[
      .i32Const PROMISE_RESULT_BUF, .i64Const 0, .store "i64.store" 0,
      .i32Const (PROMISE_RESULT_BUF + 8), .i64Const 0, .store "i64.store" 0,
      .localGet "idx", .i64Const 0, .call "promise_result", .localSet "status",
      .localGet "status", .i64Const 1, .plain "i64.eq",
      .if_ { insns := #[.i64Const 0, .i64Const PROMISE_RESULT_BUF, .call "read_register"] }
        { insns := #[] } ] } }

def promiseTransferName : String := "__pf_promise_transfer"

/-- Create a NEAR batch promise containing one native-token transfer action. -/
def promiseTransferFunc : Func :=
  { name := promiseTransferName
    params := #[
      { name := "account_ptr", type := .i32 }, { name := "account_len", type := .i32 },
      { name := "amount_lo", type := .i64 }, { name := "amount_hi", type := .i64 }]
    results := #[.i64]
    locals := #[{ name := "promise", type := .i64 }]
    body := { insns := #[
      .localGet "account_len", .plain "i64.extend_i32_u",
      .localGet "account_ptr", .plain "i64.extend_i32_u",
      .call "promise_batch_create", .localSet "promise",
      .i32Const RET_BUF, .localGet "amount_lo", .store "i64.store" 0,
      .i32Const (RET_BUF + 8), .localGet "amount_hi", .store "i64.store" 0,
      .localGet "promise", .i64Const RET_BUF, .call "promise_batch_action_transfer",
      .localGet "promise"] } }

def promiseHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesPromiseThen then #[promiseCurrentAccountFunc] else #[]) ++
    (if plan.usesPromiseResultU64 then #[promiseResultU64Func, promiseResultU128Func] else #[]) ++
    (if plan.usesPromiseTransfer then #[promiseTransferFunc] else #[])

end ProofForge.Backend.WasmHost.Promise
