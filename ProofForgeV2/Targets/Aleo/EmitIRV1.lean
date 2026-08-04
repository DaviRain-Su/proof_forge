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
  | i64Literal (value : UInt64)
  /-- Narrow unsigned literal (`bitWidth ∈ {8,16,32}`); renders as `NuN`. -/
  | uintLiteral (bitWidth : Nat) (value : UInt64)
  | boolLiteral (value : Bool)
  /-- T14 catalog v2 (BLS12-377): Leo `field` literal (`42field`). -/
  | fieldLiteral (value : UInt64)
  | reference (name : String)
  | unary (op : String) (inner : LeoExpr)
  | binary (op : String) (lhs rhs : LeoExpr)
  | ternary (condition thenValue elseValue : LeoExpr)
  /-- Leo cast `inner as ty` (required for shift counts: Leo only accepts u8/u16/u32). -/
  | cast (inner : LeoExpr) (toType : String)
  | mappingGetOrUse (mapping : String) (key : String) (default : LeoExpr)
  | call (name : String) (args : Array LeoExpr)
  /-- B-RET-ABI: Leo native tuple of preorder aggregate return leaves
      (`(a, b)` for a 2-leaf Struct). Arity ≥ 2 (Leo rejects unit `()`). -/
  | tuple (elems : Array LeoExpr)
  /-- N-ANON-RESULT: Leo fixed array `[e0, e1, …]` for anonymous
      `Array UInt64 N` returns. Arity ≥ 1. -/
  | array (elems : Array LeoExpr)
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
  /-- Int64 parameter (Leo `i64`); overrides the u64 default. -/
  isInt : Bool := false
  /-- Unsigned width: 0/64 → `u64`; 8/16/32 → native narrow. -/
  uintWidth : Nat := 0
  /-- T14 catalog v2 (BLS12-377): Leo `field` parameter. -/
  isField : Bool := false
  deriving BEq, Inhabited, Repr

structure LeoFunction where
  name : String
  params : Array LeoParam
  resultIsBool : Bool
  /-- Int64 result (Leo `i64`); overrides the u64 default. -/
  resultIsInt : Bool := false
  /-- Unsigned result width: 0/64 → `u64`; 8/16/32 → native narrow. -/
  resultUintWidth : Nat := 0
  /-- T14 catalog v2 (BLS12-377): Leo `field` result. -/
  resultIsField : Bool := false
  /-- B-RET-ABI / N-ANON-RESULT: aggregate return leaves (Leo surface on
      non-Final selected by `resultAggregateForm`). `none` for scalar. -/
  resultAggregateLeaves : Option (Array LeafAbiType) := none
  /-- Leo non-Final surface form for aggregate results. -/
  resultAggregateForm : AggregateReturnForm := .named
  /-- State-touching Final function (body runs in `return final { ... };`). -/
  isFinal : Bool
  /-- Semantic pureFn: emitted outside `program` without input modes. -/
  isHelper : Bool
  body : Array LeoStatement
  deriving BEq, Inhabited, Repr

/-- Leo mapping declaration. Values are `u64` or `i64` per the plan state
    leaf's signedness; keys stay `u8` (single-key pilot). -/
structure LeoMapping where
  name : String
  valueType : String
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
      -- Leo ENV03711001: program name must not contain the substring "aleo".
      let noAleoSubstring := (value.splitOn "aleo").length == 1
      isLower first &&
        rest.all (fun c => isLower c || isDigit c || c == '_') &&
        noAleoSubstring

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

private def renderType (isBool : Bool) (isInt : Bool := false) : String :=
  if isBool then "bool" else if isInt then "i64" else "u64"

/-- UInt64 literal (`42u64`). -/
private def renderLit (value : UInt64) : String :=
  s!"{value.toNat}u64"

/-- Int64 literal from a raw two's-complement bit pattern. Values whose top
    bit is set render as negative decimal (Leo rejects the unsigned spelling
    for i64); non-negative values render unsigned (equivalent). -/
