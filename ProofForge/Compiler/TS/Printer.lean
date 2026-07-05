/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

TypeScript AST printer — renders a `TS.Module` to TypeScript source text.

The output is intentionally formatted in a deterministic, readable style. It is
passed through the target toolchain (e.g. wrangler / TypeScript) which can
apply its own formatting if desired.
-/

import Init
import Init.Notation
import ProofForge.Compiler.TS.AST

namespace ProofForge.Compiler.TS.Printer

open ProofForge.Compiler.TS

/-- Two-space indent, repeated `n` times. -/
def indent (n : Nat) : String :=
  match n with
  | 0 => ""
  | n+1 => "  " ++ indent n

/-- Indent a single line. -/
def line (depth : Nat) (s : String) : String := indent depth ++ s ++ "\n"

/-- Render a type annotation. -/
def printType : Ty → String
  | .any => "any"
  | .void => "void"
  | .string => "string"
  | .number => "number"
  | .bigint => "bigint"
  | .boolean => "boolean"
  | .named name => name
  | .promise inner => "Promise<" ++ printType inner ++ ">"
  | .optional inner => printType inner ++ " | null"

/-- Render a literal value. -/
def printLit : Lit → String
  | .string s => "'" ++ s ++ "'"
  | .number n => toString n
  | .bigint n => toString n ++ "n"
  | .bool true => "true"
  | .bool false => "false"

/-- Render a binary operator. -/
def printBinOp : BinOp → String
  | .eq => "==="
  | .ne => "!=="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .and => "&&"
  | .or => "||"
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"

/-- Render a parameter with its type annotation. -/
def printParam (p : Param) : String :=
  p.name ++ ": " ++ printType p.type

/-- Render an optional type annotation suffix. -/
def printReturnType (type? : Option Ty) : String :=
  match type? with
  | some t => ": " ++ printType t
  | none => ""

mutual
  /-- Render an expression. -/
  partial def printExpr : Expr → String
    | .lit l => printLit l
    | .ident name => name
    | .member base field => printExprBase base ++ "." ++ field
    | .call callee args => printExprBase callee ++ "(" ++ printArgs args ++ ")"
    | .new callee args => "new " ++ printExprBase callee ++ "(" ++ printArgs args ++ ")"
    | .binary op lhs rhs => printExpr lhs ++ " " ++ printBinOp op ++ " " ++ printExpr rhs
    | .await e => "await " ++ printExpr e
    | .coalesce lhs rhs => printExpr lhs ++ " ?? " ++ printExpr rhs
    | .objectLit fields =>
        if fields.isEmpty then
          "{}"
        else
          let body := fields.foldl (fun acc (name, value) =>
            acc ++ "  " ++ name ++ ": " ++ printExpr value ++ ",\n") "\n"
          "{" ++ body ++ "}"
    | .paren e => "(" ++ printExpr e ++ ")"

  /-- Wrap binary/coalesce/await expressions in parentheses when used as the
      base of a member access, call, or `new` expression. -/
  partial def printExprBase (e : Expr) : String :=
    match e with
    | e@(.binary _ _ _) => "(" ++ printExpr e ++ ")"
    | e@(.coalesce _ _) => "(" ++ printExpr e ++ ")"
    | e@(.await _) => "(" ++ printExpr e ++ ")"
    | _ => printExpr e

  /-- Render a comma-separated argument list. -/
  partial def printArgs (args : Array Expr) : String :=
    String.intercalate ", " (args.toList.map printExpr)

  /-- Render a block of statements. -/
  partial def printBlock (depth : Nat) (stmts : Array Stmt) : String :=
    if stmts.isEmpty then
      "{}"
    else
      let body := stmts.foldl (fun acc s => acc ++ printStmt (depth + 1) s) ""
      "{\n" ++ body ++ indent depth ++ "}"

  /-- Render a statement. -/
  partial def printStmt (depth : Nat) : Stmt → String
    | .constDecl name type? init =>
        let ann := match type? with | some t => ": " ++ printType t | none => ""
        line depth s!"const {name}{ann} = {printExpr init};"
    | .letDecl name type? init =>
        let ann := match type? with | some t => ": " ++ printType t | none => ""
        line depth s!"let {name}{ann} = {printExpr init};"
    | .assign target value =>
        line depth s!"{printExpr target} = {printExpr value};"
    | .exprStmt e =>
        line depth s!"{printExpr e};"
    | .ifStmt cond thenBody elseBody? =>
        let head := indent depth ++ s!"if ({printExpr cond}) "
        let then_ := printBlock depth thenBody
        match elseBody? with
        | some elseBody => head ++ then_ ++ " else " ++ printBlock depth elseBody ++ "\n"
        | none => head ++ then_ ++ "\n"
    | .forLoop init cond step body =>
        let head := indent depth ++ s!"for ({printForClause init}; {printExpr cond}; {printForClause step}) "
        head ++ printBlock depth body ++ "\n"
    | .whileLoop cond body =>
        let head := indent depth ++ s!"while ({printExpr cond}) "
        head ++ printBlock depth body ++ "\n"
    | .return e =>
        line depth s!"return {printExpr e};"
    | .throw e =>
        line depth s!"throw {printExpr e};"

  /-- Render a `for`-loop init or step clause without a trailing newline/indent. -/
  partial def printForClause (s : Stmt) : String :=
    match s with
    | .letDecl name type? init =>
        let ann := match type? with | some t => ": " ++ printType t | none => ""
        s!"let {name}{ann} = {printExpr init}"
    | .constDecl name type? init =>
        let ann := match type? with | some t => ": " ++ printType t | none => ""
        s!"const {name}{ann} = {printExpr init}"
    | .assign target value => s!"{printExpr target} = {printExpr value}"
    | .exprStmt e => printExpr e
    | _ => (printStmt 0 s).trimAscii.toString
end

/-- Render a top-level declaration. -/
def printTopLevel : TopLevel → String
  | .exportInterface name fields =>
      let header := "export interface " ++ name ++ " {\n"
      let body := fields.foldl (fun acc (fname, ftype) =>
        acc ++ "  " ++ fname ++ ": " ++ printType ftype ++ ";\n") "\n"
      header ++ body ++ "}\n\n"
  | .functionDecl async exported name params returnType? body =>
      let exportKw := if exported then "export " else ""
      let asyncKw := if async then "async " else ""
      let paramsStr := String.intercalate ", " (params.toList.map printParam)
      let ret := printReturnType returnType?
      let header := exportKw ++ asyncKw ++ "function " ++ name ++ "(" ++ paramsStr ++ ")" ++ ret ++ " "
      header ++ printBlock 0 body ++ "\n\n"
  | .exportDefault expr =>
      "export default " ++ printExpr expr ++ ";\n"

/-- Render a full module to TypeScript source text. -/
def render (m : Module) : String :=
  m.items.foldl (fun acc item => acc ++ printTopLevel item) ""

end ProofForge.Compiler.TS.Printer
