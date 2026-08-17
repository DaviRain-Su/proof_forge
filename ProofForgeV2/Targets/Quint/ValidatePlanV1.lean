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

/-- ADR-0030 E2: does an expression tree reference vaultNative (env-read)? -/
private partial def exprUsesVaultNativeV1 (e : Expr) : Bool :=
  match e with
  | .vaultNative => true
  | .litU64 _ | .litBool _ | .param _ | .stateLoad _ | .temp _ | .externalOk _ => false
  | .arith _ l r | .compare _ l r | .boolAnd l r | .boolOr l r =>
      exprUsesVaultNativeV1 l || exprUsesVaultNativeV1 r
  | .boolNot o => exprUsesVaultNativeV1 o
  | .ite c t e =>
      exprUsesVaultNativeV1 c || exprUsesVaultNativeV1 t || exprUsesVaultNativeV1 e

/-- Bounded Plan-expression type/reference checker. It runs only after the
    rendered-size/depth walk has admitted the expression. -/
private partial def inferExprType
    (e : Expr) (what : String)
    (paramCount stateCount assetOpCount fuel : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool) :
    CompileResult (ExprType × Nat) := do
  if fuel == 0 then
    planError s!"Quint plan {what} expression exhausted type-check fuel"
  let remaining := fuel - 1
  let numeric : ExprType := if signed then .int64 else .uint64
  match e with
  | .litU64 _ => pure (numeric, remaining)
  | .litBool _ => pure (.bool, remaining)
  | .param index =>
      unless index < paramCount do
        planError s!"Quint plan {what} references unknown parameter {index}"
      if paramIsPrincipal[index]? == some true then
        pure (.principal, remaining)
      else
        pure (numeric, remaining)
  | .stateLoad fieldIndex =>
      unless fieldIndex < stateCount do
        planError s!"Quint plan {what} references unknown state field {fieldIndex}"
      pure (numeric, remaining)
  | .temp _ => pure (numeric, remaining)
  | .vaultNative => pure (.uint64, remaining)
  | .externalOk ordinal =>
      unless ordinal < assetOpCount do
        planError s!"Quint plan {what} references unknown externalOk ordinal {ordinal}"
      pure (.bool, remaining)
  | .arith _ lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      unless lhsTy == numeric && rhsTy == numeric do
        planError s!"Quint plan {what} arithmetic operands must match the numeric domain"
      pure (numeric, remaining)
  | .compare op lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      match op with
      | .eq | .ne =>
          unless lhsTy == rhsTy && (lhsTy == .uint64 || lhsTy == .int64 || lhsTy == .bool) do
            planError s!"Quint plan {what} equality operands must share UInt64/Int64/Bool type"
      | .lt | .le | .gt | .ge =>
          unless lhsTy == numeric && rhsTy == numeric do
            planError s!"Quint plan {what} ordering operands must match the numeric domain"
      pure (.bool, remaining)
  | .boolAnd lhs rhs | .boolOr lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      unless lhsTy == .bool && rhsTy == .bool do
        planError s!"Quint plan {what} logical operands must be Bool"
      pure (.bool, remaining)
  | .boolNot operand => do
      let (operandTy, remaining) ←
        inferExprType operand what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      unless operandTy == .bool do
        planError s!"Quint plan {what} logical-not operand must be Bool"
      pure (.bool, remaining)
  | .ite cond t e => do
      let (condTy, remaining) ←
        inferExprType cond what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      unless condTy == .bool do
        planError s!"Quint plan {what} ite condition must be Bool"
      let (tTy, remaining) ←
        inferExprType t what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      let (eTy, remaining) ←
        inferExprType e what paramCount stateCount assetOpCount remaining
          paramIsPrincipal signed
      unless tTy == eTy do
        planError s!"Quint plan {what} ite branches must share a type"
      pure (tTy, remaining)

/-- Iterative, fuel-bounded expression validation. Counting expanded tree
    occurrences (rather than object identity) prevents shared SSA subtrees from
    becoming exponentially large rendered source. The returned value is the
    remaining plan-wide node budget. -/
