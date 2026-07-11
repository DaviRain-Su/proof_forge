import ProofForge.Frontend.Surface.Syntax
import ProofForge.Frontend.Surface.Normalize
import ProofForge.IR.Core.Semantics

/-! # Surface AST — Reference Semantics

Executes Surface reference semantics for parity testing against Core
semantics. The initial fragment covers scalar state read/write, arithmetic,
comparison, context read, emit, assert, revert, branch, bounded loop, and
return.
-/

namespace ProofForge.Frontend.Surface

open ProofForge.IR.Core

/-- A simple runtime state for Surface reference semantics. -/
structure SurfaceRuntimeState where
  storage : Std.HashMap String Nat
  events : Array (String × Array Nat)
  reverted : Bool := false
  returnValue : Option Nat := none
  deriving Repr

private def u64Modulus : Nat := 18446744073709551616

private def evalArithmetic (op : SurfaceArithOp) (checked : Bool)
    (lhs rhs : Nat) : Except String Nat :=
  match op with
  | .add =>
      let result := lhs + rhs
      if checked && result >= u64Modulus then .error "arithmeticOverflow"
      else .ok (if checked then result else result % u64Modulus)
  | .sub =>
      if checked && lhs < rhs then .error "arithmeticOverflow"
      else .ok (if checked then lhs - rhs else (lhs + u64Modulus - rhs % u64Modulus) % u64Modulus)
  | .mul =>
      let result := lhs * rhs
      if checked && result >= u64Modulus then .error "arithmeticOverflow"
      else .ok (if checked then result else result % u64Modulus)
  | .div => if rhs == 0 then .error "divisionByZero" else .ok (lhs / rhs)
  | .mod => if rhs == 0 then .error "divisionByZero" else .ok (lhs % rhs)
  | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight =>
      .error "bitwise ops not in reference semantics"

/-- Evaluate a Surface expression to a Nat value (initial fragment only). -/
partial def evalExpr (e : SurfaceExpr) (st : SurfaceRuntimeState)
    (locals : Std.HashMap String Nat) : Except String Nat :=
  match e with
  | .literal lit => match lit with
    | .u64Lit n | .u32Lit n | .u8Lit n | .u128Lit n => .ok n
    | .boolLit b => .ok (if b then 1 else 0)
    | _ => .error "unsupported literal in reference semantics"
  | .local name => match Std.HashMap.get? locals name with
    | some v => .ok v | none => .error s!"unbound local: {name}"
  | .stateRead name => match Std.HashMap.get? st.storage name with
    | some v => .ok v | none => .error s!"missing state: {name}"
  | .arith op checked lhs rhs => do
    let l ← evalExpr lhs st locals
    let r ← evalExpr rhs st locals
    evalArithmetic op checked l r
  | .compare op lhs rhs => do
    let l ← evalExpr lhs st locals
    let r ← evalExpr rhs st locals
    match op with
    | .eq => .ok (if l == r then 1 else 0)
    | .ne => .ok (if l != r then 1 else 0)
    | .lt => .ok (if l < r then 1 else 0)
    | .le => .ok (if l ≤ r then 1 else 0)
    | .gt => .ok (if l > r then 1 else 0)
    | .ge => .ok (if l ≥ r then 1 else 0)
  | .contextRead _ => .ok 0  /- Context reads are opaque in reference semantics. -/
  | .nativeValue => .ok 0
  | .hostCall _ _ => .ok 0  /- Host calls are opaque in reference semantics. -/
  | _ => .error "unsupported expression in reference semantics"

/-- Execute a list of Surface statements. -/
partial def execStmts (stmts : Array SurfaceStmt) (st : SurfaceRuntimeState)
    (locals : Std.HashMap String Nat) : Except String SurfaceRuntimeState := do
  let mut s := st
  let mut l := locals
  for stmt in stmts do
    if s.reverted then return s
    match stmt with
    | .bind name _ value => do
      let v ← evalExpr value s l
      l := Std.HashMap.insert l name v
    | .mutBind name _ value => do
      let v ← evalExpr value s l
      l := Std.HashMap.insert l name v
    | .assign target value => do
      let v ← evalExpr value s l
      match target with
      | .local name => l := Std.HashMap.insert l name v
      | .stateField name => s := { s with storage := Std.HashMap.insert s.storage name v }
    | .stateWrite name value => do
      let v ← evalExpr value s l
      s := { s with storage := Std.HashMap.insert s.storage name v }
    | .emit name args => do
      let mut vals := #[]
      for arg in args do
        vals := vals.push (← evalExpr arg s l)
      s := { s with events := s.events.push (name, vals.toList.toArray) }
    | .assert cond _ => do
      let v ← evalExpr cond s l
      if v == 0 then s := { s with reverted := true }
    | .revert _ => s := { s with reverted := true }
    | .branch cond thenBody elseBody => do
      let v ← evalExpr cond s l
      if v ≠ 0 then
        s ← execStmts thenBody s l
      else
        s ← execStmts elseBody s l
    | .boundedLoop indexName start stop body => do
      for i in [start:stop] do
        if s.reverted then return s
        let l' := Std.HashMap.insert l indexName i
        s ← execStmts body s l'
    | .returnExpr value => do
      let v ← evalExpr value s l
      return { s with returnValue := some v }
    | .hostCallBind name _ _ _ => l := Std.HashMap.insert l name 0  /- Host calls are opaque. -/
    | .returnUnit => return s
  return s

/-- Execute a Surface entrypoint and return the final runtime state. -/
def runEntrypoint (contract : SurfaceContract) (entrypointName : String)
    (args : Array Nat)
    (initialState : SurfaceRuntimeState) :
    Except String SurfaceRuntimeState := do
  let ep ← match contract.entrypoints.find? (fun e => e.name == entrypointName) with
  | some ep => pure ep
  | none => .error s!"unknown entrypoint: {entrypointName}"
  let locals : Std.HashMap String Nat :=
    ep.params.toList.zip args.toList |>.foldl (fun m (p, a) => m.insert p.name a) {}
  execStmts ep.body initialState locals

end ProofForge.Frontend.Surface
