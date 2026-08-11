/-
  Targets host/ZK **slow** shard (ordinary CI optional / main+dispatch).

  - CosmWasmPlanV1: large Plan/IR/WAT matrix (long wall-clock)
  - NoirAcirV1: golden + optional live nargo capture

  Default `just test-targets` / PR target-smoke use TargetsHostFast only.
  Set PROOF_FORGE_TARGET_HOST_SLOW=1 or run `just test-shard targets-host-slow`.
-/
import Tests.Materialization.CosmWasmPlanV1
import Tests.Materialization.NoirAcirV1

unsafe def main : IO Unit := do
  IO.eprintln "CP run"
  Tests.Materialization.CosmWasmPlanV1.run
  IO.eprintln "CP run"
  Tests.Materialization.NoirAcirV1.run
  IO.println "shard-targets-host-slow: ok"
