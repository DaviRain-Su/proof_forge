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
  | tailTuple (elems : Array RExpr)
  | tailSuccess
  | unreachableAfterRevert
  | ifThenElse (cond : RExpr) (thenBody elseBody : Array RStmt)
  | forLoop (varName : String) (initial cond update : RExpr)
      (maxIterations : Nat) (body : Array RStmt)
  deriving BEq, Inhabited, Repr

structure RustFn where
  name : String
  params : Array String
  writesState : Bool
  stmts : Array RStmt
  /-- `some n` = view/entry leaf-tuple ABI `(u64, …)`; `none` = `-> i32`. -/
  tupleArity : Option Nat := none
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
  | .temp i =>
      pure (.name s!"pf_t{i}")
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

private partial def emitPlanStatements
    (plan : Plan) (params : Array String) (stmts : Array Statement) :
    CompileResult (Array RStmt) := do
  let mut out : Array RStmt := #[]
  for stmt in stmts do
    match stmt with
    | .store fi e =>
        let field ← stateFieldName plan fi
        let re ← lowerExprToRExpr plan params e
        out := out.push (.storeField field re)
    | .ifThenElse cond thenBody elseBody =>
        let c ← lowerExprToRExpr plan params cond
        let t ← emitPlanStatements plan params thenBody
        let e ← emitPlanStatements plan params elseBody
        out := out.push (.ifThenElse c t e)
    | .switchOn scrut cases defaultBody =>
        let folded : Array Statement :=
          cases.foldr
            (fun (v, body) acc =>
              #[.ifThenElse (.compare .eq scrut (.litU64 v)) body acc])
            defaultBody
        let sw ← emitPlanStatements plan params folded
        out := out ++ sw
    | .forLoop varTemp initial condition update maxIterations body =>
        let initE ← lowerExprToRExpr plan params initial
        let condE ← lowerExprToRExpr plan params condition
        let updE ← lowerExprToRExpr plan params update
        let bodyStmts ← emitPlanStatements plan params body
        out := out.push
          (.forLoop s!"pf_t{varTemp}" initE condE updE maxIterations bodyStmts)
    | .returnValue e =>
        let re ← lowerExprToRExpr plan params e
        out := out.push (.tailI32 re)
    | .returnAggregate leaves =>
        let mut elems : Array RExpr := #[]
        for e in leaves do
          elems := elems.push (← lowerExprToRExpr plan params e)
        out := out.push (.tailTuple elems)
    | .returnNone =>
        out := out.push .tailSuccess
  pure out

private def buildEntryFn (plan : Plan) (ent : PlanEntry) : CompileResult RustFn := do
  let mut stmts : Array RStmt := #[]
  for ck in guardChecksOf ent.checks do
    let rc ← lowerExprToRExpr plan ent.params ck.condition
    stmts := stmts.push (.guard rc ck.kind.code)
  if !ent.body.isEmpty then
    let cfgStmts ← emitPlanStatements plan ent.params ent.body
    stmts := stmts ++ cfgStmts
    let tupleArity : Option Nat :=
      match ent.resultKind with
      | .aggregate n => some n
      | _ => none
    pure ({
      name := ent.name
      params := ent.params
      writesState := true
      stmts
      tupleArity
    } : RustFn)
  else do
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
    | .aggregate n, _ => do
        unless ent.resultLeaves.size == n do
          planError s!"XRPL IR entry '{ent.name}' aggregate emit leaf count must be {n}"
        unless ent.checks.isEmpty do
          planError
            s!"XRPL IR entry '{ent.name}' aggregate return cannot contain fallible checks"
        let mut elems : Array RExpr := #[]
        for e in ent.resultLeaves do
          elems := elems.push (← lowerExprToRExpr plan ent.params e)
        stmts := stmts.push (.tailTuple elems)
    | _, _ =>
        planError s!"XRPL IR entry '{ent.name}' result shape is not canonical"
  let tupleArity : Option Nat :=
    match ent.resultKind with
    | .aggregate n => some n
    | _ => none
  pure {
    name := ent.name
    params := ent.params
    writesState := !ent.stores.isEmpty
    stmts
    tupleArity
  }

private def buildViewFn (plan : Plan) (v : PlanView) : CompileResult RustFn := do
  match v.resultKind with
  | .aggregate n => do
      unless v.leaves.size == n do
        planError s!"XRPL view '{v.name}' aggregate emit leaf count must be {n}"
      let mut elems : Array RExpr := #[]
      for e in v.leaves do
        elems := elems.push (← lowerExprToRExpr plan v.params e)
      pure {
        name := v.name
        params := v.params
        writesState := false
        stmts := #[.tailTuple elems]
        tupleArity := some n
      }
  | _ => do
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

private partial def renderStmtLines (level : Nat) : RStmt → Array String
  | .guard cond code =>
      #[indent level
          ("if !(" ++ renderRExpr cond ++ ") { return Err(" ++
            toString code ++ "i32); }")]
  | .storeField field value =>
      #[indent level ("let " ++ field ++ "_new = " ++ renderRExpr value ++ ";"),
        indent level ("write_u64(" ++ field ++ "_KEY, " ++ field ++ "_new)?;")]
  | .tailI32 value =>
      #[indent level ("Ok(" ++ renderRExpr value ++ " as i32)")]
  | .tailTuple elems =>
      let inner := String.intercalate ", " (elems.map renderRExpr).toList
      #[indent level ("(" ++ inner ++ ")")]
  | .tailSuccess =>
      #[indent level "Ok(0)"]
  | .unreachableAfterRevert =>
      #[indent level
          "unreachable!(\"Q0 template: a prior guard always returns before this point\")"]
  | .ifThenElse cond thenBody elseBody => Id.run do
      let mut lines := #[indent level ("if " ++ renderRExpr cond ++ " {")]
      for stmt in thenBody do
        lines := lines ++ renderStmtLines (level + 4) stmt
      if elseBody.isEmpty then
        lines := lines.push (indent level "}")
      else
        lines := lines.push (indent level "} else {")
        for stmt in elseBody do
          lines := lines ++ renderStmtLines (level + 4) stmt
        lines := lines.push (indent level "}")
      lines
  | .forLoop varName initial cond update maxIterations body => Id.run do
      let iter := varName ++ "_iter"
      let mut lines :=
        #[indent level ("let mut " ++ varName ++ ": u64 = " ++
            renderRExpr initial ++ ";"),
          indent level ("let mut " ++ iter ++ ": u64 = 0;"),
          indent level "loop {"]
      lines := lines.push
        (indent (level + 4)
          ("if " ++ iter ++ " >= " ++ toString maxIterations ++
            "u64 { return Err(1i32); }"))
      lines := lines.push
        (indent (level + 4) ("if !(" ++ renderRExpr cond ++ ") { break; }"))
      for stmt in body do
        lines := lines ++ renderStmtLines (level + 4) stmt
      lines := lines.push
        (indent (level + 4) (varName ++ " = " ++ renderRExpr update ++ ";"))
      lines := lines.push
        (indent (level + 4)
          (iter ++ " = " ++ iter ++
            ".checked_add(1).ok_or(1i32)?;"))
      lines := lines.push (indent level "}")
      lines