private def validateExpr
    (e : Expr) (expected : ExprType) (what : String)
    (paramCount stateCount assetOpCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool) : CompileResult Nat := do
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
    | .litU64 _ | .litBool _ | .param _ | .stateLoad _ | .temp _
    | .vaultNative | .externalOk _ =>
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
    | .ite cond t e =>
        stack := stack.push (e, depth + 1)
        stack := stack.push (t, depth + 1)
        stack := stack.push (cond, depth + 1)
  let (actual, _) ←
    inferExprType e what paramCount stateCount assetOpCount maxExprNodes
      paramIsPrincipal signed
  unless actual == expected do
    planError s!"Quint plan {what} expression type does not match its use site"
  pure remaining

private def validateCheck
    (ck : Check) (paramCount stateCount assetOpCount remaining : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool) : CompileResult Nat :=
  validateExpr ck.condition .bool "check condition" paramCount stateCount assetOpCount
    remaining paramIsPrincipal signed

private partial def validateBodyStatements
    (owner : String) (resultKind : ResultKind)
    (paramCount stateCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool)
    (body : Array Statement) : CompileResult Nat := do
  let numeric : ExprType := if signed then .int64 else .uint64
  let mut remaining := remaining0
  let mut seen : Array Nat := #[]
  for stmt in body do
    match stmt with
    | .store fi e =>
        unless fi < stateCount do
          planError s!"Quint {owner} store references an unknown state field"
        if seen.contains fi then
          planError s!"Quint {owner} store list has duplicate field indices"
        seen := seen.push fi
        remaining ←
          validateExpr e numeric "store value" paramCount stateCount 0 remaining
            paramIsPrincipal signed
    | .ifThenElse cond thenBody elseBody =>
        remaining ←
          validateExpr cond .bool "if condition" paramCount stateCount 0 remaining
            paramIsPrincipal signed
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            paramIsPrincipal signed thenBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            paramIsPrincipal signed elseBody
    | .switchOn scrut cases defaultBody =>
        remaining ←
          validateExpr scrut numeric "switch scrutinee" paramCount stateCount 0 remaining
            paramIsPrincipal signed
        for (_, caseBody) in cases do
          remaining ←
            validateBodyStatements owner resultKind paramCount stateCount remaining
              paramIsPrincipal signed caseBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            paramIsPrincipal signed defaultBody
    | .forLoop _ initial condition update _ loopBody =>
        remaining ←
          validateExpr initial numeric "for initial" paramCount stateCount 0 remaining
            paramIsPrincipal signed
        remaining ←
          validateExpr condition .bool "for condition" paramCount stateCount 0 remaining
            paramIsPrincipal signed
        remaining ←
          validateExpr update numeric "for update" paramCount stateCount 0 remaining
            paramIsPrincipal signed
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            paramIsPrincipal signed loopBody
    | .returnValue e =>
        unless resultKind == .uint64 || resultKind == .int64 || resultKind == .bool do
          planError s!"Quint {owner} Unit/aggregate result must not return a scalar"
        let expected :=
          match resultKind with
          | .int64 => ExprType.int64
          | .bool => .bool
          | _ => .uint64
        remaining ←
          validateExpr e expected "return value" paramCount stateCount 0 remaining
            paramIsPrincipal signed
    | .returnAggregate leaves =>
        match resultKind with
        | .aggregate n =>
            unless leaves.size == n do
              planError s!"Quint {owner} aggregate return must have exactly {n} leaves"
            for e in leaves do
              remaining ←
                validateExpr e numeric "aggregate return leaf" paramCount stateCount 0
                  remaining paramIsPrincipal signed
        | _ =>
            planError s!"Quint {owner} cannot return an aggregate"
    | .returnNone =>
        unless resultKind == .unit do
          planError s!"Quint {owner} non-Unit result must return a value"
  pure remaining

private partial def bodyUsesVaultNativeV1 (body : Array Statement) : Bool :=
  body.any fun stmt =>
    match stmt with
    | .store _ e | .returnValue e => exprUsesVaultNativeV1 e
    | .ifThenElse cond thenBody elseBody =>
        exprUsesVaultNativeV1 cond ||
          bodyUsesVaultNativeV1 thenBody || bodyUsesVaultNativeV1 elseBody
    | .switchOn scrut cases defaultBody =>
        exprUsesVaultNativeV1 scrut ||
          cases.any (fun (_, b) => bodyUsesVaultNativeV1 b) ||
          bodyUsesVaultNativeV1 defaultBody
    | .forLoop _ initial cond update _ loopBody =>
        exprUsesVaultNativeV1 initial || exprUsesVaultNativeV1 cond ||
          exprUsesVaultNativeV1 update || bodyUsesVaultNativeV1 loopBody
    | .returnAggregate leaves => leaves.any exprUsesVaultNativeV1
    | .returnNone => false

