import ProofForgeV2.Targets.Aleo.ValidatePlanV1

/-!
# Aleo EmitIRV1 — Plan → Leo IR emission

Target-owned Leo 4.0.2 AST/renderer and capability-internal `lower`/`emitFromIR`.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- Leo 4.0.2 expressions (pure value syntax; mapping access is final-context
    only and appears as method calls on the mapping name). -/
inductive LeoExpr where
  | u64Literal (value : UInt64)
  | boolLiteral (value : Bool)
  | reference (name : String)
  | unary (op : String) (inner : LeoExpr)
  | binary (op : String) (lhs rhs : LeoExpr)
  | ternary (condition thenValue elseValue : LeoExpr)
  | mappingGetOrUse (mapping : String) (key : String) (default : LeoExpr)
  | call (name : String) (args : Array LeoExpr)
  deriving BEq, Inhabited, Repr

/-- Leo 4.0.2 statements (final/proof context). Leo `let` requires an explicit
    type annotation, so every binding carries its Leo type name. -/
inductive LeoStatement where
  | letBinding (name ty : String) (value : LeoExpr)
  | assert (condition : LeoExpr)
  | mappingSet (mapping : String) (key : String) (value : LeoExpr)
  | returnValue (value : LeoExpr)
  | returnUnit
  | ifElse (condition : LeoExpr) (thenBody elseBody : Array LeoStatement)
  | forConst (index : String) (bound : Nat) (body : Array LeoStatement)
  deriving BEq, Inhabited, Repr

structure LeoParam where
  name : String
  isBool : Bool
  deriving BEq, Inhabited, Repr

structure LeoFunction where
  name : String
  params : Array LeoParam
  resultIsBool : Bool
  /-- `some` = state-touching Final function (body runs in final context). -/
  isFinal : Bool
  body : Array LeoStatement
  deriving BEq, Inhabited, Repr

structure LeoMapping where
  name : String
  deriving BEq, Inhabited, Repr

/-- Leo 4.0.2 program AST. Rendering source happens after Plan-to-IR
    validation so source strings cannot rediscover business semantics. -/
structure LeoProgram where
  programId : String
  mappings : Array LeoMapping
  functions : Array LeoFunction
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  program : LeoProgram
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

private def maxIrNodes : Nat := 110000

private def mappingKey : String := "0u8"
private def guardMappingName : String := "initialized"

