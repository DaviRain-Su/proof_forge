import ProofForge.IR.CounterSemantics

/-! ## Total Counter-fragment IR semantics smoke

This is the executable Track 1.1 gate for the first universal C-proof path:
the Counter subset has a total, fuel-indexed IR semantics that reduces without
the broader `partial def` interpreter.
-/

namespace ProofForge.Tests.IRCounterSemantics

open ProofForge.IR.Semantics
open ProofForge.IR.CounterSemantics

-- Closed compatibility check against the legacy executable Counter trace.
#check counter_trace_matches_legacy

-- Per-entrypoint all-state lemmas for the Counter fragment.
#check initialize_total_ok
#check get_total_ok_of_count
#check increment_total_ok_of_count

theorem closed_counter_trace_matches_legacy :
    counterTraceMatchesLegacy = true :=
  counter_trace_matches_legacy

end ProofForge.Tests.IRCounterSemantics

def main : IO UInt32 := do
  IO.println "ir-counter-semantics-smoke: total Counter-fragment semantics and per-entrypoint all-state lemmas checked"
  return 0
