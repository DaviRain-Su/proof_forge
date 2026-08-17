import ProofForgeV2.Targets.Xrpl.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Targets.Common

/-!
# XRPL EmitIRV1 — Plan → structured Rust IR → Bedrock-shaped `{name}.rs`

IR is a structured Rust guest AST. The renderer is the sole producer of
`text/x-rust` bytes. ADR-0049 Q0: scaffold-xrp Counter dialect
(`xrpl_wasm_std`, `get_data`/`set_data`, `#[unsafe(no_mangle)] pub extern "C"`).
Zero-tool finalize; not a deployable Wasm claim.
-/

namespace ProofForgeV2.Targets.Xrpl

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .xrpl message

inductive RCmpOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive RExpr where
  | litU64 (value : UInt64)
  | litBool (value : Bool)
  | name (id : String)
  | checkedAdd (lhs rhs : RExpr) (errCode : Nat)
  | checkedSub (lhs rhs : RExpr) (errCode : Nat)
  | checkedMul (lhs rhs : RExpr) (errCode : Nat)
  | checkedDiv (lhs rhs : RExpr) (errCode : Nat)
  | checkedMod (lhs rhs : RExpr) (errCode : Nat)
  | compareOp (op : RCmpOp) (lhs rhs : RExpr)
  | boolAnd (lhs rhs : RExpr)
  | boolOr (lhs rhs : RExpr)
  | boolNot (operand : RExpr)
  deriving BEq, Inhabited, Repr

inductive RStmt where
  | guard (cond : RExpr) (errCode : Nat)
  | storeField (field : String) (value : RExpr)
  | tailI32 (value : RExpr)
  | tailSuccess
  | unreachableAfterRevert
  deriving BEq, Inhabited, Repr

structure RustFn where
  name : String
  params : Array String
  writesState : Bool
  stmts : Array RStmt
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  stateFields : Array String
  initFn : Option RustFn
  entryFns : Array RustFn
  viewFns : Array RustFn
  deriving BEq, Inhabited, Repr

private def stateFieldName (plan : Plan) (fieldIndex : Nat) : CompileResult String := do
  match plan.states[fieldIndex]? with
  | some st => pure st.name
  | none => planError "XRPL IR state field index out of range"

private def paramVar (params : Array String) (index : Nat) : CompileResult String := do
  match params[index]? with
  | some n => pure n
  | none => planError "XRPL IR parameter index out of range"

private partial def lowerExprToRExpr
    (plan : Plan) (params : Array String) (e : Expr) : CompileResult RExpr := do
  match e with
  | .litU64 v => pure (.litU64 v)
  | .litBool b => pure (.litBool b)
  | .param i => do
      let n ← paramVar params i
      pure (.name n)
  | .stateLoad fi => do
      let n ← stateFieldName plan fi
      pure (.name s!"{n}_cur")
  | .arith .add l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedAdd rl rr FailureKind.overflow.code)
  | .arith .sub l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedSub rl rr FailureKind.underflow.code)
  | .arith .mul l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedMul rl rr FailureKind.overflow.code)
  | .arith .div l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedDiv rl rr FailureKind.divByZero.code)
  | .arith .mod l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedMod rl rr FailureKind.divByZero.code)
  | .compare op l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      let rop : RCmpOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
      pure (.compareOp rop rl rr)
  | .boolAnd l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.boolAnd rl rr)
  | .boolOr l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.boolOr rl rr)
  | .boolNot o => do
      let ro ← lowerExprToRExpr plan params o
      pure (.boolNot ro)

private def guardChecksOf (checks : Array Check) : Array Check :=
  checks.filter fun ck =>
    match ck.kind with
    | .overflow | .underflow => false
    | .divByZero | .assertion | .declaredRevert _ | .terminalRevert _ => true

private def buildEntryFn (plan : Plan) (ent : PlanEntry) : CompileResult RustFn := do
  let mut stmts : Array RStmt := #[]
  for ck in guardChecksOf ent.checks do
    let rc ← lowerExprToRExpr plan ent.params ck.condition
    stmts := stmts.push (.guard rc ck.kind.code)
  for (fi, e) in ent.stores do
    let field ← stateFieldName plan fi
    let rv ← lowerExprToRExpr plan ent.params e
    stmts := stmts.push (.storeField field rv)
  if ent.terminalRevert then
    stmts := stmts.push .unreachableAfterRevert
  else
    match ent.resultKind, ent.result? with
    | .unit, none => stmts := stmts.push .tailSuccess
    | .uint64, some e =>
        let rv ← lowerExprToRExpr plan ent.params e
        stmts := stmts.push (.tailI32 rv)
    | .bool, some e =>
        let rv ← lowerExprToRExpr plan ent.params e
        stmts := stmts.push (.tailI32 rv)
    | _, _ =>
        planError s!"XRPL IR entry '{ent.name}' result shape is not canonical"
  pure {
    name := ent.name
    params := ent.params
    writesState := !ent.stores.isEmpty
    stmts
  }

