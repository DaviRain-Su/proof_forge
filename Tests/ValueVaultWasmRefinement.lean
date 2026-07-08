import ProofForge.Backend.WasmNear.ValueVaultWasmRefinement

/-! WASM-5a contract-axis smoke: ValueVault universal IR↔Wasm core refinement. -/

namespace ProofForge.Tests.ValueVaultWasmRefinement

open ProofForge.Backend.WasmNear.ValueVaultWasmRefinement
open ProofForge.Backend.WasmNear.ValueVaultWasmExec

#check valueVaultWasm_step_simulates
#check valueVaultWasm_trace_simulates
#check valueVaultWasm_canonical_full_trace_simulates
#check valueVaultWasm_canonical_tail_trace_simulates
#check valueVaultCoreTraceStep_deposit
#check valueVaultCoreTraceStep_chargeFee
#check valueVaultCoreTraceStep_release
#check valueVaultCoreTraceStep_getBalance
#check valueVaultCoreTraceStep_getNetValue
#check valueVaultTraceSafe_canonical_tail

end ProofForge.Tests.ValueVaultWasmRefinement

def main : IO UInt32 := do
  IO.println "value-vault-wasm-refinement-smoke: ValueVault Wasm contract-axis universal C-proof checked"
  return 0