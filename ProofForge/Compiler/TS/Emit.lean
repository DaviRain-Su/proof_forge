/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EmitTS — lowers `ProofForge.IR.Module` to a TypeScript `TS.Module` for
Cloudflare Workers.

This first milestone only supports the Counter-shaped IR subset:
- single `u64` scalar storage
- `initialize` / `increment` / `get` style entrypoints
- arithmetic, local bindings, if/else, return

It deliberately does not cover maps, arrays, structs, cross-call, events, or
context reads yet.
-/

import Init
import Init.Control.State
import ProofForge.IR.Contract
import ProofForge.Compiler.TS.AST

section

namespace ProofForge.Compiler.TS.Emit

open ProofForge.IR
open ProofForge.Compiler.TS

/-- State for the TS emitter: accumulated statements and a fresh-name counter. -/
structure EmitState where
  stmts : Array Stmt := #[]
  fresh : Nat := 0
  deriving Inhabited

abbrev EmitTSM := ExceptT String (StateT EmitState Id)

@[inline]
def emit (s : Stmt) : EmitTSM Unit :=
  modify fun st => { st with stmts := st.stmts.push s }

/-- Generate a fresh local identifier. -/
def freshName (pfx : String := "_t") : EmitTSM String := do
  let st ← get
  set { st with fresh := st.fresh + 1 }
  pure s!"{pfx}{st.fresh}"

