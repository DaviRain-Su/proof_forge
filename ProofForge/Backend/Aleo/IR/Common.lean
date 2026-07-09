/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Aleo/Leo IR Lowering Common State and Validation Helpers

Shared error, storage-layout, type, identifier, effect-detection, and
assignment helpers for the Aleo/Leo portable IR lowering pipeline. This is the
`aleo-leo` counterpart of `ProofForge.Backend.Psy.IR.Common`: it owns the
Leo-specific vocabulary the lowering (`ProofForge.Backend.Aleo.IR`) and the
validation pass (`ProofForge.Backend.Aleo.IR.Validate`) share.

Leo-specific notes:

- Leo 4.x has **no scalar on-chain storage**: the only persistent on-chain state
  is a `mapping`. ProofForge rewrites a portable scalar state (`state id: scalar
  T`) into a single-slot Leo `mapping id: u64 => T` keyed by the constant `0u64`,
  read via `Mapping::get_or_use(id, 0u64, <default>)` and written via
  `Mapping::set(id, 0u64, value)`. `isScalarState` / `scalarStateType` carry that
  rewrite so the lowering and the validator agree.
- `valueType` maps the portable `ValueType` vocabulary onto the Leo type AST
  (`ProofForge.Compiler.Leo.AST.LeoType`). Anything Leo cannot spell yet
  (`Hash`, dynamic arrays, `Bytes`) is an explicit, honest reject.
- `hasEffect`/`hasEffectExpr`/`hasEffectStmt` drive the async/finalize split:
  any entrypoint that touches on-chain storage must lower its body into a
  `return final { … };` block (Leo's on-chain finalize model), returning `Final`.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Compiler.Leo.AST

namespace ProofForge.Backend.Aleo.IR

open ProofForge.IR
open ProofForge.Compiler.Leo.AST

/-- Shared lowering / validation error. -/
structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

/-- Lift a capability-resolution `Diagnostic` into a `LowerError`. -/
def diagnosticError (err : ProofForge.Target.Diagnostic) : LowerError :=
  { message := err.render }

/-- Look up a struct declaration by name. -/
def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? fun decl => decl.name == name

/-- Look up a struct field by name within a struct declaration. -/
def findStructField? (decl : StructDecl) (fieldName : String) : Option StructField :=
  decl.fields.find? fun field => field.id == fieldName

/-- Look up a storage state declaration by id. -/
def findState? (module : Module) (stateId : String) : Option StateDecl :=
  module.state.find? fun state => state.id == stateId

/-! ### Build context -/

/-- Build context: carries the portable IR module. Leo storage shapes are
resolved directly from `module.state` (Leo has no felt-backed-array rewrite or
pre-resolved storage layout plan, unlike Psy), so the context is intentionally
thin. -/
structure BuildContext where
  module : Module

/-- Look up a storage state declaration from the build context. -/
def lookupState? (ctx : BuildContext) (stateId : String) : Option StateDecl :=
  findState? ctx.module stateId

/-! ### Portable → Leo type mapping -/

/-- Map a portable IR `ValueType` to a Leo type.

Leo spells: `address`, `bool`, `field`, `group`, the integer widths
`u8`/`u16`/`u32`/`u64`/`u128`/`i8..i64`, `[T; N]` arrays, `struct` (composite),
and `()`. Portable `Hash`, `Bytes`, and dynamic arrays have no faithful Leo
spelling and are rejected honestly. -/
def valueType (type : ValueType) : Except LowerError LeoType :=
  match type with
  | .unit => .ok .unit
  | .bool => .ok .boolean
  | .u8 => .ok (.integer .u8)
  | .u32 => .ok (.integer .u32)
  | .u64 => .ok (.integer .u64)
  | .u128 => .ok (.integer .u128)
  | .address => .ok .address
  | .string => .ok .string
  | .hash => .error { message := "Leo IR v0 does not support Hash; use U64/Field components instead" }
  | .bytes => .error { message := "Leo IR v0 does not support Bytes" }
  | .fixedArray element length =>
      if length == 0 then
        .error { message := "Leo IR v0 fixed arrays must have non-zero length" }
      else
        match valueType element with
        | .ok t => .ok (.array t length)
        | .error e => .error e
  | .structType name => .ok (.composite name)
  | .array _ => .error { message := "Leo IR v0 does not support dynamic arrays" }

/-- Require a `ValueType` to be Leo-spellable; returns the `LeoType`. -/
def requireValueType (context : String) (type : ValueType) : Except LowerError LeoType := do
  match valueType type with
  | .ok t => .ok t
  | .error e => .error { message := s!"{context}: {e.message}" }

/-! ### Portable → Leo literal mapping -/

/-- Map a portable IR `Literal` to a Leo literal. -/
def leoLiteral : IR.Literal → ProofForge.Compiler.Leo.AST.Literal
  | .u8 value => .integer .u8 value
  | .u32 value => .integer .u32 value
  | .u64 value => .integer .u64 value
  | .u128 value => .integer .u128 value
  | .bool value => .boolean value
  | .address value => .address (toString value)
  | .hash4 _ _ _ _ => .none

/-! ### Operator mapping -/

/-- Map a portable compound-assignment operator to its Leo binary operator. -/
def assignOpToBinary : AssignOp → BinaryOperation
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .bitwiseAnd
  | .bitOr => .bitwiseOr
  | .bitXor => .xor
  | .shiftLeft => .shl
  | .shiftRight => .shr

/-! ### Storage helpers -/

/-- The default Leo mapping key used for the scalar→mapping rewrite
(a single-slot mapping keyed by `0u64`). -/
def scalarSlotKey : Expression :=
  .literal (.integer .u64 0)

/-- Require that a state is scalar storage; return its value `ValueType`. -/
def requireScalarState (ctx : BuildContext) (stateId : String) : Except LowerError ValueType :=
  match lookupState? ctx stateId with
  | some { kind := .scalar, type := t, .. } => .ok t
  | some { kind := .map _ _, .. } =>
      .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | some { kind := .array _, .. } =>
      .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | some { kind := .dynamicArray, .. } =>
      .error { message := s!"state `{stateId}` is a dynamic array, not scalar storage" }
  | none => .error { message := s!"unknown scalar state `{stateId}`" }

/-- Require that a state is map storage; return its `(keyType, valueType)`. -/
def requireMapState (ctx : BuildContext) (stateId : String) : Except LowerError (ValueType × ValueType) :=
  match lookupState? ctx stateId with
  | some { kind := .map keyType _, type := t, .. } => .ok (keyType, t)
  | some { kind := .scalar, .. } =>
      .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | some { kind := .array _, .. } =>
      .error { message := s!"state `{stateId}` is array storage, not a map" }
  | some { kind := .dynamicArray, .. } =>
      .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }
  | none => .error { message := s!"unknown map state `{stateId}`" }

