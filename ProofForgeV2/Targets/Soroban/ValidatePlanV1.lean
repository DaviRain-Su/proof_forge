import ProofForgeV2.Targets.Soroban.LowerSemanticV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Soroban ValidatePlanV1 — plan canonicity

Size, name, reference, count, and expression-depth checks before IR emission.
-/

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .soroban message

private def maxStates : Nat := 64
private def maxEntries : Nat := 256
private def maxViews : Nat := 256
private def maxParams : Nat := 64
private def maxChecks : Nat := 128
private def maxStores : Nat := 64
private def maxExprDepth : Nat := 256
private def maxExprNodes : Nat := 16384
private def maxPlanExprNodes : Nat := 131072
private def maxIdentifierBytes : Nat := 200

private def reservedRustWords : Array String :=
  #["as", "break", "const", "continue", "crate", "else", "enum", "extern",
    "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
    "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct",
    "super", "trait", "true", "type", "unsafe", "use", "where", "while",
    "async", "await", "dyn", "abstract", "become", "box", "do", "final",
    "macro", "override", "priv", "typeof", "unsized", "virtual", "yield"]

private def isReserved (name : String) : Bool :=
  reservedRustWords.contains name

private def isSafeIdent (name : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes name && !isReserved name

private partial def inferExprType
    (e : Expr) (what : String)
    (paramCount stateCount fuel : Nat) (signed : Bool)
    (sha256SiteCount : Nat) :
    CompileResult (ExprType × Nat) := do
  if fuel == 0 then
    planError s!"Soroban plan {what} expression exhausted type-check fuel"
  let remaining := fuel - 1
  let numeric : ExprType := if signed then .int64 else .uint64
  match e with
  | .litU64 _ => pure (numeric, remaining)
  | .litBool _ => pure (.bool, remaining)
  | .unixTimeSeconds | .blockHeight =>
      -- CAP-3: Semantic result is UInt64 even on signedNumeric programs.
      pure (.uint64, remaining)
  | .sha256Limb siteIndex limbIndex =>
      unless siteIndex < sha256SiteCount do
        planError s!"Soroban plan {what} references unknown sha256 site {siteIndex}"
      unless limbIndex < 4 do
        planError s!"Soroban plan {what} sha256 limb index must be 0..3"
      -- CAP-4: each limb is an unsigned u64 word of the Semantic LE digest.
      pure (.uint64, remaining)
  | .param index =>
      unless index < paramCount do
        planError s!"Soroban plan {what} references unknown parameter {index}"
      pure (numeric, remaining)
  | .stateLoad fieldIndex =>
      unless fieldIndex < stateCount do
        planError s!"Soroban plan {what} references unknown state field {fieldIndex}"
      pure (numeric, remaining)
  | .temp _ => pure (numeric, remaining)
  | .arith _ lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed sha256SiteCount
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed sha256SiteCount
      unless lhsTy == numeric && rhsTy == numeric do
        planError s!"Soroban plan {what} arithmetic operands must match the numeric domain"
      pure (numeric, remaining)
  | .compare op lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed sha256SiteCount
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed sha256SiteCount
      match op with
      | .eq | .ne =>
          unless lhsTy == rhsTy && (lhsTy == .uint64 || lhsTy == .int64 || lhsTy == .bool) do
            planError s!"Soroban plan {what} equality operands must share UInt64/Int64/Bool type"
      | .lt | .le | .gt | .ge =>
          unless lhsTy == numeric && rhsTy == numeric do
            planError s!"Soroban plan {what} ordering operands must match the numeric domain"
      pure (.bool, remaining)
  | .boolAnd lhs rhs | .boolOr lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed sha256SiteCount
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed sha256SiteCount
      unless lhsTy == .bool && rhsTy == .bool do
        planError s!"Soroban plan {what} logical operands must be Bool"
      pure (.bool, remaining)
  | .boolNot operand => do
      let (operandTy, remaining) ←
        inferExprType operand what paramCount stateCount remaining signed sha256SiteCount
      unless operandTy == .bool do
        planError s!"Soroban plan {what} logical-not operand must be Bool"
      pure (.bool, remaining)
  | .ite cond t e => do
      let (condTy, remaining) ←
        inferExprType cond what paramCount stateCount remaining signed sha256SiteCount
      unless condTy == .bool do
        planError s!"Soroban plan {what} ite condition must be Bool"
      let (tTy, remaining) ←
        inferExprType t what paramCount stateCount remaining signed sha256SiteCount
      let (eTy, remaining) ←
        inferExprType e what paramCount stateCount remaining signed sha256SiteCount
      unless tTy == eTy do
        planError s!"Soroban plan {what} ite branches must share a type"
      pure (tTy, remaining)

private def validateExpr
    (e : Expr) (expected : ExprType) (what : String)
    (paramCount stateCount remaining0 : Nat) (signed : Bool)
    (sha256SiteCount : Nat) : CompileResult Nat := do
  let mut stack : Array (Expr × Nat) := #[(e, 1)]
  let mut remaining := remaining0
  let mut localNodes : Nat := 0
  while !stack.isEmpty do
    if remaining == 0 then
      planError s!"Soroban plan expression budget exceeds {maxPlanExprNodes} nodes"
    remaining := remaining - 1
    localNodes := localNodes + 1
    if localNodes > maxExprNodes then
      planError s!"Soroban plan {what} expression exceeds {maxExprNodes} nodes"
    let (current, depth) := stack.back!
    stack := stack.pop
    if depth > maxExprDepth then
      planError s!"Soroban plan {what} expression exceeds depth limit"
    match current with
    | .litU64 _ | .litBool _ | .param _ | .stateLoad _ | .temp _
    | .unixTimeSeconds | .blockHeight | .sha256Limb _ _ =>
        pure ()
    | .arith op lhs rhs =>
        match op with
        | .div | .mod =>
            if remaining < 4 then
              planError s!"Soroban plan expression budget exceeds {maxPlanExprNodes} rendered nodes"
            if localNodes + 4 > maxExprNodes then
              planError s!"Soroban plan {what} expression exceeds {maxExprNodes} rendered nodes"
            if depth + 2 > maxExprDepth then
              planError s!"Soroban plan {what} rendered expression exceeds depth limit"
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
    inferExprType e what paramCount stateCount maxExprNodes signed sha256SiteCount
  unless actual == expected do
    planError s!"Soroban plan {what} expression type does not match its use site"
  pure remaining

private def validateCheck
    (ck : Check) (paramCount stateCount remaining : Nat) (signed : Bool)
    (sha256SiteCount : Nat) :
    CompileResult Nat :=
  validateExpr ck.condition .bool "check condition" paramCount stateCount remaining signed
    sha256SiteCount

private def validateStores
    (stores : Array (Nat × Expr)) (stateCount paramCount remaining0 : Nat)
    (signed : Bool) (sha256SiteCount : Nat) : CompileResult Nat := do
  unless stores.size ≤ maxStores do
    planError "Soroban plan store count exceeds limit"
  let mut seen : Array Nat := #[]
  let mut remaining := remaining0
  let numeric : ExprType := if signed then .int64 else .uint64
  for (fi, e) in stores do
    unless fi < stateCount do
      planError "Soroban plan store references an unknown state field"
    if seen.contains fi then
      planError "Soroban plan store list has duplicate field indices"
    seen := seen.push fi
    remaining ←
      validateExpr e numeric "store value" paramCount stateCount remaining signed
        sha256SiteCount
  pure remaining

private def validateSha256Sites
    (sites : Array Sha256Site) (paramCount stateCount remaining0 : Nat)
    (signed : Bool) : CompileResult Nat := do
  let mut remaining := remaining0
  for site in sites do
    remaining ←
      validateExpr site.input0 .uint64 "sha256 limb 0" paramCount stateCount remaining
        signed sites.size
    remaining ←
      validateExpr site.input1 .uint64 "sha256 limb 1" paramCount stateCount remaining
        signed sites.size
    remaining ←
      validateExpr site.input2 .uint64 "sha256 limb 2" paramCount stateCount remaining
        signed sites.size
    remaining ←
      validateExpr site.input3 .uint64 "sha256 limb 3" paramCount stateCount remaining
        signed sites.size
  pure remaining

private partial def validateBodyStatements
    (owner : String) (resultKind : ResultKind)
    (paramCount stateCount remaining0 : Nat) (signed : Bool)
    (sha256SiteCount : Nat)
    (body : Array Statement) : CompileResult Nat := do
  let numeric : ExprType := if signed then .int64 else .uint64
  let mut remaining := remaining0
  let mut seen : Array Nat := #[]
  for stmt in body do
    match stmt with
    | .store fi e =>
        unless fi < stateCount do
          planError s!"Soroban {owner} store references an unknown state field"
        if seen.contains fi then
          planError s!"Soroban {owner} store list has duplicate field indices"
        seen := seen.push fi
        remaining ←
          validateExpr e numeric "store value" paramCount stateCount remaining signed
            sha256SiteCount
    | .ifThenElse cond thenBody elseBody =>
        remaining ←
          validateExpr cond .bool "if condition" paramCount stateCount remaining signed
            sha256SiteCount
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed sha256SiteCount thenBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed sha256SiteCount elseBody
    | .switchOn scrut cases defaultBody =>
        remaining ←
          validateExpr scrut numeric "switch scrutinee" paramCount stateCount remaining
            signed sha256SiteCount
        for (_, caseBody) in cases do
          remaining ←
            validateBodyStatements owner resultKind paramCount stateCount remaining
              signed sha256SiteCount caseBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed sha256SiteCount defaultBody
    | .forLoop _ initial condition update _ body =>
        remaining ←
          validateExpr initial numeric "for initial" paramCount stateCount remaining
            signed sha256SiteCount
        remaining ←
          validateExpr condition .bool "for condition" paramCount stateCount remaining
            signed sha256SiteCount
        remaining ←
          validateExpr update numeric "for update" paramCount stateCount remaining
            signed sha256SiteCount
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed sha256SiteCount body
    | .returnValue e =>
        let expected :=
          match resultKind with
          | .uint64 => ExprType.uint64
          | .int64 => .int64
          | .bool => .bool
          | .unit | .aggregate _ =>
              ExprType.uint64
        unless resultKind == .uint64 || resultKind == .int64 || resultKind == .bool do
          planError s!"Soroban {owner} Unit/aggregate result must not return a scalar"
        remaining ←
          validateExpr e expected "return value" paramCount stateCount remaining signed
            sha256SiteCount
    | .returnAggregate leaves =>
        match resultKind with
        | .aggregate n =>
            unless leaves.size == n do
              planError s!"Soroban {owner} aggregate return must have exactly {n} leaves"
            for e in leaves do
              remaining ←
                validateExpr e numeric "aggregate return leaf" paramCount stateCount
                  remaining signed sha256SiteCount
        | _ =>
            planError s!"Soroban {owner} cannot return an aggregate"
    | .returnNone =>
        unless resultKind == .unit do
          planError s!"Soroban {owner} non-Unit result must return a value"
  pure remaining

private def validateParams (params : Array String) : CompileResult Unit := do
  unless params.size ≤ maxParams do
    planError "Soroban plan parameter count exceeds limit"
  let mut seen : Array String := #[]
  for p in params do
    unless isSafeIdent p do
      planError s!"Soroban parameter '{p}' is not a safe identifier"
    if seen.contains p then
      planError s!"Soroban parameter '{p}' is duplicated"
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
    planError s!"Soroban program name '{plan.programName}' is not a safe identifier"
  unless plan.states.size ≤ maxStates do
    planError "Soroban plan exceeds the state field limit"
  unless plan.entries.size ≤ maxEntries do
    planError "Soroban plan exceeds the entry limit"
  unless plan.views.size ≤ maxViews do
    planError "Soroban plan exceeds the view limit"
  unless plan.entries.size > 0 || plan.views.size > 0 do
    planError "Soroban plan requires at least one entry or view"
  let signed := plan.signedNumeric
  let mut exprBudget := maxPlanExprNodes
  let mut stateNames : Array String := #[]
  for st in plan.states do
    unless isSafeIdent st.name do
      planError s!"Soroban state '{st.name}' is not a safe identifier"
    -- Same 9-byte `symbol_short!` gate for scalar names, Array
    -- `{name}_{i}`, Option `{name}_tag`/`{name}_p0`, and Map
    -- `{name}_0`..`{name}_23`. Never truncate.
    unless st.name.toUTF8.size ≤ 9 do
      planError s!"Soroban state '{st.name}' exceeds symbol_short! 9-byte limit"
    if stateNames.contains st.name then
      planError s!"Soroban state '{st.name}' is duplicated"
    stateNames := stateNames.push st.name
  match plan.initializer with
  | none => pure ()
  | some init => do
      unless isSafeIdent init.name do
        planError s!"Soroban initializer '{init.name}' is not a safe identifier"
      validateParams init.params
      exprBudget ←
        validateSha256Sites init.sha256Sites init.params.size plan.states.size
          exprBudget signed
      exprBudget ←
        validateStores init.stores plan.states.size init.params.size exprBudget signed
          init.sha256Sites.size
  let mut entryNames : Array String := #[]
  for ent in plan.entries do
    unless isSafeIdent ent.name do
      planError s!"Soroban entry '{ent.name}' is not a safe identifier"
    if entryNames.contains ent.name then
      planError s!"Soroban entry '{ent.name}' is duplicated"
    entryNames := entryNames.push ent.name
    validateParams ent.params
    unless ent.checks.size ≤ maxChecks do
      planError "Soroban entry check count exceeds limit"
    exprBudget ←
      validateSha256Sites ent.sha256Sites ent.params.size plan.states.size
        exprBudget signed
    for ck in ent.checks do
      exprBudget ←
        validateCheck ck ent.params.size plan.states.size exprBudget signed
          ent.sha256Sites.size
    if !ent.body.isEmpty then
      unless ent.stores.isEmpty && ent.result?.isNone do
        planError
          s!"Soroban entry '{ent.name}' CFG body must not carry stores or result?"
      exprBudget ←
        validateBodyStatements ent.name ent.resultKind ent.params.size
          plan.states.size exprBudget signed ent.sha256Sites.size ent.body
    else
      exprBudget ←
        validateStores ent.stores plan.states.size ent.params.size exprBudget signed
          ent.sha256Sites.size
    let terminalMarkerCount := ent.checks.foldl
      (fun n ck => if isTerminalRevertKind ck.kind then n + 1 else n) 0
    if ent.terminalRevert then
      unless terminalMarkerCount == 1 do
        planError s!"Soroban entry '{ent.name}' terminalRevert requires exactly one terminal marker"
      match ent.checks.back? with
      | some ck =>
          unless isCanonicalTerminalRevertCheck ck do
            planError s!"Soroban entry '{ent.name}' terminalRevert requires a final terminal-revert(false) check"
      | none =>
          planError s!"Soroban entry '{ent.name}' terminalRevert requires a terminal-revert check"
    else unless terminalMarkerCount == 0 do
      planError s!"Soroban entry '{ent.name}' has a terminal-revert marker without terminalRevert"
    if !ent.body.isEmpty then
      pure ()
    else
    match ent.resultKind, ent.result?, ent.terminalRevert with
    | .unit, none, _ => pure ()
    | .unit, some _, _ =>
        planError s!"Soroban entry '{ent.name}' Unit result must not carry a result expression"
    | .uint64, some e, false =>
        exprBudget ←
          validateExpr e .uint64 "entry result" ent.params.size plan.states.size exprBudget signed
            ent.sha256Sites.size
    | .int64, some e, false =>
        exprBudget ←
          validateExpr e .int64 "entry result" ent.params.size plan.states.size exprBudget signed
            ent.sha256Sites.size
    | .bool, some e, false =>
        exprBudget ←
          validateExpr e .bool "entry result" ent.params.size plan.states.size exprBudget signed
            ent.sha256Sites.size
    | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
        planError s!"Soroban entry '{ent.name}' terminal revert must not carry a result expression"
    | .uint64, none, true | .int64, none, true | .bool, none, true => pure ()
    | .uint64, none, false | .int64, none, false | .bool, none, false =>
        planError s!"Soroban entry '{ent.name}' non-Unit result is missing without terminal revert"
    | .aggregate n, some e, false => do
        unless n == 24 || (1 ≤ n && n ≤ 8) do
          planError s!"Soroban entry '{ent.name}' aggregate return must have 1..8 leaves (or 24 for Map)"
        unless ent.leaves.size == n && ent.leafIsInt.size == n do
          planError
            s!"Soroban entry '{ent.name}' aggregate leaves must match resultKind leaf count"
        unless ent.leaves[0]? == some e do
          planError
            s!"Soroban entry '{ent.name}' aggregate result must equal the first leaf"
        for i in [0:n] do
          let some leaf := ent.leaves[i]? |
            planError s!"Soroban entry '{ent.name}' aggregate leaf {i} is missing"
          let some isInt := ent.leafIsInt[i]? |
            planError s!"Soroban entry '{ent.name}' aggregate signedness {i} is missing"
          let _ := isInt
          let ty := if signed then ExprType.int64 else ExprType.uint64
          exprBudget ←
            validateExpr leaf ty "entry aggregate leaf" ent.params.size plan.states.size exprBudget signed
              ent.sha256Sites.size
    | .aggregate _, _, true =>
        planError s!"Soroban entry '{ent.name}' terminal revert must not carry an aggregate return"
    | .aggregate _, none, false =>
        planError s!"Soroban entry '{ent.name}' aggregate result is missing"
  let mut viewNames : Array String := #[]
  for v in plan.views do
    unless isSafeIdent v.name do
      planError s!"Soroban view '{v.name}' is not a safe identifier"
    if viewNames.contains v.name then
      planError s!"Soroban view '{v.name}' is duplicated"
    viewNames := viewNames.push v.name
    validateParams v.params
    match v.resultKind with
    | .unit => planError s!"Soroban view '{v.name}' cannot have Unit result"
    | .uint64 =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Soroban view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .uint64 "view value" v.params.size plan.states.size exprBudget signed
            0
    | .int64 =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Soroban view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .int64 "view value" v.params.size plan.states.size exprBudget signed
            0
    | .bool =>
        unless v.leaves.isEmpty && v.leafIsInt.isEmpty do
          planError s!"Soroban view '{v.name}' scalar result must not carry aggregate leaves"
        exprBudget ←
          validateExpr v.value .bool "view value" v.params.size plan.states.size exprBudget signed
            0
    | .aggregate n =>
        unless n == 24 || (1 ≤ n && n ≤ 8) do
          planError s!"Soroban view '{v.name}' aggregate return must have 1..8 leaves (or 24 for Map)"
        unless v.leaves.size == n && v.leafIsInt.size == n do
          planError
            s!"Soroban view '{v.name}' aggregate leaves must match resultKind leaf count"
        unless v.leaves[0]? == some v.value do
          planError
            s!"Soroban view '{v.name}' aggregate value must equal the first leaf"
        for i in [0:n] do
          let some e := v.leaves[i]? |
            planError s!"Soroban view '{v.name}' aggregate leaf {i} is missing"
          let some isInt := v.leafIsInt[i]? |
            planError s!"Soroban view '{v.name}' aggregate signedness {i} is missing"
          let _ := isInt
          let ty := if signed then ExprType.int64 else ExprType.uint64
          exprBudget ←
            validateExpr e ty "view aggregate leaf" v.params.size plan.states.size exprBudget signed
            0
  pure ()

end ProofForgeV2.Targets.Soroban
