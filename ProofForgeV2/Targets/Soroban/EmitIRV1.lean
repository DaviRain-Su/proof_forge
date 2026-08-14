import ProofForgeV2.Targets.Soroban.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Soroban EmitIRV1 — Plan → structured IR AST → `.rs` Rust source

IR is a structured Soroban Rust AST (not String). The renderer is the sole
producer of `text/x-rust` bytes. Soroban S0 source recipe; not a deployable
Wasm claim; zero-tool finalize.
-/

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .soroban message

-- ---------------------------------------------------------------------------
-- Structured Soroban Rust IR AST
-- ---------------------------------------------------------------------------

inductive RBinOp where
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or
  deriving BEq, Inhabited, Repr

inductive RUnaryOp where
  | not
  deriving BEq, Inhabited, Repr

inductive RExpr where
  | name (id : String)
  | u64Lit (value : String)
  | boolLit (value : Bool)
  | binary (op : RBinOp) (lhs rhs : RExpr)
  | unary (op : RUnaryOp) (operand : RExpr)
  | checkedArith (method : String) (receiver arg : RExpr) (panicMsg : String)
  | storageGet (key : String)
  | storageSet (key : String) (value : RExpr)
  | ifExpr (cond thenE elseE : RExpr)
  | panic (msg : String)
  | unit
  deriving BEq, Inhabited, Repr

inductive RStatement where
  | letBind (name : String) (value : RExpr)
  | expr (value : RExpr)
  | returnExpr (value : RExpr)
  deriving BEq, Inhabited, Repr

structure RFn where
  name : String
  params : Array (String × String)
  returnType : Option String
  body : Array RStatement
  deriving BEq, Inhabited, Repr

structure RContract where
  contractName : String
  fns : Array RFn
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  contract : RContract
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Plan Expr → RExpr
-- ---------------------------------------------------------------------------

private def stateKey (plan : Plan) (fieldIndex : Nat) : CompileResult String := do
  match plan.states[fieldIndex]? with
  | some st =>
      let key := st.name
      if key.toUTF8.size ≤ 9 then
        pure key
      else
        pure ((key.take 9).toString)
  | none => planError "Soroban IR state field index out of range"

private def paramName (_params : Array String) (index : Nat) : CompileResult String := do
  match _params[index]? with
  | some n => pure n
  | none => planError "Soroban IR parameter index out of range"

private partial def lowerExpr
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (e : Expr) : CompileResult RExpr := do
  match e with
  | .litU64 v => pure (.u64Lit (toString v.toNat))
  | .litBool b => pure (.boolLit b)
  | .param i => do
      let n ← paramName params i
      pure (.name n)
  | .stateLoad fi => do
      match stateLocals[fi]? with
      | some n => pure (.name n)
      | none => do
          let key ← stateKey plan fi
          pure (.storageGet key)
  | .arith op l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      match op with
      | .add => pure (.checkedArith "checked_add" rl rr "overflow")
      | .sub => pure (.checkedArith "checked_sub" rl rr "underflow")
      | .mul => pure (.checkedArith "checked_mul" rl rr "overflow")
      | .div =>
          pure (.ifExpr
            (.binary .ne rr (.u64Lit "0"))
            (.binary .div rl rr)
            (.panic "division by zero"))
      | .mod =>
          pure (.ifExpr
            (.binary .ne rr (.u64Lit "0"))
            (.binary .mod rl rr)
            (.panic "division by zero"))
  | .compare op l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      let rop : RBinOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
      pure (.binary rop rl rr)
  | .boolAnd l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      pure (.binary .and rl rr)
  | .boolOr l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      pure (.binary .or rl rr)
  | .boolNot o => do
      let ro ← lowerExpr plan params stateLocals o
      pure (.unary .not ro)

private def emitAssertChecks
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (checks : Array Check) :
    CompileResult (Array RStatement) := do
  let mut stmts : Array RStatement := #[]
  for ck in checks do
    -- Overflow/underflow/divZero are already enforced by checked_* / guarded
    -- arith in store/result lowering; skip redundant condition re-evaluation.
    match ck.kind with
    | .overflow | .underflow | .divByZero => pure ()
    | .assertion | .declaredRevert _ | .terminalRevert _ => do
        let cond ← lowerExpr plan params stateLocals ck.condition
        let msg := match ck.kind with
          | .assertion => "assertion failed"
          | .declaredRevert idx => s!"revert({idx})"
          | .terminalRevert idx => s!"revert({idx})"
          | _ => "failure"
        stmts := stmts.push (.expr (.ifExpr (.unary .not cond) (.panic msg) .unit))
  pure stmts

private def emitStores
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (stores : Array (Nat × Expr)) :
    CompileResult (Array RStatement) := do
  let mut stmts : Array RStatement := #[]
  for (fi, e) in stores do
    let key ← stateKey plan fi
    let re ← lowerExpr plan params stateLocals e
    stmts := stmts.push (.expr (.storageSet key re))
  pure stmts

