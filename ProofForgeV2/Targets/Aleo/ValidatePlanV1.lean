import ProofForgeV2.Targets.Aleo.LowerSemanticV1

/-!
# Aleo ValidatePlanV1 — plan canonicity

Validates the public `Aleo.Plan` value before any Leo source is produced.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Hard bounds (same order of magnitude as the sibling targets). -/
private def maxFunctions : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256

/-- Leo 4.0.2 reserved words / mapping method names that a DSL identifier must
    not collide with (conservative; `leo build` is the final authority). -/
private def reservedLeoWords : Array String :=
  #[ "mapping", "transition", "finalize", "final", "function", "fn", "program",
     "constructor", "async", "record", "struct", "enum", "for", "if", "else",
     "return", "let", "assert", "true", "false", "public", "private",
     "self", "as", "cast" ]

private def isReserved (name : String) : Bool :=
  reservedLeoWords.contains name


-- ---------------------------------------------------------------------------
-- Plan validation
-- ---------------------------------------------------------------------------

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
  | .bitNot o | .boolNot o => do
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
    planError "Aleo function body exceeds the statement limit"
  for stmt in stmts do
    match stmt with
    | .store _ value | .returnValue value => do
        match validateExprNodes value with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
    | .returnNone => pure ()
    | .assert condition => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
    | .ifThenElse condition thenBody elseBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
        validateStatements thenBody
        validateStatements elseBody
    | .switchOn condition cases defaultBody => do
        match validateExprNodes condition with
        | some _ => pure ()
        | none => planError "Aleo plan expression exceeds the depth/node limit"
        for (_, caseBody) in cases do
          validateStatements caseBody
        validateStatements defaultBody
    | .forLoop start endExclusive _ body => do
        match validateExprNodes start, validateExprNodes endExclusive with
        | some _, some _ => pure ()
        | _, _ => planError "Aleo plan expression exceeds the depth/node limit"
        validateStatements body
    | .emitEvent .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .revertError _ args =>
        unless args.isEmpty do
          planError "Aleo does not support revert payloads: Leo 4.0.2 cannot represent error arguments"

def validatePlan (plan : Plan) : CompileResult Unit := do
  if plan.functions.size > maxFunctions then
    planError "Aleo plan exceeds the function limit"
  if plan.stateFieldNames.size > maxParams then
    planError "Aleo plan exceeds the state mapping limit"
  let names := plan.functions.map (·.name) ++ plan.views.map (·.name)
  for name in names do
    if isReserved name then
      planError s!"Aleo identifier '{name}' collides with a reserved Leo word"
  for fn in plan.functions do
    if fn.params.size > maxParams then
      planError "Aleo plan function exceeds the parameter limit"
    for param in fn.params do
      if isReserved param.name then
        planError s!"Aleo parameter '{param.name}' collides with a reserved Leo word"
    validateStatements fn.body
    if fn.resultDropped && fn.kind != .mutate then
      planError "resultDropped is only valid on state-touching entries"
    if fn.resultDropped && !fn.touchesState then
      planError "resultDropped requires a state-touching body"
  for view in plan.views do
    if view.stateFieldIndex >= plan.stateFieldNames.size then
      planError "Aleo view references a missing state field"
  pure ()


end ProofForgeV2.Targets.Aleo
