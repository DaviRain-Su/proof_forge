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

def returnInsnsForLoweredExpr (expected : ValueType) (expr : Expr)
    (insns : Array Insn) (actual : ValueType)
    (bridge : ProofForge.Target.HostBridge := .near)
    (_packScalars : Bool := false) : Except EmitError (Array Insn) := do
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
    | .bool => .ok (insns ++ #[.call returnBoolName])
    | .hash =>
      .ok (#[.i64Const 32] ++ insns ++
        #[.plain "i64.extend_i32_u", .call "value_return"])
    | _ => err s!"EmitWat: return type `{actual.name}` is not supported"

end ProofForge.Backend.WasmHost.Return
