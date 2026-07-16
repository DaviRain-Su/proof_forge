import ProofForge.IR.Semantics
import ProofForge.IR.SemanticsFuel
import ProofForge.IR.Examples.Counter

namespace ProofForge.IR.CounterSemantics

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.SemanticsFuel

/-! ## Counter-specific wrappers over the shared fueled IR interpreter (FV-9.0)

The generic fuel-indexed evaluator (`evalExprFuel`/`execStmtFuel`/`evalEffectFuel`/
`execStatementsFuel`) now lives in `ProofForge.IR.SemanticsFuel` and is shared
by every contract. This file keeps only the Counter-specific surface: the
fixed-fuel entrypoint wrapper `runCounterEntrypoint`, the `counterTrace`
executable smoke, and the per-entrypoint `*_total_ok*` lemmas that the Counter
C-proofs (`CounterUniversal`, `CounterWasmRefinement`, `CounterSbpfRefinement`)
rewrite with. The evaluators are re-exported here so existing `open
CounterSemantics` call sites keep resolving.
-/

-- Re-export the shared fueled evaluators so existing call sites keep working.
export ProofForge.IR.SemanticsFuel (evalExprFuel evalEffectFuel execStmtFuel
  execStatementsFuel runEntrypointWithArgsFuel runEntrypointNoArgsFuel
  runEntrypointFuel defaultFuel unsupportedExpr unsupportedEffect
  unsupportedStatement)

/-- Run a Counter entrypoint with the shared fueled interpreter at default fuel. -/
def runCounterEntrypoint (state : State) (entrypoint : Entrypoint) :
    Except String (State × Option Value) :=
  runEntrypointFuel state entrypoint

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
  simp [runCounterEntrypoint, runEntrypointFuel, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.initializeEntrypoint, execStatementsFuel,
    execStmtFuel, evalEffectFuel, evalExprFuel]
  rfl

theorem get_total_ok_of_count {state : State} {n : Nat}
    (h : state.read "count" = some (.u64 n)) :
    runCounterEntrypoint state ProofForge.IR.Examples.Counter.get =
      .ok (state, some (.u64 n)) := by
  simp [runCounterEntrypoint, runEntrypointFuel, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.get, execStatementsFuel, execStmtFuel,
    evalExprFuel, evalEffectFuel, h]
  rfl

theorem increment_total_ok_of_count {state : State} {n : Nat}
    (h : state.read "count" = some (.u64 n)) :
    runCounterEntrypoint state ProofForge.IR.Examples.Counter.increment =
      .ok (state.write "count" (.u64 (n + 1)), none) := by
  simp [runCounterEntrypoint, runEntrypointFuel, runEntrypointNoArgsFuel, defaultFuel,
    ProofForge.IR.Examples.Counter.increment, execStatementsFuel, execStmtFuel,
    evalExprFuel, evalEffectFuel, evalNumericBinary, Frame.empty, Frame.read,
    Frame.write, ProofForge.IR.Semantics.insert, h]
  rfl

end ProofForge.IR.CounterSemantics