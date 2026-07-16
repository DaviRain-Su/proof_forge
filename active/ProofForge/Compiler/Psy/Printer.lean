/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Psy AST printer — renders a `Lean.Compiler.Psy.Module` to `.psy` source text.

The `psy-dpn` counterpart of `ProofForge.Compiler.Yul.Printer` and
`ProofForge.Compiler.Wasm.Printer`: a pure structural renderer that takes a
target-side AST produced by the backend lowerer and emits reviewable `.psy`
source. Pure functional style — each printer takes an indent level and returns
the rendered text. The output is valid input for `dargo compile`/`dargo test`.

Layering: `Backend.Psy.IR` lowers portable contract IR → `Psy.Module`;
`Psy.Printer` renders `Psy.Module` → `.psy` source text. The printer performs
no IR resolution, validation, or state-shape reasoning — those decisions are
made on the lowerer side so the AST is self-describing.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Compiler.Psy.AST

namespace Lean.Compiler.Psy.Printer

open Lean.Compiler.Psy

/-- Indent prefix: four spaces per level, matching the existing Psy output. -/
def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

/-- Join non-empty lines with newlines. -/
def lines (xs : Array String) : String :=
  String.intercalate "\n" xs.toList

/-- Visibility prefix. -/
def visibilityPrefix (v : Visibility) : String :=
  match v with
  | .pub => "pub "
  | .priv => ""

/-- Binary operator spelling as printed in Psy source. -/
def binaryOpSymbol : BinaryOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .pow => "**"
  | .bitAnd => "&"
  | .bitOr => "|"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .boolAnd => "&&"
  | .boolOr => "||"

/-- Unary operator spelling. -/
def unaryOpSymbol : UnaryOp → String
  | .neg => "-"
  | .not => "!"

/-- Compound assignment operator spelling. -/
def assignOpSymbol : AssignOp → String
  | .add => "+="
  | .sub => "-="
  | .mul => "*="
  | .div => "/="
  | .mod => "%="
  | .bitAnd => "&="
  | .bitOr => "|="
  | .bitXor => "^="
  | .shiftLeft => "<<="
  | .shiftRight => ">>="

/-- The binary operator that corresponds to a compound assignment op, used when
the lowerer rewrites a Felt-backed U32 compound assignment into an explicit
`(target.get() as u32 OP value) as Felt` form. -/
def assignOpBinarySymbol : AssignOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .bitAnd => "&"
  | .bitOr => "|"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"

