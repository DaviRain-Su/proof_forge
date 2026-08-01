import ProofForgeV2.Targets.Psy.LowerSemanticV1

/-!
# Psy ValidatePlanV1 — plan canonicity

Validates the public `Psy.Plan` value before any `.psy` source is produced.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

private def maxFunctions : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256

/-- Conservative Psy reserved identifiers (dargo is the final authority). -/
private def reservedPsyWords : Array String :=
  #[ "struct", "impl", "fn", "let", "mut", "if", "else", "for", "return",
     "assert", "assert_eq", "abort", "true", "false", "pub", "priv",
     "Felt", "bool", "u32", "u8", "u128", "Map", "as", "in", "contract",
     "contract_method", "test", "derive", "Storage", "ContractMetadata",
     "ref" ]

private def isReserved (name : String) : Bool :=
  reservedPsyWords.contains name

private def validateExprNodes (expr : Expr) : Option Nat :=
  match expr with
  | .literal _ | .boolLiteral _ | .param _ | .loopVar _ | .stateLoad _ => some 1
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .compare _ l r => do
      let dl ← validateExprNodes l
      let dr ← validateExprNodes r
      if dl + dr + 1 > maxExprDepth then none else some (dl + dr + 1)
  | .boolNot o => do
      let do' ← validateExprNodes o
      if do' + 1 > maxExprDepth then none else some (do' + 1)
  | .callFn _ args => do
      let mut total : Nat := 1
      for arg in args do
        let da ← validateExprNodes arg
        total := total + da
      if total > maxExprDepth then none else some total

private partial def validateStatements (stmts : Array Statement) : CompileResult Unit := do
  if stmts.size > maxBodyStatements then
    planError "Psy function body exceeds the statement limit"
  for stmt in stmts do
    match stmt with
    | .store _ value | .returnValue value => do
        match validateExprNodes value with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
    | .returnNone | .bareRevert => pure ()
    | .assert condition => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
    | .ifThenElse condition thenBody elseBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
        validateStatements thenBody
        validateStatements elseBody
    | .switchOn condition cases defaultBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Psy plan expression exceeds the depth/node limit"
        for (_, caseBody) in cases do
          validateStatements caseBody
        validateStatements defaultBody
    | .forLoop start endExclusive _ body => do
        match validateExprNodes start, validateExprNodes endExclusive with
        | some _, some _ => pure ()
        | _, _ => planError "Psy plan expression exceeds the depth/node limit"
        validateStatements body
    | .emitEvent _ args | .externalCall _ args | .schedule _ args => do
        for arg in args do
          match validateExprNodes arg with
          | some _ => pure ()
          | none => planError "Psy plan expression exceeds the depth/node limit"
    | .revertError _ args =>
        unless args.isEmpty do
          planError "unsupported Psy semantic shape: revert with error arguments cannot be expressed on the Psy surface"

def validatePlan (plan : Plan) : CompileResult Unit := do
  if plan.functions.size > maxFunctions then
    planError "Psy plan exceeds the function limit"
  if plan.stateFieldNames.size > maxParams then
    planError "Psy plan exceeds the state field limit"
  for name in plan.stateFieldNames do
    if isReserved name then
      planError s!"Psy state identifier '{name}' collides with a reserved Psy word"
  for fn in plan.functions do
    if isReserved fn.name then
      planError s!"Psy identifier '{fn.name}' collides with a reserved Psy word"
    if fn.params.size > maxParams then
      planError "Psy plan function exceeds the parameter limit"
    for param in fn.params do
      if isReserved param.name then
        planError s!"Psy parameter '{param.name}' collides with a reserved Psy word"
    validateStatements fn.body
  for ev in plan.events do
    if isReserved ev.name then
      planError s!"Psy event identifier '{ev.name}' collides with a reserved Psy word"
  pure ()

end ProofForgeV2.Targets.Psy
