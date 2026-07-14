import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.IR.Validate.Common

/-! # Strict EVM plan lowering

This module lowers a complete EVM `ModulePlan` without a source `IR.Module`.
Callbacks that would consume legacy expressions fail closed; Canonical plans
must materialize storage, ABI, and target behavior before entering this pass.
-/

namespace ProofForge.Backend.Evm.Plan.ToYul

open ProofForge.Backend.Evm.Plan

private def error (message : String) : PlanError := { message }

private def rejectLegacyExpr (_ : ProofForge.IR.Expr) : Except PlanError Lean.Compiler.Yul.Expr :=
  .error (error "canonical EVM plan retained a Legacy IR expression")

mutual
  partial def lowerEffectExpr : EffectPlan → Except PlanError Lean.Compiler.Yul.Expr
    | .storageScalarReadTarget target =>
        ProofForge.Backend.Evm.ToYul.scalarStorageTargetReadExpr error rejectLegacyExpr target
    | .contextRead field =>
        ProofForge.Backend.Evm.ToYul.contextExprPlan error lowerExpr field
    | .storageMapContainsTarget target key =>
        ProofForge.Backend.Evm.ToYul.mapContainsTargetExpr error rejectLegacyExpr lowerEffectExpr target key
    | .storageMapGetTarget target key =>
        ProofForge.Backend.Evm.ToYul.mapGetTargetExpr error rejectLegacyExpr lowerEffectExpr target key
    | .storageMapInsertTarget target key value
    | .storageMapSetTarget target key value =>
        ProofForge.Backend.Evm.ToYul.mapSetReturnTargetExpr
          error rejectLegacyExpr lowerEffectExpr target key value
    | .storageMapDeleteTarget target key =>
        ProofForge.Backend.Evm.ToYul.mapGetTargetExpr
          error rejectLegacyExpr lowerEffectExpr { rootSlot := target.rootSlot } key
    | .storageArrayReadTarget target index =>
        ProofForge.Backend.Evm.ToYul.arrayReadTargetExpr
          error rejectLegacyExpr lowerEffectExpr target index
    | .storageStructFieldReadTarget target =>
        ProofForge.Backend.Evm.ToYul.structFieldReadTargetExpr error rejectLegacyExpr target
    | .storageArrayStructFieldReadTarget target index =>
        ProofForge.Backend.Evm.ToYul.structArrayFieldReadTargetExpr
          error rejectLegacyExpr lowerEffectExpr target index
    | .storagePathReadTarget slot =>
        ProofForge.Backend.Evm.ToYul.storagePathReadExprFromPlan error rejectLegacyExpr slot
    | .storagePathReadExprTarget slot =>
        ProofForge.Backend.Evm.ToYul.storagePathReadExprFromExprPlan error lowerExpr slot
    | _ => .error (error "canonical EVM expression retained a symbolic or statement-only effect")

  partial def lowerExpr (plan : ExprPlan) : Except PlanError Lean.Compiler.Yul.Expr :=
    match plan with
    | .crosscall mode target methodId callValue? args returnType =>
        ProofForge.Backend.Evm.ToYul.crosscallExpandedExprPlanExpr
          error lowerExpr mode target methodId callValue? args returnType
    | _ => ProofForge.Backend.Evm.ToYul.exprPlanExpr error rejectLegacyExpr lowerEffectExpr plan
end

private def lowerErrorRef (ref : ProofForge.IR.ErrorRef) :
    Except PlanError (Array Lean.Compiler.Yul.Statement) :=
  ProofForge.Backend.Evm.IR.errorRefRevertStmtsRuntime error rejectLegacyExpr ref

private def lowerErrorPlan (plan : EvmErrorPlan) :
    Except PlanError (Array Lean.Compiler.Yul.Statement) := do
  match plan.soliditySelector? with
  | none =>
      unless plan.solidityArgWords.isEmpty && plan.solidityArgExprs.isEmpty do
        throw (error "EVM error arguments require a Solidity selector")
      pure (ProofForge.Backend.Evm.IR.proofForgeErrorRevertStmts
        plan.assertionId.toNat (plan.userCode?.getD ""))
  | some selector =>
      let some selectorWord := ProofForge.Backend.Evm.IR.parseSoliditySelectorHex selector
        | throw (error s!"invalid EVM custom-error selector `{selector}`")
      unless plan.solidityArgWords.isEmpty || plan.solidityArgExprs.isEmpty do
        throw (error "EVM custom error mixes static and runtime arguments")
      if plan.solidityArgExprs.isEmpty then
        pure (ProofForge.Backend.Evm.IR.solidityCustomErrorRevertStmts
          selectorWord plan.solidityArgWords)
      else
        ProofForge.Backend.Evm.IR.solidityCustomErrorRevertStmtsRuntime
          error lowerExpr selectorWord plan.solidityArgExprs

