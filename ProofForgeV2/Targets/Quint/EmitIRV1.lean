import ProofForgeV2.Targets.Quint.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Quint EmitIRV1 — Plan → structured IR AST → `.qnt` source

IR is a structured Quint 0.32 AST (not String/JSON). The renderer is the sole
producer of `text/x-quint` bytes. Failure actions stutter business state and
record first-failure instrumentation codes.
-/

namespace ProofForgeV2.Targets.Quint

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .quint message

-- ---------------------------------------------------------------------------
-- Structured Quint 0.32 IR AST
-- ---------------------------------------------------------------------------

inductive QBinOp where
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or
  deriving BEq, Inhabited, Repr

inductive QUnaryOp where
  | not
  deriving BEq, Inhabited, Repr

inductive QExpr where
  | name (id : String)
  | intLit (value : String)
  | boolLit (value : Bool)
  | binary (op : QBinOp) (lhs rhs : QExpr)
  | unary (op : QUnaryOp) (operand : QExpr)
  | call (callee : String) (args : Array QExpr)
  | ifThenElse (cond thenE elseE : QExpr)
  | primed (id : String)
  deriving BEq, Inhabited, Repr

/-- One local value binding inside an action block (`val x = e`).
    It may read pre-state variables; `pure val` would be rejected by Quint. -/
structure QPureBind where
  name : String
  value : QExpr
  deriving BEq, Inhabited, Repr

/-- One nondet binding (`nondet x = oneOf(...)`). -/
structure QNondetBind where
  name : String
  domain : QExpr
  deriving BEq, Inhabited, Repr

/-- Assignment in `all { x' = e, ... }`. -/
structure QAssign where
  target : String
  value : QExpr
  deriving BEq, Inhabited, Repr

/-- One alternative of `action step = any { ... }`. -/
structure QActionBranch where
  nondets : Array QNondetBind
  pures : Array QPureBind
  assigns : Array QAssign
  deriving BEq, Inhabited, Repr

inductive QDecl where
  /-- `pure def PF_MAX_U64: int = ...` -/
  | pureConst (name : String) (ty : String) (value : QExpr)
  /-- `var name: ty` -/
  | varDecl (name : String) (ty : String)
  /-- `pure def name(params): ty = body` or nullary without params -/
  | pureDef (name : String) (params : Array (String × String))
      (retTy : String) (body : QExpr)
  /-- `val name = body` (invariant observation; no instrumentation) -/
  | valDecl (name : String) (body : QExpr)
  /-- `action init = { ... }` single branch -/
  | actionInit (branch : QActionBranch)
  /-- `action step = any { ... }` -/
  | actionStep (branches : Array QActionBranch)
  deriving BEq, Inhabited, Repr

structure QModule where
  name : String
  headerComment : String
  decls : Array QDecl
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  module_ : QModule
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Plan Expr → QExpr
-- ---------------------------------------------------------------------------

private def maxU64Lit : String := "18446744073709551615"

private def emittedModuleName (sourceName : String) : String :=
  "PFModel_" ++ sourceName

private def emittedStateName (sourceName : String) : String :=
  "pf_state_" ++ sourceName

private def emittedViewName (sourceName : String) : String :=
  "pf_view_" ++ sourceName

private def emittedInvariantName (sourceName : String) : String :=
  "pf_invariant_" ++ sourceName

private def entryParamName (actionIndex paramIndex : Nat) : String :=
  s!"pf_arg_a{actionIndex}_{paramIndex}"

private def initParamName (paramIndex : Nat) : String :=
  s!"pf_init_arg{paramIndex}"

private def u64Lit (v : UInt64) : QExpr :=
  .intLit (toString v.toNat)

private def stateVar (plan : Plan) (fieldIndex : Nat) : CompileResult String := do
  match plan.states[fieldIndex]? with
  | some st => pure (emittedStateName st.name)
  | none => planError "Quint IR state field index out of range"

private def paramVar (params : Array String) (index : Nat) : CompileResult String := do
  match params[index]? with
  | some n => pure n
  | none => planError "Quint IR parameter index out of range"

/-- Render Plan Expr against a parameter name table and state names.
    State loads read the pre-action business var (or overlay pure name when
    provided via `overlayNames`). -/