private def validateStores
    (stores : Array (Nat × Expr)) (stateCount paramCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool) : CompileResult Nat := do
  unless stores.size ≤ maxStores do
    planError "Quint plan store count exceeds limit"
  let mut seen : Array Nat := #[]
  let mut remaining := remaining0
  let storeTy : ExprType := if signed then .int64 else .uint64
  for (fi, e) in stores do
    unless fi < stateCount do
      planError "Quint plan store references an unknown state field"
    if seen.contains fi then
      planError "Quint plan store list has duplicate field indices"
    seen := seen.push fi
    remaining ←
      validateExpr e storeTy "store value" paramCount stateCount 0 remaining
        paramIsPrincipal signed
  pure remaining

private def validateAssetOps
    (ops : Array PfAssetsOp) (paramCount stateCount remaining0 : Nat)
    (paramIsPrincipal : Array Bool) (signed : Bool) : CompileResult Nat := do
  let mut remaining := remaining0
  for op in ops do
    remaining ←
      validateExpr op.amount .uint64 "asset op amount" paramCount stateCount ops.size
        remaining paramIsPrincipal signed
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
  unless plan.entries.size > 0 || plan.views.size > 0 do
    planError "Quint plan requires at least one entry or view"
  let signed := plan.signedNumeric
  let mut exprBudget := maxPlanExprNodes
  -- Flattened Array (`name_i`) and Option (`name_tag`/`name_p0`) leaves are
  -- ordinary scalar identifiers; this gate does not distinguish them.
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
        validateStores init.stores plan.states.size init.params.size exprBudget #[] signed
  let mut entryNames : Array String := #[]
  let mut expectedAction : Nat := 1
  let mut anyVaultUse := false
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
      anyVaultUse := true
    exprBudget ←
      validateAssetOps ent.assetOps ent.params.size plan.states.size exprBudget
        ent.paramIsPrincipal signed
    for ck in ent.checks do
      exprBudget ←
        validateCheck ck ent.params.size plan.states.size ent.assetOps.size exprBudget
          ent.paramIsPrincipal signed
      if exprUsesVaultNativeV1 ck.condition then
        anyVaultUse := true
    if !ent.body.isEmpty then
      unless ent.stores.isEmpty && ent.result?.isNone do
        planError
          s!"Quint entry '{ent.name}' CFG body must not carry stores or result?"
      exprBudget ←
        validateBodyStatements ent.name ent.resultKind ent.params.size
          plan.states.size exprBudget ent.paramIsPrincipal signed ent.body
      if bodyUsesVaultNativeV1 ent.body then
        anyVaultUse := true
    else
      exprBudget ←
        validateStores ent.stores plan.states.size ent.params.size exprBudget
          ent.paramIsPrincipal signed
      for (_fi, se) in ent.stores do
        if exprUsesVaultNativeV1 se then
          anyVaultUse := true
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
    if !ent.body.isEmpty then
      pure ()
    else
    match ent.resultKind, ent.result?, ent.terminalRevert with
    | .unit, none, _ => pure ()
    | .unit, some _, _ =>
        planError s!"Quint entry '{ent.name}' Unit result must not carry a result expression"
    | .uint64, some e, false =>
        if exprUsesVaultNativeV1 e then
          anyVaultUse := true
        exprBudget ←
          validateExpr e .uint64 "entry result" ent.params.size plan.states.size
            ent.assetOps.size exprBudget ent.paramIsPrincipal signed
    | .int64, some e, false =>
        if exprUsesVaultNativeV1 e then
          anyVaultUse := true
        exprBudget ←
          validateExpr e .int64 "entry result" ent.params.size plan.states.size
            ent.assetOps.size exprBudget ent.paramIsPrincipal signed
    | .bool, some e, false =>
        if exprUsesVaultNativeV1 e then
          anyVaultUse := true
        exprBudget ←
          validateExpr e .bool "entry result" ent.params.size plan.states.size
            ent.assetOps.size exprBudget ent.paramIsPrincipal signed
    | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
        planError s!"Quint entry '{ent.name}' terminal revert must not carry a result expression"
    | .uint64, none, true | .int64, none, true | .bool, none, true => pure ()
    | .uint64, none, false | .int64, none, false | .bool, none, false =>
        planError s!"Quint entry '{ent.name}' non-Unit result is missing without terminal revert"
    | .aggregate n, some e, false =>
        unless 1 ≤ n && n ≤ 8 do
          planError s!"Quint entry '{ent.name}' aggregate return must have 1..8 leaves"
        unless ent.leaves.size == n && ent.leafIsInt.size == n do
          planError
            s!"Quint entry '{ent.name}' aggregate leaves must match resultKind leaf count"
        unless ent.leaves[0]? == some e do
          planError
            s!"Quint entry '{ent.name}' aggregate result must equal the first leaf"
        for i in [0:n] do
          let some leaf := ent.leaves[i]? |
            planError s!"Quint entry '{ent.name}' aggregate leaf {i} is missing"
          let some isInt := ent.leafIsInt[i]? |
            planError s!"Quint entry '{ent.name}' aggregate signedness {i} is missing"
          if exprUsesVaultNativeV1 leaf then
            anyVaultUse := true
          let ty := if isInt then ExprType.int64 else ExprType.uint64
          exprBudget ←
            validateExpr leaf ty "entry aggregate leaf" ent.params.size plan.states.size
              ent.assetOps.size exprBudget ent.paramIsPrincipal signed
    | .aggregate _, _, true =>
        planError s!"Quint entry '{ent.name}' terminal revert must not carry an aggregate return"
    | .aggregate _, none, false =>
        planError s!"Quint entry '{ent.name}' aggregate result is missing"
  let mut viewNames : Array String := #[]
  for v in plan.views do
    unless isSafeIdent v.name do
      planError s!"Quint view '{v.name}' is not a safe identifier"
    if viewNames.contains v.name then
      planError s!"Quint view '{v.name}' is duplicated"
    viewNames := viewNames.push v.name
    validateParams v.params
    if exprUsesVaultNativeV1 v.value then
      anyVaultUse := true
    for leaf in v.leaves do
      if exprUsesVaultNativeV1 leaf then
        anyVaultUse := true
    match v.resultKind with
    | .unit => planError s!"Quint view '{v.name}' cannot have Unit result"
    | .uint64 =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Quint view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .uint64 "view value" v.params.size plan.states.size 0
            exprBudget #[] signed
    | .int64 =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Quint view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .int64 "view value" v.params.size plan.states.size 0
            exprBudget #[] signed
    | .bool =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Quint view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .bool "view value" v.params.size plan.states.size 0
            exprBudget #[] signed
    | .aggregate n =>
        unless 1 ≤ n && n ≤ 8 do
          planError s!"Quint view '{v.name}' aggregate return must have 1..8 leaves"
        unless v.leaves.size == n && v.leafIsInt.size == n do
          planError
            s!"Quint view '{v.name}' aggregate leaves must match resultKind leaf count"
        unless v.leaves[0]? == some v.value do
          planError
            s!"Quint view '{v.name}' aggregate value must equal the first leaf"
        for i in [0:n] do
          let some e := v.leaves[i]? |
            planError s!"Quint view '{v.name}' aggregate leaf {i} is missing"
          let some isInt := v.leafIsInt[i]? |
            planError s!"Quint view '{v.name}' aggregate signedness {i} is missing"
          let ty := if isInt then ExprType.int64 else ExprType.uint64
          exprBudget ←
            validateExpr e ty "view aggregate leaf" v.params.size plan.states.size 0
              exprBudget #[] signed
  -- ADR-0030 E2: usesVaultNative covers entry asset ops AND env-read vaultNative
  -- expressions in entries/views (not only nonempty assetOps).
  unless plan.usesVaultNative == anyVaultUse do
    planError
      "Quint plan usesVaultNative must match nonempty entry assetOps or vaultNative env-read use"
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
      exprBudget ← validateCheck ck 0 plan.states.size 0 exprBudget #[] signed
    exprBudget ←
      validateExpr inv.value .bool "invariant value" 0 plan.states.size 0 exprBudget #[]
        signed
  pure ()

end ProofForgeV2.Targets.Quint
