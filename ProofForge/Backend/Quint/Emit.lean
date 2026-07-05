import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.Emit

open ProofForge.Backend.Quint

def indent (n : Nat) : String :=
  String.ofList (List.replicate (n * 2) ' ')

partial def emitType (t : QuintType) : String :=
  t.name

partial def emitExpr (prec : Nat) (e : Expr) : String :=
  let emit (e : Expr) := emitExpr 0 e
  let wrap (ownPrec : Nat) (s : String) : String :=
    if ownPrec < prec then s!"({s})" else s
  let emitList (xs : Array Expr) : String :=
    String.intercalate ", " (xs.map emit).toList
  match e with
  | .literalInt value =>
      toString value
  | .literalBool true =>
      "true"
  | .literalBool false =>
      "false"
  | .literalStr value =>
      s!"\"{value}\""
  | .local name =>
      name
  | .binOp op lhs rhs =>
      let ownPrec := match op with
        | .or => 10
        | .and => 20
        | .eq | .ne => 30
        | .lt | .le | .gt | .ge => 40
        | .add | .sub => 50
        | .mul | .div | .mod => 60
      wrap ownPrec s!"{emitExpr ownPrec lhs} {op.symbol} {emitExpr (ownPrec + 1) rhs}"
  | .unOp op value =>
      s!"{op.symbol} {emitExpr 70 value}"
  | .prime value =>
      s!"{emitExpr 80 value}'"
  | .app fn args =>
      let argsStr := emitList args
      s!"{fn}({argsStr})"
  | .oneOf set =>
      s!"oneOf({emit set})"
  | .range low high =>
      s!"{emit low}.to({emit high})"
  | .setLit values =>
      s!"Set({emitList values})"
  | .listLit values =>
      s!"[{emitList values}]"
  | .mapLit entries =>
      let entriesStr := String.intercalate ", " (entries.map (fun (k, v) => s!"{emit k} -> {emit v}")).toList
      s!"Map({entriesStr})"
  | .ite cond thenExpr elseExpr =>
      wrap 5 s!"if ({emit cond}) {emit thenExpr} else {emit elseExpr}"

partial def emitActionClause (depth : Nat) (clause : ActionClause) : String :=
  let ind := indent depth
  match clause with
  | .assign target value =>
      s!"{ind}{emitExpr 0 target} = {emitExpr 0 value}"
  | .guard expr =>
      s!"{ind}{emitExpr 0 expr}"
  | .call name args =>
      if args.isEmpty then
        ind ++ name
      else
        let argsStr := String.intercalate ", " (args.map (emitExpr 0)).toList
        ind ++ name ++ "(" ++ argsStr ++ ")"
  | .nondet name domain body =>
      s!"{ind}nondet {name} = {emitExpr 0 domain}\n{emitActionClause depth body}"
  | .all clauses =>
      if clauses.isEmpty then
        ind ++ "all { }"
      else
        let body := String.intercalate ",\n" (clauses.map (emitActionClause (depth + 1))).toList
        ind ++ "all {\n" ++ body ++ "\n" ++ ind ++ "}"
  | .any clauses =>
      if clauses.isEmpty then
        ind ++ "any { }"
      else
        let body := String.intercalate ",\n" (clauses.map (emitActionClause (depth + 1))).toList
        ind ++ "any {\n" ++ body ++ "\n" ++ ind ++ "}"

def emitParams (params : Array (String × QuintType)) : String :=
  if params.isEmpty then
    ""
  else
    let paramsStr := String.intercalate ", " (params.map (fun (n, t) => s!"{n}: {emitType t}")).toList
    s!"({paramsStr})"

def emitAction (action : Action) : String :=
  let paramsStr := emitParams action.params
  let retStr := match action.ret? with
    | some t => s!": {emitType t}"
    | none => ""
  s!"action {action.name}{paramsStr}{retStr} = {emitActionClause 0 action.body}"

def emitPureDef (defn : PureDef) : String :=
  let paramsStr := emitParams defn.params
  s!"pure def {defn.name}{paramsStr}: {emitType defn.ret} = {emitExpr 0 defn.body}"

def emitConstant (c : Constant) : String :=
  s!"const {c.name}: {emitType c.type}"

def emitVar (v : Var) : String :=
  s!"var {v.name}: {emitType v.type}"

def emitVal (v : Val) : String :=
  s!"val {v.name} = {emitExpr 0 v.body}"

def emitModule (m : Module) : String :=
  let parts : Array String := #[]
  let parts := if m.constants.isEmpty then parts else parts ++ m.constants.map emitConstant
  let parts := if m.vars.isEmpty then parts else parts ++ m.vars.map emitVar
  let parts := if m.pureDefs.isEmpty then parts else parts ++ m.pureDefs.map emitPureDef
  let parts := parts ++ m.actions.map emitAction
  let parts := if m.vals.isEmpty then parts else parts ++ m.vals.map emitVal
  let body := String.intercalate "\n\n" (parts.map (fun s => "  " ++ s)).toList
  "module " ++ m.name ++ " {\n" ++ body ++ "\n}"

end ProofForge.Backend.Quint.Emit
