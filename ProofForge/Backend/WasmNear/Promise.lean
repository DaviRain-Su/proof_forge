/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Plan

namespace ProofForge.Backend.WasmNear.Promise

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Memory
open ProofForge.Backend.WasmNear.Plan

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

def promiseHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  (if plan.usesPromiseThen then #[promiseCurrentAccountFunc] else #[]) ++
    (if plan.usesPromiseResultU64 then #[promiseResultU64Func] else #[])

end ProofForge.Backend.WasmNear.Promise