private def lowerEffectStmt (overflowChecked : Bool) (effect : EffectPlan) :
    Except PlanError (Array Lean.Compiler.Yul.Statement) :=
  match effect with
  | .storageScalarWriteTarget .. | .storageScalarAssignOpTarget .. =>
      ProofForge.Backend.Evm.ToYul.scalarStorageTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageMapInsertTarget .. | .storageMapSetTarget .. =>
      ProofForge.Backend.Evm.ToYul.mapWriteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageMapDeleteTarget .. =>
      ProofForge.Backend.Evm.ToYul.mapDeleteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageArrayWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.arrayWriteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageDynamicArrayPushTarget .. =>
      ProofForge.Backend.Evm.ToYul.dynamicArrayPushTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageDynamicArrayPopTarget .. =>
      ProofForge.Backend.Evm.ToYul.dynamicArrayPopTargetEffectStmtPlanStatements error (.effect effect)
  | .memoryArraySet .. =>
      ProofForge.Backend.Evm.ToYul.memoryArraySetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageStructFieldWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.structFieldWriteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storageArrayStructFieldWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.structArrayFieldWriteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storagePathWriteTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathWriteTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storagePathWriteExprTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathWriteExprTargetEffectStmtPlanStatements
        error rejectLegacyExpr lowerEffectExpr lowerExpr (.effect effect)
  | .storagePathAssignOpTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathAssignOpTargetEffectStmtPlanStatements
        overflowChecked error rejectLegacyExpr lowerEffectExpr (.effect effect)
  | .storagePathAssignOpExprTarget .. =>
      ProofForge.Backend.Evm.ToYul.storagePathAssignOpExprTargetEffectStmtPlanStatements
        overflowChecked error rejectLegacyExpr lowerEffectExpr lowerExpr (.effect effect)
  | .eventEmit .. | .eventEmitIndexed .. | .eventEmitWords .. | .eventEmitIndexedWords .. =>
      ProofForge.Backend.Evm.ToYul.eventEffectStmtPlanStatements error lowerExpr (.effect effect)
  | .checkErc721Received operator fromAddr toAddr tokenId => do
      return ProofForge.Backend.Evm.ToYul.checkErc721ReceivedStatements
        (← lowerExpr operator) (← lowerExpr fromAddr) (← lowerExpr toAddr) (← lowerExpr tokenId)
  | .checkErc1155Received operator fromAddr toAddr tokenId amount => do
      return ProofForge.Backend.Evm.ToYul.checkErc1155ReceivedStatements
        (← lowerExpr operator) (← lowerExpr fromAddr) (← lowerExpr toAddr)
        (← lowerExpr tokenId) (← lowerExpr amount)
  | .checkErc1155BatchReceived .. =>
      ProofForge.Backend.Evm.ToYul.erc1155BatchReceiverEffectPlanStatements error lowerExpr effect
  | _ => .error (error "canonical EVM statement retained a symbolic storage effect")