/-- Whether a scalar state's value type should be rewritten as a Leo mapping
keyed by `u64`. All scalar states are rewritten this way (Leo has no scalar
storage), so this is true for every scalar state. -/
def isScalarState (ctx : BuildContext) (stateId : String) : Bool :=
  match lookupState? ctx stateId with
  | some { kind := .scalar, .. } => true
  | _ => false

/-! ### Context-field mapping (Leo finalize/proof-context intrinsics)

Leo 4.x exposes on-chain/proof context as `self.caller`, `self.signer`,
`block.height`, `block.timestamp`, and `network.id` (verified against the
ProvableHQ/leo `documentation/code_snippets`). Only the fields that map to a
portable `ValueType` are lowerable: caller/signer → `address`, block height →
`u32`. `block.timestamp` (i64) and `network.id` (u16) have no portable
`ValueType`, and there is no self-contract-address intrinsic, so those are
honest rejects. -/

def mapContextField (field : ContextField) : Except LowerError (ValueType × Expression) :=
  match field with
  | .userId | .userIdHash | .origin => .ok (.address, .memberAccess ⟨.identifier "self", "caller"⟩)
  | .checkpointId => .ok (.u32, .memberAccess ⟨.identifier "block", "height"⟩)
  | .timestamp => .error { message := "Leo IR v0 does not lower timestamp: Leo `block.timestamp` is i64, which has no portable ValueType" }
  | .chainId => .error { message := "Leo IR v0 does not lower chainId: Leo `network.id` is u16, which has no portable ValueType" }
  | .contractId => .error { message := "Leo IR v0 does not lower contractId: Leo has no self-contract-address intrinsic" }
  | f => .error { message := s!"Leo IR v0 does not lower context field `{f.name}`" }

/-! ### Effect detection (drives the async/finalize split) -/