private def resultTypeStr : ResultKind → Option String
  | .unit => none
  | .uint64 => some "u64"
  | .bool => some "bool"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let mut fns : Array RFn := #[]
  -- Initializer
  match plan.initializer with
  | some init => do
      let mut fnParams : Array (String × String) := #[("env", "Env")]
      for p in init.params do
        fnParams := fnParams.push (p, "u64")
      let storeStmts ← emitStores plan init.params #[] init.stores
      fns := fns.push {
        name := "init"
        params := fnParams
        returnType := none
        body := storeStmts
      }
  | none => pure ()
  -- Entries
  for ent in plan.entries do
    let mut fnParams : Array (String × String) := #[("env", "Env")]
    for p in ent.params do
      fnParams := fnParams.push (p, "u64")
    let mut body : Array RStatement := #[]
    -- Load pre-state into locals so Plan stateLoad nodes stay snapshot-stable
    -- across subsequent stores (single-block overlay honesty).
    let mut stateLocals : Array String := #[]
    for i in [0:plan.states.size] do
      match plan.states[i]? with
      | some st => do
          let key ← stateKey plan i
          let localName := s!"st_{st.name}"
          body := body.push (.letBind localName (.storageGet key))
          stateLocals := stateLocals.push localName
      | none => pure ()
    let checkStmts ← emitAssertChecks plan ent.params stateLocals ent.checks
    body := body ++ checkStmts
    let storeStmts ← emitStores plan ent.params stateLocals ent.stores
    body := body ++ storeStmts
    match ent.resultKind, ent.result? with
    | .unit, _ => pure ()
    | .uint64, some e | .bool, some e => do
        let re ← lowerExpr plan ent.params stateLocals e
        body := body.push (.returnExpr re)
    | _, _ => pure ()
    fns := fns.push {
      name := ent.name
      params := fnParams
      returnType := resultTypeStr ent.resultKind
      body
    }
  -- Views
  for v in plan.views do
    let mut fnParams : Array (String × String) := #[("env", "Env")]
    for p in v.params do
      fnParams := fnParams.push (p, "u64")
    let re ← lowerExpr plan v.params #[] v.value
    fns := fns.push {
      name := v.name
      params := fnParams
      returnType := resultTypeStr v.resultKind
      body := #[.returnExpr re]
    }
  let contract : RContract := {
    contractName := plan.programName
    fns
  }
  pure { sourcePlan := plan, contract }

-- ---------------------------------------------------------------------------
-- Renderer
-- ---------------------------------------------------------------------------

private def binOpStr : RBinOp → String
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
  | .and => "&&"
  | .or => "||"

private partial def renderExpr : RExpr → String
  | .name id => id
  | .u64Lit v => s!"{v}_u64"
  | .boolLit true => "true"
  | .boolLit false => "false"
  | .binary op l r =>
      s!"({renderExpr l} {binOpStr op} {renderExpr r})"
  | .unary .not o =>
      s!"(!{renderExpr o})"
  | .checkedArith method receiver arg panicMsg =>
      s!"{renderExpr receiver}.{method}({renderExpr arg}).expect(\"{panicMsg}\")"
  | .storageGet key =>
      s!"env.storage().instance().get(&symbol_short!(\"{key}\")).unwrap_or(0_u64)"
  | .storageSet key value =>
      s!"env.storage().instance().set(&symbol_short!(\"{key}\"), &{renderExpr value})"
  | .ifExpr cond thenE elseE =>
      s!"if {renderExpr cond} \{ {renderExpr thenE} } else \{ {renderExpr elseE} }"
  | .panic msg => s!"panic!(\"{msg}\")"
  | .unit => "()"

private def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

private def renderStatement (s : RStatement) : String :=
  match s with
  | .letBind name value => s!"let {name} = {renderExpr value};"
  | .expr value => s!"{renderExpr value};"
  | .returnExpr value => renderExpr value

private def renderFn (f : RFn) : Array String := Id.run do
  let mut lines : Array String := #[]
  let params := String.intercalate ", "
    (f.params.map (fun (n, t) => if n == "env" then s!"{n}: {t}" else s!"{n}: {t}")).toList
  let retSig := match f.returnType with
    | some t => s!" -> {t}"
    | none => ""
  lines := lines.push (indent 4 s!"pub fn {f.name}({params}){retSig} \{")
  for i in [0:f.body.size] do
    match f.body[i]? with
    | some stmt =>
        lines := lines.push (indent 8 (renderStatement stmt))
    | none => pure ()
  lines := lines.push (indent 4 "}")
  pure lines

private def renderContract (c : RContract) (sourceHash semanticHash : String) : String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push "// ProofForge Soroban S0 source recipe; not a deployable Wasm claim; zero-tool finalize."
  lines := lines.push s!"// source: {sourceHash}"
  lines := lines.push s!"// semantic: {semanticHash}"
  lines := lines.push "#![no_std]"
  lines := lines.push "use soroban_sdk::{contract, contractimpl, symbol_short, Env};"
  lines := lines.push ""
  lines := lines.push "#[contract]"
  lines := lines.push s!"pub struct {c.contractName};"
  lines := lines.push ""
  lines := lines.push "#[contractimpl]"
  lines := lines.push s!"impl {c.contractName} \{"
  for f in c.fns do
    lines := lines.push ""
    lines := lines ++ renderFn f
  lines := lines.push "}"
  lines := lines.push ""
  pure (String.intercalate "\n" lines.toList)

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderContract ir.contract ir.sourcePlan.sourceHash ir.sourcePlan.semanticHash
  pure #[{
    path := s!"{ir.sourcePlan.programName}.rs"
    mediaType := "text/x-rust"
    contents := source
  }]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless isAsciiIdentifier 240 ir.contract.contractName do
    planError "Soroban IR contract name is not a safe identifier"
  pure ()

def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  validateIR ir
  emitFromIR ir

def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  let plan ← planFromCompiledSemanticV1 compiled
  validatePlan plan
  lower plan

def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCompiledSemanticV1 compiled
  validateIR ir
  emitFromIR ir

end ProofForgeV2.Targets.Soroban