private partial def lowerExpr
    (plan : Plan) (params : Array String)
    (overlayNames : Array (Nat × String))
    (e : Expr) : CompileResult QExpr := do
  match e with
  | .litU64 v => pure (u64Lit v)
  | .litBool b => pure (.boolLit b)
  | .param i => do
      let n ← paramVar params i
      pure (.name n)
  | .stateLoad fi => do
      match overlayNames.findSome? (fun (idx, n) => if idx == fi then some n else none) with
      | some n => pure (.name n)
      | none => do
          let n ← stateVar plan fi
          pure (.name n)
  | .arith op l r => do
      let ql ← lowerExpr plan params overlayNames l
      let qr ← lowerExpr plan params overlayNames r
      let qop : QBinOp :=
        match op with
        | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
      -- Guard div/mod by zero so failed actions still evaluate.
      match op with
      | .div | .mod =>
          pure (.ifThenElse
            (.binary .ne qr (u64Lit 0))
            (.binary qop ql qr)
            (u64Lit 0))
      | _ => pure (.binary qop ql qr)
  | .compare op l r => do
      let ql ← lowerExpr plan params overlayNames l
      let qr ← lowerExpr plan params overlayNames r
      let qop : QBinOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
      pure (.binary qop ql qr)
  | .boolAnd l r => do
      let ql ← lowerExpr plan params overlayNames l
      let qr ← lowerExpr plan params overlayNames r
      pure (.binary .and ql qr)
  | .boolOr l r => do
      let ql ← lowerExpr plan params overlayNames l
      let qr ← lowerExpr plan params overlayNames r
      pure (.binary .or ql qr)
  | .boolNot o => do
      let qo ← lowerExpr plan params overlayNames o
      pure (.unary .not qo)

private def pfMaxRef : QExpr := .name "PF_MAX_U64"

private def u64Domain : QExpr :=
  .call "oneOf" #[.call "to" #[.intLit "0", pfMaxRef]]

/-- Rewrite overflow/underflow conditions that compare against max U64 literal
    to use `PF_MAX_U64` for the exact product spelling. -/
private partial def rewriteMaxBound : QExpr → QExpr
  | .intLit s =>
      if s == maxU64Lit then pfMaxRef else .intLit s
  | .binary op l r => .binary op (rewriteMaxBound l) (rewriteMaxBound r)
  | .unary op o => .unary op (rewriteMaxBound o)
  | .call c args => .call c (args.map rewriteMaxBound)
  | .ifThenElse c t e =>
      .ifThenElse (rewriteMaxBound c) (rewriteMaxBound t) (rewriteMaxBound e)
  | other => other

private def freshPure (pfx : String) (n : Nat) : String :=
  s!"{pfx}{n}"

/-- Build first-failure pure cascade: `success`, `failure` pure names. -/
private def emitCheckCascade
    (plan : Plan) (params : Array String)
    (checks : Array Check) (pures0 : Array QPureBind) (counter0 : Nat) :
    CompileResult (Array QPureBind × Nat × String × String) := do
  let mut pures := pures0
  let mut counter := counter0
  let mut ckNames : Array String := #[]
  let mut codes : Array Nat := #[]
  for ck in checks do
    let qe ← lowerExpr plan params #[] ck.condition
    let qe := rewriteMaxBound qe
    let nm := freshPure "ck" counter
    counter := counter + 1
    pures := pures.push { name := nm, value := qe }
    ckNames := ckNames.push nm
    codes := codes.push ck.kind.code
  -- success = ck0 and ck1 and ...
  let successName := freshPure "ok" counter
  counter := counter + 1
  let successExpr : QExpr :=
    if ckNames.isEmpty then .boolLit true
    else Id.run do
      let some head := ckNames[0]? | pure (.boolLit true)
      let mut acc : QExpr := .name head
      for i in [1:ckNames.size] do
        match ckNames[i]? with
        | some n => acc := .binary .and acc (.name n)
        | none => pure ()
      pure acc
  pures := pures.push { name := successName, value := successExpr }
  -- failure = if (not ck0) code0 else if (not ck1) code1 else 0
  let failureName := freshPure "fail" counter
  counter := counter + 1
  let failureExpr : QExpr := Id.run do
    let mut acc : QExpr := .intLit "0"
    let n := ckNames.size
    for i in [0:n] do
      let j := n - 1 - i
      match ckNames[j]?, codes[j]? with
      | some nm, some code =>
          acc := .ifThenElse
            (.unary .not (.name nm))
            (.intLit (toString code))
            acc
      | _, _ => pure ()
    pure acc
  pures := pures.push { name := failureName, value := failureExpr }
  pure (pures, counter, successName, failureName)

private def lastArgName (entryName : String) (i : Nat) : String :=
  s!"pf_last_{entryName}_arg{i}"

private def lastResultName (entryName : String) : String :=
  s!"pf_last_{entryName}_result"

