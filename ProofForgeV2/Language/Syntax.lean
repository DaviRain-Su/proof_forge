import Lean
import ProofForgeV2.Core.Source

open Lean Parser Command
open ProofForgeV2

namespace ProofForgeV2.Language

declare_syntax_cat pfType
syntax "UInt64" : pfType

declare_syntax_cat pfParam
syntax ident " : " pfType : pfParam
syntax "public " ident " : " pfType : pfParam
syntax "private " ident " : " pfType : pfParam

declare_syntax_cat pfExpr
syntax num : pfExpr
syntax ident : pfExpr
syntax:65 pfExpr:65 " + " pfExpr:66 : pfExpr

declare_syntax_cat pfStmt
syntax ident " := " pfExpr : pfStmt
syntax "return " pfExpr : pfStmt
syntax "call " str : pfStmt

declare_syntax_cat pfItem
syntax "state " ident " : " pfType : pfItem
syntax "init" "(" sepBy(pfParam, ", ") ")" " do" ppLine ppIndent(pfStmt*) : pfItem
syntax "entry " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine ppIndent(pfStmt*) : pfItem
syntax "view " ident "(" sepBy(pfParam, ", ") ")" " : " pfType " do" ppLine ppIndent(pfStmt*) : pfItem

syntax (name := programDecl) "program " ident " where" ppLine ppIndent(pfItem*) : command

/-- Maximum nodes in one portable decoder subtree, including its root. -/
def maxSyntaxNodes : Nat := 100000

/-- Maximum root-inclusive depth in one portable decoder subtree. -/
def maxSyntaxNesting : Nat := 256

/-- Count name components iteratively, returning `none` before exceeding `limit`. -/
def boundedNamePartCount (limit : Nat) (name : Name) : Option Nat := Id.run do
  let mut current := name
  let mut count := 0
  while current != .anonymous do
    if count >= limit then
      return none
    count := count + 1
    current := current.getPrefix
  return some count

/-- Iterative post-parser preflight over one portable Syntax subtree. This runs
before the recursive DSL decoder or macro expander; it does not protect Lean's
parser itself or impose an aggregate limit across multiple programs. -/
def preflightSyntax (root : Syntax) : CompileResult Unit := do
  let mut pending : Array (Syntax × Nat) := #[(root, 1)]
  let mut discovered := 1
  while !pending.isEmpty do
    let (current, nesting) := pending.back!
    pending := pending.pop
    if nesting > maxSyntaxNesting then
      throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
    match current with
    | .ident _ _ name _ =>
        if (boundedNamePartCount maxSyntaxNesting name).isNone then
          throw <| .resourceBound
            s!"portable identifier nesting exceeds limit {maxSyntaxNesting}"
    | _ => pure ()
    for child in current.getArgs do
      let childNesting := nesting + 1
      if childNesting > maxSyntaxNesting then
        throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
      if discovered >= maxSyntaxNodes then
        throw <| .resourceBound s!"portable syntax exceeds node limit {maxSyntaxNodes}"
      discovered := discovered + 1
      pending := pending.push (child, childNesting)

private def preflightForDecoder (stx : Syntax) : Except String Unit :=
  (preflightSyntax stx).mapError CompileError.render

/-- Decode the registered Lean syntax tree into the target-neutral source AST.
This function is also used by the non-elaborating CLI loader. -/
def decodeType : Syntax → Except String ProofForgeV2.Source.ValueType
  | `(pfType| UInt64) => .ok .u64
  | _ => .error "unsupported portable type"

def decodeParam : Syntax → Except String ProofForgeV2.Source.Param
  | `(pfParam| $name:ident : $type:pfType) => do
      return { name := name.getId.toString, type := ← decodeType type }
  | `(pfParam| public $name:ident : $type:pfType) => do
      return {
        name := name.getId.toString
        type := ← decodeType type
        visibility := .verifierVisible
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      return {
        name := name.getId.toString
        type := ← decodeType type
        visibility := .proverWitness
      }
  | _ => .error "unsupported portable parameter"

private partial def decodeExprUnchecked : Syntax → Except String ProofForgeV2.Source.Expr
  | `(pfExpr| $value:num) =>
      let number := value.getNat
      if number > 18446744073709551615 then
        .error s!"UInt64 literal is out of range: {number}"
      else
        .ok <| .literal (UInt64.ofNat number)
  | `(pfExpr| $name:ident) => .ok <| .variable name.getId.toString
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      return .checkedAdd (← decodeExprUnchecked lhs) (← decodeExprUnchecked rhs)
  | _ => .error "unsupported portable expression"

def decodeExpr (stx : Syntax) : Except String ProofForgeV2.Source.Expr := do
  preflightForDecoder stx
  decodeExprUnchecked stx

private def decodeStatementUnchecked : Syntax → Except String ProofForgeV2.Source.Statement
  | `(pfStmt| $name:ident := $value:pfExpr) => do
      return .assign name.getId.toString (← decodeExprUnchecked value)
  | `(pfStmt| return $value:pfExpr) => do
      return .returnValue (← decodeExprUnchecked value)
  | `(pfStmt| call $callee:str) => .ok <| .synchronousCall callee.getString
  | _ => .error "unsupported portable statement"