mutual
  partial def lowerStatements (overflowChecked : Bool) (returns : ReturnPlan) (leaveAfterReturn : Bool)
      (plans : Array StmtPlan) : Except PlanError (Array Lean.Compiler.Yul.Statement) := do
    let (statements, _) ← ProofForge.Backend.Evm.ToYul.stmtPlanBodyStatements
      plans () leaveAfterReturn fun _ leave plan => do
        return (← lowerStatement overflowChecked returns leave plan, ())
    return statements

  partial def lowerStatement (overflowChecked : Bool) (returns : ReturnPlan) (leaveAfterReturn : Bool) :
      StmtPlan → Except PlanError (Array Lean.Compiler.Yul.Statement)
    | plan@(.letBind ..) | plan@(.letMutBind ..) =>
        ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
          error rejectLegacyExpr lowerEffectExpr plan
    | plan@(.assign ..) | plan@(.assignOp ..) =>
        ProofForge.Backend.Evm.ToYul.scalarAssignmentStmtPlanStatements
          overflowChecked error rejectLegacyExpr lowerEffectExpr plan
    | .effect effect => lowerEffectStmt overflowChecked effect
    | plan@(.assert ..) | plan@(.assertEq ..) =>
        ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
          error rejectLegacyExpr lowerEffectExpr
          (fun | none => .ok #[ProofForge.Backend.Evm.ToYul.revertStatement]
               | some ref => lowerErrorRef ref)
          plan
    | .assertPlanned condition _ errorPlan? => do
        let revertStatements ← match errorPlan? with
          | none => pure #[ProofForge.Backend.Evm.ToYul.revertStatement]
          | some plan => lowerErrorPlan plan
        pure #[ProofForge.Backend.Evm.ToYul.assertStatementFromCondition
          (← lowerExpr condition) revertStatements]
    | .release _ => .error (error "canonical EVM plan does not support release statements")
    | .revert message =>
        ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements error lowerErrorRef (.revert message)
    | .revertWithError ref =>
        ProofForge.Backend.Evm.ToYul.revertStmtPlanStatements error lowerErrorRef (.revertWithError ref)
    | .revertPlanned plan => lowerErrorPlan plan
    | .ifElse condition thenBody elseBody => do
        let thenStatements ← lowerStatements overflowChecked returns true thenBody
        let elseStatements ← lowerStatements overflowChecked returns true elseBody
        ProofForge.Backend.Evm.ToYul.ifElseStmtPlanStatements
          error rejectLegacyExpr lowerEffectExpr thenStatements elseStatements
          (.ifElse condition thenBody elseBody)
    | .boundedFor indexName start stopExclusive body => do
        unless start < stopExclusive do
          throw (error s!"bounded loop `{indexName}` must have stop greater than start")
        let bodyStatements ← lowerStatements overflowChecked returns true body
        ProofForge.Backend.Evm.ToYul.boundedForStmtPlanStatements
          error rejectLegacyExpr lowerEffectExpr bodyStatements
          (.boundedFor indexName start stopExclusive body)
    | .return value =>
        match returns.returnType with
        | .bytes | .string | .array _ =>
            ProofForge.Backend.Evm.ToYul.dynamicReturnStmtPlanStatements
              error returns leaveAfterReturn (.return value)
        | .fixedArray .. | .structType .. =>
            .error (error "canonical EVM aggregate returns are not yet fully materialized in ModulePlan")
        | _ =>
            ProofForge.Backend.Evm.ToYul.scalarReturnExprPlanStatements
              error lowerExpr returns.localNames leaveAfterReturn (.return value)
end

def lowerEntrypoint (moduleName : String) (overflowChecked : Bool) (entrypoint : EntrypointPlan) :
    Except PlanError Lean.Compiler.Yul.Statement := do
  let body ← lowerStatements overflowChecked entrypoint.returns false entrypoint.body
  let aliases := entrypoint.params.foldl (init := #[]) fun acc param =>
    if param.isDynamic then
      acc.push (.varDecl #[{ name := param.name }]
        (some (.id (ProofForge.Backend.Evm.ToYul.dynamicParamDataPtrName param.name))))
    else acc
  return ProofForge.Backend.Evm.ToYul.entrypointFunctionDefinition
    moduleName entrypoint (aliases ++ body)

def lowerDispatch (moduleName : String) (dispatch : DispatchPlan) :
    Except PlanError Lean.Compiler.Yul.Statement := do
  let cases ← dispatch.entrypoints.mapM fun entrypoint => do
    let validation ←
      match ProofForge.Backend.Evm.IR.abiParamValidationAndDecodeStmts entrypoint.params with
      | .ok statements => .ok statements
      | .error failure => .error (error failure.message)
    let call := ProofForge.Backend.Evm.ToYul.entrypointCallExpr moduleName entrypoint
    let body ← match entrypoint.returns.returnType with
      | .bytes | .string | .array _ =>
          ProofForge.Backend.Evm.ToYul.dynamicDispatchReturnStatements
            error validation entrypoint.returns call
      | _ =>
          ProofForge.Backend.Evm.ToYul.staticDispatchReturnStatements
            error validation entrypoint.returns call
    ProofForge.Backend.Evm.ToYul.entrypointDispatchCase error entrypoint body
  return ProofForge.Backend.Evm.ToYul.dispatchPlanStatement dispatch cases

end ProofForge.Backend.Evm.Plan.ToYul