/-- Capture statements emitted by an action without mutating the outer buffer. -/
def captureStmts (act : EmitTSM Unit) : EmitTSM (Array Stmt) := do
  let saved ← get
  modify fun _ => { saved with stmts := #[] }
  act
  let st ← get
  modify fun _ => { saved with fresh := st.fresh }
  pure st.stmts

-- ---------------------------------------------------------------------------
-- Value type mapping
-- ---------------------------------------------------------------------------

/-- Map an IR value type to a TypeScript type. -/
def tsType : ValueType → Ty
  | .unit => .void
  | .bool => .boolean
  | .u32 => .number
  | .u64 => .bigint
  | .u8 => .number
  | .u128 => .bigint
  | .hash => .string
  | .address => .string
  | .bytes => .string
  | .string => .string
  | .fixedArray elem _ => .named s!"Array<{printTypeName elem}>"
  | .structType name => .named name
where
  printTypeName : ValueType → String
    | .unit => "void"
    | .bool => "boolean"
    | .u32 => "number"
    | .u8 => "number"
    | .u128 => "bigint"
    | .u64 => "bigint"
    | .hash => "string"
    | .address => "string"
    | .bytes => "string"
    | .string => "string"
    | .fixedArray elem len => s!"Array<{printTypeName elem},{len}>"
    | .structType name => name

-- ---------------------------------------------------------------------------
-- KV binding helpers
-- ---------------------------------------------------------------------------

/-- KV namespace binding name exposed in `Env`. Hard-coded for the Counter spike
    to match `wrangler.toml`; future versions should derive this from state id
    or module metadata. -/
def kvBindingName : String := "COUNTER_KV"

/-- Expression: `env.<KV>.get('key')` -/
def kvGetExpr (key : String) : Expr :=
  .await (.call1 (.member (.member (.ident "env") kvBindingName) "get") (.str key))

/-- Expression: `env.<KV>.put('key', value)` -/
def kvPutExpr (key : String) (value : Expr) : Expr :=
  .await (.call2 (.member (.member (.ident "env") kvBindingName) "put") (.str key) value)

-- ---------------------------------------------------------------------------
-- Expression lowering
-- ---------------------------------------------------------------------------

/-- Lower an IR literal to a TS expression. -/
def emitLit : Literal → Expr
  | .u32 n => .num n
  | .u64 n => .bigint n
  | .u8 n => .num n
  | .u128 n => .bigint n
  | .bool b => .bool b
  | .hash4 a b c d => .str s!"{a}{b}{c}{d}"
  | .address value => .str (toString value)

/-- Convert a stored-string expression to the requested IR type. -/
def fromStoredString (type : ValueType) (raw : Expr) : Expr :=
  match type with
  | .u64 => .call1 (.ident "BigInt") raw
  | .u32 => .call2 (.ident "parseInt") raw (.num 10)
  | .bool => .binary .eq raw (.str "true")
  | _ => raw

/-- Convert a value expression to a string suitable for KV storage. -/
def toStoredString (type : ValueType) (value : Expr) : Expr :=
  match type with
  | .u64 | .u32 => .call0 (.member value "toString")
  | .bool => .call1 (.ident "String") value
  | _ => value

mutual
  /-- Lower an IR expression to a TS expression. `expected` tells us how to
      interpret storage reads and numeric literals. -/
  partial def emitExpr (expected : ValueType) : ProofForge.IR.Expr → EmitTSM ProofForge.Compiler.TS.Expr
    | .literal l => pure (emitLit l)
    | .local name => pure (.ident name)
    | .add lhs rhs => emitBinOp expected .add lhs rhs
    | .sub lhs rhs => emitBinOp expected .sub lhs rhs
    | .mul lhs rhs => emitBinOp expected .mul lhs rhs
    | .div lhs rhs => emitBinOp expected .div lhs rhs
    | .mod lhs rhs => emitBinOp expected .mod lhs rhs
    | .eq lhs rhs => emitCmpOp .eq lhs rhs
    | .ne lhs rhs => emitCmpOp .ne lhs rhs
    | .lt lhs rhs => emitCmpOp .lt lhs rhs
    | .le lhs rhs => emitCmpOp .le lhs rhs
    | .gt lhs rhs => emitCmpOp .gt lhs rhs
    | .ge lhs rhs => emitCmpOp .ge lhs rhs
    | .boolAnd lhs rhs => emitBoolOp .and lhs rhs
    | .boolOr lhs rhs => emitBoolOp .or lhs rhs
    | .boolNot v => do let e ← emitExpr .bool v; pure (.paren (.binary .eq e (.bool false)))
    | .cast v target => emitExpr target v
    | .effect e => emitEffectExpr expected e
    | .bitAnd lhs rhs => emitBitwiseOp .and lhs rhs
    | .bitOr lhs rhs => emitBitwiseOp .or lhs rhs
    | .bitXor lhs rhs => emitBitwiseOp .bitXor lhs rhs
    | .shiftLeft lhs rhs => emitShiftOp true lhs rhs
    | .shiftRight lhs rhs => emitShiftOp false lhs rhs
    | .pow _ _ => throw "EmitTS: pow is not supported by the TS backend"
    | .arrayLit _ _ | .arrayGet _ _ | .structLit _ _ | .field _ _
    | .hashValue _ _ _ _ | .hash _ | .hashTwoToOne _ _ | .nativeValue
    | .crosscallInvoke _ _ _ | .crosscallInvokeTyped _ _ _ _
    | .crosscallInvokeValueTyped _ _ _ _ _ | .crosscallInvokeStaticTyped _ _ _ _
    | .crosscallInvokeDelegateTyped _ _ _ _ | .crosscallCreate _ _
    | .crosscallCreate2 _ _ _ =>
        throw "EmitTS: unsupported expression"

  partial def emitBinOp (expected : ValueType) (op : BinOp) (lhs rhs : ProofForge.IR.Expr) : EmitTSM ProofForge.Compiler.TS.Expr := do
    let l ← emitExpr expected lhs
    let r ← emitExpr expected rhs
    pure (.binary op l r)

  -- Comparison operands default to u64 for the Counter-shaped subset.
  partial def emitCmpOp (op : BinOp) (lhs rhs : ProofForge.IR.Expr) : EmitTSM ProofForge.Compiler.TS.Expr := do
    let l ← emitExpr .u64 lhs
    let r ← emitExpr .u64 rhs
    pure (.binary op l r)

  partial def emitBoolOp (op : BinOp) (lhs rhs : ProofForge.IR.Expr) : EmitTSM ProofForge.Compiler.TS.Expr := do
    let l ← emitExpr .bool lhs
    let r ← emitExpr .bool rhs
    pure (.binary op l r)

  /-- Bitwise operators. `.bitXor` maps to the TS `^` operator (BinOp.bitXor),
      not `&` as the previous buggy mapping did. -/
  partial def emitBitwiseOp (op : BinOp) (lhs rhs : ProofForge.IR.Expr) : EmitTSM ProofForge.Compiler.TS.Expr := do
    let l ← emitExpr .u64 lhs
    let r ← emitExpr .u64 rhs
    pure (.binary op l r)

  /-- Shift operators. `shiftLeft` -> `<<`, `shiftRight` -> `>>` (on bigint),
      not `*`/`/` as the previous buggy mapping did. -/
  partial def emitShiftOp (left : Bool) (lhs rhs : ProofForge.IR.Expr) : EmitTSM ProofForge.Compiler.TS.Expr := do
    let base ← emitExpr .u64 lhs
    let amount ← emitExpr .u64 rhs
    let op := if left then BinOp.shiftLeft else BinOp.shiftRight
    pure (.binary op base amount)

  /-- Lower an IR effect that appears in expression position. -/
  partial def emitEffectExpr (expected : ValueType) : Effect → EmitTSM ProofForge.Compiler.TS.Expr
    | .storageScalarRead stateId => do
        let tmp ← freshName "_sv"
        emit (.constDecl tmp (some (.optional .string)) (kvGetExpr stateId))
        pure (fromStoredString expected (.coalesce (.ident tmp) (.str "0")))
    | _ => throw "EmitTS: unsupported effect expression"
end

-- ---------------------------------------------------------------------------
-- Statement lowering
-- ---------------------------------------------------------------------------

def expectedUnit : ValueType := ValueType.unit

mutual
  /-- Lower a single IR statement to zero or more TS statements. -/
  partial def emitStmt : Statement → EmitTSM Unit
    | .letBind name type value => do
        let e ← emitExpr type value
        emit (.constDecl name (some (tsType type)) e)
    | .letMutBind name type value => do
        let e ← emitExpr type value
        emit (.letDecl name (some (tsType type)) e)
    | .assign target value => do
        let t ← emitExpr expectedUnit target
        let v ← emitExpr expectedUnit value
        emit (.assign t v)
    | .assignOp target op value => do
        let t ← emitExpr expectedUnit target
        let v ← emitExpr expectedUnit value
        let tsOp := match op with
          | .add => BinOp.add | .sub => BinOp.sub | .mul => BinOp.mul
          | .div => BinOp.div | .mod => BinOp.mod
          | .bitAnd => BinOp.and | .bitOr => BinOp.or | .bitXor => BinOp.bitXor
          | .shiftLeft => BinOp.shiftLeft | .shiftRight => BinOp.shiftRight
        emit (.assign t (.binary tsOp t v))
    | .effect (.storageScalarWrite stateId value) => do
        let v ← emitExpr (inferType value) value
        emit (.exprStmt (kvPutExpr stateId (toStoredString (inferType value) v)))
    | .effect (.storageScalarAssignOp stateId op value) => do
        let tmp ← freshName "_cur"
        emit (.constDecl tmp (some (.optional .string)) (kvGetExpr stateId))
        let cur := fromStoredString .u64 (.coalesce (.ident tmp) (.str "0"))
        let v ← emitExpr .u64 value
        let tsOp := match op with
          | .add => BinOp.add | .sub => BinOp.sub | .mul => BinOp.mul
          | .div => BinOp.div | .mod => BinOp.mod
          | .bitAnd => BinOp.and | .bitOr => BinOp.or | .bitXor => BinOp.bitXor
          | .shiftLeft => BinOp.shiftLeft | .shiftRight => BinOp.shiftRight
        let next := .binary tsOp cur v
        emit (.exprStmt (kvPutExpr stateId (toStoredString .u64 next)))
    | .effect e => throw s!"EmitTS: unsupported statement effect {repr e}"
    | .assert cond msg _ => do
        let c ← emitExpr .bool cond
        emit (.ifStmt (.paren (.binary .eq c (.bool false)))
          #[.throw (.new (.ident "Error") #[.str msg])]
          none)
    | .ifElse cond thenBody elseBody => do
        let c ← emitExpr .bool cond
        let thenStmts ← captureStmts (thenBody.forM emitStmt)
        let elseStmts ← captureStmts (elseBody.forM emitStmt)
        emit (.ifStmt c thenStmts (if elseStmts.isEmpty then none else some elseStmts))
    | .boundedFor indexName start stopExclusive body => do
        -- Lower to a `for (let i = start; i < stop; i++) { ...body }` loop.
        -- Previously the body was dropped (`_body`) and an empty `forEach` was
        -- emitted, producing code that silently did nothing.
        let bodyStmts ← captureStmts (body.forM emitStmt)
        let init := Stmt.letDecl indexName (some .number) (Expr.num start)
        let cond := Expr.binary .lt (.ident indexName) (Expr.num stopExclusive)
        let step := Stmt.assign (.ident indexName) (.binary .add (.ident indexName) (Expr.num 1))
        emit (.forLoop init cond step bodyStmts)
    | .assertEq lhs rhs msg _ => do
        let l ← emitExpr .u64 lhs
        let r ← emitExpr .u64 rhs
        emit (.ifStmt (.paren (.binary .ne l r))
          #[.throw (.new (.ident "Error") #[Expr.str msg])]
          none)
    -- TS/JS is garbage-collected, so releasing an owned heap local is a no-op.
    | .release _ => pure ()
    | .revert msg => emit (.throw (.new (.ident "Error") #[.str msg]))
    | .revertWithError _ => emit (.throw (.new (.ident "Error") #[.str "revertWithError"]))
    | .return value => do
        let e ← emitExpr (inferType value) value
        emit (.return (stringifyForResponse (inferType value) e))

  /-- A very rough type inference used for storage write stringification. -/
  partial def inferType : ProofForge.IR.Expr → ValueType
    | .literal (.u32 _) => .u32
    | .literal (.u64 _) => .u64
    | .literal (.bool _) => .bool
    | .local _ => .u64 -- Counter locals are u64
    | .add _ _ | .sub _ _ | .mul _ _ | .div _ _ | .mod _ _ => .u64
    | .effect (.storageScalarRead _) => .u64
    | .cast _ target => target
    | _ => .u64

  /-- Convert a returned value to a response string. -/
  partial def stringifyForResponse (type : ValueType) (e : ProofForge.Compiler.TS.Expr) : ProofForge.Compiler.TS.Expr :=
    match type with
    | .unit => .str ""
    | .u64 | .u32 => .call0 (.member e "toString")
    | .bool => .call1 (.ident "String") e
    | _ => e
end

-- ---------------------------------------------------------------------------
-- Entrypoint / module lowering
-- ---------------------------------------------------------------------------

/-- Decide HTTP method and path for an entrypoint by convention. -/
def routeForEntrypoint (ep : Entrypoint) : String × String :=
  let nameLower := ep.name.toLower
  if nameLower.startsWith "get" || nameLower.startsWith "query" then
    ("GET", "/" ++ nameLower)
  else
    ("POST", "/" ++ nameLower)

/-- Lower an IR entrypoint to a top-level async function returning a response
    body string. -/
def emitEntrypoint (ep : Entrypoint) : Except String TopLevel := do
  let paramEnv : Param := { name := "env", type := .named "Env" }
  let (body, _) ← emitStmts ep.body { stmts := #[] }
  -- Unit entrypoints that don't explicitly return need a default empty response.
  let hasReturn := body.any fun s => match s with | .return _ => true | _ => false
  let body :=
    if ep.returns == .unit && !hasReturn then
      body.push (.return (.str ""))
    else
      body
  pure (TopLevel.fn true ep.name #[paramEnv] (some (.promise .string)) body)
where
  emitStmts (stmts : Array Statement) (st : EmitState) : Except String (Array Stmt × EmitState) :=
    let result : Except String Unit × EmitState := (stmts.forM emitStmt).run st
    match result with
    | (.ok _, finalSt) => .ok (finalSt.stmts, finalSt)
    | (.error msg, _) => .error msg

/-- Build the flat if statements that dispatch to entrypoint functions. -/
def buildRouterBody (entrypoints : Array Entrypoint) : Array Stmt :=
  let urlStmt := Stmt.const_ "url" (.new (.ident "URL") #[.member (.ident "request") "url"])
  let routeStmts := entrypoints.map fun ep =>
    let (method, path) := routeForEntrypoint ep
    let cond : Expr :=
      .binary .and
        (.binary .eq (.member (.ident "request") "method") (.str method))
        (.binary .eq (.member (.ident "url") "pathname") (.str path))
    let call : Expr := .await (.call1 (.ident ep.name) (.ident "env"))
    .ifStmt cond #[.return (.new (.ident "Response") #[call])] none
  let fallback : Stmt :=
    .return (.new (.ident "Response") #[Expr.str "not found", .objectLit #[("status", Expr.num 404)]])
  #[urlStmt] ++ routeStmts ++ #[fallback]

/-- Build the top-level `fetch` handler and the `export default { fetch }`
    re-export. Using a named function avoids an arrow-expression in the AST and
    keeps the generated code readable. -/
def emitRouter (entrypoints : Array Entrypoint) : Array TopLevel :=
  let paramRequest : Param := { name := "request", type := .named "Request" }
  let paramEnv : Param := { name := "env", type := .named "Env" }
  let paramCtx : Param := { name := "ctx", type := .named "ExecutionContext" }
  let body := buildRouterBody entrypoints
  let fetchFn := TopLevel.fn true "fetch" #[paramRequest, paramEnv, paramCtx]
    (some (.promise (.named "Response"))) body
  let exportDefault := TopLevel.exportDefault (.objectLit #[("fetch", .ident "fetch")])
  #[fetchFn, exportDefault]

/-- Lower a full IR module to a TS module. Returns an error string if any IR
    construct is not supported by the TS backend (instead of panicking). -/
def emitModule (m : ProofForge.IR.Module) : Except String ProofForge.Compiler.TS.Module := do
  let envInterface : TopLevel :=
    .exportInterface "Env" #[(kvBindingName, .named "KVNamespace")]
  let funcs ← m.entrypoints.mapM emitEntrypoint
  let routerItems := emitRouter m.entrypoints
  pure { items := #[envInterface] ++ funcs ++ routerItems }

end ProofForge.Compiler.TS.Emit
