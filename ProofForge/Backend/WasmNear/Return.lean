/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.ExprAnalysis
import ProofForge.Backend.WasmNear.Scalar
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Return

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.ExprAnalysis
open ProofForge.Backend.WasmNear.Scalar
open ProofForge.Backend.WasmNear.Types

/-! Return-value encoding helpers for EmitWat. -/

def returnInsnsForLoweredExpr (expected : ValueType) (expr : Expr)
    (insns : Array Insn) (actual : ValueType) : Except EmitError (Array Insn) := do
  if actual != expected then
    err s!"EmitWat: return expected `{expected.name}`, got `{actual.name}`"
  else if exprReturnsNearPromise expr then
    .ok (insns ++ #[.call "promise_return"])
  else match actual with
    | .u64 => .ok (insns ++ #[.call returnU64Name])
    | .u32 => .ok (insns ++ #[.call returnU32Name])
    | .bool => .ok (insns ++ #[.call returnBoolName])
    | .hash => .ok (#[.i64Const 32] ++ insns ++ #[.plain "i64.extend_i32_u", .call "value_return"])
    | _ => err s!"EmitWat: return type `{actual.name}` is not supported"

end ProofForge.Backend.WasmNear.Return
