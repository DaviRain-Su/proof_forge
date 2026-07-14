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
  maps : Std.HashMap String (Array (Nat × Nat)) := {}
  arrays : Std.HashMap String (Array Nat) := {}
  events : Array (String × Array Nat)
  reverted : Bool := false
  error : Option String := none
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
  | .mapRead name key => do
    let key ← evalExpr key st locals
    let entries := st.maps.get? name |>.getD #[]
    return (entries.find? (fun entry => entry.1 == key)).map (fun entry => entry.2) |>.getD 0
  | .arrayRead name index => do
    let index ← evalExpr index st locals
    let entries := st.arrays.get? name |>.getD #[]
    match entries[index]? with
    | some value => return value
    | none => .error s!"arrayOutOfBounds: {name}[{index}]"
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
  | .crosscall .. => .ok 0  /- External results are opaque in reference semantics. -/
  | .hashPair lhs rhs => return (← evalExpr lhs st locals) * 16777619 + (← evalExpr rhs st locals)
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
    | .mapWrite name key value => do
      let key ← evalExpr key s l
      let value ← evalExpr value s l
      let entries := s.maps.get? name |>.getD #[]
      let entries := match entries.findIdx? (fun entry => entry.1 == key) with
        | some index => entries.set! index (key, value)
        | none => entries.push (key, value)
      s := { s with maps := s.maps.insert name entries }
    | .arrayWrite name index value => do
      let index ← evalExpr index s l
      let value ← evalExpr value s l
      let entries := s.arrays.get? name |>.getD #[]
      if index >= entries.size then .error s!"arrayOutOfBounds: {name}[{index}]"
      s := { s with arrays := s.arrays.insert name (entries.set! index value) }
    | .emit name args => do
      let mut vals := #[]
      for arg in args do
        vals := vals.push (← evalExpr arg s l)
      s := { s with events := s.events.push (name, vals.toList.toArray) }
    | .assert cond message => do
      let v ← evalExpr cond s l
      if v == 0 then s := { s with reverted := true, error := some message }
    | .revert message => s := { s with reverted := true, error := some message }
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
  let initializedArrays := contract.state.foldl (fun arrays declaration =>
    match declaration.kind with
    | .fixedArray _ length =>
        if arrays.contains declaration.name then arrays
        else arrays.insert declaration.name (Array.mk (List.replicate length 0))
    | _ => arrays) initialState.arrays
  execStmts ep.body { initialState with arrays := initializedArrays } locals

end ProofForge.Frontend.Surface