private def renderIntLit (value : UInt64) : String :=
  if value >= UInt64.ofNat 9223372036854775808 then
    let magnitude : UInt64 := UInt64.ofNat (18446744073709551616 - value.toNat)
    s!"-{magnitude.toNat}i64"
  else
    s!"{value.toNat}i64"

/-- T14 catalog v2 (BLS12-377): Leo `field` literal (`42field`). The UInt64
    value is always a valid BLS12-377 Fr element (`< 2^64 < r ≈ 2^253`). -/
private def renderFieldLit (value : UInt64) : String :=
  s!"{value.toNat}field"

/-- Narrow unsigned literal (`42u8` / `42u16` / `42u32`). -/
private def renderUintLit (bitWidth : Nat) (value : UInt64) : String :=
  s!"{value.toNat}{leoUintTypeName bitWidth}"

private partial def renderExpr : LeoExpr → String
  | .u64Literal value => renderLit value
  | .fieldLiteral value => renderFieldLit value
  | .i64Literal value => renderIntLit value
  | .uintLiteral bitWidth value => renderUintLit bitWidth value
  | .boolLiteral value => if value then "true" else "false"
  | .reference name => name
  | .unary op inner => s!"({op}{renderExpr inner})"
  | .binary op lhs rhs => s!"({renderExpr lhs} {op} {renderExpr rhs})"
  | .ternary condition thenValue elseValue =>
      s!"({renderExpr condition} ? {renderExpr thenValue} : {renderExpr elseValue})"
  | .cast inner toType => s!"({renderExpr inner} as {toType})"
  | .mappingGetOrUse mapping key default =>
      s!"{mapping}.get_or_use({key}, {renderExpr default})"
  | .call name args =>
      let inner := args.toList.map renderExpr |> String.intercalate ", "
      s!"{name}({inner})"
  | .tuple elems =>
      let inner := elems.toList.map renderExpr |> String.intercalate ", "
      s!"({inner})"
  | .array elems =>
      let inner := elems.toList.map renderExpr |> String.intercalate ", "
      s!"[{inner}]"

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
      -- Leo 4.0.2 rejects `return ()` (tuple arity ≥ 2); bare `return;` is unit.
      s!"{indentStr depth}return;\n"
  | .ifElse condition thenBody elseBody =>
      -- Self-balanced: one `{` opens, one `}` closes. (Historical emission
      -- used `}}`, which only parsed when the if was the final statement of
      -- the `return final { ... }` block; an if-else arm or a trailing
      -- statement after the if broke the block balance. `leo build` is the
      -- final authority; both shapes verified.)
      s!"{indentStr depth}if {renderExpr condition} \{\n" ++
      renderStatements (depth + 2) thenBody ++
      (if elseBody.isEmpty then
         s!"{indentStr depth}}\n"
       else
         s!"{indentStr depth}} else \{\n" ++
         renderStatements (depth + 2) elseBody ++
         s!"{indentStr depth}}\n")
  | .forConst index bound body =>
      -- Self-balanced: one `{` opens, one `}` closes (same fix as ifElse:
      -- the historical extra `}` only parsed when the for was the final
      -- statement of the enclosing `return final { ... }` block).
      s!"{indentStr depth}for {index} in 0u64..{bound}u64 \{\n" ++
      renderStatements (depth + 2) body ++
      s!"{indentStr depth}}\n"

end

/-- Entry-point params are `public`; helpers outside `program` cannot take modes. -/
private def renderParam (isHelper : Bool) (param : LeoParam) : String :=
  let ty := if param.isBool then "bool"
    else if param.isInt then "i64"
    else if param.isField then "field"
    else leoUintTypeName param.uintWidth
  if isHelper then s!"{param.name}: {ty}" else s!"public {param.name}: {ty}"