/-- Escape a string literal body for `assert(..., "message")` and `abort(...)`. -/
def stringLiteral (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

/-- Render a `Literal` to its Psy source text. -/
def literal : Literal → String
  | .u32 value => s!"{value}u32"
  | .felt value => toString value
  | .bool true => "true"
  | .bool false => "false"
  | .u8 value => toString value
  | .u128 value => toString value
  | .address value => toString value
  | .hash4 a b c d => s!"[{a}, {b}, {c}, {d}]"

/-- Render a `ContextField` to its Psy intrinsic call. -/
def contextFieldCall : ContextField → String
  | .userId => "get_user_id()"
  | .contractId => "get_contract_id()"
  | .checkpointId => "get_checkpoint_id()"

mutual
  /-- Render an expression at full precedence (no surrounding parens). -/
  partial def expr (e : Expr) : String :=
    match e with
    | .literal value => literal value
    | .local name => name
    | .arrayLit _ items =>
      let rendered := items.map expr
      s!"[{String.intercalate ", " rendered.toList}]"
    | .arrayGet array index => s!"{expr array}[{expr index}]"
    | .structLit typeName fields =>
      let rendered := fields.map fun (n, v) => s!"{n}: {expr v}"
      s!"new {typeName} " ++ "{" ++ s!" {String.intercalate ", " rendered.toList} " ++ "}"
    | .field base fieldName => s!"{expr base}.{fieldName}"
    | .binary lhs op rhs =>
      match op with
      | .add => s!"{expr lhs} + {expr rhs}"
      | .eq | .ne | .lt | .le | .gt | .ge | .boolAnd | .boolOr =>
        s!"({expr lhs} {binaryOpSymbol op} {expr rhs})"
      | _ => s!"{operandExpr lhs} {binaryOpSymbol op} {operandExpr rhs}"
    | .unary op rhs =>
      match op with
      | .not => s!"!({expr rhs})"
      | .neg => s!"-{operandExpr rhs}"
    | .cast value targetType => s!"{operandExpr value} as {targetType.text}"
    | .hashValue a b c d =>
      s!"[{expr a}, {expr b}, {expr c}, {expr d}]"
    | .hash preimage => s!"hash({expr preimage})"
    | .hashTwoToOne lhs rhs => s!"hash_two_to_one({expr lhs}, {expr rhs})"
    | .storageScalarRead stateId => s!"c.{stateId}.get()"
    | .storageMapContains stateId key => s!"c.{stateId}.contains({expr key})"
    | .storageMapGet stateId key => s!"c.{stateId}.get({expr key})"
    | .storageMapDelete stateId key => s!"c.{stateId}.remove({expr key})"
    | .storageMapInsert stateId key value =>
      s!"c.{stateId}.insert({expr key}, {expr value})"
    | .storageMapSet stateId key value =>
      s!"c.{stateId}.set({expr key}, {expr value})"
    | .storageArrayRead stateId index feltBackedU32 =>
      let base := s!"c.{stateId}[{expr index}].get()"
      if feltBackedU32 then s!"{base} as u32" else base
    | .storageArrayStructFieldRead stateId index fieldName =>
      s!"c.{stateId}[{expr index}].{fieldName}.get()"
    | .storageStructFieldRead stateId fieldName => s!"c.{stateId}.{fieldName}.get()"
    | .storagePathRead stateId path feltBackedU32 =>
      let pathStr := storagePathStr stateId path
      if feltBackedU32 then s!"{pathStr}.get() as u32" else s!"{pathStr}.get()"
    | .contextRead field => contextFieldCall field
    | .crosscallInvoke target methodId args =>
      s!"__invoke_sync#<Felt>({expr target}, {expr methodId}, [{String.intercalate ", " (args.map expr).toList}])"

  /-- Render an expression in operand position: wrap non-atomic expressions in
  parens to preserve precedence the way the existing lowerer does. -/
  partial def operandExpr (e : Expr) : String :=
    match e with
    | .literal _ => expr e
    | .local _ => expr e
    | .arrayGet _ _ => expr e
    | .field _ _ => expr e
    | .contextRead _ => expr e
    | .storageScalarRead _ => expr e
    | .storageMapContains _ _ => expr e
    | .storageMapGet _ _ => expr e
    | .storageMapDelete _ _ => expr e
    | .storageMapInsert _ _ _ => expr e
    | .storageMapSet _ _ _ => expr e
    | .storageArrayRead _ _ _ => expr e
    | .storageArrayStructFieldRead _ _ _ => expr e
    | .storageStructFieldRead _ _ => expr e
    | .storagePathRead _ _ _ => expr e
    | _ => s!"({expr e})"

  /-- Render a storage path as `c.<state><segments>`. -/
  partial def storagePathStr (stateId : Name) (path : Array StoragePathSegment) : String :=
    let segs := path.map fun
      | .field fieldName => s!".{fieldName}"
      | .index index => s!"[{expr index}]"
    s!"c.{stateId}{String.intercalate "" segs.toList}"
end

/-- Render a `StorageTarget` left-hand-side (used by assign/assignOp statements). -/
def storageTargetStr : StorageTarget → String
  | .scalar stateId => s!"c.{stateId}"
  | .structField stateId fieldName => s!"c.{stateId}.{fieldName}"
  | .arrayIndex stateId index _ => s!"c.{stateId}[{expr index}]"
  | .arrayStructField stateId index fieldName => s!"c.{stateId}[{expr index}].{fieldName}"
  | .path stateId path _ => storagePathStr stateId path

mutual
  /-- Render a statement at the given indent level, returning one or more lines. -/
  partial def stmt (level : Nat) (s : Stmt) : Array String :=
    match s with
    | .letBind name type value =>
      #[indent level s!"let {name}: {type.text} = {expr value};"]
    | .letMutBind name type value =>
      #[indent level s!"let mut {name}: {type.text} = {expr value};"]
    | .assign target value =>
      match target with
      | .arrayIndex _ _ true =>
        #[indent level s!"{storageTargetStr target} = {operandExpr value} as Felt;"]
      | .path _ _ true =>
        #[indent level s!"{storageTargetStr target} = {operandExpr value} as Felt;"]
      | _ => #[indent level s!"{storageTargetStr target} = {expr value};"]
    | .assignOp target op value =>
      match target with
      | .arrayIndex _ _ true =>
        let lhs := storageTargetStr target
        #[indent level s!"{lhs} = ({lhs}.get() as u32 {assignOpBinarySymbol op} {operandExpr value}) as Felt;"]
      | .path _ _ true =>
        let lhs := storageTargetStr target
        #[indent level s!"{lhs} = ({lhs}.get() as u32 {assignOpBinarySymbol op} {operandExpr value}) as Felt;"]
      | _ => #[indent level s!"{storageTargetStr target} {assignOpSymbol op} {expr value};"]
    | .localAssign target value =>
      #[indent level s!"{expr target} = {expr value};"]
    | .localAssignOp target op value =>
      #[indent level s!"{expr target} {assignOpSymbol op} {expr value};"]
    | .effect eff => effectStmt level eff
    | .assert condition message =>
      #[indent level s!"assert({expr condition}, {stringLiteral message});"]
    | .assertEq lhs rhs message =>
      #[indent level s!"assert_eq({expr lhs}, {expr rhs}, {stringLiteral message});"]
    | .ifElse condition thenBody elseIfs elseBody =>
      let thenLines := thenBody.flatMap (stmt (level + 1))
      let elseIfLines := elseIfs.flatMap fun (cond, body) =>
        #[indent level (s!"} else if {expr cond} " ++ "{")] ++ body.flatMap (stmt (level + 1))
      let elseLines := elseBody.flatMap (stmt (level + 1))
      let hasElse := !elseBody.isEmpty
      #[indent level (s!"if {expr condition} " ++ "{")]
        ++ thenLines
        ++ elseIfLines
        ++ (if hasElse then #[indent level "} else {"] ++ elseLines else #[])
        ++ #[indent level "};"]
    | .boundedFor indexName start stopExclusive body =>
      let bodyLines := body.flatMap (stmt (level + 1))
      #[indent level (s!"for {indexName} in {start}u32..{stopExclusive}u32 " ++ "{")]
        ++ bodyLines
        ++ #[indent level "}"]
    | .returnExpr value =>
      #[indent level s!"return {expr value};"]
    | .revert message =>
      #[indent level s!"abort({stringLiteral message});"]

  /-- Render an effect statement. -/
  partial def effectStmt (level : Nat) (eff : Effect) : Array String :=
    match eff with
    | .storageScalarWrite stateId value =>
      #[indent level s!"c.{stateId} = {expr value};"]
    | .storageScalarAssignOp stateId op value =>
      #[indent level s!"c.{stateId} {assignOpSymbol op} {expr value};"]
    | .storageArrayWrite stateId index value feltBackedU32 =>
      if feltBackedU32 then
        #[indent level s!"c.{stateId}[{expr index}] = {operandExpr value} as Felt;"]
      else
        #[indent level s!"c.{stateId}[{expr index}] = {expr value};"]
    | .storageArrayStructFieldWrite stateId index fieldName value =>
      #[indent level s!"c.{stateId}[{expr index}].{fieldName} = {expr value};"]
    | .storageStructFieldWrite stateId fieldName value =>
      #[indent level s!"c.{stateId}.{fieldName} = {expr value};"]
    | .storagePathWrite stateId path value feltBackedU32 =>
      let pathStr := storagePathStr stateId path
      if feltBackedU32 then
        #[indent level s!"{pathStr} = {operandExpr value} as Felt;"]
      else
        #[indent level s!"{pathStr} = {expr value};"]
    | .storagePathAssignOp stateId path op value =>
      let pathStr := storagePathStr stateId path
      #[indent level s!"{pathStr} {assignOpSymbol op} {expr value};"]
    | .storageMapInsert stateId key value =>
      #[indent level s!"c.{stateId}.insert({expr key}, {expr value});"]
    | .storageMapSet stateId key value =>
      #[indent level s!"c.{stateId}.set({expr key}, {expr value});"]
    | .storageMapDelete stateId key =>
      #[indent level s!"c.{stateId}.remove({expr key});"]
    | .eventEmit name fields =>
      let fieldStrs := fields.map fun (_, v) => expr v
      #[indent level s!"__emit([{String.intercalate ", " fieldStrs.toList}]); // event `{name}`"]
end

/-- Render a struct field declaration line. -/
def structFieldLine (field : StructField) : Array String :=
  let attrs := if field.isRef then #["#[ref]"] else #[]
  attrs ++ #[s!"{visibilityPrefix (if field.isPublic then .pub else .priv)}{field.id}: {field.type.text},"]

/-- Render a struct declaration block. -/
def structDecl (decl : StructDecl) : String :=
  let deriveLines := if decl.deriveStorage then #["#[derive(Storage)]"] else #[]
  let fieldLines := decl.fields.flatMap structFieldLine
  lines <| deriveLines ++
    #[s!"{visibilityPrefix (if decl.isPublic then .pub else .priv)}struct {decl.name} " ++ "{"] ++
    fieldLines.map (indent 1) ++
    #["}"]

/-- Render a storage declaration line inside the contract struct body. -/
def stateDeclLine (state : StateDecl) : Array String :=
  match state with
  | .scalar id type => #[s!"pub {id}: {type.text},"]
  | .structRef id type => #["#[ref]", s!"pub {id}: {type.text},"]
  | .map id keyType valueType capacity =>
    #[s!"pub {id}: Map<{keyType.text}, {valueType.text}, {capacity}u32>,"]
  | .array id elementType length feltBackedU32 =>
    if feltBackedU32 then
      #[s!"pub {id}: [Felt; {length}],"]
    else
      #[s!"pub {id}: [{elementType.text}; {length}],"]

/-- Render a method parameter list element. -/
def paramLine (param : Name × TypeName) : String :=
  s!"{param.fst}: {param.snd.text}"

/-- Render a contract method block. -/
def methodBlock (refName : Name) (m : Method) : String :=
  let returnSuffix := match m.returns with
    | none => ""
    | some type => s!" -> {type.text}"
  let paramList := m.params.map paramLine
  let header := indent 1 "#[contract_method]"
  let signature := indent 1
    (s!"pub fn {m.name}({String.intercalate ", " paramList.toList}){returnSuffix} " ++ "{")
  let newRef := indent 2 s!"let c = {refName}::new(ContractMetadata::current());"
  let bodyLines := m.body.flatMap (stmt 2)
  lines (#[header, signature, newRef] ++ bodyLines ++ #[indent 1 "}"])

/-- Render the `#[test]` entrypoint test block. -/
def testBlock (t : Test) : String :=
  lines <| #["#[test]", s!"fn {t.name}() " ++ "{"] ++ t.body.map (indent 1) ++ #["}", ""]

/-- Render a full Psy module to `.psy` source text. -/
def module (mod : Module) : String :=
  let structLines :=
    if mod.structs.isEmpty then #[]
    else #[String.intercalate "\n\n" (mod.structs.map structDecl).toList, ""]
  let stateLines := mod.state.flatMap stateDeclLine
  let methodBlocks := mod.methods.map (methodBlock mod.refName)
  let testLines := mod.test.body.map (indent 1)
  lines <|
    #[mod.headerComment, ""] ++
    structLines ++
    #["#[contract]", "#[derive(Storage)]", s!"pub struct {mod.contractName} " ++ "{"] ++
    stateLines.map (indent 1) ++
    #["}", "", s!"impl {mod.refName} " ++ "{"] ++
    methodBlocks ++
    #["}", "", "#[test]", s!"fn {mod.test.name}() " ++ "{"] ++ testLines ++ #["}", ""]

end Lean.Compiler.Psy.Printer