def decodeStatement (stx : Syntax) : Except String ProofForgeV2.Source.Statement := do
  preflightForDecoder stx
  decodeStatementUnchecked stx

private def decodeParams (params : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Param) :=
  params.mapM decodeParam

private def decodeStatementsUnchecked (statements : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Statement) :=
  statements.mapM decodeStatementUnchecked

private def decodeItemUnchecked : Syntax → Except String ProofForgeV2.Source.Item
  | `(pfItem| state $name:ident : $type:pfType) => do
      return .stateDecl { name := name.getId.toString, type := ← decodeType type }
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      return .initializer {
        params := ← decodeParams params
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeType type
        mode := .mutate
        body := ← decodeStatementsUnchecked statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeType type
        mode := .view
        body := ← decodeStatementsUnchecked statements
      }
  | _ => .error "unsupported portable program item"

def decodeItem (stx : Syntax) : Except String ProofForgeV2.Source.Item := do
  preflightForDecoder stx
  decodeItemUnchecked stx

private def decodeProgramCommandUnchecked (currentNamespace : Name) : Syntax →
    Except String ProofForgeV2.Source.Program
  | `(program $name:ident where $items:pfItem*) => do
      let shortName := name.getId.toString
      let qualifiedName := (currentNamespace ++ name.getId).toString
      let decodedItems ← items.mapM decodeItemUnchecked
      let initializerCount : Nat := decodedItems.foldl (fun count item =>
        match item with | .initializer .. => count + 1 | _ => count) 0
      if initializerCount > 1 then
        throw "program may declare at most one initializer"
      return ProofForgeV2.Source.Program.buildQualified
        qualifiedName shortName decodedItems
  | _ => .error "expected a program declaration"

/-- Bound the fully qualified identity before recursive `Name.toString`. -/
def preflightProgramIdentity (currentNamespace programName : Name) :
    CompileResult Unit := do
  let namespaceParts ←
    match boundedNamePartCount maxSyntaxNesting currentNamespace with
    | some count => .ok count
    | none => .error (.resourceBound
        s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")
  match boundedNamePartCount (maxSyntaxNesting - namespaceParts) programName with
  | some _ => .ok ()
  | none => .error (.resourceBound
      s!"portable program identity exceeds nesting limit {maxSyntaxNesting}")

def decodeProgramCommandChecked (currentNamespace : Name) (stx : Syntax) :
    CompileResult ProofForgeV2.Source.Program := do
  preflightSyntax stx
  match stx with
  | `(program $name:ident where $_items:pfItem*) =>
      preflightProgramIdentity currentNamespace name.getId
  | _ => pure ()
  match decodeProgramCommandUnchecked currentNamespace stx with
  | .ok contractProgram => .ok contractProgram
  | .error message => .error <| .invalidProgram message

def decodeProgramCommand (currentNamespace : Name) (stx : Syntax) :
    Except String ProofForgeV2.Source.Program :=
  (decodeProgramCommandChecked currentNamespace stx).mapError CompileError.render

private def expandType (type : Syntax) : MacroM (TSyntax `term) :=
  match type with
  | `(pfType| UInt64) => `(ProofForgeV2.Source.ValueType.u64)
  | _ => Macro.throwUnsupported