private def renderStmt (stmt : RStmt) : Array String :=
  renderStmtLines 8 stmt

private partial def collectLoadedFields (fn : RustFn) (all : Array String) : Array String :=
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
    let rec walkStmt (acc : Array String) : RStmt → Array String
      | .guard cond _ => walk acc cond
      | .storeField field value =>
          let acc := walk acc value
          if !acc.contains field then acc.push field else acc
      | .tailI32 value => walk acc value
      | .tailTuple elems =>
          Id.run do
            let mut a := acc
            for e in elems do
              a := walk a e
            a
      | .tailSuccess | .unreachableAfterRevert => acc
      | .ifThenElse cond thenBody elseBody =>
          Id.run do
            let mut a := walk acc cond
            for s in thenBody ++ elseBody do
              a := walkStmt a s
            a
      | .forLoop _ initial cond update _ body =>
          Id.run do
            let mut a := walk (walk (walk acc initial) cond) update
            for s in body do
              a := walkStmt a s
            a
    let mut acc : Array String := #[]
    for stmt in fn.stmts do
      acc := walkStmt acc stmt
    pure acc

private def rustTupleType (n : Nat) : String :=
  if n == 1 then "(u64,)"
  else
    let parts := List.replicate n "u64"
    "(" ++ String.intercalate ", " parts ++ ")"

private def renderFn (fn : RustFn) (allFields : Array String) : Array String := Id.run do
  let mut lines : Array String := #[]
  let params := String.intercalate ", "
    (fn.params.map (fun p => s!"{p}: u64")).toList
  lines := lines.push s!"/// @xrpl-function {fn.name}"
  lines := lines.push "#[unsafe(no_mangle)]"
  let loaded := collectLoadedFields fn allFields
  match fn.tupleArity with
  | some n =>
      lines := lines.push
        s!"pub extern \"C\" fn {fn.name}({params}) -> {rustTupleType n} {"{"}"
      for field in loaded do
        lines := lines.push (indent 4 s!"let {field}_cur = read_u64({field}_KEY);")
      for stmt in fn.stmts do
        match stmt with
        | .storeField field value =>
            lines := lines.push
              (indent 4 ("let " ++ field ++ "_new = " ++ renderRExpr value ++ ";"))
            lines := lines.push
              (indent 4 ("let _ = write_u64(" ++ field ++ "_KEY, " ++ field ++ "_new);"))
        | .tailTuple elems =>
            let inner := String.intercalate ", " (elems.map renderRExpr).toList
            lines := lines.push (indent 4 ("(" ++ inner ++ ")"))
        | other =>
            lines := lines ++ renderStmt other
      lines := lines.push "}"
  | none =>
      lines := lines.push s!"pub extern \"C\" fn {fn.name}({params}) -> i32 {"{"}"
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
