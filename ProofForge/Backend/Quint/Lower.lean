import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Emit
import ProofForge.Backend.Quint.Scenario
import ProofForge.Backend.Quint.Invariants

namespace ProofForge.Backend.Quint.Lower

set_option linter.unusedVariables false

open ProofForge.IR (ValueType Literal Statement Entrypoint StateDecl StructDecl Effect AssignOp)
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
  structs : Array StructDecl := #[]
  pureDefs : Array PureDef := #[]
  maxLoopUnroll : Nat := 10
  /-- When false, `__while_*` step locals stay symbolic during unrolling. -/
  expandLocals : Bool := true

def hashLiteralStr (a b c d : Nat) : String :=
  s!"hash:{a}:{b}:{c}:{d}"

def structFieldVarName (stateId fieldName : String) : String :=
  s!"{stateId}_{fieldName}"

def lookupStructDecl (structs : Array StructDecl) (name : String) : Option StructDecl :=
  structs.find? (fun s => s.name == name)

def mapKeysExpr (mapExpr : Expr) : Expr :=
  .methodCall mapExpr "keys" #[]

def mapContainsExpr (key mapExpr : Expr) : Expr :=
  .methodCall key "in" #[mapKeysExpr mapExpr]

def emptyMapExpr : Expr :=
  .app "Map" #[]

def hashZeroExpr : Expr :=
  .literalStr (hashLiteralStr 0 0 0 0)

def expandedStateIds (state : Array StateDecl) (structs : Array StructDecl) : Array String :=
  state.foldl (fun acc decl =>
    match decl.type with
    | .structType typeName =>
        match lookupStructDecl structs typeName with
        | some structDecl =>
            acc ++ structDecl.fields.map (fun field => structFieldVarName decl.id field.id)
        | none => acc.push decl.id
    | _ => acc.push decl.id) #[]

def whileStepLocalName (stateId : String) (step : Nat) : String :=
  s!"__while_{stateId}_{step}"

def isWhileStepLocal (name : String) : Bool :=
  name.startsWith "__while_"

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
  | .hash => .ok .hashStr
  | .fixedArray elem _ => .ok (.list (← lowerType elem))
  | .array elem => .ok (.list (← lowerType elem))
  | .structType _ => .ok (.map .str .int)
  | .bytes | .string =>
      .error { message := s!"unsupported IR value type for Quint lowering: {t.name}" }

def lowerStateVarType (s : StateDecl) : Except LowerError QuintType := do
  match s.kind with
  | .array _ => .ok (.list (← lowerType s.type))
  | .map _ _ => .ok (.map .str (← lowerType s.type))
  | _ => lowerType s.type

def quintStateVars (state : Array StateDecl) (structs : Array StructDecl) :
    Except LowerError (Array (String × QuintType)) := do
  let mut vars := #[]
  for decl in state do
    match decl.type with
    | .structType typeName =>
        match lookupStructDecl structs typeName with
        | some structDecl =>
            for field in structDecl.fields do
              vars := vars.push (structFieldVarName decl.id field.id, ← lowerType field.type)
        | none =>
            vars := vars.push (decl.id, ← lowerStateVarType decl)
    | _ =>
        vars := vars.push (decl.id, ← lowerStateVarType decl)
  pure vars

