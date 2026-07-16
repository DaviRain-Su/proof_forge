import ProofForge.Backend.WasmHost.CounterCosmWasmRefinement
import ProofForge.Backend.WasmHost.CosmWasmHost

/-! WASM-5b chain-axis smoke: Counter reuses the SAME host-agnostic
`counterWasmCoreTraceStep` on the CosmWasm host. This is the killer
chain-genericity test — the abstract core and universal induction are
unchanged from the NEAR lane; only the host instantiation differs. -/

namespace ProofForge.Tests.WasmCosmWasmRefinementSmoke

open ProofForge.Backend.WasmHost.CounterCosmWasmRefinement
open ProofForge.Backend.WasmHost.CosmWasmHost

/-- Chain-axis WASM-5b: the canonical Counter trace simulates through the
CosmWasm host using the SAME abstract core as the NEAR lane. -/
theorem chain_axis_canonical_closed :
    ∃ finalIr finalCore observables,
      ProofForge.IR.StepSemantics.runTraceListGen
          (ProofForge.Backend.Refinement.CounterUniversal.irStep)
          (.initialize :: [.get, .increment, .get])
          ProofForge.IR.Semantics.State.empty =
        .ok (finalIr, observables) ∧
      ProofForge.IR.StepSemantics.runTraceListGen
          counterWasmCoreTraceStep
          (.initialize :: [.get, .increment, .get])
          { storage := #[], returnValue := #[] } =
        .ok (finalCore, observables) ∧
      CounterWasmRel finalIr finalCore :=
  counterCosmWasm_canonical_safe_trace_simulates

end ProofForge.Tests.WasmCosmWasmRefinementSmoke

def main : IO UInt32 := do
  IO.println "wasm-cosmwasm-refinement-smoke: Counter on CosmWasm host (chain-axis WASM-5b) checked"
  return 0