private def emitEntryBranch (plan : Plan) (ent : PlanEntry) :
    CompileResult QActionBranch := do
  let mut emittedParams : Array String := #[]
  let mut nondets : Array QNondetBind := #[]
  for i in [0:ent.params.size] do
    let name := entryParamName ent.actionIndex i
    emittedParams := emittedParams.push name
    nondets := nondets.push { name, domain := u64Domain }
  let (pures, _c, successName, failureName) ←
    emitCheckCascade plan emittedParams ent.checks #[] 0
  let mut pures := pures
  -- Optional result pure
  let resultPure? ← match ent.result? with
    | none => pure (none : Option String)
    | some e => do
        let qe ← lowerExpr plan emittedParams #[] e
        let qe := rewriteMaxBound qe
        pures := pures.push { name := "resR", value := qe }
        pure (some "resR")
  -- Assignments: instrumentation + business state
  let mut assigns : Array QAssign := #[]
  assigns := assigns.push {
    target := "pf_last_action"
    value := .intLit (toString ent.actionIndex)
  }
  assigns := assigns.push {
    target := "pf_last_ok"
    value := .name successName
  }
  assigns := assigns.push {
    target := "pf_last_failure"
    value := .name failureName
  }
  -- Instrumentation: update this entry's last args; stutter every other entry's
  -- last-arg/result vars so each action assigns the full instrumentation set.
  for other in plan.entries do
    if other.name == ent.name then
      for i in [0:emittedParams.size] do
        match emittedParams[i]? with
        | some p =>
            assigns := assigns.push {
              target := lastArgName ent.name i
              value := .name p
            }
        | none => pure ()
      match ent.resultKind, resultPure? with
      | .unit, _ => pure ()
      | .uint64, some rn | .bool, some rn =>
          assigns := assigns.push {
            target := lastResultName ent.name
            value := .ifThenElse (.name successName) (.name rn)
              (.name (lastResultName ent.name))
          }
      | .uint64, none | .bool, none =>
          assigns := assigns.push {
            target := lastResultName ent.name
            value := .name (lastResultName ent.name)
          }
    else
      for i in [0:other.params.size] do
        assigns := assigns.push {
          target := lastArgName other.name i
          value := .name (lastArgName other.name i)
        }
      match other.resultKind with
      | .unit => pure ()
      | .uint64 | .bool =>
          assigns := assigns.push {
            target := lastResultName other.name
            value := .name (lastResultName other.name)
          }
  -- Business state: success → post store / identity; failure → pre-state stutter
  let mut written : Array Nat := #[]
  for (fi, e) in ent.stores do
    written := written.push fi
    let post ← lowerExpr plan emittedParams #[] e
    let post := rewriteMaxBound post
    let sn ← stateVar plan fi
    assigns := assigns.push {
      target := sn
      value := .ifThenElse (.name successName) post (.name sn)
    }
  for i in [0:plan.states.size] do
    unless written.contains i do
      let sn ← stateVar plan i
      assigns := assigns.push {
        target := sn
        value := .name sn
      }
  pure { nondets, pures, assigns }

