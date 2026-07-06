import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Emit
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Invariants

namespace ProofForge.Backend.Quint.Lower

set_option linter.unusedVariables false

open ProofForge.IR (ValueType Literal Statement Entrypoint StateDecl Effect AssignOp)
open ProofForge.Backend.Quint

structure LowerError where
  message : String

def LowerError.render (err : LowerError) : String := err.message

/-- Quint reserved words that cannot be used as action or variable names. -/
abbrev LocalEnv := List (String × Expr)

def LocalEnv.lookup (name : String) (env : LocalEnv) : Option Expr :=
  match env with
  | [] => none
  | (k, v) :: rest =>
      if k == name then some v else LocalEnv.lookup name rest

def LocalEnv.bind (name : String) (value : Expr) (env : LocalEnv) : LocalEnv :=
  (name, value) :: env

def LocalEnv.upsert (name : String) (value : Expr) (env : LocalEnv) : LocalEnv :=
  match env with
  | [] => [(name, value)]
  | (k, v) :: rest =>
      if k == name then (name, value) :: rest else (k, v) :: LocalEnv.upsert name value rest

/-- Lowering context: local bindings, shadowed state values, and guards. -/
structure LowerCtx where
  locals : LocalEnv := []
  state : LocalEnv := []
  guards : Array ActionClause := #[]
  stateDecls : Array StateDecl := #[]

def LowerCtx.stateValue (ctx : LowerCtx) (stateId : String) : Expr :=
  match ctx.state.lookup stateId with
  | some value => value
  | none => .local stateId

def LowerCtx.lookupStateDecl (ctx : LowerCtx) (stateId : String) : Option StateDecl :=
  ctx.stateDecls.find? (fun s => s.id == stateId)

/-- IR array indices are 0-based; Quint list indices are 1-based. -/
def irIndexToQuint (idx : Expr) : Expr :=
  match idx with
  | .literalInt n => .literalInt (n + 1)
  | other => .binOp .add other (.literalInt 1)

partial def listGetAt (current : Expr) (quintPos : Nat) : Expr :=
  match current with
  | .listLit elems =>
      match elems[quintPos - 1]? with
      | some elem => elem
      | none => .literalInt 0
  | _ =>
      .index current (.literalInt (Int.ofNat quintPos))

def listSetAtLiteral (current : Expr) (cap : Nat) (idx : Nat) (value : Expr) : Expr :=
  let elems := (List.range cap).map (fun pos =>
    if pos == idx then value
    else listGetAt current (pos + 1))
  .listLit elems.toArray

def listSetAtExpr (current : Expr) (cap : Nat) (idx : Expr) (value : Expr) : Expr :=
  let quintIdx := irIndexToQuint idx
  let elems := (List.range cap).map (fun pos =>
    let quintPos := .literalInt (Int.ofNat (pos + 1))
    let atPos := listGetAt current (pos + 1)
    .ite (.binOp .eq quintIdx quintPos) value atPos)
  .listLit elems.toArray

def lowerType (t : ValueType) : Except LowerError QuintType := do
  match t with
  | .unit => .ok .int
  | .bool => .ok .bool
  | .u8 | .u32 | .u64 | .u128 => .ok .int
  | .address => .ok .str
  | .fixedArray elem _ => .ok (.list (← lowerType elem))
  | .array elem => .ok (.list (← lowerType elem))
  | .structType name => .ok (.custom name)
  | .bytes | .string | .hash =>
      .error { message := s!"unsupported IR value type for Quint lowering: {t.name}" }

def lowerStateVarType (s : StateDecl) : Except LowerError QuintType := do
  match s.kind with
  | .array _ => .ok (.list (← lowerType s.type))
  | _ => lowerType s.type

def lowerLiteral (lit : Literal) : Except LowerError Expr :=
  match lit with
  | .u8 n | .u32 n | .u64 n | .u128 n => .ok (.literalInt (Int.ofNat n))
  | .bool b => .ok (.literalBool b)
  | .address n => .ok (.literalStr s!"addr{n}")
  | .hash4 _ _ _ _ => .error { message := "hash literals not supported in Quint lowering v1" }