private def expandParam (param : Syntax) : MacroM (TSyntax `term) :=
  match param with
  | `(pfParam| $name:ident : $type:pfType) => do
      let typeExpr ← expandType type
      let nameLit := Syntax.mkStrLit name.getId.toString
      `({ name := $nameLit, type := $typeExpr : ProofForgeV2.Source.Param })
  | `(pfParam| public $name:ident : $type:pfType) => do
      let typeExpr ← expandType type
      let nameLit := Syntax.mkStrLit name.getId.toString
      `({ name := $nameLit, type := $typeExpr,
          visibility := ProofForgeV2.Source.Visibility.verifierVisible : ProofForgeV2.Source.Param })
  | `(pfParam| private $name:ident : $type:pfType) => do
      let typeExpr ← expandType type
      let nameLit := Syntax.mkStrLit name.getId.toString
      `({ name := $nameLit, type := $typeExpr,
          visibility := ProofForgeV2.Source.Visibility.proverWitness : ProofForgeV2.Source.Param })
  | _ => Macro.throwUnsupported

private partial def expandExpr (expr : Syntax) : MacroM (TSyntax `term) :=
  match expr with
  | `(pfExpr| $value:num) => `(ProofForgeV2.Source.Expr.literal (UInt64.ofNat $value))
  | `(pfExpr| $name:ident) =>
      let nameLit := Syntax.mkStrLit name.getId.toString
      `(ProofForgeV2.Source.Expr.variable $nameLit)
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      let lhsExpr ← expandExpr lhs
      let rhsExpr ← expandExpr rhs
      `(ProofForgeV2.Source.Expr.checkedAdd $lhsExpr $rhsExpr)
  | _ => Macro.throwUnsupported

private def expandStatement (statement : Syntax) : MacroM (TSyntax `term) :=
  match statement with
  | `(pfStmt| $name:ident := $value:pfExpr) => do
      let nameLit := Syntax.mkStrLit name.getId.toString
      let valueExpr ← expandExpr value
      `(ProofForgeV2.Source.Statement.assign $nameLit $valueExpr)
  | `(pfStmt| return $value:pfExpr) => do
      let valueExpr ← expandExpr value
      `(ProofForgeV2.Source.Statement.returnValue $valueExpr)
  | `(pfStmt| call $callee:str) =>
      `(ProofForgeV2.Source.Statement.synchronousCall $callee)
  | _ => Macro.throwUnsupported

private def expandStatements (statements : Array Syntax) : MacroM (TSyntax `term) := do
  let values ← statements.mapM expandStatement
  `(#[$[$values],*])

private def expandParams (params : Array Syntax) : MacroM (TSyntax `term) := do
  let values ← params.mapM expandParam
  `(#[$[$values],*])

private def expandItem (item : Syntax) : MacroM (TSyntax `term) :=
  match item with
  | `(pfItem| state $name:ident : $type:pfType) => do
      let nameLit := Syntax.mkStrLit name.getId.toString
      let typeExpr ← expandType type
      `(ProofForgeV2.Source.Item.stateDecl { name := $nameLit, type := $typeExpr })
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      let paramsExpr ← expandParams params
      let statementsExpr ← expandStatements statements
      `(ProofForgeV2.Source.Item.initializer { params := $paramsExpr, body := $statementsExpr })
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      let nameLit := Syntax.mkStrLit name.getId.toString
      let paramsExpr ← expandParams params
      let typeExpr ← expandType type
      let statementsExpr ← expandStatements statements
      `(ProofForgeV2.Source.Item.entry {
          name := $nameLit, params := $paramsExpr, result := $typeExpr,
          mode := ProofForgeV2.Source.EntryMode.mutate, body := $statementsExpr })
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      let nameLit := Syntax.mkStrLit name.getId.toString
      let paramsExpr ← expandParams params
      let typeExpr ← expandType type
      let statementsExpr ← expandStatements statements
      `(ProofForgeV2.Source.Item.entry {
          name := $nameLit, params := $paramsExpr, result := $typeExpr,
          mode := ProofForgeV2.Source.EntryMode.view, body := $statementsExpr })
  | _ => Macro.throwUnsupported

elab_rules : command
  | `(program $name:ident where $items:pfItem*) => do
      let currentNamespace ← getCurrNamespace
      let commandStx ← `(program $name:ident where $items:pfItem*)
      match decodeProgramCommand currentNamespace commandStx with
      | .error message => throwError message
      | .ok _ => pure ()
      let itemExprs ← Lean.Elab.liftMacroM <| items.mapM expandItem
      let qualifiedName := currentNamespace.append name.getId
      let sourceName := Syntax.mkStrLit name.getId.toString
      let qualifiedNameLit := Syntax.mkStrLit qualifiedName.toString
      let expanded ← `(@[proof_forge_program] def $name : ProofForgeV2.Source.Program :=
          ProofForgeV2.Source.Program.buildQualified $qualifiedNameLit $sourceName #[$[$itemExprs],*])
      Lean.Elab.Command.elabCommand expanded

initialize Lean.registerBuiltinAttribute {
  name := `proof_forge_program
  descr := "marks a declaration generated by the ProofForge V2 program DSL"
  add := fun _ _ _ => pure ()
}

end ProofForgeV2.Language