private def emitInitBranch (plan : Plan) (init : PlanInit) :
    CompileResult QActionBranch := do
  let mut emittedParams : Array String := #[]
  let mut nondets : Array QNondetBind := #[]
  for i in [0:init.params.size] do
    let name := initParamName i
    emittedParams := emittedParams.push name
    nondets := nondets.push { name, domain := u64Domain }
  let mut assigns : Array QAssign := #[]
  assigns := assigns.push {
    target := "pf_last_action"
    value := .intLit "0"
  }
  assigns := assigns.push {
    target := "pf_last_ok"
    value := .boolLit true
  }
  assigns := assigns.push {
    target := "pf_last_failure"
    value := .intLit "0"
  }
  let mut written : Array Nat := #[]
  for (fi, e) in init.stores do
    written := written.push fi
    let post ← lowerExpr plan emittedParams #[] e
    let sn ← stateVar plan fi
    assigns := assigns.push { target := sn, value := post }
  for i in [0:plan.states.size] do
    unless written.contains i do
      let sn ← stateVar plan i
      -- Unwritten init fields: leave as primed identity is illegal without
      -- prior value; init must set every field or default 0.
      assigns := assigns.push { target := sn, value := .intLit "0" }
  -- Stutter entry instrumentation args/results (identity if vars exist)
  for ent in plan.entries do
    for i in [0:ent.params.size] do
      assigns := assigns.push {
        target := lastArgName ent.name i
        value := .intLit "0"
      }
    match ent.resultKind with
    | .unit => pure ()
    | .uint64 =>
        assigns := assigns.push {
          target := lastResultName ent.name
          value := .intLit "0"
        }
    | .bool =>
        assigns := assigns.push {
          target := lastResultName ent.name
          value := .boolLit false
        }
  pure { nondets, pures := #[], assigns }

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let mut decls : Array QDecl := #[]
  decls := decls.push <| .pureConst "PF_MAX_U64" "int" (.intLit maxU64Lit)
  -- Business state vars use a target-owned namespace, so source state names
  -- cannot collide with Quint built-ins, view names, or instrumentation.
  for st in plan.states do
    decls := decls.push (.varDecl (emittedStateName st.name) "int")
  -- Instrumentation vars
  decls := decls.push (.varDecl "pf_last_action" "int")
  decls := decls.push (.varDecl "pf_last_ok" "bool")
  decls := decls.push (.varDecl "pf_last_failure" "int")
  for ent in plan.entries do
    for i in [0:ent.params.size] do
      decls := decls.push (.varDecl (lastArgName ent.name i) "int")
    match ent.resultKind with
    | .unit => pure ()
    | .uint64 =>
        decls := decls.push (.varDecl (lastResultName ent.name) "int")
    | .bool =>
        decls := decls.push (.varDecl (lastResultName ent.name) "bool")
  -- Views as pure defs under a target-owned namespace. Parameters are indexed
  -- target names so source shadowing cannot capture a business state variable.
  let mut viewIndex : Nat := 0
  for v in plan.views do
    let mut emittedParams : Array String := #[]
    for i in [0:v.params.size] do
      emittedParams := emittedParams.push s!"pf_view_arg_{viewIndex}_{i}"
    let body ← lowerExpr plan emittedParams #[] v.value
    let params := emittedParams.map (fun n => (n, "int"))
    let ret := match v.resultKind with
      | .bool => "bool"
      | _ => "int"
    decls := decls.push (.pureDef (emittedViewName v.name) params ret body)
    viewIndex := viewIndex + 1
  -- Invariants as val (business state only)
  for inv in plan.invariants do
    let mut body ← lowerExpr plan #[] #[] inv.value
    -- AND all check conditions (success conditions)
    for ck in inv.checks do
      let c ← lowerExpr plan #[] #[] ck.condition
      body := .binary .and c body
    body := rewriteMaxBound body
    decls := decls.push (.valDecl (emittedInvariantName inv.name) body)
  -- init action
  match plan.initializer with
  | some init => do
      let br ← emitInitBranch plan init
      decls := decls.push (.actionInit br)
  | none => do
      -- Synthetic empty init that only zeros instrumentation + state defaults.
      let br ← emitInitBranch plan {
        name := "initialize"
        params := #[]
        stores := #[]
      }
      decls := decls.push (.actionInit br)
  -- step action: one branch per entry
  let mut branches : Array QActionBranch := #[]
  for ent in plan.entries do
    let br ← emitEntryBranch plan ent
    branches := branches.push br
  unless branches.size > 0 do
    planError "Quint IR requires at least one entry branch"
  decls := decls.push (.actionStep branches)
  let module_ : QModule := {
    -- Module identity is target-owned so a source program name can never
    -- collide with a current or future Quint keyword/builtin.
    name := emittedModuleName plan.programName
    headerComment :=
      "// Generated by proof-forge-next (Quint target, " ++ emitterSyntaxNote ++ ").\n" ++
      "// Source-only Quint 0.32 model; product materialization invokes no Quint CLI / Apalache / TLC."
    decls
  }
  pure { sourcePlan := plan, module_ }

-- ---------------------------------------------------------------------------
-- Renderer
-- ---------------------------------------------------------------------------

private def binOpSym : QBinOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .and => "and"
  | .or => "or"

private def binOpPrecedence : QBinOp → Nat
  | .or => 10
  | .and => 20
  | .eq | .ne => 30
  | .lt | .le | .gt | .ge => 40
  | .add | .sub => 50
  | .mul | .div | .mod => 60

private def wrapExpr (requested own : Nat) (rendered : String) : String :=
  if own < requested then "(" ++ rendered ++ ")" else rendered

/-- Precedence-aware Quint renderer. In particular, root `if` and `not`
    expressions must not acquire the redundant parentheses rejected by the
    Quint 0.32 parser. -/
private partial def renderExprPrec (requested : Nat) : QExpr → String
  | .name id => id
  | .intLit v => v
  | .boolLit true => "true"
  | .boolLit false => "false"
  | .binary op l r =>
      let own := binOpPrecedence op
      wrapExpr requested own
        s!"{renderExprPrec own l} {binOpSym op} {renderExprPrec (own + 1) r}"
  | .unary .not o =>
      wrapExpr requested 80 s!"not({renderExprPrec 0 o})"
  | .call "to" args =>
      -- special-case `0.to(PF_MAX_U64)` method form
      match args[0]?, args[1]? with
      | some a, some b =>
          wrapExpr requested 80
            s!"{renderExprPrec 81 a}.to({renderExprPrec 0 b})"
      | _, _ =>
          let argStr := String.intercalate ", "
            (args.map (renderExprPrec 0)).toList
          wrapExpr requested 80 s!"to({argStr})"
  | .call callee args =>
      let argStr := String.intercalate ", "
        (args.map (renderExprPrec 0)).toList
      wrapExpr requested 80 s!"{callee}({argStr})"
  | .ifThenElse c t e =>
      wrapExpr requested 5
        s!"if ({renderExprPrec 0 c}) {renderExprPrec 0 t} else {renderExprPrec 0 e}"
  | .primed id => wrapExpr requested 80 s!"{id}'"

private def renderExpr (expr : QExpr) : String :=
  renderExprPrec 0 expr

private def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

private def renderBranch (level : Nat) (br : QActionBranch) : Array String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push (indent level "{")
  for nd in br.nondets do
    lines := lines.push
      (indent (level + 2) s!"nondet {nd.name} = {renderExpr nd.domain}")
  for p in br.pures do
    lines := lines.push
      (indent (level + 2) s!"val {p.name} = {renderExpr p.value}")
  lines := lines.push (indent (level + 2) "all {")
  for a in br.assigns do
    lines := lines.push
      (indent (level + 4) s!"{a.target}' = {renderExpr a.value},")
  lines := lines.push (indent (level + 2) "}")
  lines := lines.push (indent level "}")
  pure lines

private def renderDecl (d : QDecl) : Array String :=
  match d with
  | .pureConst name ty value =>
      #[s!"  pure def {name}: {ty} = {renderExpr value}"]
  | .varDecl name ty =>
      #[s!"  var {name}: {ty}"]
  | .pureDef name params retTy body =>
      if params.isEmpty then
        #[s!"  pure def {name}: {retTy} = {renderExpr body}"]
      else
        let ps := String.intercalate ", "
          (params.map (fun (n, t) => s!"{n}: {t}")).toList
        #[s!"  pure def {name}({ps}): {retTy} = {renderExpr body}"]
  | .valDecl name body =>
      #[s!"  val {name} = {renderExpr body}"]
  | .actionInit br => Id.run do
      let mut lines : Array String := #["  action init = {"]
      for nd in br.nondets do
        lines := lines.push
          (indent 4 s!"nondet {nd.name} = {renderExpr nd.domain}")
      for p in br.pures do
        lines := lines.push
          (indent 4 s!"val {p.name} = {renderExpr p.value}")
      lines := lines.push (indent 4 "all {")
      for a in br.assigns do
        lines := lines.push
          (indent 6 s!"{a.target}' = {renderExpr a.value},")
      lines := lines.push (indent 4 "}")
      lines := lines.push "  }"
      pure lines
  | .actionStep branches => Id.run do
      let mut lines : Array String := #["  action step = any {"]
      for i in [0:branches.size] do
        match branches[i]? with
        | some br =>
            lines := lines ++ renderBranch 4 br
            if i + 1 < branches.size then
              lines := lines.push (indent 4 ",")
        | none => pure ()
      lines := lines.push "  }"
      pure lines

private def renderModule (m : QModule) : String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push m.headerComment
  lines := lines.push s!"module {m.name} \{"
  for d in m.decls do
    lines := lines.push ""
    lines := lines ++ renderDecl d
  lines := lines.push "}"
  lines := lines.push ""
  pure (String.intercalate "\n" lines.toList)

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderModule ir.module_
  pure #[{
    path := s!"{ir.sourcePlan.programName}.qnt"
    mediaType := "text/x-quint"
    contents := source
  }]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless isAsciiIdentifier 240 ir.module_.name do
    planError "Quint IR module name is not a safe identifier"
  pure ()

/-- Capability-gated public IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  validateIR ir
  emitFromIR ir

/-- Unit-test IR entry over retained SemanticProgramV1. -/
def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  let plan ← planFromCompiledSemanticV1 compiled
  validatePlan plan
  lower plan

/-- Unit-test materialize entry. -/
def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCompiledSemanticV1 compiled
  validateIR ir
  emitFromIR ir

end ProofForgeV2.Targets.Quint
