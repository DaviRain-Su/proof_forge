/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Psy Abstract Syntax Tree.

The `psy-dpn` counterpart of `ProofForge.Compiler.Yul.AST` and
`ProofForge.Compiler.Wasm.AST`: a small target-side AST that the Psy backend
(`ProofForge.Backend.Psy.IR`) lowers the portable contract IR into, and
`ProofForge.Compiler.Psy.Printer` renders to `.psy` source text. The emitted
`.psy` is valid input for the official Dargo/Psy compiler toolchain.

The shape mirrors the upstream `psy-ast` crate
(https://github.com/PsyProtocol/psy-compiler/tree/mainnet-beta/psy-ast) at the
level of granularity that ProofForge emits today: modules carry contract
structs/state, `impl <Name>Ref` method blocks, and a `#[test]` entrypoint test.
Expressions cover literals, locals, array/struct literals, field/index access,
binary/unary/cast/hash/crosscall forms, context reads, storage reads, and
storage map operations. Statements cover `let`/`let mut` bindings, plain and
compound assignment, effects, assertions, `if/else`, bounded `for`, `return`,
`revert`, and event emit.

Design notes:

- This is a *target AST*, not the upstream checked `psy-ast::Program`. It does
  not model interners, arenas, def-ids, or type checking; those stay on the
  portable-IR side. It models exactly the surface forms the Printer needs.
- `AssignOp`/`BinaryOp`/`UnaryOp` are kept as thin enums so the Printer renders
  the canonical Psy operator spellings without re-deriving them.
- `StorageTarget` captures the `c.<state>...` left-hand-side forms that the
  existing lowerer produces, including the Felt-backed U32 array rewrite.
-/

module

prelude
public import Init.Prelude
public import Init.Data.Repr
import Init.Data.Array.Basic
import Init.Data.String.Basic

public section

namespace Lean.Compiler.Psy

/-- A Psy identifier is an ASCII letter/underscore-prefixed name string. -/
abbrev Name := String

/-- Public (`pub `) or private visibility for struct fields and declarations. -/
inductive Visibility where
  | pub | priv
  deriving DecidableEq, Repr

/-- A binary operator spelled the way Psy source expects it. -/
inductive BinaryOp where
  | add | sub | mul | div | mod | pow
  | bitAnd | bitOr | bitXor
  | shiftLeft | shiftRight
  | eq | ne | lt | le | gt | ge
  | boolAnd | boolOr
  deriving DecidableEq, Repr

/-- A unary operator. Psy supports `-` (negation) and `!` (boolean not). -/
inductive UnaryOp where
  | neg | not
  deriving DecidableEq, Repr

/-- A compound assignment operator (`+=`, `-=`, ..., `>>=`). -/
inductive AssignOp where
  | add | sub | mul | div | mod
  | bitAnd | bitOr | bitXor
  | shiftLeft | shiftRight
  deriving DecidableEq, Repr

/-- Map a compound assignment operator to its underlying binary operator.
Used by the lowerer to rewrite Felt-backed U32 compound assignments into an
explicit `(target.get() as u32 OP value) as Felt` form. -/
def AssignOp.toBinaryOp : AssignOp → BinaryOp
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight

/-- A Psy type name as printed in source: `Felt`, `u32`, `[T; N]`, struct names. -/
structure TypeName where
  (text : String)
  deriving DecidableEq, Repr, Inhabited

/-- A Psy literal value as it appears in source. -/
inductive Literal where
  | u32 (value : Nat)
  | felt (value : Nat)
  | bool (value : Bool)
  | u8 (value : Nat)
  | u128 (value : Nat)
  | address (value : String)
  | hash4 (a b c d : Nat)
  deriving DecidableEq, Repr, Inhabited

/-- A context read kind. Only `userId`, `contractId`, and `checkpointId` are
spelled by the lowerer; the AST keeps the enum closed so the Printer maps each
to its Psy intrinsic. -/
inductive ContextField where
  | userId | contractId | checkpointId
  deriving DecidableEq, Repr

mutual
  /-- A storage path segment: a struct field or a fixed array index expression. -/
  inductive StoragePathSegment where
    | field (name : Name)
    | index (index : Expr)
    deriving Repr

  /-- A Psy storage left-hand-side target.

  The lowerer folds all `c.<state>...` forms into this type so the Printer does
  not need to re-resolve portable IR state shapes. `feltBackedU32` records the
  Felt-backed `[Felt; N]` rewrite for native U32 storage arrays/paths. -/
  inductive StorageTarget where
    | scalar (stateId : Name)
    | structField (stateId : Name) (fieldName : Name)
    | arrayIndex (stateId : Name) (index : Expr) (feltBackedU32 : Bool)
    | arrayStructField (stateId : Name) (index : Expr) (fieldName : Name)
    | path (stateId : Name) (segments : Array StoragePathSegment) (feltBackedU32 : Bool)
    deriving Repr

  /-- A Psy surface expression. Each constructor is one `.psy` source form. -/
  inductive Expr where
    | literal (value : Literal)
    | local (name : Name)
    | arrayLit (elementType : TypeName) (items : Array Expr)
    | arrayGet (array : Expr) (index : Expr)
    | structLit (typeName : Name) (fields : Array (Name × Expr))
    | field (base : Expr) (fieldName : Name)
    | binary (lhs : Expr) (op : BinaryOp) (rhs : Expr)
    | unary (op : UnaryOp) (rhs : Expr)
    | cast (value : Expr) (targetType : TypeName)
    | hashValue (a b c d : Expr)
    | hash (preimage : Expr)
    | hashTwoToOne (lhs rhs : Expr)
    | storageScalarRead (stateId : Name)
    | storageMapContains (stateId : Name) (key : Expr)
    | storageMapGet (stateId : Name) (key : Expr)
    | storageMapInsert (stateId : Name) (key value : Expr)
    | storageMapSet (stateId : Name) (key value : Expr)
    | storageArrayRead (stateId : Name) (index : Expr) (feltBackedU32 : Bool)
    | storageArrayStructFieldRead (stateId : Name) (index : Expr) (fieldName : Name)
    | storageStructFieldRead (stateId : Name) (fieldName : Name)
    | storagePathRead (stateId : Name) (path : Array StoragePathSegment) (feltBackedU32 : Bool)
    | contextRead (field : ContextField)
    | crosscallInvoke (target methodId : Expr) (args : Array Expr)
    deriving Repr

  /-- A Psy effect statement (storage writes, map insert/set, event emit). -/
  inductive Effect where
    | storageScalarWrite (stateId : Name) (value : Expr)
    | storageScalarAssignOp (stateId : Name) (op : AssignOp) (value : Expr)
    | storageArrayWrite (stateId : Name) (index : Expr) (value : Expr) (feltBackedU32 : Bool)
    | storageArrayStructFieldWrite (stateId : Name) (index : Expr) (fieldName : Name) (value : Expr)
    | storageStructFieldWrite (stateId : Name) (fieldName : Name) (value : Expr)
    | storagePathWrite (stateId : Name) (path : Array StoragePathSegment) (value : Expr) (feltBackedU32 : Bool)
    | storagePathAssignOp (stateId : Name) (path : Array StoragePathSegment) (op : AssignOp) (value : Expr)
    | storageMapInsert (stateId : Name) (key value : Expr)
    | storageMapSet (stateId : Name) (key value : Expr)
    | eventEmit (name : String) (fields : Array (Name × Expr))
    deriving Repr

  /-- A Psy surface statement. Each constructor is one `.psy` source form. -/
  inductive Stmt where
    | letBind (name : Name) (type : TypeName) (value : Expr)
    | letMutBind (name : Name) (type : TypeName) (value : Expr)
    | assign (target : StorageTarget) (value : Expr)
    | assignOp (target : StorageTarget) (op : AssignOp) (value : Expr)
    | localAssign (target : Expr) (value : Expr)
    | localAssignOp (target : Expr) (op : AssignOp) (value : Expr)
    | effect (eff : Effect)
    | assert (condition : Expr) (message : String)
    | assertEq (lhs rhs : Expr) (message : String)
    | ifElse (condition : Expr) (thenBody : Array Stmt) (elseIfs : Array (Expr × Array Stmt)) (elseBody : Array Stmt)
    | boundedFor (indexName : Name) (start stopExclusive : Nat) (body : Array Stmt)
    | returnExpr (value : Expr)
    | revert (message : String)
    deriving Repr
end

instance : Inhabited Expr := ⟨.literal default⟩
instance : Inhabited Effect := ⟨.storageScalarWrite "" default⟩
instance : Inhabited Stmt := ⟨.revert ""⟩
instance : Inhabited StoragePathSegment := ⟨.field ""⟩
instance : Inhabited StorageTarget := ⟨.scalar ""⟩

/-- A single struct field declaration inside a `struct` body. -/
structure StructField where
  (id : Name) (type : TypeName) (isPublic : Bool) (isRef : Bool)
  deriving DecidableEq, Repr

/-- A Psy struct declaration, optionally carrying `#[derive(Storage)]`. -/
structure StructDecl where
  (name : Name) (isPublic : Bool) (deriveStorage : Bool) (fields : Array StructField)
  deriving DecidableEq, Repr

/-- A storage declaration inside the contract struct body. -/
inductive StateDecl where
  | scalar (id : Name) (type : TypeName)
  | structRef (id : Name) (type : TypeName)
  | map (id : Name) (keyType valueType : TypeName) (capacity : Nat)
  | array (id : Name) (elementType : TypeName) (length : Nat) (feltBackedU32 : Bool)
  deriving DecidableEq, Repr

/-- A contract method (entrypoint). -/
structure Method where
  (name : Name) (params : Array (Name × TypeName)) (returns : Option TypeName) (body : Array Stmt)
  deriving Repr

/-- A `#[test]` entrypoint test body as emitted by the lowerer. -/
structure Test where
  (name : Name) (body : Array String)
  deriving DecidableEq, Repr

/-- A complete Psy module: contract struct, `impl <Name>Ref` methods, and test. -/
structure Module where
  (name : Name)
  (headerComment : String)
  (structs : Array StructDecl)
  (contractName : Name)
  (state : Array StateDecl)
  (refName : Name)
  (methods : Array Method)
  (test : Test)
  deriving Repr

end Lean.Compiler.Psy