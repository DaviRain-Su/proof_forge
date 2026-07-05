/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

TypeScript AST subset for Cloudflare Workers source generation.

This is intentionally a small, purpose-built AST: it only models the TypeScript
constructs that ProofForge's portable IR lowers to for a Workers backend. It is
not a general-purpose TypeScript parser or full-language printer.
-/
module

prelude
public import Init.Prelude
public import Init.Data.Repr
import Init.Data.Array.Basic
import Init.Data.String.Basic

public section

namespace ProofForge.Compiler.TS

/-- TypeScript type expressions used by the generated worker. -/
inductive Ty where
  | any
  | void
  | string
  | number
  | bigint
  | boolean
  | named (name : String)
  | promise (inner : Ty)
  | optional (inner : Ty)
  deriving BEq, Repr

/-- Function parameter with an explicit type annotation. -/
structure Param where
  name : String
  type : Ty
  deriving BEq, Repr

/-- Literal values. -/
inductive Lit where
  | string (value : String)
  | number (value : Nat)
  | bigint (value : Nat)
  | bool (value : Bool)
  deriving BEq, Repr

/-- Binary operators we may emit. -/
inductive BinOp where
  | eq | ne | lt | le | gt | ge
  | and | or
  | add | sub | mul | div | mod
  | bitXor | shiftLeft | shiftRight
  deriving BEq, Repr

mutual
  /-- Expression forms used in generated worker code. -/
  inductive Expr where
    | lit (value : Lit)
    | ident (name : String)
    | member (base : Expr) (field : String)
    | call (callee : Expr) (args : Array Expr)
    | new (callee : Expr) (args : Array Expr)
    | binary (op : BinOp) (lhs rhs : Expr)
    | await (expr : Expr)
    | coalesce (lhs rhs : Expr)
  | objectLit (fields : Array (String × Expr))
  | paren (expr : Expr)
  deriving BEq, Repr, Inhabited

  /-- Statements in generated worker functions. -/
  inductive Stmt where
    | constDecl (name : String) (type? : Option Ty) (init : Expr)
    | letDecl (name : String) (type? : Option Ty) (init : Expr)
    | assign (target : Expr) (value : Expr)
    | exprStmt (expr : Expr)
    | ifStmt (cond : Expr) (thenBody : Array Stmt) (elseBody? : Option (Array Stmt))
    | forLoop (init : Stmt) (cond : Expr) (step : Stmt) (body : Array Stmt)
    | whileLoop (cond : Expr) (body : Array Stmt)
    | return (expr : Expr)
    | throw (expr : Expr)
    deriving BEq, Repr, Inhabited
end

/-- Top-level declarations in a generated worker module. -/
inductive TopLevel where
  | exportInterface (name : String) (fields : Array (String × Ty))
  | functionDecl (async : Bool) (exported : Bool) (name : String)
      (params : Array Param) (returnType? : Option Ty) (body : Array Stmt)
  | exportDefault (expr : Expr)
  deriving BEq, Repr

/-- A TypeScript module / source file. -/
structure Module where
  items : Array TopLevel
  deriving BEq, Repr

-- Convenience constructors --------------------------------------------------

def Expr.str (s : String) : Expr := .lit (.string s)
def Expr.num (n : Nat) : Expr := .lit (.number n)
def Expr.bigint (n : Nat) : Expr := .lit (.bigint n)
def Expr.bool (b : Bool) : Expr := .lit (.bool b)

def Expr.prop (base : String) (field : String) : Expr := .member (.ident base) field
def Expr.call0 (callee : Expr) : Expr := .call callee #[]
def Expr.call1 (callee : Expr) (arg : Expr) : Expr := .call callee #[arg]
def Expr.call2 (callee : Expr) (a b : Expr) : Expr := .call callee #[a, b]

def Stmt.const_ (name : String) (init : Expr) : Stmt := .constDecl name none init
def Stmt.constT (name : String) (type : Ty) (init : Expr) : Stmt := .constDecl name (some type) init

def TopLevel.exportFn (async : Bool) (name : String) (params : Array Param)
    (returnType? : Option Ty) (body : Array Stmt) : TopLevel :=
  .functionDecl async true name params returnType? body

def TopLevel.fn (async : Bool) (name : String) (params : Array Param)
    (returnType? : Option Ty) (body : Array Stmt) : TopLevel :=
  .functionDecl async false name params returnType? body

end ProofForge.Compiler.TS
