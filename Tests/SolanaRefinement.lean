import ProofForge.Backend.Solana.Refinement

/-! ## Solana sBPF refinement smoke

The first Solana refinement anchor (Counter IR trace + sBPF artifact surface).
Mirrors the shape of `Tests/NearWasmFormal.lean` for the NEAR path: it
`#check`s the `native_decide`-discharged theorems and runs an entry-point that
prints which anchors were verified.
-/

namespace ProofForge.Tests.SolanaRefinement

open ProofForge.Backend.Solana.Refinement

-- Counter IR observable trace (same scenario as EVM/NEAR refinement layers).
#check counter_ir_observable_trace_ok

-- Counter sBPF artifact-surface obligation (rendered assembly surfaces every
-- entrypoint name; assembly-level execution semantics is future work).
#check counter_sbpf_artifact_surface_ok

end ProofForge.Tests.SolanaRefinement

def main : IO UInt32 := do
  IO.println "solana-refinement-smoke: Counter IR observable trace + sBPF artifact-surface obligation checked via native_decide"
  return 0
