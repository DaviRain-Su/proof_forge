import ProofForge.Backend.WasmNear.CosmWasmHost

/-! CosmWasm host dispatch smoke (WASM-5b): `runHostCall` routes `.cosmWasm` bridge. -/

namespace ProofForge.Tests.WasmCosmWasmHost

open ProofForge.Backend.WasmNear.WasmInterpreter
open ProofForge.Backend.WasmNear.CosmWasmHost

def cosmWasmState : WasmState :=
  { host := { bridge := .cosmWasm, storage := #[] } }

theorem cosmWasmHostArity_db_read : cosmWasmHostArity "db_read" = .ok 2 := rfl

theorem hostArity_cosmWasm_db_write :
    hostArity ProofForge.Target.HostBridge.cosmWasm "db_write" = .ok 4 := rfl

theorem runCosmWasmHostCall_db_remove_id :
    runCosmWasmHostCall "db_remove" #[0, 0] cosmWasmState = .ok cosmWasmState := by
  rfl

example : True := by
  have _ := @cosmWasmHostArity_db_read
  have _ := @hostArity_cosmWasm_db_write
  have _ := @runCosmWasmHostCall_db_remove_id
  have _ := @cosmWasmHost_storage_read_after_write_same
  have _ := @hostCallStep_cosmWasm_db_write_stack_reduction
  exact True.intro

end ProofForge.Tests.WasmCosmWasmHost

def main : IO UInt32 := do
  IO.println "wasm-cosmwasm-host-smoke: CosmWasm host dispatch lemmas checked"
  return 0