mutual
  partial def hasEffectExpr : Expr → Bool
    | .effect _ => true
    | .add lhs rhs _ => hasEffectExpr lhs || hasEffectExpr rhs
    | .sub lhs rhs _ => hasEffectExpr lhs || hasEffectExpr rhs
    | .mul lhs rhs _ => hasEffectExpr lhs || hasEffectExpr rhs
    | .div lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .mod lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .pow lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitAnd lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitOr lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitXor lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .shiftLeft lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .shiftRight lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .cast v _ => hasEffectExpr v
    | .eq lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .ne lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .lt lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .le lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .gt lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .ge lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolAnd lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolOr lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolNot v => hasEffectExpr v
    | .arrayLit _ vs => vs.any hasEffectExpr
    | .arrayGet a i => hasEffectExpr a || hasEffectExpr i
    | .structLit _ fs => fs.any (fun (_, e) => hasEffectExpr e)
    | .field b _ => hasEffectExpr b
    | .hashValue a b c d => hasEffectExpr a || hasEffectExpr b || hasEffectExpr c || hasEffectExpr d
    | .hash v => hasEffectExpr v
    | .hashTwoToOne l r => hasEffectExpr l || hasEffectExpr r
    | .crosscallInvoke t m args => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeValueTyped t m cv args _ => hasEffectExpr t || hasEffectExpr m || hasEffectExpr cv || args.any hasEffectExpr
    | .crosscallInvokeStaticTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeDelegateTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallCreate cv _ => hasEffectExpr cv
    | .crosscallCreate2 cv s _ => hasEffectExpr cv || hasEffectExpr s
    | .nearPromiseThen p m args d =>
        hasEffectExpr p || hasEffectExpr m || hasEffectExpr d ||
          args.any (fun arg => hasEffectExpr arg)
    | .nearPromiseResultsCount => false
    | .nearPromiseResultStatus i => hasEffectExpr i
    | .nearPromiseResultU64 i => hasEffectExpr i
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        hasEffectExpr accountIndex || hasEffectExpr methodId || hasEffectExpr deposit ||
          args.any (hasEffectExpr ·)
    | _ => false

  partial def hasEffect (body : Array IR.Statement) : Bool :=
    body.any hasEffectStmt

  partial def hasEffectStmt : IR.Statement → Bool
    | .effect _ => true
    | .letBind _ _ v => hasEffectExpr v
    | .letMutBind _ _ v => hasEffectExpr v
    | .assign t v => hasEffectExpr t || hasEffectExpr v
    | .assignOp t _ v => hasEffectExpr t || hasEffectExpr v
    | .assert c _ _ => hasEffectExpr c
    | .assertEq l r _ _ => hasEffectExpr l || hasEffectExpr r
    | .ifElse c thenBody elseBody => hasEffectExpr c || hasEffect thenBody || hasEffect elseBody
    | .boundedFor _ _ _ body => hasEffect body
    | .whileLoop c body => hasEffectExpr c || hasEffect body
    | .return v => hasEffectExpr v
    | .release _ => false
    | .revert _ | .revertWithError _ => true
end

/-! ### Identifier validation -/

def asciiLetters : String :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

def isLeoIdentifierStart (ch : Char) : Bool :=
  ch == '_' || asciiLetters.contains ch

def isLeoIdentifierContinue (ch : Char) : Bool :=
  isLeoIdentifierStart ch || ch.isDigit

/-- Leo reserved keywords that must not be used as identifiers. -/
def leoReservedIdentifiers : Array String := #[
  "address", "as", "assert", "assert_eq", "assert_neq",
  "bool", "const", "else", "false", "field", "final", "finalize", "for",
  "future", "group", "if", "in", "let", "mapping", "match", "mod", "mut",
  "program", "public", "return", "scalar", "self", "signature", "string",
  "struct", "then", "true", "const", "view", "console"
]

def validateLeoIdentifier (context name : String) : Except LowerError Unit :=
  match name.toList with
  | [] =>
      .error { message := s!"{context} must be a non-empty Leo identifier" }
  | first :: rest => do
      if !isLeoIdentifierStart first || !rest.all isLeoIdentifierContinue then
        .error { message := s!"{context} `{name}` is not a valid Leo identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`" }
      if leoReservedIdentifiers.any (fun reserved => reserved == name) then
        .error { message := s!"{context} `{name}` is a reserved Leo keyword" }

def validateDistinctNames (context : String) (names : Array String) : Except LowerError Unit := do
  let _ ← names.foldlM (init := #[]) fun seen name =>
    if seen.any (fun existing => existing == name) then
      .error { message := s!"duplicate {context} `{name}`" }
    else
      .ok (seen.push name)
  pure ()

/-! ### Type-checking helpers -/

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

def ensureNumericType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 => .ok ()
  | other => .error { message := s!"{context} expected numeric `U8`/`U32`/`U64`/`U128`/`Field`, got `{other.name}`" }

def ensureSameNumericType (operator : String) (lhs rhs : ValueType) : Except LowerError ValueType := do
  ensureNumericType s!"{operator} left operand" lhs
  ensureType s!"{operator} right operand" lhs rhs
  .ok lhs

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u32, .u64 => .ok ()
  | .u64, .u32 => .ok ()
  | .u32, .u128 => .ok ()
  | .u64, .u128 => .ok ()
  | .u32, .bool => .ok ()
  | .bool, .u64 => .ok ()
  | .bool, .u32 => .ok ()
  | .u64, .bool => .ok ()
  | source, target =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by Leo IR v0" }

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .unit =>
      .error { message := s!"{context} does not support Unit equality" }
  | .bool | .u8 | .u32 | .u64 | .u128 | .address | .fixedArray _ _ | .structType _ =>
      .ok ()
  | .hash | .bytes | .string | .array _ =>
      .error { message := s!"{context} does not support `{type.name}` equality" }

def structFieldType (module : Module) (typeName fieldName : String) : Except LowerError ValueType := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct type `{typeName}`" }
  let some field := findStructField? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  .ok field.type

def assignOpDiagnosticName : AssignOp → String
  | .add => "addition"
  | .sub => "subtraction"
  | .mul => "multiplication"
  | .div => "division"
  | .mod => "modulo"
  | .bitAnd => "bitwise and"
  | .bitOr => "bitwise or"
  | .bitXor => "bitwise xor"
  | .shiftLeft => "shift-left"
  | .shiftRight => "shift-right"

end ProofForge.Backend.Aleo.IR
