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
def reservedNames : List String := [
  "action", "all", "and", "any", "bool", "const", "def", "else", "false",
  "get", "if", "int", "list", "map", "module", "nondet", "not", "oneOf",
  "or", "pure", "set", "step", "str", "true", "val", "var"
]

def sanitizeName (name : String) : String :=
  if reservedNames.contains name then name ++ "_" else name

abbrev LocalEnv := List (String × Expr)

def LocalEnv.lookup (name : String) (env : LocalEnv) : Option Expr :=
  match env with
  | [] => none
  | (k, v) :: rest =>
      if k == name then some v else LocalEnv.lookup name rest

def LocalEnv.bind (name : String) (value : Expr) (env : LocalEnv) : LocalEnv :=
  (name, value) :: env

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
  partial def lowerExpr (env : LocalEnv) (e : ProofForge.IR.Expr) : Except LowerError Expr := do
    match e with
    | .literal lit => lowerLiteral lit
    | .local name =>
        match env.lookup name with
        | some expr => .ok expr
        | none => .ok (.local name)
    | .add lhs rhs => .ok (.binOp .add (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .sub lhs rhs =>
        -- IR semantics uses Nat subtraction (clamps to 0), so mirror that in Quint.
        let l ← lowerExpr env lhs
        let r ← lowerExpr env rhs
        .ok (.ite (.binOp .ge l r) (.binOp .sub l r) (.literalInt 0))
    | .mul lhs rhs => .ok (.binOp .mul (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .div lhs rhs =>
        -- IR semantics returns 0 on division by zero.
        let l ← lowerExpr env lhs
        let r ← lowerExpr env rhs
        .ok (.ite (.binOp .eq r (.literalInt 0)) (.literalInt 0) (.binOp .div l r))
    | .mod lhs rhs => .ok (.binOp .mod (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .eq lhs rhs => .ok (.binOp .eq (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .ne lhs rhs => .ok (.binOp .ne (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .lt lhs rhs => .ok (.binOp .lt (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .le lhs rhs => .ok (.binOp .le (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .gt lhs rhs => .ok (.binOp .gt (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .ge lhs rhs => .ok (.binOp .ge (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .boolAnd lhs rhs => .ok (.binOp .and (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .boolOr lhs rhs => .ok (.binOp .or (← lowerExpr env lhs) (← lowerExpr env rhs))
    | .boolNot value => .ok (.unOp .not (← lowerExpr env value))
    | .cast value _ => lowerExpr env value
    | .effect eff => lowerEffectExpr env eff
    | _ => .error { message := "unsupported IR expression for Quint lowering v1" }

  partial def lowerEffectExpr (env : LocalEnv) (eff : Effect) : Except LowerError Expr :=
    match eff with
    | .storageScalarRead stateId => .ok (.local stateId)
    | .contextRead field =>
        -- Phase 3 v1: the executable IR semantics returns a fixed U64(0) for
        -- all block/caller context fields. Mirror that in the model so MBT
        -- traces replay without mismatch.
        match field with
        | .userId | .contractId | .checkpointId | .timestamp | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao =>
            .ok (.literalInt 0)
        | _ => .error { message := s!"unsupported context field for Quint lowering v1: {field.name}" }
    | _ => .error { message := "unsupported effect as expression for Quint lowering v1" }

  partial def lowerEffectStmt (env : LocalEnv) (eff : Effect) : Except LowerError (Option ActionClause) := do
    match eff with
    | .storageScalarWrite stateId value =>
        .ok (some (.assign (.prime (.local stateId)) (← lowerExpr env value)))
    | .storageScalarAssignOp stateId op value =>
        let qop := lowerAssignOp op
        .ok (some (.assign (.prime (.local stateId))
          (.binOp qop (.local stateId) (← lowerExpr env value))))
    | .eventEmit _ _ =>
        -- Events are no-ops in the generated model for v1. Keep a `true`
        -- guard so event-only actions still produce valid (non-empty) `all` blocks.
        .ok (some (.guard (.literalBool true)))
    | _ => .error { message := "unsupported effect statement for Quint lowering v1" }

  partial def lowerStatement (env : LocalEnv) (s : Statement) : Except LowerError (LocalEnv × Option ActionClause) := do
    match s with
    | .letBind name _ value =>
        .ok (env.bind name (← lowerExpr env value), none)
    | .letMutBind name _ value =>
        .ok (env.bind name (← lowerExpr env value), none)
    | .assign _ _ =>
        .error { message := "local assignment not supported in Quint lowering v1" }
    | .assignOp _ _ _ =>
        .error { message := "compound local assignment not supported in Quint lowering v1" }
    | .effect eff =>
        .ok (env, ← lowerEffectStmt env eff)
    | .assert condition _ _ =>
        .ok (env, some (.guard (← lowerExpr env condition)))
    | .assertEq lhs rhs _ _ =>
        .ok (env, some (.guard (.binOp .eq (← lowerExpr env lhs) (← lowerExpr env rhs))))
    | .revert _ | .revertWithError _ =>
        .ok (env, some (.guard (.literalBool false)))
    | .ifElse _ _ _ =>
        .error { message := "if/else not supported in Quint lowering v1" }
    | .boundedFor _ _ _ _ =>
        .error { message := "boundedFor not supported in Quint lowering v1" }
    | .whileLoop _ _ =>
        .error { message := "whileLoop not supported in Quint lowering v1" }
    | .return _ =>
        .ok (env, none)
    | .release _ =>
        .ok (env, none)
end

partial def assignedStateVars (clause : ActionClause) : List String :=
  match clause with
  | .assign (.prime (.local name)) _ => [name]
  | .all clauses | .any clauses =>
      clauses.foldl (fun acc c => acc ++ assignedStateVars c) []
  | .nondet _ _ body => assignedStateVars body
  | _ => []

def lowerEntrypoint (ep : Entrypoint) (stateIds : Array String) : Except LowerError Action := do
  let params ← ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t))
  let (_env, clauses) ← ep.body.foldlM (fun (env, acc) stmt => do
    let (env', clause?) ← lowerStatement env stmt
    pure (env', match clause? with | some c => acc.push c | none => acc)) ([], #[])
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

def initAction (state : Array StateDecl) : Except LowerError Action := do
  let clauses ← state.mapM (fun s => do
    pure (.assign (.prime (.local s.id)) (← zeroExpr s.type)))
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
    pure { name := s.id, type := ← lowerType s.type })
  let init ← initAction module.state
  let stateIds := module.state.map (fun s => s.id)
  let epActions ← module.entrypoints.mapM (fun ep => lowerEntrypoint ep stateIds)
  let epParams ← module.entrypoints.mapM (fun ep => do
    ep.params.mapM (fun (n, t) => do pure (n, ← lowerType t)))
  let step := stepAction module.entrypoints epParams
  pure {
    name := s!"{module.name}Model",
    constants := #[],
    vars := vars,
    pureDefs := scenario.quintPureDefs,
    actions := #[init] ++ epActions ++ #[step],
    vals := Invariants.derive module
  }

def renderModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except LowerError String := do
  let qm ← lowerModule module scenario
  pure (Emit.emitModule qm)

end ProofForge.Backend.Quint.Lower