def lowerLiteral (lit : Literal) : Except LowerError Expr :=
  match lit with
  | .u8 n | .u32 n | .u64 n | .u128 n => .ok (.literalInt (Int.ofNat n))
  | .bool b => .ok (.literalBool b)
  | .address n => .ok (.literalStr s!"addr{n}")
  | .hash4 a b c d => .ok (.literalStr (hashLiteralStr a b c d))

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
        if !ctx.expandLocals && isWhileStepLocal name then
          .ok (.local name)
        else
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
    | .structLit _ fields => do
        let entries ← fields.mapM (fun (fieldName, fieldExpr) => do
          pure (.literalStr fieldName, ← lowerExpr ctx fieldExpr))
        .ok (.mapLit entries)
    | .field base fieldName => do
        let base' ← lowerExpr ctx base
        .ok (.methodCall base' "get" #[.literalStr fieldName])
    | .effect eff => lowerEffectExpr ctx eff
    | _ => .error { message := "unsupported IR expression for Quint lowering v1" }

  partial def lowerEffectExpr (ctx : LowerCtx) (eff : Effect) : Except LowerError Expr :=
    match eff with
    | .storageScalarRead stateId => .ok (ctx.stateValue stateId)
    | .storageArrayRead stateId key => do
        let key' ← lowerExpr ctx key
        .ok (.index (ctx.stateValue stateId) (irIndexToQuint key'))
    | .storageMapContains stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        .ok (mapContainsExpr key' mapExpr)
    | .storageMapGet stateId key => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        let present := mapContainsExpr key' mapExpr
        .ok (.ite present (.methodCall mapExpr "get" #[key']) hashZeroExpr)
    | .storageStructFieldRead stateId fieldName =>
        .ok (ctx.stateValue (structFieldVarName stateId fieldName))
    | .contextRead field =>
        match field with
        | .userId | .contractId | .checkpointId | .timestamp | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao =>
            .ok (.literalInt 0)
        | _ => .error { message := s!"unsupported context field for Quint lowering v1: {field.name}" }
    | _ => .error { message := "unsupported effect as expression for Quint lowering v1" }

  partial def lowerMutatingEffectBinding (ctx : LowerCtx) (eff : Effect) :
      Except LowerError (LowerCtx × Expr) :=
    match eff with
    | .storageMapInsert stateId key value
    | .storageMapSet stateId key value => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        let value' ← lowerExpr ctx value
        let present := mapContainsExpr key' mapExpr
        let old := .ite present (.methodCall mapExpr "get" #[key']) hashZeroExpr
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok ({ ctx with state := ctx.state.upsert stateId updated }, old)
    | _ => do
        let expr ← lowerEffectExpr ctx eff
        .ok (ctx, expr)

  partial def applyEffect (ctx : LowerCtx) (eff : Effect) : Except LowerError LowerCtx := do
    match eff with
    | .storageScalarWrite stateId value =>
        match value with
        | .structLit typeName fields =>
            match lookupStructDecl ctx.structs typeName with
            | some _ =>
                let mut nextCtx := ctx
                for (fieldName, fieldExpr) in fields do
                  let fieldValue ← lowerExpr nextCtx fieldExpr
                  nextCtx := { nextCtx with
                    state := nextCtx.state.upsert (structFieldVarName stateId fieldName) fieldValue }
                .ok nextCtx
            | none => .error { message := s!"unknown struct type `{typeName}` for storage write `{stateId}`" }
        | _ =>
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
    | .storageMapSet stateId key value => do
        let mapExpr := ctx.stateValue stateId
        let key' ← lowerExpr ctx key
        let value' ← lowerExpr ctx value
        let updated := .methodCall mapExpr "put" #[key', value']
        .ok { ctx with state := ctx.state.upsert stateId updated }
    | .storageStructFieldWrite stateId fieldName value => do
        let value' ← lowerExpr ctx value
        .ok { ctx with
          state := ctx.state.upsert (structFieldVarName stateId fieldName) value' }
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
        match value with
        | .effect eff =>
            let (ctx', expr) ← lowerMutatingEffectBinding ctx eff
            .ok { ctx' with locals := ctx'.locals.bind name expr }
        | _ =>
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
    | .whileLoop condition body =>
        let stateIds := expandedStateIds ctx.stateDecls ctx.structs
        let mut stepLocals : LocalEnv :=
          stateIds.foldl (fun (acc : LocalEnv) id =>
            acc.upsert (whileStepLocalName id 0) (ctx.stateValue id)) []
        let mut pureDefsAcc := ctx.pureDefs
        for id in stateIds do
          pureDefsAcc := pureDefsAcc.push {
            name := whileStepLocalName id 0,
            ret := .int,
            body := ctx.stateValue id }
        let mut guardsAcc := ctx.guards
        for step in [0:ctx.maxLoopUnroll] do
          let loopState := stateIds.foldl (fun (acc : LocalEnv) id =>
            acc.upsert id (.local (whileStepLocalName id step))) []
          let loopCtx := {
            ctx with
            locals := stepLocals,
            state := loopState,
            guards := #[],
            expandLocals := false }
          let cond ← lowerExpr loopCtx condition
          let thenCtx ← lowerStatements loopCtx body
          for id in stateIds do
            let preVal := .local (whileStepLocalName id step)
            let thenVal := match thenCtx.state.lookup id with | some v => v | none => preVal
            let binding := .ite cond thenVal preVal
            stepLocals := stepLocals.upsert (whileStepLocalName id (step + 1)) binding
            pureDefsAcc := pureDefsAcc.push {
              name := whileStepLocalName id (step + 1),
              ret := .int,
              body := binding }
          guardsAcc := guardsAcc ++ wrapBranchGuards cond false thenCtx.guards
        let finalState := stateIds.foldl (fun (acc : LocalEnv) id =>
          acc.upsert id (.local (whileStepLocalName id ctx.maxLoopUnroll))) []
        .ok { ctx with state := finalState, guards := guardsAcc, pureDefs := pureDefsAcc }
    | .return _ | .release _ =>
        .ok ctx

end

structure LoweredEntrypoint where
  action : Action
  pureDefs : Array PureDef := #[]

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

def lowerEntrypoint (ep : Entrypoint) (stateIds : Array String) (stateDecls : Array StateDecl)
    (structs : Array StructDecl) (maxLoopUnroll : Nat) : Except LowerError LoweredEntrypoint := do
  let params ← ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t))
  let ctx ← lowerStatements {
    stateDecls := stateDecls,
    structs := structs,
    maxLoopUnroll := maxLoopUnroll } ep.body
  let clauses := ctxToActionClauses ctx
  let assigned := clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  let identityClauses := stateIds.filterMap (fun id =>
    if assigned.contains id then none else some (.assign (.prime (.local id)) (.local id)))
  let body := ActionClause.all (clauses ++ identityClauses)
  pure {
    action := {
      name := sanitizeName ep.name,
      params := params,
      ret? := some .bool,
      body := body },
    pureDefs := ctx.pureDefs
  }

def zeroExpr (t : ValueType) : Except LowerError Expr :=
  match t with
  | .bool => .ok (.literalBool false)
  | .u8 | .u32 | .u64 | .u128 | .unit => .ok (.literalInt 0)
  | .address => .ok (.literalStr "")
  | .hash => .ok hashZeroExpr
  | .fixedArray _ _ | .array _ => .ok (.listLit #[])
  | .structType _ => .ok (.mapLit #[])
  | .bytes | .string =>
      .error { message := s!"cannot zero-initialize type for Quint: {t.name}" }

def zeroExprForState (s : StateDecl) (structs : Array StructDecl) : Except LowerError (Array (String × Expr)) := do
  match s.kind with
  | .array cap =>
      let z ← zeroExpr s.type
      .ok #[(s.id, .listLit (Array.replicate cap z))]
  | .map _ _ =>
      .ok #[(s.id, emptyMapExpr)]
  | .scalar | .dynamicArray =>
      match s.type with
      | .structType typeName =>
          match lookupStructDecl structs typeName with
          | some structDecl => do
              let mut entries := #[]
              for field in structDecl.fields do
                entries := entries.push (structFieldVarName s.id field.id, ← zeroExpr field.type)
              .ok entries
          | none =>
              let z ← zeroExpr s.type
              .ok #[(s.id, z)]
      | _ =>
          let z ← zeroExpr s.type
          .ok #[(s.id, z)]

def initAction (state : Array StateDecl) (structs : Array StructDecl) : Except LowerError Action := do
  let mut clauses := #[]
  for decl in state do
    let zeros ← zeroExprForState decl structs
    for (name, value) in zeros do
      clauses := clauses.push (.assign (.prime (.local name)) value)
  pure {
    name := "init",
    body := ActionClause.all clauses,
    ret? := none
  }

def hashKeySamples : Array Expr := #[
  .literalStr "hash:1001:0:0:0",
  .literalStr "hash:2002:0:0:0",
  .literalStr "hash:3003:0:0:0"
]

def paramDomainExpr (t : QuintType) : Expr :=
  match t with
  | .str => .oneOf (.local "USERS")
  | .hashStr => .oneOf (.setLit hashKeySamples)
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
  let stateVarPairs ← quintStateVars module.state module.structs
  let vars := stateVarPairs.map (fun (name, type) => { name, type })
  let init ← initAction module.state module.structs
  let stateIds := expandedStateIds module.state module.structs
  let loweredEps ← module.entrypoints.mapM (fun ep =>
    lowerEntrypoint ep stateIds module.state module.structs scenario.maxLoopUnroll)
  let epActions := loweredEps.map (·.action)
  let whilePureDefs := loweredEps.foldl (fun acc ep => acc ++ ep.pureDefs) #[]
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
    pureDefs := scenario.quintPureDefs ++ whilePureDefs,
    actions := #[init] ++ epActions ++ #[step],
    vals := vals
  }

def renderModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError String := do
  let qm ← lowerModule module scenario
  pure (Emit.emitModule qm)

end ProofForge.Backend.Quint.Lower