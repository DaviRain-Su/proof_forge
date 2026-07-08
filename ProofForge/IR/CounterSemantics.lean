import ProofForge.IR.Semantics
import ProofForge.IR.Examples.Counter

namespace ProofForge.IR.CounterSemantics

open ProofForge.IR
open ProofForge.IR.Semantics

/-! ## Total Counter-fragment IR semantics

This module is Track 1.1's first small step: a total, fuel-indexed executable
semantics for the IR subset used by `Examples.Counter`.

The broad `IR.Semantics` interpreter is intentionally wider and still uses
`partial def` for recursive language features. This fragment avoids that
surface: recursion is structural on `fuel`, so later C-proof work can state and
prove per-entrypoint lemmas by ordinary reduction/induction instead of relying
on opaque partial definitions.
-/

def defaultFuel : Nat := 32

def unsupportedExpr (expr : Expr) : Except String ExprResult :=
  .error s!"Counter total semantics does not support expression `{repr expr}`"

def unsupportedEffect (effect : Effect) : Except String ExprResult :=
  .error s!"Counter total semantics does not support effect `{repr effect}`"

def unsupportedStatement (statement : Statement) :
    Except String (State × Frame × Option Value) :=
  .error s!"Counter total semantics does not support statement `{repr statement}`"

mutual
  def evalExprFuel : Nat → State → Frame → Expr → Except String ExprResult
    | 0, _, _, _ => .error "Counter total semantics expression fuel exhausted"
    | fuel + 1, state, frame, expr =>
      match expr with
      | .literal literal => do
          let value ← literalValue literal
          .ok (state, value)
      | .local name =>
          match frame.read name with
          | some value => .ok (state, value)
          | none => .error s!"unknown local `{name}`"
      | .add lhs rhs _ => do
          let (stateAfterLhs, lhsValue) ← evalExprFuel fuel state frame lhs
          let (stateAfterRhs, rhsValue) ← evalExprFuel fuel stateAfterLhs frame rhs
          .ok (stateAfterRhs, ← evalNumericBinary "add" (· + ·) lhsValue rhsValue)
      | .effect effect =>
          evalEffectFuel fuel state frame effect
      | _ => unsupportedExpr expr

  def evalEffectFuel : Nat → State → Frame → Effect → Except String ExprResult
    | 0, _, _, _ => .error "Counter total semantics effect fuel exhausted"
    | fuel + 1, state, frame, effect =>
      match effect with
      | .storageScalarRead name =>
          match state.read name with
          | some value => .ok (state, value)
          | none => .error s!"unknown scalar state `{name}`"
      | .storageScalarWrite name valueExpr => do
          let (nextState, value) ← evalExprFuel fuel state frame valueExpr
          .ok (nextState.write name value, .unit)
      | _ => unsupportedEffect effect

  def execStmtFuel : Nat → State → Frame → Statement →
      Except String (State × Frame × Option Value)
    | 0, _, _, _ => .error "Counter total semantics statement fuel exhausted"
    | fuel + 1, state, frame, statement =>
      match statement with
      | .letBind name _ value => do
          let (nextState, evaluated) ← evalExprFuel fuel state frame value
          .ok (nextState, frame.write name evaluated, none)
      | .letMutBind name _ value => do
          let (nextState, evaluated) ← evalExprFuel fuel state frame value
          .ok (nextState, frame.write name evaluated, none)
      | .effect effect => do
          let (nextState, _) ← evalEffectFuel fuel state frame effect
          .ok (nextState, frame, none)
      | .return value => do
          let (nextState, returnValue) ← evalExprFuel fuel state frame value
          .ok (nextState, frame, some returnValue)
      | _ => unsupportedStatement statement

  def execStatementsFuel : Nat → List Statement → State → Frame →
      Except String (State × Option Value)
    | 0, _, _, _ => .error "Counter total semantics statement-list fuel exhausted"
    | _fuel + 1, [], state, _frame => .ok (state, none)
    | fuel + 1, statement :: rest, state, frame => do
        let (nextState, nextFrame, returnValue?) ← execStmtFuel fuel state frame statement
        match returnValue? with
        | some returnValue => .ok (nextState, some returnValue)
        | none => execStatementsFuel fuel rest nextState nextFrame
end

def runEntrypointWithArgsFuel (fuel : Nat) (state : State)
    (entrypoint : Entrypoint) (args : Array Value) :
    Except String (State × Option Value) := do
  let frame ← bindParams entrypoint.params args
  execStatementsFuel fuel entrypoint.body.toList state frame

def runEntrypointNoArgsFuel (fuel : Nat) (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  execStatementsFuel fuel entrypoint.body.toList state Frame.empty

def runCounterEntrypoint (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  runEntrypointNoArgsFuel defaultFuel state entrypoint

def counterTrace : Except String (State × Option Value) := do
  let (initialized, _) ←
    runCounterEntrypoint State.empty ProofForge.IR.Examples.Counter.initializeEntrypoint
  let (incremented, _) ←
    runCounterEntrypoint initialized ProofForge.IR.Examples.Counter.increment
  runCounterEntrypoint incremented ProofForge.IR.Examples.Counter.get

def counterTraceMatchesLegacy : Bool :=
  resultMatches counterTrace ProofForge.IR.Semantics.counterTrace

theorem counter_trace_matches_legacy :
    counterTraceMatchesLegacy = true := by
  native_decide

theorem initialize_total_ok (state : State) :
    runCounterEntrypoint state ProofForge.IR.Examples.Counter.initializeEntrypoint =
      .ok (state.write "count" (.u64 0), none) := by
  simp [runCounterEntrypoint, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.initializeEntrypoint, execStatementsFuel,
    execStmtFuel, evalEffectFuel, evalExprFuel]
  rfl

theorem get_total_ok_of_count {state : State} {n : Nat}
    (h : state.read "count" = some (.u64 n)) :
    runCounterEntrypoint state ProofForge.IR.Examples.Counter.get =
      .ok (state, some (.u64 n)) := by
  simp [runCounterEntrypoint, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.get, execStatementsFuel, execStmtFuel,
    evalExprFuel, evalEffectFuel, h]
  rfl

theorem increment_total_ok_of_count {state : State} {n : Nat}
    (h : state.read "count" = some (.u64 n)) :
    runCounterEntrypoint state ProofForge.IR.Examples.Counter.increment =
      .ok (state.write "count" (.u64 (n + 1)), none) := by
  simp [runCounterEntrypoint, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.increment, execStatementsFuel, execStmtFuel,
    evalExprFuel, evalEffectFuel, evalNumericBinary, Frame.empty, Frame.read,
    Frame.write, ProofForge.IR.Semantics.insert, h]
  rfl

end ProofForge.IR.CounterSemantics