private def buildViewFn (plan : Plan) (v : PlanView) : CompileResult RustFn := do
  let rv ← lowerExprToRExpr plan v.params v.value
  pure {
    name := v.name
    params := v.params
    writesState := false
    stmts := #[.tailI32 rv]
  }

private def buildInitFn (plan : Plan) : CompileResult (Option RustFn) := do
  match plan.initializer with
  | none =>
      if plan.states.isEmpty then
        pure none
      else
        let mut stmts : Array RStmt := #[]
        for st in plan.states do
          stmts := stmts.push (.storeField st.name (.litU64 0))
        stmts := stmts.push .tailSuccess
        pure (some {
          name := "initialize"
          params := #[]
          writesState := true
          stmts
        })
  | some initFn =>
      let mut stmts : Array RStmt := #[]
      for (fi, e) in initFn.stores do
        let field ← stateFieldName plan fi
        let rv ← lowerExprToRExpr plan initFn.params e
        stmts := stmts.push (.storeField field rv)
      stmts := stmts.push .tailSuccess
      pure (some {
        name := initFn.name
        params := initFn.params
        writesState := true
        stmts
      })

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let stateFields := plan.states.map (·.name)
  let initFn ← buildInitFn plan
  let mut entryFns : Array RustFn := #[]
  for ent in plan.entries do
    entryFns := entryFns.push (← buildEntryFn plan ent)
  let mut viewFns : Array RustFn := #[]
  for v in plan.views do
    viewFns := viewFns.push (← buildViewFn plan v)
  pure { sourcePlan := plan, stateFields, initFn, entryFns, viewFns }

private def cmpSym : RCmpOp → String
  | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="

private partial def renderRExpr : RExpr → String
  | .litU64 v => s!"{v}u64"
  | .litBool true => "true"
  | .litBool false => "false"
  | .name id => id
  | .checkedAdd l r code =>
      s!"({renderRExpr l}).checked_add({renderRExpr r}).ok_or({code}i32)?"
  | .checkedSub l r code =>
      s!"({renderRExpr l}).checked_sub({renderRExpr r}).ok_or({code}i32)?"
  | .checkedMul l r code =>
      s!"({renderRExpr l}).checked_mul({renderRExpr r}).ok_or({code}i32)?"
  | .checkedDiv l r code =>
      s!"({renderRExpr l}).checked_div({renderRExpr r}).ok_or({code}i32)?"
  | .checkedMod l r code =>
      s!"({renderRExpr l}).checked_rem({renderRExpr r}).ok_or({code}i32)?"
  | .compareOp op l r =>
      s!"({renderRExpr l} {cmpSym op} {renderRExpr r})"
  | .boolAnd l r => s!"({renderRExpr l} && {renderRExpr r})"
  | .boolOr l r => s!"({renderRExpr l} || {renderRExpr r})"
  | .boolNot o => s!"(!{renderRExpr o})"

private def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

private def renderStmt : RStmt → Array String
  | .guard cond code =>
      #[indent 8
          ("if !(" ++ renderRExpr cond ++ ") { return Err(" ++
            toString code ++ "i32); }")]
  | .storeField field value =>
      #[indent 8 ("let " ++ field ++ "_new = " ++ renderRExpr value ++ ";"),
        indent 8 ("write_u64(" ++ field ++ "_KEY, " ++ field ++ "_new)?;")]
  | .tailI32 value =>
      #[indent 8 ("Ok(" ++ renderRExpr value ++ " as i32)")]
  | .tailSuccess =>
      #[indent 8 "Ok(0)"]
  | .unreachableAfterRevert =>
      #[indent 8
          "unreachable!(\"Q0 template: a prior guard always returns before this point\")"]

private def collectLoadedFields (fn : RustFn) (all : Array String) : Array String :=
  Id.run do
    let rec walk (acc : Array String) : RExpr → Array String
      | .name id =>
          if id.endsWith "_cur" then
            let base := id.dropEnd 4 |>.copy
            if all.contains base && !acc.contains base then acc.push base else acc
          else acc
      | .checkedAdd l r _ | .checkedSub l r _ | .checkedMul l r _
      | .checkedDiv l r _ | .checkedMod l r _ => walk (walk acc l) r
      | .compareOp _ l r | .boolAnd l r | .boolOr l r => walk (walk acc l) r
      | .boolNot o => walk acc o
      | .litU64 _ | .litBool _ => acc
    let mut acc : Array String := #[]
    for stmt in fn.stmts do
      match stmt with
      | .guard cond _ => acc := walk acc cond
      | .storeField _ value => acc := walk acc value
      | .tailI32 value => acc := walk acc value
      | .tailSuccess | .unreachableAfterRevert => pure ()
    for stmt in fn.stmts do
      match stmt with
      | .storeField field _ =>
          if !acc.contains field then acc := acc.push field
      | _ => pure ()
    pure acc

