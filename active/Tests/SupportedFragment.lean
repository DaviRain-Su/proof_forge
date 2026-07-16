import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.Solana.Refinement
import ProofForge.IR.Examples.Counter

/-! ## SupportedFragment smoke

Pins the proof-fragment boundary used by the universal Counter refinement
track: target semantics that declare the Counter fragment accept only the
canonical Counter module and reject modules outside that proved scope.
-/

namespace ProofForge.Tests.SupportedFragment

open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.CounterUniversal

def checkedCounterModule : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with overflowChecked := true }

def renamedCounterModule : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with name := "CounterRenamed" }

theorem counter_model_declares_counter_fragment :
    counterModelTargetSemantics.supportsProofFragment .counter = true := by
  native_decide

theorem solana_sbpf_declares_counter_fragment :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.supportsProofFragment
      .counter = true := by
  native_decide

theorem counter_model_supports_canonical_counter :
    counterModelTargetSemantics.supportedFragment
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem solana_sbpf_supports_canonical_counter :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.supportedFragment
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

theorem counter_model_rejects_checked_counter :
    counterModelTargetSemantics.supportedFragment checkedCounterModule = false := by
  native_decide

theorem solana_sbpf_rejects_checked_counter :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.supportedFragment
      checkedCounterModule = false := by
  native_decide

theorem counter_model_rejects_renamed_counter :
    counterModelTargetSemantics.supportedFragment renamedCounterModule = false := by
  native_decide

theorem solana_sbpf_rejects_renamed_counter :
    ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.supportedFragment
      renamedCounterModule = false := by
  native_decide

theorem require_supported_fragment_accepts_counter :
    (match counterModelTargetSemantics.requireSupportedFragment
        ProofForge.IR.Examples.Counter.module with
     | .ok _ => true
     | .error _ => false) = true := by
  native_decide

theorem require_supported_fragment_rejects_checked_counter :
    (match counterModelTargetSemantics.requireSupportedFragment checkedCounterModule with
     | .ok _ => false
     | .error _ => true) = true := by
  native_decide

theorem solana_require_supported_fragment_accepts_counter :
    (match ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.requireSupportedFragment
        ProofForge.IR.Examples.Counter.module with
     | .ok _ => true
     | .error _ => false) = true := by
  native_decide

theorem solana_require_supported_fragment_rejects_checked_counter :
    (match ProofForge.Backend.Solana.Refinement.solanaSbpfTargetSemantics.requireSupportedFragment
        checkedCounterModule with
     | .ok _ => false
     | .error _ => true) = true := by
  native_decide

end ProofForge.Tests.SupportedFragment

def main : IO UInt32 := do
  IO.println "supported-fragment-smoke: Counter proof fragment accepts canonical Counter and rejects fragment-outside modules across declaring target semantics"
  return 0
