import Lean
import ProofForgeV2.Core.Source

open Lean Parser Command

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

partial def decodeExpr : Syntax → Except String ProofForgeV2.Source.Expr
  | `(pfExpr| $value:num) =>
      let number := value.getNat
      if number > 18446744073709551615 then
        .error s!"UInt64 literal is out of range: {number}"
      else
        .ok <| .literal (UInt64.ofNat number)
  | `(pfExpr| $name:ident) => .ok <| .variable name.getId.toString
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      return .checkedAdd (← decodeExpr lhs) (← decodeExpr rhs)
  | _ => .error "unsupported portable expression"

def decodeStatement : Syntax → Except String ProofForgeV2.Source.Statement
  | `(pfStmt| $name:ident := $value:pfExpr) => do
      return .assign name.getId.toString (← decodeExpr value)
  | `(pfStmt| return $value:pfExpr) => do
      return .returnValue (← decodeExpr value)
  | `(pfStmt| call $callee:str) => .ok <| .synchronousCall callee.getString
  | _ => .error "unsupported portable statement"

private def decodeParams (params : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Param) :=
  params.mapM decodeParam

private def decodeStatements (statements : Array Syntax) :
    Except String (Array ProofForgeV2.Source.Statement) :=
  statements.mapM decodeStatement

def decodeItem : Syntax → Except String ProofForgeV2.Source.Item
  | `(pfItem| state $name:ident : $type:pfType) => do
      return .stateDecl { name := name.getId.toString, type := ← decodeType type }
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      return .initializer {
        params := ← decodeParams params
        body := ← decodeStatements statements
      }
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeType type
        mode := .mutate
        body := ← decodeStatements statements
      }
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do $statements:pfStmt*) => do
      return .entry {
        name := name.getId.toString
        params := ← decodeParams params
        result := ← decodeType type
        mode := .view
        body := ← decodeStatements statements
      }
  | _ => .error "unsupported portable program item"

def decodeProgramCommand (currentNamespace : Name) : Syntax →
    Except String ProofForgeV2.Source.Program
  | `(program $name:ident where $items:pfItem*) => do
      let shortName := name.getId.toString
      let qualifiedName := (currentNamespace ++ name.getId).toString
      let decodedItems ← items.mapM decodeItem
      let initializerCount : Nat := decodedItems.foldl (fun count item =>
        match item with | .initializer .. => count + 1 | _ => count) 0
      if initializerCount > 1 then
        throw "program may declare at most one initializer"
      return ProofForgeV2.Source.Program.buildQualified
        qualifiedName shortName decodedItems
  | _ => .error "expected a program declaration"

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