private def renderFn (fn : RustFn) (allFields : Array String) : Array String := Id.run do
  let mut lines : Array String := #[]
  let params := String.intercalate ", "
    (fn.params.map (fun p => s!"{p}: u64")).toList
  lines := lines.push s!"/// @xrpl-function {fn.name}"
  lines := lines.push "#[unsafe(no_mangle)]"
  lines := lines.push s!"pub extern \"C\" fn {fn.name}({params}) -> i32 {"{"}"
  let loaded := collectLoadedFields fn allFields
  for field in loaded do
    lines := lines.push (indent 4 s!"let {field}_cur = read_u64({field}_KEY);")
  lines := lines.push (indent 4 "let result: Result<i32, i32> = (|| {")
  for stmt in fn.stmts do
    lines := lines ++ renderStmt stmt
  lines := lines.push (indent 4 "})();")
  lines := lines.push (indent 4 "match result {")
  lines := lines.push (indent 8 "Ok(code) => code,")
  lines := lines.push (indent 8 "Err(code) => if code < 0 { code } else { -code },")
  lines := lines.push (indent 4 "}")
  lines := lines.push "}"
  pure lines

private def rustKeyConst (field : String) : String :=
  s!"const {field}_KEY: &str = \"{field}\";"

private def renderContract (ir : IR) : String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push
    s!"// Generated by proof-forge-next (XRPL target, {codegenProfileString})."
  lines := lines.push
    "// ADR-0049 Q0: Bedrock-shaped source recipe; not a deployable Wasm claim; zero-tool finalize."
  lines := lines.push s!"// source: {ir.sourcePlan.sourceHash}"
  lines := lines.push s!"// semantic: {ir.sourcePlan.semanticHash}"
  lines := lines.push "#![cfg_attr(target_arch = \"wasm32\", no_std)]"
  lines := lines.push ""
  lines := lines.push "#[cfg(not(target_arch = \"wasm32\"))]"
  lines := lines.push "extern crate std;"
  lines := lines.push ""
  lines := lines.push "use xrpl_wasm_std::core::current_tx::contract_call::get_current_contract_call;"
  lines := lines.push "use xrpl_wasm_std::core::current_tx::traits::ContractCallFields;"
  lines := lines.push "use xrpl_wasm_std::core::data::codec::{get_data, set_data};"
  lines := lines.push "use xrpl_wasm_std::host::trace::trace;"
  lines := lines.push ""
  for field in ir.stateFields do
    lines := lines.push (rustKeyConst field)
  if !ir.stateFields.isEmpty then
    lines := lines.push ""
  lines := lines.push "fn read_u64(key: &str) -> u64 {"
  lines := lines.push "    let contract_call = get_current_contract_call();"
  lines := lines.push "    let contract_account = contract_call.get_contract_account().unwrap();"
  lines := lines.push "    match get_data::<u64>(&contract_account, key) {"
  lines := lines.push "        Some(value) => value,"
  lines := lines.push "        None => 0,"
  lines := lines.push "    }"
  lines := lines.push "}"
  lines := lines.push ""
  lines := lines.push "fn write_u64(key: &str, value: u64) -> Result<(), i32> {"
  lines := lines.push "    let contract_call = get_current_contract_call();"
  lines := lines.push "    let contract_account = contract_call.get_contract_account().unwrap();"
  lines := lines.push "    set_data::<u64>(&contract_account, key, value)"
  lines := lines.push "}"
  lines := lines.push ""
  if let some initFn := ir.initFn then
    lines := lines ++ renderFn initFn ir.stateFields
    lines := lines.push ""
  for fn in ir.entryFns do
    lines := lines ++ renderFn fn ir.stateFields
    lines := lines.push ""
  for fn in ir.viewFns do
    lines := lines ++ renderFn fn ir.stateFields
    lines := lines.push ""
  pure (String.intercalate "\n" lines.toList)

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderContract ir
  pure #[{
    path := s!"{ir.sourcePlan.programName}.rs"
    mediaType := "text/x-rust"
    contents := source
  }]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless isAsciiIdentifier 200 ir.sourcePlan.programName do
    planError "XRPL IR program name is not a safe identifier"
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

end ProofForgeV2.Targets.Xrpl