/-- Indent: helpers at column 0 (file-level); entry/Final inside program at 4. -/
private def renderFunction : LeoFunction → String
  | fn =>
      let indent := if fn.isHelper then "" else "    "
      let bodyIndent := if fn.isHelper then 4 else 4
      let signature :=
        (fn.params.toList.map (renderParam fn.isHelper)) |> String.intercalate ", "
      let resultTy :=
        if fn.isFinal then "Final"
        else
          match fn.resultAggregateLeaves with
          | some leaves =>
              match fn.resultAggregateForm with
              | .array =>
                  -- N-ANON-RESULT: honest Leo fixed array `[u64; N]`.
                  s!"[u64; {leaves.size}]"
              | .option =>
                  -- N-ANON-RESULT: tag is Leo bool, payload is u64.
                  "(bool, u64)"
              | .named =>
                  -- B-RET-ABI: Leo native tuple of leaf types in preorder.
                  let parts := leaves.toList.map fun leaf =>
                    if leaf.isInt then "i64" else "u64"
                  "(" ++ String.intercalate ", " parts ++ ")"
          | none =>
              if fn.resultIsBool then "bool"
              else if fn.resultIsInt then "i64"
              else if fn.resultIsField then "field"
              else leoUintTypeName fn.resultUintWidth
      let body := renderStatements bodyIndent fn.body
      s!"{indent}fn {fn.name}({signature}) -> {resultTy} \{\n" ++
      (if fn.isFinal then
         -- Leo 4.0.2 requires a trailing semicolon after `return final { ... }`.
         s!"{indent}    return final \{\n{body}{indent}    };\n"
       else
         body) ++
      s!"{indent}}\n\n"

private def renderProgram (programId : String) (program : LeoProgram) : String :=
  let helpers := program.functions.filter (·.isHelper)
  let entries := program.functions.filter (fun f => !f.isHelper)
  let helperSrc := helpers.toList.map renderFunction |> String.intercalate ""
  let mappings := (program.mappings.toList.map fun m =>
    s!"    mapping {m.name}: u8 => {m.valueType};") |> String.intercalate "\n"
  let entrySrc := entries.toList.map renderFunction |> String.intercalate ""
  s!"// Generated by proof-forge-next (Aleo target, Leo {leoToolchain}).\n" ++
  helperSrc ++
  s!"program {programId}.aleo \{\n" ++
  s!"    @noupgrade\n" ++
  -- Closed empty constructor; mappings/functions are program-level members.
  s!"    constructor() \{}\n\n" ++
  (if mappings.isEmpty then "" else mappings ++ "\n\n") ++
  s!"    mapping {guardMappingName}: u8 => bool;\n\n" ++
  entrySrc ++
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

/-- Statement lowering context: fresh-name counter, the mapping name for
    each state field, each state leaf's Int64/UInt8 flags, the current
    function's param signedness, and the callee result signedness table.
    Mapping names are generated (`pf_state_{i}`), so DSL state names cannot
    collide with Leo mapping-method vocabulary. -/
private structure EmitCtx where
  next : Nat
  mappingNames : Array String
  /-- Int64 flag per state leaf (index-aligned with `mappingNames`). -/
  stateLeafIsInt : Array Bool
  /-- Unsigned width per state leaf (0/64 = u64; 8/16/32 = narrow). -/
  stateLeafUintWidth : Array Nat := #[]
  /-- T14 catalog v2 (BLS12-377): Leo `field` flag per state leaf. -/
  stateLeafIsField : Array Bool := #[]
  /-- Int64 flag per callable param (index-aligned with source param order). -/
  paramIsInt : Array Bool := #[]
  /-- Unsigned width per callable param (0/64 = u64; 8/16/32 = narrow). -/
  paramUintWidth : Array Nat := #[]
  /-- T14 catalog v2 (BLS12-377): Leo `field` flag per callable param. -/
  paramIsField : Array Bool := #[]
  /-- Helper result meta: `(name, isInt, uintWidth)`. Unknown → u64. -/
  helperResultMetaByName : Array (String × Bool × Nat) := #[]
  /-- Current function's aggregate return form (drives returnAggregate Emit). -/
  aggregateForm : AggregateReturnForm := .named
  deriving Inhabited

private def freshName (ctx : EmitCtx) : String × EmitCtx :=
  (s!"pf_e{ctx.next}", { ctx with next := ctx.next + 1 })