def lowerAssignOp (op : AssignOp) : BinOp :=
  match op with
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .and
  | .bitOr => .or
  | .bitXor => .or
  | .shiftLeft => .add
  | .shiftRight => .sub

mutual
  partial def lowerExpr (ctx : LowerCtx) (e : ProofForge.IR.Expr) : Except LowerError Expr := do
    match e with
    | .literal lit => lowerLiteral lit
    | .local name =>
        match ctx.locals.lookup name with
        | some expr => .ok expr
        | none => .ok (.local name)
    | .add lhs rhs => .ok (.binOp .add (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .sub lhs rhs =>
        let l ← lowerExpr ctx lhs
        let r ← lowerExpr ctx rhs
        .ok (.ite (.binOp .ge l r) (.binOp .sub l r) (.literalInt 0))
    | .mul lhs rhs => .ok (.binOp .mul (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .div lhs rhs =>
        let l ← lowerExpr ctx lhs
        let r ← lowerExpr ctx rhs
        .ok (.ite (.binOp .eq r (.literalInt 0)) (.literalInt 0) (.binOp .div l r))
    | .mod lhs rhs => .ok (.binOp .mod (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .eq lhs rhs => .ok (.binOp .eq (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .ne lhs rhs => .ok (.binOp .ne (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .lt lhs rhs => .ok (.binOp .lt (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .le lhs rhs => .ok (.binOp .le (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .gt lhs rhs => .ok (.binOp .gt (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .ge lhs rhs => .ok (.binOp .ge (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolAnd lhs rhs => .ok (.binOp .and (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolOr lhs rhs => .ok (.binOp .or (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))
    | .boolNot value => .ok (.unOp .not (← lowerExpr ctx value))
    | .cast value _ => lowerExpr ctx value
    | .arrayLit _ values => do
        let elems ← values.mapM (lowerExpr ctx)
        .ok (.listLit elems)
    | .arrayGet arr idx => do
        let arr' ← lowerExpr ctx arr
        let idx' ← lowerExpr ctx idx
        .ok (.index arr' (irIndexToQuint idx'))
    | .effect eff => lowerEffectExpr ctx eff
    | _ => .error { message := "unsupported IR expression for Quint lowering v1" }

  partial def lowerEffectExpr (ctx : LowerCtx) (eff : Effect) : Except LowerError Expr :=
    match eff with
    | .storageScalarRead stateId => .ok (ctx.stateValue stateId)
    | .storageArrayRead stateId key => do
        let key' ← lowerExpr ctx key
        .ok (.index (ctx.stateValue stateId) (irIndexToQuint key'))
    | .contextRead field =>
        match field with
        | .userId | .contractId | .checkpointId | .timestamp | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao =>
            .ok (.literalInt 0)
        | _ => .error { message := s!"unsupported context field for Quint lowering v1: {field.name}" }
    | _ => .error { message := "unsupported effect as expression for Quint lowering v1" }

  partial def applyEffect (ctx : LowerCtx) (eff : Effect) : Except LowerError LowerCtx := do
    match eff with
    | .storageScalarWrite stateId value =>
        let value' ← lowerExpr ctx value
        .ok { ctx with state := ctx.state.upsert stateId value' }
    | .storageScalarAssignOp stateId op value =>
        let cur := ctx.stateValue stateId
        let value' ← lowerExpr ctx value
        let qop := lowerAssignOp op
        .ok { ctx with state := ctx.state.upsert stateId (.binOp qop cur value') }
    | .storageArrayWrite stateId key value =>
        match ctx.lookupStateDecl stateId with
        | some { kind := .array cap, .. } =>
            let current := ctx.stateValue stateId
            let key' ← lowerExpr ctx key
            let value' ← lowerExpr ctx value
            let updated :=
              match key' with
              | .literalInt n =>
                  if n >= 0 && n.toNat < cap then
                    listSetAtLiteral current cap n.toNat value'
                  else
                    listSetAtExpr current cap key' value'
              | _ => listSetAtExpr current cap key' value'
            .ok { ctx with state := ctx.state.upsert stateId updated }
        | _ =>
            .error { message := s!"storageArrayWrite on unknown or non-array state `{stateId}`" }
    | .eventEmit _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.literalBool true)) }
    | _ => .error { message := "unsupported effect statement for Quint lowering v1" }

  partial def mergeBranchState (pre : LowerCtx) (cond : Expr) (thenCtx elseCtx : LowerCtx) : LocalEnv :=
    let branchIds :=
      (thenCtx.state ++ elseCtx.state).map Prod.fst |>.eraseDups
    branchIds.foldl (fun merged stateId =>
      let preVal := { pre with state := merged }.stateValue stateId
      let thenVal := match thenCtx.state.lookup stateId with | some v => v | none => preVal
      let elseVal := match elseCtx.state.lookup stateId with | some v => v | none => preVal
      merged.upsert stateId (.ite cond thenVal elseVal)) pre.state

  partial def wrapBranchGuards (cond : Expr) (negate : Bool) (guards : Array ActionClause) : Array ActionClause :=
    if guards.isEmpty then #[] else
      let guard := if negate then .guard (.unOp .not cond) else .guard cond
      #[.all (#[guard] ++ guards)]

  partial def lowerStatements (ctx : LowerCtx) (stmts : Array Statement) : Except LowerError LowerCtx := do
    stmts.foldlM (fun ctx stmt => lowerStatement ctx stmt) ctx

  partial def lowerStatement (ctx : LowerCtx) (s : Statement) : Except LowerError LowerCtx := do
    match s with
    | .letBind name _ value =>
        .ok { ctx with locals := ctx.locals.bind name (← lowerExpr ctx value) }
    | .letMutBind name _ value =>
        .ok { ctx with locals := ctx.locals.bind name (← lowerExpr ctx value) }
    | .assign _ _ =>
        .error { message := "local assignment not supported in Quint lowering v1" }
    | .assignOp _ _ _ =>
        .error { message := "compound local assignment not supported in Quint lowering v1" }
    | .effect eff =>
        applyEffect ctx eff
    | .assert condition _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (← lowerExpr ctx condition)) }
    | .assertEq lhs rhs _ _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.binOp .eq (← lowerExpr ctx lhs) (← lowerExpr ctx rhs))) }
    | .revert _ | .revertWithError _ =>
        .ok { ctx with guards := ctx.guards.push (.guard (.literalBool false)) }
    | .ifElse condition thenBody elseBody =>
        let cond ← lowerExpr ctx condition
        let thenCtx ← lowerStatements ctx thenBody
        let elseCtx ← lowerStatements ctx elseBody
        let mergedState := mergeBranchState ctx cond thenCtx elseCtx
        let thenWrapped := wrapBranchGuards cond false thenCtx.guards
        let elseWrapped := wrapBranchGuards cond true elseCtx.guards
        .ok { ctx with
          state := mergedState,
          guards := ctx.guards ++ thenWrapped ++ elseWrapped }
    | .boundedFor indexName start stopExclusive body =>
        let mut stateAcc := ctx.state
        let mut guardsAcc := ctx.guards
        for i in [start:stopExclusive] do
          let loopCtx := {
            ctx with
            locals := ctx.locals.bind indexName (.literalInt (Int.ofNat i)),
            state := stateAcc,
            guards := #[] }
          let bodyCtx ← lowerStatements loopCtx body
          stateAcc := bodyCtx.state
          guardsAcc := guardsAcc ++ bodyCtx.guards
        .ok { ctx with state := stateAcc, guards := guardsAcc }
    | .whileLoop _ _ =>
        .error { message := "whileLoop not supported in Quint lowering v1" }
    | .return _ | .release _ =>
        .ok ctx
end

def ctxToActionClauses (ctx : LowerCtx) : Array ActionClause :=
  let assigns := ctx.state.toArray.map (fun (stateId, value) =>
    ActionClause.assign (.prime (.local stateId)) value)
  assigns ++ ctx.guards

partial def assignedStateVars (clause : ActionClause) : List String :=
  match clause with
  | .assign (.prime (.local name)) _ => [name]
  | .all clauses | .any clauses =>
      clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  | .nondet _ _ body => assignedStateVars body
  | _ => []

def lowerEntrypoint (ep : Entrypoint) (stateIds : Array String) (stateDecls : Array StateDecl) : Except LowerError Action := do
  let params ← ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t))
  let ctx ← lowerStatements { stateDecls := stateDecls } ep.body
  let clauses := ctxToActionClauses ctx
  let assigned := clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  let identityClauses := stateIds.filterMap (fun id =>
    if assigned.contains id then none else some (.assign (.prime (.local id)) (.local id)))
  let body := ActionClause.all (clauses ++ identityClauses)
  pure {
    name := sanitizeName ep.name,
    params := params,
    ret? := some .bool,
    body := body
  }

def zeroExpr (t : ValueType) : Except LowerError Expr :=
  match t with
  | .bool => .ok (.literalBool false)
  | .u8 | .u32 | .u64 | .u128 | .unit => .ok (.literalInt 0)
  | .address => .ok (.literalStr "")
  | .fixedArray _ _ | .array _ => .ok (.listLit #[])
  | .structType _ => .ok (.app "__emptyStruct" #[])
  | .bytes | .string | .hash =>
      .error { message := s!"cannot zero-initialize type for Quint: {t.name}" }

def zeroExprForState (s : StateDecl) : Except LowerError Expr := do
  match s.kind with
  | .array cap =>
      let z ← zeroExpr s.type
      .ok (.listLit (Array.replicate cap z))
  | _ => zeroExpr s.type

def initAction (state : Array StateDecl) : Except LowerError Action := do
  let clauses ← state.mapM (fun s => do
    pure (.assign (.prime (.local s.id)) (← zeroExprForState s)))
  pure {
    name := "init",
    body := ActionClause.all clauses,
    ret? := none
  }

def paramDomainExpr (t : QuintType) : Expr :=
  match t with
  | .str => .oneOf (.local "USERS")
  | _ => .oneOf (.range (.literalInt 1) (.local "MAX_UINT"))

def entrypointStepCall (ep : Entrypoint) (params : Array (String × QuintType)) : ActionClause :=
  let rec buildNondet (remaining : List (String × QuintType)) (call : ActionClause) : ActionClause :=
    match remaining with
    | [] => call
    | (n, t) :: rest => buildNondet rest (.nondet n (paramDomainExpr t) call)
  let baseCall := ActionClause.call (sanitizeName ep.name) (params.map (fun (n, _) => .local n))
  if params.isEmpty then
    baseCall
  else
    buildNondet params.toList.reverse baseCall

def stepAction (entrypoints : Array Entrypoint) (loweredParams : Array (Array (String × QuintType))) : Action :=
  let pairs := Array.zip entrypoints loweredParams
  let calls := pairs.map (fun (ep, params) => entrypointStepCall ep params)
  {
    name := "step",
    body := ActionClause.any calls,
    ret? := none
  }

def lowerModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError Module := do
  let vars ← module.state.mapM (fun s => do
    pure { name := s.id, type := ← lowerStateVarType s })
  let init ← initAction module.state
  let stateIds := module.state.map (fun s => s.id)
  let epActions ← module.entrypoints.mapM (fun ep => lowerEntrypoint ep stateIds module.state)
  let epParams ← module.entrypoints.mapM (fun ep => do
    ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t)))
  let step := stepAction module.entrypoints epParams
  let vals ← match Invariants.derive module scenario with
    | .ok vs => .ok vs
    | .error e => .error { message := e }
  pure {
    name := s!"{module.name}Model",
    constants := #[],
    vars := vars,
    pureDefs := scenario.quintPureDefs,
    actions := #[init] ++ epActions ++ #[step],
    vals := vals
  }

def renderModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError String := do
  let qm ← lowerModule module scenario
  pure (Emit.emitModule qm)

end ProofForge.Backend.Quint.Lower