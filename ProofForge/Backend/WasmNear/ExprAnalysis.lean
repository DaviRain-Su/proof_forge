/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmNear.ExprAnalysis

open ProofForge.IR

/-! Expression-shape analysis shared by EmitWat lowering paths. -/

partial def canDuplicateExpr : Expr → Bool
  | .literal _ => true
  | .local _ => true
  | .arrayLit _ values => values.all canDuplicateExpr
  | .arrayGet array index => canDuplicateExpr array && canDuplicateExpr index
  | .memoryArrayNew _ length => canDuplicateExpr length
  | .memoryArrayLength array => canDuplicateExpr array
  | .memoryArrayGet array index => canDuplicateExpr array && canDuplicateExpr index
  | .structLit _ fields => fields.all (fun field => canDuplicateExpr field.snd)
  | .field base _ => canDuplicateExpr base
    | .add lhs rhs _
    | .sub lhs rhs _
    | .mul lhs rhs _
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
  | .nearCrosscallInvokePool _ _ _ _
  | .nearPromiseThen _ _ _ _
  | .nearPromiseResultsCount
  | .nearPromiseResultStatus _
  | .nearPromiseResultU64 _
  | .effect _ => false

def exprReturnsNearPromise : Expr → Bool
  | .crosscallInvoke _ _ _ => true
  | .crosscallInvokeValueTyped _ _ _ _ _ => true
  | .nearCrosscallInvokePool _ _ _ _ => true
  | .nearPromiseThen _ _ _ _ => true
  | _ => false

end ProofForge.Backend.WasmNear.ExprAnalysis
