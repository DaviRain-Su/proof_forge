import ProofForgeV2.Targets.Quint.LowerSemanticV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Quint ValidatePlanV1 — plan canonicity

Size, name, reference, count, and expression-depth checks before IR emission.
-/

namespace ProofForgeV2.Targets.Quint

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .quint message

private def maxStates : Nat := 64
private def maxEntries : Nat := 256
private def maxViews : Nat := 256
private def maxInvariants : Nat := 256
private def maxParams : Nat := 64
private def maxChecks : Nat := 128
private def maxStores : Nat := 64
private def maxExprDepth : Nat := 256
private def maxExprNodes : Nat := 16384
private def maxPlanExprNodes : Nat := 131072
private def maxIdentifierBytes : Nat := 200

private def reservedQuintWords : Array String :=
  #["module", "const", "var", "val", "def", "pure", "action", "temporal",
    "nondet", "all", "any", "oneOf", "if", "then", "else", "match", "with",
    "case", "let", "in", "do", "and", "or", "iff", "implies", "not",
    "true", "false", "int", "bool", "Nat", "Int", "Bool", "import", "from",
    "as", "export", "type", "typedef", "assume", "expect", "run", "test"]

private def isReserved (name : String) : Bool :=
  reservedQuintWords.contains name

private def isSafeIdent (name : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes name && !isReserved name

/-- Bounded Plan-expression type/reference checker. It runs only after the
    rendered-size/depth walk has admitted the expression. -/
private partial def inferExprType
    (e : Expr) (what : String)
    (paramCount stateCount assetOpCount fuel : Nat)
    (paramIsPrincipal : Array Bool) :
    CompileResult (ExprType × Nat) := do
  if fuel == 0 then
    planError s!"Quint plan {what} expression exhausted type-check fuel"
  let remaining := fuel - 1
  match e with
  | .litU64 _ => pure (.uint64, remaining)
  | .litBool _ => pure (.bool, remaining)
  | .param index =>
      unless index < paramCount do
        planError s!"Quint plan {what} references unknown parameter {index}"
      if paramIsPrincipal[index]? == some true then
        pure (.principal, remaining)
      else
        pure (.uint64, remaining)
  | .stateLoad fieldIndex =>
      unless fieldIndex < stateCount do
        planError s!"Quint plan {what} references unknown state field {fieldIndex}"
      pure (.uint64, remaining)
  | .vaultNative => pure (.uint64, remaining)
  | .externalOk ordinal =>
      unless ordinal < assetOpCount do
        planError s!"Quint plan {what} references unknown externalOk ordinal {ordinal}"
      pure (.bool, remaining)
  | .arith _ lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      unless lhsTy == .uint64 && rhsTy == .uint64 do
        planError s!"Quint plan {what} arithmetic operands must be UInt64"
      pure (.uint64, remaining)
  | .compare op lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      match op with
      | .eq | .ne =>
          unless lhsTy == rhsTy && (lhsTy == .uint64 || lhsTy == .bool) do
            planError s!"Quint plan {what} equality operands must share UInt64/Bool type"
      | .lt | .le | .gt | .ge =>
          unless lhsTy == .uint64 && rhsTy == .uint64 do
            planError s!"Quint plan {what} ordering operands must be UInt64"
      pure (.bool, remaining)
  | .boolAnd lhs rhs | .boolOr lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining paramIsPrincipal
      unless lhsTy == .bool && rhsTy == .bool do
        planError s!"Quint plan {what} logical operands must be Bool"
      pure (.bool, remaining)
  | .boolNot operand => do
      let (operandTy, remaining) ←
        inferExprType operand what paramCount stateCount assetOpCount remaining paramIsPrincipal
      unless operandTy == .bool do
        planError s!"Quint plan {what} logical-not operand must be Bool"
      pure (.bool, remaining)

/-- Iterative, fuel-bounded expression validation. Counting expanded tree
    occurrences (rather than object identity) prevents shared SSA subtrees from
    becoming exponentially large rendered source. The returned value is the
    remaining plan-wide node budget. -/
private def validateExpr
    (e : Expr) (expected : ExprType) (what : String)
    (paramCount stateCount assetOpCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) : CompileResult Nat := do
  let mut stack : Array (Expr × Nat) := #[(e, 1)]
  let mut remaining := remaining0
  let mut localNodes : Nat := 0
  while !stack.isEmpty do
    if remaining == 0 then
      planError s!"Quint plan expression budget exceeds {maxPlanExprNodes} nodes"
    remaining := remaining - 1
    localNodes := localNodes + 1
    if localNodes > maxExprNodes then
      planError s!"Quint plan {what} expression exceeds {maxExprNodes} nodes"
    let (current, depth) := stack.back!
    stack := stack.pop
    if depth > maxExprDepth then
      planError s!"Quint plan {what} expression exceeds depth limit"
    match current with
    | .litU64 _ | .litBool _ | .param _ | .stateLoad _ | .vaultNative | .externalOk _ =>
        pure ()
    | .arith op lhs rhs =>
        match op with
        | .div | .mod =>
            -- Emission totalizes division/modulo as
            -- `if rhs != 0 then lhs op rhs else 0`: four synthetic nodes and
            -- two expanded denominator occurrences beyond this Plan node.
            if remaining < 4 then
              planError s!"Quint plan expression budget exceeds {maxPlanExprNodes} rendered nodes"
            if localNodes + 4 > maxExprNodes then
              planError s!"Quint plan {what} expression exceeds {maxExprNodes} rendered nodes"
            if depth + 2 > maxExprDepth then
              planError s!"Quint plan {what} rendered expression exceeds depth limit"
            remaining := remaining - 4
            localNodes := localNodes + 4
            stack := stack.push (rhs, depth + 2)
            stack := stack.push (rhs, depth + 2)
            stack := stack.push (lhs, depth + 2)
        | .add | .sub | .mul =>
            stack := stack.push (rhs, depth + 1)
            stack := stack.push (lhs, depth + 1)
    | .compare _ lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
        stack := stack.push (rhs, depth + 1)
        stack := stack.push (lhs, depth + 1)
    | .boolNot operand =>
        stack := stack.push (operand, depth + 1)
  let (actual, _) ←
    inferExprType e what paramCount stateCount assetOpCount maxExprNodes paramIsPrincipal
  unless actual == expected do
    planError s!"Quint plan {what} expression type does not match its use site"
  pure remaining

private def validateCheck
    (ck : Check) (paramCount stateCount assetOpCount remaining : Nat)
    (paramIsPrincipal : Array Bool) : CompileResult Nat :=
  validateExpr ck.condition .bool "check condition" paramCount stateCount assetOpCount
    remaining paramIsPrincipal

private def validateStores
    (stores : Array (Nat × Expr)) (stateCount paramCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) : CompileResult Nat := do
  unless stores.size ≤ maxStores do
    planError "Quint plan store count exceeds limit"
  let mut seen : Array Nat := #[]
  let mut remaining := remaining0
  for (fi, e) in stores do
    unless fi < stateCount do
      planError "Quint plan store references an unknown state field"
    if seen.contains fi then
      planError "Quint plan store list has duplicate field indices"
    seen := seen.push fi
    remaining ←
      validateExpr e .uint64 "store value" paramCount stateCount 0 remaining paramIsPrincipal
  pure remaining

private def validateAssetOps
    (ops : Array PfAssetsOp) (paramCount stateCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) : CompileResult Nat := do
  let mut remaining := remaining0
  for op in ops do
    remaining ←
      validateExpr op.amount .uint64 "asset op amount" paramCount stateCount ops.size
        remaining paramIsPrincipal
  pure remaining

private def validateParams (params : Array String) : CompileResult Unit := do
  unless params.size ≤ maxParams do
    planError "Quint plan parameter count exceeds limit"
  let mut seen : Array String := #[]
  for p in params do
    unless isSafeIdent p do
      planError s!"Quint parameter '{p}' is not a safe identifier"
    if seen.contains p then
      planError s!"Quint parameter '{p}' is duplicated"
    seen := seen.push p

private def isTerminalRevertKind : FailureKind → Bool
  | .terminalRevert _ => true
  | _ => false

private def isCanonicalTerminalRevertCheck (ck : Check) : Bool :=
  match ck.kind, ck.condition with
  | .terminalRevert _, .litBool false => true
  | _, _ => false

def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isSafeIdent plan.programName do
    planError s!"Quint program name '{plan.programName}' is not a safe identifier"
  unless plan.states.size ≤ maxStates do
    planError "Quint plan exceeds the state field limit"
  unless plan.entries.size ≤ maxEntries do
    planError "Quint plan exceeds the entry limit"
  unless plan.views.size ≤ maxViews do
    planError "Quint plan exceeds the view limit"
  unless plan.invariants.size ≤ maxInvariants do
    planError "Quint plan exceeds the invariant limit"
  unless plan.entries.size > 0 do
    planError "Quint plan requires at least one entry"
  let mut exprBudget := maxPlanExprNodes
  let mut stateNames : Array String := #[]
  for st in plan.states do
    unless isSafeIdent st.name do
      planError s!"Quint state '{st.name}' is not a safe identifier"
    if stateNames.contains st.name then
      planError s!"Quint state '{st.name}' is duplicated"
    stateNames := stateNames.push st.name
  match plan.initializer with
  | none => pure ()
  | some init => do
      unless isSafeIdent init.name do
        planError s!"Quint initializer '{init.name}' is not a safe identifier"
      validateParams init.params
      exprBudget ←
        validateStores init.stores plan.states.size init.params.size exprBudget #[]
  let mut entryNames : Array String := #[]
  let mut expectedAction : Nat := 1
  let mut anyAssetOps := false
  for ent in plan.entries do
    unless isSafeIdent ent.name do
      planError s!"Quint entry '{ent.name}' is not a safe identifier"
    if entryNames.contains ent.name then
      planError s!"Quint entry '{ent.name}' is duplicated"
    entryNames := entryNames.push ent.name
    unless ent.actionIndex == expectedAction do
      planError "Quint entry actionIndex must be dense 1..n in source order"
    expectedAction := expectedAction + 1
    validateParams ent.params
    unless ent.paramIsPrincipal.size == ent.params.size do
      planError s!"Quint entry '{ent.name}' paramIsPrincipal length must match params"
    unless ent.checks.size ≤ maxChecks do
      planError "Quint entry check count exceeds limit"
    if !ent.assetOps.isEmpty then
      anyAssetOps := true
    exprBudget ←
      validateAssetOps ent.assetOps ent.params.size plan.states.size exprBudget
        ent.paramIsPrincipal
    for ck in ent.checks do
      exprBudget ←
        validateCheck ck ent.params.size plan.states.size ent.assetOps.size exprBudget
          ent.paramIsPrincipal
    exprBudget ←
      validateStores ent.stores plan.states.size ent.params.size exprBudget
        ent.paramIsPrincipal
    let terminalMarkerCount := ent.checks.foldl
      (fun n ck => if isTerminalRevertKind ck.kind then n + 1 else n) 0
    if ent.terminalRevert then
      unless terminalMarkerCount == 1 do
        planError s!"Quint entry '{ent.name}' terminalRevert requires exactly one terminal marker"
      match ent.checks.back? with
      | some ck =>
          unless isCanonicalTerminalRevertCheck ck do
            planError s!"Quint entry '{ent.name}' terminalRevert requires a final terminal-revert(false) check"
      | none =>
          planError s!"Quint entry '{ent.name}' terminalRevert requires a terminal-revert check"
    else unless terminalMarkerCount == 0 do
      planError s!"Quint entry '{ent.name}' has a terminal-revert marker without terminalRevert"
    match ent.resultKind, ent.result?, ent.terminalRevert with
    | .unit, none, _ => pure ()
    | .unit, some _, _ =>
        planError s!"Quint entry '{ent.name}' Unit result must not carry a result expression"
    | .uint64, some e, false =>
        exprBudget ←
          validateExpr e .uint64 "entry result" ent.params.size plan.states.size
            ent.assetOps.size exprBudget ent.paramIsPrincipal
    | .bool, some e, false =>
        exprBudget ←
          validateExpr e .bool "entry result" ent.params.size plan.states.size
            ent.assetOps.size exprBudget ent.paramIsPrincipal
    | .uint64, some _, true | .bool, some _, true =>
        planError s!"Quint entry '{ent.name}' terminal revert must not carry a result expression"
    | .uint64, none, true | .bool, none, true => pure ()
    | .uint64, none, false | .bool, none, false =>
        planError s!"Quint entry '{ent.name}' non-Unit result is missing without terminal revert"
  unless plan.usesVaultNative == anyAssetOps do
    planError "Quint plan usesVaultNative must match nonempty entry assetOps"
  let mut viewNames : Array String := #[]
  for v in plan.views do
    unless isSafeIdent v.name do
      planError s!"Quint view '{v.name}' is not a safe identifier"
    if viewNames.contains v.name then
      planError s!"Quint view '{v.name}' is duplicated"
    viewNames := viewNames.push v.name
    validateParams v.params
    match v.resultKind with
    | .unit => planError s!"Quint view '{v.name}' cannot have Unit result"
    | .uint64 =>
        exprBudget ←
          validateExpr v.value .uint64 "view value" v.params.size plan.states.size 0
            exprBudget #[]
    | .bool =>
        exprBudget ←
          validateExpr v.value .bool "view value" v.params.size plan.states.size 0
            exprBudget #[]
  let mut invariantNames : Array String := #[]
  for inv in plan.invariants do
    unless isSafeIdent inv.name do
      planError s!"Quint invariant '{inv.name}' is not a safe identifier"
    if invariantNames.contains inv.name then
      planError s!"Quint invariant '{inv.name}' is duplicated"
    invariantNames := invariantNames.push inv.name
    unless inv.checks.size ≤ maxChecks do
      planError "Quint invariant check count exceeds limit"
    for ck in inv.checks do
      if isTerminalRevertKind ck.kind then
        planError s!"Quint invariant '{inv.name}' cannot carry a terminal-revert marker"
      exprBudget ← validateCheck ck 0 plan.states.size 0 exprBudget #[]
    exprBudget ←
      validateExpr inv.value .bool "invariant value" 0 plan.states.size 0 exprBudget #[]
  pure ()

end ProofForgeV2.Targets.Quint
