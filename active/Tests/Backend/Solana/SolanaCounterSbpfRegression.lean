import ProofForge.Backend.Solana.CounterSbpfExec
import ProofForge.Backend.Solana.CounterSbpfRefinement

/-! Counter sBPF core-tail + IR↔sBPF refinement regression smoke (SOL-2/SOL-3).

Frozen spike: do not expand in generic `SbpfExec` PRs. Kept to guard against
regressions while the contract-agnostic layer grows.
-/

namespace ProofForge.Tests.SolanaCounterSbpfRegression

open ProofForge.Backend.Solana.CounterSbpfExec
open ProofForge.Backend.Solana.CounterSbpfRefinement

#check initialize_runSteps
#check initialize_count_zero
#check increment_runSteps
#check increment_count_succ
#check get_runSteps
#check get_return_data
#check countOff_matches_layout

#check counterSbpfCore_trace_simulates_after_initialize
#check counterSbpfCore_safe_trace_simulates_after_initialize
#check counterSbpfCore_canonical_safe_trace_simulates
#check counterTraceSafe_initialize_get_increment_get

/-! ## FV-9.3 Solana cap: the structural `∀ (m : Module)` sBPF fragment-refines

The Solana-first replication of FV-9.3: `solanaSbpf_fragment_refines_all`
quantifies over every module `m` in the supported fragment, with the sBPF
core-tail as the target machine and `CounterSbpfRel` as the simulation
relation. Proved via `moduleIrStep m = irStep` (`rfl`) + the existing
`counterSbpfCore_trace_simulates_from_obligations`. -/

#check solanaSbpf_fragment_refines_all

end ProofForge.Tests.SolanaCounterSbpfRegression

def main : IO UInt32 := do
  IO.println "solana-counter-sbpf-regression: Counter exec + refinement anchors + FV-9.3 solanaSbpf_fragment_refines_all (∀ m ∈ supported fragment) checked"
  return 0