/-- The Leo type of a plan expression. Signed arithmetic/comparison results
    are `i64`; Bool results are `bool`; narrow UInt results are `uN`;
    everything else is `u64`. Param/stateLoad/callFn need the ctx tables. -/
private def exprLeoTypeCtx (ctx : EmitCtx) : Expr → String
  | .boolLiteral _ => "bool"
  | .compare _ _ _ => "bool"
  | .signedCompare _ _ _ => "bool"
  | .fieldCompare _ _ _ => "bool"
  | .logicalAnd _ _ | .logicalOr _ _ => "bool"
  | .boolNot _ => "bool"
  | .i64Literal _ => "i64"
  | .uintLiteral bitWidth _ => leoUintTypeName bitWidth
  | .fieldLiteral _ => "field"
  | .fieldBinary _ _ _ => "field"
  | .fieldNeg _ => "field"
  | .narrowCheckedAdd w _ _ | .narrowCheckedSub w _ _ | .narrowCheckedMul w _ _
  | .narrowCheckedDiv w _ _ | .narrowCheckedMod w _ _
  | .narrowBitAnd w _ _ | .narrowBitOr w _ _ | .narrowBitXor w _ _
  | .narrowShl w _ _ | .narrowShr w _ _ | .narrowBitNot w _ =>
      leoUintTypeName w
  | .signedCheckedAdd _ _ | .signedCheckedSub _ _ | .signedCheckedMul _ _
  | .signedCheckedDiv _ _ | .signedCheckedMod _ _ | .signedShl _ _
  | .signedShr _ _ | .checkedNeg _ | .signedBitNot _ => "i64"
  | .signedBitAnd _ _ | .signedBitOr _ _ | .signedBitXor _ _ => "i64"
  | .ternary _ t _ => exprLeoTypeCtx ctx t
  | .param inputIndex =>
      if ctx.paramIsInt.getD inputIndex false then "i64"
      else if ctx.paramIsField.getD inputIndex false then "field"
      else leoUintTypeName (ctx.paramUintWidth.getD inputIndex 0)
  | .stateLoad fieldIndex =>
      if ctx.stateLeafIsInt.getD fieldIndex false then "i64"
      else if ctx.stateLeafIsField.getD fieldIndex false then "field"
      else leoUintTypeName (ctx.stateLeafUintWidth.getD fieldIndex 0)
  | .callFn fnName _args =>
      match ctx.helperResultMetaByName.findSome? (fun (n, isInt, w) =>
          if n == fnName then some (isInt, w) else none) with
      | some (true, _) => "i64"
      | some (false, w) => leoUintTypeName w
      | none => "u64"
  | _ => "u64"

