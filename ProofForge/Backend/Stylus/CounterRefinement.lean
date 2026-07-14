import ProofForge.Backend.Refinement.CounterUniversal
import ProofForge.Backend.Stylus.Semantics

namespace ProofForge.Backend.Stylus.CounterRefinement

open ProofForge.Backend.Stylus.Semantics

def related (count : Nat) (state : HostState) : Prop :=
  state.storage.find? (fun entry => entry.1 == slotZero) = some (slotZero, encodeU64 count)

theorem decode_encode_zero : decodeU64 (encodeU64 0) = 0 := by native_decide

theorem slot_zero_is_word : slotZero.size = 32 := by native_decide

def lifecycleCalls : List ProofForge.Backend.Refinement.CounterUniversal.CounterCall :=
  [.initialize, .increment, .get]

#check ProofForge.Backend.Refinement.CounterUniversal.counter_trace_simulates_after_initialize

end ProofForge.Backend.Stylus.CounterRefinement
