import ProofForgeV2.Targets.Xrpl.LowerSemanticV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# XRPL ValidatePlanV1 — plan canonicity

Size, name, reference, and expression-depth checks before IR emission.
-/

namespace ProofForgeV2.Targets.Xrpl

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .xrpl message

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
    "macro", "override", "priv", "typeof", "unsized", "virtual", "yield",
    "try", "union", "main", "u8", "u16", "u32", "u64", "u128",
    "i8", "i16", "i32", "i64", "i128", "bool", "str", "String"]

private def isReserved (name : String) : Bool :=
  reservedRustWords.contains name

private def isSafeIdent (name : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes name && !isReserved name

private def numericTyOf (signed : Bool) : ExprType :=
  if signed then .int64 else .uint64

private partial def inferExprType
    (e : Expr) (what : String)
    (paramCount stateCount fuel : Nat) (signed : Bool) :
    CompileResult (ExprType × Nat) := do
  if fuel == 0 then
    planError s!"XRPL plan {what} expression exhausted type-check fuel"
  let remaining := fuel - 1
  let numeric := numericTyOf signed
  match e with
  | .litU64 _ => pure (numeric, remaining)
  | .litBool _ => pure (.bool, remaining)
  | .temp _ => pure (numeric, remaining)
  | .param index =>
      unless index < paramCount do
        planError s!"XRPL plan {what} references unknown parameter {index}"
      pure (numeric, remaining)
  | .stateLoad fieldIndex =>
      unless fieldIndex < stateCount do
        planError s!"XRPL plan {what} references unknown state field {fieldIndex}"
      pure (numeric, remaining)
  | .arith _ lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed
      unless lhsTy == numeric && rhsTy == numeric do
        planError s!"XRPL plan {what} arithmetic operands must match the program integer domain"
      pure (numeric, remaining)
  | .compare op lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed
      match op with
      | .eq | .ne =>
          unless lhsTy == rhsTy && (lhsTy == .uint64 || lhsTy == .int64 || lhsTy == .bool) do
            planError s!"XRPL plan {what} equality operands must share UInt64/Int64/Bool type"
      | .lt | .le | .gt | .ge =>
          unless lhsTy == numeric && rhsTy == numeric do
            planError s!"XRPL plan {what} ordering operands must match the program integer domain"
      pure (.bool, remaining)
  | .boolAnd lhs rhs | .boolOr lhs rhs => do
      let (lhsTy, remaining) ←
        inferExprType lhs what paramCount stateCount remaining signed
      let (rhsTy, remaining) ←
        inferExprType rhs what paramCount stateCount remaining signed
      unless lhsTy == .bool && rhsTy == .bool do
        planError s!"XRPL plan {what} logical operands must be Bool"
      pure (.bool, remaining)
  | .boolNot operand => do
      let (operandTy, remaining) ←
        inferExprType operand what paramCount stateCount remaining signed
      unless operandTy == .bool do
        planError s!"XRPL plan {what} logical-not operand must be Bool"
      pure (.bool, remaining)
  | .ite cond thenExpr elseExpr => do
      let (condTy, remaining) ←
        inferExprType cond what paramCount stateCount remaining signed
      let (thenTy, remaining) ←
        inferExprType thenExpr what paramCount stateCount remaining signed
      let (elseTy, remaining) ←
        inferExprType elseExpr what paramCount stateCount remaining signed
      unless condTy == .bool do
        planError s!"XRPL plan {what} ite condition must be Bool"
      unless thenTy == elseTy do
        planError s!"XRPL plan {what} ite branches must share a type"
      pure (thenTy, remaining)

private def validateExpr
    (e : Expr) (expected : ExprType) (what : String)
    (paramCount stateCount remaining0 : Nat) (signed : Bool) : CompileResult Nat := do
  let mut stack : Array (Expr × Nat) := #[(e, 1)]
  let mut remaining := remaining0
  let mut localNodes : Nat := 0
  while !stack.isEmpty do
    if remaining == 0 then
      planError s!"XRPL plan expression budget exceeds {maxPlanExprNodes} nodes"
    remaining := remaining - 1
    localNodes := localNodes + 1
    if localNodes > maxExprNodes then
      planError s!"XRPL plan {what} expression exceeds {maxExprNodes} nodes"
    let (current, depth) := stack.back!
    stack := stack.pop
    if depth > maxExprDepth then
      planError s!"XRPL plan {what} expression exceeds depth limit"
    match current with
    | .litU64 _ | .litBool _ | .param _ | .stateLoad _ | .temp _ => pure ()
    | .arith _ lhs rhs =>
        stack := stack.push (rhs, depth + 1)
        stack := stack.push (lhs, depth + 1)
    | .compare _ lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
        stack := stack.push (rhs, depth + 1)
        stack := stack.push (lhs, depth + 1)
    | .boolNot operand =>
        stack := stack.push (operand, depth + 1)
    | .ite cond thenExpr elseExpr =>
        stack := stack.push (elseExpr, depth + 1)
        stack := stack.push (thenExpr, depth + 1)
        stack := stack.push (cond, depth + 1)
  let (actual, _) ← inferExprType e what paramCount stateCount maxExprNodes signed
  unless actual == expected do
    planError s!"XRPL plan {what} expression type does not match its use site"
  pure remaining

private def validateCheck
    (ck : Check) (paramCount stateCount remaining : Nat) (signed : Bool) :
    CompileResult Nat :=
  validateExpr ck.condition .bool "check condition" paramCount stateCount remaining signed

private def validateStores
    (stores : Array (Nat × Expr)) (stateCount paramCount remaining0 : Nat)
    (signed : Bool) :
    CompileResult Nat := do
  unless stores.size ≤ maxStores do
    planError "XRPL plan store count exceeds limit"
  let mut seen : Array Nat := #[]
  let mut remaining := remaining0
  let numeric := numericTyOf signed
  for (fi, e) in stores do
    unless fi < stateCount do
      planError "XRPL plan store references an unknown state field"
    if seen.contains fi then
      planError "XRPL plan store list has duplicate field indices"
    seen := seen.push fi
    remaining ←
      validateExpr e numeric "store value" paramCount stateCount remaining signed
  pure remaining

private def validateParams (params : Array String) : CompileResult Unit := do
  unless params.size ≤ maxParams do
    planError "XRPL plan parameter count exceeds limit"
  let mut seen : Array String := #[]
  for p in params do
    unless isSafeIdent p do
      planError s!"XRPL parameter '{p}' is not a safe identifier"
    if seen.contains p then
      planError s!"XRPL parameter '{p}' is duplicated"
    seen := seen.push p

private partial def validateBodyStatements
    (owner : String) (resultKind : ResultKind)
    (paramCount stateCount remaining0 : Nat) (signed : Bool)
    (body : Array Statement) : CompileResult Nat := do
  let mut remaining := remaining0
  let mut seen : Array Nat := #[]
  let numeric := numericTyOf signed
  for stmt in body do
    match stmt with
    | .store fi e =>
        unless fi < stateCount do
          planError s!"XRPL {owner} store references an unknown state field"
        if seen.contains fi then
          planError s!"XRPL {owner} store list has duplicate field indices"
        seen := seen.push fi
        remaining ←
          validateExpr e numeric "store value" paramCount stateCount remaining signed
    | .ifThenElse cond thenBody elseBody =>
        remaining ←
          validateExpr cond .bool "if condition" paramCount stateCount remaining signed
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed thenBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed elseBody
    | .switchOn scrut cases defaultBody =>
        remaining ←
          validateExpr scrut numeric "switch scrutinee" paramCount stateCount remaining
            signed
        for (_, caseBody) in cases do
          remaining ←
            validateBodyStatements owner resultKind paramCount stateCount remaining
              signed caseBody
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed defaultBody
    | .forLoop _ initial condition update _ body =>
        remaining ←
          validateExpr initial numeric "for initial" paramCount stateCount remaining
            signed
        remaining ←
          validateExpr condition .bool "for condition" paramCount stateCount remaining
            signed
        remaining ←
          validateExpr update numeric "for update" paramCount stateCount remaining
            signed
        remaining ←
          validateBodyStatements owner resultKind paramCount stateCount remaining
            signed body
    | .returnValue e =>
        unless resultKind == .uint64 || resultKind == .int64 || resultKind == .bool do
          planError s!"XRPL {owner} Unit/aggregate result must not return a scalar"
        let expected :=
          match resultKind with
          | .bool => ExprType.bool
          | .int64 => ExprType.int64
          | _ => .uint64
        remaining ←
          validateExpr e expected "return value" paramCount stateCount remaining signed
    | .returnAggregate leaves =>
        match resultKind with
        | .aggregate n =>
            unless leaves.size == n do
              planError s!"XRPL {owner} aggregate return must have exactly {n} leaves"
            for e in leaves do
              remaining ←
                validateExpr e numeric "aggregate return leaf" paramCount stateCount
                  remaining signed
        | _ =>
            planError s!"XRPL {owner} cannot return an aggregate"
    | .returnNone =>
        unless resultKind == .unit do
          planError s!"XRPL {owner} non-Unit result must return a value"
  pure remaining

private def isCanonicalTerminalRevertCheck (ck : Check) : Bool :=
  match ck.kind, ck.condition with
  | .terminalRevert _, .litBool false => true
  | _, _ => false

def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isSafeIdent plan.programName do
    planError s!"XRPL program name '{plan.programName}' is not a safe identifier"
  unless plan.states.size ≤ maxStates do
    planError "XRPL plan exceeds the state field limit"
  unless plan.entries.size ≤ maxEntries do
    planError "XRPL plan exceeds the entry limit"
  unless plan.views.size ≤ maxViews do
    planError "XRPL plan exceeds the view limit"
  unless plan.entries.size > 0 || plan.views.size > 0 do
    planError "XRPL plan requires at least one entry or view"
  let signed := plan.signedNumeric
  let numeric := numericTyOf signed
  let mut exprBudget := maxPlanExprNodes
  let mut stateNames : Array String := #[]
  for st in plan.states do
    unless isSafeIdent st.name do
      planError s!"XRPL state '{st.name}' is not a safe identifier"
    if stateNames.contains st.name then
      planError s!"XRPL state '{st.name}' is duplicated"
    stateNames := stateNames.push st.name
  if let some initFn := plan.initializer then
    unless isSafeIdent initFn.name do
      planError s!"XRPL initializer '{initFn.name}' is not a safe identifier"
    validateParams initFn.params
    exprBudget ←
      validateStores initFn.stores plan.states.size initFn.params.size exprBudget
        signed
  let mut entryNames : Array String := #[]
  for ent in plan.entries do
    unless isSafeIdent ent.name do
      planError s!"XRPL entry '{ent.name}' is not a safe identifier"
    if entryNames.contains ent.name then
      planError s!"XRPL entry '{ent.name}' is duplicated"
    entryNames := entryNames.push ent.name
    validateParams ent.params
    unless ent.checks.size ≤ maxChecks do
      planError "XRPL plan check count exceeds limit"
    for ck in ent.checks do
      exprBudget ← validateCheck ck ent.params.size plan.states.size exprBudget signed
    if !ent.body.isEmpty then
      unless ent.stores.isEmpty && ent.result?.isNone && ent.resultLeaves.isEmpty do
        planError
          s!"XRPL entry '{ent.name}' CFG body cannot mix with flat stores/result"
      exprBudget ←
        validateBodyStatements ent.name ent.resultKind ent.params.size
          plan.states.size exprBudget signed ent.body
    else
    exprBudget ←
      validateStores ent.stores plan.states.size ent.params.size exprBudget signed
    if ent.body.isEmpty then
    match ent.resultKind, ent.result?, ent.terminalRevert with
    | .unit, none, _ => pure ()
    | .unit, some _, _ =>
        planError s!"XRPL entry '{ent.name}' Unit result must not return a value"
    | .uint64, some e, false =>
        exprBudget ←
          validateExpr e .uint64 "entry result" ent.params.size plan.states.size
            exprBudget signed
    | .int64, some e, false =>
        exprBudget ←
          validateExpr e .int64 "entry result" ent.params.size plan.states.size
            exprBudget signed
    | .bool, some e, false =>
        exprBudget ←
          validateExpr e .bool "entry result" ent.params.size plan.states.size
            exprBudget signed
    | .uint64, none, true | .int64, none, true | .bool, none, true =>
        unless ent.checks.any isCanonicalTerminalRevertCheck do
          planError s!"XRPL entry '{ent.name}' terminal revert is not canonical"
    | .uint64, none, false | .int64, none, false | .bool, none, false =>
        planError s!"XRPL entry '{ent.name}' non-Unit return is missing"
    | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
        planError s!"XRPL entry '{ent.name}' revert path cannot carry a return value"
    | .aggregate n, some _, false => do
        unless (n == 24 || n == 9 || (1 ≤ n && n ≤ 8)) && ent.resultLeaves.size == n do
          planError
            s!"XRPL entry '{ent.name}' aggregate leaf count must be 1..8 (or Map 24) and match resultKind"
        unless ent.checks.isEmpty do
          planError
            s!"XRPL entry '{ent.name}' aggregate return cannot contain fallible checks"
        unless !ent.terminalRevert do
          planError
            s!"XRPL entry '{ent.name}' aggregate return cannot be a terminal revert"
        for e in ent.resultLeaves do
          exprBudget ←
            validateExpr e numeric "entry aggregate leaf" ent.params.size
              plan.states.size exprBudget signed
    | .aggregate _, _, _ =>
        planError s!"XRPL entry '{ent.name}' aggregate return is not canonical"
  let mut viewNames : Array String := #[]
  for v in plan.views do
    unless isSafeIdent v.name do
      planError s!"XRPL view '{v.name}' is not a safe identifier"
    if viewNames.contains v.name || entryNames.contains v.name then
      planError s!"XRPL view '{v.name}' collides with another callable"
    viewNames := viewNames.push v.name
    validateParams v.params
    match v.resultKind with
    | .unit =>
        planError s!"XRPL view '{v.name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
    | .uint64 =>
        exprBudget ←
          validateExpr v.value .uint64 "view result" v.params.size plan.states.size
            exprBudget signed
    | .int64 =>
        exprBudget ←
          validateExpr v.value .int64 "view result" v.params.size plan.states.size
            exprBudget signed
    | .bool =>
        exprBudget ←
          validateExpr v.value .bool "view result" v.params.size plan.states.size
            exprBudget signed
    | .aggregate n => do
        unless (n == 24 || n == 9 || (1 ≤ n && n ≤ 8)) && v.leaves.size == n do
          planError
            s!"XRPL view '{v.name}' aggregate leaf count must be 1..8 (or Map 24) and match resultKind"
        for e in v.leaves do
          exprBudget ←
            validateExpr e numeric "view aggregate leaf" v.params.size
              plan.states.size exprBudget signed
  pure ()

end ProofForgeV2.Targets.Xrpl