/-- Leo default literal for a state leaf (u64/uN/i64/field). -/
private def stateDefault
    (isInt : Bool) (isField : Bool := false) (uintWidth : Nat := 0) : LeoExpr :=
  if isField then .fieldLiteral 0
  else if isInt then .i64Literal 0
  else if isNarrowUintWidth uintWidth then .uintLiteral uintWidth 0
  else .u64Literal 0

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
  let bindSigned (op : String) (l r : Expr) : CompileResult
      (Array LeoStatement × LeoExpr × EmitCtx) :=
    bind "i64" op l r
  match expr with
  | .literal value => leaf (.u64Literal value)
  | .i64Literal value => leaf (.i64Literal value)
  | .uintLiteral bitWidth value => leaf (.uintLiteral bitWidth value)
  | .boolLiteral value => leaf (.boolLiteral value)
  | .fieldLiteral value => leaf (.fieldLiteral value)
  | .param inputIndex => leaf (.reference s!"p{inputIndex}")
  | .loopVar depth => leaf (.reference s!"pf_i{depth}")
  | .stateLoad fieldIndex =>
      let isInt := ctx.stateLeafIsInt.getD fieldIndex false
      let isField := ctx.stateLeafIsField.getD fieldIndex false
      let w := ctx.stateLeafUintWidth.getD fieldIndex 0
      leaf (.mappingGetOrUse s!"pf_state_{fieldIndex}" mappingKey
        (stateDefault isInt isField w))
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
  | .narrowCheckedAdd w l r => bind (leoUintTypeName w) "+" l r
  | .narrowCheckedSub w l r => bind (leoUintTypeName w) "-" l r
  | .narrowCheckedMul w l r => bind (leoUintTypeName w) "*" l r
  | .narrowCheckedDiv w l r | .narrowCheckedMod w l r => do
      -- leo 4.0.2 traps on div/mod by zero for native uN (same as u64 path's
      -- explicit assert; keep the assert for a stable, portable failure shape).
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let ty := leoUintTypeName w
      let op := match expr with | .narrowCheckedDiv _ _ _ => "/" | _ => "%"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "!=" r' (.uintLiteral w 0)),
          .letBinding name ty (.binary op l' r')],
        .reference name, ctx3)
  | .narrowBitAnd w l r => bind (leoUintTypeName w) "&" l r
  | .narrowBitOr w l r => bind (leoUintTypeName w) "|" l r
  | .narrowBitXor w l r => bind (leoUintTypeName w) "^" l r
  | .narrowShl w l r | .narrowShr w l r => do
      -- Wire invalidShift at count ≥ bitWidth. Count arrives as UInt32
      -- (possibly on the u32 or u64 lane); assert then cast to u8 for Leo.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (countName, ctx3) := freshName ctx2
      let (name, ctx4) := freshName ctx3
      let ty := leoUintTypeName w
      let op := match expr with | .narrowShl _ _ _ => "<<" | _ => ">>"
      -- Compare count against a same-type zero-extended bound: cast count to
      -- u64 for the guard so UInt32-lane counts compare cleanly.
      let (countU64, ctx5) := freshName ctx4
      pure (ls1 ++ ls2 ++
        #[.letBinding countU64 "u64" (.cast r' "u64"),
          .assert (.binary "<" (.reference countU64) (.u64Literal w.toUInt64)),
          .letBinding countName "u8" (.cast (.reference countU64) "u8"),
          .letBinding name ty (.binary op l' (.reference countName))],
        .reference name, ctx5)
  | .narrowBitNot w operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name (leoUintTypeName w) (.unary "!" o')],
        .reference name, ctx2)
  | .signedCheckedAdd l r => bindSigned "+" l r
  | .signedCheckedSub l r => bindSigned "-" l r
  | .signedCheckedMul l r => bindSigned "*" l r
  | .signedCheckedDiv l r | .signedCheckedMod l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let op := match expr with | .signedCheckedDiv _ _ => "/" | _ => "%"
      pure (ls1 ++ ls2 ++
        #[.assert (.binary "!=" r' (.i64Literal 0)),
          .letBinding name "i64" (.binary op l' r')],
        .reference name, ctx3)
  | .shl l r | .shr l r => do
      -- Leo 4.0.2 shift count must be u8/u16/u32 (not u64). Wire count is
      -- UInt32 (native u32 lane after T8); cast to u64 for the bound guard,
      -- then to u8 for the shift operator.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (countU64, ctx3) := freshName ctx2
      let (countName, ctx4) := freshName ctx3
      let (name, ctx5) := freshName ctx4
      let op := match expr with | .shl _ _ => "<<" | _ => ">>"
      pure (ls1 ++ ls2 ++
        #[.letBinding countU64 "u64" (.cast r' "u64"),
          .assert (.binary "<" (.reference countU64) (.u64Literal 64)),
          .letBinding countName "u8" (.cast (.reference countU64) "u8"),
          .letBinding name "u64" (.binary op l' (.reference countName))],
        .reference name, ctx5)
  | .signedShl l r | .signedShr l r => do
      -- Int64 shifts: same u8 count cast; Leo `>>` on i64 is arithmetic
      -- (sign-propagating), matching the wire Int64 semantics.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (countU64, ctx3) := freshName ctx2
      let (countName, ctx4) := freshName ctx3
      let (name, ctx5) := freshName ctx4
      let op := match expr with | .signedShl _ _ => "<<" | _ => ">>"
      pure (ls1 ++ ls2 ++
        #[.letBinding countU64 "u64" (.cast r' "u64"),
          .assert (.binary "<" (.reference countU64) (.u64Literal 64)),
          .letBinding countName "u8" (.cast (.reference countU64) "u8"),
          .letBinding name "i64" (.binary op l' (.reference countName))],
        .reference name, ctx5)
  | .compare op l r => do
      let yul := match op with
        | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
      bind "bool" yul l r
  | .signedCompare op l r => do
      -- Leo's native i64 comparison is signed (type-directed).
      let yul := match op with
        | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
      bind "bool" yul l r
  | .fieldBinary op l r => do
      -- T14 catalog v2 (BLS12-377): native Leo `field` arithmetic (exact mod
      -- BLS12-377 Fr; no checked-overflow guard).
      let leoOp := match op with
        | .add => "+" | .sub => "-" | .mul => "*" | .div => "/"
      bind "field" leoOp l r
  | .fieldCompare op l r => do
      let leoOp := match op with
        | .eq => "==" | .ne => "!="
        | _ => "=="  -- unreachable: Normalize rejects Field ordering
      bind "bool" leoOp l r
  | .fieldNeg operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "field" (.binary "-" (.fieldLiteral 0) o')],
        .reference name, ctx2)
  | .bitAnd l r => bind "u64" "&" l r
  | .bitOr l r => bind "u64" "|" l r
  | .bitXor l r => bind "u64" "^" l r
  | .signedBitAnd l r => bind "i64" "&" l r
  | .signedBitOr l r => bind "i64" "|" l r
  | .signedBitXor l r => bind "i64" "^" l r
  | .logicalAnd l r => bind "bool" "&&" l r
  | .logicalOr l r => bind "bool" "||" l r
  | .bitNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "u64" (.unary "!" o')], .reference name, ctx2)
  | .signedBitNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "i64" (.unary "!" o')], .reference name, ctx2)
  | .boolNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "bool" (.unary "!" o')], .reference name, ctx2)
  | .checkedNeg operand => do
      -- Int64 negation: Leo's native checked neg reverts on intMin
      -- (spike-verified constraint failure); no extra guard needed.
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBinding name "i64" (.unary "-" o')], .reference name, ctx2)
  | .ternary condition thenValue elseValue => do
      -- Leo ternary `(cond ? thenV : elseV)`; arms must share a type. The
      -- Map-pilot selectors pass Bool conditions and same-typed arms.
      let (ls1, c', ctx1) ← lowerExprStmt ctx condition
      let (ls2, t', ctx2) ← lowerExprStmt ctx1 thenValue
      let (ls3, e', ctx3) ← lowerExprStmt ctx2 elseValue
      let (name, ctx4) := freshName ctx3
      let leoType := exprLeoTypeCtx ctx3 thenValue
      pure (ls1 ++ ls2 ++ ls3 ++
        #[.letBinding name leoType (.ternary c' t' e')], .reference name, ctx4)
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
      let leoType := exprLeoTypeCtx ctx' expr
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
    | .storeAggregate leaves => do
        -- Two-phase snapshot: lower every leaf Expr first so nested
        -- stateLoad → mappingGetOrUse sees the pre-store live mapping
        -- (Map upsert cross-reads sibling leaves). Then emit all sets.
        -- Sequential per-leaf store would interleave set with later get.
        unless leaves.size > 0 do
          planError "Aleo emission: storeAggregate has no leaves"
        let mut prepared : Array (String × LeoExpr) := #[]
        let mut ctx' := ctx
        for store in leaves do
          let (exprStmts, leo, ctx1) ← lowerExprStmt ctx' store.value
          out := out ++ exprStmts
          let mapping ← match ctx1.mappingNames[store.fieldIndex]? with
            | some m => pure m
            | none => planError "Aleo emission: storeAggregate references a missing state field"
          prepared := prepared.push (mapping, leo)
          ctx' := ctx1
        for item in prepared do
          let (mapping, leo) := item
          out := out.push (.mappingSet mapping mappingKey leo)
        ctx := ctx'
    | .assert condition => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c']
        ctx := ctx1
    | .returnValue value => do
        let (exprStmts, leo, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts
        if isFinal then
          out := out.push (.letBinding "pf_return" (exprLeoTypeCtx ctx value) leo)
        else
          out := out.push (.returnValue leo)
        ctx := ctx1
    | .returnAggregate leaves leafIsInt => do
        -- B-RET-ABI / N-ANON-RESULT: lower each leaf expr, then either drop
        -- (Final) or return the form-selected Leo surface (non-Final).
        unless leaves.size > 0 && leaves.size ≤ 8 do
          planError "Aleo emission: returnAggregate leaf count must be in 1..8"
        unless leafIsInt.size == leaves.size do
          planError "Aleo emission: returnAggregate leafIsInt length must match leaves"
        let mut leos : Array LeoExpr := #[]
        let mut ctx' := ctx
        for leaf in leaves do
          let (exprStmts, leo, ctx1) ← lowerExprStmt ctx' leaf
          out := out ++ exprStmts
          leos := leos.push leo
          ctx' := ctx1
        if isFinal then
          -- Final model cannot return a value; evaluate each leaf for
          -- failure semantics (same discipline as scalar pf_return).
          -- Option tag stays a u64 0/1 here (no bool surface on Final).
          for i in [0:leos.size] do
            let some leo := leos[i]? |
              planError "Aleo emission: returnAggregate leaf missing"
            let ty := if leafIsInt.getD i false then "i64" else "u64"
            out := out.push (.letBinding s!"pf_return_{i}" ty leo)
        else
          -- Form is threaded via EmitCtx from the enclosing function.
          match ctx'.aggregateForm with
          | .array =>
              out := out.push (.returnValue (.array leos))
          | .option =>
              unless leos.size == 2 do
                planError "Aleo emission: option return requires exactly 2 leaves"
              let some tag := leos[0]? |
                planError "Aleo emission: option tag leaf missing"
              let some payload := leos[1]? |
                planError "Aleo emission: option payload leaf missing"
              -- Plan carries tag as u64 0/1; Leo option surface is bool.
              let tagBool : LeoExpr :=
                match tag with
                | .u64Literal 0 => .boolLiteral false
                | .u64Literal 1 => .boolLiteral true
                | _ => .binary "!=" tag (.u64Literal 0)
              out := out.push (.returnValue (.tuple #[tagBool, payload]))
          | .named =>
              out := out.push (.returnValue (.tuple leos))
        ctx := ctx'
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
        -- Case literals must match the scrutinee Leo type (u8/u16/u32/u64).
        let sty := exprLeoTypeCtx ctx1 scrutinee
        let caseLit (value : UInt64) : LeoExpr :=
          match sty with
          | "u8" => .uintLiteral 8 value
          | "u16" => .uintLiteral 16 value
          | "u32" => .uintLiteral 32 value
          | "bool" => .boolLiteral (value != 0)
          | _ => .u64Literal value
        let mut caseList : List (LeoExpr × Array LeoStatement) := []
        let mut ctx' := ctx1
        for (value, caseBody) in cases do
          let (caseStmts, ctx2) ← emitStatements ctx' caseBody loopDepth isFinal
          caseList := caseList ++ [((.binary "==" s' (caseLit value)), caseStmts)]
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
        -- Loop start/end are UInt64 by construction (bounded-for induction
        -- stays on the UInt64 lane), so u64 bindings are correct here.
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
  | some (.returnValue _) | some (.returnAggregate ..) | some .returnNone => false
  | some _ => true

/-- Unreachable default return value for a non-Final function (control-flow
    arms already returned on every path). -/
private def defaultReturnExpr (fn : PlanFunction) : LeoExpr :=
  match fn.resultAggregateLeaves with
  | some leaves =>
      match fn.resultAggregateForm with
      | .array =>
          .array (leaves.map fun _ => .u64Literal 0)
      | .option =>
          .tuple #[.boolLiteral false, .u64Literal 0]
      | .named =>
          .tuple (leaves.map fun leaf =>
            if leaf.isInt then .i64Literal 0 else .u64Literal 0)
  | none =>
      if fn.resultIsBool then .boolLiteral false
      else if fn.resultIsInt then .i64Literal 0
      else if fn.resultIsField then .fieldLiteral 0
      else if isNarrowUintWidth fn.resultUintWidth then
        .uintLiteral fn.resultUintWidth 0
      else .u64Literal 0

private def emitFunction (ctx : EmitCtx) (fn : PlanFunction) :
    CompileResult (LeoFunction × EmitCtx) := do
  let params := fn.params.map fun p =>
    { name := s!"p{p.sourceIndex}", isBool := p.isBool, isInt := p.isInt,
      uintWidth := p.uintWidth, isField := p.isField }
  -- Per-function param width/signedness tables for expression typing.
  let ctxFn := { ctx with
    paramIsInt := fn.params.map (·.isInt)
    paramUintWidth := fn.params.map (·.uintWidth)
    paramIsField := fn.params.map (·.isField)
    aggregateForm := fn.resultAggregateForm
  }
  let isFinal := fn.touchesState
  let isHelper := fn.isPureHelper
  -- Helpers cannot be Final / touch mappings (Leo places them outside program).
  if isHelper && isFinal then
    planError "Aleo pure helper cannot touch state (Leo helpers are outside program)"
  -- Helpers cannot return aggregates (B-RET-ABI pureFn stay scalar).
  if isHelper && fn.resultAggregateLeaves.isSome then
    planError "Aleo pure helper cannot return an aggregate (B-RET-ABI)"
  let (body0, ctx1) ← emitStatements ctxFn fn.body 0 isFinal
  -- Proof-context functions whose last statement is control flow (all arms
  -- returned) get an unreachable trailing default return so Leo's checker
  -- accepts the function; it never executes.
  let body :=
    if isFinal then body0
    else if needsTrailingReturn fn.body then
      body0 ++ #[.returnValue (defaultReturnExpr fn)]
    else body0
  -- Initialize: inject the one-shot guard + final set.
  let body' :=
    if fn.kind == .initialize then
      #[.letBinding "pf_seen" "bool"
          (.mappingGetOrUse guardMappingName mappingKey (.boolLiteral false)),
        .assert (.unary "!" (.reference "pf_seen"))] ++ body ++
      #[.mappingSet guardMappingName mappingKey (.boolLiteral true)]
    else
      body
  pure ({
    name := fn.name
    params
    resultIsBool := fn.resultIsBool
    resultIsInt := fn.resultIsInt
    resultUintWidth := fn.resultUintWidth
    resultIsField := fn.resultIsField
    resultAggregateLeaves := fn.resultAggregateLeaves
    resultAggregateForm := fn.resultAggregateForm
    isFinal
    isHelper
    body := body'
  }, ctx1)

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let programId := asciiLower plan.programName
  unless isLeoProgramId programId do
    planError s!"'{plan.programName}' cannot form a legal Leo program id"
  let mappings := plan.stateFieldNames.mapIdx fun i _ => {
    name := s!"pf_state_{i}"
    valueType :=
      if plan.stateFieldIsInt.getD i false then "i64"
      else if plan.stateFieldIsField.getD i false then "field"
      else leoUintTypeName (plan.stateFieldUintWidth.getD i 0)
  }
  let ctx0 : EmitCtx := {
    next := 0
    mappingNames := mappings.map (·.name)
    stateLeafIsInt := plan.stateFieldIsInt
    stateLeafUintWidth := plan.stateFieldUintWidth
    stateLeafIsField := plan.stateFieldIsField
    helperResultMetaByName :=
      plan.functions.filter (·.isPureHelper) |>.map fun h =>
        (h.name, h.resultIsInt, h.resultUintWidth)
  }
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
