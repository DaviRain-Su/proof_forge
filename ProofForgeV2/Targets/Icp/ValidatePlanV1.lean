import ProofForgeV2.Targets.Icp.LowerSemanticV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# ICP ValidatePlanV1 — plan canonicity

Size, name, reference, count, and expression-depth checks before IR emission.
Mirrors the Quint/Aleo ValidatePlanV1 shape for the narrow ICP-2
Counter/StateCell envelope.
-/

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .icp message

private def maxStates : Nat := 64
private def maxMethods : Nat := 256
private def maxParams : Nat := 32
private def maxStores : Nat := 64
private def maxExprDepth : Nat := 256
private def maxExprNodes : Nat := 4096
private def maxPlanExprNodes : Nat := 65536
private def maxIdentifierBytes : Nat := 200

/-- Reserved Wasm/IC export names + the fixed initializer name. Entries and
    views must not collide with these or each other. -/
private def reservedIcpWords : Array String :=
  #["init", "memory", "canister_init", "canister_update", "canister_query"]

private def isReserved (name : String) : Bool :=
  reservedIcpWords.contains name

private def isSafeIdent (name : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes name && !isReserved name

private partial def exprNodeCount : Expr → Nat
  | .literal _ | .param _ | .stateLoad _ | .unixTimeSeconds
  | .callerPrincipalLen | .callerPrincipalWord _
  | .paramPrincipalLen _ | .paramPrincipalWord .. => 1
  | .principalEq lhs rhs | .principalNe lhs rhs =>
      1 + (lhs.foldl (fun acc e => acc + exprNodeCount e) 0) +
        (rhs.foldl (fun acc e => acc + exprNodeCount e) 0)
  | .checkedAdd lhs rhs | .checkedSub lhs rhs
  | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
  | .compare _ lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
      1 + exprNodeCount lhs + exprNodeCount rhs
  | .boolNot operand => 1 + exprNodeCount operand
  | .ite cond t e =>
      1 + exprNodeCount cond + exprNodeCount t + exprNodeCount e

/-- Iterative, fuel-bounded expression validation over param/state references.
    Returns the remaining plan-wide node budget. -/
private def validateExpr
    (e : Expr) (what : String) (paramCount stateCount remaining0 : Nat) :
    CompileResult Nat := do
  let mut stack : Array (Expr × Nat) := #[(e, 1)]
  let mut remaining := remaining0
  let mut localNodes : Nat := 0
  while !stack.isEmpty do
    if remaining == 0 then
      planError s!"ICP plan expression budget exceeds {maxPlanExprNodes} nodes"
    remaining := remaining - 1
    localNodes := localNodes + 1
    if localNodes > maxExprNodes then
      planError s!"ICP plan {what} expression exceeds {maxExprNodes} nodes"
    let (current, depth) := stack.back!
    stack := stack.pop
    if depth > maxExprDepth then
      planError s!"ICP plan {what} expression exceeds depth limit"
    match current with
    | .literal _ | .unixTimeSeconds | .callerPrincipalLen => pure ()
    | .callerPrincipalWord wordIndex =>
        unless wordIndex < icpPrincipalDataWordCountV1 do
          planError s!"ICP plan {what} callerPrincipalWord {wordIndex} is out of range"
    | .param index =>
        unless index < paramCount do
          planError s!"ICP plan {what} references unknown parameter {index}"
    | .paramPrincipalLen index =>
        unless index < paramCount do
          planError s!"ICP plan {what} references unknown Principal parameter {index}"
    | .paramPrincipalWord index wordIndex =>
        unless index < paramCount do
          planError s!"ICP plan {what} references unknown Principal parameter {index}"
        unless wordIndex < icpPrincipalDataWordCountV1 do
          planError s!"ICP plan {what} paramPrincipalWord {wordIndex} is out of range"
    | .principalEq lhs rhs | .principalNe lhs rhs =>
        unless lhs.size == icpPrincipalLeafCountV1 && rhs.size == icpPrincipalLeafCountV1 do
          planError s!"ICP plan {what} Principal compare must have 9+9 leaves"
        for e in lhs do
          stack := stack.push (e, depth + 1)
        for e in rhs do
          stack := stack.push (e, depth + 1)
    | .stateLoad fieldIndex =>
        unless fieldIndex < stateCount do
          planError s!"ICP plan {what} references unknown state field {fieldIndex}"
    | .checkedAdd lhs rhs | .checkedSub lhs rhs
    | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
    | .compare _ lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
        stack := stack.push (rhs, depth + 1)
        stack := stack.push (lhs, depth + 1)
    | .boolNot operand =>
        stack := stack.push (operand, depth + 1)
    | .ite cond t e =>
        stack := stack.push (e, depth + 1)
        stack := stack.push (t, depth + 1)
        stack := stack.push (cond, depth + 1)
  unless exprNodeCount e ≤ maxExprNodes do
    planError s!"ICP plan {what} expression exceeds {maxExprNodes} nodes"
  pure remaining

private def validateParams
    (owner : String) (params : Array String) (paramKinds : Array ParamKind) :
    CompileResult Unit := do
  unless params.size ≤ maxParams do
    planError s!"ICP {owner} parameter count exceeds limit"
  unless paramKinds.size == params.size do
    planError s!"ICP {owner} paramKinds length must match params"
  let mut seen : Array String := #[]
  for p in params do
    unless isSafeIdent p do
      planError s!"ICP {owner} parameter '{p}' is not a safe identifier"
    if seen.contains p then
      planError s!"ICP {owner} parameter '{p}' is duplicated"
    seen := seen.push p

private partial def stmtCount : Statement → Nat
  | .ifThenElse _ thenBody elseBody =>
      1 + (thenBody.map stmtCount).foldl (· + ·) 0 +
        (elseBody.map stmtCount).foldl (· + ·) 0
  | .switchOn _ cases defaultBody =>
      1 + (cases.map (fun (_, b) => (b.map stmtCount).foldl (· + ·) 0)).foldl (· + ·) 0 +
        (defaultBody.map stmtCount).foldl (· + ·) 0
  | _ => 1

/-- Validate a Statement list: `.assert` / `.store` / T9a `.ifThenElse`,
    optionally followed by a single terminal
    `.returnValue`/`.returnNone`/`.returnAggregate`, matching `resultKind`.
    Store-field uniqueness is per linear region (arms may both write the
    same field). -/
private partial def validateRegion
    (owner : String) (resultKind : ResultKind)
    (allowStores : Bool) (paramCount stateCount remaining0 : Nat)
    (body : Array Statement) : CompileResult (Nat × Bool) := do
  let mut remaining := remaining0
  let mut seenFields : Array Nat := #[]
  let mut sawTerminal := false
  let mut sawTerminalValue := false
  for stmt in body do
    if sawTerminal then
      planError s!"ICP {owner} body has statements after its return"
    match stmt with
    | .assert condition =>
        remaining ←
          validateExpr condition "assert condition" paramCount stateCount remaining
    | .store fieldIndex value =>
        unless allowStores do
          planError s!"ICP {owner} cannot write state"
        unless fieldIndex < stateCount do
          planError s!"ICP {owner} store references unknown state field {fieldIndex}"
        if seenFields.contains fieldIndex then
          planError s!"ICP {owner} store list has duplicate field indices"
        seenFields := seenFields.push fieldIndex
        remaining ←
          validateExpr value "store value" paramCount stateCount remaining
    | .ifThenElse condition thenBody elseBody =>
        remaining ←
          validateExpr condition "if condition" paramCount stateCount remaining
        let (r1, _) ←
          validateRegion owner resultKind allowStores paramCount stateCount
            remaining thenBody
        remaining := r1
        let (r2, _) ←
          validateRegion owner resultKind allowStores paramCount stateCount
            remaining elseBody
        remaining := r2
    | .switchOn scrutinee cases defaultBody =>
        remaining ←
          validateExpr scrutinee "switch scrutinee" paramCount stateCount remaining
        for (_, caseBody) in cases do
          let (r, _) ←
            validateRegion owner resultKind allowStores paramCount stateCount
              remaining caseBody
          remaining := r
        let (rd, _) ←
          validateRegion owner resultKind allowStores paramCount stateCount
            remaining defaultBody
        remaining := rd
    | .returnValue value =>
        sawTerminal := true
        sawTerminalValue := true
        unless resultKind == .uint64 || resultKind == .int64 || resultKind == .bool do
          planError s!"ICP {owner} Unit result must not return a value"
        remaining ←
          validateExpr value "return value" paramCount stateCount remaining
    | .returnAggregate leaves =>
        sawTerminal := true
        sawTerminalValue := true
        match resultKind with
        | .aggregate n =>
            unless leaves.size == n && 1 ≤ n && n ≤ 8 do
              planError
                s!"ICP {owner} aggregate return must have exactly {n} leaves"
            for e in leaves do
              remaining ←
                validateExpr e "aggregate return leaf" paramCount stateCount remaining
        | _ =>
            planError s!"ICP {owner} cannot return an aggregate"
    | .returnNone =>
        sawTerminal := true
        unless resultKind == .unit do
          planError s!"ICP {owner} non-Unit result must return a value"
  pure (remaining, sawTerminalValue)

private partial def regionHasReturn (body : Array Statement) : Bool :=
  body.any fun s =>
    match s with
    | .returnValue _ | .returnAggregate _ | .returnNone => true
    | .ifThenElse _ t e => regionHasReturn t || regionHasReturn e
    | .switchOn _ cases d =>
        cases.any (fun (_, b) => regionHasReturn b) || regionHasReturn d
    | _ => false

private def validateBody
    (owner : String) (mode : MethodMode) (resultKind : ResultKind)
    (allowStores : Bool) (paramCount stateCount remaining0 : Nat)
    (body : Array Statement) : CompileResult Nat := do
  let total := (body.map stmtCount).foldl (· + ·) 0
  unless total ≤ maxStores + 8 do
    planError s!"ICP {owner} body statement count exceeds limit"
  let (remaining, _) ←
    validateRegion owner resultKind allowStores paramCount stateCount
      remaining0 body
  let sawTerminalValue := regionHasReturn body
  match mode with
  | .initialize | .mutate =>
      match resultKind, sawTerminalValue with
      | .uint64, false | .int64, false | .bool, false | .aggregate _, false =>
          planError s!"ICP {owner} non-Unit result is missing its return statement"
      | _, _ => pure ()
  | .query =>
      unless sawTerminalValue do
        planError s!"ICP {owner} view must return a value"
  pure remaining

def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isSafeIdent plan.programName do
    planError s!"ICP program name '{plan.programName}' is not a safe identifier"
  unless plan.states.size ≤ maxStates do
    planError "ICP plan exceeds the state field limit"
  unless plan.entries.size ≤ maxMethods do
    planError "ICP plan exceeds the entry limit"
  unless plan.views.size ≤ maxMethods do
    planError "ICP plan exceeds the view limit"
  unless plan.entries.size > 0 || plan.views.size > 0 do
    planError "ICP plan requires at least one entry or view"
  let mut exprBudget := maxPlanExprNodes
  let mut stateNames : Array String := #[]
  for st in plan.states do
    unless isAsciiIdentifier maxIdentifierBytes st.name do
      planError s!"ICP state '{st.name}' is not a safe identifier"
    if stateNames.contains st.name then
      planError s!"ICP state '{st.name}' is duplicated"
    stateNames := stateNames.push st.name
  unless plan.initializer.name == "init" do
    planError "ICP initializer must be named 'init'"
  unless plan.initializer.mode == .initialize do
    planError "ICP initializer must carry MethodMode.initialize"
  unless plan.initializer.resultKind == .unit do
    planError "ICP initializer result must be Unit"
  validateParams "initializer" plan.initializer.params plan.initializer.paramKinds
  exprBudget ←
    validateBody "initializer" .initialize .unit (allowStores := true)
      plan.initializer.params.size plan.states.size exprBudget plan.initializer.body
  let mut methodNames : Array String := #[]
  for ent in plan.entries do
    unless isSafeIdent ent.name do
      planError s!"ICP entry '{ent.name}' is not a safe identifier"
    if methodNames.contains ent.name then
      planError s!"ICP entry '{ent.name}' is duplicated"
    methodNames := methodNames.push ent.name
    unless ent.mode == .mutate do
      planError s!"ICP entry '{ent.name}' must carry MethodMode.mutate"
    match ent.resultKind with
    | .aggregate n =>
        unless 1 ≤ n && n ≤ 8 do
          planError s!"ICP entry '{ent.name}' aggregate return must have 1..8 leaves"
    | .unit | .uint64 | .int64 | .bool => pure ()
    validateParams s!"entry '{ent.name}'" ent.params ent.paramKinds
    exprBudget ←
      validateBody s!"entry '{ent.name}'" .mutate ent.resultKind (allowStores := true)
        ent.params.size plan.states.size exprBudget ent.body
  for v in plan.views do
    unless isSafeIdent v.name do
      planError s!"ICP view '{v.name}' is not a safe identifier"
    if methodNames.contains v.name then
      planError s!"ICP view '{v.name}' is duplicated"
    methodNames := methodNames.push v.name
    unless v.mode == .query do
      planError s!"ICP view '{v.name}' must carry MethodMode.query"
    unless v.resultKind == .uint64 || v.resultKind == .int64 || v.resultKind == .bool ||
        (match v.resultKind with | .aggregate n => 1 ≤ n && n ≤ 8 | _ => false) do
      planError s!"ICP view '{v.name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
    validateParams s!"view '{v.name}'" v.params v.paramKinds
    exprBudget ←
      validateBody s!"view '{v.name}'" .query v.resultKind (allowStores := false)
        v.params.size plan.states.size exprBudget v.body
  pure ()

end ProofForgeV2.Targets.Icp
