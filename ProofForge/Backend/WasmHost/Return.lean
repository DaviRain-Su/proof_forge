/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.ExprAnalysis
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Return

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.ExprAnalysis
open ProofForge.Backend.WasmHost.Scalar
open ProofForge.Backend.WasmHost.Types

/-! Return-value encoding helpers for EmitWat. -/

/-- Encode a memory pointer on the stack as `value_return(len, ptr)` (Borsh blob).
    `insns` must leave an `i32` pointer as the top-of-stack result. -/
def returnBytesFromPtrInsns (byteLen : Nat) (insns : Array Insn) : Array Insn :=
  #[.i64Const byteLen] ++ insns ++
    #[.plain "i64.extend_i32_u", .call "value_return"]

/-- Encode a dynamic bytes/string return: the lowered expr leaves an i32 pointer
    to a Borsh buffer (4-byte LE length prefix + payload). We call the
    `__pf_return_bytes` helper which reads the length and calls `value_return`. -/
def returnDynamicBytesInsns (insns : Array Insn) : Array Insn :=
  insns ++ #[.call returnBytesName]

def returnInsnsForLoweredExpr (expected : ValueType) (expr : Expr)
    (insns : Array Insn) (actual : ValueType)
    (bridge : ProofForge.Target.HostBridge := .near)
    (_packScalars : Bool := false)
    (aggregateReturnBytes : Option Nat := none) : Except EmitError (Array Insn) := do
  -- Packed-scalar flush is applied once as the entrypoint body suffix in EmitWat
  -- (`packFlushInsns` after the lowered body). Do not flush here or void/return
  -- paths double-call `__pf_pack_flush`.
  if actual != expected then
    err s!"EmitWat: return expected `{expected.name}`, got `{actual.name}`"
  else if bridge == .near && exprReturnsNearPromise expr then
    -- NEAR Promise id must be passed to promise_return; Soroban invoke returns a
    -- host handle and uses ordinary value_return encoding.
    .ok (insns ++ #[.call "promise_return"])
  else match actual with
    | .u64 => .ok (insns ++ #[.call returnU64Name])
    | .u32 => .ok (insns ++ #[.call returnU32Name])
    | .u128 => .ok (insns ++ #[.call returnU128Name])
    | .bool => .ok (insns ++ #[.call returnBoolName])
    | .hash =>
      .ok (returnBytesFromPtrInsns 32 insns)
    | .structType _ | .fixedArray _ _ =>
      match aggregateReturnBytes with
      | some n =>
        if n == 0 then
          err s!"EmitWat: return type `{actual.name}` has zero Borsh size"
        else
          .ok (returnBytesFromPtrInsns n insns)
      | none =>
        err s!"EmitWat: return type `{actual.name}` requires aggregate layout size \
|(struct/fixedArray); pass layout size from EmitWat"
    | .bytes | .string =>
      .ok (returnDynamicBytesInsns insns)
    | _ => err s!"EmitWat: return type `{actual.name}` is not supported"

end ProofForge.Backend.WasmHost.Return