private def isLeoProgramId (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      let isLower (c : Char) : Bool :=
        let code := c.toNat
        97 <= code && code <= 122
      let isDigit (c : Char) : Bool :=
        let code := c.toNat
        48 <= code && code <= 57
      isLower first && rest.all (fun c =>
        isLower c || isDigit c || c == '_')

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

private def renderType (isBool : Bool) : String :=
  if isBool then "boolean" else "u64"

private def renderLit (value : UInt64) : String :=
  s!"{value.toNat}u64"

private partial def renderExpr : LeoExpr → String
  | .u64Literal value => renderLit value
  | .boolLiteral value => if value then "true" else "false"
  | .reference name => name
  | .unary op inner => s!"({op}{renderExpr inner})"
  | .binary op lhs rhs => s!"({renderExpr lhs} {op} {renderExpr rhs})"
  | .ternary condition thenValue elseValue =>
      s!"({renderExpr condition} ? {renderExpr thenValue} : {renderExpr elseValue})"
  | .mappingGetOrUse mapping key default =>
      s!"{mapping}.get_or_use({key}, {renderExpr default})"
  | .call name args =>
      let inner := args.toList.map renderExpr |> String.intercalate ", "
      s!"{name}({inner})"

private def indentStr (depth : Nat) : String :=
  String.ofList (List.replicate depth ' ')

mutual

private partial def renderStatements (depth : Nat) (stmts : Array LeoStatement) : String :=
  stmts.toList.map (renderStatement depth) |> String.intercalate ""

private partial def renderStatement (depth : Nat) : LeoStatement → String
  | .letBinding name ty value =>
      s!"{indentStr depth}let {name}: {ty} = {renderExpr value};\n"
  | .assert condition =>
      s!"{indentStr depth}assert({renderExpr condition});\n"
  | .mappingSet mapping key value =>
      s!"{indentStr depth}{mapping}.set({key}, {renderExpr value});\n"
  | .returnValue value =>
      s!"{indentStr depth}return {renderExpr value};\n"
  | .returnUnit =>
      s!"{indentStr depth}return ();\n"
  | .ifElse condition thenBody elseBody =>
      s!"{indentStr depth}if {renderExpr condition} \{\n" ++
      renderStatements (depth + 2) thenBody ++
      (if elseBody.isEmpty then
         s!"{indentStr depth}}}\n"
       else
         s!"{indentStr depth}}} else \{\n" ++
         renderStatements (depth + 2) elseBody ++
         s!"{indentStr depth}}}\n")
  | .forConst index bound body =>
      s!"{indentStr depth}for {index} in 0u64..{bound}u64 \{\n" ++
      renderStatements (depth + 2) body ++
      s!"{indentStr depth}}}\n"

end

private def renderParam (param : LeoParam) : String :=
  s!"public {param.name}: {renderType param.isBool}"

private def renderFunction : LeoFunction → String
  | fn =>
      let signature := (fn.params.toList.map renderParam) |> String.intercalate ", "
      let resultTy := if fn.isFinal then "Final" else renderType fn.resultIsBool
      let body := renderStatements 4 fn.body
      s!"    fn {fn.name}({signature}) -> {resultTy} \{\n" ++
      (if fn.isFinal then
         s!"        return final \{\n{body}        }\n"
       else
         body) ++
      s!"    }\n\n"

private def renderProgram (programId : String) (program : LeoProgram) : String :=
  let mappings := (program.mappings.toList.map fun m =>
    s!"    mapping {m.name}: u8 => u64;") |> String.intercalate "\n"
  s!"// Generated by proof-forge-next (Aleo target, Leo {leoToolchain}).\n" ++
  s!"program {programId}.aleo \{\n" ++
  s!"    @noupgrade\n" ++
  s!"    constructor() \{\n\n" ++
  (if mappings.isEmpty then "" else mappings ++ "\n\n") ++
  s!"    mapping {guardMappingName}: u8 => bool;\n\n" ++
  (program.functions.toList.map renderFunction |> String.intercalate "") ++
  s!"}\n"

private def validateLeoProgram (program : LeoProgram) : CompileResult Unit := do
  unless isLeoProgramId program.programId do
    planError s!"'{program.programId}' is not a legal Leo program id"
  unless program.functions.size ≤ maxIrNodes do
    planError "Aleo IR exceeds the node limit"

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  validateLeoProgram ir.program

-- ---------------------------------------------------------------------------
-- Plan → Leo IR
-- ---------------------------------------------------------------------------

/-- Statement lowering context: fresh-name counter and the mapping name for
    each state field. Mapping names are generated (`pf_state_{i}`), so DSL
    state names cannot collide with Leo mapping-method vocabulary. -/
private structure EmitCtx where
  next : Nat
  mappingNames : Array String
  deriving Inhabited

private def freshName (ctx : EmitCtx) : String × EmitCtx :=
  (s!"pf_e{ctx.next}", { ctx with next := ctx.next + 1 })

/-- The Leo type of a plan expression (every plan expr is u64 or boolean). -/
private def exprLeoType : Expr → String
  | .boolLiteral _ => "boolean"
  | .compare _ _ _ => "boolean"
  | .logicalAnd _ _ | .logicalOr _ _ => "boolean"
  | .boolNot _ => "boolean"
  | _ => "u64"

/-- Lower one plan expression into typed Leo lets with failure guards at every
    checked node (the EVM statement-form discipline): operands are bound in
    order, `div`/`mod` get an explicit nonzero assert, shifts get an explicit
    `count < 64` assert. Checked add/sub/mul rely on Leo's native checked
    semantics (spike-verified halt-on-overflow). Returns (statements, value
    reference, ctx). -/
private partial def lowerExprStmt
    (ctx : EmitCtx) (expr : Expr) :
    CompileResult (Array LeoStatement × LeoExpr × EmitCtx) := do
  let leaf (leo : LeoExpr) : CompileResult (Array LeoStatement × LeoExpr × EmitCtx) :=
    pure (#[], leo, ctx)
  let bind (ty : String) (op : String) (l r : Expr) : CompileResult
      (Array LeoStatement × LeoExpr × EmitCtx) := do
    let (ls1, l', ctx1) ← lowerExprStmt ctx l
    let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
    let (name, ctx3) := freshName ctx2
    pure (ls1 ++ ls2 ++ #[.letBinding name ty (.binary op l' r')], .reference name, ctx3)
  match expr with
  | .literal value => leaf (.u64Literal value)
  | .boolLiteral value => leaf (.boolLiteral value)
  | .param inputIndex => leaf (.reference s!"p{inputIndex}")
  | .loopVar depth => leaf (.reference s!"pf_i{depth}")
  | .stateLoad fieldIndex =>
      leaf (.mappingGetOrUse s!"pf_state_{fieldIndex}" mappingKey (.u64Literal 0))
  | .checkedAdd l r => bind "u64" "+" l r
  | .checkedSub l r => bind "u64" "-" l r
  | .checkedMul l r => bind "u64" "*" l r
  | .checkedDiv l r | .checkedMod l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let op := match expr with | .checkedDiv _ _ => "/" | _ => "%"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "!=" r' (.u64Literal 0)),
          .letBinding name "u64" (.binary op l' r')],
        .reference name, ctx3)
  | .shl l r | .shr l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let op := match expr with | .shl _ _ => "<<" | _ => ">>"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "<" r' (.u64Literal 64)),
          .letBinding name "u64" (.binary op l' r')],
        .reference name, ctx3)
  | .compare op l r => do
      let yul := match op with
        | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
      bind "boolean" yul l r
  | .bitAnd l r => bind "u64" "&" l r
  | .bitOr l r => bind "u64" "|" l r
  | .bitXor l r => bind "u64" "^" l r
  | .logicalAnd l r => bind "boolean" "&&" l r
  | .logicalOr l r => bind "boolean" "||" l r
  | .bitNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "u64" (.unary "!" o')], .reference name, ctx2)
  | .boolNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "boolean" (.unary "!" o')], .reference name, ctx2)
  | .callFn fnName args => do
      let mut stmts : Array LeoStatement := #[]
      let mut args' : Array LeoExpr := #[]
      let mut ctx' := ctx
      for arg in args do
        let (ls, a', ctx1) ← lowerExprStmt ctx' arg
        stmts := stmts ++ ls
        args' := args'.push a'
        ctx' := ctx1
      let (name, ctx2) := freshName ctx'
      let leoType := exprLeoType expr
      pure (stmts ++ #[.letBinding name leoType (.call fnName args')], .reference name, ctx2)

/-- Lower a statement list into Leo. `isFinal` selects the return encoding:
    in final context a return expression is evaluated for failure semantics
    and dropped (`let pf_return = ...`); in proof context it is returned. -/
private partial def emitStatements
    (ctx : EmitCtx) (stmts : Array Statement) (loopDepth : Nat)
    (isFinal : Bool) : CompileResult (Array LeoStatement × EmitCtx) := do
  let mut out : Array LeoStatement := #[]
  let mut ctx := ctx
  for stmt in stmts do
    match stmt with
    | .store fieldIndex value => do
        let (exprStmts, leo, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts
        let mapping ← match ctx1.mappingNames[fieldIndex]? with
          | some m => pure m
          | none => planError "Aleo emission: store references a missing state field"
        out := out.push (.mappingSet mapping mappingKey leo)
        ctx := ctx1
    | .assert condition => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c']
        ctx := ctx1
    | .returnValue value => do
        let (exprStmts, leo, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts
        if isFinal then
          out := out.push (.letBinding "pf_return" (exprLeoType value) leo)
        else
          out := out.push (.returnValue leo)
        ctx := ctx1
    | .returnNone =>
        if isFinal then
          pure ()
        else
          out := out.push .returnUnit
    | .ifThenElse condition thenBody elseBody => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        let (thenStmts, ctx2) ← emitStatements ctx1 thenBody loopDepth isFinal
        let (elseStmts, ctx3) ← emitStatements ctx2 elseBody loopDepth isFinal
        out := out ++ exprStmts ++ #[.ifElse c' thenStmts elseStmts]
        ctx := ctx3
    | .switchOn scrutinee cases defaultBody => do
        let (exprStmts, s', ctx1) ← lowerExprStmt ctx scrutinee
        out := out ++ exprStmts
        let mut caseList : List (LeoExpr × Array LeoStatement) := []
        let mut ctx' := ctx1
        for (value, caseBody) in cases do
          let (caseStmts, ctx2) ← emitStatements ctx' caseBody loopDepth isFinal
          caseList := caseList ++ [((.binary "==" s' (.u64Literal value)), caseStmts)]
          ctx' := ctx2
        let (defaultStmts, ctx2) ← emitStatements ctx' defaultBody loopDepth isFinal
        ctx := ctx2
        -- Right-nested if/else chain: first matching case wins, else default.
        let combined := caseList.foldr
          (fun (cond, caseStmts) acc => #[.ifElse cond caseStmts acc]) defaultStmts
        out := out ++ combined
    | .forLoop start endExclusive maxIter body => do
        let (startStmts, sLeo, ctx1) ← lowerExprStmt ctx start
        let (endStmts, eLeo, ctx2) ← lowerExprStmt ctx1 endExclusive
        -- Deterministic per-depth names (readable + testable).
        let startName := s!"pf_start{loopDepth}"
        let endName := s!"pf_end{loopDepth}"
        let ctx3 := ctx2
        let ctx4 := ctx3
        let guardCond : LeoExpr :=
          .binary "<" (.reference startName) (.reference endName)
        let fits : LeoExpr :=
          .binary "<=" (.binary "-" (.reference endName) (.reference startName))
            (.u64Literal maxIter.toUInt64)
        let (bodyStmts, ctx5) ← emitStatements ctx4 body (loopDepth + 1) isFinal
        let indexName := s!"pf_c{loopDepth}"
        let iName := s!"pf_i{loopDepth}"
        let innerGuard : LeoExpr :=
          .binary "<" (.reference indexName)
            (.binary "-" (.reference endName) (.reference startName))
        let bodyInner :=
          #[.letBinding iName "u64" (.binary "+" (.reference startName) (.reference indexName))]
          ++ bodyStmts
        let loopStmt : LeoStatement :=
          .forConst indexName maxIter #[.ifElse innerGuard bodyInner #[]]
        out := out ++ startStmts ++ endStmts ++
          #[.letBinding startName "u64" sLeo, .letBinding endName "u64" eLeo,
            .ifElse guardCond #[.assert fits] #[], loopStmt]
        ctx := ctx5
    | .emitEvent .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .revertError _ args => do
        unless args.isEmpty do
          planError "Aleo does not support revert payloads"
        out := out.push (.assert (.boolLiteral false))
  pure (out, ctx)

/-- Does a proof-context statement list need a trailing default return (its
    last statement is control flow whose arms all returned)? -/
private def needsTrailingReturn (stmts : Array Statement) : Bool :=
  match stmts.back? with
  | none => true
  | some (.returnValue _) | some .returnNone => false
  | some _ => true

private def emitFunction (ctx : EmitCtx) (fn : PlanFunction) :
    CompileResult (LeoFunction × EmitCtx) := do
  let params := fn.params.map fun p => { name := s!"p{p.sourceIndex}", isBool := p.isBool }
  let isFinal := fn.touchesState
  let (body0, ctx1) ← emitStatements ctx fn.body 0 isFinal
  -- Proof-context functions whose last statement is control flow (all arms
  -- returned) get an unreachable trailing default return so Leo's checker
  -- accepts the function; it never executes.
  let body :=
    if isFinal then body0
    else if needsTrailingReturn fn.body then
      body0 ++ #[.returnValue (if fn.resultIsBool then .boolLiteral false else .u64Literal 0)]
    else body0
  -- Initialize: inject the one-shot guard + final set.
  let body' :=
    if fn.kind == .initialize then
      #[.letBinding "pf_seen" "boolean"
          (.mappingGetOrUse guardMappingName mappingKey (.boolLiteral false)),
        .assert (.unary "!" (.reference "pf_seen"))] ++ body ++
      #[.mappingSet guardMappingName mappingKey (.boolLiteral true)]
    else
      body
  pure ({
    name := fn.name
    params
    resultIsBool := fn.resultIsBool
    isFinal
    body := body'
  }, ctx1)

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let programId := asciiLower plan.programName
  unless isLeoProgramId programId do
    planError s!"'{plan.programName}' cannot form a legal Leo program id"
  let mappings := plan.stateFieldNames.mapIdx fun i _ => { name := s!"pf_state_{i}" }
  let ctx0 : EmitCtx := { next := 0, mappingNames := mappings.map (·.name) }
  let mut functions : Array LeoFunction := #[]
  let mut ctx := ctx0
  for fn in plan.functions do
    let (leoFn, ctx1) ← emitFunction ctx fn
    functions := functions.push leoFn
    ctx := ctx1
  let program := { programId, mappings, functions }
  validateLeoProgram program
  pure { sourcePlan := plan, program }

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let programId := ir.program.programId
  let source := renderProgram programId ir.program
  pure #[{
    path := s!"{programId}.aleo"
    mediaType := "text/plain"
    contents := source
  }]

/-- Capability-gated public IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry. Sole path from the retained
    SemanticProgramV1-native Aleo Plan body to emitted files for this target. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Aleo
